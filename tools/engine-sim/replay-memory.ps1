# A big replay's memory on the dev phone with an engine branch build (docs/ENGINE-SIM.md): sets the engine, extra
# springsettings lines and the replay, starts the replay benchmark, and every 20 s logs memory available, the GPU
# driver's memory (GpuTotal), whether the engine runs and the replay's progress, until the replay benchmark is done,
# Android's low-memory killer ends it, or -Minutes pass. Then cleans up (dev-env, dev-springsettings, replay flag).
#   replay-memory.ps1 -Engine gcc-sim1 -Settings "ProjectileAtlasDownscale = 2" [-Replay isthmus8v8-20261013a.sdfz] [-Skip 600] [-Seconds 30]
#     [-DevEnv "export BARDROID_TEX_LOG=1"] (lines added to dev-env.sh) [-KillAll] (background apps closed first) [-Pacer] (dev-env-pacer.sh)
#     [-Timers] (the engine's profiler on: the busiest timers every 10 s in the infolog, bardroid_simdraw.lua)
#     [-Widgets] (every widget's call-ins timed: the busiest widgets every 10 s)
#     [-Shots <game second>] (three screenshots from that second, close to where the units are thickest, the same in every run of a replay: <run>-shot1..3.png)
# Every run logs the main thread's Sim / Draw / rest split every 10 s ([simdraw], bardroid_simdraw.lua) and keeps the
# phone's springsettings.cfg as it was before the run.
# The launcher.log of the run (the app starts a new one at each start) is kept beside the log as <...>-launcher.log (tools/tex-memory.py reads it with the texture log on).
param([string]$Engine = "gcc-sim1", [string[]]$Settings = @(), [string]$Replay = "isthmus8v8-20261013a.sdfz",
      [int]$Skip = 600, [int]$Seconds = 30, [int]$Minutes = 25, [string]$Device = "R5CW22GVC3D", [string[]]$DevEnv = @(),
      [switch]$KillAll, [string]$Label = "", [int]$Every = 20, [switch]$Pacer, [switch]$Timers, [switch]$Widgets, [switch]$HideUi, [switch]$NoDeferred, [int]$Shots = 0)
