# BAR Droid: Beyond All Reason on Android

An Android app that runs the unmodified [Recoil](https://github.com/beyond-all-reason/RecoilEngine) engine and Beyond
All Reason on a phone: BAR's own lobby, online and singleplayer games, spectating, at about 30 fps on a Snapdragon 8
Elite phone (Galaxy Z Fold7), with touch controls and gamepad support. Nothing of BAR is in the APK: the app downloads
the engine and BAR's content from BAR's own servers at install time, as BAR's PC launcher does.

How it works, in one breath: the official arm64 Linux engine runs inside a Debian container (proot, no root needed)
and draws through Mesa's Freedreno driver onto an X server compiled into the app (Termux:X11's `lorie` module);
small Lua widgets and an LD_PRELOAD library adapt BAR to a phone (touch camera, interface scale per screen, catching
up with running games, frame pacing). Details: [HANDOFF.md](HANDOFF.md) (state, measurements, decisions) and
[CLAUDE.md](CLAUDE.md) (architecture, files, rules).

## Phone requirements

Qualcomm Adreno 7xx/8xx (Snapdragon 8 Gen 2, 8 Gen 3, 8s Gen 3, 8 Elite), 12 GB RAM, about 6 GB free, Android 10 or
newer. Mali, Xclipse and Tensor GPUs have no Mesa driver path: the app's device check says so.

## Build (Windows 10/11 x64)

Everything goes into one folder: no global installs, nothing in the registry, AppData or the user profile.

1. `Install Toolchain.bat --accept-licenses` (one time; downloads a portable JDK 21, Git, the Android SDK/NDK and
   small host tools, about 6 GB; `--accept-licenses` accepts the
   [Android SDK terms](https://developer.android.com/studio/terms)). It also fetches Termux:X11 at the pinned commit
   and applies `patches/`.
2. `Build APK.bat phone` builds the phone app (arm64) into `apk\bar-droid-phone-debug.apk`; `Build APK.bat` alone
   builds the x86_64 app for the Android emulator.
3. `Install on Phone.bat` installs it on the phone connected over adb (USB debugging, or `Pair Phone.bat` for
   wireless debugging), then in the app: **Install / Update** (about 4 GB from BAR's servers), then the lobby or
   **Play vs AI**.

The toolchain folder is `toolchain\` inside the checkout, a `toolchain` folder beside it if one is installed there,
or wherever `BARDROID_TOOLCHAIN` points (`scripts\env.bat`). Logs from the phone: `Get Logs.bat phone`, or
**Share logs** in the app. `Run in Emulator.bat` runs the x86_64 build in an emulator (slow; a test bench only).

## Checks

`powershell -ExecutionPolicy Bypass -File tools\laptop-tests.ps1` runs every check that needs no phone (about
5 minutes): the downloader, settings merge and updater rollback in Java, the lobby bridge and the lobby touch
widget in BAR's real lobby, and the in-game widgets in a real skirmish. The game checks use BAR's Windows install
(`%LOCALAPPDATA%\Programs\Beyond-All-Reason`, read only, never changed). Other tools are listed in CLAUDE.md
("Build / run").

## Layout

- `app/` the Android app: `src/main/java/com/underarmcape/bardroid/` (installer, container, X server, game service,
  touch, gamepad, audio, updater), `src/main/assets/bardroid/` (container setup and launch scripts, the Lua widgets,
  the preload library), `src/main/jniLibs/` (prebuilt proot, busybox and friends; rebuilt by `tools/`).
- `patches/` the changes to Termux:X11 (fetched into `termux-x11/` by `tools/fetch-termux-x11.ps1`).
- `tools/` build scripts for the native helpers, the laptop checks and profiling tools.
- `docs/` what the app changes in BAR's settings at every start (`UPDATES.md`) and drafts for upstream reports.

## Licences

The app's own code and widgets: GPL-3.0-or-later (it embeds Termux:X11's GPL-3 `lorie` module). Third-party parts and
the one BAR-derived picture (the app icon, personal use only) are listed in [NOTICE.md](NOTICE.md). BAR's game content
(CC BY-NC-ND) is never bundled or re-encoded: it is downloaded from `repos-cdn.beyondallreason.dev` /
`files-cdn.beyondallreason.dev` on the device.
