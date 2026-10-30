-- BAR Droid first person on the gamepad (Kailil, 2026-10-30): LB + L3 held 0.3 s rides the selected unit, in the engine's
-- first-person camera with the values Kailil set for each unit type (bardroid_spectate.lua's). The same again, or B, ends
-- it. The app's controls only (PadGame), so online too; BAR's sandbox allows it: these are a camera and ordinary orders.
--   right stick  looks around; left alone for RECENTER_AFTER s the view eases back with the unit
--   left stick   walks the unit where the view points: a move order a little ahead, renewed only when the stick turns or
--                the unit nears it (Kailil: "without spamming the move orders"); nothing is selected meanwhile, so no order
--                lines or unit voices. Let go: the unit stops.
--   RT           fires at the middle of the screen, also while walking: BAR's Set Target (its own order, for "fire on the
--                move"), renewed while RT is held and cancelled when let go; at the sky, a point ahead of the unit.
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

local fp = nil -- { unitID, saved camera, selection before, x, y, z, yaw, lookYaw, lookPitch, lookAt, sticks, ... }
local cam = { mode = CAM_FPS, rz = 0 }

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
	}
end

function widget:Shutdown()
	stop()
	WG.BarDroidPadFP = nil
end
