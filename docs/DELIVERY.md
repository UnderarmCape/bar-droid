# Delivery: from this checkout to a public GitHub release

Kailil (2026-10-28): make the project easy to hand to BAR's developers and to anyone who wants to download and play
BAR on Android from GitHub, "so when we are ready to publish its simple to do so. even as we expand features".
This file is the backlog for that; each item is done in a small tested commit and ticked here. Nothing is pushed,
published or posted without Kailil.

## Where it stands (audit, 2026-10-28)

- Small and self-contained: 174 tracked files, 14.8 MB (the largest is the emulator's ANGLE, 6 MB). Prebuilt
  helpers are committed with the tools that rebuild them; BAR's content is never in the repository or the APK.
- README.md already explains the app, the phone requirements, the build and the checks.
- Blockers for a public release:
  1. **The app icon** is Kailil's edit of BAR's launcher icon (CC BY-NC-ND): it must not be in a published APK, and
     the two PNGs are tracked, so also not in a published repository (or its history).
  2. **No LICENSE file**, although README says GPL-3.0-or-later (required anyway: the app embeds Termux:X11's GPL-3
     `lorie` module).
  3. **Personal data in tracked files**: the phone's Wi-Fi address and serial, the home Wi-Fi's name (CLAUDE.md,
     HANDOFF.md) and the address as a default in `tools/phone-bench.ps1`.
  4. **Release signing**: release builds use the public debug key (`app/bardroid-debug.jks`). Fine for a test build,
     wrong for a release others update from.
- Missing for others: a players' page (download, install, first run, known limits), a developers' page (build,
  architecture, tests, rules such as online-safe only), CHANGELOG, CONTRIBUTING, an issue template that asks for the
  logs, and CI that builds the APK.

## Backlog (in order)

### Blockers
- [x] **Public icon.** The project's own icon (`res/drawable/ic_fg.xml`, a unit marker in a ring); Kailil's icon
      lives in `C:\Tools\BARANDROID\personal\res` and is added to his builds only (`local.properties`:
      `bardroid.personalRes`); `-PbardroidPublic` or no such folder: the public icon.
- [ ] **App name.** The app is called "Beyond All Reason". For a public download, Kailil decides (perhaps with BAR's
      team): keep it, or "BAR Droid" with BAR named in the description.
- [x] **LICENSE** (GPL-3.0 text, as README already said) at the top; NOTICE.md keeps the third-party parts.
      **Kailil:** HANDOFF had the file as the author's to add; confirm GPL-3.0-or-later (or `git revert c942753`).
- [x] **Personal data out of tracked files.** Phone address, serial and Wi-Fi notes in `CLAUDE.local.md`
      (untracked, read by Claude Code beside CLAUDE.md); `tools\phone-bench.ps1` finds the phone through
      `-Device`, `BARDROID_DEVICE`, `..\phone-device.txt` or the one device adb lists (toolchain.ps1
      `Get-PhoneDevice`).
- [x] **Release signing.** `Build APK.bat phone release` signs with a keystore named in `local.properties`
      (`bardroid.keystore`, passwords from the environment), never committed; without one it stops and says so.
      `versionName`/`versionCode` from one place (`gradle.properties`), the APK named with the version; release
      builds always have the public icon. Tested with a throwaway key. **Kailil:** make the real key once
      (docs/BUILDING.md "Releasing") and keep it safe.
- [x] **A publish check** (`tools/publish-check.ps1 [-Apk <release.apk>]`): fails on pictures outside the allowed
      places, private data (the terms in `..\worklog-redact.txt`, the phone, home-network addresses, profile paths,
      e-mail addresses), keys and logins, files over 50 MB, a missing LICENSE, a version without a CHANGELOG entry,
      an APK with Kailil's icon or the debug key, and reports what old commits still hold. Run before every release.
- [ ] **History.** The icon and the personal data are in old commits. Kailil decides: publish a fresh history
      (one commit; the effort record stays in docs/WORKLOG.md and docs/HISTORY.md) or rewrite this one
      (`git filter-repo`) to drop them. Either way `tools/publish-check.ps1` runs over what goes out. The commits
      also name Kailil's e-mail address (the check's NOTE): GitHub's noreply address for what goes out, or keep it.

