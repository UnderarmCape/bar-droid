-- BAR Droid portrait dock (Kailil, 2026-11-09: "Lets explore vertical orientation for playing bar ... All the menu ui
-- stuff can be on the bottom portion of the phone. And the game unobstructed shows at the top half"; his pick, layout
-- D: "Lets do D but instead of more orders button ... just have a scroll option ... Cap the buildmenu to 3x4 and have
-- the vertical scroll. If phone has less vertical space, reduce to 3x3 at minimum 3x2. Scroll should be magnetic ...
-- Do not allow scroll to half reveal objects. It should snap the next rows into place"; "I want the UI to look as
-- close as possible to the BAR original still": BAR's own FlowUI panels, buttons and unit tiles).
--
-- While the game's screen is taller than wide (a phone held upright, the unfolded Fold7 held upright: Android leaves
-- the game's orientation to the hand there) the lower part is a dock:
--   top row   the units picked (picture, name, count, health)
--   left      a builder or factory: its build options, 3 wide, 2-4 rows in sight, scrolled by whole rows; units that
--             build nothing: the selection by type (a tap keeps that type); nothing picked, after LOCAL UNITS or ALL
--             UNITS: the combat units by type (a tap picks them; MULTI picks several types)
--   right     the orders, 2 wide, scrolled by whole rows; a building picked: ONE / LINE / GRID / BORDER and the PLACE
--             panel (the build menu copy's, in placeRect); a factory's option pressed: its queue buttons; nothing
--             picked: LOCAL UNITS / ALL UNITS; a box selection being dragged: the unit filters
--   bottom    nothing picked: the control groups as pictures
-- Two modes for fingers (Kailil: the dock as "a camera movement pad ... if I single tap, the ui at the bottom, then I
-- can interact with the ui. It should indicate when its ready to be touched via a quick blink ... if I dont touch the
-- menu after like 5-10seconds, camera panning turns back on"): pad (RtsTouch moves the camera from touches on the dock)
-- and menu (taps press, up and down scroll, a drag on the game box-selects with the dock's filters). The mode and the
-- dock's rects go to RtsTouch in LuaUI/Config/bardroid_dock.txt; its lines come back in the touch log (dockscroll,
-- dockfling, docktap, act dock_menu / dock_select_start / dock_select_end). A mouse or the pad always press directly.
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

-- taller than wide by this much: the dock is up (the unfolded Fold7 upright is 1080x1198, 1.11: at 1.15 it got BAR's
-- landscape HUD squeezed upright, the case the dock is for)
local PORTRAIT = 1.05
local DOCK_MAX = 0.54 -- of the screen's height at most
local MENU_SECONDS = 7 -- the menu goes back to the camera pad after this long untouched (Kailil: "5-10seconds")
local HOME_ROWS = 3 -- nothing picked: the home grid's rows of big buttons
local BLINK = 0.45 -- seconds of the menu's opening pulse
local DOCK_FILE = "LuaUI/Config/bardroid_dock.txt"
local TOUCH_LOG = "LuaUI/Config/bardroid_touch.txt"

---------------------------------------------------------------------------------------------------------------------
-- Rows that scroll by whole rows (Kailil: "Scroll should be magnetic ... A swipe up or down should make the next blocks
-- appear with a small nudge animation ... Do not allow scroll to half reveal objects"). A finger moves them (the app's
-- dockscroll lines, or a mouse drag); on release they settle on whole rows: a quick flick brings the next page, a slow
-- drag the nearest row; the settle overshoots a little and comes back (the nudge). At rest no row is cut.
local SETTLE, OVERSHOOT, FLICK = 0.30, 1.4, 3.0 -- seconds; easeOutBack's overshoot; rows a second for a page

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
		s.pos, s.from, s.to, s.t, s.drag = 0, 0, 0, 1, nil
	elseif s.to > snapMax(s) then
		snapSettle(s, snapMax(s))
	end
end
-- dy: the finger's move, pixels (up is +); rowH: a row's height
local function snapBy(s, dy, rowH)
	if not s.drag then
		s.drag = { pos0 = s.pos, raw = s.pos }
		s.t = 1 -- (a touch holds a settle where it is)
	end
	local d = s.drag
	d.raw = d.raw + dy / rowH -- (a finger moving up brings the rows below into sight)
	local p, hi = d.raw, snapMax(s)
	if p < 0 then
		p = p / 3 -- (past the ends a rubber band, a third as far)
	elseif p > hi then
		p = hi + (p - hi) / 3
	end
	s.pos = p
end
-- vel: the finger's speed at release, rows a second (up is +)
local function snapRelease(s, vel)
	local d = s.drag
	s.drag = nil
	if not d then
		return
	end
	local base = floor(d.pos0 + 0.5)
	if vel > FLICK then
		snapSettle(s, max(base + s.visible, floor(s.pos + 0.5)))
	elseif vel < -FLICK then
		snapSettle(s, min(base - s.visible, floor(s.pos + 0.5)))
	else
		snapSettle(s, floor(s.pos + 0.5))
	end
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
local leftItems, rightItems = {}, {} -- what the two halves show now (tiles, buttons)
local leftKind, rightKind = "", ""
local press -- a mouse press on the dock: { side, x, y, button, lastY, lastT, vel, moved }
local typesFrom -- nil, or "local" / "all" / "idle": a list pressed, those units by type on the left
local multi, multiPicked = false, {}
local cycleAt = {} -- COMMANDER, IDLE BUILDER: the last one each picked (a tap again: the next)
-- Giving and the resource panel (Kailil, 2026-11-09: "a transfer unit ... button to the orders menu ... a teammate
-- selection ui"; a tap on metal or energy: "a drop down that spans the width of the phone" with the conversion (grey)
-- and share (red) sliders and "a send power or send metal button"). Both take the whole grid while open.
local sharing = nil -- "units", "metal" or "energy": the teammate picker
local shareFraction = 0.25 -- of what this team holds (metal, energy)
local resPanel = nil -- "metal" or "energy": its panel
local slide = nil -- a slider being dragged: { item, rect }
local factoryItem -- a factory's build option pressed last: its queue buttons on the right
local lastSelection = ""
local menu = false -- the dock's menu is open (fingers press it); else it is the camera pad
local menuAt, lastTouch = -100, -100 -- when it opened; the last touch on it
local selecting = false -- a box selection being dragged on the game (its filters on the right)
local selFilter = "all" -- the box selection's filter, kept for the next one
local filterAt -- a box selection just ended: the filter goes on when the engine has made it
-- the selection's style (Kailil: "I want to test this using the traditional mouse drag or the controller radial"):
-- "box", BAR's own drag; or "circle", the pad's area selection by finger (from where it came down out to it); kept
local selStyle = "box"
local circle -- the circle being dragged: { x, y, z, r } on the ground

local function inRect(x, y, r)
	return r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end

local dirty = true -- the dock's still parts changed: its texture is drawn again (drawDock)
local function markDirty()
	dirty = true
end

local function myTeam()
	return Spring.GetMyTeamID()
end

local function playing()
	local spec = Spring.GetSpectatingState()
	return not spec
end

local function touched()
	lastTouch = now()
end

---------------------------------------------------------------------------------------------------------------------
-- Layout: the dock's rects for this screen; the build grid 3 wide with 2-4 rows, as many as fit (Kailil: "Cap the
-- buildmenu to 3x4 ... reduce to 3x3 at minimum 3x2"); the dock no taller than it needs, DOCK_MAX at most

local showSel, showGroups = true, true -- the selection row and the groups strip shown (refreshNow decides)
local mobilePicked = false -- units that move are picked (refreshNow): a drag on the game draws their orders (writeDock)
-- the orders a drag draws when armed (BAR's custom formations take them with the right button; another order armed
-- would be cancelled by it)
local DRAW_CMDS = { [CMD.MOVE] = true, [CMD.FIGHT] = true, [CMD.PATROL] = true, [CMD.ATTACK] = true }

local function layout()
	markDirty()
	vsx, vsy = Spring.GetViewGeometry()
	local pad = max(4, floor(vsx * 0.012))
	local gap = max(3, floor(pad * 0.6))
	-- (by the width, and by the height on a near-square screen: the unfolded Fold7 upright, 1080x1198, gave a quarter
	-- of its short dock to these rows and the build grid small tiles beside a blank strip; tall phones keep the width's)
	local selH = floor(min(vsx * 0.15, vsy * 0.09))
	local groupsH = floor(min(vsx * 0.13, vsy * 0.075))
	local half = floor(vsx * 0.5)
	local tile = floor((half - pad - floor(pad / 2) - 2 * gap) / 3)
	local room = floor(vsy * DOCK_MAX) - (pad * 4 + selH + groupsH) -- the grid's height at most
	local rows = max(2, min(4, floor((room + gap) / (tile + gap))))
	if rows * (tile + gap) - gap > room then -- (2 rows that do not fit: smaller tiles)
		tile = max(16, floor((room + gap) / rows) - gap)
	end
	local resH = floor(min(vsx * 0.06, vsy * 0.04))
	room = room - resH - pad
	rows = max(2, min(4, floor((room + gap) / (tile + gap))))
	if rows * (tile + gap) - gap > room then
		tile = max(16, floor((room + gap) / rows) - gap)
	end
	local gridH = rows * (tile + gap) - gap
	L.pad, L.gap, L.tile, L.leftRows = pad, gap, tile, rows
	-- From the bottom: the groups (with groups, or units picked for + NEW), the grid, the selection (units picked),
	-- metal and energy. A row not shown takes no room: the dock is that much lower and the game taller (Kailil,
	-- 2026-11-09: "Remove the no units pick bar ... It should just not be there"); the grid keeps its size.
	local y = pad
	L.groups = { pad, y, vsx - pad, y + groupsH }
	if showGroups then
		y = y + groupsH + pad
	end
	L.left = { pad, y, half - floor(pad / 2), y + gridH }
	L.right = { half + floor(pad / 2), y, vsx - pad, y + gridH }
	y = y + gridH + pad
	L.sel = { pad, y, vsx - pad, y + selH }
	if showSel then
		y = y + selH + pad
	end
	-- metal and energy, at the dock's top (BAR's top bar keeps its wind, units and buttons; its two resource bars are
	-- off while the dock is up: about 1600 pixels wide at a readable size, they ran over its buttons upright)
	L.res = { pad, y, vsx - pad, y + resH }
	L.dock = { 0, 0, vsx, y + resH + pad }
	-- order buttons: 2 wide, rows of about 0.42 of a tile in the same height
	local rw = L.right[3] - L.right[1]
	L.btnW = floor((rw - gap) / 2)
	L.rightRows = max(3, floor((gridH + gap) / (floor(tile * 0.55) + gap))) -- (about 6 mm tall on a phone: thumbs)
	L.btnH = floor((gridH + gap) / L.rightRows) - gap
end

---------------------------------------------------------------------------------------------------------------------
-- RtsTouch's side: the dock's rects and mode (X screen pixels, top left origin), written when they change and every
-- second (RtsTouch takes a file older than 5 s for no dock)

local dockWritten, dockWrittenAt = nil, -10
local dgunLines -- (the D-gun mode's parts for RtsTouch, below)
local function writeDock(force)
	local text
	if active then
		local function r(x)
			return string.format("%d %d %d %d", x[1], vsy - x[4], x[3], vsy - x[2])
		end
		local _, cmd = spGetActiveCommand()
		local draw = DRAW_CMDS[cmd] or (cmd == nil and mobilePicked)
		text = string.format("dock %s %s\nleft %s\nright %s\nselect %s\ndraw %d\n", r(L.dock), menu and "menu" or "pad",
			r(L.left), r(L.right), selStyle, draw and 1 or 0) .. (dgunLines and dgunLines() or "")
	else
		text = "dock none\n"
	end
	local t = now()
	if text == dockWritten and not force and (not active or t - dockWrittenAt < 1) then
		return
	end
	local tmp = DOCK_FILE .. ".tmp"
	local f = io.open(tmp, "w")
	if f then
		f:write(text)
		f:close()
		os.rename(tmp, DOCK_FILE)
	end
	dockWritten, dockWrittenAt = text, t
end

local function setMenu(on)
	if on == menu then
		if on then
			touched()
		end
		return
	end
	menu = on
	if on then
		menuAt = now()
		touched()
	end
	writeDock(true)
end

---------------------------------------------------------------------------------------------------------------------
-- What the halves hold

-- BAR's own words for a command, as its order menu shows them ("commands.<action>" or "commands.<state>"), else nil
local trCache = {}
local function tr(key)
	if trCache[key] == nil then
		local ok, s = pcall(function()
			return BAR and BAR.I18N and BAR.I18N(key)
		end)
		trCache[key] = (ok and type(s) == "string" and s ~= "" and s ~= key and not s:find("commands.", 1, true)) and s or false
	end
	return trCache[key] or nil
end

local function cmdLabel(cmd)
	if cmd.type == CMDTYPE.ICON_MODE and cmd.params and #cmd.params > 1 then
		local state = tonumber(cmd.params[1]) or 0
		local name = cmd.params[state + 2] or cmd.name
		return tr("commands." .. tostring(name)) or name, state, #cmd.params - 1
	end
	return tr("commands." .. tostring(cmd.action)) or cmd.name
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
	for defID in pairs(spGetSelectedUnitsCounts() or {}) do
		local ud = defID ~= "n" and UnitDefs[defID]
		if ud and ud.isFactory then
			return true
		end
	end
	return false
end

-- the unit filters (Kailil: "like the controller mod Hold A and hold x menu to select builders, combat, air, etc.")
local function builder(ud)
	return ud and ud.isBuilder and not ud.isFactory and ud.canMove
end
local function flying(ud)
	return ud and ud.canFly
end
local function naval(ud)
	return ud and ud.canMove and (ud.minWaterDepth or 0) > 0 and not ud.canFly
end
-- combat units: they move, carry a weapon, build nothing and do not fly
local function combat(ud)
	return ud and ud.canMove and not ud.isBuilder and not ud.isFactory and not ud.canFly and ud.weapons and #ud.weapons > 0
end
local FILTERS = {
	{ key = "all", label = "ALL" },
	{ key = "builders", label = "BUILDERS", test = builder },
	{ key = "combat", label = "COMBAT", test = combat },
	{ key = "air", label = "AIR", test = flying },
	{ key = "naval", label = "NAVAL", test = naval },
}

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

-- my units that move and have no orders (not ones still being built)
local function idleUnits()
	local out = {}
	for _, u in ipairs(Spring.GetTeamUnits(myTeam()) or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
		if ud and ud.canMove and not ud.isFactory and not Spring.GetUnitIsBeingBuilt(u)
			and (Spring.GetUnitCommands(u, 0) or 0) == 0 then
			out[#out + 1] = u
		end
	end
	return out
end

local function myCommanders()
	local out = {}
	for _, u in ipairs(Spring.GetTeamUnits(myTeam()) or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
		if ud and ud.customParams and ud.customParams.iscommander then
			out[#out + 1] = u
		end
	end
	return out
end

-- The camera on a point of the map, the point in the middle of the game above the dock: the engine's camera target is
-- the screen's middle, which upright is the dock's top edge (a unit jumped to sat half under it). The shift is where the
-- two middles' rays meet the point's height now (a plane: the ground's ray missed over the void past the map's edge).
local function planeAt(sx, sy, h)
	local px, py, pz = Spring.GetCameraPosition()
	local dx, dy, dz = Spring.GetPixelDir(sx, vsy - sy) -- (its y from the top, as the engine's mouse; ours from the bottom)
	if not (px and dx) or dy > -1e-4 then
		return nil
	end
	local t = (h - py) / dy
	return px + dx * t, pz + dz * t
end
local function cameraTo(x, y, z)
	local cx = floor(vsx / 2)
	local ax, az = planeAt(cx, floor(vsy / 2), y)
	local bx, bz = planeAt(cx, floor((L.dock[4] + vsy) / 2), y)
	if ax and bx then
		x, z = x + ax - bx, z + az - bz
	end
	Spring.SetCameraTarget(x, y, z, 0.25)
end

local function typesUnits()
	if typesFrom == "idle" then
		return idleUnits()
	end
	if typesFrom == "local" then
		return Spring.GetVisibleUnits(myTeam(), nil, false)
	end
	return Spring.GetTeamUnits(myTeam())
end

local function activeBuild()
	local _, cmdID = spGetActiveCommand()
	return cmdID and cmdID < 0 and cmdID or nil
end

-- Before the game starts (an online game's start spot and first buildings): the start unit's build options, as BAR's
-- build menu shows them then, picked through BAR's own pregame queue widget (WG["pregame-build"], as that menu does).
-- The dock stood there with "No units picked" and nothing to queue. Its start unit, nil once the game runs
local function pregameStart()
	if Spring.GetGameFrame() > 0 or Spring.GetSpectatingState() then
		return nil
	end
	local pb = WG["pregame-build"]
	if not (pb and pb.setPreGamestartDefID and pb.getPreGameDefID and pb.getBuildQueue) then
		return nil
	end
	local d = Spring.GetTeamRulesParam(myTeam(), "startUnit")
	return d and UnitDefs[d] and d or nil -- (with no build options too: the faction buttons stay, to pick another)
end

local function pregameItems(startDefID)
	local queued = {}
	for _, b in ipairs(WG["pregame-build"].getBuildQueue() or {}) do
		if type(b) == "table" and type(b[1]) == "number" and b[1] > 0 then
			queued[b[1]] = (queued[b[1]] or 0) + 1
		end
	end
	local items = {}
	for _, d in ipairs(UnitDefs[startDefID].buildOptions or {}) do
		items[#items + 1] = { kind = "pregame", defID = d, queued = queued[d] }
	end
	return items
end

-- BAR's faction picker (gui_factionpicker.lua) sits at the bottom of the screen, under the dock upright: its factions
-- here as buttons, the same choice by the same message ("changeStartUnit", BAR's picker's own; validStartUnits, no
-- RANDOM when one real faction is left, none with one)
local FACTION_NAMES = { arm = "ARMADA", cor = "CORTEX", leg = "LEGION", dum = "RANDOM" }
local function pregameFactions()
	local valid = Spring.GetTeamRulesParam(myTeam(), "validStartUnits") or Spring.GetGameRulesParam("validStartUnits")
	local out = {}
	for s in tostring(valid or ""):gmatch("[^|]+") do
		local d = tonumber(s)
		local ud = d and UnitDefs[d]
		if ud then
			local p = ud.name:sub(1, 3)
			out[#out + 1] = { kind = "faction", startUnit = d, label = FACTION_NAMES[p] or p:upper(), random = p == "dum" }
		end
	end
	if #out == 2 then
		for i = #out, 1, -1 do
			if out[i].random then
				table.remove(out, i)
			end
		end
	end
	return #out > 1 and out or {}
end

local function placeShapes()
	return {
		{ kind = "shape", shape = "one", label = "ONE" }, { kind = "shape", shape = "line", label = "LINE" },
		{ kind = "shape", shape = "grid", label = "GRID" }, { kind = "shape", shape = "border", label = "BORDER" },
	}
end

-- Each item's cell in a half: its row and column and the columns and rows it spans (item.w, item.h, 1 by default),
-- packed in order, each at the first free place: FIGHT across both columns at twice the height, MOVE and PATROL
-- side by side as tall, then the rest (Kailil, 2026-11-09: "fight, and move and maybe patrol needs to be the largest
-- buttons in the orders ui"). Made with the items (refreshNow): cells, rows.
local function pack(items, cols)
	local cells, used, rows = {}, {}, 0
	local function free(r, c, w, h)
		for rr = r, r + h - 1 do
			for cc = c, c + w - 1 do
				if cc >= cols or used[rr * cols + cc] then
					return false
				end
			end
		end
		return true
	end
	local r, c = 0, 0
	for i, it in ipairs(items) do
		local w, h = min(cols, it.w or 1), it.h or 1
		while not free(r, c, w, h) do
			c = c + 1
			if c >= cols then
				c, r = 0, r + 1
			end
		end
		for rr = r, r + h - 1 do
			for cc = c, c + w - 1 do
				used[rr * cols + cc] = true
			end
		end
		cells[i] = { row = r, col = c, w = w, h = h }
		rows = max(rows, r + h)
	end
	return cells, rows
end
local cellsOf = { left = {}, right = {} }

-- The pad's D-gun mode (bardroid_pad.lua, v0.8.5's) on the dock (Kailil, 2026-11-09: "two joy sticks appear and a big
-- red fire button for the dgun. Then an in the corner ... to cancel the dgun control"): MOVE (left) walks the
-- commander, AIM (right) turns the shot, FIRE fires, the corner's cross leaves. RtsTouch reads them from the dock's
-- file (writeDock) and sends the sticks back (dgunsticks); the mode does the rest as with a pad.
local dgunStick = { 0, 0, 0, 0 } -- lx, ly, rx, ry as RtsTouch sent them (the knobs)
local function dgunOn()
	local D = WG.BarDroidPadDgun
	return D and D.active and D.active() or false
end

-- its parts in the grid: the sticks (x, y, radius), FIRE and the cancel corner (rects); GL pixels
local function dgunParts()
	local r = { L.left[1], L.left[2], L.right[3], L.right[4] }
	local w, h = r[3] - r[1], r[4] - r[2]
	local rad = floor(min(w * 0.2, h * 0.34))
	local cy = r[2] + floor(h * 0.42)
	local fire = { r[1] + floor(w * 0.3), r[2] + floor(h * 0.74), r[3] - floor(w * 0.3), r[4] - L.gap }
	local c = floor(min(w * 0.13, h * 0.2))
	return { l = { r[1] + floor(w * 0.24), cy, rad }, r = { r[3] - floor(w * 0.24), cy, rad }, fire = fire,
		cancel = { r[1], r[4] - c, r[1] + c, r[4] } }
end

-- (X pixels, top left origin, as the dock's other lines)
dgunLines = function()
	if rightKind ~= "dgun" then
		return ""
	end
	local p = dgunParts()
	local function rect(x)
		return string.format("%d %d %d %d", x[1], vsy - x[4], x[3], vsy - x[2])
	end
	return string.format("dgun 1\nstickl %d %d %d\nstickr %d %d %d\nfire %s\ncancel %s\n", p.l[1], vsy - p.l[2], p.l[3],
		p.r[1], vsy - p.r[2], p.r[3], rect(p.fire), rect(p.cancel))
end

local function teammateList()
	local P = WG.BarDroidPad
	return P and P.teammates and P.teammates() or {}
end

-- the teammate picker: amounts (resources), the teammates in their colours, CANCEL
local function shareItems()
	local items = {}
	if sharing ~= "units" then
		for _, f in ipairs({ 0.1, 0.25, 0.5, 1 }) do
			items[#items + 1] = { kind = "sharestep", value = f, label = floor(f * 100) .. "%" }
		end
	end
	local teams = teammateList()
	for _, t in ipairs(teams) do
		items[#items + 1] = { kind = "shareto", teamID = t.teamID, label = string.upper(t.name), color = t.color, w = 2 }
	end
	if #teams == 0 then
		items[#items + 1] = { kind = "none", label = "NO TEAMMATES", w = 2 }
	end
	items[#items + 1] = { kind = "sharecancel", label = "CANCEL", w = 2 }
	return items
end

-- the resource panel: BAR's top bar's sliders (energy: conversion, grey; both: sharing above, red), SEND, CLOSE
local function panelItems(res)
	local items = {}
	if res == "energy" then
		items[#items + 1] = { kind = "slider", what = "convert", res = res, label = "CONVERT ENERGY ABOVE", w = 2 }
	end
	items[#items + 1] = { kind = "slider", what = "share", res = res, label = "SHARE TO ALLIES ABOVE", w = 2 }
	if #teammateList() > 0 then
		items[#items + 1] = { kind = "sendres", res = res, label = res == "metal" and "SEND METAL" or "SEND ENERGY", w = 2 }
	end
	items[#items + 1] = { kind = "panelclose", label = "CLOSE", w = 2 }
	return items
end

local function sliderValue(item)
	if item.what == "convert" then
		return Spring.GetTeamRulesParam(myTeam(), "mmLevel") or 0.75
	end
	return select(6, Spring.GetTeamResources(myTeam(), item.res)) or 1
end

-- a slider set from x across its track (BAR's own calls: SetShareLevel; conversion, its LuaRules message 12-88 %)
local function setSlider(item, r, x)
	local v = max(0, min(1, (x - r[1]) / max(1, r[3] - r[1])))
	if item.what == "convert" then
		Spring.SendLuaRulesMsg(string.format(string.char(137) .. "%i", max(12, min(88, floor(v * 100 + 0.5)))))
	else
		Spring.SetShareLevel(item.res, v)
	end
	markDirty()
end

local refreshN, refreshMs = 0, 0 -- (the profile's: refreshes and their time)

-- what each half shows, refreshed a few times a second and after every press
local refreshNow
local function refresh()
	local t0 = spGetTimer()
	refreshNow()
	refreshN, refreshMs = refreshN + 1, refreshMs + spDiffTimers(spGetTimer(), t0) * 1000
end
function refreshNow()
	local sel = spGetSelectedUnits() or {}
	local builds, orders = readCommands()
	-- (units picked and no command at all: the engine's list for a frame after a press or a pick, before it is made
	-- again; taken as it was, it threw the build menu back to its first rows after each factory press)
	if #sel > 0 and #builds == 0 and #orders == 0 and not typesFrom and not selecting then
		return
	end
	local anyGroup = false
	for _, c in pairs(Spring.GetGroupList() or {}) do
		if c > 0 then
			anyGroup = true
			break
		end
	end
	mobilePicked = false
	for d in pairs(spGetSelectedUnitsCounts() or {}) do
		local ud = type(d) == "number" and UnitDefs[d]
		if ud and ud.canMove and not ud.isFactory then
			mobilePicked = true
			break
		end
	end
	if (#sel > 0) ~= showSel or (#sel > 0 or anyGroup) ~= showGroups then -- (the dock's rows: laid out again)
		showSel, showGroups = #sel > 0, #sel > 0 or anyGroup
		layout()
	end
	local key = #sel .. ":" .. tostring(sel[1])
	local newPick = key ~= lastSelection -- (another pick: both halves from their first rows, not the last unit's place)
	if newPick then
		lastSelection, factoryItem = key, nil
		if sharing == "units" then -- (another pick: not what TRANSFER was pressed for)
			sharing = nil
		end
		if #sel > 0 and not multi then
			typesFrom = nil
		end
	end
	local newLeft, newRight, lk, rk
	local pregame = #sel == 0 and not typesFrom and pregameStart()
	if pregame then
		newLeft, lk = pregameItems(pregame), "pregame"
	elseif typesFrom then -- LOCAL / ALL UNITS: the combat units by type, ALL first (IDLE: every idle unit)
		local types = byType(typesUnits(), typesFrom ~= "idle" and combat or nil)
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
	local style = { kind = "style", label = selStyle == "circle" and "SELECT: CIRCLE" or "SELECT: BOX" }
	if selecting then -- a selection being dragged: its filters (a second finger on the dock picks one)
		newRight = {}
		for _, f in ipairs(FILTERS) do
			newRight[#newRight + 1] = { kind = "filter", key = f.key, label = f.label }
		end
		rk = "filters"
	elseif pregame and WG["pregame-build"].getPreGameDefID() then -- a building picked: its shapes and PLACE, as in
		-- the game (the build menu copy places pregame buildings too: a map tap picks the spot, PLACE's Shift click
		-- adds it to BAR's queue)
		newRight, rk = placeShapes(), "place"
	elseif pregame then -- (the queue on the map, BAR's: its last one off, or all of it; the factions)
		newRight = { { kind = "pregameundo", label = "UNDO LAST" }, { kind = "pregameclear", label = "CLEAR QUEUE" } }
		for _, f in ipairs(pregameFactions()) do
			newRight[#newRight + 1] = f
		end
		rk = "pregame"
	elseif typesFrom then -- a list on the left: the lists, MULTI and DONE
		newRight = {
			{ kind = "units", from = "local", label = "LOCAL UNITS" },
			{ kind = "units", from = "all", label = "ALL UNITS" },
			{ kind = "units", from = "idle", label = "IDLE UNITS" },
			{ kind = "multi", label = multi and "MULTI: ON" or "MULTI" },
			{ kind = "done", label = "DONE" },
		}
		rk = "units"
	elseif #sel == 0 then -- nothing picked: the home grid, big buttons across the dock (Kailil, 2026-11-09: idle
		-- units, the commander with the camera on it, the camera to the base)
		newRight = {
			{ kind = "units", from = "local", label = "LOCAL UNITS" },
			{ kind = "units", from = "all", label = "ALL UNITS" },
			{ kind = "units", from = "idle", label = "IDLE UNITS" },
			{ kind = "idlebuilder", label = "IDLE BUILDER" },
			{ kind = "commander", label = "COMMANDER" },
			{ kind = "base", label = "BASE" },
		}
		rk = "home"
	elseif building and not selectedFactory() then -- a building picked: its shapes, and PLACE under them (the build
		-- menu copy's panel, in placeRect: RtsTouch places from its rects, bardroid_place.txt)
		newRight, rk = placeShapes(), "place"
	elseif factoryItem then -- a factory's item pressed: its queue
		newRight = {
			{ kind = "queue", n = 1, label = "+1" }, { kind = "queue", n = 5, label = "+5" },
			{ kind = "queue", n = 20, label = "+20" }, { kind = "queue", n = -1, label = "-1" },
			{ kind = "clearitem", label = "CLEAR" }, { kind = "back", label = "ORDERS" },
		}
		rk = "factory"
	else -- (the box or circle and its filter after the orders: with units picked only, Kailil 2026-11-09)
		newRight, rk = orders, "orders"
		if mobilePicked then -- (units that move picked: FIGHT, MOVE, PATROL first and largest, pack)
			-- (and a commander's D-gun across after them: its touch sticks, k == "order" with CMD.MANUALFIRE)
			local big = { [CMD.FIGHT] = { 1, 2, 2 }, [CMD.MOVE] = { 2, 1, 2 }, [CMD.PATROL] = { 3, 1, 2 },
				[CMD.MANUALFIRE] = { 4, 2, 1 } }
			local first, rest = {}, {}
			for _, it in ipairs(orders) do
				local b = it.kind == "order" and big[it.id]
				if b then
					it.w, it.h = b[2], b[3]
					first[b[1]] = it
				else
					rest[#rest + 1] = it
				end
			end
			newRight = {}
			for i = 1, 4 do
				if first[i] then
					newRight[#newRight + 1] = first[i]
				end
			end
			for _, it in ipairs(rest) do
				newRight[#newRight + 1] = it
			end
		end
		if #teammateList() > 0 then -- (after FIGHT, MOVE, PATROL: the picked units to a teammate)
			local at = 1
			while newRight[at] and newRight[at].h do
				at = at + 1
			end
			table.insert(newRight, at, { kind = "transfer", label = "TRANSFER" })
		end
		newRight[#newRight + 1] = style
		newRight[#newRight + 1] = { kind = "filterpick", label = "FILTER: " .. selFilter:upper() }
	end
	if sharing or resPanel then -- (the picker or the panel: the whole grid)
		newLeft, lk = {}, sharing and "share" or "panel"
		newRight, rk = sharing and shareItems() or panelItems(resPanel), lk
	end
	if dgunOn() then -- (the D-gun mode: its sticks, FIRE and cancel over the whole grid)
		newLeft, lk, newRight, rk = {}, "dgun", {}, "dgun"
	end
	leftItems, rightItems = newLeft, newRight
	markDirty()
	local leftRowsN, rightRowsN
	cellsOf.left, leftRowsN = pack(leftItems, 3)
	cellsOf.right, rightRowsN = pack(rightItems, 2)
	snapSet(leftScroll, leftRowsN, L.leftRows or 2, lk == leftKind and not newPick)
	local wideRows = max(1, floor((L.left[4] - L.left[2] + L.gap) / (floor(L.btnH * 1.5) + L.gap)))
	snapSet(rightScroll, rightRowsN, rk == "home" and HOME_ROWS or (rk == "share" or rk == "panel") and wideRows
		or L.rightRows or 3, rk == rightKind and not newPick)
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

-- the units the filter keeps (an "all" keeps them all)
local function filtered(units)
	local f
	for _, x in ipairs(FILTERS) do
		if x.key == selFilter then
			f = x
		end
	end
	if not (f and f.test) then
		return units
	end
	local keep = {}
	for _, u in ipairs(units or {}) do
		if f.test(UnitDefs[Spring.GetUnitDefID(u) or -1]) then
			keep[#keep + 1] = u
		end
	end
	return keep
end

-- the box selection's filter on what the engine selected
local function applyFilter()
	if selFilter ~= "all" then
		selectUnits(filtered(spGetSelectedUnits() or {}))
	end
end

-- the circle's units: my team's within it on the ground, through the filter
local function pickCircle()
	local c = circle
	circle = nil
	if not (c and c.r > 0) then
		return
	end
	selectUnits(filtered(Spring.GetUnitsInCylinder(c.x, c.z, c.r, myTeam()) or {}))
end

-- a "dockcircle x y r" line (X screen pixels, top left origin): its middle and edge on the ground
local function circleTo(x, y, r)
	local gy = vsy - y
	local _, a = Spring.TraceScreenRay(x, gy, true)
	if not a then
		return
	end
	local _, b = Spring.TraceScreenRay(min(vsx - 1, x + max(1, r)), gy, true)
	local wr = b and math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2) or 0
	circle = { x = a[1], y = a[2], z = a[3], r = wr }
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
	elseif k == "order" and item.id == CMD.MANUALFIRE and not long and WG.BarDroidPad and WG.BarDroidPad.act then
		WG.BarDroidPad.act("dgun") -- (the pad's D-gun mode, its sticks on the dock: dgunOn)
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
	elseif k == "filter" then
		selFilter = item.key
	elseif k == "style" then
		selStyle = selStyle == "box" and "circle" or "box"
		writeDock(true)
	elseif k == "filterpick" then -- (nothing picked: the next filter for the next selection, round the list)
		for i, f in ipairs(FILTERS) do
			if f.key == selFilter then
				selFilter = FILTERS[i % #FILTERS + 1].key
				break
			end
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
	elseif k == "commander" or k == "idlebuilder" then -- the next one picked and the camera on it (again: the next)
		local list = k == "commander" and myCommanders() or {}
		if k == "idlebuilder" then
			for _, u in ipairs(idleUnits()) do
				local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
				if ud and ud.isBuilder then
					list[#list + 1] = u
				end
			end
		end
		if #list > 0 then
			cycleAt[k] = (cycleAt[k] or 0) % #list + 1
			local u = list[cycleAt[k]]
			selectUnits({ u })
			local x, y, z = Spring.GetUnitPosition(u)
			if x then
				cameraTo(x, y, z)
			end
		end
	elseif k == "base" then -- the camera where the commander began (the start spot)
		local x, y, z = Spring.GetTeamStartPosition(myTeam())
		if x and (x > 0 or z > 0) then
			cameraTo(x, y, z)
		end
	elseif k == "transfer" then
		sharing = "units"
	elseif k == "sendres" then
		sharing, resPanel = item.res, nil
	elseif k == "sharestep" then
		shareFraction = item.value
	elseif k == "shareto" then
		local P = WG.BarDroidPad
		if P and P.give then
			P.give(item.teamID, sharing, shareFraction)
		end
		sharing = nil
	elseif k == "sharecancel" then
		sharing = nil
	elseif k == "panelclose" then
		resPanel = nil
	elseif k == "faction" and Spring.GetGameFrame() == 0 then
		Spring.SendLuaRulesMsg("changeStartUnit" .. tostring(item.startUnit))
	elseif k == "pregame" or k == "pregameundo" or k == "pregameclear" then
		local pb = WG["pregame-build"]
		if pb then
			if k == "pregame" then -- (a second tap puts it away; so does PLACE's cancel)
				pb.setPreGamestartDefID(pb.getPreGameDefID() ~= item.defID and item.defID or nil)
			elseif k == "pregameundo" then -- (as BAR's right click there: the last one off)
				local q = pb.getBuildQueue()
				if q and #q > 0 then
					table.remove(q)
				end
			elseif pb.setBuildQueue then
				pb.setBuildQueue({})
			end
			if pb.forceRefresh then
				pb.forceRefresh()
			end
		end
	end
	refresh()
end

-- Nothing picked ("home"): the right half's buttons across both halves, 2 wide and HOME_ROWS tall (Kailil,
-- 2026-11-09: "much larger buttons ... Only buttons should be there")
local function homeRect()
	return { L.left[1], L.left[2], L.right[3], L.right[4] }
end

-- a half's geometry: its rect, scroll, items, columns, cell width and height
local function half(side)
	if side == "left" then
		return L.left, leftScroll, leftItems, 3, L.tile, L.tile
	end
	if rightKind == "home" or rightKind == "share" or rightKind == "panel" then -- (the whole grid)
		local r = homeRect()
		return r, rightScroll, rightItems, 2, floor((r[3] - r[1] - L.gap) / 2),
			rightKind == "home" and floor((r[4] - r[2] + L.gap) / HOME_ROWS) - L.gap or floor(L.btnH * 1.5)
	end
	return L.right, rightScroll, rightItems, 2, L.btnW, L.btnH
end

-- an item's rect in its half as the rows stand scrolled (pack)
local function cellRect(side, i)
	local r, s, _, _, cw, ch = half(side)
	local c = cellsOf[side][i]
	if not c then
		return nil
	end
	local y1 = r[4] - (c.row - s.pos) * (ch + L.gap)
	local x0 = r[1] + c.col * (cw + L.gap)
	return { x0, y1 - (c.h * ch + (c.h - 1) * L.gap), x0 + c.w * cw + (c.w - 1) * L.gap, y1 }
end

-- the item under a point of a half
local function itemAt(side, x, y)
	local r, s, items, cols, cw, ch = half(side)
	if not inRect(x, y, r) then
		return nil
	end
	if side == "right" then -- (packed: the cell that holds the point)
		for i, it in ipairs(items) do
			local cr = cellRect(side, i)
			if cr and inRect(x, y, cr) then
				return it
			end
		end
		return nil
	end
	local row = floor((r[4] - y) / (ch + L.gap) + s.pos)
	local col = floor((x - r[1]) / (cw + L.gap))
	if col < 0 or col >= cols then
		return nil
	end
	return items[row * cols + col + 1]
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing: BAR's own FlowUI (gui_flowui.lua): Element for panels, Button for buttons, Unit for unit tiles, Selector for
-- the one in use (Kailil: "as close as possible to the BAR original")

local function flow()
	return WG.FlowUI and WG.FlowUI.Draw
end

-- opaque: the dock itself (BAR's panels show the game through; the dock covers the menus and lists under it)
local function panel(r, ctl, ctr, cbr, cbl, opaque)
	local f = flow()
	if f and f.Element then
		f.Element(r[1], r[2], r[3], r[4], ctl or 1, ctr or 1, cbr or 1, cbl or 1, nil, nil, nil, nil, nil, nil, nil, nil, opaque)
	else
		gl.Color(0.04, 0.04, 0.04, opaque and 1 or 0.8)
		gl.Rect(r[1], r[2], r[3], r[4])
	end
	gl.Color(1, 1, 1, 1) -- (a unit picture right after an Element came out dark: the state it leaves)
	gl.Texture(false)
end

-- (a unit picture drawn right after a FlowUI button or selector came out dark: the state they leave)
local function resetGL()
	gl.Color(1, 1, 1, 1)
	gl.Texture(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
end

local function button(r, c1, c2)
	local f = flow()
	if f and f.Button then
		f.Button(r[1], r[2], r[3], r[4], 1, 1, 1, 1, 1, 1, 1, 1, nil, c1, c2, max(1, floor(L.pad * 0.35)))
	else
		gl.Color(c1 or { 0.15, 0.15, 0.15, 0.9 })
		gl.Rect(r[1], r[2], r[3], r[4])
	end
	resetGL()
end

local function selector(r)
	local f = flow()
	if f and f.Selector then
		f.Selector(r[1], r[2], r[3], r[4])
	end
	resetGL()
end

-- in use: as BAR's build menu shows its picked cell (gui_buildmenu.lua drawCell): the picture closer, gold light over it
local function unitTile(defID, r, inUse)
	local f = flow()
	local cs = max(2, floor((r[3] - r[1]) * 0.06))
	if f and f.Unit then
		local zoom = inUse and 0.135 or 0.04
		f.Unit(r[1], r[2], r[3], r[4], cs, 1, 1, 1, 1, zoom, nil, nil, "#" .. defID)
		if inUse then
			gl.Blending(GL.SRC_ALPHA, GL.ONE)
			gl.Color(1, 0.85, 0.2, 0.25)
			gl.Texture("#" .. defID)
			f.Unit(r[1], r[2], r[3], r[4], cs, 1, 1, 1, 1, zoom)
			gl.Texture(false)
			gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
		end
	else
		gl.Texture("#" .. defID)
		gl.TexRect(r[1], r[2], r[3], r[4])
		gl.Texture(false)
	end
	gl.Color(1, 1, 1, 1)
end

local function textIn(text, x0, y0, x1, y1, size, color, f)
	f = f or font
	if not f then
		return
	end
	local w = f:GetTextWidth(text) * size
	if w > (x1 - x0) * 0.88 then
		size = size * (x1 - x0) * 0.88 / w
	end
	f:Print((color or "\255\235\235\235") .. text, (x0 + x1) / 2, (y0 + y1) / 2 - size * 0.32, size, "co")
end

local function drawTile(item, r)
	local w, h = r[3] - r[1], r[4] - r[2]
	if item.kind == "alltypes" then
		button(r, { 0.2, 0.2, 0.2, 0.8 }, { 0.35, 0.35, 0.35, 0.8 })
		textIn("ALL", r[1], r[2] + h * 0.38, r[3], r[4], h * 0.26, "\255\255\255\255", bold)
		textIn(tostring(item.count), r[1], r[2], r[3], r[2] + h * 0.42, h * 0.2, "\255\255\200\064")
		return
	end
	-- (a pregame option picked: lit as BAR's menu lights its picked cell)
	local pb = item.kind == "pregame" and WG["pregame-build"]
	unitTile(item.defID, r, pb and pb.getPreGameDefID and pb.getPreGameDefID() == item.defID or false)
	local p, size = max(2, floor(w * 0.05)), h * 0.15
	if item.kind == "build" or item.kind == "pregame" then -- (as BAR's build menu: metal white, energy yellow, bottom right)
		local ud = UnitDefs[item.defID]
		if ud then
			font:Print("\255\245\245\245" .. floor(ud.metalCost or 0), r[3] - p, r[2] + p + size * 1.05, size, "ro")
			font:Print("\255\255\255\000" .. floor(ud.energyCost or 0), r[3] - p, r[2] + p, size, "ro")
		end
		if item.queued and item.queued > 0 then
			bold:Print("\255\255\255\255" .. item.queued, r[1] + p * 1.5, r[4] - p - size * 1.5, size * 1.5, "o")
		end
		if item.id and (activeBuild() == item.id or factoryItem == item.id) then
			selector(r)
		end
	else -- a type: its count
		bold:Print("\255\255\255\255" .. #item.units, r[3] - p, r[2] + p, size * 1.4, "ro")
		if multi and multiPicked[item.defID] then
			selector(r)
		end
	end
end

-- BAR's order menu's state lights: green, yellow, red by the state
local STATE_COLORS = { { 0.3, 0.85, 0.3, 1 }, { 0.95, 0.8, 0.2, 1 }, { 0.9, 0.25, 0.2, 1 } }

local function currentShape()
	local B = WG.bardroidBuildmenu
	if B and B.droidPlace then
		local _, shape = B.droidPlace()
		return shape
	end
end

local function drawSlider(item, r)
	button(r)
	local v = sliderValue(item)
	local h = r[4] - r[2]
	local tx0, tx1 = r[1] + h * 0.2, r[3] - h * 0.2
	local ty0 = r[2] + h * 0.2
	local ty1 = ty0 + max(4, floor(h * 0.16))
	gl.Color(0.08, 0.08, 0.08, 0.95)
	gl.Rect(tx0, ty0, tx1, ty1)
	if item.what == "convert" then -- (BAR's top bar: the conversion grey, the share red)
		gl.Color(0.72, 0.72, 0.72, 1)
	else
		gl.Color(0.86, 0.2, 0.18, 1)
	end
	local kx = tx0 + (tx1 - tx0) * v
	gl.Rect(tx0, ty0, kx, ty1)
	gl.Color(1, 1, 1, 1)
	gl.Rect(kx - 3, ty0 - h * 0.07, kx + 3, ty1 + h * 0.07)
	textIn(item.label .. "  " .. floor(v * 100 + 0.5) .. "%", r[1], ty1, r[3], r[4], h * 0.24, "\255\235\235\235", font)
end

local function drawButton(item, r)
	if item.kind == "slider" then
		drawSlider(item, r)
		return
	end
	local _, activeID = spGetActiveCommand()
	local lit = item.kind == "order" and activeID == item.id
	local on = item.kind == "units" and typesFrom == item.from or item.kind == "multi" and multi
		or item.kind == "shape" and currentShape() == item.shape or item.kind == "filter" and selFilter == item.key
		or item.kind == "faction" and Spring.GetTeamRulesParam(myTeam(), "startUnit") == item.startUnit
		or item.kind == "sharestep" and shareFraction == item.value
	if on then -- (picked: BAR's gold)
		button(r, { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 })
	else
		button(r)
	end
	-- (the home grid's tall buttons: their words a little larger than the order buttons', not by their height)
	textIn(item.label or "", r[1], r[2], r[3], r[4], min((r[4] - r[2]) * 0.34, L.btnH * ((item.h or 1) > 1 and 0.6 or 0.46)),
		item.kind == "none" and "\255\140\140\140" or "\255\240\240\240", font)
	if item.color then -- a teammate: their colour along the bottom
		gl.Color(item.color[1], item.color[2], item.color[3], 0.95)
		gl.Rect(r[1] + 8, r[2] + 5, r[3] - 8, r[2] + max(5, (r[4] - r[2]) * 0.09))
		gl.Color(1, 1, 1, 1)
	end
	if item.states and item.states > 1 then -- a state: its light along the bottom, as BAR's
		local c = STATE_COLORS[min(3, (item.state or 0) + 1)]
		local w = (r[3] - r[1]) * 0.28
		local y = r[2] + max(3, (r[4] - r[2]) * 0.1)
		gl.Color(c)
		gl.Rect(r[3] - w - 6, y, r[3] - 6, y + max(2, (r[4] - r[2]) * 0.06))
		gl.Color(1, 1, 1, 1)
	end
	if lit then
		selector(r)
	end
end

local function drawHalf(side)
	local r, s, items = half(side)
	gl.Scissor(r[1], r[2], r[3] - r[1], r[4] - r[2])
	for i, item in ipairs(items) do
		local rect = cellRect(side, i)
		if rect and rect[2] < r[4] and rect[4] > r[2] then -- (in sight)
			if side == "left" then
				drawTile(item, rect)
			else
				drawButton(item, rect)
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

-- the place for the build menu copy's PLACE panel: the right half under the shapes' two rows
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
	local p, spot = nil, nil
	if B and B.droidPanel then
		p, spot = B.droidPanel()
	end
	if not p then
		return
	end
	local ready = spot ~= nil
	button(p.all, ready and { 0.1, 0.5, 0.1, 1 } or { 0.1, 0.25, 0.1, 1 },
		ready and { 0.25, 0.8, 0.25, 1 } or { 0.2, 0.35, 0.2, 1 })
	local pl = p.place
	textIn("PLACE", pl[1], pl[2], pl[3], pl[4], (pl[4] - pl[2]) * 0.3, ready and "\255\255\255\255" or "\255\205\225\205", bold)
	for _, k in ipairs({ "rotate", "cancel" }) do
		local r = p[k]
		button(r, { 0, 0, 0, 0.55 }, { 0.15, 0.15, 0.15, 0.6 })
		local sym = k == "rotate" and "\226\134\187" or "\226\156\149"
		textIn(sym, r[1], r[2], r[3], r[4], (r[4] - r[2]) * 0.6, k == "rotate" and "\255\235\235\235" or "\255\255\150\140", bold)
	end
	if not ready then
		-- under rotate and cancel across the panel when it is tall enough (squeezed under the PLACE label it came out
		-- tiny), at the size of the dock's other hints; a short panel keeps it under the label
		local size = (L.groups[4] - L.groups[2]) * 0.24
		local below = p.rotate[2] - p.all[2]
		if below >= size * 2.2 then
			textIn("tap the map for the spot", p.all[1], p.all[2], p.all[3], p.rotate[2], size, "\255\185\215\185")
		else
			textIn("tap the map for the spot", pl[1], pl[2], pl[3], pl[2] + (pl[4] - pl[2]) * 0.32, (pl[4] - pl[2]) * 0.14,
				"\255\185\215\185")
		end
	end
end

local function drawSelection()
	local r = L.sel
	panel(r)
	local counts = spGetSelectedUnitsCounts() or {}
	local sel = spGetSelectedUnits() or {}
	local n = #sel
	local h = r[4] - r[2]
	local p = floor(h * 0.08)
	if n == 0 then
		-- (before the game: what to do there, the start spot first; BAR's position reads 0,0 until one is picked)
		local sx, _, sz = Spring.GetTeamStartPosition(myTeam())
		local pregameText = pregameStart() and ((sx or 0) <= 0 and (sz or 0) <= 0
			and "START SPOT:  tap the map for yours" or "Start spot picked: queue buildings, then Ready")
		textIn(selecting and ((selStyle == "circle" and "CIRCLE" or "BOX") .. " SELECTION:  a second finger picks a filter")
			or pregameText or "No units picked",
			r[1], r[2] + h * 0.3, r[3], r[4], h * 0.2, "\255\175\175\175") -- (above the camera pad's hint, drawMode)
		return
	end
	local best, bestN = nil, 0
	for d, c in pairs(counts) do
		if d ~= "n" and c > bestN then
			best, bestN = d, c
		end
	end
	if not best then
		return
	end
	unitTile(best, { r[1] + p, r[2] + p, r[1] + h - p, r[4] - p })
	local ud = UnitDefs[best]
	local name = ud and (ud.translatedHumanName or ud.humanName) or ""
	local x = r[1] + h + L.pad
	bold:Print("\255\255\255\255" .. name, x, r[4] - h * 0.36, h * 0.24, "o")
	if n > 1 then
		font:Print("\255\200\200\200" .. n .. " units, " .. bestN .. " of this type", x, r[4] - h * 0.62, h * 0.17, "o")
	end
	local hp, maxHp = Spring.GetUnitHealth(sel[1])
	if hp and maxHp and maxHp > 0 then
		local x1 = r[3] - L.pad
		local frac = max(0, min(1, hp / maxHp))
		gl.Color(0.12, 0.12, 0.12, 0.9)
		gl.Rect(x, r[2] + h * 0.13, x1, r[2] + h * 0.25)
		gl.Color(1 - frac, 0.3 + 0.55 * frac, 0.2, 1)
		gl.Rect(x, r[2] + h * 0.13, x + (x1 - x) * frac, r[2] + h * 0.25)
		gl.Color(1, 1, 1, 1)
	end
end

-- metal and energy as BAR's top bar shows them: a bar filled to the storage, the amount and storage, income in green and
-- spending in red
local function short(v)
	v = floor(v + 0.5)
	return v >= 10000 and string.format("%.1fk", v / 1000) or tostring(v)
end
local function drawResources()
	local r = L.res
	local w = floor((r[3] - r[1] - L.pad) / 2)
	local h = r[4] - r[2]
	for i, res in ipairs({ "metal", "energy" }) do
		local cur, storage, _, income, expense = Spring.GetTeamResources(myTeam(), res)
		local x0 = r[1] + (i - 1) * (w + L.pad)
		local box = { x0, r[2], x0 + w, r[4] }
		panel(box)
		if cur and storage then
			local pad = max(2, floor(h * 0.12))
			local bx0, bx1 = x0 + floor(w * 0.3), x0 + w - pad
			local by0, by1 = r[2] + pad, r[2] + pad + max(3, floor(h * 0.2))
			local frac = storage > 0 and max(0, min(1, cur / storage)) or 0
			gl.Color(0.1, 0.1, 0.1, 0.9)
			gl.Rect(bx0, by0, bx1, by1)
			if res == "metal" then
				gl.Color(0.85, 0.85, 0.85, 1)
			else
				gl.Color(1, 0.86, 0.15, 1)
			end
			gl.Rect(bx0, by0, bx0 + (bx1 - bx0) * frac, by1)
			gl.Color(1, 1, 1, 1)
			local size = h * 0.34
			local ty = r[4] - pad - size * 0.95
			bold:Print((res == "metal" and "\255\225\225\225" or "\255\255\230\080") .. short(cur), x0 + pad * 1.5,
				ty, size * 1.15, "o")
			font:Print("\255\160\160\160" .. short(storage), bx1, ty, size * 0.8, "ro")
			if res == "energy" and (Game.windMax or 1) > 0 then -- (the wind, as BAR's top bar gave it: off upright)
				local wind = "\255\150\150\150wind \255\220\220\220" .. string.format("%.1f", select(4, Spring.GetWind()) or 0)
				local sw = font:GetTextWidth(short(storage)) * size * 0.8
				font:Print(wind, bx1 - sw - pad * 2, ty, size * 0.8, "ro")
			end
			font:Print(string.format("\255\120\230\120+%s  \255\240\110\100-%s", short(income or 0), short(expense or 0)),
				bx0, ty, size * 0.8, "o")
		end
	end
end

-- BAR's top bar's own resource bars: off while the screen is upright (the dock shows them; a spectator has no dock, and
-- upright they ran over the top bar's numbers and buttons there too, 2026-11-09), back once it is not
local resBarsHidden = false
local function upright()
	local x, y = Spring.GetViewGeometry()
	return y > x * PORTRAIT
end
-- Its indicators too (wind, tide, the commander counts): BAR places them by the screen's width while its buttons go by
-- their own, so upright they sat over Statistics, Settings and Quit; the dock's energy panel shows the wind instead.
local indicatorsHidden = false
local function topbarBars(dockUp)
	local tb = WG.topbar
	if not tb then
		return
	end
	if tb.setResourceBarsVisible and tb.getResourceBarsVisible then
		if dockUp and tb.getResourceBarsVisible() then -- (also when BAR shows them again, at the game's start)
			tb.setResourceBarsVisible(false)
			resBarsHidden = true
		elseif not dockUp and resBarsHidden then
			tb.setResourceBarsVisible(true)
			resBarsHidden = false
		end
	end
	if tb.setIndicatorsVisible and tb.getIndicatorsVisible then
		if dockUp and tb.getIndicatorsVisible() then
			tb.setIndicatorsVisible(false)
			indicatorsHidden = true
		elseif not dockUp and indicatorsHidden then
			tb.setIndicatorsVisible(true)
			indicatorsHidden = false
		end
	end
end

-- nothing picked: the control groups as pictures along the bottom (Kailil: "touch friendly unit groups by keeping
-- unit groups in pictures at the bottom whenever no unit is slected"); a tap picks a group
local function drawGroups()
	L.groupRects = {}
	local r = L.groups
	panel(r)
	local groups = Spring.GetGroupList() or {}
	local list = {}
	for g, c in pairs(groups) do
		if c > 0 then
			list[#list + 1] = g
		end
	end
	table.sort(list)
	local h = r[4] - r[2]
	-- the group whose units are exactly the ones picked: marked as in use (a recalled group showed nothing on its tile)
	local sel = spGetSelectedUnits() or {}
	local current = #sel > 0 and Spring.GetUnitGroup(sel[1]) or nil
	if current and groups[current] ~= #sel then
		current = nil
	end
	for i = 2, current and #sel or 0 do
		if Spring.GetUnitGroup(sel[i]) ~= current then
			current = nil
			break
		end
	end
	-- units picked: a "+ NEW" tile after the groups makes them the next free group (no keyboard for Ctrl+number)
	local free
	if #sel > 0 then
		for n = 1, 9 do
			if not groups[n] or groups[n] == 0 then
				free = n
				break
			end
		end
	end
	if #list == 0 and not free then
		textIn("Groups: pick units, then + NEW here", r[1], r[2], r[3], r[4], h * 0.24, "\255\140\140\140")
		return
	end
	local w = min(h, floor((r[3] - r[1]) / max(1, #list + (free and 1 or 0))))
	if free then
		local x0 = r[1] + #list * w
		local nr = { x0 + 3, r[2] + 3, x0 + w - 3, r[4] - 3, new = free }
		L.groupRects[#L.groupRects + 1] = nr
		button(nr, { 0.2, 0.2, 0.2, 0.8 }, { 0.32, 0.32, 0.32, 0.8 })
		textIn("+", nr[1], nr[2] + h * 0.3, nr[3], nr[4], h * 0.42, "\255\255\200\064", bold)
		textIn("NEW " .. free, nr[1], nr[2], nr[3], nr[2] + h * 0.4, h * 0.2, "\255\220\220\220", font)
	end
	for i, g in ipairs(list) do
		local x0 = r[1] + (i - 1) * w
		local gr = { x0 + 3, r[2] + 3, x0 + w - 3, r[4] - 3, group = g }
		L.groupRects[#L.groupRects + 1] = gr
		local best, bestN = nil, 0
		for d, c in pairs(Spring.GetGroupUnitsCounts(g) or {}) do
			if type(d) == "number" and c > bestN then -- (the counts carry their total as "n")
				best, bestN = d, c
			end
		end
		if best then
			unitTile(best, gr, g == current)
		else
			button(gr)
		end
		bold:Print("\255\255\200\064" .. g, gr[1] + 6, gr[4] - h * 0.3, h * 0.26, "o")
		bold:Print("\255\255\255\255" .. groups[g], gr[3] - 6, gr[2] + 6, h * 0.2, "ro")
	end
end

-- the mode: the camera pad dims the dock a little and says how to open it; the open menu has BAR's gold along its top,
-- a pulse as it opens (Kailil: "a quick blink or sparkle or something that fits the BAR aesthetic"), and the time it
-- has left before the pad comes back
local function drawMode()
	local d = L.dock
	local t = now()
	if not menu then
		gl.Color(0, 0, 0, 0.32)
		gl.Rect(d[1], d[2], d[3], d[4])
		gl.Color(1, 1, 1, 1)
		if showSel then -- (no selection row: the dimmed dock says it alone)
			local s = L.sel
			local h = s[4] - s[2]
			-- (just above the picked unit's health bar, drawSelection's r[2] + h * 0.25: at the bottom it was printed over it)
			font:Print("\255\190\190\190CAMERA PAD  \255\140\140\140tap to use the menu", s[3] - L.pad, s[2] + h * 0.3, h * 0.15, "ro")
		end
		return
	end
	local age = t - menuAt
	local edge = max(2, floor(L.pad * 0.3))
	if age < BLINK then -- two quick pulses of light over the dock, gold at its top edge
		local a = math.sin(age / BLINK * math.pi * 2) ^ 2
		gl.Color(1, 0.9, 0.6, 0.16 * a)
		gl.Rect(d[1], d[2], d[3], d[4])
		gl.Color(1, 0.82, 0.35, 0.9 * a)
		gl.Rect(d[1], d[4] - edge * 3, d[3], d[4])
	end
	local left = max(0, 1 - (t - lastTouch) / MENU_SECONDS)
	gl.Color(1, 0.78, 0.25, 0.85)
	gl.Rect(d[1], d[4] - edge, d[1] + (d[3] - d[1]) * left, d[4])
	gl.Color(1, 1, 1, 1)
end

---------------------------------------------------------------------------------------------------------------------
-- The app's lines in the touch log (RtsTouch): only the dock's are read here; bardroid_touch.lua reads the rest. One
-- handle; the size is looked at every 30 reads (the app starts a new, shorter log now and then).

local logFile, logPos, logCalls = nil, 0, 0
local function newLines()
	if not logFile then
		logFile = io.open(TOUCH_LOG, "r")
		logPos = logFile and logFile:seek("end") or 0
		return nil
	end
	logCalls = logCalls + 1
	if logCalls % 30 == 0 then
		local size = logFile:seek("end")
		if not size then
			logFile:close()
			logFile = nil
			return nil
		end
		if size < logPos then
			logPos = 0
		end
	end
	if not logFile:seek("set", logPos) then
		return nil
	end
	local text = logFile:read("*a") or ""
	local last = text:match(".*()\n")
	if not last then
		return nil
	end
	logPos = logPos + last
	return text:sub(1, last)
end

local function dockLines()
	local lines = newLines()
	if not lines then
		return
	end
	for line in lines:gmatch("[^\n]+") do
		local side, v = line:match("^dockscroll (%a+) (%S+)")
		if side and active and menu then
			local _, s, _, _, _, ch = half(side)
			snapBy(s, -(tonumber(v) or 0), ch + L.gap) -- (X pixels down: the rows follow the finger)
			touched()
		end
		side, v = line:match("^dockfling (%a+) (%S+)")
		if side and active then
			local _, s, _, _, _, ch = half(side)
			snapRelease(s, -(tonumber(v) or 0) / (ch + L.gap))
			touched()
		end
		local cx, cy, cr = line:match("^dockcircle (%S+) (%S+) (%S+)")
		if cx and active then
			circleTo(tonumber(cx), tonumber(cy), tonumber(cr))
			touched()
		end
		local a, b, c, d = line:match("^dgunsticks (%S+) (%S+) (%S+) (%S+)")
		if a then -- the D-gun mode's sticks from the dock (RtsTouch): to it, and the knobs drawn
			dgunStick = { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, tonumber(d) or 0 }
			local D = WG.BarDroidPadDgun
			if D and D.sticks then
				D.sticks(dgunStick[1], dgunStick[2], dgunStick[3], dgunStick[4])
			end
		end
		local tx, ty = line:match("^docktap (%S+) (%S+)")
		if tx and active then -- a second finger on the dock while a box selection is dragged: a filter
			local item = itemAt("right", tonumber(tx), vsy - tonumber(ty))
			if item and item.kind == "filter" then
				selFilter = item.key
			end
			touched()
		end
		local name = line:match("^act (dock_%S+)")
		if name == "dock_menu" and active then
			setMenu(true)
		elseif name == "dock_select_start" and active then
			selecting = true
			touched()
			refresh()
		elseif name == "dock_select_end" then
			selecting = false
			if circle then
				pickCircle()
			else
				filterAt = now() + 0.15 -- (the engine makes the box selection when the button goes up)
			end
			touched()
			refresh()
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
		menu, selecting = false, false
		Spring.Echo("[bardroid-portrait] dock " .. (active and "up" or "down") .. string.format(" (%dx%d)", x, y))
		writeDock(true)
	end
end

local refreshAt = 0
-- The order a drag draws, its cursor through the drag (Kailil, 2026-11-09: for Fight and Patrol "the order is placed
-- correctly, but the cursor ... stays green"): BAR's formation widget unpicks the order as a one-unit path starts
-- (cmd_customformations2: SetActiveCommand(0), the order kept as its own), so the pointer showed Move's green cursor
-- over a Fight or Patrol path. The order picked when the right button went down: its cursor until it comes up.
local armedCursor, drawCursor = nil, nil
local function drawingCursor()
	local _, _, _, _, right = Spring.GetMouseState()
	if right then
		drawCursor = drawCursor or armedCursor
		if drawCursor then
			Spring.SetMouseCursor(drawCursor)
		end
		return
	end
	drawCursor = nil
	local index, id = spGetActiveCommand()
	local desc = id and DRAW_CMDS[id] and index and Spring.GetActiveCmdDesc(index)
	armedCursor = desc and desc.cursor or nil
end

function widget:Update(dt)
	checkActive()
	dockLines()
	topbarBars(active or upright())
	if not active then
		return
	end
	drawingCursor()
	for _, s in ipairs({ leftScroll, rightScroll }) do
		if s.drag or s.t < 1 then
			markDirty() -- (rows moving: the texture drawn again each frame until they settle)
		end
		snapUpdate(s, dt)
	end
	local t = now()
	if menu and not selecting and not leftScroll.drag and not rightScroll.drag and t - lastTouch > MENU_SECONDS then
		setMenu(false)
	end
	if filterAt and t >= filterAt then
		filterAt = nil
		applyFilter()
	end
	if t >= refreshAt and not press then
		refreshAt = t + 0.25
		refresh()
	end
	writeDock(false)
end

function widget:CommandsChanged()
	if active and not press then
		refresh()
	end
end

-- springsettings bardroid_portrait_profile = 1: the dock's drawing time, its average every 10 s in the log (tools;
-- 2.1 ms a frame on the dev phone, 2026-11-09; a display list of it made that 4-10 ms, growing: FlowUI's own lists
-- inside it, made again several times a second; BAR's menus keep theirs in a texture, the way to try next)
local profile = Spring.GetConfigInt("bardroid_portrait_profile", 0) == 1
local profSum, profN, profAt = 0, 0, 0

-- The dock's still parts in a texture, drawn again only when something changed (dirty: the refresh a few times a
-- second, a press, rows moving, the layout), as BAR's own build and order menus keep theirs (gl.R2tHelper); the
-- moving parts drawn over it every frame: metal and energy, PLACE, the mode. Screen pixels (no supersampling: the
-- dock starts at 0,0, so the halves' scissor rects are the texture's own). Without the helper: all drawn each frame.
local dockTex, texW, texH
-- springsettings bardroid_portrait_tex (tools): 0 no texture (all drawn each frame), 2 the texture drawn again every
-- frame (a stress test: two GPU driver faults on the dev phone in its first 8 games, none in 18 before it, 2026-11-09)
local texMode = Spring.GetConfigInt("bardroid_portrait_tex", 1)

-- the D-gun mode's controls (live: the knobs follow the thumbs)
local function disc(x, y, r, fill)
	gl.BeginEnd(fill and GL.TRIANGLE_FAN or GL.LINE_LOOP, function()
		if fill then
			gl.Vertex(x, y)
		end
		for i = 0, 40 do
			local a = i / 40 * 2 * math.pi
			gl.Vertex(x + math.cos(a) * r, y + math.sin(a) * r)
		end
	end)
end
local function drawDgun()
	local p = dgunParts()
	for i, s in ipairs({ p.l, p.r }) do
		gl.Color(0, 0, 0, 0.5)
		disc(s[1], s[2], s[3], true)
		gl.LineWidth(2)
		gl.Color(1, 1, 1, 0.3)
		disc(s[1], s[2], s[3], false)
		gl.LineWidth(1)
		local kx, ky = s[1] + dgunStick[i * 2 - 1] * s[3], s[2] - dgunStick[i * 2] * s[3]
		if i == 1 then
			gl.Color(0.8, 0.8, 0.8, 0.9)
		else
			gl.Color(1, 0.3, 0.25, 0.95) -- (the aim: the shot's red, as its ring on the ground)
		end
		disc(kx, ky, s[3] * 0.36, true)
		gl.Color(1, 1, 1, 1)
		textIn(i == 1 and "MOVE" or "AIM", s[1] - s[3], s[2] - s[3] - L.btnH * 0.55, s[1] + s[3], s[2] - s[3] - L.gap,
			L.btnH * 0.36, "\255\200\200\200", font)
	end
	button(p.fire, { 0.5, 0.06, 0.05, 1 }, { 0.86, 0.14, 0.11, 1 })
	textIn("FIRE", p.fire[1], p.fire[2], p.fire[3], p.fire[4], (p.fire[4] - p.fire[2]) * 0.42, "\255\255\255\255", bold)
	button(p.cancel)
	textIn("\226\156\149", p.cancel[1], p.cancel[2], p.cancel[3], p.cancel[4], (p.cancel[4] - p.cancel[2]) * 0.5,
		"\255\255\150\140", bold)
	resetGL()
end

local function drawStill()
	panel(L.dock, 1, 1, 0, 0, true)
	if showSel then
		drawSelection()
	end
	drawHalf("left")
	drawHalf("right")
	if showGroups then
		drawGroups()
	else
		L.groupRects = {}
	end
end

local function drawDock()
	local R = gl.R2tHelper
	if texMode ~= 0 and R and R.RenderInRect and R.BlendTexRect then
		local w, h = L.dock[3] - L.dock[1], L.dock[4] - L.dock[2]
		if dockTex and (texW ~= w or texH ~= h) then
			gl.DeleteTexture(dockTex)
			dockTex = nil
		end
		if not dockTex then
			dockTex = gl.CreateTexture(w, h, { target = GL.TEXTURE_2D, format = GL.RGBA8, fbo = true })
			texW, texH, dirty = w, h, true
		end
		if (dirty or texMode == 2) and dockTex then
			R.RenderInRect(dockTex, L.dock[1], L.dock[2], L.dock[3], L.dock[4], drawStill, true)
			dirty = false
		end
		if dockTex then
			-- (drawn into the texture the dock's panel is no longer opaque: the game and BAR's menus under it showed
			-- through; an opaque base under it)
			gl.Color(0.03, 0.035, 0.04, 1)
			gl.Rect(L.dock[1], L.dock[2], L.dock[3], L.dock[4])
			gl.Color(1, 1, 1, 1)
			R.BlendTexRect(dockTex, L.dock[1], L.dock[2], L.dock[3], L.dock[4], true)
		end
	else
		drawStill()
	end
	resetGL()
	drawResources()
	if rightKind == "place" then
		drawPlace()
	end
	if rightKind == "dgun" then
		drawDgun()
		return -- (no camera pad dimming or menu edge: the sticks are always live)
	end
	drawMode()
end

function widget:DrawScreen()
	if not active then
		return
	end
	if drawCursor then -- (again here: after the engine has picked its own for the frame)
		Spring.SetMouseCursor(drawCursor)
	end
	font = WG.fonts and WG.fonts.getFont() or font
	bold = WG.fonts and WG.fonts.getFont(2) or font
	if not font then
		return
	end
	if not profile then
		drawDock()
		return
	end
	local t0 = spGetTimer()
	drawDock()
	profSum, profN = profSum + spDiffTimers(spGetTimer(), t0) * 1000, profN + 1
	if now() - profAt >= 10 then
		Spring.Echo(string.format("[bardroid-portrait] drawing %.2f ms a frame (%d frames), %d refreshes taking %.2f ms each",
			profSum / max(1, profN), profN, refreshN, refreshMs / max(1, refreshN)))
		profSum, profN, profAt, refreshN, refreshMs = 0, 0, now(), 0, 0
	end
end

-- the circle being dragged, on the ground in BAR's gold
function widget:DrawWorld()
	local c = active and selecting and circle
	if not (c and c.r > 0) then
		return
	end
	gl.DepthTest(false)
	gl.LineWidth(3)
	gl.Color(1, 0.78, 0.25, 0.9)
	gl.DrawGroundCircle(c.x, c.y, c.z, c.r, 64)
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

function widget:IsAbove(x, y)
	return active and inRect(x, y, L.dock)
end

function widget:GetConfigData()
	return { selStyle = selStyle, selFilter = selFilter }
end

function widget:SetConfigData(data)
	if data and (data.selStyle == "box" or data.selStyle == "circle") then
		selStyle = data.selStyle
	end
	if data and type(data.selFilter) == "string" then
		selFilter = data.selFilter
	end
end

-- presses come from fingers in menu mode (RtsTouch clicks the dock only then), a mouse, or the pad's pointer
function widget:MousePress(x, y, btn)
	if not (active and inRect(x, y, L.dock)) then
		return false
	end
	touched()
	local pr = placeRect()
	if pr and inRect(x, y, pr) then -- the PLACE panel: the build menu copy's (rotate, cancel; PLACE is RtsTouch's)
		local B = WG.bardroidBuildmenu
		if B and B.droidPressPanel then
			B.droidPressPanel(x, y)
		end
		return true
	end
	local wide = rightKind == "home" or rightKind == "share" or rightKind == "panel"
	local side = wide and inRect(x, y, homeRect()) and "right" -- (the whole grid: both halves)
		or inRect(x, y, L.left) and "left" or inRect(x, y, L.right) and "right" or nil
	if side == "right" and rightKind == "panel" then -- a slider: set where pressed, then follows the finger
		for i, item in ipairs(rightItems) do
			local cr = cellRect("right", i)
			if item.kind == "slider" and cr and inRect(x, y, cr) then
				slide = { item = item, rect = cr }
				setSlider(item, cr, x)
				return true
			end
		end
	end
	press = { side = side, x = x, y = y, button = btn, lastY = y, lastT = now(), vel = 0 }
	return true -- (the dock is the dock's: no press goes through to the map under it)
end

function widget:MouseMove(x, y)
	if slide then
		setSlider(slide.item, slide.rect, x)
		touched()
		return
	end
	local p = press
	if not (p and p.side) then
		return
	end
	if not p.moved and abs(y - p.y) < vsx * 0.012 then
		return
	end
	p.moved = true
	local _, s, _, _, _, ch = half(p.side)
	snapBy(s, y - p.lastY, ch + L.gap) -- (a mouse drag: the rows follow it)
	local t = now()
	if t > p.lastT then
		p.vel = 0.6 * p.vel + 0.4 * ((y - p.lastY) / (ch + L.gap) / (t - p.lastT))
	end
	p.lastY, p.lastT = y, t
	touched()
end

function widget:MouseRelease(x, _, btn)
	if slide then
		setSlider(slide.item, slide.rect, x)
		slide = nil
		refresh()
		return true
	end
	local p = press
	press = nil
	if not p then
		return false
	end
	if not p.side and inRect(p.x, p.y, L.res) then -- metal or energy tapped: its panel (again: closed)
		local res = p.x < (L.res[1] + L.res[3]) / 2 and "metal" or "energy"
		resPanel = resPanel ~= res and res or nil
		sharing = nil
		refresh()
		return true
	end
	if p.side then
		if p.moved then
			local _, s = half(p.side)
			snapRelease(s, p.vel)
			return true
		end
		pressItem(itemAt(p.side, p.x, p.y), btn == 3)
		return true
	end
	if L.groupRects then -- a control group's picture: those units; a long press: the units picked now become that group;
		-- "+ NEW": the units picked become the next free group (the engine's own group commands, as BAR's hotkeys)
		local picked = #(spGetSelectedUnits() or {}) > 0
		for _, gr in ipairs(L.groupRects) do
			if inRect(p.x, p.y, gr) then
				if gr.new then
					Spring.SendCommands("group set " .. gr.new)
					Spring.Echo("[bardroid-portrait] group " .. gr.new .. " made") -- (tools)
				elseif btn == 3 and picked then
					Spring.SendCommands("group set " .. gr.group)
					Spring.Echo("[bardroid-portrait] group " .. gr.group .. " set")
				else
					Spring.SendCommands("group select " .. gr.group)
				end
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
		queueRect = function() -- (bardroid_pad.lua's QUEUE, the fingers' sticky Shift: the top row's right end)
			if not active then
				return nil
			end
			local s = L.sel
			local h = floor((s[4] - s[2]) * 0.42)
			local w = floor(h * 2.6)
			return { s[3] - L.pad - w, s[4] - L.pad - h, s[3] - L.pad, s[4] - L.pad }
		end,
		menu = function()
			return menu
		end,
	}
	checkActive()
	writeDock(true)
end

function widget:Shutdown()
	if dockTex then
		gl.DeleteTexture(dockTex)
	end
	WG.BarDroidPortrait = nil
	active = false
	topbarBars(false)
	writeDock(true)
	if logFile then
		logFile:close()
	end
end
