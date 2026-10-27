# Hail-mary research: how far can Sim time drop? (2026-10-27)

Branch `research/hail-mary`. Pure research, nothing here ships: Kailil asked what the most drastic measures could
produce ("literally butcher whatever you need"). Scenario: BAR's "Benchmark BAR" (650 Grunts vs 650 Pawns on
Starwatcher 1.0, 2000 frames) on Kailil's Galaxy Z Fold7, folded, uncapped, 100 % resolution, the phone warmed into
the throttled state a late game plays in (`tools/phone-bench.ps1`: skin â‰¥ 40 Â°C, thermal status â‰¥ 1).

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
user's resolution/frame-cap prefs back and sets Game Mode standard. It waits (before taking the lock) while the phone
is unreachable or in use (screen on, another app in front: a call blocked runs on 2026-10-27).
Levers: `tools/research/levers.ps1`.

## Engine builds (laptop cross-build, no WSL, nothing installed)

Recoil `2026.07.04` (the tag the phone runs; reports itself as 2026.07.04) cross-built on Windows with the NDK's
clang 21 for `aarch64-linux-gnu`:
- sysroot: Debian trixie arm64 `.deb`s unpacked by `debfetch.py` (glibc, libstdc++-14, SDL2, OpenAL, X11, GL,
  freetype, fontconfig: the container's own versions, linked dynamically);
- Recoil's official static libs (`spring-static-libs`, branch `18.04-arm`: DevIL, curl, openssl, zlib, png, ogg/vorbis,
  unwind, minizip), the same set the official arm64 build links; a 40-line shim supplies glibc â‰¤ 2.30's
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
   `Threading.cpp`). The Snapdragon 8 Elite has 8 big cores (6 Ã— 3.53 GHz + 2 Ã— 4.47 GHz prime).
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
  C++â†’Lua call, multiplied by every gadget that registered the event.
- **Unsynced gadgets** (`tools/profile/dbg_bardroid_gadget_profile.lua`): 1.6 ms/sim frame; Fire GL4 0.37, Widget
  Events 0.29, Beam Laser GL4 0.27, CUS GL4 0.15. `UnitDamaged` fires ~23,000 times a second.
- **Widgets** (phone's set, `dbg_bardroid_profile_log.lua`): 91 ms/s in all; Cache Icons 34 (artifact, above),
  Reclaim Field Highlight 17 (recomputes reclaim fields as ~7,000 wrecks appear), API Unit Tracker 8, Health Bars 3.7,
  Sensor Ranges LOS 3.6. The widget functions are less than half of what disabling LuaUI saves: the rest is the
  dispatch of each unit event into LuaUI.
- So on the laptop ~75 % of the engine's Sim time is C++ (units, movement, projectiles, collisions, pathing):
  compiler and threading levers are where the large wins would have to come from. The phone profile (simpleperf)
  checks that.
