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

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        pad = new ControllerBridge(Prefs.controllerPort);
        touch = new RtsTouch(this);
        LorieView lorieView = getLorieView();
        View lorieParent = (View) lorieView.getParent();
        TouchInputHandler termux = BarDroidAccess.inputHandler(this);
        lorieParent.setOnTouchListener((v, e) -> {
            if (e.getAction() == MotionEvent.ACTION_DOWN)
                lorieParent.requestUnbufferedDispatch(e);   // as Termux:X11 does: no batching, less latency
            if (touch.handles(e)) return touch.onTouch(e);
            if (e.isFromSource(InputDevice.SOURCE_MOUSE)) touch.otherInput("mouse");
            return termux.handleTouchEvent(lorieParent, lorieView, e);
        });
        // Same as Termux:X11's callback, plus: the game window follows the X screen (fold / unfold).
        lorieView.setCallback((w, h, transform) -> {
            termux.handleInputTransformChanged(w, h, transform);
            screenW = w; screenH = h;
            prefer60Hz();
            touch.screenSize(w, h, refreshHz());
        });
        lorieView.resetRendererZoom();   // undo a magnifier pinch from Termux:X11's own touch handling
        prefer60Hz();
        // The refresh rate settles after a mode request or a fold: keep the widget's frame cap in step.
        getSystemService(DisplayManager.class).registerDisplayListener(displayListener, null);
    }

    private int screenW, screenH;
    private final DisplayManager.DisplayListener displayListener = new DisplayManager.DisplayListener() {
        @Override public void onDisplayAdded(int id) {}
        @Override public void onDisplayRemoved(int id) {}
        @Override public void onDisplayChanged(int id) { if (screenW > 0) touch.screenSize(screenW, screenH, refreshHz()); }
    };

    /**
     * The X server's vblank counts display frames and the game's swap interval counts vblanks, so the frame cap
     * depends on the refresh rate: ask for a 60 Hz mode of the current display (the widget adapts the interval to
     * whatever the display really runs at).
     */
    private void prefer60Hz() {
        Display d = getWindowManager().getDefaultDisplay();
        if (d == null) return;
        Display.Mode cur = d.getMode();
        WindowManager.LayoutParams lp = getWindow().getAttributes();
        int want = 0;
        for (Display.Mode m : d.getSupportedModes())
            if (m.getPhysicalWidth() == cur.getPhysicalWidth() && m.getPhysicalHeight() == cur.getPhysicalHeight()
                    && Math.abs(m.getRefreshRate() - 60f) < 1f) want = m.getModeId();
        if (lp.preferredDisplayModeId == want && lp.preferredRefreshRate == 60f) return;
        lp.preferredDisplayModeId = want;
        lp.preferredRefreshRate = 60f;
        getWindow().setAttributes(lp);
    }

    private int refreshHz() {
        Display d = getWindowManager().getDefaultDisplay();
        return d == null ? 60 : Math.round(d.getRefreshRate());
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

    @Override public void onResume() { super.onResume(); pad.start(); }
    @Override public void onPause() { pad.stop(); super.onPause(); }
    @Override protected void onDestroy() {
        getSystemService(DisplayManager.class).unregisterDisplayListener(displayListener);
        touch.close();
        super.onDestroy();
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent ev) {
        if (pad != null && pad.onMotion(ev)) {
            if (touch != null && padMoved(ev)) touch.otherInput("gamepad");
            return true;
        }
        if (touch != null && ev.isFromSource(InputDevice.SOURCE_MOUSE)) touch.otherInput("mouse");
        return super.dispatchGenericMotionEvent(ev);
    }

    /** A stick, trigger or d-pad pushed well past rest (a resting stick reports small values). */
    private static boolean padMoved(MotionEvent ev) {
        for (int axis : new int[]{MotionEvent.AXIS_X, MotionEvent.AXIS_Y, MotionEvent.AXIS_Z, MotionEvent.AXIS_RZ,
                MotionEvent.AXIS_HAT_X, MotionEvent.AXIS_HAT_Y, MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_RTRIGGER})
            if (Math.abs(ev.getAxisValue(axis)) > 0.5f) return true;
        return false;
    }

    /** A real keyboard's key (not the on-screen keyboard, the Back gesture or volume keys). */
    private static boolean physicalKeyboard(KeyEvent e) {
        InputDevice d = e.getDevice();
        return d != null && !d.isVirtual() && e.isFromSource(InputDevice.SOURCE_KEYBOARD)
                && d.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC;
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (pad != null && pad.onKey(event)) {
            if (touch != null && event.getAction() == KeyEvent.ACTION_DOWN) touch.otherInput("gamepad");
            return true;
        }
        // The touch HUD steps aside while a mouse, keyboard or gamepad is in use (it returns with the next touch).
        if (touch != null && physicalKeyboard(event)) touch.otherInput("keyboard");
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
