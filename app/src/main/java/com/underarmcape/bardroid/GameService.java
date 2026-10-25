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

    private Paths paths;
    private XServer xserver;
    private Proc engine;
    private Installer installer;
    private PowerManager.WakeLock wakeLock;
    private Thread worker;

    public static String status() { return status; }
    public static boolean busy() { return busy; }

    @Override public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onCreate() {
        super.onCreate();
        paths = BarApp.get().paths();
        xserver = new XServer(paths);
        createChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;
        startForeground(1, notification("BAR Droid", status));
        if (ACTION_STOP.equals(action)) { stopEverything(); stopSelf(); return START_NOT_STICKY; }
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
            setStatus("installed");
        } catch (Exception e) {
            Log.e("install", "failed", e);
            setStatus("install failed: " + e.getMessage());
        }
    }

    private void play(String mode) {
        Installer inst = new Installer(this, paths);
        if (!inst.isInstalled() && !"shell".equals(mode)) { setStatus("not installed yet"); return; }
        try {
            inst.writeGameFiles();                          // refresh settings + start script
            setStatus("starting X server");
            xserver.start();
            if (!xserver.waitForSocket(15000)) { setStatus("X server did not start (see log)"); xserver.stop(); return; }
            // Bring the display up
            Intent ui = new Intent(this, GameActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(ui);

            setStatus("launching engine (" + mode + ")");
            Map<String, String> env = new HashMap<>();
            env.put("ENGINE_VER", Prefs.engineVersion);
            env.put("MODE", mode);
            env.put("DISPLAY", ":0");
            env.put("LOBBY_TAG", Prefs.lobbyTag);
            env.put("MESA_LOADER_DRIVER_OVERRIDE", Prefs.mesaDriver);
            if (Prefs.forceCompat45) { env.put("MESA_GL_VERSION_OVERRIDE", "4.5COMPAT"); env.put("MESA_GLSL_VERSION_OVERRIDE", "450"); }
            env.put("BARDROID_AUDIO", Prefs.audio ? "1" : "0");
            Proot proot = new Proot(paths);
            List<String> cmd = new ArrayList<>();
            cmd.add("/bin/bash"); cmd.add("/opt/bardroid/launch-bar.sh");
            AudioPump audio = Prefs.audio ? new AudioPump(new java.io.File(paths.rootfsTmp, "bardroid-audio.fifo")) : null;
            if (audio != null) audio.start();
            engine = new Proc("engine").start(proot.command(env, cmd), proot.hostEnv(), paths.filesDir, null);
            setStatus("running (" + mode + ")");
            int rc = engine.waitFor();
            if (audio != null) audio.stop();
            setStatus("engine exited (" + rc + ")");
        } catch (Exception e) {
            Log.e("svc", "play failed", e);
            setStatus("launch failed: " + e.getMessage());
        } finally {
            xserver.stop();
            engine = null;
        }
    }

    private void stopEverything() {
        if (installer != null) installer.cancel();
        if (engine != null) engine.kill();
        xserver.stop();
        if (worker != null) worker.interrupt();
        setStatus("stopped");
    }

    private void setStatus(String s) {
        status = s;
        Log.i("svc", s);
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(1, notification("BAR Droid", s));
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
