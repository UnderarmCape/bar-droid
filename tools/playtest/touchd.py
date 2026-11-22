# The touch playtest's finger (research report "Touch playtest agent approach", step 1): one virtual touchscreen on the
# dev phone (Android's `uinput -`, kept open through one adb shell), fed gestures with a finger's timing and a little
# noise, so the app's own touch layer (RtsTouch) classifies every touch as it does a real finger's. Gestures come from
# play.py over 127.0.0.1:27183 as JSON lines; each is logged to touchlog.csv (intent, target, points sent, timing).
#   python -I touchd.py            (runs until killed; play.py starts it when it is not running)
# Gestures: {"g":"tap","x":..,"y":..,"why":".."}  {"g":"dtap",...}  {"g":"hold","x","y","ms"}
#           {"g":"drag","x","y","x2","y2","ms"}  {"g":"pinch","x","y","d1","d2","ms"}  {"g":"exact": true} turns noise off
import json, os, random, socket, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(HERE)  # (python -I leaves the script's folder out)
from playenv import ADB, DEV, WORK  # noqa: E402
PORT = 27183
W, H = 1080, 2316
PX_PER_MM = 15.5  # (the S23 Ultra at 1080 x 2316: about 395 pixels an inch)
NOISE_MM = 0.8  # a finger's spread around its aim (sigma), clipped at 2.5 sigma

REGISTER = {"id": 9, "command": "register", "name": "Playtest Finger", "vid": 4660, "pid": 22138, "bus": "usb",
            "configuration": [{"type": "UI_SET_EVBIT", "data": [1, 3]}, {"type": "UI_SET_KEYBIT", "data": [330]},
                              {"type": "UI_SET_ABSBIT", "data": [47, 48, 53, 54, 57, 58]},
                              {"type": "UI_SET_PROPBIT", "data": [1]}],
            "abs_info": [{"code": 47, "info": {"value": 0, "minimum": 0, "maximum": 9, "fuzz": 0, "flat": 0, "resolution": 0}},
                         {"code": 48, "info": {"value": 0, "minimum": 0, "maximum": 255, "fuzz": 0, "flat": 0, "resolution": 0}},
                         {"code": 53, "info": {"value": 0, "minimum": 0, "maximum": W - 1, "fuzz": 0, "flat": 0, "resolution": 0}},
                         {"code": 54, "info": {"value": 0, "minimum": 0, "maximum": H - 1, "fuzz": 0, "flat": 0, "resolution": 0}},
                         {"code": 57, "info": {"value": 0, "minimum": 0, "maximum": 65535, "fuzz": 0, "flat": 0, "resolution": 0}},
                         {"code": 58, "info": {"value": 0, "minimum": 0, "maximum": 255, "fuzz": 0, "flat": 0, "resolution": 0}}]}


