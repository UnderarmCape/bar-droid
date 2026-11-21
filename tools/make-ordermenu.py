"""The app's order menu (app/src/main/assets/bardroid/bardroid_ordermenu.lua) from BAR's own Order menu.

Kailil, 2026-11-03: the order menu online should "behave like offline". Offline (then the controller game, v0.8.5's
order menu) the orders left when the app's gamepad controls hide the ones the pad has buttons for filled the menu evenly,
the buttons bigger; BAR's released game keeps BAR's grid of at least 4 x 4 cells, which a user widget cannot change. So
the app runs a copy of BAR's Order menu under its own name in every game, as it does with the Build menu
(tools/make-buildmenu.py): the same code, with v0.8.5's even layout while the pad hides orders (WG.BarDroidPadOrders),
its cells for the app's gamepad controls (WG.ordermenu.droidCells), and an IsAbove, so a finger's drag on the menu no
longer pans the map. Each change is marked "BAR Droid:" in the copy. (Until 2026-11-21 it stood down in the controller
game, and that check took BAR's own developer game, "$VERSION", for it: no order menu copy there.)

Takes BAR's luaui/Widgets/gui_ordermenu.lua from the byar:test release (BAR's Windows install, or --adb a phone's) and
records its pool md5; it also writes the patches beside the copy, and the phone makes the copy again itself when an
update changes BAR's file (Installer, BuildMenuPatches). A patch that no longer finds its place stops the tool.
    python -I tools/make-ordermenu.py [--bar-data <BAR data folder> | --adb <adb.exe>]   (ANDROID_SERIAL names the phone)
"""
import argparse
import importlib.util
import os
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_ordermenu.lua")
PATCHES_OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_ordermenu.patches")
FILE = "luaui/widgets/gui_ordermenu.lua"


def bar_file(bar, adb):
    """(release name, pool md5, bytes) of FILE, read as tools/make-buildmenu.py reads BAR's Build menu."""
    spec = importlib.util.spec_from_file_location("make_buildmenu", os.path.join(APP, "tools", "make-buildmenu.py"))
    mb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mb)
    mb.FILE = FILE
    return mb.bar_file(bar, adb)


HEADER = """\
-- BAR Droid order menu: BAR's own Order menu (luaui/Widgets/gui_ordermenu.lua, by Floris, GPL v2 or later), from
-- {release}, unchanged except where marked "BAR Droid:" (Kailil, 2026-11-03: the order menu online should "behave like
-- offline"): while the app's gamepad controls hide the orders the pad has buttons for, the rest fill the menu evenly,
-- as in v0.8.5's order menu, and the menu answers IsAbove (a finger's drag on it no longer pans the map). Made by
-- tools/make-ordermenu.py; do not edit by hand, run it again.
-- launch-bar.sh runs it instead of BAR's Order menu; when an update changes BAR's file the phone makes it again from the
-- new file (the line below names the one it was made from; Installer, BuildMenuPatches).
-- BARDROID_ORDERMENU_FROM {md5}
"""

