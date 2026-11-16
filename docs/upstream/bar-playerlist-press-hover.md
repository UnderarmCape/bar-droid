# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, a click on the player list judged by where it is

For BAR's repository (the official Android port). The change: [bar-playerlist-press-hover.patch](bar-playerlist-press-hover.patch)
(`git apply` in BAR's checkout; made against release test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of
2026-11-15). Found and tested on 2026-11-16. The same kind of fault as [bar-topbar-press-hover.md](bar-topbar-press-hover.md)
and [bar-topbar-buttons-press-hover.md](bar-topbar-buttons-press-hover.md).

**Title:** Player list: after a tap on it, the next tap elsewhere is swallowed on a touch screen

**Body:**

In `luaui/Widgets/gui_advplayerslist.lua`, `widget:MousePress` ends with `if hoverPlayerlist then return true end`.
`hoverPlayerlist` is set in `widget:Update` from where the pointer was at the last check. On a touch screen the pointer
jumps to the finger and presses in the same frame, so right after a tap on the list the pointer rests there and the next
tap anywhere (the map, a panel without a widget of its own before the list) is taken by the list and does nothing.

The change judges the click by the list's rect under it, the same rect Update tests. Nothing changes for a mouse.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game sideways at 2008 x 938 with BAR's own screen, a
skirmish), with probe widgets logging presses at the start and at the end of the widget order: a tap on the list, then
one on the ground, three times: the ground's tap reached the end each time; no Lua errors. Tested as the app's phone
version of the file (its engine applies the change as LuaUI loads BAR's file). Not measured on the phone before the
change; the top bar's identical fault was (one tap in three of three swallowed).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
