# The overnight soak on the dev phone (RC 0.2.0 item 10, docs/DELIVERY.md): server replays played at 1x from their
# start, one chunk of at most 40 minutes each (the dev phone's lock freed 20 s between chunks, as tools\phone-round.ps1),
# through the launcher's bench mode (files/bar/.bardroid-bench-replay "0 <seconds> <replay>": bardroid_bench.lua plays
# the replay and quits after). Each chunk counts, from launcher.log and Android's exit records: the GPU driver's
# refusals (DriverWatch), low-memory kills, the engine's error exits, the thermal status's steps (PerfLog's "[perf]"
# lines once a minute) and the frame rate ("[bardroid-perf]" in the infolog). One line a chunk in
# build\phone-round\<stamp>-soak.txt; a chunk with a fault class not in that list is a FAIL.
#   powershell -ExecutionPolicy Bypass -File tools\soak-phone.ps1 [-Chunks 6] [-ChunkMinutes 40] [-Replays "a.sdfz","b.sdfz"]
# Without -Replays: the largest replays in the phone's files/bar/demos, in turn. The dev phone only.
param([int]$Chunks = 6, [int]$ChunkMinutes = 40, [string[]]$Replays = @(), [string]$Device = "", [string]$Who = "soak")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:ANDROID_USER_HOME = Join-Path $TC "home\.android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
if (-not $Device) { throw "no dev phone (BARDROID_DEVICE, or ..\phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$lockTool = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\devphone-lock.ps1"
$ChunkMinutes = [math]::Min($ChunkMinutes, 40)
$resultDir = Join-Path (Split-Path -Parent $PSScriptRoot) "build\phone-round"
New-Item -ItemType Directory -Force $resultDir | Out-Null
$result = Join-Path $resultDir "$(Get-Date -Format 'yyyyMMdd-HHmm')-soak.txt"

function Say([string]$line) { Write-Host $line; Add-Content -Encoding utf8 $result $line }
function InApp([string]$command) { & $adb -s $Device exec-out run-as $pkg sh -c $command }
function Lines([string]$file) { $n = 0; [void][int]::TryParse("$(InApp "wc -l < $file 2>/dev/null")".Trim(), [ref]$n); $n }
function LowMemorySince([string]$since) {   # (Android's exit records, newest first; as tools\phone-round.ps1)
  $ts = ""; $n = 0
  foreach ($l in (& $adb -s $Device shell dumpsys activity exit-info $pkg)) {
    if ($l -match 'timestamp=(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { $ts = $Matches[1] }
    elseif ($l -match 'reason=3 \(LOW_MEMORY\)' -and $ts -and $ts -ge $since) { $n++ }
  }
  $n
}

if (-not $Replays) {
  $Replays = @(InApp "cd files/bar/demos 2>/dev/null && ls -S *.sdfz 2>/dev/null | head -$Chunks" | ForEach-Object { "$_".Trim() } |
    Where-Object { $_ })
}
if (-not $Replays) { throw "no replays in the phone's files/bar/demos: name some with -Replays" }
Say "soak on the dev phone: $Chunks chunks of $ChunkMinutes min, replays at 1x: $($Replays -join ' | ')"
$total = @{ fault = 0; lowmem = 0; errors = 0; fails = 0 }
for ($i = 0; $i -lt $Chunks; $i++) {
  $replay = $Replays[$i % $Replays.Count]
  $taken = & $lockTool take $Who -Minutes ($ChunkMinutes + 5)
  if ("$taken" -notmatch '^taken') { Say "chunk $($i + 1): the dev phone busy ($taken): waiting 5 min"; Start-Sleep 300; $i--; continue }
  try {
    & $adb -s $Device shell am force-stop $pkg
    $since = "$(& $adb -s $Device shell date '+%Y-%m-%d %H:%M:%S')".Trim()
    $from = Lines "files/logs/launcher.log"
    InApp "rm -f files/bar/infolog.txt files/bar/.bardroid-bench-settings; echo '0 $($ChunkMinutes * 60 - 120) $replay' > files/bar/.bardroid-bench-replay" | Out-Null
    & $adb -s $Device shell "input keyevent KEYCODE_WAKEUP" | Out-Null
    & $adb -s $Device shell "am start -n $pkg/.LauncherActivity --es start bench" | Out-Null
    $t0 = Get-Date; $ended = "time"
    while (((Get-Date) - $t0).TotalMinutes -lt $ChunkMinutes) {
      Start-Sleep 20
      $now = Lines "files/logs/launcher.log"
      $start = if ($now -lt $from) { 1 } else { $from + 1 }   # (the log put aside as launcher.old.log meanwhile: all of it)
      $new = "$(InApp "tail -n +$start files/logs/launcher.log | grep -a -E 'engine exited|game ended|lack of memory|replaybench\] done' | tail -1")".Trim()
      if ("$(InApp "grep -a -c 'replaybench\] done' files/bar/infolog.txt 2>/dev/null")".Trim() -ne "0") { $ended = "replay done"; break }
      if ($new -match 'lack of memory') { $ended = "Android ended the app for memory"; break }
      if ($new -match 'engine exited \(([1-9]\d*)\)|game ended with an error') { $ended = "the engine's error exit: $new"; break }
      if (-not "$(& $adb -s $Device shell pidof $pkg)".Trim()) { $ended = "the app gone"; break }
    }
    $minutes = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
    $now = Lines "files/logs/launcher.log"
    $start = if ($now -lt $from) { 1 } else { $from + 1 }
    $log = @(InApp "tail -n +$start files/logs/launcher.log")
    $faults = @($log | Where-Object { $_ -match 'GPU driver refused' }).Count
    $errors = @($log | Where-Object { $_ -match 'engine exited \([1-9]|game ended with an error' }).Count
    $thermal = @($log | ForEach-Object { if ($_ -match '\[perf\] thermal (\d+)') { [int]$Matches[1] } })
    $steps = 0; for ($k = 1; $k -lt $thermal.Count; $k++) { if ($thermal[$k] -ne $thermal[$k - 1]) { $steps++ } }
    $tmax = if ($thermal) { ($thermal | Measure-Object -Maximum).Maximum } else { "?" }
    $fps = @(InApp "grep -a -o '\[bardroid-perf\] [0-9.]* fps' files/bar/infolog.txt 2>/dev/null" |
      ForEach-Object { if ("$_" -match '\] ([0-9.]+) fps') { [double]$Matches[1] } })
    if (-not $fps) {   # (the bench's own lines, every few seconds: "[replaybench] 12:30 x1.00 (...), 812 units, 29 fps")
      $fps = @(InApp "grep -a -o 'units, [0-9]* fps' files/bar/infolog.txt 2>/dev/null" |
        ForEach-Object { if ("$_" -match ', (\d+) fps') { [double]$Matches[1] } })
    }
    $fpsText = if ($fps) { "fps min $([math]::Round(($fps | Measure-Object -Minimum).Minimum, 1)), mean $([math]::Round(($fps | Measure-Object -Average).Average, 1)) over $($fps.Count) min" } else { "no fps lines" }
    $lowmem = LowMemorySince $since
    $total.fault += $faults; $total.lowmem += $lowmem; $total.errors += $errors
    # (known classes: the driver's refusal, a low-memory kill; anything else that ended a chunk early is new)
    $known = $ended -in @("time", "replay done") -or $ended -match 'for memory' -or ($ended -eq "the app gone" -and $lowmem -gt 0) -or
      ($ended -match 'error exit' -and $faults -gt 0)
    $verdict = if ($known) { "PASS" } else { $total.fails++; "FAIL" }
    Say ("{0}  chunk {1} ({2}): {3} min, {4}; driver refusals {5}, low-memory kills {6}, engine errors {7}; thermal max {8}, {9} steps; {10}" -f
      $verdict, ($i + 1), $replay, $minutes, $ended, $faults, $lowmem, $errors, $tmax, $steps, $fpsText)
  } finally {
    InApp "rm -f files/bar/.bardroid-bench-replay" | Out-Null
    & $adb -s $Device shell am force-stop $pkg
    & $lockTool free $Who | Out-Null
  }
  Start-Sleep 20
}
& (Join-Path $PSScriptRoot "devphone.ps1") dark | Out-Null
Say ("soak: {0} chunks, {1} new-fault chunks; driver refusals {2}, low-memory kills {3}, engine errors {4}" -f $Chunks,
  $total.fails, $total.fault, $total.lowmem, $total.errors)
Say "results: $result"
exit $total.fails
