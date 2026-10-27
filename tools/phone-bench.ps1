# BAR's "Benchmark BAR" scenario on the phone, unattended (Kailil, 2026-10-27: "make optimizations and run benchmarks
# over and over"): sets the app's game resolution and frame cap, waits until the phone has cooled (runs compare only
# from the same start), starts the benchmark through the app (LauncherActivity "start bench": launch-bar.sh MODE=bench,
# bardroid_bench.lua quits after the results), and prints the benchmark's Sim/Draw/Update ms per frame with the fps and
# heat of the run. Each run is added to build\phone-bench.csv. The phone must be awake-able without a lock screen code.
# -Profile widgets|gadgets: BAR's widget or gadget profiler on for the run (it costs time itself: not for comparing);
# its table is in the benchmark's screenshot at frame 2015, copied to build\phone-bench-<widgets|gadgets>.png.
#   powershell -ExecutionPolicy Bypass -File tools\phone-bench.ps1 [-Scale 100|85|70] [-Cap 0|30|60] [-Label text] [-NoCool]
#     [-Profile widgets|gadgets]
param([int]$Scale = 100, [int]$Cap = 0, [string]$Label = "", [switch]$NoCool, [string]$Profile = "",
  [double]$MaxSkin = 35.0, [string]$Device = "192.168.1.196:5555")
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { $adb = Get-ChildItem $TC -Recurse -Filter adb.exe | Select-Object -First 1 -ExpandProperty FullName }
$pkg = "com.underarmcape.bardroid"
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
trap { Remove-Item $lock -ErrorAction SilentlyContinue; break }

