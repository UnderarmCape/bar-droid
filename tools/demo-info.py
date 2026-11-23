"""What a Spring/Recoil demo (.sdfz) needs to play: the engine version it was recorded with, its game and map, and its
length. One "key=value" line each (engine, game, map, seconds), for tools/soak-phone.ps1, which fetches the game and
map before it plays a replay (the bench mode downloads nothing: a replay whose map was gone ended at once, error 21,
2026-11-23). Usage: python -I tools/demo-info.py <demo.sdfz> [...]"""
import re
import struct
import sys
import zlib


def info(path):
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    data = b""
    with open(path, "rb") as f:   # (the header and the script are at the front: no need to inflate the whole game)
        while len(data) < 1 << 20:
            chunk = f.read(1 << 16)
            if not chunk:
                break
            data += d.decompress(chunk)
    if not data.startswith(b"spring demofile"):
        raise ValueError("not a Spring demo")
    _version, header_size = struct.unpack_from("<ii", data, 16)
    engine = data[24:24 + 256].split(b"\0", 1)[0].decode("utf-8", "replace")
    off = 16 + 8 + 256 + 16 + 8
    script_size, _stream, game_time = struct.unpack_from("<iii", data, off)
    script = data[header_size:header_size + script_size].decode("utf-8", "replace")

    def field(name):
        m = re.search(r"(?im)^\s*" + name + r"\s*=\s*([^;\r\n]*);", script)
        return m.group(1).strip() if m else ""
    return engine, field("gametype"), field("mapname"), game_time


for p in sys.argv[1:]:
    try:
        e, g, m, s = info(p)
        print("file=%s\nengine=%s\ngame=%s\nmap=%s\nseconds=%d" % (p, e, g, m, s))
    except Exception as ex:   # (one bad file must not hide the others)
        print("file=%s\nerror=%s" % (p, ex))
