-- BAR Droid touch camera: the Android app (RtsTouch.java) reports finger drags, pinches, twists and tilts, and the
-- camera follows the fingers, smoothed over a few frames. The app needs to know whether a drag
-- starts on the interface (a mouse drag) or on the map (a pan), so this widget also reports that for the pointer.
-- It also sets BAR's interface scale for the Fold screen the game is on (the window size follows the screen in the
-- X server). Installed into LuaUI/Widgets by the app.
--
-- BAR's sandbox gives user widgets no sockets, only files under LuaUI/, so (paths relative to the write dir, X screen
-- pixels with the origin at the top left):
--   LuaUI/Config/bardroid_touch.txt   app, appended:  pan <x0> <y0> <x1> <y1>   (the map point under x0,y0 goes to x1,y1)
--                                                     zoom <ratio> <x> <y>      (finger distance grew by this factor; pinch centre)
--                                                     rot <radians>             (fingers twisted, clockwise > 0)
--                                                     tilt <fraction>           (fingers moved down by this much of the screen height)
--                                                     pad <lx> <ly> <rx> <ry> <lt> <lb>  (gamepad, when it changes: raw
--                                                                               sticks -32768..32767 with y down, LT 0..32767, LB 0|1)
--                                                     act <name>                (a gesture's action: ACTIONS below)
--                                                     spot <x> <y> | spot none  (a building's spot for the build
--                                                                               menu's PLACE button: bardroid_buildmenu.lua)
--                                                     nudge <dx> <dy>           (the waiting building moved by that many
--                                                                               pixels, y down)
--                                                     grid start | grid by <dx> <dy> | grid none  (a GRID from the
--                                                                               waiting building, its far corner moved)
--                                                     src <touch|mouse|keyboard|pad>  (the input used, when it changes)
--   LuaUI/Config/bardroid_screen.txt  app, replaced:  <w> <h> <hz> <fps>        (X screen size, display Hz; fps 0)
--   LuaUI/Config/bardroid_hover.txt   widget:         <x> <y> <0|1>             (pointer position; 1 = on the interface)
--   LuaUI/Config/bardroid_game.txt    widget, at start: controller <0|1>        (1: the controller game, v0.8.5 reads
--                                                                               the pad; 0: the pad is a mouse and keys)
--   LuaUI/Config/bardroid_catchup.txt widget:         <frame> <server frame or 0> <speed>  (only while catching up
--                                                                               with a running game: the engine then
--                                                                               draws nothing)
--
-- The gamepad camera is for BAR's released game (online, spectating), with v0.8.5's camera speeds and easing: the
-- app's pad lines say pan (lx, ly), turn (rx), zoom (ry; tilt with lb) and boost (lt). There the app makes the left
-- stick the pointer, so its lines carry the right stick: a pan, or with LB held a turn and a zoom (ControllerBridge).
-- In the controller game (BAR Controller Support v0.8.5, the app's singleplayer game) v0.8.5 reads the pad itself,
-- so this part stays off there.

function widget:GetInfo()
	return {
		name = "BAR Droid touch camera",
		desc = "Touch camera and interface scale from the BAR Droid app",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		-- last of all: IsAbove reaches this widget only where no other widget claims the pointer
		layer = 1000000,
		enabled = true,
	}
end

local TOUCH = "LuaUI/Config/bardroid_touch.txt"
local SCREEN = "LuaUI/Config/bardroid_screen.txt"
local HOVER = "LuaUI/Config/bardroid_hover.txt"
local GAME = "LuaUI/Config/bardroid_game.txt"
local TILT_RANGE = math.pi / 2 * 1.75 * 1.5 -- a drag over the screen height tilts this much (Kailil: +75%, then +50%)
-- Finger moves reach the camera over a few frames instead of in whatever batch each frame happened to collect
-- (Kailil, 2026-10-26: "super juttery", "like a super cheap touch screen mp3 player"); seconds.
local TOUCH_SMOOTHING = 0.05

local spTraceScreenRay = Spring.TraceScreenRay
local spGetCameraState = Spring.GetCameraState
local spSetCameraState = Spring.SetCameraState
local spGetViewGeometry = Spring.GetViewGeometry
local spGetMouseState = Spring.GetMouseState
local spIsAboveMiniMap = Spring.IsAboveMiniMap
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers

-- v0.8.5's camera defaults (gui_controller_camera_test.lua); the pan 30% slower (Kailil, 2026-10-29, both controller
-- modes: v0.8.5's own too)
local PAD_PAN_SPEED, PAD_FAST_PAN = 1400 * 0.7, 2.75
local PAD_ZOOM_SCALE, PAD_ROTATION, PAD_PITCH = 0.9, 3.0, 3.0
local PAD_STICK_CURVE, PAD_TRIGGER_CURVE, PAD_SMOOTHING = 1.175, 1.075, 0.06
local PAD_STICK_DEADZONE, PAD_TRIGGER_DEADZONE = 5000, 3000
local MIN_SPRING_DISTANCE, MIN_OVERHEAD_HEIGHT, MIN_CAMERA_RX, MAX_CAMERA_RX = 20, 60, 1.0, 3.05
-- the engine's limits for the Spring camera's distance (SpringController.cpp), set in Initialize
local zoomMinDistance, zoomMaxDistance = MIN_SPRING_DISTANCE, 100000

local touchPos, partial = 0, ""
local lastScreen, screenCheck = nil, 0
local updates = 0
local seenX, seenY, seenAt = -1, -1, -1000
local mouseX, mouseY, mouseSince = -1, -1, 0
local hoverTimer = nil
local padCamera = true   -- false in the controller game (until a triple tap gives the pad to the app: mod_bardroid)

-- Long queues of the selected units: the engine draws every building a selected builder has queued once more, one model
-- at a time (CommandDrawer -> CCursorIcons::DrawBuilds), over BAR's "Show Builder Queue", which has drawn them all
-- already (Fold7, 2026-10-26: a ~150 wind turbine queue ran 29-30 fps with nothing selected, 17 with the commander
-- selected). Past QUEUE_LIMIT orders of the selected builders the selection's queue is drawn only while Shift is held
-- (cmdcolors alwaysDrawQueue, the engine's own switch); BAR's widget keeps showing the queued buildings. Only builders
-- count (Kailil, 2026-10-29: a big army's move paths showed only while RT was held): other units queue no buildings.
local QUEUE_LIMIT = 40
local queueDrawn, queueCheck = true, 0
local spGetUnitCommandCount = Spring.GetUnitCommandCount
local spGetSelectedUnits = Spring.GetSelectedUnits
local pad = { lx = 0, ly = 0, rx = 0, ry = 0, lt = 0, lb = false }
local smooth = { panX = 0, panY = 0, rotate = 0, pitch = 0, zoom = 0, boost = 0 }

local function fileSize(path)
	local f = io.open(path, "r")
	if not f then
		return 0
	end
	local size = f:seek("end")
	f:close()
	return size
end

-- A file for the app, written whole and then renamed: the app reads these many times a second and must never find
-- one empty or half written (io.open "w" empties it first). True when written.
local function writeWhole(path, text)
	local f = io.open(path .. ".tmp", "w")
	if not f then
		return false
	end
	f:write(text)
	f:close()
	local ok, renamed = pcall(os.rename, path .. ".tmp", path)
	if not (ok and renamed) then -- (Windows, for the laptop tests: rename does not replace a file)
		pcall(os.remove, path)
		pcall(os.rename, path .. ".tmp", path)
	end
	return true
end

function widget:Initialize()
	touchPos = fileSize(TOUCH) -- old gestures are not replayed
	pcall(os.remove, "LuaUI/Config/bardroid_catchup.txt") -- left by a reload while catching up: written again if still behind
	-- the controller game: BAR's developer game ("$VERSION") with v0.8.5's pad bridge
	local ok, found = pcall(VFS.FileExists, "LuaUI/Widgets/controller_socket_bridge.lua", VFS.ZIP)
	padCamera = not ((ok and found) or Game.gameVersion == "$VERSION")
	-- for the app: in the controller game the pad is v0.8.5's; in BAR's game a mouse and keys (ControllerBridge)
	writeWhole(GAME, padCamera and "controller 0\n" or "controller 1\n")
	zoomMinDistance = math.max(Spring.GetConfigFloat("CamSpringMinZoomDistance", 0.1) or 0.1, 0.1)
	zoomMaxDistance = math.max(Game.mapSizeX, Game.mapSizeZ) * 1.333
	local cs = spGetCameraState()
	Spring.Echo(string.format("[bardroid-touch] camera %s (rx %s, ry %s), gamepad camera %s", tostring(cs.name),
		tostring(cs.rx), tostring(cs.ry), padCamera and "on" or "off (the controller game reads the pad)"))
end

-- Called for the pointer position only when no widget before this one (the whole interface) claimed it.
function widget:IsAbove(x, y)
	seenX, seenY, seenAt = x, y, updates
	return false
end

-- Complete new lines of the touch log since the last call. One handle across frames: an open is a path system call,
-- which proot traps (two ptrace stops and a path translation) on the phone, once a frame. The app truncates the same
-- file for a new log (the size shrinks); opened again every TOUCH_REOPEN updates in case the file itself was replaced.
local TOUCH_REOPEN = 60
local touchFile, touchFileAt = nil, -1000
local function newTouchLines()
	-- (BAR's sandbox checks the path of every io.open too: a missing file is looked for again only that often)
	if updates - touchFileAt >= TOUCH_REOPEN then
		if touchFile then
			touchFile:close()
		end
		touchFile, touchFileAt = io.open(TOUCH, "r"), updates
	end
	local f = touchFile
	if not f then
		return nil
	end
	local size = f:seek("end")
	if not size then -- (the handle went bad: open it again next time)
		f:close()
		touchFile = nil
		return nil
	end
	if size < touchPos then -- the app started a new log
		touchPos, partial = 0, ""
	end
	if size == touchPos then
		return nil
	end
	f:seek("set", touchPos)
	local data = partial .. (f:read("*a") or "")
	touchPos = f:seek()
	local cut = data:match(".*\n()") -- just after the last newline
	if not cut then
		partial = data
		return nil
	end
	partial = data:sub(cut)
	return data:sub(1, cut - 1)
end

-- Where the view ray through X screen pixel (x, y) meets the level plane at height h; nil above the horizon.
local function planePoint(x, y, h)
	local _, vsy = spGetViewGeometry()
	local dx, dy, dz = Spring.GetPixelDir(x, vsy - y)
	if not dy or dy > -0.01 then
		return nil
	end
	local cx, cy, cz = Spring.GetCameraPosition()
	local t = (h - cy) / dy
	return cx + dx * t, cz + dz * t
end

-- The map point under an X screen pixel. Off the map (the void around it) the view ray meets the plane at the height
-- of the ground the camera looks at, so dragging keeps working there; nil only above the horizon.
local function ground(x, y)
	if not (x and y) then
		return nil -- a line that is not numbers
	end
	local _, vsy = spGetViewGeometry()
	local kind, pos = spTraceScreenRay(x, vsy - y, true)
	if kind == "ground" and pos then
		return pos[1], pos[3]
	end
	local cs = spGetCameraState()
	return planePoint(x, y, cs.px and cs.pz and Spring.GetGroundHeight(cs.px, cs.pz) or 0)
end

-- Camera moves the fingers asked for and the camera has not made yet: pan (map units), twist and tilt (radians), zoom
-- (log of the distance factor) about the map point under the pinch.
local pending = { dx = 0, dz = 0, rot = 0, tilt = 0, zoom = 0, pivotX = nil, pivotZ = nil }

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end


-- The next or previous mobile builder of the player's own team that has no orders (not one still being built), selected
-- and looked at. Cycles by unit ID from the last one picked.
local lastIdleBuilder = 0
local function idleBuilder(step)
	if Spring.GetSpectatingState() then
		return
	end
	local idle = {}
	for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.isBuilder and not def.isFactory and (def.speed or 0) > 0 and spGetUnitCommandCount(unitID) == 0
			and not Spring.GetUnitIsBeingBuilt(unitID) then
			idle[#idle + 1] = unitID
		end
	end
	if #idle == 0 then
		return
	end
	table.sort(idle)
	local pick = step > 0 and idle[1] or idle[#idle] -- wrapping around
	for i = 1, #idle do
		local id = step > 0 and idle[i] or idle[#idle + 1 - i]
		if (step > 0 and id > lastIdleBuilder) or (step < 0 and id < lastIdleBuilder) then
			pick = id
			break
		end
	end
	lastIdleBuilder = pick
	Spring.SelectUnitArray({ pick })
	local x, y, z = Spring.GetUnitPosition(pick)
	if x then
		Spring.SetCameraTarget(x, y, z, 0.3)
	end
end

local function inOverview()
	return spGetCameraState().name == "ov"
end

-- Three fingers down (Kailil, 2026-10-29, and 2026-10-30: "teleport cam to commander AND select commander"): the camera
-- to the commander, selected; if it is dead, to the constructor selected last (else any). Out of the overview first: its
-- way back is waited out (lookAt, a few updates later).
local lastConstructor, lookAt = nil, nil
local function constructorDef(def)
	return def and def.isBuilder and not def.isFactory and (def.speed or 0) > 0
end
local function lookAtCommander()
	if Spring.GetSpectatingState() then
		return
	end
	local pick, builder
	for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.customParams and def.customParams.iscommander then
			pick = unitID
			break
		elseif not builder and constructorDef(def) then
			builder = unitID
		end
	end
	if not pick and lastConstructor and Spring.ValidUnitID(lastConstructor) and not Spring.GetUnitIsDead(lastConstructor) then
		pick = lastConstructor
	end
	pick = pick or builder
	local x, y, z
	if pick then
		x, y, z = Spring.GetUnitPosition(pick)
	end
	if x then
		Spring.SetCameraTarget(x, y, z, 0.3)
		Spring.SelectUnitArray({ pick })
	end
end

-- Gesture actions from the app ("act <name>", RtsTouch.java): the same commands BAR's keys send. The gamepad's are
-- bardroid_pad.lua's (any name not here goes there).
local ACTIONS = {
	fingers = function() -- a few taps since the pad was last used (RtsTouch.source): the menus as without a pad
		WG.BarDroidPadOnly = nil
	end,
	type_all = function() -- a triple tap: the types of the selection (a double tap's) on the whole map
		Spring.SendCommands("select AllMap+_InPrevSel+_ClearSelection_SelectAll+")
	end,
	select_all = function()
		Spring.SendCommands("select AllMap++_ClearSelection_SelectAll+")
	end,
	deselect = function()
		Spring.SelectUnitArray({})
	end,
	-- (as BAR's order buttons do: an order key's action sent as a command reaches no order)
	stop = function()
		Spring.SetActiveCommand("stop")
	end,
	fight = function() -- armed: the next tap places it
		Spring.SetActiveCommand("fight")
	end,
	overview_in = function()
		if not inOverview() then
			Spring.SendCommands("toggleoverview")
		end
	end,
	overview_out = function()
		if inOverview() then
			Spring.SendCommands("toggleoverview")
		end
	end,
	commander_view = function()
		if inOverview() then
			Spring.SendCommands("toggleoverview")
			lookAt = 3 -- (updates: the overview's way back first)
		else
			lookAtCommander()
		end
	end,
	idle_next = function()
		idleBuilder(1)
	end,
	idle_prev = function()
		idleBuilder(-1)
	end,
	-- the controller game: a triple tap switches the pad between v0.8.5 and the app's controls (GameActivity), the
	-- camera with it (bardroid_pad.lua shows which)
	mod_bardroid = function()
		padCamera = true
		if WG.BarDroidPad then
			WG.BarDroidPad.act("mod_bardroid")
		end
	end,
	mod_v085 = function()
		padCamera = false
		if WG.BarDroidPad then
			WG.BarDroidPad.act("mod_v085")
		end
	end,
	hud = function() -- three fingers held: the layout editor (bardroid_layout.lua)
		if WG.BarDroidLayout then
			WG.BarDroidLayout.toggle()
		end
	end,
}

-- bardroid_spectate.lua's 1st person: the fingers look around instead of moving the camera (pan: screen pixels;
-- pinch: the FOV; twist and tilt as they are)
local function readLook(lines, L)
	for x0, y0, x1, y1 in lines:gmatch("pan (%S+) (%S+) (%S+) (%S+)") do
		local a, b, c, d = tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1)
		if a and b and c and d then
			L.dx, L.dy = L.dx + c - a, L.dy + d - b
		end
	end
	for r in lines:gmatch("zoom (%S+) %S+ %S+") do
		local ratio = tonumber(r)
		if ratio and ratio > 0 then
			L.zoom = L.zoom * ratio
		end
	end
	for a in lines:gmatch("rot (%S+)") do
		L.rot = L.rot + (tonumber(a) or 0)
	end
	for t in lines:gmatch("tilt (%S+)") do
		L.tilt = L.tilt + (tonumber(t) or 0)
	end
end

local function readTouch(lines)
	local p = pending
	local L = WG.BarDroidLayout
	if L and L.isOpen() then -- the layout editor: the camera stays, a pinch resizes the panel picked
		for r in lines:gmatch("zoom (%S+) %S+ %S+") do
			L.pinch(tonumber(r) or 1)
		end
		lines = lines:gsub("pan [^\n]*", ""):gsub("zoom [^\n]*", ""):gsub("rot [^\n]*", ""):gsub("tilt [^\n]*", "")
	elseif WG.BarDroidFirstPerson and WG.BarDroidLook then
		readLook(lines, WG.BarDroidLook)
		lines = lines:gsub("pan [^\n]*", ""):gsub("zoom [^\n]*", ""):gsub("rot [^\n]*", ""):gsub("tilt [^\n]*", "")
	end
	for x0, y0, x1, y1 in lines:gmatch("pan (%S+) (%S+) (%S+) (%S+)") do
		local ax, az = ground(tonumber(x0), tonumber(y0))
		local bx, bz = ground(tonumber(x1), tonumber(y1))
		if ax and bx then
			-- grab: the point that was under the fingers moves with them
			p.dx, p.dz = p.dx + ax - bx, p.dz + az - bz
		end
	end
	for r, x, y in lines:gmatch("zoom (%S+) (%S+) (%S+)") do
		local ratio = tonumber(r)
		if ratio and ratio > 0 then
			p.zoom = p.zoom + math.log(ratio)
			local gx, gz = ground(tonumber(x), tonumber(y))
			if gx then
				p.pivotX, p.pivotZ = gx, gz
			end
		end
	end
	for a in lines:gmatch("rot (%S+)") do
		p.rot = p.rot + (tonumber(a) or 0)
	end
	for t in lines:gmatch("tilt (%S+)") do
		p.tilt = p.tilt + (tonumber(t) or 0)
	end
	for lx, ly, rx, ry, lt, lb in lines:gmatch("pad (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)") do -- the last one counts
		pad.lx, pad.ly, pad.rx, pad.ry = tonumber(lx) or 0, tonumber(ly) or 0, tonumber(rx) or 0, tonumber(ry) or 0
		pad.lt, pad.lb = tonumber(lt) or 0, lb == "1"
	end
	for name in lines:gmatch("act (%S+)") do
		local action = ACTIONS[name]
		if WG.BarDroidPadSpeed and WG.BarDroidPadSpeed.act(name) then -- luacheck: ignore 542 (the path speed tuner's)
		elseif action then
			action()
		elseif WG.BarDroidPad then
			WG.BarDroidPad.act(name)
		end
	end
	-- a building picked: the spot a tap or a drag picked for the build menu's PLACE button, a nudge of it, a GRID from it
	-- (bardroid_buildmenu.lua), in the order the app sent them; a frame's nudges and GRID moves summed
	local b = WG.bardroidBuildmenu
	if b and b.droidSpot and (lines:find("spot ", 1, true) or lines:find("nudge ", 1, true) or lines:find("grid ", 1, true)) then
		local nx, ny, gx, gy = 0, 0, 0, 0
		local function flush()
			if (nx ~= 0 or ny ~= 0) and b.droidNudge then
				b.droidNudge(nx, ny)
			end
			if (gx ~= 0 or gy ~= 0) and b.droidSetGrid then
				b.droidSetGrid("by", gx, gy)
			end
			nx, ny, gx, gy = 0, 0, 0, 0
		end
		for line in lines:gmatch("[^\n]+") do
			local kind, args = line:match("^(%a+) (.*)$")
			if kind == "nudge" then
				local x, y = args:match("^(%S+) (%S+)")
				nx, ny = nx + (tonumber(x) or 0), ny + (tonumber(y) or 0)
			elseif kind == "grid" and args:find("^by ") then
				local x, y = args:match("^by (%S+) (%S+)")
				gx, gy = gx + (tonumber(x) or 0), gy + (tonumber(y) or 0)
			elseif kind == "spot" then
				flush()
				local x, y = args:match("^(%S+) (%S+)")
				b.droidSpot(tonumber(x), tonumber(y))
			elseif kind == "grid" and b.droidSetGrid then
				flush()
				b.droidSetGrid(args)
			end
		end
		flush()
	end
	-- for bardroid_spectate.lua: the input last used (the app says when it changes) and when the fingers last panned
	for source in lines:gmatch("src (%S+)") do
		WG.BarDroidInput = source
		if source == "pad" then
			WG.BarDroidPadOnly = true -- (the pad's ways: menus hidden until RB, its orders off; until "act fingers")
		end
	end
	if lines:find("pan ", 1, true) then
		WG.BarDroidPanAt = os.clock()
	end
end

-- The part of a pending move made this frame, and what is left; the last bit all at once.
local function portion(value, fraction, epsilon)
	local part = value * fraction
	if math.abs(value - part) < epsilon then
		return value, 0
	end
	return part, value - part
end

local function applyTouch(dt)
	local p = pending
	if p.dx == 0 and p.dz == 0 and p.rot == 0 and p.tilt == 0 and p.zoom == 0 then
		return
	end
	local f = 1 - math.exp(-dt / TOUCH_SMOOTHING)
	local dx, dz, rot, tilt, zoom
	dx, p.dx = portion(p.dx, f, 0.5)
	dz, p.dz = portion(p.dz, f, 0.5)
	rot, p.rot = portion(p.rot, f, 0.0005)
	tilt, p.tilt = portion(p.tilt, f, 0.0005)
	zoom, p.zoom = portion(p.zoom, f, 0.0005)
	local cs = spGetCameraState()
	if cs.px and cs.pz then
		-- The engine keeps the camera's target on the map. At its edge, what is still pending outward would only be eaten
		-- by that clamp, and a drag back in would first have to cancel it (a dead zone): dropped.
		local nx, nz = clamp(cs.px + dx, 0, Game.mapSizeX), clamp(cs.pz + dz, 0, Game.mapSizeZ)
		if nx ~= cs.px + dx and p.dx * dx > 0 then
			p.dx = 0
		end
		if nz ~= cs.pz + dz and p.dz * dz > 0 then
			p.dz = 0
		end
		cs.px, cs.pz = nx, nz
		-- spread the fingers: closer; the map point under the pinch stays under it
		local key = cs.dist and "dist" or cs.height and "height"
		if zoom ~= 0 and key then
			-- (the engine's limit as it is now: bardroid_spectate.lua lowers it for its 1st person camera)
			local low = key == "dist" and math.max(Spring.GetConfigFloat("CamSpringMinZoomDistance", zoomMinDistance) or
				zoomMinDistance, 0.1) or MIN_OVERHEAD_HEIGHT
			local value = math.max(low, math.min(zoomMaxDistance, cs[key] / math.exp(zoom)))
			if p.pivotX then
				local s = value / cs[key]
				cs.px, cs.pz = p.pivotX + (cs.px - p.pivotX) * s, p.pivotZ + (cs.pz - p.pivotZ) * s
			end
			cs[key] = value
		end
		if p.zoom == 0 then
			p.pivotX, p.pivotZ = nil, nil -- a later pinch over the sky (no map point) zooms about the centre, not here
		end
	end
	-- Spring camera (BAR's default): ry turns around the vertical axis, rx is the pitch (the engine clamps it).
	-- The map turns with the fingers, so the camera turns the other way.
	if rot ~= 0 and cs.ry then
		cs.ry = cs.ry - rot
	end
	-- fingers down: look more from above
	if tilt ~= 0 and cs.rx then
		cs.rx = cs.rx + tilt * TILT_RANGE
	end
	spSetCameraState(cs, 0)
end

-- v0.8.5's stick handling: deadzone, response curve, then smoothing towards the stick with a 0.06 s time constant.
local function stick(v)
	local m = math.abs(v)
	if m < PAD_STICK_DEADZONE then
		return 0
	end
	local n = math.min(1, (m - PAD_STICK_DEADZONE) / (32767 - PAD_STICK_DEADZONE)) ^ PAD_STICK_CURVE
	return v < 0 and -n or n
end

local function triggerValue(v)
	if v < PAD_TRIGGER_DEADZONE then
		return 0
	end
	return math.min(1, (v - PAD_TRIGGER_DEADZONE) / (32767 - PAD_TRIGGER_DEADZONE)) ^ PAD_TRIGGER_CURVE
end

local function approach(current, target, dt)
	local value = current + (target - current) * (1 - math.exp(-dt / PAD_SMOOTHING))
	return math.abs(value) < 0.001 and 0 or value
end

local function horizontal(v)
	local x, z = v and tonumber(v[1]) or 0, v and tonumber(v[3]) or 0
	local len = math.sqrt(x * x + z * z)
	if len <= 0.001 then
		return nil
	end
	return x / len, z / len
end

local function applyPad(dt)
	local s = smooth
	local rider = WG.BarDroidPadFP
	if rider and rider.active() then -- (first person on the pad: bardroid_padfp.lua has the sticks)
		rider.sticks(stick(pad.lx), stick(pad.ly), stick(pad.rx), stick(pad.ry))
		return
	end
	if pad.lx == 0 and pad.ly == 0 and pad.rx == 0 and pad.ry == 0 and pad.lt == 0
		and s.panX == 0 and s.panY == 0 and s.rotate == 0 and s.pitch == 0 and s.zoom == 0 and s.boost == 0 then
		return -- the sticks rest: nothing to do
	end
	local y = -stick(pad.ry) -- up zooms in (tilts with LB)
	s.panX = approach(s.panX, stick(pad.lx), dt)
	s.panY = approach(s.panY, stick(pad.ly), dt)
	s.rotate = approach(s.rotate, stick(pad.rx), dt)
	s.pitch = approach(s.pitch, pad.lb and y or 0, dt)
	s.zoom = approach(s.zoom, pad.lb and 0 or y, dt)
	s.boost = approach(s.boost, triggerValue(pad.lt), dt)
	if s.panX == 0 and s.panY == 0 and s.rotate == 0 and s.pitch == 0 and s.zoom == 0 then
		return
	end
	local cs = spGetCameraState()
	if not (cs.px and cs.pz) then
		return
	end
	local maxDistance = math.max(Game.mapSizeX, Game.mapSizeZ, 1000) * 1.5
	if s.panX ~= 0 or s.panY ~= 0 then
		local v = Spring.GetCameraVectors()
		local rightX, rightZ = horizontal(v and v.right)
		local forwardX, forwardZ = horizontal(v and v.forward)
		-- a building picked: 20% slower; Back's slow pan (bardroid_pad.lua) 33% (Kailil, 2026-10-30: it was 30%, "increase
		-- slow mode by 10 percent")
		local _, activeID = Spring.GetActiveCommand()
		local distance = PAD_PAN_SPEED * (1 + (PAD_FAST_PAN - 1) * s.boost) * dt
			* (WG.BarDroidPadSlowPan and 0.33 or (activeID and activeID < 0 and 0.8 or 1))
		if rightX and forwardX then
			cs.px = cs.px + (s.panX * rightX - s.panY * forwardX) * distance
			cs.pz = cs.pz + (s.panX * rightZ - s.panY * forwardZ) * distance
		else
			cs.px, cs.pz = cs.px + s.panX * distance, cs.pz + s.panY * distance
		end
	end
	if s.zoom ~= 0 then
		local scale = 1 - s.zoom * PAD_ZOOM_SCALE * 3 * dt
		if cs.dist then
			cs.dist = clamp(cs.dist * scale, MIN_SPRING_DISTANCE, maxDistance)
		elseif cs.height then
			cs.height = clamp(cs.height * scale, MIN_OVERHEAD_HEIGHT, maxDistance)
		end
	end
	if s.rotate ~= 0 and cs.ry then
		cs.ry = cs.ry + s.rotate * PAD_ROTATION * dt
	end
	if s.pitch ~= 0 and cs.rx then
		cs.rx = clamp(cs.rx + s.pitch * PAD_PITCH * dt, MIN_CAMERA_RX, MAX_CAMERA_RX)
	end
	cs.px, cs.pz = clamp(cs.px, 0, Game.mapSizeX), clamp(cs.pz, 0, Game.mapSizeZ)
	spSetCameraState(cs, 0)
end

local function updateQueueDrawing()
	if not spGetUnitCommandCount then
		return
	end
	local orders = 0
	for _, unitID in ipairs(spGetSelectedUnits() or {}) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
		if def and def.isBuilder then
			orders = orders + (spGetUnitCommandCount(unitID) or 0)
			if orders > QUEUE_LIMIT then
				break
			end
		end
	end
	local draw = orders <= QUEUE_LIMIT
	if draw ~= queueDrawn then
		queueDrawn = draw
		Spring.LoadCmdColorsConfig("alwaysDrawQueue " .. (draw and 1 or 0))
	end
end

function widget:SelectionChanged(selected)
	updateQueueDrawing()
	for _, unitID in ipairs(selected or {}) do -- (the constructor the three-finger slide down falls back to)
		local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
		if constructorDef(def) and not (def.customParams and def.customParams.iscommander) then
			lastConstructor = unitID
			break
		end
	end
end

-- Long sessions (the target is 30 fps for hours on a hot phone): once a minute the average frame rate, the slowest
-- frame and the frames of each second go to the log, next to the app's thermal lines ("[perf]" in launcher.log).
-- Counted in the world pass (DrawWorld), i.e. drawn frames: while nobody sees the game the engine stops drawing and
-- Update runs on. A gap of more than 5 s (the game screen hidden, a reload) starts a new minute.
local perfFrames, perfStart, perfLast, perfWorst = 0, nil, nil, 0
local perSecond, secondStart, secondFrames = {}, nil, 0
local catchup -- while catching up with a running game (below): the engine's own settings, where the last log line was
local function logPerf()
	local now = spGetTimer()
	if perfLast and spDiffTimers(now, perfLast) > 5 then
		if not catchup then -- (catching up, the engine draws one picture every 30 s on purpose: its own log lines say so)
			Spring.Echo(string.format("[bardroid-perf] no frame drawn for %.0f s (game screen hidden, or a reload)",
				spDiffTimers(now, perfLast)))
		end
		perfFrames, perfStart, perfLast, perfWorst, secondStart, secondFrames = 0, nil, nil, 0, nil, 0
		for i = #perSecond, 1, -1 do
			perSecond[i] = nil
		end
	end
	if perfLast then
		local frame = spDiffTimers(now, perfLast)
		if frame > perfWorst then
			perfWorst = frame
		end
	end
	perfLast, perfFrames, secondFrames = now, perfFrames + 1, secondFrames + 1
	if not secondStart then
		secondStart = now
	elseif spDiffTimers(now, secondStart) >= 1 then
		perSecond[#perSecond + 1] = secondFrames
		secondStart, secondFrames = now, 0
	end
	if not perfStart then
		perfStart = now
		return
	end
	local seconds = spDiffTimers(now, perfStart)
	if seconds >= 60 then
		Spring.Echo(string.format("[bardroid-perf] %.1f fps over %.0f s, slowest frame %.0f ms, %d units; each second: %s",
			perfFrames / seconds, seconds, perfWorst * 1000, #(Spring.GetAllUnits() or {}), table.concat(perSecond, " ")))
		perfFrames, perfStart, perfWorst = 0, now, 0
		for i = #perSecond, 1, -1 do
			perSecond[i] = nil
		end
	end
end

-- Joining a running game (spectating, a reconnect) replays it from the start as fast as the phone can (Kailil,
-- 2026-10-26: a 40 min game "crawls at a 1-2x catch up speed"). Two joins on a hot phone: the engine kept drawing
-- 9-26 pictures a second all along (the GPU 50-99% busy, at its lowest clock), CPUs capped at 1.0-2.0 GHz, x1.6-4.
-- Lowering the engine's draw share (MinSimDrawBalance) alone did not stop that drawing. So while catching up (not in
-- replays) this widget writes CATCHUP about once a second, "<game frame> <server frame or 0> <speed>"; the app then
-- shows the progress over the game and hands the engine a hidden window (libbardroid_pace.so, /tmp/bardroid-catchup):
-- the engine draws nothing (a 10 ms sleep per pass, sound muted), as when the phone is locked, until this file is gone.
-- The simulation gets the time and the GPU cools. Update stops with the drawing, so this runs from GameFrame.
-- Catching up = the game runs faster than its speed for 2 s in a row, or GameProgress says more than 30 s behind. The
-- server's GameProgress reaches a late joiner only after the whole backlog of the game (3 min after joining a 24 min
-- game: the mode started that late, Kailil saw nothing change), so the game's own pace starts it. Caught up = less
-- than 5 s behind by GameProgress, or (no GameProgress yet) the game back at its speed for 3 s.
-- MinSimDrawBalance 0.02 / MinDrawFPS 1 (config overlay, never saved) make each stretch of simulation between those
-- passes ~50 times the last picture's cost instead of ~6. springsettings bardroid_catchup = 0 turns it all off.
local CATCHUP = "LuaUI/Config/bardroid_catchup.txt"
local CATCHUP_ENTER, CATCHUP_LEAVE = 30 * 30, 5 * 30 -- game frames behind the server
local CATCHUP_FAST, CATCHUP_FAST_SECONDS, CATCHUP_SLOW_SECONDS = 1.5, 2, 3 -- game speed multiples, checks in a row
local CATCHUP_BALANCE, CATCHUP_MIN_DRAW_FPS = 0.02, 1
local CATCHUP_LOG_EVERY = 30 -- seconds
local CATCHUP_PAUSE = 0.05 -- seconds between two simulated frames that count as a pause (drawing, or no data yet)
-- A game too big for the phone to run even at its own speed never catches up (Kailil's 6,000-unit join stayed 9 min
-- behind at x0.6-0.9, the picture frozen all along): no ground gained over CATCHUP_GIVE_UP seconds, it draws again,
-- and tries again CATCHUP_RETRY seconds later (the game may shrink, the phone cool down), then twice as long after
-- each further give-up (a live game the phone keeps falling behind in is not blanked for a minute every 5 minutes).
local CATCHUP_GIVE_UP, CATCHUP_RETRY = 60, 300
local catchupGaveUp, catchupRetry = nil, CATCHUP_RETRY -- timer of the last give-up, wait before the next try
local serverFrame, serverFrameAt -- GameProgress: the server's frame, every 150 frames
-- (catchup, declared above logPerf: while catching up, the engine's own settings and where the last log line was)
local catchupChecked, checkedFrame, lastGameFrameAt
local fastChecks, slowChecks = 0, 0
local speedFrame, speedAt, speedNow = nil, nil, 0 -- game speed over the last few seconds, for the app's progress

local function gameClock(frame)
	local s = math.floor(frame / 30)
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function endCatchup()
	if catchup then
		Spring.SetConfigFloat("MinSimDrawBalance", catchup.balance, true)
		Spring.SetConfigInt("MinDrawFPS", catchup.minDrawFps, true)
		catchup = nil
		pcall(os.remove, CATCHUP)
	end
end

function widget:GameProgress(frame)
	serverFrame, serverFrameAt = frame, spGetTimer()
end

local function updateCatchup(now, frame, rate)
	-- (springsettings bardroid_catchup = 0: the engine's own balance, for comparisons)
	if Spring.IsReplay() or Spring.GetConfigInt("bardroid_catchup", 1) == 0 then
		endCatchup()
		return
	end
	local speed, _, paused = Spring.GetGameSpeed()
	speed = speed or 1
	local behind -- game frames, by the last GameProgress; nil before the first
	if serverFrame then
		behind = serverFrame + (paused and 0 or speed * 30 * spDiffTimers(now, serverFrameAt)) - frame
	end
	fastChecks = rate > CATCHUP_FAST * speed and fastChecks + 1 or 0
	slowChecks = rate < 1.2 * speed and slowChecks + 1 or 0
	if not speedAt or spDiffTimers(now, speedAt) >= 3 then
		speedNow = speedAt and (frame - speedFrame) / 30 / spDiffTimers(now, speedAt) or 0
		speedFrame, speedAt = frame, now
	end
	if not catchup then
		-- (once GameProgress is there it decides alone: a live game the phone briefly lags behind is not a catch-up)
		if not (behind and behind > CATCHUP_ENTER or not behind and fastChecks >= CATCHUP_FAST_SECONDS) then
			return
		end
		if catchupGaveUp and spDiffTimers(now, catchupGaveUp) < catchupRetry then
			return
		end
		catchup = { balance = Spring.GetConfigFloat("MinSimDrawBalance", 0.15),
			minDrawFps = Spring.GetConfigInt("MinDrawFPS", 2), frame = frame, time = now, logFrame = frame, logTime = now,
			pauses = 0, pauseTime = 0 }
		Spring.SetConfigFloat("MinSimDrawBalance", CATCHUP_BALANCE, true)
		Spring.SetConfigInt("MinDrawFPS", CATCHUP_MIN_DRAW_FPS, true)
		Spring.Echo(string.format("[bardroid-catchup] at %s, %s, x%.1f: no drawing until caught up", gameClock(frame),
			behind and gameClock(behind) .. " behind" or "behind (no GameProgress yet)", rate))
	end
	if (behind and behind < CATCHUP_LEAVE) or (not behind and slowChecks >= CATCHUP_SLOW_SECONDS) then
		local seconds = spDiffTimers(now, catchup.time)
		Spring.Echo(string.format("[bardroid-catchup] caught up at %s after %.0f s (x%.1f on average)", gameClock(frame),
			seconds, (frame - catchup.frame) / 30 / math.max(seconds, 1)))
		endCatchup()
		catchupGaveUp, catchupRetry = nil, CATCHUP_RETRY
		return
	end
	if behind then -- ground gained over the last CATCHUP_GIVE_UP seconds
		if not catchup.gainAt then
			catchup.gainAt, catchup.gainBehind = now, behind
		elseif spDiffTimers(now, catchup.gainAt) >= CATCHUP_GIVE_UP then
			if behind >= catchup.gainBehind then
				if catchupGaveUp then -- (a second give-up and later: twice the wait)
					catchupRetry = catchupRetry * 2
				end
				Spring.Echo(string.format("[bardroid-catchup] at %s, %s behind: not gaining (x%.1f), drawing again; next try in %d s",
					gameClock(frame), gameClock(behind), speedNow, catchupRetry))
				endCatchup()
				catchupGaveUp = now
				return
			end
			catchup.gainAt, catchup.gainBehind = now, behind
		end
	end
	writeWhole(CATCHUP, string.format("%d %d %.1f\n", frame, behind and math.floor(frame + behind) or 0, speedNow))
	local logSeconds = spDiffTimers(now, catchup.logTime)
	if logSeconds >= CATCHUP_LOG_EVERY then
		Spring.Echo(string.format("[bardroid-catchup] at %s, %s, x%.1f over %.0f s, %d units; %d pauses over %d ms"
			.. " between frames, %.1f s in all", gameClock(frame), behind and gameClock(behind) .. " behind" or "no GameProgress yet",
			(frame - catchup.logFrame) / 30 / logSeconds, logSeconds, #(Spring.GetAllUnits() or {}), catchup.pauses,
			CATCHUP_PAUSE * 1000, catchup.pauseTime))
		catchup.logFrame, catchup.logTime, catchup.pauses, catchup.pauseTime = frame, now, 0, 0
	end
end

local function gameFrame(frame)
	local now = spGetTimer()
	if catchup and lastGameFrameAt then
		local gap = spDiffTimers(now, lastGameFrameAt)
		if gap > CATCHUP_PAUSE then
			catchup.pauses, catchup.pauseTime = catchup.pauses + 1, catchup.pauseTime + gap
		end
	end
	lastGameFrameAt = now
	if not catchupChecked then
		catchupChecked, checkedFrame = now, frame
		return
	end
	local seconds = spDiffTimers(now, catchupChecked)
	if seconds >= 1 then
		local rate = (frame - checkedFrame) / 30 / seconds -- game seconds per second over the last second
		catchupChecked, checkedFrame = now, frame
		updateCatchup(now, frame, rate)
	end
end

-- Deferred passes nobody reads on the phone (their readers, BAR's lights, SSAO, bloom, distortion and unit outlines,
-- are off). With BAR's advanced map shading off (its Lowest preset, the phone's) the engine still clears the map's
-- G-buffer every frame, six screen-sized render targets that nothing draws into; and it draws every tree and rock a
-- second time into the model G-buffer. Units stay in it (shields outline the units they touch, the radar and jammer
-- placement previews hide behind them). Switched off after the first drawn frames, so the buffers hold a cleared
-- picture rather than fresh memory (an engine buffer that is not drawn is not resized on fold/unfold either: it stays
-- all cleared); the map's comes back within 60 frames if the map shading is turned on. (Spring.SetDrawGroundDeferred,
-- SetDrawModelsDeferred: unsynced, allowed to user widgets.)
local DEFERRED_FIRST, DEFERRED_EVERY = 3, 60 -- drawn frames
local deferredFrames, groundDeferredOff, featuresDeferredOff = 0, false, false
local function trimDeferred()
	deferredFrames = deferredFrames + 1
	if deferredFrames ~= DEFERRED_FIRST and deferredFrames % DEFERRED_EVERY ~= 0 then
		return
	end
	local groundOff = Spring.GetConfigInt("AdvMapShading", 1) == 0
	if groundOff ~= groundDeferredOff then
		Spring.SetDrawGroundDeferred(not groundOff)
		groundDeferredOff = groundOff
		Spring.Echo("[bardroid-touch] map G-buffer pass " .. (groundOff and "off (advanced map shading is off)" or "on again"))
	end
	if not featuresDeferredOff then
		Spring.SetDrawModelsDeferred(true, false)
		featuresDeferredOff = true
		Spring.Echo("[bardroid-touch] trees and rocks drawn once (no model G-buffer pass for features)")
	end
end
local function restoreDeferred()
	if groundDeferredOff then
		Spring.SetDrawGroundDeferred(true)
		groundDeferredOff = false
	end
	if featuresDeferredOff then
		Spring.SetDrawModelsDeferred(true, true)
		featuresDeferredOff = false
	end
end

function widget:Shutdown()
	if not queueDrawn then
		Spring.LoadCmdColorsConfig("alwaysDrawQueue 1")
	end
	endCatchup() -- a LuaUI reload (fold/unfold) while catching up: the next start sees the gap again
	restoreDeferred() -- the engine's own passes back (a reload switches them off again)
	if touchFile then
		touchFile:close()
		touchFile = nil
	end
end

-- BAR's interface scale for the screen the game is on (Kailil, 2026-10-26: on the Fold's cover screen "EVERYTHING IS
-- TOO SMALL ... interface 2.0 is necessary", on the inner one "1.3 scale is good"; 2026-10-28, BAR's build menu taking no
-- size of its own: "then we will just have to reduce the interface scale to 1.0 on unfolded"). Most of BAR's widgets
-- read ui_scale only when they load, so a fold or unfold that changes it reloads LuaUI, as BAR's own slider does.
-- launch-bar.sh sets it for the screen a game starts on, so a start needs no reload.
local UI_SCALE_COVER, UI_SCALE_INNER, UI_SCALE_COVER_UPRIGHT = 2.0, 1.0, 1.0
local function applyUiScale(w, h)
	local long, short = math.max(w, h), math.min(w, h)
	if long < 640 then
		-- the floating window while the app is in the background (584x530, 488x442): no reload on the way out and back.
		-- (By the long side: at the lowest render resolution, 70%, the cover screen is 1176x504.)
		return
	end
	-- cover screen 2520x1080; held upright BAR already sizes its interface by the tall side (and 2.0 overflows the width)
	local want = long / short < 1.6 and UI_SCALE_INNER or w > h and UI_SCALE_COVER or UI_SCALE_COVER_UPRIGHT
	local screen = w .. "x" .. h
	if math.abs((Spring.GetConfigFloat("ui_scale", 1) or 1) - want) <= 0.001 then
		Spring.SetConfigString("bardroid_ui_scale_reload", "")
		return
	end
	-- one reload per screen size: if something sets the scale back, the next widget load leaves it (no reload loop)
	if Spring.GetConfigString("bardroid_ui_scale_reload", "") == screen then
		Spring.Echo(string.format("[bardroid-touch] %s screen: interface scale stays %.2f (it was set to %.1f once)", screen,
			Spring.GetConfigFloat("ui_scale", 1) or 1, want))
		return
	end
	Spring.SetConfigString("bardroid_ui_scale_reload", screen)
	Spring.SetConfigFloat("ui_scale", want)
	Spring.Echo(string.format("[bardroid-touch] %s screen: interface scale %.1f, reloading the interface", screen, want))
	Spring.SendCommands("luarules reloadluaui")
end

-- The window size is the X server's job (BAR Droid's lorie patch 0003 keeps the game window the size of the screen).
-- Never Spring.SetWindowGeometry here: the engine clamps it to the screen size SDL saw at startup, so on the other
-- screen of a foldable it would shrink the window again. The frame cap is libbardroid_pace.so's (no VSync).

-- Most of BAR's interface answers no IsAbove: its windows (the settings with their sliders) and the top bar (the
-- share and conversion sliders) would take a finger drag for a pan of the map underneath. A window that is open
-- makes the whole screen interface (BAR closes it on a click outside); the top bar tells where it is. Checked again
-- when the pointer moves, else every 10 frames (a window opened by a tap that left the pointer where it was).
local BAR_WINDOWS = { "options", "gameinfo", "teamstats", "keybinds", "changelog", "widgetselector", "missioninfo",
	"scavengerinfo" }
local barX, barY, barAt, barAnswer = nil, nil, -1000, false
local function overBarInterface(mx, my)
	if mx == barX and my == barY and updates - barAt < 10 then
		return barAnswer
	end
	barX, barY, barAt, barAnswer = mx, my, updates, false
	for i = 1, #BAR_WINDOWS do
		local w = WG[BAR_WINDOWS[i]]
		if type(w) == "table" and type(w.isvisible) == "function" and w.isvisible() then
			barAnswer = true
			return true
		end
	end
	local tb = WG.topbar
	local p = type(tb) == "table" and type(tb.GetPosition) == "function" and tb.GetPosition()
	if type(p) == "table" and p[1] and p[2] and p[3] and p[4] then -- left, bottom, right, top (+ scale, buttons' bottom)
		local bottom = math.min(p[2], tonumber(p[6]) or p[2])
		barAnswer = mx >= p[1] and mx <= p[3] and my >= bottom and my <= p[4]
	end
	return barAnswer
end

-- Whether the interface is under the pointer: the engine asks the widgets each frame (IsAbove) where the pointer is,
-- and this widget, last in line, only hears of it where nothing else answered.
-- The map/interface answer for a pointer that stays put is worked out again every HOVER_RECHECK updates only (the
-- camera moving under it can change it); a pointer that moves gets it at once. Profiled on the laptop (2026-10-26):
-- this widget was BAR's most expensive one, 0.14 ms a frame (a view ray, a string and a file open every frame).
local HOVER_RECHECK = 10
local calcX, calcY, calcAt, calcAnswer = nil, nil, -1000, 0
local hoverX, hoverY, hoverAnswer
local function updateHover()
	local mx, my = spGetMouseState()
	if mx ~= mouseX or my ~= mouseY then
		mouseX, mouseY, mouseSince = mx, my, updates
	end
	local onInterface
	if seenX == mx and seenY == my and seenAt >= mouseSince - 1 then
		-- 1 interface, 0 map (the void past the map's edge too: fingers work there as on the map)
		if mx ~= calcX or my ~= calcY or updates - calcAt >= HOVER_RECHECK then
			calcAnswer = (spIsAboveMiniMap(mx, my) or overBarInterface(mx, my)) and 1 or 0
			calcX, calcY, calcAt = mx, my, updates
		end
		onInterface = calcAnswer
	elseif updates - seenAt > 300 then
		-- no IsAbove for a long time: a window that holds the pointer for itself, else the map
		onInterface = overBarInterface(mx, my) and 1 or 0
	elseif updates - mouseSince >= 2 then
		onInterface = 1
	else
		return -- not asked yet for this position
	end
	local now = spGetTimer()
	if mx == hoverX and my == hoverY and onInterface == hoverAnswer and hoverTimer and spDiffTimers(now, hoverTimer) < 1 then
		return
	end
	-- also once a second: the app takes an old file for "no widget" (the lobby)
	local _, vsy = spGetViewGeometry()
	writeWhole(HOVER, string.format("%d %d %d\n", mx, vsy - my - 1, onInterface))
	hoverX, hoverY, hoverAnswer, hoverTimer = mx, my, onInterface, now
end

local function update(dt)
	updates = updates + 1
	local lines = newTouchLines()
	if lines then
		readTouch(lines)
	end
	applyTouch(dt)
	if padCamera then
		applyPad(dt)
	end
	if lookAt then
		lookAt = lookAt - 1
		if lookAt <= 0 then
			lookAt = nil
			lookAtCommander()
		end
	end
	updateHover()
	queueCheck = queueCheck - dt
	if queueCheck <= 0 then -- queues grow and shrink without a selection change
		queueCheck = 0.5
		updateQueueDrawing()
	end

	screenCheck = screenCheck - dt
	if screenCheck <= 0 then
		screenCheck = 0.5
		local f = io.open(SCREEN, "r")
		if f then
			local s = f:read("*l")
			f:close()
			local w, h = (s or ""):match("^(%d+) (%d+) ")
			if w and w .. "x" .. h ~= lastScreen then -- the size: the display's 60/120 Hz switches change the rest
				lastScreen = w .. "x" .. h
				applyUiScale(tonumber(w), tonumber(h))
			end
		end
	end
end

-- An error would make BAR's widget handler remove the widget for the rest of the game: no finger camera, and the app
-- would take the missing pointer answers for the lobby. Logged a few times instead, and the next frame tries again.
local errorsLogged = 0
local function guarded(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and errorsLogged < 5 then
		errorsLogged = errorsLogged + 1
		Spring.Echo("[bardroid-touch] error, the widget keeps running: " .. tostring(err))
	end
end

function widget:Update(dt)
	guarded(update, dt)
end

-- the world pass: once per drawn frame, and (unlike DrawScreen) also with the interface hidden or a window open
function widget:DrawWorld()
	guarded(logPerf)
	guarded(trimDeferred)
end

-- once per simulated frame, drawn or not (Update stops while the engine does not draw): the catch-up check, about once
-- a second of real time
function widget:GameFrame(frame)
	guarded(gameFrame, frame)
end
