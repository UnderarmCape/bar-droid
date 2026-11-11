# trapbench in the dev phone's container (docs/CONTAINER-COST.md): microseconds per system call that proot stops
# against one it lets through, three rounds. Take the dev phone first (devphone-lock.ps1); needs an installed app.
#   trapbench.ps1 [-Count 20000]
param([int]$Count = 20000, [string]$Device = "")
. (Join-Path (Split-Path $PSScriptRoot) "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }   # (the dev phone: ..\phone-device.txt, outside the repository)
$bin = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "build\container-cost\trapbench"
Send-AppFile $adb $bin "files/bar/bd-trapbench" $Device
$f = Join-Path $TC "tmp\cc-trap.sh"
$sh = "chmod 755 files/bar/bd-trapbench; for i in 1 2 3; do sh files/container.sh '/root/bar/bd-trapbench $Count'; done; echo '--- outside proot'; files/bar/bd-trapbench $Count; rm -f files/bar/bd-trapbench`n"
[IO.File]::WriteAllText($f, $sh, (New-Object Text.ASCIIEncoding))
Invoke-AppScript $adb $f $Device
