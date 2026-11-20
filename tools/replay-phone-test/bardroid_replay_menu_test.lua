-- LuaMenu widget for tools/replay-phone-test.ps1: in the offline lobby (bardroid_login_wait.lua) the login dialog's
-- Cancel, Replays, and the newest replay's Start (by its row's date). The replay's own checks are the LuaUI widget's
-- (bardroid_replay_test.lua). Logs "[replaytest] (...)" lines.
function widget:GetInfo()
	return { name = "BAR Droid replay test (lobby)", desc = "Starts the newest replay", author = "BAR Droid", layer = 0,
		enabled = true }
end

local stage, stageAt, clock = "wait", 0, 0
local STATE_FILE = "LuaUI/Config/bardroid_replaytest_state.txt" -- ("started": not again in the replay's engine)

local function log(s)
	Spring.Echo("[replaytest] " .. s)
end
local function real(o)
	return o and WG.Chili and WG.Chili.UnlinkSafe and WG.Chili.UnlinkSafe(o) or o
end
local function plain(s)
	return type(s) == "string" and s:gsub("\255...", ""):gsub("^%s+", ""):gsub("%s+$", "") or nil
end
local function findAll(test)
	local out = {}
	local function walk(o, depth)
		o = real(o)
		if not o or o.disposed or depth > 40 or o.visible == false then
			return
		end
		if test(o) then
			out[#out + 1] = o
		end
		for _, ch in ipairs(o.children or {}) do
			walk(ch, depth + 1)
		end
	end
	walk(WG.Chili and WG.Chili.Screen0, 0)
	return out
end
local function click(caption)
	local b = findAll(function(o)
		return o.classname ~= "label" and plain(o.caption) == caption and o.OnClick ~= nil and #o.OnClick > 0
	end)[1]
	if b then
		b:CallListeners(b.OnClick)
	end
	return b ~= nil
end
local function go(s)
	stage, stageAt = s, clock
end

function widget:Initialize()
	local f = io.open(STATE_FILE, "r")
	if f then
		local s = f:read("*l")
		f:close()
		if s == "started" then
			stage = "done"
		end
	end
end

function widget:Update()
	local now = Spring.GetTimer()
	widget.t0 = widget.t0 or now
	clock = Spring.DiffTimers(now, widget.t0)
	if stage == "wait" and WG.BarDroidLoggedIn and clock > 6 then
		click("Cancel") -- (the offline lobby's login dialog)
		go("tab")
	elseif stage == "tab" and clock - stageAt > 1.5 then
		if not click("Replays") then
			log("FAIL the lobby's Replays: no button")
			go("done")
			return
		end
		go("start")
	elseif stage == "start" and clock - stageAt > 3 then
		local starts = findAll(function(o)
			return plain(o.caption) == "Start" and o.OnClick ~= nil and o.classname ~= "label"
		end)
		local function rowKey(b)
			local key = ""
			local function walk(o, depth)
				o = real(o)
				if not o or depth > 6 then
					return
				end
				local s = type(o.text) == "string" and o.text or type(o.caption) == "string" and o.caption or ""
				local y, m, d, hh, mm = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)")
				if y and y .. m .. d .. hh .. mm > key then
					key = y .. m .. d .. hh .. mm
				end
				for _, ch in ipairs(o.children or {}) do
					walk(ch, depth + 1)
				end
			end
			walk(b.parent, 0)
			return key
		end
		table.sort(starts, function(a, b)
			return rowKey(a) > rowKey(b)
		end)
		if #starts == 0 or rowKey(starts[1]) == "" then
			log(string.format("FAIL a replay to start: %d listed, no dates read", #starts))
			go("done")
			return
		end
		log(string.format("(Replays: %d listed, the newest of %s started)", #starts, rowKey(starts[1])))
		local f = io.open(STATE_FILE, "w")
		if f then
			f:write("started\n")
			f:close()
		end
		starts[1]:CallListeners(starts[1].OnClick)
		go("done")
	end
end
