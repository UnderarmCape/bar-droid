package com.underarmcape.bardroid;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.hardware.display.DisplayManager;
import android.util.DisplayMetrics;
import android.view.Display;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/**
 * The engine's splash made for this screen's shape (Kailil, 2026-11-10: "resize and readjust all the other logos and png
 * that appear on loading screens to look natural on all aspect ratios both landscape and vertical"). The engine stretches
 * its splash picture over the whole screen (rts/System/SplashScreen.cpp): Recoil's 16:9 logo came out tall and thin
 * upright and wide on the folded Fold7's 21:9 side. Here the logo is taken from the engine's own picture
 * (base/RecoilEngine_4K.png) and laid on the picture's grey in a picture of the screen's shape, which the engine's
 * stretch leaves as it is: about as wide as on a 16:9 screen, a little larger upright. launch-bar.sh points the engine's
 * SplashScreenDir at it (bardroid-splash/). Made again only when the screen's shape or the engine's picture changes.
 */
final class SplashPicture {
    private SplashPicture() {}

    /** Before a start: upright as the game will be (the phone may be held the other way at that moment). */
    static void write(Context ctx, File bar, String engineVersion, boolean upright) {
        try {
            File src = new File(bar, "engine/recoil_" + engineVersion + "/base/RecoilEngine_4K.png");
            if (!src.isFile()) return;
            DisplayManager dm = ctx.getSystemService(DisplayManager.class);
            Display d = dm == null ? null : dm.getDisplay(Display.DEFAULT_DISPLAY);
            if (d == null) return;
            DisplayMetrics m = new DisplayMetrics();
            //noinspection deprecation
            d.getRealMetrics(m);   // (the panel in use: the Fold7's cover or its inner screen)
            int lo = Math.min(m.widthPixels, m.heightPixels), hi = Math.max(m.widthPixels, m.heightPixels);
            if (lo <= 0) return;
            int w = upright ? lo : hi, h = upright ? hi : lo;
            float k = 1920f / Math.max(w, h);   // (1920 on its long side: sharp enough for a logo, light on memory)
            int pw = Math.round(w * k), ph = Math.round(h * k);
            File dir = new File(bar, "bardroid-splash");
            File out = new File(dir, "splash.png"), stamp = new File(dir, ".made-for");
            String key = pw + "x" + ph + " " + src.length() + " " + src.lastModified();
            if (out.isFile() && stamp.isFile()
                    && key.equals(new String(Files.readAllBytes(stamp.toPath()), StandardCharsets.UTF_8).trim())) return;
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inSampleSize = 2;   // (its 3840 x 2160 at half: the logo is still drawn smaller than that)
            Bitmap pic = BitmapFactory.decodeFile(src.getPath(), o);
            if (pic == null) return;
            Bitmap c = Bitmap.createBitmap(pw, ph, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(c);
            cv.drawColor(pic.getPixel(2, 2));   // (the picture's own grey, 20, 20, 20)
            // the logo with a margin of the grey around it (the arcs near the picture's edges left out): in 3840 x 2160,
            // x 1000-2750, y 560-1370
            float sx = pic.getWidth() / 3840f, sy = pic.getHeight() / 2160f;
            Rect from = new Rect(Math.round(1000 * sx), Math.round(560 * sy), Math.round(2750 * sx), Math.round(1370 * sy));
            float share = pw > ph ? 0.46f : 0.78f;   // (of the width; on a 16:9 screen the engine's own picture: 0.46)
            float dw = pw * share, dh = dw * from.height() / (float) from.width();
            if (dh > ph * 0.5f) { dh = ph * 0.5f; dw = dh * from.width() / (float) from.height(); }
            RectF to = new RectF((pw - dw) / 2f, (ph - dh) / 2f, (pw + dw) / 2f, (ph + dh) / 2f);
            cv.drawBitmap(pic, from, to, new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG));
            pic.recycle();
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
            File tmp = new File(dir, "splash.png.tmp");
            try (OutputStream os = new FileOutputStream(tmp)) { c.compress(Bitmap.CompressFormat.PNG, 100, os); }
            c.recycle();
            if (!tmp.renameTo(out)) throw new IOException("rename " + tmp);
            Files.write(stamp.toPath(), key.getBytes(StandardCharsets.UTF_8));
            Log.i("app", "the engine's splash made for a " + pw + " x " + ph + " screen (" + (upright ? "upright" : "sideways") + ")");
        } catch (Throwable t) {   // (none: the engine's own picture, as before)
            Log.i("app", "the engine's splash not made: " + t);
        }
    }
}
