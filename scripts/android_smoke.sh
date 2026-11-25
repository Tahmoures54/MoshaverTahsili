#!/usr/bin/env bash
set -Eeuo pipefail

# Simorgh Android emulator smoke and integration tests.
#
# The x86_64 debug APK is disposable and MUST NOT be published.
# Release builds and signature verification are outside this script.
#
# Required:
#   - Bash
#   - Flutter SDK
#   - Android SDK platform tools (adb)
#   - GNU timeout, or gtimeout on macOS
#   - A running x86_64 Android emulator
#   - integration_test/app_test.dart
#   - integration_test/secure_storage_test.dart
#
# IMPORTANT:
#   - The initial uninstall deletes this package's emulator data.
#   - Use a dedicated test emulator.
#   - Integration tests can replace the installed application and
#     overwrite Flutter's app-debug.apk output.
#   - This script preserves the original smoke APK and reinstalls it
#     before the final launch.
#   - Android crash-buffer inspection is device-wide.
#   - A live process and clean crash buffer do not prove that Flutter
#     rendered the expected UI. Integration tests must assert that.
#
# Optional environment variables:
#   ANDROID_SERIAL
#   BUILD_TIMEOUT_SECONDS       (default: 1800)
#   TEST_TIMEOUT_SECONDS        (default: 1800 per suite)
#   BOOT_TIMEOUT_SECONDS        (default: 120)
#   INSTALL_TIMEOUT_SECONDS     (default: 180)
#   ADB_TIMEOUT_SECONDS         (default: 30)
#   PROCESS_START_SECONDS       (default: 30)
#   PROCESS_STABILITY_SECONDS   (default: 5)

PACKAGE_NAME="ir.moshaver.tahsili.debug"
# The debug variant adds an applicationId suffix, while the Kotlin
# Activity class remains in the stable Gradle namespace.
ACTIVITY_NAME="ir.moshaver.tahsili.MainActivity"

BUILD_TIMEOUT_SECONDS="${BUILD_TIMEOUT_SECONDS:-1800}"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-1800}"
BOOT_TIMEOUT_SECONDS="${BOOT_TIMEOUT_SECONDS:-120}"
INSTALL_TIMEOUT_SECONDS="${INSTALL_TIMEOUT_SECONDS:-180}"
ADB_TIMEOUT_SECONDS="${ADB_TIMEOUT_SECONDS:-30}"
PROCESS_START_SECONDS="${PROCESS_START_SECONDS:-30}"
PROCESS_STABILITY_SECONDS="${PROCESS_STABILITY_SECONDS:-5}"

# Resolve paths relative to the repository, not the caller's directory.
SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)"
PROJECT_ROOT="$(
  cd -- "$SCRIPT_DIR/.." && pwd
)"
cd -- "$PROJECT_ROOT"

REPORT_DIR="build/reports/device"
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
SMOKE_APK="$REPORT_DIR/smoke-app-debug.apk"

mkdir -p -- "$REPORT_DIR"

RESULT_FILE="$REPORT_DIR/result.txt"
SUMMARY_FILE="$REPORT_DIR/summary.txt"
INSTALL_LOG="$REPORT_DIR/install.txt"
LAUNCH_LOG="$REPORT_DIR/launch.txt"
APP_TEST_LOG="$REPORT_DIR/app-integration.txt"
SECURE_TEST_LOG="$REPORT_DIR/secure-storage-integration.txt"
SCREENSHOT="$REPORT_DIR/launch.png"
FINAL_SCREENSHOT="$REPORT_DIR/final-launch.png"

DEVICE_ID=""
TIMEOUT_BIN=""
CURRENT_STEP="Initialization"
CURRENT_STATUS_VAR=""
FAILED_STEP=""
EXIT_CODE=0
START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

