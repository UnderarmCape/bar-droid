-- LuaUI widget for tools/dock-phone-test.ps1: the upright touch dock (bardroid_portrait.lua) driven by real taps on the
-- dev phone (adb input), which this widget sets up for and checks. The script writes a stage into
-- LuaUI/Config/bardroid_docktest_cmd.txt; the widget answers in the log ("[docktest] PASS|FAIL <case>") and writes
-- what the script needs to tap into LuaUI/Config/bardroid_docktest.txt (X screen pixels, top left origin):
--   (frame 300) the commander picked; "free x y" and "blocked x y": a spot where a Bot Lab can go and one it cannot
--   placed?   the Bot Lab queued by the dock's PLACE (picked, its spot tapped, PLACE 2.6 s later)
--   blocked?  PLACE on the blocked spot: the note "CAN'T BUILD THERE: PICK ANOTHER SPOT"
--   dgun      the D-gun mode on the commander;  auto? / autooff?  full auto on / off by FIRE's swipes
--   walk      the commander's speed watched;    stopped?  it walked, and stands still soon after the stick is let go
--   presets   six Pawns given, picked, the presets open; "aim0 x y", "aim1 x y": a drag's ends on open ground
--   strafe?   STRAFE (its thumbnail tapped, the destination dragged): each Pawn two fights, repeat on
--   end       "[docktest] done: ALL PASS" or "N FAILED"
function widget:GetInfo()
	return { name = "BAR Droid dock test", desc = "What the touch dock did", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_docktest.txt", "LuaUI/Config/bardroid_docktest_cmd.txt"
local com, ready, fails, lastCmd = nil, false, 0, nil
local pawns, maxSpeed = {}, nil

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[docktest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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

-- a ground point as X screen pixels from the top left; nil off the screen, under the dock or by its edges
local function screenOf(x, z)
	local sx, sy, sz = Spring.WorldToScreenCoords(x, Spring.GetGroundHeight(x, z), z)
	local vsx, vsy = Spring.GetViewGeometry()
	local D = WG.BarDroidPortrait
	local dock = D and D.dock and D.dock()
	local top = dock and dock[4] or 0
	if sz > 1 or sx < 60 or sx > vsx - 60 or sy < top + 80 or sy > vsy - 160 then
		return nil
	end
	return math.floor(sx), math.floor(vsy - sy)
end
-- a Bot Lab spot near the commander on the screen: buildable (TestBuildOrder 2 or 3: rocks the builder reclaims, or
-- open ground; the test map is strewn with rocks) or blocked (0)
local function labSpot(want)
	local def = UnitDefNames.armlab.id
	local cx, _, cz = Spring.GetUnitPosition(com)
	for r = 200, 1200, 50 do
		for a = 0, 345, 15 do
			local x, z = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
			local bx, by, bz = Spring.Pos2BuildPos(def, x, Spring.GetGroundHeight(x, z), z, 0)
			local sx, sy = screenOf(bx, bz)
			if sx then
				local t = Spring.TestBuildOrder(def, bx, by, bz, 0)
				if (want == "free" and t >= 2) or (want == "blocked" and t == 0) then
					return sx, sy
				end
			end
		end
	end
end
local function speedOf(u)
	local vx, _, vz = Spring.GetUnitVelocity(u)
	return vx and math.sqrt(vx * vx + vz * vz) * Game.gameSpeed or 0
end

local function onCmd(c)
	local P, D = WG.BarDroidPad, WG.BarDroidPadDgun
	if c == "placed?" then
		local found, words = false, {}
		for _, cmd in ipairs(Spring.GetUnitCommands(com, 20) or {}) do
			found = found or cmd.id == -UnitDefNames.armlab.id
			words[#words + 1] = cmd.id < 0 and UnitDefs[-cmd.id] and UnitDefs[-cmd.id].name or tostring(cmd.id)
		end
		local _, _, _, active = Spring.GetActiveCommand()
		check("the Bot Lab picked on the dock, its spot tapped, PLACE 2.6 s later: queued at once", found,
			"queue [" .. table.concat(words, " ") .. "], picked " .. tostring(active))
	elseif c == "blocked?" then
		local _, note = P.note()
		check("PLACE on a blocked spot says so", note == "CAN'T BUILD THERE: PICK ANOTHER SPOT", note)
	elseif c == "dgun" then -- (the building put away by the dock's cancel first: the script taps it)
		Spring.SelectUnitArray({ com })
		P.act("dgun")
		Spring.Echo("[docktest] dgun on: " .. tostring(D.active()))
	elseif c == "auto?" then
		check("FIRE swiped right: full auto on", D.auto() == true)
	elseif c == "autooff?" then
		check("AUTO swiped left: full auto off", D.auto() == false)
	elseif c == "walk" then
		maxSpeed = 0
	elseif c == "stopped?" then
		local now = speedOf(com)
		check("MOVE held: the commander walks; let go: it stands still at once", (maxSpeed or 0) > 15 and now < 4,
			string.format("top %.0f, now %.0f", maxSpeed or 0, now))
		maxSpeed = nil
	elseif c == "presets" then
		P.act("dgun_cancel")
		local x, y, z = Spring.GetUnitPosition(com)
		Spring.SendCommands(string.format("give 6 armpw %d @%d,%d,%d", Spring.GetMyTeamID(), x, y, z + 120))
	elseif c == "strafe?" then
		local ok, words = #pawns > 0, {}
		for _, u in ipairs(pawns) do
			local q = Spring.GetUnitCommands(u, 5) or {}
			local st = Spring.GetUnitStates(u) or {}
			local fights = 0
			for _, cmd in ipairs(q) do
				fights = fights + (cmd.id == CMD.FIGHT and 1 or 0)
			end
			ok = ok and fights == 2 and st["repeat"] == true
			words[#words + 1] = fights .. (st["repeat"] and "R" or "")
		end
		check("STRAFE tapped, its destination dragged and lifted: each Pawn two fights, repeat on", ok,
			table.concat(words, " "))
	elseif c == "end" then
		Spring.Echo("[docktest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
	end
end

function widget:GameFrame(f)
	if f == 60 then
		Spring.SendCommands("cheat 1")
	end
	if not com then
		for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
			local def = UnitDefs[Spring.GetUnitDefID(u)]
			if def and def.customParams and def.customParams.iscommander then
				com = u
			end
		end
	end
	if maxSpeed and com then
		maxSpeed = math.max(maxSpeed, speedOf(com))
	end
	if com and not ready and f >= 300 then
		ready = true
		Spring.SelectUnitArray({ com })
		local fx, fy = labSpot("free")
		local bx, by = labSpot("blocked")
		write(string.format("free %s %s\nblocked %s %s\n", tostring(fx), tostring(fy), tostring(bx), tostring(by)))
		Spring.Echo(string.format("[docktest] ready: free %s,%s blocked %s,%s", tostring(fx), tostring(fy), tostring(bx),
			tostring(by)))
	end
	if #pawns == 0 and lastCmd == "presets" then -- (the given Pawns, picked once they are there; the presets opened)
		local list = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), UnitDefNames.armpw.id) or {}
		if #list >= 6 then
			pawns = list
			Spring.SelectUnitArray(pawns)
			WG.BarDroidPresets.open()
			local cx, _, cz = Spring.GetUnitPosition(com)
			local ax, ay, bx2, by2
			for r = 300, 1200, 60 do -- (two points on open ground on the screen, the second farther on)
				for a = 0, 345, 15 do
					local x, z = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
					local sx, sy = screenOf(x, z)
					if sx and not ax then
						ax, ay = sx, sy
					elseif sx and ax and math.abs(sx - ax) + math.abs(sy - ay) > 200 and not bx2 then
						bx2, by2 = sx, sy
					end
				end
			end
			write(string.format("aim0 %s %s\naim1 %s %s\n", tostring(ax), tostring(ay), tostring(bx2), tostring(by2)))
			Spring.Echo(string.format("[docktest] presets open: %d Pawns, aim %s,%s to %s,%s", #pawns, tostring(ax),
				tostring(ay), tostring(bx2), tostring(by2)))
		end
	end
	if f % 6 == 0 then
		local c = readCmd()
		if c and c ~= lastCmd then
			lastCmd = c
			onCmd(c)
		end
	end
end
