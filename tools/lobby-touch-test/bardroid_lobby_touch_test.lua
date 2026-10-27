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
local window, scroll, rows, clicked = nil, nil, {}, {}
local startScroll, dragScroll

local function log(s)
	Spring.Echo("[lobbytouch] " .. s)
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	log((ok and "PASS " or "FAIL ") .. case .. (detail and (": " .. detail) or ""))
end

-- Spring mouse coordinates of the middle of a Chili control (the inverse of the widget's chiliPoint)
local function mouseAt(c)
	local hx, hy = c:LocalToScreen(c.width / 2, c.height / 2)
	local s = WG.uiScale or 1
	return hx * s, (select(2, Spring.GetViewSizes()) - hy) * s
end

-- (Chili hands out its controls wrapped: compare what they show)
local function same(a, b)
	return a ~= nil and b ~= nil and a.caption == b.caption
end

local function barButton(caption)
	for _, c in ipairs(WG.Chili.Screen0.children) do
		if c.name == "bardroidServerBar" then
			for _, b in ipairs(c.children) do
				if b.caption == caption then
					return b
				end
			end
		end
	end
end

local cases
cases = {
	function()
		local Chili = WG.Chili
		window = Chili.Window:New({ parent = Chili.Screen0, x = 100, y = 40, width = 420, height = 600, resizable = false,
			draggable = false, caption = "touch test" })
		scroll = Chili.ScrollPanel:New({ parent = window, x = 0, y = 20, right = 0, bottom = 0 })
		for i = 1, 24 do
			local server = i <= 10
			-- (as Chobby's battle list: each row in a container of its own, the button named "battleButton")
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
		local x, y = mouseAt(rows[12])
		finger.press(x, y)
		finger.release(x, y)
	end,
	function() check("a tap on a plain row clicks it", clicked[12] == 1, tostring(clicked[12])) end,
	function()
		scroll:SetScrollPos(nil, 0, false, true)
	end,
	function()
		local x, y = mouseAt(rows[2])
		local s = WG.uiScale or 1
		local hit = WG.Chili.Screen0:HitTest(x / s, select(2, Spring.GetViewSizes()) - y / s)
		local chain, o = {}, hit
		while o and #chain < 6 do
			chain[#chain + 1] = tostring(o.name) .. "/" .. tostring(o.classname)
			o = o.parent
		end
		log("     hit at server 2: " .. table.concat(chain, " < ") .. string.format(" (uiScale %s, scroll %d)", tostring(WG.uiScale), scroll.scrollPosY))

		finger.press(x, y)
		finger.release(x, y)
	end,
	function()
		local L = WG.BarDroidLobbyTouch
		check("first tap on a server: its details, no join", same(L.popup(), rows[2]) and not clicked[2])
		local next = barButton("Next")
		check("the server bar is there", next ~= nil)
		if next then
			next:CallListeners(next.OnClick)
		end
	end,
	function()
		check("Next: the server below", same(WG.BarDroidLobbyTouch.popup(), rows[3]))
		local x, y = mouseAt(rows[3])
		finger.press(x, y)
		finger.release(x, y)
	end,
	function()
		check("second tap on that server joins it", clicked[3] == 1 and WG.BarDroidLobbyTouch.popup() == nil,
			tostring(clicked[3]))
		local x, y = mouseAt(rows[5])
		finger.press(x, y)
		finger.release(x, y)
	end,
	function()
		local close = barButton("Close")
		if close then
			close:CallListeners(close.OnClick)
		end
	end,
	function()
		check("Close: the details go, nothing joined", WG.BarDroidLobbyTouch.popup() == nil and not clicked[5])
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
