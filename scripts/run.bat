@echo off
echo Starting KazuVera2D...

:: 切换到项目根目录
cd /d "%~dp0.."

echo.
echo Current directory: %CD%

echo.
echo Getting dependencies...
flutter pub get

echo.
echo Generating code with build_runner...
dart run build_runner build --delete-conflicting-outputs

echo.
echo Checking Visual Studio Build Tools...
flutter doctor

echo.
echo If you see Visual Studio errors above, please install:
echo https://visualstudio.microsoft.com/visual-cpp-build-tools/
echo Select "Desktop development with C++" workload
echo.

flutter run -d windows

pause