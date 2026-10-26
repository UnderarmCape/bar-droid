"""Bytes of game messages per game-minute in a Spring/Recoil demo (.sdfz), and the catch-up speed a 64 KiB/s link
(the engine's default LinkOutgoingBandwidth) would allow a spectator joining late. The phone records one for every
game it joins (files/bar/demos). Usage: python -I tools/demo-rate.py <demo.sdfz>"""
import struct
import sys
import zlib
from collections import Counter, defaultdict

raw = open(sys.argv[1], "rb").read()
d = zlib.decompressobj(16 + zlib.MAX_WBITS)
data = d.decompress(raw)
magic = data[:16]
version, header_size = struct.unpack_from("<ii", data, 16)
off = 16 + 8 + 256 + 16 + 8
script_size, stream_size = struct.unpack_from("<ii", data, off)
print("magic", magic, "version", version, "header", header_size, "script", script_size, "stream", stream_size,
      "decompressed", len(data))
pos = header_size + script_size
end = pos + stream_size if stream_size > 0 else len(data)
per_min = defaultdict(int)
types = defaultdict(Counter)
last_t = 0
while pos + 8 <= end:
    t, length = struct.unpack_from("<fI", data, pos)
    pos += 8
    if pos + length > end:
        break
    m = int(t // 60)
    per_min[m] += length + 8
    types[m][data[pos]] += length
    pos += length
    last_t = t
print("game time covered: %.0f s" % last_t)
LINK = 64 * 1024
for m in sorted(per_min):
    b = per_min[m] / 60.0
    top = ", ".join("%d:%.0f%%" % (k, 100.0 * v / per_min[m]) for k, v in types[m].most_common(4))
    print("min %3d  %7.0f B/game-s  -> x%.1f at 64 KiB/s   top msg ids %s" % (m, b, LINK / b, top))
