-- BAR Droid first person on the gamepad (Kailil, 2026-10-30): LB + L3 held 0.3 s rides the selected unit, in the engine's
-- first-person camera at the spectator tools' anchor and values for its type (bardroid_spectate.lua's; Back tunes them
-- here too, Save keeps them for both). The same chord again, or B, ends it. The app's controls only (PadGame), so online
-- too; BAR's sandbox allows it: these are a camera and ordinary orders.
-- The head and the body are apart (Kailil: "so i can move in all directions with the left stick. and look in all
-- directions with the right"):
--   right stick  looks anywhere, whichever way the body faces; left alone for RECENTER_AFTER s only the pitch eases back
--                to the horizon, never the heading
--   left stick   walks the unit that way relative to the view, sideways and backwards too: a move order a little ahead,
--                renewed only when the stick turns or the unit nears it (Kailil: "without spamming the move orders");
--                nothing is selected meanwhile, so no order lines or unit voices. Let go: the unit stops.
--   RT           fires where the view points, standing or walking: BAR's Set Target ("fire on the move"), renewed while RT
--                is held and ended when let go. Its aim is the enemy under the crosshair, the ground the view points at
--                within range, else the ground at full range along the view: the flattest, longest shot there is. Open
--                air cannot be aimed at by a player's order (Kailil: "targets the max range and thin air"): the engine
--                lowers every ground attack to the terrain (CommandAI.cpp AdjustGroundAttackCommand), Set Target's
--                gadget too, and only synced game code gets past that (Spring.SetUnitTarget), which online play has not.
-- The squad (Kailil: "tell all units nearby or that im looking at to follow (guard Me) or stop"; fight and patrol "in a
-- direction"; "a UI telling me what is selected and what orders they have"): the units these orders go to. A unit of
-- yours in the middle of the screen joins it with the next order; an empty squad takes the units within NEARBY (combat
-- units; builders only where there are none).
--   A  follow me (Guard)       X  stop        Y  fight to where I look        RB  patrol to where I look
--   D-pad up  add what I look at, or the units nearby        D-pad down  an empty squad again
-- While riding the build menu's place shows the squad (each unit type, how many, what they are doing), the order menu's
-- the buttons, and BAR's info panel the unit ridden.
-- PadGame learns it is on from bardroid_pad.txt ("fp 1"), bardroid_touch.lua hands the sticks over. Installed into
-- LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid pad first person",
		desc = "Rides and drives a unit in first person on the gamepad",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -95002,
		enabled = true,
	}
end

local CAM_FPS = 0
local CMD_SET_TARGET = (GameCMD and GameCMD.UNIT_SET_TARGET) or 34923 -- luacheck: ignore 113 (BAR's global)
local CMD_CANCEL_TARGET = (GameCMD and GameCMD.UNIT_CANCEL_TARGET) or 34924 -- luacheck: ignore 113
local RECENTER_AFTER, RECENTER_SMOOTHING = 1.5, 0.5
local LOOK_TURN, LOOK_TILT = 2.2, 1.4 -- radians, degrees * 60: a full stick's look a second
local MOVE_AHEAD, MOVE_TURN, MOVE_EVERY = 280, 0.3, 0.8 -- how far the order goes, and what renews it
-- The aim renewed this often; how much of the weapon's range it reaches for (the gun is off the unit's centre, a
-- commander's arm by 23 elmos: walking sideways, 0.97 of its 300 from the body was out of range from the muzzle)
local FIRE_EVERY, FIRE_REACH = 0.25, 0.9
local NEARBY, ORDER_AHEAD = 900, 1400 -- elmos: the units nearby; fight or patrol with the view on the sky
local SUMMARY_SECONDS = 0.25
local STATUS = { [CMD.GUARD] = "Following", [CMD.FIGHT] = "Fighting", [CMD.PATROL] = "Patrolling", [CMD.MOVE] = "Moving",
	[CMD.ATTACK] = "Attacking", [CMD.RECLAIM] = "Reclaiming", [CMD.REPAIR] = "Repairing" }
local BUTTONS = { { "A", "Follow me" }, { "X", "Stop" }, { "Y", "Fight there" }, { "RB", "Patrol there" },
	{ "UP", "Add units" }, { "DN", "Clear squad" }, { "RT", "Fire" }, { "BK", "Tune camera" }, { "B", "Leave" } }
local TUNE_BUTTONS = { { "UP", "Previous" }, { "DN", "Next" }, { "LF", "Less" }, { "RG", "More" },
	{ "A", "Save" }, { "B", "Close" } }

local fp = nil -- { unitID, saved camera, x, y, z (the eye), viewYaw, lookPitch, lookAt, sticks, moving, firing, ... }
local cam = { mode = CAM_FPS, rz = 0 }
local squad, inSquad = {}, {} -- the units the orders go to; unitID -> true
local summary, summaryAt = {}, nil -- per unit type: { defID, count, status }
local lastOrder = nil -- the squad's last order (the panel tells a patrol from a fight by it)
local tuning, tuneAt = false, 1 -- the camera tuner is open; the setting on it (bardroid_spectate.lua's FP_SETTINGS)

local function now()
	return Spring.GetTimer()
end

local function say(text)
	if WG.BarDroidPad and WG.BarDroidPad.say then
		WG.BarDroidPad.say(text)
	end
end

local function unitControl()
	local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
	local v = mo.allowunitcontrolwidgets
	return v == nil or v == true or v == 1 or v == "1" or v == "true"
end

local function unitYaw(unitID)
	local dx, _, dz = Spring.GetUnitDirection(unitID)
	if not dx or (dx == 0 and dz == 0) then
		return nil
	end
	return math.atan2(dx, -dz)
end

-- The values Kailil set for the unit type in the laptop's tuner, and the point the eye rides
local function eyeOf(unitID)
	local s = WG.BarDroidSpectate
	local P = s and s.fpFor and s.fpFor(unitID) or { forward = 16, right = 4, up = 14, pitch = -8, fov = 80 }
	if s and s.anchorOf then
		local x, y, z = s.anchorOf(unitID) -- (its head, say: the piece Kailil's values start from)
		return x, y, z, P
	end
	local _, _, _, mx, my, mz = Spring.GetUnitPosition(unitID, true)
	return mx, my, mz, P
end

-- Mobile units and sentries (armed buildings): the ones the spectator tools follow
local function rideable(unitID)
	local s = WG.BarDroidSpectate
	if s and s.followable then
		return s.followable(unitID)
	end
	local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
	return def ~= nil and ((def.speed or 0) > 0 or #(def.weapons or {}) > 0)
end

local function stop(text)
	local s = fp
	if not s then
		return
	end
	fp = nil
	tuning = false
	if s.firing then
		pcall(Spring.GiveOrderToUnit, s.unitID, CMD_CANCEL_TARGET, {}, 0)
	end
	if s.moving and Spring.ValidUnitID(s.unitID) then
		pcall(Spring.GiveOrderToUnit, s.unitID, CMD.STOP, {}, 0)
	end
	Spring.SetCameraState(s.camera, 0.3)
	if WG.info and WG.info.clearDisplayUnitID then
		WG.info.clearDisplayUnitID()
	end
	if Spring.ValidUnitID(s.unitID) and not Spring.GetUnitIsDead(s.unitID) then
		Spring.SelectUnitArray({ s.unitID })
	end
	say(text or "FIRST PERSON OFF")
end

local function start()
	if not unitControl() or Spring.GetSpectatingState() then -- (a spectator's orders go nowhere: bardroid_spectate.lua's)
		say("NOT IN THIS GAME")
		return
	end
	-- (Kailil, 2026-10-30: "only work on units and sentries": the spectator tools' choice, no other buildings)
	local selected, unitID = Spring.GetSelectedUnits(), nil
	for _, id in ipairs(selected) do
		if rideable(id) then
			unitID = id
			break
		end
	end
	if not unitID then
		say(#selected > 0 and "NOT ON THIS BUILDING" or "SELECT A UNIT")
		return
	end
	local x, y, z = eyeOf(unitID)
	if not x then
		return
	end
	fp = { unitID = unitID, camera = Spring.GetCameraState(), x = x, y = y, z = z, viewYaw = unitYaw(unitID) or 0,
		lookPitch = 0, lookAt = now(), lx = 0, ly = 0, rx = 0, ry = 0, moving = false }
	Spring.SelectUnitArray({}) -- (no order lines, panels or voices while riding)
	if WG.info and WG.info.displayUnitID then
		WG.info.displayUnitID(unitID) -- (the panel at the bottom left: the unit ridden)
	end
	squad, inSquad, summary, summaryAt, lastOrder = {}, {}, {}, nil, nil
	say("FIRST PERSON")
end

local function camera(s, dt)
	local ax, ay, az, P = eyeOf(s.unitID)
	if not ax then
		return false
	end
	-- (the unit type's own smoothing; the anchor's place from the view's frame, not the body's: the eye stays put when the
	-- body turns to walk another way, and looking straight along the body is the spectator's view exactly)
	local kp = P.posSmoothing and P.posSmoothing > 0 and (1 - math.exp(-dt / P.posSmoothing)) or 1
	s.x, s.y, s.z = s.x + (ax - s.x) * kp, s.y + (ay - s.y) * kp, s.z + (az - s.z) * kp
	if s.rx ~= 0 or s.ry ~= 0 then
		s.viewYaw = s.viewYaw + s.rx * LOOK_TURN * dt
		s.lookPitch = math.max(-80, math.min(80, s.lookPitch - s.ry * LOOK_TILT * 60 * dt))
		s.lookAt = now()
	elseif s.firing then
		s.lookAt = now() -- (the aim stays where it is while RT is held)
	elseif Spring.DiffTimers(now(), s.lookAt) > RECENTER_AFTER then -- (the horizon only: the heading stays the player's)
		s.lookPitch = s.lookPitch * math.exp(-dt / RECENTER_SMOOTHING)
	end
	local fx, fz = math.sin(s.viewYaw), -math.cos(s.viewYaw)
	local rx, rz = -fz, fx
	local ex, ez = s.x + fx * P.forward + rx * P.right, s.z + fz * P.forward + rz * P.right
	local ey = s.y + P.up
	local ry = s.viewYaw + math.rad(P.yaw or 0)
	local pitchDeg = P.pitch + s.lookPitch
	local pitch = math.pi / 2 - math.rad(pitchDeg) -- (rx: pi/2 level, more is down)
	local c = cam
	c.px, c.py, c.pz, c.rx, c.ry, c.fov = ex, ey, ez, pitch, ry, P.fov
	c.dx, c.dy, c.dz = math.sin(pitch) * math.sin(ry), math.cos(pitch), -math.sin(pitch) * math.cos(ry)
	c.oldHeight = ey - Spring.GetGroundHeight(ex, ez)
	Spring.SetCameraState(c, 0)
	s.aimYaw, s.aimPitch = ry, math.rad(pitchDeg)
	return true
end

local function walk(s)
	local def = UnitDefs[Spring.GetUnitDefID(s.unitID) or -1]
	if not def or (def.speed or 0) <= 0 then -- (a sentry looks and fires, it does not walk)
		return
	end
	local moved = s.lx ~= 0 or s.ly ~= 0
	if not moved then
		if s.moving then
			s.moving, s.moveDir, s.fireAt = false, nil, nil -- (a stop ends a Set Target too: the next pass gives it again)
			pcall(Spring.GiveOrderToUnit, s.unitID, CMD.STOP, {}, 0)
		end
		return
	end
	local fx, fz = math.sin(s.viewYaw), -math.cos(s.viewYaw)
	local rx, rz = -fz, fx
	local dx, dz = rx * s.lx - fx * s.ly, rz * s.lx - fz * s.ly
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.001 then
		return
	end
	local dir = math.atan2(dx, -dz)
	local t = now()
	local turned = s.moveDir == nil or math.abs((dir - s.moveDir + math.pi) % (2 * math.pi) - math.pi) > MOVE_TURN
	if not s.moving or turned or Spring.DiffTimers(t, s.moveAt) > MOVE_EVERY then
		local ux, _, uz = Spring.GetUnitPosition(s.unitID)
		if ux then
			local ahead = math.max(MOVE_AHEAD, def.speed * MOVE_EVERY * 1.5) -- (a plane is past MOVE_AHEAD before the next one)
			local x = math.max(0, math.min(Game.mapSizeX, ux + dx / len * ahead))
			local z = math.max(0, math.min(Game.mapSizeZ, uz + dz / len * ahead))
			if pcall(Spring.GiveOrderToUnit, s.unitID, CMD.MOVE, { x, Spring.GetGroundHeight(x, z), z }, 0) then
				s.moving, s.moveDir, s.moveAt = true, dir, t
			end
		end
	end
end

local function reachOf(s)
	local def = UnitDefs[Spring.GetUnitDefID(s.unitID) or -1]
	return math.max(60, (def and def.maxWeaponRange or 300) * FIRE_REACH)
end

local function enemyAimed(s)
	local vsx, vsy = Spring.GetViewGeometry()
	local kind, target = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2))
	if kind == "unit" and target ~= s.unitID and not Spring.IsUnitAllied(target) then
		return target
	end
	return nil
end

-- The ground the view points at within reach, else the ground at reach along the view (BAR's Set Target takes only
-- ground, in range: allowTargetPos)
local function groundAim(s)
	local vsx, vsy = Spring.GetViewGeometry()
	local ux, _, uz = Spring.GetUnitPosition(s.unitID)
	local reach = reachOf(s)
	local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2), true)
	local dx, dz = math.sin(s.aimYaw) * reach, -math.cos(s.aimYaw) * reach
	if pos and s.aimPitch < 0 then
		local gx, gz = pos[1] - ux, pos[3] - uz
		local d = math.sqrt(gx * gx + gz * gz)
		if d <= reach then
			dx, dz = gx, gz
		end
	end
	local x = math.max(0, math.min(Game.mapSizeX, ux + dx))
	local z = math.max(0, math.min(Game.mapSizeZ, uz + dz))
	return { x, Spring.GetGroundHeight(x, z), z }
end

local function fire(s)
	if not s.firing then
		return
	end
	local t = now()
	if not s.fireAt or Spring.DiffTimers(t, s.fireAt) > FIRE_EVERY then
		s.fireAt = t
		local target = enemyAimed(s)
		pcall(Spring.GiveOrderToUnit, s.unitID, CMD_SET_TARGET, target and { target } or groundAim(s), 0)
	end
end

-- The squad

local function joinSquad(unitID)
	if not inSquad[unitID] then
		inSquad[unitID] = true
		squad[#squad + 1] = unitID
	end
end

local function cleanSquad()
	local alive = {}
	for _, unitID in ipairs(squad) do
		if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
			alive[#alive + 1] = unitID
		else
			inSquad[unitID] = nil
		end
	end
	squad = alive
end

-- A unit of the player's in the middle of the screen (not the one ridden, not a building)
local function lookedAt(s)
	local vsx, vsy = Spring.GetViewGeometry()
	local kind, target = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2))
	if kind == "unit" and target ~= s.unitID and Spring.GetUnitTeam(target) == Spring.GetMyTeamID() then
		local def = UnitDefs[Spring.GetUnitDefID(target) or -1]
		if def and (def.speed or 0) > 0 then
			return target
		end
	end
	return nil
end

-- The units within NEARBY: combat units; builders only where there are none (as the area select)
local function joinNearby(s)
	local combat, builders = {}, {}
	for _, unitID in ipairs(Spring.GetUnitsInCylinder(s.x, s.z, NEARBY, Spring.GetMyTeamID()) or {}) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
		if unitID ~= s.unitID and def and (def.speed or 0) > 0 and not Spring.GetUnitIsBeingBuilt(unitID) then
			local list = def.isBuilder and builders or combat
			list[#list + 1] = unitID
		end
	end
	for _, unitID in ipairs(#combat > 0 and combat or builders) do
		joinSquad(unitID)
	end
end

-- Where a fight or patrol goes: the ground the view points at, or on the sky a long way ahead
local function orderPoint(s)
	local vsx, vsy = Spring.GetViewGeometry()
	local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2), true)
	if pos then
		return { pos[1], pos[2], pos[3] }
	end
	local x = math.max(0, math.min(Game.mapSizeX, s.x + math.sin(s.viewYaw) * ORDER_AHEAD))
	local z = math.max(0, math.min(Game.mapSizeZ, s.z - math.cos(s.viewYaw) * ORDER_AHEAD))
	return { x, Spring.GetGroundHeight(x, z), z }
end

local function give(cmdID, params, name)
	if pcall(Spring.GiveOrderToUnitArray, squad, cmdID, params, 0) then
		say(name .. ": " .. #squad)
	end
	summaryAt = nil
end

-- The camera tuner (Back): the spectator tools' settings for the unit type ridden, kept for both with Save

local function tuneList()
	local s = WG.BarDroidSpectate
	return s and s.fpSettings
end

local function tune(kind)
	local list, api = tuneList(), WG.BarDroidSpectate
	if not list then
		return
	end
	if kind == "add" then
		tuneAt = (tuneAt - 2) % #list + 1
	elseif kind == "clear" then
		tuneAt = tuneAt % #list + 1
	elseif kind == "left" or kind == "right" then
		api.fpTuneStep(fp.unitID, list[tuneAt], kind == "left" and -1 or 1)
	elseif kind == "follow" then
		api.fpTuneSave(fp.unitID)
		say("CAMERA SAVED")
	elseif kind == "tune" then
		tuning = false
	end
end

local function order(kind)
	local s = fp
	if not s then
		return
	end
	if tuning then
		tune(kind)
		return
	end
	if kind == "tune" then
		tuning = tuneList() ~= nil
		return
	elseif kind == "left" or kind == "right" then
		return
	end
	cleanSquad()
	if kind == "clear" then
		squad, inSquad, summaryAt = {}, {}, nil
		say("SQUAD CLEARED")
		return
	end
	local looked = lookedAt(s)
	if looked then
		joinSquad(looked)
	elseif kind == "add" or #squad == 0 then
		joinNearby(s)
	end
	summaryAt = nil
	if kind ~= "add" then
		lastOrder = kind
	end
	if #squad == 0 then
		say("NO UNITS NEAR")
	elseif kind == "add" then
		say("SQUAD: " .. #squad)
	elseif kind == "follow" then
		give(CMD.GUARD, { s.unitID }, "FOLLOW ME")
	elseif kind == "stop" then
		give(CMD.STOP, {}, "STOP")
	elseif kind == "fight" then
		give(CMD.FIGHT, orderPoint(s), "FIGHT")
	elseif kind == "patrol" then
		give(CMD.PATROL, orderPoint(s), "PATROL")
	end
end

-- What the squad is doing, per unit type: how many, and what most of them do
local function summarize()
	local t = now()
	if summaryAt and Spring.DiffTimers(t, summaryAt) < SUMMARY_SECONDS then
		return
	end
	summaryAt = t
	cleanSquad()
	local byType, list = {}, {}
	for _, unitID in ipairs(squad) do
		local defID = Spring.GetUnitDefID(unitID)
		local entry = byType[defID]
		if not entry then
			entry = { defID = defID, count = 0, seen = {} }
			byType[defID] = entry
			list[#list + 1] = entry
		end
		entry.count = entry.count + 1
		local cmdID = Spring.GetUnitCurrentCommand(unitID)
		local status = cmdID and (STATUS[cmdID] or "Busy") or "Holding"
		if cmdID == CMD.FIGHT and lastOrder == "patrol" then
			status = "Patrolling" -- (the engine walks a patrol as a fight, with the patrol queued behind it)
		end
		entry.seen[status] = (entry.seen[status] or 0) + 1
	end
	for _, entry in ipairs(list) do
		local most = 0
		for status, n in pairs(entry.seen) do
			if n > most then
				entry.status, most = status, n
			end
		end
	end
	table.sort(list, function(a, b)
		return a.count > b.count
	end)
	summary = list
end

-- The panels: the squad where the build menu is, the buttons where the order menu is (BAR's look, WG.BarDroidStyle)

local function menuPlace(vsx, vsy)
	local o = WG.ordermenu
	if o and o.getPosition then
		local x, y, w, h = o.getPosition()
		if x and y and w and h then
			return math.floor(x * vsx), math.floor((y - h) * vsy), math.floor((x + w) * vsx), math.floor(y * vsy)
		end
	end
	return math.floor(vsx * 0.36), 0, math.floor(vsx * 0.71), math.floor(vsy * 0.28)
end

local function drawSquad(style, font, x1, y0, vsy)
	local x0 = 0
	local size = style.size(0.02, 11)
	local pad = math.floor(size * 0.6)
	local rowH = math.floor(size * 2.2)
	local rows = math.min(#summary, 7)
	local h = rows == 0 and pad * 2 + size or pad * 3 + size + rows * rowH -- (empty: one line, the view stays free)
	local y1 = math.min(y0 + h, math.floor(vsy * 0.68))
	style.panel(x0, y0, x1, y1, 1)
	font:Begin()
	font:SetOutlineColor(0, 0, 0, 0.6)
	font:SetTextColor(style.GOLD[1], style.GOLD[2], style.GOLD[3], 1)
	font:Print(rows == 0 and "Squad: none" or "Squad: " .. #squad, x0 + pad, y1 - pad - size * 0.85, size, "o")
	font:End()
	local numW = #tostring(summary[1] and summary[1].count or 1) * size * 0.62 -- (the counts in a column: the biggest is first)
	for i = 1, rows do
		local e = summary[i]
		local top = y1 - pad * 2 - size - (i - 1) * rowH
		local icon = rowH - 4
		gl.Color(1, 1, 1, 1)
		gl.Texture("#" .. e.defID)
		gl.TexRect(x0 + pad, top - icon, x0 + pad + icon, top)
		gl.Texture(false)
		local def = UnitDefs[e.defID]
		font:Begin()
		font:SetOutlineColor(0, 0, 0, 0.6)
		font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 1)
		local tx = x0 + pad * 2 + icon + numW
		font:Print(tostring(e.count), tx, top - icon * 0.62, size, "ro")
		font:Print(def and (def.translatedHumanName or def.humanName) or "", tx + size * 0.7, top - icon * 0.62, size, "o")
		font:SetTextColor(style.BLUE[1], style.BLUE[2], style.BLUE[3], 1)
		font:Print(e.status or "", x1 - pad, top - icon * 0.62, size, "ro")
		font:End()
	end
	gl.Color(1, 1, 1, 1)
end

local function drawButtons(style, font, x0, y0, x1, y1, buttons)
	style.panel(x0, y0, x1, y1, 1)
	local size = style.size(0.019, 11)
	local pad = math.floor(size * 0.8)
	local cols, rows = 2, math.ceil(#buttons / 2)
	local cw, ch = (x1 - x0 - pad) / cols, (y1 - y0 - pad) / rows
	local chip = math.floor(math.min(ch * 0.72, size * 1.7))
	for i, b in ipairs(buttons) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local x = math.floor(x0 + pad + col * cw)
		local y = math.floor(y1 - pad / 2 - (row + 1) * ch + (ch - chip) / 2)
		if style.KEYS[b[1]] then
			style.key(x, y, chip, b[1], 1)
		else
			local w = math.floor(chip * 1.5)
			style.fill(x, y, x + w, y + chip, { 0.2, 0.2, 0.2, 0.95 }, 1)
			font:Begin()
			font:SetOutlineColor(0, 0, 0, 0.6)
			font:SetTextColor(1, 1, 1, 1)
			font:Print(b[1], x + w / 2, y + chip / 2 - chip * 0.2, chip * 0.55, "co")
			font:End()
		end
		font:Begin()
		font:SetOutlineColor(0, 0, 0, 0.6)
		font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 1)
		font:Print(b[2], x + chip * 1.7, y + chip / 2 - size * 0.36, size, "o")
		font:End()
	end
	gl.Color(1, 1, 1, 1)
end

-- The tuner, in the squad's place: every setting with its value in two columns (the minimap stays free), the one on the
-- D-pad in gold
local function drawTuner(style, font, x1, y0, vsy)
	local list, api = tuneList(), WG.BarDroidSpectate
	local size = style.size(0.018, 11)
	local pad = math.floor(size * 0.6)
	local rowH = math.floor(size * 1.5)
	local rows = math.ceil(#list / 2)
	local gap = pad * 2
	local leftW = math.floor((x1 - pad * 4 - gap) * 0.43) -- (the longer labels are in the second)
	local rightW = x1 - pad * 4 - gap - leftW
	local fit = 1 -- (a narrow screen: the text comes down to its columns)
	for i, setting in ipairs(list) do
		local w = (font:GetTextWidth(setting.label) + font:GetTextWidth(api.fpTuneValue(fp.unitID, setting))) * size + pad
		fit = math.min(fit, (i > rows and rightW or leftW) / w)
	end
	local h = pad * 3 + size + rows * rowH
	local y1 = math.min(y0 + h, math.floor(vsy * 0.86))
	style.panel(0, y0, x1, y1, 1)
	local def = UnitDefs[Spring.GetUnitDefID(fp.unitID) or -1]
	font:Begin()
	font:SetOutlineColor(0, 0, 0, 0.6)
	font:SetTextColor(style.GOLD[1], style.GOLD[2], style.GOLD[3], 1)
	font:Print("Camera: " .. (def and (def.translatedHumanName or def.humanName) or ""), pad, y1 - pad - size * 0.85, size, "o")
	for i, setting in ipairs(list) do
		local lit = i == tuneAt
		local c = lit and style.GOLD or style.TEXT
		local y = y1 - pad * 2 - size - ((i - 1) % rows + 1) * rowH + rowH * 0.3
		local left = pad * 2 + (i > rows and leftW + gap or 0)
		font:SetTextColor(c[1], c[2], c[3], lit and 1 or 0.8)
		font:Print(setting.label, left, y, size * fit, "o")
		font:Print(api.fpTuneValue(fp.unitID, setting), left + (i > rows and rightW or leftW), y, size * fit, "ro")
	end
	font:End()
	gl.Color(1, 1, 1, 1)
end

function widget:DrawScreen()
	if not fp then
		return
	end
	local style, font = WG.BarDroidStyle, WG.fonts and WG.fonts.getFont()
	if not (style and font) then
		return
	end
	local vsx, vsy = Spring.GetViewGeometry()
	local x0, y0, x1, y1 = menuPlace(vsx, vsy)
	-- the crosshair (the app hides the pointer meanwhile): a thin ring and a dot, gold while firing
	local cx, cy, r = math.floor(vsx / 2), math.floor(vsy / 2), style.size(0.014, 8)
	local c = fp.firing and style.GOLD or { 1, 1, 1 }
	for pass = 1, 2 do -- (a dark edge first: it has to show on a pale sky too)
		gl.Color(pass == 1 and 0 or c[1], pass == 1 and 0 or c[2], pass == 1 and 0 or c[3], pass == 1 and 0.65 or 0.95)
		gl.LineWidth(pass == 1 and 4 or 1.5)
		gl.BeginEnd(GL.LINE_LOOP, function()
			for i = 0, 39 do
				local a = i / 40 * 2 * math.pi
				gl.Vertex(cx + math.cos(a) * r, cy + math.sin(a) * r)
			end
		end)
	end
	gl.LineWidth(1)
	style.disc(cx, cy, math.max(1.5, r * 0.12) + 1.5, { 0, 0, 0 }, 0.65)
	style.disc(cx, cy, math.max(1.5, r * 0.12), c, 0.95)
	if tuning then
		drawTuner(style, font, x0, y1, vsy)
		drawButtons(style, font, x0, y0, x1, y1, TUNE_BUTTONS)
		return
	end
	summarize()
	drawSquad(style, font, x0, y1, vsy)
	drawButtons(style, font, x0, y0, x1, y1, BUTTONS)
end

function widget:DrawWorld() -- (a ring under each unit of the squad)
	if not fp or #squad == 0 then
		return
	end
	gl.DepthTest(false)
	gl.LineWidth(2)
	gl.Color(1, 0.78, 0.25, 0.8)
	for _, unitID in ipairs(squad) do
		local x, y, z = Spring.GetUnitPosition(unitID)
		if x then
			gl.DrawGroundCircle(x, y, z, 24, 16)
		end
	end
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

function widget:Update(dt)
	local s = fp
	if not s then
		return
	end
	if not Spring.ValidUnitID(s.unitID) or Spring.GetUnitIsDead(s.unitID) then
		stop("UNIT LOST")
		return
	end
	if Spring.GetSelectedUnitsCount() > 0 then
		Spring.SelectUnitArray({})
	end
	if not camera(s, dt) then
		stop("UNIT LOST")
		return
	end
	walk(s)
	fire(s)
end

function widget:Initialize()
	WG.BarDroidPadFP = {
		active = function()
			return fp ~= nil
		end,
		stop = stop,
		toggle = function()
			if tuning then -- (B closes the tuner first)
				tuning = false
			elseif fp then
				stop()
			else
				start()
			end
		end,
		fire = function(on)
			if fp then
				fp.firing, fp.fireAt = on, nil
				if not on then
					pcall(Spring.GiveOrderToUnit, fp.unitID, CMD_CANCEL_TARGET, {}, 0)
				end
			end
		end,
		sticks = function(lx, ly, rx, ry) -- (bardroid_touch.lua, -1..1)
			if fp then
				fp.lx, fp.ly, fp.rx, fp.ry = lx, ly, rx, ry
			end
		end,
		order = order, -- (bardroid_pad.lua: fp_order_<follow|stop|fight|patrol|add|clear>)
		squad = function() -- (tests: the squad)
			return squad
		end,
	}
end

function widget:Shutdown()
	stop()
	WG.BarDroidPadFP = nil
end
