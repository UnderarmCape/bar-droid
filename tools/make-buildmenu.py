"""The app's resizable build menu (app/src/main/assets/bardroid/bardroid_buildmenu.lua) from BAR's own Build menu.

Kailil, 2026-10-28: "the vaniallal build menu works fine for touch. just rebuild the exact same one with the ability for
us to resize it freely". BAR's widgets take no size from another widget and BAR's sandbox ignores patched copies of its
widgets under their own name, so the app runs a copy of BAR's Build menu under its own name: the same code, with its
place and size from the app's layout editor (bardroid_layout.lua) and the few widget-handler calls a user widget makes
through BAR's stand-in for the handler. Each change is marked "BAR Droid:" in the copy.

Takes BAR's luaui/Widgets/gui_buildmenu.lua from the byar:test release in a BAR data folder's rapid pool (BAR's Windows
install, as the laptop checks use it) and records its pool md5. It also writes the patches beside the copy: when an
update changes BAR's file the phone makes the copy again itself (Installer, BuildMenuPatches), so a new app is needed only
when BAR rewrites a part a patch needs; until then the phone keeps running the copy it has. A patch that no longer finds
its place stops the tool.
A phone that updated first (the laptop's BAR updates only when it is started): --adb reads the release off the phone.
    python -I tools/make-buildmenu.py [--bar-data <BAR data folder> | --adb <adb.exe>]   (ANDROID_SERIAL names the phone)
"""
import argparse
import gzip
import os
import subprocess
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_buildmenu.lua")
PATCHES_OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_buildmenu.patches")
FILE = "luaui/widgets/gui_buildmenu.lua"
PACKAGE = "com.underarmcape.bardroid"


def bar_file(bar, adb):
    """(release name, pool md5, bytes) of FILE in the byar:test release of the BAR data folder bar, or with adb the phone's."""
    def on_phone(*command):
        return subprocess.run([adb, "exec-out", "run-as", PACKAGE, *command], check=True, stdout=subprocess.PIPE).stdout

    def read(path):
        if adb:
            return on_phone("cat", "files/bar/" + path)
        with open(os.path.join(bar, path), "rb") as f:
            return f.read()

    if adb:
        found = on_phone("sh", "-c", "cd files/bar && find rapid -name versions.gz").decode().split()
    else:
        found = [os.path.relpath(os.path.join(root, "versions.gz"), bar)
                 for root, _, files in os.walk(os.path.join(bar, "rapid")) if "versions.gz" in files]
    tag = None
    for path in found:
        if path.replace("\\", "/").endswith("/byar/versions.gz"):
            for line in gzip.decompress(read(path)).decode().splitlines():
                parts = line.split(",", 3)
                if parts[0] == "byar:test":
                    tag = parts
    if not tag:
        sys.exit("byar:test is not in " + ("the phone" if adb else bar))
    data = gzip.decompress(read("packages/" + tag[1] + ".sdp"))
    i = 0
    while i < len(data):
        n = data[i]
        name = data[i + 1:i + 1 + n].decode().lower()
        md5 = data[i + 1 + n:i + 17 + n].hex()
        i += 1 + n + 16 + 8
        if name == FILE:
            return tag[3], md5, gzip.decompress(read("pool/" + md5[:2] + "/" + md5[2:] + ".gz"))
    sys.exit(FILE + " is not in " + tag[3])


HEADER = """\
-- BAR Droid build menu: BAR's own Build menu (luaui/Widgets/gui_buildmenu.lua, by Floris, GPL v2 or later), from
-- {release}, unchanged except where marked "BAR Droid:" (Kailil, 2026-10-28: "the vaniallal build menu works fine for
-- touch. just rebuild the exact same one with the ability for us to resize it freely"): its place and size come from
-- the app's layout editor (bardroid_layout.lua), and the widget-handler calls go through BAR's stand-in for the handler
-- that user widgets get. Made by tools/make-buildmenu.py; do not edit by hand, run it again.
-- launch-bar.sh runs it instead of BAR's Build menu; when an update changes BAR's file the phone makes it again from the
-- new file (the line below names the one it was made from; Installer, BuildMenuPatches); in the controller game, which keeps its
-- own ("Build menu (controller)", v0.8.5's gamepad drives it), this one runs beside it and shows only while the app's
-- gamepad controls have the pad (a triple tap switches; WG.bardroidBuildmenu there, BAR's WG.buildmenu stays v0.8.5's).
-- BARDROID_BUILDMENU_FROM {md5}
"""

