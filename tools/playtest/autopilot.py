# The driver's standing rules (Kailil, 2026-11-22: the agent's own reaction loop was the slow part against BARb Hard):
# an idle constructor, commander or factory gets its next job at once, by the same touches a player would make
# (select, pick a tile, tap a spot, PLACE). Called from play.run() in "auto" mode when the dev widget paused the game
# for an idle unit; every decision is appended to autopilot.log.
import json
import os
import re
import time

from playenv import HERE, WORK

LOG = os.path.join(WORK, "autopilot.log")
# The settings (the run folder's autopilot.json, else this folder's): {"range": 2600}: how far from the base a
# constructor claims spots; autopilot-fortress.json: the turtling settings, copied over it for a run.
CONF = os.path.join(WORK, "autopilot.json")
if not os.path.exists(CONF):
    CONF = os.path.join(HERE, "autopilot.json")

CONS = ("armck", "armack")
FACTORIES = ("armlab", "armalab")


def log(text):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%H:%M:%S ") + text + "\n")


def conf():
    try:
        return json.load(open(CONF))
    except (OSError, ValueError):
        return {"range": 2600}


def hostile(st):
    return [e for e in st["e"] if e["d"] != "?" and not e["d"].startswith("critter")]


def recent_losses(st, seconds=75):
    out = []
    for t, kind, text in st["ev"]:
        m = re.search(r" at (-?\d+),(-?\d+)", text)
        if kind == "lost" and m and st["t"] - t <= seconds:
            out.append((int(m.group(1)), int(m.group(2))))
    return out


def safe(st, x, z, r=700):
    bad = [(e["x"], e["z"]) for e in hostile(st)] + recent_losses(st)
    return all((bx - x) ** 2 + (bz - z) ** 2 > r * r for bx, bz in bad)


def select(play, uid):
    play.selid([uid])
    st = play.read_state()
    if uid in st.get("sid", []):
        return True
    u = next((v for v in st["u"] if v["id"] == uid), None)
    if not u:
        return False
    # (a building on top of it took the tap: a box over its ground keeps units only)
    play.go(u["x"], u["z"])
    q = play.ask({"a": (u["x"] - 45, u["z"] - 45), "b": (u["x"] + 45, u["z"] + 45)})
    if q.get("a") and q.get("b"):
        play.set_queue(False)
        play.touch({"g": "tapdrag", "x": q["a"][0], "y": q["a"][1], "x2": q["b"][0], "y2": q["b"][1], "ms": 450,
                    "why": "box select #%d" % uid, "exact": True})
        time.sleep(0.6)
    return uid in play.read_state().get("sid", [])


def farm(play, st):
    # where energy and converters go: 450 elmos behind the base (away from the map's middle), never around the
    # factories (game 8: solars, winds and converters "by the base" walled both Bot Labs' exits in; the army stood
    # inside, its path empty)
    base = play.base_center(st)
    w, h = st.get("map", (4096, 4096))
    dx, dz = base["x"] - w / 2, base["z"] - h / 2
    n = max(1.0, (dx * dx + dz * dz) ** 0.5)
    x = min(w - 200, max(200, base["x"] + dx / n * 450))
    z = min(h - 200, max(200, base["z"] + dz / n * 450))
    return int(x), int(z)


def have(st, d, x, z, r=70):
    return any(v["d"] == d and (v["x"] - x) ** 2 + (v["z"] - z) ** 2 < r * r for v in st["u"])


def fortress_con_job(play, st, u):
    # the fortress (game 11 on): the base's own extractors only, the ways in defended, energy, the T2 lab
    c = conf()
    base = play.base_center(st)
    for d, x, z in c.get("defs", []):  # (the ways in first: game 11's Pawns came in before any defence stood)
        if not have(st, d, x, z, 160):  # (near the point, on ground the engine takes: "CAN'T BUILD THERE" on a slope)
            play.build_near(d, x, z, 1, 48)
            return "%s near %d,%d" % (d, x, z)
    near = [s for s in st["m_"] if s["free"] and play.dist(s, base) < c.get("base_r", 1000)]
    if near:
        s = min(near, key=lambda s: play.dist(s, u))
        play.build("armmex", [(s["x"], s["z"])])
        return "base extractor at %d,%d" % (s["x"], s["z"])
    if not any(v["d"] == "armalab" for v in st["u"]) and (st["m"][0] > 300 or st["t"] > 360):
        play.build("armalab", [tuple(c.get("alab_at", farm(play, st)))])
        return "the Advanced Bot Lab"
    en = st["en"]
    if en[0] < 0.4 * max(1, en[1]):
        play.build_near("armsolar", *farm(play, st), 3, 80)
        return "3 solars on the field"
    play.build_near("armmakr", *farm(play, st), 2, 110)
    return "2 converters on the field"


