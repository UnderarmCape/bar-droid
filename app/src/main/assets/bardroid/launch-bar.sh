#!/bin/bash
# BAR Droid — container-side game launcher. Env from the app: ENGINE_VER, MODE (skirmish|lobby|bench|glcheck|shell),
# BARDROID_GPU (kgsl|zink|llvmpipe) with the matching Mesa variables, MESA_GL_VERSION_OVERRIDE (optional),
# BARDROID_AUDIO (0/1), BARDROID_FPS (frame cap), DISPLAY.
set -u
BAR=/root/bar
ENGINE="$BAR/engine/recoil_${ENGINE_VER:?}"
LOGS="$BAR/logs"; mkdir -p "$LOGS"
MODE="${MODE:-skirmish}"
GPU="${BARDROID_GPU:-kgsl}"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR=/tmp
if [ "$GPU" = llvmpipe ]; then
  # Emulator build, CPU rendering: Mesa's software rasterizer (GL 4.5 compatibility profile).
  export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
  unset MESA_LOADER_DRIVER_OVERRIDE
elif [ "$GPU" = virpipe ]; then
  # Emulator build, GPU: Mesa's virgl client; the app runs the virgl server on Android's GLES.
  export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=virpipe VTEST_SOCKET_NAME="${VTEST_SOCKET_NAME:-/tmp/.virgl_test}"
  unset MESA_LOADER_DRIVER_OVERRIDE
else
  export MESA_LOADER_DRIVER_OVERRIDE="$GPU"
fi
# Adreno's compressed render targets (UBWC) off for Freedreno: with them, panels BAR draws into textures of their own
# (the build menu, the idle builders button) came out in black columns 16 px wide in 2 of 9 skirmish starts on the
# dev phone, in none of 7 without; the late 8v8 took the same GPU time and memory either way (docs/DELIVERY.md,
# 2026-11-05). dev-env.sh, read later, can `unset FD_MESA_DEBUG` to have them back.
if [ "$GPU" = kgsl ]; then
  case ",${FD_MESA_DEBUG:-}," in
    *,noubwc,*) ;;
    *) export FD_MESA_DEBUG="${FD_MESA_DEBUG:+$FD_MESA_DEBUG,}noubwc" ;;
  esac
fi
export MESA_VK_WSI_PRESENT_MODE="${MESA_VK_WSI_PRESENT_MODE:-mailbox}"
# Never wait for vblank: the frame cap is libbardroid_pace.so below instead of VSync. With swap interval 0 and the
# explicit Present fence (which pace.c steers lfdevs' Mesa onto, see there) Mesa keeps a third back buffer and never
# waits for the GPU at the swap, so the CPU builds the next frame while the GPU draws the last.
export vblank_mode="${vblank_mode:-0}"
export XCURSOR_SIZE=32
export SDL_VIDEODRIVER=x11
export SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR=0
export PRD_RAPID_REPO_MASTER="https://repos-cdn.beyondallreason.dev/repos.gz"
export PRD_HTTP_SEARCH_URL="https://files-cdn.beyondallreason.dev/find"
export PRD_RAPID_USE_STREAMER=false
export PRD_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
# AngelScript ARM64 call stub missing from the official arm64 BARb/CircuitAI build (see docs/arm64-ai-fix.md).
# Preloaded into the engine alone (LD_PRELOAD on its ./spring lines below, not exported): they live in the write folder,
# which the game's Lua can write, and exported every sleep, pidof and taskset this script starts loaded them as well, a
# library written mid-game within 3 s (release overhaul item 9, 2026-11-21). A developer's dev-env.sh may set its own.
PRELOAD=""
[ "$(uname -m)" = aarch64 ] && [ -f "$BAR/libasarm64.so" ] && PRELOAD="$BAR/libasarm64.so"
# Frame cap: sleeps after each buffer swap to BARDROID_FPS (from the app's 30/60 fps setting; 0 = none), and the
# hidden window (screen off, catching up). The emulator build's x86_64 copy (no cap, no Present-fence answer).
if [ -f "$BAR/libbardroid_pace.so" ]; then
  PRELOAD="${PRELOAD:+$PRELOAD:}$BAR/libbardroid_pace.so"
  export BARDROID_FPS="${BARDROID_FPS:-30}"
  # New textures start as zeros: Mesa's recycled GPU buffers hold old pictures, which BAR's panels showed as noise.
  [ "$(uname -m)" = aarch64 ] && export BARDROID_TEX_ZERO=1
fi

log() { echo "[launch] $*"; }
# Android layer (docs/UPDATES.md): a tweak of BAR's files that no longer finds its target is never skipped silently.
# The app reads the list after the engine exits and shows it in the launcher.
: > "$LOGS/android-layer.txt"
layer_miss() { log "!!! ANDROID LAYER: $* -- BAR changed this; the app needs a fix"; echo "$*" >> "$LOGS/android-layer.txt"; }

# 1. Wait for the X server socket (the app starts it right before us).
for i in $(seq 1 100); do
  [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] && break
  sleep 0.2
done
if [ ! -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then log "X socket /tmp/.X11-unix/X${DISPLAY#:} never appeared"; exit 10; fi
log "X socket present"

# 2. Audio: the engine's OpenAL Soft writes the mixed sound (a WAV header, then raw PCM) into a FIFO that the app
#    plays through AudioTrack (springsettings: UseSDLAudio = 0). OpenAL's mixer thread paces itself by the clock and
#    catches up after a stall, so a busy CPU only delays sound. (SDL + PulseAudio's pipe sink cut a hole into the
#    sound every time the engine's audio callback was late; setup-container.sh's slim step purges PulseAudio.)
if [ "${BARDROID_AUDIO:-1}" = "1" ]; then
  [ -p /tmp/bardroid-audio.fifo ] || mkfifo /tmp/bardroid-audio.fifo 2>/dev/null || true
  # (resampler linear: the sounds' rates to 48 kHz the cheapest smooth way; the default's longer filter cost the mixer
  # more than a phone's speakers can tell, PHONE_GFX's UseEFX/MaxSounds below)
  printf '[general]\ndrivers = wave\nfrequency = 48000\nchannels = stereo\nsample-type = int16\nperiod_size = 512\nresampler = linear\n[wave]\nfile = /tmp/bardroid-audio.fifo\n' > /root/.alsoftrc
else
  printf '[general]\ndrivers = null\n' > /root/.alsoftrc   # nobody reads the FIFO: opening it would block
fi
export ALSOFT_CONF=/root/.alsoftrc

# 3. One-time GL probe, saved for the findings/bug reports.
if [ "$MODE" = "glcheck" ] || [ ! -f "$LOGS/glcheck-$GPU.txt" ]; then
  {
    echo "driver=$GPU gl_override=${MESA_GL_VERSION_OVERRIDE:-none} date=$(date)"
    glxinfo -B 2>&1
    echo "--- extensions of interest"
    for e in GL_EXT_texture_compression_s3tc GL_ARB_multi_draw_indirect GL_ARB_shader_storage_buffer_object \
             GL_ARB_uniform_buffer_object GL_ARB_buffer_storage GL_ARB_clip_control GL_ARB_texture_compression_bptc \
             GL_ARB_explicit_attrib_location GL_ARB_compute_shader; do
      glxinfo 2>/dev/null | grep -q "$e" && echo "yes $e" || echo "NO  $e"
    done
    echo "--- vulkan"; vulkaninfo --summary 2>&1 | grep -E "deviceName|apiVersion|driverName" | head -n 6
  } > "$LOGS/glcheck-$GPU.txt" 2>&1
  cat "$LOGS/glcheck-$GPU.txt"
  [ "$MODE" = "glcheck" ] && exit 0
fi

# BAR's Grid menu off and a Build menu in its place (LuaUI/Config/BYAR.lua, BAR's widget order): the app's copy of
# BAR's Build menu, sized with the layout editor (Kailil, 2026-10-28: "just rebuild the exact same one with the ability
# for us to resize it freely"; bardroid_buildmenu.lua, tools/make-buildmenu.py), while BAR's file is still the one it was
# copied from (Installer writes that file's md5 to .bardroid-buildmenu), else BAR's own. (Until 2026-11-06 singleplayer
# played Kailil's controller game, v0.8.5 as BAR's developer game, with its own "(controller)" menus.)
widget_order() {   # widget_order <widget name> <order>, or "" to drop the entry (the widget's default)
  f="$BAR/LuaUI/Config/BYAR.lua"
  [ -f "$f" ] || { mkdir -p "$BAR/LuaUI/Config"; printf -- '-- Widget Custom data and order, order = 0 disabled widget\nreturn {\n\torder = {\n\t},\n}\n' > "$f"; }
  # the name as a regex and as replacement text ("Keybind/Mouse Info": a / would end the sed expression)
  re=$(printf '%s' "$1" | sed 's/[][\/.*^$]/\\&/g'); rep=$(printf '%s' "$1" | sed 's/[\/&]/\\&/g')
  # BAR writes a name that is a Lua identifier as a plain key ("Ecostats = 164,"), others in brackets
  # ('["Reclaim Field Highlight"] = 0,'): both forms are set (an added bracket entry before a plain one lost: Lua takes
  # the last of two, and Ecostats stayed on, 2026-10-27)
  plain=""
  case "$1" in ""|[0-9]*|*[!A-Za-z0-9_]*) ;; *) plain="^\([[:space:]]*\)$re *= *-\?[0-9][0-9]*" ;; esac
  found=""
  if grep -q "\[\"$re\"\] *= *-\?[0-9][0-9]*" "$f"; then
    found=1
    if [ -n "$2" ]; then sed -i "s/\[\"$re\"\] *= *-\?[0-9][0-9]*/[\"$rep\"] = $2/" "$f"
    else sed -i "/\[\"$re\"\] *= *-\?[0-9][0-9]*,\?[ \t]*$/d" "$f"; fi
  fi
  if [ -n "$plain" ] && grep -q "$plain" "$f"; then
    found=1
    if [ -n "$2" ]; then sed -i "s/$plain/\1$rep = $2/" "$f"
    else sed -i "/$plain,\?[ \t]*$/d" "$f"; fi
  fi
  if [ -z "$found" ] && [ -n "$2" ]; then   # the top-level order table (one tab in, as BAR writes it), not a widget's "...order = {"
    sed -i "0,/^\torder *= *{/s//\torder = {\n\t\t[\"$rep\"] = $2,/" "$f"
  fi
  [ -z "$2" ] || grep -q "\[\"$re\"\] *= *$2," "$f" || { [ -n "$plain" ] && grep -q "^[[:space:]]*$re *= *$2," "$f"; } \
    || layer_miss "widget order: \"$1\" = $2 not set in LuaUI/Config/BYAR.lua"
}
# BAR's Camera Remember opens each game in the camera the last one quit in: a first-person one (mode 0) would hold every
# later game there, with no start view (BAR's Camera Startup leaves other cameras alone). bardroid_padfp.lua puts the
# camera back as a game quits; a game that left one all the same, or one from before that, is forgotten here.
forget_fps_camera() {
  f="$BAR/LuaUI/Config/BYAR.lua"
  [ -f "$f" ] || return 0
  if sed -n '/^\t\t\["Camera Remember"\] *= *{/,/^\t\t},/p' "$f" | grep -q '[[:space:]]mode = 0,'; then
    sed -i '/^\t\t\["Camera Remember"\] *= *{/,/^\t\t},/d' "$f"
    log "camera: the first-person camera a game quit in forgotten"
  fi
}
forget_fps_camera
# The engine writes a game's replay as the game ends: one ended by Stop, a swipe from recent apps or Android's low-memory
# killer leaves an empty file, which the lobby's Replays tab listed with nothing to read (282 of 355 on the dev phone,
# 2026-11-02). Nothing is recording now (one engine at a time): empty ones go.
empty=$(find "$BAR/demos" -maxdepth 1 -name '*.sdfz' -size 0 2>/dev/null | wc -l)
if [ "$empty" -gt 0 ]; then
  find "$BAR/demos" -maxdepth 1 -name '*.sdfz' -size 0 -delete 2>/dev/null
  log "replays: $empty empty ones (games that were stopped) removed"
