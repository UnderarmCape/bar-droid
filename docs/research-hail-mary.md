# Hail-mary research: how far can Sim time drop? (2026-10-27)

> **Online-safe only (Kailil, 2026-10-27 ~20:00):** "we MUST have online play enabled. so only do online safe
> adjustments. If our tests have singlpalyer only ajustments then cull those out and leave the online ones". Online
> play needs the official engine binary and BAR's own game archive, so every engine build, the overlay games (gadget
> trim, modrules) and start-script tricks below are **culled**: they stay in this file only as the record of what the
> sim time is made of. See "Online-safe levers" at the end for what is kept and measured.

Branch `research/hail-mary`. Pure research, nothing here ships: Kailil asked what the most drastic measures could
produce ("literally butcher whatever you need"). Scenario: BAR's "Benchmark BAR" (650 Grunts vs 650 Pawns on
Starwatcher 1.0, 2000 frames) on Kailil's Galaxy Z Fold7, folded, uncapped, 100 % resolution, the phone warmed into
the throttled state a late game plays in (`tools/phone-bench.ps1`: skin ≥ 40 °C, thermal status ≥ 1).

**Results table and ranked summary: see the end of this file** (filled in as runs come in).

## How a lever is applied (no research APK)

The phone keeps the mainline APK. `launch-bar.sh` already sources `files/bar/dev-env.sh` right before the engine
starts; `tools/research/research-bench.ps1` puts `tools/research/dev-env.sh` there, which only acts on a
`MODE=bench` start with `files/bar/research/lever.conf` present: it points `ENGINE` at `research/wrap/spring`
(`tools/research/wrap-spring.sh`), which applies the lever and execs the engine:

| `lever.conf` | effect |
| --- | --- |
| `R_ENGINE` | another engine dir (a research build: our `spring`, every other file linked to the official engine dir) |
| `R_PRELOAD` | libraries in front of `LD_PRELOAD` (allocators) |
| `R_SETTINGS` | springsettings keys, in a *copy* of springsettings.cfg given with `--config` (the real file never changes) |
| `R_TASKSET`, `R_PIN_MAIN`/`R_PIN_OTHERS` | the whole engine on CPUs, or the main thread alone on its CPUs (re-pinned every 10 s) |
| `R_DEBUGCMDS`, `R_GAME` | extra start-script debug commands; another game (an overlay) |

Each run goes through `tools/phone-bench.ps1` (same parsing, clocks, CSV: `build/phone-bench.csv`, labels `hm:*`).
Before letting go of `phone-bench.lock` the harness removes the hook, the lever and the springsettings copy, puts the
user's resolution/frame-cap prefs back and sets Game Mode standard. It touches the phone only when it has been handed over (`hailmary-work\phone-ok`, made by hand when Kailil or the main
session says the phone is free; Kailil's rule: no access, not even reading its state, while he has it), and then
still waits, before taking the lock, while another app is in front. The warm-up into the throttled state is its own
(recorded `hm:warmup-baseline` runs until thermal status ≥ 1 and skin ≥ 40 °C), so every lever is measured hot.
Levers: `tools/research/levers.ps1`.

## Engine builds (laptop cross-build, no WSL, nothing installed)

Recoil `2026.07.04` (the tag the phone runs; reports itself as 2026.07.04) cross-built on Windows with the NDK's
clang 21 for `aarch64-linux-gnu`:
- sysroot: Debian trixie arm64 `.deb`s unpacked by `debfetch.py` (glibc, libstdc++-14, SDL2, OpenAL, X11, GL,
  freetype, fontconfig: the container's own versions, linked dynamically);
- Recoil's official static libs (`spring-static-libs`, branch `18.04-arm`: DevIL, curl, openssl, zlib, png, ogg/vorbis,
  unwind, minizip), the same set the official arm64 build links; a 40-line shim supplies glibc ≤ 2.30's
  `__log_finite`-style entry points those 18.04 libraries call;
