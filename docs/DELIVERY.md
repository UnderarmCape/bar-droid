# Delivery: from this checkout to a public GitHub release

Kailil (2026-10-28): make the project easy to hand to BAR's developers and to anyone who wants to download and play
BAR on Android from GitHub, "so when we are ready to publish its simple to do so. even as we expand features".
This file is the backlog for that; each item is done in a small tested commit and ticked here. Nothing is pushed,
published or posted without Kailil.

What the release is (Kailil, 2026-10-28): "im just posting it on github, then putting it in the BAR discord modding
discussion page, then asking them all to fix and check my code to make it official. i dont want to own or continue
this project. I want the community and devs to take this stepping stone and get BAR android official ... But i need
help with optimziation on the engine side, and touch controls". So: one release, no maintainer afterwards; the
repository says so (README "Status", CONTRIBUTING, [HELP-WANTED.md](HELP-WANTED.md)), and the Discord post is drafted
in `C:\Tools\BARANDROID\discord-post.md` (outside the repository; Kailil posts it and fills in the repository's URL).

## Where it stands (audit, 2026-10-28)

- Small and self-contained: 174 tracked files, 14.8 MB (the largest is the emulator's ANGLE, 6 MB). Prebuilt
  helpers are committed with the tools that rebuild them; BAR's content is never in the repository or the APK.
- README.md already explains the app, the phone requirements, the build and the checks.
- Blockers for a public release:
  1. **The app icon** is Kailil's edit of BAR's launcher icon (CC BY-NC-ND): it must not be in a published APK, and
     the two PNGs are tracked, so also not in a published repository (or its history).
  2. **No LICENSE file**, although README says GPL-3.0-or-later (required anyway: the app embeds Termux:X11's GPL-3
     `lorie` module).
  3. **Personal data in tracked files**: the phone's Wi-Fi address and serial, the home Wi-Fi's name (CLAUDE.md,
     HANDOFF.md) and the address as a default in `tools/phone-bench.ps1`.
  4. **Release signing**: release builds use the public debug key (`app/bardroid-debug.jks`). Fine for a test build,
     wrong for a release others update from.
- Missing for others: a players' page (download, install, first run, known limits), a developers' page (build,
  architecture, tests, rules such as online-safe only), CHANGELOG, CONTRIBUTING, an issue template that asks for the
  logs, and CI that builds the APK.

## Backlog (in order)

### Kailil's queue (2026-11-10, upright touch play): before the rest, in this order
Automation is Kailil's and BAR's developers' decision (Kailil, 2026-11-10: touch players must compete fairly with
keyboard and mouse, "The devs theories consist of automating micro movements ... the decision on balance is up to us"):
the app's widgets give the orders these need (`GiveOrder`), running as game widgets as the unit control restrictions
were already set aside for (`BARDROID_GAME_WIDGETS`, the engine branch). Where BAR's own command and a click do the
same, that stays the simpler way.
- [x] **Kailil's Fold7 notes, 2026-11-10 ~20:40** (with screenshots), each on the dev phone upright:
      - **Building by one finger "keeps canceling a place" (a Bot Lab)**: the dock's menu went back to the camera pad
        2 s after the last touch while the spot was picked on the map, and PLACE's tap then only opened the menu again.
        The menu now stays open while a building is picked (and while the presets, the teammate picker or the resource
        panel cover the grid: the presets' tap was lost the same way). Bot Lab, spot, PLACE 3.2 s later: queued at
        once, the lab still picked. (A spot on a slope shows the lab red and BAR refuses it, as on a PC.)
      - **LOCAL / ALL UNITS: the picked units' orders on the right** instead of the list buttons (those stay for an
        empty pick). ALL UNITS with six Pawns: ALL 6 and the Pawn on the left, Fight / Move / Patrol / PRESETS right.
      - **D-gun mode**: the walk's step 56 ahead every 0.15 s (was 150 every 0.2 s) and a stop as the stick comes to
        rest: stood still 0.18 s after release (it walked on ~4 s). The sonar: a ping ring out to the range every
        1.1 s and a radar wedge sweeping behind a bright line. FIRE's swipe right goes the whole way, past 0.92 the
        track locks full gold with AUTO on it and the button fills gold from the left; AUTO's swipe left has its own
        track to the cancel corner (FIRE at its end; it was frozen), and the gold drains out of the button
        (`dgun_auto_off`, "dgunauto 1" in the dock file tells RtsTouch which way). Screenshots of each step (and at the
        Fold7's unfolded shape, wm size 1080x1198: both tracks drawn and locking, the left one narrower). No
        gamepad words over the map when the touch dock opens the mode.
      - **Presets: STRAFE in ZIGZAG's place** ("fight to the destination then sit at the destination repeating a
        left and right strafe via a repeat ... via a fight command"): each unit, keeping its place in the group, a
        fight to the destination's left side, one to its right side, repeat on. **The destination set where the
        finger lifts**: a press on the map aims (a gold ring, the line from the group, the strafe's line), a drag
        moves it (it was BAR's right drag, whose press cancelled the preset). Six Pawns: two fights each, Repeat On.
      - **BAR not opening from the icon** ("1 of the app's adjustments to BAR did not apply"; "BAR's current version
        failed here before; kept the last good one"): a lobby that ends within 60 s keeps the icon on the launcher
        next time; one the player closed (Stop, swiped away) or the low-memory killer ended no longer counts. Why
        BAR's new release failed on the Fold7 needs its logs (the dev phone has no internet here to fetch it).
        Then (Kailil, ~23:58, the new build installed: "Why did it boot the launcher instead of the game"): two causes.
        The flag stayed set until a lobby started from the launcher (his last check was 20:21), and the launcher shared
        the icon's task, so once shown the icon brought it back without asking StartActivity. Now the flag is cleared
        as the launcher shows for it (once), and LauncherActivity has a task of its own (StartActivity's closes
        itself). Dev phone, flag set, icon taps by `monkey`: the launcher, Home, then the lobby (fdb4fe9, sent).
        BAR's Alpha set that evening: engine 2026.07.04 (unchanged), lobby test-4674 (the dev phone's), game
        test-31908-af896c5 (the dev phone has test-31836). The four copies' patches all find their places in
        test-31908's files (GitHub at af896c5: build menu 26, order menu 12, mission info 4, team stats 3), so the
        missed adjustment is one of launch-bar.sh's config checks (`layer_miss`), named in the Fold7's launcher.log.
        A review of the warning's code (11-11 ~01:10) found a stale case, not the Fold7's (its engine did not change): a
        newer engine's springsettings miss stayed counted after a rollback to the older engine; now it counts only
        while that engine plays (797e625, updater-test). The miss is named on the line under the warning, smaller and
        grey (0dafd9e). With updates off the last check's line no longer repeats "(automatic updates off)" over "BAR
        updates: only with Install / Update".
      - **Presets from the void** (review, 11-11 ~01:20): a preset's drag that began over no ground (the void past
        the map's edge, upright at the top of the view near an edge) was lost whole, the preset still armed; the aim
        now begins where the finger reaches the ground (68f62ea). dock-phone-test drags STRAFE from the void by the
        nearest edge (the old build: no orders; the new: 2 fights each) and, after its build stage lost the commander
        in 2 runs of 5 (the dock's menu not open 4 s after the first tap, so the spot's tap picked the ground), taps
        again with a note and waits for the building before its spot (8be7fec): ALL PASS. Its timings since (1dd18f6;
        3 runs: the menu 0.5-1.0 s after the first tap, the building 0.26-0.5 s after the second): the lost commander
        not seen again. `-Shots` keeps screenshots of the placing panel, the D-gun mode and a preset's aim
        (build\dock-*.png). From one: an armed preset looked like nothing on the dock once its note had gone, so
        PRESETS is gold with the preset's name (STRAFE) while the map waits for the drag. In the same screenshot the
        ground of Play vs AI's map near its north-east corner in broad diagonal bands (the interface whole, 36 s in,
        phone shadows off): likely the map's own sand ripples (its west edge's red ground had none); to compare with
        BAR on a PC some time.
      - **The D-gun's walk stop over a shot** (review, 11-11 ~02:15): fired while walking, then the stick let go: the
        stop held back over the shot went out 0.6 s later and dropped a shot still turning, walking into range or
        waiting for energy; a shot ordered after the last step now ends the walk itself (12ae122; pad-test -Dgun's
        new case: the old build sent a move over the shot, the new none). The infolog and launcher.log of the evening's
        games: BAR's own warnings only, and the lobby's two downloads failing offline. Polish from the -Shots
        screenshot: in full auto the stick's red aim line and target ring pointed at a spot AUTO ignores; they are
        drawn only outside it, and the AIM stick is grey, "AIM: AUTO".
      - **The phone tests on the newest build** (11-11 ~02:35, dev phone): touch-phone-test, lobby-phone-test,
        pad-test, -Share, -Chat, fp-save-test, then dock-phone-test: ALL PASS. VoiceChat reviewed (sessions numbered,
        the recognizer destroyed per session, close() on onStop): nothing found; a recognizer that never answers would
        keep "SPEAK TO CHAT" up, not testable without the live microphone. The Play vs AI map's straight, even diagonal bands
        (settled 11-11 ~03:40): BAR's fog-of-war stripes, Fog Diagonal Lines GL4, over ground the player does not see;
        the dev phone's lobby has AdvMapShading = 1, so launch-bar.sh leaves that widget on (it turns it off only with
        plain map shading, where it draws nothing). As meant, not the drawing (the "sand ripples" guess was wrong).
        Polish from that screenshot: the building PLACE
        builds is now marked on the dock (BAR's picked cell, the picture closer in gold light, and the build menu
        copy's gold line); FlowUI's selector alone was a faint border.
      - **A 6-minute upright skirmish, nothing touched** (11-11 ~02:50, dev phone): 30 fps each minute (slowest frame
        47-349 ms), no error from the app's widgets; Lua's memory 135, 127, 142, 143, 147, 148 MB (the collector's
        sawtooth; too short to call a leak: watch it in a long game). The share list reviewed (a dead teammate, the
        storage room under BAR's share slider, units BAR kept): matches pad-test -Share, nothing found. From the late
        screenshot: the dock's state lights were the other way round from BAR's order menu ("Fire at will" red,
        "Hold pos" and "Repeat Off" green); now as BAR's DrawCell colours them: the first state red, the second yellow
        (green of two), the third green.
      - **15 minutes upright, nothing touched** (11-11 ~03:15, dev phone): Lua's memory 135-177 MB, its lows not
        rising (135, 144, 140, 136): no leak; 30 fps, no app error. The upright lobby's screenshot (offline, the login
        guard): the arrow pointer stood over the lobby until the first touch. The game screen now starts as for
        fingers when no input has come yet and no external mouse or gamepad is connected (Samsung's built-in
        "sec_touchpad" reports a mouse: external devices only), sent again at 0.5-15 s as the X server and the lobby
        come up; any other input brings the pointer back, and a game's gesture shows it as before. Dev phone: the
        lobby without the arrow; lobby-phone-test (the pad in the lobby), pad-test, touch-phone-test, dock-phone-test
        (the pointer at the preset's aim): ALL PASS.
      - **PLACE's dead column upright** (11-11 ~03:45, from the placing screenshot): the tall green PLACE panel's tap
        area was only its left part (beside rotate and cancel at its foot), so the column above those two buttons, 40 %
        of the green, did nothing. Upright PLACE is now the whole panel but the two buttons (make-buildmenu.py's
        layoutPanel, the copy and its patches remade from the same BAR file, remake-check equal), and RtsTouch tells
        rotate and cancel first. dock-phone-test taps PLACE at the panel's middle (in the old dead column): queued;
        and a new case, cancel puts the building away without placing: ALL PASS. The word PLACE sits in the room
        above the two buttons.
      - **The upright start view** (11-11 ~04:00, two skirmishes): a screenshot within a second of frame 40 shows the
        commander on the dock's top edge (the engine's middle), the view easing to the start fit (the camera's ease
        runs longer than its 0.25 s); 6 s later the commander is in the middle of the view above the dock. A second
        fit at frame 120 was tried and found nothing to do: left out, the start fit works. (The skirmish's pregame
        lasts ~2 s, its dock not caught in a screenshot.) Polish: the launcher's "Free storage" and "RAM" in one
        decimal (75.8 GB, 6.9 GB; downloads keep two).
      - **The evening's dock changes at the Fold7 unfolded** (11-11 ~04:10, dev phone at 1080x1198, then reset):
        dock-phone-test ALL PASS (the whole-panel PLACE, its cancel case, the gold tile, STRAFE in gold, AIM: AUTO).
        Its placing screenshot caught a regression of the last run's polish: the one-row PLACE panel there has no
        room above rotate and cancel, and the word shrank to a speck. The word now goes above the two buttons or
        beside them, wherever it is the larger: beside on the unfolded shape, above on the tall one; both shapes
        ALL PASS.
      - **The evening's starts on the dev phone** (11-11 ~04:20, its two launcher logs): 35 engine starts, no hang, no
        GPU driver fault, one game closed by Android for memory (the 8 GB phone). The upright lobby at 1080x1198 opens
        on Chobby's account dialog (offline), nothing of the app's out of place. Polish, from a landscape run Android
        closed for memory: the launcher's low-memory note was four amber lines; its advice ("Close the other apps
        ...") is now on a line of its own under the warning, smaller and grey, and an engine killed from outside (exit
        137, not the player's Stop) shows "Ready" over it as Android's ending of the whole app does, not "Game ended with
        an error (137)". Dev phone: the engine SIGKILLed mid-game, the launcher's screenshot.
      - **Share logs** (11-11 ~04:30, the button Kailil is asked to use for the Fold7's logs): it zipped on the UI
        thread (after a long game the infolog alone runs to tens of MB: the launcher could stall into "not
        responding"), and left out the updater's own state (BAR's versions kept off as failed, the engine's missed
        settings: what the Fold7's "failed here before" needs). Now zipped on a thread of its own ("Zipping the
        logs..."; launcher.log "logs zipped: N KB in M ms"), update-state.properties in it. Dev phone: 2045 KB in 288
        ms, the share sheet up, closed with Back (nothing sent); the zip holds launcher.log and .old, infolog.txt and
        BAR's older infologs (logs/), springsettings.cfg, both state files, android-layer.txt.
        (On the way: `am start --es start skirmish` after an install without a force-stop is ignored on purpose: the
        launcher is restored with its saved state, as after Android ends the app for memory; the tools force-stop.)
      - **The launcher's other buttons and settings** (11-11 ~04:35, dev phone): Display (Termux:X11's pages, our
        summaries; its touch mode acts when "BAR touch controls" is off), GL check (2 s, the result in white), the
        settings column through Advanced, the left column scrolling to the log (the version line reachable): nothing
        broken. Polish: GL check names the GPU as players know it, "Adreno 740 (Freedreno)" for Freedreno's "FD740"
        (StatusText.gpuName, status-text-test's new cases).
      - **Share logs tapped twice** (11-11 ~04:40, review of the evening's LogShare): two quick taps zipped twice, the
        second deleting the first's zip as it was written (1360 KB of 2048) and two share sheets stacked, the lower one's
        file gone. A tap while a zip is made, until its sheet is started, is let go ("share logs: already zipping" in
        launcher.log). Dev phone, two taps 0.15 s apart: before, two zips and two sheets; after, one zip whole and one
        sheet (closed with Back, nothing sent). No polish this run: the screens looked at had nothing of the app's to
        better.
      - **Double taps elsewhere and landscape at the Fold7 unfolded** (11-11 ~04:50, dev phone): GameService drops a
        start while busy (Play, Lobby, GL check, Benchmark, Install / Update: one run), Display twice quickly opens one
        screen; a landscape skirmish at 1198x1080: the build and order menu copies, QUEUE, the small minimap and
        player list and BAR's panels all in place, nothing over another. Nothing to change.
      - **A tap on the upright lobby's strip while it settles** (11-11 ~05:00, review of the paging): the press stopped
        the strip's ease and the release only clicked, so a swipe and a quick tap left the page ~40 px off its place
        (a sliver of the page before at the edge) and clicked a button sliding under the finger. A tap that lands while
        the strip eases now finishes the page turn and clicks nothing. Dev phone, upright, offline (the login guard,
        Chobby's account dialog cancelled): a swipe then a tap 0.1 s after, before: page 2 off by 40 px; after: in
        place; a tap at rest still clicks (Downloads opened); lobby-phone-test ALL PASS.
      - **A tap on a flying lobby list** (11-11 ~05:05, the same review): a press stopped a fling and the release
        clicked (or opened a server's details) whatever passed under the finger. A tap on a list still flying faster
        than a fling starts (150 list px a second) now only stops it, as on any phone ("a tap stopped a flying list" in
        infolog); slower, it clicks as before. Dev phone, upright lobby offline: the news panel flung, a tap at once:
        stopped, no click, nothing opened; lobby-phone-test ALL PASS.
      - **A tap to stop the gliding camera** (11-11 ~05:15, the same review in the game): a touch stopped the map's
        glide after a flick, and the touch lifted as a tap then clicked there: on empty ground it deselected the
        player's units (upright, the dock's camera pad flicked and the game tapped: 1 picked -> 0), and on the pad it
        opened the dock's menu. A tap that stops a glide still faster than a fling starts is now only that (launcher.log
        "a touch on the gliding map (N px/s): it stops it, no tap"). Dev phone, upright skirmish: before, the commander
        deselected; after, kept (12148 px/s logged), and a tap at rest still deselects. The scratch test's timing is
        loose (adb's tap can come after the 1.2 s glide on a busy phone; such a run is a plain tap at rest), so the
        log line tells which a run was. After it: touch-phone-test, pad-test and dock-phone-test ALL PASS.
      - **A tap on the dock's rows while they settle** (11-11 ~05:35, the same review in the dock): after a flick the
        rows ease 0.3 s onto whole rows, and a tap meanwhile picked the item passing under the finger (a building at
        random). A tap on a half whose rows still settle is now no press, the rows settle on (infolog "a tap on settling
        rows: no press"). Dev phone, upright, the menu open, the build list flicked and a tile tapped at once: before,
        a building picked; after, none, and a tile tapped at rest picks it; dock-phone-test ALL PASS.
      - **A preset's drag lifted over the dock** (11-11 ~05:45): it was sent to the ground hidden behind the dock. Lifted
        there it now backs out ("STRAFE: NOT SENT, DRAG TO THE DESTINATION"), the preset still armed for another drag.
        dock-phone-test's new case (a drag from the map onto the dock: 0 fights, still armed), then STRAFE as before:
        ALL PASS. (The Fold7 out of AirDrop's reach since 03:10: no build sent tonight after 9e4e462.)
      - **A path drawn on into the dock** (11-11 ~06:00): BAR's right drag (units picked, a drag on the game) went on
        behind the dock and let go there: the order's end on ground the dock hides (Pawns' goals down to y 482 with the
        dock's top at 974). RtsTouch now holds the drawing point at the dock's top edge, moves and release. Dev phone,
        dock-phone-test's new case: let go at y 974 (the edge); BAR's formation still lengthens a line too short for
        six Pawns' spacing a little past its end (by design). ALL PASS.
      - **A building dragged on into the dock** (11-11 ~06:10): a picked building with no spot yet follows the
        finger (ONE), and dragged on into the dock it went behind it (the place file had no spot on the screen); a
        GRID's far corner likewise. Both are now held at the dock's top edge (RtsTouch sendSpot, gridTo).
        dock-phone-test's new case: the building dragged from the map onto the dock, its spot at y 1037 under a dock
        top of 1039 (before: none in sight): ALL PASS. The GRID corner's hold has its case since (a finger held on the
        map with the building picked, dragged on into the dock: the pointer held down at y 974, the dock's top; the
        panel's cancel then lets it go, nothing placed): ALL PASS.
      - **The open dock's selection dragged on into it** (11-11 ~06:25): BAR's box (nothing picked, the menu open, a
        drag on the game) followed the finger into the dock and picked units it hides (let go at y 482 under a dock top
        of 974); its corner is now held at the dock's top edge (RtsTouch, while the dock selects), and the circle's
        pick keeps only units in sight above the dock (portrait pickCircle). dock-phone-test's new case (box): let go at
        y 974; ALL PASS. The circle's filter has its case since (11-11 ~07:00; the portrait's WG selectStyle for tools,
        put back after): a Pawn given behind the dock, a circle drawn from above the dock on into it, the Pawn inside it
        on the ground: "6 units in it, 5 in sight above the dock", the hidden one not picked; ALL PASS. (On the way: the
        dock is lower with nothing picked, its selection row gone, so the case deselects first: placed under the higher
        dock the Pawn was in sight by the time the circle was drawn.)
      - **Chobby's repeated notes upright** (11-11 ~07:15, the upright Skirmish screen offline): Chobby retries a failed
        map download three times, each with its own "Download Failed" note, and the three stacked over half the
        screen's Next button. Upright, a note whose words repeat one above it is now put out of sight (it times out as
        Chobby's own; "a repeated note out of sight" in infolog). Dev phone: a failed map's two repeats and a
        skill-rating download's out of sight, one note left; lobby-phone-test ALL PASS. That one note still covered part
        of Next and all of the Skirmish screens' Advanced (Chobby lays those along the panel's foot, just above the
        grid), so upright the notes now stack down from the screen's top, over the logo's strip (at its right, over part
        of "Offline" for their few seconds). Dev phone: Next and Advanced clear, the note at the top right;
        lobby-phone-test ALL PASS. The upright Skirmish screens after (Game Type, Difficulty, Faction, and Advanced's
        battle room: teams, map, options, Start in reach) looked over: nothing of the app's to change.
      - **The phone tests after the dock-edge and tap changes** (11-11 ~06:45, dev phone, f169632's build):
        touch-phone-test, pad-test, -Online, -Dgun, -Share, -Chat, lobby-phone-test, fp-save-test, with
        dock-phone-test just before: ALL PASS.
      - **BAR's top bar buttons upright** (found 11-11 ~07:30, dev phone, a lobby skirmish upright on Onyx Cauldron):
        Statistics and Settings did nothing, showing the energy bar's and the tide's tooltips instead. Upright the dock
        hides BAR's resource bars and indicators, and BAR's Top Bar hides them from the picture only: still under the
        pointer, under the Top Bar Buttons strip (wider there than its quarter of the bar), they took the press first
        (gui_top_bar.lua hoveringElement). `bardroid_topbar.lua` (new, layer -95500): a press on a button over that
        hidden part does the button's action through BAR's WG windows (written for all of BAR's buttons; Save and
        Lobby lay clear of the hidden part in these games, so only Settings and Statistics went through it), and those
        tooltips are taken away. Dev phone: Statistics over the hidden energy bar opened and closed (launcher
        skirmish), Settings over the hidden tide opened and Statistics after it (lobby skirmish's pregame on Onyx
        Cauldron), no stray tooltips; dock-phone-test ALL PASS. BAR's own fix, `docs/upstream/bar-topbar-hidden.patch`
        (+ .md, a draft for Kailil to post): tried on the dev phone the same way as the windows' patch, with the
        app's widget off: Statistics and Settings by BAR's own buttons.
      - **BAR's pregame lines off the dock upright** (seen with the top bar above): "Pick a starting location within
        the green area then click Ready" (BAR's draft-order Pregame UI, 20 % up the screen, layer -999999: drawn after
        every widget) lay across the dock's build tiles and RANDOM. Before the game the dock is drawn again over the
        band of that widget's lines (19-27 % up: also its "Waiting for ..." ones), after everything (DrawScreenPost,
        the dock's texture as it is), unless one of BAR's windows is open or the dock was not drawn that frame (the
        lobby over the game, a modal window). Without the draft order BAR's start box widget writes its line under
        the dock already. Dev phone, a lobby skirmish upright: RANDOM and the tiles clean before and after the start
        spot; Settings open: BAR's line shows below it, as before; Ready, the game as before; dock-phone-test ALL PASS.
        (On the way: a white square around the commander for its first seconds, gone by frame 40: next item.)
      - **Open: a white square at the start on Avalanche** (11-11 ~08:30, dev phone, upright): for about the game's
        first second a sharp-edged, ground-aligned light square (~120 px, a parallelogram under the camera's tilt)
        around the commander, a round glow inside it: BAR's commander spawn effect (effects/commander-spawn.lua), its
        ground flash with its shape gone. Seen in two lobby skirmishes and two launcher skirmishes on Avalanche 3.4
        (start at the map's top left), not on Starwatcher (screenshot bursts from the first frame). Ruled out: the
        low-memory mode's texture compression losing the alpha (pace's texture log: Mesa stores the engine's generic
        GL_COMPRESSED_RGBA as DXT5, which keeps it; a run with DXT5 asked for outright: the same square; a
        CompressTextures 0 run showed a round flash, but its commander started elsewhere, so that proves nothing).
        Then (11-11 ~09:00) CompressTextures 0 with the top-left start: the same square, so compression is out. It
        goes with the start spot: all four top-left starts had it, both bottom-right ones a round flash (on brighter
        snow, where a faint square may not show). (StartPosType 0 in the launcher's script did not fix the spot: BAR
        still drew it.) Left: GroundDecals 0, the Fold7 (not in the low-memory mode), and BAR on a PC at that spot
        (the laptop only with Kailil's yes); `start-burst` style runs (launcher skirmish, its map set in the
        preferences, `screencap` from the first frame).
      - **The chat's lines no longer over the opened minimap upright** (seen in those bursts): the chat box moves up
        under the top bar while the minimap is open (at the game's start, or a tap), and it draws after the minimap:
        "Battle, Started" sat on the map. Its lines are drawn around the opened minimap's rect now (scissored), so
        the minimap lies over the box's corner as the layout meant; a short note under it shows once it is small
        again. Dev phone: an upright skirmish's first seconds, the opened minimap clean, the note under the small one
        after; pad-test -Chat ALL PASS.
      - **The phone tests after the top bar, pregame and chat changes** (11-11 ~09:10, dev phone): touch-phone-test,
        pad-test ALL PASS (dock-phone-test and pad-test -Chat with each change, above). The top bar's Save upright
        goes through bardroid_topbar.lua too ("save: pressed over BAR's hidden top bar"): a 7 MB save written, the game
        on after it. Every save holds the game about 4.5 s on the dev phone and leaves nothing picked; the same
        sideways with BAR's own Save button (the app's widget not in it), so BAR's or the engine's way, left as it is.
      - **The Fold7 reached again, its logs read** (11-11 ~09:25, Kailil: "Try the fold again"; adb over Tailscale on
        Wireless debugging's new port, found by trying the ports; no BAR running, so today's build b220f4f installed).
        Its launcher.log (to 11-10 23:56) answered the two open questions:
        - *The adjustment that did not apply* was the order menu copy: removed by BAR in one game on 11-05 23:29, its
          mark named only BAR's file, so BAR's own order menu ran there through every app update since. The mark names
          the copy too now (its md5, launch-bar.sh `copy_failed`, all four copies): a new copy gets another try, the
          same copy keeps giving way. Dev phone, three starts: an old mark, the copy ran; a removal in the last run's
          infolog, the new mark and BAR's own; the next start, BAR's own still (mark removed after).
        - *BAR's failed release*: byar:test a27e1c0e failed one start (fast, marked bad) and the lobby fetched it again;
          after that every start said it had failed before and started it as a "first start", never kept, as every
          session ended by a swipe (One UI ends the app, "REMOVE TASK", before closedByPlayer). The next start now
          judges such a run by its infolog (`Updater.judgeLastRun`: a game frame or 120 s, docs/UPDATES.md); the Fold7's
          last run played 9.5 minutes, so its next start keeps a27e1c0e, and the app update there clears the bad mark.
          updater-test ALL PASS (four new cases).
        The build with both and the next item installed on the Fold7 at 09:43 (no BAR running), after dock-phone-test
        ALL PASS on the dev phone; bd75ca1's at 09:56 (Kailil: "Send the latest to the fold"). Its first start, 10:00:
        "the app was updated: ... another try", "the last run of ... a27e1c0e ran 572 s with a game and ended from
        outside: judged now", "... started fine", then "starting" (no longer "first start"), BAR's test-31908-af896c5
        up to date; "order menu: the app's copy of BAR's", no ANDROID LAYER line. The sweep on bd75ca1's build, dev
        phone: pad-test -Share, -Online, -Dgun, lobby-phone-test, dock-phone-test ALL PASS.
        The Fold7's 10:00 start on BAR's newer release (test-31908-af896c5): all four copies in BAR's place, the build
        menu's made again on the phone for BAR's changed file (9dde14ed), no ANDROID LAYER line. The dev phone stays on
        test-31836 for now: its Install / Update found no network (Wi-Fi on, joined to none: "Unable to resolve host";
        no network is joined on it from here). The coloured strip once seen under the opened minimap at a start did not
        come back in two more starts (what stood out there was the minimap's own range rings).
      - **The launcher's low-memory note only says what applies**: "skirmish on a smaller map" stood there after the
        player had picked a map of their own (Prefs.mapChosen: the app's smaller map is a default only). Now only
        while the app's choice holds. Dev phone: with it, the note as before; with a map marked the player's, "plainer
        unit shading and map detail; close other apps before a game" on one line.
      - **The launcher's "Last check" is the last real check**: with updates off every game start wrote its time there
        (a local check, nothing asked of BAR), and an Install / Update that found no network was gone from the line at
        the next start. A start that does not go online keeps the last one that did (`Updater.checkLine`). Dev phone,
        no network: Install / Update at 10:40, a skirmish started at 10:40:20, the launcher after it: "Last check Nov 11
        10:40 (no answer from BAR)"; updater-test ALL PASS (three new cases).
      - **The top bar on the Fold7's unfolded shape** (dev phone at `wm size 1080x1198`, upright skirmish): the buttons
        small at the top right, clear of the hidden bars (wider screen), so Statistics opened by BAR's own button (the
        app's widget not needed there), the panel between the top bar and the dock. (The Fold7 itself was in a game at
        10:45: today's last two builds wait for it to be free.)
      - **No hidden sliders under the top strip upright** (found reading BAR's Top Bar for the above): its MousePress
        also hit-tests the hidden energy bar's conversion knob (any game) and the share knobs (team games): a press there
        dragged one unseen and set it where the finger let go. bardroid_topbar.lua takes every press over the hidden
        part now (a button's action as before; any other press does nothing, as BAR's Top Bar already made it do, minus
        the sliders). Dev phone upright: a tap on the strip beside the minimap logged as taken; Statistics as before.
- [x] **Kailil's dock notes, 2026-11-11 ~11:00 and ~11:20** (with screenshots), each on the dev phone upright:
      - **INSERT with a factory** blocked its +1 / +5 / +20 (BAR's CommandInsert makes a CMD.INSERT, which a factory's
        queue does not take): with only factories picked no CommandInsert key, the dock gives Alt (BAR's alt-click to
        the queue's front). **The upright loading bar** across the screen, BAR's words fitted; **Free memory** on the
        loading screen of a game the lobby starts too (4f640bd).
      - **No IDLE UNITS or IDLE BUILDER buttons**, the idle units list gone. **The idle builders in the groups row**,
        at its right: one tile per type (BAR's builders, as its Idle Builders widget counts them), its idle count at the
        top right; a tap picks the nearest unvisited one from the middle of the view and the camera goes there, taps on
        go through the rest (BAR's own cycling). Groups from the left, idle builders from the right; too many for the
        row: they follow the groups and the row scrolls sideways (a sideways drag on it, RtsTouch's `groups` rect). There
        with nothing picked and with picked units that have no orders; with orders, the remove buttons take the row's
        right and the tiles move left with them. Dev phone: the commander's tile ("1") at the row's right from the
        start, picked from it with the camera on it (the full row and the remove buttons beside idle tiles: below).
      - **PINGS in IDLE BUILDER's place** ("a button to go to last 4 pings like we have on controller. And to set a
        ping"): LAST PINGS, the camera to the newest ping from someone else, again within 2 s the one before, of the last
        4 ("2 OF 4" on it; the pad's list and cycle, which keeps 5: RB + D-pad up); PING, then a tap on the map (or the
        minimap) is a ping there, BAR's point marker (the button gold, "TAP MAP", for 10 s; again: not). Dev phone:
        "Look here! (map marker)" where the map was tapped; pad-test -Online's cycle ALL PASS. IDLE UNITS' place is open
        (a blank tile) until Kailil picks what goes there.
      - **PLACE's X twice the size**, **ROTATE 90°** in the old arrow's place (it read as redo; it turns the building
        90° a tap, as before). **No green ring at the spot**: the building's footprint, green as the engine's own, turned
        with it. **A finer drag**: the building comes down where the finger does, then moves by 12 % of the finger's way,
        rising smoothly to 60 % a quarter of the screen away (it followed the finger 1:1; a waiting one moved 50 %), the
        pointer with it so BAR's own ghost (red where it cannot stand) is on it; held still: the GRID as before; on
        into the dock: held at its top edge. Dev phone: 200 px of finger, the building ~50 px.
      - **No move path drawn after a building order**: while a picked unit has a building queued, a one-finger drag
        pans the camera; MOVE / FIGHT / PATROL pressed still draws a path, and the drag draws again once the buildings
        are done. Dev phone: a windmill placed, then a drag: the camera moved, no order.
      - dock-phone-test, pad-test, pad-test -Online ALL PASS on the build.
      - **The groups row full, seen on the phone** (11-11 ~12:40, a scratch widget giving ten builder types and
        factories by cheat in a skirmish): ten idle tiles and the commander's, past the row's width; a sideways drag
        with the menu open scrolls it, the remove buttons (the commander given a WAIT) take the right and the tiles
        move left. It stopped mid-tile, half tiles at both ends: now magnetic, as the dock's rows ("Do not allow scroll
        to half reveal objects"): when it scrolls the tiles are a little wider so a whole number fills the row, and on
        release (RtsTouch's dockfling with its sideways speed) it eases on to a whole tile, a flick further. Dev phone:
        a slow drag settled on seven whole tiles, a flick back on the first.
      - **No BAR order tooltips over the dock** (seen in the screenshots above): after a tap on the dock the pointer
        rests there, and the order menu copy under the dock showed its tooltip for 2.5 s, "Patrol" or "Fire at will",
        of its own hidden button under the pointer, not the dock's. None over the dock now (make-ordermenu.py,
        tooltipShows). Dev phone: Hold pos tapped, nothing shown a second later. dock-phone-test, touch-phone-test ALL
        PASS. On the Fold7 at 12:41 (89f5471's build, BAR not running there), with the batch above.
      - **A review of the batch** (11-11 ~13:00): PING stayed armed after units were picked, so the next map tap was a
        ping, not theirs: it disarms as the home grid goes (dev phone: PING, COMMANDER, a map tap: deselected, no ping).
        A ping's release that never came could have eaten a later dock tap (reset at each press). A GRID held after a
        fine drag started from the place file's spot, which can be a write behind: from the pointer now, which moved
        with the building (dev phone: the 3 x 3 windmills from the dragged one). **ROTATE as tall as the X** (80 % as
        wide; it was a small square beside it). The Fold7's last game (11:25, the build before) had no errors from the
        app's widgets. dock-phone-test ALL PASS.
      - **ROTATE and the X the same size, flush in the corner** (Kailil, ~13:05, on that screenshot: "Remove the padding
        on these buttons and shove them to the corner ... make the buttons the same size"): two squares of the X's size
        at the panel's bottom right, no padding round them, a hairline between them. Dev phone: ROTATE tapped, the
        building still picked, nothing placed; the X put it away; dock-phone-test ALL PASS.
- [ ] **Kailil's notes, 2026-11-11 ~13:10** (with screenshots of a spectated online game, its join, the home grid, the
      lobby's first picture), in order:
      - [x] **ROTATE without "90°"** ("90 degrees is the only rotate in the game so its redundant"): the word alone.
      - [x] **COMMANDER 30 % further out** ("too zoomed in"): the camera at 1.3 times the comfortable distance.
      - [x] **The join's pre-game screen upright, and Free memory on it**: the engine's "Waiting for server response"
        lays its lines from 60 % of the width on, cut off upright, and the app's loading state began only at the loading
        screen, so no button. From the engine's "[CPreGame] using client IP" (a game hosted elsewhere) to its loading
        screen the app covers the engine's screen but its last two lines (the version and the GPL notice) with the same
        news wrapped to the screen ("Waiting for the server", "Connecting to <address>", then "Checking the game's
        files"), Free memory at the top; a join that times out, or back in the lobby, gives the engine's screen back.
        Dev phone: a client script to an address nothing answers (dev-env.sh), the screen as above until the engine's
        timeout.
      - [x] **The lobby's first picture sharper** ("bar looks super low res ... keep the resolution and size down"):
        made again by `tools/make-loadscreen-upright.ps1` from BAR's picture: the word scaled by Lanczos and
        pre-sharpened (an unsharp mask) for the phone's two scalings on the way (the lobby's X screen under the display,
        then SGSR), the same size on the screen, 151 KB (was 127 KB). Dev phone: rivets and scratch crisp.
      - [x] **Spectating in the dock**: the spectator's buttons "much too small"; the same dock as playing; BAR's
        player list hidden and a team list in the dock (in the home grid's open place beside the pings); LAST PINGS
        only, no PING. Upright and spectating by touch the dock is up with the spectate widget's tools as its big
        buttons over the whole grid, six narrow columns: < PLAYER CAM > (the player's name in their colour once
        locked), TEAMS / LAST PINGS / HIDE, < FOLLOW UNIT > (the unit's name), FREE CAM / GROUP / FULL VIEW (BAR's
        specfullview); following, the camera's views (1st person, Shoulder, Table, Close, Mid, Tune) take the players'
        row. TEAMS lists every team, each alliance from a new row, the one watched lit, team colours along the bottom; a
        tap watches that team (BAR's specteam) with its player's camera and closes it. The dock's resources are the
        watched team's; their panels are off. The spectate widget's small bar stands down while the dock is up (Tune's
        settings still use it, above the dock). BAR's player list is under the dock; folded (HIDE), BAR's small list
        shows in its corner again: its API has no way to hide it (scale, columns, spectators only), a change for BAR's
        list would. Dev phone, a replay upright: the grid, TEAMS (Player, SimpleAI(1) (AI)), SimpleAI picked (the dock's
        metal went to the AI's), the list kept the menu open. Following, then seen in a spectated BARb vs BARb
        skirmish (a dev-env.sh client of the launcher's skirmish with the phone's player a spectator): > followed the
        Armada Commander (its name lit, the views' rows in), SHOULDER and 1ST PERSON turned the camera and lit, FREE CAM
        let go (the four rows back). There BAR's player list under the dock drew its tooltip ("Only view what the
        player can see") over the dock where the pointer rested: no BAR tooltip is drawn over the dock now (the dock
        drops WG.tooltip.ShowTooltip's asks while the pointer is on it); dock-phone-test ALL PASS.
        A long TEAMS list (review, 11-11 ~14:40): a drag on the left half of a grid over both halves (home, the
        spectator's, TEAMS, the teammate picker, a panel) went to the empty left half and panned the camera, so such a
        list scrolled from its right half only: the whole grid's now. And the place after an alliance's odd team is
        left empty (it was drawn as a button with nothing on it). Dev phone, nine NullAI teams in three alliances on
        Supreme Isthmus spectated: TEAMS 7 rows, a swipe on its left half scrolled it to Null8; dock-phone-test ALL PASS.
        Checked after (~14:50): a join nothing answers ends with the engine's exit and the launcher's "The connection to
        the game timed out" (nothing to fix). TUNE in the dock: the spectate widget's Tune rows come up over the dock,
        but at the old bar's size (half the dock's buttons, Kailil's "much too small") and narrowed for BAR's list under
        the dock: now as large as the width allows (about 1.7 times) across the whole width; dev phone, Distance's + took
        the taps (1300 to 1350, not saved).
        At the unfolded Fold7's shape (dev phone at 1080x1198, ~15:10) the spectator's grid had the playing grid's
        height, short there: four rows of 75 pixels, five of 62 while following. Spectating has no selection or groups
        rows, so the grid takes their room, up to five rows as tall as the build tiles: unfolded 130 / 104 pixels, the
        S23's own shape five rows of about 150 (the dock as tall as the playing one with its rows); laid out again when
        the player turns spectator. dock-phone-test ALL PASS.
      - [x] **A phone test sweep after the day's changes** (~15:30, dev phone): fp-save-test, lobby-phone-test, pad-test
        -Dgun, touch-phone-test ALL PASS (dock-phone-test and pad-test -Online passed earlier with them). The menu
        copies' error in an October replay (BAR's older widget handler has no RegisterUnitCommand) costs only that
        replay its menus: launch-bar.sh already keeps a replay from marking the copies failed. The join's waiting
        screen's title counts dots with its half-second check (a still screen for a slow server read as frozen), the
        unlit dots clear so the words stand still.
      - [ ] **BAR's player list hidden while the spectator's dock is folded** (from Kailil's "Hide the team list"; the
        dock covers it while up): BAR's gui_advplayerslist.lua (test-31836) offers only scale, columns, spectators and
        its position (WG.advplayerlist_api). A hide needs a change in BAR: a SetHidden that skips its DrawScreen and
        MousePress and gives GetPosition a collapsed rect at the bottom; the panels BAR stacks above it from that
        position (the Player View / Player Camera / TV buttons, the music player, the clock and speed line) are other
        widgets of BAR's and draw on unless each follows it: gui_advplayerslist_music_new.lua (placed on the list),
        gui_advplayerslist_unittotals.lua (on the music), gui_advplayerslist_gameinfo.lua (the clock, speed and fps
        line), camera_player_tv.lua (Player View / Player Camera / TV), gui_advplayerslist_mascot.lua and
        gui_clearmapmarks.lua (the eraser): seven of BAR's files, each a check in its DrawScreen and MousePress. That
        stack carries the clock and a replay's speed: Kailil's call whether the folded dock hides it too.
      - [x] **LAST PINGS says how many wait** (polish, ~16:10): it said nothing of whether there was a ping to see; now
        their count in gold at its top right, as the idle builders' (playing and spectating). Dev phone, two pings from
        "someone else" (bardroid_pad.lua's test hook): "2" on it, then 1 OF 2, 2 OF 2.
      - [x] **A review of the share code and the laptop's checks** (~16:20): the dock's teammate picker and SEND gives
        through bardroid_pad.lua's own rules (a teammate out of the game, their storage's share limit, anonymous mode):
        nothing to fix. updater-test, padgame-test, status-text-test ALL PASS. The join's line reading
        (`StatusText.preGameServer`, out of GameService, an Android class) now has laptop cases in status-text-test:
        a join's address and port, the phone's own game, port 0, ::1, other lines (6, ALL PASS); dev phone: the
        unanswered join still shows the fitted screen.
      - [x] **The playing dock at the unfolded shape** (~16:30, dev phone at 1080x1198): the home and orders as before, the
        idle commander's tile in the groups row. PLACE there is a short bar, ROTATE and the X as tall as it, and the word
        PLACE was centred on the whole panel, running into ROTATE: beside the buttons when they are as tall as the panel.
        Dev phone: unfolded, PLACE centred left of ROTATE; the S23's own shape, above them as before.
        The join's pre-game screen and a game's loading screen at that shape (~16:45): both fit; on the loading screen
        the load picture's commander fills the near-square screen and Free memory's two lines covered his head: there
        it is its name alone, one line (the S23's own shape keeps both lines). Dev phone, both shapes.
        The spectator's TEAMS and HIDE at that shape (~16:55): both work (the SHOW button at the bottom's middle); TEAMS
        always laid out five rows, so a 1v1's three were 70 pixels there: now as many as the spectator's grid, 4 or 5,
        more scroll (130 pixels unfolded).
        The upright lobby at that shape (~17:05, offline): BAR's account dialog and the lobby behind it fit; nothing to
        do. That closes the unfolded sweep of the day's screens: playing dock, PLACE, spectator grid, TEAMS, HIDE, the
        join's and the game's loading screens, the lobby.
        After the day's dock changes (~17:15, dev phone, a 4-minute upright skirmish, the phone warm: GPU held at 348
        MHz, thermal level 6): 29.4, 30.0, 29.9 fps a minute (the first second's dip only), Lua 159-177 MB as on earlier
        days; the dev phone left clean (no scratch widget, dev file or swapped script; upright off; its own screen size).
      - [x] **publish-check after the day** (~17:25): two FAILs, neither new in kind. The upright pictures made from BAR's
        (loadpicture-upright_*, loadscreen-upright.png) fell under its "no BAR artwork" rule, which predates BAR's
        developers clearing such phone versions (2026-11-06, NOTICE.md credits them): allowed by name now. And private
        data: the dev phone's serial as the default device of tools/container-cost/measure.ps1 and trapbench.ps1 (now
        toolchain.ps1's Get-PhoneDevice, from ..\phone-device.txt), and the day's test address in StatusText and its
        test (a 10.x address reads as a home network's: RFC 5737's 198.51.100.7 in the test). publish-check -NoHistory:
        "Ready to publish"; its self test and status-text-test ALL PASS. (The history question stays Kailil's.)
      - [x] **A player who turns spectator mid-game upright** (~17:35, dev phone, a skirmish, BAR's /spectator at frame
        450 by a scratch widget, removed after): the dock went from the playing grid to the spectator's the next frame,
        laid out again at its taller size (SP.laidOut); no error. And pad-test -Share and -Chat (~17:45, the two the
        day's sweep had not run): ALL PASS.
      - [x] **Lua's 200 top-level locals** (~17:50): bardroid_portrait.lua was at 199, one short of blocking the next
        change: the profile's six locals are one table (PROF), 194 now (dev phone: the profile's lines as before,
        dock-phone-test ALL PASS). bardroid_teamstats.lua is at 200, but so is BAR's own gui_teamstats.lua (test-31836):
        the copy adds none, so a new top-level local in BAR's file would stop BAR's own widget as well as the copy;
        the room has to come from BAR's file (a note for BAR's developers), not from rewriting BAR's code inside the copy,
        which the phone's remake patches could not follow. A patch set for BAR's repository, tested by a pool swap as
        the top bar's was (docs/upstream), then the dock calls SetHidden where BAR has it. An upright skirmish on the
        dev phone the same hour, played through the dock (PINGS, COMMANDER, BASE, a windmill placed and rotated):
        no error or warning from the app's widgets in infolog.txt (the engine's "No L2 or L3 cache found on ARM" only).
      - [x] **A toggle that hides the dock**, a small button at the bottom brings it back: HIDE (spectating) folds the
        dock to a SHOW button at the bottom's middle, the game on the whole screen; a tap on it (RtsTouch's act
        dock_menu, or a click) opens the dock again. Dev phone: hidden, then shown.
      - [x] **The button for the home grid's open place** (beside PINGS): Kailil, 2026-11-12: "lets do FACTORIES for the
        button beside PINGS". Done: FACTORIES picks your next finished factory (again: the next) and puts the camera on
        it at COMMANDER's distance, the dock then on its build menu; dim while you have none (BAR's unit counts, no
        scan of your units each refresh). Candidates were
        (2026-11-12; not idle units or builders, his 11-11 call: the idle builders are in the groups row):
        1. **FACTORIES** (recommended): a tap picks your next factory and puts the camera on it, as COMMANDER cycles
           (the dock then shows its build menu to queue units). Queuing units is the most frequent errand that has no
           button upright: today it takes panning the map to each factory and tapping it.
        2. **CHAT**: opens the chat's typing box (today a three-finger double tap, which nothing on the screen shows);
           a long press, speak to chat (today a three-finger tap).
        3. **LOS VIEW**: BAR's line-of-sight overlay on and off (its L key), lit while on.
        Each fits the half-row tile as the others; none needs BAR's code. Waiting for his pick.
- [x] **The lobby's Keys window upright** (2026-11-12, dev phone): Chobby's gui_keys_panel.lua lays its six tabs
      (Keys, CTRL Keys, ALT Keys, three Legacy ones) in one row 180 pixels each; upright the row shows two and a half,
      ALT Keys cut under Close and the Legacy ones out of reach, the keyboard picture small. Done the same day:
      `bardroid_lobby_touch.lua` uprightKeys lays them upright in two rows of three as wide as the room left of Close
      (when that room is under 180 a tab), the picture under them, again whenever Chobby's resize moves the picture
      back. Dev phone upright: all six whole ("Legacy CTRL Keys" just fits), Legacy ALT Keys shows its picture,
      no errors. The picture stays small: a wide picture in a tall window, as wide as the window allows.
- [x] **The lobby's Settings, Graphics: Ingame / Menu Display Mode** (2026-11-12, dev phone upright): the tab's only
      two settings, meaningless on a phone, could a player break the picture with them? Menu Display Mode set to
      Fullscreen, then Windowed (Chobby's SetLobbyFullscreenMode 3 and 2; the engine's window attributes changed):
      the lobby stayed whole at the screen's size each time (the X server keeps a full-screen window at the screen's
      size, patch 0003), and the next start came back Borderless (springsettings.cfg Fullscreen 0, WindowBorderless 1).
      Left as they are. The Lobby tab upright fits too (the longest label just clears its checkbox).
- [x] **The phone tests after the night of 2026-11-12** (~05:50, dev phone, the build of 11ec9a2 with all that night's
      changes: the upright spectating cameras, the share list, the lobby's Replays row, the launcher's map list and
      status line): dock-phone-test, touch-phone-test, fp-save-test, lobby-phone-test, pad-test (plain, -Online, -Dgun,
      -Share, -Chat) and pace-test all pass, ~16 minutes in all. Again at ~08:15 on the build of 960b3d1 (the
      container on the phone's time zone, Save keeping the selection and saying so): all 10 pass.
- [x] **The phone tests after the evening's changes** (2026-11-10 ~21:50, dev phone; and 11-11 ~00:30 on the build
      with the lobby pointer patch, the icon's task and the updater's retry: fp-save-test, pad-test -Chat, dock-phone-test,
      lobby-phone-test all pass. The start view looked high in screenshots: measured, the start spot 190 px above the
      middle of the game above the dock, but that start is by the map's top edge and keepOnMap holds the view on the
      map (the void above it shows already); re-fitting only pushed it further that way: as meant, left as it is): pad-test, -Online, -Dgun (with
      full auto's refusal and the walk's stop), -Share, lobby-phone-test: ALL PASS. touch-phone-test: its first run's
      skirmish went quiet while loading BAR's gadgets (31 s in, no test line in 4 minutes, no GPU driver fault logged;
      its infolog overwritten by the next test); run again, ALL PASS. One-off so far, as the 11-02 opening-seconds hang.
      touch-phone-test now keeps the game's infolog and launcher.log in build\touch-phone-test\fail-<time> when it
      fails. `tools/dock-phone-test.ps1` (new): the upright dock by real taps (adb input at the dock's own rects),
      its widget finding the spots and checking: a Bot Lab placed with PLACE 2.6 s after its spot, PLACE on a blocked
      spot's note, FIRE swiped right / AUTO left, MOVE held and let go, STRAFE tapped and dragged: ALL PASS. Its first
      run hung the engine at frame 188, 6 s into the game, before the test did anything (the watchdog, no stack under
      proot): the third early-game hang (11-02 replay, 21:47 touch-phone-test); the run after it passed. Since then
      the app logs a hung engine's threads from the kernel's side at BAR's watchdog line (`HangDump`: each thread's
      name, kernel wait, system call and state as "[hang]" lines in launcher.log, once a game): the next hang says
      whether the main thread waits in the GPU driver (ioctl), on a lock (futex) or loops. Checked with the watchdog's
      words echoed by a scratch widget: 26 threads logged, the main one running. Hunted at once: six skirmish starts
      in a row on the dev phone, each to frame 1700+ in 132-148 s, no hang (two in about 20 starts that evening). pad-test
      deletes the engine screenshots its run took (after copying the ones -Share and -Chat keep): 150
      of them, 255 MB, had piled up on the dev phone since 11-07 (cleared; a run after: none left, ALL PASS).
- [x] **The lobby's pointer by touch**: hidden while fingers play the lobby, back for a mouse, keyboard or the pad
      (patch 0014: the X server's mouse events no longer show a pointer the app hid; RtsTouch.showCursor), and the
      button under the lifted finger no longer stays lit after a page swipe's overshoot (the hush clears a control lit
      again). Dev phone: three page swipes, no arrow, no lit button.
- [x] **The dock's menu times out after 1.25 s** ("make time out for the mouse controls on the bottom half 1.25
      seconds instead"; it was 7 s untouched, `MENU_SECONDS`). Dev phone: open 0.7 s after a tap, the camera pad
      again by 2 s, three taps.
- [x] **The selection row is the QUEUE button**: its right 2/3 QUEUE (the sticky Shift), its left 1/3 the "alt queue
      modifier so we can insert things in front of queue" (BAR's insert at the front). INSERT is BAR's own
      CommandInsert (a game widget: online too), whose key is Space; Space also shows unit stats, picks idle units in a
      box, splits builds and loops selections, so `bardroid_pad.lua` binds the unbound numpad* to the same action and
      the app holds it while INSERT is on (`insert 1` in bardroid_pad.txt). QUEUE and INSERT turn each other off.
      Dev phone, upright: QUEUE, MOVE, two taps (A, B queued), INSERT, MOVE, a tap: the queue C, A, B. A building
      placed with PLACE while INSERT is on goes where it fits in the queue, not first (PLACE clicks with Shift: BAR's
      Space+Shift).
- [x] **Remove-order buttons**: remove the first or the last order of the queue, "in the bottom where the unit group
      assignments are", on the right, always there while a unit with orders queued, or a factory, is picked.
      "× FIRST" and "× LAST" at the groups strip's right end. Units: BAR's Command Queue Manager (its actions bound
      to Any+insert and Any+numpad/, so QUEUE's Shift does not stop them); the dock asks the app for the key
      (bardroid_pad.txt "key <n> first|last", RtsTouch presses it). A factory: BAR's build button right-clicked for
      the last item's type (the engine takes one off the back), with Alt for the first item's (off the front).
      Dev phone, upright: the commander's three moves (one walked off) to one to none; a Bot Lab's Pawn, Rocko,
      Pawn to Pawn, Rocko to Rocko.
- [x] **A factory's order menu with the larger buttons**, as FIGHT / MOVE / PATROL for units (his message broke off
      at "Im thinking the l"; asked, 2026-11-10: "Idk. I ran out of ideas on what buttons would be big", left to us).
      A factory's FIGHT, MOVE and PATROL are where its new units go: the units' sizes (FIGHT across two rows, MOVE and
      PATROL tall), and REPEAT across after them where a commander has its D-gun. Dev phone, upright, a Bot Lab: that
      layout, REPEAT tapped Off to On. Probed (2026-11-10, the lab's own orders logged): MOVE, FIGHT and PATROL each
      arm their command and a tap on the map sets the lab's rally there, the last one replacing the one before
      (move@1225,6016, then fight@747,5665, then patrol@1653,5376).
- [x] **The factory's move state for its units**: the hold position / maneuver / roam button of a picked factory sets
      every unit that came out of it, and every one that will, to the state tapped; a tap cycles the three, a state
      left 0.3 s is applied. The same for an air factory's fly / land: every plane that came out of it, not builders.
      Units built later take the factory's state themselves (the engine's); the dock remembers each factory's units
      (UnitFromFactory) and, once its button has rested 0.3 s, gives those the factory's state (GiveOrderToUnitArray),
      with a note ("7 UNITS: MANEUVER"). Dev phone, upright, a Bot Lab's 7 Pawns: Hold to Maneuver, then Roam, all 7
      each time, one order a rest. An air plant's fly / land is BAR's own button (`apLandAt`, gadget unit_air_plants),
      not the engine's: its planes get CMD.IDLEMODE with its state. Dev phone, an Aircraft Plant's 3 fighters and a
      construction aircraft: Fly, Land, Fly reached the 3 fighters each time, the construction aircraft kept Land.
- [x] **Retreat and cover** ("It is insanely hard to micro units on mobile"): a unit under 50% health falls back;
      the commander retreats behind nearby combat units, which take fight orders to cover it at a distance safe from
      its death blast and go back to where they were once it is out; a commander that lives waits on patrol (repairs
      nearby units) until given orders again; builders very close to the commander get a repair order on it inserted
      in front of their queue, then go back to it. `bardroid_retreat.lua` (GiveOrder; the dock's home grid has AUTO
      RETREAT: ON / OFF across its fourth row, kept in LuaUI/Config/bardroid_retreat.txt). A unit that moves, under
      half health, moves 600 elmos away from the nearest enemy it sees and toward its start spot, once until it is
      above 60% again (a player who sends it back keeps it there). A commander under half moves away past its blast's
      reach (BAR's 350: 600 elmos), turned up to 90 degrees along the map's edge where the edge would stop it; the
      armed units within 900 fight on its spot (spread as they stood), and once it is there (or 20 s on) those still on
      that fight go back where they were and it patrols beside its spot; mobile builders within 350 get a repair on it
      inserted at the front. Dev phone, upright, cheats: 4-8 Cortex Cans 200 elmos from the commander, 6 Pawns and a
      construction bot by it: "retreats 600 elmos (blast 350), 6 cover, 1 repair it", the bot's first order the
      repair, hurt Pawns falling back, "out, on patrol, 3 cover back" (the cover's queues: BAR's fight puts its attacks
      in front of itself, looked past), the commander repairing on patrol; in a map corner it slid along the edge
      (before: it backed into the corner and stopped). AUTO RETREAT tapped off and on: the file and the log follow.
      Found on the way: a dock half with nothing to scroll took no taps since the empty-space pan (its press was
      "empty"): the home grid's buttons and short order lists; a tap that does not move is its button's again. And a
      new top-level local took the dock over Lua's 200 (it did not load): `tools/lua-locals.py` now checks it.
- [x] **Preset orders**: a PRESETS button with combat units picked; the whole dock shows the presets as 2 x 2
      thumbnails (four for now), closed by an X in the corner or Android's Back. Presets: repeated moves along paths
      that make units hard to hit (big zigzags); formations for several units by their types' strengths (short-ranged
      and cheap units like Ticks and Pawns at the front, long-ranged at the back; fighters in front of or escorting
      bombers and transports; artillery always at the back on fight, moving with the back while the formation moves).
      First: research the practical formations for BAR's unit types, T1 front-line mixes first, then all.
      Done so far: `bardroid_presets.lua` (layer -20: the destination's tap and Back before the dock and BAR's menus).
      PRESETS among the orders while units that move and fight are picked; the dock's whole grid then shows the presets
      2 x 2, each a drawing of what it does with its name under it, an X in the top right corner; Back closes them (BAR's
      menu stays shut). A preset tapped closes them and the map's next tap is the destination (Back or the right button
      lets it go). ZIGZAG: to the destination in turns 230 elmos apart, 170 to each side, each unit keeping its place in
      the group (drawn in to 260 of its middle). Dev phone, upright: 6 Pawns, PRESETS, ZIGZAG, a tap 900 elmos off: 4
      orders each (3 turns and the destination), the group's middle swinging right, then left on the way; Back and the X
      each closed the presets.
      The research (2026-11-10; BAR's wiki and unit pages, the Recoil engine's source): front-liners and the
      short-ranged in front (Stout, Brute, Mace, Thug, Pounder, Pawn, Grunt; range up to ~400), skirmishers, rockets and
      AA a row behind (Rocketeer, Aggravator, Lasher, Whistler; AA such as Crossbow "at the back of your army" but at 760
      range it covers the front), artillery behind by its range over the front's less 100 (Shellshocker 710: ~230);
      fighters ahead of bombers; the engine already puts footprint-2 units 64 elmos apart, ~96 against splash such as
      Janus, Pounder or Quaker; BAR has no mobile shields. **Ctrl on a move given to the selection** keeps each unit's
      place from the group's middle and holds every unit to the slowest one's speed (SelectedUnitsAI); orders given unit
      by unit (BAR's line drawing, GiveOrderToUnit) do not. So the formations form up where the units stand, facing the
      destination, and then take one Ctrl+Shift fight order as the selection (picked for a moment, the player's own
      selection back in the same call): BATTLE LINE (rows 64 apart, 80 between, every other row half a place over, 12 a
      row at most), SPREAD (96 apart, 120 between), CONCAVE (the battle line, its ends forward a quarter of its width).
      Planes are a group of their own, fighters 300 ahead of bombers and transports. The destination is drawn in so every
      unit's place is on the map. Dev phone, upright, 14 units (4 Pawns, 2 Maces, 2 Rocketeers, a Crossbow, 2
      Shellshockers, 2 fighters, a bomber): BATTLE LINE: Pawns in front, Rocketeers and the Crossbow ~80 behind, the
      Shellshockers ~230 behind, all at the slowest one's speed in that order (40 elmos a second, a Pawn makes 87); at
      the map's edge the Maces' places were off the map and they stayed (now drawn in). CONCAVE to the left: the front in
      a curve at the spot, every unit moving. Once, the engine hung on the dev phone ~1 s after the selection was emptied
      with the presets open (the watchdog, no stack); the same steps again ran on without it (as the 11-02 hang).
- [x] **The first mexes at the start**: in the game's first 5 s, the commander picked and the metal extractor chosen,
      an area mex order over the mex spots within the commander's weapon range, sent at once without confirmation
      (Kailil: it may also just fire every time; where no spot is that close it does nothing and the player places it).
      `bardroid_automex.lua`, every time: as an extractor becomes the active command with a commander picked, the free
      spots within the commander's weapon range (BAR's maxWeaponRange: the Armada commander's 300) are queued, nearest
      first, through BAR's resource spot API as BAR's Area Mex (the finder's spots; the builder's PreviewExtractorCommand,
      which leaves out built spots, its SpotHasExtractorQueued, its ApplyPreviewCmds), appended to the queue (a start's
      queued buildings stay first); with orders sent the extractor is put away and the note says "3 MEXES QUEUED", with
      none it stays for the player. Dev phone, upright: on a start whose spots were over 300 away, nothing ("0 spots in
      300 elmos"); the commander walked within 190 of three spots, the Mex tile tapped: "3 spots in 300 elmos queued",
      its queue three armmex, the dock back on its orders, the first one built. (PreviewExtractorCommand takes the
      extractor's own def id: negated, as first read from BAR's Area Mex, it found no building place for any spot.)

Added 2026-11-10 ~05:00 (with screenshots):
- [x] **LOCAL UNITS / ALL UNITS pick ALL at once**: the first tap shows the list on ALL with those units selected.
      The list stays (ALL outlined; a type still narrows it). Dev phone: six Pawns, LOCAL UNITS: 6 picked, the list on.
- [x] **The dock's menu times out after 2 s** (not 1.25), **and a drag on empty dock space pans the camera** in the
      menu too. A half with nothing to scroll pans whatever the drag starts on (RtsTouch's dockscroll lines carry the
      sideways move too), and so does the space outside the halves but for the resource bars, the selection row and
      the group buttons; the camera pad's gain. Dev phone: up and down on the list 920 elmos, sideways 780, the groups
      strip's empty part 780, each with the finger.
- [x] **The game's start popup fits upright** (a scenario's mission briefing ran off the left and over the dock).
      BAR's Mission Info is 1050 x 520 times a scale from the screen's size: upright 1152 wide on 936. The app runs a
      copy (`tools/make-missioninfo.py`, 4 patches, `bardroid_missioninfo.lua`, remade on the phone like the menus):
      no wider than the screen, its text at its size wrapping, upright in the middle of the game above the dock, laid
      out again as the dock moves; its GetInfo `replaces` BAR's. Dev phone, upright, a skirmish given a scenario's
      modoption (scenario001): the whole briefing above the dock, BAR's own "not loading (replaced by ...)";
      remake-check: the phone's remake equals the shipped copy; launch-bar-test all pass. A real scenario from the
      lobby upright (2026-11-12, dev phone offline: Tick Tock, the one with an installed map, SpeedMetal; the lobby's
      numbers are not the files' scenarioNNN): the briefing above the dock, the game paused under it; the tap that
      closed it also clicked the map (BAR closes on a press outside and lets it through) and unpicked the commander.
      Patch 5 takes a finger's closing tap (a mouse's goes on); patch 6 tells the app's chat where the briefing's tab
      is, its lines ending above it (a fifth line ran under it). Dev phone: closed by a tap, unpaused, the commander
      still picked; the top bar's Mission opens it again; remake-check all pass.
- [x] **The game-end recap and its graph fit upright** (BAR's awards, gui_awards.lua, and the graphs). The awards
      fit (centred, inside the 936 wide screen). The graphs behind their Show Graphs (and the top bar's Statistics) are
      BAR's TeamStats panel, 1100 x 610 times the screen's height over 1080: 2046 wide upright, its charts cut off on
      both sides. The app runs a copy (`tools/make-teamstats.py`, 3 patches, `bardroid_teamstats.lua`, remade on the
      phone like the menus; BAR's file is at Lua's 200 top-level locals, the patches add none): on a screen taller than
      wide the panel is the screen's width, its words at a scale that keeps a table's columns in it (BAR's over 960
      wide), and as tall as the game between BAR's top bar and the portrait dock (laid out again as the dock moves); its
      chart grid divides the panel, so the charts stand taller. Dev phone, upright: Statistics in a game, the panel
      above the dock, all 12 charts inside the screen; a game lost (the commander self-destructed), Show Graphs: the
      panel the screen's width and full height, nothing cut off. remake-check: the phone's remake of all four copies
      equals the shipped ones; the patches also apply to the laptop's BAR (test-31777).
- [x] **A metal extractor places as easily as other buildings**: PLACE on a mex spot is "very finicky" (2026-11-10).
      BAR's Extractor Snap moves a mex onto the spot nearest the pointer as its Update last saw it, and lets a click
      be only when the pointer last drew over the map; PLACE moved the pointer from where it was to the spot and
      clicked at once, so the snap used the old place (the mex went to the spot by the pointer, not the one tapped)
      or none. Now the pointer is on the spot with Shift for 150 ms before the click (`PLACE_SETTLE_MS`). Dev phone,
      upright, three taps 30-50 px beside visible metal spots, PLACE each: each mex on the snap's own target.
- [x] **PLACE's rotate and cancel at its bottom right corner**, and no "tap the map for the spot" sentence (the
      build menu copy's `layoutPanel` upright; the dock no longer prints it).
- [x] **The energy box shows BAR's wind and tide details** (its empty space), **and both boxes' numbers bigger**, the
      boxes keeping their size. One row above a thin bar: the amount about two fifths bigger, income and spending,
      storage; the energy box's right side has BAR's wind indicator (its blades turning with the wind as its top bar
      turns them, the speed, the map's range) and, on a map with water for tidal generators (BAR's own test), the
      tide's waves and speed; what does not fit beside the numbers is left out.
- [x] **The battle room upright: the selectors in a row of their own** (team size, number of teams: the
      Autobalance / BalanceMode / Preset row is crushed, its labels over its values; the space under the team lists
      stands empty). Chobby's room (gui_battle_room_window.lua, the skirmish room and a server's alike) is three
      columns: the teams (to 48 %), its buttons, selectors and states (48-67 %), the map and Start (from 67 %); upright
      the middle one was a sliver ("Update Rea", "BAR-31836-b..", "...ownload failed [fa"). bardroid_lobby_touch.lua
      lays it out again upright, once a room: the teams over the left's top half, the middle column under them as wide
      as the left (60 %), the map and Start on the right (their own OnResize re-lays their children). (Chili hands out
      a new weak link each lookup: the real objects, UnlinkSafe, to compare parents and to remember a room.) Dev phone,
      upright, offline: the skirmish room's buttons and states whole under the teams, the map larger beside them,
      Start started the game. A server's room (online: the tests never log in) is the same columns; not seen here.
      lobby-phone-test passes sideways; upright it failed on the scale and the server bar's place (it expected a
      sideways lobby at 100 %; upright starts at 135 %): the test's, not a fault. Now it holds both ways: the server
      bar where the widget stands it (upright just above the bottom buttons, `WG.BarDroidLobbyTouch.barTop()`), Start's
      steps from the scale the lobby starts at (under 115 % to 130 %, else to 100 %: sideways 100 130 100, upright 135
      100 130), "Start again" checked before the test's game loads (back from a game the upright lobby puts its 135 %
      back). Dev phone: all pass sideways and upright.
      touch-phone-test upright too: its camera checks passed, but with no BAR order menu (the dock stands in its
      place) its skip jumped six steps where five were left, past its own "done" ("did not finish in 4 minutes");
      upright it now checks the pointer on the dock answers interface, the map map. Dev phone: all pass both ways.
      pad-test and pad-test -Share upright: all passed, but the share list with 15 teammates ran from 211 to 1801 over
      the dock (0-691); it now keeps above the dock, in the middle of the game above it (rows 3-15 of 15 shown, the one
      picked in sight: 753-1865), sideways as before (66-826); the test's check counts the dock upright.
      pad-test -Dgun upright: all pass; -Online upright: all but "RB: the build menu has the pad". Upright the build menu
      copy stands down (the dock has its own grid: droid.active), so the pad's RB opens nothing there; the rest of the
      pad works. The test says SKIP for it upright.
- [x] **A factory's queue buttons upright** (2026-11-10): +1, +5, +20, -1, CLEAR, ORDERS filled three short rows of the
      half; now two rows tall each, as the big orders. Checked on the way with a probe of the factory's real queue
      (Spring.GetFactoryCommands): +20 queued 100 (it sent Shift and Ctrl, BAR's x100; Shift is 5, Ctrl 20); now Ctrl
      alone: +20 queues 20. CLEAR (right click with both: 100 off) empties it, -1 takes one. Dev phone, upright, a Bot
      Lab with cheats: 20 queued, CLEAR to none.
- [x] **The dock's sharing probed** (2026-11-10, dev phone, upright; the pad widget's teammates and give stood in
      for, one teammate ALPHA): 3 Pawns picked, TRANSFER (beside PRESETS), the picker's ALPHA in its colour: give(77,
      "units"); nothing picked, the metal box: its panel (SHARE TO ALLIES ABOVE, SEND METAL, CLOSE) over the home
      grid, SEND METAL: 10 / 25 / 50 / 100 % and ALPHA, 50 % then ALPHA: give(77, "metal", 0.5), the dock back home.
      The giving itself is pad-test -Share's.
- [x] **The home grid's buttons probed** (2026-11-10, dev phone, upright; a probe of the selection and the camera, 7
      Pawns of which 4 busy, 2 construction bots 2000 elmos off of which 1 busy, the commander): LOCAL UNITS and ALL
      UNITS pick the 7 Pawns (by design the combat units by type; the list stays until DONE, its ALL counting what
      can be picked), IDLE UNITS opens its list unpicked (only LOCAL and ALL pick at once), IDLE BUILDER goes round
      the idle builders (the commander, the far bot with the camera on it, the other bot once its move was done),
      COMMANDER picks it with the camera on it, BASE takes the camera to the start spot. All as meant.
- [x] **Spectating upright** (2026-11-10): fp-save-test passes upright and sideways; a replay upright (bench mode's
      `.bardroid-bench-replay`, a Starwatcher game recorded on the dev phone): no dock (a spectator has none), BAR's
      replay speeds down the left, the player list bottom right, a tap on it the app's spectator bar (player cams,
      Free, Follow unit, Group) at the bottom left beside it, all on the screen. ("spectator" in a 1 v 1 skirmish is a
      resignation: the awards came up; a replay is the way to see it.)
- [ ] **A gamepad upright: RB on the dock's build grid** (found 2026-11-10 by pad-test -Online upright): the pad's RB
      opens no build menu upright (the dock's grid stands in the copy's place and the pad does not drive it); building
      upright is by touch. Not asked for (Kailil plays touch upright, the pad sideways): his call whether the pad should
      step through the dock's tiles.
- [x] **The lobby's bottom buttons larger, in pages**: fewer, larger buttons a page, a swipe pages through them with a
      subtle magnetic snap (pages, not lines). 3 x 2 a page (17 buttons: 3 pages), 60 high in the lobby's larger font;
      a sideways swipe moves them with the finger (past the ends a third as far), let go they settle on the nearest page,
      a flick on the next, in 0.28 s with a small overshoot; dots under them light as the pages pass. A tap is the
      button's click. (A strip three screens wide holding them was not drawn by Chili: each button moves instead.) Dev
      phone, upright, offline lobby: page 1 to 2 by a flick, a short drag back stayed on 2, Settings tapped there opened
      Settings, a flick to page 3 (Exit last); lobby-phone-test all pass.
- [x] **The BAR splash of the first load whole upright**: zoomed out to show all of "BAR"; the picture is not tall
      enough, so its edges feathered into the same grey as the background, seamless. It is Chobby's
      MenuLoadscreens/loadscreen.png, drawn as a 16:9 picture cut to the screen's shape (api_chili.lua): upright the
      middle quarter of its width. The app's `loadscreen-upright.png` (made on the laptop from BAR's: the logo scaled
      to 80% of that quarter on the picture's own grey 22,22,22, the torn bands left out, the edges faded; NOTICE.md)
      goes there while upright (launch-bar.sh; one already there kept aside), and the engine's SplashScreenDir, which
      would stretch it over the screen, points at none meanwhile (its own logo as before). Dev phone, upright: the
      whole word, then the lobby; a start not upright: the folder gone, SplashScreenDir as it was.
- [x] **Every loading screen's logos and pictures natural on every aspect ratio, landscape and upright** (Kailil,
      2026-11-10): the engine's Recoil splash (stretched to the screen), Chobby's picture (16:9, cut to the screen),
      BAR's load screen pictures (bitmaps/loadpictures, cut to the screen: upright a narrow strip of them).
      Done: the engine's splash (`SplashPicture`: before each start Recoil's logo from the engine's own picture laid on
      its grey in a picture of the screen's shape, the game's orientation, which the engine's stretch leaves as it is;
      launch-bar.sh's SplashScreenDir by absolute path; remade only when the shape or the picture changes). Dev phone:
      1920 x 895 sideways, 895 x 1920 upright, the logo in its proportions both ways. Chobby's picture: upright above;
      sideways BAR's own cut is fine (the logo is a third of its width). BAR's load pictures upright: the app's versions
      (`tools/make-loadpictures.ps1` on the laptop from BAR's armada, cortex and the three Scavengers ones: 1080 x 2400,
      the whole picture across the width, the same enlarged, blurred and darkened above and below, its edges faded;
      NOTICE.md) under BAR's names in the write folder while upright, where the engine looks before the game (only this
      phone's drawing; not synced); a start not upright takes them away. Dev phone: upright the whole Cortex picture,
      sideways BAR's own. Sideways BAR's cut of its pictures stays (as on a wide PC screen).
- [x] **BAR's low-memory line at the top of its load screen runs off the left upright** ("... memory. Try running with
      lower settings", BAR's LuaIntro, drawn for a wide screen; seen 2026-11-10 on the dev phone, 8 GB). BAR prints it
      (machines under 11 GB) as one line centred in a band 5 % of the screen tall, sized by the screen's height. Its
      load screen runs only from the game's archive: an addon of the app's in the write folder's LuaIntro/Addons was
      not even listed (the handler's scan has no VFS mode set: archive only), and its translations load the same way,
      so as with the tips (writeLoadTips) the app covers it: Installer.writeLowRamLine puts BAR's English text
      (language/en/interface.json ui.loadScreen.lowRamWarning, colours out) in .bardroid-lowram, and GameActivity shows
      it over BAR's band, wrapped to the screen, while upright and loading on a phone BAR's own test picks (1 to 11 GB).
      Dev phone, upright (7072 MB): the sentence whole on three lines across the top over BAR's band; gone in the game.
      Its colours as BAR's: grey, "12GB memory" white (BAR's warnColor, kept as marks in .bardroid-lowram).
- [x] **The upright loading screen's tips leave out the keyboard and mouse** (2026-11-10, seen on the dev phone: "Press D
      to quickly initiate aiming"). The app's tip (BAR's own tips, writeLoadTips) shows only upright, touch play: the
      tips naming keys or the mouse (27 of BAR's 56: press, hold, CTRL+(0-9), right-click, F4, (K), ~) are left out,
      all of them if none would stay. Dev phone, upright, three starts: three of the 29 left, none about a key.
- [x] **Review of the day's automation (retreat, presets)**: a unit the player drives (ridden in first person,
      `WG.BarDroidPadFP.unit()`, or walked by the pad's D-gun sticks, `WG.BarDroidPad.modal()`) takes no retreat, cover or
      repair order (it fought the player's hand); a preset's destination tapped on the minimap is the place it shows
      there (TraceScreenRay with the minimap; it was the world behind the minimap). Dev phone, upright: the commander
      in the D-gun mode with 6 Cans on it, 100 % to 0 % and no retreat; ZIGZAG with the minimap's far corner tapped:
      10804,6383, that corner of the map; the note "ZIGZAG: TAP THE DESTINATION" shows over the map after the pick.
- [x] **The day's automation where a host forbids widgets' orders** (allowunitcontrolwidgets off; BAR's handler then
      throws on a user widget's Spring.GiveOrder*, and a widget that throws is removed): auto retreat and presets would
      each have gone at their first order, and the dock with them at a factory's state for its units. Now retreat and
      presets ask once, as first person does (a pcall'd empty order), and stand down: the home grid says "AUTO RETREAT:
      OFF IN THIS GAME" (a tap says why), PRESETS is not offered; the dock's factory-state order goes through pcall;
      auto mex needs nothing (its orders are BAR's own spot builder's, a game widget's). The lobby's warning for such a
      server now names them: "First person will not work in this game, nor auto retreat and presets". Dev phone,
      upright, a skirmish with the modoption (pad-test -Online's online-on.sh): "[bardroid-retreat] off", 3 Pawns with
      no PRESETS, the home grid's line, a Bot Lab's unit out and its move state tapped to Maneuver: no error, the dock
      stays; pad-test -Online, -Chat and lobby-phone-test all pass.
- [x] **A fight with the day's automation** (dev phone, upright, 2026-11-10): 42 units given by cheat (30 Pawns, 6
      Maces, 4 Rocketeers, 2 Shellshockers) sent with BATTLE LINE to the AI's corner by a minimap tap: the march at the
      slowest one's speed, 12 hurt units fell back in the fight, no error from the app's widgets, 57-61 fps.
- [x] **Regression run, 2026-11-10 after the day's dock work**: lobby-phone-test, touch-phone-test, pad-test and pad-test
      -Share all pass on the dev phone (pad-test once lost its game to Android's low-memory killer on the 8 GB phone,
      then passed); the runs' infologs show no error from the app's widgets.
- [x] **The groups strip works as BAR's own auto groups** (vanilla and the controller support): a unit picked and
      a group button pressed puts that unit type in the group, and every one of that type built later; holding a
      group's picture takes the assignment off. "+ NEW" is BAR's Auto Group's Alt+number
      (`WG.autogroup.addCurrentSelectionToAutogroup`: the types picked, every unit of them now and later; the engine's
      own group where that widget is off), a number some auto group holds is not offered as new, a long press on a
      group's picture takes its types out of the auto groups and its units out of the group. Dev phone: one Pawn of
      six picked, + NEW: group 1 of 6, Pawns in auto group 1; two Pawns more: 8; held: group 1 empty, no auto group.
- [x] **The dock's D-gun mode, his notes** (2026-11-10, his screenshot of it): "Have the camera follow the commander
      and keep the commander in the center of the screen"; "unit group selection and first and last row be hidden so
      the ui is shorter. And hide the commander selected bar"; "an dgun full auto mode by holding fire button then
      swiping to the right. It should have an animation associated with it and engages it"; "allow the empty Gray space
      to let me zoom up and down. Or rotate. Not panning". The selection row and the groups strip go while it lasts (the
      dock 283 X pixels shorter on the dev phone); `DG.follow` keeps the commander in the middle of the game above the
      dock; a finger on none of its parts zooms (up or down) or turns (sideways), decided by its first slide as the
      camera pad's; FIRE held shows a track to its right (chevrons, a fill from red to gold, AUTO at its end), swiped to
      the end it starts full auto (`bardroid_pad.lua` dgunAuto: the D-gun loaded and the energy there, the best enemy
      in range, a commander first, led by its speed, never through a friend; the button striped gold with AUTO, a flash,
      the world's ring pulsing with a sweep, brackets on the target); FIRE again ends it. FIRE now shoots as it lets go
      (one that came down first spent the shot's 500 energy before the swipe). Dev phone, upright: all of it, three
      enemy bots given by cheat, two D-gunned or shot, our Pawn in the path of the third spared. Then: full auto with
      user widgets' orders refused (pad-test's online rule, BAR's default online) fires through the app's click, 14
      frames after the enemies appeared; pad-test -Dgun passes; entered from far off the camera eases in once to
      COMMANDER's distance (5000 to 1321 in half a second), the zoom the player's after it; FIRE shows when it can
      fire (a thin bar along its foot, white as the D-gun reloads, amber with the word dimmed while the energy for a
      shot is short). The ease-in again on a second entry with the same commander (it was skipped: 4500 stayed; now
      4500 to 1319). Sent to the Fold7 by AirDrop as bar-droid-a6da919.apk (Download), 15:14.
- [x] **The lobby upright: its menu as pages** (2026-11-10, his screenshot of the lobby's 2 x 3 menu): "we need a
      curser selection and the first 6 buttins shoukd be multi-player, skirmish, scenarios, settings, chat, friends.
      Next page. Parties, load game, downloads, account, and you sort the rest". The pages and the swipe were there,
      their dots under Chobby's version and caching lines at the screen's foot. Now the grid takes his order by the
      buttons' words (Login in Account's place offline), then Replays and Links, the rest as Chobby has them, Exit last;
      the strip under it is taller with arrows at its ends (a tap: the next page that way, a dot: its page), the page's
      dot gold, Chobby's caching words in it while they change and its version line off upright. Dev phone, offline
      lobby: the 17 buttons in that order over 3 pages, the arrows 1 to 3 and back; lobby-phone-test passes. ("curser
      selection" read as a carousel's page selector; to ask him if he meant the pad's pointer.)
- [x] **The minimap upright was half size** (found 2026-11-10 in a screenshot): `bardroid_minimap.lua`'s half size
      until tapped is the unfolded screen's (Kailil, 2026-10-28), but it took any screen not wide for that one, so a
      phone upright (the Fold7's cover screen too) got it after 7 s: about 140x90 pixels of 1080. The unfolded screen is
      near-square both ways now; upright the minimap stays BAR's size (dev phone: 275x185; later the same day Kailil
      asked for it small upright, as tall as the top bar's row: the item below). The layout editor had the
      same test for its settings per screen shape: upright shared the unfolded screen's ("square"); it is its own
      ("tall") now, started from a copy of the inner screen's (dev phone: the minimap sized upright saved under tall
      only, kept on the next start).
- [x] **Upright: the chat a full row, the minimap small beside the top bar's buttons** (Kailil, 2026-11-10: "make chat
      take up the entire row instead of sharing the row with the map. Shrink the map by default to fit at the same row
      as the buttons at the top ... comes down to a comfortable vertical space ... text size a little smaller"). The
      minimap waits as tall as BAR's top bar (a tap opens it, 7 s untouched small again); the chat is a box across the
      screen under that row, its text 0.87 of its size sideways, under the minimap only while it is small (opened it
      lies over the chat's corner). Dev phone: minimap 145 x 100 beside the 85-tall bar, the chat under them across.
- [x] **An offline game pauses while the phone is locked** (2026-11-10, for a native feel): a game with nobody else in
      it (a skirmish against AIs, a replay) pauses while the game screen is hidden (locked, another app over it) and
      runs again 0.8 s after it is back; online it runs on, and the floating window (Home) keeps it in sight and
      running. GameActivity writes LuaUI/Config/bardroid_app.txt, bardroid_touch.lua pauses from GameFrame and resumes
      from Update. Dev phone: locked, paused at frame 8425; woken, running from 8426. Again in an upright skirmish
      (2026-11-10 evening): the screen off at frame 114, held there 8 s, back 0.4 s after it came on and 30 frames a
      second after (911 at 27 s); also when the screen went off during the start countdown (paused at frame 35).
      Nothing of the app's in the infolog's errors or warnings (BAR's own: its intro's deprecated `AdvSky`, its dev
      widgets that do not load in a released game). The dock's CAMERA PAD label lost its "tap to use the menu" hint
      (Kailil's no-hint-text rule for the dock).
- [x] **The D-gun's full auto kept to the host's rules** (2026-11-10, code review): where a host forbids user widgets'
      orders (BAR's "Allow Custom 'Unit Control' Widgets" off) full auto fell back to the app's clicks, aiming and
      firing on its own around the very rule meant to stop that. Now it fires only by a given order and does not switch
      on there ("AUTO D-GUN: THIS HOST FORBIDS IT"), as AUTO RETREAT stands down; the D-gun by hand still works. pad-test
      -Dgun (orders forbidden) checks it: ALL PASS. A skirmish (orders allowed), an enemy Pawn placed in range after
      full auto was on: the shot given 3 frames later, the Pawn dead 20 frames after.
- [x] **The lobby's pages snappy, a small swipe turns one** (Kailil, 2026-11-10, on the Fold7: "too slow of an
      animation. It should be super snappy and fast and smooth ... A small swipe quickly moves the page"): the strip goes
      1.5 times the finger's way, a drag of a twentieth of the width (or a 200 px/s flick) turns the page that way, a
      long one to the page it reached, and it settles in 0.15 s with a slight overshoot (was 0.28 s; half the width or
      a 600 flick). Dev phone: swipes of 70 and 60 pixels each turned a page (2, 3, back to 2). (The "about 200 frames a
      second, about 30 in the settle" measured then was the dev phone's frame cap left at 0 by benchmark work; at the
      players' default cap of 30 the lobby draws 30 a second and the settle has about 5 frames: fast, less smooth.
      The dev phone is back on 30, 2026-11-11: pad-test and dock-phone-test pass there too.)
- [x] **The upright lobby's grid back after a popup** (2026-11-10, dev phone, offline lobby): with Chobby's login dialog
      cancelled the grid was logged "back" but not seen, the strip under the news empty: Chili puts a control shown
      again last among its parent's, drawn under Chobby's full-screen background. It is brought to the front as it comes
      back. Dev phone: the dialog cancelled, the grid's first page and its strip there 3 s later.
- [x] **Speak to chat stops listening when the game screen goes away** (2026-11-10, code review): locked or another
      app in front, the recognizer listened on and what was said next, perhaps by someone else in the room, went to the
      game's chat (online a public one). GameActivity.onStop now ends it (VoiceChat.close, "voice chat: stopped
      listening" in launcher.log). Checked on the dev phone without the microphone (the no-live-mic rule): a skirmish
      through a screen off and on, the away pause and the game after it as before; the listening itself is for the
      live-mic test above.
- [x] **The D-gun mode's whole reach on the screen upright**: entering it, the camera zooms out as far as the D-gun's
      ring and a target at its edge need inside the game above the dock (at COMMANDER's distance the ring touched both
      sides of the narrow screen and the target at its side was cut off). Dev phone: ring and target inside, a margin on
      each side.
- [x] **The launcher's map for Play vs AI picked, not typed** (2026-11-10, for a native feel): a tap on the field
      lists the maps installed (the engine's archive cache), typing narrows them; any other name still downloads at
      the start. Dev phone: its ten maps listed.
- [x] **The lobby's login dialog on the Fold7 unfolded upright** (near-square, dev phone at wm size 1080x1198): taller
      than the room above the grid, its Register / Login and Cancel lay under the grid. While one of Chobby's modal
      popups is open the grid is hidden now. Found on the way: the pad's D-pad in the lobby lost its place after every
      step at any scale but 100 % (Chobby's Spring.GetMouseState answers in scaled units); it reads the engine's
      pixels now (Spring.Orig.GetMouseState). The dock's other views near-square fit (home grid, a Bot Lab picked).
- [x] **The dock on the Fold7 unfolded upright** (the dev phone's display set near-square, `adb shell wm size
      1080x1198`, reset after; a way to try that screen without the Fold7): its orders half shows three rows, and the
      two-row FIGHT, MOVE and PATROL cut MOVE and PATROL in half at its foot; D-gun mode's MOVE and AIM fell off the
      screen. The big orders are one row there now (two where four rows or more show), the factory queue's likewise,
      the sticks sit between their words and FIRE. The tall phone's dock unchanged. Also checked upright (tall): the
      lobby's Scenarios (a scenario's page and Start Scenario), Load Game, Downloads, Replays fit.
- [x] **The lobby's Settings upright without its sliders and dropdown boxes** (found 2026-11-10): the controls had
      their size, but their picture was the one drawn before they had it. Upright, when 20 or more controls of the
      content come or go (a screen or a tab opened) it is drawn again, twice; dev phone: every slider and dropdown
      there on Settings' first open, its Graphics tab too.
- [x] **Chobby's notes over the lobby's page strip upright** (found 2026-11-10): its Chotify notes ("Download
      Failed", downloads, invites) stacked from the screen's foot over the strip's right arrow; upright they stack from
      above the grid (and the server bar) now, through WG.Chotify's _Realign. Checked upright on the dev phone: the
      Quit dialog, the offline login dialog and BAR's awards fit as they are.
- [ ] **BAR's Settings upright is wider than the screen** (found 2026-11-10, dev phone, the top bar's Settings): its
      scale is the screen's height over 1080, so upright it is ~1770 pixels wide on 936 and its values column is cut
      off. Kailil, 2026-11-10: "Just fix the setting issue. Remember I am creating the official bar android port that I
      and the devs will be supporting officially". The change to BAR's `gui_options.lua` (its scale by the width too)
      is made and tested: the dev phone's pool file swapped for the patched one, Settings upright whole (tabs and every
      value), then BAR's file put back (md5 checked). The same scale is in five more of BAR's windows (Game info,
      Widget Selector, TeamStats, Keybinds, Changelog): one patch for all six, `docs/upstream/bar-windows-upright.patch`
      (Game info and the Widget Selector also tested upright on the dev phone the same way), written up in
      `docs/upstream/bar-windows-upright.md`; players get it with the BAR release that has it. (It cannot ship in the
      app: a copy would lose Settings' widget toggles to the user widgets' sandbox, and BAR's files are in the archive
      checksum.) Left: BAR merging it (Kailil and the devs); then a taller layout for upright screens (their text is
      small at the landscape shape).
- [ ] **BAR's top bar: a 4-digit amount runs into its storage number** (found 2026-11-12, dev phone sideways, a
      replay started from the lobby's Replays tab): `gui_top_bar.lua` centres the current amount on its bar
      (`barArea[1] + barWidth / 2`, `height / 2.5 * widgetScale`) and right-aligns the smaller storage number at the
      bar's end (`barArea[3]`); at the app's interface scale 2.0 sideways the bar is short for its font, and "1000"
      touches "1000" (any amount of four digits or more, so most of a game). The change is made and tested:
      `docs/upstream/bar-topbar-amount.patch` (the amount centred unless four digits would reach the storage number,
      then just left of it; set at layout, so the redraw area follows), `bar-topbar-amount.md`. Dev phone, a 1v1
      replay of the current release sideways (an October replay runs its own older BAR, untouched by a pool swap):
      "1000" and "1000" apart, both whole; BAR's file put back (md5 checked). Left: BAR merging it.
      The same run: the lobby's flow to a replay and back (Replays, Start, the top bar's Lobby, Return to Battle, Leave
      Battle, the engine's reload into the lobby) without errors; the lobby's Lua state carries through (Rapid Pool
      Cache stays stopped, the Replays row stays fixed); the pointer from the in-game tap shows until the next finger.
- [ ] **BAR's pregame texts upright** (found 2026-11-12, dev phone, an 8v8 replay's draft pregame spectated upright):
      `map_start_position_suggestions.lua`'s tutorial ("Recommended start positions are the circles ...", shown until
      it has run once, or with BAR's tutorial notes on) sizes its font by the screen's height (vsy / 1440) and wraps at
      100 characters, so upright its lines are ~1,500 pixels on 936 and run off both edges; at 61 % of the height it
      lies on `gui_game_type_info.lua`'s "Victory condition: ..." (55 % in draft games), the two texts over each
      other. Without draft the victory line sits at 19 % of the height, under the upright dock. The change is made and
      tested: `docs/upstream/bar-pregame-upright.patch` (the tutorial wrapped to the screen's width too, the victory
      line at least 7.5 % of the height above its anchor), written up in `bar-pregame-upright.md`. Dev phone, the 8v8
      replay's draft pregame upright with both pool files swapped: the victory line whole above the tutorial, the
      tutorial inside the screen; BAR's files put back (md5s checked). On the way: the engine reads a pool file only
      up to the size BAR's package lists, so a longer patched file was cut short ("unexpected symbol near '<eof>'");
      a pool swap test needs the patched code at the original's byte size (comment lines dropped, spaces after), as
      the earlier patches' tests did (checked: their scripts made same-size copies); now in `docs/upstream/README.md`.
      Left: BAR merging it (Kailil and the devs). The non-draft line under the dock stays (the dock is the app's).
- [ ] **The upright load screen's picture** (2026-11-10, his screenshot with a box drawn on BAR's picture): "add
      generative fill and zoom in. All we need to see is the full view of the commander and the pawn to the left and
      the large titan to the right". The zoom is done (`tools/make-loadpictures.ps1` `$ZOOM`: cortex.jpg 18-77 % of
      its width across the screen; dev phone: the three whole on the load screen); above and below it for now its own
      sky and ground mirrored and softened. Left: the generative fill itself, a fill (inpainting) model on the laptop
      (AI Studio's models were removed after 7 idle days; MOSS-Image draws from words, it does not fill), run while
      the GPU is free (Monster Hunter Wilds had it at 95 % that afternoon); a download needs his yes.
- [x] **Gradle 10** (found 2026-11-13, `--warning-mode all`; the wrapper is pinned at 9.8.2, nothing breaks now):
      Termux:X11's build files use the space-assignment syntax Gradle 10 removes (`termux-x11/shell-loader/stub/
      build.gradle` lines 3 and 6, `termux-x11/lorie/build.gradle` 33 and 42-44) and start a process at configuration
      time (`lorie/version.gradle` line 2, an error in Gradle 11); the Android Gradle plugin's own
      Configuration.setVisible goes with an AGP update. When the wrapper moves: a `patches/00xx` for the two
      Termux:X11 files (`propName = value`; the version through `providers.exec`), and AGP raised with it. The app's
      own build files have none. Android lint the same night: 0 errors (two Android 10 calls guarded, df46f52), the
      launcher's fields labelled for TalkBack. Done the same night: `patches/0015-gradle10-syntax.patch` (both files
      `propName = value` throughout, the git calls through `providers.exec` with the root as their folder: the version
      line still `from BAR Droid <commit>`); `--warning-mode all` now names only AGP's own setVisible. Dev phone: built,
      installed, pace-test ALL PASS.
- [x] **Kailil's notes of 2026-11-13 morning** (after a 34-minute game on the Fold7, 30.1 fps to 445 units), in order:
      FACTORIES "should let me cycle through factories. Only after I dont press the factories button after .75 seconds
      does the bottom ui switch to show the selected factory screen": each press the camera on the next factory, picked
      once the button rests 0.75 s (nothing else picked meanwhile; L.factoryPick). The order buttons' state lights "In
      vanilla, red is always on the left. Then green on the right. And yellow in the middle": one light per state along
      the bottom, the one it is in lit (first red, second yellow, or green with two, the rest green), the others dark,
      as BAR's order menu. "Allow insert and queue to be toggled on at the same time. It should engage the hold shift
      and alt vanilla behavior": both on, Shift and Alt held (the pad file's "alt 1", RtsTouch altHeld; no CommandInsert
      key then), and "remove queue and insert toggle if the unit is not selected": both off once nothing is picked.
      "Lets officially make one finger pan universal instead of it sometimes being selection": with the dock's menu open
      and nothing picked a drag selected; it pans now, and a tap, then a drag selects (the dock's box or circle, its
      corner held at the dock's top); a drag with mobile units picked still draws their path. Dev phone upright: two
      factories given, FACTORIES twice, the camera on each, the second picked after the pause, its screen up; the lights
      (Repeat Off, Hold pos, Low Priority red on the left; Fire at will, Factory Guard green on the right); QUEUE and
      INSERT lit together ("queue 1 insert 0 alt 1"), both off after the selection emptied; dock-phone-test's new
      check (a drag with the menu open and nothing picked: the camera 101 elmos on, nothing picked) and its box and circle
      selections now by a tap and a drag: ALL PASS.
      Later that morning, sideways on the dev phone (two factories given): HOME, FACTORIES three times quickly: BOT LAB
      (1 OF 2), VEHICLE PLANT (2 OF 2), the Vehicle Plant picked after the pause, its ten vehicles in the dock; no errors
      in infolog, 29.8 fps. The wait itself was not to be seen: a gold bar along FACTORIES' foot (where a state's
      lights go) now runs out over the 0.75 s; screenshot: the bar part run out, then the Bot Lab picked;
      dock-phone-test ALL PASS. (A tap that lands just after the pause hits the factory screen's INSERT, as the dock
      has changed under it: the bar shows when that is about to happen.)
- [x] **One finger pans with units picked too; hold, then drag for their path** (Kailil, 2026-11-13, asked whether a
      drag with units picked should pan, paths by press-and-hold then drag: "Pan, hold for paths"). The dock's `draw`
      line is now on only with MOVE, FIGHT, PATROL or ATTACK pressed, or a preset armed (its aim takes the press); with
      units merely picked a drag pans, and RtsTouch's long press (450 ms, BAR's right button down) then a drag is BAR's
      own path or formation line. 2026-11-11's exception (a picked unit with a building queued pans) is the rule now:
      `idleB.buildBusy` gone. dock-phone-test: a new check (the six Pawns picked, a drag: the camera 114 elmos on, no
      moves), its path into the dock now drawn by a hold, then a drag (5 moves, let go at the dock's top edge), the
      STRAFE preset's drag unchanged: ALL PASS. Sideways on the dev phone with the commander picked: a drag panned, no
      order; held, then dragged: its path, the waypoints drawn. Launcher texts, README and CHANGELOG updated.
      Found on the way (dev phone upright): a dock button tapped (BASE), then a sideways drag from it within the double
      tap time, started BAR's box selection inside the dock, its filters over the grid; the tap-then-drag selection
      starts from the game only now (77ccdd9; the same again: no `dock_select_start`, the home grid stays).
      The next run: touch-phone-test and lobby-phone-test ALL PASS on that build (the dev phone without a network
      that afternoon: the lobby's manifest and skill downloads failed as they should, the bridge's "no connection";
      LuaMenu's "Missing GetInfo()" lines are Chobby's own libraries). The groups row's FIRST and LAST got a cross
      larger than the word (a6afa1a; it was a speck at the word's size). The run after: pad-test and pad-test -Share
      ALL PASS; their screenshots showed the pad's reticle (the ring in the screen's middle) on the share list's middle
      row, over a teammate's name: not drawn while the list is open now (bardroid_pad.lua; -Share again ALL PASS, the
      ring gone from its screenshots).
      Then: pad-test -Chat ALL PASS; the upright lobby and its offline login dialog looked right ("Battle, Started" in
      the chat box is BAR's own message text, shown as BAR sends it). Sideways, the floating D-gun mode's two FIRE
      buttons stood a third of their height above the sticks' middles (left from when MOVE and AIM were printed under
      the sticks): level with them now (the dock file: sticks and FIREs at y 765). Dev phone: the right FIRE fired
      ("D-GUN FIRED", the reload bars on both), its swipe to the middle turned full auto on (AUTO, "AIM: AUTO").
      Then a fight on the dev phone upright (14 of my units picked, 12 enemy Grunts given beside them): AUTO RETREAT
      sent four hurt units back, the dock kept its selection, no errors in infolog, 29.3 fps. BAR's message commas
      ("Battle, Started", "Enemy Units, Detected") are in BAR's own language/en/tips.json. The selection row's CAMERA
      PAD sat below the count line it shares ("14 units, 10 of this type"): on its baseline now.
      Then the unfolded Fold7's shapes on the dev phone (wm size 1198x1080 and 1080x1198): sideways the floating D-gun
      mode fits (sticks and FIREs level, y 912; the X at the band's top left), upright FACTORIES' bar and the factory
      screen fine. Found: with a factory picked the groups row's x FIRST and x LAST showed with its build queue empty
      (they act on that queue, removeOrder): shown now only while the factory has something queued. Dev phone: a Bot
      Lab picked, nothing queued: no buttons; a bot queued: both; x LAST: the bot gone, the buttons too.
      Next: with the camera pad up (the menu closed) a tap on metal or energy only opened the menu, a second one their
      panel, though the launcher says "A tap on metal or energy opens their sliders" and the home buttons, the groups
      and the build options act on the first tap (Kailil, 2026-11-12): the bars are a "live" rect now (not while
      spectating). Dev phone upright, the menu timed out first: metal's panel (its share slider) on one tap, energy's
      (convert and share) likewise; dock-phone-test ALL PASS.
      The run after found nothing to fix: the dock's TRANSFER / SEND picker read through (no teammate in a skirmish to
      try it on; P.give answers an empty selection and a teammate gone); logcat during a sideways skirmish with
      FACTORIES, a factory's FIGHT path and a pan: the app's own processes logged only the known lines (Adreno's
      profile lookup, Termux:X11's request log, app_process's boot image notes); a Bot Lab with nothing queued showed no
      x FIRST / x LAST sideways either. Then pad-test -Dgun ALL PASS, fp-save-test all pass, and an AI-vs-AI
      skirmish spectated upright: the spectator's dock (NO PLAYER CAMS dimmed with its arrows, FOLLOW UNIT, FREE CAM and
      FULL VIEW lit) and TEAMS (CLOSE, both teams in their colours, the watched one gold) as they should be.
      Then QUEUE and INSERT together by touch upright (a scratch widget logging the commander's queue and the keys):
      both lit, Alt and Shift held; a wind turbine picked, a spot, PLACE: queued; a spot on the ridge dimmed PLACE (the
      game's blueprint amber, nothing sent); a flat spot, PLACE: the second turbine queued behind the first.
      Then the sideways dock moved to the left (its arrow): BAR's "D-Gun" tooltip came up over open map at the bottom
      right, where the dock had been. The order menu copy is not drawn while the dock is up (and takes no press), but
      its hover pass still ran there: tooltips and BAR's plain pointer. A make-ordermenu.py patch skips it while the
      menu is not shown (regenerated from the dev phone's BAR file; remake-check: the phone's remake equals it). Also
      the arrow acts on its first tap now (with the camera pad up it only opened the menu). Dev phone: one tap, the
      dock on the left, no tooltip over the map; one tap, back on the right; pad-test ALL PASS.
      The same check for the build menu copy (its place the bottom left, open map while the dock is on the right): its
      DrawScreen returns before its hover pass while the dock is up (droid.active), and on the dev phone the pointer
      resting there twice showed no tooltip.
      Then BAR's Statistics (the top bar's; the app's TeamStats copy) sideways: the panel, centred at its landscape
      size, ran down into the dock, its bottom row of graphs and the dock's bars and tabs drawn through each other. A
      make-teamstats.py patch: sideways with the dock up the panel goes between the dock's top and BAR's top bar, a
      size smaller where it needs to be (upright unchanged). Regenerated from the dev phone's BAR file; remake-check:
      all four remakes equal the shipped copies. Dev phone: sideways the panel whole above the dock; upright as before.
      BAR's Settings sideways did the same (its Environment rows under the dock's bars and tabs), and it is BAR's own
      file, not a copy. So the dock steps aside while one of BAR's big windows is open (Settings, Game info, Keybinds,
      Changelog, the Widget Selector: their WG isvisible): not drawn, "dock none" for RtsTouch, no presses, and BAR's
      own panels kept hidden; back when the window closes (SP.windowOpen). Dev phone sideways: Settings whole, a drag
      where the dock had been scrolled it; closed, the dock back; dock-phone-test ALL PASS. (BAR's minimap stays in the
      dock's middle slot meanwhile; the Quit dialog fits above the dock as it is.) Upright the same: Settings open, the
      dock aside (Settings itself still wider than the screen there, the item above for BAR); closed, the dock back.
      The game's end sideways (Quit, Resign): the dock gone, BAR's Awards whole in the middle, "Leaving the game in 3 s:
      tap the screen to stay longer" in the chat box (its last lines touch the Awards title for those seconds; kept, as
      they carry that notice), then the engine's exit 0 and the launcher back, no errors in infolog. The lobby sideways
      (offline): the login dialog whole, then the menu column with its page strip and the Welcome page as they should be.
      The whole sweep on the day's last build (the dock stepping aside, the copies' patches, pan with units picked):
      dock-phone-test, touch-phone-test, fp-save-test, lobby-phone-test, pad-test (plain, -Online, -Dgun, -Share,
      -Chat) and pace-test all pass, about 18 minutes.
- [x] **The layout editor with the dock up** (2026-11-13, dev phone sideways, `/hud` typed): it outlined "Unit info"
      over the open map at the bottom left, a panel not drawn while the dock shows the selection (bardroid_info.lua's
      standDown). Its rect is none while it stands down now: the editor shows Chat, Minimap, Player list and the top
      bar only. Dev phone: the same, no Unit info outline.
- [x] **Kailil's Fold7 game of 2026-11-13 ~09:00** (read at 17:50, once the laptop's Tailscale reached it again):
      about 15 minutes, 29.8-30.1 fps every minute up to 152 units, the slowest frame 219 ms at the start then under
      75 ms; no error from the app's widgets. Two lines that are not the app's: Chobby's "A Player Joined You" has no
      English text (i18n), liblobby's REMOVESCRIPTTAGS pattern. The day's builds went on at 17:45 (Wireless debugging
      on a new port, found by a port scan).
- [ ] **The orders on the first tap too? (asked 2026-11-13)** With the camera pad up the build options, INSERT and
      QUEUE, the home buttons, the groups, metal and energy, the tabs and the swap arrow act on the first tap (Kailil,
      2026-11-12, and the runs after); FIGHT, MOVE, PATROL, D-Gun and the states still take one tap to open the menu,
      then theirs (dev phone upright: D-Gun's first tap only opened the menu). Making them live too leaves little of
      the dock as a camera pad with units picked (one finger on the game pans anyway since 2026-11-13). His call.
- [x] **Placing: one square, BAR's own** (Kailil, 2026-11-13, his screenshot of a wind turbine being dragged: "that
      green square ... is acting as the actual placement target when I confirm my placement ... I want only where the
      transparent windmill with the squares under it to be what I see ... Remove the extra square thing that the mod
      is producing"): while a finger dragged a building RtsTouch moved the X pointer (BAR's blueprint) and sent the
      widget the same steps for its spot ("nudge"), from a start read off the place file, a screen position the
      camera could have left since; the two ran apart and PLACE built at the app's green square. Now the drag sends
      the pointer's own place ("spotto": the spot the ground under the pointer, kept over the sky), and a tap's spot
      puts the pointer on its build square (rounded apart they stood a square from each other). The app's square is
      drawn only where the pointer cannot be (on the dock), as before. Dev phone (a scratch widget comparing the
      spot's build square with the pointer's each frame): after a tap the same at once (was a square apart for 1.5 s),
      a drag after a camera pan the same each move (a frame behind at most); dock-phone-test ALL PASS. Installed on
      the Fold7 (05:12).
- [x] **The D-gun mode sideways floats over the game** (Kailil, 2026-11-13, his screenshot of the band: "Don't do the
      half screen ui for the dgun mode. Instead do floating buttons with fire on both sides and remove the map. So there
      will be no Grey ui bottom half when in dgun mode on landscape"): no band, no minimap (BAR's minimap given a
      pixel's frame in the corner, L.dgFloat); MOVE and AIM low in the bottom corners, a FIRE on each stick's inner side
      (the dock file's "fire" and "fire2"), X at the band's top left. Each FIRE's swipe runs towards the screen's middle
      and turns full auto on, or off while it is on (RtsTouch: dgunTurnOff; the track from the FIRE held, its word
      AUTO or FIRE). The band's place stays the mode's for the fingers (elsewhere in it: zoom or turn). Upright
      unchanged. Dev phone sideways: no band or map, the left FIRE's swipe to the middle turned full auto on (both
      FIREs AUTO, AIM: AUTO), the right one's turned it off; dock-phone-test (upright, FIRE's swipes too) ALL PASS.
      Installed on the Fold7 (04:07). With the band gone BAR's own HUD at the bottom right (the player list, its
      clock and music lines, Idle Builders, Unit Groups) shows under AIM: user widgets cannot switch BAR's widgets
      off, and BAR's widget handler's HideInterface takes every click while it hides, where the D-gun mode fires and
      moves by the app's clicks in games that forbid widgets' orders; Kailil, the same night: "Nevermind to the
      hide". Left as it is.
- [x] **A preset's repeat outlived it** (found 2026-11-13 reviewing bardroid_presets.lua): once a group is there, its
      side to side is two fights on Repeat; the Repeat stayed on after the player's next order, so a path drawn or a
      patrol given those units later ran round and round (BAR does that only with Repeat set by hand). Now the
      player's own next order to a unit going side to side (a move, fight, attack, build, stop, ...; not a state such
      as its fire state) turns its Repeat off (widget:UnitCommand; the sway's own orders known by their spots), and a
      queued one comes after the fights in its queue. Dev phone: dock-phone-test's new check, the path drawn to the
      Pawns on the preset's repeat: their repeat off, all six (on, all six, just before); ALL PASS.

### Blockers
- [x] **Public icon.** The project's own icon (`res/drawable/ic_fg.xml`, a unit marker in a ring); Kailil's icon
      lives in `C:\Tools\BARANDROID\personal\res` and is added to his builds only (`local.properties`:
      `bardroid.personalRes`); `-PbardroidPublic` or no such folder: the public icon.
- [ ] **App name.** The app is called "Beyond All Reason". For a public download, Kailil decides (perhaps with BAR's
      team): keep it, or "BAR Droid" with BAR named in the description. Recommended: "BAR Droid" while it is
      unofficial, so it is never taken for the official app it hopes to lead to.
- [x] **LICENSE** (GPL-3.0 text, as README already said) at the top; NOTICE.md keeps the third-party parts.
      **Kailil:** HANDOFF had the file as the author's to add; confirm GPL-3.0-or-later (or `git revert c942753`).
- [x] **Personal data out of tracked files.** Phone address, serial and Wi-Fi notes in `CLAUDE.local.md`
      (untracked, read by Claude Code beside CLAUDE.md); `tools\phone-bench.ps1` finds the phone through
      `-Device`, `BARDROID_DEVICE`, `..\phone-device.txt` or the one device adb lists (toolchain.ps1
      `Get-PhoneDevice`).
- [x] **Release signing.** `Build APK.bat phone release` signs with a keystore named in `local.properties`
      (`bardroid.keystore`, passwords from the environment), never committed; without one it stops and says so.
      `versionName`/`versionCode` from one place (`gradle.properties`), the APK named with the version; release
      builds always have the public icon. Tested with a throwaway key. **Kailil:** make the real key once
      (docs/BUILDING.md "Releasing") and keep it safe. With no updates planned it signs the one APK; whoever takes
      the project on can be given it to update that install, or ship under their own key and app ID.
- [x] **A publish check** (`tools/publish-check.ps1 [-Apk <release.apk>]`): fails on pictures outside the allowed
      places, private data (the terms in `..\worklog-redact.txt`, the phone, home-network addresses, profile paths,
      e-mail addresses), keys and logins, files over 50 MB, a missing LICENSE, a version without a CHANGELOG entry,
      an APK with Kailil's icon or the debug key, and reports what old commits still hold. Run before every release.
- [ ] **History.** The icon and the personal data are in old commits. Kailil decides: publish a fresh history
      (one commit; the effort record stays in docs/WORKLOG.md and docs/HISTORY.md) or rewrite this one
      (`git filter-repo`) to drop them. Either way `tools/publish-check.ps1` runs over what goes out. The commits
      also name Kailil's e-mail address (the check's NOTE): GitHub's noreply address for what goes out, or keep it.
      Recommended for a hand-off: the fresh history (one commit by the noreply address; nothing to rewrite or keep in
      step afterwards).

### For players
- [x] README rewritten for players first: what works (lobby, online, skirmish, spectating, gamepad, keyboard and
      mouse), which phones, download from Releases, install, first start (4 GB from BAR's servers), touch controls,
      known limits, where the logs are, how to report a problem. Developers' material moved to docs/BUILDING.md.
- [ ] Screenshots for the README (the touch bar while spectating, 1st person, the lobby), from the phone or
      `tools/ui-screenshot.ps1`: Kailil picks; screenshots of the game only, no other BAR artwork. Candidates from the
      dev phone (2026-11-02, not tracked): `build/readme-candidates/` (placing a building by touch, the touch HUD, the
      lobby's Skirmish screens, the launcher, an army on the map, spectating a replay with the touch bar, 1st person).
      Added 2026-11-08: the pad's share list giving metal (`9-`, its teammates the test's stand-ins), speak to chat
      listening (`10-`) and today's launcher (`5b-`). Added 2026-11-10, upright: placing with PLACE (`11-`), the D-gun
      mode on full auto with its sonar (`12-`), the presets (`13-`), aiming STRAFE (`14-`), the lobby's pages (`15-`),
      the orders after ALL UNITS (`16-`). Added 2026-11-11, spectating upright with the dock: a unit followed in Mid
      (`17-`), TEAMS by BAR's names (`18-`), unfolded: following in Close (`19-`), Shoulder (`20-`); Shoulder on the
      tall screen (`21-`). Added 2026-11-12, after that night's camera fixes upright: spectating in 1st person, the
      ground ahead (`22-`); Shoulder with its camera further back (the commander whole and smaller, among its base),
      tall (`23-`) and unfolded (`24-`), beside `20-` and `21-`; the share list giving energy (`25-`). Added 2026-11-12
      evening, the touch dock sideways (layout A): the commander picked (`26-`), a building placed (`27-`), the
      unfolded Fold7's shape (`28-`), its D-gun mode (`29-`), a factory's queue (`30-`); and the lobby sideways, its
      one column of buttons (`31-`).
- [x] Spectating a replay on the dev phone (2026-11-02): the touch bar came up from the player list, but the first tap on
      "Follow unit" followed nothing. The bar is laid out again every 0.25 s and moves while BAR's player list opens
      beside it, so the button found at the release was a new table (or another button) and the tap was dropped; a
      later tap, with the list open, worked. `bardroid_spectate.lua` now acts when the finger lifts inside the button it
      pressed. On the dev phone the first tap on "Follow unit" followed a Pawn (the bar turned to the camera presets).
- [x] In that replay a tap on "1st person" (the bar's left end) changed nothing, and some first taps on "Follow unit"
      too. Probe widgets at 13 layers found the press taken at layer -4: BAR's player list (AdvPlayersList), which
      takes some presses far from where it draws (its own rects; the tap went through on a second try). The bar is
      drawn over everything, but its widget is at 999999, after the list. `bardroid_players.lua` (-5, just before the
      list) now hands a press on a bar button to the bar (`WG.BarDroidSpectate.barPress`, its release with it). On the
      dev phone: "Follow unit", then "1st person" on their first taps, the camera in 1st person. fp-save-test: 4 of 4.
- [x] Kailil's call: Escape and Android 17's keyboard capture (dev phone, 2026-11-03). Decided (Kailil, 2026-11-03:
      "2"): keep the capture; the notice stays on each Escape. README's keyboard section says so for players (a short
      press is Escape; a held one closes the game). adb's `input keyevent --longpress KEYCODE_ESCAPE` left the game
      open (not a held key's timing); a virtual USB keyboard through Android's `uinput` (a register line with keys
      1-58, Escape down, 3 s, up) closed it: Android removed the game's task, and the app stopped the game ("game
      removed from recent apps: closing"). README says so. Each Escape in a game shows
      Android's notice "Long press Esc key to close this app" at the bottom of the screen for a few seconds (BAR's
      Escape cancels, deselects and opens the menu: a keyboard player presses it often), and by that notice a long
      press closes the app. It comes from Android's keyboard capture, which the app turns on so Android's own shortcuts
      (Alt+Tab, Meta and its combinations, Ctrl+Space ...) reach the game (`KeyboardShortcuts`, Kailil 2026-10-27:
      "i want android to not hijack its inputs"): posted by Android's KeyGestureController before the app sees the
      key, so no app code can hide it. Checked: with the launcher's "Keyboard shortcuts go to the game" off, and with a
      test build that kept only Samsung's Meta key request, no notice, and Escape still reached BAR (the selection
      went). Seen with adb's keys; a real keyboard is likely the same. Choose: keep the capture (the notice stays), or
      drop Android's capture and keep Samsung's Meta key request (One UI's and DeX's Meta shortcuts still go to the
      game; Android's own, such as Alt+Tab, act again), or leave it to the setting (off: neither).
- [ ] Kailil's online game on the Fold7 (2026-11-02, 22:07-22:31, Ascendancy, 8 players, unfolded; "super laggy. I
      had to leave the game. And when attempting to leave, the game crashed anyways"). His phone's logs: 30 fps for the
      first 11 minutes (up to 778 units); from 22:19 Android's thermal status 3 (severe), from 22:24 the GPU held at its
      lowest clock (160 of 1200 MHz, thermal level 14) and the CPU near 1 GHz, 1000-1160 units: 10-25 fps, the last
      minute 9.4. Free memory 650-950 MB the whole late game (engine 1.0-1.6 GB, swap 6-7 GB free), and at 22:31:46,
      as he left, Android's low-memory killer ended the app (ApplicationExitInfo reason 3, LOW_MEMORY; also at 21:57
      in his game before). Options, Kailil's call: a lower render resolution by itself when the phone reports severe
      heat (the frame cap holds, the picture softer), and a lighter memory set for big online games. Leaving checked
      on the dev phone (2026-11-03, a lobby skirmish played to defeat, BAR's Awards, Leave): the game's 2 GB of GPU
      memory freed at once, 2.6 GB available through the engine's reload into the lobby, back on the Skirmish screen;
      so it is the late game's memory that leaves no room, not the leaving itself. (On the way: BAR's pregame panel at
      the folded screen's interface scale 2.0 sets "Pick your faction" over its own instruction line and runs the
      faction cards' names off the screen's bottom; picking, placing and Ready all work by touch. The same in BAR's
      own game, as online: BAR's Factionpicker sizes its panel and names for a taller screen (height 0.14 x the
      interface scale; at 2.0 on 938 lines the names are wider than their cards) and the pregame's hint line sits on
      its title; neither widget takes a size or place from another, so it stays as BAR draws it.) The minute's
      `[perf]` line now has the GPU driver's memory (`/proc/meminfo` GpuTotal): a 1v1 skirmish's start on the dev phone
      reads "engine 749 MB, GPU 2060 MB", so the GPU's textures and buffers are most of the game's memory. Its parts
      (pace's BARDROID_TEX_LOG summed, dev phone): the engine's two projectile atlases 345 MB (8176x6056 and
      6616x6152, past the low-memory mode's atlas cap: the engine's own), the screen's buffers ~200 MB, and ~570 unit
      pictures 137 MB, loaded in every game's first seconds by BAR's "Cache Icons". That widget is now off on phones
      (`launch-bar.sh`): GPU memory in a skirmish 2.08 GB a minute in where it was 2.52 GB, the start "12 8 10 31 27"
      fps where it was "2 4 5 5 5 4", the build menus' pictures as before (each loads when first shown).
      BAR's GUI Shader (the blur behind its panels, 4 screen-size textures, ~30 MB) measured with the phone benchmark,
      warm (thermal status 1): Draw 24.97 and 25.74 ms a frame with it, 26.37 without; Sim 52-54 ms (the prime CPU at
      864 MHz). It costs nothing measurable: it stays.
- [ ] A replay on the dev phone hung in its opening seconds (2026-11-02 22:32, frame -1): 21 lines of Mesa's
      "flush_submit_list: submit failed -1 (Resource deadlock avoided)", then BAR's watchdog ("Hang detection
      triggered", the main thread). Once in many replays and games tonight; 9 scratch widgets were loaded. Its
      launcher.log is kept on the dev phone as `files/logs/hang-2026-11-02.log`. Watch for it again; if it repeats,
      a report for lfdevs' Mesa (KGSL submit) with that log. Not seen again: 2026-11-03 19:11-21:44, 31 starts on the
      dev phone (28 skirmishes, 2 replays, the lobby), no hang, no crash, no low-memory exit (every exit a test's own
      stop). **It repeated**: 2026-11-04 (a replay fast-forwarded on a hot phone, after ~40 s of "GPU fence wasn't
      signalled within 100 ms") and 2026-11-05 05:46 (a replay's opening seconds again, frame -1, a cool phone, the GPU
      20% busy); all three in replays, none in the day's skirmishes and online games. The report is drafted in
      `docs/research/mesa-kgsl-submit-deadlock.md` (setup, the three times, the questions) for Kailil to post or not;
      `tools/engine-sim/replay-memory.ps1` (engine branch) now ends a run at the watchdog's line.
      A fourth, the first in a skirmish: 2026-11-05 19:52, `pad-test.ps1 -Online` (BAR's game, frame 741, a minute in,
      the virtual pad just giving orders), the same Mesa lines, then the watchdog; the test said "did not finish". The
      first with UBWC off (launch-bar.sh's new default, ~10 starts since 18:56); before, 1 in the 68 run logs kept
      since 2026-11-01. Too few to tell whether UBWC off makes it likelier: count it. The same test right after: ALL PASS.
      Count at 21:00: ~16 game starts with UBWC off since 18:56, that one hang.
      The player's side of it (2026-11-05 21:25): the picture stayed frozen with the engine alive, until the app was
      closed by hand. `DriverWatch` (GameService reads every engine line) now closes the game once the driver's
      refusal is followed by BAR's watchdog (30 s with the main thread stuck; either alone closes nothing), and the
      launcher says what happened in amber under "Ready" (not "error (137)", nor the low-memory note a killed engine
      would get). `tools/status-text-test`: 4 cases; dev phone: a scratch widget echoing the two lines (removed after):
      the game closed at frame 210, the note shown. Checked on a real one too: the 05:46 hang's kept launcher.log holds
      both kinds of line (13 of the driver's, then 21 of the watchdog's), so the app's reading of the engine's output
      sees them, not only infolog.txt.
      Again 2026-11-09 06:43: plain `pad-test.ps1` (a skirmish, frame 776, 19 of the driver's lines, the watchdog);
      DriverWatch closed the game as built, and the test said "did not finish", first put down to the virtual pad.
      1 in the 24 engine starts of that launcher.log (2026-11-08 14:08 to 11-09 07:13). pad-test now names the fault
      when it ends a run (it counts launcher.log's "GPU driver refused" lines), so it is not taken for a controls bug.
      Again 2026-11-09 11:14: `touch-phone-test.ps1` (a skirmish, frame 104, 5 s after loading, right after another
      session's 13-minute benchmark: GPU 615 MHz at thermal level 2, 96 % busy, 59 C); the test named it, the rerun
      passed. A frozen game also turns the pad into the lobby's mouse 5 s later (`RtsTouch.gameWidgetRunning`: the
      widget's hover file goes stale), harmless as DriverWatch closes the game. touch-phone-test now names the fault
      as pad-test does; the report draft's "only in replays" corrected (three of the six were skirmishes).
      Again 2026-11-09 15:54 and 16:37, both portrait games (the second: frame 147, 2 s after a scratch widget changed
      the selection), both soon after the portrait dock began drawing into a texture (gl.R2tHelper: an FBO the
      dock renders into several times a second), against none in the 18 starts of the day before it. Tested, not the
      texture: springsettings `bardroid_portrait_tex = 2` (the texture drawn again every frame) in 4 portrait games of
      2.5 minutes with the selection changing every 1.5 s (~18 000 renders into it), and one game as shipped: no fault.
      Count 2026-11-11 20:54 to 11-12 00:05 (the dev phone's launcher.log and launcher.old.log): 21 games loaded
      (skirmishes landscape and upright, spectated AI games, both screen shapes, the first-frames starts), none of the
      driver's refusal or BAR's watchdog; 2 ended by Android for low memory (the 8 GB phone, both at a start).
      Count 2026-11-12 02:28 to 06:00 (both launcher logs): 32 engine starts (skirmishes landscape and upright, two of
      14 minutes, spectated AI games, replays from the launcher and from the lobby, the 8v8 replay, the lobby, GL
      check, the full test sweep), no "[hang]" line, none of the driver's refusal (the watchdog's lines all its
      routine thread registrations), no low-memory end.
      Again 2026-11-12 21:25 (an upright dock skirmish under test): the driver's refusal, then the watchdog;
      DriverWatch closed the game as built ("engine exited (137)", the launcher's note). Count 2026-11-12 23:58 to
      11-13 02:20 (both launcher logs): 24 engine starts (idle skirmishes upright and sideways of 4-6 minutes, the
      dock tests, the full sweep of 10 phone tests, the lobby), none of the driver's refusal, no hang; 1 low-memory end,
      01:27 at a skirmish's loading (Skirmish AIs, the 8 GB phone; its run right after loaded and played).
      Again 2026-11-13 06:50:21 (plain `pad-test.ps1` in the full sweep, after the Windows update): the driver's
      refusal, DriverWatch closed the game, the test named the fault; the rerun ALL PASS, the sweep's nine others too.
      26 engine starts in the dev phone's two logs then.
- [ ] The dev phone reset itself (2026-11-03, the 33rd game start of the evening, a plain skirmish): launcher.log ends
      at 21:52:24, four seconds after "Player Phone finished loading and is now ingame" (its last `[perf]`: thermal 0,
      GPU 295 of 615 MHz, 52 C), with no error; adb shell commands hung, the phone left USB, and came back at ~21:57
      with uptime 100 s. Android's dropbox holds only the boot loader's log (`SYSTEM_LAST_KMSG_..._KP`):
      `PonReason.HARD_RESET = 1`, reboot reason 0x4, the usual sign of a watchdog after a full freeze; the kernel's
      last lines are not readable without root. The phone had run games back to back for hours (an 8 GB phone in the
      low-memory mode). Watch for it again: if it repeats, note what ran, and whether the replay
      hang above came first. Wi-Fi adb and the dark screen restored with `tools\devphone.ps1 connect` / `dark`. A
      skirmish right after it ran normally: loaded in 60 s, 28.2 fps its first minute (the load's stutter) then 30,
      memory available 744 MB, but the phone still hot (53 C on the GPU's sensor, its cap at 295 of 615 MHz, thermal
      level 7): hours of back-to-back games keep it near its limits, so the next runs give it pauses.
- [x] A review of the info panel's feature view (2026-11-03): its text is rebuilt every 0.25 s, and a wreck's
      "Reclaim" figure changes every frame while it is reclaimed, each new text a new recording of the panel (~27 ms
      on the phone): up to 4 a second. A feature's text is rebuilt once a second now (units keep 0.25 s). Dev phone,
      after a pause for its heat: the feature view as before ("San Pedro", "Reclaim 100"), no error.
- [x] v0.8.5's order tooltips by touch (the controller game) named the keyboard key in front ("5 - Set a prioritized
      target ..."), which the app's copy leaves out for fingers. The tooltip wrapper in `bardroid_touch.lua` takes
      out BAR's gold key and its " - " (`ui.orderMenu.hotkeyTooltip`) while the fingers are the input. Dev phone: Set
      Target's tooltip without "5 -"; a mouse keeps the key.
- [x] The build menu's unit pictures in stripes (dev phone, 2026-11-03 evening, BAR's game, 2 of 5 skirmish starts):
      every picture of the first page drawn in vertical stripes about 16 of its pixels wide, every other one empty
      (the panel showing through), while the menu's figures, icons and words over them were whole. It stayed (0:33
      and 0:48 of game time) until something drew the menu again (a page change, a building picked: whole at once).
      The engine loads a picture when it is first shown, on the main thread (`UnitDrawerData.cpp` SetUnitDefImage);
      BAR's Cache Icons, which loaded all of them in a game's first seconds, is off on phones since 2026-11-02
      (`launch-bar.sh`). Tried: the menu drawn again a few frames after its first drawing (the copy's warm-up kept,
      `make-buildmenu.py`): the stripes still came, at 1 of 2 starts, so it was taken out. Both striped starts loaded
      faster (game time ~0:33 when the clean ones showed ~0:07 at the same moment). A test build that logged each
      drawing: BAR draws the menu into a new texture at frame 0 (before "finished loading") and again at frame 31-42
      (~1.4 s), then only on a change. Made to draw into a new texture every 1.5 s, with screenshots every ~2 s: the
      stripes at 0:01 (the start's stutter, 10 fps), every drawing from ~1.6 s on whole. So the copy now draws the
      menu once more at 5 s of game time when its last drawing came before (`make-buildmenu.py`, `droid.settled`);
      logged on the dev phone: frames 0, 31 and 150, the menu whole. Why the first second's drawings break is not
      known (the gaps are fully transparent: perhaps the new texture's zeros from `BARDROID_TEX_ZERO` landing after
      the pictures; the words drawn last are whole).
- [x] Build range circles (Kailil, 2026-11-03, after a full online game on the Fold7: "In late game when I have tons of
      con turrets, it lags the game when I build anything because it displays literally all of them at the same time.
      Can we change it to display only the closest 10 or something?"). The engine draws them itself
      (`GuiHandler.cpp` DrawMapStuff: during a build command, one ground circle per immobile builder of the team and
      per selected builder, on the map and the minimap, each its own drawing over 40 ground heights), with no Lua
      switch; but it skips a circle whose colour is see-through (`glExtra.cpp`), and the colour (`rangeBuild`) is a
      client-side command colour, as BAR itself hides `rangeExtract` and `rangeAttack`. `bardroid_buildrange.lua`:
      while a building is picked `rangeBuild` is see-through, and the widget draws the 10 builders nearest the
      building (BAR's colour, a third of its alpha as the engine) and the picked building's own range. Dev phone, BAR's
      game, 150 construction turrets given in a skirmish, a solar collector picked, frame cap off, 20 s each: engine
      circles 26.1 and 26.2 fps, the 10 nearest 87.3 and 84.8 fps (~27 ms a frame was the circles). Installed on the
      Fold7 (the app was not running). Reviewed after (2026-11-04): the engine calls UnitTaken before the unit
      changes team, so a turret given away stayed in the widget's list (now the callins' team arguments decide);
      and BAR's cursor widget loads its whole colour file again on a cursor change, which would bring the engine's
      circles back for the rest of a pick (now the see-through colour is set every frame while a building is
      picked, one line for the engine to read). Dev phone, 150 turrets, the colour file's line loaded once
      mid-pick: 79.3 fps before, 97.3 after (the engine's circles held it at 26).
- [x] Watching an older replay switched the app's menu copies off for good (found on the engine branch's sync
      checks, 2026-11-04): a replay plays the BAR release it was recorded with, whose widgets the copies (made for
      today's) do not fit (`RegisterUnitCommand` missing in test-31465); BAR removed both copies, and launch-bar.sh,
      which gives way to BAR's own menus after a copy BAR removed in the last game, did so for every game after
      (no pad RB, no PLACE, no shape strip) until BAR's next update. A removal in a replay (`PreGame::ReadDataFromDemo`
      in that run's infolog) no longer counts (`copy_removed`); the mark says "game" now, and an older mark, which a
      replay may have written, no longer counts (a copy that really fails is marked again in its next game).
      `launch-bar-test.sh`: the replay case for both menus and the old mark, all pass. Dev phone, BAR's game: with
      both old marks still there the copies ran again; then the 2026-10-01 replay (BAR removed both copies in it) and a
      skirmish right after: the app's copies ran (launch-bar 17:43:02), the marks untouched.
- [x] The engine on every CPU (found on the engine branch, 2026-11-04, Kailil's go: "Move the latest version onto my
      zfold 7 for me to test"): the dev phone (Samsung) starts the engine on a CPU mask without its fastest core (0x3f,
      0x5f, ...; set from outside as it starts; Android's own shell may not change it, the app's may), and its busy
      threads sat where the big cluster stayed idle. launch-bar.sh's `widen_engine` gives every engine thread not on
      every CPU all of them, every 3 s (read from its status first: nothing to do on a phone that allows all 8).
      BAR's benchmark on the hot dev phone, alternating, the official engine: game speed x0.53/0.54/0.53 as started,
      x0.67/0.70/0.64 with every CPU (+26 %). Dev phone after the change: the engine's 26 threads on 0-7, no errors.
      Installed on the Fold7 for Kailil's test (whether his Fold7 starts the engine on a narrower mask too is open:
      the 2026-10-27 research saw all 8 there). Reviewed after: "every CPU" was a fixed `ff`, which a phone with
      another number of CPUs or a smaller cpuset never matches (a `taskset` for each of ~26 threads every 3 s for the
      whole game) and which would take CPUs away on one with more than 8; now it is the launch shell's own mask (the
      app's cpuset), and a thread that exits mid-scan no longer writes "No such file" into launcher.log (5 such lines
      in the dev phone's log). `launch-bar-test.sh`: the mask read, all pass; dev phone: the 26 threads on `ff`.
- [x] The launcher's two warnings in amber: "N of the app's adjustments to BAR did not apply: see the log" and the
      last run's exit note (low memory, a crash) stood in the same plain text as the routine status lines
      (`LauncherActivity.refresh`, `Updater.MISSES`). Dev phone: the miss line amber across both its wrapped lines.
- [x] Order labels of two words that their button's width shrank well below the others ("Place Blueprint" a size
      smaller than every other order) go on two lines at up to the others' size where the button is tall enough
      (`make-ordermenu.py`; the phone's remake gives the copy byte for byte). Dev phone: "Place / Blueprint" at the
      other orders' size.
- [x] The whole picture in vertical stripes in a game's first frames (dev phone, 2026-11-04, BAR's game, game time
      0:00, the engine just loaded: map, minimap, build and order menus, unit picture, every ~16 px; some text whole),
      clean by 0:25. The same pattern as the build menu's stuck stripes (fixed by drawing it again at 5 s) and the
      white columns in a pad-test screenshot: likely one GPU cause at a game's start, the heaviest frames (a frame
      shown or sampled before the GPU finished it: Adreno draws in tiles). Watch: if the order menu or another
      panel drawn into its own texture keeps stripes after the start, give it the build menu's redraw.
      2026-11-05: BAR's idle builders button (its own widget, drawn into its own texture) showed its commander
      picture in black columns at ~1:40 in 2 of 4 controller-game skirmishes, back to back on a hot dev phone (one
      at 82 C); the same picture in the app's info panel whole. Black blocks 16 px wide fit Adreno's compressed
      render targets (UBWC) read with stale flags, so 6 more skirmishes with 20 s pauses, 3 with `FD_MESA_DEBUG=noubwc`
      in dev-env.sh and 3 without: all 6 whole. Not reproduced cool: heat-linked, the UBWC lead neither confirmed nor
      ruled out. Next time it shows: the same pair on a hot phone.
      2026-11-05 ~17:00, the controller game, the dev phone warm (battery 33-36 C), screenshots at ~2:00: it showed
      at 1:14 (the build menu's pictures and BAR's idle builders picture both in columns), then 6 skirmishes
      alternating `FD_MESA_DEBUG=noubwc` and none (now `tools\stripes-test.ps1`): the idle builders
      picture in black columns in 1 of 3 normal starts, all 3 `noubwc` starts whole; the tool's own test pair after,
      both whole. With the earlier three each: columns in 2 of 9 normal starts (the build menu's 30 s redraw cleared
      its own), 0 of 7 with UBWC off. Leaning to
      UBWC, too few starts to be sure. BAR's idle builders widget draws its picture into its texture again every
      ~0.33 s, so its columns were not a stale first drawing (as the build menu's were): the drawing into that texture
      kept failing while UBWC was on. What `noubwc` costs (late 8v8, game seconds 1210-1330, gcc-wfe2, profiler on,
      the dev phone at 72-77 C, ABBA): GPU passes 18.9 and 16.5 ms a frame without UBWC, 17.7 with (the other UBWC
      run throttled hard, its simulation 68 ms a frame: left out); 20.1 and 22.6 fps against 17.2; GPU busy 66-95 %
      and the GPU driver's memory ~2.08 GB either way. No cost seen, so launch-bar.sh now sets
      `FD_MESA_DEBUG=noubwc` for Freedreno (added to a developer's own flags; `unset FD_MESA_DEBUG` in dev-env.sh
      brings UBWC back; launcher.log says "Freedreno flags: ..."); `tools\launch-bar-test.sh` 4 cases. Dev phone:
      a pair with the new default, both whole (the tally 0 of 8 without UBWC, 2 of 10 with); 20:47, two more pairs,
      all four whole: 0 of 10 without, 2 of 12 with. Open until the
      first-frames stripes above are seen gone too (not reproduced on purpose so far).
      2026-11-12 ~00:05, the first frames looked at on purpose: 6 skirmishes from the launcher, 4 with the default (UBWC
      off) and 2 with UBWC on, screenshots ~1, ~6 and ~14 s after "finished loading" (game time 0:00-0:15): all 18
      whole, the build menu whole at full size in the first second of both kinds. With the day's other starts none
      striped since UBWC went off by default: closed; reopen with a screenshot if it shows again.
- [x] The build menu's stripes past the 5 s redraw (dev phone, 2026-11-04 evening, the controller game, hot phone):
      still striped at frames 1110, 1803 and 5060, whole at once when a page change drew it again. Measured on the
      screenshot: the empty columns every ~28 screen pixels straight across the cells' borders, so the drawing into
      the menu's texture broke, not the pictures. The copy now also draws an unchanged menu again every 30 s of game
      time (`droid.redraw`, one texture drawing each time). Dev phone: the menu whole at frame 1801, no errors.
- [x] Free memory while BAR loads (Kailil, 2026-11-04: "It should appear while bar is loading as a button under the bar
      logo"): Android lets no app force-stop others (since Android 14 not even their background processes), and One
      UI's Memory screen needs `READ_SEARCH_INDEXABLES`; Device care's page (`com.samsung.android.sm.ACTION_DASHBOARD`,
      a `<queries>` entry) opens from the app, Memory one tap away. The button sits a sixth of the screen below the
      middle (under the engine's logo, over BAR's loading picture) from the engine's start until "finished loading"
      or the lobby's widget (`GameService.loading`); opened with `FLAG_ACTIVITY_NO_USER_ACTION`, as a plain tap made
      Termux:X11 shrink the game to its floating window and Back went to the launcher. Dev phone: shown on the engine's
      splash and the loading picture, Device care opens, Back returns to the loading game, gone in the game. Clean now
      itself while a game loads (2026-11-12, dev phone, a skirmish loading its map): Memory's list of what it stops
      (with View more) has Play Store, Wi-Fi Provisioner, Find My Mobile and Multi Connectivity, not the game (a
      foreground service); after Clean now the engine and the app kept their process ids, Back twice returned to the
      game, which had finished loading meanwhile and went on. The launcher's low-memory note now
      says how: Recents, Close all; or Device care, Memory, Clean now.
- [x] The app's builder queue widget removed in older replays (found in the dev phone's launcher.log, 2026-11-04):
      a replay plays its own BAR release, and test-31465's `WG.BuilderQueueApi` had no `OnBuildCommandTeamChanged`
      ("attempt to call field ... (a nil value)" in Update, BAR removed `bardroid_queue.lua` for that game: no
      queued buildings drawn, as launch-bar.sh switches BAR's own off). It now takes each callback only where the
      release has it and waits for the ones it needs. Dev phone, the 2026-10-01 replay: no error past frame 9,299
      (before: removed at 1:03).
- [x] The launcher's log on a wide screen: in two columns (the Fold7 unfolded) the left column stood half empty under
      the device lines, while the log came last under every setting; it now sits there (`fitLayout`), and last in the
      settings on a narrow screen as before. Dev phone at 1968x2184 and folded.
- [x] The launcher at the unfolded Fold7's size (the dev phone at 1968x2184, two columns): "Benchmark" cut to
      "Benchmar", too wide for its button even at the row's smallest size. `LauncherActivity.fitRow` now lets a
      button's side padding give way (down to 5 dp, 1 dp inside its shape) before the words get smaller; the style's
      padding comes back on a wider screen. Dev phone: whole at 1968x2184, the folded size unchanged. Checks this run
      on the dev phone: lobby-phone-test and touch-phone-test, all pass.
- [x] The picked building's option in the build menu (BAR's game, fingers): only BAR's slightly lighter cell said which
      building PLACE would build. Now the gold line the pad's focus has (`droid.drawPicked`, `droid.goldLine`), 4% of
      the cell wide (the focus's 2 px read as a hairline), also over BAR's hover drawing: a finger's tap leaves the
      pointer on the cell it picked, and BAR draws that cell anew on top (the first try was hidden under it). Gold is
      the app's "on": QUEUE, the picked shape. Dev phone: the frame round the wind turbine with the pointer on it and
      after a tap elsewhere; no errors; remake-check equal. (In the controller game v0.8.5's own menu shows for fingers,
      as designed: PLACE works there, the shape strip is the app's copy's.)
- [x] BAR's update to test-31820 (2026-11-04) changed its Order menu: an order's tooltip now gets a keyboard line
      ("Tap L quickly: 1x Fire at will, 2x Hold fire, ...", "Press Z Z for area mex"; `tapHotkeyLine`), and the line
      the copy's touch patch hooked into moved, so the phone could not make the copy again: the old copy ran, and the
      launcher said "1 of the app's adjustments to BAR did not apply". `make-ordermenu.py` hooks the new line and
      leaves out the tap line too for fingers; the copy made again from the phone's release (the phone's own remake,
      as `BuildMenuPatches` does, gives it byte for byte). Dev phone: no Android-layer miss at start, Fire at will's
      tooltip by touch without key or tap line. The build menu's patches still apply to test-31820. pad-test after
      the build-ranges widget: all pass. (The laptop's BAR is older, test-31777: `make-ordermenu.py --check` there
      fails until it updates.)
- [x] The launcher's settings fade out at the top and bottom of their scrolling area (a line cut in half under the
      buttons' divider read as a glitch; dev phone, 2026-11-03).
- [x] The build menu's shape strip (ONE, LINE, GRID, BORDER): the picked shape's pale gold words on its gold read
      worst of the four; now white words on a deeper gold (dev phone, 2026-11-03: ONE and LINE picked, by touch).
- [x] One screenshot of the dev phone during pad-test (2026-11-03 02:44, the "FIRST PERSON OFF" note, a skirmish at
      7 fps) showed white ragged columns about 20 px wide across the whole picture, the interface too (kept as
      `build/white-columns-2026-11-03.png`, not tracked): a frame shown before it was drawn, or a torn screenshot.
      1 of 22 shots in that run; none in 222 back-to-back shots of the next. HANDOFF's "watch for flicker" of the
      explicit Present fence covers it; if anyone sees a white flash in play, this is the picture to compare.
      2026-11-08, pad-test -Share: one engine screenshot lacked the upper part of the interface (the share list's
      panel, tabs and first rows, BAR's minimap) while the rest was drawn; the same run again drew all. No columns
      this time; 1 in ~30 shots that day.
      2026-11-11 to 11-12: ~150 adb screenshots of running games on the dev phone (upright and landscape, both screen
      shapes, spectating, the 18 first-frames shots) and pad-test -Share's 8 engine screenshots in two runs: none torn,
      none with columns. Closed as a watch; reopen with the picture if a white flash or columns show again.
- [x] **A rolling map storage limit** (Kailil, 2026-11-11: "a rolling map download size limit ... rotate downloaded
      maps"; then "Move forward with that. At the max map size to 3gb"). What grows is maps (20 to 150 MB each); BAR's
      rapid pool stays ~2.26 GB across releases (they share files: 25 MB of the dev phone's pool was only for older
      releases). `MapStore`: launcher setting Map storage (3 GB by default; 5 GB, no limit: a 10 GB choice made "No limit" wrap
      on the unfolded Fold7's width); before an engine
      starts (`GameService`), the maps played longest ago are deleted (with their `.md5.gz`) until the rest fit, never
      the one played last nor the launcher's Play vs AI map; last uses from the engine's `[CAS::GASCB] Archive file=`
      line as a game loads (`/data` is noatime), `.bardroid-maps-used`; a map never seen counts from its download.
      Dev phone: a planted 1.6 GB "map" dated 2025 with the limit at 2 GB: removed before the skirmish ("[maps] over
      2048 MB of maps: removed zz_bardroid_prune_test.sd7 (1600 MB, downloaded 2025-01-01)"), the real maps kept, the
      skirmish's map recorded; the setting saves and shows "Now: 607 MB in 10 maps".
- [x] **BAR's Rapid Pool Cache off in the lobby: measured** (2026-11-11; Kailil asked to keep it if it means fewer
      stutters in game: "The lobby being laggy is okay if it means less stutters in game"). It is no shader cache
      (Mesa's own shader cache stays, in the container's ~/.cache/mesa_shader_cache): it reads all of BAR's rapid pool
      so the files are in memory for the game's load. Dev phone, a landscape skirmish from the launcher, BAR's pool,
      maps and packages dropped from the page cache first (cold: GNU dd iflag=nocache in the container) or read into
      it (warm: what the Rapid Pool Cache does), twice each: load to "finished loading" cold 47.0 and 53.3 s, warm
      59.1 and 64.0 s; the first minute cold 29.1 / 28.9 fps with its slowest frame 393 / 402 ms, warm 28.7 / 29.3
      fps, 1169 / 583 ms; the second minute alike (30 fps, slowest ~55-65 ms). On an 8 GB phone the pre-read files
      take the memory the load needs: slower and a worse first minute, no smoother after. Off stays (launch-bar.sh's
      once-off setting and bardroid_lobby_touch.lua); the Fold7's 12 GB not measured. Kailil, 2026-11-12, asked
      whether it stays off or goes back on: "off". Settled.
- [ ] Playing with no connection (dev phone, 2026-11-08, Wi-Fi and data off; Kailil's road trip): the launcher's Play vs
      AI starts at once on what is installed (the update check gives up on the first "Unable to resolve host"), and
      the lobby opens "Offline" with its Skirmish screens. But the lobby's quick skirmish picks from four maps a mode
      (BAR's `singleplayerquickskirmish.lua`) and cannot download a missing one: the Fold7 had all of 1v1's and 2v2's,
      1 of 3v3's (Eye of Horus), 1 of Scavengers' and Raptors' (All That Glitters), and not Special Creek 1.0, whose
      download the Skirmish screen also tried. Kailil's call: fetch them ahead (the Fold7 was asked), or the app
      fetches the quick skirmish's maps with the game on Wi-Fi, for players who go offline. (2026-11-11: with no
      network at all a map or game download now fails at once in `LobbyBridge`; the lobby's four asks each started
      proot and pr-downloader before, about a second apiece, to fail on the CDN's name.)
- [x] A map download in the container failed on the dev phone ("Could not resolve host", 2026-11-08 ~14:20): not the
      container's DNS (1.1.1.1, 8.8.8.8, `Installer`). The download ran through `run-as` with the app closed, and
      Android cuts an app's network while it is in the background (no activity shown, no foreground service): a ping
      to 8.8.8.8 as the app failed then, worked with the launcher open, failed again 12 s after it went to the
      background. With the launcher open the container resolved the CDN and `setup-container.sh map "Eye Of Horus
      1.7.1"` fetched it (56 MB, 13 s). The app's own downloads run with the game screen or GameService's foreground
      service up, so they keep the network. For tools: run as the app only with the app in front. A game sent to the
      background (Home) keeps it too: GameService is a foreground service (specialUse), the app's ping worked 15 s
      and 60 s after Home, the game still running: an online game survives a look at another app.

### For developers (BAR's devs first)
- [x] docs/BUILDING.md: toolchain, builds, phone install, the laptop checks, releasing; the Linux equivalents where
      they exist.
- [x] docs/ARCHITECTURE.md: CLAUDE.md's architecture and key files written for people; CLAUDE.md keeps the AI
      assistant's working rules and points there.
- [x] CONTRIBUTING.md: online play must keep working (no engine changes, no modrules, no synced changes), never
      bundle BAR content, the checks to run, upstream reports need an accepted issue and disclose AI assistance.
- [x] CHANGELOG.md, from docs/HISTORY.md and the commit log, one section per version.
- [x] `.github/ISSUE_TEMPLATE/bug.md` (phone, Android version, "Share logs" output) and a PR template.
- [x] docs/HELP-WANTED.md for whoever takes it on: how it runs and what that costs, the engine-side performance
      measurements (what helped, what did not, what only an engine or game change can do), touch controls (what
      works, what is not solved), the other open points.
- [x] `.github/workflows/build.yml`: the phone APK on Linux (Gradle and the committed prebuilts; Termux:X11 fetched
      and patched, `-PbardroidPublic`) and the luacheck lint; the APK as an artifact. **Untested until pushed**: the
      first run on GitHub may need fixes. `gradlew` and `tools/fetch-termux-x11.sh` are executable in git now.
      Reviewed 2026-10-28: the native build needs nothing beyond the runner image (Termux:X11's own workflow builds
      the same code on ubuntu-latest with nothing installed: bison, gcc, patch, Python are there); actions at the
      versions Termux:X11's workflow uses now (checkout v7, setup-java v6, upload-artifact v7), the Gradle wrapper
      jar validated before it runs (a pull request could swap it), the token read-only.
- [x] The Java checks (downloader, settings merge, updater rollback) in CI: `tools/java-checks.sh` (passes under
      the portable Git's sh on the laptop).

### Hardening and overhead (the spectator tools first)
- [x] Measure what `bardroid_spectate.lua` costs per frame (`tools/spectate-test.ps1 -Cost`: off, the bar, following,
      group, 1st person) and cut it: the bar into a display list (0.43 → 0.06 ms, 54 → 4 KB a frame), 1st person
      without per-frame tables (0 KB); HISTORY.md "Overnight". Left as they are (measured or rare): `GetVisibleUnits`
      per tap, the group refresh twice a second, the camera state read each frame while following.
- [x] `bardroid_touch.lua`: measured before at ~0.08 ms a frame (HISTORY.md, 2026-10-27 afternoon);
      `GetConfigFloat` per pinch frame is one engine call, left as it is.
- [x] On the phone: a replay smoke run of the new build (x1.00, ~30 fps, 905 units, no widget errors). The widget on
      against off was not run: its cost (0.01-0.1 ms a frame) is far below the benchmark's run-to-run noise.
      `WorkerThreadCount` 7 (the research batch's one lead) checked in three alternating pairs: no gain on a hot
      phone, 4 stays (HISTORY.md "Overnight").
- [x] **`tools/spectate-test.ps1`: 4 FAILED on 2026-11-11 ~19:50** (Kailil, 2026-11-12, asked whether it may run
      again on the laptop: "no". Closed on the phone checks below; the tool stays for a run he allows.) (run on the laptop by mistake, without Kailil's
      yes; laptop BAR waits for it): double tap on the ground did not stop following, double tap on a unit did not
      follow it, 1st person's two checks (mode 0, facing 0.42-0.43). That run had 94faec7 (the follow's shift above the
      upright dock, which on the laptop's landscape screen has no dock and only keeps the point on the map) and
      aa0f0e3; not known whether the failures came before them. Next laptop run with his yes: run it on 81ac048 and on
      the newest, and fix what fails. On the dev phone by real taps (2026-11-12, an AI-vs-AI skirmish spectated
      upright, a scratch widget reading what is followed): a double tap on the ground stopped following, a double tap
      on the unit followed before followed it again, 1st person turned the engine's first-person camera on (mode 0); so
      on the phone the three behave. Found on the way: upright, 1st person looked into the sky (the game above the
      dock shows the view's upper part); now turned down by dockTilt as Shoulder is, the horizon in the game's upper
      third, the ground ahead in sight. fp-save-test passes. And Shoulder upright showed a commander taller than the
      game above the dock, its head cut off (the game is that share of the view's height): its camera now goes back by
      that share (dockShare), the commander whole at 1080x2316 and at 1080x1198. The pad's own 1st person
      (`bardroid_padfp.lua`) has the same sky upright, but its crosshair and aim are at the screen's middle, which
      upright is the game's lower part: left as it is while the pad plays sideways (the open "gamepad upright" item).
- [ ] **One touch layout for both orientations, sideways: built, his test pending** (Kailil, 2026-11-12: "Eventually, im going to unify/overwrite the
      vertical touch sytem onto the phone's landscape system ... Unless we split the right and left half of the botom
      UI and shove a map into the middle with the eco bars on top of it, so the top row isnt empty with eco stuff and
      that returns vertical real estate back to the actual game world. and the left and right thumbs will have
      sufficient reach"). Mockups (claude.ai artifact "BAR Droid landscape touch layouts": today's landscape HUD; A
      split dock: build left, minimap + eco middle, orders right; A folded to its middle in the camera-pad state; B
      side rails; C thumb arcs). His pick, the same day: **A, the split dock**; "yes start building". First build
      (2026-11-12): the upright dock's widget lays itself out sideways too (bardroid_portrait.lua L.land): a band 0.4 of
      the height along the bottom; left the selection row over the build grid (2 whole rows, 3-6 columns as fit);
      middle metal and energy, BAR's own minimap (its Minimap widget's external frame: the engine draws and clicks it
      there, in the map's shape; the dock's texture and dimming leave it clear; RtsTouch's "map" rect sends its
      touches to the game) and the groups; right the orders, 3 wide where there is room, or the home grid. Launcher
      setting "Touch dock sideways" (on; launch-bar.sh bardroid_landdock.txt); a pad or a mouse as the input brings
      BAR's own screen back; spectators keep the sideways spectator bar. Dev phone, 2008x938 and 1192x1080 (the
      unfolded Fold7's shape): the dock up, a minimap tap moved the camera, a building picked and its shapes and PLACE
      on the right. Not yet: spectating with it, the pad on it, the cover screen measured on the Fold7. The same
      day: its D-gun mode sideways (MOVE and AIM under the thumbs, FIRE over the middle, cancel at the left) had
      FIRE over the metal and energy panels, their edges showing round it; they step aside in that mode now, and the
      sticks take the band's whole height. Open for Kailil: with nothing picked the home grid fills the right half
      and the left half stands empty (upright the grid spans both halves; sideways the minimap is between them).
      Next run: a Bot Lab built from the dock sideways, FACTORIES picked it (its 8 bots on the left), a bot tapped:
      its queue buttons (+1 +5 +20 / -1 CLEAR ORDERS) came as two thin rows over an empty half; three wide they are
      double height now where the half has the rows (upright unchanged). And the handover: "src pad" in the touch
      log (what the app writes when the pad is used) took the dock down and brought BAR's own screen back (its
      minimap at the top left, its resource bars), "src touch" the dock again; the chat box, though, stood a third of
      the way across under the top bar while the dock was up (where the minimap had ended): now the row under the top
      bar from the left edge then, as upright. Then the unfolded Fold7 turned mid-game (dev phone, an upright skirmish,
      wm size 1080x1198, 1198x1080, back): the dock went sideways while the screen was wide (BAR's minimap into it),
      upright again after (the minimap back in its small upright place), no error; and the lobby sideways at the
      near-square size: the column 15 buttons a page, the screens beside it the whole height.
      Polish, 2026-11-13: the one-thumb panel's BUILD grid had 6 columns at most, and on the dev phone sideways a
      seventh tile's width stood blank at the panel's end, the "more" arrow off the tiles' middle; up to 7 now (both
      sideways layouts): the tiles reach the panel's end, the arrow under the middle tile, 14 options a page (12).
      Dev phone: idle skirmishes upright (6 min) and sideways (4 min) with no error of the app's, 30 fps; dock-phone-test
      all pass.
- [x] **Kailil's notes of 2026-11-12 evening on placing and the factory queue** (his screenshots: a 3 x 3 GRID with
      ONE lit, a Bot Lab with INSERT lit). Placing: "the build place menu should reflect i am in grid mode ... I should
      be able to cancel the grid by pressing one"; "I activated grid mode too easily when I was moving around my
      building placement. Grid mode should only activate with my long press if my finger doesn't move at all"; "when
      ... doing the fine tune placement adjustments, it is spawning another building ... it should instead use the
      vanilla system". Done: GRID lit while a GRID is held (the copy's droidPlace), ONE during a GRID ends it unplaced
      and picks the building again on ONE (RtsTouch gridToOne, "grid one", the place file's "one" rect; picked again 6
      frames after the button is up); a GRID only from a long press that never moved (the rest-after-a-drag trigger and
      the drag-from-the-building trigger gone: that drag nudges now); the app's own drawn building only where the
      pointer cannot be: the pointer is kept on the waiting building (camera moved, or resting on the dock after a tap)
      and BAR's blueprint is what shows (keepPointer, drawSpot). Factory: "Insert is still not inserting the unit I
      select in front"; the picture's tap now carries INSERT's Alt (only +1/+5/+20 did); "have the factory build queue
      unit pictures accept a first time ui bottom click ... for all builders and factories": the build options are a
      "live" rect in the dock file, RtsTouch opens the menu with their first tap and the tap acts. Dev phone upright
      (a Bot Lab given with the singleplayer cheat, its queue logged): armck, armpw queued with single taps on a closed
      dock, INSERT then armrectr: "armrectr armck armpw"; a still long press: GRID lit over a 3 x 2 blueprint, ONE:
      gone unplaced, ONE lit, the wind turbine still picked; a drag from the waiting building nudged it; one blueprint
      only; dock-phone-test and remake-check pass.
- [x] **Kailil, 2026-11-12, the PLACE panel and the dock's clock**: "Let the rotate and x button take up the whole
      bottom portion of place. Instead of anchoring right"; "When in build place mode, dont let the bottom ui half time
      out. So it will always accept touch". Done: in the dock ROTATE and X split the panel's bottom strip, half each,
      PLACE above them (make-buildmenu.py layoutPanel); the dock's menu held open, no clock, while a building is picked
      or about to be picked again after PLACE or ONE (SP.held, the copy's fourth droidPlace answer). Dev phone upright:
      the wind turbine picked, 4.5 s later the menu still open; spot, PLACE: queued, picked again, the menu open 4 s on;
      X: the orders.
      Found the same night on the dev phone at 1080x1198 (the Fold7 unfolded upright): there the half has three rows,
      PLACE under two rows of shapes was one row, and the strip made ROTATE and X ~43 pixels tall (as squares beside
      PLACE they had been the row's full height). Where the half has three rows (and sideways, as before) ONE, LINE,
      GRID and BORDER stand in one row and PLACE is two rows tall: ROTATE and X a full button high. PLACE lit while a
      GRID from a long press waits (the copy's fifth droidPlace answer), as the copy's own panel was; dock-phone-test
      passes at 2316 and at 1198 lines.
- [x] **Kailil, 2026-11-12 night, INSERT, placing, the home buttons, holds on the dock** (his Fold7 still on a build
      from before the day's fixes: unreachable over adb all evening). INSERT: "Insert plus tapoing a unit to build. Is not
      interrupting the build queue" (his screenshot: CAMERA PAD up): INSERT's tap only opened the menu; the selection
      row is now a "live" rect too (dev phone, a Bot Lab mid-build: INSERT, Rector: "armrectr armpw x5", building the
      Rector at once). Placing: "never ever initiate a grid command if im fine tuning ... Grid can only be initiated by
      pressing grid, or pressing and holding a finger down ... not miving my finger": a finger settled on the waiting
      building needs a full second still for a GRID (a pause of 0.3 s then a drag: a nudge); "If I press one, the grid
      disappears ... the one will be awaiting me to place where the grid initiated. If I press grid again or line, it
      shoukd restore the grid": ONE keeps the GRID's corners, the building waits at its start (the pointer on it: one
      blueprint), GRID or LINE holds the drag again, GRID and LINE switch a held one in place. Home buttons: "make rhe
      commander button. All units and local units buttins not need the ui one tap engage": the home grid is live.
      Holds: "when i press and hold any button or anywhere on the bottom ui. It jumps the camera south": a long press's
      release went to the dock's top edge and the dock panned for it (500 to 1300 elmos a hold); it stays with the
      finger now. dock-phone-test passes.
- [ ] **BAR's Settings upright, asked again** (Kailil, 2026-11-12 night, with a screenshot: "Resize the setting menu to
      fit on vertical"): BAR's fix is the patch above (`bar-windows-upright.patch`, waiting on BAR). In the app a copy of
      gui_options.lua is not workable: 131 uses of the widget handler a user widget does not have (configData,
      orderList, knownWidgets, EnableWidget ...), and the phone's patcher replaces one place each. The route that works
      in the app: the app's own upright Settings screen on BAR's options API (WG.options: getOptionsList,
      getOptionValue, applyOptionValue, toggle), BAR's widget running hidden for the switches. His call.
- [x] **Kailil, 2026-11-12, the presets**: "the strafe command needs to have a each unit walk side and have a gap
      between them if the space allows it. All preset commands shoukd be able to be sent via a tap to do a quick order
      send. Or me draw a line at the site I want the formation to end and begin the repeat commands. The length of that
      line I draw sets the length of the formation's horizontal size"; "the repeat commands for all the other presets
      besides strafe should not make it move back to the original move marker then fight marker. Instead, it should
      make the units on each row repeat move side to side the formation. Remember ranged units further back but still
      at an appropriate range to be effective". Done (bardroid_presets.lua): a tap on the map sends the preset there
      (the front's middle), a line drawn on the map is the front: as wide, facing away from the group, the places shown
      as the finger goes (blue rings, the front's side to side reach). STRAFE is a line abreast (a gap where the width
      has room, more rows behind when it is full), each unit straight to its place. Every preset turns repeat off for
      the way there (a repeat left on brought units back round to where they started) and, once every unit is there
      (or 12 s after the first), each fights 150 elmos to each side of its place on repeat, the group together. The
      ranged stand behind the front by reach, the shorter first: as far back as still lets them hit 150 elmos past the
      front row's own reach, 600 at most. Dev phone upright: dock-phone-test's STRAFE line (6 Pawns, 327 elmos: one
      row 65 apart, then side to side, 300 elmos, repeat on) ALL PASS; BATTLE LINE tapped with 4 Pawns, 3 Rocketeers,
      2 Hammers (repeat on beforehand): repeat off on the way, all 9 there 27 s later, then side to side on repeat.
      Found the same night in review: a unit of the armed preset dying before the finger went down made the preview's
      layout read UnitDefs[nil] ("Error in DrawWorld(): ... attempt to index local 'ud'", BAR removed the widget); the
      plan now leaves out units gone since (dev phone: a Pawn self-destructed after STRAFE was armed, aimed after its
      death: no error, sent to the 5 left). The preview's marks grow with the camera's distance (up to 3x), its line's
      ends and arrow never larger than the line itself.
- [x] **Kailil, 2026-11-12, PING and CHAT**: "Holding the ping button should allows me to engage drop a ping with a
      voice chat text assigned to it. Like the vanilla game behavior how you can send a ping with words. Also, allow me
      to be able to double tao the ping button and it changes it to a chat button with a sleak pop animation that fits
      the tone of the game. It will engage the voice chat chat system we built. Then after chat is sent. The button
      changes back to saying ping. With an animation." Done: the dock file's "ping" rect (PING's half of PINGS);
      RtsTouch: held, `dock_voiceping` and VoiceChat for a ping's label; tapped twice within 350 ms, `dock_chat` and
      speak to chat (a single tap waits those 350 ms, then arms PING as before); PING takes the first touch with the
      menu shut. bardroid_portrait.lua pingT: held, SPEAK (gold), the map's tap meanwhile is the spot; the words
      (bardroid_touch.lua hands them to the dock first) drop BAR's labelled ping there, or PING waits as TAP MAP with
      the words under it; no words: the spot gets a plain ping. CHAT: the button squashes away and pops back teal as
      CHAT with a gold ring bursting out, glowing while listening, and flips back to PING the same way at `voice_off`.
      Dev phone (microphone revoked): a double tap: CHAT, the phone's "no microphone", back to PING; a hold: SPEAK,
      then PING armed; injected words: spot then words ("attack here") and words then spot ("go here", shown under TAP
      MAP) each made BAR's point marker with the label; CHAT's frames with voice_on / voice_off injected, three rounds.
      Once the GPU driver's "submit failed" fault ended the game as CHAT began; three rounds after it ran clean.
- [ ] **The sideways dock for one thumb: built, his test pending** (Kailil, 2026-11-12: "Only have the map show when no
      units selected. And keep the bottom ui two slots only instead of 3 slots ... So the bottom ui can be snapped to
      the left side or right side of the bottom of the phone so it can be used by one finger only. Add a button or
      symbol to swap what side the bottom ui pins too"; of the choices asked, a HOME button on the map and BUILD |
      ORDERS tabs). bardroid_portrait.lua `L.thumb` (layout): at the pinned side's edge the panel (the tabs, the
      selection row, the tab's buttons: the left side's content under BUILD, the right's under ORDERS, PLACE, HOME,
      LISTS...; the other laid out off the screen, so no draw, press or finger finds it), beside it the map slot (metal
      and energy, BAR's minimap, the groups; HOME over the swap arrow on the panel's side of the minimap). Nothing
      picked: the map slot alone, where it stood; a tap on it (the menu opening) or HOME opens the home buttons in the
      panel, closed again with the menu's time-out. The tab: a builder BUILD, other units ORDERS, a building picked
      PLACE (its four shapes in one row, PLACE the taller), a factory's queue QUEUE; a tab tapped stays until what the
      dock shows changes. The side kept in the widget's config. The D-gun mode keeps the band across the bottom (its
      sticks under both thumbs). The panel stands at the edge, not the map: BAR stacks its player list, clock and music
      lines up from the bottom right corner, over the minimap there, and no widget can move them; the map slot does
      not follow the closed panel to the edge for the same reason (and stays under the thumb). On the way: the dock's
      texture scissors were in screen pixels (right while the dock began at x 0; `SP.scissor`), and BAR's order menu
      copy drew under the full-width dock all along (now hidden while the dock is up, make-ordermenu.py, remake-check).
      Dev phone sideways: the tabs, ORDERS, nothing picked (the map slot alone), HOME, the swap to the left and back,
      COMMANDER from HOME, a wind turbine picked (PLACE came up) and placed (the order log: the build queued), the
      D-gun's band and back. Open for Kailil: with the panel closed BAR's own corner widgets show at the bottom right
      (its 1-9 groups, idle builders, player list); the map slot could also slide to the edge then if BAR's player list
      moved above the dock.
- [ ] **Turning with the phone: built, his test pending** (Kailil, 2026-11-12: "Allow me to have auto rotate enabled
      on my phone so I can use vertical or landscape in one session anytime I want"). Launcher setting "Turn with the
      phone" (on): while the phone's auto-rotate is on, GameActivity asks for the phone's own orientation
      (`SCREEN_ORIENTATION_USER`) in place of "Play upright"'s fixed one, in the lobby and the game; auto-rotate switched
      mid-game is watched (a ContentObserver), off gives "Play upright"'s again. A game or lobby starting picks its
      loading picture and launch-bar.sh's upright tweaks by the screen's shape at the start (`Prefs.startsUpright`).
      Dev phone (it lies flat, so auto-rotate switched instead of turned): a skirmish started with auto-rotate on
      (sideways), at frame 860 auto-rotate off with "Play upright" on turned it upright mid-game (the upright dock,
      BAR's minimap small at the top left), auto-rotate on again sideways (the sideways dock, the minimap in its
      middle); each turn reloads BAR's interface at that shape's scale (as a fold does), about 6 s, no errors. The
      lobby the same way: the column sideways, the upright pages, the column again. The dev phone keeps auto-rotate off
      (toolchain.ps1 `$PhoneScreen`: its tests pick their orientation with "Play upright"). The next run, the lobby
      turned before a game: (1) turned upright from sideways, Chobby's main window stayed at the side column's edge,
      the whole height over the status line, on the right half (the side layout's place; Chobby's ViewResize keeps a
      place it did not set): now uprightOff puts the main and submenu windows back where Chobby had them, and the
      upright lobby after a turn is the same as one started upright (dev phone: sideways, upright, sideways, upright,
      the Skirmish screen the full width each time upright; lobby-phone-test passes). (2) A game started from the lobby
      loads in the same engine, so launch-bar.sh's upright choices for the load screen, made at the engine's start,
      held after a turn: BAR's tip (off upright) and BAR's load pictures (the upright versions under BAR's names). Now
      the lobby widget sets the tip for the next load by the screen's shape (in memory, an overlay: the player's own
      value sideways, from .bardroid-tips-line), and the app puts the upright pictures in place or takes them away at
      each turn (`LoadPictures`, the same steps as launch-bar.sh's). Dev phone: sideways (tip on, no pictures),
      upright (tip off, the 5 pictures there), sideways (tip on, gone). Then at a real load (a save made in a sideways
      skirmish, loaded from the lobby's Load Game, as the dev phone has no connection for maps): a lobby started
      sideways and turned upright loaded it with the upright picture whole and the app's wrapped tip, no BAR line off
      the sides; a lobby started upright and turned sideways with BAR's own picture and BAR's tip line. Left: Kailil
      turning his Fold7 in a game and the lobby.
- [x] **The Free memory button sideways clear of the logo and the commander** (found 2026-11-12, dev phone, a start
      screenshotted every 0.7 s): a sixth below the middle, where Kailil wanted it under the logo (2026-11-04, when the
      engine's splash was BAR's picture), it lay over the ENGINE of the app's Recoil splash, and on a game's load screen
      over BAR's commander. The splash picture now has the logo's middle at 37 % of the height sideways
      (`SplashPicture.LOGO_MIDDLE_SIDEWAYS`) and the button just under it, above the engine's lines at the foot; while
      a game's load screen is up, the top right corner under BAR's low memory band. Upright as before.
- [x] **The dock's menu time-out 30 % longer** (Kailil, 2026-11-12: "extend bottom UI time out by 30 percent. its too
      short"): 2 → 2.6 s (bardroid_portrait.lua MENU_SECONDS; the launcher's text and dock-phone-test's wait with it).
- [x] **The landscape lobby: one paged column of big buttons** (Kailil, 2026-11-12: "in the landscape Lobby, the
      buttons on the left ... Make them big like the vertical buttons look. and move ALL buttons to the left side of the
      page, even the buttons in the top right hand corner like login. so the main window has the full vertical space.
      make all the buttons come together with minimal padding. allow swiping pages up and down. it will be a single
      column of buttons"). bardroid_lobby_touch.lua side mode (upright.side): the upright grid's mirrored buttons as one
      column down the left (a fifth of the width, 190-300), 60 high, 4 apart, Chobby's top buttons (Keys, Website,
      Login) in it, its logo and status off (the connection state in the column's top line), the content from the
      column to the right edge and the whole height; pages one under the other, a swipe up or down turns them
      (the grid's snap), arrows up and down in its page strip. Upright keeps its grid; a turn of the phone swaps them
      (Chobby's own layout back in between). Dev phone sideways, offline: 17 buttons, 13 a page, 2 pages; a swipe up
      turned to page 2 (Plugins, Website, Keys, Exit), Plugins opened at the full height; lobby-phone-test and
      dock-phone-test all pass on the build. Later the same day: Chobby's notes sideways kept Chobby's place, its
      foot at the right, two "Download Failed: All That Simmers" over the Skirmish screen's Advanced; now as upright
      a repeat goes out of sight and the rest stack from the top over the middle beside the column (dev phone: one
      "Download Failed: Red Comet Remake" at the top, Next and Advanced clear). Also tested that night: FACTORIES (an Aircraft Plant placed from the dock,
      then FACTORIES picked it, the camera on it, its seven aircraft in the dock) and the launcher's one page.
- [x] **The launcher's settings squeezed under its top block** (found 2026-11-12, dev phone at 1080x1198, 360 dp wide):
      one over the other (under 600 dp) the top block (title, status lines, buttons) takes the height it needs and the
      settings get the rest; at font size 1.3x the settings showed one line, at display density 600 and up none. Only
      on near-square screens under 600 dp (the Fold7 unfolded is wider at its default zoom and lays them side by side;
      tall phones have the height). A cure has to choose: cap the top block (its buttons may scroll out of sight) or
      scroll both as one page. Kailil, 2026-11-12: "one scrolling page, (show me examples)", then of the examples
      (normal and 1.3x font at 1080x1198) "the top one". Done: under 600 dp and under 1.5 times as tall as wide the
      title, status lines and buttons go first in the settings' scroll (LauncherActivity.fitLayout), the device lines
      under them; a tall phone keeps its buttons above the settings, a wide screen side by side. The same night: the choice rows' 70 % step was never tried (a float loop
      ended at 69.99999 %), fixed; the status line's "(no connection)" wrapped mid-bracket, now one piece.
- [ ] Bugs found on the way, each with a check in `tools/spectate-test.ps1` or `tools/laptop-tests.ps1`. Night of
      2026-10-28: two in tonight's own caching (fixed, bdaae2e); the phone's launcher logs (58,000 lines, Kailil's
      games and tonight's runs) hold no error from the app or its widgets, only BAR's and the engine's own warnings;
      the input-source code (touch/mouse/keyboard/pad for the spectator tools) reviewed, nothing found; README's
      launcher labels match the app's. `tools/publish-check.ps1` reviewed: its home-network address check never
      matched (git grep's ERE has no `\d`), an allowed e-mail address hid a private one on the same line, the history
      check missed other letter cases and commit messages, and the APK check passed when the debug key could not be
      read; fixed, `-SelfTest` (in laptop-tests) runs the patterns through git grep over planted data, and the check
      notes the e-mail address the commits name (Kailil: GitHub's noreply address, or keep his).
      `tools/worklog.py` reviewed: run from plain PowerShell (no git on PATH) it counted 0 commits and said nothing,
      so WORKLOG.md showed "Commits 0"; it now finds the toolchain's git as env.bat does, and without any git says so
      and writes "-". Cron-fired turns are rightly not counted as Kailil's messages. `bardroid_players.lua` reviewed:
      it, the chat widget and the benchmark widget timed with `os.clock` (CPU time in standard Lua on Linux), moved to
      `Spring.GetTimer`; measured on the phone afterwards, the engine's `os.clock` keeps real time (x1.00): no bug,
      one timer in all widgets now.
      `tools/spectate-test.ps1` failed ("a replay that never starts playing"): it took BAR's newest replay, one from
      2026-10-13 that never leaves its first frame on the laptop; it and `fp-tuner.ps1` now choose from the tools'
      copies too (`toolchain.ps1` Get-ReplayFiles), so the phone-recorded 8v8 is picked: all pass.
      `bardroid_minimap.lua` reviewed: the suspicion that its in-memory size would hide a size the player sets in
      BAR's settings was wrong (BAR's own save replaces the overlay); touch-widget-test now checks that such a size
      stays (passes; a "fix" that followed BAR's value broke the shrinking: BAR takes the overlay 0.25 s late).
      `tools/phone-bench.ps1` guarded: it stops on a locked phone (`dumpsys trust` deviceLocked) before warming up
      and before the measured run, and records no run whose game ran hidden ("game screen hidden" before the results,
      `toolchain.ps1` Test-BenchHidden: today's 21 runs from the phone's log sorted right, the seven hidden ones too). `Build APK.bat` reviewed: an
      empty `bardroid.keystore=` passed its key check and built an unsigned APK named like a release, and a build
      without an APK (or a failed copy) still reported one; fixed (tested: no key and an empty key refuse, a
      throwaway key builds and passes `publish-check -Apk`), Gradle names a keyless release `-unsigned.apk`, and the
      tool prints the exact publish-check command. Line endings checked: `.gitattributes` keeps `.bat` CRLF and the
      container's `.sh` LF for any checkout, no binary is taken for text, every `.ps1` is ASCII (PowerShell 5.1).
      `bardroid_spectate.lua`'s new views reviewed: the fitted Shoulder kept the last unit's camera on the next unit,
      was framed from below on slopes (the engine lifts a camera under the ground) and looked past the unit with the
      engine's cardinal lock on; fixed, with a spectate-test case for the next unit (HISTORY.md "Evening").
      The new chat typing box reviewed against BAR's widget handler: BAR's hotkeys run before any widget hears a key
      unless one owns the text, so typing could also give orders; the box and the open layout editor own the text now
      (HISTORY.md "Night"). launch-bar.sh's new build menu switching had no check: `tools/launch-bar-test.sh` runs its
      widget_order and controller-game block as they are on a scratch BYAR.lua (the copy in, BAR's own back on another
      BAR file or none, the controller game off, a second start changing nothing; a sabotaged switch fails it); in
      laptop-tests and CI. A full laptop-tests run after the checks moved off-screen found laptop-tests.ps1 itself
      broken by that commit (a "$gitUsr:" in a string: PowerShell would not parse the file); fixed, and every
      tools\*.ps1 is now parsed first (laptop-tests, and CI with pwsh, which also covers laptop-tests.ps1). All 12
      checks pass, the lobby, bridge and catch-up tests with their games off-screen.
      The touch building's taps reviewed (`RtsTouch`, the build menu copy): a tap shorter than the game's answer for
      that point (a quick finger, a slow late-game frame) became a plain click and placed the building at once,
      without PLACE; it now asks again for up to 250 ms first. And a spot the camera had moved under the build menu,
      PLACE or the minimap made PLACE click that interface instead; such a spot is no longer told to the app (PLACE
      dims until it is back in view; a touch-widget-test case). The Java side is Kailil's to check on the phone.
      The gamepad's new game mode reviewed (`ControllerBridge`: keys and buttons let go on every mode change and pause,
      hat D-pads, the build menu's focus and a picked building routing the D-pad, B and X): nothing found. Its build
      menu focus (the copy) had one: two quick D-pad presses, before the pointer warp had reached the game (a frame
      or two), stepped the second from the option still under the pointer, so right, right moved one option; the
      focus now steps from itself and follows the pointer only once the warp has landed (or half a second on).
      touch-widget-test: right, right, down in one frame and three lefts past the edge (the real pointer's lag only
      shows with -Pointer).
      `PadGame` reviewed for a pad that lies connected while fingers or a mouse play: its tick runs 60 times a second
      whenever a pad is connected, and after each touch or mouse move it glided the pointer back to the middle at once,
      taking it from under the finger (the widget's hover answer for the finger then never came) or the mouse; also at
      the start of a game. Now it waits until the pad itself is used (a button, a stick, a trigger), and a glide under
      way stops when touch takes the pointer. padgame-test: four checks (they fail on the old code).
      `tools/profile-benchmark.ps1` loaded the phone's widgets as of a week ago: now Installer's whole list (the
      spectator tools, minimap, layout editor, build menu copy, gamepad widget too). BAR's benchmark in the controller
      game with all of them: the build menu copy (hidden beside v0.8.5's) 0.036 ms a frame and no garbage, the gamepad
      widget and the layout editor below the top 25 (under 0.036 ms); the costliest of the app's, the info panel,
      0.090 ms and 21 kB/s. The gamepad widget looked a command's kind up each frame while one was picked (a table per
      call): now once per command.
      The order menu on the pad (Back + RB) works out BAR's order grid itself (`bardroid_pad.lua` ordersLayout, from
      `gui_ordermenu.lua`'s setupCellGrid), checked so far only by the pointer landing inside the menu: touch-widget-test
      now draws the worked-out cells over BAR's buttons for its screenshot. On the laptop (1280x720, a commander, 20
      orders) every outline sits on one of BAR's 5 x 4 buttons, and the order the pad was put on (Move, the 10th) is the
      button BAR lights. The same in the controller game, whose order menu is v0.8.5's (BAR's of the older release
      with v0.8.5's edits): every outline on a button, the first order lit where the pad put it, and the app's 3x3
      build menu in place of v0.8.5's.
      The controller mod switch reviewed: a LuaUI reload (BAR's interface scale changes on every fold and unfold)
      starts the widgets with v0.8.5's controls while the app stayed on its own: no pad camera, v0.8.5's build menu
      shown, the app's hidden. The app now tells its mode again every 2 s while its controls have the pad in the
      controller game; the widgets act and note only on a change. touch-widget-test: the same mode told again changes
      nothing and shows no second note; that check found the gamepad widget's notes never cleared (`x and nil or y` is
      always `y` in Lua; harmless on screen, an expired note was not drawn): fixed. The same pattern is in BAR's own
      Build menu (`disableInput = Spring.IsGodModeEnabled() and false or (...)`: god mode never forces input on), an
      upstream matter; the app's copy keeps BAR's line.
      The files the widgets hand the app reviewed: `io.open(..., "w")` empties a file before writing it, and the app
      reads them many times a second, so it could find one empty: the build menu copy's (a tap then a plain click that
      placed the building at once, without PLACE; rewritten every frame while the camera moves a picked spot), the
      gamepad widget's (no menu: the pointer pulled out of the menu it was on) and the game file (read once per change
      of its time stamp, which the emptying and the writing can share: the wrong game for the whole match). All are
      now written whole and renamed, as the catch-up file was. touch-widget-test stopped after a fixed 240 s, which a
      throttled laptop (7 fps, screen off) ran past, cutting the cases off midway: it now stops when the log stands
      still for 90 s. New cases for the pad's group clear, LB + Y, Back + R3 and the camera bookmark; LB + Y found the
      LB orders (fight, attack, patrol) aimed where the mouse pointer was, not at the reticle: wrong for the 160 ms the
      pointer glides back to the middle after a drag or a menu, and patrol or fight with a unit under the reticle
      only picked the order. They aim at the middle now (the pointer while it is free), at the ground under a unit
      too. padgame-test: the chords (groups, L3/R3 against Back + R3, LB with the face buttons and the D-pad, the
      bookmark, Back + Start), 13 checks. At tonight's 5 fps the controller game's note checks failed (the runner's
      steps 4 s apart, the note gone after 1.3 s): they read the last note shown and a count of notes now. A full
      laptop-tests run at that speed (40 min): 12 of 13 passed; the pad's R3 case had queued two short moves that the
      commander walked before R3 came ("0 -> 0"), now held behind a WAIT (and "LB + B stops" checks a real queue).
      The next run, at 3.5 fps, lasted 11 game minutes: BARb's first raid killed the commander and ended the game
      midway. touch-widget-test plays against the engine's NullAI now (no case needs the enemy). With the commander
      held still, LB + Y's patrol point (the reticle on the commander) was where it stood: the engine ends such a patrol
      at once (the order given, the queue empty; a mouse patrol on the unit does the same); the case aims 400 elmos off.
      `bardroid_pad.lua`'s order menu reviewed: with the pointer at rest, a menu that changed under it (a selected unit
      died, BAR's priority target button came) kept the old order lit and A gave it, though another order sat under the
      pointer; it now takes the order in the cell. Its following, holding and letting go never ran in touch-widget-test
      (the recorded moves left no pointer to follow): a made-up pointer the moves land on now runs them (onto the 3rd
      order, pushed off once and held, pushed off for 0.25 s and let go).
      The build menu copy's D-pad reviewed: on the last page, right from the last option (a row not full) stayed on it,
      stuck (the step past the end was clamped back); it now goes on to the next page like right past the edge (from
      the last page, the first, the same row). touch-widget-test case.
      `RtsTouch`'s touch building taps reviewed again (the build menu copy's spot and PLACE code too: nothing): a tap
      still waiting for the game's answer (up to 250 ms, `tapBuilding`) is not tied to its gesture, so a new gesture in
      that time does not end it; its fallback click (no answer: a plain click) can then come in the middle of the new
      gesture (a drag's button held). Rare (a second touch within 250 ms of a tap the game has not answered). Fixed
      2026-10-29: the waiting tap is decided at the next touch down, before that touch moves the pointer (its late
      answer, else its click, in order). Not yet checked in a game on a phone: the dev phone (8 GB) could not load one
      then (it plays in the low-memory mode since the evening of 2026-10-29); Kailil's next Fold7 build carries it. A touch-building try on the dev phone with
      `CompressTextures = 1` (its games load then) ended at the first tap on the build menu: Android ended the app
      for lack of memory again, so that mode has no headroom for play. It showed another bug: Android restored the
      launcher with its first intent (`start skirmish`, also `start bench`), and the game started all over by
      itself (`removeExtra` does not outlive the process); the intent now acts only on a fresh start (a forced kill
      of the app's process: the launcher came back, no game).
      `tools/publish-check.ps1 -NoHistory` after the night's commits: ready. CI's `tools/java-checks.sh` run locally
      (the toolchain's sh and JDK 21): all four pass. Its javac notes `new URL(String)` in Downloader and Updater as
      deprecated (since JDK 20); left as it is on purpose: Android's `java.net.URL` is not deprecated, and the
      replacement (`URI.create(...).toURL()`, `URI.resolve`) parses more strictly (it refuses a space, which a
      redirect's `Location` can carry), a download risk for nothing on the phone.
      `bardroid_touch.lua`'s reading of the app's lines and `ControllerBridge`'s camera line reviewed: nothing. No
      pattern can match inside another line (the gamepad's act names, `slow_pan`, `pad_*`, `rotate_*`, never have the
      space after them that `pan `, `pad ` and `rot ` need); the left stick goes to the pointer exactly while it draws
      or is free, and pans under the reticle otherwise (the area select too).
      Both games' touch-widget-test logs after the night's widget changes scanned for errors and warnings the cases do
      not catch (an error in a path no case takes would remove a widget quietly): only BAR's own (a deprecated config
      key, a test weapon without a model, sound overrides).
      That scan should not be needed by hand: touch-widget-test printed only the touch widget's, the build menu's and
      the cases' lines, so an error in any other widget (pad, chat, info, players, minimap, layout, or BAR's own after
      one of the app's), which BAR's handler answers by removing the widget, passed unseen (a planted error: ALL PASS).
      Any "Error in ...()" or "Removed widget:" line is now a FAIL line (laptop-tests counts it); a case that errors
      is a FAIL and the run goes on (it had removed the test widget: no "done"); the test's widget folder is emptied
      first (a stale file kept loading). Checked with a planted error (both reported, "done: 34 FAILED") and clean
      runs in both games. One clean run before had three cases a few pixels off (the chat box, PLACE against the
      order menu, ~1%: the view resized under it?); the next passed, the code unchanged.
      The low-memory mode (2026-10-29, night) reviewed: `bardroid_lowmem.lua` leans on BAR's widget handler calling
      every widget's Shutdown when LuaUI ends (`widgetHandler:Shutdown`, its ShutdownList: yes), so a next game from the
      lobby in the same engine starts with the GL4 unit shaders off too, and a LuaUI reload (fold/unfold) puts cus2
      back before BAR's Options looks; launch-bar.sh logs the mode at every start on the dev phone ("low-memory mode
      (7072 MB of RAM)"). `tools\pace-test.ps1` could not run on a fresh phone (a `files/crun.sh` the app never writes):
      it uses the app's `container.sh` now, ALL PASS with the shipped library.
      `tools\phone-bench.ps1` on the 8 GB phone (BAR's benchmark, 13 runs through): it misread four runs (helper
      scripts that reached the phone cut short, a run past midnight, adb push's stderr, a killed game waited on for
      12 minutes); fixed (HISTORY.md "Fitting BAR into an 8 GB phone"), the midnight filter checked on the phone's log.
      After the Fold7 notes' merge: `tools/publish-check.ps1 -NoHistory` ready. `RtsTouch`'s new ONE placement
      reviewed: a tap that moves a waiting building is held back for a double tap; a second touch near it that Android
      cancelled (the notification shade, a fold) neither ran nor dropped it, so the building jumped there at some
      later touch. A cancelled touch now runs it, as a touch that was no tap does (built; the touch itself is Kailil's
      to try on the Fold7). Then main (01ec7af) checked whole: all 13 laptop checks pass (the lobby, touch and
      controller-game runs with Kailil idle, as his launch guard wants), and on the dev phone a skirmish of that build
      played its 240 s in the low-memory mode on Starwatcher with no widget error.
      The new frame cap (`tools/pace/pace.c`, patch 0008) reviewed, with its first checks in `tools/pace-test.ps1` (a
      made-up 60 Hz vsync: swaps on the grid, the hold told to the X server, the late start, back to its own clock on a
      stale vsync). A stall stayed in the late start's slowest frame for ~14 s after a hidden game, now one slot at most;
      the vsync file was looked for at the first swap only (a game started with the screen off kept the old cap to its
      end), now twice a second until found, and an empty file is left alone (a bus error otherwise). Each check fails
      without its fix. `pace-test.ps1` took any phone: with both on adb it stopped; it now takes the dev phone.
      2026-11-05 evening: the day's ~70 engine-branch run logs searched for the app's widgets' errors. Found only:
      the order menu copy removed in every replay of the 2026-10-26 8v8 (that BAR release has no
      `luaui/Include/action_tap_hotkeys.lua`; the known older-replay case, spectators get no orders anyway), the build
      menu copy's ViewResize without `WG.fonts` in a run with every BAR widget off (an experiment), the dev timer
      widget's argument on a since-fixed engine build, and launch-bar.sh's false "ANDROID LAYER" alarms quoting
      `[simdraw]` timer lines, last at 10:48, before `widget_error` left those lines out. Nothing to fix.
      The app's chat dropped who shared units: BAR's chat hands a unit share over as a system line with the sharer in
      its name text only (its name stays ""), so it read "shared Tidal Generator to Heroic_El_Paska" with no one in
      front (dev phone, the 2026-10-26 8v8 replay at 1:15). `bardroid_chat.lua` takes the name from the name text
      then (colour codes and brackets off); the same moment again: "Schluebber  shared Tidal Generator to ...".
      Also on the dev phone with the UBWC default: touch-phone-test and lobby-phone-test ALL PASS.
      A 6-minute skirmish soak (20:15, the controller game, the dev phone's own no-cap setting): no error from the app's
      widgets, only BAR's three usual warnings; the GPU 99 % busy throughout and the game at x0.90 by 7:00 while it drew
      61 fps (a 30 fps cap, the app's default, leaves that time to the simulation).
      The same in BAR's own game (controller support off for the run, `GAMEPAD_GAME=0`, 4 minutes): no error, the app's
      build and order menu copies in place (5 x 3 options a page, "< 1 / 2 >", "Place / Blueprint" on two lines); the
      grid stands centred with ~110 px empty at each side on the dev phone's wide screen, by design (Kailil's "try 5 x
      3": more columns would fill it). The setting put back afterwards.
      Unfolding and folding mid-game (the dev phone's screen set to the Fold7's inner 2184x1968 and back with `wm size`,
      a skirmish in the controller game, screenshots 25 s after each): the X screen 1192x1080 at interface scale 1.0,
      then 2008x938 at 2.0 again, each with the app's interface reload ~1 s after the change; both layouts whole, the
      folded one as before the unfold, no error. Caught 8 s after a change the HUD was still mid-reload (both layouts'
      panels at once, the top bar's words over each other, "fps 0"): passing. The unfolded proportions (a small
      minimap, a tall build menu) are the Touch HUD item below, Kailil's call.
      The Fold7's lobby session of 2026-11-05 08:46-09:01 ended "with an error (21)": the phone's network dropped
      ("Network error 101: Network is unreachable"), a join then got garbled packets and the engine stopped on
      "invalid GameData received: Unpack failure (vector)" (21 is its EXIT_CODE_CRASHED, -1003, as an exit status). On a
      PC the engine shows that in a message box; the phone showed nothing. The launcher now gives the engine's own
      message (`StatusText.engineFatal` on the infolog's `[ExitSpringProcess] errorMsg=` line) in amber under "Game ended
      with an error (21)". status-text-test: 5 cases; dev phone: a stand-in engine (dev-env.sh, removed after) writing
      that line and exiting with 21: the message shown. A plain Exit from the lobby: exit 0, "game ended", as before.
- [x] Touch GRID moved to the engine's build drag (2026-10-30): the blue grid taken out of `tools/make-buildmenu.py`
      (droid.grid, gridPositions, gridEnds, the "grid start/by/none" lines) and `tools/touch-widget-test`'s GRID checks
      changed. Checked on the dev phone: ONE, a GRID from a waiting building, PLACE; no widget error.
- [x] `tools/touch-widget-test.ps1` run after Kailil's 2026-10-30 notes, with his laptop idle: the commander, build menu
      and GRID checks pass. Its five failures were old expectations, no app bug: the place file's rotate and cancel lines,
      the pad file's new lines, and the orders coming back after a few taps (`act fingers`), not after one touch.
- [x] First person reviewed (2026-10-30): RT never fired while walking sideways. A commander's gun is 23 elmos off its
      centre, so 0.97 of the range from the body was out of range from the muzzle: no target on 60 of 60 frames, now
      59 of 60 with 0.9 (measured on the dev phone; standing and walking 60 of 60). A spectator can no longer ride, and
      leaving BAR Droid's mode ends the ride (nothing would drive the unit). Added a crosshair, gold while firing.
- [x] First person's untested parts, on the dev phone (2026-10-30): on Hold Fire no target until RT, then the enemy under
      the crosshair, gone when let go (its damage not measured: BAR hides that building's health). Save reaches
      `BYAR.lua` for the unit and its other-faction equivalent on a clean quit. Still only with a real pad: the pointer
      hidden while riding, the D-pad and face buttons.
- [x] Path speed reviewed (2026-10-30): Reset took the whole curve in one tap beside Close, now a second tap within 3 s
      ("Sure?"); + and - changed the first point in reach, now the nearest; a bad line in the file is no point.
      `touch-widget-test` never loaded this widget or first person; it does now, with six path speed cases.
- [x] A Save in either camera tuner lived only in BAR's widget config, written when the game quits: the launcher's Stop
      (SIGKILL) or a crash lost it. Each Save now also writes `LuaUI/Config/bardroid_kept.lua` at once, whole and renamed,
      read back over the config. Checked on the dev phone: Forward 2 to 6, Save, the app force-stopped, 6 in the next
      game. `spectate-test` checks the file. That test stopped at a fixed 5 min, midway on a busy laptop, and blamed the
      replay; it now stops when the log stands still for 3 min and says why.
- [x] `tools/laptop-tests.ps1` after the day's notes (2026-10-30): two failures, neither the app's behaviour as played.
      Lint: a shadowed name in a new test case. The controller game's checks predated this morning's touch change: the
      menu hides only once the pad is in use, so they now say so, and PLACE (fingers' only) is checked by touch. They
      ran into the 15 min stop at 4 fps; it is 30 now. Both pass, 14 min at that speed.
- [x] Found on the way: RB's "nothing to build after half a second: closed" counted time only, two frames at 4 fps and
      less than the 0.8 s stall early in a game: the menu closed before it was laid out. It now also waits 8 frames.
      PadGame reviewed: starting first person with LB on a building or RB held left Alt or Space down for the whole
      ride; everything is let go as it starts (two `padgame-test` cases).
- [x] `bardroid_pad.lua`'s groups and QUEUE reviewed (2026-10-30): clearing an empty group went on to the selection, in
      other groups; it now says the group is empty. QUEUE left on by fingers stayed on when the pad took over and
      queued every order of the pad's; the pad in use lets go of it (`touch-widget-test` cases for both). All 13
      `tools/laptop-tests.ps1` checks pass with these in.
- [x] `RtsTouch` reviewed (GRID, QUEUE, the input source; 2026-10-30): that QUEUE fix was only half: the app holds the
      real Shift and looked the button up only at a touch, so with the pad it stayed down. It now follows the file.
      Checked on the dev phone without a pad (`adb shell input keyevent KEYCODE_BUTTON_SELECT` counts as one, a triple tap
      by `input tap` as a triple tap): Shift down with QUEUE on, up at the press, and it stays up.
- [x] A tap as a game finished loading took BAR's music widget out for the whole game (2026-10-30, found by chance): it
      reads its buttons before its first draw, the press fails it, and BAR removes a widget that fails: no music, no
      volume sliders. 3 taps did it; a tap queued up during the load arrives just then, and a fold's LuaUI reload has the
      same moment. `bardroid_pad.lua` (before it in the order) now keeps presses from going on until two draws are done:
      30 presses before the first draw on the dev phone, no error, the widget stays.
- [x] The launcher's map setting (2026-10-30): a blank name is not saved, and the note for a map that did not download
      names the real field.
- [x] The launcher's start buttons ignored what the screen showed: only "Save settings", at the bottom of a long list,
      saved a change, so Sound unticked and Play vs AI played with sound. Every start saves first (2026-10-30). Checked on
      the dev phone: Sound unticked and the map name blanked, Play vs AI: `audio` false, the map name kept.
- [x] `tools/phone-bench.ps1` after the day's notes (dev phone, 100%, cap 30): Sim 49.8 ms, Draw 9.9, Update 6.1, 16 fps
      in the last minute; this morning 44 to 50, 22 to 24, 9.2 to 9.5, 11 to 12. No cost from the new widgets. The lower
      Draw is not a gain to count on: GPU clocks differed (220 against 348 MHz) and nothing today set out to change it.
- [x] Quitting a game in first person held every later game in that camera (2026-10-30, seen on the dev phone: mode 0 in
      the logs before any ride): BAR's Camera Remember saves the camera as a game quits, before the widgets' Shutdown,
      and BAR's start view skips any but the Spring and overhead cameras. `bardroid_padfp.lua` puts the camera back when
      the handler asks for settings (it is asked before Camera Remember), a spectator's first person too, and
      launch-bar.sh forgets one saved (`launch-bar-test`). On the dev phone: the first game back in the Spring camera at
      5000; quit while riding, Spring saved.
- [x] Kailil's notes, testing on the pad (2026-10-30): LT speeds the zoom up as it does the pan, as v0.8.5's (case in
      `touch-widget-test`, first run pending his laptop idle). LB + A / Y held drew with the left button, and BAR's
      formation widget draws with no other but the right: with five Pawns and a stick now a path, orders at x 1127, 2270,
      3486, 4702 and 5895, and the order put away. A bookmark's recall keeps the tilt, in both controller modes.
      New for tests without a pad: `adb shell input joystick motionevent MOVE 0.7 0.1` is the left stick, and
      `input keyevent --duration <ms> KEYCODE_BUTTON_L1 &` holds a button, so chords run through the app's real path.
- [x] More through the app's real pad path on the dev phone (2026-10-30): a fight path with RB held, five orders along it,
      each with Alt; a first-person walk with the stick, the unit stopping when let go and B ending the ride. The zoom
      case in `touch-widget-test` passes: 0.17 with LT, 0.06 without, 3 times as v0.8.5's. `touch-widget-test -TestWidget
      <file>` runs one widget in place of the cases (2.5 min, not 15, for one question). The nudge case failed in about
      half the runs: not its timing, as first thought, but the test game's random start positions, which can put the
      map's edge just right of the middle, where a nudge rightly stops; it nudges towards the ground now. The PLACE panel
      is solid: the order menu's buttons showed through it.
- [x] The rest of that quit case and the pad's chords (2026-10-31): a replay quit in a spectator's first person saves the
      Spring camera (`spectate-test -TestWidget`, which also takes one question now, and which loads the first-person
      widget). On the dev phone by simulated pad: Back + Y opens the path speed tuner, B closes it, Back + R3 + L3 held
      starts a unit's self-destruct. The spectator bar never set its text colour, so its labels took a dim grey from
      whatever drew last: white now. All the app's widgets checked for the same: only the layout editor's panel labels,
      fixed; chat and the info panel carry their colours in the text.
- [x] Kailil's game read back from the Fold7 (2026-11-01): its replay's start script has 19 players on BAR test-31774 with
      `allowunitcontrolwidgets=0`, `allowuserwidgets=1`, the rules `pad-test -Online` now plays by, and launcher.log the
      Android-layer miss at 20:49, just before it: both causes confirmed from the game itself. No widget error in 52
      game minutes; 22-25 fps at the end with about 3,500 units, thermal status 3. The launcher says "Ready" at rest, and
      counts missed adjustments from the last start's own list: the state's count, written when a game ends, stayed old
      after a game that was stopped (it still showed BAR's menu after the fix).
- [x] Soak of the pad fixes on the dev phone (2026-11-01): over 7 minutes of BAR's own game with user widgets' orders forbidden,
      no widget error, no adjustment missed, 29.9 fps. The pad's notes say what happened: "NO ORDERS QUEUED" for L3 or R3 with
      nothing to remove, "NO PING FROM OTHERS YET" for RB + D-pad up with none seen.
- [x] Kailil's 40-minute online game with the pad (2026-11-01): "I should have no cases of that happening". RB had no build
      menu: BAR's update the evening before had turned the app's copy off (Back + RB is BAR's own menu, so it worked). The
      phone now makes the copy again itself, a copy it cannot remake still runs, and it runs with the controller game
      switched off too. L3 / R3 said "NOT IN THIS GAME" where the host forbids user widgets' orders: they press two keys
      now, Insert and numpad /, bound to BAR's Command Queue Manager (it takes key presses only, no `SendCommands`);
      self-destruct and LB + B go by BAR's order picks, and an order at the middle is picked and clicked by the app. New:
      RB + D-pad up (held: a ping; tapped: to the last ping from someone else), down (all combat units), right (those on
      the screen). `pad-test -Online` plays all of it through a virtual pad with BAR's "Allow Custom 'Unit Control' Widgets"
      really off (Kailil's idea; its first check proves the game refuses a widget's order): 11 of 11. The laptop's
      `touch-widget-test -NoUnitControl` (in laptop-tests) still has to run, with Kailil away from the laptop.
- [x] BAR's update to test-31774 (2026-10-31, 17:42) changed `gui_buildmenu.lua`, and the phones fell back to BAR's own menu,
      as they are meant to; the launcher named it. The copy is made again from the release on the dev phone: all 24 patches
      apply. The laptop's BAR is still on an older release until Kailil starts it, so `make-buildmenu.py --adb` now reads a
      phone's release directly (the same copy to the byte), the way is written down in CONTRIBUTING.md and the release
      steps, and the launcher says "1 of the app's adjustments to BAR did not apply: see the log" in plain words.
- [x] `GameService.java` reviewed (2026-10-31): nothing found. The launcher's status says "game ended", or "game ended with
      an error (n)", where it said "engine exited (n)"; the log line stays for the tools that read it. Stop is dim whenever
      nothing is running. Benchmark on the dev phone with new textures zeroed: Sim 46.2 ms, x0.47, as before (46.9-49.9,
      x0.45-0.48), so no cost.
- [x] `GameActivity.java` reviewed (2026-10-31). The choice between v0.8.5 and the app's controls lives in the screen, so a
      screen opened anew in a running game went back to v0.8.5 while the widgets stayed on the app's controls. The new
      screen now tells them. Read from the code, not run: on the dev phone Home makes the floating window and no adb step
      closed that, so the case was never reached; a normal game and its triple tap checked by `pad-test`. The launcher's
      Stop is dim with nothing to stop, still tappable: after a crash "idle" can hide a game's processes.
- [x] `PadGame.java` reviewed (2026-10-31): the rest clean, but X, "place it and keep it", had the touch fault below: Shift
      down, click and Shift up in one tick. A virtual pad on the dev phone showed it: Shift never reached the engine and the
      building went. Now Shift comes 100 ms before the click and stays 100 ms after, in BAR's game and in the app's controls
      in the controller game, X at the end of a grid too, and the build menu picks the building again
      (`build_placed`). Seen after: Shift true, the building still picked, the builder's move order kept and the building
      behind it. `padgame-test` checks the order. A second X on the same spot takes it off again: BAR's own way. The
      pad's group list shows an empty slot's number big, in the middle.
- [x] A building placed by touch did not stay picked, though `RtsTouch.tapBuilding` and HISTORY.md said it did: the engine
      keeps a Shift click's building only while Shift stays down (CGuiHandler `needShift`), and the app lets go of Shift
      100 ms later (seen on the dev phone: active -212 until Shift up, then nil). RtsTouch now says "spot placed", and the
      build menu picks the building again once it is let go; ✕ or a long press puts it away, QUEUE's Shift keeps it as
      before. On the dev phone, taps from adb: Shift up with the building still picked, PLACE still up, the builder's
      order kept and the building behind it; touch-widget-test has a check. The layout editor's hint no longer lets the
      build menu show through its words.
- [x] `RtsTouch.java` reviewed (2026-10-31), with taps from adb on the dev phone. A double tap with a building waiting sent
      it to the double tap, not the waiting spot: `cancelGesture()` ran the held-back move at every touch, added for
      cancelled touches only (it now runs at ACTION_CANCEL). Seen before: the order at the tapped point; after: at the
      waiting spot. A building's Shift click went down, clicked and up in one burst, which the engine reads as no Shift
      (startGrid's comment says so); Shift is now down 100 ms before the click and 100 ms after. Seen after: the builder's
      move order kept, the building behind it; the old build was not measured with an order to keep. A double tap right at
      the 300 ms limit can still move the building first (the timer fires just before the second touch arrives).
- [x] BAR's unit-groups panel (the 1-9 grid beside the order menu) showed pink and white noise on the dev phone, seen in 1
      of 2 tries (2026-10-31): a skirmish, a triple tap, a virtual pad's D-pad down, then RB, 2:55 into the game. BAR's
      `gui_unitgroups.lua` rebuilds into new `gl.CreateTexture` textures with no clear, and Mesa's recycled buffers are not
      zeroed: on the dev phone 22 of 60 new render textures came back full of old pixels. `pace.c` now makes a new RGBA
      texture with no data with zeros (`BARDROID_TEX_ZERO`, every phone): 0 of 60, and none whole in four runs of
      `tools/pad-test.ps1`, which checks it now (10 checks). The same steps again, 2:30 into a game: a clean panel. The
      noise was intermittent, so that one clean panel is not proof; the 22 of 60 are. On 2 of the 4 runs a new texture
      held a few white pixels (7 to 9 samples of 156 to 361, game frames 760-800, while the test rides a unit): cause not
      known, no sign of it on screen. Not run on the Fold7. "Compare upscaling" no longer carries a dated note in its label.
- [x] `ControllerBridge.java` reviewed (2026-10-31): nothing found. On the pad BAR's hover tooltip no longer covers the
      build menu's next row; the info panel below says the same.
- [x] `tools/laptop-tests.ps1` with the 2026-10-31 fixes in: all 15 pass. No other thread does what that crash did: every
      `Handler` in the app has a Looper. The dev phone's logs since 2026-10-30 hold no error from the app or its widgets
      but one of a test widget of ours. The launcher's small buttons have one text size ("Benchmark" was smaller).
- [x] A game start could end the app (2026-10-31, in the dev phone's crash buffer: 1 start among last night's). A cold
      start called `GameActivity.hiddenFlag` on its worker thread; when that was the class's first use, Termux:X11's
      static `Handler` was made there with no Looper. The flags are on `Paths` now, `PerfLog` the same, and
      `tools/laptop-tests.ps1` fails on any other class calling into `GameActivity`. Ten cold starts: no crash. It was a
      race that ran only some of the time, so those ten show no harm, not the cure; the cure is that the call is gone.
- [x] The launcher in landscape (it opens that way after a game): two columns, the settings and log with the whole
      height. A new log line took the focus out of a field being typed in (the log's `fullScroll`): it stays in the field
      now (`dumpsys activity top` before and after), and the log keeps a reader's place while they have scrolled back.
- [x] `bardroid_padspeed.lua` and `bardroid_padfp.lua` reviewed (2026-10-31). Path speed: nothing. First person: a unit
      captured or given away in sight stayed in the squad, and a ride went on, on a unit that takes no orders; both end
      now ("UNIT LOST" for the ride). A unit out of sight was no risk: a scan of every id shows `ValidUnitID`,
      `GetUnitDefID`, `GetUnitTeam` and `GetUnitIsDead` all hide it from Lua. `pad-test`: 9 checks now (an enemy unit,
      shown by /globallos, drops out of the squad). The launcher's log scrolls by finger inside the page, and its
      heading no longer gets cut off at the end of the page.
- [x] The pad switched off (2026-10-31): the game stayed in its pad-only ways until three taps. The pad going away now
      ends them. Found with a new standing check, `tools/pad-test.ps1`: Android's uinput makes a virtual Xbox pad on the
      dev phone, a real input device with both sticks, triggers and a D-pad, so ride, RT, looking, B, zoom with LT, the
      D-pad and a real disconnect are tested through the app's own pad path with no gamepad. Settings' boxes sit
      at the first line of long labels.
- [x] Quitting in first person has a standing check (2026-10-31): `spectate-test -QuitCheck`, in `tools/laptop-tests.ps1`
      (14 checks now). It fails without the fix (`mode = 0` saved). The launcher names the app's version, for reports,
      and its status line no longer repeats the engine's. All 14 pass together.
- [x] `tools/laptop-tests.ps1` with all of the 2026-10-30 fixes in: all 13 pass. `tools/publish-check.ps1 -NoHistory`:
      ready to publish; `tools/pace-test.ps1`: all pass.
- [x] First person's squad with real units on the dev phone: 3 Pawns, a Rocketeer and a Mace taken by "add units", the
      constructor left out, Following and Patrolling shown right; the counts in their own column so the names line up.
- [x] First person on each kind of unit, on the dev phone (2026-10-30): a solar collector refused ("NOT ON THIS
      BUILDING"), a sentry rides, looks and fires and does not walk, a self-destructing Pawn ends the ride ("UNIT LOST"),
      a Falcon flies. A plane passed its order 280 elmos ahead before the next came, with gaps in the flight: the order
      now goes as far as its speed asks. The crosshair has a stronger dark edge, for a pale sky.
- [x] The launcher's skirmish map is free text, and only Starwatcher was fetched when missing: any other map, or a typing
      mistake, ended the engine in 2 s (`engine exited (21)`). Now fetched, or the launcher names the map and what to check.
- [x] `tools/laptop-tests.ps1` with the unit-control-off run and the lobby's warning (2026-11-01): 15 of 16; the last failed
      on the test, which read the units' self-destruct countdown after they had blown up (a laptop's 3 fps). Now watched
      every update; the next full run passed all 16. `tools/lobby-phone-test.ps1` runs the lobby test on the dev phone any time.
- [x] `bardroid_pad.lua`'s online code reviewed (2026-11-01): where orders go through a click, LB + A or Y on units without
      that order still asked the app to click, which dropped the selection. Now a note, and `pad-test -Online` checks it.
      Repair, reclaim and the fight and patrol paths said so too when nothing was picked; factories no longer count as builders.
- [x] `bardroid_queue.lua` reviewed (2026-11-01): if BAR's shape drawer went away in a game the next look at the queue took the
      widget out, and queued buildings stopped showing for good. Taken away and back on the dev phone: shown 0, then 1.
- [x] `LobbyBridge.java` and `Updater.java`'s engine install reviewed (2026-11-02): an engine folder left without `spring` (its
      removal cut short) could never be installed again, the final rename failing at every try. Now cleared first; on the dev
      phone a real one, `spring` moved aside, was downloaded again and the game started.
- [x] Building by touch with unit control widgets off, real taps on the dev phone (2026-11-02): a building on the build menu, a
      spot, PLACE twice with the order queued each time, the building still picked, the X puts it away; no widget error.
- [x] The hot benchmark on the dev phone, 2026-11-02 night: slower than on 10-31 (Sim 46 -> 51-56 ms, Draw 21 -> 27 ms, game
      speed x0.47 -> x0.42) at the same CPU clocks, GPU median 295 MHz against 401. Not the app: the same with 10-31's game
      files (`assets/bardroid` of 6d18d0e) and with the app's build menu off. The phone's OS is unchanged (28 Sep); open.
      Settled the next morning (10:26, with the tile-copy change in `pace.c`): Sim 34.4 ms, Draw 26.4 ms, x0.64, 11.6 fps,
      the prime core at a median 1708 MHz where the night's slow runs had it at 864 under the same 1708 cap. The night's
      slowdown was that core's clock (the night's one fast run, 02:28, had Sim 33.7 too); Draw is unchanged, so the tile
      copy costs nothing measurable.
- [x] `tools/laptop-tests.ps1` stops when Kailil comes back (2026-11-02): the first run did, after 14 passes. The check it cut
      off read as a FAIL (its engine stopped mid-run); a check the watch cut off is now a STOP. The last two still to run.
- [x] `bardroid_padfp.lua` reviewed (2026-11-02): its GetConfigData, meant for the game's end, runs whenever BAR saves the
      widgets' settings, as it does each time a widget is switched on or off; a spectator in 1st person lost the way back
      to the own camera (leaving gave a made-up one). Now kept; `tools/fp-save-test.ps1` checks it on the dev phone, 4/4.
      The dev phone's logs (56,000 launcher lines, the last game's log): no error from the app or its widgets.
- [x] The launcher's Save reviewed (2026-11-02): an emptied Mesa address was saved, and a phone's next install would have
      drawn on the CPU (no address is the emulator's choice). Now the address stays, as an emptied map does; tried on
      the dev phone. `bardroid_chat.lua`'s rounded boxes reviewed: nothing found.
- [x] The game screen without a game (2026-11-02): when Android ended the app under a game (an update, the low-memory
      killer), bringing it back from recent apps showed Termux:X11's own "Not connected" page and its buttons. Now the
      launcher opens instead, with the low-memory note when that was why; on the dev phone, a skirmish ended by an
      install and the app brought back. `tools/lobby-phone-test.ps1` on today's build: all 30 pass. The layout editor's
      rounded boxes reviewed: nothing found.
- [x] The unit info panel in online games (2026-11-02, seen in `pad-test -Online`'s screenshots): BAR's released game's
      `common/weapons.lua` now calls `tonumber`, which the panel's copy of it was not given, and every unit with a beam
      laser (the commander's too) lost its name and all its stats. Now it gets Lua's own functions, a failure there falls
      back to the plain sum, and a unit type with no stats says why in the log. On the dev phone in BAR's released game:
      all stats shown. `pad-test -Online`: 14 of 14 (the first run's last case was the test's timing on a hot phone).
- [x] A white lattice over the map and the minimap for a moment, at 2 fps and x0.60, right after first person ended
      (`pad-test`, the controller game, dev phone, 2026-11-02 08:36); 6 s later all clean. Seen again in the next run, in
      the frame after "FIRST PERSON OFF" only (a frame a second, 21 of them): rows of white blocks, like a font's glyphs,
      over the whole minimap, as a recycled GPU buffer shows before its texture is filled. Not the test's 340x83 line
      (its own probe textures, a few white pixels at times, under its threshold). `BARDROID_TEX_ZERO` zeroes only plain
      RGBA textures made with no data; next: have `pace.c` log the textures made in that frame (size, format) to see
      which one the map draws from. `pad-test`: 10 of 10 both runs.
      Third run, with `pace.c`'s new log (`BARDROID_TEX_LOG=1` in dev-env.sh): a camera jump makes dozens of the map's
      128x128 DXT1 ground tiles (`glCompressedTexImage2D`, no pointer). Those made with no pixel buffer bound now start
      as zeros, but the lattice was still on the minimap in the frame after "FIRST PERSON OFF": so those tiles come
      from a pixel buffer, or the lattice is another texture (the minimap's, or the LOS overlay's, which streams through
      pixel buffers too). Next: log the bound pixel buffer with each tile, and the minimap and info textures.
      Found in the engine's source: SMFGroundTextures.cpp fills every tile through one pixel buffer, mapped
      unsynchronized for the next tile right after the last one's upload (VBO::New of the same size keeps it), while
      Mesa copies from a pixel buffer later, on the GPU. Now `pace.c` uploads a compressed texture from a pixel buffer
      out of a copy of its bytes (BARDROID_TEX_ZERO, phones): on the dev phone the frames after "FIRST PERSON OFF" are
      clean, 11 fps where they were 2. `pad-test`: 10 of 10.
- [x] Empty replays (2026-11-02): the engine writes a replay as its game ends, so every game ended by Stop, a swipe from
      recent apps or the low-memory killer left an empty `.sdfz` that the lobby's Replays tab listed with nothing to read
      (282 of 355 on the dev phone). `launch-bar.sh` now removes the empty ones before each start; on the dev phone: 282
      removed, the 73 real ones kept. `tools/pace-test.ps1` after the tile change: all 19 pass.
- [x] The launcher on the Fold7 unfolded (2026-11-02, the dev phone at 1968x2184): one column across the whole width,
      setting lines of 1,700 pixels. Now side by side from 600 dp wide, upright too; an ordinary phone upright keeps one
      column. `pad-test -Online` with the tile-copy change: 14 of 14.
- [x] Touch HUD on the Fold7 unfolded (the dev phone at 1968x2184, 2026-11-02). Checked again 2026-11-10 with the dev
      phone's display at 1198x1080 (`wm size`, the unfolded Fold7 held wide; reset after): the build menu, unit info,
      the app's order menu copy (since 2026-11-03), BAR's groups and idle-builder panels side by side, left of the small
      player list, nothing under it; spectating (a defeat, then stay), a tap on the small list brings up the app's
      spectate bar (player cams, Free, Follow unit, Group), BAR's Player View row not needed; the controller game's
      v0.8.5 menu is gone (2026-11-06); held upright, the portrait dock (2026-11-09, near-square fixes 2026-11-10). The
      notes from then, kept:
      BAR's control-group and idle-builder panels dock to the order menu's right edge, which reaches far enough there
      that both sit under the small player list and show through it (BAR's layout; its order menu has no width setter
      and the list no position setter: the order menu raised with `setBottomPosition`, or the list kept open, are the
      app's ways). And in the controller game v0.8.5's build menu shows the commander's 26 options in 6 rows with a
      quarter of its panel empty below them (the app's copy, in BAR's game, ends at its last row); v0.8.5 changes only in
      BARGAMEPAD, at his word. And spectating there, BAR's "Player View", "Player Camera" and "TV" buttons, which sit
      on the player list's left edge, run past the screen's right edge while the list is minimized (only "Player View"
      shows): the minimized list could keep more width while spectating, or stay open for spectators.
      What the dev phone at 1968x2184 shows is the game in portrait (X screen 1080x1198), not the unfolded Fold7 held
      wide (2026-11-09): at that size (smallest width ~656 dp) Android treats the screen as large and ignores the app's
      landscape request (`dumpsys`: ignoreOrientationRequest=true, letterbox running), and the flat dev phone stays at
      rotation 0. A real Fold7 unfolded follows how it is held: wide, BAR's landscape HUD at 1198x1080; upright, this
      portrait one, cramped (the top bar's numbers over Save, the build menu sized by the height, the order menu off
      the right edge). So a portrait HUD (Kailil's portrait idea, 2026-11-09) would serve the upright unfolded Fold7 too.
      A fold and unfold four times in a running skirmish there: no error from any widget, the engine's ViewResize
      0.1-0.7 s each.
- [x] The layout editor in the controller game (2026-11-02, unfolded): v0.8.5's build menu, the one shown there, had no
      outline or label at all (the app's hidden copy took its place in the editor's list). Now shown as "Build menu
      (BAR's: fixed)" whenever the app's copy is not on screen; in BAR's game the copy stays the sizeable "Build menu",
      with no second label. Both seen on the dev phone at 1968x2184.
- [x] Replays of games that were stopped but had written something (the benchmark's runs on the dev phone): the lobby's
      Replays tab lists them as "time unknown" (no game time in the header), and one started from there stood at 0:00,
      x0.00. Looked into (2026-11-02, dev phone): a 2-minute game quit the way BAR's Quit does (`quitforce`, the engine
      exited 0) wrote a replay with game time 0 in its header as well: the engine writes the time only at game over,
      so "time unknown" is BAR's own for any game not played to its end, on a PC too. Started from the Replays tab it
      played: the 0:00, x0.00 is the game's start replayed in real time (51 s here, the phone's load of the recorded
      game) before "Beginning demo playback" reaches the game, which BAR's replay "skip" button jumps; then 0:22, x1.00.
      A stopped game's replay lists its players as "Player" and "InactiveAI(1)" (the quit one: "Phone",
      "BARbarianAI(1)"). Nothing for the app to change; the empty ones are already removed (above).
- [x] Half-made settings copies (2026-11-02): `sed -i` writes a whole copy (`sedXXXXXX`) beside the file it edits and
      renames it over the file, so a start stopped in between left the copy: a 28 KB `BYAR.lua` in `LuaUI/Config` on the
      dev phone since 10-31. `launch-bar.sh` now removes them before it edits anything; on the dev phone: "1 half-made
      sed copies removed", BYAR.lua untouched. And the Info panel's stats no longer end a line with a comma (dev phone).
- [x] BAR's messages under the HUD (2026-11-02): BAR's Messages widget (gui_messages: "Battle Started", a commander
      under attack, the tutorial's lines) types them at 16% of the screen's height from 31% of its width, which on a
      phone is behind the order menu and the unit info, and it has no position setter. `bardroid_chat.lua` now takes
      its `WG.messages.addMessage` and shows them in the chat box (BAR's message white). On the dev phone: "Battle,
      Started" and a test message there, nothing behind the order menu.
- [x] The Info panel with several units of one type (2026-11-02): a grid of one cell, one big picture and the rest of the
      panel empty (BAR's own panel does the same: any selection of two or more is its grid). Now that type's name, words
      and stats as for one unit, the count on its picture, and a tap on the picture brings the camera to the group
      (BAR's middle click on a cell). On the dev phone, 23 units of 9 types given: a tap on a cell (the touch path)
      selected that type's 6, and the panel showed "Pawn" with its stats and a 6.
- [x] Hover tooltips that stayed after a finger's tap in the lobby (2026-11-02): a finger leaves the pointer where it
      lifted, so Chili's tooltip of whatever was under it stayed up; on the Skirmish screen a tapped map's picture as
      large as the screen ("Avalanche 3.4 / Click to download this map") covered the Next button. `bardroid_lobby_touch.lua`
      now holds the hover tooltip back from a press until the pointer moves away (its own server details unaffected).
      On the dev phone: Skirmish, 1v1, Beginner, Armada, a map tapped: no tooltip, the Start button clear; Start began
      the game. lobby-phone-test: all pass.
- [x] The lobby's Settings list did not scroll under most of a finger (2026-11-02): Chili's hit test passes over a
      line's words and the gap before its control (no handler of their own) to the window behind, so only the checkbox
      lines (their box spans the line) reached the list; a probe of the screen found the rest "main_window". When
      nothing on the hit's way up scrolls, `bardroid_lobby_touch.lua` now finds the list under the finger inside what
      was hit, by its place on the screen (a dropdown open over a list is its own hit: not scrolled through). On the
      dev phone a drag from that gap scrolled Settings to its end, no setting changed. lobby-phone-test: all pass.
- [x] The app's build menu 5 wide where the screen is wide and short (Kailil, 2026-11-02: "try 5 x 3"): its 3x3 grid was
      held by the menu's height there (the dev phone, the Fold7 folded) and left the panel's sides empty. Now as many
      columns of that cell size as fit, up to 5 (`droid.maxColls`, `tools/make-buildmenu.py`; the copy made again from
      the phone's release, test-31783): the commander's options in 2 pages of 15 where they were 6 of 9. Unfolded the
      cells are as wide as 3 allow, so it stays 3x3. pad-test -Online (RB and the D-pad in that menu): 14 of 14.
- [x] The first seconds of every game at 2-5 fps (dev phone, 2026-11-02; found below): `bardroid_touch.lua` now asks
      for BAR's 26 animated cursors while the game loads, in a game with no pregame (skirmish), at the size BAR's Cursor
      widget will pick (Kailil: "Yes whatever you recommend"): 4-7 s more on the loading screen; the first seconds then
      read "3 13 9 21 25 13 17 27 ..." frames each second where they read "2 4 5 5 5 4 21 ...", and the long Updates end
      by game frame 53 where they ran to 200. What is left in those seconds is the engine's own start.
- [x] A tap on BAR's top bar cleared the selection (dev phone, 2026-11-03): the top bar takes a press only where its
      Update saw the pointer in the frame before (`hoveringTopbar`); a finger moves the pointer and clicks at once, so
      a quick tap, or any tap in a slow late-game frame, went to the map behind the bar, which deselects (the build
      menu and unit info gone). `RtsTouch` now holds a plain tap's click until the game has had a frame with the
      pointer there (the widget's hover answer for that point; up to 250 ms, then it clicks all the same; not in the
      lobby). On the dev phone the commander stays selected after a tap on the metal bar; pad-test and
      lobby-phone-test: all pass. (BAR's own hover tooltips, as "Guard" after a tap on it, stay until the pointer
      moves: left as BAR shows them.)
- [x] The layout editor by touch (dev phone, 2026-11-03, after the tap change above): `/hud`, a tap on Unit info picks
      it, the size + steps it 108, 117, 126%, Done closes. Found there: the Unit info panel made bigger grew under BAR's
      order menu, which stays where BAR's widget puts it (right of the panel's default width; no setter), and covered
      D-Gun and Set Target. The panel now stops at the order menu's left edge and grows in height and text only; at
      126% on the dev phone the orders show whole.
- [x] The same panel made taller covered the build menu's page strip (‹ 1/2 ›): the menu's bottom was BAR's fixed 14%
      of the screen, the unit panel's default height. The app's copy now keeps its bottom above the unit panel's
      height as `WG.info` tells it (`droid.infoTall`, `tools/make-buildmenu.py`; the copy made again from the phone's
      test-31783) and lays itself out again when that changes. In BAR's game on the dev phone, Unit info at 126%: the
      menu ends above it, its strip whole. pad-test -Online: all pass. The controller game's menu is v0.8.5's and keeps
      BAR's 14% (BARGAMEPAD, at Kailil's word).
- [x] The held tap (above) and the double tap (a type's units on the screen): reviewed in `RtsTouch` (the first tap's
      wait ends at the next touch down, both clicks keep their spacing, the engine's DoubleClickTime is 350 ms) and
      tried on the dev phone, 6 Pawns given: one tap selected 1, a double tap 6. And the launcher's device lines are
      set in its own type, a step quieter, where monospace broke the low-memory sentence like a log's lines.
- [x] BAR's messages in the chat box (review of `bardroid_chat.lua`, 2026-11-03): after their 15 seconds they came back
      whenever the typing box opened (its history shows old lines), and repeated ones would push the players' lines
      out of the box's 100. They now leave the list after their time, as BAR's own Messages widget lets them go. On the
      dev phone: a chat line and a message shown together, then with the typing box open only the chat line. The dev
      phone's logs (a skirmish, the lobby) hold nothing from the app's widgets but their start lines. And the layout
      editor's buttons are near-opaque: the build menu's pictures showed through their words where the bar crosses it.
- [x] The dev phone's tests over tonight's changes (2026-11-03, 01:40): pad-test, lobby-phone-test, fp-save-test and
      pace-test all pass. A 5-minute skirmish in the low-memory mode (`tools/phone-memory.ps1`) ran through: the
      engine at 4726 MB at most where the October runs reached 5100-5150, its GPU memory 1979 MB where they had
      2390-2400 (BAR's "Cache Icons" off). And the Info panel's count on one type's picture is no larger than the
      unit's name (it was 30% of the picture, as in the grid's small cells: on the big picture it outweighed the name).
- [x] Building by touch after the held tap (dev phone, BAR's game, 2026-11-03): a tap on the Solar Collector in the
      app's build menu picked it, a map tap the spot ("spot" in bardroid_place.txt), PLACE queued it (the commander's
      queue 0 -> 1, the building still picked for the next) and the cancel button put it away ("place none"); no Lua
      error. And the Info panel leaves a cost of nothing out: a Solar Collector read "Cost 155 0", now "Cost 155".
- [x] A lobby button lit after a finger's tap (dev phone, 2026-11-03): Cancel in the Register dialog left the
      Welcome screen's "Code of Conduct" under the pointer, drawn hovered as if picked (any tap does the same where the
      finger lifts over a button). Chili hovers a control only when the pointer reaches another one
      (`Screen:IsAbove`), so `bardroid_lobby_touch.lua` now takes the hover off once the button is up, with the tooltip
      it already held back, until the pointer moves on. On the dev phone: "Code of Conduct" plain after Cancel, the
      Skirmish tab still shown as the open one. lobby-phone-test: all pass.
- [x] Spectating by touch on the dev phone (2026-11-03): a replay from the lobby's Replays tab (the benchmark's, 1300
      units at 9-11 fps), "skip", a tap on the small player list brought the spectate bar, its › followed a Grunt and
      the bar turned to the camera presets. Its buttons were BAR's panels at BAR's 70% opacity without the blur BAR's
      GUI shader puts behind its own (a blur pass more per frame on a phone), so the battle showed through the words;
      now 85% at least, BAR's look kept. (A tap 7 s after the bar opened found it closed, as designed.)
- [x] The pad's first-person legend (`bardroid_padfp.lua`, screenshots during pad-test, 2026-11-03): the D-pad read
      "UP", "DN" (and "LF", "RG" in the camera tuner) and the View button "BK"; now arrows in the D-pad's chips and
      "VIEW". pad-test: all pass. Also looked into: BAR's messages read "Battle, Started" in the chat box because
      BAR's own translation has the comma (`BAR.I18N("tips.notifications.gameStarted")` on the phone), and the big
      "BUTTON_L1" boxes in some shots are the dev phone's developer option "Show key presses", not the app.
- [x] The launcher's Display & touch preferences (Termux:X11's screen, dev phone, 2026-11-03): its last line said
      "Version 1.03.01-..." in an app that calls itself BAR Droid 0.2.0 everywhere else; it is the display server's,
      now titled "Display server (Termux:X11) version" (the app's strings override Termux:X11's, as for the screen's
      title). Its Output, Pointer, Keyboard and Other pages open; nothing else there names the wrong app.
- [x] The Unit info panel after a fold (review, 2026-11-03): BAR's order menu (layer 1) lays itself out after this
      panel (layer 0), so after a fold or unfold the panel kept clear of where the order menu had been on the other
      screen; a panel made bigger could cover its orders or stop short. It now lays out again in the first Update
      after the order menu moves. On the dev phone (no fold there): the 126% panel still ends at the order menu, 30
      fps, no Lua error. A 10-minute skirmish (low-memory mode, the game left alone) ran through at 30 fps a minute,
      the engine at 4734 MB at most. And the panel's prices are grouped as BAR's build menu beside it prints them:
      "Cost 2 700   26 000" where it read "2700 26000".
- [x] The chat box after a fold (the same review): it hangs under BAR's top bar, which lays itself out after it
      (layer -95000 to the chat's -96000), so after a fold the box went by the top bar's place on the other screen. It
      lays out once more in the first Update after a resize. The app's other panels read BAR's places when they need
      them (the pad's order cells, the touch widget's top bar, the spectate bar's player list) or follow them (the
      build menu copy, the Unit info). On the dev phone: a chat line and BAR's messages, after 17 s the chat line alone
      (40 s), with the typing box open the chat line alone. And the line box ends where its longest line does (it was
      three quarters of the screen wide for one short line); while typing it keeps the typing box's width.
- [x] Tonight's fold fixes need a resize to show: the dev phone's floating window keeps the X screen at 2008x938
      (only the frame cap changes: "[display] floating window: 15 fps cap"), so they wait for the Fold7. The laptop's
      checks that start no BAR all pass over tonight's changes (Lua lint 0 warnings in 35 files, PowerShell syntax,
      launch-bar.sh's switching, publish-check's self-test, downloader, settings merge, updater rollback, PadGame).
      GL check on the dev phone: FD740. And the launcher's device lines at 12sp: turned sideways (GL check leaves the
      launcher so) the wide layout cut their last line off under the buttons; now all of them show.
- [x] LINE and GRID by touch (dev phone, BAR's game, 2026-11-03): Solar Collector, LINE, a drag across the map: 23 in
      a line (BAR's own build drag, the building put away after it); then GRID and a diagonal drag: 75 more in a
      grid, added to the queue (Shift+Alt held: 23 -> 98), and the commander building them. And the cancel button's
      cross is a soft red: in the green PLACE panel the two dark squares looked alike (rotate stays white).
- [x] BORDER and QUEUE by touch (dev phone, BAR's game, 2026-11-03): BORDER and a drag: 54 Solar Collectors round a
      rectangle; QUEUE lit gold, then two long presses on the map: two moves added after them (54 -> 55 -> 56), drawn
      as waypoints. And the Info panel's resources leave a side of nothing out: "Metal +2, Energy +30" for a
      commander standing still, where it read "+2 -0" and "+30 -0" with a red "-0".
- [x] The spot a tap picks for a building, zoomed far out (dev phone, 2026-11-03): its ring was the building's own
      radius, a 9-pixel dot at the skirmish's starting zoom; now at least 2% of the screen's height across its
      radius (the building drawn there stays true to size). PLACE and cancel as before; Lua lint clean. Also: in
      one run a PLACE right after an install, in the game's first 20 s, queued nothing; six more (five cycles of
      pick, spot, PLACE, cancel in one game) all queued. Watch for a PLACE that does nothing.
- [x] The phone tests' files into the app (2026-11-03): pad-test, lobby-phone-test, fp-save-test and pace-test piped
      their test widgets and scripts into `adb exec-in`, which phone-bench had already dropped for scripts that now and
      then never arrived; the same lost a settings restore twice tonight. Now `toolchain.ps1`'s `Send-AppFile` and
      `Invoke-AppScript` (adb push, /data/local/tmp). pad-test -Online also switches the controller game off only if it
      was on and checks that it reads on again afterwards. All four pass on the dev phone; the setting reads as before.
      And the lobby's warning box: its title and reason are two lines apart in the box's middle (they touched, the
      box's room all under them); lobby-phone-test passes at 100% and 130%.
- [x] The lobby's hover look after a press (review, 2026-11-03): taken off a control once the button is up, it stayed
      off when a mouse then moved on over the same control (Chili hovers a control again only on reaching another).
      Now lit again once the pointer moves away from the press. On the dev phone (a scratch lobby widget moving the
      pointer, adb's mouse input does not reach the game): after a finger's tap "Code of Conduct" hovered=false, the
      pointer 40 px on inside it hovered=true. lobby-phone-test: all pass. And the launcher's log box no longer
      starts with the app's library path (`nativeLibDir=/data/app/~~...`): it goes to launcher.log only (`Log.detail`).
      Nor does the last run's end carry Android's own words ("([FORCE STOP] stop com.underarmcape.bardroid due to
      from pid 10071; reason 10, importance 100)"): the box says "force stopped", launcher.log keeps the rest on a line
      of its own ("the last run's exit: ..."); phone-bench's "ended for lack of memory" line is unchanged.
- [x] Two notifications for one game (dev phone, 2026-11-03): beside the app's ("BAR Droid / running (skirmish)",
      Stop, a tap opens the launcher) Termux:X11 posted its own while the game screen was in front: title
      "Termux:X11", high importance (the kind Android may show over the game), its preferences on a button. `BarApp`
      no longer lets it be posted (`LorieApp.onActivityResumed`); the shade shows the app's alone. pad-test: all pass.
      And its small icon (status bar, lock screen) is the app's marker in its ring (`res/drawable/ic_notification.xml`,
      white, from the public icon's drawing), where it was Android's media "play" triangle: seen in the dev phone's
      status bar with a game in the floating window.
      Its words are for players: "Skirmish running" (Lobby, Benchmark, GL check likewise), "Starting" while the engine
      starts, others with a capital, where it showed the log's "running (skirmish)" (`GameService.forPlayers`; the
      status itself, which the launcher, StartActivity and the logs read, is unchanged). Seen on the dev phone.
      That status is now the notification's title: expanded it read "Beyond All Reason" (Android's header) over a
      "BAR Droid" title, the name twice and two ways; now "Skirmish running" under the header (the app's name stays
      the App name item's). Its Stop, tried during a skirmish: the engine exits (137), no game process left, the
      notification gone. A tap on it while a game runs now goes back to the game, as the app icon does (it opened the
      launcher, the game left in its floating window); otherwise the launcher. On the dev phone: a skirmish sent
      Home (floating window), the notification tapped: the game full screen again (GameActivity focused). Seen on
      the way: launcher.log's X screen read 936x2013 for a moment before 2008x938 again (the window's way out of the
      floating window), and the game took a resize for it, 373 ms (`Game::ResizeEvent`) for the size it already had.
      `GameActivity` now keeps the X screen as it is out of the floating window until the window lies its way again
      (1 s at most). On the dev phone, Home and the notification again: no upright size, no resize in the game, the
      game full screen as before. pad-test: all pass. (Review: back in the floating window within that second, the
      hold's end would have let the X screen follow the floating window; it stays frozen there now. On the dev phone
      the notification tapped, Home 0.4 s later: 2008x938 throughout, no resize in the game.)
- [x] The start screen's line under the icon (the app icon's way to the lobby, dev phone, 2026-11-03): "checking for
      BAR updates" with a capital now, and in landscape centred under the icon (the icon is the window's background,
      centred on the whole window; the line was centred beside the navigation bar, ~70 px to the left).
- [x] GL check's answer (dev phone, 2026-11-03): the button ran glxinfo and came back to a launcher saying "Ready",
      the answer only in the log box far below. The launcher now says it under Ready: "GL check: FD740, OpenGL 4.3,
      Mesa 27.0.0-devel" (`GameService.glCheckNote`, from launch-bar.sh's `$BAR/logs/glcheck-<driver>.txt`; without a
      renderer "no OpenGL from the GPU", without this run's file "no result"; the full answer stays in the log).
- [x] A game's result lost at its end (dev phone, 2026-11-03): when a game ended, the app's own closing of its screen
      reached `GameService.onTaskRemoved` as a removed task, logged "game removed from recent apps: closing" after
      every game, and with the service's end (onDestroy) turned the result into "stopped": a lobby that failed to
      start brought the launcher back to show why, and it said "Ready". Now the app's own closing is no swipe
      (`displayClosedByApp`), the service ends after every game (no "Game ended" notification left), its end keeps
      the result, and the launcher reads a plain "game ended" as Ready. On the dev phone: GL check (game ended, its
      line, no notification left), the notification's Stop (engine 137, "stopped", notification gone), a game
      swiped away in recent apps (closed as before). pad-test, lobby-phone-test: all pass.
      Then a lobby that fails at once, made with `files/bar/dev-env.sh` = `exit 3` on the dev phone: the launcher came
      back saying "Installed, game ended with an error (3)"; now "Game ended with an error (3): the log below says
      why". (That test start was a pending lobby update's first: the updater took it for a broken update, rolled
      the lobby back and listed it bad. Undone the same minute: the bad entry out of `files/update/state.properties`,
      `lobbyFailedFast` back to false, the update started again; the Benchmark, which the updater does not judge,
      for the wording's check. A fake failure for a test goes through the Benchmark or GL check, never the lobby or
      a skirmish with an update pending.)
- [x] Share logs on the dev phone (2026-11-03): a 1.7 MB zip of the logs (launcher, infolog, the engine's kept logs)
      and Android's share sheet; backed out, nothing sent. And two settings in the launcher's own words: the frame
      cap's third choice "No cap (runs hot)" beside "30 fps" and "60 fps" (it read "none (runs hot)"), the keyboard
      shortcuts' "Off: Android's own" as the other settings say what off does (it read "off = Android's").
      (The launcher's settings column scrolls back up fine: a test of mine had queued its drags in one shell line.)
      The start screen's centring reads the system bars through Android 11's insets API, the old stable insets kept
      for Android 9 and 10; centred under the icon in landscape as before.
- [x] The Benchmark button's answer (dev phone, 2026-11-03): BAR's benchmark ran ~3 minutes and came back to a
      launcher saying "Ready", its numbers only in the game's log. Now under Ready: "Benchmark, ms per frame: Sim 35.21,
      Draw 17.00, Update 7.97" (`GameService.benchNote`, the last of each line in infolog.txt as phone-bench reads
      them; "no results" if the game ended before them). phone-bench's own reading is unchanged.
- [x] publish-check over the tracked files (2026-11-03, after the night's commits): all pass (the commits' e-mail
      address a NOTE, the History item's). CHANGELOG.md's 0.2.0 caught up in players' words: the build menu up to 5
      wide (it said a 3x3 grid), BAR's messages in the chat, the top bar and spectate bar taps, the one-type unit
      info, the lobby's leftover tooltips and Settings scrolling, the first seconds' stutter, ~400 MB less graphics
      memory, GL check and the Benchmark answering in the launcher, one notification that returns to the game. README:
      "30 / 60 / no cap", the bigger unit info and the build menu. The in-game typing box looked over on the dev phone:
      nothing to change.
- [x] BAR's Settings did not scroll by finger (dev phone, 2026-11-03): its list (and BAR's key bindings, changelog,
      game info, team stats, widget list) scrolls with the mouse wheel only, and a finger's drag there was a left drag.
      `bardroid_touch.lua` now answers 2 while one of those windows is open, and `RtsTouch` sends an up or down drag
      there as wheel steps (one per 8% of the view's height: the list follows the finger), a sideways drag as before
      (the sliders). On the dev phone: the Settings list scrolled from Graphics Quality to Advanced Map Shading with
      the finger; Darken map dragged to 0.23 and back to 0.00 (left as it was); pad-test, lobby-phone-test: all pass.
      The laptop's touch-widget-test expects 2 for the open window now (not run: BAR on the laptop needs Kailil's yes).
      The other windows take the wheel only over themselves: a vertical drag beside BAR's Statistics zoomed the map
      behind it (mean pixel change of the map 75.9). `bardroid_touch.lua` (last in line) now takes a wheel no window
      took while one is open and the fingers are the input (a mouse keeps BAR's way): beside and inside Statistics
      0.3 (noise), Settings scrolls as before. CHANGELOG and README say so.
- [x] A game's end by touch (dev phone, 2026-11-03, a skirmish lost: the commander self-destructed): BAR's Awards
      window, "Defeat!" in the chat; its Leave works by tap. But 12 s later the game closed itself: BAR's Autoquit leaves
      an ended game unless the pointer moves, and says so only in the console ("Move mouse to postpone"), which the
      phone never shows. `bardroid_chat.lua` now puts it in the chat box for those seconds: "Leaving the game in 12 s:
      tap the screen to stay longer" ("move the mouse" with a mouse). On the dev phone a tap on the window's empty part
      kept the game: still running 19 s after its end, the line gone after its 12 s. pad-test: all pass.
      The end screen's Show Graphs works by tap too (BAR's Statistics with the game's graphs). And the line now goes
      the moment the pointer moves (it stayed after the tap that kept the game, then untrue); seen on the dev phone.
- [x] The top bar's Save and Quit by touch (dev phone, 2026-11-03): Save writes the game (2.6 s, 6.9 MB, the game at
      1 fps meanwhile) and the selection is gone after it; the same with `savegame` sent from a widget and no finger
      at all, so it is BAR's or the engine's own, not the touch (a probe: no press reached the map). Quit asks first
      (Stay / Resign / Quit, under BAR's blur): Stay resumes the game, the selection kept; Quit ends it. The test
      saves were removed from the dev phone. Nothing of the app's to change.
- [x] The layout editor's buttons with a panel picked (dev phone, 2026-11-03): one row of 12 buttons, wider than the
      room beside the build menu, was centred on the screen and crossed the build menu's second row. They now wrap to
      the room the panels leave in the middle of the screen (if that is half the screen at least), a "- value +"
      never split: Unit info's in two rows right of the build menu. Size + (108%), Reset (100%) and Done by tap in
      their new places; lint clean.
      And a panel's label sits as a tab on its top edge, outside, where that is on the screen and on no other panel
      (inside it covered the panel's first line: the order menu's Fire at will and Hold pos); else in its corner as
      before. On the dev phone the order menu's and the player list's labels moved above them, the rest stay.
      Android's Back in a game, tried on the way: Escape, the first press clears the selection, the second does nothing.
- [x] The spectate bar after a lost skirmish (dev phone, 2026-11-03): the player is a spectator then, the bar comes up
      from the player list, and its player arrows did nothing without a word (no human player in the game: an AI has no
      camera to follow). They now read "No player cams" in grey; Free, Follow unit and Group as before. fp-save-test
      and lobby-phone-test: all pass.
- [x] A quick flick in BAR's Settings (and its other windows) was still a left drag (the drag ended before the touch
      widget had answered for the point); it scrolls as a slower drag does now (dev phone, a 60 ms flick). The layout
      editor's labels try the panel's bottom edge too, and its right end where the left is blocked: the chat's label
      sits under its bottom right (it covered "Battle, Started"), the top bar's under its right end (it covered the
      metal figures). The lobby's server bar (Close, Previous, Next, Join) looked over during lobby-phone-test: as it
      should be.
- [x] The end-of-game line counts down ("Leaving the game in 11 s", then 4 s; dev phone). And phone-bench over the
      night's widget changes (chat, info, touch, layout editor; 2026-11-03 08:41, warm, thermal 0): Sim 49.4, Draw
      23.05, Update 10.49 ms per frame, x0.43, against last night's 52.3-54.3, 24.97-26.37 and 11.28-11.39: no cost
      from them (the GPU memory and cursor work of the evening, if anything, a little less).
- [x] The minimap by touch (dev phone, 2026-11-03): a tap brings the camera there, a drag leaves it where the finger
      ends, a long press gives a move order there (BAR's right click on the minimap). And the Info panel for a
      building under construction: its bar was its health, orange as for a damaged unit ("64 / 340 18%"); now the
      building's progress in blue, "Building 18%", and its health in green once it stands (a Solar Collector, seen
      both ways).
- [x] The touch widget's "map or interface" answer after the pointer rested on the interface (dev phone, BAR's game,
      a Bot Lab selected, 2026-11-03): ten seconds on the build menu and the answer turned to map there and on every
      other spot of the interface a finger touched next, until one touched the map (an old fallback: "no IsAbove for
      300 updates: the map"; a widget that claims the pointer keeps the touch widget from being asked at all). Now
      not asked is interface (or 2 with a BAR window open), and map only with the interface hidden (F5). Measured
      before and after: a cell, 15 s, then the menu's empty area: 0 before, 1 after; the map stays 0 after 15 s;
      BAR's Settings stays 2. The cyan arc on the build menu (the last runs' screenshots) was BAR's Guard cursor: the
      pointer left over the factory itself. And the launcher's map and worker fields at the settings' 14 sp (the map
      name stood out at 18 sp).
- [x] BAR's player list, small (`bardroid_players.lua`, names only, scale 0.65; dev phone, 2026-11-03): an AI's name
      ("SuperKitowiec (AI)") ran under an icon at the list's right end: BAR's map marks eraser (Clearmapmarks
      button), which sits in the screen's bottom right corner, where BAR's own list has empty columns. The small list
      now keeps BAR's chat column where it draws nothing (no other player, or spectating): an empty corner as wide as
      the eraser. Found on the way, a real one: BAR numbers the list's columns in the order it sorts them into, not in
      its modules table's, and the widget read them in the latter: the small list kept rank, country, share and chat
      (the orange chevron was the rank), and the "player's own" columns it put back were scrambled (opened: income
      and chat on, resources, share and ping off), and BAR saved them so at every game's end. Now each column's
      number is found once a game (switched and back), and a saved config of the old reading gives way, once, to
      BAR's default columns (config version 2). Checked on the dev phone with a probe of all 14 columns: small
      name + chat, opened BAR's defaults, the same in the next game after a clean quit.
- [x] The player list's settings at a game's end (review of `bardroid_players.lua`, 2026-11-03): BAR saves every
      widget's config before any widget's Shutdown, so the widget's "give the list back" in Shutdown came too late and
      BAR kept the small list (scale 0.65, names only) as the player's own after every game. Now done in the widget's
      GetConfigData, which BAR calls just before its list's (layer -5, -4); a save in mid-game (a widget switched on or
      off) gets the list small again at the next Update. Dev phone, after `/quitforce`: BAR's file says scale 1 and
      BAR's columns; the next game starts small and opens to them. pad-test and lobby-phone-test after the day's touch
      and player list changes: all pass. And the Info panel's health bar a deeper green to red (white figures on
      full green were hard to read), the building bar a deeper blue.
- [x] Simulation offload for low-spec phones, a study for BAR's devs (Kailil, 2026-11-03: "try the simulation skipping
      anyways I want to give the results to the devs ... the phones rely on other players to keep them sync and get the
      math from them"). Recoil is lockstep: every client simulates every frame and is checked for sync; only commands
      travel; no past frames are kept. Offline experiments only, never online, never in the shipped app. Steps: (1)
      where the phone's sim time goes at late-game sizes (`phone-bench -Profile gadgets`, the engine's own timers); (2)
      what a phone would receive instead of simulating: BAR's save of a late game on the phone (size, save and load
      time) against the command stream (`tools/demo-rate.py`); (3) a snapshot-sync try from savegames (one device
      simulates, the phone loads its states); (4) whether a modified engine build for a real skip is feasible here;
      (5) a write-up with the numbers (docs/research/), Kailil hands it on. Dynamic resolution when hot: declined
      (Kailil, 2026-11-03: "No res reduction"). Step 1 done (docs/research/sim-offload.md): in the benchmark's ~1 300
      units the phone simulates at x0.40; BAR's synced Lua is 11.1% of the running time, about a sixth of the
      simulation, the engine's own work the rest. Step 2 done: a 1 226-unit state is 11.3 MB saved (77 MB in memory),
      12 s to write on the phone, 2.5 s to load; a busy online game's command stream is 4-7 KB a game-second (whole
      states about 2 000 times that: for catching up, not for play). The study's scratch saves and widget removed.
      Steps 3 and 4 written up from Recoil's source: a save is applied only while a game starts (`CGame::Load`), so a
      running phone cannot take a state (each would be a 69 s restart); a real skip is engine design work (deltas,
      commands against a world the client did not compute, another sync check); near-term: a late join or reconnect
      from a recent save. Catch-up times added from Kailil's own late joins on the Fold7 (x2.0 at 2 400 units, never
      past ~5 000). The write-up is complete for Kailil to hand on.
- [x] The pad's interface looked over during pad-test -Online (dev phone, 8 screenshots, 2026-11-03): the even order
      menu with the commander (4 + 4 + 3), three Pawns (2 + 2) and a Solar Collector (one row of 2), the "COMBAT UNITS:
      3" note, QUEUE gone while the pad is the input, the map marker's chat line; all pass. Nothing to change. (The
      "BUTTON_R1" box in two shots is Android's own "Show key presses" on the dev phone, left as it is.) And both menu
      copies' patches, applied as the phone does, still give the shipped files byte for byte.
- [x] Building by touch after the order menu copy (dev phone, BAR's game, 2026-11-03): PLACE covers the app's order
      menu copy exactly, QUEUE lit gold. A tap on the Metal Extractor left two of BAR's texts over the app's panels:
      the build menu's tooltip (the finger's pointer stays on the cell; it covered the next row) and BAR's Screen Mode
      Info ("Screen mode: Resources ...", drawn at 21% of the screen's height in the middle: over the order menu, and
      over PLACE). The tooltip now shows to a mouse only, as it already skipped the pad (the info panel says the
      same); BAR's Screen Mode Info off in launch-bar.sh with the other hints that clash on a phone (the metal view
      itself is the engine's and stays). Seen clean after; launch-bar-test: all pass.
- [x] The same in the controller game (the launcher's Play vs AI; dev phone, 2026-11-03): with fingers its menus are
      v0.8.5's, which the copies' patches do not reach, so a tapped Metal Extractor's tooltip still covered the build
      menu's next row and a tapped Move's stayed over Reclaim, Place Blueprint and the player list until the next
      touch. `bardroid_touch.lua` now wraps BAR's tooltip API (`WG.tooltip.ShowTooltip`) while the fingers are the
      input: no build menu tooltip, an order's for 2.5 s after the pointer came to rest, as the copies do; a mouse and
      the pad keep BAR's way, v0.8.5 itself unchanged. Seen: Move's tooltip at 1 s, gone at 4 s; none on the
      extractor; no errors. And the unit info panel's largest text a sixth smaller (panel height / 7.4, was 6.2): a
      Metal Extractor's text was 1.5 times a Commander's, the largest on the screen; its description fits one line
      now, the Commander's (already below the cap) unchanged. And the BAR top bar's cut-off "Wasting metal" banner
      (`docs/upstream/bar-topbar-warning-banner.md`) is still in BAR's current code (test-31777). Three Python bytecode
      files committed by mistake in fc0bb4a (`tools/__pycache__`) untracked, `__pycache__/` in .gitignore.
- [x] The launcher's row of small buttons (dev phone, upright, 2026-11-03): each sized its own label, so "Benchmark"
      ran from edge to edge of its button (2 dp of padding kept it the size of the others). The five now share one
      size, the largest at which every label fits inside the launcher buttons' usual 6 dp padding
      (`LauncherActivity.fitRow`, again when the row's width changes). And a review of the unit info panel's
      recordings (cfcc568: keys, the oldest dropped after 8, the bar live or recorded, the grid): nothing found.
      lobby-phone-test: all pass.
- [x] The launcher's settings scrollbar ran over the long settings' line ends ("... Off: Android's own", "... where
      plain"; dev phone, sideways and upright, 2026-11-03): it has a 10 dp margin of its own now, out in the screen's
      edge (the settings at first ended 10 dp short of the buttons above: "Save settings" no longer lined up with
      "Lobby"; now both end where they did). The day's launcher logs looked over: only BAR's and the engine's own
      warnings; the one odd exit ("INVALID START", killedByAm) is Android cancelling a start in the middle of an
      `adb install -r`. The launcher's top row the same way as the small one ("Install / Update" nearly touched its
      edges: the button's shape sits 4 dp inside the view, so the 6 dp padding left 2 dp one could see): both rows
      one size each, 9 dp of padding (5 dp of air at the edge one sees); seen upright and sideways. The shape strip's
      ONE, LINE, GRID and BORDER (BAR's game, dev phone) were a size smaller than the page strip's "1 / 2" they stand in
      for (half the strip's height): now the page strip's size, BORDER still inside its button. And `java-checks.sh`
      (CI's Java checks) failed to compile: PadGameTest checks BuildMenuPatches, which `padgame-test.ps1` compiles
      and the script did not; now the same sources, all four pass. The order menu copy's "Place Blueprint" (the one
      label sized by its width) ran to its button's edges: a label sized by its width keeps 4% of the button at each
      end now, the others (sized by the row) unchanged; both copies' patches apply to test-31777 and test-31783. CI's
      other checks run locally: the PowerShell tools parse (27), publish-check -SelfTest passes. pad-test -Online
      after that change: all pass (the copy runs, 11 orders one cell each). Placing a factory by touch: on a crater's
      slope the ghost is red and PLACE stays dim; on flat ground PLACE lights, the commander goes and builds, the plant
      stays picked for the next. QUEUE off and lit looked over: nothing to change. A game's start looked over
      (launcher, ~3 s of black while the X server and engine start, Recoil's splash, BAR's loading screen): right
      after Play the launcher read "Installed, idle" for a second or two (the service busy, its status still the last
      game's word until the update check); it says "starting (skirmish)" at once now. The notification had the same
      first word ("Idle", posted before the work began): the service sets "starting" (or "installing") before it goes
      up, and shows it as "Starting" like the engine's start; titles sampled during a start: Starting, Update:
      checking for BAR updates, Starting X server, Skirmish running. The launcher's status line says the same in the
      same words now ("Skirmish running", "Installed"; it said "Installed, running (skirmish)", "Installed,
      installed"), and follows each of the service's steps at once (it read "Ready" for up to 1.5 s after Install /
      Update; at 0.3 s now "Update: checking for BAR updates"). A review of those changes: the status line now
      refreshes on each service line, at most ~10 a second while a download reports (every 2 MB), three small file
      reads each: fine. The installer's steps in players' words too ("Install rootfs: downloading Debian ..." ->
      "Installing: downloading Debian ...", "Install done: Installed (100%)" -> "Installed"; "Install failed: ..."
      kept), checked on twelve of the service's statuses with a copy of `forPlayers`. That check is a real one now:
      the words moved to `StatusText.java` (no Android classes), `tools/status-text-test.ps1` (19 cases, in
      laptop-tests) and `java-checks.sh` (CI) run it; all pass, and the notification still reads "Skirmish running"
      on the dev phone. A Wind Turbine by touch at the corner start (the spot, PLACE, the commander builds it: +42
      energy); the chat box's BAR messages ("Battle, Started" is BAR's own caption; "Idle Constructors") and its hold
      on `WG.messages.addMessage`, given back in Shutdown: fine. The info panel's grid (several unit types) not yet
      seen: a box drag at that zoom took the commander only, BAR's Ctrl+A the idle constructors (and a QUEUE tap on
      a fresh turbine missed it: the spots differ by start position). The launcher's log lines ran along their box's
      left edge: 6 dp of padding inside it now. The info panel's grid reached with a scratch widget on the dev phone
      (the commander ordered to build, then the team selected; removed after): a commander and a Wind Turbine, each
      with a big "1" on its picture. A count shows only above 1 now, as BAR's Info widget prints it. (A second try
      for counts above 1, four builds ordered by the scratch widget at the corner start, built none in 3 minutes:
      the commander stood idle; that path is unchanged.) And the unit info panel had nothing for a map feature (a
      wreck, a tree, a rock) under the pointer, where BAR's Info widget, which it replaces, shows its name and what
      reclaiming it gives. It shows them now (nothing selected): the name, "Reclaim" with metal white and energy yellow
      as the Cost line, a wreck with the picture of the unit it was, anything else text only. Dev phone, a scratch
      widget putting the pointer on the nearest feature (removed after): "San Pedro", "Reclaim 100". (A wreck's
      picture not yet seen: the scratch widget that would make one did not run.)
- [x] Navigating past the map's edge by touch (Kailil, 2026-11-03: "I want it to feel just like normal navigation when
      I push my finger around the outside of the map edge ... super inconvenient right now"). A drag over the void moved
      the map the right way across but the wrong way up and down. `bardroid_touch.lua`'s planePoint (the void's ground
      point: the view ray met with the level plane) passed `vsy - y` to `Spring.GetPixelDir`, which counts y from the
      top as X does (TraceScreenRay counts from the bottom): every void row was mirrored. Logged on the dev phone with a
      scratch widget (removed after): pixel rows near the top of the screen gave plane points by the camera. Now the
      void follows the finger as the map does (dev phone, the corner start: 200 px down moved the map 208 px down,
      200 px up 218 px up, 300 px across 284 px across); a pinch's pivot over the void comes from the same function.
      touch-widget-test's edge case now drags across and up and checks that the grabbed point stays under the finger
      (an across-only drag never showed it); not run: BAR on the laptop needs Kailil's yes. And a drag that crosses
      the edge (on the map at one end, past it at the other) takes both ends on the level plane at the map end's height:
      it met the map point with a plane point at the height the camera looks at, a jump where the edge's ground stands
      higher or lower. Dev phone: map to void 320 px up, the map edge 268 px up; void to map 400 px across, the edge
      264 px (the edge is farther than the finger's row); both with the finger. And a drag over the sky (a camera tilted
      up to the horizon) moved nothing: no ground point, no plane point. It now moves the map as the same drag made in
      the middle of the screen would. Dev phone, a scratch widget tilting the camera at the corner start (removed
      after): a drag down over the sky at the top right pulled the camera back (its target 221 -> 202), where it
      stood still before. The review of the edge path found the rest sound: a fling glides from the middle of the
      screen, the void answers "map" for taps, a pinch's pivot over the void comes from the fixed function. A pinch over
      the void checked on the dev phone without two fingers: a "zoom 1.6" line with its pivot over the void appended to
      the touch log (`bardroid_touch.txt`, as the app writes it): the map's edge went from 180 to 278 px off the pivot
      (x1.54), the void under the pivot stayed. (Lines appended to that file drive the touch camera from adb: pans,
      pinches and twists for any later phone check.) That is a phone check now: `tools/touch-phone-test.ps1` (~2 min,
      dev phone, nothing on the laptop) runs a test widget that appends the app's pan and zoom lines and checks the
      point under the finger: a drag on the map (0 off after 356), over the void across and up (0 off after 1402), a
      pinch over the void (0 off), a drag from the map onto the void (241 off after 2748: the engine lifts the camera
      over the terrain on so long a move), a drag over the sky (moves). All pass. (Its first version dragged from the
      void onto the map: that brings the void's point near, a camera past the edge, and the edge's clamp held it.)
      It covers the rest of the finger camera too now: a pinch on the map (0 off), a twist (0.3 turns by 0.300),
      fingers down tilt (rx 1.900 -> 2.065), a pinch far out stops at the widget's limit (16 380 of 16 380); all 9
      pass. (The launcher's Display screen, Termux:X11's own preferences, looked over: clean, left.) After the day's
      touch changes: fp-save-test, pace-test and lobby-phone-test on the dev phone, all pass; the lobby widget's server
      bar (Close, Previous, Next, Join) and both warnings (first person, touch and gamepad) looked over in screenshots
      taken during lobby-phone-test: text inside its box, OK clear of it; nothing to change. An 8-minute skirmish on
      the dev phone after them: 29.9-30.0 fps each minute after the first (its load, 29.1), no error or warning from
      the app's widgets in infolog, LuaUI's memory up and down by the low-memory mode's own collector notes. The AI
      never came in those 8 minutes: does it play on the phone? It does: BARb initializes ("BARbarIAn 1.6.28 (0)
      Initialized!", the arm64 AngelScript stub preloaded) and, counted by a scratch widget with cheats and global line
      of sight (removed after), had 19 units at 3:30, 24 at 4:00, 26 at 4:30; on the low-memory mode's smaller map it
      had not reached the player's base by 8:00. Its "Script: '...' not found!" lines are BAR's own script's optional
      hooks. (A note for scratch checks: the phone's toybox grep takes no `\|` in a basic pattern; `grep -E 'a|b'`
      does. The earlier "wreck" scratch widget had run; the repository's tools use no `\|`.) Its turbine was built
      and self-destructed, but a self-destruct leaves no wreck there (the map's 320 features stayed 320). Shot down by
      the commander instead it left `armwin_heap`: with the pointer on it the panel shows "Wind Turbine Debris", the
      turbine's picture (BAR's `customParams.fromunit`) and "Reclaim 10" (dev phone; the scratch widget removed
      after). And the grid with a count above 1 seen at last (the grid scratch widget had queued every building on one
      spot, TestBuildOrder knowing nothing of the queue; spread out, 5 built): four Wind Turbines with "4", the
      commander and a Solar Collector with none. The grid by finger (units given by BAR's cheats in a scratch widget:
      seconds, not minutes; removed after): a long press on the Solar Collector dropped it (armcom 1, armwin 4), a tap
      on the turbines kept only them (armwin 4), the panel then "Wind Turbine" with 4 on its picture. And 17 types
      selected (two each of 16 Armada units given, and the commander): 6 x 3 cells in the middle of the panel, each
      with its count, the commander's none; nothing to change. A big army (300 Pawns given): 29.9 fps with none
      selected and 29.9/29.8 with all 301 selected (the 30 cap holds; no error from the app's widgets), but in the grid
      "300", at a single digit's size, covered most of the Pawn's picture: a count is now no wider than about a third
      of its cell (BAR's Info widget shrinks long counts too); one or two digits keep their size. With 300 Pawns
      and 30 Construction Bots (331 units, 29.9 fps, no error): the one-type views "Pawn" with 300 and "Construction
      Bot" with 30 on the picture, the counts inside it; the idle-builders button's 30 reads. (The bots' queued
      turbines fell off the map at that start: the queue drawing with many builders not seen.) Placed on the map, 120
      turbines queued by 30 bots: the bots went to build, no error. In that scene the build menu showed the Wind
      Turbine greyed out for the Construction Bots: BAR's own build blocking (`api_build_blocking.lua`, a synced
      per-builder block the app cannot set); at the game's start only the geothermal buildings are blocked (the map
      has no vents), so BAR added it on the way. Not the app's; noted in case it is seen in play. And in the
      controller game (the launcher's Play vs AI) a finger's drag that started on v0.8.5's order or build menu panned
      the map (106 px for a 310 px drag up from Set Target; 80 px for 220 px on the build menu): v0.8.5's menus answer
      no IsAbove (the app's copies in BAR's game do). `bardroid_touch.lua` now counts their rects as interface (the
      order menu's `getPosition`, the build menu's `getSize` with the width its code gives it, not while the app's own
      build menu has its place or it sits at the bottom): the same drags leave the map where it was, the press picks
      what it starts on (a build option: PLACE), as in BAR's game. touch-phone-test checks it now: the pointer on
      the order menu and on the build menu answers interface, on the map map; all 12 cases pass. BAR's idle builders
      button and unit groups (bottom right) answer no IsAbove either, and a drag up from them pans the map; counted as
      interface too, the drag from the idle builders button lost the selection and left the commander no longer idle
      (they act on the press and have no MouseRelease: the release landed on the map). Left panning, the lesser harm;
      the menus keep their fix. Checked with a scratch widget logging the selection, the active command and the
      commander's orders (removed after): a drag from the order menu's Move leaves no command and no order (a tap on
      Move picks it), the selection stays; a drag from the build menu picks the option it starts on. The lobby by
      finger on the dev phone (offline: the tests' login wait widget, removed after): the login dialog's Cancel, then
      Skirmish, Next through game type, difficulty and faction to the map choice, each tap taken; no lobby widget
      error. Stopped at the map (a pick can download a large map onto the 8 GB phone). A review of the menu change:
      in BAR's game the build menu is the app's copy, which the layout editor can move and size, and the new rect
      (BAR's width at the left edge) could have taken a map drag beside a moved menu for a menu drag; the copy answers
      IsAbove itself, so the rect is now for other build menus only (v0.8.5's). The order menu keeps it (the copy is
      not movable). (`droidCells` marks no copy: v0.8.5's packaged order menu has it too.) touch-phone-test in both
      games: all pass. Checked with the menu moved (BAR's game, a scratch widget driving the layout editor's own
      press/move/release, the move reset after): the menu from x 0-707 to 700-1407; the pointer at its old place
      answers map, at its new place interface; the next game has it back at its default place. pad-test and pad-test
      -Online after the menus' answers changed (the pad reads them too): all pass. touch-phone-test at the Fold7's
      unfolded shape (the dev phone at `wm size 1968x2184`, reset after; interface scale 1.0): all 12 pass; the drag
      from the map onto the void drifts more there (688 off after 3032, folded 241 after 2748: the engine fits the
      camera's height to the ground under its new target on so long a move; inside the check's quarter). The HUD at
      that shape in the controller game looked over after the day's changes: the app's own panels (unit info, QUEUE,
      the order menu's place) fit; what does not is the open "Touch HUD on the Fold7 unfolded" item (Kailil's call),
      unchanged. Spectating after the day's touch changes: a skirmish's replay on the dev phone through the app's
      replay benchmark (`.bardroid-bench-replay`, removed after; no dev-env.sh needed): a tap on the small player list
      brings up the spectate bar, a drag pans the map, 30 fps, no error from the app's widgets; "Follow unit" follows a
      Pawn (the bar turns to the camera presets), and the camera goes on following when the bar goes with the player
      list closing by itself (the bar shows while the list is open, by design). After the day's commits:
      `publish-check -NoHistory` (no private data, keys or BAR artwork tracked; only the known e-mail NOTE), luacheck
      (36 files), java-checks (5) and launch-bar-test: all pass. And placing a
      building by touch in the controller game checked (a Wind Turbine: the spot, PLACE lit, PLACE, the commander off
      to build it), pad-test and fp-save-test on the dev phone: all pass. (An `am start` sent right after
      `adb install -r` can be lost while Android restarts the app: the tools never do that; noted for whoever scripts
      it.)
- [x] Spectating by touch after the day's player list changes (dev phone, a skirmish's replay started through a
      temporary `dev-env.sh`, removed after; 2026-11-03): a tap on the small list brings up the spectate bar ("No player
      cams" dimmed, Free, Follow unit, Group), the list small as a spectator, no errors. The touch widget's 0.6% of the
      benchmark looked over: nothing in it stands out after its two earlier rounds; left.
- [x] The unit info panel costs 2.0% of the benchmark's time (BAR's widget profiler on the dev phone, 2026-11-03 12:56;
      all of the app's widgets 3.1%, BAR's busiest shown 1.25%): its DrawScreen and Update. Likely the pointer resting
      over the battle, units drifting under it: the panel switching between units and nothing, re-fitting its text and
      re-recording its drawing at each switch. Measure that first (count the switches and fits a minute), then keep
      the fits per text, or with fingers stop following what drifts under a pointer that came to rest. Measured (timers in a
      scratch build, BAR's benchmark on the dev phone): the text fits were cheap (2-18 ms each 20 s); the cost was
      recording the panel's drawing, ~27 ms each, its text the bulk (text recorded into a display list is slow on the
      phone; drawn as it is, ~0.15 ms), about 1.5 a second as units passed under the pointer and health changed:
      734-985 ms each 20 s. Now a unit's picture and text are recorded once per text and kept (the last 8) and the
      health bar is drawn as it is while its numbers change, recorded once they stand still a second: 60-220 ms each
      20 s in the same battle. Description and stats print in one pass of the font. Looks as before (dev phone).
- [x] phone-bench after the day's changes (dev phone, 2026-11-03 12:43, the controller game: the order menu copy stands
      down there): Sim 52.58, Draw 26.01, Update 11.23 ms per frame, x0.40, in last night's range (52.3-54.3,
      24.97-26.37, 11.28-11.39; this morning's 49.4/23.05/10.49 ran cooler: prime CPU cap 1843 against 1708 MHz now).
      And a review of the order menu copy: BAR draws a row's first button with the edge margin by its number
      (`cell % cols == 1`, four places in its code), which rows of fewer buttons do not follow (10 orders: 4 + 3 + 3,
      the third row's first two buttons a few pixels off); the even layout now shifts those rects by the margins'
      difference instead of patching BAR's four places. Seen on the dev phone for 7, 6 and 4 orders (Construction
      Aircraft, Construction Bot and Vehicle, Pawn, Rocko: 4 + 3, 3 + 3, 2 + 2), which need no shift.
- [x] fp-save-test and pace-test on the dev phone after the day's changes (2026-11-03): all pass. And the order menu's
      tooltips by touch without the keyboard hotkey in front ("; - Set how far out of its way ..."): the copy names no
      key while the input is fingers (a mouse and keyboard keep BAR's).
- [x] Late game on the Fold7: memory or heat? (Kailil, 2026-11-03: "a way to clear ram usage as the game enters late
      game ... repeating over and over ram dumps"). His online game of 2026-11-02 22:07-22:31 (launcher.log `[perf]`,
      `[bardroid-perf]`): memory available 650-950 MB the whole game, 6.3-7.6 GB of swap free, the engine 1.0-1.6 GB
      resident, nothing killed: memory never ran short. What fell was the heat budget: thermal status 0 -> 3, the GPU's
      clock cap 1200 -> 525 -> 342 -> 160 MHz (thermal level 14), the CPUs held at 960-1017 MHz, and the frame rate 30 ->
      24 -> 16 -> 9.4 fps at 1 000-1 100 units. Clearing memory cannot help that (Android already compresses idle pages
      to swap and reclaims caches; the game's units, map and paths are in use; a forced Lua garbage collection is a
      hitch of its own, more CPU and heat). What can: less work per frame when hot (render resolution, the cap), a
      cooler phone. A note for Kailil, no change.
- [x] The portrait dock (bardroid_portrait.lua, Kailil's layout D, 2026-11-09): BAR's top bar upright. Its metal and
      energy bars need about 1600 pixels at a readable size and ran over its menu buttons; the dock hides them through
      BAR's own `WG.topbar.setResourceBarsVisible` while it is up and shows metal and energy itself. What is left over is
      BAR's wind gauge, which BAR places by the screen's width while the buttons move: over "Statistics" at interface
      scale 1.0, over "Save" at 0.8 (tried, back to 1.0: it only made everything smaller). Done 2026-11-09: BAR's top
      bar has a setter after all, `WG.topbar.setIndicatorsVisible` (wind, tide, the commander counts): off while the
      screen is upright, and the dock's energy panel shows the wind as BAR's gauge did (`%.1f` of `GetWind`). And a
      spectator upright (no dock) had the bars and indicators all over the buttons: both are off whenever the screen
      is upright now. Dev phone: a skirmish (top bar: its buttons alone; "wind 8.3" in the dock) and the 8v8 Isthmus
      replay at 5:00 (top bar: Info, Statistics, Settings, Quit, nothing over them).
- [x] Kailil's portrait list of 2026-11-09 evening, each tested on the dev phone (commits of that evening):
      the camera pad's zoom drag inverted (down: closer); nothing picked: no selection row, no groups strip without
      groups, big buttons only (LOCAL, ALL, IDLE UNITS, IDLE BUILDER, COMMANDER and BASE: the camera there, in the
      middle of the game above the dock), SELECT and FILTER with units picked only; FIGHT, MOVE, PATROL the largest
      orders (and a commander's D-GUN); a drag on the game draws units' paths and lines (BAR's right drag); TRANSFER and
      a teammate picker; metal and energy panels (BAR's conversion and share sliders, SEND to a teammate); the D-gun's
      touch sticks, FIRE and cancel; the upright loading screen's tip wrapped to the screen; the upright lobby's buttons
      in a grid at the bottom, larger. Not seen yet: the lobby's server bar over the grid online (the offline lobby
      lists no servers), the D-gun's click where the host forbids widget orders (online), anything on the Fold7.
- [x] Before the game (every online game's start: a start spot, the first buildings queued; 2026-11-09, a skirmish
      with StartPosType=2 through `dev-env.sh`, which the app's own skirmish skips): (1) PLACE queued nothing. The build
      menu copy places pregame buildings too (a tap picks the spot, PLACE is a Shift click), but BAR's pregame queue
      (`gui_pregame_build.lua`) works the spot out in its Update while the button is down, and RtsTouch's click had
      nothing between press and release: before the game the button is now held 120 ms. (2) The copy's cancel and the
      pad's B and "grid placed" called `WG["pregame-build"].setPreGameDefID`, which BAR renamed `setPreGamestartDefID`:
      the copy's did nothing, the pad's two were errors that would have taken the pad's widget out of the game. (3) The
      portrait dock showed "No units picked" there: it now shows the start unit's build options (a tap picks one for
      BAR's queue, lit as picked, the number queued on it), shapes and PLACE while one is picked, UNDO LAST and CLEAR
      QUEUE otherwise. Dev phone, portrait: three solar collectors queued on open ground (BAR's queue drawn on the
      map, "3" on the tile), UNDO 3 -> 2, CLEAR -> 0; the panel's cancel puts the building away. A spot among trees
      queues nothing, as with a mouse. pad-test and touch-phone-test ALL PASS; remake-check: both copies equal.
      Then landscape: PLACE queued too (the held click), but with no order menu before the game the panel went to the
      bottom's middle, behind BAR's "Pick your faction" panel (rotate and cancel hidden): now under the build menu when
      there is room. Upright that faction panel is under the dock: its factions are buttons in the dock's pregame right
      half (BAR's picker's own "changeStartUnit" message, its rules for RANDOM), the current one lit. Dev phone: Cortex
      picked (the left half Cortex's buildings), RANDOM, Armada again, then a building queued.
- [x] The portrait dock on the unfolded Fold7 (2026-11-09): upright its X screen is 1080x1198, 1.11 times taller than
      wide, and the dock came up only past 1.15, so "Play upright" there gave BAR's landscape HUD squeezed upright (this
      file's "Touch HUD on the Fold7 unfolded" notes). Now past 1.05; and the name, groups and resource rows are capped
      by the height too (on that short dock they took a quarter of it, the build grid got 3x2 small tiles beside a blank
      strip). Dev phone at the Fold7's 1968x2184 (`wm size`): the dock up, the grid's tiles full width, a building's
      shapes and PLACE; at its own 1080x2316 the layout as before (936x2013: 3x4 grid). BAR's wind gauge clear of its
      buttons at that width.
- [x] The portrait dock's cost (dev phone, 2026-11-09, springsettings `bardroid_portrait_profile = 1`): its drawing
      2.1-3.3 ms a frame (BAR's FlowUI panels, buttons and unit tiles drawn anew every frame), its refresh about 4 a
      second at about 1 ms. A display list of the still parts made it worse (4-10 ms, growing: FlowUI makes lists of
      its own inside, and the list was made again several times a second): reverted. Now as BAR's own menus do it:
      the panel, selection, both grids and the groups strip drawn into a texture (`gl.R2tHelper`), redrawn only when
      the lists, the layout or a scroll change, on an opaque base (the texture's panel lets the game through); the
      resource bars, PLACE and the menu-mode sparkle drawn live on top. 0.6-0.76 ms a frame.
- [x] **The dock's cost again** (2026-11-12, dev phone, `bardroid_portrait_profile = 1`, the commander picked): 1.2-1.7
      ms a frame now, upright (1.47-1.68) and sideways (1.2-1.6) alike, twice the 0.6-0.76 of 11-09. The profile line
      now also gives the texture draws and the resource panels: one texture draw per refresh (~3.7 a second, 2.3-3.2
      ms each: ~0.3 ms a frame) and the metal and energy panels, drawn live every frame, 0.8-1.0 ms a frame (FlowUI
      panels, five or six outlined prints, the wind blades turning). Next: those panels in a texture of their own,
      drawn again only when what they show changes (the numbers, the bar to the pixel, the blades by a step of their
      turn), as BAR's top bar keeps its own. Done the same day (SP.drawRes): the panels in their own texture, drawn
      again when their signature changes (the shown numbers, the bar by a two-hundredth, the wind and tide readings,
      their place), the blades and waves turning live over it. Dev phone: the dock 0.62-0.84 ms a frame sideways
      (was 1.2-1.6), 0.80-0.89 upright (was 1.47-1.68); the panels 0.10-0.18 ms, drawn again 1-2 times a second;
      they look as before, the blades turn, the wind reading follows; dock-phone-test all pass.
- [ ] Speak to chat started, cancelled and started again quickly (2026-11-09, dev phone, a virtual pad's LB + RB twice
      three times in the lobby): Android's `cancel()` answers with a late `onError(5)`. Here it came before the next
      start; had it come after, `done()` would have ended the new session (the note gone, the words dropped). The cure:
      a fresh `SpeechRecognizer` per session (`cancel()` destroys the old, so its late callbacks never arrive), and a
      new one after `ERROR_RECOGNIZER_BUSY`. Changed 2026-11-10 (`VoiceChat`: a recognizer per session, destroyed when
      it ends, and each session's callbacks numbered: a past session's late error or words are dropped and logged
      "voice chat: a past session's ... dropped"); built, not yet run with the recognizer listening, which needs a live
      microphone (the dev phone's surroundings unknown that night; the touch-log tests never open it). Test it where
      the dev phone is alone: LB + RB twice three times quickly in the lobby, then once and speak; the last session's
      words reach the chat, launcher.log shows the dropped late error. Until then the dev phone's app has the
      microphone revoked and user-fixed (2026-11-10: no test can open it); for the live test `adb shell pm
      clear-permission-flags com.underarmcape.bardroid android.permission.RECORD_AUDIO user-fixed` and `pm grant` it.
- [x] Settings' order menu options (2026-11-10, the official port: BAR's code ours to change with its devs): the copy
      declares `replaces = "Order menu"` (BAR's handler saves `replaced["Order menu"] = "BAR Droid order menu"`), and
      the change for BAR's Settings to follow that list is ready, `docs/upstream/bar-options-replaced.patch`: tested on
      the dev phone (pool swap, put back), the old config's colorize 0.7 and the copy's 0.3: Settings showed 0.7
      without it, 0.3 with it. Players get it with the BAR release that merges it. The notes from then:
- Settings' order menu options in both games (2026-11-03): BAR's Settings name the widget "Order menu" (its
      colorize, bottom position and always-show options); BAR's game runs the app's copy ("BAR Droid order menu"), the
      controller game v0.8.5's renamed "Order menu (controller)" (infolog: "Options: 'ordermenu_colorize' widgetConfig:
      unknown widget Order menu"). A change in Settings still reaches the running menu (its `WG.ordermenu` setters) and
      the copy keeps its own settings, but Settings shows the old widget's saved values. Left: it would mean patching
      BAR's Settings widget.
- [x] The order menu copy in replays of older BAR releases (2026-11-05, every engine-branch replay run on the dev
      phone, BAR test-31723's 8v8): "Error in Initialize(): ... luaui/Include/action_tap_hotkeys.lua ... File not seen
      by VFS", then "Removed widget: BAR Droid order menu": the copy (made from test-31777) includes a file that release
      did not have yet. No effect: a replay's spectator gives no orders, and `copy_removed` leaves replays out, so the
      next game still runs the copy. A live game of such an old release cannot happen (BAR's servers run the current
      one). Left as it is.
- [x] The phone's remake of the menu copies, checked (2026-11-03): the shipped `.patches` applied to BAR's files as
      `BuildMenuPatches` does give the shipped `bardroid_buildmenu.lua` and `bardroid_ordermenu.lua` byte for byte.
      `make-buildmenu.py` and `make-ordermenu.py --check` (the patches against a BAR release, nothing written) pass on
      the laptop's (test-31777) and the phone's (test-31783), and run in `laptop-tests.ps1` now, so a BAR update that
      moves a part a patch needs shows before a phone falls back. `launch-bar-test.sh` covers `order_menu`: the copy
      in, kept with an Android-layer miss when BAR's file changed, BAR's own after the copy failed in a game (the build
      menu's copy left running), the controller game off; 55 cases, all pass (its menu block had called an undefined
      `order_menu`). Since 2026-11-04 a tool does the byte-for-byte check: `tools/remake-check.ps1` (BAR's two files
      from the dev phone's release, the shipped `.patches` through the app's own `BuildMenuPatches.java`); after the
      build menu's 30 s redraw, test-31820: both copies equal. And QUEUE's label in the white of the order menu's words right under it (it was the notes' warm
      white).
- [x] The order menu copy by touch (dev phone, BAR's game, 2026-11-03): a tap on Move picks it, a tap on Fire at will
      cycles it, a drag across the menu leaves the camera where it was (the copy's IsAbove; the press picks the button
      it starts on, as BAR's does with a mouse), a long press is a right click (Hold pos back to Roam).
      lobby-phone-test after launch-bar.sh's order_menu: all pass. And an order's tooltip after a finger's tap: the
      pointer stays where the finger lifted, so BAR's tooltip stayed over the buttons beside it until the next touch;
      now it goes 2.5 s after the pointer came to rest (with fingers; a mouse keeps BAR's way). Seen at 1 s and gone
      at 4 s.
- [x] pad-test after the order menu copy (dev phone, 2026-11-03): both runs check the order menu now. `-Online`
      (BAR's released game, user widgets' orders forbidden): the app's copy runs (`WG.ordermenu.droidCells`), and
      with the pad's orders hidden the other 11 fill it, one cell each; the controller game: v0.8.5's own menu
      (`controllerApiVersion`), the copy stood down, the same 11 evenly. All pass, both. And the unit info panel no
      longer prints a description its name already says ("Armada Commander" over "Commander").
- [x] The order menu online like offline (Kailil, 2026-11-03: "Do the fix to make the orders menu behave like
      offline"): the app runs its own copy of BAR's Order menu in BAR's released game, as it does the Build menu
      (`bardroid_ordermenu.lua`, `tools/make-ordermenu.py`, 8 patches; the phone remakes it after BAR updates:
      Installer's BAR_COPIES, `.bardroid-ordermenu`, launch-bar.sh `order_menu`). In it v0.8.5's even layout while
      the pad hides orders, `WG.ordermenu.droidCells` for the app's pad controls, an IsAbove (a finger's drag on the
      menu no longer pans the map: an open risk in CLAUDE.md), and in the even layout a row of fewer, wider buttons
      keeps the other rows' text size (its labels were a third larger; offline v0.8.5's still does that). v0.8.5's
      order menu is packaged as "Order menu (controller)" (`tools/build-gamepad-game.py`: only that line of the zip
      changed), since both games share one widget list; the copy stands down in the controller game. Dev phone:
      BAR's game with the pad's orders hidden 4 + 4 + 3 filling the menu; by touch BAR's 5 x 4; the controller game
      v0.8.5's (its log line, the copy's "stands down" line). Not checked here: the laptop tests' new orders
      (touch-widget-test, ui-screenshot, profile-benchmark), BAR on the laptop needing Kailil's yes. The controller
      game's settings warn "unknown widget Order menu" for its colorize option (v0.8.5's gui_options names the old
      widget): that option is not kept there.
- [x] BAR's chat saved hidden with no input history (review of the app's Shutdowns after the order menu's, dev phone,
      2026-11-03: BAR's file said `hide = true`): `bardroid_chat.lua` gave BAR's chat back in Shutdown, after BAR's
      save. Now in its GetConfigData (layers -96000, BAR's chat -95000), taken over again if the game goes on; a config
      of an older version gives BAR's defaults back once (shown, history on). Dev phone: in game BAR's chat hidden,
      history off, as before; after `/quitforce` BAR's file says `hide = false`, `showHistoryWhenChatInput = true`;
      the next game the same. The other Shutdowns: the minimap's size is an in-memory overlay (never saved), the
      touch and low-memory ones engine settings.
- [x] The order menu's pad orders stayed hidden after a game played with the pad (Kailil, 2026-11-03: the order
      menu no longer "rearranges"): BAR saves the order menu's switch (`disabledCmd`) with every widget's config
      before any widget's Shutdown, so `bardroid_pad.lua` showing Stop, Wait, Attack, Repeat, Move, Reclaim, Repair,
      Fight and Patrol again in Shutdown came too late, and every game after one that ended normally with the pad in
      use had them hidden, by touch and online (dev phone: all nine hidden with no pad, the app's note of them
      empty). Now shown again in the widget's GetConfigData (before the order menu's: layers -95000 and 1) and
      hidden again at the next Update if the game goes on; at the first start, all nine hidden with no note is taken
      for that leftover and undone. Dev phone, three games: the leftover gone; the pad in use hid the nine, and after
      `/quitforce` BAR's file had `disabledCmd = {}`; the next game by touch showed every order. Why the menu does not
      rearrange online: the even layout (the rest filling the menu) is the controller game's order menu (v0.8.5)
      with the pad; BAR's released game keeps BAR's own, a grid of at least 4 x 4 cells (Kailil's last game on the
      Fold7, 2026-11-02 22:07, was online).
- [x] A long name in the small player list still reached BAR's eraser ("Prime_Federator (AI)", dev phone,
      2026-11-03): under 1200 lines BAR draws a name about a tenth wider than it measures it (its fontScaleMed, 1.11
      on a 938-line screen), more than the chat column's room. The small list also keeps BAR's income column where
      it is empty, for a player alone on their team (BAR draws it beside allies only: a skirmish, an online 1v1).
      "AurenTheAbsolute (AI)" clear of the eraser; the dev phone's logs after the day's games: only BAR's own
      notices. Still possible: a long last name in a team game while playing (names only there, Kailil's small list).
- [x] (the search) The first seconds of every game at 2-5 fps (dev phone, 2026-11-02): `[bardroid-perf]`'s first minute reads
      "2 4 5 5 5 4 21 24 28 ..." frames each second, then a steady 30 (a 6-minute game: 30.0, 29.9, ...). The sim keeps
      its pace (frame 190 at 6.4 s). Not the app's tile copy (`BARDROID_TEX_ZERO=0` through dev-env.sh: the same in two
      runs each), and not Mesa compiling shaders (its disk cache in the container's `/root/.cache`, 7.7 MB, unchanged
      by these games). Narrowed (a scratch widget timing each drawn frame, the engine's `/debuginfo profiling` table):
      from game frame 16 to about 300 one drawn frame every 15 game frames takes 0.2-1 s, the rest are quick; in the
      half second before frame 150 "Lua::Callins::Unsynced" is 84% of the time (Draw 8%, Sim 15%). BAR's Widget
      Profiler (on for one run through dev-env.sh's `widget_order "Widget Profiler" 1`) puts LuaUI callins at 67-90% of
      the running time but no widget above 2.3% (its 0.1 s tick and 2 s smoothing miss one long frame in fifteen, or
      the time is in what it leaves out: garbage collection and GL calls). Found: it is the Update callin (probe
      widgets from layer -1,000,000 to 1,000,000: every slow Update between 10,000 and 100,000), BAR's Cursor widget
      (layer 19000), which after the start replaces its 26 animated cursors one Update at a time (BAR's comment: "~0.7 s
      for all" on a PC). On the phone each first `Spring.ReplaceMouseCursor` takes 240-320 ms in the engine (the same
      cursor again: 0 ms; with `HardwareCursor = 0` just as slow; reading all 992 images of the 75 set through the VFS:
      0.8 s, 40 of them as textures: 38 ms). The phone already gets BAR's smallest set (75). Online games load them in
      the pregame (start positions), and a fold or unfold reloads the same set at no cost: only a skirmish's first
      seconds stutter. Kailil's call: the app could ask for the same 26 cursors while the game loads (a user widget's
      Initialize: the loading screen about 8 s longer, then BAR's own replacements cost nothing), or leave it.

## Releasing (once the blockers are done)

1. `tools/laptop-tests.ps1` passes; the phone build played on a phone (lobby, online game, skirmish). The launcher's status
   names no adjustment that did not apply (BAR's build menu changes with its releases: CONTRIBUTING.md).
2. Version in `gradle.properties`, a CHANGELOG entry.
3. `Build APK.bat phone release` with the release keystore.
4. `tools/publish-check.ps1`.
5. Kailil pushes and makes the GitHub release with the APK and the CHANGELOG text.
6. Kailil posts `C:\Tools\BARANDROID\discord-post.md` (the URLs filled in) in BAR's Discord, modding discussion.
