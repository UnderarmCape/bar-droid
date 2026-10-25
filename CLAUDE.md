# CLAUDE.md — BAR Droid (Beyond All Reason on Android)

Working folder on the laptop: `C:\Tools\BARANDROID\` (this project is `bar-droid-app/` inside it).
Owner: Kailil (GitHub UnderarmCape). Goal: a sideloadable APK that plays BAR on a Snapdragon phone.

## Architecture in one breath
Unmodified official **arm64-linux Recoil engine** (`recoil_2026.07.04_arm64-linux.7z`) runs inside a **Debian trixie
arm64 proot container** (Termux's proot bundled as `libproot.so`), draws through **Mesa for Android containers**
(Freedreno `kgsl` / Turnip+Zink) onto **Termux:X11's X server compiled into this APK** (`:lorie` module, GPL-3),
shown by `GameActivity extends com.termux.x11.MainActivity`. Content comes from BAR's own CDN via `pr-downloader`.
Gamepad → UDP `BARCTRL1` packets (UnderarmCape's controller-companion protocol). Audio: PulseAudio pipe-sink →
FIFO → `AudioTrack`.

## Key files
- `app/src/main/java/com/underarmcape/bardroid/` — `Installer` (first run), `Proot` (command builder, mirrors proot-distro),
  `XServer` (app_process launcher), `GameService` (foreground), `GameActivity` (display + gamepad), `ControllerBridge`, `AudioPump`.
- `app/src/main/assets/bardroid/` — `setup-container.sh` (apt/mesa/engine/content/import), `launch-bar.sh` (glcheck, pulseaudio, spring),
  `springsettings.cfg` (phone preset), `skirmish.template.txt`, `libasarm64.so` (ARM64 AI fix, see arm64-ai-fix-README.md).
- `termux-x11/` — upstream checkout (fetch with `tools/fetch-termux-x11.*`), with `patches/0001-*.patch` applied
  (lets CmdEntryPoint load libXlorie.so from `TERMUX_X11_LIBXLORIE_PATH`, needed because we ship libs extracted).
- `patches/circuitai-cmake-arm64-linux.patch` — upstream fix for the AI crash on arm64 Linux.

## Build / run
```
gradlew.bat :app:assembleDebug        # Windows   (first build 20–60 min: Xorg via NDK)
adb install -r app\build\outputs\apk\debug\bar-droid-debug.apk
adb logcat -s BarDroid/app BarDroid/svc BarDroid/install BarDroid/x11 BarDroid/engine BarDroid/rootfs
adb shell run-as com.underarmcape.bardroid cat files/logs/launcher.log
adb shell run-as com.underarmcape.bardroid cat files/bar/infolog.txt
```
Toolchain: AGP 9.3.1, Gradle 9.8.2 wrapper, NDK 29.0.14206865, CMake 3.22+, JDK 17+. Only arm64-v8a is built.

## Rules of the road
- Never bundle or re-encode BAR game content (CC-BY-NC-ND). Download from `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` only.
- Keep the engine binary unmodified and pinned to the version BAR's servers run (launcher config: https://launcher-config.beyondallreason.dev/config.json).
- Upstream PRs to RecoilEngine/CircuitAI must reference an accepted issue and disclose AI assistance (their `AI_POLICY.md`).
- Phone data layout: `files/rootfs` (container), `files/bar` (engine write-dir, bound at `/root/bar`), `files/logs`, `Android/data/<pkg>/files/import` (adb push content here).
- When something fails on device, first read `files/logs/launcher.log` (everything, including child process output) and `files/bar/infolog.txt`.

## Open risks (see HANDOFF.md)
app_process + CLASSPATH=base.apk on Android 14/15; Freedreno compat-profile GL version; RAM (BAR wants 12 GB); proot speed loading 3.4 GB of archives.
