@echo off
setlocal EnableExtensions
title BAR Droid - install toolchain
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

set "ACCEPT="
if /i "%~1"=="--accept-licenses" set "ACCEPT=-AcceptAndroidLicenses"

powershell -NoProfile -ExecutionPolicy Bypass -File "%APPDIR%\scripts\install-toolchain.ps1" %ACCEPT%
if errorlevel 1 goto :fail

rem Termux:X11 (the embedded X server) at the pinned commit, patched.
powershell -NoProfile -ExecutionPolicy Bypass -File "%APPDIR%\tools\fetch-termux-x11.ps1"
if errorlevel 1 goto :fail

if not exist "%APPDIR%\local.properties" (
    > "%APPDIR%\local.properties" echo sdk.dir=%ANDROID_HOME:\=\\%
)
echo.
echo  Toolchain ready. Next: "Build APK.bat"
exit /b 0

:fail
echo.
echo  Toolchain setup stopped (see messages above).
if not defined BARDROID_NOPAUSE pause
exit /b 1
