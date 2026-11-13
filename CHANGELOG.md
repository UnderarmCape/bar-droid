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
  the display; the launcher's render resolution (85%, 70%) and Display settings' display scale lower it. Launcher
  setting "Lower the resolution when fps drops" (off by default): under 27 fps the game is drawn smaller a
  step at a time (85, then 70% of the lines), never under 70%, kept only while each step makes it faster.
- Map storage (launcher, 3 GB by default; 5 GB or no limit): before a game or the lobby starts, the downloaded
  maps played longest ago are deleted until the rest fit; a map downloads again when a game needs it. The lobby opens
  without BAR's Rapid Pool Cache (it read all of BAR's 2.2 GB at every start, the lobby at half its frame rate for
  ~30 s, and measured on an 8 GB phone, games loaded ~11 s slower after it); the lobby's Settings can turn it back
  on. With no network at all the lobby's downloads fail at once instead of trying each four times. The lobby's buttons
  that open a folder (Replays' Open Folder, Links' Game Data, Plugins' Widgets Folder) are gone: a phone has no folder
  view for the app's own storage, and the launcher's Share logs gives the logs.
- The app is a game for Android and One UI: Game Booster and Gaming Hub see it, and Android's performance game mode
  (Game Booster's game performance, or `cmd game mode performance`) gave 1-2 fps more in a late 8v8 on a hot S23 Ultra.
- Smaller on the phone: the Debian container holds only what the game loads (723 -> 375 MB; an earlier install is
  slimmed once at its next start, ~25 s), and each engine version leaves out the server builds a phone never runs
  (108 -> 70 MB).
- Less work around the game itself: the screen is drawn once per game picture (BAR's animated pointer drew it two to
  three times; the display's GPU time 23 -> 10 ms a second in a late 8v8), and the game's talk with the app's X server
  no longer stops for the container on every message (the game's main thread stopped 1.05 -> 0.23 % of the time).
- Engine, game and lobby update at every start as on BAR's PC launcher; a set that fails on its first start is rolled
  back. BAR's content always comes from BAR's own servers; the APK carries only phone versions of a few of BAR's
  pictures (the upright loading pictures), which BAR's developers cleared (NOTICE.md).
- Online play stays exactly BAR's: the engine is BAR's official build, unmodified.
- BAR's clock, the saved games' names and dates and the lobby's times follow the phone's time zone (they were UTC).
  Saved games load from the lobby's Load Game, the commander picked and the camera on it as at a game's start.

**Touch**
- Speak to chat: a three-finger tap (on the pad: LB held, RB twice) listens through the phone's speech recognition and
  sends what you said as a chat message, no keyboard (nothing said, nothing sent); a three-finger double tap shows the
  keyboard. LB held and RB three times: a ping in the middle of the screen labelled with what you say. In a game the
  words go to the game's chat only (they no longer reach the lobby's server room too), and the lobby's "speak to"
  panel and channel switching stay out of the game.
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
  separately for folded and unfolded. The player list's outline takes in the rows BAR stacks on it (music, unit
  totals, the clock), its name tab above them. BAR's interface scale unfolded is 1.0 (was 1.3). The build menu is the app's
  copy of BAR's Build menu (the same menu, 3 rows a page: 3 options across, 5 on a wide, short screen such as the
  Fold7 folded; the page arrows in a strip under them), so the editor moves and sizes it too, and it keeps clear of a
  unit info panel made bigger (which stops at the order menu); in the controller game it shows while the app's gamepad controls
  have the pad (a triple tap switches); it steps aside for BAR's own when a
  BAR update changes that menu, and for the gamepad's in the controller game.
- The building you picked is framed in gold in the build menu while you place it.
- The build menu's pictures no longer stay in stripes after some game starts (the menu is drawn again 5 s in, and
  every 30 s while it is unchanged).
