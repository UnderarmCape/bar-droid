# Every check that runs on the laptop, with a PASS/FAIL line each (about 5 minutes; BAR's Windows install is only
# read). Run after changing what they cover:
#   downloader-test      Downloader.java (install/update downloads)
#   settings-merge-test  SettingsMerge.java (springsettings.cfg at every start)
#   updater-test         Updater.launchEnded (keep or roll back a BAR update)
#   padgame-test         PadGame.java (the gamepad in BAR's game: button sequences, the mouse and keys it sends)
#   lobby-bridge-test    LobbyBridge.java against the real lobby
#   lobby-touch-test     bardroid_lobby_touch.lua in the real lobby (finger scrolling, server details first)
#   lobby-game-test      the lobby's Skirmish screen with the controller game (assets\gamepad, as installed)
#   touch-widget-test    bardroid_touch.lua in BAR's game and in the controller game (when tools\profile-gamepad-game.ps1
#                        has unpacked it)
#                        and with "Allow Custom 'Unit Control' Widgets" unticked (-NoUnitControl): the pad's actions
#   spectate-test        -QuitCheck: a replay quit in first person leaves no first-person camera for later games
#   publish-check        -SelfTest: its private-data patterns through git grep, over planted data
#   launch-bar-test.sh   launch-bar.sh's switching of BAR's build menus (the app's copy in, BAR's own back) and its
#                        low-memory mode (an 8 GB phone's settings, a 12 GB phone's untouched)
#   powershell syntax    every tools\*.ps1 parses
# The phone-side checks are separate: tools\pace-test.ps1, tools\pad-test.ps1 [-Online] (need adb).
# The games open behind the window in use and never take the keyboard (toolchain.ps1 Start-Engine); the touch widget's
# checks of what is under the pointer move the real mouse pointer and run only with -Pointer (nobody at the laptop).
#   powershell -ExecutionPolicy Bypass -File tools\laptop-tests.ps1 [-Pointer]
param([switch]$Pointer)
$Tools = $PSScriptRoot
$App = Split-Path -Parent $Tools
$results = @()

# Kailil back at the laptop: the check's engine ended at once, no further check started (tools\away-watch.ps1). Not with
# -Pointer, whose checks move the pointer themselves.
. (Join-Path $Tools "away-watch.ps1")
$backFlag = Join-Path $App "build\laptop-tests.back"
$watch = if (-not $Pointer) { Start-AwayWatch $backFlag }

function Run($name, $script, $passPattern, [string[]]$extra = @()) {
  if (Test-Path $backFlag) { $script:results += "STOP $name (Kailil is back at the laptop)"; return }
  Write-Host "== $name"
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools $script) @extra 2>&1 | ForEach-Object { "$_" }
  $ok = ($out | Select-String -Pattern $passPattern -Quiet) -and
        -not ($out | Select-String -CaseSensitive -Pattern "(^\s*|\] )FAIL\b|Error in |\] Error" -Quiet)
  if (-not $ok) { $out | Select-Object -Last 25 | ForEach-Object { Write-Host "   $_" } }
  # (a check whose engine the away watch stopped is cut off, not failed: 2026-11-02 one read as a FAIL)
  if (-not $ok -and (Test-Path $backFlag)) { $script:results += "STOP $name (cut off: Kailil came back)"; return }
  $script:results += "{0} {1}" -f $(if ($ok) { "PASS" } else { "FAIL" }), $name
}

# Lua lint (.luacheckrc): the app's widgets and the test widgets, with the toolchain's luacheck (Install
# Toolchain.bat), else LUACHECK, else one on PATH
. (Join-Path $Tools "toolchain.ps1")
$luacheck = if (Test-Path "$TC\hosttools\luacheck.exe") { "$TC\hosttools\luacheck.exe" } elseif ($env:LUACHECK) { $env:LUACHECK } else {
  (Get-Command luacheck -ErrorAction SilentlyContinue).Source
}
if ($luacheck) {
  Write-Host "== lua lint"
  Push-Location $App
  $out = & $luacheck --codes app/src/main/assets/bardroid tools 2>&1 | ForEach-Object { "$_" }
  Pop-Location
  $ok = $out | Select-String -Pattern "Total: 0 warnings / 0 errors" -Quiet
  if (-not $ok) { $out | Select-String -Pattern "\(W|\(E|Total:" | Select-Object -First 25 | ForEach-Object { Write-Host "   $_" } }
  $results += "{0} lua lint" -f $(if ($ok) { "PASS" } else { "FAIL" })
} else { $results += "SKIP lua lint (no luacheck: run Install Toolchain.bat, or set LUACHECK to luacheck.exe)" }

