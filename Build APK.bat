@echo off
setlocal EnableExtensions
title BAR Droid - build APK
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

rem Default: the emulator build (x86_64, runs natively in the Android emulator, software OpenGL).
rem "Build APK.bat phone": the arm64 build for Snapdragon phones.
rem "Build APK.bat phone release": the build that goes out (docs/DELIVERY.md "Releasing"): the project's own icon,
rem signed with the release key named in local.properties (bardroid.keystore, bardroid.keyAlias; passwords in
rem BARDROID_KEYSTORE_PASSWORD and BARDROID_KEY_PASSWORD), named with the version (gradle.properties).
set "ABI=x86_64"
set "TARGET=emulator"
set "TYPE=debug"
set "TASK=assembleDebug"
if /i "%~1"=="phone" (set "ABI=arm64-v8a" & set "TARGET=phone" & shift)
if /i "%~1"=="release" (set "TYPE=release" & set "TASK=assembleRelease" & shift)

if not exist "%JAVA_HOME%\bin\java.exe" goto :no_toolchain
if not exist "%ANDROID_HOME%\ndk\29.0.14206865" goto :no_toolchain
if not exist "%APPDIR%\termux-x11\lorie\build.gradle" goto :no_toolchain
if "%TYPE%"=="release" (
    findstr /b /c:"bardroid.keystore=" "%APPDIR%\local.properties" >nul 2>nul || goto :no_key
    if not defined BARDROID_KEYSTORE_PASSWORD goto :no_key
)

cd /d "%APPDIR%"
rem (no APK of an earlier version left beside the new one)
if exist "%APPDIR%\app\build\outputs\apk\%TYPE%" rd /s /q "%APPDIR%\app\build\outputs\apk\%TYPE%"
call "%APPDIR%\gradlew.bat" --no-daemon :app:%TASK% -PbardroidAbi=%ABI% %1 %2 %3 %4
if errorlevel 1 goto :fail
for %%F in ("%APPDIR%\app\build\outputs\apk\%TYPE%\bar-droid-%TARGET%-*.apk") do set "APK=%%~fF"
copy /y "%APK%" "%BARANDROID%\apk\" >nul
for %%F in ("%APK%") do set "APKNAME=%%~nxF"
echo.
echo  APK (%TARGET%, %TYPE%): %BARANDROID%\apk\%APKNAME%
if "%TYPE%"=="release" (echo  Before publishing: tools\publish-check.ps1) else if "%TARGET%"=="emulator" (echo  Run it: "Run in Emulator.bat") else (echo  Install on the phone: "Install on Phone.bat")
exit /b 0

:no_key
echo.
echo  A release build needs the release signing key: bardroid.keystore=^<path^> (and bardroid.keyAlias=^<alias^>) in
echo  local.properties and its password in BARDROID_KEYSTORE_PASSWORD. Make a key once with the JDK's keytool:
echo    keytool -genkeypair -keystore ^<path^> -alias bardroid -keyalg RSA -keysize 4096 -validity 10000
echo  Keep it and its password safe and out of the repository: every update must be signed with the same key.
if not defined BARDROID_NOPAUSE pause
exit /b 1

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
