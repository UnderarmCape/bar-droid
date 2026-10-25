# BAR Droid — hand-off to Claude Code (2026-10-25, ~02:30 EDT)

Beyond All Reason on Android. This package is everything produced in the research/kick-off session:
research conclusions, a phone-side manual kit, and the start of the real deliverable, an Android app
("BAR Droid") that runs the **unmodified official arm64 Recoil engine** inside a Debian container with an
**embedded X server** (Termux:X11's `lorie` library) and Mesa (Freedreno/Turnip) for desktop OpenGL.

Read this file, then `CLAUDE.md`, then `RESEARCH.md`. The plan doc with full detail lives at
https://claude.ai/artifact/XDdcJwfebpK1D138U2MjZf (also summarized in RESEARCH.md).

## What exists and in what state

| Piece | Path | State |
| --- | --- | --- |
| Research + plan (engine, BAR, prior art, architecture, risks) | `RESEARCH.md`, claude.ai doc above | Done, verified against cloned sources and live endpoints |
| Phase-1 manual kit (Termux + proot + Mesa, no app) | `../phase1-kit/` (also `bar-droid-phase1-kit.zip`) | Written, syntax-checked, **never run on a phone** |
| ARM64 AI bug fix (BARb/CircuitAI missing AngelScript stub) | `../phase1-kit/phase1/arm64-ai-fix/`, `app/src/main/assets/bardroid/libasarm64.so` | **Verified** under qemu-aarch64: engine dies without it, both BARb AIs init with it |
| Engine-on-ARM proof | `../logs/emulated-run1.log`, `emulated-run2.log` | arm64 `spring-headless` + BAR + map + 2 AIs reach "Player ... is now ingame" under qemu (no GPU) |
| Android app project | this folder (`bar-droid-app/`) | Source complete for v0.1 (launcher, installer, proot, X server, engine launch, gamepad UDP bridge, audio pump). **Builds**: `../apk/bar-droid-0.1.0-debug.apk` (23.9 MB) was produced in the cloud with AGP 9.3.1 / NDK 29 — libXlorie.so (X server) compiled, proot/busybox bundled, manifest merged. **Never run on a device yet.** |
| Bundled binaries | `app/src/main/jniLibs/arm64-v8a/` | Termux `proot` 5.1.107.101 (+loader, libtalloc, libandroid-shmem, patchelf'd), Debian static busybox 1.37 — all real, from official repos |
| X server library | `termux-x11/` | Not in this zip (66 MB). Fetch with `tools/fetch-termux-x11.sh` or `.ps1` (pins commit `7e5f5c5c92`, applies `patches/0001-cmdentrypoint-explicit-libpath.patch`) |

## How the app works (one paragraph)

`LauncherActivity` → `GameService` (foreground). **Install**: `Installer` symlinks `proot`/`busybox` from the
app's native-lib dir (the only place Android lets an app exec from), downloads the official Debian trixie arm64
docker rootfs (layer digest read from the OCI manifest on GitHub), extracts it with `proot --link2symlink` +
busybox tar (hard links → symlinks), runs `/opt/bardroid/setup-container.sh apt` (SDL2/X11/OpenAL/fonts/xkb/Mesa
pkgs/PulseAudio), installs **Mesa for Android containers** over Debian's Mesa, downloads
`recoil_2026.07.04_arm64-linux.7z`, then `pr-downloader` fetches `byar:test`, `byar-chobby:test` and one map
from BAR's own CDN (nothing of BAR's CC-BY-NC-ND art is bundled). **Play**: `XServer` starts
`com.termux.x11.CmdEntryPoint` (compiled into *our* APK) via `/system/bin/app_process` with
`TMPDIR=<rootfs>/tmp` so the socket is the container's `/tmp/.X11-unix/X0`; `GameActivity` (extends Termux:X11's
`MainActivity`) shows the display and handles touch/mouse/keyboard; `launch-bar.sh` runs inside proot: waits for
the socket, starts PulseAudio with `module-pipe-sink` → FIFO → `AudioPump` → `AudioTrack`, runs a one-time
`glxinfo` probe, then `spring --isolation --write-dir /root/bar skirmish.txt` (or `--menu rapid://byar-chobby:test`).
Gamepad events are intercepted in `GameActivity` and sent as `BARCTRL1|...` UDP packets to 127.0.0.1:28777 —
the protocol of UnderarmCape's BAR Controller Companion, so the existing controller widgets work unchanged.

