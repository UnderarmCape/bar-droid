#!/bin/sh
# launch-bar.sh's switching of BAR's build menus in LuaUI/Config/BYAR.lua (the widget list both games share), on the
# laptop or in CI: its widget_order function and its controller-game block, taken from launch-bar.sh as they are,
# run against a scratch BAR write dir (build/launch-bar-test). Cases: the app's copy of BAR's Build menu in, BAR's own
# back when BAR's file is not the one the copy was made from (an Android-layer miss), the controller game switched
# off, and a second start changing nothing. Prints "[launchbartest] PASS|FAIL <case>"; exit 1 on a failure.
#   sh tools/launch-bar-test.sh          (tools\laptop-tests.ps1 runs it with the portable Git's sh)
here=$(cd "$(dirname "$0")/.." && pwd)
src="$here/app/src/main/assets/bardroid/launch-bar.sh"
copy="$here/app/src/main/assets/bardroid/bardroid_buildmenu.lua"
work="$here/build/launch-bar-test"
fails=0

fn=$(awk '/^widget_order\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$src")
block=$(awk '/^  if \[ "\$\{GAMEPAD_GAME:-0\}" = 1 \]; then/ { on = 1 } on { print } on && /^  fi$/ { exit }' "$src")
[ -n "$fn" ] && [ -n "$block" ] || { echo "[launchbartest] FAIL launch-bar.sh: widget_order or the controller-game block not found"; exit 1; }

BAR="$work/bar"; LOGS="$work/logs"
log() { :; }
layer_miss() { echo "$*" >> "$LOGS/android-layer.txt"; }
eval "$fn"
start() {   # one launch-bar.sh start: start <GAMEPAD_GAME> <md5 Installer found in BAR's release>
  GAMEPAD_GAME=$1
  printf '%s\n' "$2" > "$BAR/.bardroid-buildmenu"
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
quiet() { [ ! -s "$LOGS/android-layer.txt" ]; }

rm -rf "$work"
mkdir -p "$BAR/LuaUI/Config" "$BAR/LuaUI/Widgets" "$LOGS"
cp "$copy" "$BAR/LuaUI/Widgets/"
made=$(sed -n 's/^-- BARDROID_BUILDMENU_FROM //p' "$copy")
check "the copy says which BAR file it was made from" [ -n "$made" ]
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

start 1 "$made"
check "a second start: each entry once" order "BAR Droid build menu" 165

start 1 "0123456789abcdef0123456789abcdef"
check "BAR changed its file: BAR's Build menu on" order "Build menu" 165
check "BAR changed its file: the app's copy off" order "BAR Droid build menu" 0
check "BAR changed its file: an Android-layer miss" missed

start 1 ""
check "BAR's file not found: BAR's own" order "BAR Droid build menu" 0

start 0 "$made"
check "controller game off: BAR's Build menu at its default" absent "Build menu"
check "controller game off: the Grid menu at its default" absent "Grid menu"
check "controller game off: no controller build menu entry" absent "Build menu (controller)"
check "controller game off: the app's copy off" order "BAR Droid build menu" 0
check "controller game off: the marker gone" [ ! -f "$BAR/.bardroid-gamepad-menus" ]
check "the other widgets untouched" grep -q '^		Ecostats = 0,$' "$BAR/LuaUI/Config/BYAR.lua"

echo "[launchbartest] done: $([ "$fails" = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ "$fails" = 0 ]