ENV_STATUS="NOT_RUN"
DEVICE_STATUS="NOT_RUN"
BUILD_STATUS="NOT_RUN"
INSTALL_STATUS="NOT_RUN"
LAUNCH_STATUS="NOT_RUN"
PROCESS_STATUS="NOT_RUN"
SCREENSHOT_STATUS="NOT_RUN"
CRASH_STATUS="NOT_RUN"
APP_TEST_STATUS="NOT_RUN"
APP_CRASH_STATUS="NOT_RUN"
SECURE_TEST_STATUS="NOT_RUN"
SECURE_CRASH_STATUS="NOT_RUN"
FINAL_STATUS="NOT_RUN"

log() {
  printf '[%s] %s\n' "$(date -u +"%H:%M:%S")" "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required command not found: $1"
  fi
}

begin_step() {
  CURRENT_STEP="$1"
  CURRENT_STATUS_VAR="$2"
  printf -v "$CURRENT_STATUS_VAR" '%s' "RUNNING"
  log "$CURRENT_STEP"
}

complete_step() {
  printf -v "$CURRENT_STATUS_VAR" '%s' "PASSED"
}

validate_positive_integer() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    fail "$name must be a positive integer; received: $value"
  fi
}

timed() {
  local seconds="$1"
  shift

  "$TIMEOUT_BIN" \
    --kill-after=15s \
    "${seconds}s" \
    "$@"
}

adb_device() {
  timed "$ADB_TIMEOUT_SECONDS" adb -s "$DEVICE_ID" "$@"
}

get_app_pid() {
  local output

  output="$(
    adb_device shell pidof "$PACKAGE_NAME" 2>/dev/null
  )" || return 1

  output="${output//$'\r'/}"

  [[ "$output" =~ ^[0-9]+([[:space:]][0-9]+)*$ ]] || return 1

  printf '%s\n' "$output"
}

verify_stable_process() {
  local label="$1"
  local pid=""
  local current_pid=""
  local attempt
  local sample
  local pid_log="$REPORT_DIR/${label}-process.txt"

  : > "$pid_log"

  for ((attempt = 1; attempt <= PROCESS_START_SECONDS; attempt++)); do
    pid="$(get_app_pid || true)"

    if [[ -n "$pid" ]]; then
      break
    fi

    sleep 1
  done

  if [[ -z "$pid" ]]; then
    fail "Application process did not appear during $label verification."
    return 1
  fi

  printf 'Initial PID(s): %s\n' "$pid" >> "$pid_log"

  for ((sample = 1; sample <= PROCESS_STABILITY_SECONDS; sample++)); do
    sleep 1

    current_pid="$(get_app_pid || true)"

    printf 'Sample %s: %s\n' \
      "$sample" "${current_pid:-NOT_RUNNING}" >> "$pid_log"

    if [[ -z "$current_pid" ]]; then
      fail "Application process exited during $label verification."
      return 1
    fi

    if [[ "$current_pid" != "$pid" ]]; then
      fail "Application PID changed during $label verification."
      return 1
    fi
  done

  log "Application process remained alive. PID(s): $pid"
}

capture_screenshot() {
  local output="$1"

  adb_device exec-out screencap -p > "$output"

  if [[ ! -s "$output" ]]; then
    fail "Screenshot capture produced an empty file: $output"
  fi
}

check_crashes() {
  local label="$1"
  local crash_file="$REPORT_DIR/crash-${label}.txt"

  adb_device logcat -d -b crash -v threadtime \
    > "$crash_file" 2>&1

  # Save the main/system log as well. Dart/Flutter errors do not
  # necessarily appear in Android's crash buffer.
  adb_device logcat -d -v threadtime \
    > "$REPORT_DIR/logcat-${label}.txt" 2>&1

  if grep -Eiq \
    'FATAL EXCEPTION|Fatal signal [0-9]+|Fatal error in native method' \
    "$crash_file"; then
    fail "Fatal Android crash found at checkpoint: $label. See $crash_file"
  fi
}

