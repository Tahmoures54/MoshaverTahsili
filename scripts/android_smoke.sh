
#!/usr/bin/env bash
set -Eeuo pipefail

# Simorgh Android emulator smoke and integration tests.
#
# The x86_64 debug APK is disposable and is NEVER published.
# The release APK must be built and signature-verified separately.
#
# Required:
#   - Flutter SDK
#   - Android SDK platform tools (adb)
#   - A running Android emulator
#   - integration_test/app_test.dart
#   - integration_test/secure_storage_test.dart

PACKAGE_NAME="ir.moshaver.tahsili.debug"
ACTIVITY_NAME="ir.moshaver.tahsili.MainActivity"

REPORT_DIR="build/reports/device"
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"

mkdir -p "$REPORT_DIR"

RESULT_FILE="$REPORT_DIR/result.txt"
INSTALL_LOG="$REPORT_DIR/install.txt"
LAUNCH_LOG="$REPORT_DIR/launch.txt"
CRASH_LOG="$REPORT_DIR/crash-log.txt"
APP_TEST_LOG="$REPORT_DIR/app-integration.txt"
SECURE_TEST_LOG="$REPORT_DIR/secure-storage-integration.txt"
SCREENSHOT="$REPORT_DIR/launch.png"
SUMMARY_FILE="$REPORT_DIR/summary.txt"

DEVICE_ID=""
CURRENT_STEP="Initialization"
START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
FAILED_STEP=""
EXIT_CODE=0

# Track completed stages.
BUILD_STATUS="NOT_RUN"
INSTALL_STATUS="NOT_RUN"
LAUNCH_STATUS="NOT_RUN"
PROCESS_STATUS="NOT_RUN"
CRASH_STATUS="NOT_RUN"
APP_TEST_STATUS="NOT_RUN"
SECURE_TEST_STATUS="NOT_RUN"

log() {
  printf '[%s] %s\n' "$(date -u +"%H:%M:%S")" "$*"
}

fail() {
  log "ERROR: $*"
  return 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    fail "Required command not found: $1"
    return 1
  }
}

# Collect diagnostic information even if a step fails.
collect_diagnostics() {
  if [[ -n "$DEVICE_ID" ]] && adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
    adb -s "$DEVICE_ID" logcat -d -b crash \
      > "$CRASH_LOG" 2>&1 || true

    adb -s "$DEVICE_ID" shell dumpsys activity activities \
      > "$REPORT_DIR/activities.txt" 2>&1 || true

    adb -s "$DEVICE_ID" shell dumpsys meminfo "$PACKAGE_NAME" \
      > "$REPORT_DIR/memory.txt" 2>&1 || true
  fi
}

write_summary() {
  {
    echo "Simorgh Android device smoke test"
    echo "Started: $START_TIME"
    echo "Finished: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    echo "Device: ${DEVICE_ID:-NOT_SELECTED}"
    echo "Package: $PACKAGE_NAME"
    echo
    echo "Build: $BUILD_STATUS"
    echo "Install: $INSTALL_STATUS"
    echo "Launch: $LAUNCH_STATUS"
    echo "Process alive: $PROCESS_STATUS"
    echo "Crash check: $CRASH_STATUS"
    echo "App integration: $APP_TEST_STATUS"
    echo "Secure storage integration: $SECURE_TEST_STATUS"
    echo

    if [[ -n "$FAILED_STEP" ]]; then
      echo "Failed step: $FAILED_STEP"
      echo "Exit code: $EXIT_CODE"
      echo "Overall result: FAILED"
    else
      echo "Overall result: PASSED"
    fi

    echo
    echo "Physical-device tests: NOT_PERFORMED"
    echo "Bazaar payment tests: NOT_PERFORMED"
    echo "Release APK: BUILT_AND_VERIFIED_SEPARATELY"
  } > "$SUMMARY_FILE"
}

on_exit() {
  EXIT_CODE=$?

  if [[ "$EXIT_CODE" -ne 0 && -z "$FAILED_STEP" ]]; then
    FAILED_STEP="$CURRENT_STEP"
  fi

  collect_diagnostics
  write_summary

  if [[ "$EXIT_CODE" -eq 0 ]]; then
    {
      echo "Disposable x86_64 debug APK successfully built, installed and launched."
      echo "Application process remained alive."
      echo "No fatal Android exception was detected in the collected crash log."
      echo "Both integration test suites passed."
      echo "Release APK is handled separately."
      echo "Physical-device and Bazaar payment tests remain manual."
    } | tee "$RESULT_FILE"
  else
    {
      echo "Android device smoke test FAILED."
      echo "Failed step: ${FAILED_STEP:-UNKNOWN}"
      echo "Exit code: $EXIT_CODE"
      echo "See summary.txt and individual logs for details."
    } | tee "$RESULT_FILE"
  fi

  log "Test report: $REPORT_DIR"
}

