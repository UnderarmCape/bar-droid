-- Hail-mary research (never in the APK): times every callin of every SYNCED gadget (game logic) between game frames
-- 600 and 1900 of the benchmark and logs each gadget's exclusive time per simulated frame to infolog. Synced code has
-- no timer, so each hooked callin tells the unsynced half when it starts and ends (BAR's own Gadget Profiler does the
-- same, but only draws its table). The messages cost time themselves: the ranking counts, not the absolute numbers.
function gadget:GetInfo()
	return {
		name = "HM synced gadget profile",
		desc = "Logs each synced gadget's time per simulated frame (hail-mary research)",
		author = "BAR Droid",
		license = "GPL-2.0-or-later",
		layer = -999999,
		handler = true,
		enabled = true,
	}
end

local FROM, TO = 600, 1900

if gadgetHandler:IsSyncedCode() then
	local hooked = false
	local names = {}
	local function hookAll()
		local n = 0
		for key, list in pairs(gadgetHandler) do
			if type(key) == "string" and type(list) == "table" and key:sub(-4) == "List" then
				local callin = key:sub(1, -5)
				for _, g in ipairs(list) do
					if g ~= gadget and type(g[callin]) == "function" then
						local real = g[callin]
						names[#names + 1] = (g.ghInfo and g.ghInfo.name or "?") .. "|" .. callin
						local idx = #names
						g[callin] = function(...)
							SendToUnsynced("hmprf", 1, idx)
							local r1, r2, r3, r4, r5, r6 = real(...)
							SendToUnsynced("hmprf", 0, idx)
							return r1, r2, r3, r4, r5, r6
						end
						n = n + 1
					end
				end
			end
		end
		for i = 1, #names do
			SendToUnsynced("hmprf_name", i, names[i])
		end
		Spring.Echo("[hm-sprofile] timing " .. n .. " synced gadget callins")
	end
	function gadget:GameFrame(f)
		if f == FROM - 1 and not hooked then
			hooked = true
			hookAll()
		elseif f == FROM then
			SendToUnsynced("hmprf_go", 1)
		elseif f == TO then
			SendToUnsynced("hmprf_go", 0)
		end
	end
	return
end

local spGetTimer, spDiffTimers = Spring.GetTimerMicros or Spring.GetTimer, Spring.DiffTimers
local micro = Spring.GetTimerMicros ~= nil
local names, acc, calls = {}, {}, {}
local stack, depth, measuring, startClock = {}, 0, false, nil

local function onCall(_, start, idx)
	if not measuring then
		return
	end
	if start == 1 then
		depth = depth + 1
		local s = stack[depth] or {}
		stack[depth] = s
		s[1], s[2], s[3] = idx, spGetTimer(), 0
	elseif depth > 0 then
		local s = stack[depth]
		local el = spDiffTimers(spGetTimer(), s[2], true, micro)
		acc[s[1]] = (acc[s[1]] or 0) + el - s[3]
		calls[s[1]] = (calls[s[1]] or 0) + 1
		depth = depth - 1
		if depth > 0 then
			stack[depth][3] = stack[depth][3] + el
		end
	end
end

local function report()
	local secs = spDiffTimers(spGetTimer(), startClock, false, micro)
	local frames = TO - FROM
	local byGadget, total = {}, 0
	for idx, ms in pairs(acc) do
		local g, c = tostring(names[idx]):match("^(.*)|([^|]*)$")
		g, c = g or tostring(names[idx]), c or "?"
		local e = byGadget[g] or { ms = 0, top = "", topMs = 0, calls = 0 }
		byGadget[g] = e
		e.ms, e.calls = e.ms + ms, e.calls + (calls[idx] or 0)
		if ms > e.topMs then e.top, e.topMs = c, ms end
		total = total + ms
	end
	local rows = {}
	for g, e in pairs(byGadget) do rows[#rows + 1] = { g = g, e = e } end
	table.sort(rows, function(a, b) return a.e.ms > b.e.ms end)
	Spring.Echo(string.format("[hm-sprofile] frames %d-%d in %.0f s, %d units: synced gadgets %.3f ms/sim frame (exclusive)",
		FROM, TO, secs, #Spring.GetAllUnits(), total / frames))
	for i = 1, math.min(35, #rows) do
		local r = rows[i]
		Spring.Echo(string.format("[hm-sprofile] %2d %-44s %6.3f ms/frame %8.1f calls/frame  top %s %.0f%%", i, tostring(r.g),
			r.e.ms / frames, r.e.calls / frames, tostring(r.e.top), 100 * r.e.topMs / math.max(r.e.ms, 1e-9)))
	end
end

function gadget:Initialize()
	gadgetHandler.actionHandler.AddSyncAction(gadget, "hmprf", onCall)
	gadgetHandler.actionHandler.AddSyncAction(gadget, "hmprf_name", function(_, i, n) names[i] = n end)
	gadgetHandler.actionHandler.AddSyncAction(gadget, "hmprf_go", function(_, on)
		if on == 1 then
			measuring, startClock = true, spGetTimer()
		else
			measuring = false
			report()
		end
	end)
end
