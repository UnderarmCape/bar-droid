#!/bin/bash
# BAR Droid — container-side setup. Runs as root inside the Debian arm64 proot. Idempotent.
#   setup-container.sh apt
#   setup-container.sh mesa    /root/downloads/mesa.tar.gz
#   setup-container.sh slim                                (what the game never loads, out of the container)
#   setup-container.sh engine  /root/downloads/engine.7z  2026.07.04
#   setup-container.sh content byar:test byar-chobby:test "Supreme Isthmus v2.1"  2026.07.04
#   setup-container.sh rapid   byar:test 2026.07.04          (Updater: one rapid tag, docs/UPDATES.md; lobby bridge games)
#   setup-container.sh map     "Supreme Isthmus v2.1" 2026.07.04   (lobby bridge)
#   setup-container.sh import  2026.07.04
#   setup-container.sh check
set -u
step="${1:-}"; shift || true
BAR=/root/bar
log() { echo "[setup:$step] $*"; }
# pr-downloader of the engine, set up for BAR's servers (as BAR's launcher does)
prd_setup() {
  prd="$BAR/engine/recoil_$1/pr-downloader"
  [ -x "$prd" ] || { log "pr-downloader missing"; exit 41; }
  export PRD_RAPID_REPO_MASTER="https://repos-cdn.beyondallreason.dev/repos.gz"
  export PRD_HTTP_SEARCH_URL="https://files-cdn.beyondallreason.dev/find"
  export PRD_RAPID_USE_STREAMER=false
  export PRD_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  cd "$BAR"
}

