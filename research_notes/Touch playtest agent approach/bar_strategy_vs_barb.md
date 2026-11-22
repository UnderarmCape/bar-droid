# Beating BARb (1v1 Easy/Medium/Hard) and completing the scenario "New Beginning": strategy for a slow, low-APM agent

Research date: 2026-11-21. Primary sources are the scenario file itself (extracted from the game pool on this PC), the BAR game repo's BARb configs and unit defs on GitHub (master branch, read 2026-11-21), and beyondallreason.info unit pages. Community material (Reddit, YouTube, Discord) was mostly unreachable. Only search snippets and video titles/channels could be read, so very little human-written strategy for this scenario is verifiable. Note: WebFetch returns a model-written summary of each page, not the raw text, so treat the exact numbers as "as reported from the file".

## Key question 1: "New Beginning" scenario: description, layout, approaches, failure points

### Takeaway
No written walkthrough could be read. Only three YouTube playthroughs were found, and their contents were not accessible. The scenario file itself is the best source. The enemy has no commander and no starting constructors. Its 5 factories sit in the north/north-east behind a ring of T2 defenses. A fully assisted Advanced Aircraft Plant (4 Construction Turrets) whose hard-profile mix is 40% Wasp gunships explains the early commander deaths. Plasma shields (Overseer) protect the defensive ring, not the factories. The factories themselves are covered mostly by T1 Thistle AA plus one SAM. The difficulty selector only changes resource handicaps, and "Beginner" gives the player +50% resources.

