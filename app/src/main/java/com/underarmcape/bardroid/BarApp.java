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
        try {   // (an app update gives BAR's versions that failed here another try: Updater.forgetBadAfterAppUpdate)
            Updater.appInstalledAt = getPackageManager().getPackageInfo(getPackageName(), 0).lastUpdateTime;
        } catch (Exception ignored) {}
        Log.init(paths.logs);
        ExitRecord.install();               // (an uncaught exception's stack into launcher.log; RC 0.2.0 item 6)
        ExitRecord.readBack(this, paths.logs);   // (how the app's process ended last time, and its state then)
        ExitRecord.summary(this, "app started, screen " + ExitRecord.screen(this));
        Prefs.load(this);
        Updater.useInstalled(paths);   // the engine and tags of the last BAR update
        Log.i("app", "BAR Droid " + BuildConfig.VERSION_NAME + " starting");
        Log.detail("app", "nativeLibDir=" + paths.nativeLibDir);
    }

    /**
     * First run only: Termux:X11's display defaults suit a desktop, not a game. Full screen, landscape, no extra-keys
     * bar, screen kept on, taps as mouse clicks where the finger is, and the X screen's size: on phones the display at
     * 100% within GameActivity's caps (about 900p folded, 1080p unfolded on the Fold7), on the emulator ~540 lines.
     * Everything stays adjustable under "Display settings".
     */
    private void applyDisplayDefaults() {
        android.content.SharedPreferences sp = androidx.preference.PreferenceManager.getDefaultSharedPreferences(this);
        // Once, also for existing installs: leaving the game turns it into a floating window (Termux:X11's "PIP mode",
        // X screen size kept). A visible window is almost never killed for memory; a background app with a
        // notification is (a spectated match got LOW_MEMORY-killed). Switchable under Display settings.
        if (!sp.getBoolean("bardroid_pip_default_v1", false))
            sp.edit().putBoolean("PIP", true).putBoolean("bardroid_pip_default_v1", true).apply();
        // Once, also for existing installs: phones draw at 100% within GameActivity's caps (they used ~720 lines by the
        // display scale: 150% on the Fold7, 1680x720 folded; Kailil, 2026-10-28: "900p folded, and unfolded 1080p").
        if (!Prefs.EMULATOR_BUILD && !sp.getBoolean("bardroid_display_scale_v4", false))
            sp.edit().putInt("displayScale", 100).putBoolean("bardroid_display_scale_v4", true).apply();
        if (sp.getBoolean("bardroid_display_defaults_v3", false)) return;
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        int shortSide = Math.min(dm.widthPixels, dm.heightPixels);
        // The emulator build renders on the CPU (llvmpipe): every pixel costs, ~540 lines there.
        int scale = Prefs.EMULATOR_BUILD
                ? Math.max(100, Math.min(300, Math.round(shortSide * 100f / 540f / 10f) * 10)) : 100;
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

    /**
     * Termux:X11 posts a notification of its own while its screen is in front ("Termux:X11", high importance, its
     * preferences on a button), beside GameService's ("running (skirmish)", Stop; a tap opens the launcher): two for
     * one game in the shade (dev phone, 2026-11-03). GameService's stands for the game; Termux:X11's is not posted.
     */
    @Override
    public void onActivityResumed(com.termux.x11.MainActivity activity) { }

    public static BarApp get() { return instance; }
    public Paths paths() { return paths; }
}
