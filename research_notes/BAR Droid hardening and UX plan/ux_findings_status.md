# BAR Droid touch playtest (2026-11-21/22): status of every UX / UX bug / QOL finding

[P]: file:///C:/Tools/BARANDROID/bar-droid-app/docs/PLAYTEST.md
[F]: file:///C:/Tools/BARANDROID/toolchain/tmp/play/fixes.md
[B]: file:///C:/Tools/BARANDROID/toolchain/tmp/play/fixer-builds.txt
[D]: file:///C:/Tools/BARANDROID/bar-droid-app/docs/DELIVERY.md
[C]: file:///C:/Tools/BARANDROID/bar-droid-app/CLAUDE.md
[T]: file:///C:/Tools/BARANDROID/toolchain/tmp/play/touchlog.csv
[G]: file:///C:/Tools/BARANDROID/bar-droid-app
[PL]: file:///C:/Tools/BARANDROID/bar-droid-app/app/src/main/assets/bardroid/bardroid_portrait.lua
[PY]: file:///C:/Tools/BARANDROID/toolchain/tmp/play/play.py

Source keys used below: P = docs/PLAYTEST.md (line numbers), F = toolchain\tmp\play\fixes.md, B = fixer-builds.txt,
D = docs/DELIVERY.md, C = CLAUDE.md, T = toolchain\tmp\play\touchlog.csv (the driver's every touch, 10,283 rows,
from 22:55 on 11-21; games 1-2 were driven by plain adb input before it existed), G = git history of bar-droid-app
(`git log` / `git show --stat`), PL = app/src/main/assets/bardroid/bardroid_portrait.lua.

Status words: **FIXED+PLAY** = fixed and then confirmed in play (PLAYTEST game 8/9 "FIXED"); **FIXED-UNCHECKED** =
fixed and passed the fixer's scripted phone test, but not confirmed in play; **PARTIAL**; **OPEN** = not addressed;
**OWNER** = design question for Kailil; **UPSTREAM** = BAR's / Chobby's own behaviour; **UNCLEAR**; **KEEP** = a
"UX good" entry. The Severity and Frequency columns are my assessment (see Inferences), not logged facts.

## Q1. Which findings does docs/PLAYTEST.md log (all games), and what is each one's status?

### Takeaway
PLAYTEST.md logs about 50 UX / UX-bug / QOL / to-check items across New Beginning games 1-6 and skirmish games 1-11
(plus 13 "UX good" entries and a few notes). Only 6 distinct fixes have been confirmed in play, 6 more are fixed but
unconfirmed, and roughly 30 items were never taken up by the fixer session, which was halted at 14:30 on Kailil's
instruction ([F:63][F]).

### Cited Findings

Context of the playtest: an agent played on the dev phone (Galaxy S23 Ultra, 1080x2316, upright) using only the app's
own touch controls through `adb shell input`, with the game paused between looks ([P:8-11][P]). From game 3 on it used a
laptop driver that turns decisions into real touches; "Orders still go only through the app's touch controls" ([P:121-130][P]).
The fixer session ("playtest-fixes") ran in parallel from 10:05 ([P:368-369][P]).

#### Master table

