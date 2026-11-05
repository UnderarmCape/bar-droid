#!/bin/sh
# launch-bar.sh's switching of BAR's build and order menus in LuaUI/Config/BYAR.lua (the widget list both games share), on
# the laptop or in CI: its widget_order, build_menu and order_menu functions and its controller-game block, taken from
# launch-bar.sh as they are, run against a scratch BAR write dir (build/launch-bar-test). Cases: the app's copies of BAR's
# Build and Order menus in, kept when BAR's file is not the one they were made from (an Android-layer miss), BAR's own only
# after a copy failed in a game, the controller game switched off, and a second start changing nothing. And its low-memory mode: an 8 GB phone's settings,
# a 12 GB phone's left alone. And the CPU mask its all-CPU loop reads, and the after-game check of the app's widgets.
# Prints "[launchbartest] PASS|FAIL <case>"; exit 1 on a failure.
#   sh tools/launch-bar-test.sh          (tools\laptop-tests.ps1 runs it with the portable Git's sh)
here=$(cd "$(dirname "$0")/.." && pwd)
src="$here/app/src/main/assets/bardroid/launch-bar.sh"
copy="$here/app/src/main/assets/bardroid/bardroid_buildmenu.lua"
ocopy="$here/app/src/main/assets/bardroid/bardroid_ordermenu.lua"
work="$here/build/launch-bar-test"
fails=0