# Every PowerShell tool parses (2026-10-28: a "$name:" in a string stopped this file from running at all; CI checks this
# file too, .github/workflows/build.yml)
Write-Host "== powershell syntax"
$bad = foreach ($f in Get-ChildItem $Tools -Filter *.ps1) {
  $errs = $null
  [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
  if ($errs) { "$($f.Name): $($errs[0].Message) (line $($errs[0].Extent.StartLineNumber))" }
}
if ($bad) { $bad | ForEach-Object { Write-Host "   $_" } }
$results += "{0} powershell syntax" -f $(if ($bad) { "FAIL" } else { "PASS" })

# No other class calls into GameActivity: its first use on a worker thread ends the app (Paths.hiddenFlag says why)
Write-Host "== GameActivity left alone"
$bad = Get-ChildItem (Join-Path $Tools "..\app\src\main\java\com\underarmcape\bardroid") -Filter *.java |
  Where-Object { $_.Name -ne "GameActivity.java" } | Select-String -Pattern 'GameActivity\.[a-z]\w*\(' |
  Where-Object { $_.Line -notmatch '^\s*(\*|//)' }
if ($bad) { $bad | ForEach-Object { Write-Host "   $($_.Filename):$($_.LineNumber): $($_.Line.Trim())" } }
$results += "{0} GameActivity left alone" -f $(if ($bad) { "FAIL" } else { "PASS" })

# launch-bar.sh's switching of BAR's build menus (tools/launch-bar-test.sh), with the portable Git's sh and its tools
# (on PATH for this process only)
$gitUsr = Join-Path $TC "git\usr\bin"
if (Test-Path (Join-Path $gitUsr "sh.exe")) {
  Write-Host "== launch-bar build menus"
  $env:PATH = "$gitUsr;$env:PATH"
  $out = & (Join-Path $gitUsr "sh.exe") (Join-Path $Tools "launch-bar-test.sh") 2>&1 | ForEach-Object { "$_" }
  $ok = ($LASTEXITCODE -eq 0) -and ($out | Select-String -Pattern "done: ALL PASS" -Quiet)
  if (-not $ok) { $out | Select-Object -Last 25 | ForEach-Object { Write-Host "   $_" } }
  $results += "{0} launch-bar build menus" -f $(if ($ok) { "PASS" } else { "FAIL" })
} else { $results += "SKIP launch-bar build menus (no sh in ${gitUsr}: run Install Toolchain.bat)" }

Run "publish check patterns" "publish-check.ps1" "selftest: ALL PASS" @("-SelfTest")
Run "downloader" "downloader-test.ps1" "ALL PASS"
Run "springsettings merge" "settings-merge-test.ps1" "ALL PASS"
Run "updater rollback" "updater-test.ps1" "ALL PASS"
Run "gamepad in BAR's game (PadGame)" "padgame-test.ps1" "ALL PASS"
Run "lobby bridge" "lobby-bridge-test.ps1" "\[bridgetest\] done: [1-9]"
Run "lobby touch" "lobby-touch-test.ps1" "\[lobbytouch\] done: ALL PASS"
Run "lobby Skirmish, controller game" "lobby-game-test.ps1" "\[lobbygame\] done: ALL PASS"
$pointerArg = @(if ($Pointer) { "-Pointer" })
Run "touch widget, BAR" "touch-widget-test.ps1" "\[touchtest\] done: ALL PASS" $pointerArg
if (Test-Path (Join-Path $App "build\profile\data\games\BAR-gamepad.sdd\modinfo.lua")) {
  Run "touch widget, controller game" "touch-widget-test.ps1" "\[touchtest\] done: ALL PASS" (@("-GamepadGame") + $pointerArg)
} else { $results += "SKIP touch widget, controller game (run tools\profile-gamepad-game.ps1 once)" }
Run "quit in first person" "spectate-test.ps1" "\[spectest\] done: ALL PASS" @("-QuitCheck")
Run "pad with unit control widgets off" "touch-widget-test.ps1" "\[touchtest\] done: ALL PASS" @("-NoUnitControl", "-TestWidget", (Join-Path $Tools "touch-widget-test\bardroid_rule_off_test.lua"))

Stop-AwayWatch $watch
if (Test-Path $backFlag) { $results += "STOPPED: Kailil came back to the laptop; the checks after that did not run" }
Write-Host ""
$results | ForEach-Object { Write-Host $_ }
if ($results -match "^(FAIL|STOP)") { exit 1 }