trap on_exit EXIT

# ------------------------------------------------------------
# 1. Verify environment
# ------------------------------------------------------------

CURRENT_STEP="Environment validation"
log "Checking required tools..."

require_command flutter
require_command adb
require_command grep
require_command awk
require_command tee
require_command date

flutter --version > "$REPORT_DIR/flutter-version.txt" 2>&1
adb version > "$REPORT_DIR/adb-version.txt" 2>&1

# ------------------------------------------------------------
# 2. Build disposable x86_64 debug APK
# ------------------------------------------------------------

CURRENT_STEP="Debug APK build"
log "Building disposable Android x86_64 debug APK..."

flutter build apk \
  --debug \
  --target-platform android-x64 \
  2>&1 | tee "$REPORT_DIR/build.txt"

test -s "$APK_PATH" || fail "Debug APK was not generated."

BUILD_STATUS="PASSED"

log "Debug APK created: $APK_PATH"

# ------------------------------------------------------------
# 3. Select a running emulator
# ------------------------------------------------------------

CURRENT_STEP="Emulator selection"
log "Searching for a ready Android emulator..."

adb start-server >/dev/null

adb devices -l | tee "$REPORT_DIR/devices.txt"

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  DEVICE_ID="$ANDROID_SERIAL"

  adb -s "$DEVICE_ID" get-state 2>/dev/null \
    | grep -qx "device" \
    || fail "ANDROID_SERIAL does not identify a ready device."

  IS_EMULATOR="$(adb -s "$DEVICE_ID" shell getprop ro.kernel.qemu \
    | tr -d '\r')"

  [[ "$IS_EMULATOR" == "1" ]] \
    || fail "Selected device is not an Android emulator."
else
  DEVICE_ID="$(
    adb devices | awk '
      NR > 1 && $1 ~ /^emulator-/ && $2 == "device" {
        print $1
        exit
      }
    '
  )"

  [[ -n "$DEVICE_ID" ]] \
    || fail "No ready Android emulator found."
fi

log "Selected emulator: $DEVICE_ID"

adb -s "$DEVICE_ID" wait-for-device

# Wait until Android has completed booting.
BOOT_COMPLETED=""

for attempt in $(seq 1 60); do
  BOOT_COMPLETED="$(
    adb -s "$DEVICE_ID" shell getprop sys.boot_completed \
      2>/dev/null | tr -d '\r'
  )"

  [[ "$BOOT_COMPLETED" == "1" ]] && break
  sleep 1
done

[[ "$BOOT_COMPLETED" == "1" ]] \
  || fail "Android emulator did not finish booting."

# ------------------------------------------------------------
# 4. Install application
# ------------------------------------------------------------

CURRENT_STEP="Application installation"
log "Removing previous installation if present..."

adb -s "$DEVICE_ID" uninstall "$PACKAGE_NAME" \
  > "$REPORT_DIR/uninstall.txt" 2>&1 || true

log "Installing debug APK..."

adb -s "$DEVICE_ID" install "$APK_PATH" \
  2>&1 | tee "$INSTALL_LOG"

grep -q "Success" "$INSTALL_LOG" \
  || fail "APK installation was not successful."

INSTALL_STATUS="PASSED"

# ------------------------------------------------------------
# 5. Launch application
# ------------------------------------------------------------

CURRENT_STEP="Application launch"
log "Clearing old Android crash logs..."

adb -s "$DEVICE_ID" logcat -c

adb -s "$DEVICE_ID" shell am force-stop "$PACKAGE_NAME" \
  >/dev/null 2>&1 || true

log "Starting MainActivity..."

adb -s "$DEVICE_ID" shell am start -W \
  -n "$PACKAGE_NAME/$ACTIVITY_NAME" \
  2>&1 | tee "$LAUNCH_LOG"

grep -q "Status: ok" "$LAUNCH_LOG" \
  || fail "Android Activity launch did not return Status: ok."

LAUNCH_STATUS="PASSED"

# ------------------------------------------------------------
# 6. Verify application process
# ------------------------------------------------------------

CURRENT_STEP="Application process verification"
log "Checking that the application process remains alive..."

APP_PID=""