& $adb connect $Device | Out-Null
Adb shell "am force-stop $pkg"
# the app's saved settings (shared_prefs/bardroid.xml) while it is stopped
AppSh @'
f=shared_prefs/bardroid.xml
for kv in "$@"; do
  k=${kv%%=*}; v=${kv#*=}
  sed -i "/name=\"$k\"/d" "$f"
  sed -i "s|</map>|    <int name=\"$k\" value=\"$v\" />\n</map>|" "$f"
done
'@ @("renderScale=$Scale", "fpsCap=$Cap") | Out-Null
AppSh 'if [ -n "$1" ]; then echo "$1" > files/bar/.bardroid-bench-profile; else rm -f files/bar/.bardroid-bench-profile; fi' @($Profile) | Out-Null

if (-not $NoCool) {
  $deadline = (Get-Date).AddMinutes(25)
  while ($true) {
    $h = Thermal
    # the skin cools slowest, and Samsung caps the CPU at ~2 GHz within 20 s of a start that is still warm
    if ($h.Status -eq 0 -and $h.Ap -le 37 -and $h.Skin -le $MaxSkin) { break }
    if ((Get-Date) -gt $deadline) { Write-Host "[phone-bench] still warm after 25 min (status $($h.Status), AP $($h.Ap) C, skin $($h.Skin) C): running anyway"; break }
    Write-Host "[phone-bench] cooling: status $($h.Status), AP $($h.Ap) C, skin $($h.Skin) C"
    Start-Sleep 60
  }
}
$start = Thermal
$since = (Get-Date).ToString("HH:mm:ss")
$before = [int](AppSh "grep -c 'Benchmark Results' files/logs/launcher.log")
# the clocks every 5 s through the run (tools/phone-clocks.sh): what the CPU and GPU were allowed and the heat
$clkFile = Join-Path $App "build\phone-bench-clocks.txt"
Adb push (Join-Path $PSScriptRoot "phone-clocks.sh") /data/local/tmp/bardroid-clocks.sh | Out-Null
Adb shell "sed -i 's/\r$//' /data/local/tmp/bardroid-clocks.sh"
$clk = Start-Process -FilePath $adb -ArgumentList "-s", $Device, "shell", "sh /data/local/tmp/bardroid-clocks.sh 900" `
  -RedirectStandardOutput $clkFile -NoNewWindow -PassThru
Adb shell "input keyevent KEYCODE_WAKEUP" | Out-Null
Adb shell "am start -n $pkg/.LauncherActivity --es start bench" | Out-Null
Write-Host "[phone-bench] started ${since}: resolution $Scale%, frame cap $(if ($Cap) { $Cap } else { 'none' }), status $($start.Status), AP $($start.Ap) C, skin $($start.Skin) C"

$deadline = (Get-Date).AddMinutes(12)
while ((Get-Date) -lt $deadline) {
  Start-Sleep 15
  if ([int](AppSh "grep -c 'Benchmark Results' files/logs/launcher.log") -gt $before) { break }
}
Start-Sleep 6
$end = Thermal
Adb shell "am force-stop $pkg"
Adb shell "touch /data/local/tmp/bardroid-clocks.stop" | Out-Null
if (-not $clk.WaitForExit(15000)) { $clk.Kill() }
$clocks = @(Get-Content $clkFile | Select-Object -Skip 1 | ForEach-Object { $f = $_ -split ' '; if ($f.Count -ge 9) {
  [pscustomobject]@{ cpu6 = [int]$f[3]; cap6 = [int]$f[4]; cap0 = [int]$f[2]; gpu = [int]$f[5]; busy = [int]$f[7]; status = [int]$f[8] } } })
function Med($v) { $s = @($v | Sort-Object); if ($s.Count) { $s[[int][math]::Floor($s.Count / 2)] } else { $null } }
$lines = AppSh @'
awk -v s="$1" 'substr($0,1,8) >= s' files/logs/launcher.log | grep -E 'Benchmark complete|^.{8} \[engine\].*(Draw|Sim|Update) [0-9]+ frames|bardroid-perf\] [0-9]|\[perf\] thermal|X screen [0-9]|bardroid-bench|Watchdog|MESA: error' |
  sed 's/\[engine\] \[t=[^]]*\]\[f=[^]]*\] //' | cut -c1-230
'@ @($since)
$lines | ForEach-Object { Write-Host "  $_" }

function Ms([string]$name) { $m = $lines | Select-String "$name \d+ frames, ([\d.]+)ms per frame" | Select-Object -Last 1; if ($m) { [double]$m.Matches[0].Groups[1].Value } else { $null } }
$sim, $draw, $upd = (Ms "Sim"), (Ms "Draw"), (Ms "Update")
$fps = @($lines | Select-String 'bardroid-perf\] ([\d.]+) fps' | ForEach-Object { [double]$_.Matches[0].Groups[1].Value })
$gpu = @($lines | Select-String 'busy (\d+) %' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
$row = [pscustomobject]@{
  when = (Get-Date).ToString("yyyy-MM-dd HH:mm"); label = $Label; scale = $Scale; cap = $Cap
  sim_ms = $sim; draw_ms = $draw; update_ms = $upd
  fps_last = $(if ($fps.Count) { $fps[-1] } else { $null }); gpu_busy_max = $(if ($gpu.Count) { ($gpu | Measure-Object -Maximum).Maximum } else { $null })
  ap_start = $start.Ap; ap_end = $end.Ap; status_end = $end.Status; skin_start = $start.Skin; skin_end = $end.Skin
  cpu6_med = (Med $clocks.cpu6); cap6_min = ($clocks.cap6 | Measure-Object -Minimum).Minimum; cap0_min = ($clocks.cap0 | Measure-Object -Minimum).Minimum
  gpu_med = (Med $clocks.gpu); busy_med = (Med $clocks.busy)
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
Remove-Item $lock -ErrorAction SilentlyContinue
$csv = Join-Path $App "build\phone-bench.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $csv) | Out-Null
$row | Export-Csv -Path $csv -Append -NoTypeInformation
if ($null -eq $sim) { Write-Host "[phone-bench] no results: see files/logs/launcher.log"; exit 1 }
Write-Host ("[phone-bench] {0}: Sim {1} ms, Draw {2} ms, Update {3} ms per frame; last minute {4} fps; GPU busy up to {5}%; AP {6} -> {7} C" -f
  $(if ($Label) { $Label } else { "$Scale%" }), $sim, $draw, $upd, $row.fps_last, $row.gpu_busy_max, $start.Ap, $end.Ap)
Write-Host ("[phone-bench] clocks: prime CPU median {0} MHz, its cap down to {1} MHz (others {2}); GPU median {3} MHz, {4}% busy; {5}" -f
  $row.cpu6_med, $row.cap6_min, $row.cap0_min, $row.gpu_med, $row.busy_med, $clkFile)
