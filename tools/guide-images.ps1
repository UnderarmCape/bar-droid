# The user guide's pictures (docs/guide/img) made from the dev phone's screenshots: each PNG scaled to at most -Width
# pixels across (its shape kept) and saved as a JPEG, so the guide stays light on GitHub and on the web.
#   powershell -ExecutionPolicy Bypass -File tools\guide-images.ps1 -Map <map.txt> [-Width 720] [-Quality 82]
# map.txt: one picture a line, "<source.png> <name>" (the name without .jpg; # starts a comment). Sources relative to
# the repository's build\ folder or absolute. Crop with "<source.png> <name> top=<0..1> bottom=<0..1>" (the share of
# the height kept from the top to the bottom: top=0.55 keeps the lower 45 %).
param([Parameter(Mandatory)][string]$Map, [int]$Width = 720, [int]$Quality = 82)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$repo = Split-Path $PSScriptRoot
$out = Join-Path $repo "docs\guide\img"
New-Item -ItemType Directory -Force $out | Out-Null
$codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$params = New-Object Drawing.Imaging.EncoderParameters 1
$params.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), ([long]$Quality)
foreach ($line in [IO.File]::ReadAllLines($Map)) {
  $l = $line.Trim()
  if (-not $l -or $l.StartsWith("#")) { continue }
  $f = $l -split '\s+'
  $src = if ([IO.Path]::IsPathRooted($f[0])) { $f[0] } else { Join-Path $repo "build\$($f[0])" }
  if (-not (Test-Path $src)) { "missing: $src"; continue }
  $top = 0.0; $bottom = 1.0
  foreach ($opt in $f[2..($f.Count - 1)]) {
    if ($opt -match '^top=([0-9.]+)$') { $top = [double]$Matches[1] }
    if ($opt -match '^bottom=([0-9.]+)$') { $bottom = [double]$Matches[1] }
  }
  $img = [Drawing.Image]::FromFile($src)
  try {
    $y0 = [int]($img.Height * $top); $h = [int]($img.Height * $bottom) - $y0
    $scale = [Math]::Min(1.0, $Width / $img.Width)
    $w2 = [int]($img.Width * $scale); $h2 = [int]($h * $scale)
    $bmp = New-Object Drawing.Bitmap $w2, $h2
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, (New-Object Drawing.Rectangle 0, 0, $w2, $h2), (New-Object Drawing.Rectangle 0, $y0, $img.Width, $h), [Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $dst = Join-Path $out "$($f[1]).jpg"
    $bmp.Save($dst, $codec, $params)
    $bmp.Dispose()
    "{0,-34} {1,5}x{2,-5} {3,4} KB" -f "$($f[1]).jpg", $w2, $h2, [int]((Get-Item $dst).Length / 1KB)
  } finally { $img.Dispose() }
}
