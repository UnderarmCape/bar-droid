"""BAR's unit textures as ASTC for phones (docs/ENGINE-SIM.md, BarDroidModelTextureDir): every unittextures/**/*.dds
of an extracted BAR release (tools/mobile-models/extract.py's <out>/src) to KTX files with ASTC mipmaps, from the
first level no larger than --max on a side, as the engine uploads them (flipped: dds2tga.exe). A manifest lists each
source's path, size and CRC32, which the engine compares with the archive's file before it uses the KTX instead.
Made on the laptop; the output stays out of git (BAR's art: phone derivatives, docs/ENGINE-SIM.md).

    python -I convert.py --src <extracted>/src --out <folder> [--block 6x6] [--max 2048] [--quality -medium]
"""
import argparse
import concurrent.futures
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

TOOLS = r"C:\Tools\BARANDROID\engine-sim\astc-tools"
ASTCENC = r"C:\Tools\BARANDROID\toolchain\hosttools\astcenc\bin\astcenc-avx2.exe"
GL_FORMAT = {"4x4": 0x93B0, "5x5": 0x93B2, "6x6": 0x93B4, "8x8": 0x93B7}
KTX_ID = bytes([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A])


def crc32_file(path):
    crc = 0
    with open(path, "rb") as f:
        while True:
            b = f.read(1 << 22)
            if not b:
                return crc & 0xFFFFFFFF
            crc = zlib.crc32(b, crc)


def convert(rel, src, out, block, max_side, quality, threads):
    dds = os.path.join(src, *rel.split("/"))
    ktx_rel = rel[:-4] + ".ktx"
    dest = os.path.join(out, *ktx_rel.split("/"))
    work = tempfile.mkdtemp(prefix="astc-")
    try:
        r = subprocess.run([os.path.join(TOOLS, "dds2tga.exe"), dds, os.path.join(work, "l"), str(max_side)],
                           capture_output=True, text=True)
        if r.returncode:
            return rel, None, "dds2tga: " + (r.stderr.strip() or r.stdout.strip())
        levels, w, h, kind = r.stdout.split()[1:5]
        levels, w, h = int(levels), int(w), int(h)
        blocks = []
        for i in range(levels):
            tga, astc = os.path.join(work, "l.%d.tga" % i), os.path.join(work, "l.%d.astc" % i)
            e = subprocess.run([ASTCENC, "-cl", tga, astc, block, quality, "-silent", "-j", str(threads)],
                               capture_output=True, text=True)
            if e.returncode:
                return rel, None, "astcenc: " + e.stdout.strip()[-200:] + e.stderr.strip()[-200:]
            with open(astc, "rb") as f:
                data = f.read()
            if struct.unpack("<I", data[:4])[0] != 0x5CA1AB13:
                return rel, None, "astcenc wrote no .astc"
            blocks.append(data[16:])
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(KTX_ID)
            f.write(struct.pack("<13I", 0x04030201, 0, 1, 0, GL_FORMAT[block], 0x1908, w, h, 0, 0, 1, levels, 0))
            for b in blocks:
                f.write(struct.pack("<I", len(b)))
                f.write(b)
        return rel, (os.path.getsize(dds), crc32_file(dds), ktx_rel, w, h, levels, kind, os.path.getsize(dest)), None
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--block", default="6x6", choices=sorted(GL_FORMAT))
    ap.add_argument("--max", type=int, default=2048)
    ap.add_argument("--quality", default="-medium")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--only", default="", help="comma-separated substrings: only matching paths")
    args = ap.parse_args()
    root = os.path.join(args.src, "unittextures")
    rels = []
    for d, _, files in os.walk(root):
        for n in files:
            if n.lower().endswith(".dds") and "normal" not in n.lower():
                rels.append(os.path.relpath(os.path.join(d, n), args.src).replace("\\", "/").lower())
    if args.only:
        rels = [r for r in rels if any(s in r for s in args.only.split(","))]
    rels.sort()
    os.makedirs(args.out, exist_ok=True)
    threads = max(1, (os.cpu_count() or 8) // args.jobs)
    done, failed, before, after = [], [], 0, 0
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futs = [pool.submit(convert, r, args.src, args.out, args.block, args.max, args.quality, threads) for r in rels]
        for i, fu in enumerate(concurrent.futures.as_completed(futs)):
            rel, info, err = fu.result()
            if err:
                failed.append((rel, err))
            else:
                done.append((rel, info))
                after += info[7]
            if (i + 1) % 100 == 0:
                print("%d/%d" % (i + 1, len(rels)), flush=True)
    done.sort()
    with open(os.path.join(args.out, "manifest.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# BAR Droid ASTC unit textures: <dds path> <dds size> <dds crc32> <ktx path>; %s, max %d, astcenc %s\n"
                % (args.block, args.max, args.quality))
        for rel, info in done:
            f.write("%s %d %08x %s\n" % (rel, info[0], info[1], info[2]))
    for rel, err in failed:
        print("failed:", rel, err)
    print("%d converted, %d failed; KTX %.1f MB in all -> %s" % (len(done), len(failed), after / 1e6, args.out))


if __name__ == "__main__":
    main()
