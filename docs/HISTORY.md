# BAR Droid — history

What was found, measured and decided, session by session (newest first). The current state, build steps and next
steps are in [HANDOFF.md](../HANDOFF.md); this file is the record behind them. Paths like `..\Build APK.bat` refer to the
launchers' old place beside the checkout (now in the repository root); sections named here such as "Gamepad",
"Busy scenes" and "Next steps" are in HANDOFF.md.

## Fitting BAR into an 8 GB phone (2026-10-29, evening and night)
Kailil: "Work on getting the game to fit on a smaller ram phone". Online-safe means client settings only, so each
idea was a run on the dev phone (`tools/phone-memory.ps1`: a skirmish started by intent, `start skirmish`, with engine
settings for that run only through `dev-springsettings.cfg`, background apps stopped first; the engine's GPU memory
from Android's GL mtrack, its heap resident and swapped, the phone's available memory every 5 s; build\phone-memory.csv).
Android's resident total includes the GPU memory mapped into the engine; the engine's own heap shows as "Unknown"
(the container's allocator is not Android's). The engine's `--list-config-vars` named the memory settings to try.
First result: only `CompressTextures = 1` decided it (GPU ~2.75 → ~2.45 GB): 5 of 5 runs played on, up to a full 10
minutes of game (frame 18379, x1), the phone's free memory steady at ~600 MB; 9 of 9 runs without it were ended while
loading or at the first frames. No help on their own: Lua pools off and faster GC, map texture streaming, 2048
atlases, no model preloading (BAR loads them anyway), no sound, 70% render resolution, no deferred buffers. But
compression breaks the unit icon atlas (icons are black squares) and the projectile perlin texture, on Windows too,
also when switched off again after loading (the engine reads the setting once): an engine bug, drafted for Recoil
(`docs/upstream/recoil-compresstextures-fbo.md`). `touch-widget-test.ps1 -Settings` adds engine settings to a laptop
run.

Kailil then: "Do whatever is necessary to make it playable on low memory phones" (could the app pretend every phone
has 12 GB? No: Android's low-memory killer acts on the memory really in use). The evening's runs, now with taps on the
map so the game is played, were less kind than the first five: compression alone was ended in most of them. What
was found, and what the app does now on phones under 9.5 GB (launch-bar.sh `LOW_MEMORY`, automatic; 12 GB phones
unchanged):
- **The black icons, fixed in the app.** The engine loads GL through GLAD's own loader (`dlopen("libGL.so.1")`, then
  `glXGetProcAddressARB` from that handle; never `SDL_GL_GetProcAddress`), so `libbardroid_pace.so` wraps `dlsym`:
  asked for `glXGetProcAddress(ARB)` it hands back a wrapper whose `glFramebufferTexture2D(EXT)` gives a compressed
  texture uncompressed RGBA8 storage before it is attached (`BARDROID_FBO_UNCOMPRESS=1`): `atlasRendered=1`, no perlin
  warning. Every other `dlsym` is a tail call (`musttail`): glibc finds `RTLD_NEXT` from its caller's address.
- **Where the memory goes.** Android's resident total for the engine includes its GPU memory; inside, glibc's malloc
  held only ~1.65 GB of ~4.1 GB: the engine links mimalloc (four 1 GiB arenas, ~2.35 GB used, live and mostly swapped
  out; `MIMALLOC_*` options are read, purging gave nothing back), and the 128 MB blocks in glibc were the engine's
  **Lua memory pools**: 32 size classes of 4 MB each, every page written when a pool is made, nine of them in a game
  (1.15 GB, mostly swapped out), while BAR's Lua uses ~150 MB in all. `UseLuaMemPools = 0` (and
  `TextureMemPoolSize = 0`): the engine ~1.1 GB smaller (5.8 instead of 6.9 GB resident plus swapped). Phone-wide at
  80 s into a game: 7.24 GB of RAM, of it 2.25 GB unevictable (GPU), 1.97 GB zram holding 5.7 GB of swapped pages, the
  rest the system and caches. A GPU allocation log (a test build of the pace library, every texture and buffer of
  2 MB or more with the engine function that made it) found BAR's two projectile texture atlases at 8176x6056 and
  6616x6152 (`MaxTextureAtlasSize*` does not limit them), a 4096x4096 half-float BumpWater shore-wave texture
  (128 MB), a 160 MB model buffer, 7 stream buffers of 16 MB; QTPFS says its own footprint is 379 MB.
