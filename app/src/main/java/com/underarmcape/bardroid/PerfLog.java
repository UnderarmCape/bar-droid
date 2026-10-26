package com.underarmcape.bardroid;

import android.content.Context;
import android.os.Build;
import android.os.PowerManager;

import java.io.BufferedReader;
import java.io.FileReader;

/**
 * Once a minute while a game runs: Android's thermal status and headroom, the GPU's clock, its thermal cap and how
 * busy it is ("[perf]" lines in launcher.log; the game's widget logs its frame rate next to them). The target is 30 fps
 * for hours on a hot phone (Kailil, 2026-10-26), so long sessions have to show when and why it stops holding.
 */
final class PerfLog {
    private static final String KGSL = "/sys/class/kgsl/kgsl-3d0/";
    private final PowerManager power;
    private Thread thread;

    PerfLog(Context ctx) { power = ctx.getSystemService(PowerManager.class); }

    void start() {
        thread = new Thread(() -> {
            try {
                while (true) {
                    Thread.sleep(60_000);
                    log();
                }
            } catch (InterruptedException ignored) {}
        }, "perf-log");
        thread.setDaemon(true);
        thread.start();
    }

    void stop() { if (thread != null) thread.interrupt(); }

    private void log() {
        StringBuilder sb = new StringBuilder("thermal ");
        if (power != null) {
            sb.append(power.getCurrentThermalStatus());
            if (Build.VERSION.SDK_INT >= 30) sb.append(String.format(java.util.Locale.US, ", headroom %.2f", power.getThermalHeadroom(0)));
        }
        sb.append("; GPU ").append(mhz(read("devfreq/cur_freq"))).append(" MHz of ").append(mhz(read("devfreq/max_freq")))
          .append(" (thermal level ").append(read("thermal_pwrlevel")).append("), busy ").append(read("gpu_busy_percentage"))
          .append(", ").append(read("temp")).append(" mC");
        Log.i("perf", sb.toString());
    }

    private static String read(String name) {
        try (BufferedReader r = new BufferedReader(new FileReader(KGSL + name))) {
            String s = r.readLine();
            return s == null ? "?" : s.trim();
        } catch (Exception e) { return "?"; }
    }

    private static String mhz(String hz) {
        try { return String.valueOf(Long.parseLong(hz) / 1_000_000); } catch (NumberFormatException e) { return hz; }
    }
}
