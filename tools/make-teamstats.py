"""The app's team stats (app/src/main/assets/bardroid/bardroid_teamstats.lua) from BAR's own TeamStats panel.

Kailil, 2026-11-10: "the game-end recap and graph" must fit upright. BAR's awards fit; its graphs (the awards' Show Graphs,
the top bar's Statistics) are its TeamStats panel, 1100 x 610 times the screen's height over 1080: upright on the dev
phone 2046 pixels wide on a 936 wide screen, its 3 x 3 charts cut off on both sides. A user widget cannot resize it, so
the app runs a copy of it under its own name, as it does with the Build and Order menus and the Mission Info
(tools/make-buildmenu.py, make-ordermenu.py, make-missioninfo.py): the same code, and on a screen taller than wide the
panel as wide as the screen (its words and rows at a scale that keeps a table's columns in it) and as tall as the game
between BAR's top bar and the app's portrait dock (the charts' grid divides the panel, so they stand taller). Each
change is marked "BAR Droid:" in the copy. BAR's file is at Lua's 200 top-level locals: the patches add none.

Takes BAR's luaui/Widgets/gui_teamstats.lua from the byar:test release (BAR's Windows install, or --adb a phone's) and
records its pool md5; it also writes the patches beside the copy, and the phone makes the copy again itself when an
update changes BAR's file (Installer, BuildMenuPatches). A patch that no longer finds its place stops the tool.
    python -I tools/make-teamstats.py [--bar-data <BAR data folder> | --adb <adb.exe>] [--check]   (ANDROID_SERIAL names the phone)
"""
import argparse
import importlib.util
import os
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_teamstats.lua")
PATCHES_OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_teamstats.patches")
FILE = "luaui/widgets/gui_teamstats.lua"


def bar_file(bar, adb):
    """(release name, pool md5, bytes) of FILE, read as tools/make-buildmenu.py reads BAR's Build menu."""
    spec = importlib.util.spec_from_file_location("make_buildmenu", os.path.join(APP, "tools", "make-buildmenu.py"))
    mb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mb)
    mb.FILE = FILE
    return mb.bar_file(bar, adb)


HEADER = """\
-- BAR Droid team stats: BAR's own TeamStats panel (luaui/Widgets/gui_teamstats.lua, by Floris, GPL v2 or later), from
-- {release}, unchanged except where marked "BAR Droid:" (Kailil, 2026-11-10: the game-end recap and graph fit
-- upright): on a screen taller than wide the panel is the screen's width, its words and rows at a scale that keeps its
-- columns in it, and as tall as the game between BAR's top bar and the app's portrait dock. Made by
-- tools/make-teamstats.py; do not edit by hand, run it again. launch-bar.sh runs it instead of BAR's TeamStats; when an
-- update changes BAR's file the phone makes it again from the new file (the line below names the one it was made from;
-- Installer, BuildMenuPatches).
-- BARDROID_TEAMSTATS_FROM {md5}
"""

