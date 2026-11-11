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
-- Every press goes through Spring.SetActiveCommand or a selection, as BAR's own menus do (online-safe); the one
-- GiveOrder, a factory's state for the units it built, goes through pcall (a host can forbid widgets' orders).
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
local MENU_SECONDS = 2 -- the menu goes back to the camera pad after this long untouched (Kailil: "5-10seconds";
-- 2026-11-10: 1.25, then "Extend mouse tap ui delay too instead 2 seconds")
local HOME_ROWS = 3 -- nothing picked: the home grid's rows of big buttons (L.homeRows: as many as its buttons take,
-- one more at most, refreshNow; no new local here: the file's main chunk is at Lua's 200)
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
local unqShown = false -- the groups strip's remove-order buttons: a factory picked, or units with orders
local allPicked, keepTypes = false, false -- LOCAL / ALL UNITS: the whole list picked; the list kept through that pick
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
-- cam: where the camera will be ({ x, y, z }, its heading as now), else where it is.
local function planeAt(sx, sy, h, cam)
	local px, py, pz
	if cam then
		px, py, pz = cam[1], cam[2], cam[3]
	else
		px, py, pz = Spring.GetCameraPosition()
	end
	local dx, dy, dz = Spring.GetPixelDir(sx, vsy - sy) -- (its y from the top, as the engine's mouse; ours from the bottom)
	if not (px and dx) or dy > -1e-4 then
		return nil
	end
	local t = (h - py) / dy
	return px + dx * t, pz + dz * t
end
-- The view above the dock kept on the map where it fits (upright, a commander by the map's edge left almost half of it
-- on the empty void past the edge; dev phone, 2026-11-09): the point moved just enough for the view's corners to stay
-- inside the edges, and the view centred along a side where it is longer than the map
local function keepOnMap(x, z, h, cam)
	local ox, oz = planeAt(floor(vsx / 2), floor((L.dock[4] + vsy) / 2), h, cam)
	if not ox then
		return x, z
	end
	local x0, x1, z0, z1 = 0, 0, 0, 0
	for _, c in ipairs({ { 0, L.dock[4] }, { vsx - 1, L.dock[4] }, { 0, vsy - 1 }, { vsx - 1, vsy - 1 } }) do
		local px, pz = planeAt(c[1], c[2], h, cam)
		if not px then
			return x, z -- (a corner past the horizon: a tilted camera, left as it is)
		end
		x0, x1 = min(x0, px - ox), max(x1, px - ox)
		z0, z1 = min(z0, pz - oz), max(z1, pz - oz)
	end
	local function fit(v, lo, hi, size)
		if hi - lo >= size then
			return (size - lo - hi) / 2
		end
		return max(-lo, min(size - hi, v))
	end
	local nx, nz = fit(x, x0, x1, Game.mapSizeX), fit(z, z0, z1, Game.mapSizeZ)
	-- but never so far that the point leaves the middle half of the view: a tilted camera's far half covers a long way,
	-- and the whole move put a commander by the edge out of sight (2490 elmos). The middle half's corners on the ground,
	-- from the view's middle; after a part t of the move the point is -t times the move from that middle.
	local band = (vsy - L.dock[4]) * 0.25
	local quad = {}
	for _, c in ipairs({ { 0.2, L.dock[4] + band }, { 0.8, L.dock[4] + band }, { 0.8, vsy - band }, { 0.2, vsy - band } }) do
		local px, pz = planeAt(floor(vsx * c[1]), floor(c[2]), h, cam)
		if not px then
			return x, z
		end
		quad[#quad + 1] = { px - ox, pz - oz }
	end
	local function inMiddle(t)
		local dx, dz = -t * (nx - x), -t * (nz - z)
		local side = 0
		for i = 1, 4 do
			local a, b = quad[i], quad[i % 4 + 1]
			local cross = (b[1] - a[1]) * (dz - a[2]) - (b[2] - a[2]) * (dx - a[1])
			local s = cross > 0 and 1 or (cross < 0 and -1 or 0)
			if s ~= 0 then
				if side == 0 then
					side = s
				elseif s ~= side then
					return false
				end
			end
		end
		return true
	end
	if not inMiddle(1) then
		local lo, hi = 0, 1
		for _ = 1, 10 do
			local t = (lo + hi) / 2
			if inMiddle(t) then
				lo = t
			else
				hi = t
			end
		end
		nx, nz = x + lo * (nx - x), z + lo * (nz - z)
	end
	return nx, nz
end

-- COMMANDER and BASE's zoom (Kailil, 2026-11-10: "a comfortable level where the icon is not visible and the full 3d model
-- is shown"): the camera this far from the point, and always well under the height where units are drawn as icons
-- (the engine's: 750^0.5 x UnitIconDist over the map, by height when UseDistToGroundForIcons; 3900 by BAR's settings)
local COMFORT_DIST = 1300
local function comfortDist()
	local icon = 750 ^ 0.5 * (Spring.GetConfigFloat("UnitIconDist", 200) or 200)
	local k = Spring.GetConfigFloat("UseDistToGroundForIcons", 0) or 0
	if k > 0 then
		icon = icon / math.sqrt(k)
	end
	return max(400, min(COMFORT_DIST, icon * 0.8))
end

local function cameraTo(x, y, z, zoom)
	-- with zoom, the camera's own state (BAR's spring camera): the new distance along its heading, the view measured
	-- from where the camera will be
	local s = zoom and Spring.GetCameraState()
	local cam
	if s and s.name == "spring" and (s.dist or 0) > 1 and s.px then
		local px, py, pz = Spring.GetCameraPosition()
		local k = comfortDist() / s.dist
		s.dist = s.dist * k
		cam = { x + (px - s.px) * k, y + (py - s.py) * k, z + (pz - s.pz) * k }
	else
		s = nil
	end
	x, z = keepOnMap(x, z, y, cam)
	local cx = floor(vsx / 2)
	local ax, az = planeAt(cx, floor(vsy / 2), y, cam)
	local bx, bz = planeAt(cx, floor((L.dock[4] + vsy) / 2), y, cam)
	if ax and bx then
		x, z = x + ax - bx, z + az - bz
	end
	if s then
		s.px, s.py, s.pz = x, Spring.GetGroundHeight(x, z) or y, z
		Spring.SetCameraState(s, 0.25)
	else
		Spring.SetCameraTarget(x, y, z, 0.25)
	end
end

-- The camera dragged from the dock's empty space (Kailil, 2026-11-10: "if I grab empty space in the ui and moved my
-- finger around, let that pan my camera"), as the camera pad drags it (RtsTouch's PAD_PAN_GAIN): the ground at the
-- middle of the game above the dock follows the finger's move (GL pixels, y up), a little more than it
local PAN_GAIN = 1.3
local function panBy(dx, dy)
	local s = Spring.GetCameraState()
	if not (s and s.px) or (dx == 0 and dy == 0) then
		return
	end
	local mx, my = floor(vsx / 2), floor((L.dock[4] + vsy) / 2)
	local ax, az = planeAt(mx, my, s.py or 0)
	local bx, bz = planeAt(mx + dx * PAN_GAIN, my + dy * PAN_GAIN, s.py or 0)
	if ax and bx then
		s.px, s.pz = s.px - (bx - ax), s.pz - (bz - az)
		Spring.SetCameraState(s, 0)
	end
end

-- The D-gun mode's camera (DG above): the commander kept in the middle of the game above the dock, caught up with in
-- FOLLOW seconds (smooth as it enters the mode and between the simulation's frames); the zoom and the turn stay the
-- player's (the dock's empty space), past the map's edge too
local DG = { stick = { 0, 0, 0, 0 } } -- the D-gun mode's (below): stick: lx, ly, rx, ry as RtsTouch sent them (the
-- knobs); slide: FIRE's swipe, 0..1 while held, nil after (slideOff: when it ended, slideLast: how far it had gone)

