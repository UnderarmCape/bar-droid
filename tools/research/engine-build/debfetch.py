"""Fetch Debian trixie arm64 packages and unpack them into a directory (a cross sysroot, or a lib folder).

  python -I debfetch.py <Packages.xz> <outdir> [--deps] pkg [pkg ...]
  python -I debfetch.py <Packages.xz> --show pkg
"""
import io, lzma, os, sys, tarfile, urllib.request

MIRROR = "https://deb.debian.org/debian/"


def load_index(path):
    pk = {}
    with lzma.open(path, "rt", encoding="utf-8") as f:
        cur = {}
        last = None
        for line in f:
            line = line.rstrip("\n")
            if not line:
                if "Package" in cur:
                    pk.setdefault(cur["Package"], cur)
                    for p in cur.get("Provides", "").split(","):
                        p = p.strip().split(" ")[0]
                        if p:
                            pk.setdefault("virtual:" + p, cur)
                cur = {}
                continue
            if line[0] in " \t":
                if last:
                    cur[last] += "\n" + line
                continue
            k, _, v = line.partition(":")
            cur[k] = v.strip()
            last = k
    return pk


def deps_of(p):
    out = []
    for field in ("Depends", "Pre-Depends"):
        for alt in p.get(field, "").split(","):
            alt = alt.strip()
            if not alt:
                continue
            name = alt.split("|")[0].strip().split(" ")[0].split(":")[0]
            out.append(name)
    return out


def ar_members(data):
    assert data[:8] == b"!<arch>\n"
    i = 8
    while i < len(data):
        hdr = data[i:i + 60]
        name = hdr[:16].decode().strip().rstrip("/")
        size = int(hdr[48:58].decode().strip())
        yield name, data[i + 60:i + 60 + size]
        i += 60 + size + (size & 1)


def unpack(deb, outdir):
    for name, body in ar_members(deb):
        if name.startswith("data.tar"):
            if name.endswith(".zst"):
                from compression import zstd
                body = zstd.decompress(body)
                mode = "r:"
            elif name.endswith(".xz"):
                mode = "r:xz"
            elif name.endswith(".gz"):
                mode = "r:gz"
            else:
                mode = "r:"
            with tarfile.open(fileobj=io.BytesIO(body), mode=mode) as t:
                for m in t.getmembers():
                    target = os.path.join(outdir, m.name)
                    if m.isdir():
                        os.makedirs(target, exist_ok=True)
                    elif m.isfile():
                        os.makedirs(os.path.dirname(target), exist_ok=True)
                        with t.extractfile(m) as src, open(target, "wb") as dst:
                            dst.write(src.read())
                    elif m.issym() or m.islnk():
                        # Windows: no symlinks; remember them for a later pass
                        with open(os.path.join(outdir, ".symlinks"), "a") as s:
                            s.write(f"{m.name}\t{m.linkname}\t{'hard' if m.islnk() else 'sym'}\n")


def resolve_links(outdir):
    lst = os.path.join(outdir, ".symlinks")
    if not os.path.exists(lst):
        return
    for _ in range(5):
        for line in open(lst):
            name, link, kind = line.rstrip("\n").split("\t")
            dst = os.path.join(outdir, name)
            if os.path.exists(dst):
                continue
            if kind == "hard":
                src = os.path.join(outdir, link)
            elif link.startswith("/"):
                src = os.path.join(outdir, link.lstrip("/"))
            else:
                src = os.path.join(os.path.dirname(dst), link)
            if os.path.isfile(src):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(src, "rb") as a, open(dst, "wb") as b:
                    b.write(a.read())


def main():
    idx = load_index(sys.argv[1])
    if sys.argv[2] == "--show":
        for n in sys.argv[3:]:
            p = idx.get(n) or idx.get("virtual:" + n)
            print(n, "->", p and (p["Package"], p["Version"], p["Filename"], deps_of(p)))
        return
    outdir = sys.argv[2]
    args = sys.argv[3:]
    follow = "--deps" in args
    names = [a for a in args if not a.startswith("--")]
    skip = set()
    if "--skip" in " ".join(args):
        pass
    todo, seen = list(names), set()
    cache = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), "debs")
    os.makedirs(cache, exist_ok=True)
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        p = idx.get(n) or idx.get("virtual:" + n)
        if not p:
            print("missing", n)
            continue
        fn = os.path.join(cache, os.path.basename(p["Filename"]))
        if not os.path.exists(fn):
            urllib.request.urlretrieve(MIRROR + p["Filename"], fn)
        with open(fn, "rb") as f:
            unpack(f.read(), outdir)
        print("unpacked", p["Package"], p["Version"])
        if follow:
            todo.extend(d for d in deps_of(p) if d not in seen)
    resolve_links(outdir)


main()
