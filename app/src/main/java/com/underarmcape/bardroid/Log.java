package com.underarmcape.bardroid;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Process-wide log: keeps the last few thousand lines in memory for the UI, mirrors them to logcat
 * and appends them to logs/launcher.log. Every subsystem (installer, proot, X server, engine) writes here.
 */
public final class Log {
    public interface Listener { void onLine(String line); }

    private static final int MAX_LINES = 4000;
    private static final ArrayDeque<String> lines = new ArrayDeque<>();
    private static final List<Listener> listeners = new ArrayList<>();
    private static File file;
    private static final SimpleDateFormat fmt = new SimpleDateFormat("HH:mm:ss", Locale.US);

    public static synchronized void init(File logDir) {
        //noinspection ResultOfMethodCallIgnored
        logDir.mkdirs();
        file = new File(logDir, "launcher.log");
        if (file.length() > 4L * 1024 * 1024) //noinspection ResultOfMethodCallIgnored
            file.delete();
    }

    public static void i(String tag, String msg) { line(tag, msg, false); }
    public static void e(String tag, String msg) { line(tag, msg, true); }
    public static void e(String tag, String msg, Throwable t) {
        line(tag, msg + ": " + t, true);
        android.util.Log.e("BarDroid/" + tag, msg, t);
    }
    /** Raw output from a child process; no timestamp prefix in memory, kept verbatim. */
    public static void raw(String tag, String text) { line(tag, text, false); }

    private static void line(String tag, String msg, boolean error) {
        String s = fmt.format(new Date()) + " [" + tag + "] " + msg;
        if (error) android.util.Log.e("BarDroid/" + tag, msg); else android.util.Log.i("BarDroid/" + tag, msg);
        List<Listener> ls;
        synchronized (Log.class) {
            lines.addLast(s);
            while (lines.size() > MAX_LINES) lines.removeFirst();
            ls = new ArrayList<>(listeners);
            if (file != null) {
                try (FileWriter w = new FileWriter(file, true)) { w.write(s); w.write('\n'); } catch (IOException ignored) {}
            }
        }
        for (Listener l : ls) l.onLine(s);
    }

    public static synchronized String dump() {
        StringBuilder sb = new StringBuilder();
        for (String l : lines) sb.append(l).append('\n');
        return sb.toString();
    }

    public static synchronized void addListener(Listener l) { listeners.add(l); }
    public static synchronized void removeListener(Listener l) { listeners.remove(l); }
}
