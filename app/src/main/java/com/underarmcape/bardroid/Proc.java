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
