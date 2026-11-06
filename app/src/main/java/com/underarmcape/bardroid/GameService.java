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
    private static volatile boolean loading;
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
        return "Android closed the game: the phone ran out of memory. Close the other apps (Recents, Close all"
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
            Log.i("app", "the last run ended " + new java.text.SimpleDateFormat("MMM d HH:mm:ss", java.util.Locale.US)
                    .format(new java.util.Date(e.getTimestamp())) + ": " + (r >= 0 && r < EXIT_REASONS.length ? EXIT_REASONS[r] : "reason " + r));
            Log.detail("app", "the last run's exit: " + e.getDescription() + "; reason " + r + ", importance " + e.getImportance());
        }
        if (e.getReason() != android.app.ApplicationExitInfo.REASON_LOW_MEMORY
                || e.getImportance() > android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE
                || e.getTimestamp() <= Prefs.lowMemoryExitSeen(c)) return false;
        Prefs.setLowMemoryExitSeen(c, e.getTimestamp());
        exitNote = lowMemoryNote(c);
        Log.i("app", "the last run ended for lack of memory (importance " + e.getImportance() + "): " + exitNote);
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
            stopEverything();
            close();
        }
        super.onTaskRemoved(rootIntent);
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
        if (ACTION_STOP.equals(action)) { closing = true; stopEverything(); close(); return START_NOT_STICKY; }
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

    private void install() {
        setStatus("installing");
        installer = new Installer(this, paths);
        try {
            installer.installAll((step, detail, pct) -> setStatus("install " + step + ": " + detail + (pct >= 0 ? " (" + pct + "%)" : "")));
            update(true);   // Install / Update also updates BAR, with automatic updates off too
            setStatus("installed");
        } catch (InterruptedException e) {
            setStatus("install stopped");
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

    private void play(String mode) {
        updater = null;
        exitNote = null;
        Installer inst = new Installer(this, paths);
        if (!inst.isInstalled() && !"shell".equals(mode)) {
            // A first install, or a step an app update added or changed (e.g. a newer Mesa): run what is missing.
            install();
            inst = new Installer(this, paths);
            if (!inst.isInstalled()) return;
        }
        boolean showLauncher = true;
        try {
            inst.refreshHostFiles();                        // scripts/assets of this app version
            boolean bench = "bench".equals(mode);
            if (Prefs.gamepadGame && !inst.gamepadReady() && ("lobby".equals(mode) || "skirmish".equals(mode) || bench)) {
                // New in this app version (or a newer v0.8.5): singleplayer plays BAR's released game until it is in.
                try { inst.installGamepadGame((step, detail, pct) -> setStatus("controller game: " + detail)); }
                catch (InterruptedException e) { throw e; }
                catch (Exception e) { Log.e("svc", "controller game not installed", e); }
            }
            Updater up = "lobby".equals(mode) || "skirmish".equals(mode) ? update(Prefs.autoUpdate) : null;
            inst.writeGameFiles();                          // refresh settings + start script
            if (up != null) up.applyLauncherSettings();
            // The benchmark (BAR's "Benchmark BAR" scenario, unattended) runs what is installed, no update first, so
            // runs compare; its map comes once from BAR's servers. So does a skirmish's: the launcher's map setting is
            // free text, and without its map the engine ends in 2 s (an 8 GB phone plays the benchmark's map by default,
            // Prefs.mapName, also where the first install fetched the bigger one).
            String map = bench ? Installer.BENCH_MAP : "skirmish".equals(mode) ? Prefs.mapName : null;
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
            Map<String, String> env = new HashMap<>();
            env.put("ENGINE_VER", Prefs.engineVersion);
            env.put("MODE", mode);
            env.put("DISPLAY", ":0");
            env.put("LOBBY_TAG", Prefs.lobbyTag);
            env.put("GAMEPAD_GAME", inst.useGamepadGame() ? "1" : "0");
            Prefs.putGpuEnv(env);
            env.put("BARDROID_AUDIO", Prefs.audio ? "1" : "0");
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
                        loading = true;
                        DriverWatch driver = new DriverWatch();
                        driverLost = false;
                        engine = new Proc("engine").start(proot.command(env, cmd), proot.hostEnv(), paths.filesDir, line -> {
                            if (loading && (line.contains("finished loading") || line.contains("BAR Droid lobby touch"))) {
                                loading = false;
                                Log.i("svc", "loaded (the loading screen's Free memory button goes)");
                            }
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
                        if (audio != null) audio.stop();
                    }
                    Log.i("svc", "engine exited (" + rc + ")");   // (tools/phone-bench.ps1, phone-memory.ps1 read this line)
                    // (Stop's own kill is no error: it read "game ended with an error (137)" after the player's Stop)
                    // (closed by the app after the GPU driver's fault: the note under it says why, not "error (137): the log")
                    setStatus(closing ? "stopped" : rc == 0 || driverLost ? "game ended" : "game ended with an error (" + rc + ")");
                    String fatal = rc != 0 && !closing && !driverLost && rc != 137 ? engineFatal(paths) : null;
                    if (driverLost) {
                        exitNote = DriverWatch.note();
                        Log.i("svc", exitNote);
                    } else if (fatal != null) {   // (the engine's own message box, which the phone never shows)
                        exitNote = StatusText.engineFatalNote(fatal);
                        Log.i("svc", exitNote);
                    } else if (rc == 137 && !closing) {
                        // SIGKILL from outside: Android's low-memory killer (Stop and a game swiped away set closing
                        // first). Without a word the player only saw the launcher come back (an 8 GB phone, 2026-10-29).
                        exitNote = lowMemoryNote(this);
                        Log.i("svc", exitNote);
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
                // (a lobby the app closed for the GPU driver's fault is no broken lobby: the icon still opens it next time)
                Prefs.setLobbyFailedFast(this, rc != 0 && !driverLost && android.os.SystemClock.elapsedRealtime() - started < 60_000);
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

    private void createChannel() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null && nm.getNotificationChannel(CHANNEL) == null)
            nm.createNotificationChannel(new NotificationChannel(CHANNEL, "BAR Droid", NotificationManager.IMPORTANCE_LOW));
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
        if (version == null) return "GL check: " + renderer;
        // ("4.3 (Compatibility Profile) Mesa 27.0.0-devel (git-6f90e92dfd)": the numbers; the rest is in the log)
        java.util.regex.Matcher mesa = java.util.regex.Pattern.compile("Mesa (\\S+)").matcher(version);
        return "GL check: " + renderer + ", OpenGL " + version.split(" ")[0] + (mesa.find() ? ", Mesa " + mesa.group(1) : "");
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

    /** The engine's fatal error in this run's infolog (StatusText.engineFatal), the last one; null if there is none. */
    static String engineFatal(Paths paths) {
        String found = null;
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(new java.io.File(paths.bar, "infolog.txt")))) {
            for (String l; (l = r.readLine()) != null; ) {
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
        return new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)   // (the app's marker; it was Android's media "play" triangle)
                .setContentTitle(StatusText.forPlayers(status))
                // (while a game runs, what the tap and the button do: the title alone left the line under it empty)
                .setContentText(game ? "Tap to return to the game; Stop ends it" : null)
                .setContentIntent(pi)
                .addAction(new Notification.Action.Builder(null, "Stop", stopPi).build())
                .setOngoing(true)
                .build();
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
