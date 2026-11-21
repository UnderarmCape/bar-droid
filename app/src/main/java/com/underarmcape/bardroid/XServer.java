package com.underarmcape.bardroid;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Starts Termux:X11's X server (com.termux.x11.CmdEntryPoint, compiled into this APK via the :lorie module)
 * as a child app_process, exactly the way the `termux-x11` command does from Termux, except that:
 *  - CLASSPATH is our own APK, so the server broadcasts ACTION_START to our package and GameActivity shows it;
 *  - TMPDIR is <rootfs>/tmp, so the socket is the container's /tmp/.X11-unix/X0 and fonts/xkb come from Debian;
 *  - TERMUX_X11_LIBXLORIE_PATH points at the extracted libXlorie.so (our one-line patch to CmdEntryPoint).
 */
public final class XServer {
    private final Paths p;
    private volatile Proc proc;

    public XServer(Paths p) { this.p = p; }

    public File socket() { return new File(p.rootfsTmp, ".X11-unix/X0"); }

    public boolean isRunning() { return proc != null && proc.isAlive(); }

    public void start() throws IOException {
        if (isRunning()) return;
        //noinspection ResultOfMethodCallIgnored
        p.rootfsTmp.mkdirs();
        File sockDir = new File(p.rootfsTmp, ".X11-unix");
        //noinspection ResultOfMethodCallIgnored
        sockDir.mkdirs();
        //noinspection ResultOfMethodCallIgnored
        new File(sockDir, "X0").delete();
        File xkb = inRootfs("/usr/share/X11/xkb");
        if (!xkb.isDirectory()) throw new IOException("xkb-data missing in rootfs (" + xkb + "); run the installer first");
        File lib = p.libXlorie();
        if (!lib.exists()) throw new IOException("libXlorie.so missing: " + lib);

        // app_process needs the runtime's own environment (BOOTCLASSPATH, ANDROID_ART_ROOT, ANDROID_I18N_ROOT, ...).
        Map<String, String> env = new HashMap<>(System.getenv());
        env.remove("LD_PRELOAD");
        env.remove("LD_LIBRARY_PATH");
        env.put("CLASSPATH", p.apkPath);
        env.put("TMPDIR", p.rootfsTmp.getAbsolutePath());
        env.put("XKB_CONFIG_ROOT", xkb.getAbsolutePath());
        env.put("TERMUX_X11_LIBXLORIE_PATH", lib.getAbsolutePath());
        // the display's vsync for the engine's frame cap (/tmp/bardroid-vsync in the container: tools/pace/pace.c)
        env.put("BARDROID_VSYNC_FILE", new File(p.rootfsTmp, "bardroid-vsync").getAbsolutePath());
        if (Prefs.verboseX) env.put("TERMUX_X11_DEBUG", "1");

        List<String> cmd = new ArrayList<>();
        cmd.add("/system/bin/app_process");
        cmd.add("-Xnoimage-dex2oat");
        cmd.add("/");
        cmd.add("--nice-name=bardroid-x11");
        cmd.add("com.termux.x11.CmdEntryPoint");
        cmd.add(":0");
        cmd.add("-ac");                 // standard Xorg flag: no xauth inside the container
        // (Xtrans also listened on an abstract socket, "local": @<rootfs>/tmp/.X11-unix/X0, which has no file and so
        // no file permissions, and with -ac it took any client unasked. The container's clients connect to the path
        // socket in the app's own folder, which no other app can reach: tools/x11-probe.ps1, release overhaul item 5)
        cmd.add("-nolisten");
        cmd.add("local");
        proc =new Proc("x11").start(cmd, env, p.filesDir, null);
    }

    /**
     * Host path of a guest path, following symlinks the way the guest would: the X server runs outside proot,
     * and Debian's /usr/share/X11/xkb is a symlink (an absolute one would otherwise point into Android's /).
     */
    File inRootfs(String guestPath) {
        String path = guestPath;
        for (int hop = 0; hop < 16; hop++) {
            File f = new File(p.rootfs, path);
            String target;
            try { target = android.system.Os.readlink(f.getAbsolutePath()); }
            catch (Exception notALink) { return f; }
            path = target.startsWith("/") ? target : new File(new File(path).getParent(), target).getPath();
        }
        return new File(p.rootfs, path);
    }

    /** Waits for the unix socket to appear (the Debian client side needs it). */
    public boolean waitForSocket(long timeoutMs) {
        long end = System.currentTimeMillis() + timeoutMs;
        while (System.currentTimeMillis() < end) {
            if (socket().exists()) return true;
            if (!isRunning()) return false;
            try { Thread.sleep(200); } catch (InterruptedException e) { return false; }
        }
        return socket().exists();
    }

    // (read once: the stop thread, the worker's finally and onDestroy stop it within milliseconds of each other, and a
    // null written between a check and its use threw on a thread with no catch; release overhaul audit, 2026-11-21)
    public void stop() {
        Proc p0 = proc;
        proc = null;
        if (p0 != null) p0.kill();
    }
}