collect_diagnostics() {
  # Called with errexit disabled. All operations are best effort
  # and individually bounded.
  [[ -n "$DEVICE_ID" && -n "$TIMEOUT_BIN" ]] || return 0
  command -v adb >/dev/null 2>&1 || return 0

  if ! adb_device get-state >/dev/null 2>&1; then
    return 0
  fi

  adb_device logcat -d -b crash -v threadtime \
    > "$REPORT_DIR/crash-log.txt" 2>&1 || true

  adb_device logcat -d -v threadtime \
    > "$REPORT_DIR/logcat.txt" 2>&1 || true

  adb_device shell dumpsys activity activities \
    > "$REPORT_DIR/activities.txt" 2>&1 || true

  adb_device shell dumpsys meminfo "$PACKAGE_NAME" \
    > "$REPORT_DIR/memory.txt" 2>&1 || true

  adb_device shell dumpsys package "$PACKAGE_NAME" \
    > "$REPORT_DIR/package.txt" 2>&1 || true
}

write_summary() {
  {
    echo "Simorgh Android emulator smoke test"
    echo "Started: $START_TIME"
    echo "Finished: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    echo "Device: ${DEVICE_ID:-NOT_SELECTED}"
    echo "Package: $PACKAGE_NAME"
    echo "Preserved smoke APK: $SMOKE_APK"
    echo
    echo "Environment: $ENV_STATUS"
    echo "Emulator selection and boot: $DEVICE_STATUS"
    echo "Debug APK build: $BUILD_STATUS"
    echo "Initial installation: $INSTALL_STATUS"
    echo "Initial launch: $LAUNCH_STATUS"
    echo "Initial process stability: $PROCESS_STATUS"
    echo "Initial screenshot: $SCREENSHOT_STATUS"
    echo "Initial Android crash check: $CRASH_STATUS"
    echo "App integration: $APP_TEST_STATUS"
    echo "Post-app-test Android crash check: $APP_CRASH_STATUS"
    echo "Secure storage integration: $SECURE_TEST_STATUS"
    echo "Post-storage-test Android crash check: $SECURE_CRASH_STATUS"
    echo "Original APK reinstall and final verification: $FINAL_STATUS"
    echo
    echo "Exit code: $EXIT_CODE"

    if [[ "$EXIT_CODE" -eq 0 ]]; then
      echo "Overall result: PASSED"
    else
      echo "Failed step: ${FAILED_STEP:-UNKNOWN}"
      echo "Overall result: FAILED"
    fi

    echo
    echo "Crash inspection scope: ENTIRE_EMULATOR"
    echo "Flutter UI correctness: ASSERTED_ONLY_BY_INTEGRATION_TESTS"
    echo "Physical-device tests: NOT_PERFORMED"
    echo "Bazaar payment tests: NOT_PERFORMED"
    echo "Release APK: NOT_CHECKED_BY_THIS_SCRIPT"
    echo "Debug APK publication: PROHIBITED"
  } > "$SUMMARY_FILE"
}

