# The unit info panel in the touch dock (bardroid_info.lua in the place bardroid_portrait.lua's SP.infoRect gives it;
# Kailil, 2026-11-23) by real taps on the dev phone, in a skirmish: the commander picked (the panel where it belongs:
# the split dock's middle over the wind's and the tide's pill, else held to the dock's top; its name, health and DPS), a
# tap on its text (folded to its INFO tab), a tap on the tab (open again), three Pawns and two Construction Bots given
# and all picked (their totals: count, DPS, cost, buildpower, the health summed), the Pawns alone (their stats, their
# health summed). The test widget (tools\info-phone-test\bardroid_info_test.lua) checks each case and says where to tap.
# Pictures of each case in build\info-<shape>-<case>.png. "Play upright" is on for the run and put back after.
#   powershell -ExecutionPolicy Bypass -File tools\info-phone-test.ps1 [-Unfolded]
# -Unfolded: the display at 1080x1198 for the run (wm size; the Fold7 unfolded's shape: the split dock), reset after.
# Take the dev phone's lock around it (devphone-lock.ps1 take/free). About 2 minutes.
param([switch]$Unfolded)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_info_test.lua"
$cfg = "files/bar/LuaUI/Config"
$shape = if ($Unfolded) { "unfolded" } else { "upright" }
$shots = Join-Path (Split-Path $PSScriptRoot) "build"
New-Item -ItemType Directory -Force $shots | Out-Null

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\infotest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Stage([string]$name) { InApp "echo '$name' > $cfg/bardroid_infotest_cmd.txt" }
function WaitLog([string]$pattern, [int]$seconds) {
  $until = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $until) { $l = Log $pattern 1; if ($l) { return $l }; Start-Sleep 1 }
  return $null
}
function Rects([string]$file) {
  $t = @{}
  foreach ($line in (InApp "cat $cfg/$file 2>/dev/null")) {
    $f = "$line".Trim() -split ' '
    if ($f.Count -lt 2 -or ($f -contains "nil")) { continue }
    $nums = @()
    foreach ($v in $f[1..($f.Count - 1)]) { $d = 0.0; if ([double]::TryParse($v, [ref]$d)) { $nums += $d } }
    if ($nums.Count -ge 1) { $t[$f[0]] = $nums }
  }
  return $t
}
$script:k = 1.0
function Tap([double]$x, [double]$y) { Assert-GameInFront $adb; & $adb shell input tap ([int]($x * $script:k)) ([int]($y * $script:k)) }
function Mid($r) { return @((($r[0] + $r[2]) / 2), (($r[1] + $r[3]) / 2)) }
function Shot([string]$name) {
  & $adb shell screencap -p /sdcard/bardroid-infoshot.png
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
  try { $null = & $adb pull /sdcard/bardroid-infoshot.png (Join-Path $shots "info-$shape-$name.png") 2>&1 }
  finally { $ErrorActionPreference = $eap }
  & $adb shell rm -f /sdcard/bardroid-infoshot.png
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_info_test.lua")
if ($stray) { "[infotest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
$portraitWas = (InApp "grep -o 'name=.portrait. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
$turnWas = (InApp "grep -o 'name=.turnWithPhone. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
$sizeWas = "$(& $adb shell wm size)"
AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"true`"/' shared_prefs/bardroid.xml`n" +
  "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_infotest.txt $cfg/bardroid_infotest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "info-phone-test\bardroid_info_test.lua") $widget
try {
  if ($Unfolded) { & $adb shell wm size 1080x1198 }
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  if (-not (WaitLog '\[infotest\] ready' 240)) { throw "the game did not get to frame 320 in 4 minutes" }
  Start-Sleep 1
  $size = (& $adb shell wm size) -join " "
  $m = [regex]::Match($size, '(\d+)x(\d+)\s*$')
  $dock = Rects "bardroid_dock.txt"
  $script:k = [double]$m.Groups[1].Value / $dock["dock"][2]   # (the display's width over the X screen's)
  "[infotest] $shape, display $($m.Groups[1].Value)x$($m.Groups[2].Value), X screen width $($dock["dock"][2])"
  $p = Rects "bardroid_infotest.txt"
  if ($p["folded"] -and $p["folded"][0] -eq 1 -and $p["tab"]) {   # (folded by the player before: open it first)
    $t = Mid $p["tab"]; Tap $t[0] $t[1]; Start-Sleep -Milliseconds 1200
  }
  Stage "commander?"; Start-Sleep 1
  Shot "commander"
  $p = Rects "bardroid_infotest.txt"
  if ($p["text"]) {
    Tap $p["text"][0] $p["text"][1]; Start-Sleep -Milliseconds 1200
    Stage "folded?"; Start-Sleep 1
    Shot "folded"
    $p = Rects "bardroid_infotest.txt"
    if ($p["tab"]) { $t = Mid $p["tab"]; Tap $t[0] $t[1]; Start-Sleep -Milliseconds 1200 }
    Stage "opened?"; Start-Sleep 1
  } else { "[infotest] FAIL no panel to tap (nothing shown with the commander picked)" }
  Stage "arm"; Start-Sleep 1
  Stage "armed?"; Start-Sleep 1
  Stage "disarmed?"; Start-Sleep 1
  Stage "give"; Start-Sleep 6
  Stage "mixed"; Start-Sleep 2
  Stage "mixed?"; Start-Sleep 1
  Shot "mixed"
  Stage "onetype"; Start-Sleep 2
  Stage "onetype?"; Start-Sleep 1
  Shot "onetype"
  Stage "end"
  if (-not (WaitLog '\[infotest\] done' 10)) { "[infotest] FAIL the widget did not finish" }
  Log '\[infotest\] (PASS|FAIL|done)|Error in|Removed widget|bardroid_info' 200 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  "[infotest] pictures: $shots\info-$shape-*.png"
} finally {
  & $adb shell am force-stop $pkg
  if ($Unfolded) { & $adb shell wm size reset }
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"$(if ($portraitWas) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n" +
    $(if ($turnWas) { "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"true`"/' shared_prefs/bardroid.xml`n" } else { "" }) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_infotest.txt $cfg/bardroid_infotest_cmd.txt`n")
  "[infotest] (display before the run: $sizeWas)"
}
