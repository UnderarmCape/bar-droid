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
        try (FileOutputStream out = new FileOutputStream(p.stateFile)) { state.store(out, "bardroid install state"); }
    }
    public boolean isDone(String step) { return "done".equals(state.getProperty(step)); }
    public boolean isInstalled() { for (String s : STEPS) if (!isDone(s) && !s.equals("import")) return false; return true; }
    public void reset(String step) throws IOException { state.remove(step); try (FileOutputStream out = new FileOutputStream(p.stateFile)) { state.store(out, ""); } }
    public void cancel() { cancelled = true; dl.cancel(); }

    /** Runs every step that is not done yet. Throws on failure with a readable message. */
    public void installAll(Status st) throws Exception {
        p.mkdirs();
        refreshHostFiles();
        step("rootfs", st, () -> installRootfs(st));
        step("apt", st, () -> runSetup("apt", st, "apt"));
        step("mesa", st, () -> installMesa(st));
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

    private void installRootfs(Status st) throws Exception {
        if (new File(p.rootfs, "usr/bin/apt-get").exists()) { Log.i("install", "rootfs already extracted"); installScripts(); return; }
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
        int rc = proot.extractRootfs(tgz);
        if (rc != 0 && !new File(p.rootfs, "usr/bin/apt-get").exists()) throw new IOException("rootfs extraction failed (rc=" + rc + ")");
        if (rc != 0) Log.e("install", "tar returned " + rc + " but the rootfs looks usable; continuing");
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
        File tgz = dl.download(Prefs.mesaUrl, new File(p.downloads, "mesa.tar.gz"), null,
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
        try (InputStream in = new FileInputStream(new File(assets, "libasarm64.so")); OutputStream o = new FileOutputStream(new File(p.bar, "libasarm64.so"))) { copy(in, o); }
        // springsettings.cfg from the template plus the user's knobs
        StringBuilder cfg = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new FileReader(new File(assets, "springsettings.cfg")))) {
            String l;
            while ((l = r.readLine()) != null) {
                if (l.startsWith("WorkerThreadCount")) l = "WorkerThreadCount = " + Prefs.workerThreads;
                else if (l.startsWith("ui_scale")) l = "ui_scale = " + Prefs.uiScale;
                else if (l.startsWith("Shadows ")) l = "Shadows = " + (Prefs.shadows ? 2 : -1);
                else if (l.startsWith("CompressTextures")) l = "CompressTextures = " + (Prefs.compressTextures ? 1 : 0);
                cfg.append(l).append('\n');
            }
        }
        cfg.append("RapidTagResolutionOrder = repos-cdn.beyondallreason.dev;repos.beyondallreason.dev\n");
        writeFile(new File(p.bar, "springsettings.cfg"), cfg.toString());
        writeStartScript();
    }

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
