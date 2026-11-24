# The user guide's pictures (docs/guide) taken on the dev phone in a skirmish: the dock with nothing picked, its home
# buttons, the commander picked (with the unit info panel), the metal and energy panels, the wind's details, a building
# being placed, six Pawns, a group, a mixed pick, the presets, the D-gun mode and the layout editor. The helper widget
# (tools\guide-shots\bardroid_guide_shots.lua) sets each up; this script taps the dock where a finger would and takes the
# screenshots: build\guide\<shape>-<n>-<name>.png. Not a test: it checks nothing.
#   powershell -ExecutionPolicy Bypass -File tools\guide-shots.ps1 [-Shape upright|unfolded|sideways]
# upright: the phone as it is, "Play upright" on; unfolded: the display at 1080x1198 for the run (wm size, the Fold7
# unfolded's shape), reset after; sideways: "Play upright" off. The player's settings put back after. Take the dev
# phone's lock around it (devphone-lock.ps1 take/free). About 4 minutes.
param([ValidateSet("upright", "unfolded", "sideways")][string]$Shape = "upright")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_guide_shots.lua"
$cfg = "files/bar/LuaUI/Config"
$out = Join-Path (Split-Path $PSScriptRoot) "build\guide"
New-Item -ItemType Directory -Force $out | Out-Null

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\guideshots.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function WaitLog([string]$pattern, [int]$seconds) {
  $until = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $until) { $l = Log $pattern 1; if ($l) { return $l }; Start-Sleep -Milliseconds 500 }
  return $null
}
$script:n = 0
function Stage([string]$name, [double]$wait = 1.5) {
  InApp "echo '$name' > $cfg/bardroid_guideshots_cmd.txt"
  $null = WaitLog "\[guideshots\] $name ok" 10
  Start-Sleep -Milliseconds ([int]($wait * 1000))
}
function Rects() {
  $t = @{}
  foreach ($line in (InApp "cat $cfg/bardroid_guideshots.txt 2>/dev/null")) {
    $f = "$line".Trim() -split ' '
    if ($f.Count -lt 3) { continue }
    $nums = @(); foreach ($v in $f[1..($f.Count - 1)]) { $d = 0.0; if ([double]::TryParse($v, [ref]$d)) { $nums += $d } }
    $t[$f[0]] = $nums
  }
  return $t
}
$script:k = 1.0
function Tap([double]$x, [double]$y) { Assert-GameInFront $adb; & $adb shell input tap ([int]($x * $script:k)) ([int]($y * $script:k)) }
function TapMid($r) { if ($r) { Tap (($r[0] + $r[2]) / 2) (($r[1] + $r[3]) / 2); return $true }; return $false }
function Shot([string]$name) {
  $script:n++
  $file = Join-Path $out ("{0}-{1:D2}-{2}.png" -f $Shape, $script:n, $name)
  & $adb shell screencap -p /sdcard/bardroid-guideshot.png
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $null = & $adb pull /sdcard/bardroid-guideshot.png $file 2>&1 } finally { $ErrorActionPreference = $eap }
  & $adb shell rm -f /sdcard/bardroid-guideshot.png
  "[guideshots] $file"
}

