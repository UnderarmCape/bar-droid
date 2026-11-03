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
      `tools/ui-screenshot.ps1`: Kailil picks; screenshots of the game only, no other BAR artwork.

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
- [ ] Replays of games that were stopped but had written something (the benchmark's runs on the dev phone): the lobby's
      Replays tab lists them as "time unknown" (no game time in the header), and one started from there stood at 0:00,
      x0.00. Whether a phone game ended by the low-memory killer leaves such a replay too, and whether the tab should
      say so or leave them out, is Kailil's call; the empty ones are already removed (above).
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
- [ ] The first seconds of every game at 2-5 fps (dev phone, 2026-11-02): `[bardroid-perf]`'s first minute reads
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
