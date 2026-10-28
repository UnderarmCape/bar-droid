-- LuaUI widget for tools/spectate-test.ps1 -Cost: what bardroid_spectate.lua costs per frame (Kailil, 2026-10-28: "so
-- its not adding a large performance overhead"). Fast-forwards into the replay, then measures the spectate widget's
-- call-ins (all of them, wrapped) in phases of PHASE_S real seconds at normal speed, with Lua's garbage collector stopped
-- while measuring so the allocations count exactly:
--   off        not in use (a mouse was used: the state every player is in outside spectating)
--   bar        spectating, the bar up, nothing followed
--   follow     following the unit nearest the screen's centre (Close)
--   group      following its group
--   first      1st person on it
--   hidden     1st person with the bar closed again (how it is most of the time)
-- Logs "[spectcost] <phase>: <ms> ms and <KB> KB per frame (<frames> frames, frame <ms> ms)" and "[spectest] done".
function widget:GetInfo()
	return { name = "BAR Droid spectate cost", desc = "Measures bardroid_spectate.lua per frame", author = "BAR Droid",
		layer = -999999, enabled = true }
end

local SKIP = 600 -- game seconds: armies on the map
local PHASE_S = 12
local SETTLE_S = 2
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local spGetTimerMicros = Spring.GetTimerMicros or Spring.GetTimer
local micro = Spring.GetTimerMicros ~= nil
local t0 = spGetTimer()
local skipSent, ready = false, false
local target -- the spectate widget
local acc = { ms = 0, kb = 0, calls = 0 }
local measuring = false
local phases = { "off", "bar", "follow", "group", "first", "hidden" }
local HIDE_S = 9 -- (BAR's player list closes the bar 7 s after its last use)
local phase, phaseAt, frames, frameMs, lastFrame = 0, 0, 0, 0, nil

local function now()
	return spDiffTimers(spGetTimer(), t0)
end

local function log(s)
	Spring.Echo("[spectcost] " .. s)
end

local function wrap(w)
	for name, f in pairs(w) do
		if type(f) == "function" and name ~= "GetInfo" and name:match("^[A-Z]") then
			w[name] = function(...)
				if not measuring then
					return f(...)
				end
				local m0, t = collectgarbage("count"), spGetTimerMicros()
				local a, b, c, d = f(...)
				acc.ms = acc.ms + spDiffTimers(spGetTimerMicros(), t, true, micro)
				acc.kb = acc.kb + collectgarbage("count") - m0
				acc.calls = acc.calls + 1
				return a, b, c, d
			end
		end
	end
end

local function S()
	return WG.BarDroidSpectate
end

local function enter(name)
	local A = S().actions
	if name == "off" then
		WG.BarDroidInput = "mouse"
	elseif name == "bar" then
		WG.BarDroidInput = "touch"
	elseif name == "follow" then
		A.unit_next()
		A.preset_close()
	elseif name == "group" then
		A.group()
	elseif name == "first" then
		A.group()
		A.preset_first()
	end
end

local function report()
	local name = phases[phase]
	log(string.format("%s: %.4f ms and %.2f KB per frame (%d frames, %d calls, frame %.1f ms)", name,
		frames > 0 and acc.ms / frames or 0, frames > 0 and acc.kb / frames or 0, frames, acc.calls,
		frames > 0 and frameMs / frames or 0))
end

function widget:Update()
	if not ready then
		if not skipSent and Spring.GetGameFrame() > 30 then
			Spring.SendCommands("skip " .. SKIP)
			skipSent = true
		end
		if Spring.GetGameFrame() >= SKIP * 30 - 30 and S() then
			target = S().widget -- (user widgets cannot reach the handler's widget list)
			if not target then
				log("FAIL no BAR Droid spectate widget")
				Spring.Echo("[spectest] done")
				Spring.SendCommands("quitforce")
				return
			end
			wrap(target)
			ready = true
			phase, phaseAt = 1, now()
			enter(phases[1])
		end
		return
	end
	-- keep the bar up (BAR's player list's timer would close it)
	local name = phases[phase]
	if name ~= "off" and name ~= "hidden" and WG.BarDroidPlayers and WG.BarDroidPlayers.open then
		WG.BarDroidPlayers.open()
	end
	local t = now()
	local settle = name == "hidden" and HIDE_S or SETTLE_S
	if not measuring and t - phaseAt >= settle then
		if name == "hidden" and S().shown() then
			log("hidden: the bar is still up")
		end
		collectgarbage("collect")
		collectgarbage("stop")
		acc.ms, acc.kb, acc.calls, frames, frameMs, lastFrame = 0, 0, 0, 0, 0, nil
		measuring = true
	end
	if measuring then
		if lastFrame then
			frames = frames + 1
			frameMs = frameMs + (t - lastFrame) * 1000
		end
		lastFrame = t
	end
	if t - phaseAt >= settle + PHASE_S then
		measuring = false
		collectgarbage("restart")
		report()
		phase = phase + 1
		if phase > #phases then
			log(string.format("units on the map: %d, followed %s, group of %d", #Spring.GetAllUnits(),
				tostring(S().following()), S().members()))
			Spring.Echo("[spectest] done")
			Spring.SendCommands("quitforce")
			return
		end
		phaseAt = t
		enter(phases[phase])
	end
end

function widget:Shutdown()
	collectgarbage("restart")
end
