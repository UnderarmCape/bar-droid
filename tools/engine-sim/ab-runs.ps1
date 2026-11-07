# Whole runs of the late 8v8 by turns (docs/ENGINE-SIM.md), each a replay-memory.ps1 run with its own extra settings,
# summed: fps and game speed over the measured part ([replaybench] lines), the [perf] lines' GPU clock, busy and the
# GPU driver's and the engine's memory over it, and the textures (tools/tex-memory.py, with BARDROID_TEX_LOG=1).
#   ab-runs.ps1 -Engine gcc-shader2 -Order A,B,B,A -A "Key = 0" -B "Key = 1","Other = x" [-Settings common...] [-DevEnv ...]
#   ab-runs.ps1 -Summarize <run prefix>[,<run prefix>...]      (C:\...\runs\<stamp>-mem-<engine>-<label>)
param([string]$Engine = "gcc-shader2", [string[]]$Order = @("A", "B"), [string[]]$A = @(), [string[]]$B = @(),
      [string[]]$Settings = @(), [string[]]$DevEnv = @(), [string]$Replay = "isthmus8v8-20261026.sdfz", [int]$Skip = 1210,
      [int]$Seconds = 120, [string]$Label = "abba", [string]$Device = "R5CW22GVC3D", [string[]]$Summarize = @(), [switch]$Timers)
$ErrorActionPreference = "Continue"
$py = "C:\Tools\BARANDROID\toolchain\hosttools\python\python.exe"
function Summary([string]$prefix) {
  $info = Get-Content "$prefix-infolog.txt" -ErrorAction SilentlyContinue
  $fps = @(); $spd = @()
  foreach ($l in ($info | Select-String -Pattern '\[replaybench\] \d+:\d+ x([\d.]+) .* (\d+) fps$')) {
    $fps += [double]$l.Matches[0].Groups[2].Value; $spd += [double]$l.Matches[0].Groups[1].Value
  }
  $done = ($info | Select-String -Pattern 'replaybench\] done' | Select-Object -Last 1)
  $perf = @(Get-Content "$prefix-launcher.log" -ErrorAction SilentlyContinue | Select-String -Pattern '\[perf\].*GPU (\d+) MHz of \d+ .*busy (\d+) %.*engine (\d+) MB, GPU (\d+) MB')
  # (the minute lines while the measured part ran: after the replay's fast-forward, the last two or three)
  $late = @($perf | Select-Object -Last 3 | Where-Object { [int]$_.Matches[0].Groups[2].Value -gt 0 })
  # (-Timers: the GPU's time of two passes from the [simdraw] timers lines, % of real time -> ms a drawn frame)
  $gm = @(); $gt = @()
  foreach ($l in ($info | Select-String -Pattern '\[simdraw\] timers: .*')) {
    $mo = [regex]::Match($l.Line, 'GPU::ModelsOpaque ([\d.]+)%'); $te = [regex]::Match($l.Line, 'GPU::Terrain ([\d.]+)%')
    if ($mo.Success) { $gm += [double]$mo.Groups[1].Value }; if ($te.Success) { $gt += [double]$te.Groups[1].Value }
  }
  $tex = & $py -I "C:\Tools\BARANDROID\bar-droid-engine\tools\tex-memory.py" "$prefix-launcher.log" --top 0 2>$null | Select-Object -First 2
  [pscustomobject]@{
    run = Split-Path $prefix -Leaf
    fps = if ($fps.Count) { [math]::Round(($fps | Measure-Object -Average).Average, 1) } else { $null }
    speed = if ($spd.Count) { [math]::Round(($spd | Measure-Object -Average).Average, 2) } else { $null }
    gpuMHz = ($late | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join '/'
    busy = ($late | ForEach-Object { $_.Matches[0].Groups[2].Value }) -join '/'
    engineMB = ($late | ForEach-Object { $_.Matches[0].Groups[3].Value }) -join '/'
    gpuMB = ($late | ForEach-Object { $_.Matches[0].Groups[4].Value }) -join '/'
    textures = ($tex -join ' ')
    gpuModelsPct = if ($gm.Count) { [math]::Round(($gm | Select-Object -Last 12 | Measure-Object -Average).Average, 1) } else { $null }
    gpuTerrainPct = if ($gt.Count) { [math]::Round(($gt | Select-Object -Last 12 | Measure-Object -Average).Average, 1) } else { $null }
    done = if ($done) { $done.Line -replace '.*done ', '' } else { "(not done)" }
  }
}
if ($Summarize.Count) { $Summarize | ForEach-Object { Summary $_ } | Format-List; return }

$rows = @()
foreach ($side in $Order) {
  $extra = if ($side -eq "A") { $A } else { $B }
  "== $side $(Get-Date -Format HH:mm:ss): $($extra -join ', ')"
  $out = & "$PSScriptRoot\replay-memory.ps1" -Engine $Engine -Replay $Replay -Skip $Skip -Seconds $Seconds `
    -Settings ($Settings + $extra) -DevEnv $DevEnv -Label "$Label-$side" -Device $Device -Timers:$Timers
  $out | Select-String -Pattern '^result:|launcher.log and infolog' | ForEach-Object { "  $_" }
  $m = ($out | Select-String -Pattern 'launcher.log and infolog of the run: (.*)-launcher.log').Matches
  if ($m.Count) { $s = Summary $m[0].Groups[1].Value; $s | Add-Member side $side; $rows += $s }
}
$rows | Format-Table side, fps, speed, gpuMHz, busy, engineMB, gpuMB, gpuModelsPct, gpuTerrainPct, done -AutoSize | Out-String -Width 250
$rows | ForEach-Object { "$($_.side) $($_.run): $($_.textures)" }
