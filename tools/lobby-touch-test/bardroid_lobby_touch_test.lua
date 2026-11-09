-- LuaMenu widget for tools/lobby-touch-test.ps1: a test list in the real lobby (fake server rows as Chobby's battle
-- list makes them, and plain rows), driven the way a finger drives it: through the engine's LuaHandler (the
-- callins the engine calls for the mouse), so every widget sees the input in the lobby's real order.
-- Logs "[lobbytouch] PASS|FAIL <case>" and "[lobbytouch] done".
function widget:GetInfo()
	return { name = "BAR Droid lobby touch test", desc = "Checks bardroid_lobby_touch.lua", author = "BAR Droid",
		layer = 0, enabled = true, handler = true } -- handler: the real LuaHandler (its mouse callins)
end

-- The engine's mouse callins, as the engine calls them for a finger (RtsTouch: down = press, drag = move, up =
-- release). Not the lobby touch widget's own functions: on the phone Chili took every press first (2026-10-27).
local finger = {}
function finger.press(x, y)
	return widgetHandler.callInHookFuncs.MousePress(x, y, 1)
end
function finger.move(x, y)
	return widgetHandler.callInHookFuncs.MouseMove(x, y, 0, 0, 1)
end
function finger.release(x, y)
	return widgetHandler.callInHookFuncs.MouseRelease(x, y, 1)
end

local t, step, wait = 0, 0, 0
local fails = 0
local window, scroll, rows, maps, clicked = nil, nil, {}, {}, {}
local startScroll, dragScroll, clicksBefore, screenSize
local settleFrom, settleSeconds, scaleLogged
local SCALE_KEY = 302 -- Scroll Lock: what the pad's Start sends in the lobby (ControllerBridge)

-- the next case runs after the widget's own check of the server's settings
-- a line in the app's touch log, as RtsTouch writes it (nil: the file made, nothing written)
local function appAct(line)
	local f = io.open("LuaUI/Config/bardroid_touch.txt", "a")
	if f then
		if line then
			f:write(line .. "\n")
		end
		f:close()
	end
end

local function settle()
	settleFrom, settleSeconds = Spring.GetTimer(), 0.8
end

