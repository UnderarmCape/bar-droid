# BAR's Build Bar ("Factory dock", gui_buildbar.lua; off on phones as the app sets them up) upright on the dev phone, in a
# skirmish, by real taps: the phone version (phone-widget-gui_buildbar.lua.patch) takes a press by the icon under the
# press, not by the one the pointer was over at the last Update. The test widget (tools\buildbar-phone-test\
# bardroid_buildbar_test.lua) gives a Bot Lab and asks, three times, for a tap on the map, a tap on the lab's icon (the
# lab picked) and a tap on the map (the press reaches the map); the one-finger camera's zoom rail clear of the bar's
# icons. For the run: BAR's BuildBar on in LuaUI/Config/BYAR.lua (the file put back after), the camera knob and rails
# on, right-handed (dev-springsettings.cfg, gone after), "Play upright" on and "Turn with the phone" off (put back). Pictures in
# build\buildbar-<n>.png. Nothing on the laptop: it runs any time. About 2 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\buildbar-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_buildbar_test.lua"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\buildbartest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_buildbar_test.lua")
if ($stray) { "[buildbartest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
$prefs = "$(InApp "cat shared_prefs/bardroid.xml")"
$portraitWas = $prefs -match 'name=.portrait. value=.true.'
$turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
AppScript ((Pref "portrait" $true) + (Pref "turnWithPhone" $false) +
  "cp $cfg/BYAR.lua $cfg/BYAR.lua.buildbartest`n" +
  "sed -i 's/^\([[:space:]]*\)BuildBar = 0,/\1BuildBar = 999,/' $cfg/BYAR.lua`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_buildbartest.txt $cfg/bardroid_buildbartest_cmd.txt`n" +
  "printf 'LogFlushLevel = 0\nBarDroidCamKnob = 1\nBarDroidCamRails = 1\nBarDroidCamLeft = 0\n' > files/bar/dev-springsettings.cfg`n")
"[buildbartest] (BYAR.lua: $("$(InApp "grep -a -E 'BuildBar = ' $cfg/BYAR.lua")".Trim()))"
Send-AppFile $adb (Join-Path $PSScriptRoot "buildbar-phone-test\bardroid_buildbar_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(6); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_buildbartest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|shot) (-?\d+) (-?\d+) (\d+)' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]
      if ($act -ne "shot") { Assert-GameInFront $adb }   # (no taps on the launcher: toolchain.ps1)
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      if ($act -eq "shot") {
        & $adb shell screencap -p /sdcard/bardroid-buildbarshot.png
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
        try { $null = & $adb pull /sdcard/bardroid-buildbarshot.png (Join-Path $build "buildbar-$n.png") 2>&1 }
        finally { $ErrorActionPreference = $eap }
        & $adb shell rm -f /sdcard/bardroid-buildbarshot.png
        "[buildbartest] ($($n): a picture, build\buildbar-$n.png)"
      } else {
        & $adb shell input tap $x $y
        "[buildbartest] ($($n): a tap at $x,$y)"
      }
      InApp "echo $n > $cfg/bardroid_buildbartest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 400
  }
  if (-not (Log '\[buildbartest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[buildbartest\] done' 1)) { "[buildbartest] FAIL the test did not finish" }
  Log '\[buildbartest\]|[Bb]uild[Bb]ar.*[Ee]rror|Error in' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "if [ -f $cfg/BYAR.lua.buildbartest ]; then mv -f $cfg/BYAR.lua.buildbartest $cfg/BYAR.lua; fi`n" +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_buildbartest.txt $cfg/bardroid_buildbartest_cmd.txt`n")
}
