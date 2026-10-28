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
- [ ] **Public icon.** A neutral icon of our own in `app/src/main/res` (no BAR artwork); Kailil's icon moves out of
      the repository into `C:\Tools\BARANDROID\personal\icon\` and is picked up by his own builds only
      (`local.properties`: `bardroid.personalIcon=<folder>`). Public and CI builds get the neutral one by default.
- [ ] **LICENSE** (GPL-3.0 text) at the top; NOTICE.md keeps the third-party parts.
- [ ] **Personal data out of tracked files.** Phone address, serial and Wi-Fi notes into `CLAUDE.local.md`
      (untracked, read by Claude Code beside CLAUDE.md); tools find the phone through `adb devices` or
      `BARDROID_DEVICE`.
- [ ] **Release signing.** `Build APK.bat phone release` signs with a keystore named in `local.properties`
      (`bardroid.keystore`, passwords from the environment), never committed; without one it stops and says so.
      `versionName`/`versionCode` from one place (`gradle.properties`), the APK named with the version.
- [ ] **A publish check** (`tools/publish-check.ps1`): fails on BAR artwork, personal data, credentials, files over
      50 MB, a missing LICENSE, or a version without a CHANGELOG entry. Run before every release.
- [ ] **History.** The icon and the personal data are in old commits. Kailil decides: publish a fresh history
      (one commit; the effort record stays in docs/WORKLOG.md and docs/HISTORY.md) or rewrite this one
      (`git filter-repo`) to drop them. Either way `tools/publish-check.ps1` runs over what goes out.

### For players
- [ ] README rewritten for players first: what works (lobby, online, skirmish, spectating, gamepad, keyboard and
      mouse), which phones, download from Releases, install, first start (4 GB from BAR's servers), touch controls,
      known limits, where the logs are, how to report a problem. Developers' material moves to docs/.
- [ ] docs/TOUCH.md: the touch controls and the spectator tools (follow, presets, 1st person, Tune), with pictures
      from the laptop tools (`tools/ui-screenshot.ps1`), no BAR artwork beyond screenshots of the game.

### For developers (BAR's devs first)
- [ ] docs/BUILDING.md: toolchain, builds, phone install, the laptop checks; the launchers' Linux equivalents where
      they exist.
- [ ] docs/ARCHITECTURE.md: CLAUDE.md's architecture and key files written for people; CLAUDE.md keeps the AI
      assistant's working rules and points there.
- [ ] CONTRIBUTING.md: online play must keep working (no engine changes, no modrules, no synced changes), never
      bundle BAR content, the checks to run, upstream reports need an accepted issue and disclose AI assistance.
- [ ] CHANGELOG.md, from docs/HISTORY.md and the commit log, one section per version.
- [ ] `.github/ISSUE_TEMPLATE/bug.md` (phone, Android version, "Share logs" output) and a PR template.
- [ ] `.github/workflows/build.yml`: the phone APK on Linux (Gradle and the committed prebuilts; Termux:X11 fetched
      and patched), the luacheck lint and the Java unit checks; the APK as an artifact. Untested until pushed.

### Hardening and overhead (the spectator tools first)
- [ ] Measure what `bardroid_spectate.lua` costs per frame (laptop profiler in a replay: idle, following a unit, a
      group, 1st person) and cut anything above noise: `layout()` on every DrawScreen, `GetConfigFloat` on every
      pinch frame, tables made per frame (`fpFor`, presets), `GetVisibleUnits` per tap, the group refresh.
- [ ] The same on the phone: the replay benchmark with the spectator widget on and off.
- [ ] Bugs found on the way, each with a check in `tools/spectate-test.ps1` or `tools/laptop-tests.ps1`.

## Releasing (once the blockers are done)

1. `tools/laptop-tests.ps1` passes; the phone build played on a phone (lobby, online game, skirmish).
2. Version in `gradle.properties`, a CHANGELOG entry.
3. `Build APK.bat phone release` with the release keystore.
4. `tools/publish-check.ps1`.
5. Kailil pushes and makes the GitHub release with the APK and the CHANGELOG text.