-- The camera distance that shows the D-gun's whole reach around the commander: its ring and a target at the ring's
-- edge (32 across, and a little more) inside the game above the dock with room to spare; upright the screen's width
-- decides (dev phone, 2026-11-10: at COMMANDER's distance the ring touched both sides and a target at its side was cut
-- off). On-screen sizes go as one over the distance, so the distance now times how far past the room it reaches.
function DG.fitDist(u, s)
	local D = WG.BarDroidPadDgun
	local range = D and D.range and D.range()
	local x, y, z = Spring.GetUnitPosition(u)
	if not (range and x and s and s.dist) then
		return nil
	end
	local ux, uy = Spring.WorldToScreenCoords(x, y, z)
	local r = range + 48
	local halfW, halfH = vsx / 2 - L.pad * 2, (vsy - L.dock[4]) / 2 - L.pad * 2
	local need = 0
	for i = 0, 15 do
		local a = i * math.pi / 8
		local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
		local sx, sy = Spring.WorldToScreenCoords(px, Spring.GetGroundHeight(px, pz) or y, pz)
		if sx and halfW > 0 and halfH > 0 then
			need = max(need, abs(sx - ux) / halfW, abs(sy - uy) / halfH)
		end
	end
	return need > 0 and s.dist * need or nil
end

