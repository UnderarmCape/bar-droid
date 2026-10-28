package com.underarmcape.bardroid;

import android.os.Build;
import android.view.KeyEvent;
import android.view.WindowManager;

import com.termux.x11.LorieApp;
import com.termux.x11.MainActivity;
import com.termux.x11.utils.KeyInterceptor;
import com.termux.x11.utils.SamsungDexUtils;

/**
 * Android's, One UI's and DeX's keyboard shortcuts stay out of the game screen: the keys reach BAR instead. Kailil
 * (2026-10-27): "i want android to not hijack its inputs and listen for shortcuts and other things", then "mouse and
 * keyboard support works perfectly already. but i just want to make sure the android built in keyboard bindings and
 * shortcuts dont listen in on the bar session". So how keys and the mouse reach the X server is Termux:X11's, as
 * before; only who sees a key first changes. Launcher setting "Keyboard shortcuts go to the game"
 * (Prefs.captureShortcuts, on); off, Termux:X11's defaults.
 *
 * - Android 16.1+ keyboard capture: WindowManager.LayoutParams.setKeyboardCaptureEnabled (by reflection, compileSdk
 *   34), permission CAPTURE_KEYBOARD (normal: granted at install). Android's own shortcut handling (Meta for All apps,
 *   Alt+Tab, Ctrl+Space, Meta+letter, ...) runs before any app sees a key; with it, the focused game window gets them.
 * - Samsung's SemWindowManager.requestMetaKeyEvent (Termux:X11's "Intercept system shortcuts", dexMetaKeyCapture):
 *   One UI and DeX hand the Meta key and its combinations to the window.
 * - Keys go to the X server in LorieView's pre-IME pass (Termux:X11's "hardware keyboard scancodes workaround" off): the
 *   soft keyboard app never sees a hardware key, so its own shortcuts (Samsung Keyboard's Shift+Space or Ctrl+Space
 *   language switch) cannot act. The same Termux:X11 code sends the key either way (GameActivity.handleKey).
 * - Older Android: Termux:X11's KeyInterceptor accessibility service, renamed "Beyond All Reason keyboard shortcuts",
 *   switched on by the player (README); an accessibility service gets keys before Android's shortcut handling.
 *
 * What no app can block: touch gestures (Home and Recents swipes, the notification shade), the power key and its
 * chords. Kept Android's on purpose (isAndroidKey): the Home, Recents and All apps keys, power, brightness, call,
 * camera, assistant; volume and media keys keep Termux:X11's handling (Android's).
 */
final class KeyboardShortcuts {
    private KeyboardShortcuts() {}

    /**
     * Termux:X11's switches for the same things follow the setting; read in its onCreate, so called before it. Written
     * only when they differ (each write is a synchronous commit). Once: the build of 2026-10-27 21:01 (b148e59, mouse
     * capture and scancodes, withdrawn) set pointerCapture and preferScancodes; back to Termux:X11's defaults.
     */
    static void applyTermuxPrefs(MainActivity a) {
        com.termux.x11.Prefs p = ((LorieApp) a.getApplication()).getPrefs(a);
        boolean on = Prefs.captureShortcuts;
        if (p.dexMetaKeyCapture.get() != on) p.dexMetaKeyCapture.put(on);
        if (p.hardwareKbdScancodesWorkaround.get() == on) p.hardwareKbdScancodesWorkaround.put(!on);
        android.content.SharedPreferences sp = androidx.preference.PreferenceManager.getDefaultSharedPreferences(a);
        if (!sp.getBoolean("bardroid_no_mouse_capture_v1", false)) {
            if (p.pointerCapture.get()) p.pointerCapture.put(false);
            if (p.preferScancodes.get()) p.preferScancodes.put(false);
            sp.edit().putBoolean("bardroid_no_mouse_capture_v1", true).apply();
        }
    }

    /** After the window exists (GameActivity.onCreate). */
    static void start(MainActivity a) {
        if (!Prefs.captureShortcuts) { Log.i("input", "keyboard shortcuts: Android's (setting off)"); return; }
        String capture;
        try {
            WindowManager.LayoutParams lp = a.getWindow().getAttributes();
            WindowManager.LayoutParams.class.getMethod("setKeyboardCaptureEnabled", boolean.class).invoke(lp, true);
            a.getWindow().setAttributes(lp);
            capture = "keyboard capture on";
        } catch (ReflectiveOperationException | RuntimeException e) {
            capture = "no keyboard capture on Android " + Build.VERSION.RELEASE + " (it came with 16.1)";
        }
        Log.i("input", "keyboard shortcuts to the game: " + capture
                + (SamsungDexUtils.available() ? ", Samsung Meta key requested" : "")
                + (KeyInterceptor.isLaunched() ? ", accessibility service on" : ""));
    }

    /**
     * Android's own keys, no game key on a PC keyboard: they stay Android's on every path (the Home, Recents and All
     * apps keys, power, brightness, call, camera, assistant). Termux:X11 would send them to the X server once keyboard
     * capture or its KeyInterceptor service hands them to the app.
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
}
