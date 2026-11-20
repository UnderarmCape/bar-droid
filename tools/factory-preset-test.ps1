# A factory's preset (bardroid_presets.lua factoryForms; Kailil, 2026-11-20) on the dev phone, in a skirmish: the test
# widget (tools\factory-preset-test\bardroid_factory_preset_test.lua) gives a Bot Lab, picks it and STRAFE for it, and
# names a point of open ground; this script taps it as a finger would (the preset's own way: a tap on the map); then the
# lab builds five Pawns and three more, and the widget checks that each joins the formation with a place of its own,
# goes side to side there at once, that the formation grows wider, and that the lab's own move order ends the preset.
# Nothing on the laptop: it runs any time. About 4 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\factory-preset-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_factory_preset_test.lua"
$cfg = "files/bar/LuaUI/Config"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }

& $adb shell am force-stop $pkg
InApp "rm -f files/bar/infolog.txt $cfg/bardroid_factorytest.txt"
Send-AppFile $adb (Join-Path $PSScriptRoot "factory-preset-test\bardroid_factory_preset_test.lua") $widget
InApp "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg"   # (the log is late on a phone)
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  # the aim's point, then a tap there (X screen pixels to the display's: its width over the X screen's)
  $until = (Get-Date).AddMinutes(4); $aim = $null
  while ((Get-Date) -lt $until -and -not $aim) {
    Start-Sleep 2
    $line = "$(InApp "cat $cfg/bardroid_factorytest.txt 2>/dev/null")".Trim()
    if ($line -match '^aim (\d+) (\d+) (\d+)') { $aim = $Matches }
    elseif ($line -match '^aim nil') { "[factorytest] FAIL no open ground in sight for the aim"; break }
  }
  if ($aim) {
    $size = (& $adb shell wm size) -join " "
    $m = [regex]::Match($size, '(\d+)x(\d+)\s*$')
    $k = [double]$m.Groups[1].Value / [double]$aim[3]
    & $adb shell input tap ([int]([double]$aim[1] * $k)) ([int]([double]$aim[2] * $k))
  }
  $until = (Get-Date).AddMinutes(5)
  while ((Get-Date) -lt $until -and -not (Log '\[factorytest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[factorytest\] done' 1)) { "[factorytest] FAIL the test did not finish" }
  Log '\[factorytest\]|\[bardroid-presets\] factory|bardroid_presets.*[Ee]rror' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
} finally {
  InApp "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_factorytest.txt"
  & $adb shell am force-stop $pkg
}
