@echo off
rem Opens a root shell inside the phone's Debian container (same proot setup as the app), or runs one command:
rem   tools\container-shell.bat
rem   tools\container-shell.bat "glxinfo -B"
rem Needs the debug APK (run-as) and one connected device. The app writes files/container.sh on Install/Play.
setlocal
call "%~dp0..\..\toolchain\env.bat" >nul
if "%~1"=="" (
  adb shell -t run-as com.underarmcape.bardroid sh files/container.sh
) else (
  adb shell run-as com.underarmcape.bardroid sh files/container.sh "'%~1'"
)
