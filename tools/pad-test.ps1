# The app's gamepad controls on the dev phone with no gamepad: Android's uinput tool makes a virtual Xbox pad
# (tools\pad-test\pad.evemu), a real input device with both sticks, triggers and a D-pad, so its events take the path a
# pad's do (ControllerBridge, PadGame, the widgets) and it goes away at the end as a pad switched off does.
# tools\pad-test\bardroid_pad_test.lua reports in the game's log. About 2 min, 4 on the first start after an install.
# pad.evemu's numbers are the kernel's: EV_KEY 1, EV_ABS 3; BTN_A 304, BTN_B 305, BTN_X 307, BTN_Y 308, BTN_TL 310, BTN_TR 311,
# BTN_SELECT 314, BTN_START 315, BTN_THUMBL 317, BTN_THUMBR 318; ABS_X 0, ABS_Y 1, ABS_Z (LT) 2, ABS_RX 3, ABS_RY 4,
# ABS_RZ (RT) 5, ABS_HAT0X 16, ABS_HAT0Y 17. Xbox 360 ids, so Android's own key layout names them.
#   powershell -ExecutionPolicy Bypass -File tools\pad-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_pad_test.lua"
$evemu = "/data/local/tmp/bardroid-pad.evemu"

function Log([string]$pattern, [int]$lines) {
  & $adb exec-out run-as $pkg sh -c "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines"
}

& $adb shell am force-stop $pkg
& $adb exec-out run-as $pkg rm -f files/bar/infolog.txt
cmd /c "`"$adb`" exec-in run-as $pkg sh -c `"cat > $widget`" < `"$(Join-Path $PSScriptRoot 'pad-test\bardroid_pad_test.lua')`""
& $adb push (Join-Path $PSScriptRoot "pad-test\pad.evemu") $evemu | Out-Null
try {
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(5)
  while ((Get-Date) -lt $until -and -not (Log '\[padtest\] ready' 1)) { Start-Sleep 3 }
  if (-not (Log '\[padtest\] ready' 1)) { throw "the game did not get to frame 300 in 5 minutes" }
  # (a triple tap: the app's controls in the controller game; then the pad, which plays its script and goes)
  & $adb shell "input tap 1500 400; input tap 1500 400; input tap 1500 400; sleep 3; uinput $evemu"
  $until = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $until -and -not (Log '\[padtest\] done' 1)) { Start-Sleep 2 }
  Log '\[padtest\] (PASS|FAIL|done|a new)|Error in|Removed widget' 24 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  if (-not (Log '\[padtest\] done' 1)) { "[padtest] FAIL it did not finish: the pad never went away, or was never seen" }
} finally {
  & $adb exec-out run-as $pkg rm -f $widget
  & $adb shell am force-stop $pkg
  & $adb shell rm -f $evemu
}
