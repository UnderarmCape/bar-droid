#!/usr/bin/env bash
# Fetches Termux:X11 (the X server library this app embeds) at the pinned commit, with submodules,
# and applies our one-line patch. Run from the project root. Requires git.
set -euo pipefail
COMMIT=7e5f5c5c9226e2cdab392b2efba91bc4bd86463e
cd "$(dirname "$0")/.."
if [ ! -d termux-x11/.git ]; then
  git clone https://github.com/termux/termux-x11.git termux-x11
fi
cd termux-x11
git fetch --depth 1 origin "$COMMIT" || git fetch origin
git checkout -q "$COMMIT"
git submodule update --init --depth 1 --recursive
git apply --check ../patches/0001-cmdentrypoint-explicit-libpath.patch 2>/dev/null && git apply ../patches/0001-cmdentrypoint-explicit-libpath.patch \
  || echo "patch already applied (or failed to apply cleanly — check lorie/src/main/java/com/termux/x11/CmdEntryPoint.java for TERMUX_X11_LIBXLORIE_PATH)"
grep -q TERMUX_X11_LIBXLORIE_PATH lorie/src/main/java/com/termux/x11/CmdEntryPoint.java && echo "termux-x11 ready at $COMMIT (patched)"
