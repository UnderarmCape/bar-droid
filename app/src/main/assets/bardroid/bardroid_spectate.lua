-- BAR Droid spectating by touch (Kailil, 2026-10-27: "a touch focused spectator only setup ... cycling through players
-- to switch player cam to, blocking the bottom left hand ui from popping up ... camera tools that follow a unit or group
-- of units ... cycle through units to follow or double tap a unit to follow them"). Only while spectating and the
-- fingers were the last input (the app reports the input as "src touch|mouse|keyboard|pad" lines, bardroid_touch.lua
-- keeps it in WG.BarDroidInput); a mouse, keyboard or gamepad gets BAR's spectating as it is.
--   a bar at the bottom, shown while BAR's player list is open (a tap on the small list opens it, bardroid_players.lua;
--   7 s without a tap on either closes both: Kailil, "only popup when I touch player list"):
--     not following:      < player >  BAR's player camera (its Lockcamera widget, WG.lockcamera) on the next or
--                                     previous player, top to bottom as the player list shows them; the button says
--                                     the player's name
--                         Free        back to the own camera
--     following:          camera presets in place of the players: 1st person, Shoulder (both turn with the unit),
--                         Table, Close, Mid; Save, then a preset: that preset becomes the camera as it is now
--     always:             < unit >    follow the next or previous unit by distance from the screen's centre
--                         Group       follow the unit's group (its team's units around it) instead of the unit alone
--   double tap a unit:    follow it; double tap the ground: stop following
-- Following sticks (Kailil: "unless I deliberately move my camera away from the unit a far distance"): a pan offsets the
-- camera from the unit, pinch, twist and tilt work as always, and the offset stays with the next unit picked with the
-- arrows; only a pan or flick that takes the unit far off the screen lets go. A pan ends BAR's player camera.
-- Taps on the map select nothing while this is on, so BAR's selected-unit panels (info, orders, build menu) stay away.
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid spectate",
		desc = "Touch tools for spectating: player cameras, following units, camera presets",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		-- after BAR's interface (map taps reach it only when nothing else took them), before the touch camera, which
		-- answers "map" to every pointer position no widget before it claimed
		layer = 999999,
		enabled = true,
	}
end

