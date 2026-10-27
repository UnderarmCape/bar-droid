"""List or read files of a BAR rapid release from the laptop's BAR install (read only).
  python -I barfiles.py <bar data dir> "<release name>" list [prefix]
  python -I barfiles.py <bar data dir> "<release name>" cat <path>
"""
import gzip, os, struct, sys

data, release, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
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
entries, i = {}, 0
while i < len(raw):
    n = raw[i]; name = raw[i + 1:i + 1 + n].decode("utf-8", "replace"); i += 1 + n
    fmd5 = raw[i:i + 16].hex(); i += 16 + 4
    size = struct.unpack(">I", raw[i:i + 4])[0]; i += 4
    entries[name] = (fmd5, size)
if cmd == "list":
    pre = sys.argv[4].lower() if len(sys.argv) > 4 else ""
    for n in sorted(entries):
        if n.lower().startswith(pre):
            print(n, entries[n][1])
else:
    fmd5 = entries[sys.argv[4]][0]
    sys.stdout.buffer.write(gzip.open(os.path.join(data, "pool", fmd5[:2], fmd5[2:] + ".gz")).read())
