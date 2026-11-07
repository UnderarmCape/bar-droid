# threads.sh's two snapshots -> % of one core per thread and per process (docs/CONTAINER-COST.md)
#   thrdiff.ps1 <file> [-Top 25]
param([Parameter(Mandatory)][string]$File, [int]$Top = 25)
$lines = Get-Content $File
$i = [Array]::IndexOf($lines, "===")
function parse($arr) {
  $t = @{}; $u = @{}
  foreach ($l in $arr) {
    $f = $l -split ' '
    if ($f[0] -eq 'U') { $u[$f[1]] = [double]$f[2] }
    elseif ($f[0] -eq 'T' -and $f.Count -ge 10) { $t["$($f[1])/$($f[2])"] = $f }
  }
  @{ t = $t; u = $u }
}
$a = parse $lines[0..($i - 1)]; $b = parse $lines[($i + 1)..($lines.Count - 1)]
$rows = foreach ($k in $b.t.Keys) {
  if (-not $a.t.ContainsKey($k)) { continue }
  $x = $a.t[$k]; $y = $b.t[$k]; $p = $y[1]
  $sec = $b.u[$p] - $a.u[$p]
  if ($sec -le 0) { continue }
  [pscustomobject]@{ pid = $p; tid = $y[2]; comm = $y[3]; state = $y[4]
    cpuPct = [math]::Round(((([long]$y[5] + [long]$y[6]) - ([long]$x[5] + [long]$x[6])) / $sec), 1)   # ticks are 10 ms: /100 s * 100 %
    sysPct = [math]::Round((([long]$y[6] - [long]$x[6]) / $sec), 1)
    volPerS = [math]::Round(([long]$y[7] - [long]$x[7]) / $sec); invPerS = [math]::Round(([long]$y[8] - [long]$x[8]) / $sec) }
}
$rows | Sort-Object cpuPct -Descending | Select-Object -First $Top | Format-Table -AutoSize | Out-String -Width 200
"by process (% of one core):"
$rows | Group-Object pid | ForEach-Object {
  $main = ($_.Group | Where-Object { $_.tid -eq $_.pid } | Select-Object -First 1).comm
  "{0} {1}: {2:N1} %, {3} voluntary switches/s" -f $_.Name, $main, ($_.Group | Measure-Object cpuPct -Sum).Sum, ($_.Group | Measure-Object volPerS -Sum).Sum
}
