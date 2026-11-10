#!/bin/bash
# BAR Droid — container-side game launcher. Env from the app: ENGINE_VER, MODE (skirmish|lobby|bench|glcheck|shell),
# BARDROID_GPU (kgsl|zink|llvmpipe) with the matching Mesa variables, MESA_GL_VERSION_OVERRIDE (optional),
# BARDROID_AUDIO (0/1), GAMEPAD_GAME (0/1: singleplayer plays the controller game), BARDROID_FPS (frame cap), DISPLAY.
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
# AngelScript ARM64 call stub missing from the official arm64 BARb/CircuitAI build (see arm64-ai-fix/README.md).
[ "$(uname -m)" = aarch64 ] && [ -f "$BAR/libasarm64.so" ] && export LD_PRELOAD="$BAR/libasarm64.so"
# Frame cap: sleeps after each buffer swap to BARDROID_FPS (from the app's 30/60 fps setting; 0 = none), and the
# hidden window (screen off, catching up). The emulator build's x86_64 copy (no cap, no Present-fence answer).
if [ -f "$BAR/libbardroid_pace.so" ]; then
  export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}$BAR/libbardroid_pace.so" BARDROID_FPS="${BARDROID_FPS:-30}"
  # New textures start as zeros: Mesa's recycled GPU buffers hold old pictures, which BAR's panels showed as noise.
  [ "$(uname -m)" = aarch64 ] && export BARDROID_TEX_ZERO=1
fi

log() { echo "[launch] $*"; }
# Android layer (docs/UPDATES.md): a tweak of BAR's files that no longer finds its target is never skipped silently.
# The app reads the list after the engine exits and shows it in the launcher.
: > "$LOGS/android-layer.txt"
layer_miss() { log "!!! ANDROID LAYER: $* -- BAR changed this; fix launch-bar.sh"; echo "$*" >> "$LOGS/android-layer.txt"; }

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
#    sound every time the engine's audio callback was late.)
pulseaudio --kill >/dev/null 2>&1 || true   # left over from an older BAR Droid
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

