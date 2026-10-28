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
  printf '[general]\ndrivers = wave\nfrequency = 48000\nchannels = stereo\nsample-type = int16\nperiod_size = 512\n[wave]\nfile = /tmp/bardroid-audio.fifo\n' > /root/.alsoftrc
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
# released game). Switched off in the app (GAMEPAD_GAME=0): both go back.
widget_order() {   # widget_order <widget name> <order>, or "" to drop the entry (the widget's default)
  f="$BAR/LuaUI/Config/BYAR.lua"
  [ -f "$f" ] || { mkdir -p "$BAR/LuaUI/Config"; printf -- '-- Widget Custom data and order, order = 0 disabled widget\nreturn {\n\torder = {\n\t},\n}\n' > "$f"; }
  # the name as a regex and as replacement text ("Keybind/Mouse Info": a / would end the sed expression)
  re=$(printf '%s' "$1" | sed 's/[][\/.*^$]/\\&/g'); rep=$(printf '%s' "$1" | sed 's/[\/&]/\\&/g')
  if grep -q "\[\"$re\"\] *= *-\?[0-9][0-9]*" "$f"; then
    if [ -n "$2" ]; then sed -i "s/\[\"$re\"\] *= *-\?[0-9][0-9]*/[\"$rep\"] = $2/" "$f"
    else sed -i "/\[\"$re\"\] *= *-\?[0-9][0-9]*,\?[ \t]*$/d" "$f"; fi
  elif [ -n "$2" ]; then   # the top-level order table (one tab in, as BAR writes it), not a widget's "...order = {"
    sed -i "0,/^\torder *= *{/s//\torder = {\n\t\t[\"$rep\"] = $2,/" "$f"
  fi
  [ -z "$2" ] || grep -q "\[\"$re\"\] *= *$2," "$f" || layer_miss "widget order: \"$1\" = $2 not set in LuaUI/Config/BYAR.lua"
}
LOBBY_GAME=byar
if [ "$MODE" = skirmish ] || [ "$MODE" = lobby ] || [ "$MODE" = bench ]; then
  if [ "${GAMEPAD_GAME:-0}" = 1 ]; then
    LOBBY_GAME=byar-dev
    widget_order "Build menu" 165; widget_order "Grid menu" 0
    grep -q '\["Build menu"\] *= *165' "$BAR/LuaUI/Config/BYAR.lua" && grep -q '\["Grid menu"\] *= *0' "$BAR/LuaUI/Config/BYAR.lua" \
      || layer_miss "controller game: Build menu / Grid menu order not set in LuaUI/Config/BYAR.lua"
    touch "$BAR/.bardroid-gamepad-menus"
  elif [ -f "$BAR/.bardroid-gamepad-menus" ]; then
    widget_order "Build menu" ""; widget_order "Grid menu" ""
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
PHONE_GFX="MSAALevel=0 FSAA=0 Shadows=0 ShadowQuality=0 FeatureDrawDistance=6000 FeatureFadeDistance=4800 GroundDetail=60
  BumpWaterReflection=0 BumpWaterRefraction=0 GrassDetail=0 SmoothLines=0 SmoothPoints=0 CamMode=2
  VSync=0 VSyncGame=0 VSyncFraction=1 UnitIconFadeStart=1 UnitIconFadeVanish=1"
