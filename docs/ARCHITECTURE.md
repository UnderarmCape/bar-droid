# How BAR Droid works

BAR Droid runs Beyond All Reason's official, unmodified Recoil engine (the arm64 Linux build) on an Android phone,
without root. The app is a small Android program around four borrowed pieces: a Debian container, an X server, a
Mesa GPU driver and BAR itself. This page is the map; [HISTORY.md](HISTORY.md) has the measurements and decisions
behind each part, [UPDATES.md](UPDATES.md) what the app changes in BAR's settings.

```
 Android app (Java)                              Debian trixie container (proot, no root)
 ┌──────────────────────────────┐                ┌────────────────────────────────────────┐
 │ LauncherActivity  Installer  │  starts        │ launch-bar.sh: GPU env, Android layer  │
 │ GameService (foreground)     │───────────────▶│   over BAR's settings, then            │
 │ GameActivity: shows X screen │                │ spring (Recoil engine, unmodified)     │
 │   RtsTouch, ControllerBridge │◀── files ─────▶│   LuaUI widgets bardroid_*.lua         │
 │   AudioPump ◀── FIFO ────────│◀───────────────│   OpenAL Soft wave writer              │
 │ XServer (Termux:X11 lorie)   │◀── X11 ────────│   SDL2 window, OpenGL via Mesa         │
 └──────────────────────────────┘                └────────────────────────────────────────┘
                                                   libbardroid_pace.so (LD_PRELOAD)
```

## The pieces

- **Container.** Debian trixie in `files/rootfs`, run through Termux's `proot` (built by `tools/build-proot.py`,
  shipped as `libproot.so` because Android only executes files from the app's native library directory). `Proot`
  builds the command line as proot-distro does. `setup-container.sh` installs Debian's packages, Mesa, the engine
  and BAR's content on first run; BAR's write dir `files/bar` is bound at `/root/bar`.
- **Display.** Termux:X11's X server (`lorie`, GPL-3) is compiled into the APK from `termux-x11/` plus
  [patches/](../patches/) and started with `app_process` (`XServer`). `GameActivity extends
  com.termux.x11.MainActivity` shows its screen. The patches add fold/unfold resizing, a private knock port, cursor
  hiding under two fingers, a pixel cap for the unfolded screen, Snapdragon GSR upscaling, the display's vsync for
  the frame cap, no "X" root cursor before the game sets its pointer, and one display draw per picture (the engine's
  animated pointer no longer redraws the whole picture). Each picture reaches the screen as: the engine's Mesa renders
  into a dma-buf, the X server copies it on the CPU into the root window (an AHardwareBuffer: Android's EGL cannot
  import a dma-buf), and the app's renderer draws that through SGSR onto the SurfaceView, which the display hardware
  shows. What each step costs: [CONTAINER-COST.md](CONTAINER-COST.md).
- **Graphics.** Phones: Mesa for Android containers (Freedreno `kgsl` / Turnip + Zink, lfdevs builds); with Freedreno,
  `launch-bar.sh` turns Adreno's compressed render targets off (`FD_MESA_DEBUG=noubwc`: panels BAR draws into textures
  of their own came out in black columns with them, at no measured cost without). The emulator:
  Mesa `virpipe` → our virgl server (`VirglServer`, `tools/build-virgl.py`) → ANGLE → the host GPU, llvmpipe as
  fallback.
- **Frame pacing.** `libbardroid_pace.so` (`tools/pace/pace.c`), preloaded into the engine: the frame cap (no VSync
  wait in Mesa, so CPU and GPU overlap), locked to the display: the X server shares each vsync (termux-x11 patch 0008),
  the swap waits for its slot on that grid, each frame starts as late as the slowest recent frame allows (no added input
  lag), and the X server holds a picture for the cap's vsyncs at least, so 30 fps on a 60 Hz display shows every picture
  for exactly two vsyncs. Also an ioctl answer that puts lfdevs' Mesa on its explicit Present fence (the
  swap stops waiting for the GPU), window HIDDEN/SHOWN events while the game screen is hidden or a joined game is
  caught up, and SDL's display size following fold/unfold. In the low-memory mode it also wraps the engine's GL
  lookup (`dlsym` of `glXGetProcAddressARB`) so that a compressed texture gets uncompressed storage when it is
  attached to a framebuffer (`CompressTextures = 1` otherwise breaks the unit icon atlas: an engine bug).
- **Audio.** The engine's OpenAL Soft writes waves into a FIFO; `AudioPump` plays them with `AudioTrack`. No
  PulseAudio.
- **Input.** Touch: `RtsTouch` turns gestures into lines in files under `LuaUI/Config`, read by
  `bardroid_touch.lua` (camera, pinch, tilt, "is the finger on BAR's interface"); the widgets answer in small files
  there (the pointer's answer, the game, the building picked, the pad's menu), each written whole to a `.tmp` and
  renamed, since the app reads them many times a second. Gamepads: `ControllerBridge`
  streams `BARCTRL1` packets over UDP 28777 to BAR Controller Support (v0.8.5, the singleplayer game); in BAR's own
  game `PadGame` rebuilds v0.8.5's controls from X mouse and key events (the pointer held in the middle, the camera
  through the touch widget's pad lines, the rest as actions to `bardroid_pad.lua`); in the lobby the pad is a mouse.
  In the controller game a triple tap switches between the two. Mouse and keyboard: Termux:X11's delivery;
  `KeyboardShortcuts` keeps Android's own shortcuts out of the game.
