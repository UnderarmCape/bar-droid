-- User widget for tools/catchup-test.ps1 (the joining spectator): logs pictures drawn and game frames simulated each
-- 5 s while it catches up with the host, then quits once caught up (or after a time limit).
function widget:GetInfo()
	return { name = "BAR Droid catch-up probe", desc = "Catch-up speed for tools/catchup-test.ps1", author = "BAR Droid",
		license = "GPL-3.0-or-later", layer = 0, enabled = true }
end

local serverFrame, serverAt
local draws, lastTime, lastFrame, lastDraws = 0, nil, nil, 0
local started = Spring.GetTimer()
local caughtUpSince

function widget:GameProgress(frame)
	serverFrame, serverAt = frame, Spring.GetTimer()
end

function widget:DrawWorld()
	draws = draws + 1
end

-- bardroid_probe_burn_ms: a slower spectator (CPU burnt every simulated frame), for a catch-up that cannot succeed
local burn = (tonumber(Spring.GetConfigString("bardroid_probe_burn_ms", "0")) or 0) / 1000
function widget:GameFrame()
	if burn > 0 then
		local t = Spring.GetTimer()
		while Spring.DiffTimers(Spring.GetTimer(), t) < burn do
		end
	end
end

function widget:Update()
	local now = Spring.GetTimer()
	local frame = Spring.GetGameFrame()
	if not lastTime then
		lastTime, lastFrame = now, frame
		return
	end
	local dt = Spring.DiffTimers(now, lastTime)
	if dt < 5 then
		return
	end
	local behind = serverFrame and (serverFrame + 30 * Spring.DiffTimers(now, serverAt) - frame) or -1
	local f = io.open("LuaUI/Config/bardroid_catchup.txt", "r")   -- the touch widget's progress for the app
	local progress = f and f:read("*l") or "none"
	if f then f:close() end
	Spring.Echo(string.format("[catchup-probe] frame %d, %.0f behind, x%.1f, %.1f draws/s, MinSimDrawBalance %.2f,"
		.. " progress file: %s", frame, behind, (frame - lastFrame) / 30 / dt, (draws - lastDraws) / dt,
		Spring.GetConfigFloat("MinSimDrawBalance", -1), progress))
	lastTime, lastFrame, lastDraws = now, frame, draws
	if serverFrame and behind < 150 then
		caughtUpSince = caughtUpSince or now
		if Spring.DiffTimers(now, caughtUpSince) > 10 then
			Spring.Echo("[catchup-probe] done")
			Spring.SendCommands("quitforce")
		end
	end
	if Spring.DiffTimers(now, started) > (tonumber(Spring.GetConfigString("bardroid_probe_limit", "600")) or 600) then
		Spring.Echo("[catchup-probe] done (time limit)")
		Spring.SendCommands("quitforce")
	end
end
