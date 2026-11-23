-- LuaUI widget for tools/touchfix-phone-test.ps1: the night's touch playtest's fixes (docs/PLAYTEST.md, 2026-11-22) on
-- the dev phone, upright, by real taps where the fix is about taps. The script writes a stage into
-- LuaUI/Config/bardroid_fixtest_cmd.txt; the widget answers "[fixtest] PASS|FAIL <case>" in the log and writes what the
-- script taps into LuaUI/Config/bardroid_fixtest.txt ("key x y", X screen pixels, top left origin).
-- In a game (a map with water, the script sets it):
--   (frame 300) the commander picked; "[fixtest] ready"
--   twinvoid / twinvoid?   the Solar picked with the pointer over the void past the map's edge (and moved over it):
--                          still the Solar, not its Tidal twin (phone-widget-cmd_context_build.lua)
--   twinspots              the camera on a shore by the commander: "water x y", "land x y"
--   tide? / solar?         after the script's real tap on the water / the land: the Tidal / the Solar picked
--   placed?                after PLACE: a Solar first in the commander's queue at the land spot
--   walls?                 the Sentry picked: WALLS' cost (bardroid_walls.lua) a ring of Dragon's Teeth's metal
--   insertsetup            the commander given two far Solars; "qrect", "irect": QUEUE's and INSERT's zones; a wind
--                          picked; "spot1 x y", "spot2 x y": two land spots
--   insert1? / insert2?    INSERT alone, then QUEUE+INSERT: the winds at the queue's front, in the order placed
--   dgun                   the D-gun mode on (the pad's act); "stickr x y r" from the dock's file is the script's
--   aim? <dx> <dy>         after a quick flick of the AIM stick that way (x right, y down): the shot's way the stick's,
--                          camera-relative (bardroid_pad.lua sticks, touch)
--   pause / unpause        the game paused / running again (BAR's pause)
--   tapat / tapaim?        "tapat x y": a ground point beside the commander; after the script's tap there: the shot's
--                          way towards it, the mode still on, the commander still picked
--   end                    "[fixtest] done: ALL PASS" or "N FAILED"
function widget:GetInfo()
	return { name = "BAR Droid touch fix test", desc = "The touch playtest's fixes", author = "BAR Droid", layer = 0,
		enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_fixtest.txt", "LuaUI/Config/bardroid_fixtest_cmd.txt"
local com, ready, fails, lastCmd = nil, false, 0, nil
local D = {}
for _, n in ipairs({ "armsolar", "armtide", "armllt", "armdrag", "armwin", "armtl" }) do
	D[n] = UnitDefNames[n] and UnitDefNames[n].id
end
local landSpot, spots, solars, tapPoint
-- (paused by this test's own case only: another session's dev widget on the phone may pause the game on its events, and
-- orders given while paused are not in the queues yet; unpaused again at once, at most every 2 s)
local pausedHere, unpausedAt = false, nil
local turned = false -- (the camera turned for the D-gun's flicks)

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[fixtest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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
local function armedDef()
	local pb = WG["pregame-build"]
	if Spring.GetGameFrame() == 0 and pb and pb.getPreGameDefID then
		return pb.getPreGameDefID()
	end
	local _, id = Spring.GetActiveCommand()
	return id and id < 0 and -id or nil
end
local function nameOf(def)
	return def and UnitDefs[def] and UnitDefs[def].name or tostring(def)
end
local function arm(def)
	local pb = WG["pregame-build"]
	if Spring.GetGameFrame() == 0 and pb and pb.setPreGamestartDefID then
		pb.setPreGamestartDefID(def)
		return
	end
	local index = Spring.GetCmdDescIndex(-def)
	if index then
		Spring.SetActiveCommand(index, 1, true, false, false, false, false, false)
	end
end
-- X pixels (top left origin) of a ground point in sight above the dock, clear of the camera's knob and rails; or nil
local function screenOf(x, z, y) -- (y: the height to see it at, the ground's if none)
	local sx, sy, sz = Spring.WorldToScreenCoords(x, y or Spring.GetGroundHeight(x, z), z)
	local vsx, vsy = Spring.GetViewGeometry()
	local P = WG.BarDroidPortrait
	local dock = P and P.dock and P.dock()
	if sz > 1 or sx < 80 or sx > vsx - 80 or sy < (dock and dock[4] or 0) + 120 or sy > vsy - 220 then
		return nil
	end
	local C = WG.BarDroidCamCtl
	if C and C.rects then
		local k, zr, tr = C.rects()
		if k and (sx - k[1]) ^ 2 + (sy - k[2]) ^ 2 <= (k[3] + 110) ^ 2 then
			return nil
		end
		for _, r in ipairs({ zr or false, tr or false }) do
			if r and sx >= r[1] - 100 and sx <= r[3] + 100 and sy >= r[2] - 40 and sy <= r[4] + 40 then
				return nil
			end
		end
	end
	return math.floor(sx), math.floor(vsy - sy)
end
-- a spot for def near (cx, cz) on the screen, buildable (2: rocks the builder reclaims, 3: open), not near "avoid"s
local function freeSpot(def, cx, cz, avoid, minR)
	for r = minR or 120, 1400, 40 do
		for a = 0, 350, 10 do
			local x, z = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
			local bx, by, bz = Spring.Pos2BuildPos(def, x, Spring.GetGroundHeight(x, z), z, 0)
			local far = true
			for _, o in ipairs(avoid or {}) do
				far = far and math.abs(bx - o[1]) + math.abs(bz - o[3]) > 140
			end
			-- (above the water's level: BAR's swap tests that; a Solar's build test alone took a low shore)
			if far and Spring.GetGroundHeight(bx, bz) > 0.05 and Spring.TestBuildOrder(def, bx, by, bz, 0) >= 2
				and screenOf(bx, bz) then
				return { bx, by, bz }
			end
		end
	end
end
local function rectLine(key, r)
	local _, vsy = Spring.GetViewGeometry()
	return r and string.format("%s %d %d %d %d\n", key, r[1], vsy - r[4], r[3], vsy - r[2]) or ""
end
local function spotLine(key, p)
	local sx, sy
	if p then
		sx, sy = screenOf(p[1], p[3])
	end
	return sx and string.format("%s %d %d\n", key, sx, sy) or ""
end
local function queueOf(u)
	local out = {}
	for _, c in ipairs(Spring.GetUnitCommands(u, -1) or {}) do
		if c.id < 0 then
			out[#out + 1] = { -c.id, c.params[1], c.params[3] }
		end
	end
	return out
end
local function queueText(q)
	local t = {}
	for _, o in ipairs(q) do
		t[#t + 1] = nameOf(o[1]) .. "@" .. math.floor(o[2]) .. "," .. math.floor(o[3])
	end
	return table.concat(t, " ")
end
-- a wind of mine standing (built or being built) at a spot
local function builtAt(p)
	for _, u in ipairs(p and Spring.GetUnitsInCylinder(p[1], p[3], 40, Spring.GetMyTeamID()) or {}) do
		if Spring.GetUnitDefID(u) == D.armwin then
			return true
		end
	end
	return false
end
local function near(o, p)
	return o and p and math.abs(o[2] - p[1]) < 48 and math.abs(o[3] - p[3]) < 48
end
local function angleBetween(ax, az, bx, bz)
	local dot = math.max(-1, math.min(1, ax * bx + az * bz))
	return math.deg(math.acos(dot))
end
local function aimNow()
	local P = WG.BarDroidPad
	if not (P and P.modal) then
		return nil
	end
	local _, _, ax, az = P.modal()
	return ax, az
end
-- a screen pixel over the void past the map's edge, above the dock; nil: none in sight
local function voidPixel(skip)
	local vsx, vsy = Spring.GetViewGeometry()
	local P = WG.BarDroidPortrait
	local dock = P and P.dock and P.dock()
	local y0 = (dock and dock[4] or 0) + 60
	for y = vsy - 140, y0, -40 do
		for x = 60, vsx - 60, 40 do
			local _, pos = Spring.TraceScreenRay(x, y, true, false)
			if pos and (pos[1] < -40 or pos[3] < -40 or pos[1] > Game.mapSizeX + 40 or pos[3] > Game.mapSizeZ + 40)
				and not (skip and math.abs(skip[1] - x) + math.abs(skip[2] - y) < 100) then
				return { x, y }
			end
		end
	end
end
-- a screen pixel above the dock whose ground is at the water's level (BAR's swap's test), in the map
local function waterPixel()
	local vsx, vsy = Spring.GetViewGeometry()
	local P = WG.BarDroidPortrait
	local dock = P and P.dock and P.dock()
	local y0 = (dock and dock[4] or 0) + 120
	for y = vsy - 220, y0, -40 do
		for x = 100, vsx - 100, 40 do
			local _, pos = Spring.TraceScreenRay(x, y, true, false)
			if pos and pos[2] < 0.01 and pos[1] > 0 and pos[3] > 0 and pos[1] < Game.mapSizeX and pos[3] < Game.mapSizeZ
				and Spring.GetGroundHeight(pos[1], pos[3]) < -12 then
				return { x, y }
			end
		end
	end
end
-- the nearest water (deeper than a Tidal needs) to the commander, and the shore's land beside it
local function shore()
	local cx, _, cz = Spring.GetUnitPosition(com)
	local best, bestD
	for x = 64, Game.mapSizeX - 64, 64 do
		for z = 64, Game.mapSizeZ - 64, 64 do
			if Spring.GetGroundHeight(x, z) < -20 then
				local d = (x - cx) ^ 2 + (z - cz) ^ 2
				if not bestD or d < bestD then
					best, bestD = { x, z }, d
				end
			end
		end
	end
	return best
end

local function onCmd(c)
	local P = WG.BarDroidPad
	local Pt = WG.BarDroidPortrait
	if c == "twinvoid" then
		-- (the camera on the shore nearest the commander, the water and the land beside it in sight)
		local w = shore()
		if not w then
			check("water on this map", false, "none deeper than 20")
			return
		end
		local cx, _, cz = Spring.GetUnitPosition(com)
		local dx, dz = cx - w[1], cz - w[2]
		local d = math.max(1, math.sqrt(dx * dx + dz * dz))
		local k = math.min(d, 300) / d
		Spring.SetCameraTarget(w[1] + dx * k, 0, w[2] + dz * k, 0)
		spots = { water = w }
	elseif c == "twinvoid2" then
		-- (the pointer resting over water, as a phone's after a tap there or past the map's edge: then the Solar picked,
		-- as the dock's tile does)
		local v = waterPixel()
		if not v then
			check("water in sight above the dock", false, "no water pixel")
			return
		end
		spots.first = v
		Spring.WarpMouse(v[1], v[2])
		arm(D.armsolar)
		Spring.Echo("[fixtest] the Solar picked, the pointer resting over water at " .. v[1] .. "," .. v[2])
	elseif c == "twinvoid3" then
		check("the Solar picked with the pointer resting over water: still the Solar (no Tidal twin)",
			armedDef() == D.armsolar, "picked " .. nameOf(armedDef()))
		local v = voidPixel(spots.first)
		spots.void = v
		if v then
			Spring.WarpMouse(v[1], v[2])
		end
	elseif c == "twinvoid?" then
		if spots.void then
			check("the pointer moved past the map's edge: still the Solar", armedDef() == D.armsolar,
				"picked " .. nameOf(armedDef()))
		else
			Spring.Echo("[fixtest] note: no pixel past the map's edge in sight, that case not run")
		end
	elseif c == "twinspots" then
		Spring.SetActiveCommand(0)
		arm(D.armsolar) -- (a new pick: the taps below are the pointer's moves)
		-- (the land nearest the water that takes a Solar, anywhere, and the camera between the two: both in sight. Looked
		-- for in the camera's view alone, some start spots had none, their shore all under the water's level; the train's
		-- runs at 02347f64, 2026-11-22)
		local w = spots.water
		local land
		for r = 48, 2400, 48 do
			for a = 0, 345, 15 do
				local x, z = w[1] + math.cos(math.rad(a)) * r, w[2] + math.sin(math.rad(a)) * r
				if not land and x > 64 and z > 64 and x < Game.mapSizeX - 64 and z < Game.mapSizeZ - 64
					and Spring.GetGroundHeight(x, z) > 2 then
					local bx, by, bz = Spring.Pos2BuildPos(D.armsolar, x, Spring.GetGroundHeight(x, z), z, 0)
					if Spring.GetGroundHeight(bx, bz) > 2 and Spring.TestBuildOrder(D.armsolar, bx, by, bz, 0) >= 2 then
						land = { bx, by, bz }
					end
				end
			end
			if land then
				break
			end
		end
		spots.land = land
		local tx, tz = w[1], w[2]
		if land then
			tx, tz = (w[1] + land[1]) / 2, (w[2] + land[3]) / 2
		end
		-- (between the two in the middle of the map above the dock: the screen's middle, SetCameraTarget's, is the dock's
		-- top upright, and the land 147 elmos off lay under it, "in sight false", 2026-11-22)
		if Pt and Pt.cameraTo then
			Pt.cameraTo(tx, Spring.GetGroundHeight(tx, tz), tz)
		else
			Spring.SetCameraTarget(tx, 0, tz, 0)
		end
	elseif c == "twincloser" then -- (no water in sight from there: the camera nearer the water, the twinvoid case's)
		local w = spots.water
		local cx, _, cz = Spring.GetUnitPosition(com)
		local dx, dz = cx - w[1], cz - w[2]
		local d = math.max(1, math.sqrt(dx * dx + dz * dz))
		local k = math.min(d, 250) / d
		Spring.SetCameraTarget(w[1] + dx * k, 0, w[2] + dz * k, 0)
	elseif c == "twinspots2" then
		-- (the water and the land found in twinspots, where in sight; else a water point in sight and the land nearest it)
		-- (the water's pixel where a tap sees it: its surface, not the sea floor, and the ray from there on the water. From
		-- the sea floor's pixel, in the lower view another test's camera left, the ray met the shore first: the tap took
		-- land 290 elmos off and the Solar stayed, the build train 2026-11-22)
		local _, vsy = Spring.GetViewGeometry()
		local function onWater(sx, ty) -- (a top-left-origin pixel: the ray from it on water deeper than a Tidal needs)
			local _, pos = Spring.TraceScreenRay(sx, vsy - ty, true, false)
			return pos and Spring.GetGroundHeight(pos[1], pos[3]) < -12 and pos or nil
		end
		local wp, wx, wy
		local w = spots.water
		if w and Spring.GetGroundHeight(w[1], w[2]) < -12 then
			wx, wy = screenOf(w[1], w[2], 0)
			if wx and onWater(wx, wy) then
				wp = { w[1], 0, w[2] }
			else
				wx, wy = nil, nil
			end
		end
		if not wp then
			local px = waterPixel() -- (a pixel whose ray is on the water, GL's bottom-left origin)
			if px then
				local pos = onWater(px[1], vsy - px[2])
				if pos then
					wp, wx, wy = { pos[1], 0, pos[3] }, px[1], vsy - px[2]
				end
			end
		end
		local L = spots.land
		landSpot = L and screenOf(L[1], L[3]) and L or wp and freeSpot(D.armsolar, wp[1], wp[3], nil, 160)
		Spring.Echo(string.format("[fixtest] note: water %s, the land found %s (%s), in sight %s", tostring(wp ~= nil),
			L and string.format("%d,%d", L[1], L[3]) or "none", L and spots.water and string.format("%d elmos from the water",
			math.sqrt((L[1] - spots.water[1]) ^ 2 + (L[3] - spots.water[2]) ^ 2)) or "-", tostring(landSpot ~= nil)))
		write((wx and string.format("water %d %d\n", wx, wy) or "") .. spotLine("land", landSpot))
		spots.camAt = Spring.GetCameraState()
		Spring.Echo(string.format("[fixtest] note: the water at %s on the screen %s,%s",
			wp and string.format("%d,%d", wp[1], wp[3]) or "nil", tostring(wx), tostring(wy)))
		Spring.Echo("[fixtest] spots: water " .. tostring(wp ~= nil) .. ", land " .. tostring(landSpot ~= nil))
	elseif c == "tide?" then
		-- (where the tap went: the pointer, the ground under it, and the camera's motion since the spots were named)
		local mx, my = Spring.GetMouseState()
		local _, pos = Spring.TraceScreenRay(mx, my, true)
		local cs, ca = Spring.GetCameraState(), spots.camAt or {}
		Spring.Echo(string.format("[fixtest] note: the water tap: the pointer %d,%d on %s (ground %s); the camera %s,%s then, "
			.. "%s,%s now", mx, my, pos and string.format("%d,%d", pos[1], pos[3]) or "nil",
			pos and string.format("%.0f", Spring.GetGroundHeight(pos[1], pos[3])) or "-", tostring(ca.px and math.floor(ca.px)),
			tostring(ca.pz and math.floor(ca.pz)), tostring(cs.px and math.floor(cs.px)), tostring(cs.pz and math.floor(cs.pz))))
		check("a real tap on the water: its Tidal twin picked (BAR's own swap still works)", armedDef() == D.armtide,
			"picked " .. nameOf(armedDef()))
	elseif c == "solar?" then
		check("a real tap on the land: the Solar picked again", armedDef() == D.armsolar, "picked " .. nameOf(armedDef()))
	elseif c == "placed?" then
		local q = queueOf(com)
		check("PLACE: the Solar first in the commander's queue at the land spot", q[1] and q[1][1] == D.armsolar
			and near(q[1], landSpot), queueText(q))
		Spring.GiveOrderToUnit(com, CMD.STOP, {}, 0)
		Spring.SetActiveCommand(0)
	elseif c == "walls?" then
		Spring.SelectUnitArray({ com })
		arm(D.armllt)
		local W = WG.BarDroidWalls
		local cost = W and W.cost and W.cost(D.armllt)
		local want = math.floor(8 * (UnitDefs[D.armdrag].metalCost or 0) + 0.5)
		check("WALLS' cost for a Sentry: 8 Dragon's Teeth's metal", cost == want, tostring(cost) .. ", want " .. want)
		local none = W and W.cost and W.cost(D.armsolar)
		check("no WALLS cost for a Solar", none == nil, tostring(none))
	elseif c == "pausesetup" then -- (nothing picked: the home grid's PAUSE, a game of one player; RC 0.2.0 item 4)
		pausedHere = true -- (this case pauses: not unpaused by this widget meanwhile)
		Spring.SetActiveCommand(0)
		Spring.SelectUnitArray({})
	elseif c == "pausesetup2" then
		if Pt and Pt.menuOpen then -- (the home grid's first touch would only open the menu)
			Pt.menuOpen(true)
		end
		local cell = Pt and Pt.itemCell and Pt.itemCell("right", function(it)
			return it.kind == "pause"
		end)
		write(rectLine("pause", cell and cell[3] > cell[1] and cell or nil))
		if not cell then
			check("PAUSE on the home grid in a game of one player", false, "no PAUSE among the home grid's buttons")
		end
	elseif c == "paused?" then
		local _, item = Pt.itemCell("right", function(it)
			return it.kind == "pause"
		end)
		check("PAUSE tapped: the game paused, the button lit (PAUSED)", select(3, Spring.GetGameSpeed()) == true
			and item and item.on == true and item.label == "PAUSED", "paused " .. tostring(select(3, Spring.GetGameSpeed()))
			.. ", button " .. tostring(item and item.label))
	elseif c == "unpaused?" then
		local _, item = Pt.itemCell("right", function(it)
			return it.kind == "pause"
		end)
		check("PAUSED tapped: the game runs again, the button PAUSE", not select(3, Spring.GetGameSpeed())
			and item and item.on == false, "paused " .. tostring(select(3, Spring.GetGameSpeed())) .. ", button "
			.. tostring(item and item.label))
		pausedHere = false
		Spring.SelectUnitArray({ com })
	elseif c == "guardsetup" then -- (a tap as the dock changes under it: dropped; RC 0.2.0 item 4, NB3-5)
		Spring.SetActiveCommand(0)
		Spring.SelectUnitArray({ com })
	elseif c == "guardsetup2" then
		if Pt and Pt.menuOpen then -- (open, as in the playtest: nothing picked, the energy bar takes a tap)
			Pt.menuOpen(true)
		end
		write(rectLine("qrect", Pt and Pt.queueRect and Pt.queueRect()))
	elseif c == "guarddrop" then -- (the finger down on QUEUE: nothing picked now, the energy bar in its place)
		Spring.SelectUnitArray({})
		spots.guardAt = Spring.GetTimer()
	elseif c == "guard?" then
		local open = Pt and Pt.resPanel and Pt.resPanel()
		check("a tap lifted on QUEUE's place just after the selection went (the energy bar there now): dropped",
			open == nil, "panel " .. tostring(open))
	elseif c == "guardlater?" then
		local open = Pt and Pt.resPanel and Pt.resPanel()
		check("... the same place tapped a moment later: the bar there takes it (its panel open)", open ~= nil,
			"panel " .. tostring(open))
	elseif c == "holdsetup" then -- (a build tile held: its name and role up while held, RC 0.2.0 item 4)
		Spring.SetActiveCommand(0)
		Spring.SelectUnitArray({ com })
	elseif c == "holdsetup2" then
		local cell = Pt and Pt.itemCell and Pt.itemCell("left", function(it)
			return it.defID == D.armwin
		end)
		write(rectLine("htile", cell and cell[3] > cell[1] and cell or nil))
	elseif c == "holdtip?" then
		local held = Pt and Pt.holdTip and Pt.holdTip()
		check("a build tile held: its name and role up while the finger stays", held == D.armwin, "held " .. nameOf(held))
	elseif c == "holdgone?" then
		local held = Pt and Pt.holdTip and Pt.holdTip()
		check("the finger lifted: the name and role gone", held == nil, "held " .. nameOf(held))
		Spring.SetActiveCommand(0)
	elseif c == "insertsetup" then
		Spring.SetActiveCommand(0)
		local cx, _, cz = Spring.GetUnitPosition(com)
		Spring.SetCameraTarget(cx, 0, cz, 0)
		-- (two Solars far off, to be in the queue: the winds placed with INSERT must go before them)
		solars = {}
		for _, a in ipairs({ 0, 180 }) do
			for r = 700, 1600, 100 do
				local x, z = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
				local bx, by, bz = Spring.Pos2BuildPos(D.armsolar, x, Spring.GetGroundHeight(x, z), z, 0)
				if #solars < (a == 0 and 1 or 2) and bx > 64 and bz > 64 and bx < Game.mapSizeX - 64 and bz < Game.mapSizeZ - 64
					and Spring.TestBuildOrder(D.armsolar, bx, by, bz, 0) >= 2 then
					solars[#solars + 1] = { bx, by, bz }
				end
			end
		end
		for i, s in ipairs(solars) do
			Spring.GiveOrderToUnit(com, -D.armsolar, { s[1], s[2], s[3], 0 }, i > 1 and { "shift" } or 0)
		end
		Spring.SelectUnitArray({ com })
	elseif c == "insertsetup2" then
		local cx, _, cz = Spring.GetUnitPosition(com)
		local s1 = freeSpot(D.armwin, cx, cz, solars, 140)
		local s2 = s1 and freeSpot(D.armwin, cx, cz, { s1, solars[1] or s1, solars[2] or s1 }, 140)
		local s3 = s2 and freeSpot(D.armwin, cx, cz, { s1, s2, solars[1] or s1, solars[2] or s1 }, 140)
		spots.s1, spots.s2, spots.s3 = s1, s2, s3
		write(rectLine("qrect", Pt and Pt.queueRect and Pt.queueRect()) .. rectLine("irect", Pt and Pt.insertRect
			and Pt.insertRect()) .. spotLine("spot1", s1) .. spotLine("spot2", s2) .. spotLine("spot3", s3))
		Spring.Echo("[fixtest] insert: " .. #solars .. " far Solars queued: " .. queueText(queueOf(com)))
	elseif c == "armwind" then
		arm(D.armwin)
	elseif c == "mark1?" or c == "mark2?" then -- (PLACE's corner says what the placement does: the in-play tour)
		local want = c == "mark1?" and "+ INSERT" or "+ QUEUE  + INSERT"
		local m = Pt and Pt.placeMark and Pt.placeMark()
		check("PLACE up with " .. (c == "mark1?" and "INSERT" or "QUEUE and INSERT") .. " on: its corner says " .. want,
			m == want, "mark " .. tostring(m))
	elseif c == "insert1?" then
		local q = queueOf(com)
		local qOn, iOn = P.queueState()
		check("INSERT alone on a builder: the wind at the queue's front", q[1] and q[1][1] == D.armwin and near(q[1], spots.s1),
			queueText(q) .. string.format(" (QUEUE %s, INSERT %s)", tostring(qOn), tostring(iOn)))
	elseif c == "insert2?" then
		local q = queueOf(com)
		local qOn, iOn = P.queueState()
		-- (INSERT's first wind may be built already: the commander stands by it; while it builds its order stays)
		local firstBuilt = builtAt(spots.s1) and not (q[2] and near(q[2], spots.s1))
		check("QUEUE+INSERT on a builder: the wind at the queue's front (it went to the end with Shift+Alt)",
			q[1] and q[1][1] == D.armwin and near(q[1], spots.s2) and #q == #solars + (firstBuilt and 1 or 2),
			queueText(q) .. string.format(" (QUEUE %s, INSERT %s%s)", tostring(qOn), tostring(iOn),
				firstBuilt and ", INSERT's first built" or ""))
	elseif c == "insert3?" then
		local q = queueOf(com)
		-- (the two QUEUE+INSERT ones in either order: the held key's repeats start CommandInsert's count again or not)
		local top = q[1] and q[2] and ((near(q[1], spots.s3) and near(q[2], spots.s2)) or (near(q[1], spots.s2)
			and near(q[2], spots.s3)))
		local firstBuilt = builtAt(spots.s1) and not (q[3] and near(q[3], spots.s1))
		check("QUEUE+INSERT again: the next one at the front too, before INSERT's first and the far Solars",
			top and (firstBuilt and #q == #solars + 2 or q[3] and near(q[3], spots.s1) and #q == #solars + 3), queueText(q)
			.. (firstBuilt and " (INSERT's first built)" or ""))
		Spring.GiveOrderToUnit(com, CMD.STOP, {}, 0)
		Spring.SetActiveCommand(0)
	elseif c == "dgun" then
		Spring.SelectUnitArray({ com })
		Spring.SetActiveCommand(0)
		P.act("dgun")
		Spring.Echo("[fixtest] dgun on: " .. tostring(WG.BarDroidPadDgun and WG.BarDroidPadDgun.active()))
	elseif c == "turn" then -- (the camera turned, as the rail turns it: the stick's ways are the screen's still)
		local cs = Spring.GetCameraState()
		if cs.ry then
			cs.ry = cs.ry + 2.3
			Spring.SetCameraState(cs, 0)
			turned = true
		else
			Spring.Echo("[fixtest] note: this camera has no turn (" .. tostring(cs.name) .. ")")
		end
	elseif c:match("^aim%? ") then
		local dx, dy = c:match("^aim%? (%S+) (%S+)")
		dx, dy = tonumber(dx), tonumber(dy)
		-- (on the screen: the commander's place and a point along the shot's way, as the player sees the aim line)
		local ax, az = aimNow()
		local off = 180
		local ux, uy, uz = Spring.GetUnitPosition(com)
		if ax and ux then
			local sx, sy = Spring.WorldToScreenCoords(ux, uy, uz)
			local px, pz = ux + ax * 150, uz + az * 150
			local tx, ty = Spring.WorldToScreenCoords(px, Spring.GetGroundHeight(px, pz), pz)
			local vx, vy = tx - sx, ty - sy
			local l = math.max(0.001, math.sqrt(vx * vx + vy * vy))
			local sl = math.sqrt(dx * dx + dy * dy)
			off = angleBetween(vx / l, vy / l, dx / sl, -dy / sl) -- (the stick's y runs down, GL's up)
		end
		check(string.format("a quick flick of AIM (%s%s%s, %s): the shot that way on the screen", turned and "camera turned, "
			or "", select(3, Spring.GetGameSpeed()) and "paused, " or "", dx, dy), off <= 20, string.format("%.0f degrees off", off))
	elseif c == "pause" then
		pausedHere = true
		Spring.SendCommands("pause 1")
	elseif c == "unpause" then
		pausedHere = false
		Spring.SendCommands("pause 0")
	elseif c == "enemy" then -- (an enemy wind turbine given beside the commander, in sight above the dock, for the tap:
		-- one that stands still, so the real tap finds it)
		local gaia = Spring.GetGaiaTeamID()
		local foe
		for _, t in ipairs(Spring.GetTeamList() or {}) do
			if t ~= gaia and not Spring.AreTeamsAllied(t, Spring.GetMyTeamID()) then
				foe = foe or t
			end
		end
		local cx, cy, cz = Spring.GetUnitPosition(com)
		local ax, az = aimNow()
		local at
		-- (on land a Cortex wind can stand on: by the sea the spot was water now and then, nothing came of the give and
		-- the case never ran, 2026-11-22)
		local wind = UnitDefNames.corwin.id
		for _, dist in ipairs({ 150, 130, 170 }) do -- (well within the D-gun's reach: the rings' check tells the enemy from
			-- the reach, ~250; at 230 the reach was 22 elmos off it)
			for _, turn in ipairs({ -90, 90, -135, 135, 180, -45, 45 }) do
				local r = math.rad(turn)
				local hx, hz = ax * math.cos(r) - az * math.sin(r), ax * math.sin(r) + az * math.cos(r)
				local x, z = cx + hx * dist, cz + hz * dist
				local bx, by, bz = Spring.Pos2BuildPos(wind, x, Spring.GetGroundHeight(x, z), z, 0)
				if not at and screenOf(x, z) and Spring.GetGroundHeight(x, z) > 2
					and Spring.TestBuildOrder(wind, bx, by, bz, 0) >= 2 then
					at = { bx, bz }
				end
			end
		end
		if foe and at then
			-- (the commander on hold fire meanwhile: it shot the wind before the tap, 0 seen, the case never ran; put back
			-- at dgunoff)
			spots.fireWas = Spring.GetUnitStates(com) and Spring.GetUnitStates(com).firestate
			Spring.GiveOrderToUnit(com, CMD.FIRE_STATE, { 0 }, 0)
			Spring.SendCommands(string.format("give 1 corwin %d @%d,%d,%d", foe, at[1], cy, at[2]))
			spots.foeAt, spots.foeTeam = at, foe
		else
			check("an enemy given beside the commander", false, "team " .. tostring(foe) .. ", spot " .. tostring(at ~= nil))
		end
	elseif c == "enemy2" then
		local best, bestD
		local cx, _, cz = Spring.GetUnitPosition(com)
		local seen = Spring.GetUnitsInCylinder(cx, cz, 900, spots.foeTeam) or {}
		local all, near1 = 0, nil
		for _, u in ipairs(Spring.GetAllUnits() or {}) do
			if Spring.GetUnitDefID(u) == UnitDefNames.corwin.id then
				all = all + 1
				local ux, _, uz = Spring.GetUnitPosition(u)
				near1 = ux and string.format("%d,%d team %s", ux, uz, tostring(Spring.GetUnitTeam(u))) or near1
			end
		end
		Spring.Echo(string.format("[fixtest] note: %d units of team %s near the commander (at %d,%d); Cortex winds seen: %d, %s; asked at %d,%d",
			#seen, tostring(spots.foeTeam), cx, cz, all, tostring(near1), spots.foeAt[1], spots.foeAt[2]))
		for _, u in ipairs(seen) do
			if Spring.GetUnitDefID(u) == UnitDefNames.corwin.id then
				local ux, _, uz = Spring.GetUnitPosition(u)
				local d = (ux - spots.foeAt[1]) ^ 2 + (uz - spots.foeAt[2]) ^ 2
				if not bestD or d < bestD then
					best, bestD = u, d
				end
			end
		end
		spots.foe = best
		local ux, _, uz
		if best then
			ux, _, uz = Spring.GetUnitPosition(best)
		end
		local sx, sy
		if ux then
			sx, sy = Spring.WorldToScreenCoords(ux, Spring.GetGroundHeight(ux, uz), uz)
		end
		Spring.Echo(string.format("[fixtest] note: the enemy %s at %s,%s, on the screen %s,%s, in sight %s", tostring(best),
			tostring(ux and math.floor(ux)), tostring(uz and math.floor(uz)), tostring(sx and math.floor(sx)),
			tostring(sy and math.floor(sy)), tostring(ux and screenOf(ux, uz) ~= nil)))
		write(spotLine("foe", ux and { ux, 0, uz }))
	elseif c == "trackaim?" then
		local foe = spots.foe
		local tracked = WG.BarDroidPadDgun and WG.BarDroidPadDgun.tracking and WG.BarDroidPadDgun.tracking()
		local cx, _, cz = Spring.GetUnitPosition(com)
		local ux, _, uz
		if foe then
			ux, _, uz = Spring.GetUnitPosition(foe)
		end
		local ax, az = aimNow()
		local off = 180
		if ux and ax then
			local dx, dz = ux - cx, uz - cz
			local l = math.max(1, math.sqrt(dx * dx + dz * dz))
			off = angleBetween(ax, az, dx / l, dz / l)
		end
		check("a tap on an enemy in the D-gun mode: the aim follows it (2 s on)", tracked == foe
			and foe ~= nil and off <= 15, string.format("following %s (the enemy wind %s), %.0f degrees off",
			tostring(tracked), tostring(foe), off))
		-- (the aim's rings on it, within reach; they stood at the reach beyond it: the in-play tour)
		local Dg = WG.BarDroidPadDgun
		local rx, rz
		if Dg and Dg.ring then
			rx, rz = Dg.ring()
		elseif Dg and Dg.range and WG.BarDroidPad and WG.BarDroidPad.modal then -- (a build before the rings moved: at the
			-- reach on the aim's line)
			local _, _, aimX, aimZ = WG.BarDroidPad.modal()
			if aimX and Dg.range() then
				rx, rz = cx + aimX * Dg.range(), cz + aimZ * Dg.range()
			end
		end
		local ringOff = rx and ux and math.sqrt((rx - ux) ^ 2 + (rz - uz) ^ 2)
		check("... the aim's rings on the enemy, not at the reach beyond it", ringOff ~= nil and ringOff <= 40,
			string.format("%s elmos from it", tostring(ringOff and math.floor(ringOff))))
	elseif c == "tapat" then
		local cx, _, cz = Spring.GetUnitPosition(com)
		local ax, az = aimNow()
		-- (a point to the side of the current aim, at a turn of about 90 degrees, in sight above the dock)
		for _, turn in ipairs({ 90, -90, 135, -135, 45, -45 }) do
			local r = math.rad(turn)
			local hx = ax * math.cos(r) - az * math.sin(r)
			local hz = ax * math.sin(r) + az * math.cos(r)
			for dist = 260, 140, -40 do
				local x, z = cx + hx * dist, cz + hz * dist
				if not tapPoint and screenOf(x, z) then
					tapPoint = { x, 0, z }
				end
			end
		end
		write(spotLine("tap", tapPoint))
	elseif c == "tapaim?" then
		local cx, _, cz = Spring.GetUnitPosition(com)
		local ax, az = aimNow()
		local dx, dz = tapPoint and tapPoint[1] - cx or 0, tapPoint and tapPoint[3] - cz or 0
		local len = math.max(1, math.sqrt(dx * dx + dz * dz))
		local off = ax and angleBetween(ax, az, dx / len, dz / len) or 180
		local Dg = WG.BarDroidPadDgun
		local sel = Spring.GetSelectedUnits()
		local still = Dg and Dg.tracking and Dg.tracking()
		check("a map tap in the D-gun mode: the shot towards it (no enemy followed), the mode on, the commander picked",
			off <= 12 and Dg and Dg.active() and #sel == 1 and sel[1] == com and not still,
			string.format("%.0f degrees off, mode %s, %d picked, following %s", off, tostring(Dg and Dg.active()), #sel,
				tostring(still)))
	elseif c == "dgunoff" then
		P.act("dgun_cancel")
		if spots.fireWas then
			Spring.GiveOrderToUnit(com, CMD.FIRE_STATE, { spots.fireWas }, 0)
		end
	elseif c == "breakmenu" then -- (the app's build menu copy broken on purpose: BAR removes it; RC 0.2.0 item 7)
		local B = WG.bardroidBuildmenu
		spots.menuWas = B
		if B and B.droidBreak then
			B.droidBreak()
		else
			check("the build menu copy can be broken on purpose (droidBreak)", false, "no copy, or no droidBreak")
		end
	elseif c == "menuback?" then
		local B, M = WG.bardroidBuildmenu, WG.buildmenu
		check("the build menu copy removed for its error: BAR's own build menu on in its place (the menu watch)",
			B == nil and M ~= nil and M ~= spots.menuWas, string.format("copy %s, WG.buildmenu %s", tostring(B ~= nil),
				M == nil and "none" or M == spots.menuWas and "the copy's" or "BAR's"))
	elseif c == "end" then
		Spring.Echo("[fixtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
	end
end

local cheated = false
function widget:Update()
	local f = Spring.GetGameFrame()
	if f > 60 and not cheated then -- (the enemy case's give)
		cheated = true
		Spring.SendCommands("cheat 1")
	end
	if f > 0 and not pausedHere and select(3, Spring.GetGameSpeed()) then
		local t = Spring.GetTimer()
		if not unpausedAt or Spring.DiffTimers(t, unpausedAt) > 2 then
			unpausedAt = t
			Spring.SendCommands("pause 0")
		end
	end
	if not ready and f > 300 then
		for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID())) do
			local ud = UnitDefs[Spring.GetUnitDefID(u)]
			if ud and ud.customParams and ud.customParams.iscommander then
				com = u
			end
		end
		if com then
			ready = true
			spots = spots or {}
			Spring.SelectUnitArray({ com })
			Spring.Echo("[fixtest] ready")
		end
	end
	local c = readCmd()
	if c and c ~= lastCmd then
		lastCmd = c
		c = c:gsub(" #%d+$", "") -- (the script's stage number)
		local ok, err = pcall(onCmd, c)
		if not ok then
			check("stage " .. c, false, err)
		end
	end
end
