# bardroid_lobby_touch.lua in the real lobby on the dev phone: the widget of tools\lobby-touch-test.ps1, offline
# (tools\lobby-login\bardroid_login_wait.lua: the tests never log in), then a virtual pad's Start
# (tools\lobby-touch-test\pad-start.evemu), the way through ControllerBridge the laptop cannot take. Puts nothing on
# the laptop, so it runs any time. About a minute, 3 on the first start after an install.
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

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function Push([string]$file) {
  $name = Split-Path $file -Leaf
  cmd /c "`"$adb`" exec-in run-as $pkg sh -c `"cat > $widgets/$name`" < `"$file`""
}

& $adb shell am force-stop $pkg
InApp "rm -f files/bar/infolog.txt"
Push (Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua")
Push (Join-Path $PSScriptRoot "lobby-touch-test\bardroid_lobby_touch_test.lua")
InApp "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg"   # (the log is late on a phone)
& $adb push (Join-Path $PSScriptRoot "lobby-touch-test\pad-start.evemu") $evemu | Out-Null
try {
  & $adb shell am start -n "$pkg/.StartActivity" | Out-Null   # (the app icon: the lobby)
  $until = (Get-Date).AddMinutes(4)
  while ((Get-Date) -lt $until -and -not (Log '\[lobbytouch\] done' 1)) { Start-Sleep 3 }
  if (Log '\[lobbytouch\] done' 1) {
    Start-Sleep 1
    & $adb shell "uinput $evemu"   # (the pad plays its script and goes)
    Start-Sleep 1
    $scales = @(Log '\[lobbytouch\] scale' 9 | ForEach-Object { ($_ -split " ")[-1] }) -join " "
    if ($scales -eq "100% 130% 100%") { "[lobbytouch] PASS a pad's Start: 100%, 130% and back" }
    else { "[lobbytouch] FAIL a pad's Start: the scale went $scales" }
  } else { "[lobbytouch] FAIL the test did not finish in 4 minutes" }
  Log '\[lobbytouch\] (PASS|FAIL|done)|\[lobbylogin\]|bardroid_lobby.*[Ee]rror' 60 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  InApp "rm -f $widgets/bardroid_login_wait.lua $widgets/bardroid_lobby_touch_test.lua files/bar/dev-springsettings.cfg; sed -i '/^LogFlushLevel = 0/d' files/bar/springsettings.cfg"
  & $adb shell am force-stop $pkg
  & $adb shell rm -f $evemu
}
