package com.underarmcape.bardroid;

import android.os.Bundle;
import android.view.KeyEvent;
import android.view.MotionEvent;

import com.termux.x11.MainActivity;

/**
 * The game screen: Termux:X11's display/input activity, plus a gamepad bridge. Touch, mouse and keyboard
 * go to the X server exactly as in Termux:X11 (its preferences screen controls touch mode, scaling, etc.).
 * Gamepad/joystick events are intercepted here and sent to the engine's Lua over UDP instead.
 */
public class GameActivity extends MainActivity {
    private ControllerBridge pad;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        pad = new ControllerBridge(Prefs.controllerPort);
    }

    @Override public void onResume() { super.onResume(); pad.start(); }
    @Override public void onPause() { pad.stop(); super.onPause(); }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent ev) {
        if (pad != null && pad.onMotion(ev)) return true;
        return super.dispatchGenericMotionEvent(ev);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (pad != null && pad.onKey(event)) return true;
        return super.dispatchKeyEvent(event);
    }
}
