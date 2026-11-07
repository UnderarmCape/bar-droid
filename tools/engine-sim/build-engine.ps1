# One engine build of the engine branch (docs/ENGINE-SIM.md): build-engine.ps1 <name> [extra cmake -D...]
#   $env:ES_FLAGS / $env:ES_LDFLAGS: extra compile / link flags (never fast-math or FP contraction: sync)
# Source: hailmary-work\recoil-src (branch bardroid/sim). Build dir and output outside every repository:
#   C:\Tools\BARANDROID\engine-sim\build-<name>, ...\out\<name>\spring (debug info stripped, symbols kept)
#   -Source <dir>: another checkout of the branch (a git worktree of recoil-src, for sessions working side by side; its
#   own build-<name> folder; set $env:ES_FLAGS to "-DBARDROID_SIM -march=armv8.2-a -mtune=cortex-x3" before its first
#   build: gcc-pgo-lse's profile data belong to its own folder)
param([Parameter(Mandatory)][string]$Name, [string]$Source = "", [Parameter(ValueFromRemainingArguments)] $Rest)
$ErrorActionPreference = "Continue"   # (cmake and ninja write to stderr; their exit codes decide)
$HM = "C:\Tools\BARANDROID\hailmary-work"
$ES = "C:\Tools\BARANDROID\engine-sim"
$DK = "C:\Tools\BARANDROID\toolchain\hosttools\w64devkit\bin"
$GCC = "C:\Tools\BARANDROID\toolchain\hosttools\agcc13\bin"   # Arm GNU Toolchain 13.2.Rel1 (SOURCE.txt there)
$env:PATH = "$GCC;$DK;C:\Tools\BARANDROID\toolchain\git\cmd;$env:SystemRoot\System32;$env:SystemRoot"
$env:PKG_CONFIG_LIBDIR = "$HM/static-libs/lib/pkgconfig"
$env:PKG_CONFIG_PATH = ""
$env:PKG_CONFIG = "$DK/pkg-config.exe"
$env:PREFER_STATIC_LIBS = "TRUE"
$env:HOME = "C:\Tools\BARANDROID\toolchain\home"
$env:GIT_CONFIG_NOSYSTEM = "1"
New-Item -ItemType Directory -Force "$ES\out\$Name" | Out-Null
# glibc <= 2.30's __*_finite entry points, which the 18.04 static libraries call (the research's shim, built by GCC)
$shim = "$ES\finite_shim.o"
if (-not (Test-Path $shim)) {
  & "$GCC\aarch64-none-linux-gnu-gcc.exe" -O2 -c "$PSScriptRoot\finite_shim.c" -o $shim
  if ($LASTEXITCODE) { throw "shim failed" }
}
# -O3 -g1 as the official build's -O3 -g (less debug info: the laptop links faster). Debian's multiarch glibc headers
# here as well: some of Recoil's targets (pr-downloader's) drop CMAKE_C_FLAGS, every target keeps the build type's.
$opt = "-O3 -g1 -DNDEBUG -idirafter $HM/sysroot/usr/include/aarch64-linux-gnu $env:ES_FLAGS"
# (--allow-shlib-undefined: the sysroot lacks the libraries SDL2 itself loads (PulseAudio, ALSA, DRM, ...), which the
# phone's container has; GNU ld checks a shared library's own undefined symbols, lld did not)
$ld = "-static-libstdc++ -static-libgcc -Wl,--allow-shlib-undefined $shim -lm $env:ES_LDFLAGS"
$b = "$ES\build-$Name"
if (-not (Test-Path "$b\build.ninja")) {
  $src = if ($Source) { $Source } else { "$HM\recoil-src" }
  & "$DK\cmake.exe" -S $src -B $b -G Ninja "-DCMAKE_MAKE_PROGRAM=$DK/ninja.exe" `
    "-DCMAKE_TOOLCHAIN_FILE=$PSScriptRoot/aarch64-linux-gcc.cmake" "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" `
    -DCMAKE_BUILD_TYPE=RELWITHDEBINFO "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=$opt" "-DCMAKE_C_FLAGS_RELWITHDEBINFO=$opt" `
    "-DCMAKE_EXE_LINKER_FLAGS=$ld" "-DCMAKE_PREFIX_PATH=$HM/static-libs" `
    -DAI_TYPES=NONE -DUSERDOCS_PLAIN=ON -DPREFER_STATIC_LIBS=TRUE @Rest 2>&1 | Tee-Object "$ES\out\$Name\configure.log" |
    Select-String -Pattern 'Error|Build files|ARM64|fp-contract'
  if (-not (Test-Path "$b\build.ninja")) { throw "configure $Name failed: $ES\out\$Name\configure.log" }
}
& "$DK\ninja.exe" -C $b -j 30 engine-legacy 2>&1 | Tee-Object "$ES\out\$Name\build.log" |
  Select-String -Pattern 'error|FAILED|Linking' | Select-Object -Last 20
if ($LASTEXITCODE) { throw "build $Name failed: $ES\out\$Name\build.log" }
& "$GCC\aarch64-none-linux-gnu-objcopy.exe" --strip-debug "$b\spring" "$ES\out\$Name\spring"
"built $Name : $([int]((Get-Item "$ES\out\$Name\spring").Length / 1MB)) MB"
