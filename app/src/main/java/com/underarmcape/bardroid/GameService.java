package com.underarmcape.bardroid;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Foreground service that owns the long-running processes: the installer, the X server and the engine
 * (inside proot). Being a foreground service keeps Android from freezing the container while GameActivity
 * (the X display) is in front, and keeps a wake lock so the game is not suspended mid-match.
 */
public class GameService extends Service {
    public static final String ACTION_INSTALL = "bardroid.INSTALL";
    public static final String ACTION_PLAY = "bardroid.PLAY";        // extra "mode": skirmish | lobby | glcheck | shell
    public static final String ACTION_STOP = "bardroid.STOP";
    public static final String EXTRA_MODE = "mode";

    private static final String CHANNEL = "bardroid";
    private static volatile String status = "idle";
    private static volatile boolean busy;
    /** The app is being closed: no more notification updates, no launcher popping up. */
    private static volatile boolean closing;

    private Paths paths;
    private XServer xserver;
    private VirglServer virgl;
    private Proc engine;
    private Installer installer;
    private volatile Updater updater;
    private PowerManager.WakeLock wakeLock;
    private Thread worker;

    public static String status() { return status; }
    public static boolean busy() { return busy; }
    /** BAR is loading: the engine started, the game ("finished loading") or the lobby (its BAR Droid widget) not up yet
     *  (GameActivity's Free memory button). */
    public static boolean loading() { return loading; }
    /** The shape launch-bar.sh was told at the engine's start (BARDROID_PORTRAIT; null: none yet): LoadPictures. */
    static volatile Boolean startedUpright;
    private static volatile boolean loading;
    /**
     * The loading bar's words and how far it is, as BAR's loading screen has them (luaintro/addons/main.lua: the
     * engine's load messages, "[LoadScreen::SetLoadMessage] text=...", and its stage table), for GameActivity's upright
     * bar: BAR's is a band 60 % of the width there with its words sized by the screen's height, cut off at both ends
     * (Kailil, 2026-11-11: "The words must fit in the loading bar ... make the bar longer").
     */
    public static String loadMessage() { return loadMessage; }
    private static volatile String loadMessage = "";
    /** A game's loading screen is up (the engine made one): not the lobby's first load, which has no bar. */
    public static boolean loadScreen() { return loadScreen; }
    private static volatile boolean loadScreen;
    /** 0..1: the stage's start, moving on through the stage (BAR's own table) while it lasts. */
    public static float loadProgress() {
        float low = loadLow, high = loadHigh;
        float t = (android.os.SystemClock.elapsedRealtime() - loadStageAt) / 8000f;
        return low + (high - low) * Math.max(0f, Math.min(1f, t));
    }
    private static volatile float loadLow, loadHigh;
    private static volatile long loadStageAt;
    private static final String LOAD_MESSAGE = "[LoadScreen::SetLoadMessage] text=\"";
    // (BAR's progressByLastLine, its stage's start and end in %)
    private static final Object[][] LOAD_STAGES = {
            {"Loading Map", 0, 10}, {"Parsing Map Information", 7, 15}, {"Loading GameData Definitions", 10, 20},
            {"Creating QuadField and CEGs", 13, 22}, {"Creating Unit Textures", 16, 25}, {"Creating Sky", 19, 35},
            {"Loading Weapon Definitions", 22, 40}, {"Loading Unit Definitions", 25, 45},
            {"Loading Feature Definitions", 29, 45}, {"Loading Models and Textures", 33, 50},
            {"Loading Map Tiles", 38, 55}, {"Loading Square Textures", 43, 55}, {"Creating Projectile Textures", 48, 60},
            {"Creating Water", 54, 65}, {"PathCosts", 58, 65}, {"[LoadFinalize] finalizing PFS", 62, 65},
            {"Loading LuaRules", 69, 75}, {"Loading LuaUI", 82, 85}, {"Loading Skirmish AIs", 90, 95},
            {"Finalizing", 100, 100}};

    /** An engine output line: a load message for the upright loading bar. */
    static void loadLine(String line) {
        int at = line.indexOf(LOAD_MESSAGE);
        if (at < 0) return;
        String text = line.substring(at + LOAD_MESSAGE.length());
        int end = text.lastIndexOf('"');
        if (end >= 0) text = text.substring(0, end);
        loadMessage = text;
        for (Object[] s : LOAD_STAGES) {
            if (text.startsWith((String) s[0])) {
                loadLow = (Integer) s[1] / 100f;
                loadHigh = (Integer) s[2] / 100f;
                loadStageAt = android.os.SystemClock.elapsedRealtime();
                break;
            }
        }
    }

    /**
     * Joining a game hosted elsewhere: the engine's pre-game screen, "Waiting for server response" (Kailil, 2026-11-11,
     * an online game joined upright: "the loading screen there is not mobile formatted. Also free memory button should be
     * here too"), from the engine's "[CPreGame] using server IP" (not this phone's own server: a local game's pre-game
     * is over in a moment) to its loading screen. The server's address; whether the game's data has come (then the
     * engine checks its files and loads).
     */
    public static boolean preGame() { return preGameHost != null; }
    public static String preGameHost() { String h = preGameHost; return h == null ? "" : h; }
    public static boolean preGameData() { return preGameData; }
    private static volatile String preGameHost;
    private static volatile boolean preGameData;

