package com.termux.x11;

import com.termux.x11.input.TouchInputHandler;

/** BAR Droid: reaches Termux:X11's package-private input handler, so GameActivity can pass on what it does not handle. */
public final class BarDroidAccess {
    private BarDroidAccess() {}

    public static TouchInputHandler inputHandler(MainActivity a) { return a.mInputHandler; }
}
