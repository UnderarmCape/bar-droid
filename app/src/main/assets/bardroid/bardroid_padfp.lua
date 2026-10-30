-- BAR Droid first person on the gamepad (Kailil, 2026-10-30): LB + L3 held 0.3 s rides the selected unit, in the engine's
-- first-person camera with the values Kailil set for each unit type (bardroid_spectate.lua's). The same again, or B, ends
-- it. The app's controls only (PadGame), so online too; BAR's sandbox allows it: these are a camera and ordinary orders.
--   right stick  looks around; left alone for RECENTER_AFTER s the view eases back with the unit
--   left stick   walks the unit where the view points: a move order a little ahead, renewed only when the stick turns or
--                the unit nears it (Kailil: "without spamming the move orders"); nothing is selected meanwhile, so no order
--                lines or unit voices. Let go: the unit stops.
--   RT           fires at the middle of the screen, also while walking: BAR's Set Target (its own order, for "fire on the
--                move"), renewed while RT is held and cancelled when let go; at the sky, a point ahead of the unit.
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
local FIRE_EVERY, FIRE_SKY = 0.25, 600
local POS_SMOOTHING, TURN_SMOOTHING = 0.12, 0.2
local NEARBY, ORDER_AHEAD = 900, 1400 -- elmos: the units nearby; fight or patrol with the view on the sky
local SUMMARY_SECONDS = 0.25
local STATUS = { [CMD.GUARD] = "Following", [CMD.FIGHT] = "Fighting", [CMD.PATROL] = "Patrolling", [CMD.MOVE] = "Moving",
	[CMD.ATTACK] = "Attacking", [CMD.RECLAIM] = "Reclaiming", [CMD.REPAIR] = "Repairing" }
local BUTTONS = { { "A", "Follow me" }, { "X", "Stop" }, { "Y", "Fight there" }, { "RB", "Patrol there" },
	{ "UP", "Add units" }, { "DN", "Clear squad" }, { "RT", "Fire" }, { "B", "Leave" } }

local fp = nil -- { unitID, saved camera, selection before, x, y, z, yaw, lookYaw, lookPitch, lookAt, sticks, ... }
local cam = { mode = CAM_FPS, rz = 0 }
local squad, inSquad = {}, {} -- the units the orders go to; unitID -> true
local summary, summaryAt = {}, nil -- per unit type: { defID, count, status }
local lastOrder = nil -- the squad's last order (the panel tells a patrol from a fight by it)

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

local function angleTo(from, to, k)
	return from + ((to - from + math.pi) % (2 * math.pi) - math.pi) * k
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

local function stop(text)
	local s = fp
	if not s then
		return
	end
	fp = nil
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
	if not unitControl() then
		say("NOT IN THIS GAME")
		return
	end
	local unitID = Spring.GetSelectedUnits()[1]
	if not unitID then
		say("SELECT A UNIT")
		return
	end
	local x, y, z = eyeOf(unitID)
	if not x then
		return
	end
	fp = { unitID = unitID, camera = Spring.GetCameraState(), x = x, y = y, z = z, yaw = unitYaw(unitID) or 0,
		lookYaw = 0, lookPitch = 0, lookAt = now(), lx = 0, ly = 0, rx = 0, ry = 0, moving = false }
	Spring.SelectUnitArray({}) -- (no order lines, panels or voices while riding)
	if WG.info and WG.info.displayUnitID then
		WG.info.displayUnitID(unitID) -- (the panel at the bottom left: the unit ridden)
	end
	squad, inSquad, summary, summaryAt = {}, {}, {}, nil
	say("FIRST PERSON")
end

local function camera(s, dt)
	local ax, ay, az, P = eyeOf(s.unitID)
	if not ax then
		return false
	end
	local kp = 1 - math.exp(-dt / POS_SMOOTHING)
	local kt = 1 - math.exp(-dt / TURN_SMOOTHING)
	s.x, s.y, s.z = s.x + (ax - s.x) * kp, s.y + (ay - s.y) * kp, s.z + (az - s.z) * kp
	s.yaw = angleTo(s.yaw, unitYaw(s.unitID) or s.yaw, kt)
	if s.rx ~= 0 or s.ry ~= 0 then
		s.lookYaw = s.lookYaw + s.rx * LOOK_TURN * dt
		s.lookPitch = math.max(-80, math.min(80, s.lookPitch - s.ry * LOOK_TILT * 60 * dt))
		s.lookAt = now()
	elseif Spring.DiffTimers(now(), s.lookAt) > RECENTER_AFTER then
		local k = 1 - math.exp(-dt / RECENTER_SMOOTHING)
		s.lookYaw = angleTo(s.lookYaw, 0, k)
		s.lookPitch = s.lookPitch + (0 - s.lookPitch) * k
	end
	local fx, fz = math.sin(s.yaw), -math.cos(s.yaw)
	local rx, rz = -fz, fx
	local ex, ez = s.x + fx * P.forward + rx * P.right, s.z + fz * P.forward + rz * P.right
	local ey = s.y + P.up
	local ry = s.yaw + math.rad(P.yaw or 0) + s.lookYaw
	local pitch = math.pi / 2 - math.rad(P.pitch + s.lookPitch) -- (rx: pi/2 level, more is down)
	local c = cam
	c.px, c.py, c.pz, c.rx, c.ry, c.fov = ex, ey, ez, pitch, ry, P.fov
	c.dx, c.dy, c.dz = math.sin(pitch) * math.sin(ry), math.cos(pitch), -math.sin(pitch) * math.cos(ry)
	c.oldHeight = ey - Spring.GetGroundHeight(ex, ez)
	Spring.SetCameraState(c, 0)
	s.viewYaw = ry
	return true
end

local function walk(s)
	local moved = s.lx ~= 0 or s.ly ~= 0
	if not moved then
		if s.moving then
			s.moving = false
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
			local x = math.max(0, math.min(Game.mapSizeX, ux + dx / len * MOVE_AHEAD))
			local z = math.max(0, math.min(Game.mapSizeZ, uz + dz / len * MOVE_AHEAD))
			if pcall(Spring.GiveOrderToUnit, s.unitID, CMD.MOVE, { x, Spring.GetGroundHeight(x, z), z }, 0) then
				s.moving, s.moveDir, s.moveAt = true, dir, t
			end
		end
	end
end

-- Where the middle of the screen points: an enemy unit, the ground, or (the sky) ahead of the unit. BAR's Set Target
-- takes no ground out of the unit's range (allowTargetPos), so a far point comes in along the line to it.
local function aimPoint(s)
	local vsx, vsy = Spring.GetViewGeometry()
	local kind, target = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2))
	if kind == "unit" and target ~= s.unitID and not Spring.IsUnitAllied(target) then
		return { target }
	end
	local ux, _, uz = Spring.GetUnitPosition(s.unitID)
	local def = UnitDefs[Spring.GetUnitDefID(s.unitID) or -1]
	local reach = math.max(60, (def and def.maxWeaponRange or FIRE_SKY) * 0.9)
	local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2), true)
	local dx, dz = math.sin(s.viewYaw) * reach, -math.cos(s.viewYaw) * reach
	if pos then
		dx, dz = pos[1] - ux, pos[3] - uz
		local d = math.sqrt(dx * dx + dz * dz)
		if d > reach then
			dx, dz = dx / d * reach, dz / d * reach
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
		pcall(Spring.GiveOrderToUnit, s.unitID, CMD_SET_TARGET, aimPoint(s), 0)
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
	local x = math.max(0, math.min(Game.mapSizeX, s.x + math.sin(s.viewYaw or s.yaw) * ORDER_AHEAD))
	local z = math.max(0, math.min(Game.mapSizeZ, s.z - math.cos(s.viewYaw or s.yaw) * ORDER_AHEAD))
	return { x, Spring.GetGroundHeight(x, z), z }
