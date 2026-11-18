package android.widget;

import android.content.Context;

// (a stand-in: the words a phone would show, in the log; LobbyBridge's StartNewSpring note, 2026-11-17)
public class Toast {
    public static final int LENGTH_SHORT = 0, LENGTH_LONG = 1;
    private final CharSequence text;
    private Toast(CharSequence text) { this.text = text; }
    public static Toast makeText(Context ctx, CharSequence text, int duration) { return new Toast(text); }
    public void show() { System.out.println("[test] toast: " + text); }
}
