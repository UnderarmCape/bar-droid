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
        // StatusText.isResultNote: the launcher's note in its own colour (a result) or in amber (a warning)
        Object[][] notes = {
            { "GL check: FD740, OpenGL 4.3, Mesa 27.0.0-devel", true },
            { "GL check: FD740", true },
            { "GL check: no result (see the log)", false },
            { "GL check: no OpenGL from the GPU (see the log)", false },
            { "Benchmark, ms per frame: Sim 12.3, Draw 20.1, Update 1.2", true },
            { "Benchmark: no results in the game's log (it ended before them)", false },
            { "Map \"Starwatcher 1.0\" is not on the phone and did not download: check its name", false },
            { "The last game ended for lack of memory", false },
            { null, false },
        };
        for (Object[] n : notes) {
            boolean got = StatusText.isResultNote((String) n[0]);
            boolean ok = got == (Boolean) n[1];
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "note \"" + n[0] + "\" -> " + (got ? "result" : "warning"));
        }
        // StatusText.gpuName: the GL check's GPU as players know it
        String[][] gpus = { { "FD740", "Adreno 740 (Freedreno)" }, { "FD830", "Adreno 830 (Freedreno)" },
            { "zink Vulkan 1.3(Turnip Adreno (TM) 740 (MESA_TURNIP))", "zink Vulkan 1.3(Turnip Adreno (TM) 740 (MESA_TURNIP))" },
            { "llvmpipe (LLVM 19.1.7, 128 bits)", "llvmpipe (LLVM 19.1.7, 128 bits)" } };
        for (String[] g : gpus) {
            String got = StatusText.gpuName(g[0]);
            boolean ok = g[1].equals(got);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "gpu \"" + g[0] + "\" -> \"" + got + "\"");
        }
        // StatusText.engineFatal: the engine's fatal message from its infolog line (the Fold7's, 2026-11-05)
        Object[][] fatals = {
            { "[t=00:16:13.492054][f=-000001] Fatal: [ExitSpringProcess] errorMsg=\"invalid GameData received: Unpack failure (vector)\" msgCaption=\"Spring: caught content_error: \" mainThread=1",
              "invalid GameData received: Unpack failure (vector)" },
            { "[t=1] Fatal: [ExitSpringProcess] errorMsg=\"a \"quoted\" word\" msgCaption=\"x\"", "a \"quoted\" word" },
            { "[t=1] Error: [Watchdog::ClearTimer(id)] Invalid thread 4", null },
            { "[t=1] Fatal: [ExitSpringProcess] errorMsg=\"\" msgCaption=\"x\"", null },
            { null, null },
        };
        for (Object[] f : fatals) {
            String got = StatusText.engineFatal((String) f[0]);
            boolean ok = f[1] == null ? got == null : f[1].equals(got);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "engine fatal -> " + got);
        }
        boolean okNote = StatusText.engineFatalNote("x").equals("BAR's own message: \"x\"") && !StatusText.isResultNote(StatusText.engineFatalNote("x"));
        failed += okNote ? 0 : 1;
        System.out.println((okNote ? "PASS " : "FAIL ") + "engine fatal note, in amber");
        // StatusText.exitCodeNote: the engine's exit codes as an exit status's low byte (SpringExitCode.h)
        Object[][] codes = { { 21, "BAR stopped" }, { 23, "desync" }, { 233, "timed out" }, { 234, "could not be loaded" },
            { 236, "saved game" }, { 0, null }, { 1, null }, { 137, null }, { 139, null } };
        for (Object[] c : codes) {
            String got = StatusText.exitCodeNote((Integer) c[0]);
            boolean ok = c[1] == null ? got == null : got != null && got.contains((String) c[1]);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "exit " + c[0] + " -> " + got);
        }
        // DriverWatch: the game is closed only after the driver's refusal and then BAR's watchdog (dev phone's lines)
        String refused = "19:52:34 [engine] MESA: error: flush_submit_list:89: submit failed -1 (Resource deadlock avoided)";
        String hung = "19:53:14 [engine] [t=00:01:44.048302][f=0000741] Warning: [Watchdog] Hang detection triggered for Spring 2026.07.04.";
        DriverWatch w = new DriverWatch();
        boolean ok1 = !w.onLine("[t=00:00:30][f=-000001] Loading widget") && !w.onLine(hung) && !w.lost();
        failed += ok1 ? 0 : 1;
        System.out.println((ok1 ? "PASS " : "FAIL ") + "driver watch: a watchdog line alone (a long load) closes nothing");
        boolean ok2 = !w.onLine(refused) && w.refused() && !w.onLine(refused) && !w.lost();
        failed += ok2 ? 0 : 1;
        System.out.println((ok2 ? "PASS " : "FAIL ") + "driver watch: the driver's refusal alone closes nothing yet");
        boolean ok3 = w.onLine(hung) && w.lost() && !w.onLine(hung);
        failed += ok3 ? 0 : 1;
        System.out.println((ok3 ? "PASS " : "FAIL ") + "driver watch: refusal, then the watchdog: closed, once");
        DriverWatch w2 = new DriverWatch();
        boolean ok4 = !w2.onLine("MESA: error: flush_submit_list:89: submit failed -22 (Invalid argument)") && !w2.onLine(hung)
                && !w2.onLine(null) && !w2.lost();
        failed += ok4 ? 0 : 1;
        System.out.println((ok4 ? "PASS " : "FAIL ") + "driver watch: another submit error, then the watchdog: nothing");
        System.out.println(failed == 0 ? "ALL PASS" : failed + " FAILED");
        System.exit(failed == 0 ? 0 : 1);
    }
}
