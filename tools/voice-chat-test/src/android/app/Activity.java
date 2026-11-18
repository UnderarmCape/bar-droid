package android.app;

import android.content.Context;
import android.content.pm.PackageManager;

/** Stand-in for Android's class, for tools/voice-chat-test: the microphone's permission and its requests, made up. */
public class Activity extends Context {
    public int permission = PackageManager.PERMISSION_GRANTED;
    public int requests;   // requestPermissions calls (Android's question shown)

    public int checkSelfPermission(String permission) { return this.permission; }

    public void requestPermissions(String[] permissions, int requestCode) { requests++; }

    public String getPackageName() { return "com.underarmcape.bardroid"; }
}
