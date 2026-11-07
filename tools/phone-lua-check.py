"""Checks the app's phone versions of BAR's widgets and gadgets (app/src/main/assets/bardroid/phone-*.lua.patch) against a
BAR release: each patch file applied to BAR's file exactly as the engine branch does (BarDroidPhoneLuaDir,
rts/Lua/LuaVFS.cpp on bardroid/lua): every block's text found exactly once, in order, or none applied. With --out the
patched files are written there (to read or diff them).
    python -I tools/phone-lua-check.py <folder with BAR's luaui/ and luarules/> [--out <folder>]
(the folder: a release's Lua unpacked from a rapid pool, e.g. C:\\Tools\\BARANDROID\\research\\bar-lua-31836)
"""
import argparse
import glob
import os
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(APP, "app", "src", "main", "assets", "bardroid")
KINDS = {"phone-widget-": "luaui/widgets/", "phone-gadget-": "luarules/gadgets/"}
FIND, WITH, END = "@@@ find\n", "\n@@@ with\n", "\n@@@ end"


def apply(patches, text):
    """(patched text, None) or (None, why): the engine's BarDroidApplyPatches."""
    patches = patches.replace("\r", "")
    text = text.replace("\r", "")
    at, n = 0, 0
    while True:
        at = patches.find(FIND, at)
        if at < 0:
            break
        f0 = at + len(FIND)
        w = patches.find(WITH, f0)
        e = patches.find(END, w + len(WITH)) if w >= 0 else -1
        if e < 0:
            return None, "patch %d unfinished" % (n + 1)
        find = patches[f0:w]
        repl = patches[w + len(WITH):e]
        p = text.find(find)
        if not find or p < 0 or text.find(find, p + 1) >= 0:
            return None, "patch %d %s" % (n + 1, "finds no place" if p < 0 else "finds more than one place")
        text = text[:p] + repl + text[p + len(find):]
        at = e + len(END)
        n += 1
    if n == 0:
        return None, "no patches"
    return text, "%d patches" % n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bar")
    ap.add_argument("--out")
    args = ap.parse_args()
    bad = 0
    for path in sorted(glob.glob(os.path.join(ASSETS, "phone-*.lua.patch"))):
        name = os.path.basename(path)
        prefix = next(k for k in KINDS if name.startswith(k))
        rel = KINDS[prefix] + name[len(prefix):-len(".patch")]
        src = os.path.join(args.bar, *rel.split("/"))
        if not os.path.exists(src):
            print("%-48s BAR has no %s" % (name, rel))
            bad += 1
            continue
        with open(path, encoding="utf-8") as f:
            patches = f.read()
        with open(src, encoding="utf-8", errors="surrogateescape") as f:
            text = f.read()
        out, why = apply(patches, text)
        print("%-48s %s" % (name, why if out is not None else "NOT APPLIED: " + why))
        if out is None:
            bad += 1
        elif args.out:
            dest = os.path.join(args.out, *rel.split("/"))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "w", encoding="utf-8", errors="surrogateescape", newline="\n") as f:
                f.write(out)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
