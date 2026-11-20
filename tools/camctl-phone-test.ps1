# The one-finger camera (bardroid_camctl.lua's knob and edge rails, RtsTouch's CAM state; 2026-11-19's system) upright
# on the dev phone, in a skirmish, by real drags: the test widget (tools\camctl-phone-test\bardroid_camctl_test.lua)
# asks for drags on the knob (up, down, right, left), the zoom rail (up; slow, then fast), the turn rail (right: the
# other way from the knob's), a tap on the knob, a drag where the knob was under Settings, and left-handed a drag up the
# left zoom rail; it measures the camera's distance and turn after each. "do <n> swipe|tap|shot x y vsx [x2 y2 ms]",
# answered "<n>"; pictures in build\camctl-<n>.png. "Play upright" on for the run, "Turn with the phone" off, both put
# back after (the left-handed setting by the widget). Nothing on the laptop: it runs any time. About 2 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\camctl-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_camctl_test.lua"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\camctltest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_camctl_test.lua")
if ($stray) { "[camctltest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
$prefs = "$(InApp "cat shared_prefs/bardroid.xml")"
$portraitWas = $prefs -match 'name=.portrait. value=.true.'
$turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
AppScript ((Pref "portrait" $true) + (Pref "turnWithPhone" $false) +
  "rm -f files/bar/infolog.txt $cfg/bardroid_camctltest.txt $cfg/bardroid_camctltest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "camctl-phone-test\bardroid_camctl_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(6); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_camctltest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|shot|swipe) (-?\d+) (-?\d+) (\d+)(?: (-?\d+) (-?\d+) (\d+))?' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      if ($act -eq "shot") {
        & $adb shell screencap -p /sdcard/bardroid-camctlshot.png
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
        try { $null = & $adb pull /sdcard/bardroid-camctlshot.png (Join-Path $build "camctl-$n.png") 2>&1 }
        finally { $ErrorActionPreference = $eap }
        & $adb shell rm -f /sdcard/bardroid-camctlshot.png
        "[camctltest] ($($n): a picture, build\camctl-$n.png)"
      } elseif ($act -eq "swipe") {
        $x2 = [int]([double]$Matches[6] * $k); $y2 = [int]([double]$Matches[7] * $k); $ms = $Matches[8]
        & $adb shell input swipe $x $y $x2 $y2 $ms
        "[camctltest] ($($n): a drag $x,$y to $x2,$y2 in $ms ms)"
      } else {
        & $adb shell input tap $x $y
        "[camctltest] ($($n): a tap at $x,$y)"
      }
      InApp "echo $n > $cfg/bardroid_camctltest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 300
  }
  if (-not (Log '\[camctltest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[camctltest\] done' 1)) { "[camctltest] FAIL the test did not finish" }
  Log '\[camctltest\]|bardroid_camctl.*[Ee]rror|bardroid_touch.*[Ee]rror|Error in' 50 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_camctltest.txt $cfg/bardroid_camctltest_cmd.txt`n")
}
