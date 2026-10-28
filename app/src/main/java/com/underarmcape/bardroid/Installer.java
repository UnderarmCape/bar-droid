package com.underarmcape.bardroid;

import android.content.Context;
import android.content.res.AssetManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;
import java.util.zip.GZIPInputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * First-run installer. Each step is idempotent and records completion in install-state.properties, so a
 * crash or a cancelled download resumes where it stopped. Runs on a worker thread inside GameService.
 */
public final class Installer {
    public interface Status { void status(String step, String detail, int percent); }

    public static final String[] STEPS = {"rootfs", "apt", "mesa", "engine", "import", "content", "files"};

    private final Context ctx;
    private final Paths p;
    private final Proot proot;
    private final Properties state = new Properties();
    private final Downloader dl = new Downloader();
    private volatile boolean cancelled;

    public Installer(Context ctx, Paths p) {
        this.ctx = ctx;
        this.p = p;
        this.proot = new Proot(p);
        load();
    }

    private void load() {
        if (p.stateFile.exists()) try (FileInputStream in = new FileInputStream(p.stateFile)) { state.load(in); } catch (IOException ignored) {}
    }
    private void mark(String step) throws IOException {
        state.setProperty(step, "done");
        save();
    }
    private void save() throws IOException {
        try (FileOutputStream out = new FileOutputStream(p.stateFile)) { state.store(out, "bardroid install state"); }
    }
    public boolean isDone(String step) { return "done".equals(state.getProperty(step)); }
    public boolean isInstalled() {
        for (String s : STEPS) if (!isDone(s) && !s.equals("import")) return false;
        return !mesaOutdated();
    }

    /** The installed Mesa is not the one this build ships with (installs from before the URL was recorded: the first default). */
    private boolean mesaOutdated() {
        if (!isDone("mesa") || Prefs.mesaUrl.isEmpty()) return false;
        return !Prefs.mesaUrl.equals(state.getProperty("mesaUrl", Prefs.OLD_MESA_URLS[0]));
    }
    public void reset(String step) throws IOException { state.remove(step); try (FileOutputStream out = new FileOutputStream(p.stateFile)) { state.store(out, ""); } }
    public void cancel() { cancelled = true; dl.cancel(); }

    /** Runs every step that is not done yet. Throws on failure with a readable message. */
    public void installAll(Status st) throws Exception {
        p.mkdirs();
        refreshHostFiles();
        if (!new File(p.rootfs, ROOTFS_OK).exists() && isDone("rootfs")) {
            // A rootfs from before the completion marker existed (or a damaged one): redo it and everything on top.
            Log.e("install", "rootfs has no completion marker; reinstalling the container");
            for (String s : STEPS) state.remove(s);
            save();
        }
        step("rootfs", st, () -> installRootfs(st));
        step("apt", st, () -> runSetup("apt", st, "apt"));
        if (mesaOutdated()) { Log.i("install", "Mesa changed to " + Prefs.mesaUrl); state.remove("mesa"); save(); }
        step("mesa", st, () -> { installMesa(st); state.setProperty("mesaUrl", Prefs.mesaUrl); });
        step("engine", st, () -> installEngine(st));
        // import is optional: only when the user pushed content from a PC
        if (hasImport()) runSetup("import", st, "import", Prefs.engineVersion);
        step("content", st, () -> runSetup("content", st, "content", Prefs.gameTag, Prefs.lobbyTag, Prefs.mapName, Prefs.engineVersion));
        step("files", st, () -> writeGameFiles());
        if (Prefs.gamepadGame && !gamepadReady()) {
            try { installGamepadGame(st); }
            catch (InterruptedException e) { throw e; }
            catch (Exception e) { Log.e("install", "controller game not installed (singleplayer plays BAR's released game)", e); }
        }
        st.status("done", "Installed", 100);
    }

    private interface Step { void run() throws Exception; }
    private void step(String name, Status st, Step s) throws Exception {
        if (cancelled) throw new IOException("cancelled");
        if (isDone(name)) { Log.i("install", name + ": already done"); return; }
        int idx = Arrays.asList(STEPS).indexOf(name);
        st.status(name, "starting", idx * 100 / STEPS.length);
        Log.i("install", "==== step " + name);
        s.run();
        mark(name);
    }

