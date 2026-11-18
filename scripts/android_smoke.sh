#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/reports/device
report_dir="build/reports/device"
# The release deliverable is arm64-only. Build a disposable x86_64 debug
# APK for the hosted emulator; it is never uploaded or published.
flutter build apk --debug --target-platform android-x64
apk="build/app/outputs/flutter-apk/app-debug.apk"
test -s "$apk"

adb wait-for-device
adb uninstall ir.moshaver.tahsili >/dev/null 2>&1 || true
adb install "$apk" | tee "$report_dir/install.txt"
grep -q 'Success' "$report_dir/install.txt"

adb logcat -c
adb shell am force-stop ir.moshaver.tahsili >/dev/null 2>&1 || true
adb shell am start -W -n ir.moshaver.tahsili/.MainActivity | tee "$report_dir/launch.txt"
grep -q 'Status: ok' "$report_dir/launch.txt"

pid=""
for attempt in $(seq 1 20); do
  pid="$(adb shell pidof ir.moshaver.tahsili 2>/dev/null | tr -d '\r' || true)"
  [[ -n "$pid" ]] && break
  sleep 1
done
if [[ -z "$pid" ]]; then
  adb logcat -d -b crash > "$report_dir/crash-log.txt"
  echo "Debug smoke-test application process did not stay alive after launch" | tee "$report_dir/result.txt"
  exit 1
fi

sleep 3
adb exec-out screencap -p > "$report_dir/launch.png"
adb logcat -d -b crash > "$report_dir/crash-log.txt"
if grep -q 'FATAL EXCEPTION' "$report_dir/crash-log.txt"; then
  echo "Fatal Android exception detected during debug smoke test" | tee "$report_dir/result.txt"
  exit 1
fi

device_id="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
if [[ -z "$device_id" ]]; then
  echo "No ready Android emulator was found for the secure-storage integration test" | tee "$report_dir/secure-storage-integration.txt"
  exit 1
fi
flutter test integration_test/secure_storage_test.dart -d "$device_id" --reporter expanded 2>&1 | tee "$report_dir/secure-storage-integration.txt"

printf 'Disposable debug APK installed, launched, and remained alive on Android emulator (release APK is built and signature-verified separately) (physical-device and payment tests remain manual).\n' | tee "$report_dir/result.txt"