- CMake 4.4 + Ninja from w64devkit, `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`, `AI_TYPES=NONE`, target `engine-legacy`;
  1311 objects in ~12 min on the laptop's 32 threads.
Scripts (outside the repo, `C:\Tools\BARANDROID\hailmary-work\scripts`; copies in `tools/research/engine-build/`, with `recoil-research.patch`: the two research-only source changes):
`aarch64-linux-clang.cmake`, `build-engine.ps1 <name>` (flags from `HM_FLAGS`/`HM_LDFLAGS`), `debfetch.py`,
`finite_shim.c`.

The official arm64 build: GCC 13.1 on Ubuntu 18.04, `-O3 -g`, `-march=armv8-a+simd -ffp-contract=off
-fsingle-precision-constant -frounding-math`, mimalloc for `operator new` (`USE_MIMALLOC`), glibc `malloc`.

**Sync with official builds.** Online play needs the same floating-point results as the x86 and official arm64
builds. `-ffp-contract=off` stays in every sync-safe variant (FMA fusion desyncs, Recoil's CMake). `-mcpu=oryon-1`
only adds instructions (LSE atomics, crypto, dot product...) and scheduling, no FP semantics. LTO and PGO change
inlining and layout, not FP results. **But clang itself is not sync-identical to GCC builds**: GCC builds use
`-fsingle-precision-constant` (double literals become float), which clang lacks, so float expressions with double
literals compute differently. A shippable fast engine would have to be a GCC 13 build with the same flags plus
`-mcpu`/LTO/PGO, or prove sync with Recoil's `synctest` workflow. The fast-math variant breaks sync outright.

## Findings before any lever

1. **The engine pins nothing and starts only 3 worker threads on the phone.** infolog: `Optimal Cache Mask:
   0x00000000`, `Main thread CPU affinity not set`, Workers 1-3. Recoil's ARM topology code reads
   `/sys/devices/system/cpu/cpu*/cache/index*/size`; on the Fold7 (or under proot) that yields no cache groups, so the
   "optimal thread count" falls back and nothing is pinned (`rts/System/Platform/Linux/CpuTopology.cpp`,
   `Threading.cpp`). The Snapdragon 8 Elite has 8 big cores (6 × 3.53 GHz + 2 × 4.47 GHz prime).
2. **The ~2 GHz CPU cap is Samsung's SIOP, not the kernel's thermal governor.** During and between runs every
   `cpufreq`/`cpu-cluster` cooling device is at state 0, yet `scaling_max_freq` sits at 2.92/3.28 GHz between runs
   and 1.36-1.79 GHz during a hot run, with `sys.siop.level` set: Samsung's userspace skin-temperature throttling
   writes the caps. Android's thermal status is a coarse summary of the same skin sensor. Less heat per sim frame
   (fewer draw frames, lower GPU load) is therefore also a CPU-clock lever. Global setting
   `restricted_device_performance=1, 1` may be One UI's "Light" performance profile (question for Kailil).
3. Run-to-run noise is large: the main session's back-to-back hot runs of the same build spread Sim 21.4-29.3 ms
   (CPU cap falling as the skin heats). Levers are therefore run alternating with baselines.
4. **The benchmark's own "Sim ms per frame" is wall time, not cost.** `dbg_benchmark.lua` times from `GameFrame` to
   the next `Update`; the scenario runs at 1x, so on a machine that keeps up (the laptop) it reads ~26 ms whatever the
   load (idle time counts). On the phone the game runs below 1x (speed 0.74-0.95), so it is close to cost there, but
   a lever that brings the phone up to 1x would hit that ceiling. Every research run therefore also logs the
   engine's own timers (`debuginfo profiling` at frames 16 and 2010; `tools/research/timers.py` diffs them into ms
   per simulated frame), which count work only.
5. **"Cache Icons" is a benchmark artifact.** BAR's widget preloads 2 unit icons per draw frame until game frame 2000,
   so in this 2000-frame scenario it runs the whole time (4.5 ms per draw frame on the laptop, the costliest widget);
   in a real game it is done within the first minute. It inflates the benchmark's Draw, not Sim.

