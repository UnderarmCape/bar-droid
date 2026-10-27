# Updates: BAR Droid keeps itself current the way BAR's PC launcher does

Goal (Kailil): when BAR updates for PC, the app picks the update up on its next start and applies its Android layer
on top, with nobody stepping in, at least until BAR ships Android builds of its own. The engine binary stays the
unmodified official Recoil build, because online play needs the engine BAR's servers run.

Code: `Updater.java` (new), called from `GameService.play()` / `install()`; state under `files/update/`.

## What BAR's PC launcher does (researched 2026-10-26)

Source: `spring-launcher` (github.com/beyond-all-reason/spring-launcher, `src/`) with BYAR-Chobby's `dist_cfg/`, and
the live config https://launcher-config.beyondallreason.dev/config.json (read on 2026-10-26).

- **Config**: every run of its wizard (the Update/Start button) GETs `config_url` with a 5 s timeout, no ETag
  (`launcher_wizard.js` `generateSteps`). It rewrites its cached `config.json` only when the content changed
  (`launcher_config_update.js`); offline it logs the error and carries on with the cached copy, then the bundled one.
- **Setup**: the first setup for the platform, i.e. `manual-linux` ("Alpha") on Linux. Today it says:
  `launch.engine = recoil_2026.07.04`; the engine as a resource
  `https://github.com/beyond-all-reason/RecoilEngine/releases/download/2026.07.04/recoil_2026.07.04_amd64-linux.7z` →
  `engine/recoil_2026.07.04`; `downloads.games = ["byar:test", "byar-chobby:test"]`; `start_args = --menu
  rapid://byar-chobby:test`; `launch.springsettings = {RapidTagResolutionOrder: "repos-cdn.beyondallreason.dev;
  repos.beyondallreason.dev"}`; `env_variables` = the three `PRD_*` variables; top-level `json_files` holds
  `chobby_config.json` (server4.beyondallreason.info:8200, game `byar`). There is an "Engine Test" setup
  (`recoil_2026.09.01`) for testers; we follow Alpha, as the PC launcher does by default.
  There is no arm64 setup, but every Recoil release so far also ships `recoil_<ver>_arm64-linux.7z`
  (checked: 2026.07.04, 2026.09.01).
- **Engine**: a resource is skipped when its destination folder exists (`http_downloader.js`), so a new engine
  version is a new folder beside the old ones. It extracts into a temp folder and renames it on success. Old engines
  are never deleted. The engine to start is `launch.engine`.
- **Games**: `pr-downloader --filesystem-writepath <dir> --download-game byar:test --download-game byar-chobby:test`
  on every run (`prd_downloader.js`), env from `env_variables`. pr-downloader fetches `versions.gz` every run (ETag),
  fetches only pool files that are missing, and renames `packages/<md5>.sdp` into place only after the whole package
  downloaded (`Sdp.cpp`): an `.sdp` present means the package is complete. Exit 0 = ok, 2 = a download failed,
  5 = disk too full.
- **Files**: `json_files` are rewritten on every run. `springsettings.cfg`: `default_springsettings` fill missing keys,
  `launch.springsettings` always overwrite, on every start.
- **Failure**: a failed engine or game download stops that run (no start); the user can untick "check for updates" to
  start what is installed. There is **no rollback**. `auto_download` is dead code (the user clicks).
- The launcher also updates itself (electron-updater). BAR Droid's equivalent would be a new APK: out of scope.

## What BAR Droid does on every start

Where: `GameService.play()` for the lobby (the app icon) and skirmish, after `refreshHostFiles()` and the controller
game install, before `writeGameFiles()`. Status goes through `setStatus` ("update: …"), so it shows on the
notification and on the splash (`StartActivity` prints the status line under BAR's icon and waits for the game screen
as long as the update runs). The Install / Update button runs the same check after the install, even with automatic
updates off.

1. **Config** — GET the launcher config (5 s connect / 10 s read). Pick setup `manual-linux`, else the first `linux`
   setup with `downloads.games`. Cache it as `files/update/launcher-config.json` (used when offline). Offline or bad
   JSON: log, keep what is installed, start.
