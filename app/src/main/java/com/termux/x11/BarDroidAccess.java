package com.termux.x11;

import com.termux.x11.input.TouchInputHandler;

/** BAR Droid: reaches Termux:X11's package-private input handler, so GameActivity can pass on what it does not handle. */
public final class BarDroidAccess {
    private BarDroidAccess() {}

    public static TouchInputHandler inputHandler(MainActivity a) { return a.mInputHandler; }

    /**
     * A key's release was sent in LorieView's pre-IME pass: drop the extra release LorieView queued 50 ms later for keys
     * whose release some soft keyboards swallow (its post-IME dispatchKeyEvent drops it the same way). Re-pressed
     * within those 50 ms, Shift or Ctrl would otherwise be let go while held.
     */
    public static void keyReleaseSent(LorieView v, int keyCode) { v.keyReleaseHandler.removeMessages(keyCode); }
}
