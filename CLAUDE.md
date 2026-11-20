# CLAUDE.md — BAR Droid (Beyond All Reason on Android)

Working folder on the laptop: `C:\Tools\BARANDROID\` (this project is `bar-droid-app/` inside it).
Owner: Kailil (GitHub UnderarmCape). Goal: a sideloadable APK that plays BAR. **It plays on Kailil's Galaxy Z Fold7**
(~30 fps). Two phones on adb (Kailil, 2026-10-29): the **dev phone** (a Galaxy S23 Ultra, always on USB, adb over
Wi-Fi as a backup) is the agents' own, 24/7, for dev work, tests and benchmarks: drive its game yourself; its screen is
kept dark (`tools\devphone.ps1` status|connect|dark|bench; `tools\devphone-watch.bat` keeps it connected and dark;
`tools\phone-bench.ps1` puts it at the normal minimum brightness for a run). The **Fold7** is his daily phone, only
for builds that need his own testing (fold, play, lobby; he checks fps and sound, you read the logs): no benchmarks or
monitoring on it unless necessary, never while he plays. Install every build that needs his testing on the Fold7 right
away, even over a running game; never ask first. The tools drive the dev phone (`..\phone-device.txt`: its serial and
Wi-Fi address, outside the repository; `toolchain.ps1` Get-PhoneDevice); name the Fold7 on purpose with
`ANDROID_SERIAL` (`Install on Phone.bat`, `Get Logs.bat`) or `-Device`. Serials, addresses and the Wi-Fi both must be
on: `CLAUDE.local.md` (Kailil's, not in the repository). Wi-Fi adb: `adb tcpip 5555` over USB, until the phone
restarts. No emulator for checks (Kailil, 2026-10-25); it stays a bench for emulator builds only.

For people: README.md (players), docs/BUILDING.md, docs/ARCHITECTURE.md, CONTRIBUTING.md; keep them current when
something they describe changes.

## Architecture in one breath
BAR's **Recoil engine** (amd64 official build for the emulator; on phones by default its phone build from the engine
branch, carried in the APK, else the official one: docs/ENGINE-DEFAULT.md) runs inside a **Debian trixie
proot container** (Termux's proot, built by `tools/build-proot.py`, bundled as `libproot.so`) and draws onto
**Termux:X11's X server compiled into this APK** (`:lorie` module, GPL-3), shown by
`GameActivity extends com.termux.x11.MainActivity`. OpenGL: on the emulator,
Mesa `virpipe` → our virgl server (`VirglServer`, built by `tools/build-virgl.py`) → ANGLE → Vulkan → host GPU, with
llvmpipe as CPU fallback; on phones, Mesa for Android containers (Freedreno `kgsl` / Turnip+Zink). Content comes from
BAR's own CDN via `pr-downloader`. Gamepad → UDP `BARCTRL1` packets. Audio: the engine's OpenAL Soft wave writer →
FIFO → `AudioPump` → `AudioTrack` (`UseSDLAudio = 0`, no PulseAudio). Touch: `RtsTouch` ↔ `bardroid_touch.lua`
(files under `LuaUI/Config`).

## Key files
- `app/src/main/java/com/underarmcape/bardroid/` — `Installer` (first run), `Proot` (command builder, mirrors proot-distro),
  `XServer` (app_process launcher), `VirglServer` (GPU server), `GameService` (foreground), `GameActivity`
  (display + gamepad), `Prefs` (`EMULATOR_BUILD`, URLs per ABI, `putGpuEnv`), `ControllerBridge`, `AudioPump`.
- `app/src/main/assets/bardroid/` — `setup-container.sh` (apt/mesa/engine/content/import), `launch-bar.sh` (GPU env,
  glcheck, the Android layer over BAR's and the lobby's saved settings at every start: phone graphics `PHONE_GFX`,
  the low-memory mode under 9.5 GB of RAM `LOW_MEMORY` (with `bardroid_lowmem.lua`), interface scale, widget orders;
  spring), `springsettings.cfg` (preset; emulator overrides in
  `Installer.EMULATOR_GRAPHICS`), `libbardroid_pace.so` (`tools/pace/pace.c`, `tools/build-pace.py`; LD_PRELOADed
  into the engine: the frame cap on the display's vsync grid (the swap waits for its slot, a frame starts as late as
  the slowest recent one allows; `BARDROID_PACE_VSYNC=0`: the old sleep after the swap), the ioctl answer that puts lfdevs' Mesa on its
  explicit Present fence, so the swap never waits for the GPU (HANDOFF "Busy scenes"), the X connection's
  `recvmsg`/`sendmsg` as `recvmmsg`/`writev`, which proot's filter does not stop (Unix stream sockets without an
  address only; `BARDROID_SOCKET_TRAPS=1` off; docs/CONTAINER-COST.md), and SDL2 HIDDEN/SHOWN window
  events while the game screen is stopped (`/tmp/bardroid-hidden`, the engine stops drawing) or a joined game is
  being caught up far behind (`/tmp/bardroid-catchup`, from `bardroid_touch.lua`'s `bardroid_catchup.txt` via
  `GameActivity`), and SDL2's display size answers that follow fold/unfold (the game window's size: SDL keeps the
  startup screen, the engine's screen matrices went wrong after a fold), and in the low-memory mode
  (`BARDROID_FBO_UNCOMPRESS`) a `dlsym` wrapper around the engine's GL lookup that stores a compressed texture
  uncompressed when it is attached to a framebuffer, and through the same wrapper on phones (`BARDROID_TEX_ZERO`) new RGBA
  textures made with zeros, as Mesa's recycled buffers hold old pictures, and the map's compressed ground tiles uploaded
  from a copy of their pixel buffer's bytes (the engine maps that buffer unsynchronized for the next tile while Mesa
  still copies from it: white blocks after a camera jump); `BARDROID_TEX_LOG=1` in dev-env.sh logs the engine's
  textures (64x64 or more) and GPU buffers (64 KB or more); `tools/pace-test.ps1`, `tools/pad-test.ps1`).
- `LobbyBridge` — stand-in for BAR's PC launcher behind the lobby, on by default (Chobby's `WG.Connector`, sl-connection.json):
  web links, the lobby's downloads, replay info for the Replays tab (HANDOFF "Next steps"), and Replays' Open Folder,
  "Add" on a phone: `ReplayImportActivity` (Android's file picker, .sdfz copied into demos/, the lobby's list made again). Test it against the real
  lobby on the laptop with `tools/lobby-bridge-test.ps1` (~30 s, isolated write dir).
- `MapStore` — the map storage limit (launcher Map storage, 3 GB by default, Kailil 2026-11-11): each map's last use
  from the engine's `[CAS::GASCB] Archive file=` line (GameService; `/data` is noatime), the maps played longest ago
  deleted before an engine starts.
- `PerfLog` — once a minute while a game runs, `[perf]` in launcher.log: thermal status, GPU/CPU clocks and caps,
  memory (the GPU driver's too, `GpuTotal`); `bardroid_touch.lua` logs `[bardroid-perf]` (fps, slowest frame, frames of each second) to infolog.
- `app/src/main/jniLibs/<abi>/` — prebuilt helpers, committed: from `tools/fetch-prebuilts.py <abi>` (Termux talloc,
  shmem and ANGLE, Debian busybox), `tools/build-proot.py <abi>` (proot + loader, NDK build with our ioctl filter; run
  after fetch-prebuilts, it links its talloc/shmem) and `tools/build-virgl.py <abi>` (virglrenderer + libepoxy, NDK
  build with our DXT fix).
- `Updater` + `docs/UPDATES.md` — every lobby/skirmish start updates engine, game and lobby like BAR's PC launcher
  (its launcher config), re-applies the Android layer (each tweak logs `!!! ANDROID LAYER` when its target is gone)
  and rolls back a set that fails fast on its first start. Launcher setting "Update BAR at every start".
- `KeyboardShortcuts` — Android's, One UI's and DeX's keyboard shortcuts kept out of the game (HANDOFF "Keyboard
  shortcuts"); mouse and key delivery stay Termux:X11's (Kailil: they work). Android 16.1 keyboard capture
  (`CAPTURE_KEYBOARD`), Samsung's Meta key request, keys in LorieView's pre-IME pass; Termux:X11's KeyInterceptor
  accessibility service as the player's fallback. `GameActivity.handleKey` (pre-IME and the service) and
  `dispatchKeyEvent` route keys: gamepad, Android's own keys, the system Back (Escape after the soft keyboard), the
  rest to Termux:X11.
- `RtsTouch` (finger gestures) + `assets/bardroid/bardroid_touch.lua` (smoothed camera, continuous pinch zoom, BAR's
  interface scale per Fold screen, long-queue drawing, "is the pointer on the interface" answers, the catch-up mode,
  the engine's unread G-buffer passes off: map while `AdvMapShading` is 0, features always); `GameActivity`
  wires them up. In the lobby `assets/bardroid/bardroid_lobby_touch.lua` (a LuaMenu widget; Chobby's
  `loadLocalWidgets`, set by launch-bar.sh): a drag on a list scrolls it, a tap on a server shows its details first, a
  tap on a text box asks for Android's keyboard and a long press (the right button) on a chat's box for speak to chat
  (`bardroid_lobby_ask.txt`, RtsTouch `lobbyAskStep`; in a game the Settings copy's search field asks the same way
  through `bardroid_touch.lua`'s `WG.BarDroidAskKeyboard`, "keyboard g<id>", read for a second after a finger lifts),
  upright the battle room's buttons in its right column (the rules
  box the middle's height, `roomButtonsRight`) and the server list's counts clear of the rank icon, a
  joined server's settings that stop the app's controls show as a warning, and the pad's Start (Scroll Lock from
  `ControllerBridge`) switches the lobby's scale between 100%, launch-bar.sh's default, and 130%
  (`tools/lobby-touch-test.ps1`). `assets/bardroid/bardroid_players.lua`: BAR's player list small until tapped (WG.advplayerlist_api).
  `assets/bardroid/bardroid_layout.lua`: the layout editor (three fingers held → RtsTouch `act hud`, or `/hud` typed in
  `bardroid_chat.lua`'s own typing box); panels register with `WG.BarDroidLayout` and read their settings from it;
  BAR's own panels only through their `WG` setters (BAR's sandbox keeps user widgets out of BAR's code).
  `assets/bardroid/bardroid_buildmenu.lua`: BAR's Build menu copied by `tools/make-buildmenu.py` (do not edit; rerun it
  after BAR changes its gui_buildmenu.lua; `--adb` reads a phone's release) with a size and place hook for the editor;
  launch-bar.sh runs it in place of BAR's in every game: the pad's RB is in it. When an update changes BAR's file the phone
  makes the copy again itself (`Installer.remakeBarCopy`, `BuildMenuPatches`, the tool's `bardroid_buildmenu.patches`); if
  a patch finds no place the old copy runs and launch-bar.sh logs `!!! ANDROID LAYER ... build menu`, and only a copy BAR
  removed in a game gives way to BAR's own (`.bardroid-buildmenu-failed`); the controller game keeps v0.8.5's, renamed "Build menu
  (controller)" by `tools/build-gamepad-game.py`, in `WG.buildmenu`, and runs the copy beside it as
  `WG.bardroidBuildmenu`, shown while the app's gamepad controls have the pad (`WG.BarDroidOwnsBuildMenu`).
  `assets/bardroid/bardroid_ordermenu.lua`: BAR's Order menu copied the same way by `tools/make-ordermenu.py` (Kailil,
  2026-11-03: online "behave like offline"): v0.8.5's even layout while the pad hides orders (`WG.BarDroidPadOrders`),
  `WG.ordermenu.droidCells`, an IsAbove; launch-bar.sh's `order_menu` runs it in place of BAR's (`.bardroid-ordermenu`,
  `!!! ANDROID LAYER ... order menu`); it stands down in the controller game, whose v0.8.5 menu is "Order menu (controller)".
  `assets/bardroid/bardroid_missioninfo.lua`: BAR's Mission Info (a scenario's briefing) copied the same way by
  `tools/make-missioninfo.py`: no wider than the screen, upright above the portrait dock; its GetInfo `replaces`
  BAR's (BAR's widget handler then skips BAR's, and brings it back if the copy is not running; the order list alone did
  not keep a widget BAR had never seen run from starting); launch-bar.sh `mission_info`, `.bardroid-missioninfo`.
  `assets/bardroid/bardroid_teamstats.lua`: BAR's TeamStats panel (its graphs: the awards' Show Graphs, the top bar's
  Statistics) copied the same way by `tools/make-teamstats.py` (a red close button at its header's right end): upright the screen's width, between the top bar and the
  dock; sideways on a tall phone as large as fits, the dock aside meanwhile (`bardroid_portrait.lua` SP.windowOpen), above
  the split dock otherwise; launch-bar.sh `team_stats`, `.bardroid-teamstats`. `assets/bardroid/bardroid_options.lua`: BAR's Options
  (Settings) copied the same way by `tools/make-options.py`, laid out for a phone (upright a tab grid over a full-width
  list, sideways as large as fits, a close button); it needs BAR's widget handler, so it runs only as a game widget
  (`BARDROID_GAME_WIDGETS=1`, the engine branch) and is parked in `bardroid-parked` otherwise (launch-bar.sh
  `options_copy`, `.bardroid-options`; BAR's own Options then). While a building is picked its page strip is the shape strip (ONE,
  LINE, GRID, BORDER) and a PLACE button (rotate, cancel) covers the order menu; `bardroid_place.txt` tells `RtsTouch`
  the shape, PLACE and the spot a map tap picked ("spot" lines back): PLACE is a click on the spot (a Shift click with QUEUE on; without, it replaces the builders' orders and BAR lets go of the building, as a mouse's click, Kailil 2026-11-19), drags hold
  Shift (+Alt, +Ctrl) for BAR's own build drag. With ONE a drag moves the building ("spot", later "nudge"), a held
  finger makes a GRID ("grid start/by"; the file's "grid" corners: PLACE or a double tap replays BAR's build drag with
  Shift+Alt: the left button stays down from the GRID's start to PLACE, the engine draws and places it). `bardroid_pad.lua`'s
  QUEUE button is a sticky Shift for fingers (`RtsTouch.applyQueue`). A three-finger tap (double: the keyboard) and the pad's LB held +
  RB twice are speak to chat (`VoiceChat`: Android's SpeechRecognizer, the words hex-encoded as a `voice` line to
  `bardroid_chat.lua`); LB held + RB three times a spoken ping label (`voiceping`, `bardroid_pad.lua` voicePing); the touch dock's PING
  held is one too (RtsTouch `dock_voiceping` from the dock file's "ping" rect; `bardroid_portrait.lua` pingT takes the
  words first), PING tapped twice speak to chat (`dock_chat`, the button flips to CHAT until `voice_off`). The pad's
  own modes (`bardroid_pad.lua`, "modal dgun|share" in bardroid_pad.txt): v0.8.5's D-gun mode and the share list;
  a click at a point the game asks for ("clickat") is `PadGame.clickIfAsked`. The late-game resolution drop
  (`Prefs.lateDrop`): `bardroid_touch.lua` writes `bardroid_scale.txt`, `GameActivity.updateRenderDrop` shrinks the
  X screen (floor: 70 % of the render resolution, `RENDER_DROP_FLOOR`). With an engine-branch build, `BARDROID_GAME_WIDGETS=1` in dev-env.sh makes
  launch-bar.sh move the app's widgets to `bardroid-ui/LuaUI/Widgets`, which that engine shows LuaUI as part of the
  game archive (`BarDroidGameWidgetsDir`): BAR loads them as game widgets, outside the user widgets' sandbox (Kailil,
  2026-11-06, on a BAR developer's advice); `pad-test.ps1 -Engine <build>` tests it. `bardroid_padspeed.lua`: the pad's drawing speed by
  zoom and its tuner; `bardroid_padfp.lua`: first person on the pad (BAR's Set Target fires it, online-safe). `bardroid_retreat.lua`: hurt units
  fall back, a hurt commander retreats with its army covering it (GiveOrder; the dock's AUTO RETREAT, docs/DELIVERY.md).
  `bardroid_camctl.lua`: the one-finger camera (Kailil, 2026-11-19): a camera knob over the map and edge rails (an L at
  the map's bottom corner, each half its side: the upright one zooms, the foot's one turns; left or right side; Minimal
  in white or the dock's grey; steps scaled by the finger's speed in RtsTouch, camStepGain, and a sensitivity), each with
  a switch under Settings' Control tab ("Camera with one
  finger": WG.options.addOptions, which BAR's model puts under Custom; the options copy's droid.regroup moves options
  with `droidGroup` into that tab), Spring config `BarDroidCamKnob` / `BarDroidCamRails`; it writes
  `bardroid_camctl.txt` (knob, zoom, turn rects), RtsTouch's CAM state takes a touch that comes down on one and sends the
  dock pad's "zoom"/"rot" lines ("camheld" lights the part; the turn rail's "rot" the other way from the knob's, Kailil
  2026-11-19); the knob in the layout editor as "Camera knob". The file reads "none" (no rects, the touches go on to
  what is under) while hiddenNow: GUI hidden, a pad or mouse the input, BAR's quit screen (WG.topbar.showingQuit), the
  app's Statistics or Mission Info open (OVER_WINDOWS: upright they lie over the knob and rails), the dock aside for
  one of BAR's big windows, or the layout editor open.
  `bardroid_presets.lua`: the dock's PRESETS (2 x 2 over its grid, then a map tap: zigzags, formations; WG.BarDroidPresets).
  `bardroid_automex.lua`: the commander picked and an extractor chosen, the free mex spots in its weapon range queued
  (BAR's resource spot API, as its Area Mex). `bardroid_topbar.lua`: upright, BAR's top bar buttons over its hidden
  resource bars and indicators do their action through WG (BAR's Top Bar takes those presses; docs/upstream). In the controller game, once the pad is used (`WG.BarDroidPadOnly`, from `src pad` until three taps in
  6 s or the pad goes away: `RtsTouch.source`, `act fingers`), the app's build menu shows only when RB opens it. While the pad is in use
  `bardroid_pad.lua` hides the orders the pad has buttons for (BAR's `setDisabledCmd`, undone at the next start).
  Laptop checks start the engine with `toolchain.ps1` Start-Engine (no focus) and `WindowPosX = $OffScreenX` (off every
  screen): they never take Kailil's keyboard or cover his windows; the checks that move the real mouse pointer run only
  with `-Pointer` (touch-widget-test, laptop-tests) or `-PointerOnBattle` (profile-benchmark).
  BAR's sandbox refuses `/option`, widget toggles and engine restarts from user widgets: settings go
  in through `launch-bar.sh` instead. `tools/touch-widget-test.ps1` runs the widget in a real skirmish on the laptop
  (~1.5 min): pinch, twist, tilt and drag on the camera, and the map/interface answers; run it after touching either.
- `termux-x11/` — upstream checkout (`tools/fetch-termux-x11.*`) with `patches/0*.patch`: 0001 CmdEntryPoint loads
  libXlorie.so from `TERMUX_X11_LIBXLORIE_PATH`; 0002 Windows-host CMake build; 0003 the X server resizes full-screen
  top-level windows with the screen (fold/unfold; there is no window manager); 0004 our own knock port 17892 on
  loopback (the Termux:X11 app, if installed, knocks on 7892 every 250 ms); 0005 `LorieView.setCursorVisible`
  (`RtsTouch` hides the pointer while two or more fingers are down); 0006 `LorieView.maxScaledViewPixels` and
  `maxScaledShortSide` (the X screen at most 2100x900's pixels and 1080 lines, display scale 100%: folded 2100x900,
  unfolded 1198x1080; `GameActivity.MAX_SCREEN_PIXELS`/`MAX_SCREEN_LINES`, `BarApp` display scale v4); 0007 `LorieView.setUpscale`:
  the X screen enlarged onto the display through Qualcomm's SGSR 1 (`assets/sgsr`, BSD-3-Clause; `GameActivity`,
  settings "Sharper upscaling" and "Compare upscaling"; plain filtering if the GPU refuses the shader); 0008 the
  display's vsync shared with the frame cap (`/tmp/bardroid-vsync`, `BARDROID_VSYNC_FILE`) and a picture held for the
  cap's vsyncs at least (`lorieMinHold`), `[display] pictures held` once a minute in launcher.log; 0009 X's root
  cursor (the "X" over the black screen and the engine's splash) drawn as nothing until the game sets its pointer;
  0010 a summary under each of its preference screen's entries (Output, Pointer, Keyboard, Other), and plain words
  for Output's soft keyboard resize ("Reseed") and picture-in-picture entries and the "Needs ..." notes of greyed-out
  ones (upstream's plain double quotes, which Android drops, made them unreadable); 0011 one display draw per picture
  (the engine's animated pointer: a new pointer image alone waits up to 100 ms for the next picture; identical pointer
  sets and moves dropped), `[display-cost]` lines in logcat every 5 s (the X server's CPU copy of each picture, the
  display pass's GPU time, draws per picture), and `LorieView.surfaceAtScreenSize` (dev: `files/bar/.bardroid-display-scales`,
  the SurfaceView at the X screen's size, the display hardware scales instead of SGSR); 0012 the preference screen's
  version line: "1.03.01, built <yyyy-MM-dd> from BAR Droid <commit>" (the commit is the building checkout's; 0016
  adds " + changes" when its tracked files differ from that commit); 0013
  hides the user-action entries that never act here (Back: GameActivity makes it Escape; the notification's tap and
  buttons: BarApp keeps Termux:X11's notification away); 0015 Termux:X11's build files in the syntax Gradle 10 keeps
  (`propName = value`; its two git calls through `providers.exec` from the root, so the version line still names
  BAR Droid's commit); 0017 "Android's volume control" for upstream's lowercase "android ..." in the volume and media
  keys' "no action (...)" (the app's own strings.xml overrides the rest of that screen's words); 0018 hides Output's
"Screen orientation", which the launcher's Play upright writes at every start (`KeyboardShortcuts.applyTermuxPrefs`), 0019
Keyboard's "Intercept system shortcuts" and scancodes workaround, which its "Keyboard shortcuts go to the game" writes, 0020
Output's resolution and filtering lists shown in capitalised words (Native, Scaled; Bilinear (smooth)), the stored values unchanged. docs/CONTAINER-COST.md has
  what proot, the X server and the display pass cost; `tools/container-cost/` the probes (`measure.ps1`: a late 8v8
  with all of them).
- The app icon opens the lobby (`StartActivity`, setting "Open the lobby when the app starts"; the launcher is a task of
  its own, `taskAffinity=".Launcher"`, so the icon never just brings it back; a lobby that failed fast shows it once);
  long-press the icon → "Launcher" (`res/xml/shortcuts.xml`) for the launcher screen. Regenerate a patch with `git diff`
  inside `termux-x11/` (LF endings; git through `toolchain\env.bat`).
- Gamepad: until 2026-11-06 singleplayer played Kailil's BAR Controller Support v0.8.5 1:1 as BAR's developer game
  (`tools/build-gamepad-game.py` → `assets/gamepad/`); Kailil then: "We can pull out the 0.8.5 gamepad toggleer thing
  now. Since our gamepad controlls are so good now": every game plays BAR's released game with the app's controls,
  `Installer.removeGamepadGame` deletes an installed `games/BAR-gamepad.sdd`, and the v0.8.5 checks left in the widgets
  (`bardroid_game.txt`, `modV085`) never fire. `ControllerBridge` still streams BARCTRL1 over UDP 28777;
  in every game `PadGame` rebuilds v0.8.5's controls from an X mouse and keyboard (the pointer held in
  the middle, the camera through `bardroid_touch.lua`'s pad lines; which game it is: `bardroid_game.txt`) and sends
  the rest as actions to `assets/bardroid/bardroid_pad.lua` (the order menu on the pad, groups, idle units, LB
  orders; it writes `bardroid_pad.txt`: which menu has the pad, pregame, what is picked); in the lobby the pad is a
  mouse (its D-pad from control to control: `bardroid_lobby_touch.lua` reads `lobby_nav_*` from the touch log), BAR's
  lobby over a game too (`bardroid_overlay.txt`, `RtsTouch.lobbyOverGame`).
  `PadGame` runs on the laptop
  against a made-up pointer (`tools/padgame-test.ps1`, `PadMouse`/`PadButtons` keep it free of Android classes). Change v0.8.5 itself only in `C:\Tools\BARGAMEPAD`.
  Packaged from BARGAMEPAD branch `controller/codex-v085-perf` (performance work, same behaviour; HANDOFF.md
  "Gamepad"); measure with `tools/profile-gamepad-game.ps1` on the laptop before and after any change to it.
- `tools/container-shell.bat` — root shell (or one command) in the device's container via `files/container.sh`;
  long-press **GL check** in the app keeps X + GPU server up without the game.

## Build / run (Windows; everything portable in the toolchain folder: `scripts\env.bat` picks `BARDROID_TOOLCHAIN`, else `..\toolchain` = `C:\Tools\BARANDROID\toolchain` here, else `toolchain\` in the checkout)
The launchers are in the repository root (the copies in `C:\Tools\BARANDROID` only call them); README.md is the
newcomer's version of this section. APKs land in `apk\` beside the toolchain folder (`BARDROID_OUT` overrides).
```
"Install Toolchain.bat" --accept-licenses     # once; also fetches + patches termux-x11
"Build APK.bat"                               # emulator build (x86_64);  "Build APK.bat phone" = arm64
"Install on Phone.bat"                        # the phone build onto the adb-connected phone ("Pair Phone.bat": wireless)
"Run in Emulator.bat" [-no-audio|-wipe-data]  # AVD bardroid-x86_64: boot, install, open
"Get Logs.bat" [phone]                        # launcher.log, infolog.txt, glcheck, pulse.log, logcat -> logs\
powershell -ExecutionPolicy Bypass -File tools\laptop-tests.ps1   # every laptop check, ~5 min (BAR install read only)
powershell -ExecutionPolicy Bypass -File tools\pace-test.ps1      # the pace library's window events, on the phone
powershell -ExecutionPolicy Bypass -File tools\pad-test.ps1 [-Online|-Dgun|-Share|-Chat]   # the app's gamepad controls with no gamepad: a virtual Xbox pad on the dev phone, ~2 min; -Online: BAR's released game with user widgets' orders forbidden, as a host can; -Dgun: the same game, v0.8.5's D-gun mode (LB + RB + R3) through the app's clicks and the share list's chord; -Share: the share list's units / metal / energy (the AI's team as a stand-in teammate, BAR's share recorded), screenshots in build\pad-share-*.png; -Chat: what speak to chat sends (BAR's chat sends recorded, no pad)
powershell -ExecutionPolicy Bypass -File tools\ui-screenshot.ps1 -Screen inner|cover   # BAR's HUD at a Fold layout
powershell -ExecutionPolicy Bypass -File tools\catchup-test.ps1 [-Warmup 300]       # a spectator joining late, ~5 min
powershell -ExecutionPolicy Bypass -File tools\lobby-touch-test.ps1                # the lobby widget (finger scrolling, server details, the warning, the scale, the quick Skirmish's four pages: Back and Advanced at their foot, upright as tall as Next, Select Map's maps; a scenario's page: upright its values left of the map; the Keys window: upright as tall as its tabs and picture), ~1 min
powershell -ExecutionPolicy Bypass -File tools\lobby-phone-test.ps1                # the same on the dev phone, plus a virtual pad's Start; nothing on the laptop, ~1 min
powershell -ExecutionPolicy Bypass -File tools\dock-phone-test.ps1                 # the upright touch dock by real taps on the dev phone: the build grid's first building placed (PLACE 2.6 s after the spot), PLACE on a blocked spot, the D-gun's FIRE / AUTO swipes, MOVE's stop and its X, the STRAFE preset dragged, the wind and tide boxes' first tap, Area Mex's circle by a tap, then a drag (mexes queued), the energy panel's share knob dragged (a whole percent), SEND ENERGY's teammate picker (stand-ins, its rows whole); any screen shape (wm size 1080x1198: the Fold7 unfolded); ~3 min
powershell -ExecutionPolicy Bypass -File tools\touch-phone-test.ps1                # the touch camera at the map's edge on the dev phone (drags on the map, over the void, across the edge (one line, and a finger's: a line a frame), over the sky; a pinch over the void; under BAR's lobby over the game the camera still and the dock aside), driven through the touch log; ~2 min
powershell -ExecutionPolicy Bypass -File tools\fp-save-test.ps1                    # a spectator's 1st person through BAR's mid-game settings save, on the dev phone, ~1.5 min
powershell -ExecutionPolicy Bypass -File tools\stripes-test.ps1 [-Pairs 3]         # the interface's stripes: skirmishes on the dev phone alternating launch-bar.sh's UBWC off (FD_MESA_DEBUG=noubwc, the default) and on, screenshots + montage in build\stripes-test (DELIVERY.md), ~3 min a start
powershell -ExecutionPolicy Bypass -File tools\spectate-test.ps1 [-Replay <file.sdfz>] [-Cost] [-Settings @{Key=1}]   # spectating by touch (bardroid_spectate.lua) in a replay, ~2 min; -Cost: its ms and KB per frame; -Settings: engine settings (run it with -Command for a hashtable)
powershell -ExecutionPolicy Bypass -File tools\fp-tuner.ps1 [-Replay <file.sdfz>] [-SkipTo 240]   # Kailil sets the 1st person camera (laptop); Save -> build\fp-tuner\data\LuaUI\Config\bardroid_fp.lua -> bake into bardroid_spectate.lua FP
powershell -ExecutionPolicy Bypass -File tools\profile-big-game.ps1 [-AIs 6] [-FastMinutes 25] [-ProfileFastAtMinute 15] [-Functions] [-Gadgets] [-Settings @{Key=1}]
                                                                         # where a big game's CPU goes (widgets, unsynced gadgets, engine timers)
