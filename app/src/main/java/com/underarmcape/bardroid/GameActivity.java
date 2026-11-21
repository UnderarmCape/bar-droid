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
 * screen controls scaling etc.); Android's keyboard shortcuts stay out of the game ({@link KeyboardShortcuts}). The Back
 * button is Escape (BAR's menu, cancel the current command).
 * Gamepad/joystick events are intercepted here instead: ControllerBridge, PadGame (an X mouse and keys, and actions
 * for bardroid_pad.lua).
 */
public class GameActivity extends MainActivity {
    private ControllerBridge pad;
    private RtsTouch touch;

    /**
     * The X screen's size (Kailil, 2026-10-28: "900p folded, and unfolded 1080p"): Termux:X11's "scaled" display at 100%
     * (BarApp) with two caps (patch 0006): at most 2100x900's pixel count, at most 1080 lines on the short side. The
     * Fold7 folded (2520x1080) draws 2100x900, unfolded (2184x1968) 1198x1080. In a real 8v8 (minutes 10-13, up to 1,876
     * units, the 30 fps cap) 900p kept x1.01 and ~29.7 fps as 720p did, the GPU clocked a little higher; native 2520x1080
     * the same, with the GPU ~30% higher clocked (docs/HISTORY.md, 2026-10-28 morning): more heat over a long game.
     */
    static final int MAX_SCREEN_PIXELS = 2100 * 900;
    static final int MAX_SCREEN_LINES = 1080;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // the render resolution setting scales both screens alike; Native (0) has no cap
        float r = Prefs.renderScale / 100f;
        LorieView.maxScaledViewPixels = Math.round(MAX_SCREEN_PIXELS * r * r);
        LorieView.maxScaledShortSide = Math.round(MAX_SCREEN_LINES * r);
        // (dev, docs/CONTAINER-COST.md: files/bar/.bardroid-display-scales: the display hardware enlarges the X screen,
        // no upscaling pass on the GPU; a developer's build only: the write folder is the game's Lua's to write too)
        LorieView.surfaceAtScreenSize = Prefs.developer(this)
                && new java.io.File(BarApp.get().paths().bar, ".bardroid-display-scales").exists();
        KeyboardShortcuts.applyTermuxPrefs(this);
        super.onCreate(savedInstanceState);
        if (!GameService.busy()) {
            // Android brought the game screen back from recent apps after it ended the app (an update, the low-memory
            // killer): no game behind it, only Termux:X11's "Not connected" page. The launcher instead, saying why.
            Log.i("app", "the game screen came back with no game: the launcher instead");
            GameService.noteLowMemoryExit(this);
            startActivity(new android.content.Intent(this, LauncherActivity.class)
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK));
            finishAndRemoveTask();
            return;
        }
        KeyboardShortcuts.start(this);
        touch = new RtsTouch(this);
        voiceChat = new VoiceChat(this, new VoiceChat.Sink() {
            @Override public void listening(boolean on, boolean ping) {
                if (on) touch.voiceStarted();   // (where the words go is fixed as listening begins: RtsTouch.voice)
                touch.padAct(on ? (ping ? "voice_on_ping" : "voice_on") : "voice_off");
            }
            @Override public void heard(String text, boolean ping) { touch.voice(text, ping); }
            @Override public void unavailable() { touch.padAct("voice_none"); }
            @Override public void denied() { touch.padAct("voice_nomic"); }
            @Override public void offline() { touch.padAct("voice_nonet"); }
        });
        touch.setVoiceChat(voiceChat::start);
        touch.setVoicePing(() -> voiceChat.start(true));
        touch.setVoiceListening(voiceChat::listening);
        pad = new ControllerBridge(this, touch::padLine);
        pad.setMouse(lobbyMouse);
        pad.start();   // for as long as the screen exists
        LorieView lorieView = getLorieView();
        View lorieParent = (View) lorieView.getParent();
        TouchInputHandler termux = BarDroidAccess.inputHandler(this);
        lorieParent.setOnTouchListener((v, e) -> {
            if (e.getAction() == MotionEvent.ACTION_DOWN) {
                lorieParent.requestUnbufferedDispatch(e);   // as Termux:X11 does: no batching, less latency
                pad.otherInput();   // (the pointer moves: the pad centres it again when next used)
            }
            if (touch.handles(e)) return touch.onTouch(e);
            if (e.getAction() == MotionEvent.ACTION_DOWN) touch.source("mouse");   // a mouse, stylus or touchpad
            return termux.handleTouchEvent(lorieParent, lorieView, e);
        });
        // Same as Termux:X11's callback, plus: the game window follows the X screen (fold / unfold).
        lorieView.setCallback((w, h, transform) -> {
            termux.handleInputTransformChanged(w, h, transform);
            screenW = w; screenH = h;
            preferRefreshRate();
            touch.screenSize(w, h, refreshHz());
            // (BAR's load screen pictures for the next load in this shape: a game started from the lobby after a turn)
            boolean up = h > w * 1.05f;
            if (w > 0 && h > 0 && (picturesUpright == null || picturesUpright != up)) {
                boolean first = picturesUpright == null;
                picturesUpright = up;
                LoadPictures.follow(new java.io.File(getFilesDir(), "bar"), up, first);
            }
        });
        lorieView.resetRendererZoom();   // undo a magnifier pinch from Termux:X11's own touch handling
        addCatchupView();
        addFreeMemoryButton();
        setUpUpscale();
        preferRefreshRate();
        // The refresh rate settles after a mode request or a fold: keep the widget's frame cap in step.
        getSystemService(DisplayManager.class).registerDisplayListener(displayListener, null);
        getContentResolver().registerContentObserver(android.provider.Settings.System.getUriFor(
                android.provider.Settings.System.ACCELEROMETER_ROTATION), false, autoRotateWatch);
    }

    /** The phone's auto-rotate switched mid-game: the setting's orientation again (setRequestedOrientation). */
    private final android.database.ContentObserver autoRotateWatch =
            new android.database.ContentObserver(new android.os.Handler(android.os.Looper.getMainLooper())) {
        @Override public void onChange(boolean selfChange) {
            if (asked == ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED) return;
            setRequestedOrientation(asked);
        }
    };

    private volatile int screenW, screenH;
    private Boolean picturesUpright;   // (the shape LoadPictures last had: UI thread)

    /**
     * The pad as a mouse (and in BAR's game a keyboard too: ControllerBridge); events go to the X server on the UI
     * thread.
     */
    private final ControllerBridge.Mouse lobbyMouse = new ControllerBridge.Mouse() {
        private final android.os.Handler ui = new android.os.Handler(android.os.Looper.getMainLooper());
        @Override public int mode() {   // (the app's controls in every game since v0.8.5's game went, 2026-11-06)
            // Catching up the engine draws one picture in 30 s on purpose, so the widget's answers went stale and the pad
            // turned into the lobby's free mouse: A clicked into the game unseen behind the progress screen. Off until
            // caught up (nothing queued for afterwards either).
            if (catchingUp) return ControllerBridge.MODE_OFF;
            // (BAR's lobby over the game: the pad is the lobby's mouse there, as with no game. The game's controls held
            // the pointer in the lobby's middle and panned the camera behind it; review 2026-11-17)
            return touch.gameWidgetRunning() && !touch.lobbyOverGame() ? ControllerBridge.MODE_GAME : ControllerBridge.MODE_LOBBY;
        }
        @Override public float pixelsPerSecond() { return 0.75f * Math.max(1080, Math.max(screenW, screenH)); }
        @Override public boolean onInterface() { return touch.pointerOnInterface(); }
        @Override public void move(int dx, int dy) { send(dx, dy, InputStub.BUTTON_UNDEFINED, false); }
        @Override public void button(boolean left, boolean down) { send(0, 0, left ? InputStub.BUTTON_LEFT : InputStub.BUTTON_RIGHT, down); }
        @Override public void wheel(float dy) {
            ui.post(() -> { LorieView v = getLorieView(); if (v != null && v.connected()) v.sendMouseWheelEvent(0, dy); });
        }
        @Override public void key(int keyCode, boolean down) {
            ui.post(() -> { LorieView v = getLorieView(); if (v != null && v.connected()) v.sendKeyEvent(0, keyCode, down); });
        }
        @Override public void act(String name) { touch.padAct(name); }
        @Override public void centre() { moveTo(screenW / 2f, screenH / 2f); }
        @Override public void moveTo(float x, float y) {
            if (screenW <= 0 || screenH <= 0) return;
            ui.post(() -> {
                LorieView v = getLorieView();
                if (v != null && v.connected()) v.sendMouseEvent(x, y, InputStub.BUTTON_UNDEFINED, false, false);
            });
        }
        @Override public int width() { return screenW; }
        @Override public int height() { return screenH; }
        @Override public float[] pointer() { return touch.pointerAt(); }
        @Override public String padFocus() { return touch.padFocus(); }
        @Override public boolean pregame() { return touch.pregame(); }
        @Override public String armed() { return touch.armed(); }
        @Override public float drawSpeed() { return touch.drawSpeed(); }
        @Override public boolean firstPerson() { return touch.firstPerson(); }
        @Override public int clicks() { return touch.clicks(); }
        @Override public float[] clickAt() { return touch.clickAt(); }
        @Override public void voice(boolean ping) { ui.post(() -> { if (voiceChat != null) voiceChat.start(ping); }); }
        @Override public boolean voiceListening() { return voiceChat != null && voiceChat.listening(); }
        @Override public String modal() { return touch.padModal(); }
        private void send(int dx, int dy, int button, boolean down) {
            ui.post(() -> { LorieView v = getLorieView(); if (v != null && v.connected()) v.sendMouseEvent(dx, dy, button, down, true); });
        }
    };
    private final DisplayManager.DisplayListener displayListener = new DisplayManager.DisplayListener() {
        @Override public void onDisplayAdded(int id) {}
        @Override public void onDisplayRemoved(int id) {}
        // (not in the floating window: the display's rate follows the app in front there, 60 and 120 Hz by turns about
        // twice a second, each a log line and a file write, the launcher's log full of them, dev phone 2026-11-19; the
        // rate alone changes nothing in the game, and the full screen's is taken as the window leaves it)
        @Override public void onDisplayChanged(int id) {
            if (screenW > 0 && !isInPictureInPictureMode()) touch.screenSize(screenW, screenH, refreshHz());
        }
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

    /** What Termux:X11 last asked for (KeyboardShortcuts: the "Play upright" setting's orientation). */
    private int asked = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;

    /**
     * Termux:X11 asks for the setting's fixed orientation. With "Turn with the phone" and the phone's auto-rotate on,
     * the phone's own choice instead: upright or sideways as it is held, at any time (the dock, the lobby and BAR's
     * interface follow the screen's shape; Kailil, 2026-11-12). Otherwise sideways flips between its two sides with
     * the sensor.
     */
    @Override
    public void setRequestedOrientation(int requested) {
        boolean fixed = requested == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                || requested == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;
        asked = fixed ? requested : ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
        if (fixed && Prefs.turnWithPhone && Prefs.autoRotate(this)) requested = ActivityInfo.SCREEN_ORIENTATION_USER;
        else if (requested == ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)
            requested = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;
        if (requested == getRequestedOrientation()) return;
        super.setRequestedOrientation(requested);
        Log.i("display", "orientation: " + (requested == ActivityInfo.SCREEN_ORIENTATION_USER ? "turns with the phone (auto-rotate)"
                : requested == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT ? "upright" : requested
                == ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE ? "sideways"
                // (Termux:X11's floating window: the launcher's log said "the phone's (-1)", dev phone 2026-11-19)
                : requested == ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED ? "free (the floating window, or as the phone lies)"
                : "the phone's (" + requested + ")"));
    }

    /** Termux:X11 closes the display with finishAffinity() (game over): also take the task out of recent apps. */
    @Override
    public void finishAffinity() {
        finishAndRemoveTask();
    }

    @Override public void onPause() { if (pad != null) pad.release(); super.onPause(); }
    // (and when the window loses focus without a pause: the notification shade, split screen's other half. A stick or
    // trigger let go meanwhile went to the other window, and the pad read as held: the camera turned on by itself until
    // the stick moved again; release overhaul audit, 2026-11-21)
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (!hasFocus && pad != null) pad.release();
    }
    @Override protected void onDestroy() {
        if (pad != null) {   // (null: a screen that closed itself in onCreate, no game behind it)
            getSystemService(DisplayManager.class).unregisterDisplayListener(displayListener);
            getContentResolver().unregisterContentObserver(autoRotateWatch);
            pad.stop();
            touch.close();
            voiceChat.close();
        }
        super.onDestroy();
    }

    private VoiceChat voiceChat;

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == VoiceChat.PERMISSION_REQUEST && voiceChat != null)
            voiceChat.permissionResult(grantResults.length > 0 && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED);
    }

    // Nobody sees the game while this screen is stopped (phone locked, another app in front; the floating window only
    // pauses it): libbardroid_pace.so then tells the engine its window is hidden, and the engine stops drawing and
    // mutes its sound as a minimized BAR does on a PC. The game itself runs on. The flag outlives this screen when it
    // is closed while the game goes on (the app icon brings a new one); GameService clears it before each game.
    /**
     * "hidden" / "shown" for the game's widgets (bardroid_touch.lua: a game with nobody else in it pauses while the
     * screen is hidden and runs again when it is back; online it runs on). Small, written whole through a rename.
     */
    private static void writeAppState(boolean hidden) {
        java.io.File dir = new java.io.File(BarApp.get().paths().bar, "LuaUI/Config");
        java.io.File tmp = new java.io.File(dir, "bardroid_app.txt.tmp");
        try (java.io.FileOutputStream o = new java.io.FileOutputStream(tmp)) {
            o.write((hidden ? "hidden\n" : "shown\n").getBytes(java.nio.charset.StandardCharsets.US_ASCII));
        } catch (java.io.IOException e) {
            return;   // (no game files yet: nothing reads it)
        }
        if (!tmp.renameTo(new java.io.File(dir, "bardroid_app.txt"))) tmp.delete();
    }

    @Override protected void onStart() {
        super.onStart();
        if (voiceChat != null) voiceChat.opened();   // (speak to chat takes starts again: VoiceChat.close)
        writeAppState(false);
        setFlag(BarApp.get().paths().hiddenFlag(), false, "game screen shown: the engine draws");
        if (!isInPictureInPictureMode()) setFlag(BarApp.get().paths().floatingFlag(), false, "full screen: 30 fps cap");
        catchupHandler.post(catchupCheck);
        if (upscaleLabel != null) catchupHandler.post(upscaleCompare);
        // (fingers until another input shows: the lobby's pointer hidden from its start; again as the X server and the
        // lobby come up, a call before the X server's shared state is dropped)
        if (touch != null && !externalPointerOrPad())
            for (long ms : new long[] {500, 2000, 6000, 15000}) catchupHandler.postDelayed(assumeFingers, ms);
    }
    private final Runnable assumeFingers = () -> { if (touch != null) touch.assumeFingers(); };

    /** An external mouse or gamepad is connected (Samsung's built-in "sec_touchpad" says MOUSE too: external only). */
    private static boolean externalPointerOrPad() {
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice d = InputDevice.getDevice(id);
            if (d == null || d.isVirtual()) continue;
            // (isExternal is Android 10's: before it, Samsung's built-in touchpad left out by its name; on Android 9
            // the call threw NoSuchMethodError, lint's NewApi)
            if (android.os.Build.VERSION.SDK_INT >= 29 ? !d.isExternal() : "sec_touchpad".equals(d.getName())) continue;
            if (d.supportsSource(InputDevice.SOURCE_MOUSE) || d.supportsSource(InputDevice.SOURCE_GAMEPAD)
                    || d.supportsSource(InputDevice.SOURCE_JOYSTICK)) return true;
        }
        return false;
    }
    @Override protected void onStop() {
        writeAppState(true);
        setFlag(BarApp.get().paths().hiddenFlag(), true, "game screen hidden: the engine stops drawing");
        catchupHandler.removeCallbacks(catchupCheck);   // (hidden anyway; the next start looks again)
        catchupHandler.removeCallbacks(upscaleCompare);
        catchupHandler.removeCallbacks(assumeFingers);
        if (voiceChat != null) voiceChat.close();   // (speak to chat stops listening: what is said next is not for the game)
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
        upscaleOn = shader != null && Prefs.upscale && !LorieView.surfaceAtScreenSize;
        getLorieView().setUpscale(upscaleOn ? 1 : 0, shader);
        Log.i("display", "upscaling: " + (LorieView.surfaceAtScreenSize ? "the display's own (surface at the X screen's size)"
                : shader == null ? "plain" : Prefs.upscaleCompare ? "compare SGSR and plain" : upscaleOn ? "SGSR" : "plain"));
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
        setFlag(BarApp.get().paths().floatingFlag(), inPip, inPip ? "floating window: 15 fps cap" : "full screen: 30 fps cap");
        if (!inPip) holdSizeUntilSettled();
        if (!inPip && screenW > 0) touch.screenSize(screenW, screenH, refreshHz());   // (the rate the floating window skipped)
    }

    /**
     * Out of the floating window the window lies upright for a moment (dev phone, 2026-11-03: its first layout
     * 936x2013, then 2008x938 in the same second): Termux:X11 lets the X screen follow the window again at once, and it
     * followed both, a resize the game took 373 ms over for the size it already had. The X screen stays as it is
     * until the window lies its way again (a new layout, not the floating window's), 1 s at most (a fold meanwhile).
     */
    private void holdSizeUntilSettled() {
        LorieView v = getLorieView();
        android.util.Rational r = v.getScreenAspectRatio();
        if (r == null) return;
        boolean wide = r.floatValue() >= 1f;
        int fromW = v.getWidth(), fromH = v.getHeight();
        v.freezeDimensions(true);
        View.OnLayoutChangeListener[] listener = new View.OnLayoutChangeListener[1];
        Runnable thaw = new Runnable() {
            @Override public void run() {
                v.removeOnLayoutChangeListener(listener[0]);
                v.removeCallbacks(this);
                // (back in the floating window within the second: it stays frozen, as Termux:X11 froze it again)
                if (!isInPictureInPictureMode()) v.freezeDimensions(false);
            }
        };
        listener[0] = (view, l, t, right, bottom, ol, ot, or, ob) -> {
            int w = right - l, h = bottom - t;
            if ((w != fromW || h != fromH) && (w >= h) == wide) thaw.run();
        };
        v.addOnLayoutChangeListener(listener[0]);
        v.postDelayed(thaw, 1000);
    }

    // Catching up with a running game far behind (spectating, a reconnect; Kailil: "The catchup is still slow"): the
    // touch widget writes LuaUI/Config/bardroid_catchup.txt, "<game frame> <server frame> <speed>", about once a second
    // of real time. Meanwhile the engine draws nothing (the catch-up flag: a hidden window for the engine) and this
    // screen shows the progress on black (Kailil: "no game render shown"; the last picture stood still behind it). A
    // file not written for CATCHUP_STALE_MS (the widget gone, the game ended) counts as caught up.
    // (the first frames after joining can take over 10 s: the emulator's join showed the progress switch off once)
    private static final long CATCHUP_STALE_MS = 30000;
    private volatile boolean catchingUp;   // (read by the pad's thread: ControllerBridge's mode)
    private android.widget.TextView catchupView;
    private final android.os.Handler catchupHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    private final Runnable catchupCheck = new Runnable() {
        @Override public void run() {
            updateCatchup();
            updatePreGame();
            updateFreeMemory();
            updateLoadTip();
            updateLoadBar();
            updateLowRamLine();
            updateRenderDrop();
            if (touch != null) {
                touch.updateGestureExclusion();
                touch.gridCheck();   // (a GRID whose building went another way: let go)
            }
            catchupHandler.postDelayed(this, 500);
        }
    };

    // Free memory while BAR loads (Kailil, 2026-11-04: "It should appear while bar is loading as a button under the bar
    // logo"): Android lets no app close other apps (since Android 14 not even their background processes), and One UI's
    // Memory screen ("Clean now") needs a system permission; Device care's own page opens from any app, Memory one tap
    // away, and Back comes back here while the game loads on. Only where Device care is (Samsung); below the middle of
    // the screen, under the engine's logo; gone once the game or the lobby is up (GameService.loading).
    private static final String DEVICE_CARE = "com.samsung.android.sm.ACTION_DASHBOARD";
    private android.widget.TextView freeMemory;
    // (its name with what a tap does under it; on a near-square screen, the unfolded Fold7 upright, the name alone: the
    // load picture's commander fills that screen and the two lines covered his head, dev phone at 1080x1198)
    private CharSequence freeMemoryFull, freeMemoryShort;
    private boolean freeMemoryCompact;

    /**
     * Device care's page by its own component: the action alone let any installed app that declares it take the tap
     * (a page of its own over the loading game). Only a system app's (com.samsung.android.lool on the dev phone's
     * One UI 9), or null. Release overhaul item 5, 2026-11-21.
     */
    private android.content.Intent deviceCare() {
        android.content.Intent care = new android.content.Intent(DEVICE_CARE);
        for (android.content.pm.ResolveInfo r : getPackageManager().queryIntentActivities(care, 0)) {
            android.content.pm.ActivityInfo a = r.activityInfo;
            if (a != null && (a.applicationInfo.flags & android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0)
                return care.setClassName(a.packageName, a.name);
        }
        return null;
    }

    private void addFreeMemoryButton() {
        android.content.Intent care = deviceCare();
        if (care == null) return;
        android.widget.TextView v = new android.widget.TextView(this);
        float dp = getResources().getDisplayMetrics().density;
        // (the name bold, what a tap does smaller under it, as the launcher's settings: it leaves the game for a moment)
        String label = getString(R.string.btn_free_memory);
        int nl = label.indexOf('\n');
        android.text.SpannableString text = new android.text.SpannableString(label);
        text.setSpan(new android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, nl > 0 ? nl : label.length(), 0);
        if (nl > 0) {
            text.setSpan(new android.text.style.RelativeSizeSpan(0.68f), nl + 1, label.length(), 0);
            text.setSpan(new android.text.style.ForegroundColorSpan(0xC8FFFFFF), nl + 1, label.length(), 0);
        }
        v.setText(text);
        freeMemoryFull = text;
        android.text.SpannableString name = new android.text.SpannableString(nl > 0 ? label.substring(0, nl) : label);
        name.setSpan(new android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, name.length(), 0);
        freeMemoryShort = name;
        v.setGravity(android.view.Gravity.CENTER);
        v.setTextColor(0xFFFFFFFF);
        v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16);
        v.setPadding((int) (22 * dp), (int) (10 * dp), (int) (22 * dp), (int) (10 * dp));
        android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable();
        bg.setColor(0xC0101010);
        bg.setCornerRadius(10 * dp);
        bg.setStroke(Math.max(1, (int) dp), 0x90FFFFFF);
        // (a light ripple inside the rounded outline while the finger is down: the tap shows it was taken)
        v.setBackground(new android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(0x50FFFFFF), bg, null));
        // (NO_USER_ACTION: no onUserLeaveHint, so Termux:X11 does not shrink the game to its floating window, and Back
        // from Device care comes back to the full screen; dev phone, 2026-11-04)
        care.addFlags(android.content.Intent.FLAG_ACTIVITY_NO_USER_ACTION);
        v.setOnClickListener(x -> {
            Log.i("app", "free memory: Device care opened (Memory, Clean now; Back returns to the game)");
            try { startActivity(care); } catch (Exception e) { Log.e("app", "Device care did not open: " + e); }
        });
        v.setVisibility(View.GONE);
        addContentView(v, new android.widget.FrameLayout.LayoutParams(android.view.ViewGroup.LayoutParams.WRAP_CONTENT,
                android.view.ViewGroup.LayoutParams.WRAP_CONTENT, android.view.Gravity.CENTER));
        v.addOnLayoutChangeListener((view, l, t, r, b, ol, ot, or, ob) -> placeFreeMemory());
        freeMemory = v;
    }

    /**
     * Sideways just under the engine's logo (SplashPicture raises it above the middle for this: a sixth below the middle
     * the button lay over its ENGINE, dev phone 2026-11-12), above the engine's lines at the foot; while a game's load
     * screen is up (BAR's picture: its commander in the middle, the button lay over his waist, and at the top middle
     * over the Armada one's head; dev phone 2026-11-12) in the top right corner, under BAR's low memory band (5 % of the
     * height), over the picture's sky. Upright at the top, under the low memory line where it shows (what the button is
     * for): in the middle it lay over the load picture's commander (dev phone, 2026-11-10).
     */
    private void placeFreeMemory() {
        View v = freeMemory;
        View p = v == null ? null : (View) v.getParent();
        if (p == null || p.getHeight() == 0) return;
        int ph = p.getHeight(), pw = p.getWidth();
        float dp = getResources().getDisplayMetrics().density;
        // (the logo's foot has the picture's margin of grey under ENGINE: a little more to it)
        float ty = SplashPicture.logoFootSideways(pw, ph) * ph + 4 * dp + v.getHeight() / 2f - ph / 2f, tx = 0f;
        boolean upright = ph > pw * 1.05f;
        if (upright || GameService.loadScreen()) {
            int above = lowRamLine != null && lowRamLine.getVisibility() == View.VISIBLE ? lowRamLine.getBottom()
                    : (int) (ph * 0.05f);
            ty = above + 14 * dp - (ph - v.getHeight()) / 2f;
            if (!upright) tx = (pw - v.getWidth()) / 2f - 16 * dp;
        }
        if (v.getTranslationY() != ty) v.setTranslationY(ty);
        if (v.getTranslationX() != tx) v.setTranslationX(tx);
    }

    // The loading screen's tip upright (Kailil, 2026-11-09: "the sentences that appear should fit inside of the vertical
    // aspect ratio"): BAR wraps its own for a wide screen; upright launch-bar.sh turns it off (BAR's loadscreen_tips)
    // and this shows one of BAR's tips (Installer.writeLoadTips: .bardroid-tips) wrapped to the screen, where BAR's was:
    // above its loading bar. Not when the player turned BAR's tips off (.bardroid-no-tips, launch-bar.sh).
    private android.widget.TextView loadTip;
    private static final java.util.regex.Pattern KEY_TIP = java.util.regex.Pattern.compile(
            "(?i)\\b(press|pressing|hold|holding|hotkeys?|keybinds?|key|keys|click|clicking|mouse|ctrl|control\\+|shift|alt"
                    + "|tab|f\\d+)\\b|\\([A-Z]\\)|[~`]|alt\\+|pause/break");

    private void updateLoadTip() {
        View root = getWindow().getDecorView();
        boolean upright = root.getHeight() > root.getWidth() * 1.05f;
        // (a game's load screen made but none of its words yet: the engine's last pre-game frame, "Waiting for server
        // response" and its "Press SHIFT + ESC to quit", still shows for a moment, which the tip lay across; a saved game
        // loaded from the lobby, dev phone 2026-11-17. The tip comes with the load's first words, BAR's picture with them)
        boolean show = upright && GameService.loading() && !isInPictureInPictureMode()
                && !(GameService.loadScreen() && GameService.loadMessage().isEmpty())
                && (touch == null || !touch.gameWidgetRunning())
                && (catchupView == null || catchupView.getVisibility() != View.VISIBLE);
        if (show && loadTip == null) {
            java.io.File bar = new java.io.File(getFilesDir(), "bar");
            String[] tips = null;
            if (!new java.io.File(bar, ".bardroid-no-tips").exists()) {
                try {
                    tips = new String(java.nio.file.Files.readAllBytes(new java.io.File(bar, ".bardroid-tips").toPath()),
                            java.nio.charset.StandardCharsets.UTF_8).split("\n");
                } catch (java.io.IOException e) { tips = null; }
            }
            if (tips == null || tips.length == 0 || tips[0].isEmpty()) return;
            // (upright is touch play: the tips about keys and the mouse, 27 of BAR's 56 - "Press D to quickly initiate
            // aiming", CTRL+(0-9), right-click - left out; all of them if that leaves none)
            java.util.List<String> touchTips = new java.util.ArrayList<>();
            for (String t : tips) {
                if (!KEY_TIP.matcher(t.replace("\\n", "\n")).find()) touchTips.add(t);
            }
            if (!touchTips.isEmpty()) tips = touchTips.toArray(new String[0]);
            android.widget.TextView v = new android.widget.TextView(this);
            float dp = getResources().getDisplayMetrics().density;
            v.setText(tips[new java.util.Random().nextInt(tips.length)].replace("\\n", "\n"));
            v.setTextColor(0xFFFFFFFF);
            v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 17);
            v.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
            v.setShadowLayer(4 * dp, 0, dp, 0xE0000000);   // (on the picture, as BAR's: no box)
            v.setGravity(android.view.Gravity.CENTER);
            v.setPadding((int) (20 * dp), 0, (int) (20 * dp), 0);
            android.widget.FrameLayout.LayoutParams lp = new android.widget.FrameLayout.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.WRAP_CONTENT,
                    android.view.Gravity.BOTTOM);
            lp.bottomMargin = (int) (root.getHeight() * 0.12f);   // (BAR's loading bar: 6.5 % up, 3.8 % tall)
            addContentView(v, lp);
            loadTip = v;
        }
        if (loadTip != null && (loadTip.getVisibility() == View.VISIBLE) != show) {
            loadTip.setVisibility(show ? View.VISIBLE : View.GONE);
        }
    }

    // The loading bar upright (Kailil, 2026-11-11: "The words must fit in the loading bar. I guess make the bar longer to
    // fit more"): BAR's runs over 60 % of the width there (its ends go by the screen's height) and its words, sized by
    // the height too, ran off both ends of the screen. This bar covers BAR's from edge to edge with BAR's words (the
    // engine's load messages, GameService.loadMessage) sized to fit on two lines, filled by BAR's own stages.
    private android.widget.TextView loadBar;
    private android.graphics.drawable.ClipDrawable loadFill;
    private int loadBarForH;   // the window height the bar was sized for

    /** BAR's bar: 6.5 % up, 3.8 % tall, a border of 0.27 %: covered by one 5 % tall about its middle. */
    private static android.widget.FrameLayout.LayoutParams loadBarParams(int h) {
        int barH = (int) Math.ceil(h * 0.05f);
        android.widget.FrameLayout.LayoutParams lp = new android.widget.FrameLayout.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT, barH, android.view.Gravity.BOTTOM);
        lp.bottomMargin = Math.max(0, (int) (h * 0.084f - barH / 2f));
        return lp;
    }

    private void updateLoadBar() {
        View root = getWindow().getDecorView();
        int h = root.getHeight();
        boolean upright = h > root.getWidth() * 1.05f;
        boolean show = upright && GameService.loading() && GameService.loadScreen() && !isInPictureInPictureMode()
                && !GameService.loadMessage().isEmpty()   // (as the tip: an empty bar over the engine's pre-game frame)
                && (touch == null || !touch.gameWidgetRunning())
                && (catchupView == null || catchupView.getVisibility() != View.VISIBLE);
        if (show && loadBar == null && h > 0) {
            android.widget.TextView v = new android.widget.TextView(this);
            float dp = getResources().getDisplayMetrics().density;
            android.graphics.drawable.GradientDrawable back = new android.graphics.drawable.GradientDrawable();
            back.setColor(0xFF141414);   // (opaque: BAR's larger words under it showed through at 95 %)
            android.graphics.drawable.GradientDrawable fill = new android.graphics.drawable.GradientDrawable(
                    android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM, new int[]{0xFFC9A64E, 0xFF7E6020});
            loadFill = new android.graphics.drawable.ClipDrawable(fill, android.view.Gravity.START,
                    android.graphics.drawable.ClipDrawable.HORIZONTAL);
            android.graphics.drawable.GradientDrawable edge = new android.graphics.drawable.GradientDrawable();
            edge.setColor(0);
            edge.setStroke(Math.max(1, (int) dp), 0x60FFFFFF);
            v.setBackground(new android.graphics.drawable.LayerDrawable(
                    new android.graphics.drawable.Drawable[]{back, loadFill, edge}));
            v.setTextColor(0xFFE0E0E0);
            v.setShadowLayer(3 * dp, 0, dp, 0xE0000000);
            v.setGravity(android.view.Gravity.CENTER);
            v.setMaxLines(2);
            v.setPadding((int) (10 * dp), 0, (int) (10 * dp), 0);
            v.setAutoSizeTextTypeUniformWithConfiguration(8, 15, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
            addContentView(v, loadBarParams(h));
            loadBar = v;
            loadBarForH = h;
            Log.i("app", "loading screen: the loading bar across the upright screen, its words fitted");
        }
        if (loadBar == null) return;
        // (folded or unfolded while loading: sized again for the new height; BAR's bar, sized by the height, stood out
        // above the app's after a fold; review 2026-11-16)
        if (show && h > 0 && h != loadBarForH) {
            loadBar.setLayoutParams(loadBarParams(h));
            loadBarForH = h;
        }
        if ((loadBar.getVisibility() == View.VISIBLE) != show) loadBar.setVisibility(show ? View.VISIBLE : View.GONE);
        if (!show) return;
        String m = GameService.loadMessage();
        if (!m.contentEquals(loadBar.getText())) loadBar.setText(m);
        loadFill.setLevel((int) (GameService.loadProgress() * 10000));
    }

    // The loading screen's low memory line upright (Kailil, 2026-11-10: it ran off the screen): BAR prints its warning for
    // a machine under 11 GB of RAM as one line centred across the top in a band 5 % of the screen tall, sized by the
    // screen's height, so upright both its ends are cut off; its loading screen runs only from the game's archive. This
    // covers BAR's band with the same words (Installer.writeLowRamLine: .bardroid-lowram) wrapped to the screen, as tall as
    // they need, while upright and loading, where BAR shows it (BAR's own test: between 1 and 11 GB).
    private android.widget.TextView lowRamLine;

    private void updateLowRamLine() {
        View root = getWindow().getDecorView();
        boolean upright = root.getHeight() > root.getWidth() * 1.05f;
        boolean show = upright && GameService.loading() && !isInPictureInPictureMode()
                && (touch == null || !touch.gameWidgetRunning())
                && (catchupView == null || catchupView.getVisibility() != View.VISIBLE);
        if (show && lowRamLine == null) {
            android.app.ActivityManager.MemoryInfo mem = new android.app.ActivityManager.MemoryInfo();
            ((android.app.ActivityManager) getSystemService(ACTIVITY_SERVICE)).getMemoryInfo(mem);
            long mb = mem.totalMem / (1024 * 1024);
            if (mb <= 1000 || mb >= 11000) return;
            String text;
            try {
                text = new String(java.nio.file.Files.readAllBytes(new java.io.File(new java.io.File(getFilesDir(), "bar"),
                        ".bardroid-lowram").toPath()), java.nio.charset.StandardCharsets.UTF_8).trim();
            } catch (java.io.IOException e) { return; }
            if (text.isEmpty()) return;
            android.widget.TextView v = new android.widget.TextView(this);
            float dp = getResources().getDisplayMetrics().density;
            // (BAR's colours: its grey, and white from a \u0002 to the next \u0001, as BAR prints "12GB memory")
            android.text.SpannableStringBuilder s = new android.text.SpannableStringBuilder();
            boolean white = false;
            for (int i = 0; i < text.length(); i++) {
                char c = text.charAt(i);
                if (c == '\u0002' || c == '\u0001') { white = c == '\u0002'; continue; }
                int at = s.length();
                s.append(c);
                if (white) s.setSpan(new android.text.style.ForegroundColorSpan(0xFFFFFFFF), at, at + 1, 0);
            }
            v.setText(s);
            v.setTextColor(0xFFBBBBBB);
            v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13);
            v.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
            v.setGravity(android.view.Gravity.CENTER);
            v.setBackgroundColor(0xFF1A1A1A);   // (BAR's band is 0.15 grey at 0.7 over the picture: this covers it)
            v.setMinHeight((int) Math.ceil(root.getHeight() * 0.05f) + 1);
            v.setPadding((int) (16 * dp), (int) (6 * dp), (int) (16 * dp), (int) (6 * dp));
            addContentView(v, new android.widget.FrameLayout.LayoutParams(android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.WRAP_CONTENT, android.view.Gravity.TOP));
            lowRamLine = v;
            Log.i("app", "loading screen: the low memory line wrapped to the upright screen (" + mb + " MB)");
        }
        if (lowRamLine != null && (lowRamLine.getVisibility() == View.VISIBLE) != show) {
            lowRamLine.setVisibility(show ? View.VISIBLE : View.GONE);
        }
    }

    // The engine's pre-game screen upright, joining a game hosted elsewhere (Kailil, 2026-11-11, with a screenshot of
    // "Waiting for server response": "the loading screen there is not mobile formatted. Also free memory button should be
    // here too"): the engine lays it out for a wide screen, its lines from 60 % of the width on cut off upright. This
    // covers it, all but its last two lines (the engine's version and its GPL notice, which fit), with the same news
    // wrapped to the screen: what it waits for and the server's address (GameService.preGameHost), the Free memory
    // button over it.
    private android.widget.TextView preGameView;
    private int preGameForH;   // the window height it was sized for
    private int preGameDots = -1;

    private void updatePreGame() {
        View root = getWindow().getDecorView();
        int h = root.getHeight();
        boolean upright = h > root.getWidth() * 1.05f;
        boolean show = upright && GameService.preGame() && !isInPictureInPictureMode()
                && (touch == null || !touch.gameWidgetRunning());
        if (show && preGameView == null && h > 0) {
            android.widget.TextView v = new android.widget.TextView(this);
            float dp = getResources().getDisplayMetrics().density;
            v.setBackgroundColor(0xFF000000);   // (the engine's own black: its words under it gone)
            v.setTextColor(0xFFFFFFFF);
            v.setGravity(android.view.Gravity.CENTER);
            v.setPadding((int) (28 * dp), 0, (int) (28 * dp), 0);
            v.setClickable(false);   // (touches reach the game under it, as the catch-up screen's)
            android.widget.FrameLayout.LayoutParams lp = new android.widget.FrameLayout.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT, (int) (h * 0.9f), android.view.Gravity.TOP);
            addContentView(v, lp);
            preGameView = v;
            preGameForH = h;
            if (freeMemory != null) freeMemory.bringToFront();
            Log.i("app", "pre-game: the engine's waiting screen wrapped to the upright screen");
        }
        if (preGameView == null) return;
        if (show && h > 0 && h != preGameForH) {   // (folded or unfolded meanwhile: 90 % of the new height, as loadBar)
            android.view.ViewGroup.LayoutParams lp = preGameView.getLayoutParams();
            lp.height = (int) (h * 0.9f);
            preGameView.setLayoutParams(lp);
            preGameForH = h;
        }
        if ((preGameView.getVisibility() == View.VISIBLE) != show) preGameView.setVisibility(show ? View.VISIBLE : View.GONE);
        if (!show) return;
        // (dots that count up with the half-second check: a still screen for a slow server read as frozen; all three
        // always there, the unlit ones clear, so the centred words stand still)
        int dots = (int) ((android.os.SystemClock.uptimeMillis() / 500) % 4);
        String title = (GameService.preGameData() ? "Checking the game's files" : "Waiting for the server") + "...";
        String host = GameService.preGameHost();
        String body = GameService.preGameData() ? "The game loads next" : "Connecting to " + host;
        String text = title + "\n\n" + body;
        if (text.contentEquals(preGameView.getText()) && dots == preGameDots) return;
        preGameDots = dots;
        android.text.SpannableString s = new android.text.SpannableString(text);
        s.setSpan(new android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, title.length(), 0);
        if (dots < 3) s.setSpan(new android.text.style.ForegroundColorSpan(0x00FFFFFF), title.length() - 3 + dots,
                title.length(), 0);
        s.setSpan(new android.text.style.RelativeSizeSpan(1.6f), 0, title.length(), 0);
        s.setSpan(new android.text.style.ForegroundColorSpan(0xFFBBBBBB), title.length(), text.length(), 0);
        preGameView.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16);
        preGameView.setText(s);
    }

    private void updateFreeMemory() {
        if (freeMemory == null) return;
        // (and gone once the app's game widget runs: BAR's own interface is up then, the faction picker, "Game starting
        // in 3...", while the engine still loads the AIs; the button lay over them for those seconds, dev phone 2026-11-08)
        // (and on the pre-game screen while a game hosted elsewhere is joined, Kailil 2026-11-11: updatePreGame)
        // (not for the launcher's GL check: a few seconds of the engine's black screen, no game to make room for)
        boolean show = (GameService.loading() || GameService.preGame()) && !isInPictureInPictureMode()
                && !GameService.glCheck()
                && (touch == null || !touch.gameWidgetRunning())
                && (catchupView == null || catchupView.getVisibility() != View.VISIBLE);
        if ((freeMemory.getVisibility() == View.VISIBLE) != show) freeMemory.setVisibility(show ? View.VISIBLE : View.GONE);
        if (show) {
            View root = getWindow().getDecorView();
            int w = root.getWidth(), h = root.getHeight();
            boolean nearSquare = w > 0 && h < w * 1.3f && w < h * 1.3f;
            if (freeMemoryCompact != nearSquare && freeMemoryShort != null && freeMemoryFull != null) {
                freeMemoryCompact = nearSquare;
                freeMemory.setText(nearSquare ? freeMemoryShort : freeMemoryFull);
            }
            placeFreeMemory();   // (the low memory line comes up after it, and moves it down)
        }
    }

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
        setFlag(p.catchupFlag(), on, on ? "catching up: the engine draws nothing until caught up" : "caught up: the engine draws");
        catchingUp = on;
        if (catchupView == null) return;
        if (on) catchupView.setText(text);
        catchupView.setVisibility(on ? View.VISIBLE : View.GONE);
    }

    // The late-game drop (Prefs.lateDrop): bardroid_touch.lua writes LuaUI/Config/bardroid_scale.txt, "scale <percent>"
    // of the render resolution's lines, when the frame rate stays low, and again every 10 s while it is under 100; the
    // X screen shrinks to it (the same way a fold resizes it: the engine's window follows) and SGSR enlarges it. Never
    // under 70 % of the full lines (Kailil, 2026-11-06, after watching 50 %: "way too aggressive. You cant even see lol.
    // We gotta keep it at 70 percent res drop as the minimum instead"). A file not written for RENDER_DROP_STALE_MS (the
    // game ended, the widget gone) is full size again. Native resolution (no cap) has nothing to drop from.
    private static final long RENDER_DROP_STALE_MS = 30000;
    private static final int RENDER_DROP_FLOOR = 70;
    private int renderDrop = 100;

    private void updateRenderDrop() {
        if (!Prefs.lateDrop || Prefs.renderScale == 0) return;
        java.io.File f = new java.io.File(BarApp.get().paths().bar, "LuaUI/Config/bardroid_scale.txt");
        int want = 100;
        if (System.currentTimeMillis() - f.lastModified() < RENDER_DROP_STALE_MS) {   // (0 when there is no file)
            try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
                String line = r.readLine();
                String[] v = line == null ? new String[0] : line.trim().split(" ");
                if (v.length == 2 && v[0].equals("scale")) want = Integer.parseInt(v[1]);
            } catch (java.io.IOException | RuntimeException e) {
                return;   // (the file changing under the read: the next poll reads it again)
            }
        }
        // (a render resolution already under the floor: no drop at all)
        want = Math.max(Math.min(want, 100), Math.min(100, (RENDER_DROP_FLOOR * 100 + Prefs.renderScale - 1) / Prefs.renderScale));
        if (want == renderDrop) return;
        renderDrop = want;
        float r = Prefs.renderScale / 100f * want / 100f;
        LorieView.maxScaledViewPixels = Math.round(MAX_SCREEN_PIXELS * r * r);
        LorieView.maxScaledShortSide = Math.round(MAX_SCREEN_LINES * r);
        LorieView v = getLorieView();
        if (v != null) v.triggerCallback();
        Log.i("display", String.format(java.util.Locale.US, "late-game drop: the game drawn at %d%% of the render resolution (%d%% of the full lines)",
                want, Math.round(r * 100)));
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
            if (on ? flag.createNewFile() : flag.delete()) {
                // (with no engine running, as after a Stop, it changes nothing for a game: the shared logs only. In
                // the launcher's box "game screen hidden: the engine stops drawing" stood after "engine exited (0)" at
                // every Stop; dev phone screenshot 2026-11-19)
                if (Proc.enginePids().isEmpty()) Log.detail("display", change);
                else Log.i("display", change);
            }
        } catch (java.io.IOException e) { Log.e("display", flag.getName() + ": " + e); }
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent ev) {
        if (pad != null && pad.onMotion(ev)) { if (pad.inUse()) touch.source("pad"); return true; }
        if (touch != null && ev.isFromSource(InputDevice.SOURCE_MOUSE)) {
            touch.source("mouse");   // (bardroid_spectate.lua)
            if (pad != null) pad.otherInput();
        }
        return super.dispatchGenericMotionEvent(ev);
    }

    /**
     * Keys before the soft keyboard sees them (LorieView's pre-IME pass, KeyboardShortcuts) and from Termux:X11's
     * KeyInterceptor service; super sends them to the X server as Termux:X11 always did.
     * @return false: not used here, the key goes on (to the soft keyboard, dispatchKeyEvent, or Android)
     */
    @Override
    public boolean handleKey(KeyEvent e) {
        if (pad != null && pad.onKey(e)) { touch.source("pad"); return true; }
        if (KeyboardShortcuts.isAndroidKey(e.getKeyCode())) return false;
        if (touch != null && e.getAction() == KeyEvent.ACTION_DOWN && fromKeyboard(e)) touch.source("keyboard");
        // the system Back: Escape in dispatchKeyEvent, after the soft keyboard (if shown) has closed on it
        if (e.getKeyCode() == KeyEvent.KEYCODE_BACK && !e.isFromSource(InputDevice.SOURCE_MOUSE)) return false;
        e = uncancelled(e);
        boolean sent = super.handleKey(e);
        if (sent && e.getAction() == KeyEvent.ACTION_UP) {
            BarDroidAccess.keyReleaseSent(getLorieView(), e.getKeyCode());
            // (the keyboard's Shift, Alt or Ctrl let go of the same key the touch controls hold: QUEUE's Shift)
            if (touch != null && KeyEvent.isModifierKey(e.getKeyCode())) touch.reassertKeys();
        }
        return sent;
    }

    /**
     * A key typed on a real keyboard (bardroid_spectate.lua's touch tools step aside for one), not the phone's volume
     * buttons, a headset's media keys or the system Back (Kailil, 2026-10-27: volume up ended the follow camera).
     */
    private static boolean fromKeyboard(KeyEvent e) {
        switch (e.getKeyCode()) {
            case KeyEvent.KEYCODE_BACK: case KeyEvent.KEYCODE_VOLUME_UP: case KeyEvent.KEYCODE_VOLUME_DOWN:
            case KeyEvent.KEYCODE_VOLUME_MUTE: case KeyEvent.KEYCODE_MUTE: case KeyEvent.KEYCODE_HEADSETHOOK:
            case KeyEvent.KEYCODE_MEDIA_PLAY: case KeyEvent.KEYCODE_MEDIA_PAUSE: case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
            case KeyEvent.KEYCODE_MEDIA_NEXT: case KeyEvent.KEYCODE_MEDIA_PREVIOUS: case KeyEvent.KEYCODE_MEDIA_STOP:
                return false;
            default:
                InputDevice d = e.getDevice();
                return d != null && !d.isVirtual() && d.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC;
        }
    }

    private boolean backClicked;   // this Back's press clicked BAR's quit button: no Escape for its release either

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (pad != null && pad.onKey(event)) { touch.source("pad"); return true; }
        if (KeyboardShortcuts.isAndroidKey(event.getKeyCode())) return false;   // the window's and the system's handling
        // The system Back button/gesture (not a keyboard's or a mouse's back key): with the touch dock contextual (the dock
        // to its home grid, then BAR's quit button: RtsTouch.back), and Escape as before unless that clicked the button.
        if (event.getKeyCode() == KeyEvent.KEYCODE_BACK && !event.isFromSource(InputDevice.SOURCE_MOUSE)
                && getLorieView().connected()) {
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
                backClicked = touch != null && touch.back();
                if (!backClicked) getLorieView().sendKeyEvent(0, KeyEvent.KEYCODE_ESCAPE, true);
            } else if (event.getAction() == KeyEvent.ACTION_UP) {
                if (!backClicked) getLorieView().sendKeyEvent(0, KeyEvent.KEYCODE_ESCAPE, false);
                backClicked = false;
            }
            return true;
        }
        return super.dispatchKeyEvent(uncancelled(event));
    }

    /**
     * A key's release Android cancelled (the window lost focus with the key held: the notification shade, another
     * window under DeX) as a plain release: Termux:X11 drops a cancelled one, and the key stayed down in X (a held arrow
     * went on scrolling the map; a held Shift made every finger tap after it a Shift click). Release overhaul audit,
     * 2026-11-21.
     */
    private static KeyEvent uncancelled(KeyEvent e) {
        if (e.getAction() != KeyEvent.ACTION_UP || (e.getFlags() & KeyEvent.FLAG_CANCELED) == 0) return e;
        return KeyEvent.changeFlags(e, e.getFlags() & ~KeyEvent.FLAG_CANCELED);
    }
}
