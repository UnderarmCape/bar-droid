# The touch playtest's driver (research report "Touch playtest agent approach": text eyes, touch hands). It reads the
# game from the dev widget dev_playstate.lua (LuaUI/Config/bardroid_playstate.txt on the dev phone) and acts only
# through touches on the app's own controls, sent by touchd.py's virtual finger (started here when it is not running).
#   play.py setup | teardown               before and after a playtest, the app stopped (README.md)
#   play.py state                          the state, summed up (+ the last events)
#   play.py run <s>                        the game runs up to <s> s; the widget pauses it at once on an event
#   play.py tap X Y [why] | dtap X Y | hold X Y [ms] | drag X Y X2 Y2 [ms] | pinch X Y D1 D2 [ms]
#   play.py look [map|dock|all] [name]     a screenshot, halved, as a JPEG (for the eyes: probes, checks)
#   play.py sel <def>...                   a double tap on a unit of that type on the screen (QUEUE off first)
#   play.py selid <id>...                  a tap on each of those units (the second and on with QUEUE on: added)
#   play.py build <def> x,z [x,z...]       the selected builder's tile picked in the dock, each spot placed
#   play.py order <name> [x,z]             an order button by its name (the order menu's), then a map point
#   play.py go x,z                         the camera to a world point by finger drags on the map
#   play.py fac <def> <n>                  the selected factory: <n> taps on that unit's tile
#   play.py autopause <kinds|none>         which events pause the game (lost,idle,enemy,comhit,done)
#   play.py queue on|off                   QUEUE (the sticky Shift)
import json, os, random, re, socket, subprocess, sys, time

PKG = "com.underarmcape.bardroid"
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:  # (python -I leaves the script's folder out: autopilot.py lives beside it)
    sys.path.append(HERE)
from playenv import ADB, DEV, WORK  # noqa: E402  (the toolchain's adb, the dev phone, the run files' folder)
PY = sys.executable
PW, PH = 1080, 2316
MAP_BOTTOM = 1190
PLACE = (805, 1800)
PLACE_X = (935, 2045)
QUEUE = (1000, 1382)
GRID = (12.7, 1459, 534, 2151)  # the dock's build grid, 3 x 4 tiles, phone pixels
BUILD = {}
for name in ("armck", "armack", "armlab", "armalab", "armap", "armaap", "armvp", "armcom"):
    p = os.path.join(WORK, "..", "units", name + ".txt")
    if os.path.exists(p):
        BUILD[name] = [l.split()[3] for l in open(p) if l.strip()]
BUILDERS = {"armck": "armck", "armack": "armack", "armcom": "armcom", "armca": "armca", "armaca": "armaca"}
FACT = ("armlab", "armalab", "armap", "armaap", "armvp", "armavp", "armhp", "armshltx")
CONS = ("armck", "armack", "armca", "armaca", "armcom", "armcv", "armacv", "armfark", "armnanotc")
SETTINGS = os.path.join(WORK, "playreq.json")


# ------------------------------------------------------------------------------------------------------------- the phone
def adb(*a, out=False):
    r = subprocess.run([ADB, "-s", DEV] + list(a), capture_output=True)
    return r.stdout if out else None


def key(code):
    adb("shell", "input keyevent " + code)


def touch(g, wait=True):
    for attempt in range(2):
        try:
            s = socket.create_connection(("127.0.0.1", 27183), timeout=3)
            s.sendall((json.dumps(g) + "\n").encode())
            r = json.loads(s.makefile().readline())
            s.close()
            if wait and r.get("ok"):
                time.sleep(r["ms"] / 1000.0 + 0.12)
            return r
        except OSError:
            if attempt:
                raise
            subprocess.Popen([PY, "-I", os.path.join(HERE, "touchd.py")], cwd=HERE,
                             creationflags=0x00000008 | 0x00000200,  # (detached: it outlives this call)
                             stdout=open(os.path.join(WORK, "touchd.out"), "a"), stderr=subprocess.STDOUT)
            time.sleep(3.0)


def tap(x, y, why="", wait=0.35, exact=False):
    touch({"g": "tap", "x": x, "y": y, "why": why, "exact": exact})
    time.sleep(wait)


def dtap(x, y, why=""):
    touch({"g": "dtap", "x": x, "y": y, "why": why})
    time.sleep(0.4)


def drag(x, y, x2, y2, ms=500, why="", exact=False, still=0):
    touch({"g": "drag", "x": x, "y": y, "x2": x2, "y2": y2, "ms": ms, "why": why, "exact": exact, "still": still})


