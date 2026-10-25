# CLAUDE.md — BAR Droid (Beyond All Reason on Android)

Working folder on the laptop: `C:\Tools\BARANDROID\` (this project is `bar-droid-app/` inside it).
Owner: Kailil (GitHub UnderarmCape). Goal: a sideloadable APK that plays BAR. **Current target: the Android emulator
on this laptop** (Kailil, 2026-10-25); real phones much later, and Kailil cannot use adb with a phone for now.

## Architecture in one breath
Unmodified official **Recoil engine** (amd64 build for the emulator, arm64 for phones) runs inside a **Debian trixie
proot container** (Termux's proot bundled as `libproot.so`) and draws onto **Termux:X11's X server compiled into this
APK** (`:lorie` module, GPL-3), shown by `GameActivity extends com.termux.x11.MainActivity`. OpenGL: on the emulator,
Mesa `virpipe` → our virgl server (`VirglServer`, built by `tools/build-virgl.py`) → ANGLE → Vulkan → host GPU, with
llvmpipe as CPU fallback; on phones, Mesa for Android containers (Freedreno `kgsl` / Turnip+Zink). Content comes from
BAR's own CDN via `pr-downloader`. Gamepad → UDP `BARCTRL1` packets. Audio: PulseAudio pipe-sink → FIFO → `AudioTrack`.

## Key files
- `app/src/main/java/com/underarmcape/bardroid/` — `Installer` (first run), `Proot` (command builder, mirrors proot-distro),
  `XServer` (app_process launcher), `VirglServer` (GPU server), `GameService` (foreground), `GameActivity`
  (display + gamepad), `Prefs` (`EMULATOR_BUILD`, URLs per ABI, `putGpuEnv`), `ControllerBridge`, `AudioPump`.
- `app/src/main/assets/bardroid/` — `setup-container.sh` (apt/mesa/engine/content/import), `launch-bar.sh` (GPU env,
  glcheck, pulseaudio, spring), `springsettings.cfg` (preset; emulator overrides in `Installer.EMULATOR_GRAPHICS`).
- `app/src/main/jniLibs/<abi>/` — prebuilt helpers, committed: from `tools/fetch-prebuilts.py <abi>` (Termux proot +
  ANGLE, Debian busybox) and `tools/build-virgl.py <abi>` (virglrenderer + libepoxy, NDK build with our DXT fix).
- `termux-x11/` — upstream checkout (`tools/fetch-termux-x11.*`) with `patches/0*.patch`: 0001 CmdEntryPoint loads
  libXlorie.so from `TERMUX_X11_LIBXLORIE_PATH`; 0002 Windows-host CMake build. Regenerate a patch with `git diff`
  inside `termux-x11/` (LF endings; git through `toolchain\env.bat`).
- `tools/container-shell.bat` — root shell (or one command) in the device's container via `files/container.sh`;
  long-press **GL check** in the app keeps X + GPU server up without the game.

## Build / run (Windows; everything portable under `C:\Tools\BARANDROID\toolchain`)
```
..\Install Toolchain.bat --accept-licenses   # once
..\Build APK.bat                              # emulator build (x86_64);  "Build APK.bat phone" = arm64
..\Run in Emulator.bat [-no-audio|-wipe-data] # AVD bardroid-x86_64: boot, install, open
..\Get Logs.bat                               # launcher.log, infolog.txt, glcheck, pulse.log, logcat -> ..\logs
```
Ad-hoc commands: `cmd /c "call C:\Tools\BARANDROID\toolchain\env.bat && <command>"` (`%VARS%` on that line expand
before env.bat runs; use literal paths). `adb shell` quoting through PowerShell is fragile: push a script with
`adb exec-in run-as com.underarmcape.bardroid sh -c "cat > files/x.sh"` and run it.
Never install tools globally or write to AppData/the profile. The emulator writes `.emulator_console_auth_token` to
the real profile anyway; `Run in Emulator.bat` deletes it (also a stale one after a crash).
Toolchain: AGP 9.3.1, Gradle 9.8.2 wrapper, NDK 29.0.14206865, CMake 3.22.1, JDK 21. One ABI per APK.
Logcat tags: BarDroid/app svc install x11 engine rootfs virgl proc, plus LorieNative, CmdEntryPoint.

## Rules of the road
- Never bundle or re-encode BAR game content (CC-BY-NC-ND). Download from `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` only.
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
- Compare frame rates with the developer fps widget (HANDOFF.md) and the laptop awake: Modern Standby throttles ~2.5x.

## Open risks (see HANDOFF.md)
Emulator: ~20 fps (laptop awake), limited by virgl/ANGLE host round trips; memory tight (12 GB guest, little host RAM
left; the low-memory killer once took the app). Phones (later): Freedreno compat-profile GL version, proot on real
hardware, RAM, RTS touch input.
