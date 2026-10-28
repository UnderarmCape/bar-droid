# BAR's "Benchmark BAR" scenario on the phone, unattended (Kailil, 2026-10-27: "make optimizations and run benchmarks
# over and over"): sets the app's game resolution and frame cap, warms the phone up into the throttled state a late
# game plays in (Kailil: big unit counts come 10+ minutes in, on a hot phone; Samsung caps the CPU at ~2 GHz within
# 20 s of a start anyway) with unrecorded runs until it is there, starts the benchmark through the app
# (LauncherActivity "start bench": launch-bar.sh MODE=bench, bardroid_bench.lua quits after the results), and prints
# the benchmark's Sim/Draw/Update ms per frame with the fps, game speed and heat of the run. Back-to-back runs keep the
# phone hot. Each run is added to build\phone-bench.csv. The phone must be awake-able without a lock screen code.
# -Profile widgets|gadgets: BAR's widget or gadget profiler on for the run (it costs time itself: not for comparing);
# its table is in the benchmark's screenshot at frame 2015, copied to build\phone-bench-<widgets|gadgets>.png.
#   powershell -ExecutionPolicy Bypass -File tools\phone-bench.ps1 [-Scale 100|85|70] [-Cap 0|30|60] [-Label text]
#     [-Profile widgets|gadgets] [-Settings @{ WorkerThreadCount = 2 }] [-MinSkin 40] [-NoWarm]
# -Settings: engine settings (springsettings.cfg keys) for this run only (launch-bar.sh .bardroid-bench-settings; the
# file as it was goes back afterwards).
# -Replay <file in the phone's files/bar/demos>: a real game instead of the scenario (Kailil, 2026-10-27: real big
# battles), fast-forwarded to game second -SkipTo, then -Seconds played at normal speed: how fast the game ran against
# real time every 10 s (below x1 the phone falls behind live play), units and fps (bardroid_bench.lua). The warm-up
# stays the scenario. Its game version must be on the phone (a replay recorded there).
#   powershell -ExecutionPolicy Bypass -File tools\phone-bench.ps1 -Cap 30 -Replay "<replay>.sdfz" [-SkipTo 900] [-Seconds 600]
param([int]$Scale = 100, [int]$Cap = 0, [string]$Label = "", [switch]$NoWarm, [string]$Profile = "",
  [hashtable]$Settings = @{}, [double]$MinSkin = 40.0, [string]$Device = "",
  [string]$Replay = "", [int]$SkipTo = 900, [int]$Seconds = 600)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { $adb = Get-ChildItem $TC -Recurse -Filter adb.exe | Select-Object -First 1 -ExpandProperty FullName }
$pkg = "com.underarmcape.bardroid"
if (-not $Device) { $Device = Get-PhoneDevice $adb }   # -Device, else toolchain.ps1's choice
if (-not $Device) { throw "No phone: connect one over adb, or name it (-Device, BARDROID_DEVICE, phone-device.txt)" }
function Adb { & $adb -s $Device @args }
function AppSh([string]$script, [string[]]$a = @()) {   # a shell script run as the app (adb quoting through PowerShell is fragile)
  # (PowerShell pipes each line with a carriage return: dropped on the phone)
  $script | & $adb -s $Device exec-in run-as $pkg sh -c "tr -d '\r' > files/bench-x.sh" | Out-Null
  & $adb -s $Device exec-out run-as $pkg sh files/bench-x.sh @a
}
function Thermal {
  $t = Adb shell "dumpsys thermalservice"
  $status = [int](($t | Select-String 'Thermal Status: (\d)' | Select-Object -First 1).Matches[0].Groups[1].Value)
  $temp = { param($n) ($t | Select-String "mValue=([\d.]+), mType=\d+, mName=$n," | ForEach-Object { [double]$_.Matches[0].Groups[1].Value } | Measure-Object -Maximum).Maximum }
  [pscustomobject]@{ Status = $status; Ap = (& $temp "AP"); Skin = (& $temp "SKIN") }
}

# one benchmark on the phone at a time (this script and other sessions' research runs): the lock holds the holder's
# PID beside the toolchain folder; a lock whose process is gone is stale
$lock = Join-Path (Split-Path $TC) "phone-bench.lock"
while (Test-Path $lock) {
  $holder = (Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1)
  if (-not $holder -or [int]$holder -eq $PID -or -not (Get-Process -Id ([int]$holder) -ErrorAction SilentlyContinue)) { break }
  Write-Host "[phone-bench] phone busy (lock held by process $holder): waiting"
  Start-Sleep 30
}
Set-Content -Path $lock -Value $PID -Encoding ascii
trap { try { RestorePrefs; AppSh 'rm -f files/bar/.bardroid-bench-replay' | Out-Null } catch {}; Remove-Item $lock -ErrorAction SilentlyContinue; break }

