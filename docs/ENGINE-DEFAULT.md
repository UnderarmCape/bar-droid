# Plan: the phone engine as the app's default

Kailil, 2026-11-13, after the phone Settings landed on the engine branch: shipping that engine to every player
("yes plan it"). Today the app ships BAR's official Recoil engine; the engine branch (`engine/sim`,
`docs/ENGINE-SIM.md`) runs only where `files/bar/dev-env.sh` starts it: the dev phone in tests, and Kailil's Fold7
since 2026-11-07.

## What players gain

- **The app's controls everywhere.** The app's widgets load as the game's (`BarDroidGameWidgetsDir`), not as user
  widgets: a host's "no user widgets" or "no unit control widgets" option no longer switches the touch dock, the pad,
  presets or auto retreat off, and first person works in every game.
- **The phone Settings** (`bardroid_options.lua`): BAR's Options laid out for upright and sideways, every switch
  working. Without the phone engine players keep BAR's own window, too wide upright.
- **The phone versions of BAR's costliest Lua** (`BarDroidPhoneLuaDir`, 7 patches to BAR's own widgets and unsynced
  gadgets) and the memory settings that let 8 GB phones load 16-player games (`ProjectileAtlasDownscale`,
  `NamedTextureMaxSize`, `S3DModelVAO` ...).
- **Speed, from the exact simulation rewrite**: BAR's benchmark game speed +4-5 %, Sim -3 to -5 %, Update -7 to -12 %
  on a hot phone (gcc-all3/4/5 against gcc-fold7, ENGINE-SIM "The exact simulation rewrite").

## The one risk that matters: sync

Every client simulates every frame and the server compares checksums. An engine that computes one synced result
differently desyncs the game for all its players, and BAR's developers allow modified engines online in good faith
only (a BAR developer via Kailil, 2026-11-04). The changes fall in two kinds:

| kind | what | sync risk |
| --- | --- | --- |
| unsynced | the app's widgets as the game's, phone Lua (LuaUI and unsynced LuaRules only), memory and drawing settings, the CPU topology (which cores run threads), the profiler fix | none: the synced states never see them |
| synced, exact | the simulation rewrite (Lua VM loop, movement, unit scripts and animations, line of sight; each behind a switch, default on) | must be bit-identical; proof so far: 3 server replays of 3 BAR releases (a 1v1, two 8v8s), 0 desync warnings |

Three replays are good evidence and a small sample for code on the synced path that BAR's every game runs through.

## Decisions for Kailil