## Where the time goes (laptop, while the phone was away)

`tools/research/laptop-bench.ps1`: the same scenario on BAR's Windows engine 2026.07.04 (isolated write dir, the
phone's widget orders, BAR test-31691-a617033). Engine timers, ms per simulated frame (laptop, ~1x):

| run | Sim | Lua synced callins | Lua unsynced callins | Draw |
| --- | --- | --- | --- | --- |
| baseline (two runs) | 11.5 / 13.5 | 1.5 / 2.4 | 5.4 / 8.5 | 4.8 / 5.6 |
| LuaUI disabled (`luaui disable` at frame 17) | 10.2 | 1.3 | 1.5 | 1.8 |
| gadget trim (30 gadgets) | 10.6 | 1.0 | 4.8 | 4.9 |
| widget trim (17 widgets) | 11.0 | 1.5 | 2.3 | 1.9 |

- **Synced gadgets** (`tools/research/dbg_hm_synced_profile.lua`, frames 600-1900, 1310 units): no single big one;
  ~25 gadgets at 0.1-0.27 ms/frame each, nearly all in `UnitPreDamaged`/`UnitDamaged`/`Explosion`, each called
  ~110-270 times per sim frame (Unit Explosion Spawner, Juno Damage, Explosion_lights, Mobile Unit Paralyze Damage
  Handler, Watereffects, EMP Lightning, TurnRadius, Unit Evolution, Shield Behaviour, ...). The cost is the per-event
  C++→Lua call, multiplied by every gadget that registered the event.
- **Unsynced gadgets** (`tools/profile/dbg_bardroid_gadget_profile.lua`): 1.6 ms/sim frame; Fire GL4 0.37, Widget
  Events 0.29, Beam Laser GL4 0.27, CUS GL4 0.15. `UnitDamaged` fires ~23,000 times a second.
