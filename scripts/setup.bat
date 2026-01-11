@echo off
echo Setting up KazuVera2D...

echo.
echo Cleaning project...
flutter clean

echo.
echo Getting dependencies...
flutter pub get

echo.
echo Enabling Windows desktop support...
flutter create --platforms=windows .

echo.
echo Setup complete!
echo.
echo To run the project, you need Visual Studio Build Tools.
echo Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/
echo Select "Desktop development with C++" workload during installation.
echo.
echo After installing VS Build Tools, run: flutter run -d windows
echo.
pause