package com.underarmcape.bardroid;

import android.os.SystemClock;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;

/**
 * Keeps BAR current the way BAR's PC launcher does, with the Android layer on top (docs/UPDATES.md). Before each
 * lobby or skirmish start it reads BAR's launcher config, installs a new engine beside the old one, brings the game
 * and lobby rapid tags up to date with pr-downloader, and remembers the set (engine + packages) that starts, so a
 * set that fails fast on its first start is rolled back to the last one that worked. Network or BAR trouble is logged
 * (loudly: "!!!"), never thrown: the game then starts with what is installed.
 */
public final class Updater {
    public interface Status { void status(String detail); }
    public enum Result { NONE, PROMOTED, ROLLED_BACK }

    static final String CONFIG_URL = "https://launcher-config.beyondallreason.dev/config.json";
    static final String REPO_MASTER = "https://repos-cdn.beyondallreason.dev/repos.gz";   // PRD_RAPID_REPO_MASTER
    static final String ENGINE_RELEASES = "https://github.com/beyond-all-reason/RecoilEngine/releases/download/";
    /** An engine exit with an error this soon after the first start of an update counts as the update failing. */
    static final long FAST_FAIL_MS = 120_000;
    /** Where the engine looks a rapid tag up, in order (springsettings RapidTagResolutionOrder). */
    private static final String[] RAPID_HOSTS = {"repos-cdn.beyondallreason.dev", "repos.beyondallreason.dev"};
    private static final String ENGINE_ARCH = Prefs.EMULATOR_BUILD ? "amd64-linux" : "arm64-linux";
    private static final Pattern VERSION = Pattern.compile("[0-9A-Za-z._-]+");
    private static final Pattern TAG = Pattern.compile("[A-Za-z0-9_.-]+:[A-Za-z0-9_.:-]+");
    private static final Pattern KEY = Pattern.compile("[A-Za-z0-9_]+");
    private static final Pattern PROGRESS = Pattern.compile("\\[Progress\\].*?(\\d+)/(\\d+)");
    private static final Pattern CONFIG_VAR = Pattern.compile("\"([A-Za-z0-9_]+)\"\\s*:\\s*\\{");
    private static final int MAX_BAD = 5;

    private final Paths p;
    private final Proot proot;
    private final File dir, stateFile, configFile, goodDir, launchedDir, preDir, layerFile;
    private final Properties state = new Properties();
    private final Downloader dl = new Downloader();
    private final Map<String, String> repoUrls = new HashMap<>();
    private final Map<String, String[]> localCache = new HashMap<>();
    private volatile boolean cancelled;

    public Updater(Paths p) {
        this.p = p;
        this.proot = new Proot(p);
        dir = new File(p.filesDir, "update");
        stateFile = new File(dir, "state.properties");
        configFile = new File(dir, "launcher-config.json");
        goodDir = new File(dir, "good");
        launchedDir = new File(dir, "launched");
        preDir = new File(dir, "pre");
        layerFile = new File(p.bar, "logs/android-layer.txt");
        //noinspection ResultOfMethodCallIgnored
        dir.mkdirs();
        load(stateFile, state);
    }

    public void cancel() { cancelled = true; dl.cancel(); }

    /**
     * At app start: Prefs follow the engine and tags of the last update (the build's pinned ones on a fresh install).
     */
    public static void useInstalled(Paths p) {
        Properties s = new Properties();
        load(new File(p.filesDir, "update/state.properties"), s);
        useTags(Arrays.asList(s.getProperty("tags", "").split(",")));
        for (String key : new String[]{"launched.engine", "good.engine"}) {
            String v = s.getProperty(key);
            if (v != null && new File(p.engineDir(v), "spring").exists()) { setEngine(v); return; }
        }
    }

    /** Prefs.gameTag / lobbyTag (Installer, LOBBY_TAG) follow the tags of BAR's launcher config. */
    private static void useTags(List<String> tags) {
        for (String t : tags) {
            if (!TAG.matcher(t).matches()) continue;
            if (t.contains("chobby")) Prefs.lobbyTag = t; else Prefs.gameTag = t;
        }
    }

    private static void setEngine(String ver) {
        Prefs.engineVersion = ver;
        Prefs.engineUrl = ENGINE_RELEASES + ver + "/recoil_" + ver + "_" + ENGINE_ARCH + ".7z";
    }

    /** A rapid name as the launcher shows it: "Beyond All Reason test-31836-b250a16" -> "test-31836-b250a16"; null for none. */
    static String gameRelease(String name) {
        if (name == null || name.trim().isEmpty()) return null;
        String n = name.trim();
        return n.startsWith("Beyond All Reason ") ? n.substring("Beyond All Reason ".length()).trim() : n;
    }

    /** The end of summary()'s line about the Android layer's misses (LauncherActivity shows it as a warning). */
    static final String MISSES = " of the app's adjustments to BAR did not apply: see the log";