    // ---- steps -------------------------------------------------------------------------------------

    /**
     * Fake /proc data, asset extraction and (once the rootfs exists) the container scripts. Cheap, so it runs
     * before every install and every launch: an app update must replace the scripts of the previous version.
     */
    public void refreshHostFiles() throws IOException {
        p.mkdirs();
        if (!p.proot().exists() || !p.prootLoader().exists()) throw new IOException("proot missing from " + p.nativeLibDir);
        if (!p.libXlorie().exists()) Log.e("install", "libXlorie.so not found in " + p.nativeLibDir + " (X server will not start)");
        proot.writeFakeProc();
        extractAssets();
        proot.writeShellScript(new File(p.filesDir, "container.sh"));
        if (new File(p.rootfs, "usr/bin").isDirectory()) installScripts();
    }

    /** Copies assets/bardroid/* into files/assets-bardroid (host side) — the scripts are then installed into the rootfs. */
    private void extractAssets() throws IOException {
        File out = new File(p.filesDir, "assets-bardroid");
        //noinspection ResultOfMethodCallIgnored
        out.mkdirs();
        AssetManager am = ctx.getAssets();
        String[] names = am.list("bardroid");
        if (names == null) throw new IOException("no assets");
        for (String n : names) {
            try (InputStream in = am.open("bardroid/" + n); OutputStream o = new FileOutputStream(new File(out, n))) { copy(in, o); }
        }
    }

    /**
     * Written into the rootfs only after a clean extraction; without it the rootfs is wiped and extracted again.
     * v2: trees from before Paths became canonical hold hard-link symlinks proot cannot resolve in the app.
     */
    private static final String ROOTFS_OK = ".bardroid-rootfs-ok-v2";

    private void installRootfs(Status st) throws Exception {
        if (new File(p.rootfs, ROOTFS_OK).exists()) { Log.i("install", "rootfs already extracted"); installScripts(); return; }
        String[] leftovers = p.rootfs.list((dir, name) -> !name.equals(".l2s"));
        if (leftovers != null && leftovers.length > 0) {
            Log.i("install", "removing an incomplete rootfs");
            int rm = Proc.run("rm", Arrays.asList("/system/bin/rm", "-rf", p.rootfs.getAbsolutePath()), null, p.filesDir);
            if (rm != 0 && p.rootfs.exists()) throw new IOException("could not remove the incomplete rootfs (rc=" + rm + ")");
        }
        st.status("rootfs", "fetching Debian image manifest", 10);
        String sha = null;
        try {
            String manifest = Downloader.fetchText(Prefs.rootfsManifestUrl);
            int i = manifest.indexOf("\"layers\"");
            int j = manifest.indexOf("sha256:", i);
            if (j > 0) sha = manifest.substring(j + 7, j + 7 + 64);
            Log.i("install", "rootfs layer sha256 " + sha);
        } catch (IOException e) { Log.e("install", "manifest fetch failed, downloading without checksum: " + e); }
        File tgz = dl.download(Prefs.rootfsBlobUrl, new File(p.downloads, "rootfs.tar.gz"), sha,
                (done, total) -> st.status("rootfs", "downloading Debian " + Downloader.human(done) + " / " + Downloader.human(total), 12));
        st.status("rootfs", "extracting Debian", 15);
        //noinspection ResultOfMethodCallIgnored
        p.rootfs.mkdirs();
        //noinspection ResultOfMethodCallIgnored
        p.l2s().mkdirs();          // proot --link2symlink keeps hard-link targets here; without it link() fails
        int rc = proot.extractRootfs(tgz);
        // busybox tar stops at the first error, so a non-zero exit means a partial tree.
        File loader = new File(p.rootfs, Prefs.EMULATOR_BUILD ? "usr/lib64/ld-linux-x86-64.so.2" : "usr/lib/ld-linux-aarch64.so.1");
        if (rc != 0) throw new IOException("rootfs extraction failed (tar exit code " + rc + "; see log)");
        if (!loader.exists()) throw new IOException("rootfs incomplete: " + loader + " missing");
        // proot leaves empty placeholder files where the busybox and tarball were bound in.
        //noinspection ResultOfMethodCallIgnored
        new File(p.rootfs, "busybox-bardroid").delete();
        //noinspection ResultOfMethodCallIgnored
        new File(p.rootfs, ".bardroid-rootfs.tar.gz").delete();
        // Basic container config
        //noinspection ResultOfMethodCallIgnored
        new File(p.rootfs, "tmp").mkdirs();
        //noinspection ResultOfMethodCallIgnored
        new File(p.rootfs, "root").mkdirs();
        //noinspection ResultOfMethodCallIgnored
        new File(p.rootfs, "dev").mkdirs();
        //noinspection ResultOfMethodCallIgnored
        new File(p.rootfs, "proc").mkdirs();
        //noinspection ResultOfMethodCallIgnored
        new File(p.rootfs, "sys").mkdirs();
        writeFile(new File(p.rootfs, "etc/resolv.conf"), "nameserver 1.1.1.1\nnameserver 8.8.8.8\n");
        writeFile(new File(p.rootfs, "etc/hosts"), "127.0.0.1 localhost bardroid\n::1 localhost\n");
        writeFile(new File(p.rootfs, "etc/hostname"), "bardroid\n");
        // Debian's docker rootfs has no /etc/machine-id; some tools want one.
        writeFile(new File(p.rootfs, "etc/machine-id"), "bardroidbardroidbardroidbardroid\n");
        installScripts();
        writeFile(new File(p.rootfs, ROOTFS_OK), Prefs.rootfsBlobUrl + "\n");
        //noinspection ResultOfMethodCallIgnored
        tgz.delete();
    }