on_exit() {
  local original_exit_code=$?

  trap - EXIT
  trap '' INT TERM
  set +e
  set +u
  set +o pipefail

  EXIT_CODE="$original_exit_code"

  if [[ "$EXIT_CODE" -ne 0 ]]; then
    FAILED_STEP="$CURRENT_STEP"

    if [[ -n "$CURRENT_STATUS_VAR" ]]; then
      printf -v "$CURRENT_STATUS_VAR" '%s' "FAILED"
    fi
  fi

  collect_diagnostics
  write_summary

  if [[ "$EXIT_CODE" -eq 0 ]]; then
    {
      echo "Android emulator smoke test PASSED."
      echo "The disposable x86_64 debug APK was built and preserved."
      echo "Initial installation, launch and process stability passed."
      echo "Both integration test commands completed successfully."
      echo "The original smoke APK was reinstalled and relaunched."
      echo "No fatal Android crash matched the inspected checkpoints."
      echo "See integration logs for tested UI and storage assertions."
      echo "Release, physical-device and Bazaar tests were not performed."
    } | tee "$RESULT_FILE"
  else
    {
      echo "Android emulator smoke test FAILED."
      echo "Failed step: ${FAILED_STEP:-UNKNOWN}"
      echo "Exit code: $EXIT_CODE"
      echo "See summary.txt and individual logs for details."
    } | tee "$RESULT_FILE"
  fi

  log "Test report: $PROJECT_ROOT/$REPORT_DIR"

  exit "$original_exit_code"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ------------------------------------------------------------
# 1. Environment validation
# ------------------------------------------------------------

begin_step "Environment validation" ENV_STATUS

require_command flutter
require_command adb
require_command grep
require_command awk
require_command tr
require_command tee
require_command date
require_command cp
require_command rm
require_command sleep

if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  fail "GNU timeout is required. On macOS install coreutils for gtimeout."
fi

# Confirm the selected timeout implementation supports GNU options.
timed 5 bash -c 'exit 0'

validate_positive_integer BUILD_TIMEOUT_SECONDS "$BUILD_TIMEOUT_SECONDS"
validate_positive_integer TEST_TIMEOUT_SECONDS "$TEST_TIMEOUT_SECONDS"
validate_positive_integer BOOT_TIMEOUT_SECONDS "$BOOT_TIMEOUT_SECONDS"
validate_positive_integer INSTALL_TIMEOUT_SECONDS "$INSTALL_TIMEOUT_SECONDS"
validate_positive_integer ADB_TIMEOUT_SECONDS "$ADB_TIMEOUT_SECONDS"
validate_positive_integer PROCESS_START_SECONDS "$PROCESS_START_SECONDS"
validate_positive_integer PROCESS_STABILITY_SECONDS "$PROCESS_STABILITY_SECONDS"

[[ -f "pubspec.yaml" ]] \
  || fail "pubspec.yaml was not found in the project root."

[[ -f "lib/main.dart" ]] \
  || fail "lib/main.dart was not found."

[[ -f "integration_test/app_test.dart" ]] \
  || fail "integration_test/app_test.dart was not found."

[[ -f "integration_test/secure_storage_test.dart" ]] \
  || fail "integration_test/secure_storage_test.dart was not found."

# Remove stale artifacts produced by this script.
# Other files in REPORT_DIR are left untouched.
rm -f -- \
  "$RESULT_FILE" \
  "$SUMMARY_FILE" \
  "$SMOKE_APK" \
  "$SCREENSHOT" \
  "$FINAL_SCREENSHOT" \
  "$INSTALL_LOG" \
  "$LAUNCH_LOG" \
  "$APP_TEST_LOG" \
  "$SECURE_TEST_LOG" \
  "$REPORT_DIR/build.txt" \
  "$REPORT_DIR/devices.txt" \
  "$REPORT_DIR/device-properties.txt" \
  "$REPORT_DIR/uninstall.txt" \
  "$REPORT_DIR/boot.txt" \
  "$REPORT_DIR/final-install.txt" \
  "$REPORT_DIR/final-launch.txt" \
  "$REPORT_DIR/crash-log.txt" \
  "$REPORT_DIR/logcat.txt" \
  "$REPORT_DIR/activities.txt" \
  "$REPORT_DIR/memory.txt" \
  "$REPORT_DIR/package.txt" \
  "$REPORT_DIR/initial-process.txt" \
  "$REPORT_DIR/final-process.txt" \
  "$REPORT_DIR/crash-initial.txt" \
  "$REPORT_DIR/crash-after-app-test.txt" \
  "$REPORT_DIR/crash-after-storage-test.txt" \
  "$REPORT_DIR/crash-final.txt" \
  "$REPORT_DIR/logcat-initial.txt" \
  "$REPORT_DIR/logcat-after-app-test.txt" \
  "$REPORT_DIR/logcat-after-storage-test.txt" \
  "$REPORT_DIR/logcat-final.txt"

timed 120 flutter --version \
  > "$REPORT_DIR/flutter-version.txt" 2>&1

timed "$ADB_TIMEOUT_SECONDS" adb version \
  > "$REPORT_DIR/adb-version.txt" 2>&1

complete_step

# ------------------------------------------------------------
# 2. Select and validate a running x86_64 emulator
# ------------------------------------------------------------

begin_step "Emulator selection and boot verification" DEVICE_STATUS

timed "$ADB_TIMEOUT_SECONDS" adb start-server >/dev/null

timed "$ADB_TIMEOUT_SECONDS" adb devices -l \
  | tee "$REPORT_DIR/devices.txt"

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  DEVICE_ID="$ANDROID_SERIAL"
else
  DEVICE_ID="$(
    timed "$ADB_TIMEOUT_SECONDS" adb devices | awk '
      NR > 1 && $1 ~ /^emulator-/ && $2 == "device" {
        print $1
        exit
      }
    '
  )"