if ($Device -match ":\d+$") { & $adb connect $Device | Out-Null }   # wireless debugging: (re)connect
Adb shell "am force-stop $pkg"
# the app's saved settings (shared_prefs/bardroid.xml) while it is stopped: the run's resolution and frame cap, the
# player's own put back afterwards (an empty value: the key was not saved, the app's default applies)
$PrefsSh = @'
f=shared_prefs/bardroid.xml
for kv in "$@"; do
  k=${kv%%=*}; v=${kv#*=}
  sed -i "/name=\"$k\"/d" "$f"
  [ -z "$v" ] || sed -i "s|</map>|    <int name=\"$k\" value=\"$v\" />\n</map>|" "$f"
done
'@
$userPrefs = @(AppSh @'
for k in "$@"; do echo "$k=$(sed -n "s/.*name=\"$k\" value=\"\([0-9-]*\)\".*/\1/p" shared_prefs/bardroid.xml | head -n 1)"; done
'@ @("renderScale", "frameCap") | Where-Object { $_ -match '^\w+=' })
function RestorePrefs { if ($script:userPrefs.Count) { Adb shell "am force-stop $pkg"; AppSh $PrefsSh $script:userPrefs | Out-Null } }
AppSh $PrefsSh @("renderScale=$Scale", "frameCap=$Cap") | Out-Null
AppSh 'if [ -n "$1" ]; then echo "$1" > files/bar/.bardroid-bench-profile; else rm -f files/bar/.bardroid-bench-profile; fi' @($Profile) | Out-Null
$kv = @($Settings.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" })
AppSh 'rm -f files/bar/.bardroid-bench-settings; for l in "$@"; do echo "$l" >> files/bar/.bardroid-bench-settings; done' $kv | Out-Null
AppSh 'rm -f files/bar/.bardroid-bench-replay' | Out-Null   # (the warm-up runs the scenario)
if ($Replay) {
  # (the name in the script itself: adb joins arguments with spaces, and replay names have spaces)
  $have = "$(AppSh "[ -s 'files/bar/demos/$Replay' ] && echo yes")".Trim()
  if ($have -ne "yes") { Remove-Item $lock -ErrorAction SilentlyContinue; throw "no replay files/bar/demos/$Replay on the phone" }
}

# the launcher's log lines since the run's start ($1, the phone's clock), also when the app put the full log aside as
# launcher.old.log during the run (Log.rotateIfBig): of each file, the lines after its last line stamped earlier
$RunLog = @'
{ for f in files/logs/launcher.old.log files/logs/launcher.log; do
  [ -f "$f" ] || continue
  [ "$f" = files/logs/launcher.log ] || [ "$f" -nt files/bench-start ] || continue
  awk -v s="$1" 'substr($0,3,1) == ":" && substr($0,1,8) < s { n = 0; next } { b[++n] = $0 } END { for (i = 1; i <= n; i++) print b[i] }' "$f"
done; }
'@
function BenchDone([string]$done) { [int](AppSh "$RunLog | grep -c '$done'" @($script:since) | Select-Object -Last 1) }
function RunBench([string]$done = 'Benchmark Results', [int]$minutes = 12) {   # one run, start to quit (bardroid_bench.lua quits ~3 s after the results)
  $script:since = "$(AppSh 'touch files/bench-start; date +%H:%M:%S' | Select-Object -Last 1)".Trim()
  Adb shell "input keyevent KEYCODE_WAKEUP" | Out-Null
  Adb shell "am start -n $pkg/.LauncherActivity --es start bench" | Out-Null
  $deadline = (Get-Date).AddMinutes($minutes)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep 15
    if ((BenchDone $done) -gt 0) { break }
  }
  Start-Sleep 6
  Adb shell "am force-stop $pkg"
}

# into the throttled state first: the skin warms slowest and the thermal status follows it (a long session ended at
# skin 42 C, status 2); a hot phone goes straight on
if (-not $NoWarm) {
  for ($i = 1; $i -le 4; $i++) {
    $h = Thermal
    if ($h.Status -ge 1 -and $h.Skin -ge $MinSkin) { break }
    Write-Host "[phone-bench] warming up ($i): status $($h.Status), AP $($h.Ap) C, skin $($h.Skin) C"
    RunBench
  }
}
$start = Thermal
# the clocks every 5 s through the run (tools/phone-clocks.sh): what the CPU and GPU were allowed and the heat
$clkFile = Join-Path $App "build\phone-bench-clocks.txt"
Adb push (Join-Path $PSScriptRoot "phone-clocks.sh") /data/local/tmp/bardroid-clocks.sh | Out-Null
Adb shell "sed -i 's/\r$//' /data/local/tmp/bardroid-clocks.sh"
$runMinutes = if ($Replay) { [int]($Seconds / 60) + 25 } else { 12 }   # (a replay: fast-forward + the measured part)
$clk = Start-Process -FilePath $adb -ArgumentList "-s", $Device, "shell", "sh /data/local/tmp/bardroid-clocks.sh $($runMinutes * 60)" `
  -RedirectStandardOutput $clkFile -NoNewWindow -PassThru
Write-Host "[phone-bench] started $((Get-Date).ToString('HH:mm:ss')): resolution $Scale%, frame cap $(if ($Cap) { $Cap } else { 'none' }), status $($start.Status), AP $($start.Ap) C, skin $($start.Skin) C$(if ($Replay) { "; replay $Replay from game second $SkipTo, $Seconds s" })"
if ($Replay) {
  AppSh "echo '$SkipTo $Seconds $Replay' > files/bar/.bardroid-bench-replay" | Out-Null
  RunBench 'replaybench\] done' $runMinutes
  AppSh 'rm -f files/bar/.bardroid-bench-replay' | Out-Null
} else {
  RunBench
}
$end = Thermal
Adb shell "touch /data/local/tmp/bardroid-clocks.stop" | Out-Null
if (-not $clk.WaitForExit(15000)) { $clk.Kill() }
$threads = @(Adb shell "cat /data/local/tmp/bardroid-threads.txt 2>/dev/null")
if ($threads.Count -gt 1) {
  Write-Host "[phone-bench] busiest threads ~70 s in:"
  $threads | Select-Object -First 16 | ForEach-Object { Write-Host "  $_" }
  $threads | Set-Content (Join-Path $App "build\phone-bench-threads.txt")
}
$clocks = @(Get-Content $clkFile | Select-Object -Skip 1 | ForEach-Object { $f = $_ -split ' '; if ($f.Count -ge 9) {
  [pscustomobject]@{ cpu6 = [int]$f[3]; cap6 = [int]$f[4]; cap0 = [int]$f[2]; gpu = [int]$f[5]; busy = [int]$f[7]; status = [int]$f[8] } } })
function Med($v) { $s = @($v | Sort-Object); if ($s.Count) { $s[[int][math]::Floor($s.Count / 2)] } else { $null } }
$lines = AppSh ($RunLog + @'
 | grep -E 'Benchmark complete|^.{8} \[engine\].*(Draw|Sim|Update) [0-9]+ frames|bardroid-perf\] [0-9]|\[perf\] thermal|X screen [0-9]|bardroid-bench|replaybench|replay benchmark|Watchdog|MESA: error' |
  sed 's/\[engine\] \[t=[^]]*\]\[f=[^]]*\] //' | cut -c1-230
'@) @($since)
$lines | ForEach-Object { Write-Host "  $_" }

function Ms([string]$name) { $m = $lines | Select-String "$name \d+ frames, ([\d.]+)ms per frame" | Select-Object -Last 1; if ($m) { [double]$m.Matches[0].Groups[1].Value } else { $null } }
$sim, $draw, $upd = (Ms "Sim"), (Ms "Draw"), (Ms "Update")
# the game's speed over the benchmark: simulated frames per second of Sim + Draw + Update time (the main thread's
# whole run; its "s total" figures are milliseconds), as a multiple of real time (30 frames a second)
$tot = @($lines | Select-String '(Sim|Draw|Update) (\d+) frames, [\d.]+ms per frame, ([\d.]+)s total' | Select-Object -Last 3)
$speed = $null
if ($tot.Count -eq 3) {
  $simFrames = [int](($tot | Where-Object { $_.Matches[0].Groups[1].Value -eq "Sim" }).Matches[0].Groups[2].Value)
  $ms = ($tot | ForEach-Object { [double]$_.Matches[0].Groups[3].Value } | Measure-Object -Sum).Sum
  if ($ms -gt 0) { $speed = [math]::Round($simFrames / ($ms / 1000) / 30, 2) }
}
# a replay: its summary line (bardroid_bench.lua)
$rs = $lines | Select-String 'replaybench\] done \(([^)]*)\): speed min x([\d.]+), median x([\d.]+); below x0\.95 (\d+)% of the time; units up to (\d+)' | Select-Object -Last 1
$rsum = if ($rs) { $g = $rs.Matches[0].Groups; [pscustomobject]@{ why = $g[1].Value; min = [double]$g[2].Value; med = [double]$g[3].Value; below = [int]$g[4].Value; units = [int]$g[5].Value } }
if ($rsum) { $speed = $rsum.med }
$fps = @($lines | Select-String 'bardroid-perf\] ([\d.]+) fps' | ForEach-Object { [double]$_.Matches[0].Groups[1].Value })
$gpu = @($lines | Select-String 'busy (\d+) %' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
$row = [pscustomobject]@{
  when = (Get-Date).ToString("yyyy-MM-dd HH:mm"); label = $Label; scale = $Scale; cap = $Cap
  sim_ms = $sim; draw_ms = $draw; update_ms = $upd; speed_x = $speed; settings = ($kv -join "; ")
  fps_last = $(if ($fps.Count) { $fps[-1] } else { $null }); gpu_busy_max = $(if ($gpu.Count) { ($gpu | Measure-Object -Maximum).Maximum } else { $null })
  ap_start = $start.Ap; ap_end = $end.Ap; status_end = $end.Status; skin_start = $start.Skin; skin_end = $end.Skin
  cpu6_med = (Med $clocks.cpu6); cap6_min = ($clocks.cap6 | Measure-Object -Minimum).Minimum; cap0_min = ($clocks.cap0 | Measure-Object -Minimum).Minimum
  gpu_med = (Med $clocks.gpu); busy_med = (Med $clocks.busy)
  replay = $(if ($Replay) { "$Replay from $SkipTo s" } else { $null }); replay_speed_min = $rsum.min
  replay_below95_pct = $rsum.below; replay_units_peak = $rsum.units
}
if ($Profile) {   # the newest screenshot: the benchmark's, with the profiler's table
  $shot = (AppSh 'ls -t files/bar/screenshots/*.png 2>/dev/null | head -n 1').Trim()
  if ($shot) {
    $out = Join-Path $App "build\phone-bench-$Profile.png"
    cmd /c "`"$adb`" -s $Device exec-out run-as $pkg cat `"$shot`" > `"$out`""
    Write-Host "[phone-bench] profiler table: $out"
  }
  AppSh 'rm -f files/bar/.bardroid-bench-profile' | Out-Null
}
# BAR's settings as they were before this run's -Settings
AppSh 'rm -f files/bar/.bardroid-bench-settings; [ -f files/bar/.springsettings.pre-bench ] && mv files/bar/.springsettings.pre-bench files/bar/springsettings.cfg; true' | Out-Null
RestorePrefs
Write-Host "[phone-bench] the player's settings back: $($userPrefs -join ', ')"
Remove-Item $lock -ErrorAction SilentlyContinue
$csv = Join-Path $App "build\phone-bench.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null
$old = @(if (Test-Path $csv) { Import-Csv $csv })
$cols = @($(if ($old.Count) { $old[0].PSObject.Properties.Name }) + $row.PSObject.Properties.Name | Select-Object -Unique)
@($old) + $row | Select-Object $cols | Export-Csv -Path $csv -NoTypeInformation   # new columns join older rows empty
if ($Replay) {
  if (-not $rsum) { Write-Host "[phone-bench] no replay results: see files/logs/launcher.log"; exit 1 }
  Write-Host ("[phone-bench] {0}: replay game speed median x{1}, min x{2}, below x0.95 {3}% of the time; units up to {4} ({5}); last minute {6} fps; AP {7} -> {8} C" -f
    $(if ($Label) { $Label } else { "replay" }), $rsum.med, $rsum.min, $rsum.below, $rsum.units, $rsum.why, $row.fps_last, $start.Ap, $end.Ap)
  Write-Host ("[phone-bench] clocks: prime CPU median {0} MHz, its cap down to {1} MHz (others {2}); GPU median {3} MHz, {4}% busy; {5}" -f
    $row.cpu6_med, $row.cap6_min, $row.cap0_min, $row.gpu_med, $row.busy_med, $clkFile)
  exit 0
}
if ($null -eq $sim) { Write-Host "[phone-bench] no results: see files/logs/launcher.log"; exit 1 }
Write-Host ("[phone-bench] {0}: Sim {1} ms, Draw {2} ms, Update {3} ms per frame; game speed x{8}; last minute {4} fps; GPU busy up to {5}%; AP {6} -> {7} C" -f
  $(if ($Label) { $Label } else { "$Scale%" }), $sim, $draw, $upd, $row.fps_last, $row.gpu_busy_max, $start.Ap, $end.Ap, $speed)
Write-Host ("[phone-bench] clocks: prime CPU median {0} MHz, its cap down to {1} MHz (others {2}); GPU median {3} MHz, {4}% busy; {5}" -f
  $row.cpu6_med, $row.cap6_min, $row.cap0_min, $row.gpu_med, $row.busy_med, $clkFile)
