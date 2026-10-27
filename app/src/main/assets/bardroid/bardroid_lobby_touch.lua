-- BAR Droid lobby touch: the lobby (Chobby, Chili) for fingers (Kailil, 2026-10-27: "it is miserable to try to touch
-- and drag the tiny scroll bar"; "tapping servers to only cause the popup ... then touching it again lets me join").
-- On the phone a finger is the mouse (RtsTouch: down = press, drag = move, up = release), so this widget, ahead of
-- Chili's input widget, holds back a press on a list until it knows what the finger does:
--   drag     the list scrolls with the finger (and glides after a flick); nothing is clicked
--   tap      the click Chili would have had, on release
--   tap on a server (battle list)  its details (Chobby's own server tooltip) and a bar: Close, Previous, Next, Join;
--            a second tap on the same server joins it
-- Presses outside lists, on sliders, text boxes and scroll bars go to Chili as before. Installed into
-- LuaMenu/Widgets by the app; Chobby loads it with its "loadLocalWidgets" setting (launch-bar.sh).

function widget:GetInfo()
	return {
		name = "BAR Droid lobby touch",
		desc = "Finger scrolling in the lobby's lists; server details before joining",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		-- before Chili's input (api_chili: an API widget, layer -1000). The engine's LuaHandler sorts every API widget
		-- ahead of the others whatever their layer: without api, Chili takes every press and nothing scrolls.
		api = true,
		layer = -100000,
		enabled = true,
	}
end

local DRAG_PX = 14 -- a finger that moves this far (screen pixels) scrolls instead of clicking
local FLING_MIN, FLING_DECAY = 150, 4 -- list pixels a second; per second
local BLOCKERS = { trackbar = true, editbox = true, scrollbar = true, colorbars = true }

local Chili, screen0
local press, fling
local popupButton, bar

local function uiScale()
	return WG.uiScale or 1
end

-- Spring's mouse coordinates as Chili's input widget hands them to the screen, and the screen's own hit-test point
-- (Screen:MouseDown flips y with the engine's view height)
local function chiliPoint(x, y)
	local s = uiScale()
	local sx, sy = x / s, y / s
	return sx, sy, sx, select(2, Spring.GetViewSizes()) - sy
end

-- Chili hands out each control behind proxies (New returns a hard link, every child's .parent is a weak link of its
-- own): compare the controls themselves. (Without this a tap on the server bar never counted as ours: the bar closed
-- and the tap went to whatever was behind it.)
local function real(obj)
	return obj and Chili.UnlinkSafe and Chili.UnlinkSafe(obj) or obj
end

local function battleIdOf(obj)
	return type(obj.tooltip) == "string" and tonumber(obj.tooltip:match("^battle_tooltip_(%d+)$"))
end

local function isOurs(obj)
	local ours = real(bar)
	while obj do
		if real(obj) == ours then
			return true
		end
		obj = obj.parent
	end
	return false
end

-- What a press on hit means: the list it scrolls, the server row it is on, or nothing of ours (a slider, a text box,
-- a scroll bar, outside lists).
local function classify(hit, hx, hy)
	local panel, battle
	local obj, top = real(hit), real(screen0)
	while obj and obj ~= top do
		if BLOCKERS[obj.classname] then
			return nil, nil
		end
		if not battle and obj.name == "battleButton" and battleIdOf(obj) then
			battle = obj
		end
		if obj.SetScrollPos and obj.contentArea and obj.clientArea and obj.verticalScrollbar ~= false
			and obj.contentArea[4] > obj.clientArea[4] + 1 then
			if obj == real(hit) and obj.IsAboveVScrollbars then
				local lx, ly = obj:ScreenToLocal(hx, hy)
				if obj:IsAboveVScrollbars(lx, ly) then
					return nil, nil -- the scroll bar itself: Chili drags it
				end
			end
			panel = obj
			break
		end
		obj = real(obj.parent)
	end
	return panel, battle
end

local function mods()
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	return { alt = alt, ctrl = ctrl, meta = meta, shift = shift }
end

-- the click Chili's input widget would have sent
local function click(x, y)
	local sx, sy = chiliPoint(x, y)
	local m = mods()
	screen0:MouseDown(sx, sy, 1, m)
	screen0:MouseUp(sx, sy, 1, m)
end

--------------------------------------------------------------------------------
-- Server details

local function closePopup()
	if popupButton and WG.TooltipHandler and WG.TooltipHandler.TooltipOverrideClear then
		WG.TooltipHandler.TooltipOverrideClear()
	end
	popupButton = nil
	if bar then
		bar:Hide()
	end
end

local function scrollPanelOf(obj)
	obj = obj and obj.parent
	while obj do
		if obj.SetScrollPos and obj.contentArea then
			return obj
		end
		obj = obj.parent
	end
end

local function serverRows(panel)
	local rows = {}
	local function walk(obj)
		for _, c in ipairs(obj.children or {}) do
			if type(c) == "table" then
				if c.name == "battleButton" and battleIdOf(c) and c.visible ~= false then
					local _, y = c:LocalToScreen(0, 0)
					rows[#rows + 1] = { button = c, y = y }
				else
					walk(c)
				end
			end
		end
	end
	walk(panel)
	table.sort(rows, function(a, b)
		return a.y < b.y
	end)
	return rows
end

local makeBar
local function openPopup(button)
	popupButton = real(button)
	if WG.TooltipHandler and WG.TooltipHandler.TooltipOverride then
		WG.TooltipHandler.TooltipOverride(button.tooltip)
	end
	makeBar()
	bar:Show()
	bar:BringToFront()
end

local function step(dir)
	local panel = popupButton and scrollPanelOf(popupButton)
	if not panel then
		return
	end
	local rows = serverRows(panel)
	for i, r in ipairs(rows) do
		if real(r.button) == popupButton then
			local next = rows[i + dir]
			if next then
				-- into view: its place in the list's content, centred
				local _, py = panel:LocalToScreen(0, 0)
				local ca = panel.clientArea
				panel:SetScrollPos(nil, next.y - py - ca[2] + panel.scrollPosY + (next.button.height or 0) / 2, true)
				openPopup(next.button)
			end
			return
		end
	end
end

local function join()
	local button = popupButton
	closePopup()
	if button and button.OnClick then
		button:CallListeners(button.OnClick)
	end
end

makeBar = function()
	if bar then
		return
	end
	local sw, sh = screen0.width, screen0.height
	local w, h = math.min(sw - 16, 760), 70
	bar = Chili.Window:New({
		name = "bardroidServerBar",
		parent = screen0,
		x = math.floor((sw - w) / 2),
		y = sh - h - 10,
		width = w,
		height = h,
		resizable = false,
		draggable = false,
		padding = { 6, 6, 6, 6 },
	})
	local font = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(3)
	local actions = {
		{ "Close", closePopup },
		{ "Previous", function() step(-1) end },
		{ "Next", function() step(1) end },
		{ "Join", join },
	}
	for i, a in ipairs(actions) do
		Chili.Button:New({
			parent = bar,
			x = string.format("%d%%", (i - 1) * 25),
			y = 0,
			width = "24%",
			bottom = 0,
			caption = a[1],
			objectOverrideFont = font,
			OnClick = { a[2] },
		})
	end
	bar:Hide()
end

--------------------------------------------------------------------------------
-- Input

function widget:MousePress(x, y, button)
	if button ~= 1 or not screen0 or Spring.IsGUIHidden() then
		return false
	end
	fling = nil
	local _, _, hx, hy = chiliPoint(x, y)
	local hit = screen0:HitTest(hx, hy)
	if hit and isOurs(hit) then
		return false -- the server bar's own buttons
	end
	local panel, battle = nil, nil
	if hit then
		panel, battle = classify(hit, hx, hy)
	end
	if popupButton and battle ~= popupButton then
		closePopup() -- a tap elsewhere: the details go
	end
	if not (panel or battle) then
		return false
	end
	press = { x = x, y = y, panel = panel, battle = battle, start = panel and panel.scrollPosY or 0, moved = false,
		lastY = y, lastT = Spring.GetTimer(), vel = 0 }
	return true
end

function widget:MouseMove(_, y)
	local p = press
	if not p then
		return false
	end
	if not p.moved and p.panel and math.abs(y - p.y) > DRAG_PX then
		p.moved = true
	end
	if p.moved then
		local s = uiScale()
		p.panel:SetScrollPos(nil, p.start + (y - p.y) / s, false, true)
		local now = Spring.GetTimer()
		local dt = Spring.DiffTimers(now, p.lastT)
		if dt > 0.001 then
			p.vel = p.vel * 0.6 + (y - p.lastY) / s / dt * 0.4
			p.lastY, p.lastT = y, now
		end
	end
	return true
end

function widget:MouseRelease(x, y)
	local p = press
	press = nil
	if not p then
		return false
	end
	if p.moved then
		if math.abs(p.vel) > FLING_MIN and Spring.DiffTimers(Spring.GetTimer(), p.lastT) < 0.1 then
			fling = { panel = p.panel, v = p.vel }
		end
	elseif p.battle then
		if popupButton == p.battle then
			join()
		else
			openPopup(p.battle)
		end
	else
		click(x, y)
	end
	return true
end

local lastUpdate
function widget:Update() -- (the lobby's Update has no frame time)
	local now = Spring.GetTimer()
	local dt = lastUpdate and math.min(0.1, Spring.DiffTimers(now, lastUpdate)) or 0
	lastUpdate = now
	if not screen0 then
		Chili = WG.Chili
		screen0 = Chili and Chili.Screen0
		return
	end
	if fling then
		local panel = fling.panel
		if panel.disposed or not panel.parent then
			fling = nil
		else
			panel:SetScrollPos(nil, panel.scrollPosY + fling.v * dt, false, true)
			fling.v = fling.v * math.exp(-dt * FLING_DECAY)
			if math.abs(fling.v) < 20 then
				fling = nil
			end
		end
	end
	if popupButton and (popupButton.disposed or not popupButton.parent or popupButton.visible == false) then
		closePopup() -- the list went away (another screen, the server closed)
	end
end

function widget:Initialize()
	-- (tools/lobby-touch-test.ps1: the same input as a finger, without one)
	WG.BarDroidLobbyTouch = {
		press = function(x, y) return widget:MousePress(x, y, 1) end,
		move = function(x, y) return widget:MouseMove(x, y, 0, 0, 1) end,
		release = function(x, y) return widget:MouseRelease(x, y, 1) end,
		popup = function() return popupButton end,
	}
end

function widget:Shutdown()
	WG.BarDroidLobbyTouch = nil
	closePopup()
	if bar then
		bar:Dispose()
		bar = nil
	end
end
