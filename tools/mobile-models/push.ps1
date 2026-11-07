# The mobile models onto a phone (engine branch: BarDroidModelOverrideDir = bardroid-models): mobile_models' output
# folder (its objects3d/) packed, pushed and unpacked into the app's files/bar/bardroid-models, replacing what was there.
#   push.ps1 [-Models C:\Tools\BARANDROID\engine-sim\mobile-models\out] [-Device R5CW22GVC3D] [-Remove]
# -Remove: deletes files/bar/bardroid-models (BAR's own models drawn again, also with the setting on).
param([string]$Models = "C:\Tools\BARANDROID\engine-sim\mobile-models\out", [string]$Device = "R5CW22GVC3D", [switch]$Remove)
$ErrorActionPreference = "Stop"
$tools = Split-Path $PSScriptRoot
. (Join-Path $tools "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
$pkg = "com.underarmcape.bardroid"
if ($Remove) {
  & $adb -s $Device exec-out run-as $pkg sh -c "rm -rf files/bar/bardroid-models; echo removed"
  return
}
if (-not (Test-Path (Join-Path $Models "objects3d"))) { throw "no objects3d in $Models" }
$tar = Join-Path $TC "tmp\bardroid-models.tar"
if (Test-Path $tar) { Remove-Item $tar -Force }
& "$env:SystemRoot\System32\tar.exe" -cf $tar -C $Models objects3d
if ($LASTEXITCODE) { throw "tar failed" }
$remoteTar = "/data/local/tmp/bardroid-models.tar"
$ErrorActionPreference = "Continue"   # (adb push's progress on stderr)
& $adb -s $Device push $tar $remoteTar 2>&1 | Select-Object -Last 1
& $adb -s $Device shell chmod 644 $remoteTar
$ErrorActionPreference = "Stop"
$out = & $adb -s $Device exec-out run-as $pkg sh -c "rm -rf files/bar/bardroid-models.new && mkdir -p files/bar/bardroid-models.new && tar -xf $remoteTar -C files/bar/bardroid-models.new && rm -rf files/bar/bardroid-models && mv files/bar/bardroid-models.new files/bar/bardroid-models && find files/bar/bardroid-models -name '*.s3o' | wc -l"
& $adb -s $Device shell rm -f $remoteTar
Remove-Item $tar -Force
"$Device : $("$out".Trim()) mobile models in files/bar/bardroid-models"