# Files no program here reads (documentation, manual pages, translations): dpkg leaves them out of every package it
# installs from now on (Debian's slim images do the same); the licence texts stay.
slim_excludes() {
  cat > /etc/dpkg/dpkg.cfg.d/bardroid-slim <<'EOF'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/locale/*
path-include=/usr/share/locale/locale.alias
path-exclude=/usr/share/lintian/*
EOF
}

case "$step" in
  slim)
    # Kailil, 2026-11-06: "reduce all other aspects of the game". What the game never loads, taken out of the
    # container once (Installer step "slim"; /proc/<engine>/maps of a late 8v8 lists what it does load):
    # PulseAudio's daemon and tools (sound goes the engine's wave writer -> AudioPump; launch-bar.sh only killed a
    # leftover daemon) and x11-xserver-utils, with the ~90 libraries only they pulled in (GStreamer, FFmpeg's codecs,
    # the C preprocessor, iso-codes: 187 MB); the libraries the engine maps (libpulse0, ALSA, OpenAL, SDL2, the
    # sound file codecs) stay, as their other packages need them. On a phone, with the phone Mesa installed over
    # Debian's: Debian's own gallium driver and the Vulkan drivers for other GPUs (Freedreno's, the phone Mesa's,
    # stays). Then the documentation, manual pages and translations. Never fails the install: a removal that does not
    # go through leaves the files where they were.
    export DEBIAN_FRONTEND=noninteractive
    slim_excludes
    before=$(du -sm / --exclude=/root --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/tmp 2>/dev/null | cut -f1)
    gone=""
    for p in pulseaudio pulseaudio-utils x11-xserver-utils; do dpkg -s "$p" >/dev/null 2>&1 && gone="$gone $p"; done
    if [ -n "$gone" ]; then
      # Every library the engines (BAR's and the engine branch's builds: libatomic), the phone Mesa, OpenAL and SDL
      # link stays, whatever pulled it in, and the sound backends OpenAL and SDL open themselves.
      libs=""
      for f in "$BAR"/engine/*/spring "$BAR"/engine-sim/*/spring /usr/lib/*-linux-gnu/libgallium-*.so \
               /usr/lib/*-linux-gnu/libGLX_mesa.so.0 /usr/lib/*-linux-gnu/libEGL_mesa.so.0 /usr/lib/*-linux-gnu/gbm/dri_gbm.so \
               /usr/lib/*-linux-gnu/libvulkan_freedreno.so /usr/lib/*-linux-gnu/libopenal.so.1 /usr/lib/*-linux-gnu/libSDL2-2.0.so.0; do
        [ -e "$f" ] && libs="$libs $(ldd "$f" 2>/dev/null | awk '/=> \//{print $3}' | xargs -r readlink -f)"
      done
      keep=""
      for p in libatomic1 libpulse0 libasound2t64 libsndio7.0 $(dpkg -S $libs 2>/dev/null | cut -d: -f1 | tr -d ' ' | tr ',' '\n' | sort -u); do
        dpkg -s "$p" >/dev/null 2>&1 && keep="$keep $p"
      done
      log "keeping$keep"
      [ -n "$keep" ] && apt-mark manual $keep >/dev/null 2>&1
      log "removing$gone and what only they need"
      dpkg --configure -a >/dev/null 2>&1   # (a dpkg run cut short before: apt refuses until it is finished, as in apt)
      apt-get purge -y -q --autoremove $gone >/dev/null 2>&1 || log "warning: apt-get purge failed (continuing)"
    fi
    if [ -f /etc/bardroid/mesa-installed ]; then
      for d in /usr/lib/*-linux-gnu; do
        for v in broadcom gfxstream lvp nouveau panfrost radeon virtio intel intel_hasvk asahi powervr; do
          rm -f "$d/libvulkan_$v.so"
        done
        ls "$d"/libgallium-27* >/dev/null 2>&1 && for g in "$d"/libgallium-2[0-6]*.so; do [ -f "$g" ] && rm -f "$g"; done
      done
      for j in /usr/share/vulkan/icd.d/*.json; do
        case "$(basename "$j")" in freedreno_icd.*) ;; *) rm -f "$j" ;; esac
      done
    fi
    rm -f "$BAR"/engine/*/spring-headless "$BAR"/engine/*/spring-dedicated   # (as the engine step does now)
    find /usr/share/doc -mindepth 1 ! -name copyright ! -type d -delete 2>/dev/null
    find /usr/share/doc -mindepth 1 -type d -empty -delete 2>/dev/null
    rm -rf /usr/share/man/* /usr/share/info/* /usr/share/lintian/* 2>/dev/null
    find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name locale.alias -exec rm -rf {} + 2>/dev/null
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin
    after=$(du -sm / --exclude=/root --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/tmp 2>/dev/null | cut -f1)
    log "container ${before:-?} MB -> ${after:-?} MB"
    log "ok"
    ;;

  apt)
    export DEBIAN_FRONTEND=noninteractive
    # Android apps may not create hard links; dpkg copes thanks to proot --link2symlink, but keep it quiet.
    echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/bardroid
    echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99bardroid
    echo 'Acquire::Retries "3";' >> /etc/apt/apt.conf.d/99bardroid
    slim_excludes
    # (an install cut short in dpkg, Stop or Android's low-memory kill, leaves its journal, and every apt-get install
    # after refused with "dpkg was interrupted": the install failed at this step for good, short of clearing the app's
    # storage; release overhaul audit, 2026-11-21)
    dpkg --configure -a >/dev/null 2>&1 || log "warning: dpkg --configure -a failed (continuing)"
    log "apt-get update"
    apt-get update -q || { log "apt-get update failed"; exit 11; }
    log "installing runtime libraries"
    apt-get install -y -q --no-install-recommends \
      bash coreutils ca-certificates curl p7zip-full xz-utils procps \
      libsdl2-2.0-0 libx11-6 libxcursor1 libxext6 libxrandr2 libxi6 libxss1 libxxf86vm1 libxkbcommon0 \
      libopenal1 libsndio7.0 \
      fontconfig fonts-dejavu-core xkb-data xfonts-base xfonts-utils \
      libgl1 libegl1 libegl-mesa0 libgbm1 libglx-mesa0 libgl1-mesa-dri mesa-libgallium mesa-vulkan-drivers \
      libvulkan1 vulkan-tools mesa-utils \
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
    # (the server builds, 39 MB, never run on a phone)
    rm -f "$dest/spring-headless" "$dest/spring-dedicated"
    chmod +x "$dest/spring" "$dest/pr-downloader" 2>/dev/null || true
    "$dest/spring" --version || { log "engine does not run"; exit 32; }
    log "ok"
    ;;

  content)
    game="${1:?game tag}"; lobby="${2:?lobby tag}"; map="${3:?map name}"; ver="${4:?engine version}"
    prd_setup "$ver"
    log "downloading game $game (3.4 GB uncompressed; only missing files are fetched)"
    # (pr-downloader's 5, the disk too full, as its own exit: 45, the launcher's "storage full"; release overhaul
    # audit, 2026-11-21)
    "$prd" --filesystem-writepath "$BAR" --download-game "$game"; rc=$?
    if [ $rc -ne 0 ]; then
      log "game download failed (pr-downloader exited with $rc)"
      [ $rc -eq 5 ] && exit 45
      exit 42
    fi
    log "downloading lobby $lobby"
    "$prd" --filesystem-writepath "$BAR" --download-game "$lobby" || log "lobby download failed (continuing)"
    if ! ls "$BAR"/maps/*.sd7 "$BAR"/maps/*.sdz >/dev/null 2>&1; then
      log "downloading map $map"
      # (not fatal: the whole install failed here after 3.4 GB when the launcher's map name was mistyped or BAR had
      # removed the map; a skirmish fetches its map at its start and says so when it cannot, the lobby fetches its own;
      # release overhaul audit, 2026-11-21)
      "$prd" --filesystem-writepath "$BAR" --download-map "$map" ||
        log "map download failed (continuing: a skirmish fetches its map at its start, the lobby its own)"
    fi
    log "ok"
    ;;

  rapid)
    # The update check at every start, as BAR's launcher runs pr-downloader on its games; exits with pr-downloader's
    # code (5 = disk too full).
    tag="${1:?rapid tag}"; ver="${2:?engine version}"
    prd_setup "$ver"
    log "updating $tag (only files missing from the pool)"
    "$prd" --filesystem-writepath "$BAR" --download-game "$tag"; rc=$?
    [ $rc -eq 0 ] && log "ok" || log "pr-downloader exited with $rc"
    exit $rc
    ;;

  map)
    # A map the lobby asked for through the lobby bridge (LobbyBridge.java); exits with pr-downloader's code.
    name="${1:?map name}"; ver="${2:?engine version}"
    prd_setup "$ver"
    log "downloading map $name"
    "$prd" --filesystem-writepath "$BAR" --download-map "$name"; rc=$?
    [ $rc -eq 0 ] && log "ok" || log "pr-downloader exited with $rc"
    exit $rc
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
