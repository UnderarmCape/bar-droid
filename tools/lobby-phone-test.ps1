# bardroid_lobby_touch.lua in the real lobby on the dev phone: the widget of tools\lobby-touch-test.ps1, offline
# (tools\lobby-login\bardroid_login_wait.lua: the tests never log in), then a virtual pad's Start
# (tools\lobby-touch-test\pad-start.evemu), the way through ControllerBridge the laptop cannot take. Puts nothing on
# the laptop, so it runs any time. Then the pad's D-pad (pad-dpad.evemu): the pointer from control to control.
# About a minute, 3 on the first start after an install.
#   powershell -ExecutionPolicy Bypass -File tools\lobby-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widgets = "files/bar/LuaMenu/Widgets"
$evemu = "/data/local/tmp/bardroid-lobby-pad.evemu"
$dpad = "/data/local/tmp/bardroid-lobby-dpad.evemu"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function Push([string]$file) { Send-AppFile $adb $file "$widgets/$(Split-Path $file -Leaf)" }

& $adb shell am force-stop $pkg
InApp "rm -f files/bar/infolog.txt"
Push (Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua")
Push (Join-Path $PSScriptRoot "lobby-touch-test\bardroid_lobby_touch_test.lua")
InApp "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg"   # (the log is late on a phone)
# (the warnings about a host's widget options are for the app's widgets as user widgets, BAR's official engine; the
# phone engine loads them as the game's and launch-bar.sh turns the warnings off: the test widget checks them, so the
# app's widgets go in as user widgets here)
InApp "[ -f files/bar/dev-env.sh ] && cp files/bar/dev-env.sh files/bar/.dev-env-before-lobbytest; echo 'BARDROID_GAME_WIDGETS=0' >> files/bar/dev-env.sh"
& $adb push (Join-Path $PSScriptRoot "lobby-touch-test\pad-start.evemu") $evemu | Out-Null
& $adb push (Join-Path $PSScriptRoot "lobby-touch-test\pad-dpad.evemu") $dpad | Out-Null
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.StartActivity" | Out-Null   # (the app icon: the lobby)
  $until = (Get-Date).AddMinutes(4)
  while ((Get-Date) -lt $until -and -not (Log '\[lobbytouch\] done' 1)) { Start-Sleep 3 }
  if (Log '\[lobbytouch\] done' 1) {
    Start-Sleep 1
    & $adb shell "uinput $evemu"   # (the pad plays its script and goes)
    Start-Sleep 1
    # (Start: under 115 % to 130 %, else to 100 %; sideways the lobby starts at 100 %, upright at 135 %: 100 130 100 or
    # 135 100 130)
    $seen = @(Log '\[lobbytouch\] scale' 9 | ForEach-Object { [int](($_ -split " ")[-1]).TrimEnd('%') })
    $scales = ($seen | ForEach-Object { "$_%" }) -join " "
    $want = @(); if ($seen.Count -gt 0) { $want = @($seen[0]); foreach ($i in 1, 2) { $want += $(if ($want[-1] -lt 115) { 130 } else { 100 }) } }
    if ($seen.Count -eq 3 -and (($seen -join " ") -eq ($want -join " "))) { "[lobbytouch] PASS a pad's Start: $scales" }
    else { "[lobbytouch] FAIL a pad's Start: the scale went $scales (wanted $(($want | ForEach-Object { "$_%" }) -join ' '))" }
    # (the D-pad: down three times, right, left; the pointer from control to control, Kailil 2026-11-06; the tests'
    # lobby is offline, its login dialog in front: down onto its checkboxes and its buttons, right and left between
    # them, nothing behind it: upright the bottom grid is hidden under it, bardroid_lobby_touch.lua uprightModal)
    & $adb shell "uinput $dpad"
    Start-Sleep 1
    $on = @(Log '\[bardroid-lobby\] the pad on' 9 | ForEach-Object { $_ -replace '^.*the pad on ', '' })
    $places = @($on | ForEach-Object { ($_ -split ' at ')[-1] } | Select-Object -Unique)
    # (the offline lobby: its login dialog in front, Register and Cancel: two places)
    if ($on.Count -ge 3 -and $places.Count -ge 2) { "[lobbytouch] PASS the pad's D-pad: the pointer on $($on.Count) controls ($($on -join '; '))" }
    else {
      "[lobbytouch] FAIL the pad's D-pad: $($on.Count) moves ($($on -join '; '))"
      # (what the widget got: each press as it read it, a press with nothing that way, the pointer moved off)
      Log '\[bardroid-lobby\] the pad' 16 | ForEach-Object { $_ -replace '^\[t=([^\]]+)\]\[f=[^\]]+\] ', '  $1 ' }
    }
  } else { "[lobbytouch] FAIL the test did not finish in 4 minutes" }
  Log '\[lobbytouch\] (PASS|FAIL|done)|\[lobbylogin\]|bardroid_lobby.*[Ee]rror' 60 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  InApp "rm -f $widgets/bardroid_login_wait.lua $widgets/bardroid_lobby_touch_test.lua files/bar/dev-springsettings.cfg"   # (its LogFlushLevel: launch-bar.sh puts the old one back)
  InApp "rm -f files/bar/dev-env.sh; [ -f files/bar/.dev-env-before-lobbytest ] && mv files/bar/.dev-env-before-lobbytest files/bar/dev-env.sh; true"
  & $adb shell am force-stop $pkg
  & $adb shell rm -f $evemu $dpad
}