1. **What ships on by default.** Recommended: the unsynced changes on by default, the simulation rewrite built in but
   switched off online (its switches at 0, `BarDroidMoveAll = 0`, `BarDroidUnitsAll = 0` and the Lua VM's) until it
   has passed many more server replays (stage 2), on in skirmish and replays from the start. The other way: the
   Fold7's engine as it is, rewrite on everywhere.
2. **Where the binary comes from.** Recommended: inside the APK (the 42 MB `spring` is 17 MB compressed: the APK
   from 19 to ~36 MB), one build per BAR engine version; no server of ours to run. The other way: a download from a
   GitHub release of the project.
3. **The engine's source, public.** Recoil is GPL-2.0-or-later: an APK that carries a modified `spring` must offer its
   source. The branch (`bardroid/sim` and its parts in `hailmary-work`) goes to a public fork of RecoilEngine when the
   app goes public (a push only Kailil does), and README names the changes, as the good-faith rule asks.

**Kailil's answers (2026-11-13):** "1. You're recommendation 2. Inside the apk 3. Yes": the unsynced changes on by
default, the simulation rewrite off in online games until its replay count is met (on in skirmish and replays); the
binary inside the APK; the engine's source public with the app (his push).

## Status (2026-11-13)

- **Engine: the rewrite off online** (engine branch 869988d, 528c6a5, bar-droid-engine docs/ENGINE-SIM.md "The rewrite
  off online"): `BarDroidSimAllowed` in `Game.cpp`; every switch of the rewrite reads 0 (stock code) with a remote host,
  with more than one player on a local host, or before a game's setup has arrived; as set in the menu, replays and
  one-player games. `BarDroidSimOnline = 1` turns it on online for tests. The reason is in the infolog
  (`[BarDroidSim]`).
- **The first phone build:** `phone-2026.07.04-528c6a5` (gcc-combined: Arm GNU 13.2, `-O3 -march=armv8.2-a
  -mtune=cortex-x3`, the PGO profile, as gcc-all4 which the Fold7 has played since 2026-11-07), made into the release
  folder by `tools/phone-engine-release.ps1`.
- **Into the app** (stage 3): build.gradle carries it as assets when `local.properties` names
  `bardroid.phoneEngine` (the APK 19 -> 39 MB); `Installer.installPhoneEngine` sets up `engine/recoil_<ver>-phone`
  at every start once the official engine is there (spring copied when BUILD.txt changed, the rest linked);
  launch-bar.sh starts it with the app's widgets as the game's and the phone Lua unless the launcher's "Phone engine"
  is off, and sets a build aside that exits with an error before it ran at all (no `[BarDroidSim]` line: a binary the
  phone cannot run); `Updater.cleanupEngines` removes a
  `-phone` folder with its engine. `tools/publish-check.ps1 -Apk` fails an APK carrying it until NOTICE.md names the
  public source.
- Not yet defaults: the Fold7's own engine settings (`dev-springsettings.cfg`: model simplification, texture and
  projectile atlas sizes, the ASTC model textures made on the laptop, deferred swap, ...). They stay Kailil's until
  each is checked as a default for every phone (the ASTC folder would have to ship too).

## Stages

1. **A release build of the phone engine.** `tools/engine-sim/build-engine.ps1` from the tag BAR's servers run
   (2026.07.04 today) plus the branch, the official floating-point flags (ENGINE-SIM "Sync rules"), its source commit
   written into the binary's version line and beside it. Debug symbols kept on the laptop for crash reports.
2. **The gate every build passes before it ships** (a script, `tools/engine-gate.ps1`): the server replays to their
   end with 0 desync warnings, every switch at its shipping value (today 3; for the rewrite's switches on online: 20
   or more across the last BAR releases, 8v8s among them, collected from BAR's replay site); the phone tests
   (dock-phone-test, touch-phone-test, pad-test with and without -Online, pace-test, lobby-phone-test, remake-check);
   BAR's benchmark no slower than the official engine; the Fold7 (Kailil's games) a day on it.
3. **Into the app.** The APK carries the build and the engine version it was made for. Installer, after the official
   engine of that version is installed (as now), makes `engine/recoil_<version>-phone`: the official folder's files
   linked, our `spring` copied in (never an exec'able path into `nativeLibraryDir`). launch-bar.sh starts it with
   `BARDROID_GAME_WIDGETS=1` and `BARDROID_PHONE_LUA=1` when its version is the one BAR's servers run; the dev-env.sh
   lines become the defaults. Launcher setting "Phone engine" (on; off: BAR's official engine, the way back for anyone
   it fails).
4. **When BAR moves to a new engine.** Updater installs BAR's new official engine as now. With no phone build for it
   in the APK, the app runs the official one (BAR's own Settings, the app's widgets as user widgets: everything that
   works today) and the launcher says the phone engine waits for an app update. Then: the branch rebased on the new
   tag, built, gated (stage 2), a new APK. Updater's rollback covers it: a phone engine that fails fast on its first
   start falls back to the official one.
5. **The rules and docs.** CLAUDE.md's "Keep the engine binary unmodified" becomes "BAR's engine version, official or
   the phone build of it"; CONTRIBUTING, README (what the phone engine changes and why, the setting), docs/UPDATES.md
   (stage 4), NOTICE.md (Recoil's license and where its source is).

## Effort

Stages 1-3: about a day of work and a night of replays. Each BAR engine release after: the rebase (the branch's
changes sit behind `-DBARDROID_SIM` and switches, so most rebase cleanly), a full build on the laptop and the gate (a
few hours of replays on the dev phone). BAR's servers have run 2026.07.04 for all of this project so far.

## Not in this plan

The sim offload research (phones skipping the simulation): it needs BAR's own work (ENGINE-SIM "Calculations from
others"). Synced changes that are not exact: never (they desync).
