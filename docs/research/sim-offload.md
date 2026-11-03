# Simulation offload for low-spec phones: a study for BAR's and Recoil's developers

Kailil, 2026-11-03: "try the simulation skipping anyways I want to give the results to the devs to give them an option
for how to implement lower spec phones into multi-player. Like the phones rely on other players to keep them sync and
get the math from them."

Work in progress. Every experiment here runs offline on our own devices; nothing in it touches online play or the
shipped app, which keeps BAR's official, unmodified engine.

## How BAR plays online today

Recoil (BAR's engine) is a lockstep simulation. Every client, players and spectators alike, simulates every game frame
(30 a second) of every unit itself; the network carries only the players' commands; the clients compare checksums of
their game state and a client that differs is dropped ("sync error"). A client keeps only the present state, not past
frames; the replay file is the command stream. A client that cannot simulate fast enough falls behind, and with BAR's
speed control the game slows down for everyone.

So a phone cannot skip frames, or take results from others, without the engine changing how a client works. This study
measures what such a change would have to deal with on a phone.

## 1. Where a phone's time goes in a big battle

BAR's "Benchmark BAR" scenario (650 Grunts against 650 Pawns, ~1 300 units, 2 000 frames) on the dev phone (Galaxy S23
Ultra, Snapdragon 8 Gen 2, 8 GB), warm, frame cap off, 2026-11-03:

| | Sim | Draw | Update | game speed |
|---|---|---|---|---|
| per frame, profilers off (12:43) | 52.6 ms | 26.0 ms | 11.2 ms | x0.40 |

At this size the phone simulates at 40% of real time: online it would fall behind, or slow the game for everyone.

BAR's gadget profiler on the same run (13:06; the profiler roughly doubles the Lua side's cost, Sim 96 ms):

- Lua game logic in the simulation (BAR's synced gadgets): **11.1%** of the running time, about a sixth of the
  simulation's share; all LuaRules call-ins (synced and unsynced) 17.3%.
- The rest of the simulation, about five sixths, is the engine's own work: movement and pathing, collisions,
  projectiles, weapons and targeting.
- Lua memory 269 MB, 20% of it the synced states.

So "get the math from someone else" means mostly the engine's work, not BAR's scripts: a game-side (Lua) shortcut would
save a sixth at most.

## Next

2. What a phone would receive instead of simulating: a late game's full state (BAR's save on the phone: size, save and
   load time) against the command stream it receives now.
3. A snapshot-sync try: one device simulates, the phone loads its states.
4. Whether an engine build that really skips frames is feasible here.
