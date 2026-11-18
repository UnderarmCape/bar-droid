package com.underarmcape.bardroid;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/**
 * "Share logs": zips the app's logs and hands them to Android's share sheet (Tailscale/Taildrop, Drive, mail...),
 * so a device can be debugged without adb.
 */
final class LogShare {
    private LogShare() {}

    /** A zip being made, until its share sheet is started: a second tap meanwhile is let go (it deleted the first's zip
     *  as it started, and two share sheets stacked, the lower one's file gone; dev phone, a double tap, 2026-11-11). */
    private static final java.util.concurrent.atomic.AtomicBoolean zipping = new java.util.concurrent.atomic.AtomicBoolean();

    /**
     * Zipped off the UI thread (after a long game the infolog alone runs to tens of MB, and zipping it on the UI thread
     * could stall the launcher into Android's "not responding"), then the share sheet.
     */
    static void share(Activity a) {
        if (!zipping.compareAndSet(false, true)) {
            Log.i("app", "share logs: already zipping, the tap let go");
            return;
        }
        Toast.makeText(a, "Zipping the logs...", Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            long t0 = System.currentTimeMillis();
            File zip = null;
            try { zip = zip(a); } finally { if (zip == null) zipping.set(false); }
            if (zip == null) return;
            Log.i("app", "logs zipped: " + zip.length() / 1024 + " KB in " + (System.currentTimeMillis() - t0) + " ms");
            File made = zip;
            a.runOnUiThread(() -> {
                try { sheet(a, made); } finally { zipping.set(false); }
            });
        }, "log-share").start();
    }

    private static void sheet(Activity a, File zip) {
        if (a.isFinishing() || a.isDestroyed()) return;
        Uri uri = FileProvider.getUriForFile(a, a.getPackageName() + ".logs", zip);
        Intent send = new Intent(Intent.ACTION_SEND)
                .setType("application/zip")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_SUBJECT, "BAR Droid logs " + zip.getName().replaceAll("^bardroid-logs-|\\.zip$", ""))
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        // (the sheet in the player's words, the app being "Beyond All Reason"; the subject keeps the port's name for
        // whoever reads the logs)
        a.startActivity(Intent.createChooser(send, "Share the game's logs"));
    }

    private static File zip(Activity a) {
        Paths p = BarApp.get().paths();
        File dir = new File(a.getCacheDir(), "share");
        //noinspection ResultOfMethodCallIgnored
        dir.mkdirs();
        File[] old = dir.listFiles();
        if (old != null) for (File f : old) //noinspection ResultOfMethodCallIgnored
            f.delete();
        String stamp = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date());
        File zip = new File(dir, "bardroid-logs-" + stamp + ".zip");
        try (ZipOutputStream out = new ZipOutputStream(new FileOutputStream(zip))) {
            add(out, new File(p.logs, "launcher.log"), "launcher.log");
            add(out, new File(p.logs, "launcher.old.log"), "launcher.old.log");
            add(out, new File(p.bar, "infolog.txt"), "infolog.txt");
            add(out, new File(p.bar, "springsettings.cfg"), "springsettings.cfg");
            add(out, p.stateFile, "install-state.properties");
            // (the updater's own: the BAR versions kept off as failed, the last check, the engine's missed settings)
            add(out, new File(p.filesDir, "update/state.properties"), "update-state.properties");
            add(out, new File(p.rootfsTmp, "pulse/pulse.log"), "pulse.log");
            File[] engineLogs = new File(p.bar, "logs").listFiles();
            if (engineLogs != null) for (File f : engineLogs) add(out, f, "logs/" + f.getName());
        } catch (IOException e) {
            Log.e("app", "could not zip the logs", e);
            a.runOnUiThread(() -> Toast.makeText(a, "Could not zip the logs: " + e.getMessage(), Toast.LENGTH_LONG).show());
            return null;
        }
        return zip;
    }

    private static void add(ZipOutputStream out, File f, String name) throws IOException {
        if (!f.isFile()) return;
        out.putNextEntry(new ZipEntry(name));
        // (an online game's join password out of them, LogRedact)
        try (InputStream in = new FileInputStream(f)) { LogRedact.copy(in, out); }
        out.closeEntry();
    }
}