-- a double tap, forgiving (Kailil: "if im not deadly acurate with my two taps, it misses them"): the second tap within
-- this long and this far from the first, or on the same unit; a tap picks the unit within PICK_PX of the finger
local DOUBLE_TAP_S, DOUBLE_TAP_PX, PICK_PX = 0.55, 90, 70
local FOLLOW_SMOOTHING = 0.25 -- seconds: the camera glides after its target
local GROUP_SMOOTHING = 0.9 -- seconds: and after a group's centre, which moves as units join and leave it
local TURN_SMOOTHING = 0.35 -- seconds: and after the unit's facing (1st person, Shoulder)
local BLEND_S = 0.3 -- seconds: a preset's distance and pitch glide in
local GROUP_RADIUS = 700 -- elmos around the group's centre
local GROUP_EVERY = 0.5 -- seconds between new group members
local GROUP_MAX = 40 -- members at most (each frame's centre: ~40 position reads, a few hundredths of a millisecond)
-- letting go: the camera this far from what it follows (elmos), or twice the camera's distance if that is more
local BREAK_MIN, BREAK_DIST = 1500, 2
-- Camera presets: the Spring camera's distance from its target and pitch (rx: pi/2 level, pi straight down), and the
-- target's offset from the unit (elmos; oy up from the ground). "unit" ones turn with the unit (offset: ox to its
-- right, oz ahead; ryRel its heading's own turn), "world" ones keep the camera's turn and offset the target on the map.
-- Shoulder, Table and Mid as Kailil set them in the laptop tuner (2026-10-28).
local PRESETS = {
	{ key = "first", label = "1st person", frame = "unit", dist = 80, rx = 1.85, ryRel = 0, ox = 0, oz = 100 },
	{ key = "shoulder", label = "Shoulder", frame = "unit", dist = 270, rx = 1.688, ryRel = 0, ox = 90, oz = 140, oy = 0 },
	-- (Kailil: "make table super far. like eye in sky")
	{ key = "table", label = "Table", frame = "world", dist = 6000, rx = 2.826, ox = 0, oz = 0 },
	{ key = "close", label = "Close", frame = "world", dist = 450, rx = 2.5, ox = 0, oz = 0 },
	{ key = "mid", label = "Mid", frame = "world", dist = 1300, rx = 2.733, ox = 0, oz = 0 },
}
local saved = {} -- the views as the laptop tuner set them for everyone (its file), by key
-- A unit type's own views (presetTypes[unitName][key]) and 1st person values (FP.types) are set by the player, unit by
-- unit (Kailil, 2026-10-28: "i will only adjust unit by unit"): on the laptop in the tuner, on the phone with Tune on
-- the bar; Save keeps them (this widget's config) and gives them to the unit's equivalents in the other factions.
local presetTypes = {}
-- Table, Close and Mid are one view for every unit (Kailil, 2026-10-28: "TABLE CLOSE MID should be universal. save
-- affects all units. not individual like SHOULDER AND FIRST PERSON"): Tune sets them here, Save keeps them.
local UNIVERSAL = { table = true, close = true, mid = true }
local views = {} -- the universal views as the player set them (Tune), by key
-- Shoulder's default, where no unit type has its own (Kailil: "it should default to where every unit is centered and
-- zoomed in on the back of the unit"): the camera SHOULDER_BACK unit radii (plus elmos) behind the unit and
-- SHOULDER_UP above its middle, looking through its middle to the ground beyond (the Spring camera's focus is always
-- on the ground), so the unit is in the middle of the screen at any size.
local SHOULDER_BACK, SHOULDER_BACK_ADD = 4, 40
local SHOULDER_UP, SHOULDER_UP_ADD = 1.5, 20

-- 1st person rides the unit in the engine's first-person camera ("fps": an eye position and a direction; it keeps the
-- eye 5 elmos above the ground). Kailil sets these on the laptop with tools/fp-tuner.ps1 ("on the desktop only ... then
-- you take those adjustments and apply them globally"); the tuner edits this table live (WG.BarDroidSpectate.fp).
--   anchor:  the unit's middle, or one of its pieces: the one picked for the unit type in pieces[unitDefName], else the
--            first of pieceNames the unit has
--   facing:  "unit" (the unit's facing) or "piece" (the anchor piece's: a turret's aim)
--   forward, right, up: the eye from the anchor (elmos, in the facing's frame); pitch, yaw: the look (degrees, up and
--   right of the facing); fov (degrees); posSmoothing, turnSmoothing (seconds)
-- Kailil's values from the tuner (2026-10-27 23:00; his all-units values from then: a later session riding a fighter
-- changed them by mistake, 2026-10-28, "Can that be un done"). (The near clipping plane cannot come closer than the
-- engine's own, which follows the view range: Camera.cpp; Kailil only wanted it closer, so there is no setting for it.)
local FP = {
	pieceNames = { "head", "turret", "torso", "body", "base" },
	-- armed buildings (sentries): the gun's barrel first, and the eye turns with its aim (Kailil: "attach to sentries'
	-- gun barrels")
	staticPieceNames = { "barrel", "barrel1", "barrel2", "sleeve", "sleeves", "gun", "turret", "head" },
	-- the anchor piece per unit type, and values per unit type (by name) over the ones below (fpFor): Kailil's from the
	-- laptop tuner (2026-10-28)
	pieces = { armfig = "base", armguard = "barrel1", armham = "torso", corantiship = "base", corcom = "head",
		corhlt = "flare", corpun = "turret", cortoast = "turret" },
	classes = {}, -- (none: Kailil sets unit by unit)
	types = {
		armack = { forward = -18, right = -8, up = 28 },
		armch = { forward = -24 },
		armck = { forward = -26, right = 0, up = 20 },
		armcom = { forward = 2, up = 4 },
		armfido = { forward = -10, posSmoothing = 1.98, right = 2 },
		armguard = { forward = -26, right = 6, up = 0 },
		armham = { forward = -2, right = -4 },
		armllt = { forward = -38, fov = 80, pitch = -8, posSmoothing = 0.4, right = 18, turnSmoothing = 0.31, up = 8, yaw = -10 },
		corantiship = { forward = 20, right = 4, up = 54 },
		corcom = { forward = 0, right = 0, up = 20 },
		corhlt = { forward = -88, posSmoothing = 0.7, right = 40, turnSmoothing = 0.31, yaw = -30 },
		corllt = { forward = -34, posSmoothing = 0.5, right = 14, turnSmoothing = 0.31, up = 4, yaw = -10 },
		corpun = { forward = -38 },
		cortoast = { forward = -34, right = 0, up = 4, yaw = 26 },
		corvalk = { forward = -34, right = -6, up = 18 },
	},
	facing = "unit",
	forward = 16, right = 4, up = 14,
	pitch = -8, yaw = 0,
	fov = 80,
	posSmoothing = 0.2, turnSmoothing = 0.25,
	-- free look (Kailil: "look right and left or up and down, which will ignore the rotation of the unit ... after no
	-- more input from myself, it will auto center and reset fov values ... maybe 4 seconds"): a drag across the screen's
	-- width turns lookSpeed degrees; recenterDelay seconds without input, then back over recenterSmoothing seconds
	lookSpeed = 120, recenterDelay = 4, recenterSmoothing = 0.6,
}
-- the free look: where the player looks (absolute turn, pitch in degrees, FOV) while look.free; look.at the last input
local look = { free = false, yaw = 0, pitch = 0, fov = 70, at = 0 }

-- Wildlife is never followed (Kailil: "blacklist wildlife such as seagulls, crabs"): BAR's critters, and anything of the
-- Gaia team (the map's neutral units).
local gaiaTeam = Spring.GetGaiaTeamID()
-- mobile units, and armed buildings (Kailil: "allow me to attach to sentries' gun barrels")
local function followable(unitID, def)
	def = def or UnitDefs[Spring.GetUnitDefID(unitID) or -1]
	return def ~= nil and ((def.speed or 0) > 0 or (def.weapons and #def.weapons > 0))
		and not def.name:find("critter", 1, true) and Spring.GetUnitTeam(unitID) ~= gaiaTeam
end

-- The unit a tap means: the one under the finger, else the nearest on the screen within PICK_PX (a finger is wide).
local function pickUnit(x, y)
	local what, unitID = Spring.TraceScreenRay(x, y)
	if what == "unit" and followable(unitID) then
		return unitID
	end
	local best, bestD
	for _, id in ipairs(Spring.GetVisibleUnits(-1, 30, false) or {}) do
		local ux, uy, uz = Spring.GetUnitPosition(id)
		if ux and followable(id) then
			local sx, sy, sz = Spring.WorldToScreenCoords(ux, uy, uz)
			if sz and sz < 1 then -- (in front of the eye)
				local d = (sx - x) ^ 2 + (sy - y) ^ 2
				if d <= PICK_PX * PICK_PX and (not bestD or d < bestD) then
					best, bestD = id, d
				end
			end
		end
	end
	return best
end

local spGetCameraState, spSetCameraState = Spring.GetCameraState, Spring.SetCameraState
local spGetUnitPosition = Spring.GetUnitPosition
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers

local active = false
local shown = false -- the bar: active and BAR's player list open
local buttons = {} -- { x0, y0, x1, y1, action, label, lit, color }
local follow -- { unitID, team, members, cx, cz, at, bx, bz (the followed point, smoothed), yaw, setX, setZ, setRy }
-- the camera's place relative to what it follows; it stays when the arrows pick another unit
local view = { frame = "world", ox = 0, oz = 0, oy = 0, ryRel = 0, preset = nil, blend = nil }
local groupMode = false
local tuning = false -- Tune on the bar (below)
local cycle -- { list of unitIDs by distance from the screen's centre, taken at the first arrow }
local lastTap -- { x, y, t }
local pressedOn -- the button a press went down on
local panSeen = 0
local t0 = spGetTimer()

local function now()
	return spDiffTimers(spGetTimer(), t0)
end

local function lockcamera()
	return WG.lockcamera
end

local function lockedPlayer()
	local lc = lockcamera()
	return lc and lc.GetPlayerID and lc.GetPlayerID()
end

-- BAR's player camera off, the view staying where it is (BAR would glide back to the view before the lock)
local function unlockPlayer()
	if lockedPlayer() then
		local cs = spGetCameraState()
		lockcamera().SetPlayerID(nil)
		spSetCameraState(cs, 0)
	end
end

-- The Spring camera keeps BAR's "minimum camera height" (CamSpringMinZoomDistance, BAR's default 300) from what it
-- looks at: closer for a preset that needs it (1st person), for this session only (the overlay, not saved), and the
-- player's own back when following ends.
local MIN_ZOOM_KEY = "CamSpringMinZoomDistance"
local minZoomOwn
local function closeZoom(on)
	if on and not minZoomOwn then
		minZoomOwn = Spring.GetConfigFloat(MIN_ZOOM_KEY, 300)
		Spring.SetConfigFloat(MIN_ZOOM_KEY, 20, true)
	elseif not on and minZoomOwn then
		Spring.SetConfigFloat(MIN_ZOOM_KEY, minZoomOwn, true)
		minZoomOwn = nil
	end
end

-- the engine's camera modes (CameraHandler.h): the first-person one, and the Spring camera BAR plays with
local CAM_FPS, CAM_SPRING = 0, 2
local springBefore -- the Spring camera as it was when 1st person began

local function leaveFirstPerson()
	local cs = spGetCameraState()
	if not springBefore then
		if cs.mode == CAM_FPS and cs.px then -- (1st person begun without the Spring camera to go back to)
			spSetCameraState({ mode = CAM_SPRING, px = cs.px, py = Spring.GetGroundHeight(cs.px, cs.pz), pz = cs.pz,
				dist = 1200, rx = 2.6, ry = cs.ry or 0, rz = 0 }, 0)
		end
		return
	end
	local back = springBefore
	springBefore = nil
	if cs.mode == CAM_FPS and cs.px then -- (back over where the eye was)
		back.px, back.pz = cs.px, cs.pz
		back.py = Spring.GetGroundHeight(cs.px, cs.pz)
	end
	spSetCameraState(back, 0)
end

local function stopFollow()
	leaveFirstPerson()
	follow = nil
	cycle = nil
	tuning = false
	closeZoom(false)
end

---------------------------------------------------------------------------------------------------------------------
-- players

-- The players in the game (not spectators) top to bottom as BAR's player list shows them (gui_advplayerslist.lua
-- SortAllyTeams: the watched team's alliance first, then the others; their teams and players in the engine's order).
-- Taken once when the bar opens: the player camera changes the watched team, and the list reorders after it.
local order
local function players()
	local list, first = {}, Spring.GetMyAllyTeamID()
	local allyTeams = { first }
	for _, allyTeamID in ipairs(Spring.GetAllyTeamList() or {}) do
		if allyTeamID ~= first then
			allyTeams[#allyTeams + 1] = allyTeamID
		end
	end
	for _, allyTeamID in ipairs(allyTeams) do
		for _, teamID in ipairs(Spring.GetTeamList(allyTeamID) or {}) do
			for _, playerID in ipairs(Spring.GetPlayerList(teamID, true) or {}) do
				local name, _, spec = Spring.GetPlayerInfo(playerID, false)
				if name and not spec then
					list[#list + 1] = { id = playerID, name = name }
				end
			end
		end
	end
	return list
end

local function cyclePlayer(step)
	order = order or players()
	local list = order
	if #list == 0 or not (lockcamera() and lockcamera().SetPlayerID) then
		return
	end
	local current, at = lockedPlayer(), nil
	for i, p in ipairs(list) do
		if p.id == current then
			at = i
		end
	end
	local nextIndex = at and ((at - 1 + step) % #list + 1) or (step > 0 and 1 or #list)
	stopFollow()
	lockcamera().SetPlayerID(list[nextIndex].id)
end

---------------------------------------------------------------------------------------------------------------------
-- following

-- the unit's facing as the camera's turn (the camera looks along (sin ry, -cos ry): Camera.cpp GetFwdFromRot)
local function unitYaw(unitID)
	local dx, _, dz = Spring.GetUnitDirection(unitID)
	if not dx or (dx == 0 and dz == 0) then
		return nil
	end
	return math.atan2(dx, -dz)
end

-- the view's offset on the map (its "unit" frame turns with the unit's facing)
local function offsetOnMap(yaw)
	if view.frame ~= "unit" or not yaw then
		return view.ox, view.oz
	end
	local fx, fz = math.sin(yaw), -math.cos(yaw) -- ahead
	local rx, rz = -fz, fx -- to its right
	return rx * view.ox + fx * view.oz, rz * view.ox + fz * view.oz
end

-- a move on the map into the view's offset
local function addToOffset(dx, dz, yaw)
	if view.frame ~= "unit" or not yaw then
		view.ox, view.oz = view.ox + dx, view.oz + dz
		return
	end
	local fx, fz = math.sin(yaw), -math.cos(yaw)
	local rx, rz = -fz, fx
	view.ox = view.ox + dx * rx + dz * rz
	view.oz = view.oz + dx * fx + dz * fz
end

local function startFollow(unitID, keepOffset)
	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return
	end
	unlockPlayer()
	if not keepOffset then
		view.ox, view.oz = 0, 0
	end
	local cs = spGetCameraState()
	local yaw = unitYaw(unitID)
	local mx, mz = offsetOnMap(yaw)
	-- (from where the camera looks now: it glides to the unit)
	local bx, bz = (cs.px or x) - mx, (cs.pz or z) - mz
	follow = { unitID = unitID, team = Spring.GetUnitTeam(unitID), cx = x, cz = z, members = { unitID }, at = -1,
		bx = bx, bz = bz, yaw = yaw }
end

-- mobile units by distance from where the camera looks (the screen's centre)
local function unitsByDistance()
	local cs = spGetCameraState()
	local cx, cz = cs.px or 0, cs.pz or 0
	local list = {}
	-- (only the team spectated, as BAR's own spectating picks it: Kailil, "only follow units of the same team that is
	-- selected using the vanilla system of spectating")
	for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local x, _, z = spGetUnitPosition(unitID)
		if x and followable(unitID) and not Spring.GetUnitIsBeingBuilt(unitID) then
			list[#list + 1] = { id = unitID, d = (x - cx) ^ 2 + (z - cz) ^ 2 }
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.id < b.id
	end)
	local ids = {}
	for i, u in ipairs(list) do
		ids[i] = u.id
	end
	return ids
end

-- The arrows: the unit closest to the screen's centre first, then outwards (the order taken at the first press, so
-- the arrows walk it even as the camera moves). The offset stays.
local function cycleUnit(step)
	if not cycle then
		cycle = { list = unitsByDistance() }
	end
	local list, at = cycle.list, nil
	for i, id in ipairs(list) do
		if follow and id == follow.unitID then
			at = i
		end
	end
	for _ = 1, #list do -- (past units destroyed since)
		local nextIndex = at and ((at - 1 + step) % #list + 1) or 1
		at = nextIndex
		if Spring.ValidUnitID(list[nextIndex]) then
			local keep = cycle
			startFollow(list[nextIndex], true)
			cycle = keep
			return
		end
	end
end

-- What the camera follows: the unit, or the centre of its group: its team's mobile units around the group's centre,
-- picked again every GROUP_EVERY, their centre taken every frame (Kailil, 2026-10-27: group following was jerky when
-- the centre moved only with each new pick).
local function followTarget()
	local f = follow
	local x, _, z = spGetUnitPosition(f.unitID)
	if not x and not groupMode then
		-- the unit is gone: on to its team's unit nearest where it was (Kailil: "if a unit dies, camera moves to the
		-- closet unit next to it. on the same team")
		local best, bestD
		for _, unitID in ipairs(Spring.GetTeamUnits(f.team) or {}) do
			local ux, _, uz = spGetUnitPosition(unitID)
			if ux and followable(unitID) then
				local d = (ux - f.cx) ^ 2 + (uz - f.cz) ^ 2
				if not bestD or d < bestD then
					best, bestD = unitID, d
				end
			end
		end
		if not best then
			return nil
		end
		f.unitID, f.fpX = best, nil -- (1st person starts again on it)
		x, _, z = spGetUnitPosition(best)
	end
	if not groupMode then
		f.cx, f.cz = x, z -- (where it was, if it dies)
		return x, z
	end
	if now() - f.at >= GROUP_EVERY then
		f.at = now()
		local kept = {}
		for _, unitID in ipairs(Spring.GetUnitsInCylinder(f.cx, f.cz, GROUP_RADIUS, f.team) or {}) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			local ux, _, uz = spGetUnitPosition(unitID)
			if def and (def.speed or 0) > 0 and ux then
				kept[#kept + 1] = { id = unitID, d = (ux - f.cx) ^ 2 + (uz - f.cz) ^ 2 }
			end
		end
		-- (at most GROUP_MAX, the ones nearest the centre: the centre is taken from them every frame, which stays cheap)
		table.sort(kept, function(a, b) return a.d < b.d end)
		if #kept > 0 then
			f.members = {}
			for i = 1, math.min(#kept, GROUP_MAX) do
				f.members[i] = kept[i].id
			end
		end
	end
	local sx, sz, n = 0, 0, 0
	for _, unitID in ipairs(f.members) do
		local ux, _, uz = spGetUnitPosition(unitID)
		if ux then
			sx, sz, n = sx + ux, sz + uz, n + 1
		end
	end
	if n == 0 then
		return x, z -- (nil when the unit is gone too)
	end
	f.cx, f.cz = sx / n, sz / n
	if not x then -- the unit is gone: the group goes on, around one of its members
		for _, unitID in ipairs(f.members) do
			if Spring.ValidUnitID(unitID) then
				f.unitID = unitID
				break
			end
		end
	end
	return f.cx, f.cz
end

-- A critically damped spring towards the target (no jumps when the target does: it eases out and in); v the speed.
local function smoothDamp(current, target, v, time, dt)
	local omega = 2 / time
	local x = omega * dt
	local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local temp = (v + omega * change) * dt
	return target + (change + temp) * decay, (v - omega * temp) * decay
end

local function approachAngle(a, b, k)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * k
end

-- the anchor of 1st person: a piece of the unit (FP.pieces for its type, else the first of FP.pieceNames it has; ""
-- picks the middle) or the unit's middle; with the piece's facing on the map (dx, dz) and the anchor's name. The piece
-- is looked up once per unit and anchor setting (the unit's piece map is a new table at every call).
local anchorFound = {} -- { unitID, defID (unit IDs are used again), want, piece, name }
local function anchorOf(unitID)
	local defID = Spring.GetUnitDefID(unitID)
	local def = UnitDefs[defID or -1]
	local want = def and FP.pieces[def.name]
	local piece, name
	if anchorFound.unitID == unitID and anchorFound.defID == defID and anchorFound.want == want then
		piece, name = anchorFound.piece, anchorFound.name
	else
		name = want
		local map = Spring.GetUnitPieceMap(unitID) or {}
		piece = name and name ~= "" and map[name]
		if not piece and name ~= "" then
			for _, n in ipairs((def and (def.speed or 0) == 0) and FP.staticPieceNames or FP.pieceNames) do
				if map[n] then
					piece, name = map[n], n
					break
				end
			end
		end
		anchorFound.unitID, anchorFound.defID, anchorFound.want = unitID, defID, want
		anchorFound.piece, anchorFound.name = piece, name
	end
	if piece then
		local px, py, pz, dx, _, dz = Spring.GetUnitPiecePosDir(unitID, piece)
		if px then
			return px, py, pz, dx, dz, name
		end
	end
	local _, _, _, mx, my, mz = spGetUnitPosition(unitID, true)
	return mx, my, mz, nil, nil, ""
end

-- 1st person's values for a unit type: its own (FP.types[name]), else its class's (FP.classes: "sentry" for armed
-- buildings, "unit" for the rest), else FP's (Kailil: "save a specific type of preset for each unit type. for example
-- sentries would have less smoothing on the barrel aim")
local FP_KEYS = { "facing", "forward", "right", "up", "pitch", "yaw", "fov", "posSmoothing", "turnSmoothing",
	"lookSpeed", "recenterDelay", "recenterSmoothing" }
local function unitClass(def)
	return (def and (def.speed or 0) == 0) and "sentry" or "unit"
end
local NONE = {}
local function fpFor(def, P) -- (into P when given: 1st person reuses one table every frame)
	P = P or {}
	local c = FP.classes[unitClass(def)] or NONE
	local t = (def and FP.types[def.name]) or NONE
	for _, k in ipairs(FP_KEYS) do
		local v = t[k]
		if v == nil then
			v = c[k]
		end
		if v == nil then
			v = FP[k]
		end
		P[k] = v
	end
	return P
end

local fpValues = {} -- (fpFor's values, the same table every frame)
local fpCam = { mode = CAM_FPS, rz = 0 } -- (the camera state set every frame, the same table)
local function updateFirstPerson(dt)
	local f = follow
	local ax, ay, az, pdx, pdz, name = anchorOf(f.unitID)
	if not ax then
		stopFollow()
		return
	end
	f.anchor = name
	local def = UnitDefs[Spring.GetUnitDefID(f.unitID) or -1]
	local P = fpFor(def, fpValues) -- (this unit type's values)
	local static = def and (def.speed or 0) == 0 -- (a sentry: its gun's aim)
	local yaw = ((P.facing == "piece" or static) and pdx and (pdx ~= 0 or pdz ~= 0)) and math.atan2(pdx, -pdz)
		or unitYaw(f.unitID)
	yaw = yaw or f.fpYaw or 0
	if not f.fpX then
		f.fpX, f.fpY, f.fpZ, f.fpYaw = ax, ay, az, yaw
	end
	local kp = P.posSmoothing > 0 and (1 - math.exp(-dt / P.posSmoothing)) or 1
	local kt = P.turnSmoothing > 0 and (1 - math.exp(-dt / P.turnSmoothing)) or 1
	f.fpX, f.fpY, f.fpZ = f.fpX + (ax - f.fpX) * kp, f.fpY + (ay - f.fpY) * kp, f.fpZ + (az - f.fpZ) * kp
	f.fpYaw = approachAngle(f.fpYaw, yaw, kt)
	local fx, fz = math.sin(f.fpYaw), -math.cos(f.fpYaw) -- ahead
	local rx, rz = -fz, fx -- to its right
	local ex, ez = f.fpX + fx * P.forward + rx * P.right, f.fpZ + fz * P.forward + rz * P.right
	local ey = f.fpY + P.up
	-- where the eye looks: with the unit, or where the player looked (free look, it ignores the unit's turning) until
	-- P.recenterDelay without input, then back with the unit smoothly, the FOV too
	local wantYaw, wantPitch, wantFov = f.fpYaw + math.rad(P.yaw), P.pitch, P.fov
	local L = WG.BarDroidLook
	local input = L and (L.dx ~= 0 or L.dy ~= 0 or L.zoom ~= 1 or L.rot ~= 0 or L.tilt ~= 0)
	if input then
		if not look.free then
			look.free, look.yaw, look.pitch, look.fov = true, wantYaw, wantPitch, wantFov
		end
		local vsx = Spring.GetViewGeometry()
		local speed = math.rad(P.lookSpeed) -- (a drag across the screen's width turns this much)
		-- the view goes with the finger, as dragging the scene: right turns it left, down tilts it up (dx, dy: screen
		-- pixels, y down; rot: a twist, clockwise; tilt: two fingers down, a share of the screen's height)
		look.yaw = look.yaw - L.dx / vsx * speed - L.rot
		look.pitch = math.max(-85, math.min(85, look.pitch + math.deg(L.dy / vsx * speed) + L.tilt * 90))
		look.fov = math.max(20, math.min(120, look.fov / L.zoom))
		look.at = now()
		L.dx, L.dy, L.zoom, L.rot, L.tilt = 0, 0, 1, 0, 0
	end
	if look.free and now() - look.at > P.recenterDelay then -- back with the unit
		local kr = P.recenterSmoothing > 0 and (1 - math.exp(-dt / P.recenterSmoothing)) or 1
		look.yaw = approachAngle(look.yaw, wantYaw, kr)
		look.pitch = look.pitch + (wantPitch - look.pitch) * kr
		look.fov = look.fov + (wantFov - look.fov) * kr
		local dYaw = math.abs((wantYaw - look.yaw + math.pi) % (2 * math.pi) - math.pi)
		if dYaw < 0.01 and math.abs(wantPitch - look.pitch) < 0.5 and math.abs(wantFov - look.fov) < 0.5 then
			look.free = false
		end
	end
	local ry, pitchDeg, fov = wantYaw, wantPitch, wantFov
	if look.free then
		ry, pitchDeg, fov = look.yaw, look.pitch, look.fov
	end
	local pitch = math.pi / 2 - math.rad(pitchDeg) -- (rx: pi/2 level, more is down)
	local c = fpCam
	c.px, c.py, c.pz, c.rx, c.ry, c.fov = ex, ey, ez, pitch, ry, fov
	c.dx, c.dy, c.dz = math.sin(pitch) * math.sin(ry), math.cos(pitch), -math.sin(pitch) * math.cos(ry)
	c.oldHeight = ey - Spring.GetGroundHeight(ex, ez)
	spSetCameraState(c, 0)
end

local function updateFollow(dt)
	local f = follow
	if not f then
		return
	end
	if view.preset == "first" then
		updateFirstPerson(dt)
		return
	end
	local tx, tz = followTarget()
	if not tx then
		stopFollow()
		return
	end
	local cs = spGetCameraState()
	if not (cs.px and cs.pz) then
		return
	end
	local yaw = unitYaw(f.unitID)
	if yaw then
		f.yaw = f.yaw and approachAngle(f.yaw, yaw, 1 - math.exp(-dt / TURN_SMOOTHING)) or yaw
	end
	-- the fingers' moves since the camera was last placed: pans and pinches move the offset, a twist the turn
	if f.setX then
		addToOffset(cs.px - f.setX, cs.pz - f.setZ, f.yaw)
		if view.frame == "unit" and cs.ry and f.setRy then
			view.ryRel = view.ryRel + (cs.ry - f.setRy)
		end
	end
	local mx, mz = offsetOnMap(f.yaw)
	if math.sqrt(mx * mx + mz * mz) > math.max(BREAK_MIN, BREAK_DIST * (cs.dist or cs.height or 0)) then
		stopFollow() -- taken far off the screen: let go
		return
	end
	local k = 1 - math.exp(-dt / FOLLOW_SMOOTHING)
	local glide = groupMode and GROUP_SMOOTHING or FOLLOW_SMOOTHING
	f.bx, f.vx = smoothDamp(f.bx, tx, f.vx or 0, glide, dt)
	f.bz, f.vz = smoothDamp(f.bz, tz, f.vz or 0, glide, dt)
	cs.px, cs.pz = f.bx + mx, f.bz + mz
	if view.frame == "unit" and f.yaw and cs.ry then
		cs.ry = approachAngle(cs.ry, f.yaw + view.ryRel, k)
	end
	if cs.dist and cs.rx then -- (without last frame's Up, below: the fingers and a preset's glide work on these)
		cs.dist, cs.rx = cs.dist - (f.upDist or 0), cs.rx - (f.upRx or 0)
	end
	local b = view.blend
	if b then -- a preset's distance and pitch gliding in
		local kb = 1 - math.exp(-dt / (BLEND_S / 3))
		if cs.dist then
			cs.dist = cs.dist + (b.dist - cs.dist) * kb
		end
		if cs.rx then
			cs.rx = cs.rx + (b.rx - cs.rx) * kb
		end
		if now() - b.t > BLEND_S * 2 then
			view.blend = nil
		end
	end
	-- A view's Up: the Spring camera always looks at the ground (the engine sets its focus height every frame, so a
	-- height given in the state was lost; Kailil: "the UP tune setting doesnt work in the shoulder cam"). The camera
	-- goes up by Up above the same focus at the same distance across the ground, looking down at it more steeply.
	-- (Keeping the angle instead moved a near-level view's focus kilometres ahead.)
	f.upDist, f.upRx = 0, 0
	local up = view.oy or 0
	if up ~= 0 and cs.dist and cs.rx then
		local across = cs.dist * math.sin(cs.rx) -- (rx: pi/2 level, pi straight down)
		local height = math.max(1, -cs.dist * math.cos(cs.rx) + up)
		local dist = math.sqrt(across * across + height * height)
		local rx = math.max(math.pi * 0.51, math.min(math.pi * 0.99, math.pi / 2 + math.atan2(height, across)))
		f.upDist, f.upRx = dist - cs.dist, rx - cs.rx
		cs.dist, cs.rx = dist, rx
	end
	spSetCameraState(cs, 0)
	f.setX, f.setZ, f.setRy = cs.px, cs.pz, cs.ry
end

local function followedName()
	local def = follow and UnitDefs[Spring.GetUnitDefID(follow.unitID) or -1]
	return def and def.name
end

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = copy(v)
	end
	return c
end

-- a view as everyone gets it (the laptop tuner's, else the built-in one)
local function defaultPreset(key)
	for _, p in ipairs(PRESETS) do
		if p.key == key then
			return saved[key] or p
		end
	end
end

-- Shoulder fitted to the followed unit (SHOULDER_*): behind it, over its middle, looking through its middle
local function shoulderFit()
	local unitID = follow and follow.unitID
	local def = unitID and UnitDefs[Spring.GetUnitDefID(unitID) or -1]
	if not def then
		return nil
	end
	local r = Spring.GetUnitRadius(unitID) or def.radius or 30
	local _, by, _, _, my = spGetUnitPosition(unitID, true)
	local mid = (by and my) and math.max(5, my - by) or r -- (its middle above its base)
	local back = SHOULDER_BACK * r + SHOULDER_BACK_ADD
	local above = SHOULDER_UP * r + SHOULDER_UP_ADD -- (the camera over the middle)
	local ahead = back * mid / above -- (where the line through the middle reaches the ground)
	return { key = "shoulder", label = "Shoulder", frame = "unit", ryRel = 0, ox = 0, oz = ahead, oy = 0,
		dist = math.sqrt((back + ahead) ^ 2 + (mid + above) ^ 2), rx = math.pi / 2 + math.atan2(above, back) }
end

-- a view as the followed unit gets it: Table, Close and Mid the same for all (as the player set them), the others its
-- type's own, else everyone's (Shoulder: fitted to the unit)
local function presetByKey(key)
	if UNIVERSAL[key] then
		return views[key] or defaultPreset(key)
	end
	local name = followedName()
	local own = name and presetTypes[name] and presetTypes[name][key]
	if own then
		return own
	end
	if key == "shoulder" and not saved.shoulder then
		return shoulderFit() or defaultPreset(key)
	end
	return defaultPreset(key)
end

local function applyPreset(key)
	local p = presetByKey(key)
	if not (p and follow) then
		return
	end
	if key == "first" then -- the engine's first-person camera, set every frame (updateFirstPerson)
		if not springBefore then
			local cs = spGetCameraState()
			springBefore = cs.mode == CAM_SPRING and cs or nil
		end
		follow.fpX = nil
		view.preset = key
		return
	end
	leaveFirstPerson()
	if follow.setX then -- (the Spring camera again: from where it is now)
		local cs = spGetCameraState()
		follow.setX, follow.setZ, follow.setRy = cs.px, cs.pz, cs.ry
	end
	view.frame, view.ox, view.oz, view.ryRel, view.preset = p.frame, p.ox or 0, p.oz or 0, p.ryRel or 0, key
	view.oy = p.oy or 0
	view.blend = { dist = p.dist, rx = p.rx, t = now() }
	closeZoom(p.dist < (minZoomOwn or Spring.GetConfigFloat(MIN_ZOOM_KEY, 300)))
end

---------------------------------------------------------------------------------------------------------------------
-- A unit type's equivalents in the other factions (Kailil: "it applies to the other faction's equiltvalent. so
-- thug/mace and so on"): the same name after the faction's prefix (armllt, corllt, legllt), or the same place in the
-- same factory of Armada and Cortex (armlab and corlab list their units in the same order: armham, the Mace, where
-- corthud, the Thug, is; armfig where corveng). Legion's factories list theirs in another order: by name only.

local equivalents -- unit name -> { other names }
local FACTIONS = { "arm", "cor", "leg" }

local function buildEquivalents()
	local parent = {}
	local function find(x)
		while parent[x] and parent[x] ~= x do
			x = parent[x]
		end
		return x
	end
	local function join(a, b)
		parent[a], parent[b] = parent[a] or a, parent[b] or b
		local ra, rb = find(a), find(b)
		if ra ~= rb then
			parent[rb] = ra
		end
	end
	local bySuffix = {}
	for _, def in pairs(UnitDefs) do
		local prefix = def.name:sub(1, 3)
		for _, f in ipairs(FACTIONS) do
			if prefix == f then
				local rest = def.name:sub(4)
				if bySuffix[rest] then
					join(bySuffix[rest], def.name)
				else
					bySuffix[rest] = def.name
				end
			end
		end
	end
	for _, def in pairs(UnitDefs) do
		local rest = def.name:match("^arm(.+)$")
		local other = rest and UnitDefNames["cor" .. rest]
		if other and def.isFactory and def.buildOptions and other.buildOptions then
			for i, id in ipairs(def.buildOptions) do
				local a, b = UnitDefs[id], UnitDefs[other.buildOptions[i] or -1]
				if a and b then
					join(a.name, b.name)
				end
			end
		end
	end
	local groups = {}
	for name in pairs(parent) do
		local r = find(name)
		groups[r] = groups[r] or {}
		groups[r][#groups[r] + 1] = name
	end
	equivalents = {}
	for _, g in pairs(groups) do
		for _, name in ipairs(g) do
			local others = {}
			for _, o in ipairs(g) do
				if o ~= name then
					others[#others + 1] = o
				end
			end
			equivalents[name] = others
		end
	end
end

local function equivalentsOf(name)
	if not equivalents then
		buildEquivalents()
	end
	return equivalents[name] or {}
end

---------------------------------------------------------------------------------------------------------------------
-- Tune (the phone; Kailil: "more touch friendly so instead of a big list, you toggle through different settigns one
-- by one. and each is just for that type of unit"): the bar shows one setting of the view on at a time, < > picks
-- another, - + change it for the unit type followed (at once); Save keeps it (this widget's config) and gives it to the
-- unit's equivalents.

local tuneAt = 1
local savedAt = -100
-- what the player saved on this device, per unit type: 1st person values, anchor pieces, views; and the universal views
-- (the config)
local kept = { types = {}, pieces = {}, presetTypes = {}, views = {} }

local FP_SETTINGS = {
	{ key = "anchor", label = "Anchor" },
	{ key = "forward", label = "Forward", step = 2 },
	{ key = "right", label = "Right", step = 2 },
	{ key = "up", label = "Up", step = 2 },
	{ key = "pitch", label = "Pitch", step = 1, min = -89, max = 89 },
	{ key = "yaw", label = "Yaw", step = 2, min = -180, max = 180 },
	{ key = "fov", label = "FOV", step = 2, min = 10, max = 150 },
	{ key = "posSmoothing", label = "Move smooth", step = 0.02, min = 0, max = 3 },
	{ key = "turnSmoothing", label = "Turn smooth", step = 0.02, min = 0, max = 3 },
}
local VIEW_SETTINGS = {
	{ key = "dist", label = "Distance", step = 25, min = 20, max = 20000 },
	{ key = "rx", label = "Pitch down", step = 1, min = 0, max = 89.5, deg = true },
	{ key = "ryRel", label = "Turn", step = 5, min = -180, max = 180, rad = true, unitOnly = true },
	{ key = "ox", label = "Right", step = 10, min = -3000, max = 3000 },
	{ key = "oz", label = "Ahead", step = 10, min = -3000, max = 3000 },
	{ key = "oy", label = "Up", step = 10, min = -500, max = 3000 },
}

local function tuneSettings()
	if view.preset == "first" then
		return FP_SETTINGS
	end
	local p = presetByKey(view.preset or "mid") or {}
	local list = {}
	for _, s in ipairs(VIEW_SETTINGS) do
		if not s.unitOnly or p.frame == "unit" then
			list[#list + 1] = s
		end
	end
	return list
end

local function round(v, step)
	return math.floor(v / step + 0.5) * step
end

-- a view's value as shown (rx as degrees below level, ryRel as degrees)
local function shownViewValue(s, p)
	local v = p[s.key] or 0
	if s.deg then
		return math.deg(v - math.pi / 2)
	elseif s.rad then
		return math.deg(v)
	end
	return v
end

local function tuneValueText(s)
	if not follow then
		return "-"
	end
	if view.preset == "first" then
		if s.key == "anchor" then
			local a = follow.anchor
			return a == nil and "-" or (a == "" and "middle" or a)
		end
		local v = fpFor(UnitDefs[Spring.GetUnitDefID(follow.unitID) or -1])[s.key]
		return s.step < 1 and string.format("%.2f", v) or string.format("%g", v)
	end
	return string.format("%g", round(shownViewValue(s, presetByKey(view.preset) or {}), s.step / 10))
end

local function tuneStep(s, n)
	local name = followedName()
	if not name then
		return
	end
	if view.preset == "first" then
		if s.key == "anchor" then -- the unit's middle ("") or one of its pieces
			local list = { "" }
			for _, piece in ipairs(Spring.GetUnitPieceList(follow.unitID) or {}) do
				list[#list + 1] = piece
			end
			local at = 1
			for i, piece in ipairs(list) do
				if piece == (follow.anchor or "") then
					at = i
				end
			end
			FP.pieces[name] = list[(at - 1 + n) % #list + 1]
			return
		end
		local v = fpFor(UnitDefs[Spring.GetUnitDefID(follow.unitID) or -1])[s.key]
		FP.types[name] = FP.types[name] or {}
		FP.types[name][s.key] = math.max(s.min or -9999, math.min(s.max or 9999, round(v + s.step * n, s.step / 10)))
		return
	end
	local key = view.preset
	local p = copy(presetByKey(key))
	local v = math.max(s.min, math.min(s.max, round(shownViewValue(s, p) + s.step * n, s.step / 10)))
	if s.deg then
		v = math.rad(v) + math.pi / 2
	elseif s.rad then
		v = math.rad(v)
	end
	p[s.key] = v
	if UNIVERSAL[key] then -- (every unit's)
		views[key] = p
	else
		presetTypes[name] = presetTypes[name] or {}
		presetTypes[name][key] = p
	end
	applyPreset(key)
end

-- Save: the universal views (Table, Close, Mid) kept for every unit; the followed unit type's own values kept, and the
-- same given to its equivalents in the other factions
local function tuneSave()
	for key, p in pairs(views) do
		kept.views[key] = copy(p)
	end
	savedAt = now()
	local name = followedName()
	if not name then
		return
	end
	local names = { name }
	for _, o in ipairs(equivalentsOf(name)) do
		names[#names + 1] = o
	end
	for _, n in ipairs(names) do
		if FP.types[name] then
			FP.types[n], kept.types[n] = copy(FP.types[name]), copy(FP.types[name])
		end
		if FP.pieces[name] then
			FP.pieces[n], kept.pieces[n] = FP.pieces[name], FP.pieces[name]
		end
		if presetTypes[name] then
			presetTypes[n], kept.presetTypes[n] = copy(presetTypes[name]), copy(presetTypes[name])
		end
	end
	savedAt = now()
	Spring.Echo("[bardroid-spectate] saved for " .. table.concat(names, ", "))
end

local ACTIONS = {
	player_prev = function() cyclePlayer(-1) end,
	player_next = function() cyclePlayer(1) end,
	free = function() unlockPlayer(); stopFollow() end,
	unit_prev = function() cycleUnit(-1) end,
	unit_next = function() cycleUnit(1) end,
	group = function()
		groupMode = not groupMode
		if follow then
			follow.at = -1
			local x, _, z = spGetUnitPosition(follow.unitID)
			follow.cx, follow.cz = x or follow.cx, z or follow.cz -- (the group is the one around the unit)
		end
	end,
	tune = function()
		tuning = not tuning
		tuneAt = 1
		if tuning and not view.preset then
			applyPreset("mid")
		end
	end,
	tune_prev = function() tuneAt = (tuneAt - 2) % #tuneSettings() + 1 end,
	tune_next = function() tuneAt = tuneAt % #tuneSettings() + 1 end,
	tune_minus = function() local s = tuneSettings()[tuneAt]; if s then tuneStep(s, -1) end end,
	tune_plus = function() local s = tuneSettings()[tuneAt]; if s then tuneStep(s, 1) end end,
	tune_save = tuneSave,
}
for _, p in ipairs(PRESETS) do
	ACTIONS["preset_" .. p.key] = function()
		applyPreset(p.key)
		tuneAt = 1
	end
end

local function isActive()
	local spec = Spring.GetSpectatingState()
	local input = WG.BarDroidInput or "touch" -- (nothing reported yet: the app's own screen is a touch screen)
	return spec and input == "touch" and not Spring.IsGUIHidden()
end

---------------------------------------------------------------------------------------------------------------------
-- the bar

local function playerLabel()
	local id = lockedPlayer()
	if not id then
		return "Player cam", nil
	end
	local name, _, _, teamID = Spring.GetPlayerInfo(id, false)
	return name or "?", teamID and { Spring.GetTeamColor(teamID) }
end

local function followLabel()
	if not follow then
		return "Follow unit", nil
	end
	local def = UnitDefs[Spring.GetUnitDefID(follow.unitID) or -1]
	local name = def and (def.translatedHumanName or def.humanName) or "unit"
	if groupMode then
		name = name .. " +" .. math.max(0, #follow.members - 1)
	end
	return name, follow.team and { Spring.GetTeamColor(follow.team) }
end

-- The bar's buttons ({ x0, y0, x1, y1, action, label, lit, color, size }) as the state is now.
local function layout()
	local vsx, vsy = Spring.GetViewGeometry()
	-- (the presets row is the widest, 6 buttons: on the inner screen it fits left of the player list)
	local h = math.floor(math.min(vsy * 0.085, vsx / 17))
	local gap = math.floor(h * 0.15)
	local fLabel, fColor = followLabel()
	local rowA, rowB
	if follow and tuning then -- one setting of the view on, for the unit type followed
		local s = tuneSettings()[tuneAt] or tuneSettings()[1]
		rowA = {
			{ w = h, action = "tune_prev", label = "<" },
			{ w = h * 2.6, action = "tune_next", label = s and s.label or "-", lit = true },
			{ w = h, action = "tune_next", label = ">" },
			{ w = h, action = "tune_minus", label = "-" },
			{ w = h * 2.2, action = "tune_plus", label = s and tuneValueText(s) or "-" },
			{ w = h, action = "tune_plus", label = "+" },
		}
		rowB = {
			{ w = h * 1.6, action = "tune", label = "Done", lit = true },
			{ w = h * 1.6, action = "tune_save", label = now() - savedAt < 2 and "Saved" or "Save" },
			{ w = h, action = "unit_prev", label = "<" },
			{ w = h * 3.2, action = "unit_next", label = fLabel, color = fColor, lit = true },
			{ w = h, action = "unit_next", label = ">" },
		}
	elseif follow then -- the camera presets in place of the players
		rowA = {}
		for _, p in ipairs(PRESETS) do
			rowA[#rowA + 1] = { w = h * 1.9, action = "preset_" .. p.key, label = p.label, lit = view.preset == p.key }
		end
		rowA[#rowA + 1] = { w = h * 1.4, action = "tune", label = "Tune" }
		rowB = {
			{ w = h * 1.4, action = "free", label = "Free" },
			{ w = h, action = "unit_prev", label = "<" },
			{ w = h * 3.2, action = "unit_next", label = fLabel, color = fColor, lit = true },
			{ w = h, action = "unit_next", label = ">" },
			{ w = h * 1.6, action = "group", label = "Group", lit = groupMode },
		}
	else
		local pLabel, pColor = playerLabel()
		rowA = {
			{ w = h, action = "player_prev", label = "<" },
			{ w = h * 3.2, action = "player_next", label = pLabel, color = pColor, lit = lockedPlayer() ~= nil },
			{ w = h, action = "player_next", label = ">" },
			{ w = h * 1.6, action = "free", label = "Free", lit = not lockedPlayer() },
		}
		rowB = {
			{ w = h, action = "unit_prev", label = "<" },
			{ w = h * 3.2, action = "unit_next", label = fLabel, color = fColor },
			{ w = h, action = "unit_next", label = ">" },
			{ w = h * 1.6, action = "group", label = "Group", lit = groupMode },
		}
	end
	local function width(row)
		local w = 0
		for _, b in ipairs(row) do
			w = w + b.w + gap
		end
		return w - gap
	end
	local out = {}
	local function place(row, x, y)
		for _, b in ipairs(row) do
			out[#out + 1] = { x0 = x, y0 = y, x1 = x + b.w, y1 = y + h, action = b.action, label = b.label,
				lit = b.lit, color = b.color, size = h }
			x = x + b.w + gap
		end
	end
	local y = math.floor(h * 0.25)
	local wa, wb = width(rowA), width(rowB)
	-- the room left of BAR's (small) player list at the bottom right: the bar never runs under it
	local x0, x1 = gap, vsx - gap
	local pos = WG.advplayerlist_api and WG.advplayerlist_api.GetPosition and WG.advplayerlist_api.GetPosition()
	if pos and pos[2] and pos[3] and pos[3] < y + 2 * h + 2 * gap and pos[2] > vsx / 2 then -- { top, left, bottom, right }
		x1 = math.floor(pos[2]) - gap
	end
	local room = x1 - x0
	if wa + wb + gap * 3 <= room then -- one row
		local x = x0 + math.floor((room - (wa + wb + gap * 3)) / 2)
		place(rowA, x, y)
		place(rowB, x + wa + gap * 3, y)
	else -- two rows: the players (or presets) above
		place(rowB, x0 + math.max(0, math.floor((room - wb) / 2)), y)
		place(rowA, x0 + math.max(0, math.floor((room - wa) / 2)), y + h + gap)
	end
	return out
end

local function sameColor(a, b)
	if not (a and b) then
		return a == b
	end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function sameButtons(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		local p, q = a[i], b[i]
		if p.x0 ~= q.x0 or p.y0 ~= q.y0 or p.x1 ~= q.x1 or p.y1 ~= q.y1 or p.label ~= q.label or p.lit ~= q.lit
			or p.action ~= q.action or not sameColor(p.color, q.color) then
			return false
		end
	end
	return true
end

local function buttonAt(x, y)
	for _, b in ipairs(buttons) do
		if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 then
			return b
		end
	end
end

local function drawBar()
	local font = WG.fonts and WG.fonts.getFont()
	for _, b in ipairs(buttons) do
		if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
			WG.FlowUI.Draw.Element(b.x0, b.y0, b.x1, b.y1, 1, 1, 1, 1)
		else
			gl.Color(0, 0, 0, 0.6)
			gl.Rect(b.x0, b.y0, b.x1, b.y1)
		end
		if b.lit then
			gl.Color(1, 1, 1, 0.16)
			gl.Rect(b.x0, b.y0, b.x1, b.y1)
		end
		if b.color then -- the team's colour as a strip along the bottom
			gl.Color(b.color[1], b.color[2], b.color[3], 0.9)
			gl.Rect(b.x0 + 3, b.y0 + 3, b.x1 - 3, b.y0 + math.max(3, b.size * 0.08))
		end
	end
	gl.Color(1, 1, 1, 1)
	if font then
		font:Begin()
		for _, b in ipairs(buttons) do
			local size = b.size * 0.36
			local text = b.label
			local maxW = (b.x1 - b.x0) * 0.9
			while #text > 4 and font:GetTextWidth(text) * size > maxW do
				text = text:sub(1, #text - 2) .. "."
			end
			font:Print(text, (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2 - size * 0.35, size, "oc")
		end
		font:End()
	end
end

-- The bar is drawn into a display list, made again only when a button changes: BAR's FlowUI elements drawn directly
-- cost about 7 KB of garbage each, every frame (tools/spectate-test.ps1 -Cost: 54-75 KB a frame with the bar up).
-- The state is looked at again every LAYOUT_EVERY seconds, or at once after a press or a resize.
local LAYOUT_EVERY = 0.25
local barList, layoutAt, barDirty = nil, -1, true
local barMadeWith -- (BAR's font and FlowUI as they were when the list was made: made again when either turns up)

local function drawTools()
	return (WG.fonts and WG.fonts.getFont() and 1 or 0)
		+ (WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element and 2 or 0)
end

local function dropBarList()
	if barList then
		gl.DeleteList(barList)
		barList = nil
	end
end

function widget:DrawScreen()
	if not shown then
		return
	end
	local t = now()
	if barDirty or t - layoutAt >= LAYOUT_EVERY then
		layoutAt, barDirty = t, false
		local fresh = layout()
		local tools = drawTools()
		if not barList or tools ~= barMadeWith or not sameButtons(fresh, buttons) then
			buttons, barMadeWith = fresh, tools
			dropBarList()
			barList = gl.CreateList(drawBar)
		end
	end
	if barList then
		gl.CallList(barList)
	end
end

function widget:ViewResize()
	barDirty = true
end

function widget:IsAbove(x, y)
	return shown and buttonAt(x, y) ~= nil
end

function widget:GetTooltip(x, y)
	local b = shown and buttonAt(x, y)
	return b and b.label or nil
end

---------------------------------------------------------------------------------------------------------------------
-- taps

function widget:MousePress(x, y, button)
	if not active then
		return false
	end
	local b = shown and buttonAt(x, y)
	if b then
		pressedOn = b
		return true
	end
	if Spring.IsAboveMiniMap(x, y) then
		return false
	end
	-- A tap on the map selects nothing. A tap on a unit of another team spectates that team, as BAR's own spectating
	-- does when a unit is selected (Kailil: "physically touch that unit in game to select them"), so the arrows walk
	-- its units. A second tap quickly at the same place follows the unit there, and the bar comes up.
	pressedOn = nil
	local t = now()
	local unit = pickUnit(x, y) -- (wildlife: none)
	if unit and Spring.GetUnitTeam(unit) ~= Spring.GetMyTeamID() then
		Spring.SendCommands("specteam " .. Spring.GetUnitTeam(unit))
		order = nil
	end
	if button == 1 and lastTap and t - lastTap.t <= DOUBLE_TAP_S and ((math.abs(x - lastTap.x) <= DOUBLE_TAP_PX
		and math.abs(y - lastTap.y) <= DOUBLE_TAP_PX) or (unit and unit == lastTap.unit)) then
		unit = unit or lastTap.unit -- (the second tap a little off: the first one's unit)
		lastTap = nil
		-- (in 1st person this hops to the unit tapped: Kailil, "hop from first person to another unit first person")
		if unit then
			cycle = nil -- (the arrows start again from here)
			startFollow(unit, false) -- (centred on the unit tapped)
			-- the bar with it, on BAR's player list's own timer (Kailil: "display the touch ui with its normal autohide")
			if WG.BarDroidPlayers and WG.BarDroidPlayers.open then
				WG.BarDroidPlayers.open()
			end
		else
			stopFollow()
		end
	elseif button == 1 then
		lastTap = { x = x, y = y, t = t, unit = unit }
	end
	return true
end

function widget:MouseRelease(x, y)
	local b = pressedOn
	pressedOn = nil
	if b and buttonAt(x, y) == b and ACTIONS[b.action] then
		ACTIONS[b.action]()
		barDirty = true -- (the bar shows the press's result in the next frame)
		if WG.BarDroidPlayers and WG.BarDroidPlayers.keepOpen then
			WG.BarDroidPlayers.keepOpen() -- (the list and the bar stay open while the bar is used)
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------

function widget:Update(dt)
	local was = active
	active = isActive()
	WG.BarDroidSpectating = active -- bardroid_info.lua shows no unit then
	-- Nothing stays selected while this is on: BAR's selected-unit panels (info, orders, build menu) never open, whatever
	-- selected the units (the two-finger swipe's select-all, a box). A frame later, not from SelectionChanged: a
	-- selection replaced there is never told to the widgets after it (BAR's build menu kept showing the builder's).
	if active and Spring.GetSelectedUnitsCount() > 0 then
		Spring.SelectUnitArray({})
	end
	-- the bar with BAR's player list: open while it is (without bardroid_players.lua: always)
	local list = WG.BarDroidPlayers
	local wasShown = shown
	shown = active and (not list or (list.barWanted and list.barWanted()) or not (list.minimized and list.minimized()))
	if shown and not wasShown then
		order = players() -- top to bottom as the list shows them now
		barDirty = true
	end
	if not active then
		-- following sticks while spectating, whatever the input (a key no longer ends it): only a far pan lets go
		if was and not Spring.GetSpectatingState() then
			stopFollow()
		end
		updateFollow(dt)
		return
	end
	-- a finger pan takes the camera back from BAR's player camera (following keeps it as an offset, updateFollow)
	local pan = WG.BarDroidPanAt or 0
	if pan ~= panSeen then
		panSeen = pan
		if not follow then
			unlockPlayer()
		end
	end
	-- in 1st person bardroid_touch.lua hands the fingers' moves over as looking (WG.BarDroidLook), not camera moves
	local firstPerson = follow ~= nil and view.preset == "first"
	WG.BarDroidFirstPerson = firstPerson
	if firstPerson and not WG.BarDroidLook then
		WG.BarDroidLook = { dx = 0, dy = 0, zoom = 1, rot = 0, tilt = 0 }
	end
	if not firstPerson then
		look.free = false
	end
	updateFollow(dt)
end

-- 1st person on the laptop: a mouse drag looks around, the wheel sets the FOV (as the fingers do on the phone)
function widget:MouseMove(_, _, dx, dy)
	local L = WG.BarDroidLook
	if WG.BarDroidFirstPerson and L then
		L.dx, L.dy = L.dx + dx, L.dy - dy -- (the engine's y goes up, the fingers' down)
		lastTap = nil -- (a drag is no tap)
	end
	return false
end

function widget:MouseWheel(up)
	local L = WG.BarDroidLook
	if WG.BarDroidFirstPerson and L then
		L.zoom = L.zoom * (up and 1.1 or 1 / 1.1)
		return true
	end
	return false
end

function widget:Initialize()
	-- 1st person as tools/fp-tuner.ps1 saved it (on the laptop; the phone's are the defaults above)
	local fpFile = "LuaUI/Config/bardroid_fp.lua"
	if VFS.FileExists(fpFile, VFS.RAW) then
		local ok, t = pcall(VFS.Include, fpFile, nil, VFS.RAW)
		if ok and type(t) == "table" then
			for k, v in pairs(t) do
				if FP[k] ~= nil and type(v) == type(FP[k]) then
					FP[k] = v
				end
			end
			for key, p in pairs(type(t.presets) == "table" and t.presets or {}) do -- (the other views, as set there)
				if type(p) == "table" and tonumber(p.dist) and tonumber(p.rx) then
					saved[key] = p
				end
			end
			for name, own in pairs(type(t.presetTypes) == "table" and t.presetTypes or {}) do -- (per unit type)
				if type(own) == "table" then
					presetTypes[name] = own
				end
			end
		end
	end
	-- what the player saved on this device (Tune, Save), over the defaults (SetConfigData came first)
	for name, v in pairs(kept.types) do
		FP.types[name] = copy(v)
	end
	for name, v in pairs(kept.pieces) do
		FP.pieces[name] = v
	end
	for name, v in pairs(kept.presetTypes) do
		presetTypes[name] = copy(v)
	end
	for key, v in pairs(kept.views) do
		if UNIVERSAL[key] then
			views[key] = copy(v)
		end
	end
	-- (also for tools/spectate-test.ps1: a user widget cannot send the engine's mouse callins, so its taps come in here)
	WG.BarDroidSpectate = {
		widget = widget, -- (tools/spectate-test.ps1 -Cost times its call-ins; user widgets cannot reach the handler's list)
		actions = ACTIONS,
		following = function() return follow and follow.unitID end,
		members = function() return follow and #follow.members or 0 end,
		shown = function() return shown end,
		label = function() return (playerLabel()) end,
		offset = function() return view.ox, view.oz, view.frame, view.ryRel, follow and follow.yaw end,
		-- 1st person: its settings (tools/fp-tuner.ps1 edits them live), the anchor in use, and following a unit in it
		fp = FP,
		fpFor = function(unitID) return fpFor(UnitDefs[Spring.GetUnitDefID(unitID) or -1]) end,
		unitClass = function(unitID) return unitClass(UnitDefs[Spring.GetUnitDefID(unitID) or -1]) end,
		-- the views (presets): the list, the one on, a view's values, and setting them (applied at once when on)
		views = function() return PRESETS end,
		view = function() return view.preset end,
		presetValues = function(key) return presetByKey(key) end,
		-- (a view set in the laptop tuner: Table, Close and Mid for every unit, the others for the unit type followed,
		-- as on the phone)
		setPreset = function(key, p)
			local name = followedName()
			if UNIVERSAL[key] then
				views[key] = p
			elseif name then
				presetTypes[name] = presetTypes[name] or {}
				presetTypes[name][key] = p
			else
				return
			end
			if view.preset == key then
				applyPreset(key)
			end
		end,
		typeView = function(key)
			if UNIVERSAL[key] then
				return views[key]
			end
			local name = followedName()
			return name and presetTypes[name] and presetTypes[name][key]
		end,
		keptViews = function() return kept.views end,
		saved = function() return saved end,
		presetTypes = function() return presetTypes end,
		equivalentsOf = function(name) return equivalentsOf(name) end,
		tuning = function() return tuning end,
		apply = function(key) applyPreset(key) end,
		anchor = function() return follow and follow.anchor end,
		firstPerson = function(unitID)
			startFollow(unitID, false)
			applyPreset("first")
		end,
		preset = function(key) return presetByKey(key) end,
		tap = function(x, y)
			local taken = widget:MousePress(x, y, 1)
			widget:MouseRelease(x, y, 1)
			return taken
		end,
	}
end

function widget:Shutdown()
	dropBarList()
	closeZoom(false)
	WG.BarDroidSpectate = nil
	WG.BarDroidSpectating = nil
end

-- what the player saved with Tune (per unit type and its equivalents) stays on the device
function widget:GetConfigData()
	return { kept = kept }
end

function widget:SetConfigData(data)
	local k = type(data) == "table" and data.kept
	if type(k) == "table" then
		kept.types = type(k.types) == "table" and k.types or {}
		kept.pieces = type(k.pieces) == "table" and k.pieces or {}
		kept.presetTypes = type(k.presetTypes) == "table" and k.presetTypes or {}
		kept.views = type(k.views) == "table" and k.views or {}
	end
end