    /** The launcher's status lines (one fact a line: a phone's width wrapped one long line mid-phrase). */
    public static String summary(Paths p) {
        Properties s = new Properties();
        load(new File(p.filesDir, "update/state.properties"), s);
        StringBuilder sb = new StringBuilder();   // (the engine's version is in the lines above: only a fallback here)
        String good = s.getProperty("good.engine");
        if (good != null && !good.equals(Prefs.engineVersion)) sb.append("Falls back to engine ").append(good).append("\n");
        // (BAR's release the last start played, what players compare for an online game; known after a start)
        String release = gameRelease(s.getProperty("name." + Prefs.gameTag));
        if (release != null) sb.append("Game version ").append(release).append("\n");
        // (updates on, the default: the last check says it, the setting below too; "BAR updates at start: on" took a
        // line of the four for that, dev phone 2026-11-08. Off is worth its line: nothing checks then)
        String off = "BAR updates: only with Install / Update";
        if (s.getProperty("check") != null) {
            sb.append("Last check ").append(s.getProperty("check"));
            if (!Prefs.autoUpdate) sb.append("\n").append(off);
        } else sb.append(Prefs.autoUpdate ? "BAR updates at every start" : off);
        int misses = s.getProperty("layer.engine") != null ? 1 : 0;
        // (the last start's own list: the count in the state is written when a game ends, so one stopped kept an old one)
        File layer = new File(p.bar, "logs/android-layer.txt");
        if (layer.exists()) try (BufferedReader r = new BufferedReader(new FileReader(layer))) {
            for (String l; (l = r.readLine()) != null; ) if (!l.trim().isEmpty()) misses++;
        } catch (IOException ignored) {}
        if (misses > 0) sb.append("\n").append(misses).append(MISSES);
        return sb.toString();
    }

    // ---- the check before a start ------------------------------------------------------------------

    /**
     * online: read BAR's launcher config and download what changed (automatic updates on, or Install / Update);
     * otherwise only the local check that every tag points at a downloaded package.
     */
    public void check(boolean online, Status st) throws InterruptedException {
        String engine = Prefs.engineVersion;
        if (!new File(p.engineDir(engine), "spring").exists()) {
            // Nothing could start without it (an app build that pins another engine): fetched with updates off too.
            Log.e("update", "!!! engine " + engine + " is not on disk: downloading it");
            installEngine(engine, engine, Prefs.engineUrl, st);
        }
        List<String> tags = tags();
        if (state.getProperty("good.engine") == null) {
            // First check: what is installed (and plays) is the version to fall back to.
            state.setProperty("good.engine", engine);
            for (String t : tags) {
                String[] l = local(t);
                if (l != null && sdp(l[0]).exists()) { state.setProperty("good." + t, l[0]); snapshot(repo(t), goodDir); }
            }
        }
        String result = "automatic updates off";
        if (online) {
            st.status("checking for BAR updates");
            JSONObject setup = fetchSetup();
            if (setup != null) {
                tags = setupTags(setup, tags);
                String[] target = setupEngine(setup);
                Map<String, String> remote = remoteMd5s(tags);
                Map<String, String> want = new TreeMap<>();
                for (String t : tags) {
                    String[] l = local(t);
                    want.put(t, remote.get(t) != null ? remote.get(t) : l != null ? l[0] : "none");
                }
                String wanted = set(target != null ? target[0] : engine, want);
                if (isBad(wanted)) {
                    Log.e("update", "!!! BAR's current version (" + wanted + ") failed to start here before: staying on "
                            + set(engine, localMd5s(tags)) + " until BAR moves on");
                    result = "BAR's current version failed here before; kept the last good one";
                } else {
                    boolean ok = target != null;
                    if (ok && !target[0].equals(engine)) {
                        ok = installEngine(engine, target[0], target[1], st);
                        if (ok) engine = target[0];
                    }
                    for (String t : tags) { if (cancelled) throw new InterruptedException(); ok &= updateTag(t, remote.get(t), engine, st); }
                    result = ok ? "up to date" : "not everything updated, see log";
                }
            // (the launcher's status line after "Last check <date>": "BAR's launcher config not reachable: started what
            // is installed" wrapped over three lines on an upright phone, at every start away from a network; the
            // version that played is the line above it. launcher.log keeps the reason, "no answer from ...")
            } else result = "no answer from BAR";
        }
        verifyTags(tags);
        // The set that starts now; launchEnded judges it.
        state.setProperty("launched.engine", engine);
        for (String t : tags) recordLaunched(t);
        state.setProperty("tags", String.join(",", tags));
        useTags(tags);
        state.setProperty("check", new SimpleDateFormat("MMM d HH:mm", Locale.US).format(new Date()) + " (" + result + ")");
        save();
        setEngine(engine);
        String launched = set("launched", tags), good = set("good", tags);
        if (!launched.equals(good))
            Log.i("update", "first start of " + launched + " (last good: " + good + "); rolled back if it fails within "
                    + FAST_FAIL_MS / 1000 + " s");
        else Log.i("update", "starting " + launched);
    }

    /** The game's and lobby's rapid tags: from BAR's launcher config (saved), else the build's. */
    private List<String> tags() {
        List<String> tags = new ArrayList<>();
        for (String t : state.getProperty("tags", "").split(","))
            if (TAG.matcher(t).matches()) tags.add(t);
        if (tags.isEmpty()) { tags.add(Prefs.gameTag); tags.add(Prefs.lobbyTag); }
        return tags;
    }

