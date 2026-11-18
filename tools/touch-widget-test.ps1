# bardroid_touch.lua in a real BAR skirmish on the laptop (BAR's released game, byar:test, vs BARb): a user widget
# (tools\touch-widget-test\bardroid_touch_test.lua) moves the pointer over the map, the top bar and an open settings
# window and checks the touch widget's "interface or map" answers. Isolated write dir build\touch-widget-test\data (the
# live install's packages, pool and rapid index joined read-only by junctions, removed again at the end).
#   powershell -ExecutionPolicy Bypass -File tools\touch-widget-test.ps1 [-Engine recoil_2026.09.01]
param(
  [string]$Engine = "",
  [string]$Map = "supreme_isthmus_v2.1.sd7",
  [string]$MapName = "Supreme Isthmus v2.1",
  [string]$Widget = "",   # another bardroid_touch.lua to test (default: the app's)
  [string]$TestWidget = "",   # a test widget in place of the cases, for one question (it logs "[touchtest] done" to end)
  [switch]$GamepadGame,   # the controller game (v0.8.5) as unpacked by tools\profile-gamepad-game.ps1, not byar:test
  [switch]$NoUnitControl, # BAR's "Allow Custom 'Unit Control' Widgets" unticked, as a host can (with -TestWidget ...\bardroid_rule_off_test.lua)
  # also the "what is under the pointer" checks, which move the laptop's real mouse pointer (Spring.WarpMouse): off by
  # default (Kailil, 2026-10-28: the tests must not take his mouse); run them when nobody is using the laptop
  [switch]$Pointer,
  # engine settings added for this run (springsettings.cfg keys), e.g. @{ CompressTextures = 1 }: run with -Command
  [hashtable]$Settings = @{}
)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\touch-widget-test"
$Data = Join-Path $Work "data"
. (Join-Path $PSScriptRoot "toolchain.ps1")
Assert-BarData
$Bar = $BarData
if (-not $Engine) { $Engine = (Get-ChildItem (Join-Path $Bar "engine") -Directory | Sort-Object Name | Select-Object -Last 1).Name }
$EngineDir = Get-EngineDir $Engine

