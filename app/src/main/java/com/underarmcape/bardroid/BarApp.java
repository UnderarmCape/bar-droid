package com.underarmcape.bardroid;

import com.termux.x11.LorieApp;

/**
 * Application class. Extends Termux:X11's LorieApp because the X-server library expects its Application
 * subclass to receive the ACTION_START broadcast from the server process and hand the connection to the
 * display activity.
 */
public class BarApp extends LorieApp {
    private static BarApp instance;
    private Paths paths;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        paths = new Paths(this);
        paths.mkdirs();
        Log.init(paths.logs);
        Prefs.load(this);
        Log.i("app", "BAR Droid " + BuildConfig.VERSION_NAME + " starting; nativeLibDir=" + paths.nativeLibDir);
    }

    public static BarApp get() { return instance; }
    public Paths paths() { return paths; }
}