# (what to find, exactly once; what goes in its place)
PATCHES = [
    ('''local maxPosY = 0.74
''',
     '''local maxPosY = 0.74
-- BAR Droid: what the app adds, in one table (BAR's file is near Lua 5.1's limit of 200 locals in a chunk). At the left
-- a grid of colls x rows square cells across the menu's width (Kailil, 2026-10-28: "a 3x3 grid"), and the page arrows and
-- number in a strip under it, strip x a cell's height ("move the left and right arrows into their own small strip,
-- it will be about a quarter the height ... that will allow 3x3 items on top"; then "the page swapper and inidcator
-- needs to be bigger. double the size": half a cell, their text pageText x BAR's): 9 options a page. (BAR's own
-- paging gave a whole row to the arrows: 6 a page, the first version of this.)
-- While a building is picked the strip holds the building shapes instead (droid.place): ONE, LINE, GRID, BORDER
-- (Kailil, 2026-10-28, choosing "the build menu's own page strip turns into ONE . LINE . GRID . BORDER" for the touch
-- building of 2026-10-25, which he had removed as "ugly and clunky to switch between"), and a big green PLACE button
-- lies over the order menu with rotate and cancel inside it ("one tap needs to have a done confirmation ... appear on
-- top of the orders menu as one big green button saying done or place"; "Get rid of the circle and x and move those to
-- the order menu button popup with done as smaller sub buttons"): a tap on the map picks the spot (droid.spot, the
-- building drawn there), PLACE builds it there (the app clicks the spot with Shift held: RtsTouch).
-- The gamepad (the app makes it a mouse and keys in BAR's game; Kailil: "try your best to finesse a way" to v0.8.5's
-- feel, "RB with builder selected snaps the mouse to the build menu grid spot one, then a highlight stroke and
-- enlargement of like 10 percent of the build item ... pressing A snaps the mouse to the center of the screen ready to
-- place it"): RB puts the pointer on the menu's first option (droid.focus), the D-pad steps from option to option
-- (past the left or right edge: the page before or after), the option under the pointer is drawn 10% bigger with a
-- gold outline, A (a click) picks it and the pointer goes to the middle of the screen; B leaves the menu.
-- bardroid_pad.lua tells the app (droidFocus) and routes the pad's actions here (droidPad).
-- With ONE (Kailil, 2026-10-29) the app moves the waiting building (droid.spot) under a dragging finger or by a nudge,
-- and a finger held still (or a drag from the building) makes it the first corner of a GRID: the app holds BAR's own
-- build drag down with Shift+Alt, the engine draws it, and PLACE or a double tap lets go (droid.gridHeld: PLACE lit;
-- "GRID" shown for a moment, droid.gridShown).
local droid = { colls = 3, maxColls = 5, rows = 3, strip = 0.5, pageText = 2, gap = 0, registered = false,
	shape = "one", armed = false, defID = nil, spot = nil, panel = nil, written = nil, writtenAt = nil, shapeRects = {},
	gridHeld = nil, gridShown = nil, gridToast = 1.2, nudgeCarry = { 0, 0 },
	file = "LuaUI/Config/bardroid_place.txt",
	focus = nil, warped = nil, warpTo = nil, warp = Spring.WarpMouse, fakeWarp = false, ctl = false, shared = nil,
	wasActive = nil, leave = 0.25, settled = 150, redraw = 900, drawnAt = nil,
	items = { { "one", "ONE" }, { "line", "LINE" }, { "grid", "GRID" }, { "border", "BORDER" } } }
'''),
    ('''	-- adjust grid size when pages are needed
''',
     '''	-- BAR Droid: the grid at the left, droid.colls x droid.rows, the page strip under it. Where the menu's height keeps
	-- the cells smaller than a third of its width (a wide, short screen: the Fold7 folded, the dev phone) more columns
	-- of that size fill the sides that stood empty, up to droid.maxColls (Kailil, 2026-11-02: "try 5 x 3")
	droid.gap = 0
	if not stickToBottom then
		colls = droid.colls
		cellSize = math_floor(math_min(contentWidth / colls, contentHeight / (droid.rows + droid.strip)))
		colls = math_max(colls, math_min(droid.maxColls, math_floor(contentWidth / math_max(1, cellSize))))
		rows = droid.rows
		droid.gap = math_floor((contentWidth - colls * cellSize) / 2) -- (the grid in the middle of the menu)
	end

	-- adjust grid size when pages are needed
'''),
    ('''	else
		currentPage = 1
		pages = 1
	end

	-- these are globals so it can be reused (hover highlight)''',
     '''	else
		currentPage = 1
		pages = 1
	end
	-- BAR Droid: at the left all droid.rows stay items, the arrows in the strip under them
	if not stickToBottom then
		rows = droid.rows
		pages = math_max(1, math_ceil(cmdsCount / (colls * rows)))
		if currentPage > pages then
			currentPage = pages
		end
	end

	-- these are globals so it can be reused (hover highlight)'''),
    ('''		-- make pixel aligned
		width = math_floor(width * vsx) / vsx
		height = math_floor(height * vsy) / vsy
	end
''',
     '''		-- make pixel aligned
		width = math_floor(width * vsx) / vsx
		height = math_floor(height * vsy) / vsy

		-- BAR Droid: as tall as droid.rows cells as wide as the menu allows, and the page strip under them (Kailil:
		-- "increase the total height of the build menu to allow the pictures to fill their squares"); its bottom
		-- above the unit panel, also the app's made taller in the layout editor (droid.infoHeight)
		droid.infoHeight = droid.infoTall()
		if droid.infoHeight and droid.infoHeight + widgetSpaceMargin / vsy > posY2 then
			posY2 = math.min(droid.infoHeight + widgetSpaceMargin / vsy, posY - 0.1)
			height = math_floor((posY - posY2) * vsy) / vsy
		end
		local cellPx = (width * vsx - (bgpadding + activeAreaMargin) * 2) / droid.colls
		local want = math_floor((droid.rows + droid.strip) * cellPx + (bgpadding + activeAreaMargin) * 2) / vsy
		if want < height then
			height = want
			posY = posY2 + height
		end
	end
'''),
    ('''		name = "Build menu",
		desc = "",
		author = "Floris",''',
     '''		name = "BAR Droid build menu", -- BAR Droid: its own name (BAR ignores copies under BAR's)
		desc = "BAR's Build menu, its size and place set with the BAR Droid layout editor",
		author = "Floris (BAR's Build menu), BAR Droid",'''),
    ('''		layer = 0,
		enabled = false,
		handler = true,
	}''',
     '''		layer = 0,
		enabled = false, -- BAR Droid: launch-bar.sh switches it on in place of BAR's Build menu (no handler: a user widget)
	}'''),
    ('''function widget:ViewResize()
	tracy.ZoneBeginN("W:BuildMenu:ViewResize")''',
     '''-- BAR Droid: the layout editor's settings for the menu (moved by dx, dy of the screen; size)
function droid.edits()
	local editor = WG.BarDroidLayout
	return editor and editor.get("buildmenu") or { dx = 0, dy = 0, size = 1 }
end

-- BAR Droid: the unit panel's height (of the screen), BAR's or the app's (bardroid_info.lua, sized in the layout editor)
function droid.infoTall()
	local info = WG.info
	if info and info.getPosition then
		local _, h = info.getPosition()
		return h
	end
end

-- BAR Droid: the menu for the layout editor, once it is there (BAR's own shows in it as fixed)
function droid.register()
	local editor = WG.BarDroidLayout
	if droid.registered or not (editor and editor.register) then
		return
	end
	droid.registered = true
	editor.register("buildmenu", {
		label = "Build menu",
		can = { move = true, size = true },
		rect = function() -- (none while hidden: the controller game with v0.8.5's controls, its own menu in the place)
			if not droid.active() then
				return nil
			end
			return backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4]
		end,
		relayout = function()
			widget:ViewResize()
		end,
	})
end

-- BAR Droid: a building picked (from this menu, a key or before the start), the shape for it, the PLACE button and the
-- spot a tap picked, for the app (RtsTouch: how a finger on the map builds it), in LuaUI/Config/bardroid_place.txt,
-- X screen pixels (top left origin):
--   place <one|line|grid|border|none>
--   done <x0> <y0> <x1> <y1>    (the PLACE button, without its rotate and cancel)
--   spot <x> <y> <r>            (where the spot is on the screen now, and the building's size there; only while it is)
--   rotate, cancel <x0> <y0> <x1> <y1>    (the buttons beside PLACE: a GRID's left button is down, so taps there are the app's)
-- The strip is drawn again when the building is picked or put away.
function droid.place()
	if droid.again then
		droid.pickAgain()
	end
	local active = droid.active()
	if active ~= droid.wasActive then -- (the controller game: shown or hidden with the app's controls)
		droid.wasActive = active
		if not active then
			droid.endFocus()
		end
		clear()
		doUpdate = true
	end
	local defID
	if spGetGameFrame() == 0 and WG["pregame-build"] and WG["pregame-build"].getPreGameDefID then
		defID = WG["pregame-build"].getPreGameDefID()
	else
		local _, id = spGetActiveCommand()
		defID = id and id < 0 and -id or nil
	end
	local armed = defID ~= nil
	if defID ~= droid.defID then
		droid.defID, droid.spot = defID, nil -- (another building: the spot was for the last one)
	end
	if armed ~= droid.armed then
		droid.armed = armed
		if not armed then
			droid.gridHeld = nil
			droid.shape = "one" -- (each building picked starts with ONE: a drag pans the map until a shape is chosen)
		elseif droid.focus then
			droid.endFocus() -- (picked with the gamepad: the app glides the pointer to the middle, ready to place it)
		end
		clear()
	end
	droid.padFocus()
	if not armed and droid.written == "place none\\n" then
		droid.panel = nil
		return
	end
	droid.layoutPanel()
	local text = "place " .. (armed and droid.shape or "none") .. "\\n"
	local p = droid.panel
	if p then
		for _, b in ipairs({ { "done", p.place }, { "rotate", p.rotate }, { "cancel", p.cancel } }) do
			local r = b[2]
			text = text .. string.format("%s %d %d %d %d\\n", b[1], r[1], vsy - r[4], r[3], vsy - r[2])
		end
	end
	local sx, sy, sr = droid.spotOnScreen()
	if sx then
		text = text .. string.format("spot %d %d %d\\n", sx, vsy - sy - 1, sr)
	end
	-- (written again every second while a building is picked: the app takes an older file for none, so a file left by
	-- a game that ended with a building picked never turns taps into Shift clicks)
	local now = Spring.GetTimer()
	if text ~= droid.written or (armed and Spring.DiffTimers(now, droid.writtenAt) > 1) then
		-- written whole, then renamed: the app must never read it empty (io.open "w" empties it first), which made a
		-- tap a plain click that placed the building at once
		local f = io.open(droid.file .. ".tmp", "w")
		if f then
			f:write(text)
			f:close()
			local ok, renamed = pcall(os.rename, droid.file .. ".tmp", droid.file)
			if not (ok and renamed) then -- (Windows, for the laptop tests: rename does not replace a file)
				pcall(os.remove, droid.file)
				pcall(os.rename, droid.file .. ".tmp", droid.file)
			end
			droid.written, droid.writtenAt = text, now
		end
	end
end

-- BAR Droid: the spot a tap picked (X screen pixels; nil: none): the building goes there when PLACE is tapped
-- BAR Droid: the building the app has just placed, picked again: the engine keeps a Shift click's building only until Shift
-- comes up (CGuiHandler needShift), and it stays picked for the next spot, until the cancel button or a long press
function droid.pickAgain()
	local again = droid.again
	local _, id = spGetActiveCommand()
	again.frames = again.frames - 1
	if id == nil and spGetGameFrame() > 0 then
		droid.again = nil
		local index = Spring.GetCmdDescIndex(-again.defID)
		if index then
			Spring.SetActiveCommand(index, 1, true, false, false, false, false, false)
		end
	elseif id ~= -again.defID or again.frames <= 0 then
		droid.again = nil -- (another order picked, or Shift never came up)
	end
end

function droid.setSpot(x, y, placed)
	droid.spot, droid.nudgeCarry = nil, { 0, 0 }
	if placed and droid.defID then -- (RtsTouch sent the building off: "spot placed")
		droid.again = { defID = droid.defID, frames = 30 } -- (frames, not seconds: a slow frame must not lose it)
	end
	if x and y and droid.armed then
		local _, pos = Spring.TraceScreenRay(x, vsy - y - 1, true)
		if pos then
			droid.spot = { pos[1], pos[2], pos[3] }
		end
	end
	droid.place()
end

-- (a map point moved by dx, dy X screen pixels, y down: the ground under the pixel it lands on; nil: off the screen
-- or over the sky. The part of a pixel left over is carried to the next move: the app sends a finger's way in small
-- steps)
function droid.screenMove(p, dx, dy, carry)
	local sx, sy, sz = Spring.WorldToScreenCoords(p[1], p[2], p[3])
	if sz > 1 then
		return nil
	end
	local tx, ty = sx + dx + carry[1], sy - dy + carry[2]
	local ix, iy = math_floor(tx + 0.5), math_floor(ty + 0.5)
	local _, pos = Spring.TraceScreenRay(ix, iy, true)
	if not pos then
		return nil
	end
	carry[1], carry[2] = tx - ix, ty - iy
	return { pos[1], pos[2], pos[3] }
end

-- BAR Droid: the waiting building moved by a finger's nudge, X screen pixels
function droid.nudge(dx, dy)
	local s = droid.spot
	local moved = s and droid.armed and dx and dy and droid.screenMove(s, dx, dy, droid.nudgeCarry)
	if not moved then
		return
	end
	droid.spot = moved
	droid.place()
end

-- BAR Droid: the app's GRID, BAR's own build drag with its left button held until PLACE (RtsTouch): "held" or "free"
function droid.setGrid(kind)
	if kind == "held" then
		droid.gridHeld, droid.gridShown = true, Spring.GetTimer()
	elseif kind == "free" then
		droid.gridHeld = nil
	end
	droid.place()
end

-- (a point the app may click on the map: on the screen, not under this menu, PLACE or the minimap)
function droid.clickable(bx, by, bz)
	local sx, sy, sz = Spring.WorldToScreenCoords(bx, by, bz)
	if sz > 1 or sx < 0 or sy < 0 or sx >= vsx or sy >= vsy or widget:IsAbove(sx, sy) or Spring.IsAboveMiniMap(sx, sy) then
		return nil
	end
	local P = WG.BarDroidPortrait -- (not under the portrait dock either: the click would land on it)
	local d = P and P.dock and P.dock()
	if d and sx >= d[1] and sx <= d[3] and sy >= d[2] and sy <= d[4] then
		return nil
	end
	return math_floor(sx), math_floor(sy)
end

-- (the building's place on the build grid at the spot, and where that is on the screen)
function droid.spotPos()
	local s = droid.spot
	if not (s and droid.defID) then
		return nil
	end
	return Spring.Pos2BuildPos(droid.defID, s[1], s[2], s[3], Spring.GetBuildFacing())
end
-- (none when it is off the screen or under this menu, PLACE or the minimap: a click there would hit them, not the map;
-- with it the building's size on the screen, pixels from its middle)
function droid.spotOnScreen()
	local bx, by, bz = droid.spotPos()
	if not bx then
		return nil
	end
	local sx, sy = droid.clickable(bx, by, bz)
	if not sx then
		return nil
	end
	local def = UnitDefs[droid.defID]
	local half = math.max(def.xsize, def.zsize) * 4
	local r = 0
	for _, d in ipairs({ { half, 0 }, { 0, half } }) do
		local ex, ey = Spring.WorldToScreenCoords(bx + d[1], by, bz + d[2])
		r = math.max(r, math.sqrt((ex - sx) ^ 2 + (ey - sy) ^ 2))
	end
	return sx, sy, math_floor(r + 0.5)
end

-- BAR Droid: the building at the spot, as the engine draws a building being placed, and its footprint
function droid.drawSpot()
	local bx, by, bz = droid.spotPos()
	if not bx then
		return
	end
	local def = UnitDefs[droid.defID]
	local facing = Spring.GetBuildFacing()
	gl.DepthTest(true)
	gl.PushMatrix()
	gl.Translate(bx, by, bz)
	gl.Rotate(90 * facing, 0, 1, 0)
	gl.UnitShape(droid.defID, Spring.GetMyTeamID(), false, false, false)
	gl.PopMatrix()
	gl.DepthTest(false)
	-- (its footprint on the ground, green as the engine's own placement square, turned with the building: Kailil,
	-- 2026-11-11, "remove the green circle cursor radial that follows my finger"; the ring around it is gone)
	local fx, fz = (def and def.xsize or 2) * 4, (def and def.zsize or 2) * 4
	if facing % 2 == 1 then
		fx, fz = fz, fx
	end
	gl.Color(0.3, 1, 0.3, 0.45)
	gl.DrawGroundQuad(bx - fx, bz - fz, bx + fx, bz + fz)
	gl.Color(1, 1, 1, 1)
end

-- BAR Droid: "GRID" over the waiting building for a moment once a GRID starts, in v0.8.5's blue (its "SLOW PAN")
function droid.drawGridShown()
	local t = droid.gridShown
	local age = t and Spring.DiffTimers(Spring.GetTimer(), t)
	if not age or age > droid.gridToast then
		droid.gridShown = nil
		return
	end
	local bx, by, bz = droid.spotPos()
	local sx, sy, sz
	if bx then
		sx, sy, sz = Spring.WorldToScreenCoords(bx, by, bz)
	end
	if not sx or sz > 1 then
		sx, sy = vsx / 2, vsy / 2
	end
	local alpha = math.max(0, math.min(1, age / 0.08, (droid.gridToast - age) / 0.3))
	local s = WG.BarDroidStyle
	if s then -- (the app's controller look: a note in BAR's panel, as the pad's)
		s.toast("GRID", sx, sy + s.size(0.035), s.BLUE, alpha)
		return
	end
	local size = math.max(16, math_floor(vsy * 0.045))
	font2:Begin(true)
	font2:SetTextColor(0.2, 0.8, 1, alpha)
	font2:SetOutlineColor(0, 0, 0, 0.8)
	font2:Print("GRID", sx, math.min(vsy - size, sy + size * 1.4), size, "co")
	font2:End()
end

-- BAR Droid: the PLACE button over the order menu (else under the middle of the screen), rotate and cancel inside it
-- at the right, each a square of 0.7 of its height
function droid.layoutPanel()
	droid.panel = nil
	if not droid.armed or WG.BarDroidInput == "pad" or WG.BarDroidInput == "mouse" then -- (fingers' only: A or a
		return -- click places where the pointer is)
	end
	local x0, y0, x1, y1
	local o = WG.ordermenu
	local dock = WG.BarDroidPortrait and WG.BarDroidPortrait.placeRect and WG.BarDroidPortrait.placeRect()
	if dock then -- (the portrait dock, bardroid_portrait.lua: its place for it, under the shapes)
		x0, y0, x1, y1 = dock[1], dock[2], dock[3], dock[4]
	elseif o and o.getPosition and o.getIsShowing and o.getIsShowing() then
		local x, y, w, h = o.getPosition()
		if x and h then
			x0, y0, x1, y1 = x * vsx, (y - h) * vsy, (x + w) * vsx, y * vsy
		end
	end
	if not x0 then
		-- (no order menu: before the game. Under the build menu when there is room; at the bottom's middle it went
		-- behind BAR's "Pick your faction" panel there, rotate and cancel hidden, 2026-11-09)
		local b, h, gap = backgroundRect, vsy * 0.14, vsy * 0.01
		if b[3] > b[1] and b[2] - h - gap >= 0 then
			x0, y0, x1, y1 = b[1], b[2] - h - gap, b[3], b[2] - gap
		else
			x0, y0, x1, y1 = vsx * 0.35, 0, vsx * 0.65, vsy * 0.14
		end
	end
	x0, y0, x1, y1 = math_floor(x0), math_floor(y0), math_floor(x1), math_floor(y1)
	local pad = math_floor(math.max(2, (y1 - y0) * 0.08))
	local s = math_floor(math.min((y1 - y0) * 0.7, (x1 - x0) * 0.2))
	local my = math_floor((y0 + y1 - s) / 2)
	local cs = s
	if dock then -- (upright, the tall panel: at its bottom right corner; Kailil, 2026-11-10; its cancel twice the size,
		-- 2026-11-11: "make the X button on place 100 percent bigger")
		my = y0 + pad
		cs = math_floor(math.min(s * 2, (y1 - y0) - 2 * pad, (x1 - x0) * 0.45))
	end
	local cancel = { x1 - pad - cs, my, x1 - pad, my + cs }
	-- (upright ROTATE as tall as the X, 80 % as wide: a small square beside it, a thumb's target, 2026-11-11)
	local rw, rh = s, s
	if dock then
		rw, rh = math_floor(cs * 0.8), cs
	end
	local rotate = { cancel[1] - pad - rw, my, cancel[1] - pad, my + rh }
	-- (upright PLACE is the whole panel but its two buttons, which RtsTouch and pressPanel tell first: the column above
	-- them was a dead part of the green panel, dev phone screenshot 2026-11-11)
	local place = dock and { x0, y0, x1, y1 } or { x0, y0, rotate[1] - pad, y1 }
	droid.panel = { all = { x0, y0, x1, y1 }, place = place, rotate = rotate, cancel = cancel }
end

function droid.drawPanel()
	local p = droid.panel
	if not p then
		return
	end
	-- (green once a tap has picked the spot, while it can be clicked, or while a GRID waits)
	local ready = droid.gridHeld or droid.spotOnScreen() ~= nil
	local a = p.all
	UiButton(a[1], a[2], a[3], a[4], 1, 1, 1, 1, 1, 1, 1, 1, nil,
		ready and { 0.1, 0.5, 0.1, 1 } or { 0.1, 0.25, 0.1, 1 }, ready and { 0.25, 0.8, 0.25, 1 } or { 0.2, 0.35, 0.2, 1 },
		bgpadding * 0.5) -- (solid: the order menu's buttons are under it)
	for _, name in ipairs({ "rotate", "cancel" }) do
		local r = p[name]
		UiButton(r[1], r[2], r[3], r[4], 1, 1, 1, 1, 1, 1, 1, 1, nil, { 0, 0, 0, 0.55 }, { 0.15, 0.15, 0.15, 0.6 }, bgpadding * 0.4)
	end
	font2:Begin(true)
	local pl = p.place
	local size = math.min((pl[4] - pl[2]) * 0.45, (pl[3] - pl[1]) * 0.8 / math.max(0.01, font2:GetTextWidth("PLACE")))
	font2:Print((ready and "\\255\\255\\255\\255" or "\\255\\150\\190\\150") .. "PLACE", (pl[1] + pl[3]) / 2,
		(pl[2] + pl[4]) / 2 - size * 0.3, size, "co")
	local r = p.rotate
	local sym = (r[4] - r[2]) * 0.6
	font2:Print("\\255\\235\\235\\235\\226\\134\\187", (r[1] + r[3]) / 2, (r[2] + r[4]) / 2 - sym * 0.3, sym, "co")
	r = p.cancel -- (its cross a soft red: in the green panel it read as one more way to build)
	font2:Print("\\255\\255\\150\\140\\226\\156\\149", (r[1] + r[3]) / 2, (r[2] + r[4]) / 2 - sym * 0.3, sym, "co")
	font2:End()
end

-- BAR Droid: a press on the PLACE button: rotate turns the building, cancel puts it away; PLACE itself is the app's
-- (it clicks the spot); a mouse there does nothing
function droid.pressPanel(x, y)
	local p = droid.panel
	local function inside(r)
		return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
	end
	if not (p and inside(p.all)) then
		return false
	end
	if inside(p.rotate) then
		Spring.SendCommands("buildfacing inc")
	elseif inside(p.cancel) then
		droid.spot, droid.again = nil, nil
		-- (before the game: BAR's pregame queue's setPreGamestartDefID; its old name setPreGameDefID, which this called,
		-- is gone, and cancel did nothing there)
		local pb = spGetGameFrame() == 0 and WG["pregame-build"]
		local putAway = pb and (pb.setPreGamestartDefID or pb.setPreGameDefID)
		if putAway then
			putAway(nil)
		else
			Spring.SetActiveCommand(0)
		end
	end
	droid.place()
	return true
end

-- BAR Droid: the shape strip, in the page strip's place (area: the menu's inner rect; h: the strip's height)
function droid.drawShapes(area, width, h)
	local w = width / #droid.items
	local y0, y1 = area[2], area[2] + h - cellPadding - activeAreaMargin
	-- (one size for all: the page strip's, which they replace; at half the strip's height they read a size smaller)
	local size = math.min(math.max(0.016 * vsy, h * 0.2) * droid.pageText, (y1 - y0) * 0.62,
		w * 0.8 / math.max(0.01, font2:GetTextWidth("BORDER")))
	for i, item in ipairs(droid.items) do
		local x0 = area[1] + (i - 1) * w
		local rect = { x0, y0, x0 + w, y1, item[1] }
		droid.shapeRects[#droid.shapeRects + 1] = rect
		-- (the picked one gold with white words: its pale gold words on the gold read worst of the four, dev phone
		-- 2026-11-03)
		local lit = item[1] == droid.shape
		UiButton(rect[1] + cellPadding, rect[2] + cellPadding, rect[3] - cellPadding, rect[4] - cellPadding,
			1, 1, 1, 1, 1, 1, 1, 1, nil,
			lit and { 0.38, 0.3, 0.04, 0.9 } or { 0, 0, 0, 0.8 }, lit and { 0.66, 0.53, 0.12, 0.9 } or { 0.2, 0.2, 0.2, 0.8 },
			bgpadding * 0.5)
		font2:Print((lit and "\\255\\255\\255\\255" or "\\255\\235\\235\\235") .. item[2], x0 + w * 0.5,
			(y0 + y1) * 0.5 - size * 0.3, size, "co")
	end
end

-- BAR Droid: a tap on the shape strip picks the shape
function droid.press(x, y)
	for _, r in ipairs(droid.shapeRects) do
		if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
			droid.shape = r[5]
			clear()
			droid.place()
			return true
		end
	end
	return false
end

-- BAR Droid: the gamepad's buttons for the menu (bardroid_touch.lua's pad_* actions): build (RB: on, or off again),
-- back (B), left, right, up, down (the D-pad)
function droid.cellAt(x, y)
	for id, r in pairs(cellRects) do
		if cmds[id] and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
			return id
		end
	end
end

-- (the app glides the pointer back to the middle once no menu has the pad: Kailil, "make sure that snap back is smooth";
-- in the controller game the menu goes with the pad)
function droid.endFocus()
	droid.focus, droid.warpTo, droid.warped, droid.outSince = nil, nil, nil, nil
	droid.opened, droid.openedAt = false, nil
end

-- BAR Droid: the menu is shown and takes input (the controller game: only while the app's controls have the pad; then,
-- once the pad is in use (WG.BarDroidPadOnly: until a few taps), only after RB has opened it, as v0.8.5's own; Kailil,
-- 2026-10-29: hidden until RB, "to save screen space"; 2026-10-30, by touch: "open in its usual location. not hide by
-- default like gamepad behavior"; the PLACE button and a building's spot work either way, for fingers)
function droid.active()
	if WG.BarDroidPortrait and WG.BarDroidPortrait.active() then -- (the portrait dock has its own grid; PLACE stays this one's)
		return false
	end
	return not droid.ctl or (WG.BarDroidOwnsBuildMenu == true and (droid.opened == true or not WG.BarDroidPadOnly))
end

function droid.pad(name)
	if name == "build" then
		if droid.focus or droid.openedAt then
			droid.endFocus()
		elseif buildmenuShows and cmdsCount > 0 then
			droid.focus = math.min(cmdsCount, (currentPage - 1) * colls * rows + 1)
			droid.warpTo = droid.focus
			droid.opened = true -- (a menu fingers left open: it stays, now the pad is in use)
		elseif droid.ctl and WG.BarDroidOwnsBuildMenu == true then -- (opened: the pad on it once it is laid out)
			droid.opened, droid.openedAt, droid.openedWait = true, Spring.GetTimer(), 0
			doUpdate = true
		end
	elseif not droid.focus then
		return
	elseif name == "back" then
		droid.endFocus()
	elseif name == "pagenext" or name == "pageprev" then -- RB / LB on the menu (Kailil: "pressing RB or LB cycles the
		local per = colls * rows -- tabs"): the same place on the page after or before
		local page = math_ceil(droid.focus / per)
		local i = droid.focus - (page - 1) * per
		page = name == "pagenext" and page % pages + 1 or (page + pages - 2) % pages + 1
		local target = math.min(cmdsCount, (page - 1) * per + i)
		if page ~= currentPage then
			currentPage = page
			doUpdate = true
		end
		droid.focus, droid.warpTo = target, target
	else
		-- (from the focused option, not the one under the pointer: two quick presses come before the pointer has
		-- moved; the focus follows the pointer once it is the player's again, droid.padFocus)
		local per = colls * rows
		local id = droid.focus
		local page = math_ceil(id / per)
		local i = id - (page - 1) * per - 1
		local row, col = math_floor(i / colls), i % colls
		if name == "left" then
			col = col - 1
		elseif name == "right" then
			col = col + 1
		elseif name == "up" then
			row = math.max(0, row - 1)
		elseif name == "down" then
			row = math.min(rows - 1, row + 1)
		end
		if col < 0 then
			page, col = page - 1, colls - 1
		elseif col >= colls or (name == "right" and (page - 1) * per + row * colls + col + 1 > cmdsCount) then
			page, col = page + 1, 0 -- (right past the last option too: it stayed on it, stuck)
		end
		page = page < 1 and pages or (page > pages and 1 or page)
		local target = math.min(cmdsCount, (page - 1) * per + row * colls + col + 1)
		if page ~= currentPage then
			currentPage = page
			doUpdate = true
		end
		droid.focus, droid.warpTo = target, target
	end
	droid.padFocus()
end

-- (each Update: the pointer onto the focused option once the menu has laid it out; once the pointer has got there
-- (or half a second on) it is the player's again: the focus follows it over the options and ends off the menu, as
-- when the menu goes)
function droid.padFocus()
	if droid.openedAt then -- (the controller game: RB opened the menu; nothing to build after half a second: closed)
		if buildmenuShows and cmdsCount > 0 then
			droid.openedAt = nil
			droid.focus = math.min(cmdsCount, (currentPage - 1) * colls * rows + 1)
			droid.warpTo = droid.focus
		else
			droid.openedWait = droid.openedWait + 1 -- (and a few frames: a stall outlasts half a second before it is laid out)
			if droid.openedWait > 8 and Spring.DiffTimers(Spring.GetTimer(), droid.openedAt) > 0.5 then
				droid.endFocus()
			end
		end
	end
	if droid.focus then
		local now = Spring.GetTimer()
		if not buildmenuShows then
			droid.endFocus()
		elseif droid.warpTo then
			local r = cellRects[droid.warpTo]
			if r then
				local x, y = math_floor((r[1] + r[3]) / 2), math_floor((r[2] + r[4]) / 2)
				droid.warp(x, y)
				droid.warpTo, droid.warped = nil, { x, y, now }
			end
		elseif not droid.fakeWarp then
			local mx, my = spGetMouseState()
			local w = droid.warped
			if w and ((math.abs(mx - w[1]) <= 2 and math.abs(my - w[2]) <= 2) or Spring.DiffTimers(now, w[3]) > 0.5) then
				droid.warped, w = nil, nil
			end
			if not w then
				-- (kept on the menu: pushed off it for droid.leave seconds the pointer is let go - Kailil: "let the mouse
				-- leave it if i press B only or i constantly move the left stick out of the box", then "make it a quarter
				-- long instead": 0.25 s)
				local id = droid.cellAt(mx, my)
				if id then
					droid.focus = id
				end
				local r = backgroundRect
				local x0, y0, x1, y1 = r[1] + 2, r[2] + 2, r[3] - 2, r[4] - 2
				if mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
					droid.outSince = nil
				elseif droid.outSince and Spring.DiffTimers(now, droid.outSince) >= droid.leave then
					droid.endFocus()
				else
					droid.outSince = droid.outSince or now
					droid.warp(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				end
			end
		end
	end
end

-- BAR Droid: the option under the pointer, with the gamepad: 10% bigger, a gold line round it (the app's controller
-- look, WG.BarDroidStyle: as the order on the pad in the order menu)
function droid.drawHover(cellID, list)
	local r = cellRects[cellID]
	if not (r and (droid.focus or WG.BarDroidInput == "pad")) then
		gl.CallList(list)
		return
	end
	local cx, cy = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
	gl.PushMatrix()
	gl.Translate(cx, cy, 0)
	gl.Scale(1.1, 1.1, 1)
	gl.Translate(-cx, -cy, 0)
	gl.CallList(list)
	droid.goldLine(r)
	gl.PopMatrix()
end

-- BAR Droid: a gold line round a cell (rect r; width: of the cell's, else the style's)
function droid.goldLine(r, width)
	local s = WG.BarDroidStyle
	local x0, y0, x1, y1 = r[1] + cellPadding, r[2] + cellPadding, r[3] - cellPadding, r[4] - cellPadding
	local w = width and math.max(2, math_floor((r[3] - r[1]) * width)) or nil
	if s then
		s.outline(x0, y0, x1, y1, s.GOLD, 1, w)
	else
		local t = w or math.max(2, math_floor((r[3] - r[1]) * 0.03))
		gl.Color(1, 0.78, 0.25, 1)
		gl.Rect(x0, y0, x1, y0 + t)
		gl.Rect(x0, y1 - t, x1, y1)
		gl.Rect(x0, y0, x0 + t, y1)
		gl.Rect(x1 - t, y0, x1, y1)
		gl.Color(1, 1, 1, 1)
	end
end

-- BAR Droid: while a building is picked, its option with the gold line (BAR's lighter cell alone read faintly on the
-- phone, 2026-11-04; gold is the app's "on": QUEUE, the picked shape below it). Not while the pad is on the menu
-- (its own gold line is the focus).
function droid.drawPicked()
	if not (droid.armed and droid.defID) or droid.focus then
		return
	end
	for id, r in pairs(cellRects) do
		if cmds[id] and cmds[id].id == -droid.defID then
			droid.goldLine(r, 0.04) -- (the pad focus's 2 px read as a hairline on the dev phone)
			return
		end
	end
end

function widget:ViewResize()
	tracy.ZoneBeginN("W:BuildMenu:ViewResize")'''),
    ('''function widget:Update(dt)
''',
     '''function widget:Update(dt)
	droid.register() -- BAR Droid
	droid.place()
	if not stickToBottom and droid.infoTall() ~= droid.infoHeight then -- BAR Droid: the unit panel's height changed
		widget:ViewResize()
	end
'''),
    ('''	-- paginator
	if pages == 1 then
		paginatorRects = {}
	else''',
     '''	-- paginator (BAR Droid: while a building is picked, the shape strip in its place)
	droid.shapeRects = {}
	if droid.armed and not stickToBottom then
		paginatorRects = {}
		droid.drawShapes(activeArea, contentWidth, paginatorCellHeight)
	elseif pages == 1 then
		paginatorRects = {}
	else'''),
    ('''		if selectedBuilderCount > 0 or (preGamestartPlayer and startDefID) then
			if
				paginatorRects[1]''',
     '''		if selectedBuilderCount > 0 or (preGamestartPlayer and startDefID) then
			if droid.press(x, y) then -- BAR Droid: the shape strip
				return true
			end
			if
				paginatorRects[1]'''),
    ('''	backgroundRect = { posX, (posY - height) * vsy, posX2, posY * vsy }

	checkGuishader(true)''',
     '''	-- BAR Droid: the layout editor's size (width and height from the menu's bottom left corner) and place
	local edit = droid.edits()
	if edit.size ~= 1 or edit.dx ~= 0 or edit.dy ~= 0 then
		local bottom = posY - height
		width, height = width * edit.size, height * edit.size
		local w = math_floor(width * vsx)
		posX = math.clamp(posX + math_floor(edit.dx * vsx), 0, math.max(0, vsx - w))
		posX2 = posX + w
		bottom = math.clamp(bottom + edit.dy, 0, math.max(0, 1 - height))
		posY, posY2 = bottom + height, bottom
	end
	backgroundRect = { posX, (posY - height) * vsy, posX2, posY * vsy }

	checkGuishader(true)'''),
    ('''function widget:DrawWorld()
	-- Avoid unnecessary overhead after buildqueue has been setup in early frames
	if spGetGameFrame() > 0 then
		widgetHandler:RemoveWidgetCallIn("DrawWorld", self)
		return
	end''',
     '''-- BAR Droid: the menu and the PLACE button are interface: a finger there clicks, it does not pan or pick a spot
function widget:IsAbove(x, y)
	local r, p = backgroundRect, droid.panel
	return (buildmenuShows and r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4])
		or (p and x >= p.all[1] and x <= p.all[3] and y >= p.all[2] and y <= p.all[4]) or false
end

function widget:DrawWorld()
	droid.drawSpot() -- BAR Droid: the spot a tap picked (so this call-in stays after the start)
	-- Avoid unnecessary overhead after buildqueue has been setup in early frames
	if spGetGameFrame() > 0 then
		return
	end'''),
    ('''		elseif dlistBuildmenu then
			gl.CallList(dlistBuildmenu)
		end

		-- draw highlight''',
     '''		elseif dlistBuildmenu then
			gl.CallList(dlistBuildmenu)
		end
		droid.drawPicked() -- BAR Droid: the picked building's option outlined

		-- draw highlight'''),
    ('''					if hoverDlist then
						gl.CallList(hoverDlist)
					end''',
     '''					if hoverDlist then
						droid.drawHover(hoveredCellID, hoverDlist) -- BAR Droid: with the gamepad bigger, outlined
						droid.drawPicked() -- BAR Droid: again (a finger's tap leaves the pointer on the cell it picked,
						-- which BAR draws anew here)
					end'''),
    ('''function widget:DrawScreen()
	tracy.ZoneBeginN("W:BuildMenu:DrawScreen")
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
''',
     '''function widget:DrawScreen()
	tracy.ZoneBeginN("W:BuildMenu:DrawScreen")
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	droid.drawPanel() -- BAR Droid: the PLACE button (over the order menu)
	droid.drawGridShown() -- BAR Droid: "GRID" over a building for a moment
	if not droid.active() then -- BAR Droid: the controller game while v0.8.5 has the pad: its own menu shows
		tracy.ZoneEnd()
		return
	end
	-- BAR Droid: BAR draws the menu into its texture at a game's frame 0 and again about 1.4 s in, then only when
	-- something changes; at some starts on the phones its pictures came out of those drawings in stripes, every other
	-- 16 pixels empty, until the next change (dev phone, 2026-11-03: 2 of 8 starts; drawn every 1.5 s, only the drawings
	-- in the start's stutter were striped). A menu last drawn before droid.settled (5 s) is drawn once more then. And
	-- an unchanged menu again every droid.redraw (30 s): one start on the hot dev phone kept its stripes past the 5 s
	-- drawing (2026-11-04, stripes evenly spaced across the cells: the drawing into the texture, not the pictures; the
	-- next drawing clean), one drawing of the texture each time
	local droidFrame = spGetGameFrame()
	if droid.drawnAt and (droid.drawnAt < droid.settled and droidFrame >= droid.settled
		or droidFrame - droid.drawnAt >= droid.redraw) then
		droid.drawnAt = nil
		refreshBuildmenu = true
	end
'''),
    ('''		if buildmenuRenderedCells > 0 then
			buildmenuTexHasContent = true
''',
     '''		if buildmenuRenderedCells > 0 then
			droid.drawnAt = spGetGameFrame() -- BAR Droid: (droid.settled)
			buildmenuTexHasContent = true
'''),
    ('''	local prevBuildmenuShows = buildmenuShows
	if not preGamestartPlayer and selectedBuilderCount == 0 and not alwaysShow then''',
     '''	local prevBuildmenuShows = buildmenuShows
	if not droid.active() or (not preGamestartPlayer and selectedBuilderCount == 0 and not alwaysShow) then -- BAR Droid'''),
    ('''						if WG.tooltip and not meta then
							-- when meta: unitstats does the tooltip''',
     '''						if WG.tooltip and not meta and WG.BarDroidInput ~= "pad" and WG.BarDroidInput ~= "touch" then
							-- BAR Droid: with the pad or fingers it covers the grid's next row (a finger's pointer stays on
							-- the cell it tapped), and BAR's info panel says the same
							-- when meta: unitstats does the tooltip'''),
    ('''function widget:MousePress(x, y, button)
	if Spring.IsGUIHidden() then
		return
	end
''',
     '''function widget:MousePress(x, y, button)
	if Spring.IsGUIHidden() then
		return
	end
	if droid.pressPanel(x, y) then -- BAR Droid: the PLACE button
		return true
	end
	if not droid.active() then -- BAR Droid: hidden (the controller game while v0.8.5 has the pad)
		return
	end
'''),
    ('''function widget:Initialize()
	widgetHandler:RegisterUnitCommand(widget, CMD.BUILD)
	widgetHandler:RegisterUnitCommand(widget, CMD_STOP_PRODUCTION)''',
     '''function widget:Initialize()
	-- BAR Droid: the controller game keeps v0.8.5's build menu in BAR's place (WG.buildmenu: v0.8.5's gamepad drives
	-- it); this one runs beside it (WG.bardroidBuildmenu), shown only while the app's controls have the pad (a triple
	-- tap; bardroid_pad.lua sets WG.BarDroidOwnsBuildMenu and hides v0.8.5's panel then). Kailil, 2026-10-29: "What
	-- happened to my 3x3 build menu grid? its gone".
	if (Game.gameVersion or ""):find("$VERSION", 1, true) or (WG.buildmenu and WG.buildmenu.controllerApiVersion) then
		Spring.Echo("[bardroid-buildmenu] the controller game: beside its own build menu, shown with the app's controls")
		droid.ctl = true
	end
	widgetHandler:RegisterUnitCommand(CMD.BUILD) -- BAR Droid: the handler's stand-in for user widgets
	widgetHandler:RegisterUnitCommand(CMD_STOP_PRODUCTION)'''),
    ('''	if widgetHandler:IsWidgetKnown("Grid menu") then
		-- Grid menu needs to be disabled right now and before we recreate
		-- WG['buildmenu'] since its Shutdown will destroy it.
		widgetHandler:DisableWidgetRaw("Grid menu")
	end
''',
     '''	-- BAR Droid: BAR's Grid menu is off by launch-bar.sh (a user widget cannot switch widgets)
'''),
    ('''	widget:ViewResize()
	widget:SelectionChanged(spGetSelectedUnits())

	WG.buildmenu = {}''',
     '''	widget:ViewResize()
	widget:SelectionChanged(spGetSelectedUnits())

	droid.register() -- BAR Droid
	droid.shared = WG.buildmenu -- (the controller game: v0.8.5's, given back at the end of Initialize)
	WG.buildmenu = {}
	-- BAR Droid: the grid as laid out (tools/touch-widget-test.ps1)
	WG.buildmenu.droidGrid = function()
		return colls, rows, pages, cmdsCount
	end
	WG.buildmenu.droidPlace = function() -- (and the shape strip: a building picked, the shape, the buttons, a tap)
		return droid.armed, droid.shape, droid.shapeRects
	end
	WG.buildmenu.droidPress = droid.press
	WG.buildmenu.droidSetShape = function(shape) -- (the portrait dock's own shape buttons: one, line, grid, border)
		droid.shape = shape
		clear()
		droid.place()
	end
	WG.buildmenu.droidPanel = function() -- (the PLACE button's rects and the spot)
		return droid.panel, droid.spot
	end
	WG.buildmenu.droidPressPanel = droid.pressPanel
	WG.buildmenu.droidSpot = droid.setSpot -- (bardroid_touch.lua: the app's "spot" lines)
	WG.buildmenu.droidNudge = droid.nudge -- (the app's "nudge" lines)
	WG.buildmenu.droidSetGrid = droid.setGrid -- (the app's "grid" lines)
	WG.buildmenu.droidPad = droid.pad -- (bardroid_touch.lua: the gamepad's pad_* actions)
	WG.buildmenu.droidFocus = function() -- (the option the gamepad is on, and the page)
		return droid.focus, currentPage
	end
	WG.buildmenu.droidSetWarp = function(fn) -- (tools/touch-widget-test.ps1: no pointer moves without -Pointer; the
		droid.warp, droid.fakeWarp = fn or Spring.WarpMouse, fn ~= nil -- focus then does not follow the pointer)
	end
	WG.buildmenu.droidDrawHover = droid.drawHover -- (the same: drawn once without a pointer over the menu)'''),
    ('''		local paginatorFontSize = math_max(0.016 * vsy, paginatorCellHeight * 0.2)
''',
     '''		local paginatorFontSize = math_max(0.016 * vsy, paginatorCellHeight * 0.2)
			* (stickToBottom and 1 or droid.pageText) -- BAR Droid: the page strip's arrows and number bigger
'''),
    ('''				cellRects[cellRectID] = {
					activeArea[3] - ((colls - coll + 1) * cellSize),
					activeArea[4] - (row * cellSize),
					activeArea[3] - ((colls - coll) * cellSize),''',
     '''				cellRects[cellRectID] = { -- BAR Droid: droid.gap, the grid in the middle
					activeArea[3] - droid.gap - ((colls - coll + 1) * cellSize),
					activeArea[4] - (row * cellSize),
					activeArea[3] - droid.gap - ((colls - coll) * cellSize),'''),
    ('''	WG.buildmenu.hasHighlight = function(unitDefID)
		return unitDefID ~= nil and highlights[unitDefID] ~= nil
	end
end''',
     '''	WG.buildmenu.hasHighlight = function(unitDefID)
		return unitDefID ~= nil and highlights[unitDefID] ~= nil
	end
	-- BAR Droid: the app's widgets find this menu as WG.bardroidBuildmenu; in the controller game BAR's place
	-- (WG.buildmenu) goes back to v0.8.5's (nil if it has not started yet: it sets its own then)
	WG.bardroidBuildmenu = WG.buildmenu
	if droid.ctl then
		WG.buildmenu = droid.shared
	end
	droid.shared = nil
end'''),
    ('''	WG.buildmenu = nil
end

function widget:GetConfigData()''',
     '''	if WG.buildmenu and WG.buildmenu.getSize and not WG.buildmenu.controllerApiVersion then
		WG.buildmenu = nil
	end
	WG.bardroidBuildmenu = nil -- BAR Droid
	if WG.BarDroidLayout and WG.BarDroidLayout.unregister then -- BAR Droid
		WG.BarDroidLayout.unregister("buildmenu")
	end
end

function widget:GetConfigData()'''),
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
            sys.exit(f"BAR's build menu changed: a patch finds its place {n} times (not once):\n{find}")
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
