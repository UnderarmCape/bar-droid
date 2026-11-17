"""The app's mission info (app/src/main/assets/bardroid/bardroid_missioninfo.lua) from BAR's own Mission Info.

Kailil, 2026-11-10: "the game start ui popup needs to fit vertical screen". BAR's Mission Info (a scenario's briefing,
shown as the game starts and from the top bar's Mission button) is 1050 x 520 times a scale made from the screen's size:
upright on the dev phone 1152 pixels wide on a 936 wide screen, centred, so its lines began off the left edge, and it lay
over the app's portrait dock. A user widget cannot move it, so the app runs a copy of it under its own name, as it does
with the Build and Order menus (tools/make-buildmenu.py, tools/make-ordermenu.py): the same code, its window no wider
than the screen (the text keeps its size and wraps to the width) and, with the portrait dock up, in the middle of the
game above the dock. Each change is marked "BAR Droid:" in the copy.

Takes BAR's luaui/Widgets/gui_mission_info.lua from the byar:test release (BAR's Windows install, or --adb a phone's) and
records its pool md5; it also writes the patches beside the copy, and the phone makes the copy again itself when an
update changes BAR's file (Installer, BuildMenuPatches). A patch that no longer finds its place stops the tool.
    python -I tools/make-missioninfo.py [--bar-data <BAR data folder> | --adb <adb.exe>] [--check]   (ANDROID_SERIAL names the phone)
"""
import argparse
import importlib.util
import os
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_missioninfo.lua")
PATCHES_OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_missioninfo.patches")
FILE = "luaui/widgets/gui_mission_info.lua"


def bar_file(bar, adb):
    """(release name, pool md5, bytes) of FILE, read as tools/make-buildmenu.py reads BAR's Build menu."""
    spec = importlib.util.spec_from_file_location("make_buildmenu", os.path.join(APP, "tools", "make-buildmenu.py"))
    mb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mb)
    mb.FILE = FILE
    return mb.bar_file(bar, adb)


HEADER = """\
-- BAR Droid mission info: BAR's own Mission Info (luaui/Widgets/gui_mission_info.lua, by Floirs, GPL v2 or later), from
-- {release}, unchanged except where marked "BAR Droid:" (Kailil, 2026-11-10: "the game start ui popup needs to fit
-- vertical screen"): its window no wider than the screen, the text at its size wrapping to it, and with the app's
-- portrait dock up in the middle of the game above the dock. Made by tools/make-missioninfo.py; do not edit by hand, run
-- it again. launch-bar.sh runs it instead of BAR's Mission Info; when an update changes BAR's file the phone makes it
-- again from the new file (the line below names the one it was made from; Installer, BuildMenuPatches).
-- BARDROID_MISSIONINFO_FROM {md5}
"""

