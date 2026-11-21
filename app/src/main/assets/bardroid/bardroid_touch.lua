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
--                                                     spot <x> <y> | spot none | spot placed | spot given  (a building's spot for
--                                                                               the build menu's PLACE button: bardroid_buildmenu.lua)
--                                                     nudge <dx> <dy>           (the waiting building moved by that many
--                                                                               pixels, y down)
--                                                     grid held | grid free     (the app holds a GRID's build drag down:
--                                                                               PLACE lit)
--                                                     src <touch|mouse|keyboard|pad>  (the input used, when it changes)
--   LuaUI/Config/bardroid_screen.txt  app, replaced:  <w> <h> <hz> <fps>        (X screen size, display Hz; fps 0)
--   LuaUI/Config/bardroid_hover.txt   widget:         <x> <y> <0|1|2|3>         (pointer position; 1 = on the interface,
--                                                                               2 = a BAR window open that scrolls,
--                                                                               3 = a BAR button panel with no IsAbove:
--                                                                               WG.BarDroidTapPanels)
--   LuaUI/Config/bardroid_overlay.txt widget:         <0|1>                     (1: BAR's lobby over the game; the app
--                                                                               hides the pointer for fingers then)
--   LuaUI/Config/bardroid_catchup.txt widget:         <frame> <server frame or 0> <speed>  (only while catching up
--                                                                               with a running game: the engine then
--                                                                               draws nothing)
--
-- The gamepad camera, with v0.8.5's camera speeds and easing: the app's pad lines say pan (lx, ly), turn (rx), zoom
-- (ry; tilt with lb) and boost (lt). With a free pointer the app makes the left stick the pointer, so its lines carry
-- the right stick: a pan, or with LB held a turn and a zoom (ControllerBridge). (Until 2026-11-21 off in the controller
-- game, v0.8.5's own: that check took BAR's own developer game, "$VERSION", for it, and the pad moved no camera there.)

function widget:GetInfo()
	return {
		name = "BAR Droid touch camera",
		desc = "Touch camera and interface scale from the BAR Droid app",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		-- last of all: IsAbove reaches this widget only where no other widget claims the pointer
		layer = 1000000,
		enabled = true,
		-- (BAR's own widget handler, granted to the game's widgets only (the phone engine): a turn's new interface scale
		-- loads only the widgets that read it again, rescaleWidgets; a user widget gets none and reloads the interface)
		handler = true,
	}
end

local TOUCH = "LuaUI/Config/bardroid_touch.txt"
local SCREEN = "LuaUI/Config/bardroid_screen.txt"
local HOVER = "LuaUI/Config/bardroid_hover.txt"
-- BAR's lobby over the game ("LobbyOverlayActive1" / "0", the top bar's Lobby button), for the app: "1" or "0"
-- (RtsTouch hides the pointer for fingers there, as in the lobby; widget:RecvLuaMsg)
local OVERLAY = "LuaUI/Config/bardroid_overlay.txt"
local lobbyOver = false -- (BAR's lobby is over the game now: the fingers' camera moves dropped, readTouch)
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
local spIsGUIHidden = Spring.IsGUIHidden
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers

-- v0.8.5's camera defaults (gui_controller_camera_test.lua); the pan 30% slower (Kailil, 2026-10-29, both controller
-- modes: v0.8.5's own too)
local PAD_PAN_SPEED, PAD_FAST_PAN, PAD_FAST_ZOOM = 1400 * 0.7, 2.75, 3
local PAD_ZOOM_SCALE, PAD_ROTATION, PAD_PITCH = 0.9, 3.0, 3.0
local PAD_STICK_CURVE, PAD_TRIGGER_CURVE, PAD_SMOOTHING = 1.175, 1.075, 0.06
local PAD_STICK_DEADZONE, PAD_TRIGGER_DEADZONE = 5000, 3000
local MIN_SPRING_DISTANCE, MIN_OVERHEAD_HEIGHT, MIN_CAMERA_RX, MAX_CAMERA_RX = 20, 60, 1.0, 3.05
-- the engine's limits for the Spring camera's distance (SpringController.cpp), set in Initialize
local zoomMinDistance, zoomMaxDistance = MIN_SPRING_DISTANCE, 100000

local touchPos, partial = 0, ""
local lastScreen, screenCheck, screenFast = nil, 0, 4
local updates = 0
local seenX, seenY, seenAt = -1, -1, -1000
local mouseX, mouseY, mouseSince = -1, -1, 0
local hoverTimer = nil

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