fi

[[ -n "$DEVICE_ID" ]] \
  || fail "No ready Android emulator found."

adb_device get-state 2>/dev/null | grep -qx "device" \
  || fail "Selected device is not ready: $DEVICE_ID"

IS_EMULATOR="$(
  adb_device shell getprop ro.kernel.qemu | tr -d '\r'
)"

[[ "$IS_EMULATOR" == "1" ]] \
  || fail "Selected device is not an Android emulator."

log "Selected emulator: $DEVICE_ID"

BOOT_COMPLETED=""
BOOT_DEADLINE=$((SECONDS + BOOT_TIMEOUT_SECONDS))

: > "$REPORT_DIR/boot.txt"

while ((SECONDS < BOOT_DEADLINE)); do
  BOOT_COMPLETED="$(
    adb_device shell getprop sys.boot_completed \
      2>/dev/null | tr -d '\r' || true
  )"

  printf 'sys.boot_completed=%s\n' \
    "${BOOT_COMPLETED:-EMPTY}" >> "$REPORT_DIR/boot.txt"

  if [[ "$BOOT_COMPLETED" == "1" ]]; then
    break
  fi

  sleep 1
done

[[ "$BOOT_COMPLETED" == "1" ]] \
  || fail "Android emulator did not finish booting within the allowed time."

DEVICE_ABI="$(
  adb_device shell getprop ro.product.cpu.abi | tr -d '\r'
)"

DEVICE_ABILIST="$(
  adb_device shell getprop ro.product.cpu.abilist | tr -d '\r'
)"

{
  echo "Serial: $DEVICE_ID"
  echo "Emulator: $IS_EMULATOR"
  echo "Primary ABI: $DEVICE_ABI"
  echo "Supported ABIs: $DEVICE_ABILIST"
} > "$REPORT_DIR/device-properties.txt"

[[ "$DEVICE_ABI" == "x86_64" ]] \
  || fail "This script requires an x86_64 emulator; primary ABI is $DEVICE_ABI."

complete_step

# ------------------------------------------------------------
# 3. Build and preserve the original smoke APK
# ------------------------------------------------------------

begin_step "Disposable x86_64 debug APK build" BUILD_STATUS

timed "$BUILD_TIMEOUT_SECONDS" flutter build apk \
  --debug \
  --target lib/main.dart \
  --target-platform android-x64 \
  2>&1 | tee "$REPORT_DIR/build.txt"

[[ -s "$APK_PATH" ]] \
  || fail "Debug APK was not generated: $APK_PATH"

# Integration builds may overwrite APK_PATH.
cp -- "$APK_PATH" "$SMOKE_APK"

[[ -s "$SMOKE_APK" ]] \
  || fail "Failed to preserve the original smoke APK."

log "Preserved smoke APK: $SMOKE_APK"

complete_step

# ------------------------------------------------------------
# 4. Install the original application
# ------------------------------------------------------------

begin_step "Initial application installation" INSTALL_STATUS

log "Removing previous installation; emulator app data will be deleted."

timed "$INSTALL_TIMEOUT_SECONDS" adb -s "$DEVICE_ID" \
  uninstall "$PACKAGE_NAME" \
  > "$REPORT_DIR/uninstall.txt" 2>&1 || true

timed "$INSTALL_TIMEOUT_SECONDS" adb -s "$DEVICE_ID" \
  install "$SMOKE_APK" \
  2>&1 | tee "$INSTALL_LOG"

grep -Eq '^[[:space:]]*Success[[:space:]]*$' "$INSTALL_LOG" \
  || fail "APK installation did not report Success."

complete_step

# ------------------------------------------------------------
# 5. Launch the original application
# ------------------------------------------------------------