    private void installScripts() throws IOException {
        File src = new File(p.filesDir, "assets-bardroid");
        File dst = new File(p.rootfs, "opt/bardroid");
        //noinspection ResultOfMethodCallIgnored
        dst.mkdirs();
        for (String n : new String[]{"setup-container.sh", "launch-bar.sh"}) {
            File f = new File(dst, n);
            try (InputStream in = new FileInputStream(new File(src, n)); OutputStream o = new FileOutputStream(f)) { copy(in, o); }
            //noinspection ResultOfMethodCallIgnored
            f.setExecutable(true, false);
        }
    }

    private void runSetup(String step, Status st, String... args) throws Exception {
        installScripts();
        st.status(step, "running container setup: " + step, -1);
        Map<String, String> env = new HashMap<>();
        int rc = proot.runScript("setup:" + step, "/opt/bardroid/setup-container.sh", env, Arrays.asList(args));
        if (rc != 0) throw new IOException("container step '" + step + "' failed with exit code " + rc + " (see log)");
    }

    private void installMesa(Status st) throws Exception {
        if (Prefs.mesaUrl.isEmpty()) { Log.i("install", "emulator build: keeping Debian's Mesa (llvmpipe software GL)"); return; }
        String name = Prefs.mesaUrl.substring(Prefs.mesaUrl.lastIndexOf('/') + 1);   // one file per release: no stale reuse
        File tgz = dl.download(Prefs.mesaUrl, new File(p.downloads, name), null,
                (done, total) -> st.status("mesa", "downloading Mesa " + Downloader.human(done) + " / " + Downloader.human(total), 40));
        try { runSetup("mesa", st, "mesa", "/root/downloads/" + tgz.getName()); }
        finally { //noinspection ResultOfMethodCallIgnored
            tgz.delete(); }   // a damaged download must not be taken for a finished one on the next try
    }

