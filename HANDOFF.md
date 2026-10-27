# BAR Droid — hand-off (updated 2026-10-26 overnight)

Beyond All Reason on Android. An Android app ("BAR Droid") that runs the **unmodified official Recoil engine**
inside a Debian container with an **embedded X server** (Termux:X11's `lorie` library) and Mesa for desktop OpenGL.

**BAR plays on Kailil's Galaxy Z Fold7** (since the evening of 2026-10-25): ~30 fps, "100 percent fully playable"
against the AI (Kailil). The emulator build (x86_64, the default of `Build APK.bat`) is still the quick test bench:
amd64 Debian + the official amd64 engine, OpenGL through Mesa virpipe → virgl server → ANGLE → host GPU. Phone build:
`Build APK.bat phone` (arm64, Adreno via Mesa Freedreno on KGSL). adb to the phone: USB, or Wi-Fi
`adb connect 192.168.1.196:5555` after `adb tcpip 5555` (until the phone reboots; NordVPN on the laptop blocks it
unless its local-network access is on; Tailscale times out).

Read this file, then `CLAUDE.md`, then `RESEARCH.md`. Plan doc: https://claude.ai/artifact/XDdcJwfebpK1D138U2MjZf

## State

| Piece | Path | State |
| --- | --- | --- |
| Research + plan | `RESEARCH.md`, claude.ai doc | Done |
| Portable Windows toolchain | `..\toolchain\`, `..\Install Toolchain.bat` | Done; nothing in AppData or the profile |
| Emulator build (x86_64, default) | `..\Build APK.bat` → `..\apk\bar-droid-emulator-debug.apk` | **BAR plays in the emulator**: install from BAR's CDN, Play vs AI, BARb AI, units + full BAR UI, sim x1.00, **~20 fps** at 1256×568 at the start camera with the laptop awake (~8 fps while Windows is in Modern Standby), ~1 min to load a skirmish |
| Emulator runner | `..\Run in Emulator.bat` | Done: creates the AVD (Android 14, 12 GB RAM, 6 cores — the emulator's maximum, 32 GB, `hw.gltransport=asg`), boots, installs, opens the app |
| Phone build (arm64) | `..\Build APK.bat phone` → `..\apk\bar-droid-phone-debug.apk` | **Plays on the Galaxy Z Fold7** (Adreno 830, Android 17): ~30 fps capped (60 fps option), no flicker, lobby, touch controls, fold/unfold resize. Lacks the virgl/ANGLE GPU path (not needed with Adreno) |
| Frame pacing, swap | `tools/pace/pace.c` → `libbardroid_pace.so` | The frame cap without VSync, and Mesa on its explicit Present fence: CPU and GPU work at the same time (a spectated 8v8 with 829 units: 15-24 → 28.8 fps) |
| Phone settings layer | `launch-bar.sh` (`PHONE_GFX`, widget orders, interface scale) | No MSAA, shadows, far features, water reflections, BAR's full-screen effects; Spring camera; BAR's interface 2.0 folded / 1.3 unfolded; units drawn as icons unless close (icon distance 1, a test); queued buildings drawn near the camera only; the classic minimap; no lights, decals, AO plates, grass, order effects; unfolded at the folded pixel count; the lobby on Always One panel at 120% |
| proot | `tools/build-proot.py` | Our build of Termux's proot (pinned commit) whose seccomp filter stops only for the ioctls proot handles: 14 → 30 fps on the phone |
| Touch controls | `RtsTouch.java`, `assets/bardroid/bardroid_touch.lua` | One finger pans, pinch zooms, twist rotates, two fingers up/down tilt (see below) |
| Gamepad | `tools/build-gamepad-game.py` → `assets/gamepad/`, `Installer.installGamepadGame`, `ControllerBridge`, `bardroid_touch.lua` | Singleplayer plays Kailil's BAR Controller Support v0.8.5 1:1 as BAR's developer game; online games get a gamepad camera (see "Gamepad" below) |
| Share logs | launcher button | Zips the logs into Android's share sheet (Taildrop, Drive, mail): phone debugging without adb |
| virgl GPU server | `tools/build-virgl.py` | Built from source with the NDK (Termux's binary turns every DXT texture black, see below) |
| ARM64 AI bug fix | `app/src/main/assets/bardroid/libasarm64.so`, `patches/circuitai-cmake-arm64-linux.patch` | Phone build only; not filed upstream yet |

## Overnight hardening (2026-10-26, Kailil asleep; nothing here was checked on the phone by a person)
Found in the phone's logs and code and fixed, each installed on the phone:
- **BAR's settings did not survive a restart**: `Installer.writeGameFiles` rewrote `springsettings.cfg` from the
  template at every start (BAR keeps sound volumes and many options there, and its migration counter, so BAR also
  re-ran its first-start migrations every time). Now the file is kept and completed (`Installer.ALWAYS`). The
  launcher's "UI scale" and "Shadows" controls are gone (launch-bar.sh owns both now).
- BAR refuses `/option` from user widgets: the lights' screen-space shadows go off through `BYAR.lua` instead.
- `widget_order` broke on names with "/" ("Keybind/Mouse Info").
- The lobby wrote `CamMode = 1` at every game start: singleplayer had the overhead camera (no finger twist or tilt).
- The updater would have rolled BAR back after any crash in the first 120 s of an update (a save loading is one):
  now only when no game frame ran.
- Engine log copies were never deleted (now the newest 20); `files/container.sh` broke after every app update.
- The touch widget rewrote VSync settings at every 60/120 Hz switch (pointless since the pace library); gone, and
  VSync is off in the phone settings.
- `/proc/cpuinfo` had no CPU name for the engine: the lobby's analytics threw at every start, BAR's system info
  took "11102MB RAM" for the CPU. The container now gets a `model name` line.
- The interface scale ignores the floating window (no reload when the app goes to the background).
- `[perf]` logs memory now (Android reported low memory all through an 8v8).
- Later that night, from reading the code: a pad that reports its D-pad as keys lost a held direction at every stick
  move; Stop left the audio pump on the FIFO (the next game's sound split between two readers); springsettings.cfg
  is written atomically now that it holds the player's settings; an error in `bardroid_touch.lua` no longer removes
  it for the rest of the game (pcall); a full launcher.log becomes launcher.old.log instead of being deleted; a
  download whose `.part` was already whole (HTTP 416) or a damaged engine/Mesa archive no longer blocks the install
  or update for good.
- A finger drag on BAR's top bar (the share and conversion sliders) or in an open BAR window (the settings and their
  sliders) panned the map underneath: they answer no `IsAbove`. The touch widget now counts the top bar
  (`WG.topbar.GetPosition`) and any open window (`WG.<window>.isvisible`) as interface. Checked in a real skirmish on
  the laptop (`tools/touch-widget-test.ps1`: the old widget fails the top bar and settings cases, the new one passes).
- The lobby bridge sends the replays' winners (Won/Lost in the Replays tab), checked against BAR's own launcher cache.
- **New: the engine stops drawing while nobody sees the game** (phone locked, another app in front; not the floating
  window). It already does so when its window is hidden (as minimized on a PC: two frames a minute, sound muted), but
  without a window manager nothing hid it, so a locked phone kept drawing 30 fps. GameActivity keeps
  `/tmp/bardroid-hidden` while stopped; `libbardroid_pace.so` hands the engine SDL2's HIDDEN/SHOWN window events.
  Checked on the phone with its SDL2 (`tools/pace-test.ps1`), not yet in a game: lock the phone mid-game, unlock,
  the picture and sound come back at once ("game screen hidden/shown" in launcher.log). Off: `export
  BARDROID_HIDDEN_PAUSE=0` in `files/bar/dev-env.sh`.
- launch-bar.sh as it is now, dry-run on the phone (in the container, on copies of Kailil's BYAR.lua, IGL_data.lua,
  IGL_order.lua and springsettings.cfg, a stub engine): no layer miss; it sets the Spring camera (Kailil's pick and the
  default he wants, `CamMode = 2`; springsettings had CamMode 3, the lobby's copy 1), GroundDetail 200 → 60, the VSync keys the old touch widget left (VSync 2, VSyncGame 1)
  off, MSAA/features, Snow/SSAO/Keys/Changes off, the Build menu, the lobby's panels and 120%; a second run changes
  nothing. (The container's `/opt/bardroid` copy is refreshed only when a game starts.)
- The engine update path (never run on the phone: BAR has been on 2026.07.04 all along) checked with BAR's test engine
  2026.09.01 under a scratch name: its arm64 archive downloads, the container step extracts it, `spring --version`
  runs, and it still knows every springsettings key of ours. Removed again. When BAR's launcher config moves
  `manual-linux` to it, the phone follows at the next start.
- BAR's interface at the Fold's layouts, rendered on the laptop (`tools/ui-screenshot.ps1`, screenshots in
  `build/ui-screenshot/`): the inner screen's top bar fits at 1.3 with the phone layer (BAR's own Changes/Keys ran
  into the wind/tidal counters); the cover screen at 2.0 fits (the Build menu pages its two rows). **Open, Kailil's
  call:** on the inner screen the player list (bottom right) covers the order menu's last column (Move, Reclaim,
  Place Blueprint): BAR sizes the order menu by 1/aspect ratio, so on a near-square screen the info panel and order
  menu take 89% of the width. The player list at 75% (`AdvPlayersList.customScale`) uncovers most of it
  (`inner-phone-1.3-list075.png`); moving the order menu off the bottom does nothing there.
- The last 8v8's late slowdown (29.6 → 19.6 fps as it grew to ~1300 units) is the load, not BAR's presets: Kailil
  switched to "medium" and back to "lowest" mid-game and it stayed at ~19 fps as the game got busier. The `[perf]`
  lines of those minutes: GPU 90-93% busy at its thermal cap (525-607 MHz). Next lead for big late games.
- Tests that run on the laptop, all in `tools/laptop-tests.ps1` (~5 min, all PASS): Downloader, the springsettings
  merge (`SettingsMerge`, with Kailil's file: 147 of BAR's keys kept), the updater's rollback decision, the lobby bridge
  against the real lobby, the touch widget in BAR's game and the controller game. `tools/pace-test.ps1` checks the
  pace library on the phone.
- Morning of 2026-10-26, from Kailil's tests: (1) **map-edge drags** felt jarring: off the map the finger's point fell
  on a stand-in plane whose height does not match the terrain at the edge (a jump when crossing it) and near the
  horizon a few pixels are miles. Now a drag from off the map is measured in the middle of the screen, which the
  engine keeps on the map, and the last 400 elmos before the edge blend from finger to centre (Kailil's rule); a
  pending move against the edge clamp is dropped (no dead zone when dragging back). touch-widget-test has an edge case
  (old widget 0.67 of the right distance, new 1.00). (2) **Late-game LOD test**: `UnitIconFadeStart/Vanish = 1` in
  `PHONE_GFX` (BAR's "Unit icon distance" slider at its minimum; BAR forces `UnitIconsAsUI`, so a unit is an icon
  whenever its model would look smaller than the icon): only close units are drawn as models. BAR has no "N units"
  limit, and unit animation runs in the synced simulation for every unit. Kailil to judge in a late game. (3) **The
  floating window** draws at 15 fps (`/tmp/bardroid-floating`, pace library); its resolution already drops with the
  window (584x530). (4) The lobby's split panels: "Always One" (panel_layout 3), Kailil's correction.
- Later that morning: (5) **a touch in the void** (off the map, over the sky) selected empty space and threw the
  camera. The touch widget now answers 2 there (`bardroid_hover.txt`); `RtsTouch` ignores such a finger: no click,
  right-click or box select, the pointer goes to the middle of the screen and a drag pans from there
  (`startPanFromMap`). (6) **Queued buildings far away**: BAR's Show Builder Queue draws every queued building on the
  map every frame (a thousand queued wind turbines across the map, a tilted camera). Off; the app's
  `bardroid_queue.lua` draws them from BAR's own builder queue API and shape drawer only within 2000 elmos of where
  the camera looks (at most 400). (7) **The buttons under the minimap** come from BAR's Picture-in-Picture Minimap
  (its hover button bar ignores its own "no buttons" setting, and a finger always puts the pointer there): off, the
  classic Minimap instead. touch-widget-test runs with the phone's widget orders and checks the void answer, a void
  drag, the queue near and far, and the minimap answer.
- **GPU cuts for late games** (Kailil: "All four"; the GPU is the limit there, 90-93% busy at its thermal cap): (1)
  unfolded, the X screen has about the folded pixel count, ~1152x1044 instead of 1456x1312 (patch 0006,
  `LorieView.maxScaledViewPixels`, set by `GameActivity.MAX_SCREEN_PIXELS` = the cover screen's 2520x1080; the
  "scaled" display treats a bigger screen as one of that many pixels); (2) BAR's lights (Deferred rendering GL4) off;
  (3) scorch marks (Decals GL4), the shadow plates under units and wrecks (Ground AO Plates GL4, … Features GL4) and
  BAR's grass (Map Grass GL4) off; (4) the animated order lines (Commands FX) off. Kailil to compare fps in a late game.
  The pixel cap checked in the emulator with the inner screen's size (`adb shell wm size 2184x1968`, display prefs
  "scaled" 150% for the test, restored after): X screen 1152x1044, interface scale 1.3, the lobby fills the screen,
  a tap lands where it should.
- **The laptop's memory and the emulator:** the engine takes 7.2 GB resident in the emulator (plus 3.0 GB in its virgl
  server) for a plain skirmish. With Kailil's `llama-server` (USAJOBS Autopilot's model, 8 GB) running, a 12 GB
  emulator left the laptop at 0.7 GB free: the game ran at x0.1 and 0 fps (paging), and at 10 GB Android's low-memory
  killer took the app (and the lobby's unsaved login) while loading a big online game. Emulator games need that
  model server stopped (Kailil's call) or a smaller guest and small games.
- **Catch-up when joining a running game** (Kailil: a 40 min game "crawls at a 1-2x catch up speed"). The phone's
  logs of that join (cover screen, the cuts above on): game speed x4 at 845 units falling to x1.6 at 3400 units by
  minute 25, 9-21 pictures a second all along, GPU 50-86% busy, thermal status 2-3 with the CPUs capped at 1.2-2.0
  GHz (of 3.5/4.5) and ~1 GB of memory free. The engine's catch-up loop (Recoil `rts/Net/NetCommands.cpp`
  `GetNetMessageProcessingTimeLimit`) simulates for `(1 - MinSimDrawBalance) / MinSimDrawBalance` times the last
  picture's cost (at most `1000 / MinDrawFPS` ms) between pictures, so drawing gets 15%. First try (0c3a2a7):
  MinSimDrawBalance 0.02 / MinDrawFPS 1 in the config overlay while far behind. Kailil: "still slow"; its join
  (15:23, phone at thermal status 3-4, CPUs capped at 960-1017 MHz, GPU at its 160 MHz floor 99% busy) still drew
  15-26 pictures a second, x2.1-2.5. Not the network: the join's replay holds 5-6.5 KB of game messages per
  game-second (`tools/demo-rate.py <replay.sdfz>`; msg 50 = Lua messages about half), which the server's default
  64 KiB/s link (`LinkOutgoingBandwidth`) sends at 10-13x. Now (catch-up mode 2): more than 30 s behind (not in
  replays) `bardroid_touch.lua` writes `LuaUI/Config/bardroid_catchup.txt` ("<frame> <server frame> <speed>", from
  `GameFrame` about once a second: Update stops with the drawing); `GameActivity` polls it twice a second, shows
  "Catching up 12:30 of 41:10 x2.5" over the game and keeps `/tmp/bardroid-catchup`, which `libbardroid_pace.so`
  treats like the hidden flag (SDL HIDDEN: no drawing, a 10 ms sleep per loop pass, sound muted). The overlay
  settings stay (each stretch of simulation ~50x the last picture's cost). A file older than 10 s counts as caught
  up; GameService and the widget's Initialize remove leftovers. `[bardroid-catchup]` lines every 30 s also count
  pauses over 50 ms between simulated frames: few = the CPU is the limit; many = waiting for data.
  `bardroid_catchup = 0` in springsettings turns it off. `tools/catchup-test.ps1` (~6 min): a headless host plays
  BARb vs BARb on 127.0.0.1, a windowed spectator joins twice (mode off, on); it checks the widget's side (the
  engine on Windows has no pace library). `tools/pace-test.ps1` checks the catch-up flag on the phone.
  Kailil's next join (15:50, 6a1160c) started the mode only at 11:20 game time: GameProgress reaches a late joiner
  behind the whole backlog. Since 6bb52ae the game's own pace starts it (faster than 1.5x its speed for 2 s, until
  the first GameProgress). That join's numbers, drawing off, phone at thermal status 2 (CPUs capped at ~1.4 GHz of
  3.5/4.5 the whole time, GPU down from ~55% to 3-15% busy, 2 °C cooler): x2.0 at 2,400 units, x1.6-1.9 at
  3,000-3,400, x1.2-1.5 at 4,000-4,500, x0.9-1.0 past 5,000, x0.6-0.7 at 6,000-6,800 (it stayed 9 min behind: the
  phone cannot run such a game at 1x at all). Frames there take over 50 ms each: the CPU is the limit.
  **Catch-up on the laptop's emulator, end to end** (Kailil logged in there for online tests, but the lobby lost the
  saved login when Android's low-memory killer took the app while loading a big game in a 10 GB guest; 12 GB is
  the AVD's size): `tools/catchup-test.ps1 -HostOnly -AIs 4 -FastMinutes 20 -Engine recoil_2026.07.04 -Game "Beyond
  All Reason test-31723-95ab750"` hosts a 2v2 BARb game on the laptop, fast-forwarded (the host widget
  `tools/catchup-test/bardroid_host_speed.lua` sends speedup/slowdown), then held at 1x; the emulator app joins it as
  the spectator "Phone" through a temporary `files/bar/dev-env.sh` that copies `join.txt` (HostIP 10.0.2.2, port
  8452) over skirmish.txt before PLAY VS AI (remove both afterwards). Seen: the overlay "Catching up 0:50 of 27:18
  x3.6" over the last picture, the engine not drawing. The emulator's network (SLIRP UDP) stalls ~1 s at a time, so
  its catch-up speed says nothing about the phone's. The emulator build now ships the x86_64 pace library
  (`libbardroid_pace-x86_64.so`, no frame cap, `BARDROID_PRESENT_FENCE=0`) for the hidden window.
  A game the phone cannot run at its own speed never catches up: no ground gained in 60 s, the mode ends (it draws
  again, "not gaining" in the log) and tries again 5 min later, twice as long after each further give-up
  (`tools/catchup-test.ps1 -HostSpeed 4 -BurnMs 10 -Modes 1`: a host that stays fast, a deliberately slow spectator).
