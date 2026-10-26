-- BAR Droid touch camera: the Android app (RtsTouch.java) reports finger drags, twists and tilts, and the camera
-- follows the fingers; pinch zoom needs nothing here (it is the mouse wheel). The app needs to know whether a drag
-- starts on the interface (a mouse drag) or on the map (a pan), so this widget also reports that for the pointer.
-- It also keeps the frame cap at the display's refresh rate (which changes when a foldable folds or unfolds; the
-- window size follows the screen in the X server). Installed into LuaUI/Widgets by the app.
--
-- BAR's sandbox gives user widgets no sockets, only files under LuaUI/, so (paths relative to the write dir, X screen
-- pixels with the origin at the top left):
--   LuaUI/Config/bardroid_touch.txt   app, appended:  pan <x0> <y0> <x1> <y1>   (the map point under x0,y0 goes to x1,y1)
--                                                     rot <radians>             (fingers twisted, clockwise > 0)
--                                                     tilt <fraction>           (fingers moved down by this much of the screen height)
--                                                     pad <lx> <ly> <rx> <ry> <lt> <lb>  (gamepad, when it changes: raw
--                                                                               sticks -32768..32767 with y down, LT 0..32767, LB 0|1)
--   LuaUI/Config/bardroid_screen.txt  app, replaced:  <w> <h> <hz> <fps>        (X screen size, display Hz, frame cap)
--   LuaUI/Config/bardroid_hover.txt   widget:         <x> <y> <0|1>             (pointer position; 1 = on the interface)
--
-- The gamepad camera is for BAR's released game (online, spectating). It moves the camera the way Kailil's controller
-- build (BAR Controller Support v0.8.5, the app's singleplayer game) does: left stick pans (LT up to 2.75x faster),
-- right stick turns (x) and zooms (y; with LB held it tilts instead). In that game v0.8.5 reads the pad itself, so
-- this part stays off there.

function widget:GetInfo()
	return {
		name = "BAR Droid touch camera",
		desc = "Touch camera and frame cap from the BAR Droid app",
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
local TILT_RANGE = math.pi / 2 -- a drag over the whole screen height tilts this much

local spTraceScreenRay = Spring.TraceScreenRay
local spGetCameraState = Spring.GetCameraState
local spSetCameraState = Spring.SetCameraState
local spGetViewGeometry = Spring.GetViewGeometry
local spGetMouseState = Spring.GetMouseState
local spIsAboveMiniMap = Spring.IsAboveMiniMap
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers

-- v0.8.5's camera defaults (gui_controller_camera_test.lua)
local PAD_PAN_SPEED, PAD_FAST_PAN = 1400, 2.75
local PAD_ZOOM_SCALE, PAD_ROTATION, PAD_PITCH = 0.9, 3.0, 3.0
local PAD_STICK_CURVE, PAD_TRIGGER_CURVE, PAD_SMOOTHING = 1.175, 1.075, 0.06
local PAD_STICK_DEADZONE, PAD_TRIGGER_DEADZONE = 5000, 3000
local MIN_SPRING_DISTANCE, MIN_OVERHEAD_HEIGHT, MIN_CAMERA_RX, MAX_CAMERA_RX = 20, 60, 1.0, 3.05

local touchPos, partial = 0, ""
local lastScreen, screenCheck = nil, 0
local updates = 0
local seenX, seenY, seenAt = -1, -1, -1000
local mouseX, mouseY, mouseSince = -1, -1, 0
local lastHover, hoverTimer = nil, nil
local padCamera = true   -- false in the controller game

-- Long queues of the selected units: the engine draws every building a selected builder has queued once more, one model
-- at a time (CommandDrawer -> CCursorIcons::DrawBuilds), over BAR's "Show Builder Queue", which has drawn them all
-- already (Fold7, 2026-10-26: a ~150 wind turbine queue ran 29-30 fps with nothing selected, 17 with the commander
-- selected). Past QUEUE_LIMIT orders the selection's queue is drawn only while Shift is held (cmdcolors
-- alwaysDrawQueue, the engine's own switch); BAR's widget keeps showing the queued buildings.
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

function widget:Initialize()
	touchPos = fileSize(TOUCH) -- old gestures are not replayed
	-- the controller game: BAR's developer game ("$VERSION") with v0.8.5's pad bridge
	local ok, found = pcall(VFS.FileExists, "LuaUI/Widgets/controller_socket_bridge.lua", VFS.ZIP)
	padCamera = not ((ok and found) or Game.gameVersion == "$VERSION")
	local cs = spGetCameraState()
	Spring.Echo(string.format("[bardroid-touch] camera %s (rx %s, ry %s), gamepad camera %s", tostring(cs.name),
		tostring(cs.rx), tostring(cs.ry), padCamera and "on" or "off (the controller game reads the pad)"))
end

-- Called for the pointer position only when no widget before this one (the whole interface) claimed it.
function widget:IsAbove(x, y)
	seenX, seenY, seenAt = x, y, updates
	return false
end

-- Complete new lines of the touch log since the last call.
local function newTouchLines()
	local f = io.open(TOUCH, "r")
	if not f then
		return nil
	end
	local size = f:seek("end")
	if size < touchPos then -- the app started a new log
		touchPos, partial = 0, ""
	end
	if size == touchPos then
		f:close()
		return nil
	end
	f:seek("set", touchPos)
	local data = partial .. (f:read("*a") or "")
	touchPos = f:seek()
	f:close()
	local cut = data:match(".*\n()") -- just after the last newline
	if not cut then
		partial = data
		return nil
	end
	partial = data:sub(cut)
	return data:sub(1, cut - 1)
end

-- The map point under an X screen pixel. Off the map (the void around it) the view ray meets the plane at the height
-- of the ground the camera looks at, so dragging keeps working there; nil only above the horizon.
local function ground(x, y)
	local _, vsy = spGetViewGeometry()
	local kind, pos = spTraceScreenRay(x, vsy - y, true)
	if kind == "ground" and pos then
		return pos[1], pos[3]
	end
	local dx, dy, dz = Spring.GetPixelDir(x, vsy - y)
	if not dy or dy > -0.01 then
		return nil
	end
	local cx, cy, cz = Spring.GetCameraPosition()
	local cs = spGetCameraState()
	local h = cs.px and cs.pz and Spring.GetGroundHeight(cs.px, cs.pz) or 0
	local t = (h - cy) / dy
	return cx + dx * t, cz + dz * t
end

local function applyTouch(lines)
	local dx, dz, rot, tilt = 0, 0, 0, 0
	for x0, y0, x1, y1 in lines:gmatch("pan (%S+) (%S+) (%S+) (%S+)") do
		local ax, az = ground(tonumber(x0), tonumber(y0))
		local bx, bz = ground(tonumber(x1), tonumber(y1))
		if ax and bx then
			-- grab: the point that was under the fingers moves with them
			dx, dz = dx + ax - bx, dz + az - bz
		end
	end
	for a in lines:gmatch("rot (%S+)") do
		rot = rot + (tonumber(a) or 0)
	end
	for t in lines:gmatch("tilt (%S+)") do
		tilt = tilt + (tonumber(t) or 0)
	end
	for lx, ly, rx, ry, lt, lb in lines:gmatch("pad (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)") do -- the last one counts
		pad.lx, pad.ly, pad.rx, pad.ry = tonumber(lx) or 0, tonumber(ly) or 0, tonumber(rx) or 0, tonumber(ry) or 0
		pad.lt, pad.lb = tonumber(lt) or 0, lb == "1"
	end
	if dx == 0 and dz == 0 and rot == 0 and tilt == 0 then
		return
	end
	local cs = spGetCameraState()
	if cs.px and cs.pz then
		cs.px, cs.pz = cs.px + dx, cs.pz + dz
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

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
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
		local distance = PAD_PAN_SPEED * (1 + (PAD_FAST_PAN - 1) * s.boost) * dt
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
		orders = orders + (spGetUnitCommandCount(unitID) or 0)
		if orders > QUEUE_LIMIT then
			break
		end
	end
	local draw = orders <= QUEUE_LIMIT
	if draw ~= queueDrawn then
		queueDrawn = draw
		Spring.LoadCmdColorsConfig("alwaysDrawQueue " .. (draw and 1 or 0))
	end
end

function widget:SelectionChanged()
	updateQueueDrawing()
end

-- Long sessions (the target is 30 fps for hours on a hot phone): once a minute the average frame rate and the slowest
-- frame go to the log, next to the app's thermal lines ("[perf]" in launcher.log).
local perfFrames, perfStart, perfLast, perfWorst = 0, nil, nil, 0
local function logPerf()
	local now = spGetTimer()
	if perfLast then
		local frame = spDiffTimers(now, perfLast)
		if frame > perfWorst then
			perfWorst = frame
		end
	end
	perfLast, perfFrames = now, perfFrames + 1
	if not perfStart then
		perfStart = now
		return
	end
	local seconds = spDiffTimers(now, perfStart)
	if seconds >= 60 then
		Spring.Echo(string.format("[bardroid-perf] %.1f fps over %.0f s, slowest frame %.0f ms, %d units", perfFrames / seconds,
			seconds, perfWorst * 1000, #(Spring.GetAllUnits() or {})))
		perfFrames, perfStart, perfWorst = 0, now, 0
	end
end

function widget:Shutdown()
	if not queueDrawn then
		Spring.LoadCmdColorsConfig("alwaysDrawQueue 1")
	end
end

-- The window size is the X server's job (BAR Droid's lorie patch 0003 keeps the game window the size of the screen).
-- Never Spring.SetWindowGeometry here: the engine clamps it to the screen size SDL saw at startup, so on the other
-- screen of a foldable it would shrink the window again.
local function applyFrameCap(hz, fps)
	if hz > 0 and fps > 0 then
		local fraction = math.max(1, math.floor(hz / fps + 0.5))
		if Spring.GetConfigInt("VSync", 0) ~= fraction or Spring.GetConfigInt("VSyncFraction", 1) ~= fraction then
			-- as BAR's options do: VSync = VSyncGame (1) x VSyncFraction
			Spring.SetConfigInt("VSyncGame", 1)
			Spring.SetConfigInt("VSyncFraction", fraction)
			Spring.SetConfigInt("VSync", fraction)
			Spring.Echo(string.format("[bardroid-touch] %d Hz display, %d fps cap: swap interval %d", hz, fps, fraction))
		end
	end
end

-- Whether the interface is under the pointer: the engine asks the widgets each frame (IsAbove) where the pointer is,
-- and this widget, last in line, only hears of it where nothing else answered.
local function updateHover()
	local mx, my = spGetMouseState()
	if mx ~= mouseX or my ~= mouseY then
		mouseX, mouseY, mouseSince = mx, my, updates
	end
	local onInterface
	if seenX == mx and seenY == my and seenAt >= mouseSince - 1 then
		onInterface = spIsAboveMiniMap(mx, my) and 1 or 0
	elseif updates - seenAt > 300 then
		onInterface = 0 -- no IsAbove for a long time (a window that hides the interface?): the map
	elseif updates - mouseSince >= 2 then
		onInterface = 1
	else
		return -- not asked yet for this position
	end
	local _, vsy = spGetViewGeometry()
	local line = string.format("%d %d %d\n", mx, vsy - my - 1, onInterface)
	local now = spGetTimer()
	if line == lastHover and hoverTimer and spDiffTimers(now, hoverTimer) < 1 then
		return
	end
	-- also once a second: the app takes an old file for "no widget" (the lobby)
	local f = io.open(HOVER, "w")
	if f then
		f:write(line)
		f:close()
	end
	lastHover, hoverTimer = line, now
end

function widget:Update(dt)
	updates = updates + 1
	local lines = newTouchLines()
	if lines then
		applyTouch(lines)
	end
	if padCamera then
		applyPad(dt)
	end
	updateHover()
	queueCheck = queueCheck - dt
	if queueCheck <= 0 then -- queues grow and shrink without a selection change
		queueCheck = 0.5
		updateQueueDrawing()
	end
	logPerf()

	screenCheck = screenCheck - dt
	if screenCheck <= 0 then
		screenCheck = 0.5
		local f = io.open(SCREEN, "r")
		if f then
			local s = f:read("*l")
			f:close()
			local w, h, hz, fps = (s or ""):match("^(%d+) (%d+) (%d+) (%d+)")
			if w then
				if s ~= lastScreen then
					lastScreen = s
					applyFrameCap(tonumber(hz), tonumber(fps))
				end
			end
		end
	end
end
