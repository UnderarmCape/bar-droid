# BAR Droid: Beyond All Reason on Android

Play [Beyond All Reason](https://www.beyondallreason.info/) on an Android phone: BAR's own lobby, online games,
skirmish against AI and spectating, at about 30 fps on a Snapdragon 8 Elite phone, with touch controls, gamepads, or a
mouse and keyboard. The app plays BAR's engine at the version BAR's servers run, so you play online with everyone
else: by default its phone build (below), or BAR's official one. Nothing of BAR's game is in the app: it downloads the
game, its maps and the official engine from BAR's own servers, as BAR's PC launcher does.

**The phone engine.** The app carries a build of BAR's engine (Recoil) made for phones, from the same source as BAR's
plus the project's engine branch: the app's touch and gamepad controls load as part of the game, so a host's "no user
widgets" option no longer turns them off; BAR's Settings laid out for an upright or sideways phone; phone versions of
BAR's costliest interface code and memory settings that let 8 GB phones load big games. Its exact rewrite of the
simulation (about 4-5 % faster game speed) runs in skirmishes and replays; online it stays BAR's stock code until it
has passed many more of BAR's server replays (docs/ENGINE-DEFAULT.md). The launcher's "Phone engine" turns it off: BAR's
official engine then, the controls as user widgets. Its source goes public with the app (NOTICE.md).

**This is a complete way to play BAR on an Android phone, and all you need.** Full games, online or against the AI,
from the lobby to the end. Late games chug in big battles but run well, and you stay caught up with the game. Full
mouse and keyboard support: with a Bluetooth or USB-C mouse and keyboard it plays like BAR on a PC.

It is not a native port: the app runs BAR's Linux engine for ARM, natively on the phone's CPU and GPU (no emulation, no
translation), inside a small Linux environment the app carries. That is what keeps online play in step with everyone
else's.

BAR Droid is a fan project, not made by the Beyond All Reason team.

**Status: fully playable, handed on.** Its author does not plan to keep developing it: the hope is that BAR's developers and community take it as a stepping stone to an official
BAR for Android. It is 100% vibe coded: an AI assistant (Claude Code) wrote all of its code at the author's
direction ([docs/WORKLOG.md](docs/WORKLOG.md)). Help is wanted most with engine-side performance and touch controls:
[docs/HELP-WANTED.md](docs/HELP-WANTED.md).

## Phones

A Qualcomm Snapdragon phone with an Adreno 7xx/8xx GPU (Snapdragon 8 Gen 2, 8 Gen 3, 8s Gen 3, 8 Elite), 12 GB of
RAM and about 6 GB free. Tested on a Galaxy Z Fold7 (Android 17). 8 GB phones get a low-memory mode (plainer unit
shading, no shore foam or ground scorch marks, skirmish on a smaller map until you pick one): on a Galaxy S23 Ultra
(8 GB) BAR's own benchmark battle runs through every time (slowly: about 12 fps), and so do skirmishes on that map; on
a big map about 1 in 3 is closed by Android for lack of memory, so close other apps first. Online games there are
untested. Phones with Mali,
Xclipse or Tensor GPUs cannot run it (no driver path); the app's device check says so.

## Install

1. Download `bar-droid-phone-<version>.apk` from the [Releases](../../releases) page and open it on the phone (allow
   installing from your browser or file manager when Android asks).
2. Open **Beyond All Reason**, tap **Install / Update**: about 4 GB from BAR's servers, around 10 minutes.
3. Then the lobby (log in with your BAR account), or **Play vs AI**. The app updates BAR at every start, like the PC
   launcher; the launcher screen shows the game version the last start played.

## Touch controls

| Gesture | In the game |
|---|---|
| Tap | Click: select, buttons, place a building. Double tap: that unit type on screen; triple: on the whole map |
| Drag | Pan the map (a flick glides); on BAR's minimap and sliders it drags them instead; up or down in BAR's Settings, Statistics and other windows it scrolls them |
| Tap, then drag | Box select |
| Long press | Right click (move/attack order); keep dragging for a path (one unit) or a formation line (more) |
| Two-finger tap | Right click |
| Two fingers | Move to pan, pinch to zoom, twist to rotate; both up or down together to tilt |
| Two fingers held, then swipe | Up: select all your units; down: deselect; left: stop; right: fight |
| Three-finger tap | Speak to chat: "< SPEAK TO ALLIES >" shows in the channel's colour with a pulsing red dot, the phone's speech recognition listens, and what you said is sent as a chat message (in a game to the game's chat only, not the lobby's); nothing said, nothing sent. Meanwhile a sideways swipe (on the pad: D-pad left / right) switches the channel between allies, everyone and spectators, kept for later messages and games (typed ones too). The first time, Android asks for the microphone (not allowed: a note says to allow it in Android's settings, Apps) |
| Three-finger double tap | Show or hide the keyboard |
| Three-finger swipe | Up: the whole map; down: the camera to your commander (if it is dead, to the constructor you selected last); left/right: previous/next idle builder |
| Three fingers held | The layout editor (below) |

In the lobby a drag scrolls lists and a tap on a server shows its details first. A tap on a text box (a chat's,
the server search, the login) brings up Android's keyboard; a long press on a chat's box is speak to chat, the words
into that chat (in a game, a tap on Settings' search field brings it up too). A server whose settings stop your
controls says so when you join it: in red when custom widgets are off (no touch or gamepad controls unless you
spectate), in amber when unit control widgets are off (only first person stops).

**Building:** pick a building in the build menu; its page strip then shows **ONE · LINE · GRID · BORDER**, and a big
green **PLACE** button with ↻ and ✕ inside covers the order menu. Tap the map to pick the spot (the building shows
there), then PLACE to build it: as with a mouse, it takes the place of the builders' orders and the building is let go;
with QUEUE on it joins their queue and stays picked for the next spot. With LINE, GRID or BORDER, drag on the
map for a row, a filled area or a hollow ring of them (BAR's own line and area building, placed at once). ↻ turns the
building, ✕ puts it away (with LINE, GRID or BORDER a long press too).
With ONE a drag does not pan the map: the building follows your finger. Once it waits there, a later drag anywhere
nudges it (half your finger's way), a tap elsewhere moves it there, and a double tap sends it (with none waiting, a
double tap places one there and sends it at once). Hold your finger still on it for a moment (or start a drag on the
waiting building) and "GRID" pops up with a buzz: the drag now draws a grid of them from it; PLACE or a double tap
sends the grid. Two fingers still pan and zoom.

**The layout editor** (three fingers held, or type `/hud` in the chat): every panel shows its outline (none for a
panel the touch dock covers whole; with the dock across the bottom its buttons sit in the game above it). Tap one, drag
it to move it, pinch or use the buttons to size it; Done (or three fingers again) closes it. The app's own panels
(chat, unit info, the spectate bar) also take a text size and padding; BAR's minimap and player list take a size. The
build menu is the app's copy of BAR's own Build menu, a 3x3 grid (9 build options a page, the page arrows in a strip
under them; up to 5 wide on a wide, short screen such as the Fold7 folded), which can be moved and sized; a unit info panel made bigger stops at the order menu, and the build menu keeps clear of it. BAR's top bar, order menu and start countdown can't be moved or sized on their own
(BAR has no setting for them; their size follows the interface scale: 2.0 folded and held sideways, 1.0 folded and
upright and unfolded). Folded and unfolded each keep their own layout.

**Chat:** Enter (or the keyboard's Enter) opens the typing box at the top of the chat; long messages wrap and get
smaller so the whole message stays in view. Ctrl, Alt or Shift + Enter switch between everyone, allies and
spectators, as in BAR. BAR's own messages ("Battle Started", a commander under attack, the tutorial's lines) show in
the chat box too, for 15 seconds (on a phone BAR's own place for them is behind the bottom panels).

**Spectating** (watching a game or a replay, with touch): the player list stays small; tap it to bring up a bar
for a few seconds. On it: the players by name (switch whose camera you follow), the unit nearest the middle of the
screen to follow (or double-tap any unit), a group, and while following, camera presets: 1st person, over the
shoulder, table, close, mid. In 1st person, drag to look around; it turns back to the unit's view by itself.
**Tune** adjusts the camera for the unit type you follow, one setting at a time, and saves it for the other
factions' matching unit too.

**The camera with one finger** (in a game: Settings, Control tab, "Camera with one finger"): the **camera knob**, a
thin ring over the map: hold it and slide up or down to zoom (down closer), sideways to turn; the layout editor (three
fingers held) moves and sizes it. The **edge rails**, with the touch dock up: two thin lines in an L at the map's
bottom corner, each half its side: slide along the upright one to zoom, along the one at the foot to turn. Both light
gold while held; a slow drag makes fine steps, a fast one big ones. Settings there: each on or off, "on the left" for
the left hand, white or the dock's grey, and the sensitivity.

**Playing upright** (launcher setting "Play upright"): hold the phone upright; the game is on top and a touch dock
below it. The dock is a camera pad at rest: drag to pan, double tap and hold then move up or down to zoom (sideways
to turn), triple tap and hold to tilt. The build grid, the orders, QUEUE and INSERT, the buttons with nothing picked (and the
spectator's), metal and energy and the groups row act on the first tap; elsewhere a tap opens its menu for 2.6 seconds (while a building is being placed it stays
open): the build grid on the left, the picked
units' orders on the right (Fight, PRESETS, Patrol first and largest, the D-Gun red; a state's lights as BAR's, red
left, green right; units that build nothing: the orders that would need scrolling go under their types on the left,
the type tiles as tall as Fight, the right side as always),
the selection row as QUEUE and INSERT (both on: Shift and Alt held; off once nothing is picked), and the
metal and energy bars on top. With nothing picked it shows LOCAL UNITS and ALL UNITS (every combat unit on screen,
or all of them, picked and listed by type beside their orders; the list's first tile toggles ALL / MULTI: with MULTI
each type you tap joins the pick), FACTORIES (your next factory
in turn, the camera on each; its build menu comes up in the dock once you stop tapping for 0.75 s), PINGS (LAST PINGS: the camera to
the last 4 pings from others, tap again within 2 s for the one before; PING, then tap the map for a ping there; hold PING and say its label; tap PING twice to speak to chat),
COMMANDER, BASE and AUTO RETREAT. The idle builders sit at the right of the unit groups row, one tile per type with
its count: tap to pick the nearest and go there (zoomed in, as COMMANDER), tap again for the next. While a building is picked, or the presets
or a picker are open, the menu stays open: tap the map for the spot (or drag it there: it moves slowly at first, for
fine placing; hold still for a GRID), ROTATE turns it a quarter, then PLACE (a spot BAR refuses says so). A drag on the
game pans, units picked or not; hold, then drag to draw the picked units' path (with MOVE, FIGHT or PATROL pressed a
drag draws it at once). A tap on metal or energy opens its bar as BAR's top bar has it: the share to your team above
(red), and energy's conversion to metal (pale).
A pill shows the wind (its speed, the map's range; before the game starts the range alone, as BAR's top bar) and the
tide side by side, in a nook sunk into the dock: with units picked at the top of the selection row (the unit's name under
it, beside QUEUE), with nothing picked in the dock's top edge between metal and energy (unfolded, on the groups between
the dock's two blocks); tap a half for BAR's own details: the average, lowest and highest wind, how much of the time it
is under 6, the solar advice and the last five minutes as a graph (any tap closes them).
Spectating upright, the dock has the spectator's tools as big buttons: the player cameras, TEAMS (every team; tap one
to watch it), LAST PINGS, follow a unit (its camera views while following), FREE CAM, GROUP, FULL VIEW, and HIDE,
which folds the dock to a SHOW button at the bottom.
**Sideways too** (launcher setting "Touch dock sideways", on): the dock at one side of the bottom, for one thumb, the
rest of the screen the game's. Next to the edge a panel for the units picked: BUILD | ORDERS tabs (a builder opens on
BUILD, other units on ORDERS, a building picked on PLACE; a sideways swipe on the panel changes the tab), the
selection row, the tab's buttons; beside it metal,
energy, BAR's minimap (tap it to move the camera) and the unit groups, with the wind's and the tide's boxes and an
arrow that moves the dock to the other side of the screen (for the other hand; kept for the next game). With
nothing picked the panel holds the home buttons. The D-gun mode floats over the game: MOVE and AIM in the bottom
corners, a FIRE beside each, no minimap; swipe either FIRE towards the middle for full auto, and again to end it. Use a
gamepad or a mouse and BAR's own screen comes back; touch the screen and the dock returns.
**Unfolded** (a near-square screen, either way up): the dock splits into two blocks in the bottom corners, one under
each thumb, the game between them: metal and energy over the build grid on the left, the selection over the orders on
the right, the unit groups (and the wind's and the tide's boxes) between them at the bottom. With nothing picked the
left block keeps the build grid of the builder you picked last (else the commander's), dimmed: tap a building and that
builder is picked and its placing starts at once.
**Turning the phone** (launcher setting "Turn with the phone", on): with the phone's auto-rotate on, the lobby and
the game turn upright or sideways as you hold the phone, at any time, mid-game too (BAR's interface takes a few
seconds to redraw at the new shape). With auto-rotate off, "Play upright" decides.
- **PRESETS** (in MOVE's big place, any units that move picked): STRAFE (fight to the destination, then back and
  forth across it on repeat), BATTLE LINE, SPREAD and CONCAVE (formed up by role, moving as one). Pick one, then tap
  the map where to send it (a drag pans). With QUEUE on, tap each place in turn: the units go to the first, wait
  there for each other, then on to the next, and go side to side only at the last. With INSERT on the formation goes
  to the front of their orders.
- **D-Gun** (the commander picked): MOVE and AIM sticks and a big FIRE; the camera follows the commander. Let go of
  MOVE and it stops. Swipe FIRE to the right for full auto (it fires at the enemy in range most worth a shot, never
  through your own units; where the host allows unit control widgets), swipe AUTO to the left to end it. The empty
  space zooms (up and down) or turns (sideways); ✕ leaves.
- The lobby upright: its buttons in pages of six under the screen (swipe or tap the arrows), notes above them.
  Sideways: all its buttons (Keys, Website and Login too) in one column of large buttons on the left, a swipe up or
  down for the next page; the screens beside it take the whole height. The same in a game's Lobby (the top bar's
  Lobby button), Return to Battle first and Leave Battle with the buttons; there your fingers are the lobby's (its
  lists scroll, the game behind it stays as it was, the dock out of the way until you return). Both ways up the lobby's Settings rows
  stand further apart with taller sliders, lists and checkboxes (their choices taller too), the login dialog's
  checkboxes are larger, and upright Replays fits each team's names to its column and Plugins' buttons are finger
  sized. Replays' **Add** opens Android's file picker in Downloads: replays (.sdfz) you downloaded from BAR's website
  (Replays' Download) are copied into the game's list.

## Gamepad, mouse and keyboard

- **Gamepads:** in the lobby (also when it is opened over a game) the pad is a mouse: the D-pad puts the pointer on the next button, tab, list row or box
  that way (ringed in gold; A clicks it), and Start switches the lobby's size between 100% and 130% (each start is at
  100%). In every game (skirmish, online, spectating) the app rebuilds BAR Controller Support v0.8.5's controls from a mouse and keyboard, which
  every game allows; the pointer stays in the middle of the screen, as v0.8.5's reticle:

  | Pad | In the game |
  |---|---|
  | Left stick | Pan the map under the pointer (LT held: faster) |
  | Right stick | Turn (left/right) and zoom (up/down; LT held: faster); with LB held, tilt |
  | A | Select (twice: that type on screen); place a building |
  | A held | Nothing picked: v0.8.5's area select - a circle in the middle selects your units as you pan (RT: added to the selection, buildings too; D-pad: bigger or smaller; B: undo; X held as well: v0.8.5's filter radial, the left stick picks all mobile / combat / builders / air). Builders are never selected together with combat units. With an order picked, held for a quarter second, the left stick moves the pointer instead: an area circle (repair, reclaim), a row of buildings; let go and it glides back to the middle |
  | X | The smart order there (BAR's right click: move, attack, repair, reclaim, guard); held for a quarter second, the left stick draws a path (a shorter press stays a click, also while the camera moves) |
  | B | Cancel the order or building picked, else clear the selection |
  | RT / RB held | Queue (Shift) / put the order first in the queue (Space; on the build menu a factory's queue: Alt) |
  | RB | The build menu: the pointer onto its first option and kept on the menu (B, or a quarter second of pushing off it, lets go), the D-pad steps (past the left or right edge, or right from the last option: the page before or after), RB / LB the next / previous page, the option drawn bigger with a gold outline; A picks it (factories: queue one, RT + A five), X takes one off (RT + X five); the pointer glides back to the middle |
  | Back + RB | The order menu, the same way (the pointer at 5/8 speed): A gives the order (one that needs a target: aim it in the middle, A). While the pad is in use the orders it has buttons for (Stop, Wait, Attack, Repeat, Move, Reclaim, Repair, Fight, Patrol) are hidden from the menu, and the rest fill it evenly |
  | D-pad | Right / left: next / previous idle builder; down: the commander; up: a camera bookmark, its place and zoom (LT + up: store it) |
  | LB + D-pad | Right / left: next / previous idle unit (not builders); down: all idle units of that type |
  | RB + D-pad | Up tapped: the camera to the last ping from another player; up held: a ping in the middle of the screen; down: all your combat units; right: your combat units on the screen |
  | LB + A / X / Y / B | Fight (or attack the enemy there) / attack / patrol, in the middle; B: stop (twice: repeat; held: wait; with factories selected: stops them and clears their whole queue). With builders, A repair and X reclaim (A on the target) |
  | Start or Back + D-pad | Control groups: up / down picks the group, left tapped selects it (the camera stays), left held assigns every unit of the selection's types (and those to come), right tapped moves the camera to it, right held clears it; Start + L3 clears it too. While Start or Back is held (and a moment after) a strip shows a box for each group that has units |
  | LB + A / Y held | Draws a fight / patrol path with the left stick until let go, the units spread along it as on a move path (LB may be let go; RB held: Alt, the other fight) |
  | Back + Y | The path speed tuner (also `/padspeed` in the chat box): how fast X, LB + A and LB + Y draw at each zoom |
  | LB + L3 held | First person on the selected unit or sentry (no other buildings): the left stick walks it in any direction, the right stick looks anywhere, apart from the body, and only the horizon recentres; RT fires along the view, walking too (a player's order cannot aim above the ground, so at full range along the view at most). Back tunes the camera, the same values as the spectator tools'; B or the same chord again ends it. A squad takes orders meanwhile (the unit you look at, else the units nearby): A follow me, X stop, Y fight, RB patrol to where you look; D-pad up adds units, down clears the squad. Panels show the squad, their orders and the buttons |
  | L3 / R3 | Remove the next / the last queued order; Back + R3 + L3 held: self-destruct |
  | LB + RB + R3 (or Back + R3) | v0.8.5's D-gun mode on the selected commander: a red ring shows the D-gun's range and the target; the right stick aims around the commander, the left stick walks it, RT fires once a press, B leaves. Riding the commander in first person, RB fires the D-gun where you look |
  | LB held + RB twice / three times | Speak to chat (as the three-finger tap) / a ping in the middle of the screen with what you say as its label ("SPEAK THE PING"; nothing said, no ping). LB held + RB once opens the build menu a moment later |
  | LB + D-pad up, tapped then held | The share list: your teammates in the middle of the screen, each name in the player's colour. LB / RB switch between UNITS, METAL and ENERGY (each teammate's stock shown as a bar, a tick where their share slider caps it); D-pad up / down picks the teammate, D-pad left / right how much to give (a tenth to all you have, never more than BAR lets them take); A gives, B cancels. With no unit selected it opens on the resources |
  | Back + Start | A free pointer on the left stick (any of BAR's windows), and back; free before the game starts |
  | A building picked | v0.8.5's placement: A places it, X places it and keeps it, D-pad left/right turns it, up/down spaces a row, Back slows the pan, B puts it away. LB held: a grid ("GRID" shows) - A starts it, the left stick draws it (LB may be let go then), A places it (X: and keeps the building), B cancels |
  | An area order picked (area mex) | A starts its circle, the left stick draws it, A gives it |

  All of this works in online games, also where a lobby forbids widgets that give units orders: the pad goes the way BAR's
  own hotkeys and menus go (L3 and R3 press Insert and numpad / , which the app binds to BAR's own actions for the game;
  the D-gun mode's moves and shots are BAR's Move and D-gun picked and clicked on the spot there, so they have to be on
  the screen). Only first person needs those widgets ("FIRST PERSON OFF IN THIS GAME").
  Once the pad is used the build menu shows only when RB opens it (as v0.8.5's); three taps on the screen within 6
  seconds bring it back to opening by itself for a selected builder. (Until 2026-11-06 skirmish played v0.8.5 itself
  as BAR's developer game; the app's controls replaced it.)
- **Mouse and keyboard** (Bluetooth, or a USB-C dock): full support, as on a PC. While BAR is in front, Android's, One UI's and
  DeX's own keyboard shortcuts go to the game instead: Alt+Tab, the Windows key, Ctrl+Space, the keyboard's language
  switch (launcher setting "Keyboard shortcuts go to the game", on by default). Android keeps the Home, Recents,
  power, volume, brightness and media keys, and the swipe gestures (in the game they take a second swipe). Back is
  Escape in the game, once the touch dock has nothing left to put away (units picked, an order or building armed, a
  panel open: Back puts that away first). On Android 17 each Escape shows Android's own notice "Long press Esc key to close this app"
  (while the game gets the keyboard shortcuts): a short press is Escape for BAR, as on a PC; holding Escape down
  (3 seconds in a test) closes the game, as the notice says, so never hold it in a game you want to keep.
- Before Android 16.1, Android takes its shortcuts before any app; the optional accessibility service sends them to
  the game: Settings > Accessibility > Installed apps > **Beyond All Reason keyboard shortcuts** > On. It reads keys
  only while the game screen is in front. If Android says the setting is restricted: Settings > Apps > Beyond All
  Reason > ⋮ > Allow restricted settings, then switch it on.

## Good to know

- Big late-game battles chug: the frame rate drops with thousands of units (the phone runs the whole game simulation,
  as a PC does), but the game keeps pace, so you stay caught up (a spectated 8v8 with ~3,600 units ran at x0.97-1.02
  of real time). The frame cap is 30 fps by default (launcher: 30 / 60 / no cap).
- A match uses about 5–6 GB of memory; close other big apps first.
- Maps downloaded for games are kept under 3 GB by default (launcher: Map storage, 3 / 5 GB or no limit): before
  a game starts, the maps played longest ago are deleted, and they download again when a game needs them. BAR itself
  stays about 2.3 GB across its updates.
- Joining a running game catches up first (the screen shows how long it has left).
- With no connection the app starts what is installed: Play vs AI and the lobby's Skirmish work offline, but only on
  maps already on the phone (pick one in the lobby's map list; a map it would download cannot start). A weak signal
  can hold a start for up to ~45 s while BAR's update check waits; the launcher's "Update BAR at every start" off
  skips it. A game in the background keeps its connection, so an online match survives a look at another app.

## Problems

Tap **Share logs** on the launcher screen and attach the zip to an [issue](../../issues), with the phone model and
what happened. The zip holds the app's and the game's logs and settings; an online game's join password, which the
game writes into its log, is taken out of them first.

Known:
- Now and then, early in a game, the phone's GPU driver freezes the picture (on the S23 Ultra used for testing, about
  1 game start in 10 to 25). The app closes the frozen game and says why; start it again.
- In big online games (8v8) a hot phone can run short of memory late in the game, and Android closes the app; the
  launcher says so at its next start. Close other apps before a big game.
- If BAR's servers move to an engine version the APK has no phone build of, every game runs BAR's official engine
  until a new APK: the limits of that engine below apply, and a few of the phone fixes (such as the sea version of a
  building picked only where the finger points) are not in it.

Turning a folded phone between upright and sideways changes BAR's interface scale, and the game stops while
BAR's panels take the new size: about a second with the phone engine, 5 to 10 seconds with BAR's official engine (it
loads the whole interface again; the launcher's device lines say which engine runs). Upright, BAR's own Settings is
wider than the screen with the official engine (the phone engine has the app's Settings): open it sideways.

## For developers

[docs/HELP-WANTED.md](docs/HELP-WANTED.md) (what is left and the measurements behind it),
[docs/BUILDING.md](docs/BUILDING.md) (build, checks, releasing), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (how it
works), [CONTRIBUTING.md](CONTRIBUTING.md) (the rules: online play stays BAR's, BAR's content is never bundled),
[CHANGELOG.md](CHANGELOG.md), [docs/HISTORY.md](docs/HISTORY.md) (measurements and decisions) and
[docs/WORKLOG.md](docs/WORKLOG.md) (the effort behind it). The newest test build is the pre-release **latest-build**
on the Releases page (a debug build, replaced with each new one). That work log is also the project's conversation
archive:
[docs/worklog/](docs/worklog/) has a page a day with every message of the project's owner to Claude and Claude's
answer in full, so how the port has been supported can be read from the start.

## Licences

The app's own code and widgets: GPL-3.0-or-later ([LICENSE](LICENSE); it embeds Termux:X11's GPL-3 `lorie` module).
Third-party parts are listed in [NOTICE.md](NOTICE.md). BAR's game content (CC BY-NC-ND) is never bundled or
re-encoded: it is downloaded from `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` on the device.
