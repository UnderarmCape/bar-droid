"""The app's resizable build menu (app/src/main/assets/bardroid/bardroid_buildmenu.lua) from BAR's own Build menu.

Kailil, 2026-10-28: "the vaniallal build menu works fine for touch. just rebuild the exact same one with the ability for
us to resize it freely". BAR's widgets take no size from another widget and BAR's sandbox ignores patched copies of its
widgets under their own name, so the app runs a copy of BAR's Build menu under its own name: the same code, with its
place and size from the app's layout editor (bardroid_layout.lua) and the few widget-handler calls a user widget makes
through BAR's stand-in for the handler. Each change is marked "BAR Droid:" in the copy.

Takes BAR's luaui/Widgets/gui_buildmenu.lua from the byar:test release in a BAR data folder's rapid pool (BAR's Windows
install, as the laptop checks use it) and records its pool md5: launch-bar.sh runs the copy only while the phone's BAR
release has that same file (Installer writes its md5 to .bardroid-buildmenu), so a BAR update to its build menu brings
BAR's own back until this is run again. A patch that no longer finds its place stops the tool.
    python -I tools/make-buildmenu.py [--bar-data <BAR data folder>]
"""
import argparse
import gzip
import os
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, "app", "src", "main", "assets", "bardroid", "bardroid_buildmenu.lua")
FILE = "luaui/widgets/gui_buildmenu.lua"


def bar_file(bar):
    """(release name, pool md5, bytes) of FILE in the byar:test release of the BAR data folder bar."""
    tag = None
    for root, _, files in os.walk(os.path.join(bar, "rapid")):
        if "versions.gz" in files and root.replace("\\", "/").endswith("/byar"):
            for line in gzip.open(os.path.join(root, "versions.gz")).read().decode().splitlines():
                parts = line.split(",", 3)
                if parts[0] == "byar:test":
                    tag = parts
    if not tag:
        sys.exit("byar:test is not in " + bar)
    data = gzip.open(os.path.join(bar, "packages", tag[1] + ".sdp")).read()
    i = 0
    while i < len(data):
        n = data[i]
        name = data[i + 1:i + 1 + n].decode().lower()
        md5 = data[i + 1 + n:i + 17 + n].hex()
        i += 1 + n + 16 + 8
        if name == FILE:
            with gzip.open(os.path.join(bar, "pool", md5[:2], md5[2:] + ".gz")) as f:
                return tag[3], md5, f.read()
    sys.exit(FILE + " is not in " + tag[3])


