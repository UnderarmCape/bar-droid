# A unit type left out of ALL UNITS for a while (bardroid_portrait.lua SP.leftOut; Kailil, 2026-11-20) on the dev phone,
# upright, in a skirmish: the test widget (tools\types-phone-test\bardroid_types_test.lua) gives three Pawns, two Blitzes
# and two Maces and asks for each finger's action in turn ("do <n> tap|hold|shot x y vsx"); this script does it as a
# finger would (adb input: a tap, a press held 0.9 s, a screenshot to build\types-out.png) and answers "<n>". The widget
# checks ALL UNITS' pick, a held type left out (dimmed, out of ALL's count), still out at the next ALL UNITS, back in when
# held again, the list's last type kept in, and a plain tap on a left-out type picking it alone. "Play upright" on for the
# run, off after. Nothing on the laptop: it runs any time. About 3 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\types-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_types_test.lua"
$cfg = "files/bar/LuaUI/Config"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\typestest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function MenuOpen { return "$(InApp "head -n 1 $cfg/bardroid_dock.txt 2>/dev/null")" -match ' menu' }

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_types_test.lua")
if ($stray) { "[typestest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
# ("Turn with the phone" off for the run, as dock-phone-test.ps1: the dev phone lying sideways would run it sideways)
$turnWas = (InApp "grep -o 'name=.turnWithPhone. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"true`"/' shared_prefs/bardroid.xml`n" +
  "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_typestest.txt $cfg/bardroid_typestest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "types-phone-test\bardroid_types_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(7); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_typestest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|hold|shot) (-?\d+) (-?\d+) (\d+)' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]
      if ($act -ne "shot") { Assert-GameInFront $adb }   # (no taps on the launcher: toolchain.ps1)
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      if ($act -eq "shot") {
        & $adb shell screencap -p /sdcard/bardroid-typesshot.png
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
        try { $null = & $adb pull /sdcard/bardroid-typesshot.png (Join-Path (Split-Path $PSScriptRoot) "build\types-out.png") 2>&1 }
        finally { $ErrorActionPreference = $eap }
        & $adb shell rm -f /sdcard/bardroid-typesshot.png
      } else {
        # (no tap first to open the dock's menu: the home grid and the types list take their first touch, menu or
        # camera pad, the dock file's "live" rects; an opening tap here picked the Maces alone, 2026-11-20)
        $was = if (MenuOpen) { "menu" } else { "pad" }
        if ($act -eq "tap") { & $adb shell input tap $x $y } else { & $adb shell input swipe $x $y $x $y 900 }
      }
      "[typestest] ($($n): $act at $x,$y, the dock's $was)"
      InApp "echo $n > $cfg/bardroid_typestest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 400
  }
  if (-not (Log '\[typestest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[typestest\] done' 1)) { "[typestest] FAIL the test did not finish" }
  Log '\[typestest\]|left out of|back in ALL|stays in ALL|all back in|bardroid_portrait.*[Ee]rror|Error in' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
    $(if ($turnWas) { "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"true`"/' shared_prefs/bardroid.xml`n" } else { "" }) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_typestest.txt $cfg/bardroid_typestest_cmd.txt`n")
}
