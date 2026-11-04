# The touch camera (bardroid_touch.lua) at the map's edge on the dev phone, in a skirmish: a test widget
# (tools\touch-phone-test\bardroid_touch_phone_test.lua) appends the app's pan and zoom lines to the touch log and checks
# that a drag holds the point under the finger (on the map, over the void past the edge, across the edge), that a pinch
# over the void or on the map zooms about its point, that a drag over the sky moves the map, and a twist, a tilt and
# the zoom-out limit, and that the pointer on the build and order menus (v0.8.5's in the controller game) counts as
# interface. No fingers needed, nothing on the laptop: it runs any time. About 2 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\touch-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_touch_phone_test.lua"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }

& $adb shell am force-stop $pkg
InApp "rm -f files/bar/infolog.txt"
Send-AppFile $adb (Join-Path $PSScriptRoot "touch-phone-test\bardroid_touch_phone_test.lua") $widget
InApp "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg"   # (the log is late on a phone)
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(4)
  while ((Get-Date) -lt $until -and -not (Log '\[touchphone\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[touchphone\] done' 1)) { "[touchphone] FAIL the test did not finish in 4 minutes" }
  Log '\[touchphone\]|bardroid_touch.*[Ee]rror|\[bardroid-touch\] error' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  InApp "rm -f $widget files/bar/dev-springsettings.cfg"
  & $adb shell am force-stop $pkg
}