# (what to find, exactly once; what goes in its place)
PATCHES = [
    ('''		name = "Mission Info",
		desc = "Shows the scenario mission briefing, objectives, and details.",
''',
     '''		name = "BAR Droid mission info", -- BAR Droid: its own name (BAR's sandbox runs no user widget under BAR's)
		desc = "BAR's Mission Info; upright it fits the screen, above the app's dock (BAR Droid)",
		-- BAR Droid: BAR's own off while this runs (BAR's widget handler: GetInfo replaces; back on if this one is not
		-- running). The order list alone did not keep it off: a widget BAR has not seen run before starts anyway
		replaces = "Mission Info",
'''),
    ('''local vsx, vsy = spGetViewGeometry()
''',
     '''local vsx, vsy = spGetViewGeometry()

-- BAR Droid: the app's portrait dock (bardroid_portrait.lua) while it is up: x0, y0, x1, y1 (else nil); the window is laid
-- out again when the dock comes, goes or moves (DrawScreen)
local droid = { dockTop = nil }
function droid.dock()
	local P = WG.BarDroidPortrait
	return P and P.active and P.active() and P.dock and P.dock() or nil
end
'''),
    ('''	screenHeight = mathFloor(screenHeightOrg * widgetScale)
	screenWidth = mathFloor(screenWidthOrg * widgetScale)
	screenX = mathFloor((vsx * centerPosX) - (screenWidth / 2))
	screenY = mathFloor((vsy * centerPosY) + (screenHeight / 2))
''',
     '''	screenHeight = mathFloor(screenHeightOrg * widgetScale)
	screenWidth = mathFloor(screenWidthOrg * widgetScale)
	-- BAR Droid: no wider than the screen (upright on a phone it was 1152 on 936, its lines starting off the left edge):
	-- the text keeps its size and wraps to the width; with the portrait dock up, the height of the game above the dock
	-- at most, in its middle (the title tab above it counted)
	screenWidth = math.min(screenWidth, mathFloor(vsx * 0.96))
	local droidCentreY = vsy * centerPosY
	local droidDock = droid.dock()
	if droidDock then
		local tab = 18 * widgetScale * 1.7
		screenHeight = math.min(screenHeight, mathFloor((vsy - droidDock[4] - tab) * 0.9))
		droidCentreY = (droidDock[4] + vsy - tab) / 2
	end
	screenX = mathFloor((vsx * centerPosX) - (screenWidth / 2))
	screenY = mathFloor(droidCentreY + (screenHeight / 2))
'''),
    ('''function widget:DrawScreen()
	if not textList then
''',
     '''function widget:DrawScreen()
	-- BAR Droid: laid out again when the app's portrait dock comes, goes or moves
	local droidDock = droid.dock()
	local droidTop = droidDock and droidDock[4] or false
	if droidTop ~= droid.dockTop then
		droid.dockTop = droidTop
		widget:ViewResize()
	end
	if not textList then
'''),
    ('''			-- Outside: close on press but DON'T consume — lets top bar buttons receive the click
			if not release then
				showOnceMore = show
				show = false
				justClosedFromPress = true
			end
''',
     '''			-- Outside: close on press but DON'T consume — lets top bar buttons receive the click
			if not release then
				showOnceMore = show
				show = false
				justClosedFromPress = true
				-- BAR Droid: a finger's tap that closes it is taken (a mouse's click goes on, as in BAR): the tap that
				-- dismissed a scenario's briefing also clicked the map and unpicked the commander, the dock back on its
				-- home page (dev phone, 2026-11-12). The top bar's buttons still get theirs (above).
				return WG.BarDroidInput ~= "mouse"
			end
'''),
    ('''	WG.missioninfo.isvisible = function()
		-- Report true while justClosedFromPress so toggleWindow treats us as
		-- "was open" and doesn't immediately re-open after our mouseEvent close.
		return show or justClosedFromPress
	end
''',
     '''	WG.missioninfo.isvisible = function()
		-- Report true while justClosedFromPress so toggleWindow treats us as
		-- "was open" and doesn't immediately re-open after our mouseEvent close.
		return show or justClosedFromPress
	end
	-- BAR Droid: the top of its title tab (GL y) while it is shown: the app's chat ends its lines above it (upright its
	-- fifth line ran under the tab, dev phone 2026-11-12)
	WG.missioninfo.droidTop = function()
		return show and titleRect and titleRect[4] or nil
	end
'''),
    ('''local isScenario = _modOpts ~= nil and _modOpts.scenariooptions ~= nil

if not isScenario then
	return
end
''',
     '''local isScenario = _modOpts ~= nil and _modOpts.scenariooptions ~= nil

-- BAR Droid: false, BAR's widget handler's silent way out: as a user widget the bare return logged "Failed to load:
-- bardroid_missioninfo.lua (no GetInfo() call)" at every game that is no scenario (dev phone's launcher.log,
-- 2026-11-17; the team stats copy does the same)
if not isScenario then
	return false
end
'''),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bar-data", default=os.path.join(os.environ.get("LOCALAPPDATA_REAL") or
                    os.path.expandvars(r"%USERPROFILE%\AppData\Local"), "Programs", "Beyond-All-Reason", "data"))
    ap.add_argument("--adb", help="read BAR's file off the phone with this adb, not from a BAR data folder")
    ap.add_argument("--check", action="store_true", help="only see that every patch finds its place; write nothing")
    args = ap.parse_args()
    release, md5, raw = bar_file(args.bar_data, args.adb)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for find, repl in PATCHES:
        n = text.count(find)
        if n != 1:
            sys.exit(f"BAR's mission info changed: a patch finds its place {n} times (not once):\n{find}")
        text = text.replace(find, repl)
    if args.check:
        print(f"patches apply: {release}, {FILE} {md5}, {len(PATCHES)} patches")
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER.format(release=release, md5=md5) + text)
    # (the same patches for the phone: Installer makes the copy again when an update changes BAR's file, BuildMenuPatches)
    with open(PATCHES_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\x1e".join([HEADER] + [part for patch in PATCHES for part in patch]))
    print(f"{OUT}: {release}, {FILE} {md5}, {len(PATCHES)} patches")


if __name__ == "__main__":
    main()
