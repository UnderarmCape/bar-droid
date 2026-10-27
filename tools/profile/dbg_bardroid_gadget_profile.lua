-- BAR Droid profiling runs (tools/profile-big-game.ps1 -Gadgets, laptop only, never in the APK): times every callin of
-- every unsynced gadget (LuaRules' unsynced half: effects, unit animations, the game's own UI helpers) and logs each
-- gadget's share to infolog, per drawn frame and per simulated frame. BAR's own Gadget Profiler only draws on screen.
-- Starts when the config string bardroid_profile_go is "1" (set by the host widget), after bardroid_profile_warmup
-- seconds, for bardroid_profile_window seconds.
function gadget:GetInfo()
	return {
		name = "BAR Droid gadget profile",
		desc = "Logs each unsynced gadget's time to infolog (BAR Droid profiling runs)",
		author = "BAR Droid",
		license = "GPL-2.0-or-later",
		layer = -999999,
		handler = true,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return false
end

-- (ends 2 s before the widget profiler, which quits the game when its window is over)
local warmup = tonumber(Spring.GetConfigString("bardroid_profile_warmup", "5")) or 5
local window = (tonumber(Spring.GetConfigString("bardroid_profile_window", "60")) or 60) - 2
local spGetTimer, spDiffTimers = Spring.GetTimerMicros or Spring.GetTimer, Spring.DiffTimers
local micro = Spring.GetTimerMicros ~= nil

local stats = {} -- [gadget name][callin] = { ms, calls }
local inHook, measuring = false, false
local goAt, startClock, startDraw, startSim

local function hook(g, callin)
	local real = g[callin]
	local name = g.ghInfo and g.ghInfo.name or "?"
	local s = stats[name] or {}
	stats[name] = s
	local c = s[callin] or { 0, 0 }
	s[callin] = c
	g[callin] = function(...)
		if inHook or not measuring then
			return real(...)
		end
		inHook = true
		local t = spGetTimer()
		local r1, r2, r3, r4, r5, r6 = real(...)
		c[1], c[2] = c[1] + spDiffTimers(spGetTimer(), t, true, micro), c[2] + 1
		inHook = false
		return r1, r2, r3, r4, r5, r6
	end
end

local function hookAll()
	local n = 0
	for key, list in pairs(gadgetHandler) do
		if type(key) == "string" and type(list) == "table" and key:sub(-4) == "List" then
			local callin = key:sub(1, -5)
			for _, g in ipairs(list) do
				if g ~= gadget and type(g[callin]) == "function" then
					hook(g, callin)
					n = n + 1
				end
			end
		end
	end
	Spring.Echo(string.format("[bardroid-gprofile] timing %d gadget callins", n))
end

-- Spring.GetDrawFrame returns the frame number in two 16-bit halves
local function drawFrame()
	local lo, hi = Spring.GetDrawFrame()
	return lo + (hi or 0) * 65536
end

local function report()
	local secs = spDiffTimers(spGetTimer(), startClock, false, micro)
	local draws = math.max(1, drawFrame() - startDraw)
	local sims = math.max(1, Spring.GetGameFrame() - startSim)
	local rows, perCallin, total = {}, {}, 0
	for name, s in pairs(stats) do
		local ms, top, topMs = 0, "-", 0
		for callin, c in pairs(s) do
			ms = ms + c[1]
			if c[1] > topMs then top, topMs = callin, c[1] end
			local p = perCallin[callin] or { 0, 0 }
			p[1], p[2] = p[1] + c[1], p[2] + c[2]
			perCallin[callin] = p
		end
		total = total + ms
		rows[#rows + 1] = { name = name, ms = ms, top = top, topMs = topMs }
	end
	table.sort(rows, function(a, b) return a.ms > b.ms end)
	Spring.Echo(string.format("[bardroid-gprofile] %.0f s, %d drawn frames (%.1f fps), %d simulated frames (x%.2f), %d units; unsynced gadgets %.0f ms/s, %.3f ms/drawn frame, %.3f ms/sim frame",
		secs, draws, draws / secs, sims, sims / 30 / secs, #Spring.GetAllUnits(), total / secs, total / draws, total / sims))
	for i = 1, math.min(30, #rows) do
		local r = rows[i]
		Spring.Echo(string.format("[bardroid-gprofile] %2d %-42s %7.2f ms/s %6.3f ms/drawn %6.3f ms/sim  top %s %.0f%%", i, r.name,
			r.ms / secs, r.ms / draws, r.ms / sims, r.top, 100 * r.topMs / math.max(r.ms, 1e-9)))
	end
	local callins = {}
	for callin, p in pairs(perCallin) do callins[#callins + 1] = { name = callin, ms = p[1], calls = p[2] } end
	table.sort(callins, function(a, b) return a.ms > b.ms end)
	for i = 1, math.min(12, #callins) do
		local c = callins[i]
		Spring.Echo(string.format("[bardroid-gprofile] callin %-28s %7.2f ms/s %9.1f calls/s", c.name, c.ms / secs, c.calls / secs))
	end
end

local done = false
function gadget:Update()
	if done then
		return
	end
	if not goAt then
		if Spring.GetConfigString("bardroid_profile_go", "") ~= "1" then
			return
		end
		goAt = spGetTimer()
		hookAll()
		return
	end
	if not measuring then
		if spDiffTimers(spGetTimer(), goAt, false, micro) >= warmup then
			measuring = true
			startClock, startDraw, startSim = spGetTimer(), drawFrame(), Spring.GetGameFrame()
		end
		return
	end
	if spDiffTimers(spGetTimer(), startClock, false, micro) >= window then
		measuring, done = false, true
		report()
	end
end
