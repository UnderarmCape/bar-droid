# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, the top bar's amount clear of its storage number

For BAR's repository (the official Android port). The change: [bar-topbar-amount.patch](bar-topbar-amount.patch)
(`git apply` in BAR's checkout; made against release test-31836-b250a16). Found and tested on 2026-11-12.

**Title:** Top bar: the metal / energy amount runs into the storage number on a short resource bar

**Body:**

In `luaui/widgets/gui_top_bar.lua` (`updateResbar`) the current amount is centred on its bar
(`barArea[1] + barWidth / 2`, at `height / 2.5 * widgetScale`) and the storage number is right-aligned at the bar's
right end (`barArea[3]`, at `height / 3.2 * widgetScale`). When the bar is short for its font, as on a phone at a
large interface scale (2.0 on a 2008 x 938 screen here), an amount of four digits reaches the storage number: "1000"
and "1000" run together, for most of a game.

The change keeps the amount centred unless four digits there would reach a four-digit storage number; then it is
centred just left of it (half the storage font's size apart), never past the bar's left end. The position is set where
the layout is made, as before, so the redraw area that follows `textCurrent[2]` still covers it. On a desktop screen
the bar is long enough and nothing moves.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game sideways at 2008 x 938, interface scale 2.0, a 1v1
replay of the same release, its pregame at 1000 / 1000): the release's pool file of `gui_top_bar.lua` swapped for the
patched one (the copy trimmed of comment lines to the original's byte size, as the engine reads a pool file only up to
the size the package lists): "1000" and "1000" apart, both whole (before: run together); no Lua errors; a skirmish's
start the same. BAR's file put back after (its md5 checked).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