    private void installEngine(Status st) throws Exception {
        // Named after the release (a partial download of another version must not be resumed into it)
        String name = Prefs.engineUrl.substring(Prefs.engineUrl.lastIndexOf('/') + 1);
        File z = dl.download(Prefs.engineUrl, new File(p.downloads, name), null,
                (done, total) -> st.status("engine", "downloading engine " + Downloader.human(done) + " / " + Downloader.human(total), 55));
        try {
            runSetup("engine", st, "engine", "/root/downloads/" + z.getName(), Prefs.engineVersion);
            if (!new File(p.engineDir(Prefs.engineVersion), "spring").exists()) throw new IOException("engine binary missing after extraction");
        } finally { //noinspection ResultOfMethodCallIgnored
            z.delete(); }   // as Mesa: a failed extraction downloads again
    }

    private boolean hasImport() {
        for (String d : new String[]{"pool", "packages", "rapid", "maps", "games"}) if (new File(p.importDir, d).isDirectory()) return true;
        return false;
    }

    /**
     * No ship wakes (Kailil, 2026-10-27: "the sea wave trails behind ships is hideous on the lowest graphics settings"):
     * BAR's wake effects (waterwake-* CEGs from the ship scripts, and units wading) all draw the "wakegrey" particle
     * texture, which the engine loads by path with the write dir before the game archive (CBitmap::Load, VFS raw
     * first). A transparent 8x8 image of our own (not BAR content) at that path leaves the wakes invisible. Drawing
     * only: the simulation and online games are unaffected.
     */
    private void writeNoWakes() throws IOException {
        File f = new File(p.bar, "bitmaps/projectiletextures/wakegrey.tga");
        //noinspection ResultOfMethodCallIgnored
        f.getParentFile().mkdirs();
        byte[] tga = new byte[18 + 8 * 8 * 4];   // uncompressed 32-bit TGA, every pixel transparent black
        tga[2] = 2;                               // true colour
        tga[12] = 8; tga[14] = 8;                 // 8 x 8
        tga[16] = 32; tga[17] = 0x28;             // 32 bits, 8 alpha bits, top-left origin
        try (OutputStream o = new FileOutputStream(f)) { o.write(tga); }
    }