fi
# sed -i writes a whole copy (sedXXXXXX) beside the file and renames it over the file: a start stopped in between leaves
# the copy (a 28 KB BYAR.lua in LuaUI/Config on the dev phone, 2026-10-31). This script is the only sed here, and none
# of its own is running now.
stale=$(find "$BAR" "$BAR/LuaUI/Config" "$BAR/LuaMenu/Config" -maxdepth 1 -type f -name 'sed??????' 2>/dev/null)
if [ -n "$stale" ]; then
  printf '%s\n' "$stale" | while IFS= read -r s; do rm -f "$s"; done
  log "settings: $(printf '%s\n' "$stale" | wc -l) half-made sed copies (a start that was stopped) removed"
fi
# The app's copy of BAR's Build menu in BAR's place, in every game: the pad's RB, PLACE and the shapes are in it (Kailil,
# 2026-11-01, after BAR's update turned it off in an online game: "that is UNACCEPTABLE"). Installer makes it again when an
# update changes BAR's file; one it could not (BAR rewrote a part a patch needs) runs all the same, and is named. Only a
# copy BAR had to remove in the last game (an error in it) gives way to BAR's own, for that BAR file.
# A replay does not count: it plays the BAR release it was recorded with, whose widgets an older one's copy may not fit
# (a replay from 2026-10-01 removed both copies, and every game after ran BAR's own menus: dev phone, 2026-11-04). The
# mark says "game" since then; an older one, which a replay may have written, no longer counts.
# BAR's widget handler's own words in an engine run's infolog (luaui/barwidgets.lua): "Failed to load: <file>  (<why>)"
# as a file loads, "Error in <call-in>(): ..." (or "Sandbox error in") and "Removed widget: <name>" for an error in a
# running one. A line counts only as the whole body after the engine's log prefix ("[t=...][f=...] "): another player's
# chat with those words is "<name> Removed widget: ..." there, a spectator's "[name] ...", a map ping's label
# "<name> added point: ...", and a chat line could switch the app's menu copies off until an app update (release
# overhaul item 3, 2026-11-21). "(no GetInfo() call)" is a file that is no widget in this game (BAR's tools, a copy
# outside a scenario) and "(duplicate name)" a second copy of one that runs: nothing failed. A replay plays the BAR
# release it was recorded with, whose widgets an older copy may not fit: REPLAY 1, its faults not the copies'.
read_faults() {   # read_faults: FAULTS (the lines' bodies, in order) and REPLAY from $BAR/infolog.txt
  FAULTS=$(grep -aE '^\[t=[^]]*\]\[f=-?[0-9]+\] (Failed to load: |(Sandbox )?[Ee]rror in |Removed widget: )' "$BAR/infolog.txt" 2>/dev/null \
    | sed -E 's/^\[t=[^]]*\]\[f=-?[0-9]+\] //' | grep -avE '^Failed to load: [^ ]+  \((no GetInfo\(\) call|duplicate name)\)$')
  REPLAY=0
  grep -aqE '^\[t=[^]]*\]\[f=-?[0-9]+\] \[PreGame::ReadDataFromDemo\] ' "$BAR/infolog.txt" 2>/dev/null && REPLAY=1
}
read_faults   # (the last run's, for the copies below)
# copy_removed <widget name> <its file>: in the last run, not a replay, BAR removed it for an error (one in its Shutdown
# alone, after a whole game, does not count) or its file failed to load (the widget never ran: BAR's own then had its
# place switched off too, no build menu at all)
copy_removed() {
  [ "$REPLAY" = 0 ] && [ -n "$FAULTS" ] || return 1
  printf '%s\n' "$FAULTS" | awk -v gone="Removed widget: $1" -v failed="Failed to load: ${2##*/}  (" '
    ($0 == gone && prev !~ /^Error in Shutdown\(\): /) || index($0, failed) == 1 { hit = 1 } { prev = $0 } END { exit !hit }'
}
# The mark names BAR's file and the copy (its md5): a new copy, from an app update, gets another try. With BAR's file
# alone, the Fold7's order menu copy, removed in one game on 2026-11-05, gave way to BAR's own through every app update
# after it (its launcher: "1 of the app's adjustments to BAR did not apply", 2026-11-10).
copy_failed() {   # copy_failed <widget name> <mark file> <BAR's file md5> <the copy>: true while it gives way
  key="$3 game $(md5sum "$4" 2>/dev/null | cut -c1-32)"
  copy_removed "$1" "$4" && printf '%s\n' "$key" > "$2"
  [ -f "$2" ] && [ "$(cat "$2")" = "$key" ]
}
build_menu() {
  copied=$(sed -n 's/^-- BARDROID_BUILDMENU_FROM //p' "$BAR/LuaUI/Widgets/bardroid_buildmenu.lua" 2>/dev/null)
  bars=$(cat "$BAR/.bardroid-buildmenu" 2>/dev/null)
  failed="$BAR/.bardroid-buildmenu-failed"
  if [ -z "$copied" ] || copy_failed 'BAR Droid build menu' "$failed" "$bars" "$BAR/LuaUI/Widgets/bardroid_buildmenu.lua"; then
    widget_order "Build menu" 165; widget_order "BAR Droid build menu" 0
    layer_miss "build menu: the app's copy (made from ${copied:-?}) failed on BAR's gui_buildmenu.lua ${bars:-not found}: BAR's own, no pad focus on it, until the copy is made again (tools/make-buildmenu.py)"
    return
  fi
  widget_order "Build menu" 0; widget_order "BAR Droid build menu" 165
  if [ "$copied" = "$bars" ]; then
    log "build menu: the app's copy of BAR's (gui_buildmenu.lua $copied), sized with the layout editor"
  else
    layer_miss "build menu: BAR's gui_buildmenu.lua is ${bars:-not found}, the app's copy was made from $copied and could not be made again: the old copy runs (tools/make-buildmenu.py)"
  fi
}
# The app's copy of BAR's Order menu in BAR's place, the same way (Kailil, 2026-11-03: online the order menu should
# "behave like offline": the orders the pad leaves fill the menu, as in v0.8.5's; bardroid_ordermenu.lua,
# tools/make-ordermenu.py).
order_menu() {
  copied=$(sed -n 's/^-- BARDROID_ORDERMENU_FROM //p' "$BAR/LuaUI/Widgets/bardroid_ordermenu.lua" 2>/dev/null)
  bars=$(cat "$BAR/.bardroid-ordermenu" 2>/dev/null)
  failed="$BAR/.bardroid-ordermenu-failed"
  if [ -z "$copied" ] || copy_failed 'BAR Droid order menu' "$failed" "$bars" "$BAR/LuaUI/Widgets/bardroid_ordermenu.lua"; then
    widget_order "Order menu" 189; widget_order "BAR Droid order menu" 0
    layer_miss "order menu: the app's copy (made from ${copied:-?}) failed on BAR's gui_ordermenu.lua ${bars:-not found}: BAR's own, its grid with the pad, until the copy is made again (tools/make-ordermenu.py)"
    return
  fi
  widget_order "Order menu" 0; widget_order "BAR Droid order menu" 189
  if [ "$copied" = "$bars" ]; then
    log "order menu: the app's copy of BAR's (gui_ordermenu.lua $copied), the orders the pad leaves filling it"
  else
    layer_miss "order menu: BAR's gui_ordermenu.lua is ${bars:-not found}, the app's copy was made from $copied and could not be made again: the old copy runs (tools/make-ordermenu.py)"
  fi
}
# The app's copy of BAR's Mission Info (a scenario's briefing) in BAR's place, the same way (Kailil, 2026-11-10: "the game
# start ui popup needs to fit vertical screen": BAR's ran off both sides upright; bardroid_missioninfo.lua,
# tools/make-missioninfo.py). Outside a scenario both stop at their first line, as BAR's always has.
mission_info() {
  copied=$(sed -n 's/^-- BARDROID_MISSIONINFO_FROM //p' "$BAR/LuaUI/Widgets/bardroid_missioninfo.lua" 2>/dev/null)
  bars=$(cat "$BAR/.bardroid-missioninfo" 2>/dev/null)
  failed="$BAR/.bardroid-missioninfo-failed"
  if [ -z "$copied" ] || copy_failed 'BAR Droid mission info' "$failed" "$bars" "$BAR/LuaUI/Widgets/bardroid_missioninfo.lua"; then
    widget_order "Mission Info" ""; widget_order "BAR Droid mission info" 0
    layer_miss "mission info: the app's copy (made from ${copied:-?}) failed on BAR's gui_mission_info.lua ${bars:-not found}: BAR's own, too wide upright, until the copy is made again (tools/make-missioninfo.py)"
    return
  fi
  widget_order "Mission Info" 0; widget_order "BAR Droid mission info" 190
  if [ "$copied" = "$bars" ]; then
    log "mission info: the app's copy of BAR's (gui_mission_info.lua $copied), fitted to the screen"
  else
    layer_miss "mission info: BAR's gui_mission_info.lua is ${bars:-not found}, the app's copy was made from $copied and could not be made again: the old copy runs (tools/make-missioninfo.py)"
  fi
}
# The app's copy of BAR's TeamStats panel (its graphs: the awards' Show Graphs, the top bar's Statistics) in BAR's
# place, the same way (Kailil, 2026-11-10: the game-end recap and graph fit upright; BAR's was 2046 wide on 936;
# bardroid_teamstats.lua, tools/make-teamstats.py)
team_stats() {
  copied=$(sed -n 's/^-- BARDROID_TEAMSTATS_FROM //p' "$BAR/LuaUI/Widgets/bardroid_teamstats.lua" 2>/dev/null)
  bars=$(cat "$BAR/.bardroid-teamstats" 2>/dev/null)
  failed="$BAR/.bardroid-teamstats-failed"
  if [ -z "$copied" ] || copy_failed 'BAR Droid team stats' "$failed" "$bars" "$BAR/LuaUI/Widgets/bardroid_teamstats.lua"; then
    widget_order "TeamStats" ""; widget_order "BAR Droid team stats" 0
    layer_miss "team stats: the app's copy (made from ${copied:-?}) failed on BAR's gui_teamstats.lua ${bars:-not found}: BAR's own, too wide upright, until the copy is made again (tools/make-teamstats.py)"
    return
  fi
  # (BAR's own at its default: the copy's GetInfo replaces keeps it off while the copy runs, and a copy that stands down
  # in an older release's replay, without its model, leaves BAR's own on; at 0 here it stayed off there too)
  widget_order "TeamStats" ""; widget_order "BAR Droid team stats" 191
  if [ "$copied" = "$bars" ]; then
    log "team stats: the app's copy of BAR's (gui_teamstats.lua $copied), fitted to the screen"
  else
    layer_miss "team stats: BAR's gui_teamstats.lua is ${bars:-not found}, the app's copy was made from $copied and could not be made again: the old copy runs (tools/make-teamstats.py)"
  fi
}
# The app's widgets as the game's (BARDROID_GAME_WIDGETS=1 in dev-env.sh, with an engine-branch build that has
# BarDroidGameWidgetsDir, docs/ENGINE-SIM.md "The app's widgets as the game's"; Kailil, 2026-11-06, on a BAR developer's
# advice: they are the phone's mouse and keyboard, not unit-control widgets): they move to $GAME_WIDGETS, which that
# engine shows LuaUI as part of the game archive, so BAR loads them as game widgets. Back in LuaUI/Widgets first, as
# every start finds them (Installer puts new ones there: a newer one there wins), and moved again after dev-env.sh.
APP_WIDGETS="bardroid_touch bardroid_queue bardroid_chat bardroid_info bardroid_players bardroid_bench bardroid_spectate
  bardroid_minimap bardroid_layout bardroid_buildmenu bardroid_ordermenu bardroid_pad bardroid_padspeed bardroid_padfp
  bardroid_lowmem bardroid_buildrange bardroid_sensors bardroid_nano bardroid_portrait bardroid_missioninfo bardroid_retreat
  bardroid_presets bardroid_automex bardroid_teamstats bardroid_topbar bardroid_options bardroid_camctl bardroid_walls"