local function setTags(tags)
	WG.LibLobby.lobby:_OnSetScriptTags(tags) -- (the server's own command, in the real lobby object)
end

local function warningWindow()
	for _, c in ipairs(WG.Chili.Screen0.children) do
		if c.name == "bardroidLobbyWarning" and c.visible ~= false then
			return c
		end
	end
end

local function warningText() -- (without its colour codes)
	return (WG.BarDroidLobbyTouch.warning() or ""):gsub("\255...", "")
end

local function press(key)
	return widgetHandler.callInHookFuncs.KeyPress(key, {}, false, "", 0)
end

local function allScalesAre(scale)
	for size, s in pairs(WG.Chobby.Configuration.uiScalesForScreenSizes) do
		if math.abs(s - scale) > 0.001 then
			return false, size .. " = " .. s
		end
	end
	return true
end

local function log(s)
	Spring.Echo("[lobbytouch] " .. s)
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	log((ok and "PASS " or "FAIL ") .. case .. (detail and (": " .. detail) or ""))
end

-- Spring mouse coordinates of a point on a Chili control (fx: across it, default the middle; the inverse of the
-- widget's chiliPoint)
local function mouseAt(c, fx)
	local hx, hy = c:LocalToScreen(c.width * (fx or 0.5), c.height / 2)
	local s = WG.uiScale or 1
	return hx * s, (select(2, Spring.GetViewSizes()) - hy) * s
end

local function tap(c, fx)
	local x, y = mouseAt(c, fx)
	finger.press(x, y)
	finger.release(x, y)
end

-- a finger on the warning's OK
local function tapOk()
	for _, c in ipairs(warningWindow() and warningWindow().children or {}) do
		if c.caption == "OK" then
			tap(c)
			return true
		end
	end
	return false
end

-- (Chili hands out its controls wrapped: compare what they show)
local function same(a, b)
	return a ~= nil and b ~= nil and a.caption == b.caption
end

local function popup()
	return WG.BarDroidLobbyTouch and WG.BarDroidLobbyTouch.popup()
end

local function clickTotal()
	local n = 0
	for _, v in pairs(clicked) do
		n = n + v
	end
	return n
end

local function barWindow()
	for _, c in ipairs(WG.Chili.Screen0.children) do
		if c.name == "bardroidServerBar" and c.visible ~= false then
			return c
		end
	end
end

local function barButton(caption)
	for _, b in ipairs(barWindow() and barWindow().children or {}) do
		if b.caption == caption then
			return b
		end
	end
end

-- a finger on one of the server bar's buttons (it sits over the list: a tap that falls through clicks a row)
local function tapBar(caption)
	local b = barButton(caption)
	if b then
		tap(b)
	end
	return b ~= nil
end

local cases
cases = {
	function()
		local Chili = WG.Chili
		-- (wide and tall: the server bar, at the bottom of the screen, sits over its rows)
		window = Chili.Window:New({ parent = Chili.Screen0, x = 40, y = 40, width = 1000, height = 600, resizable = false,
			draggable = false, caption = "touch test" })
		scroll = Chili.ScrollPanel:New({ parent = window, x = 0, y = 20, right = 0, bottom = 0 })
		for i = 1, 24 do
			local server = i <= 10
			-- (as Chobby's battle list: each row in a container of its own, the button named "battleButton", its map
			-- picture in a panel of its own)
			local holder = Chili.Control:New({ parent = scroll, name = "holder" .. i, x = 0, right = 0, y = (i - 1) * 40,
				height = 38, padding = { 0, 0, 0, 0 } })
			rows[i] = Chili.Button:New({
				parent = holder,
				name = server and "battleButton" or ("row" .. i),
				tooltip = server and ("battle_tooltip_" .. (90000 + i)) or nil,
				caption = (server and "server " or "row ") .. i,
				x = 0, right = 0, y = 0, bottom = 0,
				OnClick = { function() clicked[i] = (clicked[i] or 0) + 1 end },
			})
			if server then
				maps[i] = Chili.Panel:New({ parent = rows[i], name = "minimap", x = "47%", y = 2, width = 34, bottom = 2,
					padding = { 0, 0, 0, 0 } })
			end
		end
		window:BringToFront()
	end,
	function()
		local L = WG.BarDroidLobbyTouch
		check("widget loaded", L ~= nil)
		if not L then
			return
		end
		startScroll = scroll.scrollPosY
		local x, y = mouseAt(rows[3])
		check("a press on a list goes to the lobby touch widget, not Chili", finger.press(x, y) == true
			and widgetHandler.mouseOwner ~= nil and widgetHandler.mouseOwner.GetInfo().name == "BAR Droid lobby touch",
			widgetHandler.mouseOwner and widgetHandler.mouseOwner.GetInfo().name or "no owner")
		for k = 1, 6 do
			finger.move(x, y + k * 20) -- the finger goes up the screen
		end
		dragScroll = scroll.scrollPosY -- (before the release: a fling may follow)
		finger.release(x, y + 120)
	end,
	function()
		check("drag up scrolls the list down", dragScroll > startScroll + 50,
			string.format("scroll %d -> %d", startScroll, dragScroll))
		check("a drag clicks nothing", not clicked[3])
	end,
	function()
		tap(rows[12])
	end,
	function() check("a tap on a plain row clicks it", clicked[12] == 1, tostring(clicked[12])) end,
	function()
		scroll:SetScrollPos(nil, 0, false, true)
	end,
	function()
		tap(rows[2], 0.15) -- on its title
	end,
	function()
		check("first tap on a server: its details, no join", same(popup(), rows[2]) and not clicked[2])
		clicksBefore = clickTotal()
		check("the server bar is there", tapBar("Next"))
	end,
	function()
		check("a finger on Next: the server below, nothing behind the bar clicked",
			same(popup(), rows[3]) and clickTotal() == clicksBefore, string.format("popup %s, clicks %d -> %d",
			tostring(popup() and popup().caption), clicksBefore, clickTotal()))
		tapBar("Previous")
	end,
	function()
		check("a finger on Previous: the server above, nothing clicked", same(popup(), rows[2])
			and clickTotal() == clicksBefore, tostring(popup() and popup().caption))
		tapBar("Next")
	end,
	function()
		tap(maps[3]) -- the second tap lands on its map picture
	end,
	function()
		check("second tap on that server (on its map picture) joins it", clicked[3] == 1 and popup() == nil,
			string.format("clicked %s, popup %s", tostring(clicked[3]), tostring(popup() and popup().caption)))
		tap(rows[5], 0.15)
	end,
	function()
		clicksBefore = clickTotal()
		tapBar("Close")
	end,
	function()
		check("a finger on Close: the details go, nothing clicked", popup() == nil and clickTotal() == clicksBefore,
			string.format("clicks %d -> %d", clicksBefore, clickTotal()))
		tap(maps[6]) -- a first tap on a map picture shows the details too
	end,
	function()
		check("a tap on a server's map picture: its details", same(popup(), rows[6]) and not clicked[6])
		local s0 = WG.Chili.Screen0
		screenSize = { s0.width, s0.height }
		s0:Resize(s0.width + 300, s0.height + 200) -- the phone unfolds: the lobby's screen grows
	end,
	function()
		local b, s0 = barWindow(), WG.Chili.Screen0
		check("the server bar follows the screen when the phone unfolds (bottom, centred)", b ~= nil
			and b.y + b.height + 10 == s0.height and math.abs(b.x * 2 + b.width - s0.width) <= 1,
			b and string.format("bar %d,%d %dx%d on %dx%d", b.x, b.y, b.width, b.height, s0.width, s0.height))
		s0:Resize(screenSize[1], screenSize[2])
	end,
	function()
		clicksBefore = clickTotal()
		tapBar("Join")
	end,
	function()
		check("a finger on Join joins that server, nothing else", clicked[6] == 1 and popup() == nil
			and clickTotal() == clicksBefore + 1, string.format("clicked %s, clicks %d -> %d", tostring(clicked[6]),
			clicksBefore, clickTotal()))
		window:Dispose()
		-- a joined server, without a server: the id Chobby sets at a join, the settings as the server's command
		local lobby = WG.LibLobby.lobby
		lobby.myBattleID, lobby.modoptions = 90001, {}
		setTags("game/modoptions/allowuserwidgets=1\tgame/modoptions/allowunitcontrolwidgets=1")
		settle()
	end,
	function()
		check("a server that leaves the controls alone: no warning", warningWindow() == nil, warningText())
		setTags("game/modoptions/allowuserwidgets=0")
		settle()
	end,
	function()
		check("custom widgets off: touch and gamepad will not work", warningWindow() ~= nil
			and warningText():find("Touch and gamepad controls will not work", 1, true) ~= nil, warningText())
		setTags("game/modoptions/allowuserwidgets=1\tgame/modoptions/allowunitcontrolwidgets=0")
		settle()
	end,
	function()
		check("unit control widgets off: only first person", warningWindow() ~= nil
			and warningText():find("First person will not work", 1, true) ~= nil, warningText())
		check("the warning has an OK button", tapOk())
		settle()
	end,
	function()
		check("OK closes it, and it stays closed", warningWindow() == nil, warningText())
		setTags("game/modoptions/allowunitcontrolwidgets=1")
		settle()
	end,
	function()
		setTags("game/modoptions/allowunitcontrolwidgets=0")
		settle()
	end,
	function()
		check("the host takes the setting back and sets it again: shown again", warningWindow() ~= nil, warningText())
		tapOk()
		settle()
	end,
	function()
		WG.LibLobby.lobby.myBattleID = 90002
		settle()
	end,
	function()
		check("the same setting in another server: shown again", warningWindow() ~= nil, warningText())
		tapOk()
		setTags("game/modoptions/teamcolors_anonymous_mode=global")
		settle()
	end,
	function()
		check("Anonymous Mode: a new warning, though the last was closed", warningWindow() ~= nil
			and warningText():find("Touch and gamepad controls will not work", 1, true) ~= nil, warningText())
		press(97)
		check("any other key leaves the scale alone", math.abs(WG.uiScale - 1) < 0.001, tostring(WG.uiScale))
		press(SCALE_KEY)
		settle()
	end,
	function()
		local b, s0 = warningWindow(), WG.Chili.Screen0
		local all, odd = allScalesAre(1.3)
		check("Start: 130%, on every screen size", math.abs(WG.uiScale - 1.3) < 0.001 and all, odd or tostring(WG.uiScale))
		check("the warning follows the scale (top, centred, on the screen)", b ~= nil and b.y >= 0
			and b.x + b.width <= s0.width and math.abs(b.x * 2 + b.width - s0.width) <= 1,
			b and string.format("warning %d,%d %dx%d on %dx%d", b.x, b.y, b.width, b.height, s0.width, s0.height))
		press(SCALE_KEY)
		WG.LibLobby.lobby.myBattleID = nil
		appAct(nil) -- (the app's log there before the widget reads it: it starts at its end)
		settle()
	end,
	-- speak to chat: the lobby's panel in the lobby, the game's own in a game (2026-11-08: "When in game, the voice chat
	-- should only send messages to the game chat")
	function()
		appAct("act voice_on")
		settle()
	end,
	function()
		local L = WG.BarDroidLobbyTouch
		check("speak to chat in the lobby: the panel says where the words go", L.voiceShown())
		-- (its words whole and centred: they were cut at the start, the label sized to them in a 100-wide panel)
		local px, py, pw, ph, lx, lw, tw, sw, cap = L.voiceRect()
		check("  its words fit in the panel, the label as wide as it, the panel centred on the screen",
			px and tw > 0 and tw <= pw and lx == 0 and lw == pw and px >= 0 and px + pw <= sw
				and math.abs(px * 2 + pw - sw) <= 1,
			px and string.format("panel %d,%d %dx%d, label at %d %d wide, words %d wide, screen %d: %s",
				px, py, pw, ph, lx, lw, tw, sw, tostring(cap)))
		L.activate(true)
		check("a game loads: the lobby's panel goes", not L.voiceShown())
		appAct("act voice_on")
		settle()
	end,
	function()
		local L = WG.BarDroidLobbyTouch
		check("speak to chat in a game: the lobby's panel stays down", not L.voiceShown())
		appAct("act voice_off")
		L.activate(false)
		settle()
	end,
	function() -- (the microphone not allowed: Android stops asking after two "Don't allow", speak to chat said nothing)
		appAct("act voice_nomic")
		settle()
	end,
	function()
		local L = WG.BarDroidLobbyTouch
		local px, py, pw, ph, lx, lw, tw, sw, cap = L.voiceRect()
		check("the microphone not allowed: the panel says where to allow it, its words whole",
			L.voiceShown() and tostring(cap):find("MICROPHONE", 1, true) and tw > 0 and tw <= pw and lw == pw
				and math.abs(px * 2 + pw - sw) <= 1,
			px and string.format("panel %dx%d, words %d wide: %s", pw, ph, tw, tostring(cap)))
	end,
	function()
		local all, odd = allScalesAre(1)
		check("Start again: 100%", math.abs(WG.uiScale - 1) < 0.001 and all, odd or tostring(WG.uiScale))
		check("out of the server: no warning", warningWindow() == nil, warningText())
		WG.LibLobby.lobby.modoptions = {}
		log("done: " .. (fails == 0 and "ALL PASS" or fails .. " FAILED"))
	end,
}

function widget:Update()
	-- the lobby ready (bardroid_login_wait.lua: offline, its interface built) and a few seconds more
	local t0 = WG.BarDroidLoggedIn
	t = t0 and Spring.DiffTimers(Spring.GetTimer(), t0) or 0
	if t < 5 or not (WG.Chili and WG.Chili.Screen0) then
		return
	end
	if settleSeconds then
		if Spring.DiffTimers(Spring.GetTimer(), settleFrom) < settleSeconds then
			return
		end
		settleSeconds = nil
	end
	if step > #cases then -- (tools\lobby-phone-test.ps1: what a pad's Start does afterwards)
		if WG.uiScale ~= scaleLogged then
			scaleLogged = WG.uiScale
			log(string.format("scale %d%%", scaleLogged * 100 + 0.5))
		end
		return
	end
	wait = wait - 1
	if wait > 0 then
		return
	end
	step = step + 1
	local c = cases[step]
	if c then
		local ok, err = pcall(c)
		if not ok then
			check("case " .. step .. " ran", false, tostring(err))
		end
		wait = 10
	end
end