    private List<String> setupTags(JSONObject setup, List<String> fallback) {
        JSONObject downloads = setup.optJSONObject("downloads");
        JSONArray games = downloads != null ? downloads.optJSONArray("games") : null;
        List<String> tags = new ArrayList<>();
        if (games != null) for (int i = 0; i < games.length(); i++) {
            String t = games.optString(i);
            if (TAG.matcher(t).matches()) tags.add(t);
            else Log.e("update", "!!! BAR's launcher config: game '" + t + "' is not a rapid tag; ignored");
        }
        if (tags.isEmpty()) { Log.e("update", "!!! BAR's launcher config lists no games; keeping " + fallback); return fallback; }
        if (!tags.equals(fallback)) Log.i("update", "rapid tags " + fallback + " -> " + tags);
        return tags;
    }

    // ---- BAR's launcher config ---------------------------------------------------------------------

    private JSONObject fetchSetup() {
        Http r = get(CONFIG_URL, null);
        if (r == null || r.code != 200) return null;
        try {
            JSONObject cfg = new JSONObject(new String(r.body, StandardCharsets.UTF_8));
            JSONObject setup = pickSetup(cfg);
            if (setup == null) { Log.e("update", "!!! BAR's launcher config has no Linux setup; nothing updated"); return null; }
            writeAtomically(configFile, r.body);
            return setup;
        } catch (JSONException | IOException e) {
            Log.e("update", "!!! BAR's launcher config could not be read: " + e);
            return null;
        }
    }

    /** The setup BAR's PC launcher picks on Linux: "manual-linux" (Alpha), else the first Linux one with games. */
    private static JSONObject pickSetup(JSONObject cfg) {
        JSONArray setups = cfg.optJSONArray("setups");
        if (setups == null) return null;
        JSONObject first = null;
        for (int i = 0; i < setups.length(); i++) {
            JSONObject s = setups.optJSONObject(i);
            JSONObject pkg = s != null ? s.optJSONObject("package") : null;
            if (pkg == null) continue;
            if ("manual-linux".equals(pkg.optString("id"))) return s;
            JSONObject downloads = s.optJSONObject("downloads");
            if (first == null && "linux".equals(pkg.optString("platform")) && !s.optBoolean("no_downloads")
                    && downloads != null && downloads.optJSONArray("games") != null) first = s;
        }
        return first;
    }

    /** {version, URL of our ABI's archive} of the setup's engine, or null (logged). */
    private static String[] setupEngine(JSONObject setup) {
        JSONObject launch = setup.optJSONObject("launch");
        String name = launch != null ? launch.optString("engine") : "";
        String ver = name.startsWith("recoil_") ? name.substring("recoil_".length()) : "";
        if (!VERSION.matcher(ver).matches()) { Log.e("update", "!!! BAR's launcher config: engine '" + name + "' is not recoil_<version>; engine not updated"); return null; }
        String url = null;
        JSONObject downloads = setup.optJSONObject("downloads");
        JSONArray res = downloads != null ? downloads.optJSONArray("resources") : null;
        if (res != null) for (int i = 0; i < res.length(); i++) {
            JSONObject r = res.optJSONObject(i);
            if (r != null && ("engine/" + name).equals(r.optString("destination"))) url = r.optString("url");
        }
        // BAR's launcher ships amd64 only; every Recoil release also has the arm64 archive under the same name.
        String ours = url != null ? url.replace("_amd64-linux.7z", "_" + ENGINE_ARCH + ".7z") : null;
        if (ours == null || !ours.startsWith(ENGINE_RELEASES) || !ours.endsWith("/recoil_" + ver + "_" + ENGINE_ARCH + ".7z")) {
            Log.e("update", "!!! BAR's launcher config: engine download '" + url + "' is not an official Recoil "
                    + "release we can map to " + ENGINE_ARCH + "; engine not updated");
            return null;
        }
        return new String[]{ver, ours};
    }

    // ---- engine ------------------------------------------------------------------------------------

    /** Downloads and extracts a new engine beside the current one. False (logged) when it did not work. */
    private boolean installEngine(String old, String ver, String url, Status st) throws InterruptedException {
        File dest = p.engineDir(ver);
        if (new File(dest, "spring").exists()) { Log.i("update", "engine " + ver + " is already on disk"); return true; }
        Log.i("update", "==== new engine " + ver + " (was " + old + ")");
        File tmp = p.engineDir(ver + ".new");
        File z = new File(p.downloads, url.substring(url.lastIndexOf('/') + 1));
        try {
            z = dl.download(url, z, null, (done, total) ->
                    st.status("downloading engine " + ver + " " + Downloader.human(done) + " / " + Downloader.human(total)));
            st.status("installing engine " + ver);
            removeTree(tmp);
            removeTree(dest);   // (one half deleted, with no spring: the rename below would fail at every try)
            // Extracted under another name first: a half-extracted engine never looks installed.
            int rc = proot.runScript("update:engine", "/opt/bardroid/setup-container.sh", new HashMap<>(),
                    Arrays.asList("engine", "/root/downloads/" + z.getName(), ver + ".new"));
            if (rc != 0) throw new IOException("container step 'engine' failed with exit code " + rc);
            for (String f : new String[]{"spring", "pr-downloader"})
                if (!new File(tmp, f).exists()) throw new IOException(f + " missing from the engine archive");
            if (!tmp.renameTo(dest)) throw new IOException("could not rename " + tmp + " to " + dest);
            //noinspection ResultOfMethodCallIgnored
            z.delete();
        } catch (IOException e) {
            Log.e("update", "!!! engine " + ver + " not installed, staying on " + old + ": " + e.getMessage());
            removeTree(tmp);
            // A whole but damaged archive would otherwise be taken as downloaded at every later try (a .part resumes)
            if (z.isFile()) //noinspection ResultOfMethodCallIgnored
                z.delete();
            return false;
        }
        if (!old.equals(ver) && new File(p.engineDir(old), "spring").exists()) checkConfigKeys(old, ver);
        return true;
    }

