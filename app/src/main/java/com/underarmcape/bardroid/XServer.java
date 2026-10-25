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
    private Proc proc;

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
        File xkb = new File(p.rootfs, "usr/share/X11/xkb");
        if (!xkb.isDirectory()) throw new IOException("xkb-data missing in rootfs (" + xkb + "); run the installer first");
        if (!p.libXlorie().exists()) throw new IOException("libXlorie.so missing: " + p.libXlorie());

        Map<String, String> env = new HashMap<>();
        env.put("CLASSPATH", p.apkPath);
        env.put("TMPDIR", p.rootfsTmp.getAbsolutePath());
        env.put("XKB_CONFIG_ROOT", xkb.getAbsolutePath());
        env.put("TERMUX_X11_LIBXLORIE_PATH", p.libXlorie().getAbsolutePath());
        env.put("PATH", "/system/bin");
        env.put("ANDROID_DATA", "/data");
        env.put("ANDROID_ROOT", "/system");
        if (Prefs.verboseX) env.put("TERMUX_X11_DEBUG", "1");

        List<String> cmd = new ArrayList<>();
        cmd.add("/system/bin/app_process");
        cmd.add("-Xnoimage-dex2oat");
        cmd.add("/");
        cmd.add("--nice-name=bardroid-x11");
        cmd.add("com.termux.x11.CmdEntryPoint");
        cmd.add(":0");
        cmd.add("-ac");                 // standard Xorg flag: no xauth inside the container
        proc =new Proc("x11").start(cmd, env, p.filesDir, null);
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

    public void stop() {
        if (proc != null) proc.kill();
        proc = null;
    }
}
