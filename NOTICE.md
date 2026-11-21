# Notices

**App icon:** the project's own drawing (`app/src/main/res/drawable/ic_fg.xml`, GPL-3.0-or-later like the app). The
only BAR artwork in this repository or in an APK built from it is the next two items'.

**BAR's load screen pictures upright** (`app/src/main/assets/bardroid/loadpicture-upright_*.jpg`, made by
`tools/make-loadpictures.ps1`): Beyond All Reason's own load screen pictures (`bitmaps/loadpictures/` in the game, by
the Beyond All Reason team), each laid whole across a 9:20 picture with an enlarged, blurred and darkened copy of itself
above and below, so that an upright phone shows all of it. Made on the laptop and shipped with the same clearance as
below; the originals' terms are BAR's.

**The lobby's first picture upright** (`app/src/main/assets/bardroid/loadscreen-upright.png`): made from Beyond All
Reason's lobby picture (`luamenu/configs/gameconfig/byar/defaultsettings/menuloadscreens/loadscreen.png` in
https://github.com/beyond-all-reason/BYAR-Chobby, by the Beyond All Reason team): its BAR logo scaled down on the
picture's own grey, so that an upright phone shows the whole word. Made on the laptop and shipped with BAR's
developers' clearance (2026-11-06: content made from BAR's art for phones may ship with the app); the original's terms
are BAR's.

