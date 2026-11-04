# A big replay's memory on the dev phone with an engine branch build (docs/ENGINE-SIM.md): sets the engine, extra
# springsettings lines and the replay, starts the replay benchmark, and every 20 s logs memory available, the GPU
# driver's memory (GpuTotal), whether the engine runs and the replay's progress, until the replay benchmark is done,
# Android's low-memory killer ends it, or -Minutes pass. Then cleans up (dev-env, dev-springsettings, replay flag).
#   replay-memory.ps1 -Engine gcc-sim1 -Settings "ProjectileAtlasDownscale = 2" [-Replay isthmus8v8-20261013a.sdfz] [-Skip 600] [-Seconds 30]
param([string]$Engine = "gcc-sim1", [string[]]$Settings = @(), [string]$Replay = "isthmus8v8-20261013a.sdfz",
      [int]$Skip = 600, [int]$Seconds = 30, [int]$Minutes = 25, [string]$Device = "R5CW22GVC3D")
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
$ss = if ($Settings.Count) { "printf '%s\n' " + (($Settings | ForEach-Object { "'$_'" }) -join ' ') + " > files/bar/dev-springsettings.cfg" } else { "rm -f files/bar/dev-springsettings.cfg" }
AppRun "$ss; printf '%s\n' '$Skip $Seconds $Replay' > files/bar/.bardroid-bench-replay; rm -f files/bar/infolog.txt; echo 'engine $Engine; settings: $($Settings -join ', ')'" "es-rm0.sh"
$lmk0 = [int](AppRun "grep -c 'low memory' files/logs/launcher.log" "es-rm1.sh")
& $adb -s $Device shell "am force-stop com.underarmcape.bardroid; sleep 1; am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench >/dev/null"
$t0 = Get-Date
$minAvail = 1e9; $maxGpu = 0; $state = "running"
do {
  Start-Sleep 20
  $m = @(& $adb -s $Device shell "grep -E 'MemAvailable|GpuTotal' /proc/meminfo | tr -s ' ' | cut -d' ' -f2; ps -A | grep -c ' spring$'")
  $avail = [int]($m[0]) / 1024; $gpu = [int]($m[1]) / 1024; $running = [int]($m[2])
  if ($running) { $minAvail = [math]::Min($minAvail, $avail); $maxGpu = [math]::Max($maxGpu, $gpu) }
  $prog = "$(AppRun "grep -E 'replaybench\] (done|fast|measuring|[0-9]+:[0-9]+ x)' files/bar/infolog.txt | tail -1 | cut -c1-140; grep -c 'low memory' files/logs/launcher.log" 'es-rm2.sh')"
  "$((Get-Date).ToString('HH:mm:ss')) avail $([int]$avail) MB, GPU $([int]$gpu) MB, engine $running | $prog"
  if ($prog -match 'done \(') { $state = "done"; break }
  if ([int](($prog -split '\s+')[-1]) -gt $lmk0) { $state = "killed (low memory)"; break }
} while (((Get-Date) - $t0).TotalMinutes -lt $Minutes)
"result: $state; lowest memory available $([int]$minAvail) MB, GPU driver up to $([int]$maxGpu) MB"
AppRun "grep -E 'replaybench\]|DESYNC' files/bar/infolog.txt | tail -8 | cut -c1-200; rm -f files/bar/dev-env.sh files/bar/dev-springsettings.cfg files/bar/.bardroid-bench-replay" "es-rm3.sh"
& $adb -s $Device shell "am force-stop com.underarmcape.bardroid" | Out-Null
