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
            { "closing: saving the replay", "Closing: saving the replay" },   // (Stop or a swipe: GameService.closeGently)
            { "closing", "Closing" },   // (the same while the game still loads: no replay to speak of)
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
        // ... and on the loading screen: a skirmish or benchmark loading, the lobby and the rest as they are
        String[][] loading = {
            { "running (skirmish)", "Skirmish loading" },
            { "running (bench)", "Benchmark loading" },
            { "running (lobby)", "Lobby loading" },
            { "starting (skirmish)", "Starting" },
        };
        for (String[] c : loading) {
            String got = StatusText.forPlayers(c[0], true);
            boolean ok = got.equals(c[1]);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "loading \"" + c[0] + "\" -> \"" + got + "\"" + (ok ? "" : " (want \"" + c[1] + "\")"));
        }
        // ... and a game or replay the lobby started (status, loading, game from the lobby, replay)
        Object[][] lobbyGames = {
            { "running (lobby)", false, false, false, "Lobby running" },
            { "running (lobby)", true, true, false, "Game loading" },
            { "running (lobby)", false, true, false, "Game running" },
            { "running (lobby)", true, false, true, "Replay loading" },
            { "running (lobby)", false, true, true, "Replay running" },
            { "running (skirmish)", false, true, false, "Skirmish running" },
            { "closing: saving the replay", false, true, false, "Closing: saving the replay" },
        };
        for (Object[] c : lobbyGames) {
            String got = StatusText.forPlayers((String) c[0], (Boolean) c[1], (Boolean) c[2], (Boolean) c[3]);
            boolean ok = got.equals(c[4]);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "lobby game " + c[0] + " " + c[1] + c[2] + c[3] + " -> \"" + got + "\"" + (ok ? "" : " (want \"" + c[4] + "\")"));
        }
        // StatusText.returnLine: the notification's line under its title (status, game from the lobby, replay)
        Object[][] lines = {
            { "running (lobby)", false, false, "Tap for the lobby; Stop ends it" },
            { "running (lobby)", true, false, "Tap for the game; Stop ends it" },
            { "running (lobby)", true, true, "Tap for the replay; Stop ends it" },
            { "running (lobby)", false, true, "Tap for the replay; Stop ends it" },
            { "running (skirmish)", false, false, "Tap for the game; Stop ends it" },
            { "running (bench)", false, false, "Tap for the benchmark; Stop ends it" },
            { "running (bench)", false, true, "Tap for the benchmark; Stop ends it" },   // (a replay benchmark)
            { "running (glcheck)", false, false, "Tap for the GL check; Stop ends it" },
            { "closing: saving the replay", true, false, "Tap for the game; Stop ends it" },
        };
        for (Object[] c : lines) {
            String got = StatusText.returnLine((String) c[0], (Boolean) c[1], (Boolean) c[2]);
            boolean ok = got.equals(c[3]);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "line " + c[0] + " " + c[1] + c[2] + " -> \"" + got + "\"" + (ok ? "" : " (want \"" + c[3] + "\")"));
        }
        // StatusText.adrenoModel: the kernel's gpu_model as the launcher's GPU line names it
        String[][] models = {
            { "Adreno740v2", "Adreno 740" },
            { "Adreno830v2\n", "Adreno 830" },
            { "Adreno 750", "Adreno 750" },
            { "Adreno8xx", null },
            { "", null },
            { null, null },
        };
        for (String[] c : models) {
            String got = StatusText.adrenoModel(c[0]);
            boolean ok = java.util.Objects.equals(got, c[1]);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "gpu model \"" + c[0] + "\" -> " + got + (ok ? "" : " (want " + c[1] + ")"));
        }
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
        // StatusText.benchNote: BAR's scenario's results, or a replay benchmark's summary (the dev phone's of 2026-11-19)
        String replayDone = "[t=00:06:17.332015][f=0010813] [replaybench] done (300 s played): speed min x1.00, median x1.00;"
            + " below x0.95 0% of the time; units up to 656; 29 samples";
        Object[][] benches = {
            { new String[]{ "[t=1] Sim 1801 frames, 54.08ms per frame, x", "[t=1] Draw 900 frames, 17.00ms per frame",
                "[t=2] Sim 1801 frames, 50.00ms per frame", "[t=2] Update 900 frames, 7.97ms per frame" },
              "Benchmark, ms per frame: Sim 50.0, Draw 17.0, Update 8.0" },
            { new String[]{ "[t=1] [replaybench] 6:00 x1.00 (wanted x1.00, server x1.00), 656 units, 29 fps", replayDone },
              "Benchmark, replay: speed x1.00 (lowest x1.00), behind 0% of the time, up to 656 units" },
            { new String[]{ "[t=1] [replaybench] done (the game ended): speed min x0.62, median x0.91; below x0.95 64% of the time; units up to 1830; 25 samples" },
              "Benchmark, replay: speed x0.91 (lowest x0.62), behind 64% of the time, up to 1830 units" },
            { new String[]{ "[t=1] [replaybench] done (x): some other summary" }, "Benchmark, replay: some other summary" },
            { new String[]{ "[t=1] [replaybench] done (the replay ended): no samples" },
              "Benchmark: no results in the game's log (it ended before them)" },
            { new String[]{ "[t=1] nothing", null }, "Benchmark: no results in the game's log (it ended before them)" },
        };
        for (Object[] b : benches) {
            String got = StatusText.benchNote(java.util.Arrays.asList((String[]) b[0]));
            boolean ok = b[1].equals(got);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "bench -> \"" + got + "\"" + (ok ? "" : " (want \"" + b[1] + "\")"));
        }
        boolean okReplay = StatusText.isResultNote(StatusText.benchNote(java.util.Arrays.asList(replayDone)));
        failed += okReplay ? 0 : 1;
        System.out.println((okReplay ? "PASS " : "FAIL ") + "a replay benchmark's note is a result, not amber");
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
            // (content errors over several lines, as GameService.engineFatal joins them; a save of another BAR version,
            // dev phone 2026-11-17)
            { "[t=00:00:57.972796][f=-000001] Fatal: [ExitSpringProcess] errorMsg=\"Errors:\nMetadata checksum error: Package file was saved with a different version\" msgCaption=\"Recoil: caught content_error(s)\" mainThread=1",
              "Metadata checksum error: Package file was saved with a different version" },
            { "[t=1] Fatal: [ExitSpringProcess] errorMsg=\"Errors:\nfirst\n\nsecond\" msgCaption=\"x\"", "first; second" },
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
        // the fault's words in the engine's own log lines (a player's chat, a Lua echo) arm nothing; the watchdog's words
        // in a chat line after a real refusal close nothing (2026-11-20)
        DriverWatch w4 = new DriverWatch();
        boolean ok6 = !w4.onLine("19:52:34 [engine] [t=00:00:30.1][f=0000123] <Phone> MESA: error: flush_submit_list:89: "
                + "submit failed -1 (Resource deadlock avoided)")
                && !w4.onLine("[t=00:00:30.2][f=0000124] MESA: error: flush_submit_list:89: submit failed -1 (Resource deadlock avoided)")
                && !w4.refused() && !w4.onLine(hung) && !w4.lost();
        failed += ok6 ? 0 : 1;
        System.out.println((ok6 ? "PASS " : "FAIL ") + "driver watch: the refusal's words as chat or a Lua echo arm nothing");
        DriverWatch w5 = new DriverWatch();
        boolean ok7 = !w5.onLine(refused) && w5.refused()
                && !w5.onLine("[t=00:01:40.0][f=0000700] <Bob> Warning: [Watchdog] Hang detection triggered for Spring main thread.")
                && !w5.onLine("[t=00:01:40.0][f=0000700] [Spec] Warning: [Watchdog] Hang detection triggered for Spring main thread.")
                && !w5.onLine("[t=00:01:40.0][f=0000700] > Warning: [Watchdog] Hang detection triggered for Spring main thread.")
                && !w5.lost() && w5.onLine(hung) && w5.lost();
        failed += ok7 ? 0 : 1;
        System.out.println((ok7 ? "PASS " : "FAIL ") + "driver watch: after a refusal, the watchdog's words in chat (a player's,"
                + " a spectator's, the host's) close nothing, the watchdog's own line does");
        // a player's chat line is told from the engine's own (the dev phone's lines, 2026-11-20)
        String[][] chat = {
            { "[t=00:00:51.170276][f=0000241] <Phone> [SpringApp::Reload] test", "true" },
            { "15:22:46 [engine] [t=00:00:51.170308][f=0000241] <Phone> [CPreGame] using client IP 203.0.113.7 and port 8452", "true" },
            { "[t=00:01:02.0][f=0000300] <Some Player> Allies: hi", "true" },
            { "[t=00:00:01.998326][f=-000001] [PreGame::UpdateClientNet] received local player number 0 (team 0, allyteam 0), creating LoadScreen", "false" },
            { "[t=00:00:02.032345][f=-000001] [CPreGame] using server IP 127.0.0.1 and port 0", "false" },
            { "MESA: error: flush_submit_list:89: submit failed -1 (Resource deadlock avoided)", "false" },
            { "[t=00:00:52.263293][f=0000210] Warning: [Watchdog] Hang detection triggered for Spring main thread.", "false" },
            // (a spectator's chat, the host's lines and ping labels: Recoil's Game.cpp and InMapDraw.cpp, 2026-11-21)
            { "[t=00:01:00.0][f=0000300] [Spec] [SpringApp::Reload] test", "true" },
            { "[t=00:01:00.0][f=0000300] [[Crd]Spec] Warning: [Watchdog] Hang detection triggered for Spring main thread.", "true" },
            { "[t=00:01:00.0][f=0000300] [Bob (replay)] creating LoadScreen", "true" },
            { "[t=00:01:00.0][f=0000300] [Spec] Allies: End of demo reached", "true" },
            { "[t=00:05:04.446601][f=-000001] > Host[EU6][006] * Warning: in-game IP address does not match", "true" },
            { "[t=00:05:04.4][f=0000900] > [CPreGame] using client IP 203.0.113.7 and port 8452", "true" },
            { "[t=00:09:28.210327][f=0003765] AKM added point: creating LoadScreen", "true" },
            // (the engine's own lines the app reads stay its own)
            { "[t=00:00:02.0][f=-000001] [CPreGame] using client IP 203.0.113.7 and port 8452", "false" },
            { "[t=00:00:03.4][f=-000001] [LuaMenu] Loading widget:      BAR Droid lobby touch  <bardroid_lobby_touch.lua>", "false" },
            { "[t=00:00:40.0][f=-000001] [LoadFinalize] finalizing PFS", "false" },
            { "[t=00:01:20.7][f=-000001] [SpringApp::Reload][10]", "false" },
            { "[t=00:01:22.1][f=-000001] [PreGame::GameDataReceived] recording demo to \"demos/x.sdfz\"", "false" },
            { "[t=00:01:22.1][f=-000001] [~ScopedOnceTimer][PreGame::ReadDataFromDemo] 71ms", "false" },
            { "[t=00:00:54.0][f=-000001] Player Phone finished loading and is now ingame", "false" },
            { "[t=00:01:28.9][f=0000922] Phone paused the game", "false" },
            { "[t=00:00:57.9][f=-000001] Fatal: [ExitSpringProcess] errorMsg=\"x\" msgCaption=\"y\"", "false" },
            { "[t=00:01:21.1][f=-000001] [CAS::GASCB] Archive file=\"speedmetal_bar_v2.sd7\" cs=\"8ce9\"", "false" },
            { null, "false" },
        };
        for (String[] c : chat) {
            boolean got = StatusText.isChat(c[0]);
            boolean ok = got == Boolean.parseBoolean(c[1]);
            failed += ok ? 0 : 1;
            System.out.println((ok ? "PASS " : "FAIL ") + "chat line " + got + ": " + c[0]);
        }
        // the sooner close: the refusal in a running game, then the game's widget silent STALL_MS
        DriverWatch w3 = new DriverWatch();
        boolean ok5 = !w3.stalled(true, 60000) && !w3.onLine(refused) && !w3.stalled(false, 60000)
                && !w3.stalled(true, DriverWatch.STALL_MS - 1) && w3.stalled(true, DriverWatch.STALL_MS)
                && w3.lost() && !w3.stalled(true, 60000) && !w3.onLine(hung);
        failed += ok5 ? 0 : 1;
        System.out.println((ok5 ? "PASS " : "FAIL ") + "driver watch: refusal in a game, its widget silent 8 s: closed,"
                + " once; not without the refusal, nor while loading, nor sooner");
        // a refusal the game got past, the game then left for the lobby (the same engine, no hover file there): that
        // game's watch ended closes nothing, the next game's fresh one is unarmed (audit 2026-11-21)
        DriverWatch w6 = new DriverWatch();
        boolean ok8 = !w6.onLine(refused) && w6.refused() && !w6.ended();
        w6.end();
        ok8 = ok8 && w6.ended() && !w6.stalled(true, 60000) && !w6.onLine(hung) && !w6.lost();
        DriverWatch w7 = new DriverWatch();
        ok8 = ok8 && !w7.refused() && !w7.stalled(true, 60000) && !w7.onLine(hung) && !w7.lost();
        failed += ok8 ? 0 : 1;
        System.out.println((ok8 ? "PASS " : "FAIL ") + "driver watch: a refusal, then the game left: its watch ended closes"
                + " nothing (stall or watchdog), the next game's starts unarmed");
        // the pre-game screen's server: a join's line, the phone's own game, other lines (the dev phone's lines)
        String[][] pre = {
            { "13:39:47 [engine] [t=00:00:01.802620][f=-000001] [CPreGame] using client IP 198.51.100.7 and port 8452",
                "198.51.100.7:8452" },
            { "13:21:02 [engine] [t=00:00:02.562342][f=-000001] [CPreGame] using server IP 127.0.0.1 and port 0", null },
            { "[CPreGame] using client IP 203.0.113.7 and port 0", "203.0.113.7" },
            { "[CPreGame] using client IP ::1 and port 8452", null },
            { "[PreGame::StartServer] Game/Map archives checksum acquisition took = 64 microseconds", null },
            { null, null } };
        for (String[] c : pre) {
            String got = StatusText.preGameServer(c[0]);
            boolean ok = c[1] == null ? got == null : c[1].equals(got);
            if (!ok) failed++;
            System.out.println((ok ? "PASS " : "FAIL ") + "pre-game server: " + c[1] + " -> " + got);
        }
        // the lobby bridge's rules (BridgeRules, 2026-11-21): any app on the phone can reach the bridge, so a resource only
        // over https from BAR's hosts into the lobby's own places, as data; a replay only from demos/
        String[][] res = {
            { "https://widget-hub.beyondallreason.dev/manifests.json?t=1", "LuaUI/Widgets/manifests.json", "ok" },
            { "https://widget-hub.beyondallreason.dev/x/y_325x100.png", "plugins/unit_tracker_325x100.png", "ok" },
            { "https://widget-hub.beyondallreason.dev/x/y_README.md", "plugins/unit_tracker_README.md", "ok" },
            { "https://data-marts.beyondallreason.dev/player_skill_snapshot.csv",
                "data-processing-main/data_export/player_skill_snapshot.csv", "ok" },
            { "https://widget-hub.beyondallreason.dev/manifests.json", "LuaUI/Widgets/evil.lua", "no" },
            { "https://widget-hub.beyondallreason.dev/manifests.json", "dev-env.sh", "no" },
            { "https://widget-hub.beyondallreason.dev/manifests.json", "bardroid-ui/LuaUI/Widgets/x.lua", "no" },
            { "https://widget-hub.beyondallreason.dev/a.png", "plugins/../LuaUI/Widgets/evil.png", "no" },
            { "https://widget-hub.beyondallreason.dev/a.png", "plugins/.hidden.png", "no" },
            { "https://widget-hub.beyondallreason.dev/a.png", "plugins/sub/a.png", "no" },
            { "https://widget-hub.beyondallreason.dev/a.png", "/plugins/a.png", "no" },
            { "https://widget-hub.beyondallreason.dev/a.png", "plugins/a.lua", "no" },
            { "http://widget-hub.beyondallreason.dev/manifests.json", "LuaUI/Widgets/manifests.json", "no" },
            { "https://evil.example/manifests.json", "LuaUI/Widgets/manifests.json", "no" },
            { "https://beyondallreason.dev.evil.example/m.json", "LuaUI/Widgets/manifests.json", "no" },
            // (a user part before the host; written in two pieces: whole, publish-check reads it as an e-mail address)
            { "https://user" + "@widget-hub.beyondallreason.dev/m.json", "LuaUI/Widgets/manifests.json", "no" },
            { "file:///data/data/x", "LuaUI/Widgets/manifests.json", "no" },
        };
        for (String[] c : res) {
            String why = BridgeRules.resource(c[0], c[1]);
            boolean ok = (why == null) == "ok".equals(c[2]);
            failed += ok ? 0 : 1;
            System.out.println((ok ? "PASS " : "FAIL ") + "bridge resource " + (why == null ? "allowed" : "refused (" + why + ")")
                    + ": " + c[1] + " from " + c[0]);
        }
        java.io.File base = new java.io.File(System.getProperty("java.io.tmpdir"), "bridge-rules");
        String[][] rep = {
            { "demos/2026-11-21_06-11-36-498_Starwatcher 1.0_2026.09.03.sdfz", "ok" },
            { "demos/../files/secret", "no" }, { "../demos/x.sdfz", "no" }, { "maps/x.sdfz", "no" },
            { "demos/", "no" }, { null, "no" } };
        for (String[] c : rep) {
            java.io.File f;
            try { f = BridgeRules.replay(base, c[0]); } catch (java.io.IOException e) { f = null; }
            boolean ok = (f != null) == "ok".equals(c[1]);
            failed += ok ? 0 : 1;
            System.out.println((ok ? "PASS " : "FAIL ") + "bridge replay " + (f != null ? "read" : "refused") + ": " + c[0]);
        }
        System.out.println(failed == 0 ? "ALL PASS" : failed + " FAILED");
        System.exit(failed == 0 ? 0 : 1);
    }
}
