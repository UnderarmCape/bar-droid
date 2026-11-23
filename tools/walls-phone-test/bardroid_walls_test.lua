-- LuaUI widget for tools/walls-phone-test.ps1: walls around a placed sentry (bardroid_walls.lua; Kailil, 2026-11-20).
-- In a skirmish: the commander picked, its Sentry (Armada's light laser tower) picked on the dock, a spot tapped and
-- PLACE tapped, by the script's real taps (asked for by "do <n> tap|shot <x> <y> <vsx>" in
-- LuaUI/Config/bardroid_wallstest.txt, answered "<n>" in bardroid_wallstest_cmd.txt). Checked: which defences count as
-- sentries; the Sentry first in the commander's queue, then a closed ring of Dragon's Teeth around it; with WALLS off, a
-- Sentry queued alone; a Dragon's Claw (too low to fire over them) and an AA launcher get none; two Sentries in one
-- placement get none. The T2 sentries' facts are logged for the T2 cases. "[wallstest] done: ALL PASS" or "N FAILED".
function widget:GetInfo()
	return { name = "BAR Droid walls test", desc = "Walls around a placed sentry", author = "BAR Droid", layer = 0,
		enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_wallstest.txt", "LuaUI/Config/bardroid_wallstest_cmd.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local com, spot, spot2
local twoGiven = 0 -- (the two-Sentries case: how many were placed)
local clawAt, aaAt -- (the Claw's and the AA launcher's spots)
local t2 -- the T2 cases: their builders and spots
local D = {}
for _, n in ipairs({ "armllt", "armdrag", "armclaw", "armrl", "armhlt", "armbeamer", "armguard", "armbrtha", "armrad",
	"armjamt", "armtl", "cortron", "armemp", "armsilo", "armamd", "armvulc", "armanni", "armamb", "armpb", "corvipe",
	"cortoast", "legacluster", "legapopupdef", "cordoom", "corpun", "legmg", "armfort", "corint", "leglrpc", "corfort" }) do
	D[n] = UnitDefNames[n] and UnitDefNames[n].id
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[wallstest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end
local function readCmd()
	local f = io.open(CMD_FILE, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end
local function go(s, f)
	stage, stageAt = s, f
end
local function ask(action, x, y, nextStage, f)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx))
	after = nextStage
	go("asked", f)
end

-- X pixels (top left origin) of a ground point in sight above the dock, or nil
local function screenOf(x, z)
	local sx, sy, sz = Spring.WorldToScreenCoords(x, Spring.GetGroundHeight(x, z), z)
	local vsx, vsy = Spring.GetViewGeometry()
	local P = WG.BarDroidPortrait
	local dock = P and P.dock and P.dock()
	if sz > 1 or sx < 80 or sx > vsx - 80 or sy < (dock and dock[4] or 0) + 120 or sy > vsy - 200 then
		return nil
	end
	return math.floor(sx), math.floor(vsy - sy)
end
-- a spot near the commander for a Sentry with room for its whole ring, in sight above the dock (not near "avoid")
local function freeSpot(avoid)
	local cx, _, cz = Spring.GetUnitPosition(com)
	for r = 260, 1100, 60 do
		for a = 0, 345, 15 do
			local x, z = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
			local bx, by, bz = Spring.Pos2BuildPos(D.armllt, x, Spring.GetGroundHeight(x, z), z, 0)
			local far = not avoid or math.abs(bx - avoid[1]) + math.abs(bz - avoid[3]) > 400
			-- (2: rocks there, the builder reclaims them; the test map is strewn with them, none was ever 3)
			if far and Spring.TestBuildOrder(D.armllt, bx, by, bz, 0) >= 2 and screenOf(bx, bz) then
				local ok = true
				for dx = -32, 32, 32 do
					for dz = -32, 32, 32 do
						if (dx ~= 0 or dz ~= 0) and Spring.TestBuildOrder(D.armdrag, bx + dx, by, bz + dz, 0) < 2 then
							ok = false
						end
					end
				end
				if ok then
					return { bx, by, bz }
				end
			end
		end
	end
end
-- the commander's queue: its build orders as { def, x, z } in order
local function queue()
	local out = {}
	for _, c in ipairs(Spring.GetUnitCommands(com, -1) or {}) do
		if c.id < 0 then
			out[#out + 1] = { -c.id, c.params[1], c.params[3] }
		end
	end
	return out
end
local function count(q, def)
	local n = 0
	for _, o in ipairs(q) do
		if o[1] == def then
			n = n + 1
		end
	end
	return n
end
-- a unit's queue: build orders as { def, x, z }, with others too ("guard" etc.) when all
local function queueOf(u, all)
	local out = {}
	for _, c in ipairs(Spring.GetUnitCommands(u, -1) or {}) do
		if c.id < 0 then
			out[#out + 1] = { -c.id, c.params[1], c.params[3] }
		elseif all then
			out[#out + 1] = { c.id == CMD.GUARD and "guard" or tostring(c.id) }
		end
	end
	return out
end
-- (the last ring's spots not in a unit's queue: where, from the sentry's middle, and whether buildable now)
local function missing(u)
	local L = WG.BarDroidWalls.last
	if not L then
		return "no ring"
	end
	local out = {}
	for _, s in ipairs(L.spots or {}) do
		local found = false
		for _, c in ipairs(Spring.GetUnitCommands(u, -1) or {}) do
			if c.id == -L.wall and math.abs(c.params[1] - s[1]) < 2 and math.abs(c.params[3] - s[3]) < 2 then
				found = true
			end
		end
		if not found then
			out[#out + 1] = string.format("%+d,%+d (test %d)", s[1] - L.x, s[3] - L.z, Spring.TestBuildOrder(L.wall, s[1],
				s[2], s[3], 0))
		end
	end
	return #out == 0 and "none missing" or ("missing " .. table.concat(out, "; "))
end
-- a spot near a unit for a building with room for a ring of walls (not near "avoid"); no need to be in sight
local function freeNear(def, wallDef, near, avoid, awayFrom)
	local cx, _, cz = Spring.GetUnitPosition(near)
	local ax, az
	if awayFrom then -- (a spot on the far side of "near" from that unit: "near" the nearer builder by far)
		ax, _, az = Spring.GetUnitPosition(awayFrom)
	end
	local ud, wd = UnitDefs[def], UnitDefs[wallDef]
	local reach = math.max(ud.xsize, ud.zsize) * 4 + wd.xsize * 8 + 16
	for r = 200, 1000, 60 do
		for a = 0, 345, 15 do
			local x, z = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
			local bx, by, bz = Spring.Pos2BuildPos(def, x, Spring.GetGroundHeight(x, z), z, 0)
			local far = true -- (avoid: one spot or a list of them)
			for _, s in ipairs(avoid and (type(avoid[1]) == "table" and avoid or { avoid }) or {}) do
				far = far and math.abs(bx - s[1]) + math.abs(bz - s[3]) > 500
			end
			if ax then
				far = far and math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) > math.sqrt((bx - cx) ^ 2 + (bz - cz) ^ 2) + 400
			end
			if far and Spring.TestBuildOrder(def, bx, by, bz, 0) >= 2 then
				local ok = true
				for dx = -reach, reach, 16 do
					for dz = -reach, reach, 16 do
						if Spring.TestBuildOrder(wallDef, bx + dx, by, bz + dz, 0) < 2 then
							ok = false
						end
					end
				end
				if ok then
					return { bx, by, bz }
				end
			end
		end
	end
end
-- "no walls" by the walls widget's own word: no new ring since "before" (its last ring the same) and no more Dragon's
-- Teeth queued than then (the commander builds meanwhile: a fixed count of 8 broke when it finished one, 2026-11-20)
local before
local function noNewRing()
	return before and WG.BarDroidWalls.last == before.last and count(queue(), D.armdrag) <= before.walls
end
local function ringSaid()
	return string.format("%s new ring, %d walls (before %d)", WG.BarDroidWalls.last == (before and before.last) and "no" or "a",
		count(queue(), D.armdrag), before and before.walls or -1)
end
local function shiftBuild(def, s)
	Spring.GiveOrderToUnit(com, -def, { s[1], s[2], s[3], 0 }, { "shift" })
end

function widget:GameFrame(f)
	if stage == "wait" and f >= 300 then
		com = (Spring.GetTeamUnits(Spring.GetMyTeamID()) or {})[1]
		local W = WG.BarDroidWalls
		if not (W and W.sentry and D.armllt and D.armdrag) then
			check("bardroid_walls.lua running, Armada's Sentry and Dragon's Teeth there", false, tostring(W))
			go("end", f)
			return
		end
		W.set(true)
		-- which defences are sentries (walls possible)
		local want = { armllt = true, armhlt = true, armbeamer = true, armclaw = true, armrl = false, armbrtha = false,
			armrad = false, armjamt = false, armtl = false, cortron = false, armemp = false, armsilo = false,
			armamd = false, armvulc = false }
		local wrong = {}
		for n, w in pairs(want) do
			if D[n] and W.sentry(D[n]) ~= w then
				wrong[#wrong + 1] = n .. (w and " not" or " counted")
			end
		end
		check("sentries: towers yes; AA, LRPC, radar, jammer, torpedo, tactical missiles, nukes, antinuke no", #wrong == 0,
			#wrong == 0 and "as expected" or table.concat(wrong, ", "))
		for _, n in ipairs({ "armamb", "armanni", "armpb", "armguard", "corvipe", "cortoast", "legacluster", "legapopupdef",
			"cordoom", "corpun", "legmg", "armdrag", "armfort", "armllt", "armhlt", "armclaw", "armbrtha", "corint", "leglrpc",
			"armbeamer" }) do -- (the facts the T2 cases are planned from)
			local ud = D[n] and UnitDefs[D[n]]
			if ud then
				local range, arcs, kinds = 0, true, {}
				for _, w in ipairs(ud.weapons or {}) do
					local wd = WeaponDefs[w.weaponDef]
					range = math.max(range, wd and wd.range or 0)
					arcs = arcs and wd and (wd.type == "StarburstLauncher" or (wd.type == "Cannon" and (wd.highTrajectory or 0) > 0))
						or false
					kinds[#kinds + 1] = wd and (wd.type .. "/" .. tostring(wd.highTrajectory)) or "?"
				end
				Spring.Echo(string.format("[wallstest] (%s: height %.0f, range %.0f, arcs %s (%s), tech %s, sentry %s)", n,
					ud.height or 0, range, tostring(arcs), table.concat(kinds, " "),
					tostring(ud.customParams and ud.customParams.techlevel), tostring(W.sentry(D[n]))))
			end
		end
		Spring.SelectUnitArray({ com })
		go("picked", f)
	elseif stage == "picked" and f - stageAt > 20 then
		-- the Sentry's tile on the dock's build grid; picked through the build menu when scrolled out of sight
		local P = WG.BarDroidPortrait
		local r = P and P.itemCell and P.itemCell("left", function(it)
			return it.kind == "build" and it.defID == D.armllt
		end)
		local dock = P and P.dock and P.dock()
		local _, vsy = Spring.GetViewGeometry()
		if r and dock and r[2] >= dock[2] and r[4] <= dock[4] then
			ask("tap", (r[1] + r[3]) / 2, vsy - (r[2] + r[4]) / 2, "tile", f)
		else -- (said as not run: picked by the test itself, the dock's pick proves nothing, the walls' checks still do; the
			-- dock's grid taps are dock-phone-test's; vacuous-pass audit, 2026-11-23)
			Spring.Echo("[wallstest] NOT RUN the Sentry's tile tapped on the dock's build grid (scrolled out of sight): picked "
				.. "as the build menu does")
			Spring.SetActiveCommand(Spring.GetCmdDescIndex(-D.armllt) or 0)
			go("tile", f)
		end
	elseif stage == "tile" and f - stageAt > 20 then
		local _, cmd = Spring.GetActiveCommand()
		check("the Sentry picked on the dock", cmd == -D.armllt, cmd)
		spot = freeSpot()
		if not spot then
			check("a free spot with room for a ring, in sight", false, "none")
			go("end", f)
			return
		end
		local sx, sy = screenOf(spot[1], spot[3])
		ask("tap", sx, sy, "spotted", f)
	elseif stage == "spotted" and f - stageAt > 25 then
		local B = WG.bardroidBuildmenu
		local p = B and B.droidPanel and B.droidPanel()
		if not p then
			check("the PLACE panel after the spot's tap", false, "none")
			go("end", f)
			return
		end
		local _, vsy = Spring.GetViewGeometry()
		local below = math.max(p.rotate and p.rotate[4] or p.place[2], p.cancel and p.cancel[4] or p.place[2])
		ask("tap", (p.place[1] + p.place[3]) / 2, vsy - (below + p.place[4]) / 2, "placed", f)
	elseif stage == "placed" and f - stageAt > 45 then
		local q = queue()
		local first = q[1]
		local atSpot = first and first[1] == D.armllt and math.abs(first[2] - spot[1]) < 24 and math.abs(first[3] - spot[3]) < 24
		local ring, off = 0, 0
		for i = 2, #q do
			if q[i][1] == D.armdrag then
				local dx, dz = math.abs(q[i][2] - first[2]), math.abs(q[i][3] - first[3])
				if math.max(dx, dz) >= 24 and math.max(dx, dz) <= 40 then
					ring = ring + 1
				else
					off = off + 1
				end
			end
		end
		check("PLACE tapped: the Sentry first in the commander's queue, at the spot", atSpot,
			first and (UnitDefs[first[1]].name .. " at " .. math.floor(first[2]) .. "," .. math.floor(first[3])) or "empty")
		check("then a closed ring of Dragon's Teeth around it (8, side by side)", ring == 8 and off == 0,
			ring .. " in the ring, " .. off .. " elsewhere")
		go("shot", f)
	elseif stage == "shot" then -- (the Sentry picked again: the PLACE panel with WALLS, a picture, then WALLS tapped)
		Spring.SelectUnitArray({ com })
		Spring.SetActiveCommand(Spring.GetCmdDescIndex(-D.armllt) or 0)
		go("shot2", f)
	elseif stage == "shot2" and f - stageAt > 20 then
		ask("shot", 0, 0, "wallsbtn", f)
	elseif stage == "wallsbtn" or stage == "wallsbtn2" then
		local B = WG.bardroidBuildmenu
		local p = B and B.droidPanel and B.droidPanel()
		if not (p and p.walls) then
			check("WALLS in the PLACE panel, the Sentry picked", false, p and "no walls button" or "no panel")
			Spring.SetActiveCommand(0)
			go("off", f)
			return
		end
		local _, vsy = Spring.GetViewGeometry()
		ask("tap", (p.walls[1] + p.walls[3]) / 2, vsy - (p.walls[2] + p.walls[4]) / 2,
			stage == "wallsbtn" and "walls1?" or "walls2?", f)
	elseif stage == "walls1?" and f - stageAt > 20 then
		check("WALLS tapped in the PLACE panel: off", WG.BarDroidWalls.on() == false, WG.BarDroidWalls.on())
		go("wallsbtn2", f)
	elseif stage == "walls2?" and f - stageAt > 20 then
		check("WALLS tapped again: on, the Sentry still picked", WG.BarDroidWalls.on() == true
			and select(2, Spring.GetActiveCommand()) == -D.armllt, tostring(WG.BarDroidWalls.on()) .. ", picked "
				.. tostring(select(2, Spring.GetActiveCommand())))
		Spring.SetActiveCommand(0)
		go("off", f)
	elseif stage == "off" then
		WG.BarDroidWalls.set(false)
		before = { last = WG.BarDroidWalls.last, walls = count(queue(), D.armdrag) }
		spot2 = freeSpot(spot)
		if spot2 then
			shiftBuild(D.armllt, spot2)
		end
		go("off?", f)
	elseif stage == "off?" and f - stageAt > 30 then
		local q = queue()
		local queued = false
		for _, o in ipairs(q) do
			queued = queued or (spot2 and o[1] == D.armllt and math.abs(o[2] - spot2[1]) < 24 and math.abs(o[3] - spot2[3]) < 24)
		end
		check("WALLS off: a second Sentry queued, no walls with it", queued and noNewRing(), (queued and "queued" or "not queued")
			.. ", " .. ringSaid())
		WG.BarDroidWalls.set(true)
		-- (an AA launcher: none either; on open ground with room for a ring, away from the Sentries. The Dragon's Claw
		-- comes with the T2 cases' builders: the commander builds none, its order refused, "0 Claws queued", and the
		-- check had passed on nothing, 2026-11-20)
		before = { last = WG.BarDroidWalls.last, walls = count(queue(), D.armdrag) }
		aaAt = spot2 and freeNear(D.armrl, D.armdrag, com, { spot, spot2 })
		if aaAt then
			shiftBuild(D.armrl, aaAt)
		end
		go("aa?", f)
	elseif stage == "aa?" and f - stageAt > 30 then
		local q = queue()
		local n = count(q, D.armrl)
		check("an AA launcher: queued, no walls", n >= 1 and noNewRing(), n .. " AA queued, " .. ringSaid())
		before = { last = WG.BarDroidWalls.last, walls = count(queue(), D.armdrag), sentries = count(queue(), D.armllt) }
		twoGiven = 0
		if spot2 then -- (two Sentries in one placement, as a LINE: none; two buildable spots, one fixed pair was blocked)
			local found = {}
			for dz = 200, 900, 50 do
				for _, sz in ipairs({ 1, -1 }) do
					local x, z = spot2[1], spot2[3] + dz * sz
					local bx, by, bz = Spring.Pos2BuildPos(D.armllt, x, Spring.GetGroundHeight(x, z), z, 0)
					local apart = not found[1] or math.abs(bz - found[1][3]) >= 100
					-- (and clear of the first Sentry's ring: one was given over a queued wall, which the engine then
					-- dropped, 7 walls left, 2026-11-20)
					local clear = true -- (and of the Claw and the AA launcher)
					for _, s in ipairs({ spot, clawAt or spot, aaAt or spot }) do
						clear = clear and math.abs(bx - s[1]) + math.abs(bz - s[3]) > 250
					end
					if #found < 2 and apart and clear and Spring.TestBuildOrder(D.armllt, bx, by, bz, 0) >= 2 then
						found[#found + 1] = { bx, by, bz }
					end
				end
			end
			for _, s in ipairs(found) do
				shiftBuild(D.armllt, s)
			end
			twoGiven = #found
		end
		go("two?", f)
	elseif stage == "two?" and f - stageAt > 30 then
		local q = queue()
		-- (the walls widget's own word: no new ring; one of the two orders now and then refused, its spot under one queued
		-- before. Two placed and at least one more Sentry queued: with none given "no ring" passed by itself)
		local more = count(q, D.armllt) - (before.sentries or 0)
		check("two Sentries in one placement: no walls", twoGiven == 2 and more >= 1 and noNewRing(), string.format(
			"%d placed, %d more Sentries queued, %s", twoGiven, more, ringSaid()))
		Spring.SendCommands("cheat 1") -- (the T2 cases: builders given, the give a second later)
		go("t2cheat", f)
	elseif stage == "t2cheat" and f - stageAt > 30 then
		local x, y, z = Spring.GetUnitPosition(com)
		local team = Spring.GetMyTeamID()
		t2 = { at = { x, y, z } }
		Spring.SendCommands(string.format("give 1 armack %d @%d,%d,%d", team, x + 400, y, z))
		Spring.SendCommands(string.format("give 1 corack %d @%d,%d,%d", team, x - 400, y, z))
		Spring.SendCommands(string.format("give 1 corck %d @%d,%d,%d", team, x - 400, y, z + 120))
		-- (an Armada con bot for the Dragon's Claw, 700 off towards the map's middle: away from the Cortex builders)
		local sz = z < Game.mapSizeZ / 2 and 1 or -1
		Spring.SendCommands(string.format("give 1 armck %d @%d,%d,%d", team, x, y, z + 700 * sz))
		go("t2given", f)
	elseif stage == "t2given" and f - stageAt > 45 then
		for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
			local d = Spring.GetUnitDefID(u)
			if d == UnitDefNames.armack.id then
				t2.armack = u
			elseif d == UnitDefNames.corack.id then
				t2.corack = u
			elseif d == UnitDefNames.corck.id then
				t2.corck = u
			elseif d == UnitDefNames.armck.id then
				t2.armck = u
			end
		end
		if not (t2.armack and t2.corack and t2.corck and t2.armck) then
			check("the T2 cases' builders given", false, tostring(t2.armack) .. " " .. tostring(t2.corack) .. " "
				.. tostring(t2.corck) .. " " .. tostring(t2.armck))
			go("end", f)
			return
		end
		-- a Dragon's Claw (a sentry, 18 tall: too low to fire over Dragon's Teeth) by Armada's con bot: no walls
		before = { last = WG.BarDroidWalls.last, walls = count(queueOf(t2.armck), D.armdrag) }
		clawAt = freeNear(D.armclaw, D.armdrag, t2.armck, { spot, spot2 or spot, aaAt or spot })
		if clawAt then
			Spring.GiveOrderToUnit(t2.armck, -D.armclaw, { clawAt[1], clawAt[2], clawAt[3], 0 }, {})
		end
		go("claw?", f)
	elseif stage == "claw?" and f - stageAt > 30 then
		local q = queueOf(t2.armck)
		local n, walls = count(q, D.armclaw), count(q, D.armdrag)
		local same = WG.BarDroidWalls.last == before.last
		check("a Dragon's Claw (too low to fire over them): queued, no walls", clawAt and n == 1 and walls == 0 and same,
			string.format("%s%d Claws queued, %s new ring, %d walls", clawAt and "" or "no spot; ", n, same and "no" or "a", walls))
		Spring.GiveOrderToUnit(t2.armck, CMD.STOP, {}, {})
		go("anni", f)
	elseif stage == "anni" then
		-- (A) the Annihilator by Armada's T2 con bot: Fortification Walls first, then it
		t2.anni = freeNear(D.armanni, D.armfort, t2.armack)
		if t2.anni then
			Spring.GiveOrderToUnit(t2.armack, -D.armanni, { t2.anni[1], t2.anni[2], t2.anni[3], 0 }, {})
		end
		Spring.GiveOrderToUnit(t2.corck, CMD.GUARD, { t2.corack }, {})
		go("anni?", f)
	elseif stage == "anni?" and f - stageAt > 30 then
		local q = queueOf(t2.armack)
		local walls, last = count(q, D.armfort), q[#q]
		local wallsFirst = last and last[1] == D.armanni and walls == #q - 1
		local L = WG.BarDroidWalls.last or {}
		check("a T2 sentry (the Annihilator, 88 tall): Fortification Walls round it, all before it in the T2 builder's queue",
			t2.anni and walls >= 8 and wallsFirst and walls == L.n, (t2.anni and "" or "no spot; ") .. walls .. " walls of "
				.. tostring(L.n) .. ", then " .. (last and UnitDefs[last[1]].name or "nothing") .. "; " .. missing(t2.armack))
		-- (B) the Viper (50 tall, missiles: not over a Fortification Wall) by Cortex's T2 con, a T1 con guarding it
		t2.viper = freeNear(D.corvipe, UnitDefNames.cordrag.id, t2.corack)
		if t2.viper then
			Spring.GiveOrderToUnit(t2.corack, -D.corvipe, { t2.viper[1], t2.viper[2], t2.viper[3], 0 }, {})
		end
		go("viper?", f)
	elseif stage == "viper?" and f - stageAt > 30 then
		local qa, qc = queueOf(t2.corack), queueOf(t2.corck, true)
		local drag = UnitDefNames.cordrag.id
		local front, n = 0, count(qc, drag)
		for _, o in ipairs(qc) do -- (the walls at the front, the guard after them)
			if o[1] ~= drag then
				break
			end
			front = front + 1
		end
		local guardLast = qc[#qc] and qc[#qc][1] == "guard"
		local L = WG.BarDroidWalls.last or {}
		check("a T2 sentry too low for T2 walls (the Viper): Dragon's Teeth by the T1 con guarding it, at its queue's front",
			t2.viper and n >= 8 and front == n and guardLast and n == L.n, (t2.viper and "" or "no spot; ") .. n
				.. " walls of " .. tostring(L.n) .. ", " .. front .. " at the front, the guard " .. (guardLast and "after them" or "gone")
				.. "; " .. missing(t2.corck))
		check("... and none by the T2 con, its Viper alone", count(qa, D.corvipe) == 1 and count(qa, D.corfort) == 0
			and count(qa, drag) == 0, #qa .. " orders")
		-- (C) no guard: the nearest T1 builder (the Cortex con beside the spot, the commander farther off)
		Spring.GiveOrderToUnit(t2.corck, CMD.STOP, {}, {})
		Spring.GiveOrderToUnit(t2.corack, CMD.STOP, {}, {})
		go("viper2", f)
	elseif stage == "viper2" and f - stageAt > 10 then
		t2.viper2 = freeNear(D.corvipe, UnitDefNames.cordrag.id, t2.corck, t2.viper, com)
			-- (none on the con's far side from the commander at one start: anywhere near it, the nearest T1 builder then
			-- worked out below as the walls widget does, 2026-11-20)
			or freeNear(D.corvipe, UnitDefNames.cordrag.id, t2.corck, t2.viper)
		if t2.viper2 then
			Spring.GiveOrderToUnit(t2.corack, -D.corvipe, { t2.viper2[1], t2.viper2[2], t2.viper2[3], 0 }, {})
		end
		go("viper2?", f)
	elseif stage == "viper2?" and f - stageAt > 30 then
		-- (the nearest mobile builder with a T1 wall to the spot, not the T2 con: as bardroid_walls.lua's t1Builder)
		local near, nd = t2.corck, nil
		if t2.viper2 then
			for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
				local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
				local t1wall = false
				for _, b in ipairs(ud and ud.buildOptions or {}) do
					local bd = UnitDefs[b]
					t1wall = t1wall or (bd.customParams and bd.customParams.objectify and (tonumber(bd.customParams.techlevel)
						or 1) < 2 and (bd.minWaterDepth or 0) <= 0)
				end
				if ud and ud.canMove and ud.isBuilder and u ~= t2.corack and t1wall then
					local x, _, z = Spring.GetUnitPosition(u)
					local d = (x - t2.viper2[1]) ^ 2 + (z - t2.viper2[3]) ^ 2
					if not nd or d < nd then
						near, nd = u, d
					end
				end
			end
		end
		local L = WG.BarDroidWalls.last or {}
		local qc = queueOf(near, true)
		local n = 0 -- (the walls at its queue's front: the commander, if it is the nearest, has older orders behind them)
		for _, o in ipairs(qc) do
			if o[1] ~= L.wall then
				break
			end
			n = n + 1
		end
		check("no guard: the nearest T1 builder (" .. UnitDefs[Spring.GetUnitDefID(near)].name .. ") given the walls at its "
			.. "queue's front", t2.viper2 and n >= 8 and n == L.n,
			(t2.viper2 and "" or "no spot; ") .. n .. " walls of " .. #qc .. " orders; the T2 con's queue: "
				.. #queueOf(t2.corack, true) .. " orders" .. (t2.viper2 and string.format(", the spot %d,%d test %d",
				t2.viper2[1], t2.viper2[3], Spring.TestBuildOrder(D.corvipe, t2.viper2[1], t2.viper2[2], t2.viper2[3], 0)) or ""))
		go("end", f)
	elseif stage == "end" then
		Spring.Echo("[wallstest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		write("end\n")
		go("over", f)
	end
	if stage == "asked" and f % 3 == 0 then
		local c = readCmd()
		if c and tonumber(c) == asked then
			go(after, f)
		elseif f - stageAt > 30 * 30 then
			check("the script's " .. after .. " step", false, "not done in 30 s")
			go("end", f)
		end
	end
end
