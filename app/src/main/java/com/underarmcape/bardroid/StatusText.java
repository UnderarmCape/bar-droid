package com.underarmcape.bardroid;

/**
 * The game service's status in players' words: "Skirmish running" for the log's "running (skirmish)", "Starting" for
 * "starting (...)" and "launching engine (...)", any other with a capital. The notification's title and the launcher's
 * status line say the same; the status words themselves stay (StartActivity and the logs read them). Free of Android
 * classes, for its check on the laptop and in CI (tools/status-text-test).
 */
final class StatusText {
    private StatusText() {}

    static String forPlayers(String s) {
        if (s == null || s.isEmpty()) return "";
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("^running \\((\\w+)\\)$").matcher(s);
        if (m.matches()) {
            switch (m.group(1)) {
                case "skirmish": return "Skirmish running";
                case "lobby": return "Lobby running";
                case "bench": return "Benchmark running";
                case "glcheck": return "GL check running";
                default: return "Running (" + m.group(1) + ")";
            }
        }
        if (s.startsWith("launching engine") || s.matches("^starting \\(\\w+\\)$")) return "Starting";
        // the installer's steps without their inner names ("Install rootfs: downloading Debian ...", "Install done:
        // Installed (100%)")
        if (s.startsWith("install done")) return "Installed";
        m = java.util.regex.Pattern.compile("^install (\\w+): (.*)$").matcher(s);
        if (m.matches() && !m.group(1).equals("failed")) return "Installing: " + m.group(2);
        return Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }
}
