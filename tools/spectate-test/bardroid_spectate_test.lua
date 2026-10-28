-- LuaUI widget for tools/spectate-test.ps1: bardroid_spectate.lua in a real replay (a spectator, as the phone is when it
-- watches a game). Fast-forwards into the game, then checks the touch tools: the bar with the player list, nothing
-- staying selected, following units (the arrows by distance from the screen's centre, a double tap on a unit or the
-- ground, the group), an offset pan, pinch and the next unit keeping the follow, a flick far away letting go, the camera
-- presets and Save, BAR's player camera on the next player and back, a mouse giving BAR's spectating back.
-- Logs "[spectest] PASS|FAIL <case>" and "[spectest] done".
function widget:GetInfo()
	return { name = "BAR Droid spectate test", desc = "Checks bardroid_spectate.lua", author = "BAR Droid", layer = 0,
		enabled = true }
end

local SKIP = 420 -- game seconds: armies on the map
local step, waitUntil, fails = 0, 0, 0
local skipSent = false
local t0 = Spring.GetTimer()
local unitA, unitB, players

local function now()
	return Spring.DiffTimers(Spring.GetTimer(), t0)
end

local function log(s)
	Spring.Echo("[spectest] " .. s)
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	log((ok and "PASS " or "FAIL ") .. case .. (detail and (": " .. tostring(detail)) or ""))
end

local function S()
	return WG.BarDroidSpectate
end

-- the camera's look point from a unit (elmos), as dx, dz and the distance
local function fromUnit(unitID)
	local x, _, z = Spring.GetUnitPosition(unitID)
	local cs = Spring.GetCameraState()
	if not (x and cs.px) then
		return math.huge, math.huge, math.huge
	end
	local dx, dz = cs.px - x, cs.pz - z
	return dx, dz, math.sqrt(dx * dx + dz * dz)
end

-- a camera move as the fingers make one (bardroid_touch.lua sets the camera state the same way)
local function moveCamera(dx, dz, distFactor)
	local cs = Spring.GetCameraState()
	cs.px, cs.pz = cs.px + dx, cs.pz + dz
	if distFactor and cs.dist then
		cs.dist = cs.dist * distFactor
	end
	Spring.SetCameraState(cs, 0)
end

-- the mobile unit closest to where the camera looks
local function closestUnit()
	local cs = Spring.GetCameraState()
	local best, bestD
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		local x, _, z = Spring.GetUnitPosition(unitID)
		if x and def and (def.speed or 0) > 0 and not Spring.GetUnitIsBeingBuilt(unitID) then
			local d = (x - cs.px) ^ 2 + (z - cs.pz) ^ 2
			if not bestD or d < bestD then
				best, bestD = unitID, d
			end
		end
	end
	return best
end