    private static void loadReset(boolean screen) {
        preGameHost = null;
        preGameData = false;
        loadScreen = screen;
        loadMessage = "";
        loadLow = loadHigh = 0f;
        loadStageAt = android.os.SystemClock.elapsedRealtime();
    }
    /** This game was closed by the app after the GPU driver's fault (DriverWatch): its end is no low-memory kill. */
    private volatile boolean driverLost;
    /** Why the last game ended when the player did not end it (the launcher shows it); null: nothing to say. */
    public static String exitNote() { return exitNote; }
    private static volatile String exitNote;
    /** ApplicationExitInfo's REASON_ numbers in words (0 to 16, Android 11 to 13). */
    private static final String[] EXIT_REASONS = { "reason unknown", "the app exited", "a signal", "low memory", "a crash",
            "a native crash", "not responding", "start-up failed", "a permission changed", "too many resources used",
            "force stopped", "stopped by the user", "a process it needs ended", "another reason", "frozen",
            "the app was turned off", "an app update" };

    /** (how to close the other apps, not only that: an app may not close them itself, Android 14+) */
    private static String lowMemoryNote(android.content.Context c) {
        boolean galaxy = "samsung".equalsIgnoreCase(android.os.Build.MANUFACTURER);
        // (what happened, then on a line of its own what to do: the launcher shows that line as an explanation, smaller
        // and grey; four amber lines read as one long warning, dev phone 2026-11-11)
        return "Android closed the game: the phone ran out of memory.\nClose the other apps (Recents, Close all"
                + (galaxy ? "; or Settings, Device care, Memory, Clean now" : "") + ") and try again"
                + (LauncherActivity.lowRam(c) ? " (an 8 GB phone has little to spare in a game)." : ".");
    }

