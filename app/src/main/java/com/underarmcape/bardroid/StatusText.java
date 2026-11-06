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

    /**
     * Whether the launcher's note under its status (GameService.exitNote) is a result rather than a warning: a GL
     * check's or the benchmark's answer, unless it failed (those say "(see the log)" / "no results"). The launcher shows
     * warnings in amber; "GL check: FD740, OpenGL 4.3" in amber read as a problem (2026-11-05).
     */
    static boolean isResultNote(String note) {
        if (note == null) return false;
        return (note.startsWith("GL check: ") && !note.contains("(see the log)"))
                || note.startsWith("Benchmark, ms per frame");
    }

    /**
     * The engine's fatal error from an infolog line, or null: "Fatal: [ExitSpringProcess] errorMsg="invalid GameData
     * received: Unpack failure (vector)" msgCaption="Spring: caught content_error: " ...". On a PC the engine shows it in
     * a message box; on the phone nothing did, and the launcher only said "game ended with an error (21)" (the engine's
     * EXIT_CODE_CRASHED, -1003, as an exit status; the Fold7, 2026-11-05, a join after the network dropped).
     */
    static String engineFatal(String line) {
        if (line == null) return null;
        int at = line.indexOf("[ExitSpringProcess] errorMsg=\"");
        if (at < 0) return null;
        String rest = line.substring(at + "[ExitSpringProcess] errorMsg=\"".length());
        int end = rest.indexOf("\" msgCaption=");
        if (end < 0) end = rest.lastIndexOf('"');
        String msg = (end >= 0 ? rest.substring(0, end) : rest).trim();
        if (msg.isEmpty()) return null;
        return msg.length() > 200 ? msg.substring(0, 200) + "..." : msg;
    }

    /** The launcher's note for it. */
    static String engineFatalNote(String msg) {
        return "BAR's own message: \"" + msg + "\"";
    }

    /**
     * The engine's exit codes (rts/System/SpringExitCode.h) as they arrive, an exit status's low byte: what the launcher
     * says when the engine left no message of its own; null for any other.
     */
    static String exitCodeNote(int rc) {
        switch (rc) {
            case 21: return "BAR stopped on an error of its own (its log has the details)";   // EXIT_CODE_CRASHED -1003
            case 22: return "BAR could not start (its log has the details)";                  // EXIT_CODE_NOINIT -1002
            case 23: return "The game went out of sync with the other players (a desync)";    // EXIT_CODE_DESYNC -1001
            case 233: return "The connection to the game timed out";                          // EXIT_CODE_TIMEOUT 1001
            case 234: return "The game could not be loaded";                                  // EXIT_CODE_NOLOAD 1002
            case 235: return "BAR was closed after it stopped responding";                    // EXIT_CODE_KILLED 1003
            case 236: return "The saved game could not be loaded";                            // EXIT_CODE_BADSAVE 1004
            default: return null;
        }
    }
}
