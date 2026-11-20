# The GPU driver fault's close (GameService + DriverWatch; 2026-11-19's system) on the dev phone: it must arm only on
# Mesa's own line on the engine's stderr, never on one of the engine's log lines. In a skirmish the test widget
# (tools\driverwatch-phone-test\bardroid_driverwatch_test.lua) says the driver's refusal and BAR's watchdog line as chat
# and echoes them (each an engine log line, "[t=...][f=...] ..."): the app's launcher.log must not say "the GPU driver
# refused a submit", and the game must still run 12 s later (no close, no note). (Armed by a chat line, the close killed
# a game whose widget then went quiet 8 s.) The real fault's lines are checked on the laptop: tools\status-text-test.ps1.
# Nothing on the laptop. About 1.5 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\driverwatch-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_driverwatch_test.lua"
$cfg = "files/bar/LuaUI/Config"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_driverwatch_test.lua")
if ($stray) { "[driverwatchtest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
InApp "rm -f files/bar/infolog.txt $cfg/bardroid_driverwatchtest.txt; echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg"
Send-AppFile $adb (Join-Path $PSScriptRoot "driverwatch-phone-test\bardroid_driverwatch_test.lua") $widget
$fails = 0
try {
  Set-PhoneAwake $adb
  $logLines = [int]"$(InApp 'wc -l < files/logs/launcher.log 2>/dev/null')".Trim()   # (this run's lines: after these)
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(4); $state = ""
  while ((Get-Date) -lt $until) {
    $state = "$(InApp "cat $cfg/bardroid_driverwatchtest.txt 2>/dev/null")".Trim()
    if ($state -eq "end" -or -not (& $adb shell pidof spring) -and $state -eq "said") { break }
    Start-Sleep -Milliseconds 500
  }
  $run = @(InApp "tail -n +$($logLines + 1) files/logs/launcher.log")
  $armed = @($run | Select-String -SimpleMatch "the GPU driver refused")
  $closed = @($run | Select-String -SimpleMatch "rare GPU driver fault")
  $alive = [bool](& $adb shell pidof spring)
  Log '\[driverwatchtest\]|Error in' 10 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  if ($state -ne "end") { "[driverwatchtest] FAIL the test did not finish (the widget's file: '$state', spring $(if ($alive) { 'running' } else { 'gone' }))"; $fails++ }
  if ($armed.Count -eq 0) { "[driverwatchtest] PASS the words as chat and echo: the driver watch not armed" }
  else { "[driverwatchtest] FAIL the words as chat and echo armed the driver watch: $(($armed | ForEach-Object { $_.Line.Trim() }) -join ' | ')"; $fails++ }
  if ($closed.Count -eq 0 -and $alive) { "[driverwatchtest] PASS the game still running, no driver note" }
  else { "[driverwatchtest] FAIL the game closed or noted: alive $alive, $(($closed | ForEach-Object { $_.Line.Trim() }) -join ' | ')"; $fails++ }
  # (the engine's state lines said as chat: no state of the app's changed by them)
  $state = @($run | Select-String -Pattern "back in the lobby|a game loads \(from the lobby\)|joining a game hosted elsewhere|not loading now")
  if ($state.Count -eq 0) { "[driverwatchtest] PASS the engine's state lines as chat: the app's state unchanged" }
  else { "[driverwatchtest] FAIL the engine's state lines as chat changed the app's state: $(($state | ForEach-Object { $_.Line.Trim() }) -join ' | ')"; $fails++ }
  # (how the chat lines look in the log: for the record)
  Log 'SpringApp::Reload\] test|creating LoadScreen$|203\.0\.113\.7' 6 | ForEach-Object { "[driverwatchtest] (in the log: $_)" }
  "[driverwatchtest] done: $(if ($fails -eq 0) { 'ALL PASS' } else { "$fails FAILED" })"
} finally {
  & $adb shell am force-stop $pkg
  InApp "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_driverwatchtest.txt"
}
