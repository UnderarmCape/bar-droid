# Changelog

What changed for players, one section per version (the version is in `gradle.properties`). The full story, with
measurements and decisions, is in [docs/HISTORY.md](docs/HISTORY.md); the effort behind it in
[docs/WORKLOG.md](docs/WORKLOG.md).

## 0.2.0 (not released yet)

The first version meant for other people's phones: everything since the first build.

**Playing**
- BAR's own lobby, online games, skirmish against AI and spectating on a Snapdragon phone (tested on a Galaxy Z
  Fold7), about 30 fps; the frame cap is 30 by default (30 / 60 / none in the launcher). The game draws at about 900
  lines on a wide screen and 1080 on a near-square one (the Fold7: 2100x900 folded, 1198x1080 unfolded), upscaled to
  the display; the launcher's render resolution (85%, 70%) and Display settings' display scale lower it.
- Engine, game and lobby update at every start as on BAR's PC launcher; a set that fails on its first start is rolled
  back. BAR's content always comes from BAR's own servers; nothing of BAR is in the APK.
- Online play stays exactly BAR's: the engine is BAR's official build, unmodified.

**Touch**
- Touch camera: drag to pan, continuous pinch zoom, twist to rotate, two-finger tilt; drags on BAR's windows and top
  bar act as mouse drags.
- The lobby by finger: lists scroll with a drag, a tap on a server shows its details first.
- Spectating by touch: the player list stays small, a tap on it brings up a bar to switch player cameras by name,
  follow the unit nearest the screen's centre (or double-tap a unit), follow a group, camera presets (1st person,
  over the shoulder, table, close, mid) and a 1st person camera on the unit with free look that recenters itself;
  the settings can be tuned per unit type on the phone (Tune) and apply to the other factions' equivalents.
- BAR's interface scale fits each Fold screen (cover and inner), and follows fold/unfold during a game; the lobby at
  150% on the inner screen. Unfolded, the minimap is half size until tapped.
- Camera views while following: Table, Close and Mid are the same for every unit; Shoulder (centred close behind the
  unit by default, on any ground) and 1st person can be tuned per unit type; a view's Up raises the camera.
- A layout editor: hold three fingers on the screen (or type `/hud` in the chat) to move and size the chat, the unit
  info panel and the spectate bar (and set their text size and padding), and size BAR's minimap and player list; kept
  separately for folded and unfolded. BAR's interface scale unfolded is 1.0 (was 1.3). The build menu is the app's
  copy of BAR's Build menu (the same menu, as a 3x3 grid: 6 options a page), so the editor moves and sizes it too; it steps aside for BAR's own when a
  BAR update changes that menu, and for the gamepad's in the controller game.
- Typing a chat message: the text wraps and gets smaller as it grows, in a box at the top of the chat that stays clear
  of BAR's start countdown.

**Controllers, mouse and keyboard**
- Gamepads: BAR Controller Support (v0.8.5) as the singleplayer game; the pad drives the camera online and is a
  mouse in the lobby.
- A Bluetooth or USB-C dock mouse and keyboard work as on a PC; Android's, One UI's and DeX's own keyboard shortcuts
  are kept out of the game.

**Phone-friendly running**
- Frame pacing that lets CPU and GPU overlap, a sharper upscale of the game image (Snapdragon GSR), phone graphics
  settings applied at every start, and effects nobody sees on a phone switched off (Reclaim Field Highlight, ship
  wakes, unread G-buffer passes, ...).
- Joining a running game catches up without drawing, with an estimate of the time left; the game stops drawing while
  its screen is hidden; a floating window when you leave the game.
- **Share logs** in the launcher, and a Benchmark button (BAR's "Benchmark BAR" scenario).

## 0.1.0 (2026-10-25)

The first build, from a cloud session: the Recoil engine and BAR in a Debian container on Android, drawn through
Termux:X11's X server. Not released.
