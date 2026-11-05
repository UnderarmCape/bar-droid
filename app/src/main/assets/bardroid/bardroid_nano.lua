-- BAR Droid nano spray: builders' nano spray drawn by the engine, at most CAP particles (Kailil, 2026-11-05: "Builders
-- nano spray, can it be capped at only showing x amount?"). BAR's own nano effect (gfx_nano_particles_gl4.lua, an
-- unsynced gadget) draws 3D shapes with a floor of 5000 particles; in a late 8v8 on the dev phone it took ~1-1.3 ms of
-- Lua and ~0.35 ms of drawing a frame and ~0.6 ms of GPU. With BAR's own setting NanoParticleMode at 0 (its gfx options'
-- engine spray) the gadget skips all of that and the engine draws the spray, which takes a plain cap
-- (MaxNanoParticles). The gadget hands the engine a budget of 34% of MaxParticles when it switches (it reads the setting
-- about once a second), so the cap is put back after it. The switch is made once a game: a player who picks BAR's shapes
-- again in its options keeps them for that game. Older BAR releases without the engine mode (the controller game, old
-- replays) keep their own spray; the cap then touches nothing (their gadget keeps the engine's at 0).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid nano spray",
		desc = "Builders' nano spray drawn by the engine, at most 1000 particles",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local CAP = 1000
local STEP = 2 -- seconds between looks (the gadget answers a change within one)

local switched, last = false, nil

function widget:Update()
	local now = Spring.GetTimer()
	if last and Spring.DiffTimers(now, last) < STEP then
		return
	end
	last = now
	if not switched then
		switched = true
		if Spring.GetConfigInt("NanoParticleMode", 1) ~= 0 then
			Spring.SetConfigInt("NanoParticleMode", 0)
		end
		Spring.Echo("[bardroid-nano] builders' nano spray: the engine's, at most " .. CAP .. " particles")
		return
	end
	-- (the engine's budget at 0 while BAR's shapes run: left alone)
	if Spring.GetConfigInt("NanoParticleMode", 1) == 0 and Spring.GetConfigInt("MaxNanoParticles", 0) > CAP then
		Spring.SetConfigInt("MaxNanoParticles", CAP)
	end
end
