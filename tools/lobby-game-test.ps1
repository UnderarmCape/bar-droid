# The lobby's Skirmish screen with the controller game on the laptop, as the phone sets it up: BAR's Windows engine
# runs byar-chobby:test in an isolated write dir (build\lobby-game-test\data; the live install's packages, pool and
# rapid index joined read-only by junctions, removed again at the end) with Chobby's byar-dev config and
# games\BAR-gamepad.sdd unpacked from app\src\main\assets\gamepad as Installer.installGamepadGame does (~30 s),
# offline (the test lobby never logs in: toolchain.ps1 Write-LobbyConfig). Any lobby error ("[Chili] Error") fails it.
#   powershell -ExecutionPolicy Bypass -File tools\lobby-game-test.ps1 [-Engine recoil_2026.07.04]
param([string]$Engine = "")
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\lobby-game-test"
$Data = Join-Path $Work "data"
. (Join-Path $PSScriptRoot "toolchain.ps1")
Assert-BarData
$Bar = $BarData
if (-not $Engine) { $Engine = (Get-ChildItem (Join-Path $Bar "engine") -Directory | Sort-Object Name | Select-Object -Last 1).Name }
$EngineDir = Get-EngineDir $Engine

Remove-Item -Recurse -Force "$Data\LuaMenu", "$Data\games" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Data\LuaMenu\Config", "$Data\LuaMenu\Widgets", "$Data\games" | Out-Null
$links = foreach ($d in "packages", "pool", "rapid") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $Bar $d)" | Out-Null }
  $link
}
try {
  & "$TC\hosttools\python\python.exe" -I (Join-Path $PSScriptRoot "build-gamepad-game.py") --unpack-only `
    --unpack "$Data\games\BAR-gamepad.sdd" --bar-data $Bar
  if ($LASTEXITCODE) { throw "unpacking the controller game failed" }
  # as launch-bar.sh leaves it with the controller game on: the lobby's singleplayer game is byar-dev, local widgets,
  # interface scale 100%
  $scales = (0..5 | ForEach-Object { $x = $_; 0..11 | ForEach-Object { "[`"${x}x$_`"] = 1.0," } }) -join " "
  Write-LobbyConfig $Data "gameConfigName = `"byar-dev`", loadLocalWidgets = true, panel_layout = 3, uiScalesForScreenSizes = { $scales },"
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_lobby_touch.lua") "$Data\LuaMenu\Widgets\" -Force
  Copy-Item (Join-Path $PSScriptRoot "lobby-game-test\bardroid_lobby_game_test.lua") "$Data\LuaMenu\Widgets\" -Force
  '{"server": {"address": "server4.beyondallreason.info", "port": 8200, "protocol": "spring", "serverName": "BAR"}, "game": "byar-dev"}' |
    Set-Content "$Data\chobby_config.json" -Encoding ascii
  "Fullscreen = 0`nWindowBorderless = 0`nXResolutionWindowed = 1280`nYResolutionWindowed = 720`nWindowPosX = $OffScreenX`nWindowPosY = 40`nsnd_volmaster = 0`nLogFlushLevel = 0`nRapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev" |
    Set-Content "$Data\springsettings.cfg" -Encoding ascii
  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  Write-Host "[lobby-game-test] engine $Engine"
  $p = Start-Engine (Join-Path $EngineDir "spring.exe") $EngineDir @("--isolation", "--write-dir", "`"$Data`"", "--menu", "rapid://byar-chobby:test")
  $r = Wait-LobbyTest $p $log '\[lobbygame\] done'
  Start-Sleep 2
  if (-not $p.HasExited) { $p.Kill() }
  if ($r -ne "done") { "[lobbygame] the test ran: $r" }
  $lines = Get-Content $log | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  $lines | Where-Object { $_ -match '\[lobbygame\]' -and $_ -notmatch '\] (start|done)' }
  $errors = @($lines | Where-Object { $_ -match '^\[Chili\] Error' })
  if ($errors) { "[lobbygame] FAIL no lobby errors: $($errors.Count)"; $errors | Select-Object -First 8 }
  else { "[lobbygame] PASS no lobby errors" }
  $done = $lines | Where-Object { $_ -match '\[lobbygame\] done' } | Select-Object -Last 1
  $fails = 0
  if ($done -match 'done: (\d+) FAILED') { $fails = [int]$Matches[1] }
  if (-not $done) { "[lobbygame] FAIL the test finished"; $fails++ }
  if ($errors) { $fails++ }
  "[lobbygame] done: " + $(if ($fails -eq 0) { "ALL PASS" } else { "$fails FAILED" })
} finally {
  if ($p -and -not $p.HasExited) { $p.Kill(); $p.WaitForExit(5000) | Out-Null }
  Remove-LobbyLogin $Data
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
