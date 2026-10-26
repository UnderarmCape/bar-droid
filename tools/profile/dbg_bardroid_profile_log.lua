-- BAR Droid profiling runs (tools/profile-gamepad-game.ps1, laptop only, never in the APK): logs every widget's
-- share of the time and its garbage, measured by BAR's own widget profiler module, to infolog, then quits.
--   bardroid_profile_warmup  seconds before measuring (default 40)
--   bardroid_profile_window  seconds measured (default 60)
--   bardroid_profile_detail  widget whose callins are broken down (default "Controller Camera Test")
--   bardroid_profile_functions  1: also time every global function of that widget (inclusive: a function's numbers
--                            include what it calls) and count what it allocates exactly, with Lua's garbage
--                            collector stopped while measuring (laptop only: the heap grows meanwhile)
function widget:GetInfo()
	return {
		name = "BAR Droid profile log",
		desc = "Logs each widget's time and garbage to infolog, then quits (BAR Droid profiling runs)",
		author = "BAR Droid",
		license = "GPL-2.0-or-later",
		layer = -999999,
		handler = true,
		enabled = true,
	}
end

local profiling
local warmup = tonumber(Spring.GetConfigString("bardroid_profile_warmup", "40")) or 40
local window = tonumber(Spring.GetConfigString("bardroid_profile_window", "60")) or 60
local detailName = Spring.GetConfigString("bardroid_profile_detail", "Controller Camera Test")
local functions = Spring.GetConfigInt("bardroid_profile_functions", 0) == 1
local elapsed, measured, frames = 0, 0, 0
local acc, detailAcc, samples = {}, {}, 0
local fstats, measuring = {}, false
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local spGetTimerMicros = Spring.GetTimerMicros or Spring.GetTimer
local microTimers = Spring.GetTimerMicros ~= nil

local function finish(s, t0, m0, ...)
	if measuring then
		s[1] = s[1] + spDiffTimers(spGetTimerMicros(), t0, true, microTimers) -- ms
		s[2] = s[2] + collectgarbage("count") - m0
		s[3] = s[3] + 1
	end
	return ...
end

-- set by the widget handler on every widget table, not the widget's own code
local HANDLER_FIELDS = { include = true, newfenv = true, getfenv = true, setfenv = true, loadstring = true,
	GetInfo = true, Initialize = true, Shutdown = true, GetConfigData = true, SetConfigData = true }

local function wrapFunctions(w)
	-- a widget's globals live in its widget table (BAR's handler runs each widget file with setfenv(chunk, widget))
	local n, wrappers = 0, {}
	for name, f in pairs(w) do
		if type(name) == "string" and type(f) == "function" and not HANDLER_FIELDS[name] then
			local s = { 0, 0, 0 }
			fstats[name] = s
			local wrapper = function(...)
				return finish(s, spGetTimerMicros(), collectgarbage("count"), f(...))
			end
			w[name], wrappers[f] = wrapper, wrapper
			n = n + 1
		end
	end
	-- APIs the widget published in WG hold the original functions: point them at the wrappers too
	for _, api in pairs(WG) do
		if type(api) == "table" then
			for key, value in pairs(api) do
				if wrappers[value] then api[key] = wrappers[value] end
			end
		end
	end
	Spring.Echo(string.format("[bardroid-profile] timing %d functions of %s", n, w.whInfo.name))
end

function widget:Initialize()
	local ok, m = pcall(require, "luaui/Include/widget_profiling")
	profiling = ok and m or VFS.Include("luaui/Include/widget_profiling.lua")
	if not functions then
		profiling.subscribe(widget, 1)
		profiling.setDetail(detailName)
	end
	Spring.Echo(string.format("[bardroid-profile] warmup %ds, window %ds, detail %q, functions %s", warmup, window, detailName, tostring(functions)))
end

