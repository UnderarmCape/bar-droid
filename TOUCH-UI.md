# BAR Droid — touch controls that play like a phone RTS (design v2, 2026-10-25)

Kailil: "the touch ui system needs a total overhaul and rework, it is far too rudimentary and basic as it stands. It
needs to work like a phone rts." Earlier: "enabled by default ... if keyboard and mouse is used and detected, or if
gamepad is detected and moving anything, then touch screen ui goes away allowing for all the input methods to freely
work together", and "the com build menu needs to be bigger ... easy touch focused options to quickly build a grid or
line or single item ... intuitive and less clicks".

v1 was a column of desktop shortcuts (QUEUE, CTRL, BOX...) on top of BAR's mouse UI. v2 starts from how phone RTS
games are played and uses BAR's desktop panels only where nothing better exists.

## 1. What phone RTS games do, and what we take

| Game (platform) | Pattern | Why it matters for BAR |
| --- | --- | --- |
| Company of Heroes, Rome: Total War, XCOM (Feral's iPad/Android ports of desktop strategy games) | Unit cards at the bottom for the selection; a contextual command bar for the selected units; press-and-hold opens a **radial command menu** at the finger; build ghost placed by dragging, confirmed with a tick | The closest case to BAR: deep desktop games made playable by touch. Cards make selection precise without a mouse; the radial replaces right-click-with-modifiers |
| Rusted Warfare (Android, TA-style RTS) | Tap unit = select, tap ground = move, one finger always pans; big build side panel for the selected builder; "select all army" / "idle builder" buttons; attack-move button | Same genre as BAR (Total Annihilation lineage): proves the economy+army loop works with these few rules |
| Clash of Clans / Boom Beach (mobile base builders) | Pick a building: a **ghost appears on the map with ✓ / ✕ / rotate floating beside it**; drag the ghost to move it; tap elsewhere to move it there; walls chain: after ✓ the next ghost appears next to the last | The standard for precise placement under a finger that hides what it touches; chaining = fewer taps for rows of solars/winds |
| Mindustry (mobile) | Drag to lay a line of blocks; rectangle drag for areas | LINE / GRID for walls, wind farms, solar fields |
| Most mobile games | Two-finger tap = back/cancel; long press = more options; haptic tick on menu choices; nothing important needs precision taps | Small, consistent rules that need no tutorial |

Principles taken from them:
1. **The map is the screen.** One finger drag always moves the camera (with fling), pinch zooms, twist rotates. Panels
   appear only when they have something to do, and step aside for the camera.
2. **Tap is the verb.** Tap a unit to select it, tap anywhere else to give the order that makes sense there
   (move / attack / reclaim / repair / guard). No modifier keys for the common case.
3. **Press and hold for options.** A radial menu at the finger lists only what the selection can do at that spot.
4. **Selection is managed with cards and quick-select buttons**, not with a mouse box (a box is still there).
5. **Placement by ghost + confirm**, rows and grids by dragging, chained placement for repeats.
6. **Big targets** (≥ 9 mm, 12 mm for build icons), sized in millimetres on both screens; text labels on everything.
7. **Feedback:** the armed command is highlighted; haptic tick on radial choices and confirms.
8. **Every input together:** while a mouse, keyboard or gamepad is used, the touch panels hide and BAR's desktop UI
   is there as usual; the next finger touch brings them back.

## 2. Screen layout (landscape; inner 1456×1312 X px ≈ 9.7 px/mm, cover 1680×720 ≈ 11.1 px/mm)

```
┌ minimap (BAR) ─┬──────── BAR top bar (resources, menu buttons) ─────────┬─────────┐
│                │ [1 12] [2 5] [+]          control groups               │ QUEUE   │
├────────────────┘                                                         │ SELECT  │
│ BUILD DRAWER          (camera: the whole screen)                         │ ARMY    │
│ ECON COMBAT UTIL BUILD                                                   │ IDLE    │
│ [icon][icon][icon][icon]          ghost ✓ ↻ ✕   (placement)              │ COM     │
│ [icon][icon][icon][icon]                                                 │ ☰       │
│ [icon][icon][icon][icon]   ┌──────────── ACTION DOCK ───────────────┐    ├─────────┤
│ ONE  LINE  GRID            │ [card 4×tank][card 2×bot][card 1×com] ✕ │    │ BAR     │
│ ROTATE SPACE- SPACE+ ✕     │ MOVE FIGHT ATTACK PATROL STOP REPAIR …  │    │ players │
└────────────────────────────┴────────────────────────────────────────┴────┴─────────┘
```
- **Action dock** (bottom centre, new `bardroid_touch_dock.lua`, drawn over BAR's order menu): with units selected,
  a row of **selection cards** (unit picture, count; tap = keep only that type, long press = drop that type, ✕ =
  deselect) and a **command bar** (the selection's commands as big labelled buttons: MOVE, FIGHT, ATTACK, PATROL,
  STOP, WAIT, GUARD, REPAIR, RECLAIM, RESURRECT, D-GUN, LOAD/UNLOAD..., then state toggles like FIRE/MOVE state,
  ON/OFF, CLOAK, REPEAT showing their current state). With nothing selected it is hidden.
- **Build drawer** (left, `bardroid_touch_build.lua`): the builder's buildings, BAR's categories and grid order,
  12 mm icons, placement mode ONE / LINE / GRID, ROTATE, spacing, CANCEL. A factory shows its units (tap = +1, with
  QUEUE +5, long press = −1).
- **Right rail** (`bardroid_touch_hud.lua`): QUEUE (Shift held, for waypoints and build queues), SELECT (one-finger
  drags draw a selection box), ARMY (all combat units), IDLE (next idle builder, camera follows), COM (commander,
  camera follows), ☰ (pops out CHAT, PAUSE, SETTINGS, CTRL).
- **Control groups** under the top bar: tap = select, tap again = camera to the group, long press = assign, + = new.
- The rail and the dock dock against BAR's top bar and bottom-right panels (`WG.topbar.GetPosition`,
  `WG.advplayerlist_api.GetPosition` ...). On the short cover screen the build drawer covers the minimap.

## 3. Gestures

| Gesture | On the map | On a touch panel |
| --- | --- | --- |
| Tap | own unit: select it (QUEUE: add); with units selected anywhere else: **smart order** (what a right click would do); with a command armed: carry it out; with a building armed (ONE): move the ghost there | press the button |
| Double tap | on a unit: all of its type on screen; with a building armed: place it here | — |
| One-finger drag | pan (fling); command armed: draw it (formation line, area circle); building armed: drag the ghost (ONE), lay a row (LINE), fill a rectangle (GRID); SELECT latched: selection box | drag on a list = scroll |
| Tap, then drag | selection box | — |
| **Press and hold** | **radial menu** at the finger with what the selection can do there (move, fight, patrol, attack, set target, guard, repair, reclaim, resurrect, load...); slide to a choice and lift. Lift without sliding = the right-click order | long press = the button's second action (assign group, drop card, −1 in a factory) |
| Two fingers | pan + pinch zoom + twist rotate; up/down together = tilt | scroll |
| **Two-finger tap** | **cancel**: disarm the command or building; if nothing is armed, deselect | — |
| Three-finger tap | keyboard | — |
| Back | Escape (BAR's menu) | — |

## 4. Placement (ONE mode, the Clash of Clans pattern)

Pick a building in the drawer: the ghost appears at the centre of the screen with **✓ ↻ ✕** beside it.
Drag the ghost (finger lands on or near it) to move it — it floats 1 cm above the finger; tap elsewhere to move it
there; pan with a drag elsewhere (the ghost stays under the screen centre). ✓ places it and puts the next ghost right
next to it (chained placement: four winds = pick, ✓ ✓ ✓ ✓). ↻ rotates, ✕ (or two-finger tap) stops. Double tap = place
there at once. LINE / GRID: drag over the map; the engine lays out and previews the row or the filled rectangle
(Shift / Shift+Alt held by the app). Mex: BAR's own snapping applies (the placement is a real click).

## 5. How it is built (constraints)

- **BAR's user-widget sandbox** (BAR PR #9547; the phone runs `Beyond All Reason test-31723-95ab750` = Release
  2026.10.24-1, read in its `luaui/barwidgets.lua`): our widgets load "from user": no sockets, no `debug.emulate*`
  (no synthetic input from Lua), no RmlUi; files only under `LuaUI/` (write in `LuaUI/Config`, `LuaUI/Widgets`); no
  Enable/DisableWidget, so **BAR's widgets cannot be hidden or replaced** — ours draw over them (low layer) and take
  presses first while fingers are used. Allowed and used: `Spring.SetActiveCommand`, `GetDefaultCommand`,
  `GetActiveCmdDescs`, `SelectUnitArray`, `GetSelectedUnitsSorted`, `SetCameraState`, `SendCommands` (not
  widget/keybind/execute commands), `GiveOrder*` (unless the game turns unit-control widgets off), `WG` (BAR's
  positions, `WG["pregame-build"]`, `WG.SmartSelect_SelectUnits`, `WG.options.toggle`, `WG.fonts`, `WG.FlowUI`), `gl`.
  **Never modify, bundle or re-encode BAR's game content** (CC-BY-NC-ND); unit pictures are drawn from the game
  (`#<unitDefID>` textures).
- **Only the app makes real input.** Lua asks the app (file `LuaUI/Config/bardroid_app.txt`): `mods <shift> <ctrl>
  <alt>` (hold keys: QUEUE, LINE = Shift, GRID = Shift+Alt), `key enter|escape`, `keyboard <0|1>`, `box <0|1>`,
  `click <x> <y>` / `rclick <x> <y>` (a left/right click at an X pixel: the radial's choices and ✓ go through the
  engine like a mouse click, so BAR's own handling — formations, mex snapping, pregame queue — applies), `move <x> <y>`
  (pointer only: the ghost), `buzz` (haptic tick). The app writes `bardroid_touchui.txt`: `1 <X px per mm> <input>`
  (input used last: touch / mouse / keyboard / gamepad).
- **The app's gestures** (`RtsTouch`) send camera and gesture lines to `LuaUI/Config/bardroid_touch.txt`: `pan`,
  `rot`, `tilt`, `zoom`, `box`/`boxend`/`boxcancel`, `cancel` (two-finger tap), `radial`/`radialmove`/`radialup`/
  `radialcancel` (press and hold). It asks the game what is under a touch and what is armed through
  `bardroid_hover.txt` (`x y onInterface armed`, armed 0 none / 1 building / 2 other command).
- **Smart tap**: the last-in-line HUD widget sees a left press only if no BAR widget took it; with units selected and
  nothing armed it arms `Spring.GetDefaultCommand()` and the engine carries it out on release
  (`CGuiHandler::MouseRelease`), then disarms it.
- Widgets: `bardroid_touch.lua` (always: camera, frame cap, hover), and in touch-only mode `bardroid_touch_hud.lua`
  (layer 999999: smart tap, radial, selection box, rail, groups, held keys), `bardroid_touch_dock.lua` and
  `bardroid_touch_build.lua` (layer −10: over BAR's order and build menus, under its windows and chat).

## 6. Stages

1. **v1 (done, tested once):** smart tap, latches, box select, build drawer with ONE/LINE/GRID. Kailil: "not good
   enough", "far too rudimentary".
2. **v2 stage A (eb313c9) — the dock:** selection cards, command bar, quick-select rail with ☰ menu, two-finger tap =
   cancel / deselect.
3. **v2 stage B (815bb6f) — press and hold radial menu** with haptics; orders go straight to the selected units
   (`Spring.GiveOrder`, QUEUE queues), or arm + click where the game forbids widget orders.
4. **v2 stage C — ghost placement:** BUILD / ROTATE / CANCEL beside the ghost, tap to move it, drag it from on top,
   pan under it, chained placement, double tap to build. While a building is armed the app holds Shift (chaining,
   queueing; Shift+Alt in GRID) and knows the mode (`place one|line|grid`).
   None of the v2 stages is tested on the phone yet.
5. Later: health/progress on cards, minimap size per screen, per-screen `ui_scale`, lobby (Chobby) by touch.

## 7. Test plan (phone only, Kailil drives; logs: `files/bar/infolog.txt` `[bardroid-*]`, `files/logs/launcher.log`
`[touchui]`) — see the report for each stage.
