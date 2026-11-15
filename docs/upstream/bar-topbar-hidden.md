# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, the top bar's hidden parts out of the pointer's way

For BAR's repository (the official Android port, 2026-11-11). The change: [bar-topbar-hidden.patch](bar-topbar-hidden.patch)
(`git apply` in BAR's checkout; made against release test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of 2026-11-15; first made against
test-31836-b250a16, the test below is from before this rebase).

**Title:** Top Bar: hidden resource bars and indicators no longer take the pointer (or show tooltips)

**Body:**

`WG.topbar.setResourceBarsVisible(false)` and `WG.topbar.setIndicatorsVisible(false)` stop drawing the resource bars
and the wind / tide / commander indicators, but `hoveringElement` still finds them under the pointer, so
`widget:MousePress` returns true there, and their tooltips stay registered. Since the split into Top Bar and Top Bar
Buttons (both layer -95000, Top Bar first) that matters wherever the buttons strip lies over that part of the bar: on a
screen held upright (a phone, 936 x 2013) the strip is wider than the quarter of the bar it is given and covers where
the energy bar, the wind and the tide were. There Statistics and Settings never open: the press goes to the hidden
energy bar or tide, and their tooltips ("The desired demand for Energy...", "Tidal Speed") show instead.

The patch:

- `hoveringElement` skips the resource bars while `showResourceBars` is false and the indicators while
  `cache.showIndicators` is false;
- hiding the resource bars removes their tooltips (they come back with `init()` when shown, as now);
- hiding the indicators removes the coms, wind and tide tooltips, showing them again runs `init()` (as showing the
  resource bars does) so their tooltips come back, and `updateComs` / `updateTidal` and `setWindTooltip` (since test-31958 the
  wind's, refreshed by each wind sample too) add a tooltip only while the indicators show;
- `Shutdown` removes the tide's tooltip too (it was left behind).

Nothing changes while both are shown.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, upright, 936 x 2013 game screen, an offline skirmish; BAR
Droid hides both upright, its dock shows the resources). Without the change: on Onyx Cauldron Statistics and Settings
never opened, the energy bar's and "Tidal Speed" tooltips showing instead. With it (the release's pool file of
`gui_top_bar.lua` swapped for the patched one, kept at the file's size by shortening comments, and BAR Droid's own
work-around widget switched off): Statistics, over the hidden energy bar and wind, opened by its own button and closed
again; Settings opened and closed; no tooltip of the hidden parts; no Lua error. BAR's file put back after (its md5
checked). The tide's case goes through the same check (not tried with the patch: that map has no water).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
