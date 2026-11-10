-- BAR Droid presets: preset orders for the picked combat units (Kailil, 2026-11-10: "a PRESETS button ... the whole dock
-- shows the presets as 2 x 2 thumbnails ... closed by an X in the corner or Android's Back"; repeated moves along paths
-- that make units hard to hit, and formations by their types' strengths). Touch play's automation is his and BAR's
-- developers' call (GiveOrder). The upright dock (bardroid_portrait.lua) shows PRESETS among the orders while units
-- that fight are picked, and the presets over its whole grid; a preset tapped closes them and the next tap on the map is
-- where the picked units go (Back, or a press of the right button, lets it go).
-- WG.BarDroidPresets: fits(units), isOpen(), open(), close(), items(), pick(id), drawThumb(id, rect), closeRect(rect),
-- armed(). Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid presets",
		desc = "Preset orders for the picked units: zigzags and formations",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -20, -- (before the dock, -10, and BAR's menus: the destination's tap and Back are its first)
		enabled = true,
	}
end

local ZIG_STEP = 230 -- elmos along the way between the zigzag's turns
local ZIG_SIDE = 170 -- elmos to each side of the way at its turns
local ZIG_MAX_TURNS = 30
local BLOB = 260 -- elmos: the group's shape kept, at most this far from its middle
local KEY_ESCAPE = 27

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID

local opened = false
local armedFor -- { id, units }: a preset picked, the map's next tap is its destination

local function say(text)
	local P = WG.BarDroidPad
	if P and P.say then
		P.say(text)
	end
end
local function refreshDock()
	local D = WG.BarDroidPortrait
	if D and D.refresh then
		D.refresh()
	end
end

local function fighter(ud)
	return ud and ud.canMove and not ud.isBuilding and (ud.speed or 0) > 0 and not ud.isBuilder
		and #(ud.weapons or {}) > 0
