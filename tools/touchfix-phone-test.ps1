# The night's touch playtest's fixes (docs/PLAYTEST.md, 2026-11-22) on the dev phone, upright, by real taps (adb input)
# where the fix is about taps; the test widget (tools\touchfix-phone-test\bardroid_touchfix_test.lua) sets each case up
# and checks it, in a skirmish on a map with water (Ravaged Remake v1.2 for the run): the Solar picked with the pointer
# resting over water stays the Solar (no Tidal twin; and past the map's edge when that is in sight), a real tap on water
# picks the Tidal, one on land the Solar again, PLACE builds the Solar; WALLS' cost for a Sentry; INSERT on a builder
# (real taps on INSERT and QUEUE, winds placed: at its queue's front, alone and with QUEUE); the D-gun mode's AIM stick
# flicked quickly (80 ms swipes: right, up, a short one down, paused left): the shot that way; a map tap there: the shot
# towards it, the mode on. (Not here: before the start. A skirmish the app starts begins at once, its start script made
# again at every start, and with the start spot chosen in the game that spot's tap starts it: the pre-game QUEUE row is
# checked in a game from the lobby.)
# "Play upright", "Turn with the phone" and the map put back as they were. About 4 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\touchfix-phone-test.ps1 [-Shots]
param([switch]$Shots)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_touchfix_test.lua"
$cfg = "files/bar/LuaUI/Config"
$MAP = "Ravaged Remake v1.2"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\touchfixtest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
$script:stageN = 0   # (each stage numbered: the same stage twice in a row is two)
function Stage([string]$name) { $script:stageN++; InApp "echo '$name #$($script:stageN)' > $cfg/bardroid_fixtest_cmd.txt"; Start-Sleep -Milliseconds 700 }
function WaitLog([string]$pattern, [int]$seconds) {
  $until = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $until) { $l = Log $pattern 1; if ($l) { return $l }; Start-Sleep 1 }
  return $null
}
function Rects([string]$file) {   # "key a b c d" lines as number arrays
  $t = @{}
  foreach ($line in (InApp "cat $cfg/$file 2>/dev/null")) {
    $f = "$line".Trim() -split ' '
    if ($f.Count -lt 3 -or ($f -contains "nil")) { continue }
    $nums = @()
    foreach ($v in $f[1..($f.Count - 1)]) { $d = 0.0; if ([double]::TryParse($v, [ref]$d)) { $nums += $d } }
    if ($nums.Count -ge 2) { $t[$f[0]] = $nums }
  }
  return $t
}
$script:k = 1.0
function Tap([double]$x, [double]$y) { Assert-GameInFront $adb; & $adb shell input tap ([int]($x * $script:k)) ([int]($y * $script:k)) }
function Flick([double]$x, [double]$y, [double]$dx, [double]$dy) {
  Assert-GameInFront $adb
  & $adb shell input swipe ([int]($x * $script:k)) ([int]($y * $script:k)) ([int](($x + $dx) * $script:k)) ([int](($y + $dy) * $script:k)) 80
}
function Mid($r, [string]$what = "rect") { if (-not $r) { throw "no $what" }; return @((($r[0] + $r[2]) / 2), (($r[1] + $r[3]) / 2)) }
function Shot([string]$name) {
  if (-not $Shots) { return }
  & $adb shell screencap -p /sdcard/bardroid-fixshot.png
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $null = & $adb pull /sdcard/bardroid-fixshot.png (Join-Path (Split-Path $PSScriptRoot) "build\touchfix-$name.png") 2>&1 }
  finally { $ErrorActionPreference = $eap }
  & $adb shell rm -f /sdcard/bardroid-fixshot.png
}
function PlaceNow {   # PLACE from the build menu's file, once it shows (the spot's tap picked)
  $until = (Get-Date).AddSeconds(3); $p = $null
  while ((Get-Date) -lt $until -and -not $p) { $p = (Rects "bardroid_place.txt")["done"]; if (-not $p) { Start-Sleep -Milliseconds 200 } }
  if (-not $p) { "[fixtest] note: no PLACE in the build menu's file"; return }
  Start-Sleep -Milliseconds 400
  $m = Mid $p "PLACE"; Tap $m[0] $m[1]; Start-Sleep -Milliseconds 1200
}
function StartGame {
  AppScript ("rm -f files/bar/infolog.txt $cfg/bardroid_fixtest.txt $cfg/bardroid_fixtest_cmd.txt`n")
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
}
function Report { Log '\[fixtest\] (PASS|FAIL|done|note)|bardroid_touchfix_test.*[Ee]rror|Error in ' 60 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' } }

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_touchfix_test.lua")
if ($stray) { "[fixtest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
# (the player's settings, put back after)
$prefs = (InApp "cat shared_prefs/bardroid.xml") -join "`n"
$was = @{
  portrait = [regex]::Match($prefs, 'name="portrait" value="(\w+)"').Groups[1].Value
  turn = [regex]::Match($prefs, 'name="turnWithPhone" value="(\w+)"').Groups[1].Value
  map = [regex]::Match($prefs, '<string name="mapName">([^<]*)</string>').Groups[1].Value
  chosen = [regex]::Match($prefs, 'name="mapChosen" value="(\w+)"').Groups[1].Value
}
"[fixtest] (the player's: upright $($was.portrait), turn $($was.turn), map '$($was.map)', chosen $($was.chosen))"
function SetPref([string]$kind, [string]$name, [string]$value) {
  if ($kind -eq "string") {
    return "grep -q 'name=`"$name`"' shared_prefs/bardroid.xml && sed -i -E 's#<string name=`"$name`">[^<]*</string>#<string name=`"$name`">$value</string>#' shared_prefs/bardroid.xml || sed -i 's#</map>#    <string name=`"$name`">$value</string>\n</map>#' shared_prefs/bardroid.xml`n"
  }
  return "grep -q 'name=`"$name`"' shared_prefs/bardroid.xml && sed -i -E 's#name=`"$name`" value=`"(true|false)`"#name=`"$name`" value=`"$value`"#' shared_prefs/bardroid.xml || sed -i 's#</map>#    <boolean name=`"$name`" value=`"$value`" />\n</map>#' shared_prefs/bardroid.xml`n"
}
AppScript ((SetPref bool portrait true) + (SetPref bool turnWithPhone false) + (SetPref string mapName $MAP) +
  (SetPref bool mapChosen true) +
  # (a dev-springsettings.cfg already there, another session's: kept aside and put back after)
  "[ -f files/bar/dev-springsettings.cfg ] && cp -f files/bar/dev-springsettings.cfg $cfg/bardroid_fixtest_dss.bak`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "touchfix-phone-test\bardroid_touchfix_test.lua") $widget
try {
  StartGame
  if (-not (WaitLog '\[fixtest\] ready' 300)) { throw "the game did not get to frame 300 in 5 minutes" }
  $size = (& $adb shell wm size) -join " "
  $dock = Rects "bardroid_dock.txt"
  $script:k = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value / $dock["dock"][2]
  # 1. sea twins
  Stage "twinvoid"; Start-Sleep 1; Stage "twinvoid2"; Start-Sleep 1; Stage "twinvoid3"; Start-Sleep 1; Stage "twinvoid?"
  Shot "twinvoid"
  Stage "twinspots"; Start-Sleep 1; Stage "twinspots2"; Start-Sleep -Milliseconds 500
  $s = Rects "bardroid_fixtest.txt"
  if (-not ($s["water"] -and $s["land"])) {   # (the random start: no water in that view; the camera nearer it)
    Stage "twincloser"; Start-Sleep 1; Stage "twinspots2"; Start-Sleep -Milliseconds 500
    $s = Rects "bardroid_fixtest.txt"
  }
  if ($s["water"] -and $s["land"]) {
    Tap $s["water"][0] $s["water"][1]; Start-Sleep 1; Stage "tide?"; Shot "tide"
    Tap $s["land"][0] $s["land"][1]; Start-Sleep 1; Stage "solar?"
    PlaceNow; Stage "placed?"
  } else { "[fixtest] FAIL no water or land spot in sight: $(InApp "cat $cfg/bardroid_fixtest.txt")" }
  # 2. WALLS' cost
  Stage "walls?"; Shot "walls"; Start-Sleep 1
  # 3. INSERT on a builder
  Stage "insertsetup"; Start-Sleep 1; Stage "insertsetup2"; Start-Sleep -Milliseconds 500
  $s = Rects "bardroid_fixtest.txt"
  if ($s["irect"] -and $s["qrect"] -and $s["spot1"] -and $s["spot2"] -and $s["spot3"]) {
    $i = Mid $s["irect"]; $q = Mid $s["qrect"]
    Tap $i[0] $i[1]; Start-Sleep -Milliseconds 800   # INSERT on
    Stage "armwind"; Tap $s["spot1"][0] $s["spot1"][1]; Start-Sleep -Milliseconds 700; PlaceNow; Stage "insert1?"
    Tap $q[0] $q[1]; Start-Sleep -Milliseconds 800   # QUEUE on (INSERT still on)
    Stage "armwind"; Tap $s["spot2"][0] $s["spot2"][1]; Start-Sleep -Milliseconds 700; PlaceNow; Stage "insert2?"
    Tap $s["spot3"][0] $s["spot3"][1]; Start-Sleep -Milliseconds 700; PlaceNow; Stage "insert3?"
    Tap $q[0] $q[1]; Start-Sleep -Milliseconds 500; Tap $i[0] $i[1]; Start-Sleep -Milliseconds 500   # both off
  } else { "[fixtest] FAIL INSERT's case: no rects or spots: $(InApp "cat $cfg/bardroid_fixtest.txt")" }
  # 4. the D-gun mode's AIM by quick flicks, then a map tap
  Stage "dgun"
  if (-not (WaitLog '\[fixtest\] dgun on: true' 10)) { "[fixtest] FAIL the D-gun mode did not open" }
  Start-Sleep 1
  $r = (Rects "bardroid_dock.txt")["stickr"]
  if ($r) {
    $d = [double]$r[2] * 0.8
    Flick $r[0] $r[1] $d 0; Start-Sleep -Milliseconds 600; Stage "aim? 1 0"
    Flick $r[0] $r[1] 0 (-$d); Start-Sleep -Milliseconds 600; Stage "aim? 0 -1"
    # (a short drag, a third of the ring: under the old half-way dead zone it did nothing)
    Flick $r[0] $r[1] 0 ([double]$r[2] * 0.35); Start-Sleep -Milliseconds 600; Stage "aim? 0 1"
    Stage "pause"; Start-Sleep 1
    Flick $r[0] $r[1] (-$d) 0; Start-Sleep -Milliseconds 600; Stage "aim? -1 0"; Shot "dgun-paused"
    Stage "unpause"; Start-Sleep 1
    Stage "tapat"; Start-Sleep -Milliseconds 500
    $t = (Rects "bardroid_fixtest.txt")["tap"]
    if ($t) { Tap $t[0] $t[1]; Start-Sleep 1; Stage "tapaim?" } else { "[fixtest] FAIL no ground point in sight for the D-gun's tap" }
    Stage "dgunoff"
  } else { "[fixtest] FAIL no AIM stick in the dock's file" }
  Stage "end"; Start-Sleep 1
  Report
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((SetPref bool portrait $(if ($was.portrait) { $was.portrait } else { "false" })) +
    (SetPref bool turnWithPhone $(if ($was.turn) { $was.turn } else { "false" })) +
    $(if ($was.map) { SetPref string mapName $was.map } else { "" }) +
    (SetPref bool mapChosen $(if ($was.chosen) { $was.chosen } else { "false" })) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_fixtest.txt $cfg/bardroid_fixtest_cmd.txt`n" +
    "[ -f $cfg/bardroid_fixtest_dss.bak ] && mv -f $cfg/bardroid_fixtest_dss.bak files/bar/dev-springsettings.cfg`n" +
    "true`n")
  $after = (InApp "cat shared_prefs/bardroid.xml") -join "`n"
  "[fixtest] (put back: map '$([regex]::Match($after, '<string name="mapName">([^<]*)</string>').Groups[1].Value)', upright $([regex]::Match($after, 'name="portrait" value="(\w+)"').Groups[1].Value))"
}
