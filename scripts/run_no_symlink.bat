@echo off
echo Running KazuVera2D without symlinks...
cd /d "%~dp0\.."

echo.
echo Setting environment variable to disable symlinks...
set PUB_CACHE_DISABLE_SYMLINKS=1

echo.
echo Cleaning project...
flutter clean

echo.
echo Getting dependencies...
flutter pub get

echo.
echo Running application...
flutter run -d windows

pause