-- BAR's Cursor widget (gui_cursor.lua) replaces its animated cursors after the start, one a frame; on a phone each takes
-- 0.2-0.3 s in the engine, and a skirmish's first ~8 s stuttered at 2-5 fps (dev phone, 2026-11-02). In a game with no
-- pregame the same cursors are loaded here, while the game loads (its loading screen ~8 s longer); BAR's own replacements
-- then find them in place and cost nothing. A game with one (start positions chosen in the game: online) loads them in
-- the pregame as before (Kailil, 2026-11-02: "Yes whatever you recommend"). BAR test-31992 does the same in its own
-- Initialize ("while pendingCursorDir do"): then a second pass here only cost the loading screen 631 ms (dev phone,
-- 2026-11-18), so it runs only for a game whose Cursor widget does not (an older BAR: a replay's own version).
local BAR_DEFERRED_CURSORS = { "cursorareaattack", "cursorattack", "cursorbuildbad", "cursorbuildgood", "cursorcapture",
	"cursorcentroid", "cursorwait", "cursortime", "cursorunload", "cursordwatch", "cursordgun", "cursorfight",
	"cursorgather", "cursordefend", "cursorpickup", "cursorrepair", "cursorrevive", "cursorrestore", "cursormove",
	"cursorpatrol", "cursorreclamate", "cursorselfd", "cursornumber", "cursorsettarget", "cursorupgmex", "cursorareamex" }
local function preloadCursors()
	local cursors = WG.cursors
	if not (cursors and cursors.getcursor) or Spring.GetGameFrame() > 0 or Game.startPosType == 2 then
		return
	end
	local barCursor = VFS.LoadFile("LuaUI/Widgets/gui_cursor.lua")
	if barCursor and barCursor:find("while pendingCursorDir do", 1, true) then
		Spring.Echo("[bardroid-touch] BAR's cursors loaded by BAR's Cursor widget")
		return
	end
	-- the set's size as BAR's widget picks it: the nearest of the set's folders to its size for the screen
	local set = cursors.getcursor()
	local ssx, ssy = Spring.GetScreenGeometry()
	local want = 100 * (0.6 + (ssx * ssy / 10000000)) * (Spring.GetConfigFloat("cursorsize", 1) or 1)
	local best, bestD
	for _, subdir in ipairs(VFS.SubDirs("anims") or {}) do
		local s, size = subdir:gsub("\\", "/"):match("anims/([^_/]+)_([^/]+)/?$")
		size = tonumber(size)
		if s == set and size and (not bestD or math.abs(want - size) < bestD) then
			best, bestD = size, math.abs(want - size)
		end
	end
	if not best then
		return
	end
	local t0 = Spring.GetTimer()
	for _, name in ipairs(BAR_DEFERRED_CURSORS) do
		Spring.ReplaceMouseCursor(name, set .. "_" .. best .. "/" .. name, false)
	end
	Spring.Echo(string.format("[bardroid-touch] BAR's cursors (%s_%d) loaded with the game: %d ms", set, best,
		Spring.DiffTimers(Spring.GetTimer(), t0) * 1000))
end

local loadedGame = { pending = false } -- (a saved game loaded: checkLoadedGame; one table for the locals)
function widget:Initialize()
	WG.BarDroidTapPanels = WG.BarDroidTapPanels or {} -- (overBarInterface: BAR's button panels with no IsAbove)
	-- A text field of the game's tapped (the Settings copy's search): Android's keyboard asked for, as the lobby's text
	-- boxes ask (bardroid_lobby_ask.txt, RtsTouch lobbyAskStep, read for a second after a finger lifts in a game). Each
	-- ask its own id: the app acts on a new one only.
	local askSession, askCount = math.random(100000, 999999), 0
	WG.BarDroidAskKeyboard = function()
		askCount = askCount + 1
		local f = io.open("LuaUI/Config/bardroid_lobby_ask.txt", "w")
		if f then
			f:write(string.format("keyboard g%d-%d\n", askSession, askCount))
			f:close()
		end
	end
	writeWhole(OVERLAY, "0\n") -- (one left at "1" by a game that ended under the lobby)
	WG.BarDroidLobbyOver = false
	-- (and BAR's lobby asked whether it is over the game: BAR says so only as it opens or closes, and a fold or turn
	-- reloads LuaUI between the two; the app's lobby widget answers with BAR's own "LobbyOverlayActive1")
	if Spring.SendLuaMenuMsg then
		Spring.SendLuaMenuMsg("BarDroidOverlay?")
	end
	if Spring.GetGameState then
		local ok, doneLoading, savedGame = pcall(Spring.GetGameState)
		loadedGame.pending = ok and savedGame == true and doneLoading == false
	end
	preloadCursors()
	touchPos = fileSize(TOUCH) -- old gestures are not replayed
	pcall(os.remove, "LuaUI/Config/bardroid_catchup.txt") -- left by a reload while catching up: written again if still behind
	pcall(os.remove, "LuaUI/Config/bardroid_game.txt") -- (the controller game's mark, read by no one since 2026-11-21)
	zoomMinDistance = math.max(Spring.GetConfigFloat("CamSpringMinZoomDistance", 0.1) or 0.1, 0.1)
	zoomMaxDistance = math.max(Game.mapSizeX, Game.mapSizeZ) * 1.333
	local cs = spGetCameraState()
	Spring.Echo(string.format("[bardroid-touch] camera %s (rx %s, ry %s), gamepad camera on", tostring(cs.name),
		tostring(cs.rx), tostring(cs.ry)))
end

-- Called for the pointer position only when no widget before this one (the whole interface) claimed it.
function widget:IsAbove(x, y)
	seenX, seenY, seenAt = x, y, updates
	return false
end

-- Complete new lines of the touch log since the last call. One handle across frames: an open is a path system call,
-- which proot traps (two ptrace stops and a path translation) on the phone, once a frame. The app truncates the same
-- file for a new log (the size shrinks); opened again every TOUCH_REOPEN updates in case the file itself was replaced
-- (every 60 was 0.6-0.9 % of a late 8v8's real time on the dev phone with nobody touching, 2026-11-06: the opens)
local TOUCH_REOPEN = 600
local TOUCH_SIZE_EVERY = 30 -- updates: the log's size looked at (a new, shorter log), newTouchLines
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
	-- The size only every TOUCH_SIZE_EVERY updates (the app started a new log when it shrank): seeking to the end asks
	-- for it with fstat, which proot traps to fake the file's owner, two ptrace stops: every frame that was 0.6 % of a
	-- late 8v8's real time on the dev phone with nothing written (2026-11-06). Each frame only reads on from where the
	-- last read ended (a seek there clears the end-of-file mark; neither is trapped).
	if updates % TOUCH_SIZE_EVERY == 0 then
		local size = f:seek("end")
		if not size then -- (the handle went bad: open it again next time)
			f:close()
			touchFile = nil
			return nil
		end
		if size < touchPos then -- the app started a new log
			touchPos, partial = 0, ""
		end
	end
	if not f:seek("set", touchPos) then
		return nil
	end
	local more = f:read("*a")
	if not more or more == "" then
		return nil
	end
	touchPos = touchPos + #more
	local data = partial .. more
	local cut = data:match(".*\n()") -- just after the last newline
	if not cut then
		partial = data
		return nil
	end
	partial = data:sub(cut)
	return data:sub(1, cut - 1)
end

-- Where the view ray through X screen pixel (x, y) meets the level plane at height h; nil above the horizon.
-- (GetPixelDir counts y from the top, as X does, unlike TraceScreenRay: given vsy - y it mirrored the void's rows, and a
-- drag up or down past the map's edge moved the map against the finger; Kailil, 2026-11-03: "super inconvenient")
local function planePoint(x, y, h)
	local dx, dy, dz = Spring.GetPixelDir(x, y)
	if not dy or dy > -0.01 then
		return nil
	end
	local cx, cy, cz = Spring.GetCameraPosition()
	local t = (h - cy) / dy
	return cx + dx * t, cz + dz * t
end

-- The map point under an X screen pixel, and its height when it is on the map. Off the map (the void around it) the
-- view ray meets the plane at the height of the ground the camera looks at (or at height h when given, which skips the
-- map), so dragging keeps working there; nil only above the horizon.
local function ground(x, y, h)
	if not (x and y) then
		return nil -- a line that is not numbers
	end
	if not h then
		local _, vsy = spGetViewGeometry()
		local kind, pos = spTraceScreenRay(x, vsy - y, true)
		if kind == "ground" and pos then
			return pos[1], pos[3], pos[2]
		end
		-- (the height the camera itself looks at, its state's py: BAR test-31992 on the 2026.09.03 engines switches the
		-- spring camera to smooth-mesh height tracking, where that height is the smoothed surface's, not the ground's;
		-- with the ground's the void's point under a finger drifted as the camera moved, touch-phone-test 311 and 904 off)
		local cs = spGetCameraState()
		h = cs.py or (cs.px and cs.pz and Spring.GetGroundHeight(cs.px, cs.pz)) or 0
	end
	local px, pz = planePoint(x, y, h)
	return px, pz
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
		-- (and the pad's first person ends with it: the pad gone (its battery, Bluetooth) left the ride on, the selection
		-- cleared every frame, nothing a finger could end it with; release overhaul audit, 2026-11-21)
		local rider = WG.BarDroidPadFP
		if rider and rider.active() then
			rider.stop()
		end
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
	elseif lobbyOver then -- (BAR's lobby over the game: two fingers on it moved the camera behind it)
		lines = lines:gsub("pan [^\n]*", ""):gsub("zoom [^\n]*", ""):gsub("rot [^\n]*", ""):gsub("tilt [^\n]*", "")
	end
	for x0, y0, x1, y1 in lines:gmatch("pan (%S+) (%S+) (%S+) (%S+)") do
		x0, y0, x1, y1 = tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1)
		-- One drag's lines chain, each from the last one's end (RtsTouch panTo, two fingers' middle, a fling): the map point
		-- its first line grabbed is held. With the
		-- finger over the void the move left is set outright to bring that point under it from where the camera stands
		-- now (applyTouch again for a moment after: holdAgain). Line by line the map fell behind the finger there: the
		-- camera sinks as its target goes in (smooth-mesh tracking: its focus height 236 to 47 over that drag), and a
		-- step at the far, shallow rows shrinks with it; from the map onto the void sideways, 24 lines one a frame left
		-- the grabbed point 1402 off after 2077 (dev phone, 2026-11-18)
		local now = Spring.GetTimer()
		local chained = p.chainX and x0 and y0 and math.abs(x0 - p.chainX) < 0.6 and math.abs(y0 - p.chainY) < 0.6
			and Spring.DiffTimers(now, p.chainT) < 1
		local ax, az, ah = ground(x0, y0)
		local bx, bz, bh = ground(x1, y1)
		if not chained then
			-- (only a map point is held: a drag that begins over the void keeps the void's plane at the camera's focus
			-- height of the moment, as before; held at its first height it ended 500 off in touch-phone-test's drag along
			-- the edge, where the camera's height changes under it)
			p.holdX, p.holdZ, p.holdH = nil, nil, nil
			if ax and ah then
				p.holdX, p.holdZ, p.holdH = ax, az, ah
			end
		end
		p.chainX, p.chainY, p.chainT, p.holdVoid = x1, y1, now, nil
		if bx and not bh and p.holdX then
			local hx, hz = ground(x1, y1, p.holdH)
			if hx then -- (the whole move left, from where the camera is: it replaces what was pending)
				p.dx, p.dz = p.holdX - hx, p.holdZ - hz
				p.holdVoid = true
				ax, bx = nil, nil -- (done: not added again below)
			end
		end
		if ax and bx and (ah == nil) ~= (bh == nil) then
			-- the finger crossed the map's edge: both ends on the level plane at the map end's height (the map point and
			-- the void's plane point at the height the camera looks at made a jump where the edge's ground stands higher or
			-- lower than that)
			ax, az = ground(x0, y0, ah or bh)
			bx, bz = ground(x1, y1, ah or bh)
		end
		if x0 and y0 and x1 and y1 and not (ax and bx) and not p.holdVoid then
			-- over the sky (a camera tilted up to the horizon): the same drag as made in the middle of the screen (nothing
			-- moved there before)
			local vsx, vsy = spGetViewGeometry()
			ax, az = ground(vsx / 2, vsy / 2)
			bx, bz = ground(vsx / 2 + x1 - x0, vsy / 2 + y1 - y0)
		end
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
	-- words said for a ping's label (the app's VoiceChat): the touch dock's PING held (bardroid_portrait.lua takes them
	-- when it asked), else the pad's LB held + RB three times, bardroid_pad.lua's ping
	for hex in lines:gmatch("voiceping (%x+)") do
		local text = hex:gsub("%x%x", function(h)
			return string.char(tonumber(h, 16))
		end)
		local Pt = WG.BarDroidPortrait
		if Pt and Pt.voicePing and Pt.voicePing(text) then -- luacheck: ignore 542
		elseif WG.BarDroidPad and WG.BarDroidPad.voicePing then
			WG.BarDroidPad.voicePing(text)
		end
	end
	-- words said for the chat (the app's VoiceChat), hex-encoded UTF-8: to bardroid_chat.lua, as a message typed.
	-- "voicegame" while this widget runs (the lobby takes only "voice"), "voice" from a game that has just started
	for kind, hex in lines:gmatch("(voice%a*) (%x+)") do
		if kind == "voice" or kind == "voicegame" then -- (not voiceping, above)
			local text = hex:gsub("%x%x", function(h)
				return string.char(tonumber(h, 16))
			end)
			if WG.bardroidChat and WG.bardroidChat.voice then
				WG.bardroidChat.voice(text)
			elseif text:find("%S") then -- (BAR Droid chat off: to allies, BAR's 127 bytes, never half a character)
				if #text > 127 then
					local after = text:byte(128)
					text = text:sub(1, 127)
					if after >= 128 and after < 192 then
						text = text:gsub("[\192-\255][\128-\191]*$", "")
					end
				end
				Spring.SendAllyChat(text)
			end
		end
	end
	for name in lines:gmatch("act (%S+)") do
		local action = ACTIONS[name]
		-- (BAR's lobby over the game: the gestures on it are the lobby's, which reads them itself; a two-finger swipe there
		-- picked every unit, armed FIGHT or stopped them behind the lobby, a three-finger one moved the camera. With no
		-- game the app sends none of them; 2026-11-17)
		if lobbyOver and name ~= "fingers" then -- luacheck: ignore 542
		elseif WG.BarDroidPadSpeed and WG.BarDroidPadSpeed.act(name) then -- luacheck: ignore 542 (the path speed tuner's)
		elseif action then
			action()
		elseif WG.BarDroidPad then
			WG.BarDroidPad.act(name)
		end
	end
	-- a building picked: the spot a tap or a drag picked for the build menu's PLACE button, a nudge of it, a GRID held
	-- (bardroid_buildmenu.lua), in the order the app sent them; a frame's nudges summed
	local b = WG.bardroidBuildmenu
	if b and b.droidSpot and (lines:find("spot", 1, true) or lines:find("nudge ", 1, true) or lines:find("grid ", 1, true)) then
		local nx, ny = 0, 0
		-- (the newest "spotto" not applied yet: a drag sends about four a frame, each a ground trace, the building placed
		-- again and the place file written; the newest alone is where it goes, one a frame; review 2026-11-16)
		local tx, ty
		local function applySpotto()
			if tx then
				local _, vy = Spring.GetViewGeometry()
				local _, pos = Spring.TraceScreenRay(tx, vy - ty - 1, true)
				if pos then
					b.droidSpot(tx, ty, false)
					-- (held at the dock's top edge: the build grid's snap could put the building's middle a square
					-- down, under the dock, where no click reaches it, and the build menu dropped the spot, PLACE with
					-- nothing to click (dock-phone-test, 1 run in 2, 2026-11-19): a few pixels higher, up to 48, until
					-- PLACE has a pixel; none, the spot where it was)
					if b.droidSpotPixel and not b.droidSpotPixel() then
						local found = false
						for up = 4, 48, 4 do
							local _, p2 = Spring.TraceScreenRay(tx, vy - (ty - up) - 1, true)
							if not p2 then
								break
							end
							b.droidSpot(tx, ty - up, false)
							if b.droidSpotPixel() then
								found = true
								break
							end
						end
						if not found then
							b.droidSpot(tx, ty, false)
						end
					end
				end
				tx, ty = nil, nil
			end
		end
		local function flushNudges()
			if (nx ~= 0 or ny ~= 0) and b.droidNudge then
				b.droidNudge(nx, ny)
			end
			nx, ny = 0, 0
		end
		local function flush() -- (in the order they came: a spotto waits only while no nudge follows it)
			applySpotto()
			flushNudges()
		end
		for line in lines:gmatch("[^\n]+") do
			local kind, args = line:match("^(%a+) (.*)$")
			if kind == "nudge" then
				applySpotto()
				local x, y = args:match("^(%S+) (%S+)")
				nx, ny = nx + (tonumber(x) or 0), ny + (tonumber(y) or 0)
			elseif kind == "spot" then
				flush()
				local x, y = args:match("^(%S+) (%S+)")
				-- ("given": PLACE's click went off and the building is not to be picked again, RtsTouch.sendPlaced: a
				-- plain click without QUEUE, BAR lets go of it; QUEUE's Shift keeps it picked anyway)
				if (args == "placed" or args == "given") and b.droidPanel then
					-- (PLACE on a spot BAR refuses, a slope or a unit's footprint: a word, as the building drawn red and
					-- nothing queued looked like the place cancelled; Kailil, 2026-11-10, a Bot Lab)
					local _, spot = b.droidPanel()
					local _, cmdID = Spring.GetActiveCommand()
					if spot and cmdID and cmdID < 0 then
						local facing = Spring.GetBuildFacing and Spring.GetBuildFacing() or 0
						local bx, by, bz = Spring.Pos2BuildPos(-cmdID, spot[1], spot[2], spot[3], facing)
						local P = WG.BarDroidPad
						if bx and Spring.TestBuildOrder(-cmdID, bx, by, bz, facing) == 0 and P and P.say then
							-- (2.5 s, as the pad's other notes that ask something of the player: at its 1.3 s it was
							-- gone before the eyes came back from the dock to the map; dev phone 2026-11-19)
							P.say("CAN'T BUILD THERE: PICK ANOTHER SPOT", nil, 2.5)
							Spring.Echo("[bardroid-touch] PLACE on a blocked spot") -- (tools)
						end
					end
				end
				b.droidSpot(tonumber(x), tonumber(y), args == "placed")
				-- (a tap's spot: the pointer on its build square, so BAR's blueprint is there; rounded apart the two stood
				-- a square from each other until the next move, the app's square beside BAR's, dev phone 2026-11-13)
				local s
				if b.droidPanel then
					s = select(2, b.droidPanel())
				end
				local _, cmdID = Spring.GetActiveCommand()
				-- (the pixel PLACE clicks, which builds on the spot's square: zoomed far out the rounded one stood a
				-- square off, BAR's blueprint beside the building PLACE built; review 2026-11-15)
				local px, py
				if tonumber(x) and s and cmdID and cmdID < 0 and b.droidSpotPixel then
					px, py = b.droidSpotPixel()
				end
				if px then
					Spring.WarpMouse(px, py)
				-- (the rounded pixel only with an older copy: this one's nil means the spot is under a panel, and the
				-- pointer went onto it, BAR's hover there; review 2026-11-16)
				elseif not b.droidSpotPixel and tonumber(x) and s and cmdID and cmdID < 0 then
					local bx, by, bz = Spring.Pos2BuildPos(-cmdID, s[1], s[2], s[3], Spring.GetBuildFacing())
					local wx, wy, wz = Spring.WorldToScreenCoords(bx, by, bz)
					if wz and wz <= 1 then
						Spring.WarpMouse(math.floor(wx + 0.5), math.floor(wy + 0.5))
					end
				end
			elseif kind == "spotto" then -- (a building dragged: the spot under the pointer, BAR's blueprint; over the sky
				-- or past the map's edge it stays where it was: applySpotto)
				flushNudges()
				local x, y = args:match("^(%S+) (%S+)")
				x, y = tonumber(x), tonumber(y)
				if x and y then
					tx, ty = x, y
				end
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
	-- (a drag held over the void, readTouch: its point brought under the finger again from where the camera is now, for
	-- half a second after its last line while the camera's height settles; not while a pinch, twist or tilt is under way)
	if p.holdVoid and p.chainT and p.zoom == 0 and p.rot == 0 and p.tilt == 0
		and Spring.DiffTimers(Spring.GetTimer(), p.chainT) < 0.5 then
		local hx, hz = ground(p.chainX, p.chainY, p.holdH)
		if hx then
			p.dx, p.dz = p.holdX - hx, p.holdZ - hz
		end
	end
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

local padDgunLive = false -- the pad's sticks moved in the D-gun mode last frame
local function applyPad(dt)
	local s = smooth
	local rider = WG.BarDroidPadFP
	if rider and rider.active() then -- (first person on the pad: bardroid_padfp.lua has the sticks)
		rider.sticks(stick(pad.lx), stick(pad.ly), stick(pad.rx), stick(pad.ry))
		return
	end
	local dgun = WG.BarDroidPadDgun
	if dgun and dgun.active() then -- (v0.8.5's D-gun mode: bardroid_pad.lua has the sticks, the camera stays)
		-- (the pad's sticks while they move and their rest once: else the portrait dock's touch sticks, which zeros
		-- every frame from here took away, bardroid_portrait.lua)
		local live = pad.lx ~= 0 or pad.ly ~= 0 or pad.rx ~= 0 or pad.ry ~= 0
		if live or padDgunLive then
			dgun.sticks(stick(pad.lx), stick(pad.ly), stick(pad.rx), stick(pad.ry))
		end
		padDgunLive = live
		s.panX, s.panY, s.rotate, s.pitch, s.zoom = 0, 0, 0, 0, 0
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
		-- (LT as for the pan: v0.8.5's zoomBoostMultiplier; a stall's long frame must not turn the scale over)
		local scale = math.max(0.2, 1 - s.zoom * (1 + (PAD_FAST_ZOOM - 1) * s.boost) * PAD_ZOOM_SCALE * 3 * dt)
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
local behindNow, runningFast -- (updateCatchup: game frames behind by GameProgress, nil before it; faster than its speed)
-- (for the widgets that give orders by themselves: a rejoin replays the game, their callins fire for every past frame
-- and their orders land at the live one; bardroid_retreat.lua stands down meanwhile, review 2026-11-15. Not only while
-- the no-drawing mode is on: it gives up on a game it gains nothing on, minutes behind, and starts 2 s in; still
-- behind by more than 5 s, or running faster than its speed, is catching up too; review 2026-11-16)
WG.BarDroidCatchingUp = function()
	return catchup ~= nil or (behindNow or 0) > 5 * 30 or runningFast == true
end

-- The late-game drop (Kailil, 2026-11-06: "Allow 50 percent resolution as the minimum late game drop ... Upscaling should
-- be doing the heavy lifting", then, having watched 50 %: "keep it at 70 percent res drop as the minimum instead"; the
-- app's setting "Lower the resolution when fps drops", Prefs.lateDrop): from
-- game minute DROP_AFTER on, DROP_WINDOW seconds of drawn frames under DROP_BELOW a second ask the app for the next step
-- down (SCALE: "scale <percent>" of the render resolution's lines; the app keeps 70 % of the full lines at least and
-- shrinks the X screen as a fold does, SGSR enlarging it). A step stays only if the next DROP_WINDOW seconds (after
-- DROP_SETTLE for the resize) are DROP_GAIN faster: else it goes back one step and the game keeps that (the GPU was not
-- what held it back). A size the view does not take (the setting off) ends it for the game too.
local SCALE = "LuaUI/Config/bardroid_scale.txt"
local DROP_STEPS = { 100, 85, 70 }
local DROP_AFTER, DROP_WINDOW, DROP_SETTLE, DROP_BELOW, DROP_GAIN, DROP_KEEP = 180, 20, 8, 27, 1, 10
local drop = { step = 1, window = {}, at = nil, before = nil, view = nil, keptAt = nil, locked = false }

local function dropWrite(t)
	writeWhole(SCALE, "scale " .. DROP_STEPS[drop.step] .. "\n")
	drop.keptAt = t
end

local function dropTo(step, t, why)
	local vsx, vsy = Spring.GetViewGeometry()
	drop.step, drop.at, drop.view = step, t, vsx * vsy
	for i = #drop.window, 1, -1 do
		drop.window[i] = nil
	end
	dropWrite(t)
	Spring.Echo(string.format("[bardroid-perf] resolution %d%% (%s)", DROP_STEPS[step], why))
end

local function dropSecond(frames, t)
	if not drop.started then -- (a new game starts at full size; a reload mid-game, as a fold makes, keeps the step)
		drop.started = true
		local f = Spring.GetGameFrame() > 300 and io.open(SCALE, "r")
		local percent = f and tonumber((f:read("*l") or ""):match("^scale (%d+)$"))
		if f then
			f:close()
		end
		for i, p in ipairs(DROP_STEPS) do
			if p == percent then
				drop.step, drop.keptAt = i, t
			end
		end
		if drop.step == 1 then
			pcall(os.remove, SCALE)
		end
	end
	if drop.locked then
		return
	end
	if drop.step > 1 and spDiffTimers(t, drop.keptAt) >= DROP_KEEP then -- (the app's sign that it still holds)
		dropWrite(t)
	end
	local _, _, paused = Spring.GetGameSpeed()
	if paused or catchup or Spring.GetGameFrame() < DROP_AFTER * 30 then
		return
	end
	if drop.at and spDiffTimers(t, drop.at) < DROP_SETTLE then
		return
	end
	local w = drop.window
	w[#w + 1] = frames
	if #w > DROP_WINDOW then
		table.remove(w, 1)
	end
	if #w < DROP_WINDOW then
		return
	end
	local sum = 0
	for i = 1, #w do
		sum = sum + w[i]
	end
	local fps = sum / #w
	if drop.before then -- (a step just made: kept only if it helped)
		local vsx, vsy = Spring.GetViewGeometry()
		if vsx * vsy == drop.view then
			drop.locked = true
			Spring.Echo("[bardroid-perf] resolution: the screen kept its size (the app's setting is off)")
			pcall(os.remove, SCALE)
			return
		end
		if fps < drop.before + DROP_GAIN then
			drop.locked = true
			dropTo(drop.step - 1, t, string.format("%.1f fps there against %.1f: no help, back and kept", fps, drop.before))
			return
		end
		drop.before = nil
	end
	if fps < DROP_BELOW and drop.step < #DROP_STEPS then
		drop.before = fps
		dropTo(drop.step + 1, t, string.format("%.1f fps over %d s", fps, DROP_WINDOW))
	end
end
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
		dropSecond(secondFrames / spDiffTimers(now, secondStart), now)
		secondStart, secondFrames = now, 0
	end
	if not perfStart then
		perfStart = now
		return
	end
	local seconds = spDiffTimers(now, perfStart)
	if seconds >= 60 then
		-- (and every Lua state's memory together: the engine's own memory was 2.4 GB in a 1v1 on the dev phone, 2026-11-04)
		local luaKB = Spring.GetLuaMemUsage and select(3, Spring.GetLuaMemUsage()) or 0
		Spring.Echo(string.format("[bardroid-perf] %.1f fps over %.0f s, slowest frame %.0f ms, %d units, Lua %.0f MB; each second: %s",
			perfFrames / seconds, seconds, perfWorst * 1000, #(Spring.GetAllUnits() or {}), luaKB / 1024, table.concat(perSecond, " ")))
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
		behindNow, runningFast = nil, false
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
	behindNow, runningFast = behind, fastChecks > 0 -- (WG.BarDroidCatchingUp)
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

-- Away from the game (a near-native port, 2026-11-10: a phone locked or another app in front mid-skirmish let the AI
-- play on unseen, and a touch player has no key to unpause with): the app writes "hidden" / "shown" to APP_FILE as
-- the game screen stops and starts (GameActivity). Hidden, a game with no other player in it (a skirmish against AIs,
-- a replay) is paused from GameFrame (Update stops while the engine does not draw); shown again, the pause this made
-- is lifted from Update a moment later (a paused game has no frames), never one the player made. Online it runs on.
local APP_FILE = "LuaUI/Config/bardroid_app.txt"
local away = { checkedAt = nil, paused = false, shownAt = nil }
local function appHidden()
	local f = io.open(APP_FILE, "r")
	if not f then
		return false
	end
	local s = f:read("*l")
	f:close()
	return s == "hidden"
end
local function aloneInGame()
	if Spring.IsReplay() then
		return true
	end
	local me = Spring.GetMyPlayerID()
	for _, pid in ipairs(Spring.GetPlayerList() or {}) do
		local _, active = Spring.GetPlayerInfo(pid, false)
		if pid ~= me and active then
			return false
		end
	end
	return true
end
local function awayWhileRunning(now) -- (GameFrame, twice a second of real time)
	if away.paused or (away.checkedAt and spDiffTimers(now, away.checkedAt) < 0.5) then
		return
	end
	away.checkedAt = now
	local _, _, paused = Spring.GetGameSpeed()
	if not paused and appHidden() and aloneInGame() then
		Spring.SendCommands("pause 1")
		away.paused = true
		Spring.Echo("[bardroid-touch] the game screen is hidden: paused until it is back")
	end
end
local function awayBack() -- (Update: the screen is shown)
	if not away.paused then
		return
	end
	local now = spGetTimer()
	if appHidden() then
		away.shownAt = nil
		return
	end
	away.shownAt = away.shownAt or now
	if spDiffTimers(now, away.shownAt) >= 0.8 then -- (the picture back first)
		away.paused, away.shownAt = false, nil
		local _, _, paused = Spring.GetGameSpeed()
		if paused then
			Spring.SendCommands("pause 0")
		end
		Spring.Echo("[bardroid-touch] the game screen is back: running again")
	end
end

-- A saved game loaded (the lobby's Load Game): BAR's game start does not run again, so nothing was picked and the
-- camera stood where the engine put it, away from the commander (dev phone, 2026-11-12, upright and sideways). As at a
-- start: the commander picked, the camera on it (upright above the dock), at the game's first frame. The engine's game
-- state says a saved game, and that it was still loading when this widget started: not the interface's own reloads (a
-- fold, its scale), which come with the game loaded. (BAR's "GameID" rules param is no help: the save brings back the
-- saved game's.) (loadedGame: declared above widget:Initialize, which asks the game state)
local function checkLoadedGame()
	loadedGame.pending = false
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		return
	end
	for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
		if ud and ud.customParams and ud.customParams.iscommander then
			Spring.SelectUnitArray({ u })
			local x, y, z = Spring.GetUnitPosition(u)
			local P = WG.BarDroidPortrait
			if P and P.active and P.active() and P.cameraTo then
				P.cameraTo(x, y, z)
			else
				Spring.SetCameraTarget(x, y, z, 0.5)
			end
			Spring.Echo("[bardroid-touch] a saved game loaded: the commander picked, the camera on it")
			return
		end
	end
end

local function gameFrame(frame)
	local now = spGetTimer()
	if loadedGame.pending then
		checkLoadedGame()
	end
	awayWhileRunning(now)
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

local tooltipApi, barShowTooltip, fingersShowTooltip -- BAR's tooltip API wrapped for fingers (wrapTooltips)

-- BAR's lobby over the game or gone again: told to the app (OVERLAY) and the app's widgets (WG.BarDroidLobbyOver).
-- Chobby's "LobbyOverlayActive1" reaches LuaUI from any player's Spring.SendLuaUIMsg online too, and one sent by a
-- player's widget took every phone's fingers off the game (driverwatch-phone-test, 2026-11-21): believed only once the
-- app's lobby widget, in this phone's own LuaMenu, says the same (bardroid_menushown.txt), within 2 s. "0" the same way
-- (release overhaul item 5): a widget's "0" while the lobby was over the game gave the fingers to the game under it,
-- the dock back over the lobby (overgame-phone-test)
local overlayCheck = { file = "LuaUI/Config/bardroid_menushown.txt" }
function overlayCheck.set(on)
	lobbyOver = on
	WG.BarDroidLobbyOver = on
	writeWhole(OVERLAY, on and "1\n" or "0\n")
end
function overlayCheck.step()
	if not overlayCheck.want then
		return
	end
	local f = io.open(overlayCheck.file, "r")
	local said = f and f:read("*l")
	if f then
		f:close()
	end
	if said == overlayCheck.want then
		overlayCheck.want = nil
		overlayCheck.set(said == "1")
	elseif Spring.DiffTimers(Spring.GetTimer(), overlayCheck.asked) > 2 then
		Spring.Echo("[bardroid-touch] a LobbyOverlayActive" .. overlayCheck.want
			.. " not from this phone's lobby: left alone") -- (tools)
		overlayCheck.want = nil
	end
end
function widget:RecvLuaMsg(msg)
	if msg:sub(1, 18) == "LobbyOverlayActive" then
		overlayCheck.want = msg:sub(19, 19) == "1" and "1" or "0"
		overlayCheck.asked = Spring.GetTimer()
		overlayCheck.step()
	end
end

function widget:Shutdown()
	writeWhole(OVERLAY, "0\n")
	WG.BarDroidLobbyOver = nil
	WG.BarDroidOnInterface = nil
	WG.BarDroidAskKeyboard = nil
	if not queueDrawn then
		Spring.LoadCmdColorsConfig("alwaysDrawQueue 1")
	end
	endCatchup() -- a LuaUI reload (fold/unfold) while catching up: the next start sees the gap again
	restoreDeferred() -- the engine's own passes back (a reload switches them off again)
	if tooltipApi and tooltipApi.ShowTooltip == fingersShowTooltip then -- (a widget reload wraps it again)
		tooltipApi.ShowTooltip = barShowTooltip
	end
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
-- A turn on the long screen (the folded Fold7, the dev phone) changes the scale, sideways 2.0, upright 1.0, and the
-- whole interface's reload froze the game ~7.5 s on the dev phone (Kailil, 2026-11-18: "When folded, if I swap between
-- vertical and landscape ... the game freezes and takes about 10 seconds"). With BAR's own widget handler (the phone
-- engine runs this as one of the game's widgets: handler = true) only the widgets whose files read ui_scale are loaded
-- again, FlowUI first (most of BAR's panels take their sizes from it), and the next frame every widget is told the
-- screen's size again, which the rest size themselves by. Without it (BAR's official engine) the whole reload as before.
local uiRescale = { pending = nil }
-- (a widget reading ui_scale only in its ViewResize takes the new one from the sizes sent after: no load needed; the
-- build menu copy alone took 0.5-1.2 s of 1.5-2.6 s loaded again, dev phone. Any reading outside ViewResize's body,
-- up to the file's next top-level function, counts as at load: a misread loads one more, never one too few)
function uiRescale.atLoad(src)
	-- (the app's Build menu copy reads it again in its ViewResize: make-buildmenu.py says so with this mark)
	if src:find("(bardroid-rescale: ViewResize)", 1, true) then
		return false
	end
	local vr = src:find("function widget:ViewResize", 1, true)
	local vrEnd = vr and (src:find("\nfunction ", vr + 10, true) or #src)
	local at = 1
	while true do
		local i = src:find("ui_scale", at, true)
		if not i then
			return false
		end
		if not (vr and i > vr and i < vrEnd) then
			return true
		end
		at = i + 8
	end
end
-- (only BAR's own handler: a user widget, as under BAR's official engine, gets a stand-in whose every member answers
-- with an empty table or a function that does nothing, and a warning; read past it. The first build without this
-- set the new scale under the official engine and loaded nothing again: BAR's panels kept the old size, dev phone)
function uiRescale.handler()
	local wh, get = widgetHandler, rawget
	if wh and get and type(get(wh, "widgets")) == "table" and type(get(wh, "knownWidgets")) == "table"
		and type(get(wh, "DisableWidget")) == "function" and type(get(wh, "EnableWidget")) == "function"
		and type(get(wh, "ViewResize")) == "function" then
		return wh
	end
end
-- Each file's answer kept: a turn read all 227 of the game's widget files again, 0.5-0.8 s of its freeze (dev phone).
-- From 20 s into a game they are read ahead, at most ~1 ms a frame, so even the first turn finds them read.
uiRescale.reads, uiRescale.ahead, uiRescale.updates = {}, 1, 0
function uiRescale.readsAtLoad(file)
	local r = uiRescale.reads[file]
	if r == nil then
		local ok, src = pcall(VFS.LoadFile, file)
		r = ok and type(src) == "string" and uiRescale.atLoad(src) or false
		uiRescale.reads[file] = r
	end
	return r
end
function uiRescale.readAhead()
	uiRescale.updates = uiRescale.updates + 1
	if uiRescale.updates < 600 then
		return
	end
	local wh = uiRescale.handler()
	if not wh then
		uiRescale.ahead = nil
		return
	end
	local t0 = Spring.GetTimer()
	while uiRescale.ahead do
		local w = wh.widgets[uiRescale.ahead]
		if not w then
			uiRescale.ahead = nil
			return
		end
		uiRescale.ahead = uiRescale.ahead + 1
		local file = w.whInfo and w.whInfo.filename
		if file then
			uiRescale.readsAtLoad(file)
			if Spring.DiffTimers(Spring.GetTimer(), t0) * 1000 >= 1 then
				return
			end
		end
	end
end
local function rescaleWidgets(screen, want)
	local wh = uiRescale.handler()
	if not wh then
		return false
	end
	local me, first, names, seen = widget:GetInfo().name, nil, {}, {}
	for _, w in ipairs(wh.widgets) do
		local info = w.whInfo
		local file, name = info and info.filename, info and info.name
		if name and file and name ~= me and not seen[name] then
			seen[name] = true
			if uiRescale.readsAtLoad(file) then
				if file:find("gui_flowui", 1, true) then
					first = name
				else
					names[#names + 1] = name
				end
			end
		end
	end
	if first then
		table.insert(names, 1, first)
	end
	if not first or #names < 2 then -- (no FlowUI among them: not BAR's widgets as known; the whole reload instead)
		return false
	end
	local t0 = Spring.GetTimer()
	for _, name in ipairs(names) do
		wh:DisableWidget(name)
		wh:EnableWidget(name)
	end
	-- (BAR's handler queues the loads and runs them after this call-in: the sizes go out at the next frame)
	uiRescale.pending = { t0 = t0, n = #names, screen = screen, want = want, frame = Spring.GetDrawFrame() }
	return true
end
local function rescaleFinish()
	local p = uiRescale.pending
	if not p or Spring.GetDrawFrame() <= p.frame then
		return
	end
	uiRescale.pending = nil
	local vsx, vsy = Spring.GetViewGeometry()
	pcall(widgetHandler.ViewResize, widgetHandler, vsx, vsy)
	Spring.Echo(string.format("[bardroid-touch] %s screen: interface scale %.1f, %d widgets loaded again in %d ms (no reload)",
		p.screen, p.want, p.n, Spring.DiffTimers(Spring.GetTimer(), p.t0) * 1000))
end
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
	if rescaleWidgets(screen, want) then
		return
	end
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
-- 2: one of those windows is open. They scroll their lists and text with the mouse wheel only (a finger's drag was a
-- left drag there: BAR's Settings did not scroll, dev phone 2026-11-03), so the app sends a vertical drag as the wheel.
local barX, barY, barAt, barAnswer = nil, nil, -1000, false

-- The build and order menus where they answer no IsAbove: BAR's own, where a copy of the app's gave way to it (the
-- app's copies answer it themselves). A finger's drag that started on them panned the map (dev phone, 2026-11-03: the
-- order menu, then the build menu, moved the map up). Their rects from their WG functions: the order menu's position
-- (view fractions); the build menu's top and bottom (getSize, view fractions) and the width its code gives it at the
-- left edge, not while it sits at the bottom.
local function overGameMenus(mx, my)
	local vsx, vsy = spGetViewGeometry()
	local o = WG.ordermenu
	if type(o) == "table" and type(o.getPosition) == "function" -- (the app's copy too: not movable, its place is true)
		and (type(o.getIsShowing) ~= "function" or o.getIsShowing()) then
		local x, y, w, h = o.getPosition()
		if x and y and w and h and mx >= x * vsx and mx <= (x + w) * vsx and my <= y * vsy and my >= (y - h) * vsy then
			return true
		end
	end
	-- (not the app's copy: it answers IsAbove itself, and the layout editor may have moved and sized it away from the
	-- width and place assumed here)
	local b = WG.buildmenu
	if type(b) == "table" and b ~= WG.bardroidBuildmenu and type(b.getSize) == "function"
		and type(b.getIsShowing) == "function" and b.getIsShowing()
		and not (type(b.getBottomPosition) == "function" and b.getBottomPosition()) then
		local top, bottom = b.getSize()
		if type(top) == "number" and type(bottom) == "number" and top <= 1 then -- (fractions; BAR's grid menu gives pixels)
			local ui = Spring.GetConfigFloat("ui_scale", 1) or 1
			local right = math.floor(0.212 / (vsx / vsy) * 1.78 * ui * vsx)
			if mx >= 0 and mx <= right and my >= bottom * vsy and my <= top * vsy then
				return true
			end
		end
	end
	-- (Not BAR's idle builders button and unit groups, bottom right, though a drag up from them pans the map too: they
	-- act on the press and have no MouseRelease, so as a drag the release landed on the map: the selection went and
	-- the commander was no longer idle; dev phone, 2026-11-03. A pan is the lesser harm.)
	return false
end

local function overBarInterface(mx, my)
	if mx == barX and my == barY and updates - barAt < 10 then
		return barAnswer
	end
	barX, barY, barAt, barAnswer = mx, my, updates, false
	for i = 1, #BAR_WINDOWS do
		local w = WG[BAR_WINDOWS[i]]
		if type(w) == "table" and type(w.isvisible) == "function" and w.isvisible() then
			barAnswer = 2
			return 2
		end
	end
	local tb = WG.topbar
	local p = type(tb) == "table" and type(tb.GetPosition) == "function" and tb.GetPosition()
	if type(p) == "table" and p[1] and p[2] and p[3] and p[4] then -- left, bottom, right, top (+ scale, buttons' bottom)
		local bottom = math.min(p[2], tonumber(p[6]) or p[2])
		barAnswer = mx >= p[1] and mx <= p[3] and my >= bottom and my <= p[4]
	end
	if not barAnswer then
		barAnswer = overGameMenus(mx, my)
	end
	-- 3: one of BAR's button panels that answer no IsAbove (the replay speed column, the vote panel, the pre-game Ready
	-- button; their phone patches put a function giving the panel's rect, GL pixels, in WG.BarDroidTapPanels): a tap
	-- there hides the pointer as on the interface, but a finger's drag pans as on the map (as interface, a drag that
	-- began on the replay column was a mouse drag, no pan, along a tall strip of the left edge upright; 2026-11-19)
	if not barAnswer then
		local panels = WG.BarDroidTapPanels
		if type(panels) == "table" then
			for _, rect in pairs(panels) do
				local ok, x0, y0, x1, y1 = pcall(rect)
				if ok and x0 and y1 and mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
					barAnswer = 3
					break
				end
			end
		end
	end
	return barAnswer
end

-- (bardroid_pad.lua: a click the pad asks the app for at a point lands on the map, never on a panel; also the minimap)
local function pointOnInterface(mx, my)
	return overBarInterface(mx, my) ~= false or (Spring.IsAboveMiniMap ~= nil and Spring.IsAboveMiniMap(mx, my) == true)
end

-- Those windows take the wheel only over themselves (BAR's Settings: anywhere while open), and a wheel none took zooms
-- the map: a finger's up or down drag beside BAR's Statistics zoomed the map behind it (dev phone, 2026-11-03). Taken
-- here, last in line, while one is open and the fingers are the input; a mouse keeps BAR's way.
function widget:MouseWheel()
	return WG.BarDroidInput == "touch" and overBarInterface(spGetMouseState()) == 2
end

-- Whether the interface is under the pointer: the engine asks the widgets each frame (IsAbove) where the pointer is,
-- and this widget, last in line, only hears of it where nothing else answered.
-- The map/interface answer for a pointer that stays put is worked out again every HOVER_RECHECK updates only (the
-- camera moving under it can change it); a pointer that moves gets it at once. Profiled on the laptop (2026-10-26):
-- this widget was BAR's most expensive one, 0.14 ms a frame (a view ray, a string and a file open every frame).
local HOVER_RECHECK = 10
local HOVER_KEEP = 2 -- s: the same answer written again this often (each write two opens and a rename through proot)
local calcX, calcY, calcAt, calcAnswer = nil, nil, -1000, 0
local hoverX, hoverY, hoverAnswer
local function updateHover()
	local mx, my = spGetMouseState()
	if mx ~= mouseX or my ~= mouseY then
		mouseX, mouseY, mouseSince = mx, my, updates
	end
	local onInterface
	if spIsGUIHidden() then
		onInterface = 0 -- the interface hidden (F5): all map
	elseif seenX == mx and seenY == my and seenAt >= mouseSince - 1 then
		-- 1 interface, 2 a BAR window that scrolls, 0 map (the void past the map's edge too: fingers work there as on
		-- the map)
		if mx ~= calcX or my ~= calcY or updates - calcAt >= HOVER_RECHECK then
			local bar = overBarInterface(mx, my)
			calcAnswer = (bar == 2 or bar == 3) and bar or ((spIsAboveMiniMap(mx, my) or bar) and 1 or 0)
			calcX, calcY, calcAt = mx, my, updates
		end
		onInterface = calcAnswer
	elseif updates - mouseSince >= 2 then
		-- not asked: a widget before this one claimed the pointer, however long ago this widget was last asked (the
		-- old "map after 300 updates without IsAbove" answered map all over the build menu once the pointer had
		-- rested on the interface for 10 s: fingers there then worked as on the map; dev phone, 2026-11-03)
		onInterface = overBarInterface(mx, my) == 2 and 2 or 1
	else
		return -- not asked yet for this position
	end
	local now = spGetTimer()
	if mx == hoverX and my == hoverY and onInterface == hoverAnswer and hoverTimer and spDiffTimers(now, hoverTimer) < HOVER_KEEP then
		return
	end
	-- also every HOVER_KEEP seconds: the app takes a file older than 5 s for "no widget" (the lobby; RtsTouch HOVER_STALE_MS)
	local _, vsy = spGetViewGeometry()
	writeWhole(HOVER, string.format("%d %d %d\n", mx, vsy - my - 1, onInterface))
	hoverX, hoverY, hoverAnswer, hoverTimer = mx, my, onInterface, now
end

-- The build and order menus' tooltips for fingers: a finger's pointer stays where it lifted, so the tooltip of the cell
-- or order it tapped stood over the buttons beside it until the next touch (dev phone, 2026-11-03). A build menu's says
-- what the info panel says: none; an order's goes TOOLTIP_REST seconds after the pointer came to rest. The app's menu
-- copies do that themselves (tools/make-buildmenu.py, make-ordermenu.py); BAR's own (a copy's fallback) through BAR's
-- tooltip API: its ShowTooltip wrapped while
-- the fingers are the input; a mouse and the pad keep BAR's way. Wrapped again when BAR's tooltip widget makes a new
-- API (a reload). (tooltipApi, barShowTooltip, fingersShowTooltip: declared before Shutdown, which unwraps it)
local TOOLTIP_REST = 2.5 -- (the order menu copy's TOOLTIP_SECONDS)
local TEXT_WHITE = "\255\240\240\240"
local HOTKEY = "\255\255\215\100[^\255\n]-" .. TEXT_WHITE .. " %- " -- (gold key, white " - ")
local tipX, tipY, tipRestsFrom
local function fingersTooltip(name)
	if WG.BarDroidInput ~= "touch" then
		return true
	elseif name == "buildmenu" then
		return false
	elseif name ~= "ordermenu" and name ~= "teamstats" then
		-- (the Statistics copy's too: the finger that tapped Show Graphs or Statistics left the pointer on a chart as
		-- the panel opened under it, and that chart's explanation stood over the charts below it; dev phone 2026-11-17)
		return true
	end
	local x, y = spGetMouseState()
	local now = spGetTimer()
	if x ~= tipX or y ~= tipY or not tipRestsFrom then
		tipX, tipY, tipRestsFrom = x, y, now
	end
	return spDiffTimers(now, tipRestsFrom) < TOOLTIP_REST
end
local function wrapTooltips()
	local t = WG.tooltip
	if type(t) ~= "table" or t == tooltipApi or type(t.ShowTooltip) ~= "function" then
		return
	end
	local show = t.ShowTooltip
	fingersShowTooltip = function(name, value, ...)
		if not fingersTooltip(name) then
			return
		end
		-- an order's keyboard key, which fingers have none of ("5 - Set a prioritized target ..."): BAR's
		-- ui.orderMenu.hotkeyTooltip puts it in its gold before the text's white; the app's copy leaves it out itself
		if name == "ordermenu" and type(value) == "string" and WG.BarDroidInput == "touch" then
			value = value:gsub(HOTKEY, TEXT_WHITE)
		end
		return show(name, value, ...)
	end
	tooltipApi, barShowTooltip = t, show
	t.ShowTooltip = fingersShowTooltip
end

-- Tracy zones around the parts of a frame's work (no-ops on BAR's engine; the engine branch's profiler times them,
-- docs/ENGINE-SIM.md: this widget's Update was 0.9% of a late 8v8's real time on the dev phone)
local zoneBegin = type(tracy) == "table" and tracy.ZoneBeginN or function() end
local zoneEnd = type(tracy) == "table" and tracy.ZoneEnd or function() end

local function update(dt)
	updates = updates + 1
	awayBack()
	zoneBegin("W:touch:lines")
	local lines = newTouchLines()
	if lines then
		readTouch(lines)
	end
	zoneEnd()
	wrapTooltips()
	zoneBegin("W:touch:camera")
	applyTouch(dt)
	applyPad(dt)
	zoneEnd()
	if lookAt then
		lookAt = lookAt - 1
		if lookAt <= 0 then
			lookAt = nil
			lookAtCommander()
		end
	end
	zoneBegin("W:touch:hover")
	updateHover()
	zoneEnd()
	queueCheck = queueCheck - dt
	if queueCheck <= 0 then -- queues grow and shrink without a selection change
		queueCheck = 0.5
		zoneBegin("W:touch:queue")
		updateQueueDrawing()
		zoneEnd()
	end

	screenCheck = screenCheck - dt
	if screenCheck <= 0 then
		-- (a fold or unfold resizes the view: ViewResize has it read every 0.5 s for the next 2 s, as the app writes the
		-- file about then; the display's refresh rate alone changes nothing here. Every 0.5 s always it was 0.3-0.4 % of
		-- a late 8v8's real time on the dev phone: the open)
		screenFast = math.max(0, screenFast - 1)
		screenCheck = screenFast > 0 and 0.5 or 3
		zoneBegin("W:touch:screen")
		local f = io.open(SCREEN, "r")
		if f then
			local s = f:read("*l")
			f:close()
			local w, h = (s or ""):match("^(%d+) (%d+) ")
			local size = w and w .. "x" .. h
			if not size or size == lastScreen then
				uiRescale.seen = nil
			elseif uiRescale.seen == size then -- the size: the 60/120 Hz switches change the rest
				-- (the official engine reloads the whole interface for a new scale, 5-10 s: there the size must hold
				-- 1.5 s, three more reads, so a phone turned and turned back within a second costs nothing instead of
				-- two reloads; the phone engine's 0.6-1 s rescale takes it after one)
				uiRescale.seenN = (uiRescale.seenN or 1) + 1
				if uiRescale.seenN > (uiRescale.handler() and 1 or 3) then
					lastScreen, uiRescale.seen = size, nil
					applyUiScale(tonumber(w), tonumber(h))
				else
					screenFast, screenCheck = math.max(screenFast, 1), 0.5
				end
			else
				-- (a new size counts once two reads 0.5 s apart agree: a tilt that auto-rotate turned back at once changes
				-- nothing. Kailil's Fold7, 2026-11-17: sideways and upright again within one reload, twice in a game, the
				-- first at its start. BAR's official engine, which his Fold7 runs since BAR's 2026.09.03, reloads the whole
				-- interface for each: rescaleWidgets needs the phone engine's handler)
				uiRescale.seen, uiRescale.seenN, screenFast, screenCheck = size, 1, math.max(screenFast, 1), 0.5
			end
		end
		zoneEnd()
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
	WG.BarDroidOnInterface = pointOnInterface
	overlayCheck.step() -- (a "LobbyOverlayActive1" waiting for this phone's lobby to say so)
	if uiRescale.pending then -- (a new interface scale: the reloaded widgets in, every widget told the screen's size)
		rescaleFinish()
	elseif uiRescale.ahead then
		uiRescale.readAhead()
	end
	guarded(update, dt)
end

function widget:ViewResize() -- (folded or unfolded: the screen file soon, update() above)
	screenCheck, screenFast = 0.2, 5
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
