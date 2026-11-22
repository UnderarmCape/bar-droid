# Testing, hardening and work organisation for a small-team Android port of a native RTS engine (release in days)

Scope: Recoil/Spring engine in a proot Linux container, X server inside the app, OpenGL via Mesa (Turnip/Zink) on Adreno; one owner, several parallel AI coding-agent sessions, ONE shared automated-test phone plus the owner's own phone; sideloaded APK, no Play Console. Research date 2026-11-22.

## Q1. Which testing methods find which bugs, at what cost? (agent playtests, scripted on-device suites, replay/scenario tests, AI-vs-AI soaks, monkey/fuzz, human expert passes)

### Takeaway
The published evidence is thin and mostly small-scale. No single method dominates. Deterministic replay/scenario tests and long soaks are the cheapest way to catch regressions and crash/leak/thermal problems in an RTS engine. Human expert passes on the target phone remain the only reliable judge of feel, readability and "is it fun/usable". LLM agent playtests do find real crash/hang/logic bugs in research settings, but they are slow, produce many false alarms (about 30% in the best-documented system) and play real-time games badly. Their value lies in exploration and in turning what they find into reproducible reports, not in winning games.

### Cited Findings

**Industry practice and developer attitudes**
- A 2021 literature review concluded that game studios rely almost entirely on manual playtesting and testers' knowledge, and that this lack of automation is a shortcoming. — [Politowski et al., A Survey of Video Game Testing (arXiv 2103.06431)](https://arxiv.org/pdf/2103.06431)
- In a follow-up developer survey (only 12 accepted responses), all respondents used manual playtesting regularly, some tested inside the engine, and none used scripts to playtest. Respondents were sceptical of automated agents. Their objections were the up-front cost of tools and agent training, the need for dedicated engineers who "cost more than manual testers", and seeded-bug benchmarks ("You don't want to find the bugs you already know about"). — [Politowski et al., Towards Automated Video Game Testing: Still a Long Way to Go (arXiv 2202.12777)](https://ar5iv.labs.arxiv.org/html/2202.12777)
- The same survey's respondents said they mostly hunt for crashes and stuck behaviour first, then graphical, collision and performance issues. Their testing goals ranked bug finding first, then content exploration, then balancing. The authors argue humans are still needed to spot inconsistencies and judge fun. Of the research approaches shown, an exploration (curiosity) agent was rated most desirable (8 "yes"). — [Politowski et al. 2022](https://ar5iv.labs.arxiv.org/html/2202.12777)
- EA SEED's curiosity-driven RL agents (CoG 2021) are rewarded only for novelty. They learn to reach different areas of a 3D map and are used to visualise coverage and find oversights. No bug counts were found in the abstract-level material. — [Gordillo et al., EA SEED (arXiv 2103.13798)](https://arxiv.org/pdf/2103.13798); [EA SEED news](https://www.ea.com/seed/news/cog2021-curiosity-driven-rl-agents)
- Rare (Sea of Thieves) built a framework for gameplay automated tests and gave a GDC 2019 talk on test types, coverage and keeping tests reliable on a live game. The announcement gives no counts. A Game Developer series credits automated testing with enabling over 100 internal deployments before launch (from a search snippet, not a fetched page). — [GDC 2019 announcement](https://gdconf.com/news/sea-thieves-devs-share-automated-testing-tips-gdc-2019); [GDC Vault talk page](https://gdcvault.com/play/1026366/Automated-Testing-of-Gameplay-Features); [Game Developer, part 4](https://gamedeveloper.com/design/how-rare-automates-testing-for-ai-and-more-in-sea-of-thieves-part-4-of-4-)

**(a) AI / LLM agent playtests**
- TITAN (LLM agent for MMORPG testing, GPT-4o, PC and mobile games):
  - **How it works:** it abstracts raw state into a few discretised factors (location, objectives, HP High/Med/Low, nearby NPCs/items), narrows the action list to about 5 recommended actions with expert rules, validates actions before executing them, and triggers reflection after 20 consecutive actions without progress. It keeps a persistent state-action coverage map across runs.
  - **Oracles:** a crash monitor, a task-status monitor that writes structured diagnosis reports, and an execution-time monitor.
  - **Results:** 95% task completion (humans 100%), 73% state coverage (vs 55% for DRL and 60% for ReAct), and 82% detection of seeded bugs (vs about 45% for the baselines and about 18% for humans who were limited to 5 attempts). It found 4 new bugs and is reported deployed in 8 QA pipelines.
  - **Caveats:** a 30% false-alarm rate that needs human triage, and per-loop latency and cost were not reported. The paper is internally inconsistent on the bug count (9 vs 15).
  - [Leveraging LLM Agents for Automated Video Game Testing (arXiv 2509.22170)](https://arxiv.org/html/2509.22170)
- ReAct-style agents slowed sharply on the mobile game in the TITAN study, which the authors attribute to verbose raw state dumps. This is evidence that state abstraction matters more than model choice. — [arXiv 2509.22170](https://arxiv.org/html/2509.22170)
- VideoGameBench (2025) gave vision-language models raw screenshots only. Inference latency was "a major limitation" in real time, so the authors added a Lite mode that pauses the game while the model thinks. The best model (Gemini 2.5 Pro) completed 0.48% of the benchmark in real time and 1.6% paused. Failure modes were a knowing-doing gap (right key, wrong place), memory overwriting, loops, hallucinated progress and visual misperception. — [VideoGameBench (arXiv 2505.18134)](https://arxiv.org/pdf/2505.18134)
- iv4xr agent-based testing experience report: agent playtests raised code coverage from 18.8% (unit tests alone) to 88.4% combined and found 2 subtle bugs that unit tests missed. TESTAR found a jet-pack bug after about 3 minutes of exploring a small level. — [An Agent-based Approach to Automated Game Testing (arXiv 2211.06386)](https://arxiv.org/pdf/2211.06386) (figures from the search snippet of the paper)
- Inspector (pixel-based exploration agent) found 2 potential bugs in shooter and action-RPG test maps. — [arXiv 2207.08379](https://arxiv.org/pdf/2207.08379)
- For mobile GUI testing (apps, not games), GPTDroid reached 75% activity coverage and 66% code coverage, more than 32% and 20% above the best of 10 baselines. It found 53 new bugs on Google Play, 35 of them confirmed or fixed. — [GPTDroid, ICSE 2024 (arXiv 2310.15780)](https://arxiv.org/pdf/2310.15780); earlier version: [arXiv 2305.09434](https://arxiv.org/pdf/2305.09434)

**(b) and (c) Scripted regression suites and deterministic replay/scenario tests**
- Riot made the League of Legends server deterministic specifically to get "fast, repeatable tests driven from a set of recordable inputs". Its automation harvests scenarios from public beta games and catches divergence bugs before Live. One divergence happened in only about 1 in 5,000 real games and took months to reproduce in detailed logs. Replays expire with the patch they were recorded on. Making the server deterministic took almost a year of several engineers' work. Riot ran about 100,000 test cases a day (figures from search snippets of Riot's posts). — [Determinism in LoL: Fixing Divergences](https://technology.riotgames.com/node/84); [Determinism: Implementation](https://technology.riotgames.com/node/68); [Automated Testing for League of Legends](https://technology.riotgames.com/node/33)
- Factorio: integration tests that run the whole game catch determinism regressions just by running the suite (FFF #60). A "heavy" mode saves and reloads every tick and compares map CRCs. It is very slow but "critical" for determinism (FFF #315). Wube credits the tests with uncovering many desync problems before the stable multiplayer release (FFF #62). An unverified forum post cites "almost 6,000 automated tests" in 2024. — [FFF #60](https://factorio.com/blog/post/fff-60); [FFF #315](https://cf-www.factorio.com/blog/post/fff-315); [FFF #62](https://direct.factorio.com/blog/post/fff-62); [FFF #438 forum thread](https://forums.factorio.com/viewtopic.php?p=643875)
- Recoil specifics:
  - BAR's `enginesynctestlocal` runs two engine instances on one machine to test for desyncs, and `spring-headless` can be swapped in. — [enginesynctestlocal](https://awesome.ecosyste.ms/projects/github.com%2Fbeyond-all-reason%2Fenginesynctestlocal); [Recoil headless and dedicated binaries](https://beyond-all-reason.github.io/spring/guides/headless-and-dedi)
  - BAR's netcode overview says Recoil needs hardware-specific workarounds for identical results, which is why it is not offered outside x86-64. — [Recoil netcode overview](https://beyond-all-reason.github.io/spring/articles/netcode-overview)
  - An old Spring Mantis issue notes that demos did not save per-frame sync checksums, which limits "replay a demo and compare" checks. — [Mantis 2733](https://springrts.com/mantis/view.php?id=2733)
  - A resolved headless desync bug was easy to reproduce with cheat "give all units" setups. — [Mantis 2591](https://springrts.com/mantis/view.php?id=2591)
- Flakiness baseline: at Google, about 1.5% of all test runs were flaky (both pass and fail on the same code), and almost 16% of 4.2 million tests showed some flakiness. — [Google Testing Blog, Flaky Tests at Google](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)

**(e) Monkey/fuzz input**
- In an industrial WeChat study, Monkey covered only 19.5% of code lines and 10.3% of activities, against 30.6% and 28.7% for the authors' tool. — [WeChat FSE16 industry paper](https://mir.cs.illinois.edu/winglam/publications/2016/fse16industry-wechat.pdf)
- Choudhary, Gorla and Orso compared Android input generators on 60+ real apps (1 hour per tool per app, repeated 10 times). They found the tools effective but limited. An ASE 2020 paper studied why Monkey plateaus on 68 benchmarks. — [Are We There Yet? (arXiv 1503.07217)](https://arxiv.org/pdf/1503.07217); [Seven Reasons Why, ASE 2020](https://www.se.cs.uni-saarland.de/conferences/ASE/ase2020/conf.researchr.org/details/ase-2020/ase-2020-papers/33/Seven-Reasons-Why-An-In-Depth-Study-of-the-Limitations-of-Random-Test-Input-Generati.html)

**(f) Human expert passes**
- In the TITAN study, human testers completed 100% of tasks but found far fewer crash cases (they were limited to 5 attempts and focused on finishing efficiently). — [arXiv 2509.22170](https://arxiv.org/html/2509.22170)
- Developers in the Politowski survey see humans as necessary to spot inconsistencies and judge fun. — [arXiv 2202.12777](https://ar5iv.labs.arxiv.org/html/2202.12777)

### Inferences
- **Comparison matrix (synthesis, not from one source):**

| Method | Finds best | Misses | Cost on one dev phone | Days-to-release value |
|---|---|---|---|---|
| (a) LLM touch playtest | Crashes or hangs on unusual paths, stuck states, logic and flow bugs in menus and tutorials, discoverability problems | Timing and feel issues, anything needing fast reactions, subtle visual bugs; high false-alarm triage load (~30% in TITAN) | Very high: slow loop, ties up the device, plus token cost | Low to medium. Use as scripted "feature tours" only. |
| (b) Scripted on-device touch suite | Regressions in known flows (launch, lobby, skirmish start, pad/touch controls, save/load, pause/resume, rotation/fold) | New bugs off the script; flaky by nature (touch timing, loading variance) | Medium: minutes per run, reusable | Highest. This is the release-gate smoke suite. |
| (c) Replay/scenario determinism | Sim divergence (critical for online safety), crashes in late-game states, perf regressions on a fixed workload | Input and UI bugs, Android lifecycle bugs | Low once built. Runs on the dev phone: the project's rule keeps BAR checks off the owner's laptop, so the x86 reference values must come from recorded server replays, not local runs | Very high for "sim identical/online-safe" claims and fixed perf benchmarks |
| (d) AI-vs-AI soak | Memory leaks and LMK kills, thermal throttling over time, GPU driver hangs under long load, late-game frame-time collapse, rare crashes | UI and input bugs | Device time only (hours), cheap per bug | High overnight. One long 8v8 soak per candidate build. |
| (e) Monkey/fuzz | Lifecycle and input-handling crashes, ANRs, odd orientation and IME states in the Android wrapper | Game-logic depth; random taps rarely get far into a match | Very low | Medium. A short burst on the wrapper/launcher UI per build. |
| (f) Human expert pass on the target phone | Feel, readability, control ergonomics, "is this shippable", device-specific issues on the real Fold7 | Rare crashes, long-run leaks | Owner's scarce time | Essential. Final go/no-go on the release candidate. |

- The cheapest, highest-yield oracle for this engine is determinism. Recoil already records demos and is lockstep. The upstream engine needs hardware-specific workarounds for identical results and is officially x86-64 only. So "replay a fixed demo on the phone build, compare sync checksums or end state with the x86 reference" is the strongest single check that the ARM/proot build is online-safe. Riot and Factorio both found divergence bugs this way that play could not reproduce.
- Expect on-device touch tests to be flakier than Google's 1.5% per run, because loading times and thermal state vary. Each scripted test needs a retry-once policy and a quarantine list. Otherwise agents will waste device time chasing noise.
- Monkey is weak at reaching deep game states but cheap at shaking the Android wrapper (launcher, permission dialogs, back button, rotation, app switching). Those are exactly the layers the engine's own tests cannot reach.

### Gaps
- No public numbers compare bug yield per hour across these methods in the same game. All agent yield figures come from seeded-bug or small studies.
- No source covered LLM agent playtesting of an RTS or of a touch-driven native port. Latency and cost per action for touch-driven agents went unreported in TITAN.
- Sea of Thieves test types and counts sit in the GDC Vault video or slides, which were not accessible.
- I did not verify the per-tool coverage table in Choudhary et al. My recollection that Monkey was competitive with or better than the research tools is unverified and should not be cited.

## Q2. How to harden against crashes, ANRs, GPU-driver faults, LMK kills and thermal throttling, and what telemetry works without a backend?

### Takeaway
For a sideloaded APK, the platform already keeps a free, backend-less record of how the app died: ApplicationExitInfo (Android 11+, with native tombstones from Android 12+). It is read on the next launch, together with a small app-written state summary. Combine that with the engine's own infolog/crash backtrace, rolling local logs and a "Send logs" share button. GPU hangs need their own detection (kernel and driver log lines, watchdog timeouts) and a safe-mode relaunch path. Hosted crash SDKs (Crashlytics NDK, Sentry) work without the Play Store but need a network backend and opt-in, so they are post-release.

### Cited Findings

**ANR**
- An ANR fires when input dispatch gets no response for 5 seconds, when `startForeground` is not called within 5 seconds of `startForegroundService`, when a broadcast receiver runs more than 10 seconds with an activity in the foreground, and when service or JobService callbacks overrun by "a few seconds".
- Common causes are I/O or long work on the main thread, synchronous binder calls, lock contention and deadlocks. Diagnose with `/data/anr/anr_*` traces (root), `adb bugreport`, StrictMode and ApplicationExitInfo.
- Background ANR dialogs only show with "Show all ANRs" turned on in Developer options.
- GameActivity "has reduced ANRs" in native game case studies.
- [Android Developers, ANRs](https://developer.android.com/topic/performance/vitals/anr)

**ApplicationExitInfo**
- The API is available on API 30+ through `getHistoricalProcessExitReasons()`. Reasons include REASON_CRASH_NATIVE, REASON_ANR, REASON_LOW_MEMORY, REASON_SIGNALED (status = signal number), REASON_EXCESSIVE_RESOURCE_USAGE, REASON_FREEZER (API 33), REASON_USER_REQUESTED (force stop or swipe from Recents) and REASON_INITIALIZATION_FAILURE. Newer constants REASON_MEMORY_LIMITER and REASON_ANOMALY are listed as added in "version 37.2". — [ApplicationExitInfo reference](https://developer.android.com/reference/android/app/ApplicationExitInfo)
- `getTraceInputStream()` returns ANR traces. From API 31 it also returns native-crash tombstones as protobufs (tombstone.proto). These sit in a global circular buffer and can be overwritten by other apps' crashes, so the call may return null. — [ApplicationExitInfo reference](https://developer.android.com/reference/android/app/ApplicationExitInfo); [NDK Debug native crashes](https://developer.android.com/ndk/guides/debug)
- `ActivityManager.setProcessStateSummary(byte[])` stores app-defined state that comes back through `getProcessStateSummary()` after death.
- `getPss()` and `getRss()` are the last sampled memory figures, not the exact values at death, and can be 0.
- Not every device reports REASON_LOW_MEMORY. Without that support, an LMK kill shows as REASON_SIGNALED with SIGKILL. Check `isLowMemoryKillReportSupported()`.
- [ApplicationExitInfo reference](https://developer.android.com/reference/android/app/ApplicationExitInfo)
- A single user report (Meta Quest 2, Android 14) says native SIGSEGV crashes were logged as SIGNALED with a null trace rather than CRASH_NATIVE. This is unconfirmed but shows that OEM builds vary. — [Meta community forum](https://communityforums.atmeta.com/questions-and-discussions-26/bug-native-crashes-not-reported-as-reason-crash-native-in-applicationexitinfo-179088)

**Crash SDKs**
- In-process native handlers capture only the crashing thread's stack (Sentry's inproc backend "doesn't stop any threads by design") and add about 1 MiB of unwinder per app.
- Tombstones read through ApplicationExitInfo give every thread's stack and registers, current memory maps and Java frames, with zero binary overhead. They arrive on the next app launch, need Android 12+ and lack in-app context at crash time.
- Sentry runs both side by side and merges duplicates within a 5-second window.
- [Sentry blog, Native crash postmortems via Android tombstones](https://blog.sentry.io/native-crash-postmortems-via-android-tombstones/)
- Sentry Native uses `inproc` by default on Android. Breakpad and Crashpad backends write minidumps. Whether Crashpad works on Android is unclear from the docs. — [Sentry backend tradeoffs](https://docs.sentry.io/platforms/native/advanced-usage/backend-tradeoffs); [sentry-native](https://github.com/getsentry/sentry-native)
- Version requirements conflict: Sentry's tombstone integration is cited at Android SDK 8.32.0 in one place and at sentry-android-core 8.30.0+ (`isTombstoneEnabled`) in the blog. Crashlytics is cited as collecting tombstones on Android 12+ from SDK 18.3.6. — [NDK Debug guide (search snippet)](https://developer.android.com/ndk/guides/debug); [Sentry blog](https://blog.sentry.io/native-crash-postmortems-via-android-tombstones/); [Firebase blog, Crashlytics NDK tombstones (Nov 2025)](https://firebase.blog/posts/2025/11/crashlytics-android-ndk-tombstones)

**Low memory**
- lmkd kills by oom_adj score. The foreground app has score 0 and is killed last.
- Since Android 10, lmkd triggers on PSI (time tasks stall waiting for memory) rather than vmpressure, which gave many false positives. Properties such as `ro.lmk.psi_complete_stall_ms` (default 100 ms) and `ro.lmk.kill_heaviest_task` tune it.
- [AOSP lmkd](https://source.android.com/docs/core/perf/lmkd); [kswapd and lmkd interaction](https://developer.android.com/topic/performance/memory/guide/kswapd-lmkd-interaction)

**Thermal**
- The ADPF Thermal API's `getThermalHeadroom()` predicts headroom before THERMAL_STATUS_SEVERE: 0.0 means no throttling, 1.0 means severe.
- Guidance is to poll it no more than about once per 10 seconds, from one thread. A NaN reading means it is unsupported.
- The Java API arrived in Android 11 (API 30), the NDK API in Android 12 (API 31), and threshold queries in Android 15.
- [Android ADPF Thermal API](https://developer.android.com/games/optimize/adpf/thermal)

**GPU faults (Adreno, Turnip/freedreno)**
- Mesa's debugging guide first sorts problems into a GPU memory-access fault, a recoverable hang, an unrecoverable hang or a misrendering. It recommends capturing the raw submissions that reproduce a hang so they can be resubmitted, with Turnip/freedreno instructions. — [Mesa: Debugging GPU hangs, faults and misrenderings](https://docs.mesa3d.org/graphics-debugging/debugging-misrenderings-crashes.html)
- A real KGSL report on an Adreno 640 shows the log signature: a "GPU hang detected" kernel line followed by "gpu fault" and "gpu skipcmd", then Turnip aborting on an assertion in `kgsl_syncobj_wait`. In other words, a GPU hang under Turnip+KGSL can become a userspace abort (crash) rather than a freeze. — [Mesa issue 11204](https://gitlab.freedesktop.org/mesa/mesa/-/issues/11204)
- Igalia (Turnip developers) built tools to decompile, edit and replay Adreno command streams for driver debugging, and published guides on debugging unrecoverable hangs. — [Igalia: command stream editing](https://blogs.igalia.com/dpiliaiev/debugging-by-editing-gpu-packets/); [Igalia: Debugging unrecoverable GPU hangs](https://blogs.igalia.com/dpiliaiev/debugging-unrecoverable-hangs/); [XDC 2023 slides](https://indico.freedesktop.org/event/4/contributions/177/attachments/125/185/xdc-2023-danylo-piliaiev-debugging-gpu-faults.pdf)
- On the kernel side, recovery that fails to retire the faulting submit can loop forever (hang, recover, re-execute). Mesa's own CI detects "Detected GPU hang, restarting run" and retries. — [msm/adreno recovery patch review (2026)](https://lore.gitlab.freedesktop.org/drm-ai-reviews/20260308-adreno-ringbuffer-drain-timeout-recovery-v1-1-985a33faf108%40postmarketos.org/t); [Mesa CI commit](https://lists.freedesktop.org/archives/mesa-commit/2021-December/126819.html)

### Inferences
- **The proot caveat (important, verify on device):** Android tombstones come from bionic's debuggerd crash handler, which the bionic dynamic linker installs in each process. The engine runs as glibc binaries under proot, so its crashes probably will not produce Android tombstones or REASON_CRASH_NATIVE for the app. Likely outcomes are that the guest process dies while the app process survives, or that the app sees SIGNALED or EXIT_SELF. So:
  1. Recoil's own crash handler output (infolog.txt with backtrace) is the primary native crash record and must survive in the app's storage.
  2. The Android-side launcher should `waitpid` the proot child and log exit code or signal, wall-clock time, last frame number, map, renderer/driver settings and battery temperature.
  3. Use ApplicationExitInfo for the Android wrapper process: X server, input, lifecycle, LMK and ANR.
- **No-backend telemetry that fits a sideloaded build (pre-release):**
  1. A rolling local log directory with the last N sessions: the engine's infolog, launcher log, a dmesg/logcat excerpt where readable, and an ApplicationExitInfo dump on every start.
  2. `setProcessStateSummary` updated every few seconds with a compact "where am I" record (screen, map, game frame, unit count, settings hash) so even an LMK kill says what was happening.
  3. A "Send logs" button that zips the last session and opens the Android share sheet. The user picks the channel, so there is no backend and no consent issue.
  4. A crash-on-last-run banner on the next launch offering to send logs.
  - Hosted Crashlytics or Sentry is post-release and opt-in.
- **Safe-mode fallback:** if the last session ended abnormally (signal, GPU-hang log signature, or no clean-exit marker) twice in a row, offer a "safe graphics" relaunch: lowest preset, conservative Mesa/Zink settings, known-good driver path. This mirrors Mesa CI's own "detect hang, restart" approach.
- **Watchdogs:** add an engine-side frame-progress heartbeat file or socket. If the sim or render thread stops advancing for N seconds while the app is in the foreground, the launcher records a "hang" event with timestamps and log excerpts before the system kills anything. The Android UI thread must never block on the X server, proot or file extraction (5-second input ANR rule). Move first-run rootfs extraction and any synchronous IPC off the main thread.
- **Memory:** on 8 GB phones the game is the foreground process (score 0), so it dies only under real pressure. The PSI trigger means a burst of allocations during map load is the dangerous moment. That fits a "free memory before load" approach. Record PSS/RSS from ApplicationExitInfo and the engine's own memory counters in soak runs.
- **Thermal:** the guest engine cannot call ADPF directly. The Android wrapper can poll `getThermalHeadroom` every 10 seconds or more and pass the value into the guest (file or socket) for logging and for the existing heat-capping logic.
- **What the project already has** (from the repo's CLAUDE.md; the report should build on these, not propose them as new):
  - `files/logs/launcher.log` collects all child-process output, plus `infolog.txt`, `Get Logs.bat` and the copy of infolog into logs/ on quit;
  - `PerfLog` writes `[perf]` lines once a minute (thermal status, GPU/CPU clocks, memory including the GPU driver's);
  - `DriverWatch` closes the game on a GPU driver fault, with `tools/driverwatch-phone-test.ps1` and `tools/firstdraw-phone-test.ps1` to hunt it;
  - `Updater` rolls back an engine/game/lobby set that fails fast on its first start;
  - `phone-memory.ps1` records whether a skirmish was killed;
  - a cross-session bench lock (`phone-bench.lock`) and the devphone lock;
  - about 25 scripted on-device tests (`tools/*-phone-test.ps1`).
  - The dev phone (S23 Ultra, 8 GB) completes only about 2 in 3 five-minute skirmishes in low-memory mode, so LMK kills are a live risk that soak runs must classify rather than treat as flakes.
  - Gaps against the research above: reading ApplicationExitInfo and `setProcessStateSummary` on the next start, a player-facing "Send logs" share zip, and a "crashed last time, try safe graphics" offer.

### Gaps
- No source confirmed how Android reports deaths of glibc processes under proot (tombstone or not). This needs a deliberate crash test on the dev phone.
- I found no Qualcomm developer doc on KGSL fault reporting to apps, or on whether userspace can read GPU fault events without root.
- No public data on LMK thresholds for specific Samsung 8/12 GB devices.

## Q3. How to prioritise in the last days before release and the weeks after

### Takeaway
Freeze features now. Triage every open item on severity (technical impact) and frequency/reach as separate axes. Only "unplayable with no workaround" problems (crash, hang, progression or launch blocker, online desync) block release. Gate the release candidate on a fixed smoke checklist plus an overnight soak and the owner's own pass. Ship first to a small trusted ring with a published known-issues list, then watch escapes.

### Cited Findings
- Severity (objective technical impact) and priority (business urgency) are separate axes. A debug-menu crash can be high severity and low priority, while a store-page typo can be the reverse. Priority is usually the producer's call, not QA's. — [Modern Game Testing (Packt), Severity versus priority](https://subscription.packtpub.com/book/game-development/9781803244402/10/ch10lvl1sec49/severity-versus-priority)
- One game-QA guide defines P0 as a bug that "makes the game unplayable for any player who encounters it" with no workaround, and says P0 is the only level that should halt a release. — [Bugnet, Bug severity classification for game developers](https://bugnet.io/blog/bug-severity-classification-for-game-developers)
- Crashes and progression blockers get the highest severity. A first-level QA triage filters out release blockers (P0) so they are acted on at once. — [Game Developer, How to report bugs](https://gamedeveloper.com/design/how-to-report-bugs); [HacknPlan, The bug triage process](https://hacknplan.com/blog/the-bug-triage-process)
- Bug-escape rate (bugs found after release divided by total bugs) is a standard QA metric. Blocker or critical escapes point to a test-coverage gap. — [Bugnet, Bug reporting metrics](https://bugnet.io/blog/bug-reporting-metrics-every-game-studio-should-track)
- Late in Anthropic's parallel-agent compiler project, "new features and bugfixes frequently broke existing functionality". The fix was CI with stricter enforcement so new commits could not break existing tests. — [Anthropic, Building a C compiler with parallel Claudes](https://www.anthropic.com/engineering/building-c-compiler)
- Riot's replays expire with the patch, so regression scenarios must be re-recorded for each engine version. — [Riot, Determinism: Fixing Divergences](https://technology.riotgames.com/node/84)

### Inferences
- **Release-blocker definition (proposed):**
  1. A crash or hang on launch, in the lobby, at match start or within a normal skirmish on either target phone.
  2. Any online desync or sim difference from the matching x86 engine version.
  3. Loss of a core control (unit select, move/attack, build, camera) on touch or pad.
  4. An unrecoverable state (stuck black screen, cannot exit, cannot get back to the menu).
  5. Data loss of settings or replays.
  - Everything else goes on the known-issues list or post-release.
- **Scoring for the rest:** severity (1-5) x frequency (always / often / rare) x reach (both phones vs one, all modes vs one mode). Fix the top items only if the fix is small and lands with a test. In the last days, a risky fix to a non-blocker is worse than the bug.
- **Feature freeze and stabilisation, from now:** no new features, and no "while I'm here" refactors by agents. Every change needs a linked bug ID and a test or a recorded on-device check. Any change touching the sim, net or engine must pass the determinism replay gate.
- **Release-candidate gate (smoke checklist, ~30-60 minutes on the dev phone, then the owner's pass on the Fold7):**
  1. Fresh install and first-run extraction.
  2. Upgrade install over the previous build with settings kept.
  3. Launch to menu.
  4. Offline skirmish start and 5 minutes of play with touch and pad.
  5. Pause, background, resume, fold/unfold, rotation.
  6. Save or replay where supported.
  7. Online lobby reachability. Follow the project rule that tests do not log in.
  8. Exit and relaunch.
  9. "Send logs" produces a zip.
  10. An overnight AI-vs-AI late-game soak on the RC with no crash, no LMK kill and frame time within target.
- **Staged rollout without a store:** first the owner's phone, then 2-5 trusted testers, then the public link, with 24-48 hours between rings if possible. Keep the previous APK downloadable as a rollback. Ship a KNOWN_ISSUES list with each build, because it turns duplicate reports into confirmations and sets expectations.
- **Weeks after:** track escapes by method ("which test should have caught this?") and add a scenario, replay or scripted test for each escaped blocker. Re-baseline replays on each engine bump. Only then reopen feature work.

### Gaps
- I could not retrieve Unity's "User Pain" triage formula (the blog URL returned 404). No source gave quantitative crash-rate thresholds for indie game releases. Android vitals thresholds exist for Play apps but were not fetched and do not apply to sideloaded builds.
- No sourced evidence on staged-rollout timing for private, sideloaded game betas.

## Q4. How to organise several parallel AI agent sessions on one codebase and one test device

### Takeaway
What works in documented practice:
- an isolated checkout per agent (worktree or fresh clone);
- explicit task claiming through lock files in the repo;
- a shared, strict, machine-readable test oracle that every agent must pass before pushing;
- terse test output written for agents;
- separate roles (fixer, tester, reviewer with fresh context);
- the human as the bottleneck on review, so fewer, better-specified tasks.

For the single phone, the same lock-file pattern applies as an exclusive device lease with batching. Evidence that parallel agents raise real productivity is mixed (METR's RCT found a 19% slowdown with early-2025 tools), so measure throughput rather than trusting the feeling.

### Cited Findings
- Anthropic's C compiler project (Nicholas Carlini):
  - **Scale:** 16 Claude agents and nearly 2,000 sessions over about two weeks, roughly $20k in API cost (2B input and 140M output tokens), producing a 100k-line Rust compiler that builds Linux 6.9 and passes about 99% of most compiler test suites.
  - **Organisation:** each agent ran in its own Docker container with its own clone and pushed to a shared bare repo. Agents claimed tasks by writing `current_tasks/<task>.txt`, so git sync forced collisions to pick another task. They pulled, merged, pushed and removed the lock. Merge conflicts were frequent and resolved by the agents. There was no orchestrator and no communication beyond git.
  - [Anthropic Engineering](https://www.anthropic.com/engineering/building-c-compiler)
- The same project on test harness design for agents:
  - print only a few lines and put details in log files;
  - errors go on one line starting with "ERROR" so grep finds them;
  - precompute summary statistics;
  - offer a `--fast` mode that runs a deterministic per-agent random 1% or 10% sample, so all agents together cover everything while each still catches regressions;
  - agents keep READMEs and progress files because each starts with no context;
  - specialised agents handled deduplication, performance, code quality and design critique, and documentation;
  - a known-good oracle (GCC) plus delta debugging split one shared failing build into parallel independent tasks;
  - late in the project, CI enforcement was needed because agents broke existing features.
  - [Anthropic Engineering](https://www.anthropic.com/engineering/building-c-compiler)
- Claude Code docs:
  - give each parallel session its own checkout (`claude -w` worktree); `.worktreeinclude` copies needed gitignored files;
  - "A second session is also the easiest independent reviewer you can get" (review without having watched the writing);
  - "Give Claude something it can run that comes back pass or fail";
  - ask for evidence (the command and its output, or a screenshot) because "All tests pass" alone "tells you very little";
  - "A reviewer that's asked to find problems will always find *something*", so review against a spec and skip style.
  - [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- Simon Willison (Oct 2025):
  - runs several agents in separate fresh checkouts (not worktrees);
  - parallel work suits research, explaining code, low-stakes maintenance and carefully specified tasks;
  - the review bottleneck means "only one significant change at a time" lands;
  - specs make review cheaper.
  - Cited patterns: Jesse Vincent's architect agent plans while fresh instances review and implement, and Josh Bleecher Snyder's "scout" runs a throwaway attempt to learn where the hard parts are.
  - [Simon Willison, Embracing the parallel coding agent lifestyle](https://simonwillison.net/2025/Oct/5/parallel-coding-agents/)
- METR RCT (July 2025): 16 experienced OSS developers worked 246 tasks in their own mature repos and were 19% slower with AI tools (mainly Cursor with Claude 3.5/3.7). They had expected a 24% speedup and still believed afterwards they had been 20% faster. METR calls it a snapshot of early-2025 tools. — [METR](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/); [arXiv 2507.09089](https://arxiv.org/pdf/2507.09089)
- Community guidance recommends 3-5 parallel worktrees, one task per worktree, tasks that do not touch the same files, and a reviewer that never sees the writer's chat. These are community sources, not official. — [Claude support, power user article](https://support.claude.com/en/articles/14554000-claude-code-power-user-); [Towards Data Science, worktrees](https://towardsdatascience.com/ai-agents-need-their-own-desk-and-git-worktrees-give-it-one/)

### Inferences
- **Device as a leased resource:** treat the dev phone like the compiler project's `current_tasks/` lock. Use one lease file or lock script with owner, purpose, start time, expected duration and heartbeat, and only one holder at a time. Release automatically if the heartbeat stops (crashed agent). The existing "devphone-lock take / free right after" rule matches this. Add a visible queue and a hard maximum lease (for example 20-30 minutes for interactive checks), with soaks only in a scheduled overnight slot.
- **Batch device work:** agents should not each install and boot for one check. Use a "build train": merge green fixes into one candidate every few hours, install once, run the scripted smoke suite plus each agent's targeted check in one leased block, then post per-test pass/fail lines (ERROR-on-one-line format) back to a shared results file. Keep agent-specific exploratory checks to short slots between trains.
- **Keep the phone busy productively when no agent holds it:** a nightly or idle queue of (1) the determinism replay set, (2) a long AI-vs-AI late-game soak with memory, thermal and frame-time logging, and (3) a short monkey burst on the Android wrapper UI. Results go into a morning summary that fixer agents pick up.
- **Role split for the release window:**
  - one fixer per independent area (renderer/driver, input/controls, Android wrapper and lifecycle, engine/sim), each in its own worktree or clone;
  - one test-owner agent that holds the device lease, maintains the smoke suite and runs trains;
  - one reviewer with fresh context that checks each diff against the bug's acceptance criterion, read-only;
  - the owner as release manager deciding blockers and doing the final pass on his own phone.
  - Avoid two agents in the same subsystem at once, because the merge cost erases the gain.
- **Output hygiene for on-device tests:** a test-runner wrapper that prints a few summary lines, writes logcat, infolog and screenshots to a per-run folder, and gives every failure a single grep-able line. This saves the agents' context and makes results comparable across sessions.
- **Because of METR's perception gap,** track simple numbers during the release window: blockers closed per day, regressions introduced per day, device-hours used per bug found. Add parallel sessions only while regressions stay near zero.

### Gaps
- I found no published account of multiple AI agents sharing one physical test device. The lease and batching design above is extrapolated from lock-file and CI patterns.
- No controlled study measured the multi-agent productivity of Claude Code or Codex on game or native code; the C compiler project is a single showcase with an unusually strong test oracle.

## Q5. How to make an agent playtest worth keeping

### Takeaway
If agent playtests stay, turn them into guided "feature tours" from scripted starting states. Give the agent a compact text state rather than raw screenshots, a short list of allowed actions, explicit oracles (crash, stuck, timeout, wrong state), and a reflection step when progress stalls. Make every run emit a reproducible bug report: touch log, screenshots, state summary and build ID. Tight state abstraction, action shortlists and reflection drove TITAN's gains over ReAct-style agents. Latency and visual misperception sink screenshot-only agents in real-time play.

### Cited Findings
- TITAN's gains came from:
  - state abstraction into a few discretised factors;
  - narrowing to about 5 candidate actions with rules and documentation;
  - validating actions before execution;
  - reflection after 20 no-progress actions (removing reflection hurt most in ablation);
  - a persistent coverage map across runs that deprioritises repeatedly failing actions.
  - Its bug reports are structured (goal, attempted actions, reasoning, evidence), and its oracles are crash, task-status and execution-time monitors. About 30% of reports were false alarms, mostly from imperfect state abstraction.
  - [arXiv 2509.22170](https://arxiv.org/html/2509.22170)
- Screenshot-only agents in real-time games fail on latency, and pausing the game while the model thinks roughly tripled completion (0.48% to 1.6%) for the best model. Common failures are acting at the wrong screen position, loops, memory overwrite and hallucinated progress. — [VideoGameBench (arXiv 2505.18134)](https://arxiv.org/pdf/2505.18134)
- Curiosity or exploration agents are valued for coverage maps and visualisation of where they went, and were developers' most-wanted research approach. — [EA SEED](https://www.ea.com/seed/news/cog2021-curiosity-driven-rl-agents); [Politowski et al. 2022](https://ar5iv.labs.arxiv.org/html/2202.12777)
- Developers do not want agents re-finding known bugs. — [Politowski et al. 2022](https://ar5iv.labs.arxiv.org/html/2202.12777)
- Recoil desync bugs were easy to reproduce with cheat setups (give all units), which shows that scripted state setup speeds reproduction. — [Mantis 2591](https://springrts.com/mantis/view.php?id=2591)

### Inferences
- **Feature tours, not matches:** each run gets one named target, for example "open the build menu by touch, place 3 different structures, cancel one, queue a factory, use the radial", "pad: select group, attack-move, set target", or "pause and resume, background, fold and unfold mid-match". Success criteria come from the engine's state, not from the LLM's judgement.
- **Scripted state setup:** start each tour from a known state, such as a saved scenario or start script, a cheat-enabled offline skirmish, or a replay seeked to frame X. Recoil's start scripts, cheats and demos make this cheap. The agent then needs seconds of play to reach the interesting moment instead of minutes.
- **Pause or slow the game while the agent decides** (as in VideoGameBench Lite), or limit the agent to non-time-critical UI and command flows. Time-critical behaviour belongs in scripted tests.
- **Give state as text:** export a compact JSON from a Lua widget or gadget, covering selected units, visible UI panels, last command result, frame number and FPS. Pass that plus at most an occasional screenshot. This addresses both the latency and the misperception failure modes.
- **Every agent run writes a bundle:**
  - build ID and APK hash;
  - start state;
  - a timestamped touch log replayable with adb;
  - screenshots at each decision;
  - the engine state JSON;
  - infolog and logcat excerpts;
  - the agent's own one-line verdict.
  - A failing bundle becomes a scripted regression test once confirmed, which turns agent exploration into suite growth. Re-run the touch log before filing, to filter out the roughly 30% false-alarm class.
- **Budget:** agent tours are the most device-expensive method per bug. In the release window, keep them to a few short tours on new or changed UI flows, and run them only in slots where the scripted suite and soaks are not using the device.

### Gaps
- No source measured touch-injection LLM playtesting on Android games specifically, or published cost per bug for LLM playtests.
- No evidence was found on replaying touch logs for native games under X servers or proot (timing sensitivity). Test it on the dev phone.
