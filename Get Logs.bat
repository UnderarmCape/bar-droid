@echo off
setlocal EnableExtensions
title BAR Droid - logs
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

rem Copies the app's logs into logs\<phone|emulator>-<date>-<time>\.
rem   Get Logs.bat            the emulator, or the phone when no emulator is running
rem   Get Logs.bat phone      the phone (USB or wireless) even while the emulator runs
rem The phone: ANDROID_SERIAL if set (a phone named on purpose), else the first line of phone-device.txt beside the
rem toolchain folder that adb lists (a phone kept for development; outside the repository), else the first one listed.
set "NAMED=%ANDROID_SERIAL%"
set "ANDROID_SERIAL="
set "EMU="
set "PHONE="
if defined NAMED set "PHONE=%NAMED%"
if not defined PHONE if exist "%TC%\..\phone-device.txt" for /f "usebackq eol=# tokens=1" %%d in ("%TC%\..\phone-device.txt") do if not defined PHONE call :listed %%d
for /f "skip=1 tokens=1,2" %%a in ('adb devices') do if "%%b"=="device" call :classify %%a
if defined NAMED set "EMU="
set "KIND=emulator"
if defined EMU set "ANDROID_SERIAL=%EMU%"
if /i "%~1"=="phone" set "ANDROID_SERIAL="
if not defined ANDROID_SERIAL if defined PHONE (set "ANDROID_SERIAL=%PHONE%" & set "KIND=phone")
if not defined ANDROID_SERIAL (echo  No device connected. & goto :end)
echo  Device: %ANDROID_SERIAL% (%KIND%)
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%t"
set "OUT=%BARANDROID%\logs\%KIND%-%TS%"
mkdir "%OUT%" 2>nul
set "PKG=com.underarmcape.bardroid"
adb exec-out run-as %PKG% cat files/logs/launcher.log > "%OUT%\launcher.log"
adb exec-out run-as %PKG% sh -c "cat files/logs/launcher.old.log 2>/dev/null" > "%OUT%\launcher.old.log"
adb exec-out run-as %PKG% cat files/bar/infolog.txt > "%OUT%\infolog.txt"
adb exec-out run-as %PKG% cat files/install-state.properties > "%OUT%\install-state.properties"
adb exec-out run-as %PKG% sh -c "cat files/bar/logs/glcheck-*.txt" > "%OUT%\glcheck.txt"
adb exec-out run-as %PKG% sh -c "cat files/rootfs/tmp/pulse/pulse.log" > "%OUT%\pulse.log"
adb logcat -d -s BarDroid/app BarDroid/svc BarDroid/install BarDroid/x11 BarDroid/engine BarDroid/rootfs LorieNative CmdEntryPoint AndroidRuntime > "%OUT%\logcat.txt"
echo.
echo  Saved to %OUT%
:end
if not defined BARDROID_NOPAUSE pause
exit /b

:classify
echo %1| find "emulator-" >nul
if errorlevel 1 (if not defined PHONE set "PHONE=%1") else (if not defined EMU set "EMU=%1")
exit /b

:listed
for /f "skip=1 tokens=1,2" %%a in ('adb devices') do if "%%a"=="%~1" if "%%b"=="device" set "PHONE=%~1"
exit /b
