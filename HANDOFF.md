# BAR Droid — hand-off (updated 2026-10-25 ~16:45 EDT)

Beyond All Reason on Android. An Android app ("BAR Droid") that runs the **unmodified official Recoil engine**
inside a Debian container with an **embedded X server** (Termux:X11's `lorie` library) and Mesa for desktop OpenGL.

**Target right now: the Android emulator** (Kailil, 2026-10-25: "run exclusively on the Android emulator first, test on
real phones much later"). The default build is x86_64: amd64 Debian + the official amd64 engine, with the container's
OpenGL drawn on the laptop's GPU (Mesa virpipe → virgl server → ANGLE → Vulkan → the emulator's gfxstream → host GPU).
The arm64 phone build (Adreno via Mesa Freedreno/Turnip) still builds: `Build APK.bat phone`.

Read this file, then `CLAUDE.md`, then `RESEARCH.md`. Plan doc: https://claude.ai/artifact/XDdcJwfebpK1D138U2MjZf

## State

| Piece | Path | State |
| --- | --- | --- |
| Research + plan | `RESEARCH.md`, claude.ai doc | Done |
| Portable Windows toolchain | `..\toolchain\`, `..\Install Toolchain.bat` | Done; nothing in AppData or the profile |
| Emulator build (x86_64, default) | `..\Build APK.bat` → `..\apk\bar-droid-emulator-debug.apk` | **BAR plays in the emulator**: install from BAR's CDN, Play vs AI, BARb AI, units + full BAR UI, sim x1.00, **~20 fps** at 1256×568 at the start camera with the laptop awake (~8 fps while Windows is in Modern Standby), ~1 min to load a skirmish |
| Emulator runner | `..\Run in Emulator.bat` | Done: creates the AVD (Android 14, 12 GB RAM, 6 cores — the emulator's maximum, 32 GB, `hw.gltransport=asg`), boots, installs, opens the app |
| Phone build (arm64) | `..\Build APK.bat phone` → `..\apk\bar-droid-phone-debug.apk` | Builds (checked 16:37); never run on a phone. Lacks the virgl/ANGLE GPU path (not needed with Adreno) |
| Share logs | launcher button | Zips the logs into Android's share sheet (Taildrop, Drive, mail): phone debugging without adb |
| virgl GPU server | `tools/build-virgl.py` | Built from source with the NDK (Termux's binary turns every DXT texture black, see below) |
| ARM64 AI bug fix | `app/src/main/assets/bardroid/libasarm64.so`, `patches/circuitai-cmake-arm64-linux.patch` | Phone build only; not filed upstream yet |

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
display and handles touch/mouse/keyboard; `launch-bar.sh` runs inside proot: waits for the socket, starts PulseAudio
with `module-pipe-sink` → FIFO → `AudioPump` → `AudioTrack`, runs a one-time `glxinfo` probe, then
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

## Phone requirements
Qualcomm Adreno 7xx/8xx (Snapdragon 8 Gen 2/3/8s Gen 3/8 Elite), 12 GB RAM, ~6 GB free, Android 10+.
Mali/Xclipse/Tensor: no Mesa path → the app's device check says so.

## Next steps (in order)
1. Emulator frame rate beyond ~20 fps: the per-frame depth-copy context switch in vrend's fallback blitter and
   ANGLE's per-submit fence checks (see the afternoon session). Measure with the laptop awake.
2. Touch/keyboard feel in the emulator window (mouse works as mouse there; see the touch mapping below).
3. Controller widgets. The earlier plan was to copy attempt-01's `controller_socket_bridge.lua` + `gui_controller_*`
   into `files/bar/LuaUI/Widgets`. **Not done on purpose**: `C:\Tools\BARGAMEPAD\docs\lessons-from-attempt-01.md`
   (restarted 2026-10-25) lists the companion bridge and the 19k-line widget under "do not repeat". Decide which widget
   set the phone should use; the app's UDP side (`BARCTRL1`) is ready either way.
4. File the ARM64 AI bug upstream (RecoilEngine issue first, then the CircuitAI patch), disclosing AI assistance per
   `AI_POLICY.md`; report the virglrenderer-android DXT bug to Termux.
5. Later, phones: `Build APK.bat phone`, `Install on Phone.bat`, Install / Update, GL check, Play vs AI; **Share logs**
   sends the logs back without adb.

## Licensing
Engine GPL-2.0+; BAR game code GPL-2.0; BAR art CC-BY-NC-ND 4.0 (never bundle, never re-encode; download from the
official CDN like the launcher does); termux-x11 `lorie` GPL-3.0 → this app is GPL-3.0; proot GPL-2.0; busybox
GPL-2.0; Mesa MIT; AngelScript zlib (the stub).