| ID | Game / time | Tag | Finding (brief) | Status | Evidence | Sev. (assessed) | Freq. (assessed) | Theme |
|---|---|---|---|---|---|---|---|---|
| NB1-1 | NB g1 21:45 | NOTE | BAR's "Register your account" window opens over the lobby on the app's first open, before the home page | OPEN / UPSTREAM (BAR's first-start login window; the tests start the lobby with it off) | [P:55-57][P] | Low | Once per install | Pre-game flow |
| NB1-2 | NB g1 21:46 | NOTE | "New Beginning" is 16th of 22 (list sorted by difficulty) | NOTE, not a defect | [P:58-59][P] | - | - | Lobby |
| NB1-3 | NB g1 21:48 | UX | Scenario starts paused under the Mission window; nothing says how to start (tapping Mission on the top bar started it) | OPEN (not in the fix track) | [P:62-65][P]; by design the Mission Info copy closes and unpauses on a finger's tap ([D:1975-1979][D]) | Medium | Every scenario start | Pre-game flow; state visibility |
| NB1-4 | NB g1 21:48, NB g2 22:20 | QOL | No pause control on the touch interface in a skirmish or scenario | OPEN | [P:66-68][P], [P:104-105][P]; a search of PL for "pause" finds only comments, no pause button ([PL][PL]) | Medium | Often (calls, reading the build menu) | Missing control |
| NB1-5 | NB g1 21:51 | UX, to check | INSERT on, then a Bot Lab placed: not at the front of the commander's queue | FIXED-UNCHECKED (root cause found in H4-1; 89286296) | [P:72-74][P]; [F:35-38][F] | Medium | Sometimes | Modifier state (QUEUE/INSERT) |
| NB1-6 | NB g1 21:55 | UX / QOL | Build grid's page drag went a page too far, picked the floating twin; the dock never names the picked building or the tile under a finger; QOL: name on PLACE panel or long press on a tile | OPEN | [P:80-83][P] | Medium-High | Every game for a new player | Discoverability; grid navigation |
| NB1-7 | NB g1 21:55 | UX | End screen: the Mission window (left open as pause) over BAR's Awards, texts overlapping; dock gone, lower half empty | OPEN | [P:84-85][P] | Low | Scenario end with Mission open | End flow |
| NB2-1 | NB g2 22:05 | UX | First map tap at the paused start closed the Mission window and unpaused; it was meant to pick a spot ("the window is also the pause") | OPEN; OWNER-ish (the tap-to-close is deliberate, patch 5) | [P:89-91][P]; [D:1975-1979][D] | Medium | Every scenario start | Pre-game flow; mode |
| NB2-2 | NB g2 22:06 | UX, to check | QUEUE on: a tap on a unit adds it to the selection (BAR's Shift-click) instead of selecting it alone; QOL: taps on units ignore QUEUE | OPEN (never in the fix track, never re-checked) | [P:92-94][P] | Medium | Often when QUEUE is left on | QUEUE state |
| NB2-3 | NB g2 22:09 | NOTE | Commander's Move is the 9th of 9 order buttons (foot of the column) while the build grid is up | OPEN (note) | [P:99-100][P] | Low-Medium | Often | Discoverability |
| NB2-4 | NB g2 22:12 | NOTE | AUTO RETREAT turned the commander back too late vs Tech 2 aircraft ("cannot save it from air") | OWNER (retreat semantics) | [P:101-103][P] | Medium | Air-heavy games | Automation semantics |
| NB2-5 | NB g2 22:21 | UX | Zoom rail moves by finger speed: three slow full-length drags zoomed out ~1/5, two fast ones jumped to the whole corner; "a player reads that as the rail is broken"; QOL: floor on the slow step | OPEN (speed-scaled steps are by design: camStepGain, [C][C] bardroid_camctl.lua) | [P:106-109][P] | Medium | Every rail user | Camera |
| NB2-6 | NB g2 22:22 | UX | Build grid scrolls by rows, not pages; finding the Nettle took two drags; no names | OPEN | [P:110-112][P] | Medium | Every game | Grid navigation; discoverability |
| NB2-7 | NB g2 22:36 | UX / QOL | No unit/building name anywhere on the dock's tiles (factory, build grid, PLACE panel); the Advanced Bot Lab's 18 pictures told apart only from BAR's unit files; a long press on a tile shows nothing (tried); QOL: long press shows name and role | OPEN | [P:114-117][P] (the selection row does name a selected unit, [PL:3637][PL]) | High for new players | Every build choice | Discoverability |
| NB3-1 | NB g3 23:05 | UX | BAR's lobby over a running game: Start Scenario does nothing, no "leave the running game?" prompt; game had to be stopped from the launcher | OPEN (UNCLEAR whose: likely Chobby's flow) | [P:134-135][P] | Low | Rare | Lobby; silent failure |
| NB3-2 | NB g3 23:10 | UX good + UX | Dock leaves out forbidden units (good), but the grid's rows then differ from BAR's order, so a tile's place is learned only by looking | KEEP / OPEN (minor) | [P:140-142][P] | Low | Scenarios with limits | Discoverability |
| NB3-3 | NB g3 23:12 | UX | With a building picked or an order armed, a one-finger drag moves the building / draws the line, not the camera: to place off-screen let go (X), pan, pick again; two-finger pan or the knob would need to be discoverable | OPEN (the driver works around it by turning QUEUE off before each pan, [P:410-411][P]) | [P:143-146][P] | High | Every game | Camera vs order drags |
| NB3-4 | NB g3 23:14 | UX | Camera knob (bottom right) and the turn rail take taps meant for the map: 4 of 6 converter spots went to the camera | OPEN | [P:147-149][P] | Medium-High | Often (placing near the dock's top edge) | Touch-target conflicts |
| NB3-5 | NB g3 23:16 | UX | Energy bar (nothing selected) lies where QUEUE is (something selected): a tap meant for QUEUE opened the energy panel; converters only work above 75 % storage and "A new player will not find that slider" | OPEN | [P:150-153][P]; the driver closed the panel twice ([T][T] "close energy panel" 23:45, 00:08) | Medium | Sometimes / every converter user | Touch-target conflict; hidden rule |
| NB3-6 | NB g3 23:20 | UX | Android Back over the game opened BAR's lobby (Escape), also with units selected; twice it left the battle | UNCLEAR: conflicts with the shipped "Back in a game is contextual" (2026-11-20, 8acbde4f: first Back clears selection and menus, then the quit question / lobby) ([D:51-70][D]) | [P:154-155][P]; the driver sends Back as `input keyevent` ([PY:49-50][PY]) | Medium | Often (Back is habitual) | Back / mode |
| NB3-7 | NB g3 23:27; Easy g1 13:21 | UX | Tap on a factory's middle selects the unit in its yard (a new Archangel; a half-built Centurion that the commander then guarded); the back edge works | OPEN (engine/BAR unit picking; UNCLEAR whether app-fixable) | [P:156-157][P], [P:250-251][P] | Medium | Often | Picking precision |
| NB3-8 | NB g3 23:28 | UX | ALL UNITS selects land units only (Falcon fighters not in it; no aircraft picture) | OPEN (UNCLEAR if by design) | [P:158-159][P] | Medium | Often for air play | Filters; discoverability |
| NB3-9 | NB g3 23:30 | UX | FACTORIES selected the Advanced Bot Lab once, the Bot Lab another time, "no hint which one comes next" | PARTIAL / pre-existing: since a5a9e960 (2026-11-13) FACTORIES says "BOT LAB (1 OF 2)" as a note and draws a gold wait bar ([PL:2568-2582][PL], [PL:3376][PL]); the agent did not see it | [P:160-161][P]; [G][G] a5a9e960 "FACTORIES names the factory it comes to" | Low | Sometimes | Feedback visibility |
| NB3-10 | NB g3 23:44 | UX | Guard on a constructor made the commander follow it out of AA cover twice; no "assist this building" apart from Guard and Repair | OPEN / UPSTREAM (BAR's Guard follows a moving unit) | [P:162-163][P] | Medium | Sometimes | Order set |
| NB3-11 | NB g3 23:55 | UX | Liche (atomic bomber) has no Move and no Attack among the dock's orders; a ground strike has no button; long press only moves; a factory out of sight cannot be targeted | OPEN | [P:164-166][P] | Medium (High for bomber play) | Rare-Sometimes | Order set; far targets |
| NB3-12 | NB g3 23:58 | UX | Chat text sent with Enter right after typing stayed unsent (twice); a second Enter sent it | OPEN / UNCLEAR (could be the driver's key timing) | [P:167-168][P] | Low | Unknown | Silent failure |
| NB45-1 | NB g4/5 03:10 | UX good + UX | "Tap then drag" box takes units not buildings (reliable); a double tap on a constructor among converters/turrets selected the building 3 times of 4 | KEEP / OPEN (picking) | [P:187-189][P] | Medium | Often in dense bases | Picking precision |
| NB45-2 | NB g4/5 03:12 | UX | LOCAL UNITS and ALL UNITS take combat units only (no constructors, no aircraft), with no hint | OPEN | [P:190-191][P] | Medium | Often | Filters; discoverability |
| NB45-3 | NB g4/5 03:20 | UX | Order buttons are redrawn for a new selection a moment after it changes; a tap in that moment lands on the previous selection's button (twice the factory's +1 took a tap meant for an order) | OPEN | [P:194-195][P] | Medium | Sometimes (fast taps) | Stale layout / timing |
| NB6-1 | NB g6 03:50 | UX | D-gun AIM stick does not follow the stick's direction while paused (65 deg, -12 deg, then nothing) | FIXED-UNCHECKED (89286296 dead zone; e952aae4 screen-relative); game 8 still "NOT YET" paused | [P:206-207][P]; [P:377-380][P]; [F:16-26][F] | High (a wasted D-gun) | Every stick aim | D-gun mode |
| NB6-2 | NB g6 03:55 | UX (lobby) | Difficulty list ignores an 80 ms tap, takes a 200 ms one; the scenario list's drag keeps its fling, so the same drag stops at a different scenario (three wrong scenarios opened) | OPEN ("Not fixed, noted": not reproducible from the code, needs a phone trace; the fling part not mentioned) | [P:208-210][P]; [F:49-50][F] | Low-Medium | Sometimes | Lobby touch |
| E1-1 | Easy g1 6:55 | UX / QOL | A Sentry placed alone gets 8 Dragon's Teeth by default (64 metal on top of 85, unasked); the WALLS switch shows only while a Sentry is picked; cost not shown | Cost: FIXED+PLAY ("WALLS +64", game 8 "FIXED", small type). Default on: OWNER (Kailil's spec "on by default", [D:1253-1258][D]) | [P:242-244][P]; [F:32-34][F]; [P:379][P] | Medium (early metal) | Every game with Sentries | Automation; cost feedback |
| E1-2 | Easy g1 7:03 | UX | Commander + Metal Extractor: auto-mex queues in-range spots and puts the extractor away, so a tap for a farther spot lands nowhere; BAR's snap puts an extractor tapped on a covered spot onto the nearest really free one (600 elmos away, twice); ghost shows it | Auto-mex: OWNER (by design; Kailil "it may also just fire every time", [D:1946-1953][D]; [F:49-50][F]). Snap: UPSTREAM (BAR's) | [P:245-249][P] | Medium | Every game start | Automation; feedback |
| E1-3 | Easy g1 19:06 | UX | D-Gun button opens a mode (MOVE/AIM sticks, FIRE) instead of arming a target tap; no quick "D-gun that unit" | PARTIAL: a map tap in the mode aims (89286296; FIXED+PLAY games 8 and 9); a tap on an enemy keeps aim on it, led (3104771e; FIXED-UNCHECKED). Mode vs one-tap order: OWNER | [P:252-253][P]; [P:378][P]; [P:402-405][P]; [F:16-21][F], [F:57-59][F] | Medium | Every D-gun use | D-gun mode |
| E1-4 | Easy g1 21:20 | UX / QOL | AUTO RETREAT sends hurt units home one at a time during an attack; walkers alone picked off; QOL: during a Fight the hurt fall back to the group | OWNER (retreat semantics) | [P:258-259][P] | Medium | Every push with retreat on | Automation semantics |
| E1-5 | Easy g1 22:00 | UX | A tap on a constructor next to a new Sentry or wind selected the building (three times); box and COMMANDER were the reliable ways | OPEN | [P:260-261][P] | Medium | Often | Picking precision |
| E2-1 | Easy g2 05:27 | UX bug | Before the start the dock has no QUEUE; every placement replaces BAR's pre-game queue: one building, not a build order | FIXED+PLAY (89286296; game 9 "FIXED": Bot Lab and an extractor stayed queued) | [P:277-279][P]; [P:395-396][P]; [F:27-31][F] | High (opening) | Every lobby game | Pre-game flow; QUEUE |
| E2-2 | Easy g2 05:27 | UX | Before the start, a map tap with no building picked moves the start position (the commander's start onto a metal spot) | OPEN (not in the fix track) | [P:280-281][P] | Medium | Every lobby game with a pre-queue | Pre-game flow; mode |
| E2-3 | Easy g2 06:14 | NOTE / QOL | Game end goes back to the lobby 12 s later (BAR's autoquit); the "Leaving the game in 4 s, tap the screen to stay longer" line is clear, "though 12 seconds is short for a phone put down" | OPEN (minor) | [P:284-286][P] | Low | Every game end | End flow |
| M3-1 | Medium g3 | UX / QOL | Factory Repeat repeats the whole queue, constructors included; QOL: Repeat only for combat units, or a mark per entry | OWNER ("a design change, left for Kailil"); BAR's own Repeat | [P:299-301][P]; [F:46-47][F] | Medium | Every game using Repeat | Automation semantics |
| H4-1 | Hard g4 07:20 | UX | INSERT on a builder did not put a placed building at the queue's front (twice); on a factory it works | FIXED-UNCHECKED (89286296: QUEUE+INSERT sent Shift+Alt; builders now use prepend_queue; touchfix-phone-test PASS) | [P:314-315][P]; [F:35-38][F] | Medium | Sometimes | Modifier state |
| H4-2 | Hard g4 07:25 | UX | A Move given to the commander drops its build queue (as a mouse click in BAR); with QUEUE as a separate switch it is easy to wipe a long queue when pulling the commander out of danger | OPEN (BAR semantics; app-side guard would be a design call) | [P:316-317][P] | High (lost queue) | Often | QUEUE state |
| H5-1 | Hard g5 14:50 | UX bug | D-gun mode: AIM drag did not turn the aim line (paused or running); FIRE shot the old line while ten Flashes stood east; D-gun wasted | Map-tap aim: FIXED+PLAY. Stick: FIXED-UNCHECKED | [P:331-334][P]; [F:16-26][F] | High | Every stick aim | D-gun mode |
| H5-2 | Hard g5 14:59 | UX / QOL | Commander at 23 % on the player's Fight: AUTO RETREAT did not take it out; QOL: retreat over the player's Fight, or a warning | PARTIAL: by design no second retreat ("once only"); warning "COMMANDER AT N %: PULL IT BACK" under 30 % added (89286296), "Not phone-tested (luacheck, read through)", not seen in play | [P:335-336][P]; [F:43-45][F] | High (commander loss) | Sometimes | Automation; warnings |
| H5-3 | Hard g5 07:50 | UX (lobby) | Quick Skirmish's four map tiles changed places between visits | FIXED+PLAY (1114d607; game 9 "FIXED"; lobby-phone-test ALL PASS twice) | [P:337-338][P]; [P:394-395][P]; [F:39-42][F] | Medium | Every lobby visit | Lobby |
| H6-1 | Hard g6 7:02 | UX bug | BAR's build menu arms a building's sea twin while the pointer last stood over water (Bot Lab -> Shipyard ghost) and the dock keeps the land picture | FIXED+PLAY on the phone engine (a63ecb0a, phone patch of cmd_context_build.lua; game 8 "FIXED"). Official engine: "BAR's own file (old behaviour)": UPSTREAM candidate | [P:348-353][P]; [P:377-378][P]; [F:7-15][F] | Medium-High | Maps with water / map edge | Pointer left behind |
| H6-2 | Hard g6 0:13 | UX | QUEUE turned off by something other than the player (a LuaUI reload) makes the next placement replace the whole queue; QUEUE's state easy to miss | Visibility: FIXED+PLAY ("+ QUEUE" on PLACE, game 8 "FIXED"). The reset itself: not addressed (dev-tool trigger) | [P:354-355][P]; [F:43-46][F]; [P:379][P] | Medium | Sometimes | QUEUE state |
| H7-1 | Hard g7 0:06 | UX / QOL | AIM stick turns ~30 deg/s while held ("a rate, not a direction"), a quick flick does nothing; QOL: absolute aim or a map tap as target | Map tap: FIXED+PLAY. Stick: FIXED-UNCHECKED. Diagnosis disputed (see below) | [P:359-362][P]; [F:16-21][F] | High | Every stick aim | D-gun mode |
| H8-1 | Hard g8 21:34 | UX / QOL | An order's target far off the screen cannot be given without panning there; the minimap (top left) is too small to tap upright; the driver could not pan a far point on-screen; QOL: larger minimap, or PING/LAST PINGS places as order targets | OPEN | [P:384-390][P] | High (late game) | Every late push | Far targets / minimap |
| H9-1 | Hard g9 12:02 | UX / QOL | Pre-game: PLACE stands where ARMADA/CORTEX stand once the panel closes; a late PLACE tap switched to Cortex (queue became Cortex's); the wind/tide box covers the QUEUE row's hint | FIXED-UNCHECKED (3104771e: faction taps dropped 0.8 s after the panel changes, a second tap within 3 s when a queue exists; hint under the nook); "CHECK IN PLAY" | [P:397-400][P]; [F:53-56][F]; [B:5][B] | Medium-High (wrong faction) | Every lobby game with a pre-queue | Pre-game; touch-target conflict |
| H9-2 | Hard g9 12:20 | UX / QOL | In D-gun mode the camera follows the commander, so a unit tapped a moment before has moved; QOL: a tap on an enemy aims at and leads it | FIXED-UNCHECKED (3104771e dgunTrack; "The test's given enemy spawned out of sight, so the tap itself is NOT phone-tested") | [P:408-409][P]; [F:57-59][F] | Medium | Every D-gun at a mover | D-gun mode |

Duplicates folded into the rows above: Easy g1 13:21 (Guard on a factory hits the yard unit) = NB3-7
([P:250-251][P]); the driver's note in game 9 (QUEUE on + order armed: a drag draws the order's line, not a pan) =
NB3-3 ([P:410-411][P]); NB g2 22:20 pause = NB1-4.

Notes that are not UX findings (for completeness): the driver's uinput timing bug ([P:136-139][P]); commanders are
immune to the D-gun, Kailil ([P:405-407][P]); converters side by side chain-explode ([P:232-233][P]); energy buildings
"by the base" walled in both Bot Labs' exits in game 8 (the driver's placement; no in-game warning) ([P:381-383][P]);
the Overwatch at the north-east way in "failed to place several times in a row" in game 11, cause not logged
([P:417-420][P]).

#### Fix commits (git)
- 89286296 (11:12:21) "Touch playtest fixes: D-gun aim, pre-game QUEUE, WALLS' cost, INSERT on builders, QUEUE on
  PLACE, the commander's warning": bardroid_pad.lua, bardroid_portrait.lua, bardroid_retreat.lua, bardroid_walls.lua,
  bardroid_buildmenu.lua/.patches, make-buildmenu.py, new tools/touchfix-phone-test.ps1 + test widget (10 files, +850/-34) ([G][G]).
- a63ecb0a (11:12:26) sea twins: phone-widget-cmd_context_build.lua.patch (+76) ([G][G]).
- 1114d607 (11:12:27) quick Skirmish maps in name order: bardroid_lobby_touch.lua (+70) ([G][G]).
- e952aae4 (11:58:17) "the dock's D-gun sticks aim along the screen from the commander": bardroid_pad.lua
  screenHeading, the test turns the camera ~130 deg ([G][G]).
- 3104771e (13:27:50) game 9's three: faction buttons under PLACE, pre-game hint under the nook, D-gun tap on an
  enemy: bardroid_pad.lua dgunTrack, bardroid_portrait.lua ([G][G]).
- Playtest-log commits: bdaea14d, 135a2381, be0f3177, 4572f452, 2ff24814, 60f28b7e, 55590c1b, ebbfa088, 3c9d0608,
  c8047722, 86274817, 4641ba84 (last, 13:51 "Hard games 10 and 11") ([G][G]). Working tree: only untracked reports/
  and research_notes/ ([G][G] `git status`).

### Inferences
- Severity scale used: High = loses units, a queue, the commander or the opening, or blocks a task; Medium = a wrong
  or wasted action that can be undone; Low = confusion or cosmetics. Frequency is judged for a human player on an
  upright phone; it is an estimate from how often the situation arises in the logged games, not a measurement.
- Some findings may be partly artefacts of the agent's input (taps of 60-130 ms, fast follow-up taps, keys via
  `input keyevent`): NB45-3 (stale buttons), NB3-12 (chat Enter) and NB6-2 (80 ms taps). An 80 ms tap is within a
  human's normal tap length, so NB6-2 likely affects real players too.
- Diagnosis conflict on the AIM stick: PLAYTEST game 7 calls it "a rate, not a direction" ([P:359-362][P]); the fixer
  found "Not a rate: the aim followed the stick's way already, but only past HALF its ring" ([F:16-17][F]). The fixer
  could not reproduce the game-8 "NOT YET" report on a turned camera and asked for the flick's exact display points
  ([F:22-26][F], [B:3][B]); that never came before the halt, so the stick's status in play is genuinely unknown.
- The sea-twin fix only exists on the phone engine (the engine applies the patch); on the official engine fallback
  the bug is still there ([F:14-15][F]).

### Gaps
- Games 1-2 (21:45-22:45) have no touch log; their findings rest on PLAYTEST text and screenshots only.
- NB3-6 (Back): whether the playtest's Back went through the contextual dock_back path is not recorded; needs a repro.
- No severity or frequency was logged by the playtest itself; the columns are my assessment.
- Whether ALL UNITS / LOCAL UNITS excluding constructors and aircraft is intended was not found in DELIVERY.md or PL
  (searched); UNCLEAR.

## Q2. Which findings were fixed, and which fixes were confirmed in play?

### Takeaway
Twelve fix items in five commits on 11-22 (89286296, a63ecb0a, 1114d607, e952aae4, 3104771e) cover 14 logged
findings (NB1-5, NB6-1, E1-1, E1-3, E2-1, H4-1, H5-1, H5-2, H5-3, H6-1, H6-2, H7-1, H9-1, H9-2) (several were logged more than once). Six fixes were confirmed in play in games 8 and 9. Six are still
unconfirmed in play: the D-gun AIM stick, INSERT on builders, the commander warning and all three game-9 fixes.

### Cited Findings
- Confirmed FIXED in play, game 8 (on the fixer's uncommitted 10:52 build, the same code as 89286296 + a63ecb0a +
  1114d607 [B:1-2][B]): sea twins ("Solar and Converter picked with the camera over the map's edge armed
  armsolar/armmakr"), "the D-gun mode's map tap aims the shot (paused too)", "+ QUEUE" on PLACE, "WALLS +64" (small
  type) ([P:377-379][P]).
- NOT YET in game 8: "the AIM stick paused (a quick flick moved nothing) and with a turned camera (a flick right aimed
  screen down-right: world axes, not the view's); sent back" ([P:379-380][P]).
- Confirmed FIXED in play, game 9 (build e952aae4): quick Skirmish maps in name order at every visit; pre-game QUEUE
  row, with it on "the Bot Lab and an extractor stayed queued before the start" ([P:394-396][P]). The D-gun map tap
  also aimed two D-guns at BARb's commander in game 9 ("the aim line went onto it, FIRE fired") ([P:402-405][P]).
- Fixed but not checked in play:
  - D-gun AIM stick: touch AIM from a fifth of the ring (89286296), sticks screen-relative (e952aae4); scripted test
    "1-2 degrees off" for 80/300 ms flicks, running and paused, camera turned ~130 deg ([F:16-26][F]).
  - INSERT on a builder under QUEUE: prepend_queue; "Tested: INSERT alone, QUEUE+INSERT twice: the winds ahead of the
    queued Solars" ([F:35-38][F]). Not mentioned in any later PLAYTEST check.
  - Commander warning under 30 %: "Not phone-tested (luacheck, read through)" ([F:43-45][F]).
  - Pre-game faction guard and the hint under the nook: "Pre-game only: CHECK IN PLAY" ([F:54-56][F]).
  - D-gun tap on an enemy unit (lock + lead, "D-GUN: TARGET LOST"): "NOT phone-tested: CHECK IN PLAY"; a ground tap
    clearing it was tested ([F:57-59][F]).
- The fixer's suite: touchfix-phone-test ALL PASS (14 cases, 11:10), later ALL PASS again 13:27 ([F:3-5][F], [F:60][F]).
- Deployment: Fold7 got e952aae4 at 12:05 and 3104771e at 14:28 (installed by the playtest session); fixer halted
  14:30, "Open for in-play checks: the D-gun enemy tap, the pre-game faction guard and hint" ([B:4-8][B]; [F:63][F]).
- Noted, not fixed: the lobby's Difficulty list 80 ms tap ("could not reproduce from the code; needs a phone trace");
  auto-mex putting the extractor away ("by design, Kailil's 'sent at once'") ([F:49-50][F]).
- Games 10 and 11 (after 3104771e reached the dev phone at 13:28) log no checks of the game-9 fixes ([P:413-424][P]).

### Inferences
- The pre-game fixes (faction guard, hint) can only be checked from a lobby-started game: "a skirmish the app starts
  begins at once" ([F:28-31][F]); games 10-11 left no pre-game screenshots in toolchain\tmp\play (only g9-pre0..2 exist),
  which fits them being unchecked.
- Because the Fold7 now carries 3104771e, Kailil's own play is effectively the first in-play check of those fixes.

### Gaps
- No record shows whether e952aae4's screen-relative stick was ever flicked in play.
- The commander warning has not been seen on any screen (no screenshot or log line found).

## Q3. Which remain open, which are the owner's design calls, and which are BAR upstream?

### Takeaway
About 30 items are open with no fix attempt, led by discoverability (no names on tiles), camera-vs-order drags, far
targets and touch-target conflicts. About six are explicit design calls for Kailil: walls default, auto-mex, auto
retreat semantics, factory Repeat, D-gun as a mode, and the Mission window doubling as the pause. A handful are BAR's or
Chobby's own behaviour.

### Cited Findings
- OWNER (design):
  - Walls on by default: his spec reads "a toggle beside the place button's group rotate, on by default"
    ([D:1253-1258][D]); the playtest suggests cost display (done) "or start it off" ([P:242-244][P]).
  - Auto-mex: "sent at once without confirmation (Kailil: it may also just fire every time ...)" ([D:1946-1953][D]);
    fixer: by design ([F:49-50][F]); playtest: a farther tap "lands nowhere" ([P:245-249][P]).
  - Auto retreat: hurt units walk home one by one during a push; QOL "fall back to the group, not home"
    ([P:258-259][P]); a hurt commander on the player's Fight is not retreated, by design "the player's orders stay
    theirs, 'once only'" ([F:43-45][F]); retreat too slow vs air ([P:101-103][P]).
  - Factory Repeat repeating constructors: "BAR's own Repeat (the whole queue); a mark per entry is a design change,
    left for Kailil" ([F:46-47][F]; [P:299-301][P]).
  - D-gun as a mode rather than an armed target tap ([P:252-253][P]); partly bridged by the map tap and enemy tap.
  - Mission window as the pause: a tap meant for the map starts the game ([P:89-91][P]); the tap-to-close was made
    deliberately (patch 5, [D:1975-1979][D]).
- UPSTREAM (BAR / Chobby / engine behaviour):
  - Context Build sea-twin swap: fixed only by a phone patch; official engine keeps BAR's file ([F:7-15][F]).
  - Mex snap to the nearest really free spot ([P:247-249][P]).
  - Move drops the build queue "as a mouse's click does in BAR" ([P:316-317][P]).
  - Guard follows a moving unit ("BAR's guard follows a moving unit") ([P:162-163][P]).
  - Factory Repeat = BAR's ([F:46-47][F]).
  - Register-account window = "BAR's own first-start login window" ([P:55-57][P]).
  - Chobby shuffles quick-skirmish maps (`table.shuffle`): fixed app-side in 1114d607 ([F:39-42][F]).
- OPEN, no fix attempted (IDs from Q1): NB1-3, NB1-4, NB1-6, NB1-7, NB2-1, NB2-2, NB2-3, NB2-5, NB2-6, NB2-7, NB3-1,
  NB3-2, NB3-3, NB3-4, NB3-5, NB3-7, NB3-8, NB3-10, NB3-11, NB3-12, NB45-1, NB45-2, NB45-3, NB6-2, E1-5, E2-2, E2-3,
  H4-2, H8-1 (sources in the Q1 table).
- UNCLEAR: NB3-6 Back (conflicts with [D:51-70][D]); NB3-9 FACTORIES (pre-existing name note, a5a9e960); NB3-12 chat;
  the game-11 Overwatch placement failure ([P:417-420][P]).

### Inferences
- The highest-value open items (High severity and frequent): names on build/factory tiles (NB1-6, NB2-6, NB2-7), drags
  captured by an armed building or order (NB3-3), far order targets / small minimap (H8-1), Move wiping the queue
  (H4-2) and the pause button (NB1-4).
- Several OWNER items have a cheap middle path the playtest itself proposes (walls default stays, cost shown: done;
  retreat to the group during Fight; Repeat per entry), so the decision is about defaults and semantics, not effort.

### Gaps
- No message from Kailil ruling on the playtest's design questions was found in PLAYTEST.md, fixes.md or DELIVERY.md.
- "Way-forward plan" that caused the halt ([F:63][F]) was not found in these sources.

## Q4. What themes do the findings cluster into?

### Takeaway
Nine clusters. Discoverability and labels, modifier and mode state (QUEUE, INSERT, armed orders, D-gun mode) and
touch-target conflicts hold most of the open items. The camera-vs-order drag problem and far targets are the biggest
gameplay blockers. The pointer-left-behind class was fixed for the sea twins.

### Cited Findings
- Discoverability / labels: no names on tiles or PLACE (NB1-6, NB2-6, NB2-7: [P:80-83][P], [P:110-117][P]); Move 9th
  of 9 ([P:99-100][P]); grid order differs from BAR's ([P:140-142][P]); hidden 75 % converter rule ([P:150-153][P]);
  ALL/LOCAL UNITS filters unexplained ([P:158-159][P], [P:190-191][P]); no Attack-ground for bombers ([P:164-166][P]);
  WALLS cost (fixed, [F:32-34][F]).
- Mode / state visibility (QUEUE, INSERT, armed orders, pause): QUEUE making taps Shift-clicks ([P:92-94][P]); QUEUE
  lost silently ([P:354-355][P], "+ QUEUE" fixed); Move wiping the queue ([P:316-317][P]); INSERT not at the front
  ([P:72-74][P], [P:314-315][P], fixed); paused start with no hint ([P:62-65][P]); the Mission window doubling as pause
  ([P:89-91][P]); no pause button ([P:66-68][P]).
- D-gun mode: stick aim ([P:206-207][P], [P:331-334][P], [P:359-362][P]); mode vs order ([P:252-253][P]); moving
  targets ([P:408-409][P]).
- Pointer left behind (the X pointer rests where the last tap was): sea twins ([P:348-353][P], fixed for the phone
  engine). Earlier fixes of the same class in DELIVERY: BAR tooltips drawn over the dock where the pointer rested
  ([D:1669-1672][D], [D:1716-1718][D]).
- Camera vs order drags: armed building/order captures one-finger drags ([P:143-146][P], [P:410-411][P]); zoom rail
  speed-scaling ([P:106-109][P]); build grid row scrolling and page overshoot ([P:80-83][P], [P:110-112][P]).
- Touch-target conflicts and timing: knob/rail eat map taps ([P:147-149][P]); energy bar under QUEUE's place
  ([P:150-153][P]); faction buttons under PLACE ([P:397-400][P], fixed unchecked); stale order buttons
  ([P:194-195][P]); lobby taps and fling ([P:208-210][P]).
- Picking precision (a tap selects the wrong thing): factory yard unit ([P:156-157][P], [P:250-251][P]); building
  instead of constructor ([P:187-189][P], [P:260-261][P]).
- Pre-game and end flow: register window ([P:55-57][P]); Mission start ([P:62-65][P]); pre-game QUEUE (fixed,
  [P:395-396][P]); a pre-game tap moving the start spot ([P:280-281][P]); faction switch ([P:397-400][P]); maps
  shuffled (fixed); lobby over a running game ([P:134-135][P]); end screen overlap ([P:84-85][P]); 12 s autoquit
  ([P:284-286][P]).
- Far targets / minimap: ([P:384-390][P]); bomber targets out of sight ([P:164-166][P]); placing off-screen
  ([P:143-146][P]).
- Automation semantics and feedback after actions: walls ([P:242-244][P]); auto-mex putting the extractor away
  ([P:245-249][P]); auto retreat ([P:101-103][P], [P:258-259][P], [P:335-336][P]); Repeat ([P:299-301][P]); silent
  no-ops: Start Scenario ([P:134-135][P]), chat Enter ([P:167-168][P]).

### Inferences
- Many open items share one root: the dock has implicit modes (QUEUE as a sticky Shift, a picked building, an armed
  order, D-gun mode, the pre-game) that change what the same gesture does, and the mode is shown weakly. "+ QUEUE" on
  PLACE was the first step toward fixing that.
- Upright, the space at the dock's top edge is shared by the map, the camera knob/rails and changing dock rows, which
  explains the conflicts and stale-tap findings together.

### Gaps
- No user-research data exists; the themes come from one agent player's log.

## Q5. What did the "UX good" entries say works well (to keep)?

### Takeaway
The building and economy flow (mex spots lit, PLACE, QUEUE line, LINE), factory panels and Repeat, selection gestures,
long-press orders, area orders, the D-gun aim line, the end screen and save/load all held up. The summaries say the
touch controls "did everything asked of them".

### Cited Findings
- Scenario page reads well upright ([P:60-61][P]).
- Metal Extractor lights free spots green; tap + PLACE queues; QUEUE draws the queue as a green line; LINE dragged 11
  converters in one stroke ([P:69-71][P]).
- Tap on empty ground deselects; double tap selects every unit of the type on screen ([P:95-96][P]).
- Factory +1/+5/+20/-1/CLEAR/ORDERS panel, counts on pictures ([P:97-98][P]); it acts on the unit last tapped, and
  INSERT puts the next ones first ([P:256-257][P]).
- PLACE turns bright green when a spot is picked ([P:113][P]).
- The dock leaves out what a scenario forbids ([P:140-142][P]).
- D-gun mode's aim line drawn from the commander made a wrong aim visible before firing; FIRE killed two Pyros
  ([P:169-171][P]).
- "Tap then drag" box takes units, not buildings ([P:187-189][P]).
- Long press on an enemy = attack; with QUEUE, long press on the ground queues a move ([P:192-193][P]).
- Area order by arming and dragging out BAR's circle; QUEUE keeps it armed ([P:254-255][P]).
- Factory ORDERS page: Repeat + Fight rally kept the lab busy with no further touch ([P:282-283][P]).
- End screen: "Victory!", Awards (Show Graphs, Leave), tap-to-stay line ([P:298][P], [P:284-286][P]).
- Save by the top bar, Load Game from the lobby on a new build: "save and load work by touch" ([P:375-376][P]).
- Summaries: "The touch controls held up for all of it" ([P:214-215][P]); "The touch controls themselves did
  everything asked of them; the gap is the agent's macro and reaction" ([P:437][P]).

### Inferences
- The kept strengths cluster in the mid-game economy loop; the weak spots are around it (finding the right tile,
  moving the camera while something is armed, reaching far points).

### Gaps
- None of the "UX good" entries were checked by a human; all are the agent's judgement.

## Q6. Which dock flows and features were never exercised in the playtest?

### Takeaway
The playtest only covered 1v1 singleplayer on the S23 Ultra upright. It never touched PRESETS, LAST PINGS, PING/voice,
energy sharing, Statistics, Settings, replays, spectating, the online lobby, fold/unfold, the left-handed layout, the
gamepad, the layout editor, GRID/BORDER/ROTATE, Area Mex, factory presets, late game, T2 at scale or big armies.

### Cited Findings
- Touch-log tallies ([T][T], 10,283 touches 22:55-14:22): 7,461 taps, 2,624 drags, 123 holds, 49 tap-drags, 20 double
  taps, 6 pinches. Most-used labels: pan (2,164), let go (640), deselect (604), select (460), QUEUE on/off (388/376),
  place/spot for winds, converters, extractors, LLTs; order stop (158), fight (126), patrol (30), guard (23), repair
  (20), move (15), reclaim (10), D-gun (8), Repeat on (15), INSERT (18), home COMMANDER (81), ALL UNITS (74 + 12), FACTORIES
  (2), LOCAL UNITS (1), area reclaim (2), save (1), pre-game QUEUE (1), walls off (1). Zero touches labelled PRESETS,
  PING, LAST PINGS, share/SEND ENERGY, Statistics, Settings, chat, LINE/GRID/BORDER/ROTATE or camera knob/rail
  (a search for those words found only "close energy panel" x2, double taps and pinches).
- Used only by accident: the energy panel (opened instead of QUEUE, closed twice) ([P:150-153][P]; [T][T]).
- LINE used once, in game 1, before the touch log ([P:69-71][P]); the zoom rail in game 2 ([P:106-109][P]); a
  rail-turned camera in game 8 ([F:22-23][F]).
- Device and layout: dev phone S23 Ultra upright 1080x2316 only ([P:8][P]); the Fold7 only received installs
  ([B:4-7][B]); so no fold/unfold, no inner square screen, no landscape, no left-handed layout.
- Online and lobby: the lobby tests never log in (one account) ([C][C] "The lobby tests never log in"); only offline
  Simple Skirmish and scenarios were played; lobby over a game and Load Game were used ([P:134-135][P], [P:375-376][P]).
- Not yet exercised by the playtest's own account: "late game, T2, big armies: controls not yet exercised"
  ([P:422-424][P]). Longest game 31:48 (NB game 4) ([P:182-185][P]); skirmish games ended at 4:33-22:15.
- Also absent from the log: replays (speed column), spectating, Statistics (Show Graphs seen, not used), Settings
  search, speak to chat / voice ping, factory presets, MULTI type exclusion by long press, AUTO D-gun, the layout
  editor (three fingers), gamepad/first person, Free memory button. These features and their scripted phone tests are
  described in [C][C] (dock-phone-test, factory-preset-test, types-phone-test, attack-ping-test, stats-phone-test,
  settings-phone-test, replay-phone-test, camctl-phone-test left-handed) and [D:313-322][D], [D:1146-1151][D],
  [D:1207-1249][D].

### Inferences
- The untested areas are covered only by scripted phone tests that check mechanics (taps land, files change), not by
  a playthrough that judges UX. The release-relevant gaps are the Fold7's inner screen and fold/unfold, team games
  (energy share, pings, presets with allies) and the late game.

### Gaps
- Games 1-2 have no touch log, so features used only there (LINE, zoom rail) are known from PLAYTEST text alone.
- The touch log labels are the driver's own descriptions; a feature touched under a generic label (e.g. a "pan" that
  hit the knob) would not show in the tallies.
