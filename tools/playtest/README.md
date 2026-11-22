# The touch playtest's driver (dev only, never in the APK)

An agent plays BAR on the dev phone through the app's own touch controls, as a player would (2026-11-21/22: six New
Beginning games and eleven 1v1 skirmishes, findings in [docs/PLAYTEST.md](../../docs/PLAYTEST.md); the approach:
`reports/Touch playtest agent approach.md`). Its eyes are text, its hands real touches:

- `dev_playstate.lua`: a dev widget (`files/bar/LuaUI/Widgets` on the phone, only during a playtest) that writes the
  game as text to `LuaUI/Config/bardroid_playstate.txt` (units, enemies seen, metal spots, queues, the dock's state)
  and pauses the game on the events asked for (lost, idle, enemy, comhit, done); requests come back through
  `bardroid_playreq.txt` (paths, pauses).
- `touchd.py`: one virtual touchscreen on the phone (Android's `uinput -` over one adb shell), fed gestures with a
  finger's timing and a little noise, so `RtsTouch` treats them as a finger's; each gesture logged to `touchlog.csv`.
- `play.py`: the driver (its header lists the commands: state, run, tap, build, order, go, fac, look, ...).
  `play.py setup` (app stopped) saves the player's Play upright / Turn with the phone, sets upright and not turning
  (the driver's pixel positions are the upright dock's on the S23 Ultra, 1080 x 2316) and puts the widget in place;
  `play.py teardown` (app stopped) removes the widget and its files, puts the settings back and closes the finger.
- `autopilot.py`: standing rules for `play.py run <s> auto` (idle constructors, the commander and factories get their
  next job by touch); settings `autopilot.json` (`autopilot-fortress.json`: turtling). `assign.py`: build plans for
  constructors standing close together. `restart-skirmish.ps1`: from a running game to the quick Skirmish's first page.

Run files (screenshots, the touch log, the autopilot's log, requests) go to `..\toolchain\tmp\play`
(`BARDROID_PLAY_DIR`), never into the repository; `playenv.py` finds the toolchain (`BARDROID_TOOLCHAIN`) and the
dev phone (`BARDROID_DEVICE`, else `..\phone-device.txt`). Python: the NDK's, with `-I`.

Rules: the dev phone only through `devphone-lock.ps1 take playtest` / `free playtest`; never the Fold7; the lobby
never logged in (offline skirmishes and scenarios only); `play.py teardown` before the lock is freed. Until the
release (docs/DELIVERY.md "Release candidate 0.2.0") it runs short feature tours that confirm fixes in play, not
open-ended matches.
