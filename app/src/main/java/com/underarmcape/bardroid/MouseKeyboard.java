package com.underarmcape.bardroid;

import android.hardware.input.InputManager;
import android.os.Build;
import android.util.SparseBooleanArray;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.WindowManager;

import com.termux.x11.LorieApp;
import com.termux.x11.LorieView;
import com.termux.x11.MainActivity;
import com.termux.x11.input.InputStub;
import com.termux.x11.input.TouchInputHandler;

/**
 * A mouse and a keyboard on the game screen (Bluetooth, or a USB-C dock), played as on a PC. Kailil (2026-10-27): "I
 * want people to be able to use mouse and keyboard either via Bluetooth or plugged in via usb-c dock. and i want
 * android to not hijack its inputs and listen for shortcuts and other things". Launcher setting "Mouse and keyboard
 * go to the game" (Prefs.mouseKeyboard, on); off, Termux:X11 handles them as before (its Display settings).
 *
 * Mouse: Android's pointer capture. Android's arrow is gone and the engine gets relative motion as from a PC mouse, so
 * BAR's pointer never stops at the display's edge (middle-button camera drags; Recoil's middle-click scroll uses SDL's
 * relative mode, which only sees lorie's relative motion: its absolute moves carry POINTER_NORAW), and no button can
 * turn into Android's Back. Taken when the screen gets focus with a mouse connected, when a mouse is connected, and on
 * a click; Android lets it go when the screen loses focus (Home or Recents gesture, the notification shade, another
 * app). Ctrl+Alt, pressed and let go with no other key, lets it go by hand (DeX's taskbar); a click takes it back.
 * Termux:X11 lets it go at every Escape: not here, BAR uses Escape all the time.
 *
 * Keyboard: keys go to the X server before the soft keyboard sees them (Samsung Keyboard's language switch on
 * Shift+Space), as scancodes (key down and key up as pressed: BAR holds keys such as Space, and binds scancodes), and
 * Android's own shortcuts are asked to come to the game: Android 16.1+ keyboard capture
 * (WindowManager.LayoutParams.setKeyboardCaptureEnabled, permission CAPTURE_KEYBOARD, a normal permission: Meta,
 * Alt+Tab, Ctrl+Space ...) and Samsung's Meta key request (Termux:X11's "Intercept system shortcuts"). For what an older
 * Android still takes, Termux:X11's KeyInterceptor accessibility service ("Beyond All Reason keyboard shortcuts"),
 * switched on by the player (README). Keys that are Android's and no game key (isAndroidKey: Home, Recents, power,
 * brightness) stay Android's on every path; volume and media keys keep Termux:X11's handling (Android's, unless its
 * Display settings give them an action).
 */
final class MouseKeyboard implements InputManager.InputDeviceListener {
    /** Termux:X11 sends this many scroll units per wheel click; lorie divides by 120 (cmdentrypoint.cpp). */
    private static final float WHEEL_CLICK = 120;

    private final MainActivity activity;
    private final TouchInputHandler termux;
    private final InputManager inputManager;
    private final SparseBooleanArray rightButtons = new SparseBooleanArray();   // mice seen with BUTTON_SECONDARY
    private int captured;              // mouse buttons held while captured (MotionEvent.BUTTON_*)
    private final CtrlAltRelease release = new CtrlAltRelease();
    private boolean releasedByHand;    // Ctrl+Alt let the mouse go: no capture again until a click or new focus

    MouseKeyboard(MainActivity activity, TouchInputHandler termux) {
        this.activity = activity;
        this.termux = termux;
        inputManager = activity.getSystemService(InputManager.class);
    }

    /**
     * Termux:X11's switches for the same things follow the setting; read in its onCreate, so called before it. Off =
     * Termux:X11's defaults. Written only when they differ (each write is a synchronous commit).
     */
    static void applyTermuxPrefs(MainActivity a) {
        com.termux.x11.Prefs p = ((LorieApp) a.getApplication()).getPrefs(a);
        boolean on = Prefs.mouseKeyboard;
        if (p.pointerCapture.get() != on) p.pointerCapture.put(on);
        if (p.dexMetaKeyCapture.get() != on) p.dexMetaKeyCapture.put(on);
        if (p.preferScancodes.get() != on) p.preferScancodes.put(on);
        if (p.hardwareKbdScancodesWorkaround.get() == on) p.hardwareKbdScancodesWorkaround.put(!on);
    }

    void start() {
        if (!Prefs.mouseKeyboard) { Log.i("input", "mouse and keyboard: Termux:X11's handling (setting off)"); return; }
        inputManager.registerInputDeviceListener(this, null);
        keyboardCapture();
        LorieView v = activity.getLorieView();
        // instead of Termux:X11's: its speed is in display densities, its wheel 100 units a click (lorie wants 120)
        v.setOnCapturedPointerListener((view, e) -> onCaptured(e) || termux.handleTouchEvent(v, v, e));
        Log.i("input", "mouse and keyboard to the game; connected: " + devices());
    }

