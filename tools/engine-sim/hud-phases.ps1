# Freedreno's own counters per A/B phase (docs/ENGINE-SIM.md): a run with GALLIUM_HUD + GALLIUM_HUD_DUMP_DIR (one value a
# second per counter, invisible with GALLIUM_HUD_VISIBLE=false) and bardroid_abswitch.lua's phases; each counter averaged
# over each phase's measured part (its last 4/5) and divided by the frame rate the HUD counted: per drawn frame.
#   hud-phases.ps1 -Infolog <run>-infolog.txt -Hud <folder of the dumps> [-Period 20] [-From 1210]
param([Parameter(Mandatory)][string]$Infolog, [Parameter(Mandatory)][string]$Hud, [int]$Period = 20, [int]$From = 1210)
$series = @{}
foreach ($f in Get-ChildItem $Hud -File) {
  $series[$f.BaseName] = @(Get-Content $f.FullName | ForEach-Object { [double]::Parse(($_ -split '\s+')[-1], [Globalization.CultureInfo]::InvariantCulture) })
}
if (-not $series.ContainsKey("fps")) { throw "no fps dump in $Hud" }
$rows = foreach ($l in (Get-Content $Infolog | Select-String -Pattern '^\[t=(\d+):(\d+):([\d.]+)\].*\[abswitch\] (\d+):(\d+) \S+ (\d+):')) {
  $g = $l.Matches[0].Groups
  $t = [int]$g[1].Value * 3600 + [int]$g[2].Value * 60 + [double]::Parse($g[3].Value, [Globalization.CultureInfo]::InvariantCulture)
  if (([int]$g[4].Value * 60 + [int]$g[5].Value) -lt $From) { continue }
  $a = [int][math]::Ceiling($t - $Period * 0.8); $b = [int][math]::Floor($t) - 1
  $o = [ordered]@{ value = [int]$g[6].Value }
  $fps = ($series["fps"][$a..$b] | Measure-Object -Average).Average
  $o.fps = [math]::Round($fps, 1)
  foreach ($k in ($series.Keys | Where-Object { $_ -ne "fps" } | Sort-Object)) {
    $v = ($series[$k][$a..$b] | Measure-Object -Average).Average
    $o[$k] = if ($fps -gt 0) { [math]::Round($v / $fps, 2) } else { $null }
  }
  [pscustomobject]$o
}
"per phase (counters per drawn frame):"
$rows | Format-Table -AutoSize | Out-String -Width 250
"by value:"
$rows | Group-Object value | ForEach-Object {
  $grp = $_.Group; $o = [ordered]@{ value = $_.Name; phases = $grp.Count }
  foreach ($p in $grp[0].PSObject.Properties.Name | Where-Object { $_ -ne "value" }) { $o[$p] = [math]::Round(($grp | Measure-Object $p -Average).Average, 2) }
  [pscustomobject]$o
} | Format-Table -AutoSize | Out-String -Width 250
