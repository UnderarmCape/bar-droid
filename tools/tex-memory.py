"""The engine's textures in a phone's launcher.log, summed: what holds the GPU's memory in a game.

Android's meminfo puts most of a game's memory in the GPU driver (PerfLog's "GPU ... MB": 2.5 GB in a 1v1 skirmish on
the dev phone, 2026-11-02, the engine itself 0.75 GB). With `export BARDROID_TEX_LOG=1` in the phone's
files/bar/dev-env.sh, libbardroid_pace.so logs every texture of 64x64 or more the engine makes ("[pace] glTexImage2D
...", tools/pace/pace.c) and every buffer of 64 KB or more it gives storage to ("[pace] glBufferData ... bytes"; in a 1v1
skirmish the GPU driver held 2.0 GB, its textures ~0.5 GB); this adds them up by call, internal format and size,
largest first, the buffers apart. A texture is counted as
made, not as freed later (the log has no deletes), a compressed format the driver may store uncompressed is counted at
4 bytes a pixel (GL_COMPRESSED_RGBA: Mesa's choice), and glTexStorage2D's mipmaps at a third more.
    python -I tools/tex-memory.py <launcher.log> [--top 25]
"""
import argparse
import collections
import re

# bytes per pixel by internal format (GL enums); generic or unsized ones as the phone's Mesa stores them
BPP = {0x8058: 4, 0x1908: 4, 0x881A: 8, 0x8814: 16, 0x822E: 4, 0x81A6: 4, 0x81A7: 4, 0x8CAC: 4, 0x8229: 1,
       0x822B: 2, 0x8051: 4, 0x1907: 4, 0x83F1: 0.5, 0x83F0: 0.5, 0x83F2: 1, 0x83F3: 1, 0x805B: 8, 0x822A: 2,
       0x881B: 8, 0x8059: 4, 0x1902: 4, 0x8C3A: 4, 0x81A5: 2, 0x8D48: 4, 0x88F0: 4, 0x8230: 8, 0x822F: 4,
       0x822D: 2, 0x8C43: 4, 0x1906: 1, 0x84EE: 4, 0x4: 4, 0x3: 4}
FLOAT_TYPES = {0x1406: 4, 0x140B: 2, 0x8D61: 2}
LINE = re.compile(r"\[pace\] (\w+) (\d+)x(\d+) target 0x([0-9a-f]+) internal 0x([0-9a-f]+) format 0x([0-9a-f]+) "
                  r"type 0x([0-9a-f]+) (with data|empty)")
# buffers of 1 MB or more (pace.c buf_said): storage given, not freed later (a buffer given storage again counts again)
BUF = re.compile(r"\[pace\] (\w+) (\d+) bytes target 0x([0-9a-f]+) usage 0x([0-9a-f]+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()
    size_by, count_by, unknown = collections.Counter(), collections.Counter(), collections.Counter()
    buf_size, buf_count = collections.Counter(), collections.Counter()
    for line in open(args.log, encoding="utf-8", errors="replace"):
        b = BUF.search(line)
        if b:
            key = "%s target %s usage %s %.1f MB" % (b.group(1), "0x" + b.group(3), "0x" + b.group(4),
                                                     int(b.group(2)) / 2 ** 20)
            buf_size[key] += int(b.group(2))
            buf_count[key] += 1
            continue
        m = LINE.search(line)
        if not m:
            continue
        call, w, h = m.group(1), int(m.group(2)), int(m.group(3))
        target, internal, fmt, typ = (int(m.group(i), 16) for i in (4, 5, 6, 7))
        bpp = BPP.get(internal)
        if internal in (0x1908, 0x1907, 0x4, 0x3) and typ in FLOAT_TYPES:
            bpp = 4 * FLOAT_TYPES[typ]
        if bpp is None:
            unknown[hex(internal)] += 1
            bpp = 4
        size = w * h * bpp
        if call == "glTexStorage2D" and fmt > 1:  # (pace logs the levels in the format's place)
            size *= 4 / 3
        if target == 0x8513:  # a cube map: six faces
            size *= 6
        key = "%s %s %dx%d" % (call, hex(internal), w, h)
        size_by[key] += size
        count_by[key] += 1
    total = sum(size_by.values())
    print("%.0f MB in %d textures of 128x128 or more" % (total / 2 ** 20, sum(count_by.values())))
    for key, size in size_by.most_common(args.top):
        print("%8.1f MB  %5d x  %s" % (size / 2 ** 20, count_by[key], key))
    if unknown:
        print("formats not known here (counted at 4 bytes a pixel):", dict(unknown))
    if buf_size:
        print("%.0f MB in %d buffers of 1 MB or more" % (sum(buf_size.values()) / 2 ** 20, sum(buf_count.values())))
        for key, size in buf_size.most_common(args.top):
            print("%8.1f MB  %5d x  %s" % (size / 2 ** 20, buf_count[key], key))


if __name__ == "__main__":
    main()
