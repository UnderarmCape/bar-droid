# The upright touch dock (bardroid_portrait.lua) by real taps on the dev phone (adb input), in a skirmish: the build
# grid's first building (in sight on any screen shape; the dock's itemCell says where) picked on the dock, its spot tapped and PLACE pressed 2.6 s later (the dock's menu must still take it), PLACE on a
# blocked spot (its note), the D-gun mode's FIRE swiped right (full auto on) and left (off), its MOVE stick held and let
# go (the commander stops at once), and the STRAFE preset picked and dragged onto the map. The test widget
# (tools\dock-phone-test\bardroid_dock_test.lua) finds the spots and checks each case; the taps' places come from the
# dock's own file (bardroid_dock.txt) and the build menu's (bardroid_place.txt). "Play upright" is on for the run and
# off after. Nothing on the laptop: it runs any time. About 3 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\dock-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_dock_test.lua"
$cfg = "files/bar/LuaUI/Config"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\docktest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Stage([string]$name) { InApp "echo '$name' > $cfg/bardroid_docktest_cmd.txt" }
function WaitLog([string]$pattern, [int]$seconds) {
  $until = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $until) { $l = Log $pattern 1; if ($l) { return $l }; Start-Sleep 1 }
  return $null
}
# a file of "key a b c d" lines as a table of number arrays (the numbers of each line; a line with "nil" left out)
function Rects([string]$file) {
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
# X screen pixels to the display's (adb input): the X screen is the display scaled down
$script:k = 1.0
function Tap([double]$x, [double]$y) { & $adb shell input tap ([int]($x * $script:k)) ([int]($y * $script:k)) }
function Touch([string]$what, [double]$x, [double]$y) { & $adb shell input motionevent $what ([int]($x * $script:k)) ([int]($y * $script:k)) }
function Mid($r, [string]$what = "rect") { if (-not $r) { throw "no $what in the dock's files (bardroid_dock.txt, bardroid_place.txt)" }; return @((($r[0] + $r[2]) / 2), (($r[1] + $r[3]) / 2)) }

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_dock_test.lua")
if ($stray) { "[docktest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"true`"/' shared_prefs/bardroid.xml`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_docktest.txt $cfg/bardroid_docktest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "dock-phone-test\bardroid_dock_test.lua") $widget
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  if (-not (WaitLog '\[docktest\] ready' 240)) { throw "the game did not get to frame 300 in 4 minutes" }
  $size = (& $adb shell wm size) -join " "
  $m = [regex]::Match($size, '(\d+)x(\d+)\s*$')
  $dock = Rects "bardroid_dock.txt"
  $script:k = [double]$m.Groups[1].Value / $dock["dock"][2]   # (the display's width over the X screen's)
  $spots = Rects "bardroid_docktest.txt"
  # 1. the build grid's first building (its tile from the dock: in sight on any screen shape); a tap opens the menu, a
  # second picks it; its spot; PLACE
  $tile = Mid $spots["tile"] "the first build tile"
  # (the second tap once the dock says its menu is open: just after loading the game is slow, and a tap 0.6 s later
  # still found the camera pad and only opened the menu again. 2026-11-11, 2 runs in 5: no menu 4 s after the tap, the
  # second tap only opened it, the spot's tap then picked the ground and the commander went: a note, and one more tap)
  foreach ($try in 1..2) {
    Tap $tile[0] $tile[1]
    $until = (Get-Date).AddSeconds(4); $head = ""
    while ((Get-Date) -lt $until -and -not ($head -match ' menu')) { Start-Sleep -Milliseconds 200; $head = "$(InApp "head -n 1 $cfg/bardroid_dock.txt")" }
    if ($head -match ' menu') { break }
    "[docktest] note: a tap on the dock did not open its menu in 4 s (tap $try; the dock's line: $head)"
  }
  Tap $tile[0] $tile[1]
  # (the spot's tap once the building is picked: PLACE in the build menu's file)
  $until = (Get-Date).AddSeconds(3)
  while ((Get-Date) -lt $until -and -not (Rects "bardroid_place.txt")["done"]) { Start-Sleep -Milliseconds 200 }
  if (-not (Rects "bardroid_place.txt")["done"]) { "[docktest] note: the tile's tap did not pick the building in 3 s (place file: $(InApp "cat $cfg/bardroid_place.txt" | Select-Object -First 2))" }
  if ($spots["free"]) { Tap $spots["free"][0] $spots["free"][1] }
  Start-Sleep -Milliseconds 2600   # (past the 2 s the dock's menu once had: PLACE's tap only opened it again)
  $p = Mid (Rects "bardroid_place.txt")["done"] "PLACE (the building not picked?)"; Tap $p[0] $p[1]
  Start-Sleep -Milliseconds 1500
  Stage "placed?"
  # 2. PLACE on a blocked spot
  if ($spots["blocked"]) {
    Tap $spots["blocked"][0] $spots["blocked"][1]; Start-Sleep -Milliseconds 900
    $p = Mid (Rects "bardroid_place.txt")["done"] "PLACE"; Tap $p[0] $p[1]; Start-Sleep -Milliseconds 400
    Stage "blocked?"
  } else { "[docktest] (no blocked spot on the screen: that case left out)" }
  Start-Sleep 1
  $place = Rects "bardroid_place.txt"
  if ($place["cancel"]) { $p = Mid $place["cancel"] "the building's cancel"; Tap $p[0] $p[1]; Start-Sleep 1 }
  # 3. the D-gun mode: FIRE swiped right to the grid's edge, AUTO swiped left to the cancel corner
  Stage "dgun"
  if (-not (WaitLog '\[docktest\] dgun on' 10)) { throw "the D-gun mode did not open" }
  Start-Sleep 1
  $dock = Rects "bardroid_dock.txt"
  $f = Mid $dock["fire"] "FIRE"
  Touch DOWN $f[0] $f[1]; Touch MOVE ($f[0] + 60) $f[1]; Touch MOVE ($dock["right"][2] - 4) $f[1]
  Start-Sleep -Milliseconds 300; Touch UP ($dock["right"][2] - 4) $f[1]; Start-Sleep -Milliseconds 700
  Stage "auto?"; Start-Sleep 1
  Touch DOWN $f[0] $f[1]; Touch MOVE ($f[0] - 40) $f[1]; Touch MOVE ($dock["cancel"][2] + 2) $f[1]
  Start-Sleep -Milliseconds 300; Touch UP ($dock["cancel"][2] + 2) $f[1]; Start-Sleep -Milliseconds 700
  Stage "autooff?"; Start-Sleep 1
  # 4. MOVE held up 1.5 s, let go
  Stage "walk"; Start-Sleep 1
  $s = $dock["stickl"]
  & $adb shell input swipe ([int]($s[0] * $script:k)) ([int]($s[1] * $script:k)) ([int]($s[0] * $script:k)) ([int](($s[1] - $s[2] * 0.9) * $script:k)) 1800
  Start-Sleep -Milliseconds 700
  Stage "stopped?"; Start-Sleep 1
  # 5. the presets: STRAFE (the grid's top left quarter), then a drag on the map, lifted at its end
  Stage "presets"
  if (-not (WaitLog '\[docktest\] presets open' 20)) { throw "the presets did not open" }
  Start-Sleep 1
  $dock = Rects "bardroid_dock.txt"; $aims = Rects "bardroid_docktest.txt"
  $g = @($dock["left"][0], $dock["left"][1], $dock["right"][2], $dock["left"][3])
  Tap ($g[0] + ($g[2] - $g[0]) / 4) ($g[1] + ($g[3] - $g[1]) / 4); Start-Sleep -Milliseconds 900
  $a0 = $aims["aim0"]; $a1 = $aims["aim1"]
  # (from over the void past the map's edge when the screen shows some: the aim must begin once the finger reaches the
  # ground; a press there lost the whole drag, 2026-11-11)
  if ($aims["void"]) {
    "[docktest] the STRAFE drag starts over the void"
    $v = $aims["void"]; Touch DOWN $v[0] $v[1]; Start-Sleep -Milliseconds 150
    Touch MOVE (($v[0] + $a0[0]) / 2) (($v[1] + $a0[1]) / 2); Touch MOVE $a0[0] $a0[1]
  } else { "[docktest] (no void on the screen: the STRAFE drag starts on the ground)"; Touch DOWN $a0[0] $a0[1] }
  Start-Sleep -Milliseconds 150
  Touch MOVE (($a0[0] + $a1[0]) / 2) (($a0[1] + $a1[1]) / 2); Touch MOVE $a1[0] $a1[1]
  Start-Sleep -Milliseconds 300; Touch UP $a1[0] $a1[1]; Start-Sleep -Milliseconds 1500
  Stage "strafe?"; Start-Sleep 1
  Stage "end"
  if (-not (WaitLog '\[docktest\] done' 10)) { "[docktest] FAIL the widget did not finish" }
  Log '\[docktest\] (PASS|FAIL|done)|Error in|Removed widget' 20 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_docktest.txt $cfg/bardroid_docktest_cmd.txt`n")
}
