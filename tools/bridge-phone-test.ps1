# The lobby bridge (LobbyBridge, BridgeRules) against another app on the dev phone: the bridge listens on 127.0.0.1 and
# Android cannot say which app connects (the release audit, 2026-11-21). The lobby started as the app icon does; then,
# through adb's port forward (adbd's own user, as another app would be), tools\bridge-phone-test\bridge_client.py asks
# for a widget written into LuaUI/Widgets, a dev-env.sh, a replay read from outside demos/ and a third connection (all
# refused), and the plugin manifest the lobby itself downloads (allowed). Anything it made is deleted after. Needs the
# phone's network for the manifest. Nothing on the laptop runs BAR. About 1.5 minutes.
#   powershell -ExecutionPolicy Bypass -File tools\bridge-phone-test.ps1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
if (-not $env:ANDROID_SERIAL) { throw "No phone: connect one over adb, or name it (ANDROID_SERIAL, BARDROID_DEVICE, phone-device.txt)" }
$pkg = "com.underarmcape.bardroid"
$py = (Get-ChildItem $TC -Recurse -Filter python.exe -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
function InApp([string]$command) { & $adb exec-out run-as $pkg sh -c $command }

$fails = 0
$local = 28911
& $adb shell am force-stop $pkg
InApp "rm -f files/bar/sl-connection.json"
try {
  Set-PhoneAwake $adb
  $logLines = [int]"$(InApp 'wc -l < files/logs/launcher.log 2>/dev/null')".Trim()
  & $adb shell am start -n "$pkg/.StartActivity" | Out-Null   # (the app icon: the lobby, the bridge with it)
  $port = $null; $until = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $until -and -not $port) {
    $m = [regex]::Match("$(InApp 'cat files/bar/sl-connection.json 2>/dev/null')", '"_sl_port":\s*(\d+)')
    if ($m.Success) { $port = $m.Groups[1].Value } else { Start-Sleep -Milliseconds 700 }
  }
  if (-not $port) { throw "no sl-connection.json: the lobby bridge did not start" }
  # (the lobby's own connection first: the client then is the second, and a third the one over the limit)
  $until = (Get-Date).AddSeconds(60)
  while ((Get-Date) -lt $until -and -not ("$(InApp "tail -n +$($logLines + 1) files/logs/launcher.log")" -match 'lobby connected')) { Start-Sleep 1 }
  & $adb forward "tcp:$local" "tcp:$port" | Out-Null
  $out = @(& $py -I (Join-Path $PSScriptRoot "bridge-phone-test\bridge_client.py") $local)
  $r = @{}; foreach ($l in $out) { $p = "$l".Split(' ', 2); if ($p.Count -eq 2) { $r[$p[0]] = $p[1].Trim() } }
  $evil = "$(InApp 'ls files/bar/LuaUI/Widgets/bardroid_bridge_evil.lua files/bar/dev-env.sh 2>/dev/null')".Trim()
  # (the longest of the bridge's last 40 "not JSON" lines, this run's: the client's 200 KB lines are clipped before they
  # are logged; across launcher.old.log too, as 40 such lines whole rotated the log at the next start)
  $sh = Join-Path $TC "tmp\bridge-longest-line.sh"
  [IO.File]::WriteAllText($sh, "cat files/logs/launcher.old.log files/logs/launcher.log 2>/dev/null | grep -a -e 'not JSON' | tail -n 40 | awk '{ if (length(`$0) > m) m = length(`$0) } END { print m + 0 }'`n", (New-Object Text.ASCIIEncoding))
  $longest = [int]("$(Invoke-AppScript $adb $sh)".Trim() + "")
  $cases = @(
    @("a widget into LuaUI/Widgets: refused, no file", ($r.widget -eq "failed" -and $evil -notmatch 'evil'), $r.widget),
    @("a dev-env.sh: refused, no file", ($r.devenv -eq "failed" -and $evil -notmatch 'dev-env'), $r.devenv),
    @("a replay from outside demos/: no answer", ($r.replay -eq "no answer"), $r.replay),
    @("a third connection: closed", ($r.third -eq "closed"), $r.third),
    @("the plugin manifest the lobby downloads: allowed", ($r.manifest -eq "success"), $r.manifest),
    @("40 lines of 200 KB from another app: logged clipped", ($longest -gt 0 -and $longest -lt 2000), "$longest characters"),
    @("a message nested 100,000 deep: the app lives, a new connection's download answered", ($r.afterdeep -eq "success"), $r.afterdeep))
  foreach ($c in $cases) {
    if ($c[1]) { "[bridgetest] PASS $($c[0]) ($($c[2]))" } else { "[bridgetest] FAIL $($c[0]) ($($c[2]); files: '$evil')"; $fails++ }
  }
  InApp "tail -n +$($logLines + 1) files/logs/launcher.log" | Select-String -Pattern 'refused' | Select-Object -First 6 |
    ForEach-Object { "[bridgetest] (log: $("$_".Trim()))" }
  "[bridgetest] done: $(if ($fails -eq 0) { 'ALL PASS' } else { "$fails FAILED" })"
} finally {
  & $adb forward --remove "tcp:$local" 2>$null | Out-Null
  & $adb shell am force-stop $pkg
  InApp "rm -f files/bar/LuaUI/Widgets/bardroid_bridge_evil.lua files/bar/LuaUI/Widgets/bardroid_bridge_evil.lua.part files/bar/dev-env.sh"
}
