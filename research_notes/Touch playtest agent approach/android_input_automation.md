# Driving and observing an Android game from a laptop for an LLM agent (late 2026)

Scope: fast, cheap and finger-faithful input + capture for Claude playing BAR Droid (OpenGL UI inside an embedded X server, no Android view hierarchy) on a Galaxy S23 Ultra over USB/Wi-Fi adb, no root. Researched 2026-11-21. Current baseline being replaced: `adb shell input tap/swipe` per gesture (~100-300 ms each as measured locally), `screencap -p` + `adb pull` (~1-2 s per 1080x2316 PNG), uinput virtual touchscreen for multi-touch.

## 1. Faster and more faithful input injection

### Takeaway
The per-gesture cost is mostly the adb round trip plus process start, not the injection itself: a warm, persistent channel (a long-lived `adb shell` pipe into an on-device process, or a socket via `adb forward`) brings commands down to single-digit milliseconds. For faithfulness, `input tap` is the least finger-like option (DOWN and UP with the same timestamp, pressure 1.0, size 1.0), while a uinput virtual touchscreen fed by a persistent pipe with on-device scheduled delays is both the fastest to drive precisely and the closest to a real finger, because its events go through the same reader pipeline as hardware.

### Cited Findings
**Latency of the options**
- `adb shell input tap X Y` measured at 40-80 ms on "a recent Pixel" (coordinates only); uiautomator2 click by text 30-100 ms; Appium find+click 100-500 ms. Same post: an on-device daemon reached by a warm socket answered in 2-3 ms per round trip, with 2-7 ms for a full tap-by-label; `getprop` via adb took 46 ms vs 1.6 ms through the daemon. No device model, Android version or sample count given (published 2026-05-23) — [handsets.dev, "Tapping Android in 5 ms"](https://handsets.dev/blog/tapping-android-in-5ms-vs-appium-uiautomator2/)
- That daemon's design: a small jar pushed to the device and run under `app_process` with shell UID, kept alive between calls, with a length-prefixed binary protocol over `adb forward`; first call ~150 ms while it starts — [handsets.dev](https://handsets.dev/blog/tapping-android-in-5ms-vs-appium-uiautomator2/)
- High-level automation frameworks add 600-1400 ms per action in AndroidWorld-style agents, which cost the single-agent baseline 5 of its 42 failures (fewer retries before timeout) — [Minitap, arXiv 2602.07787](https://arxiv.org/html/2602.07787v1)
- Older measurement (Galaxy Note 4): ~1160 ms per `input tap` vs ~860 ms per `sendevent` tap; a `sendevent` tap needs about a dozen separate commands, and per-call `adb shell` overhead dominates; batching lines in one shell call is the suggested fix — [Habr article](https://habr.com/ru/post/712374) (forum/blog-grade evidence, old device)
- `input` (Java framework path) vs `sendevent` (native toolbox writing to /dev/input nodes) explanation; writing a whole event stream at once with `dd` is too fast for the touchscreen — summarised from [StackOverflow archive "adb input tap is slow"](https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/68788995/adb-input-tap-is-slow) and [dev.to, tapping from the Linux layer](https://dev.to/xarantolus/how-to-tap-the-android-screen-from-the-underlying-linux-system-34jf?comments_sort=oldest)

**What `input` actually injects (AOSP InputShellCommand.java, HEAD)**
- Tap: DOWN and UP injected back to back with the same timestamp, no sleep (a 0 ms touch) — [AOSP InputShellCommand.java](https://android.googlesource.com/platform/frameworks/base/+/HEAD/services/core/java/com/android/server/input/InputShellCommand.java)
- Pressure hard-coded 1.0 for DOWN/MOVE and 0.0 for UP; size 1.0; tool type FINGER for touchscreen source; deviceId = first input device that supports the source (else 0); source defaults to touchscreen — [AOSP InputShellCommand.java](https://android.googlesource.com/platform/frameworks/base/+/HEAD/services/core/java/com/android/server/input/InputShellCommand.java)
- Swipe: default 300 ms, MOVE events at up to 120 Hz (~8.3 ms), linear interpolation, then UP — [AOSP InputShellCommand.java](https://android.googlesource.com/platform/frameworks/base/+/HEAD/services/core/java/com/android/server/input/InputShellCommand.java)
- Motion events are always injected with `INJECT_INPUT_EVENT_MODE_WAIT_FOR_FINISH` (the call blocks until dispatch finishes) — [AOSP InputShellCommand.java](https://android.googlesource.com/platform/frameworks/base/+/HEAD/services/core/java/com/android/server/input/InputShellCommand.java)
- `input motionevent DOWN|MOVE|UP|CANCEL x y` exists, so a held press can be built from separate DOWN and UP calls — [AOSP InputShellCommand.java](https://android.googlesource.com/platform/frameworks/base/+/HEAD/services/core/java/com/android/server/input/InputShellCommand.java)

**Android's `uinput` shell tool (virtual devices from stdin)**
- `uinput -` reads commands from stdin until EOF (recommended, "interactively or when driven by another program"); `uinput <file>` also works; input format auto-detected: evemu recording format (recommended, one device per recording) or lenient JSON — [AOSP cmds/uinput README](https://android.googlesource.com/platform/frameworks/base/+/HEAD/cmds/uinput/README.md)
- Commands: `register` (id, name, vid, pid, bus, configuration with UI_SET_EVBIT first, abs_info), `inject` (type/code/value triples), `delay` (ms), `updateTimeBase`, `sync` (returns a sync result). Delays are scheduled relative to a time base, so a 500 ms then 10 ms delay fires at base+510 ms and scheduling drift does not accumulate; send `updateTimeBase` after an idle gap — [AOSP cmds/uinput README](https://android.googlesource.com/platform/frameworks/base/+/HEAD/cmds/uinput/README.md)
- Registration is asynchronous (commands sent before the device is ready are dropped); the device is removed at EOF, no explicit unregister — [AOSP cmds/uinput README](https://android.googlesource.com/platform/frameworks/base/+/HEAD/cmds/uinput/README.md)

**scrcpy control channel**
- scrcpy-server runs via `app_process` from `/data/local/tmp`, opens up to three sockets (video, audio, control) over `adb reverse` (default) or `adb forward`; control messages are handled on a separate Controller thread and injected through the hidden `InputManager.injectInputEvent()` via reflection; the server version must match the client exactly; the only protocol documentation is the unit tests — [scrcpy doc/develop.md](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md)
- INJECT_TOUCH_EVENT is described as a fixed 32-byte message with type, action, pointer id (plus position, screen size, pressure, buttons); layout has changed across releases — [mcp-scrcpy-vision research cache, 2025-12-22](https://glama.ai/mcp/servers/@invidtiv/mcp-scrcpy-vision/blob/a954edbbee018503d6b036d80c9f4ce8a0631980/.research-cache/scrcpy-control-protocol-2025-12-22.md) (secondary source; verify against the server version used)
- Python clients exist (`py-scrcpy-client` fork, `pyscrcpy`) exposing `control.touch(x, y, action)` — [haskely/py-scrcpy-client](https://github.com/haskely/py-scrcpy-client), [pyscrcpy](https://github.com/yixinNB/pyscrcpy); a game bot (Arknights Mower) drives touch through the scrcpy control socket behind a lock and implements swipes as a timed move loop — [arknights-mower control.py](https://codeclimate.com/github/Konano/arknights-mower/arknights_mower/utils/device/scrcpy/control.py/source)
- scrcpy README (v5.0.1 shown) lists HID simulation for keyboard (`--keyboard=uhid`), gamepad (`--gamepad=uhid`) and mouse, and `--otg` control without mirroring; no multi-touch simulation option is documented on that page — [Genymobile/scrcpy README](https://github.com/Genymobile/scrcpy)

**Accessibility-service gestures**
- `GestureDescription` limits: up to `getMaxStrokeCount()` paths and `getMaxGestureDuration()` total; a framework listing gives 10 strokes and 60000 ms — [Android GestureDescription reference](https://developer.android.com/reference/android/accessibilityservice/GestureDescription); values from [e/OS framework commit](https://gitlab.e.foundation/e/os/android_frameworks_base/-/commit/a6b64f5099b7be6e8384958d8bcddb97bb06ec93)
- Gestures are turned into MotionEvents by a generator with a sampling interval (100 ms seen at one call site; implementation detail) — [e/OS framework commit](https://gitlab.e.foundation/e/os/android_frameworks_base/-/commit/a6b64f5099b7be6e8384958d8bcddb97bb06ec93)
- No published dispatch-latency figures found for `dispatchGesture` — [search summary of the above]

**Injected vs real touch**
- The dispatcher marks accessibility-originated events (`FLAG_IS_ACCESSIBILITY_EVENT` on key events) so apps can tell them from hardware events — [e/OS mirror of AOSP frameworks/native commit](https://gitlab.e.foundation/e/os/android_frameworks_native/-/commit/61cfde719b9dac7d718a0af72c3a8748d0f7ffe7)
- InputDispatcher cancels an injected touch gesture when another MotionEvent arrives on the same display from a different device or source (for example a real finger) — [AOSP InputDispatcher tests/commit (e/OS mirror)](https://gitlab.e.foundation/e/os/android_frameworks_native/-/commit/f00a4ec687e2bf9110106238c7738927fc3e87d7)
- An AOSP change that flagged unmodified injected events was reverted because it caused input lag with accessibility filters active — [e/OS mirror of AOSP commit](https://gitlab.e.foundation/e/os/android_frameworks_base/-/commit/0c25ba71ed2270681ae337a4aca151f1c3aaa0ad)
- System-level injection is treated as real hardware input and is hard for the app layer to detect — [DEV Community, monitoring AI agents on phones](https://dev.to/observabilityguy/when-ai-agents-take-over-phones-how-to-monitor-on-mobile-devices-3p7p) (blog-grade)

### Inferences
- The locally measured 100-300 ms per `adb shell input` call versus 40-80 ms on a Pixel suggests most of the cost is the per-call adb shell session setup (and Wi-Fi adb), not `input` itself. A single persistent `adb shell` (or `adb exec-out`) whose stdin stays open removes that setup from every gesture.
- Best fit for BAR Droid: keep the existing uinput virtual touchscreen, but drive it through one long-lived pipe (Android's own `uinput -` tool with evemu or JSON commands, or the current uinput helper kept running) and let on-device `delay` commands set touch durations and move spacing. Then a 120 ms tap, a 16 ms-spaced drag or a two-finger pinch is timed on the phone, independent of adb jitter. Each agent action becomes one write of a few hundred bytes.
- Faithfulness ranking for touch-UX findings (most to least finger-like): (1) uinput virtual touchscreen with realistic duration, slop and multi-pointer slots, since it enters through InputReader like hardware and the app sees TOOL_TYPE_FINGER with axis-derived pressure and size; (2) InputManager injection with realistic timing (scrcpy control socket, an app_process daemon, or `input motionevent` DOWN ... UP); (3) `input tap` (0 ms, pressure 1.0, size 1.0, no jitter), which can pass a button that a real finger misses, or the reverse if the dock has a minimum press time; (4) accessibility `dispatchGesture` (sampled, max 10 strokes, flagged on the accessibility path; needs an accessibility service installed).
- Because BAR Droid owns the MotionEvent to X translation, the team can check exactly which fields its touch code reads (deviceId, tool type, pressure, size, event timing, touch slop) and make sure the agent's synthetic events exercise the same branches a finger does. Logging those fields for one real tap and one synthetic tap and diffing them is a cheap check.
- The scrcpy route is attractive only if the video stream is adopted too (one server gives video plus touch). On its own, a uinput pipe is simpler, works over Wi-Fi adb, and avoids the scrcpy version-lock.
- Real-finger cancellation of injected gestures means a human touch on the dev phone during an agent move would cancel InputManager-injected gestures; uinput gestures would instead combine with it as a second device.

### Gaps
- No published measurement found for a persistent `adb shell` pipe (write a line, event reaches the app) on a Samsung phone over USB vs Wi-Fi; this should be measured locally (for example, timestamp the write on the laptop and the MotionEvent in BAR Droid's log, then align clocks).
- Could not confirm from documentation whether the stock `uinput` command accepts ABS_MT_* multi-touch registration on Samsung One UI user builds or which permission it needs; the existing BAR Droid uinput touchscreen already proves that some path works on this phone.
- No measured latency for scrcpy control-socket touch injection was found.
- No source found on how scrcpy simulates two-finger pinch (it is commonly done with Ctrl+drag in the desktop client, but this was not verified in this pass).
- No measured dispatch latency found for AccessibilityService `dispatchGesture`.

## 2. Faster screen capture and cutting image tokens

### Takeaway
`screencap -p` is slow because of on-device PNG encoding (about 90% of its time in the one measured setup); raw `screencap` over `exec-out` or, better, an on-device JPEG encode at reduced size is 25-100x faster, and a scrcpy H.264 stream gives frames with a claimed 35-70 ms latency. On the token side, Claude Opus 5.5 charges ceil(w/28) x ceil(h/28) visual tokens, so a full 2316x1080 frame costs about 3,237 tokens, and a 768-px-long-edge frame or a 400x400 crop costs about 225-364.

### Cited Findings
**screencap measurements (Android 15 emulator, 1440x3120, 20 samples after 3 warm-ups, published 2026-05-22)**
- `adb exec-out screencap -p` (PNG) median 2122 ms (p10 661, p90 3007), 1973 KB; `adb exec-out screencap` (raw) median 675 ms (p10 664, p90 683), 17.5 MB — [handsets.dev, "Why adb screencap is slow"](https://handsets.dev/blog/category/performance/)
- On-device phases: capture + raw write 75 ms; capture + PNG encode 624 ms; `adb pull` raw 17.5 MB 60 ms; `adb pull` PNG 25 ms. PNG encoding is almost 90% of on-device time — [handsets.dev](https://handsets.dev/blog/category/performance/)
- On-device daemon capture: JPEG q80 full res 24 ms (138 KB); JPEG q80 at 768 px long edge 12 ms (22 KB); PNG full res through the daemon 584 ms; recommendation: JPEG for agent loops, PNG only for debugging, 768 px long edge default — [handsets.dev](https://handsets.dev/blog/category/performance/)
- The same author notes physical devices show less variance on the `exec-out` path (roughly 600-900 ms) but gives no physical-device table — [handsets.dev](https://handsets.dev/blog/category/performance/)
- Raw screencap output has no image header beyond its small dimension/format header, so the receiver must decode by width, height and pixel format — [codegenes.net guide](https://www.codegenes.net/blog/using-adb-to-capture-the-screen/); screencap source (`-p` PNG, raw default) — [AOSP screencap.cpp](https://android.googlesource.com/platform/frameworks/base/+/HEAD/cmds/screencap/screencap.cpp)

**scrcpy video stream**
- README claims: latency 35-70 ms, 30-120 fps depending on device, ~1 s to first image; `-m/--max-size` (e.g. `-m1024`) "may greatly improve performance"; `--max-fps`, `--video-codec=h265`, `-b` bitrate, `--record=file.mp4`, `--no-playback`, `--v4l2-sink` (Linux only) — [Genymobile/scrcpy README](https://github.com/Genymobile/scrcpy)
- Video is MediaCodec-encoded from a display Surface (H.264 default; H.265, AV1 listed), sent as a raw stream with a 12-byte header per packet (PTS, key-frame flag, size) plus a session packet with width/height that changes on rotation; frames are only produced when the surface changes; the desktop client shows frames as soon as possible without buffering; a standalone `raw_stream=true max_size=1920` example over a TCP forward is given — [scrcpy doc/develop.md](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md)
- The client renders the most recent decoded frame and drops older ones by default — [scrcpy fork README](https://github.com/Win7GM/scrcpy) (fork; upstream more authoritative)
- No independent glass-to-glass measurement of scrcpy was found; standard method is filming a clock on both screens, with precision limited by camera fps (about 33 ms at 30 fps) — [bloggeek glossary](https://bloggeek.me/webrtcglossary/glass-to-glass/), [RidgeRun latency wiki](https://developer.ridgerun.com/wiki/index.php/Jetson_TX2/NVIDIA_Jetson_TX1/TX2_Video_Latency)

**Other capture stacks**
- Airtest screenshot preference: custom > MINICAP > JAVACAP > ADBCAP; ADBCAP triggers a warning for very low efficiency; touch: MINITOUCH, then MAXTOUCH (used on Android 10+), then ADBTOUCH; manual selection discouraged since 1.1.2 — [Airtest android constants](https://airtest.readthedocs.io/en/latest/all_module/airtest.core.android.constant.html), [Airtest releases](https://www.Github.com/AirtestProject/Airtest/releases?page=2)

**Image token cost for Claude (current docs)**
- Visual tokens = ceil(width/28) x ceil(height/28) (28x28 px patches) — [Claude docs, Vision](https://platform.claude.com/docs/en/build-with-claude/vision)
- High-resolution tier (Claude 4.7 and later, including Opus 5.5): max long edge 2,576 px and max 4,784 visual tokens; standard tier: 1,568 px / 1,568 tokens; larger images are downscaled preserving aspect ratio — [Claude docs, Vision](https://platform.claude.com/docs/en/build-with-claude/vision)
- Coordinates come back relative to the image as processed after resizing; pre-resize and rescale yourself, or set `oversized_image: "error"`; computer-use tool_result screenshots over the limit are rejected rather than downscaled — [Claude docs, Vision](https://platform.claude.com/docs/en/build-with-claude/vision)
- Lossy JPEG/WebP cuts request size and latency, but heavy compression can hurt legibility, especially with repeated passes — [Claude docs, Vision](https://platform.claude.com/docs/en/build-with-claude/vision)
- Example price in the docs: Opus 5.5 at $4 per million input tokens, a 1000x1000 image is about $5.18 per thousand images — [Claude docs, Vision](https://platform.claude.com/docs/en/build-with-claude/vision)

### Inferences
- Token arithmetic with the documented formula (landscape S23 Ultra at FHD+): 2316x1080 full frame = 83 x 39 = 3,237 tokens; 1158x540 (half) = 42 x 20 = 840; 768x358 = 28 x 13 = 364; a 400x400 crop of the minimap or dock = 15 x 15 = 225; a 224x224 crop around a target = 64. Sizes that are multiples of 28 waste nothing (for example 1176x546 = 42 x 20 = 840 tokens; 784x364 = 28 x 13 = 364).
- A practical loop: a low-res whole-screen frame (about 768-1176 px long edge, JPEG q75-85) for "what is happening", plus on-demand full-resolution crops around the dock or a target before a precise tap. This mirrors the zoom-in grounding methods in section 4 and keeps most steps under ~1,000 image tokens.
- Raw `screencap` of 2316x1080 RGBA is ~10 MB per frame; over USB 3 that is fine, over Wi-Fi adb it will dominate. Encoding JPEG on the phone (a tiny app_process helper, or the scrcpy stream decoded on the laptop) is the way to make Wi-Fi capture fast.
- scrcpy frames come from a hardware encoder and arrive continuously, so the agent can grab the latest frame instantly instead of paying a capture per step, and the same stream can be recorded to MP4 for the UX log. The cost is extra encoder load on the phone; for 30 fps thermal work it is worth capping with `--max-fps` and `-m` and measuring the game's frame time with and without the stream.
- Decoding the stream on the laptop (for example PyAV/FFmpeg on the H.264 bytes) is cheap; the agent only needs a "latest frame" buffer.

### Gaps
- No measured screencap or scrcpy numbers for a Galaxy S23 Ultra or any Samsung device were found; the handsets.dev numbers are from an emulator.
- minicap status on Android 14-16 / One UI was not established (Airtest still lists it; current compatibility not verified).
- MediaProjection-based capture apps were not benchmarked in any source found; they would need a one-time user consent dialog per session.

## 3. Game-testing frameworks for GL-rendered UIs and coordinate stability

### Takeaway
Every framework that taps game UI reliably either instruments the engine to expose object positions (AltTester for Unity/Unreal, Airtest's Poco) or falls back to image templates/OCR on screenshots (Airtest). No SDK exists for the Recoil/Spring engine, but BAR Droid owns its touch dock, so exporting the dock's own button rectangles from the app is the equivalent of Poco/AltTester and gives exact, resolution-proof coordinates while input still goes through the touch layer.

### Cited Findings
- AltTester needs the app built with its SDK: the Unity SDK instruments the app to expose all objects in the Unity hierarchy; the Unreal plugin does the same for Unreal; a websocket client in the game talks to the AltTester Server in AltTester Desktop — [AltTester SDK overview](https://alttester.com/docs/sdk/pages/overview.html), [AltTester Unreal SDK overview](https://alttester.com/docs/unreal-sdk/latest/pages/overview.html)
- AltTester can read element properties including screen coordinates, find objects by hierarchy path (for example `//Canvas/MainMenu/PlayButton`), and find the object at given screen coordinates; the CLI requires an instrumented game — [AltTester CLI docs](https://alttester.com/docs/desktop/2.3.2/pages/alttester-cli.html), [AltTester commands](https://alttester.com/docs/sdk/pages/commands.html)
- Airtest supports image capture via MINICAP/JAVACAP/ADBCAP and touch via MINITOUCH/MAXTOUCH/ADBTOUCH, choosing automatically; MAXTOUCH is used on Android 10+ — [Airtest android constants](https://airtest.readthedocs.io/en/latest/all_module/airtest.core.android.constant.html), [Airtest android module](https://airtest.readthedocs.io/en/latest/all_module/airtest.core.android.android.html)
- Accessibility-based agent stacks state that apps without accessibility support, such as games and canvas UIs, "cannot be reliably automated" by their hierarchy-first approach — [Minitap, arXiv 2602.07787](https://arxiv.org/html/2602.07787v1)
- AppAgent v2 notes its parser-based element detection limits flexibility for non-standard components such as video players and games — [AppAgent v2, arXiv 2408.11824](https://arxiv.org/html/2408.11824v4)
- I found no documentation for a product named "GameDriver" in this pass — [search summary](https://alttester.com/docs/sdk/pages/overview.html)

### Inferences
- For BAR Droid the cheapest faithful "Poco" is a debug channel in the app that writes the dock's live layout (button id, label, screen-pixel rect, enabled/visible, current page) to a file or socket the laptop can read in one round trip. The agent then taps the rect's center (or a randomized point inside it) through uinput. That keeps grounding exact while still testing whether a finger-sized touch at that point works.
- For map gestures (units, buildings, terrain), there is no UI tree; options are (a) Lua widget/engine queries for unit screen positions via the existing game-widget path, (b) vision on screenshots with zoom-in crops. Engine-side positions should be logged, not used to bypass the touch path.
- Coordinate stability: always work in one canonical frame (device physical pixels for the current rotation, read once from `wm size`/session packet) and convert model coordinates back from the resized image size. Re-read the rotation/size when the scrcpy session packet or `wm size` changes (Fold-style devices change size when folded/unfolded).
- BAR Droid has two coordinate frames: the display (what `screencap`/scrcpy capture and what uinput/`input` touch) and the X screen the engine draws in, which the app caps below the display size (per project CLAUDE.md, at most 2100x900's pixels and 1080 lines, then upscaled through SGSR). Lua widgets (the dock, `bardroid_camctl.txt` rects) work in X-screen pixels, so exported rects must be converted to display pixels with the same scale and offset LorieView uses, or the agent's taps will drift. The dev phone runs Android 17 / One UI 9 (CLAUDE.local.md), newer than every source above, so the AOSP behaviours cited (HEAD sources) are the closest match.
- Image templates (Airtest style) are brittle across resolution/DPI and theme changes; with the dock layout exported, templates would only be needed for checking that a button visibly reacted.

### Gaps
- Airtest's `Template(record_pos, resolution)` behaviour for coordinate prediction and its recommended thresholds were not re-verified in this pass.
- No GL/game-specific automation framework for Spring/Recoil was found.
- GameDriver (if it is a separate commercial product) was not located; its docs were not reviewed.

## 4. Mobile GUI agents: latency, grounding, success rates, lessons

### Takeaway
Benchmark-leading Android agents reach 80-100% on AndroidWorld, but they ground taps through the accessibility hierarchy and verify after each action; their own papers say games and canvas UIs are out of reach for that approach. Pure-vision grounding is much weaker on small targets in high-resolution screenshots (18.9% for the best specialist model on ScreenSpot-Pro at release), and zoom-in/crop passes are the standard fix, at the cost of extra model calls.

### Cited Findings
**AndroidWorld and successors**
- AndroidWorld (116 tasks): original M3A agent 30.6% success vs 80% human — [AndroidWorld, arXiv 2405.14573](https://arxiv.org/html/2405.14573v3)
- 2026 self-reported results: Minitap 100%, AGI-0 97.4%, askui AndroidVisionAgent 94.8%, DroidRun 91.4%, Agent-Visco 88.8%, gbox.ai 86.2%, AutoGLM-Mobile 80.2%, single-agent baseline 64% — [Minitap, arXiv 2602.07787](https://arxiv.org/html/2602.07787v1) (self-reported, not independently verified)
- Minitap grounding: UI hierarchy first, screenshot used selectively; input via UIAutomator2 with adb shell fallback; removing hybrid perception -11 points, removing post-action validation -15 points (abstract says +7, table +15), sequential execution with immediate abort on a failed call -12 points; average task 31 s vs 68 s for the baseline; failure causes include repetitive loops (5) and error propagation (4) — [Minitap, arXiv 2602.07787](https://arxiv.org/html/2602.07787v1)
- V-Droid reported 59.5% success with 6.1x lower latency (baseline not named in the excerpt); UI-Venus 65.9% with RL fine-tuning — as cited in [Minitap, arXiv 2602.07787](https://arxiv.org/html/2602.07787v1)
- AndroidDaily plots per-step inference latency against success; closed models trade higher latency for accuracy; best model 62.0%; Gemini 3 Flash had the best accuracy/latency trade-off — [AndroidDaily, arXiv 2605.27761](https://arxiv.org/html/2605.27761)
- AndroidLens evaluates long-latency, nested-sub-target tasks for Android GUI agents — [AndroidLens, arXiv 2512.21302](https://arxiv.org/html/2512.21302v1) (not read in depth)

**Grounding taps without a hierarchy**
- AppAgent added an optional grid overlay so the agent can tap/swipe anywhere, used for elements without numeric tags — [AppAgent README](https://raw.githubusercontent.com/TencentQQGYLab/AppAgent/main/README.md)
- Mobile-Agent grounds with vision tools (detection models such as Grounding DINO and CLIP) on screenshots to find coordinates — as described in [See-Control, arXiv 2512.08629](https://arxiv.org/html/2512.08629v1)
- Grid coordinate mapping struggles with dense UIs or small targets, needing very fine or multi-level grids — [Browser agents paper, arXiv 2511.19477](https://arxiv.org/pdf/2511.19477)
- ScreenSpot-Pro (high-res full screens, small relative targets): best specialist model at release, OS-Atlas-7B, 18.9%; the authors' ScreenSeekeR narrows the search region and improves results without training — [ScreenSpot-Pro, arXiv 2504.07981](https://arxiv.org/html/2504.07981v1), [HF blog](https://huggingface.co/blog/Ziyang/screenspot-pro)
- AdaZoom-GUI zooms a second time only when the first predicted element is small; UI-AGILE uses crop-based resampling; inference-time zoom costs extra forward passes, and a 2026 zoom-consistency loss reports +3.80 on ScreenSpot-Pro — [AdaZoom-GUI, arXiv 2603.17441](https://arxiv.org/html/2603.17441), [UI-AGILE, arXiv 2507.22025](https://arxiv.org/html/2507.22025v1), [ICML 2026 zoom consistency](https://icml.cc/virtual/2026/69346)

### Inferences
- The lessons that transfer to a game agent: (1) verify after every action with a cheap check (did the dock button highlight, did the selection count change) rather than trusting the tap; post-validation was the single biggest ablation in Minitap; (2) abort a planned sequence as soon as one step fails, instead of firing the rest at stale coordinates; (3) detect loops (same action, same screen) and change strategy; (4) per-action latency directly costs retries, so cutting 600-1400 ms framework overhead to tens of ms matters even when model latency dominates.
- Grounding for BAR Droid should not rely on the model guessing pixel coordinates from a downscaled full frame. Use exported dock rects (exact), and for map targets a two-stage approach: coarse frame to pick a region, then a full-resolution crop with a small grid or marks to pick the point; convert back to device pixels in code.
- The game state changes while the model thinks (RTS), so screenshots used for a tap should be taken right before the tap, and taps on moving units should be tolerant (or use engine-side positions that are logged alongside).

### Gaps
- No published numbers found for LLM agents tapping real-time game UIs (RTS or similar) on Android; game-playing agent work (for example on desktop games) was outside this pass.
- Per-step latency of the AndroidWorld leaders (model time vs device time) was not reported in a comparable way.

## 5. Automated playtesting for touch-control UX: logging and tooling

### Takeaway
The accepted baselines are Google's 48x48 dp minimum (about 9 mm) with 8 dp spacing, 7-10 mm physical targets, and the WCAG 2.2 AA 24 dp spacing floor; finger touch has an absolute imprecision that Fitts' law alone does not capture (FFitts law). For traces, Perfetto's `android.input.inputevent` data source records every input event but is documented for userdebug/eng builds with `adb root`, so on a retail S23 the practical stack is app-side MotionEvent logging in BAR Droid plus `getevent`-style kernel logs, recorded alongside a scrcpy MP4 with timestamps.

### Cited Findings
**Target size and spacing**
- Touch targets at least 48x48 dp, separated by 8 dp or more; 48 dp is about 9 mm physical regardless of screen; padding can make the touch area larger than the visible icon — [Android developers, make apps more accessible](https://developer.android.com/guide/topics/ui/accessibility/apps)
- Recommended physical target size 7-10 mm — [Google Accessibility help, touch target size](https://support.google.com/accessibility/android/answer/7101858)
- WCAG 2.2 AA touch target spacing rule uses a 24 dp minimum (tool vendor rule), separate from Google's 48 dp size recommendation — [Deque, touch target spacing](https://docs.deque.com/devtools-mobile/2025.7.2/en/android-touch-target-spacing)
- Accessibility Scanner for manual on-device checks; Espresso/Robolectric accessibility checks for automated tests (views only) — [Google Accessibility help](https://support.google.com/accessibility/android/answer/7101858)

**Finger precision models**
- FFitts law splits touch endpoint spread into a speed-accuracy (relative) part and an absolute finger-precision part independent of task difficulty, addressing the fat-finger problem that classic Fitts' law cannot model — [FFitts Law, Bi, Li, Zhai, CHI 2013](https://research.google/pubs/ffitts-law-modeling-finger-touch-with-fitts-law/), [PDF](https://research.google.com/pubs/archive/41645.pdf)
- Later work extends FFitts law to 2D and debates nominal vs effective width — [Stony Brook, ChineseCHI 2021](https://www3.cs.stonybrook.edu/~xiaojun/pdf/ChineseCHI2021.pdf)

**Timing thresholds**
- Tap vs long-press cut-off is often around 500 ms; double-tap recognition commonly 250 ms; some users tap in 100-300 ms — [User-sensitive mobile interfaces, arXiv 1402.1036](https://arxiv.org/pdf/1402.1036)
- Touch-down to touch-up duration is used as a feature to separate single from double taps — [Single-tap latency reduction, arXiv 2408.02525](https://arxiv.org/html/2408.02525v1)
- Android WALT measures ACTION_DOWN/ACTION_UP delivery latency (sample figures roughly 14-27 ms) — [AOSP WALT TapLatency.md](https://Android.googlesource.com/platform/external/walt/+/HEAD/docs/TapLatency.md)
- Swipe and drag in `input` use the system long-press timeout before moving for draganddrop — [AOSP InputShellCommand.java](https://android.googlesource.com/platform/frameworks/base/+/HEAD/services/core/java/com/android/server/input/InputShellCommand.java)

**Input trace tooling**
- Perfetto data source `android.input.inputevent` with `TRACE_MODE_TRACE_ALL` records all input events processed by the system; rule-based mode via `android_input_event_config.proto`; captured with `adb shell -t perfetto ... -o /data/misc/perfetto-traces/trace`; the page documents adb collection on userdebug/eng builds after `adb root`, and says TRACE_ALL is only for local or test devices — [AOSP Winscope, capture traces with adb](https://source.android.com/docs/core/graphics/winscope/capture/adb)
- Trace Processor exposes `android_motion_events`, `android_key_events` and `android_input_event_dispatch` tables; the Perfetto UI has an Input Events plugin — [Perfetto commit](https://flutter.googlesource.com/third_party/perfetto/+/9756e48703804c3ad8ca1f16da18599d22af8aec), [Perfetto UI plugin](https://flutter.googlesource.com/third_party/perfetto/+/12dcdebab024d48cd2fe71459bc3defe444c9c89/ui/src/plugins/com.android.InputEvents/index.ts)
- Since Android 15, Winscope traces are integrated into Perfetto — [AOSP Winscope, capture traces with adb](https://source.android.com/docs/core/graphics/winscope/capture/adb)
- `getevent`/`sendevent` record and replay kernel input events; tools such as adb-touch-event-replayer and getevent_sendevent wrap them — [adb-touch-event-replayer](https://github.com/testerclub/adb-touch-event-replayer), [getevent_sendevent](https://www.github.com/hansalemaos/getevent_sendevent)
- scrcpy `--record=file.mp4` records the mirrored stream; packets carry PTS — [scrcpy README](https://github.com/Genymobile/scrcpy), [scrcpy develop.md](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md)
- Touch logging apps can achieve about 5 ms error (test touches at 150/300/600 ms logged at 147/301/600 ms) — [search summary citing a smartphone touch-logging study](https://arxiv.org/pdf/1612.03196) (attribution in the search snippet was unclear; verify)

### Inferences
- Size check for this phone: the S23 Ultra panel is commonly listed as 6.8 in at 3088x1440 (about 500 ppi), so at the FHD+ 2316x1080 mode it is about 375 px per inch, and 9 mm (48 dp) is roughly 130 px. Confirm with `adb shell wm size` and `wm density`. In a half-size agent frame, a 48 dp button is about 65 px, which the model can see, but it should still tap via exported rects or a full-res crop.
- Since a real finger has an absolute spread (FFitts law), the agent's synthetic taps should add noise: sample the touch point from a 2D Gaussian around the intended point (a few mm sigma) and use human-like durations (about 60-150 ms for taps, under the long-press threshold) plus small movement during the press. Then report "hit rate under finger noise" per dock button, which is a far better UX signal than "the exact center works".
- A useful per-gesture UX log row: wall clock and monotonic time, intended target id and rect, injected points and timing, what BAR Droid's touch layer decided (tap, drag, pinch, cancelled, slop exceeded, which button), what the game did (order issued, selection changed), the frame index in the scrcpy MP4, and the verdict (hit, miss, wrong target, gesture conflict). The app-side "what the touch layer decided" field is what Perfetto would otherwise give, and BAR Droid can log it on a retail build.
- Flag automatically: targets under 48 dp or with under 8 dp spacing (from exported rects), taps that land within slop of two targets, drags that the layer reclassified (tap vs pan vs box-select), and repeated attempts needed for the same intent.
- Android's developer options "Show taps" and "Pointer location" overlay real and injected touches in the recorded video, which helps reviewers line up the trace with the footage.

### Gaps
- Whether `android.input.inputevent` Perfetto tracing works on a Samsung user build without root was not established (the docs describe userdebug/eng with `adb root`).
- No population-wide average human tap duration was found; the 60-150 ms tap range in the inferences is an estimate built from the 100-300 ms and 500 ms figures above.
- The exact FFitts absolute-precision constant (often quoted near 2 mm for index fingers) was not confirmed in the sources read.
- The "Show taps" / "Pointer location" behaviour is from general Android knowledge and was not re-verified against documentation in this pass.