for kv in $PHONE_GFX; do
  k=${kv%%=*}; v=${kv#*=}
  if grep -q "^$k *=" "$BAR/springsettings.cfg"; then sed -i "s/^$k *=.*/$k = $v/" "$BAR/springsettings.cfg"
  else echo "$k = $v" >> "$BAR/springsettings.cfg"; fi
  [ -f "$BAR/LuaMenu/Config/IGL_data.lua" ] && sed -i "s/^\([[:space:]]*$k = \)[0-9.-]*,/\1$v,/" "$BAR/LuaMenu/Config/IGL_data.lua"
done
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

# BAR's interface scale for the screen the game starts on (Kailil: 2.0 on the Fold's cover screen, 1.3 on the inner
# one; bardroid_touch.lua switches it on fold/unfold). The app keeps the X screen size in bardroid_screen.txt.
scr="$BAR/LuaUI/Config/bardroid_screen.txt"
if [ -f "$scr" ] && read -r sw sh _ < "$scr" && [ "${sw:-0}" -gt 0 ] && [ "${sh:-0}" -gt 0 ]; then
  if [ "$sw" -gt "$sh" ]; then long=$sw short=$sh; else long=$sh short=$sw; fi
fi
# (not the floating window, 584x530: by the long side, as the cover screen at 70% render resolution is 1176x504)
if [ "${long:-0}" -ge 640 ]; then
  if [ $((long * 10)) -lt $((short * 16)) ]; then uis=1.3      # inner screen
  elif [ "$sw" -gt "$sh" ]; then uis=2.0                        # cover screen
  else uis=1.0; fi                                              # cover screen held upright: BAR scales by the tall side
  if grep -q '^ui_scale *=' "$BAR/springsettings.cfg"; then sed -i "s/^ui_scale *=.*/ui_scale = $uis/" "$BAR/springsettings.cfg"
  else echo "ui_scale = $uis" >> "$BAR/springsettings.cfg"; fi
  log "interface scale $uis (${sw}x${sh} screen)"
fi
# The top bar's button strip is laid out for wide screens: at 1.3 on the near-square inner screen it ran under the
# wind/tidal/commander counters. Its Keys (keyboard shortcuts) and Changes (patch notes) buttons are no use on a
# phone: their widgets off, the rest has room.
if [ "$MODE" = skirmish ] || [ "$MODE" = lobby ] || [ "$MODE" = bench ]; then
  widget_order "Keybind/Mouse Info" 0; widget_order "Changelog Info" 0
  # BAR's Picture-in-Picture Minimap shows a row of buttons under the map whenever the pointer is over it, and every
  # touch puts the pointer there (Kailil: "useless and in the way even when they autohide"): the classic Minimap
  # widget instead (the PIP minimap switches it off while it runs)
  widget_order "Picture-in-Picture Minimap" 0; widget_order "Minimap" 1
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

# Developer overrides, never created by the app: extra environment, extra springsettings lines (later keys win).
[ -f "$BAR/dev-env.sh" ] && . "$BAR/dev-env.sh" && log "applied $BAR/dev-env.sh"
[ -f "$BAR/dev-springsettings.cfg" ] && cat "$BAR/dev-springsettings.cfg" >> "$BAR/springsettings.cfg" && log "appended dev-springsettings.cfg"

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
    # Autodetect to Always One, 2026-10-26) and interface scale 120%. Chobby keeps the
    # scale per window size (key vsx/500 x vsy/250) and falls back to 100% for a size it has not saved; the Fold's two
    # displays and every resolution scale differ, so each size up to 3000x3000 gets 1.2. Its saved settings exist after
    # the first lobby run. One-line tables first: Chobby saves an empty one as "{}".
    igl="$BAR/LuaMenu/Config/IGL_data.lua"
    if [ -f "$igl" ]; then
      scales=""
      for x in 0 1 2 3 4 5; do for y in 0 1 2 3 4 5 6 7 8 9 10 11; do scales="$scales[\"${x}x$y\"] = 1.2, "; done; done
      sed -i -e '/^\t\tpanel_layout = /d' -e '/^\t\tuiScalesForScreenSizes = {.*}/d' \
        -e '/^\t\tuiScalesForScreenSizes = {$/,/^\t\t},*$/d' \
        -e "s/^\t\[\"Chili lobby\"\] *= *{$/&\n\t\tpanel_layout = 3,\n\t\tuiScalesForScreenSizes = { $scales},/" "$igl"
      if grep -q '^[[:space:]]*panel_layout = 3,' "$igl" && grep -q '\["2x5"\] = 1.2' "$igl"; then
        log "lobby: split panels always one, interface scale 120%"
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
touch_err=$(grep -iE 'bardroid_touch|BAR Droid touch' "$BAR/infolog.txt" 2>/dev/null | grep -iE 'error|fail|removed' | head -n 1)
[ -n "$touch_err" ] && layer_miss "touch widget (bardroid_touch.lua): $touch_err"
queue_err=$(grep -iE 'bardroid_queue|BAR Droid builder queue' "$BAR/infolog.txt" 2>/dev/null | grep -iE 'error|fail|removed' | head -n 1)
[ -n "$queue_err" ] && layer_miss "builder queue widget (bardroid_queue.lua): $queue_err"
chat_err=$(grep -iE 'bardroid_chat|BAR Droid chat' "$BAR/infolog.txt" 2>/dev/null | grep -iE 'error|fail|removed' | head -n 1)
[ -n "$chat_err" ] && layer_miss "chat widget (bardroid_chat.lua): $chat_err"
info_err=$(grep -iE 'bardroid_info|BAR Droid info' "$BAR/infolog.txt" 2>/dev/null | grep -iE 'error|fail|removed' | head -n 1)
[ -n "$info_err" ] && layer_miss "info panel widget (bardroid_info.lua): $info_err"
spec_err=$(grep -iE 'bardroid_spectate|BAR Droid spectate' "$BAR/infolog.txt" 2>/dev/null | grep -iE 'error|fail|removed' | head -n 1)
[ -n "$spec_err" ] && layer_miss "spectating widget (bardroid_spectate.lua): $spec_err"
cp -f "$BAR/infolog.txt" "$LOGS/infolog-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
# the newest 20 copies (one per engine run; a long game's is several MB, 23 of them were 19 MB)
ls -t "$LOGS"/infolog-*.txt 2>/dev/null | tail -n +21 | xargs -r rm -f
grep -E "GL version|GLSL version|GL4 support|S3TC|GL_VENDOR|GL_RENDERER|Video RAM|Error|error|OOM|Segmentation|desync" "$BAR/infolog.txt" 2>/dev/null | head -n 60
exit $rc
