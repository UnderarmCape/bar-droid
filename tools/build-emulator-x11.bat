@echo off
rem Emulator testing only: builds Termux:X11's X server for x86_64 so that the display pipeline (X server,
rem ACTION_START broadcast, GameActivity) can be exercised on an x86_64 Android emulator. The engine/proot side
rem cannot run there (proot cannot trace ARM-translated processes). Then build with:
rem   gradlew.bat :app:assembleDebug -PbardroidEmulatorX11
setlocal
call "%~dp0..\..\toolchain\env.bat" >nul
set "B=%APPDIR%\build\emu-x86_64"
set "NDK=%ANDROID_HOME%\ndk\29.0.14206865"
set "CM=%ANDROID_HOME%\cmake\3.22.1\bin"
"%CM%\cmake.exe" "-H%APPDIR%\termux-x11\lorie\src\main\cpp" "-B%B%" -GNinja -DCMAKE_SYSTEM_NAME=Android ^
  -DCMAKE_SYSTEM_VERSION=24 -DANDROID_PLATFORM=android-24 -DANDROID_ABI=x86_64 -DCMAKE_ANDROID_ARCH_ABI=x86_64 ^
  "-DANDROID_NDK=%NDK%" "-DCMAKE_ANDROID_NDK=%NDK%" "-DCMAKE_TOOLCHAIN_FILE=%NDK%\build\cmake\android.toolchain.cmake" ^
  "-DCMAKE_MAKE_PROGRAM=%CM%\ninja.exe" "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=%B%\out" -DCMAKE_BUILD_TYPE=Release || exit /b 1
"%CM%\ninja.exe" -C "%B%" || exit /b 2
if not exist "%B%\jnilibs\arm64-v8a" mkdir "%B%\jnilibs\arm64-v8a"
rem Packaged under arm64-v8a on purpose: the app is arm64 (run through the emulator's ARM translation);
rem only the X server child process (app_process) is x86_64.
"%NDK%\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe" -o "%B%\jnilibs\arm64-v8a\libXlorie_x86_64.so" "%B%\out\libXlorie.so" || exit /b 3
echo x86_64 X server: %B%\jnilibs\arm64-v8a\libXlorie_x86_64.so