    /** springsettings.cfg, the AI stub, start script. Re-run whenever settings change. */
    public void writeGameFiles() throws IOException {
        File assets = new File(p.filesDir, "assets-bardroid");
        // The AngelScript ARM64 call stub fixes the official arm64 AI build; the amd64 engine needs nothing.
        File stub = new File(p.bar, "libasarm64.so");
        if (Prefs.EMULATOR_BUILD) { //noinspection ResultOfMethodCallIgnored
            stub.delete();
        } else try (InputStream in = new FileInputStream(new File(assets, "libasarm64.so")); OutputStream o = new FileOutputStream(stub)) { copy(in, o); }
        // The frame cap and the hidden-window events (tools/pace/pace.c), preloaded into the engine by launch-bar.sh. The
        // emulator build has its x86_64 build: no cap there (BARDROID_FPS 0), but the hidden window (screen off, catching
        // up) works the same, so catch-up can be tried on the laptop.
        File pace = new File(p.bar, "libbardroid_pace.so");
        String paceAsset = Prefs.EMULATOR_BUILD ? "libbardroid_pace-x86_64.so" : "libbardroid_pace.so";
        try (InputStream in = new FileInputStream(new File(assets, paceAsset)); OutputStream o = new FileOutputStream(pace)) { copy(in, o); }
        // Our own widget (not BAR content): the camera side of the two-finger pan (RtsTouch).
        File widgets = new File(p.bar, "LuaUI/Widgets");
        //noinspection ResultOfMethodCallIgnored
        widgets.mkdirs();
        // and the queued buildings near where the camera looks (launch-bar.sh turns BAR's Show Builder Queue off), and
        // BAR's chat lines laid out for the phone (names at the left edge, the text filling the box), and the unit info
        // panel with its text sized to fit (launch-bar.sh turns BAR's Info widget off), and BAR's player list small until
        // touched, and the touch tools for spectating (player cameras, following units), and the minimap half size on the
        // unfolded screen until touched, and the layout editor (three fingers held, or /hud in the chat)
        for (String name : new String[]{"bardroid_touch.lua", "bardroid_queue.lua", "bardroid_chat.lua", "bardroid_info.lua",
                "bardroid_players.lua", "bardroid_bench.lua", "bardroid_spectate.lua", "bardroid_minimap.lua",
                "bardroid_layout.lua"})
            try (InputStream in = new FileInputStream(new File(assets, name));
                 OutputStream o = new FileOutputStream(new File(widgets, name))) { copy(in, o); }
        // and in the lobby: a finger drag scrolls lists, a tap on a server shows its details first (Chobby loads it with
        // its "local widgets" setting, which launch-bar.sh switches on)
        File menuWidgets = new File(p.bar, "LuaMenu/Widgets");
        //noinspection ResultOfMethodCallIgnored
        menuWidgets.mkdirs();
        try (InputStream in = new FileInputStream(new File(assets, "bardroid_lobby_touch.lua"));
             OutputStream o = new FileOutputStream(new File(menuWidgets, "bardroid_lobby_touch.lua"))) { copy(in, o); }
        writeNoWakes();
        // Widgets of the removed touch-only mode (Kailil, 2026-10-25): gone from earlier installs too.
        for (String name : new String[]{"bardroid_touch_hud.lua", "bardroid_touch_dock.lua", "bardroid_touch_build.lua"})
            //noinspection ResultOfMethodCallIgnored
            new File(widgets, name).delete();
        // springsettings.cfg: kept and completed (SettingsMerge), the Android keys and the user's knobs set
        java.util.List<String> template = readLines(new File(assets, "springsettings.cfg"));
        Map<String, String> templateKeys = SettingsMerge.keys(template);
        Map<String, String> set = new java.util.LinkedHashMap<>();
        for (String key : SettingsMerge.ALWAYS) if (templateKeys.containsKey(key)) set.put(key, templateKeys.get(key));
        set.put("WorkerThreadCount", String.valueOf(Prefs.workerThreads));
        set.put("RapidTagResolutionOrder", "repos-cdn.beyondallreason.dev;repos.beyondallreason.dev");
        if (Prefs.EMULATOR_BUILD) set.putAll(EMULATOR_GRAPHICS);
        File out = new File(p.bar, "springsettings.cfg");
        String cfg = SettingsMerge.merge(template, out.exists() ? readLines(out) : null, set);
        // Replaced whole: the app killed mid-write must not cut off the player's BAR settings.
        File tmp = new File(out.getPath() + ".tmp");
        writeFile(tmp, cfg);
        Updater.replace(tmp, out);
        writeStartScript();
    }

    private static java.util.List<String> readLines(File f) throws IOException {
        java.util.List<String> lines = new java.util.ArrayList<>();
        try (BufferedReader r = new BufferedReader(new FileReader(f))) {
            for (String l; (l = r.readLine()) != null; ) lines.add(l);
        }
        return lines;
    }

    /** Emulator build: OpenGL goes through virgl (or the CPU), so trade looks for frame time.
     *  MaxParticles stays at the template's 10000: BAR's Lua breaks below that (see springsettings.cfg). */
    private static final Map<String, String> EMULATOR_GRAPHICS = new java.util.LinkedHashMap<String, String>() {{
        put("VSync", "0");
        put("Water", "0");
        put("AdvMapShading", "0");
        put("AdvUnitShading", "0");
        put("GroundDetail", "20");
    }};

    /** Human (team 0) vs one AI (team 1), on the controller game when it is installed, else on BAR's released game. */
    public void writeStartScript() throws IOException {
        File assets = new File(p.filesDir, "assets-bardroid");
        String tpl;
        try (InputStream in = new FileInputStream(new File(assets, "skirmish.template.txt"))) { tpl = new String(readAll(in), StandardCharsets.UTF_8); }
        String game = useGamepadGame() ? GAMEPAD_GAME : resolveGameName();
        tpl = tpl.replace("@GAME@", game).replace("@MAP@", Prefs.mapName);
        // AI difficulty is a BARb option; keep ShortName=BARb (the only native AI shipped in the arm64 engine archive).
        writeFile(new File(p.bar, "skirmish.txt"), tpl);
        // BAR's "Benchmark BAR" scenario as its lobby starts it (the lobby's _script.txt, 2026-10-27: 650 Grunts against
        // 650 Pawns on Starwatcher 1.0, 2000 frames), with the singleplayer game: launch-bar.sh MODE=bench
        String bench;
        try (InputStream in = new FileInputStream(new File(assets, "benchmark.template.txt"))) { bench = new String(readAll(in), StandardCharsets.UTF_8); }
        writeFile(new File(p.bar, "bench.txt"), bench.replace("@GAME@", game));
    }

