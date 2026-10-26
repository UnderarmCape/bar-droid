package com.underarmcape.bardroid;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Stand-ins for the Android-bound classes Updater.java uses (tools/updater-test.ps1). */
final class Log {
    static boolean quiet;
    static void i(String t, String m) { if (!quiet) System.out.println("     [" + t + "] " + m); }
    static void e(String t, String m) { if (!quiet) System.out.println("     [" + t + "] E " + m); }
}

final class BuildConfig { static final String VERSION_NAME = "test"; }

final class Installer {
    static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        byte[] b = new byte[65536];
        for (int n; (n = in.read(b)) > 0; ) o.write(b, 0, n);
        return o.toByteArray();
    }
}

final class Prefs {
    static final boolean EMULATOR_BUILD = false;
    static String engineVersion = "", engineUrl = "", gameTag = "byar:test", lobbyTag = "byar-chobby:test";
    static boolean autoUpdate = true;
}

final class Paths {
    final File filesDir, bar, downloads;
    Paths(File root) {
        filesDir = root;
        bar = new File(root, "bar");
        downloads = new File(root, "downloads");
    }
    File engineDir(String version) { return new File(bar, "engine/recoil_" + version); }
}

final class Proot {
    Proot(Paths p) {}
    List<String> command(Map<String, String> env, List<String> cmd) { return new ArrayList<>(cmd); }
    Map<String, String> hostEnv() { return new HashMap<>(); }
    int runScript(String tag, String script, Map<String, String> env, List<String> args) { return 0; }
}

/** Runs nothing, except "rm -rf <path>" (Updater.removeTree), which it does in Java. */
final class Proc {
    interface LineSink { void line(String s); }
    Proc(String tag) {}
    static int run(String tag, List<String> cmd, Map<String, String> env, File cwd) throws IOException, InterruptedException {
        if (cmd.size() == 3 && cmd.get(0).endsWith("/rm") && cmd.get(1).equals("-rf")) delete(new File(cmd.get(2)));
        return 0;
    }
    Proc start(List<String> cmd, Map<String, String> env, File cwd, LineSink sink) throws IOException { return this; }
    int waitFor() throws InterruptedException { return 0; }
    private static void delete(File f) {
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) delete(k);
        //noinspection ResultOfMethodCallIgnored
        f.delete();
    }
}
