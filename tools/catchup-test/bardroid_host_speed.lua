-- User widget for tools/catchup-test.ps1 -HostOnly (the headless host): runs the game fast until a game time
-- (springsettings bardroid_host_fast_until, frames; speed bardroid_host_speed), then at 1x so a spectator can join
-- a long game and catch up. Logs the game time, speed and unit count every game minute. GameFrame, not Update: the
-- headless engine does not draw.
function widget:GetInfo()
	return { name = "BAR Droid catch-up host", desc = "Fast-forwards the host's game for tools/catchup-test.ps1",
		author = "BAR Droid", license = "GPL-3.0-or-later", layer = 0, enabled = true }
end

local target = tonumber(Spring.GetConfigString("bardroid_host_speed", "1")) or 1
local fastUntil = tonumber(Spring.GetConfigString("bardroid_host_fast_until", "0")) or 0
local announced = false
local readyFrame
local minuteAt -- real time of the last game minute
-- (tools/profile-big-game.ps1: the profile widget waits for bardroid_profile_go; the engine's own timers are logged
-- 50 s into the measurement)
local engineProfileAfter = tonumber(Spring.GetConfigString("bardroid_host_engine_profile_after", "0")) or 0
-- (bardroid_host_profile_fast_at: frame at which the profile widget goes while still fast: per-simulated-frame costs)
local profileFastAt = tonumber(Spring.GetConfigString("bardroid_host_profile_fast_at", "0")) or 0

function widget:GameFrame(frame)
	if frame % 30 ~= 0 then
		return
	end
	if profileFastAt > 0 and frame == profileFastAt then
		Spring.Echo(string.format("[catchup-host] profiling at speed %.1f, %d units", Spring.GetGameSpeed(), #Spring.GetAllUnits()))
		Spring.SetConfigString("bardroid_profile_go", "1", true)
		readyFrame = frame -- (the engine timers then follow as after "ready")
	end
	local speed = Spring.GetGameSpeed()
	local want = frame < fastUntil and target or 1
	if speed < want - 0.05 then
		Spring.SendCommands("speedup")
	elseif speed > want + 0.05 then
		Spring.SendCommands("slowdown")
	end
	if frame >= fastUntil and math.abs(speed - 1) < 0.05 and not announced then
		announced, readyFrame = true, frame
		Spring.Echo(string.format("[catchup-host] ready: game at %d:%02d, speed 1, %d units", math.floor(frame / 1800),
			math.floor(frame / 30) % 60, #Spring.GetAllUnits()))
		Spring.SetConfigString("bardroid_profile_go", "1", true)
	end
	if readyFrame and engineProfileAfter > 0 and frame == readyFrame + engineProfileAfter * 30 then
		Spring.Echo(string.format("[catchup-host] engine timers at %d units:", #Spring.GetAllUnits()))
		Spring.SendCommands("debuginfo profiling")
	end
	if frame % 1800 == 0 then
		local now = Spring.GetTimer()
		local actual = minuteAt and 60 / math.max(0.001, Spring.DiffTimers(now, minuteAt)) or 0 -- game minute per real minute
		minuteAt = now
		Spring.Echo(string.format("[catchup-host] game %d:00, speed %.1f (reached x%.1f), %d units", math.floor(frame / 1800),
			speed, actual, #Spring.GetAllUnits()))
		-- the phone's builder queue widget against BAR's API (a leak: its count runs away from the API's)
		local q, api = WG.bardroidQueue, WG.BuilderQueueApi
		if q and api and api.ForEachActiveBuildCommand then
			local n = 0
			api.ForEachActiveBuildCommand(function() n = n + 1 end)
			Spring.Echo(string.format("[catchup-host] queue widget: %d commands, %d shapes; BAR's API: %d", q.total(), q.shown(), n))
		end
	end
end
