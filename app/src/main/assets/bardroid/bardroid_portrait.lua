-- BAR Droid portrait dock (Kailil, 2026-11-09: "Lets explore vertical orientation for playing bar ... All the menu ui
-- stuff can be on the bottom portion of the phone. And the game unobstructed shows at the top half"; his pick, layout
-- D: "Lets do D but instead of more orders button ... just have a scroll option ... Cap the buildmenu to 3x4 and have
-- the vertical scroll. If phone has less vertical space, reduce to 3x3 at minimum 3x2. Scroll should be magnetic ...
-- Do not allow scroll to half reveal objects. It should snap the next rows into place").
--
-- While the game's screen is taller than wide (a phone held upright, the unfolded Fold7 held upright: Android leaves
-- the game's orientation to the hand there) the lower half is a dock for touch:
--   selection row  the units picked (picture, name, count, health), or nothing picked: the control groups as pictures
--   left           a builder or factory: its build options, 3 wide, 2-4 rows in sight, scrolled by whole rows;
--                  other units: the selection by type (a tap keeps that type); nothing picked, after LOCAL UNITS or
--                  ALL UNITS: the combat units by type (a tap picks them; MULTI picks several types)
--   right          the orders, 2 wide, scrolled by whole rows; a building picked: its placing buttons; a factory's
--                  item pressed: that item's queue buttons; nothing picked: LOCAL UNITS / ALL UNITS
-- Every press goes through Spring.SetActiveCommand or a selection, as BAR's own menus do (no GiveOrder: online-safe).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid portrait",
		desc = "Portrait play: the game on top, a touch dock below (build grid, orders, groups)",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -10, -- (before BAR's menus and the touch widget: the dock answers IsAbove and presses first)
		enabled = true,
	}
end

local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local spGetActiveCmdDescs, spGetActiveCommand = Spring.GetActiveCmdDescs, Spring.GetActiveCommand
local spGetSelectedUnits, spGetSelectedUnitsCounts = Spring.GetSelectedUnits, Spring.GetSelectedUnitsCounts
local spGetCmdDescIndex, spSetActiveCommand = Spring.GetCmdDescIndex, Spring.SetActiveCommand
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local timer0 = spGetTimer()
local function now()
	return spDiffTimers(spGetTimer(), timer0)
end

local GOLD = { 1, 0.78, 0.25, 1 }
local PORTRAIT = 1.15 -- taller than wide by this much: the dock is up
local DOCK = 0.54 -- of the screen's height
local TAP_SLOP = 0.012 -- of the screen's width: a press that moves less is a tap

---------------------------------------------------------------------------------------------------------------------
-- Rows that scroll by whole rows (Kailil: "Scroll should be magnetic ... A swipe up or down should make the next blocks
-- appear with a small nudge animation ... Do not allow scroll to half reveal objects"). A drag follows the finger; on
-- release the list settles on whole rows: a quick swipe brings the next page, a slow drag the nearest row; the settle
-- overshoots a little and comes back (the nudge). At rest no row is cut.
local SETTLE, OVERSHOOT, FLICK = 0.30, 1.4, 3.0 -- seconds; easeOutBack's overshoot; rows a second for a swipe

local function snapNew()
	return { rows = 0, visible = 1, pos = 0, from = 0, to = 0, t = 1 }
end
local function snapMax(s)
	return max(0, s.rows - s.visible)
end
local function easeOutBack(t)
	t = t - 1
	return 1 + (OVERSHOOT + 1) * t * t * t + OVERSHOOT * t * t
end
local function snapSettle(s, target)
	s.from, s.to, s.t = s.pos, max(0, min(snapMax(s), target)), 0
end
local function snapSet(s, rows, visible, keep)
	s.rows, s.visible = rows, visible
	if not keep then
		s.pos, s.from, s.to, s.t = 0, 0, 0, 1
	elseif s.to > snapMax(s) then
		snapSettle(s, snapMax(s))
	end
end
local function snapPress(s, y)
	s.drag = { y0 = y, pos0 = s.pos, lastY = y, lastT = now(), vel = 0, moved = false }
	s.t = 1 -- (a press holds a settle where it is)
end
local function snapMove(s, y, rowH, slop)
	local d = s.drag
	if not d or (not d.moved and abs(y - d.y0) < slop) then
		return false
	end
	d.moved = true
	local p = d.pos0 + (y - d.y0) / rowH -- (a finger moving up brings the rows below into sight)
	local hi = snapMax(s)
	if p < 0 then
		p = p / 3 -- (past the ends a rubber band, a third as far)
	elseif p > hi then
		p = hi + (p - hi) / 3
	end
	local t = now()
	if t > d.lastT then
		d.vel = 0.6 * d.vel + 0.4 * ((y - d.lastY) / rowH / (t - d.lastT))
	end
	d.lastY, d.lastT, s.pos = y, t, p
	return true
end
local function snapRelease(s) -- true: it was a drag
	local d = s.drag
	s.drag = nil
	if not (d and d.moved) then
		return false
	end
	local base = floor(d.pos0 + 0.5)
	if d.vel > FLICK then
		snapSettle(s, max(base + s.visible, floor(s.pos + 0.5)))
	elseif d.vel < -FLICK then
		snapSettle(s, min(base - s.visible, floor(s.pos + 0.5)))
	else
		snapSettle(s, floor(s.pos + 0.5))
	end
	return true
end
local function snapUpdate(s, dt)
	if s.drag or s.t >= 1 then
		return
	end
	s.t = min(1, s.t + dt / SETTLE)
	s.pos = s.t >= 1 and s.to or s.from + (s.to - s.from) * easeOutBack(s.t)
end

---------------------------------------------------------------------------------------------------------------------
-- State

local active = false -- the dock is up (a tall screen, playing)
local vsx, vsy = 0, 0
local L = {} -- the layout: rects { x0, y0, x1, y1 } (GL: y up from the bottom)
local font, bold
local leftScroll, rightScroll = snapNew(), snapNew()
local leftItems, rightItems = {}, {} -- what the two sections show now (tiles, buttons)
local leftKind, rightKind = "", ""
local press -- { side, x, y, item } while a finger is down on the dock
local typesFrom -- nil, or "local" / "all": LOCAL UNITS or ALL UNITS pressed, the combat units by type on the left
local multi, multiPicked = false, {}
local factoryItem -- a factory's build option pressed last: its queue buttons on the right
local lastSelection = ""

local function inRect(x, y, r)
	return r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end

local function myTeam()
	return Spring.GetMyTeamID()
end

local function playing()
	local spec = Spring.GetSpectatingState()
	return not spec
end

---------------------------------------------------------------------------------------------------------------------
-- Layout: the dock's rects for this screen; the build grid 3 wide with 2-4 rows, as many as fit

local function layout()
	vsx, vsy = Spring.GetViewGeometry()
	local pad = max(4, floor(vsx * 0.012))
	local dockH = floor(vsy * DOCK)
	local selH = floor(vsx * 0.17)
	L.pad, L.gap = pad, max(3, floor(pad * 0.6))
	L.dock = { 0, 0, vsx, dockH }
	L.sel = { pad, dockH - pad - selH, vsx - pad, dockH - pad }
	local gridTop = L.sel[2] - pad
	local mid = floor(vsx * 0.5)
	L.left = { pad, pad, mid - floor(pad / 2), gridTop }
	L.right = { mid + floor(pad / 2), pad, vsx - pad, gridTop }
	-- build tiles: 3 wide, square; rows that fit, 2 to 4 (Kailil: "Cap the buildmenu to 3x4 ... at minimum 3x2")
	local lw = L.left[3] - L.left[1]
	L.tile = floor((lw - 2 * L.gap) / 3)
	local gh = gridTop - pad
	L.leftRows = max(2, min(4, floor((gh + L.gap) / (L.tile + L.gap))))
	if L.leftRows * (L.tile + L.gap) - L.gap > gh then -- (2 rows that do not fit: smaller tiles)
		L.tile = floor((gh + L.gap) / L.leftRows) - L.gap
	end
	-- order buttons: 2 wide, a bit under half a tile tall; as many rows as fit in the same height
	local rw = L.right[3] - L.right[1]
	L.btnW = floor((rw - L.gap) / 2)
	local leftH = L.leftRows * (L.tile + L.gap) - L.gap
	L.rightRows = max(3, floor((leftH + L.gap) / (floor(L.tile * 0.46) + L.gap)))
	L.btnH = floor((leftH + L.gap) / L.rightRows) - L.gap
	-- both sections end at the grid's height, from the selection row down
	L.left[2] = gridTop - leftH
	L.right[2] = L.left[2]
	-- nothing picked: the control groups along the bottom, under LOCAL / ALL UNITS
	L.groups = { pad, pad, vsx - pad, pad + floor(L.tile * 0.8) }
end

---------------------------------------------------------------------------------------------------------------------
-- What the sections hold

local function cmdLabel(cmd)
	if cmd.type == CMDTYPE.ICON_MODE and cmd.params and #cmd.params > 1 then
		local state = tonumber(cmd.params[1]) or 0
		return cmd.params[state + 2] or cmd.name, state, #cmd.params - 1
	end
	return cmd.name
end

-- BAR's order menu's filter (gui_ordermenu.lua, as bardroid_pad.lua's orderCommands): BAR marks every command hidden
-- (the engine's own panel), so "hidden" says nothing; these are the ones its menu leaves out
local HIDDEN = {
	[CMD.LOAD_ONTO] = true, [CMD.SELFD] = true, [CMD.GATHERWAIT] = true, [CMD.SQUADWAIT] = true,
	[CMD.DEATHWAIT] = true, [CMD.TIMEWAIT] = true, [CMD.AUTOREPAIRLEVEL] = true, [39812] = true, [34922] = true,
	[34924] = true, -- (cancel target: only with a priority target; left out here)
}
local HIDDEN_TYPE = { [CMDTYPE.CUSTOM] = true, [CMDTYPE.PREV] = true, [CMDTYPE.NEXT] = true }

-- the selection's build options (builders, factories) and its orders in the order menu's order (states, Wait, the
-- rest), from the engine's own list
local function readCommands()
	local builds, states, others, wait = {}, {}, {}, nil
	for _, cmd in ipairs(spGetActiveCmdDescs() or {}) do
		if type(cmd) == "table" and cmd.action and not cmd.disabled and not HIDDEN[cmd.id] and not HIDDEN_TYPE[cmd.type] then
			if cmd.action:find("buildunit_", 1, true) == 1 then
				builds[#builds + 1] = { kind = "build", id = cmd.id, defID = -cmd.id,
					queued = tonumber(cmd.params and cmd.params[1]) }
			elseif cmd.type ~= CMDTYPE.ICON_BUILDING then
				local label, state, count = cmdLabel(cmd)
				local item = { kind = "order", id = cmd.id, label = label, state = state, states = count }
				if cmd.type == CMDTYPE.ICON_MODE then
					states[#states + 1] = item
				elseif cmd.id == CMD.WAIT then
					wait = item
				else
					others[#others + 1] = item
				end
			end
		end
	end
	if wait then
		states[#states + 1] = wait
	end
	for _, item in ipairs(others) do
		states[#states + 1] = item
	end
	return builds, states
end

local function selectedFactory()
	local counts = spGetSelectedUnitsCounts()
	if not counts or (counts.n or 0) == 0 then
		return false
	end
	for defID in pairs(counts) do
		local ud = defID ~= "n" and UnitDefs[defID]
		if ud and ud.isFactory then
			return true
		end
	end
	return false
end

-- combat units: they move and carry a weapon, and build nothing
local function combat(ud)
	return ud and ud.canMove and not ud.isBuilder and not ud.isFactory and ud.weapons and #ud.weapons > 0
end

-- the units by type: { defID, units = {...} }, the biggest groups first
local function byType(units, filter)
	local t, list = {}, {}
	for _, u in ipairs(units or {}) do
		local d = Spring.GetUnitDefID(u)
		if d and (not filter or filter(UnitDefs[d])) then
			if not t[d] then
				t[d] = { kind = "type", defID = d, units = {} }
				list[#list + 1] = t[d]
			end
			local g = t[d].units
			g[#g + 1] = u
		end
	end
	table.sort(list, function(a, b)
		return #a.units > #b.units or (#a.units == #b.units and a.defID < b.defID)
	end)
	return list
end

local function typesUnits()
	if typesFrom == "local" then
		return Spring.GetVisibleUnits(myTeam(), nil, false)
	end
	return Spring.GetTeamUnits(myTeam())
end

local function activeBuild()
	local _, cmdID = spGetActiveCommand()
	return cmdID and cmdID < 0 and cmdID or nil
end

-- what each section shows, refreshed a few times a second and after every press
local function refresh()
	local sel = spGetSelectedUnits() or {}
	local key = #sel .. ":" .. tostring(sel[1])
	if key ~= lastSelection then
		lastSelection, factoryItem = key, nil
		if #sel > 0 and not multi then
			typesFrom = nil
		end
	end
	local builds, orders = readCommands()
	local newLeft, newRight, lk, rk
	if typesFrom then -- LOCAL / ALL UNITS: the combat units by type, ALL first
		local types = byType(typesUnits(), combat)
		newLeft = { { kind = "alltypes", label = "ALL", count = 0 } }
		for _, g in ipairs(types) do
			newLeft[#newLeft + 1] = g
			newLeft[1].count = newLeft[1].count + #g.units
		end
		lk = "types:" .. typesFrom
	elseif #sel == 0 then
		newLeft, lk = {}, "none"
	elseif #builds > 0 then
		newLeft, lk = builds, "build"
	else -- units that build nothing: the selection by type (a tap keeps one type)
		newLeft, lk = byType(sel), "seltypes"
		for _, g in ipairs(newLeft) do
			g.kind = "seltype"
		end
	end
	local building = activeBuild()
	if #sel == 0 or typesFrom then
		newRight = {
			{ kind = "units", from = "local", label = "LOCAL UNITS" },
			{ kind = "units", from = "all", label = "ALL UNITS" },
		}
		if typesFrom then
			newRight[#newRight + 1] = { kind = "multi", label = multi and "MULTI: ON" or "MULTI" }
			newRight[#newRight + 1] = { kind = "done", label = "DONE" }
		end
		rk = "units"
	elseif building and not selectedFactory() then -- a building picked: its shapes, and PLACE under them (the build
		-- menu copy's panel, in placeRect: RtsTouch places from its rects, bardroid_place.txt)
		newRight = {
			{ kind = "shape", shape = "one", label = "ONE" }, { kind = "shape", shape = "line", label = "LINE" },
			{ kind = "shape", shape = "grid", label = "GRID" }, { kind = "shape", shape = "border", label = "BORDER" },
		}
		rk = "place"
	elseif factoryItem then -- a factory's item pressed: its queue
		newRight = {
			{ kind = "queue", n = 1, label = "+1" }, { kind = "queue", n = 5, label = "+5" },
			{ kind = "queue", n = 20, label = "+20" }, { kind = "queue", n = -1, label = "-1" },
			{ kind = "clearitem", label = "CLEAR" }, { kind = "back", label = "ORDERS" },
		}
		rk = "factory"
	else
		newRight, rk = orders, "orders"
	end
	leftItems, rightItems = newLeft, newRight
	snapSet(leftScroll, math.ceil(#leftItems / 3), L.leftRows or 2, lk == leftKind)
	snapSet(rightScroll, math.ceil(#rightItems / 2), L.rightRows or 3, rk == rightKind)
	if lk ~= leftKind or rk ~= rightKind then
		Spring.Echo(string.format("[bardroid-portrait] %d picked: left %s (%d), right %s (%d)", #sel, lk, #leftItems, rk,
			#rightItems)) -- (tools: what the dock shows)
	end
	leftKind, rightKind = lk, rk
end

---------------------------------------------------------------------------------------------------------------------
-- Pressing

local function runCommand(id, right, shift, ctrl)
	local index = spGetCmdDescIndex(id)
	if index then
		spSetActiveCommand(index, right and 3 or 1, not right, right or false, false, ctrl or false, false, shift or false)
	end
end

local function selectUnits(units, append)
	Spring.SelectUnitArray(units or {}, append or false)
end

local function pressItem(item, long)
	if not item then
		return
	end
	local k = item.kind
	if k == "build" then
		if selectedFactory() then -- a factory: one more (a long press: one less), and its queue buttons
			runCommand(item.id, long)
			factoryItem = item.id
		else
			runCommand(item.id)
		end
	elseif k == "order" then
		runCommand(item.id, long)
	elseif k == "units" then
		typesFrom = typesFrom ~= item.from and item.from or nil
		multi, multiPicked = false, {}
	elseif k == "multi" then
		multi, multiPicked = not multi, {}
	elseif k == "done" then
		typesFrom, multi, multiPicked = nil, false, {}
	elseif k == "alltypes" then
		local all = {}
		for _, g in ipairs(leftItems) do
			for _, u in ipairs(g.units or {}) do
				all[#all + 1] = u
			end
		end
		selectUnits(all)
		typesFrom, multi, multiPicked = nil, false, {}
	elseif k == "type" then
		if multi then
			multiPicked[item.defID] = not multiPicked[item.defID] or nil
			local all = {}
			for _, g in ipairs(leftItems) do
				if g.defID and multiPicked[g.defID] then
					for _, u in ipairs(g.units) do
						all[#all + 1] = u
					end
				end
			end
			selectUnits(all)
		else
			selectUnits(item.units)
			typesFrom = nil
		end
	elseif k == "seltype" then
		selectUnits(item.units)
	elseif k == "shape" then
		local B = WG.bardroidBuildmenu
		if B and B.droidSetShape then
			B.droidSetShape(item.shape)
		end
	elseif k == "queue" and factoryItem then
		if item.n < 0 then
			runCommand(factoryItem, true)
		else
			runCommand(factoryItem, false, item.n >= 5, item.n >= 20) -- (Shift: 5, Ctrl: 20, as BAR's build menu)
		end
	elseif k == "clearitem" and factoryItem then
		runCommand(factoryItem, true, true, true) -- (right click with Shift and Ctrl: the whole queue of it)
	elseif k == "back" then
		factoryItem = nil
	end
	refresh()
end

-- the item under a point of a section, with its rect
local function itemAt(side, x, y)
	local r = side == "left" and L.left or L.right
	if not inRect(x, y, r) then
		return nil
	end
	local s = side == "left" and leftScroll or rightScroll
	local cols = side == "left" and 3 or 2
	local cw = side == "left" and L.tile or L.btnW
	local ch = side == "left" and L.tile or L.btnH
	local row = floor((r[4] - y) / (ch + L.gap) + s.pos)
	local col = floor((x - r[1]) / (cw + L.gap))
	if col < 0 or col >= cols then
		return nil
	end
	local items = side == "left" and leftItems or rightItems
	return items[row * cols + col + 1]
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing

local function element(r, color)
	local f = WG.FlowUI and WG.FlowUI.Draw
	if f and f.RectRound then
		local cs = max(2, floor((r[4] - r[2]) * 0.12))
		f.RectRound(r[1], r[2], r[3], r[4], cs, 1, 1, 1, 1, color, color)
	else
		gl.Color(color)
		gl.Rect(r[1], r[2], r[3], r[4])
	end
end

local function outline(r, color, w)
	gl.Color(color)
	gl.Rect(r[1], r[2], r[3], r[2] + w)
	gl.Rect(r[1], r[4] - w, r[3], r[4])
	gl.Rect(r[1], r[2], r[1] + w, r[4])
	gl.Rect(r[3] - w, r[2], r[3], r[4])
	gl.Color(1, 1, 1, 1)
end

local function picture(defID, x0, y0, x1, y1)
	local f = WG.FlowUI and WG.FlowUI.Draw
	if f and f.Unit then
		f.Unit(x0, y0, x1, y1, nil, 1, 1, 1, 1, 0.03, nil, nil, "#" .. defID)
	else
		gl.Color(1, 1, 1, 1)
		gl.Texture("#" .. defID)
		gl.TexRect(x0, y0, x1, y1)
		gl.Texture(false)
	end
end

local function textIn(text, x0, y0, x1, y1, size, color, f)
	f = f or font
	if not f then
		return
	end
	local w = f:GetTextWidth(text) * size
	if w > (x1 - x0) * 0.9 then
		size = size * (x1 - x0) * 0.9 / w
	end
	f:Print((color or "\255\235\235\235") .. text, (x0 + x1) / 2, (y0 + y1) / 2 - size * 0.32, size, "co")
end

local function drawTile(item, r)
	local tileBg = { 0.06, 0.07, 0.08, 0.92 }
	if item.kind == "alltypes" then
		element(r, { 0.16, 0.18, 0.21, 0.95 })
		textIn("ALL", r[1], r[2] + (r[4] - r[2]) * 0.35, r[3], r[4], (r[4] - r[2]) * 0.3, "\255\255\255\255", bold)
		textIn(tostring(item.count), r[1], r[2], r[3], r[2] + (r[4] - r[2]) * 0.4, (r[4] - r[2]) * 0.22, "\255\255\200\064")
		return
	end
	element(r, tileBg)
	local p = max(2, floor((r[3] - r[1]) * 0.03))
	picture(item.defID, r[1] + p, r[2] + p, r[3] - p, r[4] - p)
	local size = (r[4] - r[2]) * 0.17
	if item.kind == "build" then
		local ud = UnitDefs[item.defID]
		if ud then
			font:Print("\255\255\255\255" .. floor(ud.metalCost or 0), r[3] - p * 3, r[2] + p * 3 + size * 1.05, size * 0.85, "ro")
			font:Print("\255\255\240\080" .. floor(ud.energyCost or 0), r[3] - p * 3, r[2] + p * 3, size * 0.85, "ro")
		end
		if item.queued and item.queued > 0 then
			bold:Print("\255\255\255\255" .. item.queued, r[1] + p * 3, r[4] - p * 3 - size * 1.1, size * 1.3, "o")
		end
		if activeBuild() == item.id or factoryItem == item.id then
			outline(r, GOLD, max(2, floor(p * 1.2)))
		end
	else -- a type: its count
		bold:Print("\255\255\255\255" .. #item.units, r[3] - p * 3, r[2] + p * 3, size * 1.3, "ro")
		if multi and multiPicked[item.defID] then
			outline(r, GOLD, max(2, floor(p * 1.2)))
		end
	end
end

local STATE_COLORS = { { 0.3, 0.85, 0.3, 1 }, { 0.95, 0.8, 0.2, 1 }, { 0.9, 0.25, 0.2, 1 } }

local function currentShape()
	local B = WG.bardroidBuildmenu
	if B and B.droidPlace then
		local _, shape = B.droidPlace()
		return shape
	end
end

local function drawButton(item, r)
	local _, activeID = spGetActiveCommand()
	local lit = item.kind == "order" and activeID == item.id
	local bg = { 0.10, 0.11, 0.13, 0.94 }
	if item.kind == "units" and typesFrom == item.from or item.kind == "multi" and multi
		or item.kind == "shape" and currentShape() == item.shape then
		bg = { 0.38, 0.3, 0.04, 0.95 }
	end
	element(r, bg)
	textIn(item.label or "", r[1], r[2], r[3], r[4], (r[4] - r[2]) * 0.34, "\255\240\240\240", bold)
	if item.states and item.states > 1 then -- a state: its bar (green, yellow, red as BAR's)
		local c = STATE_COLORS[min(3, (item.state or 0) + 1)]
		local w = (r[3] - r[1]) * 0.3
		gl.Color(c)
		gl.Rect(r[3] - w - 6, r[2] + 5, r[3] - 6, r[2] + 9)
		gl.Color(1, 1, 1, 1)
	end
	if lit then
		outline(r, GOLD, 3)
	end
end

local function drawSection(side)
	local r = side == "left" and L.left or L.right
	local s = side == "left" and leftScroll or rightScroll
	local items = side == "left" and leftItems or rightItems
	local cols = side == "left" and 3 or 2
	local cw = side == "left" and L.tile or L.btnW
	local ch = side == "left" and L.tile or L.btnH
	gl.Scissor(r[1], r[2], r[3] - r[1], r[4] - r[2])
	local first = floor(s.pos)
	for row = first - 1, first + s.visible + 1 do
		for col = 0, cols - 1 do
			local item = items[row * cols + col + 1]
			if item and row >= 0 then
				local y1 = r[4] - (row - s.pos) * (ch + L.gap)
				local x0 = r[1] + col * (cw + L.gap)
				local rect = { x0, y1 - ch, x0 + cw, y1 }
				if side == "left" then
					drawTile(item, rect)
				else
					drawButton(item, rect)
				end
			end
		end
	end
	gl.Scissor(false)
	-- more rows: a small gold chevron at the edge they come from
	if s.rows > s.visible then
		local cx, w = (r[1] + r[3]) / 2, (r[3] - r[1]) * 0.05
		gl.Color(1, 0.78, 0.25, 0.85)
		if s.pos < snapMax(s) - 0.01 then
			gl.BeginEnd(GL.TRIANGLES, function()
				gl.Vertex(cx - w, r[2] + w * 0.9)
				gl.Vertex(cx + w, r[2] + w * 0.9)
				gl.Vertex(cx, r[2] + 1)
			end)
		end
		if s.pos > 0.01 then
			gl.BeginEnd(GL.TRIANGLES, function()
				gl.Vertex(cx - w, r[4] - w * 0.9)
				gl.Vertex(cx + w, r[4] - w * 0.9)
				gl.Vertex(cx, r[4] - 1)
			end)
		end
		gl.Color(1, 1, 1, 1)
	end
end

-- the place for the build menu copy's PLACE panel: the right section under the shapes' two rows
local function placeRect()
	if not (active and rightKind == "place") then
		return nil
	end
	local top = L.right[4] - 2 * (L.btnH + L.gap) - L.gap
	return { L.right[1], L.right[2], L.right[3], top }
end

-- the PLACE panel as the copy laid it out in placeRect (its rects are what RtsTouch places from): green, brighter once a
-- tap has picked the spot, rotate and cancel inside at the right
local function drawPlace()
	local B = WG.bardroidBuildmenu
	local panel, spot = nil, nil
	if B and B.droidPanel then
		panel, spot = B.droidPanel()
	end
	if not panel then
		return
	end
	local ready = spot ~= nil
	element(panel.all, ready and { 0.12, 0.52, 0.14, 1 } or { 0.1, 0.26, 0.11, 1 })
	local pl = panel.place
	textIn("PLACE", pl[1], pl[2], pl[3], pl[4], (pl[4] - pl[2]) * 0.3, ready and "\255\255\255\255" or "\255\150\190\150", bold)
	for _, k in ipairs({ "rotate", "cancel" }) do
		local r = panel[k]
		element(r, { 0, 0, 0, 0.55 })
		local sym = k == "rotate" and "\226\134\187" or "\226\156\149"
		textIn(sym, r[1], r[2], r[3], r[4], (r[4] - r[2]) * 0.6, k == "rotate" and "\255\235\235\235" or "\255\255\150\140", bold)
	end
	if not ready then
		textIn("tap the map for the spot", pl[1], pl[2], pl[3], pl[2] + (pl[4] - pl[2]) * 0.3, (pl[4] - pl[2]) * 0.1,
			"\255\170\200\170")
	end
end

local function drawSelection()
	local r = L.sel
	element(r, { 0.06, 0.07, 0.08, 0.9 })
	local counts = spGetSelectedUnitsCounts() or {}
	local n = #(spGetSelectedUnits() or {})
	local h = r[4] - r[2]
	if n == 0 then -- nothing picked: the control groups, as pictures
		local groups = Spring.GetGroupList() or {}
		local list = {}
		for g, c in pairs(groups) do
			if c > 0 then
				list[#list + 1] = g
			end
		end
		table.sort(list)
		L.groupRects = {}
		if #list == 0 then
			textIn("No units picked.  Groups: pick units, then hold a number key, or LOCAL / ALL UNITS",
				r[1], r[2], r[3], r[4], h * 0.2, "\255\170\170\170")
			return
		end
		local w = min(h, floor((r[3] - r[1]) / max(1, #list)))
		for i, g in ipairs(list) do
			local x0 = r[1] + (i - 1) * w
			local gr = { x0 + 3, r[2] + 3, x0 + w - 3, r[4] - 3, group = g }
			L.groupRects[#L.groupRects + 1] = gr
			local best, bestN = nil, 0
			for d, c in pairs(Spring.GetGroupUnitsCounts(g) or {}) do
				if c > bestN then
					best, bestN = d, c
				end
			end
			element(gr, { 0.1, 0.11, 0.13, 0.95 })
			if best then
				picture(best, gr[1] + 3, gr[2] + 3, gr[3] - 3, gr[4] - 3)
			end
			bold:Print("\255\255\200\064" .. g, gr[1] + 8, gr[4] - h * 0.3, h * 0.26, "o")
			bold:Print("\255\255\255\255" .. groups[g], gr[3] - 8, gr[2] + 8, h * 0.2, "ro")
		end
		return
	end
	L.groupRects = nil
	local best, bestN = nil, 0
	for d, c in pairs(counts) do
		if d ~= "n" and c > bestN then
			best, bestN = d, c
		end
	end
	if best then
		picture(best, r[1] + 4, r[2] + 4, r[1] + h - 4, r[4] - 4)
		local ud = UnitDefs[best]
		local name = ud and (ud.translatedHumanName or ud.humanName) or ""
		local x = r[1] + h + L.pad
		bold:Print("\255\255\255\255" .. name, x, r[4] - h * 0.36, h * 0.24, "o")
		font:Print("\255\200\200\200" .. (n > 1 and (n .. " units, " .. bestN .. " of them this type") or ""), x,
			r[4] - h * 0.62, h * 0.18, "o")
		local u = (spGetSelectedUnits() or {})[1]
		local hp, maxHp
		if u then
			hp, maxHp = Spring.GetUnitHealth(u)
		end
		if hp and maxHp and maxHp > 0 then
			local x1 = r[3] - L.pad
			local frac = max(0, min(1, hp / maxHp))
			element({ x, r[2] + h * 0.12, x1, r[2] + h * 0.26 }, { 0.15, 0.15, 0.15, 1 })
			element({ x, r[2] + h * 0.12, x + (x1 - x) * frac, r[2] + h * 0.26 },
				{ 1 - frac, 0.25 + 0.55 * frac, 0.2, 1 })
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Callins

local function checkActive()
	local x, y = Spring.GetViewGeometry()
	local was = active
	active = y > x * PORTRAIT and playing()
	if active and (x ~= vsx or y ~= vsy or not was) then
		layout()
		refresh()
	end
	if active ~= was then
		Spring.Echo("[bardroid-portrait] dock " .. (active and "up" or "down") .. string.format(" (%dx%d)", x, y))
	end
end

local refreshAt = 0
local DEBUG, debugAt = true, nil
function widget:Update(dt)
	checkActive()
	if not active then
		return
	end
	snapUpdate(leftScroll, dt)
	snapUpdate(rightScroll, dt)
	local t = now()
	if t >= refreshAt and not press then
		refreshAt = t + 0.25
		refresh()
		if DEBUG and t >= (debugAt or 0) then
			debugAt = t + 1
			local descs = spGetActiveCmdDescs() or {}
			Spring.Echo(string.format("[bardroid-portrait] debug: %d descs, %d left, %d right", #descs, #leftItems, #rightItems))
		end
	end
end

function widget:CommandsChanged()
	if active and not press then
		refresh()
	end
end

function widget:DrawScreen()
	if not active then
		return
	end
	font = WG.fonts and WG.fonts.getFont() or font
	bold = WG.fonts and WG.fonts.getFont(2) or font
	if not font then
		return
	end
	element(L.dock, { 0.03, 0.035, 0.04, 1 })
	font:Begin()
	drawSelection()
	drawSection("left")
	drawSection("right")
	if rightKind == "place" then
		drawPlace()
	end
	font:End()
end

function widget:IsAbove(x, y)
	return active and inRect(x, y, L.dock)
end

function widget:MousePress(x, y, button)
	if not (active and inRect(x, y, L.dock)) then
		return false
	end
	local pr = placeRect()
	if pr and inRect(x, y, pr) then -- the PLACE panel: the build menu copy's (rotate, cancel; PLACE is RtsTouch's)
		local B = WG.bardroidBuildmenu
		if B and B.droidPressPanel then
			B.droidPressPanel(x, y)
		end
		return true
	end
	local side = inRect(x, y, L.left) and "left" or inRect(x, y, L.right) and "right" or nil
	press = { side = side, x = x, y = y, button = button, t = now() }
	if side then
		snapPress(side == "left" and leftScroll or rightScroll, y)
	end
	return true -- (the dock is the dock's: no press goes through to the map under it)
end

function widget:MouseMove(_, y)
	if not press or not press.side then
		return
	end
	local s = press.side == "left" and leftScroll or rightScroll
	local rowH = (press.side == "left" and L.tile or L.btnH) + L.gap
	if snapMove(s, y, rowH, vsx * TAP_SLOP) then
		press.dragged = true
	end
end

function widget:MouseRelease(_, _, button)
	local p = press
	press = nil
	if not p then
		return false
	end
	if p.side then
		local s = p.side == "left" and leftScroll or rightScroll
		if snapRelease(s) or p.dragged then
			return true
		end
		pressItem(itemAt(p.side, p.x, p.y), button == 3)
		return true
	end
	if L.groupRects then -- a control group's picture: those units
		for _, gr in ipairs(L.groupRects) do
			if inRect(p.x, p.y, gr) then
				Spring.SendCommands("group " .. gr.group)
				refresh()
				return true
			end
		end
	end
	return true
end

function widget:ViewResize()
	checkActive()
end

function widget:Initialize()
	WG.BarDroidPortrait = {
		active = function()
			return active
		end,
		dock = function() -- (other widgets keep out of it: x0, y0, x1, y1)
			return active and L.dock or nil
		end,
		placeRect = placeRect, -- (the build menu copy's PLACE panel goes there while a building is picked)
	}
	checkActive()
end

function widget:Shutdown()
	WG.BarDroidPortrait = nil
end
