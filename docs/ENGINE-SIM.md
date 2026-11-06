# Engine branch: the simulation on phones (started 2026-11-04)

Kailil, 2026-11-04: "Lets pursue the new engine build. But we will tackle the simulation issue first. Optimization of
the simulation to make it less demanding on mobile, and seeing if the phone can get calculations from others to offset
the cost of calculations on device. And exploring multithreading on android. Do all of it on one build first to see if
Gains were made during the bench mark then if they are, we start with replays, then spectating 16 player games on Dev
phone to see if it can share the simulated loads. Make sure this new branch of what we are doing is clearly separated
from the part work. So it's easy to reverse course".

Why it is possible now: a BAR developer told Kailil (Discord, 2026-11-04) that BAR's online check does not verify the
engine 1:1; developers join multiplayer games with prototype engine builds labelled as the matching version, in good
faith. What no server checks, the game still does: every client simulates every frame (lockstep) and the server
compares checksums, so a build whose simulation computes anything differently desyncs the game for everyone.

## Kept apart, easy to reverse

| what | where | how to drop it |
| --- | --- | --- |
| this work in the app | branch `engine/sim`, worktree `C:\Tools\BARANDROID\bar-droid-engine` | delete the branch; `main` never has it |
| engine source | `hailmary-work\recoil-src`, branch `bardroid/sim` from tag `2026.07.04` (the 2026-10-27 research edits: branch `research/hail-mary-switches`) | `git checkout 2026.07.04` |
| builds, toolchain scripts | `C:\Tools\BARANDROID\engine-sim\` (outside every repository); the GCC cross compiler in `toolchain\hosttools\arm-gnu-13.2` | delete the folders |
| on the phone | a separate engine folder `files/bar/engine-sim/<build>`, started only by `files/bar/dev-env.sh` (a test run's own file, removed after) | the app never uses it otherwise; delete the folder |

The shipped app (`main`) keeps BAR's official engine. Nothing from this branch reaches Kailil's Fold7 or an online
game until the replay and spectating stages below say it computes exactly what the official engine computes.
(2026-11-05: Kailil had the 30 fps build put on his Fold7 after those checks; Status below.)

## Sync rules for every change

- The official arm64 engine is GCC 13 (Ubuntu 18.04) with `-O3 -march=armv8-a+simd -ffp-contract=off
  -fsingle-precision-constant -frounding-math`. Our builds use GCC 13 too (Arm's 13.2 cross compiler) with the same
  floating-point flags: clang has no `-fsingle-precision-constant` and computes some float expressions differently
  (docs/research-hail-mary.md on `research/hail-mary`).
- Allowed: anything that leaves every synced result bit for bit the same: code order of independent work, fewer
  allocations, threads for work whose results do not depend on the order it finishes, CPU tuning that adds
  instructions but no floating-point contraction (`-mcpu`, LTO, PGO), and unsynced work (drawing, events to LuaUI).
- Not allowed: a different libm (streflop stays), fast-math, FMA contraction, game speed, any change to what is
  simulated, and switching the sync checksum off (the server compares it).
- Proof: a replay recorded by BAR's server carries every player's checksum; played back, the engine logs
  `[DESYNC WARNING]` for any frame whose checksum differs from its own (`rts/Net/NetCommands.cpp`). A build must
  play whole multiplayer replays without one, as the official engine does.

## Stages

1. A stock GCC build of 2026.07.04 for arm64 (the official flags): plays a replay without desync warnings, benchmarks
   like the official engine. The baseline every change is measured against.
2. One build with all of it:
   - sim optimizations that keep results identical (the research's depth-first piece walk in `TickAllAnims`: -7 % on
     the laptop; allocations and lookups in unit scripts and weapons, the two biggest sim zones);
   - multithreading: the phone runs main + 3 workers (Recoil finds no cache topology under Android); thread count and
     which sim passes run on the workers;
   - compiler: `-mcpu` for the phones' cores, LTO, PGO;
   - "calculations from others": lockstep means every client computes every frame itself; what a phone could take
     from other players instead is a research prototype (offline only), measured for what it would save.
3. The phone benchmark (`tools/phone-bench.ps1`, hot, alternating with the stock build): gains or not.
4. If gains: replays (no desync warning in whole multiplayer games), then spectating 16-player games on the dev phone.

## Engine changes (`bardroid/sim`, all behind `-DBARDROID_SIM`: the same source builds stock without it)

- `rts/Sim/Units/Scripts/UnitScript.cpp` `TickAllAnims`: each animating unit's pieces walked depth-first from a stack
  kept per worker thread, not breadth-first through a `std::deque` allocated per unit per frame (laptop research:
  -7 % Sim). Same transforms in the same values: a piece's transform depends only on its parent's. (Recoil's own
  disabled DFS branch needs C++23 explicit object parameters, which GCC 13 lacks.)
- `rts/System/Platform/Linux/CpuTopology.cpp`: Android lists each core's caches without sizes, so Recoil found no
  cache groups, counted the little cores as performance cores and fell back to its default thread count. Without
  cache sizes the cores are now grouped by the kernel's `cpu_capacity` (dev phone: 1024 prime, 811 x4, 266 x3):
  the slowest are efficiency cores, the groups sorted fastest first, so the thread pool takes the fast groups up to
  its threshold (dev phone: main + 4 workers on the prime and big cores; Fold7: all 8) and keeps off the little ones.
  Threads only: which core runs a task never changes its result.
- Memory for 8v8 replays on the 8 GB dev phone (Kailil, 2026-11-04: "Cut wherever necessary. I want that dev phone
  running 8v8 30min plus games via replay"); drawing and memory only, each a setting (off by default) or behind
  `BARDROID_SIM`:
  - `ProjectileAtlasDownscale` (1-4): the projectile and ground effect atlases' pictures shrunk on each side
    (8176x6056 + 6616x6152 uncompressed, 344 MB; at 4: ~22 MB).
  - `NamedTextureMaxSize`: picture files loaded by name (Lua's `gl.Texture`) larger than this on a side shrunk to it
    (BAR's loading pictures: 3840x2160, 33 MB each).
  - `MaxDrawnParticles`: at most this many see-through projectiles and particles drawn a frame, the nearest.
  - `S3DModelVAO`: the models' CPU copies (an 8v8: 336 MB vertices, 104 MB indices) given back right after their
    upload (they stayed through the pathfinder's and LuaRules' load, and `clear()` kept their memory for the game);
    and the model buffer grown by half at least when models load as needed (`PreloadModels = 0`, an existing
    setting), where 8 MB steps made the whole buffer anew each time (~1.9 GB of GPU memory in 8 s).
- `rts/Sim/Units/UnitHandler.cpp`: `UpdatePreFrame` (each unit's previous-frame piece transforms, for the draw
  interpolation) on the thread pool in blocks of 16 units; `UpdateUnitLosStates` works every unit's new LOS status
  out on the workers (`CalcLosStatus` only reads) and sets them in the original order on the main thread, where
  the Lua events run, working a status out again if a call-in changed it meanwhile.
- `rts/Lua/LuaHandle.cpp`: with the engine's profiler on (`/debug 1 0`), a timer per handle and call-in, and BAR's
  Tracy zones (`W:Update:<widget>`, `G:GameFrame:<gadget>`) as timers.
- `rts/Lua/LuaVFS.cpp`: `BarDroidUnsyncedGadgetsOff`, gadget files left out of the unsynced LuaRules state's lists.
- `rts/Rendering/GlobalRendering.cpp`, `rts/System/SpringApp.cpp`: `BarDroidDeferSwap`, the deferred present.
- `rts/Rendering/BarDroidGpuTimer.h` (WorldDrawer.cpp, Game.cpp, LuaHandle.cpp): with the profiler on, the GPU's time
  per drawing pass and per widget's or gadget's drawing call-in ("GPU::<pass>"); a result over a second (a query
  Mesa never ran: the minimap widget's read ~5e8 s) is left out.
- `rts/Rendering/Models/IModelParser.cpp` + `rts/lib/meshoptimizer` (meshoptimizer 0.23, MIT: its simplifier and vertex
  cache optimizer only): `BarDroidModelSimplify` (share of triangles kept, 0 = off) and `BarDroidModelSimplifyError`
  (elmos): every model piece's triangles simplified once when the model loads (edge collapses that keep seams and open
  edges), then ordered for the GPU's vertex cache. Only the index list changes: vertices, sizes, bounds and collision
  volumes stay exactly the same, so the simulation cannot notice; every pass (units, features, wreck pieces, build
  previews) draws the shorter list. Pieces under 48 triangles are left alone.
- `rts/Net/NetCommands.cpp`: `BarDroidMaxSimPerDraw`, one simulated frame per drawn frame while few are waiting.
- `rts/System/Threading/ThreadPool.h`: `for_mt_chunk` in about four chunks a thread, taken as threads come free.
- `rts/Sim/Features/FeatureHandler.cpp`: the features' previous-frame transforms on the workers.
- `rts/Lua/LuaUnsyncedRead.cpp` (a plain fix, not behind the flag): `Spring.GetProfilerTimeRecord` reads its optional
  argument before pushing its results, and makes the frame table before filling it.
- `rts/Rendering/Env/CubeMapHandler.cpp`: `BarDroidReflectionEvery` (default 1), the reflection cubemap's next face
  drawn every N drawn frames (each face a terrain pass from another camera). At 8: its main-thread time 0.97 -> 0.12
  ms a frame and its GPU pass (0.39 ms) gone from the profile, a whole cubemap still renewed every 1.6 s at 30 fps.
- `rts/System/Threading/ThreadPool.h/.cpp`: `BARDROID_POOL_WAIT` (environment; "wfe", the default, "spin" as stock,
  "sleep"): a thread waiting for a task group (the main thread for the workers) spins 50 us
  (`BARDROID_POOL_SPIN_US`), then rests in ARM's wait-for-event until another core writes the group's task counter,
  instead of spinning on the clock for up to 500 ms (~7 % of the main thread in a late 8v8). Fast-forward of 10 game
  minutes, alternating: spin 100-125 s (the phone warming), WFE at once 127/127 s, a futex sleep 129/136 s, the
  spin-then-WFE default 95/108 against spin 109/95 s; 0 desync warnings throughout.
- Tried and not kept (2026-11-05), the unit update loop (`CUnitHandler::UpdateUnits`, ~1.1 ms a frame with 3,500
  units): it cannot go to the workers with the same results, as builders and factories do their own work inside it
  (building, terraforming, moving their buildee, synced Lua call-ins) between other units' updates, and a unit's
  change of air/water state fires synced Lua call-ins that BAR's gadgets answer (water speed, depth damage, collision
  damage). Asking for the next units' memory ahead of time instead (the same code in the same order) was measured
  on and off by turns in one run of the whole 8v8 replay: 1.114 against 1.133 ms over 2,500 units (-1.7 %), 0 desync
  warnings; too small to keep.
- The main thread's wait at the end of parallel sections (2026-11-05 22:30, from the evening's late-8v8 runs with the
  profiler, gcc-wfe2): `ThreadPool::AddTask` times a whole `for_mt` on the calling thread (its own share and the wait
  after it), `ThreadPool::WaitFor` only its own share (`ExecuteLoop`). 23.6-25.8 % of real time against 19.6-20.6 %:
  the main thread idles 4-5 % of real time, ~2 ms a drawn frame (8-10 % of the simulation), for the workers' last
  pieces. Lead: the engine pins its workers to cores itself (`FindWorkerThreadCore`), but launch-bar.sh's
  `widen_engine` gives every engine thread all CPUs every 3 s, so a worker can run its last piece on a little core
  (A510, about a third of the X3's speed). Next: the 4 workers on the A715/A710 cores (cpus 3-6), the main thread free
  to keep the X3, through a launch-bar.sh hook, measured by the alternating fast-forward (`ab-wfe2.ps1`'s way) and the
  same timers. The hook: `BARDROID_WORKER_CPUS` (hex, dev-env.sh only; the app's launch-bar.sh `widen_engine`), the
  pool's six workers (two pools of three, "worker1".."worker3") on that mask, every other thread on all; checked on
  the dev phone (78 on the workers, `recoil-main` free). Fast-forward of 10 game-minutes, alternating: workers on
  cpus 3-6 101 and 140 s, on all 121 and 129 s; 0 desync warnings. Inconclusive: the two pinned runs differ by 40 %,
  far more than the effect sought (the phone warming run to run). Next: the timer gap itself (AddTask - WaitFor) in
  each mode, ABBA, with the profiler. The Fold7's 8 Elite has no little cores (two 4.47 GHz and six 3.53 GHz Oryon),
  so it would gain little either way; it matters for phones like the dev phone.
  The timer A/B (23:16-23:57, profiler on, ABBA): the wait 4.32 and 3.96 ms a frame pinned, 3.58 all (the other "all"
  run throttled to 5.6 fps, left out): ~8.5-9 % of the simulation's time either way. Pinning does not shorten the tail;
  dropped (the hook stays, unset).
- **The sustained-heat state (2026-11-05, Kailil's goal from 23:05: consistent 30 fps in late 8v8 on the dev phone).**
  After an evening of runs the dev phone's thermal governor capped the X3 at 1248-1363 MHz (of ~3360) and the
  A715s at 940-1056 MHz (18:45: 1843 and 1536). The same late-8v8 window (game seconds 1210-1330, gcc-wfe2,
  profiler on): 22.6 fps at 18:45, 12.1-13.2 fps at 23:16-23:57 (Sim 43-47 ms a drawn frame against 20.4). 30 fps
  must hold in this state, the one a long game ends in: at these clocks the main thread would need well under half of
  today's work a frame. Watts are the currency: less CPU and GPU work raises the caps.
- `rts/Sim/Path/QTPFS/PathManager.cpp` (a plain fix): `Sim::Path::RawSearches` registered with the profiler, as
  `Sim::Path::Requests` is (every profiled game logged "[ResortProfilesRaw] timer with hash 2549212347 wasn't
  registered").
- Compiler: `-mtune=cortex-x3` (the dev phone's prime core; scheduling only, no instruction or FP change).
- LTO: not with this compiler: Arm's Windows-hosted GCC is a 32-bit program, too small for whole-engine LTO.

## Toolchain notes

- Arm's folder name made the compiler's own header paths pass Windows' 260-character limit
  (`bits/c++allocator.h` "not found"): it lives at `toolchain\hosttools\agcc13`.
- Its `include-fixed/pthread.h` (a copy of Arm's glibc 2.38 header) shadowed the sysroot's glibc 2.41 one
  (`PTHREAD_COND_INITIALIZER` no longer matched): moved aside (`agcc13\SOURCE.txt`).
- Debian's multiarch folders (`usr/include/aarch64-linux-gnu`, `usr/lib/aarch64-linux-gnu`) are passed by hand
  (`-idirafter`, `-B`, `-L`, `-rpath-link`); some of Recoil's targets drop `CMAKE_C_FLAGS`, so the include goes in
  the build type's flags too. `--allow-shlib-undefined`: SDL2's own dependencies are on the phone, not in the sysroot.
- A replay's game version must be installed: `pr-downloader --download-game "Beyond All Reason test-NNNNN-hash"` in
  the phone's container (BAR's rapid servers, as the app's update does).

## Findings on the way

- **Memory before 16-player games on 8 GB phones.** The 8v8 replay (Supreme Isthmus, 2026-10-13) does not load on the
  dev phone: Android's low-memory killer closed the app while the engine loaded it (13:12:59, "the phone ran out of
  memory"; ~3.1 GB available idle). Stage 4's "spectating 16-player games on the dev phone" needs the engine to use
  less memory first (the projectile atlases' 345 MB and the screen's buffers are unsynced: engine-side work now
  possible), or Kailil's Fold7 (12 GB). The sync checks use a 1v1 server replay meanwhile (SpeedMetal, 2026-10-01).
- **PGO** (profile-guided optimization; the main thread is mostly BAR's Lua and unit scripts, interpreters gain most
  from it): the Windows-hosted GCC writes profile names with Windows backslashes; with `-fprofile-prefix-path` set to
  the build folder (backslash form) they come out as `<dir>\rts#...#File.cpp.gcda`, which the rebuild in the same
  folder finds again.

