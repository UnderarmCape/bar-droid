# The app's X server's listeners on the dev phone (tools/x11-probe/x11-probe.pl, run in the app's container with its
# perl): which socket names take a client, and whether the X setup is accepted with no authorization. The X server
# must be up: run it while a game runs (any phone test), or with the launcher's GL check held. Expected since
# 2026-11-21: the abstract names "no listener", the path socket (in the app's own folder) "accepted".
#   powershell -ExecutionPolicy Bypass -File tools\x11-probe.ps1      (ANDROID_SERIAL names another phone)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
$tmp = Join-Path $TC "tmp"
New-Item -ItemType Directory -Force $tmp | Out-Null
$pl = Join-Path $tmp "x11-probe.pl"
[IO.File]::WriteAllText($pl, ((Get-Content (Join-Path $PSScriptRoot "x11-probe\x11-probe.pl") -Raw) -replace "`r`n", "`n"))
$run = Join-Path $tmp "x11-probe-run.sh"
[IO.File]::WriteAllText($run, "pidof bardroid-x11 >/dev/null || echo '[x11probe] the X server is not running'`nsh files/container.sh 'perl /root/bar/.x11-probe.pl'`nrm -f files/bar/.x11-probe.pl`n")
try {
  Send-AppFile $adb $pl "files/bar/.x11-probe.pl" $env:ANDROID_SERIAL
  Invoke-AppScript $adb $run $env:ANDROID_SERIAL
} finally {
  Remove-Item -Force $pl, $run -ErrorAction SilentlyContinue
}