## Build

Toolchain pinned by termux-x11: **AGP 9.3.1, Gradle 9.8.2 (wrapper), NDK 29.0.14206865, CMake ≥ 3.22, JDK 17+.**
Only `arm64-v8a` is built (root `build.gradle` forces it; cuts the Xorg compile 4x).

Windows (laptop):
1. Install Android Studio or cmdline-tools; `sdkmanager "platforms;android-34" "build-tools;34.0.0" "ndk;29.0.14206865" "cmake;3.22.1" "platform-tools"`.
2. `tools\fetch-termux-x11.ps1` (git clone + submodules + patch).
3. `local.properties`: `sdk.dir=C\:\\Users\\<you>\\AppData\\Local\\Android\\Sdk`
4. `gradlew.bat :app:assembleDebug` → `app\build\outputs\apk\debug\bar-droid-debug.apk`.
   Expect 20–60 min the first time (the X server, pixman, libX11... compile with the NDK).
5. `adb install -r app\build\outputs\apk\debug\bar-droid-debug.apk`.

Linux/WSL: same with `tools/fetch-termux-x11.sh` and `./gradlew`.

Known unknowns at hand-off (nothing below was reached before the session ended):
- (`:lorie` as a dependency of our app module, the manifest merge and the native X-server compile all work: build log in `../logs/cloud-build-6-success.log`.)
- Whether `app_process` accepts `CLASSPATH=<our base.apk>` on Android 14/15 (Termux:X11 moved to a tiny loader APK on SDK ≥ 34; if it fails, port their `shell-loader` approach: a dex-only loader).
- Whether Freedreno (`MESA_LOADER_DRIVER_OVERRIDE=kgsl`) gives a *compatibility* profile ≥ 3.0 with GL4 extensions on the test phone; fallback `zink`, then `MESA_GL_VERSION_OVERRIDE=4.5COMPAT` (checkboxes in the app).
- RAM: BAR wants 12 GB; measure on device.

## Phone requirements
Qualcomm Adreno 7xx/8xx (Snapdragon 8 Gen 2/3/8s Gen 3/8 Elite), 12 GB RAM, ~6 GB free, Android 10+.
Mali/Xclipse/Tensor: no Mesa path → the app's device check says so.

## Suggested next steps for Claude Code (in order)
1. Finish the first build; fix manifest-merge or Java compile errors (there will be a few — nothing was compiled yet).
2. `adb install`, tap **Install / Update**, watch the log; fix proot/rootfs issues (`PROOT_NO_SECCOMP` checkbox if proot hangs).
3. Tap **GL check**; read `files/bar/logs/glcheck-kgsl.txt`. Goal: GL 4.x compat + S3TC.
4. **Play vs AI**. First boot will surface engine env issues (fonts, GL context, audio). `files/bar/infolog.txt` is the engine log.
5. Content import from the PC to skip the 4 GB download: `adb push <BAR data>\pool /sdcard/Android/data/com.underarmcape.bardroid/files/import/pool` (same for `packages`, `rapid`, `maps`), then Install again.
6. Copy the controller widgets from `underarmcape-bar-controller-support-attempt-01` branch `fix/console-update-prompt-v085`
   (`luaui/Widgets/gui_controller_*.lua`, `controller_socket_bridge.lua`, `luaui/Include/controller_*.lua`) into `files/bar/LuaUI/Widgets`.
7. File the ARM64 AI bug upstream (RecoilEngine issue → CircuitAI PR with `patches/circuitai-cmake-arm64-linux.patch`), disclosing AI assistance per their `AI_POLICY.md`.

## Licensing
Engine GPL-2.0+; BAR game code GPL-2.0; BAR art CC-BY-NC-ND 4.0 (never bundle, never re-encode; download from the official CDN like the launcher does);
termux-x11 `lorie` GPL-3.0 → this app is GPL-3.0; proot GPL-2.0; busybox GPL-2.0; Mesa MIT; AngelScript zlib (the stub).
