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
- `termux-x11/` — upstream checkout (fetch with `tools/fetch-termux-x11.*`), with `patches/0*.patch` applied:
  0001 lets CmdEntryPoint load libXlorie.so from `TERMUX_X11_LIBXLORIE_PATH` (we ship libs extracted);
  0002 makes the X server's CMake build work on a Windows host (inert on Linux). Edit termux-x11, then regenerate the
  patch with `git diff` from inside `termux-x11/` (LF endings; run git through `toolchain\env.bat`).
- `patches/circuitai-cmake-arm64-linux.patch` — upstream fix for the AI crash on arm64 Linux.
- `tools/emulator-test.bat`, `tools/build-emulator-x11.bat` — x86_64 emulator smoke test (Android side only).

## Build / run (Windows; everything portable under `C:\Tools\BARANDROID\toolchain`)
```
..\Install Toolchain.bat --accept-licenses   # once: JDK, MinGit, SDK/NDK/CMake, host Python/bison/gcc, termux-x11 fetch
..\Build APK.bat                              # gradlew :app:assembleDebug with toolchain\env.bat
..\Install on Phone.bat                       # adb install -r + start
..\Phone Logs.bat                             # pulls launcher.log, infolog.txt, glcheck, pulse.log, logcat into ..\logs
```
For ad-hoc commands: `cmd /c "call C:\Tools\BARANDROID\toolchain\env.bat && <command>"` (note: `%VARS%` in the same
line expand before env.bat runs; use literal paths). Never install tools globally or write to AppData/the profile
(the emulator writes `.emulator_console_auth_token` to the real profile; `emulator-test.bat` deletes it on exit).
Toolchain: AGP 9.3.1, Gradle 9.8.2 wrapper, NDK 29.0.14206865, CMake 3.22.1, JDK 21. Only arm64-v8a is built.
Logcat tags: BarDroid/app svc install x11 engine rootfs, plus LorieNative, CmdEntryPoint.

## Rules of the road
- Never bundle or re-encode BAR game content (CC-BY-NC-ND). Download from `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` only.
- Keep the engine binary unmodified and pinned to the version BAR's servers run (launcher config: https://launcher-config.beyondallreason.dev/config.json).
- Upstream PRs to RecoilEngine/CircuitAI must reference an accepted issue and disclose AI assistance (their `AI_POLICY.md`).
- Phone data layout: `files/rootfs` (container), `files/bar` (engine write-dir, bound at `/root/bar`), `files/logs`, `Android/data/<pkg>/files/import` (adb push content here).
- When something fails on device, first read `files/logs/launcher.log` (everything, including child process output) and `files/bar/infolog.txt`.

- Never keep exec'able paths into `nativeLibraryDir` on disk (symlinks, saved paths): it moves on every app update.
- Child processes go through `Proc` so Stop can kill them; `XServer` must inherit the app environment (app_process needs it).

## Open risks (see HANDOFF.md)
Freedreno compat-profile GL version; proot on the phone; RAM (BAR wants 12 GB); proot speed loading 3.4 GB of archives;
RTS touch input. (app_process + CLASSPATH=base.apk on Android 14: works, verified on the emulator.)
