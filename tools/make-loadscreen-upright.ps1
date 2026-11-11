# The lobby's first picture upright (app/src/main/assets/bardroid/loadscreen-upright.png), made from BAR's own
# (Chobby's MenuLoadscreens/loadscreen.png, 3821x2160, credited in NOTICE.md).
#
# Chobby draws that picture as 16:9 cut to the screen's shape (api_chili.lua): upright only the middle quarter of its
# width is seen. So the word is laid, whole, into that quarter on the picture's own grey (Kailil, 2026-11-10: "zoom out
# so it can show the full word BAR ... feather the edges ... the same Grey so it looks seamless"), the torn bands left
# out. Kailil, 2026-11-11: "bar looks super low res. Can you regenerate a sharper image ... But keep the resolution and
# size down": on a phone the lobby's X screen is smaller than the display (Termux:X11's pixel cap) and the picture is
# scaled twice on its way (into the X screen, then SGSR onto the display), so the word is scaled here with a sharp
# filter and pre-sharpened (an unsharp mask), the rest flat grey (the PNG stays ~130 KB).
#
#   powershell -ExecutionPolicy Bypass -File tools\make-loadscreen-upright.ps1 -Source <BAR's loadscreen.png>
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [string]$Out = "",            # default: the app's asset
  [double]$WordShare = 0.8,     # the letters' width, of the quarter that shows upright
  [double]$Sharpen = 0.9,       # the unsharp mask's amount
  [double]$Radius = 1.1         # its blur radius, pixels of the result
)
$ErrorActionPreference = "Stop"
if (-not $Out) { $Out = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\app\src\main\assets\bardroid\loadscreen-upright.png" }
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class LoadUp {
    static byte[] Bytes(Bitmap b, out int stride) {
        var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
        stride = d.Stride;
        var a = new byte[stride * b.Height];
        Marshal.Copy(d.Scan0, a, 0, a.Length);
        b.UnlockBits(d);
        return a;
    }
    static void Put(Bitmap b, byte[] a) {
        var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
        Marshal.Copy(a, 0, d.Scan0, a.Length);
        b.UnlockBits(d);
    }
    // Lanczos-3 resampling of one row or column pass (separable), 24-bit RGB
    static float L3(double x) {
        if (x == 0) return 1f;
        if (x <= -3 || x >= 3) return 0f;
        double px = Math.PI * x;
        return (float)(3 * Math.Sin(px) * Math.Sin(px / 3) / (px * px));
    }
    public static Bitmap Lanczos(Bitmap src, int w, int h) {
        int sw = src.Width, sh = src.Height, ss;
        byte[] s = Bytes(src, out ss);
        float[] mid = new float[w * sh * 3];
        double kx = (double)sw / w, fx = Math.Max(1, kx);
        for (int x = 0; x < w; x++) {
            double c = (x + 0.5) * kx - 0.5;
            int lo = (int)Math.Floor(c - 3 * fx), hi = (int)Math.Ceiling(c + 3 * fx);
            for (int y = 0; y < sh; y++) {
                float r = 0, g = 0, bl = 0, sum = 0;
                for (int i = lo; i <= hi; i++) {
                    float wt = L3((i - c) / fx);
                    if (wt == 0) continue;
                    int ix = Math.Min(sw - 1, Math.Max(0, i));
                    int o = y * ss + ix * 3;
                    bl += wt * s[o]; g += wt * s[o + 1]; r += wt * s[o + 2]; sum += wt;
                }
                int m = (y * w + x) * 3;
                mid[m] = bl / sum; mid[m + 1] = g / sum; mid[m + 2] = r / sum;
            }
        }
        var dst = new Bitmap(w, h, PixelFormat.Format24bppRgb);
        int ds;
        byte[] d = Bytes(dst, out ds);
        double ky = (double)sh / h, fy = Math.Max(1, ky);
        for (int y = 0; y < h; y++) {
            double c = (y + 0.5) * ky - 0.5;
            int lo = (int)Math.Floor(c - 3 * fy), hi = (int)Math.Ceiling(c + 3 * fy);
            for (int x = 0; x < w; x++) {
                float r = 0, g = 0, bl = 0, sum = 0;
                for (int i = lo; i <= hi; i++) {
                    float wt = L3((i - c) / fy);
                    if (wt == 0) continue;
                    int iy = Math.Min(sh - 1, Math.Max(0, i));
                    int m = (iy * w + x) * 3;
                    bl += wt * mid[m]; g += wt * mid[m + 1]; r += wt * mid[m + 2]; sum += wt;
                }
                int o = y * ds + x * 3;
                d[o] = Clamp(bl / sum); d[o + 1] = Clamp(g / sum); d[o + 2] = Clamp(r / sum);
            }
        }
        Put(dst, d);
        return dst;
    }
    static byte Clamp(double v) { return (byte)Math.Max(0, Math.Min(255, Math.Round(v))); }
    // unsharp mask: v + amount * (v - gaussian(v)), in place
    public static void Unsharp(Bitmap b, double radius, double amount) {
        int w = b.Width, h = b.Height, st;
        byte[] a = Bytes(b, out st);
        int n = (int)Math.Ceiling(radius * 3);
        double[] k = new double[2 * n + 1];
        double ks = 0;
        for (int i = -n; i <= n; i++) { k[i + n] = Math.Exp(-i * i / (2 * radius * radius)); ks += k[i + n]; }
        for (int i = 0; i < k.Length; i++) k[i] /= ks;
        var t = new double[w * h * 3];
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) for (int c = 0; c < 3; c++) {
            double v = 0;
            for (int i = -n; i <= n; i++) { int ix = Math.Min(w - 1, Math.Max(0, x + i)); v += k[i + n] * a[y * st + ix * 3 + c]; }
            t[(y * w + x) * 3 + c] = v;
        }
        var bl = new double[w * h * 3];
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) for (int c = 0; c < 3; c++) {
            double v = 0;
            for (int i = -n; i <= n; i++) { int iy = Math.Min(h - 1, Math.Max(0, y + i)); v += k[i + n] * t[(iy * w + x) * 3 + c]; }
            bl[(y * w + x) * 3 + c] = v;
        }
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) for (int c = 0; c < 3; c++) {
            int o = y * st + x * 3 + c;
            a[o] = Clamp(a[o] + amount * (a[o] - bl[(y * w + x) * 3 + c]));
        }
        Put(b, a);
    }
    // the word laid on the grey with its edges feathered over f pixels (no seam where the crop ends)
    public static void Lay(Bitmap canvas, Bitmap word, int x0, int y0, int f, Color grey) {
        int cs, wsd;
        byte[] c = Bytes(canvas, out cs);
        byte[] s = Bytes(word, out wsd);
        for (int y = 0; y < word.Height; y++) for (int x = 0; x < word.Width; x++) {
            int e = Math.Min(Math.Min(x, word.Width - 1 - x), Math.Min(y, word.Height - 1 - y));
            double t = Math.Min(1.0, e / (double)f);
            t = t * t * (3 - 2 * t);
            int o = (y0 + y) * cs + (x0 + x) * 3, q = y * wsd + x * 3;
            c[o] = Clamp(grey.B + t * (s[q] - grey.B));
            c[o + 1] = Clamp(grey.G + t * (s[q + 1] - grey.G));
            c[o + 2] = Clamp(grey.R + t * (s[q + 2] - grey.R));
        }
        Put(canvas, c);
    }
}
'@

