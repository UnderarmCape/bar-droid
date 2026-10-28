# Build one research engine variant for the LAPTOP (Windows x86-64, w64devkit's GCC + BAR's mingwlibs64), to measure
# engine patches with laptop-bench.ps1 -EngineDir while the phone is away:  build-engine-win.ps1 <name> [cmake args]
# Flags from $env:HM_FLAGS (defines such as -DHM_GAME_SPEED=20). Output: win-engine\<name>\ = the official 2026.07.04
# Windows engine dir (hard links, without the ReShade/DLSS files found there) with our spring.exe.
param([string]$Name, [Parameter(ValueFromRemainingArguments)] $Rest)
$HM = "C:\Tools\BARANDROID\hailmary-work"
$DK = "C:\Tools\BARANDROID\toolchain\hosttools\w64devkit\bin"
$env:PATH = "$DK;C:\Tools\BARANDROID\toolchain\git\cmd;$env:SystemRoot\System32;$env:SystemRoot"
$env:MINGWLIBS = "$HM/mingwlibs64"
$env:HOME = "C:\Tools\BARANDROID\toolchain\home"
$env:GIT_CONFIG_NOSYSTEM = "1"
$opt = "-O3 -g1 -DNDEBUG $env:HM_FLAGS"
$DKf = $DK.Replace("\", "/")   # CMake reads backslashes in these as escapes
$b = "$HM\build-win-$Name"
if (-not (Test-Path "$b\build.ninja")) {
  & "$DK\cmake.exe" -S "$HM\recoil-src" -B $b -G Ninja "-DCMAKE_MAKE_PROGRAM=$DKf/ninja.exe" `
    "-DCMAKE_C_COMPILER=$DKf/gcc.exe" "-DCMAKE_CXX_COMPILER=$DKf/g++.exe" "-DCMAKE_RC_COMPILER=$DKf/windres.exe" `
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON `
    -DCMAKE_BUILD_TYPE=RELWITHDEBINFO "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=$opt" "-DCMAKE_C_FLAGS_RELWITHDEBINFO=$opt" `
    "-DCMAKE_CXX_FLAGS_INIT=-static-libstdc++ -static-libgcc" "-DCMAKE_C_FLAGS_INIT=-static-libstdc++ -static-libgcc" `
    "-DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++ -static-libgcc $env:HM_LDFLAGS" `
    "-DMINGWLIBS=$HM/mingwlibs64" -DAI_TYPES=NONE -DUSERDOCS_PLAIN=ON @Rest | Select-String -Pattern 'Error|Build files'
}
& "$DK\ninja.exe" -C $b -j 30 engine-legacy | Select-String -Pattern 'error|FAILED|Linking' | Select-Object -Last 20
if ($LASTEXITCODE) { throw "build $Name failed" }
$off = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "Programs\Beyond-All-Reason\data\engine\recoil_2026.07.04"
$out = "$HM\win-engine\$Name"
if (-not (Test-Path $out)) {
  New-Item -ItemType Directory -Force $out | Out-Null
  foreach ($i in Get-ChildItem $off) {
    if ($i.Name -match '^(spring\.exe|opengl32\.dll|ReShade.*|.*dlss.*|.*renodx.*|nvngx.*|infolog\.txt|springsettings\.cfg|.*\.png|.*\.dmp|Verify-.*)$') { continue }
    if ($i.PSIsContainer) { cmd /c mklink /J "$out\$($i.Name)" "$($i.FullName)" | Out-Null }
    else { New-Item -ItemType HardLink -Path "$out\$($i.Name)" -Target $i.FullName | Out-Null }
  }
}
Copy-Item "$b\spring.exe" "$out\spring.exe" -Force
"built win $Name : $out"
