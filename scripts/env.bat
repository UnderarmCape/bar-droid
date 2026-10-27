@echo off
rem ---------------------------------------------------------------------------
rem  BAR Droid - process-local build environment.
rem  Every variable set here lives only inside the current console window.
rem  Nothing is written to the registry, global PATH, %USERPROFILE% or AppData.
rem
rem  The portable toolchain's folder (JDK, Git, Android SDK/NDK, host tools; "Install Toolchain.bat" fills it):
rem    BARDROID_TOOLCHAIN if set, else a "toolchain" folder beside this checkout if one is installed there (the
rem    original C:\Tools\BARANDROID layout), else toolchain\ inside this checkout (git-ignored).
rem  Built APKs and logs go to apk\ and logs\ in the toolchain folder's parent, or in BARDROID_OUT if set.
rem ---------------------------------------------------------------------------
for %%I in ("%~dp0..") do set "APPDIR=%%~fI"
if defined BARDROID_TOOLCHAIN (
    for %%I in ("%BARDROID_TOOLCHAIN%") do set "TC=%%~fI"
) else if exist "%APPDIR%\..\toolchain\jdk\bin\java.exe" (
    for %%I in ("%APPDIR%\..\toolchain") do set "TC=%%~fI"
) else (
    set "TC=%APPDIR%\toolchain"
)
for %%I in ("%TC%\..") do set "BARANDROID=%%~fI"
if defined BARDROID_OUT for %%I in ("%BARDROID_OUT%") do set "BARANDROID=%%~fI"

set "JAVA_HOME=%TC%\jdk"
set "ANDROID_HOME=%TC%\android-sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
set "ANDROID_USER_HOME=%TC%\home\.android"
rem The emulator ignores USERPROFILE and needs these to stay out of the real profile.
set "ANDROID_EMULATOR_HOME=%TC%\home\.android"
set "ANDROID_AVD_HOME=%TC%\home\.android\avd"
set "GRADLE_USER_HOME=%TC%\gradle-home"
set "GIT_DIR_TC=%TC%\git"

rem Only our own tools plus core Windows folders (curl.exe / tar.exe live in System32).
set "PATH=%JAVA_HOME%\bin;%GIT_DIR_TC%\cmd;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\cmdline-tools\latest\bin;%TC%\hosttools\python;%TC%\hosttools\winflexbison;%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0"
rem Host C compiler for the X server's makekeys generator (termux-x11 assumes /usr/bin/gcc).
set "LORIE_HOST_CC=%TC%\hosttools\w64devkit\bin\gcc.exe"
set "PYTHONDONTWRITEBYTECODE=1"

rem Redirect every per-user location a tool might fall back to (~/.gradle, ~/.android, ~/.gitconfig, adbkey).
set "HOME=%TC%\home"
set "USERPROFILE=%TC%\home"
set "TEMP=%TC%\temp"
set "TMP=%TC%\temp"
set "APPDATA=%TC%\home\AppData\Roaming"
set "LOCALAPPDATA=%TC%\home\AppData\Local"
set "XDG_CONFIG_HOME=%TC%\home\.config"
set "GIT_CONFIG_NOSYSTEM=1"
rem Java ignores USERPROFILE for user.home on Windows; pin it explicitly.
set "JAVA_TOOL_OPTIONS=-Duser.home=%TC%\home"

for %%D in ("%TC%\home" "%TC%\temp" "%APPDATA%" "%LOCALAPPDATA%" "%ANDROID_USER_HOME%" "%GRADLE_USER_HOME%" "%TC%\downloads" "%BARANDROID%\apk" "%BARANDROID%\logs") do (
    if not exist "%%~D" mkdir "%%~D"
)
if not exist "%TC%\home\.gitconfig" (
    > "%TC%\home\.gitconfig" echo [core]
    >> "%TC%\home\.gitconfig" echo 	autocrlf = false
    >> "%TC%\home\.gitconfig" echo 	longpaths = true
    >> "%TC%\home\.gitconfig" echo 	symlinks = false
)
exit /b 0