for attempt in $(seq 1 30); do
  APP_PID="$(
    adb -s "$DEVICE_ID" shell pidof "$PACKAGE_NAME" \
      2>/dev/null | tr -d '\r' || true
  )"

  [[ -n "$APP_PID" ]] && break
  sleep 1
done

if [[ -z "$APP_PID" ]]; then
  fail "Application process did not remain alive after launch."
fi

PROCESS_STATUS="PASSED"

log "Application process is alive. PID: $APP_PID"

sleep 3

# ------------------------------------------------------------
# 7. Capture screenshot and inspect crashes
# ------------------------------------------------------------

CURRENT_STEP="Initial crash inspection"
log "Capturing application screenshot..."

adb -s "$DEVICE_ID" exec-out screencap -p > "$SCREENSHOT"

test -s "$SCREENSHOT" \
  || fail "Screenshot capture failed."

adb -s "$DEVICE_ID" logcat -d -b crash \
  > "$CRASH_LOG" 2>&1

if grep -Eiq \
  'FATAL EXCEPTION|Fatal signal [0-9]+|Fatal error in native method' \
  "$CRASH_LOG"; then
  fail "Fatal Android crash detected after application launch."
fi

CRASH_STATUS="PASSED"

# ------------------------------------------------------------
# 8. Run application integration tests
# ------------------------------------------------------------

CURRENT_STEP="Application integration tests"
log "Running application integration tests..."

flutter test integration_test/app_test.dart \
  -d "$DEVICE_ID" \
  --reporter expanded \
  2>&1 | tee "$APP_TEST_LOG"

APP_TEST_STATUS="PASSED"

# ------------------------------------------------------------
# 9. Run secure storage integration tests
# ------------------------------------------------------------

CURRENT_STEP="Secure storage integration tests"
log "Running secure storage integration tests..."

flutter test integration_test/secure_storage_test.dart \
  -d "$DEVICE_ID" \
  --reporter expanded \
  2>&1 | tee "$SECURE_TEST_LOG"

SECURE_TEST_STATUS="PASSED"

# ------------------------------------------------------------
# 10. Restore the app package after Flutter integration runner
# ------------------------------------------------------------

CURRENT_STEP="Restore application package after integration tests"
log "Restoring the standalone debug APK after Flutter's instrumentation runner..."

# flutter test integration_test builds and installs a separate instrumentation
# target and may remove/replace the standalone app package during teardown.
# Reinstall the exact APK whose initial launch was already verified.
adb -s "$DEVICE_ID" install -r "$APK_PATH" \
  2>&1 | tee "$REPORT_DIR/reinstall-after-tests.txt"

grep -q "Success" "$REPORT_DIR/reinstall-after-tests.txt" \
  || fail "Standalone application APK could not be restored after integration tests."

# ------------------------------------------------------------
# 11. Final application process and crash verification
# ------------------------------------------------------------

CURRENT_STEP="Final application verification"
log "Performing final Android diagnostics..."

adb -s "$DEVICE_ID" logcat -d -b crash \
  > "$CRASH_LOG" 2>&1

if grep -Eiq \
  'FATAL EXCEPTION|Fatal signal [0-9]+|Fatal error in native method' \
  "$CRASH_LOG"; then
  fail "Fatal Android crash detected during integration tests."
fi

# The test runner may have stopped the app. Relaunch it before
# checking that the actual application process remains alive.
adb -s "$DEVICE_ID" shell am force-stop "$PACKAGE_NAME" \
  >/dev/null 2>&1 || true

adb -s "$DEVICE_ID" shell am start -W \
  -n "$PACKAGE_NAME/$ACTIVITY_NAME" \
  > "$REPORT_DIR/final-launch.txt" 2>&1

grep -q "Status: ok" "$REPORT_DIR/final-launch.txt" \
  || fail "Application could not be relaunched after integration tests."

sleep 3

FINAL_PID="$(
  adb -s "$DEVICE_ID" shell pidof "$PACKAGE_NAME" \
    2>/dev/null | tr -d '\r' || true
)"

[[ -n "$FINAL_PID" ]] \
  || fail "Application process is not alive after integration tests."

adb -s "$DEVICE_ID" logcat -d -b crash \
  > "$CRASH_LOG" 2>&1

if grep -Eiq \
  'FATAL EXCEPTION|Fatal signal [0-9]+|Fatal error in native method' \
  "$CRASH_LOG"; then
  fail "Fatal Android crash detected during final verification."
fi

log "All Android emulator checks completed successfully."

exit 0
