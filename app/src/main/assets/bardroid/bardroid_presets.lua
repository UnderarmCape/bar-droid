-- BAR Droid presets: preset orders for the picked combat units (Kailil, 2026-11-10: "a PRESETS button ... the whole dock
-- shows the presets as 2 x 2 thumbnails ... closed by an X in the corner or Android's Back"; repeated moves along paths
-- that make units hard to hit, and formations by their types' strengths). Touch play's automation is his and BAR's
-- developers' call (GiveOrder). The dock (bardroid_portrait.lua) shows PRESETS in MOVE's big place while units that
-- move are picked, and the presets over its whole grid; a preset tapped closes them, then a tap on the map sends it
-- there (taps only: a finger's drag pans; a mouse's drag is the front's line, as wide) (Back lets it go). Every preset:
-- the units to their places (no repeat), then, once they are there, each one fights side to side across its place on
-- repeat, the group together. With the dock's QUEUE on the preset stays armed and each tap is the next place (addLeg);
-- with INSERT on the formation goes to the front of their queues.
-- WG.BarDroidPresets: fits(units), isOpen(), open(), close(), items(), pick(id), drawThumb(id, rect), closeRect(rect),
-- armed(), lastPlan(), side. Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid presets",
		desc = "Preset orders for the picked units: a strafe and formations",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -20, -- (before the dock, -10, and BAR's menus: the destination's tap and Back are its first)
		enabled = true,
	}
end

local SIDE = 150 -- elmos each unit goes to each side of its place, round and round, once the group is there
local GAP = 40 -- elmos between two units abreast, where the width has room for it
local LINE_PX = 30 -- screen pixels: a finger that moved this far draws a line; less is a tap
local LINE_MIN = 64 -- elmos: a line shorter than this is a tap where the finger lifted
local KEY_ESCAPE = 27

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID

local opened = false
local armedFor -- { id, units }: a preset picked, the map's next tap or line is where it goes

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

-- (every unit that moves, builders and commanders too: Kailil, 2026-11-13, PRESETS "for all the units" in MOVE's big
-- place; buildings and factories keep their orders)
local function fighter(ud)
	return ud and ud.canMove and not ud.isBuilding and not ud.isFactory and (ud.speed or 0) > 0
end
-- the picked units presets order
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
local function centre(units)
	local cx, cz, n = 0, 0, 0
	for _, u in ipairs(units) do
		local x, _, z = spGetUnitPosition(u)
		if x then
			cx, cz, n = cx + x, cz + z, n + 1
		end
	end
	if n == 0 then
		return nil
	end
	return cx / n, cz / n
end
local function way(cx, cz, tx, tz)
	local dx, dz = tx - cx, tz - cz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1 then
		return 0, 1, 0
	end
	return dx / d, dz / d, d
end

-- Formations (research of 2026-11-10: BAR's wiki and unit pages, the Recoil engine's source; docs/DELIVERY.md). Each
-- unit by its role: brawlers and the short-ranged (range up to 400: Pawns, Ticks, Grunts, Maces, Stouts) in the front
-- row; the ranged behind them by their reach, the shorter first: each row as far back as still lets it hit 150 elmos
-- past the front row's own reach (Kailil, 2026-11-12: "ranged units further back but still at an appropriate range to
-- be effective ... They should be able to all strike ahead of the front line units like pawns and ticks"), 600 at
-- most; planes their own group, fighters ahead of bombers and transports. The units form up where they stand, facing
-- the destination, then go there as one: a fight order with Ctrl and Shift given to them as the selection, which the
-- engine moves at the slowest one's speed keeping each one's place (SelectedUnitsAI; Ctrl on orders given unit by unit
-- does not), so the artillery stays at the back while the formation moves.
local ROW_MAX = 12 -- units a row without a drawn line; more make another row behind it
local FORM_AHEAD = 80 -- elmos: where the front forms up, ahead of the group's middle (toward the destination)
local AIR_LEAD = 300 -- elmos the fighters fly ahead of the bombers and transports
local BACK_MAX = 600 -- elmos: the farthest a ranged row stands behind the front
local REACH_AHEAD = 150 -- elmos a ranged row's reach goes past the front row's
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
	elseif ud.isBuilder and #(ud.weapons or {}) == 0 then -- (constructors: behind the front, with the ranged)
		r = "mid"
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
local function reach(u)
	return role(spGetUnitDefID(u))[2]
end
local widthOf = {}
local function unitWidth(u) -- (elmos: its footprint, or its size where that is bigger)
	local d = spGetUnitDefID(u) or -1
	local w = widthOf[d]
	if not w then
		local ud = UnitDefs[d]
		w = ud and math.max((ud.xsize or 4) * 8, (ud.radius or 8) * 2) or 32
		widthOf[d] = w
	end
	return w
end

-- the rows across for a list of units: with a drawn line W elmos long, as many abreast as fit it with no gap, the
-- rows evened out and each spread over the whole width (a gap between them where it has room: Kailil, 2026-11-12,
-- "have a gap between them if the space allows it"; "The length of that line I draw sets the length of the
-- formation's horizontal size"); without one, ROW_MAX a row, `spacing` apart or a unit and a GAP
local function rowsFor(list, W, spacing)
	local n = #list
	if n == 0 then
		return {}
	end
	local wide = 0
	for _, u in ipairs(list) do
		wide = math.max(wide, unitWidth(u))
	end
	local per = W and math.max(1, math.floor(W / wide) + 1) or ROW_MAX
	local rows = math.ceil(n / per)
	per = math.ceil(n / rows)
	local sp = W and (per > 1 and W / (per - 1) or 0) or math.max(spacing, wide + GAP)
	local out = {}
	for i = 1, n, per do
		local row = {}
		for k = i, math.min(n, i + per - 1) do
			row[#row + 1] = list[k]
		end
		out[#out + 1] = { units = row, sp = sp }
	end
	return out
end

-- each unit's place (along, across) in formation-local elmos: along toward the destination, the front row at 0
local function layout(units, style, W)
	local spacing = style == "spread" and 96 or 64
	local rowGap = style == "spread" and 120 or 80
	local place, rowN = {}, 0
	local function putRow(row, along)
		local n = #row.units
		local stagger = (rowN % 2) * row.sp * 0.5 -- (every other row half a place over: a checkerboard)
		if W and (n - 1) / 2 * row.sp + stagger > W / 2 + 1 then
			stagger = 0 -- (a full row of a drawn width stays inside it)
		end
		for k, u in ipairs(row.units) do
			place[u] = { along, (k - 1 - (n - 1) / 2) * row.sp + stagger }
		end
		rowN = rowN + 1
	end
	if style == "strafe" then -- (one line abreast, more behind it when the width is full)
		for i, row in ipairs(rowsFor(units, W, 64)) do
			putRow(row, -(i - 1) * rowGap)
		end
		return place
	end
	local front, ranged, frontReach = {}, {}, 0
	for _, u in ipairs(units) do
		if role(spGetUnitDefID(u))[1] == "front" then
			front[#front + 1] = u
			frontReach = math.max(frontReach, reach(u))
		else
			ranged[#ranged + 1] = u
		end
	end
	table.sort(ranged, function(a, b)
		local ra, rb = reach(a), reach(b)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	if #front == 0 and #ranged > 0 then -- (no brawlers: the shortest reach leads)
		local lead, rest = reach(ranged[1]) + 50, {}
		for _, u in ipairs(ranged) do
			if reach(u) <= lead then
				front[#front + 1] = u
				frontReach = math.max(frontReach, reach(u))
			else
				rest[#rest + 1] = u
			end
		end
		ranged = rest
	end
	local depth = 0
	for i, row in ipairs(rowsFor(front, W, spacing)) do
		depth = (i - 1) * rowGap
		putRow(row, -depth)
	end
	for _, row in ipairs(rowsFor(ranged, W, spacing)) do -- (shortest reach first: its row's least reach is its first)
		depth = math.max(depth + rowGap, math.min(BACK_MAX, reach(row.units[1]) - frontReach - REACH_AHEAD))
		putRow(row, -depth)
	end
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

local PRESETS = {
	-- STRAFE (Kailil, 2026-11-10: "a battle formation that make the units straight left or right on repeat when they
	-- reach the destination ... fight to the destination then sit at the destination repeating a left and right strafe
	-- via a repeat"; 2026-11-12: "each unit walk side and have a gap between them if the space allows it"): a line
	-- abreast, each unit straight to its place
	{ name = "STRAFE", style = "strafe", thumb = "strafe" },
	{ name = "BATTLE LINE", style = "line", thumb = "line" },
	{ name = "SPREAD", style = "spread", thumb = "spread" },
	{ name = "CONCAVE", style = "concave", thumb = "concave" },
}

-- where a preset puts each unit: aim is a tap { x, z } (the front's middle there, facing away from the group) or a
-- line { ax, az, bx, bz } (the front along it, as wide, facing away from the group's side of it); from { x, z }: where
-- the group comes from instead of where it stands (a queued leg: the last leg's place)
local function plan(id, units, aim, from, prev)
	local P = PRESETS[id]
	local live = {} -- (units picked when it was armed may be gone since: their role, nil's UnitDefs, threw while aiming)
	for _, u in ipairs(units) do
		if spGetUnitDefID(u) and not Spring.GetUnitIsDead(u) then
			live[#live + 1] = u
		end
	end
	units = live
	local cx, cz = centre(units)
	if from and cx then
		cx, cz = from[1], from[2]
	end
	if not (P and cx) then
		return nil
	end
	local mx, mz, fx, fz, W
	if aim.bx then
		mx, mz = (aim.ax + aim.bx) / 2, (aim.az + aim.bz) / 2
		local ux, uz, len = way(aim.ax, aim.az, aim.bx, aim.bz)
		fx, fz, W = -uz, ux, len
		if (mx - cx) * fx + (mz - cz) * fz < 0 then
			fx, fz = -fx, -fz
		end
	else
		mx, mz = aim.x, aim.z
		fx, fz = way(cx, cz, mx, mz)
	end
	local px, pz = -fz, fx
	local land, air = {}, {}
	for _, u in ipairs(units) do
		local r = role(spGetUnitDefID(u))
		local list = (r[1] == "fighter" or r[1] == "air") and air or land
		list[#list + 1] = u
	end
	local place = layout(land, P.style, W)
	-- (each row's units to its places by their own side to side order: the fewest crossings)
	local byRow = {}
	for _, u in ipairs(land) do
		local p = place[u]
		local key = string.format("%.0f", p[1])
		local row = byRow[key] or { slots = {}, units = {} }
		byRow[key] = row
		row.slots[#row.slots + 1] = p
		row.units[#row.units + 1] = u
	end
	for _, row in pairs(byRow) do
		table.sort(row.slots, function(a, b)
			return a[2] < b[2]
		end)
		local side = {}
		for _, u in ipairs(row.units) do
			local x, _, z = spGetUnitPosition(u)
			if prev and prev[u] then -- (a queued leg: from the unit's place in the last one)
				x, z = prev[u][1], prev[u][2]
			end
			side[u] = x and ((x - cx) * px + (z - cz) * pz) or 0
		end
		table.sort(row.units, function(a, b)
			if side[a] ~= side[b] then
				return side[a] < side[b]
			end
			return a < b
		end)
		for i, u in ipairs(row.units) do
			place[u] = row.slots[i]
		end
	end
	-- (the middle drawn in so every place is on the map; on the map's edge the places past it went nowhere and those
	-- units stayed)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in pairs(place) do
		local wx, wz = fx * p[1] + px * p[2], fz * p[1] + pz * p[2]
		x0, x1, z0, z1 = math.min(x0, wx), math.max(x1, wx), math.min(z0, wz), math.max(z1, wz)
	end
	local m = 48
	if x0 <= x1 then
		if Game.mapSizeX - m - x1 >= m - x0 then
			mx = math.max(m - x0, math.min(Game.mapSizeX - m - x1, mx))
		end
		if Game.mapSizeZ - m - z1 >= m - z0 then
			mz = math.max(m - z0, math.min(Game.mapSizeZ - m - z1, mz))
		end
	end
	local slots = {}
	for u, p in pairs(place) do
		slots[u] = { mx + fx * p[1] + px * p[2], mz + fz * p[1] + pz * p[2], p[1], p[2] }
	end
	return { land = land, air = air, place = place, slots = slots, fx = fx, fz = fz, px = px, pz = pz, mx = mx, mz = mz,
		cx = cx, cz = cz, W = W }
end

local groupOrders = {} -- { frame, units, x, z }: the move as one, a frame after the form-up orders (SelectedUnitsAI
-- measures each unit's place from where its queue ends)
-- forms the units up where they stand (place: along, across), facing the way, then sends them as one so that each
-- lands on its place from the front's middle
local function formUp(units, place, pl)
	if #units == 0 then
		return 0
	end
	local fx, fz, px, pz = pl.fx, pl.fz, pl.px, pl.pz
	local ax, az = pl.cx + fx * FORM_AHEAD, pl.cz + fz * FORM_AHEAD
	local sx, sz = 0, 0
	for _, u in ipairs(units) do
		local p = place[u]
		local wx, wz = fx * p[1] + px * p[2], fz * p[1] + pz * p[2]
		sx, sz = sx + wx, sz + wz
		Spring.GiveOrderToUnit(u, CMD.MOVE, ground(ax + wx, az + wz), 0)
	end
	-- (the move as one sends each unit to the target plus its place from the group's middle: the target is the
	-- front's middle plus that middle, so the front row stands on the drawn line)
	groupOrders[#groupOrders + 1] = { frame = Spring.GetGameFrame() + 2, units = units, x = pl.mx + sx / #units,
		z = pl.mz + sz / #units }
	return #units
end

-- the side to side fights, once the group is there (Kailil, 2026-11-12: "the repeat commands for all the other presets
-- besides strafe should not make it move back to the original move marker then fight marker. Instead, it should make
-- the units on each row repeat move side to side the formation"): the way there is given without repeat; the repeat
-- and the two fights across each unit's place only when every unit is there, or SWAY_WAIT after the first, so the
-- rows go side to side together. A unit the player sends elsewhere (its queue without the fight to its place, or
-- stopped away from it) is let go.
local SWAY_WAIT = 12 * 30 -- frames
local GIVE_UP = 120 * 30 -- frames: a group never there by then is let go
local sways = {}
-- the units going side to side: the player's own next order ends it, their repeat off (left on, a path or a patrol
-- given them later ran round and round, which BAR does only with Repeat set by hand); [unit] = { at: the frame the
-- sway was given, its two ends a, b }
local swaying = {}
local ENDS_SWAY = {} -- (orders that move or set the unit to work; a state such as its fire or move state does not)
for _, c in ipairs({ CMD.MOVE, CMD.FIGHT, CMD.PATROL, CMD.ATTACK, CMD.AREA_ATTACK, CMD.GUARD, CMD.STOP, CMD.RECLAIM,
	CMD.REPAIR, CMD.RESURRECT, CMD.CAPTURE, CMD.RESTORE, CMD.MANUALFIRE, CMD.LOAD_UNITS, CMD.LOAD_ONTO,
	CMD.UNLOAD_UNIT, CMD.UNLOAD_UNITS }) do
	if c then
		ENDS_SWAY[c] = true
	end
end
local lastPlan -- (the last preset sent: its places, for tools/dock-phone-test)
local function swayCheck(f)
	for i = #sways, 1, -1 do
		local g = sways[i]
		local keep, there = {}, 0
		if f - g.since >= 15 then
			for _, u in ipairs(g.units) do
				local s = g.slots[u]
				local x, _, z = spGetUnitPosition(u)
				if x and not Spring.GetUnitIsDead(u) then
					local q = Spring.GetUnitCommands(u, 40) or {}
					if #q == 0 then -- (q: a queued chain of legs is long, its last fight far down the queue)
						if (x - s[1]) ^ 2 + (z - s[2]) ^ 2 < 160 * 160 then
							there = there + 1
							keep[#keep + 1] = u
						elseif f - g.since < 90 then -- (its order not come yet, by ping: kept for 3 s; dropped at the first
							-- look, half a second on, a group could end with nobody swaying, review 2026-11-15)
							keep[#keep + 1] = u
						end
					else
						for _, c in ipairs(q) do
							if c.id == CMD.FIGHT and c.params[3] and (c.params[1] - s[1]) ^ 2 + (c.params[3] - s[2]) ^ 2 < 300 * 300 then
								keep[#keep + 1] = u
								break
							end
						end
					end
				end
			end
			g.units = keep
			if there > 0 and not g.first then
				g.first = f
			end
		end
		if f - g.since >= 15 and (#keep == 0 or f - g.since > (g.giveUp or GIVE_UP)) then
			g.done = true
			table.remove(sways, i)
		elseif f - g.since >= 15 and (there == #keep or (g.first and f - g.first > SWAY_WAIT)) then
			g.done = true
			for _, u in ipairs(keep) do
				local s = g.slots[u]
				local a, b = ground(s[1] + g.px * SIDE, s[2] + g.pz * SIDE), ground(s[1] - g.px * SIDE, s[2] - g.pz * SIDE)
				Spring.GiveOrderArrayToUnitArray({ u }, {
					{ CMD.REPEAT, { 1 }, {} },
					{ CMD.FIGHT, a, {} },
					{ CMD.FIGHT, b, { "shift" } },
				})
				swaying[u] = { at = f, a = a, b = b }
			end
			Spring.Echo(string.format("[bardroid-presets] %s: %d units there, side to side on repeat", g.name, #keep)) -- (tools)
			table.remove(sways, i)
		end
	end
end

-- mode "insert" (the dock's INSERT on): each unit straight to its place at the front of its queue, its own orders after
-- (no side to side, its repeat as it was)
local function send(id, units, aim, mode)
	local pl = plan(id, units, aim)
	if not pl then
		return 0
	end
	local P = PRESETS[id]
	if mode == "insert" then
		-- (internal: not taken round again by a repeat on, the side to side of an earlier preset: the units do it once,
		-- then their loop goes on; given plain it joined the loop, dev phone 2026-11-13)
		local INSERT_OPTS = CMD.OPT_INTERNAL or 8
		local n = 0
		local air = airLayout(pl.air)
		for _, u in ipairs(pl.land) do
			local s = pl.slots[u]
			local g = ground(s[1], s[2])
			Spring.GiveOrderToUnit(u, CMD.INSERT, { 0, CMD.FIGHT, INSERT_OPTS, g[1], g[2], g[3] }, { "alt" })
			n = n + 1
		end
		for _, u in ipairs(pl.air) do
			local p = air[u]
			local g = ground(pl.mx + pl.fx * p[1] + pl.px * p[2], pl.mz + pl.fz * p[1] + pl.pz * p[2])
			Spring.GiveOrderToUnit(u, CMD.INSERT, { 0, CMD.FIGHT, INSERT_OPTS, g[1], g[2], g[3] }, { "alt" })
			n = n + 1
		end
		lastPlan = pl
		return n, pl
	end
	-- (a repeat left on by an earlier preset sent them back round to where they had been: Kailil, 2026-11-12)
	Spring.GiveOrderToUnitArray(units, CMD.REPEAT, { 0 }, 0)
	local n = 0
	if P.style == "strafe" then -- (each straight to its place)
		for _, u in ipairs(pl.land) do
			local s = pl.slots[u]
			Spring.GiveOrderToUnit(u, CMD.FIGHT, ground(s[1], s[2]), 0)
			n = n + 1
		end
	else
		n = formUp(pl.land, pl.place, pl)
	end
	n = n + formUp(pl.air, airLayout(pl.air), pl) -- (planes: their own group, fighters ahead; no side to side)
	local g
	if #pl.land > 0 then
		g = { units = pl.land, slots = pl.slots, px = pl.px, pz = pl.pz, since = Spring.GetGameFrame(), name = P.name }
		sways[#sways + 1] = g
	end
	lastPlan = pl
	return n, pl, g
end

-- QUEUE on (Kailil, 2026-11-13: "If I have queue on and I make multiple taps, I want the formations to move to the first
-- tap, then wait for all units to reach their destinations in the first formation location, then they move on to the
-- next and the next. On the final formation location, then they do the repeat commands"): each tap after the first a
-- leg: BAR's gather wait at the last place (the engine's WaitCommandsAI, given through the selection as its key does:
-- each unit waits there until all of them are), then on to this place in the formation, facing from the last one; the
-- side to side only at the final place (the sway group's places moved on). a: the armed chain { id, prev plan, legs,
-- sway group }. A group already going side to side (the last tap came after they were there): a fresh send instead.
local function addLeg(a, units, aim)
	if not (a.sway and not a.sway.done) then
		local n, pl, g = send(a.id, units, aim)
		if pl then
			a.prev, a.sway, a.legs = pl, g, 1
		end
		return n, pl
	end
	local pl = plan(a.id, units, aim, { a.prev.mx, a.prev.mz }, a.prev.slots)
	if not pl then
		return 0
	end
	local all = {}
	for _, u in ipairs(pl.land) do
		all[#all + 1] = u
	end
	for _, u in ipairs(pl.air) do
		all[#all + 1] = u
	end
	local mine = Spring.GetSelectedUnits()
	Spring.SelectUnitArray(all)
	Spring.GiveOrder(CMD.GATHERWAIT, {}, { "shift" })
	Spring.SelectUnitArray(mine)
	for _, u in ipairs(pl.land) do
		local s = pl.slots[u]
		Spring.GiveOrderToUnit(u, CMD.FIGHT, ground(s[1], s[2]), { "shift" })
	end
	local air = airLayout(pl.air)
	for _, u in ipairs(pl.air) do
		local p = air[u]
		Spring.GiveOrderToUnit(u, CMD.FIGHT, ground(pl.mx + pl.fx * p[1] + pl.px * p[2], pl.mz + pl.fz * p[1] + pl.pz * p[2]),
			{ "shift" })
	end
	a.legs = a.legs + 1
	local g = a.sway
	g.units, g.slots, g.px, g.pz, g.since, g.first = pl.land, pl.slots, pl.px, pl.pz, Spring.GetGameFrame(), nil
	g.giveUp = GIVE_UP * a.legs -- (the whole way: two minutes a leg)
	a.prev = pl
	lastPlan = pl
	return #all, pl
end

-- the dock's QUEUE and INSERT (bardroid_pad.lua's, the dock's selection row)
local function queueMode()
	local Pd = WG.BarDroidPad
	if Pd and Pd.queueState then
		return Pd.queueState()
	end
	return false, false
end

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
function THUMBS.strafe(x0, y0, x1, y1) -- (the group up to the destination, then a line across it with arrows both ways)
	local w, h = x1 - x0, y1 - y0
	local gold, lw = { 0.95, 0.78, 0.25, 0.95 }, math.max(2, w * 0.018)
	local cx, top = x0 + w * 0.5, y0 + h * 0.72
	line({ { cx, y0 + h * 0.2 }, { cx, top } }, lw, { 0.95, 0.78, 0.25, 0.5 })
	line({ { x0 + w * 0.18, top }, { x1 - w * 0.18, top } }, lw * 1.4, gold)
	local a = w * 0.07
	for _, s in ipairs({ -1, 1 }) do -- (the arrow heads at both ends)
		local ex = cx + s * (w * 0.32)
		line({ { ex - s * a, top + a }, { ex, top }, { ex - s * a, top - a } }, lw * 1.4, gold)
	end
	for i = -2, 2 do -- (the group on the line, a gap between them)
		dot(cx + i * w * 0.1, top, math.max(3, w * 0.022), { 0.4, 0.7, 1, 1 })
	end
	for i = 1, 3 do -- (and at the start)
		dot(cx + (i - 2) * w * 0.06, y0 + h * (0.12 + (i % 2) * 0.04), math.max(3, w * 0.022), { 0.4, 0.7, 1, 1 })
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

-- whether this game lets the app's widgets give orders (a host can forbid user widgets' Spring.GiveOrder*: BAR's
-- handler then throws, and a widget that throws is removed): asked once, as first person asks; no PRESETS without it
local canOrder
local function mayOrder()
	if canOrder == nil then
		canOrder = pcall(Spring.GiveOrderToUnitArray, {}, CMD.STOP, {}, 0)
	end
	return canOrder
end

function widget:Initialize()
	WG.BarDroidPresets = {
		fits = function(units)
			return mayOrder() and #combatUnits(units) > 0
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
				-- (taps only: a drag pans, Kailil 2026-11-13 "make presets a single tap only"; QUEUE on: a tap for each
				-- place in turn)
				say(p.name .. (queueMode() and ": TAP EACH PLACE IN TURN" or ": TAP WHERE TO SEND"))
			end
			refreshDock()
		end,
		disarm = function() -- (Android's Back: the dock's SP.back puts everything away)
			if armedFor then
				armedFor = nil
				refreshDock()
			end
		end,
		armed = function() -- (and the armed preset's name: the dock's PRESETS button shows it, gold)
			local p = armedFor and PRESETS[armedFor.id]
			return armedFor ~= nil, p and p.name
		end,
		drawThumb = function(id, r)
			local p = PRESETS[id]
			local f = p and THUMBS[p.thumb]
			if f then
				local m = math.min(r[3] - r[1], r[4] - r[2]) * 0.08
				local x0, x1 = r[1] + m, r[3] - m
				local h = r[4] - r[2] - 2 * m
				if x1 - x0 > h * 1.6 then -- (a wide tile, sideways: the picture centred at its upright shape; drawn
					-- across the whole width its dots, sized by the width, overlapped from row to row, dev phone 2026-11-12)
					local c = (x0 + x1) / 2
					x0, x1 = c - h * 0.8, c + h * 0.8
				end
				f(x0, r[2] + m, x1, r[4] - m)
				gl.Color(1, 1, 1, 1)
			end
		end,
		closeRect = function(r) -- (the X: a square in the grid's top right corner)
			local s = math.floor(math.min(r[3] - r[1], r[4] - r[2]) * 0.14)
			return { r[3] - s, r[4] - s, r[3], r[4] }
		end,
		lastPlan = function() -- (tools: the last sent preset's places, slots[unit] = { x, z, along, across }, the way
			-- it faces fx, fz, across px, pz, the front's middle mx, mz, a drawn line's length W)
			return lastPlan
		end,
		side = SIDE,
	}
end

function widget:Shutdown()
	WG.BarDroidPresets = nil
	for u in pairs(swaying) do -- (the side to side's repeat off: left on, the units walked their two legs for good; a
		-- host that forbids widget orders throws, hence pcall; review 2026-11-15)
		pcall(Spring.GiveOrderToUnit, u, CMD.REPEAT, { 0 }, 0)
	end
end

-- The destination by finger (Kailil, 2026-11-10: "allow me to drag my finger and it sets the preset only when I lift
-- up"; 2026-11-12: "All preset commands should be able to be sent via a tap to do a quick order send. Or me draw a line
-- at the site I want the formation to end and begin the repeat commands. The length of that line I draw sets the
-- length of the formation's horizontal size"): a press of either button on the map starts aiming; lifted where it
-- went down it is a tap, the front's middle there; a finger that moved draws the line from where it reached the ground
-- to where it lifts, the places it gives drawn as it goes.
local aiming -- { x, z: the finger now; x0, z0: where it reached the ground; sx, sy: there on the screen; line }
local function groundAt(x, y)
	local kind, pos = Spring.TraceScreenRay(x, y, true, true) -- (on the minimap: the place it shows there)
	if kind == "ground" and pos then
		return pos[1], pos[3]
	end
end
local function aimOf(a)
	if a.line and (a.x - a.x0) ^ 2 + (a.z - a.z0) ^ 2 >= LINE_MIN * LINE_MIN then
		return { ax = a.x0, az = a.z0, bx = a.x, bz = a.z }
	end
	return { x = a.x, z = a.z }
end

-- (a point on the portrait dock: its own presses; the split dock's game between its blocks is the map's)
local function onDock(x, y)
	local D = WG.BarDroidPortrait
	if D and D.onDock then
		return D.onDock(x, y)
	end
	local dock = D and D.dock and D.dock()
	return dock and x >= dock[1] and x <= dock[3] and y >= dock[2] and y <= dock[4] or false
end

function widget:MousePress(x, y)
	if not armedFor then
		return false
	end
	if onDock(x, y) then
		return false -- (the dock's own presses)
	end
	local gx, gz = groundAt(x, y)
	if gx then
		aiming = { x = gx, z = gz, x0 = gx, z0 = gz, sx = x, sy = y }
	end
	return true -- (off the map: nothing yet, still armed)
end

function widget:MouseMove(x, y)
	if not armedFor then
		return false
	end
	local gx, gz = groundAt(x, y)
	if gx and aiming then
		aiming.x, aiming.z = gx, gz
		if not aiming.line and math.abs(x - aiming.sx) + math.abs(y - aiming.sy) > LINE_PX then
			aiming.line = true
		end
	elseif gx then -- (a press over the void past the map's edge or the sky aims once the finger reaches the ground: it
		-- was lost, the preset still armed, until another press)
		aiming = { x = gx, z = gz, x0 = gx, z0 = gz, sx = x, sy = y }
	end
	return true
end

function widget:MouseRelease(x, y)
	if not (aiming and armedFor) then
		aiming = nil
		return false
	end
	-- (lifted over the dock: the aim backs out, the preset stays armed for another try; it went to the ground hidden
	-- behind the dock, 2026-11-11)
	if onDock(x, y) then
		aiming = nil
		say(PRESETS[armedFor.id] and PRESETS[armedFor.id].name .. ": NOT SENT, TAP THE MAP" or "NOT SENT")
		Spring.Echo("[bardroid-presets] lifted over the dock: not sent, still armed") -- (tools)
		return true
	end
	local gx, gz = groundAt(x, y)
	if gx then
		aiming.x, aiming.z = gx, gz
	end
	local aim = aimOf(aiming)
	local a = armedFor
	aiming = nil
	local alive = {}
	for _, u in ipairs(a.units) do
		if Spring.ValidUnitID(u) and not Spring.GetUnitIsDead(u) then
			alive[#alive + 1] = u
		end
	end
	local p = PRESETS[a.id]
	local n, pl = 0, nil
	local queued, insert = queueMode()
	local how = " (a tap)"
	if p and queued then -- (QUEUE: the preset stays armed, each tap a leg; QUEUE with INSERT the same)
		if a.prev then
			n, pl = addLeg(a, alive, aim)
		else
			local g
			n, pl, g = send(a.id, alive, aim)
			a.prev, a.sway, a.legs = pl, g, 1
		end
		how = string.format(" (place %d)", a.legs or 1)
		say(string.format("%s: PLACE %d, %d %s; TAP THE NEXT", p.name, a.legs or 1, n, n == 1 and "UNIT" or "UNITS"))
	else
		armedFor = nil
		if p then
			n, pl = send(a.id, alive, aim, insert and "insert" or nil)
		end
		how = insert and " (inserted)" or how
		say(string.format("%s: %d %s%s", p and p.name or "PRESET", n, n == 1 and "UNIT" or "UNITS", insert and ", FIRST" or ""))
	end
	Spring.Echo(string.format("[bardroid-presets] %s to %.0f,%.0f%s: %d units", p and p.name or "?", pl and pl.mx or 0,
		pl and pl.mz or 0, pl and pl.W and string.format(" (a line %.0f wide)", pl.W) or how, n)) -- (tools)
	return true
end

-- a chain of queued places ends when QUEUE goes off (the preset no longer armed; what was sent goes on)
function widget:Update()
	if armedFor and armedFor.prev and not queueMode() then
		armedFor = nil
		refreshDock()
	end
end

-- while aiming: a tap's pulsing gold ring with dashes from the group, or the drawn line with the way it faces; the
-- places the units would take (blue rings) and how far the front goes side to side (a faint gold line)
local preview -- { key, plan }
function widget:DrawWorld()
	if not (aiming and armedFor) then
		preview = nil
		return
	end
	local aim = aimOf(aiming)
	local key = aim.bx and string.format("%.0f %.0f %.0f %.0f", aim.ax, aim.az, aim.bx, aim.bz)
		or string.format("%.0f %.0f", aim.x, aim.z)
	if not preview or preview.key ~= key then
		preview = { key = key, plan = plan(armedFor.id, armedFor.units, aim) }
	end
	local pl = preview.plan
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8)
	-- (the marks' size with the camera's distance: zoomed out the line's ends, the arrow and the places were specks,
	-- dev phone screenshot 2026-11-12)
	local mx0, mz0 = aim.bx and (aim.ax + aim.bx) / 2 or aim.x, aim.bx and (aim.az + aim.bz) / 2 or aim.z
	local camX, camY, camZ = Spring.GetCameraPosition()
	local camD = math.sqrt((camX - mx0) ^ 2 + (camY - (Spring.GetGroundHeight(mx0, mz0) or 0)) ^ 2 + (camZ - mz0) ^ 2)
	local k = math.max(1, math.min(3, camD / 1500))
	gl.DepthTest(false)
	if aim.bx then
		local ay, by = Spring.GetGroundHeight(aim.ax, aim.az) or 0, Spring.GetGroundHeight(aim.bx, aim.bz) or 0
		gl.LineWidth(5)
		gl.Color(1, 0.8, 0.25, 0.75 + 0.25 * pulse)
		gl.BeginEnd(GL.LINES, function()
			gl.Vertex(aim.ax, ay + 8, aim.az)
			gl.Vertex(aim.bx, by + 8, aim.bz)
		end)
		gl.LineWidth(3)
		-- (the ends and the arrow never larger than the line itself: on a short one they hid it)
		local len = math.sqrt((aim.bx - aim.ax) ^ 2 + (aim.bz - aim.az) ^ 2)
		local endR = math.min(24 * k, math.max(16, len * 0.12))
		gl.DrawGroundCircle(aim.ax, ay, aim.az, endR, 24)
		gl.DrawGroundCircle(aim.bx, by, aim.bz, endR, 24)
		if pl then -- (the way the front faces: an arrow from the line's middle)
			local mx, mz = (aim.ax + aim.bx) / 2, (aim.az + aim.bz) / 2
			local my = Spring.GetGroundHeight(mx, mz) or 0
			local al = math.min(110 * k, math.max(80, len * 0.6)) -- (the arrow's length)
			local tx, tz = mx + pl.fx * al, mz + pl.fz * al
			local hb, hs = al * 0.27, al * 0.2 -- (the head's back and side)
			gl.BeginEnd(GL.LINE_STRIP, function()
				gl.Vertex(mx, my + 8, mz)
				gl.Vertex(tx, my + 8, tz)
				gl.Vertex(tx - pl.fx * hb + pl.px * hs, my + 8, tz - pl.fz * hb + pl.pz * hs)
			end)
			gl.BeginEnd(GL.LINES, function()
				gl.Vertex(tx, my + 8, tz)
				gl.Vertex(tx - pl.fx * hb - pl.px * hs, my + 8, tz - pl.fz * hb - pl.pz * hs)
			end)
		end
	else
		local tx, tz = aim.x, aim.z
		local ty = Spring.GetGroundHeight(tx, tz) or 0
		gl.LineWidth(3)
		gl.Color(1, 0.8, 0.25, 0.7 + 0.3 * pulse)
		gl.DrawGroundCircle(tx, ty, tz, (50 + 12 * pulse) * k, 40)
		if pl then -- (the way from the group: dashes running towards the mark; a plain line at half alpha was lost on
			-- the ground, dev phone screenshot)
			local cx, cz = pl.cx, pl.cz
			local cy = Spring.GetGroundHeight(cx, cz) or ty
			local dx, dz = tx - cx, tz - cz
			local len = math.sqrt(dx * dx + dz * dz)
			local dash, run = 40, (os.clock() * 120) % 80
			gl.Color(1, 0.85, 0.3, 0.85)
			gl.BeginEnd(GL.LINES, function()
				for s = run - 80, len, 80 do
					local a, b = math.max(0, s) / math.max(1, len), math.min(len, s + dash) / math.max(1, len)
					if b > a then
						gl.Vertex(cx + dx * a, cy + (ty - cy) * a + 8, cz + dz * a)
						gl.Vertex(cx + dx * b, cy + (ty - cy) * b + 8, cz + dz * b)
					end
				end
			end)
		end
	end
	if pl then
		local lo, hi = math.huge, -math.huge
		gl.LineWidth(2)
		gl.Color(0.55, 0.85, 1, 0.9)
		for _, s in pairs(pl.slots) do -- (larger zoomed out, never over the next place: 22 at most)
			gl.DrawGroundCircle(s[1], Spring.GetGroundHeight(s[1], s[2]) or 0, s[2], math.min(22, 14 * k), 12)
			if s[3] == 0 then
				lo, hi = math.min(lo, s[4]), math.max(hi, s[4])
			end
		end
		if lo <= hi then -- (the front's side to side: as far as its ends go)
			local ax, az = pl.mx + pl.px * (lo - SIDE), pl.mz + pl.pz * (lo - SIDE)
			local bx, bz = pl.mx + pl.px * (hi + SIDE), pl.mz + pl.pz * (hi + SIDE)
			gl.LineWidth(2)
			gl.Color(1, 0.8, 0.25, 0.35)
			gl.BeginEnd(GL.LINES, function()
				gl.Vertex(ax, (Spring.GetGroundHeight(ax, az) or 0) + 6, az)
				gl.Vertex(bx, (Spring.GetGroundHeight(bx, bz) or 0) + 6, bz)
			end)
		end
	end
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

-- the formations' moves as one: the units picked for a moment (the engine's Ctrl group move works on the selection),
-- the order given, the player's own selection back in the same call; and the side to side once a group is there
function widget:GameFrame(f)
	if #sways > 0 and f % 10 == 0 then
		swayCheck(f)
	end
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

-- a unit going side to side given an order of the player's (or any not the sway's own): its repeat off, as it was
-- before the preset; a queued order (Shift) then comes after the fights in its queue instead of joining their round
function widget:UnitCommand(unitID, _, _, cmdID, cmdParams)
	local s = swaying[unitID]
	if not s then
		return
	end
	local p = cmdParams or {}
	if cmdID == CMD.REPEAT then -- (the sway's own, or Repeat set by hand: the player's choice from then on)
		if not (p[1] == 1 and Spring.GetGameFrame() - s.at < 90) then
			swaying[unitID] = nil
		end
		return
	end
	if cmdID == CMD.INSERT and p[2] then -- (the dock's INSERT, BAR's Space, a helper's repair: the order inside decides; an
		-- insert ended nothing, it joined the side to side's loop and came back every lap, review 2026-11-15)
		cmdID, p = p[2], { p[4], p[5], p[6] }
	end
	if cmdID == CMD.FIGHT and p[3] then
		for _, e in ipairs({ s.a, s.b }) do
			if math.abs(p[1] - e[1]) < 2 and math.abs(p[3] - e[3]) < 2 then
				return
			end
		end
	end
	if cmdID < 0 or ENDS_SWAY[cmdID] then
		swaying[unitID] = nil
		Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 0 }, 0)
	end
end

function widget:UnitDestroyed(unitID)
	swaying[unitID] = nil
end
function widget:UnitTaken(unitID) -- (given to an ally: theirs to order)
	swaying[unitID] = nil
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
		armedFor, aiming = nil, nil
		say("PRESET CANCELLED")
		return true
	end
	return false
end