GAME_WIDGETS="$BAR/bardroid-ui/LuaUI/Widgets"
app_widgets_to() { # app_widgets_to <from dir> <to dir>: the app's widgets moved; one already there stays (the newer)
  mkdir -p "$2"
  for w in $APP_WIDGETS; do
    [ -f "$1/$w.lua" ] || continue
    if [ -f "$2/$w.lua" ] && [ "$2" = "$BAR/LuaUI/Widgets" ]; then rm -f "$1/$w.lua"; else mv -f "$1/$w.lua" "$2/$w.lua"; fi
  done
}
[ -d "$GAME_WIDGETS" ] && app_widgets_to "$GAME_WIDGETS" "$BAR/LuaUI/Widgets"
# bardroid-ui is the app's alone: with the phone engine every file in its LuaUI/Widgets loads as one of the game's
# widgets, past a host's ban on user widgets, and one the app no longer ships (a retired widget, or a file put there by
# Lua: BAR's handler lets user widgets write in LuaUI/Config and LuaUI/Widgets only since test-31943, an older
# release's, which a replay plays, in the whole write folder) loaded in every game after. At every start, once the
# app's own are out (above), everything else in it goes; they alone go back in below (release overhaul item 4).
game_widgets_only() {
  [ -d "$BAR/bardroid-ui" ] || return 0
  gone=$(find "$BAR/bardroid-ui" ! -type d 2>/dev/null | while IFS= read -r f; do
    keep=0
    for w in $APP_WIDGETS; do [ "$f" = "$GAME_WIDGETS/$w.lua" ] && keep=1; done   # (one whose move back failed)
    [ "$keep" = 1 ] && continue
    rm -f "$f" && printf '%s\n' "${f#"$BAR"/}"
  done)
  find "$BAR/bardroid-ui" -mindepth 1 -depth -type d -empty -delete 2>/dev/null
  [ -z "$gone" ] || log "!!! bardroid-ui: removed what is not the app's widgets (only the app's load as the game's), $(printf '%s\n' "$gone" | wc -l | tr -d ' ') in all: $(printf '%s\n' "$gone" | head -n 3 | tr '\n' ' ' | sed 's/ $//')"
}
game_widgets_only
rm -f "$BAR/LuaUI/Config/bardroid_game_widgets.txt"   # (the lobby's warnings about a host's widget options: shown)

# With loadLocalWidgets on (below: the app's own lobby widget needs it) the lobby loads every LuaMenu widget in the write
# folder, with no sandbox. In a release build only the app's own stays there: a file put there by the game's Lua would
# have run in every lobby (release overhaul item 9, 2026-11-21). A developer's build keeps the tools' test widgets.
lobby_widgets_only() {
  [ "${BARDROID_DEV:-0}" = 1 ] && return 0
  [ -d "$BAR/LuaMenu/Widgets" ] || return 0
  gone=$(find "$BAR/LuaMenu/Widgets" ! -type d 2>/dev/null | while IFS= read -r f; do
    [ "$f" = "$BAR/LuaMenu/Widgets/bardroid_lobby_touch.lua" ] && continue
    rm -f "$f" && printf '%s\n' "${f#"$BAR"/}"
  done)
  [ -z "$gone" ] || log "!!! LuaMenu/Widgets: removed what is not the app's lobby widget, $(printf '%s\n' "$gone" | wc -l | tr -d ' ') in all: $(printf '%s\n' "$gone" | head -n 3 | tr '\n' ' ' | sed 's/ $//')"
}

LOBBY_GAME=byar
if [ "$MODE" = skirmish ] || [ "$MODE" = lobby ] || [ "$MODE" = bench ]; then
  widget_order "Grid menu" 0
  build_menu
  order_menu
  mission_info
  team_stats
  if [ -f "$BAR/.bardroid-gamepad-menus" ]; then   # (an install from the controller game's days: its menus' entries)
    widget_order "Build menu (controller)" ""
    widget_order "Order menu (controller)" ""
    rm -f "$BAR/.bardroid-gamepad-menus"
  fi
  igl="$BAR/LuaMenu/Config/IGL_data.lua"   # the lobby's saved settings: they override chobby_config.json's game
  if [ -f "$igl" ]; then
    if grep -q 'gameConfigName = "' "$igl"; then
      sed -i "s/gameConfigName = \"[^\"]*\"/gameConfigName = \"$LOBBY_GAME\"/" "$igl"
    else
      sed -i "0,/\[\"Chili lobby\"\] *= *{/s//&\n\t\tgameConfigName = \"$LOBBY_GAME\",/" "$igl"
    fi
    grep -q "gameConfigName = \"$LOBBY_GAME\"" "$igl" || layer_miss "singleplayer game: gameConfigName not set in LuaMenu/Config/IGL_data.lua"
    # the lobby loads the app's LuaMenu/Widgets/bardroid_lobby_touch.lua (finger scrolling, server details first) only
    # with its developer setting "load local widgets"
    if grep -q 'loadLocalWidgets = ' "$igl"; then
      sed -i 's/loadLocalWidgets = [a-z]*/loadLocalWidgets = true/' "$igl"
    else
      sed -i "0,/\[\"Chili lobby\"\] *= *{/s//&\n\t\tloadLocalWidgets = true,/" "$igl"
    fi
    grep -q 'loadLocalWidgets = true' "$igl" || layer_miss "lobby touch: loadLocalWidgets not set in LuaMenu/Config/IGL_data.lua"
  fi
  lobby_widgets_only
  log "singleplayer game: $LOBBY_GAME"
fi

