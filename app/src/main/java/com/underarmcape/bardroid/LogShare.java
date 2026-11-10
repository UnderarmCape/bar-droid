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

    static void share(Activity a) {
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
            add(out, new File(p.rootfsTmp, "pulse/pulse.log"), "pulse.log");
            File[] engineLogs = new File(p.bar, "logs").listFiles();
            if (engineLogs != null) for (File f : engineLogs) add(out, f, "logs/" + f.getName());
        } catch (IOException e) {
            Log.e("app", "could not zip the logs", e);
            Toast.makeText(a, "Could not zip the logs: " + e.getMessage(), Toast.LENGTH_LONG).show();
            return;
        }
        Uri uri = FileProvider.getUriForFile(a, a.getPackageName() + ".logs", zip);
        Intent send = new Intent(Intent.ACTION_SEND)
                .setType("application/zip")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_SUBJECT, "BAR Droid logs " + stamp)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        // (the sheet in the player's words, the app being "Beyond All Reason"; the subject keeps the port's name for
        // whoever reads the logs)
        a.startActivity(Intent.createChooser(send, "Share the game's logs"));
    }

    private static void add(ZipOutputStream out, File f, String name) throws IOException {
        if (!f.isFile()) return;
        out.putNextEntry(new ZipEntry(name));
        try (InputStream in = new FileInputStream(f)) { Installer.copy(in, out); }
        out.closeEntry();
    }
}
