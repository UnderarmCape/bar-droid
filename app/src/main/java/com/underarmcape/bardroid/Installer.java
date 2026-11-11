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
        slimContainer(st);
        step("engine", st, () -> installEngine(st));
        // import is optional: only when the user pushed content from a PC
        if (hasImport()) runSetup("import", st, "import", Prefs.engineVersion);
        step("content", st, () -> runSetup("content", st, "content", Prefs.gameTag, Prefs.lobbyTag, Prefs.mapName, Prefs.engineVersion));
        step("files", st, () -> writeGameFiles());
        try { removeGamepadGame(); } catch (IOException e) { Log.e("install", "the controller game's files", e); }
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

    /**
     * What the game never loads, out of the container, once (setup-container.sh "slim": ~300 MB on a phone). Not one
     * of {@link #STEPS}: an install from before it stays installed (the icon still opens the lobby) and gets it at
     * its next start (GameService.play). Never fails a start: the files then stay where they were.
     */
    public void slimContainer(Status st) {
        if (isDone("slim") || !isDone("mesa")) return;
        try {
            Log.i("install", "==== step slim");
            runSetup("slim", st, "slim");
            mark("slim");
        } catch (Exception e) {
            Log.e("install", "slim: " + e.getMessage());
        }
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
        // unfolded screen until touched, and the layout editor (three fingers held, or /hud in the chat), and the
        // app's copy of BAR's Build menu that the editor sizes and of its Order menu (launch-bar.sh switches them in,
        // see writeBarCopiesMd5), and BAR's GL4 unit shaders kept off in launch-bar.sh's low-memory mode (8 GB phones), and
        // while a building is picked the build ranges of the nearest builders only, not the engine's one of every turret,
        // and BAR's sonar, radar and line-of-sight circles off in big games (their GPU cost grows with the square of the units),
        // and builders' nano spray drawn by the engine with a cap (BAR's own 3D spray has a floor of 5000 particles), and
        // upright BAR's top bar buttons answering over its hidden resource bars (bardroid_topbar.lua)
        for (String name : new String[]{"bardroid_touch.lua", "bardroid_queue.lua", "bardroid_chat.lua", "bardroid_info.lua",
                "bardroid_players.lua", "bardroid_bench.lua", "bardroid_spectate.lua", "bardroid_minimap.lua",
                "bardroid_layout.lua", "bardroid_buildmenu.lua", "bardroid_ordermenu.lua", "bardroid_pad.lua", "bardroid_padspeed.lua",
                "bardroid_padfp.lua", "bardroid_lowmem.lua", "bardroid_buildrange.lua", "bardroid_sensors.lua", "bardroid_nano.lua",
                "bardroid_portrait.lua", "bardroid_missioninfo.lua", "bardroid_retreat.lua", "bardroid_presets.lua", "bardroid_automex.lua", "bardroid_teamstats.lua",
                "bardroid_topbar.lua"})
            try (InputStream in = new FileInputStream(new File(assets, name));
                 OutputStream o = new FileOutputStream(new File(widgets, name))) { copy(in, o); }
        installPhoneLua(assets);
        writeBarCopiesMd5();
        // the lobby's first picture for an upright screen (launch-bar.sh puts it in MenuLoadscreens while upright)
        try (InputStream in = new FileInputStream(new File(assets, "loadscreen-upright.png"));
             OutputStream o = new FileOutputStream(new File(p.bar, ".bardroid-loadscreen-upright.png"))) { copy(in, o); }
        // and BAR's load screen pictures for an upright screen (tools/make-loadpictures.ps1: loadpicture-upright_<name>;
        // launch-bar.sh puts them under BAR's names while upright): copied when new or changed
        File lpTo = new File(p.bar, ".bardroid-loadpictures-upright");
        File[] lps = assets.listFiles((dir, n) -> n.startsWith("loadpicture-upright_"));
        if (lps != null && lps.length > 0) {
            //noinspection ResultOfMethodCallIgnored
            lpTo.mkdirs();
            for (File f : lps) {
                File t = new File(lpTo, f.getName().substring("loadpicture-upright_".length()));
                if (t.length() == f.length()) continue;
                try (InputStream in = new FileInputStream(f); OutputStream o = new FileOutputStream(t)) { copy(in, o); }
            }
        }
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

    /**
     * The phone versions of BAR's widgets and of its gadgets' unsynced halves, as patches to BAR's own files
     * (assets phone-widget-*.lua.patch, phone-gadget-*.lua.patch; tools/phone-lua-check.py): into bardroid-phone/LuaUI/Widgets
     * and bardroid-phone/LuaRules/Gadgets, where an engine-branch build applies them as LuaUI and the unsynced LuaRules
     * state load BAR's files (BarDroidPhoneLuaDir, which launch-bar.sh sets with BARDROID_PHONE_LUA=1 in dev-env.sh;
     * docs/ENGINE-SIM.md on engine/sim, "BAR's Lua on phones"). The folder holds the current set only.
     */
    private void installPhoneLua(File assets) throws IOException {
        File root = new File(p.bar, "bardroid-phone");
        String[][] kinds = {{"phone-widget-", "LuaUI/Widgets"}, {"phone-gadget-", "LuaRules/Gadgets"}};
        for (String[] k : kinds) {
            File dir = new File(root, k[1]);
            File[] old = dir.listFiles();
            if (old != null) for (File f : old) //noinspection ResultOfMethodCallIgnored
                f.delete();
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
            File[] patches = assets.listFiles((d, n) -> n.startsWith(k[0]) && n.endsWith(".lua.patch"));
            if (patches == null) continue;
            for (File f : patches)
                try (InputStream in = new FileInputStream(f);
                     OutputStream o = new FileOutputStream(new File(dir, f.getName().substring(k[0].length())))) { copy(in, o); }
        }
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

    /** Human (team 0) vs one AI (team 1), on BAR's released game. */
    public void writeStartScript() throws IOException {
        File assets = new File(p.filesDir, "assets-bardroid");
        String tpl;
        try (InputStream in = new FileInputStream(new File(assets, "skirmish.template.txt"))) { tpl = new String(readAll(in), StandardCharsets.UTF_8); }
        String game = resolveGameName();
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

    /** On the phone? BAR's map files are named after their map: Starwatcher 1.0 is maps/starwatcher_1.0.sd7. */
    public boolean hasMap(String name) {
        String file = "maps/" + name.toLowerCase(Locale.ROOT).replace(' ', '_');
        return new File(p.bar, file + ".sd7").exists() || new File(p.bar, file + ".sdz").exists();
    }

    /** BAR's widgets the app runs a copy of in their place (launch-bar.sh): BAR's file, the copy, its patches, the file
     *  that tells launch-bar.sh BAR's md5, the copy's line naming the md5 it was made from, a name for the log. */
    private static final String[][] BAR_COPIES = {
            {"luaui/widgets/gui_buildmenu.lua", "bardroid_buildmenu.lua", "bardroid_buildmenu.patches", ".bardroid-buildmenu",
                    "-- BARDROID_BUILDMENU_FROM ", "build menu"},   // tools/make-buildmenu.py
            {"luaui/widgets/gui_ordermenu.lua", "bardroid_ordermenu.lua", "bardroid_ordermenu.patches", ".bardroid-ordermenu",
                    "-- BARDROID_ORDERMENU_FROM ", "order menu"},   // tools/make-ordermenu.py
            {"luaui/widgets/gui_mission_info.lua", "bardroid_missioninfo.lua", "bardroid_missioninfo.patches",
                    ".bardroid-missioninfo", "-- BARDROID_MISSIONINFO_FROM ", "mission info"},   // tools/make-missioninfo.py
            {"luaui/widgets/gui_teamstats.lua", "bardroid_teamstats.lua", "bardroid_teamstats.patches",
                    ".bardroid-teamstats", "-- BARDROID_TEAMSTATS_FROM ", "team stats"},   // tools/make-teamstats.py
    };

    /**
     * The pool md5 of each of BAR's widgets the app has a copy of (BAR_COPIES: its Build and Order menus, its Mission Info)
     * in the released game this phone has, into .bardroid-buildmenu, -ordermenu, -missioninfo ("" when not found), and the copy made again
     * here when that is another file than it was made from. launch-bar.sh runs the copies. Written after the update at
     * every start.
     */
    private void writeBarCopiesMd5() {
        File rapid = new File(p.bar, "rapid");
        File[] hosts = rapid.listFiles();
        String pkg = null;
        if (hosts != null) for (File h : hosts) {
            File v = new File(h, "byar/versions.gz");
            if (!v.exists() || pkg != null) continue;
            try (BufferedReader r = new BufferedReader(new InputStreamReader(new GZIPInputStream(new FileInputStream(v)), StandardCharsets.UTF_8))) {
                for (String l; (l = r.readLine()) != null; ) {
                    String[] f = l.split(",", 4);
                    if (f.length == 4 && f[0].equals(Prefs.gameTag)) pkg = f[1];
                }
            } catch (IOException ignored) {}
        }
        Map<String, String> files = null;
        try {
            if (pkg != null) files = sdpFiles(new File(p.bar, "packages/" + pkg + ".sdp"));
        } catch (IOException e) {
            Log.e("install", "BAR's build and order menus not looked up: " + e);
        }
        for (String[] c : BAR_COPIES) {
            String md5 = files == null || files.get(c[0]) == null ? "" : files.get(c[0]);
            if (!md5.isEmpty()) remakeBarCopy(c, md5);
            try { writeFile(new File(p.bar, c[3]), md5 + "\n"); }
            catch (IOException e) { Log.e("install", c[3] + " not written: " + e); }
        }
        writeLoadTips(files);
        writeLowRamLine(files);
    }

    /**
     * The loading screen's tips, for GameActivity to show upright (Kailil, 2026-11-09: "the sentences that appear should
     * fit inside of the vertical aspect ratio"): BAR wraps its tip for a wide screen, and its loading screen comes only
     * from the game's archive (a copy in the write folder is listed but not run, dev phone), so upright launch-bar.sh
     * turns BAR's off and the app shows one wrapped to the screen. BAR's own: the keys its loading screen picks from
     * (luaintro/addons/main.lua tipKeys), the English texts (language/en/tips.json), into .bardroid-tips one a line
     * (its line breaks as \n); those with a key binding to fill in are left out.
     */
    private void writeLoadTips(Map<String, String> files) {
        if (files == null) return;
        try {
            String main = poolText(files.get("luaintro/addons/main.lua"));
            String json = poolText(files.get("language/en/tips.json"));
            if (main == null || json == null) return;
            int a = main.indexOf("local tipKeys = {");
            int b = a < 0 ? -1 : main.indexOf('}', a);
            if (b < 0) return;
            org.json.JSONObject tips = new org.json.JSONObject(json).getJSONObject("tips").getJSONObject("loadscreen");
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("\"([A-Za-z0-9_]+)\"").matcher(main.substring(a, b));
            StringBuilder out = new StringBuilder();
            while (m.find()) {
                String t = tips.optString(m.group(1), "");
                if (!t.isEmpty() && !t.contains("%{")) out.append(t.replace("\n", "\\n")).append('\n');
            }
            writeFile(new File(p.bar, ".bardroid-tips"), out.toString());
        } catch (IOException | org.json.JSONException e) {
            Log.e("install", "the loading screen's tips not read: " + e);
        }
    }

    /**
     * The loading screen's low memory line (Kailil, 2026-11-10: upright it ran off the screen): BAR prints it for a
     * machine under 11 GB as one line centred across the top, sized by the screen's height, from the game's archive
     * only; GameActivity shows it wrapped over BAR's band. The English text (language/en/interface.json
     * ui.loadScreen.lowRamWarning), its colours left out, into .bardroid-lowram.
     */
    private void writeLowRamLine(Map<String, String> files) {
        if (files == null) return;
        try {
            String json = poolText(files.get("language/en/interface.json"));
            if (json == null) return;
            String t = new org.json.JSONObject(json).getJSONObject("ui").getJSONObject("loadScreen")
                    .optString("lowRamWarning", "");
            // (BAR's two colours kept as marks: \u0002 its warning's white from there, \u0001 back to its grey)
            t = t.replace("%{warnColor}", "\u0002").replace("%{textColor}", "\u0001").replaceAll("%\\{[A-Za-z]+\\}", "")
                    .replaceAll("\\s+", " ").replace(" \u0001.", "\u0001.").replace(" .", ".").trim();
            writeFile(new File(p.bar, ".bardroid-lowram"), t);
        } catch (IOException | org.json.JSONException e) {
            Log.e("install", "the loading screen's low memory line not read: " + e);
        }
    }

    /** A file of BAR's pool by its md5, as text; null without one. */
    private String poolText(String md5) throws IOException {
        if (md5 == null || md5.length() < 3) return null;
        File f = new File(p.bar, "pool/" + md5.substring(0, 2) + "/" + md5.substring(2) + ".gz");
        try (InputStream in = new GZIPInputStream(new FileInputStream(f))) { return new String(readAll(in), StandardCharsets.UTF_8); }
    }

    /**
     * BAR's update changed one of the widgets the app has a copy of: the copy made again from BAR's new file
     * (BuildMenuPatches). If a patch finds no place the copy from the last app stays, and launch-bar.sh names that: it
     * runs (the build menu's: the pad's RB with it).
     */
    private void remakeBarCopy(String[] c, String md5) {
        File copy = new File(p.bar, "LuaUI/Widgets/" + c[1]);
        try (BufferedReader r = new BufferedReader(new FileReader(copy))) {
            for (String l; (l = r.readLine()) != null && l.startsWith("--"); )
                if (l.equals(c[4] + md5)) return;   // (the copy is of this file)
        } catch (IOException e) { Log.e("install", "the " + c[5] + " copy not read: " + e); }
        try {
            File bar = new File(p.bar, "pool/" + md5.substring(0, 2) + "/" + md5.substring(2) + ".gz");
            String barFile, patches;
            try (InputStream in = new GZIPInputStream(new FileInputStream(bar))) { barFile = new String(readAll(in), StandardCharsets.UTF_8); }
            try (InputStream in = new FileInputStream(new File(p.filesDir, "assets-bardroid/" + c[2]))) {
                patches = new String(readAll(in), StandardCharsets.UTF_8);
            }
            String release = resolveGameName();
            String made = BuildMenuPatches.apply(barFile, patches, release, md5);
            File tmp = new File(copy.getPath() + ".tmp");
            writeFile(tmp, made);
            Updater.replace(tmp, copy);
            Log.i("install", c[5] + ": the app's copy made again from " + release);
        } catch (IOException | IllegalArgumentException e) {
            Log.e("install", c[5] + ": the app's copy not made again, the last one stays: " + e.getMessage());
        }
    }

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
     * Kailil's controller (BAR Controller Support v0.8.5) ran as BAR's developer game in singleplayer until 2026-11-06
     * (Kailil: "We can pull out the 0.8.5 gamepad toggleer thing now. Since our gamepad controlls are so good now"):
     * skirmish plays BAR's own game with the app's controls, as online. The one an earlier build installed
     * (games/BAR-gamepad.sdd) goes, and its mark in the install state.
     */
    void removeGamepadGame() throws IOException {
        File dir = new File(p.bar, "games/BAR-gamepad.sdd");
        if (dir.exists() || state.getProperty("gamepad") != null) {
            deleteTree(dir);
            deleteTree(new File(p.bar, "games/BAR-gamepad.sdd.tmp"));
            state.remove("gamepad");
            save();
            Log.i("install", "the controller game (v0.8.5) removed: singleplayer plays BAR's released game");
        }
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
