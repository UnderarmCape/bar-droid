-- BAR Droid walls: a sentry placed, a ring of walls queued around it (Kailil, 2026-11-20: "When building walls, I need
-- a way to draw a block of walls around a sentry quickly ... when any builder places a sentry ... A wall is automatically
-- built around it. The wall should be t1 for t1 stuff and t2 for t2 sentry ... For t2 sentries make it so the wall is
-- built first then the sentry. Do not build walls for aa guns or sea sentries ... Tactical missile launchers, nuke silos,
-- antinuke silos, should not get walls. Be smart about this system ... A long range plasma cannon or things taller than
-- that should not get walls. Jammers or radar in case they are labeled a sentry.").
-- A sentry here: a land building of BAR's "weapon" unit group (or "weaponaa", Legion's machine guns), no stockpiled
-- weapon (tactical missiles, nukes, the Juno, the Hive), no weapon reaching 1500 elmos or more and no taller than BAR's
-- Long Range Plasma Cannon (Armada's Big Bertha); AA, torpedo, nuke and antinuke groups, radar and jammers ("util") are
-- never one. Its walls: the builders' own T1 wall (dragon's teeth) for a T1 sentry, after it; the T2 wall (fortification)
-- for a T2 sentry, before it. Walls only where the sentry fires over them: an arcing weapon, or the sentry half again as
-- tall as the wall (the low pop-up turrets, Dragon's Claw and the like, get none). One sentry placed alone; a line or a
-- grid of them in one placement gets none (their rings would cross). On by default; the place panel's WALLS (WG).
-- Touch play's automation is Kailil's and BAR's developers' call (GiveOrder). Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid walls",
		desc = "A sentry placed: a ring of walls queued around it",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local CONFIG = "LuaUI/Config/bardroid_walls.txt"
local LONG_RANGE = 1500 -- elmos: a weapon this long is artillery's, not a sentry's (the LRPC's ~4000)
local OVER = 1.5 -- a sentry this many times the wall's height fires over it

local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitDefID = Spring.GetUnitDefID

local enabled = true
local myTeam = Spring.GetMyTeamID()
-- (the walls' own build orders come back through UnitCommand a frame later: walls are no sentries, so they start nothing;
-- a builder's queue given again with the walls in it sends its sentry's order again: resent, key -> until which frame)
local resent = {}
local placed = {} -- the sentry placements by frame: frame -> key -> { def, x, y, z, facing, builders = { unitID = true } }

local function readConfig()
	local fh = io.open(CONFIG, "r")
	if fh then
		local s = fh:read("*a") or ""
		fh:close()
		enabled = not s:find("on 0", 1, true)
	end
end
local function writeConfig()
	local fh = io.open(CONFIG, "w")
	if fh then
		fh:write("on " .. (enabled and 1 or 0) .. "\n")
		fh:close()
	end
end

-- the walls: BAR marks them "objectify" (buildings the game treats as terrain); land ones only
local walls = {} -- defID -> { tech, height }
for id, ud in pairs(UnitDefs) do
	local cp = ud.customParams or {}
	if cp.objectify and not ud.canMove and (ud.minWaterDepth or 0) <= 0 then
		walls[id] = { tech = tonumber(cp.techlevel) or 1, height = ud.height or 0 }
	end
end

-- (the Long Range Plasma Cannons' heights, the tallest of the three factions', with 15 % to spare: these are the
-- models' heights, not their collision volumes, and the Big Bertha's and Intimidator's models are 88 tall, the Sentinel
-- tower's (HLT) 96; the Doomsday Machine's 119, Vulcan's and Buzzsaw's more: those are the tall ones; dev phone
-- 2026-11-20)
local TALLEST = 0
for _, n in ipairs({ "armbrtha", "corint", "leglrpc" }) do
	TALLEST = math.max(TALLEST, UnitDefNames[n] and UnitDefNames[n].height or 0)
end
TALLEST = (TALLEST > 0 and TALLEST or 90) * 1.15

-- a sentry's facts, or nil: { tech, height, arcs }
local sentries = {}
local function sentryOf(defID)
	if sentries[defID] ~= nil then
		return sentries[defID] or nil
	end
	local ud = UnitDefs[defID]
	local cp = ud and ud.customParams or {}
	local info = false
	if ud and (cp.unitgroup == "weapon" or cp.unitgroup == "weaponaa") and not ud.canMove and (ud.minWaterDepth or 0) <= 0
		and not walls[defID] and (ud.height or 0) <= TALLEST then
		local arcs, ok = true, #(ud.weapons or {}) > 0
		for _, w in ipairs(ud.weapons or {}) do
			local wd = WeaponDefs[w.weaponDef]
			if wd then
				if wd.stockpile or (wd.range or 0) >= LONG_RANGE then
					ok = false
				end
				-- (a cannon with its high trajectory on, or the player's switch for it (2), and the vertical launchers arc;
				-- every weapon reports a highTrajectory, lasers and lightning too: alone it gave the Dragon's Claw walls)
				if not (wd.type == "StarburstLauncher" or (wd.type == "Cannon" and (wd.highTrajectory or 0) > 0)) then
					arcs = false
				end
			end
		end
		if ok then
			info = { tech = tonumber(cp.techlevel) or 1, height = ud.height or 0, arcs = arcs }
		end
	end
	sentries[defID] = info
	return info or nil
end

local function firesOver(s, wallDef)
	return s.arcs or s.height >= walls[wallDef].height * OVER
end

-- a builder's wall of a tier (1 or 2), or nil
local function wallOf(builder, tier)
	local ud = UnitDefs[spGetUnitDefID(builder) or -1]
	for _, d in ipairs(ud and ud.buildOptions or {}) do
		local w = walls[d]
		if w and ((tier >= 2) == (w.tech >= 2)) then
			return d
		end
	end
end

-- the ring's spots around a building at x, z (its footprint by its facing): walls side by side, a closed square, each
-- buildable now
local function ringSpots(def, x, z, facing, wallDef)
	local ud, wd = UnitDefs[def], UnitDefs[wallDef]
	local hx, hz = ud.xsize * 4, ud.zsize * 4 -- (half its footprint: xsize in 8-elmo squares)
	if facing == 1 or facing == 3 then
		hx, hz = hz, hx
	end
	local W, G = wd.xsize * 8, 16 -- (the wall's width; the build grid a 2x2 wall's middle sits on)
	-- (the ring on the footprint's edges, which lie on the grid: walls side by side from the near edge; a span that is
	-- no whole number of walls (a 3x3 sentry's 48 elmos) gets its gap on the far side. Laid out from the sentry's middle
	-- the Annihilator's and the Viper's walls fell between grid lines, two snapped onto each other and the engine dropped
	-- one: 11 of 12, dev phone 2026-11-20)
	local x0, x1 = math.floor((x - hx) / G + 0.5) * G, math.floor((x + hx) / G + 0.5) * G
	local z0, z1 = math.floor((z - hz) / G + 0.5) * G, math.floor((z + hz) / G + 0.5) * G
	x1 = x0 + math.ceil((x1 - x0) / W) * W
	z1 = z0 + math.ceil((z1 - z0) / W) * W
	local rx, rz = (x1 - x0) / 2 + W / 2, (z1 - z0) / 2 + W / 2
	x, z = (x0 + x1) / 2, (z0 + z1) / 2
	local out, seen = {}, {}
	local function add(px, pz)
		local bx, by, bz = Spring.Pos2BuildPos(wallDef, px, Spring.GetGroundHeight(px, pz), pz, 0)
		local key = math.floor(bx) .. ":" .. math.floor(bz)
		if not seen[key] and Spring.TestBuildOrder(wallDef, bx, by, bz, 0) > 0 then
			seen[key] = true
			out[#out + 1] = { bx, by, bz }
		end
	end
	for k = -rz, rz, W do -- (the left and right sides, corners included)
		add(x - rx, z + k)
		add(x + rx, z + k)
	end
	for k = -rx + W, rx - W, W do -- (the top and bottom between the corners)
		add(x + k, z - rz)
		add(x + k, z + rz)
	end
	return out
end

local mayOrderAnswer
local function mayOrder() -- (as bardroid_retreat.lua: a host may forbid widgets' orders)
	if mayOrderAnswer == nil then
		mayOrderAnswer = pcall(Spring.GiveOrderToUnitArray, {}, CMD.STOP, {}, 0)
	end
	return mayOrderAnswer
end

-- the sentry's place in a builder's queue (0 based) and its order's tag, or nil
local function queueIndex(u, def, x, z)
	for i, c in ipairs(spGetUnitCommands(u, -1) or {}) do
		if c.id == -def and c.params and math.abs(c.params[1] - x) < 2 and math.abs(c.params[3] - z) < 2 then
			return i - 1, c.tag
		end
	end
end

-- a T1 builder for a T2 sentry's T1 walls: one guarding a builder of it, else my nearest T1-wall builder
local function t1Builder(builders, x, z)
	local best, bestD
	for _, u in ipairs(Spring.GetTeamUnits(myTeam) or {}) do
		local ud = UnitDefs[spGetUnitDefID(u) or -1]
		if ud and ud.canMove and ud.isBuilder and not builders[u] and wallOf(u, 1) then
			local first = (spGetUnitCommands(u, 1) or {})[1]
			if first and first.id == CMD.GUARD and builders[first.params and first.params[1] or -1] then
				return u, "guarding"
			end
			local ux, _, uz = Spring.GetUnitPosition(u)
			local d = ux and (ux - x) ^ 2 + (uz - z) ^ 2
			if d and (not bestD or d < bestD) then
				best, bestD = u, d
			end
		end
	end
	return best, best and "nearest"
end

local function wallUp(p)
	local s = sentryOf(p.def)
	if not s then
		return
	end
	local list = {} -- (the builders that took the sentry: an order a builder cannot carry out still comes through
	-- UnitCommand, the commander's Dragon's Claw, and its walls went up around nothing, dev phone 2026-11-20)
	for u in pairs(p.builders) do
		if queueIndex(u, p.def, p.x, p.z) then
			list[#list + 1] = u
		end
	end
	local name = UnitDefs[p.def].name
	if #list == 0 then
		Spring.Echo(string.format("[bardroid-walls] %s: in no builder's queue, no walls", name)) -- (tools)
		return
	end
	local wall, by, mode, how -- (mode: "before" the sentry, "front" of another builder's queue, "after" the sentry)
	if s.tech >= 2 then
		local w2 = wallOf(list[1], 2)
		if w2 and firesOver(s, w2) then
			wall, by, mode, how = w2, list, "before", "before it"
		else -- (T1 walls by a T1 builder, at the front of its queue: "It should issue the command using insert")
			local t1, why = t1Builder(p.builders, p.x, p.z)
			local w1 = t1 and wallOf(t1, 1)
			if w1 and firesOver(s, w1) then
				wall, by, mode, how = w1, { t1 }, "front", string.format("by the T1 builder %s (%s %d), at its queue's front",
					why, UnitDefs[spGetUnitDefID(t1)].name, t1)
			end
		end
	else
		local w1 = wallOf(list[1], 1)
		if w1 and firesOver(s, w1) then
			wall, by, mode, how = w1, list, "after", "after it"
		end
	end
	if not wall then
		Spring.Echo(string.format("[bardroid-walls] %s: no walls (it would not fire over them, or no builder for them)",
			name)) -- (tools)
		return
	end
	local spots = ringSpots(p.def, p.x, p.z, p.facing, wall)
	if #spots == 0 then
		return
	end
	-- (the builder's queue given again with the walls in it: before the command with that tag, or at the front; the
	-- first order replaces the queue, the rest are queued after it, each with its own options. CMD.INSERT did not do:
	-- by the queue's index the first wall went missing, on an idle builder's empty queue all of them, and by a tag
	-- ("alt") they went to the queue's end, dev phone 2026-11-20. The engine's own orders (internal) are left out.)
	local function before(u, tag)
		local orders, done = {}, false
		local function addWalls()
			for _, sp in ipairs(spots) do
				orders[#orders + 1] = { -wall, { sp[1], sp[2], sp[3], 0 }, {} }
			end
			done = true
		end
		if not tag then
			addWalls()
		end
		for _, c in ipairs(spGetUnitCommands(u, -1) or {}) do
			if tag and c.tag == tag then
				addWalls()
			end
			local o = c.options or {}
			if not o.internal then
				local opts = {}
				for _, k in ipairs({ "alt", "ctrl", "meta", "right" }) do
					if o[k] then
						opts[#opts + 1] = k
					end
				end
				orders[#orders + 1] = { c.id, c.params or {}, opts }
			end
		end
		if not done then
			addWalls()
		end
		for i = 2, #orders do
			local opts = orders[i][3]
			opts[#opts + 1] = "shift"
		end
		-- (the sentry's own order goes again with them: not a new placement, or its walls came again each frame)
		local f = Spring.GetGameFrame()
		for _, o in ipairs(orders) do
			if o[1] < 0 and o[2][3] then
				resent[-o[1] .. ":" .. math.floor(o[2][1]) .. ":" .. math.floor(o[2][3])] = f + 15
			end
		end
		Spring.GiveOrderArrayToUnitArray({ u }, orders)
	end
	if mode == "before" then -- (T2: each builder's walls just before the sentry in its queue)
		for _, u in ipairs(by) do
			local _, tag = queueIndex(u, p.def, p.x, p.z)
			if tag then
				before(u, tag)
			end
		end
	elseif mode == "front" then -- (a T1 builder's own queue: the walls at its front, before what it does now)
		local first = (spGetUnitCommands(by[1], 1) or {})[1]
		before(by[1], first and first.tag)
	else -- (T1: after the sentry)
		local orders = {}
		for k, sp in ipairs(spots) do
			orders[k] = { -wall, { sp[1], sp[2], sp[3], 0 }, { "shift" } }
		end
		Spring.GiveOrderArrayToUnitArray(by, orders)
	end
	Spring.Echo(string.format("[bardroid-walls] %s: %d %s around it, %s, %d builder(s)", name, #spots, UnitDefs[wall].name,
		how, #by)) -- (tools)
	if WG.BarDroidWalls then
		WG.BarDroidWalls.last = { def = p.def, wall = wall, n = #spots, spots = spots, x = p.x, z = p.z } -- (tools)
	end
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams)
	if not enabled or cmdID >= 0 or unitTeam ~= myTeam or not cmdParams or #cmdParams < 3 then
		return
	end
	if not sentryOf(-cmdID) then
		return
	end
	local f = Spring.GetGameFrame()
	local key = -cmdID .. ":" .. math.floor(cmdParams[1]) .. ":" .. math.floor(cmdParams[3])
	if resent[key] then
		if f <= resent[key] then
			return
		end
		resent[key] = nil
	end
	local batch = placed[f] or {}
	placed[f] = batch
	local p = batch[key]
	if not p then
		p = { def = -cmdID, x = cmdParams[1], y = cmdParams[2], z = cmdParams[3], facing = cmdParams[4] or 0, builders = {} }
		batch[key] = p
	end
	p.builders[unitID] = true
end

function widget:GameFrame(f)
	for bf, batch in pairs(placed) do
		if bf < f then -- (a frame later: the orders in the builders' queues)
			placed[bf] = nil
			local n = 0
			for _ in pairs(batch) do
				n = n + 1
			end
			if Spring.GetSpectatingState() or not mayOrder() then -- luacheck: ignore 542
				-- (nothing: a spectator, or a host forbidding widgets' orders)
			elseif n > 1 then -- (a line or a grid of sentries: no rings, they would cross)
				Spring.Echo(string.format("[bardroid-walls] %d sentries in one placement: no walls", n)) -- (tools)
			else
				for _, p in pairs(batch) do
					wallUp(p)
				end
			end
		end
	end
end

function widget:PlayerChanged()
	myTeam = Spring.GetMyTeamID()
end

function widget:Initialize()
	readConfig()
	WG.BarDroidWalls = {
		on = function()
			return enabled
		end,
		set = function(on)
			enabled = on and true or false
			writeConfig()
			Spring.Echo("[bardroid-walls] " .. (enabled and "on" or "off")) -- (tools)
		end,
		sentry = function(defID) -- (the place panel: WALLS shown for a sentry only)
			return sentryOf(defID) ~= nil
		end,
		allowed = mayOrder,
	}
end

function widget:Shutdown()
	WG.BarDroidWalls = nil
end
