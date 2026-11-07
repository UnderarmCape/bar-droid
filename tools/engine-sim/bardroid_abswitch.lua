-- Engine-branch dev widget (docs/ENGINE-SIM.md): an A/B inside one game, the two sides in the same heat. Every
-- <period> seconds of real time it sets an engine setting to the next of its values (Spring.SetConfigInt, not saved),
-- in the order A B B A A B B A ..., and logs each phase: drawn frames a second, game speed, and with "timers" the GPU's
-- time per drawing pass (the branch's GPU::<pass> timers, the profiler on) in ms a drawn frame. The first fifth of a
-- phase is left out (a shader made at its first use, the GPU timers' results come a few frames late).
-- LuaUI/Config/bardroid_abswitch.txt: "key BarDroidModelShader values 0 1 period 20 from 1200 timers"
--   (from: game second the phases start at; before it the setting stays at the first value)
-- ab-run.ps1 puts it in for a run and takes it out again.

function widget:GetInfo()
	return {
		name = "BAR Droid A/B switch",
		desc = "Dev: alternates an engine setting in a game, fps and GPU passes per phase",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local key, values, period, from, timers
local phase, phaseStart, mark, measuring
local PASSES = { "GPU::ModelsOpaque", "GPU::AlphaModels", "GPU::ProjectileModels", "GPU::Terrain", "GPU::Particles" }

local function drawFrame()
	local lo, hi = Spring.GetDrawFrame()
	return (lo or 0) + (hi or 0) * 65536
end

local function gpuTotals()
	local t, all = {}, 0
	for _, name in ipairs(Spring.GetProfilerRecordNames() or {}) do
		if name:sub(1, 5) == "GPU::" then
			local total = Spring.GetProfilerTimeRecord(name) or 0
			t[name] = total
			all = all + total
		end
	end
	t.all = all
	return t
end

local function snapshot()
	return { timer = Spring.GetTimer(), drawn = drawFrame(), frame = Spring.GetGameFrame(), gpu = timers and gpuTotals() or nil }
end

local function valueOf(i)
	-- A B B A for two values; for more, each in turn
	if #values == 2 then
		local p = i % 4
		return values[(p == 0 or p == 3) and 1 or 2]
	end
	return values[(i % #values) + 1]
end

function widget:Initialize()
	local text = VFS.FileExists("LuaUI/Config/bardroid_abswitch.txt", VFS.RAW)
		and VFS.LoadFile("LuaUI/Config/bardroid_abswitch.txt", VFS.RAW) or ""
	key = text:match("key (%S+)")
	period = tonumber(text:match("period (%d+)")) or 20
	from = tonumber(text:match("from (%d+)")) or 0
	timers = text:find("timers", 1, true) ~= nil
	values = {}
	for v in (text:match("values ([%d%s]+)") or ""):gmatch("%d+") do
		values[#values + 1] = tonumber(v)
	end
	if not key or #values < 2 then
		Spring.Echo("[abswitch] no key and values in LuaUI/Config/bardroid_abswitch.txt: off")
		widgetHandler:RemoveWidget(self)
		return
	end
	if timers then
		Spring.SendCommands("debug 1 0")
	end
	Spring.SetConfigInt(key, values[1], true)
	Spring.Echo(string.format("[abswitch] %s over %s, %d s a phase from game second %d%s", key, table.concat(values, "/"),
		period, from, timers and ", GPU timers on" or ""))
end

function widget:Update()
	if not key then
		return
	end
	local now = Spring.GetTimer()
	if not phase then
		if Spring.GetGameFrame() < from * 30 then
			return
		end
		phase, phaseStart, mark, measuring = 0, now, nil, false
		Spring.SetConfigInt(key, valueOf(0), true)
		return
	end
	local age = Spring.DiffTimers(now, phaseStart)
	if not measuring and age >= period * 0.2 then
		measuring, mark = true, snapshot()
	end
	if age < period then
		return
	end
	if mark then
		local s = snapshot()
		local secs = Spring.DiffTimers(s.timer, mark.timer)
		local drawn = s.drawn - mark.drawn
		local parts = {}
		if timers and drawn > 0 then
			for _, name in ipairs(PASSES) do
				local d = (s.gpu[name] or 0) - (mark.gpu[name] or 0)
				parts[#parts + 1] = string.format("%s %.2f", name:sub(6), d / drawn)
			end
			parts[#parts + 1] = string.format("all %.2f", (s.gpu.all - mark.gpu.all) / drawn)
		end
		local gs = math.floor(s.frame / 30)
		Spring.Echo(string.format("[abswitch] %d:%02d %s %d: %.1f fps, x%.2f%s%s", gs / 60, gs % 60, key, valueOf(phase),
			drawn / secs, (s.frame - mark.frame) / 30 / secs, timers and "; GPU ms a frame: " or "", table.concat(parts, ", ")))
	end
	phase = phase + 1
	phaseStart, mark, measuring = now, nil, false
	Spring.SetConfigInt(key, valueOf(phase), true)
end

function widget:Shutdown()
	if key then
		Spring.SetConfigInt(key, values[1], true)
	end
	if timers then
		Spring.SendCommands("debug 0")
	end
end