def t2_con_job(play, st, u):
    c = conf()
    base = play.base_center(st)
    mexes = [v for v in st["u"] if v["d"] == "armmex" and play.dist(v, base) < c.get("base_r", 1000)]
    if mexes:  # (an advanced extractor over a base extractor replaces it)
        m = min(mexes, key=lambda v: play.dist(v, u))
        play.build("armmoho", [(m["x"], m["z"])])
        return "advanced extractor over %d,%d" % (m["x"], m["z"])
    if not any(v["d"] == "armfus" for v in st["u"]):
        play.build_near("armfus", *farm(play, st), 1, 140)
        return "a fusion reactor"
    for d, x, z in c.get("defs2", []):
        if not have(st, d, x, z):
            play.build(d, [(x, z)])
            return "%s at %d,%d" % (d, x, z)
    play.build_near("armmmkr", *farm(play, st), 2, 120)
    return "2 advanced converters"


def con_job(play, st, u):
    if conf().get("mode") == "fortress":
        return t2_con_job(play, st, u) if u["d"] == "armack" else fortress_con_job(play, st, u)
    base = play.base_center(st)
    rng = conf()["range"]
    free = [s for s in st["m_"] if s["free"] and play.dist(s, base) < rng and safe(st, s["x"], s["z"])]
    if free:
        s = min(free, key=lambda s: play.dist(s, u))
        # (the Sentry first: Ticks and Grunts killed extractors finished before their Sentry, games 8-10; its place
        # beside the spot, toward the base, so the extractor's own place stays free)
        base = play.base_center(st)
        bx = s["x"] + (60 if base["x"] > s["x"] else -60)
        bz = s["z"] + (60 if base["z"] > s["z"] else -60)
        play.build_near("armllt", bx, bz, 1, 48)
        play.build("armmex", [(s["x"], s["z"])])
        return "Sentry + extractor at %d,%d" % (s["x"], s["z"])
    if not any(v["d"] == "armalab" for v in st["u"]) and st["m"][0] > 600:  # (metal banking: the T2 lab)
        play.build_near("armalab", *farm(play, st), 1, 120)
        return "the Advanced Bot Lab"
    en = st["en"]
    if en[0] < 0.5 * max(1, en[1]):
        play.build_near("armsolar", *farm(play, st), 2, 80)
        return "2 solars by the base"
    play.build_near("armmakr", *farm(play, st), 2, 110)
    return "2 converters by the base"


def commander_job(play, st, u):
    base = play.base_center(st)
    near = [s for s in st["m_"] if s["free"] and play.dist(s, base) < conf().get("base_r", 1000) and safe(st, s["x"], s["z"], 400)]
    if near:  # (the base's own extractors first: lost ones rebuilt by the strongest builder)
        s = min(near, key=lambda s: play.dist(s, u))
        play.build("armmex", [(s["x"], s["z"])])
        return "base extractor at %d,%d" % (s["x"], s["z"])
    labs = sum(1 for v in st["u"] if v["d"] == "armlab")
    if st["m"][0] > 250 and labs < 2 and st["t"] > 420:  # (metal banking: a second Bot Lab spends it)
        play.build_near("armlab", int(base["x"]) + 150, int(base["z"]) + 100, 1, 96)
        return "a second Bot Lab"
    en = st["en"]
    if en[0] < 0.4 * max(1, en[1]):
        play.build_near("armsolar", *farm(play, st), 3, 80)
        return "3 solars by the base"
    if en[0] > 0.85 * max(1, en[1]):
        play.build_near("armmakr", *farm(play, st), 2, 110)
        return "2 converters by the base"
    play.build_near("armwin", *farm(play, st), 3, 56)
    return "3 winds by the base"


