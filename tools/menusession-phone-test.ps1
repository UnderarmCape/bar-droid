# Two games of one lobby session on the dev phone (RC 0.2.0 item 7, release overhaul item 36): the lobby offline
# (tools\lobby-login\bardroid_login_wait.lua: the tests never log in); its test widget
# (tools\menusession-phone-test\bardroid_menusession_menu_test.lua) starts a skirmish (the phone's skirmish.txt) through
# the lobby's own start (Chobby's StartGameFromString: Spring.Reload in the same engine, launch-bar.sh not run again);
# in it the game's test widget (bardroid_menusession_ui_test.lua) picks the commander, sees the app's build menu copy,
# breaks it on purpose (droidBreak) and sees BAR's own in its place (bardroid_touch.lua's menu watch); back to the lobby
# (Spring.Reload(""), as BAR's Leave); a second game started the same way: BAR's own build menu from the start,
# showing the commander's options, the copy not back. Pictures build\menusession-game1.png, -game2.png.
# Sideways for the run ("Play upright" off, "Turn with the phone" off: BAR's build menu at its place), both put back;
# BAR's widget settings (LuaUI/Config/BYAR.lua) put back as they were, the session's infolog removed (it names the copy
# as removed: launch-bar.sh's next start would give the copy's place to BAR's own). Nothing on the laptop. ~5 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\menusession-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$menuWidgets = "files/bar/LuaMenu/Widgets"
$uiWidget = "files/bar/LuaUI/Widgets/bardroid_menusession_ui_test.lua"
$cfg = "files/bar/LuaUI/Config"
$build = Join-Path (Split-Path $PSScriptRoot) "build"
$files = "$cfg/bardroid_menusession_state.txt $cfg/bardroid_menusession_ui.txt $cfg/bardroid_menusession_ui_cmd.txt"
$mark = "files/bar/.bardroid-buildmenu-failed"

function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }
function AppScript([string]$text) {
  $f = Join-Path $TC "tmp\menusessiontest.sh"
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
$markWas = "$(InApp "test -f $mark && echo yes")".Trim() -eq "yes"
AppScript ((Pref "portrait" $false) + (Pref "turnWithPhone" $false) +
  "rm -f files/bar/infolog.txt $files`n" +
  "[ -f $cfg/BYAR.lua ] && cp -f $cfg/BYAR.lua $cfg/BYAR.lua.menusession.bak`n" +
  "echo 'LogFlushLevel = 0' > files/bar/dev-springsettings.cfg`n")
Send-AppFile $adb (Join-Path $PSScriptRoot "lobby-login\bardroid_login_wait.lua") "$menuWidgets/bardroid_login_wait.lua"
Send-AppFile $adb (Join-Path $PSScriptRoot "menusession-phone-test\bardroid_menusession_menu_test.lua") "$menuWidgets/bardroid_menusession_menu_test.lua"
Send-AppFile $adb (Join-Path $PSScriptRoot "menusession-phone-test\bardroid_menusession_ui_test.lua") $uiWidget
# (the lines as they come, each once with its time: the engine of a session keeps one infolog, a Reload may start it again)
$raw = New-Object System.Collections.Generic.List[string]
function Collect {
  foreach ($l in @(InApp "grep -a -E '\[menusession\]|\[lobbylogin\]|\[bardroid-touch\] the app.s build menu|Removed widget: BAR Droid build menu|bardroid_menusession.*[Ee]rror' files/bar/infolog.txt 2>/dev/null")) {
    $s = "$l"
    if ($s -and -not $raw.Contains($s)) { $raw.Add($s) }
  }
}
try {
  Set-PhoneAwake $adb
  & $adb shell am start -n "$pkg/.StartActivity" | Out-Null   # (the app icon: the lobby)
  $until = (Get-Date).AddMinutes(9); $seen = @{}   # (each game's widget counts its own pictures from 1)
  while ((Get-Date) -lt $until) {
    $line = "$(InApp "cat $cfg/bardroid_menusession_ui.txt 2>/dev/null")".Trim()
    if ($line -match '^shot (\d+) (game\d)' -and [int]$Matches[1] -gt [int]$seen[$Matches[2]]) {
      $n = [int]$Matches[1]; $g = $Matches[2]; $png = Join-Path $build "menusession-$g.png"
      & $adb shell screencap -p /sdcard/bardroid-menusessionshot.png
      $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (adb pull's progress line on stderr)
      try { $null = & $adb pull /sdcard/bardroid-menusessionshot.png $png 2>&1 } finally { $ErrorActionPreference = $eap }
      & $adb shell rm -f /sdcard/bardroid-menusessionshot.png
      "[menusession] (a picture: $png)"
      InApp "echo $n > $cfg/bardroid_menusession_ui_cmd.txt"
      $seen[$g] = $n
    }
    Collect
    if ($line -eq "game2 checked" -or $line -eq "end") { break }
    Start-Sleep -Milliseconds 500
  }
  Start-Sleep 2; Collect
  $lines = @($raw | ForEach-Object { $_ -replace '^\[t=[^\]]+\]\[f=[^\]]+\] ', '' })
  $lines
  $watch = @($lines | Where-Object { $_ -match '\[bardroid-touch\] the app.s build menu' }).Count
  # (game 2 is looked at past frame 90, when the menu watch would already have switched BAR's own on had the session
  # lost it: a second watch line is that rescue, not BAR's own from the start; vacuous-pass audit, 2026-11-23)
  $rescued = $watch -ne 1
  "[menusession] $(if ($rescued) { 'FAIL' } else { 'PASS' }) the menu watch acted in game 1 alone: $watch times in the session"
  $unfinished = -not ($lines | Where-Object { $_ -match '\[menusession\] game2 done' })
  if ($unfinished) { "[menusession] FAIL the test did not finish (both games)" }
  $fails = @($lines | Where-Object { $_ -match '\[menusession\] FAIL' }).Count + [int]$unfinished + [int]$rescued
  "[menusession] done: $(if ($fails -eq 0) { 'ALL PASS' } else { "$fails FAILED" })"
} finally {
  & $adb shell am force-stop $pkg
  AppScript ((Pref "portrait" $portraitWas) + (Pref "turnWithPhone" $turnWas) +
    "rm -f $menuWidgets/bardroid_login_wait.lua $menuWidgets/bardroid_menusession_menu_test.lua $uiWidget files/bar/dev-springsettings.cfg $files files/bar/infolog.txt`n" +
    "[ -f $cfg/BYAR.lua.menusession.bak ] && mv -f $cfg/BYAR.lua.menusession.bak $cfg/BYAR.lua`n" +
    $(if (-not $markWas) { "rm -f $mark`n" } else { "" }) + "true`n")
}
