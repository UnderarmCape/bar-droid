-- BAR Droid gamepad: the game side of the app's gamepad in BAR's own game (online, spectating). The app makes the pad a
-- mouse and keyboard rebuilt on Kailil's BAR Controller Support v0.8.5 ("Build-First Commander"; PadGame.java has the
-- whole layout) and sends what a mouse and keys cannot do as actions through bardroid_touch.lua ("act <name>"); this
-- widget does them, with what BAR lets a user widget do (Kailil, 2026-10-29: "match 1to1 using any means necessary ...
-- RB and Back + RB to teleport mouse to build menu and orders menu to replace the tactical menu radial"):
--   the order menu on the pad (Back + RB): the pointer onto its first order, the D-pad steps, the order under it lit
--     with BAR's own highlight, A gives it (an order that needs a target sends the pointer back to the middle to aim),
--     B leaves; the build menu's own (RB) is bardroid_buildmenu.lua's
--   control groups (Start + D-pad): recall, assign, BAR's autogroup (the app presses Alt+N), clear; BAR's group
--     actions, the group's number shown
--   idle units (D-pad; LB + D-pad), the commander (D-pad down), a camera bookmark (D-pad up; LT + up stores it)
--   cancel (B), LB + A/X/Y/B orders at the middle of the screen, removing queued orders (L3/R3), the D-gun (Back + R3)
--   a reticle in the middle while the pad is the input, and short notes (v0.8.5's hotkey feedback)
-- Orders at a point go to the units at once where the game allows unit-control widgets (BAR's default), else the order
-- is picked and A gives it. The app learns which menu has the pad, whether the game has started and what kind of order
-- is picked from LuaUI/Config/bardroid_pad.txt ("focus build|orders|none", "pregame 0|1",
-- "armed build|area|unitarea|other|none": a tap of A starts an area order's circle, PadGame).
-- A menu on the pad keeps the pointer on it (Kailil: "constrain the mouse within the menu bounds ... let the mouse leave
-- it if i press B only or i constantly move the left stick out of the box for ... 1 second"); the app brings the
-- pointer back to the middle afterwards, gliding.

function widget:GetInfo()
	return {
		name = "BAR Droid gamepad",
		desc = "The BAR Droid app's gamepad in BAR's game: menus, groups, idle units, orders",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -95000,
		enabled = true,
	}
end

local PAD_FILE = "LuaUI/Config/bardroid_pad.txt"

-- written whole, then renamed: the app reads it every 100 ms and must never find it empty (io.open "w" empties it
-- first: "no menu" pulled the pointer out of the menu, "not pregame" to the middle)
local function writeWhole(path, text)
	local f = io.open(path .. ".tmp", "w")
	if not f then
		return false
	end
	f:write(text)
	f:close()
	local ok, renamed = pcall(os.rename, path .. ".tmp", path)
	if not (ok and renamed) then -- (Windows, for the laptop tests: rename does not replace a file)
		pcall(os.remove, path)
		pcall(os.rename, path .. ".tmp", path)
	end
	return true
end

local TOAST_SECONDS = 1.3
local LEAVE_SECONDS = 0.25 -- the pointer pushed off a menu this long lets go of it (Kailil: "make it a quarter long")
local HIGHLIGHT = { 1, 0.8, 0.25 }

-- BAR's order menu (luaui/Widgets/gui_ordermenu.lua): the orders it hides, and how it lays out its grid
local HIDDEN = {
	[CMD.LOAD_ONTO] = true, [CMD.SELFD] = true, [CMD.GATHERWAIT] = true, [CMD.SQUADWAIT] = true,
	[CMD.DEATHWAIT] = true, [CMD.TIMEWAIT] = true, [CMD.AUTOREPAIRLEVEL] = true, [39812] = true, [34922] = true,
}
local HIDDEN_TYPE = { [CMDTYPE.CUSTOM] = true, [CMDTYPE.PREV] = true, [CMDTYPE.NEXT] = true }
local CANCEL_TARGET = 34924

local orders = nil -- the order menu on the pad: { index, cmdID, warped = {x, y, timer}, layout }
local toast, toastAt = nil, nil
local written, writtenAt = nil, nil
local bookmark = nil
local idleType = nil -- the type of the last idle unit picked (LB + D-pad down)
local lastIdleMobile = 0
local mouseMode = false -- Back + Start, as the app's switch (PadGame)
local controllerGame = false -- v0.8.5's game: the pad is v0.8.5's until a triple tap switches it (modV085)
local modV085 = false
-- v0.8.5's area select (A held with nothing picked: PadGame): a circle in the middle of the screen selects the player's
-- units it passes over while the camera pans; units first (buildings only when there are no units in it, or with RT:
-- added to the selection, buildings too); the D-pad sizes it, held quickly, the circle easing to its new size in about
-- 0.1 s (Kailil, 2026-10-30); B undoes it. v0.8.5's radius: 320 in 80s up to 1200; down to 20, in 20s under 160.
-- X held as well: v0.8.5's filter radial (Kailil, 2026-10-29), the left stick picks All Mobile (up), Combat (down),
-- Builders (left) or Air (right), kept for the next area select. Builders and combat units are never selected together
-- (Kailil: "prefer combat units (BAR's vanilla behavior), so con bots are not sent into battle").
local FILTER_SIDES = { up = "All Mobile", down = "Combat", left = "Builders", right = "Air" }
local area = { on = false, radius = 320, target = 320, units = {}, count = 0, keep = {}, shift = false, x = nil, y = nil,
	z = nil, filter = "All Mobile", radial = false, highlight = nil }
local AREA_MIN, AREA_MAX, AREA_EASE = 20, 1200, 0.035 -- (the ease: 95% of the way in 0.1 s)
-- the group list (control groups, below): the slot in use, Start held, shown until
local GROUP_LIST_SECONDS = 1.5
local groupList = { slot = 1, held = false, untilAt = nil }
local warp, fakeWarp = Spring.WarpMouse, false -- (tools/touch-widget-test.ps1 records the moves instead)
-- (tools/touch-widget-test.ps1: a made-up pointer, {x, y}, which the recorded moves land on, so the order menu's
-- following, holding and letting go run without moving the real one)
local fakePointer = nil
local function pointerAt()
	if fakePointer then
		return fakePointer[1], fakePointer[2]
	end
	return Spring.GetMouseState()
end
local function warpTo(x, y)
	if fakePointer then
		fakePointer = { x, y }
	end
	warp(x, y)
end

local function now()
	return Spring.GetTimer()
end

-- The pad's pointer is free (the left stick moves it) before the start, or after Back + Start; else in the middle
local function freePointer()
	return mouseMode ~= (Spring.GetGameFrame() == 0 and not Spring.GetSpectatingState())
end

-- The app's controller interface, one look (Kailil, 2026-10-30: "make them look more polished. not extravagant"): BAR's
-- own panels (WG.FlowUI's Element: its dark glass, corners and padding) and font, sizes from BAR's interface scale (the
-- phone sets it per Fold screen, so a note is about as big on the cover screen as on the inner one), and two accents:
-- gold where the pad is (the focus on a menu, a lit choice), v0.8.5's blue for placing and filters. The app's build
-- menu draws with it too (WG.BarDroidStyle).
local style = {
	GOLD = { 1, 0.78, 0.25 },
	BLUE = { 0.2, 0.8, 1 },
	TEXT = { 0.96, 0.92, 0.8 },
	-- the pad's face buttons in their Xbox colours (a note naming one at its end, "REPAIR: A", shows it as a key)
	KEYS = { A = { 0.33, 0.66, 0.24 }, B = { 0.82, 0.24, 0.2 }, X = { 0.2, 0.44, 0.88 }, Y = { 0.9, 0.7, 0.1 } },
}

-- a size from BAR's interface scale: this fraction of the screen's height at scale 1; least: the smallest (10: text)
function style.size(fraction, least)
	local _, vsy = Spring.GetViewGeometry()
	local scale = (WG.FlowUI and WG.FlowUI.scale) or Spring.GetConfigFloat("ui_scale", 1) or 1
	return math.max(least or 10, math.floor(vsy * fraction * scale + 0.5))
end

-- BAR's panel, its alpha times alpha
function style.panel(x0, y0, x1, y1, alpha)
	local f = WG.FlowUI
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	if f and f.Draw and f.Draw.Element then
		local o = math.min(1, (f.opacity or 0.7) + 0.1) * (alpha or 1)
		f.Draw.Element(x0, y0, x1, y1, 1, 1, 1, 1, 1, 1, 1, 1, o, { 0.03, 0.03, 0.03, o }, { 1, 1, 1, o * 0.07 },
			math.max(1, math.floor((f.elementPadding or 2) * 0.8)))
	else
		gl.Color(0.03, 0.03, 0.03, 0.8 * (alpha or 1))
		gl.Rect(x0, y0, x1, y1)
	end
end

-- (a rounded rect, filled; BAR's own when it is there)
function style.fill(x0, y0, x1, y1, color, alpha, corner)
	local f = WG.FlowUI
	local c = { color[1], color[2], color[3], (color[4] or 1) * (alpha or 1) }
	local cs = corner or math.max(2, math.floor(math.min(x1 - x0, y1 - y0) * 0.14))
	if f and f.Draw and f.Draw.RectRound then
		f.Draw.RectRound(x0, y0, x1, y1, cs, 1, 1, 1, 1, c, c)
	else
		gl.Color(c[1], c[2], c[3], c[4])
		gl.Rect(x0, y0, x1, y1)
	end
end

-- an accent line round a rect (the pad's focus, a lit choice), its corners cut as BAR's panels' are; width: about BAR's
-- element padding
local function ring(x0, y0, x1, y1, cs, w)
	local ics = math.max(0, cs - w * 0.586) -- (the cut as thick as the sides)
	local points = {
		x1, y1 - cs, x1 - w, y1 - w - ics, x1 - cs, y1, x1 - w - ics, y1 - w,
		x0 + cs, y1, x0 + w + ics, y1 - w, x0, y1 - cs, x0 + w, y1 - w - ics,
		x0, y0 + cs, x0 + w, y0 + w + ics, x0 + cs, y0, x0 + w + ics, y0 + w,
		x1 - cs, y0, x1 - w - ics, y0 + w, x1, y0 + cs, x1 - w, y0 + w + ics,
		x1, y1 - cs, x1 - w, y1 - w - ics,
	}
	gl.BeginEnd(GL.TRIANGLE_STRIP, function()
		for i = 1, #points, 2 do
			gl.Vertex(points[i], points[i + 1])
		end
	end)
end
function style.outline(x0, y0, x1, y1, color, alpha, width)
	local w = width or style.size(0.0026, 2)
	local cs = math.max(w + 1, math.floor(math.min(x1 - x0, y1 - y0) * 0.1))
	gl.Color(color[1], color[2], color[3], alpha or 1)
	ring(math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1), cs, w)
	gl.Color(1, 1, 1, 1)
end

-- (a filled circle)
function style.disc(x, y, r, color, alpha)
	gl.Color(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
	gl.BeginEnd(GL.TRIANGLE_FAN, function()
		gl.Vertex(x, y)
		for i = 0, 24 do
			local a = i / 24 * 2 * math.pi
			gl.Vertex(x + math.cos(a) * r, y + math.sin(a) * r)
		end
	end)
	gl.Color(1, 1, 1, 1)
end

-- a pad button as a small round key in its colour, its letter on it; size: its side
function style.key(x0, y0, size, letter, alpha)
	local c = style.KEYS[letter] or { 0.4, 0.4, 0.4 }
	local r = size / 2
	style.disc(x0 + r, y0 + r, r, { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5 }, alpha)
	style.disc(x0 + r, y0 + r, r - math.max(1, size * 0.08), c, alpha)
	local font = WG.fonts and WG.fonts.getFont()
	if font then
		font:Begin()
		font:SetTextColor(1, 1, 1, alpha or 1)
		font:SetOutlineColor(0, 0, 0, 0.5 * (alpha or 1))
		font:Print(letter, x0 + size / 2, y0 + size * 0.5 - size * 0.62 * 0.36, size * 0.62, "co")
		font:End()
	end
end

-- a short message in a panel, its middle at x and its bottom at y; key: a pad button shown after the words
function style.toast(text, x, y, color, alpha, key)
	local font = WG.fonts and WG.fonts.getFont()
	if not font then
		return
	end
	local size = style.size(0.02)
	local pad = math.floor(size * 0.75)
	local chip = key and math.floor(size * 1.3) or 0
	local gap = key and math.floor(size * 0.5) or 0
	local tw = math.ceil(font:GetTextWidth(text) * size)
	local w, h = tw + gap + chip + pad * 2, math.floor(size * 2)
	local _, vsy = Spring.GetViewGeometry()
	local x0 = math.floor(x - w / 2)
	y = math.min(math.floor(y), vsy - h - 2)
	style.panel(x0, y, x0 + w, y + h, alpha)
	font:Begin()
	font:SetTextColor(color[1], color[2], color[3], alpha)
	font:SetOutlineColor(0, 0, 0, 0.55 * alpha)
	font:Print(text, x0 + pad, y + h / 2 - size * 0.36, size, "o")
	font:End()
	if key then
		style.key(x0 + pad + tw + gap, math.floor(y + (h - chip) / 2), chip, key, alpha)
	end
end

local lastNote, notes = nil, 0 -- (tools/touch-widget-test.ps1: the last note, also once it has faded, and how many)
local GOLD, BLUE = style.TEXT, style.BLUE -- (notes warm white; blue: v0.8.5's placement notes, "SLOW PAN", "GRID")
local toastColor = GOLD
local function note(text, color)
	toast, toastAt, toastColor = text, now(), color or GOLD
	lastNote, notes = text, notes + 1
end

-- Orders at a point straight to the units only where the game allows it (BAR's sandbox; the modoption is on by default)
local function unitControl()
	local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
	local v = mo.allowunitcontrolwidgets
	return v == nil or v == true or v == 1 or v == "1" or v == "true"
end

local function shiftHeld()
	local _, _, _, shift = Spring.GetModKeyState()
	return shift
end

local function selectAndLook(units)
	if #units == 0 then
		return false
	end
	Spring.SelectUnitArray(units)
	local x, y, z = Spring.GetUnitPosition(units[1])
	if x then
		Spring.SetCameraTarget(x, y, z, 0.3)
	end
	return true
end

local function myUnits()
	if Spring.GetSpectatingState() then
		return {}
	end
	return Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}
end

-- The order menu's commands in its own order (order states first, then Wait, then the rest)
local function orderCommands()
	local states, others, wait = {}, {}, nil
	local o = WG.ordermenu
	local hasTarget = false
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		if Spring.GetUnitRulesParam(unitID, "hasPriorityTarget") then
			hasTarget = true
			break
		end
	end
	for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do
		if type(cmd) == "table" and not (o.getDisabledCmd and o.getDisabledCmd(cmd.name))
			and not HIDDEN[cmd.id] and not HIDDEN_TYPE[cmd.type] and cmd.action ~= nil and not cmd.disabled
			and not (cmd.id == CANCEL_TARGET and not hasTarget) then
			if cmd.type == CMDTYPE.ICON_BUILDING or cmd.action:find("buildunit_", 1, true) == 1 then -- luacheck: ignore 542
			elseif cmd.type == CMDTYPE.ICON_MODE then
				states[#states + 1] = cmd
			elseif cmd.id == CMD.WAIT then
				wait = cmd
			else
				others[#others + 1] = cmd
			end
		end
	end
	if wait then
		states[#states + 1] = wait
	end
	for _, cmd in ipairs(others) do
		states[#states + 1] = cmd
	end
	return states
end

-- The order menu's cells as BAR lays them out (setupCellGrid in gui_ordermenu.lua), bottom left origin; nil: not shown
local function ordersLayout()
	local o = WG.ordermenu
	if not (o and o.getPosition and o.getIsShowing and o.getIsShowing()) then
		return nil
	end
	if o.droidCells then -- (the controller game's order menu tells its own cells: its even layout with the pad)
		local rects, list = o.droidCells()
		local cells, cmds = {}, {}
		for i, cmd in ipairs(list or {}) do
			local r = rects and rects[i]
			if r and type(cmd) == "table" then
				cells[#cells + 1] = { r[1], r[2], r[3], r[4] }
				cmds[#cmds + 1] = cmd
			end
		end
		return #cmds > 0 and { cmds = cmds, cells = cells } or nil
	end
	local cmds = orderCommands()
	if #cmds == 0 then
		return nil
	end
	local posX, posY, width, height = o.getPosition()
	local vsx, vsy = Spring.GetViewGeometry()
	local bp = WG.FlowUI and WG.FlowUI.elementPadding or 0
	local abp = math.floor(bp * 1.4 + 0.5)
	local ar = {
		posX * vsx + (posX > 0 and abp or math.ceil(bp * 0.6)),
		(posY - height) * vsy + (posY - height > 0 and math.floor(abp) or math.floor(abp / 3)),
		(posX + width) * vsx - abp,
		posY * vsy - abp,
	}
	local add = Spring.GetConfigFloat("ui_scale", 1) < 0.85 and -1 or 0
	local n, cols, rows = #cmds, 7 + add, 7
	for _, s in ipairs({ { 4, 4 }, { 5, 4 }, { 5, 5 }, { 5, 6 }, { 6, 6 }, { 6, 7 } }) do
		if n <= (s[1] + add) * s[2] then
			cols, rows = s[1] + add, s[2]
			break
		end
	end
	local cw, ch = math.floor((ar[3] - ar[1]) / cols), math.floor((ar[4] - ar[2]) / rows)
	local leftW = ((ar[3] - ar[1]) - cw * cols) - 1
	local leftH = ((ar[4] - ar[2]) - ch * rows) - (posY - height <= 0 and 1 or 0)
	local cells, addedH, addedHf = {}, 0, 0
	for row = 1, rows do
		local prevH = addedH
		addedHf = addedHf + leftH / rows
		addedH = math.floor(addedHf)
		local prevW, addedWf = 0, 0
		for col = 1, cols do
			addedWf = addedWf + leftW / cols
			local addedW = math.floor(addedWf)
			cells[#cells + 1] = {
				math.floor(ar[1] + prevW + cw * (col - 1) + 0.5),
				math.floor(ar[4] - addedH - ch * row + 0.5),
				math.ceil(ar[1] + addedW + cw * col + 0.5),
				math.ceil(ar[4] - prevH - ch * (row - 1) + 0.5),
			}
			prevW = addedW
		end
	end
	return { cmds = cmds, cells = cells, cols = cols, rows = rows }
end

local function ordersLight(cmdID)
	local o = WG.ordermenu
	if o and o.clearHighlights then
		o.clearHighlights()
	end
	if cmdID and o and o.setHighlight then
		o.setHighlight(cmdID, HIGHLIGHT)
	end
end

-- (the app glides the pointer back to the middle once no menu has the pad)
local function ordersEnd()
	if orders then
		ordersLight(nil)
	end
	orders = nil
end

local function ordersGo(index)
	local layout = ordersLayout()
	if not layout then
		ordersEnd()
		return
	end
	index = math.max(1, math.min(#layout.cmds, index))
	local r = layout.cells[index]
	orders = { index = index, cmdID = layout.cmds[index].id, layout = layout }
	local x, y = math.floor((r[1] + r[3]) / 2), math.floor((r[2] + r[4]) / 2)
	warpTo(x, y)
	orders.warped = { x, y, now() }
	ordersLight(orders.cmdID)
end

-- The D-pad on the order menu, by where the buttons are (rows may hold different numbers of them: the controller game's
-- even layout): left / right the next button in the row, wrapping round it; up / down the nearest in the row above or
-- below, staying put at the top or bottom
local function ordersStep(dx, dy)
	local layout = orders.layout
	local n = #layout.cmds
	local cur = layout.cells[orders.index]
	if not cur then
		ordersGo(1)
		return
	end
	local cx, cy = (cur[1] + cur[3]) / 2, (cur[2] + cur[4]) / 2
	local best, bestScore
	for i = 1, n do
		local r = layout.cells[i]
		local x, y = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
		local sameRow = y > cur[2] and y < cur[4]
		local score
		if dx ~= 0 and sameRow and i ~= orders.index then
			local ahead = (x - cx) * dx
			score = ahead > 0 and ahead or ahead + 1e6 -- (none ahead: the farthest the other way)
		elseif dy ~= 0 and not sameRow and (cy - y) * dy > 0 then -- (dy > 0: down the screen, y smaller)
			score = math.abs(cy - y) * 1e4 + math.abs(x - cx)
		end
		if score and (not bestScore or score < bestScore) then
			best, bestScore = i, score
		end
	end
	ordersGo(best or orders.index)
end

-- A on the order menu: the order as BAR's button gives it (a state changes, an order without a target is given, one
-- with a target is picked: the pointer back to the middle to aim it, A gives it there)
local function ordersSelect()
	local index = Spring.GetCmdDescIndex(orders.cmdID)
	if not index then
		return
	end
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	Spring.SetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
	local _, active = Spring.GetActiveCommand()
	if active == orders.cmdID then
		ordersEnd()
	else
		ordersGo(orders.index) -- (the menu may have changed: a state's label, Wait)
	end
end

-- The idle units: the builders' cycle is bardroid_touch.lua's; this is the rest (mobile units with nothing to do)
local function idleMobile(step)
	local idle = {}
	for _, unitID in ipairs(myUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and not def.isBuilder and (def.speed or 0) > 0 and Spring.GetUnitCommandCount(unitID) == 0
			and not Spring.GetUnitIsBeingBuilt(unitID) then
			idle[#idle + 1] = unitID
		end
	end
	if #idle == 0 then
		note("NO IDLE UNITS")
		return
	end
	table.sort(idle)
	local pick = step > 0 and idle[1] or idle[#idle]
	for i = 1, #idle do
		local id = step > 0 and idle[i] or idle[#idle + 1 - i]
		if (step > 0 and id > lastIdleMobile) or (step < 0 and id < lastIdleMobile) then
			pick = id
			break
		end
	end
	lastIdleMobile = pick
	idleType = Spring.GetUnitDefID(pick)
	selectAndLook({ pick })
end

local function idleOfType()
	local selected = Spring.GetSelectedUnits()
	local defID = idleType or (selected[1] and Spring.GetUnitDefID(selected[1]))
	if not defID then
		return
	end
	local units = {}
	for _, unitID in ipairs(myUnits()) do
		if Spring.GetUnitDefID(unitID) == defID and Spring.GetUnitCommandCount(unitID) == 0
			and not Spring.GetUnitIsBeingBuilt(unitID) then
			units[#units + 1] = unitID
		end
	end
	if #units > 0 then
		Spring.SelectUnitArray(units)
		note("IDLE " .. string.upper(UnitDefs[defID].translatedHumanName or UnitDefs[defID].humanName or "") .. " x" .. #units)
	end
end

local function commander()
	local units = {}
	for _, unitID in ipairs(myUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.customParams and def.customParams.iscommander then
			units[#units + 1] = unitID
		end
	end
	if selectAndLook(units) then
		note("COMMANDER")
	end
end

-- Where the pad points: the reticle in the middle of the screen (the pointer only while it is free: it is still gliding
-- back to the middle for 160 ms after a drag or a menu); the unit there, and the ground (under a unit too: patrol or
-- fight on a unit goes to its place)
local function aim()
	local x, y
	if freePointer() then
		x, y = Spring.GetMouseState()
	else
		local vsx, vsy = Spring.GetViewGeometry()
		x, y = math.floor(vsx / 2), math.floor(vsy / 2)
	end
	local kind, target = Spring.TraceScreenRay(x, y)
	local _, pos = Spring.TraceScreenRay(x, y, true)
	return kind == "unit" and target or nil, pos
end

-- An order at the middle of the screen: given at once where allowed, else picked (A gives it)
local function orderAt(cmdID, name, unitOK)
	local selected = Spring.GetSelectedUnits()
	if #selected == 0 then
		return
	end
	local unitID, pos = aim()
	local opts = shiftHeld() and { "shift" } or {}
	if unitControl() and ((unitID and unitOK) or pos) then
		local params = (unitID and unitOK) and { unitID } or { pos[1], pos[2], pos[3] }
		if pcall(Spring.GiveOrderToUnitArray, selected, cmdID, params, opts) then
			note(string.upper(name))
			return
		end
	end
	Spring.SetActiveCommand(name)
	note(string.upper(name) .. ": A")
end

local function hasBuilder()
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.isBuilder then
			return true
		end
	end
	return false
end

local function enemyAt(unitID)
	return unitID and not Spring.IsUnitAllied(unitID)
end

-- L3 / R3: the next or the last queued order of the selected units removed
local function queueRemove(last)
	if not unitControl() then
		note("NOT IN THIS GAME")
		return
	end
	local removed = 0
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local queue = Spring.GetUnitCommands(unitID, -1) or {}
		local cmd = last and queue[#queue] or queue[1]
		if cmd and cmd.tag and pcall(Spring.GiveOrderToUnit, unitID, CMD.REMOVE, { cmd.tag }, 0) then
			removed = removed + 1
		end
	end
	if removed > 0 then
		note(last and "REMOVED LAST ORDER" or "REMOVED NEXT ORDER")
	end
end

local function pregameBuild()
	local pb = WG["pregame-build"]
	return Spring.GetGameFrame() == 0 and pb and pb.getPreGameDefID and pb.getPreGameDefID() ~= nil
end

-- LB + B with factories selected: each stopped with its whole queue gone. BAR's own Stop Production (it keeps the unit
-- being built), then that one taken off too (a right click on its build option); true when there were factories
local CMD_STOP_PRODUCTION = (GameCMD and GameCMD.STOP_PRODUCTION) or 13923 -- luacheck: ignore 113 (BAR's global)
local function clearFactories()
	local factories = {}
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
		if def and def.isFactory then
			factories[#factories + 1] = unitID
		end
	end
	if #factories == 0 then
		return false
	end
	if not unitControl() then
		note("NOT IN THIS GAME")
		return true
	end
	local cleared = 0
	for _, unitID in ipairs(factories) do
		local first = (Spring.GetFactoryCommands(unitID, 1) or {})[1]
		if pcall(Spring.GiveOrderToUnit, unitID, CMD_STOP_PRODUCTION, {}, 0) then
			cleared = cleared + 1
		end
		if first and first.id < 0 then
			pcall(Spring.GiveOrderToUnit, unitID, first.id, {}, { "right", "ctrl", "shift" })
		end
	end
	note(cleared > 1 and "FACTORIES STOPPED, QUEUES CLEARED" or "FACTORY STOPPED, QUEUE CLEARED")
	return true
end

-- What kind of order is picked, for the app: a building, an area only (area mex: A starts its circle, the next A ends
-- it), a unit or an area (repair, reclaim: hold A and draw for the area), another order, or none. Asked every frame:
-- a command's kind is looked up once (GetActiveCmdDesc makes a table each call)
local kindOf = {}
local function armedKind()
	if pregameBuild() then
		return "build"
	end
	local _, id = Spring.GetActiveCommand()
	if not id then
		return "none"
	elseif id < 0 then
		return "build"
	end
	local kind = kindOf[id]
	if not kind then
		local index = Spring.GetCmdDescIndex(id)
		local desc = index and Spring.GetActiveCmdDesc(index)
		local t = desc and desc.type
		if t == CMDTYPE.ICON_AREA then
			kind = "area"
		elseif t == CMDTYPE.ICON_UNIT_OR_AREA or t == CMDTYPE.ICON_UNIT_FEATURE_OR_AREA or t == CMDTYPE.ICON_UNIT_OR_RECTANGLE then
			kind = "unitarea"
		else
			kind = "other"
		end
		if desc then
			kindOf[id] = kind
		end
	end
	return kind
end

-- The units the area select has passed over that its filter takes: mobile units first (buildings only when there are
-- none, or with RT); of those, builders only when no combat unit is among them (Builders: builders only)
local function chooseUnits(units, defOf, filter, shift)
	local builders, others, buildings = {}, {}, {}
	for _, unitID in ipairs(units) do
		local def = defOf(unitID)
		if def and (def.speed or 0) > 0 and not def.isFactory then
			local builder = def.isBuilder
			local fits = filter == "All Mobile" or (filter == "Air" and def.canFly) or (filter == "Builders" and builder)
				or (filter == "Combat" and not builder and (def.canAttack or #(def.weapons or {}) > 0))
			if fits then
				local list = builder and builders or others
				list[#list + 1] = unitID
			end
		elseif def then
			buildings[#buildings + 1] = unitID
		end
	end
	local pick = #others > 0 and others or builders
	if shift or (#pick == 0 and filter == "All Mobile") then
		for _, unitID in ipairs(buildings) do
			pick[#pick + 1] = unitID
		end
	end
	return pick
end

local function unitDefOf(unitID)
	return UnitDefs[Spring.GetUnitDefID(unitID) or -1]
end

local function areaPick()
	local units = {}
	for unitID in pairs(area.units) do
		units[#units + 1] = unitID
	end
	local pick = chooseUnits(units, unitDefOf, area.filter, area.shift)
	for _, unitID in ipairs(area.keep) do
		pick[#pick + 1] = unitID
	end
	return pick
end

-- The area select's step: the units under the circle added, the selection set when that changed
local function areaUpdate(force)
	local vsx, vsy = Spring.GetViewGeometry()
	local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2), true)
	if not pos then
		area.x = nil
		return
	end
	area.x, area.y, area.z = pos[1], pos[2], pos[3]
	local added = false
	for _, unitID in ipairs(Spring.GetUnitsInCylinder(pos[1], pos[3], area.radius, Spring.GetMyTeamID()) or {}) do
		if not area.units[unitID] then
			area.units[unitID] = true
			area.count = area.count + 1
			added = true
		end
	end
	if added or force then
		Spring.SelectUnitArray(areaPick())
	end
end

local function cancel()
	if pregameBuild() then
		WG["pregame-build"].setPreGameDefID(nil)
	elseif select(2, Spring.GetActiveCommand()) then
		Spring.SetActiveCommand(0)
	else
		Spring.SelectUnitArray({})
	end
end

-- The app's build menu (bardroid_buildmenu.lua, WG.bardroidBuildmenu): RB puts the pointer on it. In the controller
-- game it runs beside v0.8.5's and shows while the app's controls have the pad (WG.BarDroidOwnsBuildMenu; Kailil, of
-- v0.8.5's own focus there: "its doing a weird selector system, i dont want that, i want a mouse cursor, with a stroke
-- just like the orders").
local function buildMenu(name)
	local b = WG.bardroidBuildmenu
	if b and b.droidPad then
		b.droidPad(name)
	end
end

local function buildFocus()
	local b = WG.bardroidBuildmenu
	return b and b.droidFocus and b.droidFocus() ~= nil or false
end

local ACTIONS = {
	pad_build = function() -- RB
		ordersEnd()
		buildMenu("build")
	end,
	pad_orders = function() -- Back + RB
		if orders then
			ordersEnd()
			return
		end
		if buildFocus() then
			buildMenu("build")
		end
		ordersGo(1)
		if not orders then
			note("NO ORDERS")
		end
	end,
	pad_select = function() -- A on the order menu
		if orders then
			ordersSelect()
		end
	end,
	area_on = function()
		local _, _, _, shift = Spring.GetModKeyState()
		area.on, area.units, area.count, area.shift = true, {}, 0, shift
		area.keep = shift and Spring.GetSelectedUnits() or {}
		if not shift then
			Spring.SelectUnitArray({})
		end
		areaUpdate()
	end,
	area_off = function()
		area.on, area.radial = false, false
	end,
	area_cancel = function() -- B: the selection as it was before
		area.on, area.radial = false, false
		Spring.SelectUnitArray(area.keep)
	end,
	area_filter_open = function() -- X held in the area select: the filter radial
		area.radial, area.highlight = area.on, nil
	end,
	area_filter_pick = function() -- X let go: the side the stick picked (none: the filter stays)
		if area.radial and area.highlight then
			area.filter = area.highlight
			note("FILTER: " .. string.upper(area.filter), BLUE)
			areaUpdate(true)
		end
		area.radial, area.highlight = false, nil
	end,
	area_filter_close = function()
		area.radial, area.highlight = false, nil
	end,
	grid_on = function() -- LB with a building picked (PadGame holds Shift+Alt: BAR's grid)
		note("GRID", BLUE)
	end,
	build_placed = function() -- X placed the building: the engine lets go of it as Shift comes up, and X keeps it
		local b = WG.bardroidBuildmenu
		if b and b.droidSpot then
			b.droidSpot(nil, nil, true)
		end
	end,
	build_exit = function() -- a grid placed with A: the building put away, as v0.8.5's A does
		if pregameBuild() then
			WG["pregame-build"].setPreGameDefID(nil)
		else
			local _, id = Spring.GetActiveCommand()
			if id and id < 0 then
				Spring.SetActiveCommand(0)
			end
		end
	end,
	area_bigger = function()
		area.target = math.min(AREA_MAX, area.target + (area.target >= 160 and 80 or 20))
		note("AREA " .. area.target)
	end,
	area_smaller = function()
		area.target = math.max(AREA_MIN, area.target - (area.target > 160 and 80 or 20))
		note("AREA " .. area.target)
	end,
	pad_page_next = function() -- RB / LB on the build menu: its pages (Kailil: "pressing RB or LB cycles the tabs")
		buildMenu("pagenext")
	end,
	pad_page_prev = function()
		buildMenu("pageprev")
	end,
	-- the triple tap in the controller game (GameActivity, through bardroid_touch.lua): the app's build menu in place of
	-- v0.8.5's (DrawGenesis hides v0.8.5's panel). The app tells the app's mode again every 2 s (a LuaUI reload starts
	-- this widget with v0.8.5's): the note only when it changes
	mod_bardroid = function()
		WG.BarDroidOwnsBuildMenu = controllerGame or nil
		if modV085 then
			modV085 = false
			note("CONTROLLER MOD: BAR DROID")
		end
	end,
	mod_v085 = function()
		WG.BarDroidOwnsBuildMenu = nil
		if WG.BarDroidPadFP and WG.BarDroidPadFP.active() then -- (v0.8.5 has the pad now: nothing would drive the unit)
			WG.BarDroidPadFP.stop()
		end
		if not modV085 then
			modV085 = true
			ordersEnd()
			buildMenu("back")
			note("CONTROLLER MOD: v0.8.5")
		end
	end,
	pad_back = function()
		if orders then
			ordersEnd()
		else
			buildMenu("back")
		end
	end,
	slow_pan = function() -- Back while placing a building (v0.8.5): the pan at 30% until the building is put away
		WG.BarDroidPadSlowPan = not WG.BarDroidPadSlowPan
		note(WG.BarDroidPadSlowPan and "SLOW PAN" or "FULL PAN")
	end,
	cancel = cancel,
	commander = commander,
	idle_mobile_next = function() idleMobile(1) end,
	idle_mobile_prev = function() idleMobile(-1) end,
	idle_type = idleOfType,
	bookmark_store = function()
		bookmark = Spring.GetCameraState()
		note("BOOKMARK SET")
	end,
	bookmark_recall = function()
		if bookmark then -- (the place and the zoom; the tilt stays as it is, Kailil 2026-10-30)
			bookmark.rx = Spring.GetCameraState().rx
			Spring.SetCameraState(bookmark, 0.4)
		else
			note("LT + UP SETS A BOOKMARK")
		end
	end,
	rotate_left = function() Spring.SendCommands("buildfacing dec") end,
	rotate_right = function() Spring.SendCommands("buildfacing inc") end,
	spacing_up = function() Spring.SendCommands("buildspacing inc") end,
	spacing_down = function() Spring.SendCommands("buildspacing dec") end,
	lb_a = function() -- builders: repair (picked: A on a unit, or drag an area); else attack the enemy there, or fight
		if hasBuilder() then
			Spring.SetActiveCommand("repair")
			note("REPAIR: A")
			return
		end
		local unitID = aim()
		if enemyAt(unitID) then
			orderAt(CMD.ATTACK, "attack", true)
		else
			orderAt(CMD.FIGHT, "fight", false)
		end
	end,
	lb_x = function() -- builders: reclaim (picked); else attack there
		if hasBuilder() then
			Spring.SetActiveCommand("reclaim")
			note("RECLAIM: A")
			return
		end
		orderAt(CMD.ATTACK, "attack", true)
	end,
	lb_y = function()
		orderAt(CMD.PATROL, "patrol", false)
	end,
	path_fight = function() -- LB + A held: picked, the app's drag draws it (BAR's formation widget gives the path)
		Spring.SetActiveCommand("fight")
		note("FIGHT PATH")
	end,
	path_patrol = function() -- LB + Y held
		Spring.SetActiveCommand("patrol")
		note("PATROL PATH")
	end,
	path_end = function() -- the drag let go: BAR's formation widget has the path, and leaves the order picked for many units
		Spring.SetActiveCommand(0)
	end,
	selfd = function() -- Back + R3 + L3 held, as v0.8.5's (given again: called off)
		local selected = Spring.GetSelectedUnits()
		if #selected == 0 then
			return
		end
		if unitControl() and pcall(Spring.GiveOrderToUnitArray, selected, CMD.SELFD, {}, 0) then
			note("SELF DESTRUCT")
		else
			note("NOT IN THIS GAME")
		end
	end,
	pad_speed = function() -- Back + Y: the path speed tuner
		if WG.BarDroidPadSpeed then
			WG.BarDroidPadSpeed.toggle()
		end
	end,
	fp_toggle = function() -- LB + L3 held, or B in first person (bardroid_padfp.lua)
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.toggle()
		end
	end,
	fp_fire_on = function() -- RT in first person
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.fire(true)
		end
	end,
	fp_fire_off = function()
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.fire(false)
		end
	end,
	lb_b = function() -- stop; factories selected: stopped and their whole queue cleared (Kailil, 2026-10-29)
		if clearFactories() then
			return
		end
		Spring.SetActiveCommand("stop")
		note("STOP")
	end,
	lb_b2 = function()
		Spring.SetActiveCommand("repeat")
		note("REPEAT")
	end,
	lb_b_hold = function()
		Spring.SetActiveCommand("wait")
		note("WAIT")
	end,
	queue_remove_first = function() queueRemove(false) end,
	queue_remove_last = function() queueRemove(true) end,
	dgun = function()
		for _, unitID in ipairs(Spring.GetSelectedUnits()) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			if def and def.customParams and def.customParams.iscommander then
				Spring.SetActiveCommand("manualfire")
				note("D-GUN: A")
				return
			end
		end
		note("SELECT THE COMMANDER")
	end,
	mouse_toggle = function() -- Back + Start (the app keeps the same switch)
		mouseMode = not mouseMode
		note(freePointer() and "MOUSE ON" or "MOUSE OFF")
	end,
	group_list_on = function() -- Start held: the group list
		groupList.held = true
	end,
	group_list_off = function()
		if groupList.held then
			groupList.held, groupList.untilAt = false, now()
		end
	end,
}

-- control groups: group_<recall|assign|look|clear|show>_<1..9>. BAR's own system with other keys (Kailil, 2026-10-30: "it
-- should literarly just be the vanilla system just different UI and keybindings"): the engine's group commands and BAR's
-- autogroup, nothing kept here. Recall: "group select", the camera stays. Assign: BAR's select of the selection's types
-- on the whole map (a double tap's), "group set", and the autogroup so that those to come join. Look: "group focus".
-- Clear: the group selected, taken out of its autogroup and "group unset", the selection as it was. The group list
-- (v0.8.5's: a box for each group that has units, the slot in use too) shows while Start or Back is held and for a moment
-- after each group action.
local function groupUnits(n)
	local units = {}
	for _, unitID in ipairs(Spring.GetGroupUnits(n) or {}) do
		if not Spring.GetUnitIsDead(unitID) then
			units[#units + 1] = unitID
		end
	end
	return units
end
local function group(kind, n)
	n = tonumber(n)
	groupList.slot, groupList.untilAt = n, now()
	local autogroup = WG.autogroup
	if kind == "recall" then
		if #groupUnits(n) > 0 then
			Spring.SendCommands("group select " .. n)
			note("GROUP " .. n)
		else
			note("GROUP " .. n .. " EMPTY")
		end
	elseif kind == "assign" then
		if Spring.GetSelectedUnitsCount() == 0 then
			note("SELECT A UNIT")
			return
		end
		Spring.SendCommands("select AllMap+_InPrevSel+_ClearSelection_SelectAll+")
		Spring.SendCommands("group set " .. n)
		if autogroup and autogroup.addCurrentSelectionToAutogroup then
			autogroup.addCurrentSelectionToAutogroup(n)
		end
		note("GROUP " .. n .. " SET: " .. #groupUnits(n))
	elseif kind == "look" then
		if #groupUnits(n) > 0 then
			Spring.SendCommands("group focus " .. n .. " 0.3")
			note("GROUP " .. n)
		else
			note("GROUP " .. n .. " EMPTY")
		end
	elseif kind == "clear" then
		if #groupUnits(n) == 0 then -- (what comes next would work on the selection, in other groups)
			note("GROUP " .. n .. " EMPTY")
			return
		end
		local keep = Spring.GetSelectedUnits()
		Spring.SendCommands("group select " .. n)
		if autogroup and autogroup.removeCurrentSelectionFromAutogroup then
			autogroup.removeCurrentSelectionFromAutogroup()
		end
		Spring.SendCommands("group unset")
		Spring.SelectUnitArray(keep)
		note("GROUP " .. n .. " CLEARED")
	else
		note("GROUP " .. n)
	end
end

-- (the groups that have units, in key order 1..9, 0; the slot in use as well while it is empty)
local function groupSlots()
	local slots = {}
	for _, n in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }) do
		local units = groupUnits(n)
		if #units > 0 or n == groupList.slot then
			slots[#slots + 1] = { n = n, units = units }
		end
	end
	return slots
end

-- (where BAR's interface at the bottom of the screen ends: the order menu's top, else a tenth of the screen)
local function bottomInterfaceTop(vsy)
	local o = WG.ordermenu
	if o and o.getPosition and o.getIsShowing and o.getIsShowing() then
		local _, y = o.getPosition()
		if y then
			return math.floor(y * vsy)
		end
	end
	return math.floor(vsy * 0.1)
end

-- The group strip: one of BAR's panels in the middle just above its interface at the bottom, a box for each group with
-- units (the unit type's picture, its key at the top left, how many at the bottom right) and the slot in use outlined
-- in gold (dim while it is empty)
local function drawGroupList(vsx, vsy)
	local shown = groupList.held or (groupList.untilAt and Spring.DiffTimers(now(), groupList.untilAt) < GROUP_LIST_SECONDS)
	if not shown then
		groupList.untilAt = nil
		return
	end
	local alpha = groupList.held and 1 or math.min(1, (GROUP_LIST_SECONDS - Spring.DiffTimers(now(), groupList.untilAt)) / 0.3)
	local slots = groupSlots()
	local size = style.size(0.048)
	local gap = math.max(2, math.floor(size * 0.12))
	local pad = math.max(3, math.floor(size * 0.16))
	local width = #slots * size + (#slots - 1) * gap
	local x0 = math.floor((vsx - width) / 2)
	local y0 = bottomInterfaceTop(vsy) + pad * 3
	style.panel(x0 - pad, y0 - pad, x0 + width + pad, y0 + size + pad, alpha)
	local font = WG.fonts and WG.fonts.getFont()
	for i, s in ipairs(slots) do
		local x = x0 + (i - 1) * (size + gap)
		local active = s.n == groupList.slot
		local empty = #s.units == 0
		style.fill(x, y0, x + size, y0 + size, { 0.12, 0.12, 0.12, 0.9 }, alpha)
		local defID = s.units[1] and Spring.GetUnitDefID(s.units[1])
		if defID then
			local inset = math.max(2, math.floor(size * 0.06))
			gl.Color(1, 1, 1, (active and 1 or 0.8) * alpha)
			gl.Texture("#" .. defID)
			gl.TexRect(x + inset, y0 + inset, x + size - inset, y0 + size - inset)
			gl.Texture(false)
		end
		if active then
			style.outline(x, y0, x + size, y0 + size, style.GOLD, (empty and 0.6 or 1) * alpha)
		else
			style.outline(x, y0, x + size, y0 + size, { 1, 1, 1 }, 0.14 * alpha, 1)
		end
		if font then
			local ts = math.floor(size * 0.3)
			font:Begin()
			font:SetOutlineColor(0, 0, 0, 0.8 * alpha)
			if empty then -- (no unit's picture to share the box with: the slot's number big, in the middle)
				local big = math.floor(size * 0.46)
				font:SetTextColor(1, 1, 1, (active and 0.8 or 0.5) * alpha)
				font:Print(tostring(s.n), x + size / 2, y0 + size / 2 - big * 0.36, big, "co")
			else
				font:SetTextColor(1, 1, 1, alpha)
				font:Print(tostring(s.n), x + size * 0.1, y0 + size - ts * 1.05, ts, "o")
				font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], alpha)
				font:Print(tostring(#s.units), x + size * 0.92, y0 + size * 0.08, ts, "ro")
			end
			font:End()
		end
	end
	gl.Color(1, 1, 1, 1)
end

-- v0.8.5's filter radial around the area select's middle: the four filters in BAR's panels, each with its colour's dot;
-- the one the stick points at outlined in gold, the one in use outlined faintly
local FILTER_PLACES = { { "All Mobile", 0, 1, { 0.35, 0.75, 1 } }, { "Combat", 0, -1, { 1, 0.4, 0.25 } },
	{ "Builders", -1, 0, { 1, 0.75, 0.15 } }, { "Air", 1, 0, { 0.55, 0.95, 0.55 } } }
local function drawFilterRadial(cx, cy, vsy)
	local font = WG.fonts and WG.fonts.getFont()
	if not font then
		return
	end
	local size = style.size(0.019)
	local pad = math.floor(size * 0.7)
	local dot = math.floor(size * 0.5)
	local w = 0
	for _, p in ipairs(FILTER_PLACES) do
		w = math.max(w, font:GetTextWidth(string.upper(p[1])) * size)
	end
	w = math.ceil(w) + dot + pad * 3
	local h = math.floor(size * 2)
	local r = math.max(h * 2.2, vsy * 0.13)
	for _, p in ipairs(FILTER_PLACES) do
		local lit, inUse = area.highlight == p[1], area.filter == p[1]
		local x = math.floor(cx + p[2] * (r * 0.9 + w / 2) - w / 2)
		local y = math.floor(cy + p[3] * r - h / 2)
		style.panel(x, y, x + w, y + h, 1)
		if lit then
			style.outline(x, y, x + w, y + h, style.GOLD, 1)
		elseif inUse then
			style.outline(x, y, x + w, y + h, { 1, 1, 1 }, 0.35, 1)
		end
		local c = p[4]
		style.disc(x + pad + dot / 2, y + h / 2, dot / 2, c, lit and 1 or 0.8)
		font:Begin()
		font:SetOutlineColor(0, 0, 0, 0.6)
		local t = lit and style.GOLD or style.TEXT
		font:SetTextColor(t[1], t[2], t[3], (lit or inUse) and 1 or 0.8)
		font:Print(string.upper(p[1]), x + pad * 2 + dot, y + h / 2 - size * 0.36, size, "o")
		font:End()
	end
	gl.Color(1, 1, 1, 1)
end

local function act(name)
	local action = ACTIONS[name]
	if action then
		action()
		return true
	end
	local kind, n = name:match("^group_(%a+)_(%d)$")
	if kind then
		group(kind, n)
		return true
	end
	local fpOrder = name:match("^fp_order_(%a+)$")
	if fpOrder then -- (first person: the squad's orders)
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.order(fpOrder)
		end
		return true
	end
	local side = FILTER_SIDES[name:match("^area_filter_(%a+)$") or ""]
	if side then -- (the left stick on the filter radial)
		if area.radial then
			area.highlight = side
		end
		return true
	end
	-- the D-pad on a menu
	local dir = name:match("^pad_(%a+)$")
	if dir == "left" or dir == "right" or dir == "up" or dir == "down" then
		if orders then
			ordersStep(dir == "left" and -1 or dir == "right" and 1 or 0, dir == "up" and -1 or dir == "down" and 1 or 0)
		else
			buildMenu(dir)
		end
		return true
	end
	return false
end

-- The order menu while the pad is the input (Kailil, 2026-10-29, both controller modes): the orders the pad gives with
-- its buttons are hidden (BAR's own switch, WG.ordermenu.setDisabledCmd), so the rest is bigger. BAR saves that switch
-- with its settings, so the names hidden here are kept in springsettings (bardroid_pad_hidden_orders) and shown again
-- at the next start, whatever ended the game; names the player had hidden in BAR's options stay theirs.
local PAD_HIDDEN_ORDERS = { "Stop", "Wait", "Attack", "Repeat", "Move", "Reclaim", "Repair", "Fight", "Patrol" }
local HIDDEN_KEY = "bardroid_pad_hidden_orders"
local ordersHidden, ordersRecovered = nil, false
local function padOrders(want)
	local o = WG.ordermenu
	if not (o and o.getDisabledCmd and o.setDisabledCmd) then
		return
	end
	if not ordersRecovered then -- (a game that ended with them hidden)
		ordersRecovered = true
		for name in (Spring.GetConfigString(HIDDEN_KEY, "") or ""):gmatch("[^,]+") do
			o.setDisabledCmd({ name, false })
		end
		Spring.SetConfigString(HIDDEN_KEY, "")
	end
	if want == (ordersHidden ~= nil) then
		return
	end
	-- (the controller game's order menu then lays the rest out evenly over the whole menu: gui_ordermenu.lua there)
	WG.BarDroidPadOrders = want or nil
	if want then
		ordersHidden = {}
		for _, name in ipairs(PAD_HIDDEN_ORDERS) do
			if not o.getDisabledCmd(name) then
				o.setDisabledCmd({ name, true })
				ordersHidden[#ordersHidden + 1] = name
			end
		end
		Spring.SetConfigString(HIDDEN_KEY, table.concat(ordersHidden, ","))
	else
		for _, name in ipairs(ordersHidden) do
			o.setDisabledCmd({ name, false })
		end
		ordersHidden = nil
		Spring.SetConfigString(HIDDEN_KEY, "")
	end
end

-- BAR's info panel (bottom left) shows the unit under the pointer before the selection, and the pad's pointer rests in
-- the middle of the screen: a unit there stayed on the panel, whatever was selected, also after B, until a tap moved the
-- pointer (Kailil, 2026-10-30: it "freezes ... or it doesn't close after I hit B"). While the pad is in use with its
-- pointer in the middle the panel gets no hover (BAR's own WG.info.setCustomHover, there for its picture-in-picture).
local hoverOff = false
local function padHover()
	local info = WG.info
	if not (info and info.setCustomHover and info.clearCustomHover) then
		return
	end
	local want = WG.BarDroidPadOnly == true and not freePointer() and not orders and not buildFocus()
	if want ~= hoverOff then
		hoverOff = want
		if want then
			info.setCustomHover("none", 1)
		else
			info.clearCustomHover()
		end
	end
end

-- QUEUE (Kailil, 2026-10-30: touch "doesn't have a way to add to queue (the shift button)"): a button above the order
-- menu while fingers have units selected, a sticky Shift: on, the app holds Shift, so orders and buildings queue as with
-- BAR's Shift key, until it is tapped off (bardroid_pad.txt "queue 1", RtsTouch). Over any of BAR's interface it answers
-- IsAbove, so a tap on it is a click and not an order.
local queue = { on = false, rect = nil }
local function queueShows()
	return queue.on or (WG.BarDroidPadOnly ~= true and WG.BarDroidInput ~= "mouse" and not Spring.GetSpectatingState()
		and Spring.GetSelectedUnitsCount() > 0)
end
local function queueLayout(vsx, vsy)
	if not queueShows() then
		queue.rect = nil
		return
	end
	local h, w = style.size(0.036), style.size(0.11)
	local gap = style.size(0.008, 3)
	local x1, y0 = math.floor(vsx * 0.65), math.floor(vsy * 0.16)
	local o = WG.ordermenu
	if o and o.getPosition and o.getIsShowing and o.getIsShowing() then
		local x, y, width = o.getPosition()
		if x and y and width then
			x1, y0 = math.floor((x + width) * vsx), math.floor(y * vsy) + gap
		end
	end
	queue.rect = { x1 - w, y0, x1, y0 + h }
end
local function drawQueue()
	local r = queue.rect
	local font = WG.fonts and WG.fonts.getFont()
	if not (r and font) then
		return
	end
	style.panel(r[1], r[2], r[3], r[4], 1)
	if queue.on then
		style.outline(r[1], r[2], r[3], r[4], style.GOLD, 1)
	end
	local size = math.floor((r[4] - r[2]) * 0.5)
	local c = queue.on and style.GOLD or style.TEXT
	font:Begin()
	font:SetOutlineColor(0, 0, 0, 0.6)
	font:SetTextColor(c[1], c[2], c[3], 1)
	font:Print("QUEUE", (r[1] + r[3]) / 2, (r[2] + r[4]) / 2 - size * 0.36, size, "co")
	font:End()
end
local function inQueueButton(x, y)
	local r = queue.rect
	return r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end
function widget:IsAbove(x, y)
	return inQueueButton(x, y)
end
-- Presses before the first draws go no further (2026-10-30): BAR's music widget reads its buttons before it has any, and
-- BAR takes a widget that fails out of the game: no music, no volume sliders. A tap while the game loads comes in just then.
local draws = 0
function widget:MousePress(x, y)
	if draws < 2 then
		return true
	end
	if inQueueButton(x, y) then
		queue.on = not queue.on
		return true
	end
	return false
end

-- The order menu on the pad follows the pointer once it is the player's again (the warp landed, or half a second),
-- keeps it on the menu (pushed off it for LEAVE_SECONDS it lets go) and ends when the menu goes; the app is told
-- which menu has the pad and what is picked
function widget:Update(dt)
	padOrders(WG.BarDroidPadOnly == true)
	padHover()
	if queue.on and WG.BarDroidPadOnly == true then -- (fingers' button: left on, it would queue every order of the pad's)
		queue.on = false
	end
	if area.radius ~= area.target then
		local r = area.radius + (area.target - area.radius) * math.min(1, (dt or 0) / AREA_EASE)
		area.radius = math.abs(area.target - r) < 1 and area.target or r
	end
	if orders then
		local layout = ordersLayout()
		if not layout then
			ordersEnd()
		else
			orders.layout = layout
			local mx, my = pointerAt()
			local recorded = fakeWarp and not fakePointer -- (the moves only recorded: no pointer to follow)
			local w = recorded or orders.warped
			if w and not recorded and ((math.abs(mx - w[1]) <= 2 and math.abs(my - w[2]) <= 2) or Spring.DiffTimers(now(), w[3]) > 0.5) then
				orders.warped, w = nil, nil
			end
			if not w then
				local over
				for i, r in ipairs(layout.cells) do
					if i <= #layout.cmds and mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then
						over = i
						break
					end
				end
				-- (also the same cell with another order in it: the menu changed under a pointer at rest, as when a
				-- selected unit dies or the priority target button comes; the order lit and given is the one there)
				if over and (over ~= orders.index or layout.cmds[over].id ~= orders.cmdID) then
					orders.index, orders.cmdID = over, layout.cmds[over].id
					ordersLight(orders.cmdID)
				end
				local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge -- (the menu: all its cells)
				for _, r in ipairs(layout.cells) do
					x0, y0, x1, y1 = math.min(x0, r[1] + 2), math.min(y0, r[2] + 2), math.max(x1, r[3] - 2), math.max(y1, r[4] - 2)
				end
				if mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
					orders.outSince = nil
				elseif not orders.outSince then
					orders.outSince = now()
					warpTo(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				elseif Spring.DiffTimers(now(), orders.outSince) >= LEAVE_SECONDS then
					ordersEnd()
				else
					warpTo(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				end
			end
		end
	end
	if area.on then
		areaUpdate()
	end
	local armed = armedKind()
	if armed ~= "build" and WG.BarDroidPadSlowPan then -- (the slow pan is for placing only, as in v0.8.5)
		WG.BarDroidPadSlowPan = nil
	end
	local focus = orders and "orders" or (buildFocus() and "build" or "none")
	local pregame = Spring.GetGameFrame() == 0 and not Spring.GetSpectatingState()
	local text = "focus " .. focus .. "\npregame " .. (pregame and 1 or 0) .. "\narmed " .. armed .. "\ndrawspeed "
		.. string.format("%.2f", WG.BarDroidDrawSpeed or 1) .. "\nqueue " .. (queue.on and 1 or 0)
		.. "\nfp " .. ((WG.BarDroidPadFP and WG.BarDroidPadFP.active()) and 1 or 0) .. "\n"
	local t = now()
	local keep = focus ~= "none" or pregame or armed ~= "none" or queue.on or text:find("fp 1", 1, true)
	if text ~= written or (keep and Spring.DiffTimers(t, writtenAt) > 1) then
		if writeWhole(PAD_FILE, text) then
			written, writtenAt = text, t
		end
	end
end

-- The area select's circle on the ground
function widget:DrawWorld()
	if area.on and area.x then
		gl.DepthTest(false)
		gl.LineWidth(2.5)
		gl.Color(area.shift and 1 or 0.35, area.shift and 0.85 or 1, 0.35, 0.9)
		gl.DrawGroundCircle(area.x, area.y, area.z, area.radius, 48)
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
	end
end

-- The controller game with the app's controls: v0.8.5's build menu panel hidden through its own switch
-- (controllerSetPanelVisible); v0.8.5's camera widget sets that switch again in each Update, so here, after every
-- Update and before anything is drawn or clicked
function widget:DrawGenesis()
	local b = WG.buildmenu
	if WG.BarDroidOwnsBuildMenu and b and b ~= WG.bardroidBuildmenu and b.controllerSetPanelVisible then
		b.controllerSetPanelVisible(false)
	end
end

-- The reticle in the middle of the screen while the pad is the input (and its pointer is there), and the notes
function widget:DrawScreen()
	draws = math.min(draws + 1, 2)
	local vsx, vsy = Spring.GetViewGeometry()
	local cx, cy = math.floor(vsx / 2), math.floor(vsy / 2)
	local pad = WG.BarDroidInput == "pad"
	local riding = WG.BarDroidPadFP and WG.BarDroidPadFP.active() -- (first person has its own crosshair)
	if pad and not riding and not modV085 and not orders and not buildFocus() and not freePointer() then
		-- (a white ring on a dark one: it reads over snow and over water alike)
		local r = style.size(0.016)
		for pass = 1, 2 do
			gl.Color(pass == 1 and 0 or 1, pass == 1 and 0 or 1, pass == 1 and 0 or 1, pass == 1 and 0.35 or 0.75)
			gl.LineWidth(pass == 1 and 4 or 2)
			gl.BeginEnd(GL.LINE_LOOP, function()
				for i = 0, 47 do
					local a = i / 48 * 2 * math.pi
					gl.Vertex(cx + math.cos(a) * r, cy + math.sin(a) * r)
				end
			end)
		end
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
	end
	-- the order on the pad: outlined in gold over BAR's own highlight, as the build menu's option on the pad
	local cell = orders and orders.layout and orders.layout.cells[orders.index]
	if cell then
		style.outline(cell[1] + 1, cell[2] + 1, cell[3] - 1, cell[4] - 1, style.GOLD, 1)
	end
	if not modV085 and not (area.radial and area.on) then -- (the filter radial reaches down to where the strip is)
		drawGroupList(vsx, vsy)
	end
	if area.radial and area.on then
		drawFilterRadial(cx, cy, vsy)
	end
	queueLayout(vsx, vsy)
	drawQueue()
	if toast then
		local age = Spring.DiffTimers(now(), toastAt)
		if age > TOAST_SECONDS then
			toast = nil
			return
		end
		-- (a quick fade in, a slower fade out; a pad button at the end of a note as its key)
		local alpha = math.max(0, math.min(1, age / 0.08, (TOAST_SECONDS - age) / 0.3))
		local words, key = toast:match("^(.-): ([ABXY])$")
		style.toast(words or toast, cx, cy + vsy * 0.09, toastColor, alpha, key)
	end
end

function widget:Initialize()
	-- the controller game (as bardroid_touch.lua finds it): the pad is v0.8.5's until a triple tap switches it
	local ok, found = pcall(VFS.FileExists, "LuaUI/Widgets/controller_socket_bridge.lua", VFS.ZIP)
	controllerGame = (ok and found) or Game.gameVersion == "$VERSION"
	modV085 = controllerGame
	WG.BarDroidStyle = style -- (the app's build menu: its GRID note and its option on the pad in the same look)
	WG.BarDroidPad = {
		act = act,
		say = note, -- (bardroid_padfp.lua's notes)
		-- (tools/touch-widget-test.ps1: the order on the pad, its place in the menu, the menu's size; putting the pad on
		-- one order; pointer moves recorded instead of made)
		orders = function()
			return orders and orders.cmdID, orders and orders.index, orders and #orders.layout.cmds
		end,
		ordersCells = function() -- (the order menu's cells as worked out here, and its commands)
			local layout = ordersLayout()
			return layout and layout.cells, layout and layout.cmds
		end,
		ordersOn = function(cmdID)
			local layout = ordersLayout()
			for i, cmd in ipairs(layout and layout.cmds or {}) do
				if cmd.id == cmdID then
					ordersGo(i)
					return true
				end
			end
			return false
		end,
		setWarp = function(fn)
			warp, fakeWarp = fn or Spring.WarpMouse, fn ~= nil
			if not fn then
				fakePointer = nil
			end
		end,
		setPointer = function(x, y) -- (a made-up pointer the recorded moves land on, with setWarp; nil: none)
			fakePointer = x and { x, y } or nil
		end,
		note = function() -- (the note showing, the last one shown, how many so far)
			return toast, lastNote, notes
		end,
		area = function() -- (the area select: on, its radius, how many units it has passed over; its filter, radial)
			return area.on, area.target, area.count, area.filter, area.radial and area.highlight
		end,
		chooseUnits = chooseUnits, -- (what the area select takes of units: made-up unit types)
		ordersHidden = function() -- (the order menu's orders hidden while the pad is the input)
			return ordersHidden
		end,
		queueOn = function(on) -- (QUEUE: on or off, as a tap on it would)
			if on ~= nil then
				queue.on = on
			end
			return queue.on
		end,
	}
end

function widget:Shutdown()
	padOrders(false)
	ordersEnd()
	if hoverOff and WG.info and WG.info.clearCustomHover then
		WG.info.clearCustomHover()
	end
	WG.BarDroidPad = nil
	WG.BarDroidStyle = nil
	WG.BarDroidOwnsBuildMenu = nil
	writeWhole(PAD_FILE, "focus none\npregame 0\narmed none\nqueue 0\n")
end
