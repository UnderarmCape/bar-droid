package com.underarmcape.bardroid;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Properties;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * Updater.launchEnded, the rollback decision after the engine exits, on a made-up files dir: a set of engine A and
 * byar:test package "aaaa…" (the last good one) and engine B with "bbbb…" (the update that just started).
 */
public final class UpdaterTest {
    static final String HOST = "repos-cdn.beyondallreason.dev";
    static final String MD5_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", MD5_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    static int fails;

    static void check(String what, boolean ok) {
        System.out.println((ok ? "ok   " : "FAIL ") + what);
        if (!ok) fails++;
    }

    static void write(File f, String s) throws IOException {
        //noinspection ResultOfMethodCallIgnored
        f.getParentFile().mkdirs();
        Files.write(f.toPath(), s.getBytes(StandardCharsets.UTF_8));
    }

    static void versions(File f, String md5) throws IOException {
        //noinspection ResultOfMethodCallIgnored
        f.getParentFile().mkdirs();
        try (OutputStream o = new GZIPOutputStream(new FileOutputStream(f))) {
            o.write(("byar:test," + md5 + ",,Beyond All Reason test-" + md5.charAt(0) + "\n").getBytes(StandardCharsets.UTF_8));
        }
    }

    static String tagMd5(File versionsGz) throws IOException {
        try (InputStream in = new GZIPInputStream(new FileInputStream(versionsGz))) {
            return new String(Installer.readAll(in), StandardCharsets.UTF_8).split(",")[1];
        }
    }

    /** A files dir after an update to B started; good = A. pending = launched differs from good. */
    static Paths setup(String name, boolean pending, String infolog) throws IOException {
        File root = Files.createTempDirectory("updater-" + name).toFile();
        Paths p = new Paths(root);
        for (String v : new String[]{"A", "B", "OLD"}) write(new File(p.engineDir(v), "spring"), "");
        write(new File(p.bar, "packages/" + MD5_A + ".sdp"), "");
        write(new File(p.bar, "packages/" + MD5_B + ".sdp"), "");
        String launchedMd5 = pending ? MD5_B : MD5_A, launchedEngine = pending ? "B" : "A";
        versions(new File(p.bar, "rapid/" + HOST + "/byar/versions.gz"), launchedMd5);
        versions(new File(root, "update/good/" + HOST + "/byar/versions.gz"), MD5_A);
        versions(new File(root, "update/launched/" + HOST + "/byar/versions.gz"), launchedMd5);
        write(new File(root, "update/state.properties"),
                "tags=byar\\:test\ngood.engine=A\ngood.byar\\:test=" + MD5_A + "\nlaunched.engine=" + launchedEngine
                        + "\nlaunched.byar\\:test=" + launchedMd5 + "\nname.byar\\:test=Beyond All Reason test-"
                        + launchedMd5.charAt(0) + "\n");
        write(new File(p.bar, "infolog.txt"), infolog);
        Prefs.engineVersion = launchedEngine;
        return p;
    }

    static Properties state(Paths p) throws IOException {
        Properties s = new Properties();
        try (InputStream in = new FileInputStream(new File(p.filesDir, "update/state.properties"))) { s.load(in); }
        return s;
    }

    static final String NO_FRAME = "[t=00:00:01.000000][f=-000001] loading\n";
    static final String A_FRAME = NO_FRAME + "[t=00:01:10.000000][f=0000120] a game ran\n";