    /**
     * At the app's start (Android 11+): Android ended the app's last process for lack of memory while it was in front,
     * as on an 8 GB phone when the game loads, where the app goes with the engine (2026-10-29: the player only saw the
     * app start again). The launcher says so, once per such end. True when there is something to say.
     */
    private static boolean exitLogged;
    static boolean noteLowMemoryExit(android.content.Context c) {
        if (android.os.Build.VERSION.SDK_INT < 30 || busy) return false;
        android.app.ActivityManager am = c.getSystemService(android.app.ActivityManager.class);
        if (am == null) return false;
        java.util.List<android.app.ApplicationExitInfo> exits;
        try { exits = am.getHistoricalProcessExitReasons(c.getPackageName(), 0, 1); } catch (Exception e) { return false; }
        if (exits.isEmpty()) return false;
        android.app.ApplicationExitInfo e = exits.get(0);
        if (!exitLogged) {   // (once per process: how the app's last run ended, for the shared logs)
            exitLogged = true;
            int r = e.getReason();   // (the cause in words for the launcher's log box; Android's own words in the shared logs)
            // (", in the background": the app idle there, no game running; "(low memory)" alone read as a game killed in a
            // review of the Fold7's log, 2026-11-17: the app had been left in the background for seven minutes)
            boolean behind = e.getImportance() > android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE;
            Log.i("app", "the last run ended " + new java.text.SimpleDateFormat("MMM d HH:mm:ss", java.util.Locale.US)
                    .format(new java.util.Date(e.getTimestamp())) + " (" + (r >= 0 && r < EXIT_REASONS.length ? EXIT_REASONS[r] : "reason " + r)
                    + (behind ? ", in the background" : "")
                    + ")");   // (in brackets: "09:08:08: force stopped" read as a fourth number of the time, dev phone 2026-11-12)
            Log.detail("app", "the last run's exit: " + e.getDescription() + "; reason " + r + ", importance " + e.getImportance());
        }
        if (e.getReason() != android.app.ApplicationExitInfo.REASON_LOW_MEMORY
                || e.getImportance() > android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE
                || e.getTimestamp() <= Prefs.lowMemoryExitSeen(c)) return false;
        Prefs.setLowMemoryExitSeen(c, e.getTimestamp());
        exitNote = lowMemoryNote(c);
        Log.i("app", "the last run ended for lack of memory (importance " + e.getImportance() + "): " + exitNote.replace('\n', ' '));
        return true;
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    /**
     * Swiping the game away in the recent-apps screen closes the app, like Stop in the notification. Android also
     * reports tasks the app removes itself (StartActivity handing over to the game): only the game's task counts, and
     * not once the app has closed the game's screen itself (closeDisplay, a game that ended): that read "game removed
     * from recent apps" after every game and turned its result into "stopped" (a failed lobby's launcher said
     * "Ready", dev phone, 2026-11-03).
     */
    private volatile boolean displayClosedByApp;
    @Override
    public void onTaskRemoved(Intent rootIntent) {
        android.content.ComponentName c = rootIntent != null ? rootIntent.getComponent() : null;
        if (c != null && GameActivity.class.getName().equals(c.getClassName()) && !displayClosedByApp) {
            Log.i("svc", "game removed from recent apps: closing");
            closing = true;
            closeGently();
        }
        super.onTaskRemoved(rootIntent);
    }

    /**
     * How long the player's Stop or swipe waits for the engine's own quit before the kill (Proc.endEngine): a 2-minute
     * skirmish took 7.7 s on the dev phone (BAR's quit dialog's second ask 1 s in, its Lua and the rest ~5 s, 2026-11-18);
     * a long game's replay is compressed as it ends too. Nothing is on the screen meanwhile.
     */
    private static final long ENGINE_QUIT_MS = 20000;
    /** After that, how long launch-bar.sh has to end by itself (its checks and the infolog's copy: well under a second). */
    private static final long SCRIPT_END_MS = 5000;

    /**
     * The player's Stop or swipe: the engine asked to quit first, so the game's replay is written (Proc.endEngine; a
     * killed game left an empty one, the Fold7 2026-11-18), then everything stopped as before. Off the main thread: the
     * wait is up to ENGINE_QUIT_MS.
     */
    private volatile boolean closingGently;
    /** The engine plays a replay (its "ReadDataFromDemo"), not a game it records ("recording demo to"). */
    private volatile boolean playingReplay;
    private void closeGently() {
        // (a second Stop meanwhile: one quit is on its way; a third SIGTERM after the engine has shut SDL down ends it
        // at once)
        if (closingGently) return;
        closingGently = true;
        // (the launcher said "Skirmish running" for the 5 s of the quit, BAR's quit dialog flashing in its picture-in-
        // picture: the Stop looked untaken; dev phone 2026-11-18)
        if (!Proc.enginePids().isEmpty()) {
            // (still loading: no game in it yet, its replay a header only; "saving the replay" over the loading screen,
            // dev phone 2026-11-18; and no quit waited for, below)
            setStatus(loading || playingReplay ? "closing" : "closing: saving the replay");
            // (setStatus leaves the notification once closing: it said "Skirmish running", Stop and all, for the
            // quit's seconds after a swipe or a Stop; dev phone 2026-11-18)
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.notify(1, notification(status));
        }
        // (still loading: stopped at once, as before. The engine's quit waits for the loading's end, nothing to keep yet:
        // a Stop over the loading screen took 10 s once and ran past the 20 s another time, a first start after an
        // install; dev phone 2026-11-18)
        boolean whileLoading = loading;
        Thread t = new Thread(() -> {
            try {
                boolean quit = !whileLoading && Proc.endEngine(ENGINE_QUIT_MS);
                // (and launch-bar.sh after the engine, its last seconds: the app's widgets' error lines to the launcher, the
                // infolog's copy into logs/ for Share logs; killed with the engine, the Fold7's newest copy was of 11-10,
                // every game since closed by a swipe or Stop; dev phone 2026-11-18)
                Proc e = engine;
                long until = android.os.SystemClock.elapsedRealtime() + SCRIPT_END_MS;
                while (quit && e != null && e.isAlive() && android.os.SystemClock.elapsedRealtime() < until) {
                    try { Thread.sleep(100); } catch (InterruptedException x) { Thread.currentThread().interrupt(); break; }
                }
                if (quit && e != null) Log.i("svc", e.isAlive() ? "launch-bar.sh still running: stopped" : "launch-bar.sh ended after the engine");
                stopEverything();
                close();
            } finally {
                closingGently = false;
            }
        }, "svc-close");
        t.start();
    }

    /** Ends this foreground service and its notification. */
    private void close() {
        closing = true;
        stopForeground(STOP_FOREGROUND_REMOVE);
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.cancel(1);
        stopSelf();
    }

    @Override
    public void onCreate() {
        super.onCreate();
        paths = BarApp.get().paths();
        xserver = new XServer(paths);
        virgl = new VirglServer(paths);
        createChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;
        String mode = intent != null && intent.getStringExtra(EXTRA_MODE) != null ? intent.getStringExtra(EXTRA_MODE) : "skirmish";
        if (!busy) closing = false;
        // what is starting, before the notification goes up (it read "Idle", then the launcher "Installed, idle", for a
        // second or two after Play: the last game's word; dev phone, 2026-11-03)
        if (!busy && ACTION_PLAY.equals(action)) setStatus("starting (" + mode + ")");
        else if (!busy && ACTION_INSTALL.equals(action)) setStatus("installing");
        startForeground(1, notification(status));
        if (ACTION_STOP.equals(action)) { closing = true; closeGently(); return START_NOT_STICKY; }
        if (busy) { Log.i("svc", "busy; ignoring " + action); return START_NOT_STICKY; }
        if (ACTION_INSTALL.equals(action)) runAsync(this::install);
        else if (ACTION_PLAY.equals(action)) runAsync(() -> play(mode));
        return START_NOT_STICKY;
    }

    private void runAsync(Runnable r) {
        busy = true;
        acquireWakeLock();
        worker = new Thread(() -> {
            try { r.run(); }
            finally { busy = false; releaseWakeLock(); }
        }, "bardroid-worker");
        worker.start();
    }

    private void install() { install(true); }

    /**
     * The install's steps, and with updateBar BAR's own update too (Install / Update, and a first install: with automatic
     * updates off too). A start that only fetches a step an app update added (a newer Mesa) leaves BAR to its own check
     * (play): it forced an online update at every start until the new Mesa came, 30 s waits offline (review 2026-11-16).
     */
    private void install(boolean updateBar) {
        setStatus("installing");
        installer = new Installer(this, paths);
        try {
            installer.installAll((step, detail, pct) -> setStatus("install " + step + ": " + detail + (pct >= 0 ? " (" + pct + "%)" : "")));
            if (updateBar) update(true);
            setStatus("installed");
        } catch (InterruptedException e) {
            setStatus("install stopped");
            Thread.currentThread().interrupt();   // (the start that called it stops too: play)
        } catch (Exception e) {
            Log.e("install", "failed", e);
            setStatus("install failed: " + e.getMessage());
        }
    }

    /** BAR's PC launcher's update, then the Android layer on top (docs/UPDATES.md); its status shows on the splash. */
    private Updater update(boolean online) throws InterruptedException {
        Updater u = updater = new Updater(paths);
        u.check(online, detail -> setStatus("update: " + detail));
        return u;
    }

    /** The downloaded maps kept under the launcher's limit (MapStore): before an engine starts, never under one. */
    private void pruneMaps(String keep) {
        if (Prefs.mapCapMb <= 0) return;
        try {
            for (String gone : MapStore.prune(paths.bar, (long) Prefs.mapCapMb << 20, keep)) {
                Log.i("maps", "over " + Prefs.mapCapMb + " MB of maps: removed " + gone);
            }
        } catch (RuntimeException e) {
            Log.e("maps", "map storage", e);
        }
    }

    private void play(String mode) {
        updater = null;
        exitNote = null;
        Installer inst = new Installer(this, paths);
        if ((!inst.isInstalled() || inst.mesaOutdated()) && !"shell".equals(mode)) {
            // A first install, or a step an app update added or changed (e.g. a newer Mesa: fetched when it can be, the
            // installed one running meanwhile): run what is missing.
            install(!inst.isInstalled());
            inst = new Installer(this, paths);
            // (Stop during it ends the start: the older Mesa still counts as installed, and the game went on after Stop,
            // the service already gone; review 2026-11-16)
            if (closing || Thread.currentThread().isInterrupted() || !inst.isInstalled()) return;
        }
        boolean showLauncher = true;
        try {
            inst.refreshHostFiles();                        // scripts/assets of this app version
            boolean bench = "bench".equals(mode);
            try { inst.removeGamepadGame(); }   // (v0.8.5's game, out of the app since 2026-11-06: one installed earlier goes)
            catch (java.io.IOException e) { Log.e("svc", "the controller game's files", e); }
            inst.slimContainer((step, detail, percent) -> setStatus("container: making room"));
            Updater up = "lobby".equals(mode) || "skirmish".equals(mode) ? update(Prefs.autoUpdate) : null;
            inst.writeGameFiles();                          // refresh settings + start script
            if (up != null) up.applyLauncherSettings();
            // The benchmark (BAR's "Benchmark BAR" scenario, unattended) runs what is installed, no update first, so
            // runs compare; its map comes once from BAR's servers. So does a skirmish's: the launcher's map setting is
            // free text, and without its map the engine ends in 2 s (an 8 GB phone plays the benchmark's map by default,
            // Prefs.mapName, also where the first install fetched the bigger one).
            String map = bench ? Installer.BENCH_MAP : "skirmish".equals(mode) ? Prefs.mapName : null;
            pruneMaps(map != null ? map : Prefs.mapName);
            if (map != null && !inst.hasMap(map)) {
                setStatus((bench ? "benchmark" : "skirmish") + ": downloading " + map);
                int got = new Proot(paths).runScript("bench:map", "/opt/bardroid/setup-container.sh", new HashMap<>(),
                        java.util.Arrays.asList("map", map, Prefs.engineVersion));
                if (got != 0) {
                    exitNote = "Map \"" + map + "\" is not on the phone and did not download: check its name at Map"
                            + " (skirmish) below, and the connection.";
                    Log.i("svc", exitNote);
                    setStatus("no map");
                    return;
                }
            }
            setStatus("starting X server");
            xserver.start();
            if (!xserver.waitForSocket(15000)) { setStatus("X server did not start (see log)"); xserver.stop(); return; }
            if ("virpipe".equals(Prefs.mesaDriver)) {
                setStatus("starting GPU server (virgl)");
                virgl.start();
                if (!virgl.waitForSocket(10000)) { setStatus("virgl server did not start (see log)"); return; }
            }
            // Bring the display up (a hidden flag left by the last game screen must not hide this one)
            //noinspection ResultOfMethodCallIgnored
            paths.hiddenFlag().delete();
            //noinspection ResultOfMethodCallIgnored
            paths.floatingFlag().delete();
            //noinspection ResultOfMethodCallIgnored
            paths.catchupFlag().delete();
            //noinspection ResultOfMethodCallIgnored
            new java.io.File(paths.bar, "LuaUI/Config/bardroid_catchup.txt").delete();
            Intent ui = new Intent(this, GameActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            displayClosedByApp = false;
            startActivity(ui);

            setStatus("launching engine (" + mode + ")");
            boolean upright = Prefs.startsUpright(this);   // (turning with the phone: as it is held now)
            startedUpright = upright;
            SplashPicture.write(this, paths.bar, Prefs.engineVersion, upright);   // (launch-bar.sh: SplashScreenDir)
            Map<String, String> env = new HashMap<>();
            env.put("ENGINE_VER", Prefs.engineVersion);
            env.put("MODE", mode);
            env.put("DISPLAY", ":0");
            env.put("LOBBY_TAG", Prefs.lobbyTag);
            env.put("GAMEPAD_GAME", "0");   // (launch-bar.sh: the v0.8.5 game is gone; its controller game branch never runs)
            Prefs.putGpuEnv(env);
            env.put("BARDROID_AUDIO", Prefs.audio ? "1" : "0");
            env.put("BARDROID_PHONE_ENGINE", Prefs.phoneEngine ? "1" : "0");   // (launch-bar.sh; the launcher's Phone engine)
            env.put("BARDROID_PORTRAIT", upright ? "1" : "0");   // (launch-bar.sh: BAR's loading tips off upright)
            env.put("BARDROID_LAND_DOCK", Prefs.landDock ? "1" : "0");   // (launch-bar.sh: the touch dock sideways)
            env.put("BARDROID_FPS", Prefs.EMULATOR_BUILD ? "0" : String.valueOf(Prefs.fpsCap));   // libbardroid_pace.so; 0 = none
            // (the explicit Present fence is for the phone's lfdevs Mesa on KGSL; the emulator's virgl keeps Mesa's own path)
            if (Prefs.EMULATOR_BUILD) env.put("BARDROID_PRESENT_FENCE", "0");
            Proot proot = new Proot(paths);
            List<String> cmd = new ArrayList<>();
            cmd.add("/bin/bash"); cmd.add("/opt/bardroid/launch-bar.sh");
            long started;
            int rc;
            LobbyBridge bridge = null;
            LobbyBridge.removeConnectionFile(paths);
            if ("lobby".equals(mode) && Prefs.lobbyBridge) {
                bridge = new LobbyBridge(this, paths);
                try { bridge.start(); } catch (Exception e) { Log.e("svc", "lobby bridge not started", e); bridge = null; }
            }
            try {
                for (boolean again = false; ; again = true) {
                    env.put("ENGINE_VER", Prefs.engineVersion);
                    AudioPump audio = Prefs.audio ? new AudioPump(new java.io.File(paths.rootfsTmp, "bardroid-audio.fifo")) : null;
                    if (audio != null) audio.start();
                    // Stopped in every case: a pump left behind (Stop, a failed start) would read the next game's
                    // FIFO too and take half of its sound.
                    try {
                        loadReset(false);
                        loading = true;
                        playingReplay = false;
                        DriverWatch driver = new DriverWatch();
                        driverLost = false;
                        boolean[] hangLogged = {false};
                        engine = new Proc("engine").start(proot.command(env, cmd), proot.hostEnv(), paths.filesDir, line -> {
                            // (BAR's watchdog: where the engine is stuck, from the kernel's side; once a game, HangDump)
                            if (!hangLogged[0] && line.contains(DriverWatch.HUNG)) {
                                hangLogged[0] = true;
                                HangDump.dumpAsync();
                            }
                            // (a replay watched records nothing: the quit's status says no "saving the replay" then)
                            if (line.contains("ReadDataFromDemo")) playingReplay = true;
                            else if (line.contains("recording demo to")) playingReplay = false;
                            if (loading && (line.contains("finished loading") || line.contains("BAR Droid lobby touch"))) {
                                loading = false;
                                Log.i("svc", "loaded (the loading screen's Free memory button goes)");
                                refreshNotification();
                            }
                            // (joining a game hosted elsewhere: the pre-game screen, GameActivity's upright version of it)
                            String server = StatusText.preGameServer(line);
                            if (server != null) {
                                preGameHost = server;
                                preGameData = false;
                                Log.i("svc", "joining a game hosted elsewhere: the pre-game screen until it loads");
                            } else if (preGameHost != null && line.contains("[PreGame::GameDataReceived]")) {
                                preGameData = true;
                            } else if (preGameHost != null && (line.contains("BAR Droid lobby touch")
                                    || line.contains("server connection timeout"))) {
                                // (the join failed: back in the lobby, or the engine's own word on it shows)
                                preGameHost = null;
                                Log.i("svc", "the join ended before the game loaded: the engine's screen again");
                            }
                            // (a game the lobby starts loads in the same engine: loading again, the Free memory button,
                            // the upright tip and bar with it; before, only the engine's first load had them, Kailil,
                            // 2026-11-11: "Allow free memory button in this loading menu too")
                            if (line.contains("creating LoadScreen")) {
                                boolean was = loading;
                                if (!was) Log.i("svc", "a game loads (from the lobby): the loading screen's buttons again");
                                loadReset(true);
                                loading = true;
                                if (!was) refreshNotification();
                            }
                            if (loading) loadLine(line);
                            // (a replay that ends before its game began: its game closed by force before the engine
                            // wrote any of it, the file its start script only; the lobby lists it "time unknown", and it
                            // loaded to a still, empty map without a word, dev phone 2026-11-17: said on the screen)
                            if (line.contains("End of demo reached") && line.contains("[f=-000001]")) {
                                Log.i("svc", "a replay with no game in it: said on the screen");
                                new android.os.Handler(android.os.Looper.getMainLooper()).post(() ->
                                        android.widget.Toast.makeText(getApplicationContext(),
                                                "This replay is empty (cut off before its game began): tap Lobby to go back",
                                                android.widget.Toast.LENGTH_LONG).show());
                            }
                            // (the map a game loads on: its last use, for the map storage limit, MapStore)
                            String mapFile = MapStore.usedIn(line);
                            if (mapFile != null) MapStore.markUsed(paths.bar, mapFile);
                            // (the GPU driver's rare fault freezes the game for good: closed, and the launcher says why)
                            if (driver.onLine(line)) {
                                driverLost = true;
                                Log.e("svc", "the GPU driver refused the game's graphics and the game stopped responding: closing it");
                                Proc.killAll();
                            }
                        });
                        setStatus("running (" + mode + ")");
                        started = android.os.SystemClock.elapsedRealtime();
                        PerfLog perf = new PerfLog(this);
                        perf.start();
                        try { rc = engine.waitFor(); } finally { perf.stop(); }
                    } finally {
                        loading = false;
                        preGameHost = null;
                        if (audio != null) audio.stop();
                    }
                    Log.i("svc", "engine exited (" + rc + ")");   // (tools/phone-bench.ps1, phone-memory.ps1 read this line)
                    // (Stop's own kill is no error: it read "game ended with an error (137)" after the player's Stop)
                    // (closed by the app after the GPU driver's fault: the note under it says why, not "error (137): the log")
                    // (a SIGKILL from outside, Android's low-memory killer: its note says so; "error (137)" over it read
                    // as an error of the game's, and Android ending the whole app shows "Ready" with the same note,
                    // dev phone 2026-11-11)
                    setStatus(closing ? "stopped" : rc == 0 || driverLost || rc == 137 ? "game ended" : "game ended with an error (" + rc + ")");
                    String fatal = rc != 0 && !closing && !driverLost && rc != 137 ? engineFatal(paths) : null;
                    String coded = rc != 0 && !closing && !driverLost && fatal == null ? StatusText.exitCodeNote(rc) : null;
                    if (driverLost) {
                        exitNote = DriverWatch.note();
                        Log.i("svc", exitNote);
                    } else if (fatal != null) {   // (the engine's own message box, which the phone never shows)
                        exitNote = StatusText.engineFatalNote(fatal);
                        Log.i("svc", exitNote);
                    } else if (coded != null) {   // (an exit code of the engine's own, without a message)
                        exitNote = coded;
                        Log.i("svc", exitNote);
                    } else if (rc == 137 && !closing) {
                        // SIGKILL from outside: Android's low-memory killer (Stop and a game swiped away set closing
                        // first). Without a word the player only saw the launcher come back (an 8 GB phone, 2026-10-29).
                        exitNote = lowMemoryNote(this);
                        Log.i("svc", exitNote.replace('\n', ' '));
                    }
                    if (up != null && closing) {   // (the player's Stop or swipe: a set that ran is kept, Updater)
                        try { up.closedByPlayer(android.os.SystemClock.elapsedRealtime() - started); }
                        catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                        catch (RuntimeException e) { Log.e("update", "closed game not judged: " + e); }
                    }
                    if (up == null || closing) break;
                    // The first start of a BAR update failed fast: once more on the last good version, same display.
                    Updater.Result r = up.launchEnded(rc, android.os.SystemClock.elapsedRealtime() - started);
                    if (again || r != Updater.Result.ROLLED_BACK) break;
                    setStatus("BAR update failed to start: back to engine " + Prefs.engineVersion);
                    inst.writeGameFiles();
                    up.applyLauncherSettings();
                }
            } finally {
                if (bridge != null) bridge.stop();
            }
            if ("glcheck".equals(mode)) {   // (its answer was only in the log box at the bottom: the launcher says it)
                exitNote = glCheckNote(paths, started);
                Log.i("svc", exitNote);
            } else if ("bench".equals(mode) && !closing && rc == 0) {   // (so is the benchmark's: its ms per frame)
                exitNote = benchNote(paths);
                Log.i("svc", exitNote);
            }
            if ("lobby".equals(mode)) {   // a lobby that dies at once is not started again from the app icon
                // (a lobby the app closed for the GPU driver's fault is no broken lobby: the icon still opens it next time;
                // nor one the player closed (Stop, swiped away: killed, rc not 0) or Android's low-memory killer ended:
                // the Fold7's icon showed the launcher after a lobby closed early, 2026-11-10)
                Prefs.setLobbyFailedFast(this, rc != 0 && rc != 137 && !closing && !driverLost
                        && android.os.SystemClock.elapsedRealtime() - started < 60_000);
                showLauncher = rc != 0;   // quitting the lobby closes the app; a failure shows the launcher and its log
            }
        } catch (InterruptedException e) {
            setStatus("stopped");
        } catch (Exception e) {
            Log.e("svc", "play failed", e);
            setStatus("launch failed: " + e.getMessage());
        } finally {
            virgl.stop();
            xserver.stop();
            engine = null;
            closeDisplay(showLauncher && !closing);
            // nothing left running in any case (the launcher shown or not; the status stays for it): no notification
            // left behind ("Game ended" stayed once onTaskRemoved no longer took the app's own closing for a swipe)
            close();
        }
    }

    /** Closes the X display activity (Termux:X11's ACTION_STOP) and, if asked, brings the launcher back with the result. */
    private void closeDisplay(boolean showLauncher) {
        displayClosedByApp = true;
        sendBroadcast(new Intent(com.termux.x11.MainActivity.ACTION_STOP).setPackage(getPackageName()));
        if (!showLauncher) return;
        try {
            startActivity(new Intent(this, LauncherActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
        } catch (Exception e) { Log.e("svc", "could not reopen the launcher", e); }
    }

    private void stopEverything() { stopEverything(true); }

    /** say: the status becomes "stopped" (not when this service ends itself after a game: its result stays). */
    private void stopEverything(boolean say) {
        if (installer != null) installer.cancel();
        if (updater != null) updater.cancel();
        if (engine != null) engine.kill();
        Proc.killAll();          // container setup steps (proot) started by the installer
        xserver.stop();
        if (worker != null) worker.interrupt();
        if (say) setStatus("stopped");
    }

    /** The notification again for the same status (its title says loading or running: notification). */
    private void refreshNotification() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null && !closing) nm.notify(1, notification(status));
    }

    private void setStatus(String s) {
        if (s.equals(status)) return;   // (one Stop passes the action, the game thread and onDestroy: "stopped" three times)
        status = s;
        Log.i("svc", s);
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null && !closing) nm.notify(1, notification(s));
    }

    private void acquireWakeLock() {
        PowerManager pm = getSystemService(PowerManager.class);
        if (pm != null && wakeLock == null) {
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "bardroid:game");
            wakeLock.acquire();
        }
    }
    private void releaseWakeLock() { if (wakeLock != null && wakeLock.isHeld()) wakeLock.release(); wakeLock = null; }

