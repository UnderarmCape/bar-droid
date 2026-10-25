#!/bin/bash
# BAR Droid — container-side setup. Runs as root inside the Debian arm64 proot. Idempotent.
#   setup-container.sh apt
#   setup-container.sh mesa    /root/downloads/mesa.tar.gz
#   setup-container.sh engine  /root/downloads/engine.7z  2026.07.04
#   setup-container.sh content byar:test byar-chobby:test "Supreme Isthmus v2.1"  2026.07.04
#   setup-container.sh import  2026.07.04
#   setup-container.sh check
set -u
step="${1:-}"; shift || true
BAR=/root/bar
log() { echo "[setup:$step] $*"; }

case "$step" in
  apt)
    export DEBIAN_FRONTEND=noninteractive
    # Android apps may not create hard links; dpkg copes thanks to proot --link2symlink, but keep it quiet.
    echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/bardroid
    echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99bardroid
    echo 'Acquire::Retries "3";' >> /etc/apt/apt.conf.d/99bardroid
    log "apt-get update"
    apt-get update -q || { log "apt-get update failed"; exit 11; }
    log "installing runtime libraries"
    apt-get install -y -q --no-install-recommends \
      bash coreutils ca-certificates curl p7zip-full xz-utils procps \
      libsdl2-2.0-0 libx11-6 libxcursor1 libxext6 libxrandr2 libxi6 libxss1 libxxf86vm1 libxkbcommon0 \
      libopenal1 libsndio7.0 \
      fontconfig fonts-dejavu-core xkb-data xfonts-base xfonts-utils x11-xserver-utils \
      libgl1 libegl1 libegl-mesa0 libgbm1 libglx-mesa0 libgl1-mesa-dri mesa-libgallium mesa-vulkan-drivers \
      libvulkan1 vulkan-tools mesa-utils \
      pulseaudio pulseaudio-utils \
      || { log "apt-get install failed"; exit 12; }
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    # Fonts for the X server (lorie looks under <rootfs>/usr/share/fonts/X11/{misc,...}).
    ls /usr/share/fonts/X11/misc >/dev/null 2>&1 || log "warning: no misc X11 fonts installed"
    log "ok"
    ;;

  mesa)
    tgz="${1:?mesa tarball}"
    [ -f "$tgz" ] || { log "missing $tgz"; exit 21; }
    log "installing Mesa for Android containers over the distro Mesa"
    tar -zxf "$tgz" -C / || { log "tar failed"; exit 22; }
    ldconfig
    mkdir -p /etc/bardroid && basename "$tgz" > /etc/bardroid/mesa-installed
    log "ok"
    ;;

  engine)
    archive="${1:?engine 7z}"; ver="${2:?engine version}"
    dest="$BAR/engine/recoil_$ver"
    mkdir -p "$dest"
    log "extracting engine $ver"
    7z x -y "$archive" -o"$dest" >/dev/null || { log "7z failed"; exit 31; }
    chmod +x "$dest/spring" "$dest/spring-headless" "$dest/spring-dedicated" "$dest/pr-downloader" 2>/dev/null || true
    "$dest/spring" --version || { log "engine does not run"; exit 32; }
    log "ok"
    ;;

  content)
    game="${1:?game tag}"; lobby="${2:?lobby tag}"; map="${3:?map name}"; ver="${4:?engine version}"
    prd="$BAR/engine/recoil_$ver/pr-downloader"
    [ -x "$prd" ] || { log "pr-downloader missing"; exit 41; }
    export PRD_RAPID_REPO_MASTER="https://repos-cdn.beyondallreason.dev/repos.gz"
    export PRD_HTTP_SEARCH_URL="https://files-cdn.beyondallreason.dev/find"
    export PRD_RAPID_USE_STREAMER=false
    export PRD_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    cd "$BAR"
    log "downloading game $game (3.4 GB uncompressed; only missing files are fetched)"
    "$prd" --filesystem-writepath "$BAR" --download-game "$game" || { log "game download failed"; exit 42; }
    log "downloading lobby $lobby"
    "$prd" --filesystem-writepath "$BAR" --download-game "$lobby" || log "lobby download failed (continuing)"
    if ! ls "$BAR"/maps/*.sd7 "$BAR"/maps/*.sdz >/dev/null 2>&1; then
      log "downloading map $map"
      "$prd" --filesystem-writepath "$BAR" --download-map "$map" || { log "map download failed"; exit 43; }
    fi
    log "ok"
    ;;

  import)
    # Content pushed from a PC into Android/data/<pkg>/files/import (pool/, packages/, rapid/, maps/, games/)
    for d in pool packages rapid maps games; do
      if [ -d "/root/import/$d" ]; then
        log "importing $d"
        mkdir -p "$BAR/$d"
        (cd "/root/import/$d" && find . -type f -print0 | while IFS= read -r -d '' f; do
            mkdir -p "$BAR/$d/$(dirname "$f")"; mv -f "/root/import/$d/$f" "$BAR/$d/$f"; done)
      fi
    done
    log "ok"
    ;;

  check)
    echo "debian: $(cat /etc/debian_version 2>/dev/null)"
    echo "mesa: $(cat /etc/bardroid/mesa-installed 2>/dev/null || echo none)"
    command -v glxinfo >/dev/null && echo "glxinfo: present" || echo "glxinfo: missing"
    ls "$BAR"/engine 2>/dev/null
    ls "$BAR"/packages 2>/dev/null | head -n 3
    ;;

  *)
    log "unknown step '$step'"; exit 2 ;;
esac
