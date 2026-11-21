package com.underarmcape.bardroid;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.util.List;

/** Stand-in for the app's Log (it writes launcher.log on the phone). */
final class Log {
    static void i(String t, String m) { System.out.println("     [" + t + "] " + m); }
    static void e(String t, String m) { System.out.println("     [" + t + "] E " + m); }
    static void e(String t, String m, Throwable x) { System.out.println("     [" + t + "] E " + m + ": " + x); }
}

/**
 * MapStore.java (the map storage limit) on made-up map folders: the engine's lines it reads a map's use from, the
 * record, and the pruning order (the ones played longest ago first, never the one played last nor the kept one, each
 * map's .md5.gz with it, down to the limit and no further).
 *   tools/map-store-test.ps1, tools/java-checks.sh
 */
public final class MapStoreTest {
    private static int failed;
    private static final long MB = 1L << 20;

    private static void check(boolean ok, String what) {
        System.out.println((ok ? "PASS  " : "FAIL  ") + what);
        if (!ok) failed++;
    }

    private static File map(File bar, String name, long mb, long mtime) throws IOException {
        File f = new File(new File(bar, "maps"), name);
        try (RandomAccessFile r = new RandomAccessFile(f, "rw")) { r.setLength(mb * MB); }   // (sparse: no real space)
        //noinspection ResultOfMethodCallIgnored
        f.setLastModified(mtime);
        File md5 = new File(f.getPath() + ".md5.gz");
        try (RandomAccessFile r = new RandomAccessFile(md5, "rw")) { r.setLength(80); }
        return f;
    }

    private static void delete(File f) {
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) delete(k);
        //noinspection ResultOfMethodCallIgnored
        f.delete();
    }

    public static void main(String[] args) throws Exception {
        // the engine's lines
        check("starwatcher_1.0.sd7".equals(MapStore.usedIn("[t=00:00:01.887544][f=-000001] [CAS::GASCB] Archive "
                + "file=\"starwatcher_1.0.sd7\" cs=\"51f3\"")), "a map's checksum line names its archive");
        check("Iron_Isle_V1.SDZ".equals(MapStore.usedIn("[CAS::GASCB] Archive file=\"Iron_Isle_V1.SDZ\" cs=\"0\"")),
                "an .sdz in capitals too");
        check(MapStore.usedIn("[CAS::GASCB] Archive file=\"ad33f718.sdp\" cs=\"0\"") == null, "a game package is no map");
        check(MapStore.usedIn("[PreGame::AddMapArchivesToVFS] using map \"Starwatcher 1.0\"") == null
                && MapStore.usedIn(null) == null, "other lines: none");

        File bar = new File(System.getProperty("java.io.tmpdir"), "map-store-test/bar");
        delete(bar.getParentFile());
        //noinspection ResultOfMethodCallIgnored
        new File(bar, "maps").mkdirs();
        long day = 86_400_000L, now = System.currentTimeMillis();
        map(bar, "a_old.sd7", 900, now - 30 * day);     // downloaded a month ago, never played
        map(bar, "b_played.sd7", 900, now - 40 * day);  // downloaded earlier, played yesterday (below)
        map(bar, "c_mid.sdz", 900, now - 20 * day);
        map(bar, "starwatcher_1.0.sd7", 900, now - 50 * day);   // the Play vs AI map: kept
        map(bar, "e_new.sd7", 900, now - day / 2);      // the newest
        long[] u = MapStore.usage(bar);
        check(u[0] == 4500 * MB && u[1] == 5, "usage: 5 maps, 4500 MB (the .md5.gz files not counted): " + (u[0] / MB) + " MB, " + u[1]);

        MapStore.markUsed(bar, "b_played.sd7");
        MapStore.markUsed(bar, "springcontent.sdz");   // (the engine's own archive: not in maps/)
        String record = new String(java.nio.file.Files.readAllBytes(new File(bar, MapStore.USED).toPath()), "UTF-8");
        check(record.contains("b_played.sd7=") && !record.contains("springcontent"), "the record: the map played, not the engine's archive");

        check(MapStore.prune(bar, 0, "Starwatcher 1.0").isEmpty() && MapStore.usage(bar)[1] == 5, "no limit: nothing removed");
        check(MapStore.prune(bar, 5000 * MB, "Starwatcher 1.0").isEmpty(), "under the limit: nothing removed");

        // 4500 MB over a 2700 MB limit: two maps go, the ones played or downloaded longest ago that are not kept:
        // starwatcher (kept, oldest), then a_old (30 days), c_mid (20 days); b_played was played now, e_new is new
        List<String> removed = MapStore.prune(bar, 2700 * MB, "Starwatcher 1.0");
        File maps = new File(bar, "maps");
        check(removed.size() == 2 && !new File(maps, "a_old.sd7").exists() && !new File(maps, "c_mid.sdz").exists(),
                "over the limit: the two longest ago removed, a_old then c_mid: " + removed);
        check(new File(maps, "starwatcher_1.0.sd7").exists(), "the kept map stays though oldest");
        check(new File(maps, "b_played.sd7").exists() && new File(maps, "e_new.sd7").exists(), "the played and the new stay");
        check(!new File(maps, "a_old.sd7.md5.gz").exists() && new File(maps, "e_new.sd7.md5.gz").exists(),
                "each removed map's .md5.gz with it, the others' stay");
        check(MapStore.usage(bar)[0] == 2700 * MB, "down to the limit and no further: " + (MapStore.usage(bar)[0] / MB) + " MB");
        check(removed.get(0).startsWith("a_old.sd7 (900 MB, downloaded "), "the log line: " + removed.get(0));

        // a limit below what is left: everything but the newest-played and the kept goes
        MapStore.markUsed(bar, "e_new.sd7");
        List<String> more = MapStore.prune(bar, 100 * MB, "Starwatcher 1.0");
        check(more.size() == 1 && more.get(0).startsWith("b_played.sd7 (900 MB, last played ")
                && new File(maps, "e_new.sd7").exists() && new File(maps, "starwatcher_1.0.sd7").exists(),
                "never the one played last nor the kept one: " + more);

        // a cut-off download's .tmp (pr-downloader renames it at its end): an old one goes, a fresh one (a download that
        // may still be running) stays, the maps stay (release overhaul audit, 2026-11-21)
        File oldPart = map(bar, "f_cut.sd7.tmp", 60, now - 2 * 3_600_000L);
        File freshPart = map(bar, "g_running.sdz.tmp", 40, now - 60_000L);
        long mapsBefore = MapStore.usage(bar)[1];
        List<String> parts = MapStore.dropCutDownloads(bar);
        check(parts.size() == 1 && parts.get(0).startsWith("f_cut.sd7.tmp (60 MB)") && !oldPart.exists() && freshPart.exists()
                && MapStore.usage(bar)[1] == mapsBefore, "a cut-off download's old .tmp removed, a fresh one and the maps kept: " + parts);
        check(MapStore.dropCutDownloads(new File(bar, "nothing-here")).isEmpty(), "no maps folder: nothing");

        delete(bar.getParentFile());
        System.out.println(failed == 0 ? "ALL PASS" : failed + " FAILED");
        System.exit(failed == 0 ? 0 : 1);
    }
}
