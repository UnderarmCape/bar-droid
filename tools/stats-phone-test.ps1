# The app's Statistics upright (bardroid_teamstats.lua: BAR's TeamStats copied; 2026-11-19's system) on the dev phone, in a
# skirmish, by real taps: the test widget (tools\stats-phone-test\bardroid_stats_test.lua) finds BAR's Statistics button
# on the top bar and asks for its tap; the panel open, the screen's width, between the top bar and the dock; the camera
# knob and rails off while it is open; a real drag over the panel where the knob stands leaves the camera still; its
# graphs open; the red close button tapped: closed, the knob back; Statistics tapped twice: open, closed. The widget asks
# "do <n> tap|shot|swipe x y vsx [x2 y2]", answered "<n>"; pictures in build\stats-<n>.png. "Play upright" on for the
# run, "Turn with the phone" off, both put back after. Nothing on the laptop: it runs any time. About 2 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\stats-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_stats_test.lua"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\statstest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_stats_test.lua")
if ($stray) { "[statstest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
# (the player's settings, put back after: "Play upright" on and "Turn with the phone" off for the run, as
# dock-phone-test.ps1: the dev phone lying sideways would run it sideways)
$prefs = "$(InApp "cat shared_prefs/bardroid.xml")"
$portraitWas = $prefs -match 'name=.portrait. value=.true.'
$turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
AppScript ((Pref "portrait" $true) + (Pref "turnWithPhone" $false) +
  "rm -f files/bar/infolog.txt $cfg/bardroid_statstest.txt $cfg/bardroid_statstest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "stats-phone-test\bardroid_stats_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(6); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_statstest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|shot|swipe) (-?\d+) (-?\d+) (\d+)(?: (-?\d+) (-?\d+))?' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]
      if ($act -ne "shot") { Assert-GameInFront $adb }   # (no taps on the launcher: toolchain.ps1)
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      if ($act -eq "shot") {
        & $adb shell screencap -p /sdcard/bardroid-statsshot.png
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
        try { $null = & $adb pull /sdcard/bardroid-statsshot.png (Join-Path $build "stats-$n.png") 2>&1 }
        finally { $ErrorActionPreference = $eap }
        & $adb shell rm -f /sdcard/bardroid-statsshot.png
        "[statstest] ($($n): a picture, build\stats-$n.png)"
      } elseif ($act -eq "swipe") {
        $x2 = [int]([double]$Matches[6] * $k); $y2 = [int]([double]$Matches[7] * $k)
        & $adb shell input swipe $x $y $x2 $y2 600
        "[statstest] ($($n): a drag $x,$y to $x2,$y2)"
      } else {
        & $adb shell input tap $x $y
        "[statstest] ($($n): a tap at $x,$y)"
      }
      InApp "echo $n > $cfg/bardroid_statstest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 400
  }
  if (-not (Log '\[statstest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[statstest\] done' 1)) { "[statstest] FAIL the test did not finish" }
  Log '\[statstest\]|teamstats.*[Ee]rror|bardroid_camctl.*[Ee]rror|Error in' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_statstest.txt $cfg/bardroid_statstest_cmd.txt`n")
}
