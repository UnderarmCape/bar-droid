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
        applyDisplayDefaults();      // before LorieApp reads its preferences
        super.onCreate();
        instance = this;
        paths = new Paths(this);
        paths.mkdirs();
        Log.init(paths.logs);
        Prefs.load(this);
        Log.i("app", "BAR Droid " + BuildConfig.VERSION_NAME + " starting; nativeLibDir=" + paths.nativeLibDir);
    }

    /**
     * First run only: Termux:X11's display defaults suit a desktop, not a game. Full screen, landscape, no extra-keys
     * bar, screen kept on, taps as mouse clicks where the finger is, and a ~720p X screen (BAR at native phone
     * resolution is too heavy). Everything stays adjustable under "Display settings".
     */
    private void applyDisplayDefaults() {
        android.content.SharedPreferences sp = android.preference.PreferenceManager.getDefaultSharedPreferences(this);
        // Once, also for existing installs: leaving the game turns it into a floating window (Termux:X11's "PIP mode",
        // X screen size kept). A visible window is almost never killed for memory; a background app with a
        // notification is (a spectated match got LOW_MEMORY-killed). Switchable under Display settings.
        if (!sp.getBoolean("bardroid_pip_default_v1", false))
            sp.edit().putBoolean("PIP", true).putBoolean("bardroid_pip_default_v1", true).apply();
        if (sp.getBoolean("bardroid_display_defaults_v3", false)) return;
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        int shortSide = Math.min(dm.widthPixels, dm.heightPixels);
        // The emulator build renders on the CPU (llvmpipe): every pixel costs, so aim lower there.
        float targetLines = Prefs.EMULATOR_BUILD ? 540f : 720f;
        int scale = Math.max(100, Math.min(300, Math.round(shortSide * 100f / targetLines / 10f) * 10));
        sp.edit()
                .putBoolean("fullscreen", true)
                .putBoolean("hideCutout", true)
                .putString("forceOrientation", "landscape")
                .putBoolean("showAdditionalKbd", false)
                .putBoolean("additionalKbdVisible", false)
                .putBoolean("showIMEWhileExternalConnected", false)   // no soft keyboard popping up over the game
                .putString("screenIdleTimeout", "never")
                .putString("touchMode", "2")                    // simulated touchscreen
                .putString("displayResolutionMode", "scaled")
                .putInt("displayScale", scale)
                .putBoolean("bardroid_display_defaults_v3", true)
                .apply();
    }

    public static BarApp get() { return instance; }
    public Paths paths() { return paths; }
}
