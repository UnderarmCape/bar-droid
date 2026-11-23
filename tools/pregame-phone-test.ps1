# The touch dock's faction buttons before the start, on the dev phone, upright: the skirmish turned into one with a
# pre-game (a dev-env.sh for the run: StartPosType 2 in skirmish.txt, as a lobby's game has it), and the test widget
# (tools\pregame-phone-test\bardroid_pregame_test.lua) asks for each tap in turn ("do <n> tap x y vsx"); this script taps
# as a finger would (adb input) and answers "<n>". Checked: nothing queued, one tap switches the faction; a building
# queued, the first tap asks for a second and switches nothing, the second switches with the queue, its note gone with
# it. No phone test reached a pre-game before (the faction guard erring at every tap went unseen: 86012f7f). "Play
# upright" and "Turn with the phone" as the player had them after; a dev-env.sh already there put back. ~2 min.
#   powershell -ExecutionPolicy Bypass -File tools\pregame-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_pregame_test.lua"
$cfg = "files/bar/LuaUI/Config"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\pregametest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_pregame_test.lua")
if ($stray) { "[pregametest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
$portraitWas = (InApp "grep -o 'name=.portrait. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
$turnWas = (InApp "grep -o 'name=.turnWithPhone. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
$devEnvWas = "$(InApp "test -f files/bar/dev-env.sh && echo yes")".Trim() -eq "yes"
AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"true`"/' shared_prefs/bardroid.xml`n" +
  "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_pregametest.txt $cfg/bardroid_pregametest_cmd.txt`n" +
  $(if ($devEnvWas) { "cp files/bar/dev-env.sh files/bar/dev-env.sh.pregametest`n" } else { "" }) +
  "printf '%s\n' 'sed -i `"s/StartPosType=[0-9];/StartPosType=2;/`" `"`$BAR/skirmish.txt`"' >> files/bar/dev-env.sh`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "pregame-phone-test\bardroid_pregame_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(5); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_pregametest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) tap (-?\d+) (-?\d+) (\d+)' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]
      Assert-GameInFront $adb   # (no taps on the launcher: toolchain.ps1)
      $k = $w / [double]$Matches[4]
      $x = [int]([double]$Matches[2] * $k); $y = [int]([double]$Matches[3] * $k)
      & $adb shell input tap $x $y
      "[pregametest] ($($n): a tap at $x,$y)"
      InApp "echo $n > $cfg/bardroid_pregametest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 300
  }
  if (-not (Log '\[pregametest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[pregametest\] done' 1)) { "[pregametest] FAIL the test did not finish" }
  Log '\[pregametest\]|faction tap|bardroid_portrait.*[Ee]rror|Error in|DiffTimers' 30 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"$(if ($portraitWas) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n" +
    "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"$(if ($turnWas) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n" +
    $(if ($devEnvWas) { "mv -f files/bar/dev-env.sh.pregametest files/bar/dev-env.sh`n" } else { "rm -f files/bar/dev-env.sh`n" }) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_pregametest.txt $cfg/bardroid_pregametest_cmd.txt`n")
}