2. **Engine** — version from `launch.engine` (`recoil_<ver>`), URL from the resource with destination
   `engine/recoil_<ver>`, with `_amd64-linux.7z` replaced by our ABI's archive (`arm64-linux` on phones). Accepted
   only from `https://github.com/beyond-all-reason/RecoilEngine/releases/download/` and with a version matching
   `[0-9A-Za-z._-]+`; anything else is logged as an error and ignored. A new version is downloaded (resumable) and
   extracted by `setup-container.sh engine` into `engine/recoil_<ver>.new`, which must hold `spring` and
   `pr-downloader` and pass `spring --version`; then it is renamed to `engine/recoil_<ver>`, beside the old one.
   Download or extraction failure: logged, the old engine stays. A partial download resumes at the next start; a whole
   archive that failed to extract is deleted (there is no checksum to tell a damaged one), so the next start fetches
   it again. Checked on the Fold7 with 2026.09.01 under a scratch name (2026-10-26).
3. **Game and lobby** — the rapid tags of `downloads.games` (today `byar:test`, `byar-chobby:test`; `Prefs.gameTag` /
   `lobbyTag` follow them). Fast path, so an unchanged start costs two small requests instead of a pr-downloader run
   in proot: GET `<repo>/versions.gz` with the saved ETag (304 = unchanged), read the tag's md5, compare with the tag in
   the local `rapid/<host>/<repo>/versions.gz` (hosts in `RapidTagResolutionOrder` order) and check that
   `packages/<md5>.sdp` exists. Otherwise `setup-container.sh rapid <tag> <engine>` (pr-downloader of the current
   engine, only missing files; progress on the splash). Before the run the repo's `versions.gz` files are copied
   aside; when pr-downloader fails or the tag's `.sdp` is missing afterwards, they are put back, so the tag keeps
   pointing at the complete package it had (a half-downloaded update never breaks the lobby).
4. **Android layer** — re-applied on every launch, after the update (see the table below), each tweak checking that
   its target still exists.

## Rollback

`files/update/state.properties` keeps the **current** set (engine version + md5 of each tag) and the **last good**
set (the set of the last launch that did not fail fast), plus `files/update/good/<host>/<repo>/versions.gz`: the
rapid index of the last good launch. Rapid packages are content-addressed and never deleted, so pointing a tag back at
an old package is just restoring its `versions.gz`.

- The first check snapshots what is installed as the last good set.
- An update that changes the set marks it **pending**.
- After the engine exits (`GameService`, not when the player pressed Stop or closed the app):
  - pending and **failed fast** (exit code ≠ 0 within 120 s, and no game frame in `infolog.txt`: a game or a saved
    game that ran and then crashed is not a failed start) → **rollback**: the current set goes on the bad list,
    the engine goes back to the last good version, the good `versions.gz` files are restored, and the game starts once
    more right away on the old set (same X server and game screen). Logged as an error.
  - pending and not failed fast → the set becomes the last good set; engine folders other than the last good and the
    one before it are deleted.
  - not pending → nothing changes (the existing "lobby failed fast → open the launcher" rule still applies).
- The bad list holds whole sets (engine + md5s, last 5). An update that would recreate a bad set is not applied; as
  soon as BAR moves any part (byar:test moves several times a day), the new set is tried. So a broken BAR version
  costs at most one failed launch per new set, and the engine is never blocked for good.
- Caveat: while the app sits on an older engine, online battles hosted on BAR's new engine cannot be joined
  (engine mismatch). Skirmish and the lobby work. The loud log says so.

Automatic updates off (launcher checkbox "Update BAR at every start"): no config fetch, no pr-downloader; the app
starts the current set (the engine of the last update, or the build's pinned `Prefs.engineVersion` on a fresh
install). Only the local integrity check runs (a tag whose `.sdp` is missing goes back to the good index).

## The Android layer, and how each part checks its target

