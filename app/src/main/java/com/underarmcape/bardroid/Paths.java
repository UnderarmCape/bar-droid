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
        filesDir = ctx.getFilesDir();
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

    public File nativeLib(String name) { return new File(nativeLibDir, name); }
    // Executed in place: the native-lib dir is the only exec-allowed location, and it moves on every app update,
    // so links to it would dangle.
    public File proot() { return nativeLib("libproot.so"); }
    public File prootLoader() { return nativeLib("libproot-loader.so"); }
    public File busybox() { return nativeLib("libbusybox.so"); }
    public File libXlorie() { return nativeLib("libXlorie.so"); }

    public File engineDir(String version) { return new File(bar, "engine/recoil_" + version); }

    public void mkdirs() {
        for (File f : new File[]{rootfs, bar, downloads, logs, prootTmp, shm, fakeProc, importDir,
                new File(bar, "maps"), new File(bar, "games"), new File(bar, "engine"), new File(bar, "LuaUI/Widgets")}) {
            //noinspection ResultOfMethodCallIgnored
            f.mkdirs();
        }
    }
}
