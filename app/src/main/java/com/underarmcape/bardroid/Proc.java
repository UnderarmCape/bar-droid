package com.underarmcape.bardroid;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Runs a child process, streams merged stdout/stderr to the Log, returns the exit code. */
public final class Proc {
    public interface LineSink { void line(String s); }

    private Process process;
    private final String tag;
    private volatile boolean killed;
    private static final Set<Proc> live = new HashSet<>();

    public Proc(String tag) { this.tag = tag; }

    /** Kills every child process still running (Stop button, service teardown). */
    public static void killAll() {
        List<Proc> all;
        synchronized (live) { all = new ArrayList<>(live); }
        for (Proc p : all) p.kill();
        killStrays();
    }

    /**
     * SIGKILLs every other process running under this app's UID. Needed because proot ignores SIGTERM (what
     * Process.destroy* sends on Android) and, when it is SIGKILLed, leaves its tracees (the engine, a daemonized
     * PulseAudio) running. Everything the app launches runs under its UID, so this takes down the whole tree.
     */
    static void killStrays() {
        int me = android.os.Process.myPid(), uid = android.os.Process.myUid();
        File[] procs = new File("/proc").listFiles();
        if (procs == null) return;
        for (File d : procs) {
            int pid;
            try { pid = Integer.parseInt(d.getName()); } catch (NumberFormatException e) { continue; }
            if (pid == me) continue;
            try (BufferedReader r = new BufferedReader(new java.io.FileReader(new File(d, "status")))) {
                String line;
                while ((line = r.readLine()) != null) {
                    // (a process already dead, not yet reaped: a second Stop pass "killed" it again in the log)
                    if (line.startsWith("State:") && line.substring(6).trim().startsWith("Z")) break;
                    if (!line.startsWith("Uid:")) continue;
                    if (Integer.parseInt(line.substring(4).trim().split("\\s+")[0]) == uid) {
                        android.system.Os.kill(pid, android.system.OsConstants.SIGKILL);
                        Log.i("proc", "killed pid " + pid);
                    }
                    break;
                }
            } catch (Exception ignored) {}   // gone already, or not ours to read
        }
    }

    /**
     * Asks the engine (each "spring" process under this app's UID) to quit and waits up to waitMs for it to end: its
     * replay is written only as it ends (Recoil's demo recorder keeps the game in memory until its destructor), so a game
     * the player closed (Stop, swiped away), SIGKILLed, left an empty .sdfz (the Fold7, 2026-11-18: a 9-minute
     * skirmish swiped away, 0 bytes). SIGTERM is SDL's quit event in the engine (proot passes it on to its tracee), the
     * window's close button: in a running game BAR's top bar buttons (gui_top_bar_buttons.lua AllowQuit) answer the
     * first with its quit dialog and quit on a second once the dialog has been up over half a second, so a second
     * follows a second later (dev phone: "quit vetoed by Lua (AllowQuit)" with one). Only two: once the engine has shut
     * SDL down a SIGTERM ends it at once. A refusal beyond that: the kill after the wait. True if it ended in time.
     */
    static boolean endEngine(long waitMs) {
        List<Integer> pids = enginePids();
        if (pids.isEmpty()) return false;
        long t0 = android.os.SystemClock.elapsedRealtime();
        for (int pid : pids) {
            try { android.system.Os.kill(pid, android.system.OsConstants.SIGTERM); } catch (Exception ignored) {}
        }
        Log.i("proc", "asked the engine to quit (pid " + pids + "): its replay is written as it ends");
        boolean again = false;
        while (android.os.SystemClock.elapsedRealtime() - t0 < waitMs) {
            if (!again && android.os.SystemClock.elapsedRealtime() - t0 >= 1000) {
                again = true;   // (BAR's quit dialog's "asked again")
                for (int pid : pids) {
                    if (!running(pid)) continue;
                    try { android.system.Os.kill(pid, android.system.OsConstants.SIGTERM); } catch (Exception ignored) {}
                    Log.i("proc", "asked the engine again (BAR's quit dialog): pid " + pid);
                }
            }
            boolean left = false;
            for (int pid : pids) if (running(pid)) { left = true; break; }
            if (!left) {
                Log.i("proc", "the engine quit in " + (android.os.SystemClock.elapsedRealtime() - t0) + " ms");
                return true;
            }
            try { Thread.sleep(100); } catch (InterruptedException e) { Thread.currentThread().interrupt(); break; }
        }
        Log.i("proc", "the engine did not quit within " + waitMs + " ms: killed");
        return false;
    }

