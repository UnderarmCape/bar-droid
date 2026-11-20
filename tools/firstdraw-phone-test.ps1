# Does the GPU driver's fault come with units drawn for the first time? (docs/DELIVERY.md, DriverWatch: Mesa's "submit
# failed -1 (Resource deadlock avoided)", most of them in a game's first minute.) On the dev phone, in a skirmish: the
# test widget (tools\firstdraw-phone-test\bardroid_firstdraw_test.lua) gives every unit type with a model, 12 every 3 s,
# to the neutral Gaia team in front of the camera; this script watches the launcher's log for the driver's refusal and
# says after how many types it came (and the batch then), or that all were drawn without it. -Runs N: that many games.
# Nothing on the laptop: it runs any time. About 4 minutes a run.
#   powershell -ExecutionPolicy Bypass -File tools\firstdraw-phone-test.ps1 [-Runs 3]
# -Mode jump: no units, the camera to another part of the map every 2 s, 90 times (ground never drawn before).
param([int]$Runs = 1, [ValidateSet("units", "jump")] [string]$Mode = "units")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_firstdraw_test.lua"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }

$faults = 0
try {
  foreach ($run in 1..$Runs) {
    & $adb shell am force-stop $pkg
    InApp "rm -f files/bar/infolog.txt"
    $mark = [int]"$(InApp "wc -l < files/logs/launcher.log")".Trim()
    Send-AppFile $adb (Join-Path $PSScriptRoot "firstdraw-phone-test\bardroid_firstdraw_test.lua") $widget
    InApp "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg; echo $Mode > files/bar/LuaUI/Config/bardroid_firstdraw_mode.txt"
    Set-PhoneAwake $adb
    & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
    $until = (Get-Date).AddMinutes(6); $result = $null
    while ((Get-Date) -lt $until -and -not $result) {
      Start-Sleep 3
      $refused = "$(InApp "tail -n +$($mark + 1) files/logs/launcher.log | grep -a -m1 'submit failed'")"
      if ($refused) {
        $faults++
        $last = "$(Log '\[firstdraw\] [0-9]+ (of|camera)' 1)" -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', ''
        $result = "run $($run): the driver's refusal after: $(if ($last) { $last } else { 'no batch yet' })"
      } elseif (Log '\[firstdraw\] done' 1) {
        $result = "run $($run): every type drawn, no refusal"
      }
    }
    if (-not $result) { $result = "run $($run): neither in 6 minutes (last: $(Log '\[firstdraw\]|Error in' 1))" }
    "[firstdraw] $result"
    & $adb shell am force-stop $pkg
    Start-Sleep 5
  }
  "[firstdraw] $faults of $Runs runs met the driver's refusal"
} finally {
  InApp "rm -f $widget files/bar/dev-springsettings.cfg files/bar/LuaUI/Config/bardroid_firstdraw_mode.txt"
  & $adb shell am force-stop $pkg
}
