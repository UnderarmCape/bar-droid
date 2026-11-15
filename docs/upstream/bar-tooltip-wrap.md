# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, tooltip lines wrapped to the screen's width

For BAR's repository (the official Android port). The change: [bar-tooltip-wrap.patch](bar-tooltip-wrap.patch)
(`git apply` in BAR's checkout; made against release test-31836-b250a16). Found and tested on 2026-11-15.

**Title:** Tooltip: a line wider than the screen runs off it on a tall (portrait) screen

**Body:**

`luaui/widgets/gui_tooltip.lua` moves a tooltip box that would pass the screen's right edge to the pointer's left
(`drawTooltip`), but never wraps a line. The widgets that show tooltips wrap their text by the font's size (the
Widget Selector's, the faction picker's `WG.tooltip.getFontsize() * 80` and the like), and the font's size follows
the screen's height. On a portrait screen, as on a phone held upright (936 x 2013 at interface scale 2.0 here), a
line is then wider than the whole screen and its end is cut off, wherever the box is moved.

The change wraps each line wider than the screen, less the box's padding, with the font's own `WrapText` before the
box is measured. On a landscape screen no line is that wide and nothing changes.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game upright at 936 x 2013, interface scale 2.0, a
skirmish): the Widget Selector open, a row's favourite star tooltip ("Collects this widget under Favorites ...") in
five lines inside the screen (before: its lines cut at the right edge); no Lua errors. Tested as the app's phone
version of the file (its engine applies the change as LuaUI loads BAR's file).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
