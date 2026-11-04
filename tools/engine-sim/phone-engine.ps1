# The engine branch's builds on the dev phone (docs/ENGINE-SIM.md), kept apart from the app's own engine:
#   phone-engine.ps1 -Install <build>   C:\Tools\BARANDROID\engine-sim\out\<build>\spring -> files/bar/engine-sim/<build>/
#                                       (every other file of the official engine dir linked, not copied)
#   phone-engine.ps1 -Use <build>       files/bar/dev-env.sh starts that engine at the next game start
#   phone-engine.ps1 -Off               dev-env.sh removed: the official engine again
#   phone-engine.ps1 -Replay <file.sdfz> -Engine <build|official> [-Skip 900] [-Seconds 120] [-Timeout 3600]
#       a replay through the app's replay benchmark with that engine: fast-forwards to game second -Skip (every frame
#       simulated and, in a replay BAR's server recorded, checked against every player's checksum), then measures the
#       game's speed for -Seconds. Prints the [DESYNC WARNING] count and the speed lines; the infolog goes to
#       C:\Tools\BARANDROID\engine-sim\runs\. The replay must be in the phone's demos/ (pushed from the laptop if it
#       is not), its game and map installed. Afterwards dev-env.sh is removed again. -Perf <seconds>: simpleperf on the
#       engine for that long once the measured part begins (the .perf.data beside the infolog). One run at a time.
param([string]$Install, [string]$Use, [switch]$Off, [string]$Replay, [string]$Engine = "official",
      [int]$Skip = 900, [int]$Seconds = 120, [int]$Timeout = 3600, [int]$Perf = 0, [string]$Device = "")
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot) "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
$ES = "C:\Tools\BARANDROID\engine-sim"
$official = "engine/recoil_2026.07.04"
$tmp = Join-Path $TC "tmp"
New-Item -ItemType Directory -Force $tmp | Out-Null

function App-Script([string]$text, [string]$name = "es.sh") {
  $f = Join-Path $tmp $name
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
function Set-DevEnv([string]$build) {
  if ($build -eq "official") { App-Script "rm -f files/bar/dev-env.sh; echo 'dev-env.sh removed'" ; return }
  App-Script @"
[ -x files/bar/engine-sim/$build/spring ] || { echo 'not installed: $build'; exit 1; }
printf '%s\n' '# engine branch (docs/ENGINE-SIM.md): phone-engine.ps1 -Use; -Off removes this file' 'ENGINE="`$BAR/engine-sim/$build"' 'log "engine-sim: `$ENGINE"' > files/bar/dev-env.sh
echo "dev-env.sh: engine-sim/$build"
"@
}

if ($Install) {
  $bin = "$ES\out\$Install\spring"
  if (-not (Test-Path $bin)) { throw "no build: $bin" }
  App-Script "mkdir -p files/bar/engine-sim/$Install"
  Send-AppFile $adb $bin "files/bar/engine-sim/$Install/spring" $Device
  App-Script @"
cd files/bar/engine-sim/$Install || exit 1
chmod 700 spring
for f in ../../$official/*; do n=`${f##*/}; [ "`$n" = spring ] || ln -sfn "`$f" "`$n"; done
echo "installed ${Install}:`$(ls | wc -l) entries, spring `$(wc -c < spring) bytes"
"@
}
if ($Use) { Set-DevEnv $Use }
if ($Off) { Set-DevEnv "official" }

if ($Replay) {
  $name = Split-Path $Replay -Leaf
  $have = App-Script "[ -f 'files/bar/demos/$name' ] && echo yes"
  if ($have -ne "yes") {
    if (-not (Test-Path $Replay)) { throw "replay not on the phone and not found here: $Replay" }
    Send-AppFile $adb $Replay "'files/bar/demos/$name'" $Device
  }
  Set-DevEnv $Engine
  App-Script "printf '%s\n' '$Skip $Seconds $name' > files/bar/.bardroid-bench-replay; echo 'replay set'"
  # (the end: one more "[svc] engine exited" line in launcher.log; the app's process stays after the game)
  $count = "grep -c 'svc\] engine exited' files/logs/launcher.log"
  $before = [int](App-Script $count "es-count.sh")
  & $adb -s $Device shell "am force-stop com.underarmcape.bardroid; sleep 1; am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench" | Out-Null
  $start = Get-Date
  $perfDone = -not $Perf
  $seen = $false   # (the engine's process seen; gone again = ended, also when Android's low-memory killer took the app)
  do {
    Start-Sleep 20
    $now = [int](App-Script $count "es-count.sh")
    $engine = "$(& $adb -s $Device shell 'pidof recoil-main || pidof spring')".Trim()
    if ($engine) { $seen = $true } elseif ($seen) { $now = $before + 1; "the engine's process is gone" }
    # -Perf: simpleperf on the engine (user space, 2000 samples a second) once the measured part has begun
    if (-not $perfDone -and "$(App-Script "grep -c 'replaybench\] measuring' files/bar/infolog.txt 2>/dev/null" "es-perf0.sh")".Trim() -ge 1) {
      $perfDone = $true
      $sp = Join-Path $TC "android-sdk\ndk\29.0.14206865\simpleperf\bin\android\arm64\simpleperf"
      if ("$(App-Script '[ -x files/simpleperf ] && echo yes' 'es-perf1.sh')".Trim() -ne "yes") {
        Send-AppFile $adb $sp "files/simpleperf" $Device; App-Script "chmod 755 files/simpleperf" | Out-Null
      }
      & $adb -s $Device shell "setprop security.perf_harden 0" | Out-Null
      App-Script "pid=`$(pidof recoil-main || pidof spring); files/simpleperf record -p `$pid -e cpu-clock:u -f 2000 --duration $Perf -o files/es-perf.data 2>&1 | tail -n 2" "es-perf2.sh"
      & $adb -s $Device shell "setprop security.perf_harden 1" | Out-Null
    }
  } while ($now -le $before -and ((Get-Date) - $start).TotalSeconds -lt $Timeout)
  if ($now -le $before) { "timeout after $Timeout s" }
  & $adb -s $Device shell "am force-stop com.underarmcape.bardroid" | Out-Null
  $runs = "$ES\runs"
  New-Item -ItemType Directory -Force $runs | Out-Null
  $out = "$runs\$((Get-Date).ToString('yyyyMMdd-HHmmss'))-$Engine-$($name -replace '[^\w.-]','_').txt"
  # (this run's infolog: the next start removes it, and a force-stop can come before launch-bar.sh's copy in files/logs)
  App-Script "cat files/bar/infolog.txt" "es-cat.sh" | Out-File -Encoding utf8 $out
  App-Script "rm -f files/bar/.bardroid-bench-replay files/bar/dev-env.sh" | Out-Null
  if ($Perf) {
    & cmd /c "`"$adb`" -s $Device exec-out run-as com.underarmcape.bardroid cat files/es-perf.data > `"$($out -replace '\.txt$','.perf.data')`""
    App-Script "rm -f files/es-perf.data" | Out-Null
    "profile: $($out -replace '\.txt$','.perf.data')"
  }
  $log = Get-Content $out
  $desync = @($log | Select-String -SimpleMatch "[DESYNC WARNING]").Count
  "engine $Engine, replay ${name}: $desync desync warnings, $([int]((Get-Date) - $start).TotalSeconds) s; infolog $out"
  $log | Select-String -Pattern 'engine-sim|\[replaybench\]|DESYNC WARNING|Sync error|Error in|ShutDown' | Select-Object -First 40 |
    ForEach-Object { $_.Line }
}
