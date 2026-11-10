# BAR's load screen pictures for an upright screen (Kailil, 2026-11-10: "resize and readjust all the other logos and png
# that appear on loading screens to look natural on all aspect ratios both landscape and vertical"). BAR's load screen
# (LuaIntro) draws a 16:9 picture from bitmaps/loadpictures cut to the screen's shape: upright a narrow strip of it. These
# are made on the laptop from BAR's own (BAR's developers' clearance, 2026-11-06; NOTICE.md): 1080 x 2400 (9:20), the
# whole picture across the width in the middle, above and below it the same picture enlarged, blurred and darkened, the
# sharp picture's top and bottom fading into it. Any upright phone (9:21 to near square) shows the whole picture. The app
# puts them in the write folder under BAR's names while upright (Installer, launch-bar.sh), where the engine looks before
# the game. Run it again when BAR changes its pictures.
#   powershell -ExecutionPolicy Bypass -File tools\make-loadpictures.ps1 -From <folder of BAR's pictures>
#   (BAR's bitmaps/loadpictures: armada.jpg, cortex.jpg, manual__scavengers__<name>.jpg for manual/scavengers/<name>.jpg)
param([Parameter(Mandatory = $true)][string]$From)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
# (into assets/bardroid itself as loadpicture-upright_<name>: the app unpacks that folder flat, no folders in it)
$out = Join-Path (Split-Path -Parent $PSScriptRoot) "app\src\main\assets\bardroid"
$W, $H = 1080, 2400
$FEATHER = 110          # pixels of the sharp picture's top and bottom that fade into the blurred one
$jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$q = New-Object System.Drawing.Imaging.EncoderParameters 1
$q.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 84L
foreach ($f in Get-ChildItem $From -Filter *.jpg) {
  $src = [System.Drawing.Image]::FromFile($f.FullName)
  $canvas = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($canvas)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  # the blurred ground: the picture cut to the canvas's shape, made tiny and drawn large again (a soft blur), darkened
  $cw = [int]($src.Height * $W / $H)
  $cut = New-Object System.Drawing.Rectangle ([int](($src.Width - $cw) / 2)), 0, $cw, $src.Height
  $tiny = New-Object System.Drawing.Bitmap 27, 60
  $gt = [System.Drawing.Graphics]::FromImage($tiny)
  $gt.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gt.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, 27, 60), $cut, [System.Drawing.GraphicsUnit]::Pixel)
  $gt.Dispose()
  $wrap = New-Object System.Drawing.Imaging.ImageAttributes
  $wrap.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)   # (no dark rim where the scaling meets the edge)
  $g.DrawImage($tiny, (New-Object System.Drawing.Rectangle 0, 0, $W, $H), 0, 0, 27, 60, [System.Drawing.GraphicsUnit]::Pixel, $wrap)
  $tiny.Dispose()
  $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
  $g.FillRectangle($dark, 0, 0, $W, $H); $dark.Dispose()
  # the whole picture across the width in the middle, its top and bottom rows fading in (strips of rising opacity)
  $ph = [int]($src.Height * $W / $src.Width)
  $py = [int](($H - $ph) / 2)
  $scaled = New-Object System.Drawing.Bitmap $W, $ph
  $gs = [System.Drawing.Graphics]::FromImage($scaled)
  $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gs.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $gs.DrawImage($src, 0, 0, $W, $ph); $gs.Dispose()
  $g.DrawImage($scaled, (New-Object System.Drawing.Rectangle 0, ($py + $FEATHER), $W, ($ph - 2 * $FEATHER)), 0, $FEATHER, $W, ($ph - 2 * $FEATHER), [System.Drawing.GraphicsUnit]::Pixel)
  for ($r = 0; $r -lt $FEATHER; $r++) {
    $a = [float](($r + 0.5) / $FEATHER); $a = $a * $a * (3 - 2 * $a)   # (smoothstep)
    $m = New-Object System.Drawing.Imaging.ColorMatrix; $m.Matrix33 = $a
    $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($m)
    $g.DrawImage($scaled, (New-Object System.Drawing.Rectangle 0, ($py + $r), $W, 1), 0, $r, $W, 1, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    $g.DrawImage($scaled, (New-Object System.Drawing.Rectangle 0, ($py + $ph - 1 - $r), $W, 1), 0, ($ph - 1 - $r), $W, 1, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    $ia.Dispose()
  }
  $scaled.Dispose(); $g.Dispose(); $src.Dispose()
  $to = Join-Path $out ("loadpicture-upright_" + $f.Name)
  $canvas.Save($to, $jpeg, $q); $canvas.Dispose()
  "{0}: {1:N0} bytes" -f $f.Name, (Get-Item $to).Length
}
