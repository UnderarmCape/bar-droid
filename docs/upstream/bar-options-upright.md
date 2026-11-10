# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, a change to `luaui/widgets/gui_options.lua`

For BAR's repository (the official Android port, 2026-11-10). Tested on a phone held upright; on a PC (wider than
tall) the window is the same as before: there `vsx / 1000` is larger than `vsy / 1080`, so the height still decides.

**Title:** Settings: no wider than the screen (a phone held upright)

**Body:**

The Settings window scales by the screen's height alone (`widgetScale = vsy / 1080`, its 950 x 610 at 1080p). On a
screen taller than wide, such as a phone held upright (936 x 2013), it comes out ~1770 pixels wide: the values column
(dropdowns, toggles, sliders) is off the right edge and cannot be reached. Taking the width into account too keeps the
whole window on the screen:

```diff
--- a/luaui/widgets/gui_options.lua
+++ b/luaui/widgets/gui_options.lua
@@ -197,7 +197,7 @@ if select(3, Spring.GetGroundExtremes()) < 0 then
 end
 local heightmapChangeBuffer = {}
 
-local widgetScale = (vsy / 1080)
+local widgetScale = math.min(vsy / 1080, vsx / (screenWidthOrg + 50)) -- no wider than the screen (a phone upright)
 
 local edgeMoveWidth = tonumber(Spring.GetConfigFloat("EdgeMoveWidth", 1) or 0.02)
 
@@ -502,7 +502,7 @@ end
 function widget:ViewResize()
 	vsx, vsy = Spring.GetViewGeometry()
 
-	widgetScale = (vsy / 1080)
+	widgetScale = math.min(vsy / 1080, vsx / (screenWidthOrg + 50)) -- no wider than the screen (a phone upright)
 
 	screenHeight = math.floor(screenHeightOrg * widgetScale)
 	screenWidth = math.floor(screenWidthOrg * widgetScale)
```

(Line numbers from release test-31836-b250a16, file md5 be3b05c70770d3feb6909868ce90f7e1. `screenWidthOrg` is 950 and
is defined above both lines; the 50 is a margin of ~25 pixels a side at 1080p.)

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, upright, 936 x 2013 game screen, an offline skirmish, the
release's pool file swapped for the patched one and put back after): Settings opened from the top bar shows the whole
window, the tabs on the left and every value on the right ("custom", "window 936 x 2013", "off" ...), at the size it
has when the phone is held sideways. Without it the values were cut off at the screen's edge.

The same `vsy / 1080` scale is in BAR's other windows; TeamStats is the other one that overflows upright (BAR Droid
runs a copy of it with this change, `tools/make-teamstats.py`, until BAR has it).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