def factory_job(play, st, u):
    if u["d"] == "armalab":
        if not any(v["d"] == "armack" for v in st["u"]):
            play.fac("armack", 1)
        play.fac("armzeus", 4)
        play.fac("armfido", 2)
        play.fac("armfboy", 1)
        play.tap(936, 1953, why="ORDERS")
        rp = [n for (s, n) in play.read_state().get("c", {}) if s == "R"]
        if "repeat_off" in rp:
            t = play.tile("R", "repeat_off", "repeat")
            if t:
                play.tap(*t[1], why="Repeat on")
        play.order("Patrol", tuple(conf().get("rally", (1400, 4100))))
        return "T2: Welders, Hounds, a Fatboy on repeat"
    play.fac("armwar", 1)
    play.tap(936, 1555, why="+5 Centurions")
    play.fac("armrock", 2)
    play.tap(936, 1953, why="ORDERS")
    if "repeat_off" in [n for (s, n) in play.read_state().get("c", {}) if s == "R"]:
        play.tile("R", "repeat_off", "repeat") and play.tap(*play.tile("R", "repeat_off", "repeat")[1], why="Repeat on")
    play.order("Patrol", tuple(conf().get("rally", (1400, 4100))))
    return "6 Centurions, 2 Rocketeers on repeat, Patrol rally"


ASSIGNED = os.path.join(WORK, "autopilot-assigned.json")
LAST_JOB = {}  # unit id -> game second of its last job (this run of play.py)


def assigned():
    try:
        return set(json.load(open(ASSIGNED)))
    except (OSError, ValueError):
        return set()


def mark_assigned(text):
    a = assigned()
    a.add(text)
    json.dump(sorted(a), open(ASSIGNED, "w"))


SWEEP = {"t": -999}
PUSH = {"t": -999}
ARMY = ("armwar", "armrock", "armham", "armpw", "armzeus", "armfido", "armfboy", "armmav", "armsnipe")