# --------------------------------------------------------------------------------------------------------------- state
def read_state():
    for _ in range(6):
        raw = adb("exec-out", "run-as", PKG, "cat", "files/bar/LuaUI/Config/bardroid_playstate.txt", out=True)
        text = raw.decode("utf-8", "replace")
        if text.rstrip().endswith("end"):
            break
        time.sleep(0.25)
    st = {"u": [], "e": [], "m_": [], "p": {}, "sel": {}, "selN": 0, "ev": [], "o": {}, "paused_by": None}
    for line in text.splitlines():
        f = line.split()
        if not f:
            continue
        k = f[0]
        try:
            if k == "t":
                st["t"], st["paused"], st["speed"] = int(f[1]), f[2] == "1", float(f[3])
            elif k == "scr":
                st["vsx"], st["vsy"] = int(f[1]), int(f[2])
            elif k == "res":
                st["m"] = [float(v) for v in f[2:6]]
                st["en"] = [float(v) for v in f[7:11]]
            elif k == "shift":
                st["shift"] = f[1] == "1"
            elif k == "sel":
                st["selN"] = int(f[1])
                st["sel"] = dict((kv.split("=")[0], int(kv.split("=")[1])) for kv in f[2:])
            elif k == "active":
                st["active"] = f[1]
            elif k == "cam":
                st["cam"] = (int(f[1]), int(f[2]))
            elif k == "u":
                st["u"].append(dict(id=int(f[1]), d=f[2], x=int(f[3]), z=int(f[4]), s=pt(st, f[5], f[6]),
                                    hp=int(f[7]), idle=f[8] == "1", built=int(f[9]), q=int(f[10])))
            elif k == "e":
                st["e"].append(dict(id=int(f[1]), d=f[2], x=int(f[3]), z=int(f[4]), s=pt(st, f[5], f[6]),
                                    hp=int(f[7])))
            elif k == "m":
                st["m_"].append(dict(x=int(f[1]), z=int(f[2]), s=pt(st, f[3], f[4]), free=f[5] == "1"))
            elif k == "p":
                st["p"][f[1]] = pt(st, f[2], f[3])
                if f[2] != "-":
                    st.setdefault("praw", {})[f[1]] = scale(st, int(f[2]), int(f[3]))
            elif k == "o":
                st["o"][f[1].lower()] = scale(st, (int(f[2]) + int(f[4])) / 2, (int(f[3]) + int(f[5])) / 2)
            elif k == "sid":
                st["sid"] = [int(v) for v in f[1:]]
            elif k == "map":
                st["map"] = (int(f[1]), int(f[2]))
            elif k == "q":
                st.setdefault("q", []).append("#%s: %s" % (f[1], " ".join(f[2:]) or "(none)"))
            elif k == "f":
                st["f"] = [tuple(int(float(c)) for c in v.split(",")) for v in f[2:]]
            elif k == "c":  # (the dock's tiles, X-screen pixels from the top)
                st.setdefault("c", {})[(f[1], f[2].lower())] = (int(f[3]), int(f[4]), int(f[5]), int(f[6]))
            elif k == "ev":
                st["ev"].append((int(f[1]), f[2], " ".join(f[3:])))
            elif k == "paused_by":
                st["paused_by"] = " ".join(f[1:])
        except (ValueError, IndexError):
            pass
    st.setdefault("m", [0, 0, 0, 0])
    st.setdefault("en", [0, 0, 0, 0])
    return st


def scale(st, sx, sy):
    return int(sx * PW / st["vsx"]), int(sy * PH / st["vsy"])


def pt(st, sx, sy):
    if sx == "-":
        return None
    x, y = scale(st, int(sx), int(sy))
    if y > MAP_BOTTOM - 15 or y < 95 or x < 12 or x > PW - 70:  # (under the dock or the top bar, or on the rails)
        return None
    if (x - 910) ** 2 + (y - 1015) ** 2 < 85 ** 2 or (y > 1110 and x > 520):  # (the camera knob, the turn rail)
        return None
    if y < 95 or (y < 90 and x > 500):  # (the top bar's buttons)
        return None
    return (x, y)


def dist(a, b):
    return int(((a["x"] - b["x"]) ** 2 + (a["z"] - b["z"]) ** 2) ** 0.5)


def base_center(st):
    bs = [u for u in st["u"] if u["d"] in FACT] or st["u"] or [dict(x=0, z=0)]
    return dict(x=sum(u["x"] for u in bs) / len(bs), z=sum(u["z"] for u in bs) / len(bs))


