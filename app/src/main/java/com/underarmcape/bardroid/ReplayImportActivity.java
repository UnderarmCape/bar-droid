package com.underarmcape.bardroid;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * The lobby's Replays "Add" (Chobby's Open Folder for demos/, which LobbyBridge brings here): Android's file picker for
 * BAR replays (.sdfz) the phone has, as its browser downloads them from BAR's replays website (the tab's Download),
 * copied into the engine's demos/ folder in the app's own storage, which no file manager reaches. The lobby's widget
 * makes its list again when {@link #STAMP} changes (bardroid_lobby_touch.lua). No UI of its own: see-through over the
 * lobby while the picker is up.
 */
public class ReplayImportActivity extends Activity {
    private static final int PICK = 1;
    /** Written under the write dir after replays were added: the time, for the lobby's widget to refresh its list. */
    static final String STAMP = "LuaUI/Config/bardroid_replays.txt";
    private static final long MAX_BYTES = 512L << 20;   // (a 10-minute 1v1 is about 1 MB; an 8v8 hour some tens)
    private static final Uri DOWNLOADS = Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload");

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        if (saved != null) return;   // (recreated while the picker is up: its answer still comes to onActivityResult)
        // (opened in Downloads, where a browser puts a replay: it opened on Recent, the folder a few taps away down its
        // side menu, dev phone 2026-11-17; a hint only, the picker may keep its own)
        Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                .putExtra(DocumentsContract.EXTRA_INITIAL_URI, DOWNLOADS);
        try {
            startActivityForResult(pick, PICK);
            Log.i("bridge", "replay import: the file picker");
        } catch (ActivityNotFoundException e) {
            Log.e("bridge", "replay import: no file picker on this phone: " + e);
            Toast.makeText(this, "No file picker on this phone", Toast.LENGTH_LONG).show();
            finish();
        }
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != PICK) return;
        List<Uri> picked = new ArrayList<>();
        if (result == RESULT_OK && data != null) {
            ClipData clip = data.getClipData();
            if (clip != null) for (int i = 0; i < clip.getItemCount(); i++) picked.add(clip.getItemAt(i).getUri());
            else if (data.getData() != null) picked.add(data.getData());
        }
        if (picked.isEmpty()) {
            Log.i("bridge", "replay import: nothing picked");
            finish();
            return;
        }
        ContentResolver cr = getContentResolver();
        File bar = BarApp.get().paths().bar;
        new Thread(() -> {
            String said = importAll(cr, picked, bar);
            runOnUiThread(() -> {
                Toast.makeText(this, said, Toast.LENGTH_LONG).show();
                finish();
            });
        }, "replay-import").start();
    }

    /** Copies the picked .sdfz files into demos/ (never over one already there); what to tell the player. */
    static String importAll(ContentResolver cr, List<Uri> picked, File bar) {
        File demos = new File(bar, "demos");
        //noinspection ResultOfMethodCallIgnored
        demos.mkdirs();
        int added = 0, there = 0, notReplays = 0, failed = 0, shortOnes = 0;
        for (Uri uri : picked) {
            String name = displayName(cr, uri);
            if (name == null || name.contains("/") || !name.toLowerCase(Locale.US).endsWith(".sdfz")) {
                notReplays++;
                Log.i("bridge", "replay import: not a BAR replay (.sdfz): " + name);
                continue;
            }
            File part = new File(demos, name + ".part");
            try {
                long n = copy(cr, uri, part);
                // (the lobby lists a replay only with its date at the start of its name, the engine's way: one renamed
                // on the way, "bd-import-test.sdfz", was copied and never shown, dev phone 2026-11-17; the game's start
                // from its header goes in front, in UTC as the lobby reads it)
                long[] hd = header(part);
                long started = hd[0];
                // (BAR's list leaves out a replay under a minute long, gui_replay_handler.lua: "1 replay added" for one it
                // then did not show, a 16 s test game, dev phone 2026-11-17; said so)
                boolean isShort = hd[1] > 0 && hd[1] < 60;
                if (!DATED.matcher(name).find())
                    name = new java.text.SimpleDateFormat("yyyy-MM-dd_HH-mm-ss-SSS_", Locale.US) {{
                        setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
                    }}.format(new java.util.Date(started > 0 ? started * 1000 : System.currentTimeMillis())) + name;
                File out = new File(demos, name);
                if (out.exists()) {
                    if (isShort) shortOnes++;
                    else there++;
                    //noinspection ResultOfMethodCallIgnored
                    part.delete();
                    Log.i("bridge", "replay import: already in the list: " + name);
                    continue;
                }
                if (!part.renameTo(out)) throw new IOException("could not name it " + name);
                added++;
                if (isShort) shortOnes++;
                Log.i("bridge", "replay import: " + name + " (" + n / 1024 + " KB)");
            } catch (NotReplay e) {   // (named .sdfz, but not one inside: said as such, not "could not be copied")
                notReplays++;
                //noinspection ResultOfMethodCallIgnored
                part.delete();
                Log.i("bridge", "replay import: " + name + ": " + e.getMessage());
            } catch (IOException | RuntimeException e) {
                // (RuntimeException too: a provider's SecurityException or IllegalArgumentException in this thread would
                // have ended the app's process, the lobby with it)
                failed++;
                //noinspection ResultOfMethodCallIgnored
                part.delete();
                Log.e("bridge", "replay import: " + name + ": " + e);
            }
        }
        if (added > 0) {
            File stamp = new File(bar, STAMP);
            //noinspection ResultOfMethodCallIgnored
            stamp.getParentFile().mkdirs();
            try (OutputStream o = new FileOutputStream(stamp)) {
                o.write((System.currentTimeMillis() + "\n").getBytes(StandardCharsets.US_ASCII));
            } catch (IOException e) { Log.e("bridge", "replay import: " + STAMP + ": " + e.getMessage()); }
        }
        List<String> parts = new ArrayList<>();
        if (added > 0) parts.add(added + (added == 1 ? " replay added" : " replays added"));
        if (shortOnes > 0) parts.add(shortOnes + (shortOnes == 1 ? " is" : " are") + " under a minute long, which the list leaves out");
        if (there > 0) parts.add(there + " already in the list");
        if (notReplays > 0) parts.add(notReplays + (notReplays == 1 ? " file is not" : " files are not") + " a BAR replay (.sdfz)");
        if (failed > 0) parts.add(failed + " could not be copied");
        String said = parts.isEmpty() ? "No replays added" : String.join("; ", parts);
        Log.i("bridge", "replay import: " + said);
        return said;
    }

    /** The date and time the lobby reads from a replay's name (gui_replay_handler.lua: dashes optional). */
    private static final java.util.regex.Pattern DATED = java.util.regex.Pattern.compile("^\\d{4}-?\\d{2}-?\\d{2}_\\d{2}-?\\d{2}-?\\d{2}");

    /**
     * The game's start (Unix seconds) and length (game seconds), 0 where not written, from the replay's header
     * (demofile.h DemoFileHeader: magic, version, headerSize, versionString[256], gameID[16], unixTime int64,
     * scriptSize, demoStreamSize, gameTime, ...); not a BAR replay: a {@link NotReplay}.
     */
    private static long[] header(File f) throws IOException {
        try (java.io.DataInputStream in = new java.io.DataInputStream(new java.util.zip.GZIPInputStream(new java.io.FileInputStream(f)))) {
            byte[] h = new byte[16 + 4 + 4 + 256 + 16 + 8 + 3 * 4];
            in.readFully(h);
            if (!new String(h, 0, 15, StandardCharsets.US_ASCII).equals("spring demofile")) throw new NotReplay("not a BAR replay");
            long t = 0;
            for (int i = 7; i >= 0; i--) t = (t << 8) | (h[296 + i] & 0xff);
            long len = (h[312] & 0xff) | (h[313] & 0xff) << 8 | (h[314] & 0xff) << 16 | (long) (h[315] & 0xff) << 24;
            return new long[]{t, len > Integer.MAX_VALUE ? 0 : len};
        } catch (java.io.EOFException | java.util.zip.ZipException e) { throw new NotReplay("not a BAR replay"); }
    }

    /** A file named .sdfz that holds no replay. */
    private static final class NotReplay extends IOException {
        NotReplay(String why) { super(why); }
    }

    /** A replay is a gzip file: its first two bytes checked as it is copied. */
    private static long copy(ContentResolver cr, Uri uri, File to) throws IOException {
        try (InputStream in = cr.openInputStream(uri); OutputStream o = new FileOutputStream(to)) {
            if (in == null) throw new IOException("could not be read");
            byte[] b = new byte[64 * 1024];
            long total = 0;
            int first = -1;   // (the first byte, until the second comes: a provider's first read may give one byte alone)
            for (int r; (r = in.read(b)) > 0; ) {
                for (int i = 0; i < r && total + i < 2; i++) {
                    int v = b[i] & 0xff;
                    if (total + i == 0) first = v;
                    else if (first != 0x1f || v != 0x8b) throw new NotReplay("not a BAR replay (no gzip header)");
                }
                total += r;
                if (total > MAX_BYTES) throw new IOException("larger than " + (MAX_BYTES >> 20) + " MB");
                o.write(b, 0, r);
            }
            if (total < 2) throw new NotReplay(total == 0 ? "empty" : "not a BAR replay (no gzip header)");
            return total;
        }
    }

    private static String displayName(ContentResolver cr, Uri uri) {
        try (Cursor c = cr.query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (c != null && c.moveToFirst() && !c.isNull(0)) return c.getString(0);
        } catch (RuntimeException e) { Log.e("bridge", "replay import: the file's name: " + e); }
        String last = uri.getLastPathSegment();
        return last == null ? null : last.substring(last.lastIndexOf('/') + 1);
    }
}
