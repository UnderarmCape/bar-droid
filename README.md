# BAR Droid: Beyond All Reason on Android

Play [Beyond All Reason](https://www.beyondallreason.info/) on an Android phone: BAR's own lobby, online games,
skirmish against AI and spectating, at about 30 fps on a Snapdragon 8 Elite phone, with touch controls, gamepads, or a
mouse and keyboard. The app runs BAR's official, unmodified engine, so you play online with everyone else. Nothing of
BAR is in the app: it downloads the engine and the game from BAR's own servers, as BAR's PC launcher does.

**This is a complete way to play BAR on an Android phone, and all you need.** Full games, online or against the AI,
from the lobby to the end. Late games chug in big battles but run well, and you stay caught up with the game. Full
mouse and keyboard support: with a Bluetooth or USB-C mouse and keyboard it plays like BAR on a PC.

It is not a native port: the app runs BAR's official Linux engine for ARM, natively on the phone's CPU and GPU (no
emulation, no translation), inside a small Linux environment the app carries. That is what keeps online play in step
with everyone else's.

BAR Droid is a fan project, not made by the Beyond All Reason team.

**Status: fully playable, handed on.** Its author does not plan to keep developing it: the hope is that BAR's developers and community take it as a stepping stone to an official
BAR for Android. It is 100% vibe coded: an AI assistant (Claude Code) wrote all of its code at the author's
direction ([docs/WORKLOG.md](docs/WORKLOG.md)). Help is wanted most with engine-side performance and touch controls:
[docs/HELP-WANTED.md](docs/HELP-WANTED.md).

## Phones

A Qualcomm Snapdragon phone with an Adreno 7xx/8xx GPU (Snapdragon 8 Gen 2, 8 Gen 3, 8s Gen 3, 8 Elite), 12 GB of
RAM and about 6 GB free. Tested on a Galaxy Z Fold7 (Android 17). 8 GB is not enough: on a Galaxy S23 Ultra (8 GB)
it installs and its graphics work, but Android closes the game while it loads for lack of memory. Phones with Mali,
Xclipse or Tensor GPUs cannot run it (no driver path); the app's device check says so.

## Install

1. Download `bar-droid-phone-<version>.apk` from the [Releases](../../releases) page and open it on the phone (allow
   installing from your browser or file manager when Android asks).
2. Open **Beyond All Reason**, tap **Install / Update**: about 4 GB from BAR's servers, around 10 minutes.
3. Then the lobby (log in with your BAR account), or **Play vs AI**. The app updates BAR at every start, like the PC
   launcher.

## Touch controls

| Gesture | In the game |
|---|---|
| Tap | Click: select, buttons, place a building. Double tap: that unit type on screen; triple: on the whole map (in the controller game: switch the gamepad between v0.8.5 and the app's controls) |
| Drag | Pan the map (a flick glides); on BAR's windows and minimap it drags them instead |
| Tap, then drag | Box select |
| Long press | Right click (move/attack order); keep dragging for a formation |
| Two-finger tap | Right click |
| Two fingers | Move to pan, pinch to zoom, twist to rotate; both up or down together to tilt |
| Two fingers held, then swipe | Up: select all your units; down: deselect; left: stop; right: fight |
| Three-finger tap | Show or hide the keyboard |
| Three-finger swipe | Up: the whole map, down: back; left/right: previous/next idle builder |
| Three fingers held | The layout editor (below) |

In the lobby a drag scrolls lists and a tap on a server shows its details first.

**Building:** pick a building in the build menu; its page strip then shows **ONE · LINE · GRID · BORDER**, and a big
green **PLACE** button with ↻ and ✕ inside covers the order menu. Tap the map to pick the spot (the building shows
there), then PLACE to build it; the building stays picked for the next spot. With LINE, GRID or BORDER, drag on the
map for a row, a filled area or a hollow ring of them (BAR's own line and area building, placed at once). ↻ turns the
building, ✕ (or a long press) puts it away. With ONE, a drag pans the map.

**The layout editor** (three fingers held, or type `/hud` in the chat): every panel shows its outline. Tap one, drag
it to move it, pinch or use the buttons to size it; Done (or three fingers again) closes it. The app's own panels
(chat, unit info, the spectate bar) also take a text size and padding; BAR's minimap and player list take a size. The
build menu is the app's copy of BAR's own Build menu, a 3x3 grid (9 build options a page, the page arrows in a strip
under them), which can be moved and sized (in the controller game, the gamepad's own build menu instead). BAR's top bar, order menu and start countdown can't be moved or sized on their own
(BAR has no setting for them; their size follows the interface scale: 2.0 folded, 1.0 unfolded). Folded and unfolded
each keep their own layout.

**Chat:** Enter (or the keyboard's Enter) opens the typing box at the top of the chat; long messages wrap and get
smaller so the whole message stays in view. Ctrl, Alt or Shift + Enter switch between everyone, allies and
spectators, as in BAR.

**Spectating** (watching a game or a replay, with touch): the player list stays small; tap it to bring up a bar
for a few seconds. On it: the players by name (switch whose camera you follow), the unit nearest the middle of the
screen to follow (or double-tap any unit), a group, and while following, camera presets: 1st person, over the
shoulder, table, close, mid. In 1st person, drag to look around; it turns back to the unit's view by itself.
**Tune** adjusts the camera for the unit type you follow, one setting at a time, and saves it for the other
factions' matching unit too.

## Gamepad, mouse and keyboard

- **Gamepads:** skirmish runs BAR Controller Support (v0.8.5), a full controller interface; in the lobby the pad is a
  mouse. In BAR's own game (online, spectating) the app rebuilds v0.8.5's controls from a mouse and keyboard, which
  every game allows; the pointer stays in the middle of the screen, as v0.8.5's reticle:

  | Pad | In the game |
  |---|---|
  | Left stick | Pan the map under the pointer (LT held: faster) |
  | Right stick | Turn (left/right) and zoom (up/down); with LB held, tilt |
  | A | Select (twice: that type on screen); place a building |
  | A held | Nothing picked: v0.8.5's area select - a circle in the middle selects your units as you pan (RT: added to the selection, buildings too; D-pad: bigger or smaller; B: undo). With an order picked, the left stick moves the pointer instead: an area circle (repair, reclaim), a row of buildings; let go and it glides back to the middle |
  | X | The smart order there (BAR's right click: move, attack, repair, reclaim, guard); held, the left stick draws a path |
  | B | Cancel the order or building picked, else clear the selection |
  | RT / RB held | Queue (Shift) / put the order first in the queue (Space; on the build menu a factory's queue: Alt) |
  | RB | The build menu: the pointer onto its first option and kept on the menu (B, or a quarter second of pushing off it, lets go), the D-pad steps (past the left or right edge, or right from the last option: the page before or after), RB / LB the next / previous page, the option drawn bigger with a gold outline; A picks it (factories: queue one, RT + A five), X takes one off (RT + X five); the pointer glides back to the middle |
  | Back + RB | The order menu, the same way (the pointer at 5/8 speed): A gives the order (one that needs a target: aim it in the middle, A) |
  | D-pad | Right / left: next / previous idle builder; down: the commander; up: a camera bookmark (LT + up: store it) |
  | LB + D-pad | Right / left: next / previous idle unit (not builders); down: all idle units of that type |
  | LB + A / X / Y / B | Fight (or attack the enemy there) / attack / patrol, in the middle; B: stop (twice: repeat; held: wait). With builders, A repair and X reclaim (A on the target) |
  | Start + D-pad | Control groups: up / down picks the group, left tapped recalls it (held: assigns the selection), right: that type joins it from now on; Start + L3 clears it |
  | L3 / R3 | Remove the next / the last queued order; Back + R3: the D-gun (A fires) |
  | Back + Start | A free pointer on the left stick (any of BAR's windows), and back; free before the game starts |
  | A building picked | v0.8.5's placement: A places it, X places it and keeps it, D-pad left/right turns it, up/down spaces a row, Back slows the pan, B puts it away. LB held: a grid - A starts it, the left stick draws it, A places it (X: and keeps the building), B cancels |
  | An area order picked (area mex) | A starts its circle, the left stick draws it, A gives it |

  A lobby can forbid widgets that give units orders (most allow them): there LB + A / X / Y only pick the order (A
  gives it, in the middle) and L3 / R3 do nothing ("NOT IN THIS GAME").
  In the controller game (skirmish), a quick triple tap anywhere switches the pad between v0.8.5 and these controls,
  to compare them ("CONTROLLER MOD: ..."); with these controls the app's 3x3 build menu (and the touch PLACE button)
  takes v0.8.5's build menu's place.
- **Mouse and keyboard** (Bluetooth, or a USB-C dock): full support, as on a PC. While BAR is in front, Android's, One UI's and
  DeX's own keyboard shortcuts go to the game instead: Alt+Tab, the Windows key, Ctrl+Space, the keyboard's language
  switch (launcher setting "Keyboard shortcuts go to the game", on by default). Android keeps the Home, Recents,
  power, volume, brightness and media keys, and the swipe gestures (in the game they take a second swipe). Back is
  Escape in the game.
- Before Android 16.1, Android takes its shortcuts before any app; the optional accessibility service sends them to
  the game: Settings > Accessibility > Installed apps > **Beyond All Reason keyboard shortcuts** > On. It reads keys
  only while the game screen is in front. If Android says the setting is restricted: Settings > Apps > Beyond All
  Reason > ⋮ > Allow restricted settings, then switch it on.

## Good to know

- Big late-game battles chug: the frame rate drops with thousands of units (the phone runs the whole game simulation,
  as a PC does), but the game keeps pace, so you stay caught up (a spectated 8v8 with ~3,600 units ran at x0.97-1.02
  of real time). The frame cap is 30 fps by default (launcher: 30 / 60 / none).
- A match uses about 5–6 GB of memory; close other big apps first.
- Joining a running game catches up first (the screen shows how long it has left).

## Problems

Tap **Share logs** on the launcher screen and attach the zip to an [issue](../../issues), with the phone model and
what happened.

## For developers

[docs/HELP-WANTED.md](docs/HELP-WANTED.md) (what is left and the measurements behind it),
[docs/BUILDING.md](docs/BUILDING.md) (build, checks, releasing), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (how it
works), [CONTRIBUTING.md](CONTRIBUTING.md) (the rules: online play stays BAR's, BAR's content is never bundled),
[CHANGELOG.md](CHANGELOG.md), [docs/HISTORY.md](docs/HISTORY.md) (measurements and decisions) and
[docs/WORKLOG.md](docs/WORKLOG.md) (the effort behind it).

## Licences

The app's own code and widgets: GPL-3.0-or-later ([LICENSE](LICENSE); it embeds Termux:X11's GPL-3 `lorie` module).
Third-party parts are listed in [NOTICE.md](NOTICE.md). BAR's game content (CC BY-NC-ND) is never bundled or
re-encoded: it is downloaded from `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` on the device.