    void stop() {
        if (Prefs.mouseKeyboard) inputManager.unregisterInputDeviceListener(this);
    }

    /** Android 16.1+: the system's keyboard shortcuts reach this window while it has focus. */
    private void keyboardCapture() {
        try {
            WindowManager.LayoutParams lp = activity.getWindow().getAttributes();
            WindowManager.LayoutParams.class.getMethod("setKeyboardCaptureEnabled", boolean.class).invoke(lp, true);
            activity.getWindow().setAttributes(lp);
            Log.i("input", "keyboard capture on: Android's shortcuts go to the game");
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.i("input", "no keyboard capture on Android " + Build.VERSION.RELEASE + " (it came with 16.1): " + e);
        }
    }

    /** The screen got or lost focus: with a mouse there, take it (also after Ctrl+Alt). */
    void focusChanged(boolean focused) {
        if (focused) releasedByHand = false;
        captureIfMouse();
    }

    /** The capture began or ended (GameActivity.onPointerCaptureChanged). */
    void captureChanged(boolean captured) {
        if (captured) releasedByHand = false;
    }

    /**
     * With focus, the X server connected and an external mouse there, the mouse is taken, unless Ctrl+Alt let it go
     * (then a click takes it back: Termux:X11 asks for the capture at each mouse click it gets).
     */
    void captureIfMouse() {
        if (Prefs.mouseKeyboard && !releasedByHand && activity.hasWindowFocus() && mousePresent())
            activity.setCapturingEnabled(true);   // (TouchInputHandler: nothing while the X server is not connected)
    }

    @Override public void onInputDeviceAdded(int id) {
        InputDevice d = InputDevice.getDevice(id);
        if (d == null || d.isVirtual()) return;
        Log.i("input", kind(d) + " connected: " + d.getName());
        if (isMouse(d)) { releasedByHand = false; captureIfMouse(); }
    }
    @Override public void onInputDeviceRemoved(int id) { rightButtons.delete(id); Log.i("input", "input device gone; connected: " + devices()); }
    @Override public void onInputDeviceChanged(int id) {}

    /**
     * Keys before the soft keyboard and from the KeyInterceptor service (GameActivity.handleKey), after the gamepad's.
     * @return true if used up here: a mouse's side buttons (Back, Forward: lorie has no buttons 8/9, and BAR none)
     */
    boolean onKey(KeyEvent e) {
        if (!Prefs.mouseKeyboard) return false;
        int code = e.getKeyCode();
        if (fromMouse(e) && (code == KeyEvent.KEYCODE_FORWARD
                || (code == KeyEvent.KEYCODE_BACK && rightButtons.get(e.getDeviceId()))))
            return true;   // (a mouse that never showed BUTTON_SECONDARY sends its right button as Back: Termux:X11 clicks)
        watchRelease(e);
        return false;
    }

    /** A lone Ctrl+Alt (CtrlAltRelease): the mouse goes back to Android. */
    private void watchRelease(KeyEvent e) {
        int code = e.getKeyCode();
        int key = code == KeyEvent.KEYCODE_CTRL_LEFT || code == KeyEvent.KEYCODE_CTRL_RIGHT ? CtrlAltRelease.CTRL
                : code == KeyEvent.KEYCODE_ALT_LEFT || code == KeyEvent.KEYCODE_ALT_RIGHT ? CtrlAltRelease.ALT
                : CtrlAltRelease.OTHER;
        if (e.getAction() == KeyEvent.ACTION_DOWN) {
            if (e.getRepeatCount() == 0) release.down(key);
        } else if (e.getAction() == KeyEvent.ACTION_UP && release.up(key)) {
            LorieView v = activity.getLorieView();
            if (v.hasPointerCapture()) {
                releasedByHand = true;
                v.releasePointerCapture();
                Log.i("input", "Ctrl+Alt: the mouse is Android's until the next click in the game");
            }
        }
    }

    /** Hover and wheel events of a mouse that is not captured. @return true if handled */
    boolean onGenericMotion(MotionEvent e) {
        if (!Prefs.mouseKeyboard || !e.isFromSource(InputDevice.SOURCE_MOUSE)) return false;
        seeButtons(e);
        if (e.getActionMasked() != MotionEvent.ACTION_SCROLL) return false;
        wheel(e);
        return true;
    }

    /** A mouse's button presses (the touch listener): which mice have a real right button. */
    void seeButtons(MotionEvent e) {
        if (Prefs.mouseKeyboard && (e.getButtonState() & MotionEvent.BUTTON_SECONDARY) != 0 && !rightButtons.get(e.getDeviceId())) {
            rightButtons.put(e.getDeviceId(), true);
            Log.i("input", "mouse right button seen: its Back key is a side button (ignored)");
        }
    }

