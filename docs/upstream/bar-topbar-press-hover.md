# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, a top bar press judged by where it is

For BAR's repository (the official Android port). The change: [bar-topbar-press-hover.patch](bar-topbar-press-hover.patch)
(`git apply` in BAR's checkout; made against release test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of
2026-11-15). Found and tested on 2026-11-16.

**Title:** Top bar: a tap on a top bar button is swallowed when the pointer was last over a resource bar

**Body:**

In `luaui/Widgets/gui_top_bar.lua`, `widget:MousePress` ends with `if hoveringTopbar then return true end`.
`hoveringTopbar` is worked out in `widget:Update` from where the pointer was at the last check, not from the press.
With a mouse the pointer reaches a button frames before the click, so the two agree. On a touch screen the pointer
jumps to the finger and presses in the same frame: `hoveringTopbar` still names the element under the previous tap.
Top Bar hears a press before Top Bar Buttons (both layer -95000), so when the previous tap was over the metal or
energy bar, the wind or the commander counter, the next tap on a button (Quit, Settings, ...) is taken by Top Bar and
nothing happens; a second tap works. Upright on a phone, where Top Bar Buttons' row is wide enough to lie over the
resource bars, every tap on Quit right after Save did nothing.

The change judges the press by the element under it (`hoveringElement(x, y)`, the same check Update makes, with the
same height test). Nothing changes for a mouse: there the two always agree.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game upright at 936 x 2013, a skirmish): before, Save then
one tap on Quit opened nothing, three times in three; after, the quit dialog opened each time, three in three; no Lua
errors. Tested as the app's phone version of the file (its engine applies the change as LuaUI loads BAR's file).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
