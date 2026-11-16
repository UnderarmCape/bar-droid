# Upstream reports: drafts

Not posted. Each one needs Kailil's go-ahead, and he posts it (or says to). The projects ask for an issue before a PR
and for AI assistance to be disclosed (RecoilEngine `AI_POLICY.md`); every draft ends with that line.

Testing a change to BAR's own files on the dev phone (the `bar-*` drafts): the release's rapid pool file of each file
(`files/bar/pool/<md5[:2]>/<md5[2:]>.gz`, the md5 from the release's `packages/<id>.sdp`) is backed up, overwritten with
the patched file gzipped, and put back after the test, its content's md5 checked against its name. The engine reads a
pool file only up to the size the package lists, so the test copy must be the original's exact byte size: the patch's
code with comment lines dropped and spaces added at the end. A longer copy is cut short and the widget fails to load
("unexpected symbol near '<eof>'"; the pregame test's first run, 2026-11-12). Every `bar-*` patch here makes its files
longer (2026-11-12, measured against test-31836-b250a16); their tests used same-size copies.

Refreshed 2026-11-15 against test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of that day: every `bar-*`
patch applies with `git apply` as it is (no offsets), its paths in the repository's case (`luaui/Widgets/`,
`luaui/Include/`; the release's pool lists them lower case, and `git apply` on a case-sensitive checkout missed them),
every patched file parses (luacheck). Made by the scratchpad's refresh: the release's files, the change made again where
BAR moved the code (Settings' config reads into `options/model.lua`, the tooltip's text measured as `text`, the
wind's tooltip set in `setWindTooltip`), diffed back. Their dev-phone tests are from before the refresh.

| Draft | Where | Attach |
| --- | --- | --- |
| [lfdevs-mesa-kgsl-present-fence.md](lfdevs-mesa-kgsl-present-fence.md) | github.com/lfdevs/mesa-for-android-container issues | nothing (numbers are in the text) |
| [recoil-arm64-barb-angelscript-stub.md](recoil-arm64-barb-angelscript-stub.md) | github.com/beyond-all-reason/RecoilEngine issues, then the CircuitAI patch | the log lines; later `patches/circuitai-cmake-arm64-linux.patch` |
| [recoil-save-load-crash.md](recoil-save-load-crash.md) | github.com/beyond-all-reason/RecoilEngine issues (or BAR's Discord bug channel first) | Kailil's save `Saves/20261026_063343.ssf` |
| [recoil-compresstextures-fbo.md](recoil-compresstextures-fbo.md) | github.com/beyond-all-reason/RecoilEngine issues | an infolog with the lines; a screenshot of the black icons |
| [bar-topbar-warning-banner.md](bar-topbar-warning-banner.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_top_bar.lua` (the official port's) | [bar-topbar-warning-banner.patch](bar-topbar-warning-banner.patch); tested on the dev phone |
| [bar-options-replaced.md](bar-options-replaced.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `luaui/Include/options/model.lua` (Settings' model since test-31958; the official port's) | [bar-options-replaced.patch](bar-options-replaced.patch); tested on the dev phone |
| [bar-windows-upright.md](bar-windows-upright.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to six windows (the official port's) | [bar-windows-upright.patch](bar-windows-upright.patch); tested on the dev phone |
| [bar-pregame-upright.md](bar-pregame-upright.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `map_start_position_suggestions.lua` and `gui_game_type_info.lua` (the official port's) | [bar-pregame-upright.patch](bar-pregame-upright.patch); tested on the dev phone |
| [bar-topbar-amount.md](bar-topbar-amount.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_top_bar.lua` (the official port's) | [bar-topbar-amount.patch](bar-topbar-amount.patch); tested on the dev phone |
| [bar-playerlist-hide.md](bar-playerlist-hide.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_advplayerslist.lua` (the official port's) | [bar-playerlist-hide.patch](bar-playerlist-hide.patch); tested on the dev phone |
| [bar-tooltip-wrap.md](bar-tooltip-wrap.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_tooltip.lua` (the official port's) | [bar-tooltip-wrap.patch](bar-tooltip-wrap.patch); tested on the dev phone |
| [bar-topbar-warning-clear.md](bar-topbar-warning-clear.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_top_bar.lua` (the official port's) | [bar-topbar-warning-clear.patch](bar-topbar-warning-clear.patch); tested on the dev phone |
| [bar-topbar-hidden.md](bar-topbar-hidden.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_top_bar.lua` (the official port's) | [bar-topbar-hidden.patch](bar-topbar-hidden.patch) |
| [bar-topbar-press-hover.md](bar-topbar-press-hover.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_top_bar.lua` (the official port's) | [bar-topbar-press-hover.patch](bar-topbar-press-hover.patch); tested on the dev phone |
| [bar-playerlist-press-hover.md](bar-playerlist-press-hover.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_advplayerslist.lua` (the official port's) | [bar-playerlist-press-hover.patch](bar-playerlist-press-hover.patch); tested on the dev phone |
| [bar-topbar-buttons-press-hover.md](bar-topbar-buttons-press-hover.md) | github.com/beyond-all-reason/Beyond-All-Reason, a change to `gui_top_bar_buttons.lua` (the official port's) | [bar-topbar-buttons-press-hover.patch](bar-topbar-buttons-press-hover.patch); tested on the dev phone |
