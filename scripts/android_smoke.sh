#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/reports/device
adb wait-for-device
flutter test integration_test/app_test.dart -d emulator-5554 --reporter expanded 2>&1 | tee build/reports/device/integration.txt
apk=$(find device-artifacts -type f -name '*x86_64.apk' | head -1)
test -n "$apk" || { echo 'Release x86_64 APK artifact missing'; exit 1; }
adb uninstall ir.moshaver.tahsili >/dev/null 2>&1 || true
adb install "$apk" | tee build/reports/device/install.txt
grep -q Success build/reports/device/install.txt
adb shell am start -W -n ir.moshaver.tahsili/.MainActivity | tee build/reports/device/launch.txt
grep -q 'Status: ok' build/reports/device/launch.txt
adb shell pidof ir.moshaver.tahsili | tee build/reports/device/pid.txt
test -s build/reports/device/pid.txt
adb exec-out screencap -p > build/reports/device/launch.png
adb logcat -d -b crash > build/reports/device/crash-log.txt
if grep -q 'FATAL EXCEPTION' build/reports/device/crash-log.txt; then
  echo 'Fatal Android exception detected'
  exit 1
fi
printf 'Integration test, release APK installation, launch and process checks passed on an emulator (not a physical phone).\n' > build/reports/device/result.txt
