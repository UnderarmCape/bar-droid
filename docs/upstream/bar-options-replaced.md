# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, Settings and widgets that take another's place

For BAR's repository (the official Android port, 2026-11-10). The change: [bar-options-replaced.patch](bar-options-replaced.patch)
(`git apply` in BAR's checkout; made against release test-31836-b250a16).

**Title:** Settings: a replaced widget's options read and saved in the config of the widget that took its place

**Body:**

BAR's widget handler lets a widget take another's place (GetInfo `replaces`): the old one is not loaded and
`widgetHandler.replacedList[old] = new` is saved with the order. Settings (`gui_options.lua`) still reads and writes
the old widget's config by its name (`widgetConfig = { "Order menu", "colorize", ... }`, `saveOptionValue("Order
menu", ...)`), so it shows the old widget's last saved values, not the running one's, and its dev check reports the
old name. BAR Droid runs its own copy of the Order menu ("BAR Droid order menu", the same config keys, the same
`WG.ordermenu` setters) in its place; Settings' setters reach the copy, but what Settings shows comes from the old
config.

The change: a `configName()` that follows `replacedList` to the widget running in the old one's place (only while that
one is active), used where Settings reads a widget's saved config (`widgetConfigValue`), where it saves one
(`saveOptionValue`), and in its dev-mode binding check. Without a replacement nothing changes.

**Tested** on the BAR Droid dev phone (an offline skirmish, the release's pool file swapped for the patched one and put
back after): the saved configs given different values, the old "Order menu" colorize 0.7 and the running "BAR Droid
order menu" 0.3: Settings' `ordermenu_colorize` read 0.7 without the change, 0.3 with it.

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
