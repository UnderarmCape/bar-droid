# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason issues

**Before posting:** check it on BAR's current release with `ui_scale = 2` on a PC (seen on the dev phone, BAR's game
and the controller game, 2026-11-02, at the app's interface scale 2.0 on a 2008x938 screen).

**Title:** Top bar: the "Wasting metal / energy" banner's text runs out of its banner (off the screen) at a large
interface scale

**Body:**

In `luaui/widgets/gui_top_bar.lua` the overflow banner's text size is

    local fontSize = (orgHeight * (1 + (ui_scale - 1) / 1.33) / 4) * widgetScale

while `widgetScale` already holds the interface scale (`widgetScale = (vsy / height) * 0.0425 * ui_scale`), and the
banner it sits in does not grow with the extra factor (`bannerH = 15.5 * widgetScale`, the text's baseline at
`resbarArea[res][4] - 9.3 * widgetScale`). At `ui_scale = 1` the text (11.5 x widgetScale) fits; at 2 it is 1.75 times
that, about 20 x widgetScale, and its top runs past the banner's top, which is the screen's top edge: "Wasting metal"
shows with the upper part of its letters cut off.

Dropping the `(1 + (ui_scale - 1) / 1.33)` factor (the scale counted once), or growing `bannerH` and the baseline
offset with it, keeps the text inside the banner.

_This report was written with the help of an AI assistant (Claude); the cut-off text was seen on a phone running BAR._
