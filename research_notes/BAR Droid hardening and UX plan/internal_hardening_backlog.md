# BAR Droid: internal hardening backlog, test coverage and constraints (audit of 2026-11-22)

Scope: read-only audit of `C:\Tools\BARANDROID\bar-droid-app` (branch `main`, untracked only `reports/` and
`research_notes/`), its docs, tools and git history, plus the dev-phone lock in `bar-droid-engine`. No tests run, no
phone touched. Sources are local files (line numbers as read on 2026-11-22) and commit hashes. "DELIVERY" means
`docs/DELIVERY.md` (848 KB, 7,600 lines: 662 ticked `[x]` entries, ~20 unticked `[ ]` entries, plus a numbered
60-item "release overhaul" list whose items are ticked by separate `[x] **Item N**` entries).

Abbreviations: APP = `C:/Tools/BARANDROID/bar-droid-app`.

## 1. What open items does docs/DELIVERY.md list, and which are done vs open? Which block a release?

### Takeaway
The 2026-11-21 "release overhaul" (60 audit findings from 14 read-only audits) is mostly worked: about 45 of 60 are
ticked done, all HIGH-rated ones except item 40 (an owner's call). What remains open is (a) MEDIUM/LOW
robustness items 36-38, 43, 45, 47-49, 52-53, 55-60 and the "noted, not worked" sub-findings, (b) eight features
"built, his test pending" on Kailil's Fold7, and (c) owner decisions that block a *public* release (app name, git
history, release key, publishing the phone engine's source). For a *private* release most owner items do not block,
but the GPL engine-source and the release-key questions still decide which APK can be handed out.

### Cited Findings
**The release overhaul list (Kailil 2026-11-21 ~01:20: "We are releasing this in the next 4 days")**
- The list's rule: "each item moves to its own [x] entry below when done"; four to fourteen read-only audits added
  items 1-60 between 01:25 and 21:27 on 2026-11-21 — [DELIVERY:384-648](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- DONE (each a ticked `**Item N**` entry, dated 2026-11-21): 1 (lobby bridge only does what the lobby needs), 2 (engine-log
  readers vs spectator/host/ping words), 3 (widget checks anchored to BAR's own lines), 4 (bardroid-ui holds only the
  app's widgets: fair play online), 5, 6 (v0.8.5 controller game code removed), 7a-7h (APK 2.1 MB smaller, retired
  prefs, per-frame costs: camctl 40% cheaper, dock garbage -37%, pad widget garbage gone, info panel idle, wind/tide
  display list), 8 (NOTICE, publish-check, CHANGELOG 0.2.0), 9 (launch-bar.sh trusts the write folder less), 10 (PC
  import dev-only), 11 (cheap parts), 12 (Java lifecycle/threads), 13 (bloat), 14 (fresh install's first lobby gets the
  lobby widget, HIGH), 15 (dpkg interrupted recovers, HIGH), 16 (bardroid_lowmem.lua out), 17, 18-20, 21 (Updater
  judgement), 22 (full phone says so), 23 (bridge survives hostile local app, HIGH), 24, 25 (nothing stays held when
  pad goes), 26, 27, 28 (touch log restart without losing a gesture), 29 (stuck keys), 30-31, 32, 33, 34 (menu copies
  within Lua's 200 locals, HIGH), 35 (failure mark names files that ran, HIGH), 39 (fresh install's first start is not
  an update's, HIGH), 41, 42, 44, 46 (sound survives failed AudioTrack), 50, 51 (Share logs keeps battle password out),
  54 (Stop ends a stalled download) — [DELIVERY:649-1200](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md); commits
  5688b2d9 ... 4b878e90 (`git log`, 2026-11-21 01:44-21:43)
- OPEN, no `[x]` entry found (grep for "Item 36/37/38/40/45/47/48/49/52/53/55-60" finds none; 43 only "looked at"):
  - 36 MEDIUM-HIGH: within a lobby session nothing falls back to BAR's own build menu; a copy that errors is removed
    in every game of the session with BAR's own still off; a BAR release fetched mid-session gets no remake
    — [DELIVERY:551-553](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 37 MEDIUM: a phone patch of BAR's widget that applies but errors is never noticed and never falls back to BAR's
    unpatched file — [DELIVERY:554-555](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 38 MEDIUM: one replay in a lobby session hides every live game's faults; an error the copy causes in a caller's
    unprotected call removes the caller, not the copy; LOW: two byar hosts' indexes, invalid UTF-8, OOM in remake not
    caught — [DELIVERY:556-559](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 40 HIGH, owner's call: phones BAR cannot run (Mali, Xclipse, PowerVR, Adreno 5xx and older, 4-6 GB RAM) download
    ~5 GB anyway; the only hint is a grey device line; "which phones to refuse or warn about is Kailil's"
    — [DELIVERY:566-568](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 43 MEDIUM (guess): game started from background may have no screen; looked at 20:40, "left noted" (notification
    and icon bring it in) — [DELIVERY:574-586](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - MEDIUM-LOW/LOW from the first-run audit, not worked: container DNS fixed to 1.1.1.1/8.8.8.8 (networks blocking
    outside DNS fail apt, pr-downloader and the lobby); no warning before ~5 GB over mobile data; developer words
    under the icon; Debian base image from a moving branch — [DELIVERY:577-581](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 45 MEDIUM: game sound ~0.45 s late (not 0.2 s); left as a trade-off pending underrun counts from real games
    — [DELIVERY:589-603](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 47 MEDIUM: launcher settings changed mid-game half apply (late-game drop, render resolution, frame cap None ->
    120 Hz at next fold); left, reaches only players who turn the drop on — [DELIVERY:595-604](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 48 LOW (FIFO setup/shutdown races), 49 LOW guess (no audio focus/ducking) — [DELIVERY:598-600](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 52 MEDIUM, partly a guess: splash keeps no screen on, a long update outlasts the timeout and the lobby may run
    hidden — [DELIVERY:616-618](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 53 MEDIUM: a crash of the app's own process during a lobby start is not remembered and no default
    uncaught-exception handler writes its stack to launcher.log — [DELIVERY:619-620](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - 55-60 LOW: Share logs carries names/chat/up to 20 old infologs; resumed downloads without If-Range; plain-http
    redirects followed, Mesa and engine downloaded without a checksum; downloads/*.part never cleaned (~100 MB); splash
    give-up clock reset by every update tick; manifest merges WRITE_SECURE_SETTINGS and a com.termux query
    — [DELIVERY:621-631](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
  - "Noted, not worked" sub-findings: item 11's touch-log/bardroid_pad.txt click and key lines writable by user widgets
    (a user widget could make the app click; "no user widget can reach a release phone today"); item 23's per-start key
    for the lobby bridge ("left for after the release"), unbounded Download queue, OpenFile opens any https link,
    CLIENTS_MAX lock-out by two idle connections; item 25/27's two-pad shared state and USB XInput clones' trigger
    axes; item 28's palm-cancel as second finger; the lobby camera-line fix parked unproven (`toolchain\tmp\lobbycam.diff`)
    — [DELIVERY:423-426, 480-493, 511-513, 535-539](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Owner's decisions listed for Kailil: app name; fresh history or filter-repo and which repository goes public (the
  private repo's latest-build pre-release is a debug APK with his personal icon); the release key; the phone engine's
  source made public ("GPL: NOTICE needs its link, or release without it"); his name and the worklog archive in what
  goes public; "which 'his test pending' items must pass on his Fold7 first"; launcher developer controls, Benchmark
  button, emulator build, late-game resolution drop; Releasing step 1's laptop-tests ("BAR on the laptop is off
  limits"); laptop-only tools built on the retired controller game — [DELIVERY:635-643](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Item 8's note: "What still fails for a release is the owner's: the release key, the phone engine's source line";
  an unsigned public release build (-PbardroidPublic) passed the debuggable/phone-build/icon checks
  — [DELIVERY:811-819](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)

**Blockers section (public release)**
- Done: public icon, LICENSE (Kailil still to confirm GPL-3.0-or-later), personal data out of tracked files, release
  signing mechanism, publish-check. Open: **App name** (recommended "BAR Droid" while unofficial) and **History**
  (icon and personal data in old commits; commits name Kailil's e-mail; recommended a fresh one-commit history)
  — [DELIVERY:5131-5159](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- "Releasing" steps: 1 laptop-tests pass and phone build played (lobby, online, skirmish); 2 version + CHANGELOG;
  3 `Build APK.bat phone release` with the release keystore; 4 publish-check; 5 Kailil pushes and makes the GitHub
  release; 6 Kailil posts the Discord draft — [DELIVERY:7591-7599](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- CHANGELOG has "0.2.0 (not released yet)" — [CHANGELOG.md:7](C:/Tools/BARANDROID/bar-droid-app/CHANGELOG.md)

**Other unticked `[ ]` entries**
- Built, "his test pending" on the Fold7 (8): one-finger camera second build (left side, speed-sensitive, half rails;
  PLACE without QUEUE replaces the queue) [L2579]; camera knob + edge rails [L2604]; unfolded dock split in two [L5577];
  Kailil's dock asks of 2026-11-16 [L5862]; upright dock on unfolded Fold7 max a third of the screen [L5902]; one touch
  layout for both orientations sideways [L5920]; sideways one-thumb dock [L6326]; "Turning with the phone" auto-rotate
  [L6348] — [DELIVERY](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Flaky test: "dock-phone-test's Area Mex case failed once" (2026-11-20 05:50, "0 mex orders"; ~20 passing runs since;
  left open with extra logging) — [DELIVERY:84-89](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Perf: the dock's texture redrawn at every 0.25 s refresh, changed or not (~0.3-0.4 ms/frame avg, as single 3 ms
  frames) — [DELIVERY:3918-3923](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Kailil's call: gamepad RB on the upright dock's build grid (pad does not drive the dock) [L4621]; load screen
  generative fill [L4854]; README screenshots (Kailil picks) [L5165]; offline quick skirmish cannot download missing
  maps [L5506] — [DELIVERY](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Stability, still open (see question 2): Kailil's laggy online 8v8 that ended in a low-memory kill [L5207]; Mesa
  KGSL submit deadlock / GPU driver fault [L5233-5305]; dev phone hard reset after 33 game starts [L5306]
  — [DELIVERY](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Unticked but apparently resolved: speak-to-chat restart race, "Changed 2026-11-10 (VoiceChat: a recognizer per
  session ...)" — [DELIVERY:7464-7469](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)

**Touch playtest findings (2026-11-21/22, new source of open UX items)**
- Fixed and tested on the dev phone (touchfix-phone-test ALL PASS): D-gun AIM from a fifth of the ring, map tap aims
  D-gun, pre-game QUEUE row, "WALLS +64", INSERT on builders, "+ QUEUE" on PLACE, commander-under-30% warning
  (89286296); sea twins (a63ecb0a); quick Skirmish maps in name order (1114d607); D-gun sticks screen-relative
  (e952aae4); faction buttons under PLACE, pre-game hint, D-gun tap on an enemy leads it (3104771e) — `git show` of
  those commits; [PLAYTEST.md:377-411](C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md)
- Not yet fixed (logged UX/QOL; no matching fix commit found): no pause control on the touch UI in singleplayer
  [L66-68]; scenario starts paused behind the Mission window with no "start" cue, a map tap unpauses [L62-65, L89-91];
  no unit/building names on dock tiles, long press shows nothing [L80-83, L114-117]; zoom rail barely moves on slow
  drags [L106-108]; build grid scrolls by rows not pages [L110-112]; camera knob/turn rail swallow map taps near the
  dock edge (4 of 6 taps) [L147-149]; energy panel opens from a tap meant for QUEUE [L150-153]; Android Back opened BAR's
  lobby with units selected (2026-11-21 23:20, after the 11-20 contextual Back work) [L154-155]; factory-middle tap
  selects the unit in its yard [L156-157, L250-251]; ALL UNITS / LOCAL UNITS omit aircraft and constructors with no hint
  [L158-159, L190-191]; FACTORIES cycling has no hint [L160-161]; no "assist" order [L162-163]; bombers have no
  Attack-ground button [L164-166]; chat Enter right after typing left text unsent [L167-168]; dock order buttons lag a
  selection change, taps land on the old buttons [L194-195]; lobby Difficulty list ignores quick taps, scenario list
  fling inconsistent [L208-210]; lobby over a running game: Start Scenario does nothing, no prompt [L134-135]; far
  order targets need a pan first, minimap too small upright [L384-390]; auto retreat sends hurt units home one by one
  [L257-259]; factory Repeat repeats constructors [L299-301]; Move drops the commander's build queue (BAR behaviour)
  [L316-317]; end screen Awards under Mission window [L84-85]; 12 s autoquit short [L284-287]; BAR's "Register your
  account" window is a new player's first sight [L55-57]; constructors' Overwatch failed to place several times
  (game 11) [L418-420] — [PLAYTEST.md](C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md)
- Outcome: Easy lost then won (game 2), Medium won (game 3), Hard 0 wins in 8 games; "The touch controls did each
  thing asked; the gap is the agent's own macro" — [PLAYTEST.md:413-440](C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md)

### Inferences
- Release blockers for a ~2026-11-25 private release (by severity of what is open): item 40 (unsupported phones
  download 5 GB; matters only if the APK reaches non-Fold7 phones), item 53 (no uncaught-exception handler: crashes
  in the field leave no stack in Share logs), item 36 (build menu absent for a whole lobby session after one error,
  online too), and the GPL question (an APK carrying the modified engine must offer source; publish-check fails such
  an APK until NOTICE names the source). Everything else open is MEDIUM/LOW or UX polish.
- The 8 "his test pending" features are the largest unknown: they were built by agents and pass dev-phone tests but
  have no owner sign-off; DELIVERY itself asks Kailil which must pass first.
- The playtest found no crash-class bug in ~17 games; its findings are discoverability/UX (pause, names, knob tap
  stealing, Back) which are cheap and player-visible.

### Gaps
- Whether item 38's LOW parts and the item 7 "log floods" are fully covered by 7a-7h was not traced line by line.
- Whether the Back-opens-lobby observation (PLAYTEST L154) is a regression of the 11-20 contextual Back or an artefact
  of the dev driver: not determined from the docs.
- No single list ranks the overhaul items by release-blocking; the HIGH/MEDIUM labels are the audits' own.

## 2. Open risks named in CLAUDE.md, HANDOFF.md, ARCHITECTURE.md (memory, GPU driver faults, display/fold, online safety, engine gate)

### Takeaway
The two live stability risks are (1) memory: Android's low-memory killer on 8 GB phones and in big/late online
games, and (2) a random Mesa/KGSL GPU submit deadlock ("the driver's refusal") that freezes ~4-12 % of game starts on
the dev phone, now auto-closed by DriverWatch rather than fixed. Online safety and the engine gate are controlled by
design (sim rewrite off online, gate passed for 2026.09.03) but rest on a small replay sample. HANDOFF.md's risk list
is dated 2026-10-27 and partly stale.

### Cited Findings
- CLAUDE.md "Open risks": phone RAM (~5-6 GB a match), BAR's UI on the near-square inner display, BAR panels without
  IsAbove take finger drags as pans (covered for top bar/windows; tap panels registered via WG.BarDroidTapPanels),
  "touch-only play (later)" — [CLAUDE.md:349-357](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- HANDOFF "Open risks (2026-10-27)": RAM (low memory logged through a spectated 8v8; the killer has taken the game);
  heat (after an hour GPU capped 443-900 of 1200 MHz; thermal status 3 at 160 MHz floor); only one phone model tested
  (Fold7 then; Adreno 7xx/8xx others untested); BAR saved games crash the engine on load (also Windows, upstream);
  explicit Present fence new (watch flicker/stall on fold/unfold, floating window); lobby without BAR's launcher;
  BAR's graphics presets undo the phone layer until next start — [HANDOFF.md:98-112](C:/Tools/BARANDROID/bar-droid-app/HANDOFF.md)
- HANDOFF title says "updated 2026-10-28" and its Next steps are dated 2026-10-27 (e.g. "Keyboard shortcuts,
  Kailil's check" still pending) — [HANDOFF.md:1, 273-283](C:/Tools/BARANDROID/bar-droid-app/HANDOFF.md)
- Save/load in practice now: playtest game 8 saved by the top bar's Save and loaded from Load Game on a new build:
  "save and load work by touch" — [PLAYTEST.md:375-376](C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md)
- ARCHITECTURE.md has no risk section; "Things that bite" lists canonical proot paths, nativeLibraryDir moving, Proc
  SIGKILL, no `--kernel-release`, seccomp traps, MaxParticles >= 10000, chobby_config.json
  — [ARCHITECTURE.md:150-159](C:/Tools/BARANDROID/bar-droid-app/docs/ARCHITECTURE.md)

**Memory**
- README: 12 GB RAM required; 8 GB phones get a low-memory mode; on the S23 Ultra (8 GB) "on a big map about 1 in 3 is
  closed by Android for lack of memory ... Online games there are untested" — [README.md:34-39](C:/Tools/BARANDROID/bar-droid-app/README.md)
- Kailil's online 8-player game on the Fold7 (2026-11-02): 30 fps first 11 min, then thermal status 3, GPU at 160 MHz,
  10-25 fps, last minute 9.4; free memory 650-950 MB late; Android's low-memory killer ended the app as he left
  (LOW_MEMORY, also earlier that evening); still `[ ]` — [DELIVERY:5207-5214](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- GPU textures are most of a game's memory ("engine 749 MB, GPU 2060 MB" at a 1v1 start); projectile atlases 345 MB;
  Cache Icons turned off on phones saved ~0.44 GB — [DELIVERY:5223-5229](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- The 2026.09.03 engine gate dropped one 8v8 replay because "Android's low-memory killer took it four times with the
  phone engine, and BAR's official 2026.09.03 while loading" on the 8 GB dev phone — [DELIVERY:3995-3998](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Low-memory ends counted among dev-phone starts: 2 of 21 (11-11/12), 1 of 24 (11-12/13) — [DELIVERY:5271-5282](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)

**GPU driver fault (DriverWatch)**
- Symptom: Mesa "flush_submit_list: submit failed -1 (Resource deadlock avoided)", then BAR's watchdog; picture
  frozen, engine alive. DriverWatch (GameService reads engine lines) closes the game; since 2026-11-19 it closes 8 s
  after the game's widget goes silent (DriverWatch.stalled) — [DELIVERY:5233-5295](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Rate: ~1 in 25 starts earlier; "2026-11-20, more often: 5 in the 41 engine starts ... (12 %) ... all early: 4-112 s
  into a game"; neither first-draw of every unit type nor camera jumps reliably trigger it (firstdraw-phone-test: 1
  in 7 games, 0 in 4); "Still random, early in a game" — [DELIVERY:5296-5305](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- An upstream report for lfdevs' Mesa is drafted (`docs/research/mesa-kgsl-submit-deadlock.md`), for Kailil to post
  or not — [DELIVERY:5241-5243](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- A separate early GPU hang on joining an online 8v8 (2026-10-27) was tied to "Compare upscaling" toggling SGSR
  every 3 s; that diagnostic stays off — [HANDOFF.md:289-296](C:/Tools/BARANDROID/bar-droid-app/HANDOFF.md)
- The 11-20 hardening found a chat line could close a healthy game as a driver fault (fixed; driverwatch-phone-test
  covers spoofed lines) — [DELIVERY:173-185](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md); [CLAUDE.md:248](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- Dev phone hard reset (watchdog-like, `PonReason.HARD_RESET`) after the 33rd game start of an evening, 2026-11-03;
  open — [DELIVERY:5306-5311](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)

**Display / fold**
- Fold handling lives in termux-x11 patches 0003 (resize full-screen windows), 0006 (pixel cap 2100x900 folded,
  1198x1080 unfolded) and libbardroid_pace.so's SDL display-size answers — [CLAUDE.md:44-50, 165-171](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- Folded turn freeze (~10 s) fixed on the Fold7 with the phone engine: six turns each "21 widgets loaded again in"
  561-1010 ms, 30 fps late, no SIGSEGV (2026-11-18) — [DELIVERY:2050-2065](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Known limit: with BAR's official engine a turn stalls 5-10 s and BAR's Settings is wider than the screen upright
  — [README.md:251-254](C:/Tools/BARANDROID/bar-droid-app/README.md)
- Mid-game launcher changes and frame cap None move the display to 120 Hz at the next fold (item 47, open)
  — [DELIVERY:595-597](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)

**Online safety and engine gate**
- Sync is "the one risk that matters"; the exact sim rewrite is "built in but switched off online"
  (`BarDroidSimAllowed`: stock code with a remote host or more than one player) until it passes 20+ server replays;
  proof so far 3 replays, 0 desync warnings — [ENGINE-DEFAULT.md:25-60](C:/Tools/BARANDROID/bar-droid-app/docs/ENGINE-DEFAULT.md)
- 2026.09.03 phone engine `phone-2026.09.03-83a8536d37` passed `tools/engine-gate.ps1` on 2026-11-18: three server
  replays to the end with 0 desync warnings (as shipped and with every switch at 0), plus dock, touch, pad, pad
  -Online, pace, lobby-phone tests and remake-check ALL PASS; one SIGSEGV 3 s into a first start seen once, not in ~20
  starts after — [DELIVERY:3986-4004](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- The gate script itself excludes "BAR's benchmark against the official engine and the Fold7's day of games (stage
  2's last two)" — [engine-gate.ps1:16](C:/Tools/BARANDROID/bar-droid-app/tools/engine-gate.ps1)
- "No APK carrying one goes out before the branch's source is public (NOTICE.md)" — [CLAUDE.md:328-329](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- Fair-play fixes in the overhaul: item 4 (only the app's widgets load as game widgets), item 2/3 (other players'
  chat cannot spoof engine lines), 11-20/21 fixes for chat faking "Game saved", Autoquit countdown, overlay state
  — [DELIVERY:186-197, 332-383, 724-736](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Kailil's online game 2026-11-21 01:04 surfaced "BAR's Notifications failed to load" (fixed by a phone patch,
  eb319e7d) — [DELIVERY:691-707](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)

### Inferences
- Memory is the risk most likely to hit a release user on a 12 GB phone in a big online game (the only owner online
  8v8 data point ended in LOW_MEMORY); there is no automated pass/fail memory gate, only measurements.
- The driver fault is mitigated (auto-close, a clear note) but not cured; its 12 % day suggests test runs should
  expect and classify it rather than read it as a controls bug (pad-test and touch-phone-test already name it).
- The sim rewrite being off online makes the engine gate's small replay count acceptable for online play, but the
  phone engine's *unsynced* changes and game-widget loading run online with no replay-based check beyond the gate.
- HANDOFF.md, ENGINE-DEFAULT.md "Status (2026-11-13)" (names 2026.07.04) and `bar-droid-engine/CLAUDE.md` (still says
  "Unmodified official Recoil engine", UDP BARCTRL1, controller game) are stale relative to the code; a hand-off reader
  would be misled.

### Gaps
- No record found of the driver fault on the Fold7 (Adreno 830): grep of docs for Fold7 + refusal/deadlock found
  only dev-phone counts; whether it affects the owner's device is unknown.
- No current (post-2026-11-13) measurement of memory headroom on the Fold7 in a late online game was found.
- Other phone models (Adreno 7xx/8xx besides S23 Ultra and Fold7): untested per HANDOFF; no newer data found.

## 3. What recent commits (since 2026-11-15) fixed, and which areas changed most

### Takeaway
About 1,000 commits in 8 days (106-212 a day), dominated by docs/worklog churn; code work centred on the touch dock
(`bardroid_portrait.lua`), the lobby widget, RtsTouch/GameService/GameActivity, BAR's menu copies, and on 2026-11-21 a
security/robustness overhaul; 2026-11-22 switched to a touch playtest with same-day UX fixes.

### Cited Findings
- Commits per day (git log on main): 11-15 106, 11-16 174, 11-17 163, 11-18 193, 11-19 212, 11-20 100, 11-21 78,
  11-22 17 (to 13:51) — `git -C APP log --since/--until` (counted 2026-11-22)
- Most-touched files since 11-15 (file-change count): docs/DELIVERY.md 511; docs/WORKLOG.md 479;
  docs/worklog/data/sessions.json 479; messages.jsonl 476; worklog day pages 40-125 each; bardroid_portrait.lua 88;
  CLAUDE.md 57; bardroid_lobby_touch.lua 52; RtsTouch.java 35; GameService.java 35; bardroid_pad.lua 28;
  bardroid_touch.lua 26; StatusTextTest.java 21; README 19; strings.xml 18; GameActivity 18; dock-phone-test 18;
  LauncherActivity 18; launch-bar.sh 15; teamstats/options copies and their generators 13-15 each; Installer 12;
  camctl 12; buildmenu copy/patches 11-14; LobbyBridge 9; Updater 8 — `git log --name-only` aggregate
- Subject prefixes since 11-15: 253 "DELIVERY", 35 Dock, 29 Lobby, 29 Launcher, 14 Touch, 10 Playtest by touch, 9
  Display preferences, 9 dock-phone-test, 8 Pad, 7 Lobby upright, 7 Portrait ...; 151 subjects mention
  crash/freeze/hang/stuck/fault/leak/memory/desync/fold/lost/fail — `git log --format=%s` aggregate
- 2026-11-20: Kailil's queue of 11 features (LINE/BORDER hold, contextual Back, factory presets, strafe at once, ALL
  UNITS exclude a type, attack pings, walls around sentries, D-gun speed check, auto retreat test, transfer button) all
  done, then "hardening loops" on 11-19's systems (one-finger camera, lobby upright, Statistics, replay speed column,
  Settings search, Load Game/Replays over a game, lobby keyboard/speak to chat, driver fault close), each given a new
  real-tap phone test — [DELIVERY:35-383](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md); [worklog 2026-11-20](C:/Tools/BARANDROID/bar-droid-app/docs/worklog/2026-11-20.md)
- Security fixes found by hardening on 11-20/21: a player's chat could change app state, fake "Game saved", fake chat
  system lines and BAR's Autoquit countdown; "Another player's widget could take every phone's fingers off the game"
  (6604ab43: overlay believed only with the phone's own lobby saying so) — [DELIVERY:186, 332, 347, 364](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- 2026-11-21: release overhaul items 1-54 (commits 5688b2d9 ... 4b878e90), e.g. dev hooks only in debuggable builds
  (5688b2d9), dex compressed 39.9 -> 31.7 MB (73d3fa1d), lobby bridge hardened (513c0cd2, 36caae7d), controller game
  removed (78b69920), fresh-install fixes (76627d70, 33f3721f, cd9139b5), stuck input (ebc5b298, 5060c244, 6390ebd4),
  menu-copy remake limits (17bd6b47, 4aec9ab3) — `git log` 2026-11-21
- 2026-11-22: "Playtest by touch" games 1-11 and fixes 89286296, a63ecb0a, 1114d607, e952aae4, 3104771e — `git log`
- Older notable fixes in the window: 2026.09.03 phone engine into the APK, folded-turn freeze fixed (2026-11-18,
  1195062c build) — [DELIVERY:2050-2065](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)

### Inferences
- Roughly half of all file changes are bookkeeping (DELIVERY + worklog data regenerated per commit); the
  worklog's `sessions.json`/`messages.jsonl` committed ~480 times is noise in the history that a fresh public
  history would drop anyway.
- The highest-churn code (`bardroid_portrait.lua`, the lobby widget, RtsTouch) is also where the playtest found most
  UX issues and where the 8 unsigned-off features live: the riskiest area for regressions before the release.

### Gaps
- Commit-level diff sizes (lines changed) were not computed; churn is by file-touch count only.
- Commits on other branches (github-sync pushes every branch) were not examined.

## 4. Which on-device test suites exist, what each covers, and which important flows have no automated test

### Takeaway
There is a broad set of ~30 dev-phone scripts that drive the real app by adb taps, a virtual uinput gamepad or
scratch test widgets, each a few minutes, plus Java/shell unit tests on the laptop. Coverage is strong for individual
touch-dock features and hardening regressions, but there is no automated end-to-end game (lobby -> pre-game -> play
-> end screen), no online/lobby-login test (forbidden), no fresh-install test, no memory or thermal pass/fail gate,
no real fold/hinge test, and the laptop BAR checks (lobby-touch, lobby-bridge, touch-widget, catchup, spectate) can
no longer be run.

### Cited Findings
**Dev-phone tests (descriptions from CLAUDE.md's Build/run list and script headers)**
- dock-phone-test (~3 min, real taps, upright and 1080x1198): build grid first building + PLACE 2.6 s later, PLACE
  on a blocked spot, D-gun FIRE/AUTO, MOVE stop, STRAFE preset, wind/tide boxes, Area Mex circle, energy share knob,
  SEND ENERGY picker; plus LINE/BORDER hold, Back/Quit cases (33 cases) — [CLAUDE.md:235](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md); [dock-phone-test.ps1:1-12](C:/Tools/BARANDROID/bar-droid-app/tools/dock-phone-test.ps1); [DELIVERY:47-49, 83](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- factory-preset-test (~4 min), types-phone-test (~3 min), attack-ping-test (~2 min), walls-phone-test (~3 min),
  stats-phone-test (~2 min), settings-phone-test (~2 min), overgame-phone-test (~3 min: lobby over a game, Load Game
  of the newest save, Replays' Add, Return to Battle), camctl-phone-test (~2 min, incl. back-gesture exclusion),
  replay-phone-test (~2 min), lobbychat-phone-test (~1.5 min; refuses to run with mic permission granted),
  buildbar-phone-test (~2 min), bridge-phone-test (~1.5 min, hostile local app), driverwatch-phone-test (~4 min,
  spoofed fault/save/pause lines), firstdraw-phone-test (driver fault hunt), x11-probe (sockets), dgun-speed-test
  (~3 min), touchfix-phone-test (~4 min, the playtest fixes), retreat-phone-test (~7 min, per unit kind with AUTO
  RETREAT on vs off), touch-phone-test (~2 min, camera at the map's edge), fp-save-test (~1.5 min), stripes-test
  (UBWC screenshots), lobby-phone-test (~1 min, lobby widget + virtual pad's Start) — [CLAUDE.md:234-256](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- pad-test (~2 min; virtual Xbox pad through uinput, real input path; -Online: user widgets' orders forbidden as a
  host can; -Dgun; -Share with the AI as stand-in teammate; -Chat; -Engine) — [pad-test.ps1:1-14](C:/Tools/BARANDROID/bar-droid-app/tools/pad-test.ps1)
- pace-test: libbardroid_pace.so window events and frame cap with SDL's dummy driver, no display — [pace-test.ps1:1-5](C:/Tools/BARANDROID/bar-droid-app/tools/pace-test.ps1)
- remake-check: phone remake of menu copies byte for byte, every phone patch against the release on the dev phone;
  lua-locals.py: widgets under Lua's 200 locals — [CLAUDE.md:261-262](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- engine-gate.ps1: server replays (0 desync), phone tests (dock, touch, pad, pad -Online, pace, lobby-phone,
  remake-check); takes the dev phone via devphone-lock per item — [engine-gate.ps1:1-17](C:/Tools/BARANDROID/bar-droid-app/tools/engine-gate.ps1)
- Measurement tools, not pass/fail: phone-bench.ps1 (BAR's "Benchmark BAR", warmed up), phone-memory.ps1 (engine GPU,
  RSS, swap, available memory, killed or not -> CSV), profile tools — [CLAUDE.md:270-279](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md); [phone-memory.ps1:1-10](C:/Tools/BARANDROID/bar-droid-app/tools/phone-memory.ps1)
- "Rounds": sessions rerun sets of these tests after each batch ("Round A/B ... ALL PASS"), e.g. round A on 80562d9f
  and round B on 54cba210 on 2026-11-21; no committed runner script for a round was found in tools/ — [DELIVERY:995, 1021](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Hand-tapping tests call Assert-GameInFront first (no taps on the launcher) — [DELIVERY:1139](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md) (commit b6bc114c)

**Laptop tests**
- laptop-tests.ps1 bundles Java/shell tests (downloader, settings-merge, updater, padgame, status-text, map-store,
  log-redact, voice-chat, launch-bar-test.sh, publish-check -SelfTest, PowerShell syntax) with BAR-launching ones
  (lobby-bridge-test, lobby-touch-test, touch-widget-test, spectate-test -QuitCheck) — [laptop-tests.ps1:1-26](C:/Tools/BARANDROID/bar-droid-app/tools/laptop-tests.ps1)
- catchup-test runs a headless host and a windowed spectator on the laptop — [catchup-test.ps1:1-9](C:/Tools/BARANDROID/bar-droid-app/tools/catchup-test.ps1)
- Since 2026-11-19 "No BAR tests on the laptop, idle or not", enforced by a PreToolUse hook (`bar_launch_guard.py`);
  it also blocked this audit's attempt to read test headers through PowerShell — [CLAUDE.local.md](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.local.md); observed hook denial 2026-11-22

**Flows without an automated test (as found)**
- Full game start-to-end by touch: only the 2026-11-21/22 agent playtest, whose driver (dev_playstate.lua, play.py,
  touchd.py, autopilot.py) lives in `toolchain\tmp\play`, not in the repository — [PLAYTEST.md:121-130, 370](C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md)
- Pre-game (start position, faction pick, pregame queue): "a skirmish the app starts has no pre-game"; the pre-game
  QUEUE and faction-switch fixes were "Not on the phone" — commits 89286296, 3104771e
- Online lobby flows (login, join a battle, autohost, catch-up as a joiner): tests never log in (one session per
  account; a test login ended his phone game) — [CLAUDE.md:288-292](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md); catch-up's test is laptop-only — [catchup-test.ps1:1-2](C:/Tools/BARANDROID/bar-droid-app/tools/catchup-test.ps1)
- Save/load: overgame-phone-test loads the newest save from Load Game; a save -> load round trip was checked by hand in
  playtest game 8 — [CLAUDE.md:242](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md); [PLAYTEST.md:375-376](C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md)
- Long games / thermal: phone-bench measures a warmed benchmark; no soak test with a pass/fail line
- Memory pressure: phone-memory measures one game; LMK ends are counted incidentally in rounds and the gate
- Fold/unfold: dev phone uses `wm size 1080x1198` / `1080x1080` to emulate shapes; the real hinge only on the
  Fold7 by Kailil — [DELIVERY:2053, 2059-2065](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Fresh install end to end (empty storage, ~4-5 GB): items 14/15/39/41/42 were tested by targeted state setups and
  launch-bar-test.sh, not a full first-run test — [DELIVERY:1001-1018, 1112-1127](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Audio (latency, underruns, focus): no test; item 45 waits for underrun counts — [DELIVERY:601-603](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Real gamepads (Bluetooth, USB XInput clones, two pads): only the virtual uinput pad — [DELIVERY:511-513](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Auto-rotate ("Turn with the phone"), sideways one-thumb dock, split dock: built, owner test pending (question 1)

### Inferences
- The suite answers "does each dock control do what it says" well; it does not answer "can a player get from the
  icon to a finished online game", which is what a release user does first.
- Committing a trimmed version of the playtest driver (state export + touch daemon) would give the project its only
  end-to-end, pre-game-inclusive harness; today it can be lost with toolchain\tmp.
- Releasing step 1 ("laptop-tests passes") cannot be met as written under the no-laptop-BAR rule; the Java/shell
  subset could be split out and run.

### Gaps
- Exact current case counts and runtimes per test beyond what CLAUDE.md and DELIVERY state were not verified (no
  tests run).
- Whether spectate-test and fp-save-test run on the phone or the laptop was not confirmed from their headers
  (fp-save-test is listed as "on the dev phone"; spectate-test's -QuitCheck is part of laptop-tests).

## 5. Time spent and recurring problems in the last week (docs/WORKLOG.md, docs/worklog/2026-11-2*.md)

### Takeaway
Claude sessions logged ~181 hours in the last 8 days (often several sessions in parallel) against ~9 hours of
Kailil's time; Kailil's input is a few messages a day, mostly queues of features or "continue hardening". The
recurring friction is the Fold7 being unreachable over adb/Tailscale (builds waiting), GPU driver faults and
low-memory kills interrupting dev-phone runs, and test-harness faults.

### Cited Findings
- Totals: 29 days, 15 Claude Code sessions, 574 messages from Kailil, Kailil 66.9 h, Claude 538.0 h, 62,003 tool
  calls, 2,562 commits — [WORKLOG.md:7-16](C:/Tools/BARANDROID/bar-droid-app/docs/WORKLOG.md)
- Last week, Kailil h / Claude h / commits: 11-15 0.7/18.0/106; 11-16 0.7/21.9/174; 11-17 1.9/24.8/163; 11-18
  1.5/24.0/193; 11-19 2.1/22.8/212; 11-20 0.7/30.8/100; 11-21 1.2/27.0/78; 11-22 0.1/11.6/7 (partial) — [WORKLOG.md:45-52](C:/Tools/BARANDROID/bar-droid-app/docs/WORKLOG.md)
- Claude's time counts sessions "side by side" additively — [WORKLOG.md:18](C:/Tools/BARANDROID/bar-droid-app/docs/WORKLOG.md)
- 2026-11-20 Kailil: "Continue this loop of improvement indefinitely and autonomously. I will not be available for
  questions." — [worklog 2026-11-20:27](C:/Tools/BARANDROID/bar-droid-app/docs/worklog/2026-11-20.md)
- 2026-11-21 Kailil: the overhaul request; "Make the preset button for factories big"; "Give me q full recap"; the
  playtest request ("fully play ... skirmish 1v1 Hard games against the AI, and win"); then asked for a more
  effective way and research — [worklog 2026-11-21](C:/Tools/BARANDROID/bar-droid-app/docs/worklog/2026-11-21.md)
- Fold7 reachability: repeated "Not on the Fold7 yet (refusing port 44111)", "The Fold7 still unreachable (04:03,
  04:31)", new wireless-debugging ports supplied by Kailil several times a day; Fold7 offline on Tailscale for hours —
  [DELIVERY:757, 782, 1221-1286](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md); [worklog 2026-11-20:98-158](C:/Tools/BARANDROID/bar-droid-app/docs/worklog/2026-11-20.md); [worklog 2026-11-21:39-61](C:/Tools/BARANDROID/bar-droid-app/docs/worklog/2026-11-21.md)
- Last documented Fold7 install: HEAD 54cba210's build since 2026-11-21 20:41 (items 27-35, 39, 41, 42, 44) —
  [DELIVERY:1019-1021](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Driver faults interrupting tests ("did not finish", first blamed on the virtual pad); low-memory kills of tests on
  the 8 GB dev phone — [DELIVERY:5257-5273, 4687](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Test-harness faults fixed as hardening: walls-phone-test counted a finished Dragon's Tooth; "two tests' own
  faults"; pad-test -Share/-Chat placed their widget too early; Area Mex flake open — [DELIVERY:84-96, 240, 875](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- BAR's own moving releases (test-31992 -> test-32018, a newer release fetched mid-session) drive menu-copy remakes
  and the 200-locals limit — [DELIVERY:542-553](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Parallel sessions share the dev phone: playtest and a "playtest-fixes" session side by side on 11-22 —
  [PLAYTEST.md:368-369](C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md)

### Inferences
- Owner time is the scarcest resource (~1 h/day): the 8 pending owner tests and the owner decisions will not clear
  themselves; they need a short, ordered ask.
- Fold7 builds lag the dev phone by hours to a day whenever the adb link drops; anything that must be on the Fold7
  for the release should be batched into one install while it is reachable.

### Gaps
- Per-topic time breakdown (hardening vs features vs docs) is not in WORKLOG.md; worklog.py's data could give it but
  was not processed here.
- 2026-11-22's worklog page is mostly AIRDROP-session text; the playtest's own time is not separated.

## 6. Constraints that apply

### Takeaway
Work is bounded by: one shared dev phone (S23 Ultra, 8 GB) behind a queue lock; the Fold7 as the owner's daily
phone (installs allowed without asking, never while he plays, no benchmarks); no BAR runs on the laptop; online play
must keep working with only online-safe changes and an engine pinned to BAR's server version; private GitHub repos
only, with any public step being Kailil's.

### Cited Findings
- Dev phone: the agents' own 24/7, screen kept dark (`tools\devphone.ps1`), tests and benchmarks there —
  [CLAUDE.md:4-15](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md); it is an 8 GB S23 Ultra in the low-memory mode,
  "about 2 in 3 five-minute skirmishes run through" (2026-10-29 note) — [CLAUDE.local.md](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.local.md)
- Lock: `devphone-lock.ps1 take <who> [-Minutes 60]` queues and waits, `free` gives back; "Keep holds under ~45 min
  and free between chunks"; one file per waiter — [devphone-lock.ps1:1-12](C:/Tools/BARANDROID/bar-droid-engine/tools/engine-sim/devphone-lock.ps1);
  benchmarks additionally take `phone-bench.lock` — [CLAUDE.md:275](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- Fold7: "only for builds that need his own testing ... no benchmarks or monitoring on it unless necessary, never
  while he plays. Install every build that needs his testing on the Fold7 right away, even over a running game; never
  ask first" — [CLAUDE.md:8-11](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- No emulator for checks — [CLAUDE.md:15](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- No BAR tests on the laptop (2026-11-19), hook-enforced; laptop builds are fine — [CLAUDE.local.md](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.local.md)
- Lobby tests never log in; the login file is not read — [CLAUDE.md:288-292](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- Online: "Only online-safe changes (Kailil, 2026-10-27: 'we MUST have online play enabled')"; anything the
  simulation or archive checksums see stays BAR's own — [HANDOFF.md:310-312](C:/Tools/BARANDROID/bar-droid-app/HANDOFF.md); [CLAUDE.md:311-315](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- Engine pinned to BAR's server version (launcher config), official or the phone build; a new phone build ships only
  after the gate; "no APK carrying one goes out before the branch's source is public" — [CLAUDE.md:320-329](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- BAR content only from BAR's CDNs; BAR's devs cleared phone-made derivatives (NOTICE credits); Kailil's personal icon
  never in a published APK — [CLAUDE.md:311-319](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- GitHub: private (UnderarmCape/bar-droid and bar-droid-engine), `tools\github-sync.ps1` after each commit,
  `-Release` after a Fold7 install; "Never force a branch; the repositories stay private unless Kailil says
  otherwise" — [CLAUDE.md:305-310](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- "Nothing is pushed, published or posted without Kailil" (public release) — [DELIVERY:5-6](C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md)
- Worklog rule: run `tools\worklog.py` before the last commit of each session — [CLAUDE.md:301-304](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md)
- Upstream PRs to Recoil/CircuitAI need an accepted issue and AI disclosure; upstream reports need Kailil's go-ahead
  — [CLAUDE.md:330](C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md); [HANDOFF.md:341-344](C:/Tools/BARANDROID/bar-droid-app/HANDOFF.md)
- Hand-off goal: "no known bugs and build from a clone with README's three steps; every fix keeps
  tools/laptop-tests.ps1 passing" — [HANDOFF.md:346-351](C:/Tools/BARANDROID/bar-droid-app/HANDOFF.md)

### Inferences
- The "every fix keeps laptop-tests passing" rule and the no-laptop-BAR rule conflict; the DELIVERY owner list
  already flags it, so release step 1 needs a phone-side substitute or an owner waiver.
- Test throughput is capped by one 8 GB phone shared across parallel sessions; a full round of ~20 scripts at 2-7 min
  each is roughly an hour of phone time, before re-runs for driver faults or LMK.
- The release being "private" (per the brief) is narrower than DELIVERY's public GitHub plan; which repository and
  which APK (debug with personal icon vs public-icon release build) a private release uses is not decided in the docs.

### Gaps
- No document states the scope of the ~2026-11-25 release (who receives it, which APK variant); DELIVERY describes
  only the public GitHub release.
- Whether the Fold7's current build includes items 46, 50, 51, 54 and the 2026-11-22 playtest fixes is not recorded.
