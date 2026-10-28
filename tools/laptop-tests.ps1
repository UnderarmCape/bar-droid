# Every check that runs on the laptop, with a PASS/FAIL line each (about 5 minutes; BAR's Windows install is only
# read). Run after changing what they cover:
#   downloader-test      Downloader.java (install/update downloads)
#   settings-merge-test  SettingsMerge.java (springsettings.cfg at every start)
#   updater-test         Updater.launchEnded (keep or roll back a BAR update)
#   mouse-keyboard-test  CtrlAltRelease.java (a lone Ctrl+Alt gives the captured mouse back to Android)
#   lobby-bridge-test    LobbyBridge.java against the real lobby
#   lobby-touch-test     bardroid_lobby_touch.lua in the real lobby (finger scrolling, server details first)
#   lobby-game-test      the lobby's Skirmish screen with the controller game (assets\gamepad, as installed)
#   touch-widget-test    bardroid_touch.lua in BAR's game and in the controller game (when tools\profile-gamepad-game.ps1
#                        has unpacked it)
# The phone-side checks are separate: tools\pace-test.ps1 (needs adb).
#   powershell -ExecutionPolicy Bypass -File tools\laptop-tests.ps1
$Tools = $PSScriptRoot
$App = Split-Path -Parent $Tools
$results = @()

function Run($name, $script, $passPattern, [string[]]$extra = @()) {
  Write-Host "== $name"
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools $script) @extra 2>&1 | ForEach-Object { "$_" }
  $ok = ($out | Select-String -Pattern $passPattern -Quiet) -and
        -not ($out | Select-String -CaseSensitive -Pattern "(^\s*|\] )FAIL\b|Error in |\] Error" -Quiet)
  if (-not $ok) { $out | Select-Object -Last 25 | ForEach-Object { Write-Host "   $_" } }
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

Run "downloader" "downloader-test.ps1" "ALL PASS"
Run "springsettings merge" "settings-merge-test.ps1" "ALL PASS"
Run "updater rollback" "updater-test.ps1" "ALL PASS"
Run "mouse release (Ctrl+Alt)" "mouse-keyboard-test.ps1" "ALL PASS"
Run "lobby bridge" "lobby-bridge-test.ps1" "\[bridgetest\] done: [1-9]"
Run "lobby touch" "lobby-touch-test.ps1" "\[lobbytouch\] done: ALL PASS"
Run "lobby Skirmish, controller game" "lobby-game-test.ps1" "\[lobbygame\] done: ALL PASS"
Run "touch widget, BAR" "touch-widget-test.ps1" "\[touchtest\] done: ALL PASS"
if (Test-Path (Join-Path $App "build\profile\data\games\BAR-gamepad.sdd\modinfo.lua")) {
  Run "touch widget, controller game" "touch-widget-test.ps1" "\[touchtest\] done: ALL PASS" @("-GamepadGame")
} else { $results += "SKIP touch widget, controller game (run tools\profile-gamepad-game.ps1 once)" }

Write-Host ""
$results | ForEach-Object { Write-Host $_ }
if ($results -match "^FAIL") { exit 1 }
