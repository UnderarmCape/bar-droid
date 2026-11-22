#!/bin/sh
# launch-bar.sh's switching of BAR's build and order menus in LuaUI/Config/BYAR.lua (the widget list both games share), on
# the laptop or in CI: its widget_order, build_menu and order_menu functions and its menus block, taken from
# launch-bar.sh as they are, run against a scratch BAR write dir (build/launch-bar-test). Cases: the app's copies of BAR's
# Build and Order menus in, kept when BAR's file is not the one they were made from (an Android-layer miss), BAR's own only
# after a copy failed in a game, an old install's controller-game entries dropped, and a second start changing nothing. And its low-memory mode: an 8 GB phone's settings,
# a 12 GB phone's left alone. And the CPU mask its all-CPU loop reads, and the after-game check of the app's widgets.
# Prints "[launchbartest] PASS|FAIL <case>"; exit 1 on a failure.
#   sh tools/launch-bar-test.sh          (tools\laptop-tests.ps1 runs it with the portable Git's sh)
here=$(cd "$(dirname "$0")/.." && pwd)
src="$here/app/src/main/assets/bardroid/launch-bar.sh"
copy="$here/app/src/main/assets/bardroid/bardroid_buildmenu.lua"
ocopy="$here/app/src/main/assets/bardroid/bardroid_ordermenu.lua"
mcopy="$here/app/src/main/assets/bardroid/bardroid_missioninfo.lua"
tcopy="$here/app/src/main/assets/bardroid/bardroid_teamstats.lua"
work="$here/build/launch-bar-test"
fails=0

body() { awk -v f="^$1\\\\(\\\\) \\\\{" '$0 ~ f { on = 1 } on { print } on && /^}/ { exit }' "$src"; }
fn=$(body widget_order)
faults=$(body read_faults)
removed=$(body copy_removed)
# (copy_failed, mission_info and team_stats came later, 11-10 and 11-11: build_menu and the menus block call
# them, and this test, which took the first four only, failed five cases on "command not found" until 2026-11-18)
failedfn=$(body copy_failed)
menu=$(body build_menu)
omenu=$(body order_menu)
minfo=$(body mission_info)
tstats=$(body team_stats)
block=$(awk '/^  widget_order "Grid menu" 0$/ { on = 1 } on { print } on && /^  fi$/ { exit }' "$src")
for part in "$fn" "$faults" "$removed" "$failedfn" "$menu" "$omenu" "$minfo" "$tstats" "$block"; do
  [ -n "$part" ] || { echo "[launchbartest] FAIL launch-bar.sh: widget_order, read_faults, copy_removed, copy_failed, build_menu, order_menu, mission_info, team_stats or the menus block not found"; exit 1; }
done

