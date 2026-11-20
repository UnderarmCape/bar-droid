-- LuaUI widget for tools/firstdraw-phone-test.ps1: does the GPU driver's fault (Mesa's "submit failed -1 (Resource
-- deadlock avoided)", DriverWatch; docs/DELIVERY.md) come with units drawn for the first time? Most of the faults fell in
-- a game's first minute, three of 2026-11-20's five just after new unit types appeared. In a skirmish (cheats on): every
-- BATCH frames, the next PER unit types not yet given (every UnitDef with a model, by id; the commanders and the walls'
-- objectify buildings too) given to the neutral Gaia team (no fights) on a grid in front of the camera, so each is drawn
-- for the first time; "[firstdraw] n of N types given (last: name ...)" after each batch, "[firstdraw] done" after the
-- last. The script reads the launcher's log for the driver's refusal meanwhile.
function widget:GetInfo()
	return { name = "BAR Droid first draw test", desc = "New unit types drawn, one batch after another", author = "BAR Droid",
		layer = 0, enabled = true }
end

local PER, BATCH = 12, 90
local defs, nextAt, at, gaia = {}, nil, 1, nil
local spot -- where they go: the place on the map farthest from every start (given beside the commander, a geothermal
-- plant off its vent blew up and took the commander with it: the game ended, the same batch in two runs, 2026-11-20)

local function farSpot()
	local best, bestD
	for i = 1, 3 do
		for j = 1, 3 do
			local x, z = Game.mapSizeX * i / 4, Game.mapSizeZ * j / 4
			local d = math.huge
			for _, t in ipairs(Spring.GetTeamList() or {}) do
				local sx, _, sz = Spring.GetTeamStartPosition(t)
				if sx and (sx > 0 or sz > 0) then
					d = math.min(d, math.sqrt((sx - x) ^ 2 + (sz - z) ^ 2))
				end
			end
			if not bestD or d > bestD then
				best, bestD = { x, Spring.GetGroundHeight(x, z), z }, d
			end
		end
	end
	return best, bestD
end
local function center()
	Spring.SetCameraTarget(spot[1], spot[2], spot[3], 0) -- (the camera on them: each type drawn as it comes)
	return spot
end

function widget:Initialize()
	for id, ud in pairs(UnitDefs) do
		if ud.modelname and ud.modelname ~= "" and not ud.name:find("^dbg_") then
			defs[#defs + 1] = id
		end
	end
	table.sort(defs)
end

-- the "jump" mode (LuaUI/Config/bardroid_firstdraw_mode.txt "jump"): no units, the camera to another part of the map
-- every 2 s, round a 5 x 5 grid in a scattered order (ground never drawn before, its tiles uploaded at once: one fault
-- came a second after the units' mode jumped the camera 10 000 elmos, 2026-11-20)
local mode
local function readMode()
	local fh = io.open("LuaUI/Config/bardroid_firstdraw_mode.txt", "r")
	local s = fh and fh:read("*l") or "units"
	if fh then
		fh:close()
	end
	return s
end
local jumps = 0
local function jump(f)
	local k = (jumps * 7) % 25 -- (7 and 25 coprime: every cell once in 25 jumps, each far from the last)
	local x = Game.mapSizeX * (k % 5 + 0.5) / 5
	local z = Game.mapSizeZ * (math.floor(k / 5) + 0.5) / 5
	Spring.SetCameraTarget(x, Spring.GetGroundHeight(x, z), z, 0)
	jumps = jumps + 1
	if jumps % 10 == 0 then
		Spring.Echo(string.format("[firstdraw] %d camera jumps", jumps))
	end
	if jumps >= 90 then
		Spring.Echo("[firstdraw] done")
		return math.huge
	end
	return f + 60
end

function widget:GameFrame(f)
	if f == 300 then
		mode = readMode()
	end
	if mode == "jump" then
		if f == 300 or (nextAt and f >= nextAt) then
			nextAt = jump(f)
		end
		return
	end
	if f == 300 then
		Spring.SendCommands("cheat 1")
		gaia = Spring.GetGaiaTeamID()
		nextAt = f + 30
		local d
		spot, d = farSpot()
		Spring.Echo(string.format("[firstdraw] %d unit types to give, %d every %.1f s, at %d,%d (%d elmos from the nearest "
			.. "start)", #defs, PER, BATCH / 30, spot[1], spot[3], d))
	end
	if not nextAt or f < nextAt then
		return
	end
	nextAt = f + BATCH
	local pos = center()
	if not pos then
		return
	end
	local names = {}
	for k = 0, PER - 1 do
		local id = defs[at]
		if not id then
			break
		end
		local x = pos[1] + (k % 4 - 1.5) * 90
		local z = pos[3] + (math.floor(k / 4) - 1) * 90
		Spring.SendCommands(string.format("give 1 %s %d @%d,%d,%d", UnitDefs[id].name, gaia, x, Spring.GetGroundHeight(x, z), z))
		names[#names + 1] = UnitDefs[id].name
		at = at + 1
	end
	Spring.Echo(string.format("[firstdraw] %d of %d types given (this batch: %s)", at - 1, #defs, table.concat(names, " ")))
	if at > #defs then
		Spring.Echo("[firstdraw] done")
		nextAt = math.huge
	end
end
