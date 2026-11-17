# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, the Awards' buttons pressed in a finger's strip

For BAR's repository (the official Android port). The change: [bar-awards-touch-strips.patch](bar-awards-touch-strips.patch)
(`git apply` in BAR's checkout; made against release test-31958-7ffdbab, whose files are BAR's master 8ff9f0a of
2026-11-15). Found and tested on 2026-11-17.

**Title:** Awards: Leave, Show Graphs and the close X are hard to hit on a touch screen

**Body:**

In `luaui/Widgets/gui_awards.lua`, `widget:MousePress` takes Leave and Show Graphs in a strip from 5 under to 5 over
their words, about 27 units high, and the close X in a box of about 22 by 27 round a 12 wide letter. With a mouse that
is fine; on a phone held upright it is about 1.5 mm, and a finger's tap often lands just beside them and does nothing.

The change widens only where a press counts: 22 under and over the words of Leave and Show Graphs, and the X's box out
to the panel's right edge and 52 under its top. The words, their places and their hover colours are as before (the hover
tests in `DrawScreen` keep BAR's strips; they could be widened alike). The wider strips hold nothing else of the panel.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra), a skirmish ended upright and one sideways, as the app's phone
version of the file (its engine applies the change as LuaUI loads BAR's file): upright a tap 28 pixels under Show
Graphs (outside BAR's strip) opened the graphs, a tap 25 left of and 20 under the X closed the panel; sideways the tap
under Show Graphs opened them too; no Lua errors.

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
