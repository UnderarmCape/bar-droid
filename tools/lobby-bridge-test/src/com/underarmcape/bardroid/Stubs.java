package com.underarmcape.bardroid;

import java.io.File;
import java.util.List;
import java.util.Map;

final class Log {
    static void i(String t, String m) { System.out.println("[" + t + "] " + m); }
    static void e(String t, String m) { System.out.println("[" + t + "] E " + m); }
}

final class BuildConfig { static final String VERSION_NAME = "test"; }

final class Prefs { static String engineVersion = "2026.09.01"; }

final class Paths {
    final File bar;
    Paths(File bar) { this.bar = bar; }
}

final class Proot {
    Proot(Paths p) {}
    int runScript(String tag, String script, Map<String, String> env, List<String> args) throws java.io.IOException, InterruptedException {
        System.out.println("[test] container step " + tag + ": " + script + " " + args);
        return 0;
    }
}
