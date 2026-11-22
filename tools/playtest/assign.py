# Build plans for several constructors standing close together: each tap selects whichever is on top, so the plan
# given is the one of the unit actually selected (its id read back from the state), until every plan is given.
#   assign.py '<json: {"id": [["def", x, z], ...], ...}>'   (or a file path holding that json)
import json
import os
import sys

sys.argv = sys.argv[:1] + sys.argv[1:]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play  # noqa: E402

arg = sys.argv[1]
plans = json.load(open(arg)) if os.path.exists(arg) else json.loads(arg)
plans = {int(k): v for k, v in plans.items()}
done = set()
for attempt in range(3 * len(plans)):
    left = [i for i in plans if i not in done]
    if not left:
        break
    target = left[attempt % len(left)]
    play.selid([target])
    st = play.read_state()
    sid = st.get("sid", [])
    got = sid[0] if len(sid) == 1 else None
    if got not in plans or got in done:
        print("selected %s, not a constructor with a plan left" % sid)
        continue
    play.order("Stop")
    for d, x, z in plans[got]:
        play.build(d, [(int(x), int(z))])
    done.add(got)
    print("#%d: %s" % (got, " ".join("%s@%d,%d" % tuple(p) for p in plans[got])))
print("given: %s; not given: %s" % (sorted(done), sorted(set(plans) - done)))
