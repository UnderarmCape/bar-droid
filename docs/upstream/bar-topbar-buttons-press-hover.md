# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, a click on the top bar's buttons strip judged by where it is

For BAR's repository (the official Android port). The change: [bar-topbar-buttons-press-hover.patch](bar-topbar-buttons-press-hover.patch)
(`git apply` in BAR's checkout; made against release test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of
2026-11-15). Found and tested on 2026-11-16. The same kind of fault as [bar-topbar-press-hover.md](bar-topbar-press-hover.md),
in the other half of the top bar.

**Title:** Top bar buttons: after a tap on the strip, the next tap on the map is swallowed on a touch screen

**Body:**

In `luaui/Widgets/gui_top_bar_buttons.lua`, `widget:MousePress` ends with `if hoveringButtons then return true end`
("a click on the strip itself never falls through to the world"). `hoveringButtons` is set in `widget:Update` from
where the pointer was at the last check. With a mouse the pointer is over the map well before a click there. On a
touch screen the pointer jumps to the finger and presses in the same frame: after a tap on the strip (Quit to open the
dialog, Quit again to close it), the pointer rests on the strip, and the next tap on the map is taken by this widget,
which sits before the world in the widget order, and does nothing. A second tap works.

The change judges the click by the strip under it: `overStrip(x, y)`, the check Update makes, moved above
`widget:MousePress` so that it can call it (unchanged). Nothing changes for a mouse: there the two always agree.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game upright at 936 x 2013, a skirmish), with two probe
widgets logging presses at the start and at the end of the widget order: before, after Quit then Quit, the tap on the
map reached the first and not the last; after, all three of three reached both; no Lua errors. Tested as the app's
phone version of the file (its engine applies the change as LuaUI loads BAR's file), which inlines the same test
because a phone version cannot move code.

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
