"""Copy every S3O model of BAR's byar:test release into a folder, for mobile_models to work on (read only on BAR's side).

    python -I tools/mobile-models/extract.py --out <folder> [--bar-data <BAR data folder> | --adb <adb.exe>]

--adb reads the release off the phone (ANDROID_SERIAL names it; the app's own files through run-as), else from a BAR
data folder (the laptop's BAR install). The models land at <out>/src/<their path in the archive, lower case> and
<out>/src/manifest.tsv lists path, pool md5 and size, with the release's name on its first line. Files that are
already there with the same md5 are not read again.
"""
import argparse
import concurrent.futures
import gzip
import hashlib
import os
import subprocess
import sys

PACKAGE = "com.underarmcape.bardroid"


class Source:
    def __init__(self, bar=None, adb=None):
        self.bar, self.adb = bar, adb

    def read(self, path):
        if self.adb:
            return subprocess.run([self.adb, "exec-out", "run-as", PACKAGE, "cat", "files/bar/" + path],
                                  check=True, stdout=subprocess.PIPE).stdout
        with open(os.path.join(self.bar, path), "rb") as f:
            return f.read()

    def versions(self):
        if self.adb:
            out = subprocess.run([self.adb, "exec-out", "run-as", PACKAGE, "sh", "-c",
                                  "cd files/bar && find rapid -name versions.gz"], check=True,
                                 stdout=subprocess.PIPE).stdout.decode().split()
            return out
        return [os.path.relpath(os.path.join(root, "versions.gz"), self.bar)
                for root, _, files in os.walk(os.path.join(self.bar, "rapid")) if "versions.gz" in files]


def release_files(src, tag_name="byar:test"):
    tag = None
    for path in src.versions():
        if path.replace("\\", "/").endswith("/byar/versions.gz"):
            for line in gzip.decompress(src.read(path)).decode().splitlines():
                parts = line.split(",", 3)
                if parts[0] == tag_name:
                    tag = parts
    if not tag:
        sys.exit(tag_name + " not found")
    data = gzip.decompress(src.read("packages/" + tag[1] + ".sdp"))
    files, i = {}, 0
    while i < len(data):
        n = data[i]
        name = data[i + 1:i + 1 + n].decode("utf-8", "replace").lower()
        md5 = data[i + 1 + n:i + 17 + n].hex()
        size = int.from_bytes(data[i + 21 + n:i + 25 + n], "big")
        i += 1 + n + 16 + 8
        files[name] = (md5, size)
    return tag[3], files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--bar-data")
    ap.add_argument("--adb")
    ap.add_argument("--jobs", type=int, default=8)
    args = ap.parse_args()
    if not args.bar_data and not args.adb:
        sys.exit("--bar-data or --adb")
    src = Source(args.bar_data, args.adb)
    release, files = release_files(src)
    models = sorted(n for n in files if n.startswith("objects3d/") and n.endswith(".s3o"))
    # (and the models' textures, which mobile_models checks its cuts against: unittextures/*.dds|tga)
    models += sorted(n for n in files if n.startswith("unittextures/") and n.endswith((".dds", ".tga")))
    out = os.path.join(args.out, "src")
    os.makedirs(out, exist_ok=True)

    def fetch(name):
        md5, size = files[name]
        dest = os.path.join(out, *name.split("/"))
        if os.path.exists(dest):
            with open(dest, "rb") as f:
                if hashlib.md5(f.read()).hexdigest() == md5:
                    return name, False
        raw = gzip.decompress(src.read("pool/" + md5[:2] + "/" + md5[2:] + ".gz"))
        if hashlib.md5(raw).hexdigest() != md5:
            raise RuntimeError("md5 mismatch: " + name)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(raw)
        return name, True

    fetched = 0
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        for name, new in pool.map(fetch, models):
            fetched += new
    with open(os.path.join(out, "manifest.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# " + release + "\n")
        for name in models:
            f.write("%s\t%s\t%d\n" % (name, files[name][0], files[name][1]))
    print("%s: %d models (%d read now) -> %s" % (release, len(models), fetched, out))


if __name__ == "__main__":
    main()
