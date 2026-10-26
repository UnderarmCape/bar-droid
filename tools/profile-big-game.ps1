# Where a big game's CPU time goes, on the laptop the way the phone runs BAR's released game: a windowed spectator hosts
# -AIs BARb (teams alternating), fast-forwarded (-Speed) to -FastMinutes of game, then at 1x BAR's widget profiler
# (tools/profile/dbg_bardroid_profile_log.lua, in a tiny game overlay of its own: it needs a game widget's rights)
# measures every widget for -Window seconds, and the engine's own timers (/debuginfo profiling: simulation, drawing,
# Lua) are logged on the way. The phone's widget orders and user widgets (bardroid_touch.lua, bardroid_queue.lua).
# Isolated write dir build\profile-big\data (the live install's packages, pool and rapid index joined read-only by
# junctions, removed again at the end).
#   powershell -ExecutionPolicy Bypass -File tools\profile-big-game.ps1 [-AIs 6] [-FastMinutes 25]
param(
  [int]$AIs = 6,
  [int]$FastMinutes = 25,
  [double]$Speed = 10,
  [int]$Window = 60,
  [string]$Engine = "",
  [string]$Map = "supreme_isthmus_v2.1.sd7",
  [string]$MapName = "Supreme Isthmus v2.1",
  [string[]]$AlsoOff = @(),  # more widgets off (by name), to compare
  [string]$Detail = "BAR Droid touch camera",
  [switch]$Functions         # time each callin/global function of -Detail instead of each widget
)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\profile-big"
$Data = Join-Path $Work "data"
$Bar = Join-Path $env:LOCALAPPDATA "Programs\Beyond-All-Reason\data"
if (-not $Engine) { $Engine = (Get-ChildItem (Join-Path $Bar "engine") -Directory | Sort-Object Name | Select-Object -Last 1).Name }
$EngineDir = Join-Path $Bar "engine\$Engine"

$gz = Join-Path $Bar "rapid\repos-cdn.beyondallreason.dev\byar\versions.gz"
$reader = New-Object IO.StreamReader (New-Object IO.Compression.GZipStream ([IO.File]::OpenRead($gz)), ([IO.Compression.CompressionMode]::Decompress))
$base = $null
while (($l = $reader.ReadLine()) -ne $null) { if ($l.StartsWith("byar:test,")) { $base = $l.Split(",", 4)[3] } }
$reader.Close()
if (-not $base) { throw "byar:test not in $gz" }

