<#
.SYNOPSIS
  BAR's "Benchmark BAR" scenario on the laptop, the way the phone runs it (tools/phone-bench.ps1), with every profiler
  logging to infolog: where a simulated frame's time goes when 1,300 units fight.

.DESCRIPTION
  - The phone's game: v0.8.5's overlay (tools/build-gamepad-game.py, games/BAR-gamepad.sdd) on the BAR release it was
    ported to (-Released: the plain release), the app's start script (assets/bardroid/benchmark.template.txt), the
    phone's widget orders and user widgets (launch-bar.sh, MODE=bench), Starwatcher 1.0 from the live install.
  - Profilers (laptop only, never in the APK), from frame 300 (the battle is on):
      tools/profile/dbg_bardroid_profile_log.lua      every widget's share (BAR's widget profiler module), -Window s
      tools/profile/dbg_bardroid_gadget_profile.lua   every unsynced gadget callin, per drawn and per simulated frame
      the engine's own timers (/debuginfo profiling) at frame 1500: Sim, Draw, synced and unsynced Lua (synced Lua
      cannot time single gadgets: synced code has no timer)
    -NoProfilers: none of them (each costs time itself), for comparing BAR's own result lines between runs.
  - Isolated write dir (build/profile-bench/data): the live BAR install is only read (packages/, pool/ linked in).
  The laptop's numbers are not the phone's (another CPU, not throttled): use them for shares and for A/B comparisons.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\profile-benchmark.ps1
  powershell -ExecutionPolicy Bypass -File tools\profile-benchmark.ps1 -NoProfilers -AlsoOff "Defense Range GL4"
#>
[CmdletBinding()]
param(
  [string]$Branch = "controller/codex-v085-perf",
  [string]$Repo = "C:\Tools\BARGAMEPAD\src\bar-codex",
  [string]$Engine = "recoil_2026.07.04",   # the phone's
  [int]$Window = 40,
  [string[]]$AlsoOff = @(),                # more widgets off (by name), to compare
  [hashtable]$Settings = @{},              # extra springsettings lines, to compare
  [switch]$NoProfilers,
  [string]$Detail = "BAR Droid touch camera",
  [switch]$Functions,                      # time each function of -Detail (inclusive) instead of each widget
  [switch]$Released
)

$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
Assert-BarData
$EngineDir = Get-EngineDir $Engine
$Work = Join-Path $App "build\profile-bench"
$Data = Join-Path $Work "data"
$Sdd = Join-Path $Data "games\BAR-gamepad.sdd"
Remove-Item -Recurse -Force (Join-Path $Data "LuaUI"), (Join-Path $Data "games") -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $Data "games"), (Join-Path $Data "maps"), (Join-Path $Data "LuaUI\Config"), (Join-Path $Data "LuaUI\Widgets") | Out-Null