    // (named for what it is in Android's notification settings, where "BAR Droid", the project's name, meant nothing to
    // a player of "Beyond All Reason"; made again each start, so an existing channel takes the name: Android keeps the
    // player's own choices for it, its importance and sound)
    private void createChannel() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null) return;
        NotificationChannel c = new NotificationChannel(CHANNEL, getString(R.string.channel_game), NotificationManager.IMPORTANCE_LOW);
        c.setDescription(getString(R.string.channel_game_desc));
        nm.createNotificationChannel(c);
    }

    /**
     * GL check's answer in a line (launch-bar.sh writes glxinfo's to $BAR/logs/glcheck-<driver>.txt): the renderer and
     * the OpenGL version, or that there was none.
     */
    static String glCheckNote(Paths paths, long startedElapsed) {
        java.io.File newest = null;
        java.io.File[] files = new java.io.File(paths.bar, "logs").listFiles((d, n) -> n.startsWith("glcheck-") && n.endsWith(".txt"));
        for (java.io.File f : files == null ? new java.io.File[0] : files)
            if (newest == null || f.lastModified() > newest.lastModified()) newest = f;
        long startedWall = System.currentTimeMillis() - (android.os.SystemClock.elapsedRealtime() - startedElapsed);
        if (newest == null || newest.lastModified() < startedWall - 5000) return "GL check: no result (see the log)";
        String renderer = null, version = null;
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(newest))) {
            for (String line; (line = r.readLine()) != null; ) {
                if (line.startsWith("OpenGL renderer string:")) renderer = line.substring(23).trim();
                else if (line.startsWith("OpenGL version string:")) version = line.substring(22).trim();
            }
        } catch (java.io.IOException e) { return "GL check: no result (see the log)"; }
        if (renderer == null) return "GL check: no OpenGL from the GPU (see the log)";
        renderer = StatusText.gpuName(renderer);   // ("FD740": Freedreno's name for the Adreno 740)
        if (version == null) return "GL check: " + renderer;
        // ("4.3 (Compatibility Profile) Mesa 27.0.0-devel (git-6f90e92dfd)": the numbers; the rest is in the log)
        java.util.regex.Matcher mesa = java.util.regex.Pattern.compile("Mesa (\\S+)").matcher(version);
        // (each name kept with its number, no-break spaces and hyphens: the launcher broke the line between "Mesa" and
        // "27.0.0-devel", dev phone 2026-11-17)
        return "GL check: " + renderer + ", OpenGL " + version.split(" ")[0]
                + (mesa.find() ? ", Mesa " + mesa.group(1).replace('-', '‑') : "");
    }

    /**
     * BAR's benchmark in a line, from its results in this run's infolog ("Sim 1801 frames, 54.08ms per frame, ..."; the
     * last of each, as tools/phone-bench.ps1 reads them): the main thread's ms per frame for Sim, Draw and Update.
     */
    static String benchNote(Paths paths) {
        java.util.regex.Pattern line = java.util.regex.Pattern.compile("\\] (Sim|Draw|Update) \\d+ frames, ([\\d.]+)ms per frame");
        java.util.Map<String, String> ms = new java.util.HashMap<>();
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(new java.io.File(paths.bar, "infolog.txt")))) {
            for (String l; (l = r.readLine()) != null; ) {
                java.util.regex.Matcher m = line.matcher(l);
                if (m.find()) ms.put(m.group(1), m.group(2));
            }
        } catch (java.io.IOException ignored) {}
        if (!ms.containsKey("Sim")) return "Benchmark: no results in the game's log (it ended before them)";
        java.util.List<String> parts = new java.util.ArrayList<>();
        for (String k : new String[]{"Sim", "Draw", "Update"})
            if (ms.containsKey(k)) parts.add(k + " " + ms.get(k));
        return "Benchmark, ms per frame: " + String.join(", ", parts);
    }

    /**
     * The engine's fatal error in this run's infolog (StatusText.engineFatal), the last one; null if there is none. A
     * message over several lines ("Errors:" and the content errors under it) is read up to its closing quote.
     */
    static String engineFatal(Paths paths) {
        String found = null;
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(new java.io.File(paths.bar, "infolog.txt")))) {
            for (String l; (l = r.readLine()) != null; ) {
                if (l.contains("[ExitSpringProcess] errorMsg=\"")) {
                    StringBuilder all = new StringBuilder(l);
                    for (int n = 0; n < 20 && all.indexOf("\" msgCaption=") < 0; n++) {
                        String next = r.readLine();
                        if (next == null) break;
                        all.append('\n').append(next);
                    }
                    l = all.toString();
                }
                String m = StatusText.engineFatal(l);
                if (m != null) found = m;
            }
        } catch (java.io.IOException ignored) {}
        return found;
    }

    // (the status is the title: Android's header above it names the app; a "BAR Droid" title under "Beyond All Reason"
    // named it twice, two ways)
    private Notification notification(String status) {
        // a tap: back to the game while one runs (as the app icon, StartActivity; it opened the launcher, with the game
        // left in its floating window), else the launcher (installing, updating, a game that ended)
        boolean game = status != null && status.startsWith("running");
        Intent open = game ? new Intent(this, GameActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                : new Intent(this, LauncherActivity.class);
        PendingIntent pi = PendingIntent.getActivity(this, game ? 2 : 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Intent stop = new Intent(this, GameService.class).setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(this, 1, stop, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder b = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)   // (the app's marker; it was Android's media "play" triangle)
                // (loading as the launcher says it: the notification said "Skirmish running" over the loading screen,
                // dev phone 2026-11-18; refreshNotification as the loading ends)
                .setContentTitle(StatusText.forPlayers(status, loading))
                // (while a game runs, what the tap and the button do: the title alone left the line under it empty)
                .setContentText(game ? "Tap to return to the game; Stop ends it" : null)
                .setContentIntent(pi)
                .setOngoing(true);
        // (closing: no Stop, one is on its way; closeGently ignores another)
        if (status == null || !status.startsWith("closing")) {
            b.addAction(new Notification.Action.Builder(null, "Stop", stopPi).build());
        }
        return b.build();
    }

    @Override
    public void onDestroy() {
        stopEverything(!closing);   // (closing: Stop or a swipe said so already, or a game ended and its result stays)
        super.onDestroy();
    }

    public static void start(Context ctx, String action, String mode) {
        Intent i = new Intent(ctx, GameService.class).setAction(action);
        if (mode != null) i.putExtra(EXTRA_MODE, mode);
        if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i); else ctx.startService(i);
    }

    @SuppressWarnings("unused")
    private static int fgsType() { return Build.VERSION.SDK_INT >= 34 ? ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE : 0; }
}
