# BAR Droid — hand-off (updated 2026-10-25 ~03:50 EDT, laptop session)

Beyond All Reason on Android. An Android app ("BAR Droid") that runs the **unmodified official arm64 Recoil engine**
inside a Debian container with an **embedded X server** (Termux:X11's `lorie` library) and Mesa (Freedreno/Turnip)
for desktop OpenGL.

Read this file, then `CLAUDE.md`, then `RESEARCH.md`. Plan doc: https://claude.ai/artifact/XDdcJwfebpK1D138U2MjZf

## State

| Piece | Path | State |
| --- | --- | --- |
| Research + plan | `RESEARCH.md`, claude.ai doc | Done, verified against cloned sources and live endpoints |
| Phase-1 manual kit (Termux + proot + Mesa, no app) | `../phase1-kit/` | Written, never run on a phone |
| ARM64 AI bug fix | `app/src/main/assets/bardroid/libasarm64.so`, `patches/circuitai-cmake-arm64-linux.patch` | Verified under qemu-aarch64 (cloud session); not filed upstream yet |
| Engine-on-ARM proof | `../logs/emulated-run*.log` | arm64 `spring-headless` + BAR + map + 2 AIs reach "now ingame" under qemu (no GPU) |
| Portable Windows toolchain | `..\toolchain\`, `..\Install Toolchain.bat` | **Done.** JDK 21, MinGit, Android SDK 34 / NDK 29 / CMake 3.22.1, host Python/bison/gcc, all inside `toolchain\`; nothing in AppData or the profile |
| APK | `..\Build APK.bat` → `..\apk\bar-droid-0.1.1-debug.apk` | **Builds on the laptop** (17.8 MB). `..\apk\superseded\bar-droid-0.1.0-debug.apk` is the cloud build from before tonight's fixes; do not use it (its X server cannot start) |
| Android-side runtime | app | **Smoke-tested on an Android 14 x86_64 emulator** (below). Container/engine side untested: needs a real arm64 phone |
| Phone test | — | **Not done: no phone was connected.** This is the next step |

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

## Laptop session (2026-10-25, 02:40–03:50)

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

## Build / install (Windows laptop)

```
Install Toolchain.bat --accept-licenses   one time; ~1.5 GB into toolchain\ (Android SDK terms)
Build APK.bat                             first build ~5 min (X server via NDK), then ~1 min
Install on Phone.bat                      adb install -r + start (USB debugging on, one device connected)
Phone Logs.bat                            launcher.log, infolog.txt, glcheck, pulse.log, logcat → logs\phone-<time>\
```
Developer: `bar-droid-app\tools\emulator-test.bat` (builds the emulator variant, which replaces the APK in
`app\build`; rebuild before installing on a phone). Linux/WSL: `tools/fetch-termux-x11.sh` + `./gradlew :app:assembleDebug`.
Toolchain pinned by termux-x11: AGP 9.3.1, Gradle 9.8.2 (wrapper), NDK 29.0.14206865, CMake 3.22.1, JDK 17+ (21 used).
Only `arm64-v8a` is built.

## Open risks
- Freedreno (`MESA_LOADER_DRIVER_OVERRIDE=kgsl`) compat-profile GL version on the phone; fallback `zink`, then
  `MESA_GL_VERSION_OVERRIDE=4.5COMPAT` (checkboxes in the app).
- proot on the phone (seccomp; `PROOT_NO_SECCOMP` checkbox) and its speed loading 3.4 GB of archives.
- RAM: BAR wants 12 GB; measure on device.
- Touch: "simulated touchscreen" gives left clicks; right-click/drag for an RTS needs testing and probably a Lua or
  gesture layer.

## Phone requirements
Qualcomm Adreno 7xx/8xx (Snapdragon 8 Gen 2/3/8s Gen 3/8 Elite), 12 GB RAM, ~6 GB free, Android 10+.
Mali/Xclipse/Tensor: no Mesa path → the app's device check says so.

## Next steps (in order)
1. Phone: `Install on Phone.bat`, tap **Install / Update**, then `Phone Logs.bat`. Expect proot/rootfs/apt issues
   first. To skip the 4 GB content download, push the PC's BAR data before Install:
   `adb push "%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\pool" /sdcard/Android/data/com.underarmcape.bardroid/files/import/pool`
   (same for `packages`, `rapid`, `maps`).
2. **GL check**; read `glcheck.txt` from `Phone Logs.bat`. Goal: GL 4.x compat + S3TC.
3. **Play vs AI**; `infolog.txt` is the engine log. Expect env issues (fonts, GL context, audio).
4. Controller widgets. The earlier plan was to copy attempt-01's `controller_socket_bridge.lua` + `gui_controller_*`
   into `files/bar/LuaUI/Widgets`. **Not done on purpose**: `C:\Tools\BARGAMEPAD\docs\lessons-from-attempt-01.md`
   (restarted 2026-10-25) lists the companion bridge and the 19k-line widget under "do not repeat". Decide which widget
   set the phone should use; the app's UDP side (`BARCTRL1`) is ready either way.
5. File the ARM64 AI bug upstream (RecoilEngine issue first, then the CircuitAI patch), disclosing AI assistance per `AI_POLICY.md`.

## Licensing
Engine GPL-2.0+; BAR game code GPL-2.0; BAR art CC-BY-NC-ND 4.0 (never bundle, never re-encode; download from the
official CDN like the launcher does); termux-x11 `lorie` GPL-3.0 → this app is GPL-3.0; proot GPL-2.0; busybox
GPL-2.0; Mesa MIT; AngelScript zlib (the stub).
