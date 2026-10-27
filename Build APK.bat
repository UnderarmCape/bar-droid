@echo off
setlocal EnableExtensions
title BAR Droid - build APK
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

rem Default: the emulator build (x86_64, runs natively in the Android emulator, software OpenGL).
rem "Build APK.bat phone": the arm64 build for Snapdragon phones.
set "ABI=x86_64"
set "TARGET=emulator"
if /i "%~1"=="phone" (set "ABI=arm64-v8a" & set "TARGET=phone" & shift)

if not exist "%JAVA_HOME%\bin\java.exe" goto :no_toolchain
if not exist "%ANDROID_HOME%\ndk\29.0.14206865" goto :no_toolchain
if not exist "%APPDIR%\termux-x11\lorie\build.gradle" goto :no_toolchain

cd /d "%APPDIR%"
call "%APPDIR%\gradlew.bat" --no-daemon :app:assembleDebug -PbardroidAbi=%ABI% %1 %2 %3 %4
if errorlevel 1 goto :fail
set "APK=%APPDIR%\app\build\outputs\apk\debug\bar-droid-%TARGET%-debug.apk"
copy /y "%APK%" "%BARANDROID%\apk\" >nul
echo.
echo  APK (%TARGET%): %BARANDROID%\apk\bar-droid-%TARGET%-debug.apk
if "%TARGET%"=="emulator" (echo  Run it: "Run in Emulator.bat") else (echo  Install on the phone: "Install on Phone.bat")
exit /b 0

:no_toolchain
echo.
echo  The toolchain is not set up yet. Double-click "Install Toolchain.bat" first.
if not defined BARDROID_NOPAUSE pause
exit /b 1

:fail
echo.
echo  Build failed (see messages above).
if not defined BARDROID_NOPAUSE pause
exit /b 1