- **BAR's settings.** `launch-bar.sh` puts the Android layer over BAR's and the lobby's saved settings at every start
  (phone graphics, interface scale per Fold screen, widget orders and switches) and reports `!!! ANDROID LAYER` when
  a target it edits is gone. BAR's sandbox refuses widget toggles from user widgets, so they go in here. Phones with
  less than 9.5 GB of RAM get a low-memory mode on top (Lua memory pools off, compressed textures, BAR's GL4 unit
  shaders, shore waves and ground decals off; docs/HISTORY.md "Fitting BAR into an 8 GB phone").
- **Updates.** `Updater` updates engine, game and lobby at every start as BAR's PC launcher does (its launcher
  config), re-applies the layer and rolls back a set that fails on its first start. Content only ever comes from BAR's
  CDN (`pr-downloader`).
- **Lobby.** BAR's own Chobby lobby. `LobbyBridge` stands in for the PC launcher behind it (web links, downloads,
  replay info); `bardroid_lobby_touch.lua` makes it finger-friendly.
- **In-game widgets** (`app/src/main/assets/bardroid/`): `bardroid_touch.lua` (camera, perf log, catch-up mode),
  `bardroid_players.lua` (small player list), `bardroid_spectate.lua` (spectating by touch: player cameras, follow,
  presets, 1st person), `bardroid_info.lua`, `bardroid_chat.lua` (chat lines and the typing box),
  `bardroid_minimap.lua` (minimap small until tapped, unfolded), `bardroid_layout.lua` (the layout editor: panels
  register with `WG.BarDroidLayout` and read their settings from it), `bardroid_buildmenu.lua` (BAR's Build menu
  copied by `tools/make-buildmenu.py`: a sizeable 3x3 grid, up to 5 wide on a wide short screen, the touch building's shape strip and PLACE button, the
  gamepad's focus), `bardroid_pad.lua` (the gamepad in BAR's game: the order menu on the pad, groups, idle units, area
  select, LB orders, the touch QUEUE button), `bardroid_padspeed.lua` (the pad's drawing speed by zoom, and its tuner),
  `bardroid_padfp.lua` (first person on the pad), `bardroid_queue.lua`, `bardroid_bench.lua`, `bardroid_lowmem.lua` (keeps BAR's GL4 unit shaders
  off in the low-memory mode), `bardroid_buildrange.lua` (while a building is picked: the engine's build range circle
  of every construction turret made see-through, which the engine then skips, and the 10 nearest the building drawn),
  `bardroid_sensors.lua` (in games of 10 teams or more BAR's sonar, radar and line-of-sight circles at opacity 0 and its
  always-shown jammer coverage off: their GPU cost grows with the square of the units; the player's values back in the
  next smaller game), `bardroid_nano.lua` (builders' nano spray drawn by the engine, at most 1000 particles: BAR's own
  setting NanoParticleMode 0, whose gadget then skips its per-frame work, and MaxNanoParticles put back after the
  gadget's own budget), `bardroid_retreat.lua` (touch play's automation, Kailil's and BAR's developers' call: a unit
  under half health falls back once; a hurt commander retreats past its death blast's reach, the combat units near it
  fight on its spot and go back once it is out, builders by it repair it first, then it waits on patrol; the dock's
  AUTO RETREAT switches it, LuaUI/Config/bardroid_retreat.txt), `bardroid_presets.lua` (the dock's PRESETS, 2 x 2 over
  its grid, then a map tap for the destination: ZIGZAG, and BATTLE LINE, SPREAD and CONCAVE, which form the units up
  by role where they stand and move them as one with a Ctrl+Shift fight given to them as the selection, the engine's
  way of keeping a group's shape at its slowest unit's speed).
- The app's widgets' main chunks stay under Lua's 200 locals (`tools/lua-locals.py`, in laptop-tests and CI): over
  it a widget does not load at all, and luacheck does not see it.

## Source map

| Where | What |
|---|---|
| `app/src/main/java/com/underarmcape/bardroid/` | `LauncherActivity`, `Installer` (first run), `Proot`, `XServer`, `VirglServer`, `GameService`, `GameActivity`, `Prefs`, `RtsTouch`, `ControllerBridge`, `PadGame` (+ `PadMouse`, `PadButtons`), `AudioPump`, `Updater`, `LobbyBridge`, `KeyboardShortcuts`, `PerfLog`, `LogShare` |
| `app/src/main/assets/bardroid/` | `setup-container.sh`, `launch-bar.sh`, `springsettings.cfg`, the Lua widgets |
| `app/src/main/assets/gamepad/` | BAR Controller Support v0.8.5, packed by `tools/build-gamepad-game.py` |
| `app/src/main/jniLibs/<abi>/` | prebuilt helpers (proot, busybox, talloc, ANGLE, virgl), rebuilt by `tools/` |
| `patches/` | the Termux:X11 changes, applied to `termux-x11/` by `tools/fetch-termux-x11.*` |
| `tools/` | native builds, laptop checks, phone benchmark, profilers, the 1st person tuner, `worklog.py`, `publish-check.ps1` |

On the device: `files/rootfs` (container), `files/bar` (engine write dir), `files/logs` (`launcher.log` has
everything, child processes included), `Android/data/<package>/files/import`.

## Things that bite

- Paths handed to proot must be canonical: in the app's mount namespace `/data/user/0` is a symlink to `/data/data`.
- Never keep paths into `nativeLibraryDir` on disk: it moves with every app update.
- Child processes go through `Proc`; Stop kills every process of the app's UID (proot ignores SIGTERM and orphans its
  tracees).
- No `--kernel-release` for proot on kernels 4 and newer: its kompat extension traps every futex.
- proot's seccomp filter must not trap syscalls proot does not act on: GPU drivers make hundreds of ioctls a frame.
- `MaxParticles` stays at 10000 or more (BAR's minimum), or unsynced LuaRules die and no unit is drawn.
- The lobby needs `chobby_config.json` in the write dir (`launch-bar.sh` writes it, as BAR's launcher does).
