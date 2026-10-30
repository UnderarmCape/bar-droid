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

-- Shoulder's framing of a unit: its middle on the screen (x, y), the camera behind it (> 0) and whether that is the
-- middle of the screen with the camera behind
local function shoulderFrame(u)
	local _, _, _, mx, my, mz = Spring.GetUnitPosition(u, true)
	local sx, sy = Spring.WorldToScreenCoords(mx, my, mz)
	local vsx, vsy = Spring.GetViewGeometry()
	local cxw, _, czw = Spring.GetCameraPosition()
	local ux, _, uz = Spring.GetUnitPosition(u)
	local heading = Spring.GetUnitHeading(u) * math.pi / 32768 -- (0: facing +z)
	local behind = -((cxw - ux) * math.sin(heading) + (czw - uz) * math.cos(heading))
	local ok = math.abs(sx - vsx / 2) < vsx * 0.1 and math.abs(sy - vsy / 2) < vsy * 0.12 and behind > 0
	return ok, string.format("unit at %.0f,%.0f of %dx%d, camera %.0f behind", sx, sy, vsx, vsy, behind)
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

-- the mobile unit of the spectated team closest to where the camera looks (wildlife aside)
local function closestUnit()
	local cs = Spring.GetCameraState()
	local best, bestD
	for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		local x, _, z = Spring.GetUnitPosition(unitID)
		if x and def and (def.speed or 0) > 0 and not def.name:find("critter", 1, true)
			and not Spring.GetUnitIsBeingBuilt(unitID) then
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
local before -- (a view's Up: the camera before)
local other -- (Shoulder on the next unit)
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
		check("a tap on the player list brings up the bar, the list stays small", S().shown() == true
			and WG.BarDroidPlayers.minimized())
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
		check("> : follows the spectated team's unit closest to the screen's centre", unitA ~= nil and unitA == expected
			and off < 150 and Spring.GetUnitTeam(unitA) == Spring.GetMyTeamID(),
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
		check("> again: the next unit outwards (same team), the offset kept", unitB ~= nil and unitB ~= unitA
			and Spring.GetUnitTeam(unitB) == Spring.GetUnitTeam(unitA) and math.abs(dx - 300) < 100
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
		-- (a finger a little off, the two taps not on the same spot: forgiving)
		local taken = S().tap(sx + 18, sy + 12)
		S().tap(sx - 20, sy + 30)
		check("a tap on the map is taken (it selects nothing)", taken == true)
		check("double tap on a unit: follows it, centred", S().following() == unitB and select(1, S().offset()) == 0,
			string.format("tapped %.0f,%.0f: following %s", sx, sy, tostring(S().following())))
		S().actions.preset_first()
		return 2
	end,
	function()
		check("double tap on a unit: the bar comes up (the next frame)", S().shown() == true)
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
		expected = cs.ry
		-- free look: a drag (as the fingers or the mouse give it), then nothing for longer than the recenter delay
		WG.BarDroidLook.dx = 400
		S().fp.recenterDelay = 1.5
		return 0.5
	end,
	function()
		local cs = Spring.GetCameraState()
		local turned = math.abs((cs.ry - expected + math.pi) % (2 * math.pi) - math.pi)
		check("1st person: a drag looks around", turned > 0.3, string.format("turned %.2f rad", turned))
		return 4
	end,
	function()
		local cdx, _, cdz = Spring.GetCameraDirection()
		local udx, _, udz = Spring.GetUnitDirection(unitB)
		local ln = math.sqrt(cdx * cdx + cdz * cdz) * math.sqrt(udx * udx + udz * udz)
		local dot = ln > 0 and (cdx * udx + cdz * udz) / ln or -1
		check("1st person: back with the unit after the recenter delay", dot > 0.5, string.format("facing %.2f", dot))
		S().fp.recenterDelay = 4
		-- a sentry: an armed building of the team
		expected = nil
		for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			if def and (def.speed or 0) == 0 and def.weapons and #def.weapons > 0 and not Spring.GetUnitIsBeingBuilt(unitID) then
				expected = unitID
				break
			end
		end
		if expected then
			S().firstPerson(expected)
		end
		return 1.5
	end,
	function()
		local cs = Spring.GetCameraState()
		local def = expected and UnitDefs[Spring.GetUnitDefID(expected)]
		check("1st person on a sentry, riding its gun", expected == nil or (S().following() == expected and cs.mode == 0),
			expected and string.format("%s: anchor %s", def and def.name or "?", tostring(S().anchor())) or "no sentry here")
		if expected then
			S().firstPerson(unitB)
		end
		S().actions.preset_table()
		return 1.5
	end,
	function()
		local cs = Spring.GetCameraState()
		check("Table: far overhead (eye in the sky)", cs.dist and cs.dist > 3000 and cs.rx > 2.8,
			string.format("dist %.0f, rx %.2f", cs.dist or -1, cs.rx or -1))
		S().actions.preset_shoulder()
		return 2
	end,
	-- a view's Up (Kailil: "the UP tune setting doesnt work in the shoulder cam"): the Spring camera keeps its focus on
	-- the ground, so Up lifts the camera over the same focus, looking down more steeply
	function()
		-- Shoulder's default (Kailil: "every unit is centered and zoomed in on the back of the unit")
		check("Shoulder: the unit in the middle of the screen, the camera behind it", shoulderFrame(S().following()))
		local x, y, z = Spring.GetCameraPosition()
		before = { h = y - Spring.GetGroundHeight(x, z), rx = Spring.GetCameraState().rx }
		local p = {}
		for k, v in pairs(S().preset("shoulder")) do
			p[k] = v
		end
		before.oy = p.oy or 0
		p.oy = before.oy + 300
		S().setPreset("shoulder", p)
		return 2
	end,
	function()
		local x, y, z = Spring.GetCameraPosition()
		local h, rx = y - Spring.GetGroundHeight(x, z), Spring.GetCameraState().rx
		check("Shoulder: Up +300 lifts the camera ~300, looking down at the unit more steeply",
			math.abs(h - before.h - 300) < 100 and rx > before.rx + 0.1,
			string.format("height %.0f -> %.0f, rx %.2f -> %.2f", before.h, h, before.rx, rx))
		local p = {}
		for k, v in pairs(S().preset("shoulder")) do
			p[k] = v
		end
		p.oy = before.oy
		S().setPreset("shoulder", p)
		-- Tune on Close: its first setting (Distance) four steps up, for every unit (Close is universal), then Save
		S().actions.preset_close()
		expected = S().preset("close").dist + 100
		S().actions.tune()
		for _ = 1, 4 do
			S().actions.tune_plus()
		end
		S().actions.tune_save()
		S().actions.tune() -- (Done)
		return 0.5
	end,
	function()
		local p, k = S().preset("close"), S().keptViews().close
		local def = UnitDefs[Spring.GetUnitDefID(S().following())]
		local own = S().presetTypes()[def.name]
		check("Tune: Close's distance set and saved for every unit, not the unit type",
			p and k and math.abs(p.dist - expected) < 1 and math.abs(k.dist - expected) < 1 and not (own and own.close),
			p and string.format("dist %.0f, saved %s, wanted %.0f", p.dist, k and string.format("%.0f", k.dist) or "-", expected))
		local read, file = pcall(VFS.Include, "LuaUI/Config/bardroid_kept.lua", nil, VFS.RAW)
		local close = read and type(file) == "table" and file.views and file.views.close
		check("Tune: Save is in its file at once, not only when the game quits", close and math.abs(close.dist - expected) < 1,
			tostring(close and close.dist))
		local eq = {}
		for _, n in ipairs(S().equivalentsOf("armham")) do
			eq[n] = true
		end
		local fig, llt = {}, {}
		for _, n in ipairs(S().equivalentsOf("armfig")) do
			fig[n] = true
		end
		for _, n in ipairs(S().equivalentsOf("armllt")) do
			llt[n] = true
		end
		check("equivalents: Mace and Thug, Fighter and Fighter, Sentry and Guard", eq.corthud and fig.corveng and llt.corllt,
			string.format("armham: %s", table.concat(S().equivalentsOf("armham"), " ")))
		-- (the unit type's own Shoulder, from the Up case above: Save gives it to the equivalents)
		local others = S().equivalentsOf(def.name)
		local mine = own and own.shoulder
		local given = others[1] and S().presetTypes()[others[1]] and S().presetTypes()[others[1]].shoulder
		check("Save gives the unit type's own views to its equivalents",
			#others == 0 or (mine and given and math.abs(given.dist - mine.dist) < 1),
			string.format("%s -> %s", def.name, table.concat(others, " ")))
		S().actions.preset_shoulder()
		return 1.5
	end,
	function()
		-- Shoulder kept on while the next unit is followed (the arrows: the offset kept): fitted to that unit, here the
		-- team's unit least like this one in size, of a type without its own Shoulder
		local r0 = Spring.GetUnitRadius(S().following()) or 30
		local bestK
		other = nil
		for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			local own = def and S().presetTypes()[def.name]
			if def and (def.speed or 0) > 0 and not def.name:find("critter", 1, true) and not def.canFly
				and not Spring.GetUnitIsBeingBuilt(unitID) and not (own and own.shoulder) then
				local k = math.abs(math.log((Spring.GetUnitRadius(unitID) or 30) / r0))
				if not bestK or k > bestK then
					other, bestK = unitID, k
				end
			end
		end
		if other then
			S().follow(other, true)
		end
		return 2.5
	end,
	function()
		local fit = S().presetValues("shoulder").fit or { back = -1 }
		local ok, detail = true, "no other unit type here"
		if other then
			ok, detail = shoulderFrame(other)
			-- (the camera as far behind the unit as fitted to it: the distance itself changes with the ground)
			local cx, _, cz = Spring.GetCameraPosition()
			local ux, _, uz = Spring.GetUnitPosition(other)
			local back = math.sqrt((cx - ux) ^ 2 + (cz - uz) ^ 2)
			ok = ok and S().following() == other and math.abs(back - fit.back) < fit.back * 0.3
			local ox, oz, _, ryRel, yaw = S().offset()
			local vx, _, vz = Spring.GetUnitVelocity(other)
			detail = string.format("%s: %s, %.0f behind, fitted %.0f (offset %.0f %.0f, turn %.2f, camera ry %.2f, unit yaw %.2f, "
				.. "speed %.1f)", UnitDefs[Spring.GetUnitDefID(other)].name, detail, back, fit.back, ox, oz, ryRel,
				Spring.GetCameraState().ry or -1, yaw or -1, math.sqrt(vx * vx + vz * vz))
		end
		check("Shoulder on the next unit: fitted to that unit, not the last one", ok, detail)
		S().actions.group()
		S().actions.preset_mid()
		return 1.5
	end,
	function()
		check("Group: its team's units around it", S().members() >= 1, S().members() .. " units")
		check("still nothing selected (no unit panels)", Spring.GetSelectedUnitsCount() == 0,
			Spring.GetSelectedUnitsCount() .. " selected")
		do -- (a tap on the list: the bar again)
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
		check("the tuned Close comes back", cs.dist and math.abs(cs.dist - expected) < 80, string.format("dist %.0f", cs.dist or -1))
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
		check("7 s untouched: the bar gone, the list small", WG.BarDroidPlayers.minimized() and not S().shown())
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
