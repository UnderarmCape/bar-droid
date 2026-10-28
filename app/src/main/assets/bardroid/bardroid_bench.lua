-- BAR Droid benchmark: the app's direct start of BAR's "Benchmark BAR" scenario (launch-bar.sh MODE=bench, which
-- leaves LuaUI/Config/bardroid_bench.txt; nothing happens without it). The game runs unattended: if it starts paused
-- (BAR pauses singleplayer while a window such as the scenario's Mission Info is open; launch-bar.sh switches that
-- widget off for benchmarks) it is resumed, and once the benchmark gadget has printed its results the game is quit, so
-- tools/phone-bench.ps1 can start the next run. Installed into LuaUI/Widgets by the app.
--
-- A replay benchmark (phone-bench.ps1 -Replay; the flag file says "replay <game second> <seconds>"): a real game played
-- again, as every player's engine simulates it online. Fast-forwarded to that game second (the engine's skip), then
-- played at normal speed for that many seconds: every 10 s how fast the game ran against real time (the simulated
-- frames of those 10 s: x1 keeps up with live play, below it the phone falls behind), the units and the fps; then a
-- summary and the game is quit (Kailil, 2026-10-27: measure real big battles, not only the 1,300-unit scenario).

function widget:GetInfo()
	return {
		name = "BAR Droid benchmark",
		desc = "Runs BAR's benchmark scenario or a replay unattended when the app starts it",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local FLAG = "LuaUI/Config/bardroid_bench.txt"
local QUIT_AFTER = 3 -- seconds after the results, for the log to take them
local quitAt

local replay -- { skip = game second, seconds = real seconds to measure }
local STEP = 10 -- seconds between replay samples
local skipSent, measuring, lastTimer, lastFrame, startTimer
local stalls = 0 -- samples in a row without a new frame: the replay is over
local samples = {}

function widget:Initialize()
	if not VFS.FileExists(FLAG, VFS.RAW) then
		widgetHandler:RemoveWidget()
		return
	end
	local flag = VFS.LoadFile(FLAG, VFS.RAW) or ""
	local skip, seconds = flag:match("^replay (%d+) (%d+)")
	if skip then
		replay = { skip = tonumber(skip), seconds = tonumber(seconds) }
		Spring.Echo(string.format("[replaybench] unattended replay: from game second %d, %d s", replay.skip, replay.seconds))
	else
		Spring.Echo("[bardroid-bench] unattended benchmark")
	end
end

local function clock(frame)
	local s = math.floor(frame / 30)
	return string.format("%d:%02d", s / 60, s % 60)
end

local function summary()
	local speeds, peak, below = {}, 0, 0
	for _, s in ipairs(samples) do
		speeds[#speeds + 1] = s.speed
		peak = math.max(peak, s.units)
		if s.speed < 0.95 then
			below = below + 1
		end
	end
	table.sort(speeds)
	local n = #speeds
	if n == 0 then
		return "no samples"
	end
	return string.format("speed min x%.2f, median x%.2f; below x0.95 %d%% of the time; units up to %d; %d samples",
		speeds[1], speeds[math.floor((n + 1) / 2)], math.floor(100 * below / n + 0.5), peak, n)
end

local function finish(why)
	Spring.Echo("[replaybench] done (" .. why .. "): " .. summary())
	quitAt = os.clock() + QUIT_AFTER
end

local function replayUpdate()
	local frame = Spring.GetGameFrame()
	if frame <= 0 then
		return
	end
	if not skipSent then
		skipSent = true
		if replay.skip * 30 > frame then
			Spring.Echo("[replaybench] fast-forwarding to " .. clock(replay.skip * 30))
			Spring.SendCommands("skip " .. replay.skip)
		end
		return
	end
	if not measuring then
		if frame < replay.skip * 30 then
			return
		end
		measuring = true
		startTimer, lastTimer, lastFrame = Spring.GetTimer(), Spring.GetTimer(), frame
		Spring.Echo("[replaybench] measuring from " .. clock(frame))
		return
	end
	local now = Spring.GetTimer()
	local dt = Spring.DiffTimers(now, lastTimer)
	if dt < STEP then
		return
	end
	local speed = (frame - lastFrame) / 30 / dt
	local userSpeed, internalSpeed = Spring.GetGameSpeed()
	local units = #Spring.GetAllUnits()
	-- (not the first 10 s after the fast-forward: the game settles first, x0.5 on the laptop)
	local settling = Spring.DiffTimers(lastTimer, startTimer) < STEP / 2
	if not settling then
		samples[#samples + 1] = { speed = speed, units = units }
	end
	Spring.Echo(string.format("[replaybench] %s x%.2f (wanted x%.2f, server x%.2f), %d units, %d fps%s", clock(frame), speed,
		userSpeed or 0, internalSpeed or 0, units, Spring.GetFPS(), settling and " (settling, not counted)" or ""))
	stalls = frame == lastFrame and stalls + 1 or 0
	if stalls >= 3 then
		finish("the replay ended")
	elseif Spring.DiffTimers(now, startTimer) >= replay.seconds then
		finish(replay.seconds .. " s played")
	end
	lastTimer, lastFrame = now, frame
end

local checked = 0
function widget:Update()
	local now = os.clock()
	if quitAt then
		if now >= quitAt then
			Spring.Echo("[bardroid-bench] done: quitting")
			Spring.SendCommands("quitforce")
			quitAt = math.huge
		end
		return
	end
	if replay then
		replayUpdate()
		return
	end
	if now - checked < 2 then
		return
	end
	checked = now
	local _, _, paused = Spring.GetGameSpeed()
	if paused and Spring.GetGameFrame() > 0 then
		Spring.Echo("[bardroid-bench] the game was paused: resuming")
		Spring.SendCommands("pause 0")
	end
end

function widget:GameOver()
	if replay and measuring and not quitAt then
		finish("the game ended")
	end
end

function widget:AddConsoleLine(line)
	if not replay and not quitAt and line:find("Benchmark ended", 1, true) then
		quitAt = os.clock() + QUIT_AFTER
	end
end