    /** Android layer: springsettings keys of ours that the old engine knew and the new one does not. */
    private void checkConfigKeys(String old, String ver) throws InterruptedException {
        Set<String> before = configKeys(old), after = configKeys(ver);
        if (before.isEmpty() || after.isEmpty()) {
            Log.e("update", "!!! could not list the config keys of engine " + (before.isEmpty() ? old : ver) + ": springsettings.cfg not checked");
            return;
        }
        List<String> gone = new ArrayList<>();
        for (String k : springKeys().keySet()) if (before.contains(k) && !after.contains(k)) gone.add(k);
        if (gone.isEmpty()) { state.remove("layer.engine"); Log.i("update", "engine " + ver + " knows every springsettings key of ours"); return; }
        String miss = "engine " + ver + " no longer knows springsettings key(s) " + gone + " (" + old + " did): fix "
                + "assets/bardroid/springsettings.cfg / Installer.writeGameFiles";
        state.setProperty("layer.engine", miss);
        Log.e("update", "!!! ANDROID LAYER: " + miss);
    }

    /** The config keys an engine declares (spring --list-config-vars), cached per version. */
    private Set<String> configKeys(String ver) throws InterruptedException {
        Set<String> keys = new LinkedHashSet<>();
        File cache = new File(dir, "config-vars-" + ver + ".txt");
        if (!cache.exists()) try {
            File json = new File(p.downloads, "config-vars-" + ver + ".json");
            String sh = "cd /root/bar/engine/recoil_" + ver + " && timeout 60 ./spring --list-config-vars > /root/downloads/"
                    + json.getName() + " 2>/dev/null";
            Proc.run("update", proot.command(new HashMap<>(), Arrays.asList("/bin/sh", "-c", sh)), proot.hostEnv(), p.filesDir);
            StringBuilder out = new StringBuilder();
            if (json.exists()) try (BufferedReader r = new BufferedReader(new FileReader(json))) {
                for (String l; (l = r.readLine()) != null; ) {
                    Matcher m = CONFIG_VAR.matcher(l);
                    if (m.find()) out.append(m.group(1)).append('\n');
                }
            }
            //noinspection ResultOfMethodCallIgnored
            json.delete();
            if (out.length() == 0) return keys;
            writeAtomically(cache, out.toString().getBytes(StandardCharsets.UTF_8));
        } catch (IOException e) { Log.e("update", "engine " + ver + " config keys: " + e); return keys; }
        try (BufferedReader r = new BufferedReader(new FileReader(cache))) {
            for (String l; (l = r.readLine()) != null; ) if (!l.isEmpty()) keys.add(l);
        } catch (IOException ignored) {}
        return keys;
    }

    /** Keeps the last good engine and the one before it; BAR's launcher never deletes any, but a phone has less room. */
    private void cleanupEngines() throws InterruptedException {
        Set<String> keep = new LinkedHashSet<>(Arrays.asList(state.getProperty("good.engine"), state.getProperty("previous.engine"), Prefs.engineVersion));
        File[] dirs = new File(p.bar, "engine").listFiles();
        if (dirs != null) for (File d : dirs) {
            String n = d.getName();
            if (!n.startsWith("recoil_") || keep.contains(n.substring("recoil_".length()))) continue;
            Log.i("update", "removing old engine " + n);
            removeTree(d);
            //noinspection ResultOfMethodCallIgnored
            new File(dir, "config-vars-" + n.substring("recoil_".length()) + ".txt").delete();
        }
    }

    // ---- game and lobby (rapid) --------------------------------------------------------------------

    /** md5 of each tag on BAR's rapid server (null: unknown). An unchanged versions.gz costs a 304. */
    private Map<String, String> remoteMd5s(List<String> tags) {
        Map<String, String> md5s = new HashMap<>();
        Map<String, List<String>> byRepo = new LinkedHashMap<>();
        for (String t : tags) {
            List<String> l = byRepo.get(repo(t));
            if (l == null) byRepo.put(repo(t), l = new ArrayList<>());
            l.add(t);
        }
        for (Map.Entry<String, List<String>> e : byRepo.entrySet()) {
            String repo = e.getKey();
            Http r = get(repoUrl(repo) + "/versions.gz", state.getProperty("etag." + repo));
            if (r == null) continue;
            if (r.code == 200) {
                Map<String, String[]> found;
                try { found = findTags(new ByteArrayInputStream(r.body), e.getValue()); }
                catch (IOException ex) { Log.e("update", repo + "/versions.gz unreadable: " + ex); continue; }
                for (String t : e.getValue()) {
                    if (found.containsKey(t)) state.setProperty("remote." + t, found.get(t)[0]);
                    else { state.remove("remote." + t); Log.e("update", "!!! " + t + " is not on BAR's rapid server"); }
                }
                if (r.etag != null) state.setProperty("etag." + repo, r.etag); else state.remove("etag." + repo);
            }
            for (String t : e.getValue()) if (state.getProperty("remote." + t) != null) md5s.put(t, state.getProperty("remote." + t));
        }
        return md5s;
    }