powershell -ExecutionPolicy Bypass -File tools\remake-check.ps1                    # the phone's remake of the menu copies (BuildMenuPatches) byte for byte against the shipped ones, and every phone patch (phone-*.lua.patch, phone-lua-check.py) against the same release, BAR's files from the dev phone; after make-buildmenu.py / make-ordermenu.py --adb and after a BAR update
python -I tools\lua-locals.py                                           # the app's widgets under Lua's 200 top-level locals (over it a widget does not load; luacheck misses it)
powershell -ExecutionPolicy Bypass -File tools\make-loadscreen-upright.ps1 -Source <BAR's MenuLoadscreens/loadscreen.png>   # the lobby's first picture upright (loadscreen-upright.png: the word in the quarter Chobby shows, Lanczos + unsharp mask)
python -I tools\demo-rate.py <replay.sdfz>                               # game message bytes per game-second
python -I tools\tex-memory.py <launcher.log> [--top 25]                  # the engine's textures and GPU buffers summed (a game run with BARDROID_TEX_LOG=1 in dev-env.sh)
python -I tools\worklog.py                                               # docs/WORKLOG.md: Kailil's messages, Claude's answers, time spent
powershell -ExecutionPolicy Bypass -File tools\publish-check.ps1 [-Apk <release.apk>] [-NoHistory] [-SelfTest]   # before anything goes public (docs/DELIVERY.md)
powershell -ExecutionPolicy Bypass -File tools\github-sync.ps1 [-Release] [-NoEngine]   # after every commit (Kailil, 2026-11-18): every branch to the private UnderarmCape/bar-droid, the engine's bardroid/* to UnderarmCape/bar-droid-engine; -Release after a Fold7 install: the APK as the rolling pre-release latest-build
"Build APK.bat" phone release                                            # the public build: own icon, release key (local.properties), versioned name
powershell -ExecutionPolicy Bypass -File tools\phone-bench.ps1 [-Scale 100|85|70] [-Cap 0|30|60] [-Label text] [-Profile widgets|gadgets] [-Settings @{Key=1}] [-DisplayScale 150|120|100] [-WidgetsOff "Name"]
            # BAR's "Benchmark BAR" scenario on the phone, unattended (launcher "Benchmark" button, or
            # `am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench`): warms the phone up into the
            # throttled state a late game plays in (Kailil: measure hot, back to back), then Sim/Draw/Update ms per frame,
            # game speed, clocks every 5 s (tools/phone-clocks.sh) and the busiest threads -> build\phone-bench.csv; one
            # run at a time across sessions (lock C:\Tools\BARANDROID\phone-bench.lock). On the dev phone (the Fold7: not
            # unless necessary, and never while Kailil uses it).
