# Side by side crops of the same region of several screenshots, enlarged, with labels: crop-compare.ps1 -Images a.png,b.png
# -Labels "BAR's","mobile" -X 600 -Y 250 -W 200 -H 160 -Scale 3 -Out out.png
param([string[]]$Images, [string[]]$Labels, [int]$X, [int]$Y, [int]$W, [int]$H, [int]$Scale = 3, [string]$Out)
Add-Type -AssemblyName System.Drawing
$cols = $Images.Count
$bmp = New-Object System.Drawing.Bitmap ($W * $Scale * $cols + 8 * ($cols - 1)), ($H * $Scale + 36)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(30, 30, 30))
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$font = New-Object System.Drawing.Font "Segoe UI", 16, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $cols; $i++) {
  $img = [System.Drawing.Image]::FromFile($Images[$i])
  $dx = $i * ($W * $Scale + 8)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle $dx, 36, ($W * $Scale), ($H * $Scale)), (New-Object System.Drawing.Rectangle $X, $Y, $W, $H), [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString($Labels[$i], $font, [System.Drawing.Brushes]::White, ($dx + 6), 4)
  $img.Dispose()
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
$Out