- Building by touch: while a building is picked, the build menu's page strip shows ONE, LINE, GRID and BORDER (the
  picked one gold, in white words), and a big green PLACE button (rotate and cancel inside) covers the order menu. A tap on the map picks the spot, PLACE
  builds there (the building stays picked); with LINE, GRID or BORDER a drag lays out a row, a filled area or a
  hollow ring of them (BAR's own build drag).
- Typing a chat message: the text wraps and gets smaller as it grows, in a box at the top of the chat that stays clear
  of BAR's start countdown.
- BAR's messages ("Battle Started", a commander under attack, the tutorial's lines) show in the chat box for 15
  seconds, where they were typed behind the order menu. When a game ends the chat says that BAR will leave it in 12
  seconds and that a tap keeps it open (it closed without a word).
- A tap on BAR's top bar (metal, energy) no longer clears the selection, and the spectate bar's buttons work on the
  first tap. BAR's Settings, Statistics, key bindings and other windows scroll with a finger drag up or down (sideways
  still moves their sliders), and the map behind them stays put. Saving a game (the top bar's Save) keeps the units
  you had picked (the engine unpicks them for the save, the app picks them again) and says "Game saved" in the chat
  box.
- Several units of one type selected: the unit info panel shows that type's name and stats with the count on its
  picture; a tap on the picture brings the camera to them.
- The lobby: a tooltip or a pressed look no longer stays where a finger lifted, and the Settings list scrolls from
  anywhere on it.
- Past the map's edge the camera moves as on the map: a drag there holds the point under the finger up and down as
  well as across (up and down went the wrong way), a drag across the edge moves smoothly, a pinch there zooms about
  the fingers, and a drag over the sky (the camera tilted up to the horizon) moves the map.
- In a game the build menu's tooltip no longer stays over the next row after a tap, and an order's tooltip goes
  2.5 s after the finger lifts, in every game (the controller game's menus too). In the controller game a drag that
  starts on the build or order menu no longer pans the map, as in BAR's own game.
- A scenario's briefing: the tap that closes it no longer clicks the map behind it too (it unpicked the commander),
  and the chat's lines end above it.
- The unit info panel: a wreck, a tree or a rock under the finger (nothing selected) shows its name and what
  reclaiming it gives, a wreck with the picture of the unit it was; several types selected show a count only above
  1, a long count small enough to leave the picture visible; its largest text a size smaller.
- The lobby and the game turn with the phone (launcher setting "Turn with the phone", on): with the phone's
  auto-rotate on, upright or sideways as it is held, at any time; with auto-rotate off, "Play upright" decides.
- The touch dock sideways too (launcher setting "Touch dock sideways", on), for one thumb: at one side of the bottom
  the units' panel with BUILD | ORDERS tabs, and beside it metal, energy, BAR's minimap and the unit groups, with HOME
  and an arrow that moves the dock to the other side; with nothing picked only the minimap part. BAR's resource bars
  and minimap move into the dock. A gamepad or a mouse brings BAR's own screen layout back.
- Playing upright (launcher setting "Play upright"): the game on top, a touch dock below. Its D-gun mode keeps the
  commander in the middle of the screen, hides the rows it does not need, fires on FIRE's release, and FIRE swiped to
  the right switches on full auto (the enemy in range most worth a shot, a commander first, never through a friendly unit; only where the
  host allows unit control widgets), with its
  own animation; the dock's empty space zooms or turns the camera. The chat takes the full row under the top bar, the
  minimap shrunk to the top bar's height. The lobby upright: its buttons on two pages (Multiplayer, Skirmish,
  Scenarios, Settings, Chat, Friends first), notes at the top left beside the connection state, BAR's Settings drawn
  in full, a scenario's page with its values clear of their labels and its records whole, the Keys window's six tabs
  in two rows (the three Legacy ones were out of reach). The lobby sideways: all its buttons, Keys, Website and Login
  too, in one column of large buttons down the left, close together, a swipe up or down for the next page; the
  screens beside it take the whole height. Taps on the dock answer
  with a light vibration. The dock's presets (STRAFE: a line abreast with gaps; three formations, the ranged behind the front
  by their reach) go where the map is tapped, or a line drawn on the map is their front, as wide; there each unit
  fights side to side across its place on repeat, the group together. PLACE, the presets and the build menus take the
  first tap; the dock stays open while a building is being placed. INSERT, QUEUE and the home buttons take the first tap too.
  A GRID comes only from a long press that never moved (on the waiting building, a full second): ONE during a GRID
  keeps it, the building waiting where it began, and GRID or LINE brings it back; GRID and LINE switch a held one.
  A long press on the dock no longer moves the camera.
