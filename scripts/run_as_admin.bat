@echo off
echo Checking for administrator privileges...

net session >nul 2>&1
if %errorLevel% == 0 (
    echo Administrator privileges confirmed.
    goto :run
) else (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c cd /d %~dp0 && %~nx0' -Verb RunAs"
    exit /b
)

:run
echo Running KazuVera2D with administrator privileges...
cd /d "%~dp0\.."

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