# the game: v0.8.5's overlay as the app lays it out (or a tiny overlay of our own on the plain release), plus profilers
$py = "call `"$App\scripts\env.bat`" >nul && python -I `"$App\tools\build-gamepad-game.py`" --repo `"$Repo`" --branch $Branch --out `"$Work\pkg`" --unpack `"$Sdd`" --bar-data `"$BarData`""
cmd /c $py
if ($LASTEXITCODE -ne 0) { throw "build-gamepad-game.py failed" }
if ($Released) {
  $base = (Get-Content "$Work\pkg\gamepad.properties" | Where-Object { $_ -match '^base.name = ' }) -replace '^base.name = ', ''
  Remove-Item -Recurse -Force $Sdd
  New-Item -ItemType Directory -Force -Path (Join-Path $Sdd "luaui\Widgets") | Out-Null
  "return { name = `"Beyond All Reason`", shortName = `"BYAR`", version = `"`$VERSION`", game = `"Beyond All Reason`", shortGame = `"BYAR`", modtype = 1, depend = { `"$base`" } }" |
    Set-Content -Path (Join-Path $Sdd "modinfo.lua") -Encoding ascii
}
if (-not $NoProfilers) {
  New-Item -ItemType Directory -Force -Path (Join-Path $Sdd "luarules\gadgets"), (Join-Path $Sdd "luaui\Widgets") | Out-Null
  foreach ($f in "dbg_bardroid_profile_log.lua", "dbg_bardroid_bench_go.lua") { Copy-Item (Join-Path $PSScriptRoot "profile\$f") (Join-Path $Sdd "luaui\Widgets\") }
  Copy-Item (Join-Path $PSScriptRoot "profile\dbg_bardroid_gadget_profile.lua") (Join-Path $Sdd "luarules\gadgets\")
}
$game = "Beyond All Reason `$VERSION"

# content from the live install, read only
$links = foreach ($d in "packages", "pool") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $BarData $d)" | Out-Null }
  $link
}
try {
  $mapDst = Join-Path $Data "maps\starwatcher_1.0.sd7"
  if (-not (Test-Path $mapDst)) { Copy-Item (Join-Path $BarData "maps\starwatcher_1.0.sd7") $mapDst }

  # the phone's user widgets and the files the app keeps for them
  foreach ($f in "bardroid_touch.lua", "bardroid_queue.lua", "bardroid_chat.lua", "bardroid_info.lua", "bardroid_players.lua", "bardroid_bench.lua") {
    Copy-Item (Join-Path $App "app\src\main\assets\bardroid\$f") (Join-Path $Data "LuaUI\Widgets\") -Force
  }
  Set-Content (Join-Path $Data "LuaUI\Config\bardroid_touch.txt") -Value $null -NoNewline
  "1680 720 60 0" | Set-Content (Join-Path $Data "LuaUI\Config\bardroid_screen.txt") -Encoding ascii
  "1" | Set-Content (Join-Path $Data "LuaUI\Config\bardroid_bench.txt") -Encoding ascii   # bardroid_bench.lua: quit after the results
  # the widget orders launch-bar.sh sets on the phone for a benchmark
  $off = @("Bloom Shader Deferred", "SSAO", "Distortion GL4", "Snow", "Map Edge Extension", "Show Builder Queue",
    "Deferred rendering GL4", "Decals GL4", "Ground AO Plates GL4", "Ground AO Plates Features GL4", "Map Grass GL4",
    "Commands FX", "Contrast Adaptive Sharpen", "Jammed Units Highlight", "Keybind/Mouse Info", "Changelog Info",
    "Picture-in-Picture Minimap", "Fog Diagonal Lines GL4", "Info", "Mission Info") + $AlsoOff
  $orders = @($off | ForEach-Object { "`t`t[`"$_`"] = 0," }) + "`t`t[`"Minimap`"] = 1," + "`t`t[`"BAR Droid profile log`"] = 1," +
    "`t`t[`"Build menu`"] = $(if ($Released) { 0 } else { 165 })," + "`t`t[`"Grid menu`"] = $(if ($Released) { 113 } else { 0 }),"
  "-- Widget Custom data and order, order = 0 disabled widget`nreturn {`n`tdata = {`n`t},`n`torder = {`n$($orders -join "`n")`n`t},`n}" |
    Set-Content (Join-Path $Data "LuaUI\Config\BYAR.lua") -Encoding ascii
  # the phone's graphics (launch-bar.sh PHONE_GFX and Kailil's Lowest preset), a window the size of the folded X screen
  @"
RapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev
LogFlushLevel = 0
Fullscreen = 0
WindowBorderless = 0
XResolutionWindowed = 1680
YResolutionWindowed = 720
WindowPosX = 20
WindowPosY = 40
snd_volmaster = 0
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
AdvMapShading = 0
Water = 0
MaxNanoParticles = 0
WorkerThreadCount = 4
bardroid_profile_wait_go = 1
bardroid_profile_warmup = 1
bardroid_profile_window = $Window
bardroid_profile_detail = $Detail
bardroid_profile_functions = $(if ($Functions) { 1 } else { 0 })
bardroid_profile_quit = 0
$(($Settings.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join "`n")
"@ | Set-Content -Path (Join-Path $Data "springsettings.cfg") -Encoding ascii

  $startscript = Join-Path $Work "bench.txt"
  (Get-Content (Join-Path $App "app\src\main\assets\bardroid\benchmark.template.txt") -Raw).Replace("@GAME@", $game) |
    Set-Content -Path $startscript -Encoding ascii

  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  Write-Host "[profile-bench] $(if ($Released) { 'BAR release' } else { $Branch }), engine $Engine, profilers $(-not $NoProfilers), off: $($AlsoOff -join ', ')"
  $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "`"$startscript`"" -WorkingDirectory $EngineDir -PassThru
  if (-not $p.WaitForExit(15 * 60 * 1000)) { $p.Kill(); Write-Host "[profile-bench] timed out; see $log" -ForegroundColor Red }
  $lines = Get-Content $log
  $lines | Select-String -Pattern '\[bardroid-(profile|gprofile|bench-profile|bench)\]|Benchmark complete|(Draw|Sim|Update) \d+ frames|Error in |Removed (widget|gadget)' |
    ForEach-Object { $_.Line -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  $i = ($lines | Select-String -Pattern 'engine timers at frame' | Select-Object -First 1).LineNumber
  if ($i) { $lines[$i..([Math]::Min($lines.Count - 1, $i + 90))] | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' } | Select-String -NotMatch '\[bardroid' | ForEach-Object { $_.Line } }
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
