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
    ("reloadable" atlases: ~360 MB), which `ProjectileAtlasDownscale` already shrinks 16x.
