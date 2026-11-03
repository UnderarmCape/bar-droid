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