BAR="$work/bar"; LOGS="$work/logs"
log() { :; }
layer_miss() { echo "$*" >> "$LOGS/android-layer.txt"; }
eval "$fn"
eval "$faults"
eval "$removed"
eval "$failedfn"
eval "$menu"
eval "$omenu"
eval "$minfo"
eval "$tstats"
start() {   # one launch-bar.sh start: start <build menu md5 Installer found in BAR's release> [<order menu's>]
  printf '%s\n' "$1" > "$BAR/.bardroid-buildmenu"
  printf '%s\n' "${2-$omade}" > "$BAR/.bardroid-ordermenu"
  printf '%s\n' "$mmade" > "$BAR/.bardroid-missioninfo"   # (Mission Info's and TeamStats' copies as made: quiet)
  printf '%s\n' "$tmade" > "$BAR/.bardroid-teamstats"
  : > "$LOGS/android-layer.txt"
  read_faults   # (launch-bar.sh reads the last run's infolog once, before the copies)
  eval "$block"
}
infolog() {   # infolog <body>...: the last run's infolog, each line after the engine's log prefix
  : > "$BAR/infolog.txt"
  for b in "$@"; do printf '[t=00:01:02.345678][f=0001234] %s\n' "$b" >> "$BAR/infolog.txt"; done
}
check() {   # check <case> <condition...>
  name=$1; shift
  if "$@"; then echo "[launchbartest] PASS $name"; else echo "[launchbartest] FAIL $name"; fails=$((fails + 1)); fi
}
order() {   # order <widget name> <value>: its order entry is there once, with that value (not its data: "= {")
  [ "$(grep -c "\[\"$1\"\] = $2,$" "$BAR/LuaUI/Config/BYAR.lua")" = 1 ] &&
    [ "$(grep -c "\[\"$1\"\] = -\?[0-9][0-9]*,$" "$BAR/LuaUI/Config/BYAR.lua")" = 1 ]
}
absent() { ! grep -q "\[\"$1\"\] = -\?[0-9][0-9]*,$" "$BAR/LuaUI/Config/BYAR.lua"; }
missed() { grep -q "build menu" "$LOGS/android-layer.txt"; }
omissed() { grep -q "order menu" "$LOGS/android-layer.txt"; }
quiet() { [ ! -s "$LOGS/android-layer.txt" ]; }

rm -rf "$work"
mkdir -p "$BAR/LuaUI/Config" "$BAR/LuaUI/Widgets" "$LOGS"
cp "$copy" "$ocopy" "$mcopy" "$tcopy" "$BAR/LuaUI/Widgets/"
made=$(sed -n 's/^-- BARDROID_BUILDMENU_FROM //p' "$copy")
omade=$(sed -n 's/^-- BARDROID_ORDERMENU_FROM //p' "$ocopy")
mmade=$(sed -n 's/^-- BARDROID_MISSIONINFO_FROM //p' "$mcopy")
tmade=$(sed -n 's/^-- BARDROID_TEAMSTATS_FROM //p' "$tcopy")
check "the copy says which BAR file it was made from" [ -n "$made" ]
check "the order menu copy too" [ -n "$omade" ]
# as BAR writes it: an order table one tab in, a widget's own "order = {" inside its data, the Build menu from before
printf -- '-- Widget Custom data and order, order = 0 disabled widget\nreturn {\n\tdata = {\n\t\t["Build menu"] = {\n\t\t\torder = {\n\t\t\t},\n\t\t},\n\t},\n\torder = {\n\t\t["Build menu"] = 165,\n\t\tEcostats = 0,\n\t\t["Grid menu"] = 0,\n\t},\n}\n' \
  > "$BAR/LuaUI/Config/BYAR.lua"

start "$made"
check "same BAR file: BAR's Build menu off" order "Build menu" 0
check "same BAR file: the app's copy on" order "BAR Droid build menu" 165
check "same BAR file: no controller build menu entry (the controller game is gone)" absent "Build menu (controller)"
check "same BAR file: the Grid menu off" order "Grid menu" 0
check "same BAR file: no Android-layer miss" quiet
check "the widgets' own data untouched" grep -q '^		\["Build menu"\] = {$' "$BAR/LuaUI/Config/BYAR.lua"
check "same BAR file: BAR's Order menu off" order "Order menu" 0
check "same BAR file: the app's order menu copy on" order "BAR Droid order menu" 189
check "same BAR file: no controller order menu entry" absent "Order menu (controller)"

start "$made"
check "a second start: each entry once" order "BAR Droid build menu" 165

start "0123456789abcdef0123456789abcdef"
check "BAR changed its file and no new copy: the old copy runs (the pad's RB is in it)" order "BAR Droid build menu" 165
check "BAR changed its file and no new copy: BAR's Build menu off" order "Build menu" 0
check "BAR changed its file and no new copy: an Android-layer miss" missed

start ""
check "BAR's file not found: the copy runs" order "BAR Droid build menu" 165

# (BAR's handler's words in other lines: another player's chat, a spectator's, the host's, a map ping's label, and a
# replay's line in a chat; none is BAR's own: 2026-11-21)
for said in "<Player> Removed widget: BAR Droid build menu" "[Spec] Removed widget: BAR Droid build menu" \
    "[Spec (replay)] Removed widget: BAR Droid build menu" "> Removed widget: BAR Droid build menu" \
    "Player added point: Removed widget: BAR Droid build menu" "<Player> Failed to load: bardroid_buildmenu.lua  (x)"; do
  infolog "$said"
  start "fedcba9876543210fedcba9876543210"
  check "\"$said\" said: the copy runs" order "BAR Droid build menu" 165
  check "\"$said\" said: no mark" [ ! -f "$BAR/.bardroid-buildmenu-failed" ]
done
infolog "Error in Shutdown()" 'Error in Shutdown(): [string "LuaUI/Widgets/bardroid_buildmenu.lua"]:9: attempt to index nil' \
  "Removed widget: BAR Droid build menu"
start "fedcba9876543210fedcba9876543210"
check "an error in the copy's Shutdown alone (it ran the whole game): the copy runs" order "BAR Droid build menu" 165
infolog "Removed widget: BAR Droid build menus" "Removed widget: Build menu"
start "fedcba9876543210fedcba9876543210"
check "another widget removed (a longer name, BAR's own): the copy runs" order "BAR Droid build menu" 165
infolog "Failed to load: bardroid_missioninfo.lua  (no GetInfo() call)" "Failed to load: bardroid_buildmenu.lua  (duplicate name)"
start "$made"
check "no GetInfo() call (no scenario) and a duplicate name: Mission Info's copy on" order "BAR Droid mission info" 190
check "... and the build menu's" order "BAR Droid build menu" 165
check "... no Android-layer miss" quiet
infolog '<Player> [PreGame::ReadDataFromDemo] pre-scanning demo file' "Removed widget: BAR Droid build menu"
start "$made"   # (the same files as the run that failed: a fault counts against them only, 2026-11-21)
check "a replay's line said as chat, the copy removed: BAR's own (no replay)" order "Build menu" 165
rm -f "$BAR/.bardroid-buildmenu-failed"
infolog 'Failed to load: bardroid_buildmenu.lua  ([string "LuaUI/Widgets/bardroid_buildmenu.lua"]:12: unexpected symbol near ")")'
start "fedcba9876543210fedcba9876543210"
check "the copy failed to load in the last game (it never ran): BAR's own" order "Build menu" 165
check "the copy failed to load: the copy off" order "BAR Droid build menu" 0
rm -f "$BAR/.bardroid-buildmenu-failed"
infolog "Removed widget: BAR Droid build menu"
start "fedcba9876543210fedcba9876543210"
check "the copy failed in the last game: BAR's own" order "Build menu" 165
check "the copy failed in the last game: the copy off" order "BAR Droid build menu" 0
check "the copy failed in the last game: an Android-layer miss" missed
rm -f "$BAR/infolog.txt"
start "fedcba9876543210fedcba9876543210"
check "the copy failed on this BAR file: still BAR's own" order "BAR Droid build menu" 0
start "$made"
check "another BAR file: the copy runs again" order "BAR Droid build menu" 165
rm -f "$BAR/.bardroid-buildmenu-failed"
infolog "[PreGame::ReadDataFromDemo] pre-scanning demo file" "Removed widget: BAR Droid build menu"
start "fedcba9876543210fedcba9876543210"
check "the copy removed in a replay (it plays its own BAR release): the copy still runs" order "BAR Droid build menu" 165
rm -f "$BAR/infolog.txt"
printf '%s\n' "fedcba9876543210fedcba9876543210" > "$BAR/.bardroid-buildmenu-failed"
start "fedcba9876543210fedcba9876543210"
check "a mark from before \"game\" (a replay may have written it): the copy runs" order "BAR Droid build menu" 165
rm -f "$BAR/.bardroid-buildmenu-failed"
# (the lobby fetched a newer BAR release mid-session and the old copy failed in it; Installer made the copy again at
# this start: that fault is not the new copy's, release overhaul audit 2026-11-21)
start "$made"
cp "$BAR/LuaUI/Widgets/bardroid_buildmenu.lua" "$work/buildmenu-kept.lua"
printf -- '-- made again\n' >> "$BAR/LuaUI/Widgets/bardroid_buildmenu.lua"
infolog "Removed widget: BAR Droid build menu"
start "fedcba9876543210fedcba9876543210"
check "the old copy failed on a newer BAR file, the copy made again since: the new copy runs" order "BAR Droid build menu" 165
check "... and is not marked" [ ! -f "$BAR/.bardroid-buildmenu-failed" ]
infolog "Removed widget: BAR Droid build menu"
start "fedcba9876543210fedcba9876543210"
check "... the new copy failed too (the files that ran): BAR's own" order "Build menu" 165
cp "$work/buildmenu-kept.lua" "$BAR/LuaUI/Widgets/bardroid_buildmenu.lua"
rm -f "$BAR/.bardroid-buildmenu-failed" "$BAR/.bardroid-buildmenu-failed.ran" "$BAR/infolog.txt"

start "$made" "0123456789abcdef0123456789abcdef"
check "BAR changed its Order menu and no new copy: the old copy runs" order "BAR Droid order menu" 189
check "BAR changed its Order menu and no new copy: BAR's off" order "Order menu" 0
check "BAR changed its Order menu and no new copy: an Android-layer miss" omissed
infolog "Removed widget: BAR Droid order menu"
start "$made" "0123456789abcdef0123456789abcdef"   # (the files that ran)
check "the order menu copy failed in the last game: BAR's own" order "Order menu" 189
check "the order menu copy failed in the last game: the copy off" order "BAR Droid order menu" 0
check "the order menu copy failed: the build menu copy keeps running" order "BAR Droid build menu" 165
rm -f "$BAR/infolog.txt"
start "$made"
check "another BAR Order menu file: the copy runs again" order "BAR Droid order menu" 189
rm -f "$BAR/.bardroid-ordermenu-failed"
infolog "[PreGame::ReadDataFromDemo] pre-scanning demo file" "Removed widget: BAR Droid order menu"
start "$made" "fedcba9876543210fedcba9876543210"
check "the order menu copy removed in a replay: the copy still runs" order "BAR Droid order menu" 189
rm -f "$BAR/infolog.txt"

# (an install from the controller game's days: its menus' entries and its mark; dropped at the next start)
widget_order "Build menu (controller)" 165; widget_order "Order menu (controller)" 189; : > "$BAR/.bardroid-gamepad-menus"
start "$made"
check "controller game off: the copy still in BAR's place (the pad online)" order "BAR Droid build menu" 165
check "controller game off: the order menu copy still in BAR's place" order "BAR Droid order menu" 189
check "controller game off: no controller order menu entry" absent "Order menu (controller)"
check "controller game off: BAR's Build menu off" order "Build menu" 0
check "controller game off: the Grid menu off" order "Grid menu" 0
check "controller game off: no controller build menu entry" absent "Build menu (controller)"
check "controller game off: the marker gone" [ ! -f "$BAR/.bardroid-gamepad-menus" ]
check "the other widgets untouched" grep -q '^		Ecostats = 0,$' "$BAR/LuaUI/Config/BYAR.lua"

# A game quit in first person: BAR's Camera Remember would open every later game in that camera
forget=$(awk '/^forget_fps_camera\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$src")
check "launch-bar.sh: forget_fps_camera found" [ -n "$forget" ]
eval "$forget"
remembered() {   # remembered <mode>: BYAR.lua with a saved camera of that mode, and another widget's own "mode" beside it
  printf -- 'return {\n\tdata = {\n\t\tBefore = {\n\t\t\tmode = 0,\n\t\t},\n\t\t["Camera Remember"] = {\n\t\t\tfov = 80,\n\t\t\tmode = %s,\n\t\t\tpx = 6144,\n\t\t},\n\t\tCameraShake = {\n\t\t\tmode = 0,\n\t\t},\n\t},\n\torder = {\n\t\t["Camera Remember"] = 106,\n\t},\n}\n' "$1" \
    > "$BAR/LuaUI/Config/BYAR.lua"
}
saved() { grep -q '\["Camera Remember"\] = {' "$BAR/LuaUI/Config/BYAR.lua"; }
remembered 2; forget_fps_camera
check "the Spring camera stays remembered" saved
remembered 0; forget_fps_camera
check "a first-person camera forgotten" sh -c "! grep -q '\[\"Camera Remember\"\] = {' '$BAR/LuaUI/Config/BYAR.lua'"
check "... its place in the widget order kept" order "Camera Remember" 106
check "... the other widgets' data untouched" [ "$(grep -c 'mode = 0,' "$BAR/LuaUI/Config/BYAR.lua")" = 2 ]
check "... and the file still ends as it did" grep -q '^		CameraShake = {$' "$BAR/LuaUI/Config/BYAR.lua"
rm -f "$BAR/LuaUI/Config/BYAR.lua"; forget_fps_camera
check "no widget settings yet: nothing to do" [ ! -f "$BAR/LuaUI/Config/BYAR.lua" ]

# The low-memory mode (phones under 9.5 GB): its block as it is, /proc/meminfo swapped for a scratch one
low=$(awk '/^mem_kb=\$\(sed / { on = 1 } on { print } on && /^fi$/ { exit }' "$src" | sed "s#/proc/meminfo#$work/meminfo#")
check "launch-bar.sh: the low-memory block found" [ -n "$low" ]
phone() {   # phone <MemTotal kB> [again]: one start's settings on a scratch springsettings.cfg and lobby copy (again: on the last start's)
  printf 'MemTotal:        %s kB\nMemFree:          100000 kB\n' "$1" > "$work/meminfo"
  if [ "${2:-}" != again ]; then
    printf 'CompressTextures = 0\nXResolution = 1200\n' > "$BAR/springsettings.cfg"
    mkdir -p "$BAR/LuaMenu/Config"; printf 'return {\n  game_settings = {\n    cus2 = 1,\n    UseLuaMemPools = 1,\n  },\n}\n' > "$BAR/LuaMenu/Config/IGL_data.lua"
  fi
  unset BARDROID_FBO_UNCOMPRESS
  eval "$low"
}
setting() { [ "$(grep -c "^$1 = $2$" "$BAR/springsettings.cfg")" = 1 ] && [ "$(grep -c "^$1 *=" "$BAR/springsettings.cfg")" = 1 ]; }
phone 7242340
check "8 GB: Lua memory pools off" setting UseLuaMemPools 0
check "8 GB: compressed textures (set over the 0)" setting CompressTextures 1
check "8 GB: BAR's GL4 unit shaders off" setting cus2 0
check "8 GB: the other settings untouched" setting XResolution 1200
check "8 GB: the lobby's copy too" grep -q '^    cus2 = 0,$' "$BAR/LuaMenu/Config/IGL_data.lua"
check "8 GB: framebuffer textures uncompressed" [ "${BARDROID_FBO_UNCOMPRESS:-}" = 1 ]
phone 7242340 again
check "8 GB, a second start: each setting once" setting UseLuaMemPools 0
phone 11392000
check "12 GB: settings untouched" [ "$(cat "$BAR/springsettings.cfg")" = "$(printf 'CompressTextures = 0\nXResolution = 1200')" ]
check "12 GB: framebuffer textures left alone" [ -z "${BARDROID_FBO_UNCOMPRESS:-}" ]

# The engine's threads on every CPU (widen_engine): the mask read from a status file, as for every thread every 3 s
cpus=$(awk '/^cpus_allowed\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$src")
[ -n "$cpus" ] || { echo "[launchbartest] FAIL launch-bar.sh: cpus_allowed not found"; exit 1; }
eval "$cpus"
printf 'Name:\tspring\nCpus_allowed_list:\t0-4,6\nCpus_allowed:\t5f\nMems_allowed:\t1\n' > "$work/status"
cpus_allowed "$work/status"
check "CPU mask: a thread's Cpus_allowed (not its _list)" [ "$mask" = 5f ]
cpus_allowed "$work/no-such-status"
check "CPU mask: none for a thread that has exited" [ -z "$mask" ]

# The after-game check of the app's widgets (app_widget_faults, one pass over read_faults' lines): BAR's handler's
# lines count, one entry a widget; the dev profiler's timer lines (which name every widget, "W:VisibleUnitRemoved:BAR
# Droid touch": three false launcher warnings, 2026-11-05) and chat with the handler's words do not (2026-11-21)
wfaults=$(body app_widget_faults)
[ -n "$wfaults" ] || { echo "[launchbartest] FAIL launch-bar.sh: app_widget_faults not found"; exit 1; }
eval "$wfaults"
infolog '[simdraw] timers: W:VisibleUnitRemoved:BAR Droid touch 0.1%, W:Update:BAR Droid chat 0.2%' \
  'Error in DrawScreen(): [string "LuaUI/Widgets/bardroid_chat.lua"]:12: attempt to index nil' \
  'Removed widget: BAR Droid chat' \
  'Error in Update(): [string "LuaUI/Widgets/gui_buildmenu.lua"]:40: attempt to call a nil value' \
  'Removed widget: BAR Droid pad' \
  'Error in Initialize(): [string "luaui/widgets/gui_pip.lua"]:9: attempt to call field' 'Removed widget: Picture-in-Picture Minimap' \
  '<Player> Error in DrawScreen(): [string "LuaUI/Widgets/bardroid_touch.lua"]:1: said' \
  '[Spec] Removed widget: BAR Droid walls' \
  'Failed to load: bardroid_missioninfo.lua  (no GetInfo() call)' \
  'Failed to load: bardroid_retreat.lua  ([string "LuaUI/Widgets/bardroid_retreat.lua"]:3: unexpected symbol)' \
  'Error in Shutdown()' 'Error in Shutdown(): [string "LuaUI/Widgets/bardroid_queue.lua"]:45: attempt to call field' \
  'Removed widget: BAR Droid builder queue' \
  'Error in DrawScreen(): [string "LuaUI/Widgets/bardroid_chat.lua"]:13: again' \
  'Error in Update(): [string "LuaMenu/Widgets/bardroid_lobby_touch.lua"]:7: attempt to index nil'
read_faults
found=$(app_widget_faults)
has() { printf '%s\n' "$found" | grep -qxF -e "$1"; }
check "widget check: a widget's error, by its file" has 'bardroid_chat.lua|Error in DrawScreen(): [string "LuaUI/Widgets/bardroid_chat.lua"]:12: attempt to index nil'
check "widget check: an error in BAR's code a widget called, by its name" has 'BAR Droid pad|Removed widget: BAR Droid pad'
check "widget check: a load failure" has 'bardroid_retreat.lua|Failed to load: bardroid_retreat.lua  ([string "LuaUI/Widgets/bardroid_retreat.lua"]:3: unexpected symbol)'
check "widget check: an error in Shutdown, by its file" has 'bardroid_queue.lua|Error in Shutdown(): [string "LuaUI/Widgets/bardroid_queue.lua"]:45: attempt to call field'
check "widget check: the lobby's widget" has 'bardroid_lobby_touch.lua|Error in Update(): [string "LuaMenu/Widgets/bardroid_lobby_touch.lua"]:7: attempt to index nil'
check "widget check: five widgets, each once (no profiler line, chat, BAR's own widget, Removed after its error line, no GetInfo)" \
  [ "$(printf '%s\n' "$found" | grep -c .)" = 5 ]
infolog '[simdraw] timers: W:VisibleUnitRemoved:BAR Droid touch 0.1%'
read_faults
check "widget check: a profiler line alone is no fault" [ -z "$(app_widget_faults | grep .)" ]

# Adreno's compressed render targets off for Freedreno (the stripes, 2026-11-05): added once to what is there, never
# for Turnip + Zink
ubwc=$(awk '/^if \[ "\$GPU" = kgsl \]; then$/ { on = 1 } on { print } on && /^fi$/ { exit }' "$src")
[ -n "$ubwc" ] || { echo "[launchbartest] FAIL launch-bar.sh: the UBWC block not found"; exit 1; }
ubwc_for() { ( GPU=$1; if [ -n "$2" ]; then FD_MESA_DEBUG=$2; else unset FD_MESA_DEBUG; fi; eval "$ubwc"; echo "${FD_MESA_DEBUG:-}" ); }
check "UBWC: off for Freedreno" [ "$(ubwc_for kgsl '')" = noubwc ]
check "UBWC: added to other Freedreno flags" [ "$(ubwc_for kgsl nolrz)" = nolrz,noubwc ]
check "UBWC: not twice" [ "$(ubwc_for kgsl noubwc,nolrz)" = noubwc,nolrz ]
check "UBWC: Turnip + Zink untouched" [ -z "$(ubwc_for zink '')" ]

# The developer hooks only in a developer's (debuggable) build, BARDROID_DEV=1: in a release build a dev-env.sh in the
# write folder, which BAR's Lua can write, is not run, and dev-springsettings.cfg is not added (2026-11-21)
dev=$(awk '/^# Developer overrides, never created by the app/ { on = 1 } /^# The app.s Settings: BAR.s Options/ { exit } on { print }' "$src")
[ -n "$dev" ] || { echo "[launchbartest] FAIL launch-bar.sh: the developer overrides block not found"; exit 1; }
dev_start() {   # dev_start <BARDROID_DEV>: the block against a write folder holding both developer files
  rm -rf "$work/dev"; mkdir -p "$work/dev"
  ( BAR="$work/dev"; DEV_KEYS="$BAR/.dev-springsettings-keys"; DEV_ORIG="$BAR/.dev-springsettings-orig"
    ENGINE=official; PHONE_ENGINE=phone; BARDROID_DEV=$1
    printf 'touch "%s/ran"\n' "$BAR" > "$BAR/dev-env.sh"
    printf 'LogFlushLevel = 0\n' > "$BAR/dev-springsettings.cfg"
    printf 'XResolution = 1\n' > "$BAR/springsettings.cfg"
    eval "$dev" )
}
dev_start 0
check "a release build: dev-env.sh not run" [ ! -f "$work/dev/ran" ]
check "a release build: dev-springsettings.cfg not added" [ -z "$(grep LogFlushLevel "$work/dev/springsettings.cfg")" ]
dev_start 1
check "a developer's build: dev-env.sh run" [ -f "$work/dev/ran" ]
check "a developer's build: dev-springsettings.cfg added" [ -n "$(grep LogFlushLevel "$work/dev/springsettings.cfg")" ]

# The game widgets' folder (bardroid-ui) holds the app's widgets only: anything else in it loaded as one of the game's
# widgets with the phone engine (release overhaul item 4, 2026-11-21)
apps=$(awk '/^APP_WIDGETS="/ { on = 1 } on { print } on && /"$/ { exit }' "$src")
gw=$(grep '^GAME_WIDGETS=' "$src")
to=$(body app_widgets_to)
only=$(body game_widgets_only)
[ -n "$apps" ] && [ -n "$gw" ] && [ -n "$to" ] && [ -n "$only" ] ||
  { echo "[launchbartest] FAIL launch-bar.sh: APP_WIDGETS, GAME_WIDGETS, app_widgets_to or game_widgets_only not found"; exit 1; }
eval "$apps"; eval "$gw"; eval "$to"; eval "$only"
log() { printf '%s\n' "$*" >> "$LOGS/launch.txt"; }
rm -rf "$BAR/bardroid-ui" "$BAR/LuaUI/Widgets"
mkdir -p "$GAME_WIDGETS/sub" "$BAR/LuaUI/Widgets" "$BAR/bardroid-ui/LuaUI/Config"
echo new > "$BAR/LuaUI/Widgets/bardroid_touch.lua"; echo old > "$GAME_WIDGETS/bardroid_touch.lua"
echo app > "$GAME_WIDGETS/bardroid_chat.lua"
for f in "$GAME_WIDGETS/bardroid_cheat.lua" "$GAME_WIDGETS/sub/gui_x.lua" "$GAME_WIDGETS/bardroid_touch_hud.lua" \
    "$BAR/bardroid-ui/LuaUI/Config/y.txt"; do echo x > "$f"; done
: > "$LOGS/launch.txt"
app_widgets_to "$GAME_WIDGETS" "$BAR/LuaUI/Widgets"; game_widgets_only
check "bardroid-ui: a widget not the app's gone" [ ! -e "$GAME_WIDGETS/bardroid_cheat.lua" ]
check "... one the app retired (the touch-only mode's) gone" [ ! -e "$GAME_WIDGETS/bardroid_touch_hud.lua" ]
check "... one in a subfolder gone" [ ! -e "$GAME_WIDGETS/sub/gui_x.lua" ]
check "... any other file gone" [ ! -e "$BAR/bardroid-ui/LuaUI/Config/y.txt" ]
check "... the app's own back in LuaUI/Widgets, the newer kept" [ "$(cat "$BAR/LuaUI/Widgets/bardroid_touch.lua")" = new ]
check "... and one only there" [ "$(cat "$BAR/LuaUI/Widgets/bardroid_chat.lua" 2>/dev/null)" = app ]
check "... said in launcher.log" grep -q "bardroid-ui: removed what is not the app's widgets .*, 4 in all: " "$LOGS/launch.txt"
mkdir -p "$GAME_WIDGETS"; echo stuck > "$GAME_WIDGETS/bardroid_walls.lua"
: > "$LOGS/launch.txt"; game_widgets_only
check "an app widget left in the folder (its move back failed): kept" [ -f "$GAME_WIDGETS/bardroid_walls.lua" ]
check "nothing foreign: nothing said" [ ! -s "$LOGS/launch.txt" ]
rm -rf "$BAR/bardroid-ui"; game_widgets_only
check "no bardroid-ui (BAR's official engine): nothing made" [ ! -e "$BAR/bardroid-ui" ]
log() { :; }
# The app's widgets are listed twice: launch-bar.sh's APP_WIDGETS and the Installer's copy list
inst=$(sed -n '/new String\[\]{"bardroid_touch.lua"/,/})/p' "$here/app/src/main/java/com/underarmcape/bardroid/Installer.java" |
  grep -o 'bardroid_[a-z_]*\.lua' | sed 's/\.lua$//' | sort | tr '\n' ' ')
mine=$(for w in $APP_WIDGETS; do echo "$w"; done | sort | tr '\n' ' ')
all_1() { [ -n "$inst" ] && [ "$inst" = "$mine" ]; }; check "the app's widgets: launch-bar.sh's list is the Installer's ($(echo $mine | wc -w))" all_1

# The write folder trusted less (release overhaul item 9, 2026-11-21): the lobby's widgets in a release build only the
# app's own; .bardroid-loadpictures-ours' lines never outside bitmaps/loadpictures; the benchmark's profile file only in a
# developer's build; the engine preloaded with the app's libraries on its own command line, not exported
lw=$(body lobby_widgets_only)
[ -n "$lw" ] || { echo "[launchbartest] FAIL launch-bar.sh: lobby_widgets_only not found"; exit 1; }
eval "$lw"
log() { printf '%s\n' "$*" >> "$LOGS/launch.txt"; }
lobby_start() {   # lobby_start <BARDROID_DEV>
  rm -rf "$BAR/LuaMenu"; mkdir -p "$BAR/LuaMenu/Widgets/sub" "$BAR/LuaMenu/Config"
  echo app > "$BAR/LuaMenu/Widgets/bardroid_lobby_touch.lua"; echo x > "$BAR/LuaMenu/Widgets/evil.lua"
  echo x > "$BAR/LuaMenu/Widgets/sub/more.lua"; echo cfg > "$BAR/LuaMenu/Config/IGL_data.lua"
  : > "$LOGS/launch.txt"
  ( BARDROID_DEV=$1; lobby_widgets_only )
}
lobby_start 0
check "a release build's lobby: a widget not the app's gone" [ ! -e "$BAR/LuaMenu/Widgets/evil.lua" ]
check "... one in a subfolder too" [ ! -e "$BAR/LuaMenu/Widgets/sub/more.lua" ]
check "... the app's own lobby widget kept" [ "$(cat "$BAR/LuaMenu/Widgets/bardroid_lobby_touch.lua")" = app ]
check "... the lobby's settings untouched" [ "$(cat "$BAR/LuaMenu/Config/IGL_data.lua")" = cfg ]
check "... said in launcher.log" grep -q "LuaMenu/Widgets: removed what is not the app's lobby widget, 2 in all" "$LOGS/launch.txt"
lobby_start 1
all_2() { [ -f "$BAR/LuaMenu/Widgets/evil.lua" ] && [ -f "$BAR/LuaMenu/Widgets/sub/more.lua" ]; }; check "a developer's build: the tools' test widgets kept" all_2
# The lobby's saved settings made when there are none yet (a fresh install's first lobby: no lobby widget before,
# release overhaul audit 2026-11-21), in the layout the settings blocks after it match; a player's own left alone
seed=$(body lobby_settings_seed)
[ -n "$seed" ] || { echo "[launchbartest] FAIL launch-bar.sh: lobby_settings_seed not found"; exit 1; }
eval "$seed"
rm -rf "$BAR/LuaMenu"; : > "$LOGS/launch.txt"
lobby_settings_seed "$BAR/LuaMenu/Config/IGL_data.lua"
igl="$BAR/LuaMenu/Config/IGL_data.lua"
tab=$(printf '\t')
check "no lobby settings yet: made, loadLocalWidgets on" grep -q "^$tab${tab}loadLocalWidgets = true,$" "$igl"
check "... in Chobby's layout (the scale block's pattern)" grep -q "^$tab\[\"Chili lobby\"\] = {\$" "$igl"
all_3() { grep -q 'drawAtFullSpeed = false' "$igl" && grep -q 'doNotDisturb = false' "$igl" && grep -q 'enableCacheRapidPool = true' "$igl"; }; check "... the once-only fields there for their blocks" all_3
all_4() { [ ! -e "$igl.tmp" ] && grep -q "lobby: its settings file made" "$LOGS/launch.txt"; }; check "... no temp file left, said in launcher.log" all_4
sed -i "0,/\[\"Chili lobby\"\] *= *{/s//&\n\t\tgameConfigName = \"byar\",/" "$igl"
check "... launch-bar.sh's gameConfigName insert finds its place" grep -q 'gameConfigName = "byar",' "$igl"
echo 'return { ["Chili lobby"] = { panel_layout = 2, }, }' > "$igl"; : > "$LOGS/launch.txt"
lobby_settings_seed "$igl"
all_5() { [ "$(cat "$igl")" = 'return { ["Chili lobby"] = { panel_layout = 2, }, }' ] && [ ! -s "$LOGS/launch.txt" ]; }; check "a player's lobby settings: left alone" all_5
: > "$igl"
lobby_settings_seed "$igl"
check "an empty one (cut off): made again" grep -q 'loadLocalWidgets = true' "$igl"
log() { :; }
lp=$(awk '/^  while read -r rel; do$/ { on = 1 } on { print } on && /^  done < "\$LP_OURS"$/ { exit }' "$src")
[ -n "$lp" ] || { echo "[launchbartest] FAIL launch-bar.sh: the load pictures' removal loop not found"; exit 1; }
mkdir -p "$BAR/bitmaps/loadpictures/manual" "$BAR/demos"
echo p > "$BAR/bitmaps/loadpictures/manual/x.jpg"; echo keep > "$BAR/demos/game.sdfz"; echo keep > "$work/outside.txt"
LP_OURS="$work/lp-ours"
printf '%s\n' "manual/x.jpg" "../../demos/game.sdfz" "/$work/outside.txt" "" > "$LP_OURS"
eval "$lp"
check "load pictures: ours removed" [ ! -e "$BAR/bitmaps/loadpictures/manual/x.jpg" ]
check "load pictures: a line with .. removes nothing outside" [ -f "$BAR/demos/game.sdfz" ]
check "load pictures: a line from the root removes nothing" [ -f "$work/outside.txt" ]
pf=$(grep -A1 '^prof=""$' "$src")
[ -n "$pf" ] || { echo "[launchbartest] FAIL launch-bar.sh: the benchmark profile's lines not found"; exit 1; }
echo widgets > "$BAR/.bardroid-bench-profile"
check "a release build: the benchmark's profile file ignored" [ -z "$(BARDROID_DEV=0; eval "$pf"; echo "$prof")" ]
check "a developer's build: honoured" [ "$(BARDROID_DEV=1; eval "$pf"; echo "$prof")" = widgets ]
all_6() { [ -z "$(grep -n 'export LD_PRELOAD' "$src")" ] &&
  [ "$(grep -c 'LD_PRELOAD="${LD_PRELOAD:-$PRELOAD}" ./spring --isolation' "$src")" = 4 ] &&
  [ "$(grep -c '^ *\./spring ' "$src")" = 0 ]; }; check "the preload on the engine's lines alone, not exported" all_6

# BYAR.lua without its top-level order table (BAR's widget list reset, then a killed session): widget_order adds one
# instead of missing every order; one with no "return {" at all set aside and made anew (release overhaul audit,
# 2026-11-21)
byar="$BAR/LuaUI/Config/BYAR.lua"; mkdir -p "$BAR/LuaUI/Config"
printf -- '-- Widget Custom data and order\nreturn {\n\tallowUserWidgets = true,\n}\n' > "$byar"; : > "$LOGS/android-layer.txt"
widget_order "Grid menu" 0; widget_order "Build menu" 165
all_7() { grep -q '\["Grid menu"\] = 0,' "$byar" && grep -q '\["Build menu"\] = 165,' "$byar"; }; check "BYAR.lua with no order table: the orders set" all_7
all_8() { grep -q 'allowUserWidgets = true,' "$byar" && [ ! -s "$LOGS/android-layer.txt" ]; }; check "... the player's other settings kept, nothing missed" all_8
printf -- 'return { [cut' > "$byar"; : > "$LOGS/android-layer.txt"
widget_order "Grid menu" 0
all_9() { grep -q '\["Grid menu"\] = 0,' "$byar" &&
  [ "$(cat "$byar.bardroid-unread")" = 'return { [cut' ] && grep -q "unreadable, made anew" "$LOGS/android-layer.txt"; }; check "BYAR.lua cut short: made anew, the order set, the old one kept" all_9
rm -f "$byar" "$byar.bardroid-unread"

# setup-container.sh's content step (a fresh install's download) with its map's download failing (a mistyped name, a
# map BAR removed): the install goes on, the skirmish start fetches the map; the game's failing still fails it
# (release overhaul audit, 2026-11-21). A copy on a scratch BAR folder, pr-downloader a stub.
sc="$work/sc"; rm -rf "$sc"; mkdir -p "$sc/bar/engine/recoil_9.9/maps" "$sc/bar/maps"
sed "s#^BAR=/root/bar\$#BAR=$sc/bar#" "$here/app/src/main/assets/bardroid/setup-container.sh" > "$sc/setup.sh"
printf '#!/bin/sh\ncase "$*" in *--download-map*) exit 1 ;; *--download-game*nogame*) exit 2 ;; esac\nexit 0\n' \
  > "$sc/bar/engine/recoil_9.9/pr-downloader"
chmod +x "$sc/bar/engine/recoil_9.9/pr-downloader"
out=$(sh "$sc/setup.sh" content byar:test byar-chobby:test "No Such Map 1.0" 9.9 2>&1); rc=$?
all_10() { [ "$rc" = 0 ] && echo "$out" | grep -q "map download failed (continuing"; }; check "content: the map's download failing, the install goes on" all_10
out=$(sh "$sc/setup.sh" content nogame byar-chobby:test "No Such Map 1.0" 9.9 2>&1); rc=$?
check "content: the game's failing still stops it" [ "$rc" = 42 ]

echo "[launchbartest] done: $([ "$fails" = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ "$fails" = 0 ]
