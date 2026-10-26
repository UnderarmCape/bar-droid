# BAR Droid — touch-only controls (design, 2026-10-25)

Goal (Kailil): "eventually ... we will implement touch controls to play the full game touch only". Fingers only: no
mouse, keyboard or gamepad, on the Galaxy Z Fold7 (inner display and cover display). It is a launcher option,
**Touch-only mode**, off by default; with it off the app behaves exactly as before (RtsTouch mouse emulation + camera).

## 1. Constraints that shape the design

- **BAR's user-widget sandbox** (BAR PR #9547, in the game the phone runs: `Beyond All Reason test-31723-95ab750` =
  Release 2026.10.24-1; read in `luaui/barwidgets.lua` of that commit). Our widgets load "from user":
  - no sockets, no `debug.emulate*` (no synthetic mouse or keys from Lua), no RmlUi;
  - files: read anywhere under `LuaUI/`, write only `LuaUI/Config/` and `LuaUI/Widgets/` (not `LuaUI/Config/BYAR.lua`,
    `uikeys.txt`, `keybind_profiles.json`);
  - reduced `widgetHandler`: no Enable/DisableWidget, no FindWidget; **no way to hide or replace BAR's own widgets
    from Lua** (and loose copies of game widgets are ignored). Our widgets go *next to* BAR's, never instead;
  - allowed and used here: `Spring.SetActiveCommand`, `Spring.GetDefaultCommand`, `Spring.GetActiveCommand`,
    `Spring.SelectUnitArray`, `Spring.GiveOrder*` (unless the game sets `allowunitcontrolwidgets` off),
    `Spring.SetCameraState`, `Spring.SendCommands` (all but widget/keybind/`execute`-type commands: `group select 3`,
    `select AllMap+...`, `buildfacing inc`, `pause` pass), `widgetHandler.actionHandler:KeyAction(...)` (runs bound
    LuaUI actions such as `selectcomm focus`, `gridmenu_key 1 1`; BAR PR #9675), the shared `WG` table (BAR's own
    hooks: `WG.topbar.GetPosition`, `WG.advplayerlist_api.GetPosition`, `WG.ordermenu.getPosition`,
    `WG.buildmenu.getSize`, `WG.minimap.setMaxHeight`, `WG.options.toggle`, `WG.fonts.getFont`, `WG.FlowUI.Draw.*`),
    `gl.*` drawing, `IsAbove`/`MousePress` call-ins, `widgetHandler:RegisterModalWindow`, `Pause/Unpause`.
  - **Never modify, bundle or re-encode BAR's game content** (CC-BY-NC-ND). Only our own widgets.
- **Only the app can make real input.** Modifier keys (Shift = queue, Ctrl), Enter (open chat), the soft keyboard
  must come from the app as X events (`LorieView.sendKeyEvent`). The engine reads Shift for queueing, build lines,
  add-to-selection; BAR's chat opens on a real Enter key press.
- Files are the only channel between the app and Lua (as for the touch camera). The game reads them every frame
  (~30 fps); the app reads its file with a `FileObserver` (inotify).

## 2. Architecture

```
                 X events (mouse, keys)                       files under files/bar/LuaUI/Config
 RtsTouch ───────────────────────────────▶ engine ──▶ LuaUI ──▶ bardroid_touch.lua      (camera, hover + command state)
   ▲  │  bardroid_touch.txt  (pan/rot/tilt/zoom) ────────────▶                          
   │  │  bardroid_touchui.txt (mode, px per mm) ──────────────▶ bardroid_touch_hud.lua  (touch HUD, smart tap)
   │  └─ reads bardroid_hover.txt  ◀── "x y onInterface command"
   └──── TouchUiLink reads bardroid_app.txt ◀── "mods 1 0 0" / "key enter" / "keyboard" / "box 1"
```

- `RtsTouch` (app) turns fingers into mouse events and camera lines, as today. In touch-only mode it also asks the
  game what is active (command / build) to decide what a one-finger drag means, and sends pinch zoom as a camera line
  instead of mouse-wheel clicks (latched Shift/Ctrl would otherwise turn the wheel into fast zoom / tilt: the spring
  camera reads `movefast`/`movetilt`).
- `TouchUiLink` (app, new) executes what the HUD asks for: hold or release Shift/Ctrl/Alt in the X server, press a
  key, show the soft keyboard, latch box select. It also writes the touch-UI mode and the X-pixels-per-millimetre of
  the current screen, so the HUD can size buttons in millimetres on either display.
- `bardroid_touch.lua` (existing, always installed) keeps the camera, frame cap and "is the pointer on the interface"
  answer; the answer gains the active-command kind (0 none, 1 build, 2 other).
