-- BAR Droid retreat: a hurt unit falls back, a hurt commander retreats behind its army (Kailil, 2026-11-10: "It is
-- insanely hard to micro units on mobile"; touch players must compete fairly with keyboard and mouse, and the decision on
-- that balance is his and BAR's developers'). In a game the player plays (not spectating):
--   - a unit that moves, under HURT of its health, falls back FALLBACK elmos: away from the nearest enemy it sees and
--     toward its team's start spot. Once only, until its health is above REARM again (so a player who sends it back in
--     keeps it there).
--   - a commander under HURT retreats away from the nearest enemy, past its death blast's reach from where it stood; the
--     combat units near it (COVER) take a fight order to that spot, where they cover it at a distance its blast does not
--     reach, and go back to where they were once it is out (at its spot, or RETREAT_SECONDS on); then it waits on patrol
--     (a commander on patrol repairs and reclaims around it) until the player gives it orders. Builders very near it
--     (HELPERS) get a repair order on it put in front of their queues (their queues go on after it).
-- WG.BarDroidRetreat: on(), set(on) (the dock's AUTO RETREAT button; LuaUI/Config/bardroid_retreat.txt keeps it).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid retreat",
		desc = "Hurt units fall back; a hurt commander retreats behind its army, which covers it",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local HURT = 0.5
local REARM = 0.6
local FALLBACK = 600
local COVER = 900 -- elmos around the commander: its cover
local HELPERS = 350 -- elmos around the commander: builders that repair it
local SEE_ENEMY = 1500
local RETREAT_SECONDS = 20
local COMMANDER_REARM_SECONDS = 15 -- (a commander still on the patrol it was given retreats again after this)
local CONFIG = "LuaUI/Config/bardroid_retreat.txt"

local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitCommands = Spring.GetUnitCommands
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spValidUnitID = Spring.ValidUnitID

local enabled = true
local myTeam = Spring.GetMyTeamID()
local playing = false
local pending = {} -- unitID -> true: hurt since the last look
local fell = {} -- unitID -> true: it fell back (or retreated), not again until its health is above REARM
local coms = {} -- commander unitID -> its retreat: { to, since, cover = { unitID = { x, y, z, fx, fz } }, ended }
local blastOf = {} -- unitDefID -> its death blast's radius

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

local function isCommander(ud)
	return ud.customParams and ud.customParams.iscommander ~= nil
end
local function mobile(ud)
	return ud.canMove and not ud.isBuilding and (ud.speed or 0) > 0 and not ud.canKamikaze
end
local function combat(ud)
	return mobile(ud) and not ud.isBuilder and not isCommander(ud) and #(ud.weapons or {}) > 0
end
local function blast(defID, ud)
	local r = blastOf[defID]
	if not r then
		local named = ud.deathExplosion and WeaponDefNames[ud.deathExplosion]
		local wd = named and WeaponDefs[named.id]
		r = wd and (wd.damageAreaOfEffect or 0) or 0
		r = r > 0 and r or 400
		blastOf[defID] = r
	end
	return r
end
local function healthy(u, at)
	local h, mh, _, _, built = spGetUnitHealth(u)
	return h and mh and mh > 0 and (built or 1) >= 1 and h / mh >= at
end

local function onMap(x, z)
	return math.max(48, math.min(Game.mapSizeX - 48, x)), math.max(48, math.min(Game.mapSizeZ - 48, z))
end
local function norm(x, z)
	local d = math.sqrt(x * x + z * z)
	if d < 1 then
		return 0, 0, 0
	end
	return x / d, z / d, d
end
-- the way back from a unit: away from the nearest enemy it sees, and toward the start spot
local function wayBack(u, x, z)
	local ax, az = 0, 0
	local e = Spring.GetUnitNearestEnemy(u, SEE_ENEMY, true)
	local ex, _, ez
	if e then
		ex, _, ez = spGetUnitPosition(e)
	end
	if ex then
		ax, az = norm(x - ex, z - ez)
	end
	local hx, _, hz = Spring.GetTeamStartPosition(myTeam)
	local bx, bz, home = 0, 0, 0
	if hx and (hx > 0 or hz > 0) then
		bx, bz, home = norm(hx - x, hz - z)
	end
	if home < 300 then
		bx, bz = 0, 0 -- (at home: just away)
	end
	local dx, dz = norm(ax + bx, az + bz)
	if dx == 0 and dz == 0 then
		dx, dz = norm(ax ~= 0 and ax or bx, az ~= 0 and az or bz)
	end
	return dx, dz, ex, ez
end

-- the spot dist elmos out along (dx, dz), turned up to 90 degrees where the map's edge would cut that way short (a
-- commander in a corner otherwise backs into the edge and stops there, its chasers on it)
local TURNS = { 0, 30, -30, 60, -60, 90, -90 }
local function openWay(x, z, dx, dz, dist)
	local best, bx, bz
	for _, a in ipairs(TURNS) do
		local r = math.rad(a)
		local cx, cz = dx * math.cos(r) - dz * math.sin(r), dx * math.sin(r) + dz * math.cos(r)
		local tx, tz = x + cx * dist, z + cz * dist
		local mx, mz = onMap(tx, tz)
		local cut = math.sqrt((tx - mx) ^ 2 + (tz - mz) ^ 2)
		if cut < dist * 0.15 then
			return mx, mz
		end
		if not best or cut < best then
			best, bx, bz = cut, mx, mz
		end
	end
	return bx, bz
