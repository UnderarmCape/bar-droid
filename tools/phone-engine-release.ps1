# The phone engine for the APK (docs/ENGINE-DEFAULT.md): an engine branch build put where build.gradle takes it.
#   phone-engine-release.ps1 [-Build gcc-combined] [-Version <engine>] [-Source <checkout>] [-Out <folder>]
# -Build: C:\Tools\BARANDROID\engine-sim\out\<Build>\spring (bar-droid-engine tools\engine-sim\build-engine.ps1);
# -Version: the engine version it was built for (default: Prefs.engineVersion); -Source: the checkout it was built
# from (its commit goes into BUILD.txt; refused with uncommitted changes under rts/); -Out: the folder that
# local.properties bardroid.phoneEngine names (default C:\Tools\BARANDROID\engine-sim\release).
# Writes <Out>\phone-engine\<Version>\spring and BUILD.txt, whose first line is the build's name: Installer and
# launch-bar.sh compare it (a new name: copied again, its first start watched).
param([string]$Build = "gcc-combined", [string]$Version = "", [string]$Source = "C:\Tools\BARANDROID\hailmary-work\recoil-combined",
      [string]$Out = "C:\Tools\BARANDROID\engine-sim\release")
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot
if (-not $Version) {
  $m = Select-String -Path "$root\app\src\main\java\com\underarmcape\bardroid\Prefs.java" -Pattern 'engineVersion = "([^"]+)"' | Select-Object -First 1
  $Version = $m.Matches[0].Groups[1].Value
}
$bin = "C:\Tools\BARANDROID\engine-sim\out\$Build\spring"
if (-not (Test-Path $bin)) { throw "no build: $bin" }
$git = "C:\Tools\BARANDROID\toolchain\git\cmd\git.exe"
$commit = (& $git -C $Source rev-parse --short HEAD).Trim()
$branch = (& $git -C $Source rev-parse --abbrev-ref HEAD).Trim()
$dirty = & $git -C $Source status --porcelain -- rts
if ($dirty) { throw "uncommitted changes under $Source\rts: commit them first (BUILD.txt names a commit)" }
$when = (& $git -C $Source log -1 --format=%cs).Trim()
$dir = "$Out\phone-engine\$Version"
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item $bin "$dir\spring" -Force
$sha = (Get-FileHash "$dir\spring" -Algorithm SHA256).Hash.ToLower()
$lines = @(
  "phone-$Version-$commit",
  "Recoil $Version with the BAR Droid engine branch: $branch $commit ($when)",
  "built as $Build, $([int]((Get-Item "$dir\spring").Length / 1MB)) MB, sha256 $sha",
  "source: RecoilEngine $Version + the branch (GPL-2.0-or-later; docs/ENGINE-DEFAULT.md, NOTICE.md)"
)
[IO.File]::WriteAllText("$dir\BUILD.txt", (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
"phone engine $Version : $($lines[0]) -> $dir"