    /** The benchmark's map (benchmark.template.txt). */
    public static final String BENCH_MAP = "Starwatcher 1.0";

    /** Looks up the display name for the game tag in the downloaded rapid index; falls back to the tag itself. */
    private String resolveGameName() {
        File rapid = new File(p.bar, "rapid");
        File[] hosts = rapid.listFiles();
        if (hosts != null) for (File h : hosts) {
            File v = new File(h, "byar/versions.gz");
            if (!v.exists()) continue;
            try (BufferedReader r = new BufferedReader(new InputStreamReader(new GZIPInputStream(new FileInputStream(v)), StandardCharsets.UTF_8))) {
                String l;
                while ((l = r.readLine()) != null) {
                    if (l.startsWith(Prefs.gameTag + ",")) {
                        String[] f = l.split(",", 4);
                        if (f.length == 4 && !f[3].isEmpty()) return f[3];
                    }
                }
            } catch (IOException ignored) {}
        }
        return Prefs.gameTag;
    }

    // ---- the controller game -------------------------------------------------------------------------

    /**
     * Kailil's controller (BAR Controller Support v0.8.5, tools/build-gamepad-game.py) is BAR's own game with the
     * controller added, so it runs as BAR's developer game under this name, the game of the lobby's
     * "Beyond All Reason Dev" setting. games/BAR-gamepad.sdd holds only v0.8.5's files; its modinfo.lua depends on
     * the BAR release v0.8.5 was ported to, which the engine loads under it.
     */
    public static final String GAMEPAD_GAME = "Beyond All Reason $VERSION";

    private Properties gamepadInfo() throws IOException {
        Properties info = new Properties();
        try (InputStream in = ctx.getAssets().open("gamepad/gamepad.properties")) { info.load(in); }
        return info;
    }

    private File gamepadDir() { return new File(p.bar, "games/BAR-gamepad.sdd"); }

    /**
     * This app build carries the controller game (`tools/build-gamepad-game.py` writes assets/gamepad). Kailil
     * (2026-10-26): out of the builds until v0.8.5's frame cost is down; a build without it removes an installed one.
     */
    public boolean gamepadAvailable() {
        try { ctx.getAssets().open("gamepad/gamepad.properties").close(); return true; }
        catch (IOException e) { return false; }
    }

    /** games/BAR-gamepad.sdd is this app build's v0.8.5. */
    public boolean gamepadReady() {
        try {
            return gamepadInfo().getProperty("version").equals(state.getProperty("gamepad"))
                    && new File(gamepadDir(), "modinfo.lua").exists();
        } catch (IOException e) { return false; }
    }

    /** Singleplayer plays the controller game: the setting is on and the game is installed. */
    public boolean useGamepadGame() { return Prefs.gamepadGame && gamepadReady(); }

