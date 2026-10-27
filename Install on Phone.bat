@echo off
setlocal EnableExtensions
title BAR Droid - install on phone
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

rem The phone (arm64) build. For the emulator use "Run in Emulator.bat".
rem Connect the phone first: USB debugging, or wireless debugging over Tailscale with "Pair Phone.bat".
set "APK=%BARANDROID%\apk\bar-droid-phone-debug.apk"
if not exist "%APK%" (
    echo.
    echo  No phone APK yet. Run "Build APK.bat" phone first.
    goto :end
)
rem The first connected device that is not the emulator (adb uses ANDROID_SERIAL for every command below).
set "ANDROID_SERIAL="
for /f "skip=1 tokens=1,2" %%a in ('adb devices') do if "%%b"=="device" if not defined ANDROID_SERIAL (echo %%a| find "emulator-" >nul || set "ANDROID_SERIAL=%%a")
if not defined ANDROID_SERIAL (
    echo.
    echo  No phone connected. Run "Pair Phone.bat" ^(wireless, over Tailscale^) or plug in USB with USB debugging on.
    adb devices -l
    goto :end
)
echo  Phone: %ANDROID_SERIAL%
adb install -r "%APK%"
if errorlevel 1 (
    echo.
    echo  Install failed. On Samsung, "Auto Blocker" ^(Settings ^> Security and privacy^) blocks adb installs: switch it off.
    goto :end
)
adb shell am start -n com.underarmcape.bardroid/.LauncherActivity
echo.
echo  Installed and started. Logs from the phone: "Get Logs.bat" phone
:end
if not defined BARDROID_NOPAUSE pause
