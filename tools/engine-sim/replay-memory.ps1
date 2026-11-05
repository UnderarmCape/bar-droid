# A big replay's memory on the dev phone with an engine branch build (docs/ENGINE-SIM.md): sets the engine, extra
# springsettings lines and the replay, starts the replay benchmark, and every 20 s logs memory available, the GPU
# driver's memory (GpuTotal), whether the engine runs and the replay's progress, until the replay benchmark is done,
# Android's low-memory killer ends it, or -Minutes pass. Then cleans up (dev-env, dev-springsettings, replay flag).
#   replay-memory.ps1 -Engine gcc-sim1 -Settings "ProjectileAtlasDownscale = 2" [-Replay isthmus8v8-20261013a.sdfz] [-Skip 600] [-Seconds 30]
#     [-DevEnv "export BARDROID_TEX_LOG=1"] (lines added to dev-env.sh) [-KillAll] (background apps closed first)
# The launcher.log of the run (the app starts a new one at each start) is kept beside the log as <...>-launcher.log (tools/tex-memory.py reads it with the texture log on).
param([string]$Engine = "gcc-sim1", [string[]]$Settings = @(), [string]$Replay = "isthmus8v8-20261013a.sdfz",
      [int]$Skip = 600, [int]$Seconds = 30, [int]$Minutes = 25, [string]$Device = "R5CW22GVC3D", [string[]]$DevEnv = @(),
      [switch]$KillAll, [string]$Label = "", [int]$Every = 20)
$ErrorActionPreference = "Continue"
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
if ($DevEnv.Count) { AppRun ("printf '%s\n' " + (($DevEnv | ForEach-Object { "'$_'" }) -join ' ') + " >> files/bar/dev-env.sh") "es-rm-env.sh" | Out-Null }
$ss = if ($Settings.Count) { "printf '%s\n' " + (($Settings | ForEach-Object { "'$_'" }) -join ' ') + " > files/bar/dev-springsettings.cfg" } else { "rm -f files/bar/dev-springsettings.cfg" }
AppRun "$ss; printf '%s\n' '$Skip $Seconds $Replay' > files/bar/.bardroid-bench-replay; rm -f files/bar/infolog.txt; echo 'engine $Engine; settings: $($Settings -join ', ')'" "es-rm0.sh"
$lmk0 = [int](AppRun "grep -c 'low memory' files/logs/launcher.log" "es-rm1.sh")
$lines0 = [int]("$(AppRun 'wc -l < files/logs/launcher.log' 'es-rm-lines.sh')".Trim())   # (this run's lines follow)
if ($KillAll) { & $adb -s $Device shell "am kill-all" | Out-Null }
& $adb -s $Device shell "am force-stop com.underarmcape.bardroid; sleep 1; am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench >/dev/null"
$t0 = Get-Date
$minAvail = 1e9; $maxGpu = 0; $state = "running"
do {
  Start-Sleep $Every
  $m = @(& $adb -s $Device shell "grep -E 'MemAvailable|GpuTotal|SwapFree' /proc/meminfo | tr -s ' ' | cut -d' ' -f2; ps -A | grep -c ' spring$'; p=`$(pidof spring); grep -E 'VmRSS|VmSwap' /proc/`$p/status 2>/dev/null | tr -s ' ' | cut -d' ' -f2")
  $avail = [int]($m[0]) / 1024; $swap = [int]($m[1]) / 1024; $gpu = [int]($m[2]) / 1024; $running = [int]($m[3])
  $rss = if ($m.Count -gt 4) { [int]($m[4]) / 1024 } else { 0 }; $eswap = if ($m.Count -gt 5) { [int]($m[5]) / 1024 } else { 0 }
  if ($running) { $minAvail = [math]::Min($minAvail, $avail); $maxGpu = [math]::Max($maxGpu, $gpu) }
  $prog = "$(AppRun "grep -E 'replaybench\] (done|fast|measuring|[0-9]+:[0-9]+ x)' files/bar/infolog.txt | tail -1 | cut -c1-140; grep -c 'low memory' files/logs/launcher.log" 'es-rm2.sh')"
  "$((Get-Date).ToString('HH:mm:ss')) avail $([int]$avail) MB, swap free $([int]$swap) MB, GPU $([int]$gpu) MB, engine $running ($([int]$rss) MB in RAM, $([int]$eswap) MB swapped) | $prog"
  if ($prog -match 'done \(') { $state = "done"; break }
  if ([int](($prog -split '\s+')[-1]) -gt $lmk0) { $state = "killed (low memory)"; break }
} while (((Get-Date) - $t0).TotalMinutes -lt $Minutes)
"result: $state; lowest memory available $([int]$minAvail) MB, GPU driver up to $([int]$maxGpu) MB"
AppRun "grep -E 'replaybench\]|DESYNC' files/bar/infolog.txt | tail -8 | cut -c1-200; rm -f files/bar/dev-env.sh files/bar/dev-springsettings.cfg files/bar/.bardroid-bench-replay" "es-rm3.sh"
# (launch-bar.sh appends dev-springsettings.cfg to the phone's springsettings.cfg and the engine saves it: the run's keys
# would stay for every later game, as PreloadModels = 0 did, 2026-11-04)
$keys = @($Settings | ForEach-Object { ($_ -split '=')[0].Trim() } | Where-Object { $_ -match '^\w+$' })
if ($keys.Count) { AppRun "sed -i -E '/^($($keys -join '|')) *=/d' files/bar/springsettings.cfg" "es-rm4.sh" | Out-Null }
$keep = "C:\Tools\BARANDROID\engine-sim\runs\$((Get-Date).ToString('yyyyMMdd-HHmmss'))-mem-$Engine$(if ($Label) { '-' + $Label })-launcher.log"
& cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid tail -n +$($lines0 + 1) files/logs/launcher.log > `"$keep`""
"launcher.log of the run: $keep"
& $adb -s $Device shell "am force-stop com.underarmcape.bardroid" | Out-Null
