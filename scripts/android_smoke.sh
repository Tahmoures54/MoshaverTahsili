#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/reports/device
report_failure() {
  status=${1:-$?}
  python3 scripts/annotate_log.py build/reports/device/integration.txt build/reports/device/install.txt build/reports/device/launch.txt build/reports/device/crash-log.txt || true
  exit "$status"
}
trap report_failure ERR
adb wait-for-device
set +e
flutter test integration_test/app_test.dart -d emulator-5554 --timeout 300s --reporter expanded 2>&1 | tee build/reports/device/integration.txt
integration_status=${PIPESTATUS[0]}
set -e
if [[ "$integration_status" != 0 ]]; then
  report_failure "$integration_status"
fi
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
