# Research summary — BAR on Android (2026-10-25)

Condensed from the plan doc (https://claude.ai/artifact/XDdcJwfebpK1D138U2MjZf). Everything here was checked
against the cloned RecoilEngine (master `b988c72`, 23 Oct 2026) and Beyond-All-Reason repos, the user's forks,
the extracted `recoil_2026.07.04_arm64-linux.7z`, the live launcher config, and the web pages listed at the end.

## Bottom line
- The CPU side is done upstream: Recoil merged ARM64 in March 2026 (#2819 deterministic NEON floats via streflop,
  #2885 `arm64-linux` CI, #2886 streflop submodule). Release 2026.06 says "ARM64 architecture builds now have nominal
  support"; every release since ships `recoil_<ver>_arm64-linux.7z` (33 MB; 108 MB unpacked). BAR's CDN publisher
  only forwards the amd64 archives, so the launcher never installs the ARM build.
- The blocker is OpenGL: the engine opens a desktop GL **compatibility** context (3.0 minimum; `GLContextMajorVersion`),
  still has 800+ fixed-function call sites (`glPushMatrix` 113, `glMatrixMode` 179, `glVertex*` 255, display lists...),
  and BAR gates its renderer on GL 4.3 features (30 `*_gl4` widgets, 59 of 70 shaders are `#version 420/430`, SSBOs).
  Android only has GLES. The only working desktop-GL stack on Android in 2026 is Mesa (Freedreno/Turnip + Zink) on
  Qualcomm Adreno inside a Linux container: "Mesa for Android containers" (github.com/lfdevs/mesa-for-android-container,
  Mesa 26.x, Adreno 6xx/7xx/8xx tested, PRoot/chroot/LXC).
- Textures: 972 unit DDS files, 925 DXT5 / 25 DXT3 / 11 DXT1 (BAR-wide: 2,550 DDS, 1.5 GB). The engine's only
  transcode fallback is for map tiles (DXT1 → ETC2 in `SMFGroundTextures.cpp`); unit textures need S3TC. Adreno
  exposes S3TC via Mesa; Mali/Xclipse/Tensor do not → Snapdragon only.
- Verified tonight under qemu-aarch64 (x86 host, no GPU): official arm64 `spring-headless` + BAR git checkout +
  "Supreme Isthmus v2.1" loads map (4.8 s), defs (2.4 s), pathfinder (41 s), LuaRules/Gaia/UI, 2× BARb, reaches
  "Player ... is now ingame" at 4.3 GB RSS. One real bug: `libSkirmishAI.so` (BARb and CircuitAI) has undefined
  `CallARM64*` → `symbol lookup error: undefined symbol: CallARM64RetInMemory` at AI load. Cause:
  `AI/Skirmish/BARb/CMakeLists.txt` only assembles AngelScript's `as_callfunc_arm64_xcode.S` for APPLE; Linux arm64
  never gets `as_callfunc_arm64_gcc.S`. Fix: preload the assembled stub (`libasarm64.so`, shipped) or the 6-line
  CMake patch (`patches/circuitai-cmake-arm64-linux.patch`). Worth filing upstream immediately — it kills every AI
  skirmish on the official ARM build.

## Engine facts that matter (from source)
- C++23, CMake ≥ 3.27, Lua 5.1 (patched, no JIT → no W^X issues). Only x86-64 and ARM64 accepted; 64-bit only.
- Targets: `engine-legacy` (`spring`: SDL2, GL, X11/Xcursor, Fontconfig, Freetype, OpenAL, RmlUi), `engine-headless`
  (GL/SDL stubbed — first native-NDK milestone), `engine-dedicated`, `unitsync`, `pr-downloader`.
- arm64 release binary `spring` NEEDED: libSDL2-2.0.so.0, libX11.so.6, libXcursor.so.1, libopenal.so.1, glibc ≥ 2.27
  (libstdc++ static). Built on Ubuntu 18.04 + gcc-13 with `spring-static-libs` branch `18.04-arm`.
- Desktop-only code is small (phase-3 native port surface): X11 in 3 files, Fontconfig 2, backtrace() 3, GLX 4 (stubbed
  when absent), 57 files with platform ifdefs. SDL usage is ordinary. The expensive part of a native build is rebuilding
  the static deps + Mesa EGL/Zink for bionic, not the engine code.
- `haveGL4` = ARB_multi_draw_indirect + UBO + SSBO + GLSL 4.3 probe; `ForceDisableGL4=1` falls back to GL3 drawers
  (BAR becomes "potato" mode). `MESA_GL_VERSION_OVERRIDE` is read by the engine and raises its minimum context.
- Input: engine inits only SDL video+audio (no joystick, no touch). Release 2026.07 added
  `debug.emulateKeyPress/MousePress/MouseMove/MouseWheel` Lua hooks → a touch layer can synthesize mouse input from Lua.
- Sync: cross-arch streflop tests (NEON vs SSE) pass in CI; online play from ARM is plausible but unproven ("nominal").
- Maintainers (contributing.md): lead ivand/lhog, vice-lead Tarnished Knight/lostsquirrel1, p2004a (infra), sprunk
  (gamedev API), badosu (UX/input), loveridge + ChrisFloofyKitsune (RmlUi). AI_POLICY.md: disclose AI use, PRs need an
  accepted issue, human-tested.

## BAR facts that matter
- Live launcher config (launcher-config.beyondallreason.dev/config.json, 25 Oct 2026): stable engine `recoil_2026.07.04`,
  test `recoil_2026.09.01`; games via rapid `byar:test` + `byar-chobby:test`; `PRD_RAPID_REPO_MASTER=https://repos-cdn.beyondallreason.dev/repos.gz`,
  `PRD_HTTP_SEARCH_URL=https://files-cdn.beyondallreason.dev/find`, pool seed `https://pool-init.beyondallreason.dev/data.7z` (2.23 GB);
  launch `spring --menu rapid://byar-chobby:test`.
- Lobby-less start: `spring --isolation --write-dir <dir> script.txt` (BAR's `tools/headless_testing/startscript*.txt`).
  `GameType` may be a rapid tag or the display name (`Beyond All Reason test-31723-95ab750` on 25 Oct).
- Size: `byar:test` = 18,621 files / 3.39 GB uncompressed (unittextures 820 MB, unitpics 632, music 540, luaui 455,
  sounds 454, objects3d 215); lobby 423 MB; 227 maps of 25–343 MB (median 78). Engine 113 MB. Budget 4–6 GB.
- Official minimum: quad-core 2.7 GHz, GTX 960, **12 GB RAM**, Win10/Linux (Ubuntu 18.04-era libs). macOS unsupported
  ("OpenGL 4.3" + a dep without ARM support). Steam via Hooded Horse announced 16 Jun 2026 (team keeps IP).
- Licensing: engine GPL-2.0+, game code GPL-2.0, art CC-BY-NC-ND 4.0 with an explicit no-repackaging clause → never
  bundle or re-encode content; download at runtime from the official CDN like the launcher.
- No public Android/mobile discussion found anywhere (issues, discussions, Reddit, Discord summaries, GamingOnLinux).
  Closest: Beyond-All-Reason#2258 "ARM64 Support" (Asahi M1 user). Steam Deck works (x86).

## Prior art / platform facts
- Mesa Zink: OpenGL 4.6 **compatibility** contexts since Mesa 21.3 (Phoronix, Aug 2021). Freedreno gallium: GL 4.5 core
  on a6xx+ (features.txt); compat-profile level on Adreno to be measured on device (`glxinfo -B`).
- Mesa for Android containers: `MESA_LOADER_DRIVER_OVERRIDE=kgsl` (Freedreno) or `zink`; tarballs per distro
  (`..._debian_trixie_arm64.tar.gz`, extract over `/` + `ldconfig`); glmark2 2211 on Adreno 830 in PRoot, 3574 on 840.
- Turnip: a6xx mature, a7xx fixed through Mesa 24–26, a8xx (8 Elite) since mid-2026 (Turnip v26.1+ / A8xx builds).
- Termux:X11: `--shared-tmp` proot login; the X server is `com.termux.x11.CmdEntryPoint` run through `app_process`;
  `lorie` is an Android *library* module designed to be hosted by another app (host applicationId becomes
  BuildConfig.APPLICATION_ID) → embedded in BAR Droid. Needs `TMPDIR` (socket at `$TMPDIR/.X11-unix/X0`) and
  `XKB_CONFIG_ROOT`; fonts from `<dirname TMPDIR>/usr/share/fonts/X11`. GPL-3.
- proot-distro (Termux): `--kill-on-exit --link2symlink --sysvipc -L --kernel-release=... --root-id --bind=/dev,/proc,/sys,
  /dev/urandom:/dev/random, /proc/self/fd..., fake /proc/{stat,version,loadavg,uptime,vmstat}, /dev/shm`. Termux's proot
  needs `PROOT_LOADER`, `PROOT_TMP_DIR`, libtalloc + libandroid-shmem.
- Android 16 Linux Terminal (AVF Debian VM): GPU via Gfxstream only on Pixel 10, partial Vulkan, no Adreno Mesa path → not viable yet.
- Hardware pick if buying: AYN Odin 2 (Snapdragon 8 Gen 2 / Adreno 740, up to 16 GB, fan, built-in gamepad).

## User's prior work (UnderarmCape)
- `controllersupport-RecoilEngine-attempt-01`: `Spring.GetAvailableControllers/GetControllerState` via SDL (473 lines), May–Jun 2026.
- `underarmcape-bar-controller-support-attempt-01`: BAR Controller Companion v0.4.x–v0.8.5 (Jul 2026): Windows
  `BARControllerBridge.exe` → UDP `BARCTRL1|seq|connected|lx|ly|rx|ry|lt|rt|<21 buttons in SDL order>` to 127.0.0.1:28777,
  consumed by `luaui/Widgets/controller_socket_bridge.lua` + radial/camera widgets. BAR Droid speaks this protocol.
- The earlier Android attempt itself is not on GitHub.

## Sources (opened)
RecoilEngine and Beyond-All-Reason repos; launcher-config.beyondallreason.dev/config.json; beyondallreason.info/download;
beyondallreason.info/news/beyond-all-reason-and-hooded-horse; gamingonlinux.com (ARM64 article, 16 Jul 2026);
github.com/lfdevs/mesa-for-android-container (+ release notes 26.2.0-devel-20260610); docs.mesa3d.org (zink, envvars);
phoronix.com/news/Zink-Compatibility-Ctx; Mesa features.txt; LinuxDroidMaster/Termux-Desktops HardwareAcceleration.md;
termux-x11 README + source; termux/proot-distro source; pocket-gaming.org Turnip guide (15 Jun 2026);
androidauthority.com (Turnip 8 Elite, Pixel 10 Gfxstream); liliputing.com (AYN Odin 2 specs).
