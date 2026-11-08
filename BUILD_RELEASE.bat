@echo off
setlocal
cd /d "%~dp0"

echo ================================================
echo Smart Mechanic - Release Build 1.2.2+5
echo ================================================

where flutter >nul 2>&1
if errorlevel 1 (
  echo ERROR: Flutter was not found in PATH.
  echo Install Flutter and restart this terminal.
  exit /b 1
)

flutter doctor -v
if errorlevel 1 exit /b 1

flutter clean
if errorlevel 1 exit /b 1

flutter pub get
if errorlevel 1 exit /b 1

if exist "%~dp0assets\branding\app_icon.png" (
  dart run flutter_launcher_icons
  if errorlevel 1 exit /b 1
)

flutter analyze --no-fatal-infos
if errorlevel 1 (
  echo WARNING: Dart analyzer reported non-blocking lint findings; tests and build remain required gates.
)

flutter test
if errorlevel 1 (
  echo ERROR: Tests failed.
  exit /b 1
)

flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build\symbols
if errorlevel 1 (
  echo ERROR: APK build failed.
  exit /b 1
)

flutter build appbundle --release --target-platform android-arm64 --obfuscate --split-debug-info=build\symbols
if errorlevel 1 (
  echo ERROR: App Bundle build failed.
  exit /b 1
)

echo.
echo SUCCESS
echo APK (direct installation): build\app\outputs\flutter-apk\app-release.apk
echo AAB (Google Play): build\app\outputs\bundle\release\app-release.aab
exit /b 0
