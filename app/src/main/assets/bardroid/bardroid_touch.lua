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
--   LuaUI/Config/bardroid_screen.txt  app, replaced:  <w> <h> <hz> <fps>        (X screen size, display Hz; fps 0)
--   LuaUI/Config/bardroid_hover.txt   widget:         <x> <y> <0|1>             (pointer position; 1 = on the interface)
--
-- The gamepad camera is for BAR's released game (online, spectating). It moves the camera the way Kailil's controller
-- build (BAR Controller Support v0.8.5, the app's singleplayer game) does: left stick pans (LT up to 2.75x faster),
-- right stick turns (x) and zooms (y; with LB held it tilts instead). In that game v0.8.5 reads the pad itself, so
-- this part stays off there.

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

-- v0.8.5's camera defaults (gui_controller_camera_test.lua)
local PAD_PAN_SPEED, PAD_FAST_PAN = 1400, 2.75
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

-- Camera moves the fingers asked for and the camera has not made yet: pan (map units), twist and tilt (radians), zoom
-- (log of the distance factor) about the map point under the pinch.
local pending = { dx = 0, dz = 0, rot = 0, tilt = 0, zoom = 0, pivotX = nil, pivotZ = nil }

local function readTouch(lines)
	local p = pending
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
		cs.px, cs.pz = cs.px + dx, cs.pz + dz
		-- spread the fingers: closer; the map point under the pinch stays under it
		local key = cs.dist and "dist" or cs.height and "height"
		if zoom ~= 0 and key then
			local low = key == "dist" and zoomMinDistance or MIN_OVERHEAD_HEIGHT
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

-- Long sessions (the target is 30 fps for hours on a hot phone): once a minute the average frame rate, the slowest
-- frame and the frames of each second go to the log, next to the app's thermal lines ("[perf]" in launcher.log).
local perfFrames, perfStart, perfLast, perfWorst = 0, nil, nil, 0
local perSecond, secondStart, secondFrames = {}, nil, 0
local function logPerf()
	local now = spGetTimer()
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

function widget:Shutdown()
	if not queueDrawn then
		Spring.LoadCmdColorsConfig("alwaysDrawQueue 1")
	end
end

-- BAR's interface scale for the screen the game is on (Kailil, 2026-10-26: on the Fold's cover screen "EVERYTHING IS
-- TOO SMALL ... interface 2.0 is necessary", on the inner one "1.3 scale is good"). BAR's slider stops at 1.3, and
-- most of its widgets read ui_scale only when they load, so a fold or unfold that changes it reloads LuaUI, as BAR's
-- own slider does. launch-bar.sh sets it for the screen a game starts on, so a start needs no reload.
local UI_SCALE_COVER, UI_SCALE_INNER, UI_SCALE_COVER_UPRIGHT = 2.0, 1.3, 1.0
local function applyUiScale(w, h)
	local long, short = math.max(w, h), math.min(w, h)
	if short < 600 then
		return -- the floating window while the app is in the background (584x530): no reload on the way out and back
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
		readTouch(lines)
	end
	applyTouch(dt)
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
			local w, h = (s or ""):match("^(%d+) (%d+) ")
			if w and w .. "x" .. h ~= lastScreen then -- the size: the display's 60/120 Hz switches change the rest
				lastScreen = w .. "x" .. h
				applyUiScale(tonumber(w), tonumber(h))
			end
		end
	end
end
