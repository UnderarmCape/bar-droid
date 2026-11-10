# Help wanted: taking BAR Droid on

BAR Droid shows that Beyond All Reason plays fully on an Android phone: BAR's lobby, online games, skirmish against
the AI and spectating, on BAR's official, unmodified engine. It is complete as it is: full games from the lobby to
the end, late games chug but run well and stay caught up, and with a mouse and keyboard it plays like BAR on a PC.
What follows is about making it better and official, not about making it work. Its author does not plan to keep
developing it. The hope
is that BAR's developers and community take it as a stepping stone to an official BAR for Android: fork it, take it
over, or take what is useful into BAR's own work. Two areas need people who know them best: **engine-side
performance** and **touch controls** (the gamepad's state is below too). Everything below was measured on one phone, a Galaxy Z Fold7 (Snapdragon 8
Elite, Adreno 830, Android 17); [HISTORY.md](HISTORY.md) has the runs behind each number.

## How it runs (and what that costs)

The official Linux arm64 Recoil build runs inside a Debian container (proot), draws desktop OpenGL through Mesa
(Freedreno on KGSL) onto an X server built into the app (Termux:X11's `lorie`), which Android shows
([ARCHITECTURE.md](ARCHITECTURE.md)). That stack exists so the engine and the game stay exactly BAR's and online play
works: this app changes only client-side settings and its own LuaUI widgets ([CONTRIBUTING.md](../CONTRIBUTING.md)).
Known costs of the stack: proot stops the engine at every trapped system call (narrowing its seccomp filter to the
calls proot acts on took the phone from 14 to 30 fps), and the frame goes engine → Mesa → X server → Android. An
official port is free to do what this app could not: build Recoil for Android itself, change the engine, change the
game.

## Engine-side performance

- **Late games are CPU-bound on the engine's main thread.** BAR's "Benchmark BAR" scenario (~1,300 units fighting), on
  a phone hot from play: Sim 21-31 ms per frame, the game at x0.70-0.95 of real time, the main thread 88-94% of a core,
  its three workers ~60% of a core together (`WorkerThreadCount` 2 was ~5% slower than 4; 7 no better).
- **Where the main thread goes** (the same scenario profiled on a laptop, `tools/profile-benchmark.ps1`): the
  simulation ~51%, of which synced Lua callins ~10% (the rest the engine's C++); unsynced Lua ~21%; drawing ~13%.
  Costliest Lua: unsynced gadgets Fire GL4, Fire & Smoke GL4, CUS GL4, Beam Laser GL4, Widget Events; widgets Reclaim
  Field Highlight (half of all Lua garbage; the app turns it off), API Unit Tracker, Health Bars.
- **Heat sets the clocks.** Within ~20 s of a battle Samsung caps the CPUs at ~2.0 GHz (of 3.5/4.5); after an hour of
  play 1.4-1.7 GHz, and the GPU 160-1050 MHz of 1200 depending on the load history. Measure hot, back to back
  (`tools/phone-bench.ps1` warms the phone up first).
- **Spectating a real 8v8** (30 fps cap): ~30 fps to ~2,000 units, game speed x0.97-1.02 at ~3,600 units, the GPU 67-73%
  busy at 342-443 MHz. Uncapped the GPU is 93-99% busy at its thermal cap: 88 fps at 178 units, 26 at 1,400.
- **What did not help:** BAR's graphics presets (the app already turns off most of what they turn off), 70% render
  resolution, Android Game Mode. 900p against 720p costs nothing measurable.
- **What would**, out of this app's reach: a cheaper simulation main thread (or more of it on the workers), an
  Android-native engine build (no proot, no X server), GL ES or Vulkan rendering instead of desktop GL through Mesa,
  cheaper versions of the GL4 effect gadgets, and GPU timer queries in Recoil (`gl.QueryCounter`/`GetQueryDelta`,
  which BAR's GPU Profiler widget expects) to see where the GPU's time goes.
- Measure: `tools/phone-bench.ps1` (the benchmark or a replay on the phone, clocks and busiest threads into a CSV),
  `tools/profile-benchmark.ps1` (the same scenario on a laptop, every widget, gadget and engine timer).

## Touch controls

What works ([README.md](../README.md) "Touch controls"): taps, box select, long press for orders, two-finger camera
(pan, pinch, twist, tilt), gesture shortcuts, finger scrolling in the lobby, and spectating by touch (follow a unit,
camera presets, 1st person). Code: `RtsTouch.java` (Android gestures to X mouse events) and the LuaUI widgets in
`app/src/main/assets/bardroid/` (`bardroid_touch.lua` the camera and interface answers, `bardroid_spectate.lua`,
`bardroid_info.lua`, `bardroid_players.lua`, `bardroid_minimap.lua`, `bardroid_lobby_touch.lua`).

Not solved:
- **Playing (not spectating) by touch is basic.** BAR's build and order menus have no "is the pointer over me"
  answer, so the app runs its own copies of both (`bardroid_buildmenu.lua`, `bardroid_ordermenu.lua`, patched copies
  remade on the phone after BAR updates), which answer it: a drag there no longer pans the map. In the controller
  game the menus are v0.8.5's own. Placing buildings by finger works through the build menu copy: while a building is
  picked its page strip offers ONE, LINE, GRID and BORDER and a PLACE button (rotate, cancel) covers the order menu;
  a tap picks the spot, a drag moves it, PLACE confirms it, and `RtsTouch` holds Shift (and Alt, Ctrl) for the click
  or drag so BAR's own building does the rest. What is still missing is a touch design for the rest of play: picking
  targets, unit groups, a selection without a box drag.
- **BAR's interface on a near-square screen** (a foldable unfolded): the player list covers the order menu's last
  column; the minimap is shrunk until tapped.
- **BAR's windows on a phone held upright.** BAR's Settings (`gui_options.lua`) sizes itself by the screen's height
  alone (`widgetScale = vsy / 1080`, its 950 x 610 at 1080p): on a 936 x 2013 screen it is ~1770 pixels wide, its
  values column off the right edge. The fix belongs in BAR's file: `widgetScale = math.min(vsy / 1080, vsx / 1000)`
  in its `ViewResize` (or the same for every window of that kind). The app cannot do it for Settings: a copy, as it
  runs for TeamStats (`tools/make-teamstats.py`, which patches the same line), would lose Settings' widget toggles to
  the user widgets' sandbox.
- **The map's edge:** solved for the app's touch camera (2026-11-03: a drag past the edge holds the point under the
  finger on the level plane, across the edge too, a pinch there zooms about it, a drag over the sky moves the map;
  `tools/touch-phone-test.ps1`). The engine still keeps the camera's target on the map, so a drag outward stops
  where BAR's mouse camera stops too.
- **A movable HUD.** The app's layout editor (`bardroid_layout.lua`) moves and sizes the app's own panels, but BAR's
  only as far as BAR's widgets allow another widget: the minimap's and player list's size. For the build menu the app
  runs a copy of BAR's Build menu with a size and place hook (`bardroid_buildmenu.lua`, made by
  `tools/make-buildmenu.py`, used only while BAR's file is the one it was copied from): the kind of hook BAR's own
  panels could take. BAR's top bar (metal, energy, wind), its order menu (its size follows the interface scale), its
  start countdown and the positions of the minimap and player list are fixed in BAR's code. (The menus' own bottom/left setting,
  `setBottomPosition`, made BAR's older build menu fail drawing when switched while shown: `gui_buildmenu.lua`, a cell
  drawn without its command.) Position (and size) settings for those panels in BAR, or `WG` setters
  like the ones the build menu has, would let a phone layout be made to fit each screen.
- The widgets' limits come from BAR's sandbox for user widgets (no `/option`, no widget toggles, no engine restarts,
  no access to other widgets): touch support inside BAR's own widgets would remove most of the workarounds.

## Gamepad

What works ([README.md](../README.md) "Gamepad, mouse and keyboard"): skirmish runs the author's BAR Controller
Support v0.8.5 (radials, a reticle, its own build and order menus) as BAR's developer game, the pad's state sent to it
by the app (`ControllerBridge`, BARCTRL1 over UDP). Online that game cannot run (BAR's sandbox removes `socket`, BAR's
own widgets lack its hooks, `GiveOrder` needs `allowunitcontrolwidgets`), so in BAR's own game `PadGame.java` rebuilds
v0.8.5's controls from X mouse and key events, which no lobby setting or widget rule can see or block: the pointer
held in the middle, the left stick panning the map under it, A a click, X BAR's right click, RT Shift, RB and
Back + RB putting the build and order menus on the pad (`bardroid_pad.lua`, the build menu copy), groups, idle units,
area select. In the controller game a triple tap switches between the two to compare them. `tools/padgame-test.ps1`
runs `PadGame` against a made-up pointer (laptop and CI).

Not solved:
- Without unit-control widgets allowed in a lobby, the LB shortcuts fall back to picking the order (A gives it) and
  the queue removal (L3/R3) does nothing; v0.8.5's Smart-X decisions are BAR's default order instead.
- The order menu's grid is worked out by copying BAR's layout code (`gui_ordermenu.lua` setupCellGrid): it breaks
  when BAR changes that code. A `WG.ordermenu` call returning the cells (or a focus API, as v0.8.5's edits add) would
  remove the copy.
- An engine gamepad API (Recoil PRs #2985, #3365) would not help on Android: SDL inside the container cannot see the
  phone's input devices, so the pad always comes through the app. A BAR widget reading the app's packets, accepted by
  BAR's developers, plus small `WG` hooks in the build and order menus, would let v0.8.5's full interface play online.

## Also open

- Two phones have run it. The Galaxy Z Fold7 (12 GB) plays. A Galaxy S23 Ultra (Snapdragon 8 Gen 2, Adreno 740,
  8 GB, Android 17) takes the same path (Mesa's Freedreno, OpenGL 4.3, the GL check passes) but is short of memory:
  with ~3.4 GB available at rest (Samsung's and Google's apps hold ~3 GB; 4.1 GB after `am kill-all`), the engine
  reaches ~2.7 GB resident 30 s into loading a skirmish, the rest is pushed into compressed swap (1-3 fps), and
  without the low-memory mode (below) Android's low-memory killer ended it (exit 137), or the whole app, within 1-2
  minutes every time; BAR's benchmark scenario the same, 2 of 2. The app and engine run at oom_score_adj 0 (the top
  activity): nothing to raise. Mali, Xclipse and Tensor GPUs have no driver path in this stack.
- A match uses 5-6 GB of RAM; Android's low-memory killer has taken the game, and an 8 GB phone plays only in the
  low-memory mode, with little to spare.
  On the S23 Ultra the engine's GPU memory (Android's `GL mtrack`, ordinary RAM on a phone) reached 2.8 GB within
  90 s of loading a 1v1 skirmish, its CPU side ~3.2 GB resident plus ~4.2 GB swapped; BAR on Windows in the same kind
  of skirmish uses ~2.5 GB of GPU memory too (the laptop's per-process GPU counters), so the footprint is BAR's own,
  not the stack's. By loading phase (`GL mtrack` against the engine's load messages): the map ~500 MB, models,
  square and projectile textures and water ~1 GB, LuaRules (BAR's gadgets) ~620 MB, LuaUI ~110 MB, the game's start
  ~270 MB. GPU memory cannot be swapped, and an 8 GB phone has ~4 GB at best. One engine setting closes the gap:
  `CompressTextures = 1` (GPU ~2.75 → ~2.45 GB) let a 1v1 skirmish load and play in all 5 tries (3 to 10 minutes,
  the phone's free memory steady at ~600 MB), where every one of 9 tries without it was ended while loading
  (`tools/phone-memory.ps1`, build\phone-memory.csv). But it breaks two textures the engine draws into: the unit
  icon atlas (icons draw as black squares) and the projectile perlin texture, on Windows too: an engine bug, report
  drafted in [upstream/](upstream/recoil-compresstextures-fbo.md); the app works around it (the pace library stores
  such a texture uncompressed when it is attached to a framebuffer). Phones under 9.5 GB now get a low-memory mode
  (docs/HISTORY.md "Fitting BAR into an 8 GB phone"): the engine's Lua memory pools off (nine pools of 128 MB, every
  page written at the start, ~1.1 GB), compression, BAR's GL4 unit shaders (which BAR's Options switch back on in a
  developer game), shore waves and ground decals off. On the S23 Ultra 4 of 6 five-minute skirmishes ran through, the
  phone's free memory always at 550-650 MB. What is left is BAR's or the engine's: two projectile texture atlases of
  8176x6056 and 6616x6152 that `MaxTextureAtlasSize*` does not limit, the map's textures, the pathfinder (379 MB),
  ~2.35 GB of live engine data in mimalloc, mostly swapped out. Smaller atlases, lower texture detail for low-memory
  devices and Lua pools that are not written in full up front would each help.
- The app's touch camera, panels and touch building are LuaUI user widgets: a lobby that turns custom widgets off
  loads none of them (the pad's mouse and keys still work; touch is then mouse clicks only). BAR's Code of Conduct
  asks for custom widgets used on public servers to be posted publicly (#widgets): they are all in
  `app/src/main/assets/bardroid/`. Shipping them with BAR (or touch support in BAR's own widgets) would settle both.
- Reports drafted for upstream, not filed ([upstream/](upstream/)): BAR's saved games crash the engine on load
  (Windows too), Mesa's KGSL present-fence path, an arm64 AI bug in CircuitAI.
- It is 100% vibe coded: an AI assistant (Claude Code) wrote all of the project's own code at the author's
  direction, so it wants review by people who know the engine and BAR; [WORKLOG.md](WORKLOG.md) records every
  request and the time spent.
