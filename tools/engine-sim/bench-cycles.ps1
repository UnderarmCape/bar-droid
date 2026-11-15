# BAR's benchmark scenario on the dev phone, counted in CPU work instead of time (docs/ENGINE-SIM.md): the phone's
# clocks swing with its heat from run to run (the big cores' cluster at 864 MHz in one run, 1843 MHz in the next), so
# wall-time comparisons of engine builds need many runs; instructions and cycles per simulated frame do not depend on
# the clock. simpleperf counts the engine's user-space instructions and cycles (all threads, and the main thread on
# its own) from "Starting Benchmark" (game frame 15) to "Benchmark Results" (frame 2017).
#   bench-cycles.ps1 -Engines official,gcc-stock,gcc-sim1 [-Rounds 2]   ("+auto", "+allcpu" as in bench-engines.ps1)
# Rows: C:\Tools\BARANDROID\engine-sim\runs\cycles.csv
param([string[]]$Engines = @("official", "gcc-stock"), [int]$Rounds = 1, [string]$Device = "R5CW22GVC3D")
$ErrorActionPreference = "Continue"
$Engines = @($Engines | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$tools = Split-Path $PSScriptRoot
. (Join-Path $tools "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$csv = "C:\Tools\BARANDROID\engine-sim\runs\cycles.csv"
if (-not (Test-Path $csv)) { '"when","engine","round","frames","instr_all_M","cycles_all_M","instr_main_M","cycles_main_M","instr_per_frame_M","cycles_per_frame_M","main_cycles_per_frame_M","cpu_mask","seconds"' | Out-File -Encoding utf8 $csv }
$tmp = Join-Path $TC "tmp"
function AppRun([string]$text, [string]$name) {
  $f = Join-Path $tmp $name
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
$sp = Join-Path $TC "android-sdk\ndk\29.0.14206865\simpleperf\bin\android\arm64\simpleperf"
if ("$(AppRun '[ -x files/simpleperf ] && echo yes' 'es-c0.sh')".Trim() -ne "yes") { Send-AppFile $adb $sp "files/simpleperf" $Device; AppRun "chmod 755 files/simpleperf" "es-c1.sh" | Out-Null }
# (on the phone: waits for the fight's start, counts until its results, prints frames and counts)
$watch = @'
i=0
while ! grep -q 'Starting Benchmark' files/bar/infolog.txt 2>/dev/null; do sleep 1; i=$((i+1)); [ $i -gt 400 ] && { echo "no start"; exit 1; }; done
pid=$(pidof recoil-main || pidof spring)
mask=$(grep Cpus_allowed_list /proc/$pid/status | cut -f2)
f0=$(grep 'Starting Benchmark' files/bar/infolog.txt | head -1 | grep -o 'f=[0-9]*' | cut -d= -f2)
files/simpleperf stat -p $pid -e instructions:u,cpu-cycles:u --per-thread -o files/es-stat.txt --duration 1200 >/dev/null 2>&1 &
sp=$!
t0=$(date +%s)
while ! grep -q 'Benchmark Results' files/bar/infolog.txt 2>/dev/null; do sleep 1; [ -d /proc/$pid ] || { echo "engine gone"; break; }; done
kill -INT $sp; wait $sp
f1=$(grep 'Benchmark Results' files/bar/infolog.txt | head -1 | grep -o 'f=[0-9]*' | cut -d= -f2)
echo "frames $f0 $f1 seconds $(( $(date +%s) - t0 )) mask $mask main $pid"
cat files/es-stat.txt
'@
foreach ($r in 1..$Rounds) {
  foreach ($spec in $Engines) {
    $e = $spec -replace '\+auto|\+allcpu', ''
    $ds = if ($spec -match '\+auto') { "printf 'WorkerThreadCount = -1\nThreadPinPolicy = 1\n' > files/bar/dev-springsettings.cfg" } else { "rm -f files/bar/dev-springsettings.cfg" }
    AppRun $ds "es-c2.sh" | Out-Null
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use $e -Device $Device | Out-Null
    if ($e -eq "official") { & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use official -Device $Device | Out-Null }
    if ($spec -match '\+allcpu') {
      Send-AppFile $adb "$PSScriptRoot\dev-env-allcpu.sh" "files/bar/es-allcpu.txt" $Device
      AppRun "cat files/bar/es-allcpu.txt >> files/bar/dev-env.sh; rm -f files/bar/es-allcpu.txt" "es-c3.sh" | Out-Null
    }
    & $adb -s $Device shell "setprop security.perf_harden 0" | Out-Null
    # (the last run's infolog would answer the watcher at once: launch-bar.sh removes it only when the engine starts)
    AppRun "rm -f files/bar/.bardroid-bench-replay files/es-stat.txt files/bar/infolog.txt" "es-c4.sh" | Out-Null
    & $adb -s $Device shell "am force-stop com.underarmcape.bardroid; sleep 1; input keyevent KEYCODE_WAKEUP; am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench" | Out-Null
    Start-Sleep 5
    $out = @(AppRun $watch "es-c5.sh")
    & $adb -s $Device shell "setprop security.perf_harden 1" | Out-Null
    Start-Sleep 15
    & $adb -s $Device shell "am force-stop com.underarmcape.bardroid" | Out-Null
    $hdr = $out | Where-Object { $_ -match '^frames ' } | Select-Object -First 1
    if (-not $hdr) { "[$spec r$r] no result: $($out -join ' | ')"; continue }
    $p = $hdr -split ' '
    $frames = [int]$p[2] - [int]$p[1]
    # simpleperf stat --per-thread lines: <thread name> <pid> <tid> <count> <event> # ...; the main thread: tid = pid
    $iAll = 0.0; $cAll = 0.0; $iMain = 0.0; $cMain = 0.0
    foreach ($l in $out) {
      if ($l -match '^\s*(\S+)\s+(\d+)\s+(\d+)\s+([\d,]+)\s+(instructions:u|cpu-cycles:u)\b') {
        $v = [double]($Matches[4] -replace ',', '')
        $isMain = ($Matches[2] -eq $Matches[3])
        if ($Matches[5] -eq 'instructions:u') { $iAll += $v; if ($isMain) { $iMain += $v } } else { $cAll += $v; if ($isMain) { $cMain += $v } }
      }
    }
    if ($iAll -eq 0) { "[$spec r$r] counts not parsed:"; $out | Select-Object -First 30; continue }
    $row = '"{0}","{1}","{2}","{3}","{4:F0}","{5:F0}","{6:F0}","{7:F0}","{8:F2}","{9:F2}","{10:F2}","{11}","{12}"' -f (Get-Date -Format "yyyy-MM-dd HH:mm"), $spec, $r, $frames,
      ($iAll / 1e6), ($cAll / 1e6), ($iMain / 1e6), ($cMain / 1e6), ($iAll / 1e6 / $frames), ($cAll / 1e6 / $frames), ($cMain / 1e6 / $frames), $p[6], $p[4]
    $row | Out-File -Append -Encoding utf8 $csv
    "[$spec r$r] frames $frames, instructions $([math]::Round($iAll/1e6/$frames,1)) M/frame, cycles $([math]::Round($cAll/1e6/$frames,1)) M/frame (main $([math]::Round($cMain/1e6/$frames,1))), CPUs $($p[6]), $($p[4]) s"
  }
}
AppRun "rm -f files/bar/dev-springsettings.cfg files/es-stat.txt" "es-c6.sh" | Out-Null
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Off -Device $Device | Out-Null
