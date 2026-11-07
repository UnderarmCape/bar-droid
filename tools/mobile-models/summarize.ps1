# Each mobile-models run: fps (the replay benchmark's 10 s samples in the measured part), game speed, units, the GPU's
# clock and busy share and the memory from launcher.log's [perf] lines, the mobile models' load line.
param([string]$Pattern = "*-mm-*-infolog.txt", [string]$Since = "")
$runs = Get-ChildItem C:\Tools\BARANDROID\engine-sim\runs -Filter $Pattern | Sort-Object Name
if ($Since) { $runs = $runs | Where-Object { $_.Name -ge $Since } }
foreach ($r in $runs) {
  $l = Get-Content $r.FullName
  $meas = $false; $fps = @(); $speed = @(); $units = 0
  foreach ($line in $l) {
    if ($line -match 'replaybench\] measuring') { $meas = $true; continue }
    if ($meas -and $line -match 'replaybench\] \d+:\d+ x([\d.]+) .*, (\d+) units, (\d+) fps') {
      $speed += [double]$Matches[1]; $units = [math]::Max($units, [int]$Matches[2]); $fps += [double]$Matches[3]
    }
  }
  # (drawn frames from the [simdraw] lines whose game time is in 1210-1330 s, as the 30 fps push's avg2.ps1)
  $frames = @()
  foreach ($line in $l) {
    if ($line -match '\[simdraw\] (\d+):(\d\d) sim .*draw \d+% \([\d.]+ ms x (\d+)\)') {
      $t = [int]$Matches[1] * 60 + [int]$Matches[2]
      if ($t -ge 1210 -and $t -le 1330) { $frames += [int]$Matches[3] }
    }
  }
  $sdFps = if ($frames.Count) { ($frames | Measure-Object -Average).Average / 10 } else { 0 }
  $mob = ($l | Select-String -Pattern 'mobile models: (\d+) drawn.*' | Select-Object -Last 1)
  $simp = ($l | Select-String -Pattern 'models simplified .*: (\d+) models, (\d+) -> (\d+) triangles' | Select-Object -Last 1)
  $lg = $r.FullName -replace '-infolog\.txt$', '-launcher.log'
  $gpu = @(); $busy = @(); $avail = @(); $gmem = @()
  if (Test-Path $lg) {
    foreach ($p in (Select-String -Path $lg -Pattern '\[perf\].*GPU (\d+) MHz of \d+.*busy (\d+) %.*memory available (\d+) MB.*GPU (\d+) MB')) {
      $gpu += [int]$p.Matches[0].Groups[1].Value; $busy += [int]$p.Matches[0].Groups[2].Value
      $avail += [int]$p.Matches[0].Groups[3].Value; $gmem += [int]$p.Matches[0].Groups[4].Value
    }
  }
  $f = if ($fps.Count) { ($fps | Measure-Object -Average).Average } else { 0 }
  $s = if ($speed.Count) { ($speed | Measure-Object -Average).Average } else { 0 }
  "{0}: simdraw {12:N1} fps ({13} windows); replaybench {1:N1} fps ({2} samples, {3}-{4}), x{5:N2}, {6} units; GPU {7:N0} MHz {8:N0} % busy (last 3 min: {9}); mem avail min {10} MB, GPU mem max {11} MB" -f `
    ($r.Name -replace '-infolog\.txt$', ''), $f, $fps.Count, ($fps | Measure-Object -Minimum).Minimum, ($fps | Measure-Object -Maximum).Maximum, $s, $units,
    (($gpu | Select-Object -Last 3 | Measure-Object -Average).Average), (($busy | Select-Object -Last 3 | Measure-Object -Average).Average),
    (($gpu | Select-Object -Last 3) -join '/'), (($avail | Measure-Object -Minimum).Minimum), (($gmem | Measure-Object -Maximum).Maximum), $sdFps, $frames.Count
  if ($mob) { "    " + ($mob.Line -replace '^.*\[BarDroid\] ', '') }
  if ($simp) { "    " + ($simp.Line -replace '^.*\[BarDroid\] ', '') }
}
