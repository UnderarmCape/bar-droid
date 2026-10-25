package com.underarmcape.bardroid;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * GPU path for devices without the Adreno Mesa stack (the Android emulator first): Termux's
 * virgl_test_server_android, bundled as libvirgl_server.so, executes the container's OpenGL with Android's own
 * EGL/GLES (on the emulator that is the host GPU via gfxstream). Inside the container Mesa's virpipe driver talks
 * to it over the socket <rootfs>/tmp/.virgl_test, i.e. the guest's /tmp/.virgl_test.
 */
public final class VirglServer {
    public static final String GUEST_SOCKET = "/tmp/.virgl_test";
    private final Paths p;
    private Proc proc;

    public VirglServer(Paths p) { this.p = p; }

    public File socket() { return new File(p.rootfsTmp, ".virgl_test"); }

    public void start() throws IOException {
        if (proc != null && proc.isAlive()) return;
        File exe = p.nativeLib("libvirgl_server.so");
        if (!exe.exists()) throw new IOException("virgl server missing: " + exe);
        //noinspection ResultOfMethodCallIgnored
        socket().delete();
        // EGL needs the app runtime's environment, like app_process in XServer.
        Map<String, String> env = new HashMap<>(System.getenv());
        env.remove("LD_PRELOAD");
        env.put("LD_LIBRARY_PATH", p.nativeLibDir);
        env.put("BARDROID_ANGLE_DIR", p.nativeLibDir);   // ANGLE's libEGL_angle.so etc. (tools/build-virgl.py)
        env.put("TMPDIR", p.rootfsTmp.getAbsolutePath());
        List<String> cmd = new ArrayList<>();
        cmd.add(exe.getAbsolutePath());
        // Developer switch (files/bar/dev-virgl-native): the system's own EGL/GLES instead of ANGLE, with a pbuffer
        // per context where surfaceless contexts are missing (tools/build-virgl.py).
        if (new File(p.bar, "dev-virgl-native").exists()) Log.i("virgl", "using the system GLES driver (dev switch)");
        else cmd.add("--angle-vulkan");   // ANGLE = GLES on Vulkan, surfaceless EGL
        cmd.add("--socket-path");
        cmd.add(socket().getAbsolutePath());
        proc = new Proc("virgl").start(cmd, env, p.filesDir, null);
    }

    public boolean waitForSocket(long timeoutMs) {
        long end = System.currentTimeMillis() + timeoutMs;
        while (System.currentTimeMillis() < end) {
            if (socket().exists()) return true;
            if (proc == null || !proc.isAlive()) return false;
            try { Thread.sleep(100); } catch (InterruptedException e) { return false; }
        }
        return socket().exists();
    }

    public void stop() {
        if (proc != null) proc.kill();
        proc = null;
    }
}
