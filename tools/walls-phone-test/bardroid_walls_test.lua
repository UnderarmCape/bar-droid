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
local D = {}
for _, n in ipairs({ "armllt", "armdrag", "armclaw", "armrl", "armhlt", "armbeamer", "armguard", "armbrtha", "armrad",
	"armjamt", "armtl", "cortron", "armemp", "armsilo", "armamd", "armvulc", "armanni", "armamb", "armpb", "corvipe",
	"cortoast", "legacluster", "legapopupdef", "cordoom", "corpun", "legmg", "armfort", "corint", "leglrpc" }) do
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
		else
			Spring.Echo("[wallstest] (the Sentry's tile out of sight: picked as the build menu does)")
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
	elseif stage == "shot" then
		Spring.SetActiveCommand(0)
		Spring.SelectUnitArray({ com })
		ask("shot", 0, 0, "off", f)
	elseif stage == "off" then
		WG.BarDroidWalls.set(false)
		spot2 = freeSpot(spot)
		if spot2 then
			shiftBuild(D.armllt, spot2)
		end
		go("off?", f)
	elseif stage == "off?" and f - stageAt > 30 then
		local q = queue()
		check("WALLS off: a second Sentry queued, no walls with it", count(q, D.armllt) == 2 and count(q, D.armdrag) == 8,
			count(q, D.armllt) .. " Sentries, " .. count(q, D.armdrag) .. " walls")
		WG.BarDroidWalls.set(true)
		-- (a Dragon's Claw and an AA launcher: none either; at the second spot and beside it)
		if spot2 then
			shiftBuild(D.armclaw, { spot2[1] + 160, spot2[2], spot2[3] })
		end
		go("claw?", f)
	elseif stage == "claw?" and f - stageAt > 30 then
		local q = queue()
		-- (the commander may not build Claws: its order then refused, still no walls around nothing)
		check("a Dragon's Claw (too low to fire over them): no walls", count(q, D.armdrag) == 8,
			count(q, D.armclaw) .. " Claws queued, " .. count(q, D.armdrag) .. " walls")
		if spot2 then
			shiftBuild(D.armrl, { spot2[1] - 160, spot2[2], spot2[3] })
		end
		go("aa?", f)
	elseif stage == "aa?" and f - stageAt > 30 then
		local q = queue()
		check("an AA launcher: no walls", count(q, D.armdrag) == 8,
			count(q, D.armrl) .. " AA queued, " .. count(q, D.armdrag) .. " walls")
		if spot2 then -- (two Sentries in one placement, as a LINE: none)
			shiftBuild(D.armllt, { spot2[1], spot2[2], spot2[3] + 200 })
			shiftBuild(D.armllt, { spot2[1], spot2[2], spot2[3] + 300 })
		end
		go("two?", f)
	elseif stage == "two?" and f - stageAt > 30 then
		local q = queue()
		check("two Sentries in one placement: no walls", count(q, D.armllt) == 4 and count(q, D.armdrag) == 8,
			count(q, D.armllt) .. " Sentries, " .. count(q, D.armdrag) .. " walls")
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
