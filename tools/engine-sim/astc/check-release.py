"""Which of the ASTC manifest's unit textures a BAR release on the phone has unchanged (docs/ENGINE-SIM.md).

    python -I check-release.py --manifest <bardroid-astc>/manifest.txt --src <extracted>/src --adb <adb.exe> [--release test-31723]

Compares each manifest entry's source (by its md5 in the laptop's extraction manifest, tools/mobile-models/extract.py)
with the md5 the phone's release package lists for the same path. Lists the releases the phone has without --release.
"""
import argparse
import gzip
import os
import subprocess

PACKAGE = "com.underarmcape.bardroid"


def adb_read(adb, path):
    return subprocess.run([adb, "exec-out", "run-as", PACKAGE, "cat", "files/bar/" + path], check=True,
                          stdout=subprocess.PIPE).stdout


def sdp_files(data):
    files, i = {}, 0
    while i < len(data):
        n = data[i]
        name = data[i + 1:i + 1 + n].decode("utf-8", "replace").lower()
        files[name] = data[i + 1 + n:i + 17 + n].hex()
        i += 1 + n + 16 + 8
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--src", required=True)
    ap.add_argument("--adb", required=True)
    ap.add_argument("--release", default="")
    args = ap.parse_args()
    lines = gzip.decompress(adb_read(args.adb, "rapid/repos-cdn.beyondallreason.dev/byar/versions.gz")).decode().splitlines()
    tags = [l.split(",", 3) for l in lines]
    if not args.release:
        for t in tags[-15:]:
            print(t[0], t[1], t[3])
        return
    match = [t for t in tags if args.release in t[3]]
    if not match:
        raise SystemExit("no release " + args.release)
    pkg = match[-1][1]
    phone = sdp_files(gzip.decompress(adb_read(args.adb, "packages/" + pkg + ".sdp")))
    laptop = {}
    with open(os.path.join(args.src, "manifest.tsv"), encoding="utf-8") as f:
        for line in f:
            if not line.startswith("#"):
                p, md5, _ = line.rstrip("\n").split("\t")
                laptop[p] = md5
    same = differ = missing = 0
    with open(args.manifest, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            path = line.split()[0]
            if path not in phone:
                missing += 1
            elif phone[path] == laptop.get(path):
                same += 1
            else:
                differ += 1
                print("differs:", path)
    print("%s (%s): %d the same, %d differ, %d not in it" % (match[-1][3], pkg, same, differ, missing))


if __name__ == "__main__":
    main()
