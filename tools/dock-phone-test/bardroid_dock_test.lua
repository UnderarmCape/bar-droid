-- LuaUI widget for tools/dock-phone-test.ps1: the upright touch dock (bardroid_portrait.lua) driven by real taps on the
-- dev phone (adb input), which this widget sets up for and checks. The script writes a stage into
-- LuaUI/Config/bardroid_docktest_cmd.txt; the widget answers in the log ("[docktest] PASS|FAIL <case>") and writes
-- what the script needs to tap into LuaUI/Config/bardroid_docktest.txt (X screen pixels, top left origin):
--   (frame 320) the commander picked; "tile x0 y0 x1 y1": the build grid's first tile; "free x y", "blocked x y": a spot its building can go, one it cannot
--   placed?   that building queued by the dock's PLACE (picked, its spot tapped, PLACE 2.6 s later)
--   blocked?  PLACE on the blocked spot: the note "CAN'T BUILD THERE: PICK ANOTHER SPOT"
--   dgun      the D-gun mode on the commander;  auto? / autooff?  full auto on / off by FIRE's swipes
--   walk      the commander's speed watched;    stopped?  it walked, and stands still soon after the stick is let go
--   xoff?     the mode's X tapped: the D-gun mode off
--   shapecells the building picked again: "line ...", "border ...": the dock's LINE and BORDER cells
--   linehold? / borderhold?  LINE / BORDER, a press held on the map, a drag: the shape held, the building still picked
--   lineplaced? / borderplaced?  PLACE: 2+ / 3+ buildings queued;  stopcom  the commander's queue cleared
--   backhome? / quitshown? / quitclosed?  Android's Back: the building put away, the home grid; BAR's quit question; closed
--   quitbtn   "quitbtn x y": BAR's Quit on its top bar;  quitbtnshown? / quitbtnclosed?  tapped: the question; Back: closed
--   presetsback, backpresets?  the Pawns picked, the presets open; Back: closed, nothing picked
--   presets   six Pawns given, picked, the presets open; "aim0 x y", "aim1 x y": a drag's ends on open ground
--   strafe?   STRAFE (its thumbnail tapped, its front line drawn): each Pawn one fight to its place, on one line, apart
--   sway?     the Pawns there: each two fights across its place, repeat on
--   pickpanned? (after campos) the Pawns picked, one finger dragged on the game: a pan, no path for them
--   drawdock? their path drawn (a press held, then a drag) on into the dock: its end at the dock's edge, their repeat off
--   panned?   (after campos) one finger dragged on the game, the dock's menu open, nothing picked: a pan, no selection
--   areamex / areamexpick / areamexarm  two Construction Bots given, picked, Area Mex armed; "mex0 x y", "mex1 x y": a
--             metal spot in sight and a point 90 px on;  areamex?  a tap, then a drag between them: mexes queued
--   resrects  "metal ...", "energy ...": the resource boxes;  slider  "bar ...": the energy panel's bar's cell;
--             slider?  its share knob dragged to about 40 %: a whole percent, the conversion knob left alone
--   sendbtn   stand-in teammates; "send ...": SEND ENERGY's cell;  picker?  its picker's rows in sight all whole
--   end      "[docktest] done: ALL PASS" or "N FAILED"
function widget:GetInfo()
	return { name = "BAR Droid dock test", desc = "What the touch dock did", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_docktest.txt", "LuaUI/Config/bardroid_docktest_cmd.txt"
local com, ready, fails, lastCmd = nil, false, 0, nil
local buildDef -- (the build grid's first building, in sight on any screen shape: an Armada commander's Solar Collector)
local pawns, maxSpeed = {}, nil
local edge, aimAt -- (the presets' stage: the map's edge the camera looks at, the frame to find the aims at)
local camAt -- (the camera before the pan's drag)
local mexSpot -- (the Area Mex case's metal spot)
local shapeQueued -- (the commander's queued buildings before a held LINE or BORDER's PLACE)
local realTeammates -- (the pad's teammate list, while stand-ins fill the picker: sendbtn, picker?)
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
	-- (nor on the camera knob or an edge rail, bardroid_camctl.lua, with a margin: a tap there is the camera's; Area Mex's
	-- spot under the knob queued no mex, 2026-11-19)
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
		-- (the camera controls' rects in the detail: the turn rail stands just above the dock, where the spot is held)
		local C = WG.BarDroidCamCtl
		local k, z, t = nil, nil, nil
		if C and C.rects then
			k, z, t = C.rects()
		end
		local function r(v)
			return v and table.concat(v, ",") or "-"
		end
		check("the building dragged on into the dock: its spot at the dock's top edge, in sight", y >= 0 and y < top + 40,
			string.format("spot y %d, the dock's top %d; dock %s, knob %s, zoom %s, turn %s (GL)", y, top, r(dock), r(k),
				r(z), r(t)))
	elseif c == "deselect" or c == "deselect-again" then
		Spring.SelectUnitArray({})
	elseif c == "circlecam" then -- (the circle's camera: up to 700 elmos towards the map's middle across, put back after
		-- the case; the earlier cases leave it by the map's edge, and off the turn rail the circle's start, the screen's
		-- left, lay past the edge, no ground for the Pawn; dev phone, 2026-11-23)
		local vsx, vsy = Spring.GetViewGeometry()
		circ = { camWas = Spring.GetCameraState() }
		local _, p = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2), true)
		if p then
			local nx = p[1] + math.max(-700, math.min(700, Game.mapSizeX / 2 - p[1]))
			Spring.SetCameraTarget(nx, Spring.GetGroundHeight(nx, p[3]), p[3], 0)
		end
	elseif c == "circle" then -- (a Pawn given just behind the dock's top edge; nothing picked; the circle style; where
		-- to draw the circle: its middle just above the edge, its edge at the dock's middle)
		local Pt = WG.BarDroidPortrait
		local dock = Pt.dock()
		local vsx, vsy = Spring.GetViewGeometry()
		-- (behind the dock: in the split the screen's middle is the game between the blocks, where a circle picks units,
		-- 2026-11-16: the right block's middle there)
		local hx = math.floor(vsx / 2)
		if Pt.onDock and not Pt.onDock(hx, dock[4] - 80) then
			local a, b
			for x = hx, vsx - 1, 4 do
				local on = Pt.onDock(x, dock[4] - 80)
				if on and not a then
					a = x
				elseif a and not on then
					b = x - 4
					break
				end
			end
			if a then
				hx = math.floor((a + (b or vsx - 1)) / 2)
			end
		end
		-- (the circle's start off the one-finger camera's knob and rails: the turn rail lies just above the dock from the
		-- screen's middle out, and the touch that came down on its edge was the camera's, the dock drew no circle, every
		-- run since the rails, 2026-11-19; dev phone, 2026-11-23. The middle of the longest stretch of that line clear of
		-- them, the Pawn behind the dock there)
		local C = WG.BarDroidCamCtl
		local kn, zr, tr
		if C and C.rects then
			kn, zr, tr = C.rects()
		end
		local yc, M = dock[4] + 60, 32
		local function clear(x)
			for _, r in ipairs({ zr or false, tr or false }) do
				if r and x >= r[1] - M and x <= r[3] + M and yc >= r[2] - M and yc <= r[4] + M then
					return false
				end
			end
			if kn and math.sqrt((x - kn[1]) ^ 2 + (yc - kn[2]) ^ 2) <= kn[3] + M then
				return false
			end
			if Pt.onDock and not Pt.onDock(x, dock[4] - 80) then
				return false
			end
			-- (ground under the circle's start and under the Pawn's place)
			local _, g1 = Spring.TraceScreenRay(x, yc, true)
			local _, g2 = Spring.TraceScreenRay(x, dock[4] - 80, true)
			return g1 ~= nil and g2 ~= nil
		end
		if not clear(hx) then
			local best, from = 0, nil
			for x = M, vsx - M, 4 do
				if clear(x) then
					from = from or x
					if x - from > best then
						best, hx = x - from, math.floor((from + x) / 2)
					end
				else
					from = nil
				end
			end
		end
		local _, pos = Spring.TraceScreenRay(hx, dock[4] - 80, true)
		if pos then
			hideAt = pos
			Spring.SendCommands(string.format("give 1 armpw %d @%d,%d,%d", Spring.GetMyTeamID(), pos[1], pos[2], pos[3]))
		end
		Spring.SelectUnitArray({})
		styleWas = Pt.selectStyle()
		Pt.selectStyle("circle")
		local camWas = circ and circ.camWas
		circ = { hx, vsy - (dock[4] + 60), hx, vsy - math.floor((dock[2] + dock[4]) / 2) }
		circ.cam, circ.top, circ.camWas = { Spring.GetCameraPosition() }, dock[4], camWas -- (the check's detail: what moved since)
		write(string.format("circle0 %d %d\ncircle1 %d %d\n", circ[1], circ[2], circ[3], circ[4]))
		Spring.Echo("[docktest] circle: a Pawn behind the dock at " .. tostring(pos and math.floor(pos[1])) .. ","
			.. tostring(pos and math.floor(pos[3])) .. ", the style was " .. tostring(styleWas) .. "; the circle's start "
			.. hx .. "," .. yc .. " (GL), the turn rail " .. (tr and table.concat(tr, ",") or "none"))
	elseif c:match("^circledock%?") then -- (the circle drawn on into the dock: the Pawn it hides not picked; the number:
		-- the dock's circle picks since the drag began, from the infolog: none, and no circle was drawn)
		local picks = tonumber(c:match("(%d+)$")) or 0
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
		-- (what moved since the Pawn was given: the Pawn itself, pushed by my other units, the camera, the dock's top;
		-- the ccb4f0cc train picked it once, 2026-11-22, the rerun not)
		local why = ""
		if circ and circ.cam and hidden and hideAt then
			local hx, hy, hz = Spring.GetUnitPosition(hidden)
			local Pt = WG.BarDroidPortrait
			local dock = Pt and Pt.dock and Pt.dock()
			local cx, _, cz = Spring.GetCameraPosition()
			local near, nearMoving = nil, 0
			if hx then
				for _, u in ipairs(Spring.GetUnitsInCylinder(hx, hz, 160, Spring.GetMyTeamID()) or {}) do
					if u ~= hidden then
						local ux, _, uz = Spring.GetUnitPosition(u)
						local d = math.sqrt((ux - hx) ^ 2 + (uz - hz) ^ 2)
						near = near and math.min(near, d) or d
						nearMoving = nearMoving + (speedOf(u) > 4 and 1 or 0)
					end
				end
			end
			local _, sy = Spring.WorldToScreenCoords(hx or 0, hy or 0, hz or 0)
			why = string.format("; the Pawn moved %d elmos since given, at y %d (the dock's top %d, %d when given); the "
				.. "camera moved %d; my other units within 160: nearest %s, %d moving", hx and math.floor(math.sqrt((hx
				- hideAt[1]) ^ 2 + (hz - hideAt[3]) ^ 2)) or -1, math.floor(sy), dock and dock[4] or -1, circ.top,
				math.floor(math.sqrt((cx - circ.cam[1]) ^ 2 + (cz - circ.cam[3]) ^ 2)), near and math.floor(near) or "none",
				nearMoving)
		end
		check("a circle selection drawn on into the dock: the dock's circle, the unit it hides (inside it) not picked",
			hidden ~= nil and inside and picks > 0 and not picked, string.format("%d circle picks, hidden Pawn %s, inside "
				.. "%s, picked %s, %d picked%s", picks, tostring(hidden), tostring(inside), tostring(picked),
				Spring.GetSelectedUnitsCount(), why))
		WG.BarDroidPortrait.selectStyle(styleWas or "box")
		if circ and circ.camWas then -- (the camera back for the cases after)
			Spring.SetCameraState(circ.camWas, 0)
		end
	elseif c:match("^pathend") then -- (the drawn path's end: the first of the script's columns with ground on the line
		-- just above the dock, where RtsTouch holds the end: the camera at the map's edge, panned since the aims, had it
		-- over no ground once, and the path gave no order; dev phone, the split dock at 1080x1198, 2026-11-15)
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local top = (dock and dock[4] or 0) + 3
		local pick
		for xs in c:gmatch("(%-?%d+)") do
			local x = tonumber(xs)
			local kind, pos = Spring.TraceScreenRay(x, top, true, false)
			if not pick and kind == "ground" and pos and pos[1] > 64 and pos[3] > 64 and pos[1] < Game.mapSizeX - 64
				and pos[3] < Game.mapSizeZ - 64 then
				pick = x
			end
		end
		write(string.format("pathend %s 0\n", tostring(pick)))
		Spring.Echo("[docktest] the path's end column: " .. tostring(pick))
	elseif c:match("^pathstart") then -- (the drawn path's start, X screen pixels, y down: the aim point the script names if
		-- there is ground under it, else the first point up the screen from it, then up the game's middle, that has: the
		-- pan just before moved the camera, and when it moved far the aim point lay past the map's edge, no path and no
		-- order; dev phone at 1080x1198, 2026-11-15, 2 runs in 3)
		local vsx, vsy = Spring.GetViewGeometry()
		local ax, ay = c:match("^pathstart (%-?%d+) (%-?%d+)")
		ax, ay = tonumber(ax), tonumber(ay)
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local top = dock and dock[4] or 0
		local cands = {}
		if ax and ay then
			for i = 0, 8 do
				cands[#cands + 1] = { ax, ay - i * 60 }
			end
		end
		for i = 2, 8 do
			cands[#cands + 1] = { math.floor(vsx / 2), math.floor((vsy - top) * i / 10) }
		end
		local pick
		for _, p in ipairs(cands) do
			local gy = vsy - p[2]
			if not pick and p[2] > 0 and gy > top + 40 then
				local kind, pos = Spring.TraceScreenRay(p[1], gy, true, false)
				if kind == "ground" and pos and pos[1] > 64 and pos[3] > 64 and pos[1] < Game.mapSizeX - 64
					and pos[3] < Game.mapSizeZ - 64 then
					pick = p
				end
			end
		end
		write(pick and string.format("pathstart %d %d\n", pick[1], pick[2]) or "pathstart nil nil\n")
		Spring.Echo("[docktest] the path's start: " .. (pick and (pick[1] .. "," .. pick[2]) or "none"))
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
	elseif c == "shapecells" then -- (the building picked again: LINE's and BORDER's cells on the dock, the queue so far)
		local Pt = WG.BarDroidPortrait
		local _, vsy = Spring.GetViewGeometry()
		local text = ""
		for _, s in ipairs({ "line", "border" }) do
			local r = Pt and Pt.itemCell and Pt.itemCell("right", function(it)
				return it.kind == "shape" and it.shape == s
			end)
			if r and r[3] > 0 then
				text = text .. string.format("%s %d %d %d %d\n", s, r[1], vsy - r[4], r[3], vsy - r[2])
			end
		end
		write(text)
		shapeQueued = 0
		for _, q in ipairs(Spring.GetUnitCommands(com, 50) or {}) do
			shapeQueued = shapeQueued + (q.id == -buildDef and 1 or 0)
		end
		Spring.Echo("[docktest] shape cells: " .. text:gsub("\n", "; ") .. " queued before " .. shapeQueued)
	elseif c == "linehold?" or c == "borderhold?" then -- (LINE / BORDER picked, a press held on the map, then a drag:
		-- the shape held from there, the building still picked; it was a right click, the building put away; Kailil,
		-- 2026-11-20)
		local _, cmd = Spring.GetActiveCommand()
		local _, _, held = Spring.GetMouseState()
		check(c == "linehold?" and "LINE picked, a press held on the map and dragged: the line held, the building still picked"
			or "BORDER picked, a press held on the map and dragged: the border held, the building still picked",
			cmd == -buildDef and held, "picked " .. tostring(cmd) .. ", button " .. tostring(held))
	elseif c == "lineplaced?" or c == "borderplaced?" then -- (PLACE: the shape's buildings queued, several)
		local n = 0
		for _, q in ipairs(Spring.GetUnitCommands(com, 50) or {}) do
			n = n + (q.id == -buildDef and 1 or 0)
		end
		local want = c == "lineplaced?" and 2 or 3
		check(c == "lineplaced?" and "the held LINE's PLACE: a line of buildings queued"
			or "the held BORDER's PLACE: a ring of buildings queued", n - (shapeQueued or 0) >= want,
			string.format("%d queued, %d before", n, shapeQueued or 0))
		shapeQueued = n
	elseif c == "backhome?" then -- (Android's Back with a building picked: put away, nothing picked, the home grid,
		-- whose "back" line names BAR's quit button; Kailil, 2026-11-20)
		local _, cmd = Spring.GetActiveCommand()
		local n = Spring.GetSelectedUnitsCount()
		local f = io.open("LuaUI/Config/bardroid_dock.txt", "r")
		local text = f and f:read("*a") or ""
		if f then
			f:close()
		end
		check("Back with a building picked: put away, nothing picked, the dock's home grid (BAR's quit question next)",
			not cmd and n == 0 and text:find("\nback quit", 1, true) ~= nil,
			string.format("picked %s, %d units, back line %s", tostring(cmd), n, tostring(text:find("\nback quit", 1, true) ~= nil)))
	elseif c == "quitshown?" then -- (Back again at home: BAR's top bar quit button, its quit question)
		local tb = WG.topbar
		local q = tb and tb.showingQuit and tb.showingQuit()
		check("Back at the home grid: BAR's leave-battle question", q and true or false, "showing " .. tostring(q))
	elseif c == "quitbtn" then -- (BAR's own Quit on its top bar, for a finger's tap: its middle, found along the strip)
		local tb = WG.topbar
		local pos = tb and tb.GetButtonsPosition and tb.GetButtonsPosition()
		local vsy = select(2, Spring.GetViewGeometry())
		local qx0, qx1, qy
		if pos and tb.buttonAt then
			qy = math.floor((pos[2] + pos[4]) / 2)
			for x = math.floor(pos[1]), math.floor(pos[3]), 4 do
				if tb.buttonAt(x, qy) == "quit" then
					qx0, qx1 = qx0 or x, x
				end
			end
		end
		write(qx0 and string.format("quitbtn %d %d\n", (qx0 + qx1) / 2, vsy - qy) or "quitbtn nil nil\n")
		-- (over BAR's hidden resource bars or not: there the app's top bar hands the press to BAR's buttons, elsewhere
		-- BAR's buttons take it themselves)
		local free = tb and tb.GetFreeArea and tb.GetFreeArea()
		Spring.Echo(string.format("[docktest] (BAR's Quit at x %s-%s; BAR's hidden top bar to x %s)", tostring(qx0),
			tostring(qx1), tostring(free and free[1])))
	elseif c == "quitbtnshown?" then -- (BAR's Quit tapped in a game not from the lobby: its quit question, 2026-11-20)
		local tb = WG.topbar
		local q = tb and tb.showingQuit and tb.showingQuit()
		check("BAR's Quit tapped upright (a game not from the lobby): its leave-battle question", q and true or false,
			"showing " .. tostring(q))
	elseif c == "quitclosed?" or c == "quitbtnclosed?" then -- (Back again: the question closed, Escape's hideWindows)
		local tb = WG.topbar
		local q = tb and tb.showingQuit and tb.showingQuit()
		check("Back with BAR's quit question up: it closes, the game goes on", not q, "showing " .. tostring(q))
		if q and tb.hideWindows then -- (the rest of the test needs the game)
			tb.hideWindows()
		end
	elseif c == "linespot" then -- (a line's two ends on open ground, every spot of it buildable, in sight above the dock:
		-- "lspot x0 y0 x1 y1"; from the free spot sideways it ran over the crater's rim on Starwatcher and BAR placed none,
		-- 4 runs on 2026-11-22)
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local _, vsy = Spring.GetViewGeometry()
		local top = dock and (vsy - dock[4]) or vsy -- (X pixels from the top)
		local cx, _, cz = Spring.GetUnitPosition(com)
		local found
		for r = 250, 1400, 50 do
			for a = 0, 345, 15 do
				if not found then
					local mx, mz = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
					local ok, ends = true, {}
					for o = -160, 160, 40 do
						local x, z = mx + o, mz
						local bx, by, bz = Spring.Pos2BuildPos(buildDef, x, Spring.GetGroundHeight(x, z), z, 0)
						if Spring.TestBuildOrder(buildDef, bx, by, bz, 0) < 2 then
							ok = false
						end
						local sx, sy = screenOf(bx, bz)
						if not sx or sy > top - 30 or sy < 120 then
							ok = false
						end
						if o == -160 or o == 160 then
							ends[#ends + 1] = { sx, sy }
						end
					end
					if ok then
						found = { ends[1][1], ends[1][2], ends[2][1], ends[2][2] }
					end
				end
			end
		end
		write(found and string.format("lspot %d %d %d %d\n", found[1], found[2], found[3], found[4]) or "lspot nil nil nil nil\n")
		Spring.Echo("[docktest] the line's ends: " .. (found and table.concat(found, ",") or "none"))
	elseif c == "borderspot" then -- (a ring's two corners on open ground, every spot of it buildable and clear of the
		-- line's buildings, in sight above the dock: "bspot x0 y0 x1 y1"; a ring guessed above the line found none, 2 runs)
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local _, vsy = Spring.GetViewGeometry()
		local top = dock and (vsy - dock[4]) or vsy -- (X pixels from the top)
		local cx, _, cz = Spring.GetUnitPosition(com)
		local found
		for r = 250, 1400, 50 do
			for a = 0, 345, 15 do
				if not found then
					local mx, mz = cx + math.cos(math.rad(a)) * r, cz + math.sin(math.rad(a)) * r
					local ok, corners = true, {}
					for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
						local x, z = mx + o[1] * 112, mz + o[2] * 112
						local bx, by, bz = Spring.Pos2BuildPos(buildDef, x, Spring.GetGroundHeight(x, z), z, 0)
						if Spring.TestBuildOrder(buildDef, bx, by, bz, 0) < 2 then
							ok = false
						end
						local sx, sy = screenOf(bx, bz)
						if not sx or sy > top - 30 or sy < 120 then
							ok = false
						end
						corners[#corners + 1] = { sx, sy }
					end
					if ok then
						found = { corners[1][1], corners[1][2], corners[4][1], corners[4][2] }
					end
				end
			end
		end
		write(found and string.format("bspot %d %d %d %d\n", found[1], found[2], found[3], found[4]) or "bspot nil nil nil nil\n")
		Spring.Echo("[docktest] the border's corners: " .. (found and table.concat(found, ",") or "none"))
	elseif c == "presetsback" then -- (the Pawns picked, the presets open over the dock: then Android's Back)
		Spring.SelectUnitArray(pawns)
		if WG.BarDroidPresets then
			WG.BarDroidPresets.open()
		end
	elseif c == "backpresets?" then -- (Back with the presets open: closed, nothing picked)
		local PR = WG.BarDroidPresets
		local open = PR and PR.isOpen()
		local n = Spring.GetSelectedUnitsCount()
		check("Back with the presets open on picked units: closed, nothing picked, the dock's home grid", not open and n == 0,
			string.format("presets open %s, %d picked", tostring(open), n))
	elseif c == "stopcom" then -- (the shapes' buildings off the commander's queue: the D-gun mode's walk must not build)
		Spring.GiveOrderToUnit(com, CMD.STOP, {}, 0)
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
	elseif c == "xoff?" then -- (the X tapped by a finger)
		check("the D-gun mode's X tapped: the mode off", D.active() == false, "active " .. tostring(D.active()))
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
	elseif c == "windrects" then -- (the wind's and the tide's boxes, X pixels from the top left)
		local Pt, vsy = WG.BarDroidPortrait, select(2, Spring.GetViewGeometry())
		local wb, tb
		if Pt and Pt.windRects then
			wb, tb = Pt.windRects()
		end
		local function line(name, r)
			return r and string.format("%s %d %d %d %d\n", name, r[1], vsy - r[4], r[3], vsy - r[2]) or (name .. " nil nil\n")
		end
		write(line("wind", wb) .. line("tide", tb))
	elseif c == "tide?" or c == "wind?" then -- (a first tap on the box, the dock's camera pad up: its details open)
		local Pt = WG.BarDroidPortrait
		local open = Pt and Pt.windOpen and Pt.windOpen()
		local kind = c:sub(1, 4)
		check("the " .. kind .. "'s box, its first tap with the camera pad up: its details open", open == kind, open or "none open")
	elseif c == "areamex" then -- (Area Mex, Kailil 2026-11-17: two Construction Bots given by the commander)
		-- (the wind's details of the case before closed: open 15 s, they lay over the metal spot the tap was for)
		local Pw = WG.BarDroidPortrait
		if Pw and Pw.windClose then
			Pw.windClose()
		end
		local x, y, z = Spring.GetUnitPosition(com)
		Spring.SendCommands(string.format("give 2 armck %d @%d,%d,%d", Spring.GetMyTeamID(), x + 120, y, z + 120))
	elseif c == "areamexpick" then -- (they picked; the metal spot nearest the commander in the middle of the game above
		-- the dock, the dock's own camera move: SetCameraTarget left it off the screen, the view's middle is the dock's edge)
		local cks = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), UnitDefNames.armck.id) or {}
		Spring.SelectUnitArray(cks)
		local F, Pt = WG.resource_spot_finder, WG.BarDroidPortrait
		local cx, _, cz = Spring.GetUnitPosition(com)
		local best, bd
		for _, s in ipairs(F and F.metalSpotsList or {}) do
			local d = (s.x - cx) ^ 2 + (s.z - cz) ^ 2
			if not bd or d < bd then
				best, bd = s, d
			end
		end
		if best and Pt and Pt.cameraTo then
			Pt.cameraTo(best.x, Spring.GetGroundHeight(best.x, best.z), best.z)
		end
		Spring.Echo("[docktest] area mex: " .. #cks .. " Construction Bots picked, the camera on a spot "
			.. tostring(best and math.floor(best.x)) .. "," .. tostring(best and math.floor(best.z)))
	elseif c == "areamexarm" then -- (Area Mex armed; a metal spot in sight: the circle's middle there, its edge 90 px on)
		local idx
		for i, d in ipairs(Spring.GetActiveCmdDescs() or {}) do
			if d.action == "areamex" then
				idx = i
			end
		end
		if idx then
			Spring.SetActiveCommand(idx)
		end
		local F = WG.resource_spot_finder
		local vsx = Spring.GetViewGeometry()
		local sx, sy
		local list = F and F.metalSpotsList or {}
		local cx, _, cz = Spring.GetUnitPosition(com)
		table.sort(list, function(a, b) -- (the nearest the commander first: in sight above the dock)
			return (a.x - cx) ^ 2 + (a.z - cz) ^ 2 < (b.x - cx) ^ 2 + (b.z - cz) ^ 2
		end)
		for _, s in ipairs(list) do
			if not sx then
				sx, sy = screenOf(s.x, s.z)
				mexSpot = sx and s or nil
			end
		end
		if not sx and list[1] then
			local wx, wy = Spring.WorldToScreenCoords(list[1].x, Spring.GetGroundHeight(list[1].x, list[1].z), list[1].z)
			Spring.Echo(string.format("[docktest] area mex: %d spots, none in sight; the nearest at %d,%d on the screen",
				#list, wx, wy))
		end
		local ex = sx and (sx + 90 < vsx - 60 and sx + 90 or sx - 90)
		write(sx and string.format("mex0 %d %d\nmex1 %d %d\n", sx, sy, ex, sy) or "mex0 nil nil\n")
		Spring.Echo(string.format("[docktest] area mex armed: %s, a spot at %s,%s", tostring(idx), tostring(sx), tostring(sy)))
	elseif c == "areamex?" then -- (a tap, then a drag: the circle drawn, its spots' mexes queued for the bots)
		local mex = 0
		for _, u in ipairs(Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), UnitDefNames.armck.id) or {}) do
			for _, q in ipairs(Spring.GetUnitCommands(u, 40) or {}) do
				local d = q.id < 0 and UnitDefs[-q.id]
				if d and (d.extractsMetal or 0) > 0 then
					mex = mex + 1
				end
			end
		end
		check("Area Mex armed, a tap, then a drag from a metal spot: BAR's circle, its mexes queued", mex > 0,
			mex .. " mex orders")
		if mex == 0 then -- (why, for the flake of 2026-11-20 05:50: the spot buildable for a mex, the bots' orders,
			-- the command armed at the check)
			local s, mexDef = mexSpot, UnitDefNames.armmex and UnitDefNames.armmex.id
			local orders = {}
			for _, u in ipairs(Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), UnitDefNames.armck.id) or {}) do
				local q = (Spring.GetUnitCommands(u, 1) or {})[1]
				orders[#orders + 1] = q and tostring(q.id) or "none"
			end
			Spring.Echo(string.format("[docktest] (Area Mex: the spot %s, a mex there %s, the bots' first orders %s, armed %s)",
				s and (math.floor(s.x) .. "," .. math.floor(s.z)) or "none",
				s and mexDef and tostring(Spring.TestBuildOrder(mexDef, s.x, Spring.GetGroundHeight(s.x, s.z), s.z, 0)) or "-",
				table.concat(orders, " "), tostring(select(2, Spring.GetActiveCommand()))))
		end
		Spring.SelectUnitArray({})
	elseif c == "resrects" or c == "slider" then -- (metal's and energy's boxes; with the energy panel open, its bar's
		-- cell: X pixels from the top left)
		local Pt, vsy = WG.BarDroidPortrait, select(2, Spring.GetViewGeometry())
		local function line(name, r)
			return r and string.format("%s %d %d %d %d\n", name, r[1], vsy - r[4], r[3], vsy - r[2]) or (name .. " nil nil\n")
		end
		if c == "resrects" then
			local mb, eb
			if Pt and Pt.resBoxes then
				mb, eb = Pt.resBoxes()
			end
			write(line("metal", mb) .. line("energy", eb))
		else
			local r = Pt and Pt.itemCell and Pt.itemCell("right", function(it)
				return it.kind == "slider" and it.res == "energy"
			end)
			write(line("bar", r))
		end
	elseif c == "sendbtn" then -- (stand-in teammates for the picker, the AI's team and two made up, so the energy panel
		-- has its SEND; its cell; the pad's own list again at "picker?")
		local Pd, Pt, vsy = WG.BarDroidPad, WG.BarDroidPortrait, select(2, Spring.GetViewGeometry())
		if Pd and Pd.teammates and not realTeammates then
			realTeammates = Pd.teammates
			local teams = {}
			for _, t in ipairs(Spring.GetTeamList() or {}) do
				if t ~= Spring.GetMyTeamID() and t ~= Spring.GetGaiaTeamID() then
					teams[#teams + 1] = { teamID = t, name = "ALLY " .. t, color = { 0.9, 0.2, 0.2 } }
				end
			end
			teams[#teams + 1] = { teamID = 98, name = "ALLY 98", color = { 0.2, 0.6, 1 } }
			teams[#teams + 1] = { teamID = 99, name = "ALLY 99", color = { 0.95, 0.85, 0.1 } }
			Pd.teammates = function()
				return teams
			end
		end
		if Pt and Pt.refresh then
			Pt.refresh()
		end
		local r = Pt and Pt.itemCell and Pt.itemCell("right", function(it)
			return it.kind == "sendres" and it.res == "energy"
		end)
		write(r and string.format("send %d %d %d %d\n", r[1], vsy - r[4], r[3], vsy - r[2]) or "send nil nil\n")
	elseif c == "picker?" then -- (the teammate picker: every row in sight whole, none cut at the grid's edges; at a
		-- fixed row height 4.8 rows stood in the upright grid, the fifth cut at rest, 2026-11-17)
		local Pt = WG.BarDroidPortrait
		local g = Pt and Pt.gridRect and Pt.gridRect()
		local rows, cut, kinds = 0, 0, {}
		for n = 1, 40 do
			local k = 0
			local r, it = Pt.itemCell("right", function()
				k = k + 1
				return k == n
			end)
			if not r then
				break
			end
			kinds[it.kind] = true
			local inside = r[2] >= g[2] - 1 and r[4] <= g[4] + 1
			local outside = r[4] <= g[2] + 1 or r[2] >= g[4] - 1
			if inside then
				rows = rows + 1
			elseif not outside then
				cut = cut + 1
			end
		end
		check("SEND ENERGY: the teammate picker, every row in sight whole", kinds.shareto and cut == 0 and rows > 0,
			string.format("%d cells in sight, %d cut", rows, cut))
		if realTeammates then
			WG.BarDroidPad.teammates, realTeammates = realTeammates, nil
		end
	elseif c == "slider?" then -- (the share knob dragged to about 40 %: a whole percent, the conversion knob left alone;
		-- before 2026-11-17 the share went in unrounded at every finger move)
		local team = Spring.GetMyTeamID()
		local share = select(6, Spring.GetTeamResources(team, "energy")) or -1
		local conv = Spring.GetTeamRulesParam(team, "mmLevel") or -1
		local whole = math.abs(share * 100 - math.floor(share * 100 + 0.5)) < 0.001
		check("the energy panel's share knob dragged: a whole percent, the conversion knob left alone",
			whole and share > 0.05 and share < 0.9 and math.abs(conv - 0.75) < 0.001,
			string.format("share %.4f, conversion %.2f", share, conv))
	elseif c == "twopan" or c == "minifight" then -- (check only, RC 0.2.0 item 5: the commander picked; its orders a
		-- frame later, so armed at the next stage)
		Spring.SelectUnitArray({ com })
		Spring.GiveOrderToUnit(com, CMD.STOP, {}, 0)
	elseif c == "twopanarm" then -- (two fingers dragged with a building picked)
		local index = Spring.GetCmdDescIndex(-UnitDefNames.armsolar.id)
		if index then
			Spring.SetActiveCommand(index, 1, true, false, false, false, false, false)
		end
		camAt = Spring.GetCameraState()
		local vsx, vsy = Spring.GetViewGeometry()
		local Pt = WG.BarDroidPortrait
		local dock = Pt and Pt.dock and Pt.dock()
		local top = dock and dock[4] or 0
		write(string.format("pan %d %d\n", math.floor(vsx * 0.5), math.floor(vsy - (top + (vsy - top) * 0.55))))
	elseif c == "twopan?" then
		local cs = Spring.GetCameraState()
		local moved = math.abs((cs.px or 0) - (camAt.px or 0)) + math.abs((cs.pz or 0) - (camAt.pz or 0))
			+ math.abs((cs.dist or cs.height or 0) - (camAt.dist or camAt.height or 0))
		local _, id = Spring.GetActiveCommand()
		local queued = #(Spring.GetUnitCommands(com, 5) or {})
		check("check only: two fingers dragged with a Solar picked: the camera moves, the Solar still picked, nothing queued",
			moved > 20 and id == -UnitDefNames.armsolar.id and queued == 0,
			string.format("camera moved %.0f, picked %s, %d orders", moved, tostring(id), queued))
		Spring.SetActiveCommand(0)
	elseif c == "minifightarm" then -- (Fight armed; the minimap small, as upright it is until touched: "open x y", its
		-- middle: a player's first tap only opens it, bardroid_minimap.lua, Kailil 2026-10-28)
		local index = Spring.GetCmdDescIndex(CMD.FIGHT)
		if index then
			Spring.SetActiveCommand(index, 1, true, false, false, false, false, false)
		end
		local M = WG.BarDroidMinimap
		local px, py, sx, sy = Spring.GetMiniMapGeometry()
		local _, vsy = Spring.GetViewGeometry()
		local x, y = math.floor(px + sx * 0.5), math.floor(py + sy * 0.5)
		if not Spring.IsAboveMiniMap(x, y) then
			y = math.floor(vsy - py - sy * 0.5)
		end
		write(M and M.small() and Spring.IsAboveMiniMap(x, y) and string.format("open %d %d\n", x, vsy - y) or "")
	elseif c == "minifightpt" then -- (the minimap open: a place on it, "mini x y")
		local M = WG.BarDroidMinimap
		local px, py, sx, sy = Spring.GetMiniMapGeometry()
		local _, vsy = Spring.GetViewGeometry()
		local x, y = math.floor(px + sx * 0.7), math.floor(py + sy * 0.35)
		if not Spring.IsAboveMiniMap(x, y) then -- (its y from the top: the other way round)
			y = math.floor(vsy - py - sy * 0.65)
		end
		local _, pos = Spring.TraceScreenRay(x, y, true, true)
		mexSpot = { mini = pos, tol = math.max(Game.mapSizeX / math.max(1, sx), Game.mapSizeZ / math.max(1, sy)) * 12 }
		local _, armed = Spring.GetActiveCommand()
		Spring.Echo(string.format("[docktest] the minimap %s,%s %sx%s (small %s), the tap %d,%d (above it %s), the place %s, armed %s",
			tostring(px), tostring(py), tostring(sx), tostring(sy), tostring(M and M.small()), x, y,
			tostring(Spring.IsAboveMiniMap(x, y)), pos and string.format("%.0f,%.0f", pos[1], pos[3]) or "nil", tostring(armed)))
		write(Spring.IsAboveMiniMap(x, y) and pos and string.format("mini %d %d\n", x, vsy - y) or "")
	elseif c == "minifight?" then
		local _, armed = Spring.GetActiveCommand()
		local mx, my = Spring.GetMouseState()
		Spring.Echo(string.format("[docktest] after the minimap's tap: armed %s, the pointer %d,%d, %d picked", tostring(armed),
			mx, my, Spring.GetSelectedUnitsCount()))
		local q = Spring.GetUnitCommands(com, 2) or {}
		local f, m = q[1], mexSpot and mexSpot.mini
		local off = f and m and f.params and f.params[3] and math.sqrt((f.params[1] - m[1]) ^ 2 + (f.params[3] - m[3]) ^ 2)
		check("check only: Fight armed, BAR's minimap tapped open, then a place on it: the Fight goes there", f and f.id == CMD.FIGHT
			and off and off <= mexSpot.tol, string.format("first order %s, %s elmos from the place (within %d)",
				tostring(f and f.id), tostring(off and math.floor(off)), math.floor(mexSpot and mexSpot.tol or 0)))
		Spring.GiveOrderToUnit(com, CMD.STOP, {}, 0)
		Spring.SetActiveCommand(0)
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

-- (and between frames: a paused game has none, and BAR pauses a game alone while its quit question is up, Back's case:
-- the question's stage waited for the game to go on, after the next Back had closed it; 2026-11-20)
local cmdAt = 0
function widget:Update()
	local t = os.clock()
	if not ready or t - cmdAt < 0.2 then
		return
	end
	cmdAt = t
	local c = readCmd()
	if c and c ~= lastCmd then
		lastCmd = c
		onCmd(c)
	end
end
