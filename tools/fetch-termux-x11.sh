#!/usr/bin/env bash
# Fetches Termux:X11 (the X server library this app embeds) at the pinned commit, with submodules,
# and applies our patches (patches/0*.patch). Run from the project root. Requires git.
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
for p in ../patches/0*.patch; do
  if git apply --reverse --check "$p" 2>/dev/null; then echo "already applied: $p"; continue; fi
  git apply "$p" && echo "applied: $p"
done
grep -q TERMUX_X11_LIBXLORIE_PATH lorie/src/main/java/com/termux/x11/CmdEntryPoint.java && echo "termux-x11 ready at $COMMIT (patched)"