Kailil's own builds replace it with his artwork (2026-10-25): the Beyond All Reason launcher icon
(`dist_cfg/build/icon.png` in https://github.com/beyond-all-reason/BYAR-Chobby, by the Beyond All Reason team,
licensed CC BY-NC-ND 4.0, https://creativecommons.org/licenses/by-nc-nd/4.0/) with an Android robot added. It is kept
outside the repository and added only when `local.properties` names its folder (`bardroid.personalRes`,
`app/build.gradle`). Because it adapts a NoDerivatives work it is for his personal, non-commercial use: an APK
carrying it must not be published or shared without the BAR team's permission. Build anything that goes out with
`-PbardroidPublic`.

**The phone engine** (`assets/phone-engine/<version>/spring` in an arm64 APK, put there by
`tools/phone-engine-release.ps1` from outside the repository; docs/ENGINE-DEFAULT.md): the Recoil engine
(https://github.com/beyond-all-reason/RecoilEngine, GPL-2.0-or-later, by the Spring and Recoil developers) at the
version BAR's servers run, with the BAR Droid engine branch's changes (`bardroid/sim`: the app's widgets as the game's,
BAR's Lua in phone versions, memory and drawing settings for phones, the exact simulation rewrite). `BUILD.txt` beside
it names the branch's commit. GPL-2.0 asks whoever passes the binary on to offer its complete source: the branch goes
public as a fork of RecoilEngine together with the app (Kailil's push, 2026-11-13), and no APK carrying it goes out
before that (`tools/publish-check.ps1 -Apk` fails until a line "Phone engine source: https://..." here names it). Without `bardroid.phoneEngine` in `local.properties` an APK has no phone engine and plays BAR's official
one.

**The display server (`lib/<abi>/libXlorie.so` and its Java part, `com.termux.x11`):** Termux:X11
(https://github.com/termux/termux-x11, 1.03.01, GPL-3.0), the `termux-x11/` checkout with the app's changes in
`patches/0*.patch`. It carries the X.Org server and libraries built into the same library: xserver, libX11, libXau,
libXdmcp, xtrans, libxkbfile, libXfont, libfontenc, libxcvt, libxshmfence, xkbcomp, xorgproto (X.Org's MIT/X11-style
licences, each in its folder under `termux-x11/lorie/src/main/cpp/`), pixman (MIT), libepoxy (MIT), libtirpc
(BSD-3-Clause) and bzip2 (its own BSD-style licence).

**The container's helpers (`lib/<abi>/`):** PRoot (`libproot.so`, `libproot-loader.so`; https://github.com/termux/proot
at commit b27d81a6, GPL-2.0-or-later) built by `tools/build-proot.py` with the app's ioctl filter; talloc
(`libtalloc.so`, from Samba via Termux's package 2.5.0; LGPL-3.0-or-later upstream, Termux lists GPL-3.0) and
libandroid-shmem (`libandroid-shmem.so`, https://github.com/termux/libandroid-shmem 0.7, BSD-3-Clause), both from
Termux's packages (`tools/fetch-prebuilts.py`); BusyBox (`libbusybox.so`, Debian's busybox-static, GPL-2.0-only,
https://busybox.net/). The emulator build also carries virglrenderer (MIT) and libepoxy (MIT), built by
`tools/build-virgl.py` with Termux's patches, and ANGLE (BSD-3-Clause) from Termux's packages.

**AngelScript's ARM64 call stub (`app/src/main/assets/bardroid/libasarm64.so`):** the hand-written AArch64 calling
code of the AngelScript library (https://www.angelcode.com/angelscript/, zlib licence), which the official arm64 build
of BAR's AI lacks; preloaded for it in the container (docs/arm64-ai-fix.md).

**AndroidX and Kotlin's standard library** (the app's and Termux:X11's Java dependencies): Apache-2.0.

**Downloaded on the phone, not shipped:** Debian's packages for the container (each its own licence, as Debian lists),
Mesa for Android containers (MIT), BAR's engine, game, lobby and maps from BAR's own servers (their own terms), and
pr-downloader (GPL-2.0, with BAR's engine).

(Kailil's BAR Controller Support v0.8.5, the singleplayer controller game, is no longer in the app since 2026-11-06,
and its last checks left it on 2026-11-21.)

**Build menu (`app/src/main/assets/bardroid/bardroid_buildmenu.lua`):** BAR's Build menu widget
(`luaui/Widgets/gui_buildmenu.lua` of the BAR game, https://github.com/beyond-all-reason/Beyond-All-Reason, by Floris,
GPL-2.0-or-later), copied from a BAR release by `tools/make-buildmenu.py` with its changes marked "BAR Droid:" (its
size and place from the app's layout editor; the widget-handler calls a user widget makes). Code only: the unit
pictures it draws come from BAR's downloaded release on the phone.

**Order menu (`app/src/main/assets/bardroid/bardroid_ordermenu.lua`):** BAR's Order menu widget
(`luaui/Widgets/gui_ordermenu.lua` of the BAR game, by Floris, GPL-2.0-or-later), copied from a BAR release by
`tools/make-ordermenu.py` with its changes marked "BAR Droid:" (the even layout of v0.8.5's order menu while the app's
gamepad controls hide orders, an IsAbove). Code only.

**Mission Info, TeamStats and Options (`bardroid_missioninfo.lua`, `bardroid_teamstats.lua`, `bardroid_options.lua` in
`app/src/main/assets/bardroid/`):** BAR's own widgets of those names (`luaui/Widgets/gui_mission_info.lua`,
`gui_teamstats.lua`, `gui_options.lua` of the BAR game, GPL-2.0-or-later, by their authors named in each file's
GetInfo), copied the same way by `tools/make-missioninfo.py`, `make-teamstats.py` and `make-options.py`, the changes
marked "BAR Droid:". Code only.

**Phone versions of BAR's Lua (`app/src/main/assets/bardroid/phone-*.lua.patch`):** changes to BAR's own widget and
gadget files (GPL-2.0-or-later, the BAR game), each a set of find-and-replace blocks the phone engine applies to BAR's
file as it loads; the patched lines come from BAR's code. Upstream versions of several are in `docs/upstream/`.

**Upscaling shader (`app/src/main/assets/sgsr/`):** Snapdragon Game Super Resolution 1
(`sgsr/v1/include/glsl/sgsr1_shader_mobile.frag` in https://github.com/SnapdragonGameStudios/snapdragon-gsr),
Copyright (c) 2023-2025 Qualcomm Innovation Center, Inc., BSD-3-Clause (`LICENSE` next to it). Three small changes
for strict GLSL ES compilers, listed at the top of the file.
