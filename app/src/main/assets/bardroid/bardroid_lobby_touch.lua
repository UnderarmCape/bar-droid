-- BAR Droid lobby touch: the lobby (Chobby, Chili) for fingers (Kailil, 2026-10-27: "it is miserable to try to touch
-- and drag the tiny scroll bar"; "tapping servers to only cause the popup ... then touching it again lets me join").
-- On the phone a finger is the mouse (RtsTouch: down = press, drag = move, up = release), so this widget, ahead of
-- Chili's input widget, holds back a press on a list until it knows what the finger does:
--   drag     the list scrolls with the finger (and glides after a flick); nothing is clicked
--   tap      the click Chili would have had, on release
--   tap on a server (battle list)  its details (Chobby's own server tooltip) and a bar: Close, Previous, Next, Join;
--            a second tap on the same server joins it
-- Presses outside lists, on sliders, text boxes and scroll bars go to Chili as before. After a press the hover tooltips
-- wait until the pointer moves on (a finger leaves it where it lifted: a tooltip stayed up), and again from where a
-- drag on a list ends. Also: a warning in a server
-- whose settings take away the app's controls (Kailil, 2026-11-01: the lobby has no room to show them), and the pad's
-- Start in the lobby: the interface scale 100% or 130% (launch-bar.sh starts at 100%). Installed into LuaMenu/Widgets
-- by the app; Chobby loads it with its "loadLocalWidgets" setting (launch-bar.sh).

function widget:GetInfo()
	return {
		name = "BAR Droid lobby touch",
		desc = "Finger scrolling in the lobby's lists; server details before joining; warns of settings that stop the controls",
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
local SCALE_KEY = 302 -- Scroll Lock (the engine's key code): ControllerBridge sends it for the pad's Start
local SCALE_SMALL, SCALE_LARGE = 1.0, 1.3
local WARNING_CHECK_S = 0.5 -- a joined server's settings arrive after the join, and its host can change them later
local OFF_VALUES = { ["0"] = true, ["false"] = true }
-- (the title white and the reason in the box's tint, a size smaller: with the title tinted and the reason white, the
-- reason outshone what the warning is about, dev phone 2026-11-05)
local WARNING_RED = { fill = { 0.5, 0.06, 0.05, 1 }, edge = { 0.95, 0.3, 0.25, 1 }, why = "\255\255\205\170" }
local WARNING_AMBER = { fill = { 0.42, 0.27, 0.02, 1 }, edge = { 0.95, 0.7, 0.2, 1 }, why = "\255\255\225\130" }

local Chili, screen0
local press, fling
local hush -- where the last press left the pointer: Chili's hover tooltip held back until it moves (Update)
local popupButton, bar
local warning, warningTitle, warningWhy, warningColour, warningShown, warningClosed, warningBattle, warningSize, warningCheck

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

local function overflows(obj)
	return obj.SetScrollPos and obj.contentArea and obj.clientArea and obj.verticalScrollbar ~= false
		and obj.contentArea[4] > obj.clientArea[4] + 1
end

-- The innermost list within obj that lies under the point, by its place on the screen. Chili's hit test passes over a
-- list's labels and gaps (no handler of their own) to the window behind it: a finger on a settings line's words, or
-- between them and its control, did not scroll the lobby's Settings (only its checkbox lines did; dev phone,
-- 2026-11-02). Searched only inside what was hit, so a dropdown open over a list is not scrolled through.
local function listUnder(obj, hx, hy)
	obj = real(obj)
	if not obj or obj.hidden or obj.visible == false or not obj.LocalToScreen then
		return nil
	end
	local x, y = obj:LocalToScreen(0, 0)
	if hx < x or hy < y or hx > x + (obj.width or 0) or hy > y + (obj.height or 0) then
		return nil
	end
	for _, child in ipairs(obj.children or {}) do
		local inner = listUnder(child, hx, hy)
		if inner then
			return inner
		end
	end
	return overflows(obj) and obj or nil
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
		if overflows(obj) then
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
	if not panel and not battle then
		panel = listUnder(hit, hx, hy)
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

local makeBar, placeBar
local function openPopup(button)
	popupButton = real(button)
	if WG.TooltipHandler and WG.TooltipHandler.TooltipOverride then
		WG.TooltipHandler.TooltipOverride(button.tooltip)
	end
	makeBar()
	placeBar()
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

-- centred at the bottom of the screen as it is now (folding or unfolding the phone resizes the lobby's screen)
local barSize
placeBar = function()
	local sw, sh = screen0.width, screen0.height
	local w, h = math.min(sw - 16, 760), 70
	bar:SetPos(math.floor((sw - w) / 2), sh - h - 10, w, h)
	barSize = sw .. "x" .. sh
end

makeBar = function()
	if bar then
		return
	end
	bar = Chili.Window:New({
		name = "bardroidServerBar",
		parent = screen0,
		x = 0,
		y = 0,
		width = 100,
		height = 70,
		resizable = false,
		draggable = false,
		padding = { 6, 6, 6, 6 },
	})
	local font = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(3)
	local actions = {
		{ "Close", closePopup },
		{ "Previous", function() step(-1) end },
		{ "Next", function() step(1) end },
		{ "Join", join, "positive_button" }, -- (the skin's "go ahead", as its red negative_button is "cancel")
	}
	for i, a in ipairs(actions) do
		Chili.Button:New({
			parent = bar,
			x = string.format("%.1f%%", (i - 1) * 25 + 0.5),
			y = 0,
			width = "24%",
			bottom = 0,
			caption = a[1],
			classname = a[3],
			objectOverrideFont = font,
			OnClick = { a[2] },
		})
	end
	bar:Hide()
end

--------------------------------------------------------------------------------
-- A server's settings that stop the app's controls (BAR's luaui/barwidgets.lua). The controls are user widgets:
-- custom widgets off, or Anonymous Mode, keeps all of them out of a player's game (a spectator's game is exempt);
-- unit control widgets off only stops first person (the rest of the app gives no Spring.GiveOrder).

local function warningLines(title, why, colour)
	return "\255\255\255\255" .. title .. "\n" .. colour.why .. why, colour
end

local function controlsWarning(options)
	-- (the app's widgets loaded as the game's, an engine-branch build: launch-bar.sh's BARDROID_GAME_WIDGETS; neither
	-- setting reaches them there)
	if VFS.FileExists("LuaUI/Config/bardroid_game_widgets.txt", VFS.RAW) then
		return nil
	end
	local anonymous = options.teamcolors_anonymous_mode
	if OFF_VALUES[tostring(options.allowuserwidgets)] or (anonymous and anonymous ~= "disabled") then
		return warningLines("Touch and gamepad controls will not work if you play here",
			"The host turned off custom widgets. They do work if you spectate.", WARNING_RED)
	end
	if OFF_VALUES[tostring(options.allowunitcontrolwidgets)] then
		return warningLines("First person will not work in this game",
			"The host turned off unit control widgets. Touch and gamepad controls work.", WARNING_AMBER)
	end
end

-- at the top of the screen as it is now (the scale and folding the phone both resize the lobby's screen)
local function placeWarning()
	local sw = screen0.width
	local w = math.min(sw - 16, 900)
	warning:SetPos(math.floor((sw - w) / 2), 8, w, 92)
	warningSize = sw .. "x" .. screen0.height
end

local function closeWarning()
	warningClosed = warningShown
	warningShown = nil
	warning:Hide()
end

local function makeWarning()
	local config = WG.Chobby and WG.Chobby.Configuration
	local font = config and config:GetFont(3)
	local small = config and config:GetFont(2) or font
	warning = Chili.Window:New({
		name = "bardroidLobbyWarning",
		parent = screen0,
		x = 0,
		y = 0,
		width = 100,
		height = 92,
		resizable = false,
		draggable = false,
		padding = { 0, 0, 0, 0 },
	})
	-- (the title and the reason each a line of their own, apart and in the middle of the box: as one text box's two
	-- lines they touched, with the box's room all below them)
	warningTitle = Chili.TextBox:New({
		parent = warning,
		x = 14,
		y = 16,
		right = 118,
		height = 30,
		text = "",
		objectOverrideFont = font,
	})
	warningWhy = Chili.TextBox:New({
		parent = warning,
		x = 14,
		y = 52,
		right = 118,
		bottom = 0,
		text = "",
		objectOverrideFont = small,
	})
	Chili.Button:New({
		parent = warning,
		right = 8,
		y = 8,
		width = 100,
		bottom = 8,
		caption = "OK",
		objectOverrideFont = font,
		OnClick = { closeWarning },
	})
	Chili.Control:New({ -- (the last child draws first; a window's own colour only tints the skin's dark, clear picture)
		parent = warning,
		x = 0,
		y = 0,
		width = "100%",
		height = "100%",
		padding = { 0, 0, 0, 0 },
		drawcontrolv2 = true, -- (drawn in its own place, Chili 2.1: without it a warning in every lobby's log)
		DrawControl = function(obj)
			gl.Texture(false)
			gl.Color(warningColour.edge)
			gl.Rect(0, 0, obj.width, obj.height)
			gl.Color(warningColour.fill)
			gl.Rect(2, 2, obj.width - 2, obj.height - 2)
			gl.Color(1, 1, 1, 1)
		end,
	})
	warning:Hide()
end

-- Nothing while no server is joined. A warning closed stays closed until it says something else, the host takes the
-- setting back, or the player is in another server.
local function updateWarning()
	local lobby = WG.LibLobby and WG.LibLobby.lobby
	local battle = lobby and lobby.myBattleID
	local text, colour
	if battle then
		text, colour = controlsWarning(lobby.modoptions or {})
	end
	if not text or battle ~= warningBattle then
		warningClosed = nil
	end
	warningBattle = battle
	if text == warningClosed then
		text = nil
	end
	if text ~= warningShown then
		warningShown = text
		if not warning then
			makeWarning()
		end
		if text then
			local title, why = text:match("^(.-)\n(.*)$")
			warningTitle:SetText(title or text)
			warningWhy:SetText(why or "")
			warningColour = colour
			placeWarning()
			warning:Show()
			warning:BringToFront()
		else
			warning:Hide()
		end
	elseif warningShown and warningSize ~= screen0.width .. "x" .. screen0.height then
		placeWarning()
	end
end

--------------------------------------------------------------------------------
-- The interface scale, the same on every screen size (Chobby keeps one per size: folding would change it back)

local function toggleScale()
	local config = WG.Chobby and WG.Chobby.Configuration
	if not (config and config.SetUiScale) then
		return
	end
	local scale = (config.uiScale or SCALE_SMALL) < (SCALE_SMALL + SCALE_LARGE) / 2 and SCALE_LARGE or SCALE_SMALL
	for size in pairs(config.uiScalesForScreenSizes or {}) do -- (a lobby version without the per-size table: just the scale)
		config.uiScalesForScreenSizes[size] = scale
	end
	config:SetUiScale(scale)
end

function widget:KeyPress(key)
	if key ~= SCALE_KEY then
		return false
	end
	toggleScale()
	return true
end

--------------------------------------------------------------------------------
-- Input

function widget:MousePress(x, y, button)
	hush = { x = x, y = y } -- (any button: a finger's long press is a right click, and lifted there too)
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
	hush = { x = x, y = y } -- (after a drag too: a replay's teams came up where the finger lifted)
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
	-- A finger leaves the pointer where it lifted, and Chili's hover tooltip of whatever is under it stayed up: on the
	-- Skirmish screen a tapped map's picture as large as the screen, over the Next button (dev phone, 2026-11-02). Held
	-- back from a press until the pointer moves away; a mouse moving on gets its tooltips as before. And the hover look
	-- once the button is up: Cancel tapped in the Register dialog left the Welcome screen's "Code of Conduct" under the
	-- pointer lit as if picked (dev phone, 2026-11-03). Chili hovers a control again only when the pointer reaches another
	-- (Screen:IsAbove), so one MouseOut keeps it plain; a mouse moving on over that same control lights it again.
	if hush then
		local mx, my, left, middle, right = Spring.GetMouseState()
		if math.abs(mx - hush.x) + math.abs(my - hush.y) > DRAG_PX then
			local out = hush.out
			hush = nil
			if out and screen0._lastHoveredControl == out then
				pcall(function() out:MouseOver() end)
			end
		else
			screen0.currentTooltip = nil
			local hovered = screen0._lastHoveredControl
			if hovered and hovered ~= hush.out and not (left or middle or right) then
				hush.out = hovered
				pcall(function() hovered:MouseOut() end) -- (a weak link: its control may be gone)
			end
		end
	end
	if popupButton and (popupButton.disposed or not popupButton.parent or popupButton.visible == false) then
		closePopup() -- the list went away (another screen, the server closed)
	elseif popupButton and barSize ~= screen0.width .. "x" .. screen0.height then
		placeBar() -- folded or unfolded
	end
	if not warningCheck or Spring.DiffTimers(now, warningCheck) >= WARNING_CHECK_S then
		warningCheck = now
		updateWarning()
	end
end

function widget:Initialize()
	-- (tools/lobby-touch-test.ps1: the same input as a finger, without one)
	WG.BarDroidLobbyTouch = {
		press = function(x, y) return widget:MousePress(x, y, 1) end,
		move = function(x, y) return widget:MouseMove(x, y, 0, 0, 1) end,
		release = function(x, y) return widget:MouseRelease(x, y, 1) end,
		popup = function() return popupButton end,
		warning = function() return warningShown end,
	}
end

function widget:Shutdown()
	WG.BarDroidLobbyTouch = nil
	closePopup()
	if bar then
		bar:Dispose()
		bar = nil
	end
	if warning then
		warning:Dispose()
		warning = nil
	end
end
