#!/bin/bash
# BAR Droid — container-side game launcher. Env from the app: ENGINE_VER, MODE (skirmish|lobby|glcheck|shell),
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
# Never wait for vblank: with swap interval 0 the phone's Mesa (KGSL Present-fence path) keeps a third back buffer, so
# the CPU builds the next frame while the GPU draws the last. The frame cap is libbardroid_pace.so below instead of
# VSync (swap interval 2 left two buffers: the main thread waited for the GPU 43-58% of each frame, measured).
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
# Frame cap: sleeps after each buffer swap to BARDROID_FPS (from the app's 30/60 fps setting; 0 = none).
if [ "$(uname -m)" = aarch64 ] && [ -f "$BAR/libbardroid_pace.so" ]; then
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
  if grep -q "\[\"$1\"\] *= *-\?[0-9][0-9]*" "$f"; then
    if [ -n "$2" ]; then sed -i "s/\[\"$1\"\] *= *-\?[0-9][0-9]*/[\"$1\"] = $2/" "$f"
    else sed -i "/\[\"$1\"\] *= *-\?[0-9][0-9]*,\?[ \t]*$/d" "$f"; fi
  elif [ -n "$2" ]; then
    sed -i "0,/order *= *{/s//order = {\n\t\t[\"$1\"] = $2,/" "$f"
  fi
}
LOBBY_GAME=byar
if [ "$MODE" = skirmish ] || [ "$MODE" = lobby ]; then
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
  fi
  log "singleplayer game: $LOBBY_GAME"
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
    # Every start (Kailil): Split Panel Mode "Autodetect" (panel_layout 1) and interface scale 120%. Chobby keeps the
    # scale per window size (key vsx/500 x vsy/250) and falls back to 100% for a size it has not saved; the Fold's two
    # displays and every resolution scale differ, so each size up to 3000x3000 gets 1.2. Its saved settings exist after
    # the first lobby run. One-line tables first: Chobby saves an empty one as "{}".
    igl="$BAR/LuaMenu/Config/IGL_data.lua"
    if [ -f "$igl" ]; then
      scales=""
      for x in 0 1 2 3 4 5; do for y in 0 1 2 3 4 5 6 7 8 9 10 11; do scales="$scales[\"${x}x$y\"] = 1.2, "; done; done
      sed -i -e '/^\t\tpanel_layout = /d' -e '/^\t\tuiScalesForScreenSizes = {.*}/d' \
        -e '/^\t\tuiScalesForScreenSizes = {$/,/^\t\t},*$/d' \
        -e "s/^\t\[\"Chili lobby\"\] *= *{$/&\n\t\tpanel_layout = 1,\n\t\tuiScalesForScreenSizes = { $scales},/" "$igl"
      if grep -q '^[[:space:]]*panel_layout = 1,' "$igl" && grep -q '\["2x5"\] = 1.2' "$igl"; then
        log "lobby: split panels autodetect, interface scale 120%"
      else
        layer_miss "lobby panels and scale: no [\"Chili lobby\"] settings in LuaMenu/Config/IGL_data.lua"
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
cp -f "$BAR/infolog.txt" "$LOGS/infolog-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
grep -E "GL version|GLSL version|GL4 support|S3TC|GL_VENDOR|GL_RENDERER|Video RAM|Error|error|OOM|Segmentation|desync" "$BAR/infolog.txt" 2>/dev/null | head -n 60
exit $rc