end
-- the picked units presets order: those that move and fight (builders and buildings keep their orders)
local function combatUnits(units)
	local out = {}
	for _, u in ipairs(units or {}) do
		if fighter(UnitDefs[spGetUnitDefID(u) or -1]) then
			out[#out + 1] = u
		end
	end
	return out
end

local function onMap(x, z)
	return math.max(32, math.min(Game.mapSizeX - 32, x)), math.max(32, math.min(Game.mapSizeZ - 32, z))
end
local function ground(x, z)
	x, z = onMap(x, z)
	return { x, Spring.GetGroundHeight(x, z), z }
end
-- the units' middle and each one's place from it (the group's shape, drawn in to BLOB)
local function shape(units)
	local cx, cz, n, at = 0, 0, 0, {}
	for _, u in ipairs(units) do
		local x, _, z = spGetUnitPosition(u)
		if x then
			at[u] = { x, z }
			cx, cz, n = cx + x, cz + z, n + 1
		end
	end
	if n == 0 then
		return nil
	end
	cx, cz = cx / n, cz / n
	local far = 0
	for _, p in pairs(at) do
		p[1], p[2] = p[1] - cx, p[2] - cz
		far = math.max(far, math.sqrt(p[1] * p[1] + p[2] * p[2]))
	end
	local k = far > BLOB and BLOB / far or 1
	for _, p in pairs(at) do
		p[1], p[2] = p[1] * k, p[2] * k
	end
	return cx, cz, at
end
local function way(cx, cz, tx, tz)
	local dx, dz = tx - cx, tz - cz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1 then
		return 0, 1, 0
	end
	return dx / d, dz / d, d
end
local function orders(u, list)
	local cmds = {}
	for i, p in ipairs(list) do
		cmds[#cmds + 1] = { CMD.MOVE, p, i == 1 and {} or { "shift" } }
	end
	if #cmds > 0 then
		Spring.GiveOrderArrayToUnitArray({ u }, cmds)
	end
end

-- ZIGZAG: to the destination in big turns from side to side (slow shots aimed where a unit was going land beside it),
-- each unit keeping its place in the group
local function zigzag(units, tx, tz)
	local cx, cz, at = shape(units)
	if not cx then
		return 0
	end
	local fx, fz, d = way(cx, cz, tx, tz)
	local px, pz = -fz, fx
	local turns = math.min(ZIG_MAX_TURNS, math.floor(d / ZIG_STEP))
	local n = 0
	for u, o in pairs(at) do
		local list = {}
		for k = 1, turns do
			local side = (k % 2 == 1) and ZIG_SIDE or -ZIG_SIDE
			list[#list + 1] = ground(cx + fx * ZIG_STEP * k + px * side + o[1], cz + fz * ZIG_STEP * k + pz * side + o[2])
		end
		list[#list + 1] = ground(tx + o[1], tz + o[2])
		orders(u, list)
		n = n + 1
	end
	return n
end

-- Formations (research of 2026-11-10: BAR's wiki and unit pages, the Recoil engine's source; docs/DELIVERY.md). Each
-- unit by its role: brawlers and the short-ranged (range up to 400: Pawns, Grunts, Maces, Stouts, Pounders) in the front
-- row; skirmishers, rockets and AA (BAR's unitgroup "aa") a row behind, staggered; artillery (a high trajectory, or a
-- range of 650 or more) behind them by its range over the front's less 100 (150 at least); planes their own group,
-- fighters ahead of bombers and transports. The units form up where they stand, facing the destination, then go there
-- as one: a fight order with Ctrl and Shift given to them as the selection, which the engine moves at the slowest one's
-- speed keeping each one's place (SelectedUnitsAI; Ctrl on orders given unit by unit does not), so the artillery stays
-- at the back while the formation moves.
local ROW_MAX = 12 -- units a row; more make another row behind it
local FORM_AHEAD = 80 -- elmos: where the front forms up, ahead of the group's middle (toward the destination)
local AIR_LEAD = 300 -- elmos the fighters fly ahead of the bombers and transports
local roleOf = {}
local function role(defID)
	local r = roleOf[defID]
	if r then
		return r
	end
	local ud = UnitDefs[defID]
	local aa = ud.customParams and ud.customParams.unitgroup == "aa"
	local range = ud.maxWeaponRange or 0
	if ud.canFly then
		r = aa and "fighter" or "air"
	elseif ud.highTrajectoryType == 1 or (range >= 650 and not aa) then
		r = "art"
	elseif aa then
		r = "aa"
	elseif range <= 400 then
		r = "front"
	else
		r = "mid"
	end
	roleOf[defID] = { r, range }
	return roleOf[defID]
end

-- each unit's place (along, across) in formation-local elmos: along toward the destination, the front row at 0
local function layout(units, style)
	local spacing = style == "spread" and 96 or 64
	local rowGap = style == "spread" and 120 or 80
	local rows = { front = {}, mid = {}, art = {} }
	local frontRange, artRange = 0, math.huge
	for _, u in ipairs(units) do
		local r = role(spGetUnitDefID(u))
		local kind = (r[1] == "aa") and "mid" or r[1]
		rows[kind][#rows[kind] + 1] = u
		if kind == "front" then
			frontRange = math.max(frontRange, r[2])
		elseif kind == "art" then
			artRange = math.min(artRange, r[2])
		end
	end
	if #rows.front == 0 then -- (no brawlers: the middle row leads)
		rows.front, rows.mid = rows.mid, {}
		for _, u in ipairs(rows.front) do
			frontRange = math.max(frontRange, role(spGetUnitDefID(u))[2])
		end
	end
	local backAt = artRange < math.huge and math.min(600, math.max(150, artRange - frontRange - 100)) or 0
	local place, rowN = {}, 0
	local function putRow(list, startAlong, gap)
		local a = startAlong
		for i = 1, #list, ROW_MAX do
			local n = math.min(ROW_MAX, #list - i + 1)
			local stagger = (rowN % 2) * spacing * 0.5 -- (every other row half a place over: a checkerboard)
			for k = 0, n - 1 do
				place[list[i + k]] = { a, (k - (n - 1) / 2) * spacing + stagger }
			end
			rowN = rowN + 1
			a = a - gap
		end
		return a
	end
	local along = putRow(rows.front, 0, rowGap)
	along = putRow(rows.mid, along, rowGap)
	putRow(rows.art, math.min(along, -backAt), rowGap)
	if style == "concave" then -- (the ends forward: a quarter of the front's width at its tips)
		local half = 0
		for _, p in pairs(place) do
			half = math.max(half, math.abs(p[2]))
		end
		if half > 0 then
			for _, p in pairs(place) do
				p[1] = p[1] + (p[2] / half) ^ 2 * half * 0.5
			end
		end
	end
	return place
end
-- planes: the fighters a row AIR_LEAD ahead, the rest a row behind them
local function airLayout(units)
	local fighters, rest = {}, {}
	for _, u in ipairs(units) do
		local r = role(spGetUnitDefID(u))
		if r[1] == "fighter" then
			fighters[#fighters + 1] = u
		else
			rest[#rest + 1] = u
		end
	end
	local place = {}
	for _, list in ipairs({ { fighters, #rest > 0 and AIR_LEAD or 0 }, { rest, 0 } }) do
		local n = #list[1]
		for k, u in ipairs(list[1]) do
			place[u] = { list[2], (k - 1 - (n - 1) / 2) * 70 }
		end
	end
	return place
end

local groupOrders = {} -- { frame, units, x, z }: the move as one, a frame after the form-up orders (SelectedUnitsAI
-- measures each unit's place from where its queue ends)
-- forms the units up where they stand (place: along, across), facing (fx, fz), then sends them to (tx, tz) as one
local function formUp(units, place, fx, fz, tx, tz)
	if #units == 0 then
		return 0
	end
	local cx, cz = shape(units)
	local px, pz = -fz, fx
	-- (each row's units to its places by their own side to side order: the fewest crossings)
	local byRow = {}
	for _, u in ipairs(units) do
		local p = place[u]
		local key = string.format("%.0f", p[1])
		byRow[key] = byRow[key] or { slots = {}, units = {} }
		local row = byRow[key]
		row.slots[#row.slots + 1] = p
		row.units[#row.units + 1] = u
	end
	local ax, az = cx + fx * FORM_AHEAD, cz + fz * FORM_AHEAD
	-- (the move as one sends each unit to the destination plus its place from the formation's middle: the destination
	-- drawn in so every place is on the map; on the map's edge the places past it went nowhere and those units stayed)
	local sx, sz, x0, x1, z0, z1 = 0, 0, math.huge, -math.huge, math.huge, -math.huge
	for _, u in ipairs(units) do
		local p = place[u]
		local wx, wz = fx * p[1] + px * p[2], fz * p[1] + pz * p[2]
		sx, sz = sx + wx, sz + wz
		x0, x1, z0, z1 = math.min(x0, wx), math.max(x1, wx), math.min(z0, wz), math.max(z1, wz)
	end
	sx, sz = sx / #units, sz / #units
	local m = 48
	if Game.mapSizeX - m - (x1 - sx) >= m - (x0 - sx) then
		tx = math.max(m - (x0 - sx), math.min(Game.mapSizeX - m - (x1 - sx), tx))
	end
	if Game.mapSizeZ - m - (z1 - sz) >= m - (z0 - sz) then
		tz = math.max(m - (z0 - sz), math.min(Game.mapSizeZ - m - (z1 - sz), tz))
	end
	local n = 0
	for _, row in pairs(byRow) do
		table.sort(row.slots, function(a, b)
			return a[2] < b[2]
		end)
		local side = {}
		for _, u in ipairs(row.units) do
			local x, _, z = spGetUnitPosition(u)
			side[u] = x and ((x - cx) * px + (z - cz) * pz) or 0
		end
		table.sort(row.units, function(a, b)
			return side[a] < side[b]
		end)
		for i, u in ipairs(row.units) do
			local s = row.slots[i]
			Spring.GiveOrderToUnit(u, CMD.MOVE, ground(ax + fx * s[1] + px * s[2], az + fz * s[1] + pz * s[2]), 0)
			n = n + 1
		end
	end
	groupOrders[#groupOrders + 1] = { frame = Spring.GetGameFrame() + 2, units = units, x = tx, z = tz }
	return n
end
local function formation(style)
	return function(units, tx, tz)
		local cx, cz = shape(units)
		if not cx then
			return 0
		end
		local fx, fz = way(cx, cz, tx, tz)
		local land, air = {}, {}
		for _, u in ipairs(units) do
			local r = role(spGetUnitDefID(u))
			local list = (r[1] == "fighter" or r[1] == "air") and air or land
			list[#list + 1] = u
		end
		return formUp(land, layout(land, style), fx, fz, tx, tz) + formUp(air, airLayout(air), fx, fz, tx, tz)
	end
end

local PRESETS = {
	{ name = "ZIGZAG", run = zigzag, thumb = "zigzag" },
	{ name = "BATTLE LINE", run = formation("line"), thumb = "line" },
	{ name = "SPREAD", run = formation("spread"), thumb = "spread" },
	{ name = "CONCAVE", run = formation("concave"), thumb = "concave" },
}

-- the thumbnails: small drawings of what each does, in the rect (x0, y0, x1, y1), y up
local function line(points, width, c)
	gl.Color(c[1], c[2], c[3], c[4] or 1)
	gl.LineWidth(width)
	gl.BeginEnd(GL.LINE_STRIP, function()
		for _, p in ipairs(points) do
			gl.Vertex(p[1], p[2], 0)
		end
	end)
	gl.LineWidth(1)
end
local function dot(x, y, r, c)
	gl.Color(c[1], c[2], c[3], c[4] or 1)
	gl.Rect(x - r, y - r, x + r, y + r)
end
local THUMBS = {}
function THUMBS.zigzag(x0, y0, x1, y1)
	local w, h = x1 - x0, y1 - y0
	local pts = {}
	for k = 0, 6 do -- (from the bottom left up to the top right, side to side)
		local t = k / 6
		local side = (k == 0 or k == 6) and 0 or ((k % 2 == 1) and 1 or -1)
		pts[#pts + 1] = { x0 + w * (0.15 + 0.7 * t) + side * w * 0.11, y0 + h * (0.12 + 0.76 * t) - side * h * 0.06 }
	end
	line(pts, math.max(2, w * 0.018), { 0.95, 0.78, 0.25, 0.95 })
	local e = pts[#pts]
	dot(e[1], e[2], math.max(3, w * 0.025), { 0.95, 0.78, 0.25, 1 })
	for i = 1, 3 do -- (the group at the start)
		dot(x0 + w * (0.08 + i * 0.05), y0 + h * (0.1 + (i % 2) * 0.05), math.max(3, w * 0.022), { 0.4, 0.7, 1, 1 })
	end
end

-- the formations' drawings: rows of units (front orange, middle blue, artillery violet) and the way they face
local FRONT_C, MID_C, ART_C = { 0.95, 0.6, 0.25, 1 }, { 0.4, 0.7, 1, 1 }, { 0.75, 0.5, 0.95, 1 }
local function arrowUp(x, y0, y1, w)
	line({ { x, y0 }, { x, y1 } }, math.max(2, w * 0.6), { 0.95, 0.78, 0.25, 0.95 })
	gl.Color(0.95, 0.78, 0.25, 0.95)
	gl.BeginEnd(GL.TRIANGLES, function()
		gl.Vertex(x - w * 2.2, y1 - w * 2.6, 0)
		gl.Vertex(x + w * 2.2, y1 - w * 2.6, 0)
		gl.Vertex(x, y1 + w * 0.8, 0)
	end)
end
local function rowsThumb(x0, y0, x1, y1, gapX, gapY, curve)
	local w, h = x1 - x0, y1 - y0
	local r = math.max(3, w * 0.025)
	local cx = x0 + w / 2
	for _, row in ipairs({ { 6, 0.56, FRONT_C, 0 }, { 5, 0.56 - gapY, MID_C, 0.5 }, { 2, 0.56 - gapY * 2.4, ART_C, 0 } }) do
		local n = row[1]
		for k = 0, n - 1 do
			local off = (k - (n - 1) / 2 + row[4]) * gapX
			local lift = curve and row[3] == FRONT_C and (off / (gapX * 2.5)) ^ 2 * h * 0.1 or 0
			dot(cx + off * w, y0 + h * row[2] + lift, r, row[3])
		end
	end
	arrowUp(cx, y0 + h * 0.7, y0 + h * 0.9, math.max(1.5, w * 0.012))
end
function THUMBS.line(x0, y0, x1, y1)
	rowsThumb(x0, y0, x1, y1, 0.1, 0.17)
end
function THUMBS.spread(x0, y0, x1, y1)
	rowsThumb(x0, y0, x1, y1, 0.15, 0.21)
end
function THUMBS.concave(x0, y0, x1, y1)
	rowsThumb(x0, y0, x1, y1, 0.1, 0.17, true)
end

local function closePresets()
	if opened then
		opened = false
		refreshDock()
	end
end

function widget:Initialize()
	WG.BarDroidPresets = {
		fits = function(units)
			return #combatUnits(units) > 0
		end,
		isOpen = function()
			return opened
		end,
		open = function()
			opened, armedFor = true, nil
			refreshDock()
		end,
		close = closePresets,
		items = function()
			local out = {}
			for i, p in ipairs(PRESETS) do
				out[#out + 1] = { kind = "preset", id = i, label = p.name }
			end
			return out
		end,
		pick = function(id)
			local p = PRESETS[id]
			local units = combatUnits(Spring.GetSelectedUnits())
			opened = false
			if p and #units > 0 then
				armedFor = { id = id, units = units }
				say(p.name .. ": TAP THE DESTINATION")
			end
			refreshDock()
		end,
		armed = function()
			return armedFor ~= nil
		end,
		drawThumb = function(id, r)
			local p = PRESETS[id]
			local f = p and THUMBS[p.thumb]
			if f then
				local m = math.min(r[3] - r[1], r[4] - r[2]) * 0.08
				f(r[1] + m, r[2] + m, r[3] - m, r[4] - m)
				gl.Color(1, 1, 1, 1)
			end
		end,
		closeRect = function(r) -- (the X: a square in the grid's top right corner)
			local s = math.floor(math.min(r[3] - r[1], r[4] - r[2]) * 0.14)
			return { r[3] - s, r[4] - s, r[3], r[4] }
		end,
	}
end

function widget:Shutdown()
	WG.BarDroidPresets = nil
end

function widget:MousePress(x, y, btn)
	if not armedFor then
		return false
	end
	local D = WG.BarDroidPortrait
	local dock = D and D.dock and D.dock()
	if dock and x >= dock[1] and x <= dock[3] and y >= dock[2] and y <= dock[4] then
		return false -- (the dock's own presses)
	end
	local a = armedFor
	armedFor = nil
	if btn ~= 1 then
		say("PRESET CANCELLED")
		return true
	end
	local kind, pos = Spring.TraceScreenRay(x, y, true)
	if kind ~= "ground" or not pos then
		say("PRESET CANCELLED")
		return true
	end
	local alive = {}
	for _, u in ipairs(a.units) do
		if Spring.ValidUnitID(u) and not Spring.GetUnitIsDead(u) then
			alive[#alive + 1] = u
		end
	end
	local p = PRESETS[a.id]
	local n = p and p.run(alive, pos[1], pos[3]) or 0
	say(string.format("%s: %d %s", p and p.name or "PRESET", n, n == 1 and "UNIT" or "UNITS"))
	Spring.Echo(string.format("[bardroid-presets] %s to %d,%d: %d units", p and p.name or "?", pos[1], pos[3], n)) -- (tools)
	return true
end

-- the formations' moves as one: the units picked for a moment (the engine's Ctrl group move works on the selection),
-- the order given, the player's own selection back in the same call
function widget:GameFrame(f)
	if #groupOrders == 0 or groupOrders[1].frame > f then
		return
	end
	local mine = Spring.GetSelectedUnits()
	while groupOrders[1] and groupOrders[1].frame <= f do
		local g = table.remove(groupOrders, 1)
		local alive = {}
		for _, u in ipairs(g.units) do
			if Spring.ValidUnitID(u) and not Spring.GetUnitIsDead(u) then
				alive[#alive + 1] = u
			end
		end
		if #alive > 0 then
			Spring.SelectUnitArray(alive)
			Spring.GiveOrder(CMD.FIGHT, ground(g.x, g.z), { "ctrl", "shift" })
		end
	end
	Spring.SelectUnitArray(mine)
end

function widget:KeyPress(key)
	if key ~= KEY_ESCAPE then
		return false
	end
	if opened then -- (Android's Back is Escape in the game: it closes the presets, BAR's menu stays shut)
		closePresets()
		return true
	end
	if armedFor then
		armedFor = nil
		say("PRESET CANCELLED")
		return true
	end
	return false
end
