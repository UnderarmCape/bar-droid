# Build one research engine variant: build-engine.ps1 <name>   (flags from $env:HM_FLAGS / $env:HM_LDFLAGS)
# -> build-<name>\spring (with debug info), out\<name>\spring (debug info stripped, symbol table kept)
param([string]$Name, [Parameter(ValueFromRemainingArguments)] $Rest)
$HM = "C:\Tools\BARANDROID\hailmary-work"
$DK = "C:\Tools\BARANDROID\toolchain\hosttools\w64devkit\bin"
$LLVM = "C:\Tools\BARANDROID\toolchain\android-sdk\ndk\29.0.14206865\toolchains\llvm\prebuilt\windows-x86_64\bin"
$env:PATH = "$DK;C:\Tools\BARANDROID\toolchain\git\cmd;$env:SystemRoot\System32;$env:SystemRoot"
$env:PKG_CONFIG_LIBDIR = "$HM/static-libs/lib/pkgconfig"
$env:PKG_CONFIG_PATH = ""
$env:PKG_CONFIG = "$DK/pkg-config.exe"
$env:PREFER_STATIC_LIBS = "TRUE"
$env:HOME = "C:\Tools\BARANDROID\toolchain\home"
$env:GIT_CONFIG_NOSYSTEM = "1"
$opt = "-O3 -g1 -DNDEBUG $env:HM_FLAGS"
$ld = "-fuse-ld=lld -static-libstdc++ -static-libgcc $HM/scripts/finite_shim.o -lm $env:HM_LDFLAGS"
$b = "$HM\build-$Name"
if (-not (Test-Path "$b\build.ninja")) {
  & "$DK\cmake.exe" -S "$HM\recoil-src" -B $b -G Ninja "-DCMAKE_MAKE_PROGRAM=$DK/ninja.exe" `
    "-DCMAKE_TOOLCHAIN_FILE=$HM/scripts/aarch64-linux-clang.cmake" "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" `
    -DCMAKE_BUILD_TYPE=RELWITHDEBINFO "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=$opt" "-DCMAKE_C_FLAGS_RELWITHDEBINFO=$opt" `
    "-DCMAKE_EXE_LINKER_FLAGS=$ld" "-DCMAKE_PREFIX_PATH=$HM/static-libs" `
    -DAI_TYPES=NONE -DUSERDOCS_PLAIN=ON -DPREFER_STATIC_LIBS=TRUE @Rest | Select-String -Pattern 'Error|Build files'
}
& "$DK\ninja.exe" -C $b -j 30 engine-legacy | Select-String -Pattern 'error|FAILED|Linking' | Select-Object -Last 20
if ($LASTEXITCODE) { throw "build $Name failed" }
New-Item -ItemType Directory -Force "$HM\out\$Name" | Out-Null
& "$LLVM\llvm-objcopy.exe" --strip-debug "$b\spring" "$HM\out\$Name\spring"
"built $Name : $([int]((Get-Item "$HM\out\$Name\spring").Length / 1MB)) MB"
