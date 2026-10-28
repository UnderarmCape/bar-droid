-- LuaUI widget for tools/spectate-test.ps1: bardroid_spectate.lua in a real replay (a spectator, as the phone is when it
-- watches a game). Fast-forwards into the game, then checks the touch tools: nothing stays selected, following units
-- (the next most valuable one, a double tap on a unit, a double tap on the ground, the group), BAR's player camera on
-- the next player and back, a finger pan ending the following, and a mouse giving BAR's spectating back.
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

-- how far the camera looks from a unit (elmos)
local function offFrom(unitID)
	local x, _, z = Spring.GetUnitPosition(unitID)
	local cs = Spring.GetCameraState()
	if not (x and cs.px) then
		return math.huge
	end
	return math.sqrt((cs.px - x) ^ 2 + (cs.pz - z) ^ 2)
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
		S().actions.unit_next()
		unitA = S().following()
		return 2.5
	end,
	function()
		check("< unit >: follows the most valuable unit", unitA ~= nil and offFrom(unitA) < 300,
			unitA and string.format("unit %d, camera %.0f elmos off", unitA, offFrom(unitA)))
		S().actions.unit_next()
		unitB = S().following()
		check("< unit > again: the next one", unitB ~= nil and unitB ~= unitA, tostring(unitB))
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
		-- the camera still looks at unit B (it glided there): a double tap on it follows it again
		local x, y, z = Spring.GetUnitPosition(unitB)
		local sx, sy = Spring.WorldToScreenCoords(x, y, z)
		local taken = S().tap(sx, sy)
		S().tap(sx, sy)
		check("a tap on the map is taken (it selects nothing)", taken == true)
		check("double tap on a unit: follows it", S().following() == unitB,
			string.format("tapped %.0f,%.0f: following %s", sx, sy, tostring(S().following())))
		S().actions.group()
		return 1.5
	end,
	function()
		check("Group: its team's units around it", S().members() >= 1, S().members() .. " units")
		check("still nothing selected (no unit panels)", Spring.GetSelectedUnitsCount() == 0,
			Spring.GetSelectedUnitsCount() .. " selected")
		WG.BarDroidPlayers.keepOpen() -- (as a tap on the bar does)
		Spring.SendCommands("screenshot png") -- the bar, following a group (build\spectate-test\data\screenshots)
		S().actions.group()
		S().actions.player_next()
		return 1
	end,
	function()
		local p1 = WG.lockcamera and WG.lockcamera.GetPlayerID()
		check("< player >: BAR's player camera on a player", p1 ~= nil, tostring(p1))
		local name = p1 and Spring.GetPlayerInfo(p1, false)
		check("the button says the player's name", name ~= nil and S().label() == name, S().label())
		check("the player camera ends the following", S().following() == nil)
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
		S().actions.unit_next()
		return 0.5
	end,
	function()
		WG.BarDroidPanAt = os.clock() + 1000 -- as bardroid_touch.lua marks a finger pan
		return 0.5
	end,
	function()
		check("a finger pan ends the following", S().following() == nil, tostring(S().following()))
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
