"""A research overlay's gamedata/modrules.lua, generated at run time from BAR's own file in a BAR install (read only;
the result is never committed or shipped): BAR's file wrapped in a function, then the given keys changed.
  python -I tools/research/modrules-override.py <bar data dir> "<release>" "sensors.los.losMipLevel=4;system.x=1" <out file>
"""
import gzip, os, struct, sys

data, release, edits, out = sys.argv[1:5]
md5 = None
for root, _, files in os.walk(os.path.join(data, "rapid")):
    for f in files:
        if f == "versions.gz":
            for line in gzip.open(os.path.join(root, f), "rt", encoding="utf-8"):
                p = line.rstrip("\n").split(",")
                if len(p) >= 4 and p[3] == release:
                    md5 = p[1]
if not md5:
    sys.exit("release not found: " + release)
raw = gzip.open(os.path.join(data, "packages", md5 + ".sdp")).read()
i, src = 0, None
while i < len(raw):
    n = raw[i]; name = raw[i + 1:i + 1 + n].decode("utf-8", "replace"); i += 1 + n
    fmd5 = raw[i:i + 16].hex(); i += 16 + 4
    struct.unpack(">I", raw[i:i + 4]); i += 4
    if name == "gamedata/modrules.lua":
        src = gzip.open(os.path.join(data, "pool", fmd5[:2], fmd5[2:] + ".gz")).read().decode("utf-8")
if src is None:
    sys.exit("no gamedata/modrules.lua in " + release)
lines = ["-- generated at run time from %s's gamedata/modrules.lua (hail-mary research, never shipped): %s" % (release, edits),
         "local function barModrules()", src, "end", "local m = barModrules()"]
for e in filter(None, edits.split(";")):
    path, value = e.split("=", 1)
    keys = path.strip().split(".")
    for k in range(1, len(keys)):
        t = "m." + ".".join(keys[:k])
        lines.append("%s = %s or {}" % (t, t))
    lines.append("m.%s = %s" % (path.strip(), value.strip()))
lines.append("return m")
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
