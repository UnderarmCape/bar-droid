package com.underarmcape.bardroid;

import android.content.Context;

import java.io.File;

/** Every on-disk location the launcher uses, in one place. */
public final class Paths {
    public final File filesDir;      // /data/data/<pkg>/files
    public final File rootfs;        // Debian arm64 container root
    public final File rootfsTmp;     // rootfs/tmp — also the X server's TMPDIR, so the socket lands in the container's /tmp
    public final File bar;           // Recoil write-dir: engine/, pool/, packages/, maps/, games/, infolog.txt ... bound at /root/bar
    public final File downloads;     // partial downloads
    public final File logs;          // launcher + engine logs copied here
    public final File prootTmp;      // PROOT_TMP_DIR
    public final File shm;           // bound at /dev/shm
    public final File fakeProc;      // fake /proc files proot binds over the real ones Android hides
    public final File importDir;     // Android/data/<pkg>/files/import — adb push content here
    public final String nativeLibDir;
    public final String apkPath;
    public final File stateFile;

    public Paths(Context ctx) {
        // Canonical on purpose: inside an app's mount namespace (Android 11+ data isolation) /data/user/0 is a
        // symlink to /data/data. proot canonicalizes its rootfs, so every path we hand it (and the hard-link
        // symlinks --link2symlink writes from PROOT_L2S_DIR) must use the same spelling, or they cannot be resolved.
        filesDir = canonical(ctx.getFilesDir());
        rootfs = new File(filesDir, "rootfs");
        rootfsTmp = new File(rootfs, "tmp");
        bar = new File(filesDir, "bar");
        downloads = new File(filesDir, "downloads");
        logs = new File(filesDir, "logs");
        prootTmp = new File(filesDir, "proot-tmp");
        shm = new File(filesDir, "shm");
        fakeProc = new File(filesDir, "fakeproc");
        File ext = ctx.getExternalFilesDir(null);
        importDir = ext != null ? new File(ext, "import") : new File(filesDir, "import");
        nativeLibDir = ctx.getApplicationInfo().nativeLibraryDir;
        apkPath = ctx.getApplicationInfo().sourceDir;
        stateFile = new File(filesDir, "install-state.properties");
    }

    private static File canonical(File f) {
        try { return f.getCanonicalFile(); } catch (java.io.IOException e) { return f.getAbsoluteFile(); }
    }

    public File nativeLib(String name) { return new File(nativeLibDir, name); }
    // Executed in place: the native-lib dir is the only exec-allowed location, and it moves on every app update,
    // so links to it would dangle.
    public File proot() { return nativeLib("libproot.so"); }
    public File prootLoader() { return nativeLib("libproot-loader.so"); }
    public File busybox() { return nativeLib("libbusybox.so"); }
    /** proot --link2symlink stores hard-link targets here (PROOT_L2S_DIR); it must exist. */
    public File l2s() { return new File(rootfs, ".l2s"); }
    public File libXlorie() { return nativeLib("libXlorie.so"); }

    // The flags libbardroid_pace.so looks for (the container's /tmp/bardroid-hidden, -floating, -catchup). Here, not on
    // GameActivity: its first use on a worker thread creates Termux:X11's static Handler there, with no Looper, and the
    // app dies (a skirmish start on the dev phone, 2026-10-31). tools/laptop-tests.ps1 looks for that.
    public File hiddenFlag() { return new File(rootfsTmp, "bardroid-hidden"); }
    public File floatingFlag() { return new File(rootfsTmp, "bardroid-floating"); }
    public File catchupFlag() { return new File(rootfsTmp, "bardroid-catchup"); }

    public File engineDir(String version) { return new File(bar, "engine/recoil_" + version); }

    public void mkdirs() {
        for (File f : new File[]{rootfs, bar, downloads, logs, prootTmp, shm, fakeProc, importDir,
                new File(bar, "maps"), new File(bar, "games"), new File(bar, "engine"), new File(bar, "LuaUI/Widgets")}) {
            //noinspection ResultOfMethodCallIgnored
            f.mkdirs();
        }
    }
}
