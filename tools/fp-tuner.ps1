# The 1st person camera tuner (the laptop only; Kailil, 2026-10-27): plays a replay in BAR's Windows engine with the
# app's spectate widget riding a unit in 1st person and a panel to set its values with the mouse
# (tools\fp-tuner\bardroid_fp_tuner.lua). Save writes them to build\fp-tuner\data\LuaUI\Config\bardroid_fp.lua (kept
# between runs, read again at the next start); they become bardroid_spectate.lua's defaults (FP) for the phone.
# Isolated write dir build\fp-tuner\data (the live install's packages, pool, rapid index and maps joined read-only by
# junctions, removed again at the end). Runs until the window is closed.
#   powershell -ExecutionPolicy Bypass -File tools\fp-tuner.ps1 [-Replay <file.sdfz>] [-SkipTo 240] [-Engine recoil_2026.07.04]
param([string]$Replay = "", [int]$SkipTo = 240, [string]$Engine = "")
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\fp-tuner"
$Data = Join-Path $Work "data"
. (Join-Path $PSScriptRoot "toolchain.ps1")
Assert-BarData
if (-not $Replay) {
  $Replay = Get-ChildItem (Join-Path $BarData "demos") -Filter *.sdfz | Sort-Object LastWriteTime -Descending |
    Where-Object { $_.Length -gt 500000 } | Select-Object -First 1 -ExpandProperty FullName
  if (-not $Replay) { throw "no replay in $BarData\demos: pass -Replay" }
}
if (-not $Engine) { $Engine = if ((Split-Path $Replay -Leaf) -match '_(\d{4}\.\d{2}\.\d{2})\.sdfz$') { "recoil_$($Matches[1])" } }
$EngineDir = Get-EngineDir $Engine

Remove-Item -Recurse -Force "$Data\LuaUI\Widgets" -ErrorAction SilentlyContinue   # (LuaUI\Config keeps the saved values)
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
  Copy-Item (Join-Path $PSScriptRoot "fp-tuner\bardroid_fp_tuner.lua") "$Data\LuaUI\Widgets\" -Force
  "$SkipTo" | Set-Content "$Data\LuaUI\Config\bardroid_fp_tuner_skip.txt" -Encoding ascii
  "-- Widget Custom data and order, order = 0 disabled widget`nreturn {`n`tdata = {`n`t},`n`torder = {`n`t`t[`"Info`"] = 0,`n`t`t[`"Ecostats`"] = 0,`n`t},`n}" |
    Set-Content "$Data\LuaUI\Config\BYAR.lua" -Encoding ascii
  "Fullscreen = 0`nWindowBorderless = 0`nXResolutionWindowed = 1600`nYResolutionWindowed = 900`nWindowPosX = 40`nWindowPosY = 30`nsnd_volmaster = 0`nLogFlushLevel = 0" |
    Set-Content "$Data\springsettings.cfg" -Encoding ascii
  $demo = Join-Path $Data "demos\$(Split-Path $Replay -Leaf)"
  Write-Host "[fp-tuner] $(Split-Path $Replay -Leaf) from game second $SkipTo (the start fast-forwards there first), engine $Engine"
  $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -WorkingDirectory $EngineDir -PassThru `
    -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "`"$demo`""
  $p.WaitForExit()
  $saved = Join-Path $Data "LuaUI\Config\bardroid_fp.lua"
  if (Test-Path $saved) { Write-Host "[fp-tuner] saved values: $saved"; Get-Content $saved }
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
