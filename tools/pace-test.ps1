# libbardroid_pace.so's hidden-window events, tested on the phone in the app's container without a display:
# builds tools\pace\pace.c (as tools\build-pace.py does, into build\pace-test) and tools\pace\pace_test.c, pushes both
# into files/bar, runs `perl -e 1` with both preloaded and SDL's dummy video driver, removes them again.
# Needs the phone on adb (ANDROID_SERIAL) and an installed app with its container.
#   powershell -ExecutionPolicy Bypass -File tools\pace-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $App "build\pace-test"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$ndk = Get-ChildItem (Join-Path $App "..\toolchain\android-sdk\ndk") -Directory | Sort-Object Name | Select-Object -Last 1
$clang = Join-Path $ndk.FullName "toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
foreach ($pair in @(@("pace.c", "libbardroid_pace.so"), @("pace_test.c", "pace_test.so"))) {
  & $clang --target=aarch64-linux-gnu -O2 -fPIC -shared -nostdlib -fuse-ld=lld -ffreestanding -fno-stack-protector `
    -Wall -Wextra "-Wl,--hash-style=gnu,--build-id=none,-soname,$($pair[1]),-z,noexecstack" `
    -o (Join-Path $Out $pair[1]) (Join-Path $PSScriptRoot "pace\$($pair[0])")
  if ($LASTEXITCODE -ne 0) { throw "clang failed on $($pair[0])" }
}
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = "192.168.1.196:5555" }
$env:USERPROFILE = Join-Path $App "..\toolchain\home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $App "..\toolchain\android-sdk\platform-tools\adb.exe"
$pkg = "com.underarmcape.bardroid"
foreach ($f in "libbardroid_pace.so", "pace_test.so") {
  & $adb push (Join-Path $Out $f) "/data/local/tmp/$f" | Out-Null
  & $adb shell "run-as $pkg sh -c 'mkdir -p files/bar/pace-test && cat /data/local/tmp/$f > files/bar/pace-test/$f' && rm /data/local/tmp/$f"
}
$script = "rm -f /tmp/bardroid-hidden; cd /root/bar/pace-test && SDL_VIDEODRIVER=dummy " +
          "LD_PRELOAD=/root/bar/pace-test/libbardroid_pace.so:/root/bar/pace-test/pace_test.so perl -e 1; rm -rf /root/bar/pace-test /tmp/bardroid-hidden"
$script | Out-File -Encoding ascii -NoNewline (Join-Path $Out "run.sh")
cmd /c "type `"$(Join-Path $Out 'run.sh')`" | `"$adb`" exec-in run-as $pkg sh -c `"cat > files/bar/pace-test-run.sh`""
& $adb shell "run-as $pkg sh files/crun.sh 'sh /root/bar/pace-test-run.sh; rm -f /root/bar/pace-test-run.sh'"