function DG.follow(dt)
	local FOLLOW = 0.08
	local D = WG.BarDroidPadDgun
	local u = D and D.unit and D.unit()
	local x, y, z
	if u then
		x, y, z = Spring.GetUnitPosition(u)
	end
	local s = x and Spring.GetCameraState()
	if u ~= DG.unitWas then -- (the mode just entered: from far off, the camera eased in once to COMMANDER's distance,
		-- the D-gun's ring a speck at the start's 5000; dev phone, 2026-11-10; the zoom is the player's from there), and
		-- out as far as the D-gun's whole reach needs (fitDist)
		DG.unitWas, DG.zoomUntil = u, u and now() + 0.6 or nil
		local fit = u and DG.fitDist(u, s)
		DG.zoomTo = u and s and s.dist and s.dist > comfortDist() * 1.2 and max(comfortDist(), fit or 0) or nil
		if u and not DG.zoomTo and fit and s.dist < fit then
			DG.zoomTo = fit
		end
	end
	if not (s and s.px) then
		return
	end
	local zooming = DG.zoomTo and now() < DG.zoomUntil and s.dist
	if zooming then
		s.dist = s.dist + (DG.zoomTo - s.dist) * (1 - math.exp(-(dt or 0.033) / 0.12))
	end
	-- the ground at the middle of the game above the dock, at the commander's height: the camera moved by what is
	-- between them
	local bx, bz = planeAt(floor(vsx / 2), floor((L.dock[4] + vsy) / 2), y)
	if not bx then
		return
	end
	local tx, tz = s.px + x - bx, s.pz + z - bz
	local k = 1 - math.exp(-(dt or 0.033) / FOLLOW)
	local nx, nz = s.px + (tx - s.px) * k, s.pz + (tz - s.pz) * k
	if abs(nx - s.px) + abs(nz - s.pz) < 0.05 and not zooming then
		return
	end
	s.px, s.pz = nx, nz
	s.py = Spring.GetGroundHeight(nx, nz) or s.py
	Spring.SetCameraState(s, 0)
end

-- Once at the start, after the engine's own move to the start spot (a second): the start spot in the middle of the view
-- above the dock (the engine's middle is the dock's top edge: the commander sat on it), the view kept on the map
local startFitted = false
local function startFit()
	if startFitted then
		return
	end
	local f = Spring.GetGameFrame()
	if f < 40 then
		return
	end
	startFitted = true
	if f > 90 then
		return -- (the widget loaded mid-game: the camera is the player's)
	end
	local x, y, z = Spring.GetTeamStartPosition(myTeam())
	if x and (x > 0 or z > 0) then
		cameraTo(x, y, z)
		Spring.Echo("[bardroid-portrait] start view on the start spot")
	end
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
-- Kailil, 2026-11-10: while it lasts "unit group selection and first and last row be hidden so the ui is shorter. And
-- hide the commander selected bar" (refreshNow: the dock's lower rows go and the game takes their room); "Have the camera
-- follow the commander and keep the commander in the center" (DG.follow: the middle of the game above the dock); "the
-- empty Gray space to let me zoom up and down. Or rotate. Not panning" (RtsTouch: a finger there, up or down zooms,
-- sideways turns); full auto "by holding fire button then swiping to the right" (RtsTouch's dgunslide lines: the track
-- beside FIRE fills, at its end "act dgun_auto"; FIRE again ends it; bardroid_pad.lua dgunAuto)
local function dgunOn()
	local D = WG.BarDroidPadDgun
	return D and D.active and D.active() or false
end

-- its parts in the grid: the sticks (x, y, radius), FIRE and the cancel corner (rects); GL pixels
local function dgunParts()
	local r = { L.left[1], L.left[2], L.right[3], L.right[4] }
	local w, h = r[3] - r[1], r[4] - r[2]
	-- the sticks between their words (MOVE, AIM: under them) and FIRE's foot (on the near-square screen, the Fold7
	-- unfolded upright, a stick sized by the height alone reached the grid's foot and its word fell off the screen)
	local words = floor(L.btnH * 0.6)
	local room = floor(h * 0.74) - L.gap - words
	local rad = floor(min(w * 0.2, room * 0.5))
	local cy = r[2] + words + floor(room / 2)
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
	-- (dgunauto: full auto on, FIRE's swipe goes left to end it)
	local D = WG.BarDroidPadDgun
	local auto = D and D.auto and D.auto()
	return string.format("dgun 1\nstickl %d %d %d\nstickr %d %d %d\nfire %s\ncancel %s\ndgunauto %d\n", p.l[1], vsy - p.l[2],
		p.l[3], p.r[1], vsy - p.r[2], p.r[3], rect(p.fire), rect(p.cancel), auto and 1 or 0)
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
	local dg = dgunOn() -- (the D-gun mode: neither row, a shorter dock)
	local wantSel, wantGroups = #sel > 0 and not dg, (#sel > 0 or anyGroup) and not dg
	if wantSel ~= showSel or wantGroups ~= showGroups then -- (the dock's rows: laid out again)
		showSel, showGroups = wantSel, wantGroups
		layout()
	end
	local unq = #sel > 0 and selectedFactory()
	for i = 1, unq and 0 or #sel do
		if (Spring.GetUnitCommandCount(sel[i]) or 0) > 0 then
			unq = true
			break
		end
	end
	if (unq == true) ~= unqShown then
		unqShown = unq == true
		markDirty()
	end
	local key = #sel .. ":" .. tostring(sel[1])
	local newPick = key ~= lastSelection -- (another pick: both halves from their first rows, not the last unit's place)
	if newPick then
		lastSelection, factoryItem = key, nil
		if sharing == "units" then -- (another pick: not what TRANSFER was pressed for)
			sharing = nil
		end
		if #sel > 0 and not multi and not keepTypes then
			typesFrom = nil
		end
		allPicked = allPicked and keepTypes
	end
	keepTypes = false
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
	elseif typesFrom and #sel == 0 then -- a list on the left with nothing picked: the lists, MULTI and DONE (with units
		-- picked, their orders as for any pick: Kailil, 2026-11-10, "For selecting all units or local units. Get rid of the
		-- buttons thats on the right. Instead show the order buttons that appear when a unit is selected")
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
		if WG.BarDroidRetreat then -- (across the dock under them: hurt units fall back, bardroid_retreat.lua; where the
			-- host forbids widgets' orders it cannot, and says so)
			local R = WG.BarDroidRetreat
			local allowed = not R.allowed or R.allowed()
			newRight[#newRight + 1] = { kind = "retreat", w = 2, on = allowed and R.on(),
				label = not allowed and "AUTO RETREAT: OFF IN THIS GAME" or R.on() and "AUTO RETREAT: ON"
					or "AUTO RETREAT: OFF" }
		end
		rk = "home"
	elseif building and not selectedFactory() then -- a building picked: its shapes, and PLACE under them (the build
		-- menu copy's panel, in placeRect: RtsTouch places from its rects, bardroid_place.txt)
		newRight, rk = placeShapes(), "place"
	elseif factoryItem then -- a factory's item pressed: its queue
		-- (two rows tall each, as the big orders: six buttons filled three short rows of the half; one row where pages
		-- of two-row pairs would be cut: an odd number of rows under six in sight)
		local rr = L.rightRows or 3
		local qh = (rr >= 6 or rr % 2 == 0) and 2 or 1
		newRight = {
			{ kind = "queue", n = 1, label = "+1", h = qh }, { kind = "queue", n = 5, label = "+5", h = qh },
			{ kind = "queue", n = 20, label = "+20", h = qh }, { kind = "queue", n = -1, label = "-1", h = qh },
			{ kind = "clearitem", label = "CLEAR", h = qh }, { kind = "back", label = "ORDERS", h = qh },
		}
		rk = "factory"
	else -- (the box or circle and its filter after the orders: with units picked only, Kailil 2026-11-09)
		newRight, rk = orders, "orders"
		if mobilePicked or selectedFactory() then -- (units that move picked: FIGHT, MOVE, PATROL first and largest, pack)
			-- (and a commander's D-gun across after them: its touch sticks, k == "order" with CMD.MANUALFIRE; a factory's
			-- FIGHT, MOVE and PATROL are where its new units go, the same size, and its REPEAT across after them: Kailil,
			-- 2026-11-10, the factory's order menu "with the larger buttons arrangement too", the rest left to us)
			-- (two rows tall where the half shows four or more: three, the unfolded Fold7 upright, cut MOVE and PATROL
			-- through the middle at its foot, Kailil: "Do not allow scroll to half reveal objects"; one row then)
			local bh = (L.rightRows or 3) >= 4 and 2 or 1
			local big = { [CMD.FIGHT] = { 1, 2, bh }, [CMD.MOVE] = { 2, 1, bh }, [CMD.PATROL] = { 3, 1, bh },
				[CMD.MANUALFIRE] = { 4, 2, 1 } }
			if not mobilePicked then
				big[CMD.MANUALFIRE], big[CMD.REPEAT] = nil, { 4, 2, 1 }
			end
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
		if WG.BarDroidPresets and WG.BarDroidPresets.fits(sel) then -- (after FIGHT, MOVE, PATROL, D-gun: bardroid_presets.lua)
			local at = 1
			while newRight[at] and newRight[at].h do
				at = at + 1
			end
			table.insert(newRight, at, { kind = "presets", label = "PRESETS" })
		end
		newRight[#newRight + 1] = style
		newRight[#newRight + 1] = { kind = "filterpick", label = "FILTER: " .. selFilter:upper() }
	end
	if sharing or resPanel then -- (the picker or the panel: the whole grid)
		newLeft, lk = {}, sharing and "share" or "panel"
		-- (with nothing picked the home grid stays under the panel, a drop-down over it: it took the whole dock, half of
		-- it empty below CLOSE; a press on one of them closes the panel)
		local home = not sharing and rk == "home" and newRight
		newRight, rk = sharing and shareItems() or panelItems(resPanel), lk
		for _, it in ipairs(home or {}) do
			it.home = true
			newRight[#newRight + 1] = it
		end
	end
	if WG.BarDroidPresets and WG.BarDroidPresets.isOpen() then -- (the presets: 2 x 2 over the whole grid, an X)
		if #sel > 0 then
			newLeft, lk, newRight, rk = {}, "presets", WG.BarDroidPresets.items(), "presets"
		else
			WG.BarDroidPresets.close()
		end
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
	if rk == "home" then -- (all of it on the dock: AUTO RETREAT a fourth row, no scrolling)
		L.homeRows = max(HOME_ROWS, min(HOME_ROWS + 1, rightRowsN))
	elseif rk == "presets" then -- (laid out as the home grid, 2 x 2)
		L.homeRows = 2
	end
	snapSet(rightScroll, rightRowsN, (rk == "home" or rk == "presets") and (L.homeRows or HOME_ROWS)
		or (rk == "share" or rk == "panel") and wideRows
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

-- A factory's move state for its units (Kailil, 2026-11-10: "sets every unit that came out of the factory or that will
-- come out of the factory to the status I toggle it to. Tapping the button will cycle through the three states.
-- Stopping on a state for .3 seconds still initiate the selection"; and an air factory's fly / land for "all planes that
-- came out of the factory (except the builders)"). Units built later take the factory's state themselves (the engine's;
-- BAR's Factory hold position relies on it); those it built before get it once the factory's button has rested
-- fac.REST: the units each factory turned out are remembered (UnitFromFactory). (One table: the file's main chunk is at
-- Lua's 200 locals.)
local fac = {
	REST = 0.3,
	made = {}, -- factory unitID -> { unitID = true }
	pressed = nil, -- { cmd, give, at }: a factory's move state or fly / land pressed last, the order its units get
}
-- An air plant's fly / land is BAR's own button (gadget unit_air_plants, "apLandAt": 0 Fly, 1 Land), which hands its
-- state to new planes as CMD.IDLEMODE (0 fly, 1 land); the engine's IDLEMODE button is not on an air plant
function fac.isLandAt(id)
	for _, f in ipairs(spGetSelectedUnits() or {}) do
		for _, d in ipairs(Spring.GetUnitCmdDescs(f) or {}) do
			if d.id == id then
				return d.name == "apLandAt" or d.action == "apLandAt"
			end
		end
	end
	return false
end
local function factoryStates()
	local p = fac.pressed
	if not p or now() - p.at < fac.REST then -- (now(): seconds)
		return
	end
	fac.pressed = nil
	local total, label = 0, nil
	for _, f in ipairs(spGetSelectedUnits() or {}) do
		local fd = UnitDefs[Spring.GetUnitDefID(f) or -1]
		local made = fac.made[f]
		if fd and fd.isFactory and made then
			local state
			for _, d in ipairs(Spring.GetUnitCmdDescs(f) or {}) do
				if d.id == p.cmd and d.params and d.params[1] then
					state = tonumber(d.params[1])
					label = d.params[(state or 0) + 2] or label
				end
			end
			local units = {}
			for u in pairs(made) do
				local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
				if not ud or Spring.GetUnitTeam(u) ~= myTeam() then
					made[u] = nil -- (gone, or no longer this team's)
				elseif p.give ~= CMD.IDLEMODE or (ud.canFly and not ud.isBuilder) then
					units[#units + 1] = u
				end
			end
			-- (through pcall: a host can forbid user widgets' orders, BAR's handler then throws, and a widget that throws
			-- is removed, the whole dock with it; the units built later still take the factory's state)
			if state and #units > 0 and pcall(Spring.GiveOrderToUnitArray, units, p.give, { state }, 0) then
				total = total + #units
			end
		end
	end
	if total > 0 then
		label = (label or ""):match("^%s*(.-)%s*$") -- (BAR's " Fly ")
		local P = WG.BarDroidPad
		if P and P.say then
			P.say(string.format("%d %s: %s", total, total == 1 and "UNIT" or "UNITS", string.upper(label)))
		end
		Spring.Echo(string.format("[bardroid-portrait] factory state %s to %d units", label, total)) -- (tools)
	end
end

function widget:UnitFromFactory(unitID, _, unitTeam, factID)
	if unitTeam == myTeam() and factID then
		fac.made[factID] = fac.made[factID] or {}
		fac.made[factID][unitID] = true
	end
end

function widget:UnitDestroyed(unitID)
	fac.made[unitID] = nil
end

-- The first or the last order taken off (Kailil, 2026-11-10: "a way to remove orders at the front or end of a queue"):
-- a factory's build queue through BAR's own build button right-clicked (the engine takes one of that type off the
-- back; with Alt the first of it), the last or the first item's type; units' orders through BAR's Command Queue
-- Manager, whose keys the app presses (bardroid_pad.lua queueKey), as the pad's L3 and R3 do
local function removeOrder(last)
	for _, u in ipairs(spGetSelectedUnits() or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
		if ud and ud.isFactory then
			local items = {}
			for _, c in ipairs(Spring.GetFactoryCommands(u, -1) or {}) do
				if c.id < 0 then
					items[#items + 1] = c.id
				end
			end
			local id = last and items[#items] or items[1]
			local index = id and spGetCmdDescIndex(id)
			if index then
				spSetActiveCommand(index, 3, false, true, not last, false, false, false)
			end
			return
		end
	end
	local P = WG.BarDroidPad
	if P and P.queueKey then
		P.queueKey(last)
	end
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
	if item.home then -- (the home grid under the resource panel)
		resPanel = nil
	end
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
		if selectedFactory() then -- (its units follow once the state rests: factoryStates)
			local give = (item.id == CMD.MOVE_STATE or item.id == CMD.IDLEMODE) and item.id
				or (fac.isLandAt(item.id) and CMD.IDLEMODE)
			if give then
				fac.pressed = { cmd = item.id, give = give, at = now() }
			end
		end
	elseif k == "units" then
		typesFrom = typesFrom ~= item.from and item.from or nil
		multi, multiPicked, allPicked = false, {}, false
		if typesFrom == "local" or typesFrom == "all" then -- (Kailil, 2026-11-10: "default to all and have them selected
			-- upon first tapping all units or local units": the list stays, its ALL lit, a type still narrows it)
			local all = {}
			for _, g in ipairs(byType(typesUnits(), combat)) do
				for _, u in ipairs(g.units) do
					all[#all + 1] = u
				end
			end
			keepTypes, allPicked = true, #all > 0
			selectUnits(all)
		end
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
			-- (Shift: 5, Ctrl: 20, as BAR's build menu; both are 100: +20 sent both and queued 100, 2026-11-10)
			runCommand(factoryItem, false, item.n == 5, item.n == 20)
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
				cameraTo(x, y, z, k == "commander")
			end
		end
	elseif k == "base" then -- the camera where the commander began (the start spot)
		local x, y, z = Spring.GetTeamStartPosition(myTeam())
		if x and (x > 0 or z > 0) then
			cameraTo(x, y, z, true)
		end
	elseif k == "retreat" and WG.BarDroidRetreat then -- (bardroid_retreat.lua: hurt units fall back, on or off)
		if WG.BarDroidRetreat.allowed and not WG.BarDroidRetreat.allowed() then
			if WG.BarDroidPad and WG.BarDroidPad.say then
				WG.BarDroidPad.say("THIS GAME'S HOST TURNED OFF UNIT CONTROL WIDGETS")
			end
		else
			WG.BarDroidRetreat.set(not WG.BarDroidRetreat.on())
		end
	elseif k == "presets" and WG.BarDroidPresets then -- (bardroid_presets.lua: the presets over the grid)
		WG.BarDroidPresets.open()
	elseif k == "preset" and WG.BarDroidPresets then -- (one picked: the map's next tap is where they go)
		WG.BarDroidPresets.pick(item.id)
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
	if rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets" then -- (the whole grid)
		local r = homeRect()
		return r, rightScroll, rightItems, 2, floor((r[3] - r[1] - L.gap) / 2),
			(rightKind == "home" or rightKind == "presets") and floor((r[4] - r[2] + L.gap) / (L.homeRows or HOME_ROWS)) - L.gap
			or floor(L.btnH * 1.5)
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
		if allPicked then -- (all of the list picked: LOCAL or ALL UNITS' first tap)
			selector(r)
		end
		return
	end
	-- (a pregame option picked: lit as BAR's menu lights its picked cell)
	local pb = item.kind == "pregame" and WG["pregame-build"]
	-- (the building PLACE will build: BAR's picked cell (the picture closer, gold light) and the gold line of the build
	-- menu copy's picked cell; FlowUI's selector alone was a faint border nobody saw, dev phone screenshot 2026-11-11)
	local picked = item.kind == "build" and item.id and activeBuild() == item.id
	unitTile(item.defID, r, picked or (pb and pb.getPreGameDefID and pb.getPreGameDefID() == item.defID) or false)
	if picked and WG.BarDroidStyle then
		WG.BarDroidStyle.outline(r[1], r[2], r[3], r[4], WG.BarDroidStyle.GOLD, 1, max(2, floor(w * 0.04)))
	end
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
	if item.kind == "preset" and WG.BarDroidPresets then -- (its thumbnail, its name under it)
		button(r)
		local lh = (r[4] - r[2]) * 0.2
		WG.BarDroidPresets.drawThumb(item.id, { r[1], r[2] + lh, r[3], r[4] })
		textIn(item.label or "", r[1], r[2], r[3], r[2] + lh * 1.2, lh * 0.62, "\255\240\240\240", font)
		return
	end
	local _, activeID = spGetActiveCommand()
	local lit = item.kind == "order" and activeID == item.id
	-- (a preset armed: PRESETS in gold with its name, as long as the map waits for its drag; it looked like any button
	-- once the pick's note had gone, dev phone screenshot 2026-11-11)
	local armed, armedName = false, nil
	if item.kind == "presets" and WG.BarDroidPresets then
		armed, armedName = WG.BarDroidPresets.armed()
	end
	local on = armed or item.kind == "units" and typesFrom == item.from or item.kind == "multi" and multi
		or item.kind == "shape" and currentShape() == item.shape or item.kind == "filter" and selFilter == item.key
		or item.kind == "faction" and Spring.GetTeamRulesParam(myTeam(), "startUnit") == item.startUnit
		or item.kind == "sharestep" and shareFraction == item.value or item.kind == "retreat" and item.on
	if on then -- (picked: BAR's gold)
		button(r, { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 })
	else
		button(r)
	end
	-- (the home grid's tall buttons: their words a little larger than the order buttons', not by their height)
	textIn(armedName or item.label or "", r[1], r[2], r[3], r[4], min((r[4] - r[2]) * 0.34, L.btnH * ((item.h or 1) > 1 and 0.6 or 0.46)),
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
	if side == "right" and rightKind == "presets" and WG.BarDroidPresets then -- (the presets' X, in the corner)
		local x = WG.BarDroidPresets.closeRect(r)
		button(x, { 0.42, 0.1, 0.08, 0.95 }, { 0.75, 0.25, 0.2, 0.95 })
		textIn("\195\151", x[1], x[2], x[3], x[4], (x[4] - x[2]) * 0.7, "\255\250\240\240", bold)
	end
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
	-- (no "tap the map for the spot" under it any more, Kailil 2026-11-10: the panel's dim green says it is waiting)
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
	local x = r[1] + floor((r[3] - r[1]) / 3) + L.pad -- (the row's left third is INSERT, its words beside the tile, drawn
	-- live with QUEUE's: drawQueueZones)
	bold:Print("\255\255\255\255" .. name, x, r[4] - h * 0.36, h * 0.24, "o")
	L.selCountEnd = nil -- (where the count line ends: the camera pad's words keep right of it, drawMode)
	if n > 1 then
		local count = n .. " units, " .. bestN .. " of this type"
		font:Print("\255\200\200\200" .. count, x, r[4] - h * 0.62, h * 0.17, "o")
		L.selCountEnd = x + font:GetTextWidth(count) * h * 0.17
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
-- The energy box also has BAR's wind and tide indicators, as its top bar draws them (its blades turning with the wind,
-- the speed, the map's range; the waves and the tidal speed where the map has water for tidal generators), which are off
-- upright (Kailil, 2026-11-10: "the wind and wave details widgets should be present in the energy portion. There's
-- plenty of empty space ... make the numbers size bigger ... keep the overall size of the metal and energy boxes")
local BLADES, WAVES = ":n:LuaUI/Images/wind-blades.png", ":n:LuaUI/Images/tidal-waves.png"
local windTurn, tideShown = 0, nil
local function tideRelevant() -- (BAR's top bar's test: water 20 deep somewhere, where tidal generators can stand)
	if tideShown == nil then
		local low = select(3, Spring.GetGroundExtremes()) or 0
		tideShown = (Spring.GetTidal() or 0) > 0 and low - ((Spring.GetModOptions() or {}).map_waterlevel or 0) <= -20
	end
	return tideShown
end
-- The wind's or the tide's reading: its picture turning before the number (behind it, as BAR's top bar has it, the
-- blades' hub sat on the decimal point at this size: "6.5" read "6:5", dev phone 2026-11-10), the wind's range after it
local function indicatorSlot(text, s)
	return s * 0.95 + bold:GetTextWidth(text) * s * 0.62
end
local function indicatorWidth(text, s, extra)
	return indicatorSlot(text, s) + (extra and s * 0.14 + font:GetTextWidth(extra) * s * 0.5 or 0)
end
local function drawIndicator(tex, turn, x, cy, s, text, extra)
	local slot = indicatorSlot(text, s)
	gl.Color(1, 1, 1, 0.8)
	gl.Texture(tex)
	gl.PushMatrix()
	gl.Translate(x + s * 0.42, cy, 0)
	gl.Rotate(turn, 0, 0, 1)
	gl.TexRect(-s * 0.42, -s * 0.42, s * 0.42, s * 0.42)
	gl.PopMatrix()
	gl.Texture(false)
	gl.Color(1, 1, 1, 1)
	local size = s * 0.62
	bold:Print("\255\255\255\255" .. text, x + s * 0.95, cy - size * 0.32, size, "o")
	if extra then
		font:Print("\255\185\185\185" .. extra, x + slot + s * 0.14, cy - size * 0.32, s * 0.5, "o")
	end
end
local function drawResources()
	local r = L.res
	local w = floor((r[3] - r[1] - L.pad) / 2)
	local h = r[4] - r[2]
	local pad = max(2, floor(h * 0.1))
	local barH = max(3, floor(h * 0.12))
	local rowH = h - 3 * pad - barH -- (the text above a thin bar: the numbers about two fifths bigger than they were)
	local big, small = rowH * 0.92, rowH * 0.62
	for i, res in ipairs({ "metal", "energy" }) do
		local cur, storage, _, income, expense = Spring.GetTeamResources(myTeam(), res)
		local x0 = r[1] + (i - 1) * (w + L.pad)
		local x1 = x0 + w
		local box = { x0, r[2], x1, r[4] }
		panel(box)
		if cur and storage then
			local by0, by1 = r[2] + pad, r[2] + pad + barH
			local frac = storage > 0 and max(0, min(1, cur / storage)) or 0
			gl.Color(0.1, 0.1, 0.1, 0.9)
			gl.Rect(x0 + pad, by0, x1 - pad, by1)
			if res == "metal" then
				gl.Color(0.85, 0.85, 0.85, 1)
			else
				gl.Color(1, 0.86, 0.15, 1)
			end
			gl.Rect(x0 + pad, by0, x0 + pad + (x1 - x0 - 2 * pad) * frac, by1)
			gl.Color(1, 1, 1, 1)
			local cy = by1 + pad + rowH / 2 -- (the row's middle)
			local amount = short(cur)
			bold:Print((res == "metal" and "\255\225\225\225" or "\255\255\230\080") .. amount, x0 + pad * 1.5,
				cy - big * 0.34, big, "o")
			local flows = string.format("\255\120\230\120+%s \255\240\110\100-%s", short(income or 0), short(expense or 0))
			local fx = x0 + pad * 1.5 + bold:GetTextWidth(amount) * big + pad * 2
			font:Print(flows, fx, cy - small * 0.32, small, "o")
			local left = fx + font:GetTextWidth(flows) * small + pad * 2 -- (where the right side's things must stop)
			local rx = x1 - pad * 1.5
			font:Print("\255\150\150\150" .. short(storage), rx, cy - small * 0.32, small * 0.85, "ro")
			rx = rx - font:GetTextWidth(short(storage)) * small * 0.85 - pad * 3
			if res == "energy" then
				local s = rowH
				local tide = tostring(floor(Spring.GetTidal() or 0))
				if tideRelevant() and rx - indicatorWidth(tide, s) >= left then
					rx = rx - indicatorWidth(tide, s)
					drawIndicator(WAVES, 0, rx, cy, s, tide)
					rx = rx - pad * 3
				end
				if (Game.windMax or 0) > 0 then
					local range = floor(Game.windMin or 0) .. "-" .. floor(Game.windMax or 0)
					local wind = string.format("%.1f", select(4, Spring.GetWind()) or 0)
					if rx - indicatorWidth(wind, s, range) >= left then
						drawIndicator(BLADES, windTurn, rx - indicatorWidth(wind, s, range), cy, s, wind, range)
					elseif rx - indicatorWidth(wind, s) >= left then
						drawIndicator(BLADES, windTurn, rx - indicatorWidth(wind, s), cy, s, wind)
					end
				end
			end
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
	-- the remove-order buttons at the strip's right end (unqShown): the first or the last order of the units picked, or
	-- of a factory's build queue (removeOrder)
	local x1 = r[3]
	if unqShown then
		local h = r[4] - r[2]
		local bw = floor(h * 1.7)
		for i, which in ipairs({ "first", "last" }) do
			local b = { r[3] - (3 - i) * bw + 3, r[2] + 3, r[3] - (2 - i) * bw - 3, r[4] - 3, unq = which }
			L.groupRects[#L.groupRects + 1] = b
			button(b, { 0.3, 0.09, 0.08, 0.9 }, { 0.46, 0.13, 0.11, 0.9 })
			textIn("\195\151 " .. which:upper(), b[1], b[2], b[3], b[4], h * 0.26, "\255\255\228\218", bold)
		end
		x1 = r[3] - 2 * bw
	end
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
	-- units picked: a "+ NEW" tile after the groups puts their types in the next free group (BAR's auto groups: a
	-- number held by an auto group's type with no unit left is not free)
	local free
	if #sel > 0 then
		local taken = {}
		local A = WG.autogroup
		for _, gr in pairs(A and A.getGroups and A.getGroups() or {}) do
			taken[tonumber(gr) or -1] = true
		end
		for n = 1, 9 do
			if (not groups[n] or groups[n] == 0) and not taken[n] then
				free = n
				break
			end
		end
	end
	if #list == 0 and not free then
		textIn("Groups: pick units, then + NEW here", r[1], r[2], x1, r[4], h * 0.24, "\255\140\140\140")
		return
	end
	local w = min(h, floor((x1 - r[1]) / max(1, #list + (free and 1 or 0))))
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

-- the mode: the camera pad dims the dock a little and names itself; the open menu has BAR's gold along its top,
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
			-- (just above the picked unit's health bar, drawSelection's r[2] + h * 0.25: at the bottom it was printed over it;
			-- right of the count line, "6 units, 6 of this type", which it ran under: left out where it does not fit; the name
			-- alone, no "tap to use the menu" beside it: Kailil, 2026-11-09, the dock shows no hint text)
			local size, right = h * 0.15, s[3] - L.pad
			local from = (L.selCountEnd or 0) + L.pad * 2
			local label = "CAMERA PAD"
			if right - font:GetTextWidth(label) * size >= from then
				font:Print("\255\190\190\190" .. label, right, s[2] + h * 0.3, size, "ro")
			end
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
	local held = rightKind == "place" or rightKind == "presets" or rightKind == "share" or rightKind == "panel"
	local left = held and 1 or max(0, 1 - (t - lastTouch) / MENU_SECONDS) -- (placing, picking: no clock)
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
		local side, v, vx = line:match("^dockscroll (%a+) (%S+) ?(%S*)")
		if side and active and menu then
			local _, s, _, _, _, ch = half(side)
			if snapMax(s) == 0 then -- (nothing to scroll there: the drag pans the camera; X pixels, y down)
				panBy(tonumber(vx) or 0, -(tonumber(v) or 0))
			else
				snapBy(s, -(tonumber(v) or 0), ch + L.gap) -- (X pixels down: the rows follow the finger)
			end
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
			DG.stick = { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, tonumber(d) or 0 }
			local D = WG.BarDroidPadDgun
			if D and D.sticks then
				D.sticks(DG.stick[1], DG.stick[2], DG.stick[3], DG.stick[4])
			end
		end
		local slidWord = line:match("^dgunslide (%S+)")
		if slidWord then -- FIRE held: how far it is swiped, right (to AUTO) or left (below 0: back to FIRE); "off": let go
			local slid = tonumber(slidWord)
			if slid then
				if not DG.slide then -- (a new hold: its way from its first line, "-0.00" on AUTO)
					DG.slideLocked, DG.slideDir = false, slidWord:sub(1, 1) == "-" and -1 or 1
				end
				DG.slide = max(-1, min(1, slid))
				DG.slideLocked = DG.slideLocked or abs(DG.slide) >= 0.92
			elseif DG.slide then
				DG.slide, DG.slideLast, DG.slideOff = nil, DG.slide, now()
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
	startFit()
	factoryStates()
	windTurn =(windTurn + (select(4, Spring.GetWind()) or 0) * 0.2 * (dt or 0) * 30) % 360 -- (BAR's top bar's blade speed)
	drawingCursor()
	if rightKind == "dgun" then
		DG.follow(dt)
	else
		DG.unitWas = nil -- (the next start eases in again, the same commander too)
	end
	for _, s in ipairs({ leftScroll, rightScroll }) do
		if s.drag or s.t < 1 then
			markDirty() -- (rows moving: the texture drawn again each frame until they settle)
		end
		snapUpdate(s, dt)
	end
	local t = now()
	-- (a building picked: the menu stays open, PLACE, rotate and cancel take the first tap. Its 2 s ran out while the
	-- spot was picked on the map, the dock went back to the camera pad, and PLACE's tap only opened the menu again: "it
	-- keeps canceling a place", Kailil 2026-11-10, a Bot Lab; dev phone: the spot tapped, PLACE 2.5 s later, nothing)
	-- (so with the presets, the teammate picker and the resource panel over the grid: picked to be tapped next; the
	-- presets' thumbnails went back to the camera pad under a finger reaching for one, dev phone)
	if rightKind == "place" or rightKind == "presets" or rightKind == "share" or rightKind == "panel" then
		if not menu then
			setMenu(true)
		end
	elseif menu and not selecting and not leftScroll.drag and not rightScroll.drag and t - lastTouch > MENU_SECONDS then
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
-- FIRE's swipe track (Kailil, 2026-11-10: "the fire mode animation doesn't fully slide to the right and fill the auto.
-- And when you swipe left to disable auto, the animation doesn't work. Its just frozen"): FIRE's to the right, to the
-- grid's edge, AUTO at its end; AUTO's to the left, to the cancel corner, FIRE at its end (RtsTouch measures the swipe
-- against the same spans). The knob goes all the way, the track fills behind it (red to gold towards AUTO, gold to red
-- towards FIRE), chevrons run the way to go; locked (past 0.92) it is full, the knob gone into it, the word on it.
-- f: FIRE's rect, cancel: the cancel corner's, dir 1 right / -1 left, v 0..1, alpha
function DG.track(f, cancel, dir, v, alpha, locked, t)
	local fh = f[4] - f[2]
	local m = dir > 0 and 0.16 or 0.26 -- (the left one thinner: the cancel corner leaves it less room across)
	local y0, y1 = f[2] + floor(fh * m), f[4] - floor(fh * m)
	local k = dir > 0 and { f[3] + L.gap * 2, y0, L.right[3], y1 } or { cancel[3] + L.gap * 2, y0, f[1] - L.gap * 2, y1 }
	local tw, th = k[3] - k[1], k[4] - k[2]
	if tw < th * 1.3 or alpha <= 0 then
		return
	end
	local r, cy = th * 0.4, (k[2] + k[4]) / 2
	local from, to = dir > 0 and k[1] + r or k[3] - r, dir > 0 and k[3] - r or k[1] + r
	local kx = from + (to - from) * v
	gl.Color(0, 0, 0, 0.6 * alpha)
	gl.Rect(k[1], k[2], k[3], k[4])
	local c = dir > 0 and v or 1 - v
	gl.Color(0.86 + 0.14 * c, 0.14 + 0.66 * c, 0.11, (locked and 0.95 or 0.85) * alpha)
	if locked then
		gl.Rect(k[1], k[2], k[3], k[4])
	elseif dir > 0 then
		gl.Rect(k[1], k[2], kx, k[4])
	else
		gl.Rect(kx, k[2], k[3], k[4])
	end
	gl.Color(1, 1, 1, 0.3 * alpha)
	gl.Rect(k[1], k[2], k[3], k[2] + 1)
	gl.Rect(k[1], k[4] - 1, k[3], k[4])
	gl.Rect(k[1], k[2], k[1] + 1, k[4])
	gl.Rect(k[3] - 1, k[2], k[3], k[4])
	if not locked then
		local phase, cw = (t * 1.6) % 1, th * 0.22
		gl.LineWidth(max(2, floor(th * 0.09)))
		for i = 0, 2 do
			local q = (i + phase) / 3
			local x = from + (to - from) * q
			gl.Color(1, 1, 1, math.sin(q * math.pi) * 0.8 * alpha)
			gl.BeginEnd(GL.LINE_STRIP, function()
				gl.Vertex(x - dir * cw * 0.5, cy + cw)
				gl.Vertex(x + dir * cw * 0.5, cy)
				gl.Vertex(x - dir * cw * 0.5, cy - cw)
			end)
		end
		gl.LineWidth(1)
		gl.Color(1, 1, 1, alpha)
		disc(kx, cy, r, true)
	end
	if alpha > 0.2 then
		local ls = fh * 0.245 -- (from FIRE's height, as the right track's: the thinner left one's word came out small)
		local word = dir > 0 and "AUTO" or "FIRE"
		local tx = dir > 0 and k[3] - L.pad or k[1] + L.pad
		local ww = bold:GetTextWidth(word) * ls
		local mid = tx - dir * ww / 2
		-- (the white knob under the word: dark letters on it, the gold ones were lost there; dev phone screenshots)
		local onKnob = not locked and abs(kx - mid) < r + ww * 0.4
		local col = locked and (dir > 0 and "\255\050\024\000" or "\255\255\255\255")
			or onKnob and "\255\070\040\010"
			or (v >= 0.6 and "\255\255\200\064" or "\255\190\190\190")
		bold:Print(col .. word, tx, cy - ls * 0.36, ls, dir > 0 and "ro" or "o")
	end
	gl.Color(1, 1, 1, 1)
end

local function drawDgun()
	local p = dgunParts()
	local D = WG.BarDroidPadDgun
	local autoOn, autoFor = false, 0
	if D and D.auto then
		autoOn, autoFor = D.auto()
		autoFor = autoFor or 0
	end
	for i, s in ipairs({ p.l, p.r }) do
		gl.Color(0, 0, 0, 0.5)
		disc(s[1], s[2], s[3], true)
		gl.LineWidth(2)
		gl.Color(1, 1, 1, 0.3)
		disc(s[1], s[2], s[3], false)
		gl.LineWidth(1)
		local kx, ky = s[1] + DG.stick[i * 2 - 1] * s[3], s[2] - DG.stick[i * 2] * s[3]
		if i == 1 then
			gl.Color(0.8, 0.8, 0.8, 0.9)
		elseif autoOn then -- (full auto aims itself: the stick greyed, "AIM: AUTO"; its red read as aiming, screenshot)
			gl.Color(0.45, 0.45, 0.45, 0.6)
		else
			gl.Color(1, 0.3, 0.25, 0.95) -- (the aim: the shot's red, as its ring on the ground)
		end
		disc(kx, ky, s[3] * 0.36, true)
		gl.Color(1, 1, 1, 1)
		textIn(i == 1 and "MOVE" or autoOn and "AIM: AUTO" or "AIM", s[1] - s[3], s[2] - s[3] - L.btnH * 0.55, s[1] + s[3],
			s[2] - s[3] - L.gap, L.btnH * 0.36, "\255\200\200\200", font)
	end
	local f, t = p.fire, now()
	local fw, fh = f[3] - f[1], f[4] - f[2]
	local e = max(2, floor(L.pad * 0.35))
	if DG.autoWas and not autoOn then
		DG.autoOffAt = t -- (full auto just ended: the gold drains out of the button, below)
	end
	DG.autoWas = autoOn
	if autoOn then -- full auto: FIRE turns gold-orange, stripes run across it, its edge pulses; AUTO on it
		button(f, { 0.55, 0.2, 0.02, 1 }, { 0.95, 0.48, 0.07, 1 })
		local step = fh * 0.6
		local shift = (t * fh * 1.4) % step
		gl.Scissor(f[1], f[2], fw, fh)
		gl.Color(1, 0.9, 0.4, 0.18)
		for sx = f[1] - fh - step + shift, f[3], step do
			gl.BeginEnd(GL.QUADS, function()
				gl.Vertex(sx, f[2])
				gl.Vertex(sx + step * 0.45, f[2])
				gl.Vertex(sx + step * 0.45 + fh, f[4])
				gl.Vertex(sx + fh, f[4])
			end)
		end
		gl.Scissor(false)
		local pulse = 0.5 + 0.5 * math.sin(t * 6)
		gl.Color(1, 0.85, 0.35, 0.45 + 0.45 * pulse)
		gl.Rect(f[1], f[2], f[3], f[2] + e)
		gl.Rect(f[1], f[4] - e, f[3], f[4])
		gl.Rect(f[1], f[2], f[1] + e, f[4])
		gl.Rect(f[3] - e, f[2], f[3], f[4])
		if autoFor < 0.3 then -- (as it engages the gold fills the button from the left, the red going out at the right)
			local w = (1 - autoFor / 0.3) ^ 2
			gl.Color(0.86, 0.14, 0.11, 0.95)
			gl.Rect(f[3] - fw * w, f[2], f[3], f[4])
		end
		if autoFor < 0.6 then -- (and a flash, and the edge thrown out around the button)
			local a, grow = 1 - autoFor / 0.6, autoFor / 0.6 * fh * 0.6
			gl.Color(1, 0.92, 0.6, 0.55 * a)
			gl.Rect(f[1], f[2], f[3], f[4])
			gl.Color(1, 0.8, 0.3, 0.8 * a)
			gl.Rect(f[1] - grow, f[2] - grow, f[3] + grow, f[2] - grow + e)
			gl.Rect(f[1] - grow, f[4] + grow - e, f[3] + grow, f[4] + grow)
			gl.Rect(f[1] - grow, f[2] - grow, f[1] - grow + e, f[4] + grow)
			gl.Rect(f[3] + grow - e, f[2] - grow, f[3] + grow, f[4] + grow)
		end
		gl.Color(1, 1, 1, 1)
	else
		button(f, { 0.5, 0.06, 0.05, 1 }, { 0.86, 0.14, 0.11, 1 })
		local off = DG.autoOffAt and t - DG.autoOffAt
		if off and off < 0.4 then -- (full auto ended: the gold drains to the left, a white flash going with it)
			local w = (1 - off / 0.4) ^ 2
			gl.Color(0.95, 0.48, 0.07, 0.95)
			gl.Rect(f[1], f[2], f[1] + fw * w, f[4])
			gl.Color(1, 1, 1, 0.5 * w)
			gl.Rect(f[1], f[2], f[3], f[4])
			gl.Color(1, 1, 1, 1)
		end
	end
	-- whether it can fire now: a thin bar along FIRE's foot, white as the D-gun reloads, amber (and the word dimmed)
	-- while the team lacks a shot's energy; none once it is ready
	local loaded, energy = 1, 1
	if D and D.ready then
		loaded, energy = D.ready()
		loaded, energy = loaded or 1, energy or 1
	end
	local lacking = energy < 1
	local part = lacking and energy or loaded
	if part < 1 then
		local bh = max(3, floor(fh * 0.07))
		local x0, x1 = f[1] + e * 2, f[3] - e * 2
		gl.Color(0, 0, 0, 0.45)
		gl.Rect(x0, f[2] + e * 2, x1, f[2] + e * 2 + bh)
		if lacking then
			gl.Color(1, 0.7, 0.2, 0.95)
		else
			gl.Color(1, 1, 1, 0.9)
		end
		gl.Rect(x0, f[2] + e * 2, x0 + (x1 - x0) * part, f[2] + e * 2 + bh)
		gl.Color(1, 1, 1, 1)
	end
	textIn(autoOn and "AUTO" or "FIRE", f[1], f[2], f[3], f[4], fh * 0.42,
		lacking and "\255\200\160\150" or "\255\255\255\255", bold)
	-- FIRE held: its swipe's track (DG.track). Let go past 0.92 the track stays full and fades; short of it it runs back
	local held = DG.slide
	local fade = not held and DG.slideOff and t - DG.slideOff < 0.3 and 1 - (t - DG.slideOff) / 0.3
	if held or fade then
		local s = held or DG.slideLast or 0
		local locked = DG.slideLocked
		local v = locked and 1 or abs(s) * (held and 1 or fade)
		DG.track(f, p.cancel, DG.slideDir or (s < 0 and -1 or 1), v, held and 1 or fade, locked, t)
	end
	button(p.cancel)
	textIn("\226\156\149", p.cancel[1], p.cancel[2], p.cancel[3], p.cancel[4], (p.cancel[4] - p.cancel[2]) * 0.5,
		"\255\255\150\140", bold)
	resetGL()
end

-- The selection row as two buttons (Kailil, 2026-11-10: "turn the entire selected unit description into the queue
-- button 2/3s is queue on the right. And 1/3 is alt queue modifier so we can insert things in front of queue"):
-- bardroid_pad.lua's QUEUE (a sticky Shift) and INSERT (BAR's CommandInsert: the front of the queue) take the presses;
-- here their words, gold and a gold edge while one is on, drawn live over the row
local function queueZones()
	local s = L.sel
	local third = s[1] + floor((s[3] - s[1]) / 3)
	return { s[1], s[2], third, s[4] }, { third, s[2], s[3], s[4] }
end
local function drawQueueZones()
	if not showSel then
		return
	end
	local Pd = WG.BarDroidPad
	local qOn, iOn = false, false
	if Pd and Pd.queueState then
		qOn, iOn = Pd.queueState()
	end
	local ins, que = queueZones()
	local h = ins[4] - ins[2]
	local e = max(2, floor(L.pad * 0.3))
	for _, z in ipairs({ { ins, iOn }, { que, qOn } }) do
		local r = z[1]
		if z[2] then
			gl.Color(1, 0.78, 0.25, 0.14)
			gl.Rect(r[1], r[2], r[3], r[4])
			gl.Color(1, 0.78, 0.25, 0.95)
			gl.Rect(r[1], r[2], r[3], r[2] + e)
			gl.Rect(r[1], r[4] - e, r[3], r[4])
			gl.Rect(r[1], r[2], r[1] + e, r[4])
			gl.Rect(r[3] - e, r[2], r[3], r[4])
		end
	end
	gl.Color(1, 1, 1, 0.16) -- (where one ends and the other begins)
	gl.Rect(ins[3] - 1, ins[2] + h * 0.18, ins[3] + 1, ins[4] - h * 0.18)
	gl.Color(1, 1, 1, 1)
	local size = h * 0.2
	local gold, white = "\255\255\200\064", "\255\235\235\235"
	bold:Print((iOn and gold or white) .. "INSERT", (ins[1] + h + ins[3]) / 2, (ins[2] + ins[4]) / 2 - size * 0.35, size, "co")
	bold:Print((qOn and gold or white) .. "QUEUE", que[3] - L.pad, que[4] - h * 0.36, size, "ro")
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
	drawQueueZones()
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
	if rightKind == "presets" and WG.BarDroidPresets and inRect(x, y, WG.BarDroidPresets.closeRect(homeRect())) then
		WG.BarDroidPresets.close() -- (the presets' X)
		return true
	end
	local wide = rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets"
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
	-- (empty space in the open menu: a drag there pans the camera as the camera pad does; Kailil, 2026-11-10: "if I grab
	-- empty space in the ui and moved my finger around, let that pan my camera"; a half whose rows scroll keeps its drag)
	local empty -- (a half with nothing to scroll: a drag anywhere on it pans, as the fingers' dockscroll lines do)
	if side then
		local _, s = half(side)
		empty = snapMax(s) == 0
	else
		empty = not (inRect(x, y, L.res) or (showSel and inRect(x, y, L.sel)))
		for _, gr in ipairs(L.groupRects or {}) do
			empty = empty and not inRect(x, y, gr)
		end
	end
	press = { side = side, x = x, y = y, button = btn, lastY = y, lastT = now(), vel = 0, empty = empty,
		panX = x, panY = y }
	return true -- (the dock is the dock's: no press goes through to the map under it)
end


function widget:MouseMove(x, y)
	if slide then
		setSlider(slide.item, slide.rect, x)
		touched()
		return
	end
	local p = press
	if p and p.empty then
		if not p.moved and abs(x - p.x) + abs(y - p.y) < vsx * 0.012 then
			return
		end
		p.moved = true
		panBy(x - p.panX, y - p.panY)
		p.panX, p.panY = x, y
		touched()
		return
	end
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
	if p.empty and (p.moved or not p.side) then -- (a pan, or a tap on nothing; a tap on a half with nothing to scroll is
		-- its button's: those halves were all "empty" for the pan, and their buttons took no taps, 2026-11-10)
		return true
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
	if L.groupRects then -- a control group's picture: those units; "+ NEW": the types picked become the next free group,
		-- every one of them now and later (Kailil, 2026-11-10: "Unit groups at the bottom should use the unit group vanilla
		-- behavior. Assigning a unit type to a group", BAR's Auto Group, its Alt+number); a long press on a picture takes
		-- that group's assignment off ("hold the unit pictures and it unassign the group assignment")
		for _, gr in ipairs(L.groupRects) do
			if inRect(p.x, p.y, gr) then
				local A = WG.autogroup
				if gr.unq then
					removeOrder(gr.unq == "last")
				elseif gr.new then
					if A and A.addCurrentSelectionToAutogroup then
						A.addCurrentSelectionToAutogroup(gr.new)
					else -- (no Auto Group: the engine's own group of the units picked, as BAR's Ctrl+number)
						Spring.SendCommands("group set " .. gr.new)
					end
					Spring.Echo("[bardroid-portrait] group " .. gr.new .. " made") -- (tools)
				elseif btn == 3 then
					local types = A and A.getGroups and A.getGroups()
					for defID, g in pairs(types or {}) do
						if tonumber(g) == gr.group then
							types[defID] = nil
						end
					end
					for _, u in ipairs(Spring.GetGroupUnits(gr.group) or {}) do
						Spring.SetUnitGroup(u, -1)
					end
					Spring.Echo("[bardroid-portrait] group " .. gr.group .. " unassigned")
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
		queueRect = function() -- (bardroid_pad.lua's QUEUE, the fingers' sticky Shift: the selection row's right two
			-- thirds; none while nothing is picked)
			if not (active and showSel) then
				return nil
			end
			local _, q = queueZones()
			return q
		end,
		insertRect = function() -- (its INSERT, BAR's CommandInsert: the row's left third)
			if not (active and showSel) then
				return nil
			end
			return (queueZones())
		end,
		menu = function()
			return menu
		end,
		refresh = refresh, -- (bardroid_presets.lua: its presets opened or closed)
		-- (tools/dock-phone-test.ps1: the first item of a half the test function takes: its cell (GL pixels, where it is
		-- drawn now: off the half when scrolled away) and the item)
		itemCell = function(side, test)
			for i, it in ipairs(side == "left" and leftItems or rightItems) do
				if test(it) then
					return cellRect(side, i), it
				end
			end
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
