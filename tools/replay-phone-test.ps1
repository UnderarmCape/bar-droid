# BAR's replay speed column (its Replay buttons with the app's phone patch; 2026-11-19's system) upright on the dev
# phone, by real taps: the offline lobby (tools\lobby-login\bardroid_login_wait.lua: the tests never log in) starts the
# newest replay (tools\replay-phone-test\bardroid_replay_menu_test.lua); in it the test widget (bardroid_replay_test.lua)
# asks for taps on 1x, 4x, 10x and 0.5x (the replay's speed each), a drag from the column across the map (the camera
# pans, the speed kept) and checks the camera's rails left-handed (clear of the column; the setting put back).
# "do <n> tap|swipe|shot x y vsx [x2 y2 ms]", answered "<n>"; pictures build\replay-<n>.png. "Play upright" on for the
# run, "Turn with the phone" off, both put back after. Nothing on the laptop. About 2 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\replay-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$menuWidgets = "files/bar/LuaMenu/Widgets"
$uiWidget = "files/bar/LuaUI/Widgets/bardroid_replay_test.lua"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"
$files = "$cfg/bardroid_replaytest.txt $cfg/bardroid_replaytest_cmd.txt $cfg/bardroid_replaytest_state.txt"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\replaytest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}

& $adb shell am force-stop $pkg
$prefs = "$(InApp "cat shared_prefs/bardroid.xml")"
$portraitWas = $prefs -match 'name=.portrait. value=.true.'
$turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
AppScript ((Pref "portrait" $true) + (Pref "turnWithPhone" $false) +
  "rm -f files/bar/infolog.txt $files`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua") "$menuWidgets/bardroid_login_wait.lua"
Send-AppFile $adb (Join-Path $PSScriptRoot "replay-phone-test\bardroid_replay_menu_test.lua") "$menuWidgets/bardroid_replay_menu_test.lua"
Send-AppFile $adb (Join-Path $PSScriptRoot "replay-phone-test\bardroid_replay_test.lua") $uiWidget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.StartActivity" | Out-Null   # (the app icon: the lobby)
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(7); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_replaytest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|shot|swipe) (-?\d+) (-?\d+) (\d+)(?: (-?\d+) (-?\d+) (\d+))?' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]
      if ($act -ne "shot") { Assert-GameInFront $adb }   # (no taps on the launcher: toolchain.ps1)
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      if ($act -eq "shot") {
        & $adb shell screencap -p /sdcard/bardroid-replayshot.png
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
        try { $null = & $adb pull /sdcard/bardroid-replayshot.png (Join-Path $build "replay-$n.png") 2>&1 }
        finally { $ErrorActionPreference = $eap }
        & $adb shell rm -f /sdcard/bardroid-replayshot.png
        "[replaytest] ($($n): a picture, build\replay-$n.png)"
      } elseif ($act -eq "swipe") {
        $x2 = [int]([double]$Matches[6] * $k); $y2 = [int]([double]$Matches[7] * $k); $ms = $Matches[8]
        & $adb shell input swipe $x $y $x2 $y2 $ms
        "[replaytest] ($($n): a drag $x,$y to $x2,$y2 in $ms ms)"
      } else {
        & $adb shell input tap $x $y
        "[replaytest] ($($n): a tap at $x,$y)"
      }
      InApp "echo $n > $cfg/bardroid_replaytest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 300
  }
  if (-not (Log '\[replaytest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[replaytest\] done' 1)) { "[replaytest] FAIL the test did not finish" }
  Log '\[replaytest\]|replaybuttons.*[Ee]rror|bardroid_camctl.*[Ee]rror|Error in' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "rm -f $menuWidgets/bardroid_login_wait.lua $menuWidgets/bardroid_replay_menu_test.lua $uiWidget files/bar/dev-springsettings.cfg $files`n")
}