# Kailil's controller game (v0.8.5 as BAR's developer game, games/BAR-gamepad.sdd) for singleplayer, set up the way
# its Windows installer does: the lobby's singleplayer game is "Beyond All Reason Dev" (Chobby's byar-dev config), and
# BAR's Build menu replaces the Grid menu, which v0.8.5 does not drive (LuaUI/Config/BYAR.lua, shared with BAR's
# released game). In the controller game that is v0.8.5's own ("Build menu (controller)": tools/build-gamepad-game.py
# renames it), in BAR's released game the app's copy of BAR's Build menu, sized with the layout editor (Kailil,
# 2026-10-28: "just rebuild the exact same one with the ability for us to resize it freely"; bardroid_buildmenu.lua,
# tools/make-buildmenu.py), while BAR's file is still the one it was copied from (Installer writes that file's md5 to
# .bardroid-buildmenu), else BAR's own. Switched off in the app (GAMEPAD_GAME=0): BAR's defaults again.
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
copy_removed() {   # copy_removed <widget name>: BAR removed it in the last run, and that run was not a replay
  grep -aq "Removed widget: $1" "$BAR/infolog.txt" 2>/dev/null && ! grep -aq 'PreGame::ReadDataFromDemo' "$BAR/infolog.txt" 2>/dev/null
}
build_menu() {
  copied=$(sed -n 's/^-- BARDROID_BUILDMENU_FROM //p' "$BAR/LuaUI/Widgets/bardroid_buildmenu.lua" 2>/dev/null)
  bars=$(cat "$BAR/.bardroid-buildmenu" 2>/dev/null)
  failed="$BAR/.bardroid-buildmenu-failed"
  copy_removed 'BAR Droid build menu' && printf '%s game\n' "$bars" > "$failed"
  if [ -z "$copied" ] || { [ -f "$failed" ] && [ "$(cat "$failed")" = "$bars game" ]; }; then
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
# "behave like offline": the orders the pad leaves fill the menu, as in the controller game's; bardroid_ordermenu.lua,
# tools/make-ordermenu.py). It stands down in the controller game, which keeps v0.8.5's ("Order menu (controller)").
order_menu() {
  copied=$(sed -n 's/^-- BARDROID_ORDERMENU_FROM //p' "$BAR/LuaUI/Widgets/bardroid_ordermenu.lua" 2>/dev/null)
  bars=$(cat "$BAR/.bardroid-ordermenu" 2>/dev/null)
  failed="$BAR/.bardroid-ordermenu-failed"
  copy_removed 'BAR Droid order menu' && printf '%s game\n' "$bars" > "$failed"
  if [ -z "$copied" ] || { [ -f "$failed" ] && [ "$(cat "$failed")" = "$bars game" ]; }; then
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
  copy_removed 'BAR Droid mission info' && printf '%s game\n' "$bars" > "$failed"
  if [ -z "$copied" ] || { [ -f "$failed" ] && [ "$(cat "$failed")" = "$bars game" ]; }; then
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
# The app's widgets as the game's (BARDROID_GAME_WIDGETS=1 in dev-env.sh, with an engine-branch build that has
# BarDroidGameWidgetsDir, docs/ENGINE-SIM.md "The app's widgets as the game's"; Kailil, 2026-11-06, on a BAR developer's
# advice: they are the phone's mouse and keyboard, not unit-control widgets): they move to $GAME_WIDGETS, which that
# engine shows LuaUI as part of the game archive, so BAR loads them as game widgets. Back in LuaUI/Widgets first, as
# every start finds them (Installer puts new ones there: a newer one there wins), and moved again after dev-env.sh.
APP_WIDGETS="bardroid_touch bardroid_queue bardroid_chat bardroid_info bardroid_players bardroid_bench bardroid_spectate
  bardroid_minimap bardroid_layout bardroid_buildmenu bardroid_ordermenu bardroid_pad bardroid_padspeed bardroid_padfp
  bardroid_lowmem bardroid_buildrange bardroid_sensors bardroid_nano bardroid_portrait bardroid_missioninfo bardroid_retreat
  bardroid_presets bardroid_automex"
GAME_WIDGETS="$BAR/bardroid-ui/LuaUI/Widgets"
app_widgets_to() { # app_widgets_to <from dir> <to dir>: the app's widgets moved; one already there stays (the newer)
  mkdir -p "$2"
  for w in $APP_WIDGETS; do
    [ -f "$1/$w.lua" ] || continue
    if [ -f "$2/$w.lua" ] && [ "$2" = "$BAR/LuaUI/Widgets" ]; then rm -f "$1/$w.lua"; else mv -f "$1/$w.lua" "$2/$w.lua"; fi
  done
}
[ -d "$GAME_WIDGETS" ] && app_widgets_to "$GAME_WIDGETS" "$BAR/LuaUI/Widgets"
rm -f "$BAR/LuaUI/Config/bardroid_game_widgets.txt"   # (the lobby's warnings about a host's widget options: shown)

LOBBY_GAME=byar
if [ "$MODE" = skirmish ] || [ "$MODE" = lobby ] || [ "$MODE" = bench ]; then
  widget_order "Grid menu" 0
  build_menu
  order_menu
  mission_info
  if [ "${GAMEPAD_GAME:-0}" = 1 ]; then
    LOBBY_GAME=byar-dev
    widget_order "Build menu (controller)" 165
    widget_order "Order menu (controller)" 189
    grep -q '\["Build menu (controller)"\] *= *165' "$BAR/LuaUI/Config/BYAR.lua" && grep -q '\["Grid menu"\] *= *0' "$BAR/LuaUI/Config/BYAR.lua" \
      && grep -q '\["Order menu (controller)"\] *= *189' "$BAR/LuaUI/Config/BYAR.lua" \
      || layer_miss "controller game: Build menu (controller) / Order menu (controller) / Grid menu order not set in LuaUI/Config/BYAR.lua"
    touch "$BAR/.bardroid-gamepad-menus"
  elif [ -f "$BAR/.bardroid-gamepad-menus" ]; then
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
  log "singleplayer game: $LOBBY_GAME"
fi

# A benchmark's own engine settings (tools/phone-bench.ps1 -Settings, the file .bardroid-bench-settings: key = value
# lines) change springsettings.cfg for that run only: the file as it was before goes back at the next start, before
# anything else here touches it (and phone-bench.ps1 puts it back after its run).
if [ -f "$BAR/.springsettings.pre-bench" ]; then
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
#   cus2 0                 BAR's GL4 unit shaders off (BAR's cus_gl4.lua): the engine's plainer unit shading; the
#                          controller game would switch them back on, which bardroid_lowmem.lua (BarDroidLowMemory)
#                          prevents
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
prof=$(cat "$BAR/.bardroid-bench-profile" 2>/dev/null)
if [ "$MODE" = bench ]; then
  widget_order "Mission Info" 0; echo 1 > "$BAR/LuaUI/Config/bardroid_bench.txt"
  if [ "$prof" = widgets ]; then widget_order "Widget Profiler" 1; else widget_order "Widget Profiler" ""; fi
  [ "$prof" = gadgets ] && sed -i 's/|20:vsync 0|/|20:vsync 0|40:luarules profile|/' "$BAR/bench.txt"
  log "benchmark${prof:+, profiling $prof}"
  if [ -s "$BAR/.bardroid-bench-settings" ]; then
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
  while read -r rel; do [ -n "$rel" ] && rm -f "$BAR/bitmaps/loadpictures/$rel"; done < "$LP_OURS"
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
# Developer overrides, never created by the app: extra environment, extra springsettings lines (later keys win).
[ -f "$BAR/dev-env.sh" ] && . "$BAR/dev-env.sh" && log "applied $BAR/dev-env.sh"
if [ -f "$BAR/dev-springsettings.cfg" ]; then
  sed -n 's/^ *\([A-Za-z0-9_]*\) *=.*/\1/p' "$BAR/dev-springsettings.cfg" > "$DEV_KEYS"
  : > "$DEV_ORIG"
  while read -r k; do [ -n "$k" ] && grep "^$k *=" "$BAR/springsettings.cfg" >> "$DEV_ORIG"; done < "$DEV_KEYS"
  cat "$BAR/dev-springsettings.cfg" >> "$BAR/springsettings.cfg" && log "appended dev-springsettings.cfg (until a start without it)"
fi
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
rm -f "$BAR/infolog.txt"
case "$MODE" in
  skirmish)
    log "spring skirmish: $BAR/skirmish.txt"
    ./spring --isolation --write-dir "$BAR" "$BAR/skirmish.txt"; rc=$? ;;
  bench)
    # A replay benchmark (tools/phone-bench.ps1 -Replay): .bardroid-bench-replay says "<game second> <seconds> <replay
    # in demos/>"; bardroid_bench.lua fast-forwards to that second and measures the game's speed for that long.
    rep="$BAR/.bardroid-bench-replay"
    if [ -s "$rep" ] && read -r skip secs file < "$rep" && [ -f "$BAR/demos/$file" ]; then
      echo "replay $skip $secs" > "$BAR/LuaUI/Config/bardroid_bench.txt"
      log "spring replay benchmark: demos/$file from game second $skip, $secs s"
      ./spring --isolation --write-dir "$BAR" "$BAR/demos/$file"; rc=$?
    else
      [ -s "$rep" ] && log "replay benchmark: no demos/$(cut -d' ' -f3- "$rep"); BAR's benchmark instead"
      log "spring benchmark: $BAR/bench.txt"
      ./spring --isolation --write-dir "$BAR" "$BAR/bench.txt"; rc=$?
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
    log "spring lobby: rapid://${LOBBY_TAG:-byar-chobby:test}"
    ./spring --isolation --write-dir "$BAR" --menu "rapid://${LOBBY_TAG:-byar-chobby:test}"; rc=$? ;;
  shell)
    log "shell mode: sleeping; use the app log to inspect"; sleep 3600; rc=0 ;;
  *) log "unknown MODE=$MODE"; rc=2 ;;
