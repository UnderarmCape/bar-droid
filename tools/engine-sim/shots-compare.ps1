# Two runs' screenshots side by side (skirmish-shots.ps1 / replay-memory.ps1 -Shots: <run>-shot1..3.png), one row per
# shot, A on the left, B on the right, each scaled to -Width; and a crop of each shot's middle at full size below
# (-Crop pixels square), for drawing changes (docs/ENGINE-SIM.md).
#   shots-compare.ps1 -A <run prefix> -B <run prefix> -Out <png> [-Width 900] [-Crop 360] [-LabelA x] [-LabelB y]
param([Parameter(Mandatory)][string]$A, [Parameter(Mandatory)][string]$B, [Parameter(Mandatory)][string]$Out,
      [int]$Width = 900, [int]$Crop = 360, [string]$LabelA = "A", [string]$LabelB = "B")
Add-Type -AssemblyName System.Drawing
$rows = @()
for ($i = 1; $i -le 3; $i++) {
  $fa = "$A-shot$i.png"; $fb = "$B-shot$i.png"
  if ((Test-Path $fa) -and (Test-Path $fb)) { $rows += , @([System.Drawing.Image]::FromFile($fa), [System.Drawing.Image]::FromFile($fb)) }
}
if (-not $rows.Count) { throw "no shot pairs ($A-shot1.png, $B-shot1.png)" }
$h0 = [int]($rows[0][0].Height * $Width / $rows[0][0].Width)
$label = 24
$H = $rows.Count * ($h0 + $label) + $rows.Count * ($Crop + $label)
$bmp = New-Object System.Drawing.Bitmap (2 * $Width + 8), $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$g.InterpolationMode = 'HighQualityBicubic'
$font = New-Object System.Drawing.Font "Segoe UI", 11
$y = 0
for ($r = 0; $r -lt $rows.Count; $r++) {
  for ($c = 0; $c -lt 2; $c++) {
    $img = $rows[$r][$c]
    $g.DrawString("$(@($LabelA, $LabelB)[$c]) shot $($r + 1)", $font, [System.Drawing.Brushes]::White, $c * ($Width + 8), $y + 2)
    $g.DrawImage($img, $c * ($Width + 8), $y + $label, $Width, [int]($img.Height * $Width / $img.Width))
  }
  $y += $h0 + $label
}
$g.InterpolationMode = 'NearestNeighbor'
for ($r = 0; $r -lt $rows.Count; $r++) {
  for ($c = 0; $c -lt 2; $c++) {
    $img = $rows[$r][$c]
    $src = New-Object System.Drawing.Rectangle ([int](($img.Width - $Crop) / 2)), ([int](($img.Height - $Crop) / 2)), $Crop, $Crop
    $g.DrawString("$(@($LabelA, $LabelB)[$c]) shot $($r + 1), middle 1:1", $font, [System.Drawing.Brushes]::White, $c * ($Width + 8), $y + 2)
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle ($c * ($Width + 8)), ($y + $label), $Crop, $Crop), $src, [System.Drawing.GraphicsUnit]::Pixel)
  }
  $y += $Crop + $label
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); foreach ($p in $rows) { $p[0].Dispose(); $p[1].Dispose() }
"montage: $Out"