end

local function say(text)
	local P = WG.BarDroidPad
	if P and P.say then
		P.say(text)
	end
end

-- a unit the player drives right now: ridden in first person (bardroid_padfp.lua) or walked by the pad's D-gun sticks
-- (bardroid_pad.lua): no retreat, cover or repair order over the player's hand
local function driven(u)
	local fp = WG.BarDroidPadFP
	if fp and fp.unit and fp.unit() == u then
		return true
	end
	local pad = WG.BarDroidPad
	if pad and pad.modal then
		local mode, dgunUnit = pad.modal()
		return mode == "dgun" and dgunUnit == u
	end
	return false
end

local function fallBack(u)
	local x, _, z = spGetUnitPosition(u)
	if not x then
		return
	end
	local dx, dz = wayBack(u, x, z)
	if dx == 0 and dz == 0 then
		return
	end
	local tx, tz = openWay(x, z, dx, dz, FALLBACK)
	spGiveOrderToUnit(u, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
	fell[u] = true
	Spring.Echo(string.format("[bardroid-retreat] unit %d falls back", u)) -- (tools)
end

local function commanderRetreat(c, defID, ud)
	local x, _, z = spGetUnitPosition(c)
	if not x then
		return
	end
	local dx, dz = wayBack(c, x, z)
	if dx == 0 and dz == 0 then
		return
	end
	local r = blast(defID, ud)
	local go = math.max(FALLBACK, r + 200) -- (past its blast's reach from where it stood: the cover's spot)
	local tx, tz = openWay(x, z, dx, dz, go)
	spGiveOrderToUnit(c, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
	local cover, helpers = {}, 0
	local near = Spring.GetUnitsInCylinder(x, z, COVER, myTeam) or {}
	local cx, cz, n = 0, 0, 0
	for _, u in ipairs(near) do
		local d = UnitDefs[spGetUnitDefID(u) or -1]
		if u ~= c and d and combat(d) and healthy(u, HURT) and not Spring.GetUnitTransporter(u) and not driven(u) then
			local ux, uy, uz = spGetUnitPosition(u)
			cover[u] = { ux, uy, uz }
			cx, cz, n = cx + ux, cz + uz, n + 1
		end
	end
	if n > 0 then
		cx, cz = cx / n, cz / n
		for u, at in pairs(cover) do -- (each to the commander's spot as it stands to the others: spread, not one heap)
			local ox, oz = at[1] - cx, at[3] - cz
			local _, _, d = norm(ox, oz)
			local k = d > 200 and 200 / d or 1
			local fx, fz = onMap(x + ox * k, z + oz * k)
			at[4], at[5] = fx, fz
			spGiveOrderToUnit(u, CMD.FIGHT, { fx, Spring.GetGroundHeight(fx, fz), fz }, 0)
		end
	end
	for _, u in ipairs(Spring.GetUnitsInCylinder(x, z, HELPERS, myTeam) or {}) do
		local d = UnitDefs[spGetUnitDefID(u) or -1]
		if u ~= c and d and d.isBuilder and d.canRepair ~= false and mobile(d) and not isCommander(d) and not driven(u) then
			spGiveOrderToUnit(u, CMD.INSERT, { 0, CMD.REPAIR, 0, c }, { "alt" })
			helpers = helpers + 1
		end
	end
	coms[c] = { to = { tx, tz }, since = Spring.GetGameFrame(), cover = cover }
	fell[c] = true
	say(n > 0 and string.format("COMMANDER RETREATING, %d COVER", n) or "COMMANDER RETREATING")
	Spring.Echo(string.format("[bardroid-retreat] commander %d retreats %d elmos (blast %d), %d cover, %d repair it", c,
		go, r, n, helpers)) -- (tools)
end

-- the cover's units still on the fight order they were given (or done with it) go back to where they were (a fight
-- order puts the attacks it finds in front of itself: it may be behind them)
local function onOurFight(u, at)
	local q = spGetUnitCommands(u, 4) or {}
	if #q == 0 then
		return true
	end
	for _, c in ipairs(q) do
		if c.id == CMD.FIGHT then
			return c.params and math.abs((c.params[1] or 0) - at[4]) < 8 and math.abs((c.params[3] or 0) - at[5]) < 8
		elseif c.id ~= CMD.ATTACK then
			return false
		end
	end
	return false
end
local function releaseCover(s)
	local back = 0
	for u, at in pairs(s.cover) do
		if spValidUnitID(u) and at[4] then
			if onOurFight(u, at) then
				spGiveOrderToUnit(u, CMD.MOVE, { at[1], at[2], at[3] }, 0)
				back = back + 1
			end
		end
	end
	s.cover = {}
	return back
end

local function onOurMove(c, s)
	local q = spGetUnitCommands(c, 1) or {}
	local first = q[1]
	return not first or (first.id == CMD.MOVE and first.params and math.abs((first.params[1] or 0) - s.to[1]) < 8
		and math.abs((first.params[3] or 0) - s.to[2]) < 8)
end

local function watchCommanders(f)
	for c, s in pairs(coms) do
		if not spValidUnitID(c) or Spring.GetUnitIsDead(c) then
			releaseCover(s)
			coms[c] = nil
		elseif not s.ended and f - s.since < 90 then -- luacheck: ignore 542
			-- (its MOVE not back yet, by ping, or the same frame: read as the player's own orders, the cover let go at once
			-- with no FIGHT kept, the commander's watch dropped; review 2026-11-15)
		elseif not s.ended and not spGetUnitPosition(c) then -- (no place to read, out of sight: let it go)
			releaseCover(s)
			coms[c] = nil
		elseif not s.ended then
			local x, _, z = spGetUnitPosition(c)
			local _, _, d = norm(x - s.to[1], z - s.to[2])
			local ours = onOurMove(c, s)
			if not ours or d < 120 or f - s.since > RETREAT_SECONDS * 30 then
				local back = releaseCover(s)
				if ours then -- (out: it waits on patrol, repairing and reclaiming around it, until given orders)
					local dx, dz = norm(x - s.to[1], z - s.to[2])
					if dx == 0 and dz == 0 then
						dx, dz = 1, 0
					end
					local px, pz = onMap(x - dz * 150, z + dx * 150)
					spGiveOrderToUnit(c, CMD.PATROL, { px, Spring.GetGroundHeight(px, pz), pz }, 0)
					s.ended, s.patrol = f, { px, pz }
				else
					coms[c] = nil -- (the player's orders: it is theirs again)
				end
				Spring.Echo(string.format("[bardroid-retreat] commander %d out%s, %d cover back", c,
					ours and ", on patrol" or " (player's orders)", back)) -- (tools)
			end
		elseif f - s.ended > COMMANDER_REARM_SECONDS * 30 then
			local q = spGetUnitCommands(c, 1) or {}
			if q[1] and q[1].id == CMD.PATROL then
				fell[c] = nil -- (still on its patrol: it may retreat again)
			end
			coms[c] = nil
		end
	end
end

-- whether this game lets the app's widgets give orders: a host can forbid user widgets' Spring.GiveOrder* (BAR's
-- allowunitcontrolwidgets; its handler then throws, and a widget that throws is removed): asked once, as first person
-- asks (bardroid_padfp.lua); as the game's widgets (an engine-branch build) the answer is yes
local canOrder
local function mayOrder()
	if canOrder == nil then
		canOrder = pcall(Spring.GiveOrderToUnitArray, {}, CMD.STOP, {}, 0)
		if not canOrder then
			Spring.Echo("[bardroid-retreat] off: this game's host does not let widgets give orders") -- (tools)
		end
	end
	return canOrder
end

local function lookAt(u)
	if fell[u] or not spValidUnitID(u) or Spring.GetUnitTeam(u) ~= myTeam or driven(u) or not mayOrder() then
		return
	end
	local h, mh, _, _, built = spGetUnitHealth(u)
	if not h or not mh or mh <= 0 or (built or 1) < 1 or h / mh >= HURT then
		return
	end
	local defID = spGetUnitDefID(u)
	local ud = defID and UnitDefs[defID]
	if not ud or not mobile(ud) or Spring.GetUnitTransporter(u) then
		return
	end
	if isCommander(ud) then
		commanderRetreat(u, defID, ud)
	else
		fallBack(u)
	end
end

local function updatePlaying()
	myTeam = Spring.GetMyTeamID()
	playing = not Spring.GetSpectatingState()
end

function widget:Initialize()
	readConfig()
	updatePlaying()
	WG.BarDroidRetreat = {
		on = function()
			return enabled
		end,
		allowed = function() -- (the dock's button says when this game's host forbids it)
			return mayOrder()
		end,
		set = function(on)
			enabled = on and true or false
			writeConfig()
			pending = {}
			Spring.Echo("[bardroid-retreat] " .. (enabled and "on" or "off")) -- (tools)
		end,
	}
end

function widget:Shutdown()
	WG.BarDroidRetreat = nil
end

function widget:PlayerChanged()
	updatePlaying()
end

-- catching up with a running game (a rejoin replays it from the start): no retreat then, every past hurt unit fell back
-- and every past commander retreat pulled its cover again, hundreds of orders landing at the live frame (bardroid_touch.lua
-- tells; review 2026-11-15)
local function catchingUp()
	local f = WG.BarDroidCatchingUp
	return f and f() or false
end

function widget:UnitDamaged(unitID, _, unitTeam, damage, paralyzer)
	if enabled and playing and unitTeam == myTeam and not paralyzer and damage > 0 and not fell[unitID]
		and not catchingUp() then
		pending[unitID] = true
	end
end

function widget:UnitDestroyed(unitID)
	pending[unitID], fell[unitID] = nil, nil
end

function widget:UnitGiven(unitID)
	fell[unitID] = nil
end

function widget:UnitTaken(unitID) -- (given away: not ours to order; a retreating commander's cover goes back)
	pending[unitID], fell[unitID] = nil, nil
	if coms[unitID] then
		releaseCover(coms[unitID])
		coms[unitID] = nil
	end
end

function widget:GameFrame(f)
	if not enabled or not playing then
		return
	end
	if catchingUp() then
		pending = {}
		return
	end
	if f % 3 == 0 and next(pending) then
		local look = pending
		pending = {}
		for u in pairs(look) do
			lookAt(u)
		end
	end
	if f % 15 == 0 then
		watchCommanders(f)
		for u in pairs(fell) do
			if not coms[u] and (not spValidUnitID(u) or healthy(u, REARM)) then
				fell[u] = nil
			end
		end
	end
end