- **Widgets** (phone's set, `dbg_bardroid_profile_log.lua`): 91 ms/s in all; Cache Icons 34 (artifact, above),
  Reclaim Field Highlight 17 (recomputes reclaim fields as ~7,000 wrecks appear), API Unit Tracker 8, Health Bars 3.7,
  Sensor Ranges LOS 3.6. The widget functions are less than half of what disabling LuaUI saves: the rest is the
  dispatch of each unit event into LuaUI.
- So on the laptop ~75 % of the engine's Sim time is C++ (units, movement, projectiles, collisions, pathing):
  compiler and threading levers are where the large wins would have to come from. The phone profile (simpleperf)
  checks that.

## Round 2 ("Research again. More ways", 2026-10-27 evening)

The phone stayed with Kailil, so round 2 was measured on the laptop (engine timers: work per simulated frame, not
wall time) and every phone lever is queued in `tools/research/queue.ps1` (steps 6-8) for when it is handed over.

### Laptop setup notes
- **The laptop's BAR engine dir holds ReShade.** `engine\recoil_2026.07.04` contains `opengl32.dll` (ReShade's proxy)
  with `ReShade.ini`, renodx/DLSS add-ons and `nvngx_dlss*.dll`: every laptop benchmark so far (this session's and
  the main session's) drew through ReShade, which may explain much of the laptop's Draw noise (4.4-9.2 ms between
  identical runs). Research runs now also use `hailmary-work\win-engine\official-clean`: the same engine files as
  hard links and junctions, without those files (`laptop-bench.ps1 -EngineDir`). Removing such a dir must use
  `rmdir` per entry, never a recursive delete (the junctions point into BAR's install).
- Laptop timings drift with heat by ±15 % over an hour; every variant runs once per round, rounds repeated, medians
  compared (`tools/research/laptop-matrix.ps1`).

### Analysis without measurements
- **streflop.** The arm64 build runs streflop in NEON mode: plain hardware single/double arithmetic, but every
  `math::sin/cos/atan2/sqrt...` goes to streflop's own portable C libm (`rts/lib/streflop/libm/flt-32`, `dbl-64`), and
  that library is compiled `-march=armv8-a+simd` even in a `-mcpu` build. A research build with `ENABLE_STREFLOP=OFF`
  (system glibc libm, vectorised and tuned for the core) is the lever ("eng-syslibm"); it is not sync-safe (glibc's
  results differ in the last bit from streflop's). Its size is whatever simpleperf shows in `streflop::` symbols.
- **ADPF (PerformanceHintManager).** AOSP's `HintManagerService` accepts thread ids of the calling UID even from other
  processes ("tids can belong to different application processes"; only isolated processes are checked by PID), so
  the app could create a hint session for the engine's main thread (same UID under proot) with a 33 ms target and
  report each frame's duration (libbardroid_pace.so knows it). What it buys: the power HAL raises the *floor* (uclamp
  min, placement on the prime cores) when frames run long. It cannot lift Samsung's SIOP *ceiling*
  (`scaling_max_freq`), and in the hot runs the CPU already sits at that ceiling, so the expected gain under throttle
  is small; it could matter early in a game and for frame pacing. Measuring it needs a small app change (a research
  APK in `apk-research`); not done.
- **BOLT.** The NDK has no llvm-bolt and BOLT does not build for Windows hosts; it would have to run in the phone's
  container (Debian's `bolt-19`) with instrumentation (no LBR on the phone) on top of the PGO build. Ranked last:
  BOLT's typical 2-7 % on top of PGO, hours of phone time.
- **GAME_SPEED 20** (`-DHM_GAME_SPEED=20`, `GlobalConstants.h`) and **UnitDamaged to synced Lua only**
  (`-DHM_SYNCED_DAMAGE_EVENTS_ONLY`, `EventHandler.h`): research patches guarded by defines in the Recoil tree
  (`tools/research/engine-build/recoil-research.patch`). GAME_SPEED 20 is compared per game second (Sim ms per frame
  x 20 against x 30); BAR's Lua partly assumes 30 frames per second (timers, effects), so gameplay timing is off.
- **Only Kailil can test** (nothing changed by me): plugged in vs unplugged (charging heat on the same skin sensor);
  One UI's Performance profile (`restricted_device_performance=1, 1` was set: Light?) against Standard; a clip-on fan
  or a cold pack for the no-throttle ceiling.
### Where the sim frame goes (Tracy, laptop)
Recoil's own Tracy-instrumented release (`recoil_2026.07.04_amd64-windows-tracy.7z`), the same benchmark, Tracy
0.11.1's `tracy-capture` for 40 s of the fight (1,198 sim frames, frames ~600-1800), `tracy-csvexport`
(`hailmary-work\tracy\zones.csv`). Main-thread zones, ms per simulated frame:

| zone | ms/frame | what it is |
| --- | --- | --- |
| `Sim::Script` | **4.77** | unit scripts: `CobEngine::Tick` 1.90 (of it `WakeSleepingThreads` 1.75) + the animation pass `CUnitScriptEngine::Tick(MT)` 2.74 (waiting for the workers) |
| `Sim::Unit::Weapon` | **3.81** | 1.56 M `UpdateWeapons` calls (every unit, every frame: targeting, aiming, salvos) |
| `Sim::Projectiles` | **2.17** | of it collisions 1.66 |
| `Sim::Unit::MoveType` | 1.40 | ground movement (collision detection itself 0.19) |
| `Sim::GameFrame` (Lua) | 1.24 | of it the benchmark's own spawner gadget 0.75 (a benchmark artifact) |
| `Sim::Unit::SlowUpdate` | 1.02 | |
| LOS (`Sim::Los` + `UpdateLosTypeMT`) | 0.37 | |
| `Sim::Path` (QTPFS) | 0.09 | |

Off the main thread, `TickAllAnims` (each animating unit's piece animations, `for_mt` over the worker threads) took
22.6 s of CPU in 40 s: **~19 ms of CPU per sim frame, 14.6 µs per unit per frame**. Per call it sorts the unit's
animation list, ticks each animation (turns go through streflop's software `fmod`), checksums each one, and walks the
piece tree breadth-first with a freshly allocated `std::deque`. With the phone's main + 3 workers on slower cores this
pass alone is likely ~9 ms of wall time per frame: the thread count and these per-unit costs are where the C++ sim
can give.

### Laptop results, round 2 (engine timer "Sim", ms per sim frame, median of 3 interleaved rounds)

| variant | Sim | vs base | Lua synced / unsynced | Draw | gameplay effect |
| --- | --- | --- | --- | --- | --- |
| base (official engine, ReShade dir) | 12.32 | | 1.68 / 5.56 | 4.99 | |
| LuaUI disabled | 10.62 | **-14 %** | 1.38 / 1.42 | 1.87 | no interface at all |
| gadget trim (30 gadgets) | 10.96 | **-11 %** | 1.03 / 4.86 | 5.08 | paralyze, shields, Juno, evolution, death effects, fire/laser effects gone |
| modrules: unit quad position updates every 6th frame | 11.94 | -3 % | | | targeting/collision lookups from older positions |
| modrules: pathing x0.5 rate, QTPFS 4096 nodes | 12.09 | -2 % | | | slower path refresh |
| modrules: collision avoidance every 6th frame | 12.09 | -2 % | | | more bumping in crowds |
| modrules: LOS/air/radar one mip coarser | 12.16 | -1 % | | | blockier LOS edges |
| modrules: all of the above | 12.45 | +1 % | | | |
| modrules: quadfield 64 / 256 elmos | 12.49 / 12.91 | +1 / +5 % | | | |
| modrules: unit collision overlap | 13.01 | +6 % | | | units clump |
| Sound=0 | 13.16 | +7 % | | | silence |

The spread between identical runs is ±8 %, so only the two Lua levers are clearly real; the modrules knobs act on
costs the Tracy table shows are small (LOS 0.4, pathing 0.1, collision detection 0.2 ms) and change nothing
measurable here. Sound runs on its own thread: on the laptop it frees nothing on the main thread (the phone's
benefit would be heat, a soak-pair question).

**Main-thread split (forced 3x, the laptop behind like the phone):** game speed 1.81 (defaults), 1.80
(`MinSimDrawBalance=0.05`), 1.80 (`MinSimDrawBalance=0`, `MinDrawFPS=1`): no gain on the laptop, whose draw is only
~3.5 ms per sim frame. The phone's draw + update is ~3x larger, so the levers stay queued for it.
### Engine patches on the laptop (Windows research builds)
To measure engine patches without the phone, the same Recoil 2026.07.04 tree was also built for Windows with
w64devkit's GCC 16 and BAR's `mingwlibs64` (`hailmary-work\scripts\build-engine-win.ps1`, ~10 min a build; engine dirs
in `hailmary-work\win-engine\`). The patches are **runtime switches** in one build (`-DHM_RESEARCH_SWITCHES`, each
off unless its environment variable is set), so they compare within the same binary:
- `HM_ANIM_DFS`: `TickAllAnims` walks the piece tree depth-first (Recoil's own disabled `#else` branch: recursion,
  no `std::deque` allocated per unit per frame);
- `HM_NO_SYNC_HASH`: no sync checksum work (`CSyncChecker::Sync`, the per-animation `LiteHash`);
- `HM_DMG_SYNCED_ONLY`: `UnitDamaged` reaches synced Lua only (not LuaUI, not unsynced LuaRules; ~23,000 calls a
  second in the fight).
Two need builds of their own: `HM_GAME_SPEED=20` (`GlobalConstants.h`) and `ENABLE_STREFLOP=OFF` (system libm; needed
two fixes: missing `math::truncf`-style mappings in `streflop_cond.h` and an empty `streflop` stand-in target).

Engine timer "Sim", ms per sim frame, median of 3 interleaved rounds (all from the clean engine dir):

| variant | Sim | vs research build, switches off | sync-safe? | gameplay effect |
| --- | --- | --- | --- | --- |
| official engine (GCC 13) | 13.36 | +5 % | yes | |
| research build, switches off (GCC 16 -O3) | 12.73 | | compiler differs: unproven | |
| `HM_NO_SYNC_HASH` | 12.78 | 0 % | no desync detection | none visible |
| `HM_ANIM_DFS` | 11.87 | **-7 %** | yes (same results, other order of a pure tree walk) | none |
| system libm (streflop off) | 11.66 | **-8 %** | **no** | none visible |
| `HM_DMG_SYNCED_ONLY` | 11.51 | **-10 %** | yes (unsynced only) | health bars, damage notifications, hit sounds that hang on UnitDamaged stop |
| all three switches | 10.92 | **-14 %** | no desync detection | as above |
| GAME_SPEED 20 | 12.19 per frame = **-36 % per game second** | | **no** | BAR's Lua timers, effects and UI that assume 30 frames a second run slow; units move the same |
| WorkerThreadCount 4 / 16 (official) | 13.61 / 12.46 | | yes | |

Identical runs spread ±8 %, so single levers of 5-10 % are suggestive, the combination (-14 %) and GAME_SPEED are
solid. Threads scale weakly on the laptop (4 → 16 workers: -9 %); the phone has slower cores and only main + 3
workers by default, so `workers8` is still the first CPU lever to measure there. Observation: Draw per sim frame is
~2x higher from the clean engine dir than from BAR's dir with ReShade's `opengl32.dll` (10.8 vs 5.0 ms), so laptop
Draw numbers are only comparable within one dir.
## Ranked summary (2026-10-27, after round 2; no phone run yet: laptop numbers, phone queue ready)

Ranked by measured Sim reduction (engine timer, work per frame; laptop, ±8 % noise between identical runs):

| # | lever | measured | sync / online | could it be made safe for the real build? |
| --- | --- | --- | --- | --- |
| 1 | GAME_SPEED 20 (engine build) | **-36 % sim per game second** | breaks sync with every other build; BAR's Lua assumes 30 Hz | no (a game-wide change for BAR, not a client lever) |
| 2 | LuaUI off | -14 % | client-only | partly: the costliest widgets can go on the phone (Reclaim Field Highlight; its cost grows with wrecks) |
| 3 | engine switches together (DFS piece walk + UnitDamaged to synced Lua only + no sync hash) | -14 % | DFS: identical results; damage-event filter: unsynced only | **DFS walk: yes, as an upstream Recoil change** (no allocation per unit per frame, same results); the damage filter would need an engine option ("no unsynced UnitDamaged") and breaks health bars/notifications |
| 4 | gadget trim (30 damage-event and effect gadgets) | -11 % | synced gadgets: a different game, singleplayer only | in singleplayer only, as part of the controller game overlay (it is already an overlay); effects gadgets could become a BAR option |
| 5 | UnitDamaged to synced Lua only | -10 % | client-only | see 3 |
| 6 | system libm instead of streflop | -8 % | **no** (last-bit differences) | no |
| 7 | DFS piece walk in `TickAllAnims` | -7 % | yes | yes, upstream (see 3) |
| 8 | 16 vs 4 worker threads | -9 % between them | yes | yes: a setting; the phone runs main + 3 because Recoil found no cache topology. Measure workers8 on the phone first |
| 9 | own GCC 16 -O3 build vs official GCC 13 | -5 % | unproven | only as a GCC build with the official flags, proven with Recoil's synctest |
| - | modrules: LOS mip, collision avoidance and quad update rates, quadfield size, pathing budget, overlap | within ±3 % (overlap, quad 256 worse) | game change | not worth it: Tracy shows LOS 0.4, pathing 0.1, collision detection 0.2 ms per frame |
| - | MinSimDrawBalance / MinDrawFPS (forced 3x) | no change on the laptop | client | phone pending (its draw share is 3x larger) |
| - | Sound=0, no sync hash alone | no main-thread change | | heat question: soak pair on the phone |

Not measured yet (phone queue, `tools/research/queue.ps1`): the arm64 compiler builds (oryon, ThinLTO, fast-math,
PGO), workers 5/7/8, main-thread pinning, allocators, frame caps 20/30 as game speed, soak pair (15 min each), huge
pages, the engine switches on arm64, and "everything" (the ceiling: every lever at once). simpleperf will show the
phone's own split (and whether worker threads spin), the scheduling probe the engine's cgroup/uclamp, and the proot
CPU share (a proot-free start is only worth trying if that share is large).

**Biggest single surprise:** the sim frame is dominated by unit scripts and weapons (Tracy: 4.8 + 3.8 ms of ~13 ms on
the laptop), and the per-unit animation pass costs ~19 ms of worker-thread CPU per frame, while the levers people
usually reach for (LOS resolution, pathing, collision rates) act on fractions of a millisecond.
## Online-safe levers (from 2026-10-27 ~20:00)

**Culled** (they change the engine binary or the game a player joins): every research engine build (clang/oryon/LTO/
PGO/fast-math/no-sync-hash/system libm/GAME_SPEED 20/the runtime-switch patches, also the GCC 16 Windows builds),
BOLT, the gadget-trim and modrules overlay games, start-script commands (`luaui disable`, `hideinterface`), and
LuaUI-off (online-safe but unplayable: kept only as the laptop reference ceiling, -14 %). `levers.ps1` lists them in
`$Culled`; `research-bench.ps1` refuses them.

**Kept, and why each changes nothing synced:**

| lever | sync check |
| --- | --- |
| WorkerThreadCount 5/6/7/8 | the thread pool only splits homogeneous `for_mt` work; Recoil keeps sim results independent of how work lands on threads (`coding-agents/ENGINE_PERFORMANCE.md`), and the setting is a normal player option |
| main thread on the prime core, taskset | OS scheduling only |
| mimalloc/jemalloc for malloc (LD_PRELOAD), glibc huge pages | where memory comes from; nothing synced may depend on addresses (players already differ in OS, allocator and ASLR) |
| MinSimDrawBalance / MinDrawFPS | when the client simulates vs draws; the frames simulated are the same |
| frame cap 30 (Kailil's hard lock), Sound=0 | drawing and audio only |
| MaxParticles 10000 / MaxNanoParticles 0 | unsynced effect particles (synced projectiles are not limited by them) |
| LuaUI widget trim | local widgets |
| Lua garbage-collection settings | change only when collection runs, which already varies with each player's CPU speed (the run-time budget is in ms), so synced Lua cannot depend on it |
| graphics settings (min-render without `hideinterface`), Game Mode, the cgroup/uclamp probe, proot cost | client-side or read-only |

Harness fix found on the way (2026-10-27 21:00): Windows PowerShell puts a UTF-8 BOM in front of any text piped into
adb. Android's sh (mksh) skips it, the container's bash does not: `dev-env.sh` failed on line 1 and no lever was
applied in the first two attempts (their rows are plain baselines). `research-bench.ps1` now pushes text through a
BOM-free file. Also: the round-2 laptop "work" and "speed" matrices ran from BAR's engine dir (ReShade in the path);
their Sim timers stand, their Draw numbers are not comparable with the clean-dir runs.
## Online-safe phone batch (2026-10-28 00:58-02:25, verdict)

Kailil's phone on the charger overnight, mainline APK (Reclaim Field Highlight already off, frame cap saved at 30;
benchmarks uncapped unless a lever sets a cap), official engine, `tools/research/queue.ps1`. 3 warm-up runs, then
36 benchmark runs, every lever next to baselines, plus one simpleperf run. Hot throughout after the warm-up (thermal
status 3, skin ~45 C, AP 44-49 C). Raw rows: `build/phone-bench.csv` (labels `hm:*`), infologs with the engine timers:
`build/research-infolog/`, profile: `build/research-perf/perf-baseline.data`.

**The CPU cap decides the game speed.** 18 baseline runs: game speed 0.65-0.90 (Sim 23.2-31.8 ms), and the spread
follows Samsung's CPU cap during the run (`speed = 0.00019 x cap(MHz) + 0.474`, residual ±4 %): the cap moved between
~1,000 and ~1,800 MHz from run to run with the skin steady at 45 C, and 1,000 -> 1,800 MHz is worth **+23 %** game
speed. So each lever is shown as its residual against that fit (same clocks), and against its neighbouring baselines:

| lever (online-safe) | game speed vs fit at the run's CPU cap | vs neighbouring baselines (Sim) | verdict |
| --- | --- | --- | --- |
| WorkerThreadCount 5 / 7 / 8 (auto = 4 on the phone) | **+8.3 / +7.6 / +6.3 %** | -7.4 / +1.3 / +4.0 % | the one consistent signal: all three above the fit (~3 sigma together); worth shipping as the default, confirm with 2-3 more pairs |
| main thread pinned to prime core 7 | +0.9 % | -2.2 % | nothing |
| whole engine on prime cores 6-7 | +3.8 % | -3.1 % | nothing (even 2 cores suffice: the sim is main-thread bound) |
| mimalloc / jemalloc for malloc | +1.0 / -1.8 % | -0.3 / -0.9 % | nothing |
| glibc / mimalloc huge pages | +5.0 / -5.8 % | +9.5 / +8.7 % | nothing: THP is already `always` on the phone |
| LuaUI widget trim (17 widgets) | -0.4 % | +1.7 % (Draw -18 %) | nothing for the sim (Reclaim Field Highlight, the costly one, is already off) |
| frame cap 20 / 30 | +3.4 / +0.9 % | -5.3 / -4.3 % (game speed +8 / +6 %) | the runs ran at the higher cap; less drawing may keep the CPU cap up, too weak to claim |
| Sound=0, soak of 6 runs | -1.4 % (mean) | mixed | nothing (openal is ~7 % of the engine's CPU on its own thread) |

**Where the phone's time goes** (simpleperf, 30 s of the fight, user-space samples, official engine with its debug
symbols): 1.54 cores busy; main thread 52.5 % of the samples, workers 12.7 / 11.9 / 10.4 % (each ~18 % busy), OpenAL
6.8 %, Mesa 4.7 %. The main thread is flat: the Lua VM (`luaV_execute` 4.6 %, `luaH_get` 1.6 %, `luaD_precall` 1.4 %),
unit scripts (`CUnitScript::FindAnim` 2.2 %, `CCobThread::Tick` 1.8 %, `TickAllAnims`, `WakeSleepingThreads`), the sync
checksum (`CSyncChecker::Sync` 1.4 %), collisions, timers. The workers run the animation pass (`TickAllAnims`, quaternion
rotations, streflop's `fmodf`/`sinf`) and spin very little (`try_dequeue` + `WorkerLoop` + clock reads ~10 % of their
time, ~3.5 % of all CPU).

**Probes:** proot used 0.27 s of CPU in those 30 s against 48 s for the engine (**0.6 %**): a proot-free start is not
worth it. The engine runs in the `top-app` cgroup (cpuset, cpu, cpuacct), all 8 CPUs allowed, uclamp not readable;
120,801 voluntary vs 1,135 involuntary context switches (it waits more than it is preempted). Transparent huge pages:
`[always]` already.

**Verdict for Kailil:** online-safe optimization is close to done. One setting is worth shipping: **WorkerThreadCount
7 (or 8) instead of the auto 4: about +7 % game speed at equal CPU clocks** (confirm with a few more alternating
pairs before making it the default). Everything else online-safe measured flat. The rest of the sim time is BAR's
own game logic and Recoil's C++ (only changeable upstream or in BAR), and the biggest remaining factor is heat:
Samsung's CPU cap swings game speed by ~23 %, so cooling, not charging while playing, and One UI's performance profile
(Kailil's tests) move more than any further client setting would.