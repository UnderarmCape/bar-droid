# bardroid_spectate.lua (spectating by touch) in a real replay on the laptop: BAR's Windows engine plays a replay from
# BAR's install or the tools' copies (the newest whose game and map are installed: toolchain.ps1 Get-ReplayFiles; or
# -Replay) in an isolated write dir
# (build\spectate-test\data; the live install's packages, pool, rapid index and maps joined read-only by junctions,
# removed again at the end) with the app's touch, info and spectate widgets and a test widget
# (tools\spectate-test\bardroid_spectate_test.lua) that fast-forwards into the game and checks the touch tools (~2 min).
#   powershell -ExecutionPolicy Bypass -File tools\spectate-test.ps1 [-Replay <file.sdfz>] [-Engine recoil_2026.07.04]
# -Cost: instead of the checks, what the spectate widget costs per frame (ms and KB of garbage) when off, with the bar
# up, following a unit, a group and in 1st person (tools\spectate-test\bardroid_spectate_cost.lua, ~1.5 min).
# -Settings @{ Key = value }: engine settings for the run (e.g. CamSpringLockCardinalDirections = 0, as the phone has
# it; the engine's default, on, is what the checks run with otherwise).
param([string]$Replay = "", [string]$Engine = "", [switch]$Cost, [hashtable]$Settings = @{})
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\spectate-test"
$Data = Join-Path $Work "data"
. (Join-Path $PSScriptRoot "toolchain.ps1")
Assert-BarData

# a replay's start script (the .sdfz is a gzipped demo: its header says where the script is)
function DemoScript([string]$path) {
  $gz = New-Object IO.Compression.GZipStream ([IO.File]::OpenRead($path)), ([IO.Compression.CompressionMode]::Decompress)
  $buf = New-Object byte[] 262144
  $n = 0
  while ($n -lt $buf.Length) { $r = $gz.Read($buf, $n, $buf.Length - $n); if ($r -le 0) { break }; $n += $r }
  $gz.Close()
  $headerSize = [BitConverter]::ToInt32($buf, 20); $scriptSize = [BitConverter]::ToInt32($buf, 304)
  if ($headerSize + $scriptSize -gt $n) { return "" }
  [Text.Encoding]::UTF8.GetString($buf, $headerSize, $scriptSize)
}
# the game versions installed (rapid packages) and the map files
$installed = @{}
$packages = @{}
Get-ChildItem (Join-Path $BarData "packages") -Filter *.sdp | ForEach-Object { $packages[$_.BaseName] = $true }
Get-ChildItem (Join-Path $BarData "rapid") -Recurse -Filter versions.gz | ForEach-Object {
  $s = New-Object IO.StreamReader (New-Object IO.Compression.GZipStream ([IO.File]::OpenRead($_.FullName)), ([IO.Compression.CompressionMode]::Decompress))
  while (($l = $s.ReadLine()) -ne $null) { $f = $l.Split(",", 4); if ($f.Count -eq 4 -and $packages[$f[1]]) { $installed[$f[3]] = $true } }
  $s.Close()
}
$maps = @{}
Get-ChildItem (Join-Path $BarData "maps") -File | ForEach-Object { $maps[$_.BaseName.ToLower()] = $true }
function Playable([string]$path) {
  $script = DemoScript $path
  $game = if ($script -match '(?i)gametype=([^;]*);') { $Matches[1] }
  $map = if ($script -match '(?i)mapname=([^;]*);') { $Matches[1] }
  $game -and $installed[$game] -and $map -and $maps[$map.ToLower().Replace(" ", "_")]
}
if (-not $Replay) {
  $Replay = Get-ReplayFiles | Where-Object { Playable $_.FullName } | Select-Object -First 1 -ExpandProperty FullName
  if (-not $Replay) { throw "no replay in $BarData\demos or build\*\data\demos with its game and map installed: pass -Replay" }
}
if (-not $Engine) { $Engine = if ((Split-Path $Replay -Leaf) -match '_(\d{4}\.\d{2}\.\d{2})\.sdfz$') { "recoil_$($Matches[1])" } }
$EngineDir = Get-EngineDir $Engine

Remove-Item -Recurse -Force "$Data\LuaUI" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Data\LuaUI\Widgets", "$Data\LuaUI\Config", "$Data\demos" | Out-Null
$links = foreach ($d in "packages", "pool", "rapid", "maps") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $BarData $d)" | Out-Null }
  $link
}
try {
  Copy-Item $Replay "$Data\demos\" -Force
  foreach ($f in "bardroid_touch.lua", "bardroid_info.lua", "bardroid_players.lua", "bardroid_spectate.lua") {
    Copy-Item (Join-Path $App "app\src\main\assets\bardroid\$f") "$Data\LuaUI\Widgets\" -Force
  }
  $driver = if ($Cost) { "bardroid_spectate_cost.lua" } else { "bardroid_spectate_test.lua" }
  Copy-Item (Join-Path $PSScriptRoot "spectate-test\$driver") "$Data\LuaUI\Widgets\" -Force
  # the phone's widget orders that matter here: BAR's Info widget off (bardroid_info.lua instead), Ecostats off
  "-- Widget Custom data and order, order = 0 disabled widget`nreturn {`n`tdata = {`n`t},`n`torder = {`n`t`t[`"Info`"] = 0,`n`t`t[`"Ecostats`"] = 0,`n`t},`n}" |
    Set-Content "$Data\LuaUI\Config\BYAR.lua" -Encoding ascii
  ("Fullscreen = 0`nWindowBorderless = 0`nXResolutionWindowed = 1280`nYResolutionWindowed = 720`nWindowPosX = 40`nWindowPosY = 40`nsnd_volmaster = 0`nLogFlushLevel = 0" +
    ($Settings.Keys | ForEach-Object { "`n$_ = $($Settings[$_])" }) -join "") |
    Set-Content "$Data\springsettings.cfg" -Encoding ascii
  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  $demo = Join-Path $Data "demos\$(Split-Path $Replay -Leaf)"
  Write-Host "[spectate-test] $(Split-Path $Replay -Leaf), engine $Engine"
  $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -WorkingDirectory $EngineDir -PassThru `
    -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "`"$demo`""
  $deadline = (Get-Date).AddSeconds($(if ($Cost) { 600 } else { 300 }))
  while (-not $p.HasExited -and (Get-Date) -lt $deadline -and
         -not ((Test-Path $log) -and (Select-String -Path $log -Pattern '\[spectest\] done' -Quiet))) { Start-Sleep 1 }
  Start-Sleep 1
  if (-not $p.HasExited) { $p.Kill() }
  Select-String -Path $log -Pattern '\[spectest\]|\[spectcost\]|BAR Droid spectate|bardroid_spectate' |
    ForEach-Object { $_.Line -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  if (-not (Select-String -Path $log -Pattern '\[spectest\] done' -Quiet)) {
    "[spectest] FAIL the test finished (a replay that never starts playing: pass another with -Replay)"
  }
  $shot = Get-ChildItem "$Data\screenshots" -Filter *.png -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if ($shot) { "[spectate-test] the bar: $($shot.FullName)" }
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
