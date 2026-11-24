# The app's gamepad controls on the dev phone with no gamepad: Android's uinput tool makes a virtual Xbox pad
# (tools\pad-test\pad.evemu), a real input device with both sticks, triggers and a D-pad, so its events take the path a
# pad's do (ControllerBridge, PadGame, the widgets) and it goes away at the end as a pad switched off does.
# tools\pad-test\bardroid_pad_test.lua reports in the game's log. About 2 min, 4 on the first start after an install.
# pad.evemu's numbers are the kernel's: EV_KEY 1, EV_ABS 3; BTN_A 304, BTN_B 305, BTN_X 307, BTN_Y 308, BTN_TL 310, BTN_TR 311,
# BTN_SELECT 314, BTN_START 315, BTN_THUMBL 317, BTN_THUMBR 318; ABS_X 0, ABS_Y 1, ABS_Z (LT) 2, ABS_RX 3, ABS_RY 4,
# ABS_RZ (RT) 5, ABS_HAT0X 16, ABS_HAT0Y 17. Xbox 360 ids, so Android's own key layout names them.
# -Online: BAR's released game with user widgets' orders forbidden, as a host can forbid them, and pad-online.evemu: the
# controls that must work in any online game (tools\pad-test\online-on.sh; the skirmish keeps its AI opponent).
# -Dgun: the same game, pad-dgun.evemu: v0.8.5's D-gun mode (LB + RB + R3) through the app's clicks, the share list's chord.
# -Engine <build>: an engine-branch build on the phone (engine-sim/<build>, phone-engine.ps1 -Install) with the app's widgets
# as the game's (BARDROID_GAME_WIDGETS=1, launch-bar.sh; docs/ENGINE-SIM.md on engine/sim).
# -Share: the share list's metal and energy (bardroid_pad_share_test.lua: the AI's team stands in for teammates, no pad,
# BAR's share recorded, not sent); its screenshots of the list go to build\pad-share-*.png.
# -Chat: what speak to chat sends (bardroid_chat_voice_test.lua: BAR's chat sends recorded, not sent; no pad).
# -Shots <tag>: the pad's panels one at a time (bardroid_pad_shots.lua: the group list, the filters, the share list, a
# note, the D-gun mode, the order menu on the pad; no pad), each screenshot cut to its piece and framed:
# build\pad-ui\<tag>-<upright|sideways>-<piece>.png; with both a "before" and an "after" of a piece, compare-*.png side by
# side. -Sideways / -Upright: the game that way for the run ("Play upright" off / on, "Turn with the phone" off, both
# put back; neither: as the player has them).
#   powershell -ExecutionPolicy Bypass -File tools\pad-test.ps1 [-Online | -Dgun | -Share | -Chat | -Shots <tag> [-Sideways | -Upright]] [-Engine <build>]
param([switch]$Online, [switch]$Dgun, [switch]$Share, [switch]$Chat, [string]$Shots = "", [switch]$Sideways, [switch]$Upright,
  [string]$Engine = "")
if ($Dgun) { $Online = $true }   # (-Dgun: the same game, the D-gun mode's and the share list's script)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
# (-Share, -Chat: the recorder among the game's widgets: on the phone engine, the app's default since 2026-11-13, the
# app's widgets load as the game's and call BAR's real Spring functions, which a user widget's stand-ins never see;
# -Dgun: its cases are the official engine's route, the app's widgets as user widgets under the host's rule)
$gameDir = ($Share -or $Chat)
$widget = if ($gameDir) { "files/bar/bardroid-ui/LuaUI/Widgets/bardroid_pad_test.lua" } else { "files/bar/LuaUI/Widgets/bardroid_pad_test.lua" }
if ($gameDir) { & $adb exec-out run-as $pkg mkdir -p files/bar/bardroid-ui/LuaUI/Widgets }
$evemu = "/data/local/tmp/bardroid-pad.evemu"