- Upright, the idle builders sit at the right of the unit groups row, one tile per type with its count (a tap picks
  the nearest and goes there, again for the next); the row scrolls sideways when full. PINGS on the home grid: LAST
  PINGS goes to the last 4 pings from others (their count on it), PING then a map tap pings there; PING held: what you say labels the ping (as BAR's pings with
  words); PING tapped twice: CHAT, speak to chat, with a flip back to PING when it is sent. FACTORIES beside
  them picks your next factory and brings the camera to it, its build menu in the dock to queue units. The dock's
  menu stays open 2.6 s after the last touch (was 2). Placing a building:
  a drag moves it slowly at first for fine control, ROTATE and X across PLACE's bottom, a GRID only from a still long
  press (lit while held; ONE ends it), BAR's own blueprint while moving it, a factory's INSERT puts the unit first, and while a picked unit has a
  building queued a one-finger drag pans instead of drawing a move path. COMMANDER frames a wider view.
- Spectating upright: the same dock with big buttons (player cameras, TEAMS to watch any team, LAST PINGS, follow a
  unit and its camera views, FREE CAM, GROUP, FULL VIEW) and HIDE, which folds it to a SHOW button. A unit followed
  stays in the middle of the game above the dock (Shoulder turned down onto it and far enough back to show it whole,
  1st person looking ahead rather than into the sky); AI teams go by the names BAR gives them, in TEAMS and the
  gamepad's share list.
- Joining an online game upright: the "Waiting for server response" screen fitted to the screen, with Free memory; the
  lobby's first BAR picture sharper.
- A game alone (a replay, or no other active player) pauses while the app is out of sight and goes on when you come
  back. The launcher's map field lists the maps you have, again after a game downloaded or removed some.

**Controllers, mouse and keyboard**
- Gamepads: a mouse in the lobby, where Start switches its size between 100% and 130%; in every game (skirmish,
  online, spectating) BAR Controller Support v0.8.5's controls rebuilt from a mouse and keyboard: the pointer in the middle of the screen,
  the left stick pans, the right stick turns and zooms, A selects and places, X is the smart order, B cancels; RB and
  Back + RB put the build and order menus on the pad (the D-pad steps, the option on the pad highlighted, the
  pointer kept on the menu); control groups on Start + D-pad, idle units and the commander on the D-pad, LB orders,
  queue removal; v0.8.5's D-gun mode on LB + RB + R3 or Back + R3 (the right stick aims around the commander, the left
  walks it, RT fires, B leaves; riding the commander in first person RB fires the D-gun); LB + D-pad up tapped, then
  held: the share list (units, metal or energy to a teammate, names in their colours: LB / RB switch between UNITS,
  METAL and ENERGY, D-pad up / down picks the teammate, each row showing how much of it they hold, D-pad left / right
  sets how much to give, from a tenth to all you have, never more than BAR lets in: their storage up to their share
  slider, marked on their bar; A gives, B cancels;
  with no unit selected it opens on the resources);
  v0.8.5's placement (LB grid: A, draw, A); v0.8.5's area select (A held); X held draws a
  path, A held with an order picked an area; RB / LB page the build menu; the pointer glides back to the middle; once
  the pad is used the app's build menu shows only when RB opens it, until three taps on the screen or the pad goes
  away. Skirmish plays BAR's own game with these controls too (Kailil, 2026-11-06: the v0.8.5 game and its triple-tap
  switch are gone). In the lobby the D-pad puts the pointer on the next control that way, ringed in gold. RB + D-pad:
  up held a ping in the middle, up tapped the camera to the last ping from another player (tapped again within 2 s
  the one before it, back through the last 5 and round again; after a pause the newest again), down every combat
  unit, right those on the screen. All of it works online, also where a lobby forbids widgets that give units orders;
  only first person does not.
