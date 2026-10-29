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
  answer, so a drag that starts on them pans the map, and they cannot be hidden from a user widget; they need touch
  versions (as the info panel got). Placing buildings by finger works through the app's build menu copy: while a
  building is picked its page strip offers ONE, LINE, GRID and BORDER and a PLACE button (rotate, cancel) covers the
  order menu; a tap picks the spot, PLACE confirms it, and `RtsTouch` holds Shift (and Alt, Ctrl) for the click or
  drag so BAR's own building does the rest. Nudging a picked spot, and confirming a drawn line, are still to come.
- **BAR's interface on a near-square screen** (a foldable unfolded): the player list covers the order menu's last
  column; the minimap is shrunk until tapped.
- **The map's edge:** touch navigation there is still open.
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

- Only one phone has run it; other Adreno 7xx/8xx phones should take the same path but are untested. Mali, Xclipse
  and Tensor GPUs have no driver path in this stack.
- A match uses 5-6 GB of RAM; Android's low-memory killer has taken the game.
- The app's touch camera, panels and touch building are LuaUI user widgets: a lobby that turns custom widgets off
  loads none of them (the pad's mouse and keys still work; touch is then mouse clicks only). BAR's Code of Conduct
  asks for custom widgets used on public servers to be posted publicly (#widgets): they are all in
  `app/src/main/assets/bardroid/`. Shipping them with BAR (or touch support in BAR's own widgets) would settle both.
- Reports drafted for upstream, not filed ([upstream/](upstream/)): BAR's saved games crash the engine on load
  (Windows too), Mesa's KGSL present-fence path, an arm64 AI bug in CircuitAI.
- It is 100% vibe coded: an AI assistant (Claude Code) wrote all of the project's own code at the author's
  direction, so it wants review by people who know the engine and BAR; [WORKLOG.md](WORKLOG.md) records every
  request and the time spent.
