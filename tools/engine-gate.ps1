# The gate a phone engine build passes before it ships (docs/ENGINE-DEFAULT.md stage 2), on the dev phone with the APK
# that carries the build installed (the app's default engine is then that build, as players get it):
#   engine-gate.ps1 -Version <engine> -Replays <a.sdfz>,... [-OffReplays <b.sdfz>,...] [-Tests all|none|<name>,...]
#                   [-Who engine-gate] [-Device <serial>]
# - the launch line: launcher.log's "phone engine: phone-<Version>-..." for every replay's start, and the build's
#   "[BarDroidSim]" line in its infolog (it ran);
# - each -Replays file to its end with the switches as shipped (a replay: the simulation rewrite as set, on), each
#   -OffReplays file with every switch of the rewrite at 0 (stock code: what an online game runs): 0 "[DESYNC WARNING]"
#   lines and the end reached ("End of demo reached", or the game over before it). Server replays of the engine
#   version only (BAR's replay site: api.bar-rts.com/replays; the replay's game and map installed on the phone);
#   bar-droid-engine tools\engine-sim\phone-engine.ps1 -Replay -Engine default runs each (its infolog in
#   C:\Tools\BARANDROID\engine-sim\runs);
# - the phone tests: dock-phone-test, touch-phone-test, pad-test, pad-test -Online, pace-test, lobby-phone-test,
#   remake-check (a test passes with a PASS line and no FAIL line).
# The dev phone is taken through devphone-lock.ps1 for each item and freed after it (sessions side by side take turns).
# Not here: BAR's benchmark against the official engine and the Fold7's day of games (stage 2's last two).
# The summary: build\engine-gate-<Version>.txt; the exit code is the number of items failed.
param([Parameter(Mandatory)][string]$Version, [string[]]$Replays = @(), [string[]]$OffReplays = @(),
      [string[]]$Tests = @("all"), [string]$Who = "engine-gate", [string]$Device = "")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
$lockTool = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\devphone-lock.ps1"
$replayTool = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\phone-engine.ps1"
$root = Split-Path $PSScriptRoot
New-Item -ItemType Directory -Force "$root\build" | Out-Null
$summary = "$root\build\engine-gate-$Version.txt"
# (every switch of the simulation rewrite at 0: what BarDroidSimAllowed makes of them in an online game)
$off = @("BarDroidMoveAll = 0", "BarDroidUnitsAll = 0", "BarDroidLuaVM = 0", "BarDroidLuaFastCall = 0",
         "BarDroidLuaFastCompare = 0", "BarDroidLuaFastIter = 0", "BarDroidLuaFastTable = 0", "BarDroidLuaPrefetch = 0",
         "BarDroidLuaStrHash = 0", "BarDroidLuaAllocRelaxed = 0", "BarDroidForGrain = 0", "BarDroidPrevSkip = 0")
$results = New-Object System.Collections.Generic.List[string]
$failed = 0
function Note([string]$line) { $line; $script:results.Add($line) }
function Take { & powershell -ExecutionPolicy Bypass -File $lockTool take $Who -Minutes 50 | Out-Host }
function Free { & powershell -ExecutionPolicy Bypass -File $lockTool free $Who | Out-Host }
function AppLog([string]$cmd) {
  $f = Join-Path $TC "tmp\engine-gate.sh"
  [IO.File]::WriteAllText($f, ($cmd -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  "$(Invoke-AppScript $adb $f $Device)".Trim()
}

function Run-Replay([string]$file, [bool]$switchesOff) {
  $name = Split-Path $file -Leaf
  $label = "replay $name, $(if ($switchesOff) { 'every switch off' } else { 'switches as shipped' })"
  # (game second 9000: past the end, so the whole replay is simulated, every frame checked against the players' checksums)
  $p = @{ Replay = $file; Engine = "default"; Skip = 9000; Seconds = 30; Timeout = 3600; Device = $Device }
  if ($switchesOff) { $p.Settings = $off }
  Take
  try { $out = & $replayTool @p 2>&1 | ForEach-Object { "$_" } } catch { $out = @("$_") } finally { Free }
  $out | Select-Object -Last 12 | Out-Host
  $line = $out | Where-Object { $_ -match 'desync warnings' } | Select-Object -Last 1
  $infolog = if ($line -match 'infolog (.+\.txt)$') { $Matches[1] } else { "" }
  $desync = if ($line -match ': (\d+) desync warnings') { [int]$Matches[1] } else { -1 }
  $log = if ($infolog -and (Test-Path $infolog)) { Get-Content $infolog } else { @() }
  $end = $log | Select-String -Pattern 'End of demo reached|[Gg]ame ?[Oo]ver' | Select-Object -First 1
  $ran = $log | Select-String -SimpleMatch "[BarDroidSim]" | Select-Object -First 1
  $ver = $log | Select-String -Pattern 'Spring Engine Version: (.+)$' | Select-Object -First 1
  $launch = AppLog "grep -E 'phone engine: |official engine ' files/logs/launcher.log | tail -n 1"
  $ok = ($desync -eq 0) -and $end -and $ran -and ($launch -match "phone engine: phone-$([regex]::Escape($Version))-")
  if (-not $ok) { $script:failed++ }
  Note ("{0} {1}: {2} desync warnings, {3}; launch: {4}; engine: {5}; infolog {6}" -f $(if ($ok) { "PASS" } else { "FAIL" }),
    $label, $desync, $(if ($end) { ($end.Line -replace '^\[t=[^\]]+\]', '').Trim() } else { "the end not reached" }),
    ($launch -replace '^.*\] ', ''), $(if ($ver) { $ver.Matches[0].Groups[1].Value } else { "?" }), $infolog)
}

function Run-Test([string]$script, [string[]]$extra = @()) {
  $label = "$script $($extra -join ' ')".Trim()
  Take
  try { $out = & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$script.ps1") @extra 2>&1 | ForEach-Object { "$_" } } finally { Free }
  $out | Out-Host
  $fails = @($out | Where-Object { $_ -match '\bFAIL(ED)?\b' })
  $ok = ($fails.Count -eq 0) -and ($out | Where-Object { $_ -match '\bPASS\b' })
  if (-not $ok) { $script:failed++ }
  Note ("{0} {1}{2}" -f $(if ($ok) { "PASS" } else { "FAIL" }), $label, $(if ($fails.Count) { ": " + (($fails | Select-Object -First 3) -join " / ") } else { "" }))
}

Note "engine gate for $Version on $Device, $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"
foreach ($r in $Replays) { Run-Replay $r $false }
foreach ($r in $OffReplays) { Run-Replay $r $true }
$all = @(@("dock-phone-test"), @("touch-phone-test"), @("pad-test"), @("pad-test", "-Online"), @("pace-test"),
         @("lobby-phone-test"), @("remake-check"))
foreach ($t in $all) {
  if ($Tests -contains "none") { break }
  if (-not ($Tests -contains "all" -or $Tests -contains (($t -join ' ')))) { continue }
  Run-Test $t[0] @($t | Select-Object -Skip 1)
}
Note "engine gate for ${Version}: $(if ($failed -eq 0) { 'ALL PASS' } else { "$failed FAILED" })"
[IO.File]::WriteAllText($summary, (($results -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
"summary: $summary"
exit $failed