- `bardroid_touch_hud.lua` (new, installed only in touch-only mode) draws the touch HUD and turns map taps into
  orders ("smart tap", below). Layer 999999: second to last, so it hears a press only when BAR's interface declined
  it, and draws under BAR's windows (options, menus stay on top).

## 3. Gestures

| Gesture | Default (today) | Touch-only mode |
| --- | --- | --- |
| Tap on the interface | left click | left click (BAR's buttons, build menu, order menu, minimap, our HUD) |
| Tap on own unit | left click (select) | select it (with QUEUE latched: add to selection) |
| Tap on map/enemy/wreck, units selected, no command armed | left click (deselects) | **smart tap**: the order a right click would give (move, attack, reclaim, repair, guard, load...) |
| Tap with a command armed (move/attack/patrol/fight/build/...) | left click | left click: carries out the command (QUEUE latched: keeps queueing) |
| Double tap on a unit | double click (all of its type in view) | same |
| One-finger drag on the map | pan (with fling) | pan; **with a command armed: left drag** (formation line for move/fight/patrol, circle for area attack/reclaim/repair, line of buildings with QUEUE); **build armed, QUEUE off: the building ghost follows ~1 cm above the finger, lift places it** |
| One-finger drag, BOX latched | — | box select |
| Tap, then drag | box select | box select |
| Drag starting on the interface | left drag | left drag |
| Long press | right button (lift = order, drag = formation) | same: always "order here" (e.g. repair/guard a friendly unit) |
| Long press on a HUD button | — | secondary action (control group: assign) |
| Two fingers | pan + pinch zoom (wheel) + twist + tilt | same, zoom is smooth (camera line, keeps the point under the fingers) |
| Two fingers on the interface | pan | **scroll** (mouse wheel: lists, chat history, options) |
| Two-finger tap | right click | right click (cancels an armed command) |
| Three-finger tap | keyboard | keyboard |
| Back | Escape | Escape |

## 4. RTS actions by touch

| Action | How |
| --- | --- |
| Select | tap a unit; double tap = all of that type on screen; HUD **ALL** = every mobile combat unit; **IDLE** = next idle builder (camera follows); **COM** = commander (BAR's `selectcomm focus`); **CLEAR** = deselect |
| Box / area select | double-tap-drag, or latch **BOX** and drag; QUEUE latched adds to the selection |
| Move / attack / guard / reclaim / repair (default order) | tap the target (smart tap) or long press |
| Explicit orders (move, attack, patrol, fight, stop, wait, D-gun, area mex, fire/move states...) | BAR's order menu (tap), then tap or drag on the map |
| Build placement | BAR's build menu (tap a category, tap a building), then tap the spot, or drag the ghost and lift; **ROTATE** in the context bar (`buildfacing inc`); **CANCEL** (or two-finger tap / Back) |
| Factory queues | build menu with the factory selected: tap = +1, QUEUE latched = +5, long press = −1 |
| Queueing (Shift) | **QUEUE** latch: real Shift held in the X server while lit. Waypoints, build lines, build queues, add-to-selection all work as with a keyboard |
| Control groups | group row under the top bar: tap = select, tap again = camera to the group, long press = assign the selection, **+** = assign to the first free group |
| Camera | one-finger pan, pinch zoom, twist rotate, two-finger tilt; minimap tap/drag (BAR's minimap) |
| Minimap orders | long press on the minimap = right click = move order there |
| Chat | HUD **CHAT**: releases the latches, presses Enter (BAR opens its chat input) and shows the soft keyboard; Enter on the keyboard sends |
| Menus / settings | HUD **MENU** (`WG.options.toggle`), BAR's top bar buttons (tap), Back = Escape |
| Pause | HUD **PAUSE** (`pause`) |

## 5. BAR widgets: what we rely on, overlay or replace

| BAR widget | Touch-only plan |
| --- | --- |
| Grid menu (build menu), Order menu | kept; tap targets grow with `ui_scale`. They consume their own presses, so smart tap never fires on them |
| Minimap | kept (engine minimap; tap = camera, long press = move order). Later: `WG.minimap.setMaxHeight` for a bigger one |
| Top bar, player list, info, chat | kept; the HUD docks between the top bar (`WG.topbar.GetPosition`) and the player list (`WG.advplayerlist_api.GetPosition`) |
| Unit groups (`gui_unitgroups`) | kept; overlaid by our larger group row |
| Idle builders | kept; HUD **IDLE** does the same with a big target |
| Smart select, selection box | kept; our tap logic runs after them and steps aside for presses they or the engine own |
| Replacing a BAR widget | not possible from a user widget (no DisableWidget). If one ever must go, the app can edit `LuaUI/Config/BYAR.lua` (order 0) before the game starts and restore it afterwards — not needed so far |

## 6. Sizes for a 7–8" foldable

The app writes X pixels per millimetre (`DisplayMetrics` dpi × X-pixels per view pixel) to `bardroid_touchui.txt`:
inner display 1456×1312 X px ≈ 9.7 px/mm, cover display 1680×720 X px ≈ 11.1 px/mm.

- Buttons: 9 mm (≈ 87 px inner, ≈ 100 px cover), never below 7.5 mm; 1.5 mm gaps; labels 2.6 mm. Android's minimum
  touch target is 48 dp ≈ 7.6 mm.
- **Inner display** (near-square, lots of height): one column on the right edge, from under the top bar down to the
  player list: QUEUE, CTRL, BOX, ALL, IDLE, COM, CLEAR, CHAT, PAUSE, MENU (≈ 10 × 10.5 mm = 1015 px of the ~1100 free).
- **Cover display** (wide, 720 px tall): the same buttons in two columns (≈ 500 px of free height = 5 rows).
- Context bar (build / command armed): ROTATE and CANCEL left of the column's bottom, 12 mm wide.
- Group row: under the top bar, right of the minimap; only groups that exist, plus **+**.
- The right edge is the thumb's side when the phone is held in landscape; BAR's own panels sit left and bottom.
- BAR's own UI follows `ui_scale` (launcher setting, 1.4) and the screen height, so on the cover it is ~half the
  physical size of the inner display. Per-screen `ui_scale` on fold/unfold is a later step (see 8), coordinated with
  the fold/unfold work.

## 7. Smart tap (the core of touch-only orders)

In `bardroid_touch_hud.lua`'s `MousePress(x, y, 1)`, reached only when no BAR widget took the press:
1. in game (frame > 0; pregame start boxes and the pregame queue keep plain clicks), not over the minimap,
   no command armed, units selected, Ctrl/Alt not held, and the press is not on a unit we can select;
2. `idx, id = Spring.GetDefaultCommand()` — exactly what a right click would do here (the engine's choice, including
   BAR's `DefaultCommand` call-ins);
3. `Spring.SetActiveCommand(idx, 1, true, false, Spring.GetModKeyState())` and return false: the engine's GUI handler
   then sees a left press with that command armed and carries it out on release (`CGuiHandler::MousePress/
   MouseRelease`, engine 2026.07.04);
4. next frame, if our command is still armed (Shift keeps it), disarm it, so each tap picks its own order like a
   shift-right-click.

## 8. Stages

1. **Done in this session (needs Kailil's test):** design; launcher checkbox; `TouchUiLink`; touch-only gestures in
   `RtsTouch` (command drags, build ghost, scroll on the interface, smooth zoom); HUD column (QUEUE, CTRL, BOX, ALL,
   IDLE, COM, CLEAR, CHAT, PAUSE, MENU), context bar (ROTATE, CANCEL), group row; smart tap.
2. Feel: tune sizes/offsets from Kailil's test; haptics on HUD presses (the HUD would ask the app); a collapse handle.
3. BAR's panels for touch: drags on the build/order menus pan today (they have no `IsAbove`; the hover answer can use
   `WG.ordermenu.getPosition` / `WG.buildmenu.getSize`); per-screen `ui_scale` and a bigger minimap.
4. Lobby (Chobby) by touch: it is a separate Lua UI (LuaMenu) where our widgets do not run; taps work, scrolling needs
   the two-finger scroll outside the game too.
5. Radial build menu at the finger (long press on empty ground with a builder selected) — only if the grid menu
   proves too small.

## 9. Test plan (phone only, Kailil drives)

Launcher: tick **Touch-only mode (experimental)**, Save, Play vs AI. Then:
1. HUD column on the right; on the cover screen two columns. Buttons light up when tapped.
2. Tap the commander (selects), tap ground (walks there), tap a wreck (reclaims), tap an enemy (attacks).
3. QUEUE on: tap three spots (three waypoints); QUEUE off.
4. Build menu: pick a building, drag on the map: ghost above the finger, lift places it. ROTATE before placing.
   QUEUE on + drag: a line of buildings.
5. Order menu: Move, then drag a line on the map (formation). Patrol/Fight the same.
6. Select some units, long press group **+** … then CLEAR, tap the group (selects), tap again (camera goes there).
7. BOX on: drag a box. ALL / IDLE / COM buttons.
8. Two fingers on the options window or chat history: scroll. Pinch: smooth zoom with QUEUE on (no fast zoom).
9. CHAT: keyboard opens, type, Enter sends. PAUSE, MENU.
Logs: `files/bar/infolog.txt` (`[bardroid-hud]`, `[bardroid-touch]`), `files/logs/launcher.log` (`touch`/`touchui`).
