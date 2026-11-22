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
- 01:20 GAME 3 given up at 22:01 (not lost): turtled with 3 Sharpshooters, 2 Fatboys, 4 Welders, 4 Overwatch,
  income +26 metal, 7-8 Vampires over the base killing an Arbalest the moment it was finished and the Advanced Fusion
  site; 4 Liches built, all shot down before a factory came into sight. Restarted as game 4 with the plan in
  toolchain\tmp\play\strategy.md (economy on converters and fusions inside flak, no expansions, a Sharpshooter army
  along the west and north edges).
- 00:00 LOST the first Liche to Vampire fighters over the north edge before it reached the Vehicle Plant. Enemy air
  (Hailstorm bombers, Wasp gunships, Vampires) has picked off 6 extractors, 8 Nettles, 2 advanced and 2 T1
  constructors so far; Nettles do not stop Hailstorms before they drop.

