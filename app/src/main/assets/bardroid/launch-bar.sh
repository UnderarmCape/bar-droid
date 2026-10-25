#!/bin/bash
# BAR Droid — container-side game launcher. Env from the app: ENGINE_VER, MODE (skirmish|lobby|glcheck|shell),
# MESA_LOADER_DRIVER_OVERRIDE, MESA_GL_VERSION_OVERRIDE (optional), BARDROID_AUDIO (0/1), DISPLAY.
set -u
BAR=/root/bar
ENGINE="$BAR/engine/recoil_${ENGINE_VER:?}"
LOGS="$BAR/logs"; mkdir -p "$LOGS"
MODE="${MODE:-skirmish}"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR=/tmp
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-kgsl}"
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
[ -f "$BAR/libasarm64.so" ] && export LD_PRELOAD="$BAR/libasarm64.so"

log() { echo "[launch] $*"; }

# 1. Wait for the X server socket (the app starts it right before us).
for i in $(seq 1 100); do
  [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] && break
  sleep 0.2
done
if [ ! -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then log "X socket /tmp/.X11-unix/X${DISPLAY#:} never appeared"; exit 10; fi
log "X socket present"

# 2. Audio: PulseAudio inside the container writing raw PCM to a FIFO that the app plays through AudioTrack.
if [ "${BARDROID_AUDIO:-1}" = "1" ]; then
  mkdir -p /tmp/pulse
  [ -p /tmp/bardroid-audio.fifo ] || mkfifo /tmp/bardroid-audio.fifo 2>/dev/null || true
  pulseaudio --kill >/dev/null 2>&1 || true
  pulseaudio --daemonize=yes --exit-idle-time=-1 --disallow-exit --disallow-module-loading=0 \
    --log-target=file:/tmp/pulse/pulse.log --realtime=no --high-priority=no \
    -L "module-pipe-sink file=/tmp/bardroid-audio.fifo format=s16le rate=48000 channels=2 sink_name=bardroid" \
    -L "module-native-protocol-unix socket=/tmp/pulse/native auth-anonymous=1" \
    -n 2>/dev/null \
    && export PULSE_SERVER=unix:/tmp/pulse/native \
    || log "pulseaudio failed to start; continuing without sound"
fi

# 3. One-time GL probe, saved for the findings/bug reports.
if [ "$MODE" = "glcheck" ] || [ ! -f "$LOGS/glcheck-$MESA_LOADER_DRIVER_OVERRIDE.txt" ]; then
  {
    echo "driver=$MESA_LOADER_DRIVER_OVERRIDE gl_override=${MESA_GL_VERSION_OVERRIDE:-none} date=$(date)"
    glxinfo -B 2>&1
    echo "--- extensions of interest"
    for e in GL_EXT_texture_compression_s3tc GL_ARB_multi_draw_indirect GL_ARB_shader_storage_buffer_object \
             GL_ARB_uniform_buffer_object GL_ARB_buffer_storage GL_ARB_clip_control GL_ARB_texture_compression_bptc \
             GL_ARB_explicit_attrib_location GL_ARB_compute_shader; do
      glxinfo 2>/dev/null | grep -q "$e" && echo "yes $e" || echo "NO  $e"
    done
    echo "--- vulkan"; vulkaninfo --summary 2>&1 | grep -E "deviceName|apiVersion|driverName" | head -n 6
  } > "$LOGS/glcheck-$MESA_LOADER_DRIVER_OVERRIDE.txt" 2>&1
  cat "$LOGS/glcheck-$MESA_LOADER_DRIVER_OVERRIDE.txt"
  [ "$MODE" = "glcheck" ] && exit 0
fi

# 4. Launch the engine.
cd "$ENGINE" || { log "engine dir missing: $ENGINE"; exit 11; }
rm -f "$BAR/infolog.txt"
case "$MODE" in
  skirmish)
    log "spring skirmish: $BAR/skirmish.txt"
    ./spring --isolation --write-dir "$BAR" "$BAR/skirmish.txt"; rc=$? ;;
  lobby)
    log "spring lobby: rapid://${LOBBY_TAG:-byar-chobby:test}"
    ./spring --isolation --write-dir "$BAR" --menu "rapid://${LOBBY_TAG:-byar-chobby:test}"; rc=$? ;;
  shell)
    log "shell mode: sleeping; use the app log to inspect"; sleep 3600; rc=0 ;;
  *) log "unknown MODE=$MODE"; rc=2 ;;
esac
log "spring exited with $rc"
cp -f "$BAR/infolog.txt" "$LOGS/infolog-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
grep -E "GL version|GLSL version|GL4 support|S3TC|GL_VENDOR|GL_RENDERER|Video RAM|Error|error|OOM|Segmentation|desync" "$BAR/infolog.txt" 2>/dev/null | head -n 60
pulseaudio --kill >/dev/null 2>&1 || true
exit $rc
