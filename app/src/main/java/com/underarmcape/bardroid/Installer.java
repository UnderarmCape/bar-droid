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
import java.util.Map;
import java.util.Properties;
import java.util.zip.GZIPInputStream;

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
        runSetup("mesa", st, "mesa", "/root/downloads/" + tgz.getName());
        //noinspection ResultOfMethodCallIgnored
        tgz.delete();
    }

    private void installEngine(Status st) throws Exception {
        File z = dl.download(Prefs.engineUrl, new File(p.downloads, "engine.7z"), null,
                (done, total) -> st.status("engine", "downloading engine " + Downloader.human(done) + " / " + Downloader.human(total), 55));
        runSetup("engine", st, "engine", "/root/downloads/" + z.getName(), Prefs.engineVersion);
        if (!new File(p.engineDir(Prefs.engineVersion), "spring").exists()) throw new IOException("engine binary missing after extraction");
        //noinspection ResultOfMethodCallIgnored
        z.delete();
    }

    private boolean hasImport() {
        for (String d : new String[]{"pool", "packages", "rapid", "maps", "games"}) if (new File(p.importDir, d).isDirectory()) return true;
        return false;
    }

    /** springsettings.cfg, the AI stub, start script. Re-run whenever settings change. */
    public void writeGameFiles() throws IOException {
        File assets = new File(p.filesDir, "assets-bardroid");
        // The AngelScript ARM64 call stub fixes the official arm64 AI build; the amd64 engine needs nothing.
        File stub = new File(p.bar, "libasarm64.so");
        if (Prefs.EMULATOR_BUILD) { //noinspection ResultOfMethodCallIgnored
            stub.delete();
        } else try (InputStream in = new FileInputStream(new File(assets, "libasarm64.so")); OutputStream o = new FileOutputStream(stub)) { copy(in, o); }
        // Our own widget (not BAR content): the camera side of the two-finger pan (RtsTouch).
        File widgets = new File(p.bar, "LuaUI/Widgets");
        //noinspection ResultOfMethodCallIgnored
        widgets.mkdirs();
        try (InputStream in = new FileInputStream(new File(assets, "bardroid_touch.lua"));
             OutputStream o = new FileOutputStream(new File(widgets, "bardroid_touch.lua"))) { copy(in, o); }
        // Widgets of the removed touch-only mode (Kailil, 2026-10-25): gone from earlier installs too.
        for (String name : new String[]{"bardroid_touch_hud.lua", "bardroid_touch_dock.lua", "bardroid_touch_build.lua"})
            //noinspection ResultOfMethodCallIgnored
            new File(widgets, name).delete();
        // springsettings.cfg from the template plus the user's knobs (each key replaced in place, never duplicated)
        Map<String, String> set = new java.util.LinkedHashMap<>();
        set.put("WorkerThreadCount", String.valueOf(Prefs.workerThreads));
        set.put("ui_scale", String.valueOf(Prefs.uiScale));
        set.put("Shadows", Prefs.shadows ? "2" : "-1");
        set.put("RapidTagResolutionOrder", "repos-cdn.beyondallreason.dev;repos.beyondallreason.dev");
        // Frame cap. BAR sets VSync = VSyncGame (1 on) x VSyncFraction; at 60 Hz a fraction of 2 is 30 fps. The touch
        // widget adjusts the fraction to the display's real refresh rate (the Fold7's screens run 60 and 120 Hz).
        // The emulator overrides VSync.
        set.put("VSyncGame", "1");
        set.put("VSyncFraction", Prefs.fps60 ? "1" : "2");
        set.put("VSync", Prefs.fps60 ? "1" : "2");
        if (Prefs.EMULATOR_BUILD) set.putAll(EMULATOR_GRAPHICS);
        StringBuilder cfg = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new FileReader(new File(assets, "springsettings.cfg")))) {
            String l;
            while ((l = r.readLine()) != null) {
                int eq = l.indexOf('=');
                String key = eq > 0 && !l.startsWith("#") ? l.substring(0, eq).trim() : null;
                if (key != null && set.containsKey(key)) l = key + " = " + set.remove(key);
                cfg.append(l).append('\n');
            }
        }
        if (Prefs.EMULATOR_BUILD) cfg.append("# emulator build\n");
        for (Map.Entry<String, String> kv : set.entrySet()) cfg.append(kv.getKey()).append(" = ").append(kv.getValue()).append('\n');
        writeFile(new File(p.bar, "springsettings.cfg"), cfg.toString());
        writeStartScript();
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

    /** Human (team 0) vs one AI (team 1). GameType uses the rapid tag; the engine resolves it from the local rapid index. */
    public void writeStartScript() throws IOException {
        File assets = new File(p.filesDir, "assets-bardroid");
        String tpl;
        try (InputStream in = new FileInputStream(new File(assets, "skirmish.template.txt"))) { tpl = new String(readAll(in), StandardCharsets.UTF_8); }
        String game = resolveGameName();
        tpl = tpl.replace("@GAME@", game).replace("@MAP@", Prefs.mapName);
        // AI difficulty is a BARb option; keep ShortName=BARb (the only native AI shipped in the arm64 engine archive).
        writeFile(new File(p.bar, "skirmish.txt"), tpl);
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
