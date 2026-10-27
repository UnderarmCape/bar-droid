@echo off
setlocal EnableExtensions
title BAR Droid - pair phone (wireless debugging)
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

rem Wireless adb to the phone (no USB cable), on the same Wi-Fi as this PC or over Tailscale. On the phone:
rem   Developer options > Wireless debugging ON (needs Wi-Fi), then "Pair device with pairing code".
rem Use the IP address and PORTS the phone shows; with Tailscale on this PC the phone's Tailscale address is found
rem automatically.
rem   Pair Phone.bat                                  asks for the address, the ports and the code
rem   Pair Phone.bat <pair-port> <code> <connect-port> [phone-ip]
rem   Pair Phone.bat - - <connect-port> [phone-ip]    already paired: connect only
set "TS=%ProgramFiles%\Tailscale\tailscale.exe"
set "IP=%~4"
if not defined IP if exist "%TS%" for /f "tokens=1,4" %%a in ('"%TS%" status') do if /i "%%b"=="android" if not defined IP set "IP=%%a"
if not defined IP set /p "IP= Phone's IP address, as its Wireless debugging screen shows it (without the :port): "
if not defined IP goto :end
echo  Phone: %IP%

set "PAIRPORT=%~1"
set "CODE=%~2"
set "PORT=%~3"
rem The phone already lists this laptop under "Paired devices": then just press Enter here and only connect.
if not defined PAIRPORT set /p "PAIRPORT= Pairing port (Enter to skip if the laptop is already under 'Paired devices'): "
if not defined PAIRPORT goto :connect
if "%PAIRPORT%"=="-" goto :connect
if not defined CODE set /p "CODE= Six-digit pairing code: "
adb pair %IP%:%PAIRPORT% %CODE%
if errorlevel 1 (echo  Pairing failed. The code expires after about a minute; open the pairing screen again. & goto :end)

:connect

if not defined PORT set /p "PORT= Port shown on the Wireless debugging screen under 'IP address & Port': "
adb connect %IP%:%PORT%
adb devices -l
echo.
echo  Paired. Next: "Install on Phone.bat" (the port changes whenever Wireless debugging is switched off and on:
echo  then run "Pair Phone.bat" again; pairing is remembered, only the connect step is needed).
:end
if not defined BARDROID_NOPAUSE pause
