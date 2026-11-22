# LLM / foundation-model agents in RTS and GUI/touch games: what makes them effective (as of Nov 2026)

Scope note: covers StarCraft II LLM agents (2023-2025), microRTS, VLM micro agents, skill-library/code-as-policy game agents, screenshot/GUI/mobile agents, hierarchical and dual-speed designs, APM fairness, and agent-based playtesting/UX work. Dates are given per source; 2023 and early-2024 work is flagged as older. Where a figure came only from a search-result summary rather than a page I read, it is marked "(search summary)". Level numbers ("Lv") refer to the StarCraft II built-in AI levels 1-10; naming differs between papers (TextStarCraft II calls Lv5 "Harder", HEP calls Lv7 "Elite", MASMP calls Lv7 "the hardest"), so compare by number.

## Q1. LLM-RTS systems: observation format, action abstraction, decision cadence, real-time handling, results

### Takeaway
Every LLM-RTS agent that beats built-in AIs at mid-to-high levels gives the LLM a compact text state and a menu of macro actions (train / build / research / attack / expand), with placement, targeting and micro done by scripts. None of them drives raw clicks. When the LLM has to pick coordinates or building spots itself, win rates collapse: LLM-PySC2 goes from 92% to 0% at Lv3. The best 2025 systems (HIMA, MASMP, StarEvolve) reach about 60-90% against Lv7. They get there with fewer LLM calls that each cover a longer horizon, plus state machines / behaviour trees, persistent strategy memory, or fine-tuned small models.