def summary(st, events_since=None):
    m, e = st["m"], st["en"]
    o = ["t %d:%02d %s | M %d/%d +%.1f -%.1f | E %d/%d +%.0f -%.0f | QUEUE %s | sel %d %s | active %s | cam %s" % (
        st["t"] // 60, st["t"] % 60, "PAUSED" if st["paused"] else "running", m[0], m[1], m[2], m[3], e[0], e[1],
        e[2], e[3], "on" if st.get("shift") else "off", st["selN"],
        " ".join("%s=%d" % kv for kv in st["sel"].items()), st.get("active"), st.get("cam"))]
    groups = {}
    for u in st["u"]:
        groups.setdefault(u["d"], []).append(u)
    for d, us in sorted(groups.items(), key=lambda kv: (kv[0] not in FACT, kv[0] not in CONS, -len(kv[1]))):
        if d in CONS or d in FACT:
            o.append("  %s x%d: " % (d, len(us)) + "  ".join(
                "#%d%s%s%s%s@%s" % (u["id"], " IDLE" if u["idle"] else " q%d" % u["q"],
                                   "" if u["built"] >= 100 else " built%d%%" % u["built"],
                                   " hp%d" % u["hp"] if u["hp"] < 70 else "", "",
                                   "%d,%d" % u["s"] if u["s"] else "(%d,%d)" % (u["x"], u["z"])) for u in us))
        else:
            unb = [u for u in us if u["built"] < 100]
            hurt = [u for u in us if u["hp"] < 50]
            on = [u for u in us if u["s"]]
            cx = sum(u["x"] for u in us) // len(us)
            cz = sum(u["z"] for u in us) // len(us)
            o.append("  %s x%d at~%d,%d%s%s%s" % (d, len(us), cx, cz, " (%d unfinished)" % len(unb) if unb else "",
                                                 " (%d hurt)" % len(hurt) if hurt else "",
                                                 " on screen %d" % len(on) if on else ""))
    base = base_center(st)
    if st["e"]:
        eg = {}
        for u in st["e"]:
            eg.setdefault(u["d"], []).append(u)
        o.append("  ENEMY: " + "; ".join("%s x%d nearest %d (%d,%d)%s" % (
            d, len(us), dist(n, base), n["x"], n["z"], " @%d,%d" % n["s"] if n["s"] else "")
            for d, us in sorted(eg.items(), key=lambda kv: min(dist(u, base) for u in kv[1]))
            for n in [min(us, key=lambda u: dist(u, base))]))
    free = sorted([s for s in st["m_"] if s["free"]], key=lambda s: dist(s, base))
    o.append("  free metal %d, nearest: " % len(free) + " ".join(
        "%d,%d%s" % (s["x"], s["z"], "@%d,%d" % s["s"] if s["s"] else "") for s in free[:8]))
    if st["o"]:
        o.append("  orders: " + " ".join("%s@%d,%d" % (k, v[0], v[1]) for k, v in st["o"].items()))
    for q in st.get("q", []):
        o.append("  queue " + q)
    evs = st["ev"] if events_since is None else [e for e in st["ev"] if e[0] >= events_since]
    evs = [e for e in evs if e[1] != "done"] + [e for e in evs if e[1] == "done"][-6:]
    if evs:
        o.append("  events: " + "; ".join("%d:%02d %s %s" % (e[0] // 60, e[0] % 60, e[1], e[2]) for e in evs[-14:]))
    if st["paused_by"]:
        o.append("  PAUSED BY: " + st["paused_by"])
    return "\n".join(o)


# ----------------------------------------------------------------------------------------------------------- requests
def settings():
    try:
        return json.load(open(SETTINGS))
    except (OSError, ValueError):
        return {"autopause": "lost,idle,enemy,comhit", "near": 1600}


def push_req(points=None):
    s = settings()
    body = "autopause %s\nnear %d\n" % (s["autopause"], s["near"])
    for t, (x, z) in (points or {}).items():
        body += "p %s %d %d\n" % (t, x, z)
    tmp = os.path.join(WORK, "playreq.txt")
    open(tmp, "w", newline="\n").write(body)
    adb("push", tmp, "/data/local/tmp/bardroid-playreq.txt")
    adb("shell", "run-as %s sh -c 'cat /data/local/tmp/bardroid-playreq.txt > files/bar/LuaUI/Config/bardroid_playreq.txt'"
        % PKG)


def ask(points):
    push_req(points)
    time.sleep(0.8)
    return read_state()["p"]


# -------------------------------------------------------------------------------------------------------------- acting
def set_queue(on):
    st = read_state()
    if not st["selN"]:  # (nothing selected: QUEUE is not on the dock; that place is the energy bar then)
        return
    if bool(st.get("shift")) != on:
        tap(*QUEUE, why="QUEUE " + ("on" if on else "off"), exact=True)


def deselect(st=None):
    # (a tap on bare ground clears the selection: the ground found by the widget's own test, near the camera's
    # middle; Android's Back opens BAR's lobby over the game instead)
    st = st or read_state()
    if not st["selN"]:
        return
    cam = st.get("cam") or (0, 0)
    for s in find_spots("armfus", cam[0], cam[1], 3, 160):  # (a fusion's room: bare ground well clear of units)
        p = ask({"d": s}).get("d")
        if p:
            tap(*p, why="deselect", exact=True)
            return
    tap(*free_spot(st), why="deselect")


def free_spot(st):
    taken = [u["s"] for u in st["u"] + st["e"] if u["s"]] + [s["s"] for s in st["m_"] if s["s"]]
    for y in range(320, MAP_BOTTOM - 160, 70):
        for x in range(200, 840, 70):
            if all(abs(x - a) > 80 or abs(y - b) > 80 for a, b in taken):
                return x, y
    return 540, 160


def sel(defs):
    set_queue(False)
    st = read_state()
    deselect(st)
    first = True
    for d in defs:
        us = [u for u in st["u"] if u["d"] == d and u["s"]]
        if not us:
            print("none on the screen:", d)
            continue
        if not first:
            set_queue(True)
        touch({"g": "dtap", "x": us[0]["s"][0], "y": us[0]["s"][1], "why": "select all " + d, "exact": True})
        time.sleep(0.4)
        first = False
    set_queue(False)
    print(summary(read_state()).splitlines()[0])


def selid(ids):
    set_queue(False)
    st = read_state()
    deselect(st)
    for k, i in enumerate(ids):
        u = next((u for u in st["u"] if u["id"] == i), None)
        if u and not u["s"] and k == 0:  # (the first unit brought onto the screen by panning)
            go(u["x"], u["z"])
            st = read_state()
            u = next((v for v in st["u"] if v["id"] == i), None)
        if not u or not u["s"]:
            print("not on the screen:", i)
            continue
        if k == 1:
            set_queue(True)
        s = u["s"]
        if u["d"] in FACT:  # (its new units stand in its middle: the corners of the building are the factory alone)
            for ox, oz in ((0, -40), (-40, -40), (40, -40), (-44, 0), (44, 0)):
                c = ask({"b": (u["x"] + ox, u["z"] + oz)}).get("b")
                if not c:
                    continue
                tap(*c, why="select #%d" % i, exact=True)
                if read_state()["sel"].get(u["d"]):
                    break
                deselect()
            continue
        tap(*s, why="select #%d" % i, exact=True)
    set_queue(False)
    print(summary(read_state()).splitlines()[0])


def grid_cell(row_vis, col):
    w, h = (GRID[2] - GRID[0]) / 3, (GRID[3] - GRID[1]) / 4
    return GRID[0] + (col + 0.5) * w, GRID[1] + (row_vis + 0.5) * h


def options_of(st):
    for k in st["sel"]:
        if k in BUILD:
            return k, BUILD[k]
        if k in BUILDERS and BUILDERS[k] in BUILD:
            return k, BUILD[BUILDERS[k]]
    return None, []


HALF_TOP, HALF_BOTTOM = 1268, 1870  # (the upright dock's halves, X-screen pixels from the top)
HALF_X = {"L": 237, "R": 699}


def tile(side, name, why):
    # a dock tile by its name, scrolled into its half first (slow drags settle on whole rows; a flick brings a page)
    missing = 0
    for _ in range(10):
        st = read_state()
        c = st.get("c", {}).get((side, name.lower())) or st.get("c", {}).get((side, "pregame:" + name.lower()))
        if not c:
            missing += 1
            if missing < 4:  # (the dock fills its halves a moment after the selection changes)
                time.sleep(0.6)
                continue
            print("no tile %s %s; shown: %s" % (side, name, " ".join(n for s, n in st.get("c", {}) if s == side)))
            return None
        x1, y1, x2, y2 = c
        if y1 >= HALF_TOP - 6 and y2 <= HALF_BOTTOM + 6:
            return st, scale(st, (x1 + x2) / 2, (y1 + y2) / 2)
        hx = scale(st, HALF_X[side], 0)[0]
        if y2 > HALF_BOTTOM:  # (below: the rows up)
            rows = min(3, max(1, round((y2 - HALF_BOTTOM) / (y2 - y1 + 6))))
            a, b = 2000, 2000 - rows * 175
        else:
            rows = min(3, max(1, round((HALF_TOP - y1) / (y2 - y1 + 6))))
            a, b = 1500, 1500 + rows * 175
        drag(hx, a, hx, b, 900 + 300 * rows, why="dock rows for " + why, exact=True, still=200)
        time.sleep(0.9)
    return None


SEA_TWIN = {"armtide": "armsolar", "armfmkr": "armmakr", "armsy": "armlab", "armtl": "armllt", "armfrad": "armrad",
            "armfrt": "armrl", "armfdrag": "armdrag", "armuwms": "armmstor", "armuwes": "armestor", "armfhp": "armhp",
            "armuwmex": "armmex"}


def pick(d):
    for attempt in range(3):
        t = tile("L", d, "pick " + d)
        if not t:
            return False
        st, (x, y) = t
        if ("L", "pregame:" + d) in st.get("c", {}):  # (pre-game: BAR's own queue, no active command to check)
            tap(x, y, why="pick " + d, wait=0.5)
            return True
        if st.get("active") != d:
            tap(x, y, why="pick " + d, wait=0.5)
        got = read_state().get("active")
        if got == d or SEA_TWIN.get(got) == d:  # (BAR's menu arms the sea twin while the pointer last stood over
            return True  # water; the spot's tap on land swaps it back, the land building is queued)
        if d in ("armmex", "cormex") and got in (None, "-"):  # (auto mex: the commander's spots in range queued
            print("auto mex took the pick")  # at once and the extractor put away; nothing to retry)
            return False
        print("picked %s for %s%s" % (got, d, ", again" if attempt < 2 else ""))
        if got not in (None, "-"):  # (the wrong one let go; the grid settles, its places read again)
            tap(*place_buttons()[1], why="let go of " + str(got), exact=True)
        hx = scale(read_state(), HALF_X["L"], 0)[0]  # (the grid back to its top by two slow drags down: its
        for _ in range(2):  # reported places and the drawn ones disagreed after a scroll)
            drag(hx, 1480, hx, 2000, 1200, why="grid to its top", exact=True, still=200)
            time.sleep(0.6)
        time.sleep(1.0)
    return False


def go(x, z):
    for _ in range(10):
        p = ask({"g": (x, z)}).get("g")
        if p and 220 < p[1] < 900 and 150 < p[0] < 840:
            return True
        if p and _ >= 2:  # (by a map edge the camera stops short of centring it: on the screen is enough)
            return True
        st = read_state()
        cam = st.get("cam")
        if not cam:
            return False
        push_req({"a": cam, "b": (cam[0] + 150, cam[1]), "c": (cam[0], cam[1] - 150)})
        time.sleep(0.8)
        q = read_state().get("praw", {})  # (unfiltered: an axis point under the dock still tells the direction)
        if not (q.get("a") and q.get("b") and q.get("c")):
            print("go: the camera's axes are not on the screen", cam, q)
            return False
        ax, ay = q["a"]
        bx, by = q["b"][0] - ax, q["b"][1] - ay
        cx, cy = q["c"][0] - ax, q["c"][1] - ay
        dx, dz = x - cam[0], z - cam[1]
        sx, sy = (bx * dx - cx * dz) / 150.0, (by * dx - cy * dz) / 150.0
        sx, sy = max(-430, min(430, sx)), max(-430, min(430, sy))
        drag(540, 640, 540 - sx, 640 - sy, 700, why="pan to %d,%d" % (x, z), exact=True)
        time.sleep(1.0)
    return False


def world_tap(x, z, why):
    p = ask({"s": (x, z)}).get("s")
    if not p:
        if not go(x, z):
            print("cannot bring %d,%d onto the screen" % (x, z))
            return False
        p = ask({"s": (x, z)}).get("s")
        if not p:
            return False
    tap(*p, why=why, wait=0.6)
    return True


def place_buttons(st=None):
    # PLACE and X below the shape strip (GRID's row): their place follows the dock's height (pre-game it is taller)
    st = st or read_state()
    g = st.get("c", {}).get(("R", "grid"))
    if not g:
        return PLACE, PLACE_X
    gx, gy = scale(st, (g[0] + g[2]) / 2, (g[1] + g[3]) / 2)
    return (805, gy + 198), (935, gy + 442)


def find_spots(d, x, z, n, gap):
    s = settings()
    body = "autopause %s\nnear %d\nf q %s %d %d %d %d\n" % (s["autopause"], s["near"], d, x, z, n, gap)
    tmp = os.path.join(WORK, "playreq.txt")
    open(tmp, "w", newline="\n").write(body)
    adb("push", tmp, "/data/local/tmp/bardroid-playreq.txt")
    adb("shell", "run-as %s sh -c 'cat /data/local/tmp/bardroid-playreq.txt > files/bar/LuaUI/Config/bardroid_playreq.txt'"
        % PKG)
    time.sleep(1.0)
    got = read_state().get("f", [])
    push_req()
    return got


def path(x1, z1, x2, z2):
    # the engine's path finder's waypoints for a Centurion from x1,z1 to x2,z2 (the dev widget's "w" request); asked
    # twice, as the first answer after a reload came back empty
    for _ in range(2):
        s = settings()
        body = "autopause %s\nnear %d\nw %d %d %d %d\n" % (s["autopause"], s["near"], x1, z1, x2, z2)
        tmp = os.path.join(WORK, "playreq.txt")
        open(tmp, "w", newline="\n").write(body)
        adb("push", tmp, "/data/local/tmp/bardroid-playreq.txt")
        adb("shell", "run-as %s sh -c 'cat /data/local/tmp/bardroid-playreq.txt > files/bar/LuaUI/Config/bardroid_playreq.txt'"
            % PKG)
        time.sleep(1.2)
        raw = adb("exec-out", "run-as", PKG, "cat", "files/bar/LuaUI/Config/bardroid_playstate.txt", out=True)
        pts = []
        for line in raw.decode("utf-8", "replace").splitlines():
            if line.startswith("w "):
                pts = [xz(v) for v in line.split()[1:]]
        push_req()
        if pts:
            return pts
    return []


def select_army(only=None):
    # ALL UNITS on the dock (combat land units), then one type's picture if asked
    set_queue(False)
    deselect(read_state())
    t = tile("R", "all_units", "ALL UNITS")
    if t:
        tap(*t[1], why="ALL UNITS")
        if only:
            t = tile("L", "type:" + only, "type " + only)
            if t:
                tap(*t[1], why="only " + only)
    return read_state()


def queued(st):
    ids = set(st.get("sid", []))
    return sum(u["q"] for u in st["u"] if u["id"] in ids)


def build_near(d, x, z, n, gap):
    spots = find_spots(d, x, z, n, gap)
    print("spots for %s near %d,%d: %s" % (d, x, z, " ".join("%d,%d" % p for p in spots)))
    if spots:
        build(d, spots)


def build(d, spots):
    st0 = read_state()
    q0 = queued(st0)
    if st0.get("active") not in (None, "-") and ("R", "grid") in st0.get("c", {}):
        # (one picked before, its place panel up: let go, or the pans below move it; pre-game that place is CORTEX)
        tap(*place_buttons(st0)[1], why="let go of " + str(st0.get("active")), exact=True)
    # (a building picked, a finger's drag on the map moves the building, not the camera: a spot off the screen is
    # reached by letting go, panning, and picking again)
    set_queue(True)
    picked = False
    for (x, z) in spots:
        p = ask({"s": (x, z)}).get("s")
        if not p:
            if picked:
                tap(*PLACE_X, why="let go to pan", exact=True)
                picked = False
            if not go(x, z):
                print("cannot bring %d,%d onto the screen" % (x, z))
                continue
            p = ask({"s": (x, z)}).get("s")
            if not p:
                continue
        if not picked:
            if not pick(d):
                return
            picked = True
            p = ask({"s": (x, z)}).get("s") or p
        tap(*p, why="spot for " + d, wait=0.6, exact=True)  # (finger noise is measured on the dock's buttons)
        tap(*place_buttons()[0], why="PLACE " + d, wait=0.5)
    if picked:
        tap(*place_buttons()[1], why="let go", exact=True)
    st = read_state()
    print("queued %d of %d %s" % (queued(st) - q0, len(spots), d))
    print(summary(st).splitlines()[0])


def order(name, xz=None):
    # (the target brought onto the screen first: with an order armed, a finger's drag on the map is the order's own
    # drag, a formation line, not a camera pan)
    if xz and not ask({"s": xz}).get("s"):
        st0 = read_state()
        queue_was = bool(st0.get("shift"))
        if st0.get("active") not in (None, "-"):  # (an order still armed, QUEUE on: a drag would draw its line,
            set_queue(False)  # not pan; QUEUE off lets go of it, put back after the pan)
        ok = go(*xz)
        if queue_was:
            set_queue(True)
        if not ok:
            print("cannot bring %d,%d onto the screen" % xz)
            return
    for attempt in range(2):
        t = tile("R", name, "order " + name)
        if not t:
            return
        tap(*t[1], why="order " + name, wait=0.45)
        if not xz or read_state().get("active") not in (None, "-"):  # (Stop, Wait: done at the tap)
            break
        print("order %s: not armed after the tap%s" % (name, ", again" if attempt == 0 else ""))
    else:
        return
    if xz:
        for attempt in range(3):  # (the order stays armed when its target tap did not take: tapped again)
            p = ask({"s": xz}).get("s")
            if p:
                tap(*p, why="target of " + name, wait=0.6, exact=True)
            st = read_state()
            if st.get("active") in (None, "-") or st.get("shift"):  # (with QUEUE on it stays armed: Shift held)
                break
            print("order %s: still armed after the target tap" % name)
    print(summary(read_state()).splitlines()[0])


def fac(d, n):
    t = tile("L", d, "queue " + d)
    if not t:
        return
    for _ in range(n):
        tap(*t[1], why="queue " + d, wait=0.3)
    print(summary(read_state()).splitlines()[0])


IGNORE = ("enemy corawac", "enemy armpeep", "enemy corfink", "enemy armawac", "enemy corhunt",  # (scouts)
          "lost armmex", "lost armmakr", "lost armrl", "lost armmoho", "lost armfig", "idle armap", "idle armalab", "idle armaap", "lost armhlt", "lost armnanotc", "lost armaak",
          "lost armsnipe", "lost armzeus", "lost armhawk", "lost armjeth", "lost armca", "lost armcir", "lost armflak", "lost armbeamer", "lost armllt", "lost armjeth", "lost armwin", "lost armsolar", "lost armdrag", "lost armrock", "lost armham", "lost armpw", "lost armwar",
          "lost armflea", "lost armjeth",  # (cheap losses: on)
          "enemy corhurc", "enemy corape", "enemy corvamp", "enemy corbw", "enemy corshad", "enemy corveng",
          "enemy cortitan", "enemy corcrw", "enemy ?", "enemy coratl", "enemy corvalk", "enemy corseah", "enemy corsb",
          "enemy corhvytrans", "enemy corca", "enemy coraca", "enemy critter")  # (aircraft: the anti-air answers them, not a decision)


FIGHT_MODE = False
AUTO_MODE = False
LAST_ENEMY_FILE = os.path.join(WORK, "last_enemy.json")
try:
    LAST_ENEMY = json.load(open(LAST_ENEMY_FILE))
except (OSError, ValueError):
    LAST_ENEMY = {}


def save_last_enemy():
    json.dump(LAST_ENEMY, open(LAST_ENEMY_FILE, "w"))
ENEMY_FACTORIES = ("corlab", "corvp", "corap", "coraap", "coralab", "coravp", "corhp", "corfhp", "corgant")


def run(seconds):
    st = read_state()
    t0 = st.get("t", 0)
    if st["paused"]:
        key("KEYCODE_BREAK")
    start = time.time()
    unexplained = 0
    time.sleep(1.0)
    while time.time() - start < seconds:
        st = read_state()
        over = [e for e in st["ev"] if e[1] == "gameover"]
        if over:
            print("GAME OVER: %s at %d:%02d" % (over[-1][2], over[-1][0] // 60, over[-1][0] % 60))
            break
        if AUTO_MODE:  # (a new constructor patrols from its factory and never idles: it gets its job when done)
            import autopilot
            if autopilot.needs_sweep(st):
                if not st["paused"]:
                    key("KEYCODE_BREAK")
                    time.sleep(0.8)
                autopilot.sweep(sys.modules[__name__], read_state())
                if read_state()["paused"]:
                    key("KEYCODE_BREAK")
                time.sleep(1.0)
                continue
            fresh = [e for e in st["ev"] if e[1] == "done" and e[2].split(" ")[0] in autopilot.CONS
                     and e[2] not in autopilot.assigned()]
            if fresh:
                if not st["paused"]:
                    key("KEYCODE_BREAK")
                    time.sleep(0.8)
                for e in fresh:
                    autopilot.mark_assigned(e[2])
                    autopilot.handle_idle(sys.modules[__name__], "idle " + e[2], fresh_unit=True)
                if read_state()["paused"]:
                    key("KEYCODE_BREAK")
                time.sleep(1.0)
                continue
        if st["paused"]:
            pb = st["paused_by"] or ""
            if not pb:  # (the pause's reason is written a moment later; none at all: not the widget's, go on)
                time.sleep(0.7)
                st = read_state()
                if not st["paused"]:
                    continue
                pb = st["paused_by"] or ""
                if not pb:
                    unexplained += 1
                    if unexplained > 2:  # (paused again and again by nothing of ours: the game's end, say)
                        print("paused with no reason three times: stopped")
                        break
                    key("KEYCODE_BREAK")
                    time.sleep(1.0)
                    continue
            if AUTO_MODE and pb.startswith("idle "):  # (the standing rules give an idle builder its next job)
                import autopilot
                if autopilot.handle_idle(sys.modules[__name__], pb):
                    if read_state()["paused"]:
                        key("KEYCODE_BREAK")
                    time.sleep(1.0)
                    continue
            go_on = pb.startswith(IGNORE)
            m = re.match(r"enemy (\S+) #\d+ at (-?\d+),(-?\d+)", pb)
            if FIGHT_MODE and not pb.startswith(("comhit", "lost armcom", "lost armlab", "lost armalab", "lost armap",
                                                 "lost armaap", "lost armfus", "lost armckfus")) and not (
                    m and m.group(1) in ENEMY_FACTORIES):
                go_on = True  # (a fight: only the commander, the big buildings and an enemy factory stop the run)
            if m and m.group(1) not in ENEMY_FACTORIES:  # (an enemy seen far from the base: no decision; a factory
                b = base_center(st)  # or anything near the base stops the run)
                if ((int(m.group(2)) - b["x"]) ** 2 + (int(m.group(3)) - b["z"]) ** 2) ** 0.5 > 1500:
                    go_on = True
            if m and not go_on and st["t"] - LAST_ENEMY.get("t", -99) < 15:
                go_on = True  # (the same wave: one stop for it, not one per unit)
            if m:
                LAST_ENEMY["t"] = st["t"]
                save_last_enemy()
            if go_on:
                key("KEYCODE_BREAK")
                time.sleep(1.0)
                continue
            break
        time.sleep(0.5)
    else:
        if not read_state()["paused"]:  # (an event may have paused it a moment ago: the pause is a toggle)
            key("KEYCODE_BREAK")
            for _ in range(6):  # (the file is written twice a second: the pause shows a moment later)
                time.sleep(0.4)
                if read_state()["paused"]:
                    break
        st = read_state()
    print("ran %.0f s (game %d s)%s" % (time.time() - start, st["t"] - t0,
                                        "" if st["paused_by"] else ": time"))
    lines = summary(st, events_since=t0).splitlines()
    idle = [u for u in st["u"] if u["idle"] and u["built"] >= 100 and (u["d"] in CONS or u["d"] in FACT)]
    counts = {}
    for u in st["u"]:
        counts[u["d"]] = counts.get(u["d"], 0) + 1
    print(lines[0])
    print("  units: " + " ".join("%s=%d" % kv for kv in sorted(counts.items())))
    if idle:
        print("  idle: " + " ".join("%s#%d@%d,%d" % (u["d"], u["id"], u["x"], u["z"]) for u in idle))
    for l in lines[1:]:
        if l.strip().startswith(("ENEMY", "events", "PAUSED")):
            print(l)


def look(part="map", name=None):
    name = name or "look-" + time.strftime("%H%M%S")
    png = os.path.join(WORK, name + ".png")
    adb("shell", "screencap -p /data/local/tmp/bardroid-play.png")
    adb("pull", "/data/local/tmp/bardroid-play.png", png)
    crop = {"map": (0, 0, 1080, 1195), "dock": (0, 1195, 1080, 2316), "all": (0, 0, 1080, 2316)}[part]
    out = os.path.join(WORK, name + "-s.jpg")
    ps = ("Add-Type -AssemblyName System.Drawing; $i=[Drawing.Image]::FromFile('%s'); $r=New-Object Drawing.Rectangle "
          "%d,%d,%d,%d; $w=[int]($r.Width/2); $h=[int]($r.Height/2); $b=New-Object Drawing.Bitmap $w,$h; "
          "$g=[Drawing.Graphics]::FromImage($b); $g.InterpolationMode='HighQualityBicubic'; "
          "$g.DrawImage($i,(New-Object Drawing.Rectangle 0,0,$w,$h),$r,[Drawing.GraphicsUnit]::Pixel); "
          "$b.Save('%s',[Drawing.Imaging.ImageFormat]::Jpeg); $i.Dispose()" % (
              png, crop[0], crop[1], crop[2] - crop[0], crop[3] - crop[1], out))
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True)
    print(out, "(half size: double its coordinates%s)" % (", +1195 in y" if part == "dock" else ""))


def xz(a):
    x, z = a.split(",")
    return int(float(x)), int(float(z))


# ------------------------------------------------------------------------------------- before and after a playtest
PREFS = "shared_prefs/bardroid.xml"
PREFS_BEFORE = os.path.join(WORK, "prefs-before.txt")
PLAY_PREFS = {"portrait": "true", "turnWithPhone": "false"}  # (the driver's pixel positions are the upright dock's)


def prefs_get():
    xml = adb("shell", "run-as %s cat %s" % (PKG, PREFS), out=True).decode("utf-8", "replace")
    got = {}
    for k in PLAY_PREFS:
        m = re.search(r'name="%s" value="(true|false)"' % k, xml)
        if m:
            got[k] = m.group(1)
    return got


def prefs_set(values):
    sed = " ".join("-e 's/name=.%s. value=.(true|false)./name=\"%s\" value=\"%s\"/'" % (k, k, v)
                   for k, v in values.items())
    adb("shell", "run-as %s sed -i -E %s %s" % (PKG, sed, PREFS))


def setup():
    if not os.path.exists(PREFS_BEFORE):  # (a second setup keeps the first one's saved values)
        json.dump(prefs_get(), open(PREFS_BEFORE, "w"))
    prefs_set(PLAY_PREFS)
    adb("push", os.path.join(HERE, "dev_playstate.lua"), "/data/local/tmp/dev_playstate.lua")
    adb("shell", "run-as %s cp /data/local/tmp/dev_playstate.lua files/bar/LuaUI/Widgets/dev_playstate.lua" % PKG)
    print("set up:", prefs_get(), "(the player's before:", open(PREFS_BEFORE).read() + ")")


def teardown():
    adb("shell", "run-as %s rm -f files/bar/LuaUI/Widgets/dev_playstate.lua files/bar/LuaUI/Config/bardroid_playstate.txt "
        "files/bar/LuaUI/Config/bardroid_playreq.txt" % PKG)
    if os.path.exists(PREFS_BEFORE):
        before = json.load(open(PREFS_BEFORE))
        if before:
            prefs_set(before)
        os.remove(PREFS_BEFORE)
    try:  # (the virtual finger closed: its touchscreen goes away with it)
        s = socket.create_connection(("127.0.0.1", 27183), timeout=2)
        s.sendall(b'{"g": "quit"}\n')
        s.close()
    except OSError:
        pass
    print("torn down:", prefs_get())


def main():
    a = sys.argv[1:]
    c = a[0] if a else "state"
    if c == "state":
        print(summary(read_state()))
    elif c == "units":
        for u in read_state()["u"]:
            print(u)
    elif c == "enemies":
        for u in read_state()["e"]:
            print(u)
    elif c == "run":
        global FIGHT_MODE, AUTO_MODE
        FIGHT_MODE = "fight" in a[2:]
        AUTO_MODE = "auto" in a[2:]
        run(float(a[1]) if len(a) > 1 else 30)
    elif c == "tap":
        tap(int(a[1]), int(a[2]), why=" ".join(a[3:]))
    elif c == "dtap":
        dtap(int(a[1]), int(a[2]))
    elif c == "hold":
        touch({"g": "hold", "x": int(a[1]), "y": int(a[2]), "ms": int(a[3]) if len(a) > 3 else 800})
    elif c == "drag":
        drag(int(a[1]), int(a[2]), int(a[3]), int(a[4]), int(a[5]) if len(a) > 5 else 500)
    elif c == "pinch":
        touch({"g": "pinch", "x": int(a[1]), "y": int(a[2]), "d1": int(a[3]), "d2": int(a[4]),
               "ms": int(a[5]) if len(a) > 5 else 500})
    elif c == "key":
        key(a[1])
    elif c == "setup":  # (the app stopped: upright, not turning with the phone, the dev widget in place)
        setup()
    elif c == "teardown":  # (the app stopped: the dev widget and its files gone, the player's settings back)
        teardown()
    elif c == "reload":  # (the dev widget pushed again and LuaUI reloaded through the chat box: /luaui reload)
        adb("push", os.path.join(HERE, "dev_playstate.lua"), "/data/local/tmp/dev_playstate.lua")
        adb("shell", "run-as %s cp /data/local/tmp/dev_playstate.lua files/bar/LuaUI/Widgets/dev_playstate.lua" % PKG)
        set_queue(False)
        key("KEYCODE_ENTER")
        time.sleep(0.7)
        adb("shell", "input text /luaui%sreload")
        time.sleep(2.5)  # (an Enter right after the text left it unsent in the chat box, twice)
        key("KEYCODE_ENTER")
        time.sleep(9)
        if not read_state()["paused"]:
            key("KEYCODE_BREAK")
            time.sleep(0.8)
        print(summary(read_state()).splitlines()[0])
    elif c == "pause":  # (BAR's pause is a toggle: pressed only when the game runs)
        if not read_state()["paused"]:
            key("KEYCODE_BREAK")
            time.sleep(0.8)
        print(summary(read_state()))
    elif c == "sel":
        sel(a[1:])
    elif c == "selid":
        selid([int(v) for v in a[1:]])
    elif c == "build":
        build(a[1], [xz(s) for s in a[2:]])
    elif c == "near":  # near <def> x,z <n> [gap]: free spots found by the widget, then built
        build_near(a[1], *xz(a[2]), int(a[3]) if len(a) > 3 else 1, int(a[4]) if len(a) > 4 else 64)
    elif c == "order":
        order(a[1], xz(a[2]) if len(a) > 2 else None)
    elif c == "path":  # path x1,z1 x2,z2: the waypoints a Centurion would walk (the engine's path finder)
        (x1, z1), (x2, z2) = xz(a[1]), xz(a[2])
        print("w " + " ".join("%d,%d" % p for p in path(x1, z1, x2, z2)))
    elif c == "area":  # area <order> x,z <radius px>: the order armed, then a drag out from the middle (BAR's circle)
        cx, cz = xz(a[2])
        if not ask({"s": (cx, cz)}).get("s"):
            go(cx, cz)
        t = tile("R", a[1], "area " + a[1])
        if t:
            tap(*t[1], why="order " + a[1], wait=0.45)
            p = ask({"s": (cx, cz)}).get("s")
            if p and read_state().get("active") not in (None, "-"):
                r = int(a[3]) if len(a) > 3 else 150
                drag(p[0], p[1], min(PW - 80, p[0] + r), p[1], 700, why="area " + a[1], exact=True)
            else:
                print("area %s: not armed or no point" % a[1])
        print(summary(read_state()).splitlines()[0])
    elif c == "fac":
        fac(a[1], int(a[2]) if len(a) > 2 else 1)
    elif c == "go":
        print(go(*xz(a[1])))
    elif c == "army":  # army <def>: ALL UNITS on the dock, then that type's picture: only that type stays selected
        print(summary(select_army(a[1] if len(a) > 1 else None)).splitlines()[0])
    elif c == "home":  # (nothing selected: the dock's home page, e.g. commander, factories, all_units, local_units)
        set_queue(False)
        st = read_state()
        deselect(st)
        t = tile("R", a[1], "home " + a[1])
        if t:
            tap(*t[1], why="home " + a[1])
        print(summary(read_state()).splitlines()[0])
    elif c == "spots":  # free metal spots, nearest first, with the margin to the scenario's ground defences
        rng = {"corllt": 435, "corhllt": 600, "corhlt": 650, "cordoom": 950, "corvipe": 730}
        defs = []
        p = os.path.join(WORK, "defenses.txt")
        if os.path.exists(p):
            for line in open(p):
                d, x, z = line.split()
                if d in rng:
                    defs.append((int(x), int(z), rng[d], d))
        st = read_state()
        base = base_center(st)
        alive = set((e["x"] // 64, e["z"] // 64) for e in st["e"])
        rows = []
        for s in st["m_"]:
            if not s["free"]:
                continue
            m = min([int(((s["x"] - x) ** 2 + (s["z"] - z) ** 2) ** 0.5) - r for x, z, r, d in defs] or [9999])
            rows.append((dist(s, base), s["x"], s["z"], m))
        for dd, x, z, m in sorted(rows):
            print("%5d,%-5d base %5d  margin %5d %s" % (x, z, dd, m, "SAFE" if m > 150 else "danger"))
    elif c == "box":  # box x1,z1 x2,z2 [def]: the app's tap-then-drag selection box over that ground (units only);
        # with a def, then only that type kept (its picture in the dock)
        p1, p2 = xz(a[1]), xz(a[2])
        go((p1[0] + p2[0]) // 2, (p1[1] + p2[1]) // 2)
        q = ask({"a": p1, "b": p2})
        if q.get("a") and q.get("b"):
            set_queue(False)
            touch({"g": "tapdrag", "x": q["a"][0], "y": q["a"][1], "x2": q["b"][0], "y2": q["b"][1], "ms": 450,
                   "why": "box select", "exact": True})
            time.sleep(0.6)
            if len(a) > 3:
                t = tile("L", "seltype:" + a[3], "only " + a[3]) or tile("L", "type:" + a[3], "only " + a[3])
                if t:
                    tap(*t[1], why="only " + a[3])
        else:
            print("box corners not on the screen", q)
        print(summary(read_state()).splitlines()[0])
    elif c == "lp":  # lp x,z [x,z ...]: a long press on each map point: the default order there (a move; on an enemy,
        # an attack); QUEUE on for more than one; each point brought onto the screen first
        pts = [xz(v) for v in a[1:]]
        if len(pts) > 1:
            set_queue(True)
        for p in pts:
            q = ask({"s": p}).get("s")
            if not q:
                go(*p)
                q = ask({"s": p}).get("s")
            if q:
                touch({"g": "hold", "x": q[0], "y": q[1], "ms": 750, "why": "long press %d,%d" % p, "exact": True})
                time.sleep(0.4)
            else:
                print("cannot bring %d,%d onto the screen" % p)
        set_queue(False)
        print(summary(read_state()).splitlines()[0])
    elif c == "lpe":  # lpe <enemy id>: a long press on that enemy unit (an attack order)
        st = read_state()
        e = next((u for u in st["e"] if u["id"] == int(a[1])), None)
        if not e:
            print("enemy not seen:", a[1])
        else:
            if not e["s"]:
                go(e["x"], e["z"])
                st = read_state()
                e = next((u for u in st["e"] if u["id"] == int(a[1])), e)
            if e["s"]:
                touch({"g": "hold", "x": e["s"][0], "y": e["s"][1], "ms": 750, "why": "attack #" + a[1], "exact": True})
            print(summary(read_state()).splitlines()[0])
    elif c == "ask":
        pts = dict(("q%d" % i, xz(v)) for i, v in enumerate(a[1:]))
        r = ask(pts)
        st = read_state()
        print(r, "cam", st.get("cam"))
    elif c == "wtap":
        world_tap(*xz(a[1]), why=" ".join(a[2:]))
    elif c == "look":
        look(a[1] if len(a) > 1 else "map", a[2] if len(a) > 2 else None)
    elif c == "queue":
        set_queue(a[1] == "on")
    elif c == "pick":
        print(pick(a[1]))
    elif c == "autopause":
        s = settings()
        s["autopause"] = a[1]
        if len(a) > 2:
            s["near"] = int(a[2])
        json.dump(s, open(SETTINGS, "w"))
        push_req()
        print(s)
    else:
        print(open(__file__).read().split("import json")[0])


if __name__ == "__main__":
    main()
