# The container layer's cost in a late 8v8 on the dev phone (docs/CONTAINER-COST.md): plays the replay through
# replay-memory.ps1 (engine branch, bar-droid-engine's tools) and, once its measured part runs, probes the phone:
#   threads.sh 30 s (each thread's CPU and switches: engine, proot, X server, the app's renderer),
#   stopsample 20 s on the engine's main thread (time stopped by proot, by system call),
#   memory of each process (smaps_rollup), and afterwards the X server's and renderer's [display-cost] lines (logcat).
#   measure.ps1 [-Engine gcc-cut] [-Label x] [-Skip 1210] [-Seconds 120] [-DevEnv "line", ...] [-Settings "K = v", ...]
# Take the dev phone first (devphone-lock.ps1 take <who>); results in C:\Tools\BARANDROID\engine-sim\runs\<time>-cc-<label>*.
param([string]$Engine = "gcc-cut", [string]$Label = "base", [int]$Skip = 1210, [int]$Seconds = 120,
      [string[]]$DevEnv = @(), [string[]]$Settings = @(), [string]$Replay = "isthmus8v8-20261026.sdfz",
      [string]$Device = "")
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path $PSScriptRoot) "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }   # (the dev phone: ..\phone-device.txt, outside the repository)
$out = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "build\container-cost"
$runs = "C:\Tools\BARANDROID\engine-sim\runs"
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$base = "$runs\$stamp-cc-$Label"
& $adb -s $Device push "$PSScriptRoot\threads.sh" /data/local/tmp/bd-threads.sh | Out-Null
Send-AppFile $adb "$out\stopsample" "files/bd-stopsample" $Device
& $adb -s $Device shell "run-as com.underarmcape.bardroid chmod 755 files/bd-stopsample"
$since = "$(& $adb -s $Device shell 'date +%m-%d\ %H:%M:%S.000')".Trim()
$rm = "C:\Tools\BARANDROID\bar-droid-engine\tools\engine-sim\replay-memory.ps1"
$rmArgs = @("-ExecutionPolicy", "Bypass", "-File", $rm, "-Engine", $Engine, "-Replay", $Replay, "-Skip", $Skip, "-Seconds", $Seconds,
          "-Label", "cc-$Label", "-Minutes", 30)
if ($DevEnv.Count) { $rmArgs += "-DevEnv"; $rmArgs += $DevEnv }
if ($Settings.Count) { $rmArgs += "-Settings"; $rmArgs += $Settings }
$job = Start-Job -ScriptBlock { param($a) & powershell @a 2>&1 } -ArgumentList (, $rmArgs)
"replay running (job $($job.Id)); waiting for the measured part"
$t0 = Get-Date
while ($job.State -eq "Running") {
  Start-Sleep 10
  $m = "$(& $adb -s $Device shell "run-as com.underarmcape.bardroid grep -c 'replaybench\] measuring' files/bar/infolog.txt 2>/dev/null")".Trim()
  if ($m -match '^[1-9]') { break }
  if (((Get-Date) - $t0).TotalMinutes -gt 25) { break }
}
if ($job.State -eq "Running") {
  "measured part began $(Get-Date -Format HH:mm:ss)"
  Start-Sleep 10
  & $adb -s $Device shell "sh /data/local/tmp/bd-threads.sh 30" | Out-File -Encoding ascii "$base-threads.txt"
  $e = "$(& $adb -s $Device shell 'pidof spring || pidof recoil-main')".Trim()
  if ($e) {
    & $adb -s $Device shell "run-as com.underarmcape.bardroid files/bd-stopsample $e 20 2000 $e" | Out-File -Encoding ascii "$base-stops.txt"
    & $adb -s $Device exec-out run-as com.underarmcape.bardroid cat /proc/$e/maps | Out-File -Encoding ascii "$base-maps.txt"
    $mem = @'
for p in $(pidof com.underarmcape.bardroid) $(pidof bardroid-x11) $(pidof libproot.so) $(pidof spring); do
  echo "== $p $(cat /proc/$p/comm) $(grep -E '^(Rss|Pss|Pss_Anon|Pss_File|Pss_Shmem|SwapPss):' /proc/$p/smaps_rollup | tr -s ' ' | tr '\n' ' ')"
done
grep -E 'MemAvailable|GpuTotal' /proc/meminfo
cat /sys/class/kgsl/kgsl-3d0/gpubusy /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null
'@
    $f = Join-Path $TC "tmp\cc-mem.sh"
    [IO.File]::WriteAllText($f, ($mem -replace "`r", ""), (New-Object Text.ASCIIEncoding))
    Invoke-AppScript $adb $f $Device | Out-File -Encoding ascii "$base-mem.txt"
    # (how SurfaceFlinger shows the game: DEVICE = a display-hardware layer, CLIENT = composed on the GPU)
    & $adb -s $Device shell "dumpsys SurfaceFlinger | grep -E 'SurfaceView.*BLAST|composition type' | head -12" |
      Out-File -Encoding ascii -Append "$base-mem.txt"
  }
  "probes done $(Get-Date -Format HH:mm:ss)"
}
Receive-Job $job -Wait | Out-File -Encoding utf8 "$base-replay.txt"
Remove-Job $job
& $adb -s $Device shell "logcat -d -T '$since' | grep -E 'display-cost|LorieNative.*FPS|GPU fence'" | Out-File -Encoding utf8 "$base-display.txt"
"--- replay"; Get-Content "$base-replay.txt" | Select-Object -Last 14
"--- threads"; & "$PSScriptRoot\thrdiff.ps1" -File "$base-threads.txt" -Top 18
"--- stops"; Get-Content "$base-stops.txt" -ErrorAction SilentlyContinue
"--- memory"; Get-Content "$base-mem.txt" -ErrorAction SilentlyContinue
"--- display (last 12)"; Get-Content "$base-display.txt" | Select-Object -Last 12
"files: $base-*"
