package android.content;

import android.net.Uri;

public class Intent {
    public static final String ACTION_VIEW = "android.intent.action.VIEW";
    public static final int FLAG_ACTIVITY_NEW_TASK = 0x10000000;
    private final String action; private final Uri uri;
    public Intent(String action, Uri uri) { this.action = action; this.uri = uri; }
    public Intent addFlags(int f) { return this; }
    @Override public String toString() { return action + " " + uri; }
}
