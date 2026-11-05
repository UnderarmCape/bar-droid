# The interface's stripes (docs/DELIVERY.md "The whole picture in vertical stripes") on the dev phone: skirmishes with
# the launcher's settings, alternating FD_MESA_DEBUG=noubwc (Adreno's compressed render targets off, through
# dev-env.sh) and none, a screenshot -After seconds after the game's first perf line, then the game force-stopped and
# -Pause seconds of rest. Screenshots and a montage (the build menu, BAR's idle builders button, the whole screen) in
# build\stripes-test; one line per start: mode, battery temperature, game frame of the screenshot.
#   powershell -ExecutionPolicy Bypass -File tools\stripes-test.ps1 [-Pairs 3] [-After 60] [-Pause 20]
param([int]$Pairs = 3, [int]$After = 60, [int]$Pause = 20, [string]$Device = "")
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "toolchain.ps1")
$adb = Join-Path $TC "android-sdk\platform-tools\adb.exe"
if (-not $Device) { $Device = Get-PhoneDevice $adb }
$out = Join-Path (Split-Path $PSScriptRoot) "build\stripes-test"
New-Item -ItemType Directory -Force $out | Out-Null
$tmp = Join-Path $TC "tmp"
New-Item -ItemType Directory -Force $tmp | Out-Null
function AppRun([string]$text) {
  $f = Join-Path $tmp "stripes.sh"
  [IO.File]::WriteAllText($f, ($text -replace "`r", ""), (New-Object Text.ASCIIEncoding))
  Invoke-AppScript $adb $f $Device
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$shots = @()
for ($k = 0; $k -lt 2 * $Pairs; $k++) {
  $mode = @('noubwc', 'normal')[$k % 2]
  if ($mode -eq 'noubwc') {
    AppRun "printf '%s\n' 'export FD_MESA_DEBUG=noubwc' 'log `"stripes-test: FD_MESA_DEBUG=noubwc`"' > files/bar/dev-env.sh; rm -f files/bar/infolog.txt" | Out-Null
  } else {
    AppRun "rm -f files/bar/dev-env.sh files/bar/infolog.txt" | Out-Null
  }
  # (the battery's own line of dumpsys, in tenths of a degree; the history lines after it repeat "temperature:")
  $temp = (& $adb -s $Device shell 'dumpsys battery' | Where-Object { $_ -match '^\s+temperature: (\d+)' } | Select-Object -First 1) -replace '\D', ''
  # background apps closed first: the dev phone's 8 GB leaves little for a loading game (Android's low-memory kill)
  & $adb -s $Device shell "am kill-all; am force-stop com.underarmcape.bardroid; sleep 1; am start -n com.underarmcape.bardroid/.LauncherActivity --es start skirmish" | Out-Null
  $started = $false
  for ($i = 0; $i -lt 30 -and -not $started; $i++) {
    Start-Sleep 10
    $n = "$(& $adb -s $Device shell 'run-as com.underarmcape.bardroid grep -c bardroid-perf files/bar/infolog.txt 2>/dev/null')".Trim() -replace '\D', ''
    $started = [bool]($n -and [int]$n -gt 0)
  }
  if ($started) { Start-Sleep $After }
  $png = Join-Path $out ("{0}-{1}-{2}.png" -f $stamp, ($k + 1), $mode)
  & cmd /c "`"$adb`" -s $Device exec-out screencap -p > `"$png`""
  $last = "$(& $adb -s $Device shell 'run-as com.underarmcape.bardroid tail -n 1 files/bar/infolog.txt')"
  $frame = if ($last -match '\[f=(-?\d+)\]') { [int]$matches[1] } else { "?" }
  & $adb -s $Device shell "am force-stop com.underarmcape.bardroid; input keyevent KEYCODE_HOME" | Out-Null
  $state = if ($started) { "frame $frame" } else { "no game (see launcher.log: low memory?)" }
  "{0} {1}: battery {2} C, {3}" -f ($k + 1), $mode, ([double]("0$temp") / 10), $state
  $shots += $png
  Start-Sleep $Pause
}
AppRun "rm -f files/bar/dev-env.sh" | Out-Null

# the montage: per start a row with the build menu (50 %), BAR's idle builders button and the whole screen (25 %)
Add-Type -AssemblyName System.Drawing
$rowH = 300
$img0 = [System.Drawing.Image]::FromFile($shots[0]); $W = $img0.Width; $H = $img0.Height; $img0.Dispose()
$sx = $W / 2316.0; $sy = $H / 1080.0   # (the regions were measured on the dev phone's 2316x1080 landscape screen)
$bmp = New-Object System.Drawing.Bitmap 1500, ($rowH * $shots.Count)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font 'Arial', 16
$y = 0
foreach ($f in $shots) {
  $img = [System.Drawing.Image]::FromFile($f)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, ($y + 24), 406, 166), (New-Object System.Drawing.Rectangle 0, ([int](365 * $sy)), ([int](812 * $sx)), ([int](331 * $sy))), [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle 416, ($y + 24), 185, 94), (New-Object System.Drawing.Rectangle ([int](1775 * $sx)), ([int](986 * $sy)), ([int](185 * $sx)), ([int](94 * $sy))), [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle 615, ($y + 24), 579, 270), (New-Object System.Drawing.Rectangle 0, 0, $img.Width, $img.Height), [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString((Split-Path $f -Leaf), $font, [System.Drawing.Brushes]::White, 0, $y)
  $img.Dispose()
  $y += $rowH
}
$montage = Join-Path $out "$stamp-montage.png"
$bmp.Save($montage, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"montage: $montage"
