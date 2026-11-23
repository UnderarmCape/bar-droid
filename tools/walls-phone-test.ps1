# Walls around a placed sentry (bardroid_walls.lua; Kailil, 2026-11-20) on the dev phone, upright, in a skirmish: the
# test widget (tools\walls-phone-test\bardroid_walls_test.lua) picks the commander and asks for real taps ("do <n>
# tap|shot x y vsx", answered "<n>"): the Sentry's tile on the dock, a spot on the map with room for a ring, PLACE; then
# checks the commander's queue (the Sentry, then 8 Dragon's Teeth around it), a screenshot (build\walls-ring.png), and
# by orders: WALLS off, a Dragon's Claw, an AA launcher, two Sentries at once (no walls for any). "Play upright" on for
# the run, put back after. Nothing on the laptop: it runs any time. About 2 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\walls-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_walls_test.lua"
$cfg = "files/bar/LuaUI/Config"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\wallstest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function MenuOpen { return "$(InApp "head -n 1 $cfg/bardroid_dock.txt 2>/dev/null")" -match ' menu' }

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_walls_test.lua")
if ($stray) { "[wallstest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
# ("Turn with the phone" off for the run, as dock-phone-test.ps1: the dev phone lying sideways would run it sideways)
$portraitWas = (InApp "grep -o 'name=.portrait. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'   # (put back after, as the player had it: forced off after, it left factory-preset-test sideways, 2026-11-22)
$turnWas = (InApp "grep -o 'name=.turnWithPhone. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"true`"/' shared_prefs/bardroid.xml`n" +
  "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_wallstest.txt $cfg/bardroid_wallstest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "walls-phone-test\bardroid_walls_test.lua") $widget
# (WALLS as the player had it, put back after: the test turns it off and on, a run that breaks off between left it off)
$wallsWas = "$(InApp "cat $cfg/bardroid_walls.txt 2>/dev/null")".Trim()
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(7); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_wallstest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|hold|shot) (-?\d+) (-?\d+) (\d+)' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]
      if ($act -ne "shot") { Assert-GameInFront $adb }   # (no taps on the launcher: toolchain.ps1)
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      if ($act -eq "shot") {
        & $adb shell screencap -p /sdcard/bardroid-wallsshot.png
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
        try { $null = & $adb pull /sdcard/bardroid-wallsshot.png (Join-Path (Split-Path $PSScriptRoot) "build\walls-ring.png") 2>&1 }
        finally { $ErrorActionPreference = $eap }
        & $adb shell rm -f /sdcard/bardroid-wallsshot.png
      } else {
        # (no tap first to open the dock's menu: the home grid takes its first touch, menu or camera pad, the dock
        # file's "live" rects; types-phone-test.ps1's opening tap was itself a press, 2026-11-20)
        $was = if (MenuOpen) { "menu" } else { "pad" }
        if ($act -eq "tap") { & $adb shell input tap $x $y } else { & $adb shell input swipe $x $y $x $y 900 }
      }
      "[wallstest] ($($n): $act at $x,$y, the dock's $was)"
      InApp "echo $n > $cfg/bardroid_wallstest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 400
  }
  if (-not (Log '\[wallstest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[wallstest\] done' 1)) { "[wallstest] FAIL the test did not finish" }
  Log '\[wallstest\]|\[bardroid-walls\]|bardroid_walls.*[Ee]rror|bardroid_portrait.*[Ee]rror|Error in' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  $put = if ($wallsWas -match '^on [01]$') { $wallsWas } else { "on 1" }
  InApp "echo '$put' > $cfg/bardroid_walls.txt"
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"$(if ($portraitWas) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n" +
    $(if ($turnWas) { "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"true`"/' shared_prefs/bardroid.xml`n" } else { "" }) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_wallstest.txt $cfg/bardroid_wallstest_cmd.txt`n")
}