### Cited Findings
- Scenario metadata: index 21, scenarioid "Begin04", version "1", title "New Beginning", author wilkubyk, map "Death Valley v1.0.1", par time 2400 s (40 min), par resources 4,000,000, perceived difficulty 8.1 at Normal, default difficulty Normal. Summary text: a garbled "Incoming Transmission" about Cortex. Briefing tips, verbatim: "Build a Shield as soon as possible", "Try to Capture enemy constructor to gain access to foe Tech", "Don't forget early AA". — [scenario021.lua (local copy extracted from the BAR game pool), C:\Tools\BARANDROID\toolchain\tmp\scen\scenario021.lua](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Difficulty levels change resource handicaps only. The comment reads "Currently difficulty modifier only affects the resource bonuses". Beginner: player +50, enemy 0. Novice: player +25. Normal: 0/0. Hard: enemy +25. Brutal: enemy +50. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Win/lose: "Kill all enemy factories" and "Loss of all your builders and factories". The start script sets `deathmode = builders`. Only Armada is allowed (`disablefactionpicker = true`). — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- The enemy AI entry in the start script is `Name = BARbstable(1); ShortName = BARb; Version = stable;`. There is no `[Options]` block, so no difficulty `profile` is set and BARb uses its default profile. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- The engine-side BARb AIOptions.lua has the `profile` option with `def = 'hard'`. In this engine copy only the "dev" item is active, and the hard/medium/easy items are commented out. The `game_config` option ("Load game config") defaults to true. — [AIOptions.lua (local engine copy, recoil-0903)](file:///C:/Tools/BARANDROID/hailmary-work/recoil-0903/AI/Skirmish/BARb/data/AIOptions.lua)
- Our starting units (team 0): armcom at (552, 6767), Cloakable Fusion Reactor `armckfus` at (584, 7008), Cloakable Jammer `armjamt` (Sneaky Pete) at (656, 6624), and 3 `armmoho` at (464, 6512), (336, 6913), (861, 6867). That puts us in the south-west corner. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Enemy factories at start: `corlab` Bot Lab at (4656, 2112) and (3680, 1520). `corvp` Vehicle Plant at (3192, 824). `coraap` Advanced Aircraft Plant at (5392, 576) with 4 `cornanotc` Construction Turrets beside it and a SAM (`cormadsam`) at (5656, 408). Naval Hovercraft Platform `corfhp` at (4736, 1208), in water (y = -4), with 2 `cornanotcplat` and floating dragon's teeth. All of them are in the northern/north-eastern part of the map. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- The enemy loadout has no Cortex commander and no mobile constructors. As the file notes, "If you have ANY units in loadout, then there will be no initial units spawned for anyone." — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Enemy unit caps, which define what the AI can add: corlab 2, coralab 1, corvp 2, coravp 1, corap 2, coraap 1, corhp 1, corfhp 1, corck 3, corack 3, corcv 3, coracv 3, corca 4, corch 4, cornecro 10, corfast 10, cormlv 5. Disabled (0): coraca, corsilo, corbuzz, corgant, corsy, corasy, cormando, cordecom, cormuskrat, corplat, corcsa. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Our unit caps: armsilo 0 (no nukes), armvulc 0, armbrtha 0 (no Basilica long-range plasma cannon), armmercury 0 (no Mercury long-range AA), armasp 0 (no air repair pad), armshltx 0 (no T3 gantry), armdl 0, armamsub 0. armafus is capped at 2 and armmmkr (Advanced Energy Converter) at 6. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Enemy static defenses, counted from the loadout: 18 `cordoom` (Bulwark), 20 `corvipe` (Scorpion), 16 `corllt` (Guard), 4 `corflak` (Birdshot), 6 `corgate` (Overseer) and about 10 `corshroud` (Shroud jammers). Also: 2 `corhlt` (Warden), 4 `corhllt` (Twin Guard), 7 `corrl` (Thistle), 1 `cormadsam` (SAM), 2 `corfrt` (floating AA), 2 `corfmd` (Prevailer anti-nuke), several `corrad` radars, and 3 `coratl` torpedo launchers. This matches the user-supplied counts. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Where the defenses are:
  - The Birdshot flak guns are on the middle defensive ring: (1504, 3824), (3392, 4784), (3648, 5728) and (4080, 3856).
  - The Overseers are on the same ring: (1552, 3632), (3536, 4880), (3840, 5744), (4240, 6096), (4176, 7120) and (4368, 4384).
  - The AA near the factories is Thistles at (3976, 2312), (3432, 2104), (4488, 2712) and (2152, 840), plus the SAM by the aircraft plant.
  - Bulwark/Scorpion lines are at, for example, (1376–1648, ~3900), (3248–3536, 4752–5040), (4032–4144, 6096–6480), (4112, 6976–7104), (3616–4032, 3776–4240), (4368–4544, 3296–3568) and (2672–2896, 2384–2448). Seven Scorpions line (3496–4200, 2408–2840) in front of the bot labs, and five more are on the west approach, (1992–2456, 184–1320).

  — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Enemy economy at start:
  - Windmill farms: about 36 `corwin` at x 5880–6072, z 1432–1944, and about 48 at x 3688–4392, z 72–264.
  - Energy converters: 8-unit `cormakr` rings around `coradvsol` at (896, 2112) and (5328, 4944), plus 4 at each bot lab.
  - Underwater: 3 `coruwfus` fusions with advanced storages at x 40–712, z ~3500–3800, on the west side.
  - Mexes: about 28 `cormex` spread over the whole map, including near our side: (5984, 6144), (5552, 6368), (5584, 5824) in the south-east, (4704, 6784) and (4768, 7072).

  — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- Three YouTube playthroughs exist:
  - "Scenario 20 - New Beginning - Beyond All Reason Guide", channel Requiem. The search engine dated it about 1,073 days old, i.e. late 2023. — [YouTube o5mLhGeHcJw](https://www.youtube.com/watch?v=o5mLhGeHcJw); title and channel via [oEmbed](https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=o5mLhGeHcJw&format=json)
  - "Beyond All Reason : New Beginning", channel nairda draosi. The search snippet mentions a comment about a Brutal playthrough with a tip to "start a vehicle earlier". — [YouTube UfscTKmItro](https://www.youtube.com/watch?v=UfscTKmItro)
  - "Beyond All Reason Scenarios [17 - NEW BEGINNING]". The snippet mentions trouble getting a rocket launcher close enough to a "Basilisk". — [YouTube 6Fdyo32UlAw](https://www.youtube.com/watch?v=6Fdyo32UlAw)

  The video pages themselves (description, comments, chapters) could not be read.
- The hard profile's Cortex Advanced Aircraft Plant (`coraap`) has caretaker 3 and income_tier [50]. Its unit list is [coraca, corvamp, corawac, corhurc, corape, corcrw]. Land-map weights: tier0 [0.10, 0.20, 0.15, 0.05, 0.40, 0.00] and tier1 [0.10, 0.20, 0.10, 0.20, 0.15, 0.15]. So early on, 40% of its output is Wasp gunships (corape), 20% Nighthawk fighters and 15% Condor radar planes. Hailstorm heavy bombers (corhurc) and Archaic Dragon flying fortresses (corcrw) rise in tier1. — [BARb hard factory.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/hard/factory.json)
- The Wasp (corape) is T2: 370 metal, 6,800 energy, build time 18,000, 1,560 HP, speed 159, range 410, 111 DPS of splash rockets that can only hit surface targets. The page says it survives light T1 AA and warns it to "Avoid flak, fighters and heavier SAMs at all costs!" — [beyondallreason.info unit: corape](https://www.beyondallreason.info/unit/corape)

### Inferences
- **Choose the difficulty deliberately.** "Beginner" changes only the player's resource bonus (+50%); the AI and its defenses stay the same. If the goal is only to complete the scenario, Beginner or Novice cuts the economic pressure at no strategic cost. That is a call for the person running the tests (Kailil) — whether a Beginner win counts. Hard/Brutal only add enemy resources.
- **The AI is probably on the hard profile.** No profile is passed, and the engine default is `hard`. Whether BAR's game-side config overrides that default was not verified.
- **Why the commander died at minute 2–5.** The aircraft plant exists from second 0, is assisted by 4 Construction Turrets, and has a 50-income tier gate. The enemy's huge wind, converter and fusion economy clears that gate at once. On land its early mix is 40% Wasps. Four Wasps deal about 444 DPS against the commander's 3,700 HP, which kills it in roughly 8 s. The straight-line distance from the plant (5392, 576) to our commander (552, 6767) is about 7,860 elmos, so at speed 159 Wasps arrive about 50 s after leaving the plant.
- **Survive the first air wave before anything else.**
  - The commander can only build Nettle (armrl) as AA. Chainsaw and Ferret need a T1 constructor; see Key question 4.
  - Useful first moves: pause; have the commander build 2–3 Nettles right next to itself and the fusion; start a factory for T1 constructors; then build Chainsaws.
  - Keep the commander still and under the AA umbrella, never wandering.
  - The commander's cloak costs 100 E/s while still and 1,000 E/s while moving, against the fusion's 750 E/s. A stationary cloak is therefore affordable and may hide the commander from Wasps. This is untested, and BARb's ability to see cloaked units was not checked.
  - Falcon fighters (armfig) from an Aircraft Plant are another option, since the Wasp page warns against fighters.
- **The shield tip has limits.** The Keeper is T2 and costs 3,000 metal and 54,000 energy. Per its unit page it blocks plasma artillery, not missiles or bombs (Wasps fire missiles). So "build a shield early" probably refers to enemy plasma/artillery later, not the T2 air. Early AA matters more.
- **Plasma attacks into the defensive ring will be absorbed.** The enemy ring is covered by 6 Overseer plasma shields, so plasma-based attackers (Fatboy, Rattlesnake, Gauntlet) will lose much of their damage there. Missile and rocket units (Ambassador, armmerl, "good vs. static defense") and bombers are not blocked by shields, per the Keeper page's description of BAR shields.
- **The factories are softer than the ring.** All 4 Birdshot flak guns are on the middle ring, while the factories are covered by Thistles and one SAM. Bombers (Stormbringer, Blizzard) could take waypointed paths around the flak ring, e.g. along the map edges, to hit the aircraft plant and labs. There are no air repair pads (armasp is capped at 0), so bombers cannot be repaired. Nighthawk fighters (20–60% of the aircraft plant's mix) are the main danger to bombers.
- **The south-east enemy outpost is a target and a capture opportunity.** The enemy's south-east mexes and outpost — Twin Guard (5712, 6128), Thistle (5672, 6088), advanced solar (5520, 6128) and metal storage (5781, 6285) — are relatively close to our side. The enemy's T1 constructors (up to 3 corck, 3 corcv, 4 corca) will go out to expand. Catching one near our side is the practical "capture a constructor" chance; see Key question 4 for what can capture.
- **The hover platform must die too.** The water hover platform counts as a factory, and the AI may also build a second Vehicle Plant, two Aircraft Plants, a ground Hovercraft Platform, an Advanced Bot Lab and an Advanced Vehicle Plant. All of them have to be destroyed.
- **Scenario numbering has shifted.** The videos call it scenario 17 and 20, the file says 21, so the list has been renumbered across versions. Strategy shown in older videos may predate current balance.

### Gaps
- No readable walkthrough text, Discord post or Reddit thread specific to "New Beginning" was found. The YouTube descriptions and comments could not be fetched, so which strategy winning players used (air, Ambassador, Fatboy, capture) is unverified.
- The Bulwark's range, damage and weapon type (cordoom, "Energy Weapon") and the Scorpion's stats were not fetched. Whether Ambassador or Rattlesnake outrange the Bulwark is unknown.
- It is unclear whether the `deathmode = builders` enemy-loss check counts Construction Turrets as builders, i.e. whether killing all factories is enough or every turret and constructor must also die.
- Death Valley terrain (cliffs, chokepoints, wind and tidal values) was not researched beyond the coordinates in the scenario file.
- It was not verified whether BAR's game-side config overrides the engine default `hard` profile for scenarios.

## Key question 2: BARb behaviour: difficulty differences, cheats, timing, weaknesses

### Takeaway
BARb's Easy, Medium and Hard profiles are separate config sets in the BAR game repo (there is also a `hard_aggressive` profile). They differ by expansion caps, artificial build delays, build-power ratios and energy targets, not by resource cheats. Resource bonuses come from the lobby handicap, and global vision is an off-by-default option. Easy is deliberately passive and over-builds light defenses. The hard config exposes an exploitable rule: its air factories stop producing when your anti-air threat is high, and its bombers avoid AA.

### Cited Findings
- The game repo's BARb config folder contains the profile directories `easy`, `medium`, `hard` and `hard_aggressive`, plus shared JSON files (behaviour, block_map, build_chain, commander, economy, factory, response). — [GitHub API listing: luarules/configs/BARb/stable/config](https://api.github.com/repos/beyond-all-reason/Beyond-All-Reason/contents/luarules/configs/BARb/stable/config)
- The script folder has matching easy, medium, hard and hard_aggressive directories. The medium `init.as` only loads the profile JSONs (plus Legion, scav and extra-units add-ons via mod options). It contains no cheat or income settings. — [GitHub API listing: script](https://api.github.com/repos/beyond-all-reason/Beyond-All-Reason/contents/luarules/configs/BARb/stable/script); [medium init.as](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/script/medium/init.as)
- Engine-side AIOptions: "LOS vision" (`cheating`, global sight) defaults to false; there are also "Disabled units" and "Load game config" options; the difficulty `profile` defaults to `hard`. — [AIOptions.lua (local engine copy)](file:///C:/Tools/BARANDROID/hailmary-work/recoil-0903/AI/Skirmish/BARb/data/AIOptions.lua)
- Easy profile readme, as summarised by the fetch tool.
  - Stated design goals: expand gradually with fewer mobile builders, play defensively without early raids, keep unit production low, rely heavily on solar, and tech up late.
  - Observed behaviour:
    - The commander stays near base.
    - Too few builders and nano turrets.
    - Raiders act as skirmishers, so there is no early raiding.
    - It relies on standard solar for a long time.
    - Its heavy artillery is easy to kill.
    - "Units respond only to air threats."
    - In a second phase it builds many Porcupines and over-protects the base with light defenses.

  — [easy_ai_readme.txt](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/easy/easy_ai_readme.txt)
- Easy economy: the AI may hold at most 30% of the map's mexes, counting allies. A build delay falls from 3 s to 1 s over the first 1,200 s. Mobile build-power ratio 0.6, one mex upgrade at a time, energy income factor 1.0 at 300 s rising to 10.0 at 7,200 s. — [easy economy.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/easy/economy.json)
- Medium economy: `mex_max` [0.80, true] (80% of mexes). `build_delay` [[1, 0], [0, 900]], i.e. 1 s falling to 0 by 900 s. Energy factor 1.0 at 300 s rising to 15.0 at 3,600 s. Production multipliers [0.9, 0.7, 0.8, 0.8], buildpower 0.6. — [medium economy.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/medium/economy.json)
- Hard economy: `mex_max` [1.0, false] (no cap). `build_delay` disabled (-1; the comment says it is "used to make ai easier"). Energy factor 6.0 at 1 s, 20 at 300 s, 30 at 420 s and 60 at 3,600 s. Production multipliers [0.8, 0.8, 1.0, 0.8], buildpower 1.2. — [hard economy.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/hard/economy.json)
- Hard behaviour, attack and defense:
  - Attack groups need a minimum power of 60 (`quota.attack`).
  - Raid squads have a power range of [6, 150].
  - The enemy-threat multiplier for choosing attack targets is [0.6, 0.8].
  - Retreat thresholds: builders [0.85, 1.0], fighters [0.5, 1.0].
  - Defense radius: base [800, 1,400], commander [800, 400].

  — [hard behaviour.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/hard/behaviour.json)
- Hard behaviour, air:
  - `quota.aa_threat` [[8, 500.0], [24, 500.0]]. Per the config comment, "air factories stop production when anti-air threat exceeds this value".
  - Bombers avoid AA and attack only when expected losses are acceptable (scaled by 0.25 of AA threat against bomber power).
  - Bombers return to airpads for repair, and constructors do not repair air units.
  - Roles: Wasp (corape) is a raider with retreat 0.8; Hailstorm and Whirlwind are bombers; Nighthawk and Valiant are anti-air; Archaic Dragon is heavy.
  - Commanders have the role "builder" with retreat 0.6.

  — [hard behaviour.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/hard/behaviour.json)
- Hard T1 Cortex Aircraft Plant (`corap`): units [corca, corveng, corfink, corshad, corbw], income tiers [30, 90]. Land tier0 is weighted 60% Shuriken paralyzer drones and 30% Whirlwind bombers. — [hard factory.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/luarules/configs/BARb/stable/config/hard/factory.json)
- Since January 29, 2026, the lobby shows each BARbarianAI's difficulty profile next to its name (a contribution by Arcadiyyyyyyyy), per the search snippet of a BAR microblog. — [BAR microblog 171](https://www.beyondallreason.info/microblogs/171)
- Community comments (search snippets only; the Reddit mirror pages could not be loaded):
  - A player who reports a 100% win rate against 1v1 Hard BARb says the AI "does not have much of a plan", that they out-eco it even on large maps without anti-AI cheese, and that working out a good solar-start economy took a few hours. Post dated Dec 17, 2024. — [r/beyondallreason via redlib mirror](https://redlib.hyperreal.coffee/r/beyondallreason/comments/1hggze1/how_to_be_faster)
  - Another thread says the AI is optimised for semi-flat, ground-based maps and makes odd decisions elsewhere. One newer player beat the bot on a volcano map with Armada vehicle-factory spam after a few tries. — [r/beyondallreason via redlib mirror](https://redlib.ssps.io/r/beyondallreason/comments/1lixzjq/best_map_to_challenge_a_beginner)

### Inferences
- **Difficulty is about how fast and how far the AI expands and builds, not cheating.**
  - Easy takes at most 30% of mexes and adds delays.
  - Medium takes up to 80% of mexes with a short delay early on.
  - Hard expands without limits, with no delay and double the mobile build-power ratio of Easy/Medium (1.2 vs 0.6).
  - For a slow agent, Easy and Medium leave large parts of the map uncontested, so out-expanding them is realistic. Hard demands contesting mexes and defending against raids.
- **The AA-threat rule is the clearest low-APM lever.** If enough static AA (Chainsaws, Arbalests) stands near the agent's base, the hard AI should stop air production and its bombers should refuse to engage. Static AA needs no micro. How "threat" is computed (likely DPS-based) and how much AA reaches 500 was not verified, so confirm it by observation.
- **Easy is close to a passive turtle.** It does not raid early, keeps few builders and over-protects with light defenses. A slow agent can safely build up its economy and then push with artillery or T2 units outranging Porcupine-style light defenses.
- **Ground maps are safest for the AI's competence.** Since BARb is tuned for semi-flat ground maps, a cliff/chokepoint map makes it play worse; the counterpart is that the agent's own touch-driven pathing also gets harder on such maps.

### Gaps
- Exact first-attack timings for each profile were not found in the sources. There is no data on "first raid at minute X" for Easy, Medium or Hard. The agent should measure them.
- The `hard_aggressive` profile's differences were not fetched.
- The game-side behaviour.json for Easy and Medium (aggression, retreat) was not compared with Hard; only the economy files were.
- No first-hand Discord, forum or YouTube guide on beating BARb Medium or Hard could be read; Reddit was blocked and the mirrors were down.

## Key question 3: Low-APM-friendly strategies and build orders (Armada vs Cortex AI)

### Takeaway
No authoritative, current Armada-vs-BARb build order was found. The official guides give economy ratios rather than build orders. The low-APM plan that the sources support is: balance metal, energy and build power by the official ratios; get static AA early (which, per the hard config, also suppresses the AI's air); expand to mexes the AI's profile leaves open; then win with stationary or slow tools that need few orders — static defenses at chokepoints, rocket/missile artillery against static defenses, and grouped T2 pushes. Nukes and the Basilica are disabled in "New Beginning".

### Cited Findings
- Official economy guide (search snippet): the economy runs on metal, energy and build power. Use roughly 2 constructors or 1 Construction Turret (200 BP) for every 100 E/s and every 5 M/s. Don't build many metal makers before having a large energy economy. T2 advanced mexes give much more metal. — [beyondallreason.info: in-depth look at economy](https://beyondallreason.info/guide/in-depth-look-at-economy)
- Official "how to start / manage your economy" guide (snippet): it covers starting a base and first expansions, and suggests hovering over the windmill icon to see wind output. — [beyondallreason.info: how to start manage your economy](https://www.beyondallreason.info/guide/how-to-start-manage-your-economy)
- Third-party hub "Master BAR Economics", which describes itself as compiled with AI help from wiki, Reddit and YouTube material:
  - T1 mex ~2 M/s, T2 Advanced Mex ~8 M/s, Fusion ~1,000 E/s, Construction Turret 200 BP.
  - T2 benchmarks: 20–40 M/s metal, 500–800 E/s energy, 1,000–2,000 stored metal, around minutes 5–8.
  - No version or date is stated.

  — [bar-for-new-players.pages.dev](https://bar-for-new-players.pages.dev/)
- Another third-party "Armada Strategy Guide" (not official, AI-generated look) says there is no universal build order and to check wind and metal before choosing wind or solar. One snippet says to build 3 Wind Turbines when wind is high. — [gameai-5v7.pages.dev economy guide](https://gameai-5v7.pages.dev/economy_guide.html)
- The commander's build list is armsolar, armwin, armmstor, armestor, armmex, armmakr, armlab, armvp, armap, armeyes, armrad, armdrag, armllt, armrl, armdl, armtide, armuwms, armuwes, armfmkr, armsy, armfdrag, armtl, armfrt, armfrad, armhp and armfhp. It has workertime 300 and build distance 145. — [armcom.lua](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/units/armcom.lua)
- In New Beginning, nukes (armsilo) and long-range plasma cannons (armbrtha, armvulc) are disabled for the player. Advanced Fusion is capped at 2 and Advanced Energy Converters at 6. — [scenario021.lua (local)](file:///C:/Tools/BARANDROID/toolchain/tmp/scen/scenario021.lua)
- The Ambassador (armmerl) is described as a "Stealthy Rocket Launcher - good vs. static defense". The Rattlesnake (armamb) is a "Cloakable Pop-up Plasma Artillery", the Gauntlet (armguard) "Area Control Plasma Artillery", the Mauser (armmart) "Mobile Artillery" and the Pulsar (armanni) a "Tachyon Accelerator". — [BAR en/units.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/language/en/units.json)

### Inferences
- **Low-APM skirmish plan vs BARb, built from the config findings plus BAR's economy ratios.** No single source documents this plan.
  1. **Pause at 0:00.** The commander places mexes and energy (wind/solar by map), then a Bot Lab or Vehicle Plant set to repeat-build constructors. Long repeat queues on factories minimise decisions.
  2. **By about minute 3–5,** the second and third constructors take nearby mexes. One builds a Construction Turret next to the factory, which is cheap build power that needs no orders.
  3. **Put static AA at the core early:** Nettles by the commander, then 1–2 Chainsaws from a T1 constructor. This blunts BARb's bombers and gunships and, on Hard, may shut its air production off.
  4. **Hold chokepoints with a few static defenses (Sentry/Overwatch class)** instead of micro-heavy units. Easy explicitly does not raid early, and Hard's raid squads are small (power 6–150).
  5. **Go T2 when income reaches the benchmark range** (around 20 M/s and 500 E/s). Build an Advanced Bot or Vehicle Lab, use T2 constructors to upgrade mexes to advanced mexes, and add Fusion.
  6. **Attack with one big, slow group given a single fight order at a time** — e.g. T2 bots or tanks with Ambassadors behind them against static defenses — rather than many small raids.
- **Why this suits a slow agent.** BARb's attack and defense quotas rely on threat estimates. Massed static AA and defenses are threats the agent never has to micro. One large attack-move group fits a seconds-per-decision loop better than raiding.
- **For New Beginning specifically,** nukes and the Basilica are out, and plasma is weakened by 6 Overseers. Missiles/rockets (Ambassador), bombers routed around the flak ring, or a heavy T2 ground push that kills Overseers first (e.g. Fatboys after the shields drop) are the realistic win conditions.

### Gaps
- No verified current (2025–2026) Armada opening build order (exact first 10 orders) for medium maps was found. Official guides give ratios, not orders. Third-party pages are of unknown currency and partly AI-generated.
- No measured win reports for specific strategies (turtle, air, artillery) against each BARb profile were found.

## Key question 4: Unit facts that matter (Armada AA, shield, T2 constructors, bombers, capture; Cortex T2 air)

### Takeaway
Early on, Nettle is the commander's only AA. Chainsaw (T1, 750 metal, range 1,200, 625 DPS, 4,450 HP) is the strongest static AA a T1 constructor can make. Arbalest flak (T2, 500 DPS, range 850) is the T2 standard. Keeper is a costly T2 shield that blocks plasma only. Only commanders (and the T2 Decoy Commander) can capture. The Lazarus rez bot cannot. The Cortex T2 air that kills commanders is mainly Wasp gunships, with Hailstorm heavy bombers and Dragons later.

### Cited Findings
- Armada AA names, from the unit list:
  - Nettle (armrl) "Light Anti-Air Tower"
  - Chainsaw (armcir) "Medium-Range Anti-Air Missile Battery"
  - Ferret (armferret) "Pop-Up Anti-Air Missile Battery"
  - Arbalest (armflak) "Anti-Air Flak Gun"
  - Mercury (armmercury) "Long Range Anti-Air Tower" — disabled in New Beginning
  - Crossbow (armjeth) "Amphibious Anti-Air Bot"
  - Archangel (armaak) "Advanced Amphibious Anti-Air Bot"
  - Shredder (armyork) "Anti-Air Flak Vehicle"
  - Falcon (armfig) "Fighter"
  - Highwind (armhawk) "Stealth Fighter"

  — [BAR en/units.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/language/en/units.json)
- Chainsaw: T1, 750 metal, 7,300 energy, build time 12,000, 4,450 HP, range 1,200, 625 DPS (4-missile salvo, 250 damage per shot, reload 1.6 s). Described as "bomb-resistant", with the most HP, range and damage of the three T1 AA turrets (Nettle, Ferret, Chainsaw). — [beyondallreason.info unit: armcir](https://www.beyondallreason.info/unit/armcir)
- Ferret: T1, 330 metal, 5,700 energy, build time 5,000, 1,600 HP, range 950, 208 DPS. Pop-up, stealth, cloaks for 12 energy. Downs most T1 and some T2 aircraft; the page advises against it as primary AA. — [beyondallreason.info unit: armferret](https://www.beyondallreason.info/unit/armferret)
- Arbalest: T2, 820 metal, 13,000 energy, build time 19,000, 1,750 HP, range 850, 500 DPS (250 per shot every 0.5 s, 172 AoE), air only. — [beyondallreason.info unit: armflak](https://www.beyondallreason.info/unit/armflak)
- Keeper (armgate): T2 plasma shield, 3,000 metal, 54,000 energy, build time 55,000, 3,550 HP. Shield 6,175 strength, radius 550, 130/s regen, 562 energy to regenerate. The page says it blocks plasma artillery, not bombs, lasers or missiles, and suggests a few around the base against early artillery. — [beyondallreason.info unit: armgate](https://www.beyondallreason.info/unit/armgate)
- Among AA, the commander can only build Nettle (armrl). Chainsaw, Ferret, Arbalest and Keeper are not in its build list. — [armcom.lua](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/units/armcom.lua)
- Armada commander: `cancapture = true`, `capturespeed = 1800`, workertime 300, build distance 145, 3,700 HP, autoheal 5, speed 37.5, main laser range 300. D-gun "Disintegrator": range 250, 500 energy per shot, 99,999 damage (0 vs commanders). Cloak cost 100 (still) / 1,000 (moving). — [armcom.lua](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/units/armcom.lua)
- Units with `cancapture` in the BAR repo: commanders (armcom, corcom, legcom and their EvoCom levels), the Decoy Commanders (units/ArmBots/T2/armdecom.lua, cordecom, legdecom), assist drones (armassistdrone, armassistdrone_land) and boss units. — [GitHub code search for "cancapture" in beyond-all-reason/Beyond-All-Reason (via gh api search/code)](https://github.com/search?q=repo%3Abeyond-all-reason%2FBeyond-All-Reason+cancapture&type=code)
- Lazarus (armrectr) has `canresurrect = true`, workertime 200, 130 metal, speed 78 and stealth, with no `cancapture` key. It resurrects but does not capture. — [armrectr.lua](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/units/ArmBots/armrectr.lua)
- Armada T2 constructors: Advanced Construction Bot (armack), Advanced Construction Vehicle (armacv) and Advanced Construction Aircraft (armaca), all "Tech 2 Constructor". — [BAR en/units.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/language/en/units.json)
- Armada bombers and gunships: Stormbringer (armthund) "Bomber", Blizzard (armpnix) "Strategic Bomber", Stiletto (armstil) "EMP Bomber", Liche (armliche) "Atomic Bomber", Hornet (armblade) "Rapid Assault Gunship", Roughneck (armbrawl) "Gunship". — [BAR en/units.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/language/en/units.json)
- Cortex T2 air:
  - Wasp (corape) "Gunship", stats in Key question 1.
  - Hailstorm (corhurc) "Heavy Strategic Bomber"
  - Nighthawk (corvamp) "Stealth Fighter"
  - Archaic Dragon (corcrw) "Flying Fortress"
  - Condor (corawac) "Radar / Sonar Plane"
  - Angler (cortitan) "Torpedo Bomber"
  - Watcher (corhunt) "Advanced Radar / Sonar Plane"

  Cortex T1 air: Valiant (corveng) fighter, Whirlwind (corshad) bomber, Shuriken (corbw) "Light Paralyzer Drone", Finch (corfink) scout. — [BAR en/units.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/language/en/units.json)
- Cortex defenses in the scenario:
  - Bulwark (cordoom) "Energy Weapon"
  - Scorpion (corvipe) "Pop-up Sabot Battery"
  - Birdshot (corflak) "Anti-Air Flak Gun"
  - Overseer (corgate) "Plasma Shield"
  - Shroud (corshroud) "Long-Range Jamming Tower"
  - Thistle (corrl) "Light Anti-Air Tower"
  - SAM (cormadsam) "Hardened Anti-Air Missile Battery"
  - Warden (corhlt) "Area Control Laser Tower"
  - Twin Guard (corhllt) "Anti-Swarm Double Guard"
  - Guard (corllt) "Light Laser Tower"
  - Prevailer (corfmd) "Anti-Nuke System"

  — [BAR en/units.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/language/en/units.json)
- Our starting structures: Cloakable Fusion Reactor (armckfus) "Produces 750 Energy"; Sneaky Pete (armjamt) "Jammer Tower"; Advanced Metal Extractor (armmoho); Advanced Energy Converter (armmmkr) "Converts 600 energy into 10.3 metal per sec". — [BAR en/units.json](https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/language/en/units.json)

### Inferences
- **"Capture enemy constructor" means using the commander.** Only commanders and Decoy Commanders can capture. The commander starts with capture (capture speed 1,800), so it can capture a Cortex constructor that comes within reach (build distance 145) — ideally while the constructor is stopped, building a mex near our side. That unlocks Cortex build menus (Cortex T1 or T2 structures) for the player. A Decoy Commander (armdecom, T2 bot) is a second capturer that does not risk the real commander. Whether armdecom can be built in this scenario (no cap was set for it) and how its capture speed compares were not checked.
- **AA order for the scenario's first 5 minutes:**
  1. Commander: Nettles at once (cheap, and the only AA it can build).
  2. First T1 constructor: Chainsaws (range 1,200, 625 DPS, 4,450 HP, "bomb-resistant").
  3. After T2: Arbalests.

  One Chainsaw (625 DPS) kills a 1,560 HP Wasp in about 2.5 s, so 2–3 Chainsaws plus Nettles around the commander and fusion should break a 4–6 Wasp raid. That figure ignores missile travel and overkill. Ferret is a cheaper filler and should not be the main AA.
- **What Keeper is and isn't for.** At 3,000 metal and 54,000 energy, a Keeper is a mid-game purchase against plasma bombardment, e.g. if the AI's ground units shell the base. It does not stop Wasps (missiles) or Hailstorms (bombs).

### Gaps
- Nettle, Crossbow and Archangel stats (cost, range, DPS) were not fetched.
- Hailstorm, Nighthawk and Archaic Dragon stats were not fetched, nor did any source confirm which Cortex T2 aircraft actually killed the commander in the user's runs. The Wasp is the likeliest, given its 40% early weight in the hard config.
- Capture mechanics (capture time formula, whether capturing needs the target idle, what a captured Cortex constructor can build for Armada) were not documented in the sources read.
- Whether BARb can target the commander while it is cloaked and stationary, and whether building breaks the cloak, was not verified.