& $adb shell am force-stop $pkg
$portraitWas = (InApp "grep -o 'name=.portrait. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
$turnWas = (InApp "grep -o 'name=.turnWithPhone. value=.[a-z]*.' shared_prefs/bardroid.xml") -match 'value=.true.'
$upright = if ($Shape -eq "sideways") { "false" } else { "true" }
AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"$upright`"/' shared_prefs/bardroid.xml`n" +
  "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"false`"/' shared_prefs/bardroid.xml`n" +
  "rm -f files/bar/infolog.txt $cfg/bardroid_guideshots.txt $cfg/bardroid_guideshots_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "guide-shots\bardroid_guide_shots.lua") $widget
try {
  if ($Shape -eq "unfolded") { & $adb shell wm size 1080x1198 }
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  if (-not (WaitLog '\[guideshots\] ready' 240)) { throw "the game did not get to frame 320 in 4 minutes" }
  Start-Sleep 2
  $dockLine = InApp "grep -a -E '^dock ' $cfg/bardroid_dock.txt | head -1"
  $wm = [regex]::Match("$(& $adb shell wm size)" -join " ", '(\d+)x(\d+)\s*$')
  $dw = [double]("$dockLine".Trim() -split ' ')[3]
  $sizes = @([double]$wm.Groups[1].Value, [double]$wm.Groups[2].Value)
  # (the display's width over the X screen's; sideways the display's long side is the game's width)
  $dispW = if ($Shape -eq "sideways") { ($sizes | Measure-Object -Maximum).Maximum } else { $sizes[0] }
  if ($dw -gt 0) { $script:k = $dispW / $dw }
  "[guideshots] $Shape, X width $dw, k $($script:k)"
  Stage "none"; Shot "start"
  Stage "menu"; Shot "home-buttons"
  Stage "none"
  Stage "com" 2.5; Shot "commander"
  Stage "rects" 0.5; $r = Rects
  if (TapMid $r["energy"]) { Start-Sleep -Milliseconds 1500; Shot "energy-panel"; [void](TapMid $r["energy"]); Start-Sleep 1 }
  Stage "com" 1; Stage "rects" 0.5; $r = Rects
  if (TapMid $r["metal"]) { Start-Sleep -Milliseconds 1500; Shot "metal-panel"; [void](TapMid $r["metal"]); Start-Sleep 1 }
  Stage "com" 1; Stage "rects" 0.5; $r = Rects
  if (TapMid $r["wind"]) { Start-Sleep -Milliseconds 1500; Shot "wind-details"; [void](TapMid $r["wind"]); Start-Sleep 1 }
  Stage "com" 1.5; Stage "rects" 0.5; $r = Rects
  if ($r["infotab"] -and $r["info"]) {   # (the info panel folded to its tab and open again)
    $i = $r["info"]; Tap ($i[0] + ($i[2] - $i[0]) * 0.8) (($i[1] + $i[3]) / 2); Start-Sleep -Milliseconds 1200; Shot "info-folded"
    Stage "rects" 0.5; $r = Rects; [void](TapMid $r["infotab"]); Start-Sleep -Milliseconds 1200
  }
  Stage "com" 1; Stage "rects" 0.5; $r = Rects
  if ($r["tile"]) {   # (a building picked from the build grid: the first tap may only open the dock's menu)
    [void](TapMid $r["tile"]); Start-Sleep -Milliseconds 900; [void](TapMid $r["tile"]); Start-Sleep -Milliseconds 1500
    Shot "building-picked"
    & $adb shell input keyevent 4; Start-Sleep 1
  }
  Stage "give" 6
  Stage "pickarmy" 2; Shot "army"
  Stage "group" 2; Shot "group"
  Stage "mixed" 2; Shot "mixed-pick"
  Stage "cons" 2; Shot "constructors"
  Stage "presets" 2; Shot "presets"
  Stage "presetsoff" 1
  Stage "dgun" 2.5; Shot "dgun-mode"
  Stage "dgunoff" 1
  Stage "editor" 2; Shot "layout-editor"
  Stage "editoroff" 1
  Stage "none" 1
  & $adb shell input keyevent 4; Start-Sleep -Milliseconds 1500; Shot "quit-question"
  & $adb shell input keyevent 4; Start-Sleep 1
  Log '\[guideshots\]|Error in|Removed widget' 100 | Select-Object -Last 8 | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  & $adb shell am force-stop $pkg
  if ($Shape -eq "unfolded") { & $adb shell wm size reset }
  AppScript ("sed -i -E 's/name=.portrait. value=.(true|false)./name=`"portrait`" value=`"$(if ($portraitWas) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n" +
    $(if ($turnWas) { "sed -i -E 's/name=.turnWithPhone. value=.(true|false)./name=`"turnWithPhone`" value=`"true`"/' shared_prefs/bardroid.xml`n" } else { "" }) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_guideshots.txt $cfg/bardroid_guideshots_cmd.txt`n")
}
