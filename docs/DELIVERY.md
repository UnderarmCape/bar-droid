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
- [ ] Kailil's call: Escape and Android 17's keyboard capture (dev phone, 2026-11-03). Each Escape in a game shows
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
      a report for lfdevs' Mesa (KGSL submit) with that log.
- [ ] One screenshot of the dev phone during pad-test (2026-11-03 02:44, the "FIRST PERSON OFF" note, a skirmish at
      7 fps) showed white ragged columns about 20 px wide across the whole picture, the interface too (kept as
      `build/white-columns-2026-11-03.png`, not tracked): a frame shown before it was drawn, or a torn screenshot.
      1 of 22 shots in that run; none in 222 back-to-back shots of the next. HANDOFF's "watch for flicker" of the
      explicit Present fence covers it; if anyone sees a white flash in play, this is the picture to compare.

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
- [ ] Touch HUD on the Fold7 unfolded (the dev phone at 1968x2184, 2026-11-02), Kailil's call on both:
      BAR's control-group and idle-builder panels dock to the order menu's right edge, which reaches far enough there
      that both sit under the small player list and show through it (BAR's layout; its order menu has no width setter
      and the list no position setter: the order menu raised with `setBottomPosition`, or the list kept open, are the
      app's ways). And in the controller game v0.8.5's build menu shows the commander's 26 options in 6 rows with a
      quarter of its panel empty below them (the app's copy, in BAR's game, ends at its last row); v0.8.5 changes only in
      BARGAMEPAD, at his word. And spectating there, BAR's "Player View", "Player Camera" and "TV" buttons, which sit
      on the player list's left edge, run past the screen's right edge while the list is minimized (only "Player View"
      shows): the minimized list could keep more width while spectating, or stay open for spectators.
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
      264 px (the edge is farther than the finger's row); both with the finger. And placing a
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
- [ ] Settings' order menu options in both games (2026-11-03): BAR's Settings name the widget "Order menu" (its
      colorize, bottom position and always-show options); BAR's game runs the app's copy ("BAR Droid order menu"), the
      controller game v0.8.5's renamed "Order menu (controller)" (infolog: "Options: 'ordermenu_colorize' widgetConfig:
      unknown widget Order menu"). A change in Settings still reaches the running menu (its `WG.ordermenu` setters) and
      the copy keeps its own settings, but Settings shows the old widget's saved values. Left: it would mean patching
      BAR's Settings widget.
- [x] The phone's remake of the menu copies, checked (2026-11-03): the shipped `.patches` applied to BAR's files as
      `BuildMenuPatches` does give the shipped `bardroid_buildmenu.lua` and `bardroid_ordermenu.lua` byte for byte.
      `make-buildmenu.py` and `make-ordermenu.py --check` (the patches against a BAR release, nothing written) pass on
      the laptop's (test-31777) and the phone's (test-31783), and run in `laptop-tests.ps1` now, so a BAR update that
      moves a part a patch needs shows before a phone falls back. `launch-bar-test.sh` covers `order_menu`: the copy
      in, kept with an Android-layer miss when BAR's file changed, BAR's own after the copy failed in a game (the build
      menu's copy left running), the controller game off; 55 cases, all pass (its menu block had called an undefined
      `order_menu`). And QUEUE's label in the white of the order menu's words right under it (it was the notes' warm
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
