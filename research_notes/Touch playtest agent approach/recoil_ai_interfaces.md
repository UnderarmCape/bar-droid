# Recoil engine and BAR interfaces for AIs, Lua widgets and game control (late 2026)

Basis: engine facts were read in source, in the local checkout `C:\Tools\BARANDROID\hailmary-work\recoil-0903` (the engine's 2026.09.03 release branch with BAR Droid patches). The links go to RecoilEngine `master`, and line numbers there may have moved a little. BAR facts were read at Beyond-All-Reason commit `50bd47b34fcbcdd73e2403441cdf62e90a070e26` (master, fetched 2026-11-21); the BAR line numbers quoted are from that commit. The newest RecoilEngine release on GitHub is 2026.11.04, published 2026-11-19 ([releases](https://github.com/beyond-all-reason/RecoilEngine/releases)). Labels: "source" means I read it in code; "inference" means it is my reading of the code and was not tested in game.

## 1. Skirmish AI interface: languages, BARb loading and profiles, AI on the player's team, seeing and blocking AI commands

### Takeaway
In late 2026 the engine supports native (C ABI / C++ wrapper) skirmish AIs only. The Java bindings were removed in July 2026, and the engine has no Python AI interface. BARb (the CircuitAI "barbarian" branch) loads its difficulty profile from the game archive: `LuaRules/Configs/BARb/stable/{config,script}/<profile>/`, with the profiles easy, medium, hard and hard_aggressive. A skirmish AI can be attached to your own team (`/aicontrol`, allowed for the team leader or in singleplayer). Its orders do pass through synced `AllowCommand`. But when the host player hosts the AI on that player's own team, `AllowCommand` receives the same arguments for the AI's orders as for the player's own orders (playerID = host, fromSynced = true, fromLua = false). A gadget therefore cannot tell them apart by arguments alone.

### Cited Findings
- **Interfaces:** `AI/Interfaces` on RecoilEngine master holds only `C` (plus CMakeLists). The C++ wrappers live under `AI/Wrappers` (Cpp, CUtils, LegacyCpp) — [AI/Interfaces (master)](https://github.com/beyond-all-reason/RecoilEngine/tree/master/AI/Interfaces); local checkout listing.
- **Java removed:** PR #3059 "Remove Java AI bindings" was merged 2026-07-10. The PR text says "No one seems to be using them" and that hosting bindings other than C++ is not the engine's job — [PR #3059](https://github.com/beyond-all-reason/RecoilEngine/pull/3059).
- **No Python:** the engine has no Python AI interface. The only Python in `.gitmodules` is `tools/unitsync/python` (pyunitsync, a lobby/unitsync binding, not an AI interface) — [.gitmodules](https://github.com/beyond-all-reason/RecoilEngine/blob/master/.gitmodules).
- **Bundled skirmish AIs:** `AI/Skirmish/BARb` (rlcevg/CircuitAI, branch `barbarian`), `AI/Skirmish/CircuitAI` (branch `zk`), `CppTestAI`, `NullAI`, and on master a new `AI/Skirmish/CampaignAI` submodule (beyond-all-reason/campaign-ai). CampaignAI was added 2026-11-09 (PR #3717) and updated 2026-11-12 (#3738) — [.gitmodules](https://github.com/beyond-all-reason/RecoilEngine/blob/master/.gitmodules); [CampaignAI PR #3717](https://github.com/beyond-all-reason/RecoilEngine/pull/3717).
- **CampaignAI:** its README calls it "Champion", "Based on C++ Circuit AI with AngelScript usage for game concepts". No options or mission hooks are documented on the front page — [campaign-ai](https://github.com/beyond-all-reason/campaign-ai).
- **BARb config path:** BARb reads its game-side config from `LuaRules/Configs/<shortName>/<version>/<subdir>/` (`GetAIDataGameDir`). It does this when the AI option `game_config` is true (the default), and otherwise falls back to its own bundled `config/` — [FileSystem.h](https://github.com/rlcevg/CircuitAI/blob/barbarian/src/circuit/util/FileSystem.h); [SetupManager.cpp LoadConfig](https://github.com/rlcevg/CircuitAI/blob/barbarian/src/circuit/setup/SetupManager.cpp).
- **AngelScript loading:** the AngelScript `script/<profile>/` files load the same way (game-side first, then bundled) — [ScriptManager.cpp](https://github.com/rlcevg/CircuitAI/blob/barbarian/src/circuit/script/ScriptManager.cpp).
- **Bundled AIOptions.lua** has these options:
  - `cheating` ("LOS vision", global sight, default false)
  - `comm_merge`
  - `ally_base` (avoid building in allied bases, default true)
  - `disabledunits`
  - `game_config` (default true)
  - `profile` (list, `def = 'hard'`). The only uncommented item is `dev`; hard, medium and easy are commented out.

  Source: [AIOptions.lua](https://github.com/rlcevg/CircuitAI/blob/barbarian/data/AIOptions.lua) (local copy under `AI/Skirmish/BARb/data`).
- **BAR's profiles:** BAR ships `luarules/configs/BARb/stable/config/{easy,medium,hard,hard_aggressive}/*.json` and `script/{easy,medium,hard,hard_aggressive}/{init.as,main.as,manager/*,misc/*}`. The JSON parts are behaviour, block_map, build_chain, commander, economy, factory and response, each with `_leg` (Legion) variants plus `behaviour_extra_units` and `behaviour_scav_units` — [BAR luarules/configs/BARb/stable](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable).
- **What Hard changes.** I compared the files across profiles by hash:
  - `script/main.as`, `manager/builder.as`, `manager/economy.as` and `manager/factory.as` are identical in easy and medium. They differ in hard, and hard and hard_aggressive are identical.
  - `manager/military.as` is identical in all four profiles.
  - `commander.json` is the same in easy and medium, and different (and shared) in hard and hard_aggressive.
  - `block_map.json` exists only in hard and hard_aggressive.
  - `economy.json` is the same in hard and hard_aggressive.

  Source: [BAR BARb stable](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable).
- **Medium vs Hard in the scripts:**
  - Hard's `main.as` tags heavy energy buildings (cost ≥ 200 metal, immobile) as BASE builds, and marks the T2/T3 factory defs.
  - Hard's `economy.as` sets `isMetalFull` at 99 % of storage (medium: 80 %) and uses a 3-minute early "assist required" window (medium: 2 minutes).

  Source: [hard/manager/economy.as](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable/script/hard/manager/economy.as); [medium/manager/economy.as](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable/script/medium/manager/economy.as).
- **Hard vs hard_aggressive:**
  - `behaviour.json`: `enemy_count_per_team_to_end_scaling` is 350 in hard and 450 in aggressive; `end_scale_value` is 0.5 in hard and 0.4 in aggressive.
  - `factory.json`: different unit-mix `importance` weights and fewer caretakers (nanos) per factory in aggressive (for example hard 8/12 against aggressive 3–6).

  Source: [hard/behaviour.json](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable/config/hard/behaviour.json); [hard_aggressive/factory.json](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable/config/hard_aggressive/factory.json).
- **Easy:** the designers' readme describes it as "command delay => lower unit production and expansion rate", with fewer mobile builders, a reduced commander radius, few nanos, no early raiding, heavy reliance on solars, more artillery, and response only to air threats — [easy_ai_readme.txt](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable/config/easy/easy_ai_readme.txt).
- **The `init.as` files** for all four profiles are the same apart from the log line. Each loads the same part list and adds the Legion, scav-units and extra-units parts depending on mod options — [hard/init.as](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/configs/BARb/stable/script/hard/init.as).
- **"New Beginning" setup:**
  - It is `scenario021.lua` (scenarioid `Begin04`, map "Death Valley v1", Armada only, victory = kill all enemy factories).
  - Its startscript adds `[ai0]` with `ShortName = BARb; Version = stable; Team = 1; Host = 0` and passes no `[Options]`, so no profile is set explicitly.
  - Its difficulty selector changes only the resource `Handicap`: Normal 0/0, Hard enemy +25, Brutal enemy +50, Beginner player +50.

  Source: [scenario021.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/singleplayer/scenarios/scenario021.lua).
- **AI on your own team (`/aicontrol`):**
  - Usage: `/aicontrol teamToControl aiShortName [aiVersion] [name]`.
  - It is allowed `if (weAreLeader || singlePlayer || (weAreAllied && (cheating || noLeader)))`.
  - It refuses a team that already has a skirmish AI ("TODO remove this, if support for multiple Skirmish AIs per team is in place").
  - It refuses Lua AIs mid-game ("it is currently not supported to initialize Lua AIs mid-game").

  Source: [UnsyncedGameCommands.cpp AIControlActionExecutor](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/UnsyncedGameCommands.cpp).
- **How a skirmish AI order travels:**
  - `CAICallback::GiveOrder` refuses units not on the AI's team (`unit->team != team` → -5) and sends `NETMSG_AICOMMAND` with the hosting player's number — [AICallback.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/ExternalAI/AICallback.cpp).
  - The client handles it in `AINetOrder` ("handles NETMSG_AICOMMAND{S}'s sent by AICallback / LuaUnsyncedCtrl (!)"), which calls `unit->commandAI->GiveCommand(c, playerID, true, false)` — [SelectedUnitsHandler.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/SelectedUnitsHandler.cpp); [NetCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/NetCommands.cpp).
- **Where `AllowCommand` and `UnitCommand` sit:** `CCommandAI::GiveCommand` calls `eventHandler.AllowCommand(owner, c, playerNum, fromSynced, fromLua)`. If that returns false, the command is dropped and neither `UnitCommand` nor the command queue sees it. Otherwise it calls `eventHandler.UnitCommand(...)` and then `GiveCommandReal` — [CommandAI.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Sim/Units/CommandAI/CommandAI.cpp).
- **Human UI orders** (`NETMSG_COMMAND` → `NetOrder` → `selectedUnitsAI.GiveCommandNet`) also call `GiveCommand(c, playerNum, true, false)` on most paths; some formation and front-move paths pass `false` for fromSynced. `NetOrder` also calls `eoh->PlayerCommandGiven`, which notifies AIs of player commands — [SelectedUnitsAI.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/SelectedUnitsAI.cpp); [SelectedUnitsHandler.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/SelectedUnitsHandler.cpp).
- **Synced Lua orders** (`Spring.GiveOrderToUnit` in a gadget) call `GiveCommand(cmd, -1, true, true)`, so playerID = -1 and fromLua = true — [LuaSyncedCtrl.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Lua/LuaSyncedCtrl.cpp).
- **Server-side drop switch:** when `NoHelperAIs` is set (startscript `GAME\ModOptions\NoHelperAIs`, or the server action `nohelp`), the server drops every `NETMSG_AICOMMAND`/`NETMSG_AICOMMANDS` instead of forwarding it. `NETMSG_COMMAND` (human UI) is still forwarded. BAR's scenario startscript sets `nohelperais = 0` — [GameServer.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp); [GameSetup.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/GameSetup.cpp); [scenario021.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/singleplayer/scenarios/scenario021.lua).

### Inferences
- **(b) works mechanically.** `/aicontrol 0 BARb stable` from the player's own client in singleplayer passes the permission check, and BARb then commands every unit on team 0. Its orders and the agent's touch orders would fight over the same units unless one side is muted.
- **(c) works, but the gadget needs a way to tell the AI apart.** A synced gadget registering `AllowCommand` does see BARb's orders and can record them and return false.
  - The catch: the AI is hosted by player 0 on team 0, so its orders arrive with the same signature as the human's (playerID 0, fromSynced true, fromLua false).
  - If BAR Droid's touch controls issue orders from LuaUI widgets (`Spring.GiveOrderToUnit` in unsynced code), those also travel as `NETMSG_AICOMMAND(S)` and look identical too.
  - So blocking "AI orders only" needs something extra. Options: a mode switch (block everything while the agent is not touching), timing or heuristics, or a patch. Because BAR Droid builds the engine and BARb from source, a patch is possible: for example, tag BARb's orders (a spare option bit), or have BARb log its intended orders and then set NoHelperAIs so the server drops them.
- **A blocked AI order leaves BARb with stale belief.** BARb is not told. Its task managers will likely see idle units and re-issue orders, so expect repeated, slightly different suggestions rather than one clean order stream.
- **A Lua planner is easier to separate.** Lua (gadget) AI orders are distinguishable: playerID -1 and fromLua true. A gadget-based planner can be filtered cleanly, or can simply publish suggestions without ever issuing orders.
- **New Beginning's "Hard" is not BARb Hard.** The scenario's "Hard" is a +25 % resource handicap for the enemy, not a BARb profile. Which BARb profile runs there depends on the default the engine applies for `profile` (the bundled AIOptions default is 'hard') — not verified in game.

### Gaps
- Not verified: whether a startscript can declare an `[AI]` section with `Team = 0` while `[player0]` is also on team 0 (static helper AI). `/aicontrol` is the verified path.
- Not confirmed: whether the engine fills in AIOptions defaults (profile = hard) when the startscript passes no options. I did not finish tracing CircuitAI's handling of an empty profile.
- Not checked: how the BAR lobby (Chobby) shows easy/medium/hard/hard_aggressive to players, given that the bundled AIOptions list only `dev`.
- Not checked: whether `CAICallback`'s `allowOrders` flag can be false for an AI attached mid-game.

## 2. Lua AIs in BAR: SimpleAI, STAI, ScavengersAI and others, and use as a planner for a human team

### Takeaway
BAR's `luaai.lua` now lists five Lua AIs: SimpleAI, SimpleDefenderAI, SimpleConstructorAI, ScavengersAI and RaptorsAI. STAI no longer exists in BAR's master tree. Lua AIs are synced LuaRules gadgets that act for teams whose `Spring.GetTeamLuaAI(teamID)` names them. A gadget loads only from the game archive unless Lua dev mode is on, so a planner gadget means modifying the game or running in dev mode. A gadget planner's orders are cleanly distinguishable in `AllowCommand`.

### Cited Findings
- **The list:** `luaai.lua` returns SimpleAI, SimpleDefenderAI and SimpleConstructorAI (desc "EasyAI"), ScavengersAI ("Infinite Games") and RaptorsAI ("Raptor Defence") — [luaai.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaai.lua).
- **No STAI:** no path containing "STAI"/"stai" exists in the BAR master tree at commit 50bd47b (checked by searching the full 19,315-entry git tree). The top-level AI gadgets are `ai_namer.lua`, `ai_ruins.lua`, `ai_ruin_blueprint_tester.lua`, `ai_simpleai.lua` and `ai_zombies.lua` — [BAR luarules/gadgets](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/gadgets).
- **How SimpleAI works:** `ai_simpleai.lua` starts with `local enabled = false`, scans teams with `Spring.GetTeamLuaAI(teamID)`, and enables itself only when a team runs a Simple* AI. It acts through synced `Spring.GiveOrderToUnit` (build orders with `{"shift"}`, D-gun, reclaim, move and so on) — [ai_simpleai.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/gadgets/ai_simpleai.lua). Checked in a local copy of BAR's game Lua, rev 31836.
- **Gadget load mode:** `luarules/gadgets.lua` sets `local VFSMODE = VFS.ZIP_ONLY` and switches to `VFS.RAW_FIRST` only `if Spring.IsDevLuaEnabled()` — [gadgets.lua L20-23](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/gadgets.lua#L20-L23).
- **Turning dev mode on:**
  - The synced action `/devlua` ("Enables/Disables Lua dev-mode (can cause desyncs if enabled)") is registered with the cheat-required flag set — [SyncedGameCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/SyncedGameCommands.cpp).
  - The startscript key `GAME\ModOptions\LuaDevMode` sets it from the start — [GameSetup.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/GameSetup.cpp).
- **Lua AIs only at game start:** a Lua AI cannot be attached mid-game with `/aicontrol` — [UnsyncedGameCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/UnsyncedGameCommands.cpp).
- **Gadget orders are tagged:** synced gadget orders arrive in `AllowCommand` with playerID -1 and fromLua true — [LuaSyncedCtrl.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Lua/LuaSyncedCtrl.cpp).

### Inferences
- **Using SimpleAI-style logic as a planner for team 0** means editing or forking the gadget: drop the `GetTeamLuaAI` gate, or key it to a mod option. That is a game modification: a BAR Droid-side gadget, or a raw file under `LuaRules/Gadgets/` loaded with dev mode on.
- **A planner gadget need not issue orders at all.** It can publish intended orders to unsynced code, and a widget can then export them as text. That avoids the interception problem in section 1.
- **Quality:** SimpleAI-class logic is far weaker than BARb Hard, so as a planner it would not beat BARb Hard. BARb as the shadow planner (section 1) is the stronger option, but harder to separate. This is a judgement, not a measured result.
- **Dev mode can desync** ("can cause desyncs"), which is fine offline or in singleplayer but not online.

### Gaps
- Not verified: how ScavengersAI and RaptorsAI are implemented (which gadgets) — out of scope for this pass.
- Not verified: whether BAR's gadget handler also picks up new gadget files from raw `LuaRules/Gadgets/` under RAW_FIRST (likely, since the same VFSMODE is used for includes and dir listings, but not traced).

## 3. LuaUI user widgets in BAR: sandbox, callins during pause, the APIs needed, enabling, and /luaui reload

### Takeaway
The plain engine gives unsynced Lua `io` and `os`, minus popen, exit, execute, tmpname and getenv. BAR then sandboxes user widgets (files not from the game archive):
- File writes are allowed only in `LuaUI/Config/` and `LuaUI/Widgets/`; reads only under `LuaUI/`.
- `GiveOrder*` is allowed unless the mod option `allowunitcontrolwidgets` is false (default true; always allowed in replays and as a spectator).
- Widget-control and keybind commands are refused, and so are Spring.Start, Restart and Reload.
- Pause and speed commands are not blocked.

`widget:Update` runs while the game is paused; `GameFrame` does not. All the listed APIs exist in the engine. `WG.resource_spot_finder.metalSpotsList` exists in BAR.

### Cited Findings
- **Engine Lua libraries:** `OpenUnsynced` opens io, os and debug, routes fopen/system/remove/rename through `LuaIO`, and removes `io.popen` plus `os.exit`, `os.execute`, `os.tmpname` and `os.getenv` — [LuaLibs.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Lua/LuaLibs.cpp).
- **BAR user-widget file paths:**
  - `userWritableFolders = { "luaui/config/", "luaui/widgets/" }` and `userReadableFolder = "luaui/"` — [barwidgets.lua L634-635](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua#L634-L635).
  - Absolute paths, `..`, `:` and `~` are refused, and the widget config, `uikeys.txt` and `keybind_profiles.json` are read-only. `io.open`, `io.lines`, `io.input`, `io.output`, `os.remove` and `os.rename` are wrapped with these checks — [barwidgets.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua).
- **Unit-control gate:**
  - `local allowunitcontrolwidgets = Spring.GetModOptions().allowunitcontrolwidgets` (L114). When it is false, every `Spring.GiveOrder*` in a user widget's sandbox raises "User 'unit control' widgets disallowed on this game" (L1051-1056).
  - In replays and as a spectator, both user widgets and unit-control widgets are forced on.

  Source: [barwidgets.lua L1051-1056](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua#L1051-L1056).
- **Mod option defaults:** `allowuserwidgets` ("Allow Custom Widgets", bool, def true, hidden) and `allowunitcontrolwidgets` ("Allow Custom 'Unit Control' Widgets", bool, def true) — [modoptions.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/modoptions.lua).
- **Anonymous mode:** a `teamcolors_anonymous_mode` other than "disabled" forces `allowuserwidgets = false` — [barwidgets.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua).
- **Sandboxed `SendCommands`:**
  - Always dropped: commands containing enablewidget, disablewidget, togglewidget, execute, keyload, keyreload, keysave, keybindingfile, factoryreset, userwidgets, runtests, runscenario or option.
  - Dropped in multiplayer as a player only: save, savegame, luasave and dumpstate.
  - Everything else (for example `pause`, `setspeed`, `luaui reload`) passes.

  Source: [barwidgets.lua L605-632, L995-1008](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua#L605-L632).
- **Engine restart refused:** `Spring.Start`, `Spring.Restart` and `Spring.Reload` log "User widgets cannot start, restart or reload the engine" — [barwidgets.lua L1042-1048](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua#L1042-L1048).
- **How a widget gets enabled:** a widget with no saved order in the handler config gets order 12345 (enabled) `if widget.whInfo.enabled and (knownInfo.fromZip or self.allowUserWidgets)`. A saved order ≤ 0 means disabled. User widget files are loaded from `LuaUI/Widgets/` with raw VFS only when `allowUserWidgets` and the mod option both allow it ("LuaUI: Allowing User Widgets") — [barwidgets.lua L1569-1577](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua#L1569-L1577).
- **Pause API for widgets:** BAR's widget handler has `widgetHandler:Pause(source)` and `Unpause(source)`, which send `pause 1` / `pause 0` and cannot pause before frame 1. The synced `GG.GamePause` API (gadget "Game Pause", dated 2026-10) sets the rules params `gamePaused`, `gamePauseGeneration` and `gamePausePublished` — [barwidgets.lua L3290-3330](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua#L3290-L3330); [api_game_pause.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/gadgets/api_game_pause.lua).
- **Callins during pause:** `CGame::Update` calls `eventHandler.Update()` in its unsynced section on every update. `eventHandler.GameFrame(gs->frameNum)` is called only from the sim-frame path — [Game.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/Game.cpp).
- **APIs confirmed registered in the engine:**
  - LuaUnsyncedRead: `WorldToScreenCoords`, `TraceScreenRay`, `GetActiveCommand`, `GetVisibleUnits`, `GetSelectedUnits`, `GetGameSpeed`, `GetMouseState`, `IsGUIHidden`.
  - LuaSyncedRead (also available to unsynced): `GetUnitLosState`, `GetTeamResources`, `GetUnitCommands`, `GetFactoryCommands`, `GetCommandQueue`, `IsPosInLos`, `IsPosInRadar`, `GetPositionLosState`, `IsUnitInLos`, `GetTeamUnits`, `GetUnitsInRectangle`, `GetUnitPosition`, `GetGameFrame`, `IsDevLuaEnabled`.
  - LuaUnsyncedCtrl: `GiveOrderToUnit`, `SetActiveCommand`, `SendCommands`.

  Source: [LuaUnsyncedRead.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Lua/LuaUnsyncedRead.cpp); [LuaSyncedRead.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Lua/LuaSyncedRead.cpp); [LuaUnsyncedCtrl.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Lua/LuaUnsyncedCtrl.cpp).
- **Metal spots:** `common/upgets/api_resource_spot_finder.lua`, loaded by `luaui/Widgets/api_resource_spot_finder.lua` (a one-line `require`), sets `resource_spot_finder.metalSpotsList`, `.geoSpotsList` and `.isMetalMap` on its global scope (WG for widgets). The list "is refilled IN PLACE" — [api_resource_spot_finder.lua L395-424](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/common/upgets/api_resource_spot_finder.lua#L395-L424).
- **`/luaui reload` in the engine:** the `LuaUI` action handles `reload`/`enable`/`disable` with no cheat or multiplayer check — [UnsyncedGameCommands.cpp LuaUIActionExecutor](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/UnsyncedGameCommands.cpp).

### Inferences
- **(a) is fully supported in singleplayer with default mod options.** A dev-only user widget in `LuaUI/Widgets/` can:
  - read state with the APIs above;
  - write a text state file under `LuaUI/Config/` (or `LuaUI/Widgets/`) for adb to pull;
  - keep exporting while paused through `widget:Update` or `DrawScreen`.

  It must not give orders itself, so the touch-only rule stays intact. Even the `allowunitcontrolwidgets = false` restriction would not affect a read-only exporter.
- **LOS still applies to the exporter.** As a player (not spectator), `GetVisibleUnits` and `GetUnitLosState` report only what the player's ally team can see, so the export respects fog of war. Not tested.
- **Screen coordinates move with the camera.** `WorldToScreenCoords` depends on the current camera, so the exporter should write coordinates fresh in the same frame the agent's screenshot or touch decision uses.
- **Watch for scaling.** BAR Droid's touch layer may scale LuaUI pixels differently from the Android touch pixels (an app-specific concern).
- **`/luaui reload` should work in BAR singleplayer.** The engine has no gate and BAR's sandbox list does not include it. Not tested on BAR Droid.

### Gaps
- No primary source found for BAR's "no user unit-control widgets in ranked/online" policy beyond the `allowunitcontrolwidgets` mod option. The values lobby hosts set for ranked games were not verified.
- `GetInfo` handling for hidden or `handler = true` widgets was not traced in detail.

## 4. Game speed and pause in singleplayer: /setspeed, /setminspeed, /setmaxspeed, the +/- keys, minimum speed, orders while paused, scenario pausing

### Takeaway
The default speed range is 0.1x–20x, from the startscript mod options `MinSpeed`/`MaxSpeed`; BAR's `modoptions.lua` does not override them. `/setspeed X` sets any positive speed within that range, and `SpeedUp`/`SlowDown` step by 0.1 below 2x. `/setminspeed` and `/setmaxspeed` are server commands that only the local host can run, which the singleplayer player is. Orders given while paused are accepted in singleplayer: BAR's "Paused is paused" blocker is disabled there, and the engine processes command packets during pause.

### Cited Findings
- **Default range:** `GameSetup` reads `maxSpeed` default "20." from `GAME\ModOptions\MaxSpeed` and `minSpeed` default "0.1" from `GAME\ModOptions\MinSpeed`. The server copies these into `maxUserSpeed`/`minUserSpeed` — [GameSetup.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/GameSetup.cpp); [GameServer.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp).
- **Clamping:** `UserSpeedChange` clamps every request: `std::clamp(newSpeed, minUserSpeed, maxUserSpeed)` — [GameServer.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp).
- **`/setmaxspeed` and `/setminspeed`:**
  - `setmaxspeed` takes `max(arg, minUserSpeed)` and applies it only if it is > 0.2.
  - `setminspeed` sets `min(arg, maxUserSpeed)`, with no lower bound in code.
  - Both are server commands. A client's `NETMSG_CCOMMAND` server command runs only `if (serverCommand && players[a].isLocal)`.

  Source: [GameServer.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp).
- **`/setspeed`:** "SetSpeed" — "Set the simulation speed to any positive value, bounded by the minimum and maximum game speed settings". It refuses values ≤ 0 — [UnsyncedGameCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/UnsyncedGameCommands.cpp).
- **`SpeedUp` / `SlowDown` steps:** +0.1 below 2x, +0.2 from 2x to 5x, +0.5 from 5x to 10x and +1 above, rounded to whole numbers near integers. `SlowDown` mirrors this with the steps {0.1, 0.2, 0.5, 1.0} over the ranges {≤2, ≤5, ≤10, above} — [UnsyncedGameCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/UnsyncedGameCommands.cpp).
- **No BAR override:** BAR's `modoptions.lua` has no MinSpeed or MaxSpeed entries (searched) — [modoptions.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/modoptions.lua).
- **Pause rules:**
  - `/pause` cannot be used before the game is playing.
  - On the server, the host can pause even when the game is not pausable ("allow host to pause even if nopause is set"), and spectators cannot pause.
  - Clients set `gs->paused` and fire the `GamePaused` callin.

  Source: [UnsyncedGameCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Game/UnsyncedGameCommands.cpp); [GameServer.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp); [NetCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/NetCommands.cpp).
- **Orders during pause in the engine:**
  - The server forwards `NETMSG_COMMAND` without a pause check.
  - The client's `ClientReadNet` loop reads every packet in the queue. Pause stops only `NETMSG_NEWFRAME`, so command packets are applied to command queues during pause.

  Source: [GameServer.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp); [NetCommands.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/NetCommands.cpp).
- **BAR's blocker:** the gadget "Paused is paused" ("Prevent commands being queued while paused") returns false from `AllowCommand` while paused, unless cheats are on. But it exits at load `if Spring.GetModOptions().allowpausegameplay or BAR.Utilities.Gametype.IsSinglePlayer()` — [cmd_paused_is_paused.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/gadgets/cmd_paused_is_paused.lua).
- **Mission pausing:**
  - The newer Mission API has `pause`/`unpause` and pause/unpause-countdown actions (`luarules/mission_api/actions/game/pause.lua` and others), built on `GG.GamePause` — [mission_api/actions/game](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/mission_api/actions/game); [api_game_pause.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/gadgets/api_game_pause.lua).
  - The "Mission Info" widget (`gui_mission_info.lua`, active when `scenariooptions` is set) contains no `Pause(`, `Unpause(` or `"pause` call (searched) — [gui_mission_info.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/Widgets/gui_mission_info.lua).
  - New Beginning is an old-style scenario (`Begin04`). The "Scenario Script" gadget loads `singleplayer/scenarios/scenarioscripts/<id>.lua` only if that file exists, and only `Begin06.lua` exists — [unit_scenario_script.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luarules/gadgets/unit_scenario_script.lua).

### Inferences
- **(d) is available out of the box.** `/setspeed 0.1` (or SlowDown from 1x, nine presses) reaches the 0.1x floor in singleplayer.
- **Below 0.1x might work.** `/setminspeed 0.02` followed by `/setspeed 0.02` should go lower, since the code has no lower bound, but this was not tested and may expose timing edge cases.
- **Pausing is the better mode for an agent.** The agent can pause, issue touch orders while paused (they enter the queues immediately in singleplayer), and unpause.
- **This pause behaviour is singleplayer-only.** Online, BAR's gadget refuses orders while paused unless `allowpausegameplay` is set.
- **Where the mission-window pause comes from is unclear.** The upstream BAR Lua checked here has no "mission window pauses" behaviour for New Beginning. If BAR Droid sees one, it likely comes from BAR Droid's own UI or the lobby; check the app code before relying on it.

### Gaps
- Not verified: BAR's default key binds for speed (`+`/`-` mapped to speedup/slowdown) in its keybind files.
- Not measured: how the server's automatic internal slowdown (`InternalSpeedChange`, `speedControl`) interacts with a very low user speed on the phone.
- Not found: where the scenario "Mission" window pause on BAR Droid comes from.

## 5. Headless and replay-based options for testing an agent

### Takeaway
Recoil builds a headless engine (`engine-headless`) that "only does the simulation". Widgets are its main input, and the Recoil docs recommend it for AI-vs-AI runs and replay analysis. When BAR plays a replay, or when you spectate, it turns on user and unit-control widgets. These suit offline checks of a state-export widget or a shadow-AI recorder, not touch UX testing.

### Cited Findings
- **Build targets:** `engine-legacy` (interactive), `engine-headless` ("headless engine (no graphics)") and `engine-dedicated` — [RecoilEngine AGENTS.md](https://github.com/beyond-all-reason/RecoilEngine/blob/master/AGENTS.md).
- **What headless does:** it "only does the simulation" and "does not do any rendering". Widgets still work and are "the main way to provide input", while rendering callins do nothing. Listed uses: analysing replays with a widget, AI-vs-AI games, and verifying replays. For unattended rendering, the docs suggest the normal binary with `--background-window` (`Spring.IsBackgroundWindow()`) — [Recoil docs: Headless and Dedicated](https://recoilengine.org/docs/guides/getting-started/headless-and-dedicated/).
- **Dedicated server:** it "only collects and relays network traffic without running the simulation", and replays are still produced — [Recoil docs: Headless and Dedicated](https://recoilengine.org/docs/guides/getting-started/headless-and-dedicated/).
- **Replays and spectating in BAR:** `if spIsReplay() or spGetSpectatingState() then allowuserwidgets = true; allowunitcontrolwidgets = true` — [barwidgets.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/50bd47b34fcbcdd73e2403441cdf62e90a070e26/luaui/barwidgets.lua).
- **Pausing a demo:** the server lets demo spectators "pause" only locally ("pause is a synced message, thus demo spectators may not pause for real") — [GameServer.cpp](https://github.com/beyond-all-reason/RecoilEngine/blob/master/rts/Net/GameServer.cpp).

### Inferences
- **Headless use:** a headless run of BARb against BARb (or against a scripted opponent) can test a shadow-AI recording gadget or a state-export widget's text format quickly, without the phone.
- **Phone-only rule:** BAR Droid's rule is to test on the phone only, so headless runs would have to run on the dev phone, not on the laptop.
- **Replays:** replays of the agent's own games, played back with a spectator widget, can produce exact after-game statistics (LOS-free) for scoring the agent. They cannot test touch controls.

### Gaps
- Not verified: the exact headless binary name and command line used in BAR Droid's Linux container, or whether its build includes `engine-headless`.
- Not researched: demo-file (`.sdfz`) recording flags and replay-speed controls in this pass.