def push_rule(play, st):
    # the army, once big enough, by a Fight order to the mirror of our start (BARb's start on these 1v1 maps); the
    # engine's path finder routes it; again every push_every seconds with whoever is new (the ones already out keep
    # going: their order is the same point)
    c = conf()
    army = [u for u in st["u"] if u["d"] in ARMY and u["built"] >= 100]
    if len(army) < c.get("push_at", 22) or st["t"] - PUSH["t"] < c.get("push_every", 150) or not st.get("map"):
        return False
    base = play.base_center(st)
    w, h = st["map"]
    target = (int(w - base["x"]), int(h - base["z"]))
    if not PUSH.get("route"):  # (the path finder's way there, a point every ~900 elmos: each one reachable by a
        pts = play.path(int(base["x"]), int(base["z"]), target[0], target[1])  # camera pan from the one before)
        if not pts:  # (no answer from the path finder: straight hops; a Fight point in a cliff ends at its foot)
            d = ((target[0] - base["x"]) ** 2 + (target[1] - base["z"]) ** 2) ** 0.5
            n = int(d / 900) + 1
            pts = [(int(base["x"] + (target[0] - base["x"]) * i / n), int(base["z"] + (target[1] - base["z"]) * i / n))
                   for i in range(n + 1)]
            log("push route: path finder silent, straight hops")
        route, last = [], None
        for p in pts:
            if last is None or (p[0] - last[0]) ** 2 + (p[1] - last[1]) ** 2 >= 900 ** 2:
                route.append(p)
                last = p
        if pts and route[-1] != pts[-1]:
            route.append(pts[-1])
        dense, prev = [], (int(base["x"]), int(base["z"]))  # (no hop longer than 900: a waypoint path with long
        for p in route[1:] or [target]:  # straight runs, or two points only, still pans in steps)
            d = ((p[0] - prev[0]) ** 2 + (p[1] - prev[1]) ** 2) ** 0.5
            k = int(d / 900)
            for i in range(1, k + 1):
                dense.append((int(prev[0] + (p[0] - prev[0]) * i / (k + 1)), int(prev[1] + (p[1] - prev[1]) * i / (k + 1))))
            dense.append(tuple(p))
            prev = p
        PUSH["route"] = dense
        log("push route: " + " ".join("%d,%d" % p for p in dense))
    route = PUSH["route"]
    if PUSH["t"] < 0:
        play.select_army()
    else:  # (later pushes: only the units at home; the ones out already keep their way)
        play.go(int(base["x"]), int(base["z"]))
        play.set_queue(False)
        play.deselect(play.read_state())
        t = play.tile("R", "local_units", "LOCAL UNITS")
        if t:
            play.tap(*t[1], why="LOCAL UNITS")
    play.order("Fight", route[0])
    play.set_queue(True)
    for p in route[1:]:
        play.order("Fight", p)
    play.set_queue(False)
    PUSH["t"] = st["t"]
    log("t %d:%02d push: %d units, Fight to %d,%d" % (st["t"] // 60, st["t"] % 60, len(army), target[0], target[1]))
    print("  auto: push with %d units to %d,%d" % (len(army), target[0], target[1]))
    return True


CONS_RULE = {"t": -999}


def cons_rule(play, st):
    # fewer than 2 constructors alive (none being built): a Bot Lab puts 2 at its queue's front (INSERT)
    cons = [u for u in st["u"] if u["d"] in CONS]
    if len(cons) >= 2 or st["t"] - CONS_RULE["t"] < 90:
        return False
    lab = next((u for u in st["u"] if u["d"] == "armlab" and u["built"] >= 100), None)
    if not lab or not select(play, lab["id"]):
        return False
    play.tap(270, 1367, why="INSERT")
    play.fac("armck", 2)
    play.tap(270, 1367, why="INSERT off")
    CONS_RULE["t"] = st["t"]
    log("t %d:%02d lab #%d: 2 constructors first" % (st["t"] // 60, st["t"] % 60, lab["id"]))
    print("  auto: lab #%d -> 2 constructors first" % lab["id"])
    return True


def needs_sweep(st):
    if st["t"] - SWEEP["t"] < 45:
        return False
    if sum(1 for u in st["u"] if u["d"] in CONS) < 2 and st["t"] - CONS_RULE["t"] >= 90:
        return True
    if any(u["idle"] and u["built"] >= 100 and u["d"] in CONS + FACTORIES + ("armcom",) for u in st["u"]):
        return True
    c = conf()
    army = sum(1 for u in st["u"] if u["d"] in ARMY and u["built"] >= 100)
    return army >= c.get("push_at", 22) and st["t"] - PUSH["t"] >= c.get("push_every", 150)


def sweep(play, st):
    # every 45 game seconds: a builder or factory still idle (its job had failed, or a factory's queue ran out
    # without an idle event) gets a job; the game is paused meanwhile by the caller
    if st["t"] - SWEEP["t"] < 45:
        return False
    SWEEP["t"] = st["t"]
    idle = [u for u in st["u"] if u["idle"] and u["built"] >= 100 and u["d"] in CONS + FACTORIES + ("armcom",)
            and st["t"] - LAST_JOB.get(u["id"], -999) >= 45]
    for u in idle:
        handle_idle(play, "idle %s #%d" % (u["d"], u["id"]))
    built = cons_rule(play, play.read_state())
    pushed = push_rule(play, play.read_state())
    return bool(idle) or pushed or built


def handle_idle(play, pb, fresh_unit=False):
    m = re.match(r"idle (\S+) #(\d+)", pb)
    if not m:
        return False
    d, uid = m.group(1), int(m.group(2))
    if d not in CONS + FACTORIES + ("armcom",):
        return False
    st = play.read_state()
    u = next((v for v in st["u"] if v["id"] == uid), None)
    if not u or u["built"] < 100 or (not u["idle"] and not fresh_unit):
        return True  # (gone, unfinished or busy again: nothing to do, go on)
    last = LAST_JOB.get(uid)
    if last is not None and st["t"] - last < 20 and not fresh_unit:
        log("t %d: %s #%d idle again within 20 s: left idle" % (st["t"], d, uid))
        return True  # (its job failed at once, a placement refused: no loop of retries)
    LAST_JOB[uid] = st["t"]
    if not select(play, uid):
        log("t %d: could not select %s #%d" % (st["t"], d, uid))
        return True
    if d not in FACTORIES:  # (a fresh constructor's Patrol from its factory never ends: cleared before the job)
        play.order("Stop")
    if d in CONS:
        what = con_job(play, st, u)
    elif d in FACTORIES:
        what = factory_job(play, st, u)
    else:
        what = commander_job(play, st, u)
    play.set_queue(False)
    log("t %d:%02d %s #%d -> %s" % (st["t"] // 60, st["t"] % 60, d, uid, what))
    print("  auto: %s #%d -> %s" % (d, uid, what))
    return True
