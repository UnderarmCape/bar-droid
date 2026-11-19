package com.underarmcape.bardroid;

/**
 * The game service's status in players' words: "Skirmish running" for the log's "running (skirmish)", "Starting" for
 * "starting (...)" and "launching engine (...)", any other with a capital. The notification's title and the launcher's
 * status line say the same; the status words themselves stay (StartActivity and the logs read them). Free of Android
 * classes, for its check on the laptop and in CI (tools/status-text-test).
 */
final class StatusText {
    private StatusText() {}

    /**
     * The same, with the engine still on its loading screen (GameService.loading): a skirmish or benchmark is "loading"
     * until it is in, as the launcher said "Skirmish running" over the loading screen (dev phone, 2026-11-16). The lobby
     * keeps its word: its loading also counts a game started from it.
     */
    static String forPlayers(String s, boolean loading) {
        return forPlayers(s, loading, false, false);
    }

    /**
     * The status as the notification's title: in BAR's lobby, a game or a replay it started says so ("Game running",
     * "Replay loading"; it said "Lobby running" all through an online game, dev phone 2026-11-19), the lobby itself
     * "Lobby running" (gameFromLobby: a game loaded in the lobby's engine and not left yet; replay: it plays a replay).
     */
    static String forPlayers(String s, boolean loading, boolean gameFromLobby, boolean replay) {
        String t = forPlayers(s);
        if ("Lobby running".equals(t) && (gameFromLobby || replay)) {
            return (replay ? "Replay" : "Game") + (loading ? " loading" : " running");
        }
        // (the lobby itself starting: "Lobby loading" until its menu is up, as a skirmish's "Skirmish loading")
        if (loading && ("Skirmish running".equals(t) || "Benchmark running".equals(t) || "Lobby running".equals(t))) {
            return t.replace(" running", " loading");
        }
        return t;
    }

    /**
     * The notification's line under its title while BAR runs: what a tap returns to, and that Stop ends it. It said
     * "the game" over a replay and over the lobby alike (dev phone screenshot, a replay sideways, 2026-11-19).
     */
    static String returnLine(String s, boolean gameFromLobby, boolean replay) {
        String t = forPlayers(s);
        String what = "Benchmark running".equals(t) ? "the benchmark"
                : "GL check running".equals(t) ? "the GL check"
                : replay ? "the replay"
                : "Lobby running".equals(t) && !gameFromLobby ? "the lobby"
                : "the game";
        return "Tap to return to " + what + "; Stop ends it";
    }

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
    /**
     * The GPU as players know it from the OpenGL renderer string: Freedreno's "FD740" is the Adreno 740 ("Adreno 740
     * (Freedreno)"); anything else as it is (Zink's string already names the Adreno).
     */
    static String gpuName(String renderer) {
        if (renderer == null) return null;
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("^FD(\\d{3,4})$").matcher(renderer.trim());
        return m.find() ? "Adreno " + m.group(1) + " (Freedreno)" : renderer;
    }

