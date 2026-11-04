# BAR's benchmark scenario on the dev phone with several engines, alternating (docs/ENGINE-SIM.md): the phone's CPU cap
# follows its heat from run to run, so each engine is measured next to the others, round after round.
#   bench-engines.ps1 -Engines official,gcc-stock,gcc-sim1 [-Rounds 2]
# Rows go to build\phone-bench.csv labelled es:<engine>:r<round>; the engine's own infolog of each run is kept in
# C:\Tools\BARANDROID\engine-sim\runs\ (its thread and core lines, the engine timers).
param([string[]]$Engines = @("official", "gcc-stock", "gcc-sim1"), [int]$Rounds = 2, [string]$Device = "R5CW22GVC3D")
$ErrorActionPreference = "Continue"
$Engines = @($Engines | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # (powershell -File passes "a,b" as one string)
$tools = Split-Path $PSScriptRoot
. (Join-Path $tools "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$runs = "C:\Tools\BARANDROID\engine-sim\runs"
New-Item -ItemType Directory -Force $runs | Out-Null
$first = $true
# "<build>+auto": that build with the engine's own thread choice (WorkerThreadCount -1, ThreadPinPolicy 1 = its system
# default) instead of the app's preset (4 workers, no pinning), through launch-bar.sh's dev-springsettings.cfg
$tmpf = Join-Path $TC "tmp\es-devss.sh"
function DevSettings([bool]$auto) {
  $text = if ($auto) { "printf 'WorkerThreadCount = -1\nThreadPinPolicy = 1\n' > files/bar/dev-springsettings.cfg" } else { "rm -f files/bar/dev-springsettings.cfg" }
  [IO.File]::WriteAllText($tmpf, $text, (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $tmpf $Device | Out-Null
}
# "+allcpu": the engine's threads allowed on every CPU (dev-env-allcpu.sh). It starts with a CPU mask that leaves out
# the dev phone's prime core 7 (0x3f, 0x5f, ...; 2026-11-04).
function AllCpu {
  $add = Join-Path $TC "tmp\es-allcpu.sh"
  Send-AppFile $adb "$PSScriptRoot\dev-env-allcpu.sh" "files/bar/es-allcpu.txt" $Device
  [IO.File]::WriteAllText($add, "cat files/bar/es-allcpu.txt >> files/bar/dev-env.sh; rm -f files/bar/es-allcpu.txt; tail -1 files/bar/dev-env.sh", (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $add $Device
}
foreach ($r in 1..$Rounds) {
  foreach ($spec in $Engines) {
    $e = $spec -replace '\+auto|\+allcpu', ''
    DevSettings ($spec -match '\+auto')
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Use $e -Device $Device
    if ($e -eq "official") { & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Off -Device $Device }
    if ($spec -match '\+allcpu') { AllCpu }
    $e = $spec
    # (phone-bench.ps1 writes build\phone-bench.csv in this worktree; -NoWarm after the first run: the phone stays hot)
    New-Item -ItemType Directory -Force (Join-Path (Split-Path $tools) "build") | Out-Null
    $args2 = @("-ExecutionPolicy", "Bypass", "-File", "$tools\phone-bench.ps1", "-Label", "es:${e}:r$r", "-Device", $Device)
    if (-not $first) { $args2 += "-NoWarm" }
    $first = $false
    & powershell @args2 2>&1 |
      Select-String -Pattern 'Sim|speed|fps|skin|rror' | Select-Object -Last 8 | ForEach-Object { "[$e r$r] $($_.Line)" }
    $f = "$runs\$((Get-Date).ToString('yyyyMMdd-HHmmss'))-bench-$e-r$r.txt"
    & $adb -s $Device exec-out run-as com.underarmcape.bardroid cat files/bar/infolog.txt | Out-File -Encoding utf8 $f
    Select-String -Path $f -Pattern 'CpuTopology|Optimal thread count|SetThreadCount\]\[2\]|Main thread affinity|thread affinity|Affinity Mask|Core Mask' |
      Select-Object -First 10 | ForEach-Object { "[$e r$r]   $($_.Line.Substring(0, [Math]::Min(170, $_.Line.Length)))" }
  }
}
DevSettings $false
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\phone-engine.ps1" -Off -Device $Device