    /**
     * The engine's processes: this app's UID, started as "spring" (/proc/<pid>/cmdline's first word; its comm is
     * "recoil-main", the engine names its main thread, dev phone 2026-11-18).
     */
    static List<Integer> enginePids() {
        List<Integer> out = new ArrayList<>();
        int me = android.os.Process.myPid(), uid = android.os.Process.myUid();
        File[] procs = new File("/proc").listFiles();
        if (procs == null) return out;
        for (File d : procs) {
            int pid;
            try { pid = Integer.parseInt(d.getName()); } catch (NumberFormatException e) { continue; }
            if (pid == me) continue;
            try (java.io.FileInputStream in = new java.io.FileInputStream(new File(d, "cmdline"))) {
                byte[] b = new byte[256];
                int n = in.read(b), end = 0;
                while (end < Math.max(0, n) && b[end] != 0) end++;
                String first = new String(b, 0, end, StandardCharsets.UTF_8);
                if (!(first.equals("spring") || first.endsWith("/spring"))) continue;
            } catch (Exception e) { continue; }
            if (uid == statusUid(pid) && running(pid)) out.add(pid);
        }
        return out;
    }

    /** A process there and not a zombie (dead, not yet reaped). */
    private static boolean running(int pid) {
        try (BufferedReader r = new BufferedReader(new java.io.FileReader("/proc/" + pid + "/status"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith("State:")) return !line.substring(6).trim().startsWith("Z");
            }
        } catch (Exception ignored) {}
        return false;
    }

    private static int statusUid(int pid) {
        try (BufferedReader r = new BufferedReader(new java.io.FileReader("/proc/" + pid + "/status"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith("Uid:")) return Integer.parseInt(line.substring(4).trim().split("\\s+")[0]);
            }
        } catch (Exception ignored) {}
        return -1;
    }

    public static int run(String tag, List<String> cmd, Map<String, String> env, File cwd) throws IOException, InterruptedException {
        return new Proc(tag).start(cmd, env, cwd, null).waitFor();
    }

    public Proc start(List<String> cmd, Map<String, String> env, File cwd, LineSink extraSink) throws IOException {
        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.redirectErrorStream(true);
        if (cwd != null) pb.directory(cwd);
        if (env != null) {
            Map<String, String> e = pb.environment();
            e.clear();
            e.putAll(env);
        }
        Log.i(tag, "exec: " + String.join(" ", cmd));
        process = pb.start();
        synchronized (live) { live.add(this); }
        Thread t = new Thread(() -> {
            try (BufferedReader r = new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                    Log.raw(tag, line);
                    if (extraSink != null) extraSink.line(line);
                }
            } catch (IOException ignored) {}
        }, "proc-" + tag);
        t.setDaemon(true);
        t.start();
        return this;
    }

    public int waitFor() throws InterruptedException {
        int rc;
        try { rc = process.waitFor(); }
        catch (InterruptedException e) { kill(); throw e; }   // never leave an orphaned proot behind
        synchronized (live) { live.remove(this); }
        Log.i(tag, killed ? "killed" : ("exit code " + rc));
        return rc;
    }

    public boolean isAlive() { return process != null && process.isAlive(); }

    public void kill() {
        killed = true;
        if (process != null) process.destroyForcibly();
        synchronized (live) { live.remove(this); }
    }

    public Process process() { return process; }
}
