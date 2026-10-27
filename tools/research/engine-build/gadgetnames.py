import gzip, os, re, struct, sys
data, release = sys.argv[1], sys.argv[2]
md5 = None
for root, _, files in os.walk(os.path.join(data, "rapid")):
    for f in files:
        if f == "versions.gz":
            for line in gzip.open(os.path.join(root, f), "rt", encoding="utf-8"):
                p = line.rstrip("\n").split(",")
                if len(p) >= 4 and p[3] == release: md5 = p[1]
raw = gzip.open(os.path.join(data, "packages", md5 + ".sdp")).read()
i = 0
while i < len(raw):
    n = raw[i]; name = raw[i+1:i+1+n].decode(); i += 1+n
    fmd5 = raw[i:i+16].hex(); i += 24
    if name.startswith("luarules/gadgets/") and name.endswith(".lua") and name.count("/") == 2:
        src = gzip.open(os.path.join(data, "pool", fmd5[:2], fmd5[2:] + ".gz")).read().decode("utf-8", "replace")
        m = re.search(r'name\s*=\s*"([^"]+)"', src)
        print("%s\t%s" % (m.group(1) if m else "?", name))
