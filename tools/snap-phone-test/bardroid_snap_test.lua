-- LuaUI widget for tools/snap-phone-test.ps1: the long press's forgiving aim (bardroid_touch.lua SNAP, RtsTouch
-- SNAP_HOLD; Kailil, 2026-11-24: "if im not pixel perfect with my single finger hold on the unit, it just issues a move
-- command close to the unit i want guarded"), checked while the script presses on the dev phone. The script writes a
-- stage into LuaUI/Config/bardroid_snaptest_cmd.txt; the widget answers in the log ("[snaptest] PASS|FAIL <case>") and
-- writes the points the script presses into LuaUI/Config/bardroid_snaptest.txt (X screen pixels, top left origin):
--   give        a Construction Bot and a Pawn given beside the commander
--   camera / camera2  the camera over them, the scene in the map's free middle (above the dock)
--   aim         "guard x y" beside the Pawn (off it: the ray finds the ground), "on x y" on it, "far x y" ground clear
--               of every target, "mex x y" beside a free metal spot (off its circle), "away x y" where a drag goes
--   guard? on? far? mex? drag?   the Construction Bot's first order after the script's press, then it is stopped:
--               Guard of the Pawn, Guard (BAR's own, on the Pawn), Move, the extractor on the spot, a Move (held beside
--               the Pawn, then dragged on: the path, no Guard)
--   end         "[snaptest] done: ALL PASS" or "N FAILED"
function widget:GetInfo()
	return { name = "BAR Droid snap test", desc = "The long press's forgiving aim", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_snaptest.txt", "LuaUI/Config/bardroid_snaptest_cmd.txt"
local SNAP_FILE = "LuaUI/Config/bardroid_snap.txt"
local com, ready, fails, lastCmd = nil, false, 0, nil
local con, pawn, spot -- (the Construction Bot picked, the Pawn, the metal spot aimed beside)
local scene -- { x, y, z }: the middle of what the camera looks at
local OFF = 40 -- X screen pixels beside a target's edge (about 3 mm on the dev phone; the reach is 6 mm)

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[snaptest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end

-- the map's free middle: above the dock and the unit info panel on it, below the top bar (a press on the panel is the
-- panel's: the first run's press beside the Pawn folded it)
local function freeMiddle()
	local vsx, vsy = Spring.GetViewGeometry()
	local P = WG.BarDroidPortrait
	local d = P and P.dock and P.dock()
	local foot = d and d[4] or 0
	local info = P and P.infoRect and P.infoRect()
	if info then
		foot = math.max(foot, info[4])
	end
	return vsx / 2, (foot + vsy * 0.94) / 2, foot
end

-- a place near the commander at least 260 elmos from every metal spot (a Pawn there is aimed at alone: on the first
-- run it stood by a spot, and the spot was nearer the finger)
local function clearOfSpots(x, z)
	local finder = WG.resource_spot_finder
	for _, a in ipairs({ 0, 45, 90, 135, 180, 225, 270, 315 }) do
		local r = math.rad(a)
		local px, pz = x + math.cos(r) * 300, z + math.sin(r) * 300
		local ok = px > 100 and pz > 100 and px < Game.mapSizeX - 100 and pz < Game.mapSizeZ - 100
		for _, s in ipairs(finder and finder.metalSpotsList or {}) do
			ok = ok and (s.x - px) ^ 2 + (s.z - pz) ^ 2 >= 260 * 260
		end
		if ok then
			return px, pz
		end
	end
	return x + 220, z + 60
end

-- a GL point clear of the dock and of the camera's knob and rails
local function clear(x, y)
	local vsx, vsy = Spring.GetViewGeometry()
	local _, _, foot = freeMiddle()
	if x < 20 or x > vsx - 20 or y < foot + 20 or y > vsy * 0.92 then
		return false
	end
	local C = WG.BarDroidCamCtl
	if C and C.rects then
		local kn, zr, trn = C.rects()
		if kn and (x - kn[1]) ^ 2 + (y - kn[2]) ^ 2 <= (kn[3] + 30) ^ 2 then
			return false
		end
		for _, r in ipairs({ zr or false, trn or false }) do
			if r and x >= r[1] - 30 and x <= r[3] + 30 and y >= r[2] - 30 and y <= r[4] + 30 then
				return false
			end
		end
	end
	return true
end

-- elmos per pixel at a ground point on the screen
local function scaleAt(sx, sy)
	local _, a = Spring.TraceScreenRay(sx, sy, true)
	local _, b = Spring.TraceScreenRay(sx + 50, sy, true)
	if a and b then
		return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2) / 50
	end
	return 1