- **BAR's GL4 unit shaders came back.** `cus2 = 0` keeps BAR's CUS GL4 gadget from starting when LuaRules loads, but
  in the controller game ("Beyond All Reason $VERSION": BAR's developer mode) BAR's Options widget sees 3 GB or more
  of GPU memory (the engine reports the phone's RAM, 7072 MB, also with Mesa's NVX/ATI memory extensions hidden) and
  switches them back on at the game's start; switched off again afterwards (`luarules disablecusgl4`) gave no memory
  back. `bardroid_lowmem.lua` (layer below BAR's Options) puts cus2 back to 1 once LuaRules has seen 0, so BAR's
  check finds nothing to switch: 60-100 MB of GPU less. In BAR's own game the phone's GPU counts as a low-end one and
  BAR never switches them on.
- The mode: `UseLuaMemPools 0`, `TextureMemPoolSize 0`, `CompressTextures 1` (with the pace fix), `cus2 0` (with the
  widget), `BumpWaterShoreWaves 0`, `GroundDecals 0`, map texture streaming, 2048 atlases, no deferred buffers, no
  high-resolution info texture. GPU at most ~2.5 GB (was ~2.75), the engine ~5.7 GB resident plus swapped (was ~7.2).
- **Result:** 4 of 6 five-minute skirmishes with taps ran through (frame ~7190), the plain app 2 of 3 with nothing
  set by hand; the others ended while loading or in the first minutes, the phone's free memory always down to
  550-650 MB. Playable, with little to spare: close other apps first. The launcher says "low-memory mode" for such a
  phone, and Android's ending says so. Fps in these games: 12.5 over the first minute (swapping in), 23 the next.
  Not tried: an online game (the dev phone never logs in). What is left is BAR's own (projectile atlases, map
  textures, the pathfinder) or the engine's.
- `tools\pace-test.ps1` ran a helper (`files/crun.sh`) the app never writes: now the app's own `files/container.sh`
  (ALL PASS on the dev phone with the shipped library).
- **BAR's benchmark on the 8 GB phone** (Kailil: "I want the 8gb phone getting passed multiple real bar benchmark
  tests"): "Benchmark BAR" (Starwatcher, up to ~1,300 units fighting) in the low-memory mode ran through 13 times in a
  row (results at frame 2016, a clean quit), never ended by Android; the phone's free memory stayed above ~700 MB.
  `tools\phone-bench.ps1`, five recorded runs: Sim 41-49 ms, Draw 20-22 ms, Update 9 ms a frame, the main thread at
  x0.45-0.53 of real time, ~12 fps in the busiest minute, 1536-1920 MHz on the prime core, the GPU at ~400 MHz and
  ~43% busy, thermal status 0 throughout (the dev phone never got hot enough for the tool's warm-up target). So in the
  benchmark's battle the phone survives but falls behind live play by half. The benchmark's map is small: the 1v1
  skirmishes on Supreme Isthmus (a 144 MB map against Starwatcher's 75 MB) are the harder test (2 in 3).
- phone-bench itself misread four of those runs: piped into `adb exec-in`, its helper scripts sometimes reached the
  phone cut short while a game loaded (a run's start time empty, so the previous run's results counted at once; a done
  check that answered with a shell error); a run that went past midnight never found its results (its log lines
  `00:...` compared as earlier than the start); `adb push`'s progress line stopped it when a caller merged stderr;
  and a game that Android ended was waited on for the full 12 minutes and recorded like any other. Now the scripts go
  as files (`adb push`), a start time is checked, times compare across midnight, the push ignores stderr, and a run
  without results stops at once and says why (`ended` in build\phone-bench.csv, "FAIL the run gave no results").
- The same 1v1 skirmish on Starwatcher: 3 of 3 played through (the engine ~5.1 GB resident plus swapped against ~5.7,
  GPU ~2.4 GB, free memory never below 668 MB). So an 8 GB phone's skirmish defaults to Starwatcher (`Prefs`: until
  the player changes the map in the launcher, `mapChosen`), and the game service fetches it before a skirmish where
  the first install fetched Supreme Isthmus. 12 GB phones keep Supreme Isthmus.

## A dev phone, and the first 8 GB phone (2026-10-29, afternoon)
Kailil gave the agents a phone of their own: always on USB adb to the laptop (Wi-Fi adb as a backup), "You can use this
phone 24/7", its screen ultra dark at all times, the normal minimum brightness for benchmarks; his Fold7 only for
builds that need his testing. He called it a Galaxy S22 Ultra; adb reports SM-S918U, an S23 Ultra (Snapdragon 8 Gen 2,
Adreno 740, 8 GB, Android 17, One UI 9). `tools\devphone.ps1` keeps it connected and dark (brightness 1, Extra dim
100% kept across restarts, the wallpaper dimmed, awake while powered; `tools\devphone-watch.bat` every minute), and
the tools drive it (`..\phone-device.txt`). The darkest the shell can do: a black overlay window would black out
screenshots and Android drops touches through it; SurfaceFlinger's color matrix is refused to the shell on Android 17.
BAR Droid installed on it in about 4 minutes (Debian, Mesa, engine, BAR's game and lobby, the controller game over a
fast line); the GL check passes (FD740, OpenGL 4.3, Turnip for Vulkan). But it cannot play: with ~3.4 GB available at
rest (4.1 GB after `am kill-all`), the engine is ~2.7 GB resident 30 s into loading a skirmish, the rest goes to
compressed swap (BAR's benchmark ran at 1-3 fps, CPU capped at 0.9-1.5 GHz), and Android's low-memory killer ends the
engine (exit 137) or the whole app within 1-2 minutes: two benchmark runs and three skirmish starts. The engine runs
at oom_score_adj 0 like the top activity. An unexplained "recents" gesture in the first run was not a touch (a
second run logged every input event: none); the app's own launcher came up when the engine was killed. phone-bench
on the dev phone stopped at once: adb's progress line on stderr is an error record under phone-bench's
`$ErrorActionPreference = "Stop"` (fixed in toolchain.ps1 Invoke-PhoneScript).

## Overnight hardening, no phone (2026-10-29, night)
Kailil went to bed ("spend all your time doing the permanent hardening and bug fixing ... don't try to reach the
phone tonight"): laptop checks only, the APKs built and not installed. Found and fixed:
- The widgets' files for the app (the pointer's answer, the game, the building picked, the pad's menu) were rewritten
  in place; `io.open "w"` empties a file first, and the app reads them many times a second: an empty read could
  place a building without PLACE, drop the pad's menu, or (the game file, read once per time stamp) name the wrong
  game for a match. All are written to a `.tmp` and renamed now (3eb6c84).
- The pad's LB orders aimed at the mouse pointer, not the reticle (wrong while it glides back; patrol or fight on a
  unit only picked the order); they aim at the middle (3eb6c84). The order menu kept an order lit that the menu had
  moved from under a resting pointer (e2f7477). The build menu copy's D-pad stuck on the last page's last option
  (06e016d).
- The laptop was throttled (4-8 fps, the screen off), which broke the touch test itself: a fixed 240 s stop, toasts
  faded before their checks, moves walked before R3 came, BARb's first raid ending the game, a patrol to where the
  commander stood (the engine ends it at once). The test stops when its log stands still, plays against NullAI and
  holds its queues (3eb6c84, ce956be); the order menu's following and letting go now run in it with a made-up pointer.
- Open, for the phone: a touch tap waiting for the game's answer (up to 250 ms) can click in the middle of a newer
  gesture (`RtsTouch`, DELIVERY.md).

## The gamepad, second round of notes; the 3x3 menu in the controller game (2026-10-29, night)
Kailil, testing in the controller game: "What happened to my 3x3 build menu grid? its gone and now its displaying the
huge list again", RB "doing a weird selector system, i dont want that, i want a mouse cursor, with a stroke just like
the orders", "pressing RB or LB cycles the tabs", the menus' hold "too long. make it a quarter long", the order menu's
pointer "increase speed by a quarter", the touch PLACE button "not even putting the place box over the orders box",
and "when holding A to select units ... is it not possible to do the 0.8.5 method". The phone's log showed the
controller game (GAMEPAD_GAME=1), where the app's copy stood down for v0.8.5's build menu. Now it runs beside it there
(`WG.bardroidBuildmenu`; BAR's `WG.buildmenu` stays v0.8.5's, which v0.8.5's radials read) and shows while the app's
controls have the pad: `bardroid_pad.lua` sets `WG.BarDroidOwnsBuildMenu` on the switch and hides v0.8.5's panel
through v0.8.5's own `controllerSetPanelVisible(false)`, from `DrawGenesis` (v0.8.5's camera widget sets that switch
again in each Update; after every Update and before anything is drawn or clicked, the app's wins). The PLACE button
and the touch spot work in both modes. The v0.8.5-selector path is gone. RB and LB on the build menu turn its pages
(the same place on the next or previous page; RB held there stays Alt). The menus let go after 0.25 s of pushing off;
the order menu's pointer at 5/8 speed. v0.8.5's area select (read from `ControllerCameraTestSelectAreaUnits`: radius
320, 120..1200 in 80s on the D-pad, units first, RT including buildings and toggling into the selection): A held
past 0.25 s with nothing picked lets the click go and a circle in the middle selects the units it passes over while
the left stick pans; B undoes it. With an order picked A held still draws with the pointer. touch-widget-test: the
pages, the area select in BAR's game; in the controller game the switch hides v0.8.5's panel, shows the 3x3 menu, RB,
the pages, and the way back. padgame-test: the pages, the area select, the order menu's speed.

## The gamepad: Kailil's notes from playing it (2026-10-29)
Kailil, while playing: the LB grid placement of v0.8.5 to be copied "1 to 1 overwriting what you have now" (the touch
buttons left for touch); the pointer kept inside the build and order menus, let go on B or "constantly move the left
stick out of the box for ... 1 second", half speed on the order menu; "Hold X for a pan path isnt working. its just
applying a move command when I release the X"; on factories "X doesnt remove one from queue or RT + X doesnt remove
5"; area mex "makes the highlight mex options appear for a split second then drops the command"; "i cant click and
drag to draw the circles" (repair, reclaim, area mex); LB + B twice or held "triggers stop first"; RB held does not
insert into a factory's queue; then "make sure that snap back is smooth and not jerky", and "i want the controller mod
toggle in this build". The cause of the drags: Recoil counts a drag only when the pointer moves
(`CMouseHandler::buttons[].movement` against `dragCircleCommandThreshold` and friends in `GuiHandler.cpp`), and the
pointer held in the middle never moves while the camera pans. So while A or X is held the left stick moves the
pointer (`PadGame` "drawing"); let go, it glides back to the middle (ease-out over 0.16 s, from where it was: the
app's own moves, or the touch widget's hover answer after a touch or a menu). v0.8.5's placement (read from
`ControllerCameraTestHandlePlacementInput`): A places, X places and stays, B cancels, the D-pad turns and spaces, Back
slows the pan (30%, `bardroid_touch.lua`), LB held a grid (Alt: the engine's filled rectangle) where a tap of A starts
the drag and the next A ends it (X: placing and staying; B: the order put away first through `SetActiveCommand(0)`,
which drops the engine's pending press, then the button let go); the same tap-draw-tap for an area-only order
(`bardroid_pad.txt` "armed area": area mex). The menus keep the pointer on them (`bardroid_pad.lua`, the build menu
copy: warped back to the edge, let go after a second outside); the order menu at half speed. X on the build menu is
the right button (a factory's queue minus one, RT + X five); RB held there is Alt (Recoil's `FactoryCAI`: Alt queues
at the front). LB + B decides after the double-tap window (stop), on the second tap (repeat) or at half a second held
(wait), only one of them. The controller mod toggle: in the controller game a quick triple tap (`RtsTouch`, where
elsewhere it selects the type on the whole map) switches `ControllerBridge` between v0.8.5 (packets as before) and
`PadGame` (packets "disconnected", so v0.8.5 idles; it drops to mouse mode as soon as the mouse moves), the touch
widget's pad camera with it, and `bardroid_pad.lua` notes "CONTROLLER MOD: ..."; there RB drives v0.8.5's own build
menu through its controller calls (`controllerSetFocus`, `controllerMoveFocus`, `controllerActivate`), since the app's
copy stands down in that game. `PadMouse` and `PadButtons` hold the pad's interface without Android classes, so
`tools/padgame-test` (laptop-tests and CI) runs `PadGame` against a made-up pointer and game: 30 checks of the button
sequences above.

## The gamepad online: v0.8.5's controls rebuilt (2026-10-29)
Kailil, after testing: "Remove the full map thing when I click the right thumb stick ... BACK + RB sends the mouse to
orders menu and does the highlight behavior that the build menu does. So take a look at my controls that my Original
8.5 build had and match/rebuild workarounds to match the behavior of that original mod. match 1to1 using any means
necessary ... dont worry about radials ... I want mouse to be locked to the center of the screen like it is in 8.5 so
left thumb stick is controlling the mouse. Right stick will work as the pan, zoom, rotate etc."
v0.8.5's "Build-First Commander" bindings and behaviour were read from its source (`gui_controller_camera_test.lua`
in `C:\Tools\BARGAMEPAD\src\bar-codex-perf`, its docs) and rebuilt: `PadGame.java` (new) owns the pad in BAR's game.
The pointer is held in the middle of the screen (an absolute X move, again after a touch or a real mouse moved it),
so the left stick pans the map under it with v0.8.5's camera (the touch widget's pad lines in their first form: LS
pan, LT faster, RS turn and zoom, LB + RS tilt). A is the left button there (select, double select, box select by
holding A and panning, place), X the right button (BAR's default order: v0.8.5's smart X), B cancels or clears.
RB tapped opens the build menu as before; Back + RB the order menu (`bardroid_pad.lua`, new): its grid worked out as
BAR's `gui_ordermenu.lua` lays it out (its commands in its order, `setupCellGrid`'s cells), the pointer onto an
order, the D-pad steps, BAR's own `WG.ordermenu.setHighlight` lights the order, A gives it through
`SetActiveCommand` as BAR's button does (an order that needs a target sends the pointer back to the middle). The
rest: control groups on Start + D-pad (BAR's `group set/select`, the autogroup by Alt+N), idle builders and units,
the commander, a camera bookmark, LB + A/X/Y orders at the middle (at once where the game allows unit-control
widgets, BAR's default; else picked for A), LB + B stop/repeat/wait, L3/R3 queue removal, Back + R3 the D-gun, Back +
Start a free pointer (free before the start, as v0.8.5), RB held Space (front of the queue), with a building picked
LB held Alt (an area). Left out: the radials (the menus instead, as asked), v0.8.5's own Smart-X tree (BAR's default
order does most of it), Disassemble, self-destruct, mouse-mode speeds. The right stick click's whole-map view is gone.
touch-widget-test: the order menu on the pad, Move picked from it, B, a group set and recalled, the commander, R3, LB +
B (all pass; one earlier run failed five camera checks before any pad case, a rerun passed them all).

## The gamepad and the build menu, as in v0.8.5; the lobby at 135% (2026-10-29, early)
Kailil: "so i really cant get behavior close to what i had with 8.5 in this new method? can you try your best to
finesse a way to do it using this system you have built. Like RB with builder selected snaps the mouse to the build
menu grid spot one, then a highlight stroke and enlargement of like 10 percent of the build item as the mouse
highlights on to easily show what item im selecting. pressing A snaps the mouse to the center of the screen ready to
place it." The build menu copy owns it: RB (`act pad_build` through the touch widget) puts the menu on the pad and
the pointer on its first option (`Spring.WarpMouse`, once the menu has laid the cell out); the D-pad (`pad_left` ...)
steps from the option under the pointer, past the left or right edge to the page before or after (wrapping);
the option under the pointer is drawn 10% bigger with a gold outline (BAR's own hover drawing, scaled about the
cell's middle) while the pad is the input; A is still the pad's left click, so BAR's own menu picks the option, and
the copy then sends the pointer to the middle of the screen. B (or RB again) leaves the menu, as does moving the
pointer off it. The copy tells the app in `bardroid_pad.txt` ("focus 1", rewritten every second) so that
`ControllerBridge` gives the D-pad and B to the menu meanwhile, and while a building is picked the D-pad turns it
(`buildfacing`) and spaces a row (`buildspacing`), X places it and keeps it (a Shift click; v0.8.5's placeStay),
B is BAR's right click (puts it away). The touch PLACE button stays off for the pad and the mouse (A or a click
places where the pointer is). A D-pad on hat axes now counts short presses too. touch-widget-test: RB, right and
down, past the left edge to the last page, the pointer to the middle after a pick (pointer moves recorded, not made,
without -Pointer), the highlight drawn once, the D-pad turning a picked building.
Then: "Add the 135 percent lobby change into tissue": the lobby's interface scale held back since the evening (the
lobby at 135% on both screens, folded and unfolded alike; "new folded and unfolded lobby UI is 135. just keep them the
same") goes in: launch-bar.sh writes 1.35 for every window size; the lobby tests run at 135% and pass.

## Building by touch: a PLACE button (2026-10-28, night)
Kailil, on the shape strip: "one tap needs to have a done confirmation the done should be large in the bottom of the
screen. it should take up the width of the orders menu and appear on top of the orders menu as one big green button
saying done or place", and "Get rid of the circle and x and move those to the order menu button popup with done as
smaller sub buttons within done." So the strip keeps ONE · LINE · GRID · BORDER (four wider buttons), and while a
building is picked the copy draws PLACE over BAR's order menu (its rect from `WG.ordermenu.getPosition`, as the
layout editor finds it; under the middle of the screen when there is none, before the start), dim until a spot is
picked, green after, with ↻ and ✕ as smaller buttons inside at its right. A tap on the map no longer clicks:
`RtsTouch` sends "spot <x> <y>", the copy keeps the ground point and draws the building there (`gl.UnitShape` and a
green ring, from its DrawWorld, which now stays on after the start), and writes where it is on the screen and where
PLACE is into `bardroid_place.txt`; a tap on PLACE is the Shift click on the spot, wherever the camera has gone since.
The building stays picked for the next spot (✕ or a long press puts it away); LINE, GRID and BORDER drags still build
at once. The copy now answers IsAbove for the menu and PLACE, so a finger there is a click (before, a drag on the
build menu panned, and with a building picked a tap there would have picked a spot under it). touch-widget-test:
PLACE lies over the order menu, rotate and cancel inside it work, a "spot" line picks the spot and the file says
so (picture sent to Kailil); the taps on the phone are his to check.

## The gamepad online: a mouse and keyboard (2026-10-28, night)
Kailil: "spin up a helper to research some way to get our gamepad support working in online." The research (a
background agent, BAR release 2026.10.20-1 and master read): v0.8.5 cannot run as a user widget online. It reads the
pad over a socket (the sandbox removes `socket`), it relies on ten of BAR's widgets patched with `WG.*.controller*`
hooks (online BAR's originals load), it uses widget-handler internals, and its 89 `GiveOrder*` calls need
`allowunitcontrolwidgets`. What works with nothing from BAR's developers is the pad as an X mouse and keyboard from
the app, which no widget, modoption or lobby setting can see or block. Its other findings: a lobby that turns custom
widgets off loads none of the app's widgets (the touch camera included), and BAR's Code of Conduct asks for custom
widgets used on public servers to be posted on #widgets. Kailil: "Yes, start the pad-as-mouse-and-keyboard plan".
`ControllerBridge` now has three modes: the lobby (as before), the controller game (v0.8.5 reads the packets; the
touch widget says which game it is in `bardroid_game.txt`), and BAR's game: the left stick the pointer (x0.6 over the
interface by the widget's hover answer, x0.35 with LT held), the right stick the camera through the old pad lines
(a pan, or with LB a turn and a zoom; tilt stays with two fingers), A and B the mouse buttons, RT Shift, LB Ctrl,
the D-pad 1-4, Back Escape, Start F10 (BAR's options; Escape, 1-4, Ctrl+1-4 and F10 checked in BAR's
keybind_defaults.json), and X, Y and the stick clicks the touch widget's actions (fight, the next idle builder,
select all, the overview, now also a toggle). Every key and button is let go when the mode changes or the screen
pauses. touch-widget-test: the overview toggle and the game file; the pad itself is Kailil's to check on the phone.

## Building by touch again: the shape strip (2026-10-28, late evening)
Kailil: "what happened to the touch building system we created a while back, wht the line, grid and border setup.
revamp the whole system before you bring it in." That was the touch-only mode of 2026-10-25 (`c33d9af` a touch build
menu with ONE / LINE / GRID, `f6a3c6a` a ghost with BUILD / ROTATE / CANCEL beside it), removed in `5b3ae63` when
Kailil found the mode "all bad" and "ugly and clunky to switch between". Asked how it should come back, he picked the
build menu's own strip: while a building is picked, the copy's page strip (`bardroid_buildmenu.lua`, from
`tools/make-buildmenu.py`) shows ONE · LINE · GRID · BORDER, ↻ (BAR's `buildfacing inc`) and ✕ (puts it away), the
chosen shape lit; no new panels. The app does no building of its own: the copy tells `RtsTouch` the shape in
`LuaUI/Config/bardroid_place.txt` ("place line", rewritten every second while a building is picked, so an old file
counts as none), and the finger is a mouse with keys held, BAR's own placing as with a mouse: a tap on the map is a
click with Shift (one there, and the building stays picked), a drag with LINE, GRID or BORDER is the engine's build
drag with Shift, Shift+Alt or Shift+Alt+Ctrl (`GuiHandler::GetBuildPositions`: a line, a filled rectangle, a hollow
one); with ONE a drag pans. A long press (right click) also puts the building away. Each building picked starts with
ONE. touch-widget-test: the strip shows for a picked building, a tap picks GRID and writes it, ↻ turns the building,
✕ puts it away (screenshot sent to Kailil); the taps and drags on the phone are his to check.

## The build menu as a 3x3 grid (2026-10-28, evening)
Kailil, after playing with the copy: "Can the build menu be reduced to show only 6 items per page and have a 3x3 grid."
BAR's paging already takes the bottom row for its arrows when the options do not fit, so the copy lays the menu out
at the left as 3 columns of square cells, 3 rows tall (the panel no taller than that, its bottom above the unit
panel): 6 options a page with the arrows below, all of them when a builder has 9 or fewer. The commander's 26 options:
3 x 2 and "1 / 5" (touch-widget-test, a screenshot sent to Kailil); the editor's size and move work as before. The
first try did not load: BAR's file sits near Lua 5.1's limit of 200 locals in one chunk and two more constants passed
it ("main function has more than 200 local variables"); everything the copy adds is now one table (`droid`), fewer
locals than before.
Then, from the screenshots: "keep it the same size, but move the left and right arrows to into thier own small strip,
it will be about a quarter the height of the real grid. and that will allow 3x3 items on top", "the page swapper and
inidcator needs to be bigger. double the size", "increase the total height of the build menu to allow the pictures to
fill their squares". So: 3 rows of items always (9 a page; BAR's paging set aside at the left), the arrows and the
page number in a strip half a cell high under them, their text twice BAR's size, the grid centred, and the menu as
tall as three rows of cells as wide as it allows plus the strip (height / width 1.16 on the laptop). The commander's
26 options: 3 pages.

## Past midnight: a sizeable copy of BAR's Build menu; quiet laptop checks (2026-10-28)
Kailil: "the vaniallal build menu works fine for touch. just rebuild the exact same one with the ability for us to
resize it freely. becuaser right now it is too large."
- **Which menu:** with the controller game on (the app's default) BAR's Build menu (gui_buildmenu.lua) replaces the
  Grid menu in BAR's released game too: the two games share one widget list (LuaUI/Config/BYAR.lua). The controller
  game's is v0.8.5's edit of it, which the gamepad drives (~300 more lines).
- **The copy:** `tools/make-buildmenu.py` takes BAR's file from the release in BAR's rapid pool (test-31740-57a02af,
  pool md5 a5d8e476..., the same release the phone had) and makes `bardroid_buildmenu.lua`: its own name (BAR ignores
  loose copies of its widgets under their names), its size and place from the layout editor (width and height from
  the bottom left corner, a move), and three handler calls through BAR's stand-in for user widgets
  (RegisterUnitCommand, RemoveCallIn, no Grid menu switch-off). Orders go through `Spring.SetActiveCommand` as in BAR's,
  so it works where a host forbids widgets that give orders.
- **Switching:** v0.8.5's build menu is "Build menu (controller)" in the package now (`tools/build-gamepad-game.py`,
  the only change), so launch-bar.sh can turn BAR's "Build menu" off and the copy on for BAR's released game while the
  controller game keeps its own; the copy stands down in the controller game. The copy runs only while the phone's BAR
  file has the md5 it was made from (Installer writes it to `.bardroid-buildmenu` after each update); a BAR update to
  the build menu brings BAR's own back, logged as an Android-layer miss, until the tool runs again.
- touch-widget-test: shown for a builder, picked in the editor, Size - twice (0.855), dragged, Reset; in the controller
  game the copy stands down and v0.8.5's shows. All pass in both games.
- On the phone (20:26, Kailil's phone free; the app's benchmark start): Installer wrote BAR's gui_buildmenu.lua md5
  a5d8e476... (the copy's), launch-bar.sh switched the copy in ("build menu: the app's copy of BAR's"), the renamed
  controller game installed, and in it the copy stood down for "Build menu (controller)"; the benchmark ran to its
  results and quit (exit 0), no widget errors. BAR's options log "'buildmenu_maxposy' widgetConfig: unknown widget
  Build menu" in the controller game: that one setting of BAR's options panel finds its menu by name; its other build
  menu settings go through WG.buildmenu and reach both menus.
- **Quiet laptop checks** (Kailil: "is it possible to not have it hijack my mouse or keyboard when its testing", "the
  laptop test is also appearing on top and not letting any window display over it"): the engine's window was never
  "always on top" (its style sampled during a run), but every new game window opened in front and took the keyboard,
  and a few touch checks move the real pointer (`Spring.WarpMouse`). The checks now start the engine without
  activating it (`toolchain.ps1` Start-Engine, SW_SHOWNOACTIVATE: 56 samples of the foreground window during a run,
  never the game) and place its window off every screen (`WindowPosX = -10000`; the engine does not clamp it, spectate
  and touch tests pass, screenshots included); the pointer checks run only with `-Pointer` (touch-widget-test,
  laptop-tests), the benchmark's pointer only with `-PointerOnBattle`. fp-tuner, used by hand, keeps a normal window.

## Late night: the build menu vanished; unfolded at interface scale 1.0 (2026-10-28)
Kailil: "I chose bottom when I had the build menu selected, and now it's complete gone ... I restart the game and it
comes back ... Is it not possible to adjust the size of the build menu? If not then we will just have to reduce the
interface scale to 1.0 on unfolded".
- **The vanishing:** his skirmish runs the controller game, which uses BAR's older Build menu (gui_buildmenu.lua, not
  the Grid menu). The editor's Bottom called its `WG.buildmenu.setBottomPosition(true)` while it was on screen; its
  next draw failed (`gui_buildmenu.lua:1398: attempt to index field '?'`: a cell drawn without its command, in a
  render-to-texture) and BAR removes a widget whose call-in fails, until the next start. BAR's saved settings on the
  phone were back to the left afterwards. The editor no longer moves BAR's menus: they show as fixed.
- **The build menu's size:** neither build menu takes one from another widget. The older one is as wide as the
  interface scale makes it (0.212 of the screen x the scale, for a 16:9 screen) and as tall as the room between the
  minimap and the unit panel; the Grid menu the same. So unfolded is at interface scale 1.0 now (launch-bar.sh at
  start, bardroid_touch.lua on unfolding), as Kailil chose; folded stays 2.0.

## Night: the chat's typing box and the layout editor (2026-10-28)
Kailil: "when I'm typing a message I the chat box, I want the message to word wrap and grow smaller as new lines
populate so I can see my entire message. Right now it's just pushing the message off screen to the right"; "the
message chat box overlaps with the GAME COUNT DOWN POP-UP"; and "a tool to select ui elements on screen while in a
real game ... tap A ui element, to adjust its size, position, and if possible, text size inside of it and padding".
- **What can be moved.** BAR 2026.10.20 sandboxes user widgets (no widget handler, no patched copies of BAR's
  widgets), so the app reaches BAR's panels only through what they offer other widgets (`WG.*`): the minimap's
  `MinimapMaxHeight`, the player list's `SetScale`, the build and order menus' `setBottomPosition`. BAR's top bar and
  start countdown (`gui_pregameui.lua`, 67% up the screen) have none. Kailil chose the editor for everything movable
  now, with a movable HUD for BAR's own panels written up for BAR's devs (HELP-WANTED.md).
- **Typing box** (`bardroid_chat.lua`, now layer -96000, under BAR's chat at -95000, so it hears Enter first): its own
  box at the top of the chat box, the text wrapped at word boundaries and smaller past two lines (down to 55%), the
  chat lines below it; before the game starts the lines end above BAR's countdown. As BAR's: the channels and
  Ctrl/Alt/Shift+Enter, Escape, history, Ctrl+V, "/" commands, and BAR's word filter (`luaui/configs/badwords.lua`,
  a message held back once). BAR's own box still opens for map marker labels. `/hud` opens the editor.
- **Layout editor** (`bardroid_layout.lua`, new; three fingers held for most of a second in RtsTouch, `act hud`, or
  `/hud`): outlines and names every panel; a tap picks one, a drag moves it, a pinch or the buttons size it; text size
  and padding for the app's own (chat, unit info, spectate bar). Settings per screen shape (wide: folded, near-square:
  unfolded) in its config. The button bar sits mid-screen (at the bottom it covered the unit info panel and the player
  list, so a tap on them hit a button; found by the test, screenshots before and after).
- **Found in review afterwards: typing could also press BAR's hotkeys.** BAR's widget handler runs its key actions
  (`actionHandler:KeyAction`, the hotkeys BAR binds in Lua) before any widget hears a key, unless a widget owns the
  text (`barwidgets.lua` KeyPress); BAR's chat takes ownership while typing, the new box did not, so a letter typed
  could also give an order or pick a build. The box and the open editor now own the text (`widgetHandler:OwnText`,
  which BAR's handler gives user widgets too); the test drove the widget's KeyPress directly and could not see it.
  touch-widget-test checks the ownership (BAR's chat refuses a map marker box while the app's box is open) and that
  no box opens while the editor holds the keys.
- touch-widget-test: 28 new checks (typing: opens on Enter in the allies' channel, wraps, smaller past two lines,
  Backspace, Escape, a sent line reaches the chat; editor: /hud, picking, a drag, Size/Text on the chat, Size on the
  unit panel, BAR's player list and minimap, the top bar fixed, Reset all, Done, three fingers); all pass, spectate-test
  all pass, lint 0 warnings.

## Evening: Shoulder on any ground and any unit (2026-10-28)
A review of `bardroid_spectate.lua`'s afternoon changes, with new spectate-test cases, found three ways the fitted
Shoulder missed "every unit is centered":
- **Another unit kept the last one's camera.** The arrows and a double tap kept Shoulder on but not its fit: a
  Jethro after another unit got that unit's distance (243 against its own 144) and sat off the screen's middle. The
  view is fitted again whenever the unit followed changes.
- **On a slope the engine moved the camera.** The fit assumed level ground: the Spring camera's focus is always on the
  ground and the engine lifts a camera below the ground to 5 elmos above it (`CSpringController::GetPos`), so a unit
  with rising ground behind it was framed from below (the replay's unit at 563,571 of 1280x720; the camera 5 elmos
  over the ground). The fit is made each frame from the ground as it is: the camera at least 20 elmos above the ground
  behind the unit, the focus where the line through the unit's middle meets the ground (gliding as the unit moves).
- **The camera looked past the unit.** With `CamSpringLockCardinalDirections` on (the engine's default; the app's
  springsettings.cfg turns it off, BAR or a player can turn it on again) the Spring camera looks not along its state's
  turn but along a "locked" one, up to ~25 degrees off (`CSpringController::GetAzimuth`): the Commander facing 1.32 rad
  was looked at from 1.06. The widget now gives the engine the turn that looks where it means.
spectate-test: all pass with the lock on and off (`-Settings @{CamSpringLockCardinalDirections=0}`, new); the
Commander at 640,355 of 1280x720, the replay's bot at 639,418.

## Afternoon: the unfolded screen, the views, Native tried (2026-10-28, from 12:30)
Kailil, spectating on the phone:
- **Native resolution: "a no go"** after a game unfolded at 2184x1968 (the launcher's Native choice stays; the phone
  is back at 100%: 2100x900 folded, 1198x1080 unfolded).
- **The lobby at 150% unfolded** ("unfolded, lobby UI scale should be default 150"): launch-bar.sh gives Chobby's
  per-size scale 1.5 to every near-square size key (the inner screen at 1080p, native, 85%, 70%: 2x4, 4x7, 2x3, 1x3)
  and keeps 1.2 for the wide ones.
- **The minimap half size unfolded until tapped** ("about half the size it already is, then when i tap it, it expands
  to default size"): `bardroid_minimap.lua` sets BAR's Minimap's `MinimapMaxHeight` as the engine's in-memory overlay
  (never saved) to half the minimap's height on the near-square screen; a tap on it only opens it, 7 s without one
  make it small again, folded it is BAR's. touch-widget-test checks it (told it is unfolded on the wide laptop
  window): half the height, a tap taken, BAR's size, small again after 7 s, BAR's size folded.
- **Up did nothing in the Shoulder view** ("the UP tune setting doesnt work in the shoulder cam"): the Spring camera
  (Shoulder, Table, Close, Mid) sets its focus height on the ground every frame (`CSpringController::Update`: "always
  focus on the ground"), so the height the widget gave it was lost. Up now raises the camera over the same focus at
  the same distance across the ground, looking down more steeply (a first try keeping the angle moved the near-level
  Shoulder's focus kilometres ahead and the camera into the ground). spectate-test: +300 lifts it ~270-300.
- **Table, Close and Mid are one view for every unit** ("save affects all units. not individual like SHOULDER AND FIRST
  PERSON"): Tune sets them for all, Save keeps them (the widget's config, `kept.views`); Shoulder and 1st person stay
  per unit type, Save still giving them to the equivalents. Old per-type Table/Close/Mid settings are not used.
- **Shoulder by default centred on the unit, close behind it** ("shoulder is very off by default"): fitted to each
  unit, the camera 4 radii + 40 elmos behind and 1.5 radii + 20 above its middle, looking through its middle (the
  focus where that line meets the ground); a unit type's own Shoulder (Tune) still wins. spectate-test: the unit at
  639,371 of a 1280x720 screen, the camera behind it.
- The lobby tests run offline now (one BAR account: a test login ended his game on the phone).

## Morning: the slow night was the phone; the info panel's cost (2026-10-28, from 06:30)
Kailil asked whether the graphics could drop by themselves as a game gets busy, and (seeing last night's numbers) "i
authorize you to investigate and automaotically do what you need to do to handle it"; if the spectating tools cost
the simulation, they should be off by default with a toggle.
- **Graphics presets do not help a busy late game**, and cannot be switched mid-game from our widgets anyway (BAR
  refuses `/option` and widget toggles from user widgets). The engine already keeps the simulation going when it falls
  behind: it reserves 15% of the main thread for drawing (`MinSimDrawBalance` 0.15) and draws as few as 2 frames a
  second (`MinDrawFPS` 2); BAR's presets mostly save GPU work, while the main thread holds the simulation (about half,
  the engine's C++) and BAR's Lua. Matches Kailil's own test (medium to lowest mid-8v8: still ~19 fps) and 70% render
  resolution (no gain).
- **Draw per frame "doubled" overnight (15-17 ms in the 10-27 evening runs, 26-29 ms at 02:36-02:48): the phone, not
  the build.** Same build, same folded screen (1680x720, interface scale 2.0, in both sets; the evening's profiler
  screenshots are 1680x720 too), after the phone rebooted at 03:51: Draw 10.4 / 11.2 ms, Sim 19.8 / 20.7 ms, game speed
  x1.03 / x1.00, 35-38 fps, with the GPU at 900-1050 MHz and the prime core allowed 2649 MHz; overnight the GPU sat at
  ~443 MHz and the prime core's cap at 1401-1689 MHz at the same skin temperature (status 2, 42 C). Samsung's limits
  depend on more than the moment's heat (hours of load before them); Draw follows the GPU clock. The phone's adb port
  5555 was gone after the reboot (wireless debugging still on: `adb mdns services` found it, `adb tcpip 5555` again).
- **The spectating tools need no toggle**: BAR's widget profiler on the phone does not list them in a game that is
  not spectated (they do nothing outside spectating), and spectating they cost ~0.1 ms a frame (above).
- **The info panel (`bardroid_info.lua`) was the costliest widget on the phone**: 7.9% of the benchmark's running
  time and 53 kB/s of garbage (BAR's own widgets 1.3% together; BAR's Info widget 0.3% in the evening run), with the
  pointer resting on the battle, as a finger leaves it. With a unit shown it rebuilt its text four times a second and
  each time fitted the text size by stepping down half a pixel at a time, wrapping and measuring every word at each
  step (up to ~30 tries), and looked every label's translation up again (a new closure and pcall each). Now: the
  size by binary search (~6 tries), fitted again only when the text or the panel changes (health moves only the bar),
  the recorded drawing made again only when what it shows changes, translations looked up once. Laptop, BAR's
  benchmark with the pointer on the battle (`tools/profile-benchmark.ps1 -PointerOnBattle`, new), two runs each: 2.69
  / 3.11 ms/s and 39.5 / 48.4 kB/s before, 2.01 / 2.03 ms/s and 18.5 / 20.0 kB/s after. `tools/touch-widget-test.ps1`:
  all pass (the panel shows the selection).
  On the phone the panel's cost does not show: BAR's benchmark with it on and off, alternating, the phone unlocked
  (11:29-11:39): x0.78 / x0.77 on, x0.74 / x0.72 off (the "off" runs drew lower CPU caps, 1401 against 1689 MHz for
  the prime core: noise). BAR's widget profiler had put it at 7.9% before the fix and 19.4% after (that run with no
  panel on screen): its shares on the phone are not to be trusted; measure with `-WidgetsOff`.
- `tools/phone-bench.ps1` new switches: `-DisplayScale <percent>` (Termux:X11's display scale for a run) and
  `-WidgetsOff "<name>",...` (widgets off for a run, each one's order put back afterwards; awk on the phone: Android's
  toybox `sed` and `grep` know none of GNU's `\?` and `s//`, and the shell took apostrophes in comments for quotes).
  **The phone locked itself at ~09:10** (after the morning's unlock; `dumpsys trust`: deviceLocked=1): every run since
  started with "game screen hidden: the engine stops drawing" and a portrait X screen, so its numbers are not a game's
  (one run never got the engine started and timed out after 12 minutes). Benchmarks need the phone unlocked; a run's
  launcher.log shows it ("X screen" landscape at the start, "hidden" only at the end).
- **`os.clock`: a suspected bug that was not one.** `bardroid_players.lua` (the list's 7 s), `bardroid_chat.lua` and
  `bardroid_bench.lua` timed with `os.clock`, which in standard Lua on Linux is the process's CPU time (all threads:
  faster than real time in a busy game); Windows' C library returns real time (the laptop: x1.00 over 42 s). They were
  moved to `Spring.GetTimer` (as the other widgets), with the benchmark widget logging the ratio on the phone: **x1.00 in
  every run** (98-586 s), so the engine's `os.clock` is real time there too and nothing ran fast. The change stays (one
  timer in all widgets); the earlier commit (5d4d54c) said otherwise.
- **A higher resolution** (Kailil: "investigate if its worth running native resolution on both, or at least increasing
  to 900p folded, and unfolded 1080p"). Folded, a real 8v8 replay (Supreme Isthmus, minutes 10-13, up to 1,876 units),
  the 30 fps cap, alternating, two runs each:

  | X screen (folded) | game speed | fps | GPU clock (median) | GPU busy (median) |
  |---|---|---|---|---|
  | 1680x720 (until now) | x1.01 | 29.7 / 29.7 | 342 / 342 MHz | 70 / 69% |
  | 2096x900 | x1.01 | 29.6 / 29.7 | 389 / 342 MHz | 71 / 66% |
  | 2520x1080 (native) | x1.01 | 29.7 / 29.8 | 443 / 443 MHz | 73 / 69% |

  Every size kept up; native holds the GPU ~30% higher clocked (more power and heat over hours), 900p costs little.
  Unfolded "1080p" (1198x1080) is about the 1157x1043 drawn until now. One pixel cap could not give both (folded has
  the more pixels at fewer lines), so patch 0006 has a line cap too (`LorieView.maxScaledShortSide`), both counted in
  X screen pixels: the display scale 100% for phones (`BarApp`, once for existing installs), at most 2100x900's pixels
  and 1080 lines (`GameActivity`): folded 2100x900, unfolded 1198x1080; render resolution 85%: 1785x765 / 1018x918.
  The way back to the old folded size: Display settings, display scale 150 (folded 1680x720, unfolded stays 1198x1080).
  **A heavy late game at 900p** (the same 8v8 from minute 20, ~3,600 units, the 30 fps cap, alternating, the phone
  unlocked by Kailil at 11:00; the first four such runs, earlier, went with the phone locked and are not counted):

  | X screen (folded) | game speed | fps | GPU clock (median) | GPU busy (median) | AP at the end |
  |---|---|---|---|---|---|
  | 1680x720 | x0.97 / x1.02 | 28.8 / 28.3 | 342 / 342 MHz | 69 / 67% | 44.7 / 46.5 C |
  | 2096x900 | x0.98 / x1.01 | 29.3 / 29.2 | 342 / 342 MHz | 67 / 72% | 50.2 / 47.4 C |

  900p costs nothing measurable in game speed or fps; the phone ran a little warmer in one of the two 900p runs. 900p
  stays the default. The launcher's game resolution has a **Native** choice now (render scale 0: no cap; Kailil, to
  try in a full spectated game unfolded, 2184x1968, 3.6x today's 1198x1080). Found on the way: `phone-bench.ps1`
  read the display scale before the new build's one-time switch to 100% ran and put the old 150 back after each run,
  so Kailil's phone drew 1680x720 folded from 09:29 until it was set to 100% by hand at ~12:30. Frame generation: Lossless Scaling's (LSFG) runs on Android
  as an overlay app over any game (LSFG-Android, Adreno 7xx and newer) with the player's own copy of Lossless Scaling;
  not built in (the shaders are Lossless Scaling's, lsfg-vk is now no-derivatives licensed, and late games have no GPU
  to spare), a player can try it over the app as it is.

## Overnight: delivery and the spectator tools' cost (2026-10-28, from 00:30)
Kailil, going to bed: "start an endless task hardening and bug fixing and optimizign what we just buit especially so
its not adding a large performance overhead. and overhaul this entire project so that it will make it easy to deliver
this as a deliverable to the devs and anyone else who wants to download and play BAR on github", and the effort and
time logged from now on. The backlog is [DELIVERY.md](DELIVERY.md); the log [WORKLOG.md](WORKLOG.md)
(`tools/worklog.py`).
- **What the spectator widget costs**, measured with `tools/spectate-test.ps1 -Cost` (the widget's call-ins timed in
  a 10-minute-old 8v8 replay on the laptop, 1,560 units, the garbage collector stopped while measuring so every KB
  allocated counts). Before / after, per frame:

  | | before | after |
  |---|---|---|
  | not in use (every player outside spectating) | 0.017 ms, 0 KB | 0.014 ms, 0 KB |
  | the bar up | 0.43 ms, 54 KB | 0.064 ms, 4 KB |
  | following a unit, the bar up | 0.61 ms, 75 KB | 0.095 ms, 7 KB |
  | a group, the bar up | 0.60 ms, 75 KB | 0.105 ms, 8 KB |
  | 1st person, the bar up | 0.59 ms, 76 KB | 0.104 ms, 6 KB |
  | 1st person, the bar closed (the usual state) | not measured | 0.032 ms, 0 KB |

  The cost was the bar: BAR's FlowUI elements, drawn directly, allocate about 7 KB each, every frame. The bar is now
  drawn into a display list made again only when a button changes (the state looked at four times a second, at once
  after a press). 1st person no longer allocates per frame: the anchor piece is looked up once per unit (the engine's
  piece map is a new table at every call), the settings and the camera state go into the same tables every frame.
  `tools/spectate-test.ps1`: all pass; the bar draws as before (screenshot).
- **On the phone** (Kailil at ~01:10: "if the phone tests are usefull you can conduct them tonight ... as long as i dont
  need to interact"): the hail-mary session's online-safe batch ran 00:58-02:25 (36 hot runs; branch
  `research/hail-mary` ca05b0d, its `docs/research-hail-mary.md`): everything flat except `WorkerThreadCount` 7-8,
  about +7% game speed at equal CPU clocks in single runs. Tonight's build installed 02:27; a replay smoke run
  (5:00-7:00 of an 8v8) kept x1.00 at ~30 fps up to 905 units, the spectate widget loaded without errors.
- **Worker threads: 4 stays.** Three alternating pairs, hot, uncapped, BAR's benchmark scenario (`phone-bench.ps1
  -Settings @{ WorkerThreadCount = 4|7 }`): Sim 29.72 / 29.26 / 29.44 ms and x0.72 each with 4; 28.46 / 29.35 / 29.20
  ms and x0.74 / 0.72 / 0.72 with 7; Draw a little higher with 7 (29.0 against 27.5 ms). With 7 workers Samsung capped
  the CPUs lower (prime core down to 1401 MHz against 1689, the others 1363 against 1555-1785): the gain at equal
  clocks goes into heat, and on a hot phone the game runs no faster.

## Keyboard shortcuts kept out of the game (2026-10-27 evening)
Kailil asked for mouse and keyboard over Bluetooth or a USB-C dock "and i want android to not hijack its inputs and
listen for shortcuts and other things". A first build (b148e59, installed 21:01) also captured the mouse and sent keys
as scancodes; then Kailil: "mouse and keyboard support works perfectly already. but i just want to make sure the
android built in keyboard bindings and shortcuts dont listen in on the bar session". The mouse and key handling went
back to Termux:X11's (no mouse had been used with that build: launcher.log listed no input device), and only the
shortcut part stayed (HANDOFF.md "Keyboard shortcuts"). What was found on the way:
- **Android 16.1 has keyboard capture for apps.** Moonlight's commit ddb674a ("Add support for Android 16.1 keyboard
  capture") calls `WindowManager.LayoutParams.setKeyboardCaptureEnabled(true)` with the permission
  `android.permission.CAPTURE_KEYBOARD`. On the Fold7 (Android 17, One UI 9.0): `dumpsys package permission` shows it
  `prot=normal`; its `/system/framework/framework.jar` has `setKeyboardCaptureEnabled`, `hasKeyboardCapture` and
  `INPUT_FEATURE_CAPTURE_KEYBOARD`, and Samsung's `requestMetaKeyEvent`. No documentation of which shortcuts it covers
  was found (AOSP's KeyGestureController, read in full, does not mention it: it consumes Alt+Tab, Meta, Ctrl+Space,
  the Recents and screenshot keys before dispatch). Kailil's check on the phone decides whether the accessibility
  fallback is needed there.
- Soft keyboard apps see hardware keys before the app unless the focused view takes them pre-IME; Termux:X11 does
  that only with its "hardware keyboard scancodes workaround" off; otherwise a keyboard app's own shortcuts (Samsung
  Keyboard's language switch) can act on keys meant for BAR.
- Noted from the mouse work, not changed (the mouse works for Kailil): Recoil's middle-click scroll puts SDL in
  relative mode (`CMouseHandler::HideMouse`), which on X11 reads XInput2 raw events, and lorie queues Android's
  absolute pointer positions with `POINTER_NORAW` (cmdentrypoint.cpp): that scroll mode may not move with a mouse.
  Termux:X11 sends 100 wheel units a click where lorie divides by 120. A mouse's right button arrives as
  `BUTTON_SECONDARY` on stock Android; some older Samsung, Huawei and Xiaomi builds sent it as Back (SDL bug 3227),
  which Termux:X11 maps back to the right button.

## Spectating: one player's units, forgiving taps, sentries, a bar beside the small list (2026-10-27 midnight)
Kailil, after playing it on the inner screen: the open player list covered the bar ("should we keep the player list
small when I tap it ... tapping it just spawns the touch ui buttons?"); arrows only over the spectated player's units
and sentries; a tap on another player's unit spectates that player; double tap more forgiving, hopping between units
in 1st person, the bar coming up with it; sentries' gun barrels; Table "eye in sky"; a unit that dies hands over to
its player's nearest unit; every view editable in the tuner; wildlife never followed.
- While spectating by touch BAR's list stays small; a tap on it (or a double tap that follows a unit) brings up the bar
  for 7 s (`bardroid_players.lua` barWanted); the bar is laid out left of the list.
- A tap picks the unit under the finger or the nearest on screen within 70 px; a double tap counts within 0.55 s and
  90 px, or on the same unit.
- Armed buildings are followable; 1st person rides their barrel (barrel, sleeve, gun, turret...) and turns with its
  aim.
- **Ecostats stayed on**: BAR saves widget names that are Lua identifiers as plain keys (`Ecostats = 164,`); the
  launch script added `["Ecostats"] = 0,` before it and Lua kept the later one. `widget_order` sets both forms now.

## Following that sticks, camera presets, 1st person and its tuner (2026-10-27 late)
Kailil: the arrows "just do the closest unit to the center of the screen"; following should "stick no matter what i do
unless I deliberately move my camera away from the unit a far distance" (pan offsets, zoom, tilt and rotate while
following; offsets carry to the next unit); in follow mode camera presets in place of the players (first person, over
the shoulder, tabletop, close, mid) with Save; group following "never jerky"; volume up broke following.
- The camera's target is the followed point plus an offset; each frame the fingers' moves since the camera was last
  placed go into the offset (pinch and twist as well). Letting go: the offset past 1,500 elmos or twice the camera's
  distance (a flick's glide). Presets "unit"-framed turn with the unit's facing (ry = atan2(dx, -dz): the camera looks
  along (sin ry, -cos ry), Camera.cpp).
- Group: members picked twice a second (at most 40, nearest the centre), their centre taken every frame, the camera on
  a critically damped spring (0.9 s): no jumps when the centre does. ~40 position reads a frame.
- 1st person is the engine's first-person camera (mode 0: an eye position, a direction, its FOV; the eye stays 5 elmos
  above the ground), riding a piece of the unit (per unit type, else the first of head, turret, torso, body, base) with
  its own smoothing; a drag or flick lasting past 0.35 s leaves it. The Spring camera stops at BAR's minimum camera
  height (CamSpringMinZoomDistance, 300): close presets lower it for the session only (the config overlay).
- `tools/fp-tuner.ps1` (laptop): the same widget riding a unit in a replay, a mouse panel for anchor, facing, offsets,
  pitch, yaw, FOV and both smoothings; Save writes `bardroid_fp.lua`, to be baked into `bardroid_spectate.lua` FP.
- Keys from the phone's volume buttons, media keys or anything that is not an alphabetic keyboard no longer count as
  keyboard use (the touch tools stepped aside and following ended); following now also goes on under a mouse or
  keyboard.

## Spectating by touch (2026-10-27 night)
Kailil: "a touch focused spectator only setup ... cycling through players to switch player cam to, blocking the bottom
left hand ui from popping up ... camera tools that follow a unit or group of units ... double tap a unit to follow
them"; then "the touch UI to follow players be hidden and only popup when I touch player list", the player's name on
the button in the list's order, and BAR's top-right Ecostats hidden. `bardroid_spectate.lua` acts only while
spectating with fingers: the app reports the input in use ("src touch|mouse|keyboard|pad" in the touch log, at most every
2 s while in use, so a game started since learns it; `RtsTouch.source`, `GameActivity`). BAR's player camera is its
Lockcamera widget (`WG.lockcamera.SetPlayerID`, what its player list uses). Taps on the map are taken (nothing
selected); anything selected otherwise is dropped a frame later, not from SelectionChanged: a selection replaced there
is never told to the widgets after it (BAR's build menu kept showing a builder's options). Following moves the
camera's target only (pinch and twist keep working). `tools/spectate-test.ps1` checks it in a replay (23 checks; the
replay must start playing: one of the laptop's older replays stayed at frame -1, so pass one with `-Replay`).
Ecostats is off in every game (`launch-bar.sh`).

## Benchmarks on the hot phone; online-safe changes only (2026-10-27 evening)
Kailil: "we MUST have online play enabled. so only do online safe adjustments." Online games need BAR's official
engine binary and BAR's own game archive, so the hail-mary research's engine builds, overlay games and modrule
changes are out; what is left are client-side settings, local widgets and what runs around the unchanged engine.
Runs back to back, throttled (thermal status 2, skin ~42 °C, CPU caps 1.40 / 1.36 GHz), the controller game:
- **Worker threads: keep 4.** `WorkerThreadCount` 4: Sim 28.96 / 31.21 ms, game speed x0.72 / x0.70; 2: Sim 31.48 /
  32.14 ms, x0.67 / x0.68 (alternated). The main thread is 87-94% of a core, each worker ~16-22%.
- **Where the Lua time goes on the phone** (BAR's profilers, `phone-bench.ps1 -Profile widgets|gadgets`; they cost
  time themselves): LuaUI 11.1% of the running time and 812 kB/s of garbage, of which Reclaim Field Highlight 3.1% and
  477 kB/s, v0.8.5's Controller Camera Test 1.1% and 217 kB/s (singleplayer only), BAR's Info 0.3%, Notifications
  0.2%. LuaRules 20.2%: synced 12.0% (Unit Explosion Spawner 0.88, Juno Damage 0.83, Paralyze Damage Handler 0.71,
  Explosion_lights 0.70 and 410 kB/s, Watereffects 0.51, EMP Lightning 0.50), unsynced 8.1% (CUS GL4 2.67, Fire GL4
  1.67 and 219 kB/s, Beam Laser GL4 0.89, Fire & Smoke GL4 0.71, Widget Events 0.60). Gadgets are BAR's game: not
  changeable for online play.
- **Reclaim Field Highlight off** (Kailil: "Turn Reclaim Field Highlight off on the phone"; launch-bar.sh
  `widget_order`, a local widget: online-safe). Benchmarks from this build on run without it (a lower baseline).
- BAR's developer tools stay off in the controller game on the phone: infolog shows the empty files in their place
  (the two widgets "Failed to load ... (no GetInfo() call)", the gadget loaded with nothing in it).
- `phone-bench.ps1` waited 12 minutes and parsed nothing when the app put a full `launcher.log` aside as
  `launcher.old.log` during a run (`Log.rotateIfBig`): it reads the run's lines from both files now, from the phone's
  own clock at the run's start.

## Benchmarks: where a big battle's time goes (2026-10-27 afternoon)
Kailil: "make optimizations and run benchmarks over and over"; the game should be GPU-bound, and the sim made cheaper
without editing the engine. BAR's own "Benchmark BAR" scenario (650 Grunts against 650 Pawns on Starwatcher 1.0,
~1,300 units fighting for 2000 frames; `luarules/gadgets/dbg_benchmark.lua` prints Sim/Draw/Update ms per frame)
now runs unattended on the phone: launcher "Benchmark" or `am start ... --es start bench` (launch-bar.sh MODE=bench,
`bardroid_bench.lua` unpauses BAR's paused scenario start and quits after the results), `tools/phone-bench.ps1` runs
it with the clocks every 5 s (`tools/phone-clocks.sh`) and the busiest threads, into `build\phone-bench.csv`.
- **CPU-bound, not GPU-bound.** Folded, uncapped: 100% resolution Sim 21.4-26.5, Draw 10.7-14.2, Update 6.5-8.4 ms
  per frame, ~17-24 fps; 70% resolution the same (Sim 22.9). GPU 56-90% busy. The game itself fell behind: x0.74-0.95
  of real time (simulated frames per second of the main thread's time).
- **Heat sets the clock.** Within ~20 s of a start Samsung caps both CPU clusters at ~2.0 GHz (of 3.53 / 4.47) once
  the AP sensor reaches ~43 °C, at thermal status 0; at status 2 (skin ~42 °C, the state a late game plays in) 1.69 /
  1.40 GHz and the GPU 443-607 MHz. Run to run the numbers swing ±10% with the heat, so Kailil's rule (big unit counts
  come 10+ minutes in, on a hot phone): measure throttled, back to back; `phone-bench.ps1` warms the phone up (thermal
  status ≥ 1, skin ≥ 40 °C) with unrecorded runs first.
- **Android Game Mode does nothing here.** The app declared a game (`appCategory="game"`, `game_mode_config.xml`)
  and Game Mode "performance" vs "standard", alternating, throttled: x0.74 / x0.79 against x0.77 / x0.77. Reverted
  (a game also gets Samsung's Game Booster panel, which could take touches).
- **Threads** (~70 s in, throttled): the engine's main thread 88% of a core (the limit), its 3 workers ~60% together,
  OpenAL's mixer 10% plus Android's audioserver 7%, the GPU driver's submit thread 10%, the X server ~6%.
- **On the laptop** (`tools/profile-benchmark.ps1`: the phone's game, widget orders and user widgets, BAR's widget
  profiler module, every unsynced gadget callin timed, the engine's timers): Sim 15.1 ms per frame (the throttled
  phone ~1.7x that, its Draw ~4x). Of the main thread: Sim 51%, unsynced Lua 21% (widgets ~111-119 ms/s, unsynced
  gadgets 73-134 ms/s), Draw 13%; synced Lua callins are ~10% of Sim, so the simulation is the engine's C++ (not
  changeable without a different engine build; the hail-mary research session, branch `research/hail-mary`, tries
  that). Costliest: Reclaim Field Highlight 18-21 ms/s and half of all Lua garbage (0.6 MB/s; it tracks every wreck
  even when it shows nothing), API Unit Tracker 11, Health Bars 6, v0.8.5's camera widget 5.5-6.5 (+0.3 MB/s
  garbage, singleplayer only); gadgets: Fire GL4 21-40 (wreck fires, new in BAR since May), Widget Events 13 (unit
  deaths to widgets), Fire & Smoke GL4 10-19, Beam Laser GL4 8. Laptop A/B timings are too noisy for small changes
  (Draw 4.4-9.2 ms between identical runs): judge by the profilers' own numbers, and on the phone.
- **The laptop checks drew through ReShade.** Kailil's BAR install has ReShade beside `spring.exe` (an `opengl32.dll`
  proxy with DLSS add-ons; found by the hail-mary session): every laptop check drew through it (likely part of that
  Draw spread, and in `ui-screenshot.ps1`'s pictures) and wrote ReShade's logs into BAR's install. The laptop tools
  start the engine from `build\engine\<engine>` now (`tools/toolchain.ps1` Get-EngineDir: the engine's files copied,
  its folders linked, ReShade's left out; BAR's install unchanged).
- **Fixed: BAR's developer tools ran in every singleplayer game.** BAR turns on its developer mode for a game whose
  version holds `$VERSION` (`luarules/gadgets.lua`), and v0.8.5 plays as that game: the engine shader reloader read
  every engine shader every 10 s in one frame, the widget and gadget reloaders re-read every widget and gadget file
  when the pointer came back into the window (each read a trapped system call under proot), plus test helpers.
  `tools/build-gamepad-game.py` (DEV_TOOLS_OFF) now ships an empty file for each, as BAR's own file is outside its
  developer game (Kailil, 2026-10-26: "we can get rid of the debug stuff"). Online games never had them.
- **Fixed: the app's info panel** printed its whole text afresh every frame (4 ms/s on the laptop with the pointer on
  a unit, 51 kB/s garbage); it is recorded once per change now (a display list, rebuilt at most 4 times a second).
- Our touch widget costs ~0.08 ms per frame (its functions timed; the widget profiler's 0.2 includes its own hooks).
- `tools/touch-widget-test.ps1` failed once (the finger drag 528 elmos off; the next runs passed): on a slow run BAR's
  own camera move to the start position came during the drag case. Its cases now wait until nothing else moves the
  camera (`settle`: a case that returns false runs again 20 frames later).
- Benchmark-only engine settings: `phone-bench.ps1 -Settings @{ Key = value }` (launch-bar.sh
  `.bardroid-bench-settings`); BAR's `springsettings.cfg` as it was goes back after the run and at the next start.

## Overnight hardening and after (2026-10-26 night to 2026-10-27; the overnight part was not checked on the phone by a person)
Found in the phone's logs and code and fixed, each installed on the phone:
- **BAR's settings did not survive a restart**: `Installer.writeGameFiles` rewrote `springsettings.cfg` from the
  template at every start (BAR keeps sound volumes and many options there, and its migration counter, so BAR also
  re-ran its first-start migrations every time). Now the file is kept and completed (`Installer.ALWAYS`). The
  launcher's "UI scale" and "Shadows" controls are gone (launch-bar.sh owns both now).
- BAR refuses `/option` from user widgets: the lights' screen-space shadows go off through `BYAR.lua` instead.
- `widget_order` broke on names with "/" ("Keybind/Mouse Info").
- The lobby wrote `CamMode = 1` at every game start: singleplayer had the overhead camera (no finger twist or tilt).
- The updater would have rolled BAR back after any crash in the first 120 s of an update (a save loading is one):
  now only when no game frame ran.
- Engine log copies were never deleted (now the newest 20); `files/container.sh` broke after every app update.
- The touch widget rewrote VSync settings at every 60/120 Hz switch (pointless since the pace library); gone, and
  VSync is off in the phone settings.
- `/proc/cpuinfo` had no CPU name for the engine: the lobby's analytics threw at every start, BAR's system info
  took "11102MB RAM" for the CPU. The container now gets a `model name` line.
- The interface scale ignores the floating window (no reload when the app goes to the background).
- `[perf]` logs memory now (Android reported low memory all through an 8v8).
- Later that night, from reading the code: a pad that reports its D-pad as keys lost a held direction at every stick
  move; Stop left the audio pump on the FIFO (the next game's sound split between two readers); springsettings.cfg
  is written atomically now that it holds the player's settings; an error in `bardroid_touch.lua` no longer removes
  it for the rest of the game (pcall); a full launcher.log becomes launcher.old.log instead of being deleted; a
  download whose `.part` was already whole (HTTP 416) or a damaged engine/Mesa archive no longer blocks the install
  or update for good.
- A finger drag on BAR's top bar (the share and conversion sliders) or in an open BAR window (the settings and their
  sliders) panned the map underneath: they answer no `IsAbove`. The touch widget now counts the top bar
  (`WG.topbar.GetPosition`) and any open window (`WG.<window>.isvisible`) as interface. Checked in a real skirmish on
  the laptop (`tools/touch-widget-test.ps1`: the old widget fails the top bar and settings cases, the new one passes).
- The lobby bridge sends the replays' winners (Won/Lost in the Replays tab), checked against BAR's own launcher cache.
- **New: the engine stops drawing while nobody sees the game** (phone locked, another app in front; not the floating
  window). It already does so when its window is hidden (as minimized on a PC: two frames a minute, sound muted), but
  without a window manager nothing hid it, so a locked phone kept drawing 30 fps. GameActivity keeps
  `/tmp/bardroid-hidden` while stopped; `libbardroid_pace.so` hands the engine SDL2's HIDDEN/SHOWN window events.
  Checked on the phone with its SDL2 (`tools/pace-test.ps1`), not yet in a game: lock the phone mid-game, unlock,
  the picture and sound come back at once ("game screen hidden/shown" in launcher.log). Off: `export
  BARDROID_HIDDEN_PAUSE=0` in `files/bar/dev-env.sh`.
- launch-bar.sh as it is now, dry-run on the phone (in the container, on copies of Kailil's BYAR.lua, IGL_data.lua,
  IGL_order.lua and springsettings.cfg, a stub engine): no layer miss; it sets the Spring camera (Kailil's pick and the
  default he wants, `CamMode = 2`; springsettings had CamMode 3, the lobby's copy 1), GroundDetail 200 → 60, the VSync keys the old touch widget left (VSync 2, VSyncGame 1)
  off, MSAA/features, Snow/SSAO/Keys/Changes off, the Build menu, the lobby's panels and 120%; a second run changes
  nothing. (The container's `/opt/bardroid` copy is refreshed only when a game starts.)
- The engine update path (never run on the phone: BAR has been on 2026.07.04 all along) checked with BAR's test engine
  2026.09.01 under a scratch name: its arm64 archive downloads, the container step extracts it, `spring --version`
  runs, and it still knows every springsettings key of ours. Removed again. When BAR's launcher config moves
  `manual-linux` to it, the phone follows at the next start.
- BAR's interface at the Fold's layouts, rendered on the laptop (`tools/ui-screenshot.ps1`, screenshots in
  `build/ui-screenshot/`): the inner screen's top bar fits at 1.3 with the phone layer (BAR's own Changes/Keys ran
  into the wind/tidal counters); the cover screen at 2.0 fits (the Build menu pages its two rows). **Open, Kailil's
  call:** on the inner screen the player list (bottom right) covers the order menu's last column (Move, Reclaim,
  Place Blueprint): BAR sizes the order menu by 1/aspect ratio, so on a near-square screen the info panel and order
  menu take 89% of the width. The player list at 75% (`AdvPlayersList.customScale`) uncovers most of it
  (`inner-phone-1.3-list075.png`); moving the order menu off the bottom does nothing there.
- The last 8v8's late slowdown (29.6 → 19.6 fps as it grew to ~1300 units) is the load, not BAR's presets: Kailil
  switched to "medium" and back to "lowest" mid-game and it stayed at ~19 fps as the game got busier. The `[perf]`
  lines of those minutes: GPU 90-93% busy at its thermal cap (525-607 MHz). Next lead for big late games.
- Tests that run on the laptop, all in `tools/laptop-tests.ps1` (~5 min, all PASS): Downloader, the springsettings
  merge (`SettingsMerge`, with Kailil's file: 147 of BAR's keys kept), the updater's rollback decision, the lobby bridge
  against the real lobby, the touch widget in BAR's game and the controller game. `tools/pace-test.ps1` checks the
  pace library on the phone.
- Morning of 2026-10-26, from Kailil's tests: (1) **map-edge drags** felt jarring: off the map the finger's point fell
  on a stand-in plane whose height does not match the terrain at the edge (a jump when crossing it) and near the
  horizon a few pixels are miles. Now a drag from off the map is measured in the middle of the screen, which the
  engine keeps on the map, and the last 400 elmos before the edge blend from finger to centre (Kailil's rule); a
  pending move against the edge clamp is dropped (no dead zone when dragging back). touch-widget-test has an edge case
  (old widget 0.67 of the right distance, new 1.00). (2) **Late-game LOD test**: `UnitIconFadeStart/Vanish = 1` in
  `PHONE_GFX` (BAR's "Unit icon distance" slider at its minimum; BAR forces `UnitIconsAsUI`, so a unit is an icon
  whenever its model would look smaller than the icon): only close units are drawn as models. BAR has no "N units"
  limit, and unit animation runs in the synced simulation for every unit. Kailil to judge in a late game. (3) **The
  floating window** draws at 15 fps (`/tmp/bardroid-floating`, pace library); its resolution already drops with the
  window (584x530). (4) The lobby's split panels: "Always One" (panel_layout 3), Kailil's correction.
- Later that morning: (5) **a touch in the void** (off the map, over the sky) selected empty space and threw the
  camera. The touch widget now answers 2 there (`bardroid_hover.txt`); `RtsTouch` ignores such a finger: no click,
  right-click or box select, the pointer goes to the middle of the screen and a drag pans from there
  (`startPanFromMap`). (6) **Queued buildings far away**: BAR's Show Builder Queue draws every queued building on the
  map every frame (a thousand queued wind turbines across the map, a tilted camera). Off; the app's
  `bardroid_queue.lua` draws them from BAR's own builder queue API and shape drawer only within 2000 elmos of where
  the camera looks (at most 400). (7) **The buttons under the minimap** come from BAR's Picture-in-Picture Minimap
  (its hover button bar ignores its own "no buttons" setting, and a finger always puts the pointer there): off, the
  classic Minimap instead. touch-widget-test runs with the phone's widget orders and checks the void answer, a void
  drag, the queue near and far, and the minimap answer.
- **GPU cuts for late games** (Kailil: "All four"; the GPU is the limit there, 90-93% busy at its thermal cap): (1)
  unfolded, the X screen has about the folded pixel count, ~1152x1044 instead of 1456x1312 (patch 0006,
  `LorieView.maxScaledViewPixels`, set by `GameActivity.MAX_SCREEN_PIXELS` = the cover screen's 2520x1080; the
  "scaled" display treats a bigger screen as one of that many pixels); (2) BAR's lights (Deferred rendering GL4) off;
  (3) scorch marks (Decals GL4), the shadow plates under units and wrecks (Ground AO Plates GL4, … Features GL4) and
  BAR's grass (Map Grass GL4) off; (4) the animated order lines (Commands FX) off. Kailil to compare fps in a late game.
  The pixel cap checked in the emulator with the inner screen's size (`adb shell wm size 2184x1968`, display prefs
  "scaled" 150% for the test, restored after): X screen 1152x1044, interface scale 1.3, the lobby fills the screen,
  a tap lands where it should.
- **The laptop's memory and the emulator:** the engine takes 7.2 GB resident in the emulator (plus 3.0 GB in its virgl
  server) for a plain skirmish. With Kailil's `llama-server` (USAJOBS Autopilot's model, 8 GB) running, a 12 GB
  emulator left the laptop at 0.7 GB free: the game ran at x0.1 and 0 fps (paging), and at 10 GB Android's low-memory
  killer took the app (and the lobby's unsaved login) while loading a big online game. Emulator games need that
  model server stopped (Kailil's call) or a smaller guest and small games.
- **Catch-up when joining a running game** (Kailil: a 40 min game "crawls at a 1-2x catch up speed"). The phone's
  logs of that join (cover screen, the cuts above on): game speed x4 at 845 units falling to x1.6 at 3400 units by
  minute 25, 9-21 pictures a second all along, GPU 50-86% busy, thermal status 2-3 with the CPUs capped at 1.2-2.0
  GHz (of 3.5/4.5) and ~1 GB of memory free. The engine's catch-up loop (Recoil `rts/Net/NetCommands.cpp`
  `GetNetMessageProcessingTimeLimit`) simulates for `(1 - MinSimDrawBalance) / MinSimDrawBalance` times the last
  picture's cost (at most `1000 / MinDrawFPS` ms) between pictures, so drawing gets 15%. First try (0c3a2a7):
  MinSimDrawBalance 0.02 / MinDrawFPS 1 in the config overlay while far behind. Kailil: "still slow"; its join
  (15:23, phone at thermal status 3-4, CPUs capped at 960-1017 MHz, GPU at its 160 MHz floor 99% busy) still drew
  15-26 pictures a second, x2.1-2.5. Not the network: the join's replay holds 5-6.5 KB of game messages per
  game-second (`tools/demo-rate.py <replay.sdfz>`; msg 50 = Lua messages about half), which the server's default
  64 KiB/s link (`LinkOutgoingBandwidth`) sends at 10-13x. Now (catch-up mode 2): more than 30 s behind (not in
  replays) `bardroid_touch.lua` writes `LuaUI/Config/bardroid_catchup.txt` ("<frame> <server frame> <speed>", from
  `GameFrame` about once a second: Update stops with the drawing); `GameActivity` polls it twice a second, shows
  "Catching up 12:30 of 41:10 x2.5" over the game and keeps `/tmp/bardroid-catchup`, which `libbardroid_pace.so`
  treats like the hidden flag (SDL HIDDEN: no drawing, a 10 ms sleep per loop pass, sound muted). The overlay
  settings stay (each stretch of simulation ~50x the last picture's cost). A file older than 10 s counts as caught
  up; GameService and the widget's Initialize remove leftovers. `[bardroid-catchup]` lines every 30 s also count
  pauses over 50 ms between simulated frames: few = the CPU is the limit; many = waiting for data.
  `bardroid_catchup = 0` in springsettings turns it off. `tools/catchup-test.ps1` (~6 min): a headless host plays
  BARb vs BARb on 127.0.0.1, a windowed spectator joins twice (mode off, on); it checks the widget's side (the
  engine on Windows has no pace library). `tools/pace-test.ps1` checks the catch-up flag on the phone.
  Kailil's next join (15:50, 6a1160c) started the mode only at 11:20 game time: GameProgress reaches a late joiner
  behind the whole backlog. Since 6bb52ae the game's own pace starts it (faster than 1.5x its speed for 2 s, until
  the first GameProgress). That join's numbers, drawing off, phone at thermal status 2 (CPUs capped at ~1.4 GHz of
  3.5/4.5 the whole time, GPU down from ~55% to 3-15% busy, 2 °C cooler): x2.0 at 2,400 units, x1.6-1.9 at
  3,000-3,400, x1.2-1.5 at 4,000-4,500, x0.9-1.0 past 5,000, x0.6-0.7 at 6,000-6,800 (it stayed 9 min behind: the
  phone cannot run such a game at 1x at all). Frames there take over 50 ms each: the CPU is the limit.
  **Catch-up on the laptop's emulator, end to end** (Kailil logged in there for online tests, but the lobby lost the
  saved login when Android's low-memory killer took the app while loading a big game in a 10 GB guest; 12 GB is
  the AVD's size): `tools/catchup-test.ps1 -HostOnly -AIs 4 -FastMinutes 20 -Engine recoil_2026.07.04 -Game "Beyond
  All Reason test-31723-95ab750"` hosts a 2v2 BARb game on the laptop, fast-forwarded (the host widget
  `tools/catchup-test/bardroid_host_speed.lua` sends speedup/slowdown), then held at 1x; the emulator app joins it as
  the spectator "Phone" through a temporary `files/bar/dev-env.sh` that copies `join.txt` (HostIP 10.0.2.2, port
  8452) over skirmish.txt before PLAY VS AI (remove both afterwards). Seen: the overlay "Catching up 0:50 of 27:18
  x3.6" over the last picture, the engine not drawing. The emulator's network (SLIRP UDP) stalls ~1 s at a time, so
  its catch-up speed says nothing about the phone's. The emulator build now ships the x86_64 pace library
  (`libbardroid_pace-x86_64.so`, no frame cap, `BARDROID_PRESENT_FENCE=0`) for the hidden window.
  A game the phone cannot run at its own speed never catches up: no ground gained in 60 s, the mode ends (it draws
  again, "not gaining" in the log) and tries again 5 min later, twice as long after each further give-up
  (`tools/catchup-test.ps1 -HostSpeed 4 -BurnMs 10 -Modes 1`: a host that stays fast, a deliberately slow spectator).
- **Where a big game's CPU goes** (`tools/profile-big-game.ps1`: a BARb game fast-forwarded, BAR's widget profiler at
  1x with the phone's widget orders, the engine's timers via `/debuginfo profiling`; `-ProfileFastAtMinute` measures
  at 10x, i.e. per simulated frame; `-Functions` times one widget's callins). 6 BARb, 753 units, laptop: all widgets
  1.45 ms/frame at 1x; the engine's totals over the run (mostly at 10x) Sim 89 s, unsynced Lua callins 50 s (widgets
  and the game's unsynced gadgets), drawing 29 s, synced Lua 11 s. Found and fixed: our own touch widget was the
  costliest widget (0.14 ms/frame: a file open and a view ray every frame; now 0.035 ms Update); Jammed Units
  Highlight (a red tint on units in jammer cover, every unit checked every 6 simulated frames) costs the most per
  simulated frame (13.8 ms/s at 10x): off on the phone, with the full-screen Contrast Adaptive Sharpen pass. Other
  big ones, all gameplay information, left on (Kailil's call): Defense Range GL4 (5 ms/s at 1x), Top Bar, AdvPlayersList,
  Sensor Ranges Jammer Preview, Ecostats, Metalspots, BuildETA. `[perf]` now finds the engine (its process is
  `recoil-main`, the memory column was always "?").
- **More worker threads do not speed up the simulation** (a headless 6-BARb host at max speed, `catchup-test.ps1
  -HostOnly -Workers 4|7`): at 680-700 units x14.3-15.1 with 4 workers, x13.6 with 7. The app's `WorkerThreadCount =
  4` stays (fewer busy cores, less heat). Load-time pathing setup ("PFS", 4.1 s of the phone's ~45 s load) is the
  only place that uses them much. Phone load after the game data: map 7 s, map tiles 4 s, projectile textures 4 s,
  radar icons 4 s, PFS 4 s, LuaRules 8 s.
- **Second optimisation search (2026-10-26 evening, Kailil away).** The phone's own infolog (`logs/catchup3/infolog2.txt`)
  shows what it runs: BAR's Lowest preset (Kailil's: `AdvMapShading = 0`, `Water = 0`, `MaxNanoParticles = 0`, GUI
  Shader off), 225 widgets, 204 unsynced gadgets; Outline Shader GL4 removes itself there. Found, from Recoil's source
  (2026.07.04 = the phone's engine): BAR forces `AllowDeferredMapRendering`/`AllowDeferredModelRendering = 1`
  (`luaintro/springconfig.lua`), so every frame the engine (1) clears the map's G-buffer, six screen-sized targets, which
  with advanced map shading off is all it ever does to it (`SMFGroundDrawer::DrawDeferredPass`), and (2) draws every
  tree, rock and unit model a second time into the model G-buffer (`ModelDrawer::Draw` → `LuaObjectDrawer::
  DrawDeferredPass`, CUS GL4's deferred shaders), for readers that are all off on the phone (lights, SSAO, bloom,
  distortion, outlines) except shields (units touching them) and the radar/jammer placement previews.
  `bardroid_touch.lua` now switches the map pass off while `AdvMapShading` is 0 (`Spring.SetDrawGroundDeferred`,
  checked every 60 drawn frames) and the features' model pass off for good (`Spring.SetDrawModelsDeferred(true,
  false)`: units stay, their pass clears the buffer every frame, so nothing stale is left), from the 3rd drawn frame
  (both buffers hold a cleared picture by then; one that is not drawn is not resized either), restored in Shutdown.
  And BAR's Fog Diagonal Lines GL4 reads the ground from that map buffer: with it only cleared its full-screen pass
  discards every pixel, so `launch-bar.sh` turns it off while the lobby's (`IGL_data.lua` game_settings) or the
  engine's `AdvMapShading` is 0 (marker `.bardroid-fog-lines-off`; back to BAR's default at 1). No visible change
  expected; the GPU saving is unmeasured (the laptop's RTX says nothing about a tiler): check late-game fps on the
  phone. `[bardroid-touch] map G-buffer pass off` / `trees and rocks drawn once` in infolog.
  Measured on the laptop (`tools/profile-big-game.ps1 -Gadgets`, new: `tools/profile/dbg_bardroid_gadget_profile.lua`
  times every unsynced gadget callin; 8 BARb, 989 units at 30 min): unsynced gadgets 6 ms/s at 1x, 0.19 ms per
  simulated frame (Beam Laser GL4 0.074 of it, its GameFramePost scan; CUS GL4 1.2 ms/s; Team stats 0.5 ms/s); all
  widgets ~12 ms/s plus BAR test's dev-only Engine Shader Auto Reloader (5.7 ms/s, not in the release the phone runs).
  Lua is ~2% of the frame there: the phone's late game is the GPU, catch-up the simulation (Sim 110 s of the run).
  Also: the pad thread (`ControllerBridge`) slept 16 ms in a loop with no pad; it now waits out the 100 ms heartbeat
  and wakes on pad input. Not changed, for the record: `UseLuaMemPools = 0` comes from the lobby's own settings;
  `MaxSounds` is reset to 128 by BAR's options; BAR's GPU Profiler needs `gl.QueryCounter`, in no released engine yet.
  The laptop ran at ~6 fps the whole evening (also a 2-unit skirmish): its idle power state, not the game.
- **Kailil back, evening of 2026-10-26** (build 09e6e74 on the phone): a 16-17 min game caught up in 164 s (x6.1 on
  average, 0:21 → 17:07), then 29-30 fps with 2,500-3,900 units (dips to 16-20 for a few seconds). Asked for and
  done: the catch-up screen is black (the progress over a full-screen black view; the last picture stood still behind
  a 75% black box before); tilt is forgiving (`RtsTouch.twoFingerKind`: both fingers moving up or down together,
  without pinch or twist, however they sit; the slower finger gets 3 slops to follow; a second finger within 250 ms
  of the first is one two-finger gesture even if the first already slid; the tilt counts from where the fingers came
  down); new gestures (RtsTouch → "act <name>" lines → `bardroid_touch.lua` ACTIONS, checked by
  `tools/touch-widget-test.ps1`): triple tap = the double tap's types on the whole map (`select
  AllMap+_InPrevSel+_ClearSelection_SelectAll+`), two fingers held 450 ms (buzz) then swiped: up select all / down
  deselect / left stop / right fight (armed), three-finger swipe: up overview / down back / left-right previous-next
  idle builder (own mobile builders without orders, camera to it). Stop and fight go through
  `Spring.SetActiveCommand` (BAR's order buttons do the same; `SendCommands("stop")` reaches no order). Three-finger
  tap still toggles the keyboard (Kailil: keep it, but as a small floating keyboard in the bottom left: that is
  Samsung Keyboard's Floating mode, the user's setting; LorieView already asks for no full-screen editor).
  **Chat** (not changed yet, Kailil's call): BAR's chat box runs from the top bar's left edge to 74% of the width;
  each line has a game-time column and a name column as wide as the longest player name in the game, so on the inner
  screen at 1.3 the text wraps in ~120 px (`tools/ui-screenshot.ps1 -Screen inner -Scale 1 -Chat -PlayerName
  LongPlayerName_2026`, new). BAR's only setting is the font size (`fontsizeMult`, slider 0.92-1.12; 0.6 and 0.5
  tried: ~170-200 px of text). So the app has its own chat display, `bardroid_chat.lua` (Kailil approved the
  screenshots, installed 23:15): BAR's lines hidden (`WG.chat.setHide(true)`; its typing box, sounds and ignore list
  stay; its history on typing off), the lines BAR parsed come through `WG.chat.addChatProcessor`; names at the box's
  left edge in team colour, broken every 10 characters, the text filling the rest (BAR's box: top bar's left edge to
  74%), 75% of BAR's font size, 8 rows (14 while typing), 40 s per line; paused / left / lagging console lines from
  AddConsoleLine. Lost: tapping a map-marker line, emoji images, the lines from before a LuaUI reload (fold/unfold).
  In the touch test (a said line arrives); `launch-bar.sh` reports its errors. In the controller game v0.8.5 clears
  an armed command, so the fight gesture does not stay armed there (the test notes it).
- **2026-10-27, after a full 30-min game spectated** (Kailil: performance "really good", catch-up "worked well"):
  - **No ship wakes** (Kailil: "hideous on the lowest graphics settings"; his screenshot 23:55 showed grey smoke trails
    over basic water). They are BAR's `waterwake-*` CEGs (CBitmapMuzzleFlame, texture `wakegrey`) that ship scripts
    emit every few frames (`emit-sfx 1024+1`), and the Wade Effects gadget for wading units: synced, game content, no
    switch. But the engine loads projectile textures by path raw-first (`CBitmap::Load` → `CFileHandler`, default
    `SPRING_VFS_RAW_FIRST`): `Installer.writeNoWakes` writes a transparent 8x8 TGA of our own to
    `files/bar/bitmaps/projectiletextures/wakegrey.tga` and the wakes are invisible (drawing only: sync and online
    unaffected; the particles are still made and drawn, so no fps to gain). Seen on the laptop:
    `tools/ui-screenshot.ps1 -Screen cover -Scale 0.6 -Ships [-NoWakes]` (cheats, six armpship moving east).
  - **Lobby for fingers** (`LuaMenu/Widgets/bardroid_lobby_touch.lua`, Chobby loads local widgets with its
    `["Chili lobby"].loadLocalWidgets` in `IGL_data.lua`, which `launch-bar.sh` sets): ahead of Chili's input widget it
    holds back a press on a list: a drag (14 px) scrolls the list with the finger and glides after a flick, a tap is
    replayed to Chili on release; a tap on a server row (Chobby's `battleButton`, tooltip `battle_tooltip_<id>`) shows
    Chobby's own server tooltip (`WG.TooltipHandler.TooltipOverride`) and a bar Close / Previous / Next / Join; a second
    tap on the same row joins (its OnClick). Sliders, text boxes and scroll bars go to Chili as before.
    `tools/lobby-touch-test.ps1` (real lobby, no login: a fake list of servers and plain rows) is in laptop-tests.
    Chili hands out controls wrapped: compare what they show, not the tables.
  - **The unit info panel's text** (bottom left; "too large and jumbled") is BAR's Info widget: its text size comes from
    the interface scale (2.0 cover / 1.3 inner) but the panel is made narrower on wide screens, and the text column
    starts 18% in while the unit picture is 4.4 text heights wide: at these scales the stats run under the picture and
    off the bottom. No setting or WG API for it. Kailil chose our own panel: `bardroid_info.lua` (launch-bar.sh turns
    BAR's "Info" off) takes the same rectangle (BAR's build/order/grid menus hard-code it), shows BAR's numbers (its
    refreshUnitInfo/drawUnitInfo stat logic ported: DPS min-max with its special cases, EMP, shields, ranges, XP),
    picks the largest text size at which name, description, health bar and stats fit, and lets stats below the
    picture use the full width. Several units: their types in a grid with counts (tap = keep only that type, long
    press = drop it); tap the picture = camera to the unit. It provides BAR's `WG.info` API (build bar, PIP, idle
    builders, options ask it) and does what BAR's widget does to the engine: `tooltip 0`,
    `Spring.SetDrawSelectionInfo(false)` (else the engine's "Selected units N" text shows); it stands down if BAR's
    Info runs anyway. `tools/ui-screenshot.ps1 -BarDroidInfo [-Select] [-NoInfo]`; the touch test checks it.
- `[bardroid-perf]` counts drawn frames now (the world pass), not Update calls, which go on while nothing is drawn;
  `[perf]` says when the game screen is hidden. `widget_order` only writes into BYAR.lua's top-level order table and
  reports a miss if an order did not land.
Found, not ours: BAR's save-load crash also happens on Windows (upstream; draft report in `docs/upstream/`). The lobby
bridge stays off by default (launcher setting) until Kailil has tried it in the phone's lobby; it passed against the
real lobby on the laptop (Next steps). Verified on the laptop engine: the per-screen interface scale (one reload, no
loop), the touch camera in BAR's game and the controller game, and the touch widget's cost (none measurable).

## Phone session (2026-10-25, 17:00–20:00): first runs on the Fold7

Results on the Galaxy Z Fold7 (SM-F966N, SM8750 / Adreno 830, Android 17, 11.4 GB RAM; inner display 2184×1968 at
up to 120 Hz, cover 1080×2520 at 60 Hz):
- **Flicker** (frames shown before the GPU finished them): lfdevs' Mesa before 27.0.0-devel-20261025 lacks the KGSL
  present-wait fence. `Prefs.mesaUrl` is now that build; `Installer.mesaOutdated()` reinstalls Mesa when the saved
  URL is older (Play runs the install first). Kailil: "flicker is solved fully".
- **14–15 fps → ~30 fps**: Termux's proot puts `ioctl` in its seccomp filter with an exit stop on Android, so every
  KGSL GPU-driver ioctl cost two ptrace stops (18,600 proot wake-ups/s, libproot 48% CPU). `tools/build-proot.py`
  builds proot (termux/proot `b27d81a`, sha256-pinned) with the NDK and patches `syscall/seccomp.c` so `ioctl` traps
  only for the requests proot handles (SIOCGIFINDEX, TCSETSF, TCGETS2/TCSETS*2, FICLONE). Checked on the phone and the
  emulator with a perl loop: 0 of 200 `TCGETS` ioctls stop, 50 of 50 `TCSETSF` still do, futex untouched. The
  loader is built like Termux's (`-Ttext=<LOADER_ADDRESS>,--rosegment`, same segment layout). `fetch-prebuilts.py`
  no longer writes proot.
- **Audio gaps**: the chain was engine → SDL → PulseAudio `module-pipe-sink` → FIFO → `AudioTrack`. AudioFlinger
  showed 0 underruns with ~380 ms queued, so the holes were already in the stream: whenever SDL's audio callback was
  late, PulseAudio rendered silence. Now `UseSDLAudio = 0` and OpenAL Soft's **wave writer** writes straight into the
  FIFO (`/root/.alsoftrc`: `drivers = wave`, 48 kHz stereo int16); its mixer thread is paced by the clock and catches
  up after a stall. `AudioPump` parses the WAV header and starts the track with 200 ms queued (also less latency than
  the ~700 ms before). PulseAudio is no longer started. Kailil: "sound is perfect".
- **Lobby black screen**: Chobby needs `chobby_config.json` (BAR's launcher writes it from its config's
  `json_files`: server4.beyondallreason.info:8200, game `byar`); without it Chobby finds no game config and shuts
  down. `launch-bar.sh` writes it for lobby mode. On the phone Kailil logged in, browsed servers and spectated a
  multiplayer game.
- Frame cap: `VSync = VSyncGame × VSyncFraction` like BAR's options (BAR rewrites `VSync`); the app asks for a 60 Hz
  display mode and the widget picks the swap interval from the real refresh rate (30 fps default, 60 experimental).
- Fold/unfold: the activity is not recreated and the X screen follows the view. There is no window manager, so
  `patches/0003-lorie-fit-windows-on-resize.patch` makes the X server resize mapped top-level windows at the origin
  to the new screen size itself (in `lorieRRScreenSetSize`): works in the lobby, while a game loads (Flex/tent mode
  first hands the app part of the inner screen, then all of it) and in game. The patch also wraps `ConfigNotify`:
  when a client resizes such a window to anything but the screen size, a work proc fits it again. Needed because
  SDL keeps the display bounds it saw at startup and the engine clamps every window-attribute update to them
  (`GetWindowPosSizeBounded`): started unfolded, the cover screen's 1680x720 became 1456x720. For the same reason the
  widget must never call `Spring.SetWindowGeometry` (it did as a fallback and kept re-clamping). Each X screen size
  the app sees is logged (`[display]` in launcher.log). Tested on the emulator with `adb shell wm size` (lobby, three
  resizes while loading, in game); the ConfigNotify rule only on the phone (Kailil). Its first version called
  present's `ConfigNotify` without unwrapping, so present's own unwrap/rewrap dropped ours after one call (found with
  the `screen`/`fit window` lines lorie logs to logcat, tag LorieNative). The phone's logcat buffer is set to 5 MB
  (`adb logcat -G 16M`; the app floods it otherwise). Last piece: Chobby's LuaMenu widget "Resolution limiter" shrank
  the window to SDL's stale screen size on every ViewResize and toggled fullscreen, fighting the fit twice a second
  (black flicker); `launch-bar.sh` sets it to 0 in `LuaMenu/Config/IGL_order.lua`. **Kailil (21:50): folding and
  unfolding works perfectly** (lobby, either starting screen).
  Landscape only, both sides (`sensorLandscape`). Samsung's "continue apps on cover screen" must allow BAR Droid.
- RAM: a match uses ~5–6 GB (1.1 GB resident + swap at the time); the launcher no longer says 12 GB.
- **Memory (spectated 8v8, one snapshot each):** `recoil-main` held 5.2 GB anonymous (3.4 GB swapped), GPU (kgsl)
  only 341 MB; Android killed the app in the background for `LOW_MEMORY` (`dumpsys activity exit-info`).
  `VFSCacheArchiveFiles = 0` (the engine kept every file read from the pool archive in memory, decompressed) and
  `TextureMemPoolSize = 0` (512 MB image pool): 5.6 → 4.5 GB, phone free 1.1 → 1.5 GB. The rest is engine data
  kept on purpose (largest anonymous region 652 MB, nearly all swapped; QTPFS 234 MB; mimalloc already purges
  freed memory). Leaving the game now opens a floating window (Termux:X11 `PIP` pref, set once in
  `BarApp.applyDisplayDefaults`): visible, so Android almost never kills it. Background survival not yet confirmed.
- **Black squares for units zoomed out** (strategic icons): the engine builds its icon atlas (and the projectile
  atlas the Perlin smoke draws into) as `GL::Texture2D(..., wantCompress = true)` and renders into it through an FBO.
  With `CompressTextures = 1` Freedreno picks a compressed format, which is not color-renderable:
  `FBO-TEXTURE-RENDER-ATLAS: None/Unsupported textures/buffers attached`, `atlasRendered=0`, every icon black (also
  `FBO-PROJECTILE-DRAWER-PERLIN`). The emulator's virgl does not compress, so it never showed there. Now
  `CompressTextures = 0` always (the app setting is gone). Confirmed on the phone: no atlas warning in the last eight
  engine runs (2026-10-26). (The engine drops the key when it saves springsettings.cfg, 0 being its default.)
- Lobby: `launch-bar.sh` turns Chobby's `drawAtFullSpeed` on once (`LuaMenu/Config/IGL_data.lua`, marker
  `.bardroid-lobby-fullspeed`); the player can turn it off again in the lobby's Settings.
- Mouse: `HardwareCursor = 1`, so lorie draws the pointer on every display frame instead of the engine once per game
  frame (verified: with spring SIGSTOPped the pointer still follows). The lobby is slow by design on top of the
  phone's speed: Chobby's `gfx_limit_idle_fps` runs it at VSync 2 (30 fps) while active and VSync 4 (15 fps) after
  1–2 s idle (and it measures time with `os.clock()`, CPU time); its Settings checkbox `drawFullSpeed` makes the
  active rate 60.

**Touch controls** (`RtsTouch`, on by default; off = Termux:X11's touch modes), Kailil's spec of 19:30:
tap = left click (double tap = double click); one-finger drag = pan (grab, with a fling); tap-then-drag = box select;
long press = right button (lift = order, drag = formation); two fingers = pan + pinch zoom (mouse wheel at the centre)
+ twist rotate; two fingers moving up/down side by side = tilt; two-finger tap = right click; three-finger tap =
keyboard; Back = Escape. The app talks to `bardroid_touch.lua` through files under `LuaUI/Config` (BAR's sandbox gives
user widgets no sockets). A one-finger drag that starts on the interface is a mouse drag instead: the widget is the
last `IsAbove` in line, so it hears about the pointer only where no widget claimed it, and answers through
`bardroid_hover.txt` (+ `Spring.IsAboveMiniMap`). That catches the minimap and modal windows (options); BAR's top bar,
build and order menus do not implement `IsAbove`, so a drag there pans (taps are fine). `CamSpringLockCardinalDirections
= 0`, or small twist steps never leave north. Tested on the emulator with injected multitouch (pan, twist, tilt);
not on the phone yet.

Next: Kailil checks audio, gestures, lobby and fold/unfold on the phone; then RAM, BAR's UI on the near-square inner
display (ui_scale), and touch-only play (later, Kailil).

## Afternoon session (2026-10-25, 12:40–16:45): units, speed, Share logs

**Invisible units (would have hit phones too).** Our presets set `MaxParticles` 2000 (phones) / 600 (emulator).
BAR's `gfx_fire_smoke_gl4` sizes a VBO at `(MaxParticles - 7000) * 2 + 10000`; at ≤ 0 `LuaVBOImpl::Define` throws while
unsynced LuaRules loads, the whole unsynced LuaRules dies and CUS GL4 (BAR's unit renderer) with it: no units, no
command panel. Now `MaxParticles = 10000` (bottom of BAR's own slider); the emulator no longer overrides particles,
LOD or icon distance. Commander, build menu, unit info and orders all work (`..\logs\emulator-units-ingame.png`).

**Frame rate, measured the same way each time** (developer widget `tools/dev/bardroid_fps.lua`, copied to the
device's `files/bar/LuaUI/Widgets/`, logs `[bardroid-fps]` to infolog every 10 s; not shipped by the app). All with the laptop in Modern Standby unless noted:
| Change | Result |
| --- | --- |
| Before | 2 fps, sim x0.5–0.7, skirmish load 3:21 |
| proot without `--kernel-release` (its kompat extension traps every `futex()`; spring's render thread spent ~45% in ptrace stops) | load 1:46, sim x1.00 |
| Emulator `hw.gltransport=asg` (shared-memory ring instead of the goldfish kernel pipe; 87% of the virgl server's CPU was in `goldfish_pipe_read_write`) | 7 fps (X server 45%→11% CPU), load 1:13 |
| virgl: no timer-query cap, deferred query polls, no per-command `glGetError` | ~8–9 fps; **~20 fps with the laptop awake** |
Not worth it (measured): `mesa_glthread=true` (≤5%), half the pixels (`displayScale` 270: +18%), ANGLE
`asyncCommandQueue` (not in this ANGLE build). Where the time goes now: spring's render thread waits in
`glXSwapBuffers` for virgl to finish and read back the frame; virgl waits on the host (ANGLE checks a fence after
every submit = a host round trip; vrend's fallback blit for the engine's per-frame Z24S8→Z32 depth copy switches GL
contexts twice per frame, each a flush + submit). Ideas left: avoid that context switch (an experiment storing
Z32_UNORM as DEPTH24_STENCIL8 showed no clear gain while throttled; not kept), fewer ANGLE submits.
**Host power matters**: Windows Modern Standby (lid/screen off) throttles the laptop to ~40% of the awake frame rate.
Check `Get-WinEvent` Kernel-Power 506/507 before comparing numbers.

Experiment, not usable yet: the emulator's own GLES driver instead of ANGLE (developer switch file
`files/bar/dev-virgl-native`; build-virgl.py adds a pbuffer fallback for EGL without surfaceless contexts). It lacks
geometry shaders and `OES_texture_3D` framebuffer attachments; libepoxy aborts the server on
`glFramebufferTexture3DOES` while BAR loads.

Developer hooks (none created by the app): `files/bar/dev-env.sh` (sourced by `launch-bar.sh`),
`files/bar/dev-springsettings.cfg` (appended to springsettings), `files/bar/dev-virgl-native`, `LuaUI/Widgets/*.lua`
in `files/bar`. Profiling: `adb root` works on the google_apis image; NDK `simpleperf` (pushed to `/data/local/tmp`)
with `--call-graph dwarf --trace-offcpu` shows wall time; the unstripped virgl library for symbols is
`build/virgl/build-x86_64/src/libvirglrenderer.so`.

Memory: once, the low-memory killer took the whole app ~40 s into a match (guest swap full). Later runs held at
~0.7 GB available. The laptop has 31.6 GB; other programs (llama-server ~14 GB, a Windows BAR) leave little room.

## Emulator-first session (2026-10-25, 08:50–11:10)

Why x86_64: Google's emulator cannot run ARM64 Android images on an Intel host, and on x86_64 images with ARM
translation proot cannot trace translated processes (it hangs). So the emulator build is x86_64 end to end:
- `tools/fetch-prebuilts.py <abi>`: Termux proot/talloc/shmem + Termux's ANGLE + Debian static busybox for any ABI,
  patched like the original arm64 set (`libtalloc.so`, `RUNPATH=$ORIGIN`).
- `-PbardroidAbi=x86_64|arm64-v8a` (root `build.gradle`) picks the ABI; `BuildConfig.TARGET_ABI` → `Prefs.EMULATOR_BUILD`
  switches the Debian image (dist-amd64), engine (`recoil_2026.07.04_amd64-linux.7z`), skips the Adreno Mesa tarball
  and the ARM64 AI stub, and selects the GPU path.

Fixed on the way (all would also have hit phones):
- **App processes see `/data/user/0` as a symlink to `/data/data`** (Android 11+ data isolation). proot canonicalizes
  its rootfs, so the hard-link symlinks written by `--link2symlink` (from `PROOT_L2S_DIR`) were unresolvable inside the
  app: Perl and every hard-linked file vanished, apt's maintainer scripts failed. `Paths` now uses canonical paths;
  the rootfs completion marker is versioned so older trees are rebuilt.
- proot's `.l2s` directory must exist before extraction, busybox tar aborts at the first error (a partial tree was
  accepted before), Debian's static busybox has no `--exclude`: rootfs extraction is now strict (exit code + loader
  check + completion marker; an incomplete tree is wiped).
- **Stop did not stop the game**: proot ignores SIGTERM (what `Process.destroy*` sends on Android) and leaves its
  tracees running when SIGKILLed. Stop now SIGKILLs every other process of the app's UID.
- `AudioPump` keeps draining the FIFO when no `AudioTrack` can be created (an emulator without audio).

GPU path (virpipe): `VirglServer` starts the virgl server next to the X server; Mesa inside the container uses
`GALLIUM_DRIVER=virpipe` + `MESA_GL_VERSION_OVERRIDE=4.3COMPAT` (virgl on GLES only advertises 2.1 compat; the host
has the GL4.3 features BAR uses). The engine reports `GL 4.3 (Compatibility Profile)`, renderer
`virgl (ANGLE (NVIDIA, Vulkan 1.3.0 (NVIDIA GeForce RTX ...)))`, "GL4 support: 1". Findings:
- The emulator's own EGL lacks `EGL_KHR_surfaceless_context`, so the server uses ANGLE (GLES on Vulkan, Termux's
  `angle-android`, bundled) via `--angle-vulkan` + `BARDROID_ANGLE_DIR`.
- **Termux's virglrenderer-android always decompresses DXT on the server and re-uploads with `glTexImage2D` into
  immutable compressed storage → GL_INVALID_OPERATION → every DXT texture black** (BAR's map tiles, minimap, unit
  skins). `tools/build-virgl.py` rebuilds virglrenderer 1.3.0 + libepoxy 1.5.10 with Termux's patches (pinned commit)
  and decompresses only when the host lacks S3TC, also recognizing ANGLE's per-format DXT extension names (upstream
  does not). Verified with a DXT1 test texture (`[255,0,0]` instead of `[0,0,0]`) and a textured map in game.
  Worth reporting to Termux.
- CPU rendering (llvmpipe, checkbox "Render on the CPU") works too: x0.70 speed, ~1 fps.

Emulator caveats
- (11:10) 3–4 fps, units invisible: both fixed in the afternoon session above.
- A host crash (PC restart) corrupted the emulator's data disk (kernel panic, ext4). Recovery: start the emulator once
  with `-wipe-data` (`Run in Emulator.bat -wipe-data`), then Install / Update again (~10 min, 4 GB download).
- Developer hook: long-press **GL check** = display + GPU server stay up for an hour without the game, for testing GL
  inside the container (`tools\container-shell.bat`).

## Laptop session, night (2026-10-25, 02:40–03:50) — history

Toolchain + build
- Nothing was installed on the laptop. Added `toolchain\env.bat` (process-local: JAVA_HOME, ANDROID_HOME,
  GRADLE_USER_HOME, ANDROID_EMULATOR_HOME, HOME/USERPROFILE/APPDATA/TEMP all redirected into `toolchain\`),
  `toolchain\install-toolchain.ps1` and the top-level `.bat` launchers. Google replaced `sdkmanager` with the
  "Android CLI" (`android.exe sdk install ndk/29.0.14206865 ...`, package names use `/`); the installer uses it with
  `--no-metrics`. The Android SDK terms were accepted on Kailil's go-ahead.
- termux-x11's native build assumes a Linux host. `patches/0002-lorie-windows-host-build.patch` (applied by
  `tools/fetch-termux-x11.*`; every change is inside `if(CMAKE_HOST_WIN32)` or host-neutral) adds: `git apply` instead
  of bash+GNU patch (with `recipes/fix-patch-headers.py` normalizing patches git rejects, and `--unidiff-zero`),
  host gcc from `$LORIE_HOST_CC` for `makekeys`, copies instead of symlinks (no Developer Mode needed), and a
  case-insensitivity fix (the NDK's `<xlocale.h>` resolved to X11's `Xlocale.h`).
- Native libs: AGP now strips `libXlorie.so` (21 MB → 3.5 MB; `ndkVersion` pinned in `app/build.gradle`); the prebuilt
  proot/talloc/busybox are excluded from stripping so they stay byte-identical to the Termux/Debian builds.

Bugs found and fixed
- **Any app update broke every container step**: `files/bin/proot` symlinks pointed into the old native-lib dir
  (Android moves it on each update). proot/busybox now run in place; assets and container scripts are refreshed
  before every install and launch. (Found on the emulator.)
- **The X server could never start**: `XServer` cleared the environment, so `app_process` had no BOOTCLASSPATH /
  ANDROID_ART_ROOT and died silently. Now inherits the app's environment. (Found on the emulator.)
- **Stop left proot running** (installer children were untracked): `Proc.killAll()` on Stop; an interrupted wait
  kills its child.
- busybox `tar` would have refused to run (bound as `/.bardroid-busybox`, "applet not found"); now `/busybox-bardroid`.
- Debian's `/usr/share/X11/xkb` is a symlink; the host-side X server now resolves symlinks inside the rootfs.
- Crashes on Android 9–12: `InputStream.readAllBytes()` (API 33) and `Build.SOC_MODEL` (API 31).
- `AudioPump.stop()` could leave a thread blocked opening the FIFO (two readers on the next game).
- The game screen stayed open after the engine exited; it now closes and the launcher comes back.
- Termux:X11's activities/receivers were exported (meant for the Termux app, another UID); now non-exported.
- First-run display defaults for a game: full screen, landscape, no extra-keys bar, screen kept on, "simulated
  touchscreen" (tap = click at the finger), X screen scaled to ~720p. All adjustable under Display prefs.

Emulator smoke test (Android 14 x86_64 with ARM translation; `tools\emulator-test.bat`) — passed:
- Launcher UI, device check, settings; specialUse foreground service; notification permission prompt.
- Debian rootfs download + SHA-256; proot starts from the native-lib dir (then stalls: proot cannot ptrace
  ARM-translated processes, an emulator limit).
- **Open risk closed: on Android 14, `app_process` with `CLASSPATH=<our base.apk>` runs `CmdEntryPoint` from our
  APK.** With an emulator-only x86_64 X server, the whole display path works: X server up, socket at the container's
  `/tmp/.X11-unix/X0`, ACTION_START reaches our non-exported receiver, `GameActivity` connects (60 Hz), full-screen X
  root window with the game defaults.
- Gamepad bridge: `BARCTRL1` packets at ~60 Hz on 127.0.0.1:28777; injected gamepad A → button bit 0, then released.
- Stop during install and during play kills X server + proot and closes the display. Audio FIFO is created.
- Not testable there: container (proot), apt, Mesa, engine, GL, audio playback.

Static checks of the container side (scripts kept in the session scratchpad; easy to redo with Python):
- All 37 packages in `setup-container.sh apt` exist in Debian trixie arm64. `p7zip-full` is now a transitional
  package for `7zip` 25.01, which still ships `/usr/bin/7z`.
- Every `DT_NEEDED` of the 9 ELF files in `recoil_2026.07.04_arm64-linux.7z` (spring: SDL2, X11, Xcursor, OpenAL,
  glibc) and of the Mesa tarball's 7 ELF files is provided by the container (base image + dependency closure of the
  apt list = 295 packages).
- The Mesa tarball carries `dri/kgsl_dri.so`, `dri/zink_dri.so`, Turnip (`libvulkan_freedreno.so` + ICD json) and
  `libgallium-26.2.0-devel.so`; it overwrites Debian's Mesa files in place as intended.
- glxinfo, vulkaninfo, pulseaudio (+ module-pipe-sink / module-native-protocol-unix), 7z, ldconfig, fc-cache are all
  in installed packages.

Debugging on the phone: the app writes `files/container.sh` before every install/launch, so
`bar-droid-app\tools\container-shell.bat` gives a root shell in the phone's container (or runs one command:
`container-shell.bat "glxinfo -B"`).
