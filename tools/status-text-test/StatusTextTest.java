package com.underarmcape.bardroid;

/**
 * StatusText.forPlayers on the game service's own statuses: what the notification and the launcher's status line say.
 * Prints each case and "ALL PASS", or the failures and "FAILED" (exit 1).
 */
public class StatusTextTest {
    public static void main(String[] args) {
        String[][] cases = {
            { "starting (skirmish)", "Starting" },
            { "launching engine (skirmish)", "Starting" },
            { "running (skirmish)", "Skirmish running" },
            { "running (lobby)", "Lobby running" },
            { "running (bench)", "Benchmark running" },
            { "running (glcheck)", "GL check running" },
            { "running (shell)", "Running (shell)" },
            { "update: checking for BAR updates", "Update: checking for BAR updates" },
            { "starting X server", "Starting X server" },
            { "installing", "Installing" },
            { "install rootfs: downloading Debian 12 MB / 300 MB (12%)", "Installing: downloading Debian 12 MB / 300 MB (12%)" },
            { "install mesa: running container setup: mesa", "Installing: running container setup: mesa" },
            { "install done: Installed (100%)", "Installed" },
            { "installed", "Installed" },
            { "install failed: no network", "Install failed: no network" },   // (a failure keeps its word)
            { "install stopped", "Install stopped" },
            { "game ended with an error (3)", "Game ended with an error (3)" },
            { "", "" },
        };
        int failed = 0;
        for (String[] c : cases) {
            String got = StatusText.forPlayers(c[0]);
            boolean ok = got.equals(c[1]);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "\"" + c[0] + "\" -> \"" + got + "\"" + (ok ? "" : " (want \"" + c[1] + "\")"));
        }
        if (StatusText.forPlayers(null).length() != 0) { failed++; System.out.println("FAIL null -> not empty"); }
        System.out.println(failed == 0 ? "ALL PASS" : failed + " FAILED");
        System.exit(failed == 0 ? 0 : 1);
    }
}
