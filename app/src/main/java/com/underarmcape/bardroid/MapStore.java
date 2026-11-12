package com.underarmcape.bardroid;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Properties;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The maps BAR downloads (the write dir's maps/) kept under a size: the ones played longest ago go first (Kailil,
 * 2026-11-11: "a rolling map download size limit ... rotate downloaded maps", 3 GB). BAR's game files themselves stay
 * about the same size across its releases (the rapid pool shares their files: 2.26 GB on the dev phone, 25 MB of it
 * only for older releases); maps are what grows, 20 to 150 MB each, every new map an online game is on.
 *
 * <p>/data is mounted noatime, so a map's last use is the app's own record ({@link #USED}): the engine names each map
 * archive it checks as a game loads ("[CAS::GASCB] Archive file="...sd7""), GameService passes those lines here; a map
 * never seen in one counts from its download (its file's time). Pruned before an engine starts (GameService), never
 * under a running one; a pruned map downloads again when a game needs it (BAR's lobby, the launcher's Play vs AI).
 */
final class MapStore {
    /** The record of last uses: map archive file name = epoch milliseconds (in the write dir). */
    static final String USED = ".bardroid-maps-used";
    private static final Pattern ARCHIVE =
            Pattern.compile("\\[CAS::GASCB\\] Archive file=\"([^\"/]+\\.(?:sd7|sdz))\"", Pattern.CASE_INSENSITIVE);

    private static String lastMarked;
    private static long lastMarkedAt;

    private MapStore() {}

    /** The map archive an engine line names as checked for a game, or null (cheap for the other lines). */
    static String usedIn(String line) {
        if (line == null || !line.contains("[CAS::GASCB]")) return null;
        Matcher m = ARCHIVE.matcher(line);
        return m.find() ? m.group(1) : null;
    }

    /** Records that a game is on this map now (the same map again within a minute: once; a load names it ~10 times). */
    static synchronized void markUsed(File bar, String fileName) {
        long now = System.currentTimeMillis();
        if (fileName.equals(lastMarked) && now - lastMarkedAt < 60_000) return;
        // (the engine's own archives are checked the same way at each load, springcontent.sdz and the like: not maps)
        if (!new File(new File(bar, "maps"), fileName).isFile()) return;
        lastMarked = fileName;
        lastMarkedAt = now;
        Properties used = load(bar);
        used.setProperty(fileName, Long.toString(now));
        store(bar, used);
    }

    /** The maps' total size in bytes and how many there are: { bytes, count }. */
    static long[] usage(File bar) {
        long bytes = 0, count = 0;
        for (File f : maps(bar)) { bytes += f.length(); count++; }
        return new long[]{bytes, count};
    }

    /**
     * Deletes maps, the one played longest ago first, until they take at most capBytes (0: no limit). Never the one
     * played last, nor the archive keepName names (the launcher's Play vs AI map, by BAR's file naming: lower case,
     * spaces as underscores). Each map's ".md5.gz" beside it goes with it. Returns a line for each map removed.
     */
    static synchronized List<String> prune(File bar, long capBytes, String keepName) {
        List<String> removed = new ArrayList<>();
        if (capBytes <= 0) return removed;
        List<File> maps = maps(bar);
        long total = 0;
        for (File f : maps) total += f.length();
        if (total <= capBytes) return removed;
        Properties used = load(bar);
        String keep = keepName == null ? "" : keepName.trim().toLowerCase(Locale.ROOT).replace(' ', '_');
        File newest = null;
        for (File f : maps) if (newest == null || lastUse(used, f) > lastUse(used, newest)) newest = f;
        maps.sort((a, b) -> Long.compare(lastUse(used, a), lastUse(used, b)));
        for (File f : maps) {
            if (total <= capBytes) break;
            String base = f.getName().replaceFirst("(?i)\\.(sd7|sdz)$", "").toLowerCase(Locale.ROOT);
            if (f.equals(newest) || (!keep.isEmpty() && base.equals(keep))) continue;
            long size = f.length();
            String when = (used.getProperty(f.getName()) != null ? "last played " : "downloaded ")
                    + new java.text.SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(new java.util.Date(lastUse(used, f)));
            if (!f.delete()) { Log.e("maps", "could not delete " + f.getName()); continue; }
            //noinspection ResultOfMethodCallIgnored
            new File(f.getPath() + ".md5.gz").delete();
            used.remove(f.getName());
            total -= size;
            removed.add(String.format(Locale.ROOT, "%s (%d MB, %s)", f.getName(), size >> 20, when));
        }
        store(bar, used);
        return removed;
    }

    private static long lastUse(Properties used, File f) {
        String t = used.getProperty(f.getName());
        if (t != null) {
            try { return Long.parseLong(t); } catch (NumberFormatException ignored) {}
        }
        return f.lastModified();   // (never seen in a game: from its download)
    }

    private static List<File> maps(File bar) {
        File[] files = new File(bar, "maps").listFiles((d, n) -> {
            String l = n.toLowerCase(Locale.ROOT);
            return l.endsWith(".sd7") || l.endsWith(".sdz");
        });
        List<File> out = new ArrayList<>();
        if (files != null) for (File f : files) if (f.isFile()) out.add(f);
        return out;
    }

    private static Properties load(File bar) {
        Properties p = new Properties();
        File f = new File(bar, USED);
        if (f.isFile()) {
            try (InputStream in = new FileInputStream(f)) { p.load(in); } catch (IOException e) { Log.e("maps", "record unread", e); }
        }
        return p;
    }

    private static void store(File bar, Properties p) {
        File f = new File(bar, USED), tmp = new File(bar, USED + ".tmp");
        try (OutputStream o = new FileOutputStream(tmp)) {
            p.store(o, "BAR Droid: when each map was last played (MapStore)");
        } catch (IOException e) {
            Log.e("maps", "record unsaved", e);
            return;
        }
        // (a replacing move: File.renameTo onto an existing file fails on some systems, and the record went unsaved)
        try {
            java.nio.file.Files.move(tmp.toPath(), f.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            Log.e("maps", "record not saved", e);
        }
    }
}
