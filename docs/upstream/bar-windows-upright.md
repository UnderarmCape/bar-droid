# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, BAR's windows no wider than the screen

For BAR's repository (the official Android port, 2026-11-10). The change: [bar-windows-upright.patch](bar-windows-upright.patch)
(`git apply` in BAR's checkout; made against release test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of 2026-11-15; first made against
test-31836-b250a16, the test below is from before this rebase).

**Title:** Settings, Game info, Widget Selector, TeamStats, Keybinds, Changelog: no wider than the screen (a phone
held upright)

**Body:**

Six of BAR's windows scale by the screen's height alone: `widgetScale = (vsy / 1080)` for a window of
`screenWidthOrg` x `screenHeightOrg` at 1080p (950 x 610 for Settings, 1100 x 610 for the others; Keybinds' size is
its page's). On a screen taller than wide, a phone held upright (936 x 2013), they come out 1.8 to 2 times the
screen's width: Settings' values column, Game info's values and the Widget Selector's switches are off the right edge
and cannot be reached. Scaling by the width too keeps each on the screen:

    widgetScale = math.min(vsy / 1080, vsx / (screenWidthOrg + 50))

where the widget sets it now (its first value and `ViewResize`); in Keybinds after `pageSize(currentPage)`, which sets
the width it uses. On a screen wider than tall nothing changes (`vsx / (screenWidthOrg + 50)` is the larger there, so
the height still decides). The 50 is a margin of ~25 pixels a side at 1080p.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, upright, 936 x 2013 game screen, an offline skirmish): the
release's pool files of `gui_options.lua`, `gui_gameinfo.lua` and `widget_selector.lua` swapped for the patched ones,
each window opened (the top bar's Settings; `WG.gameinfo.toggle(true)`, `WG.widgetselector.toggle(true)`): each whole
on the screen, every column reachable; without the change Settings was ~1770 pixels wide, its values cut off. BAR's
files put back after (their md5s checked). TeamStats with the same change has run on phones since 2026-11-10 (BAR
Droid's copy, `tools/make-teamstats.py`); Keybinds and Changelog are off in BAR Droid (no keyboard, no patch notes on
a phone) and were not opened.

Upright the windows keep their landscape shape, so their text is small (Settings and Game info about 0.8 to 0.9 of
their 1080p size on that phone). A taller layout for screens taller than wide (fewer columns, larger rows) would be
the next step for a phone.

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
