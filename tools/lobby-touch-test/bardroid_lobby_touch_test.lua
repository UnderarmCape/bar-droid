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
		log("done: " .. (fails == 0 and "ALL PASS" or fails .. " FAILED"))
	end,
}

local t0 = Spring.GetTimer()
function widget:Update()
	t = Spring.DiffTimers(Spring.GetTimer(), t0)
	if t < 8 or not (WG.Chili and WG.Chili.Screen0) then -- the lobby builds its interface first
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