# A benchmark's own engine settings (tools/phone-bench.ps1 -Settings, the file .bardroid-bench-settings: key = value
# lines) change springsettings.cfg for that run only: the file as it was before goes back at the next start, before
# anything else here touches it (and phone-bench.ps1 puts it back after its run). The benchmark's files, which the
# developer's tools write over adb, count only in a developer's build (BARDROID_DEV): the write folder is the game's Lua's
# to write too, and .bardroid-bench-settings went into a sed command as it was (release overhaul item 9, 2026-11-21).
if [ "${BARDROID_DEV:-0}" = 1 ] && [ -f "$BAR/.springsettings.pre-bench" ]; then
  mv "$BAR/.springsettings.pre-bench" "$BAR/springsettings.cfg" && log "settings from before the benchmark put back"
fi

# Phone graphics at every start, whatever preset BAR's settings hold (Kailil's target: 30 fps for hours on a hot
# phone; "disable msaa on every graphics profile or setting", "we can still cut more things"). Every one of these
# costs more the more of the map a tilted camera shows. The lobby keeps its own copy of the engine's settings
# (Chobby's game_settings in IGL_data.lua) and writes it into springsettings.cfg whenever a game starts, so both get
# them; the engine reads MSAALevel only at startup.
#   MSAALevel, FSAA        no multisampling (the lobby's MSAALevel = 4 drew every game 4x multisampled)
#   Shadows, ShadowQuality off (BAR's shadow slider reads ShadowQuality and sets Shadows from it)
#   FeatureDrawDistance    trees and rocks fade out from 4800 and are gone at 6000 (the lobby's 600000: every one on
#   FeatureFadeDistance    the map in a tilted view)
#   GroundDetail           60, the engine's default
#   BumpWater*             BAR's "high" water without the reflection and refraction passes (each draws the scene again)
#   GrassDetail            0 (the engine's grass; BAR draws its own)
#   SmoothLines/Points     0
#   CamMode                2, the Spring camera (BAR's default, the one finger twist and tilt turn): the lobby's
#                          CamMode = 1 started singleplayer games with the overhead camera, which has neither
#   VSync*                 off: libbardroid_pace.so caps the frame rate (bardroid_touch.lua once set VSyncGame 1 and
#                          VSyncFraction 2, which BAR multiplies into VSync at every game start)
#   UnitIconFade*          1, the strictest unit LOD BAR has (its "Unit icon distance" slider at its minimum): a unit is
#                          an icon whenever its model would look smaller than the icon, so only units close to the
#                          camera are drawn as models (Kailil, 2026-10-26, late games: "a max distance something is
#                          animated ... like a lod system"; a test, see docs/HISTORY.md)
#   UseEFX 0, MaxSounds 48 the sound mixer lighter (Kailil, 2026-11-05: heat): no reverb or underwater muffling, 48 sounds
#                          at once (BAR's 128); with OpenAL's linear resampler (.alsoftrc above) its thread took 5 % of the
#                          engine's CPU in a late 8v8 replay on the dev phone, where it took 10 %
#   MiniMapRefreshRate 8   the minimap's picture (every unit's icon) drawn again 8 times a second, not the engine's 15
#                          for a small minimap: its GPU time 0.25 -> 0.05 % in a late 8v8 on the dev phone, whose GPU
#                          is the limit once hot (docs/ENGINE-SIM.md on engine/sim, "BAR's Lua on phones")
PHONE_GFX="MSAALevel=0 FSAA=0 Shadows=0 ShadowQuality=0 FeatureDrawDistance=6000 FeatureFadeDistance=4800 GroundDetail=60
  BumpWaterReflection=0 BumpWaterRefraction=0 GrassDetail=0 SmoothLines=0 SmoothPoints=0 CamMode=2
  VSync=0 VSyncGame=0 VSyncFraction=1 UnitIconFadeStart=1 UnitIconFadeVanish=1 UseEFX=0 MaxSounds=48 MiniMapRefreshRate=8"