# (what to find, exactly once; what goes in its place)
PATCHES = [
    ('''		name = "Order menu",
		desc = "",
		author = "Floris",
		date = "April 2020",
		license = "GNU GPL, v2 or later",
		layer = 1,
		enabled = true,
''',
     '''		name = "BAR Droid order menu", -- BAR Droid: its own name (BAR's sandbox runs no user widget under BAR's)
		desc = "BAR's Order menu; with the app's gamepad controls the orders left fill it (BAR Droid)",
		author = "Floris",
		date = "April 2020",
		license = "GNU GPL, v2 or later",
		layer = 1,
		enabled = false, -- BAR Droid: launch-bar.sh switches it on in place of BAR's Order menu
		replaces = "Order menu", -- BAR Droid: BAR's handler then knows whose place it took (knownWidgets[...].replacedBy)
'''),
    ('''local function setupCellGrid(force)
''',
     '''-- BAR Droid: what the app adds: the even layout's last shape, the WG.ordermenu this copy set (another's is left
-- alone at its end), and where and since when the pointer rests (tooltipShows)
local droid = { evenKey = nil, api = nil, x = nil, y = nil, restsFrom = nil, TOOLTIP_SECONDS = 2.5, two = {} }

-- BAR Droid: with fingers the pointer stays where the last one lifted, and an order's tooltip with it, over the buttons
-- beside it until the next touch (dev phone, 2026-11-03): it goes TOOLTIP_SECONDS after the pointer came to rest (BAR's
-- tooltip widget draws one only while it is asked for it each frame). A mouse keeps BAR's way.
function droid.tooltipShows()
	local x, y = Spring.GetMouseState()
	local now = Spring.GetTimer()
	if x ~= droid.x or y ~= droid.y or not droid.restsFrom then
		droid.x, droid.y, droid.restsFrom = x, y, now
	end
	-- (upright the portrait dock covers this menu: none of its tooltips there, "Patrol" and "Fire at will" showed over
	-- the dock's own buttons after a tap, dev phone 2026-11-11)
	local P = WG.BarDroidPortrait
	local d = P and P.dock and P.dock()
	if d and x >= d[1] and x <= d[3] and y >= d[2] and y <= d[4] then
		return false
	end
	return WG.BarDroidInput ~= "touch" or Spring.DiffTimers(now, droid.restsFrom) < droid.TOOLTIP_SECONDS
end

local function setupCellGrid(force)
'''),
    ('''	local sizeDivider = ((cols + rows) / 16)
	cellMargin = (cellMarginOriginal / sizeDivider) * uiScale

	if force or oldCols ~= cols or oldRows ~= rows then
''',
     '''	-- BAR Droid (Kailil, 2026-10-29 offline, 2026-11-03 online too): while the pad is the
	-- input the orders it gives with its buttons are hidden (bardroid_pad.lua, through setDisabledCmd) and the rest fill
	-- the menu evenly, whatever their number: as many rows as make the buttons about twice as wide as tall (BAR's own
	-- buttons' shape: their words stay readable), each row's buttons sharing its width (WG.BarDroidPadOrders)
	local evenRows = nil
	if WG.BarDroidPadOrders and cmdCount > 0 then
		local w, h = activeRect[3] - activeRect[1], activeRect[4] - activeRect[2]
		local r = math_max(1, math_min(cmdCount, math_floor(math.sqrt(2 * cmdCount * h / math_max(1, w)) + 0.5)))
		evenRows = {}
		local left = cmdCount
		for i = 1, r do
			evenRows[i] = math_ceil(left / (r - i + 1))
			left = left - evenRows[i]
		end
		cols, rows = evenRows[1], r
	end
	local evenKey = evenRows and (cmdCount .. "x" .. rows) or nil
	if evenKey ~= droid.evenKey then
		droid.evenKey = evenKey
		force = true
	end

	local sizeDivider = ((cols + rows) / 16)
	cellMargin = (cellMarginOriginal / sizeDivider) * uiScale

	if (force or oldCols ~= cols or oldRows ~= rows) and evenRows then -- BAR Droid: the even layout
		clearStateLightDisplayLists()
		clickedCell = nil
		clickedCellTime = nil
		clickedCellDesiredState = nil
		local w = activeRect[3] - activeRect[1]
		cellHeight = math_floor((activeRect[4] - activeRect[2]) / rows)
		cellWidth = math_floor(w / cols)
		cellMarginPx = math_max(1, math_ceil(cellHeight * 0.5 * cellMargin))
		cellMarginPx2 = math_max(0, math_ceil(cellHeight * 0.18 * cellMargin))
		local i = 0
		for row = 1, rows do
			local k = evenRows[row]
			for col = 1, k do
				i = i + 1
				cellRects[i] = cellRects[i] or {}
				local rect = cellRects[i]
				rect[1] = math_floor(activeRect[1] + w * (col - 1) / k + 0.5)
				rect[2] = math_floor(activeRect[4] - cellHeight * row + 0.5)
				rect[3] = math_floor(activeRect[1] + w * col / k + 0.5)
				rect[4] = math_floor(activeRect[4] - cellHeight * (row - 1) + 0.5)
				-- (BAR's drawing gives a row's first button its edge margin by the cell's number, i % cols == 1, which
				-- rows of fewer buttons do not follow (10 orders: 4 + 3 + 3): those rects shift by the difference, so
				-- every row's first button lines up)
				if cols > 1 and (i % cols == 1) ~= (col == 1) then
					local d = cellMarginPx - cellMarginPx2
					rect[1] = rect[1] + (col == 1 and -d or d)
				end
			end
		end
		for j = i + 1, #cellRects do
			cellRects[j] = nil
		end
	elseif force or oldCols ~= cols or oldRows ~= rows then
'''),
    ('''function widget:Initialize()
	widgetHandler:RegisterUnitCommand(CMD.WAIT)
''',
     '''function widget:Initialize()
	-- BAR Droid: an older BAR's handler (a replay of an older release plays its own files) has no RegisterUnitCommand and
	-- hands every unit command to every widget anyway
	if widgetHandler.RegisterUnitCommand then
		widgetHandler:RegisterUnitCommand(CMD.WAIT)
	end
'''),
    ('''				isStateCommand[command.id] = true
				widgetHandler:RegisterUnitCommand(command.id)''',
     '''				isStateCommand[command.id] = true
				if widgetHandler.RegisterUnitCommand then -- BAR Droid: not in an older BAR's handler (a replay)
					widgetHandler:RegisterUnitCommand(command.id)
				end'''),
    ('''	tapHotkeys = require("luaui/Include/action_tap_hotkeys")''',
     '''	-- BAR Droid: none where BAR's file is not (a replay of an older release plays its own files: without it this copy
	-- did not load there)
	tapHotkeys = VFS.FileExists("luaui/Include/action_tap_hotkeys.lua") and require("luaui/Include/action_tap_hotkeys") or {}'''),
    ('''	WG.ordermenu.getIsShowing = function()
		return ordermenuShows
	end
''',
     '''	WG.ordermenu.getIsShowing = function()
		return ordermenuShows
	end
	-- BAR Droid: the cells as laid out (bottom left origin) and the orders in them, in the same order: the app's gamepad
	-- controls step through them (bardroid_pad.lua), the even layout included
	WG.ordermenu.droidCells = function()
		return cellRects, commands
	end
	droid.api = WG.ordermenu
'''),
    ('''	WG.ordermenu = nil
end
''',
     '''	if WG.ordermenu == droid.api then -- BAR Droid: another's left alone
		WG.ordermenu = nil
	end
end
'''),
    ('''			local fontSize = cellInnerWidth / textWidth * math_min(1, (cellInnerHeight / (rows * 6)))
			if fontSize > cellInnerWidth / 7 then
				fontSize = cellInnerWidth / 7
			end
''',
     '''			-- BAR Droid: in the even layout a row of fewer, wider buttons keeps the narrowest row's largest text size (its
			-- labels came out a third larger than the rows above); a long label still fits its own button
			local sizeWidth = cellInnerWidth
			if droid.evenKey then
				sizeWidth = math_min(cellInnerWidth, cellWidth - ((cellRects[cell][3] - cellRects[cell][1]) - cellInnerWidth))
			end
			-- (and a label sized by its width keeps 4% of the button at each end: "Place Blueprint" ran to its edges)
			local fontSize = cellInnerWidth * 0.92 / textWidth * math_min(1, (cellInnerHeight / (rows * 6)))
			if fontSize > sizeWidth / 7 then
				fontSize = sizeWidth / 7
			end
'''),
    ('''						local cmd = commands[cell]
						if WG.tooltip then
''',
     '''						local cmd = commands[cell]
						if WG.tooltip and droid.tooltipShows() then -- BAR Droid: a finger's tooltip goes after a while
'''),
    ('''							local hotkey = tapLine and "" or hotkeyCache[cmd.action]
''',
     '''							local hotkey = tapLine and "" or hotkeyCache[cmd.action]
							-- BAR Droid: no key to name to fingers ("; - Set how far ...", "Tap L quickly: 1x Fire at will, ...")
							if WG.BarDroidInput == "touch" then
								hotkey, tapLine = "", nil
							end
'''),
    ('''			font:Print(
				printStr,
				cellRects[cell][1] + ((cellRects[cell][3] - cellRects[cell][1]) / 2),
				(cellRects[cell][2] - ((cellRects[cell][2] - cellRects[cell][4]) / 2) - fontHeightOffset),
				fontSize,
				"con"
			)
''',
     '''			-- BAR Droid: a label of two or more words that its button's width shrank well below the others' size
			-- ("Place Blueprint" a size smaller than every other order, dev phone 2026-11-04) goes on two lines at up to
			-- the others' size, where the button is tall enough for them
			local two = droid.two[text]
			if two == nil then
				local best = false
				for at in text:gmatch("() ") do
					local a, b = text:sub(1, at - 1), text:sub(at + 1)
					local w = math_max(font:GetTextWidth("  " .. a .. " "), font:GetTextWidth("  " .. b .. " "))
					if not best or w < best[3] then
						best = { a, b, w }
					end
				end
				droid.two[text] = best
				two = best
			end
			local twoSize = two and math_min(sizeWidth / 7, cellInnerWidth * 0.92 / two[3] * math_min(1, (cellInnerHeight / (rows * 6)))) * zoom
			if twoSize and twoSize > fontSize * 1.15 and twoSize * 2.1 <= cellInnerHeight * zoom then
				local x = cellRects[cell][1] + ((cellRects[cell][3] - cellRects[cell][1]) / 2)
				local y = cellRects[cell][2] - ((cellRects[cell][2] - cellRects[cell][4]) / 2) - fontHeightOffset * twoSize / fontSize
				font:Print(textColor .. two[1], x, y + twoSize * 0.52, twoSize, "con")
				font:Print(textColor .. two[2], x, y - twoSize * 0.52, twoSize, "con")
			else
			font:Print(
				printStr,
				cellRects[cell][1] + ((cellRects[cell][3] - cellRects[cell][1]) / 2),
				(cellRects[cell][2] - ((cellRects[cell][2] - cellRects[cell][4]) / 2) - fontHeightOffset),
				fontSize,
				"con"
			)
			end
'''),
    ('''function widget:MousePress(x, y, button)
''',
     '''-- BAR Droid: the menu is interface: a finger's drag there does not pan the map (BAR's own answers no IsAbove)
function widget:IsAbove(x, y)
	return ordermenuShows and math_isInRect(x, y, backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4])
end

function widget:MousePress(x, y, button)
'''),
    ('''		(WG.guishader and not displayListGuiShader) or (#commands == 0 and (not alwaysShow or spGetGameFrame() == 0))
	then''',
     '''		(WG.guishader and not displayListGuiShader) or (#commands == 0 and (not alwaysShow or spGetGameFrame() == 0))
		or (WG.BarDroidPortrait and WG.BarDroidPortrait.active()) -- BAR Droid: the portrait dock has the orders
	then'''),
    # (and not drawn while the dock is up: the dock across the bottom covered it, but sideways for one thumb it leaves
    # the bottom's other side to the game, and the menu's buttons showed beside it, dev phone 2026-11-12)
    ('''	if #commands == 0 and (not alwaysShow or spGetGameFrame() == 0) then -- dont show pregame because factions interface is shown''',
     '''	if (#commands == 0 and (not alwaysShow or spGetGameFrame() == 0)) -- dont show pregame because factions interface is shown
		or (WG.BarDroidPortrait and WG.BarDroidPortrait.active()) then -- BAR Droid: the dock has the orders, not drawn'''),
    # (and drawn again when it shows after the dock: hidden with orders to show, its last picture was of the pick before
    # the dock's, or never made, while the orders under it were the live ones; BAR hides it only with no orders, so its
    # next shown frame always counted as a change; review 2026-11-16)
    ('''		doUpdate = nil
		tracy.ZoneEnd()
	else
		tracy.ZoneBeginN("W:OrderMenu:DrawScreen:Visible")
''',
     '''		doUpdate = nil
		droid.hidden = true -- BAR Droid: hidden (the dock up, or no orders): drawn again once it shows
		tracy.ZoneEnd()
	else
		tracy.ZoneBeginN("W:OrderMenu:DrawScreen:Visible")
		if droid.hidden then -- BAR Droid: shown again: its orders' picture made anew
			droid.hidden, doUpdate = nil, true
		end
'''),
    # (nor hovered while not drawn: sideways for one thumb with the dock moved to the left the menu's place is open map,
    # and its buttons' tooltips ("D-Gun") and its plain pointer showed there, dev phone 2026-11-13)
    ('''	tracy.ZoneBeginN("W:OrderMenu:DrawScreen:HoverScan")
	if not WG.topbar or not WG.topbar.showingQuit() then
''',
     '''	tracy.ZoneBeginN("W:OrderMenu:DrawScreen:HoverScan")
	-- BAR Droid: not while the menu is not shown (the dock has the orders): its place may be open map
	if ordermenuShows and (not WG.topbar or not WG.topbar.showingQuit()) then
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
            sys.exit(f"BAR's order menu changed: a patch finds its place {n} times (not once):\n{find}")
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
