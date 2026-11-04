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
  | oryon-lto-fast (research build with `-ffast-math`: the control) | **1,190, from frame 0** |

  So clang's missing `-fsingle-precision-constant` did not show in 20 minutes of a real game (Recoil's synced math
  writes its float literals as floats); GCC stays the safe choice. All builds played the replay's measured minute in
  real time on the dev phone (x1.00).
- **Old replays and the app's menu copies** (a `main` bug found here, fixed there: 9dd7f16): the replay's BAR release
  is older than the copies, BAR removed them, and launch-bar.sh switched them off for every later game.

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
