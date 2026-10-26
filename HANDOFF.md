# BAR Droid — hand-off (updated 2026-10-25 ~20:00 EDT)

Beyond All Reason on Android. An Android app ("BAR Droid") that runs the **unmodified official Recoil engine**
inside a Debian container with an **embedded X server** (Termux:X11's `lorie` library) and Mesa for desktop OpenGL.

**BAR plays on Kailil's Galaxy Z Fold7** (since the evening of 2026-10-25): ~30 fps, "100 percent fully playable"
against the AI (Kailil). The emulator build (x86_64, the default of `Build APK.bat`) is still the quick test bench:
amd64 Debian + the official amd64 engine, OpenGL through Mesa virpipe → virgl server → ANGLE → host GPU. Phone build:
`Build APK.bat phone` (arm64, Adreno via Mesa Freedreno on KGSL). adb to the phone: USB, or Wi-Fi
`adb connect 192.168.1.196:5555` after `adb tcpip 5555` (until the phone reboots; NordVPN on the laptop blocks it
unless its local-network access is on; Tailscale times out).

Read this file, then `CLAUDE.md`, then `RESEARCH.md`. Plan doc: https://claude.ai/artifact/XDdcJwfebpK1D138U2MjZf

## State

| Piece | Path | State |
| --- | --- | --- |
| Research + plan | `RESEARCH.md`, claude.ai doc | Done |
| Portable Windows toolchain | `..\toolchain\`, `..\Install Toolchain.bat` | Done; nothing in AppData or the profile |
| Emulator build (x86_64, default) | `..\Build APK.bat` → `..\apk\bar-droid-emulator-debug.apk` | **BAR plays in the emulator**: install from BAR's CDN, Play vs AI, BARb AI, units + full BAR UI, sim x1.00, **~20 fps** at 1256×568 at the start camera with the laptop awake (~8 fps while Windows is in Modern Standby), ~1 min to load a skirmish |
| Emulator runner | `..\Run in Emulator.bat` | Done: creates the AVD (Android 14, 12 GB RAM, 6 cores — the emulator's maximum, 32 GB, `hw.gltransport=asg`), boots, installs, opens the app |
| Phone build (arm64) | `..\Build APK.bat phone` → `..\apk\bar-droid-phone-debug.apk` | **Plays on the Galaxy Z Fold7** (Adreno 830, Android 17): ~30 fps capped (60 fps option), no flicker, lobby, touch controls, fold/unfold resize. Lacks the virgl/ANGLE GPU path (not needed with Adreno) |
| proot | `tools/build-proot.py` | Our build of Termux's proot (pinned commit) whose seccomp filter stops only for the ioctls proot handles: 14 → 30 fps on the phone |
| Touch controls | `RtsTouch.java`, `assets/bardroid/bardroid_touch.lua` | One finger pans, pinch zooms, twist rotates, two fingers up/down tilt (see below) |
| Gamepad | `tools/build-gamepad-game.py` → `assets/gamepad/`, `Installer.installGamepadGame`, `ControllerBridge`, `bardroid_touch.lua` | Singleplayer plays Kailil's BAR Controller Support v0.8.5 1:1 as BAR's developer game; online games get a gamepad camera (see "Gamepad" below) |
| Share logs | launcher button | Zips the logs into Android's share sheet (Taildrop, Drive, mail): phone debugging without adb |
| virgl GPU server | `tools/build-virgl.py` | Built from source with the NDK (Termux's binary turns every DXT texture black, see below) |
| ARM64 AI bug fix | `app/src/main/assets/bardroid/libasarm64.so`, `patches/circuitai-cmake-arm64-linux.patch` | Phone build only; not filed upstream yet |

## Phone session (2026-10-25, 17:00–20:00): first runs on the Fold7

Results on the Galaxy Z Fold7 (SM-F966N, SM8750 / Adreno 830, Android 17, 11.4 GB RAM; inner display 2184×1968 at
up to 120 Hz, cover 1080×2520 at 60 Hz):
- **Flicker** (frames shown before the GPU finished them): lfdevs' Mesa before 27.0.0-devel-20261025 lacks the KGSL
  present-wait fence. `Prefs.mesaUrl` is now that build; `Installer.mesaOutdated()` reinstalls Mesa when the saved
  URL is older (Play runs the install first). Kailil: "flicker is solved fully".
- **14–15 fps → ~30 fps**: Termux's proot puts `ioctl` in its seccomp filter with an exit stop on Android, so every
  KGSL GPU-driver ioctl cost two ptrace stops (18,600 proot wake-ups/s, libproot 48% CPU). `tools/build-proot.py`
  builds proot (termux/proot `b27d81a`, sha256-pinned) with the NDK and patches `syscall/seccomp.c` so `ioctl` traps
  only for the requests proot handles (SIOCGIFINDEX, TCSETSF, TCGETS2/TCSETS*2, FICLONE). Checked on the phone and the
  emulator with a perl loop: 0 of 200 `TCGETS` ioctls stop, 50 of 50 `TCSETSF` still do, futex untouched. The
  loader is built like Termux's (`-Ttext=<LOADER_ADDRESS>,--rosegment`, same segment layout). `fetch-prebuilts.py`
  no longer writes proot.
- **Audio gaps**: the chain was engine → SDL → PulseAudio `module-pipe-sink` → FIFO → `AudioTrack`. AudioFlinger
  showed 0 underruns with ~380 ms queued, so the holes were already in the stream: whenever SDL's audio callback was
  late, PulseAudio rendered silence. Now `UseSDLAudio = 0` and OpenAL Soft's **wave writer** writes straight into the
  FIFO (`/root/.alsoftrc`: `drivers = wave`, 48 kHz stereo int16); its mixer thread is paced by the clock and catches
  up after a stall. `AudioPump` parses the WAV header and starts the track with 200 ms queued (also less latency than
  the ~700 ms before). PulseAudio is no longer started. Kailil: "sound is perfect".
- **Lobby black screen**: Chobby needs `chobby_config.json` (BAR's launcher writes it from its config's
  `json_files`: server4.beyondallreason.info:8200, game `byar`); without it Chobby finds no game config and shuts
  down. `launch-bar.sh` writes it for lobby mode. On the phone Kailil logged in, browsed servers and spectated a
  multiplayer game.
- Frame cap: `VSync = VSyncGame × VSyncFraction` like BAR's options (BAR rewrites `VSync`); the app asks for a 60 Hz
  display mode and the widget picks the swap interval from the real refresh rate (30 fps default, 60 experimental).
- Fold/unfold: the activity is not recreated and the X screen follows the view. There is no window manager, so
  `patches/0003-lorie-fit-windows-on-resize.patch` makes the X server resize mapped top-level windows at the origin
  to the new screen size itself (in `lorieRRScreenSetSize`): works in the lobby, while a game loads (Flex/tent mode
  first hands the app part of the inner screen, then all of it) and in game. The patch also wraps `ConfigNotify`:
  when a client resizes such a window to anything but the screen size, a work proc fits it again. Needed because
  SDL keeps the display bounds it saw at startup and the engine clamps every window-attribute update to them
  (`GetWindowPosSizeBounded`): started unfolded, the cover screen's 1680x720 became 1456x720. For the same reason the
  widget must never call `Spring.SetWindowGeometry` (it did as a fallback and kept re-clamping). Each X screen size
  the app sees is logged (`[display]` in launcher.log). Tested on the emulator with `adb shell wm size` (lobby, three
  resizes while loading, in game); the ConfigNotify rule only on the phone (Kailil). Its first version called
  present's `ConfigNotify` without unwrapping, so present's own unwrap/rewrap dropped ours after one call (found with
  the `screen`/`fit window` lines lorie logs to logcat, tag LorieNative). The phone's logcat buffer is set to 5 MB
  (`adb logcat -G 16M`; the app floods it otherwise). Last piece: Chobby's LuaMenu widget "Resolution limiter" shrank
  the window to SDL's stale screen size on every ViewResize and toggled fullscreen, fighting the fit twice a second
  (black flicker); `launch-bar.sh` sets it to 0 in `LuaMenu/Config/IGL_order.lua`. **Kailil (21:50): folding and
  unfolding works perfectly** (lobby, either starting screen).
  Landscape only, both sides (`sensorLandscape`). Samsung's "continue apps on cover screen" must allow BAR Droid.
- RAM: a match uses ~5–6 GB (1.1 GB resident + swap at the time); the launcher no longer says 12 GB.
- **Memory (spectated 8v8, one snapshot each):** `recoil-main` held 5.2 GB anonymous (3.4 GB swapped), GPU (kgsl)
  only 341 MB; Android killed the app in the background for `LOW_MEMORY` (`dumpsys activity exit-info`).
  `VFSCacheArchiveFiles = 0` (the engine kept every file read from the pool archive in memory, decompressed) and
  `TextureMemPoolSize = 0` (512 MB image pool): 5.6 → 4.5 GB, phone free 1.1 → 1.5 GB. The rest is engine data
  kept on purpose (largest anonymous region 652 MB, nearly all swapped; QTPFS 234 MB; mimalloc already purges
  freed memory). Leaving the game now opens a floating window (Termux:X11 `PIP` pref, set once in
  `BarApp.applyDisplayDefaults`): visible, so Android almost never kills it. Background survival not yet confirmed.
- **Black squares for units zoomed out** (strategic icons): the engine builds its icon atlas (and the projectile
  atlas the Perlin smoke draws into) as `GL::Texture2D(..., wantCompress = true)` and renders into it through an FBO.
  With `CompressTextures = 1` Freedreno picks a compressed format, which is not color-renderable:
  `FBO-TEXTURE-RENDER-ATLAS: None/Unsupported textures/buffers attached`, `atlasRendered=0`, every icon black (also
  `FBO-PROJECTILE-DRAWER-PERLIN`). The emulator's virgl does not compress, so it never showed there. Now
  `CompressTextures = 0` always (the app setting is gone). Not yet seen on the phone.
- Lobby: `launch-bar.sh` turns Chobby's `drawAtFullSpeed` on once (`LuaMenu/Config/IGL_data.lua`, marker
  `.bardroid-lobby-fullspeed`); the player can turn it off again in the lobby's Settings.
- Mouse: `HardwareCursor = 1`, so lorie draws the pointer on every display frame instead of the engine once per game
  frame (verified: with spring SIGSTOPped the pointer still follows). The lobby is slow by design on top of the
  phone's speed: Chobby's `gfx_limit_idle_fps` runs it at VSync 2 (30 fps) while active and VSync 4 (15 fps) after
  1–2 s idle (and it measures time with `os.clock()`, CPU time); its Settings checkbox `drawFullSpeed` makes the
  active rate 60.

**Touch controls** (`RtsTouch`, on by default; off = Termux:X11's touch modes), Kailil's spec of 19:30:
tap = left click (double tap = double click); one-finger drag = pan (grab, with a fling); tap-then-drag = box select;
long press = right button (lift = order, drag = formation); two fingers = pan + pinch zoom (mouse wheel at the centre)
+ twist rotate; two fingers moving up/down side by side = tilt; two-finger tap = right click; three-finger tap =
keyboard; Back = Escape. The app talks to `bardroid_touch.lua` through files under `LuaUI/Config` (BAR's sandbox gives
user widgets no sockets). A one-finger drag that starts on the interface is a mouse drag instead: the widget is the
last `IsAbove` in line, so it hears about the pointer only where no widget claimed it, and answers through
`bardroid_hover.txt` (+ `Spring.IsAboveMiniMap`). That catches the minimap and modal windows (options); BAR's top bar,
build and order menus do not implement `IsAbove`, so a drag there pans (taps are fine). `CamSpringLockCardinalDirections
= 0`, or small twist steps never leave north. Tested on the emulator with injected multitouch (pan, twist, tilt);
not on the phone yet.

Next: Kailil checks audio, gestures, lobby and fold/unfold on the phone; then RAM, BAR's UI on the near-square inner
display (ui_scale), and touch-only play (later, Kailil).

## Afternoon session (2026-10-25, 12:40–16:45): units, speed, Share logs

**Invisible units (would have hit phones too).** Our presets set `MaxParticles` 2000 (phones) / 600 (emulator).
BAR's `gfx_fire_smoke_gl4` sizes a VBO at `(MaxParticles - 7000) * 2 + 10000`; at ≤ 0 `LuaVBOImpl::Define` throws while
unsynced LuaRules loads, the whole unsynced LuaRules dies and CUS GL4 (BAR's unit renderer) with it: no units, no
command panel. Now `MaxParticles = 10000` (bottom of BAR's own slider); the emulator no longer overrides particles,
LOD or icon distance. Commander, build menu, unit info and orders all work (`..\logs\emulator-units-ingame.png`).

**Frame rate, measured the same way each time** (developer widget `tools/dev/bardroid_fps.lua`, copied to the
device's `files/bar/LuaUI/Widgets/`, logs `[bardroid-fps]` to infolog every 10 s; not shipped by the app). All with the laptop in Modern Standby unless noted:
| Change | Result |
| --- | --- |
| Before | 2 fps, sim x0.5–0.7, skirmish load 3:21 |
| proot without `--kernel-release` (its kompat extension traps every `futex()`; spring's render thread spent ~45% in ptrace stops) | load 1:46, sim x1.00 |
| Emulator `hw.gltransport=asg` (shared-memory ring instead of the goldfish kernel pipe; 87% of the virgl server's CPU was in `goldfish_pipe_read_write`) | 7 fps (X server 45%→11% CPU), load 1:13 |
| virgl: no timer-query cap, deferred query polls, no per-command `glGetError` | ~8–9 fps; **~20 fps with the laptop awake** |
Not worth it (measured): `mesa_glthread=true` (≤5%), half the pixels (`displayScale` 270: +18%), ANGLE
`asyncCommandQueue` (not in this ANGLE build). Where the time goes now: spring's render thread waits in
`glXSwapBuffers` for virgl to finish and read back the frame; virgl waits on the host (ANGLE checks a fence after
every submit = a host round trip; vrend's fallback blit for the engine's per-frame Z24S8→Z32 depth copy switches GL
contexts twice per frame, each a flush + submit). Ideas left: avoid that context switch (an experiment storing
Z32_UNORM as DEPTH24_STENCIL8 showed no clear gain while throttled; not kept), fewer ANGLE submits.
**Host power matters**: Windows Modern Standby (lid/screen off) throttles the laptop to ~40% of the awake frame rate.
Check `Get-WinEvent` Kernel-Power 506/507 before comparing numbers.

Experiment, not usable yet: the emulator's own GLES driver instead of ANGLE (developer switch file
`files/bar/dev-virgl-native`; build-virgl.py adds a pbuffer fallback for EGL without surfaceless contexts). It lacks
geometry shaders and `OES_texture_3D` framebuffer attachments; libepoxy aborts the server on
`glFramebufferTexture3DOES` while BAR loads.

Developer hooks (none created by the app): `files/bar/dev-env.sh` (sourced by `launch-bar.sh`),
`files/bar/dev-springsettings.cfg` (appended to springsettings), `files/bar/dev-virgl-native`, `LuaUI/Widgets/*.lua`
in `files/bar`. Profiling: `adb root` works on the google_apis image; NDK `simpleperf` (pushed to `/data/local/tmp`)
with `--call-graph dwarf --trace-offcpu` shows wall time; the unstripped virgl library for symbols is
`build/virgl/build-x86_64/src/libvirglrenderer.so`.

Memory: once, the low-memory killer took the whole app ~40 s into a match (guest swap full). Later runs held at
~0.7 GB available. The laptop has 31.6 GB; other programs (llama-server ~14 GB, a Windows BAR) leave little room.

## Emulator-first session (2026-10-25, 08:50–11:10)

Why x86_64: Google's emulator cannot run ARM64 Android images on an Intel host, and on x86_64 images with ARM
translation proot cannot trace translated processes (it hangs). So the emulator build is x86_64 end to end:
- `tools/fetch-prebuilts.py <abi>`: Termux proot/talloc/shmem + Termux's ANGLE + Debian static busybox for any ABI,
  patched like the original arm64 set (`libtalloc.so`, `RUNPATH=$ORIGIN`).
- `-PbardroidAbi=x86_64|arm64-v8a` (root `build.gradle`) picks the ABI; `BuildConfig.TARGET_ABI` → `Prefs.EMULATOR_BUILD`
  switches the Debian image (dist-amd64), engine (`recoil_2026.07.04_amd64-linux.7z`), skips the Adreno Mesa tarball
  and the ARM64 AI stub, and selects the GPU path.

Fixed on the way (all would also have hit phones):
- **App processes see `/data/user/0` as a symlink to `/data/data`** (Android 11+ data isolation). proot canonicalizes
  its rootfs, so the hard-link symlinks written by `--link2symlink` (from `PROOT_L2S_DIR`) were unresolvable inside the
  app: Perl and every hard-linked file vanished, apt's maintainer scripts failed. `Paths` now uses canonical paths;
  the rootfs completion marker is versioned so older trees are rebuilt.
- proot's `.l2s` directory must exist before extraction, busybox tar aborts at the first error (a partial tree was
  accepted before), Debian's static busybox has no `--exclude`: rootfs extraction is now strict (exit code + loader
  check + completion marker; an incomplete tree is wiped).
- **Stop did not stop the game**: proot ignores SIGTERM (what `Process.destroy*` sends on Android) and leaves its
  tracees running when SIGKILLed. Stop now SIGKILLs every other process of the app's UID.
- `AudioPump` keeps draining the FIFO when no `AudioTrack` can be created (an emulator without audio).

GPU path (virpipe): `VirglServer` starts the virgl server next to the X server; Mesa inside the container uses
`GALLIUM_DRIVER=virpipe` + `MESA_GL_VERSION_OVERRIDE=4.3COMPAT` (virgl on GLES only advertises 2.1 compat; the host
has the GL4.3 features BAR uses). The engine reports `GL 4.3 (Compatibility Profile)`, renderer
`virgl (ANGLE (NVIDIA, Vulkan 1.3.0 (NVIDIA GeForce RTX ...)))`, "GL4 support: 1". Findings:
- The emulator's own EGL lacks `EGL_KHR_surfaceless_context`, so the server uses ANGLE (GLES on Vulkan, Termux's
  `angle-android`, bundled) via `--angle-vulkan` + `BARDROID_ANGLE_DIR`.
- **Termux's virglrenderer-android always decompresses DXT on the server and re-uploads with `glTexImage2D` into
  immutable compressed storage → GL_INVALID_OPERATION → every DXT texture black** (BAR's map tiles, minimap, unit
  skins). `tools/build-virgl.py` rebuilds virglrenderer 1.3.0 + libepoxy 1.5.10 with Termux's patches (pinned commit)
  and decompresses only when the host lacks S3TC, also recognizing ANGLE's per-format DXT extension names (upstream
  does not). Verified with a DXT1 test texture (`[255,0,0]` instead of `[0,0,0]`) and a textured map in game.
  Worth reporting to Termux.
- CPU rendering (llvmpipe, checkbox "Render on the CPU") works too: x0.70 speed, ~1 fps.

Emulator caveats
- (11:10) 3–4 fps, units invisible: both fixed in the afternoon session above.
- A host crash (PC restart) corrupted the emulator's data disk (kernel panic, ext4). Recovery: start the emulator once
  with `-wipe-data` (`Run in Emulator.bat -wipe-data`), then Install / Update again (~10 min, 4 GB download).
- Developer hook: long-press **GL check** = display + GPU server stay up for an hour without the game, for testing GL
  inside the container (`tools\container-shell.bat`).

## How the app works (one paragraph)

`LauncherActivity` → `GameService` (foreground). **Install**: `Installer` runs `libproot.so`/`libbusybox.so` straight
from the app's native-lib dir (the only place Android lets an app exec from), downloads the official Debian trixie
arm64 docker rootfs (layer digest read from the OCI manifest on GitHub, SHA-256 checked), extracts it with
`proot --link2symlink` + busybox tar (hard links → symlinks), runs `/opt/bardroid/setup-container.sh apt`
(SDL2/X11/OpenAL/fonts/xkb/Mesa pkgs/PulseAudio), installs **Mesa for Android containers** over Debian's Mesa,
downloads `recoil_2026.07.04_arm64-linux.7z`, then `pr-downloader` fetches `byar:test`, `byar-chobby:test` and one
map from BAR's own CDN (nothing of BAR's CC-BY-NC-ND art is bundled). **Play**: `XServer` starts
`com.termux.x11.CmdEntryPoint` (compiled into *our* APK) via `/system/bin/app_process` with `TMPDIR=<rootfs>/tmp`
so the socket is the container's `/tmp/.X11-unix/X0`; `GameActivity` (extends Termux:X11's `MainActivity`) shows the
display and handles touch/mouse/keyboard; `launch-bar.sh` runs inside proot: waits for the socket, points OpenAL
Soft's wave writer at the FIFO (→ `AudioPump` → `AudioTrack`), runs a one-time `glxinfo` probe, then
`spring --isolation --write-dir /root/bar skirmish.txt` (or `--menu rapid://byar-chobby:test`). Gamepad events are
intercepted in `GameActivity` and sent as `BARCTRL1|...` UDP packets to 127.0.0.1:28777 (UnderarmCape's controller
companion protocol).

## Laptop session, night (2026-10-25, 02:40–03:50) — history

Toolchain + build
- Nothing was installed on the laptop. Added `toolchain\env.bat` (process-local: JAVA_HOME, ANDROID_HOME,
  GRADLE_USER_HOME, ANDROID_EMULATOR_HOME, HOME/USERPROFILE/APPDATA/TEMP all redirected into `toolchain\`),
  `toolchain\install-toolchain.ps1` and the top-level `.bat` launchers. Google replaced `sdkmanager` with the
  "Android CLI" (`android.exe sdk install ndk/29.0.14206865 ...`, package names use `/`); the installer uses it with
  `--no-metrics`. The Android SDK terms were accepted on Kailil's go-ahead.
- termux-x11's native build assumes a Linux host. `patches/0002-lorie-windows-host-build.patch` (applied by
  `tools/fetch-termux-x11.*`; every change is inside `if(CMAKE_HOST_WIN32)` or host-neutral) adds: `git apply` instead
  of bash+GNU patch (with `recipes/fix-patch-headers.py` normalizing patches git rejects, and `--unidiff-zero`),
  host gcc from `$LORIE_HOST_CC` for `makekeys`, copies instead of symlinks (no Developer Mode needed), and a
  case-insensitivity fix (the NDK's `<xlocale.h>` resolved to X11's `Xlocale.h`).
- Native libs: AGP now strips `libXlorie.so` (21 MB → 3.5 MB; `ndkVersion` pinned in `app/build.gradle`); the prebuilt
  proot/talloc/busybox are excluded from stripping so they stay byte-identical to the Termux/Debian builds.

Bugs found and fixed
- **Any app update broke every container step**: `files/bin/proot` symlinks pointed into the old native-lib dir
  (Android moves it on each update). proot/busybox now run in place; assets and container scripts are refreshed
  before every install and launch. (Found on the emulator.)
- **The X server could never start**: `XServer` cleared the environment, so `app_process` had no BOOTCLASSPATH /
  ANDROID_ART_ROOT and died silently. Now inherits the app's environment. (Found on the emulator.)
- **Stop left proot running** (installer children were untracked): `Proc.killAll()` on Stop; an interrupted wait
  kills its child.
- busybox `tar` would have refused to run (bound as `/.bardroid-busybox`, "applet not found"); now `/busybox-bardroid`.
- Debian's `/usr/share/X11/xkb` is a symlink; the host-side X server now resolves symlinks inside the rootfs.
- Crashes on Android 9–12: `InputStream.readAllBytes()` (API 33) and `Build.SOC_MODEL` (API 31).
- `AudioPump.stop()` could leave a thread blocked opening the FIFO (two readers on the next game).
- The game screen stayed open after the engine exited; it now closes and the launcher comes back.
- Termux:X11's activities/receivers were exported (meant for the Termux app, another UID); now non-exported.
- First-run display defaults for a game: full screen, landscape, no extra-keys bar, screen kept on, "simulated
  touchscreen" (tap = click at the finger), X screen scaled to ~720p. All adjustable under Display prefs.

Emulator smoke test (Android 14 x86_64 with ARM translation; `tools\emulator-test.bat`) — passed:
- Launcher UI, device check, settings; specialUse foreground service; notification permission prompt.
- Debian rootfs download + SHA-256; proot starts from the native-lib dir (then stalls: proot cannot ptrace
  ARM-translated processes, an emulator limit).
- **Open risk closed: on Android 14, `app_process` with `CLASSPATH=<our base.apk>` runs `CmdEntryPoint` from our
  APK.** With an emulator-only x86_64 X server, the whole display path works: X server up, socket at the container's
  `/tmp/.X11-unix/X0`, ACTION_START reaches our non-exported receiver, `GameActivity` connects (60 Hz), full-screen X
  root window with the game defaults.
- Gamepad bridge: `BARCTRL1` packets at ~60 Hz on 127.0.0.1:28777; injected gamepad A → button bit 0, then released.
- Stop during install and during play kills X server + proot and closes the display. Audio FIFO is created.
- Not testable there: container (proot), apt, Mesa, engine, GL, audio playback.

Static checks of the container side (scripts kept in the session scratchpad; easy to redo with Python):
- All 37 packages in `setup-container.sh apt` exist in Debian trixie arm64. `p7zip-full` is now a transitional
  package for `7zip` 25.01, which still ships `/usr/bin/7z`.
- Every `DT_NEEDED` of the 9 ELF files in `recoil_2026.07.04_arm64-linux.7z` (spring: SDL2, X11, Xcursor, OpenAL,
  glibc) and of the Mesa tarball's 7 ELF files is provided by the container (base image + dependency closure of the
  apt list = 295 packages).
- The Mesa tarball carries `dri/kgsl_dri.so`, `dri/zink_dri.so`, Turnip (`libvulkan_freedreno.so` + ICD json) and
  `libgallium-26.2.0-devel.so`; it overwrites Debian's Mesa files in place as intended.
- glxinfo, vulkaninfo, pulseaudio (+ module-pipe-sink / module-native-protocol-unix), 7z, ldconfig, fc-cache are all
  in installed packages.

Debugging on the phone: the app writes `files/container.sh` before every install/launch, so
`bar-droid-app\tools\container-shell.bat` gives a root shell in the phone's container (or runs one command:
`container-shell.bat "glxinfo -B"`).

## Build / run (Windows laptop)

```
Install Toolchain.bat --accept-licenses   one time; ~1.5 GB into toolchain\ (Android SDK terms)
Build APK.bat                             emulator build (x86_64) -> apk\bar-droid-emulator-debug.apk
Run in Emulator.bat                       boots the emulator (first time ~1.8 GB download), installs + opens the app
Get Logs.bat                              launcher.log, infolog.txt, glcheck, pulse.log, logcat -> logs\device-<time>\
Build APK.bat phone / Install on Phone.bat   the arm64 phone build
Pair Phone.bat [pair-port code connect-port]  wireless adb over Tailscale (phone: Wireless debugging, needs Wi-Fi)
Get Logs.bat phone                            logs from the phone while the emulator also runs
```
Kailil's phone: Galaxy Z Fold7 (Snapdragon 8 Elite / Adreno 830, so the Freedreno/Turnip path), Tailscale name
`kailils-z-fold7` (100.103.32.18). No USB adb; wireless debugging over Tailscale only, and Android enables it only
while the phone is connected to some Wi-Fi (its own hotspot does not count; Wi-Fi without internet is fine). The
phone already lists `kaili@KAILILLAPTOP` under Paired devices, so usually only the connect port is needed:
`Pair Phone.bat - - <port>`. Samsung's Auto Blocker can block adb installs. Waiting for Kailil to be on Wi-Fi.
In the app: **Install / Update** (Debian + engine + BAR content, ~4 GB, ~10 min) → **Play vs AI**.
Native helper binaries: `tools/fetch-prebuilts.py <abi>` (proot, busybox, ANGLE) and `tools/build-virgl.py <abi>`
(virgl server); both run with the toolchain's Python inside `toolchain\env.bat`. Their output is committed under
`app/src/main/jniLibs/<abi>/`, so a normal build needs neither.
Toolchain pinned by termux-x11: AGP 9.3.1, Gradle 9.8.2 (wrapper), NDK 29.0.14206865, CMake 3.22.1, JDK 21.
One ABI per APK.

## Open risks
- Freedreno (`MESA_LOADER_DRIVER_OVERRIDE=kgsl`) compat-profile GL version on the phone; fallback `zink`, then
  `MESA_GL_VERSION_OVERRIDE=4.5COMPAT` (checkboxes in the app).
- proot on the phone (seccomp; `PROOT_NO_SECCOMP` checkbox) and its speed loading 3.4 GB of archives.
- RAM: BAR wants 12 GB; measure on device.
- Touch (Termux:X11 "simulated touchscreen", from its TouchInputHandler; untested with BAR): 1-finger tap = left
  click at the finger, 2-finger tap = right click (orders), 3-finger tap = middle click, long-press then drag = left
  drag (box select), 2-finger long-press drag = right drag (formation move), 3-finger long-press drag = middle drag
  (camera pan), 2-finger swipe = mouse wheel (zoom), 3-finger swipe down = toggle the extra-keys bar (Esc/Ctrl/Alt).
  Whether this is playable needs the phone; a Lua gesture layer may follow.

## Gamepad (2026-10-26)
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
over our `Shadows = -1`.

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
- Loading BAR saves crashed (SIGSEGV in "Loading Saved Game", no stack): Recoil's save support; not investigated.
- **Still waiting on the GPU (spectating an 8v8, 226-418 units, 23-24 fps; 2026-10-26, with the pace cap):** the main
  thread is busy ~50% and blocked in `0x400c0907` 42%; GPU 342 MHz of 1200, 61-76% busy (no thermal cap); the prime
  cores (cpu6-7) idle at 1017 MHz, the main thread runs on cpu0-5. Its stack while blocked (read from
  `/proc/<pid>/mem` at the SP in `/proc/<pid>/task/<tid>/syscall`; simpleperf has no off-CPU events on this phone;
  `stackparse.py`/`symchain.py`-style scan, libgallium has a symtab): 29 of 30 samples in immediate mode,
  `_mesa_Color4fv` → `vbo_exec_wrap_upgrade_vertex` → `_mesa_bufferobj_map_range` → `tc_buffer_map` (`_tc_sync`) →
  `fd_resource_transfer_map` → `__fd_resource_wait` → `fd_bo_cpu_prep` → KGSL wait. So the GL immediate-mode
  vertex buffer (Lua `gl.BeginEnd`/`gl.Color`/`gl.Vertex` and the engine's own `glBegin` paths) is mapped while the
  GPU still uses it, and the CPU waits for the GPU each time. Untested ideas: `mesa_glthread=true` (moves the waits
  off the main thread), `GALLIUM_THREAD=0`, `MESA_EXTENSION_OVERRIDE=-GL_ARB_buffer_storage` (vbo's other map path);
  try them through `files/bar/dev-env.sh` on a replay of the same game and compare the `[bardroid-perf]` seconds.

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

## Phone requirements
Qualcomm Adreno 7xx/8xx (Snapdragon 8 Gen 2/3/8s Gen 3/8 Elite), 12 GB RAM, ~6 GB free, Android 10+.
Mali/Xclipse/Tensor: no Mesa path → the app's device check says so.

## Next steps (in order)
1. Emulator frame rate beyond ~20 fps: the per-frame depth-copy context switch in vrend's fallback blitter and
   ANGLE's per-submit fence checks (see the afternoon session). Measure with the laptop awake.
2. Touch/keyboard feel in the emulator window (mouse works as mouse there; see the touch mapping below).
3. Gamepad: done as Kailil chose (2026-10-26), see "Gamepad". Measure v0.8.5's frame cost on the phone.
4. File the ARM64 AI bug upstream (RecoilEngine issue first, then the CircuitAI patch), disclosing AI assistance per
   `AI_POLICY.md`; report the virglrenderer-android DXT bug to Termux.
5. Later, phones: `Build APK.bat phone`, `Install on Phone.bat`, Install / Update, GL check, Play vs AI; **Share logs**
   sends the logs back without adb.

## Licensing
Engine GPL-2.0+; BAR game code GPL-2.0; BAR art CC-BY-NC-ND 4.0 (never bundle, never re-encode; download from the
official CDN like the launcher does); termux-x11 `lorie` GPL-3.0 → this app is GPL-3.0; proot GPL-2.0; busybox
GPL-2.0; Mesa MIT; AngelScript zlib (the stub).