# (what to find, exactly once; what goes in its place)
PATCHES = [
    ('''		name = "TeamStats",
		desc = "Shows game stats.",
''',
     '''		name = "BAR Droid team stats", -- BAR Droid: its own name (BAR's sandbox runs no user widget under BAR's)
		desc = "BAR's TeamStats; upright it fits the screen, above the app's dock (BAR Droid)",
		-- BAR Droid: BAR's own off while this runs (BAR's widget handler: GetInfo replaces; back on if this one is not
		-- running)
		replaces = "TeamStats",
'''),
    ('''	vsx, vsy = spGetViewGeometry()
	widgetScale = (vsy / 1080)

	screenHeight = mathFloor(screenHeightOrg * widgetScale)
	screenWidth = mathFloor(screenWidthOrg * widgetScale)
	screenX = mathFloor((vsx * 0.5) - (screenWidth / 2))
	screenY = mathFloor((vsy * 0.5) + (screenHeight / 2))
''',
     '''	vsx, vsy = spGetViewGeometry()
	widgetScale = (vsy / 1080)

	screenHeight = mathFloor(screenHeightOrg * widgetScale)
	screenWidth = mathFloor(screenWidthOrg * widgetScale)
	screenX = mathFloor((vsx * 0.5) - (screenWidth / 2))
	screenY = mathFloor((vsy * 0.5) + (screenHeight / 2))
	-- BAR Droid: on a screen taller than wide (a phone upright: 2046 wide on 936, the charts cut off on both sides) the
	-- panel is the screen's width, its words and rows at a scale that keeps its columns in it, and as tall as the game
	-- between BAR's top bar and the app's portrait dock (laid out again as the dock comes, goes or moves: DrawScreen).
	-- (No new local up top: BAR's file is at Lua's 200; the dock's top is kept in metrics.)
	local droidP = WG.BarDroidPortrait
	local droidDock = droidP and droidP.active and droidP.active() and droidP.dock and droidP.dock() or nil
	-- (upright with the dock stepped aside, the game over or one of BAR's big windows open: its room is the panel's too;
	-- after the Awards' Show Graphs the panel kept the dock's room empty under it, dev phone 2026-11-17)
	local droidAside = droidDock and vsx < vsy and droidP.aside and droidP.aside() or false
	metrics.droidDockTop = droidDock and (droidAside and 0 or droidDock[4]) or false
	if vsx < vsy then
		-- (vsx / 800: at vsx / 960 its menu's rows were about 32 pixels apart and the charts' words 14, under 2 mm and
		-- 1 mm on the dev phone; with 12 charts a page three across, below, their titles have the room; at vsx / 760
		-- "Activity  Actions per minute" lost its last letter at the panel's edge, 2026-11-17)
		widgetScale = math.min(widgetScale, vsx / 800)
		local droidBottom = droidDock and not droidAside and droidDock[4] or 0
		local droidTop = vsy - mathFloor(96 * widgetScale)
		screenWidth = mathFloor(vsx * 0.98)
		screenHeight = mathFloor((droidTop - droidBottom) * 0.97)
		screenX = mathFloor((vsx - screenWidth) / 2)
		screenY = mathFloor((droidTop + droidBottom) / 2 + screenHeight / 2)
	elseif droidDock and droidP.sideways and droidP.sideways() then
		-- BAR Droid: sideways on a tall phone (the dock along the bottom): as large as fits below BAR's top bar, over the
		-- dock, which steps aside while the panel is open, as for BAR's Settings (bardroid_portrait.lua SP.windowOpen).
		-- Fitted above the dock its words were about 11 pixels on a 1080 high screen (dev phone, 2026-11-17)
		local droidTop = vsy - mathFloor(96 * widgetScale)
		local droidM = math.max(4, mathFloor(vsy * 0.012))
		widgetScale = math.min((vsx - 2 * droidM) / screenWidthOrg, (droidTop - 2 * droidM) / screenHeightOrg)
		screenHeight = mathFloor(screenHeightOrg * widgetScale)
		screenWidth = mathFloor(screenWidthOrg * widgetScale)
		screenX = mathFloor((vsx - screenWidth) / 2)
		screenY = mathFloor(droidTop / 2 + screenHeight / 2)
	elseif droidDock then
		-- BAR Droid: sideways with the dock up (the split dock of a near-square screen): above the dock and below BAR's
		-- top bar, a size smaller where it needs to be (it ran down into the dock, the two drawn through each other, dev
		-- phone 2026-11-13)
		local droidBottom = droidDock[4]
		local droidTop = vsy - mathFloor(96 * widgetScale)
		local room = mathFloor((droidTop - droidBottom) * 0.97)
		if screenHeight > room and room > 0 then
			widgetScale = widgetScale * room / screenHeight
			screenHeight = mathFloor(screenHeightOrg * widgetScale)
			screenWidth = mathFloor(screenWidthOrg * widgetScale)
			screenX = mathFloor((vsx * 0.5) - (screenWidth / 2))
		end
		screenY = mathFloor((droidTop + droidBottom) / 2 + screenHeight / 2)
	end
	-- BAR Droid: upright BAR's 12 charts a page three across and four down (its 4 x 3 left their titles running into
	-- each other at a scale a finger can use, "Metal income by sourceComposition", dev phone 2026-11-17); sideways 4 x 3
	-- as BAR has it. The player's setting stays 12. (BAR's grids: metrics.droidPages, metrics.droidGraphsModule.)
	for _, spec in ipairs(metrics.droidPages or {}) do
		if spec.n == 12 then
			spec.cols, spec.rows = vsx < vsy and 3 or 4, vsx < vsy and 4 or 3
		end
	end
	if graphs and graphs.invalidate then
		graphs.invalidate()
	end
'''),
    ('''graphs = require("luaui/Include/teamstats_graphs").new(model.pageContext({
''',
     '''-- BAR Droid: BAR's Graphs page as require loads it (luaui/Include/teamstats_graphs.lua, in this file's environment),
-- its list of grids (PAGES) handed to this copy on the way, so that upright its 12 a page can be laid out three across
-- (ViewResize); BAR's own require where its text is not as expected or does not load. (Fields, not locals: BAR's file
-- is at Lua's 200.)
metrics.droidGraphsModule = function()
	local src = VFS.LoadFile("luaui/Include/teamstats_graphs.lua", VFS.ZIP)
	local text, n = (src or ""):gsub("local PAGES = (%b{})", "local PAGES = WG.BarDroidStatsPages(%1)", 1)
	local chunk = n == 1 and loadstring(text, "@luaui/include/teamstats_graphs.lua")
	if chunk then
		WG.BarDroidStatsPages = function(pages)
			metrics.droidPages = pages
			return pages
		end
		setfenv(chunk, getfenv(1))
		local ok, mod = pcall(chunk)
		WG.BarDroidStatsPages = nil
		if ok and type(mod) == "table" then
			return mod
		end
		metrics.droidPages = nil
		Spring.Echo("[bardroid-teamstats] BAR's Graphs page as BAR loads it: " .. tostring(mod)) -- (tools)
	end
	local mod = require("luaui/Include/teamstats_graphs")
	return mod
end
graphs = metrics.droidGraphsModule().new(model.pageContext({
'''),
    ('''function widget:DrawScreen()
	if not (show or showOnceMore) then
		deleteGuishader()
		return
	end
''',
     '''function widget:DrawScreen()
	if not (show or showOnceMore) then
		deleteGuishader()
		return
	end
	-- BAR Droid: laid out again when the app's portrait dock comes, goes, moves or steps aside (upright: ViewResize)
	local droidP = WG.BarDroidPortrait
	local droidDock = droidP and droidP.active and droidP.active() and droidP.dock and droidP.dock() or nil
	local droidAside = droidDock and vsx < vsy and droidP.aside and droidP.aside() or false
	if (droidDock and (droidAside and 0 or droidDock[4]) or false) ~= metrics.droidDockTop then
		widget:ViewResize()
	end
'''),
    ('''				local width = WG.tooltip.getFontsize() * 90
''',
     '''				local width = WG.tooltip.getFontsize() * 90
				-- BAR Droid: no wider than the screen: upright the Summary's "Right-click to rename or move it, or put its
				-- columns back ..." ran off its right edge (dev phone, 2026-11-16). WrapText measures at the font's own
				-- size, the tooltip prints at its own: the room scaled from the one to the other.
				local droidFs = WG.tooltip.getFontsize()
				if droidFs and droidFs > 0 then
					width = math.min(width, vsx * 0.85 * ((font and font.size or droidFs) / droidFs))
				end
'''),
    ('''		WG.FlowUI.clampedOpacity
''',
     '''		-- BAR Droid: nearly opaque, as the app's Settings: without the GUI shader's blur (off on phones) the game showed
		-- through, the chat's "Phone paused the game" across the title and BAR's GAME PAUSED across the charts (dev
		-- phone, upright, 2026-11-16)
		math.max(0.94, WG.FlowUI.clampedOpacity or 0)
'''),
    ('''function widget:GetInfo()''',
     '''-- BAR Droid: a release without the model this copy is made on (a replay of an older BAR release plays its own files):
-- nothing registered, so the handler loads BAR's own TeamStats instead (this copy's replaces never takes its place);
-- false is BAR's silent way out, a bare return went on to "Failed to load ... (no GetInfo() call)"
if not VFS.FileExists("luaui/Include/teamstats_model.lua") then
	return false
end

function widget:GetInfo()'''),
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
            sys.exit(f"BAR's team stats changed: a patch finds its place {n} times (not once):\n{find}")
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
