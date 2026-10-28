# CLAUDE.md — BAR Droid (Beyond All Reason on Android)

Working folder on the laptop: `C:\Tools\BARANDROID\` (this project is `bar-droid-app/` inside it).
Owner: Kailil (GitHub UnderarmCape). Goal: a sideloadable APK that plays BAR. **It plays on Kailil's Galaxy Z Fold7**
(~30 fps); the emulator on this laptop stays the quick test bench. Phone adb: USB (serial R3CY70B9VRH) or Wi-Fi
`adb connect 192.168.1.196:5555` (after `adb tcpip 5555`, until the phone reboots; the phone must be on the laptop's
Wi-Fi "MoUniqueHelp": "Mounique Help 5G" is a separate network, 192.168.12.x, the laptop cannot reach it). Kailil checks fps and sound
themselves: do not run monitoring on the phone while Kailil plays. Install every new phone build right away, even
over a running game; never ask first (Kailil). Test on the phone only (Kailil, 2026-10-25): Kailil does the check
(fold, play, lobby), you read the logs; no emulator, and don't drive the phone's game yourself unless asked.

## Architecture in one breath
Unmodified official **Recoil engine** (amd64 build for the emulator, arm64 for phones) runs inside a **Debian trixie
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
  interface scale, widget orders; spring), `springsettings.cfg` (preset; emulator overrides in
  `Installer.EMULATOR_GRAPHICS`), `libbardroid_pace.so` (`tools/pace/pace.c`, `tools/build-pace.py`; LD_PRELOADed
  into the engine: the frame cap after `SDL_GL_SwapWindow`, the ioctl answer that puts lfdevs' Mesa on its
  explicit Present fence, so the swap never waits for the GPU (HANDOFF "Busy scenes"), and SDL2 HIDDEN/SHOWN window
  events while the game screen is stopped (`/tmp/bardroid-hidden`, the engine stops drawing) or a joined game is
  being caught up far behind (`/tmp/bardroid-catchup`, from `bardroid_touch.lua`'s `bardroid_catchup.txt` via
  `GameActivity`), and SDL2's display size answers that follow fold/unfold (the game window's size: SDL keeps the
  startup screen, the engine's screen matrices went wrong after a fold); `tools/pace-test.ps1`).
- `LobbyBridge` — stand-in for BAR's PC launcher behind the lobby, on by default (Chobby's `WG.Connector`, sl-connection.json):
  web links, the lobby's downloads, replay info for the Replays tab (HANDOFF "Next steps"). Test it against the real
  lobby on the laptop with `tools/lobby-bridge-test.ps1` (~30 s, isolated write dir).
- `PerfLog` — once a minute while a game runs, `[perf]` in launcher.log: thermal status, GPU/CPU clocks and caps,
  memory; `bardroid_touch.lua` logs `[bardroid-perf]` (fps, slowest frame, frames of each second) to infolog.
- `app/src/main/jniLibs/<abi>/` — prebuilt helpers, committed: from `tools/fetch-prebuilts.py <abi>` (Termux talloc,
  shmem and ANGLE, Debian busybox), `tools/build-proot.py <abi>` (proot + loader, NDK build with our ioctl filter; run
  after fetch-prebuilts, it links its talloc/shmem) and `tools/build-virgl.py <abi>` (virglrenderer + libepoxy, NDK
  build with our DXT fix).
- `Updater` + `docs/UPDATES.md` — every lobby/skirmish start updates engine, game and lobby like BAR's PC launcher
  (its launcher config), re-applies the Android layer (each tweak logs `!!! ANDROID LAYER` when its target is gone)
  and rolls back a set that fails fast on its first start. Launcher setting "Update BAR at every start".
- `RtsTouch` (finger gestures) + `assets/bardroid/bardroid_touch.lua` (smoothed camera, continuous pinch zoom, BAR's
  interface scale per Fold screen, long-queue drawing, "is the pointer on the interface" answers, the catch-up mode,
  the engine's unread G-buffer passes off: map while `AdvMapShading` is 0, features always); `GameActivity`
  wires them up. In the lobby `assets/bardroid/bardroid_lobby_touch.lua` (a LuaMenu widget; Chobby's
  `loadLocalWidgets`, set by launch-bar.sh): a drag on a list scrolls it, a tap on a server shows its details first
  (`tools/lobby-touch-test.ps1`). `assets/bardroid/bardroid_players.lua`: BAR's player list small until tapped (WG.advplayerlist_api).
  BAR's sandbox refuses `/option`, widget toggles and engine restarts from user widgets: settings go
  in through `launch-bar.sh` instead. `tools/touch-widget-test.ps1` runs the widget in a real skirmish on the laptop
  (~1.5 min): pinch, twist, tilt and drag on the camera, and the map/interface answers; run it after touching either.
- `termux-x11/` — upstream checkout (`tools/fetch-termux-x11.*`) with `patches/0*.patch`: 0001 CmdEntryPoint loads
  libXlorie.so from `TERMUX_X11_LIBXLORIE_PATH`; 0002 Windows-host CMake build; 0003 the X server resizes full-screen
  top-level windows with the screen (fold/unfold; there is no window manager); 0004 our own knock port 17892 on
  loopback (the Termux:X11 app, if installed, knocks on 7892 every 250 ms); 0005 `LorieView.setCursorVisible`
  (`RtsTouch` hides the pointer while two or more fingers are down); 0006 `LorieView.maxScaledViewPixels` (unfolded,
  the X screen keeps the cover screen's pixel count: `GameActivity.MAX_SCREEN_PIXELS`); 0007 `LorieView.setUpscale`:
  the X screen enlarged onto the display through Qualcomm's SGSR 1 (`assets/sgsr`, BSD-3-Clause; `GameActivity`,
  settings "Sharper upscaling" and "Compare upscaling"; plain filtering if the GPU refuses the shader).
- The app icon opens the lobby (`LauncherActivity.openFromIcon`, setting "Open the lobby when the app starts");
  long-press the icon → "Launcher" (`res/xml/shortcuts.xml`) for the launcher screen. Regenerate a patch with `git diff`
  inside `termux-x11/` (LF endings; git through `toolchain\env.bat`).
- Gamepad: singleplayer plays Kailil's BAR Controller Support v0.8.5 1:1 as BAR's developer game
  ("Beyond All Reason $VERSION", `files/bar/games/BAR-gamepad.sdd`, depends on the BAR release it was ported to):
  `tools/build-gamepad-game.py` (rerun after a new v0.8.5 commit) → `assets/gamepad/`, `Installer.installGamepadGame`,
  `launch-bar.sh` (`GAMEPAD_GAME`). `ControllerBridge` is its companion (BARCTRL1 over UDP 28777, always streaming)
  and feeds the online gamepad camera in `bardroid_touch.lua`. Change v0.8.5 itself only in `C:\Tools\BARGAMEPAD`.
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
powershell -ExecutionPolicy Bypass -File tools\ui-screenshot.ps1 -Screen inner|cover   # BAR's HUD at a Fold layout
powershell -ExecutionPolicy Bypass -File tools\catchup-test.ps1 [-Warmup 300]       # a spectator joining late, ~5 min
powershell -ExecutionPolicy Bypass -File tools\lobby-touch-test.ps1                # the lobby widget (finger scrolling, server details), ~30 s
powershell -ExecutionPolicy Bypass -File tools\lobby-game-test.ps1                 # the lobby's Skirmish screen with the controller game, ~30 s
powershell -ExecutionPolicy Bypass -File tools\profile-big-game.ps1 [-AIs 6] [-FastMinutes 25] [-ProfileFastAtMinute 15] [-Functions] [-Gadgets] [-Settings @{Key=1}]
                                                                         # where a big game's CPU goes (widgets, unsynced gadgets, engine timers)
python -I tools\demo-rate.py <replay.sdfz>                               # game message bytes per game-second
powershell -ExecutionPolicy Bypass -File tools\phone-bench.ps1 [-Scale 100|85|70] [-Cap 0|30|60] [-Label text] [-Profile widgets|gadgets] [-Settings @{Key=1}]
            # BAR's "Benchmark BAR" scenario on the phone, unattended (launcher "Benchmark" button, or
            # `am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench`): warms the phone up into the
            # throttled state a late game plays in (Kailil: measure hot, back to back), then Sim/Draw/Update ms per frame,
            # game speed, clocks every 5 s (tools/phone-clocks.sh) and the busiest threads -> build\phone-bench.csv; one
            # run at a time across sessions (lock C:\Tools\BARANDROID\phone-bench.lock). Only while Kailil is not using the phone.
powershell -ExecutionPolicy Bypass -File tools\profile-benchmark.ps1 [-NoProfilers] [-AlsoOff "Widget"] [-Functions -Detail "Widget"]
            # the same scenario on the laptop as the phone runs it, every widget, unsynced gadget and engine timer logged
```
Ad-hoc commands: `cmd /c "call C:\Tools\BARANDROID\bar-droid-app\scripts\env.bat && <command>"` (PowerShell tools: dot-source
`tools\toolchain.ps1` for `$TC`) (`%VARS%` on that line expand
before env.bat runs; use literal paths). `adb shell` quoting through PowerShell is fragile: push a script with
`adb exec-in run-as com.underarmcape.bardroid sh -c "cat > files/x.sh"` and run it.
The lobby tests run logged in (Kailil): `C:\Tools\BARANDROID\bar-lobby-login.txt`, written by Kailil alone, outside the
repository; never read it aloud, print or commit it (`tools\toolchain.ps1` Get-LobbyLoginLua; empty: the test lobby
waits up to 5 minutes for a login by hand).
Laptop checks start spring from `build\engine\<engine>` (`tools\toolchain.ps1` Get-EngineDir), never from BAR's
install folder: Kailil's has ReShade beside `spring.exe`.
Never install tools globally or write to AppData/the profile. The emulator writes `.emulator_console_auth_token` to
the real profile anyway; `Run in Emulator.bat` deletes it (also a stale one after a crash).
Toolchain: AGP 9.3.1, Gradle 9.8.2 wrapper, NDK 29.0.14206865, CMake 3.22.1, JDK 21. One ABI per APK.
Logcat tags: BarDroid/app svc install x11 engine rootfs virgl proc, plus LorieNative, CmdEntryPoint.