### Cited Findings
**TextStarCraft II + Chain of Summarization (Ma et al.; older: Dec 2023, v3 Jun 2024, NeurIPS-format submission)**
- Text environment built on python-sc2. Observations fall into six categories: Resources, Units, Buildings, In-Process Activities, Enemy Status, Research Progress — [arXiv 2312.11865 (HTML)](https://arxiv.org/html/2312.11865v3)
- The LLM picks macro actions from a dictionary with four categories (unit production, building construction, technology research, other), written as tokens such as `<BUILD PHOTONCANNON>` or `<RESEARCH PSISTORMTECH>`. Micro is done by predefined rule-based Python scripts, "similar to OpenAI Five" — [arXiv 2312.11865](https://arxiv.org/html/2312.11865v3)
- Chain of Summarization has two stages. Single-frame summarization compresses the raw observation. Multi-frame summarization analyzes several frames, recommends commands and makes strategic decisions. Each LLM call returns K actions into an action queue, which is consumed between calls — [arXiv 2312.11865 abstract](https://arxiv.org/abs/2312.11865); [HTML](https://arxiv.org/html/2312.11865v3)
- Results vs Lv5 (20 games each, Protoss vs Zerg): GPT-3.5-turbo-16k 11/20, GPT-4 12/20, Gemini-Pro 5/20, GLM4 4/20, Claude 2.1 3/20. Llama2-70B could not produce valid commands. Fine-tuned Qwen-7B (no CoT) scored 9/20. The abstract's claim that LLMs "can defeat" Lv5 is looser than this table — [arXiv 2312.11865](https://arxiv.org/html/2312.11865v3)
- Prompt design swings results a lot. GPT-3.5 at Lv1-Lv6: Prompt 1 scored 87.5 / 66.7 / 25 / 12.5 / 0 / 0%; Prompt 2 scored 100 / 100 / 100 / 84 / 50 / 8.33% — [arXiv 2312.11865](https://arxiv.org/html/2312.11865v3)
- Fine-tuned small models lost strategic diversity and mostly mass-produced Stalkers. Training data quality mattered: win rate was 28 with all games, 48 with wins only, and 54 with wins from top-25%-APU games — [arXiv 2312.11865](https://arxiv.org/html/2312.11865v3)
- Against humans, a fine-tuned Qwen-1.8B went 0/10 vs a pro and a Grandmaster, 5/10 vs a Gold player and 10/10 vs a new player — [arXiv 2312.11865](https://arxiv.org/html/2312.11865v3)
- The paper's stated limitations are rule-based micro, no visual input and limited race coverage — [arXiv 2312.11865](https://arxiv.org/html/2312.11865v3)

**LLM-PySC2 (Nov 2024)**
- Observation can be text, images, or both. Text covers global info, on-screen units with positions and health, nearby-unit wiki knowledge, recent events, valid actions, errors and messages. Images are RGB screen, minimap and feature maps, with added auxiliary lines and annotations to help the LLM read coordinates — [arXiv 2411.05348](https://arxiv.org/html/2411.05348)
- Action space is the full pysc2 set (over 100 text actions for Protoss), written as `<ActionName(args)>` with screen or minimap coordinates or unit tags and parsed by regex. "Easy Build / Easy Control" modes let the environment choose positions — [arXiv 2411.05348](https://arxiv.org/html/2411.05348)
- Multi-agent roles: Commander, Developer, Builder and CombatGroups, which message each other in natural language. The loop is step-based with a maximum wait per step, and agents query in independent threads — [arXiv 2411.05348](https://arxiv.org/html/2411.05348)
- GPT-4o-mini win rates by mode:

  | Mode | Lv1 | Lv2 | Lv3 | Lv4 | Lv6 | Lv7 |
  |---|---|---|---|---|---|---|
  | Easy Control + Easy Build | 100% | 100% | 92% | 50% | 8% | 0% |
  | Standard Control + Easy Build | 100% | 50% | 0% | 0% | 0% | 0% |
  | Easy Control + Standard Build | 75% | 17% | 0% | 0% | 0% | 0% |

  Source: [arXiv 2411.05348](https://arxiv.org/html/2411.05348)
- Failure modes reported: invalid actions; mistaking allies for enemies; confusing screen and minimap coordinates; idle or out-of-position units; buildings in dangerous or invalid spots; verbose or wrong inter-agent messages; agents trusting teammates without checking — [arXiv 2411.05348](https://arxiv.org/html/2411.05348)
- The paper reports no ablation of images vs text-only — [arXiv 2411.05348](https://arxiv.org/html/2411.05348)

**SwarmBrain (Jan 2024; older)**
- An LLM "Overmind Intelligence Matrix" handles macro strategy (resources, expansion, multi-pronged attacks). A "Swarm ReflexNet" condition-response state machine handles basic Zerg unit maneuvers, explicitly because LLM reasoning is too slow for that. It plays Zerg vs built-in Terran and beat the built-in AI at several difficulty levels (the abstract gives no numbers) — [arXiv 2401.17749](https://arxiv.org/abs/2401.17749)

**HEP, Hierarchical Expert Prompt (Feb 2025)**
- Adds expert tactical knowledge and a hierarchy of task priorities to TextStarCraft II prompts. It was the first LLM agent to beat the Elite (Lv7) built-in AI — [arXiv 2502.11122](https://arxiv.org/abs/2502.11122)
- In HIMA's comparison table, HEP scores 100 / 75 / 75 / 25% at Lv4-Lv7 — [HIMA, arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)

**HIMA, "Society of Mind Meets Real-Time Strategy" (Aug 2025, arXiv)**
- Design: three imitation agents (Qwen-2 1.5B with LoRA, trained on human replays and clustered by unit composition) each propose multi-step macro sequences covering a 3-minute window. A GPT-4o-mini Strategic Planner merges the proposals with a Nominal-Group-Technique-style process and a "temporal chain-of-thought" over immediate, short-term and long-term goals — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)
- Action space: 58 / 61 / 62 race-specific macro actions (production, construction, tech) — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)
- Cadence and latency (game not paused):

  | | HIMA | TextStarCraft II | HEP |
  |---|---|---|---|
  | LLM calls per 20-min game | ~11 | 636 | 468 |
  | Time per call | 22.5 s | 12.1 s | 10.4 s |
  | Total LLM time | ~247 s | 7,695 s | 4,867 s |

  Gameplay continues while HIMA's LLM thinks. Replanning triggers on a failed sequence or on more than 10 visible enemy units — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)
- Protoss vs Zerg win rates, Lv4-Lv10: 100 / 92 / 84 / 82 / 68 / 20 / 16%. Baselines: TextStarCraft II 84 / 55 / 8% (Lv4-6); EpicStar 67% at Lv5 and 30% at Lv6. HIMA won 10/10 head-to-head against SwarmBrain, TextStarCraft II and HEP — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)
- Planner model sensitivity at Lv7: GPT-4o 90%, Claude-Sonnet 70%, Qwen-2.5-72B 75%, Qwen-3-8B 15% — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)
- Limitations:
  - Micro-heavy Terran is much weaker (TvT 62% at Lv4, 4% at Lv5).
  - Most matchups collapse at Lv9-10.
  - Single map, 20-50 games per condition.
  - The 3-minute window and 10-enemy threshold were chosen heuristically.
  - APU and similar efficiency metrics correlate weakly with win rate.

  Source: [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)

**MASMP, Memory-Augmented State Machine Prompting (Oct 2025)**
- Built on LLM-PySC2 (Easy modes) with DeepSeek-V3. Three parts: a macro-strategic state machine whose transition conditions are written in natural language; a behaviour tree for action implementation; and standalone atomic rules. A MemoryDB stores strategy variables (e.g. `[Tactic]:<defensive>`, `[PriorityUnit]`) extracted by regex from LLM output and re-injected every cycle — [arXiv 2510.18395](https://arxiv.org/html/2510.18395v1)
- Simple64, Lv1-7: baseline 100 / 100 / 100 / 40 / 40 / 0 / 0%; MASMP 100 / 100 / 100 / 100 / 100 / 80 / 60% — [arXiv 2510.18395](https://arxiv.org/html/2510.18395v1)
- Failure modes it names in prior LLM RTS agents: hallucinated or invalid actions; greedy short-term choices; fragmented, inconsistent execution across decision cycles; a "knowing-doing gap" where good plans aren't carried out — [arXiv 2510.18395](https://arxiv.org/html/2510.18395v1)
- Internal inconsistency: the text cites LLM-PySC2 at 8% vs Lv6, while its own baseline table shows 0% — [arXiv 2510.18395](https://arxiv.org/html/2510.18395v1)
- No latency or token figures are reported — [arXiv 2510.18395](https://arxiv.org/html/2510.18395v1)

**SC2Arena / StarEvolve (Aug 2025)**
- Supports all races and low-level action spaces, with text observations "optimized" for spatial reasoning. StarEvolve uses a Planner-Executor-Verifier structure with iterative self-correction, plus fine-tuning on gameplay data selected by a scoring system — [arXiv 2508.10428](https://arxiv.org/abs/2508.10428)
- (search summary, not verified in the full paper) A fine-tuned Qwen2.5-7B reaches 73% at Lv7 — [arXiv 2508.10428 PDF](https://arxiv.org/pdf/2508.10428)

**AVA, Attentive VLM Agent (Mar 2025, v6)**
- This is micro only, not the full game (21 maps, mostly SMAC-style).
- Observation: RGB screenshot, a natural-language battlefield description, and structured per-unit metadata (ID, type, position, HP, status), plus detection boxes.
- Actions: attack(unit, target); move to grid cell 1-10 or a direction; ability(unit, ability, target). Runs as a 2 Hz step loop.
- Results: on 3m, zero-shot GPT-4o wins 81% vs QMIX 27.1% after 5M steps. Across 12 micro scenarios GPT-4o averages 30.9%. Every model scored 0% on 2c_vs_64zg and 6r_vs_8z.
- The authors cite "inconsistent spatial understanding in dense unit formations." The abstract's "75-90%" doesn't match its own tables.

Source: [arXiv 2503.05383](https://arxiv.org/html/2503.05383v6)

**microRTS**
- PLAP, "Plan with Language, Act with Parameter" (IJCNN 2025): a library of parameterized skills, an LLM skill planner, and an executor that turns skills into action sequences. GPT-4o zero-shot beats 80% of baseline agents. Qwen2-72B with crafted few-shot examples beats CoacAI, the top scripted agent — [arXiv 2509.13127](https://arxiv.org/abs/2509.13127)
- (search summary) A strategy-augmented LLM planner had the highest win rate against scripted AIs, but performance dropped on larger maps — [arXiv 2505.08459](https://arxiv.org/pdf/2505.08459)
- The MicroRTS LLM Competition at IEEE WCCI 2026 scores agents against six reference AIs (RandomBiased, HeavyRush, LightRush, WorkerRush, Tiamat, CoacAI) on 8x8 and 16x16 maps, 0-100 scale. The leaderboard was empty when fetched — [MicroRTS LLM Competition](https://drchangliu.github.io/MicroRTS/index.html)

### Inferences
- **The interface matters more than the model.** LLM-PySC2's Easy/Standard gap (92% vs 0% at Lv3, same model) is the clearest evidence in the literature. For BAR Droid, Claude should choose things like "build Solar near commander", and the laptop-side executor should turn that into dock taps plus a map tap at a widget-computed valid spot. Claude should not infer build placement from pixels. This keeps every action on the touch surface (required for UX logging) while giving Claude macro-level choices.
- **Fewer, longer-horizon plans with event-triggered replanning beat frequent calls.** HIMA made about 11 calls per game, replanning on a failed sequence or more than 10 enemies, and still won without pausing. That maps directly onto "event-driven auto-pause": replan on enemy sighted or count jump, unit or building lost, build or order failure, idle constructor or factory, resource overflow or stall, or a plan step finishing.
- **Most published wins were not played in real time.** TextStarCraft II's 636 calls × 12.1 s = 7,695 s of LLM time inside a 20-minute game means the game cannot have run in real time during calls (presumably python-sc2's non-realtime stepping; my inference, not stated). So most "beats Lv5-7" numbers come from stepped or paused play, like the current pause-and-think loop. HIMA is the main explicit no-pause result.
- **A persistent strategy memory reduces drift.** MASMP's "Tactic / PriorityUnit" memory and explicit state machine target the inconsistency across cycles that a pause-screenshot-decide loop is prone to. A short persistent plan file that is re-injected every cycle is cheap.
- **Micro is where LLM agents still fail** (Terran in HIMA, dense formations in AVA). BAR fights should lean on engine-side behaviours that the touch dock already exposes (fight or attack-move, area commands, move/fire states, factory repeat), keeping Claude at the macro level.
- **Model choice matters most at the top difficulty** (HIMA: GPT-4o 90% vs Claude-Sonnet 70% as planner at Lv7). Those were 2024-25 models; current Claude models are not represented in any RTS paper found.

### Gaps
- TextStarCraft II's K value and real-time settings were not found in the readable text.
- SwarmBrain's per-level win rates were not retrieved.
- No token or dollar cost figures were found for any StarCraft II LLM agent.
- No LLM agent for Spring/Recoil/BAR, Age of Empires, or Command & Conquer / OpenRA was found in this pass. AoE and OpenRA were not searched specifically within the budget.
- WCCI 2026 microRTS LLM results had not been posted when fetched.
- StarEvolve's 73% figure was not verified against the paper's tables.

## Q2. Voyager-style skill libraries and code-as-policy in games (Voyager, Cradle, CivRealm, others)

### Takeaway
Code skills built on a high-level game API work well (Voyager over a bot API; PLAP's parameterized skills in microRTS). Code skills built on raw keyboard and mouse in commercial games (Cradle) handle navigation and menus. They fail on precise positioning, combat timing and unfamiliar icons, and in practice they paused the game. Persistent, model-managed memory plus a "go to this point" helper were the key harness pieces in Claude Plays Pokémon.

### Cited Findings
- **Voyager** (older: May 2023, revised Oct 2023) has three parts:
  - an automatic curriculum that maximizes exploration;
  - an ever-growing skill library of executable code;
  - iterative prompting with environment feedback, execution errors and self-verification.

  Against prior state of the art it found 3.3x more unique items, travelled 2.3x farther and unlocked tech-tree milestones up to 15.3x faster, using GPT-4 as a black box — [arXiv 2305.16291](https://arxiv.org/abs/2305.16291)
- **Cradle** (v3, Jul 2024): see the summary below.
  - Observation: a 2 fps video clip of the last action's execution, read with GPT-4o OCR, template matching, Grounding DINO and SAM.
  - Actions and skills: LMM-written Python over key and mouse primitives. Skills are curated as code functions in procedural memory and retrieved by embedding.
  - Pausing: **RDR2 and Stardew Valley were paused while waiting for the model.**
  - The paper notes "potentially high costs and long delays."
  - Source: [arXiv 2403.03186](https://arxiv.org/html/2403.03186)
- **Cradle results (GPT-4o, 5 runs):**

  | Game | Task results |
  |---|---|
  | RDR2 | Follow Dutch 5/5, Follow Micah 5/5, Hitch Horse 4/5, Protect Dutch 1/5, Search for Supplies 1/5 |
  | Stardew Valley | Cultivation 4/5, Shopping 1/5 |
  | Cities: Skylines | roads 4/5, water 1/5, electricity 5/5; population 450±224 (850±142 with human help) |
  | Dealer's Life 2 | profit rate 39.6±27.3% |

  Source: [arXiv 2403.03186](https://arxiv.org/html/2403.03186)
- **Cradle failure modes:**
  - spatial perception and locating enemies, especially indoors;
  - precise timing in real-time combat;
  - out-of-distribution icons and art styles;
  - precise grid positioning;
  - non-standard UI layouts;
  - skipped UI steps (e.g. forgetting to press Save).

  Source: [arXiv 2403.03186](https://arxiv.org/html/2403.03186)
- **CivRealm** (ICLR 2024; older):
  - BaseLang runs one AutoGPT-like LLM instance per unit. Mastaba adds an advisor-plus-workers hierarchy.
  - By turn 113, Mastaba had already passed the exploration and settlement BaseLang reached by turn 210.
  - Mastaba's fast early growth sometimes triggered Freeciv's pirate invasions and early defeats.
  - Both RL and LLM agents struggle to make real progress in the full game.

  Source (search summary of the paper): [arXiv 2401.10568](https://arxiv.org/html/2401.10568v2)
- **PLAP** (microRTS, IJCNN 2025): a parameterized skill library plus a separate executor beat the top scripted microRTS agent with an open model — [arXiv 2509.13127](https://arxiv.org/abs/2509.13127)
- **MASMP**: a behaviour tree under an LLM state machine lifted LLM-PySC2 from 0% to 60% at Lv7 — [arXiv 2510.18395](https://arxiv.org/html/2510.18395v1)
- **Claude Plays Pokémon** (public Feb 2025; secondary sources):
  - Tools: emulator buttons; a model-managed knowledge base capped at about 8,000 tokens; a "Navigator" tool that lets the model point at an on-screen location and walks the character there.
  - Each button press returns the game screenshot plus a copy with coordinate overlays.
  - Navigating the 2D world was the main weakness.

  Sources: [ZenML LLMOps database](https://www.zenml.io/llmops-database/building-and-deploying-a-pokemon-playing-llm-agent-at-anthropic); [michaelyliu6 write-up](https://michaelyliu6.github.io/posts/claude-plays-pokemon); [TechCrunch](https://techcrunch.com/2025/02/25/anthropics-claude-ai-is-playing-pokemon-on-twitch-slowly). A community post says Opus 4.7 finally beat Pokémon Red; unverified — [LessWrong](https://www.lesswrong.com/posts/sehJYg5Yny9fvpbpt/a-year-late-claude-finally-beats-pokemon)
- **lmgame-Bench** (ICLR 2026): a modular harness of perception, memory and reasoning. Perception either reads game state from the backend or has the LLM describe the screen. The harness lifts models clearly above random, and the benchmark exposes weaknesses in visual state extraction, reflection, spatiotemporal reasoning and long context — [arXiv 2505.15146](https://arxiv.org/abs/2505.15146)
- **A related modular-harness study:** memory dominates in long-horizon puzzles; perception is critical in general agent settings — [arXiv 2507.11633](https://arxiv.org/html/2507.11633v1)

### Inferences
- **Treat macro actions as a skill library of touch scripts** that run on the laptop with no LLM in the loop. Examples: select idle constructors; queue N of X at factory F; build X at world point P; fight-move group G to P; toggle repeat. Each skill should check its own result against the next state dump (Voyager-style self-verification) and report failures as events. Skills that repeatedly fail or need retries are themselves UX data points.
- **Build the equivalent of Pokémon's Navigator**: a "tap world point (x, z)" helper that uses the widget's world-to-screen projection. Every touch-based game agent in this literature lost time to localization.
- **Avoid one LLM per unit.** CivRealm's per-unit LLMs (BaseLang) did poorly. Keep one strategist with group-level skills.

### Gaps
- Cradle's per-step latency, tokens and cost were not in the readable portion.
- The fetched Voyager abstract doesn't describe its interface. Its use of the Mineflayer JavaScript API comes from prior knowledge and was not confirmed in this pass.
- No published Anthropic write-up of the Pokémon harness was fetched, so those details rest on secondary sources.

## Q3. Screenshot/GUI-only agents (games and mobile apps): accuracy and speed limits; combining with accessibility trees or state APIs

### Takeaway
Screenshot-only agents remain slow, waste steps, and struggle to place taps precisely. On real-time games they nearly fail outright (VideoGameBench: best model under 2% even with pausing). Structured text (accessibility tree, API, CLI over adb) matches or beats screenshots on success, with fewer steps. Large trees, however, add thousands of tokens per step and latency. The strongest agents mix modes: text state plus annotated screenshots (Set-of-Marks, coordinate overlays, detection boxes).

### Cited Findings
- **VideoGameBench** (May 2025): 1990s games.
  - A "Lite" variant pauses the game while waiting for the model, added because inference latency was a major limitation.
  - Best model, Gemini 2.5 Pro, completed only 0.48% of the full benchmark and 1.6% of Lite.

  Source: [arXiv 2505.18134](https://arxiv.org/abs/2505.18134v2). (search summary) Lite brought only slight quantitative and notable qualitative improvement; a later project version lists 23 games — [OpenCV write-up](https://opencv.org/videogamebench/)
- **AndroidWorld** (ICLR 2025): the M3A agent reached 30.6%. Multimodal input generally did not beat text-only (accessibility tree) input (search summary) — [arXiv 2405.14573](https://arxiv.org/pdf/2405.14573)
- **OSWorld-Human** (2025, revised May 2026):
  - Top computer-use agents take tens of minutes on tasks humans do in a few minutes.
  - Planning, reflection and judging LLM calls make up most of the latency.
  - Later steps take up to 3x longer than early ones.
  - The best of 16 agents still use 2.7-4.3x more steps than humans.

  Source: [arXiv 2506.16042](https://arxiv.org/abs/2506.16042). (search summary) Adding the accessibility tree "drastically" raises per-task latency because it adds thousands of tokens per step, though it sometimes cut step counts — [arXiv 2506.16042 PDF](https://arxiv.org/pdf/2506.16042)
- **"Beyond the GUI Paradigm: Do Mobile Agents Need the Phone Screen?"** (Jun 2026): agents driving Android over adb with a CLI and no screen.

  | Benchmark | CLI agent | GUI agent(s) |
  |---|---|---|
  | AndroidWorld | Claude Code (Opus 4.7) 71.8% | GUI-Owl-1.5-32B 69.3% |
  | MobileWorld | Claude Code (Opus 4.7) 51.9% | GUI-Owl-1.5-32B 43.2% |
  | CLI-advantage suite | 60.7-68.9% | 22.2-33.3% |
  | Average steps per task | 10.7 | 18.6 |

  - GUI failures cluster in step repetition and premature termination. CLI failures cluster in reasoning-action mismatch and weak verification.
  - The CLI cannot reach functions that exist only in visual UI flows.

  Source: [arXiv 2606.19388](https://www.alphaxiv.org/abs/2606.19388.md)
- **Lap** (Jul 2025), LLM playtesting of a match-3 game from board snapshots (o1-mini / GPT-4). It beat prior tools on code coverage and crashes. (search summary) GPT-4 consistently struggled with precise candy localization and move choice from visual input alone — [arXiv 2507.09490](https://arxiv.org/html/2507.09490v1)
- **LLM-PySC2 needed grid overlays** on screenshots and still saw screen-vs-minimap coordinate confusion — [arXiv 2411.05348](https://arxiv.org/html/2411.05348)
- **AVA combined screenshot, text and structured unit metadata**, and still reported spatial confusion in dense formations — [arXiv 2503.05383](https://arxiv.org/html/2503.05383v6)
- **Cradle's failures** (icons, precise positioning, UI layouts) are the screenshot-only failure set in commercial games — [arXiv 2403.03186](https://arxiv.org/html/2403.03186)

### Inferences
- **Make the widget's text dump the primary observation and take screenshots on demand**, e.g.:
  - when the dump can't answer a question;
  - to confirm that a new or changed dock screen looks right;
  - when logging a suspected UX issue.

  With today's loop, the full screenshot per cycle is probably the biggest token cost, and the literature suggests it buys little decision quality.
- **Keep the dump compact.** The OSWorld-Human result on tree cost applies here: send diffs or deltas since the last cycle, group units by type and position cluster, cap lists, and put screen coordinates only on things Claude can act on.
- **Verify sometimes.** The CLI agents' weakness is weak verification. A state-only agent can miss that a tap landed on the wrong dock button. Have the executor compare expected and actual state change after each touch script, with an occasional cheap low-resolution screenshot.

### Gaps
- No study was found that directly measures per-step latency for screenshot vs accessibility-tree vs API input on the same Android agent.
- The 600-1,400 ms per-action Android automation figure in one search summary could not be tied to a citable source, so it is omitted.

## Q4. Hierarchical "LLM plans, script executes" designs and dual-speed architectures

### Takeaway
This is the most consistent winning pattern across RTS, 4X and real-time benchmarks. The slow LLM sets strategy and parameters; rules, behaviour trees or learned policies execute and react. Running a fast reactive path in parallel with slow planning (AgileThinker) holds up far better under time pressure than either alone.

### Cited Findings
- **The pattern recurs across every StarCraft II system above:**
  - TextStarCraft II: LLM macro, rule-based micro — [arXiv 2312.11865](https://arxiv.org/html/2312.11865v3)
  - SwarmBrain: LLM Overmind plus ReflexNet state machine, explicitly for latency — [arXiv 2401.17749](https://arxiv.org/abs/2401.17749)
  - LLM-PySC2: Easy modes delegate placement and control — [arXiv 2411.05348](https://arxiv.org/html/2411.05348)
  - HIMA: an LLM planner over small imitation policies that emit 3-minute macro sequences — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)
  - MASMP: an LLM state machine over a behaviour tree — [arXiv 2510.18395](https://arxiv.org/html/2510.18395v1)
- **The same pattern appears outside StarCraft II:** PLAP's LLM skill planner and skill executor in microRTS — [arXiv 2509.13127](https://arxiv.org/abs/2509.13127); CivRealm's Mastaba advisor-worker hierarchy outpacing flat per-unit LLMs — [arXiv 2401.10568](https://arxiv.org/html/2401.10568v2)
- **Real-Time Reasoning Gym / AgileThinker** (Nov 2025, ICLR 2026):
  - The environment advances at a fixed rate whether or not the agent has finished thinking. If no action arrives in time, a default is applied (repeat the last move, or idle).
  - Reactive DeepSeek-V3 vs planning DeepSeek-R1: reactive agents lose quality as cognitive load rises (0.89 → 0.15); planning agents collapse as time pressure rises (0.92 → 0.05).
  - AgileThinker runs both threads in parallel. The reactive thread acts in the last part of each step and reads the planner's partial reasoning trace. It held up much better (0.88 → 0.50 under load; 0.90 → 0.58 under pressure) — [arXiv 2511.04898](https://arxiv.org/html/2511.04898v1)
- **AgileThinker results** (normalized scores, 0-1):

  | Game, condition | Reactive (V3) | Planning (R1) | AgileThinker |
  |---|---|---|---|
  | Freeway, 4k tokens/step | 0.29 | 0.12 | 0.62 |
  | Overcooked, 4k tokens/step | 0.38 | 0.02 | 0.71 |
  | Freeway, wall-clock (~8k tokens/step) | 0.24 | 0.12 | 0.88 |
  | Snake, wall-clock | 0.37 | 0.04 | 0.45 |
  | Overcooked, wall-clock | 0.57 | 0.00 | 0.89 |

  The best reactive budget was about 2-5k tokens per step — [arXiv 2511.04898](https://arxiv.org/html/2511.04898v1)

### Inferences
- **Recommended shape for BAR Droid:**
  1. A slow Claude strategist, called on events or on a long timer. It writes a short plan: a build-order queue, army posture, targets.
  2. A deterministic laptop executor with no LLM. It runs touch skills from that plan and handles "reflex" rules: keep factories producing, re-queue failed builds, pull back when a group's HP drops, send idle constructors to assist. It raises events that trigger the strategist.
  3. A default action when no plan is ready: keep the last orders running (factory repeat, constructor queues). This mirrors AgileThinker's "repeat previous action".
- **Pause vs no pause:**
  - Event-driven auto-pause is the "Lite" or stepped mode that most published wins used.
  - The executor still lets the game run unpaused between strategist calls (HIMA style). That should both speed up wall-clock play and give more realistic touch-UX timing.
- **The reflex rules must issue taps through the dock too**, or the UX log will miss those interactions.

### Gaps
- No paper compared paused and unpaused play for the same RTS LLM agent head to head.
- No paper used a touch-only action surface for an RTS LLM agent.

## Q5. APM / reaction-time limits and fairness constraints, and what they mean for a slow agent

### Takeaway
Fairness work (AlphaStar) caps agents from above, at about 22 agent actions per 5 s and with a camera view. LLM RTS agents sit far below any such cap, and they compete against built-in AIs that have no human-like limits. For BAR Droid the binding constraint is too few actions, not too many. Pausing is fine for a "can it win" milestone, but it hides time-pressure UX problems unless timing is measured separately.

### Cited Findings
- **AlphaStar (Nature version, Oct 2019; older):**
  - At most 22 agent actions per 5 seconds. One agent action is a selection, an ability and a target, and counts as up to 3 actions on the in-game APM counter.
  - Camera moves count as agent actions but not toward APM.
  - It sees the game through a camera view with information similar to a human's.
  - The limits were set with pro player TLO to match "the same kind of constraints that humans play under."

  Source: [DeepMind blog](https://deepmind.google/blog/alphastar-grandmaster-level-in-starcraft-ii-using-multi-agent-reinforcement-learning/)
- **The earlier Jan 2019 demo had looser limits:** no camera restriction, per [Fortune](https://fortune.com/2019/10/30/artificial-intelligence-can-now-beat-nearly-everyone-at-video-game-starcraft-2), and community analysis reported 1,000+ APM bursts over 5-second windows, per [LessWrong](https://www.lesswrong.com/posts/du8qqfgQz3ovBm26A/link-did-alphastar-just-click-faster) (community commentary)
- **The Nature paper also notes delays** from network latency and computation time, with peak APM well below humans' (search summary) — [DeepMind research page](https://deepmind.google/research/breakthroughs/alphastar/)
- **LLM agents run at very low action rates.** HIMA makes about 11 strategic calls per game at 22.5 s each — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1). TextStarCraft II and HEP average 10-12 s per call — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)
- **HIMA reports that efficiency metrics** (APU and similar) correlate only weakly with win rate — [arXiv 2508.06042](https://arxiv.org/html/2508.06042v1)

### Inferences
- **Rough rate for the current loop** (my estimate): a 15-30 s cycle with roughly 3-8 taps works out to about 6-30 taps per minute. That is about 1-10% of AlphaStar's cap (about 264 agent actions per minute) and well below typical human RTS APM. No fairness cap is needed. The design question is how to multiply effective actions per LLM call, which is what macro skills, queues and reflexes do.
- **Because built-in AIs act every frame**, winning against BARb Hard at this cadence depends on choosing macro actions that the engine carries out without further input (factory repeat, queued build orders, fight commands, area reclaim/repair).
- **For UX logging, keep game-time and wall-clock timing separate**: time from intent to completed touch sequence, touches per intent, and retries. A paused agent can say a control is hard to hit, but not that it's too slow under pressure unless that is measured or simulated.

### Gaps
- An exact AlphaStar reaction-delay figure (a ~350 ms average is often quoted) was not verified in this pass.
- No data was found on BARb's APM or reaction time.
- No LLM-RTS paper reports agent APM.

## Q6. Bots/agents for automated playtesting and UX evaluation of controls

### Takeaway
Automated playtesting is well established for finding bugs, measuring coverage and predicting difficulty. Examples: King's human-like agents for Candy Crush, EA's Sims Mobile agents, 2025 LLM testers (Lap, TITAN). LLM "simulated user" usability work exists for web and iOS screens (UXAgent, UXCascade, UX-LLM). No published work was found in which an agent drives a real touch control surface in an RTS and reports control-UX problems, so BAR Droid's goal is largely novel. The same perception failures listed above (mis-taps, icon confusion, step repetition, premature stopping) are both risks and potential UX signals.

### Cited Findings
- **Human-like playtesting with deep learning** (King, CoG 2018; older): networks learned from player data predict new levels' difficulty in Candy Crush Saga and Soda Saga — [Gudmundsson et al.](https://www.academia.edu/40020341/Human_Like_Playtesting_with_Deep_Learning)
- **EA's The Sims Mobile agents** (2018; older): automated agents explore the game space faster than human sessions — [arXiv 1811.06962](https://arxiv.org/pdf/1811.06962)
- **A lightweight human-like playtesting approach** (2021; older), on the open-source CasseBonbons match-3 clone. It cites Android touch record-and-replay and GUI input generators (Humanoid, Dynodroid) as baselines — [arXiv 2102.13026](https://arxiv.org/pdf/2102.13026)
- **Lap** (Jul 2025): an LLM plays match-3 from board snapshots, with higher code coverage and more crashes found than prior tools. GPT-4 struggled to localize candies precisely from the image — [arXiv 2507.09490](https://arxiv.org/html/2507.09490v1)
- **TITAN** (Sep 2025): an LLM agent for MMORPG QA with 95% task completion, deployed in 8 real QA pipelines. It targets functional and logic bugs, not UX (search summary) — [arXiv 2509.22170](https://arxiv.org/html/2509.22170v1)
- **Persona-guided GUI testing** (Mar 2026): LLM testers with personas found more crashes and functional bugs than a persona-free baseline. It notes that game alpha/beta testing depends on crowds for device- and region-specific problems (search summary) — [arXiv 2603.24160](https://arxiv.org/html/2603.24160v2)
- **UX-LLM**: a vision-language model flags usability issues on iOS screens. Experts validated its predictions, and a focus group said it surfaced problems they hadn't known about (search summary) — [arXiv 2411.00634](https://arxiv.org/pdf/2411.00634v2)
- **UXAgent** (CHI EA 2025): generated personas run simulated sessions on websites. 16 UX researchers praised it but raised concerns — [arXiv 2502.12561](https://arxiv.org/pdf/2502.12561)
- **UXCascade** (2026): aggregates agent usability feedback across persona traits and goals and links each issue to the agent's reasoning. It was compared with human feedback on a site seeded with known issues (search summary) — [UXCascade](https://www.alphaxiv.org/abs/2601.15777)
- **Known agent failure modes on real UIs** double as UX signals, but agent and UI causes must be separated:
  - Cradle: non-standard layouts, missed Save, OOD icons — [arXiv 2403.03186](https://arxiv.org/html/2403.03186)
  - GUI mobile agents: step repetition, premature termination — [arXiv 2606.19388](https://www.alphaxiv.org/abs/2606.19388.md)

### Inferences
- **Structure UX logging around each intent.** For every macro skill, log:
  - the intended action;
  - the exact touch sequence (taps, drags, coordinates, dock screen);
  - the state diff before and after;
  - success or failure, and retries;
  - wall-clock time.

  Touches per intent, retry rate and "needed a screenshot to recover" are measurable UX metrics. A failure that recurs in the same dock place across games is a UX candidate. A one-off is more likely agent error.
- **Perfect coordinates hide discovery problems.** An agent fed exact world-to-screen positions and dock button positions by the widget won't notice that a button is hard for a human to find or read. Add periodic screenshot-only probes of individual dock flows: find and use the build grid or order buttons from the image alone, and log where it gets confused, the way Cradle got confused by icons. This keeps the fast, cheap state path for play while still testing what the screen shows.
- **The human remains the judge of "feel".** The literature has validated agents for finding bugs and predicting difficulty, but agent UX findings so far still rely on expert review or human comparison (UX-LLM, UXCascade). Agent-logged UX issues are best treated as candidates for Kailil to confirm.

### Gaps
- No study was found of an LLM or RL agent driving a real touch control scheme in an RTS (or any action game) to find control-UX issues.
- No published accuracy figures were found for how often agent-reported UX issues match human-reported ones in games.
- EA SEED's and Ubisoft La Forge's recent playtesting-agent work was not searched within the budget.