end

local function firstOrder()
	local cmds = con and Spring.GetUnitCommands(con, 3) or {}
	return cmds[1], #cmds
end

local function orderText(c)
	if not c then
		return "no order"
	end
	local name = CMD[c.id] or (c.id < 0 and UnitDefs[-c.id] and ("build " .. UnitDefs[-c.id].name)) or tostring(c.id)
	return string.format("%s %s", name, table.concat(c.params or {}, ","))
end

local function snapAnswer()
	return (readFile(SNAP_FILE) or "nothing"):gsub("\n", "")
end

local function stopCon()
	if con then
		Spring.GiveOrderToUnit(con, CMD.STOP, {}, 0)
		Spring.SelectUnitArray({ con })
	end
end

local function point(name, x, y, out)
	local _, vsy = Spring.GetViewGeometry()
	out[#out + 1] = string.format("%s %d %d", name, math.floor(x + 0.5), math.floor(vsy - y + 0.5))
end

local checked = {} -- the cases checked (end)
local function onCmd(c)
	checked[c] = true
	if c == "give" then
		local x, y, z = Spring.GetUnitPosition(com)
		local px, pz = clearOfSpots(x, z)
		Spring.SendCommands(string.format("give 1 armck %d @%d,%d,%d", Spring.GetMyTeamID(), x - (px - x) * 0.5, y,
			z - (pz - z) * 0.5))
		Spring.SendCommands(string.format("give 1 armpw %d @%d,%d,%d", Spring.GetMyTeamID(), px, Spring.GetGroundHeight(px, pz), pz))
	elseif c == "camera" then
		for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
			local d = Spring.GetUnitDefID(u)
			if d == UnitDefNames.armck.id then
				con = u
			elseif d == UnitDefNames.armpw.id then
				pawn = u
			end
		end
		if not (con and pawn) then
			check("the Construction Bot and the Pawn given", false, string.format("con %s, pawn %s", tostring(con), tostring(pawn)))
			return
		end
		Spring.GiveOrderToUnit(con, CMD.STOP, {}, 0)
		Spring.GiveOrderToUnit(pawn, CMD.STOP, {}, 0)
		Spring.GiveOrderToUnit(pawn, CMD.MOVE_STATE, { 0 }, 0) -- (hold position: it stays where it is aimed at)
		local x, y, z = Spring.GetUnitPosition(com)
		local ux, _, uz = Spring.GetUnitPosition(pawn)
		scene = { (x + ux) / 2, y, (z + uz) / 2 }
		Spring.SelectUnitArray({ con })
		local st = Spring.GetCameraState()
		if st.dist then
			st.dist = 1100
		end
		if st.height then
			st.height = 1100
		end
		Spring.SetCameraState(st, 0)
		Spring.SetCameraTarget(scene[1], scene[2], scene[3], 0)
	elseif c == "spotcam" then -- (the mex case: the camera over the free metal spot nearest the commander)
		local finder, rb = WG.resource_spot_finder, WG.resource_spot_builder
		local x, _, z = Spring.GetUnitPosition(com)
		local bestD
		spot = nil
		for _, s in ipairs(finder and finder.metalSpotsList or {}) do
			local free = rb and rb.ExtractorCanBeBuiltOnSpot and rb.ExtractorCanBeBuiltOnSpot(s, UnitDefNames.armmex.id)
			local d = (s.x - x) ^ 2 + (s.z - z) ^ 2
			if free and #(Spring.GetUnitsInCylinder(s.x, s.z, 200) or {}) == 0 and (not bestD or d < bestD) then
				spot, bestD = s, d
			end
		end
		if spot then
			scene = { spot.x, spot.y or Spring.GetGroundHeight(spot.x, spot.z), spot.z }
			Spring.SetCameraTarget(scene[1], scene[2], scene[3], 0)
		end
	elseif c == "camera2" and scene then -- (the scene where the free middle is, not under the dock)
		local mx, my = freeMiddle()
		local _, hit = Spring.TraceScreenRay(mx, my, true)
		if hit then
			local st = Spring.GetCameraState()
			-- (the zoom again: a run whose camera stood at 1.81 elmos a pixel had the game's own start move after
			-- "camera"; the script runs both twice)
			if st.dist then
				st.dist = 1100
			end
			if st.height then
				st.height = 1100
			end
			local tx, tz = scene[1] + (scene[1] - hit[1]), scene[3] + (scene[3] - hit[3])
			if st.px then
				st.px, st.pz = st.px + (scene[1] - hit[1]), st.pz + (scene[3] - hit[3])
				Spring.SetCameraState(st, 0)
			else
				Spring.SetCameraTarget(tx, scene[2], tz, 0)
			end
		end
	elseif c == "aim" then
		local out = {}
		local per
		if pawn then -- beside the Pawn: its edge on the screen plus OFF, away from the commander
			local _, _, _, ux, uy, uz = Spring.GetUnitPosition(pawn, true)
			local sx, sy = Spring.WorldToScreenCoords(ux, uy, uz)
			per = scaleAt(sx, sy)
			local rpx = UnitDefs[UnitDefNames.armpw.id].radius / per
			local gx = sx + rpx + OFF
			local kind = Spring.TraceScreenRay(gx, sy)
			if clear(gx, sy) and kind == "ground" then
				point("guard", gx, sy, out)
				point("away", gx + 160, sy + 120, out)
			else
				Spring.Echo(string.format("[snaptest] NOT RUN guard: the point beside the Pawn %s (%s)",
					clear(gx, sy) and "is on something" or "is not in the map's free part", tostring(kind)))
			end
			if clear(sx, sy) then
				point("on", sx, sy, out)
			end
		end
		-- ground clear of every target: the free middle's top quarter, a little left, if nothing is within 200 pixels
		local vsx, vsy = Spring.GetViewGeometry()
		local _, mid, foot = freeMiddle()
		for _, cand in ipairs({ { vsx * 0.3, mid + (vsy - mid) * 0.5 }, { vsx * 0.7, mid + (vsy - mid) * 0.5 },
			{ vsx * 0.25, foot + 120 }, { vsx * 0.75, foot + 120 } }) do
			local cx, cy = cand[1], cand[2]
			local _, g = Spring.TraceScreenRay(cx, cy, true)
			local busy = not g or not clear(cx, cy)
			if g then
				local reach = 200 * scaleAt(cx, cy)
				busy = busy or #(Spring.GetUnitsInCylinder(g[1], g[3], reach) or {}) > 0
				for _, f in ipairs(Spring.GetFeaturesInCylinder(g[1], g[3], reach) or {}) do
					local fd = FeatureDefs[Spring.GetFeatureDefID(f)]
					busy = busy or (fd and (fd.metal or 0) > 0)
				end
				local finder = WG.resource_spot_finder
				for _, s in ipairs(finder and finder.metalSpotsList or {}) do
					busy = busy or (s.x - g[1]) ^ 2 + (s.z - g[3]) ^ 2 <= reach * reach
				end
			end
			if not busy then
				point("far", cx, cy, out)
				break
			end
		end
		write(table.concat(out, "\n") .. "\n")
		Spring.Echo(string.format("[snaptest] aimed: %s (%.2f elmos a pixel)", table.concat(out, "; "), per or 0))
	elseif c == "aimmex" then -- beside the spot spotcam looked at: the extractor's edge plus OFF, away from other spots
		local out = {}
		if spot then
			local sx, sy = Spring.WorldToScreenCoords(spot.x, spot.y or Spring.GetGroundHeight(spot.x, spot.z), spot.z)
			local rpx = UnitDefs[UnitDefNames.armmex.id].radius / scaleAt(sx, sy) -- (the snap's size of a spot)
			for _, dir in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local px, py = sx + dir[1] * (rpx + OFF), sy + dir[2] * (rpx + OFF)
				if clear(px, py) and Spring.TraceScreenRay(px, py) == "ground" then
					point("mex", px, py, out)
					break
				end
			end
		end
		if #out == 0 then
			Spring.Echo("[snaptest] NOT RUN mex: no free metal spot " .. (spot and "with a clear point beside it" or "near the commander"))
		end
		write(table.concat(out, "\n") .. "\n")
		Spring.Echo(string.format("[snaptest] aimed for the mex: %s", table.concat(out, "; ")))
	elseif c == "guard?" or c == "on?" then
		local o = firstOrder()
		check(c == "guard?" and "held a finger's width beside the Pawn: the Construction Bot guards it"
			or "held on the Pawn itself: it guards it (BAR's own right click)",
			o and o.id == CMD.GUARD and o.params and o.params[1] == pawn,
			string.format("%s (the Pawn %s; the answer '%s')", orderText(o), tostring(pawn), snapAnswer()))
		stopCon()
	elseif c == "far?" then
		local o = firstOrder()
		check("held on open ground: a Move there", o and o.id == CMD.MOVE,
			string.format("%s (the answer '%s')", orderText(o), snapAnswer()))
		stopCon()
	elseif c == "mex?" then
		local o = firstOrder()
		local near = o and spot and o.params and o.params[1] and (o.params[1] - spot.x) ^ 2 + (o.params[3] - spot.z) ^ 2
			<= 80 * 80
		check("held a finger's width beside a free metal spot: an extractor queued on it",
			o and o.id < 0 and UnitDefs[-o.id] and UnitDefs[-o.id].extractsMetal and UnitDefs[-o.id].extractsMetal > 0 and near,
			string.format("%s (the spot %s; the answer '%s')", orderText(o), spot and (spot.x .. "," .. spot.z) or "none",
				snapAnswer()))
		stopCon()
	elseif c == "drag?" then
		local o = firstOrder()
		check("held beside the Pawn, then dragged on: the path, no Guard", o and o.id == CMD.MOVE,
			string.format("%s (the answer '%s')", orderText(o), snapAnswer()))
		stopCon()
	elseif c == "end" then -- (a case with no point to press is a FAIL too: a run with one case read ALL PASS)
		for _, case in ipairs({ "guard?", "on?", "far?", "drag?", "mex?" }) do
			if not checked[case] then
				check(case:sub(1, -2) .. " checked", false, "not run: no point to press")
			end
		end
		Spring.Echo("[snaptest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
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
	if com and not ready and f >= 320 then
		ready = true
		Spring.Echo("[snaptest] ready")
	end
end

-- (between frames too: the stages go on while the game is paused)
local cmdAt = 0
function widget:Update()
	local t = os.clock()
	if not ready or t - cmdAt < 0.2 then
		return
	end
	cmdAt = t
	local f = io.open(CMD_FILE, "r")
	local c = f and f:read("*l")
	if f then
		f:close()
	end
	if c and c ~= lastCmd then
		lastCmd = c
		onCmd(c)
	end
end
