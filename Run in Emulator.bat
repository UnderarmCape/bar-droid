@echo off
setlocal EnableExtensions
title BAR Droid - Android emulator
cd /d "%~dp0"
rem The emulator writes .emulator_console_auth_token into the real profile whatever USERPROFILE says; it is
rem deleted again when the emulator closes.
set "TOKEN=%USERPROFILE%\.emulator_console_auth_token"
call "%~dp0scripts\env.bat"

rem Starts a virtual Android 14 phone (x86_64, 12 GB RAM, 6 cores, 32 GB storage) and installs + opens BAR Droid.
rem Extra arguments go to the emulator, e.g. "Run in Emulator.bat" -no-audio
set "AVD=bardroid-x86_64"
set "APK=%BARANDROID%\apk\bar-droid-emulator-debug.apk"
if not exist "%APK%" (echo. & echo  No emulator APK yet. Run "Build APK.bat" first. & goto :end)

if not exist "%ANDROID_HOME%\emulator\emulator.exe" set "NEED=1"
if not exist "%ANDROID_HOME%\system-images\android-34\google_apis\x86_64\system.img" set "NEED=1"
if defined NEED (
  echo  Downloading the Android emulator and the Android 14 system image ^(about 1.8 GB, one time^)...
  "%ANDROID_HOME%\cmdline-tools\latest\bin\android.exe" --no-metrics "--sdk=%ANDROID_HOME%" sdk install emulator system-images/android-34/google_apis/x86_64 || goto :end
)
if not exist "%ANDROID_AVD_HOME%\%AVD%.ini" (
  mkdir "%ANDROID_AVD_HOME%\%AVD%.avd" 2>nul
  > "%ANDROID_AVD_HOME%\%AVD%.ini" (echo avd.ini.encoding=UTF-8& echo path=%ANDROID_AVD_HOME%\%AVD%.avd& echo target=android-34)
  > "%ANDROID_AVD_HOME%\%AVD%.avd\config.ini" (
    echo AvdId=%AVD%& echo avd.ini.displayname=BAR Droid x86_64& echo abi.type=x86_64& echo hw.cpu.arch=x86_64
    echo hw.cpu.ncore=6& echo hw.ramSize=12288& echo vm.heapSize=512& echo disk.dataPartition.size=32G
    echo image.sysdir.1=system-images\android-34\google_apis\x86_64\& echo tag.id=google_apis& echo PlayStore.enabled=false
    echo hw.lcd.width=2400& echo hw.lcd.height=1080& echo hw.lcd.density=420& echo hw.initialOrientation=landscape
    echo hw.keyboard=yes& echo hw.mainKeys=no& echo hw.gpu.enabled=yes& echo hw.gpu.mode=host& echo hw.gamepad=yes)
)
rem GPU commands over shared memory (asg) instead of the goldfish pipe: ~3x the game's frame rate. Takes effect
rem on the next emulator start.
find "hw.gltransport" "%ANDROID_AVD_HOME%\%AVD%.avd\config.ini" >nul || >> "%ANDROID_AVD_HOME%\%AVD%.avd\config.ini" (
  echo hw.gltransport=asg& echo hw.gltransport.asg.writeBufferSize=8388608& echo hw.gltransport.asg.writeStepSize=65536
  echo hw.gltransport.asg.dataRingSize=4194304)

adb devices | find "emulator-" >nul
if errorlevel 1 (
  rem A token left behind by a crash or restart (the cleanup below never ran).
  del /f /q "%TOKEN%" 2>nul
  echo  Starting the emulator...
  start "BAR Droid emulator" /min cmd /c ""%ANDROID_HOME%\emulator\emulator.exe" -avd %AVD% -no-boot-anim -no-metrics %* & del /f /q "%TOKEN%" 2>nul"
)
adb wait-for-device
:boot
adb shell getprop sys.boot_completed 2>nul | find "1" >nul || (ping -n 3 127.0.0.1 >nul & goto :boot)
echo  Installing BAR Droid...
adb install -r -g "%APK%" || goto :end
adb shell am start -n com.underarmcape.bardroid/.LauncherActivity >nul
echo.
echo  BAR Droid is open in the emulator window. First time: tap INSTALL / UPDATE (downloads ~4 GB), then PLAY VS AI.
echo  Logs: "Get Logs.bat". Closing the emulator window shuts it down.
:end
if not defined BARDROID_NOPAUSE pause
