# Notices

**App icon:** the project's own drawing (`app/src/main/res/drawable/ic_fg.xml`, GPL-3.0-or-later like the app); no
BAR artwork is in this repository or in an APK built from it.

Kailil's own builds replace it with his artwork (2026-10-25): the Beyond All Reason launcher icon
(`dist_cfg/build/icon.png` in https://github.com/beyond-all-reason/BYAR-Chobby, by the Beyond All Reason team,
licensed CC BY-NC-ND 4.0, https://creativecommons.org/licenses/by-nc-nd/4.0/) with an Android robot added. It is kept
outside the repository and added only when `local.properties` names its folder (`bardroid.personalRes`,
`app/build.gradle`). Because it adapts a NoDerivatives work it is for his personal, non-commercial use: an APK
carrying it must not be published or shared without the BAR team's permission. Build anything that goes out with
`-PbardroidPublic`.

**Controller game (`app/src/main/assets/gamepad/`):** Kailil's BAR Controller Support v0.8.5 (UnderarmCape, branch
`controller/codex-v085-release` of the BAR game repository): new Lua widgets and modified copies of ten of BAR's
interface widgets, GPL-2.0-or-later like BAR's own Lua code, and controller glyph atlases made for it
(GPL-2.0-or-later OR CC0-1.0, `luaui/images/controller-glyphs/LICENSE.md` inside the zip). The three BAR icons it shows
are copied from BAR's downloaded release on the phone, not shipped. Its build and order menus' widget names are "Build
menu (controller)" and "Order menu (controller)" in the package (`tools/build-gamepad-game.py`), nothing else of it
changed.

**Build menu (`app/src/main/assets/bardroid/bardroid_buildmenu.lua`):** BAR's Build menu widget
(`luaui/Widgets/gui_buildmenu.lua` of the BAR game, https://github.com/beyond-all-reason/Beyond-All-Reason, by Floris,
GPL-2.0-or-later), copied from a BAR release by `tools/make-buildmenu.py` with its changes marked "BAR Droid:" (its
size and place from the app's layout editor; the widget-handler calls a user widget makes). Code only: the unit
pictures it draws come from BAR's downloaded release on the phone.

**Order menu (`app/src/main/assets/bardroid/bardroid_ordermenu.lua`):** BAR's Order menu widget
(`luaui/Widgets/gui_ordermenu.lua` of the BAR game, by Floris, GPL-2.0-or-later), copied from a BAR release by
`tools/make-ordermenu.py` with its changes marked "BAR Droid:" (the even layout of v0.8.5's order menu while the app's
gamepad controls hide orders, an IsAbove). Code only.

**Upscaling shader (`app/src/main/assets/sgsr/`):** Snapdragon Game Super Resolution 1
(`sgsr/v1/include/glsl/sgsr1_shader_mobile.frag` in https://github.com/SnapdragonGameStudios/snapdragon-gsr),
Copyright (c) 2023-2025 Qualcomm Innovation Center, Inc., BSD-3-Clause (`LICENSE` next to it). Three small changes
for strict GLSL ES compilers, listed at the top of the file.