end

local function give(cmdID, params, name)
	if pcall(Spring.GiveOrderToUnitArray, squad, cmdID, params, 0) then
		say(name .. ": " .. #squad)
	end
	summaryAt = nil
end

local function order(kind)
	local s = fp
	if not s then
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
	local h = pad * 3 + size + math.max(1, rows) * rowH
	local y1 = math.min(y0 + h, math.floor(vsy * 0.68))
	style.panel(x0, y0, x1, y1, 1)
	font:Begin()
	font:SetOutlineColor(0, 0, 0, 0.6)
	font:SetTextColor(style.GOLD[1], style.GOLD[2], style.GOLD[3], 1)
	font:Print("Squad: " .. #squad, x0 + pad, y1 - pad - size * 0.85, size, "o")
	font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 0.75)
	if rows == 0 then
		font:Print("none yet: an order takes the units nearby", x0 + pad, y1 - pad * 2 - size * 2, size * 0.85, "o")
	end
	font:End()
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
		font:Print(e.count .. "  " .. (def and (def.translatedHumanName or def.humanName) or ""), x0 + pad * 2 + icon, top - icon * 0.62, size, "o")
		font:SetTextColor(style.BLUE[1], style.BLUE[2], style.BLUE[3], 1)
		font:Print(e.status or "", x1 - pad, top - icon * 0.62, size, "ro")
		font:End()
	end
	gl.Color(1, 1, 1, 1)
end

local function drawButtons(style, font, x0, y0, x1, y1)
	style.panel(x0, y0, x1, y1, 1)
	local size = style.size(0.019, 11)
	local pad = math.floor(size * 0.8)
	local cols, rows = 2, math.ceil(#BUTTONS / 2)
	local cw, ch = (x1 - x0 - pad) / cols, (y1 - y0 - pad) / rows
	local chip = math.floor(math.min(ch * 0.72, size * 1.7))
	for i, b in ipairs(BUTTONS) do
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
	summarize()
	drawSquad(style, font, x0, y1, vsy)
	drawButtons(style, font, x0, y0, x1, y1)
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
		toggle = function()
			if fp then
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