for kv in $PHONE_GFX; do
  k=${kv%%=*}; v=${kv#*=}
  if grep -q "^$k *=" "$BAR/springsettings.cfg"; then sed -i "s/^$k *=.*/$k = $v/" "$BAR/springsettings.cfg"
  else echo "$k = $v" >> "$BAR/springsettings.cfg"; fi
  [ -f "$BAR/LuaMenu/Config/IGL_data.lua" ] && sed -i "s/^\([[:space:]]*$k = \)[0-9.-]*,/\1$v,/" "$BAR/LuaMenu/Config/IGL_data.lua"
done
# Phones with less than 9.5 GB (8 GB: Android ended every game while it loaded, docs/HISTORY.md "Fitting BAR into an
# 8 GB phone"): over 1 GB less engine memory, all client settings (online-safe). The 12 GB phones keep the above.
#   UseLuaMemPools 0       the engine's Lua pools take 128 MB each (32 size classes of 4 MB, every page written when
#                          the pool is made), nine of them in a game: 1.15 GB, while BAR's Lua uses ~150 MB in all
#   TextureMemPoolSize 0   no memory set aside for loading pictures
#   CompressTextures 1     textures compressed on the GPU (~300 MB less GPU memory, which a phone can never swap);
#                          the two textures the engine draws into come back uncompressed (libbardroid_pace.so,
#                          BARDROID_FBO_UNCOMPRESS; else unit icons draw as black squares)
#   cus2 0                 BAR's GL4 unit shaders off (BAR's cus_gl4.lua): the engine's plainer unit shading; a
#                          developer game ("$VERSION") would switch them back on, which bardroid_lowmem.lua
#                          (BarDroidLowMemory) prevents
#   BumpWaterShoreWaves 0  no foam along the shores (BAR's water setting; a 4096x4096 half-float texture, 128 MB)
#   GroundDecals 0         no tracks and scorch marks on the ground (BAR does the same for a low-end GPU in its game)
#   SMFTextureStreaming, MaxTextureAtlasSize* 2048, AllowDeferred*Rendering 0, HighResInfoTexture 0: smaller map and
#                          atlas textures, no G-buffers (nothing on the phone reads them: lights and decals are off)
mem_kb=$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo)
if [ "${mem_kb:-0}" -gt 0 ] && [ "$mem_kb" -lt 9277343 ]; then
  LOW_MEMORY="UseLuaMemPools=0 TextureMemPoolSize=0 CompressTextures=1 cus2=0 BarDroidLowMemory=1
    BumpWaterShoreWaves=0 GroundDecals=0 SMFTextureStreaming=1 MaxTextureAtlasSizeX=2048 MaxTextureAtlasSizeY=2048
    AllowDeferredMapRendering=0 AllowDeferredModelRendering=0 HighResInfoTexture=0"
  for kv in $LOW_MEMORY; do
    k=${kv%%=*}; v=${kv#*=}
    if grep -q "^$k *=" "$BAR/springsettings.cfg"; then sed -i "s/^$k *=.*/$k = $v/" "$BAR/springsettings.cfg"
    else echo "$k = $v" >> "$BAR/springsettings.cfg"; fi
    [ -f "$BAR/LuaMenu/Config/IGL_data.lua" ] && sed -i "s/^\([[:space:]]*$k = \)[0-9.-]*,/\1$v,/" "$BAR/LuaMenu/Config/IGL_data.lua"
  done
  export BARDROID_FBO_UNCOMPRESS=1
  log "low-memory mode ($((mem_kb / 1024)) MB of RAM): $(echo $LOW_MEMORY)"
fi
# and BAR's full-screen effects off (order 0 = disabled; BAR's settings can switch them on again until the next start):
# bloom, ambient occlusion, heat distortion, snow, the mirrored map beyond its edges; and the lights' screen-space
# shadows (a full-screen pass, BAR's default 2) in that widget's saved settings. (A user widget cannot do it: BAR
# refuses "/option" from user widgets.)
if [ "$MODE" = skirmish ] || [ "$MODE" = lobby ] || [ "$MODE" = bench ]; then
  for w in "Bloom Shader Deferred" "SSAO" "Distortion GL4" "Snow" "Map Edge Extension"; do widget_order "$w" 0; done
  # BAR's Show Builder Queue draws every queued building on the map every frame: the app's "BAR Droid builder queue"
  # (bardroid_queue.lua) draws only those near where the camera looks
  widget_order "Show Builder Queue" 0
  # Late games are limited by the GPU (Kailil, 2026-10-26, "All four"): BAR's lights (every shot and explosion lights
  # the ground), scorch marks, the shadow plates under units and wrecks, the map's grass, the animated order lines
  for w in "Deferred rendering GL4" "Decals GL4" "Ground AO Plates GL4" "Ground AO Plates Features GL4" "Map Grass GL4" \
    "Commands FX"; do widget_order "$w" 0; done
  # Profiled on the laptop with the phone's set (tools/profile-big-game.ps1, 2026-10-26): BAR's full-screen sharpening
  # pass (Contrast Adaptive Sharpen, GPU); and Jammed Units Highlight, a faint red tint on units inside jammer cover that
  # checks every unit every 6 simulated frames (a spectator: every unit of the game), the costliest widget per
  # simulated frame (13.8 ms/s at 10x on the laptop): catching up and late games run on the CPU
  widget_order "Contrast Adaptive Sharpen" 0; widget_order "Jammed Units Highlight" 0
  # BAR's Reclaim Field Highlight outlines fields of wrecks for builders; it recomputes the fields as every wreck
  # appears even while it shows nothing: the costliest widget in big battles, 3.1% of the phone's running time and over
  # half of LuaUI's garbage (docs/HISTORY.md, 2026-10-27 evening). Kailil: "Turn Reclaim Field Highlight off"
  widget_order "Reclaim Field Highlight" 0
  # BAR's Ecostats: the alliances' resource bars in the top right corner (Kailil, 2026-10-27: "hidden if possible")
  widget_order "Ecostats" 0
  # BAR's Cache Icons loads every unit's picture in a game's first seconds (~570 with Legion, Raptors and Scavengers),
  # so that none shows white for a moment: 137 MB of GPU memory on a phone, uncompressed, and loading work in the
  # start's stutter (dev phone, 2026-11-02; Kailil's online game on the Fold7 ended by Android's low-memory killer).
  # Without it a picture loads when first shown (the app's build menu loads its page's own as it opens).
  widget_order "Cache Icons" 0
  # BAR's fog-of-war stripes (Fog Diagonal Lines GL4) find the ground in the map's G-buffer, which the engine only
  # clears with advanced map shading off (BAR's Lowest preset, the phone's): a full-screen pass every frame whose every
  # pixel is discarded. Off while the lobby's or the engine's setting is 0 (the lobby's copy is what the next game
  # gets), back to BAR's default when it is 1 again.
  adv=$(grep -o 'AdvMapShading = [01]' "$BAR/LuaMenu/Config/IGL_data.lua" 2>/dev/null | head -n 1)
  [ -n "$adv" ] || adv=$(grep -o '^AdvMapShading *= *[01]' "$BAR/springsettings.cfg" 2>/dev/null | head -n 1)
  if [ "${adv##* }" = 0 ]; then
    widget_order "Fog Diagonal Lines GL4" 0; touch "$BAR/.bardroid-fog-lines-off"
  elif [ -f "$BAR/.bardroid-fog-lines-off" ]; then
    widget_order "Fog Diagonal Lines GL4" ""; rm -f "$BAR/.bardroid-fog-lines-off"
  fi
  sed -i 's/^\([[:space:]]*screenSpaceShadows = \)[0-9.]*,/\10,/' "$BAR/LuaUI/Config/BYAR.lua"
  # (the widget saves its settings after its first game; until then there is nothing to set)
  if grep -q '\["Deferred rendering GL4"\] *= *{' "$BAR/LuaUI/Config/BYAR.lua"; then
    grep -q '^[[:space:]]*screenSpaceShadows = 0,' "$BAR/LuaUI/Config/BYAR.lua" \
      || layer_miss "lights' screen-space shadows: no screenSpaceShadows in LuaUI/Config/BYAR.lua"
  fi
fi
log "phone graphics: $(echo $PHONE_GFX); no bloom, SSAO, distortion, snow, map edge extension, lights, decals, AO plates, grass, order effects, sharpening, jammed-unit tint, reclaim fields, ecostats$([ -f "$BAR/.bardroid-fog-lines-off" ] && echo ", fog-of-war stripes (no advanced map shading)"); queued buildings near the camera only"

# BAR's interface scale for the screen the game starts on (Kailil: 2.0 on the Fold's cover screen; on the inner one 1.3
# until 2026-10-28, then 1.0: BAR's build menu takes no size of its own, its width follows this scale, "then we will
# just have to reduce the interface scale to 1.0 on unfolded"; bardroid_touch.lua switches it on fold/unfold). The
# app keeps the X screen size in bardroid_screen.txt.
scr="$BAR/LuaUI/Config/bardroid_screen.txt"
if [ -f "$scr" ] && read -r sw sh _ < "$scr" && [ "${sw:-0}" -gt 0 ] && [ "${sh:-0}" -gt 0 ]; then
  if [ "$sw" -gt "$sh" ]; then long=$sw short=$sh; else long=$sh short=$sw; fi
fi
# (not the floating window, 584x530: by the long side, as the cover screen at 70% render resolution is 1176x504)
if [ "${long:-0}" -ge 640 ]; then
  if [ $((long * 10)) -lt $((short * 16)) ]; then uis=1.0      # inner screen
  elif [ "$sw" -gt "$sh" ]; then uis=2.0                        # cover screen
  else uis=1.0; fi                                              # cover screen held upright: BAR scales by the tall side
  if grep -q '^ui_scale *=' "$BAR/springsettings.cfg"; then sed -i "s/^ui_scale *=.*/ui_scale = $uis/" "$BAR/springsettings.cfg"
  else echo "ui_scale = $uis" >> "$BAR/springsettings.cfg"; fi
  log "interface scale $uis (${sw}x${sh} screen)"
fi
# The top bar's button strip is laid out for wide screens: at 1.3 on the near-square inner screen it ran under the
# wind/tidal/commander counters. Its Keys (keyboard shortcuts) and Changes (patch notes) buttons are no use on a
# phone: their widgets off (also at 1.0), the rest has room.
if [ "$MODE" = skirmish ] || [ "$MODE" = lobby ] || [ "$MODE" = bench ]; then
  widget_order "Keybind/Mouse Info" 0; widget_order "Changelog Info" 0
  # BAR's Picture-in-Picture Minimap shows a row of buttons under the map whenever the pointer is over it, and every
  # touch puts the pointer there (Kailil: "useless and in the way even when they autohide"): the classic Minimap
  # widget instead (the PIP minimap switches it off while it runs)
  widget_order "Picture-in-Picture Minimap" 0; widget_order "Minimap" 1
  # BAR's Screen Mode Info prints its notice ("Screen mode: Resources ...", when a metal extractor is picked) at 21% of
  # the screen's height in the middle: on a phone's screen over the order menu, and over the app's PLACE while a
  # building waits (dev phone, 2026-11-03). The view itself (metal spots in green) is the engine's and stays.
  widget_order "Screen Mode Info" 0
  # BAR's unit info panel sizes its text by the interface scale but narrows the panel on wide screens: at 2.0 and 1.3
  # the stats ran under the unit picture and off the screen (Kailil: "too large and it is jumbled up"). The app's
  # bardroid_info.lua takes its place.
  widget_order "Info" 0
fi

# The app's benchmark (MODE=bench, Installer's bench.txt): BAR's "Benchmark BAR" scenario, unattended. BAR pauses a
# singleplayer game while its Mission Info window (the scenario's briefing) is open: off for benchmarks, BAR's own
# default otherwise; bardroid_bench.lua (by its flag file) resumes a paused start and quits after the results.
# A profiling run (tools/phone-bench.ps1 -Profile, the file .bardroid-bench-profile): BAR's Widget Profiler (LuaUI CPU
# per widget) or the gadget profiler (game logic CPU per gadget, "luarules profile") on, their tables caught by the
# benchmark's own screenshot at frame 2015.
prof=""
[ "${BARDROID_DEV:-0}" = 1 ] && prof=$(cat "$BAR/.bardroid-bench-profile" 2>/dev/null)
if [ "$MODE" = bench ]; then
  widget_order "Mission Info" 0; echo 1 > "$BAR/LuaUI/Config/bardroid_bench.txt"
  if [ "$prof" = widgets ]; then widget_order "Widget Profiler" 1; else widget_order "Widget Profiler" ""; fi
  [ "$prof" = gadgets ] && sed -i 's/|20:vsync 0|/|20:vsync 0|40:luarules profile|/' "$BAR/bench.txt"
  log "benchmark${prof:+, profiling $prof}"
  if [ "${BARDROID_DEV:-0}" = 1 ] && [ -s "$BAR/.bardroid-bench-settings" ]; then
    [ -f "$BAR/.springsettings.pre-bench" ] || cp "$BAR/springsettings.cfg" "$BAR/.springsettings.pre-bench"
    while IFS='=' read -r k v; do
      k=$(echo $k); v=$(echo $v); [ -n "$k" ] || continue
      if grep -q "^$k *=" "$BAR/springsettings.cfg"; then sed -i "s/^$k *=.*/$k = $v/" "$BAR/springsettings.cfg"
      else echo "$k = $v" >> "$BAR/springsettings.cfg"; fi
    done < "$BAR/.bardroid-bench-settings"
    log "benchmark settings: $(tr '\n' ' ' < "$BAR/.bardroid-bench-settings")"
  fi
else
  widget_order "Mission Info" ""; widget_order "Widget Profiler" ""; rm -f "$BAR/LuaUI/Config/bardroid_bench.txt"
fi

# The engine saves every key it read into springsettings.cfg at exit: the keys below that only some starts set, and the
# keys of a developer's dev-springsettings.cfg, would outlive the start that set them (a test's LogFlushLevel and
# profiling switch stayed on the dev phone after its file was gone). They go, and the lines the dev file covered come
# back, before this start adds its own.
sed -i -e '/^BarDroidPhoneLuaDir *=/d' -e '/^BarDroidGameWidgetsDir *=/d' "$BAR/springsettings.cfg" 2>/dev/null
DEV_KEYS="$BAR/.dev-springsettings-keys" DEV_ORIG="$BAR/.dev-springsettings-orig"
if [ -f "$DEV_KEYS" ]; then
  while read -r k; do [ -n "$k" ] && sed -i "/^$k *=/d" "$BAR/springsettings.cfg"; done < "$DEV_KEYS"
  cat "$DEV_ORIG" >> "$BAR/springsettings.cfg" 2>/dev/null
  rm -f "$DEV_KEYS" "$DEV_ORIG"
fi
# Sideways the touch dock too (the app's "Touch dock sideways", BARDROID_LAND_DOCK; layout A, bardroid_portrait.lua):
# this file while it is on
mkdir -p "$BAR/LuaUI/Config"
if [ "${BARDROID_LAND_DOCK:-0}" = 1 ]; then
  echo 1 > "$BAR/LuaUI/Config/bardroid_landdock.txt"
else
  rm -f "$BAR/LuaUI/Config/bardroid_landdock.txt"
fi
# Upright (the app's "Play upright", BARDROID_PORTRAIT): BAR's loading screen tip off, as BAR wraps it for a wide
# screen and upright it ran off both sides; the app shows one wrapped to the screen (GameActivity). The player's own
# line is kept in .bardroid-tips-line and put back at a start that is not upright; their tips off: none from the app
# either (.bardroid-no-tips).
TIPS_LINE="$BAR/.bardroid-tips-line"
if [ "${BARDROID_PORTRAIT:-0}" = 1 ]; then
  if [ ! -f "$TIPS_LINE" ]; then
    grep -E '^loadscreen_tips *=' "$BAR/springsettings.cfg" > "$TIPS_LINE" 2>/dev/null || : > "$TIPS_LINE"
  fi
  if grep -qE '= *0' "$TIPS_LINE"; then touch "$BAR/.bardroid-no-tips"; else rm -f "$BAR/.bardroid-no-tips"; fi
  sed -i '/^loadscreen_tips *=/d' "$BAR/springsettings.cfg"
  echo "loadscreen_tips = 0" >> "$BAR/springsettings.cfg"
elif [ -f "$TIPS_LINE" ]; then
  sed -i '/^loadscreen_tips *=/d' "$BAR/springsettings.cfg"
  cat "$TIPS_LINE" >> "$BAR/springsettings.cfg"
  rm -f "$TIPS_LINE" "$BAR/.bardroid-no-tips"
fi
# And the lobby's first picture (Kailil, 2026-11-10: "the BAR slash during the first load needs to zoom out so it can
# show the full word BAR ... feather the edges of the picture and have the background be the same Grey"): Chobby draws
# MenuLoadscreens/loadscreen.png as a 16:9 picture cut to the screen's shape, so upright only the middle quarter of its
# width showed, the word cut off. Upright the app's version is there instead (Installer's .bardroid-loadscreen-upright.png:
# the word scaled into that quarter on the picture's own grey); a picture already there is kept aside and put back at a
# start that is not upright.
LOADPIC="$BAR/MenuLoadscreens/loadscreen.png"
if [ "${BARDROID_PORTRAIT:-0}" = 1 ] && [ -f "$BAR/.bardroid-loadscreen-upright.png" ]; then
  mkdir -p "$BAR/MenuLoadscreens"
  if [ -f "$LOADPIC" ] && [ ! -f "$BAR/.bardroid-loadscreen-ours" ]; then mv -f "$LOADPIC" "$BAR/.bardroid-loadscreen-orig.png"; fi
  cp -f "$BAR/.bardroid-loadscreen-upright.png" "$LOADPIC" && touch "$BAR/.bardroid-loadscreen-ours"
elif [ -f "$BAR/.bardroid-loadscreen-ours" ]; then
  rm -f "$LOADPIC" "$BAR/.bardroid-loadscreen-ours"
  [ -f "$BAR/.bardroid-loadscreen-orig.png" ] && mv -f "$BAR/.bardroid-loadscreen-orig.png" "$LOADPIC"
  rmdir "$BAR/MenuLoadscreens" 2>/dev/null || :
fi
# BAR's load screen pictures upright (Kailil, 2026-11-10: the loading screens' pictures "natural on all aspect ratios"):
# BAR's load screen cuts its 16:9 pictures to the screen, upright a narrow strip of them. The app's versions (Installer's
# .bardroid-loadpictures-upright/, tools/make-loadpictures.ps1: the whole picture across the width, the same blurred
# above and below) go under BAR's names in the write folder, where the engine looks before the game (not synced: only
# what this phone draws); .bardroid-loadpictures-ours lists them, and a start that is not upright takes them away.
LP_OURS="$BAR/.bardroid-loadpictures-ours"
if [ "${BARDROID_PORTRAIT:-0}" = 1 ] && [ -d "$BAR/.bardroid-loadpictures-upright" ]; then
  : > "$LP_OURS"
  for f in "$BAR/.bardroid-loadpictures-upright/"*.jpg; do
    [ -f "$f" ] || continue
    rel=$(basename "$f" | sed 's/__/\//g')   # (manual__scavengers__x.jpg: manual/scavengers/x.jpg)
    mkdir -p "$BAR/bitmaps/loadpictures/$(dirname "$rel")"
    cp -f "$f" "$BAR/bitmaps/loadpictures/$rel" && echo "$rel" >> "$LP_OURS"
  done
elif [ -f "$LP_OURS" ]; then
  # (a line with "..", or from the root, is no picture of ours: the file is in the write folder, which the game's Lua can
  # write, and its lines are deleted; release overhaul item 9)
  while read -r rel; do
    case "$rel" in "" | /* | *..*) continue ;; esac
    rm -f "$BAR/bitmaps/loadpictures/$rel"
  done < "$LP_OURS"
  rmdir "$BAR/bitmaps/loadpictures/manual/scavengers" "$BAR/bitmaps/loadpictures/manual" "$BAR/bitmaps/loadpictures" 2>/dev/null || :
  rm -f "$LP_OURS"
fi
# The engine's splash in this screen's shape (GameService made it: SplashPicture): the engine stretches its splash over
# the screen, and Recoil's 16:9 logo came out of shape upright and on the folded Fold7's wide side. SplashScreenDir by
# its absolute path (relative, it is the engine's own folder, which has none: the logo in base/). The player's line is
# kept in .bardroid-splash-line and put back once the picture is gone.
SPLASH_LINE="$BAR/.bardroid-splash-line"
if [ -f "$BAR/bardroid-splash/splash.png" ]; then
  [ -f "$SPLASH_LINE" ] || { grep -E '^SplashScreenDir *=' "$BAR/springsettings.cfg" > "$SPLASH_LINE" 2>/dev/null || : > "$SPLASH_LINE"; }
  sed -i '/^SplashScreenDir *=/d' "$BAR/springsettings.cfg"
  echo "SplashScreenDir = $BAR/bardroid-splash" >> "$BAR/springsettings.cfg"
elif [ -f "$SPLASH_LINE" ]; then
  sed -i '/^SplashScreenDir *=/d' "$BAR/springsettings.cfg"
  cat "$SPLASH_LINE" >> "$BAR/springsettings.cfg"
  rm -f "$SPLASH_LINE"
fi
# The phone engine (docs/ENGINE-DEFAULT.md; Kailil, 2026-11-13: "1. You're recommendation 2. Inside the apk 3. Yes"):
# the engine branch's build of this engine version, carried in the APK and set up beside BAR's official one
# (Installer.installPhoneEngine: its spring, the official folder's other files linked). It loads the app's widgets as
# the game's (BarDroidGameWidgetsDir: the touch dock, the pad, presets and the phone Settings in every game, whatever a
# host allows user widgets) and the phone versions of BAR's costliest Lua, both unsynced; its simulation rewrite runs in
# skirmishes and replays only, stock code online (the engine's BarDroidSimAllowed). The launcher's "Phone engine" off
# (BARDROID_PHONE_ENGINE=0): BAR's official engine, the app's widgets as user widgets. A build that failed to run at all
# waits until the app brings another (.bardroid-phone-failed). dev-env.sh, read next, may still name another engine.
PHONE_ENGINE="$ENGINE-phone"
PHONE_BUILD=$(head -n 1 "$PHONE_ENGINE/BUILD.txt" 2>/dev/null)
PHONE_FIRST=0
if [ "${BARDROID_PHONE_ENGINE:-1}" != 1 ]; then
  log "BAR's official engine $ENGINE_VER (the launcher's Phone engine is off)"
elif [ ! -x "$PHONE_ENGINE/spring" ] || [ -z "$PHONE_BUILD" ]; then
  log "BAR's official engine $ENGINE_VER (this app has no phone build of it)"
elif [ "$(cat "$BAR/.bardroid-phone-failed" 2>/dev/null)" = "$PHONE_BUILD" ]; then
  log "!!! phone engine: $PHONE_BUILD could not run on this phone; BAR's official engine until the app brings another build"
else
  ENGINE="$PHONE_ENGINE"
  [ "$(cat "$BAR/.bardroid-phone-ok" 2>/dev/null)" = "$PHONE_BUILD" ] || PHONE_FIRST=1
  log "phone engine: $PHONE_BUILD$([ "$PHONE_FIRST" = 1 ] && echo ' (not yet proven on this phone)')"
fi
# Developer overrides, never created by the app: extra environment, extra springsettings lines (later keys win). Only in a
# developer's (debuggable) build, BARDROID_DEV=1 from GameService: $BAR is the engine's write folder, which BAR's Lua can
# write, and a dev-env.sh there runs here as a shell script (2026-11-21)
if [ "${BARDROID_DEV:-0}" = 1 ]; then
  [ -f "$BAR/dev-env.sh" ] && . "$BAR/dev-env.sh" && log "applied $BAR/dev-env.sh"
elif [ -f "$BAR/dev-env.sh" ] || [ -f "$BAR/dev-springsettings.cfg" ]; then
  log "!!! dev-env.sh or dev-springsettings.cfg in the write folder: ignored (a release build)"
fi
# (the phone engine's defaults, unless dev-env.sh set its own)
if [ "$ENGINE" = "$PHONE_ENGINE" ]; then
  BARDROID_GAME_WIDGETS=${BARDROID_GAME_WIDGETS:-1}
  BARDROID_PHONE_LUA=${BARDROID_PHONE_LUA:-1}
fi
if [ "${BARDROID_DEV:-0}" = 1 ] && [ -f "$BAR/dev-springsettings.cfg" ]; then
  sed -n 's/^ *\([A-Za-z0-9_]*\) *=.*/\1/p' "$BAR/dev-springsettings.cfg" > "$DEV_KEYS"
  : > "$DEV_ORIG"
  while read -r k; do [ -n "$k" ] && grep "^$k *=" "$BAR/springsettings.cfg" >> "$DEV_ORIG"; done < "$DEV_KEYS"
  cat "$BAR/dev-springsettings.cfg" >> "$BAR/springsettings.cfg" && log "appended dev-springsettings.cfg (until a start without it)"
fi
# The app's Settings: BAR's Options laid out for a phone, upright and sideways (bardroid_options.lua, tools/make-options.py;
# Kailil, 2026-11-13: "Fully rebuild the settings menu to fit mobile", by "The engine rebuild/patch method"). Only with
# the app's widgets as the game's (below): as a user widget it would lack the widget handler Options needs (BAR's
# sandbox), so otherwise it waits in bardroid-parked and BAR's own Options runs. In BAR's place through its GetInfo
# replaces; a copy BAR removed in the last game gives way to BAR's own for that BAR file, as the menu copies do.
PARKED="$BAR/bardroid-parked"
options_copy() {
  w="$BAR/LuaUI/Widgets/bardroid_options.lua"
  mkdir -p "$PARKED"
  if [ -f "$w" ]; then rm -f "$PARKED/bardroid_options.lua"   # (a newer one from the app: that one)
  elif [ -f "$PARKED/bardroid_options.lua" ]; then mv -f "$PARKED/bardroid_options.lua" "$w"; fi
  [ -f "$w" ] || return
  if [ "${BARDROID_GAME_WIDGETS:-0}" != 1 ]; then
    mv -f "$w" "$PARKED/bardroid_options.lua"
    widget_order "BAR Droid settings" ""
    return
  fi
  copied=$(sed -n 's/^-- BARDROID_OPTIONS_FROM //p' "$w" 2>/dev/null)
  bars=$(cat "$BAR/.bardroid-options" 2>/dev/null)
  if [ -z "$copied" ] || copy_failed 'BAR Droid settings' "$BAR/.bardroid-options-failed" "$bars" "$w"; then
    mv -f "$w" "$PARKED/bardroid_options.lua"
    widget_order "BAR Droid settings" ""
    layer_miss "settings: the app's copy (made from ${copied:-?}) failed on BAR's gui_options.lua ${bars:-not found}: BAR's own, too wide upright, until the copy is made again (tools/make-options.py)"
    return
  fi
  # (BAR's own at its default: the copy's GetInfo replaces keeps it off while the copy runs, and BAR's handler saves it
  # at 0 then; a copy that stands down in an older release's replay, without its model, must leave BAR's own on)
  widget_order "Options" ""
  if [ "$copied" = "$bars" ]; then
    log "settings: the app's copy of BAR's Options (gui_options.lua $copied), laid out for the phone"
  else
    layer_miss "settings: BAR's gui_options.lua is ${bars:-not found}, the app's copy was made from $copied and could not be made again: the old copy runs (tools/make-options.py)"
  fi
}
options_copy
if [ "${BARDROID_GAME_WIDGETS:-0}" = 1 ]; then   # (above: the app's widgets as the game's)
  app_widgets_to "$BAR/LuaUI/Widgets" "$GAME_WIDGETS"
  printf 'BarDroidGameWidgetsDir = bardroid-ui\n' >> "$BAR/springsettings.cfg"
  mkdir -p "$BAR/LuaUI/Config" && : > "$BAR/LuaUI/Config/bardroid_game_widgets.txt"   # (no warnings: they do not apply)
  log "the app's widgets as the game's: $(ls "$GAME_WIDGETS" | grep -c '\.lua$') in bardroid-ui/LuaUI/Widgets (BarDroidGameWidgetsDir)"
fi
# Phone versions of BAR's costliest widgets and of its gadgets' unsynced halves (BARDROID_PHONE_LUA=1 in dev-env.sh, with
# an engine-branch build that has BarDroidPhoneLuaDir, docs/ENGINE-SIM.md "BAR's Lua on phones"): patches to BAR's own
# files in bardroid-phone/ (Installer), which that engine applies as LuaUI and the unsynced LuaRules state load them, all
# of a file's or none (then BAR's file as it is: the infolog's "[BarDroid] phone version of" lines say which). The synced
# game never sees them.
if [ "${BARDROID_PHONE_LUA:-0}" = 1 ]; then
  printf 'BarDroidPhoneLuaDir = bardroid-phone\n' >> "$BAR/springsettings.cfg"
  log "phone versions of BAR's Lua: $(ls "$BAR/bardroid-phone/LuaUI/Widgets" "$BAR/bardroid-phone/LuaRules/Gadgets" 2>/dev/null | grep -c '\.patch$') patches in bardroid-phone (BarDroidPhoneLuaDir)"
fi
# (what the engine gets, after dev-env.sh: the UBWC default above, or a developer's own flags)
[ "$GPU" = kgsl ] && log "Freedreno flags: FD_MESA_DEBUG=${FD_MESA_DEBUG:-none}"

# The engine's threads allowed on every CPU of the app's cpuset. The dev phone (Samsung) starts it on a CPU mask without
# its fastest core (0x3f, 0x5f, ...: never core 7, from the engine's first log line on, while this shell has all 8; set
# from outside, and Android's own shell may not change it, the app's may), and the busy threads sat where the big
# cluster stayed idle. BAR's benchmark on the hot dev phone, alternating: game speed x0.53/0.54/0.53 as started,
# x0.67/0.70/0.64 with every CPU allowed (2026-11-04, engine branch docs/ENGINE-SIM.md). Scheduling only, nothing
# synced. Every 3 s, each engine thread not on every CPU gets them (read from its status first: no taskset where
# nothing is to do, a phone that allows all of them runs none). "Every CPU" is this shell's own mask, the app's
# cpuset: a fixed ff would never match on a phone with another number of CPUs or a smaller cpuset (a taskset for
# every thread every 3 s) and would take CPUs away on one with more than 8. Stopped when the engine has exited.
cpus_allowed() { # $1: a /proc status file -> its Cpus_allowed mask in $mask (no subshell: called for every thread)
  mask=""
  while read -r k v; do [ "$k" = "Cpus_allowed:" ] && { mask=$v; break; }; done 2>/dev/null < "$1" # (a thread that
  # exited meanwhile: no message in launcher.log, the stderr redirect before the file's)
}
# BARDROID_WORKER_CPUS (dev-env.sh only, an experiment, docs/ENGINE-SIM.md on engine/sim): the engine's pool workers
# ("worker1".."workerN") get that hex mask instead (the dev phone: 78, its A715/A710 cores), the other threads all.
widen_engine() {
  cpus_allowed /proc/self/status
  local all=$mask want comm
  [ -n "$all" ] || return
  while :; do
    sleep 3
    for p in $(pidof spring 2>/dev/null); do
      for t in /proc/$p/task/*; do
        cpus_allowed "$t/status"
        want=$all
        if [ -n "${BARDROID_WORKER_CPUS:-}" ]; then
          comm=; read -r comm 2>/dev/null < "$t/comm"
          case "$comm" in worker*) want=$BARDROID_WORKER_CPUS ;; esac
        fi
        [ -n "$mask" ] && [ "$mask" != "$want" ] && taskset -p "${want//,/}" "${t##*/}" >/dev/null 2>&1
      done
    done
  done
}
widen_engine &
widen=$!

