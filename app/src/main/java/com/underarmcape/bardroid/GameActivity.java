package com.underarmcape.bardroid;

import android.content.pm.ActivityInfo;
import android.hardware.display.DisplayManager;
import android.os.Bundle;
import android.view.Display;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

import com.termux.x11.BarDroidAccess;
import com.termux.x11.LorieView;
import com.termux.x11.MainActivity;
import com.termux.x11.input.InputStub;
import com.termux.x11.input.TouchInputHandler;

/**
 * The game screen: Termux:X11's display/input activity, plus a gamepad bridge. Finger gestures go through
 * {@link RtsTouch}; mouse, stylus, touchpad and keyboard go to the X server exactly as in Termux:X11 (its preferences
 * screen controls scaling etc.). The Back button is Escape (BAR's menu, cancel the current command).
 * Gamepad/joystick events are intercepted here and sent to the engine's Lua over UDP instead.
 */
public class GameActivity extends MainActivity {
    private ControllerBridge pad;
    private RtsTouch touch;

    /**
     * Termux:X11's "scaled" display treats a bigger screen as one of the Fold7's cover screen's pixel count (patch 0006):
     * unfolded (2184x1968) the game draws about as many pixels as folded (1680x720 at 150%) instead of 1.6x as many.
     * Late games are limited by the GPU (Kailil, 2026-10-26: "What else can we do to save performance").
     */
    static final int MAX_SCREEN_PIXELS = 2520 * 1080;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // the render resolution setting scales both screens alike: folded the cap then applies too (2520x1080 is the cap)
        float r = Prefs.renderScale / 100f;
        LorieView.maxScaledViewPixels = Math.round(MAX_SCREEN_PIXELS * r * r);
        super.onCreate(savedInstanceState);
        touch = new RtsTouch(this);
        pad = new ControllerBridge(this, Prefs.controllerPort, touch::padLine);
        pad.setMouse(lobbyMouse);
        pad.start();   // for as long as the screen exists: v0.8.5 must never find its companion gone
        LorieView lorieView = getLorieView();
        View lorieParent = (View) lorieView.getParent();
        TouchInputHandler termux = BarDroidAccess.inputHandler(this);
        lorieParent.setOnTouchListener((v, e) -> {
            if (e.getAction() == MotionEvent.ACTION_DOWN)
                lorieParent.requestUnbufferedDispatch(e);   // as Termux:X11 does: no batching, less latency
            if (touch.handles(e)) return touch.onTouch(e);
            return termux.handleTouchEvent(lorieParent, lorieView, e);
        });
        // Same as Termux:X11's callback, plus: the game window follows the X screen (fold / unfold).
        lorieView.setCallback((w, h, transform) -> {
            termux.handleInputTransformChanged(w, h, transform);
            screenW = w; screenH = h;
            preferRefreshRate();
            touch.screenSize(w, h, refreshHz());
        });
        lorieView.resetRendererZoom();   // undo a magnifier pinch from Termux:X11's own touch handling
        addCatchupView();
        setUpUpscale();
        preferRefreshRate();
        // The refresh rate settles after a mode request or a fold: keep the widget's frame cap in step.
        getSystemService(DisplayManager.class).registerDisplayListener(displayListener, null);
    }

    private volatile int screenW, screenH;

    /** The pad as a mouse where no game runs (the lobby, loading screens); events go to the X server on the UI thread. */
    private final ControllerBridge.Mouse lobbyMouse = new ControllerBridge.Mouse() {
        private final android.os.Handler ui = new android.os.Handler(android.os.Looper.getMainLooper());
        @Override public boolean active() { return !touch.gameWidgetRunning(); }
        @Override public float pixelsPerSecond() { return 0.75f * Math.max(1080, Math.max(screenW, screenH)); }
        @Override public void move(int dx, int dy) { send(dx, dy, InputStub.BUTTON_UNDEFINED, false); }
        @Override public void button(boolean left, boolean down) { send(0, 0, left ? InputStub.BUTTON_LEFT : InputStub.BUTTON_RIGHT, down); }
        @Override public void wheel(float dy) {
            ui.post(() -> { LorieView v = getLorieView(); if (v != null && v.connected()) v.sendMouseWheelEvent(0, dy); });
        }
        private void send(int dx, int dy, int button, boolean down) {
            ui.post(() -> { LorieView v = getLorieView(); if (v != null && v.connected()) v.sendMouseEvent(dx, dy, button, down, true); });
        }
    };
    private final DisplayManager.DisplayListener displayListener = new DisplayManager.DisplayListener() {
        @Override public void onDisplayAdded(int id) {}
        @Override public void onDisplayRemoved(int id) {}
        @Override public void onDisplayChanged(int id) { if (screenW > 0) touch.screenSize(screenW, screenH, refreshHz()); }
    };

    /**
     * A 60 Hz mode of the current display: enough for the 30 and 60 fps caps, and half the display's own work of
     * 120 Hz. Uncapped (Prefs.fpsCap 0) its fastest mode, so the display never limits a measurement.
     */
    private void preferRefreshRate() {
        Display d = display();
        if (d == null) return;
        Display.Mode cur = d.getMode();
        WindowManager.LayoutParams lp = getWindow().getAttributes();
        boolean fastest = Prefs.fpsCap == 0;
        int want = 0;
        float wantHz = 0f;
        for (Display.Mode m : d.getSupportedModes()) {
            if (m.getPhysicalWidth() != cur.getPhysicalWidth() || m.getPhysicalHeight() != cur.getPhysicalHeight()) continue;
            float hz = m.getRefreshRate();
            if (fastest ? hz > wantHz : Math.abs(hz - 60f) < 1f) { want = m.getModeId(); wantHz = hz; }
        }
        float rate = fastest ? wantHz : 60f;
        if (lp.preferredDisplayModeId == want && lp.preferredRefreshRate == rate) return;
        lp.preferredDisplayModeId = want;
        lp.preferredRefreshRate = rate;
        getWindow().setAttributes(lp);
    }

    private int refreshHz() {
        Display d = display();
        return d == null ? 60 : Math.round(d.getRefreshRate());
    }

    /** The display this screen is on (Android 11 deprecated getDefaultDisplay for Activity.getDisplay). */
    @SuppressWarnings("deprecation")
    private Display display() {
        return android.os.Build.VERSION.SDK_INT >= 30 ? getDisplay() : getWindowManager().getDefaultDisplay();
    }

    /** Termux:X11 asks for fixed landscape; let the phone flip between the two landscape sides with the sensor. */
    @Override
    public void setRequestedOrientation(int requested) {
        super.setRequestedOrientation(requested == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                ? ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE : requested);
    }

    /** Termux:X11 closes the display with finishAffinity() (game over): also take the task out of recent apps. */
    @Override
    public void finishAffinity() {
        finishAndRemoveTask();
    }

    @Override public void onPause() { pad.release(); super.onPause(); }
    @Override protected void onDestroy() {
        getSystemService(DisplayManager.class).unregisterDisplayListener(displayListener);
        pad.stop();
        touch.close();
        super.onDestroy();
    }

    // Nobody sees the game while this screen is stopped (phone locked, another app in front; the floating window only
    // pauses it): libbardroid_pace.so then tells the engine its window is hidden, and the engine stops drawing and
    // mutes its sound as a minimized BAR does on a PC. The game itself runs on. The flag outlives this screen when it
    // is closed while the game goes on (the app icon brings a new one); GameService clears it before each game.
    @Override protected void onStart() {
        super.onStart();
        setFlag(hiddenFlag(BarApp.get().paths()), false, "game screen shown: the engine draws");
        if (!isInPictureInPictureMode()) setFlag(floatingFlag(BarApp.get().paths()), false, "full screen: 30 fps cap");
        catchupHandler.post(catchupCheck);
        if (upscaleLabel != null) catchupHandler.post(upscaleCompare);
    }
    @Override protected void onStop() {
        setFlag(hiddenFlag(BarApp.get().paths()), true, "game screen hidden: the engine stops drawing");
        catchupHandler.removeCallbacks(catchupCheck);   // (hidden anyway; the next start looks again)
        catchupHandler.removeCallbacks(upscaleCompare);
        super.onStop();
    }

    // Upscaling (Kailil, 2026-10-27: "a cheaper anti aliasing or upscale"): the X screen is smaller than the display
    // (MAX_SCREEN_PIXELS) and lorie enlarged it with plain bilinear filtering. Qualcomm's SGSR 1 (assets/sgsr,
    // BSD-3-Clause; patch 0007 draws it) enlarges it with sharp edges, in one pass on the GPU. The compare mode switches
    // it on and off every 3 s under a label saying which.
    private static final long UPSCALE_COMPARE_MS = 3000;
    private android.widget.TextView upscaleLabel;
    private boolean upscaleOn;
    private final Runnable upscaleCompare = new Runnable() {
        @Override public void run() {
            setUpscale(!upscaleOn);
            catchupHandler.postDelayed(this, UPSCALE_COMPARE_MS);
        }
    };

    private void setUpUpscale() {
        String shader = null;
        if (Prefs.upscale || Prefs.upscaleCompare) {
            try (java.io.InputStream in = getAssets().open("sgsr/sgsr1_shader_mobile.frag")) {
                java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
                byte[] b = new byte[8192];
                for (int n; (n = in.read(b)) > 0; ) out.write(b, 0, n);
                shader = out.toString("UTF-8");
            } catch (java.io.IOException e) { Log.e("display", "SGSR shader: " + e); }
        }
        upscaleOn = shader != null && Prefs.upscale;
        getLorieView().setUpscale(upscaleOn ? 1 : 0, shader);
        Log.i("display", "upscaling: " + (shader == null ? "plain" : Prefs.upscaleCompare ? "compare SGSR and plain" : upscaleOn ? "SGSR" : "plain"));
        if (shader == null || !Prefs.upscaleCompare) return;
        android.widget.TextView v = new android.widget.TextView(this);
        float dp = getResources().getDisplayMetrics().density;
        v.setBackgroundColor(0xB0000000);   // small, at the top: touches still reach the game below (not clickable)
        v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15);
        v.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        v.setPadding((int) (12 * dp), (int) (4 * dp), (int) (12 * dp), (int) (4 * dp));
        android.widget.FrameLayout.LayoutParams lp = new android.widget.FrameLayout.LayoutParams(
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT, android.view.ViewGroup.LayoutParams.WRAP_CONTENT,
                android.view.Gravity.TOP | android.view.Gravity.CENTER_HORIZONTAL);
        lp.topMargin = (int) (48 * dp);
        addContentView(v, lp);
        upscaleLabel = v;
    }

    private void setUpscale(boolean on) {
        LorieView v = getLorieView();
        upscaleOn = on;
        v.setUpscale(on ? 1 : 0, null);
        if (upscaleLabel == null) return;
        boolean refused = v.getUpscaleState() < 0;   // (known after the first frame drawn with it)
        upscaleLabel.setText(refused ? "SGSR upscaling: not supported on this GPU" : on ? "SGSR upscaling ON" : "SGSR upscaling OFF");
        upscaleLabel.setTextColor(on && !refused ? 0xFF7CFC00 : 0xFFFFFFFF);
    }

    // The floating window: the X screen shrinks to it (the engine draws few pixels), and libbardroid_pace.so caps the
    // frame rate at 15 while this flag is there (Kailil, 2026-10-26).
    @Override
    public void onPictureInPictureModeChanged(boolean inPip, android.content.res.Configuration newConfig) {
        super.onPictureInPictureModeChanged(inPip, newConfig);
        setFlag(floatingFlag(BarApp.get().paths()), inPip, inPip ? "floating window: 15 fps cap" : "full screen: 30 fps cap");
    }

    /** The flags libbardroid_pace.so looks for (the container's /tmp/bardroid-hidden, -floating, -catchup). */
    static java.io.File hiddenFlag(Paths p) { return new java.io.File(p.rootfsTmp, "bardroid-hidden"); }
    static java.io.File floatingFlag(Paths p) { return new java.io.File(p.rootfsTmp, "bardroid-floating"); }
    static java.io.File catchupFlag(Paths p) { return new java.io.File(p.rootfsTmp, "bardroid-catchup"); }

    // Catching up with a running game far behind (spectating, a reconnect; Kailil: "The catchup is still slow"): the
    // touch widget writes LuaUI/Config/bardroid_catchup.txt, "<game frame> <server frame> <speed>", about once a second
    // of real time. Meanwhile the engine draws nothing (the catch-up flag: a hidden window for the engine) and this
    // screen shows the progress on black (Kailil: "no game render shown"; the last picture stood still behind it). A
    // file not written for CATCHUP_STALE_MS (the widget gone, the game ended) counts as caught up.
    // (the first frames after joining can take over 10 s: the emulator's join showed the progress switch off once)
    private static final long CATCHUP_STALE_MS = 30000;
    private android.widget.TextView catchupView;
    private final android.os.Handler catchupHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    private final Runnable catchupCheck = new Runnable() {
        @Override public void run() {
            updateCatchup();
            catchupHandler.postDelayed(this, 500);
        }
    };

    private void addCatchupView() {
        android.widget.TextView v = new android.widget.TextView(this);
        float dp = getResources().getDisplayMetrics().density;
        v.setTextColor(0xFFFFFFFF);
        v.setBackgroundColor(0xFF000000);   // the whole screen: touches still reach the game below (not clickable)
        v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 22);
        v.setGravity(android.view.Gravity.CENTER);
        v.setPadding((int) (24 * dp), (int) (16 * dp), (int) (24 * dp), (int) (16 * dp));
        v.setVisibility(View.GONE);
        addContentView(v, new android.widget.FrameLayout.LayoutParams(android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT));
        catchupView = v;
    }

    private void updateCatchup() {
        Paths p = BarApp.get().paths();
        java.io.File f = new java.io.File(p.bar, "LuaUI/Config/bardroid_catchup.txt");
        boolean on = System.currentTimeMillis() - f.lastModified() < CATCHUP_STALE_MS;   // (0 when there is no file)
        String text = null;
        if (on) {
            try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
                String line = r.readLine();
                String[] v = line == null ? new String[0] : line.trim().split(" ");
                long frame = Long.parseLong(v[0]), server = Long.parseLong(v[1]);   // server 0: not known yet
                float speed = Float.parseFloat(v[2]);                               // 0: not measured yet
                text = "Catching up\n" + gameClock(frame) + (server > 0 ? " of " + gameClock(server) : "")
                        + (speed > 0 ? String.format(java.util.Locale.US, "   x%.1f", speed) : "")
                        + timeLeft(server - frame, speed);
            } catch (java.io.IOException | RuntimeException e) {
                return;   // the file changing under the read: keep what is shown, the next poll reads it again
            }
        }
        setFlag(catchupFlag(p), on, on ? "catching up: the engine draws nothing until caught up" : "caught up: the engine draws");
        if (catchupView == null) return;
        if (on) catchupView.setText(text);
        catchupView.setVisibility(on ? View.VISIBLE : View.GONE);
    }

    /** "about N min left": the gap shrinks by (speed - 1) game seconds a second (the live game runs on at 1x). */
    private static String timeLeft(long behindFrames, float speed) {
        if (behindFrames <= 0 || speed < 1.1f) return "";
        long seconds = Math.round(behindFrames / 30.0 / (speed - 1));
        return seconds < 90 ? "\nunder 2 min left" : "\nabout " + Math.round(seconds / 60.0) + " min left";
    }

    private static String gameClock(long frame) {
        long s = frame / 30;
        return String.format(java.util.Locale.US, "%d:%02d", s / 60, s % 60);
    }

    private static void setFlag(java.io.File flag, boolean on, String change) {
        try {
            if (on ? flag.createNewFile() : flag.delete()) Log.i("display", change);
        } catch (java.io.IOException e) { Log.e("display", flag.getName() + ": " + e); }
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent ev) {
        if (pad != null && pad.onMotion(ev)) return true;
        return super.dispatchGenericMotionEvent(ev);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (pad != null && pad.onKey(event)) return true;
        // The system Back button/gesture (not a keyboard's or a mouse's back key) becomes Escape.
        if (event.getKeyCode() == KeyEvent.KEYCODE_BACK && !event.isFromSource(InputDevice.SOURCE_MOUSE)
                && getLorieView().connected()) {
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0)
                getLorieView().sendKeyEvent(0, KeyEvent.KEYCODE_ESCAPE, true);
            else if (event.getAction() == KeyEvent.ACTION_UP)
                getLorieView().sendKeyEvent(0, KeyEvent.KEYCODE_ESCAPE, false);
            return true;
        }
        return super.dispatchKeyEvent(event);
    }
}
