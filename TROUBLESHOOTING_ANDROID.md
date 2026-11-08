# Android Troubleshooting — Smart Mechanic 1.2.2

## If APK installs but closes immediately

1. Enable USB debugging on the phone.
2. Connect the device.
3. Run:

```bat
adb logcat -c
adb logcat AndroidRuntime:E flutter:E *:S
```

4. Launch Smart Mechanic and copy the first `FATAL EXCEPTION` block.

## Safe startup design

The app startup path intentionally does **not** initialize:

- Flutter Sound / native recorder
- Local notifications
- Notification timezone database
- Notification channels

Those native services are initialized only when the related feature is actually used.

## Clean rebuild

```bat
flutter clean
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter build apk --release --target-platform android-arm64 --split-debug-info=build/symbols
```

## APK location

`build\\app\\outputs\\flutter-apk\\app-release.apk`