fn=$(awk '/^widget_order\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$src")
removed=$(awk '/^copy_removed\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$src")
menu=$(awk '/^build_menu\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$src")
omenu=$(awk '/^order_menu\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$src")
block=$(awk '/^  widget_order "Grid menu" 0$/ { on = 1 } on { print } on && /^  fi$/ { exit }' "$src")
[ -n "$fn" ] && [ -n "$removed" ] && [ -n "$menu" ] && [ -n "$omenu" ] && [ -n "$block" ] || { echo "[launchbartest] FAIL launch-bar.sh: widget_order, copy_removed, build_menu, order_menu or the controller-game block not found"; exit 1; }

BAR="$work/bar"; LOGS="$work/logs"
log() { :; }
layer_miss() { echo "$*" >> "$LOGS/android-layer.txt"; }
eval "$fn"
eval "$removed"
eval "$menu"
eval "$omenu"
start() {   # one launch-bar.sh start: start <GAMEPAD_GAME> <build menu md5 Installer found in BAR's release> [<order menu's>]
  GAMEPAD_GAME=$1
  printf '%s\n' "$2" > "$BAR/.bardroid-buildmenu"
  printf '%s\n' "${3-$omade}" > "$BAR/.bardroid-ordermenu"
  : > "$LOGS/android-layer.txt"
  eval "$block"
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
widget_error_found() { widget_error "$1" | grep -q 'attempt to index nil'; }

rm -rf "$work"
mkdir -p "$BAR/LuaUI/Config" "$BAR/LuaUI/Widgets" "$LOGS"
cp "$copy" "$ocopy" "$BAR/LuaUI/Widgets/"
made=$(sed -n 's/^-- BARDROID_BUILDMENU_FROM //p' "$copy")
omade=$(sed -n 's/^-- BARDROID_ORDERMENU_FROM //p' "$ocopy")
check "the copy says which BAR file it was made from" [ -n "$made" ]
check "the order menu copy too" [ -n "$omade" ]
# as BAR writes it: an order table one tab in, a widget's own "order = {" inside its data, the Build menu from before
printf -- '-- Widget Custom data and order, order = 0 disabled widget\nreturn {\n\tdata = {\n\t\t["Build menu"] = {\n\t\t\torder = {\n\t\t\t},\n\t\t},\n\t},\n\torder = {\n\t\t["Build menu"] = 165,\n\t\tEcostats = 0,\n\t\t["Grid menu"] = 0,\n\t},\n}\n' \
  > "$BAR/LuaUI/Config/BYAR.lua"

start 1 "$made"
check "same BAR file: BAR's Build menu off" order "Build menu" 0
check "same BAR file: the app's copy on" order "BAR Droid build menu" 165
check "same BAR file: the controller game's own on" order "Build menu (controller)" 165
check "same BAR file: the Grid menu off" order "Grid menu" 0
check "same BAR file: no Android-layer miss" quiet
check "the widgets' own data untouched" grep -q '^		\["Build menu"\] = {$' "$BAR/LuaUI/Config/BYAR.lua"
check "same BAR file: BAR's Order menu off" order "Order menu" 0
check "same BAR file: the app's order menu copy on" order "BAR Droid order menu" 189
check "same BAR file: the controller game's own order menu on" order "Order menu (controller)" 189

start 1 "$made"
check "a second start: each entry once" order "BAR Droid build menu" 165

start 1 "0123456789abcdef0123456789abcdef"
check "BAR changed its file and no new copy: the old copy runs (the pad's RB is in it)" order "BAR Droid build menu" 165
check "BAR changed its file and no new copy: BAR's Build menu off" order "Build menu" 0
check "BAR changed its file and no new copy: an Android-layer miss" missed

start 1 ""
check "BAR's file not found: the copy runs" order "BAR Droid build menu" 165

echo "[t=0] Removed widget: BAR Droid build menu" > "$BAR/infolog.txt"
start 1 "fedcba9876543210fedcba9876543210"
check "the copy failed in the last game: BAR's own" order "Build menu" 165
check "the copy failed in the last game: the copy off" order "BAR Droid build menu" 0
check "the copy failed in the last game: an Android-layer miss" missed
rm -f "$BAR/infolog.txt"
start 1 "fedcba9876543210fedcba9876543210"
check "the copy failed on this BAR file: still BAR's own" order "BAR Droid build menu" 0
start 1 "$made"
check "another BAR file: the copy runs again" order "BAR Droid build menu" 165
rm -f "$BAR/.bardroid-buildmenu-failed"
printf '%s\n' "[t=0] [PreGame::ReadDataFromDemo] pre-scanning demo file" "[t=1] Removed widget: BAR Droid build menu" > "$BAR/infolog.txt"
start 1 "fedcba9876543210fedcba9876543210"
check "the copy removed in a replay (it plays its own BAR release): the copy still runs" order "BAR Droid build menu" 165
rm -f "$BAR/infolog.txt"
printf '%s\n' "fedcba9876543210fedcba9876543210" > "$BAR/.bardroid-buildmenu-failed"
start 1 "fedcba9876543210fedcba9876543210"
check "a mark from before \"game\" (a replay may have written it): the copy runs" order "BAR Droid build menu" 165
rm -f "$BAR/.bardroid-buildmenu-failed"

start 1 "$made" "0123456789abcdef0123456789abcdef"
check "BAR changed its Order menu and no new copy: the old copy runs" order "BAR Droid order menu" 189
check "BAR changed its Order menu and no new copy: BAR's off" order "Order menu" 0
check "BAR changed its Order menu and no new copy: an Android-layer miss" omissed
echo "[t=0] Removed widget: BAR Droid order menu" > "$BAR/infolog.txt"
start 1 "$made" "fedcba9876543210fedcba9876543210"
check "the order menu copy failed in the last game: BAR's own" order "Order menu" 189
check "the order menu copy failed in the last game: the copy off" order "BAR Droid order menu" 0
check "the order menu copy failed: the build menu copy keeps running" order "BAR Droid build menu" 165
rm -f "$BAR/infolog.txt"
start 1 "$made"
check "another BAR Order menu file: the copy runs again" order "BAR Droid order menu" 189
rm -f "$BAR/.bardroid-ordermenu-failed"
printf '%s\n' "[t=0] [PreGame::ReadDataFromDemo] pre-scanning demo file" "[t=1] Removed widget: BAR Droid order menu" > "$BAR/infolog.txt"
start 1 "$made" "fedcba9876543210fedcba9876543210"
check "the order menu copy removed in a replay: the copy still runs" order "BAR Droid order menu" 189
rm -f "$BAR/infolog.txt"

start 0 "$made"
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
check "8 GB: the low-memory widget told" setting BarDroidLowMemory 1
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

# The after-game check of the app's widgets (widget_error): an error line counts, the dev profiler's timer lines (which
# name every widget, "W:VisibleUnitRemoved:BAR Droid touch") do not (three false launcher warnings, 2026-11-05)
werr=$(grep '^widget_error() {' "$src")
[ -n "$werr" ] || { echo "[launchbartest] FAIL launch-bar.sh: widget_error not found"; exit 1; }
eval "$werr"
printf '%s\n' '[t=1][f=9] [simdraw] timers: W:VisibleUnitRemoved:BAR Droid touch 0.1%, W:Update:BAR Droid chat 0.2%' \
  '[t=2][f=9] Error in DrawScreen(): [string "LuaUI/Widgets/bardroid_chat.lua"]:12: attempt to index nil' > "$BAR/infolog.txt"
check "widget check: a profiler line is no error" [ -z "$(widget_error 'bardroid_touch|BAR Droid touch')" ]
check "widget check: a widget's error still is" widget_error_found 'bardroid_chat|BAR Droid chat'

echo "[launchbartest] done: $([ "$fails" = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ "$fails" = 0 ]
