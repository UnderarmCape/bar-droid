# The Settings copy's search field (bardroid_options.lua; 2026-11-19's system) upright on the dev phone, in a skirmish,
# by real taps and keys: the test widget (tools\settings-phone-test\bardroid_settings_test.lua) finds BAR's Settings
# button on the top bar and asks for its tap; the search field tapped (focused, Android's keyboard asked and up),
# "shadow" typed with adb shell input text (the list cut), the field's clear button (the list whole), Back (the keyboard
# down, Settings open), "radar" typed, Back (the search cleared), Back (closed), opened again and the red close tapped.
# The widget asks "do <n> tap|shot|ime|type|key x y vsx [text|key code]", answered "<n> [answer]" ("ime": 1 when
# Android's input method is shown); pictures in build\settings-<n>.png. "Play upright" on for the run, "Turn with the
# phone" off, both put back after. Nothing on the laptop: it runs any time. About 2 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\settings-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$widget = "files/bar/LuaUI/Widgets/bardroid_settings_test.lua"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\settingstest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}
function ImeShown {
  $lines = @(& $adb shell dumpsys input_method | Select-String -Pattern '(?i)\b(mInputShown|mWindowVisible|mDecorViewVisible|mIsInputViewShown)=')
  "[settingstest] (input method: $((($lines | ForEach-Object { $_.Line.Trim() }) | Select-Object -Unique) -join '; '))" | Out-Host
  return [bool](($lines -join "`n") -match '(?i)\bmInputShown=true')
}

& $adb shell am force-stop $pkg
$stray = Get-StrayWidgets $adb @("bardroid_settings_test.lua")
if ($stray) { "[settingstest] warning: widgets on the phone that are not the app's (they run in the test's game): $($stray -join ', ')" }
$prefs = "$(InApp "cat shared_prefs/bardroid.xml")"
$portraitWas = $prefs -match 'name=.portrait. value=.true.'
$turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
AppScript ((Pref "portrait" $true) + (Pref "turnWithPhone" $false) +
  "rm -f files/bar/infolog.txt $cfg/bardroid_settingstest.txt $cfg/bardroid_settingstest_cmd.txt`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "settings-phone-test\bardroid_settings_test.lua") $widget
& $adb logcat -c
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.LauncherActivity" --es start skirmish | Out-Null
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(6); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_settingstest.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|shot|ime|type|key) (-?\d+) (-?\d+) (\d+)(?: (\S+))?' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]; $arg = $Matches[6]
      if ($act -ne "shot") { Assert-GameInFront $adb }   # (no taps on the launcher: toolchain.ps1)
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      $reply = "$n"
      switch ($act) {
        "shot" {
          & $adb shell screencap -p /sdcard/bardroid-settingsshot.png
          $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
          try { $null = & $adb pull /sdcard/bardroid-settingsshot.png (Join-Path $build "settings-$n.png") 2>&1 }
          finally { $ErrorActionPreference = $eap }
          & $adb shell rm -f /sdcard/bardroid-settingsshot.png
          "[settingstest] ($($n): a picture, build\settings-$n.png)"
        }
        "ime" {
          Start-Sleep -Milliseconds 1200   # (the keyboard's slide)
          $on = ImeShown
          $reply = "$n $(if ($on) { 1 } else { 0 })"
          & $adb shell screencap -p /sdcard/bardroid-settingsshot.png   # (what the screen shows of it)
          $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
          try { $null = & $adb pull /sdcard/bardroid-settingsshot.png (Join-Path $build "settings-$n.png") 2>&1 }
          finally { $ErrorActionPreference = $eap }
          "[settingstest] ($($n): Android's keyboard $(if ($on) { 'shown' } else { 'not shown' }))"
        }
        "type" { & $adb shell input text $arg; "[settingstest] ($($n): typed $arg)" }
        "key" { & $adb shell input keyevent $arg; "[settingstest] ($($n): key $arg)" }
        default { & $adb shell input tap $x $y; "[settingstest] ($($n): a tap at $x,$y)" }
      }
      InApp "echo $reply > $cfg/bardroid_settingstest_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 400
  }
  if (-not (Log '\[settingstest\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[settingstest\] done' 1)) { "[settingstest] FAIL the test did not finish" }
  Log '\[settingstest\]|bardroid_options.*[Ee]rror|bardroid_touch.*[Ee]rror|Error in' 40 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  $asks = @(& $adb logcat -d | Select-String "game's text field tapped").Count
  "[settingstest] (the app's log: `"a game's text field tapped`" $asks time(s))"
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "rm -f $widget files/bar/dev-springsettings.cfg $cfg/bardroid_settingstest.txt $cfg/bardroid_settingstest_cmd.txt`n")
}
