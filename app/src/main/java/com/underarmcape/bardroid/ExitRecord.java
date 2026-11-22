package com.underarmcape.bardroid;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.os.Build;

import java.io.File;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * What is left after the app dies (RC 0.2.0 item 6, release overhaul item 53): an exception no code caught writes its
 * stack to launcher.log before Android's own handler ends the process (Share logs sends it; logcat alone was gone by
 * the time a player shared logs); the process's state summary (the screen and the map, Android 11+'s
 * setProcessStateSummary, at most 128 bytes) is kept by Android with the process's exit record; and at the next start
 * the exit records Android kept since the last one read are written to launcher.log, each with its reason, its words
 * and that summary. The engine is a child process (proot): its own crash ends no app process, so it leaves no exit
 * record (its signal is in launcher.log from launch-bar.sh and in infolog.txt).
 */
final class ExitRecord {
    private ExitRecord() {}

    private static final String SEEN = ".exit-records-seen";   // (logs/: the newest record already written)

    /** The default handler: the stack into launcher.log, then the one before (Android's: the crash dialog, the end). */
    static void install() {
        final Thread.UncaughtExceptionHandler before = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
            try {
                StringWriter s = new StringWriter();
                error.printStackTrace(new PrintWriter(s));
                Log.e("crash", "an exception no code caught, in thread \"" + thread.getName() + "\": the app ends\n" + s);
            } catch (Throwable ignored) {
                // (nothing more to do: the handler below still runs)
            }
            if (before != null) before.uncaughtException(thread, error);
            else {
                android.os.Process.killProcess(android.os.Process.myPid());
                System.exit(10);
            }
        });
    }

    /** The process's state for its exit record: what runs, the map, the screen (Android 11+; 128 bytes at most). */
    static void summary(Context ctx, String state) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || ctx == null) return;
        try {
            byte[] b = state.getBytes(StandardCharsets.UTF_8);
            if (b.length > 128) b = java.util.Arrays.copyOf(b, 128);
            ActivityManager am = ctx.getSystemService(ActivityManager.class);
            if (am != null) am.setProcessStateSummary(b);
        } catch (RuntimeException e) {
            Log.detail("exit", "state summary not kept: " + e);
        }
    }

    /** The screen as it is now: its size and which way up (for summary). */
    static String screen(Context ctx) {
        android.util.DisplayMetrics dm = ctx.getResources().getDisplayMetrics();
        return dm.widthPixels + "x" + dm.heightPixels + (dm.heightPixels > dm.widthPixels ? " upright" : " sideways");
    }

    /** The exit records Android kept since the last start that read them, into launcher.log (Android 11+). */
    static void readBack(Context ctx, File logDir) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || ctx == null) return;
        try {
            ActivityManager am = ctx.getSystemService(ActivityManager.class);
            if (am == null) return;
            List<ApplicationExitInfo> list = am.getHistoricalProcessExitReasons(ctx.getPackageName(), 0, 8);
            File seenFile = new File(logDir, SEEN);
            long seen = 0;
            try { seen = Long.parseLong(new String(java.nio.file.Files.readAllBytes(seenFile.toPath()),
                    StandardCharsets.UTF_8).trim()); } catch (Exception ignored) {}
            long newest = seen;
            // (oldest first, as they happened)
            for (int i = list.size() - 1; i >= 0; i--) {
                ApplicationExitInfo x = list.get(i);
                if (x.getTimestamp() <= seen) continue;
                newest = Math.max(newest, x.getTimestamp());
                byte[] st = x.getProcessStateSummary();
                String state = st != null ? new String(st, StandardCharsets.UTF_8) : "none";
                Log.i("exit", "the app's process ended " + new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss",
                        java.util.Locale.US).format(new java.util.Date(x.getTimestamp())) + ": " + reason(x.getReason())
                        + (x.getStatus() != 0 ? " (status " + x.getStatus() + ")" : "")
                        + (x.getDescription() != null ? ", \"" + x.getDescription() + "\"" : "")
                        + ", importance " + x.getImportance() + ", process " + x.getProcessName()
                        + "; its state then: " + state);
            }
            if (newest > seen) java.nio.file.Files.write(seenFile.toPath(),
                    Long.toString(newest).getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            Log.detail("exit", "exit records not read: " + e);
        }
    }

    private static String reason(int r) {
        switch (r) {
            case ApplicationExitInfo.REASON_ANR: return "not responding (ANR)";
            case ApplicationExitInfo.REASON_CRASH: return "crashed (an exception in Java)";
            case ApplicationExitInfo.REASON_CRASH_NATIVE: return "crashed (native code)";
            case ApplicationExitInfo.REASON_DEPENDENCY_DIED: return "a process it needs died";
            case ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE: return "used too much of the phone";
            case ApplicationExitInfo.REASON_EXIT_SELF: return "ended itself";
            case ApplicationExitInfo.REASON_INITIALIZATION_FAILURE: return "failed to start";
            case ApplicationExitInfo.REASON_LOW_MEMORY: return "killed for memory (low memory)";
            case ApplicationExitInfo.REASON_OTHER: return "ended by the system (other)";
            case ApplicationExitInfo.REASON_PERMISSION_CHANGE: return "a permission changed";
            case ApplicationExitInfo.REASON_SIGNALED: return "killed by a signal";
            case ApplicationExitInfo.REASON_USER_REQUESTED: return "stopped by the user (force stop, a swipe away)";
            case ApplicationExitInfo.REASON_USER_STOPPED: return "the user stopped";
            default: return "reason " + r;
        }
    }
}
