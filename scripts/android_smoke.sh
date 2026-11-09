#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/reports/device
report_dir="build/reports/device"
apk="$(find device-artifacts -type f -name '*-x86_64.apk' -print -quit)"
if [[ -z "$apk" ]]; then
  echo "Release x86_64 APK artifact missing" | tee "$report_dir/result.txt"
  exit 1
fi

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
  echo "Release application process did not stay alive after launch" | tee "$report_dir/result.txt"
  exit 1
fi

sleep 3
adb exec-out screencap -p > "$report_dir/launch.png"
adb logcat -d -b crash > "$report_dir/crash-log.txt"
if grep -q 'FATAL EXCEPTION' "$report_dir/crash-log.txt"; then
  echo "Fatal Android exception detected" | tee "$report_dir/result.txt"
  exit 1
fi

printf 'Release APK installed, launched, and remained alive on Android emulator (physical-device and payment tests remain manual).\n' | tee "$report_dir/result.txt"