    public static void main(String[] a) throws Exception {
        Log.quiet = a.length == 0;

        Paths p = setup("fastfail", true, NO_FRAME);
        Updater.Result r = new Updater(p).launchEnded(1, 30_000);
        Properties s = state(p);
        check("update failed on its first start (exit 1 after 30 s, no game frame): rolled back", r == Updater.Result.ROLLED_BACK);
        check("  the engine goes back to the last good one", "A".equals(Prefs.engineVersion) && "A".equals(s.getProperty("launched.engine")));
        check("  byar:test points at the last good package again", MD5_A.equals(tagMd5(new File(p.bar, "rapid/" + HOST + "/byar/versions.gz"))));
        check("  the failed set is on the bad list", s.getProperty("bad.0", "").startsWith("engine B, byar:test bbbbbbbb"));
        check("  the launcher's game version is the last good one's", "Beyond All Reason test-a".equals(s.getProperty("name.byar:test")));

        // the launcher's "adjustments did not apply" line: engine B's springsettings miss counts only while B plays
        String missB = "engine B no longer knows springsettings key(s) [X] (A did): fix it";
        p = setup("enginemiss", true, NO_FRAME);
        Prefs.engineVersion = "A";   // (state from before the fix: rolled back, B's miss still there)
        write(new File(p.filesDir, "update/state.properties"), "tags=byar\\:test\ngood.engine=A\nlaunched.engine=A\nlayer.engine=" + missB + "\n");
        check("an older engine plays: the newer one's springsettings miss is not counted", !Updater.summary(p).contains(Updater.MISSES));
        Prefs.engineVersion = "B";
        check("  that engine plays: it is counted and named", Updater.summary(p).contains("1" + Updater.MISSES) && Updater.summary(p).contains(Updater.MISSES + "\nengine B no longer"));
        write(new File(p.filesDir, "update/state.properties"), "tags=byar\\:test\ncheck=Nov 11 00\\:57 (automatic updates off)\n");
        Prefs.autoUpdate = false;
        check("updates off: the last check's line without \"(automatic updates off)\", the line under it says it",
                Updater.summary(p).contains("Last check Nov 11 00:57\nBAR updates: only with Install / Update"));
        Prefs.autoUpdate = true;
        check("  updates on again: the check's result as it was", Updater.summary(p).contains("Last check Nov 11 00:57 (automatic updates off)"));
        p = setup("enginemissrollback", true, NO_FRAME);
        s = state(p);
        s.setProperty("layer.engine", missB);
        try (OutputStream o = new FileOutputStream(new File(p.filesDir, "update/state.properties"))) { s.store(o, null); }
        new Updater(p).launchEnded(1, 30_000);
        check("  rolled back from B to A: B's miss leaves the state", state(p).getProperty("layer.engine") == null);

        p = setup("crashafterframe", true, A_FRAME);
        r = new Updater(p).launchEnded(139, 70_000);
        s = state(p);
        check("a crash after a game frame ran (a saved game, 70 s): no rollback, the update is kept", r == Updater.Result.PROMOTED);
        check("  B is the last good set now", "B".equals(s.getProperty("good.engine")) && MD5_B.equals(s.getProperty("good.byar:test")));

        p = setup("clean", true, A_FRAME);
        r = new Updater(p).launchEnded(0, 600_000);
        s = state(p);
        check("a clean run of the update: promoted", r == Updater.Result.PROMOTED);
        check("  A is kept as the one before", "A".equals(s.getProperty("previous.engine")));
        check("  older engines removed, A and B kept", !p.engineDir("OLD").exists() && p.engineDir("A").exists() && p.engineDir("B").exists());

        p = setup("notpending", false, NO_FRAME);
        r = new Updater(p).launchEnded(1, 5_000);
        s = state(p);
        check("no update pending and a fast crash: nothing changes", r == Updater.Result.NONE
                && "A".equals(s.getProperty("good.engine")) && s.getProperty("bad.0") == null && "A".equals(Prefs.engineVersion));

        for (int code : new int[]{137, 233}) {   // a low-memory kill / the app's own close, a join that timed out
            p = setup("outside" + code, true, NO_FRAME);
            r = new Updater(p).launchEnded(code, 30_000);
            s = state(p);
            check("exit " + code + " in the update's first 30 s, no game frame: undecided, no rollback", r == Updater.Result.NONE
                    && "B".equals(s.getProperty("launched.engine")) && "A".equals(s.getProperty("good.engine"))
                    && s.getProperty("bad.0") == null && "B".equals(Prefs.engineVersion));
        }

        // the player closed the game (Stop, or swiped away): closedByPlayer keeps a set that ran, judges a short one later
        p = setup("closedlong", true, NO_FRAME);
        new Updater(p).closedByPlayer(140_000);
        s = state(p);
        check("closed by the player after 140 s: the update is kept", "B".equals(s.getProperty("good.engine"))
                && MD5_B.equals(s.getProperty("good.byar:test")) && "A".equals(s.getProperty("previous.engine")));
        p = setup("closedframe", true, A_FRAME);
        new Updater(p).closedByPlayer(70_000);
        s = state(p);
        check("closed after 70 s with a game frame: kept", "B".equals(s.getProperty("good.engine")));
        p = setup("closedloading", true, NO_FRAME);
        new Updater(p).closedByPlayer(25_000);
        s = state(p);
        check("closed while loading (25 s, no game frame): undecided, nothing changes", "A".equals(s.getProperty("good.engine"))
                && "B".equals(s.getProperty("launched.engine")) && s.getProperty("bad.0") == null);

        // the next start judges a run nothing judged when it ended (swiped away: One UI ends the app first)
        p = setup("nextlong", true, NO_FRAME + "[t=00:02:31.000000][f=-000001] the lobby, 151 s in\n");
        new Updater(p).judgeLastRun();
        s = state(p);
        check("the next start: the last run's lobby ran 151 s, then the app was ended from outside: the update is kept",
                "B".equals(s.getProperty("good.engine")) && MD5_B.equals(s.getProperty("good.byar:test"))
                        && "A".equals(s.getProperty("previous.engine")));
        p = setup("nextframe", true, A_FRAME);
        new Updater(p).judgeLastRun();
        check("  a game frame in its 70 s: kept", "B".equals(state(p).getProperty("good.engine")));
        p = setup("nextshort", true, NO_FRAME + "[t=00:00:40.000000][f=-000001] loading\n");
        new Updater(p).judgeLastRun();
        s = state(p);
        check("  40 s, no game frame: still undecided (a fast failure next rolls back)", "A".equals(s.getProperty("good.engine"))
                && "B".equals(s.getProperty("launched.engine")) && s.getProperty("bad.0") == null);
        p = setup("nextsame", false, A_FRAME);
        new Updater(p).judgeLastRun();
        check("  nothing pending: nothing changes", "A".equals(state(p).getProperty("good.engine")) && state(p).getProperty("previous.engine") == null);

        // the launcher's "Last check": a start that did not go online keeps the last one that did
        String online = "Nov 11 10:10 (no answer from BAR)", local = "Nov 11 10:22 (" + Updater.NOT_CHECKED + ")";
        check("last check: a game start that did not go online keeps the last online check", online.equals(Updater.checkLine(online, false, local)));
        check("  an online one replaces it", "Nov 11 11:00 (up to date)".equals(Updater.checkLine(online, true, "Nov 11 11:00 (up to date)")));
        check("  none yet: the start's own", local.equals(Updater.checkLine(null, false, local)));

        // the launcher's game version line (Updater.gameRelease on the rapid name the start's check keeps)
        check("game version: BAR's name without \"Beyond All Reason\"", "test-31836-b250a16".equals(Updater.gameRelease("Beyond All Reason test-31836-b250a16")));
        check("  another name as it is", "Some Mod 1.2".equals(Updater.gameRelease("Some Mod 1.2")));
        check("  none or empty: no line", Updater.gameRelease(null) == null && Updater.gameRelease(" ") == null);

        System.out.println(fails == 0 ? "ALL PASS" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
