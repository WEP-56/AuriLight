@echo off
echo Enabling Windows desktop support...

echo.
echo Creating Windows desktop configuration...
flutter create --platforms=windows .

echo.
echo Windows desktop support enabled!
echo You can now run: flutter run -d windows

pause