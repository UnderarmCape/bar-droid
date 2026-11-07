# An A/B inside one replay run on the dev phone (docs/ENGINE-SIM.md): replay-memory.ps1 with bardroid_abswitch.lua,
# which switches an engine setting between its values every -Period seconds (A B B A ...) once the game reaches
# -From, and logs each phase's fps, game speed and (-Timers) the GPU's time per pass. Then the phases summed by value.
#   ab-run.ps1 -Engine gcc-shader -Key BarDroidModelShader -Values 0,1 [-Period 20] [-From 1210] [-Timers]
#              [-Skip 1210] [-Seconds 240] [-Settings "Key = value", ...] [-DevEnv "line", ...] [-Label x]
#              [-Cpu "Draw::Screen::UnitIcons,Sim"] (with -Timers: those CPU timers per phase too)
param([string]$Engine = "gcc-shader", [Parameter(Mandatory)][string]$Key, [int[]]$Values = @(0, 1), [int]$Period = 20,
      [int]$From = 1210, [switch]$Timers, [string]$Replay = "isthmus8v8-20261026.sdfz", [int]$Skip = 1210,
      [int]$Seconds = 240, [string[]]$Settings = @(), [string[]]$DevEnv = @(), [string]$Label = "ab",
      [string]$Device = "R5CW22GVC3D", [string]$Summarize = "", [string]$Cpu = "")
$ErrorActionPreference = "Stop"
function Summary([string]$infolog) {
  $rows = foreach ($l in (Get-Content $infolog | Select-String -Pattern '\[abswitch\] (\d+):(\d+) \S+ (\d+): ([\d.]+) fps, x([\d.]+)(?:; GPU ms a frame: (.*))?')) {
    $m = $l.Matches[0].Groups
    $gpu = @{}
    if ($m[6].Success) { foreach ($p in ($m[6].Value -split ', ')) { $kv = $p -split ' '; $gpu[$kv[0]] = [double]$kv[1] } }
    [pscustomobject]@{ t = [int]$m[1].Value * 60 + [int]$m[2].Value; value = [int]$m[3].Value; fps = [double]$m[4].Value; speed = [double]$m[5].Value; gpu = $gpu }
  }
  $rows = @($rows | Where-Object { $_.t -ge $From })
  "phases at or after game second ${From}: $($rows.Count)"
  foreach ($g in ($rows | Group-Object value)) {
    $f = ($g.Group | Measure-Object fps -Average -Minimum -Maximum)
    $s = ($g.Group | Measure-Object speed -Average).Average
    $line = "  $Key $($g.Name): $($g.Count) phases, fps mean $([math]::Round($f.Average, 2)) ($($f.Minimum)-$($f.Maximum)), speed x$([math]::Round($s, 2))"
    $names = @($g.Group | ForEach-Object { $_.gpu.Keys } | Sort-Object -Unique)
    if ($names.Count) {
      $line += "; GPU ms a frame: " + (($names | ForEach-Object { $n = $_; "$n $([math]::Round(($g.Group | ForEach-Object { $_.gpu[$n] } | Measure-Object -Average).Average, 2))" }) -join ', ')
    }
    $line
  }
  # pairwise: each phase against its neighbours of the other value (drift cancels in A B B A)
  "  by phase: " + (($rows | ForEach-Object { "$($_.value):$($_.fps)" }) -join ' ')
}
if ($Summarize) { Summary $Summarize; return }

. "C:\Tools\BARANDROID\bar-droid-app\tools\toolchain.ps1"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$tmp = Join-Path $TC "tmp"
function AppRun([string]$text, [string]$name) {
  $f = Join-Path $tmp $name
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
Send-AppFile $adb "$PSScriptRoot\bardroid_abswitch.lua" "files/bar/LuaUI/Widgets/bardroid_abswitch.lua" $Device
$cfg = "key $Key values $($Values -join ' ') period $Period from $From$(if ($Timers) { ' timers' })$(if ($Cpu) { " cpu $Cpu" })"
AppRun "echo '$cfg' > files/bar/LuaUI/Config/bardroid_abswitch.txt" "ab-cfg.sh" | Out-Null
try {
  $out = & "$PSScriptRoot\replay-memory.ps1" -Engine $Engine -Replay $Replay -Skip $Skip -Seconds $Seconds `
    -Settings $Settings -DevEnv $DevEnv -Label $Label -Device $Device
  $out
} finally {
  AppRun "rm -f files/bar/LuaUI/Widgets/bardroid_abswitch.lua files/bar/LuaUI/Config/bardroid_abswitch.txt" "ab-clean.sh" | Out-Null
}
$log = ($out | Select-String -Pattern 'launcher.log and infolog of the run: (.*)-launcher.log').Matches
if ($log.Count) { Summary "$($log[0].Groups[1].Value)-infolog.txt" }
