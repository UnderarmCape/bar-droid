# Contributing

Thanks for helping BAR run on phones. The author does not plan to maintain this project: it is meant for BAR's
developers and community to take on (fork it, or ask for the repository to be handed over), with engine-side
performance and touch controls the open areas ([docs/HELP-WANTED.md](docs/HELP-WANTED.md)). A few rules keep the app
as it is safe for online play and for BAR's content, then the checks to run.

## Rules

- **Online play must keep working.** The engine is BAR's official Recoil build, unmodified, pinned to the version
  BAR's servers run. Changes live on the app side (Java, the container scripts, the X server patches) and in BAR's
  user layer: LuaUI widgets and settings the app puts in place at every start (`launch-bar.sh`, listed in
  [docs/UPDATES.md](docs/UPDATES.md)). No engine rebuilds, no modrules, no synced gadgets, nothing that would make a
  phone's game differ from everyone else's.
- **Never bundle or re-encode BAR's content** (game, maps, artwork: CC BY-NC-ND). The app downloads it from
  `repos-cdn.beyondallreason.dev` / `files-cdn.beyondallreason.dev` on the device. No BAR artwork in the repository,
  icons included (`tools/publish-check.ps1` fails on pictures outside the allowed places).
- **Licence:** the app is GPL-3.0-or-later ([LICENSE](LICENSE)); third-party parts are listed in
  [NOTICE.md](NOTICE.md). New third-party files need their licence beside them and a line there.
- **Upstream reports** (RecoilEngine, CircuitAI, Termux:X11, Mesa) go through an accepted issue first; Recoil's
  `AI_POLICY.md` asks for AI assistance to be disclosed. Drafts live in [docs/upstream/](docs/upstream/).
- **AI assistance:** much of this project was written with Claude Code ([docs/WORKLOG.md](docs/WORKLOG.md)). Say so
  in a pull request when an AI helped with it.

## Checks

On Windows with the toolchain set up ([README.md](README.md) "Build"):

- `powershell -ExecutionPolicy Bypass -File tools\laptop-tests.ps1`: every check that needs no phone (about 5
  minutes), including the Lua lint. Run it before every pull request.
- Touched a widget? Its own test too: `tools\touch-widget-test.ps1` (the touch camera), `tools\spectate-test.ps1`
  (spectating by touch), `tools\lobby-touch-test.ps1` (the lobby). Each starts BAR on the laptop.
- On a phone: `"Build APK.bat" phone`, `"Install on Phone.bat"`, then play: the lobby, an online game, a skirmish,
  fold/unfold on a foldable. `"Get Logs.bat" phone` or **Share logs** in the app collects the logs.
- Performance: `tools\phone-bench.ps1` measures BAR's benchmark scenario (or a replay) on a hot phone; compare
  before and after.

## Reporting a problem

Open an issue with the phone model, its Android version, what happened, and the zip from **Share logs** (launcher
screen). The app's own log is `files/logs/launcher.log`, the game's `files/bar/infolog.txt`.
