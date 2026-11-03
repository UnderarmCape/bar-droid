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

## 2. What a phone would have to receive instead

The engine can already write a game's whole state and start from it: BAR's save (`/save`, a `.ssf` file). That is the
nearest thing to "the math from someone else" Recoil has. A skirmish on the dev phone with the benchmark's armies (650
Pawns against 650 Grunts) given at frame 90 and saved three times as they fought (2026-11-03):

| units at the save | file (compressed) | writing it on the phone (game frozen) |
|---|---|---|
| 1 226 | 11.3 MB | 12.0 s |
| 785 | 11.5 MB | 8.4 s |
| 417 | 10.0 MB | 6.5 s |

Uncompressed, the 1 226-unit state is 58.1 MB of engine state and 19.3 MB of Lua state (77 MB; the engine's own
save log). The file's size hardly follows the units: most of it is the fixed part (map, features, Lua state).

Starting from that save on the phone took 69 s, of which **2.5 s** were the state itself ("Loading Saved Game"); the
rest is what every game start does (map 7.8 s, textures, pathing 2.6 s, 24 s of interface Lua).

What lockstep sends instead, from replays on the dev phone (`tools/demo-rate.py`, the command stream):

| game | per game-second |
|---|---|
| online, 16 players (three replays, minutes 2-15) | 4-7 KB, up to 11.7 KB |
| skirmish against one AI | 0.35 KB |

So a full state is about 2 000 times a busy online game's command stream for one second of play. A phone fed whole
states every 10 s would need about 1.1 MB/s (9 Mbit/s) of download and spend 2.5 s of every 10 loading them, and
whoever made the states would freeze for seconds to write each one (12 s on this phone; a PC much less). Whole states
work for catching up (a late join, a reconnect), not for continuous play. Continuous play needs the engine to send
changes since the last state (deltas), or only the part of the world a player sees: the engine has neither today.

## Next

3. A snapshot-sync try: one device simulates, the phone loads its states.
4. Whether an engine build that really skips frames is feasible here.
