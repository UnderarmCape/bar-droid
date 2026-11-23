# Every library the container's programs link is there (ldd inside the app's container on the dev phone): the engines
# (BAR's official build and the phone engine), pr-downloader, the phone Mesa's GL, EGL, GBM and Vulkan drivers, OpenAL
# and SDL2. A new player's container once lacked libatomic1, which the phone engine links: its first game ended in 127
# and BAR's official engine ran from then on (the fresh-install run, 2026-11-22; setup-container.sh "apt" and "libs").
# One line a file: "[containerlibs] PASS <file>" or "[containerlibs] FAIL <file>: <library> not found"; seconds.
#   powershell -ExecutionPolicy Bypass -File tools\container-libs-phone-test.ps1      (ANDROID_SERIAL names another phone)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$env:USERPROFILE = Join-Path $TC "home"; $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE ".android"
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = Get-PhoneDevice $adb }   # toolchain.ps1's choice: the dev phone
$tmp = Join-Path $TC "tmp"
New-Item -ItemType Directory -Force $tmp | Out-Null
$check = Join-Path $tmp "container-libs.sh"
$body = @'
#!/bin/bash
n=0
L=/usr/lib/aarch64-linux-gnu
for f in /root/bar/engine/*/spring /root/bar/engine-sim/*/spring /root/bar/engine/*/pr-downloader $L/libgallium-*.so \
         $L/libGLX_mesa.so.0 $L/libEGL_mesa.so.0 $L/gbm/dri_gbm.so $L/libvulkan_freedreno.so $L/libopenal.so.1 \
         $L/libSDL2-2.0.so.0; do
  [ -e "$f" ] || continue
  n=$((n + 1))
  miss=$(ldd "$f" 2>&1 | awk '/not found/ { print $1 }' | tr '\n' ' ')
  if [ -n "$miss" ]; then echo "[containerlibs] FAIL $f: ${miss}not found"; else echo "[containerlibs] PASS $f"; fi
done
[ "$n" -gt 0 ] || echo "[containerlibs] FAIL nothing to check (the container not set up?)"
echo "[containerlibs] done: $n checked"
'@
[IO.File]::WriteAllText($check, ($body -replace "`r`n", "`n"))
$run = Join-Path $tmp "container-libs-run.sh"
[IO.File]::WriteAllText($run, "sh files/container.sh 'bash /root/bar/.container-libs.sh'`nrm -f files/bar/.container-libs.sh`n")
try {
  Send-AppFile $adb $check "files/bar/.container-libs.sh" $env:ANDROID_SERIAL
  Invoke-AppScript $adb $run $env:ANDROID_SERIAL
} finally {
  Remove-Item -Force $check, $run -ErrorAction SilentlyContinue
}
