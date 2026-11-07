# Builds the container-cost probes (docs/CONTAINER-COST.md) static for arm64 with the NDK: build\container-cost\
#   stopsample  (runs on the phone as the app's user: how long a thread sits stopped by proot, and in which calls)
#   trapbench   (runs inside the container: microseconds per trapped and untrapped system call)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot) "toolchain.ps1")
$clang = Join-Path $TC "android-sdk\ndk\29.0.14206865\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$out = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "build\container-cost"
New-Item -ItemType Directory -Force $out | Out-Null
foreach ($n in "stopsample", "trapbench") {
  & $clang --target=aarch64-linux-android29 -O2 -static -o "$out\$n" "$PSScriptRoot\$n.c"
  if ($LASTEXITCODE) { throw "build $n failed" }
  "built $out\$n"
}
