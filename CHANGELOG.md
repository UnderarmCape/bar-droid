# Changelog

What changed for players, one section per version (the version is in `gradle.properties`). The full story, with
measurements and decisions, is in [docs/HISTORY.md](docs/HISTORY.md); the effort behind it in
[docs/WORKLOG.md](docs/WORKLOG.md).

## 0.2.0 (not released yet)

The first version meant for other people's phones: everything since the first build.

**Playing**
- BAR's own lobby, online games, skirmish against AI and spectating on a Snapdragon phone (tested on a Galaxy Z
  Fold7), about 30 fps; the frame cap is 30 by default (30 / 60 / no cap in the launcher). The game draws at about 900
  lines on a wide screen and 1080 on a near-square one (the Fold7: 2100x900 folded, 1198x1080 unfolded), upscaled to
  the display; the launcher's render resolution (85%, 70%) and Display settings' display scale lower it.
- Engine, game and lobby update at every start as on BAR's PC launcher; a set that fails on its first start is rolled
  back. BAR's content always comes from BAR's own servers; nothing of BAR is in the APK.
- Online play stays exactly BAR's: the engine is BAR's official build, unmodified.

**Touch**
- Touch camera: drag to pan, continuous pinch zoom, twist to rotate, two-finger tilt; drags on BAR's windows and top
  bar act as mouse drags. A three-finger swipe down brings the camera to the commander and selects it (dead: the
  constructor selected last).
- Placing one building by touch: the building follows a drag instead of the map panning, a later drag nudges it, a
  tap moves it, a double tap sends it; held still (or dragged from the waiting building) it becomes a GRID drawn by
  the finger and sent with PLACE or a double tap.
- The lobby by finger: lists scroll with a drag, a tap on a server shows its details first. A server whose settings
  stop the touch or gamepad controls says so when you join it.
- Spectating by touch: the player list stays small, a tap on it brings up a bar to switch player cameras by name,
  follow the unit nearest the screen's centre (or double-tap a unit), follow a group, camera presets (1st person,
  over the shoulder, table, close, mid) and a 1st person camera on the unit with free look that recenters itself;
  the settings can be tuned per unit type on the phone (Tune) and apply to the other factions' equivalents.
- BAR's interface scale fits each Fold screen (cover and inner), and follows fold/unfold during a game; the lobby at
  100% on both screens. Unfolded, the minimap is half size until tapped.
- Camera views while following: Table, Close and Mid are the same for every unit; Shoulder (centred close behind the
  unit by default, on any ground) and 1st person can be tuned per unit type; a view's Up raises the camera.
- A layout editor: hold three fingers on the screen (or type `/hud` in the chat) to move and size the chat, the unit
  info panel and the spectate bar (and set their text size and padding), and size BAR's minimap and player list; kept
  separately for folded and unfolded. BAR's interface scale unfolded is 1.0 (was 1.3). The build menu is the app's
  copy of BAR's Build menu (the same menu, 3 rows a page: 3 options across, 5 on a wide, short screen such as the
  Fold7 folded; the page arrows in a strip under them), so the editor moves and sizes it too, and it keeps clear of a
  unit info panel made bigger (which stops at the order menu); in the controller game it shows while the app's gamepad controls
  have the pad (a triple tap switches); it steps aside for BAR's own when a
  BAR update changes that menu, and for the gamepad's in the controller game.
- Building by touch: while a building is picked, the build menu's page strip shows ONE, LINE, GRID and BORDER, and a
  big green PLACE button (rotate and cancel inside) covers the order menu. A tap on the map picks the spot, PLACE
  builds there (the building stays picked); with LINE, GRID or BORDER a drag lays out a row, a filled area or a
  hollow ring of them (BAR's own build drag).
- Typing a chat message: the text wraps and gets smaller as it grows, in a box at the top of the chat that stays clear
  of BAR's start countdown.
- BAR's messages ("Battle Started", a commander under attack, the tutorial's lines) show in the chat box for 15
  seconds, where they were typed behind the order menu.
- A tap on BAR's top bar (metal, energy) no longer clears the selection, and the spectate bar's buttons work on the
  first tap. BAR's Settings, Statistics, key bindings and other windows scroll with a finger drag up or down (sideways
  still moves their sliders), and the map behind them stays put.
- Several units of one type selected: the unit info panel shows that type's name and stats with the count on its
  picture; a tap on the picture brings the camera to them.
- The lobby: a tooltip or a pressed look no longer stays where a finger lifted, and the Settings list scrolls from
  anywhere on it.