    /** The repo's URL from BAR's repos.gz (what pr-downloader uses), else the usual one. */
    private String repoUrl(String repo) {
        if (repoUrls.isEmpty()) {
            Http r = get(REPO_MASTER, null);
            if (r != null && r.code == 200) try (BufferedReader in = gzLines(new ByteArrayInputStream(r.body))) {
                for (String l; (l = in.readLine()) != null; ) {
                    String[] f = l.split(",");
                    if (f.length >= 2 && f[1].matches("https://[a-z0-9.-]+\\.beyondallreason\\.dev/[A-Za-z0-9_.-]+")) repoUrls.put(f[0], f[1]);
                }
            } catch (IOException e) { Log.e("update", "repos.gz unreadable: " + e); }
            repoUrls.put("", "");   // looked once
        }
        String u = repoUrls.get(repo);
        return u != null ? u : "https://repos-cdn.beyondallreason.dev/" + repo;
    }

    /** pr-downloader on one tag (only missing files); the tag keeps its old package if the download fails (false). */
    private boolean updateTag(String tag, String remote, String engine, Status st) throws InterruptedException {
        String[] before = local(tag);
        if (remote != null && before != null && remote.equals(before[0]) && sdp(before[0]).exists()) {
            Log.i("update", tag + " is up to date (" + before[1] + ")");
            return true;
        }
        String repo = repo(tag);
        snapshot(repo, preDir);
        st.status("downloading " + tag);
        long[] shown = {0};
        int rc;
        try {
            Proc proc = new Proc("update").start(proot.command(new HashMap<>(),
                            Arrays.asList("/bin/bash", "/opt/bardroid/setup-container.sh", "rapid", tag, engine)),
                    proot.hostEnv(), p.filesDir, line -> {
                        Matcher m = PROGRESS.matcher(line);
                        long now = SystemClock.elapsedRealtime();
                        if (m.find() && now - shown[0] > 1000) {
                            shown[0] = now;
                            long done = Long.parseLong(m.group(1)), total = Math.max(1, Long.parseLong(m.group(2)));
                            st.status("downloading " + tag + " " + (done * 100 / total) + "%");
                        }
                    });
            rc = proc.waitFor();
        } catch (IOException e) { Log.e("update", "!!! " + tag + ": " + e); rc = -1; }
        String[] after = local(tag);
        if (rc != 0 || after == null || !sdp(after[0]).exists()) {
            String why = rc == 5 ? "disk too full" : rc != 0 ? "pr-downloader failed (exit " + rc + ")" : "package not complete";
            Log.e("update", "!!! " + tag + ": " + why + "; keeping " + (before != null ? before[1] : "nothing"));
            restore(repo, preDir);
            return false;
        }
        if (before == null || !after[0].equals(before[0]))
            Log.i("update", tag + ": " + (before != null ? before[1] : "none") + " -> " + after[1]);
        return true;
    }

    /** Local check: each tag points at a package that is downloaded (an interrupted download, another tag's run). */
    private void verifyTags(List<String> tags) {
        for (String t : tags) {
            String[] l = local(t);
            if (l != null && sdp(l[0]).exists()) continue;
            String good = state.getProperty("good." + t);
            Log.e("update", "!!! " + t + " points at " + (l != null ? l[1] + ", which is not downloaded" : "nothing")
                    + (good != null ? ": back to the last good index" : ""));
            if (good != null) restore(repo(t), goodDir);
        }
    }

    private static String repo(String tag) { return tag.substring(0, tag.indexOf(':')); }
    private File sdp(String md5) { return new File(p.bar, "packages/" + md5 + ".sdp"); }

    /** {md5, name} the engine resolves the tag to from the local rapid index, or null. */
    private String[] local(String tag) {
        File rapid = new File(p.bar, "rapid");
        List<File> files = new ArrayList<>();
        for (String h : RAPID_HOSTS) files.add(new File(rapid, h + "/" + repo(tag) + "/versions.gz"));
        File[] hosts = rapid.listFiles();
        if (hosts != null) for (File h : hosts) {
            File f = new File(h, repo(tag) + "/versions.gz");
            if (!files.contains(f)) files.add(f);
        }
        for (File f : files) {
            if (!f.exists()) continue;
            String key = f.getPath() + ':' + f.lastModified() + ':' + f.length() + ':' + tag;   // byar's index: 1.5 MB, 12,600 lines
            String[] e = localCache.get(key);
            if (e == null) try (InputStream in = new FileInputStream(f)) {
                e = findTags(in, java.util.Collections.singletonList(tag)).get(tag);
                localCache.put(key, e != null ? e : new String[0]);
            } catch (IOException ignored) {}
            if (e != null && e.length == 2) return e;
        }
        return null;
    }

    private Map<String, String> localMd5s(List<String> tags) {
        Map<String, String> m = new TreeMap<>();
        for (String t : tags) { String[] l = local(t); m.put(t, l != null ? l[0] : "none"); }
        return m;
    }

