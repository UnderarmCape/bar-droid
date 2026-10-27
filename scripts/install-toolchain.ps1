# Portable toolchain for BAR Droid: Temurin JDK 21, MinGit, Android SDK (cmdline-tools, platform 34,
# build-tools 34, NDK 29.0.14206865, CMake 3.22.1, platform-tools). Run through "Install Toolchain.bat",
# which sets the process-local environment (env.bat) first. Re-running skips what is already there.
param([switch]$AcceptAndroidLicenses)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$TC = $env:TC
if (-not $TC) { throw "Run this through 'Install Toolchain.bat' (env.bat sets TC)." }
$Dl = Join-Path $TC "downloads"

function Get-File($Url, $Name) {
    $out = Join-Path $Dl $Name
    if (Test-Path $out) { return $out }
    Write-Host "  downloading $Name"
    & curl.exe -L --fail --retry 3 -C - -o "$out.part" $Url
    if ($LASTEXITCODE -ne 0) { throw "download failed: $Url" }
    Move-Item "$out.part" $out
    return $out
}

# Extracts a zip whose single top-level folder becomes $Dest.
function Expand-Single($Zip, $Dest) {
    $tmp = "$Dest.extract"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory $tmp | Out-Null
    & tar.exe -xf $Zip -C $tmp
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $Zip" }
    $top = Get-ChildItem $tmp
    $src = if ($top.Count -eq 1 -and $top[0].PSIsContainer) { $top[0].FullName } else { $tmp }
    Move-Item $src $Dest
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
}

# 1. JDK (Temurin 21, zip build: no installer, no registry)
if (-not (Test-Path "$TC\jdk\bin\java.exe")) {
    Write-Host "[1/5] JDK 21"
    $zip = Get-File "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse" "temurin21-jdk.zip"
    Expand-Single $zip "$TC\jdk"
} else { Write-Host "[1/5] JDK present" }

# 2. MinGit (portable Git for Windows, no installer)
if (-not (Test-Path "$TC\git\cmd\git.exe")) {
    Write-Host "[2/5] MinGit"
    $rel = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $asset = $rel.assets | Where-Object name -match '^MinGit-[\d.]+-64-bit\.zip$' | Select-Object -First 1
    $zip = Get-File $asset.browser_download_url $asset.name
    New-Item -ItemType Directory "$TC\git" | Out-Null
    & tar.exe -xf $zip -C "$TC\git"
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $zip" }
} else { Write-Host "[2/5] Git present" }

# 3. Android cmdline-tools -> android-sdk\cmdline-tools\latest
$sdk = $env:ANDROID_HOME
if (-not (Test-Path "$sdk\cmdline-tools\latest\bin\sdkmanager.bat")) {
    Write-Host "[3/5] Android cmdline-tools"
    $repo = [xml](Invoke-WebRequest -UseBasicParsing "https://dl.google.com/android/repository/repository2-3.xml").Content
    $pkg = $repo.'sdk-repository'.remotePackage | Where-Object path -eq 'cmdline-tools;latest'
    $name = ($pkg.archives.archive | Where-Object { $_.'host-os' -eq 'windows' }).complete.url
    $zip = Get-File "https://dl.google.com/android/repository/$name" $name
    New-Item -ItemType Directory "$sdk\cmdline-tools" -Force | Out-Null
    Expand-Single $zip "$sdk\cmdline-tools\latest"
} else { Write-Host "[3/5] cmdline-tools present" }

# 4. SDK packages via the Android CLI (android.exe replaced sdkmanager in 2026; package names use '/').
#    Installing implies the Android SDK terms (https://developer.android.com/studio/terms).
Write-Host "[4/5] Android SDK packages"
if (-not $AcceptAndroidLicenses -and -not (Test-Path "$sdk\ndk\29.0.14206865")) {
    Write-Host ""
    Write-Host "  Installing the SDK means accepting the Android SDK terms: https://developer.android.com/studio/terms"
    Write-Host "  To accept and continue, run:  `"Install Toolchain.bat`" --accept-licenses"
    exit 2
}
$cli = "$sdk\cmdline-tools\latest\bin\android.exe"
$have = (Test-Path "$sdk\platforms\android-34") -and (Test-Path "$sdk\build-tools\34.0.0") -and (Test-Path "$sdk\ndk\29.0.14206865") -and (Test-Path "$sdk\cmake\3.22.1") -and (Test-Path "$sdk\platform-tools\adb.exe")
if (-not $have) { & $cli --no-metrics "--sdk=$sdk" sdk install platform-tools platforms/android-34 build-tools/34.0.0 ndk/29.0.14206865 cmake/3.22.1
if ($LASTEXITCODE -ne 0) { throw "android sdk install failed" } }

# 5. Host tools the X server's native build expects from a Linux box: Python 3 (libepoxy codegen),
#    bison (xkbcomp parser) and a host gcc (libX11's makekeys). All portable zips. Plus luacheck for the checks.
Write-Host "[5/5] Host build tools (Python, bison, gcc, luacheck)"
$ht = "$TC\hosttools"
New-Item -ItemType Directory $ht -Force | Out-Null
if (-not (Test-Path "$ht\python\python.exe")) {
    $zip = Get-File "https://www.python.org/ftp/python/3.14.9/python-3.14.9-embed-amd64.zip" "python-3.14.9-embed-amd64.zip"
    New-Item -ItemType Directory "$ht\python" | Out-Null
    & tar.exe -xf $zip -C "$ht\python"
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $zip" }
}
if (-not (Test-Path "$ht\winflexbison\win_bison.exe")) {
    $zip = Get-File "https://github.com/lexxmark/winflexbison/releases/download/v2.5.25/win_flex_bison-2.5.25.zip" "win_flex_bison-2.5.25.zip"
    New-Item -ItemType Directory "$ht\winflexbison" | Out-Null
    & tar.exe -xf $zip -C "$ht\winflexbison"
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $zip" }
}
if (-not (Test-Path "$ht\w64devkit\bin\gcc.exe")) {
    # A 7-Zip self-extractor; Windows' tar (libarchive) reads it without running it.
    $sfx = Get-File "https://github.com/skeeto/w64devkit/releases/download/v2.10.1/w64devkit-x64-2.10.1.7z.exe" "w64devkit-x64-2.10.1.7z.exe"
    & tar.exe -xf $sfx -C $ht
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $sfx" }
}
# luacheck for the Lua lint step of tools\laptop-tests.ps1 (.luacheckrc); one self-contained exe
if (-not (Test-Path "$ht\luacheck.exe")) {
    $exe = Get-File "https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe" "luacheck-1.2.0.exe"
    if ((Get-FileHash $exe -Algorithm SHA256).Hash -ne "0F1C69C4D09F1EBB4D8DF14C215E4553E2E639BD4CB7BF3C639B0DAA6198317B") {
        Remove-Item $exe; throw "luacheck-1.2.0.exe: unexpected SHA-256"
    }
    Copy-Item $exe "$ht\luacheck.exe"
}
Write-Host ""
Write-Host "Toolchain ready in $TC"
