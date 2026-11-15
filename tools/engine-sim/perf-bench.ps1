# Where an engine branch build spends its CPU in BAR's benchmark fight on the dev phone (docs/ENGINE-SIM.md):
# simpleperf samples the engine (user space, every 0.5 ms of CPU: -c, as -f fails from the app, which may not raise the sample-rate property) for -Seconds, from -After seconds past "Starting Benchmark",
# then reports per thread and per function on the laptop (the build's own binary with its symbol table as symfs).
#   perf-bench.ps1 -Engine gcc-sim1 [-After 40] [-Seconds 40] [-Top 40] [-Record "--call-graph dwarf"]
param([string]$Engine = "gcc-sim1", [int]$After = 40, [int]$Seconds = 40, [int]$Top = 40, [string]$Record = "", [string]$Device = "R5CW22GVC3D")
$ErrorActionPreference = "Continue"
$tools = Split-Path $PSScriptRoot
. (Join-Path $tools "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$sp = Join-Path $TC "android-sdk\ndk\29.0.14206865\simpleperf\bin"
$tmp = Join-Path $TC "tmp"
function AppRun([string]$text, [string]$name) {
  $f = Join-Path $tmp $name
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
if ("$(AppRun '[ -x files/simpleperf ] && echo yes' 'es-pf0.sh')".Trim() -ne "yes") { Send-AppFile $adb "$sp\android\arm64\simpleperf" "files/simpleperf" $Device; AppRun "chmod 755 files/simpleperf" "es-pf1.sh" | Out-Null }
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use $Engine -Device $Device | Out-Null
if ($Engine -eq "official") { & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use official -Device $Device | Out-Null }
AppRun "rm -f files/bar/.bardroid-bench-replay files/bar/infolog.txt files/es-perf.data" "es-pf2.sh" | Out-Null
& $adb -s $Device shell "setprop security.perf_harden 0; am force-stop com.underarmcape.bardroid; sleep 1; input keyevent KEYCODE_WAKEUP; am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench" | Out-Null
Start-Sleep 5
AppRun @"
i=0; while ! grep -q 'Starting Benchmark' files/bar/infolog.txt 2>/dev/null; do sleep 1; i=`$((i+1)); [ `$i -gt 400 ] && exit 1; done
sleep $After
pid=`$(pidof recoil-main || pidof spring)
files/simpleperf record -p `$pid -e cpu-cycles:u -c 500000 $Record --duration $Seconds -o files/es-perf.data 2>&1 | tail -n 1
"@ "es-pf3.sh"
& $adb -s $Device shell "setprop security.perf_harden 1" | Out-Null
$out = "C:\Tools\BARANDROID\engine-sim\runs\$((Get-Date).ToString('yyyyMMdd-HHmmss'))-perf-$Engine"
& cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid cat files/es-perf.data > `"$out.data`""
Start-Sleep 60   # (the benchmark ends itself; the next start removes dev-env)
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Off -Device $Device | Out-Null
& $adb -s $Device shell "am force-stop com.underarmcape.bardroid" | Out-Null
# symfs: the binary at the path the phone mapped it from
$symfs = "C:\Tools\BARANDROID\engine-sim\symfs"
$bin = "$symfs\data\data\com.underarmcape.bardroid\files\bar\engine-sim\$Engine"
New-Item -ItemType Directory -Force $bin | Out-Null
Copy-Item "C:\Tools\BARANDROID\engine-sim\out\$Engine\spring" "$bin\spring" -Force
& "$sp\windows\x86_64\simpleperf.exe" report -i "$out.data" --symfs $symfs --sort comm --percent-limit 1 2>$null | Select-Object -Skip 6 | Out-File -Encoding utf8 "$out-threads.txt"
& "$sp\windows\x86_64\simpleperf.exe" report -i "$out.data" --symfs $symfs --comms recoil-main --sort symbol --percent-limit 0.4 2>$null | Out-File -Encoding utf8 "$out-main.txt"
"threads:"; Get-Content "$out-threads.txt" | Select-Object -First 14
"main thread, by function:"; Get-Content "$out-main.txt" | Select-Object -Skip 6 -First $Top
