# Playtest by touch: the scenario "New Beginning", then 1v1 skirmishes against the AI

Kailil, 2026-11-21 ~21:40: "fully play the game ... use the phone touch controls to fully play skirmish 1v1 Hard games
against the AI, and win ... start off in the first scenario new beginnings and complete the scenario ... then move to
doing the skirmish 1v1, easy first ... logging UX, UI and all other kinds of logs to determine bugs, UX possible
improvements, or QOL things". Brightness 25 % for these runs (tools\devphone.ps1 play).

How it is played: an agent on the dev phone (Galaxy S23 Ultra, 1080x2316, upright, the app's own touch controls: the
upright dock, taps, drags and long presses on the map; `adb shell input` stands in for the finger). An agent's look
at the screen (a screenshot) and its decision take seconds, so the game is paused between looks with the Pause key
(BAR's own pause; singleplayer only), unless the touch controls offer one (looked for in the first game, below).

## What the guides say (read 2026-11-21 before playing)

Sources: beyondallreason.info's guides (how to start and manage your economy, the in-depth look at economy, tips for
Supreme Commander / TA players) and the community's bar-for-new-players pages (standard playbook, wind, economy 101).

- Opening (Armada): the commander builds 2-3 Metal Extractors on the nearest spots first, then energy: Wind
  Turbines when the map's average wind is over ~10 (each about the wind speed in E/s, cheap in metal), else Solar
  Collectors (20 E/s each). "3 mex, 2 solar" as the universal start; then a Bot Lab (cheap, climbs hills, scouts and
  expands) and its first Construction Bots; 2-3 constructors by minute 2; a Radar Tower on high ground; 1-2 Light
  Laser Towers by the metal and the factory; 1-2 energy storages at 2-3 min.
- Balance: metal is the bottleneck. Keep energy 2.5-3x the metal income; an energy stall slows everything. Energy
  overflowing: Energy Converters (-70 E/s for +1 M/s each, a few, not ten). Metal piling up (1000+): more build power
  (a constructor or a Construction Turret per ~100 E/s and 5 M/s).
- Expansion: most starts have 3 metal spots; take 10-20 over the game, close ones first, each guarded by a Light Laser
  Tower. Reclaim rocks and wrecks (area reclaim) for early metal.
- The commander is weak in BAR: keep it behind the front; its D-gun kills anything but only when safe; losing it can
  lose a 1v1.
- Units: Fight (attack-move) to advance, Patrol to guard; builders on Fight or Patrol repair and reclaim on the way;
  line-drag moves spread a group; attack only when sure to get through.
- T2: after ~1000-2000 metal stored and +20 M/s, +500 E/s income; an Advanced Bot Lab or Advanced Vehicle Plant at
  5-6 min in a good game, Advanced Metal Extractors before a Fusion Reactor.
