# LobbyBridge against the real lobby, on the laptop: BAR's Windows engine runs the lobby (byar-chobby:test) in an
# isolated write dir (build\lobby-bridge-test\data) that joins the live install's packages, pool and rapid index in
# read-only (junctions, removed again at the end), and LobbyBridge.java runs on the toolchain's JDK with stand-ins for
# Android, org.json and the container (tools\lobby-bridge-test\src; game/map downloads only log). A LuaMenu widget opens
# the Replays tab and a web link. Prints the bridge's log and the lobby's bridge lines; a lobby error shows there too.
#   powershell -ExecutionPolicy Bypass -File tools\lobby-bridge-test.ps1 [-Engine recoil_2026.09.01] [-Replays 4]
param(
  [string]$Engine = "",
  [int]$Replays = 4
)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Src = Join-Path $PSScriptRoot "lobby-bridge-test"
$Work = Join-Path $App "build\lobby-bridge-test"
$Data = Join-Path $Work "data"
$Bar = Join-Path $env:LOCALAPPDATA "Programs\Beyond-All-Reason\data"
if (-not $Engine) { $Engine = (Get-ChildItem (Join-Path $Bar "engine") -Directory | Sort-Object Name | Select-Object -Last 1).Name }
$EngineDir = Join-Path $Bar "engine\$Engine"

New-Item -ItemType Directory -Force -Path "$Data\LuaMenu\Config", "$Data\LuaMenu\Widgets", "$Data\demos" | Out-Null
$links = foreach ($d in "packages", "pool", "rapid") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $Bar $d)" | Out-Null }
  $link
}
try {
  Get-ChildItem (Join-Path $Bar "demos") -Filter *.sdfz | Sort-Object LastWriteTime -Descending | Select-Object -First $Replays |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $Data "demos") -Force }
  'return { ["Chili lobby"] = { loadLocalWidgets = true, }, }' | Set-Content "$Data\LuaMenu\Config\IGL_data.lua" -Encoding ascii
  Copy-Item (Join-Path $Src "bardroid_bridge_test.lua") "$Data\LuaMenu\Widgets\" -Force
  '{"server": {"address": "server4.beyondallreason.info", "port": 8200, "protocol": "spring", "serverName": "BAR"}, "game": "byar"}' |
    Set-Content "$Data\chobby_config.json" -Encoding ascii
  "Fullscreen = 0`nWindowBorderless = 0`nXResolutionWindowed = 1280`nYResolutionWindowed = 720`nWindowPosX = 40`nWindowPosY = 40`nsnd_volmaster = 0`nLogFlushLevel = 0`nRapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev" |
    Set-Content "$Data\springsettings.cfg" -Encoding ascii

  $classes = Join-Path $Work "classes"
  Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
  $javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
  $java = Join-Path (Split-Path $javac) "java.exe"
  $env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
  $sources = @(Get-ChildItem (Join-Path $Src "src") -Recurse -Filter *.java | ForEach-Object FullName) +
    (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\LobbyBridge.java")
  & $javac -nowarn -d $classes $sources
  if ($LASTEXITCODE -ne 0) { throw "javac failed" }
  $bridge = Start-Process -FilePath $java -ArgumentList "-cp", "`"$classes`"", "com.underarmcape.bardroid.BridgeMain", "`"$Data`"", "120" `
    -RedirectStandardOutput "$Work\bridge.log" -RedirectStandardError "$Work\bridge.err" -PassThru -WindowStyle Hidden
  Start-Sleep 3

  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  Write-Host "[bridge-test] engine $Engine, $Replays replays"
  $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -WorkingDirectory $EngineDir -PassThru `
    -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "--menu", "rapid://byar-chobby:test"
  $deadline = (Get-Date).AddSeconds(90)
  while (-not $p.HasExited -and (Get-Date) -lt $deadline -and
         -not ((Test-Path $log) -and (Select-String -Path $log -Pattern '\[bridgetest\] done' -Quiet))) { Start-Sleep 1 }
  if (-not $p.HasExited) { $p.Kill() }
  if (-not $bridge.HasExited) { $bridge.Kill() }
  Write-Host "---- bridge"; Get-Content "$Work\bridge.log"
  Write-Host "---- lobby"
  Select-String -Path $log -Pattern "bridgetest|spring-launcher|WrapperLoopback|ReplayHandler|Error" |
    Where-Object { $_.Line -notmatch "CPoolArchive|CBufferedArchive" } | ForEach-Object { $_.Line }
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
