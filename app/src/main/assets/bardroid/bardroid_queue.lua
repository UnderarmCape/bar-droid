-- BAR Droid builder queue: the see-through buildings of every builder's queue, as BAR's "Show Builder Queue" draws
-- them, but only near where the camera looks. BAR's widget draws every queued building (up to 4096 models) every
-- frame, wherever it is; in late games, a thousand queued wind turbines across the map, a tilted camera saw them all
-- (Kailil, 2026-10-26: "not drawing build grid orders if 1000 windmill thats queued up in the far distance").
-- launch-bar.sh switches BAR's widget off. Uses BAR's own builder queue API (WG.BuilderQueueApi) and shape drawer
-- (WG.DrawUnitShapeGL4). Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid builder queue",
		desc = "Queued buildings near where the camera looks (the phone's Show Builder Queue)",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local DRAW_RADIUS = 2000 -- elmos from the camera's target (the middle of the screen)
local MAX_SHAPES = 400
local OPACITY = 0.24 -- BAR's
local CHECK_EVERY = 0.25 -- seconds

local spGetCameraState = Spring.GetCameraState
local spGetGroundHeight = Spring.GetGroundHeight

local waterline = {} -- submerged buildings are drawn at their waterline, as BAR's widget does
for defID, def in pairs(UnitDefs) do
	if def.waterline and def.waterline > 0 then
		waterline[defID] = def.waterline
	end
end

local commands = {} -- command id -> { def, x, y, z, rot, team }
local shapes = {} -- command id -> shape handle
local shown, total = 0, 0
local api
local callbacks = {}
local check = 0
local guiHidden = false
-- the camera's target at the last look over every queued building, and the time since: in a late 16-player game,
-- thousands of queued buildings and new orders every frame, each of which used to start that look again (0.2 % of the
-- dev phone's main thread, docs/ENGINE-SIM.md on engine/sim "BAR's Lua on phones"). A new one is now placed on its own;
-- the look runs again when the camera has moved, or every 2 s.
local lastX, lastZ, sinceLook = nil, nil, 0
local MOVED = 100 -- elmos
local LOOK_EVERY = 2 -- seconds

local function hide(id)
	local s = shapes[id]
	if s then
		if WG.StopDrawUnitShapeGL4 then -- (gone when BAR's shape drawer shut down first, its shapes with it)
			WG.StopDrawUnitShapeGL4(s)
		end
		shapes[id] = nil
		shown = shown - 1
	end
end

local function showIfNear(id, c)
	local draw = WG.DrawUnitShapeGL4
	if not (lastX and draw) or guiHidden or shapes[id] or shown >= MAX_SHAPES then
		return
	end
	local dx, dz = c.x - lastX, c.z - lastZ
	if dx * dx + dz * dz <= DRAW_RADIUS * DRAW_RADIUS then
		shapes[id] = draw(c.def, c.x, c.y - 0.01, c.z, c.rot, OPACITY, c.team)
		if shapes[id] then
			shown = shown + 1
		end
	end
end

local function add(id, c)
	if commands[id] then
		return
	end
	local y = spGetGroundHeight(c.positionX, c.positionZ)
	if waterline[c.unitDefId] then
		y = math.max(y, -waterline[c.unitDefId])
	end
	local cmd = { def = c.unitDefId, x = c.positionX, y = y, z = c.positionZ,
		rot = (c.rotation or 0) * math.pi / 2, team = c.teamId }
	commands[id] = cmd
	total = total + 1
	showIfNear(id, cmd) -- (now, if it is near where the camera looked last)
end

local function remove(id)
	hide(id)
	if commands[id] then
		commands[id] = nil
		total = total - 1
	end
end

local function clear()
	for id in pairs(shapes) do
		hide(id)
	end
	commands, total = {}, 0
end

-- shows what is within DRAW_RADIUS of the camera's target (up to MAX_SHAPES), hides the rest
local function refresh()
	local cs = spGetCameraState()
	local cx, cz = cs.px, cs.pz
	local draw = WG.DrawUnitShapeGL4 -- (gone if BAR's shape drawer shut down: the call would take this widget with it)
	if not (cx and cz and draw) or guiHidden then
		for id in pairs(shapes) do
			hide(id)
		end
		lastX, lastZ = nil, nil
		return
	end
	if lastX and sinceLook < LOOK_EVERY and (cx - lastX) ^ 2 + (cz - lastZ) ^ 2 < MOVED * MOVED then
		return -- (the camera has not moved: new orders were placed as they came)
	end
	lastX, lastZ, sinceLook = cx, cz, 0
	local r2 = DRAW_RADIUS * DRAW_RADIUS
	for id, c in pairs(commands) do
		local dx, dz = c.x - cx, c.z - cz
		local near = dx * dx + dz * dz <= r2
		if not near then
			hide(id)
		elseif not shapes[id] and shown < MAX_SHAPES then
			shapes[id] = draw(c.def, c.x, c.y - 0.01, c.z, c.rot, OPACITY, c.team)
			if shapes[id] then
				shown = shown + 1
			end
		end
	end
end

local function start()
	clear()
	api = WG.BuilderQueueApi
	if not (api and WG.DrawUnitShapeGL4 and WG.StopDrawUnitShapeGL4) then
		return false
	end
	-- (each one only where BAR's release has it: an older replay plays its own release, whose API had no
	-- OnBuildCommandTeamChanged (test-31465, 2026-11-04: "attempt to call field", and BAR removed this widget))
	for _, f in ipairs({ "OnBuildCommandAdded", "OnBuildCommandRemoved", "ForEachActiveBuildCommand", "UnregisterCallback" }) do
		if type(api[f]) ~= "function" then
			api = nil
			return false
		end
	end
	callbacks = {}
	local function on(name, fn)
		if type(api[name]) == "function" then
			callbacks[#callbacks + 1] = api[name](fn)
		end
	end
	on("OnBuildCommandAdded", add)
	on("OnBuildCommandRemoved", remove)
	on("OnBuildCommandTeamChanged", function(id, c)
		remove(id)
		add(id, c)
	end)
	on("OnUnitCreated", function(_, _, id) -- the building has started: the real one is there
		remove(id)
	end)
	on("OnUnitFinished", function(_, id)
		remove(id)
	end)
	api.ForEachActiveBuildCommand(add)
	return true
end

local function stop()
	if api then
		for i = 1, #callbacks do
			local cb = callbacks[i]
			if cb then
				api.UnregisterCallback(cb.eventName, cb.callback)
			end
		end
	end
	callbacks = {}
	clear()
end

local started = false
function widget:Update(dt)
	if not started then
		started = start() -- BAR's APIs load with the game widgets: try until they are there
		if not started then
			return
		end
	end
	local hidden = Spring.IsGUIHidden()
	if hidden ~= guiHidden then
		guiHidden, check, lastX = hidden, 0, nil
	end
	sinceLook = sinceLook + dt
	check = check - dt
	if check <= 0 then
		check = CHECK_EVERY
		refresh()
	end
end

local _, fullView = Spring.GetSpectatingState()
function widget:PlayerChanged(playerID)
	if playerID ~= Spring.GetLocalPlayerID() then
		return
	end
	local _, now = Spring.GetSpectatingState()
	if started and now ~= fullView then -- a spectator's full view changes what can be seen
		stop()
		started = start()
	end
	fullView = now
end

function widget:Shutdown()
	stop()
	WG.bardroidQueue = nil
end

-- for tools/touch-widget-test.ps1
WG.bardroidQueue = {
	shown = function() return shown end,
	total = function() return total end,
	radius = DRAW_RADIUS,
	max = MAX_SHAPES,
}