New-Item -ItemType Directory -Force -Path "$Data\LuaUI\Widgets", "$Data\LuaUI\Config", "$Data\maps" | Out-Null
$links = foreach ($d in "packages", "pool", "rapid") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $Bar $d)" | Out-Null }
  $link
}
try {
  if (-not (Test-Path "$Data\maps\$Map")) { Copy-Item (Join-Path $Bar "maps\$Map") "$Data\maps\$Map" }
  if (-not $Widget) { $Widget = Join-Path $App "app\src\main\assets\bardroid\bardroid_touch.lua" }
  Remove-Item "$Data\LuaUI\Widgets\*.lua" -ErrorAction SilentlyContinue   # (only the widgets below: none left from before)
  Copy-Item $Widget "$Data\LuaUI\Widgets\bardroid_touch.lua" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_queue.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_chat.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_info.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_players.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_minimap.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_layout.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_buildmenu.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_ordermenu.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_pad.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_padspeed.lua") "$Data\LuaUI\Widgets\" -Force
  Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_padfp.lua") "$Data\LuaUI\Widgets\" -Force
  $cases = if ($TestWidget) { $TestWidget } else { Join-Path $PSScriptRoot "touch-widget-test\bardroid_touch_test.lua" }
  Copy-Item $cases "$Data\LuaUI\Widgets\bardroid_touch_test.lua" -Force
  Remove-Item "$Data\LuaUI\Config\bardroid_hover.txt", "$Data\LuaUI\Config\bardroid_screen.txt" -ErrorAction SilentlyContinue
  # the widget orders launch-bar.sh sets on the phone (BAR's own saved settings from a run before are dropped)
  $orders = @("Bloom Shader Deferred", "SSAO", "Distortion GL4", "Snow", "Map Edge Extension", "Show Builder Queue",
    "Deferred rendering GL4", "Decals GL4", "Ground AO Plates GL4", "Ground AO Plates Features GL4", "Map Grass GL4",
    "Commands FX", "Contrast Adaptive Sharpen", "Jammed Units Highlight", "Reclaim Field Highlight", "Ecostats", "Keybind/Mouse Info", "Changelog Info", "Screen Mode Info", "Picture-in-Picture Minimap", "Info") | ForEach-Object { "`t`t[`"$_`"] = 0," }
  $orders += "`t`t[`"Minimap`"] = 1,"
  # the build and order menus as launch-bar.sh sets them with the controller game on: BAR's off, the app's copies on
  # (the build menu's runs beside the controller game's own "Build menu (controller)", the order menu's stands down there)
  $orders += "`t`t[`"Grid menu`"] = 0,", "`t`t[`"Build menu`"] = 0,", "`t`t[`"BAR Droid build menu`"] = 165,",
    "`t`t[`"Build menu (controller)`"] = 165,", "`t`t[`"Order menu`"] = 0,", "`t`t[`"BAR Droid order menu`"] = 189,",
    "`t`t[`"Order menu (controller)`"] = 189,"
  # (the unpacked controller game carries the profiler's widget, which quits the game after its 100 s)
  if ($GamepadGame) { $orders += "`t`t[`"BAR Droid profile log`"] = 0," }
  "-- Widget Custom data and order, order = 0 disabled widget`nreturn {`n`tdata = {`n`t},`n`torder = {`n$($orders -join "`n")`n`t},`n}" |
    Set-Content "$Data\LuaUI\Config\BYAR.lua" -Encoding ascii
  ("Fullscreen = 0`nWindowBorderless = 0`nXResolutionWindowed = 1280`nYResolutionWindowed = 720`nWindowPosX = $(if ($Pointer) { 40 } else { $OffScreenX })`nWindowPosY = 40`nsnd_volmaster = 0`nLogFlushLevel = 0`nRapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev" +
    "`nbardroid_touchtest_pointer = $(if ($Pointer) { 1 } else { 0 })" +
    (($Settings.GetEnumerator() | ForEach-Object { "`n$($_.Name) = $($_.Value)" }) -join "")) |
    Set-Content "$Data\springsettings.cfg" -Encoding ascii

  if ($GamepadGame) {
    $sdd = Join-Path $App "build\profile\data\games\BAR-gamepad.sdd"
    if (-not (Test-Path "$sdd\modinfo.lua")) { throw "no ${sdd}: run tools\profile-gamepad-game.ps1 once" }
    # (one unpacked before build-gamepad-game.py named v0.8.5's order menu "Order menu (controller)" ran no order menu
    # at all here, BAR's "Order menu" being off: five cases failed, 2026-11-18)
    if (-not (Select-String -Path "$sdd\luaui\Widgets\gui_ordermenu.lua" -Pattern 'Order menu \(controller\)' -Quiet)) {
      throw "${sdd} is from before the packager's menu names: run tools\profile-gamepad-game.ps1 again"
    }
    New-Item -ItemType Directory -Force -Path "$Data\games" | Out-Null
    $gameLink = Join-Path $Data "games\BAR-gamepad.sdd"
    if (-not (Test-Path $gameLink)) { cmd /c mklink /J "$gameLink" "$sdd" | Out-Null }
    $links = @($links) + $gameLink
    $game = "Beyond All Reason `$VERSION"
  } else {
    $gameLink = Join-Path $Data "games\BAR-gamepad.sdd"   # a junction left by a killed -GamepadGame run: the link only
    if (Test-Path $gameLink) { cmd /c rmdir "$gameLink" }
    # byar:test -> the archive name the start script needs
    $gz = Join-Path $Bar "rapid\repos-cdn.beyondallreason.dev\byar\versions.gz"
    $reader = New-Object IO.StreamReader (New-Object IO.Compression.GZipStream ([IO.File]::OpenRead($gz)), ([IO.Compression.CompressionMode]::Decompress))
    $game = $null
    while (($l = $reader.ReadLine()) -ne $null) { if ($l.StartsWith("byar:test,")) { $game = $l.Split(",", 4)[3] } }
    $reader.Close()
    if (-not $game) { throw "byar:test not in $gz" }
  }
  $script = (Get-Content (Join-Path $App "app\src\main\assets\bardroid\skirmish.template.txt") -Raw).Replace("@GAME@", $game).Replace("@MAP@", $MapName)
  # the opponent the engine's NullAI (it does nothing): on a throttled laptop (4 fps) the cases run past ten game
  # minutes, and BARb's first raid killed the commander and ended the game midway (no case needs the enemy)
  if (Test-Path (Join-Path $EngineDir "AI\Skirmish\NullAI\0.1\AIInfo.lua")) {
    $script = $script.Replace("ShortName=BARb;", "ShortName=NullAI;").Replace("Version=stable;", "Version=0.1;")
  }
  if ($NoUnitControl) { $script = $script.Replace("deathmode=com;", "deathmode=com;`n`t`tallowunitcontrolwidgets=0;") }
  $startscript = Join-Path $Work "skirmish.txt"
  $script | Set-Content $startscript -Encoding ascii

  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  Write-Host "[touch-test] $game on $MapName, engine $Engine"
  $p = Start-Engine (Join-Path $EngineDir "spring.exe") $EngineDir @("--isolation", "--write-dir", "`"$Data`"", "`"$startscript`"")
  # stopped once the log stands still for 90 s (a hung game), not after a fixed time: a throttled laptop (screen off,
  # 7 fps) takes several times as long, and a fixed 240 s cut the cases off midway
  $hardStop = (Get-Date).AddMinutes(30)
  $lastSize = -1; $quietSince = Get-Date; $done = $false
  while (-not $p.HasExited -and (Get-Date) -lt $hardStop -and ((Get-Date) - $quietSince).TotalSeconds -lt 90 -and -not $done) {
    Start-Sleep 1
    $size = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
    if ($size -ne $lastSize) { $lastSize = $size; $quietSince = Get-Date }
    $done = (Test-Path $log) -and (Select-String -Path $log -Pattern '\[touchtest\] done' -Quiet)
  }
  $exited = $p.HasExited
  if (-not $exited) { $p.Kill() }   # (the game stays in after the last case)
  if (-not $done) {
    Write-Host "[touch-test] stopped before the end: $(if ($exited) { 'the game ended' } elseif ((Get-Date) -ge $hardStop) { '30 min' } else { 'the log stood still for 90 s' })"
  }
  Select-String -Path $log -Pattern "touchtest|bardroid-touch|bardroid_touch|bardroid-perf|bardroid-buildmenu|bardroid_buildmenu|BAR Droid build menu" |
    ForEach-Object { $_.Line }
  # any widget's error (BAR's handler removes that widget, often quietly for the cases: the pad, chat, info, players,
  # minimap or layout widget, or BAR's own after one of the app's): a FAIL line (laptop-tests counts it)
  Select-String -Path $log -CaseSensitive -Pattern "Error in [A-Za-z]+\(\)|Removed widget: " |
    ForEach-Object { "[touch-test] FAIL widget error: " + ($_.Line -replace '^\[t=[^\]]*\](\[f=[^\]]*\])? ', '') }
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
