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
--                                                     zoom <factor> <x> <y>     (touch-only mode: fingers spread by this
--                                                                                factor around x,y; > 1 = closer)
--   LuaUI/Config/bardroid_screen.txt  app, replaced:  <w> <h> <hz> <fps>        (X screen size, display Hz, frame cap)
--   LuaUI/Config/bardroid_hover.txt   widget:         <x> <y> <0|1> <cmd>       (pointer position; 1 = on the interface;
--                                                                                armed command: 0 none, 1 build, 2 other)

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
local spGetActiveCommand = Spring.GetActiveCommand
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers

local touchPos, partial = 0, ""
local lastScreen, screenCheck = nil, 0
local updates = 0
local seenX, seenY, seenAt = -1, -1, -1000
local mouseX, mouseY, mouseSince = -1, -1, 0
local lastHover, hoverTimer = nil, nil

local function fileSize(path)
	local f = io.open(path, "r")
	if not f then
		return 0
	end
	local size = f:seek("end")
	f:close()
	return size
end

-- BAR's interface scale on the screen at hand. BAR sizes its panels by the screen height times ui_scale, but its top
-- bar shares out the width: on the near-square inner display of a foldable (1456x1312) ui_scale 1.4 pushes the top
-- bar's buttons over its own counters. BAR offers ui_scale up to 1.3 on 16:9 screens, so a screen narrower than that
-- gets the same proportions: ui_scale <= 1.3 * (1080 / 1920) * width / height (0.81 inner, 1.4 stays on the cover).
-- The app's (or the player's) setting is the base; the file remembers it across the reload that applies a new scale
-- (BAR applies ui_scale with "luarules reloadluaui", as its options menu does).
local UISCALE = "LuaUI/Config/bardroid_uiscale.txt" -- "<base> <applied>"
local UI_FIT = 1.3 * 1080 / 1920
local UI_SETTLE_SECONDS = 1.5 -- a fold passes through in-between sizes: wait for the last one
local uiPending

local function fitUiScale()
	local vsx, vsy = spGetViewGeometry()
	if vsx < 200 or vsy < 200 then
		return
	end
	local current = Spring.GetConfigFloat("ui_scale", 1)
	local base, applied
	local f = io.open(UISCALE, "r")
	if f then
		base, applied = (f:read("*l") or ""):match("^([%d%.]+) ([%d%.]+)")
		f:close()
		base, applied = tonumber(base), tonumber(applied)
	end
	if not (applied and math.abs(current - applied) < 0.005) then
		base = current -- set by the app at launch, or by the player in BAR's options
	end
	local want = math.floor(math.min(base, UI_FIT * vsx / vsy) * 100) / 100
	f = io.open(UISCALE, "w")
	if f then
		f:write(string.format("%.2f %.2f\n", base, want))
		f:close()
	end
	if math.abs(want - current) >= 0.02 then
		Spring.Echo(string.format("[bardroid-touch] %dx%d screen: ui_scale %.2f -> %.2f (setting %.2f)", vsx, vsy, current, want, base))
		Spring.SetConfigFloat("ui_scale", want)
		Spring.SendCommands("luarules reloadluaui")
	end
end

function widget:Initialize()
	touchPos = fileSize(TOUCH) -- old gestures are not replayed
	local cs = spGetCameraState()
	Spring.Echo(string.format("[bardroid-touch] camera %s (rx %s, ry %s)", tostring(cs.name), tostring(cs.rx), tostring(cs.ry)))
	fitUiScale()
end

function widget:ViewResize()
	uiPending = spGetTimer() -- fold / unfold: fit the scale once the size has settled
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
-- of the ground the camera looks at, so dragging and pinching keep working there; nil only above the horizon.
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

-- Zoom by this factor (> 1 = closer) keeping the ground point under X screen pixel (x, y) where it is on screen: the
-- camera target moves towards that point as the distance shrinks (a scaling centred on it keeps its direction).
local function applyZoom(factor, x, y)
	local cs = spGetCameraState()
	if cs.dist then -- spring camera (BAR's default)
		local gx, gz = ground(x, y)
		local before = cs.dist
		cs.dist = before / factor
		spSetCameraState(cs, 0)
		local after = spGetCameraState() -- the engine clamps the distance
		local k = after.dist and before > 0 and after.dist / before or 1
		if gx and k ~= 1 and after.px and after.pz then
			after.px = gx + (cs.px - gx) * k
			after.pz = gz + (cs.pz - gz) * k
			spSetCameraState(after, 0)
		end
	elseif cs.height then -- overhead camera
		cs.height = cs.height / factor
		spSetCameraState(cs, 0)
	end
end

local function applyTouch(lines)
	local zoom, zx, zy = 1, nil, nil
	for f, x, y in lines:gmatch("zoom (%S+) (%S+) (%S+)") do
		zoom, zx, zy = zoom * (tonumber(f) or 1), tonumber(x), tonumber(y)
	end
	if zoom ~= 1 and zx and zy then
		applyZoom(zoom, zx, zy)
	end
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
	-- what a one-finger drag on the map does in touch-only mode depends on the armed command (RtsTouch)
	local _, cmdID = spGetActiveCommand()
	local armed = not cmdID and 0 or cmdID < 0 and 1 or 2
	local pregame = WG["pregame-build"]
	if armed == 0 and pregame and pregame.getPreGameDefID and (pregame.getPreGameDefID() or 0) > 0 then
		armed = 1 -- a building picked before the game starts (BAR's pregame queue)
	end
	local line = string.format("%d %d %d %d\n", mx, vsy - my - 1, onInterface, armed)
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
	updateHover()

	if uiPending and spDiffTimers(spGetTimer(), uiPending) >= UI_SETTLE_SECONDS then
		uiPending = nil
		fitUiScale()
	end

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
