-- Engine-branch dev widget (docs/ENGINE-SIM.md): where the main thread's time goes, every 10 s of real time, from the
-- engine's two always-on timers ("Sim": the simulated frames, synced gadgets and widgets' GameFrame; "Draw": the drawn
-- frames, Lua draw call-ins included). The rest is Update call-ins, the swap, sound, networking and waiting.
-- replay-memory.ps1 puts it into LuaUI/Widgets for a run and takes it out again. With "timers" in
-- LuaUI/Config/bardroid_simdraw.txt (replay-memory.ps1 -Timers) the engine's whole profiler is on ("debug 1 0": the
-- timers without their drawing; it costs a little time itself) and every 10 s the busiest timers follow
-- ("Lua::Callins::Synced" is the game's gadgets, "Lua::Callins::Unsynced" widgets and unsynced gadgets).
-- With "widgets" in that file (replay-memory.ps1 -Widgets) every widget's call-ins are timed (each widget's functions
-- wrapped, as BAR's Widget Profiler does) and the busiest widgets follow every 10 s, in % of real time.

function widget:GetInfo()
	return {
		name = "BAR Droid sim/draw split",
		desc = "Dev: logs the main thread's Sim and Draw time every 10 s",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
		handler = true, -- (BAR's real widgetHandler, for its widget list: user widgets get a stand-in without it)
	}
end

local STEP = 10
local TOP = 150
local last, timers, totals, widgetTimes, hideUi, noDeferred, shotsAt

-- each widget's call-ins wrapped with a timer: seconds spent, by widget name
local wrapped = {}
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local function wrapWidgets()
	for _, w in ipairs(widgetHandler.widgets or {}) do
		local name = w.whInfo and w.whInfo.name or (w.GetInfo and w:GetInfo().name) or "?"
		if not wrapped[w] and w ~= widget then
			wrapped[w] = true
			for key, fn in pairs(w) do
				if type(fn) == "function" and key:match("^%u") and key ~= "GetInfo" and key ~= "Initialize"
					and key ~= "Shutdown" then
					w[key] = function(...)
						local t = spGetTimer()
						local a, b, c, d, e, f = fn(...)
						widgetTimes[name] = (widgetTimes[name] or 0) + spDiffTimers(spGetTimer(), t)
						return a, b, c, d, e, f
					end
				end
			end
		end
	end
end

local function logWidgets(ms)
	local rows = {}
	for name, s in pairs(widgetTimes) do
		rows[#rows + 1] = { name = name, ms = s * 1000 }
	end
	table.sort(rows, function(a, b) return a.ms > b.ms end)
	local parts, sum = {}, 0
	for i, r in ipairs(rows) do
		sum = sum + r.ms
		if i <= TOP then
			parts[#parts + 1] = string.format("%s %.1f%%", r.name, 100 * r.ms / ms)
		end
	end
	Spring.Echo(string.format("[simdraw] widgets %.1f%% in all: %s", 100 * sum / ms, table.concat(parts, ", ")))
	widgetTimes = {}
	wrapWidgets() -- (widgets switched on since)
end

function widget:Initialize()
	local flag = VFS.FileExists("LuaUI/Config/bardroid_simdraw.txt", VFS.RAW)
		and VFS.LoadFile("LuaUI/Config/bardroid_simdraw.txt", VFS.RAW) or ""
	timers = flag:find("timers", 1, true) ~= nil
	if timers then
		Spring.SendCommands("debug 1 0")
		Spring.Echo("[simdraw] the engine's profiler is on (timers every " .. STEP .. " s)")
	end
	if flag:find("widgets", 1, true) then
		widgetTimes = {}
		Spring.Echo("[simdraw] every widget's call-ins timed")
	end
	hideUi = flag:find("hideui", 1, true) ~= nil
	noDeferred = flag:find("nodeferred", 1, true) ~= nil
	shotsAt = tonumber(flag:match("shots (%d+)"))
end

-- "shots <game second>" (replay-memory.ps1 -Shots): at that game second the camera goes close to where the units are
-- thickest (the same spot and frames in every run of a replay, to compare drawing changes), and three screenshots are
-- taken: close, middle, far (files/bar/screenshots)
local SHOT_STEPS = { { 0, 500 }, { 45, 1300 }, { 90, 3000 } } -- (game frames after the start, camera distance)
local shotSpot
local function thickestSpot()
	local units = Spring.GetAllUnits()
	local best, bestN = nil, -1
	for i = 1, #units, math.max(1, math.floor(#units / 60)) do
		local x, y, z = Spring.GetUnitPosition(units[i])
		if x then
			local n = #(Spring.GetUnitsInCylinder(x, z, 350) or {})
			if n > bestN then
				best, bestN = { x, y, z }, n
			end
		end
	end
	return best, bestN
end
local function shots(frame)
	local start = shotsAt * 30
	for i, step in ipairs(SHOT_STEPS) do
		if frame == start + step[1] then
			if i == 1 then
				local n
				shotSpot, n = thickestSpot()
				Spring.Echo(string.format("[simdraw] shots around %.0f, %.0f (%d units within 350)", shotSpot and shotSpot[1] or -1,
					shotSpot and shotSpot[3] or -1, n or 0))
			end
			if shotSpot then
				Spring.SetCameraTarget(shotSpot[1], shotSpot[2], shotSpot[3], 0)
				local state = Spring.GetCameraState()
				state.dist, state.height = step[2], step[2]
				Spring.SetCameraState(state, 0)
			end
		elseif frame == start + step[1] + 20 then
			Spring.SendCommands("screenshot png")
			Spring.Echo("[simdraw] shot " .. i)
		end
	end
end

-- "hideui": BAR's interface hidden once the game runs (what the UI's drawing costs); "nodeferred": the units' second
-- (G-buffer) pass off as well (the touch widget turns the features' off), set again now and then
local uiHidden
function widget:GameFrame(frame)
	if hideUi and not uiHidden then
		uiHidden = true
		Spring.SendCommands("hideinterface 1")
		Spring.Echo("[simdraw] the interface hidden")
	end
	if shotsAt then
		shots(frame)
	end
	if noDeferred and frame % 300 == 0 and Spring.SetDrawModelsDeferred then
		Spring.SetDrawModelsDeferred(false, false)
		if frame % 9000 == 0 then
			Spring.Echo("[simdraw] the models' deferred pass off")
		end
	end
end

-- every timer's total so far (ms), by name; and its longest single run lately (the profiler halves it every 6 s)
local longest = {}
local function allTotals()
	local t = {}
	for _, name in ipairs(Spring.GetProfilerRecordNames() or {}) do
		local total, _, maxDt = Spring.GetProfilerTimeRecord(name)
		t[name] = total or 0
		longest[name] = maxDt or 0
	end
	return t
end

-- the hitches: the timers whose longest single run lately was longest (what a slow frame spent its time in)
local function logLongest()
	local rows = {}
	for name, ms in pairs(longest) do
		if ms >= 8 then
			rows[#rows + 1] = { name = name, ms = ms }
		end
	end
	table.sort(rows, function(a, b) return a.ms > b.ms end)
	local parts = {}
	for i = 1, math.min(25, #rows) do
		parts[#parts + 1] = string.format("%s %.0f", rows[i].name, rows[i].ms)
	end
	Spring.Echo("[simdraw] longest (ms): " .. table.concat(parts, ", "))
end

local function logTimers(ms)
	local now, rows = allTotals(), {}
	if totals then
		for name, total in pairs(now) do
			local d = total - (totals[name] or 0)
			if d > 0 then
				rows[#rows + 1] = { name = name, ms = d }
			end
		end
		table.sort(rows, function(a, b) return a.ms > b.ms end)
		local parts = {}
		for i = 1, math.min(TOP, #rows) do
			parts[#parts + 1] = string.format("%s %.1f%%", rows[i].name, 100 * rows[i].ms / ms)
		end
		Spring.Echo("[simdraw] timers: " .. table.concat(parts, ", "))
		logLongest()
	end
	totals = now
end

local function drawFrame()
	local lo, hi = Spring.GetDrawFrame()
	return (lo or 0) + (hi or 0) * 65536
end

local function sample()
	return {
		timer = Spring.GetTimer(),
		sim = Spring.GetProfilerTimeRecord("Sim") or 0,
		draw = Spring.GetProfilerTimeRecord("Draw") or 0,
		frame = Spring.GetGameFrame(),
		drawn = drawFrame(),
	}
end

-- hitches: the time from one Update to the next (one per drawn frame), the long ones counted
local prevUpdate, over50, over100, worstGap = nil, 0, 0, 0

function widget:Update()
	local t = Spring.GetTimer()
	if prevUpdate then
		local gap = Spring.DiffTimers(t, prevUpdate) * 1000
		over50 = over50 + (gap > 50 and 1 or 0)
		over100 = over100 + (gap > 100 and 1 or 0)
		worstGap = math.max(worstGap, gap)
	end
	prevUpdate = t
	if not last then
		last = sample()
		if widgetTimes then
			wrapWidgets()
		end
		return
	end
	if Spring.DiffTimers(Spring.GetTimer(), last.timer) < STEP then
		return
	end
	local now = sample()
	local ms = Spring.DiffTimers(now.timer, last.timer) * 1000
	local sim, draw = now.sim - last.sim, now.draw - last.draw
	local simFrames, drawFrames = now.frame - last.frame, now.drawn - last.drawn
	local s = math.floor(now.frame / 30)
	Spring.Echo(string.format("[simdraw] %d:%02d sim %.0f%% (%.1f ms x %d frames), draw %.0f%% (%.1f ms x %d), rest %.0f%%; "
		.. "frames over 50 ms %d, over 100 ms %d, longest %.0f ms",
		s / 60, s % 60, 100 * sim / ms, sim / math.max(simFrames, 1), simFrames, 100 * draw / ms,
		draw / math.max(drawFrames, 1), drawFrames, 100 * (ms - sim - draw) / ms, over50, over100, worstGap))
	over50, over100, worstGap = 0, 0, 0
	if timers then
		logTimers(ms)
	end
	if widgetTimes then
		logWidgets(ms)
	end
	last = now
end

function widget:Shutdown()
	if timers then
		Spring.SendCommands("debug 0")
	end
end
