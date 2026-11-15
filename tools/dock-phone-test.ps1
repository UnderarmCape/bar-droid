# The upright touch dock (bardroid_portrait.lua) by real taps on the dev phone (adb input), in a skirmish: the build
# grid's first building (in sight on any screen shape; the dock's itemCell says where) picked on the dock, its spot tapped and PLACE pressed 2.6 s later (the dock's menu must still take it), PLACE on a
# blocked spot (its note), the D-gun mode's FIRE swiped right (full auto on) and left (off), its MOVE stick held and let
# go (the commander stops at once), and the STRAFE preset picked and dragged onto the map. The test widget
# (tools\dock-phone-test\bardroid_dock_test.lua) finds the spots and checks each case; the taps' places come from the
# dock's own file (bardroid_dock.txt) and the build menu's (bardroid_place.txt). "Play upright" is on for the run and
# off after. Nothing on the laptop: it runs any time. About 3 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\dock-phone-test.ps1 [-Shots]
# -Shots: screenshots of the placing panel, the D-gun mode and a preset's aim, build\dock-*.png (to judge the dock's look)
param([switch]$Shots)
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
# a tap, then a finger down at the same point within the double tap's time (one adb call): a drag after it selects
function TapDown([double]$x, [double]$y) {
  $px = [int]($x * $script:k); $py = [int]($y * $script:k)
  & $adb shell "input tap $px $py; input motionevent DOWN $px $py"
}
function Shot([string]$name) {
  if (-not $Shots) { return }
  & $adb shell screencap -p /sdcard/bardroid-dockshot.png
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
  try { $null = & $adb pull /sdcard/bardroid-dockshot.png (Join-Path (Split-Path $PSScriptRoot) "build\dock-$name.png") 2>&1 }
  finally { $ErrorActionPreference = $eap }
  & $adb shell rm -f /sdcard/bardroid-dockshot.png
}
function Mid($r, [string]$what = "rect") { if (-not $r) { throw "no $what in the dock's files (bardroid_dock.txt, bardroid_place.txt)" }; return @((($r[0] + $r[2]) / 2), (($r[1] + $r[3]) / 2)) }
# the dock's middle for a drag or tap onto it: on a near-square screen the split dock's right block (its middle is the
# game's, the dock file's "gap"), else the whole dock's
function DockMid($d) { if ($d["gap"]) { return Mid $d["right"] "the dock's right block" }; return Mid $d["dock"] "the dock" }
# the grid the home buttons and the presets take: the split dock's right block, else both halves
function WholeGrid($d) { if ($d["gap"]) { return $d["right"] }; return @($d["left"][0], $d["left"][1], $d["right"][2], $d["left"][3]) }

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
    $t0 = Get-Date; Tap $tile[0] $tile[1]; $tapMs = ((Get-Date) - $t0).TotalMilliseconds
    $until = (Get-Date).AddSeconds(4); $head = ""
    while ((Get-Date) -lt $until -and -not ($head -match ' menu')) { Start-Sleep -Milliseconds 200; $head = "$(InApp "head -n 1 $cfg/bardroid_dock.txt")" }
    "[docktest] (the tile's first tap: adb {0:N0} ms, the menu in the dock's file {1:N0} ms after the tap began)" -f $tapMs, ((Get-Date) - $t0).TotalMilliseconds
    if ($head -match ' menu') { break }
    "[docktest] note: a tap on the dock did not open its menu in 4 s (tap $try; the dock's line: $head)"
  }
  $t0 = Get-Date; Tap $tile[0] $tile[1]
  # (the spot's tap once the building is picked: PLACE in the build menu's file)
  $until = (Get-Date).AddSeconds(3)
  while ((Get-Date) -lt $until -and -not (Rects "bardroid_place.txt")["done"]) { Start-Sleep -Milliseconds 200 }
  "[docktest] (the tile's second tap: the building picked {0:N0} ms after the tap began)" -f ((Get-Date) - $t0).TotalMilliseconds
  if (-not (Rects "bardroid_place.txt")["done"]) { "[docktest] note: the tile's tap did not pick the building in 3 s (place file: $(InApp "cat $cfg/bardroid_place.txt" | Select-Object -First 2); dock: $(InApp "head -n 1 $cfg/bardroid_dock.txt"))" }
  # (the building, no spot yet, dragged from the map on into the dock: it moves by part of the finger's way, held at the
  # dock's top edge)
  if ($spots["free"]) {
    $dm0 = DockMid $dock; $f0 = $spots["free"]
    Touch DOWN $f0[0] $f0[1]; Start-Sleep -Milliseconds 120
    Touch MOVE $f0[0] (($f0[1] + $dm0[1]) / 2); Touch MOVE $dm0[0] $dm0[1]
    Start-Sleep -Milliseconds 300; Touch UP $dm0[0] $dm0[1]; Start-Sleep -Milliseconds 700
    $spot = (Rects "bardroid_place.txt")["spot"]
    Stage "spotdock? $(if ($spot) { [int]$spot[1] } else { -1 })"; Start-Sleep 1
  }
  if ($spots["free"]) { Tap $spots["free"][0] $spots["free"][1] }
  Shot "place"
  Start-Sleep -Milliseconds 3200   # (past the dock menu's 2.6 s: once PLACE's tap after its time-out only opened it again)
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
  # (a GRID: a finger held on the map with the building picked, then dragged on into the dock: its far corner, the
  # pointer held down for BAR's build drag, stays at the dock's top edge; the cancel below lets it go, nothing placed)
  if ($spots["free"]) {
    $fr = $spots["free"]; $dmg = DockMid $dock
    Touch DOWN $fr[0] $fr[1]; Start-Sleep -Milliseconds 1000
    Touch MOVE $fr[0] (($fr[1] + $dmg[1]) / 2); Touch MOVE $fr[0] $dmg[1]
    Start-Sleep -Milliseconds 300; Touch UP $fr[0] $dmg[1]; Start-Sleep -Milliseconds 600
    Stage "griddock?"; Start-Sleep 1
  }
  $place = Rects "bardroid_place.txt"
  if ($place["cancel"]) { $p = Mid $place["cancel"] "the building's cancel"; Tap $p[0] $p[1]; Start-Sleep 1; Stage "cancelled?"; Start-Sleep 1 }
  # 3. the D-gun mode: FIRE swiped right to the grid's edge, AUTO swiped left to the cancel corner
  Stage "dgun"
  if (-not (WaitLog '\[docktest\] dgun on' 10)) { throw "the D-gun mode did not open" }
  Start-Sleep 1
  $dock = Rects "bardroid_dock.txt"
  $f = Mid $dock["fire"] "FIRE"
  Touch DOWN $f[0] $f[1]; Touch MOVE ($f[0] + 60) $f[1]; Touch MOVE ($dock["right"][2] - 4) $f[1]
  Start-Sleep -Milliseconds 300; Touch UP ($dock["right"][2] - 4) $f[1]; Start-Sleep -Milliseconds 700
  Stage "auto?"; Shot "dgun-auto"; Start-Sleep 1
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
  $g = WholeGrid $dock
  Tap ($g[0] + ($g[2] - $g[0]) / 4) ($g[1] + ($g[3] - $g[1]) / 4); Start-Sleep -Milliseconds 900
  $a0 = $aims["aim0"]; $a1 = $aims["aim1"]
  # (first a drag from the map down onto the dock: with a preset armed a finger's drag pans (taps only, Kailil
  # 2026-11-13: "make presets a single tap only"), nothing sent, STRAFE still armed)
  $dm = DockMid $dock
  Touch DOWN $a0[0] $a0[1]; Start-Sleep -Milliseconds 150
  Touch MOVE $a0[0] (($a0[1] + $dm[1]) / 2); Touch MOVE $dm[0] $dm[1]
  Start-Sleep -Milliseconds 200; Touch UP $dm[0] $dm[1]; Start-Sleep -Milliseconds 800
  Stage "dockback?"; Start-Sleep 1
  # (then a tap on the map: STRAFE sent there)
  Tap $a1[0] $a1[1]; Start-Sleep -Milliseconds 1500
  Stage "strafe?"; Start-Sleep 1
  # (once the Pawns stand on the line: their side to side on repeat)
  if (-not (WaitLog '\[bardroid-presets\] STRAFE: [0-9]+ units there' 75)) { "[docktest] (the Pawns were not there in 75 s)" }
  Stage "sway?"; Start-Sleep 1
  # 6. the Pawns picked: one finger dragged on the game pans, no path (Kailil, 2026-11-13: "Pan, hold for paths"); then
  # their path by a press held, then a drag, from the map on into the dock: held at the dock's top edge, every goal in sight
  Stage "campos"; Start-Sleep -Milliseconds 300
  Touch DOWN $a1[0] $a1[1]; Start-Sleep -Milliseconds 120
  Touch MOVE ($a1[0] + 60) ($a1[1] + 40); Touch MOVE ($a1[0] + 160) ($a1[1] + 100)
  Start-Sleep -Milliseconds 200; Touch UP ($a1[0] + 160) ($a1[1] + 100); Start-Sleep -Milliseconds 800
  Stage "pickpanned?"; Start-Sleep 1
  Touch DOWN $a1[0] $a1[1]; Start-Sleep -Milliseconds 700   # (held past RtsTouch's long press, 450 ms: the right button)
  # (on the split dock its end on the right block's inner edge: at the block's middle, straight under the aim and held
  # at the dock's top, the path was ~100 pixels long and no order came; the full dock's diagonal to its middle ~400)
  $dp = if ($dock["gap"]) { @(($dock["right"][0] + 12), $dm[1]) } else { $dm }
  Touch MOVE $a1[0] (($a1[1] + $dp[1]) / 2); Touch MOVE $dp[0] $dp[1]
  Start-Sleep -Milliseconds 300; Touch UP $dp[0] $dp[1]; Start-Sleep -Milliseconds 1200
  Stage "drawdock?"; Start-Sleep 1
  # 7. nothing picked, the dock's menu open: a drag on the game pans (Kailil, 2026-11-13: one finger pans, always), then
  # a tap and a drag: a box selection dragged from the map on into the dock, its corner held at the dock's top edge
  Stage "deselect"; Start-Sleep 2
  Tap $dm[0] $dm[1]
  $until = (Get-Date).AddSeconds(3)
  while ((Get-Date) -lt $until -and -not ((InApp "head -n 1 $cfg/bardroid_dock.txt") -match ' menu')) { Start-Sleep -Milliseconds 200 }
  Stage "campos"; Start-Sleep -Milliseconds 300
  Touch DOWN $a1[0] $a1[1]; Start-Sleep -Milliseconds 120
  Touch MOVE ($a1[0] + 60) ($a1[1] + 40); Touch MOVE ($a1[0] + 160) ($a1[1] + 100)
  Start-Sleep -Milliseconds 200; Touch UP ($a1[0] + 160) ($a1[1] + 100); Start-Sleep -Milliseconds 800
  Stage "panned?"; Start-Sleep 1
  TapDown $a1[0] $a1[1]; Start-Sleep -Milliseconds 120
  Touch MOVE $a1[0] (($a1[1] + $dm[1]) / 2); Touch MOVE ($a1[0] + 80) $dm[1]
  Start-Sleep -Milliseconds 300; Touch UP ($a1[0] + 80) $dm[1]; Start-Sleep -Milliseconds 800
  Stage "boxdock?"; Start-Sleep 1
  # 8. the circle style: a circle drawn from just above the dock on into it; a Pawn just behind the dock's edge,
  # inside the circle on the ground, is not picked (the style put back after)
  # (nothing picked first: the dock is lower without its selection row, and the Pawn must be behind the dock as it is
  # while the circle is drawn)
  Stage "deselect-again"; Start-Sleep 2
  Stage "circle"; Start-Sleep 2
  $cs = Rects "bardroid_docktest.txt"
  if ($cs["circle0"] -and $cs["circle1"]) {
    $c0 = $cs["circle0"]; $c1 = $cs["circle1"]
    TapDown $c0[0] $c0[1]; Start-Sleep -Milliseconds 120   # (a tap, then the drag: the dock's circle selects)
    Touch MOVE $c0[0] (($c0[1] + $c1[1]) / 2); Touch MOVE $c1[0] $c1[1]
    Start-Sleep -Milliseconds 300; Touch UP $c1[0] $c1[1]; Start-Sleep -Milliseconds 1000
  } else { "[docktest] note: no circle's points" }
  Stage "circledock?"; Start-Sleep 1
  Stage "end"
  if (-not (WaitLog '\[docktest\] done' 10)) { "[docktest] FAIL the widget did not finish" }
  Log '\[docktest\] (PASS|FAIL|done)|Error in|Removed widget' 20 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_docktest.txt $cfg/bardroid_docktest_cmd.txt`n")
}
