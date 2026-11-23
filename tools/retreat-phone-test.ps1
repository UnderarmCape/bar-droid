# Auto retreat by repeatable fights (bardroid_retreat.lua; Kailil, 2026-11-20: "Make sure auto retreat issues working
# for all combat units. Actually test it.") on the dev phone, in a skirmish: the test widget
# (tools\retreat-phone-test\bardroid_retreat_test.lua) turns AUTO RETREAT on and plays a round for each kind of combat
# unit (a bot, a vehicle, a hover, an amphibious one, a T2 one, a squad of four Pawns), two of it given facing an enemy
# pack of Grunts (and T2 Cans for the T2); every unit watched: hurt under 50 %, fell back within a second, got clear, turned back into the fight, died
# before or after falling back; per kind and in all. Nothing on the laptop: it runs any time. About 3 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\retreat-phone-test.ps1 [-Only hover]
# -Only <kind> (bot, vehicle, hover, amphibious, T2, squad): that kind's on and off rounds three times, each unit's
# first 3 s after falling back logged (its order, the point reachable for it, its speed, the enemy's distance).
# -Commander: the commander's case alone (the coordinator's tour, 2026-11-22): the D-gun mode entered and left, a 12 s
# pause, two enemy Bulldogs and the fight in 1 s steps between 6 s pauses: not read as catching up after the pause, the
# retreat within a second of going under half; the Bulldogs removed for the retreat's watch, then the player's Fight
# back into two fresh ones: under 30 % the dock's warning. ~3 min.
param([string]$Only = "", [switch]$Commander)
if ($Commander) { $Only = "commander" }
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_retreat_test.lua"
$cfg = "files/bar/LuaUI/Config"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }

& $adb shell am force-stop $pkg
# (AUTO RETREAT as the player had it, put back after: the test turns it on and off, and a run that broke off left it off)
$retreatWas = "$(InApp "cat $cfg/bardroid_retreat.txt 2>/dev/null")".Trim()
InApp "rm -f files/bar/infolog.txt $cfg/bardroid_retreattest.txt $cfg/bardroid_retreattest_only.txt"
if ($Only) { InApp "echo $Only > $cfg/bardroid_retreattest_only.txt" }
Send-AppFile $adb (Join-Path $PSScriptRoot "retreat-phone-test\bardroid_retreat_test.lua") $widget
InApp "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg"   # (the log is late on a phone)
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $until = (Get-Date).AddMinutes(9)
  while ((Get-Date) -lt $until -and -not (Log '\[retreattest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[retreattest\] done' 1)) { "[retreattest] FAIL the test did not finish" }
  Log '\[retreattest\]|\[bardroid-retreat\] (commander|off|on)|\[bardroid-catchup\]|bardroid_retreat.*[Ee]rror|Error in' 60 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  InApp "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_retreattest.txt $cfg/bardroid_retreattest_only.txt"
  $put = if ($retreatWas -match '^on [01]$') { $retreatWas } else { "on 1" }
  InApp "echo '$put' > $cfg/bardroid_retreat.txt"
  & $adb shell am force-stop $pkg
}
