@echo off
rem Developer smoke test on an x86_64 Android 14 emulator (WHPX). Covers the Android side only: launcher UI,
rem foreground service, downloads, X server + display + gamepad UDP bridge. proot cannot run there (it cannot
rem trace ARM-translated processes), so container steps hang; tap Stop. One-time setup:
rem   android sdk install emulator system-images/android-34/google_apis/x86_64  (see HANDOFF.md)
rem   tools\build-emulator-x11.bat
rem Usage: tools\emulator-test.bat            (boots the AVD, builds the emulator APK, installs, starts it)
setlocal
rem The emulator writes .emulator_console_auth_token to the real profile regardless of USERPROFILE; delete it on exit.
set "TOKEN=%USERPROFILE%\.emulator_console_auth_token"
call "%~dp0..\..\toolchain\env.bat" >nul
if not exist "%ANDROID_HOME%\system-images\android-34\google_apis\x86_64\system.img" (
  "%ANDROID_HOME%\cmdline-tools\latest\bin\android.exe" --no-metrics "--sdk=%ANDROID_HOME%" sdk install emulator system-images/android-34/google_apis/x86_64 || exit /b 1
)
if not exist "%APPDIR%\build\emu-x86_64\jnilibs\arm64-v8a\libXlorie_x86_64.so" call "%~dp0build-emulator-x11.bat" || exit /b 1
if not exist "%ANDROID_AVD_HOME%\bardroid-test.ini" (
  mkdir "%ANDROID_AVD_HOME%\bardroid-test.avd" 2>nul
  > "%ANDROID_AVD_HOME%\bardroid-test.ini" (echo avd.ini.encoding=UTF-8& echo path=%ANDROID_AVD_HOME%\bardroid-test.avd& echo target=android-34)
  > "%ANDROID_AVD_HOME%\bardroid-test.avd\config.ini" (
    echo AvdId=bardroid-test& echo abi.type=x86_64& echo hw.cpu.arch=x86_64& echo hw.cpu.ncore=4& echo hw.ramSize=4096
    echo disk.dataPartition.size=8G& echo image.sysdir.1=system-images\android-34\google_apis\x86_64\& echo tag.id=google_apis
    echo hw.lcd.width=2400& echo hw.lcd.height=1080& echo hw.lcd.density=420& echo hw.initialOrientation=landscape
    echo hw.keyboard=yes& echo hw.gpu.enabled=yes& echo hw.gpu.mode=swiftshader_indirect& echo fastboot.forceColdBoot=yes)
)
start "BAR Droid emulator" cmd /c ""%ANDROID_HOME%\emulator\emulator.exe" -avd bardroid-test -no-snapshot -no-boot-anim -no-audio -no-metrics -gpu swiftshader_indirect & del /f /q "%TOKEN%" 2>nul"
adb wait-for-device
:boot
adb shell getprop sys.boot_completed | find "1" >nul || (ping -n 4 127.0.0.1 >nul & goto :boot)
call "%APPDIR%\gradlew.bat" -p "%APPDIR%" --no-daemon :app:assembleDebug -PbardroidEmulatorX11 || exit /b 2
adb install -r "%APPDIR%\app\build\outputs\apk\debug\bar-droid-debug.apk" || exit /b 3
adb shell am start -n com.underarmcape.bardroid/.LauncherActivity
echo Emulator running. Note: the APK in app\build is now the emulator build; rebuild before installing on a phone.
