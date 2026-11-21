# BAR's lobby over a running game (2026-11-19's system: Load Game and Replays there, Return to Battle) upright on the
# dev phone, by real taps: the lobby offline (tools\lobby-login\bardroid_login_wait.lua: the tests never log in); its
# test widget (tools\overgame-phone-test\bardroid_overgame_menu_test.lua) loads the newest save from Load Game; in the
# game the game's test widget (bardroid_overgame_ui_test.lua) taps BAR's Lobby on the top bar; over the game Replays
# (Add, not Open Folder), Load Game (the dates year first, Load and Delete apart), a drag over the lobby (the game's
# camera still), Return to Battle (the overlay file "0", the camera knob back, a drag on the map pans). Both widgets ask
# "do <n> tap|shot|swipe x y vsx [x2 y2]" in their own file, answered "<n>"; pictures build\overgame-<widget>-<n>.png.
# "Play upright" on for the run, "Turn with the phone" off, both put back after. Nothing on the laptop. About 3 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\overgame-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$menuWidgets = "files/bar/LuaMenu/Widgets"
$uiWidget = "files/bar/LuaUI/Widgets/bardroid_overgame_ui_test.lua"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"
$files = "$cfg/bardroid_overgame_menu.txt $cfg/bardroid_overgame_menu_cmd.txt $cfg/bardroid_overgame_ui.txt $cfg/bardroid_overgame_ui_cmd.txt $cfg/bardroid_overgame_state.txt"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\overgametest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}

& $adb shell am force-stop $pkg
$prefs = "$(InApp "cat shared_prefs/bardroid.xml")"
$portraitWas = $prefs -match 'name=.portrait. value=.true.'
$turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
AppScript ((Pref "portrait" $true) + (Pref "turnWithPhone" $false) +
  "rm -f files/bar/infolog.txt $files`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua") "$menuWidgets/bardroid_login_wait.lua"
Send-AppFile $adb (Join-Path $PSScriptRoot "overgame-phone-test\bardroid_overgame_menu_test.lua") "$menuWidgets/bardroid_overgame_menu_test.lua"
Send-AppFile $adb (Join-Path $PSScriptRoot "overgame-phone-test\bardroid_overgame_ui_test.lua") $uiWidget
$lines = New-Object System.Collections.Generic.List[string]   # ("[overgame]" lines as they come: a new engine starts a new infolog)
function Collect {
  foreach ($l in @(InApp "grep -a -E '\[overgame\]|bardroid_overgame.*[Ee]rror|Error in' files/bar/infolog.txt 2>/dev/null")) {
    $s = "$l" -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', ''
    if ($s -and -not $lines.Contains($s)) { $lines.Add($s) }
  }
}
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.StartActivity" | Out-Null   # (the app icon: the lobby)
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(8); $seen = @{ menu = 0; ui = 0 }
  while ((Get-Date) -lt $until) {
    $done = $false
    foreach ($who in "menu", "ui") {
      $line = "$(InApp "cat $cfg/bardroid_overgame_$who.txt 2>/dev/null")".Trim()
      if ($who -eq "ui" -and $line -eq "end") { $done = $true }
      if ($line -match '^do (\d+) (tap|shot|swipe) (-?\d+) (-?\d+) (\d+)(?: (-?\d+) (-?\d+))?' -and [int]$Matches[1] -gt $seen[$who]) {
        $n = [int]$Matches[1]; $act = $Matches[2]
        if ($act -ne "shot") { Assert-GameInFront $adb }   # (no taps on the launcher: toolchain.ps1)
        $k = $w / [double]$Matches[5]
        $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
        if ($act -eq "shot") {
          & $adb shell screencap -p /sdcard/bardroid-overgameshot.png
          $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
          try { $null = & $adb pull /sdcard/bardroid-overgameshot.png (Join-Path $build "overgame-$who-$n.png") 2>&1 }
          finally { $ErrorActionPreference = $eap }
          & $adb shell rm -f /sdcard/bardroid-overgameshot.png
          "[overgame] ($who $($n): a picture, build\overgame-$who-$n.png)"
        } elseif ($act -eq "swipe") {
          $x2 = [int]([double]$Matches[6] * $k); $y2 = [int]([double]$Matches[7] * $k)
          & $adb shell input swipe $x $y $x2 $y2 600
          "[overgame] ($who $($n): a drag $x,$y to $x2,$y2)"
        } else {
          & $adb shell input tap $x $y
          "[overgame] ($who $($n): a tap at $x,$y)"
        }
        InApp "echo $n > $cfg/bardroid_overgame_$($who)_cmd.txt"
        $seen[$who] = $n
      }
    }
    Collect
    if ($done) { break }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep 2; Collect
  # (counted in the summary: it said "ALL PASS" under this line while the lobby never opened, 2026-11-21)
  $unfinished = -not ($lines | Where-Object { $_ -match '\[overgame\] game done' })
  if ($unfinished) { "[overgame] FAIL the test did not finish" }
  $lines
  $fails = @($lines | Where-Object { $_ -match '\[overgame\] FAIL' }).Count + [int]$unfinished
  "[overgame] done: $(if ($fails -eq 0) { 'ALL PASS' } else { "$fails FAILED" })"
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "rm -f $menuWidgets/bardroid_login_wait.lua $menuWidgets/bardroid_overgame_menu_test.lua $uiWidget files/bar/dev-springsettings.cfg $files`n")
}
