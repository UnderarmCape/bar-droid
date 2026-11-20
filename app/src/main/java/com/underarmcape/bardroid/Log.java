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

    private static final long ROTATE_BYTES = 4L * 1024 * 1024;
    private static int sinceCheck;

    public static synchronized void init(File logDir) {
        //noinspection ResultOfMethodCallIgnored
        logDir.mkdirs();
        file = new File(logDir, "launcher.log");
        rotateIfBig();
    }

    /**
     * A full log becomes launcher.old.log (Share logs sends both): the session that went wrong is still there after
     * the app restarts. Checked at start and every 2000 lines (the app can live for days behind the launcher).
     */
    private static void rotateIfBig() {
        if (file.length() <= ROTATE_BYTES) return;
        File old = new File(file.getParentFile(), "launcher.old.log");
        //noinspection ResultOfMethodCallIgnored
        old.delete();
        if (!file.renameTo(old)) //noinspection ResultOfMethodCallIgnored
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
    /** For the shared logs only (launcher.log, logcat): not in the launcher's log box, where players read. */
    public static void detail(String tag, String msg) {
        android.util.Log.i("BarDroid/" + tag, msg);
        synchronized (Log.class) { write(fmt.format(new Date()) + " [" + tag + "] " + msg); }
    }

    private static void write(String s) {
        if (file == null) return;
        if (++sinceCheck >= 2000) { sinceCheck = 0; rotateIfBig(); }
        try (FileWriter w = new FileWriter(file, true)) { w.write(s); w.write('\n'); } catch (IOException ignored) {}
    }

    /**
     * The engine's own harmless lines that read as faults in the launcher's log box: its disk check, "Warning:
     * [IsPathOnSpinningDisk] Error 'No such file or directory' opening file '/sys/block/dm-0/queue/rotational'", twice
     * at every start (the container has no such file; dev phone screenshot 2026-11-19); and BAR's own two at every
     * game's end, "Error: [SetConfigInt] key "AdvSky" is deprecated" and "[weapondefs.lua] Error: removed
     * ceg_test_projectile_unit_ceg_test_projectile weaponDef, missing model" (its test weapon; dev phone screenshot, the
     * same day). The shared logs keep them.
     */
    private static boolean quiet(String tag, String msg) {
        return msg.contains("[IsPathOnSpinningDisk]") || msg.contains("key \"AdvSky\" is deprecated")
                || msg.contains("Error: removed ceg_test_projectile")
                || (DOWNLOADS.matcher(tag).find() && CURL.matcher(msg).find());
    }

    /**
     * curl's own account of pr-downloader's downloads (a map the lobby asks for, the game's update): each address tried
     * ("* Immediate connect fail for 2606:...: Network is unreachable", the phone having no IPv6 route; the IPv4 one after
     * it connects), the certificates, the request's and the answer's headers: ~70 lines a map in the launcher's box, the
     * unreachable ones reading as a failure (dev phone 2026-11-20). pr-downloader's own lines and its progress stay.
     */
    private static final java.util.regex.Pattern DOWNLOADS = java.util.regex.Pattern.compile("^(bridge|setup|update|bench):?");
    private static final java.util.regex.Pattern CURL =
            java.util.regex.Pattern.compile("^(\\* |[<>] |[<>]$|(Host|User-Agent|Accept): |$)");

    private static void line(String tag, String msg, boolean error) {
        if (!error && quiet(tag, msg)) { detail(tag, msg); return; }
        String s = fmt.format(new Date()) + " [" + tag + "] " + msg;
        if (error) android.util.Log.e("BarDroid/" + tag, msg); else android.util.Log.i("BarDroid/" + tag, msg);
        List<Listener> ls;
        synchronized (Log.class) {
            lines.addLast(s);
            while (lines.size() > MAX_LINES) lines.removeFirst();
            ls = new ArrayList<>(listeners);
            write(s);
        }
        for (Listener l : ls) l.onLine(s);
    }

    public static synchronized String dump() {
        StringBuilder sb = new StringBuilder();
        for (String l : lines) sb.append(l).append('\n');
        return sb.toString();
    }

    /** The last n lines kept, as dump() (the launcher's log box: a few hundred lines laid out, not MAX_LINES). */
    public static synchronized String tail(int n) {
        StringBuilder sb = new StringBuilder();
        int skip = Math.max(0, lines.size() - n), i = 0;
        for (String l : lines) {
            if (i++ >= skip) sb.append(l).append('\n');
        }
        return sb.toString();
    }

    public static synchronized void addListener(Listener l) { listeners.add(l); }
    public static synchronized void removeListener(Listener l) { listeners.remove(l); }
}