-- per-function mode: no per-widget hooks (they would sit around every callin), own clock
local fElapsed, fStart, wrapped = 0, nil, false
local function functionsUpdate()
	if not wrapped then -- this widget loads first (lowest layer): wrap once the others are in
		wrapped = true
		for _, w in ipairs(widgetHandler.widgets) do
			if w.whInfo and w.whInfo.name == detailName then
				wrapFunctions(w)
			end
		end
	end
	fElapsed = fElapsed + (fStart and spDiffTimers(spGetTimer(), fStart) or 0)
	fStart = spGetTimer()
	if not measuring and fElapsed >= warmup then
		collectgarbage("collect")
		collectgarbage("stop")
		measuring, measured, frames = true, 0, 0
		fElapsed = 0
		return
	end
	if measuring then
		frames = frames + 1
		if fElapsed >= window then
			measuring = false
			collectgarbage("restart")
			local rows = {}
			for name, s in pairs(fstats) do
				if s[3] > 0 then
					rows[#rows + 1] = { name = name, ms = s[1], kb = s[2], calls = s[3] }
				end
			end
			local fps = frames / fElapsed
			hintDiagnostics()
			Spring.Echo(string.format("[bardroid-profile] %s functions over %.0f s, %.1f fps (inclusive: callers include callees)", detailName, fElapsed, fps))
			table.sort(rows, function(x, y) return x.kb > y.kb end)
			for i = 1, math.min(40, #rows) do
				local r = rows[i]
				Spring.Echo(string.format("[bardroid-profile] kB  %-62s %8.1f kB/s %7.3f ms/frame %8.1f calls/frame", r.name, r.kb / fElapsed, r.ms / frames, r.calls / frames))
			end
			table.sort(rows, function(x, y) return x.ms > y.ms end)
			for i = 1, math.min(40, #rows) do
				local r = rows[i]
				Spring.Echo(string.format("[bardroid-profile] ms  %-62s %7.3f ms/frame %8.1f kB/s %8.1f calls/frame", r.name, r.ms / frames, r.kb / fElapsed, r.calls / frames))
			end
			Spring.SendCommands("quitforce")
			widgetHandler:RemoveWidget(widget)
		end
	end
end

function widget:Shutdown()
	if profiling then
		profiling.unsubscribe(widget)
	end
end

local function hintDiagnostics()
	local registry = WG.ControllerHintRegistry
	local d = registry and type(registry.GetDiagnostics) == "function" and registry.GetDiagnostics()
	if type(d) == "table" then
		Spring.Echo(string.format("[bardroid-profile] hint panel: %s rebuilds, drawn directly %s, recorded %s, replayed %s",
			tostring(d.rebuildCount), tostring(d.drawDirect), tostring(d.drawRecorded), tostring(d.drawReplayed)))
	end
end

local function report()
	hintDiagnostics()
	local rows = {}
	for name, a in pairs(acc) do
		rows[#rows + 1] = { name = name, ms = a[1] / samples * 1000, kb = a[2] / samples }
	end
	table.sort(rows, function(x, y) return x.ms > y.ms end)
	local fps = frames / measured
	local totalMs, totalKb = 0, 0
	for _, r in ipairs(rows) do
		totalMs, totalKb = totalMs + r.ms, totalKb + r.kb
	end
	Spring.Echo(string.format("[bardroid-profile] %.0f s measured, %.1f fps; all widgets %.0f ms/s (%.2f ms/frame), garbage %.0f kB/s; LuaUI heap %.0f MB",
		measured, fps, totalMs, totalMs / fps, totalKb, collectgarbage("count") / 1024))
	for i = 1, math.min(25, #rows) do
		local r = rows[i]
		Spring.Echo(string.format("[bardroid-profile] %2d %-40s %7.2f ms/s %6.3f ms/frame %8.1f kB/s", i, r.name, r.ms, r.ms / fps, r.kb))
	end
	local d = {}
	for cname, a in pairs(detailAcc) do
		d[#d + 1] = { name = cname, pct = a[1] / samples, kb = a[2] / samples }
	end
	table.sort(d, function(x, y) return x.pct > y.pct end)
	for i = 1, math.min(12, #d) do
		Spring.Echo(string.format("[bardroid-profile]    %s:%-24s %6.2f%% of time %8.1f kB/s", detailName, d[i].name, d[i].pct, d[i].kb))
	end
end

function widget:Update(dt)
	if functions then
		functionsUpdate()
		return
	end
	if elapsed >= warmup then
		frames = frames + 1
	end
	if not profiling.sample() then
		return
	end
	local step = profiling.deltaTime
	elapsed = elapsed + step
	if elapsed < warmup then
		return
	end
	measured, samples = measured + step, samples + 1
	for name, e in pairs(profiling.stats) do
		local a = acc[name] or { 0, 0 }
		a[1], a[2] = a[1] + (e.share or 0), a[2] + (e.space or 0)
		acc[name] = a
	end
	for cname, v in pairs(profiling.callins(detailName) or {}) do
		local a = detailAcc[cname] or { 0, 0 }
		a[1], a[2] = a[1] + v[1], a[2] + v[2]
		detailAcc[cname] = a
	end
	if measured >= window then
		report()
		Spring.SendCommands("quitforce")
		widgetHandler:RemoveWidget(widget)
	end
end