# 4. Launch the engine.
cd "$ENGINE" || { log "engine dir missing: $ENGINE"; exit 11; }
ENGINE_STARTED=$(date +%s)
rm -f "$BAR/infolog.txt"
# (a phone build not yet proven here: proven once it has written its first lines, while it runs, so that a game the
# app or a swipe ends still counts; below, after the exit, the same test decides a build that never ran)
if [ "$PHONE_FIRST" = 1 ]; then
  ( for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      sleep 3
      grep -q '\[BarDroidSim\]' "$BAR/infolog.txt" 2>/dev/null && { echo "$PHONE_BUILD" > "$BAR/.bardroid-phone-ok"; break; }
    done ) &
fi
case "$MODE" in
  skirmish)
    log "spring skirmish: $BAR/skirmish.txt"
    LD_PRELOAD="${LD_PRELOAD:-$PRELOAD}" ./spring --isolation --write-dir "$BAR" "$BAR/skirmish.txt"; rc=$? ;;
  bench)
    # A replay benchmark (tools/phone-bench.ps1 -Replay): .bardroid-bench-replay says "<game second> <seconds> <replay
    # in demos/>"; bardroid_bench.lua fast-forwards to that second and measures the game's speed for that long.
    rep="$BAR/.bardroid-bench-replay"
    [ "${BARDROID_DEV:-0}" = 1 ] || rep="/nonexistent"   # (a developer's build only, as the benchmark's other files)
    # (a replay in demos/ itself: no "/" in its name, so no "..")
    if [ -s "$rep" ] && read -r skip secs file < "$rep" && [ -n "$file" ] && [ "$file" = "${file##*/}" ] \
        && [ -f "$BAR/demos/$file" ]; then
      echo "replay $skip $secs" > "$BAR/LuaUI/Config/bardroid_bench.txt"
      log "spring replay benchmark: demos/$file from game second $skip, $secs s"
      LD_PRELOAD="${LD_PRELOAD:-$PRELOAD}" ./spring --isolation --write-dir "$BAR" "$BAR/demos/$file"; rc=$?
    else
      [ -s "$rep" ] && log "replay benchmark: no demos/$(cut -d' ' -f3- "$rep"); BAR's benchmark instead"
      log "spring benchmark: $BAR/bench.txt"
      LD_PRELOAD="${LD_PRELOAD:-$PRELOAD}" ./spring --isolation --write-dir "$BAR" "$BAR/bench.txt"; rc=$?
    fi ;;
  lobby)
    # Written by BAR's launcher before every start (launcher config "json_files"); without it Chobby picks no game
    # config and shuts down (a black screen). The app's update check saves BAR's current one; the built-in copy is
    # the fallback.
    src="$BAR/.bardroid-chobby_config.json"
    if [ -f "$src" ] && grep -q '"game": *"[^"]*"' "$src"; then
      sed "s/\"game\": *\"[^\"]*\"/\"game\": \"$LOBBY_GAME\"/" "$src" > "$BAR/chobby_config.json"
    else
      [ -f "$src" ] && layer_miss "chobby_config.json: BAR's launcher config has no \"game\" key (built-in copy used)"
      printf '{"server": {"address": "server4.beyondallreason.info", "port": 8200, "protocol": "spring", "serverName": "BAR"}, "game": "%s"}\n' \
        "$LOBBY_GAME" > "$BAR/chobby_config.json"
    fi
    # Once: Chobby's "draw at full speed" on (active lobby 60 fps instead of 30). Its settings exist after the first
    # lobby run; later changes in the lobby's Settings stay the player's.
    if [ ! -f "$BAR/.bardroid-lobby-fullspeed" ] && [ -f "$BAR/LuaMenu/Config/IGL_data.lua" ]; then
      if grep -q 'drawAtFullSpeed = ' "$BAR/LuaMenu/Config/IGL_data.lua"; then
        sed -i 's/drawAtFullSpeed = false/drawAtFullSpeed = true/' "$BAR/LuaMenu/Config/IGL_data.lua" \
          && touch "$BAR/.bardroid-lobby-fullspeed" && log "lobby: draw at full speed"
      else
        layer_miss "lobby full speed: no drawAtFullSpeed in LuaMenu/Config/IGL_data.lua"
      fi
    fi
    # Every start (Kailil): Split Panel Mode "Always One" (panel_layout 3; 1 Autodetect, 2 Always Two; Kailil corrected
    # Autodetect to Always One, 2026-10-26) and interface scale 100% on both screens (Kailil, 2026-11-01: "default lobby
    # ui scale at 100"; the pad's Start toggles 100 and 130, bardroid_lobby_touch.lua; before: 120%, 135%, 150% unfolded
    # for a few hours). Chobby keeps the scale per window size (key vsx/500 x vsy/250) and falls back to 100% for a size
    # it has not saved; the Fold's two displays and every resolution scale differ, so each size up to 3000x3000 gets it.
    # Its saved settings exist after the first lobby run. One-line tables first: Chobby saves an empty one as "{}".
    igl="$BAR/LuaMenu/Config/IGL_data.lua"
    if [ -f "$igl" ]; then
      scales=""
      for x in 0 1 2 3 4 5; do for y in 0 1 2 3 4 5 6 7 8 9 10 11; do scales="$scales[\"${x}x$y\"] = 1.0, "; done; done
      sed -i -e '/^\t\tpanel_layout = /d' -e '/^\t\tuiScalesForScreenSizes = {.*}/d' \
        -e '/^\t\tuiScalesForScreenSizes = {$/,/^\t\t},*$/d' \
        -e "s/^\t\[\"Chili lobby\"\] *= *{$/&\n\t\tpanel_layout = 3,\n\t\tuiScalesForScreenSizes = { $scales},/" "$igl"
      if grep -q '^[[:space:]]*panel_layout = 3,' "$igl" && grep -q '\["4x3"\] = 1.0' "$igl" && grep -q '\["2x4"\] = 1.0' "$igl"; then
        log "lobby: split panels always one, interface scale 100%"
      else
        layer_miss "lobby panels and scale: no [\"Chili lobby\"] settings in LuaMenu/Config/IGL_data.lua"
      fi
      # Once: Chobby's "Do Not Disturb" on. A message naming the player (the host greets everyone who joins: "Hi
      # UnderarmCape! Current battle type is ...") or a private one switched the one-panel lobby to Chat, away from the
      # battle room just joined (Kailil, 2026-10-27). The chat tab still counts unread messages; later changes in the
      # lobby's Settings stay the player's.
      if [ ! -f "$BAR/.bardroid-lobby-dnd" ]; then
        if grep -q 'doNotDisturb = ' "$igl"; then
          sed -i 's/doNotDisturb = false/doNotDisturb = true/' "$igl" && touch "$BAR/.bardroid-lobby-dnd" && log "lobby: do not disturb"
        else
          layer_miss "lobby do not disturb: no doNotDisturb in LuaMenu/Config/IGL_data.lua"
        fi
      fi
    fi
    # Chobby's "Resolution limiter" shrinks the window to Spring.GetScreenGeometry() on every resize, but SDL keeps the
    # screen size it saw at startup: after a fold or unfold it fought the X server (which keeps the window at the screen
    # size, patch 0003) twice a second, toggling fullscreen each time (black flicker). 0 disables a LuaMenu widget.
    order="$BAR/LuaMenu/Config/IGL_order.lua"
    if [ -f "$order" ]; then
      sed -i 's/\["Resolution limiter"\] *= *[0-9]*/["Resolution limiter"] = 0/' "$order"
      grep -q '\["Resolution limiter"\]' "$order" || sed -i '0,/^return *{/s//&\n\t["Resolution limiter"] = 0,/' "$order"
      grep -q '\["Resolution limiter"\] = 0' "$order" || layer_miss "Resolution limiter not off in LuaMenu/Config/IGL_order.lua"
    else
      mkdir -p "$BAR/LuaMenu/Config" && printf 'return {\n\t["Resolution limiter"] = 0,\n}\n' > "$order"
    fi
    # Once: the lobby's Settings "Rapid Pool Cache" off. That widget reads all of the rapid pool (every BAR version in
    # it: 2.2 GB, 21817 files on the dev phone) when the lobby opens, 50 ms of every frame, whenever its first read is
    # under 80 MB/s, which through proot it is even with the files cached: the lobby at 13-15 fps instead of 30 for its
    # first ~30 s at every start, a 1.2 s freeze first (dev phone, 2026-11-11), for a page cache an 8 GB phone gives up
    # to the game. BAR's "Disable NonBar Widgets" starts it at every start whatever its order; bardroid_lobby_touch.lua
    # stops it again while this setting is off. Ticked again in the lobby's Settings: it runs.
    if [ ! -f "$BAR/.bardroid-lobby-nocache" ] && [ -f "$BAR/LuaMenu/Config/IGL_data.lua" ]; then
      if grep -q 'enableCacheRapidPool = ' "$BAR/LuaMenu/Config/IGL_data.lua"; then
        sed -i 's/enableCacheRapidPool = true/enableCacheRapidPool = false/' "$BAR/LuaMenu/Config/IGL_data.lua" \
          && touch "$BAR/.bardroid-lobby-nocache" && log "lobby: rapid pool cache off"
      else
        layer_miss "lobby rapid pool cache: no enableCacheRapidPool in LuaMenu/Config/IGL_data.lua"
      fi
    fi
    log "spring lobby: rapid://${LOBBY_TAG:-byar-chobby:test}"
    LD_PRELOAD="${LD_PRELOAD:-$PRELOAD}" ./spring --isolation --write-dir "$BAR" --menu "rapid://${LOBBY_TAG:-byar-chobby:test}"; rc=$? ;;
  shell)
    log "shell mode: sleeping; use the app log to inspect"; sleep 3600; rc=0 ;;
  *) log "unknown MODE=$MODE"; rc=2 ;;
