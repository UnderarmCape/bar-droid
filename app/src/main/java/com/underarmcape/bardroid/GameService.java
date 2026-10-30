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
    /** Why the last game ended when the player did not end it (the launcher shows it); null: nothing to say. */
    public static String exitNote() { return exitNote; }
    private static volatile String exitNote;

    private static String lowMemoryNote(android.content.Context c) {
        return "Android closed the game: the phone ran out of memory. Close other apps and try again"
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
            Log.i("app", "the last run ended: " + e.getDescription() + ", reason " + e.getReason() + ", importance "
                    + e.getImportance() + ", " + new java.util.Date(e.getTimestamp()));
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
     * reports tasks the app removes itself (StartActivity handing over to the game): only the game's task counts.
     */
    @Override
    public void onTaskRemoved(Intent rootIntent) {
        android.content.ComponentName c = rootIntent != null ? rootIntent.getComponent() : null;
        if (c != null && GameActivity.class.getName().equals(c.getClassName())) {
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
        if (!busy) closing = false;
        startForeground(1, notification("BAR Droid", status));
        if (ACTION_STOP.equals(action)) { closing = true; stopEverything(); close(); return START_NOT_STICKY; }
        if (busy) { Log.i("svc", "busy; ignoring " + action); return START_NOT_STICKY; }
        if (ACTION_INSTALL.equals(action)) runAsync(this::install);
        else if (ACTION_PLAY.equals(action)) { String mode = intent.getStringExtra(EXTRA_MODE); runAsync(() -> play(mode == null ? "skirmish" : mode)); }
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
            // runs compare; its map comes once from BAR's servers.
            if (bench && !new java.io.File(paths.bar, "maps/starwatcher_1.0.sd7").exists()) {
                setStatus("benchmark: downloading " + Installer.BENCH_MAP);
                new Proot(paths).runScript("bench:map", "/opt/bardroid/setup-container.sh", new HashMap<>(),
                        java.util.Arrays.asList("map", Installer.BENCH_MAP, Prefs.engineVersion));
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
            GameActivity.hiddenFlag(paths).delete();
            //noinspection ResultOfMethodCallIgnored
            GameActivity.floatingFlag(paths).delete();
            //noinspection ResultOfMethodCallIgnored
            GameActivity.catchupFlag(paths).delete();
            //noinspection ResultOfMethodCallIgnored
            new java.io.File(paths.bar, "LuaUI/Config/bardroid_catchup.txt").delete();
            Intent ui = new Intent(this, GameActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
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
                        engine = new Proc("engine").start(proot.command(env, cmd), proot.hostEnv(), paths.filesDir, null);
                        setStatus("running (" + mode + ")");
                        started = android.os.SystemClock.elapsedRealtime();
                        PerfLog perf = new PerfLog(this);
                        perf.start();
                        try { rc = engine.waitFor(); } finally { perf.stop(); }
                    } finally {
                        if (audio != null) audio.stop();
                    }
                    setStatus("engine exited (" + rc + ")");
                    if (rc == 137 && !closing) {
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
            if ("lobby".equals(mode)) {   // a lobby that dies at once is not started again from the app icon
                Prefs.setLobbyFailedFast(this, rc != 0 && android.os.SystemClock.elapsedRealtime() - started < 60_000);
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
            if (!showLauncher || closing) close();   // the lobby was quit, or the app closed: nothing left running
        }
    }

    /** Closes the X display activity (Termux:X11's ACTION_STOP) and, if asked, brings the launcher back with the result. */
    private void closeDisplay(boolean showLauncher) {
        sendBroadcast(new Intent(com.termux.x11.MainActivity.ACTION_STOP).setPackage(getPackageName()));
        if (!showLauncher) return;
        try {
            startActivity(new Intent(this, LauncherActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
        } catch (Exception e) { Log.e("svc", "could not reopen the launcher", e); }
    }

    private void stopEverything() {
        if (installer != null) installer.cancel();
        if (updater != null) updater.cancel();
        if (engine != null) engine.kill();
        Proc.killAll();          // container setup steps (proot) started by the installer
        xserver.stop();
        if (worker != null) worker.interrupt();
        setStatus("stopped");
    }

    private void setStatus(String s) {
        status = s;
        Log.i("svc", s);
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null && !closing) nm.notify(1, notification("BAR Droid", s));
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

    private Notification notification(String title, String text) {
        Intent open = new Intent(this, LauncherActivity.class);
        PendingIntent pi = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Intent stop = new Intent(this, GameService.class).setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(this, 1, stop, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(pi)
                .addAction(new Notification.Action.Builder(null, "Stop", stopPi).build())
                .setOngoing(true)
                .build();
    }

    @Override
    public void onDestroy() {
        stopEverything();
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
