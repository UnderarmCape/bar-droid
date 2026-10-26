package com.underarmcape.bardroid;

import android.graphics.Rect;
import android.graphics.RectF;
import android.os.FileObserver;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.KeyEvent;

import com.termux.x11.LorieView;
import com.termux.x11.MainActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * Touch-only mode: the app's half of the touch HUD (assets/bardroid/bardroid_touch_hud.lua, see TOUCH-UI.md). BAR's
 * sandbox lets the HUD make no input, so it appends requests to LuaUI/Config/bardroid_app.txt and they are carried
 * out here:
 *
 *   mods <shift> <ctrl> <alt>   hold (1) or release (0) these keys in the X server (the HUD's QUEUE and CTRL latches)
 *   key <name>                  press and release a key: enter, escape, tab, backspace
 *   keyboard <0|1>              hide / show the soft keyboard
 *   box <0|1>                   BOX latch: a one-finger drag on the map selects instead of panning (read by RtsTouch)
 *
 * It also keeps LuaUI/Config/bardroid_touchui.txt current ("1 <X screen pixels per millimetre>"), so the HUD sizes
 * its buttons in millimetres on either screen of a foldable.
 */
final class TouchUiLink {
    private static final String APP = "bardroid_app.txt";
    private static final long INFO_PERIOD_MS = 1000;

    private final MainActivity activity;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Handler io;
    private final File appFile, infoFile, infoTmp;
    private final FileObserver observer;
    private long readPos;                                   // observer thread
    private final StringBuilder partial = new StringBuilder();
    private boolean shift, ctrl, alt, box;                  // UI thread: what the HUD wants
    private boolean heldShift, heldCtrl, heldAlt;           // UI thread: what the X server has
    private String lastInfo;

    private final Runnable info = new Runnable() {
        @Override public void run() {
            writeInfo();
            ui.postDelayed(this, INFO_PERIOD_MS);
        }
    };

    @SuppressWarnings("deprecation")   // FileObserver(File) needs API 29
    TouchUiLink(MainActivity activity, File widgetDir, Handler io) {
        this.activity = activity;
        this.io = io;
        appFile = new File(widgetDir, APP);
        infoFile = new File(widgetDir, "bardroid_touchui.txt");
        infoTmp = new File(widgetDir, "bardroid_touchui.tmp");
        //noinspection ResultOfMethodCallIgnored
        widgetDir.mkdirs();
        //noinspection ResultOfMethodCallIgnored
        appFile.delete();   // a new game screen: nothing from an earlier one is replayed
        observer = new FileObserver(widgetDir.getPath(), FileObserver.MODIFY | FileObserver.CLOSE_WRITE) {
            @Override public void onEvent(int event, String path) { if (APP.equals(path)) readRequests(); }
        };
        observer.startWatching();
        ui.post(info);
        Log.i("touchui", "touch-only mode");
    }

    void close() {
        observer.stopWatching();
        ui.removeCallbacks(info);
        ui.post(() -> { shift = ctrl = alt = false; applyMods(); });
    }

    /** QUEUE is latched: Shift is held. */
    boolean shift() { return shift; }

    /** BOX is latched: one-finger drags on the map select. */
    boolean boxSelect() { return box; }

    /** View (physical) pixels per millimetre on the current display. */
    float viewPxPerMm() {
        DisplayMetrics dm = new DisplayMetrics();
        //noinspection deprecation
        activity.getWindowManager().getDefaultDisplay().getRealMetrics(dm);
        float dpi = (dm.xdpi + dm.ydpi) / 2;
        if (dpi < dm.densityDpi * 0.6f || dpi > dm.densityDpi * 1.6f) dpi = dm.densityDpi;   // some phones report nonsense
        return dpi / 25.4f;
    }

    /** New complete lines of the HUD's request file (observer thread). */
    private void readRequests() {
        try (RandomAccessFile f = new RandomAccessFile(appFile, "r")) {
            long len = f.length();
            if (len < readPos) { readPos = 0; partial.setLength(0); }   // a new file
            if (len == readPos) return;
            byte[] b = new byte[(int) Math.min(len - readPos, 1 << 16)];
            f.seek(readPos);
            f.readFully(b);
            readPos += b.length;
            partial.append(new String(b, StandardCharsets.US_ASCII));
        } catch (IOException e) { return; }
        int nl;
        while ((nl = partial.indexOf("\n")) >= 0) {
            String line = partial.substring(0, nl).trim();
            partial.delete(0, nl + 1);
            if (!line.isEmpty()) ui.post(() -> execute(line));
        }
    }

    private void execute(String line) {
        Log.i("touchui", line);
        String[] f = line.split(" ");
        switch (f[0]) {
            case "mods":
                if (f.length < 4) break;
                shift = "1".equals(f[1]); ctrl = "1".equals(f[2]); alt = "1".equals(f[3]);
                applyMods();
                break;
            case "key": {
                int code = f.length < 2 ? 0 : keyCode(f[1]);
                LorieView v = activity.getLorieView();
                if (code != 0 && v.connected()) { v.sendKeyEvent(0, code, true); v.sendKeyEvent(0, code, false); }
                break;
            }
            case "keyboard":
                activity.getLorieView().setKeyboardVisible(f.length < 2 || "1".equals(f[1]));
                break;
            case "box":
                box = f.length > 1 && "1".equals(f[1]);
                break;
            default:
                Log.e("touchui", "unknown request: " + line);
        }
    }

    private static int keyCode(String name) {
        switch (name) {
            case "enter": return KeyEvent.KEYCODE_ENTER;
            case "escape": return KeyEvent.KEYCODE_ESCAPE;
            case "tab": return KeyEvent.KEYCODE_TAB;
            case "backspace": return KeyEvent.KEYCODE_DEL;
            default: return 0;
        }
    }

    /** The X server's Shift/Ctrl/Alt follow the HUD's latches. */
    private void applyMods() {
        LorieView v = activity.getLorieView();
        if (v == null || !v.connected()) return;
        if (shift != heldShift) { v.sendKeyEvent(0, KeyEvent.KEYCODE_SHIFT_LEFT, shift); heldShift = shift; }
        if (ctrl != heldCtrl) { v.sendKeyEvent(0, KeyEvent.KEYCODE_CTRL_LEFT, ctrl); heldCtrl = ctrl; }
        if (alt != heldAlt) { v.sendKeyEvent(0, KeyEvent.KEYCODE_ALT_LEFT, alt); heldAlt = alt; }
    }

    /** X screen pixels per millimetre for the HUD (changes when a foldable folds or unfolds). */
    private void writeInfo() {
        LorieView v = activity.getLorieView();
        if (v == null) return;
        Rect vp = v.getInputViewport();
        RectF src = v.getInputSourceRect();
        if (vp.width() <= 0 || src.width() <= 0) return;
        String line = String.format(Locale.US, "1 %.2f\n", viewPxPerMm() * src.width() / vp.width());
        if (line.equals(lastInfo)) return;
        lastInfo = line;
        Log.i("touchui", "screen " + Math.round(src.width()) + "x" + Math.round(src.height()) + ", " + line.trim().substring(2) + " px/mm");
        byte[] data = line.getBytes(StandardCharsets.US_ASCII);
        io.post(() -> {
            try {
                try (FileOutputStream o = new FileOutputStream(infoTmp)) { o.write(data); }
                if (!infoTmp.renameTo(infoFile)) throw new IOException("rename " + infoTmp);
            } catch (IOException e) { Log.e("touchui", "touch-ui file", e); }
        });
    }
}
