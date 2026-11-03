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

## 3. Can a running game take a state from elsewhere?

Not with today's engine. Recoil applies a saved state only while a game starts: `CGame::Load` reaches "Loading Saved
Game" (`rts/Game/Game.cpp`, ~line 460: `saveFileHandler->LoadGame()`) after the map, definitions and pathing are
loaded, and nowhere else; `PreGame` creates the handler from the file named on the command line. So "the phone takes
the math from another player" with the stock engine means a full restart of the game for each state: 69 s on the
phone, with the game gone meanwhile. The snapshot-sync try therefore needs no more experiments to be answered: the
engine cannot do it during play.

Where whole states already fit is catching up. A client that joins a running game (a spectator, a player who
reconnects) receives the game's commands from the start and re-simulates every frame up to the present; a phone that
simulates a big late game at x0.40 can never catch up that way. Starting it from a recent state that another client
saved (11 MB, 2.5 s to load on the phone) and then replaying only the commands since would let it in. The engine has
both halves (saving any time, starting from a save, replaying commands); what is missing is a host or a peer sending
a fresh save to a joining client, and the client continuing from it in sync.

## 4. A modified engine for a real skip

Building Recoil is possible here (a source checkout is on the laptop; its Linux build is Docker-based, or native on an
arm64 Debian, which the app's own container on the dev phone is). Laptop engine builds wait for Kailil's word
(BARGAMEPAD rule). A real "skip" would be engine design work, not a switch: a client that does not simulate needs the
world from somewhere each frame (deltas of what changed, or of what its player can see), a way to send its commands
against a world it did not compute, and a different sync check, since lockstep's checksums assume every client
simulated. That is the proposal to take to the developers, with the numbers above.

### Catching up today, on a real phone

Kailil's own late joins of online games as a spectator on his Galaxy Z Fold7 (Snapdragon 8 Elite), drawing switched
off by the app while far behind (docs/HISTORY.md, "Catch-up when joining a running game"): the phone re-simulated at

| units in the game | catch-up speed |
|---|---|
| 2 400 | x2.0 |
| 3 000-3 400 | x1.6-1.9 |
| 4 000-4 500 | x1.2-1.5 |
| past 5 000 | x0.9-1.0 |
| 6 000-6 800 | x0.6-0.7 |

with the CPUs held at ~1.4 GHz by heat. At x1.5 a client gains half a minute a minute: joining 40 minutes into a game
takes over an hour of catching up; past ~5 000 units the phone never catches up (it stayed 9 minutes behind). From a
fresh save the same join would take a game start plus the commands since the save, about a minute and a half on the dev
phone. The network was not the limit: those games' command streams were 5-6.5 KB a game-second, which the server's
default 64 KiB/s link sends 10-13 times as fast as the game runs.

## Summary for BAR's and Recoil's developers

- A phone (Snapdragon 8 Gen 2) simulates a ~1 300-unit battle at 40% of real time; five sixths of that is the engine's
  C++ simulation, a sixth BAR's synced Lua.
- A whole game state is ~11 MB compressed (77 MB in memory) at that size, ~12 s to write on the phone, 2.5 s to load;
  a busy online game sends 4-7 KB of commands a second.
- Recoil can start from a state but not take one during play.
- Near-term, feasible with today's pieces: late join / reconnect from a recent save instead of re-simulating from frame
  0. A phone catches up at x2.0 with 2 400 units and not at all past ~5 000 (Kailil's joins on a Fold7); from a save
  it would be in within about a minute and a half.
- Long-term, the "thin client" Kailil describes: state or interest-based deltas from a host, commands sent against
  them, sync checked differently. An architecture change in the engine.

## Method notes

Dev phone measurements: `tools/phone-bench.ps1` (BAR's "Benchmark BAR" scenario; `-Profile gadgets` for BAR's gadget
profiler), a scratch widget that gave the benchmark's armies in a skirmish and saved with `/save <name> -y` (timed from
the engine's own log lines), a temporary `files/bar/dev-env.sh` that started the engine from the save (removed after),
`tools/demo-rate.py` on replays. Catch-up numbers: the app's logs of Kailil's joins (docs/HISTORY.md).
