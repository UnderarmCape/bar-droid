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
  bar act as mouse drags. A three-finger swipe down brings the camera to the commander (dead: the constructor
  selected last).
- Placing one building by touch: the building follows a drag instead of the map panning, a later drag nudges it, a
  tap moves it, a double tap sends it; held still (or dragged from the waiting building) it becomes a GRID drawn by
  the finger and sent with PLACE or a double tap.
- The lobby by finger: lists scroll with a drag, a tap on a server shows its details first.
- Spectating by touch: the player list stays small, a tap on it brings up a bar to switch player cameras by name,
  follow the unit nearest the screen's centre (or double-tap a unit), follow a group, camera presets (1st person,
  over the shoulder, table, close, mid) and a 1st person camera on the unit with free look that recenters itself;
  the settings can be tuned per unit type on the phone (Tune) and apply to the other factions' equivalents.
- BAR's interface scale fits each Fold screen (cover and inner), and follows fold/unfold during a game; the lobby at
  135% on both screens. Unfolded, the minimap is half size until tapped.
- Camera views while following: Table, Close and Mid are the same for every unit; Shoulder (centred close behind the
  unit by default, on any ground) and 1st person can be tuned per unit type; a view's Up raises the camera.
- A layout editor: hold three fingers on the screen (or type `/hud` in the chat) to move and size the chat, the unit
  info panel and the spectate bar (and set their text size and padding), and size BAR's minimap and player list; kept
  separately for folded and unfolded. BAR's interface scale unfolded is 1.0 (was 1.3). The build menu is the app's
  copy of BAR's Build menu (the same menu, as a 3x3 grid: 9 options a page, the page arrows in a strip under
  them), so the editor moves and sizes it too; in the controller game it shows while the app's gamepad controls
  have the pad (a triple tap switches); it steps aside for BAR's own when a
  BAR update changes that menu, and for the gamepad's in the controller game.
- Building by touch: while a building is picked, the build menu's page strip shows ONE, LINE, GRID and BORDER, and a
  big green PLACE button (rotate and cancel inside) covers the order menu. A tap on the map picks the spot, PLACE
  builds there (the building stays picked); with LINE, GRID or BORDER a drag lays out a row, a filled area or a
  hollow ring of them (BAR's own build drag).
- Typing a chat message: the text wraps and gets smaller as it grows, in a box at the top of the chat that stays clear
  of BAR's start countdown.

**Controllers, mouse and keyboard**
- Gamepads: BAR Controller Support (v0.8.5) as the singleplayer game; a mouse in the lobby; in BAR's own game
  (online, spectating) v0.8.5's controls rebuilt from a mouse and keyboard: the pointer in the middle of the screen,
  the left stick pans, the right stick turns and zooms, A selects and places, X is the smart order, B cancels; RB and
  Back + RB put the build and order menus on the pad (the D-pad steps, the option on the pad highlighted, the
  pointer kept on the menu); control groups on Start + D-pad, idle units and the commander on the D-pad, LB orders,
  queue removal, the D-gun; v0.8.5's placement (LB grid: A, draw, A); v0.8.5's area select (A held); X held draws a
  path, A held with an order picked an area; RB / LB page the build menu; the pointer glides back to the middle. In
  the controller game a triple tap switches between v0.8.5 and these controls (with them the app's 3x3 build menu,
  shown once RB opens it).
- The app's controller interface in one look with BAR's own: notes, the filter radial and the group strip in BAR's
  panels and font, sized by the interface scale (about the same on both Fold screens); the pad's place on the build
  and order menus a thin gold line; a pad button named in a note shown as its coloured key.
- Both controller modes (Kailil's Fold7 notes): the camera pans 30% slower; A held then X opens the area select's
  filter radial (all mobile, combat, builders, air), and builders are never selected together with combat units; LB
  grid shows "GRID" and draws with LB alone; X (and A with an order picked) needs a quarter-second hold before it
  draws, so a quick press while the camera moves stays a click; the order menu drops the orders the pad has buttons
  for (in the controller game the rest fill it evenly); a group strip shows the groups that have units, and recalling
  one no longer moves the camera; LB + B with factories selected stops them and clears their queues; a big army's
  paths and queue show without RT.
- A Bluetooth or USB-C dock mouse and keyboard work as on a PC; Android's, One UI's and DeX's own keyboard shortcuts
  are kept out of the game.

**Phone-friendly running**
- Frame pacing that lets CPU and GPU overlap, a sharper upscale of the game image (Snapdragon GSR), phone graphics
  settings applied at every start, and effects nobody sees on a phone switched off (Reclaim Field Highlight, ship
  wakes, unread G-buffer passes, ...).
- Joining a running game catches up without drawing, with an estimate of the time left; the game stops drawing while
  its screen is hidden; a floating window when you leave the game.
- **Share logs** in the launcher, and a Benchmark button (BAR's "Benchmark BAR" scenario).
- When Android closes the game for lack of memory, the launcher says so (before, the app just started again).
- 8 GB phones play in a low-memory mode, set automatically: over 1 GB less memory (the engine's Lua memory pools off,
  compressed textures, BAR's GL4 unit shaders, shore foam and ground scorch marks off), and skirmish on a smaller map
  (Starwatcher) until you pick one. On a Galaxy S23 Ultra BAR's benchmark battle and skirmishes on that map play
  through (13 of 13 and 3 of 3); close other apps first. 12 GB phones are unchanged.

## 0.1.0 (2026-10-25)

The first build, from a cloud session: the Recoil engine and BAR in a Debian container on Android, drawn through
Termux:X11's X server. Not released.
