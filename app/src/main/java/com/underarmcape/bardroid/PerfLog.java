package com.underarmcape.bardroid;

import android.content.Context;
import android.os.Build;
import android.os.PowerManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;

/**
 * Once a minute while a game runs: Android's thermal status and headroom, the GPU's clock, its thermal cap and how
 * busy it is, the CPU clusters' clocks and caps, free memory and the engine's resident size ("[perf]" lines in launcher.log; the game's widget logs its frame rate next to them). The target is 30 fps
 * for hours on a hot phone (Kailil, 2026-10-26), so long sessions have to show when and why it stops holding.
 */
final class PerfLog {
    private static final String KGSL = "/sys/class/kgsl/kgsl-3d0/";
    private final PowerManager power;
    private Thread thread;

    PerfLog(Context ctx) { power = ctx.getSystemService(PowerManager.class); }

    void start() {
        thread = new Thread(() -> {
            int failed = 0;
            try {
                while (true) {
                    Thread.sleep(60_000);
                    // (uncaught on this thread a RuntimeException ended the app's process mid-game; review 2026-11-20)
                    try { log(); }
                    catch (RuntimeException e) { if (failed++ < 3) Log.e("perf", "the minute's line failed", e); }
                }
            } catch (InterruptedException ignored) {}
        }, "perf-log");
        thread.setDaemon(true);
        thread.start();
    }

    void stop() { if (thread != null) thread.interrupt(); }

    private void log() {
        StringBuilder sb = new StringBuilder("thermal ");
        if (power != null && Build.VERSION.SDK_INT >= 29) {   // (Android 10's: on Android 9 it threw, lint's NewApi)
            sb.append(power.getCurrentThermalStatus());
            if (Build.VERSION.SDK_INT >= 30) sb.append(String.format(java.util.Locale.US, ", headroom %.2f", power.getThermalHeadroom(0)));
        }
        sb.append("; GPU ").append(mhz(read("devfreq/cur_freq"))).append(" MHz of ").append(mhz(read("devfreq/max_freq")))
          .append(" (thermal level ").append(read("thermal_pwrlevel")).append("), busy ").append(read("gpu_busy_percentage"))
          .append(", ").append(read("temp")).append(" mC");
        // every CPU cluster by its first core (cpufreq policyN): the Fold7's cpu0-5 and cpu6-7, the S23 Ultra's cpu0-2,
        // cpu3-6 and cpu7 (its prime core; a cpu6 reading there was a middle core); thermal lowers scaling_max_freq
        for (int cpu : clusters()) {
            String dir = "/sys/devices/system/cpu/cpu" + cpu + "/cpufreq/";
            sb.append("; cpu").append(cpu).append(' ').append(mhz(readFile(dir + "scaling_cur_freq"), 1000)).append(" MHz of ")
              .append(mhz(readFile(dir + "scaling_max_freq"), 1000));
        }
        // memory: Android logged low memory all through an 8v8 (2026-10-26), and its killer has taken the game before
        sb.append("; memory available ").append(meminfo("MemAvailable:")).append(" MB, swap free ")
          .append(meminfo("SwapFree:")).append(" MB, engine ").append(engineRss()).append(" MB");
        // the GPU driver's own memory (textures, buffers: not in the engine's RSS); in Kailil's online game on the Fold7
        // the game took ~3 GB of available memory with the engine at 1-1.6 GB, and the low-memory killer ended it
        // (2026-11-02). Android's meminfo has it on Qualcomm phones (GpuTotal); left out where it does not.
        String gpu = meminfo("GpuTotal:");
        if (!"?".equals(gpu)) sb.append(", GPU ").append(gpu).append(" MB");
        if (BarApp.get().paths().hiddenFlag().exists()) sb.append("; game screen hidden (engine not drawing)");
        else if (BarApp.get().paths().catchupFlag().exists()) sb.append("; catching up (engine not drawing)");
        Log.i("perf", sb.toString());
    }

    /** The first core of each CPU cluster (the cpufreq policies), lowest first; 0 and 6 if they cannot be listed. */
    private static int[] clusters() {
        String[] names = new java.io.File("/sys/devices/system/cpu/cpufreq").list();
        java.util.TreeSet<Integer> first = new java.util.TreeSet<>();
        if (names != null) for (String n : names) {
            if (n.matches("policy\\d+")) first.add(Integer.parseInt(n.substring(6)));
        }
        if (first.isEmpty()) return new int[] {0, 6};
        int[] out = new int[first.size()];
        int i = 0;
        for (int c : first) out[i++] = c;
        return out;
    }

    /** A /proc/meminfo field in MB, or "?". */
    private static String meminfo(String field) {
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/meminfo"))) {
            for (String s; (s = r.readLine()) != null; ) {
                if (s.startsWith(field)) return String.valueOf(Long.parseLong(s.replaceAll("[^0-9]", "")) / 1024);
            }
        } catch (Exception ignored) {}
        return "?";
    }

    /**
     * Resident memory of the engine (one of this app's processes) in MB, or "?". Recoil names its main thread, and so
     * the process, "recoil-main" (it was always "?" while this looked for "spring", the binary's name).
     */
    private static String engineRss() {
        File[] procs = new File("/proc").listFiles();
        if (procs == null) return "?";
        for (File p : procs) {
            if (!p.getName().matches("\\d+")) continue;
            String comm = readFile(p + "/comm");
            if (!"recoil-main".equals(comm) && !"spring".equals(comm)) continue;
            try (BufferedReader r = new BufferedReader(new FileReader(p + "/status"))) {
                for (String s; (s = r.readLine()) != null; ) {
                    if (s.startsWith("VmRSS:")) return String.valueOf(Long.parseLong(s.replaceAll("[^0-9]", "")) / 1024);
                }
            } catch (Exception ignored) {}
        }
        return "?";
    }

    private static String read(String name) { return readFile(KGSL + name); }

    private static String readFile(String path) {
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            String s = r.readLine();
            return s == null ? "?" : s.trim();
        } catch (Exception e) { return "?"; }
    }

    private static String mhz(String hz) { return mhz(hz, 1_000_000); }

    private static String mhz(String value, long perMhz) {
        try { return String.valueOf(Long.parseLong(value) / perMhz); } catch (NumberFormatException e) { return value; }
    }
}