esac
log "spring exited with $rc"
kill "$widen" 2>/dev/null
# A phone build until it has run once: an error exit before it wrote its first lines (the engine's [BarDroidSim] line,
# at once: a binary that does not run on this phone, a missing library) sets the build aside, BAR's official engine
# from the next start on. An engine that ran proves it, whatever ended it later (a missing map's error exit too).
if [ "$PHONE_FIRST" = 1 ] && [ "$ENGINE" = "$PHONE_ENGINE" ]; then
  if grep -q '\[BarDroidSim\]' "$BAR/infolog.txt" 2>/dev/null; then
    echo "$PHONE_BUILD" > "$BAR/.bardroid-phone-ok"
  elif [ "$rc" -ne 0 ]; then
    echo "$PHONE_BUILD" > "$BAR/.bardroid-phone-failed"
    log "!!! phone engine: $PHONE_BUILD exited with $rc after $(( $(date +%s) - ENGINE_STARTED )) s without running; BAR's official engine from the next start"
  fi
fi
# The app's widgets' faults in this run, BAR's handler's own lines only (read_faults), the first of each widget: by its
# file (bardroid_<x>.lua in "Error in <call-in>(): [string ".../bardroid_<x>.lua"]:..." and in "Failed to load:"), or by
# its name in a "Removed widget: BAR Droid ..." whose error line just before named no file of the app's (an error in
# BAR's code that it called). Every widget of the app's, the lobby's too, in one pass (13 greps of the infolog for 13
# widgets until 2026-11-21). The dev profiler's [simdraw] lines, which name every widget's timers ("W:VisibleUnitRemoved:
# BAR Droid touch"), are no handler line (three false launcher warnings, 2026-11-05).
app_widget_faults() {   # app_widget_faults: one "<file or name>|<line>" per widget, from FAULTS
  printf '%s\n' "$FAULTS" | awk '
    { key = "" }
    match($0, /bardroid_[A-Za-z0-9_]+\.lua/) { key = substr($0, RSTART, RLENGTH) }
    key == "" && index($0, "Removed widget: BAR Droid ") == 1 && !named { key = substr($0, 17) }
    key != "" && !seen[key]++ { print key "|" $0 }
    { named = key != "" && index($0, "Removed widget: ") != 1 }'
}
read_faults   # (this run's)
app_widget_faults | while IFS='|' read -r key line; do layer_miss "the app's widget $key: $line"; done
# A phone version of one of BAR's files (the phone engine's BarDroidPhoneLuaDir: assets/bardroid/phone-*.lua.patch) that
# no longer fits BAR's file after an update: the engine loaded BAR's own file instead ("[BarDroid] phone version of
# <file> (<state>): patch N finds no place: the game's own file loads"), so its fixes and savings are gone until the
# patch is made again (tools/phone-lua-check.py). A replay plays the BAR release it was recorded with, whose files may
# differ: not counted, as for the menu copies (copy_removed).
if [ "$REPLAY" = 0 ]; then
  grep -aE "^\[t=[^]]*\]\[f=-?[0-9]+\] \[BarDroid\] phone version of .*: the game's own file loads" "$BAR/infolog.txt" 2>/dev/null \
    | sed -e 's/^.*\[BarDroid\] phone version of //' -e 's/ ([^)]*): /: /' -e "s/: the game's own file loads\$//" | sort -u \
    | while read -r miss; do layer_miss "phone Lua: $miss, BAR's own file ran (assets/bardroid/phone-*.lua.patch)"; done
fi
cp -f "$BAR/infolog.txt" "$LOGS/infolog-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
# the newest 20 copies (one per engine run; a long game's is several MB, 23 of them were 19 MB)
ls -t "$LOGS"/infolog-*.txt 2>/dev/null | tail -n +21 | xargs -r rm -f
grep -E "GL version|GLSL version|GL4 support|S3TC|GL_VENDOR|GL_RENDERER|Video RAM|Error|error|OOM|Segmentation|desync" "$BAR/infolog.txt" 2>/dev/null | head -n 60
exit $rc
