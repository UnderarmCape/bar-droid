# BAR's in-game interface at a Fold screen's layout, on the laptop: a skirmish (byar:test, vs BARb) in a window of the
# screen's shape, BAR's interface scale as the phone sets it, with or without the phone layer's widget changes
# (Keys/Changes off, BAR's full-screen effects off), and a screenshot after ~5 s of game. BAR sizes its interface by
# the window height and places it by the width, so a smaller window of the same shape shows the same layout.
#   powershell -ExecutionPolicy Bypass -File tools\ui-screenshot.ps1 -Screen inner [-Scale 0.65] [-NoPhoneLayer]
#   -Screen inner = 1152x1044 at 1.3, cover = 2520x1080 at 2.0 (the X screen sizes since the unfolded pixel cap);
#   -Chat: a few chat lines from a player with a long name first. Writes build\ui-screenshot\<screen>-<layer>.png
param(
  [ValidateSet("inner", "cover")] [string]$Screen = "inner",
  [double]$Scale = 0.65,
  [switch]$NoPhoneLayer,
  [double]$UiScale = 0,   # another interface scale than the phone's for that screen
  [string]$WidgetData = "",   # widget settings for BYAR.lua's data table, e.g. 'AdvPlayersList = { customScale = 0.8 },'
  [string]$Name = "",     # added to the screenshot's file name
  [switch]$Chat,          # chat lines before the screenshot
  [switch]$BarDroidChat,  # with the app's chat display (bardroid_chat.lua)
  [switch]$Ships,         # ships moving on the water, the camera on their wakes
  [switch]$BarDroidInfo,  # the app's info panel (bardroid_info.lua) instead of BAR's Info widget
  [switch]$NoInfo,        # BAR's Info widget off, nothing in its place (what it covers)
  [switch]$Select,        # several kinds of units given and selected (cheats)
  [switch]$NoWakes,       # the app's transparent wake texture (Installer.writeNoWakes)
  [string]$PlayerName = "Phone",
  [switch]$GamepadGame,   # the controller game (v0.8.5) as unpacked by tools\profile-gamepad-game.ps1
  [string]$Engine = "",
  [string]$Map = "supreme_isthmus_v2.1.sd7",
  [string]$MapName = "Supreme Isthmus v2.1"
)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $App "build\ui-screenshot"
$Data = Join-Path $Work "data"
. (Join-Path $PSScriptRoot "toolchain.ps1")
Assert-BarData
$Bar = $BarData
if (-not $Engine) { $Engine = (Get-ChildItem (Join-Path $Bar "engine") -Directory | Sort-Object Name | Select-Object -Last 1).Name }
$EngineDir = Get-EngineDir $Engine
$size = @{ inner = @(1152, 1044, 1.3); cover = @(2520, 1080, 2.0) }[$Screen]
$w = [int]($size[0] * $Scale); $h = [int]($size[1] * $Scale)
$uiScale = if ($UiScale -gt 0) { $UiScale } else { $size[2] }
$layer = $(if ($NoPhoneLayer) { "bar" } else { "phone" }) + "-" + $uiScale + $(if ($Name) { "-$Name" } else { "" })

