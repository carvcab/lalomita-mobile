@echo off
echo Compilando APK de La Lomita...
cd /d "%~dp0"
flutter pub get
flutter build apk --release
echo.
echo APK generada en: mobile\build\app\outputs\flutter-apk\app-release.apk
pause