powershell -ExecutionPolicy Bypass -File tools\devphone.ps1 [status|connect|dark|bench|watch]   # the dev phone's adb links and screen
powershell -ExecutionPolicy Bypass -Command "& tools\phone-memory.ps1 -Settings @{ CompressTextures = 1 } [-Scale 70] [-Seconds 150] [-Label x]"
            # the engine's memory on the dev phone in a skirmish (GPU, heap, swap, free memory, killed or not) -> build\phone-memory.csv
powershell -ExecutionPolicy Bypass -File tools\profile-benchmark.ps1 [-NoProfilers] [-AlsoOff "Widget"] [-Functions -Detail "Widget"] [-PointerOnBattle]
            # the same scenario on the laptop as the phone runs it, every widget, unsynced gadget and engine timer logged
```
Ad-hoc commands: `cmd /c "call C:\Tools\BARANDROID\bar-droid-app\scripts\env.bat && <command>"` (PowerShell tools: dot-source
`tools\toolchain.ps1` for `$TC`) (`%VARS%` on that line expand
before env.bat runs; use literal paths). `adb shell` quoting through PowerShell is fragile: `toolchain.ps1`'s
`Send-AppFile` (a file into the app's folder) and `Invoke-AppScript` (a script run there as the app) go through
`adb push` and /data/local/tmp; piped into `adb exec-in` the input now and then never arrived or came cut short.
The lobby tests never log in (Kailil, 2026-10-28: "dont login and disable autologin on the laptop when you run the
tests"): BAR's server allows one session per account, and a test's login ended his game on the phone. Their lobby
starts offline (`tools\toolchain.ps1` Write-LobbyConfig: no login, automatic login off; `tools\lobby-login\
bardroid_login_wait.lua` disconnects one that connects anyway). `C:\Tools\BARANDROID\bar-lobby-login.txt` (Kailil's,
outside the repository) is no longer read; never read it aloud, print or commit it.
Laptop checks start spring from `build\engine\<engine>` (`tools\toolchain.ps1` Get-EngineDir), never from BAR's
install folder: Kailil's has ReShade beside `spring.exe`.
Never install tools globally or write to AppData/the profile. The emulator writes `.emulator_console_auth_token` to
the real profile anyway; `Run in Emulator.bat` deletes it (also a stale one after a crash).
Toolchain: AGP 9.3.1, Gradle 9.8.2 wrapper, NDK 29.0.14206865, CMake 3.22.1, JDK 21. One ABI per APK.
Logcat tags: BarDroid/app svc install x11 engine rootfs virgl proc input, plus LorieNative, CmdEntryPoint.

## Rules of the road
- The work log is kept from now on (Kailil, 2026-10-28: "i want the time logging from now moving forward as well for
  statistics"): run `python -I tools\worklog.py` before the last commit of every work session and commit
  `docs/WORKLOG.md` and `docs/worklog/` with it. Private terms it must hide go in `..\worklog-redact.txt`, never in
  the repository. The road to a public release: `docs/DELIVERY.md`.
- GitHub, private (Kailil, 2026-11-18: "Get this project fully on github as private and make sure that our new builds
  and work is reflected via github as well"): after each commit `tools\github-sync.ps1` (every branch to
  UnderarmCape/bar-droid, the phone engine's bardroid/* branches to UnderarmCape/bar-droid-engine); after a build goes
  on the Fold7, `-Release` too (the APK as the rolling pre-release latest-build). Never force a branch; the
  repositories stay private unless Kailil says otherwise (going public: publish-check and the fresh-history question
  in docs/DELIVERY.md first). The work log's day pages are the conversation archive there.
- BAR's game itself (CC-BY-NC-ND) comes from `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` only,
  as BAR's launcher fetches it. Kailil, 2026-11-06: BAR's developers cleared him ("full authority to do whatever
  necessary to get this game android ready"; they are bringing him onboard), so content made from BAR's art for
  phones (made ahead of time on the laptop rather than on players' phones) may ship with the app; credit BAR in
  NOTICE.md. Anything the simulation or the archive checksums see stays BAR's own (online play).
  Kailil's own builds carry his edit of BAR's launcher icon (an Android robot added; NOTICE.md), personal use only
  (NoDerivatives): it lives outside the repository (`C:\Tools\BARANDROID\personal\res`, local.properties
  `bardroid.personalRes`); public builds (`-PbardroidPublic`, or no such folder) get the project's own icon. An APK
  with his icon must not be published. The app is named "Beyond All Reason".
- The engine is pinned to the version BAR's servers run (launcher config: https://launcher-config.beyondallreason.dev/config.json):
  BAR's official build, or its phone build (Kailil, 2026-11-13, docs/ENGINE-DEFAULT.md): the engine branch
  (`hailmary-work/recoil-src`, `bardroid/sim`; bar-droid-engine docs/ENGINE-SIM.md) built for that version, put in
  the APK by `tools/phone-engine-release.ps1` (local.properties `bardroid.phoneEngine`), set up as
  `engine/recoil_<version>-phone` by `Installer.installPhoneEngine`, started by launch-bar.sh unless the launcher's
  "Phone engine" is off (a build that cannot run on the phone, no `[BarDroidSim]` line before its error exit: the
  official one). Its synced changes stay exact and
  run online only once the rewrite has its replay count (the engine's `BarDroidSimAllowed`: off with a remote host or
  other players). A new phone build ships only after the gate (ENGINE-DEFAULT stage 2: server replays with 0 desync
  warnings, the phone tests); no APK carrying one goes out before the branch's source is public (NOTICE.md).
- Upstream PRs to RecoilEngine/CircuitAI must reference an accepted issue and disclose AI assistance (their `AI_POLICY.md`).
- Device data layout: `files/rootfs` (container), `files/bar` (engine write-dir, bound at `/root/bar`), `files/logs`, `Android/data/<pkg>/files/import`.
- When something fails on device, first read `files/logs/launcher.log` (everything, including child process output) and `files/bar/infolog.txt`.
- Paths handed to proot must be canonical (`Paths`): in the app's mount namespace `/data/user/0` is a symlink to `/data/data`.
- Never keep exec'able paths into `nativeLibraryDir` on disk (symlinks, saved paths): it moves on every app update.
- Child processes go through `Proc`; Stop SIGKILLs every process of the app's UID (proot ignores SIGTERM and orphans
  its tracees). The player's Stop and a swipe from recent apps first ask the engine to quit (`Proc.endEngine`: SIGTERM
  to spring, again 1 s later for BAR's quit dialog; up to 20 s; then launch-bar.sh's last seconds, up to 5 s: its widget
  checks and the infolog's copy into logs/): the replay is written only as the engine ends, and a killed game left an
  empty .sdfz. Still loading: stopped at once (the quit waits for the loading's end; nothing to keep). `XServer`/`VirglServer` inherit the app environment (app_process and EGL need it).
- No `--kernel-release` for proot on kernels >= 4 (its kompat extension traps every futex: half the render thread).
- `MaxParticles` stays >= 10000 (BAR's minimum): lower values kill unsynced LuaRules and no unit is drawn.
- proot's seccomp filter must not trap syscalls proot does not act on (each trap = two ptrace stops; GPU drivers make
  hundreds of ioctls per frame). A stopped call costs 30-460 us (`tools/container-cost/trapbench`); proot also stops
  `getsockopt`, `close`, `recvmsg`/`sendmsg` and every path call: never add such calls to a per-frame path.
  Phone Mesa must be lfdevs 27.0.0-devel-20261025 or newer (KGSL present fence: flicker).
- The lobby needs `chobby_config.json` in the write dir (launch-bar.sh writes it, as BAR's launcher does).
- Compare frame rates with the developer fps widget (`tools/dev/bardroid_fps.lua`, docs/HISTORY.md) and the laptop awake: Modern Standby throttles ~2.5x.

## Open risks (see HANDOFF.md)
Emulator: ~20 fps at best (laptop awake), limited by virgl/ANGLE host round trips; memory tight (12 GB guest, little
host RAM left; the low-memory killer once took the app). Phone: RAM (~5–6 GB a match), BAR's UI on the near-square
inner display, BAR's own panels without an `IsAbove` take a finger drag for a pan (the app's menu copies answer it;
the top bar and BAR's windows are covered: `bardroid_touch.lua` overBarInterface, `tools/touch-widget-test.ps1`;
v0.8.5's menus in the controller game are its own; BAR's button panels a finger taps, the replay speed column, the vote
panel and the pre-game Ready buttons, register a rect function in `WG.BarDroidTapPanels` from their phone patches: the
hover file's answer 3, the pointer hidden after a tap as on the interface while a drag still pans as on the map,
RtsTouch HOVER_TAP; an IsAbove there made drags mouse drags), touch-only play (later).
