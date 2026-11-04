-- BAR Droid build ranges: while a building is picked the engine draws the build range of every construction turret of
-- the player's team, and of each selected builder, as a circle on the ground: twice (the map and the minimap), each
-- circle its own drawing over 40 ground heights (GuiHandler.cpp DrawMapStuff). With many turrets in a late game,
-- picking anything to build lagged the game (Kailil, 2026-11-03, after an online game on the Fold7: "it displays
-- literally all of them at the same time. Can we change it to display only the closest 10 or something?"). So while a
-- building is picked the engine's build range colour is see-through, and the engine skips those circles without
-- drawing them (BAR hides engine circles it does not want the same way: cmdcolors_icexuick.txt, gui_cursor.lua), and
-- this widget draws the ranges of the MAX_SHOWN builders nearest the building, and the picked building's own range if
-- it builds. Client-side only. Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid build ranges",
		desc = "While a building is picked: the build ranges of the builders nearest it, not of every turret",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local MAX_SHOWN = 10
local SEGMENTS = 40 -- (the engine's)
-- BAR's build range colour (cmdcolors_icexuick.txt, loaded by its cursor widget); the engine draws the other builders'
-- ranges at a third of its alpha, the picked building's at all of it
local R, G, B, A = 0.3, 1.0, 0.3, 0.3
local SHOWN = "rangeBuild " .. R .. " " .. G .. " " .. B .. " " .. A
local HIDDEN = "rangeBuild " .. R .. " " .. G .. " " .. B .. " 0"

local spGetActiveCommand = Spring.GetActiveCommand
local spGetMouseState = Spring.GetMouseState
local spTraceScreenRay = Spring.TraceScreenRay
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local glDrawGroundCircle = gl.DrawGroundCircle

local reach = {} -- unitDefID -> build distance, for builders (not factories: no builder circles for them)
local immobile = {} -- unitDefID -> true for construction turrets
local own = {} -- unitDefID -> build distance: a picked building's own range (factories too, as the engine)
for defID, def in pairs(UnitDefs) do
	if def.isBuilder and (def.buildDistance or 0) > 0 then
		own[defID] = def.buildDistance
		if not def.isFactory then
			reach[defID] = def.buildDistance
			immobile[defID] = not def.canMove or nil
		end
	end
end

local myTeam = Spring.GetMyTeamID()
local turrets = {} -- unitID -> { x, y, z, build distance }: the team's construction turrets (they never move)
local hidden = false
-- the nearest builders this frame (kept between frames: no tables made while drawing)
local nearX, nearY, nearZ, nearR, nearD = {}, {}, {}, {}, {}
local nearN = 0

-- (team: the unit's team after the event: the engine calls UnitTaken before the unit changes team, Unit.cpp ChangeTeam)
local function track(unitID, defID, team)
	if immobile[defID] and team == myTeam then
		local x, y, z = spGetUnitPosition(unitID)
		if x then
			turrets[unitID] = { x, y, z, reach[defID] }
		end
	else
		turrets[unitID] = nil
	end
end

local function trackAll()
	turrets = {}
	myTeam = Spring.GetMyTeamID()
	for _, unitID in ipairs(Spring.GetTeamUnits(myTeam) or {}) do
		track(unitID, spGetUnitDefID(unitID), myTeam)
	end
end

-- (set again every frame while hidden: BAR's cursor widget loads its whole colour file again when the cursor changes,
-- a resize too; one line for the engine to read)
local function setHidden(h)
	if h or h ~= hidden then
		hidden = h
		Spring.LoadCmdColorsConfig(h and HIDDEN or SHOWN)
	end
end

-- keeps the MAX_SHOWN nearest (an insertion into a short sorted list)
local function consider(x, y, z, r, px, pz)
	local dx, dz = x - px, z - pz
	local d = dx * dx + dz * dz
	if nearN == MAX_SHOWN and d >= nearD[nearN] then
		return
	end
	local i = nearN < MAX_SHOWN and nearN + 1 or nearN
	nearN = i
	while i > 1 and nearD[i - 1] > d do
		nearX[i], nearY[i], nearZ[i], nearR[i], nearD[i] = nearX[i - 1], nearY[i - 1], nearZ[i - 1], nearR[i - 1], nearD[i - 1]
		i = i - 1
	end
	nearX[i], nearY[i], nearZ[i], nearR[i], nearD[i] = x, y, z, r, d
end

-- where the picked building would go: the ground under the pointer, else under the middle of the screen
local function buildSpot()
	local mx, my = spGetMouseState()
	local _, pos = spTraceScreenRay(mx, my, true)
	if not pos then
		local vsx, vsy = Spring.GetViewGeometry()
		_, pos = spTraceScreenRay(vsx / 2, vsy / 2, true)
	end
	return pos
end

-- (before the frame is drawn: the engine reads the colour as it draws its circles)
local picked -- the picked building's unitDefID
function widget:Update()
	local _, cmdID = spGetActiveCommand()
	picked = cmdID and cmdID < 0 and -cmdID or nil
	setHidden(picked ~= nil)
end

function widget:DrawWorld()
	if not picked then
		return
	end
	local pos = buildSpot()
	if not pos then
		return
	end
	local px, pz = pos[1], pos[3]
	nearN = 0
	for _, t in pairs(turrets) do
		consider(t[1], t[2], t[3], t[4], px, pz)
	end
	for _, unitID in ipairs(spGetSelectedUnits()) do
		local defID = spGetUnitDefID(unitID)
		if reach[defID] and not turrets[unitID] then
			local x, y, z = spGetUnitPosition(unitID)
			if x then
				consider(x, y, z, reach[defID], px, pz)
			end
		end
	end
	gl.Color(R, G, B, A / 3)
	for i = 1, nearN do
		glDrawGroundCircle(nearX[i], nearY[i], nearZ[i], nearR[i], SEGMENTS)
	end
	if own[picked] then -- the picked building builds: its own range where it would stand
		local x, y, z = Spring.Pos2BuildPos(picked, pos[1], pos[2], pos[3], Spring.GetBuildFacing())
		gl.Color(R, G, B, A)
		glDrawGroundCircle(x, y, z, own[picked], SEGMENTS)
	end
	gl.Color(1, 1, 1, 1)
end

function widget:UnitCreated(unitID, unitDefID, team)
	track(unitID, unitDefID, team)
end

function widget:UnitGiven(unitID, unitDefID, newTeam)
	track(unitID, unitDefID, newTeam)
end

function widget:UnitTaken(unitID, unitDefID, _, newTeam)
	track(unitID, unitDefID, newTeam)
end

function widget:UnitDestroyed(unitID)
	turrets[unitID] = nil
end

function widget:PlayerChanged()
	if Spring.GetMyTeamID() ~= myTeam then
		trackAll()
	end
end

function widget:Initialize()
	trackAll()
end

function widget:Shutdown()
	setHidden(false)
end