    /** versions.gz lines: tag,md5,depends,name. */
    private static Map<String, String[]> findTags(InputStream gz, Collection<String> tags) throws IOException {
        Map<String, String[]> found = new HashMap<>();
        try (BufferedReader r = gzLines(gz)) {
            for (String l; (l = r.readLine()) != null && found.size() < tags.size(); ) {
                int c = l.indexOf(',');
                if (c <= 0 || !tags.contains(l.substring(0, c))) continue;
                String[] f = l.split(",", 4);
                if (f.length == 4 && f[1].matches("[0-9a-f]{32}")) found.put(f[0], new String[]{f[1], f[3]});
            }
        }
        return found;
    }

    private static BufferedReader gzLines(InputStream gz) throws IOException {
        return new BufferedReader(new InputStreamReader(new GZIPInputStream(gz), StandardCharsets.UTF_8));
    }

    /** Saves the repo's rapid index (versions.gz of every host) into to/<host>/<repo>/. */
    private void snapshot(String repo, File to) { if (!copyIndex(repo, new File(p.bar, "rapid"), to)) deleteRepo(to, repo); }

    /** Puts a saved rapid index back: the repo's tags point where they pointed then. */
    private void restore(String repo, File from) {
        if (!copyIndex(repo, from, new File(p.bar, "rapid"))) Log.e("update", "no saved rapid index for " + repo + " to go back to");
    }

    /** Replaces the repo's versions.gz files under to with those under from; false (nothing changed) if from has none. */
    private static boolean copyIndex(String repo, File from, File to) {
        File[] hosts = from.listFiles();
        boolean any = false;
        if (hosts != null) for (File h : hosts) any |= new File(h, repo + "/versions.gz").exists();
        if (!any) return false;
        deleteRepo(to, repo);
        for (File h : hosts) {
            File f = new File(h, repo + "/versions.gz");
            if (f.exists()) copyFile(f, new File(to, h.getName() + "/" + repo + "/versions.gz"));
        }
        return true;
    }

    private static void deleteRepo(File root, String repo) {
        File[] hosts = root.listFiles();
        if (hosts != null) for (File h : hosts) //noinspection ResultOfMethodCallIgnored
            new File(h, repo + "/versions.gz").delete();
    }

    // ---- the result of a start ---------------------------------------------------------------------

    /** After the engine exited (not stopped by the player): keep the set that started, or roll a failed update back. */
    public Result launchEnded(int rc, long ms) throws InterruptedException {
        readLayerMisses();
        List<String> tags = tags();
        if (state.getProperty("launched.engine") == null) return Result.NONE;
        String launched = set("launched", tags), good = set("good", tags);
        // Ended from outside or by the network, not by the update: undecided, judged at the next start. 137 is a SIGKILL
        // from outside (Android's low-memory killer while an 8 GB phone loads, or the app closing a game the GPU driver
        // froze: GameService.driverLost), 233 the engine's EXIT_CODE_TIMEOUT (a join that timed out). Before, either in a
        // new version's first two minutes rolled BAR back to a version online games reject.
        if (rc == 137 || rc == 233) {
            if (!launched.equals(good))
                Log.i("update", "the game was ended from outside (" + rc + "): " + launched + " is judged at the next start");
            save();
            return Result.NONE;
        }
        // A crash once a game ran (loading one of Kailil's saves crashes the engine on every platform, ~70 s after the
        // app started) is not the update failing to start: it must not roll BAR back to a version online games reject.
        boolean fast = rc != 0 && ms < FAST_FAIL_MS && !gameFrameRan();
        Result result = Result.NONE;
        if (!launched.equals(good) && fast) {
            Log.e("update", "!!! the update to " + launched + " failed to start (exit " + rc + " after " + ms / 1000
                    + " s): back to " + good + ". Online battles on BAR's newer engine cannot be joined until this is fixed.");
            List<String> bad = new ArrayList<>();
            bad.add(launched);
            for (int i = 0; i < MAX_BAD - 1 && state.getProperty("bad." + i) != null; i++) bad.add(state.getProperty("bad." + i));
            for (int i = 0; i < bad.size(); i++) state.setProperty("bad." + i, bad.get(i));
            String engine = state.getProperty("good.engine");
            if (!new File(p.engineDir(engine), "spring").exists()) {
                Log.e("update", "!!! engine " + engine + " is gone from disk: keeping " + Prefs.engineVersion);
                engine = Prefs.engineVersion;
            }
            for (String t : tags) restore(repo(t), goodDir);
            state.setProperty("launched.engine", engine);
            for (String t : tags) recordLaunched(t);   // (the launcher's game version too: the failed update's name went)
            setEngine(engine);
            result = Result.ROLLED_BACK;
        } else if (!fast) {
            result = keepLaunched(tags, launched, good);
        }
        save();
        if (result == Result.PROMOTED) cleanupEngines();
        return result;
    }

