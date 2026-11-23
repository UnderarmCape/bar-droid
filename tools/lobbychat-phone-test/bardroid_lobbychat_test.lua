-- LuaMenu widget for tools/lobbychat-phone-test.ps1: the lobby's keyboard and speak to chat (bardroid_lobby_touch.lua
-- textBoxAsk, RtsTouch lobbyAskStep; Kailil 2026-11-19) upright on the dev phone, by real taps, in the offline lobby
-- (bardroid_login_wait.lua): Skirmish, Advanced (Chobby's skirmish room, its chat box: the console input, 7 from its
-- foot and 31 from its right); the box tapped: the ask "keyboard <id>" in LuaUI/Config/bardroid_lobby_ask.txt, the box
-- focused, Android's keyboard shown (the script asks Android); "hello" typed: in the box; Back: the keyboard down, the
-- room still up; the box held: the ask "voice <id>", speak to chat's panel up and, the app's microphone denied on the dev
-- phone, saying so ("MICROPHONE"). Asks "do <n> tap|hold|shot|ime|type|key <x> <y> <vsx> [<text or key>]" (X pixels,
-- top left origin) in LuaUI/Config/bardroid_lobbychat.txt, answered "<n> [answer]". "[lobbychat] done: ..." at the end.
function widget:GetInfo()
	return { name = "BAR Droid lobby chat test", desc = "The lobby's keyboard and speak to chat by real taps",
		author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_lobbychat.txt", "LuaUI/Config/bardroid_lobbychat_cmd.txt"
local ASK_FILE = "LuaUI/Config/bardroid_lobby_ask.txt"
local NOHOLD_FILE = "LuaUI/Config/bardroid_lobbychat_nohold.txt"
local stage, stageAt, clock, fails = "wait", 0, 0, 0
local asked, after, answer, readAt = 0, nil, nil, nil
local box, askBefore

local function log(s)
	Spring.Echo("[lobbychat] " .. s)
end
local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
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
local function ask(action, x, y, nextStage, extra)
	asked = asked + 1
	write(string.format("do %d %s %d %d %d%s\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx(),
		extra and (" " .. extra) or ""))
	after, answer = nextStage, nil
	go("asked")
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
local function click(caption) -- (setup, not under test: the button's own listeners)
	local b = findAll(function(o)
		return o.classname ~= "label" and plain(o.caption) == caption and o.OnClick ~= nil and #o.OnClick > 0
	end)[1]
	if b then
		b:CallListeners(b.OnClick)
	end
	return b ~= nil
end
-- X pixels per Chili unit (the screen's width over Chili's screen's: WG.uiScale is not it)
local function scale()
	local sw = WG.Chili and WG.Chili.Screen0 and WG.Chili.Screen0.width
	return sw and sw > 0 and vsx() / sw or 1
end
local function middle(c, fx)
	local hx, hy = c:LocalToScreen(c.width * (fx or 0.5), c.height / 2)
	local s = scale()
	return hx * s, hy * s
end
local function chatBox() -- (Chobby's console input: 7 from its foot, 31 from its right, the emoji button there)
	return findAll(function(o)
		local b = o._relativeBounds
		return o.classname == "editbox" and b and b.bottom == 7 and b.right == 31
	end)[1]
end

local function step()
	local L = WG.BarDroidLobbyTouch
	if stage == "wait" and WG.BarDroidLoggedIn and clock > 6 then
		click("Cancel") -- (the offline lobby's login dialog)
		go("skirmish")
	elseif stage == "skirmish" and clock - stageAt > 1.5 then
		if not click("Skirmish") then
			check("the lobby's Skirmish", false, "no button")
			go("end")
			return
		end
		go("advanced")
	elseif stage == "advanced" and clock - stageAt > 2.5 then
		if not click("Advanced") then
			check("the quick Skirmish's Advanced (the skirmish room)", false, "no button")
			go("end")
			return
		end
		go("room")
	elseif stage == "room" and clock - stageAt > 3 then
		box = chatBox()
		if not box then
			check("the skirmish room's chat box", false, "not found")
			go("end")
			return
		end
		local x, y = middle(box, 0.4)
		log(string.format("(the chat box at %d,%d, %dx%d Chili; tapped at %d,%d)", box.x or 0, box.y or 0, box.width or 0,
			box.height or 0, x, y))
		askBefore = readLine(ASK_FILE)
		ask("tap", x, y, "tap?")
	elseif stage == "tap?" and clock - stageAt > 1.5 then
		local a = readLine(ASK_FILE)
		check("the chat box tapped: the keyboard asked", a and a ~= askBefore and a:find("^keyboard ") ~= nil,
			tostring(askBefore) .. " -> " .. tostring(a))
		check("... the box focused", box.state and box.state.focused or false, tostring(box.state and box.state.focused))
		ask("ime", 0, 0, "ime?")
	elseif stage == "ime?" then
		check("... Android's keyboard shown", answer == "1", "shown " .. tostring(answer))
		ask("type", 0, 0, "typed?", "hello")
	elseif stage == "typed?" and clock - stageAt > 1.5 then
		check("\"hello\" typed: in the box", box.text == "hello", "\"" .. tostring(box.text) .. "\"")
		ask("shot", 0, 0, "back")
	elseif stage == "back" then
		ask("key", 0, 0, "back?", "4")
	elseif stage == "back?" and clock - stageAt > 1.5 then
		ask("ime", 0, 0, "backime?")
	elseif stage == "backime?" then
		check("Back: the keyboard down, the room and its box still up", answer == "0" and chatBox() ~= nil,
			"shown " .. tostring(answer) .. ", box " .. tostring(chatBox() ~= nil))
		if box.SetText then
			box:SetText("") -- (the test's word not left in the room's box)
		else
			box.text = ""
		end
		box = chatBox() or box
		if readLine(NOHOLD_FILE) then
			-- (the script's: the app's microphone not denied for good on this phone, a hold would bring up Android's
			-- "Allow ... to record audio?" over the lobby, 2026-11-23 after a pm clear; never a prompt a tap could allow)
			log("SKIP the chat box held: Android would ask for the microphone (its permission not denied for good here)")
			ask("shot", 1, 0, "end")
			return
		end
		askBefore = readLine(ASK_FILE)
		local x, y = middle(box, 0.4)
		ask("hold", x, y, "hold?")
	elseif stage == "hold?" and clock - stageAt > 2 then
		local a = readLine(ASK_FILE)
		check("the chat box held: speak to chat asked", a and a ~= askBefore and a:find("^voice ") ~= nil,
			tostring(askBefore) .. " -> " .. tostring(a))
		local shown = L and L.voiceShown and L.voiceShown()
		local cap = shown and select(9, L.voiceRect()) or nil
		check("... its panel up, saying the microphone is denied (the dev phone's is)", shown and tostring(cap):find("MICROPHONE",
			1, true) ~= nil, tostring(shown) .. ", \"" .. tostring(cap) .. "\"")
		ask("shot", 1, 0, "end")
	elseif stage == "end" then
		log("done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		write("end\n")
		go("over")
	end
	if stage == "asked" and clock - (readAt or -1) >= 0.1 then
		readAt = clock
		local c = readLine(CMD_FILE)
		local n, rest = (c or ""):match("^(%d+)%s*(%S*)")
		if n and tonumber(n) == asked then
			answer = rest
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