Remove-Item -Recurse -Force "$Data\LuaUI", "$Data\screenshots" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Data\LuaUI\Widgets", "$Data\LuaUI\Config", "$Data\maps" | Out-Null
$links = foreach ($d in "packages", "pool", "rapid") {
  $link = Join-Path $Data $d
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$(Join-Path $Bar $d)" | Out-Null }
  $link
}
try {
  if (-not (Test-Path "$Data\maps\$Map")) { Copy-Item (Join-Path $Bar "maps\$Map") "$Data\maps\$Map" }
  Copy-Item (Join-Path $PSScriptRoot "ui-screenshot\bardroid_shot.lua") "$Data\LuaUI\Widgets\" -Force
  Remove-Item -Recurse -Force "$Data\bitmaps" -ErrorAction SilentlyContinue
  if ($NoWakes) {   # as Installer.writeNoWakes: an 8x8 transparent 32-bit TGA
    New-Item -ItemType Directory -Force -Path "$Data\bitmaps\projectiletextures" | Out-Null
    $tga = New-Object byte[] (18 + 256); $tga[2] = 2; $tga[12] = 8; $tga[14] = 8; $tga[16] = 32; $tga[17] = 0x28
    [IO.File]::WriteAllBytes("$Data\bitmaps\projectiletextures\wakegrey.tga", $tga)
  }
  if ($BarDroidInfo) { Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_info.lua") "$Data\LuaUI\Widgets\" -Force }
  if ($BarDroidChat) { Copy-Item (Join-Path $App "app\src\main\assets\bardroid\bardroid_chat.lua") "$Data\LuaUI\Widgets\" -Force }
  # the phone layer as launch-bar.sh sets it with the controller game on (Kailil's setting): BAR's Build menu instead
  # of the Grid menu, in BAR's released game too (one BYAR.lua)
  $orders = if ($NoPhoneLayer) { "" } else {
    (($("Bloom Shader Deferred", "SSAO", "Distortion GL4", "Snow", "Map Edge Extension", "Show Builder Queue",
        "Deferred rendering GL4", "Decals GL4", "Ground AO Plates GL4", "Ground AO Plates Features GL4", "Map Grass GL4", "Commands FX", "Contrast Adaptive Sharpen", "Jammed Units Highlight", "Reclaim Field Highlight", "Ecostats", "Keybind/Mouse Info",
        "Changelog Info", "Picture-in-Picture Minimap", "Grid menu") + $(if ($BarDroidInfo -or $NoInfo) { @("Info") } else { @() }) |
      ForEach-Object { "`t`t[`"$_`"] = 0," }) + "`t`t[`"Minimap`"] = 1," + "`t`t[`"Build menu`"] = 165,") -join "`n"
  }
  "-- Widget Custom data and order, order = 0 disabled widget`nreturn {`n`tdata = {`n`t`t$WidgetData`n`t},`n`torder = {`n$orders`n`t},`n}" |
    Set-Content "$Data\LuaUI\Config\BYAR.lua" -Encoding ascii
  "Fullscreen = 0`nWindowBorderless = 1`nXResolutionWindowed = $w`nYResolutionWindowed = $h`nWindowPosX = 0`nWindowPosY = 0`nui_scale = $uiScale`nsnd_volmaster = 0`nLogFlushLevel = 0`nRapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev`nbardroid_shot_chat = $(if ($Chat) { 1 } else { 0 })`nbardroid_shot_ships = $(if ($Ships) { 1 } else { 0 })`nbardroid_shot_select = $(if ($Select) { 1 } else { 0 })`nWater = 0`nAdvMapShading = 0" |
    Set-Content "$Data\springsettings.cfg" -Encoding ascii

  $gameLink = Join-Path $Data "games\BAR-gamepad.sdd"
  if (Test-Path $gameLink) { cmd /c rmdir "$gameLink" }   # a junction left by a killed run: the link only
  if ($GamepadGame) {
    $sdd = Join-Path $App "build\profile\data\games\BAR-gamepad.sdd"
    if (-not (Test-Path "$sdd\modinfo.lua")) { throw "no ${sdd}: run tools\profile-gamepad-game.ps1 once" }
    New-Item -ItemType Directory -Force -Path "$Data\games" | Out-Null
    cmd /c mklink /J "$gameLink" "$sdd" | Out-Null
    $links = @($links) + $gameLink
    $game = "Beyond All Reason `$VERSION"
    $layer = "gamepad-$layer"
  } else {
    $gz = Join-Path $Bar "rapid\repos-cdn.beyondallreason.dev\byar\versions.gz"
    $reader = New-Object IO.StreamReader (New-Object IO.Compression.GZipStream ([IO.File]::OpenRead($gz)), ([IO.Compression.CompressionMode]::Decompress))
    $game = $null
    while (($l = $reader.ReadLine()) -ne $null) { if ($l.StartsWith("byar:test,")) { $game = $l.Split(",", 4)[3] } }
    $reader.Close()
  }
  $script = (Get-Content (Join-Path $App "app\src\main\assets\bardroid\skirmish.template.txt") -Raw).Replace("@GAME@", $game).Replace("@MAP@", $MapName).Replace("=Phone;", "=$PlayerName;")
  $startscript = Join-Path $Work "skirmish.txt"
  $script | Set-Content $startscript -Encoding ascii

  $log = Join-Path $Data "infolog.txt"
  Remove-Item $log -ErrorAction SilentlyContinue
  Write-Host "[ui-shot] $Screen ($($size[0])x$($size[1]) at $uiScale) as ${w}x$h, $layer layer, $game"
  $p = Start-Process -FilePath (Join-Path $EngineDir "spring.exe") -WorkingDirectory $EngineDir -PassThru `
    -ArgumentList "--isolation", "--write-dir", "`"$Data`"", "`"$startscript`""
  if (-not $p.WaitForExit(240000)) { $p.Kill() }
  $shot = Get-ChildItem "$Data\screenshots" -Filter *.png -ErrorAction SilentlyContinue | Select-Object -Last 1
  if (-not $shot) { Select-String -Path $log -Pattern "uishot|screenshot|Error" | ForEach-Object { $_.Line }; throw "no screenshot" }
  $out = Join-Path $Work "$Screen-$layer.png"
  Copy-Item $shot.FullName $out -Force
  Write-Host "[ui-shot] $out"
} finally {
  foreach ($l in $links) { if (Test-Path $l) { cmd /c rmdir "$l" } }   # the junction only, never the live install's files
}
