# Every check that runs on the laptop, with a PASS/FAIL line each (about 5 minutes; BAR's Windows install is only
# read). Run after changing what they cover:
#   downloader-test      Downloader.java (install/update downloads)
#   settings-merge-test  SettingsMerge.java (springsettings.cfg at every start)
#   lobby-bridge-test    LobbyBridge.java against the real lobby
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
  $ok = ($out | Select-String -Pattern $passPattern -Quiet) -and -not ($out | Select-String -Pattern "FAIL|Error in |\] Error" -Quiet)
  if (-not $ok) { $out | Select-Object -Last 25 | ForEach-Object { Write-Host "   $_" } }
  $script:results += "{0} {1}" -f $(if ($ok) { "PASS" } else { "FAIL" }), $name
}

Run "downloader" "downloader-test.ps1" "ALL PASS"
Run "springsettings merge" "settings-merge-test.ps1" "ALL PASS"
Run "lobby bridge" "lobby-bridge-test.ps1" "\[bridgetest\] done: [1-9]"
Run "touch widget, BAR" "touch-widget-test.ps1" "\[touchtest\] done: ALL PASS"
if (Test-Path (Join-Path $App "build\profile\data\games\BAR-gamepad.sdd\modinfo.lua")) {
  Run "touch widget, controller game" "touch-widget-test.ps1" "\[touchtest\] done: ALL PASS" @("-GamepadGame")
} else { $results += "SKIP touch widget, controller game (run tools\profile-gamepad-game.ps1 once)" }

Write-Host ""
$results | ForEach-Object { Write-Host $_ }
if ($results -match "^FAIL") { exit 1 }