Remove-Item -Recurse -Force "$Data\LuaUI", "$Data\games" -ErrorAction SilentlyContinue
$Sdd = Join-Path $Data "games\BAR-profile.sdd"
New-Item -ItemType Directory -Force -Path "$Data\LuaUI\Widgets", "$Data\LuaUI\Config", "$Data\maps", "$Sdd\luaui\Widgets" | Out-Null
Copy-Item (Join-Path $PSScriptRoot "profile\dbg_bardroid_profile_log.lua") "$Sdd\luaui\Widgets\"
"return { name = `"Beyond All Reason`", shortName = `"BYAR`", version = `"`$VERSION`", game = `"Beyond All Reason`", shortGame = `"BYAR`", modtype = 1, depend = { `"$base`" } }" |
  Set-Content -Path "$Sdd\modinfo.lua" -Encoding ascii

$links = foreach ($d in "packages", "pool", "rapid") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $Bar $d)" | Out-Null }
  $link
}
try {
  if (-not (Test-Path "$Data\maps\$Map")) { Copy-Item (Join-Path $Bar "maps\$Map") "$Data\maps\$Map" }
  foreach ($f in "bardroid_touch.lua", "bardroid_queue.lua") { Copy-Item (Join-Path $App "app\src\main\assets\bardroid\$f") "$Data\LuaUI\Widgets\" -Force }
  Copy-Item (Join-Path $PSScriptRoot "catchup-test\bardroid_host_speed.lua") "$Data\LuaUI\Widgets\" -Force
  # the files the app keeps for the touch widget (an empty touch log, the X screen size)
  Set-Content "$Data\LuaUI\Config\bardroid_touch.txt" -Value $null -NoNewline
  "1280 720 60 0" | Set-Content "$Data\LuaUI\Config\bardroid_screen.txt" -Encoding ascii
  # the widget orders launch-bar.sh sets on the phone
  $off = @("Bloom Shader Deferred", "SSAO", "Distortion GL4", "Snow", "Map Edge Extension", "Show Builder Queue",
    "Deferred rendering GL4", "Decals GL4", "Ground AO Plates GL4", "Ground AO Plates Features GL4", "Map Grass GL4",
    "Commands FX", "Keybind/Mouse Info", "Changelog Info", "Picture-in-Picture Minimap") + $AlsoOff
  $orders = @($off | ForEach-Object { "`t`t[`"$_`"] = 0," }) + "`t`t[`"Minimap`"] = 1," + "`t`t[`"BAR Droid profile log`"] = 1,"
  "-- Widget Custom data and order, order = 0 disabled widget`nreturn {`n`tdata = {`n`t},`n`torder = {`n$($orders -join "`n")`n`t},`n}" |
    Set-Content "$Data\LuaUI\Config\BYAR.lua" -Encoding ascii
  # the phone's graphics (launch-bar.sh PHONE_GFX), a phone-sized window
  @"
Fullscreen = 0
WindowBorderless = 0
XResolutionWindowed = 1280
YResolutionWindowed = 720
WindowPosX = 40
WindowPosY = 40
snd_volmaster = 0
LogFlushLevel = 0
VSync = 0
MSAALevel = 0
Shadows = 0
ShadowQuality = 0
FeatureDrawDistance = 6000
FeatureFadeDistance = 4800
GroundDetail = 60
BumpWaterReflection = 0
BumpWaterRefraction = 0
GrassDetail = 0
UnitIconFadeStart = 1
UnitIconFadeVanish = 1
RapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev
bardroid_profile_wait_go = 1
bardroid_profile_warmup = 5
bardroid_profile_window = $Window
bardroid_profile_detail = $Detail
bardroid_profile_functions = $(if ($Functions) { 1 } else { 0 })
bardroid_host_speed = $Speed
bardroid_host_fast_until = $($FastMinutes * 1800)
bardroid_host_engine_profile_after = $([Math]::Max(10, $Window - 10))
"@ | Set-Content "$Data\springsettings.cfg" -Encoding ascii

  $teams = for ($i = 0; $i -lt $AIs; $i++) {
    "`t[TEAM$i] { Side=$(if ($i % 2) { 'Cortex' } else { 'Armada' }); Handicap=0; AllyTeam=$($i % 2); TeamLeader=0; }"
    "`t[AI$i] { Host=0; Name=BARb$($i + 1); ShortName=BARb; Team=$i; Version=stable; }"
  }
  @"
[GAME]
{
	MapName=$MapName;
	GameType=Beyond All Reason `$VERSION;
	GameStartDelay=3;
	StartPosType=1;
	MyPlayerName=Host;
	IsHost=1;
	HostIP=127.0.0.1;
	HostPort=0;
	MaxSpeed=20;
	[MODOPTIONS] { deathmode=com; }
	[ALLYTEAM0] { NumAllies=0; }
	[ALLYTEAM1] { NumAllies=0; }
$($teams -join "`n")
	[PLAYER0] { Name=Host; Spectator=1; Team=0; }
}
"@ | Set-Content "$Work\script.txt" -Encoding ascii

  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  Write-Host "[profile-big] $base + profiler, engine $Engine, $AIs BARb, fast to $FastMinutes min at x$Speed, then $Window s measured"
  $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -WorkingDirectory $EngineDir -PassThru `
    -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "`"$Work\script.txt`""
  if (-not $p.WaitForExit(($FastMinutes * 60 + $Window + 600) * 1000)) { $p.Kill(); Write-Host "[profile-big] timed out" }
  Get-Content $log | Select-String -Pattern '\[bardroid-profile\]|\[catchup-host\]|Error in |Removed widget' |
    ForEach-Object { $_.Line -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  # the engine's timers (/debuginfo profiling): the table after the host widget's line
  $lines = Get-Content $log
  $i = ($lines | Select-String -Pattern 'engine timers at' | Select-Object -First 1).LineNumber
  if ($i) { $lines[$i..([Math]::Min($lines.Count - 1, $i + 80))] | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' } }
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