$src = New-Object Drawing.Bitmap (Resolve-Path $Source).Path
if ($src.Width -ne 3821 -or $src.Height -ne 2160) { Write-Warning "BAR's picture was 3821x2160; this one is $($src.Width)x$($src.Height)" }
$sx = $src.Width / 3821.0; $sy = $src.Height / 2160.0
# (the word with its dark glow, inside the torn bands: BAR's 3821x2160 picture; the letters span x 1320..2554)
$crop = New-Object Drawing.Rectangle ([int](1230 * $sx)), ([int](730 * $sy)), ([int](1420 * $sx)), ([int](720 * $sy))
$letters = 1234 * $sx
$src24 = $src.Clone($crop, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
$quarter = $src.Width / 4.0
$k = $WordShare * $quarter / $letters
$w = [int][Math]::Round($crop.Width * $k); $h = [int][Math]::Round($crop.Height * $k)
$word = [LoadUp]::Lanczos($src24, $w, $h)
[LoadUp]::Unsharp($word, $Radius, $Sharpen)
$grey = [Drawing.Color]::FromArgb(22, 22, 22)
$canvas = New-Object Drawing.Bitmap $src.Width, $src.Height, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [Drawing.Graphics]::FromImage($canvas); $g.Clear($grey); $g.Dispose()
[LoadUp]::Lay($canvas, $word, [int](($src.Width - $w) / 2), [int](($src.Height - $h) / 2), [int](0.12 * $h), $grey)
$canvas.Save([IO.Path]::GetFullPath($Out), [Drawing.Imaging.ImageFormat]::Png)
"$Out : $($canvas.Width)x$($canvas.Height), the word $w x $h (letters $([int]($letters * $k)) px of the quarter's $([int]$quarter)), $((Get-Item $Out).Length) bytes"
$src.Dispose(); $src24.Dispose(); $word.Dispose(); $canvas.Dispose()
