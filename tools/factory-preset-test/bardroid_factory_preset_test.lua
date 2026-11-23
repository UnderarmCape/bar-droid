-- LuaUI widget for tools/factory-preset-test.ps1: a factory's preset (bardroid_presets.lua factoryForms; Kailil,
-- 2026-11-20: "give factories the preset functionality, where any units that come out of it, join the formation
-- assigned by the factory and the continuously expand the formation"). In a skirmish (cheats on, nothing costs): a Bot
-- Lab given beside the commander and picked, STRAFE picked for it; "aim x y vsx" in LuaUI/Config/bardroid_factorytest.txt
-- (X screen pixels, top left origin) for the script's real tap on the map there; then five Pawns built, then three more:
-- each must join the formation, take a place of its own in it, and on its place go side to side on repeat at once.
-- Then a sent preset's units arriving apart (two Pawns at the aim, two far off, STRAFE sent to all four): each goes
-- side to side as it gets there, the first two while the far two are still on their way.
-- "[factorytest] PASS|FAIL <case>", "[factorytest] done: ALL PASS" or "N FAILED".
function widget:GetInfo()
	return { name = "BAR Droid factory preset test", desc = "A factory's preset, its units joining", author = "BAR Droid",
		layer = 0, enabled = true }
end

local OUT = "LuaUI/Config/bardroid_factorytest.txt"
local fails, stage, stageAt = 0, "wait", 0
local com, lab, aimX, aimZ
local camAim -- (the camera when the aim was named)
local out = {} -- the Pawns out of the lab, in order
local firstPlaces -- the first five's places, [unit] = { x, z }
local given, strafe = {}, nil -- the strafe case's Pawns (given, not from the lab); { near, far, all }
local labDef, pawnDef = UnitDefNames.armlab and UnitDefNames.armlab.id, UnitDefNames.armpw and UnitDefNames.armpw.id

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[factorytest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end
local function go(s, f)
	stage, stageAt = s, f
end

function widget:UnitCreated(unitID, unitDefID, teamID)
	if teamID == Spring.GetMyTeamID() and unitDefID == labDef and not lab then
		lab = unitID
	end
	if stage == "strafegive" and teamID == Spring.GetMyTeamID() and unitDefID == pawnDef then
		given[#given + 1] = unitID
	end
end
function widget:UnitFromFactory(unitID, unitDefID, _, factID)
	if factID == lab and unitDefID == pawnDef then
		out[#out + 1] = unitID
	end
end

-- a point of open ground in sight above the dock, ~550 elmos from the lab toward the map's middle
local function aimPoint()
	local lx, _, lz = Spring.GetUnitPosition(lab)
	local vsx, vsy = Spring.GetViewGeometry()
	local P = WG.BarDroidPortrait
	local dock = P and P.dock and P.dock()
	local top = dock and dock[4] or 0
	local mx, mz = Game.mapSizeX / 2, Game.mapSizeZ / 2
	local base = math.atan2(mz - lz, mx - lx)
	for r = 550, 300, -50 do
		for _, d in ipairs({ 0, 30, -30, 60, -60, 90, -90, 120, -120, 180 }) do
			local a = base + math.rad(d)
			local x, z = lx + math.cos(a) * r, lz + math.sin(a) * r
			local sx, sy, sz = Spring.WorldToScreenCoords(x, Spring.GetGroundHeight(x, z), z)
			if sz <= 1 and sx > 80 and sx < vsx - 80 and sy > top + 120 and sy < vsy - 200 then
				return x, z, math.floor(sx), math.floor(vsy - sy), vsx
			end
		end
	end
end

local function sway(u)
	local st = Spring.GetUnitStates(u)
	local q = Spring.GetUnitCommands(u, 5) or {}
	local fights = 0
	for _, c in ipairs(q) do
		fights = fights + (c.id == CMD.FIGHT and 1 or 0)
	end
	return st and st["repeat"] and fights >= 2
end

local function formCheck(n, label)
	local B = WG.BarDroidPresets
	local F = B and B.factoryForm and B.factoryForm(lab)
	local members, places, swaying, minGap = 0, {}, 0, math.huge
	for _, u in ipairs(out) do
		local s = F and F.slots[u]
		if s and Spring.ValidUnitID(u) then
			members = members + 1
			for _, o in ipairs(places) do
				minGap = math.min(minGap, math.sqrt((o[1] - s[1]) ^ 2 + (o[2] - s[2]) ^ 2))
			end
			places[#places + 1] = s
			swaying = swaying + (sway(u) and 1 or 0)
		end
	end
	check(label .. ": every Pawn out of the lab joined its formation, a place of its own", members == n and minGap >= 40,
		string.format("%d of %d with a place, nearest two %.0f apart", members, n, minGap == math.huge and 0 or minGap))
	check(label .. ": each one on its place goes side to side on repeat", swaying == n,
		string.format("%d of %d swaying", swaying, n))
	return F
end

function widget:GameFrame(f)
	if stage == "wait" and f >= 300 then
		-- (cheats first, the give a second later: given in the same frame it came to nothing)
		Spring.SendCommands("cheat 1")
		go("cheat", f)
	elseif stage == "cheat" and f - stageAt > 30 then
		Spring.SendCommands("nocost 1")
		local units = Spring.GetTeamUnits(Spring.GetMyTeamID())
		com = units[1]
		local x, y, z = Spring.GetUnitPosition(com)
		Spring.SendCommands(string.format("give 1 armlab %d @%d,%d,%d", Spring.GetMyTeamID(), x + 220, y, z))
		Spring.Echo("[factorytest] a Bot Lab given beside the commander")
		go("lab", f)
	elseif stage == "lab" and not lab and f - stageAt > 30 * 10 then
		check("a Bot Lab given", false, "none 10 s after the give")
		go("end", f)
	elseif stage == "lab" and lab and f - stageAt > 60 then
		Spring.SelectUnitArray({ lab })
		local B = WG.BarDroidPresets
		check("a Bot Lab picked: PRESETS for it", B and B.fits({ lab }) or false)
		if B then
			B.pick(1) -- STRAFE
		end
		local armed, name -- (not "B and B.armed()": Lua's and keeps one value, the name was lost)
		if B then
			armed, name = B.armed()
		end
		check("STRAFE picked for the lab: armed, its units' gathering place next", armed and name == "STRAFE",
			tostring(armed) .. " " .. tostring(name))
		local x, z, sx, sy, vsx = aimPoint()
		aimX, aimZ = x, z
		camAim = Spring.GetCameraState()
		write(sx and string.format("aim %d %d %d\n", sx, sy, vsx) or "aim nil nil nil\n")
		Spring.Echo("[factorytest] aim: " .. tostring(sx) .. "," .. tostring(sy) .. " of " .. tostring(vsx))
		go("aim", f)
	elseif stage == "aim" and f - stageAt > 30 * 20 then
		check("the map tapped: the lab's preset set", false, "no preset 20 s after the aim")
		go("end", f)
	elseif stage == "aim" then
		local B = WG.BarDroidPresets
		local F = B and B.factoryForm and B.factoryForm(lab)
		if F then
			local a = F.aim
			local d = a.x and math.sqrt((a.x - aimX) ^ 2 + (a.z - aimZ) ^ 2) or 999
			check("the map tapped: the lab's preset STRAFE there", F.id == 1 and d < 120, string.format("%.0f elmos off", d))
			-- (where it went, and the camera then against the aim's: a camera that moved between the aim and the tap)
			local cs, ca = Spring.GetCameraState(), camAim or {}
			local mx, my = Spring.GetMouseState()
			local _, pos = Spring.TraceScreenRay(mx, my, true)
			Spring.Echo(string.format("[factorytest] (the preset at %s,%s, the aim %d,%d; the pointer %d,%d on %s; camera at "
				.. "the aim %s,%s dist %s ry %s, now %s,%s dist %s ry %s)", tostring(a.x and math.floor(a.x)),
				tostring(a.z and math.floor(a.z)), aimX, aimZ, mx, my, pos and string.format("%d,%d", pos[1], pos[3]) or "nil",
				tostring(ca.px and math.floor(ca.px)), tostring(ca.pz and math.floor(ca.pz)),
				tostring(ca.dist and math.floor(ca.dist) or ca.height), tostring(ca.ry), tostring(cs.px and math.floor(cs.px)),
				tostring(cs.pz and math.floor(cs.pz)), tostring(cs.dist and math.floor(cs.dist) or cs.height), tostring(cs.ry)))
			for _ = 1, 5 do
				Spring.GiveOrderToUnit(lab, -pawnDef, {}, 0)
			end
			go("five", f)
		end
	elseif stage == "five" and (#out >= 5 and f - stageAt > 30 * 25 or f - stageAt > 30 * 60) then
		local F = formCheck(5, "five Pawns")
		firstPlaces = {}
		for _, u in ipairs(out) do
			local s = F and F.slots[u]
			firstPlaces[u] = s and { s[1], s[2] } or nil
		end
		for _ = 1, 3 do
			Spring.GiveOrderToUnit(lab, -pawnDef, {}, 0)
		end
		go("eight", f)
	elseif stage == "eight" and (#out >= 8 and f - stageAt > 30 * 25 or f - stageAt > 30 * 60) then
		local F = formCheck(8, "three more (eight)")
		-- (the formation grew: one row abreast, wider than five made it)
		local lo, hi = math.huge, -math.huge
		for _, u in ipairs(out) do
			local s = F and F.slots[u]
			if s and F.px then
				local across = (s[1] - (F.mx or 0)) * F.px + (s[2] - (F.mz or 0)) * F.pz
				lo, hi = math.min(lo, across), math.max(hi, across)
			end
		end
		check("the formation grew with them: eight abreast", hi - lo > 64 * 6, string.format("%.0f elmos wide", hi - lo))
		-- (and grew around the first five: their places where they were)
		local moved = 0
		for u, p in pairs(firstPlaces or {}) do
			local s = F and F.slots[u]
			if not s or math.abs(s[1] - p[1]) + math.abs(s[2] - p[2]) > 1 then
				moved = moved + 1
			end
		end
		check("the first five's places kept as three more joined", moved == 0, moved .. " moved")
		-- (the lab's own move order: its preset ends, its next units do as BAR does)
		local lx, ly, lz = Spring.GetUnitPosition(lab)
		Spring.GiveOrderToUnit(lab, CMD.MOVE, { lx + 100, ly, lz + 100 }, 0)
		go("rally", f)
	elseif stage == "rally" and f - stageAt > 30 then
		local B = WG.BarDroidPresets
		check("the lab given its own move order: its preset ends", not (B and B.factoryForm(lab)))
		-- (Kailil, 2026-11-20: a sent preset's units begin the strafing as each arrives, not once all are there: two Pawns
		-- given at the aim, two ~1100 elmos off, all four sent STRAFE there)
		local lx, _, lz = Spring.GetUnitPosition(lab)
		local fx, fz = aimX + (lx - aimX) * 2, aimZ + (lz - aimZ) * 2
		fx = math.max(100, math.min(Game.mapSizeX - 100, fx))
		fz = math.max(100, math.min(Game.mapSizeZ - 100, fz))
		local team = Spring.GetMyTeamID()
		Spring.SendCommands(string.format("give 2 armpw %d @%d,%d,%d", team, aimX + 60, Spring.GetGroundHeight(aimX, aimZ), aimZ))
		Spring.SendCommands(string.format("give 2 armpw %d @%d,%d,%d", team, fx, Spring.GetGroundHeight(fx, fz), fz))
		go("strafegive", f)
	elseif stage == "strafegive" and f - stageAt > 45 then
		local near, far = {}, {}
		for _, u in ipairs(given) do
			local x, _, z = Spring.GetUnitPosition(u)
			if x then
				local d = math.sqrt((x - aimX) ^ 2 + (z - aimZ) ^ 2)
				if d < 300 then
					near[#near + 1] = u
				elseif d > 600 then
					far[#far + 1] = u
				end
			end
		end
		strafe = { near = near, far = far, all = given }
		check("two Pawns at the aim, two far off", #near == 2 and #far == 2, #near .. " near, " .. #far .. " far")
		local B = WG.BarDroidPresets
		if B and B.toolsSend then
			B.toolsSend(1, given, { x = aimX, z = aimZ })
		end
		go("strafeearly", f)
	elseif stage == "strafeearly" and f - stageAt > 30 * 4.5 then
		local nearOn, farGoing = 0, 0
		for _, u in ipairs(strafe.near) do
			nearOn = nearOn + (sway(u) and 1 or 0)
		end
		for _, u in ipairs(strafe.far) do
			local x, _, z = Spring.GetUnitPosition(u)
			if x and not sway(u) and math.sqrt((x - aimX) ^ 2 + (z - aimZ) ^ 2) > 300 then
				farGoing = farGoing + 1
			end
		end
		check("STRAFE sent, the first two there: side to side at once, the far two still on their way", nearOn == 2 and farGoing == 2,
			nearOn .. " near swaying, " .. farGoing .. " far still going")
		go("strafeall", f)
	elseif stage == "strafeall" then
		local on = 0
		for _, u in ipairs(strafe.all) do
			on = on + (sway(u) and 1 or 0)
		end
		if on == #strafe.all or f - stageAt > 30 * 40 then
			check("the far two there too: all four side to side", on == #strafe.all and on == 4, on .. " of " .. #strafe.all)
			go("end", f)
		end
	elseif stage == "end" then
		Spring.Echo(fails == 0 and "[factorytest] done: ALL PASS" or ("[factorytest] done: " .. fails .. " FAILED"))
		go("over", f)
	end
end
