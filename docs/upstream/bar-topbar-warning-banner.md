# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, the overflow banner's text inside its banner

For BAR's repository (the official Android port). The change: [bar-topbar-warning-banner.patch](bar-topbar-warning-banner.patch)
(`git apply` in BAR's checkout; made against release test-31836-b250a16). First written up as an issue on 2026-11-02;
the patch and the phone test 2026-11-11.

**Title:** Top bar: the "Wasting metal / energy" banner's text inside its banner at a large interface scale

**Body:**

In `luaui/widgets/gui_top_bar.lua` the overflow banner's text size is

    local fontSize = (orgHeight * (1 + (ui_scale - 1) / 1.33) / 4) * widgetScale

while `widgetScale` already holds the interface scale (`widgetScale = (vsy / height) * 0.0425 * ui_scale`), and the
banner it sits in does not grow with the extra factor (`bannerH = 15.5 * widgetScale`, the text's baseline at
`resbarArea[res][4] - 9.3 * widgetScale`). At `ui_scale = 1` the text (11.5 x widgetScale) fits; at 2 it is 1.75 times
that, about 20 x widgetScale, and its top runs past the banner's top, which is the screen's top edge: "Wasting metal"
shows with the upper part of its letters cut off.

The change counts the scale once:

    local fontSize = (orgHeight / 4) * widgetScale

At `ui_scale = 1` nothing changes; above it the text grows with `widgetScale` as the banner does, and the banner's
width (the text's width) with it.

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, a 2316 x 1080 screen at the app's interface scale 2.0, an
offline skirmish): the release's pool file of `gui_top_bar.lua` swapped for the patched one, both banners up at the
game's start: "Wasting metal" and "Wasting energy" whole inside their banners (before: the tops of their letters cut
off at the screen's edge); no Lua errors. BAR's file put back after (its md5 checked).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
