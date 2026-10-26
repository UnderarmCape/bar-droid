<#
.SYNOPSIS
  Profiles the controller game (BAR Controller Support v0.8.5) on the laptop the way the phone runs it, and prints
  each widget's share of the time and its garbage.

.DESCRIPTION
  - Packs the chosen v0.8.5 branch with tools/build-gamepad-game.py and lays it out as games/BAR-gamepad.sdd, the
    overlay on the BAR release it was ported to, plus tools/profile/dbg_bardroid_profile_log.lua (BAR's own widget
    profiler module, logged to infolog instead of drawn).
  - Isolated write dir (build/profile/data): the live BAR install is only read (its packages/ and pool/ are linked
    in, the map is copied). Build menu on, Grid menu off, as the app sets it up.
  - A skirmish against BARb on Supreme Isthmus; with -Pad, BARGAMEPAD's companion plays a scripted pad (--fake).
  - Prints the [bardroid-profile] report when the widget quits the game.
  The game window opens on the desktop (and v0.8.5 moves the OS cursor while the pad is active).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\profile-gamepad-game.ps1 -Branch controller/codex-v085-perf -Pad
#>
[CmdletBinding()]
param(
  [string]$Branch = "controller/codex-v085-perf", # what the app packages; controller/codex-v085-release = the original
  [string]$Repo = "C:\Tools\BARGAMEPAD\src\bar-codex",
  [string]$EngineDir = "C:\Tools\BARGAMEPAD\builds\engine-2026.07.04",
  [string]$Companion = "C:\Tools\BARGAMEPAD\tools\companion\BARGamepadCompanion.exe",
  [string]$BarData = (Join-Path $env:LOCALAPPDATA "Programs\Beyond-All-Reason\data"),
  [string]$Map = "supreme_isthmus_v2.1.sd7",
  [string]$MapName = "Supreme Isthmus v2.1",
  [int]$Warmup = 40,
  [int]$Window = 60,
  [string]$Detail = "Controller Camera Test",
  [switch]$Pad,
  [switch]$Functions, # time each of the detail widget's functions instead of each widget
  [switch]$Released # BAR's released game of the base (no v0.8.5) for comparison
)

$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\profile"
$Data = Join-Path $Work "data"
$Sdd = Join-Path $Data "games\BAR-gamepad.sdd"
New-Item -ItemType Directory -Force -Path (Join-Path $Data "games"), (Join-Path $Data "maps"), (Join-Path $Data "LuaUI\Config") | Out-Null

# the game: v0.8.5's overlay, laid out as the app does, plus the logging profiler
$py = "call C:\Tools\BARANDROID\toolchain\env.bat >nul && python -I `"$App\tools\build-gamepad-game.py`" --repo `"$Repo`" --branch $Branch --out `"$Work\pkg`" --unpack `"$Sdd`" --bar-data `"$BarData`""
cmd /c $py
if ($LASTEXITCODE -ne 0) { throw "build-gamepad-game.py failed" }
Copy-Item (Join-Path $App "tools\profile\dbg_bardroid_profile_log.lua") (Join-Path $Sdd "luaui\Widgets\")
$game = "Beyond All Reason `$VERSION"
if ($Released) {
  # the same widget in a tiny overlay of its own on the plain release
  $base = (Get-Content "$Work\pkg\gamepad.properties" | Where-Object { $_ -match '^base.name = ' }) -replace '^base.name = ', ''
  Remove-Item -Recurse -Force $Sdd
  New-Item -ItemType Directory -Force -Path (Join-Path $Sdd "luaui\Widgets") | Out-Null
  Copy-Item (Join-Path $App "tools\profile\dbg_bardroid_profile_log.lua") (Join-Path $Sdd "luaui\Widgets\")
  "return { name = `"Beyond All Reason`", shortName = `"BYAR`", version = `"`$VERSION`", game = `"Beyond All Reason`", shortGame = `"BYAR`", modtype = 1, depend = { `"$base`" } }" |
    Set-Content -Path (Join-Path $Sdd "modinfo.lua") -Encoding ascii
}

# content from the live install, read only
foreach ($d in "packages", "pool") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $BarData $d)" | Out-Null }
}
$mapDst = Join-Path $Data "maps\$Map"
if (-not (Test-Path $mapDst)) { Copy-Item (Join-Path $BarData "maps\$Map") $mapDst }

@"
-- Widget Custom data and order, order = 0 disabled widget
return {
	order = {
		["Build menu"] = $(if ($Released) { 0 } else { 165 }),
		["Grid menu"] = $(if ($Released) { 113 } else { 0 }),
		["BAR Droid profile log"] = 1,
	},
}
"@ | Set-Content -Path (Join-Path $Data "LuaUI\Config\BYAR.lua") -Encoding ascii
@"
RapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev
LogFlushLevel = 0
Fullscreen = 0
WindowBorderless = 0
XResolutionWindowed = 1280
YResolutionWindowed = 720
WindowPosX = 40
WindowPosY = 40
snd_volmaster = 0
VSync = 0
bardroid_profile_warmup = $Warmup
bardroid_profile_window = $Window
bardroid_profile_detail = $Detail
bardroid_profile_functions = $(if ($Functions) { 1 } else { 0 })
"@ | Set-Content -Path (Join-Path $Data "springsettings.cfg") -Encoding ascii

$template = Get-Content (Join-Path $App "app\src\main\assets\bardroid\skirmish.template.txt") -Raw
$script = $template.Replace("@GAME@", $game).Replace("@MAP@", $MapName)
$startscript = Join-Path $Work "skirmish.txt"
$script | Set-Content -Path $startscript -Encoding ascii

$log = Join-Path $Data "infolog.txt"
Remove-Item $log -ErrorAction SilentlyContinue
Write-Host "[profile] $(if ($Released) { 'BAR release (no v0.8.5)' } else { $Branch }), pad: $([bool]$Pad), warmup $Warmup s, window $Window s"
$p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "`"$startscript`"" -WorkingDirectory $EngineDir -PassThru
if ($Pad) {
  while (-not $p.HasExited -and -not ((Test-Path $log) -and (Select-String -Path $log -Pattern '\[f=0+[1-9]\d*\]' -Quiet))) { Start-Sleep -Milliseconds 500 }
  Start-Process -FilePath $Companion -ArgumentList "--until-pid", $p.Id, "--fake", "--codex" -WindowStyle Hidden | Out-Null
}
if (-not $p.WaitForExit(($Warmup + $Window + 240) * 1000)) { $p.Kill(); Write-Host "[profile] timed out; see $log" -ForegroundColor Red }
Get-Content $log | Select-String -Pattern '\[bardroid-profile\]|Error in |Removed widget' | ForEach-Object { $_.Line -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