-- an X screen point (bottom-up, as the engine's mouse callins) over the ground, away from units
local function groundPoint()
	local vsx, vsy = Spring.GetViewGeometry()
	for fy = 0.9, 0.3, -0.1 do
		for fx = 0.1, 0.9, 0.1 do
			local x, y = math.floor(vsx * fx), math.floor(vsy * fy)
			if Spring.TraceScreenRay(x, y) == "ground" then
				return x, y
			end
		end
	end
end

local expected
local cases = {
	function()
		WG.BarDroidInput = "touch" -- as the app reports after a finger
		check("the replay is watched as a spectator", Spring.GetSpectatingState() == true)
	end,
	function()
		check("the touch tools are on (spectating, fingers last)", WG.BarDroidSpectating == true and S() ~= nil)
		check("the bar waits for the player list (small)", S().shown() == false and WG.BarDroidPlayers
			and WG.BarDroidPlayers.minimized())
		local pos = WG.advplayerlist_api and WG.advplayerlist_api.GetPosition()
		if pos and pos[1] then -- { top, left, bottom, right }
			WG.BarDroidPlayers.press((pos[2] + pos[4]) / 2, (pos[1] + pos[3]) / 2)
		end
		return 0.5
	end,
	function()
		check("a tap on the player list opens it and the bar", S().shown() == true and not WG.BarDroidPlayers.minimized())
		-- a builder, as a tap or BAR's select-all could pick: BAR's build menu would show its options
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			if def and def.isBuilder and (def.speed or 0) > 0 then
				Spring.SelectUnitArray({ unitID })
				break
			end
		end
	end,
	function()
		check("nothing stays selected (no unit panels)", Spring.GetSelectedUnitsCount() == 0, Spring.GetSelectedUnitsCount())
		local shows = WG.buildmenu and WG.buildmenu.getIsShowing and WG.buildmenu.getIsShowing()
		check("BAR's build menu is not showing", not shows, tostring(shows))
		expected = closestUnit()
		S().actions.unit_next()
		unitA = S().following()
		return 2.5
	end,
	function()
		local _, _, off = fromUnit(unitA)
		check("> : follows the unit closest to the screen's centre", unitA ~= nil and unitA == expected and off < 150,
			string.format("unit %s (closest %s), camera %.0f elmos off", tostring(unitA), tostring(expected), off))
		moveCamera(300, 0) -- a finger pan, a little
		return 1.5
	end,
	function()
		local dx, dz = fromUnit(unitA)
		check("a pan offsets the camera and the follow goes on", S().following() == unitA and math.abs(dx - 300) < 80
			and math.abs(dz) < 80, string.format("following %s, camera %+.0f %+.0f from the unit", tostring(S().following()), dx, dz))
		local cs = Spring.GetCameraState()
		expected = cs.dist and cs.dist * 0.6
		moveCamera(0, 0, 0.6) -- a pinch
		return 1
	end,
	function()
		local cs = Spring.GetCameraState()
		check("a pinch zooms and the follow goes on", S().following() == unitA and cs.dist
			and math.abs(cs.dist - expected) < expected * 0.1, string.format("dist %.0f, wanted %.0f", cs.dist or -1, expected))
		S().actions.unit_next()
		unitB = S().following()
		return 2.5
	end,
	function()
		local dx, dz = fromUnit(unitB)
		check("> again: the next unit outwards, the offset kept", unitB ~= nil and unitB ~= unitA and math.abs(dx - 300) < 100
			and math.abs(dz) < 100, string.format("unit %s, camera %+.0f %+.0f from it", tostring(unitB), dx, dz))
		local gx, gy = groundPoint()
		if gx then
			S().tap(gx, gy)
			S().tap(gx, gy)
		end
		check("double tap on the ground: following stops", gx ~= nil and S().following() == nil,
			gx and string.format("at %d,%d: %s", gx, gy, tostring(S().following())) or "no ground on screen")
		return 1
	end,
	function()
		-- unit B is still near the screen's centre (the camera looked at it): a double tap on it follows it again
		local x, y, z = Spring.GetUnitPosition(unitB)
		local sx, sy = Spring.WorldToScreenCoords(x, y, z)
		local taken = S().tap(sx, sy)
		S().tap(sx, sy)
		check("a tap on the map is taken (it selects nothing)", taken == true)
		check("double tap on a unit: follows it, centred", S().following() == unitB and select(1, S().offset()) == 0,
			string.format("tapped %.0f,%.0f: following %s", sx, sy, tostring(S().following())))
		S().actions.preset_first()
		return 2
	end,
	function()
		local cs = Spring.GetCameraState()
		local cx, cy, cz = Spring.GetCameraPosition()
		local ux, uy, uz = Spring.GetUnitPosition(unitB)
		local cdx, _, cdz = Spring.GetCameraDirection()
		local udx, _, udz = Spring.GetUnitDirection(unitB)
		local ln = math.sqrt(cdx * cdx + cdz * cdz) * math.sqrt(udx * udx + udz * udz)
		local dot = ln > 0 and (cdx * udx + cdz * udz) / ln or -1
		local off = math.sqrt((cx - ux) ^ 2 + (cz - uz) ^ 2)
		-- (facing loosely: the turn is smoothed, and a unit may be turning right then)
		check("1st person: the engine's first-person camera on the unit, looking its way", cs.mode == 0 and off < 120
			and dot > 0.5, string.format("mode %s, eye %.0f elmos from the unit, %.0f above its base, anchor %s, facing %.2f",
			tostring(cs.mode), off, cy - uy, tostring(S().anchor()), dot))
		S().actions.preset_table()
		return 1.5
	end,
	function()
		local cs = Spring.GetCameraState()
		check("Table: the preset's distance", cs.dist and math.abs(cs.dist - 1100) < 110, string.format("dist %.0f", cs.dist or -1))
		S().actions.save()
		moveCamera(0, 0, 777 / cs.dist) -- the camera as the player wants it
		return 0.5
	end,
	function()
		S().actions.preset_close() -- (Save armed: saves)
		local p = S().preset("close")
		check("Save, then Close: Close is the camera as it is now", p and math.abs(p.dist - 777) < 40,
			p and string.format("dist %.0f", p.dist))
		S().actions.group()
		S().actions.preset_mid()
		return 1.5
	end,
	function()
		check("Group: its team's units around it", S().members() >= 1, S().members() .. " units")
		check("still nothing selected (no unit panels)", Spring.GetSelectedUnitsCount() == 0,
			Spring.GetSelectedUnitsCount() .. " selected")
		if WG.BarDroidPlayers.minimized() then -- (7 s since it opened: open it again, as a tap does)
			local pos = WG.advplayerlist_api.GetPosition()
			WG.BarDroidPlayers.press((pos[2] + pos[4]) / 2, (pos[1] + pos[3]) / 2)
		end
		return 0.5
	end,
	function()
		Spring.SendCommands("screenshot png") -- the presets in the bar (build\spectate-test\data\screenshots)
		S().actions.group()
		S().actions.preset_close()
		return 1.5
	end,
	function()
		local cs = Spring.GetCameraState()
		check("the saved Close comes back", cs.dist and math.abs(cs.dist - 777) < 80, string.format("dist %.0f", cs.dist or -1))
		moveCamera(6000, 0) -- a flick, far away
		return 1
	end,
	function()
		check("a flick far away lets go", S().following() == nil, tostring(S().following()))
		S().actions.player_next()
		return 1
	end,
	function()
		local p1 = WG.lockcamera and WG.lockcamera.GetPlayerID()
		check("< player >: BAR's player camera on a player", p1 ~= nil, tostring(p1))
		local name = p1 and Spring.GetPlayerInfo(p1, false)
		check("the button says the player's name", name ~= nil and S().label() == name, S().label())
		players = p1
		S().actions.player_next()
		return 1
	end,
	function()
		local p2 = WG.lockcamera and WG.lockcamera.GetPlayerID()
		check("< player > again: the next player", p2 ~= nil and p2 ~= players, tostring(p2))
		S().actions.free()
		return 1
	end,
	function()
		check("Free: the own camera again", WG.lockcamera.GetPlayerID() == nil and S().following() == nil)
		WG.BarDroidInput = "mouse"
		return 0.5
	end,
	function()
		check("a mouse: the touch tools step aside", WG.BarDroidSpectating == false)
		Spring.SelectUnitArray({ unitB })
		return 0.5
	end,
	function()
		check("a mouse: units can be selected again", Spring.GetSelectedUnitsCount() == 1, Spring.GetSelectedUnitsCount())
		WG.BarDroidInput = "touch"
		return 8
	end,
	function()
		check("7 s untouched: the list small again and the bar gone", WG.BarDroidPlayers.minimized() and not S().shown())
		log("done: " .. (fails == 0 and "ALL PASS" or fails .. " FAILED"))
	end,
}

function widget:Update()
	local frame = Spring.GetGameFrame()
	if frame <= 0 then
		return
	end
	if not skipSent then
		skipSent = true
		Spring.SendCommands("skip " .. SKIP)
		return
	end
	if frame < SKIP * 30 or now() < waitUntil then
		return
	end
	step = step + 1
	local c = cases[step]
	if not c then
		return
	end
	local ok, res = pcall(c)
	if not ok then
		check("case " .. step .. " ran", false, res)
	end
	waitUntil = now() + (ok and type(res) == "number" and res or 0.5)
end
