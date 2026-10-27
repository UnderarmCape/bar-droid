"""The hail-mary results table: every research run (label hm:*) of build/phone-bench.csv, grouped by lever, with the
engine's own timers from the run's infolog (build/research-infolog/HHMM-<lever>.txt, tools/research/timers.py) and the
change against the baseline runs of the same day.
  python -I tools/research/summary.py [--markdown]
"""
import csv, glob, os, re, statistics, sys
sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
CSV = os.path.join(APP, "build", "phone-bench.csv")
LOGS = os.path.join(APP, "build", "research-infolog")
ROW = re.compile(r"^\[t=[^\]]*\](?:\[f=(-?\d+)\])?\s+(.+?)\s+([\d.]+)ms\s+([\d.]+)%\s*$")


def timers(path):
    """ms per sim frame between the first and last `debuginfo profiling` dumps."""
    dumps, cur = [], None
    for line in open(path, encoding="utf-8", errors="replace"):
        if "Total Time" in line and "Part" in line:
            m = re.search(r"\[f=(-?\d+)\]", line)
            cur = {}
            dumps.append((int(m.group(1)) if m else None, cur))
            continue
        m = ROW.match(line.rstrip("\n"))
        if m and cur is not None:
            cur[m.group(2).strip()] = float(m.group(3))
        elif cur:
            cur = None
    if len(dumps) < 2:
        return {}
    (f0, a), (f1, b) = dumps[0], dumps[-1]
    n = (f1 - f0) if f0 is not None and f1 is not None and f1 > f0 else 1994
    return {k: (b[k] - a.get(k, 0.0)) / n for k in b}


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


runs = []
for r in csv.DictReader(open(CSV, encoding="utf-8-sig")):
    label = r.get("label", "")
    if not label.startswith("hm:"):
        continue
    lever = label[3:].split(" ")[0]
    hhmm = r["when"][-5:].replace(":", "")
    # the infolog saved right after the run (same or next minute)
    t = None
    for cand in sorted(glob.glob(os.path.join(LOGS, "*-%s.txt" % lever))):
        stamp = os.path.basename(cand)[:4]
        if 0 <= int(stamp) - int(hhmm) <= 2:
            t = timers(cand)
    runs.append(dict(day=r["when"][:10], lever="baseline" if lever == "warmup-baseline" else lever, sim=num(r.get("sim_ms")),
                     draw=num(r.get("draw_ms")), upd=num(r.get("update_ms")), fps=num(r.get("fps_last")),
                     speed=num(r.get("speed_x")), cpu6=num(r.get("cpu6_med")), cap6=num(r.get("cap6_min")),
                     cap0=num(r.get("cap0_min")), esim=(t or {}).get("Sim"), lsync=(t or {}).get("Lua::Callins::Synced"),
                     lunsync=(t or {}).get("Lua::Callins::Unsynced"), warm=lever == "warmup-baseline"))


def mean(xs):
    xs = [x for x in xs if x is not None]
    return (statistics.mean(xs), statistics.pstdev(xs) if len(xs) > 1 else 0.0, len(xs)) if xs else (None, None, 0)


base = {}
for day in {r["day"] for r in runs}:
    b = [r for r in runs if r["day"] == day and r["lever"] == "baseline" and not r["warm"]]
    base[day] = (mean([r["sim"] for r in b])[0], mean([r["esim"] for r in b])[0])

levers = []
for r in runs:
    if r["lever"] not in levers:
        levers.append(r["lever"])
md = "--markdown" in sys.argv
head = ["lever", "runs", "Sim ms", "Δ Sim", "engine Sim ms", "Δ eng", "Draw", "Update", "fps", "speed", "CPU6 MHz",
        "cap6/cap0 min", "Lua sync/unsync"]
print(("| " + " | ".join(head) + " |\n|" + "---|" * len(head)) if md else "  ".join(head))
for lv in levers:
    rs = [r for r in runs if r["lever"] == lv and not (lv == "baseline" and r["warm"] and
          any(not x["warm"] for x in runs if x["lever"] == "baseline"))]
    s, sd, n = mean([r["sim"] for r in rs])
    e = mean([r["esim"] for r in rs])[0]
    days = {r["day"] for r in rs}
    bs = mean([base[d][0] for d in days])[0]
    be = mean([base[d][1] for d in days])[0]
    f = lambda v, p=1: "-" if v is None else ("%.*f" % (p, v))
    pct = lambda v, b: "-" if v is None or not b else "%+.0f%%" % (100 * (v / b - 1))
    cells = [lv, str(n), "%s±%s" % (f(s), f(sd)), pct(s, bs), f(e, 2), pct(e, be),
             f(mean([r["draw"] for r in rs])[0]), f(mean([r["upd"] for r in rs])[0]), f(mean([r["fps"] for r in rs])[0]),
             f(mean([r["speed"] for r in rs])[0], 2), f(mean([r["cpu6"] for r in rs])[0], 0),
             "%s/%s" % (f(mean([r["cap6"] for r in rs])[0], 0), f(mean([r["cap0"] for r in rs])[0], 0)),
             "%s/%s" % (f(mean([r["lsync"] for r in rs])[0], 2), f(mean([r["lunsync"] for r in rs])[0], 2))]
    print(("| " + " | ".join(cells) + " |") if md else "  ".join(cells))
