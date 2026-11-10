"""The app's Lua files' main chunks against Lua's limit of 200 local variables in one function.

A widget whose main chunk declares more fails to load at all ("main function has more than 200 local variables"), and
luacheck does not see it: on 2026-11-10 one more local in bardroid_portrait.lua took the whole upright dock away. This
counts the locals a file declares at its top level (lines that start with `local`, the files' own style: a top-level
statement starts at the line's first column), names in one `local a, b = ...` each.

  python -I tools/lua-locals.py [files or folders ...]   (default: app/src/main/assets/bardroid)
Exit 1 when a file is over the limit; the files within NEAR of it are named as a warning.
"""
import os
import re
import sys

LIMIT = 200
NEAR = 8
LOCAL_FUNCTION = re.compile(r"local\s+function\s+[A-Za-z_]\w*")
LOCAL_NAMES = re.compile(r"local\s+([A-Za-z_][\w\s,<>]*?)\s*(?:=|--|$)")


def top_level_locals(path):
    n = 0
    in_long_comment = False
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if in_long_comment:
                if "]]" in line:
                    in_long_comment = False
                continue
            if line.startswith("--[["):
                in_long_comment = "]]" not in line
                continue
            if LOCAL_FUNCTION.match(line):
                n += 1
                continue
            m = LOCAL_NAMES.match(line)
            if m:
                n += len([x for x in m.group(1).split(",") if x.strip()])
    return n


def main(args):
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    targets = args or [os.path.join(here, "app", "src", "main", "assets", "bardroid")]
    files = []
    for t in targets:
        if os.path.isdir(t):
            files += [os.path.join(t, n) for n in sorted(os.listdir(t)) if n.endswith(".lua")]
        else:
            files.append(t)
    over = 0
    for path in files:
        n = top_level_locals(path)
        if n > LIMIT:
            print(f"OVER {n} top-level locals (Lua's limit {LIMIT}): {path}")
            over += 1
        elif n > LIMIT - NEAR:
            print(f"near {n} top-level locals of {LIMIT}: {path}")
    print(f"lua-locals: {len(files)} files, {over} over the limit")
    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
