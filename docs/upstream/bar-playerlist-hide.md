# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, a way to hide the player list

For BAR's repository (the official Android port). The change: [bar-playerlist-hide.patch](bar-playerlist-hide.patch)
(`git apply` in BAR's checkout; made against release test-31836-b250a16). Asked for 2026-11-11 (Kailil: "Hide the team
list"), built and tested on 2026-11-15.

**Title:** AdvPlayersList: `WG.advplayerlist_api.SetHidden` to hide the list for a while

**Body:**

`luaui/widgets/gui_advplayerslist.lua`'s API offers scale, columns, spectators and the list's position, but no way to
put the list away. A phone's interface that covers the screen's foot (the BAR Droid port's touch dock, folded to a
small button while spectating so the whole map shows) needs the list out of the way then, and back after.

The change adds `SetHidden(hidden)` and `GetHidden()`. Hidden, the list skips its `DrawScreen` and `MousePress`, and
`GetPosition` returns a rect collapsed onto the list's foot, so the panels BAR stacks on the list's position (Player
View / Player Camera / TV, the clock and speed line, the music player, unit totals, the mascot, the map mark eraser)
move down onto it and stay usable. The collapsed rect is a new table only when the list's own changes, as
`GetPosition` returns now (those panels ask every frame). Nothing changes unless something calls `SetHidden(true)`.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game upright, a server replay of the 2026-10-01 release
spectated): `SetHidden(true)` from the app's dock, the list gone and the stacked panels at the bottom right, working;
`SetHidden(false)`, the list back. No Lua errors. Tested as the app's phone version of the file (its engine applies the
change as LuaUI loads BAR's file).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
