-- LuaMenu widget for tools/overgame-phone-test.ps1: BAR's lobby over a running game upright on the dev phone (2026-11-19's
-- system, hardened 2026-11-20), with bardroid_overgame_ui_test.lua (LuaUI) in the game. In the offline lobby
-- (bardroid_login_wait.lua): the login dialog's Cancel, Load Game, a save loaded (its Load). In the game the LuaUI
-- widget taps BAR's Lobby on the top bar; over the game, by real taps: Replays (Open Folder made Add, its rows),
-- Load Game (the dates year first, each row's Load and Delete apart), a drag over the lobby, Return to Battle (the
-- lobby gone). Taps and pictures asked for by "do <n> tap|shot|swipe <x> <y> <vsx> [<x2> <y2>]" (X pixels, top left
-- origin) in LuaUI/Config/bardroid_overgame_menu.txt, answered "<n>" in bardroid_overgame_menu_cmd.txt. Logs
-- "[overgame] PASS|FAIL ..." (the LuaUI widget's lines too) and "[overgame] menu done".
function widget:GetInfo()
	return { name = "BAR Droid over-game test (lobby)", desc = "The lobby over a game by real taps", author = "BAR Droid",
		layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_overgame_menu.txt", "LuaUI/Config/bardroid_overgame_menu_cmd.txt"
-- (the save's game starts in an engine of its own, which loads this widget again: "loading" here sends it on to the
-- game's part; the script removes the file before and after)
local STATE_FILE = "LuaUI/Config/bardroid_overgame_state.txt"
local UI_CMD = "LuaUI/Config/bardroid_overgame_ui_cmd.txt" -- (the game widget's tap on Lobby answered: "1")
local stage, stageAt = "wait", 0
local asked, after = 0, nil
local readAt
local gameOn = false -- (the engine's ActivateGame: a game loaded)
local clock = 0

local function log(s)
	Spring.Echo("[overgame] " .. s)
end
local function check(case, ok, detail)
	log((ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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
local function go(s)
	stage, stageAt = s, clock
end
local function vsx()
	return (Spring.GetViewGeometry())
end
local function ask(action, x, y, nextStage, x2, y2)
	asked = asked + 1
	write(string.format("do %d %s %d %d %d%s\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx(),
		x2 and string.format(" %d %d", math.floor(x2), math.floor(y2)) or ""))
	after = nextStage
	go("asked")
end

local function real(o)
	return o and WG.Chili and WG.Chili.UnlinkSafe and WG.Chili.UnlinkSafe(o) or o
end
local function plain(s)
	return type(s) == "string" and s:gsub("\255...", ""):gsub("^%s+", ""):gsub("%s+$", "") or nil
end
-- every control under the screen that passes test; shownOnly: not under a hidden one
local function findAll(test, shownOnly)
	local out = {}
	local function walk(o, depth)
		o = real(o)
		if not o or o.disposed or depth > 40 or (shownOnly and o.visible == false) then
			return
		end
		if test(o) then
			out[#out + 1] = o
		end
		for _, ch in ipairs(o.children or {}) do
			walk(ch, depth + 1)
		end
		if not shownOnly then
			for ch in pairs(o.children_hidden or {}) do
				walk(ch, depth + 1)
			end
		end
	end
	walk(WG.Chili and WG.Chili.Screen0, 0)
	return out
end
local function button(caption)
	local list = findAll(function(o)
		return o.classname ~= "label" and plain(o.caption) == caption and o.OnClick ~= nil and #o.OnClick > 0
	end, true)
	return list[1]
end
local function click(caption) -- (setup steps, not under test: the button's own listeners)
	local b = button(caption)
	if b then
		b:CallListeners(b.OnClick)
	end
	return b ~= nil
end
-- X pixels per Chili unit: the screen's width over Chili's screen's (WG.uiScale read 2.0 over a game where it is 1.35,
-- the taps off the screen, 2026-11-20)
local function scale()
	local sw = WG.Chili and WG.Chili.Screen0 and WG.Chili.Screen0.width
	return sw and sw > 0 and vsx() / sw or 1
end
-- a control's middle in X pixels from the top left
local function middle(c)
	local hx, hy = c:LocalToScreen(c.width / 2, c.height / 2)
	local s = scale()
	return hx * s, hy * s
end
local function rectOf(c)
	local x0, y0 = c:LocalToScreen(0, 0)
	return { x0, y0, x0 + c.width, y0 + c.height }
end
local function overlap(a, b)
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end
local function lobbyOver()
	local root = WG.Chobby and WG.Chobby.interfaceRoot
	local h = root and root.GetLobbyInterfaceHolder and root.GetLobbyInterfaceHolder()
	return gameOn and h ~= nil and h.visible ~= false
end
-- a grid button tapped as a finger would: first the grid turned to its page (a tap on the page strip's arrow end, the
-- grid's foot: bardroid_lobby_touch.lua stripPage), as many times as needed; over a game Return to Battle comes first,
-- so Replays and Load Game are a page on (the first try tapped off the screen, 2026-11-20)
local seek -- { caption, next stage, page turns so far }
local function tapButton(caption, nextStage)
	seek = { caption = caption, after = nextStage, turns = 0 }
	go("seek")
end
local function seekStep()
	local b = button(seek.caption)
	if not b then
		check("\"" .. seek.caption .. "\" in the lobby", false, "not found")
		go("end")
		return
	end
	local r = rectOf(b)
	local sw, sh = WG.Chili.Screen0.width, WG.Chili.Screen0.height
	if r[1] >= 0 and r[3] <= sw and r[2] >= 0 and r[4] <= sh then
		local x, y = middle(b)
		ask("tap", x, y, seek.after)
		return
	end
	-- (a later page: right of the screen; an earlier one: left of it, or placed below it, bardroid_lobby_touch.lua
	-- stripPlace)
	local back = r[1] < 0 or (r[2] >= sh and r[1] < sw)
	local g = real(b.parent)
	if seek.turns >= 4 or not (g and g.LocalToScreen) then
		check("\"" .. seek.caption .. "\" brought onto the screen", false,
			string.format("at %d-%d of %d after %d page turns", r[1], r[3], sw, seek.turns))
		go("end")
		return
	end
	seek.turns = seek.turns + 1
	-- (a sideways swipe along a row of the page shown, as a finger turns it: the grid's buttons on the screen give the
	-- row; a tap on the page strip's end went off the screen, the grid's size not in the lobby's units, 2026-11-20)
	local rowY
	for _, ch in ipairs(g.children or {}) do
		local c = real(ch)
		if c and c ~= b and c.LocalToScreen and type(c.caption) == "string" then
			local cr = rectOf(c)
			if cr[1] >= 0 and cr[3] <= sw and cr[2] >= 0 and cr[4] <= sh then
				rowY = (cr[2] + cr[4]) / 2
				break
			end
		end
	end
	local s = scale()
	log(string.format("(\"%s\" at %d,%d of %dx%d: the grid's page swiped %s along y %s)", seek.caption, r[1], r[2], sw, sh,
		back and "back" or "on", rowY and string.format("%d", rowY) or "(none on the screen: 90 %)"))
	rowY = (rowY or sh * 0.9) * s
	local from, to = sw * s * (back and 0.15 or 0.85), sw * s * (back and 0.85 or 0.15)
	ask("swipe", from, rowY, "seekwait", to, rowY)
end

function widget:ActivateGame()
	gameOn = true
end

function widget:Initialize()
	if readLine(STATE_FILE) == "loading" then -- (the game's engine: on to the game's part)
		log("(the lobby test in the game's engine)")
		stage = "overwait"
	end
end

local function step()
	if stage == "wait" and WG.BarDroidLoggedIn and clock > 6 then
		click("Cancel") -- (the offline lobby's login dialog)
		go("loadtab")
	elseif stage == "loadtab" and clock - stageAt > 1.5 then
		if not click("Load Game") then
			check("the lobby's Load Game", false, "no button")
			go("end")
			return
		end
		go("load")
	elseif stage == "load" and clock - stageAt > 2.5 then
		-- (a save of this engine: the newest by its row's date, either way written: the first row was a save of the
		-- 2026.07.04 engine, which a phone cannot open, 2026-11-20)
		local loads = findAll(function(o)
			return plain(o.caption) == "Load" and o.OnClick ~= nil and o.classname ~= "label"
		end, true)
		local function rowKey(load)
			local key = ""
			local function walk(o, depth)
				o = real(o)
				if not o or depth > 6 then
					return
				end
				local s = type(o.text) == "string" and o.text or type(o.caption) == "string" and o.caption or ""
				local y, m, d, hh, mm = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)\n(%d%d):(%d%d)")
				if not y then
					d, m, y, hh, mm = s:match("(%d%d)/(%d%d)/(%d%d%d%d)\n(%d%d):(%d%d)")
				end
				if y and y .. m .. d .. hh .. mm > key then
					key = y .. m .. d .. hh .. mm
				end
				for _, ch in ipairs(o.children or {}) do
					walk(ch, depth + 1)
				end
			end
			walk(load.parent, 0)
			return key
		end
		table.sort(loads, function(a, b)
			return rowKey(a) > rowKey(b)
		end)
		log(string.format("(Load Game: %d saves listed, the newest of %s)", #loads, loads[1] and rowKey(loads[1]) or "none"))
		if #loads == 0 or rowKey(loads[1]) == "" then
			check("a save to load", false, #loads .. " listed, no dates read")
			go("end")
			return
		end
		local f = io.open(STATE_FILE, "w")
		if f then
			f:write("loading\n")
			f:close()
		end
		loads[1]:CallListeners(loads[1].OnClick)
		go("overwait")
	elseif stage == "overwait" and readLine(UI_CMD) == "1" and lobbyOver() then -- (after the game widget's tap only:
		-- the lobby shows while the game loads)
		check("BAR's Lobby tapped in the game: the lobby over it", true, "shown")
		go("replays")
	elseif stage == "overwait" and clock - stageAt > 180 then
		check("the lobby over the game", false, "not shown in 3 min")
		go("end")
	elseif stage == "replays" and clock - stageAt > 1.5 then
		tapButton("Replays", "replays?")
	elseif stage == "replays?" and clock - stageAt > 2.5 then
		local add = findAll(function(o)
			return plain(o.caption) == "Add" and o.classname == "option_button"
		end, true)
		local folder = findAll(function(o)
			return plain(o.caption) == "Open Folder"
		end, true)
		check("Replays over the game: Open Folder made Add", #add >= 1 and #folder == 0,
			string.format("%d Add, %d Open Folder", #add, #folder))
		ask("shot", 0, 0, "loadgame")
	elseif stage == "loadgame" then
		tapButton("Load Game", "loadgame?")
	elseif stage == "loadgame?" and clock - stageAt > 2.5 then
		local dates, dayFirst = 0, 0
		for _, o in ipairs(findAll(function(o)
			return o.classname == "textbox" and type(o.text) == "string"
		end, true)) do
			if o.text:find("^%d%d%d%d%-%d%d%-%d%d\n%d%d:%d%d$") then
				dates = dates + 1
			elseif o.text:find("^%d%d/%d%d/%d%d%d%d") then
				dayFirst = dayFirst + 1
			end
		end
		check("Load Game over the game: the dates year first", dates >= 1 and dayFirst == 0,
			string.format("%d year first, %d day first", dates, dayFirst))
		-- (each row's Load and Delete: the two in one parent, apart)
		local rows, apart = 0, 0
		for _, load in ipairs(findAll(function(o)
			return plain(o.caption) == "Load" and o.classname == "action_button"
		end, true)) do
			local parent = real(load.parent)
			for _, ch in ipairs(parent and parent.children or {}) do
				local c = real(ch)
				if c and plain(c.caption) == "Delete" then
					rows = rows + 1
					if not overlap(rectOf(load), rectOf(c)) then
						apart = apart + 1
					end
				end
			end
		end
		check("... each row's Load and Delete apart", rows >= 1 and apart == rows, string.format("%d of %d rows", apart, rows))
		-- (the saves of another engine, which a phone cannot open: their Load greyed, as many as there are)
		local other = 0
		for _, path in ipairs(VFS.DirList("Saves", "*.lua") or {}) do
			local ok, data = pcall(VFS.Include, path)
			if ok and type(data) == "table" and data.engineVersion and data.engineVersion ~= Engine.version then
				other = other + 1
			end
		end
		local greyed = #findAll(function(o)
			return o.classname == "action_button" and type(o.tooltip) == "string" and o.tooltip:find("another engine", 1, true)
		end, true)
		check("... the saves of another engine (" .. tostring(Engine.version) .. " here) with their Load greyed",
			greyed == other, string.format("%d greyed, %d saves of another engine", greyed, other))
		ask("shot", 1, 0, "drag")
	elseif stage == "drag" then -- (a drag over the lobby: the game's camera under it must not move, the LuaUI widget)
		local w = vsx()
		local _, h = Spring.GetViewGeometry()
		ask("swipe", w * 0.5, h * 0.55, "back", w * 0.5, h * 0.35)
	elseif stage == "back" and clock - stageAt > 1 then
		log("(the drag done)")
		write("dragged\n") -- (the LuaUI widget's sign: compare the camera now)
		go("back2")
	elseif stage == "back2" and clock - stageAt > 1 then
		tapButton("Return to Battle", "back?")
	elseif stage == "back?" and clock - stageAt > 2 then
		check("Return to Battle tapped: the lobby gone, the game shown", not lobbyOver(), "over " .. tostring(lobbyOver()))
		go("end")
	elseif stage == "seek" then
		seekStep()
	elseif stage == "seekwait" and clock - stageAt > 1 then -- (the strip's slide)
		go("seek")
	elseif stage == "end" then
		log("menu done")
		write("menu done\n")
		go("over")
	end
	if stage == "asked" and clock - (readAt or -1) >= 0.1 then
		readAt = clock
		local c = readLine(CMD_FILE)
		if c and tonumber(c) == asked then
			go(after)
		elseif clock - stageAt > 30 then
			check("the script's " .. tostring(after) .. " step", false, "not done in 30 s")
			go("end")
		end
	end
end

function widget:Update()
	local now = Spring.GetTimer()
	widget.t0 = widget.t0 or now
	clock = Spring.DiffTimers(now, widget.t0)
	step()
end