$ErrorActionPreference = "Continue"
# one run at a time: a run started while the last one still cleans up was force-stopped by it (2026-11-05)
$lock = "C:\Tools\BARANDROID\engine-sim\replay-memory.lock"
for ($w = 0; (Test-Path $lock) -and $w -lt 360; $w++) {
  $owner = 0; [void][int]::TryParse("$(Get-Content $lock -ErrorAction SilentlyContinue)".Trim(), [ref]$owner)
  if ($owner -le 0 -or -not (Get-Process -Id $owner -ErrorAction SilentlyContinue)) { break }
  if ($w -eq 0) { "waiting for the run in process $owner to end" }
  Start-Sleep 5
}
"$PID" | Set-Content $lock
$tools = Split-Path $PSScriptRoot
. (Join-Path $tools "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$tmp = Join-Path $TC "tmp"
function AppRun([string]$text, [string]$name) {
  $f = Join-Path $tmp $name
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use $Engine -Device $Device | Out-Null
if ($Engine -eq "official") { & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Off -Device $Device | Out-Null }
if ($Pacer) {   # (the memory pacer, dev-env-pacer.sh: the engine paused while Android's available memory is low)
  Send-AppFile $adb "$PSScriptRoot\dev-env-pacer.sh" "files/bar/dev-env-pacer.sh" $Device
  AppRun "cat files/bar/dev-env-pacer.sh >> files/bar/dev-env.sh; rm -f files/bar/dev-env-pacer.sh" "es-rm-pacer.sh" | Out-Null
}
if ($DevEnv.Count) { AppRun ("printf '%s\n' " + (($DevEnv | ForEach-Object { "'$_'" }) -join ' ') + " >> files/bar/dev-env.sh") "es-rm-env.sh" | Out-Null }
$ss = if ($Settings.Count) { "printf '%s\n' " + (($Settings | ForEach-Object { "'$_'" }) -join ' ') + " > files/bar/dev-springsettings.cfg" } else { "rm -f files/bar/dev-springsettings.cfg" }
# bardroid_simdraw.lua: the main thread's Sim / Draw / rest split every 10 s in the infolog ([simdraw])
Send-AppFile $adb "$PSScriptRoot\bardroid_simdraw.lua" "files/bar/LuaUI/Widgets/bardroid_simdraw.lua" $Device
$modes = @()   # (built one by one: @($(if ...), $(if ...)) came out empty when only the last switch was set)
if ($Timers) { $modes += "timers" }; if ($Widgets) { $modes += "widgets" }; if ($HideUi) { $modes += "hideui" }
if ($NoDeferred) { $modes += "nodeferred" }; if ($Shots) { $modes += "shots $Shots" }
AppRun $(if ($modes.Count) { "echo '$($modes -join ' ')' > files/bar/LuaUI/Config/bardroid_simdraw.txt" } else { "rm -f files/bar/LuaUI/Config/bardroid_simdraw.txt" }) "es-rm-timers.sh" | Out-Null
# (springsettings.cfg kept as it was: launch-bar.sh appends dev-springsettings.cfg to it and the engine saves it at exit)
AppRun "$ss; cp files/bar/springsettings.cfg files/bar/.springsettings-before-run; printf '%s\n' '$Skip $Seconds $Replay' > files/bar/.bardroid-bench-replay; rm -f files/bar/infolog.txt; echo 'engine $Engine; settings: $($Settings -join ', ')'" "es-rm0.sh"
$lmk0 = [int](AppRun "grep -c 'ended for lack of memory' files/logs/launcher.log" "es-rm1.sh")
$lines0 = [int]("$(AppRun 'wc -l < files/logs/launcher.log' 'es-rm-lines.sh')".Trim())   # (this run's lines follow)
if ($KillAll) { & $adb -s $Device shell "am kill-all" | Out-Null }
& $adb -s $Device shell "am force-stop com.underarmcape.bardroid; sleep 1; am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench >/dev/null"
$t0 = Get-Date
$minAvail = 1e9; $maxGpu = 0; $state = "running"; $seen = $false
do {
  Start-Sleep $Every
  $m = @(& $adb -s $Device shell "grep -E 'MemAvailable|GpuTotal|SwapFree' /proc/meminfo | tr -s ' ' | cut -d' ' -f2; ps -A | grep -c ' spring$'; p=`$(pidof spring); grep -E 'VmRSS|VmSwap' /proc/`$p/status 2>/dev/null | tr -s ' ' | cut -d' ' -f2")
  $avail = [int]($m[0]) / 1024; $swap = [int]($m[1]) / 1024; $gpu = [int]($m[2]) / 1024; $running = [int]($m[3])
  $rss = if ($m.Count -gt 4) { [int]($m[4]) / 1024 } else { 0 }; $eswap = if ($m.Count -gt 5) { [int]($m[5]) / 1024 } else { 0 }
  if ($running) { $seen = $true; $minAvail = [math]::Min($minAvail, $avail); $maxGpu = [math]::Max($maxGpu, $gpu) }
  $prog = "$(AppRun "grep -E 'replaybench\] (done|fast|measuring|[0-9]+:[0-9]+ x)' files/bar/infolog.txt | tail -1 | cut -c1-140; grep -c 'ended for lack of memory' files/logs/launcher.log" 'es-rm2.sh')"
  "$((Get-Date).ToString('HH:mm:ss')) avail $([int]$avail) MB, swap free $([int]$swap) MB, GPU $([int]$gpu) MB, engine $running ($([int]$rss) MB in RAM, $([int]$eswap) MB swapped) | $prog"
  if ($prog -match 'done \(') { $state = "done"; break }
  # (the GPU driver's "submit failed ... Resource deadlock avoided", then the engine's watchdog: it never comes back)
  if ("$(AppRun "grep -c 'Watchdog\] Hang detection' files/bar/infolog.txt 2>/dev/null" 'es-rm-hang.sh')".Trim() -match '^[1-9]') {
    $state = "engine hung (watchdog; GPU driver: $("$(AppRun "grep -c 'submit failed' files/logs/launcher.log" 'es-rm-hang2.sh')".Trim()) failed submits)"; break
  }
  if ([int](($prog -split '\s+')[-1]) -gt $lmk0) { $state = "killed (low memory)"; break }
  if ($seen -and -not $running) { $state = "engine gone (not by low memory as the app saw it)"; break }
} while (((Get-Date) - $t0).TotalMinutes -lt $Minutes)
"result: $state; lowest memory available $([int]$minAvail) MB, GPU driver up to $([int]$maxGpu) MB"
AppRun "grep -E 'replaybench\]|simdraw\]|DESYNC' files/bar/infolog.txt | tail -12 | cut -c1-200; rm -f files/bar/dev-env.sh files/bar/dev-springsettings.cfg files/bar/.bardroid-bench-replay" "es-rm3.sh"
$keep = "C:\Tools\BARANDROID\engine-sim\runs\$((Get-Date).ToString('yyyyMMdd-HHmmss'))-mem-$Engine$(if ($Label) { '-' + $Label })"
& cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid tail -n +$($lines0 + 1) files/logs/launcher.log > `"$keep-launcher.log`""
& cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid cat files/bar/infolog.txt > `"$keep-infolog.txt`""
"launcher.log and infolog of the run: $keep-launcher.log, -infolog.txt"
if ($Shots) {   # (the engine's screenshots of this run, oldest first, kept beside the logs and taken off the phone)
  $names = @("$(AppRun 'ls -tr files/bar/screenshots/*.png 2>/dev/null | tail -3' 'es-rm-shots.sh')" -split '\s+' | Where-Object { $_ })
  for ($i = 0; $i -lt $names.Count; $i++) {
    & cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid cat $($names[$i]) > `"$keep-shot$($i + 1).png`""
  }
  AppRun "rm -f files/bar/screenshots/*.png" "es-rm-shots2.sh" | Out-Null
  "screenshots: $($names.Count) ($keep-shot1.png ...)"
}
& $adb -s $Device shell "am force-stop com.underarmcape.bardroid" | Out-Null
# (the run's settings out of springsettings.cfg again: the engine saved them there, as PreloadModels = 0 stayed for
# every later game, 2026-11-04), and the dev widget out of LuaUI/Widgets
AppRun "[ -f files/bar/.springsettings-before-run ] && mv files/bar/.springsettings-before-run files/bar/springsettings.cfg; rm -f files/bar/LuaUI/Widgets/bardroid_simdraw.lua files/bar/LuaUI/Config/bardroid_simdraw.txt" "es-rm4.sh" | Out-Null
Remove-Item $lock -ErrorAction SilentlyContinue