HEADER = """\
-- BAR Droid build menu: BAR's own Build menu (luaui/Widgets/gui_buildmenu.lua, by Floris, GPL v2 or later), from
-- {release}, unchanged except where marked "BAR Droid:" (Kailil, 2026-10-28: "the vaniallal build menu works fine for
-- touch. just rebuild the exact same one with the ability for us to resize it freely"): its place and size come from
-- the app's layout editor (bardroid_layout.lua), and the widget-handler calls go through BAR's stand-in for the handler
-- that user widgets get. Made by tools/make-buildmenu.py; do not edit by hand, run it again.
-- launch-bar.sh runs it instead of BAR's Build menu only while the BAR release on the phone has the same file as the
-- line below (Installer writes the md5 of BAR's file to .bardroid-buildmenu); in the controller game, which keeps its
-- own ("Build menu (controller)", the gamepad drives it), this one stands down.
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
-- The app learns of the focus from LuaUI/Config/bardroid_pad.txt ("focus 1": the D-pad and B are the menu's).
local droid = { colls = 3, rows = 3, strip = 0.5, pageText = 2, gap = 0, registered = false,
	shape = "one", armed = false, defID = nil, spot = nil, panel = nil, written = nil, writtenAt = nil, shapeRects = {},
	file = "LuaUI/Config/bardroid_place.txt",
	focus = nil, focusFrom = nil, warpTo = nil, padFile = "LuaUI/Config/bardroid_pad.txt", padWritten = nil,
	padWrittenAt = nil, warp = Spring.WarpMouse,
	items = { { "one", "ONE" }, { "line", "LINE" }, { "grid", "GRID" }, { "border", "BORDER" } } }
'''),
    ('''	-- adjust grid size when pages are needed
''',
     '''	-- BAR Droid: the grid at the left, droid.colls x droid.rows, the page strip under it
	droid.gap = 0
	if not stickToBottom then
		colls = droid.colls
		cellSize = math_floor(math_min(contentWidth / colls, contentHeight / (droid.rows + droid.strip)))
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
		-- above the unit panel
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
		rect = function()
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
--   spot <x> <y>                (where the spot is on the screen now; only while it is)
-- The strip is drawn again when the building is picked or put away.
function droid.place()
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
			droid.shape = "one" -- (each building picked starts with ONE: a drag pans the map until a shape is chosen)
		elseif droid.focus then
			droid.endFocus(true) -- (picked with the gamepad: the pointer to the middle, ready to place it)
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
		text = text .. string.format("done %d %d %d %d\\n", p.place[1], vsy - p.place[4], p.place[3], vsy - p.place[2])
	end
	local sx, sy = droid.spotOnScreen()
	if sx then
		text = text .. string.format("spot %d %d\\n", sx, vsy - sy - 1)
	end
	-- (written again every second while a building is picked: the app takes an older file for none, so a file left by
	-- a game that ended with a building picked never turns taps into Shift clicks)
	local now = Spring.GetTimer()
	if text ~= droid.written or (armed and Spring.DiffTimers(now, droid.writtenAt) > 1) then
		local f = io.open(droid.file, "w")
		if f then
			f:write(text)
			f:close()
			droid.written, droid.writtenAt = text, now
		end
	end
end

-- BAR Droid: the spot a tap picked (X screen pixels; nil: none): the building goes there when PLACE is tapped
function droid.setSpot(x, y)
	droid.spot = nil
	if x and y and droid.armed then
		local _, pos = Spring.TraceScreenRay(x, vsy - y - 1, true)
		if pos then
			droid.spot = { pos[1], pos[2], pos[3] }
		end
	end
	droid.place()
end

-- (the building's place on the build grid at the spot, and where that is on the screen)
function droid.spotPos()
	local s = droid.spot
	if not (s and droid.defID) then
		return nil
	end
	return Spring.Pos2BuildPos(droid.defID, s[1], s[2], s[3], Spring.GetBuildFacing())
end
-- (none when it is off the screen or under this menu, PLACE or the minimap: a click there would hit them, not the map)
function droid.spotOnScreen()
	local bx, by, bz = droid.spotPos()
	if not bx then
		return nil
	end
	local sx, sy, sz = Spring.WorldToScreenCoords(bx, by, bz)
	if sz > 1 or sx < 0 or sy < 0 or sx >= vsx or sy >= vsy or widget:IsAbove(sx, sy) or Spring.IsAboveMiniMap(sx, sy) then
		return nil
	end
	return math_floor(sx), math_floor(sy)
end

-- BAR Droid: the building at the spot, as the engine draws a building being placed, and a ring around it
function droid.drawSpot()
	local bx, by, bz = droid.spotPos()
	if not bx then
		return
	end
	local def = UnitDefs[droid.defID]
	gl.DepthTest(true)
	gl.PushMatrix()
	gl.Translate(bx, by, bz)
	gl.Rotate(90 * Spring.GetBuildFacing(), 0, 1, 0)
	gl.UnitShape(droid.defID, Spring.GetMyTeamID(), false, false, false)
	gl.PopMatrix()
	gl.DepthTest(false)
	gl.Color(0.3, 1, 0.3, 0.8)
	gl.LineWidth(2)
	gl.DrawGroundCircle(bx, by, bz, def and def.radius or 32, 32)
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
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
	if o and o.getPosition and o.getIsShowing and o.getIsShowing() then
		local x, y, w, h = o.getPosition()
		if x and h then
			x0, y0, x1, y1 = x * vsx, (y - h) * vsy, (x + w) * vsx, y * vsy
		end
	end
	if not x0 then
		x0, y0, x1, y1 = vsx * 0.35, 0, vsx * 0.65, vsy * 0.14
	end
	x0, y0, x1, y1 = math_floor(x0), math_floor(y0), math_floor(x1), math_floor(y1)
	local pad = math_floor(math.max(2, (y1 - y0) * 0.08))
	local s = math_floor(math.min((y1 - y0) * 0.7, (x1 - x0) * 0.2))
	local my = math_floor((y0 + y1 - s) / 2)
	local cancel = { x1 - pad - s, my, x1 - pad, my + s }
	local rotate = { cancel[1] - pad - s, my, cancel[1] - pad, my + s }
	droid.panel = { all = { x0, y0, x1, y1 }, place = { x0, y0, rotate[1] - pad, y1 }, rotate = rotate, cancel = cancel }
end

function droid.drawPanel()
	local p = droid.panel
	if not p then
		return
	end
	local ready = droid.spotOnScreen() ~= nil -- (green once a tap has picked the spot, while it can be clicked)
	local a = p.all
	UiButton(a[1], a[2], a[3], a[4], 1, 1, 1, 1, 1, 1, 1, 1, nil,
		ready and { 0.1, 0.5, 0.1, 0.95 } or { 0.1, 0.25, 0.1, 0.9 }, ready and { 0.25, 0.8, 0.25, 0.95 } or { 0.2, 0.35, 0.2, 0.9 },
		bgpadding * 0.5)
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
	r = p.cancel
	font2:Print("\\255\\235\\235\\235\\226\\156\\149", (r[1] + r[3]) / 2, (r[2] + r[4]) / 2 - sym * 0.3, sym, "co")
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
		droid.spot = nil
		if spGetGameFrame() == 0 and WG["pregame-build"] and WG["pregame-build"].setPreGameDefID then
			WG["pregame-build"].setPreGameDefID(nil)
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
	local size = math.min((y1 - y0) * 0.5, w * 0.8 / math.max(0.01, font2:GetTextWidth("BORDER"))) -- (one size for all)
	for i, item in ipairs(droid.items) do
		local x0 = area[1] + (i - 1) * w
		local rect = { x0, y0, x0 + w, y1, item[1] }
		droid.shapeRects[#droid.shapeRects + 1] = rect
		local lit = item[1] == droid.shape
		UiButton(rect[1] + cellPadding, rect[2] + cellPadding, rect[3] - cellPadding, rect[4] - cellPadding,
			1, 1, 1, 1, 1, 1, 1, 1, nil,
			lit and { 0.45, 0.36, 0.05, 0.9 } or { 0, 0, 0, 0.8 }, lit and { 0.75, 0.62, 0.15, 0.9 } or { 0.2, 0.2, 0.2, 0.8 },
			bgpadding * 0.5)
		font2:Print((lit and "\\255\\255\\235\\150" or "\\255\\235\\235\\235") .. item[2], x0 + w * 0.5,
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

function droid.endFocus(center)
	droid.focus, droid.warpTo, droid.focusFrom = nil, nil, nil
	if center then
		droid.warp(math_floor(vsx / 2), math_floor(vsy / 2))
	end
end

function droid.pad(name)
	if name == "build" then
		if droid.focus then
			droid.endFocus(false)
		elseif buildmenuShows and cmdsCount > 0 then
			droid.focus = math.min(cmdsCount, (currentPage - 1) * colls * rows + 1)
			droid.warpTo = droid.focus
		end
	elseif not droid.focus then
		return
	elseif name == "back" then
		droid.endFocus(true)
	else
		local per = colls * rows
		local id = droid.cellAt(spGetMouseState()) or droid.focus
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
		elseif col >= colls then
			page, col = page + 1, 0
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

-- (each Update: the pointer onto the focused option once the menu has laid it out; the focus ends when the menu goes
-- or the pointer is moved off it; the app told)
function droid.padFocus()
	if droid.focus then
		if not buildmenuShows then
			droid.endFocus(false)
		elseif droid.warpTo then
			local r = cellRects[droid.warpTo]
			if r then
				droid.warp(math_floor((r[1] + r[3]) / 2), math_floor((r[2] + r[4]) / 2))
				droid.warpTo, droid.focusFrom = nil, nil
			end
		else
			local mx, my = spGetMouseState()
			local r = backgroundRect
			if not droid.focusFrom then
				droid.focusFrom = { mx, my }
			elseif (mx ~= droid.focusFrom[1] or my ~= droid.focusFrom[2])
				and not (r and mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4]) then
				droid.endFocus(false)
			end
		end
	end
	local text = droid.focus and "focus 1\\n" or "focus 0\\n"
	local now = Spring.GetTimer()
	if text ~= droid.padWritten or (droid.focus and Spring.DiffTimers(now, droid.padWrittenAt) > 1) then
		local f = io.open(droid.padFile, "w")
		if f then
			f:write(text)
			f:close()
			droid.padWritten, droid.padWrittenAt = text, now
		end
	end
end

-- BAR Droid: the option under the pointer, with the gamepad: 10% bigger, a gold outline around it
function droid.drawHover(cellID, list)
	local r = cellRects[cellID]
	if not (r and (droid.focus or WG.BarDroidInput == "pad")) then
		gl.CallList(list)
		return
	end
	local cx, cy = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
	local t = math.max(2, math_floor((r[3] - r[1]) * 0.035))
	gl.PushMatrix()
	gl.Translate(cx, cy, 0)
	gl.Scale(1.1, 1.1, 1)
	gl.Translate(-cx, -cy, 0)
	RectRound(r[1] + cellPadding - t, r[2] + cellPadding - t, r[3] - cellPadding + t, r[4] - cellPadding + t,
		cornerSize * 1.5, 1, 1, 1, 1, { 1, 0.78, 0.2, 1 }, { 1, 0.92, 0.45, 1 })
	gl.CallList(list)
	gl.PopMatrix()
end

function widget:ViewResize()
	tracy.ZoneBeginN("W:BuildMenu:ViewResize")'''),
    ('''function widget:Update(dt)
''',
     '''function widget:Update(dt)
	droid.register() -- BAR Droid
	droid.place()
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
    ('''					if hoverDlist then
						gl.CallList(hoverDlist)
					end''',
     '''					if hoverDlist then
						droid.drawHover(hoveredCellID, hoverDlist) -- BAR Droid: with the gamepad bigger, outlined
					end'''),
    ('''function widget:DrawScreen()
	tracy.ZoneBeginN("W:BuildMenu:DrawScreen")
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
''',
     '''function widget:DrawScreen()
	tracy.ZoneBeginN("W:BuildMenu:DrawScreen")
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	droid.drawPanel() -- BAR Droid: the PLACE button (over the order menu)
'''),
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
'''),
    ('''function widget:Initialize()
	widgetHandler:RegisterUnitCommand(widget, CMD.BUILD)
	widgetHandler:RegisterUnitCommand(widget, CMD_STOP_PRODUCTION)''',
     '''function widget:Initialize()
	-- BAR Droid: the controller game keeps its own build menu (the gamepad drives it)
	if (Game.gameVersion or ""):find("$VERSION", 1, true) or (WG.buildmenu and WG.buildmenu.controllerApiVersion) then
		Spring.Echo("[bardroid-buildmenu] the controller game: its own build menu")
		widgetHandler:RemoveWidget()
		return
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
	WG.buildmenu = {}
	-- BAR Droid: the grid as laid out (tools/touch-widget-test.ps1)
	WG.buildmenu.droidGrid = function()
		return colls, rows, pages, cmdsCount
	end
	WG.buildmenu.droidPlace = function() -- (and the shape strip: a building picked, the shape, the buttons, a tap)
		return droid.armed, droid.shape, droid.shapeRects
	end
	WG.buildmenu.droidPress = droid.press
	WG.buildmenu.droidPanel = function() -- (the PLACE button's rects and the spot)
		return droid.panel, droid.spot
	end
	WG.buildmenu.droidPressPanel = droid.pressPanel
	WG.buildmenu.droidSpot = droid.setSpot -- (bardroid_touch.lua: the app's "spot" lines)
	WG.buildmenu.droidPad = droid.pad -- (bardroid_touch.lua: the gamepad's pad_* actions)
	WG.buildmenu.droidFocus = function() -- (the option the gamepad is on, and the page)
		return droid.focus, currentPage
	end
	WG.buildmenu.droidSetWarp = function(fn) -- (tools/touch-widget-test.ps1: no pointer moves without -Pointer)
		droid.warp = fn or Spring.WarpMouse
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
    ('''	WG.buildmenu = nil
end

function widget:GetConfigData()''',
     '''	if WG.buildmenu and WG.buildmenu.getSize and not WG.buildmenu.controllerApiVersion then
		WG.buildmenu = nil
	end
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
    args = ap.parse_args()
    release, md5, raw = bar_file(args.bar_data)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for find, repl in PATCHES:
        n = text.count(find)
        if n != 1:
            sys.exit(f"BAR's build menu changed: a patch finds its place {n} times (not once):\n{find}")
        text = text.replace(find, repl)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER.format(release=release, md5=md5) + text)
    print(f"{OUT}: {release}, {FILE} {md5}, {len(PATCHES)} patches")


if __name__ == "__main__":
    main()