## Rules of the road
- Never bundle or re-encode BAR game content (CC-BY-NC-ND). Download from `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` only.
  One exception, Kailil's call (2026-10-25): the app icon is Kailil's edit of BAR's launcher icon (an Android robot
  added), credited in `NOTICE.md`; personal use only (NoDerivatives), so an APK with it must not be published. The
  app is named "Beyond All Reason".
- Keep the engine binary unmodified and pinned to the version BAR's servers run (launcher config: https://launcher-config.beyondallreason.dev/config.json).
- Upstream PRs to RecoilEngine/CircuitAI must reference an accepted issue and disclose AI assistance (their `AI_POLICY.md`).
- Device data layout: `files/rootfs` (container), `files/bar` (engine write-dir, bound at `/root/bar`), `files/logs`, `Android/data/<pkg>/files/import`.
- When something fails on device, first read `files/logs/launcher.log` (everything, including child process output) and `files/bar/infolog.txt`.
- Paths handed to proot must be canonical (`Paths`): in the app's mount namespace `/data/user/0` is a symlink to `/data/data`.
- Never keep exec'able paths into `nativeLibraryDir` on disk (symlinks, saved paths): it moves on every app update.
- Child processes go through `Proc`; Stop SIGKILLs every process of the app's UID (proot ignores SIGTERM and orphans
  its tracees). `XServer`/`VirglServer` inherit the app environment (app_process and EGL need it).