    /**
     * The benchmark in a line from a run's infolog lines: BAR's scenario's results ("Sim 1801 frames, 54.08ms per frame,
     * ..."; the last of each, as tools/phone-bench.ps1 reads them: the main thread's ms per frame for Sim, Draw and
     * Update), or a replay benchmark's summary (bardroid_bench.lua's "[replaybench] done (300 s played): speed min x1.00,
     * ..."; it said "no results in the game's log" over one, dev phone 2026-11-19).
     */
    static String benchNote(Iterable<String> lines) {
        java.util.regex.Pattern line = java.util.regex.Pattern.compile("\\] (Sim|Draw|Update) \\d+ frames, ([\\d.]+)ms per frame");
        java.util.regex.Pattern replay = java.util.regex.Pattern.compile("\\[replaybench\\] done \\([^)]*\\): (.+)$");
        java.util.Map<String, String> ms = new java.util.HashMap<>();
        String replayDone = null;
        for (String l : lines) {
            if (l == null) continue;
            java.util.regex.Matcher m = line.matcher(l);
            if (m.find()) ms.put(m.group(1), m.group(2));
            java.util.regex.Matcher r = replay.matcher(l);
            if (r.find()) replayDone = r.group(1).trim();
        }
        if (ms.containsKey("Sim")) {
            // (a tenth of a millisecond: "Sim 24.92, Draw 2.83, Update 3.27" read as more than it says; the log has them
            // whole, tools/phone-bench.ps1 reads them there)
            java.util.List<String> parts = new java.util.ArrayList<>();
            for (String k : new String[]{"Sim", "Draw", "Update"}) {
                if (!ms.containsKey(k)) continue;
                String v = ms.get(k);
                try { v = String.format(java.util.Locale.US, "%.1f", Double.parseDouble(v)); } catch (NumberFormatException ignored) {}
                parts.add(k + " " + v);
            }
            return "Benchmark, ms per frame: " + String.join(", ", parts);
        }
        if (replayDone != null && !replayDone.startsWith("no samples")) {
            // (its figures shorter: the summary as logged ran over three lines of the launcher's status, dev phone
            // screenshot 2026-11-19; the whole of it stays in the log)
            java.util.regex.Matcher f = java.util.regex.Pattern.compile(
                    "speed min x([\\d.]+), median x([\\d.]+); below x0\\.95 (\\d+)% of the time; units up to (\\d+)").matcher(replayDone);
            if (f.find()) {
                return "Benchmark, replay: speed x" + f.group(2) + " (lowest x" + f.group(1) + "), behind "
                        + f.group(3) + "% of the time, up to " + f.group(4) + " units";
            }
            return "Benchmark, replay: " + replayDone;
        }
        return "Benchmark: no results in the game's log (it ended before them)";
    }

    static boolean isResultNote(String note) {
        if (note == null) return false;
        return (note.startsWith("GL check: ") && !note.contains("(see the log)"))
                || note.startsWith("Benchmark, ms per frame") || note.startsWith("Benchmark, replay: ");
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
        // (a list of content errors runs over several lines, "Errors:" first, GameService joins them: the launcher said
        // only "Errors:", a saved game of another BAR version, dev phone 2026-11-17; the errors themselves, joined)
        if (msg.indexOf('\n') >= 0) {
            java.util.List<String> parts = new java.util.ArrayList<>();
            for (String l : msg.split("\n")) {
                l = l.trim();
                if (!l.isEmpty() && !l.equals("Errors:")) parts.add(l);
            }
            msg = String.join("; ", parts);
        }
        if (msg.isEmpty()) return null;
        return msg.length() > 200 ? msg.substring(0, 200) + "..." : msg;
    }

    /** The launcher's note for it. */
    static String engineFatalNote(String msg) {
        return "BAR's own message: \"" + msg + "\"";
    }

    // (a join: "[CPreGame] using client IP <the server> and port <its port>"; the phone's own game: "using server IP
    // 127.0.0.1 and port 0"; dev phone, a client script to an address nothing answers, 2026-11-11)
    private static final String[] PREGAME_LINES = { "[CPreGame] using client IP ", "[CPreGame] using server IP " };

    /**
     * The server an engine line names as a game is joined ("[CPreGame] using client IP 1.2.3.4 and port 8452"):
     * "1.2.3.4:8452"; null: no such line, or the phone's own server (a local game: its pre-game is over in a moment).
     * GameService's pre-game screen (GameActivity's upright version of the engine's "Waiting for server response").
     */
    static String preGameServer(String line) {
        if (line == null) return null;
        int at = -1;
        String key = null;
        for (String k : PREGAME_LINES) {
            at = line.indexOf(k);
            if (at >= 0) { key = k; break; }
        }
        if (key == null) return null;
        String[] w = line.substring(at + key.length()).trim().split("\\s+");
        String ip = w.length > 0 ? w[0] : "";
        if (ip.isEmpty() || ip.startsWith("127.") || ip.equals("::1") || ip.equalsIgnoreCase("localhost")
                || ip.equals("0.0.0.0")) return null;
        String port = w.length >= 4 && w[1].equals("and") && w[2].equals("port") ? w[3] : "";
        return port.isEmpty() || port.equals("0") ? ip : ip + ":" + port;
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