    /**
     * Downloads the BAR release v0.8.5 was ported to (pr-downloader fetches only files missing from the pool) and
     * unpacks v0.8.5 as games/BAR-gamepad.sdd. Optional: without it singleplayer plays BAR's released game.
     */
    public void installGamepadGame(Status st) throws Exception {
        if (!gamepadAvailable()) {
            if (gamepadDir().exists() || state.getProperty("gamepad") != null) {
                deleteTree(gamepadDir());
                state.remove("gamepad");
                save();
                Log.i("install", "controller game removed (not in this app build): singleplayer plays BAR's released game");
            }
            return;
        }
        Properties info = gamepadInfo();
        Log.i("install", "==== controller game " + info.getProperty("version") + " on " + info.getProperty("base.name"));
        st.status("gamepad", "downloading " + info.getProperty("base.name"), -1);
        runSetup("gamepad", st, "gamepad", info.getProperty("base.tag"), Prefs.engineVersion);
        File dir = gamepadDir(), tmp = new File(p.bar, "games/BAR-gamepad.sdd.tmp");
        deleteTree(tmp);
        String root = tmp.getCanonicalPath() + File.separator;
        try (ZipInputStream z = new ZipInputStream(ctx.getAssets().open("gamepad/gamepad.zip"))) {
            for (ZipEntry e; (e = z.getNextEntry()) != null; ) {
                if (e.isDirectory()) continue;
                File f = new File(tmp, e.getName());
                if (!f.getCanonicalPath().startsWith(root)) throw new IOException("bad zip entry " + e.getName());
                //noinspection ResultOfMethodCallIgnored
                f.getParentFile().mkdirs();
                try (OutputStream o = new FileOutputStream(f)) { copy(z, o); }
            }
        }
        // BAR artwork v0.8.5 shows under its own names, and BAR files the lobby reads from this archive alone
        // (modoptions.lua: the Skirmish screen): copied from the downloaded release, never shipped in the APK.
        Map<String, String> files = sdpFiles(new File(p.bar, "packages/" + info.getProperty("base.md5") + ".sdp"));
        for (String key : info.stringPropertyNames()) {
            if (!key.startsWith("copy.")) continue;
            String[] f = info.getProperty(key).trim().split("\\s+");
            String md5 = files.get(f[1].toLowerCase(Locale.ROOT));
            if (md5 == null) throw new IOException(f[1] + " is not in " + info.getProperty("base.name"));
            File out = new File(tmp, f[0]);
            //noinspection ResultOfMethodCallIgnored
            out.getParentFile().mkdirs();
            File gz = new File(p.bar, "pool/" + md5.substring(0, 2) + "/" + md5.substring(2) + ".gz");
            try (InputStream in = new GZIPInputStream(new FileInputStream(gz)); OutputStream o = new FileOutputStream(out)) { copy(in, o); }
        }
        deleteTree(dir);
        if (!tmp.renameTo(dir)) throw new IOException("could not rename " + tmp + " to " + dir);
        state.setProperty("gamepad", info.getProperty("version"));
        save();
        Log.i("install", "controller game ready: " + dir);
    }

    /** File name (lower case) -> pool md5 of a rapid package: gzip of [name length, name, md5, crc32, size] per file. */
    private static Map<String, String> sdpFiles(File sdp) throws IOException {
        Map<String, String> m = new HashMap<>();
        try (java.io.DataInputStream in = new java.io.DataInputStream(new java.io.BufferedInputStream(new GZIPInputStream(new FileInputStream(sdp))))) {
            byte[] name = new byte[255], md5 = new byte[16], rest = new byte[8];
            for (int n; (n = in.read()) >= 0; ) {
                in.readFully(name, 0, n);
                in.readFully(md5);
                in.readFully(rest);
                StringBuilder hex = new StringBuilder(32);
                for (byte b : md5) hex.append(String.format("%02x", b & 0xff));
                m.put(new String(name, 0, n, StandardCharsets.UTF_8).toLowerCase(Locale.ROOT), hex.toString());
            }
        }
        return m;
    }

    private static void deleteTree(File f) throws IOException {
        File[] children = f.isDirectory() ? f.listFiles() : null;
        if (children != null) for (File c : children) deleteTree(c);
        if (f.exists() && !f.delete()) throw new IOException("could not delete " + f);
    }

    // ---- utils ---------------------------------------------------------------------------------------

    static void writeFile(File f, String content) throws IOException {
        //noinspection ResultOfMethodCallIgnored
        f.getParentFile().mkdirs();
        try (FileWriter w = new FileWriter(f)) { w.write(content); }
    }
    static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] b = new byte[1 << 16]; int n;
        while ((n = in.read(b)) > 0) out.write(b, 0, n);
    }
    /** InputStream.readAllBytes() only exists on Android 13+; minSdk is 28. */
    static byte[] readAll(InputStream in) throws IOException {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        copy(in, out);
        return out.toByteArray();
    }
}
