# BAR Droid — hand-off (updated 2026-10-28)

> **Stale in parts (note of 2026-11-22).** Much of this file was written by 2026-10-28; the sections dated so are kept
> as the record of that time. What holds now: [docs/DELIVERY.md](docs/DELIVERY.md) (the release candidate 0.2.0 list,
> the open blockers, Kailil's calls), [CHANGELOG.md](CHANGELOG.md) (what 0.2.0 changes for players),
> [CLAUDE.md](CLAUDE.md) (every file and tool), [docs/PLAYTEST.md](docs/PLAYTEST.md) (the touch playtest's findings).
> Where they disagree with this file, they win. Known changes since: the upright touch dock (bardroid_portrait.lua)
> is the main touch interface; Android's Back puts the dock's picks and panels away before it is Escape; the lobby
> bridge is phone-tested (tools/bridge-phone-test.ps1); BAR checks run on the dev phone only (the phone suites,
> tools/phone-round.ps1), never on the laptop.

Beyond All Reason on Android. An Android app ("BAR Droid") that runs **BAR's Recoil engine** (since 2026-11-13 by
default the app's phone build of the version BAR's servers run, docs/ENGINE-DEFAULT.md; else the official one)
inside a Debian container with an **embedded X server** (Termux:X11's `lorie` library) and Mesa for desktop OpenGL.

**BAR plays on Kailil's Galaxy Z Fold7** (since the evening of 2026-10-25): BAR's lobby, online games, spectating
(joining a running game catches up with the drawing off), singleplayer against the AI, touch and gamepad controls,
~30 fps capped. Late in a spectated game with 2,500-3,900 units it held 29-30 fps, with dips to 16-20 for a few
seconds (2026-10-26). The emulator build (x86_64, the default of `Build APK.bat`) is the quick test bench:
amd64 Debian + the official amd64 engine, OpenGL through Mesa virpipe → virgl server → ANGLE → host GPU.

Where to read on: [README.md](README.md) (for players), [docs/BUILDING.md](docs/BUILDING.md) (build in three steps,
checks, releasing), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[docs/DELIVERY.md](docs/DELIVERY.md) (the road to a public GitHub release), [docs/WORKLOG.md](docs/WORKLOG.md) (Kailil's
messages and the time spent), this file (state, risks, next steps),
[CLAUDE.md](CLAUDE.md) (architecture, every file and tool, rules), [docs/HISTORY.md](docs/HISTORY.md) (what was found,
measured and decided, session by session), [docs/UPDATES.md](docs/UPDATES.md) (what the app changes in BAR's
settings at every start), [docs/upstream/](docs/upstream/) (draft reports of bugs that are not ours),
[RESEARCH.md](RESEARCH.md) (the research before the first line of code), [docs/HELP-WANTED.md](docs/HELP-WANTED.md)
(for whoever takes it on).

## State

| Piece | Path | State |
| --- | --- | --- |
| Build from a clone | `Install Toolchain.bat`, `Build APK.bat` (repository root), `scripts/env.bat` | A fresh clone builds the phone APK with the two launchers alone (checked 2026-10-27); portable toolchain (~6 GB), nothing installed globally, nothing in AppData or the profile; no build warnings in the app's own Java and Gradle files |
| Phone build (arm64) | `Build APK.bat phone` → `apk\bar-droid-phone-debug.apk` | **Plays on the Galaxy Z Fold7** (Adreno 830, Android 17): ~30 fps capped (60 fps option), no flicker, lobby, fold/unfold resize, floating window when leaving the game |
| Emulator build (x86_64, default) | `Build APK.bat` → `apk\bar-droid-emulator-debug.apk`, `Run in Emulator.bat` | Test bench: install from BAR's CDN, Play vs AI, units + full BAR UI, ~20 fps with the laptop awake (~8 in Modern Standby). The AVD: Android 14, 12 GB RAM, 6 cores, `hw.gltransport=asg` |
| Frame pacing, swap | `tools/pace/pace.c` → `libbardroid_pace.so` | The frame cap without VSync, and Mesa on its explicit Present fence: CPU and GPU work at the same time (a spectated 8v8 with 829 units: 15-24 → 28.8 fps); the engine stops drawing while the game is hidden or catching up |
| Phone settings layer | `launch-bar.sh` (`PHONE_GFX`, widget orders, interface scale), [docs/UPDATES.md](docs/UPDATES.md) | No MSAA, shadows, far features, water reflections, BAR's full-screen effects; Spring camera; BAR's interface 2.0 folded / 1.0 unfolded (1.3 until 2026-10-28); units drawn as icons unless close; queued buildings drawn near the camera only; the classic minimap; no lights, decals, AO plates, grass, order effects, ship wakes; unfolded at the folded pixel count; the lobby on Always One panel at 135%. Each tweak logs `!!! ANDROID LAYER` when its target is gone |
| proot | `tools/build-proot.py` | Our build of Termux's proot (pinned commit) whose seccomp filter stops only for the ioctls proot handles: 14 → 30 fps on the phone |
| Touch in game | `RtsTouch.java`, `assets/bardroid/bardroid_touch.lua` | Tap = click, double tap = same type on screen, triple tap = same type on the map; one finger pans (drag from the interface = mouse drag), tap-then-drag = box select, long press = right button; two fingers pan, pinch zoom, twist rotate, move up/down together to tilt, tap = right click; two fingers held 450 ms then swiped: up select all, down deselect, left stop, right fight; three-finger swipe: up overview, down back, left/right previous/next idle builder; three-finger tap = keyboard; Back = Escape |
| Touch in the lobby | `assets/bardroid/bardroid_lobby_touch.lua` (a lobby widget) | A drag scrolls lists with a fling; a tap on a server shows its details and Close / Previous / Next / Join, a second tap joins |
| Keyboard shortcuts | `KeyboardShortcuts.java`, `GameActivity.handleKey` (see "Keyboard shortcuts" below) | A Bluetooth or dock mouse and keyboard work as Termux:X11 delivers them (Kailil: "works perfectly already"); Android's, One UI's and DeX's shortcuts kept out of the game: Android 16.1 keyboard capture, Samsung's Meta key request, keys before the soft keyboard app; Kailil's check pending |
| Chat display | `assets/bardroid/bardroid_chat.lua` | BAR's chat lines in the same box, names flush left (wrapped every 10 characters), the text filling the rest, 75% of BAR's font size; BAR's typing box and ignore list stay |
| Unit info panel | `assets/bardroid/bardroid_info.lua` | Replaces BAR's Info widget (its text ran under the picture at phone scales): BAR's numbers, the largest text that fits, a type grid with counts for several units (tap keeps a type, long press drops it), BAR's `WG.info` API |
| Spectating by touch | `assets/bardroid/bardroid_spectate.lua`, `RtsTouch.source`, `tools/spectate-test.ps1 [-Cost]`, `tools/fp-tuner.ps1` | While spectating with fingers (the app reports touch/mouse/keyboard/pad): taps select nothing (no unit panels); a tap on another player's unit spectates that player, a double tap on a unit follows it (forgiving; the ground: stops); following sticks through pans, zooms and twists (an offset) until a far flick; a tap on the small player list brings up a bar for 7 s: < player name > (BAR's player camera, in the list's order), Free, < unit > (the player's units nearest the screen's centre), Group; while following: 1st person (free look, recenters after 4 s), Shoulder, Table, Close, Mid, and Tune (per unit type, saved on the device, given to the other factions' equivalent). Costs 0.014 ms a frame when not in use, 0.03 ms in 1st person, ~0.1 ms with the bar up (laptop, 1,560 units) |
| Public release | [docs/DELIVERY.md](docs/DELIVERY.md), `tools/publish-check.ps1`, `Build APK.bat phone release`, `.github/` | The project's own icon in public builds (Kailil's BAR-derived icon only in his debug builds, from outside the repository), LICENSE, personal data out of tracked files, release signing with the publisher's key, CI, players' README, CHANGELOG, CONTRIBUTING; on GitHub, private, since 2026-11-18 (UnderarmCape/bar-droid, every branch; the phone engine's source in UnderarmCape/bar-droid-engine; the newest build as the pre-release latest-build; `tools/github-sync.ps1` after every commit); left for Kailil: the release key, the app's public name, a fresh or rewritten history, making it public |
| Work log | `tools/worklog.py` → [docs/WORKLOG.md](docs/WORKLOG.md), `docs/worklog/` | Kailil's messages, Claude's answers (whole since 2026-11-18: the project's conversation archive) and both sides' hours from the Claude Code transcripts, kept in the repository; rerun after every work session |
| Catch-up | `bardroid_touch.lua`, `GameActivity`, `libbardroid_pace.so` | Joining a running game: a black screen with "Catching up 12:30 of 41:10 x2.5", the engine not drawing (a 17-minute game caught up in 164 s); a game too big to catch up draws again after a minute |
| Gamepad | `ControllerBridge`, `PadGame`, `assets/bardroid/bardroid_pad.lua`, `bardroid_touch.lua`, `tools/pad-test.ps1` | Every game plays BAR's released game with the app's pad controls: v0.8.5's rebuilt from an X mouse and keys (`PadGame`), the rest as actions for `bardroid_pad.lua`; the pad is a mouse in the lobby. Until 2026-11-06 singleplayer played Kailil's BAR Controller Support v0.8.5 as BAR's developer game; its code left the app on 2026-11-21 ("Gamepad" below is its record) |
| Upscaling (SGSR) | patch 0007, `assets/sgsr/`, `GameActivity` | The X screen (smaller than the display) is enlarged with Qualcomm's SGSR 1 instead of plain bilinear filtering; plain if the GPU refuses the shader; "Compare upscaling" switches it every 3 s under a label (on until Kailil has compared, then off by default) |
| Lobby bridge (on) | `LobbyBridge.java` | Stands in for BAR's PC launcher behind the lobby (web links, downloads, replay info); on by default since 2026-10-27 (without it the Replays tab hung on "Loading"); checked against the real lobby on the laptop, first phone check pending (Next steps) |
| Updates | `Updater`, [docs/UPDATES.md](docs/UPDATES.md) | Every start updates engine, game and lobby like BAR's PC launcher and rolls back a set that fails on its first start |
| Share logs | launcher button | Zips the logs into Android's share sheet: phone debugging without adb; an online game's join password (`MyPasswd`) taken out (`LogRedact`) |
| virgl GPU server (emulator) | `tools/build-virgl.py` | Built from source with the NDK (Termux's binary turns every DXT texture black) |
| ARM64 AI bug fix | `app/src/main/assets/bardroid/libasarm64.so`, `patches/circuitai-cmake-arm64-linux.patch` | Phone build only; not filed upstream yet |
| Benchmark | launcher "Benchmark", `tools/phone-bench.ps1`, `tools/profile-benchmark.ps1` | BAR's "Benchmark BAR" scenario unattended on the phone (warmed up, clocks and threads logged, per-run engine settings) and profiled on the laptop (every widget, unsynced gadget and engine timer) |
| Checks | `tools/laptop-tests.ps1`, `tools/pace-test.ps1` | Every laptop check passes (Lua lint, downloader, settings merge, updater rollback, lobby bridge, lobby touch and the lobby's Skirmish screen with the controller game in the real lobby, the touch, chat and info widgets in a real skirmish and in the controller game) |

## How the app works (one paragraph)

`LauncherActivity` → `GameService` (foreground). **Install**: `Installer` runs `libproot.so`/`libbusybox.so` straight
from the app's native-lib dir (the only place Android lets an app exec from), downloads the official Debian trixie
arm64 docker rootfs (layer digest read from the OCI manifest on GitHub, SHA-256 checked), extracts it with
`proot --link2symlink` + busybox tar (hard links → symlinks), runs `/opt/bardroid/setup-container.sh apt`
(SDL2/X11/OpenAL/fonts/xkb/Mesa pkgs; no documentation, manual pages or translations), installs **Mesa for Android
containers** over Debian's Mesa, `slim` (once, older installs too: PulseAudio's daemon and x11-xserver-utils with the
~90 packages only they need, on a phone Debian's own gallium driver and other GPUs' Vulkan drivers; 723 -> 375 MB),
downloads `recoil_2026.09.03_arm64-linux.7z` (the engine BAR's servers run; Prefs.engineVersion), then `pr-downloader` fetches `byar:test`, `byar-chobby:test` and one
map from BAR's own CDN (nothing of BAR's CC-BY-NC-ND art is bundled). **Play**: `XServer` starts
`com.termux.x11.CmdEntryPoint` (compiled into *our* APK) via `/system/bin/app_process` with `TMPDIR=<rootfs>/tmp`
so the socket is the container's `/tmp/.X11-unix/X0`; `GameActivity` (extends Termux:X11's `MainActivity`) shows the
display and handles touch/mouse/keyboard; `launch-bar.sh` runs inside proot: waits for the socket, points OpenAL
Soft's wave writer at the FIFO (→ `AudioPump` → `AudioTrack`), runs a one-time `glxinfo` probe, then
`spring --isolation --write-dir /root/bar skirmish.txt` (or `--menu rapid://byar-chobby:test`). Gamepad events are
intercepted in `GameActivity`: `ControllerBridge` → `PadGame` (an X mouse and keys, and actions for
`bardroid_pad.lua`); the BARCTRL1 UDP stream of the controller game's days went on 2026-11-21.

## Build / run (Windows laptop)

The launchers are in the repository root (the copies beside the checkout in `C:\Tools\BARANDROID` only call them).
```
Install Toolchain.bat --accept-licenses   one time; ~6 GB into the toolchain folder (Android SDK terms)
Build APK.bat phone                       arm64 phone build -> apk\bar-droid-phone-debug.apk
Install on Phone.bat                      onto the adb-connected phone (USB debugging, or Pair Phone.bat)
Pair Phone.bat                            wireless debugging: pairs and connects (asks for the phone's ports and code)
Get Logs.bat phone                        launcher.log, infolog.txt, glcheck, logcat -> logs\phone-<time>\
Build APK.bat                             emulator build (x86_64) -> apk\bar-droid-emulator-debug.apk
Run in Emulator.bat                       boots the emulator (first time ~1.8 GB download), installs + opens the app
powershell -ExecutionPolicy Bypass -File tools\laptop-tests.ps1   every check that needs no phone (~5 min)
```
The toolchain folder: `BARDROID_TOOLCHAIN` if set, else a `toolchain` folder beside the checkout, else `toolchain\`
inside it (`scripts\env.bat`); APKs and logs go beside it (`BARDROID_OUT` overrides). The laptop checks read BAR's
Windows install (`BAR_DATA`, default the BAR launcher's folder in Local AppData) and never change it.
Kailil's phone: Galaxy Z Fold7 (Snapdragon 8 Elite / Adreno 830, so the Freedreno/Turnip path). adb: USB, or Wi-Fi
`adb connect <phone address>:5555` after `adb tcpip 5555` (until the phone reboots; the phone must be on the laptop's
Wi-Fi network). Samsung's Auto Blocker can block adb installs.
In the app: **Install / Update** (Debian + engine + BAR content, ~4 GB, ~10 min) → the lobby or **Play vs AI**.
Native helper binaries: `tools/fetch-prebuilts.py <abi>` (proot, busybox, ANGLE), `tools/build-proot.py <abi>`,
`tools/build-virgl.py <abi>` (virgl server) and `tools/build-pace.py` (the pace library); they run with the
toolchain's Python inside `scripts\env.bat`. Their output is committed under `app/src/main/jniLibs/<abi>/` and
`app/src/main/assets/bardroid/`, so a normal build needs none of them.
Toolchain pinned by termux-x11: AGP 9.3.1, Gradle 9.8.2 (wrapper), NDK 29.0.14206865, CMake 3.22.1, JDK 21.
One ABI per APK.

## Open risks (2026-10-27)
- RAM: Android logged low memory all through a spectated 8v8 (~1000 units); its killer has taken the game before.
  The `[perf]` minute line now has MemAvailable, SwapFree and the engine's resident size.
- Heat: after an hour the GPU is capped at 443-900 MHz of 1200 and the CPUs at ~2 GHz; `[perf]` shows when. In the
  30-minute game of 2026-10-27 the phone sat at thermal status 3 with the GPU at its 160 MHz floor and still drew
  ~30 fps up to ~2,000 units.
- Only one phone has run it (Fold7, Adreno 830, Android 17). Other Adreno 7xx/8xx phones should take the same path
  (lfdevs Mesa, KGSL) but are untested.
- BAR's saved games crash the engine when loaded, on Windows too (Gamepad section, "Busy scenes"): upstream.
- The explicit Present fence (`libbardroid_pace.so`'s ioctl answer) is new: watch for flicker or a stall on
  fold/unfold and in the floating window.
- The lobby runs without BAR's launcher behind it ("WrapperLoopback", Next steps): some lobby features fail quietly.
- BAR's graphics presets in its settings menu undo the phone layer for the rest of that game ("medium" switches
  shadows, bloom, snow, distortion and decals back on); the next start resets them. They were not what slowed the
  last 8v8 (docs/HISTORY.md): late games with ~1300 units run ~19 fps on a hot phone, GPU-bound at its thermal cap.

## Gamepad (2026-10-26)
> Retired: since 2026-11-06 every game plays BAR's released game with the app's own pad controls (`PadGame`,
> `bardroid_pad.lua`; CLAUDE.md "Gamepad"), and the controller game's code (assets/gamepad, `Installer`'s install of it,
> the BARCTRL1 stream, the launcher's checkbox) left the app on 2026-11-21 (docs/DELIVERY.md, release overhaul item 6).
> This section is the record of how it worked; the pad as a mouse in the lobby and the online pad camera below stay.

Kailil (2026-10-26): "Do v0.8.5 1:1 as the developer game for skirmish and the lobby, plus the pad camera for online
and spectating"; no "controller not connected" indicator on Android; keep it cheap.

**Performance (2026-10-26).** Kailil: v0.8.5 "was working perfectly ingame", but fps dropped ("i neveer figured out
using codex how to get the usage down"); it was out of the builds (a019af7) until it was cheaper. The phone's log:
LuaUI garbage 79-268 MB/min with v0.8.5 against 0-44 MB/min on BAR's released game. Now packaged from BARGAMEPAD
branch **`controller/codex-v085-perf`** (sparse worktree `src\bar-codex-perf`; release branch untouched), same
behaviour and pixels. Laptop, v0.8.5 skirmish with the companion's scripted pad (`tools/profile-gamepad-game.ps1`):
all LuaUI garbage 10.5 → 0.83 MB/s, the hint runtime 1.10 → 0.35 ms/frame and 9.8 MB/s → 0.12, the controller
widgets together ~1.6 → ~0.8 ms/frame. What it was and what changed:
- The hint runtime's 25 Hz context snapshot copied the engine's command list (and per-unit command lists) out of
  the engine several times per poll: now cached until BAR's `CommandsChanged`/`SelectionChanged`.
- The hint panel was laid out and drawn with ~150 kB of new tables every frame: now a display list replayed until
  what it shows changes (drawn directly when it changes and while it fades in, re-recorded once a second), and the
  renderer/glyph code allocates nothing (5384 gl calls compared identical to the release branch).
- A resting stick read the camera state each frame only for the hidden debug panel.
- The build radial (RB) rebuilt its tables, text and BAR's unit cells in immediate mode every frame it was open
  (Kailil: 20-23 fps on opening, ~10 s to recover): now a display list, recorded once its inputs (options, selection,
  page, affordability, queues, progress, availability text, position, settings) held for a frame, replayed until one
  changes. Laptop (`-Radial`): 355 of 358 frames per open replayed, garbage while open 1.8 → 0.33 MB/s (as when
  closed), first-open worst frame 46 → 37 ms; its screenshot shows the same radial.
v0.8.5's own suite (`BARGAMEPAD scripts\codex-tests.ps1 -GameDir src\bar-codex-perf`): 20 pass + the 6 known
attempt-01 failures, as on the release branch. Profiling: `tools/profile-gamepad-game.ps1 [-Functions -Detail <widget>]`
(per widget, or every function of one widget with exact allocations); `-Released` measures BAR without v0.8.5.
Remaining controller costs (laptop): the camera widget ~0.4 ms/frame, 0.45 MB/s, spread over many functions
(selected-unit status panel, control groups, packet parsing).

**Stripped for the phone** (Kailil, 2026-10-26: "get rid of the debug stuff and the hints menu all together. and
remove bindings menu and UI ... its too clunky to use on mobile"; the hints were too small to read anyway):
`build-gamepad-game.py` turns the hints off (the runtime then polls nothing) and leaves out the bindings menu, the UI
layout editor, the SmartX audit and v0.8.5's tests (`MOBILE_LEFT_OUT`). Laptop: LuaUI garbage 0.67 MB/s. The phone
after the first optimization: LuaUI memory changes 20-79 MB/min (before 79-268; BAR's released game 0-44) and the
sim kept real time through a 31-minute skirmish, so the 15-30 fps Kailil sees is rendering: the potato pass.
BAR's own options widget re-applies its saved shadow setting at every start (`Set "shadows" config-parameter to 1`)
over our `Shadows = -1` (it saw a fresh springsettings.cfg each start, see docs/HISTORY.md "Overnight hardening"; launch-bar.sh now
sets ShadowQuality 0, which BAR's slider reads).

**Busy scenes (2026-10-26, measured on the Fold7 with simpleperf and /proc while Kailil played).** On BAR's Lowest
preset a base with ~200 wind turbines still ran 15-23 fps, so effects were not the limit. What was:
- CPU and GPU took turns: the engine's main thread sat in `IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID` (waiting for the GPU)
  43-58% of each frame and was busy only ~36%; the GPU, idle in between, read ~72% busy and its governor kept it at
  342-443 MHz of 1200. Cause: lfdevs Mesa's Present-fence path only keeps a third back buffer at swap interval 0, and
  our 30 fps cap was VSync (swap interval 2, `vblank_mode=3`). Now `vblank_mode=0` plus our own cap,
  `libbardroid_pace.so` (`tools/pace/pace.c`, `tools/build-pace.py`; LD_PRELOAD, sleeps after `SDL_GL_SwapWindow` to
  `BARDROID_FPS`). With `vblank_mode=0` alone the GPU ran at 832 MHz in a similar scene.
- After hours of play the phone was hot (skin 42 °C, thermal status 2): the GPU was capped at 607 MHz
  (`/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel` 8, `devfreq/max_freq`). Power per frame is what keeps the clocks: the
  cap matters, and potato mode should cut work and resolution.
- Simpleperf on the phone: `adb shell setprop security.perf_harden 0`, then from the shell
  `/data/local/tmp/simpleperf record --app com.underarmcape.bardroid -p <spring,proot,x11 pids> -e cpu-clock:u`
  (kernel samples are refused; `--app` alone only catches the Java process).
- Loading BAR saves crashed (SIGSEGV in "Loading Saved Game", no stack). **Not Android's** (2026-10-26, overnight):
  Kailil's save `Saves/20261026_063343.ssf` (controller game, Death Valley, vs BARb, frame 88559) crashes the
  Windows build of the same engine (2026.07.04, `spring.exe --isolation --write-dir build\profile\data <save>.ssf`)
  at the same point: access violation in spring.exe at frame 88559 right after "Loading Saved Game" (offsets from
  the image base: 0x965868, 0x9626f2, 0x5b3fd2, 0x535eae, 0xd5d099; no symbols). The controller game only changes
  LuaUI, so the synced state is BAR's own. An upstream report (Recoil/BAR) needs Kailil's go-ahead.
- **Still waiting on the GPU (spectating an 8v8, 226-418 units, 23-24 fps; 2026-10-26, with the pace cap):** the main
  thread is busy ~50% and blocked in `0x400c0907` 42%; GPU 342 MHz of 1200, 61-76% busy (no thermal cap); the prime
  cores (cpu6-7) idle at 1017 MHz, the main thread runs on cpu0-5. Its stack while blocked (read from
  `/proc/<pid>/mem` at the SP in `/proc/<pid>/task/<tid>/syscall`; simpleperf has no off-CPU events on this phone;
  walk the aarch64 frame records x29 -> {x29, x30}, libgallium has a symtab; a plain scan for code addresses mostly
  finds stale words): 24 of 30 samples `SDL_GL_SwapWindow` → `__glXSwapBuffers` → `loader_dri3_swap_buffers_msc` →
  `dri_flush` → `st_context_flush` → `tc_flush` → `_tc_sync` → `tc_batch_execute` → `__fd_resource_wait` →
  `fd_bo_cpu_prep` → KGSL wait, the rest in `_tc_sync`. So at every swap the driver waits for the GPU to finish with a
  resource the frame queued (likely this Mesa's Present-fence path waiting for the frame itself): CPU and GPU take
  turns, the GPU idles ~35% and its governor stays at the bottom clock. Ideas: less GPU work (MSAA was 4x until
  launch-bar.sh forced 0; shadows; terrain detail; features at any distance from Chobby's `FeatureDrawDistance =
  600000`), a Mesa that does not wait at the swap, ADPF hints. Kailil: a top-down camera runs much faster than a
  tilted one. A second 8v8 an hour later: 15 fps, blocked 51%, GPU capped at 443-525 MHz and CPUs at ~2 GHz (hot).
- **The swap wait's cause** (lfdevs Mesa PR #96 source): `fd_flush_resource` on KGSL CPU-waits for the frame
  (`FD_BO_PREP_READ`) unless the frontend uses the explicit Present fence, which `dri3_present_sync_init` enables
  only when `DMA_BUF_IOCTL_EXPORT_SYNC_FILE` fails with ENOTTY/ENOSYS. The Fold7's kernel supports it (KGSL attaches
  no fences, so the export is empty), the engine had no `present` thread. `libbardroid_pace.so` now answers ENOTTY
  for that ioctl (`BARDROID_PRESENT_FENCE=0` = off); lorie has the X server half (termux-x11 b36dac08). Check: a
  `present` thread in `/proc/<engine>/task/*/comm`, no `0x400c0907` waits in the main thread, no flicker.
  Result (Kailil: "HOLY SHIT THAT WORKED", spectating an 8v8 with 829 units, hot phone): `sprin:present0` runs, the
  main thread no longer waits for the GPU (0 of 200 samples, was 42-51%; 63% running), the GPU 78-91% busy at its
  thermal maximum (734-900 MHz, was stuck at 342), 28.8 fps over the minute, nearly every second at 30.
- **Phone graphics at every start** (`launch-bar.sh` `PHONE_GFX`, Kailil: "disable msaa on every graphics profile",
  "we can still cut more things"): no MSAA, no shadows, features drawn to 6000, GroundDetail 60, no water
  reflection/refraction passes, no engine grass or line smoothing, in springsettings.cfg and Chobby's game_settings;
  BAR's bloom/SSAO/distortion/snow/map edge extension widgets off; the lights' screen-space shadows 0 (in
  `LuaUI/Config/BYAR.lua`: BAR refuses `/option` from user widgets, "User widgets cannot control other widgets or
  execute remote code"). BAR's settings menu can change them until the next start.

**Pad as a mouse in the lobby** (Kailil: "just simple mouse movement, scroll and A and B as left and right click"):
`ControllerBridge.Mouse` (GameActivity `lobbyMouse`) is on while no game widget writes the hover file (older than
3 s: the lobby, loading screens): left stick moves the X pointer, right stick scrolls, A/B left/right button.
- **Why a developer game:** BAR Controller Support v0.8.5 (`C:\Tools\BARGAMEPAD`, branch
  `controller/codex-v085-release`) is BAR's own game with the controller added (new widgets, edits inside ten of BAR's
  widgets), ported onto BAR Release 2026.10.20-1 (`a61703336e`). BAR's user-widget sandbox (BAR PR #9547) blocks its
  socket and input emulation, so like on Windows it runs as BAR's developer game, "Beyond All Reason $VERSION", which
  the lobby plays with `gameConfigName = "byar-dev"` ("Beyond All Reason Dev"). Online games use BAR's released game.
- **The archive:** `tools/build-gamepad-game.py` packs only v0.8.5's added/changed files (`luaui/`, `controller-ui/`)
  into `assets/gamepad/gamepad.zip` plus a `modinfo.lua` that depends on "Beyond All Reason test-31691-a617033"
  (rapid tag `byar:git:a61703336e…`). The engine adds an archive's own files before its dependencies' (Recoil
  `CVFSHandler::AddArchiveWithDeps`, overwrite=false), so v0.8.5's files win. `Installer.installGamepadGame` downloads
  that release (setup step `gamepad`, ~4 MB beyond byar:test), unpacks the zip to `files/bar/games/BAR-gamepad.sdd`, and
  copies the three BAR icons v0.8.5 reuses from the downloaded pool (no BAR artwork in the APK). It runs at install and,
  for an app update, before the next lobby/skirmish start (status in the notification); failures leave singleplayer on
  BAR's released game. Launcher checkbox "Controller support v0.8.5 in singleplayer" (`Prefs.gamepadGame`, default on).
- **Set up like the Windows installer** (`launch-bar.sh`, `GAMEPAD_GAME=1`): lobby game byar-dev (chobby_config.json and
  `IGL_data.lua`), BAR's Build menu on and Grid menu off in `LuaUI/Config/BYAR.lua` (v0.8.5 drives the Build menu).
  No `devmode.txt` (only Chobby's developer buttons). Off again: both go back.
- **No indicator:** the shipped UI defaults turn v0.8.5's "companion status" panel off (the only Android change to it),
  and `ControllerBridge` streams packets from the moment the game screen opens (heartbeat every 100 ms, v0.8.5 calls the
  stream gone after 250 ms), pad or not, exactly as the Windows companion's `--codex` mode: raw axes, no Guide.
- **Online gamepad camera:** `ControllerBridge` writes `pad …` lines (only when the sticks change) into the touch log;
  `bardroid_touch.lua` moves the camera each frame with v0.8.5's camera constants (left stick pans, LT faster, right
  stick turns/zooms, LB+right stick tilts). Off in the controller game (v0.8.5 reads the pad itself).

## Keyboard shortcuts (2026-10-27)
Kailil: "mouse and keyboard support works perfectly already. but i just want to make sure the android built in
keyboard bindings and shortcuts dont listen in on the bar session." So how the mouse and keys reach the X server is
Termux:X11's, unchanged; only who sees a key first changes. `KeyboardShortcuts` (launcher setting "Keyboard
shortcuts go to the game", `Prefs.captureShortcuts`, on; off = Termux:X11's defaults). Client-side only (online-safe).
- **Android 16.1+ keyboard capture**: `WindowManager.LayoutParams.setKeyboardCaptureEnabled(true)` (API 36.1, by
  reflection: compileSdk is 34), permission `android.permission.CAPTURE_KEYBOARD`. On the Fold7 (Android 17, One UI
  9.0) the permission is `prot=normal` (`dumpsys package permission`), granted at install; framework.jar has the
  setter and `INPUT_FEATURE_CAPTURE_KEYBOARD`; launcher.log said "keyboard capture on" at the first start. Moonlight
  uses the same call (its commit ddb674a, "Add support for Android 16.1 keyboard capture"). Without it Android's
  shortcut handling (AOSP KeyGestureController: Meta alone for All apps, Alt+Tab, Ctrl+Space, Meta+letter, the Recents
  and screenshot keys) runs before any app sees the key. Which shortcuts the capture hands over is documented nowhere
  we found: Kailil's check tells.
- **Samsung's Meta key request** (`SemWindowManager.requestMetaKeyEvent`, Termux:X11's "Intercept system shortcuts",
  `dexMetaKeyCapture`): One UI and DeX hand the Windows key and its combinations to the window.
- **Keys before the soft keyboard app**: Termux:X11's "hardware keyboard scancodes workaround" off, so LorieView's
  pre-IME pass sends keys (`GameActivity.handleKey` → Termux:X11's own `handleKey`, the same code as before) and the
  keyboard app never sees a hardware key: its shortcuts (Samsung Keyboard's Shift+Space or Ctrl+Space language
  switch) cannot act. The extra key release LorieView queues 50 ms after a Shift/Ctrl/Backspace release (for soft
  keyboards that swallow releases) is dropped there as its post-IME path did (`BarDroidAccess.keyReleaseSent`), so a
  quickly re-pressed Shift is not let go.
- **Fallback for older Android**: Termux:X11's KeyInterceptor accessibility service, renamed "Beyond All Reason
  keyboard shortcuts", with our own config (the library's points at a settings screen that is not exported here),
  switched on by the player (README); an accessibility service gets keys before Android's shortcut handling (only
  volume keys go to the policy first). Its keys go through `GameActivity.handleKey` too: the gamepad's first (it would
  otherwise send pad buttons to the X server).
- **Kept Android's on purpose** (`KeyboardShortcuts.isAndroidKey`, on every path): the Home, Recents and All apps keys,
  power, brightness, call, camera, assistant; volume and media keys keep Termux:X11's handling (Android's). The system
  Back (gesture, button) is Escape as before, after the soft keyboard (if shown) has closed on it.
- **No app can block**: the touch gestures (Home and Recents swipes, the notification shade; full screen they take a
  second swipe), the power key and its chords (screenshot, emergency). On Android before 16.1 without the accessibility
  service, Alt+Tab, the Windows key and Ctrl+Space stay Android's.
- The first build of this (b148e59, installed 21:01, withdrawn the same evening before any mouse was used with it)
  also captured the mouse and sent keys as scancodes. It switched Termux:X11's `pointerCapture` and `preferScancodes`
  on; `KeyboardShortcuts.applyTermuxPrefs` sets them back to Termux:X11's defaults once.

## Phone requirements
Qualcomm Adreno 7xx/8xx (Snapdragon 8 Gen 2/3/8s Gen 3/8 Elite), 12 GB RAM, ~6 GB free. The APK installs from
Android 9 (minSdk 28); tested on Android 17 (the Fold7) and Android 14 (the emulator).
Mali/Xclipse/Tensor: no Mesa path → the app's device check says so.

## Next steps (2026-10-27)
0. **Keyboard shortcuts, Kailil's check** ("Keyboard shortcuts" above). In a game and in the lobby, whether Android
   still acts on any of: Esc (Back), the Windows key alone (All apps, search), Windows+D/E/N/other letters, Alt+Tab,
   Ctrl+Space or Shift+Space (language), Alt+F4, Ctrl+Esc. Mouse and typing should feel exactly as before. If a
   shortcut gets through, try again with Settings > Accessibility > Installed apps > "Beyond All Reason keyboard
   shortcuts" on. Afterwards: launcher.log `[input]` ("keyboard shortcuts to the game: keyboard capture on, ...").
1. **Kailil checks on the phone** (everything is installed; the phone's logs show no app errors): the forgiving tilt
   and the new gestures, the black catch-up screen, the chat display, finger scrolling and the server details in the
   lobby, the unit info panel (one unit and several), no ship wakes, late-game fps with the deferred-pass trims
   (shields and the radar/jammer placement previews should look as before). Not reported back yet from earlier
   builds: lock the phone mid-game and unlock (picture and sound back at once), drag the top bar's and the settings'
   sliders with a finger, BAR settings (e.g. volume) kept after a restart, the unfolded resolution cap. And whether
   the lobby still asks to log in again (its saved login was in place on 2026-10-27). New on 2026-10-27: the lobby's
   Skirmish screen and Replays tab, the server bar after unfolding, joining a server shows its room (not Chat: the
   lobby's Do Not Disturb, launch-bar.sh), a game started folded then unfolded keeps its proportions (launcher.log:
   `GR::UpdateScreenMatrices` with ssx/ssy equal to vsx/vsy and vpy=0 after the fold), and SGSR upscaling (on;
   the comparison off since Kailil's look at it). **Open: a GPU hang on joining** (2026-10-27 12:08 and 12:12, the
   same online 8v8 on All That Glitters v2.2.3, the first games with the SGSR / screen-size build): lorie's display
   fences time out ("GPU fence wasn't signalled", tag gles-renderer, debug level: `adb logcat -s gles-renderer:D`),
   then the engine's Mesa gets EDEADLK on every submit (KGSL invalidated the engine's context: its work hung the GPU)
   and the engine freezes for good. SGSR built and drew (logcat "Xlorie: SGSR 1 upscaling on OpenGL ES 3.2"), lorie's
   context survived. With the comparison off (12:23 build) Kailil played another map and then All That Glitters
   again without a hang (12:29: 30 fps, 1151 units): both hangs were while "Compare upscaling" switched SGSR on and
   off every 3 s, the suspect; it stays off (a diagnostic only). **Frame cap 30 by default** (launcher "Frame cap"
   30 / 60 / none, `Prefs.fpsCap`, saved as "frameCap"): uncapped only for measuring (`phone-bench.ps1 -Cap 0`, which
   puts the player's cap back). Kailil after the benchmarks (2026-10-27): "put the hard 30 fps lock back on the
   phone. I resign to the fps tanking when the battle gets rough. we have optimized enough." **Where the time goes**
   (Kailil's uncapped 8v8, 2026-10-27): GPU-bound, 93-99% busy all game, the GPU's top clock throttled by heat from
   1200 to ~400 MHz; 88 fps at 178 units, 26 at 1400; BAR's Lowest preset changed nothing (the phone already has
   almost everything it turns off). Stress test: BAR's Scenarios → "Benchmark BAR" (1000 Grunts against 1000 Pawns,
   4000 frames; "Benchmark Results" in infolog: Sim/Draw/Update ms per frame). Per-stage GPU timing needs
   gl.QueryCounter/GetQueryDelta, which BAR's GPU Profiler widget expects but no Recoil has yet (master 2026-10-23
   neither). **BAR's benchmark on the phone** (`tools/phone-bench.ps1`, unattended, throttled; docs/HISTORY.md
   "Benchmarks"): a 1,300-unit battle is CPU-bound (70% resolution changed nothing), the main thread at ~1.7 GHz under
   Samsung's heat caps, the game at x0.74-0.95 of real time; Android Game Mode no help. Done since: BAR's developer
   tools out of singleplayer (checked on the phone), the info panel cached; `WorkerThreadCount` 4 beats 2 by ~5%
   (keep 4); the phone's profilers: LuaUI 11% of the running time (Reclaim Field Highlight 3.1%), LuaRules 20% (BAR's
   game: not changeable online). **Only online-safe changes** (Kailil, 2026-10-27: "we MUST have online play
   enabled"): no engine builds, overlay games or modrules, also in research. Map edge: past it the camera moves as
   on the map since 2026-11-03 (Kailil: "feel just like normal navigation"; the void's point on the level plane,
   `bardroid_touch.lua` planePoint; `tools/touch-phone-test.ps1`). BAR's player list: small until tapped
   (`bardroid_players.lua`, 7 s). Build and order menus: the app runs its own copies of BAR's in BAR's game
   (`bardroid_buildmenu.lua`, `bardroid_ordermenu.lua`, remade on the phone after BAR updates) with an IsAbove and
   touch placement; v0.8.5's in the controller game are counted as interface by their rects.
2. **Kailil's calls:** the `LICENSE` file is in since 2026-10-28 (the GPL-3.0 text, as README has always said
   GPL-3.0-or-later and the embedded `lorie` module requires GPL-3; Kailil to confirm "or later", or `git revert`
   it); the public release's open points (docs/DELIVERY.md); more gameplay-information widgets off (Reclaim Field Highlight is off since 2026-10-27, Kailil's call;
   Defense Range GL4,
   Sensor Ranges, Ecostats, BuildETA: CPU per frame) or GPU ones (Outline Shader GL4, Orb Effects); MaxSounds lower (OpenAL mixing); on the inner screen the
   player list covers the order menu's last column (at 75% it uncovers most of it; docs/HISTORY.md, "Overnight
   hardening").
3. **The lobby without BAR's launcher.** Chobby talks to BAR's PC launcher through `WG.Connector`
   (`libs/spring-launcher/luaui/widgets/api_spring_launcher.lua`: host/port from `sl-connection.json` in the write
   dir, `{"name":…,"command":…}` JSON lines over TCP) and `luamenu/widgets/sl_loopback.lua` (`WrapperLoopback`):
   OpenFile (web links), Download (with it on, maps and games too; "resource" files such as the OpenSkill ratings CSV
   only through it: "Download aborted (no wrapper, unsupported VFS type)" every start), ReadReplayInfo (Replays tab),
   ParseMiniMap (map thumbnails), StartNewSpring (games and replays on another engine), UploadLog, Discord.
   **Built overnight as `LobbyBridge`, launcher setting "Lobby bridge", on by default since 2026-10-27** (off, the
   Replays tab hangs on "Loading": `gui_replay_handler.lua` calls `WG.WrapperLoopback` unchecked): web links, game/map
   downloads through pr-downloader (`setup-container.sh` steps rapid/map), resource downloads by HTTP, replay info
   from the replay's header and start script. **Checked against the real lobby on the laptop**
   (`tools/lobby-bridge-test.ps1`: BAR's Windows engine runs byar-chobby:test in an isolated write dir, LobbyBridge on
   the JDK with stand-ins for Android and the container): it connects, the Replays tab lists Kailil's replays with
   engine, map, game time and both teams, the lobby's two resource downloads (widget manifest, skill ratings CSV)
   arrive, a web link goes to the browser, no lobby error. The map step (`setup-container.sh map`, pr-downloader in
   the container) ran on the phone: exit 0, the map in place (it downloads even a map already there; the lobby only
   asks for missing ones). Not yet checked in the phone's lobby: the Replays tab, a map download, a link;
   `bridge` lines in launcher.log. Thumbnails, other engines and Discord stay unanswered (the lobby does not wait for those).
4. Upstream, with Kailil's go-ahead (drafts ready in `docs/upstream/`): the save-load crash (Recoil/BAR); lfdevs Mesa: `dri3_dmabuf_sync_file_unavailable`
   takes the CPU-wait path on KGSL whenever the kernel supports `DMA_BUF_IOCTL_EXPORT_SYNC_FILE`, though KGSL never
   attaches fences to the dma-buf (our ioctl answer is the workaround); the ARM64 AI bug (RecoilEngine issue, then
   the CircuitAI patch), disclosing AI assistance per `AI_POLICY.md`.
5. 30 fps for hours: read the `[perf]`/`[bardroid-perf]` lines of long sessions; a potato/default switch in game.
6. **Hand-off to BAR's developers** (Kailil, 2026-10-27): when development ends, the port goes to BAR's developers
   to take in. It must have no known bugs and build from a clone with README's three steps; every fix keeps
   `tools/laptop-tests.ps1` passing. Kailil, 2026-10-28: a GitHub release, then a post in BAR's Discord (modding
   discussion) asking the community and devs to check it and make it official; he will not own or continue it, and
   needs help with engine-side optimization and touch controls ([docs/HELP-WANTED.md](docs/HELP-WANTED.md), the post
   drafted in `C:\Tools\BARANDROID\discord-post.md`).

## Licensing
Engine GPL-2.0+; BAR game code GPL-2.0; BAR art CC-BY-NC-ND 4.0 (never bundle, never re-encode; download from the
official CDN like the launcher does); termux-x11 `lorie` GPL-3.0 → this app is GPL-3.0; proot GPL-2.0; busybox
GPL-2.0; Mesa MIT; AngelScript zlib (the stub).
