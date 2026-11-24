# The long press's forgiving aim (bardroid_touch.lua SNAP, RtsTouch SNAP_HOLD; Kailil, 2026-11-24: "if im not pixel
# perfect with my single finger hold on the unit, it just issues a move command close to the unit i want guarded") by
# real presses on the dev phone, in a skirmish: a Construction Bot picked, a finger held about 3 mm beside a Pawn (it
# guards the Pawn), on the Pawn (BAR's own Guard), on open ground (a Move), beside a free metal spot (an extractor queued
# on it), and held beside the Pawn, then dragged on (the path: a Move, no Guard). The test widget
# (tools\snap-phone-test\bardroid_snap_test.lua) gives the units, sets the camera, says where to press and checks each
# order. Pictures in build\snap-<case>.png. "Play upright" is on for the run and put back after.
#   powershell -ExecutionPolicy Bypass -File tools\snap-phone-test.ps1
# Take the dev phone's lock around it (devphone-lock.ps1 take/free). About 2 minutes.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_snap_test.lua"
$cfg = "files/bar/LuaUI/Config"
$shots = Join-Path (Split-Path $PSScriptRoot) "build"
New-Item -ItemType Directory -Force $shots | Out-Null

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\snaptest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Stage([string]$name) { InApp "echo '$name' > $cfg/bardroid_snaptest_cmd.txt" }
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
function Px([double]$v) { return [int]($v * $script:k) }
# a finger held still for 0.9 s (past the long press's 450 ms), then lifted
function Hold([double]$x, [double]$y) { Assert-GameInFront $adb; & $adb shell "input motionevent DOWN $(Px $x) $(Px $y); sleep 0.9; input motionevent UP $(Px $x) $(Px $y)" }
# held, then dragged on to (x2, y2) in steps, lifted there
function HoldDrag([double]$x, [double]$y, [double]$x2, [double]$y2) {
  Assert-GameInFront $adb
  $moves = (1..6 | ForEach-Object { "input motionevent MOVE $(Px ($x + ($x2 - $x) * $_ / 6)) $(Px ($y + ($y2 - $y) * $_ / 6))" }) -join "; "
  & $adb shell "input motionevent DOWN $(Px $x) $(Px $y); sleep 0.9; $moves; input motionevent UP $(Px $x2) $(Px $y2)"
}
function Shot([string]$name) {
  & $adb shell screencap -p /sdcard/bardroid-snapshot.png
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
  try { $null = & $adb pull /sdcard/bardroid-snapshot.png (Join-Path $shots "snap-$name.png") 2>&1 }
  finally { $ErrorActionPreference = $eap }
  & $adb shell rm -f /sdcard/bardroid-snapshot.png
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_snap_test.lua")
if ($stray) { "[snaptest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
$portraitWas = (InApp "grep -o 'name=.portrait. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
$turnWas = (InApp "grep -o 'name=.turnWithPhone. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"true`"/' shared_prefs/bardroid.xml`n" +
  "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_snaptest.txt $cfg/bardroid_snaptest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "snap-phone-test\bardroid_snap_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  if (-not (WaitLog '\[snaptest\] ready' 240)) { throw "the game did not get to frame 320 in 4 minutes" }
  Start-Sleep 1
  $size = (& $adb shell wm size) -join " "
  $m = [regex]::Match($size, '(\d+)x(\d+)\s*$')
  $dock = Rects "bardroid_dock.txt"
  $xw = if ($dock["dock"] -and $dock["dock"][2] -gt 0) { $dock["dock"][2] } else { 1 }
  $script:k = [double]$m.Groups[1].Value / $xw   # (the display's width over the X screen's)
  Stage "give"; Start-Sleep 4
  # (twice: the game's own camera move at the start can come after the first; one run aimed at 1.81 elmos a pixel)
  Stage "camera"; Start-Sleep 2
  Stage "camera2"; Start-Sleep 2
  Stage "camera"; Start-Sleep 2
  Stage "camera2"; Start-Sleep 2
  Stage "aim"; Start-Sleep 1
  $p = Rects "bardroid_snaptest.txt"
  Shot "scene"
  $cases = @(@("guard", "guard?"), @("on", "on?"), @("far", "far?"))
  foreach ($c in $cases) {
    $pt = $p[$c[0]]
    if (-not $pt) { "[snaptest] NOT RUN $($c[0]): no point"; continue }
    Hold $pt[0] $pt[1]; Start-Sleep -Milliseconds 700
    Shot $c[0]
    Stage $c[1]; Start-Sleep 1
  }
  if ($p["guard"] -and $p["away"]) {
    HoldDrag $p["guard"][0] $p["guard"][1] $p["away"][0] $p["away"][1]; Start-Sleep -Milliseconds 700
    Stage "drag?"; Start-Sleep 1
  } else { "[snaptest] NOT RUN drag: no point" }
  # (the mex case on its own camera: the free metal spot nearest the commander, in the map's free middle)
  Stage "spotcam"; Start-Sleep 2
  Stage "camera2"; Start-Sleep 2
  Stage "spotcam"; Start-Sleep 1
  Stage "camera2"; Start-Sleep 2
  Stage "aimmex"; Start-Sleep 1
  $pm = (Rects "bardroid_snaptest.txt")["mex"]
  if ($pm) {
    Hold $pm[0] $pm[1]; Start-Sleep -Milliseconds 700
    Shot "mex"
    Stage "mex?"; Start-Sleep 1
  }
  Stage "end"
  if (-not (WaitLog '\[snaptest\] done' 10)) { "[snaptest] FAIL the widget did not finish" }
  Log '\[snaptest\] (PASS|FAIL|NOT RUN|aimed|done)|\[bardroid-snap\]|Error in|Removed widget' 200 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  "[snaptest] pictures: $shots\snap-*.png"
} finally {
  & $adb shell am force-stop $pkg
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"$(if ($portraitWas) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n" +
    $(if ($turnWas) { "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"true`"/' shared_prefs/bardroid.xml`n" } else { "" }) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_snaptest.txt $cfg/bardroid_snaptest_cmd.txt`n")
}