- Against the AI (players' reports): the AI has no plan; out-economy it, defend its early raids, then push with a
  bigger army.

## The scenario: "New Beginning" (scenario 21, by wilkubyk)

From its definition in BAR's lobby (luamenu/configs/gameconfig/byar/scenarios/scenario021.lua): Armada only, map
Death Valley v1.0.1, perceived difficulty 8.1 of 10 at Normal, par time 40 minutes. Win: destroy all enemy factories;
lose: all of your builders and factories gone. Its tips: build a Shield as soon as possible, try to capture an enemy
constructor (its tech), don't forget early AA. The player starts with the commander, three Advanced Metal Extractors, a
Cloakable Fusion Reactor and a Cloakable Jammer; the enemy (Cortex, BARb AI) holds a built-up base: 2 Bot Labs, a
Vehicle Plant, an Advanced Aircraft Plant and a Naval Hovercraft Platform, behind 18 Doomsday Machines, 20 Vipers, 16
Light Laser Towers, 4 Flak cannons, 6 Shield Generators, Dragon's Teeth lines, Radar and Shroud jammers. Some Armada
units are limited (no Bertha, Vulcan, nukes, T3 gantry; 2 Advanced Fusions, 6 Metal Makers).

## Log

Each entry: when (laptop clock), the game, what happened, and what it means (BUG, UX, QOL, or a note), with the
screenshot (toolchain\tmp\play\...) or log line behind it.

### 2026-11-21, New Beginning (Normal), game 1: HEAD 4b878e90, dev phone upright

- 21:45 NOTE (BAR's lobby): the app's icon opened the lobby with BAR's "Register your account" window over it
  (username, password, email twice): the first thing a player without an account sees, before the home page. Cancel
  closes it. (BAR's own first-start login window; the tests start the lobby with it off.) [nb-000]
- 21:46 NOTE: Kailil's "first scenario, New Beginnings" is listed 16th of 22, difficulty 8/15 (scenario021 in BAR's
  files); the lobby sorts by difficulty and the first is "Fortress Assault" (1/15). Played as named. [nb-002, nb-003]
- 21:46 UX good: the scenario page reads well upright (victory, loss, difficulty, time, faction and difficulty pickers
  left of the map, the tips under it). [nb-004]
- 21:48 UX: the scenario starts paused with the Mission window open ("Player paused the game", GAME PAUSED); nothing
  on the window says how to start. Tapping Mission on the top bar closed it and the game ran ("Player unpaused the
  game"). A player may sit at a paused game: a "Start" or close button on the Mission window, or a line saying "tap
  Mission to start", would say it. [nb-005, nb-006]
- 21:48 QOL: no pause control on the touch interface in a skirmish or scenario (the top bar has Save, Mission,
  Settings, Lobby; the Mission window pauses only in a scenario). A singleplayer pause button would help a phone
  player (a call, a look at the build menu) and is how this playtest keeps up (the Pause key stands in).
- 21:50 UX good: picking the Metal Extractor lights the free metal spots green, and a tap on one then PLACE queues it
  (QUEUE on: the commander's queue drawn as a green line, three spots in a row). LINE dragged a row of 11 Energy
  Converters in one stroke. [nb-007, nb-008, nb-009]
- 21:51 UX, to check: INSERT on, then a Bot Lab placed: it did not go to the front of the commander's queue (it built
  the converters first). Either INSERT does not reach a building's placement, or the order is "after the current
  one"; a player expects "next". [nb-010, nb-013]
- 21:52 NOTE: the start's economy (+780 energy from the Cloakable Fusion Reactor, +24 metal from three Advanced Metal
  Extractors) fills both storages within a minute; the commander alone cannot spend it (build power is the limit).
- 21:55 LOST (~3 min in): enemy Tech 2 aircraft ("Aircraft, Detected", "Tech 2 Unit, Detected", then "Commander,
  Taking Heavy Damage!") killed the commander while it built the Bot Lab; no AA yet, and the commander was the only
  builder (the loss condition). Lesson: AA towers first, the commander beside them. [nb-015 .. nb-017]
- 21:55 UX: the build grid's page 2 opens by a drag on the grid; my drag went a page further than meant and I picked
  the floating twin of the tower I wanted (the same 80/900, a blue water background). The dock never names the picked
  building or the tile under a finger: only its picture and cost say which it is. QOL: the picked building's name on
  the PLACE panel (or a long press on a tile showing its name and role). [nb-016]
- 21:55 UX: the end screen: with the Mission window open (it was my pause) BAR's Awards window lies under it, their
  texts over each other; the dock is gone and the lower half of the screen is empty. [nb-017]

### 2026-11-21, New Beginning (Normal), game 2: the same build

- 22:05 UX: with the scenario paused at its start (the Mission window open), my first tap on the map closed the
  window and unpaused the game; I had meant to pick a spot. On a phone the window is also the pause: a tap meant for
  the map starts the game. [nb2-001]
- 22:06 UX, to check: QUEUE on, a tap on a unit adds it to the selection (BAR's Shift-click) instead of selecting
  it alone; with QUEUE as a sticky Shift for placing, a player who left it on finds a tap on the lab added the lab to
  the constructors. A tap on a unit might ignore QUEUE (QUEUE for orders and placing only).
- 22:07 UX good: a tap on empty ground deselects all (as a mouse's left click), and a double tap on a unit selects
  every unit of its type on screen (BAR's double-click): the 4 Construction Bots in one gesture. [nb2-018]
- 22:08 UX good: the factory's +1/+5/+20/-1/CLEAR/ORDERS panel after a tap on a unit picture; each tap on a
  picture adds one and its count shows on the picture. [nb2-028]
- 22:09 NOTE: the commander has no Move on the dock's first page when the build grid is up (Fight, Patrol, PRESETS,
  Hold pos, Repeat, Low Priority, Wait, Stop, Move: Move is at the foot of the order column, the 9th of 9).
- 22:12 LOST the commander (~5 min in) to enemy Tech 2 aircraft at the northern extractors, outside the three
  Nettles' cover. AUTO RETREAT (on) turned it back too late: aircraft outrun a commander; the retreat cannot save it
  from air. The Bot Lab and its first constructors survive, so the game goes on (the loss needs all builders gone).
- 22:20 QOL: the Pause key (BAR's /pause) works in a scenario, but the touch interface has no pause (above). With it
  the game is played as a turn-based game: pause, orders, a 15-30 s run.
- 22:21 UX: the camera's zoom rail moves by the finger's speed: three slow full-length drags (1.5 s each) zoomed out
  about a fifth; two fast ones (0.25 s) went from close to the whole corner of the map. A slow, careful drag barely
  does anything: a player reads that as "the rail is broken". A floor on the step for a slow drag would help.
  [nb2-031, nb2-032]
- 22:22 UX: the build grid scrolls by rows (a 300 px drag: two rows), not by its pages; finding the Nettle took two
  drags and a look each time, and there is no name on any tile or on the PLACE panel (game 1's note). [nb2-019,
  nb2-020]
- 22:23 UX good: picking a spot turns PLACE bright green (from a dim green): a clear "ready". [nb2-025]
- 22:36 UX: the dock never names a unit or building anywhere (the factory's tiles, the build grid, the PLACE
  panel): the Advanced Bot Lab's 18 pictures could only be told apart by reading BAR's unit files (Archangel, the T2
  AA bot, is a pink-lit picture among them). A long press on a tile shows nothing (tried). QOL: a long press on a tile
  showing its name and one line on its role. [nb2-039]
- 22:45 GAME 2 abandoned: commander gone, the base under ground attack, metal 40. Restarted as game 3 with the
  driver below.

### How the playing changed after game 2 (research report "Touch playtest agent approach")

Kailil, 22:47: "a more effective way ... instead of step by step?", then "a hook into the game's engine ... like the
in-game AI", then "research which path would be best". The report (reports/ in the checkout, not committed) chose:
a dev-only widget on the dev phone exports the game as text twice a second (my units, enemies in sight, resources,
metal spots, the dock's tiles and buttons where they are drawn, screen points for world points) and pauses the game
on events (a loss, an idle builder or factory, an enemy near, the commander hit); a laptop driver turns decisions
into real touches through one virtual touchscreen with a finger's timing and a little noise (toolchain\tmp\play:
dev_playstate.lua, play.py, touchd.py; every touch logged in touchlog.csv). Orders still go only through the app's
touch controls; nothing is given to the engine directly.

### 2026-11-21/22, New Beginning (Normal), game 3: the driver, Nettles first

- 23:05 UX: BAR's lobby over a running game (top bar's Lobby): Start Scenario does nothing, no "leave the running
  game?" prompt; the game had to be stopped from the app's launcher (Stop) and the lobby opened again. [nb3-000]
- 23:09 NOTE (the driver, not the app): injected drags were read as flings of 6000-15000 px/s and paged the build
  grid, and the next tap was swallowed while it settled: Android's `uinput` schedules delays from a time base, so
  after an idle gap a whole gesture arrives at once; fixed with `updateTimeBase` before each gesture (fling 0 since).
  A real finger was never affected; recorded so the next tool does not repeat it.
- 23:10 UX good: the dock leaves out what the scenario forbids (the commander's grid has 25 tiles; Anemone, limited to
  0 here, is not among them). But the grid's rows then differ from BAR's own order, so a tile's place is learned only
  by looking.
- 23:12 UX: a building picked, a one-finger drag on the map moves the building (or draws BAR's line), not the
  camera: to place at a spot off the screen the player must let go (X), pan, and pick again. Same with an order armed
  (Fight, Move): a drag draws the order's formation line. A phone player places across the map all the time; two
  fingers to pan while placing, or the camera knob, would need to be discoverable.
- 23:14 UX: the camera knob (bottom right) and the turn rail take taps meant for the map: four of six converter
  spots tapped there went to the camera and nothing was placed. The knob sits over playable ground at the dock's top
  edge, where buildings near the bottom of the view are placed.
- 23:16 UX: the energy panel (SHARE ENERGY ABOVE / CONVERT ABOVE) opens from a tap on the energy bar; with nothing
  selected that bar lies where QUEUE is when something is selected, so a tap meant for QUEUE opened it. It also
  showed that converters work only above 75 % energy storage: mine stood idle most of the game while building kept
  energy at 60-70 %. A new player will not find that slider. [nb3-023]
- 23:20 UX: Android's Back over the game opens BAR's lobby (Escape), also with units selected: a phone player's
  Back means "cancel" or "deselect"; twice it took me out of the battle (Return to Battle brings it back). [nb3-026]
- 23:27 UX: tapping the middle of a factory selects the unit standing in its yard (a new Archangel), not the
  factory; the back of the building works. [nb3 Archangel]
- 23:28 UX: ALL UNITS selects land units only: the Falcon fighters were not in it (no "aircraft" type picture), so
  fighters could be selected only by a double tap on one on the screen.
- 23:30 UX: FACTORIES selected the Advanced Bot Lab once and the Bot Lab another time, with no hint which one comes
  next or how to reach the others.
- 23:44 UX: a Guard on a constructor made the commander follow it out of the anti-air cover twice (BAR's guard
  follows a moving unit); the dock gives no "assist this building" order apart from Guard and Repair.
- 23:55 UX: the Liche (atomic bomber) has no Move and no Attack among the dock's orders (Fight, Patrol, Hold fire,
  Maneuver, Repeat, Land, Wait, Stop only): a bomber's strike on a map spot (BAR's Attack on the ground) has no button;
  the long press (the default order) only moves it, so a factory out of sight cannot be targeted.
- 23:58 UX: typed chat text sent with Enter right after typing stayed in the box unsent (twice); a second Enter
  seconds later sent it.
- 00:40 UX good: the commander's D-gun mode (the dock turns into MOVE and AIM sticks with FIRE and an X): the aim
  line is drawn on the map from the commander, a drag of the AIM stick set it on two Pyros and FIRE killed both. The
  first try had aimed at my own Aircraft Plant; the line made that visible before firing. [nb3-036]
- 00:00 LOST the first Liche to Vampire fighters over the north edge before it reached the Vehicle Plant. Enemy air
  (Hailstorm bombers, Wasp gunships, Vampires) has picked off 6 extractors, 8 Nettles, 2 advanced and 2 T1
  constructors so far; Nettles do not stop Hailstorms before they drop.
- 01:20 GAME 3 given up at 22:01 (not lost): turtled with 3 Sharpshooters, 2 Fatboys, 4 Welders, 4 Overwatch,
  income +26 metal, 7-8 Vampires over the base killing an Arbalest the moment it was finished and the Advanced Fusion
  site; 4 Liches built, all shot down before a factory came into sight. Restarted as game 4 with the plan in
  toolchain\tmp\play\strategy.md (economy on converters and fusions inside flak, no expansions, a Sharpshooter army
  along the west and north edges).
### 2026-11-22, New Beginning (Normal), games 4 and 5

- 03:00 GAME 4 (the plan in strategy.md): Advanced Bot Lab at 3:02, three fusions by 12:50, the Advanced Fusion at
  21:07, +120 metal at best; Hailstorm bomber waves (2-4 every ~2 minutes from ~4:00) took 48 converters, a fusion, two
  Advanced Fusion sites and 5 Archangels at once; a Fatboy push at 26:22 was bombed to pieces on the west edge.
  Given up at 31:48. GAME 5 (air first): a single Pyro walked through the base at 9:49 and destroyed the Bot Lab and
  the Advanced Bot Lab; given up at 10:20.
- 03:10 UX good: "tap then drag selects" (the launcher's own hint) draws a box that takes units, not buildings: the
  only way that reliably selected constructors standing between converters and turrets; a double tap on one of them
  selected the turret or the converters beside it three times out of four.
- 03:12 UX: LOCAL UNITS and ALL UNITS take combat units only (no constructors, no aircraft), with no hint of that;
  a player looking for "my builders" has the idle-builder icons on the bottom row or a box.
- 03:15 UX good: a long press on an enemy unit gives the attack order (the commander killed the Pyro that way at
  once), and with QUEUE on a long press on the ground queues a move: the bomber route of game 3 was laid that way.
- 03:20 UX: the dock's order buttons are drawn for the selection a moment after it changes; a tap in that moment
  lands on the previous selection's button (twice the factory's +1 panel took a tap meant for an order).

### 2026-11-22, New Beginning (Beginner), game 6: the same build with +50 % resources

- 03:05 Game 6 on Beginner (the scenario's lowest difficulty: +50 % resources for the player, the same AI and
  defences; whether a Beginner win counts is Kailil's call, not decided here) to find out whether the build can win
  at all. Best economy of the night: +60 metal at 6:44, three fusions and the Advanced Aircraft Plant by 9:52, the
  Advanced Fusion by ~17:00 (+6,900 energy), metal full from then on.
- 03:50 The push (12 Fatboys, 6 Archangels, 2 Crossbows on 7 queued Fight waypoints, west edge then north edge) was
  met by 8 Wasp gunships near the north-west lake and lost every Fatboy within two minutes; Pyros, a Goliath and
  Hailstorms kept killing the fusions and the Aircraft Plant at home. Stopped at 19:58.
- 03:50 UX: the D-gun's AIM stick turns the aim line by an amount that does not follow the stick's direction while
  the game is paused (three drags: 65 deg, -12 deg, then no change); unpaused in game 3 it aimed well.
- 03:55 UX: the lobby's Difficulty list (scenario page) ignores a quick tap on an entry (80 ms) and takes a held
  one (200 ms); the scenario list's drag keeps its fling, so the same drag stops at a different scenario each time
  (three wrong scenarios opened tonight).
- 03:55 SUMMARY of New Beginning: 6 games, no win. The build that worked best (Nettles at once, Bot Lab inside them,
  Advanced Bot Lab ~3:00, fusions and converters, Advanced Fusion) survives but does not outgrow BARb's steady raids
  (Hailstorm waves every ~2 minutes from ~4:00 on the economy, Wasps on anything that leaves the base, Pyro/Reaper/
  Goliath/Banisher raids); no Liche reached a factory (7 built), no ground army got past the north-west lake. The
  touch controls held up for all of it; the slow part is the agent's own reaction loop, which a human does not have.

### 2026-11-22, skirmish 1v1 against BARb Easy, game 1: Avalanche 3.4, Armada, dev phone upright

- 03:56 Start: Armada vs BARb (profile Easy, the lobby's Simple Skirmish), map 4096 x 4096, our start (508, 369)
  in the north-west, theirs presumably mirrored in the south-east. Commander: extractors, winds (wind 3-19 here,
  often 15+), a Bot Lab; the lab 3 constructors, Maces and Rocketeers.
- From ~5:00 on, Grunts (BARb's fast infantry bot, 5 to 18 at a time) raided from the south (800, 1216), the north
  edge (1250, 200), the east (2560, 1350) and later the west edge; every extractor outside the base was lost at least
  once (1632,704 twice, 2112,1232 twice, 3104,208, 1024,720, 800,240). Most of our income came from 3-5 extractors;
  BARb held the middle (extractors, solars, a Sentry-class tower at 2336,2016) by ~9:00.
- game 10:30: a 13-Mace push toward the south-east lost 8 Maces to Grunts in 15 seconds near (2650, 2950): plasma is the
  wrong answer to fast swarms. Switched the lab to Centurions ("Anti-Swarm Bot"), which held the base well after.
- game 13:00-16:00: BARb's Graverobbers raised our dead Maces, Rocketeers and a constructor: its army had our own units in
  it. Up to 40 radar contacts by 15:00.
- game 19:20: Area Reclaim on the fight's wrecks gave +52 metal a second for a while (income otherwise +12): the best
  metal of the game, and wrecks reclaimed are wrecks BARb cannot raise.
- game 20:40: one Aggravator in the base killed one energy converter and the explosions took all nine (they stood side by
  side): converters need gaps.
- game 21:50, 05:25: last throw: 24 units toward the south-east met BARb's commander beside a heavy laser tower at (2900, 2800);
  an Attack order on the commander lost the army (auto retreat had already sent the hurt ones home one by one).
  Game given up at 22:15: 1 extractor, +5 metal.
- What to change (game 2): 3-4 constructors before any army, every extractor in our quarter at once with a Sentry each,
  Centurions from the first army unit, the army kept home as a mobile defence between the three ways in, converters
  apart, reclaim after every fight, and no attack until the army clearly outnumbers what BARb shows.

UX, bugs and QOL from this game:
- game 6:55, UX: a Sentry placed alone gets its ring of 8 Dragon's Teeth (bardroid_walls.lua) by default: 64 metal on top
  of the Sentry's 85, in the first minutes, unasked; the WALLS switch is only on the place panel while a Sentry is
  picked, and nothing says what the walls cost. QOL: show the cost on the switch ("WALLS +64"), or start it off.
- game 7:03, UX: with the commander selected, picking the Metal Extractor queues the free spots in its weapon range at once
  (bardroid_automex.lua, by design) and puts the extractor away, so a tap meant for a farther spot lands nowhere: the
  player has to pick it again. A spot already covered by an extractor standing off its middle is not free for BAR's
  snap: an extractor tapped there is put on the nearest really free spot (600 elmos away, twice); the ghost shows it,
  so it is visible before PLACE, but easy to miss.
- game 13:21, UX: Guard on a factory: a tap on the factory's middle hits the unit being built in its yard, so the commander
  guarded a half-built Centurion (and would have followed it out); the factory's back edge takes it.
- game 19:06, UX: the D-Gun button opens the D-gun mode (MOVE and AIM sticks, FIRE) instead of arming a target tap as every
  other order does; there is no quick "D-gun that unit" by a tap or a long press.
- game 19:20, UX good: an area order works by arming it (Reclaim) and dragging out from the middle: BAR's circle. With
  QUEUE on the order stays armed after the drag (Shift held), so the next map tap gives another one; QUEUE off ends it.
- game 13:40, UX good: the factory panel's +1 / +5 / +20 / -1 / CLEAR act on the unit last tapped; INSERT (top left) puts
  the next ones at the queue's front: two constructors went first that way.
- game 21:20, UX: AUTO RETREAT (on) sends hurt units home one at a time during an attack: the push thinned on the way and
  the units walking home alone were picked off. QOL idea: during a Fight order the hurt fall back to the group, not home.
- game 22:00, UX: a tap on a constructor next to a new Sentry or wind selected the building (three times); "tap then
  drag" boxes and the dock's COMMANDER button were the reliable ways.

### 2026-11-22, skirmish 1v1 against BARb Easy, game 2: WON at 12:14 (Avalanche 3.4, Armada; BARb played Armada)

- 05:30 The plan from game 1: Bot Lab first (the pre-game queue), the commander's three extractors and winds, the lab
  4 constructors and Centurions on repeat with a Fight rally in the middle (1250, 900); constructors to every
  extractor in our quarter with a Sentry each (walls off); converters 110 elmos apart; a Construction Turret on the
  lab; solars and energy storage when the wind fell to 4 (Centurions cost 3,100 energy each).
- game 5:01: 8 extractors (game 1: 3-5 at that time), +16 metal; 9 extractors by 7:00. BARb's Pawns and Maces still
  took outlying extractors, solars and two constructors one at a time, but the army lost nothing to them: 17
  Centurions and 6 Rocketeers by 11:16, the commander on Patrol through the base against raiders.
- game 11:16 the push (Fight 2700,2700, then 3150,3150): at 12:14 BARb's commander died near (3150, 3150) and its
  death explosion took 10 Centurions in the same second; the game ended ("Kill all enemy Commanders"), BARb's AI was
  removed and the engine went back to the lobby 12 seconds later. First win against the AI by touch.

UX, bugs and QOL from game 2:
- 05:27 UX bug: before the start the dock has no QUEUE, and BAR's pre-game queue is replaced by every placement made
  without Shift: one building can be queued before the start, not a build order (the commander's first minute is
  queued only after it starts). QOL: QUEUE (or "add to queue" as the default) on the pre-game dock.
- 05:27 UX: before the start, a map tap with no building picked moves the start position: after a placement let go of
  the extractor, the next spot's tap moved the commander's start onto that metal spot.
- 06:00 UX good: the factory's ORDERS page has Repeat and the factory's own Fight/Move: Repeat On plus a Fight point
  in the middle kept the lab busy and sent every Centurion to the front with no further touch.
- 06:14 The game's end goes back to the lobby by itself 12 seconds later (BAR's autoquit). Checked in game 3: the
  screen shows "Victory!", BAR's Awards over the map and the app's own "Leaving the game in 4 s, tap the screen to
  stay longer" in the chat lines: clear enough, though 12 seconds is short for a phone put down after the last fight.

### 2026-11-22, skirmish 1v1 against BARb Medium, game 3: WON at 12:25 (Avalanche 3.4, Armada vs Armada)

- 06:40 The same plan as game 2, with the lab's constructors taken off its repeat once four were out (the factory's
  CLEAR on the constructor), a second Bot Lab at 7:38 when metal banked, Beamers at the outposts.
- BARb Medium raided with Flashes (fast tanks) from 2:41 on: one Flash alone took the east extractor, a Sentry, two
  constructors (one by one, the north-east one twice) and a dozen wind turbines over the game; Centurions never caught
  it. 8 extractors held, +21-25 metal from 7:00.
- game 10:46 the push: 21 Centurions and 6 Rocketeers by Fight orders to (2700, 2700), (2900, 2900), then BARb's
  Vehicle Plant at (3104, 3248); BARb's commander died at 12:25 (the push lost 6 Centurions to its death explosion).
  The dev widget's GameOver said "won".
- game 12:25 UX good: the end screen: "Victory!", the Awards (Show Graphs, Leave) and the tap-to-stay line.
- UX: the factory's Repeat repeats the whole queue, constructors included: four constructors queued first come back
  every cycle unless taken off (tap the constructor, CLEAR). QOL idea: Repeat only for combat units, or a mark per
  entry.

### 2026-11-22, skirmish 1v1 against BARb Hard, game 4: given up at 7:37 (Avalanche 3.4, Armada vs Cortex)

- 07:05 The game-3 build lost from the first minute: a Grunt in the base at 1:46, Thugs and Aggravators from 5:00 on,
  from the east, south and north at once. The lab's Centurions (3,100 energy, 270 metal each) and the constructors'
  extractors drew on the same +6 metal and energy +30-90, so neither got anywhere: at 4:40 two extractors and two
  Centurions. Clearing the lab's queue let the constructors build, but every extractor past the core (1632,704 three
  times, 1024,720, 416,2160) and five Sentries fell to groups of 3-4 raiders; two constructors died. 7:37: three
  extractors, two Centurions. Stopped to try a map with defensible ramps.
- Lessons for Hard: energy first (the commander's first queue: winds before far extractors; solars cost no energy
  and fixed the stall), no army until 4-5 extractors stand, Sentries in pairs or a Beamer, and everything compact
  around the commander until a Centurion group exists.
- 07:20 UX: INSERT on a builder (its top-left switch) did not put a placed building at the queue's front (twice: the
  solars and a Construction Turret went to the end or nowhere); on a factory it works.
- 07:25 UX: a Move given to the commander drops its build queue (as a mouse's click does in BAR); on a phone, where
  QUEUE is a separate switch, it is easy to wipe a long queue by pulling the commander out of danger.

### 2026-11-22, skirmish 1v1 against BARb Hard, game 5: Ravaged Remake v1.2, given up at 17:28

- 07:45 Ravaged Remake (5120 x 5120; our start the south-west plateau, four extractors in the start box, the map's
  edge behind it): 9 extractors at 4:44 and 10 at 5:48, a second Bot Lab at 7:08, 18 Centurions at 11:04. BARb Hard
  (Armada) raided from 2:44 on with Rovers, then packs of 5, 7, 10 and 11 Flashes, then Stumpies with Janus rocket
  tanks and Shellshocker artillery: every outpost fell (north, south-east, east line), Sentries and Beamers alone
  did not stop a pack, and BARb built its own extractors on our north spots.
- game 14:16 the push (24 Centurions, three Fight points to the north-east) stalled in the middle while Flashes and
  Janus went through the base: the second Bot Lab fell and the commander dropped to 13 % before it got away and two
  constructors repaired it. The army came home; 17:28: two extractors, +10 metal. Given up.
- Next: walls on (Dragon's Teeth slow raiders), turrets in groups, the army on a Patrol loop that answers raids by
  itself (the agent's own reaction is the slow part against BARb Hard), the T2 lab earlier.
- game 14:50 UX bug: in the dock's D-gun mode a drag of the AIM stick did not turn the aim line, paused or for the 2
  seconds the game ran, and FIRE then shot along the old line (south, at nothing) while ten Flashes stood east of the
  commander. The D-gun was wasted. (In New Beginning game 3 a drag aimed well with the game running.) To check: does
  the aim move only while the stick is held, at a fixed speed? A quick drag-and-release then does almost nothing.
- game 14:59 UX: the commander at 23 % still had an order from me (Fight) and AUTO RETREAT did not take it out: the
  player's own order wins. QOL idea: a hurt commander's retreat over the player's Fight, or a warning.
- 07:50 UX (lobby): the quick Skirmish's four map tiles changed places between two visits (Avalanche top left, then
  bottom left); a player who picks by place gets the wrong map.

### 2026-11-22, skirmish 1v1 against BARb Hard, game 6: Ravaged Remake, given up at 12:26

- 08:40 The base plateau's ways out found by the engine's path finder (a dev-widget probe): north-east by
  (1300, 3950) and east along the map's south edge by (1600, 4280). An Overwatch and Sentries at each, the army on a
  Patrol loop over both and the east line: the base held (no raid reached the labs this time), 10 extractors at
  10:05, an Advanced Bot Lab started at 10:05. But BARb Hard had fortified the north spots (Overwatch, Beamer,
  Sentry, three construction vehicles) before we got there, its Janus/Stumpy groups and Rovers kept taking
  outposts and constructors, and the Advanced Bot Lab sat at 33 % at 12:26 with metal at 0. Given up.
- game 7:02 UX bug: BAR's build menu arms a building's sea twin while the pointer last stood over water (Solar ->
  Tidal Generator, Energy Converter -> Naval Energy Converter, Bot Lab -> Shipyard, Sentry -> Harpoon), and the dock
  keeps showing the land picture and name, so the player picks "Bot Lab" and gets a Shipyard ghost. On a phone the
  pointer stays where the last tap was (here the void at the map's edge). The tap on a land spot swaps it back and
  the land building is queued, so it places right; the ghost before that tap is the wrong one. QOL: the dock's tile
  should follow BAR's swap (show the twin), or the app should move the pointer onto the map when a tile is tapped.
- game 0:13 UX: QUEUE turned off by something other than the player (here the dev tools' LuaUI reload) makes the next
  placement replace the commander's whole queue; QUEUE's state is easy to miss on the dock.

### 2026-11-22, skirmish 1v1 against BARb Hard, game 7: stopped at 4:33

- 09:45 game 0:06 UX: the D-gun mode's AIM stick turns the shot at about 30 degrees a second while it is held and
  the game runs (a 1.5 s hold to the right turned it 45 degrees; paused it does not turn at all): it is a rate, not
  a direction, so a quick flick does nothing and aiming at a raider beside the commander takes seconds. QOL: aim
  where the stick points (an absolute direction), or a tap on the map as the D-gun's target (BAR's own way).
- By 4:33 a single Cortex scout car had killed a base extractor, a Sentry and the north constructor: the same early
  bleed as games 4-6. Stopped; the Hard win needs more than this driver's reaction loop gives (below).

### 2026-11-22, skirmish 1v1 against BARb Hard, game 8 (Ravaged Remake), stopped at 21:57

- 10:05 Kailil asked for play, logging and fixing to run side by side: a second session ("playtest-fixes") fixes the
  findings while this one plays; the dev phone is shared through its lock, screen at minimum brightness again.
- The driver got standing rules (toolchain\tmp\play\autopilot.py, all by the same touches): an idle or new
  constructor claims the nearest free metal spot with a Sentry, else builds energy; the commander rebuilds the base's
  extractors, then energy or a second Bot Lab; an idle factory goes back to Centurions on Repeat with a Patrol rally
  between the base's two ways out; under two constructors a lab puts two at its queue's front (INSERT); the army
  pushes at 22. It held 11 extractors at 9:23 (the best yet against Hard) and two labs by 12:56.
- game 12:56 the game saved by the top bar's Save ("Game saved: the lobby's Load Game opens it"), the phone handed to
  the fixer session, then loaded from Load Game on its new build at 12:58: save and load work by touch.
- Checked in play on the fixer's build (uncommitted, 10:52): FIXED: the sea twins (Solar and Converter picked with the
  camera over the map's edge armed armsolar/armmakr, the right tile lit); the D-gun mode's map tap aims the shot
  (paused too); "+ QUEUE" on PLACE; "WALLS +64" (small type). NOT YET: the AIM stick paused (a quick flick moved
  nothing) and with a turned camera (a flick right aimed screen down-right: world axes, not the view's); sent back.
- game 17:17 the army would not leave: solars, winds and converters the rules had put "by the base" walled in both
  Bot Labs' exits; the engine's path finder found no way out from where the Centurions stood. Reclaiming four
  converters and a Sentry opened it. Energy now goes to a field behind the base, away from the factories.
- game 21:34 a Cortex assault (Thugs, a Can, Morty artillery, Graverobbers) took the second Bot Lab; the army held
  the base but the push never went out: a Fight order to the far side of the map needs its point on the screen, and
  the camera pan could not bring it there ("cannot bring 4152,816 onto the screen"). Stopped at 21:57 (4
  extractors, 17 Centurions).
- UX: an order's target point far off the screen cannot be given by touch without first panning there; the
  minimap (top left) is too small to tap a far point on the upright layout. QOL: a larger minimap to tap, or the
  dock's PING/LAST PINGS places as order targets.

### 2026-11-22, skirmish 1v1 against BARb Hard, game 9 (Ravaged Remake, BARb Armada): lost at 6:02

- 12:00 On the fixer's build e952aae4: the quick Skirmish's maps now stand in name order (Avalanche, Onyx Cauldron,
  Ravaged Remake, Shallow Straits) at every visit: FIXED. The pre-game dock has a QUEUE row ("START SPOT: tap the map
  for yours" ... QUEUE): with it on, the Bot Lab and an extractor stayed queued before the start: FIXED.
- 12:02 UX: in the pre-game dock PLACE stands where ARMADA / CORTEX stand once the place panel closes; a tap meant
  for PLACE a moment late switched the faction to Cortex (the queue's buildings became Cortex's). QOL: keep the
  faction buttons away from PLACE's place, or ask before switching with a queue. Also the wind/tide box lies over the
  QUEUE row's hint text ("START SPOT: tap the map...").
- BARb Hard (Armada) sent Ticks at 2:56: three extractors and a Sentry lost before the first Centurions, again.
- 12:20 A commander raid instead (the D-gun map tap now aims): the commander walked the path finder's way in Move
  hops and reached BARb's base at 5:43 (99 %), met its commander "Arquebus (AI)" at 5:48 ~360 elmos off, and fired
  two D-guns, each aimed by a tap on it in the dock's D-gun mode: the aim line went onto it, FIRE fired ("D-GUN FIRED",
  500 energy each); it lived on, and ours died at 6:01 to Pawns, a Sentry and its laser (100 % -> 0 in ~20 s).
  Kailil, afterwards: "You cannot dgun another commander. Commanders are immune." The raid was a dead end by design;
  the map tap's aiming itself worked.
- UX: in the D-gun mode the camera follows the commander, so a unit tapped a moment before has moved on the screen;
  a moving raider is easy to miss. QOL idea: a tap on an enemy unit (not the ground) aims at the unit and leads it.
- Driver: with QUEUE on and an order armed, a drag on the map draws the order's line instead of panning; the driver
  now lets go (QUEUE off) before a pan and puts QUEUE back after.

### 2026-11-22, skirmish 1v1 against BARb Hard, games 10 and 11 (Ravaged Remake): stopped at 10:51 and 10:14

- Game 10: the driver built each outpost's Sentry before its extractor and sent the labs' Patrol rallies out over the
  outposts (Centurions east, a Pawn squad north): Ticks and Pawns still took every outpost; 2 extractors at 10:51.
- Game 11, a "fortress" (no outposts; the four extractors inside the plateau; Overwatch, Sentry and Beamer at each
  way in; the Advanced Bot Lab next): the first Pawn raid (7) came in at 5:31 before any defence stood, a dozen more
  at 10:12; the constructors' Overwatch at the north-east way in failed to place several times in a row; 1 extractor
  at 10:14.
- Where this leaves Hard: BARb Hard's cheap fast raiders arrive from 2-3 minutes on and keep coming in packs of 5-12;
  every agent-driven defence so far came a step late. The touch controls did each thing asked; the gap is the
  agent's own macro. The playtest goes on with Medium games (late game, T2, big armies: controls not yet exercised)
  between new attempts at Hard.

### Skirmish summary (2026-11-22)

- BARb Easy: game 1 lost, game 2 WON at 12:14. BARb Medium: game 3 WON at 12:25 (first try with the game-2 build).
  BARb Hard: games 4-7 not won (given up at 7:37, 17:28, 12:26, 4:33).
- What beat Easy and Medium: the Bot Lab first, four constructors claiming every extractor in our quarter with a
  Sentry each, Centurions on factory Repeat with a Fight rally, converters apart, solars when the wind fell, the
  commander at home (Patrol), one push of ~20 Centurions at 11-12 minutes along Fight points to BARb's base.
- Why Hard was not beaten: BARb Hard raids from the second minute with fast single units and packs (scouts,
  Flashes, Rovers, then Stumpy/Janus/artillery groups) at every outpost and constructor at once; the driver reacts
  at the speed of a person reading the state and deciding each move (the game paused meanwhile, but every reaction
  is one place at a time), so outposts and constructors fell one by one and BARb out-expanded us every game.
  The touch controls themselves did everything asked of them; the gap is the agent's macro and reaction.
- To try next for Hard: the driver's own standing rules (constructors escorted by the first Centurions, lost
  extractors rebuilt by whichever constructor is nearest, new units joining a Patrol loop by themselves), Overwatch
  pairs at the base's ways out from the first minutes, and the Advanced Bot Lab earlier.