    /** A captured mouse: relative motion, buttons, wheel. Touchpads stay with Termux:X11 (its touchpad gestures). */
    private boolean onCaptured(MotionEvent e) {
        if (!e.isFromSource(InputDevice.SOURCE_MOUSE_RELATIVE)) return false;
        LorieView v = activity.getLorieView();
        if (!v.connected()) return true;
        seeButtons(e);
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_SCROLL:
                wheel(e);
                return true;
            case MotionEvent.ACTION_MOVE:
            case MotionEvent.ACTION_HOVER_MOVE: {
                float dx = e.getX(), dy = e.getY();   // relative counts while captured
                for (int h = 0; h < e.getHistorySize(); h++) { dx += e.getHistoricalX(h); dy += e.getHistoricalY(h); }
                // one X screen pixel per count (a PC mouse on a monitor of the X screen's size), Termux:X11's speed
                // factor (Display settings) on top; the X server accelerates fast moves as on a desktop
                float speed = activity.prefs.capturedPointerSpeedFactor.get() / 100f;
                if (dx != 0 || dy != 0) v.sendMouseEvent(dx * speed, dy * speed, InputStub.BUTTON_UNDEFINED, false, true);
                break;
            }
            default:
        }
        int now = e.getButtonState();
        button(v, now, MotionEvent.BUTTON_PRIMARY, InputStub.BUTTON_LEFT);
        button(v, now, MotionEvent.BUTTON_TERTIARY, InputStub.BUTTON_MIDDLE);
        button(v, now, MotionEvent.BUTTON_SECONDARY, InputStub.BUTTON_RIGHT);
        captured = now;
        return true;
    }

    private void button(LorieView v, int now, int mask, int x11) {
        if ((captured & mask) == (now & mask)) return;
        boolean down = (now & mask) != 0;
        if (down) release.click();   // Ctrl+Alt+click is BAR's, not the release
        v.sendMouseEvent(0, 0, x11, down, true);
    }

    /** One wheel click = 120 units (Termux:X11 sent 100: every sixth click was lost). Signs as Termux:X11's. */
    private void wheel(MotionEvent e) {
        LorieView v = activity.getLorieView();
        if (v.connected())
            v.sendMouseWheelEvent(-WHEEL_CLICK * e.getAxisValue(MotionEvent.AXIS_HSCROLL), -WHEEL_CLICK * e.getAxisValue(MotionEvent.AXIS_VSCROLL));
    }

    /**
     * Android's own keys, no game key on a PC keyboard: they stay Android's on every path (the Home, Recents and All
     * apps keys, power, brightness, call, camera, assistant). Termux:X11 would send them to the X server once
     * keyboard capture or its KeyInterceptor service hands them to the app.
     */
    static boolean isAndroidKey(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_HOME: case KeyEvent.KEYCODE_APP_SWITCH: case KeyEvent.KEYCODE_ALL_APPS:
            case KeyEvent.KEYCODE_POWER: case KeyEvent.KEYCODE_SLEEP: case KeyEvent.KEYCODE_WAKEUP:
            case KeyEvent.KEYCODE_SOFT_SLEEP: case KeyEvent.KEYCODE_BRIGHTNESS_UP: case KeyEvent.KEYCODE_BRIGHTNESS_DOWN:
            case KeyEvent.KEYCODE_CALL: case KeyEvent.KEYCODE_ENDCALL: case KeyEvent.KEYCODE_CAMERA:
            case KeyEvent.KEYCODE_ASSIST: case KeyEvent.KEYCODE_VOICE_ASSIST: case KeyEvent.KEYCODE_NOTIFICATION:
                return true;
            default:
                return false;
        }
    }

    /** A key a mouse sent (its side buttons): captured, its events are SOURCE_MOUSE_RELATIVE, not SOURCE_MOUSE. */
    static boolean fromMouse(KeyEvent e) {
        return e.isFromSource(InputDevice.SOURCE_MOUSE) || e.isFromSource(InputDevice.SOURCE_MOUSE_RELATIVE);
    }

    private static boolean isMouse(InputDevice d) {
        return d != null && !d.isVirtual() && d.supportsSource(InputDevice.SOURCE_MOUSE) && TouchInputHandler.isExternal(d);
    }

    private static boolean mousePresent() {
        for (int id : InputDevice.getDeviceIds()) if (isMouse(InputDevice.getDevice(id))) return true;
        return false;
    }

    private static String kind(InputDevice d) {
        boolean keyboard = d.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC;
        boolean mouse = d.supportsSource(InputDevice.SOURCE_MOUSE);
        boolean touchpad = d.supportsSource(InputDevice.SOURCE_TOUCHPAD);
        return keyboard && mouse ? "keyboard+mouse" : keyboard ? "keyboard" : touchpad ? "touchpad" : mouse ? "mouse"
                : ControllerBridge.isGamepad(d) ? "gamepad" : "input device";
    }

    /** The external keyboards, mice and pads, for the log. */
    private static String devices() {
        StringBuilder sb = new StringBuilder();
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice d = InputDevice.getDevice(id);
            if (d == null || d.isVirtual() || !TouchInputHandler.isExternal(d)) continue;
            sb.append(sb.length() == 0 ? "" : ", ").append(kind(d)).append(' ').append(d.getName());
        }
        return sb.length() == 0 ? "none" : sb.toString();
    }
}
