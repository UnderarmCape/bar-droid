-- BAR Droid auto mex: the commander picked and a metal extractor chosen, the free mex spots within the commander's
-- weapon range are queued at once, nearest first, with no tap on the map (Kailil, 2026-11-10: "the first mexes at the
-- start ... sent at once without confirmation"; "it may also just fire every time; where no spot is that close it does
-- nothing and the player places it"). It goes through BAR's own resource spot API, as BAR's Area Mex does
-- (WG.resource_spot_finder's spots, WG.resource_spot_builder's orders: spots built or queued are left out), appended to
-- the builders' queues (a start's queued buildings stay first). With orders sent the extractor is put away; with none
-- it stays for the player to place. Touch play's automation is Kailil's and BAR's developers' call (GiveOrder).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid auto mex",
		desc = "Commander picked and a metal extractor chosen: the mex spots in its weapon range queued at once",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local spGetActiveCommand = Spring.GetActiveCommand
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition

local lastCmd -- the active command last seen: it fires as the extractor is chosen, not again while it stays chosen
local commanderDef = {}
for id, ud in pairs(UnitDefs) do
	if ud.customParams and ud.customParams.iscommander then
		commanderDef[id] = math.max(ud.maxWeaponRange or 0, 1)
	end
end

local function queueSpots(mexDefID)
	local finder, builder = WG.resource_spot_finder, WG.resource_spot_builder
	if not (finder and builder and finder.metalSpotsList) or finder.isMetalMap then
		return 0
	end
	local constructors = builder.GetMexConstructors and builder.GetMexConstructors() or {}
	local com, range
	for _, u in ipairs(spGetSelectedUnits() or {}) do
		local r = commanderDef[spGetUnitDefID(u) or -1]
		if r and constructors[u] then
			com, range = u, r
			break
		end
	end
	if not com then
		return 0
	end
	local cx, _, cz = spGetUnitPosition(com)
	if not cx then
		return 0
	end
	local cmds, spots = {}, {}
	for _, spot in ipairs(finder.metalSpotsList) do
		local dx, dz = spot.x - cx, spot.z - cz
		local queued = builder.SpotHasExtractorQueued and builder.SpotHasExtractorQueued(spot)
		if dx * dx + dz * dz <= range * range and not queued then
			local cmd = builder.PreviewExtractorCommand({ spot.x, spot.y, spot.z }, mexDefID, spot) -- (the def's own id:
			-- the finder's GetBuildingPositions looks its footprint up by it)
			if cmd then
				cmds[#cmds + 1], spots[#spots + 1] = cmd, spot
			end
		end
	end
	-- nearest first, then on from each (BAR's Area Mex weighs by a spot's worth too)
	local ordered, x, z = {}, cx, cz
	while #cmds > 0 do
		local best, bestD = 1, math.huge
		for i, c in ipairs(cmds) do
			local d = ((c[2] - x) ^ 2 + (c[4] - z) ^ 2) / math.max(0.1, spots[i].worth or 1)
			if d < bestD then
				best, bestD = i, d
			end
		end
		local c = table.remove(cmds, best)
		table.remove(spots, best)
		ordered[#ordered + 1] = c
		x, z = c[2], c[4]
	end
	if #ordered > 0 then
		builder.ApplyPreviewCmds(ordered, constructors, true)
	end
	return #ordered, range
end

function widget:Update()
	local _, cmd = spGetActiveCommand()
	if cmd == lastCmd then
		return
	end
	lastCmd = cmd
	if not cmd or cmd >= 0 or Spring.GetGameFrame() < 1 or Spring.GetSpectatingState() then
		return
	end
	local builder = WG.resource_spot_builder
	local mexes = builder and builder.GetMexBuildings and builder.GetMexBuildings()
	if not (mexes and mexes[-cmd]) then
		return
	end
	local n, range = queueSpots(-cmd)
	if n > 0 then
		Spring.SetActiveCommand(0) -- (done: no extractor left on the pointer to place by mistake)
		lastCmd = nil
		local P = WG.BarDroidPad
		if P and P.say then
			P.say(string.format("%d %s QUEUED", n, n == 1 and "MEX" or "MEXES"))
		end
	end
	Spring.Echo(string.format("[bardroid-automex] %s: %d spots in %d elmos queued", UnitDefs[-cmd].name, n, range or 0)) -- (tools)
end