$results = "files/bar/LuaUI/Config/bardroid_padtest.txt"   # (-Online: the test's own file, the game's log is late on a phone)
function Log([string]$pattern, [int]$lines) {
  $from = if ($Online) { $results } else { "files/bar/infolog.txt" }
  & $adb exec-out run-as $pkg sh -c "grep -a -E '$pattern' $from 2>/dev/null | tail -$lines"
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb
if ($stray) { "[padtest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
& $adb exec-out run-as $pkg rm -f files/bar/infolog.txt $results
# (the run's start, so the engine screenshots its widgets take are deleted after it, below: 150 of them, 255 MB, had
# piled up on the dev phone by 2026-11-10)
& $adb exec-out run-as $pkg touch files/padtest-start
# the GPU driver's rare fault (docs/DELIVERY.md): counted now, a new one during the run is named in the result
function FaultCount { [int]("0" + ((& $adb exec-out run-as $pkg sh -c "grep -a -c 'GPU driver refused' files/logs/launcher.log 2>/dev/null") | Select-Object -First 1)) }
$faults0 = FaultCount
function DriverFault { (FaultCount) -gt $faults0 }
$testWidget = if ($Shots) { "bardroid_pad_shots.lua" } elseif ($Chat) { "bardroid_chat_voice_test.lua" } elseif ($Share) { "bardroid_pad_share_test.lua" } elseif ($Dgun) { "bardroid_pad_dgun_test.lua" } elseif ($Online) { "bardroid_pad_online_test.lua" } else { "bardroid_pad_test.lua" }
$padScript = if ($Dgun) { "pad-dgun.evemu" } elseif ($Online) { "pad-online.evemu" } else { "pad.evemu" }
function InApp([string]$script) { Invoke-AppScript $adb (Join-Path $PSScriptRoot "pad-test\$script") }
# (-Share, -Chat: placed only once launch-bar.sh has moved the app's widgets in, below: its start empties bardroid-ui of
# everything that is not the app's, release overhaul item 4)
if (-not $gameDir) { Send-AppFile $adb (Join-Path $PSScriptRoot "pad-test\$testWidget") $widget }
function GameWidgetsCount { [int]("0" + ((& $adb exec-out run-as $pkg sh -c "grep -a -c the.app.s.widgets.as.the.game.s files/logs/launcher.log 2>/dev/null") | Select-Object -First 1)) }
$gw0 = GameWidgetsCount
& $adb push (Join-Path $PSScriptRoot "pad-test\$padScript") $evemu | Out-Null
# (-Sideways: the player's two settings as they were, put back at the end)
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}
function AppText([string]$text) {
  $f = Join-Path $TC "tmp\padtest-prefs.sh"
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
$turned = $Sideways -or $Upright
if ($turned) {
  $prefs = "$(& $adb exec-out run-as $pkg cat shared_prefs/bardroid.xml)"
  $portraitWas = $prefs -match 'name=.portrait. value=.true.'
  $turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
  "[padtest] $(if ($Upright) { 'upright' } else { 'sideways' }) for the run (the player's: Play upright $portraitWas, Turn with the phone $turnWas)"
  AppText ((Pref "portrait" ([bool]$Upright)) + (Pref "turnWithPhone" $false))
}
# (-Shots: a screenshot cut to its piece, a margin of the game round it, framed; GL pixels, y up, as the widget logs them)
function Save-Shot([string]$png, [int[]]$r, [string]$to) {
  Add-Type -AssemblyName System.Drawing
  $img = [Drawing.Bitmap]::FromFile($png)
  try {
    $m, $b = 28, 3
    $x0 = [Math]::Max(0, $r[0] - $m); $x1 = [Math]::Min($img.Width, $r[2] + $m)
    $y0 = [Math]::Max(0, $img.Height - $r[3] - $m); $y1 = [Math]::Min($img.Height, $img.Height - $r[1] + $m)
    if ($x1 -le $x0 -or $y1 -le $y0) { $x0, $y0, $x1, $y1 = 0, 0, $img.Width, $img.Height }
    $out = New-Object Drawing.Bitmap (($x1 - $x0) + 2 * $b), (($y1 - $y0) + 2 * $b)
    $g = [Drawing.Graphics]::FromImage($out)
    $g.Clear([Drawing.Color]::FromArgb(255, 42, 42, 44))
    $g.DrawImage($img, (New-Object Drawing.Rectangle $b, $b, ($x1 - $x0), ($y1 - $y0)), (New-Object Drawing.Rectangle $x0, $y0, ($x1 - $x0), ($y1 - $y0)), [Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $out.Save($to, [Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
  } finally { $img.Dispose() }
}
# (both a before and an after of a piece: the two side by side, each named over it)
function Save-Compare([string]$before, [string]$after, [string]$to) {
  Add-Type -AssemblyName System.Drawing
  $a = [Drawing.Bitmap]::FromFile($before); $c = [Drawing.Bitmap]::FromFile($after)
  try {
    $label, $gap = 44, 24
    $out = New-Object Drawing.Bitmap ($a.Width + $gap + $c.Width), ($label + [Math]::Max($a.Height, $c.Height))
    $g = [Drawing.Graphics]::FromImage($out)
    $g.Clear([Drawing.Color]::FromArgb(255, 24, 24, 26))
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAlias
    $font = New-Object Drawing.Font "Segoe UI", 18, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $g.DrawString("BEFORE", $font, [Drawing.Brushes]::Gainsboro, 6, 10)
    $g.DrawString("AFTER", $font, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 255, 200, 64))), ($a.Width + $gap + 6), 10)
    $g.DrawImage($a, 0, $label, $a.Width, $a.Height)
    $g.DrawImage($c, ($a.Width + $gap), $label, $c.Width, $c.Height)
    $g.Dispose()
    $out.Save($to, [Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
  } finally { $a.Dispose(); $c.Dispose() }
}
try {
  if ($Online) { InApp "online-on.sh" }
  if ($Dgun) {   # (after online-on.sh, which writes dev-env.sh anew: the app's widgets as user widgets, see $gameDir)
    $f = Join-Path $TC "tmp\padtest-userwidgets.sh"
    [IO.File]::WriteAllText($f, "printf '%s\n' 'BARDROID_GAME_WIDGETS=0' >> files/bar/dev-env.sh`n", (New-Object Text.ASCIIEncoding))
    Invoke-AppScript $adb $f
  }
  if ($Engine) {   # (after online-on.sh, which writes dev-env.sh anew)
    $f = Join-Path $TC "tmp\padtest-engine.sh"
    [IO.File]::WriteAllText($f, ("printf '%s\n' 'ENGINE=`"`$BAR/engine-sim/$Engine`"' 'export BARDROID_GAME_WIDGETS=1' 'log `"pad-test: engine-sim/$Engine, the app widgets as the game''s`"' >> files/bar/dev-env.sh`n"), (New-Object Text.ASCIIEncoding))
    Invoke-AppScript $adb $f
  }
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  if ($gameDir) {
    $until = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $until -and (GameWidgetsCount) -le $gw0) { Start-Sleep 1 }
    if ((GameWidgetsCount) -le $gw0) { throw "launch-bar.sh never put the app's widgets in as the game's (the phone engine's BarDroidGameWidgetsDir): the test widget has no place" }
    Send-AppFile $adb (Join-Path $PSScriptRoot "pad-test\$testWidget") $widget
  }
  $until = (Get-Date).AddMinutes(5)
  while ((Get-Date) -lt $until -and -not (Log '\[padtest\] ready' 1)) { Start-Sleep 3 }
  if (-not (Log '\[padtest\] ready' 1)) { throw "the game did not get to frame 300 in 5 minutes" }
  # (the pad, which plays its script and goes; BAR's game in skirmish too since v0.8.5's game went, 2026-11-06)
  if ($Shots) {   # (no pad: the widget opens each piece itself; then the screenshots, oldest first, one for each shot line)
    $until = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $until -and -not (Log '\[padtest\] done' 1)) { Start-Sleep 2 }
    Start-Sleep 3   # (the engine writes the last one a moment later)
    $lines = @(Log '\[padtest\] shot ' 40)
    # (by name: the engine names them by the time and a count)
    $files = @(& $adb exec-out run-as $pkg sh -c "ls files/bar/screenshots/*.png 2>/dev/null" | Where-Object { $_.Trim() } | Sort-Object)
    $files = @($files | Select-Object -Last $lines.Count)
    $orient = if ($Sideways) { "sideways" } elseif ($Upright) { "upright" } else { "asis" }
    $dir = Join-Path (Split-Path $PSScriptRoot) "build\pad-ui"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $raw = Join-Path $TC "tmp\padtest-shot.png"
    if ($files.Count -ne $lines.Count) { "[padtest] FAIL $($lines.Count) shots logged, $($files.Count) screenshots found" }
    for ($i = 0; $i -lt [Math]::Min($files.Count, $lines.Count); $i++) {
      if ($lines[$i] -notmatch '\[padtest\] shot (\S+) (-?\d+) (-?\d+) (-?\d+) (-?\d+)') { continue }
      $name, $r = $Matches[1], @([int]$Matches[2], [int]$Matches[3], [int]$Matches[4], [int]$Matches[5])
      & cmd /c "`"$adb`" exec-out run-as $pkg sh -c `"cat $($files[$i].Trim())`" > `"$raw`""
      $to = Join-Path $dir "$Shots-$orient-$name.png"
      Save-Shot $raw $r $to
      "[padtest] screenshot: $to"
      $before, $after = (Join-Path $dir "before-$orient-$name.png"), (Join-Path $dir "after-$orient-$name.png")
      if ((Test-Path $before) -and (Test-Path $after)) { Save-Compare $before $after (Join-Path $dir "compare-$orient-$name.png") }
    }
    Remove-Item -Force $raw -ErrorAction SilentlyContinue
  } elseif ($Share) {   # (no pad: the test widget drives the list itself, then copies of its four screenshots)
    # (90 s and a moment after "done": at 30 s the widget was still at its cases and only the first two screenshots
    # were there, the note's and the 15 teammates' never copied, dev phone 2026-11-17)
    $until = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $until -and -not (Log '\[padtest\] done' 1)) { Start-Sleep 2 }
    Start-Sleep 3   # (the engine writes the last one a moment later)
    $pngs = @(& $adb exec-out run-as $pkg sh -c "ls -t files/bar/screenshots/*.png 2>/dev/null | head -4")
    $build = Join-Path (Split-Path $PSScriptRoot) "build"
    New-Item -ItemType Directory -Force $build | Out-Null
    for ($i = 0; $i -lt $pngs.Count; $i++) {
      $to = Join-Path $build "pad-share-$($pngs.Count - $i).png"
      & cmd /c "`"$adb`" exec-out run-as $pkg sh -c `"cat $($pngs[$i].Trim())`" > `"$to`""
      "[padtest] screenshot: $to"
    }
  } elseif ($Chat) {   # (no pad: the widget runs its cases itself, then screenshots: the listening note, the autoquit note)
    $until = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $until -and -not (Log '\[padtest\] shot' 1)) { Start-Sleep 2 }
    Start-Sleep 3   # (the engine writes it a moment later: the last run's was taken for it)
    $pngs = @(& $adb exec-out run-as $pkg sh -c "ls -t files/bar/screenshots/*.png 2>/dev/null | head -2")
    $names = @("chat-autoquit.png", "chat-voice.png")   # (newest first)
    for ($i = 0; $i -lt $pngs.Count; $i++) {
      $to = Join-Path (Split-Path $PSScriptRoot) "build\$($names[$i])"
      & cmd /c "`"$adb`" exec-out run-as $pkg sh -c `"cat $($pngs[$i].Trim())`" > `"$to`""
      "[padtest] screenshot: $to"
    }
  } else { & $adb shell "uinput $evemu" }
  # (-Online: its widget gives up 2400 frames after "ready" and then says which case missed: a slow phone needs the time)
  $until = (Get-Date).AddSeconds($(if ($Online) { 75 } else { 30 }))
  while ((Get-Date) -lt $until -and -not (Log '\[padtest\] done' 1) -and -not (DriverFault)) { Start-Sleep 2 }
  # (no case logged and the game still up: the virtual pad was not seen; its script once more)
  if (-not ($Share -or $Chat -or $Shots) -and -not (Log '\[padtest\] done' 1) -and -not (Log '\[padtest\] (PASS|FAIL)' 1) -and -not (DriverFault)) {
    "[padtest] the pad was not seen: its script once more"
    & $adb shell "uinput $evemu"
    $until = (Get-Date).AddSeconds($(if ($Online) { 75 } else { 30 }))
    while ((Get-Date) -lt $until -and -not (Log '\[padtest\] done' 1)) { Start-Sleep 2 }
  }
  $lines = if ($Online) { 60 } else { 24 }   # (-Online: its trace too)
  $which = if ($Online) { '\[padtest\]' } else { '\[padtest\] (PASS|FAIL|done|a new)|Error in|Removed widget' }
  Log $which $lines | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  # (2026-11-09: a run that "did not finish" was the GPU driver's rare fault, the game frozen and closed by DriverWatch,
  # not the pad: said so, as the controls were never tested)
  if (-not (Log '\[padtest\] done' 1)) {
    if (DriverFault) { "[padtest] FAIL the game ended on the GPU driver's rare fault (MESA submit failed, DriverWatch closed it): not the controls; run it again" }
    else { "[padtest] FAIL it did not finish: the pad never went away, or was never seen" }
  }
} finally {
  & $adb exec-out run-as $pkg rm -f $widget
  & $adb shell am force-stop $pkg
  # (this run's screenshots, copied to build\ above where they are wanted; Android's find lists what it deletes)
  & $adb exec-out run-as $pkg sh -c "find files/bar/screenshots -name 'screen_*.png' -newer files/padtest-start -delete >/dev/null 2>&1; rm -f files/padtest-start"
  & $adb shell rm -f $evemu
  if ($Engine -and -not $Online) { & $adb exec-out run-as $pkg rm -f files/bar/dev-env.sh }
  if ($Online) { InApp "online-off.sh" }
  if ($turned) { AppText ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) + "true`n") }
}