**Controllers, mouse and keyboard**
- Gamepads: BAR Controller Support (v0.8.5) as the singleplayer game; a mouse in the lobby, where Start switches its
  size between 100% and 130%; in BAR's own game
  (online, spectating) v0.8.5's controls rebuilt from a mouse and keyboard: the pointer in the middle of the screen,
  the left stick pans, the right stick turns and zooms, A selects and places, X is the smart order, B cancels; RB and
  Back + RB put the build and order menus on the pad (the D-pad steps, the option on the pad highlighted, the
  pointer kept on the menu); control groups on Start + D-pad, idle units and the commander on the D-pad, LB orders,
  queue removal, the D-gun; v0.8.5's placement (LB grid: A, draw, A); v0.8.5's area select (A held); X held draws a
  path, A held with an order picked an area; RB / LB page the build menu; the pointer glides back to the middle. In
  the controller game a triple tap switches between v0.8.5 and these controls (with them the app's build menu:
  once the pad is used it shows only when RB opens it, until three taps on the screen or the pad goes away). RB + D-pad:
  up held a ping in the middle, up tapped the camera to the last ping from another player, down every combat unit,
  right those on the screen. All of it works online, also where a lobby forbids widgets that give units orders;
  only first person does not.
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
- First person on the pad (LB + L3 held) on a unit or a sentry: the left stick walks it in any direction, the right
  stick looks anywhere apart from the body, RT fires where you look, and a squad of units nearby takes orders (follow
  me, stop, fight, patrol there). Its camera uses the spectator tools' values and is tuned in place. A Save in either
  camera tuner is kept at once, not only when the game quits.
- Fight and patrol paths (LB + A / Y held), drawn as a move path is, with the units spread along them. The pointer's
  speed while drawing follows the zoom, on a curve you set (Back + Y). LT speeds up the zoom too, as in v0.8.5. A
  camera bookmark brings back its place and zoom and leaves the tilt alone. Self-destruct is Back + R3 + L3 held.
- A QUEUE button for fingers (a sticky Shift, let go when the pad takes over), and the menus open by themselves by
  touch, also in the controller game; three-finger swipe down selects the commander as well.
- A tap as a game finishes loading no longer takes BAR's music and volume sliders out of that game, and quitting in
  first person no longer starts later games in that camera.
- The launcher's start buttons use what the screen shows: a changed setting no longer needs Save settings first.
- A Bluetooth or USB-C dock mouse and keyboard work as on a PC; Android's, One UI's and DeX's own keyboard shortcuts
  are kept out of the game.

**Phone-friendly running**
- Smooth 30 fps: the frame cap follows the display's vsync and every picture stays on screen for the same time. At a
  steady 30 fps a third of the pictures used to stay too short or too long (a stutter you could feel without the fps
  dropping); now 99.9% stay exactly right.
- Frame pacing that lets CPU and GPU overlap, a sharper upscale of the game image (Snapdragon GSR), phone graphics
  settings applied at every start, and effects nobody sees on a phone switched off (Reclaim Field Highlight, ship
  wakes, unread G-buffer passes, ...).
- Joining a running game catches up without drawing, with an estimate of the time left; the game stops drawing while
  its screen is hidden; a floating window when you leave the game.
- **Share logs** in the launcher, and a Benchmark button (BAR's "Benchmark BAR" scenario); GL check and the
  Benchmark show their result in the launcher, and a game that fails to start says so there.
- A skirmish's first seconds no longer stutter at 2-5 fps (BAR's cursors load with the game), and a game takes about
  400 MB less graphics memory (BAR's unit picture cache off).
- One notification while a game runs (with Stop); a tap on it goes back to the game, and coming back from the
  floating window no longer makes the game pause to lay itself out again.
- When Android closes the game for lack of memory, the launcher says so (before, the app just started again).
- 8 GB phones play in a low-memory mode, set automatically: over 1 GB less memory (the engine's Lua memory pools off,
  compressed textures, BAR's GL4 unit shaders, shore foam and ground scorch marks off), and skirmish on a smaller map
  (Starwatcher) until you pick one. On a Galaxy S23 Ultra BAR's benchmark battle and skirmishes on that map play
  through (13 of 13 and 3 of 3); close other apps first. 12 GB phones are unchanged.

## 0.1.0 (2026-10-25)

The first build, from a cloud session: the Recoil engine and BAR in a Debian container on Android, drawn through
Termux:X11's X server. Not released.