    /**
     * The player closed the game (Stop, or swiped away from recent apps; launchEnded is not asked then): a set that ran
     * FAST_FAIL_MS or showed a game frame started fine. Before, only a game that ended by itself (BAR's Quit) kept a new
     * set, and the Fold7, closed by a swipe, kept the lobby of the day before as the one to fall back to, the new one
     * "first start" at every start (2026-11-08). A shorter one is judged at the next start, as before.
     */
    public void closedByPlayer(long ms) throws InterruptedException {
        List<String> tags = tags();
        if (state.getProperty("launched.engine") == null) return;
        if (ms < FAST_FAIL_MS && !gameFrameRan()) return;
        readLayerMisses();
        Result r = keepLaunched(tags, set("launched", tags), set("good", tags));
        save();
        if (r == Result.PROMOTED) cleanupEngines();
    }

    /** The set that started is the one to fall back to now. */
    private Result keepLaunched(List<String> tags, String launched, String good) {
        Result result = Result.NONE;
        if (!launched.equals(good)) {
            Log.i("update", launched + " started fine: it is now the version to fall back to");
            String oldEngine = state.getProperty("good.engine");
            if (oldEngine != null && !oldEngine.equals(state.getProperty("launched.engine"))) state.setProperty("previous.engine", oldEngine);
            result = Result.PROMOTED;
        }
        // The index as it was at the start: the lobby may have downloaded other versions since.
        state.setProperty("good.engine", state.getProperty("launched.engine"));
        for (String t : tags) {
            String md5 = state.getProperty("launched." + t);
            if (md5 != null) state.setProperty("good." + t, md5); else state.remove("good." + t);
            if (!copyIndex(repo(t), launchedDir, goodDir)) deleteRepo(goodDir, repo(t));
        }
        return result;
    }

    /**
     * The package the tag points at now, as the set that starts, with its index; and its release's name for the
     * launcher's status ("Beyond All Reason test-31836-b250a16"): read here, where the index is read anyway, as 1.5 MB
     * of it on the launcher's thread at every refresh would be too much.
     */
    private void recordLaunched(String t) {
        String[] l = local(t);
        if (l != null) state.setProperty("launched." + t, l[0]); else state.remove("launched." + t);
        if (l != null && !l[1].isEmpty()) state.setProperty("name." + t, l[1]); else state.remove("name." + t);
        snapshot(repo(t), launchedDir);
    }

    private static final Pattern GAME_FRAME = Pattern.compile("^\\[t=[^\\]]*\\]\\[f=0*[1-9]");

    /** Whether the engine's log of this run shows a game frame (a game or a loaded save ran). */
    private boolean gameFrameRan() {
        try (BufferedReader r = new BufferedReader(new FileReader(new File(p.bar, "infolog.txt")))) {
            for (String l; (l = r.readLine()) != null; ) if (GAME_FRAME.matcher(l).find()) return true;
        } catch (IOException ignored) {}
        return false;
    }

    /** launch-bar.sh lists the Android tweaks that found no target in logs/android-layer.txt (docs/UPDATES.md). */
    private void readLayerMisses() {
        int n = 0;
        if (layerFile.exists()) try (BufferedReader r = new BufferedReader(new FileReader(layerFile))) {
            for (String l; (l = r.readLine()) != null; ) if (!l.trim().isEmpty()) { n++; Log.e("update", "!!! ANDROID LAYER: " + l); }
        } catch (IOException ignored) {}
        state.setProperty("layer.misses", String.valueOf(n));
    }

    private String set(String prefix, List<String> tags) {
        Map<String, String> m = new TreeMap<>();
        for (String t : tags) m.put(t, state.getProperty(prefix + "." + t, "none"));
        return set(state.getProperty(prefix + ".engine", "none"), m);
    }

    /** A set as text: "engine 2026.07.04, byar-chobby:test 0123abcd, byar:test 4567ef01" (md5s shortened). */
    private static String set(String engine, Map<String, String> md5s) {
        StringBuilder sb = new StringBuilder("engine ").append(engine);
        for (Map.Entry<String, String> e : new TreeMap<>(md5s).entrySet())
            sb.append(", ").append(e.getKey()).append(' ').append(e.getValue().length() > 8 ? e.getValue().substring(0, 8) : e.getValue());
        return sb.toString();
    }

    private boolean isBad(String set) {
        for (int i = 0; i < MAX_BAD; i++) if (set.equals(state.getProperty("bad." + i))) return true;
        return false;
    }

    // ---- BAR's launcher settings, on top of which the Android layer wins ----------------------------