- **The engine never ran on the dev phone's prime core.** Its threads start with a CPU mask that leaves out core 7 (the
  X3, 3.36 GHz) and often 5 or 6 (0x3f, 0x5f, 0x3b, 0x58...; the engine's first log line already has it, while the
  launch shell has all 8), set from outside as it starts (most likely Samsung's game service); the cpuset is
  top-app (0-7). Android's side may not change it (run-as: Permission denied, SELinux); the app's own shell can:
  `tools/engine-sim/dev-env-allcpu.sh` re-allows every CPU every 3 s (engine `0-7` from then on). App-side, no engine
  change. Measured hot, the official engine, alternating (BAR's benchmark, uncapped, AP 49-57 C):

  | | game speed | Sim ms per frame | big cluster's median clock |
  | --- | --- | --- | --- |
  | as started (cores 0-5 or so) | x0.53, x0.54, x0.53 | 40.1, 39.0, 39.6 | 864 MHz |
  | every CPU allowed | x0.67, x0.70, x0.64 | 33.2, 30.9, 34.1 | 1593 MHz |

  **+26 % game speed** with the same binary and heat: as started, the engine's busy threads sat mostly where the big
  cluster stayed idle at its floor. Scheduling only, nothing synced: it can go to `main` on its own (launch-bar.sh),
  after a look at the Fold7's mask (the 2026-10-27 research saw all 8 CPUs there).
- **Wall time is the wrong yardstick for small changes on a hot phone**: in 8 alternating hot runs the big cores'
  cluster sat at 864 MHz in seven and at 1843 MHz in one; game speed followed the clock, not the build. CPU work per
  simulated frame (simpleperf: user-space instructions and cycles of all engine threads from game frame 15 to 2017
  of BAR's benchmark, `tools/engine-sim/bench-cycles.ps1`) repeats within ~1 %:

  | engine | instructions per frame (2 runs) | cycles per frame | main thread cycles |
  | --- | --- | --- | --- |
  | official | 197.5 / 196.8 M | 167.2 / 166.4 M | 115.5 / 115.3 M |
  | gcc-stock | 184.6 / 184.9 M (-6.4 %) | 163.5 / 164.4 M (-1.8 %) | 112.8 / 113.2 M |
  | gcc-sim1 | 184.0 / 184.4 M | 161.2 / 162.9 M (-2.8 %) | 112.2 / 113.2 M |
  | gcc-sim1, the engine's own thread choice | 184.5 / 184.7 M | 162.0 / 164.0 M | 111.8 / 113.3 M |

  So the GCC 13.2 build with the newer libraries already does less work than the official one, and the first sim
  changes add little in this scenario (the deque was a laptop cost more than a phone one). The engine's own thread
  choice changes nothing measurable while the main thread is the limit (it is ~70 % of all cycles).

  Profile-guided (`tools/engine-sim/pgo-train.ps1`: BAR's benchmark played with an instrumented build, 1,086 profiles,
  then rebuilt with them), against the same day's official and gcc-stock rows:

  | engine | instructions per frame (2 runs) | cycles per frame | main thread cycles |
  | --- | --- | --- | --- |
  | official | 201.0 / 189.0 M | 168.5 / 123.1 M | 115.9 / 81.1 M |
  | gcc-stock | 183.7 / 183.6 M | 163.1 / 162.7 M | 113.0 / 113.0 M |
  | gcc-pgo | 171.0 / 172.6 M (-7 % from gcc-stock, -13 % from official) | 152.4 / 162.5 M | 105.5 / 113.4 M |

  Instructions repeat; cycles depend on which core the main thread got (official's second run: core 7, the X3, in
  its mask: 123 M), so instructions are the yardstick between builds and cycles only within one core type.

  With every CPU allowed (`main`'s launch-bar.sh since 46cfe85) even instructions stop repeating: the main thread
  spin-waits for the worker threads' parts of a frame, and those spins count. `gcc-pgo-lse` (`gcc-pgo` with
  `-march=armv8.2-a`: the atomics as single LSE instructions instead of load/store-exclusive loops; every phone BAR
  can run on has them), main thread per frame:

  | engine | instructions (2 runs) | cycles |
  | --- | --- | --- |
  | gcc-pgo | 116.0 / 106.3 M | 84.0 / 74.7 M |
  | gcc-pgo-lse | 106.7 / 104.0 M | 76.9 / 73.7 M |

  The same build moved 9 % between its runs; the LSE build's gain (-2 % between the closer pair) is inside that.
  Measuring builds this close needs the spinning out of the count (simpleperf on the main thread's functions without
  the thread pool's wait loop) or more rounds.

- **Sync proven on a real game, and the check proven to bite.** BAR's server echoes every player's checksum every
  60 frames into its recording (`GameServer.cpp`, `syncResponseEchoInterval`), and a replay played back compares
  each with its own (`NetCommands.cpp`). The 1v1 server replay (SpeedMetal, 2026-10-01, Kailil's own game as
  UnderarmCape vs chrrod1, BAR test-31465), fast-forwarded 20 minutes (36,000 frames, ~1,150 units at the end):

  | engine | desync warnings |
  | --- | --- |
  | official | 0 |
  | gcc-stock (GCC 13.2, official flags) | 0 |
  | clang-o3 (the 2026-10-27 research build: no `-fsingle-precision-constant`) | 0 |
  | gcc-pgo (sim changes, `-mtune=cortex-x3`, profile-guided) | 0 |
  | gcc-pgo-lse (the same, `-march=armv8.2-a`; flags checked in build.ninja: fp-contract off, single-precision constants and rounding math kept) | 0 (37,683 frames) |
  | oryon-lto-fast (research build with `-ffast-math`: the control) | **1,190, from frame 0** |

  So clang's missing `-fsingle-precision-constant` did not show in 20 minutes of a real game (Recoil's synced math
  writes its float literals as floats); GCC stays the safe choice. All builds played the replay's measured minute in
  real time on the dev phone (x1.00).
- **Old replays and the app's menu copies** (a `main` bug found here, fixed there: 9dd7f16): the replay's BAR release
  is older than the copies, BAR removed them, and launch-bar.sh switched them off for every later game.

- **16-player games on the 8 GB dev phone: memory, not the sim, stops them first.** The 8v8 replay (Supreme Isthmus)
  loaded once with the official engine (~700 MB available in the pre-game, the GPU driver at 2.35 GB, the engine
  ~600 MB) and Android's low-memory killer ended it as the game started; other times during the load. Its textures
  of 128x128 or more (pace's `BARDROID_TEX_LOG`): 780 MB, of it the two projectile atlases 189 + 155 MB (8176x6056,
  6616x6152, requested as generic compressed RGBA, which Mesa keeps uncompressed), three 3840x2160 (95 MB) and one
  4080x3256 (51 MB). `ProjectileAtlasDownscale = 2` (an engine setting on this branch: the atlases' images shrunk 2x
  on each side, effects only) took the GPU driver's peak to 2.14 GB, -200 MB; the replay was still killed while it
  loaded (956 MB available a moment before: Android kills on memory pressure, not only on free memory). Next: what
  the 4K textures are (perhaps the loading screens' pictures, held after the load), and what else the load allocates
  at its peak. `tools/engine-sim/replay-memory.ps1` runs it.
  The textures (the official run's log): the three 3840x2160 are pictures of the loading phase (one at the engine's
  start, the splash; two as the load screen begins), 33 MB each uncompressed, all in the load's peak; 4080x3256 is
  the engine's unit icon atlas (`IconsAtlas_0`, drawn into, stored uncompressed). With the background apps killed
  first (`am kill-all`: 3.78 GB available) the replay was killed 45 s into the load, 1.1 GB still available. Android's
  kill daemon says why (logcat): "Reclaim 'com.underarmcape.bardroid' ... oom_score_adj 0 ... reason: min2x watermark
  is breached even after kill": the load allocates faster than the kernel frees and compresses, the free pages fall
  under twice the kernel's minimum, and lmkd kills the app (the engine with it), whatever "available" says. So on the
  8 GB phone the load's burst has to shrink (the loading pictures at the screen's size, the projectile atlases, the
  icon atlas), or the 16-player stage runs on a 12 GB phone (the Fold7).

## "Calculations from others"

Recoil is lockstep: players exchange only their commands, every client simulates every frame itself and reports a
checksum, and the server compares them. So no client can take results from another while it plays:
- A **player's** phone must simulate: its own commands depend on the state, its checksum is what keeps the game fair,
  and trusting another machine's results would let that machine decide the game.
- A **spectator's** phone could, in a new engine mode: a client that keeps up (a PC player, or BAR's server) streams
  the synced state (units' positions, health, build progress, projectiles) at e.g. 10 per second, and the phone
  draws it without simulating. That is an engine and server feature for BAR's developers (a new network message, a
  "draw without sim" spectator, state compression), not something a client can do alone. What it would save and
  cost on the phone: the whole Sim (30-45 ms per frame in BAR's benchmark when hot) against receiving and decoding
  the state (a 1,000-unit battle: ~32 bytes per unit, ~320 KB/s raw at 10 Hz, much less as deltas).
- Pieces of the sim (pathing, LOS) are cheap per frame (Tracy, research: 0.1-0.4 ms): not worth taking from others.

Next for this part: measure, from a 16-player replay, the state a spectator would need per second (units alive,
changed fields per frame) against the phone's Sim per frame, as numbers for BAR's developers.

## Status

- 2026-11-04: branches and folders set up; Arm GNU toolchain 13.2.Rel1 (GCC 13.2, mingw-hosted, aarch64 Linux)
  downloaded into the portable toolchain. `gcc-stock` built (the official flags, checked in its compile lines) and
  installed on the dev phone as `engine-sim/gcc-stock`. Replays for the checks: two 8v8 Supreme Isthmus games BAR's
  server recorded (engine 2026.07.04; `engine-sim\replays`).
- 2026-11-04, evening: stages 1-3 done, stage 4's replays done, its 16-player part waiting.
  - Stage 3, the benchmark (CPU work per simulated frame, "Findings"): `gcc-stock` -6.4 % instructions against the
    official engine, the sim changes (`gcc-sim1`) about the same again, profile-guided (`gcc-pgo`) -13 %;
    `gcc-pgo-lse` inside run-to-run noise. Game speed on a hot phone not measured for these (heat swings more).
  - Multithreading: the engine's own thread choice changed nothing measurable (the main thread is the limit); the
    big gain was scheduling, +26 % game speed with every CPU allowed, shipped on `main` (46cfe85) and on the Fold7.
  - Stage 4, replays: 0 desync warnings in 20 minutes of the SpeedMetal server replay for official, `gcc-stock`,
    `gcc-pgo`, `gcc-pgo-lse` (and the research's clang build); the fast-math control 1,190.
  - "Calculations from others": not for players (lockstep); a spectator state stream is BAR's to build (section above).
  - Stage 4, 16 players: the 8v8 replay does not load on the 8 GB dev phone (Android's low-memory killer during the
    load); `ProjectileAtlasDownscale = 2` saved ~200 MB, not enough. Kailil's choice (2026-11-04 ~21:10): the dev
    phone, "Cut wherever necessary".
- 2026-11-04, night: 8v8 memory on the dev phone (`tools/engine-sim/replay-memory.ps1`, build `gcc-8v8`).
  - Where it goes (a 1v1 skirmish, Android's report for the engine): GPU 2.0 GB (textures of 64x64 or more ~0.5-0.9
    GB, buffers ~0.4 GB, the rest small items and the driver's own), the engine's own memory 2.4 GB (0.7 GB in RAM,
    1.7 GB swapped). In an 8v8's load: the models' buffers 336 + 104 MB, the pathfinder 379 MB (synced: stays),
    then BAR's LuaRules and LuaUI; Android kills when the load allocates faster than it can swap the engine's cold
    memory out (11 GB of swap free; ~3.4 GB available at the start, Android and its apps hold ~4.1 GB).
  - Cut so far: effect atlases at 1/4 (-322 MB GPU), loading pictures at 1024 (-55 MB), game resolution 70 % (the
    screen-sized targets halved), the models' CPU copies freed after upload (-440 MB), on-demand models
    (`PreloadModels = 0`) with the buffer grown by half (no 8 MB copy churn). Not helping: closing background apps
    (`am kill-all`), a "pacer" pausing the engine while memory is low (`dev-env-pacer.sh`: available memory kept
    falling during 3 s pauses).
  - Results: the 2026-10-13 replay (BAR test-31604) loaded once (on-demand models) and played ~80 s at 1,153 units,
    fast-forwarding to 10:00 on a hot phone, until the GPU driver dropped the context ("submit failed ... Resource
    deadlock avoided", the engine hung: the 2026-11-02 replay hang's signature) after ~40 s of "GPU fence wasn't
    signalled within 100 ms". The 30-minute 2026-10-26 replay (test-31723) is still killed in its load.
  - Next: free the on-demand models' CPU copies too; find the GPU memory the logs do not show; the heaviest LuaUI
    widgets for a replay; and for the GPU drop, play at x1 (no fast-forward) with the frame cap at 30.
  - The engine's own memory, second by second through the 30-minute replay's load (`gcc-8v8`, every cut, on-demand
    models; mimalloc's three 1 GiB arenas hold it): the map +580 MB, its tiles +715 MB (streamed: kept in RAM, which
    swaps, not on the GPU), the pathfinder +270 MB, LuaRules +600 MB, LuaUI +450 MB: 2.9 GB at "finished loading",
    1.8 GB of it in RAM, GPU 1.64 GB. The replay loaded completely and was killed as its playback began. Not the
    cause: mimalloc keeping freed memory (`MIMALLOC_PURGE_DELAY=0`: -220 MB only), the archive cache (a file is kept
    only from its second read; 0 bytes at a replay's exit), Lua itself (134 MB in a 1v1: the app's `[bardroid-perf]`
    line says it now). With the official engine the effect atlases' source pictures also stay in RAM for the game
    ("reloadable" atlases: ~360 MB), which `ProjectileAtlasDownscale` already shrinks 16x. Also not it: the map's
    unpacked .sd7 (a test build freed every 7z extraction buffer before the pathfinder's load: 1 MB; reverted).
  - Correction: the runs "killed at finished loading" were `replay-memory.ps1` itself: it took any launcher.log line
    with "low memory" for Android's kill, and the app's "BAR Droid low memory" widget logs that phrase as LuaUI
    loads, so the tool force-stopped its own game (fixed: the app's "ended for lack of memory", or the engine gone).
    With the fix, the 30-minute replay loaded and played: x1.00 at 60-68 fps up to 2:11 of game time (276 units),
    then the hot phone (GPU held at 220 MHz, thermal level 8, 73.6 C, after an evening of runs) fell to 4-12 fps,
    and Android's low-memory killer ended it at 2:41 (318 units; 964 MB available a moment before).
  - The models' CPU copies are now given back after every upload in either load mode (`vertBase`/`indxBase`).
  - **The 30-minute 8v8 played to its end on the dev phone** (2026-11-04, 22:58-23:28; the 2026-10-26 Supreme
    Isthmus replay, BAR test-31723, from its start at normal speed): `gcc-8v8` with `ProjectileAtlasDownscale = 4`,
    `NamedTextureMaxSize = 1024`, `MaxDrawnParticles = 3000`, `PreloadModels = 0`, the game resolution at 70 %, the
    frame cap at 30, background apps closed (`am kill-all`). 28:58 of game time, up to 3,680 units; game speed median
    x1.01, below x0.95 1 % of the time (lowest x0.70); 12-29 fps, 17.6 on average; memory available never under
    553 MB, GPU driver up to 1.80 GB, the engine ~1.1-1.6 GB in RAM and ~1.5-1.8 GB swapped; the phone up to 70 C;
    **0 desync warnings** over the whole game (every player's checksum the server recorded matched).
  - Freeing other apps' memory from the app (Kailil, 2026-11-04): Android lets no app force-stop others, and since
    Android 14 `killBackgroundProcesses` reaches only the app's own; One UI's memory screen ("Clean now",
    `com.samsung.android.sm.ACTION_RAM`) needs `READ_SEARCH_INDEXABLES`, a system permission; Device care's own page
    (`com.samsung.android.sm.ACTION_DASHBOARD`) opens from any app, one tap from Memory. On the dev phone closing the
    background apps (`am kill-all`, about what "Clean now" does) gave ~0.4 GB and did not change the 8v8's outcome.
- 2026-11-05, night: **toward a locked 30 fps in the late 8v8** (Kailil, 2026-11-04: "Make it happen ... start super
  aggressive"; 2026-11-05: "Do not stop until we get 30fps 8v8"). Every run: the 2026-10-26 replay from 20:00 for
  150 s at normal speed (3,150-3,500 units), `gcc-8v8` and its successors, the frame cap off, the phone hot (AP
  62-68 C, the prime core capped at 1.4-1.8 of 3.36 GHz, the GPU at 220-615 MHz).
  - Measuring: `replay-memory.ps1` now logs the main thread's split every 10 s (`[simdraw]`, `bardroid_simdraw.lua`
    from the engine's always-on "Sim" and "Draw" timers, with the drawn frames over 50 and 100 ms; `-Timers`: the
    whole profiler, the busiest timers and the longest single runs; `-Shots <game second>`: three screenshots from
    that second, the camera close to where the units are thickest, the same in every run of a replay) and keeps
    the run's infolog. `Spring.GetProfilerTimeRecord` failed on every call (it read its optional argument after
    pushing its results): fixed on the branch. User widgets cannot time other widgets (BAR keeps
    `widgetHandler.widgets` from them), so the branch times each Lua call-in by name while the profiler is on
    (`Lua::<handle>::<call-in>`). The app keeps a render scale the tools set over adb (Prefs reset anything but
    100/85/70/native to 100: the first "1 %" runs were at 100 %); 10 (1 % of the pixels, 200x93) crashes BAR's UI
    load (NaN sizes in its widgets, then a segfault), so the CPU-side runs use 30 (9 %).
  - Where the main thread goes at 100 % and 3,400 units, 11-15 fps: Sim 57 % of real time (~19 ms a simulated frame),
    Draw 16 % (~11 ms a drawn frame), Update 14 %, the buffer swap 11 %; Lua call-ins outside the synced game
    (widgets, unsynced gadgets) ~19 % across all of them, the game's synced gadgets ~6 %.
  - Cut for the drawing side (settings): `MaxSounds = 16` (OpenAL mixing was 10 % of the engine's CPU samples),
    `UnitIconDist = 50`, `GroundDetail = 30`, `FeatureDrawDistance = 1500`, `Water = 0`, `MaxDrawnParticles = 500`,
    `WorkerThreadCount = 8` (every core): game speed x0.91 -> x1.00, 11-13 -> 12-15 fps at 100 %. Mesa's GL thread
    (`mesa_glthread=true`): no gain.
  - **The render scale at 30 % (9 % of the pixels): 20-26 fps, median ~23, x1.01**; Sim fell to ~15 ms a frame (the
    GPU's lighter load leaves the CPU faster clocks: the phone shares one heat budget).
  - Sim threading (sync-exact, 0 desync warnings in each run): the units' previous-frame transforms (~5 % of the
    main thread) and their LOS status checks (~2.5 %) on every worker, the LOS events still raised in the original
    order on the main thread (a status a call-in changed meanwhile is worked out again there).
  - At 30 % and 3,200-3,500 units (median 21-23 fps over 14 samples; the phone's heat moves a run by about +-2):
    Sim ~15 ms a simulated frame (45 % of real time at x1), Draw ~10.5 ms a drawn frame, the rest ~30 %: Update
    (Lua ~3 ms, the unit drawer's per-frame update ~2.5 ms) and the swap. The main thread runs ~80 % of the time.
    Lua outside the synced game ~22 % of real time (with the profiler on), a long tail: BAR's Nano Particles GL4
    gadget 1.7 % (its `NanoParticleMode = 0` does not idle it in this BAR version), unit sound effects 0.9 %, the
    app's own touch widget 0.8 %, Fire & Smoke GL4 0.7 %, Defense Range GL4 0.7 %, and ~30 more at 0.1-0.5 %.
  - No change (within the heat noise): units drawn as icons almost everywhere (`UnitIconDist = 10`), 5 engine
    threads instead of 8 (the little cores), nine effect gadgets left out of unsynced LuaRules (the GPU's load fell
    from ~89 % to ~60 % at its thermal cap of 220-295 MHz, the fps did not move).
  - The swap (`BARDROID_SWAP_LOG=1`, the pace library times it): ~7 ms a drawn frame, nearly all inside Mesa itself
    (X server waits 0, the driver's ioctls ~0.13 ms): the main thread waits for Mesa's driver thread (`gdrv0`) to
    finish the frame's commands. That thread is ~34 % busy (~15 ms of CPU a drawn frame), 29 % of it in atomic
    reference counts (`__aarch64_ldadd4_acq_rel`: buffer and texture tracking; a frame has only ~220 draw calls but
    ~400 texture binds, 700-1,000 buffer binds and 24 framebuffer binds, `libbardroid_pace_dev.so`'s counter).
    Without Mesa's driver thread (`GALLIUM_THREAD=0`): 6 fps (91 ms a drawn frame). The main thread alone on the
    prime core and the rest on the others (a launch-bar.sh trial): no change. BAR's interface hidden: no change.
  - **The deferred present** (`BarDroidDeferSwap = 1`, GlobalRendering.cpp/SpringApp.cpp): the drawn frame is handed
    to the window only before the next one is drawn, after the next simulated frames ran while the driver thread
    finished it. The swap 7 -> 2 ms, **21-22 -> 26 fps median** (up to 30) uncapped; with the 30 fps cap (the
    display at 60 Hz) 24 (a frame just over 33 ms waits for the next vsync slot). 0 desync warnings.
  - With the cap, the vsync-aligned pacing waited ~7 ms in 64 % of the frames while 36 % came too late for their
    slot (`BARDROID_SWAP_LOG` now logs the cap's waits): after a late frame the next ran two simulated frames to
    catch up and was late too. **One simulated frame per drawn frame while few are waiting**
    (`BarDroidMaxSimPerDraw = 1`, NetCommands.cpp: two from 4 waiting, all from a second's worth, as a replay's skip
    needs): **29 fps (27-30), 92 % of the pictures held exactly two vsyncs**, game speed x1.01, 0 desync warnings
    (with the cosmetic widgets below off).
  - Also measured, each within the heat noise (+-1 fps) alone: the units' G-buffer pass off (`SetDrawModelsDeferred
    (false, false)`; shields read it), fewer particles, `for_mt_chunk` in four chunks a thread, the features' save
    on the workers, BAR's unit sound gadget's unsynced half left out; BAR's cosmetic widgets off (Defense Range GL4,
    the four Sensor Ranges, AllyCursors, Commander Name Tags, Ally Selected Units: -1.3 ms a drawn frame); every BAR
    widget off: drawing 10 -> 6.5 ms a frame.
  - The same with BAR's whole interface (no widget cut): 26 fps (24-28).
  - **On the Fold7 since 2026-11-05 ~08:45** (Kailil: "Push this to the zfold but not the resolution changes or
    cosmetic widgets disabled"): build `gcc-fold` (all the changes above; the sync version reported as `2026.07.04`,
    `GameVersion.cpp`, as BAR's servers compare it exactly), started by the Fold7's `files/bar/dev-env.sh` (with
    `BARDROID_PACE_LATE=0`) and `dev-springsettings.cfg` (`BarDroidDeferSwap = 1`, `BarDroidMaxSimPerDraw = 1`) only;
    no graphics, sound, widget or gadget setting changed. Before: the whole 29-minute 8v8 replay simulated by that
    build (fast-forward to its end) with 0 desync warnings, and the lobby test on the dev phone ALL PASS with it.
    Back to BAR's engine: delete those two files on the Fold7.
  - At full resolution (the Fold7's setup on the dev phone, BAR's whole interface): **14-18 fps, median 16** (11-13
    before these changes), the GPU 99 % busy at its thermal cap (295-401 MHz). GPU time per pass (GL time-elapsed
    queries, `BarDroidGpuTimer.h`, with the profiler on; BAR's own per-widget marks get one each), in % of real time:
    unit and feature models 15, terrain 6.8, see-through models 5.2, water 1.1; and of BAR's widgets **Sensor Ranges
    Sonar 8.6, Sensor Ranges Radar 3.8, Sensor Ranges LOS 2.0, Jammer Preview 1.2** (the range circles of every
    unit a spectator sees: ~16 % together), GUI Shader's blur 1.7, Defense Range GL4 1.6, Nano Particles GL4 0.9.
  - **Mobile drawing overhaul** (Kailil, 2026-11-05 ~09:50: sensor ranges off in big games, "optimize the unit models
    ... be as heavy handed as you need", "go as wild as you need to. To keep temps down"). Same replay, game seconds
    1210-1330, full resolution, profiler on, a hot phone (GPU 401-475 of 615 MHz, prime core 1.2-1.4 GHz):
    - BAR's sonar, radar and LOS circles at opacity 0 and the jammer coverage off (the app's `bardroid_sensors.lua`,
      games of 10 teams or more): **11.2 -> 14.4 fps**; their 13 ms of GPU a frame gone. The phone is then limited by
      the simulation (Sim 57 % of the time, the GPU 51-69 % busy).
    - `BarDroidModelSimplify` 0.25 / 2 elmos: 1.35M -> 0.98M triangles; models 8.6 -> 7.9 ms of GPU a frame,
      see-through models 2.9 -> 1.9 ms; fps the same (simulation-bound); no difference visible at the closest zoom
      (`replay-memory.ps1 -Shots`). 0.10 / 6 elmos only reaches 0.93M: BAR's models have hard edges and UV seams on
      most edges, which an edge-collapse simplifier keeps, and many pieces are under 48 triangles.
    - Where the simulation's ~20 ms a tick goes (late 8v8, 3,300 units, hot dev phone): unit movement 3.6 ms, unit
      scripts 3.2, BAR's synced gadgets 2.3, unit updates 1.9 + 1.3 (slow), line of sight 1.1, paths 1.0 + 0.75 (map
      updates), weapons 0.9, projectiles 0.75. Recoil already runs the parallel-safe parts on the workers: movement's
      traversal plans and collision detection (stages 1 and 3), the scripts' animation ticks; what stays serial
      changes synced state in an order every client must repeat (movement stages 2, 4 and 5, "the vars are synced and
      that's what is stopping this being MT'ed", upstream's own TODO; the COB threads; the gadgets, which are BAR's game
      code and cannot change). What is left there is ~1.5 ms a tick of movement stage 5 and part of the scripts' 3.2,
      at a real desync risk: the heat that remains is cut on the drawing side (fewer drawn frames, cosmetic effects).
    - CPU profile of the same window (`phone-engine.ps1 -Replay ... -Perf 40`, `gcc-refl`, 0 desync warnings): the
      main thread 45 % of the samples, the three workers 33 %, **OpenAL's mixer 10 %** (128 sounds, EFX reverb on,
      48 kHz, OpenAL Soft's default resampler), Mesa's driver thread 8 %. On the main thread: Lua ~13 % (luaV_execute
      5.3, luaH_get 5.3, luaD_precall 2.7), **`__kernel_clock_gettime` 7.2 %** (timer reads; callers not known
      without a call graph), the units' animation ticks 3.2, line of sight 2.1, previous-frame transforms 2.0, ground
      heights 1.9, the sync checker 1.4, COB threads 1.4. Next: the mixer with EFX off / fewer sounds / a cheaper
      resampler (client-side, online-safe), and a call-graph profile for the clock reads.
    - The see-through pass is mostly map features in the fade band (`FeatureFadeDistance` 4800 to
      `FeatureDrawDistance` 6000: drawn blended, twice with water: below and above its surface). Without the band
      (`FeatureFadeDistance = 6000`) those features join the solid pass: +1.3 ms there, -1.6 ms of see-through, a net
      -0.3 ms for features popping in: not kept. The ground's anisotropic filtering off (`SMFTexAniso = 0`): no gain
      (terrain 3.9 -> 4.2 ms, within the heat noise): not kept.
    - So the models' GPU time is mostly not their triangles (a third fewer: -10 %), nor draw calls (~220 a frame in
      all, above); at 9 % of the pixels it was 9.5 ms against 13.5 at full resolution (hotter, other clocks), so
      not mostly pixels either. Not known yet; the dev phone draws them with the engine's plainer shading (the
      low-memory mode keeps BAR's GL4 unit shaders off), the Fold7 with BAR's GL4 shaders.
  - Once in ~20 runs the GPU driver failed ("submit failed -1 (Resource deadlock avoided)", KGSL refusing a context
    after a GPU fault) and the engine hung, here before the game started (05:46, a cool phone): the 2026-11-02 and
    2026-11-04 hangs' signature, before any of these changes; `replay-memory.ps1` now ends such a run at the
    engine's watchdog line.
