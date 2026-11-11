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
#   powershell -ExecutionPolicy Bypass -File tools\pad-test.ps1 [-Online | -Dgun | -Share | -Chat] [-Engine <build>]
param([switch]$Online, [switch]$Dgun, [switch]$Share, [switch]$Chat, [string]$Engine = "")
if ($Dgun) { $Online = $true }   # (-Dgun: the same game, the D-gun mode's and the share list's script)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_pad_test.lua"
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
$testWidget = if ($Chat) { "bardroid_chat_voice_test.lua" } elseif ($Share) { "bardroid_pad_share_test.lua" } elseif ($Dgun) { "bardroid_pad_dgun_test.lua" } elseif ($Online) { "bardroid_pad_online_test.lua" } else { "bardroid_pad_test.lua" }
$padScript = if ($Dgun) { "pad-dgun.evemu" } elseif ($Online) { "pad-online.evemu" } else { "pad.evemu" }
function InApp([string]$script) { Invoke-AppScript $adb (Join-Path $PSScriptRoot "pad-test\$script") }
Send-AppFile $adb (Join-Path $PSScriptRoot "pad-test\$testWidget") $widget
& $adb push (Join-Path $PSScriptRoot "pad-test\$padScript") $evemu | Out-Null
try {
  if ($Online) { InApp "online-on.sh" }
  if ($Engine) {   # (after online-on.sh, which writes dev-env.sh anew)
    $f = Join-Path $TC "tmp\padtest-engine.sh"
    [IO.File]::WriteAllText($f, ("printf '%s\n' 'ENGINE=`"`$BAR/engine-sim/$Engine`"' 'export BARDROID_GAME_WIDGETS=1' 'log `"pad-test: engine-sim/$Engine, the app widgets as the game''s`"' >> files/bar/dev-env.sh`n"), (New-Object Text.ASCIIEncoding))
    Invoke-AppScript $adb $f
  }
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(5)
  while ((Get-Date) -lt $until -and -not (Log '\[padtest\] ready' 1)) { Start-Sleep 3 }
  if (-not (Log '\[padtest\] ready' 1)) { throw "the game did not get to frame 300 in 5 minutes" }
  # (the pad, which plays its script and goes; BAR's game in skirmish too since v0.8.5's game went, 2026-11-06)
  if ($Share) {   # (no pad: the test widget drives the list itself, then copies of its four screenshots)
    $until = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $until -and -not (Log '\[padtest\] done' 1)) { Start-Sleep 2 }
    $shots = @(& $adb exec-out run-as $pkg sh -c "ls -t files/bar/screenshots/*.png 2>/dev/null | head -4")
    $build = Join-Path (Split-Path $PSScriptRoot) "build"
    New-Item -ItemType Directory -Force $build | Out-Null
    for ($i = 0; $i -lt $shots.Count; $i++) {
      $to = Join-Path $build "pad-share-$($shots.Count - $i).png"
      & cmd /c "`"$adb`" exec-out run-as $pkg sh -c `"cat $($shots[$i].Trim())`" > `"$to`""
      "[padtest] screenshot: $to"
    }
  } elseif ($Chat) {   # (no pad: the widget runs its cases itself, then screenshots: the listening note, the autoquit note)
    $until = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $until -and -not (Log '\[padtest\] shot' 1)) { Start-Sleep 2 }
    Start-Sleep 3   # (the engine writes it a moment later: the last run's was taken for it)
    $shots = @(& $adb exec-out run-as $pkg sh -c "ls -t files/bar/screenshots/*.png 2>/dev/null | head -2")
    $names = @("chat-autoquit.png", "chat-voice.png")   # (newest first)
    for ($i = 0; $i -lt $shots.Count; $i++) {
      $to = Join-Path (Split-Path $PSScriptRoot) "build\$($names[$i])"
      & cmd /c "`"$adb`" exec-out run-as $pkg sh -c `"cat $($shots[$i].Trim())`" > `"$to`""
      "[padtest] screenshot: $to"
    }
  } else { & $adb shell "uinput $evemu" }
  # (-Online: its widget gives up 2400 frames after "ready" and then says which case missed: a slow phone needs the time)
  $until = (Get-Date).AddSeconds($(if ($Online) { 75 } else { 30 }))
  while ((Get-Date) -lt $until -and -not (Log '\[padtest\] done' 1) -and -not (DriverFault)) { Start-Sleep 2 }
  # (no case logged and the game still up: the virtual pad was not seen; its script once more)
  if (-not ($Share -or $Chat) -and -not (Log '\[padtest\] done' 1) -and -not (Log '\[padtest\] (PASS|FAIL)' 1) -and -not (DriverFault)) {
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
  # (this run's screenshots, copied to build\ above where they are wanted)
  & $adb exec-out run-as $pkg sh -c "find files/bar/screenshots -name 'screen_*.png' -newer files/padtest-start -delete 2>/dev/null; rm -f files/padtest-start"
  & $adb shell rm -f $evemu
  if ($Engine -and -not $Online) { & $adb exec-out run-as $pkg rm -f files/bar/dev-env.sh }
  if ($Online) {   # (again while its marker stays: the setting must read as before)
    for ($i = 0; $i -lt 3; $i++) {
      InApp "online-off.sh"
      if (-not (& $adb exec-out run-as $pkg sh -c "ls files/padtest-gamepad-was-on 2>/dev/null")) { break }
      Start-Sleep 2
    }
    if (& $adb exec-out run-as $pkg sh -c "ls files/padtest-gamepad-was-on 2>/dev/null") {
      "[padtest] FAIL the controller game setting was not switched back on (files/padtest-gamepad-was-on)"
    }
  }
}
