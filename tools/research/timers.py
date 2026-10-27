"""The engine's timers over the benchmark: the difference between the two `debuginfo profiling` dumps (frames 16 and
2010) of a research run's infolog, as ms per simulated frame (1994 frames) and as a share of the Sim timer.
  python -I tools/research/timers.py <infolog.txt> [more infologs: one column each]
"""
import re, sys

ROW = re.compile(r"^\[t=[^\]]*\](?:\[f=(-?\d+)\])?\s+(.+?)\s+([\d.]+)ms\s+([\d.]+)%\s*$")


def dumps(path):
    out, cur, frame = [], None, None
    for line in open(path, encoding="utf-8", errors="replace"):
        if "Total Time" in line and "Part" in line:
            m = re.search(r"\[f=(-?\d+)\]", line)
            cur = {}
            out.append((int(m.group(1)) if m else None, cur))
            continue
        m = ROW.match(line.rstrip("\n"))
        if m and cur is not None:
            cur[m.group(2).strip()] = float(m.group(3))
        elif cur is not None and cur:
            cur = None
    return out


cols = []
for p in sys.argv[1:]:
    d = dumps(p)
    if len(d) < 2:
        print("fewer than two timer dumps in", p)
        continue
    (f0, a), (f1, b) = d[0], d[-1]
    frames = (f1 - f0) if (f0 is not None and f1 is not None) else 1994
    cols.append((p, {k: (b[k] - a.get(k, 0.0)) / frames for k in b}, frames))
if not cols:
    sys.exit(1)
keys = sorted(cols[0][1], key=lambda k: -cols[0][1][k])
sim = cols[0][1].get("Sim", 1.0) or 1.0
print("%-38s" % "part (ms per sim frame)" + "".join("%10s" % ("run%d" % i) for i in range(len(cols))) + "   % of Sim")
for k in keys:
    v = cols[0][1][k]
    if v < 0.05:
        continue
    print("%-38s" % k[:38] + "".join("%10.2f" % c[1].get(k, 0.0) for c in cols) + "   %5.1f" % (100 * v / sim))
for i, c in enumerate(cols):
    print("run%d = %s (%d frames)" % (i, c[0], c[2]))
