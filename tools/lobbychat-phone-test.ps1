# The lobby's keyboard and speak to chat (bardroid_lobby_touch.lua textBoxAsk, RtsTouch lobbyAskStep; 2026-11-19's
# system) upright on the dev phone, by real taps, in the offline lobby (tools\lobby-login\bardroid_login_wait.lua: the
# tests never log in): the test widget (tools\lobbychat-phone-test\bardroid_lobbychat_test.lua) opens Chobby's skirmish
# room and asks for a tap on its chat box (the keyboard asked and shown), "hello" typed, Back (the keyboard down), a
# long press on the box (speak to chat asked, its panel saying the microphone is denied). Never a live microphone
# (memory: the dev phone travels with Kailil): the run stops at once if the app holds the microphone permission.
# "do <n> tap|hold|shot|ime|type|key x y vsx [text|key]", answered "<n> [answer]"; pictures build\lobbychat-<n>.png.
# "Play upright" on for the run, "Turn with the phone" off, both put back after. Nothing on the laptop. About 1.5 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\lobbychat-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$menuWidgets = "files/bar/LuaMenu/Widgets"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"
$files = "$cfg/bardroid_lobbychat.txt $cfg/bardroid_lobbychat_cmd.txt"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function Log([string]$pattern, [int]$lines) { InApp "grep -a -E '$pattern' files/bar/infolog.txt 2>/dev/null | tail -$lines" }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\lobbychattest.sh"
  New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
  [IO.File]::WriteAllText($f, $text.Replace("`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f
}
function Pref([string]$name, [bool]$on) {
  "sed -i -E 's/name=.$name. value=.(true|false)./name=`"$name`" value=`"$(if ($on) { 'true' } else { 'false' })`"/' shared_prefs/bardroid.xml`n"
}
function ImeShown {
  $lines = @(& $adb shell dumpsys input_method | Select-String -Pattern '(?i)\bmInputShown=')
  return [bool](($lines -join "`n") -match '(?i)\bmInputShown=true')
}

# (never a live microphone: speak to chat is checked only with the app's microphone permission denied)
$mic = (& $adb shell dumpsys package $pkg) -join "`n"
if ($mic -match 'android\.permission\.RECORD_AUDIO: granted=true') {
  "[lobbychat] the app holds the microphone permission on this phone: not run (speak to chat would listen)"
  exit 1
}
& $adb shell am force-stop $pkg
$prefs = "$(InApp "cat shared_prefs/bardroid.xml")"
$portraitWas = $prefs -match 'name=.portrait. value=.true.'
$turnWas = $prefs -match 'name=.turnWithPhone. value=.true.'
AppScript ((Pref "portrait" $true) + (Pref "turnWithPhone" $false) +
  "rm -f files/bar/infolog.txt $files`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua") "$menuWidgets/bardroid_login_wait.lua"
Send-AppFile $adb (Join-Path $PSScriptRoot "lobbychat-phone-test\bardroid_lobbychat_test.lua") "$menuWidgets/bardroid_lobbychat_test.lua"
& $adb logcat -c
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.StartActivity" | Out-Null   # (the app icon: the lobby)
  $size = (& $adb shell wm size) -join " "
  $w = [double][regex]::Match($size, '(\d+)x(\d+)\s*$').Groups[1].Value
  $until = (Get-Date).AddMinutes(5); $seen = 0
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_lobbychat.txt 2>/dev/null")".Trim()
    if ($line -eq "end") { break }
    if ($line -match '^do (\d+) (tap|hold|shot|ime|type|key) (-?\d+) (-?\d+) (\d+)(?: (\S+))?' -and [int]$Matches[1] -gt $seen) {
      $n = [int]$Matches[1]; $act = $Matches[2]; $arg = $Matches[6]
      $k = $w / [double]$Matches[5]
      $x = [int]([double]$Matches[3] * $k); $y = [int]([double]$Matches[4] * $k)
      $reply = "$n"
      switch ($act) {
        "shot" {
          & $adb shell screencap -p /sdcard/bardroid-lobbychatshot.png
          $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
          try { $null = & $adb pull /sdcard/bardroid-lobbychatshot.png (Join-Path $build "lobbychat-$n.png") 2>&1 }
          finally { $ErrorActionPreference = $eap }
          & $adb shell rm -f /sdcard/bardroid-lobbychatshot.png
          "[lobbychat] ($($n): a picture, build\lobbychat-$n.png)"
        }
        "ime" {
          Start-Sleep -Milliseconds 1200   # (the keyboard's slide)
          $on = ImeShown
          $reply = "$n $(if ($on) { 1 } else { 0 })"
          "[lobbychat] ($($n): Android's keyboard $(if ($on) { 'shown' } else { 'not shown' }))"
        }
        "type" { & $adb shell input text $arg; "[lobbychat] ($($n): typed $arg)" }
        "key" { & $adb shell input keyevent $arg; "[lobbychat] ($($n): key $arg)" }
        "hold" { & $adb shell input swipe $x $y $x $y 900; "[lobbychat] ($($n): held at $x,$y)" }
        default { & $adb shell input tap $x $y; "[lobbychat] ($($n): a tap at $x,$y)" }
      }
      InApp "echo $reply > $cfg/bardroid_lobbychat_cmd.txt"
      $seen = $n
    }
    Start-Sleep -Milliseconds 300
  }
  if (-not (Log '\[lobbychat\] done' 1)) { Start-Sleep 3 }
  if (-not (Log '\[lobbychat\] done' 1)) { "[lobbychat] FAIL the test did not finish" }
  Log '\[lobbychat\]|\[bardroid-lobby\] a text box|bardroid_lobby.*[Ee]rror|Error in' 30 |
    ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' }
  $app = @(& $adb logcat -d | Select-String "lobby text box tapped|lobby chat box held")
  "[lobbychat] (the app's log: $(($app | ForEach-Object { ($_ -split ': ', 2)[-1] }) -join '; '))"
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "rm -f $menuWidgets/bardroid_login_wait.lua $menuWidgets/bardroid_lobbychat_test.lua files/bar/dev-springsettings.cfg $files`n")
}
