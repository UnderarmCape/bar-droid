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
  hiding under two fingers, a pixel cap for the unfolded screen and Snapdragon GSR upscaling.
- **Graphics.** Phones: Mesa for Android containers (Freedreno `kgsl` / Turnip + Zink, lfdevs builds). The emulator:
  Mesa `virpipe` → our virgl server (`VirglServer`, `tools/build-virgl.py`) → ANGLE → the host GPU, llvmpipe as
  fallback.
- **Frame pacing.** `libbardroid_pace.so` (`tools/pace/pace.c`), preloaded into the engine: the frame cap after each
  swap (no VSync, so CPU and GPU overlap), an ioctl answer that puts lfdevs' Mesa on its explicit Present fence (the
  swap stops waiting for the GPU), window HIDDEN/SHOWN events while the game screen is hidden or a joined game is
  caught up, and SDL's display size following fold/unfold.
- **Audio.** The engine's OpenAL Soft writes waves into a FIFO; `AudioPump` plays them with `AudioTrack`. No
  PulseAudio.
- **Input.** Touch: `RtsTouch` turns gestures into lines in files under `LuaUI/Config`, read by
  `bardroid_touch.lua` (camera, pinch, tilt, "is the finger on BAR's interface"). Gamepads: `ControllerBridge`
  streams `BARCTRL1` packets over UDP 28777 to BAR Controller Support (the singleplayer game) and to the touch widget's
  pad camera online. Mouse and keyboard: Termux:X11's delivery; `KeyboardShortcuts` keeps Android's own shortcuts
  out of the game.
- **BAR's settings.** `launch-bar.sh` puts the Android layer over BAR's and the lobby's saved settings at every start
  (phone graphics, interface scale per Fold screen, widget orders and switches) and reports `!!! ANDROID LAYER` when
  a target it edits is gone. BAR's sandbox refuses widget toggles from user widgets, so they go in here.
- **Updates.** `Updater` updates engine, game and lobby at every start as BAR's PC launcher does (its launcher
  config), re-applies the layer and rolls back a set that fails on its first start. Content only ever comes from BAR's
  CDN (`pr-downloader`).
- **Lobby.** BAR's own Chobby lobby. `LobbyBridge` stands in for the PC launcher behind it (web links, downloads,
  replay info); `bardroid_lobby_touch.lua` makes it finger-friendly.
- **In-game widgets** (`app/src/main/assets/bardroid/`): `bardroid_touch.lua` (camera, perf log, catch-up mode),
  `bardroid_players.lua` (small player list), `bardroid_spectate.lua` (spectating by touch: player cameras, follow,
  presets, 1st person), `bardroid_info.lua`, `bardroid_chat.lua`, `bardroid_queue.lua`, `bardroid_bench.lua`.

## Source map

| Where | What |
|---|---|
| `app/src/main/java/com/underarmcape/bardroid/` | `LauncherActivity`, `Installer` (first run), `Proot`, `XServer`, `VirglServer`, `GameService`, `GameActivity`, `Prefs`, `RtsTouch`, `ControllerBridge`, `AudioPump`, `Updater`, `LobbyBridge`, `KeyboardShortcuts`, `PerfLog`, `LogShare` |
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
