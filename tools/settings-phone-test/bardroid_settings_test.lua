-- LuaUI widget for tools/settings-phone-test.ps1: the Settings copy's search field (bardroid_options.lua; 2026-11-19's
-- system, hardened 2026-11-20) upright on the dev phone, by real taps and keys. In a skirmish: BAR's Settings on the top
-- bar tapped (found along its strip with WG.topbar.buttonAt); the search field tapped: focused, Android's keyboard asked
-- (bardroid_lobby_ask.txt "keyboard g...", bardroid_touch.lua's WG.BarDroidAskKeyboard) and up (the script asks
-- Android); "shadow" typed (adb shell input text): the list cut to fewer lines, some; the field's clear button tapped:
-- empty, the list whole again; Back: the keyboard down, Settings still open; "radar" typed with the keyboard down, Back:
-- the search cleared (BAR's Escape), Settings open; Back again: closed; opened again, the red close tapped: closed.
-- Taps, keys and pictures asked for by "do <n> tap|shot|ime|type|key <x> <y> <vsx> [<text or key code>]" (X pixels,
-- top left origin) in LuaUI/Config/bardroid_settingstest.txt, answered "<n> [<answer>]" in bardroid_settingstest_cmd.txt.
-- Stepped in Update by real time (a game alone pauses under BAR's windows). "[settingstest] done: ALL PASS" or
-- "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid settings test", desc = "Settings' search by real taps", author = "BAR Droid", layer = 0,
		enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_settingstest.txt", "LuaUI/Config/bardroid_settingstest_cmd.txt"
local ASK_FILE = "LuaUI/Config/bardroid_lobby_ask.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after, answer = 0, nil, nil
local readAt
local btnAt -- BAR's Settings button's middle (X pixels, top left origin)
local askBefore -- bardroid_lobby_ask.txt before the tap on the field
local linesAll -- the list's option lines with no search

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[settingstest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end
local function readLine(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end
local function go(s, f)
	stage, stageAt = s, f
end
local function ask(action, x, y, nextStage, f, extra)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d%s\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx,
		extra and (" " .. extra) or ""))
	after, answer = nextStage, nil
	go("asked", f)
end

local function shown()
	local O = WG.options
	return O and O.isvisible and O.isvisible() or false
end
local function search()
	local rect, text, focused, close, lines = WG.options.droidSearch()
	local n, names = 0, {}
	for _, line in ipairs(lines or {}) do
		if line.kind == "row" or line.kind == "cells" then
			n = n + 1
			local o = line.option or (line.cells and line.cells[1])
			if #names < 4 and o and o.name then
				names[#names + 1] = tostring(o.name)
			end
		end
	end
	return { rect = rect, text = text, focused = focused, close = close, n = n, names = table.concat(names, ", ") }
end
-- BAR's Settings button's middle on the top bar (X pixels from the top left), found along its strip
local function settingsButton()
	local tb = WG.topbar
	local pos = tb and tb.GetButtonsPosition and tb.GetButtonsPosition()
	if not (pos and tb.buttonAt) then
		return nil
	end
	local vsy = select(2, Spring.GetViewGeometry())
	local y = math.floor((pos[2] + pos[4]) / 2)
	local x0, x1, seen = nil, nil, {}
	for x = math.floor(pos[1]), math.floor(pos[3]), 3 do
		local b = tb.buttonAt(x, y)
		if b then
			seen[b] = true
		end
		if b == "options" or b == "settings" then
			x0, x1 = x0 or x, x
		end
	end
	local names = {}
	for b in pairs(seen) do
		names[#names + 1] = b
	end
	return x0 and { (x0 + x1) / 2, vsy - y } or nil, table.concat(names, " ")
end

local function step(f)
	local vsx, vsy = Spring.GetViewGeometry()
	if stage == "wait" and Spring.GetGameFrame() >= 150 then
		local P = WG.BarDroidPortrait
		if not (P and P.active and P.active() and vsx < vsy) then
			check("upright with the app's dock", false, string.format("%dx%d", vsx, vsy))
			go("end", f)
			return
		end
		if not (WG.options and WG.options.droidSearch) then
			check("the app's Settings (bardroid_options.lua) running, its droidSearch there", false, tostring(WG.options))
			go("end", f)
			return
		end
		Spring.SelectUnitArray({})
		local names
		btnAt, names = settingsButton()
		Spring.Echo(string.format("[settingstest] (%dx%d; the top bar's buttons: %s; Settings at %s)", vsx, vsy,
			tostring(names), btnAt and string.format("%d,%d", btnAt[1], btnAt[2]) or "none"))
		if not btnAt then
			check("BAR's Settings button on the top bar", false, "not found along the strip")
			go("end", f)
			return
		end
		ask("tap", btnAt[1], btnAt[2], "open?", f)
	elseif stage == "open?" and f - stageAt > 30 then
		check("Settings tapped on the top bar: open", shown(), tostring(shown()))
		local s = search()
		local r = s.rect
		check("its search field on the screen, a finger's height", r and r[1] >= 0 and r[3] <= vsx and r[4] <= vsy
			and r[4] - r[2] >= vsx * 0.04 and r[3] - r[1] >= vsx * 0.3,
			r and string.format("%d,%d-%d,%d of %dx%d", r[1], r[2], r[3], r[4], vsx, vsy) or "none")
		if s.text ~= "" then -- (a search kept from before: cleared first, the list's whole count needs it)
			Spring.Echo("[settingstest] (a search kept from before: \"" .. s.text .. "\", cleared)")
			local box = select(6, WG.options.droidSearch())
			box:setText("")
			box:blur()
		end
		ask("shot", 0, 0, "field", f)
	elseif stage == "field" then -- (the list counted after the picture: a cleared search's list made again by then)
		local s = search()
		linesAll = s.n
		askBefore = readLine(ASK_FILE)
		Spring.Echo(string.format("[settingstest] (the list: %d option lines, the first %s; the search \"%s\")", s.n, s.names,
			tostring(s.text)))
		local r = s.rect
		-- (left of the middle: the clear button is the field's right end)
		ask("tap", r[1] + (r[3] - r[1]) * 0.3, vsy - (r[2] + r[4]) / 2, "focus?", f)
	elseif stage == "focus?" and f - stageAt > 30 then
		local s = search()
		local a = readLine(ASK_FILE)
		check("the search field tapped: focused", s.focused, tostring(s.focused))
		check("... and Android's keyboard asked (bardroid_lobby_ask.txt)", a and a ~= askBefore and a:find("^keyboard g") ~= nil,
			tostring(askBefore) .. " -> " .. tostring(a))
		ask("ime", 0, 0, "ime?", f)
	elseif stage == "ime?" then
		check("... and up (Android's input method shown)", answer == "1", "shown " .. tostring(answer))
		ask("type", 0, 0, "typed?", f, "shadow")
	elseif stage == "typed?" and f - stageAt > 30 then
		local s = search()
		check("\"shadow\" typed with the keyboard: in the field, the list cut", s.text == "shadow" and s.n > 0 and s.n < linesAll,
			string.format("\"%s\", %d option lines of %d: %s", tostring(s.text), s.n, linesAll or -1, s.names))
		ask("shot", 1, 0, "clear", f)
	elseif stage == "clear" then
		local r = search().rect
		local h = r[4] - r[2]
		-- (left of BAR's small clear button, a field's height in from the right end, inside the copy's wider tap area
		-- for it: the field's last 1.8 heights)
		ask("tap", r[3] - h * 1.4, vsy - (r[2] + r[4]) / 2, "cleared?", f)
	elseif stage == "cleared?" and f - stageAt > 30 then
		local s = search()
		check("the field's clear tapped (beside BAR's small button): empty, focused, the list whole again",
			s.text == "" and s.focused and s.n == linesAll,
			string.format("\"%s\", %d option lines of %d", tostring(s.text), s.n, linesAll or -1))
		ask("key", 0, 0, "back1?", f, "4")
	elseif stage == "back1?" and f - stageAt > 30 then
		ask("ime", 0, 0, "back1ime?", f)
	elseif stage == "back1ime?" then
		check("Back with the keyboard up: the keyboard down, Settings still open", answer == "0" and shown(),
			"keyboard " .. tostring(answer) .. ", open " .. tostring(shown()))
		ask("type", 0, 0, "typed2?", f, "radar")
	elseif stage == "typed2?" and f - stageAt > 30 then
		local s = search()
		check("\"radar\" typed with the keyboard down: in the field", s.text == "radar", "\"" .. tostring(s.text) .. "\"")
		ask("key", 0, 0, "back2?", f, "4")
	elseif stage == "back2?" and f - stageAt > 30 then
		local s = search()
		check("Back with a search: the search cleared, Settings still open", s.text == "" and shown(),
			"\"" .. tostring(s.text) .. "\", open " .. tostring(shown()))
		ask("key", 0, 0, "back3?", f, "4")
	elseif stage == "back3?" and f - stageAt > 30 then
		check("Back again: Settings closed", not shown(), "open " .. tostring(shown()))
		if shown() then
			WG.options.toggle(false)
		end
		ask("tap", btnAt[1], btnAt[2], "again?", f)
	elseif stage == "again?" and f - stageAt > 30 then
		check("Settings tapped again: open", shown(), tostring(shown()))
		local c = search().close
		if not c then
			check("its close button", false, "none")
			go("end", f)
			return
		end
		Spring.Echo(string.format("[settingstest] (the close button %d,%d-%d,%d)", c[1], c[2], c[3], c[4]))
		ask("tap", (c[1] + c[3]) / 2, vsy - (c[2] + c[4]) / 2, "closed?", f)
	elseif stage == "closed?" and f - stageAt > 30 then
		check("its red close tapped: closed", not shown(), "open " .. tostring(shown()))
		if shown() then
			WG.options.toggle(false)
		end
		go("end", f)
	elseif stage == "end" then
		Spring.Echo("[settingstest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		write("end\n")
		go("over", f)
	end
	if stage == "asked" and f - (readAt or -10) >= 3 then
		readAt = f
		local c = readLine(CMD_FILE)
		local n, rest = (c or ""):match("^(%d+)%s*(%S*)")
		if n and tonumber(n) == asked then
			answer = rest
			go(after, f)
		elseif f - stageAt > 30 * 30 then
			check("the script's " .. after .. " step", false, "not done in 30 s")
			go("end", f)
		end
	end
end

local clock = 0
function widget:Update(dt)
	clock = clock + (dt or 0)
	step(math.floor(clock * 30))
end
