# A spectator's 1st person through BAR's mid-game settings save, on the dev phone (nothing on the laptop), ~1.5 min:
# tools\spectate-test\bardroid_fpsave_test.lua in a skirmish, its lines from its own file (the game's log is late on a phone).
#   powershell -ExecutionPolicy Bypass -File tools\fp-save-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_fpsave_test.lua"
$out = "files/bar/LuaUI/Config/bardroid_fpsave.txt"

& $adb shell am force-stop $pkg
& $adb exec-out run-as $pkg rm -f $out
Send-AppFile $adb (Join-Path $PSScriptRoot "spectate-test\bardroid_fpsave_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(6)
  while ((Get-Date) -lt $until) {
    if ((& $adb exec-out run-as $pkg sh -c "cat $out 2>/dev/null") -match '\[fpsave\] (done|FAIL never)') { break }
    Start-Sleep 3
  }
  $lines = & $adb exec-out run-as $pkg sh -c "cat $out 2>/dev/null"
  $lines
  if (-not ($lines -match '\[fpsave\] done')) { "[fpsave] FAIL it did not finish in 6 minutes (a dialog over the app? the game did not start?)" }
} finally {
  & $adb exec-out run-as $pkg rm -f $widget $out
  & $adb shell am force-stop $pkg
}
