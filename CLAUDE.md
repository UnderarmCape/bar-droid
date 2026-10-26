# CLAUDE.md — BAR Droid (Beyond All Reason on Android)

Working folder on the laptop: `C:\Tools\BARANDROID\` (this project is `bar-droid-app/` inside it).
Owner: Kailil (GitHub UnderarmCape). Goal: a sideloadable APK that plays BAR. **It plays on Kailil's Galaxy Z Fold7**
(~30 fps); the emulator on this laptop stays the quick test bench. Phone adb: USB (serial R3CY70B9VRH) or Wi-Fi
`adb connect 192.168.1.196:5555` (after `adb tcpip 5555`, until the phone reboots). Kailil checks fps and sound
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
  glcheck, pulseaudio, spring), `springsettings.cfg` (preset; emulator overrides in `Installer.EMULATOR_GRAPHICS`).
- `app/src/main/jniLibs/<abi>/` — prebuilt helpers, committed: from `tools/fetch-prebuilts.py <abi>` (Termux talloc,
  shmem and ANGLE, Debian busybox), `tools/build-proot.py <abi>` (proot + loader, NDK build with our ioctl filter; run
  after fetch-prebuilts, it links its talloc/shmem) and `tools/build-virgl.py <abi>` (virglrenderer + libepoxy, NDK
  build with our DXT fix).
- `RtsTouch` (finger gestures) + `assets/bardroid/bardroid_touch.lua` (camera, window size on fold/unfold, frame cap,
  "is the pointer on the interface" answers); `GameActivity` wires them up.
- `termux-x11/` — upstream checkout (`tools/fetch-termux-x11.*`) with `patches/0*.patch`: 0001 CmdEntryPoint loads
  libXlorie.so from `TERMUX_X11_LIBXLORIE_PATH`; 0002 Windows-host CMake build; 0003 the X server resizes full-screen
  top-level windows with the screen (fold/unfold; there is no window manager). Regenerate a patch with `git diff`
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
- Compare frame rates with the developer fps widget (HANDOFF.md) and the laptop awake: Modern Standby throttles ~2.5x.

## Open risks (see HANDOFF.md)
Emulator: ~20 fps at best (laptop awake), limited by virgl/ANGLE host round trips; memory tight (12 GB guest, little
host RAM left; the low-memory killer once took the app). Phone: RAM (~5–6 GB a match), BAR's UI on the near-square
inner display, drags on BAR's top bar/menus pan instead of dragging (they have no `IsAbove`), touch-only play (later).