| Part | Where | Re-applied | Target check (miss = loud) |
| --- | --- | --- | --- |
| `springsettings.cfg` (Android keys) | `Installer.writeGameFiles`: the existing file is kept (BAR's and the player's settings), the template's missing keys added, the `ALWAYS` keys set | every launch | after an engine update, `spring --list-config-vars` of the old and new engine: a key of our template the old engine knew and the new one does not is an error |
| Phone graphics `PHONE_GFX` (no MSAA, shadows, far features, water passes, engine grass, line smoothing; Spring camera; VSync off) | `launch-bar.sh`: `springsettings.cfg` and the lobby's `game_settings` in `IGL_data.lua` | every launch | set, or appended when missing; the lobby's copy where it has the key |
| BAR's full-screen effects off (bloom, SSAO, distortion, snow, map edge extension); top bar Keys/Changes off; lights (Deferred rendering GL4), decals, AO plates, map grass, Commands FX, Contrast Adaptive Sharpen, Jammed Units Highlight off; Fog Diagonal Lines GL4 off while `AdvMapShading` is 0 (lobby's game_settings, else springsettings; marker `.bardroid-fog-lines-off`); Show Builder Queue off (the app's `bardroid_queue.lua` instead); the classic Minimap instead of the Picture-in-Picture Minimap | `launch-bar.sh` `widget_order`, `LuaUI/Config/BYAR.lua` | every lobby/skirmish start | a missing entry is inserted; not set afterwards = miss |
| Lights' screen-space shadows 0 | `launch-bar.sh`, BYAR.lua `["Deferred rendering GL4"]` | every lobby/skirmish start | the widget's saved data without `screenSpaceShadows` = miss |
| Interface scale per Fold screen (2.0 cover, 1.3 inner, 1.0 cover upright) | `launch-bar.sh` at start; `bardroid_touch.lua` on fold/unfold (one LuaUI reload) | every launch / screen change | set or appended (`tools/touch-widget-test.ps1`) |
| Lobby: split panels Always One, interface 120% | `launch-bar.sh`, `IGL_data.lua` | every lobby start | not set afterwards = miss |
| BAR's `launch.springsettings` | `Updater.applyLauncherSettings` | every launch | keys our layer does not set are added; where ours differ, ours win (logged) |
| `files/bar/bitmaps/projectiletextures/wakegrey.tga` (transparent: no ship wakes) | `Installer.writeNoWakes` | every launch | - |
| `LuaMenu/Widgets/bardroid_lobby_touch.lua`; `loadLocalWidgets = true` in `LuaMenu/Config/IGL_data.lua` | `Installer.writeGameFiles`; `launch-bar.sh` | every launch; every lobby/skirmish start | not set afterwards = miss |
| `bardroid_touch.lua`, `bardroid_queue.lua`, `bardroid_chat.lua` and `bardroid_info.lua` widgets (BAR's "Info" off in `BYAR.lua`) | `Installer.writeGameFiles` | every launch | after a game, `launch-bar.sh` greps infolog for errors of the widget |
| `chobby_config.json` | `launch-bar.sh` (lobby) | every lobby start | from BAR's `json_files` (saved by the update check as `.bardroid-chobby_config.json`), `"game"` set to `byar`/`byar-dev`; no `"game"` key = miss |
| Resolution limiter off | `launch-bar.sh`, `LuaMenu/Config/IGL_order.lua` | every lobby start | entry missing → inserted; still not `= 0` = miss |
| `drawAtFullSpeed` on (once) | `launch-bar.sh`, `LuaMenu/Config/IGL_data.lua` | until done | no `drawAtFullSpeed` in the file = miss (marker not set) |
| `gameConfigName` | `launch-bar.sh`, `IGL_data.lua` | every lobby/skirmish start | not set afterwards = miss |
| Build menu / Grid menu order (controller game) | `launch-bar.sh`, `LuaUI/Config/BYAR.lua` | every start | not set afterwards = miss |
| Container environment (Mesa, SDL, OpenAL wave writer, `PRD_*`, `libasarm64.so` preload) | `launch-bar.sh`, `Prefs.putGpuEnv` | every launch | none to check; a new engine that breaks it fails fast and rolls back |

A miss is printed as `[launch] !!! ANDROID LAYER: …` (in `files/logs/launcher.log` with all child output), written
to `files/bar/logs/android-layer.txt`, logged again by the app as an error (logcat `BarDroid/update`) and shown in
the launcher's status line until a launch has no miss. Nothing is skipped silently.

## Not automated, on purpose

- **The controller game** (BAR Controller Support v0.8.5 on BAR `byar:git:a61703336e`, `Installer.installGamepadGame`)
  stays pinned: the updater never touches it. It runs on whatever engine is current; if a new engine breaks it, the
  failure shows (it is not rolled back unless the launch was the first one after the update).
- The PC launcher's `pool` seed (`pool-init…/data.7z`, optional) and `default_springsettings` (PC graphics defaults
  that would overload a phone): skipped.
- Mesa, the Debian container and the APK itself: they change with app builds, not with BAR.

## State files

- `files/update/state.properties` — current / good / previous engine, md5s, pending flag, bad sets, ETags, last check.
- `files/update/launcher-config.json` — the last launcher config fetched.
- `files/update/good/…`, `files/update/pre/…` — `versions.gz` copies (last good launch; before a pr-downloader run).
- `files/update/config-vars-<ver>.txt` — config keys each engine knows.
- `files/bar/.bardroid-chobby_config.json` — BAR's `chobby_config.json` from the config.
- `files/bar/logs/android-layer.txt` — the last launch's Android layer misses.
