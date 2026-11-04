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

## Status

- 2026-11-04: branches and folders set up; Arm GNU toolchain 13.2.Rel1 (GCC 13.2, mingw-hosted, aarch64 Linux)
  downloaded into the portable toolchain. `gcc-stock` built (the official flags, checked in its compile lines) and
  installed on the dev phone as `engine-sim/gcc-stock`. Replays for the checks: two 8v8 Supreme Isthmus games BAR's
  server recorded (engine 2026.07.04; `engine-sim\replays`).