    /**
     * After Installer.writeGameFiles, every start: BAR's json_files (chobby_config.json, for launch-bar.sh) and its
     * launch.springsettings for keys our springsettings.cfg does not set; where ours set a key, ours win (logged).
     * BAR's default_springsettings are PC graphics defaults and stay out.
     */
    public void applyLauncherSettings() {
        if (!configFile.exists()) return;
        JSONObject cfg, setup;
        try (InputStream in = new FileInputStream(configFile)) {
            cfg = new JSONObject(new String(Installer.readAll(in), StandardCharsets.UTF_8));
            setup = pickSetup(cfg);
        } catch (IOException | JSONException e) { Log.e("update", "cached launcher config unreadable: " + e); return; }
        if (setup == null) return;
        try {
            JSONObject files = cfg.optJSONObject("json_files"), own = setup.optJSONObject("json_files");
            JSONObject chobby = own != null && own.has("chobby_config.json") ? own.optJSONObject("chobby_config.json")
                    : files != null ? files.optJSONObject("chobby_config.json") : null;
            File out = new File(p.bar, ".bardroid-chobby_config.json");
            if (chobby != null) writeAtomically(out, (chobby.toString(2) + "\n").getBytes(StandardCharsets.UTF_8));
            else //noinspection ResultOfMethodCallIgnored
                out.delete();
            JSONObject launch = setup.optJSONObject("launch");
            JSONObject overrides = launch != null ? launch.optJSONObject("springsettings") : null;
            if (overrides == null) return;
            Map<String, String> ours = springKeys();
            StringBuilder add = new StringBuilder();
            for (java.util.Iterator<String> it = overrides.keys(); it.hasNext(); ) {
                String k = it.next();
                Object v = overrides.opt(k);
                if (!KEY.matcher(k).matches() || v == null || v == JSONObject.NULL) continue;
                String val = String.valueOf(v).replace('\n', ' ');
                if (!ours.containsKey(k)) add.append(k).append(" = ").append(val).append('\n');
                else if (!ours.get(k).equals(val)) Log.i("update", "Android layer keeps " + k + " = " + ours.get(k) + " (BAR's launcher: " + val + ")");
            }
            if (add.length() > 0) {
                try (OutputStream o = new FileOutputStream(new File(p.bar, "springsettings.cfg"), true)) {
                    o.write(("# from BAR's launcher config (launch.springsettings)\n" + add).getBytes(StandardCharsets.UTF_8));
                }
                Log.i("update", "springsettings from BAR's launcher config: " + add.toString().trim().replace('\n', ';'));
            }
        } catch (IOException | JSONException e) { Log.e("update", "BAR's launcher settings not applied: " + e); }
    }

    /** Keys and values of files/bar/springsettings.cfg (as Installer.writeGameFiles wrote it). */
    private Map<String, String> springKeys() {
        Map<String, String> m = new LinkedHashMap<>();
        try (BufferedReader r = new BufferedReader(new FileReader(new File(p.bar, "springsettings.cfg")))) {
            for (String l; (l = r.readLine()) != null; ) {
                int eq = l.indexOf('=');
                if (eq > 0 && !l.startsWith("#") && !m.containsKey(l.substring(0, eq).trim())) m.put(l.substring(0, eq).trim(), l.substring(eq + 1).trim());
            }
        } catch (IOException ignored) {}
        return m;
    }

    // ---- utils -------------------------------------------------------------------------------------

    private static final class Http { int code; byte[] body; String etag; }

    /** GET with the PC launcher's short timeouts; null (logged) when there is no usable answer. */
    private static Http get(String url, String etag) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(5000);
            c.setReadTimeout(10000);
            c.setRequestProperty("User-Agent", "BARDroid/" + BuildConfig.VERSION_NAME);
            c.setRequestProperty("Accept-Encoding", "identity");   // a .gz must arrive as it is
            if (etag != null) c.setRequestProperty("If-None-Match", etag);
            try {
                Http h = new Http();
                h.code = c.getResponseCode();
                h.etag = c.getHeaderField("ETag");
                if (h.code == 200) try (InputStream in = c.getInputStream()) { h.body = Installer.readAll(in); }
                else if (h.code != 304) { Log.e("update", "HTTP " + h.code + " for " + url); return null; }
                return h;
            } finally { c.disconnect(); }
        } catch (IOException e) {
            Log.e("update", "no answer from " + url + ": " + e);
            return null;
        }
    }

    /** rm -rf (engine trees come from proot and may hold symlinks, which File.delete walks into). */
    private void removeTree(File f) throws InterruptedException {
        if (!f.exists()) return;
        try { Proc.run("update", Arrays.asList("/system/bin/rm", "-rf", f.getAbsolutePath()), null, p.filesDir); }
        catch (IOException e) { Log.e("update", "could not remove " + f + ": " + e); }
    }

    private static void copyFile(File from, File to) {
        //noinspection ResultOfMethodCallIgnored
        to.getParentFile().mkdirs();
        try (InputStream in = new FileInputStream(from)) { writeAtomically(to, Installer.readAll(in)); }
        catch (IOException e) { Log.e("update", "could not copy " + from + " to " + to + ": " + e); }
    }

    private static void writeAtomically(File f, byte[] data) throws IOException {
        //noinspection ResultOfMethodCallIgnored
        f.getParentFile().mkdirs();
        File tmp = new File(f.getPath() + ".tmp");
        try (OutputStream o = new FileOutputStream(tmp)) { o.write(data); }
        replace(tmp, f);
    }

    /**
     * rename(2) over the target (File.renameTo does not replace an existing file on Windows: tools/updater-test).
     * Every game start writes springsettings.cfg through here, so File.renameTo (also rename(2) on Android) backs it up.
     */
    static void replace(File from, File to) throws IOException {
        try {
            java.nio.file.Files.move(from.toPath(), to.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException | RuntimeException e) {
            if (!from.renameTo(to)) throw new IOException("could not replace " + to + ": " + e, e);
        }
    }

    private static void load(File f, Properties into) {
        if (f.exists()) try (InputStream in = new FileInputStream(f)) { into.load(in); } catch (IOException ignored) {}
    }

    private void save() {
        try {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            state.store(out, "BAR Droid update state (docs/UPDATES.md)");
            writeAtomically(stateFile, out.toByteArray());
        } catch (IOException e) { Log.e("update", "state not saved: " + e); }
    }
}