esac
log "spring exited with $rc"
kill "$widen" 2>/dev/null
# an error line of one of the app's widgets (the dev profiler's [simdraw] lines name every widget's timers, such as
# W:VisibleUnitRemoved:BAR Droid touch: not errors; three false warnings in the launcher, 2026-11-05)
widget_error() { grep -iE "$1" "$BAR/infolog.txt" 2>/dev/null | grep -v '\[simdraw\]' | grep -iE 'error|fail|removed' | head -n 1; }
touch_err=$(widget_error 'bardroid_touch|BAR Droid touch')
[ -n "$touch_err" ] && layer_miss "touch widget (bardroid_touch.lua): $touch_err"
queue_err=$(widget_error 'bardroid_queue|BAR Droid builder queue')
[ -n "$queue_err" ] && layer_miss "builder queue widget (bardroid_queue.lua): $queue_err"
chat_err=$(widget_error 'bardroid_chat|BAR Droid chat')
[ -n "$chat_err" ] && layer_miss "chat widget (bardroid_chat.lua): $chat_err"
info_err=$(widget_error 'bardroid_info|BAR Droid info')
[ -n "$info_err" ] && layer_miss "info panel widget (bardroid_info.lua): $info_err"
spec_err=$(widget_error 'bardroid_spectate|BAR Droid spectate')
[ -n "$spec_err" ] && layer_miss "spectating widget (bardroid_spectate.lua): $spec_err"
range_err=$(widget_error 'bardroid_buildrange|BAR Droid build ranges')
[ -n "$range_err" ] && layer_miss "build ranges widget (bardroid_buildrange.lua): $range_err"
sensors_err=$(widget_error 'bardroid_sensors|BAR Droid sensor ranges')
[ -n "$sensors_err" ] && layer_miss "sensor ranges widget (bardroid_sensors.lua): $sensors_err"
nano_err=$(widget_error 'bardroid_nano|BAR Droid nano spray')
[ -n "$nano_err" ] && layer_miss "nano spray widget (bardroid_nano.lua): $nano_err"
retreat_err=$(widget_error 'bardroid_retreat|BAR Droid retreat')
[ -n "$retreat_err" ] && layer_miss "retreat widget (bardroid_retreat.lua): $retreat_err"
presets_err=$(widget_error 'bardroid_presets|BAR Droid presets')
[ -n "$presets_err" ] && layer_miss "presets widget (bardroid_presets.lua): $presets_err"
automex_err=$(widget_error 'bardroid_automex|BAR Droid auto mex')
[ -n "$automex_err" ] && layer_miss "auto mex widget (bardroid_automex.lua): $automex_err"
cp -f "$BAR/infolog.txt" "$LOGS/infolog-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
# the newest 20 copies (one per engine run; a long game's is several MB, 23 of them were 19 MB)
ls -t "$LOGS"/infolog-*.txt 2>/dev/null | tail -n +21 | xargs -r rm -f
grep -E "GL version|GLSL version|GL4 support|S3TC|GL_VENDOR|GL_RENDERER|Video RAM|Error|error|OOM|Segmentation|desync" "$BAR/infolog.txt" 2>/dev/null | head -n 60
exit $rc