- The order menu with the pad, in every game: the orders the pad has buttons for are hidden and the rest fill the
  menu with bigger buttons, online too (the app's copy of BAR's Order menu runs in BAR's released game), and a
  finger's drag on the order menu no longer pans the map. The hidden orders come back after a game played with the pad
  (they had stayed hidden in later games, by touch too).
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
  Its status line and the notification say what is happening in the same words from the first moment ("Starting",
  "Installing: ...", "Skirmish running"), and its buttons and settings no longer crowd their edges. On a narrow,
  near-square screen (large display size or font) it is one scrolling page: the buttons scroll with the settings,
  which before had a line or two left under them.
- A Bluetooth or USB-C dock mouse and keyboard work as on a PC; Android's, One UI's and DeX's own keyboard shortcuts
  are kept out of the game.

**Phone-friendly running**
- Smooth 30 fps: the frame cap follows the display's vsync and every picture stays on screen for the same time. At a
  steady 30 fps a third of the pictures used to stay too short or too long (a stutter you could feel without the fps
  dropping); now 99.9% stay exactly right.
- Frame pacing that lets CPU and GPU overlap, a sharper upscale of the game image (Snapdragon GSR), phone graphics
  settings applied at every start, and effects nobody sees on a phone switched off (Reclaim Field Highlight, ship
  wakes, unread G-buffer passes, ...). In big games (10 teams or more) BAR's sonar, radar and line-of-sight circles and
  its always-shown jammer coverage are off (a late 8v8 spent ~13% of the GPU's time on them); your own settings come
  back in the next smaller game. Builders' nano spray is the engine's, at most 1000 particles (BAR's 3D spray kept at
  least 5000 and cost ~2 ms a frame in a late 8v8).
- Joining a running game catches up without drawing, with an estimate of the time left; the game stops drawing while
  its screen is hidden; a floating window when you leave the game.
- **Share logs** in the launcher, and a Benchmark button (BAR's "Benchmark BAR" scenario); GL check and the
  Benchmark show their result in the launcher, and a game that fails to start says so there. The launcher's
  settings show their name first, what they do smaller under it (its text fields and option groups too: the map
  says it is Play vs AI's); its warnings stand in amber. It shows BAR's game version the last start played
  ("Game version test-31836-b250a16"), the one to compare with friends before an online game.
- A skirmish's first seconds no longer stutter at 2-5 fps (BAR's cursors load with the game), and a game takes about
  400 MB less graphics memory (BAR's unit picture cache off).
- Interface pictures in black stripes (the build menu's, the idle builders button's) should be gone: the GPU's
  compressed drawing buffers are off on Snapdragon phones, at no measured cost.
- Picking a building no longer lags with many construction turrets: the engine drew the build range of every one of
  them; now the 10 nearest the building are drawn (150 turrets on the dev phone: 26 fps before, 85 after, uncapped).
- One notification while a game runs (with Stop); a tap on it goes back to the game, and coming back from the
  floating window no longer makes the game pause to lay itself out again.
- When Android closes the game for lack of memory, the launcher says so (before, the app just started again), and how
  to close the other apps. When the phone's GPU driver hits its rare fault and the game freezes for good, the app
  closes it and says why, instead of leaving a frozen picture. When BAR stops on an error of its own (on a PC a
  message box), the launcher shows its message. A game Android closed for memory, or a join that timed out, in a
  new BAR version's first minutes no longer rolls BAR back to the older version (which online games reject).
- A Free memory button while BAR loads (Galaxy phones): it opens Device care, where Memory, Clean now closes the
  other apps; Back returns to the loading game; it lights up under the finger. (Android lets no app close other apps
  itself.)
- 8 GB phones play in a low-memory mode, set automatically: over 1 GB less memory (the engine's Lua memory pools off,
  compressed textures, BAR's GL4 unit shaders, shore foam and ground scorch marks off), and skirmish on a smaller map
  (Starwatcher) until you pick one. On a Galaxy S23 Ultra BAR's benchmark battle and skirmishes on that map play
  through (13 of 13 and 3 of 3); close other apps first. 12 GB phones are unchanged.

## 0.1.0 (2026-10-25)

The first build, from a cloud session: the Recoil engine and BAR in a Debian container on Android, drawn through
Termux:X11's X server. Not released.
