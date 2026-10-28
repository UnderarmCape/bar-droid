# bardroid_lobby_touch.lua in the real lobby on the laptop: BAR's Windows engine runs byar-chobby:test in an isolated
# write dir (build\lobby-touch-test\data; the live install's packages, pool and rapid index joined read-only by
# junctions, removed again at the end) with the app's lobby widget and a test widget that builds a list of fake
# servers and plain rows and drives it as a finger would (~20 s), offline (the test lobby never logs in: toolchain.ps1 Write-LobbyConfig).
#   powershell -ExecutionPolicy Bypass -File tools\lobby-touch-test.ps1 [-Engine recoil_2026.09.01]
param([string]$Engine = "")
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\lobby-touch-test"
$Data = Join-Path $Work "data"
. (Join-Path $PSScriptRoot "toolchain.ps1")
Assert-BarData
$Bar = $BarData
if (-not $Engine) { $Engine = (Get-ChildItem (Join-Path $Bar "engine") -Directory | Sort-Object Name | Select-Object -Last 1).Name }
$EngineDir = Get-EngineDir $Engine

Remove-Item -Recurse -Force "$Data\LuaMenu" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Data\LuaMenu\Config", "$Data\LuaMenu\Widgets" | Out-Null
$links = foreach ($d in "packages", "pool", "rapid") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $Bar $d)" | Out-Null }
  $link
}
try {
  # as launch-bar.sh leaves it: the lobby loads local widgets, interface scale 120% at every window size
  $scales = (0..5 | ForEach-Object { $x = $_; 0..11 | ForEach-Object { "[`"${x}x$_`"] = 1.2," } }) -join " "
  Write-LobbyConfig $Data "loadLocalWidgets = true, panel_layout = 3, uiScalesForScreenSizes = { $scales },"
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_lobby_touch.lua") "$Data\LuaMenu\Widgets\" -Force
  Copy-Item (Join-Path $PSScriptRoot "lobby-touch-test\bardroid_lobby_touch_test.lua") "$Data\LuaMenu\Widgets\" -Force
  '{"server": {"address": "server4.beyondallreason.info", "port": 8200, "protocol": "spring", "serverName": "BAR"}, "game": "byar"}' |
    Set-Content "$Data\chobby_config.json" -Encoding ascii
  "Fullscreen = 0`nWindowBorderless = 0`nXResolutionWindowed = 1280`nYResolutionWindowed = 720`nWindowPosX = 40`nWindowPosY = 40`nsnd_volmaster = 0`nLogFlushLevel = 0`nRapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev" |
    Set-Content "$Data\springsettings.cfg" -Encoding ascii
  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  Write-Host "[lobby-touch-test] engine $Engine"
  $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -WorkingDirectory $EngineDir -PassThru `
    -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "--menu", "rapid://byar-chobby:test"
  $r = Wait-LobbyTest $p $log '\[lobbytouch\] done'
  Start-Sleep 2
  if (-not $p.HasExited) { $p.Kill() }
  Select-String -Path $log -Pattern '\[lobbytouch\]|\[lobbylogin\]|BAR Droid lobby|bardroid_lobby' |
    ForEach-Object { $_.Line -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  if ($r -ne "done") { "[lobbytouch] FAIL the test ran: $r" }
} finally {
  if ($p -and -not $p.HasExited) { $p.Kill(); $p.WaitForExit(5000) | Out-Null }
  Remove-LobbyLogin $Data
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