### For players
- [x] README rewritten for players first: what works (lobby, online, skirmish, spectating, gamepad, keyboard and
      mouse), which phones, download from Releases, install, first start (4 GB from BAR's servers), touch controls,
      known limits, where the logs are, how to report a problem. Developers' material moved to docs/BUILDING.md.
- [ ] Screenshots for the README (the touch bar while spectating, 1st person, the lobby), from the phone or
      `tools/ui-screenshot.ps1`: Kailil picks; screenshots of the game only, no other BAR artwork.

### For developers (BAR's devs first)
- [x] docs/BUILDING.md: toolchain, builds, phone install, the laptop checks, releasing; the Linux equivalents where
      they exist.
- [x] docs/ARCHITECTURE.md: CLAUDE.md's architecture and key files written for people; CLAUDE.md keeps the AI
      assistant's working rules and points there.
- [x] CONTRIBUTING.md: online play must keep working (no engine changes, no modrules, no synced changes), never
      bundle BAR content, the checks to run, upstream reports need an accepted issue and disclose AI assistance.
- [x] CHANGELOG.md, from docs/HISTORY.md and the commit log, one section per version.
- [x] `.github/ISSUE_TEMPLATE/bug.md` (phone, Android version, "Share logs" output) and a PR template.
- [x] `.github/workflows/build.yml`: the phone APK on Linux (Gradle and the committed prebuilts; Termux:X11 fetched
      and patched, `-PbardroidPublic`) and the luacheck lint; the APK as an artifact. **Untested until pushed**: the
      first run on GitHub may need fixes. `gradlew` and `tools/fetch-termux-x11.sh` are executable in git now.
      Reviewed 2026-10-28: the native build needs nothing beyond the runner image (Termux:X11's own workflow builds
      the same code on ubuntu-latest with nothing installed: bison, gcc, patch, Python are there); actions at the
      versions Termux:X11's workflow uses now (checkout v7, setup-java v6, upload-artifact v7), the Gradle wrapper
      jar validated before it runs (a pull request could swap it), the token read-only.
- [x] The Java checks (downloader, settings merge, updater rollback) in CI: `tools/java-checks.sh` (passes under
      the portable Git's sh on the laptop).

### Hardening and overhead (the spectator tools first)
- [x] Measure what `bardroid_spectate.lua` costs per frame (`tools/spectate-test.ps1 -Cost`: off, the bar, following,
      group, 1st person) and cut it: the bar into a display list (0.43 → 0.06 ms, 54 → 4 KB a frame), 1st person
      without per-frame tables (0 KB); HISTORY.md "Overnight". Left as they are (measured or rare): `GetVisibleUnits`
      per tap, the group refresh twice a second, the camera state read each frame while following.
- [x] `bardroid_touch.lua`: measured before at ~0.08 ms a frame (HISTORY.md, 2026-10-27 afternoon);
      `GetConfigFloat` per pinch frame is one engine call, left as it is.
- [x] On the phone: a replay smoke run of the new build (x1.00, ~30 fps, 905 units, no widget errors). The widget on
      against off was not run: its cost (0.01-0.1 ms a frame) is far below the benchmark's run-to-run noise.
      `WorkerThreadCount` 7 (the research batch's one lead) checked in three alternating pairs: no gain on a hot
      phone, 4 stays (HISTORY.md "Overnight").
- [ ] Bugs found on the way, each with a check in `tools/spectate-test.ps1` or `tools/laptop-tests.ps1`. Night of
      2026-10-28: two in tonight's own caching (fixed, bdaae2e); the phone's launcher logs (58,000 lines, Kailil's
      games and tonight's runs) hold no error from the app or its widgets, only BAR's and the engine's own warnings;
      the input-source code (touch/mouse/keyboard/pad for the spectator tools) reviewed, nothing found; README's
      launcher labels match the app's. `tools/publish-check.ps1` reviewed: its home-network address check never
      matched (git grep's ERE has no `\d`), an allowed e-mail address hid a private one on the same line, the history
      check missed other letter cases and commit messages, and the APK check passed when the debug key could not be
      read; fixed, `-SelfTest` (in laptop-tests) runs the patterns through git grep over planted data, and the check
      notes the e-mail address the commits name (Kailil: GitHub's noreply address, or keep his).
      `tools/worklog.py` reviewed: run from plain PowerShell (no git on PATH) it counted 0 commits and said nothing,
      so WORKLOG.md showed "Commits 0"; it now finds the toolchain's git as env.bat does, and without any git says so
      and writes "-". Cron-fired turns are rightly not counted as Kailil's messages. `bardroid_players.lua` reviewed:
      it, the chat widget and the benchmark widget timed with `os.clock` (CPU time in standard Lua on Linux), moved to
      `Spring.GetTimer`; measured on the phone afterwards, the engine's `os.clock` keeps real time (x1.00): no bug,
      one timer in all widgets now.
      `tools/spectate-test.ps1` failed ("a replay that never starts playing"): it took BAR's newest replay, one from
      2026-10-13 that never leaves its first frame on the laptop; it and `fp-tuner.ps1` now choose from the tools'
      copies too (`toolchain.ps1` Get-ReplayFiles), so the phone-recorded 8v8 is picked: all pass.
      `bardroid_minimap.lua` reviewed: the suspicion that its in-memory size would hide a size the player sets in
      BAR's settings was wrong (BAR's own save replaces the overlay); touch-widget-test now checks that such a size
      stays (passes; a "fix" that followed BAR's value broke the shrinking: BAR takes the overlay 0.25 s late).
      `tools/phone-bench.ps1` guarded: it stops on a locked phone (`dumpsys trust` deviceLocked) before warming up
      and before the measured run, and records no run whose game ran hidden ("game screen hidden" before the results,
      `toolchain.ps1` Test-BenchHidden: today's 21 runs from the phone's log sorted right, the seven hidden ones too). `Build APK.bat` reviewed: an
      empty `bardroid.keystore=` passed its key check and built an unsigned APK named like a release, and a build
      without an APK (or a failed copy) still reported one; fixed (tested: no key and an empty key refuse, a
      throwaway key builds and passes `publish-check -Apk`), Gradle names a keyless release `-unsigned.apk`, and the
      tool prints the exact publish-check command. Line endings checked: `.gitattributes` keeps `.bat` CRLF and the
      container's `.sh` LF for any checkout, no binary is taken for text, every `.ps1` is ASCII (PowerShell 5.1).

## Releasing (once the blockers are done)

1. `tools/laptop-tests.ps1` passes; the phone build played on a phone (lobby, online game, skirmish).
2. Version in `gradle.properties`, a CHANGELOG entry.
3. `Build APK.bat phone release` with the release keystore.
4. `tools/publish-check.ps1`.
5. Kailil pushes and makes the GitHub release with the APK and the CHANGELOG text.
