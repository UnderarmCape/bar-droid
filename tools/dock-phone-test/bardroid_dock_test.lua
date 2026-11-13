-- LuaUI widget for tools/dock-phone-test.ps1: the upright touch dock (bardroid_portrait.lua) driven by real taps on the
-- dev phone (adb input), which this widget sets up for and checks. The script writes a stage into
-- LuaUI/Config/bardroid_docktest_cmd.txt; the widget answers in the log ("[docktest] PASS|FAIL <case>") and writes
-- what the script needs to tap into LuaUI/Config/bardroid_docktest.txt (X screen pixels, top left origin):
--   (frame 320) the commander picked; "tile x0 y0 x1 y1": the build grid's first tile; "free x y", "blocked x y": a spot its building can go, one it cannot
--   placed?   that building queued by the dock's PLACE (picked, its spot tapped, PLACE 2.6 s later)
--   blocked?  PLACE on the blocked spot: the note "CAN'T BUILD THERE: PICK ANOTHER SPOT"
--   dgun      the D-gun mode on the commander;  auto? / autooff?  full auto on / off by FIRE's swipes
--   walk      the commander's speed watched;    stopped?  it walked, and stands still soon after the stick is let go
--   presets   six Pawns given, picked, the presets open; "aim0 x y", "aim1 x y": a drag's ends on open ground
--   strafe?   STRAFE (its thumbnail tapped, its front line drawn): each Pawn one fight to its place, on one line, apart
--   sway?     the Pawns there: each two fights across its place, repeat on
--   pickpanned? (after campos) the Pawns picked, one finger dragged on the game: a pan, no path for them
--   drawdock? their path drawn (a press held, then a drag) on into the dock: its end at the dock's edge, their repeat off
--   panned?   (after campos) one finger dragged on the game, the dock's menu open, nothing picked: a pan, no selection
--   end       "[docktest] done: ALL PASS" or "N FAILED"
function widget:GetInfo()
	return { name = "BAR Droid dock test", desc = "What the touch dock did", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_docktest.txt", "LuaUI/Config/bardroid_docktest_cmd.txt"
local com, ready, fails, lastCmd = nil, false, 0, nil
local buildDef -- (the build grid's first building, in sight on any screen shape: an Armada commander's Solar Collector)
local pawns, maxSpeed = {}, nil
local edge, aimAt -- (the presets' stage: the map's edge the camera looks at, the frame to find the aims at)
local camAt -- (the camera before the pan's drag)
local hideAt, hidden, styleWas, circ -- (the circle's case: where its Pawn behind the dock is given, the Pawn, the style
-- before, the circle's two points in X pixels)

function widget:UnitCreated(unitID, unitDefID, teamID)
	if hideAt and not hidden and teamID == Spring.GetMyTeamID() and unitDefID == UnitDefNames.armpw.id then
		local x, _, z = Spring.GetUnitPosition(unitID)
		if x and math.abs(x - hideAt[1]) + math.abs(z - hideAt[3]) < 64 then
			hidden = unitID
		end
	end
end

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
-- a spot for the building near the commander on the screen: buildable (TestBuildOrder 2 or 3: rocks the builder reclaims, or
-- open ground; the test map is strewn with rocks) or blocked (0)
local function labSpot(want)
	local def = buildDef
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
	if c:match("^spotdock%?") then -- (the picked building dragged on into the dock: its spot at the dock's top edge)
		local y = tonumber(c:match("(%-?%d+)$")) or -1
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local _, vsy = Spring.GetViewGeometry()
		local top = dock and vsy - dock[4] or 0 -- (X pixels from the top, as the place file's spot)
		-- (the spot snaps to the build grid: a few pixels past the edge it was held at; unheld it was the dock's middle)
		check("the building dragged on into the dock: its spot at the dock's top edge, in sight", y >= 0 and y < top + 40,
			string.format("spot y %d, the dock's top %d", y, top))
	elseif c == "deselect" or c == "deselect-again" then
		Spring.SelectUnitArray({})
	elseif c == "circle" then -- (a Pawn given just behind the dock's top edge; nothing picked; the circle style; where
		-- to draw the circle: its middle just above the edge, its edge at the dock's middle)
		local Pt = WG.BarDroidPortrait
		local dock = Pt.dock()
		local vsx, vsy = Spring.GetViewGeometry()
		local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), dock[4] - 80, true)
		if pos then
			hideAt = pos
			Spring.SendCommands(string.format("give 1 armpw %d @%d,%d,%d", Spring.GetMyTeamID(), pos[1], pos[2], pos[3]))
		end
		Spring.SelectUnitArray({})
		styleWas = Pt.selectStyle()
		Pt.selectStyle("circle")
		circ = { math.floor(vsx / 2), vsy - (dock[4] + 60), math.floor(vsx / 2), vsy - math.floor((dock[2] + dock[4]) / 2) }
		write(string.format("circle0 %d %d\ncircle1 %d %d\n", circ[1], circ[2], circ[3], circ[4]))
		Spring.Echo("[docktest] circle: a Pawn behind the dock at " .. tostring(pos and math.floor(pos[1])) .. ","
			.. tostring(pos and math.floor(pos[3])) .. ", the style was " .. tostring(styleWas))
	elseif c == "circledock?" then -- (the circle drawn on into the dock: the Pawn it hides not picked)
		local picked = false
		for _, u in ipairs(Spring.GetSelectedUnits() or {}) do
			picked = picked or u == hidden
		end
		-- (the Pawn inside the circle as the dock makes it, circleTo: its middle on the ground, its radius the ground
		-- across as many pixels; else the case proves nothing)
		local vsx, vsy = Spring.GetViewGeometry()
		local inside = false
		if circ and hidden then
			local r = math.sqrt((circ[3] - circ[1]) ^ 2 + (circ[4] - circ[2]) ^ 2)
			local _, a = Spring.TraceScreenRay(circ[1], vsy - circ[2], true)
			local _, b = Spring.TraceScreenRay(math.min(vsx - 1, circ[1] + r), vsy - circ[2], true)
			local hx, _, hz = Spring.GetUnitPosition(hidden)
			if a and b and hx then
				inside = math.sqrt((hx - a[1]) ^ 2 + (hz - a[3]) ^ 2) <= math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
			end
		end
		check("a circle selection drawn on into the dock: the unit it hides (inside the circle) not picked",
			hidden ~= nil and inside and not picked, string.format("hidden Pawn %s, inside %s, picked %s, %d picked",
				tostring(hidden), tostring(inside), tostring(picked), Spring.GetSelectedUnitsCount()))
		WG.BarDroidPortrait.selectStyle(styleWas or "box")
	elseif c == "campos" then -- (the camera before a one-finger drag on the game)
		camAt = { Spring.GetCameraPosition() }
	elseif c == "panned?" then -- (the dock's menu open, nothing picked: the drag panned, nothing selected)
		local x, _, z = Spring.GetCameraPosition()
		local moved = camAt and math.sqrt((x - camAt[1]) ^ 2 + (z - camAt[3]) ^ 2) or 0
		local n = Spring.GetSelectedUnitsCount()
		check("one finger dragged on the game with the dock's menu open, nothing picked: it pans, nothing selected",
			moved > 30 and n == 0, string.format("camera moved %.0f, %d picked", moved, n))
	elseif c == "pickpanned?" then -- (the Pawns picked, one finger dragged on the game: a pan, no path for them; Kailil,
		-- 2026-11-13: "Pan, hold for paths")
		local x, _, z = Spring.GetCameraPosition()
		local moved = camAt and math.sqrt((x - camAt[1]) ^ 2 + (z - camAt[3]) ^ 2) or 0
		local moves = 0
		for _, u in ipairs(pawns) do
			local cmd = (Spring.GetUnitCommands(u, 1) or {})[1]
			moves = moves + (cmd and cmd.id == CMD.MOVE and 1 or 0)
		end
		local n = Spring.GetSelectedUnitsCount()
		check("units picked, one finger dragged on the game: it pans, no path drawn", moved > 30 and moves == 0 and n > 0,
			string.format("camera moved %.0f, %d moves, %d picked", moved, moves, n))
	elseif c == "boxdock?" then -- (a box selection dragged on into the dock: let go at the dock's top edge)
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local top = dock and dock[4] or 0
		local _, my = Spring.GetMouseState()
		check("a box selection dragged on into the dock: let go at the dock's top edge, the box in sight", my >= top - 2,
			string.format("let go at y %d, the dock's top %d, %d picked", my, top, Spring.GetSelectedUnitsCount()))
	elseif c == "griddock?" then -- (a GRID dragged on into the dock: its far corner, the pointer, at the dock's top edge)
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local top = dock and dock[4] or 0
		local _, my, held = Spring.GetMouseState()
		check("a GRID dragged on into the dock: its far corner held at the dock's top edge, in sight",
			held and my >= top - 2, string.format("button %s, corner y %d, the dock's top %d", tostring(held), my, top))
	elseif c == "placed?" then
		local found, words = false, {}
		for _, cmd in ipairs(Spring.GetUnitCommands(com, 20) or {}) do
			found = found or cmd.id == -buildDef
			words[#words + 1] = cmd.id < 0 and UnitDefs[-cmd.id] and UnitDefs[-cmd.id].name or tostring(cmd.id)
		end
		local _, _, _, active = Spring.GetActiveCommand()
		check("a building picked on the dock, its spot tapped, PLACE 2.6 s later: queued at once", found,
			"queue [" .. table.concat(words, " ") .. "], picked " .. tostring(active))
	elseif c == "blocked?" then
		local _, note = P.note()
		check("PLACE on a blocked spot says so", note == "CAN'T BUILD THERE: PICK ANOTHER SPOT", note)
	elseif c == "cancelled?" then -- (upright PLACE is the whole panel around rotate and cancel: cancel must not place)
		local _, cmd = Spring.GetActiveCommand()
		local queued = 0
		for _, q in ipairs(Spring.GetUnitCommands(com, 20) or {}) do
			queued = queued + (q.id == -buildDef and 1 or 0)
		end
		check("the panel's cancel puts the building away, nothing placed", not (cmd and cmd < 0) and queued <= 1,
			"picked " .. tostring(cmd) .. ", queued " .. queued)
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
	elseif c == "dockback?" then -- (STRAFE picked, the drag lifted over the dock: nothing sent, still armed)
		local fights = 0
		for _, u in ipairs(pawns) do
			for _, cmd in ipairs(Spring.GetUnitCommands(u, 5) or {}) do
				fights = fights + (cmd.id == CMD.FIGHT and 1 or 0)
			end
		end
		local armed = WG.BarDroidPresets and WG.BarDroidPresets.armed()
		check("STRAFE's drag lifted over the dock: not sent, the preset still armed", fights == 0 and armed == true,
			string.format("%d fights, armed %s", fights, tostring(armed)))
		-- (that drag panned the camera, a finger's drag with a preset armed since 2026-11-13: back where the aims were
		-- found, so the next tap's point is on the ground again)
		if edge then
			Spring.SetCameraTarget(edge[1], Spring.GetGroundHeight(edge[1], edge[2]), edge[2], 0)
		end
	elseif c == "drawdock?" then -- (the Pawns' path drawn from the map on into the dock: its end at the dock's edge)
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local top = dock and dock[4] or 0
		local n, lowest, ys = 0, nil, {}
		for _, u in ipairs(pawns) do
			local cmd = (Spring.GetUnitCommands(u, 1) or {})[1]
			if cmd and cmd.id == CMD.MOVE and cmd.params[3] then
				local sx, sy = Spring.WorldToScreenCoords(cmd.params[1], cmd.params[2], cmd.params[3])
				n = n + 1
				lowest = lowest and math.min(lowest, sy) or sy
				ys[#ys + 1] = string.format("%d,%d", sx, sy)
			end
		end
		-- (where the drag let go: at the dock's top edge, not deep in it; BAR's formation lengthens a line too short for
		-- the units' spacing past its end, so goals may lie a little beyond it)
		local _, my = Spring.GetMouseState()
		Spring.Echo("[docktest] the drawn path's goals (GL x,y): " .. table.concat(ys, " "))
		check("a path drawn on into the dock: let go at the dock's top edge, the path in sight", n > 0 and my >= top - 2,
			string.format("%d moves, let go at y %d, the dock's top %d, lowest goal y %s", n, my, top,
				tostring(lowest and math.floor(lowest))))
		-- (the Pawns were going side to side on the preset's repeat: the player's own order ends it, or the path ran
		-- round and round)
		local rep = {}
		for _, u in ipairs(pawns) do
			local st = Spring.GetUnitStates(u)
			if st then
				rep[#rep + 1] = st["repeat"] and "R" or "-"
			end
		end
		local on = table.concat(rep):find("R") ~= nil
		check("the path given to the Pawns on the preset's repeat: their repeat off", #rep > 0 and not on, table.concat(rep, " "))
	elseif c == "strafe?" then -- (a tap sent it, taps only since 2026-11-13: each Pawn one fight to its place, no
		-- repeat yet, or already there; the places in rows abreast (80 elmos apart when more than a row), the front row
		-- at the tap, a Pawn's width or more apart; a drawn line's width only with a mouse)
		local Pr = WG.BarDroidPresets
		local pl = Pr and Pr.lastPlan and Pr.lastPlan()
		local ok, words, rows = #pawns > 0 and pl ~= nil, {}, {}
		for _, u in ipairs(pawns) do
			local q = Spring.GetUnitCommands(u, 5) or {}
			local st = Spring.GetUnitStates(u) or {}
			local s = pl and pl.slots[u]
			local fights, onIt = 0, false
			for _, cmd in ipairs(q) do
				if cmd.id == CMD.FIGHT then
					fights = fights + 1
					onIt = s and cmd.params[3] and math.abs(cmd.params[1] - s[1]) + math.abs(cmd.params[3] - s[2]) < 4
				end
			end
			if fights == 0 and s then -- (a Pawn that started next to its place may be there already)
				local x, _, z = Spring.GetUnitPosition(u)
				onIt = x and (x - s[1]) ^ 2 + (z - s[2]) ^ 2 < 160 * 160
			end
			ok = ok and s ~= nil and fights <= 1 and onIt and st["repeat"] == false
			words[#words + 1] = fights .. (st["repeat"] and "R" or "") .. (onIt and "" or "?")
			if s then
				local key = string.format("%.0f", s[3])
				rows[key] = rows[key] or {}
				table.insert(rows[key], s[4])
			end
		end
		local n, near, front = 0, math.huge, false
		for key, across in pairs(rows) do
			n = n + 1
			front = front or tonumber(key) == 0
			ok = ok and tonumber(key) % 80 == 0
			table.sort(across)
			for i = 2, #across do
				near = math.min(near, across[i] - across[i - 1])
			end
			if pl and pl.W and #across > 1 and tonumber(key) == 0 then -- (the front row spread over the line's length)
				ok = ok and math.abs(across[#across] - across[1] - pl.W) < 2
			end
		end
		ok = ok and front and near >= 30
		check("STRAFE picked, the map tapped: each Pawn one fight to its place, rows abreast, apart, no repeat",
			ok, string.format("%s; %d rows, nearest two %.0f apart", table.concat(words, " "), n,
				near == math.huge and -1 or near))
	elseif c == "sway?" then -- (once they were there: each Pawn two fights across its place, repeat on: 2 x SIDE, or
		-- less where the map's edge cuts one end)
		local Pr = WG.BarDroidPresets
		local pl = Pr and Pr.lastPlan and Pr.lastPlan()
		local side = Pr and Pr.side or 150
		local ok, words = #pawns > 0 and pl ~= nil, {}
		local function onMap(v, size)
			return math.max(32, math.min(size - 32, v))
		end
		for _, u in ipairs(pawns) do
			local q = Spring.GetUnitCommands(u, 5) or {}
			local st = Spring.GetUnitStates(u) or {}
			local s = pl and pl.slots[u]
			local f = {}
			for _, cmd in ipairs(q) do
				if cmd.id == CMD.FIGHT and cmd.params[3] then
					f[#f + 1] = cmd.params
				end
			end
			local span = #f == 2 and math.sqrt((f[1][1] - f[2][1]) ^ 2 + (f[1][3] - f[2][3]) ^ 2) or 0
			local want = 0
			if s then
				local ax, az = onMap(s[1] + pl.px * side, Game.mapSizeX), onMap(s[2] + pl.pz * side, Game.mapSizeZ)
				local bx, bz = onMap(s[1] - pl.px * side, Game.mapSizeX), onMap(s[2] - pl.pz * side, Game.mapSizeZ)
				want = math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
			end
			ok = ok and #f == 2 and st["repeat"] == true and math.abs(span - want) < 4
			words[#words + 1] = string.format("%d%s/%.0f", #f, st["repeat"] and "R" or "", span)
		end
		check(string.format("STRAFE: the Pawns there, each fights side to side across its place on repeat (%d elmos)",
			2 * side), ok, table.concat(words, " "))
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
	if com and f == 290 then
		Spring.SelectUnitArray({ com }) -- (the dock's lists filled a few frames on: read at 320)
	end
	if com and not ready and f >= 320 then
		ready = true
		local vsy = select(2, Spring.GetViewGeometry())
		local P = WG.BarDroidPortrait
		local cell, item = P.itemCell("left", function(it)
			return it.kind == "build"
		end)
		buildDef = item and item.defID or UnitDefNames.armlab.id
		local fx, fy = labSpot("free")
		local bx, by = labSpot("blocked")
		write(string.format("free %s %s\nblocked %s %s\ntile %d %d %d %d\n", tostring(fx), tostring(fy), tostring(bx),
			tostring(by), cell and cell[1] or 0, cell and vsy - cell[4] or 0, cell and cell[3] or 0, cell and vsy - cell[2] or 0))
		Spring.Echo("[docktest] the building: " .. tostring(UnitDefs[buildDef] and UnitDefs[buildDef].name))
		Spring.Echo(string.format("[docktest] ready: free %s,%s blocked %s,%s", tostring(fx), tostring(fy), tostring(bx),
			tostring(by)))
	end
	if #pawns == 0 and lastCmd == "presets" then -- (the given Pawns, picked once they are there; the presets opened)
		local list = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), UnitDefNames.armpw.id) or {}
		if #list >= 6 then
			pawns = list
			Spring.SelectUnitArray(pawns)
			WG.BarDroidPresets.open()
			-- the camera 350 elmos inside the map's edge nearest the commander (the west, east or north edge: the south
			-- one shows under the dock), so the void past it shows above the dock (the drag starts there)
			local x, _, z = Spring.GetUnitPosition(com)
			local mx, IN = Game.mapSizeX, 350
			local d = math.min(x, z, mx - x)
			edge = { d == x and IN or d == mx - x and mx - IN or x, d == z and IN or z }
			Spring.SetCameraTarget(edge[1], Spring.GetGroundHeight(edge[1], edge[2]), edge[2], 0)
			aimAt = f + 45
		end
	end
	if aimAt and f >= aimAt then -- (the aims once the camera is there)
		aimAt = nil
		do
			-- the game between the dock and the top bar on a grid: spots over the ground and over no ground (the void
			-- past the map's edge); the drag starts at the lowest void spot when there is one (the aim begins once the
			-- finger reaches the ground), goes to the ground spot nearest it (aim0), then to one 200+ px on (aim1)
			local vsx, vsy = Spring.GetViewGeometry()
			local D = WG.BarDroidPortrait
			local dock = D and D.dock and D.dock()
			local vx, vy
			local grounds = {}
			for gy = (dock and dock[4] or 0) + 80, vsy - 200, 16 do
				for gx = 80, vsx - 80, 32 do
					local kind, pos = Spring.TraceScreenRay(gx, gy, true, false)
					if not kind and not vx then
						vx, vy = gx, vsy - gy
					elseif kind == "ground" and pos and pos[1] > 64 and pos[3] > 64 and pos[1] < Game.mapSizeX - 64
						and pos[3] < Game.mapSizeZ - 64 then
						grounds[#grounds + 1] = { gx, vsy - gy }
					end
				end
			end
			local function dist(p, x, y)
				return math.abs(p[1] - x) + math.abs(p[2] - y)
			end
			local ox, oy = vx or vsx / 2, vy or vsy / 2
			table.sort(grounds, function(p, q)
				return dist(p, ox, oy) < dist(q, ox, oy)
			end)
			local a0 = grounds[math.min(#grounds, vx and 3 or 1)] -- (a little way off the edge)
			local ax, ay, bx2, by2 = a0 and a0[1], a0 and a0[2], nil, nil
			for _, p in ipairs(grounds) do -- (the drag a front line for the presets: 400+ px on where there is room)
				if a0 and dist(p, ax, ay) > (bx2 and dist({ bx2, by2 }, ax, ay) or 200) and dist(p, ax, ay) < 700 then
					bx2, by2 = p[1], p[2]
				end
			end
			Spring.Echo(string.format("[docktest] camera on the map's edge at %d,%d: %d ground spots on the grid",
				edge[1], edge[2], #grounds))
			write(string.format("aim0 %s %s\naim1 %s %s\nvoid %s %s\n", tostring(ax), tostring(ay), tostring(bx2),
				tostring(by2), tostring(vx), tostring(vy)))
			Spring.Echo(string.format("[docktest] presets open: %d Pawns, aim %s,%s to %s,%s, void %s,%s", #pawns,
				tostring(ax), tostring(ay), tostring(bx2), tostring(by2), tostring(vx), tostring(vy)))
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
