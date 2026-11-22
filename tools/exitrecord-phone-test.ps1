# What is left after the app or the engine dies (ExitRecord; RC 0.2.0 item 6, release overhaul item 53), on the dev phone:
#  1. a developer's build's "start crashtest" throws an exception no code catches: its stack in launcher.log;
#  2. the next start writes Android's record of that death to launcher.log: "crashed (an exception in Java)", with the
#     process's state summary then ("app started, screen ...");
#  3. -EngineCrash: a skirmish, its engine sent SIGSEGV once it plays; what launcher.log, infolog.txt and the next start's
#     exit records then hold is printed (for docs/DELIVERY.md), and a force stop's record read back with its summary (the
#     game's map and screen).
# Nothing on the laptop. About 1 minute, 4 with -EngineCrash.
#   powershell -ExecutionPolicy Bypass -File tools\exitrecord-phone-test.ps1 [-EngineCrash]
param([switch]$EngineCrash)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$fails = 0
function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Check([string]$case, [bool]$ok, [string]$detail) {
  "[exitrec] $(if ($ok) { 'PASS' } else { 'FAIL' }) $case$(if ($detail) { ": $detail" })"
  if (-not $ok) { $script:fails++ }
}
function LogSince([int]$from) { @(InApp "tail -c +$($from + 1) files/logs/launcher.log 2>/dev/null") }
function LogSize { [int]("$(InApp "wc -c < files/logs/launcher.log 2>/dev/null")".Trim()) }
function Launcher { & $adb shell am start -n "$pkg/.LauncherActivity" | Out-Null }

& $adb shell am force-stop $pkg
Set-PhoneAwake $adb
# (a start first: the records of deaths before this test read and set aside, so the next ones are this test's)
Launcher; Start-Sleep 4
$at = LogSize
& $adb shell am start -n "$pkg/.LauncherActivity" --es start crashtest | Out-Null
Start-Sleep 4
$lines = LogSince $at
$stack = ($lines | Select-String -SimpleMatch "an exception no code caught" | Select-Object -First 1)
$trace = ($lines | Select-String -SimpleMatch "BAR Droid crash test (start crashtest): thrown on purpose" | Select-Object -First 1)
$frames = @($lines | Select-String -Pattern '^\s+at ' ).Count
Check "an exception no code caught: its stack in launcher.log" ($null -ne $stack -and $null -ne $trace -and $frames -ge 3) "$frames stack lines"
& $adb shell am force-stop $pkg   # (the crash dialog, if Android shows one)
$at = LogSize
Launcher; Start-Sleep 5
$rec = (LogSince $at | Select-String -Pattern '\[exit\] the app''s process ended .*crashed \(an exception in Java\).*its state then: ' | Select-Object -First 1)
Check "the next start: Android's record of that death in launcher.log, with the state then" ($null -ne $rec) "$rec"

if ($EngineCrash) {
  & $adb shell am force-stop $pkg
  InApp "rm -f files/bar/infolog.txt"
  $at = LogSize
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(4); $pid0 = ""
  while ((Get-Date) -lt $until) {
    $pid0 = "$(InApp "pidof spring")".Trim()
    $frame = "$(InApp "grep -a -o '\[f=00002[0-9][0-9]\]' files/bar/infolog.txt 2>/dev/null | tail -n 1")".Trim()
    if ($pid0 -and $frame) { break }
    Start-Sleep 3
  }
  if (-not $pid0) { Check "the skirmish's engine running" $false "no spring in 4 minutes" }
  else {
    "[exitrec] (the engine at frame 200+, pid ${pid0}: SIGSEGV)"
    InApp "kill -SEGV $($pid0.Split(' ')[0])"
    Start-Sleep 12
    "[exitrec] --- launcher.log after the engine's SIGSEGV:"
    LogSince $at | Select-String -Pattern 'signal|SIGSEGV|exit|crash|Segmentation|killed|ended|rc=|code' | Select-Object -Last 15 | ForEach-Object { "  $_" }
    "[exitrec] --- infolog.txt's last lines:"
    @(InApp "tail -n 25 files/bar/infolog.txt") | ForEach-Object { "  $_" }
    "[exitrec] --- the app's process: $(if ("$(& $adb shell pidof $pkg)".Trim()) { 'alive (the engine is a child process: no exit record of the app)' } else { 'gone' })"
  }
  # (a death the app does not see coming, as a swipe from recent apps: its record and the state summary read back)
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(4)
  while ((Get-Date) -lt $until -and -not ("$(InApp "grep -a -c 'Archive file=' files/bar/infolog.txt 2>/dev/null")".Trim() -gt 0)) { Start-Sleep 3 }
  Start-Sleep 5
  & $adb shell am force-stop $pkg
  $at = LogSize
  Launcher; Start-Sleep 5
  $rec = (LogSince $at | Select-String -Pattern '\[exit\] the app''s process ended .*its state then: game, map ' | Select-Object -First 1)
  Check "a force stop in a game: its record read back with the game's map and screen" ($null -ne $rec) "$rec"
  & $adb shell am force-stop $pkg
}
"[exitrec] done: $(if ($fails -eq 0) { 'ALL PASS' } else { "$fails FAILED" })"
