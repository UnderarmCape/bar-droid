package com.underarmcape.bardroid;

/**
 * Ctrl and Alt pressed together, then let go with no other key or mouse button in between: the captured mouse goes
 * back to Android (MouseKeyboard). Ctrl+Alt with anything else (a key, a click) is BAR's. Plain Java, so the laptop
 * checks it on the JDK: tools/mouse-keyboard-test.ps1.
 */
final class CtrlAltRelease {
    static final int OTHER = 0, CTRL = 1, ALT = 2;
    private boolean ctrl, alt, other;

    /** A key went down (not an auto-repeat): CTRL, ALT or OTHER. */
    void down(int key) {
        if (!ctrl && !alt) other = false;   // a new combination starts
        if (key == CTRL) ctrl = true;
        else if (key == ALT) alt = true;
        else other = true;
    }

    /** A mouse button went down. */
    void click() { other = true; }

    /** A key went up. @return true if it ends a lone Ctrl+Alt (once per press) */
    boolean up(int key) {
        if (key == OTHER) return false;
        boolean lone = ctrl && alt && !other;
        if (key == CTRL) ctrl = false;
        else alt = false;
        if (lone) other = true;
        return lone;
    }
}