begin_step "Initial application launch" LAUNCH_STATUS

adb_device shell am force-stop "$PACKAGE_NAME"

# Clear all available log buffers before the first measured launch.
adb_device logcat -b all -c

adb_device shell am start -W \
  -n "$PACKAGE_NAME/$ACTIVITY_NAME" \
  2>&1 | tee "$LAUNCH_LOG"

grep -Eq '^[[:space:]]*Status:[[:space:]]*ok[[:space:]]*$' \
  "$LAUNCH_LOG" \
  || fail "Activity launch did not return Status: ok."

complete_step

# ------------------------------------------------------------
# 6. Verify initial process stability
# ------------------------------------------------------------

begin_step "Initial application process stability" PROCESS_STATUS

verify_stable_process initial

complete_step

# ------------------------------------------------------------
# 7. Capture initial screenshot
# ------------------------------------------------------------

begin_step "Initial screenshot capture" SCREENSHOT_STATUS

capture_screenshot "$SCREENSHOT"

complete_step

# ------------------------------------------------------------
# 8. Inspect initial Android crash logs
# ------------------------------------------------------------

begin_step "Initial Android crash inspection" CRASH_STATUS

check_crashes initial

complete_step

# ------------------------------------------------------------
# 9. Run application integration tests
# ------------------------------------------------------------

begin_step "Application integration tests" APP_TEST_STATUS

timed "$TEST_TIMEOUT_SECONDS" flutter test \
  integration_test/app_test.dart \
  -d "$DEVICE_ID" \
  --reporter expanded \
  2>&1 | tee "$APP_TEST_LOG"

complete_step

begin_step "Android crash inspection after app tests" APP_CRASH_STATUS

check_crashes after-app-test

complete_step

# ------------------------------------------------------------
# 10. Run secure storage integration tests
# ------------------------------------------------------------

begin_step "Secure storage integration tests" SECURE_TEST_STATUS

timed "$TEST_TIMEOUT_SECONDS" flutter test \
  integration_test/secure_storage_test.dart \
  -d "$DEVICE_ID" \
  --reporter expanded \
  2>&1 | tee "$SECURE_TEST_LOG"

complete_step

begin_step \
  "Android crash inspection after storage tests" \
  SECURE_CRASH_STATUS

check_crashes after-storage-test

complete_step

# ------------------------------------------------------------
# 11. Restore and verify the ORIGINAL application
# ------------------------------------------------------------

begin_step \
  "Original APK reinstall and final application verification" \
  FINAL_STATUS

[[ -s "$SMOKE_APK" ]] \
  || fail "Preserved smoke APK is missing."

log "Reinstalling the original lib/main.dart smoke APK."

# Keep existing test data. Do not silently uninstall if replacement
# fails; installation/signature errors should fail this stage.
timed "$INSTALL_TIMEOUT_SECONDS" adb -s "$DEVICE_ID" \
  install -r "$SMOKE_APK" \
  2>&1 | tee "$REPORT_DIR/final-install.txt"

grep -Eq '^[[:space:]]*Success[[:space:]]*$' \
  "$REPORT_DIR/final-install.txt" \
  || fail "Original smoke APK reinstall did not report Success."

adb_device shell am force-stop "$PACKAGE_NAME"

# Earlier crash checkpoints have already been saved.
# Isolate the final launch logs from test-runner activity.
adb_device logcat -b all -c

adb_device shell am start -W \
  -n "$PACKAGE_NAME/$ACTIVITY_NAME" \
  2>&1 | tee "$REPORT_DIR/final-launch.txt"

grep -Eq '^[[:space:]]*Status:[[:space:]]*ok[[:space:]]*$' \
  "$REPORT_DIR/final-launch.txt" \
  || fail "Original application relaunch did not return Status: ok."

verify_stable_process final

capture_screenshot "$FINAL_SCREENSHOT"

check_crashes final

complete_step

CURRENT_STEP="Completed"
CURRENT_STATUS_VAR=""

log "All Android emulator checks completed successfully."

exit 0
