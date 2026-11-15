# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, the amount whole after the overflow warning's clear

For BAR's repository (the official Android port). The change: [bar-topbar-warning-clear.patch](bar-topbar-warning-clear.patch)
(`git apply` in BAR's checkout; made against release test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of 2026-11-15; first made against
test-31836-b250a16, the test below is from before this rebase). Found and tested on 2026-11-14.

**Title:** Top bar: the metal / energy amount loses its last digits when "Wasting" shows on a short resource bar

**Body:**

In `luaui/Widgets/gui_top_bar.lua` (`widget:DrawScreen`), when the overflow warning first shows, the storage number's
area of the text texture is cleared once (`clearFn` through `storageScissors`: from 4 storage font sizes left of the
bar's right end), and the storage number is not drawn while the warning shows. On a short bar, as on a phone at a large
interface scale (2.0 on a 2008 x 938 screen), that area reaches into the current amount, centred on the bar. The amount
is drawn again only when its value changes, so at a game's start, with storage full and the amount at 1000 until the
player spends, the bar shows "1" (or "100") of "1000" for as long as it stays there.

The change marks the amount as not drawn (`cache.lastDrawnValue[res] = ""`) right after that clear, so the next
update draws it again, whole; its own redraw area covers it as before. Nothing changes where the bar is long enough.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game sideways at 2008 x 938, interface scale 2.0, a
skirmish's start with both warnings up): before, "1" of "1000" for metal and energy (with the amount moved left by
bar-topbar-amount.patch, "100"); after, "1000" and "1000" whole; no Lua errors. Tested as the app's phone version of
the file (its engine applies the change as LuaUI loads BAR's file).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
