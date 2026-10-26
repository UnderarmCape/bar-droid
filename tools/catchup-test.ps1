# Catch-up on the laptop: a headless host plays BARb vs BARb on 127.0.0.1, and after -Warmup seconds a windowed
# spectator joins and catches up, twice: with the touch widget's catch-up mode off (bardroid_catchup = 0) and on.
# Logs the probe's lines (game frames and pictures per 5 s) and the widget's [bardroid-catchup] lines of each join.
# Isolated write dirs under build\catchup-test (the live install's packages, pool and rapid index joined read-only by
# junctions, removed again at the end).
#   powershell -ExecutionPolicy Bypass -File tools\catchup-test.ps1 [-Warmup 300]
param(
  [int]$Warmup = 300,   # seconds of game before the first join (game time = real time on the host)
  [string]$Engine = "",
  [string]$Map = "supreme_isthmus_v2.1.sd7",
  [string]$MapName = "Supreme Isthmus v2.1"
)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\catchup-test"
$Bar = Join-Path $env:LOCALAPPDATA "Programs\Beyond-All-Reason\data"
if (-not $Engine) { $Engine = (Get-ChildItem (Join-Path $Bar "engine") -Directory | Sort-Object Name | Select-Object -Last 1).Name }
$EngineDir = Join-Path $Bar "engine\$Engine"
$Port = 8452

$gz = Join-Path $Bar "rapid\repos-cdn.beyondallreason.dev\byar\versions.gz"
$reader = New-Object IO.StreamReader (New-Object IO.Compression.GZipStream ([IO.File]::OpenRead($gz)), ([IO.Compression.CompressionMode]::Decompress))
$game = $null
while (($l = $reader.ReadLine()) -ne $null) { if ($l.StartsWith("byar:test,")) { $game = $l.Split(",", 4)[3] } }
$reader.Close()
if (-not $game) { throw "byar:test not in $gz" }

$links = @()
function New-WriteDir($dir) {
  New-Item -ItemType Directory -Force -Path "$dir\LuaUI\Widgets", "$dir\LuaUI\Config", "$dir\maps" | Out-Null
  foreach ($d in "packages", "pool", "rapid") {
    $link = Join-Path $dir $d
    if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $Bar $d)" | Out-Null }
    $script:links += $link
  }
  if (-not (Test-Path "$dir\maps\$Map")) { Copy-Item (Join-Path $Bar "maps\$Map") "$dir\maps\$Map" }
}

$hostScript = @"
[GAME]
{
	MapName=$MapName;
	GameType=$game;
	GameStartDelay=3;
	StartPosType=1;
	MyPlayerName=Host;
	IsHost=1;
	HostIP=127.0.0.1;
	HostPort=$Port;
	[MODOPTIONS] { deathmode=com; }
	[ALLYTEAM0] { NumAllies=0; }
	[ALLYTEAM1] { NumAllies=0; }
	[TEAM0] { Side=Armada; Handicap=0; AllyTeam=0; TeamLeader=0; }
	[TEAM1] { Side=Cortex; Handicap=0; AllyTeam=1; TeamLeader=0; }
	[AI0] { Host=0; Name=BARb1; ShortName=BARb; Team=0; Version=stable; }
	[AI1] { Host=0; Name=BARb2; ShortName=BARb; Team=1; Version=stable; }
	[PLAYER0] { Name=Host; Spectator=1; Team=0; }
	[PLAYER1] { Name=Watcher1; Spectator=1; Team=0; }
	[PLAYER2] { Name=Watcher2; Spectator=1; Team=0; }
}
"@

$hostProc = $null
try {
  $hostDir = Join-Path $Work "host"; New-WriteDir $hostDir
  "LogFlushLevel = 0`nRapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev" | Set-Content "$hostDir\springsettings.cfg" -Encoding ascii
  $hostScript | Set-Content "$Work\host.txt" -Encoding ascii
  Remove-Item "$hostDir\infolog.txt" -ErrorAction SilentlyContinue
  Write-Host "[catchup-test] host: $game on $MapName, engine $Engine, BARb vs BARb; first join after $Warmup s of game"
  $hostProc = Start-Process -FilePath (Join-Path $EngineDir "spring-headless.exe") -WorkingDirectory $EngineDir -PassThru -WindowStyle Hidden `
    -ArgumentList "--isolation", "--write-dir", "`"$hostDir`"", "`"$Work\host.txt`""
  $deadline = (Get-Date).AddSeconds(240)
  while (-not ((Test-Path "$hostDir\infolog.txt") -and (Select-String -Path "$hostDir\infolog.txt" -Pattern '\[Initial Spawn\]' -Quiet))) {
    if ($hostProc.HasExited -or (Get-Date) -gt $deadline) { throw "the host's game did not start (see $hostDir\infolog.txt)" }
    Start-Sleep 2
  }
  Start-Sleep $Warmup

  $clientDir = Join-Path $Work "client"; New-WriteDir $clientDir
  foreach ($f in "bardroid_touch.lua", "bardroid_queue.lua") { Copy-Item (Join-Path $App "app\src\main\assets\bardroid\$f") "$clientDir\LuaUI\Widgets\" -Force }
  Copy-Item (Join-Path $PSScriptRoot "catchup-test\bardroid_catchup_probe.lua") "$clientDir\LuaUI\Widgets\" -Force
  $n = 0
  foreach ($mode in 0, 1) {
    $n++
    "Fullscreen = 0`nWindowBorderless = 0`nXResolutionWindowed = 1280`nYResolutionWindowed = 720`nWindowPosX = 40`nWindowPosY = 40`nsnd_volmaster = 0`nLogFlushLevel = 0`nbardroid_catchup = $mode`nRapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev" |
      Set-Content "$clientDir\springsettings.cfg" -Encoding ascii
    "[GAME]`n{`n`tHostIP=127.0.0.1;`n`tHostPort=$Port;`n`tIsHost=0;`n`tMyPlayerName=Watcher$n;`n`tMyPasswd=;`n}" | Set-Content "$Work\client.txt" -Encoding ascii
    $log = "$clientDir\infolog.txt"
    Remove-Item $log -ErrorAction SilentlyContinue
    Write-Host "[catchup-test] join $n, catch-up mode $(if ($mode) { 'on' } else { 'off' })"
    $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -WorkingDirectory $EngineDir -PassThru `
      -ArgumentList "--isolation", "--write-dir", "`"$clientDir`"", "`"$Work\client.txt`""
    if (-not $p.WaitForExit(660000)) { $p.Kill() }
    Copy-Item $log "$Work\client-$n-catchup$mode.txt" -Force
    Select-String -Path $log -Pattern "catchup-probe|bardroid-catchup|bardroid_touch|Error in" | ForEach-Object { "   " + $_.Line }
  }
} finally {
  if ($hostProc -and -not $hostProc.HasExited) { $hostProc.Kill() }
  Start-Sleep 2
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
