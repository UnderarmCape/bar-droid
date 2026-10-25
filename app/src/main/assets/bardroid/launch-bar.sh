#!/bin/bash
# BAR Droid — container-side game launcher. Env from the app: ENGINE_VER, MODE (skirmish|lobby|glcheck|shell),
# BARDROID_GPU (kgsl|zink|llvmpipe) with the matching Mesa variables, MESA_GL_VERSION_OVERRIDE (optional),
# BARDROID_AUDIO (0/1), DISPLAY.
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
export vblank_mode="${vblank_mode:-3}"
export XCURSOR_SIZE=32
export SDL_VIDEODRIVER=x11
export SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR=0
export PRD_RAPID_REPO_MASTER="https://repos-cdn.beyondallreason.dev/repos.gz"
export PRD_HTTP_SEARCH_URL="https://files-cdn.beyondallreason.dev/find"
export PRD_RAPID_USE_STREAMER=false
export PRD_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
# AngelScript ARM64 call stub missing from the official arm64 BARb/CircuitAI build (see arm64-ai-fix/README.md).
[ "$(uname -m)" = aarch64 ] && [ -f "$BAR/libasarm64.so" ] && export LD_PRELOAD="$BAR/libasarm64.so"

log() { echo "[launch] $*"; }

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
    # config and shuts down (a black screen).
    printf '%s\n' '{"server": {"address": "server4.beyondallreason.info", "port": 8200, "protocol": "spring", "serverName": "BAR"}, "game": "byar"}' \
      > "$BAR/chobby_config.json"
    log "spring lobby: rapid://${LOBBY_TAG:-byar-chobby:test}"
    ./spring --isolation --write-dir "$BAR" --menu "rapid://${LOBBY_TAG:-byar-chobby:test}"; rc=$? ;;
  shell)
    log "shell mode: sleeping; use the app log to inspect"; sleep 3600; rc=0 ;;
  *) log "unknown MODE=$MODE"; rc=2 ;;
esac
log "spring exited with $rc"
cp -f "$BAR/infolog.txt" "$LOGS/infolog-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
grep -E "GL version|GLSL version|GL4 support|S3TC|GL_VENDOR|GL_RENDERER|Video RAM|Error|error|OOM|Segmentation|desync" "$BAR/infolog.txt" 2>/dev/null | head -n 60
exit $rc