class Finger:
    def __init__(self):
        self.proc = None
        self.track = 100
        self.lock = threading.Lock()
        self.open()

    def open(self):
        self.proc = subprocess.Popen([ADB, "-s", DEV, "shell", "uinput -"], stdin=subprocess.PIPE,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.send({"__raw": REGISTER})
        time.sleep(1.5)  # (the device registers asynchronously; commands before it is ready are lost)

    def send(self, cmd):
        line = json.dumps(cmd["__raw"] if "__raw" in cmd else cmd) + "\n"
        try:
            self.proc.stdin.write(line.encode())
            self.proc.stdin.flush()
        except OSError:
            self.open()
            self.proc.stdin.write(line.encode())
            self.proc.stdin.flush()

    def inject(self, ev):
        self.send({"id": 9, "command": "inject", "events": ev})

    def delay(self, ms):
        self.send({"id": 9, "command": "delay", "duration": int(ms)})

    def down(self, slot, x, y):
        self.track += 1
        return [3, 47, slot, 3, 57, self.track, 3, 53, int(x), 3, 54, int(y), 3, 48, 6, 3, 58, 40]

    @staticmethod
    def move(slot, x, y):
        return [3, 47, slot, 3, 53, int(x), 3, 54, int(y)]

    @staticmethod
    def up(slot):
        return [3, 47, slot, 3, 57, -1]


def noisy(x, y, exact):
    if exact:
        return x, y
    s = NOISE_MM * PX_PER_MM
    dx = max(-2.5 * s, min(2.5 * s, random.gauss(0, s)))
    dy = max(-2.5 * s, min(2.5 * s, random.gauss(0, s)))
    return max(0, min(W - 1, x + dx)), max(0, min(H - 1, y + dy))


def path(x, y, x2, y2, ms):
    n = max(2, int(ms / 16))
    pts = []
    for i in range(1, n + 1):
        t = i / n
        e = t * t * (3 - 2 * t)  # (a finger speeds up and slows down)
        pts.append((x + (x2 - x) * e, y + (y2 - y) * e))
    return pts, ms / n


def gesture(f, g):
    kind = g["g"]
    exact = g.get("exact", False)
    sent = []
    total = 0
    with f.lock:
        # (delays run against a time base: after an idle gap every delay would already be due and the gesture would
        # arrive at once, a fling with no time in it; the base set again first)
        f.send({"id": 9, "command": "updateTimeBase"})
        if kind in ("tap", "dtap"):
            for k in range(2 if kind == "dtap" else 1):
                x, y = noisy(g["x"], g["y"], exact)
                dur = g.get("ms") or random.uniform(60, 130)
                f.inject(f.down(0, x, y) + [1, 330, 1, 0, 0, 0])
                f.delay(dur / 2)
                jx, jy = (x, y) if exact else (x + random.uniform(-2, 2), y + random.uniform(-2, 2))
                f.inject(f.move(0, jx, jy) + [0, 0, 0])
                f.delay(dur / 2)
                f.inject(f.up(0) + [1, 330, 0, 0, 0, 0])
                sent.append((round(x), round(y), round(dur)))
                total += dur
                if kind == "dtap" and k == 0:
                    gap = random.uniform(70, 110)
                    f.delay(gap)
                    total += gap
        elif kind == "hold":
            x, y = noisy(g["x"], g["y"], exact)
            f.inject(f.down(0, x, y) + [1, 330, 1, 0, 0, 0])
            f.delay(g.get("ms", 800))
            f.inject(f.up(0) + [1, 330, 0, 0, 0, 0])
            sent.append((round(x), round(y), g.get("ms", 800)))
            total = g.get("ms", 800)
        elif kind == "drag":
            x, y = noisy(g["x"], g["y"], exact)
            x2, y2 = g["x2"] + (x - g["x"]), g["y2"] + (y - g["y"])
            ms = g.get("ms", 400)
            f.inject(f.down(0, x, y) + [1, 330, 1, 0, 0, 0])
            f.delay(g.get("settle", 40))
            pts, step = path(x, y, x2, y2, ms)
            for px, py in pts:
                f.inject(f.move(0, px, py) + [0, 0, 0])
                f.delay(step)
            rest = g.get("rest", 30)
            if g.get("still"):  # (the finger held still before it lifts: no fling; a few unmoved samples)
                for k in range(int(g["still"] / 16)):
                    f.inject(f.move(0, x2 + (k % 2), y2) + [0, 0, 0])
                    f.delay(16)
            f.delay(rest)
            f.inject(f.up(0) + [1, 330, 0, 0, 0, 0])
            sent.append((round(x), round(y), round(x2), round(y2), ms))
            total = ms + g.get("settle", 40) + g.get("rest", 30) + g.get("still", 0)
        elif kind == "tapdrag":  # the app's "tap then drag selects": a tap, then at once a drag from the same place
            x, y, x2, y2, ms = g["x"], g["y"], g["x2"], g["y2"], g.get("ms", 500)
            f.inject(f.down(0, x, y) + [1, 330, 1, 0, 0, 0])
            f.delay(70)
            f.inject(f.up(0) + [1, 330, 0, 0, 0, 0])
            f.delay(g.get("gap", 110))
            f.inject(f.down(0, x, y) + [1, 330, 1, 0, 0, 0])
            f.delay(40)
            pts, step = path(x, y, x2, y2, ms)
            for px, py in pts:
                f.inject(f.move(0, px, py) + [0, 0, 0])
                f.delay(step)
            for k in range(8):
                f.inject(f.move(0, x2 + (k % 2), y2) + [0, 0, 0])
                f.delay(16)
            f.inject(f.up(0) + [1, 330, 0, 0, 0, 0])
            sent.append((x, y, x2, y2, ms))
            total = 70 + g.get("gap", 110) + 40 + ms + 128
        elif kind == "pinch":  # two fingers on a line through (x, y), from d1 apart to d2 apart
            x, y, d1, d2, ms = g["x"], g["y"], g["d1"], g["d2"], g.get("ms", 500)
            f.inject(f.down(0, x - d1 / 2, y) + f.down(1, x + d1 / 2, y) + [1, 330, 1, 0, 0, 0])
            f.delay(40)
            n = max(2, int(ms / 16))
            for i in range(1, n + 1):
                d = d1 + (d2 - d1) * i / n
                f.inject(f.move(0, x - d / 2, y) + f.move(1, x + d / 2, y) + [0, 0, 0])
                f.delay(ms / n)
            f.inject(f.up(0) + f.up(1) + [1, 330, 0, 0, 0, 0])
            sent.append((x, y, d1, d2, ms))
            total = ms + 40
        else:
            return {"ok": False, "err": "unknown gesture " + kind}
    with open(os.path.join(WORK, "touchlog.csv"), "a") as log:
        log.write("%s,%s,%s,%s,%s,\"%s\"\n" % (time.strftime("%H:%M:%S"), kind, g.get("x"), g.get("y"),
                                               json.dumps(sent).replace(",", ";"), g.get("why", "")))
    return {"ok": True, "sent": sent, "ms": round(total)}


def main():
    f = Finger()
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(4)
    print("touchd ready on", PORT, flush=True)
    while True:
        c, _ = srv.accept()
        with c:
            buf = b""
            while not buf.endswith(b"\n"):
                d = c.recv(65536)
                if not d:
                    break
                buf += d
            for line in buf.decode().splitlines():
                if not line.strip():
                    continue
                try:
                    g = json.loads(line)
                    if g.get("g") == "quit":
                        c.sendall(b'{"ok":true}\n')
                        f.proc.stdin.close()
                        return
                    r = gesture(f, g)
                except Exception as e:  # (one bad request never ends the finger)
                    r = {"ok": False, "err": repr(e)}
                c.sendall((json.dumps(r) + "\n").encode())


if __name__ == "__main__":
    main()
