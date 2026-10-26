# DRAFT (not posted): beyond-all-reason/RecoilEngine (or BAR's bug channel first)

**Before posting:** check whether it still crashes on the current engine/BAR release, and whether a save from BAR's
released game (not the controller game) crashes too. The controller game changes LuaUI only, so the synced state
should be BAR's own, but a maintainer will ask.

**Title:** Loading a skirmish save crashes right after "Loading Saved Game" (access violation, Windows and Linux arm64)

**Body:**

A singleplayer save (vs BARb, Death Valley, saved at frame 88559) crashes the engine every time it is loaded, at the
same point on two platforms:

- Windows, engine 2026.07.04: `spring.exe --isolation --write-dir <dir> 20261026_063343.ssf` → access violation in
  spring.exe right after "Loading Saved Game" (offsets from the image base: 0x965868, 0x9626f2, 0x5b3fd2, 0x535eae,
  0xd5d099; no symbols in the release build).
- Linux arm64, the same engine 2026.07.04 (the official arm64 build in a container on an Android phone, where the save
  was made): SIGSEGV at the same log line, no stack.

The save file is attached. Game: a developer build of BAR (BAR's release of 2026-10-20 with a LuaUI-only controller
overlay); map Death Valley v1.0.1; one human, one BARb.

Steps: put the save in `Saves/`, start it with the command above (or from the lobby's Load Game).

_This report was written with the help of an AI assistant (Claude); the crash was reproduced by running the engine._