- **Where a big game's CPU goes** (`tools/profile-big-game.ps1`: a BARb game fast-forwarded, BAR's widget profiler at
  1x with the phone's widget orders, the engine's timers via `/debuginfo profiling`; `-ProfileFastAtMinute` measures
  at 10x, i.e. per simulated frame; `-Functions` times one widget's callins). 6 BARb, 753 units, laptop: all widgets
  1.45 ms/frame at 1x; the engine's totals over the run (mostly at 10x) Sim 89 s, unsynced Lua callins 50 s (widgets
  and the game's unsynced gadgets), drawing 29 s, synced Lua 11 s. Found and fixed: our own touch widget was the
  costliest widget (0.14 ms/frame: a file open and a view ray every frame; now 0.035 ms Update); Jammed Units
  Highlight (a red tint on units in jammer cover, every unit checked every 6 simulated frames) costs the most per
  simulated frame (13.8 ms/s at 10x): off on the phone, with the full-screen Contrast Adaptive Sharpen pass. Other
  big ones, all gameplay information, left on (Kailil's call): Defense Range GL4 (5 ms/s at 1x), Top Bar, AdvPlayersList,
  Sensor Ranges Jammer Preview, Ecostats, Metalspots, BuildETA. `[perf]` now finds the engine (its process is
  `recoil-main`, the memory column was always "?").
- **More worker threads do not speed up the simulation** (a headless 6-BARb host at max speed, `catchup-test.ps1
  -HostOnly -Workers 4|7`): at 680-700 units x14.3-15.1 with 4 workers, x13.6 with 7. The app's `WorkerThreadCount =
  4` stays (fewer busy cores, less heat). Load-time pathing setup ("PFS", 4.1 s of the phone's ~45 s load) is the
  only place that uses them much. Phone load after the game data: map 7 s, map tiles 4 s, projectile textures 4 s,
  radar icons 4 s, PFS 4 s, LuaRules 8 s.
- **Second optimisation search (2026-10-26 evening, Kailil away).** The phone's own infolog (`logs/catchup3/infolog2.txt`)
  shows what it runs: BAR's Lowest preset (Kailil's: `AdvMapShading = 0`, `Water = 0`, `MaxNanoParticles = 0`, GUI
  Shader off), 225 widgets, 204 unsynced gadgets; Outline Shader GL4 removes itself there. Found, from Recoil's source
  (2026.07.04 = the phone's engine): BAR forces `AllowDeferredMapRendering`/`AllowDeferredModelRendering = 1`
  (`luaintro/springconfig.lua`), so every frame the engine (1) clears the map's G-buffer, six screen-sized targets, which
  with advanced map shading off is all it ever does to it (`SMFGroundDrawer::DrawDeferredPass`), and (2) draws every
  tree, rock and unit model a second time into the model G-buffer (`ModelDrawer::Draw` → `LuaObjectDrawer::
  DrawDeferredPass`, CUS GL4's deferred shaders), for readers that are all off on the phone (lights, SSAO, bloom,
  distortion, outlines) except shields (units touching them) and the radar/jammer placement previews.
  `bardroid_touch.lua` now switches the map pass off while `AdvMapShading` is 0 (`Spring.SetDrawGroundDeferred`,
  checked every 60 drawn frames) and the features' model pass off for good (`Spring.SetDrawModelsDeferred(true,
  false)`: units stay, their pass clears the buffer every frame, so nothing stale is left), from the 3rd drawn frame
  (both buffers hold a cleared picture by then; one that is not drawn is not resized either), restored in Shutdown.
  And BAR's Fog Diagonal Lines GL4 reads the ground from that map buffer: with it only cleared its full-screen pass
  discards every pixel, so `launch-bar.sh` turns it off while the lobby's (`IGL_data.lua` game_settings) or the
  engine's `AdvMapShading` is 0 (marker `.bardroid-fog-lines-off`; back to BAR's default at 1). No visible change
  expected; the GPU saving is unmeasured (the laptop's RTX says nothing about a tiler): check late-game fps on the
  phone. `[bardroid-touch] map G-buffer pass off` / `trees and rocks drawn once` in infolog.
  Measured on the laptop (`tools/profile-big-game.ps1 -Gadgets`, new: `tools/profile/dbg_bardroid_gadget_profile.lua`
  times every unsynced gadget callin; 8 BARb, 989 units at 30 min): unsynced gadgets 6 ms/s at 1x, 0.19 ms per
  simulated frame (Beam Laser GL4 0.074 of it, its GameFramePost scan; CUS GL4 1.2 ms/s; Team stats 0.5 ms/s); all
  widgets ~12 ms/s plus BAR test's dev-only Engine Shader Auto Reloader (5.7 ms/s, not in the release the phone runs).
  Lua is ~2% of the frame there: the phone's late game is the GPU, catch-up the simulation (Sim 110 s of the run).
  Also: the pad thread (`ControllerBridge`) slept 16 ms in a loop with no pad; it now waits out the 100 ms heartbeat
  and wakes on pad input. Not changed, for the record: `UseLuaMemPools = 0` comes from the lobby's own settings;
  `MaxSounds` is reset to 128 by BAR's options; BAR's GPU Profiler needs `gl.QueryCounter`, in no released engine yet.
  The laptop ran at ~6 fps the whole evening (also a 2-unit skirmish): its idle power state, not the game.
- **Kailil back, evening of 2026-10-26** (build 09e6e74 on the phone): a 16-17 min game caught up in 164 s (x6.1 on
  average, 0:21 → 17:07), then 29-30 fps with 2,500-3,900 units (dips to 16-20 for a few seconds). Asked for and
  done: the catch-up screen is black (the progress over a full-screen black view; the last picture stood still behind
  a 75% black box before); tilt is forgiving (`RtsTouch.twoFingerKind`: both fingers moving up or down together,
  without pinch or twist, however they sit; the slower finger gets 3 slops to follow; a second finger within 250 ms
  of the first is one two-finger gesture even if the first already slid; the tilt counts from where the fingers came
  down); new gestures (RtsTouch → "act <name>" lines → `bardroid_touch.lua` ACTIONS, checked by
  `tools/touch-widget-test.ps1`): triple tap = the double tap's types on the whole map (`select
  AllMap+_InPrevSel+_ClearSelection_SelectAll+`), two fingers held 450 ms (buzz) then swiped: up select all / down
  deselect / left stop / right fight (armed), three-finger swipe: up overview / down back / left-right previous-next
  idle builder (own mobile builders without orders, camera to it). Stop and fight go through
  `Spring.SetActiveCommand` (BAR's order buttons do the same; `SendCommands("stop")` reaches no order). Three-finger
  tap still toggles the keyboard (Kailil: keep it, but as a small floating keyboard in the bottom left: that is
  Samsung Keyboard's Floating mode, the user's setting; LorieView already asks for no full-screen editor).
  **Chat** (not changed yet, Kailil's call): BAR's chat box runs from the top bar's left edge to 74% of the width;
  each line has a game-time column and a name column as wide as the longest player name in the game, so on the inner
  screen at 1.3 the text wraps in ~120 px (`tools/ui-screenshot.ps1 -Screen inner -Scale 1 -Chat -PlayerName
  LongPlayerName_2026`, new). BAR's only setting is the font size (`fontsizeMult`, slider 0.92-1.12; 0.6 and 0.5
  tried: ~170-200 px of text). So the app has its own chat display, `bardroid_chat.lua` (Kailil approved the
  screenshots, installed 23:15): BAR's lines hidden (`WG.chat.setHide(true)`; its typing box, sounds and ignore list
  stay; its history on typing off), the lines BAR parsed come through `WG.chat.addChatProcessor`; names at the box's
  left edge in team colour, broken every 10 characters, the text filling the rest (BAR's box: top bar's left edge to
  74%), 75% of BAR's font size, 8 rows (14 while typing), 40 s per line; paused / left / lagging console lines from
  AddConsoleLine. Lost: tapping a map-marker line, emoji images, the lines from before a LuaUI reload (fold/unfold).
  In the touch test (a said line arrives); `launch-bar.sh` reports its errors. In the controller game v0.8.5 clears
  an armed command, so the fight gesture does not stay armed there (the test notes it).
- `[bardroid-perf]` counts drawn frames now (the world pass), not Update calls, which go on while nothing is drawn;
  `[perf]` says when the game screen is hidden. `widget_order` only writes into BYAR.lua's top-level order table and
  reports a miss if an order did not land.
Found, not ours: BAR's save-load crash also happens on Windows (upstream; draft report in `docs/upstream/`). The lobby
bridge stays off by default (launcher setting) until Kailil has tried it in the phone's lobby; it passed against the
real lobby on the laptop (Next steps). Verified on the laptop engine: the per-screen interface scale (one reload, no
loop), the touch camera in BAR's game and the controller game, and the touch widget's cost (none measurable).

## Phone session (2026-10-25, 17:00–20:00): first runs on the Fold7

Results on the Galaxy Z Fold7 (SM-F966N, SM8750 / Adreno 830, Android 17, 11.4 GB RAM; inner display 2184×1968 at
up to 120 Hz, cover 1080×2520 at 60 Hz):
- **Flicker** (frames shown before the GPU finished them): lfdevs' Mesa before 27.0.0-devel-20261025 lacks the KGSL
  present-wait fence. `Prefs.mesaUrl` is now that build; `Installer.mesaOutdated()` reinstalls Mesa when the saved
  URL is older (Play runs the install first). Kailil: "flicker is solved fully".
- **14–15 fps → ~30 fps**: Termux's proot puts `ioctl` in its seccomp filter with an exit stop on Android, so every
  KGSL GPU-driver ioctl cost two ptrace stops (18,600 proot wake-ups/s, libproot 48% CPU). `tools/build-proot.py`
  builds proot (termux/proot `b27d81a`, sha256-pinned) with the NDK and patches `syscall/seccomp.c` so `ioctl` traps
  only for the requests proot handles (SIOCGIFINDEX, TCSETSF, TCGETS2/TCSETS*2, FICLONE). Checked on the phone and the
  emulator with a perl loop: 0 of 200 `TCGETS` ioctls stop, 50 of 50 `TCSETSF` still do, futex untouched. The
  loader is built like Termux's (`-Ttext=<LOADER_ADDRESS>,--rosegment`, same segment layout). `fetch-prebuilts.py`
  no longer writes proot.
- **Audio gaps**: the chain was engine → SDL → PulseAudio `module-pipe-sink` → FIFO → `AudioTrack`. AudioFlinger
  showed 0 underruns with ~380 ms queued, so the holes were already in the stream: whenever SDL's audio callback was
  late, PulseAudio rendered silence. Now `UseSDLAudio = 0` and OpenAL Soft's **wave writer** writes straight into the
  FIFO (`/root/.alsoftrc`: `drivers = wave`, 48 kHz stereo int16); its mixer thread is paced by the clock and catches
  up after a stall. `AudioPump` parses the WAV header and starts the track with 200 ms queued (also less latency than
  the ~700 ms before). PulseAudio is no longer started. Kailil: "sound is perfect".
- **Lobby black screen**: Chobby needs `chobby_config.json` (BAR's launcher writes it from its config's
  `json_files`: server4.beyondallreason.info:8200, game `byar`); without it Chobby finds no game config and shuts
  down. `launch-bar.sh` writes it for lobby mode. On the phone Kailil logged in, browsed servers and spectated a
  multiplayer game.
- Frame cap: `VSync = VSyncGame × VSyncFraction` like BAR's options (BAR rewrites `VSync`); the app asks for a 60 Hz
  display mode and the widget picks the swap interval from the real refresh rate (30 fps default, 60 experimental).
- Fold/unfold: the activity is not recreated and the X screen follows the view. There is no window manager, so
  `patches/0003-lorie-fit-windows-on-resize.patch` makes the X server resize mapped top-level windows at the origin
  to the new screen size itself (in `lorieRRScreenSetSize`): works in the lobby, while a game loads (Flex/tent mode
  first hands the app part of the inner screen, then all of it) and in game. The patch also wraps `ConfigNotify`:
  when a client resizes such a window to anything but the screen size, a work proc fits it again. Needed because
  SDL keeps the display bounds it saw at startup and the engine clamps every window-attribute update to them
  (`GetWindowPosSizeBounded`): started unfolded, the cover screen's 1680x720 became 1456x720. For the same reason the
  widget must never call `Spring.SetWindowGeometry` (it did as a fallback and kept re-clamping). Each X screen size
  the app sees is logged (`[display]` in launcher.log). Tested on the emulator with `adb shell wm size` (lobby, three
  resizes while loading, in game); the ConfigNotify rule only on the phone (Kailil). Its first version called
  present's `ConfigNotify` without unwrapping, so present's own unwrap/rewrap dropped ours after one call (found with
  the `screen`/`fit window` lines lorie logs to logcat, tag LorieNative). The phone's logcat buffer is set to 5 MB
  (`adb logcat -G 16M`; the app floods it otherwise). Last piece: Chobby's LuaMenu widget "Resolution limiter" shrank
  the window to SDL's stale screen size on every ViewResize and toggled fullscreen, fighting the fit twice a second
  (black flicker); `launch-bar.sh` sets it to 0 in `LuaMenu/Config/IGL_order.lua`. **Kailil (21:50): folding and
  unfolding works perfectly** (lobby, either starting screen).
  Landscape only, both sides (`sensorLandscape`). Samsung's "continue apps on cover screen" must allow BAR Droid.
- RAM: a match uses ~5–6 GB (1.1 GB resident + swap at the time); the launcher no longer says 12 GB.
- **Memory (spectated 8v8, one snapshot each):** `recoil-main` held 5.2 GB anonymous (3.4 GB swapped), GPU (kgsl)
  only 341 MB; Android killed the app in the background for `LOW_MEMORY` (`dumpsys activity exit-info`).
  `VFSCacheArchiveFiles = 0` (the engine kept every file read from the pool archive in memory, decompressed) and
  `TextureMemPoolSize = 0` (512 MB image pool): 5.6 → 4.5 GB, phone free 1.1 → 1.5 GB. The rest is engine data
  kept on purpose (largest anonymous region 652 MB, nearly all swapped; QTPFS 234 MB; mimalloc already purges
  freed memory). Leaving the game now opens a floating window (Termux:X11 `PIP` pref, set once in
  `BarApp.applyDisplayDefaults`): visible, so Android almost never kills it. Background survival not yet confirmed.
- **Black squares for units zoomed out** (strategic icons): the engine builds its icon atlas (and the projectile
  atlas the Perlin smoke draws into) as `GL::Texture2D(..., wantCompress = true)` and renders into it through an FBO.
  With `CompressTextures = 1` Freedreno picks a compressed format, which is not color-renderable:
  `FBO-TEXTURE-RENDER-ATLAS: None/Unsupported textures/buffers attached`, `atlasRendered=0`, every icon black (also
  `FBO-PROJECTILE-DRAWER-PERLIN`). The emulator's virgl does not compress, so it never showed there. Now
  `CompressTextures = 0` always (the app setting is gone). Confirmed on the phone: no atlas warning in the last eight
  engine runs (2026-10-26). (The engine drops the key when it saves springsettings.cfg, 0 being its default.)
- Lobby: `launch-bar.sh` turns Chobby's `drawAtFullSpeed` on once (`LuaMenu/Config/IGL_data.lua`, marker
  `.bardroid-lobby-fullspeed`); the player can turn it off again in the lobby's Settings.
- Mouse: `HardwareCursor = 1`, so lorie draws the pointer on every display frame instead of the engine once per game
  frame (verified: with spring SIGSTOPped the pointer still follows). The lobby is slow by design on top of the
  phone's speed: Chobby's `gfx_limit_idle_fps` runs it at VSync 2 (30 fps) while active and VSync 4 (15 fps) after
  1–2 s idle (and it measures time with `os.clock()`, CPU time); its Settings checkbox `drawFullSpeed` makes the
  active rate 60.

**Touch controls** (`RtsTouch`, on by default; off = Termux:X11's touch modes), Kailil's spec of 19:30:
tap = left click (double tap = double click); one-finger drag = pan (grab, with a fling); tap-then-drag = box select;
long press = right button (lift = order, drag = formation); two fingers = pan + pinch zoom (mouse wheel at the centre)
+ twist rotate; two fingers moving up/down side by side = tilt; two-finger tap = right click; three-finger tap =
keyboard; Back = Escape. The app talks to `bardroid_touch.lua` through files under `LuaUI/Config` (BAR's sandbox gives
user widgets no sockets). A one-finger drag that starts on the interface is a mouse drag instead: the widget is the
last `IsAbove` in line, so it hears about the pointer only where no widget claimed it, and answers through
`bardroid_hover.txt` (+ `Spring.IsAboveMiniMap`). That catches the minimap and modal windows (options); BAR's top bar,
build and order menus do not implement `IsAbove`, so a drag there pans (taps are fine). `CamSpringLockCardinalDirections
= 0`, or small twist steps never leave north. Tested on the emulator with injected multitouch (pan, twist, tilt);
not on the phone yet.

Next: Kailil checks audio, gestures, lobby and fold/unfold on the phone; then RAM, BAR's UI on the near-square inner
display (ui_scale), and touch-only play (later, Kailil).

## Afternoon session (2026-10-25, 12:40–16:45): units, speed, Share logs

**Invisible units (would have hit phones too).** Our presets set `MaxParticles` 2000 (phones) / 600 (emulator).
BAR's `gfx_fire_smoke_gl4` sizes a VBO at `(MaxParticles - 7000) * 2 + 10000`; at ≤ 0 `LuaVBOImpl::Define` throws while
unsynced LuaRules loads, the whole unsynced LuaRules dies and CUS GL4 (BAR's unit renderer) with it: no units, no
command panel. Now `MaxParticles = 10000` (bottom of BAR's own slider); the emulator no longer overrides particles,
LOD or icon distance. Commander, build menu, unit info and orders all work (`..\logs\emulator-units-ingame.png`).

**Frame rate, measured the same way each time** (developer widget `tools/dev/bardroid_fps.lua`, copied to the
device's `files/bar/LuaUI/Widgets/`, logs `[bardroid-fps]` to infolog every 10 s; not shipped by the app). All with the laptop in Modern Standby unless noted:
| Change | Result |
| --- | --- |
| Before | 2 fps, sim x0.5–0.7, skirmish load 3:21 |
| proot without `--kernel-release` (its kompat extension traps every `futex()`; spring's render thread spent ~45% in ptrace stops) | load 1:46, sim x1.00 |
| Emulator `hw.gltransport=asg` (shared-memory ring instead of the goldfish kernel pipe; 87% of the virgl server's CPU was in `goldfish_pipe_read_write`) | 7 fps (X server 45%→11% CPU), load 1:13 |
| virgl: no timer-query cap, deferred query polls, no per-command `glGetError` | ~8–9 fps; **~20 fps with the laptop awake** |
Not worth it (measured): `mesa_glthread=true` (≤5%), half the pixels (`displayScale` 270: +18%), ANGLE
`asyncCommandQueue` (not in this ANGLE build). Where the time goes now: spring's render thread waits in
`glXSwapBuffers` for virgl to finish and read back the frame; virgl waits on the host (ANGLE checks a fence after
every submit = a host round trip; vrend's fallback blit for the engine's per-frame Z24S8→Z32 depth copy switches GL
contexts twice per frame, each a flush + submit). Ideas left: avoid that context switch (an experiment storing
Z32_UNORM as DEPTH24_STENCIL8 showed no clear gain while throttled; not kept), fewer ANGLE submits.
**Host power matters**: Windows Modern Standby (lid/screen off) throttles the laptop to ~40% of the awake frame rate.
Check `Get-WinEvent` Kernel-Power 506/507 before comparing numbers.

Experiment, not usable yet: the emulator's own GLES driver instead of ANGLE (developer switch file
`files/bar/dev-virgl-native`; build-virgl.py adds a pbuffer fallback for EGL without surfaceless contexts). It lacks
geometry shaders and `OES_texture_3D` framebuffer attachments; libepoxy aborts the server on
`glFramebufferTexture3DOES` while BAR loads.

Developer hooks (none created by the app): `files/bar/dev-env.sh` (sourced by `launch-bar.sh`),
`files/bar/dev-springsettings.cfg` (appended to springsettings), `files/bar/dev-virgl-native`, `LuaUI/Widgets/*.lua`
in `files/bar`. Profiling: `adb root` works on the google_apis image; NDK `simpleperf` (pushed to `/data/local/tmp`)
with `--call-graph dwarf --trace-offcpu` shows wall time; the unstripped virgl library for symbols is
`build/virgl/build-x86_64/src/libvirglrenderer.so`.

Memory: once, the low-memory killer took the whole app ~40 s into a match (guest swap full). Later runs held at
~0.7 GB available. The laptop has 31.6 GB; other programs (llama-server ~14 GB, a Windows BAR) leave little room.

## Emulator-first session (2026-10-25, 08:50–11:10)

Why x86_64: Google's emulator cannot run ARM64 Android images on an Intel host, and on x86_64 images with ARM
translation proot cannot trace translated processes (it hangs). So the emulator build is x86_64 end to end:
- `tools/fetch-prebuilts.py <abi>`: Termux proot/talloc/shmem + Termux's ANGLE + Debian static busybox for any ABI,
  patched like the original arm64 set (`libtalloc.so`, `RUNPATH=$ORIGIN`).
- `-PbardroidAbi=x86_64|arm64-v8a` (root `build.gradle`) picks the ABI; `BuildConfig.TARGET_ABI` → `Prefs.EMULATOR_BUILD`
  switches the Debian image (dist-amd64), engine (`recoil_2026.07.04_amd64-linux.7z`), skips the Adreno Mesa tarball
  and the ARM64 AI stub, and selects the GPU path.

Fixed on the way (all would also have hit phones):
- **App processes see `/data/user/0` as a symlink to `/data/data`** (Android 11+ data isolation). proot canonicalizes
  its rootfs, so the hard-link symlinks written by `--link2symlink` (from `PROOT_L2S_DIR`) were unresolvable inside the
  app: Perl and every hard-linked file vanished, apt's maintainer scripts failed. `Paths` now uses canonical paths;
  the rootfs completion marker is versioned so older trees are rebuilt.
- proot's `.l2s` directory must exist before extraction, busybox tar aborts at the first error (a partial tree was
  accepted before), Debian's static busybox has no `--exclude`: rootfs extraction is now strict (exit code + loader
  check + completion marker; an incomplete tree is wiped).
- **Stop did not stop the game**: proot ignores SIGTERM (what `Process.destroy*` sends on Android) and leaves its
  tracees running when SIGKILLed. Stop now SIGKILLs every other process of the app's UID.
- `AudioPump` keeps draining the FIFO when no `AudioTrack` can be created (an emulator without audio).

GPU path (virpipe): `VirglServer` starts the virgl server next to the X server; Mesa inside the container uses
`GALLIUM_DRIVER=virpipe` + `MESA_GL_VERSION_OVERRIDE=4.3COMPAT` (virgl on GLES only advertises 2.1 compat; the host
has the GL4.3 features BAR uses). The engine reports `GL 4.3 (Compatibility Profile)`, renderer
`virgl (ANGLE (NVIDIA, Vulkan 1.3.0 (NVIDIA GeForce RTX ...)))`, "GL4 support: 1". Findings:
- The emulator's own EGL lacks `EGL_KHR_surfaceless_context`, so the server uses ANGLE (GLES on Vulkan, Termux's
  `angle-android`, bundled) via `--angle-vulkan` + `BARDROID_ANGLE_DIR`.
- **Termux's virglrenderer-android always decompresses DXT on the server and re-uploads with `glTexImage2D` into
  immutable compressed storage → GL_INVALID_OPERATION → every DXT texture black** (BAR's map tiles, minimap, unit
  skins). `tools/build-virgl.py` rebuilds virglrenderer 1.3.0 + libepoxy 1.5.10 with Termux's patches (pinned commit)
  and decompresses only when the host lacks S3TC, also recognizing ANGLE's per-format DXT extension names (upstream
  does not). Verified with a DXT1 test texture (`[255,0,0]` instead of `[0,0,0]`) and a textured map in game.
  Worth reporting to Termux.
- CPU rendering (llvmpipe, checkbox "Render on the CPU") works too: x0.70 speed, ~1 fps.

Emulator caveats
- (11:10) 3–4 fps, units invisible: both fixed in the afternoon session above.
- A host crash (PC restart) corrupted the emulator's data disk (kernel panic, ext4). Recovery: start the emulator once
  with `-wipe-data` (`Run in Emulator.bat -wipe-data`), then Install / Update again (~10 min, 4 GB download).
- Developer hook: long-press **GL check** = display + GPU server stay up for an hour without the game, for testing GL
  inside the container (`tools\container-shell.bat`).

## How the app works (one paragraph)

`LauncherActivity` → `GameService` (foreground). **Install**: `Installer` runs `libproot.so`/`libbusybox.so` straight
from the app's native-lib dir (the only place Android lets an app exec from), downloads the official Debian trixie
arm64 docker rootfs (layer digest read from the OCI manifest on GitHub, SHA-256 checked), extracts it with
`proot --link2symlink` + busybox tar (hard links → symlinks), runs `/opt/bardroid/setup-container.sh apt`
(SDL2/X11/OpenAL/fonts/xkb/Mesa pkgs/PulseAudio), installs **Mesa for Android containers** over Debian's Mesa,
downloads `recoil_2026.07.04_arm64-linux.7z`, then `pr-downloader` fetches `byar:test`, `byar-chobby:test` and one
map from BAR's own CDN (nothing of BAR's CC-BY-NC-ND art is bundled). **Play**: `XServer` starts
`com.termux.x11.CmdEntryPoint` (compiled into *our* APK) via `/system/bin/app_process` with `TMPDIR=<rootfs>/tmp`
so the socket is the container's `/tmp/.X11-unix/X0`; `GameActivity` (extends Termux:X11's `MainActivity`) shows the
display and handles touch/mouse/keyboard; `launch-bar.sh` runs inside proot: waits for the socket, points OpenAL
Soft's wave writer at the FIFO (→ `AudioPump` → `AudioTrack`), runs a one-time `glxinfo` probe, then
`spring --isolation --write-dir /root/bar skirmish.txt` (or `--menu rapid://byar-chobby:test`). Gamepad events are
intercepted in `GameActivity` and sent as `BARCTRL1|...` UDP packets to 127.0.0.1:28777 (UnderarmCape's controller
companion protocol).

## Laptop session, night (2026-10-25, 02:40–03:50) — history

Toolchain + build
- Nothing was installed on the laptop. Added `toolchain\env.bat` (process-local: JAVA_HOME, ANDROID_HOME,
  GRADLE_USER_HOME, ANDROID_EMULATOR_HOME, HOME/USERPROFILE/APPDATA/TEMP all redirected into `toolchain\`),
  `toolchain\install-toolchain.ps1` and the top-level `.bat` launchers. Google replaced `sdkmanager` with the
  "Android CLI" (`android.exe sdk install ndk/29.0.14206865 ...`, package names use `/`); the installer uses it with
  `--no-metrics`. The Android SDK terms were accepted on Kailil's go-ahead.
- termux-x11's native build assumes a Linux host. `patches/0002-lorie-windows-host-build.patch` (applied by
  `tools/fetch-termux-x11.*`; every change is inside `if(CMAKE_HOST_WIN32)` or host-neutral) adds: `git apply` instead
  of bash+GNU patch (with `recipes/fix-patch-headers.py` normalizing patches git rejects, and `--unidiff-zero`),
  host gcc from `$LORIE_HOST_CC` for `makekeys`, copies instead of symlinks (no Developer Mode needed), and a
  case-insensitivity fix (the NDK's `<xlocale.h>` resolved to X11's `Xlocale.h`).
- Native libs: AGP now strips `libXlorie.so` (21 MB → 3.5 MB; `ndkVersion` pinned in `app/build.gradle`); the prebuilt
  proot/talloc/busybox are excluded from stripping so they stay byte-identical to the Termux/Debian builds.

Bugs found and fixed
- **Any app update broke every container step**: `files/bin/proot` symlinks pointed into the old native-lib dir
  (Android moves it on each update). proot/busybox now run in place; assets and container scripts are refreshed
  before every install and launch. (Found on the emulator.)
- **The X server could never start**: `XServer` cleared the environment, so `app_process` had no BOOTCLASSPATH /
  ANDROID_ART_ROOT and died silently. Now inherits the app's environment. (Found on the emulator.)
- **Stop left proot running** (installer children were untracked): `Proc.killAll()` on Stop; an interrupted wait
  kills its child.
- busybox `tar` would have refused to run (bound as `/.bardroid-busybox`, "applet not found"); now `/busybox-bardroid`.
- Debian's `/usr/share/X11/xkb` is a symlink; the host-side X server now resolves symlinks inside the rootfs.
- Crashes on Android 9–12: `InputStream.readAllBytes()` (API 33) and `Build.SOC_MODEL` (API 31).
- `AudioPump.stop()` could leave a thread blocked opening the FIFO (two readers on the next game).
- The game screen stayed open after the engine exited; it now closes and the launcher comes back.
- Termux:X11's activities/receivers were exported (meant for the Termux app, another UID); now non-exported.
- First-run display defaults for a game: full screen, landscape, no extra-keys bar, screen kept on, "simulated
  touchscreen" (tap = click at the finger), X screen scaled to ~720p. All adjustable under Display prefs.

Emulator smoke test (Android 14 x86_64 with ARM translation; `tools\emulator-test.bat`) — passed:
- Launcher UI, device check, settings; specialUse foreground service; notification permission prompt.
- Debian rootfs download + SHA-256; proot starts from the native-lib dir (then stalls: proot cannot ptrace
  ARM-translated processes, an emulator limit).
- **Open risk closed: on Android 14, `app_process` with `CLASSPATH=<our base.apk>` runs `CmdEntryPoint` from our
  APK.** With an emulator-only x86_64 X server, the whole display path works: X server up, socket at the container's
  `/tmp/.X11-unix/X0`, ACTION_START reaches our non-exported receiver, `GameActivity` connects (60 Hz), full-screen X
  root window with the game defaults.
- Gamepad bridge: `BARCTRL1` packets at ~60 Hz on 127.0.0.1:28777; injected gamepad A → button bit 0, then released.
- Stop during install and during play kills X server + proot and closes the display. Audio FIFO is created.
- Not testable there: container (proot), apt, Mesa, engine, GL, audio playback.

Static checks of the container side (scripts kept in the session scratchpad; easy to redo with Python):
- All 37 packages in `setup-container.sh apt` exist in Debian trixie arm64. `p7zip-full` is now a transitional
  package for `7zip` 25.01, which still ships `/usr/bin/7z`.
- Every `DT_NEEDED` of the 9 ELF files in `recoil_2026.07.04_arm64-linux.7z` (spring: SDL2, X11, Xcursor, OpenAL,
  glibc) and of the Mesa tarball's 7 ELF files is provided by the container (base image + dependency closure of the
  apt list = 295 packages).
- The Mesa tarball carries `dri/kgsl_dri.so`, `dri/zink_dri.so`, Turnip (`libvulkan_freedreno.so` + ICD json) and
  `libgallium-26.2.0-devel.so`; it overwrites Debian's Mesa files in place as intended.
- glxinfo, vulkaninfo, pulseaudio (+ module-pipe-sink / module-native-protocol-unix), 7z, ldconfig, fc-cache are all
  in installed packages.

Debugging on the phone: the app writes `files/container.sh` before every install/launch, so
`bar-droid-app\tools\container-shell.bat` gives a root shell in the phone's container (or runs one command:
`container-shell.bat "glxinfo -B"`).

## Build / run (Windows laptop)

```
Install Toolchain.bat --accept-licenses   one time; ~1.5 GB into toolchain\ (Android SDK terms)
Build APK.bat                             emulator build (x86_64) -> apk\bar-droid-emulator-debug.apk
Run in Emulator.bat                       boots the emulator (first time ~1.8 GB download), installs + opens the app
Get Logs.bat                              launcher.log, infolog.txt, glcheck, pulse.log, logcat -> logs\device-<time>\
Build APK.bat phone / Install on Phone.bat   the arm64 phone build
Pair Phone.bat [pair-port code connect-port]  wireless adb over Tailscale (phone: Wireless debugging, needs Wi-Fi)
Get Logs.bat phone                            logs from the phone while the emulator also runs
```
Kailil's phone: Galaxy Z Fold7 (Snapdragon 8 Elite / Adreno 830, so the Freedreno/Turnip path), Tailscale name
`kailils-z-fold7` (100.103.32.18). No USB adb; wireless debugging over Tailscale only, and Android enables it only
while the phone is connected to some Wi-Fi (its own hotspot does not count; Wi-Fi without internet is fine). The
phone already lists `kaili@KAILILLAPTOP` under Paired devices, so usually only the connect port is needed:
`Pair Phone.bat - - <port>`. Samsung's Auto Blocker can block adb installs. Waiting for Kailil to be on Wi-Fi.
In the app: **Install / Update** (Debian + engine + BAR content, ~4 GB, ~10 min) → **Play vs AI**.
Native helper binaries: `tools/fetch-prebuilts.py <abi>` (proot, busybox, ANGLE) and `tools/build-virgl.py <abi>`
(virgl server); both run with the toolchain's Python inside `toolchain\env.bat`. Their output is committed under
`app/src/main/jniLibs/<abi>/`, so a normal build needs neither.
Toolchain pinned by termux-x11: AGP 9.3.1, Gradle 9.8.2 (wrapper), NDK 29.0.14206865, CMake 3.22.1, JDK 21.
One ABI per APK.

## Open risks (2026-10-26)
- RAM: Android logged low memory all through a spectated 8v8 (~1000 units); its killer has taken the game before.
  The `[perf]` minute line now has MemAvailable, SwapFree and the engine's resident size.
- Heat: after an hour the GPU is capped at 443-900 MHz of 1200 and the CPUs at ~2 GHz; `[perf]` shows when.
- BAR's saved games crash the engine when loaded, on Windows too (Gamepad section, "Busy scenes"): upstream.
- The explicit Present fence (`libbardroid_pace.so`'s ioctl answer) is new: watch for flicker or a stall on
  fold/unfold and in the floating window.
- The lobby runs without BAR's launcher behind it ("WrapperLoopback", below): some lobby features fail quietly.
- BAR's graphics presets in its settings menu undo the phone layer for the rest of that game ("medium" switches
  shadows, bloom, snow, distortion and decals back on); the next start resets them. They were not what slowed the
  last 8v8 (above): late games with ~1300 units run ~19 fps on a hot phone, GPU-bound at its thermal cap.

## Gamepad (2026-10-26)
Kailil (2026-10-26): "Do v0.8.5 1:1 as the developer game for skirmish and the lobby, plus the pad camera for online
and spectating"; no "controller not connected" indicator on Android; keep it cheap.

**Performance (2026-10-26).** Kailil: v0.8.5 "was working perfectly ingame", but fps dropped ("i neveer figured out
using codex how to get the usage down"); it was out of the builds (a019af7) until it was cheaper. The phone's log:
LuaUI garbage 79-268 MB/min with v0.8.5 against 0-44 MB/min on BAR's released game. Now packaged from BARGAMEPAD
branch **`controller/codex-v085-perf`** (sparse worktree `src\bar-codex-perf`; release branch untouched), same
behaviour and pixels. Laptop, v0.8.5 skirmish with the companion's scripted pad (`tools/profile-gamepad-game.ps1`):
all LuaUI garbage 10.5 → 0.83 MB/s, the hint runtime 1.10 → 0.35 ms/frame and 9.8 MB/s → 0.12, the controller
widgets together ~1.6 → ~0.8 ms/frame. What it was and what changed:
- The hint runtime's 25 Hz context snapshot copied the engine's command list (and per-unit command lists) out of
  the engine several times per poll: now cached until BAR's `CommandsChanged`/`SelectionChanged`.
- The hint panel was laid out and drawn with ~150 kB of new tables every frame: now a display list replayed until
  what it shows changes (drawn directly when it changes and while it fades in, re-recorded once a second), and the
  renderer/glyph code allocates nothing (5384 gl calls compared identical to the release branch).
- A resting stick read the camera state each frame only for the hidden debug panel.
- The build radial (RB) rebuilt its tables, text and BAR's unit cells in immediate mode every frame it was open
  (Kailil: 20-23 fps on opening, ~10 s to recover): now a display list, recorded once its inputs (options, selection,
  page, affordability, queues, progress, availability text, position, settings) held for a frame, replayed until one
  changes. Laptop (`-Radial`): 355 of 358 frames per open replayed, garbage while open 1.8 → 0.33 MB/s (as when
  closed), first-open worst frame 46 → 37 ms; its screenshot shows the same radial.
v0.8.5's own suite (`BARGAMEPAD scripts\codex-tests.ps1 -GameDir src\bar-codex-perf`): 20 pass + the 6 known
attempt-01 failures, as on the release branch. Profiling: `tools/profile-gamepad-game.ps1 [-Functions -Detail <widget>]`
(per widget, or every function of one widget with exact allocations); `-Released` measures BAR without v0.8.5.
Remaining controller costs (laptop): the camera widget ~0.4 ms/frame, 0.45 MB/s, spread over many functions
(selected-unit status panel, control groups, packet parsing).

**Stripped for the phone** (Kailil, 2026-10-26: "get rid of the debug stuff and the hints menu all together. and
remove bindings menu and UI ... its too clunky to use on mobile"; the hints were too small to read anyway):
`build-gamepad-game.py` turns the hints off (the runtime then polls nothing) and leaves out the bindings menu, the UI
layout editor, the SmartX audit and v0.8.5's tests (`MOBILE_LEFT_OUT`). Laptop: LuaUI garbage 0.67 MB/s. The phone
after the first optimization: LuaUI memory changes 20-79 MB/min (before 79-268; BAR's released game 0-44) and the
sim kept real time through a 31-minute skirmish, so the 15-30 fps Kailil sees is rendering: the potato pass.
BAR's own options widget re-applies its saved shadow setting at every start (`Set "shadows" config-parameter to 1`)
over our `Shadows = -1` (it saw a fresh springsettings.cfg each start, see "Overnight hardening"; launch-bar.sh now
sets ShadowQuality 0, which BAR's slider reads).

**Busy scenes (2026-10-26, measured on the Fold7 with simpleperf and /proc while Kailil played).** On BAR's Lowest
preset a base with ~200 wind turbines still ran 15-23 fps, so effects were not the limit. What was:
- CPU and GPU took turns: the engine's main thread sat in `IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID` (waiting for the GPU)
  43-58% of each frame and was busy only ~36%; the GPU, idle in between, read ~72% busy and its governor kept it at
  342-443 MHz of 1200. Cause: lfdevs Mesa's Present-fence path only keeps a third back buffer at swap interval 0, and
  our 30 fps cap was VSync (swap interval 2, `vblank_mode=3`). Now `vblank_mode=0` plus our own cap,
  `libbardroid_pace.so` (`tools/pace/pace.c`, `tools/build-pace.py`; LD_PRELOAD, sleeps after `SDL_GL_SwapWindow` to
  `BARDROID_FPS`). With `vblank_mode=0` alone the GPU ran at 832 MHz in a similar scene.
- After hours of play the phone was hot (skin 42 °C, thermal status 2): the GPU was capped at 607 MHz
  (`/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel` 8, `devfreq/max_freq`). Power per frame is what keeps the clocks: the
  cap matters, and potato mode should cut work and resolution.
- Simpleperf on the phone: `adb shell setprop security.perf_harden 0`, then from the shell
  `/data/local/tmp/simpleperf record --app com.underarmcape.bardroid -p <spring,proot,x11 pids> -e cpu-clock:u`
  (kernel samples are refused; `--app` alone only catches the Java process).
- Loading BAR saves crashed (SIGSEGV in "Loading Saved Game", no stack). **Not Android's** (2026-10-26, overnight):
  Kailil's save `Saves/20261026_063343.ssf` (controller game, Death Valley, vs BARb, frame 88559) crashes the
  Windows build of the same engine (2026.07.04, `spring.exe --isolation --write-dir build\profile\data <save>.ssf`)
  at the same point: access violation in spring.exe at frame 88559 right after "Loading Saved Game" (offsets from
  the image base: 0x965868, 0x9626f2, 0x5b3fd2, 0x535eae, 0xd5d099; no symbols). The controller game only changes
  LuaUI, so the synced state is BAR's own. An upstream report (Recoil/BAR) needs Kailil's go-ahead.
- **Still waiting on the GPU (spectating an 8v8, 226-418 units, 23-24 fps; 2026-10-26, with the pace cap):** the main
  thread is busy ~50% and blocked in `0x400c0907` 42%; GPU 342 MHz of 1200, 61-76% busy (no thermal cap); the prime
  cores (cpu6-7) idle at 1017 MHz, the main thread runs on cpu0-5. Its stack while blocked (read from
  `/proc/<pid>/mem` at the SP in `/proc/<pid>/task/<tid>/syscall`; simpleperf has no off-CPU events on this phone;
  walk the aarch64 frame records x29 -> {x29, x30}, libgallium has a symtab; a plain scan for code addresses mostly
  finds stale words): 24 of 30 samples `SDL_GL_SwapWindow` → `__glXSwapBuffers` → `loader_dri3_swap_buffers_msc` →
  `dri_flush` → `st_context_flush` → `tc_flush` → `_tc_sync` → `tc_batch_execute` → `__fd_resource_wait` →
  `fd_bo_cpu_prep` → KGSL wait, the rest in `_tc_sync`. So at every swap the driver waits for the GPU to finish with a
  resource the frame queued (likely this Mesa's Present-fence path waiting for the frame itself): CPU and GPU take
  turns, the GPU idles ~35% and its governor stays at the bottom clock. Ideas: less GPU work (MSAA was 4x until
  launch-bar.sh forced 0; shadows; terrain detail; features at any distance from Chobby's `FeatureDrawDistance =
  600000`), a Mesa that does not wait at the swap, ADPF hints. Kailil: a top-down camera runs much faster than a
  tilted one. A second 8v8 an hour later: 15 fps, blocked 51%, GPU capped at 443-525 MHz and CPUs at ~2 GHz (hot).
- **The swap wait's cause** (lfdevs Mesa PR #96 source): `fd_flush_resource` on KGSL CPU-waits for the frame
  (`FD_BO_PREP_READ`) unless the frontend uses the explicit Present fence, which `dri3_present_sync_init` enables
  only when `DMA_BUF_IOCTL_EXPORT_SYNC_FILE` fails with ENOTTY/ENOSYS. The Fold7's kernel supports it (KGSL attaches
  no fences, so the export is empty), the engine had no `present` thread. `libbardroid_pace.so` now answers ENOTTY
  for that ioctl (`BARDROID_PRESENT_FENCE=0` = off); lorie has the X server half (termux-x11 b36dac08). Check: a
  `present` thread in `/proc/<engine>/task/*/comm`, no `0x400c0907` waits in the main thread, no flicker.
  Result (Kailil: "HOLY SHIT THAT WORKED", spectating an 8v8 with 829 units, hot phone): `sprin:present0` runs, the
  main thread no longer waits for the GPU (0 of 200 samples, was 42-51%; 63% running), the GPU 78-91% busy at its
  thermal maximum (734-900 MHz, was stuck at 342), 28.8 fps over the minute, nearly every second at 30.
- **Phone graphics at every start** (`launch-bar.sh` `PHONE_GFX`, Kailil: "disable msaa on every graphics profile",
  "we can still cut more things"): no MSAA, no shadows, features drawn to 6000, GroundDetail 60, no water
  reflection/refraction passes, no engine grass or line smoothing, in springsettings.cfg and Chobby's game_settings;
  BAR's bloom/SSAO/distortion/snow/map edge extension widgets off; the lights' screen-space shadows 0 (in
  `LuaUI/Config/BYAR.lua`: BAR refuses `/option` from user widgets, "User widgets cannot control other widgets or
  execute remote code"). BAR's settings menu can change them until the next start.

**Pad as a mouse in the lobby** (Kailil: "just simple mouse movement, scroll and A and B as left and right click"):
`ControllerBridge.Mouse` (GameActivity `lobbyMouse`) is on while no game widget writes the hover file (older than
3 s: the lobby, loading screens): left stick moves the X pointer, right stick scrolls, A/B left/right button.
- **Why a developer game:** BAR Controller Support v0.8.5 (`C:\Tools\BARGAMEPAD`, branch
  `controller/codex-v085-release`) is BAR's own game with the controller added (new widgets, edits inside ten of BAR's
  widgets), ported onto BAR Release 2026.10.20-1 (`a61703336e`). BAR's user-widget sandbox (BAR PR #9547) blocks its
  socket and input emulation, so like on Windows it runs as BAR's developer game, "Beyond All Reason $VERSION", which
  the lobby plays with `gameConfigName = "byar-dev"` ("Beyond All Reason Dev"). Online games use BAR's released game.
- **The archive:** `tools/build-gamepad-game.py` packs only v0.8.5's added/changed files (`luaui/`, `controller-ui/`)
  into `assets/gamepad/gamepad.zip` plus a `modinfo.lua` that depends on "Beyond All Reason test-31691-a617033"
  (rapid tag `byar:git:a61703336e…`). The engine adds an archive's own files before its dependencies' (Recoil
  `CVFSHandler::AddArchiveWithDeps`, overwrite=false), so v0.8.5's files win. `Installer.installGamepadGame` downloads
  that release (setup step `gamepad`, ~4 MB beyond byar:test), unpacks the zip to `files/bar/games/BAR-gamepad.sdd`, and
  copies the three BAR icons v0.8.5 reuses from the downloaded pool (no BAR artwork in the APK). It runs at install and,
  for an app update, before the next lobby/skirmish start (status in the notification); failures leave singleplayer on
  BAR's released game. Launcher checkbox "Controller support v0.8.5 in singleplayer" (`Prefs.gamepadGame`, default on).
- **Set up like the Windows installer** (`launch-bar.sh`, `GAMEPAD_GAME=1`): lobby game byar-dev (chobby_config.json and
  `IGL_data.lua`), BAR's Build menu on and Grid menu off in `LuaUI/Config/BYAR.lua` (v0.8.5 drives the Build menu).
  No `devmode.txt` (only Chobby's developer buttons). Off again: both go back.
- **No indicator:** the shipped UI defaults turn v0.8.5's "companion status" panel off (the only Android change to it),
  and `ControllerBridge` streams packets from the moment the game screen opens (heartbeat every 100 ms, v0.8.5 calls the
  stream gone after 250 ms), pad or not, exactly as the Windows companion's `--codex` mode: raw axes, no Guide.
- **Online gamepad camera:** `ControllerBridge` writes `pad …` lines (only when the sticks change) into the touch log;
  `bardroid_touch.lua` moves the camera each frame with v0.8.5's camera constants (left stick pans, LT faster, right
  stick turns/zooms, LB+right stick tilts). Off in the controller game (v0.8.5 reads the pad itself).

## Phone requirements
Qualcomm Adreno 7xx/8xx (Snapdragon 8 Gen 2/3/8s Gen 3/8 Elite), 12 GB RAM, ~6 GB free, Android 10+.
Mali/Xclipse/Tensor: no Mesa path → the app's device check says so.

## Next steps (2026-10-26)
0. **Evening (Kailil away):** also not on the phone yet: the deferred-pass trims and fog-lines switch (see "Second
   optimisation search"); check late-game fps against the afternoon's, the infolog lines, and that shields and the
   radar/jammer placement previews look as before. **Afternoon run (Kailil away, phone off the home Wi-Fi):** builds 1884d80..93550e9 are not on the phone yet
   (`..\apk\bar-droid-phone-debug.apk` is current; install over adb when it is back). To check: joining a running
   game, the "Catching up" box within seconds (not minutes) and the picture frozen behind it; in a game too big to
   catch up, drawing back after a minute ("not gaining" in infolog); late-game fps with the sharpening pass and the
   jammed-unit tint off; `[perf]` lines now with the engine's memory. Unfolded resolution cap (887b97e) not judged
   yet. Ideas that need Kailil's call: more gameplay-information widgets off (Defense Range GL4, Sensor Ranges, Ecostats,
   BuildETA: CPU per frame), Outline Shader GL4 / Orb Effects / Fog Diagonal Lines (GPU), a lower resolution while the
   phone is hot (dynamic: the lorie pixel cap from Android's thermal status), MaxSounds lower (OpenAL mixing).
1. Kailil checks the overnight builds on the phone: BAR's interface at 2.0 folded and 1.3 unfolded (one LuaUI reload
   on fold/unfold), the top bar without Keys/Changes, finger twist and tilt in singleplayer (now the Spring
   camera), no flicker with the explicit Present fence, the lobby's Always One panel and 120% scale. New since:
   lock the phone mid-game and unlock (picture and sound back at once), drag the top bar's sliders and the
   settings' sliders with a finger, BAR settings (e.g. volume) kept after a restart.
2. **The lobby without BAR's launcher.** Chobby talks to BAR's PC launcher through `WG.Connector`
   (`libs/spring-launcher/luaui/widgets/api_spring_launcher.lua`: host/port from `sl-connection.json` in the write
   dir, `{"name":…,"command":…}` JSON lines over TCP) and `luamenu/widgets/sl_loopback.lua` (`WrapperLoopback`):
   OpenFile (web links), Download (with it on, maps and games too; "resource" files such as the OpenSkill ratings CSV
   only through it: "Download aborted (no wrapper, unsupported VFS type)" every start), ReadReplayInfo (Replays tab),
   ParseMiniMap (map thumbnails), StartNewSpring (games and replays on another engine), UploadLog, Discord.
   **Built overnight as `LobbyBridge`, launcher setting "Lobby bridge (beta)", off by default**: web links, game/map
   downloads through pr-downloader (`setup-container.sh` steps rapid/map), resource downloads by HTTP, replay info
   from the replay's header and start script. **Checked against the real lobby on the laptop**
   (`tools/lobby-bridge-test.ps1`: BAR's Windows engine runs byar-chobby:test in an isolated write dir, LobbyBridge on
   the JDK with stand-ins for Android and the container): it connects, the Replays tab lists Kailil's replays with
   engine, map, game time and both teams, the lobby's two resource downloads (widget manifest, skill ratings CSV)
   arrive, a web link goes to the browser, no lobby error. The map step (`setup-container.sh map`, pr-downloader in
   the container) ran on the phone: exit 0, the map in place (it downloads even a map already there; the lobby only
   asks for missing ones). Not yet in the phone's lobby: tick it, open the Replays tab, download a map, open a link;
   `bridge` lines in launcher.log. Thumbnails, other engines and Discord stay unanswered (the lobby does not wait for those).
3. Upstream, with Kailil's go-ahead (drafts ready in `docs/upstream/`): the save-load crash (Recoil/BAR); lfdevs Mesa: `dri3_dmabuf_sync_file_unavailable`
   takes the CPU-wait path on KGSL whenever the kernel supports `DMA_BUF_IOCTL_EXPORT_SYNC_FILE`, though KGSL never
   attaches fences to the dma-buf (our ioctl answer is the workaround); the ARM64 AI bug (RecoilEngine issue, then
   the CircuitAI patch), disclosing AI assistance per `AI_POLICY.md`.
4. 30 fps for hours: read the `[perf]`/`[bardroid-perf]` lines of long sessions; a potato/default switch in game.

## Licensing
Engine GPL-2.0+; BAR game code GPL-2.0; BAR art CC-BY-NC-ND 4.0 (never bundle, never re-encode; download from the
official CDN like the launcher does); termux-x11 `lorie` GPL-3.0 → this app is GPL-3.0; proot GPL-2.0; busybox
GPL-2.0; Mesa MIT; AngelScript zlib (the stub).