- No `--kernel-release` for proot on kernels >= 4 (its kompat extension traps every futex: half the render thread).
- `MaxParticles` stays >= 10000 (BAR's minimum): lower values kill unsynced LuaRules and no unit is drawn.
- proot's seccomp filter must not trap syscalls proot does not act on (each trap = two ptrace stops; GPU drivers make
  hundreds of ioctls per frame). Phone Mesa must be lfdevs 27.0.0-devel-20261025 or newer (KGSL present fence: flicker).
- The lobby needs `chobby_config.json` in the write dir (launch-bar.sh writes it, as BAR's launcher does).
- Compare frame rates with the developer fps widget (`tools/dev/bardroid_fps.lua`, docs/HISTORY.md) and the laptop awake: Modern Standby throttles ~2.5x.

## Open risks (see HANDOFF.md)
Emulator: ~20 fps at best (laptop awake), limited by virgl/ANGLE host round trips; memory tight (12 GB guest, little
host RAM left; the low-memory killer once took the app). Phone: RAM (~5–6 GB a match), BAR's UI on the near-square
inner display, a drag that starts on BAR's build/order menus pans (they have no `IsAbove`; the top bar and BAR's
windows are covered: `bardroid_touch.lua` overBarInterface, `tools/touch-widget-test.ps1`), touch-only play (later).
