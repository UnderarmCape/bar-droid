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
		handler = true, -- (the real widgetHandler: stopping BAR's Rapid Pool Cache, poolCacheCheck)
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
-- a press or the pad's click, when: a lobby tab may have opened, replaysRowCheck looks for a few seconds after (it walked
-- every control once a second for the whole session until Replays, Links and Plugins had all been opened; review
-- 2026-11-15)
local tabWake = { at = nil }

local function uiScale()
	return WG.uiScale or 1
end

-- The pointer in the engine's pixels, as the call-ins hand them out: Chobby's function_override.lua makes
-- Spring.GetMouseState answer in its own scaled units (pixels over the lobby's scale) and keeps the engine's as
-- Spring.Orig.GetMouseState. (Read as pixels the D-pad's pointer was let go after every step and the next one started
-- from the wrong place at any scale but 100 %: upright, 135 %; dev phone, 2026-11-10.)
local function mouse()
	local orig = Spring.Orig and Spring.Orig.GetMouseState
	if orig then
		return orig()
	end
	return Spring.GetMouseState()
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
	tabWake.at = Spring.GetTimer()
	local sx, sy = chiliPoint(x, y)
	local m = mods()
	screen0:MouseDown(sx, sy, 1, m)
	screen0:MouseUp(sx, sy, 1, m)
end

--------------------------------------------------------------------------------
-- Server details

local function scrollPanelOf(obj)
	obj = obj and obj.parent
	while obj do
		if obj.SetScrollPos and obj.contentArea then
			return obj
		end
		obj = obj.parent
	end
end

-- A tapped server's details pinned to the server list's top right (Kailil, 2026-11-09: "this popup that occurs when
-- clicking the server should stay pinned on the top right hand corner of the server list always", upright and wide):
-- Chobby's tooltip widget puts its window at the pointer at every update (gui_tooltip.lua SetTooltipPos); while the
-- details are up that window's SetPos takes the list's corner instead. Back to Chobby's own when they close.
local function pinnedPlace(w, h)
	local panel = popupButton and scrollPanelOf(popupButton)
	if not (panel and panel.LocalToScreen) then
		return nil
	end
	local px, py = panel:LocalToScreen(0, 0)
	local x = px + (panel.width or 0) - (w or 0) - 4
	local y = math.max(0, math.min(py + 4, screen0.height - (h or 0)))
	return math.max(0, x), y
end

local function pinTooltip(on)
	local tip = screen0 and screen0.GetObjectByName and real(screen0:GetObjectByName("tooltipWindow"))
	if not tip then
		return
	end
	if on and not tip.bardroidSetPos then
		local setPos = tip.SetPos
		tip.bardroidSetPos = setPos
		tip.SetPos = function(self, x, y, w, h, ...)
			local px, py = pinnedPlace(w or self.width, h or self.height)
			if px then
				x, y = px, py
			end
			return setPos(self, x, y, w, h, ...)
		end
	elseif not on and tip.bardroidSetPos then
		tip.SetPos, tip.bardroidSetPos = nil, nil -- (the class's own again)
	end
end

local function closePopup()
	if popupButton and WG.TooltipHandler and WG.TooltipHandler.TooltipOverrideClear then
		WG.TooltipHandler.TooltipOverrideClear()
	end
	popupButton = nil
	pinTooltip(false)
	if bar then
		bar:Hide()
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
	pinTooltip(true)
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

-- centred at the bottom of the screen as it is now (folding or unfolding the phone resizes the lobby's screen);
-- upright: just above the bottom buttons (uprightBarTop), the content shrunk to leave it room
local barSize
local uprightBarTop -- (set below: the top of the upright bottom buttons, nil when not upright)
local uprightRelayout
-- (sideways, the column of big buttons' right edge, 0 without it: the bar and the warning centred in the room beside it;
-- on the whole screen the bar's Close lay over the column's down arrow and the warning over Multiplayer, review
-- 2026-11-15; set below, where the column is)
local sideLeft
local function sideKey()
	return screen0.width .. "x" .. screen0.height .. "+" .. (sideLeft and sideLeft() or 0)
end
placeBar = function()
	local sw, sh = screen0.width, screen0.height
	local left = sideLeft and sideLeft() or 0
	local w, h = math.min(sw - left - 16, 760), 70
	local top = uprightBarTop and uprightBarTop()
	bar:SetPos(left + math.floor((sw - left - w) / 2), (top or sh) - h - (top and 4 or 10), w, h)
	barSize = sideKey()
	if uprightRelayout then
		uprightRelayout()
	end
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
-- Upright (Kailil, 2026-11-09: "the vertical menu and scale is too small. Also move the buttons on the side and top
-- to the very bottom of the screen so its more easy to reach. Then to press next and prev on the different servers it
-- should appear on top of the buttons at the bottom of the screen and that should shrink the vertical space if the
-- server list"): Chobby's left column hidden and its buttons, with the top's (Keys, Website, Account), as a grid along
-- the bottom, each a tap on Chobby's own (its OnClick: the same handlers, its look copied: the menu picked lit); the
-- content takes the width and ends above the grid, and above the server bar (Close, Previous, Next, Join) while it is
-- up. The scale larger while upright (SCALE_UPRIGHT; the old one back after). Chobby lays itself out again on its own
-- (resizes, its panels): checked twice a second and laid out again.
local UPRIGHT = 1.05
local SCALE_UPRIGHT = 1.35
local gameLoaded = false -- a game runs beside the lobby (ActivateGame / ActivateMenu, below): no grid then
-- The grid in pages (Kailil, 2026-11-10: "make the buttons larger and allow scrolling ... the magnetic snapping type of
-- scrolling and it scrolls in pages. Not line by one ... a subtle snap animation to each swipe"): PAGE_COLS x PAGE_ROWS
-- larger buttons a page, the pages side by side in a strip a sideways swipe moves with the finger; let go it settles on
-- the nearest page (a flick: the next one) with a small overshoot; dots under it say which page
-- Kailil, 2026-11-10 ("we need a curser selection", his pages unseen under Chobby's version line): the page strip under
-- the buttons taller, a tap on its arrows turns the page (on a dot: that page), Chobby's caching line in it and its
-- version line off while upright (both lay over the strip at the screen's foot)
local PAGE_COLS, PAGE_ROWS, GRID_ROW_H, GRID_GAP, GRID_DOTS_H = 3, 2, 60, 4, 28
local GRID_ORDER = { "multiplayer", "skirmish", "scenarios", "settings", "chat", "friends",
	"parties", "load game", "downloads", "account", "login", "replays", "links" } -- (Login: Account's place offline)
-- Kailil, 2026-11-10, on the Fold7: "too slow of an animation. It should be super snappy and fast and smooth ... the
-- swipe sensitivity curve needs to be more aggressive. A small swipe quickly moves the page": the strip goes 1.5 times
-- the finger's way, a drag of a twentieth of the width (or a light flick) turns the page that way, and it settles in
-- 0.15 s with a slight overshoot (was 0.28 s, half the width or a 600 flick)
local PAGE_SETTLE, PAGE_OVERSHOOT, PAGE_FLICK = 0.15, 0.35, 200 -- seconds; easeOutBack's; Chili pixels a second
local PAGE_GAIN, PAGE_TURN = 1.5, 0.05 -- the strip's move per finger move; the drag (share of the width) that turns
-- Sideways the same buttons as one column down the left (Kailil, 2026-11-12: "in the landscape Lobby, the buttons on
-- the left ... Make them big like the vertical buttons look. and move ALL buttons to the left side of the page, even the
-- buttons in the top right hand corner like login. so the main window has the full vertical space. make all the buttons
-- come together with minimal padding. allow swiping pages up and down. it will be a single column of buttons"): side
-- mode, upright.side. The column SIDE_SHARE of the width (SIDE_MIN to SIDE_MAX), Chobby's logo and status line off (the
-- connection state in the column's top line), the content from the column to the right edge, top to bottom; the pages
-- one under the other, a swipe up or down turns them. (upright.on: the grid or the column is up; stripX: the strip's
-- offset along its pages, x or y; pageSize: a page's length along it)
local SIDE_SHARE, SIDE_MIN, SIDE_MAX, SIDE_STATUS_H = 0.2, 190, 300, 36
local upright = { on = false, side = false, grid = nil, mirror = {}, scaleBefore = nil, checkAt = nil, page = 0, pages = 1,
	stripX = 0, pageSize = 1, anim = nil }

-- The pages' strip moved: each button to its place on its page plus the offset (a strip of its own, three screens wide,
-- was not drawn by Chili: its buttons stood in the grid as before); sideways down the column
-- A button's place on the strip. Chili takes a negative number as measured from the parent's far edge (util.lua
-- ProcessRelativeCoord: total + num), so a page left of the one shown came back onto the screen: the grid made again
-- on page 3 (back from a game, 19 buttons to 17) drew page 2's over page 3's, "Welcome" showing through "Parties"
-- (dev phone, 2026-11-13). A negative place is set as the plain number it is.
local function stripPlace(c, v)
	v = math.floor(v + 0.5)
	local key, bound = upright.side and "y" or "x", upright.side and "top" or "left"
	if v >= 0 then
		if upright.side then
			c:SetPos(nil, v)
		else
			c:SetPos(v)
		end
	elseif c[key] ~= v then
		c[key] = v
		c._relativeBounds[bound], c._givenBounds[bound] = false, v
		c:UpdateClientArea(true)
	end
end

local function stripTo(x)
	upright.stripX = x
	for _, m in ipairs(upright.mirror) do
		if m.base and not m.mine.disposed then
			stripPlace(m.mine, m.base + x)
		end
	end
end

local function chobbyObject(name)
	return screen0 and screen0.GetObjectByName and screen0:GetObjectByName(name)
end

-- Chobby's buttons the grid stands for: the left column's (the menus, the panels' tabs, Exit), the top's
local function chobbyButtons()
	local out = {}
	local function walk(obj, top)
		local list = {}
		for _, c in ipairs(obj and obj.children or {}) do
			list[#list + 1] = c
		end
		if top then -- (the top's buttons: hidden by uprightRelayout, Chili keeps them in children_hidden)
			for c in pairs(obj and obj.children_hidden or {}) do
				list[#list + 1] = c
			end
		end
		for _, c in ipairs(list) do
			c = real(c)
			if c.classname == "button" or c.classname == "negative_button" or c.classname == "positive_button"
				or (c.OnClick and #c.OnClick > 0 and type(c.caption) == "string") then
				if type(c.caption) == "string" and c.caption ~= "" then
					out[#out + 1] = { button = c, top = top }
				end
			else
				walk(c, top)
			end
		end
	end
	walk(chobbyObject("buttonsHolder_buttons"), false)
	walk(chobbyObject("holder_status"), true)
	if gameLoaded then -- (over a game: Chobby's top bar, Return to Battle and Leave Battle, in the grid too)
		walk(chobbyObject("holder_topBar"), true)
	end
	-- Kailil's order (2026-11-10: "the first 6 buttins shoukd be multi-player, skirmish, scenarios, settings, chat,
	-- friends. Next page. Parties, load game, downloads, account, and you sort the rest"): those by their words, then
	-- Replays and Links (the page's last two), the rest as Chobby has them, Exit last (away from the thumbs' first reach)
	local rank = {}
	for i, f in ipairs(out) do
		local c = string.lower(f.button.caption):gsub("\255...", ""):gsub("^%s+", "")
		rank[f] = 100 + i
		for k, word in ipairs(GRID_ORDER) do
			if c:sub(1, #word) == word then
				rank[f] = k
				break
			end
		end
		if c == "exit" or c == "quit" then
			rank[f] = 1000
		elseif c == "return to battle" then -- (over a game: back to it first, leaving it last but Exit)
			rank[f] = 0
		elseif c == "leave battle" then
			rank[f] = 999
		end
	end
	table.sort(out, function(a, b)
		return rank[a] < rank[b]
	end)
	return out
end

uprightBarTop = function()
	if not (upright.on and upright.grid) or upright.side then
		return nil
	end
	return upright.grid.y
end
sideLeft = function()
	local col = upright.on and upright.side and real(upright.grid)
	return col and not col.disposed and math.floor((col.x or 0) + (col.width or 0)) or 0
end

-- Sideways: Chobby's logo and status off, the content from the column's right edge, the whole height (the server bar,
-- while it is up, at the foot over the content as Chobby's own)
local function sideRelayout()
	local colW = upright.grid and upright.grid.width or 0
	upright.sideHidden = upright.sideHidden or {}
	for _, name in ipairs({ "holder_heading", "holder_status" }) do
		local o = real(chobbyObject(name))
		if o and o.visible ~= false then
			o:SetVisibility(false)
			upright.sideHidden[o] = true -- (shown again with Chobby's layout: uprightOff)
		end
	end
	local column = chobbyObject("mainWindow_buttonsHolder")
	if column and column.visible ~= false then
		column:SetVisibility(false)
	end
	local barUp = bar and bar.visible
	upright.sideBounds = upright.sideBounds or {}
	for _, name in ipairs({ "holder_mainWindow", "holder_submenuWindow" }) do
		local o = chobbyObject(name)
		local r = real(o)
		if r and r._relativeBounds and not upright.sideBounds[r] then -- (Chobby's own place, for uprightOff)
			local rb = {}
			for k, v in pairs(r._relativeBounds) do
				rb[k] = v
			end
			upright.sideBounds[r] = { x = r.x, y = r.y, rb = rb }
		end
		if o and o._relativeBounds then
			if o.x ~= colW or o.y ~= 0 then
				o:SetPos(colW, 0)
			end
			o._relativeBounds.right = 0
			o._relativeBounds.width = false
			o._relativeBounds.bottom = barUp and (bar.height + 14) or 0
			o:UpdateClientArea()
		end
	end
	local content = chobbyObject("mainWindow_mainContent")
	if content and content._relativeBounds then
		if content.x ~= 0 then
			content:SetPos(0)
		end
		content._relativeBounds.right = 0
		content._relativeBounds.bottom = 0
		content:UpdateClientArea()
	end
	for _, m in ipairs(upright.mirror) do -- (the top's buttons: in the column)
		if m.top and m.button.visible ~= false then
			m.button:SetVisibility(false)
		end
	end
	local st, s = real(chobbyObject("connectivityText")), upright.status -- (the connection state, in the column's top)
	if st and s and not s.disposed and type(st.text) == "string" and s.caption ~= st.text then
		s:SetCaption(st.text)
	end
end

-- the content between the top and the grid (and the server bar while it is up); Chobby's left column hidden
uprightRelayout = function()
	if not upright.on then
		return
	end
	if upright.side then
		return sideRelayout()
	end
	local barUp = bar and bar.visible
	local bottom = (screen0.height - (upright.grid and upright.grid.y or screen0.height)) + (barUp and (bar.height + 4) or 0)
	local column = chobbyObject("mainWindow_buttonsHolder")
	if column and column.visible ~= false then
		column:SetVisibility(false)
	end
	for _, name in ipairs({ "mainWindow_mainContent", "holder_submenuWindow" }) do
		local o = chobbyObject(name)
		if o and o._relativeBounds then
			if o.x ~= 0 then
				o:SetPos(0)
			end
			o._relativeBounds.right = 0
			o._relativeBounds.bottom = name == "holder_submenuWindow" and bottom or 0
			o:UpdateClientArea()
		end
	end
	local main = chobbyObject("holder_mainWindow")
	if main and main._relativeBounds then
		main._relativeBounds.right = 0
		main._relativeBounds.bottom = bottom
		main:UpdateClientArea()
	end
	for _, m in ipairs(upright.mirror) do -- (the top's buttons: in the grid)
		if m.top and m.button.visible ~= false then
			m.button:SetVisibility(false)
		end
	end
end

local function uprightGrid()
	local found = chobbyButtons()
	if #found == 0 then
		return
	end
	local sw, sh = screen0.width, screen0.height
	local isSide = upright.side
	local colW = math.floor(math.max(SIDE_MIN, math.min(SIDE_MAX, sw * SIDE_SHARE)))
	-- (sideways: as many rows as the column holds between its status line and its page strip, one button a row)
	local sideRows = math.max(1, math.floor((sh - SIDE_STATUS_H - GRID_DOTS_H - GRID_GAP) / (GRID_ROW_H + GRID_GAP)))
	local perPage = isSide and sideRows or PAGE_COLS * PAGE_ROWS
	local pages = math.ceil(#found / perPage)
	local rows = isSide and math.min(sideRows, #found) or math.min(PAGE_ROWS, math.ceil(#found / PAGE_COLS))
	local dots = pages > 1 and GRID_DOTS_H or 0
	local h = isSide and sh or rows * GRID_ROW_H + (rows + 1) * GRID_GAP + dots
	if upright.grid then
		upright.grid:Dispose()
	end
	upright.pages = pages
	upright.page = math.min(upright.page, pages - 1)
	upright.pageSize = isSide and sh or sw -- (a page's length along the strip: off the screen when not shown)
	upright.anim = nil
	upright.grid = Chili.Window:New({
		name = "bardroidLobbyGrid",
		parent = screen0,
		x = 0, y = sh - h, width = isSide and colW or sw, height = h,
		resizable = false, draggable = false,
		padding = { 0, GRID_GAP, 0, GRID_GAP },
	})
	upright.caching, upright.status = nil, nil
	if isSide then -- (the connection state, Chobby's own words: sideRelayout)
		upright.status = Chili.Label:New({ -- (centred, a size up: in the corner at Chobby's small size it was barely read)
			parent = upright.grid,
			x = GRID_GAP, y = 0, right = GRID_GAP, height = SIDE_STATUS_H - GRID_GAP,
			autosize = false,
			caption = "",
			align = "center",
			valign = "center",
			objectOverrideFont = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(3),
		})
	end
	if pages > 1 then -- (the page strip, under the buttons: arrows at its ends, the dots between, the one shown lit)
		Chili.Control:New({
			parent = upright.grid,
			x = 0, bottom = 0, width = "100%", height = dots,
			padding = { 0, 0, 0, 0 },
			drawcontrolv2 = true,
			DrawControl = function(obj)
				local s, gap = 8, 12
				local x0 = (obj.width - (upright.pages * s + (upright.pages - 1) * gap)) / 2
				local at = -upright.stripX / math.max(1, upright.pageSize)
				local cy = obj.height / 2
				gl.Texture(false)
				-- (a dark backing with cut corners, as the lobby's buttons: the dots and arrows lay bare on BAR's picture,
				-- its red and white under them; dev phone screenshot sideways 2026-11-18)
				local bx0, by0, bx1, by1, c = 2, 1, obj.width - 2, obj.height - 1, 5
				gl.Color(0, 0, 0, 0.55)
				gl.BeginEnd(GL.TRIANGLE_FAN, function()
					gl.Vertex(bx0 + c, by0)
					gl.Vertex(bx1 - c, by0)
					gl.Vertex(bx1, by0 + c)
					gl.Vertex(bx1, by1 - c)
					gl.Vertex(bx1 - c, by1)
					gl.Vertex(bx0 + c, by1)
					gl.Vertex(bx0, by1 - c)
					gl.Vertex(bx0, by0 + c)
				end)
				for p = 0, upright.pages - 1 do
					local lit = math.max(0, 1 - math.abs(at - p)) -- (lit as the strip passes it)
					gl.Color(1, 0.78 + 0.2 * (1 - lit), 0.25 + 0.75 * (1 - lit), 0.3 + 0.7 * lit)
					-- (round, a little wider than their 8 px slot, which stripPage's taps go by: squares read as specks)
					local cx, r = x0 + p * (s + gap) + s / 2, s * 0.65
					gl.BeginEnd(GL.TRIANGLE_FAN, function()
						gl.Vertex(cx, cy)
						for k = 0, 20 do
							local t = k * math.pi / 10
							gl.Vertex(cx + r * math.cos(t), cy + r * math.sin(t))
						end
					end)
				end
				local a = obj.height * 0.34 -- (the arrows, dim at the first and the last page)
				-- (solid triangles: drawn as 4 pixel lines they came out about 2 thin on the phone's GLES, faint marks at the
				-- strip's ends; dev phone screenshot 2026-11-17, as the dock's spectator arrows before them)
				for side = -1, 1, 2 do
					local to = upright.page + side
					gl.Color(1, 1, 1, (to >= 0 and to < upright.pages) and 0.8 or 0.18)
					local x = side < 0 and obj.height * 0.6 or obj.width - obj.height * 0.6
					gl.BeginEnd(GL.TRIANGLES, function()
						if upright.side then -- (pages one under the other: up at the left end, down at the right; Chili y down)
							gl.Vertex(x - a * 0.75, cy - side * a * 0.55)
							gl.Vertex(x, cy + side * a * 0.55)
							gl.Vertex(x + a * 0.75, cy - side * a * 0.55)
						else
							gl.Vertex(x - side * a * 0.55, cy - a * 0.75)
							gl.Vertex(x + side * a * 0.55, cy)
							gl.Vertex(x - side * a * 0.55, cy + a * 0.75)
						end
					end)
				end
				gl.Color(1, 1, 1, 1)
			end,
		})
		if not isSide then -- (sideways the column has no room in its strip: Chobby's own line stays hidden, as upright)
			upright.caching = Chili.Label:New({ -- (Chobby's caching words, mirrored: uprightMirror; at the strip's own y:
				-- with bottom = 0 they stood over the last row's first button)
				parent = upright.grid,
				x = dots * 1.2, y = rows * (GRID_ROW_H + GRID_GAP) - GRID_GAP, width = "38%", height = dots,
				autosize = false,
				caption = "",
				valign = "center",
				objectOverrideFont = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(1),
			})
		end
	end
	local font = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(3)
	upright.mirror = {}
	upright.stripX = -upright.page * upright.pageSize
	local w = isSide and colW - 2 * GRID_GAP or (sw - (PAGE_COLS + 1) * GRID_GAP) / PAGE_COLS
	for i, f in ipairs(found) do
		local page, k = math.floor((i - 1) / perPage), (i - 1) % perPage
		local col, row = k % PAGE_COLS, math.floor(k / PAGE_COLS)
		local target = f.button
		local base, x, y
		if isSide then -- (one column; base: the button's y on the strip, its page under the one before)
			base = math.floor(page * sh + SIDE_STATUS_H + k * (GRID_ROW_H + GRID_GAP))
			x, y = GRID_GAP, base + upright.stripX
		else
			base = math.floor(page * sw + GRID_GAP + col * (w + GRID_GAP))
			x, y = base + upright.stripX, row * (GRID_ROW_H + GRID_GAP)
		end
		local mine = Chili.Button:New({
			parent = upright.grid,
			x = math.max(0, x), y = math.max(0, y), -- (a page before the one shown: placed below, stripPlace)
			width = math.floor(w), height = GRID_ROW_H,
			caption = target.caption,
			classname = target.classname == "negative_button" and "negative_button" or nil,
			objectOverrideFont = font,
			OnClick = { function() target:CallListeners(target.OnClick) end },
		})
		upright.mirror[#upright.mirror + 1] = { button = target, mine = mine, top = f.top, base = base }
		if (isSide and y or x) < 0 then
			stripPlace(mine, isSide and y or x)
		end
	end
	upright.grid:BringToFront()
	local words = {}
	for i, f in ipairs(found) do
		words[i] = f.button.caption:gsub("\255...", "")
	end
	Spring.Echo(string.format("[bardroid-lobby] %s: %d buttons, %d a page, %d pages: %s", isSide and "column" or "grid", #found,
		perPage, pages, table.concat(words, " | "))) -- (tools)
end

-- a tap on the page strip (Chili's point): the page it asks for (an arrow: the next that way, a dot: its own), else nil
local function stripPage(hx, hy)
	local g = upright.grid
	if not (g and upright.pages > 1) then
		return nil
	end
	local bottom = g.y + g.height - GRID_GAP
	if hy < bottom - GRID_DOTS_H - GRID_GAP or hy > g.y + g.height then
		return nil
	end
	local x = hx - g.x
	if x < g.width * 0.3 then
		return upright.page - 1
	elseif x > g.width * 0.7 then
		return upright.page + 1
	end
	local s, gap = 8, 12
	local x0 = (g.width - (upright.pages * s + (upright.pages - 1) * gap)) / 2
	return math.max(0, math.min(upright.pages - 1, math.floor((x - x0 + gap / 2) / (s + gap))))
end

-- The strip settled on a page (a short ease with a small overshoot, uprightAnimate)
local function uprightSettle(page)
	if not upright.grid then
		return
	end
	upright.page = math.max(0, math.min(upright.pages - 1, page))
	upright.anim = { from = upright.stripX, to = -upright.page * upright.pageSize, t = 0 }
	Spring.Echo("[bardroid-lobby] grid page " .. (upright.page + 1)) -- (tools)
end

local function uprightAnimate(dt)
	local a = upright.anim
	if not (a and upright.grid) or upright.grid.disposed then
		upright.anim = nil
		return
	end
	a.t = math.min(1, a.t + dt / PAGE_SETTLE)
	local t = a.t - 1
	local e = 1 + (PAGE_OVERSHOOT + 1) * t * t * t + PAGE_OVERSHOOT * t * t -- (easeOutBack)
	stripTo(a.from + (a.to - a.from) * e)
	if a.t >= 1 then
		upright.anim = nil
	end
end

-- is the point (Chili's) on the grid
local function onGrid(hit)
	local g = real(upright.grid)
	local obj = hit
	while obj and g do
		if real(obj) == g then
			return true
		end
		obj = obj.parent
	end
	return false
end

-- the grid's buttons as Chobby's are now: their words, and the colours that light the menu picked
local function uprightMirror()
	for _, m in ipairs(upright.mirror) do
		local b, mine = m.button, m.mine
		if type(b.caption) == "string" and mine.caption ~= b.caption then
			mine:SetCaption(b.caption)
		end
		if b.backgroundColor and mine.backgroundColor ~= b.backgroundColor then
			mine.backgroundColor, mine.focusColor = b.backgroundColor, b.focusColor
			mine:Invalidate()
		end
	end
	-- Chobby's caching line and version line (at the screen's foot, over the page strip) off; the caching words in the
	-- strip while they change (Chobby hides its line when it is done, which it cannot do once hidden here: words that
	-- stand 3 s are taken for done)
	local cl = real(chobbyObject("cachingLabel"))
	if cl then
		upright.labels = upright.labels or {}
		if upright.labels[cl] == nil then
			upright.labels[cl] = cl.visible ~= false
		end
		for _, c in ipairs(cl.parent and cl.parent.children or {}) do
			c = real(c)
			if upright.labels[c] == nil and type(c.caption) == "string" and c.caption:find("Engine: ", 1, true) then
				upright.labels[c] = c.visible ~= false
			end
		end
		for l in pairs(upright.labels) do
			if l.visible ~= false then
				l:SetVisibility(false)
			end
		end
		local text, t = type(cl.caption) == "string" and cl.caption or "", Spring.GetTimer()
		if upright.cachingText == nil then
			upright.cachingText = text -- (the words as first seen: not news)
		elseif text ~= upright.cachingText then
			upright.cachingText, upright.cachingAt = text, t
		end
		local show = upright.cachingAt and Spring.DiffTimers(t, upright.cachingAt) < 3 and text or ""
		local mine = upright.caching
		if mine and not mine.disposed and mine.caption ~= show then
			mine:SetCaption(show)
		end
	end
end

-- Chobby's own layout back: the grid or the column gone, Chobby's buttons, lines, scale and layout as they were
local function uprightOff()
	local config = WG.Chobby and WG.Chobby.Configuration
	for o in pairs(upright.sideHidden or {}) do -- (Chobby's logo and status line, hidden for the column)
		if not o.disposed then
			o:SetVisibility(true)
		end
	end
	upright.sideHidden, upright.status = nil, nil
	-- (the column's content windows where Chobby had them: its layout keeps a place it did not set, and a turn upright
	-- left the main window at the column's edge, the whole height, over the status line: dev phone, 2026-11-12)
	for o, was in pairs(upright.sideBounds or {}) do
		if not o.disposed then
			for k in pairs(o._relativeBounds) do
				o._relativeBounds[k] = nil
			end
			for k, v in pairs(was.rb) do
				o._relativeBounds[k] = v
			end
			o:SetPos(was.x, was.y)
			o:UpdateClientArea()
		end
	end
	upright.sideBounds = nil
	for o, was in pairs(upright.mapListSaved or {}) do -- (the map picker as Chobby laid it: uprightMapList)
		if not o.disposed then
			for k in pairs(o._relativeBounds) do
				o._relativeBounds[k] = nil
			end
			for k, v in pairs(was.rb) do
				o._relativeBounds[k] = v
			end
			for k in pairs(o._givenBounds) do
				o._givenBounds[k] = nil
			end
			for k, v in pairs(was.gb) do
				o._givenBounds[k] = v
			end
			o:SetPosRelative(was.x, was.y, was.w, was.h, nil, true) -- (the numbers only: the bounds are put back above)
			o:UpdateClientArea()
		end
	end
	upright.mapListSaved, upright.mapListDone = nil, nil
	if upright.grid then
		upright.grid:Dispose()
		upright.grid = nil
	end
	upright.anim = nil
	for _, m in ipairs(upright.mirror) do
		if m.button.visible == false then
			m.button:SetVisibility(true)
		end
	end
	upright.mirror = {}
	for l, was in pairs(upright.labels or {}) do -- (Chobby's foot lines back; the caching one only while it still runs)
		local caching = l.name == "cachingLabel"
		if was and not l.disposed and (not caching or (upright.cachingAt
			and Spring.DiffTimers(Spring.GetTimer(), upright.cachingAt) < 3)) then
			l:SetVisibility(true)
		end
	end
	upright.labels, upright.cachingText, upright.cachingAt = nil, nil, nil
	local column = chobbyObject("mainWindow_buttonsHolder")
	if column then
		column:SetVisibility(true)
	end
	if config and config.SetUiScale and upright.scaleBefore then
		config:SetUiScale(upright.scaleBefore)
		upright.scaleBefore = nil
	end
	local root = WG.Chobby and WG.Chobby.interfaceRoot
	if root and root.ViewResize then -- (Chobby's own layout back)
		pcall(root.ViewResize, screen0.width, screen0.height)
	end
end

-- BAR's loading screen tip at the next game's load, as the screen is shaped now: launch-bar.sh turns it off for an
-- upright start (BAR's line ran off both sides; the app shows its own), but a game started here loads in this engine,
-- after a turn of the phone too ("Turn with the phone"). Upright off, sideways the player's own setting (launch-bar.sh
-- keeps it in .bardroid-tips-line while it has it off). In memory only (an overlay): the file keeps launch-bar.sh's;
-- the player's value too, for a lobby loaded again after a game.
upright.tips = function(isUpright)
	if upright.tipsUpright == isUpright then
		return
	end
	local mine = Spring.GetConfigInt("bardroid_player_tips", -1)
	if mine < 0 then
		local f = io.open(".bardroid-tips-line", "r")
		local line = f and f:read("*a")
		if f then
			f:close()
		end
		mine = line and (tonumber(line:match("=%s*(%d+)")) or 1) or Spring.GetConfigInt("loadscreen_tips", 1)
		Spring.SetConfigInt("bardroid_player_tips", mine, true)
	end
	upright.tipsUpright = isUpright
	Spring.SetConfigInt("loadscreen_tips", isUpright and 0 or mine, true)
	Spring.Echo("[bardroid-lobby] loading screen tips at the next load: " .. ((isUpright or mine == 0) and "off" or "on")
		.. (isUpright and " (upright)" or ""))
end

-- on: the grid (upright) or the column (side: sideways) up; between the two (a turn of the phone) the one goes first
local function uprightSet(on, side)
	side = (on and side) and true or false
	if on == upright.on and side == upright.side then
		return
	end
	if upright.on then
		uprightOff()
	end
	upright.on, upright.side = on, side
	local config = WG.Chobby and WG.Chobby.Configuration
	if on and not side and config and config.SetUiScale and (config.uiScale or 1) < SCALE_UPRIGHT then
		upright.scaleBefore = config.uiScale or 1
		config:SetUiScale(SCALE_UPRIGHT)
	end -- (the grid at the next check: the screen at its new scale)
end

-- The battle room upright (Kailil, 2026-11-10: "the selectors in a row of their own ... the space under the team lists
-- stands empty"). Chobby's room (gui_battle_room_window.lua) is three columns side by side: the teams (playerPanel, to
-- 48 %), its buttons, selectors and states (leftInfo, 48-67 %) and the map with Start (rightInfo, from 67 %). Upright the
-- middle one is a sliver: "Update Rea", "BAR-31836-b..", a map's "...ownload failed [fa", the online room's Autobalance,
-- BalanceMode and Preset crushed, their labels over their values. Upright the teams keep the left's top half, the middle
-- column goes under them as wide as the left (60 %), the map and Start keep the right; both re-lay their own children as
-- they resize (their OnResize). Done once to each room's columns (a new room: new columns).
local roomsLaidOut = setmetatable({}, { __mode = "k" })

-- The room's buttons in the right column (Kailil, 2026-11-19, an online room on the Fold7: "There needs to be wayyyy
-- more space for the lobby special conditions and rules section (the section that says ranked = 1) ... there's a bunch
-- of free space on the right side. Can you move the buttons i circle to the right side?"): the middle column's
-- selectors and buttons (2 Teams, 1 per Team, Change Map, Adv Options, Option Presets) and its game and map lines under
-- the start boxes, the rules (Chobby's modoptions summary, modoptionsHolder) from the middle column's top, its whole
-- height; it was a strip of a line under them. Chobby's UpdateBattleMode lays those rows out again at each change (a
-- team count hidden, the download bar shown): their SetPos and the summary's take our places (Chili's own realigns pass
-- dontUpdateRelative and keep them). Chobby's rows and steps: gui_battle_room_window.lua SetupInfoButtonsPanel.
local ROOM_ROWS = { { "teamCountSelect", 38 }, { "teamSizeSelect", 38 }, { "btnPickMap", 38 },
	{ "btnModoptions", 38, "btnReloadModoptions" }, { "btnOptionPresets", 40 }, { "lblGame", 26 },
	{ "imHaveGame", 25, "lblHaveGame" }, { "imHaveMap", 30, "lblHaveMap" } }
local ROOM_LINES = 26 + 25 + 30 -- (lblGame's row to the summary's top in Chobby's layout)
local ROOM_PROGRESS = 35 -- (Chobby's INLINE_PROGRESS_REFLOW: its download bar's row over the summary)
local function roomButtonsRight(middle, right)
	local function childOf(parent, name)
		for _, ch in ipairs(parent.children or {}) do
			local c = real(ch)
			if c and c.name == name then
				return c
			end
		end
		for ch in pairs(parent.children_hidden or {}) do
			local c = real(ch)
			if c and c.name == name then
				return c
			end
		end
	end
	local st = { objs = {}, y = {}, orig = {} }
	local moved = {}
	for _, row in ipairs(ROOM_ROWS) do
		for i = 1, 3, 2 do
			local name = row[i]
			local o = name and childOf(middle, name)
			if o then
				st.objs[name] = o
				moved[#moved + 1] = o
			end
		end
	end
	local holder, sb = childOf(middle, "modoptionsHolder"), childOf(right, "startBoxPanel")
	local lblGame = st.objs.lblGame
	if not (holder and sb and lblGame and st.objs.btnPickMap) then
		return false
	end
	-- (not yet: a room just made, its columns not laid out by Chili, read "-58 free" there; uprightBattleRoom asks again)
	if not (right.clientArea and right.clientArea[4] > 300 and (sb.y or 0) > 50) then
		return false
	end
	st.chobbyTop = (lblGame.y or 0) + ROOM_LINES
	local inline = childOf(middle, "inlineProgressPanel")
	local downloader
	for _, ch in ipairs(middle.children or {}) do -- (Chobby's Downloader: the middle's other control, 120 high)
		local c = real(ch)
		if c and c ~= holder and c ~= inline and not st.objs[c.name] and c._givenBounds
			and c._givenBounds.height == 120 then
			downloader = c
		end
	end
	local busy = false
	local function stack()
		busy = true
		local y = (sb.y or 0) + (sb.height or 0) + 8
		-- (their room: down to the right column's own buttons at its foot, Playing to Start. A row past them waits out of
		-- sight, as while Android's keyboard is up and the screen shorter, and comes back when there is room)
		local foot = right.clientArea and right.clientArea[4] or right.height or 0
		for _, ch in ipairs(right.children or {}) do
			local c = real(ch)
			if c and c.visible ~= false and c ~= sb and not st.y[c] and not st.objs[c.name] and type(c.y) == "number"
				and c.y > y and c.name ~= "minimapPanel" and c.name ~= "lblMapName" then
				foot = math.min(foot, c.y)
			end
		end
		for _, row in ipairs(ROOM_ROWS) do
			local o = st.objs[row[1]]
			if o and o.visible ~= false then
				local at = y + row[2] - 3 <= foot - 4 and y or -10000
				st.y[o] = at
				local o2 = row[3] and st.objs[row[3]]
				if o2 then
					st.y[o2] = at
				end
				y = y + row[2]
			end
		end
		for o, oy in pairs(st.y) do
			if not o.disposed then
				st.orig[o](o, nil, oy)
			end
		end
		st.leftTop = (inline and inline.visible ~= false) and ROOM_PROGRESS or 0
		if inline and not inline.disposed and inline.y ~= 0 then
			st.orig[inline](inline, nil, 0)
		end
		if downloader and not downloader.disposed and downloader.y ~= st.leftTop then
			downloader:SetPos(nil, st.leftTop)
		end
		busy = false
	end
	local function take(o, place)
		st.orig[o] = o.SetPos
		o.SetPos = function(_, x, y, w, h, clientArea, dontUpdateRelative, ...)
			if type(y) == "number" and not dontUpdateRelative and not busy then
				y, h = place(y, h)
			end
			return st.orig[o](o, x, y, w, h, clientArea, dontUpdateRelative, ...)
		end
	end
	for _, o in ipairs(moved) do
		local hidden = o.visible == false
		if hidden then
			o:SetVisibility(true)
		end
		local ok = pcall(right.AddChild, right, o) -- (AddChild takes it from the middle)
		if hidden then
			o:SetVisibility(false)
		end
		if not ok then
			Spring.Echo("[bardroid-lobby] battle room upright: " .. tostring(o.name) .. " not moved")
		end
		take(o, function(y, h)
			if o == lblGame then -- (Chobby's rows laid out again: its summary's top follows its game line)
				st.chobbyTop = y + ROOM_LINES
			end
			stack()
			return st.y[o] or y, h
		end)
	end
	if inline then
		take(inline, function(_, h)
			return 0, h
		end)
	end
	take(holder, function(y, h) -- (Chobby's top, or 120 under it with the download list shown: from ours)
		local ny = (st.leftTop or 0) + math.max(0, y - st.chobbyTop)
		local ca = middle.clientArea
		return ny, (type(h) == "number" and ca) and math.max(10, ca[4] - ny) or h
	end)
	right.OnResize = right.OnResize or {}
	right.OnResize[#right.OnResize + 1] = function() -- (after Chobby's own: the start boxes where the map's size put them)
		stack()
	end
	stack()
	holder:SetPos(nil, holder.y, nil, holder.height)
	right:Invalidate()
	middle:Invalidate()
	return true
end

-- An online room's SPADS strip upright (gui_battle_room_window.lua SetupSpadsStatusPanel: Autobalance, BalanceMode
-- and Preset in a row, Balance, Lock and Unlock under them, in shares of a strip 96 high to 67 % of the room): it ran
-- under the right column's Playing and Ready, which start at 60 % ("custom" under Playing, Unlock under Ready's tick),
-- and each label under its own box ("Autobalancelvanced"; Kailil's screenshot, 2026-11-19). Upright the strip to 60 %
-- and half again as tall, in three rows: Autobalance and BalanceMode, Preset, the three buttons; the middle column
-- (the rules) ends above it. The vote panel in the same place to 60 % too.
local SPADS_H = 144
local spadsLaidOut = setmetatable({}, { __mode = "k" })
local function roomSpads(parent, middle)
	local function childOf(p, name)
		for _, ch in ipairs(p.children or {}) do
			local c = real(ch)
			if c and c.name == name then
				return c
			end
		end
		for ch in pairs(p.children_hidden or {}) do
			local c = real(ch)
			if c and c.name == name then
				return c
			end
		end
	end
	local spads = childOf(parent, "spadsStatusPanel")
	local mb = middle._relativeBounds
	if not (spads and spads._relativeBounds and spads._relativeBounds.right == "33%" and mb.bottom == 96) then
		return false -- (a skirmish: no strip, the middle to the room's foot)
	end
	local function rel(c, left, top, width, height)
		local r, g = c._relativeBounds, c._givenBounds
		r.left, g.left, r.top, g.top = left, left, top, top
		r.width, g.width, r.height, g.height = width, width, height, height
		r.right, g.right, r.bottom, g.bottom = false, false, false, false
		c._isRelative = true
	end
	local rows = { -- (each: its label's place, then its box's; a third of the strip high)
		{ "stslabel1", "autoBalance", "1%", "1%" }, { "stslabel2", "balanceMode", "51%", "1%" },
		{ "stslabel3", "preset", "1%", "34%" } }
	for _, r in ipairs(rows) do
		local label, box = childOf(spads, r[1]), childOf(spads, r[2])
		local x = tonumber((r[3]:gsub("%%", "")))
		if label then
			rel(label, r[3], r[4], "23%", "31%")
		end
		if box then
			rel(box, (x + 24) .. "%", r[4], "24%", "31%")
		end
	end
	for i, name in ipairs({ "balanceButton", "lockButton", "unlockButton" }) do
		local b = childOf(spads, name)
		if b then
			rel(b, ({ "1%", "34%", "67%" })[i] , "67%", "31%", "32%")
		end
	end
	spads._relativeBounds.right, spads._givenBounds.right = "40%", "40%"
	spads._givenBounds.height, spads.height = SPADS_H, SPADS_H
	spads._relativeBounds.height = false
	spads:UpdateClientArea()
	local vote = childOf(parent, "votePanel")
	if vote and vote._relativeBounds and vote._relativeBounds.right == "33%" then
		vote._relativeBounds.right, vote._givenBounds.right = "40%", "40%"
		vote:UpdateClientArea()
	end
	mb.bottom, middle._givenBounds.bottom = SPADS_H, SPADS_H
	middle:UpdateClientArea()
	for _, ch in ipairs(spads.children or {}) do -- (the children at their new shares)
		local c = real(ch)
		if c and c.UpdateClientArea then
			c:UpdateClientArea()
		end
	end
	return true
end

local function uprightBattleRoom()
	-- (Chili hands out weak links, a new one each time: the real objects, to compare and to remember)
	local players, middle, right = real(chobbyObject("playerPanel")), real(chobbyObject("leftInfo")),
		real(chobbyObject("rightInfo"))
	if not (players and middle and right) or middle.disposed
		or not (players._relativeBounds and middle._relativeBounds and right._relativeBounds)
		or real(players.parent) ~= real(middle.parent) or real(middle.parent) ~= real(right.parent) then
		return
	end
	-- (the buttons to the right once Chili has laid the new columns out: tried at the checks after, up to 5 s)
	local tries = roomsLaidOut[middle]
	if tries then
		if not spadsLaidOut[middle] then
			spadsLaidOut[middle] = true
			local ok, done = pcall(roomSpads, real(middle.parent), middle)
			if not ok or done then
				Spring.Echo("[bardroid-lobby] battle room upright: " .. (ok and "its SPADS strip in three rows, left of"
					.. " Playing and Ready" or ("its SPADS strip left as it was: " .. tostring(done)))) -- (tools)
			end
		end
		if tries >= 0 then
			local ok, moved = pcall(roomButtonsRight, middle, right)
			if not ok or moved or tries >= 10 then
				roomsLaidOut[middle] = -1
				Spring.Echo("[bardroid-lobby] battle room upright: " .. ((ok and moved)
					and "its buttons in the right column, the rules from the middle's top"
					or ("its buttons left in the middle: " .. tostring(ok and "no room laid out" or moved)))) -- (tools)
			else
				roomsLaidOut[middle] = tries + 1
			end
		end
		return
	end
	roomsLaidOut[middle] = 0
	local function bounds(o, left, top, rightEdge, bottom)
		o._givenBounds.left, o._givenBounds.top = left, top
		o._relativeBounds.left, o._relativeBounds.top = left, top
		o._relativeBounds.right, o._relativeBounds.bottom = rightEdge, bottom
		o._relativeBounds.width, o._relativeBounds.height = false, false
		o:UpdateClientArea()
	end
	bounds(players, "0%", "0%", "40%", "50%")
	bounds(middle, "0%", "50%", "40%", middle._relativeBounds.bottom or 0)
	bounds(right, "60%", "0%", 0, right._relativeBounds.bottom or 0)
	Spring.Echo("[bardroid-lobby] battle room upright: the teams over the middle column, the map beside them") -- (tools)
end

-- A scenario's page upright (Chobby's gui_scenario_window.lua, laid out in shares of its panel for a wide one): its
-- values 16 % in ran into their labels ("Est. Resource50K metal"), the loss condition over the map, "Personal Records"
-- cut at the panel's edge (dev phone, 2026-11-12). Upright the values from 24 % and 36 % wide, the map 40 % wide (from
-- 60 %), the records' column from 73 %, the picture and the briefing to 71 % (74 %: under the records' first letters).
-- Each pick of a scenario makes its page anew.
local scenariosLaidOut = setmetatable({}, { __mode = "k" })
local function uprightScenario()
	local mark -- (the page's "Est. Resources" label: new with each page)
	local function find(o, depth)
		if mark or not o or depth > 30 or o.visible == false then
			return
		end
		if o.caption == "Est. Resources" then
			mark = o
			return
		end
		for _, c in ipairs(o.children or {}) do
			find(c, depth + 1)
		end
	end
	find(real(chobbyObject("holder_mainWindow")), 0)
	mark = real(mark)
	local panel = mark and real(mark.parent)
	if not panel or scenariosLaidOut[mark] then
		return
	end
	scenariosLaidOut[mark] = true
	local function set(o, left, width, height)
		o._givenBounds.left, o._relativeBounds.left = left, left
		o._relativeBounds.width = width
		if height then
			o._relativeBounds.height = height
		end
		o:UpdateClientArea()
	end
	for _, c in ipairs(panel.children or {}) do
		local b = c._relativeBounds
		if b and b.left == "16%" and b.width == "50%" then
			set(c, "24%", "36%")
		elseif b and b.right == "0%" and b.width == "47%" and b.height == "47%" then -- (the map)
			c._relativeBounds.width, c._relativeBounds.height = "40%", "40%"
			c:UpdateClientArea()
		elseif b and b.left == "76%" and (b.width == "20%" or b.width == "25%") then -- (the records; Start keeps its place)
			set(c, "73%", "27%")
		elseif b and b.width == "74%" then -- (the picture and the briefing under it: to 71 %, clear of the records)
			c._relativeBounds.width = "71%"
			c:UpdateClientArea()
		end
	end
	-- (a value wider than the room left of the map ran on over it, "Loss of all your builders and factories", dev phone
	-- screenshot 2026-11-18: such a one in a smaller size of its font, as fits; the rows stand a line apart, no room for
	-- a second line)
	local map, config = nil, WG.Chobby and WG.Chobby.Configuration
	for _, ch in ipairs(panel.children or {}) do
		local c = real(ch)
		local b = c and c._relativeBounds
		if b and b.right == "0%" and b.width == "40%" then
			map = c
		end
	end
	local shrunk = 0
	for _, ch in ipairs(map and config and config.GetFont and panel.children or {}) do
		local c = real(ch)
		local b, f = c and c._relativeBounds, c and c.font
		if b and b.left == "24%" and type(c.caption) == "string" and f and f.GetTextWidth then
			local room, w = map.x - c.x - 24, f:GetTextWidth(c.caption) -- (24: 12 left it 5 pixels from the map)
			if room > 40 and w > room then
				local size = math.max(11, math.floor((f.size or 17) * room / w))
				local small = config:GetFont(size, "bardroidScenarioValue",
					{ font = f.font, shadow = f.shadow, outline = f.outline, outlineColor = f.outlineColor }, true)
				c.objectOverrideFont, c.font = small, small -- (Chobby's shared fonts: never disposed with a label)
				c:UpdateLayout()
				c:Invalidate()
				shrunk = shrunk + 1
			end
		end
	end
	Spring.Echo("[bardroid-lobby] scenario page upright: values clear of their labels, the map narrower"
		.. (shrunk > 0 and (", " .. shrunk .. " value(s) smaller to fit beside it") or "")) -- (tools)
end

-- Chobby's map picker upright (gui_maplist_panel.lua, a skirmish room's Change Map): laid out for a wide window, its
-- caption ("Select a Map. Certified maps are recommended.") ran under Manual Download, and the picked map's details,
-- beside the picture in a third of the width, ran on over Preview and Select Map (dev phone, 2026-11-13, Avalanche).
-- Upright the caption takes the width, the rest of the window a row lower; the details under the picture across the
-- panel, Preview and Select Map beside the picture under the map's name; the panel taller, the list under it lower.
-- Once each window (Chobby keeps the one it made); Chobby's places back for sideways (uprightOff).
-- (the panel 340: Avalanche's details and two lines of its description took to 300, dev phone; the picture 19 + 166)
local MAPLIST_DY, MAPLIST_PREVIEW_H, MAPLIST_PIC_BOTTOM = 26, 340, 185
local function uprightMapList()
	local cap = real(chobbyObject("captionHolder"))
	local win = cap and real(cap.parent)
	upright.mapListDone = upright.mapListDone or setmetatable({}, { __mode = "k" })
	if not win or win.disposed or win.visible == false or upright.mapListDone[win] then
		return
	end
	local function all(o) -- (a control's children, the hidden ones too: Select Map and Preview until a map is picked)
		local list = {}
		for _, c in ipairs(o.children or {}) do
			list[#list + 1] = real(c)
		end
		for c in pairs(o.children_hidden or {}) do
			list[#list + 1] = real(c)
		end
		return list
	end
	-- (Chili keeps a number's place in x, y, width, height and _givenBounds; only right and bottom anchors, and shares
	-- of the parent, in _relativeBounds: SetPosRelative moves the numbers)
	local preview
	for _, c in ipairs(all(win)) do
		if c.classname == "overlay_window" and type(c.y) == "number" and (not preview or c.y < preview.y) then
			preview = c -- (the top one: not a filter's list)
		end
	end
	local isPicker = false -- (Chobby's text entry popup has a captionHolder too)
	for _, c in ipairs(preview and all(preview) or {}) do
		isPicker = isPicker or c.caption == "Select Map"
	end
	if not (isPicker and preview._givenBounds and type(preview._givenBounds.height) == "number") then
		return
	end
	upright.mapListDone[win] = true
	upright.mapListSaved = upright.mapListSaved or setmetatable({}, { __mode = "k" })
	local saved = upright.mapListSaved
	local function set(o, x, y, h, anchors) -- (anchors: right / bottom; false drops one)
		if not saved[o] then
			local rb, gb = {}, {}
			for k, v in pairs(o._relativeBounds) do
				rb[k] = v
			end
			for k, v in pairs(o._givenBounds) do
				gb[k] = v
			end
			saved[o] = { rb = rb, gb = gb, x = o.x, y = o.y, w = o.width, h = o.height }
		end
		for k, v in pairs(anchors or {}) do
			o._relativeBounds[k], o._givenBounds[k] = v, v or nil
		end
		o:SetPosRelative(x, y, nil, h)
		o:UpdateClientArea()
	end
	local pTop, extra = preview.y, MAPLIST_PREVIEW_H - preview._givenBounds.height
	for _, c in ipairs(all(win)) do
		if c ~= cap and c ~= preview and type(c.y) == "number" and c._givenBounds and c._givenBounds.top then
			set(c, nil, c.y + MAPLIST_DY + (c.y > pTop and extra or 0))
		end
	end
	set(preview, nil, pTop + MAPLIST_DY, MAPLIST_PREVIEW_H)
	set(cap, nil, nil, nil, { right = 0 })
	for _, c in ipairs(all(preview)) do
		if c.classname == "textbox" then -- (the details: under the picture, across the panel)
			set(c, 10, MAPLIST_PIC_BOTTOM + 10, nil, { bottom = 10 })
		elseif c.caption == "Select Map" or c.caption == "Preview" then -- (beside the picture, at its foot)
			set(c, nil, MAPLIST_PIC_BOTTOM - 44, 44, { bottom = false })
		end
	end
	win:UpdateClientArea()
	Spring.Echo("[bardroid-lobby] map picker upright: the caption clear of Manual Download, the details under the picture") -- (tools)
end

-- Chobby's Keys window upright (gui_keys_panel.lua): its six tabs in one row, 180 each from 20, Close at the right:
-- upright Keys, CTRL Keys and half of ALT Keys under Close, the three Legacy ones out of reach (dev phone, 2026-11-12).
-- Upright two rows of three, as wide as the room left of Close, the keyboard picture under them. Laid again whenever
-- Chobby has moved them back (its holder's OnResize places the picture anew).
local KEYS_TABS = { "Keys", "CTRL Keys", "ALT Keys", "Legacy Keys", "Legacy CTRL Keys", "Legacy ALT Keys" }
local function uprightKeys()
	local holder = real(chobbyObject("buttonsHolder"))
	local win = holder and real(holder.parent)
	if not (win and not win.disposed and win.visible ~= false and (holder.width or 0) > 0) then
		return
	end
	local tabs, n = {}, 0
	for _, c in ipairs(holder.children or {}) do
		c = real(c)
		for i, cap in ipairs(KEYS_TABS) do
			if c.caption == cap then
				tabs[i], n = c, n + 1
			end
		end
	end
	if n ~= #KEYS_TABS then
		return
	end
	local x0, gap, h = 20, 6, 35
	local w = math.floor((holder.width - x0 - 2 * gap) / 3)
	if w >= 180 then -- (room for Chobby's one row)
		return
	end
	local moved = false
	for i, t in ipairs(tabs) do
		local x, y = x0 + ((i - 1) % 3) * (w + gap), 13 + math.floor((i - 1) / 3) * (h + 4)
		if t.x ~= x or t.y ~= y or t.width ~= w then
			t:SetPos(x, y, w, h)
			moved = true
		end
	end
	-- (the picture's box as tall as the picture at that width: Chili centres a kept-aspect picture in its box, and in the
	-- tall window it stood mid-screen, ~800 pixels under the tabs; its size known once Chili has loaded it)
	local top = 13 + 2 * h + 4 + 6
	local fitTo -- (the picture's foot, its size known)
	for _, c in ipairs(win.children or {}) do
		c = real(c)
		if c.name == "imKeys" then
			local iw, ih = win.width - 20, win.height - top - 10
			local ok, info = pcall(gl.TextureInfo, c.file)
			if ok and type(info) == "table" and (info.xsize or 0) > 0 and (info.ysize or 0) > 0 then
				ih = math.min(ih, math.ceil(iw * info.ysize / info.xsize))
				fitTo = top + ih
			end
			if c.y ~= top or c.x ~= 1 or math.abs((c.width or 0) - iw) > 1 or math.abs((c.height or 0) - ih) > 1 then
				c:SetPos(1, top, iw, ih)
				moved = true
			end
		end
	end
	-- (and the window as tall as its tabs and the picture, in the middle of the screen: Chobby's is the screen's height
	-- less 100, two thirds of it empty under the picture upright, dev phone screenshot 2026-11-18)
	local parent = real(win.parent)
	if fitTo and parent and (parent.height or 0) > 0 then
		local want = fitTo + 14 + (win.height - (win.clientHeight or win.height))
		local y = math.floor((parent.height - want) / 2)
		if want < win.height - 40 or (math.abs(win.height - want) <= 1 and win.y ~= y) then
			win:SetPos(win.x, y, win.width, want)
			moved = true
		end
	end
	if moved then
		Spring.Echo("[bardroid-lobby] Keys window upright: its tabs in two rows of three") -- (tools)
	end
end

-- Chobby's Plugins (chobby/components/plugins_window.lua): Contribute, Refresh, Update All and the search box 28 high,
-- the page arrows 40 x 30, fonts of 12 and 13 whatever the lobby's scale: too small for a finger (dev phone upright,
-- 2026-11-16, about 3 mm tall). Its header and page rows have the room (the rows 48 and 40 high, the list placed below
-- them by constants): the buttons and the box 40 high, the arrows 52 x 40, their words larger, nothing else moved.
-- Asked every half second (the window's own children only): a control already sized no longer matches, and the
-- arrows wait for the window's width (found before its first layout sideways, they were left small).
function upright.pluginButtons(win)
	if not win or win.disposed then
		return
	end
	local function bigger(c, size)
		local f = c.font
		if f and f.SetSize then
			pcall(f.SetSize, f, size)
		end
	end
	local resized = 0
	local pw = win.clientWidth or win.width or 0
	-- (the arrows at their new places: SetPos takes them absolute and works their right anchors out from them)
	local arrowX = { ["<<"] = 0, ["<"] = 60, [">"] = pw - 112, [">>"] = pw - 52 }
	for _, ch in ipairs(win.children or {}) do
		local c = real(ch)
		local cls = c and tostring(c.classname or "")
		if c and c.height == 28 and (cls:find("button") or cls == "editbox") then -- (the header row's four)
			c:SetPos(nil, nil, nil, 40)
			bigger(c, 15)
			resized = resized + 1
		elseif c and c.height == 30 and c.width == 40 and arrowX[c.caption] and pw > 300 then -- (<< < > >>)
			c:SetPos(arrowX[c.caption], nil, 52, 40)
			bigger(c, 17)
			resized = resized + 1
		elseif c and c.height == 30 and c.classname == "label" and c.x == 96 and pw > 300 then -- (the page number)
			c:SetPos(120, nil, pw - 240, 40)
		end
	end
	if resized > 0 then
		Spring.Echo("[bardroid-lobby] Plugins: " .. resized .. " buttons sized for a finger") -- (tools)
	end
end

-- Chobby's Settings (gui_settings_window.lua): each tab a list of rows 36 apart, their checkboxes, sliders and lists 30
-- high, under 3 mm a row on a phone upright and 2 mm sideways (dev phone screenshots, 2026-11-16: thirty rows down the
-- screen, a 20 box a checkbox). Both ways up the rows SETTINGS_ROW times as far apart and their controls as tall (a
-- checkbox's box with it), a row's words beside its control's middle as before (tall false puts Chobby's places back).
-- The tab shown only, asked every half second (Chobby builds the window when it is first opened, a tab's list when it
-- is first shown).
upright.SETTINGS_ROW = 1.5
function upright.settingsRows(tall)
	local win = real(chobbyObject("settingsWindow"))
	if not (win and not win.disposed and win.visible ~= false) then
		return
	end
	upright.settingsSaved = upright.settingsSaved or setmetatable({}, { __mode = "k" })
	local saved, f, moved = upright.settingsSaved, tall and upright.SETTINGS_ROW or 1, 0
	local function walk(o, depth)
		if not o or depth > 8 or o.disposed then
			return
		end
		for _, ch in ipairs(o.children or {}) do
			local c = real(ch)
			if c and c.classname == "scrollpanel" then
				for _, row in ipairs(c.children or {}) do
					local r = real(row)
					if r and type(r.y) == "number" and type(r.height) == "number" then
						local s = saved[r]
						if not s then
							s = { y = r.y, h = r.height, box = r.boxsize, ih = r.itemHeight, dh = r.maxDropDownHeight }
							saved[r] = s
						end
						if (s.f or 1) ~= f then
							s.f, moved = f, moved + 1
							-- (a row's words, 6 below its control's top in a box as tall: as far from its middle as before)
							local words = r.classname == "label"
							local y = words and math.floor((s.y - 6) * f + 15 * (f - 1) + 6) or math.floor(s.y * f)
							r:SetPos(nil, y, nil, words and s.h or math.floor(s.h * f))
							if s.box then
								-- (24: "Show Battles with Test Engine Versions" ran up to a 28 box, the words as wide as before)
								r.boxsize = f > 1 and math.min(24, math.floor(s.h * f) - 14) or s.box
								-- (and at 24 its last word still touched the box, dev phone screenshot 2026-11-19: a caption
								-- with under 12 before its box in a smaller size of its font, as fits; Chobby's back with
								-- the rows)
								local font, config = r.font, WG.Chobby and WG.Chobby.Configuration
								if s.font == nil then
									s.font, s.font0 = r.objectOverrideFont or false, font
								end
								if f > 1 and type(r.caption) == "string" and font and font.GetTextWidth and config
									and config.GetFont then
									local room, w = (r.width or 0) - r.boxsize - 12, font:GetTextWidth(r.caption)
									if room > 60 and w > room then
										local size = math.max(11, math.floor((font.size or 17) * room / w))
										local small = config:GetFont(size, "bardroidSettingsCaption",
											{ font = font.font, shadow = font.shadow, outline = font.outline,
												outlineColor = font.outlineColor }, true)
										r.objectOverrideFont, r.font = small, small -- (Chobby's shared fonts: never disposed with it)
									end
								elseif f == 1 and s.font0 and r.font ~= s.font0 then
									r.objectOverrideFont = s.font or nil
									r.font = s.font0
								end
								r:Invalidate()
							end
							-- (a list's choices, made as it opens: Chili's 20 high, about 1.6 mm, "Remember Last" over "Always
							-- Spectator"; 1.6 times, the drop-down as much taller, dev phone 2026-11-16)
							if r.classname == "combobox" and s.ih then
								r.itemHeight = f > 1 and math.floor(s.ih * 1.6) or s.ih
								r.maxDropDownHeight = s.dh and math.floor(s.dh * (f > 1 and 1.6 or 1)) or nil
							end
						end
					end
				end
			elseif c then
				walk(c, depth + 1)
			end
		end
	end
	walk(win, 0)
	if moved > 0 then
		Spring.Echo("[bardroid-lobby] Settings: " .. moved .. " rows " .. (f > 1 and "spaced for a finger" or "back")) -- (tools)
	end
end

-- Chobby's Links (helpsubmenuconfig.lua, "Community and development links"): its link buttons 34 high in rows 43 apart
-- (a SortableList), under 3 mm a button upright and the panel's lower third empty (dev phone, 2026-11-17). The rows as
-- much as SETTINGS_ROW times as far apart as the panel has room for (sideways it has less), their buttons as much
-- taller, each row's words beside its button's middle as before. The list puts its rows back when it resizes
-- (SortableList:RecalculatePosition): asked every half second, rows moved only where they are not in place.
function upright.linkRows()
	local mark
	local function find(o, depth)
		if mark or not o or depth > 14 or o.disposed or o.visible == false then
			return
		end
		if o.caption == "Community and development links" then
			mark = o
			return
		end
		for _, c in ipairs(o.children or {}) do
			find(real(c), depth + 1)
		end
	end
	for _, name in ipairs({ "holder_submenuWindow", "holder_mainWindow", "mainWindow_mainContent" }) do
		if not mark then
			find(real(chobbyObject(name)), 0)
		end
	end
	local panel = mark and real(mark.parent)
	local list
	local function findList(o, depth)
		if list or not o or depth > 6 then
			return
		end
		for _, ch in ipairs(o.children or {}) do
			local c = real(ch)
			if c and c.classname == "scrollpanel" then
				list = c
				return
			end
			findList(c, depth + 1)
		end
	end
	findList(panel, 0)
	if not list then
		return
	end
	upright.linkSaved = upright.linkSaved or setmetatable({}, { __mode = "k" })
	local saved, rows = upright.linkSaved, {}
	for _, ch in ipairs(list.children or {}) do
		local r = real(ch)
		if r and type(r.y) == "number" and type(r.height) == "number" then
			rows[#rows + 1] = r
		end
	end
	if #rows < 2 then
		return
	end
	table.sort(rows, function(a, b)
		return a.y < b.y
	end)
	local base = saved[list]
	if not base then -- (Chobby's spacing, as the list first stands)
		base = { step = rows[2].y - rows[1].y, h = rows[1].height, top = rows[1].y }
		saved[list] = base
	end
	local room = (list.clientHeight or list.height or 0) - 2 * base.top
	local f = math.max(1, math.min(upright.SETTINGS_ROW, room / (#rows * base.step)))
	local moved = 0
	for i, r in ipairs(rows) do
		local y, h = math.floor((i - 1) * base.step * f + base.top), math.floor(base.h * f)
		if r.y ~= y or r.height ~= h then
			r:SetPos(nil, y, nil, h)
			moved = moved + 1
		end
		local button
		for _, ch in ipairs(r.children or {}) do
			local c = real(ch)
			if c and not saved[c] then
				saved[c] = { y = c.y, h = c.height }
			end
			if c and c.classname == "option_button" then
				button = c
				local bh = math.floor(saved[c].h * f)
				if c.height ~= bh then
					c:SetPos(nil, nil, nil, bh)
				end
			end
		end
		for _, ch in ipairs(r.children or {}) do -- (the words: as far from the button's middle as before)
			local c = real(ch)
			if c and c ~= button and button and c.classname == "textbox" then
				local ty = math.floor(saved[c].y + (saved[button].h * f - saved[button].h) / 2)
				if c.y ~= ty then
					c:SetPos(nil, ty)
				end
			end
		end
	end
	if moved > 0 then
		Spring.Echo(string.format("[bardroid-lobby] Links: %d rows %s", moved, f > 1 and
			string.format("spaced %.2f times for a finger", f) or "as Chobby's")) -- (tools)
	end
end

-- A SortableList's rows for a finger (Downloads, Load Game): the list under the label captioned `caption` in the open
-- tab, each row SETTINGS_ROW times as tall and as far apart; place(c, s, grow, rowH, baseH) puts each control of a row
-- (s: its place as Chobby made it). The list puts its rows back when one is added or removed
-- (SortableList:RecalculatePosition): asked every half second, rows moved only where they are not in place. A list
-- longer than the panel scrolls further. tag names it in the log.
function upright.spaceListRows(caption, tag, place)
	local mark
	local function find(o, depth)
		if mark or not o or depth > 14 or o.disposed or o.visible == false then
			return
		end
		if o.classname == "label" and o.caption == caption then
			mark = o
			return
		end
		for _, c in ipairs(o.children or {}) do
			find(real(c), depth + 1)
		end
	end
	for _, name in ipairs({ "holder_submenuWindow", "holder_mainWindow", "mainWindow_mainContent" }) do
		if not mark then
			find(real(chobbyObject(name)), 0)
		end
	end
	local panel = mark and real(mark.parent)
	local list
	local function findList(o, depth)
		if list or not o or depth > 6 then
			return
		end
		for _, ch in ipairs(o.children or {}) do
			local c = real(ch)
			if c and c.classname == "scrollpanel" then
				list = c
				return
			end
			findList(c, depth + 1)
		end
	end
	findList(panel, 0)
	if not list then
		return
	end
	upright.rowsSaved = upright.rowsSaved or setmetatable({}, { __mode = "k" })
	local saved, rows = upright.rowsSaved, {}
	for _, ch in ipairs(list.children or {}) do
		local r = real(ch)
		if r and type(r.y) == "number" and type(r.height) == "number" then
			rows[#rows + 1] = r
		end
	end
	if #rows == 0 then
		return
	end
	table.sort(rows, function(a, b)
		return a.y < b.y
	end)
	local base = saved[list]
	if not base then -- (Chobby's spacing: the SortableList's row height, 3 between, from its first row)
		base = { step = #rows > 1 and rows[2].y - rows[1].y or rows[1].height + 3, h = rows[1].height, top = rows[1].y }
		saved[list] = base
	end
	local f = upright.SETTINGS_ROW
	local grow = math.floor(base.h * f) - base.h
	local moved = 0
	for i, r in ipairs(rows) do
		local y, h = math.floor((i - 1) * base.step * f + base.top), base.h + grow
		if r.y ~= y or r.height ~= h then
			r:SetPos(nil, y, nil, h)
			moved = moved + 1
		end
		for _, ch in ipairs(r.children or {}) do
			local c = real(ch)
			if c then
				if not saved[c] then
					saved[c] = { y = c.y, h = c.height }
				end
				place(c, saved[c], grow, h, base.h)
			end
		end
	end
	if moved > 0 then
		Spring.Echo(string.format("[bardroid-lobby] %s: %d rows spaced %.2f times for a finger", tag, moved, f)) -- (tools)
	end
end
-- a row's control down by half the row's growth (its middle stays the row's)
function upright.rowMiddle(c, s, grow)
	local ty = s.y + math.floor(grow / 2)
	if c.y ~= ty then
		c:SetPos(nil, ty)
	end
end

-- Chobby's Downloads (gui_download_window.lua): a SortableList of rows 40 high, 43 apart, their Retry, Cancel and To
-- Front buttons 34 high (y 3, bottom 3) and the name and status 20 high from y 12; sideways about 1.8 mm a button
-- (dev phone, the failed downloads of a phone with no network, 2026-11-17). Its buttons and progress bar grow with the
-- row (held to its top and bottom), its words go to the row's middle.
function upright.downloadRows()
	upright.spaceListRows("Downloads", "Downloads", function(c, s, grow)
		if c.classname == "textbox" then
			upright.rowMiddle(c, s, grow)
		end
	end)
end

-- Chobby's Load Game (gui_loadgame.lua): rows 80 high, Load (y 3) above Delete (bottom 4) at the row's end, each 65 x 35
-- with 3 pixels between them (dev phone sideways, 2026-11-17; Delete asks first, Load does not). Each row 1.5 times
-- as tall: Load and Delete as much taller at its top and bottom, now well apart; the map's picture and the words in the
-- row's middle.
function upright.saveRows()
	local caption = "Load saved game"
	if type(i18n) == "function" then -- (Chobby's words in the lobby's language)
		local ok, words = pcall(i18n, "load_saved_game")
		caption = ok and type(words) == "string" and words or caption
	end
	local f = upright.SETTINGS_ROW
	upright.spaceListRows(caption, "Load Game", function(c, s, grow, rowH, baseH)
		if c.classname == "textbox" or c.name == "minimap" then
			upright.rowMiddle(c, s, grow)
		elseif (c.classname == "action_button" or c.classname == "negative_button") and s.h then
			local h = math.floor(s.h * f)
			local y = s.y < baseH / 2 and s.y or rowH - (baseH - s.y - s.h) - h -- (at the top, or at the bottom as before)
			if c.y ~= y or c.height ~= h then
				c:SetPos(nil, y, nil, h)
			end
		end
	end)
end

-- Chobby's server list (battle_list_window.lua MakeJoinBattle; Kailil, 2026-11-19, upright on the Fold7: "Can you remove
-- the padding when on the server browser so there's more room. Because the player numbers saying if its x/16 players
-- gets cut off"): a row's players right-aligned at its end, the average rank's icon at 90 % of the row and the lock at
-- 86 %: "16/16" ran over the icon. The list 2 from the window's left side (12) with 2 of padding (4), the rows' own 10
-- at each side 4; the icon and the lock just left of the widest count ("88/88") and the map's name up to them, wherever
-- the row's width puts them. Both ways up; each row once (Chobby makes rows as servers come).
function upright.serverRows()
	-- (its note over the empty list, "You are not connected to the server.\nPlease wait 30 seconds while we
	-- automatically reconnect you.", in a box 70 % of the list wide: upright both lines cut at both ends, "re not
	-- connected to the server", dev phone 2026-11-19; the box 94 % wide. Chobby makes the list once: found, done)
	-- (the searches of the whole lobby only for a few seconds after a press, when a tab may have opened, tabWake: they
	-- ran every check, the list never opened; review 2026-11-19)
	local now = Spring.GetTimer()
	local woke = tabWake.at and Spring.DiffTimers(now, tabWake.at) < 4
	local info = upright.serverInfo
	if woke and not (info and not info.disposed) and (not upright.serverInfoAt
		or Spring.DiffTimers(now, upright.serverInfoAt) > 2) then
		upright.serverInfoAt = Spring.GetTimer()
		local function find(o, depth)
			for _, ch in ipairs(o.children or {}) do
				local c = real(ch)
				local b = c and c._relativeBounds
				if b and c.classname == "overlay_window" and b.left == "15%" and b.right == "15%" and b.top == "40%"
					and b.bottom == "40%" then
					return c
				end
				local r = c and depth < 9 and find(c, depth + 1)
				if r then
					return r
				end
			end
			for ch in pairs(o.children_hidden or {}) do
				local c = real(ch)
				local b = c and c._relativeBounds
				if b and c.classname == "overlay_window" and b.left == "15%" and b.right == "15%" and b.top == "40%"
					and b.bottom == "40%" then
					return c
				end
			end
		end
		info = find(real(screen0), 0)
		if info then
			upright.serverInfo = info
			info._relativeBounds.left, info._givenBounds.left = "3%", "3%"
			info._relativeBounds.right, info._givenBounds.right = "3%", "3%"
			info:UpdateClientArea()
			Spring.Echo("[bardroid-lobby] server list: its note over an empty list as wide as the list") -- (tools)
		end
	end
	-- (the list once found: its rows walked from it; Chobby keeps it for the session. Looked for again every check just
	-- after a press, else every 3 s: servers can come in after the list opened)
	local panel = upright.serverPanel
	if not (panel and not panel.disposed and panel.parent) then
		panel = nil
		if woke or not upright.serverLookAt or Spring.DiffTimers(now, upright.serverLookAt) > 3 then
			upright.serverLookAt = now
			local first = screen0.GetObjectByName and real(screen0:GetObjectByName("battleButton"))
			panel = first and battleIdOf(first) and real(scrollPanelOf(first))
			upright.serverPanel = panel or nil
		end
	end
	if not (panel and not panel.disposed and panel.visible ~= false and panel._relativeBounds)
		or (panel.IsVisibleOnScreen and not panel:IsVisibleOnScreen()) then -- (another tab in front: its rows wait)
		return
	end
	upright.serverDone = upright.serverDone or setmetatable({}, { __mode = "k" })
	local done = upright.serverDone
	if not done[panel] then
		done[panel] = true
		local rb, gb = panel._relativeBounds, panel._givenBounds
		-- (the right side's 12 and 4 kept: the lobby's frame covers the list's last 16 there, the counts' last digit cut)
		if gb.left == 12 and rb.right == 12 then -- (Chobby's ListWindow listPanel)
			panel.x, gb.left = 2, 2
			local p = panel.padding
			panel.padding = { 2, p and p[2] or 4, p and p[3] or 4, p and p[4] or 4 }
			panel:UpdateClientArea()
		end
	end
	local fixed = 0
	for _, row in ipairs(serverRows(panel)) do
		local b = real(row.button)
		if b and not done[b] then
			done[b] = true
			local p = b.padding
			if type(p) == "table" and (p[1] or 0) > 4 then
				b.padding = { 4, p[2], 4, p[4] }
			end
			local kids = {}
			for _, ch in ipairs(b.children or {}) do
				kids[#kids + 1] = real(ch)
			end
			for ch in pairs(b.children_hidden or {}) do
				kids[#kids + 1] = real(ch)
			end
			local count
			for _, c in ipairs(kids) do
				if c and c.name == "playersCaption" then
					count = c
				end
			end
			local f = count and count.font
			local w = f and f.GetTextWidth and f:GetTextWidth("88/88") or 44
			local r = math.ceil(w) + 4
			local function atRight(c, right, width)
				c._relativeBounds.left, c._givenBounds.left = false, false
				c._relativeBounds.right, c._givenBounds.right = right, right
				c._relativeBounds.width, c._givenBounds.width, c.width = false, width, width
				c._isRelative = true
			end
			for _, c in ipairs(kids) do
				if c and c._relativeBounds then
					if c.name == "imgAvgRank" then
						atRight(c, r, 20)
					elseif (c.name == "imgLocked" or c.name == "password") and c._relativeBounds.left == "86%" then
						atRight(c, r + 22, 20)
					elseif c.name == "mapCaption" then
						c._relativeBounds.right, c._givenBounds.right = r + 44, r + 44
					end
				end
			end
			b:UpdateClientArea()
			b:RequestRealign()
			fixed = fixed + 1
		end
	end
	if fixed > 0 and not upright.serverSaid then
		upright.serverSaid = true
		Spring.Echo("[bardroid-lobby] server list: less padding, the players' count clear of the rank icon") -- (tools)
	end
end

-- Chobby's Replays, each row's teams (gui_replay_handler.lua: a column a team from x 346, every 130 or so, each name 115
-- wide whatever the room): upright the second and third columns ran under Start and Delete, the names cut by them
-- ("SimpleA", "Inactive/"; dev phone upright, 2026-11-16). Where the columns do not fit the room the list gives them,
-- they share it evenly and the names are shortened to their column with Chobby's own ".." (its OnResize); back to
-- Chobby's places where they fit (sideways). Only the open Replays tab is walked (upright.replayPanel, replaysRowCheck).
function upright.replayTeams(panel)
	local prefix = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration.REPLAY_TOOLTIP_PREFIX
	if not (prefix and panel and not panel.disposed and panel.visible ~= false
		and (not panel.IsVisibleOnScreen or panel:IsVisibleOnScreen())) then
		return
	end
	upright.replayOrig = upright.replayOrig or setmetatable({}, { __mode = "k" })
	local orig = upright.replayOrig
	local lists = {}
	local function walk(o, depth)
		if not o or depth > 12 or o.disposed then
			return
		end
		for _, ch in ipairs(o.children or {}) do
			local c = real(ch)
			if c and c.greedyHitTest and type(c.tooltip) == "string" and c.tooltip:sub(1, #prefix) == prefix then
				lists[#lists + 1] = c
			elseif c and c.classname == "textbox" and type(c.text) == "string" and c.text:find(" minutes$") then
				-- (a row's length: Chobby writes "N minutes" and "N hour", "1 minutes" and "2 hour 5 minutes" in the list,
				-- dev phone 2026-11-17)
				local text = c.text:gsub("^(%d+) hour ", function(h)
					return h .. (h == "1" and " hour " or " hours ")
				end):gsub("%f[%d]1 minutes$", "1 minute")
				if text ~= c.text then
					c:SetText(text)
				end
			elseif c and c.classname == "textbox" and c.text == "time unknown" then
				-- (a replay whose length Chobby could not read: under its date and time "time unknown" read as the time
				-- of day unknown; dev phone screenshot 2026-11-19)
				c:SetText("length unknown")
			elseif c then
				walk(c, depth + 1)
			end
		end
	end
	walk(panel, 0)
	local fitted = 0
	for _, u in ipairs(lists) do
		-- (the list's top edge 4 higher, its contents where they were: the team headers stand at its top and their
		-- capitals' tops were cut, "Ieam 1" upright)
		if not u.bardroidLifted and (u.y or 0) >= 4 then
			u.bardroidLifted = true
			u:SetPos(nil, u.y - 4, nil, (u.height or 0) + 4)
			for _, ch in ipairs(u.children or {}) do
				local c = real(ch)
				if c then
					c:SetPos(nil, (c.y or 0) + 4)
				end
			end
		end
		local room = u.clientWidth or u.width or 0
		if room > 50 and u.bardroidRoom ~= room then
			u.bardroidRoom = room
			local cols, maxX = {}, 0
			for _, ch in ipairs(u.children or {}) do
				local c = real(ch)
				if c then
					orig[c] = orig[c] or c.x
					cols[orig[c]] = true
					maxX = math.max(maxX, orig[c])
				end
			end
			local n = 0
			for _ in pairs(cols) do
				n = n + 1
			end
			local fits = maxX + 18 + 115 <= room
			local f = (fits or maxX <= 0) and 1 or (room - room / n) / maxX -- (the last column's start at room - room / n)
			local nameW = fits and 115 or math.max(30, math.floor(room / n) - 18 - 6)
			for _, ch in ipairs(u.children or {}) do
				local c = real(ch)
				local x = c and math.floor(orig[c] * f)
				if c and (c.x ~= x or c.x + (c.width or 0) ~= room) then
					c:SetPos(x, nil, math.max(10, room - x)) -- (to the list's right edge, as Chobby's right = 0: moved alone
					-- it kept its width, and a moved column's box cut its name short)
				end
				local name = c and c.GetChildByName and c:GetChildByName("userName")
				if name and name.width ~= nameW then
					-- (shortened here: its own OnResize ran before a moved column's new width, and the name wrapped,
					-- its second line hidden: "SimpleA", no "..")
					orig[name] = orig[name] or name.text or ""
					name:SetPos(nil, nil, nameW)
					local text, font = orig[name], name.font
					if font and font.GetTextWidth and font:GetTextWidth(text) > nameW - 2 then
						local i = #text - 1
						while i > 1 and font:GetTextWidth(text:sub(1, i) .. "..") > nameW - 2 do
							i = i - 1
						end
						text = text:sub(1, i) .. ".."
					end
					name:SetText(text)
				end
			end
			fitted = fitted + (fits and 0 or 1)
		end
	end
	if fitted > 0 then
		Spring.Echo("[bardroid-lobby] Replays upright: " .. fitted .. " rows' teams fitted to their room") -- (tools)
	end
end

-- Chobby's quick Skirmish, its last page, Select Map (gui_battle_room_window.lua's simple skirmish): four minimaps a
-- quarter of the panel wide, each map's name only in a hover tooltip, which a finger never brings up, and nothing said
-- which are downloaded (dev phone upright, 2026-11-16: four small unnamed squares; offline a tap on one not downloaded
-- started its download, "Download Failed", Start waiting on it). Each map's name under its picture, "not downloaded"
-- under that while it is not, both ways up; upright the four in two columns across the panel, larger. Chobby's places
-- kept, and put back sideways. A new game type makes the page's buttons anew.
-- Chobby's place of a control before the first move (upright.quickSaved: quickMaps puts them all back sideways)
function upright.quickKeep(o)
	local saved = upright.quickSaved
	if not saved[o] then
		local rb, gb = {}, {}
		for k, v in pairs(o._relativeBounds or {}) do
			rb[k] = v
		end
		for k, v in pairs(o._givenBounds or {}) do
			gb[k] = v
		end
		saved[o] = { rb = rb, gb = gb, x = o.x, y = o.y, w = o.width, h = o.height }
	end
end
-- Back and Advanced at a page's foot as tall as Next between them: Chobby's 48 beside Next's own height, 68 pixels on
-- the dev phone upright, under Android's 48 dp for a finger (dev phone screenshot 2026-11-18); put back sideways with
-- the rest (quickMaps). Grown upwards from Chobby's own foot (4 % of the panel from its bottom, as Next's): Next's y is
-- not to be had while it is hidden, as Start is on Select Map until a map is picked: there the two went to the
-- panel's top and the maps' room shrank to nothing (dev phone, 2026-11-18)
function upright.quickFoot(panel)
	local nextB = panel and panel.GetChildByName and real(panel:GetChildByName("nextButton"))
	local ph = panel and (panel.clientHeight or panel.height) or 0
	if not (nextB and not nextB.disposed and ph > 0) then
		return
	end
	local bottom = ph - math.floor(ph * 0.04)
	for _, name in ipairs({ "prevPage", "advButton" }) do
		local c = real(panel:GetChildByName(name))
		local was = c and upright.quickSaved[c]
		local h = nextB.height
		if c and not c.disposed and h > (was and was.h or c.height) and h < ph * 0.2
			and (c.height ~= h or c.y ~= bottom - h) then
			upright.quickKeep(c)
			c:SetPos(c.x, bottom - h, c.width, h)
		end
	end
end
function upright.quickMaps(tall)
	upright.quickSaved = upright.quickSaved or setmetatable({}, { __mode = "k" })
	upright.quickLabels = upright.quickLabels or setmetatable({}, { __mode = "k" })
	local saved, labels = upright.quickSaved, upright.quickLabels
	local found = {}
	local function walk(o, depth)
		if not o or depth > 25 or o.disposed or o.visible == false then
			return
		end
		for _, ch in ipairs(o.children or {}) do
			local c = real(ch)
			local p = c and real(c.parent)
			if c and c.classname == "button_simple" and type(c.tooltip) == "string"
				and c.tooltip:sub(1, 16) == "minimap_tooltip_" and p and p.GetChildByName and p:GetChildByName("titleLabel") then
				found[#found + 1] = c
			elseif c then
				walk(c, depth + 1)
			end
		end
	end
	for _, name in ipairs({ "holder_mainWindow", "mainWindow_mainContent", "holder_submenuWindow" }) do
		if #found == 0 then
			walk(real(chobbyObject(name)), 0)
		end
	end
	local config = WG.Chobby and WG.Chobby.Configuration
	local font = config and config:GetFont(1)
	local labelH = math.floor(((font and font.size) or 16) * 2.4) + 4
	local keep = upright.quickKeep
	local panel
	for i, b in ipairs(found) do
		local name = b.tooltip:sub(17):match("^(.-)|") or b.tooltip:sub(17)
		local have = VFS.HasArchive(name)
		local caption = name .. (have and "" or "\n\255\160\160\160not downloaded")
		local label = labels[b]
		if not label or label.disposed then
			-- (over the picture's foot, the picture left as Chobby made it: a picture shortened for the label's room drew
			-- nothing, three of four blank, dev phone 2026-11-16)
			label = Chili.Label:New({ -- (at the left: centred, its two lines drifted right, the colour code counted in)
				x = 8,
				right = 4,
				bottom = 0,
				height = labelH,
				align = "left",
				valign = "center",
				caption = caption,
				objectOverrideFont = font,
				parent = b,
			})
			label:BringToFront() -- (Chili draws a child added last first: under the picture, its name hidden)
			labels[b] = label
		elseif label.caption ~= caption then -- (downloaded since)
			label:SetCaption(caption)
		end
		panel = panel or real(b.parent)
		if tall and panel then
			keep(b)
			local w = panel.clientWidth or panel.width or 0
			local colW, gapX = math.floor(w * 0.44), math.floor(w * 0.04)
			local h = math.floor(colW * 0.92) + labelH -- (a square map whole at the column's width)
			local y0 = saved[found[1]] and saved[found[1]].y or b.y
			-- (and both rows above the hint and the buttons at the panel's foot: on a near-square screen, 1080x1198 as the
			-- unfolded Fold7, the second row ran under Back and Advanced and off the panel; dev phone 2026-11-16)
			local adv = panel:GetChildByName("advButton")
			local foot = (adv and adv.y or math.floor((panel.clientHeight or panel.height or 0) * 0.9)) - 70
			h = math.max(labelH + 40, math.min(h, math.floor((foot - y0 - 16) / 2)))
			local x = gapX + ((i - 1) % 2) * (colW + gapX)
			local y = y0 + math.floor((i - 1) / 2) * (h + 16)
			if b.x ~= x or b.y ~= y or b.width ~= colW or b.height ~= h then
				b:SetPos(x, y, colW, h)
			end
			local tip = panel:GetChildByName("tipTextBox")
			if tip and i == #found then
				keep(tip)
				local ty = y + h + 24
				if tip.y ~= ty then
					tip:SetPos(nil, ty)
				end
			end
		end
	end
	if tall and panel then
		upright.quickFoot(panel)
	end
	if not tall then -- (sideways: Chobby's places back)
		for o, was in pairs(saved) do
			if not o.disposed then
				for k in pairs(o._relativeBounds) do
					o._relativeBounds[k] = nil
				end
				for k, v in pairs(was.rb) do
					o._relativeBounds[k] = v
				end
				for k in pairs(o._givenBounds) do
					o._givenBounds[k] = nil
				end
				for k, v in pairs(was.gb) do
					o._givenBounds[k] = v
				end
				o:SetPosRelative(was.x, was.y, was.w, was.h, nil, true)
				o:UpdateClientArea()
			end
			saved[o] = nil
		end
	end
	if #found > 0 and upright.quickSeen ~= found[1] then -- (tools)
		upright.quickSeen = found[1]
		Spring.Echo("[bardroid-lobby] quick skirmish maps named" .. (tall and ", two columns across the panel" or ""))
	end
end

-- The quick Skirmish's pages with a picture (Select Game Type, the difficulty, the faction): laid out for a wide panel,
-- the picture in its left half, the buttons in its right; upright the picture a sliver cut from the middle of its 16:9
-- and the right column empty under the buttons for most of the panel (dev phone, 2026-11-17). Upright the picture across
-- the panel at its own 16:9 (shorter where the panel is), the buttons under it as wide. After quickMaps, which puts
-- Chobby's places back sideways.
function upright.quickPages(tall)
	local saved = upright.quickSaved
	if not (tall and saved) then
		return
	end
	local pictures = {}
	local function walk(o, depth)
		if not o or depth > 25 or o.disposed or o.visible == false then
			return
		end
		for _, ch in ipairs(o.children or {}) do
			local c = real(ch)
			if c and c.name == "skirmishPreviewPanel" then
				pictures[#pictures + 1] = c
			elseif c then
				walk(c, depth + 1)
			end
		end
	end
	for _, name in ipairs({ "holder_mainWindow", "mainWindow_mainContent", "holder_submenuWindow" }) do
		if #pictures == 0 then
			walk(real(chobbyObject(name)), 0)
		end
	end
	local keep = upright.quickKeep
	for _, pic in ipairs(pictures) do
		local panel = real(pic.parent)
		local w = panel and (panel.clientWidth or panel.width) or 0
		upright.quickFoot(panel)
		local buttons = {}
		for _, ch in ipairs(panel and panel.children or {}) do -- (the page's own: Chobby puts them at 52 % across)
			local c = real(ch)
			local rb = c and (saved[c] and saved[c].rb or c._relativeBounds)
			if c and c.classname == "button_simple" and rb and rb.left == "52%" then
				buttons[#buttons + 1] = c
			end
		end
		local function y0of(o)
			return saved[o] and saved[o].y or o.y
		end
		table.sort(buttons, function(a, b)
			return y0of(a) < y0of(b)
		end)
		local n = #buttons
		if w > 0 and n > 0 then
			local bh = saved[buttons[1]] and saved[buttons[1]].h or buttons[1].height
			local gap, x0, pw, top = 14, math.floor(w * 0.04), math.floor(w * 0.92), y0of(pic)
			local adv = panel:GetChildByName("advButton")
			local foot = (adv and adv.y or math.floor((panel.clientHeight or panel.height or 0) * 0.9)) - 24
			local ph = math.min(math.floor(pw * 9 / 16), foot - top - 16 - n * (bh + gap))
			if ph >= math.floor(pw * 0.3) then -- (no room for a picture worth the name: Chobby's layout stays)
				keep(pic)
				if pic.x ~= x0 or pic.y ~= top or pic.width ~= pw or pic.height ~= ph then
					pic:SetPos(x0, top, pw, ph)
				end
				for i, b in ipairs(buttons) do
					keep(b)
					local y = top + ph + 16 + (i - 1) * (bh + gap)
					if b.x ~= x0 or b.y ~= y or b.width ~= pw or b.height ~= bh then
						b:SetPos(x0, y, pw, bh)
					end
				end
				local tip = panel:GetChildByName("tipTextBox")
				if tip then
					keep(tip)
					local ty = top + ph + 16 + n * (bh + gap) + 8
					if tip.y ~= ty then
						tip:SetPos(nil, ty)
					end
				end
				if upright.pagesSeen ~= pic then -- (tools)
					upright.pagesSeen = pic
					Spring.Echo("[bardroid-lobby] quick skirmish page upright: the picture across, " .. n .. " buttons under it")
				end
			end
		end
	end
end

-- Chobby's notes (its Chotify: "Download Failed", downloads, invites) stack up from the screen's foot at its right,
-- over the grid's page strip and its right arrow upright (dev phone, 2026-11-10): upright they stack up from above the
-- grid, and the server bar while it is up; not upright, Chobby's own place
local function uprightNotes()
	local C = WG.Chotify -- (Chobby's api_chotify.lua)
	if upright.notesHooked or type(C) ~= "table" or type(C._Realign) ~= "function" then
		return
	end
	upright.notesHooked = true
	local own = C._Realign
	-- a note's words (its captions and texts), to tell a repeat: offline the Skirmish screen's map download failed three
	-- times, three "Download Failed: Special Creek 1.0" stacked over its Next button (dev phone, 2026-11-11)
	local function words(o, out, depth)
		if o and depth < 8 then
			local t = o.caption or o.text
			if type(t) == "string" and t ~= "" then
				out[#out + 1] = t
			end
			for _, c in ipairs(o.children or {}) do
				words(c, out, depth + 1)
			end
		end
		return out
	end
	-- (one "Download Failed" note at a time, whichever map: with no network every map the lobby asks for fails in turn,
	-- three notes stacked over the map picker's caption and picture, dev phone 2026-11-13; the rest as repeats)
	local function noteKey(n)
		local key = table.concat(words(n.window, {}, 0), "|")
		return key:find("^Download Failed") and "Download Failed" or key
	end
	C._Realign = function(self, sorted)
		local col = upright.on and upright.side and real(upright.grid)
		if col and not col.disposed then
			-- Sideways beside the column: repeats out of sight too, the rest from the top down over the middle of the screen
			-- beside the column (at Chobby's place, its foot at the right, two "Download Failed: All That Simmers" covered
			-- the Skirmish screen's Advanced, dev phone 2026-11-12; at the top a screen's title is hidden a few seconds)
			local seen, row = {}, 0
			for _, n in pairs(sorted) do
				local key = noteKey(n)
				local win = n.window
				if key ~= "" and seen[key] then
					win:SetPos(nil, -4000)
				else
					seen[key] = true
					row = row + 1
					-- (at three quarters of the room beside the column, short of the panels' Close: in its middle it covered the
					-- Skirmish steps' centred titles, "Select Game Type" under "Download Failed", dev phone 2026-11-18)
					local x = col.width + math.floor((screen0.width - col.width) * 0.75 - win.width / 2)
					x = math.max(col.width + 4, math.min(x, screen0.width - win.width - 140))
					win:SetPos(x, 6 + (row - 1) * 110)
				end
			end
			return
		end
		local g = upright.on and real(upright.grid)
		if not (g and not g.disposed) then
			return own(self, sorted)
		end
		-- (from the screen's top down, over the logo's strip: above the grid they covered the screens' own buttons along
		-- the panel's foot, Next and all of Advanced on the Skirmish screens, dev phone 2026-11-11)
		-- (at its left, over the logo, as wide as the room before the connection state: at Chobby's right a "Download
		-- Failed" note covered "Offline", the reason it failed, dev phone 2026-11-11; no room for 150: Chobby's right)
		local room
		local state = real(chobbyObject("connectivityText"))
		local box = state and real(state.parent)
		if box and box.LocalToScreen then
			local bx = box:LocalToScreen(0, 0)
			room = bx and bx - 8
		end
		local seen, row = {}, 0
		for _, n in pairs(sorted) do
			local key = noteKey(n)
			if key ~= "" and seen[key] then
				if n.window.y ~= -4000 then
					Spring.Echo("[bardroid-lobby] a repeated note out of sight: " .. key:sub(1, 60)) -- (tools)
				end
				n.window:SetPos(nil, -4000) -- (a repeat: out of sight, it times out as Chobby's own)
			else
				seen[key] = true
				row = row + 1
				local win = n.window
				win.bardroidW = win.bardroidW or win.width
				if room and room >= 150 then
					-- (as wide as that room, up to 1.4 times Chobby's: at Chobby's width "Download Failed / Red Comet Remake
					-- 1.8 of type" broke "map" onto a line of its own with ~80 pixels left before "Offline", dev phone
					-- upright 2026-11-16)
					win:SetPos(2, 6 + (row - 1) * 110, math.min(math.floor(win.bardroidW * 1.4), room))
				else
					win:SetPos(nil, 6 + (row - 1) * 110)
				end
			end
		end
	end
	Spring.Echo("[bardroid-lobby] Chobby's notes above the grid upright") -- (tools)
end

-- Upright, controls Chobby lays out by the panel's width (its Settings' sliders and dropdowns at "55%" to the right
-- edge) came up blank when a screen opened: their size right, their picture the one drawn before they had it
-- (dev phone, 2026-11-10: Settings' sliders, its dropdowns' boxes; a redraw brought them). When what the content shows
-- changes (a screen or a tab opened: its visible controls counted), it is drawn again, then once more a check later.
local function contentCount()
	local n = 0
	local function walk(o, depth)
		if not o or depth > 40 or o.visible == false then
			return
		end
		n = n + 1
		for _, c in ipairs(o.children or {}) do
			walk(c, depth + 1)
		end
	end
	walk(real(chobbyObject("mainWindow_mainContent")), 0)
	walk(real(chobbyObject("holder_submenuWindow")), 0)
	return n
end
local function redrawContent()
	local function walk(o, depth)
		if not o or depth > 40 then
			return
		end
		if o.Invalidate then
			o:Invalidate()
		end
		for _, c in ipairs(o.children or {}) do
			walk(c, depth + 1)
		end
	end
	walk(real(chobbyObject("mainWindow_mainContent")), 0)
	walk(real(chobbyObject("holder_submenuWindow")), 0)
end
-- Chobby's modal popups (its PriorityPopup: the login dialog, confirmations) eat every tap outside them, and on the
-- near-square screen (the Fold7 unfolded upright) the login dialog is taller than the room above the grid: its
-- Login / Register and Cancel lay under the grid (dev phone, wm size 1080x1198, 2026-11-10). While one is open the grid
-- is hidden, the popup whole; it comes back as the popup goes.
-- A popup's text boxes (the login dialog's name, password and email) as wide as their row allows, upright and
-- sideways: Chobby sizes them for the desktop's window, upright a third of the window, a long email cut short beside
-- an empty half (dev phone screenshot, 2026-11-12). Each box once; its left edge where Chobby put it.
upright.widened = setmetatable({}, { __mode = "k" })
-- The login dialog's Login and Register tabs (Chobby's components/login_window.lua): rows 40 apart, the boxes 35 high,
-- under 3 mm a row upright with the dialog's lower half empty above its checkboxes (dev phone screenshot, 2026-11-18).
-- A panel's rows that hold a text box (the words beside it) and the lines just under them stand up to SETTINGS_ROW
-- times as far apart, as far as the room down to the panel's next control allows (Chobby's error line, the
-- checkboxes), the boxes as much taller up to 1.3 times; the rest where Chobby put it. Asked again with each check, from
-- the places Chobby gave (a turn: the room it has then). A panel with a button in the boxes' rows (Recover/Change) is
-- left as it is.
upright.formSaved, upright.formF = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
function upright.spreadForm(panel)
	local kids, boxes = {}, 0
	for _, ch in ipairs(panel.children or {}) do
		local c = real(ch)
		if c and not c.disposed and type(c.y) == "number" and type(c.height) == "number" then
			local s = upright.formSaved[c]
			if not s then
				s = { y = c.y, h = c.height }
				upright.formSaved[c] = s
			end
			kids[#kids + 1] = c
			boxes = boxes + (c.classname == "editbox" and 1 or 0)
		end
	end
	if boxes < 2 then
		return
	end
	local top, last = math.huge, -math.huge
	for _, c in ipairs(kids) do
		if c.classname == "editbox" then
			local s = upright.formSaved[c]
			top, last = math.min(top, s.y), math.max(last, s.y)
		end
	end
	local form, bottom, below = {}, top, panel.clientHeight or panel.height or math.huge
	for _, c in ipairs(kids) do
		local s = upright.formSaved[c]
		if s.y >= top - 12 and s.y <= last + 60 then
			if c.classname == "button" or c.classname == "checkbox" then
				return
			end
			form[#form + 1] = c
			bottom = math.max(bottom, s.y + math.min(s.h, 70)) -- (the Login tab's error box is 400 high, its words on top)
		elseif s.y > last + 60 and c.visible ~= false then
			below = math.min(below, s.y)
		end
	end
	local f = bottom > top and math.max(1, math.min(upright.SETTINGS_ROW, (below - 12 - top) / (bottom - top))) or 1
	if math.abs((upright.formF[panel] or 1) - f) < 0.02 then
		return
	end
	upright.formF[panel] = f
	local grow = math.min(f, 1.3)
	for _, c in ipairs(form) do
		local s = upright.formSaved[c]
		local y = top + (s.y - top) * f
		if c.classname == "editbox" then
			c:SetPos(nil, math.floor(y), nil, math.floor(s.h * grow))
		else -- (its words as far from the grown box's middle as before)
			c:SetPos(nil, math.floor(y + 35 * (grow - 1) / 2))
		end
	end
	Spring.Echo(string.format("[bardroid-lobby] a popup's %d form rows %.2f times as far apart", #form, f)) -- (tools)
end
function upright.widenInputs(win)
	local function walk(o, depth)
		if not o or depth > 12 or o.disposed then
			return
		end
		upright.spreadForm(o)
		for _, ch in ipairs(o.children or {}) do
			local c = real(ch)
			if c and c.classname == "editbox" and not upright.widened[c] and (c.width or 0) > 0 then
				-- (to the popup's right edge, whatever panel holds it: the Register tab's boxes sit in a panel as narrow
				-- as they are)
				local _, cx = pcall(function() return (c:LocalToScreen(0, 0)) end)
				local _, wx = pcall(function() return (win:LocalToScreen(0, 0)) end)
				local winW = win.clientWidth or win.width
				local want = type(cx) == "number" and type(wx) == "number" and winW
					and math.floor(wx + winW - winW * 0.05 - cx)
				upright.widened[c] = true
				-- (a button beside it in its row: up to that; Recover/Change's "Change Username" went over its button)
				for _, sib in ipairs(c.parent and c.parent.children or {}) do
					local s = real(sib)
					if want and s and s ~= c and s.x and s.y and s.height and s.x >= c.x + c.width - 1
						and s.y < c.y + c.height and s.y + s.height > c.y then
						want = math.min(want, s.x - c.x - 6)
					end
				end
				if want and want > c.width * 1.2 then
					local was = c.width
					local need, p = c.x + want, c.parent -- (its panels as wide, or the box is cut at their edge)
					while p and p ~= win and p.width and p.x do
						local inner = p.clientWidth or p.width
						if need <= inner then
							break
						end
						p:SetPos(nil, nil, math.floor(need + (p.width - inner) + 2))
						need, p = p.x + p.width, p.parent
					end
					c:SetPos(nil, nil, want)
					Spring.Echo(string.format("[bardroid-lobby] a popup's text box %d wide, now %d", was, want)) -- (tools)
				end
			elseif c and c.classname == "checkbox" and (c.boxsize or 0) < 22 and (c.height or 0) >= 32 then
				-- (and its checkboxes' boxes as tall as their row allows: the login dialog's Remember password and Login
				-- automatically drew a 15 box in a row 35 high, a speck beside the words, dev phone screenshot 2026-11-16;
				-- the whole row was always the tap's)
				c.boxsize = math.min(24, c.height - 8)
				c:Invalidate()
				Spring.Echo("[bardroid-lobby] a popup's checkbox box " .. c.boxsize) -- (tools)
			elseif c then
				walk(c, depth + 1)
			end
		end
	end
	walk(win, 0)
end

local function uprightModal()
	local g = real(upright.grid)
	if not (g and not g.disposed) then
		return
	end
	local C = WG.Chobby
	local ok, popups = pcall(function()
		return C and C.GetRegisteredPopups and C:GetRegisteredPopups()
	end)
	local modal = false
	for _, p in pairs(ok and type(popups) == "table" and popups or {}) do
		local w = p.mainWindow and real(p.mainWindow)
		if w and not w.disposed and w.visible ~= false then
			modal = true
			-- (sideways too: there the Register tab's boxes were 230 pixels in a 660 one, the rest of the row empty,
			-- dev phone screenshot 2026-11-13)
			upright.widenInputs(w)
			break
		end
	end
	if modal == (g.visible ~= false) then
		g:SetVisibility(not modal)
		if not modal then -- (Chili puts a control shown again last among its parent's, drawn first: under Chobby's
			-- full-screen background, the grid "back" and unseen; dev phone, the login dialog cancelled, 2026-11-10)
			g:BringToFront()
		end
		Spring.Echo("[bardroid-lobby] grid " .. (modal and "hidden under a popup" or "back")) -- (tools)
	end
end

local function uprightRedraw()
	local n = contentCount()
	-- (20 or more: a screen or a tab, not a server row coming or going online, each a full redraw twice)
	if not upright.shown or math.abs(n - upright.shown) >= 20 then
		upright.shown, upright.redrawAgain = n, true
		redrawContent()
	elseif upright.redrawAgain then
		upright.redrawAgain = false
		redrawContent()
	end
end

-- The lobby on the screen: always, but in a game only while Chobby's lobby is over it (BAR's Lobby button, Chobby's
-- SetMainInterfaceVisible; Kailil, 2026-11-13: "when you're in game and you press lobby, you get this screen. I want it
-- to reflect how lobby looks in our phone friendly lobby overhaul": the grid and the column were off in a game)
local function lobbyShown()
	if not gameLoaded then
		return true
	end
	local root = WG.Chobby and WG.Chobby.interfaceRoot
	local h = root and root.GetLobbyInterfaceHolder and root.GetLobbyInterfaceHolder()
	return h and h.visible ~= false or false
end

-- A game's touch widget starting again (a fold or turn reloads LuaUI) asks whether BAR's lobby is over the game: it
-- hears Chobby's "LobbyOverlayActive" only as the lobby opens or closes (bardroid_touch.lua's Initialize). The answer is
-- Chobby's own message, to LuaUI as Chobby sends it.
function widget:RecvLuaMsg(msg)
	if msg == "BarDroidOverlay?" and gameLoaded and lobbyShown() and Spring.SendLuaUIMsg then
		Spring.SendLuaUIMsg("LobbyOverlayActive1")
	end
end

local function uprightUpdate(now)
	local shown = lobbyShown() -- (a change at once: Chobby's own layout half a second over the game before)
	if upright.checkAt and Spring.DiffTimers(now, upright.checkAt) < 0.5 and shown == upright.wasShown then
		return
	end
	upright.checkAt, upright.wasShown = now, shown
	if not (screen0 and WG.Chobby and WG.Chobby.interfaceRoot) then
		return
	end
	uprightNotes()
	upright.tips(screen0.height > screen0.width * UPRIGHT)
	if shown then
		upright.quickMaps(screen0.height > screen0.width * UPRIGHT)
		upright.quickPages(screen0.height > screen0.width * UPRIGHT)
		upright.replayTeams(upright.replayPanel)
		upright.pluginButtons(upright.pluginsWin)
		upright.settingsRows(true) -- (both ways up: sideways its rows were the densest, about 2 mm)
		upright.linkRows() -- (both ways up, as far as the panel has room)
		upright.downloadRows() -- (both ways up)
		upright.saveRows() -- (both ways up)
		upright.serverRows() -- (both ways up)
	end
	-- (sideways: the column, upright.side; the upright layouts of the battle room, a scenario and Keys upright only)
	uprightSet(shown, screen0.height <= screen0.width * UPRIGHT)
	if not upright.on then
		return
	end
	local grid = upright.grid
	local size = screen0.width .. "x" .. screen0.height
	if not grid or upright.size ~= size or #upright.mirror ~= #chobbyButtons() then
		uprightGrid()
		upright.size = size
	end
	uprightMirror()
	uprightRelayout()
	if not upright.side then
		uprightBattleRoom()
		uprightScenario()
		uprightKeys()
		uprightMapList()
	end
	uprightRedraw()
	uprightModal()
	if bar and bar.visible then
		placeBar()
	end
end

--------------------------------------------------------------------------------
-- A server's settings that stop the app's controls (BAR's luaui/barwidgets.lua). The controls are user widgets:
-- custom widgets off, or Anonymous Mode, keeps all of them out of a player's game (a spectator's game is exempt);
-- unit control widgets off stops first person and the dock's automation that gives orders (auto retreat, presets;
-- the rest of the app gives no Spring.GiveOrder, and auto mex goes through BAR's own spot builder).

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
	if OFF_VALUES[tostring(options.allowunitcontrolwidgets)] then -- (and the dock's automation that gives orders)
		return warningLines("First person will not work in this game, nor auto retreat and presets",
			"The host turned off unit control widgets. Touch and gamepad controls work.", WARNING_AMBER)
	end
end

-- at the top of the screen as it is now (the scale and folding the phone both resize the lobby's screen)
local function placeWarning()
	local sw = screen0.width
	local left = sideLeft and sideLeft() or 0 -- (sideways beside the column: sideLeft)
	local w = math.min(sw - left - 16, 900)
	warning:SetPos(left + math.floor((sw - left - w) / 2), 8, w, 92)
	warningSize = sideKey()
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
	elseif warningShown and warningSize ~= sideKey() then
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

-- Text boxes for fingers (Kailil, 2026-11-19: "Allow double tap or tap on the chat in the lobby to allow you to ooen
-- the android keyboard to type. If you long press it shlukd enable voice tts system that we have built"): RtsTouch makes
-- a tap a left click and a long press the right button; on a text box the first asks the app for Android's keyboard
-- (any box: chat, search, login), the second, on a chat's box, for speak to chat, its words into that chat
-- (upright.voiceBox, appUpdate's voice_on). The app reads LuaUI/Config/bardroid_lobby_ask.txt (RtsTouch lobbyAskStep).
local ASK_FILE = "LuaUI/Config/bardroid_lobby_ask.txt"
-- (each lobby's own ids: the app keeps the last one it acted on, and a new lobby's first "keyboard 1" was the old one's)
local askSession, askCount = (os and os.time and os.time()) or math.random(100000, 999999), 0
local function textBoxAsk(x, y, button)
	local _, _, hx, hy = chiliPoint(x, y)
	local box = real(screen0:HitTest(hx, hy))
	for _ = 1, 3 do -- (the box itself, or a part of it)
		if not box or box.classname == "editbox" or (box.InheritsFrom and box:InheritsFrom("editbox")) then
			break
		end
		box = real(box.parent)
	end
	if not (box and (box.classname == "editbox" or (box.InheritsFrom and box:InheritsFrom("editbox")))) then
		return
	end
	local what = "keyboard"
	if button == 3 then
		-- (a chat's box: Chobby's console input, 7 from its foot and 31 from its right, the emoji button there)
		local b = box._relativeBounds
		if not (b and b.bottom == 7 and b.right == 31) then
			return
		end
		what = "voice"
		upright.voiceBox, upright.voiceBoxAt = box, Spring.GetTimer()
	end
	askCount = askCount + 1
	local f = io.open(ASK_FILE, "w")
	if f then
		f:write(string.format("%s %d-%d\n", what, askSession, askCount))
		f:close()
	end
	Spring.Echo("[bardroid-lobby] a text box " .. (what == "voice" and "held: speak to chat" or "tapped: the keyboard")) -- (tools)
end

function widget:MousePress(x, y, button)
	hush = { x = x, y = y } -- (any button: a finger's long press is a right click, and lifted there too)
	tabWake.at = Spring.GetTimer()
	if (button == 1 or button == 3) and screen0 and not Spring.IsGUIHidden() then
		pcall(textBoxAsk, x, y, button)
	end
	if button ~= 1 or not screen0 or Spring.IsGUIHidden() then
		return false
	end
	-- (a list still flying: the tap stops it and is no click, as on any phone; its item under the finger was a passing one)
	local flying = fling ~= nil and math.abs(fling.v) > FLING_MIN
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
	if hit and upright.on and upright.grid and onGrid(hit) then -- (the bottom buttons: a sideways swipe pages, a tap
		-- clicks where it is)
		-- (settling: the strip still easing to its page, a tap's buttons moving under the finger)
		press = { grid = true, x = x, y = y, start = upright.stripX, moved = false, lastX = upright.side and -y or x,
			lastT = Spring.GetTimer(), vel = 0, settling = upright.anim ~= nil }
		upright.anim = nil
		return true
	end
	if not (panel or battle) then
		return false
	end
	press = { x = x, y = y, panel = panel, battle = battle, start = panel and panel.scrollPosY or 0, moved = false,
		lastY = y, lastT = Spring.GetTimer(), vel = 0, stopped = flying }
	return true
end

function widget:MouseMove(x, y)
	local p = press
	if not p then
		return false
	end
	if p.grid then -- the bottom buttons' strip with the finger (past its ends a third as far: it gives, then settles)
		-- (sideways the column's: up and down; the engine's y runs up, Chili's down)
		local along, from = x, p.x
		if upright.side then
			along, from = -y, -p.y
		end
		if not p.moved and math.abs(along - from) > DRAG_PX then
			p.moved = true
		end
		if p.moved and upright.grid then
			local s = uiScale()
			local nx, minX = p.start + (along - from) / s * PAGE_GAIN, -(upright.pages - 1) * upright.pageSize
			if nx > 0 then
				nx = nx / 3
			elseif nx < minX then
				nx = minX + (nx - minX) / 3
			end
			stripTo(nx)
			local now = Spring.GetTimer()
			local dt = Spring.DiffTimers(now, p.lastT)
			if dt > 0.001 then
				p.vel = p.vel * 0.6 + (along - p.lastX) / s / dt * 0.4
				p.lastX, p.lastT = along, now
			end
		end
		return true
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
	if p.grid then -- a swipe turns the page its way (PAGE_TURN, or a flick), a long one to the page it reached; a tap is
		-- the button's click
		if p.moved and upright.grid then
			local w = math.max(1, upright.pageSize)
			local nearest = math.floor(-upright.stripX / w + 0.5)
			local drag = upright.stripX - p.start
			local page = nearest
			if math.abs(drag) > PAGE_TURN * w then
				page = drag < 0 and math.max(upright.page + 1, nearest) or math.min(upright.page - 1, nearest)
			elseif math.abs(p.vel) > PAGE_FLICK and Spring.DiffTimers(Spring.GetTimer(), p.lastT) < 0.1 then
				page = upright.page + (p.vel < 0 and 1 or -1)
			end
			uprightSettle(page)
		elseif not p.moved and p.settling then
			-- (a tap while the strip eased to its page: the press stopped it there, between two pages, and the click went
			-- to a button passing under the finger; dev phone, a swipe then a tap, 2026-11-11: the page turn finishes)
			uprightSettle(upright.page)
		elseif not p.moved and (math.abs(x - p.x) > DRAG_PX or math.abs(y - p.y) > DRAG_PX) then
			-- (a slide across the paging way, off the buttons: no click; it went to whatever was under the lifted finger,
			-- sideways a server row, which Chobby joined; review 2026-11-15)
			uprightSettle(upright.page)
		elseif not p.moved then
			local _, _, hx, hy = chiliPoint(x, y)
			local page = stripPage(hx, hy)
			if page then
				uprightSettle(page)
			else
				click(x, y)
			end
		end
		return true
	end
	if p.moved then
		if math.abs(p.vel) > FLING_MIN and Spring.DiffTimers(Spring.GetTimer(), p.lastT) < 0.1 then
			fling = { panel = p.panel, v = p.vel }
		end
	elseif p.stopped then
		Spring.Echo("[bardroid-lobby] a tap stopped a flying list (no click)") -- (tools)
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

--------------------------------------------------------------------------------
-- The app's lines in the lobby (RtsTouch's touch log, the one the game's widget reads; Kailil, 2026-11-06: "I want the
-- text chat stuff working in lobby too", "allow dpad menu navigation via selection in the lobby"):
--   speak to chat (a three-finger tap; the pad's LB held + RB twice): the words go to the server room's chat while one
--     is joined, else to the chat tab open; while it listens D-pad left / right or a sideways swipe step through them
--     (the room first, then each tab), a note at the top saying where
--   the pad's D-pad: the pointer onto the nearest control that way (a button, a tab, a list's row, a box), ringed in
--     gold; A clicks it as always. Only what is not covered (a dialog in front keeps the D-pad on itself); in a list
--     the D-pad scrolls on past its last row in sight. The left stick or a finger moving the pointer away lets go.

local TOUCH_LOG = "LuaUI/Config/bardroid_touch.txt"
local logFile, logPos

-- the log's new whole lines since the last call (none the first time: what came before is not replayed). Its size only
-- every 30 calls (a seek to the end is an fstat, which proot traps: bardroid_touch.lua's newTouchLines); else reads on.
local logCalls = 0
local logMissing = false -- (no log at the first look: one that appears after holds only new lines)
local function appLines()
	if not logFile then
		logFile = io.open(TOUCH_LOG, "r")
		-- (a log that was not there before is read from its start: its first line made it, and opened at its end that
		-- line was lost; laptop lobby-touch-test, 2026-11-18, "act voice_on" written into a log not yet made)
		logPos = logFile and (logMissing and 0 or logFile:seek("end"))
		logMissing = logFile == nil
		if not (logFile and logPos == 0) then
			return nil
		end
	end
	logCalls = logCalls + 1
	if logCalls % 30 == 0 then
		local size = logFile:seek("end")
		if not size then
			logFile:close()
			logFile = nil
			return nil
		end
		if size < logPos then
			logPos = 0 -- (the app began the log anew)
		end
	end
	if not logFile:seek("set", logPos) then
		return nil
	end
	local text = logFile:read("*a") or ""
	if text == "" then
		return nil
	end
	local last = text:match(".*()\n")
	if not last then
		return nil
	end
	logPos = logPos + last
	return text:sub(1, last)
end

local GOLD = { 1, 0.78, 0.25, 1 }

-- Speak to chat

local voiceOn, voiceTarget = false, nil -- listening; the target picked, by name (kept for the lobby's session)
local voicePanel, voiceLabel
-- its words' width, as the font measures them; arrows: the target's (the channel steps), drawn either side of the words
local voiceTextW, voiceArrows = 0, false

local function voiceTargets()
	local targets = {}
	local lobby = WG.LibLobby and WG.LibLobby.lobby
	if lobby and lobby.myBattleID then
		targets[#targets + 1] = { name = "SERVER ROOM", send = function(text) lobby:SayBattle(text) end }
	end
	local root = WG.Chobby and WG.Chobby.interfaceRoot
	local chat = root and root.GetChatWindow and root.GetChatWindow()
	local tabBar = chat and chat.tabPanel and chat.tabPanel.tabBar
	for i, child in ipairs(tabBar and tabBar.children or {}) do
		local console = chat.tabbars and chat.tabbars[child.name]
		if console and console.listener then
			local user = child.name:match("^(.-) messages$")
			targets[#targets + 1] = { name = user and ("@" .. user) or ("#" .. child.name), tab = child.name,
				open = tabBar.selected == i, send = console.listener, console = console }
		end
	end
	return targets
end

-- the target now: the one picked if it is still there, else the server room, else the open tab, else the first
local function voiceCurrent(targets)
	for _, t in ipairs(targets) do
		if t.name == voiceTarget then
			return t
		end
	end
	if targets[1] and targets[1].name == "SERVER ROOM" then
		return targets[1]
	end
	for _, t in ipairs(targets) do
		if t.open then
			return t
		end
	end
	return targets[1]
end

-- say: a note in the panel instead of the target (the microphone not allowed: voice_nomic, VOICE_NOMIC_SECONDS)
local VOICE_NOMIC = "TO SPEAK, ALLOW THE MICROPHONE IN ANDROID'S SETTINGS" -- (bardroid_pad.lua's in a game)
local VOICE_NOMIC_SECONDS = 4
local voiceNoteAt = nil -- the note's start; the panel goes after VOICE_NOMIC_SECONDS
local function voiceShow(say)
	if not voicePanel then
		local config = WG.Chobby and WG.Chobby.Configuration
		voicePanel = Chili.Window:New({
			name = "bardroidLobbyVoice",
			parent = screen0,
			x = 0, y = 8, width = 100, height = 56,
			resizable = false, draggable = false,
			padding = { 0, 0, 0, 0 },
		})
		-- (not Chili's autosize: sized to its text while the panel was still 100 wide, the words sat off centre and their
		-- start was cut, "'EAK TO CHAT: JOIN A SERVER ...", dev phone, 2026-11-09)
		voiceLabel = Chili.Label:New({
			parent = voicePanel,
			x = 0, y = 0, right = 0, bottom = 0,
			autosize = false,
			align = "center", valign = "center",
			caption = "",
			objectOverrideFont = config and config:GetFont(3),
		})
		-- (the target's arrows as solid triangles either side of the words, as the game's note draws them: the font's
		-- "<" and ">" were thin marks; dev phone 2026-11-18)
		Chili.Control:New({
			parent = voicePanel,
			x = 0, y = 0, right = 0, bottom = 0,
			padding = { 0, 0, 0, 0 },
			drawcontrolv2 = true,
			DrawControl = function(obj)
				if not voiceArrows then
					return
				end
				local h, cx = obj.height, obj.width / 2
				local cy, a, gap = h / 2, h * 0.17, h * 0.3
				gl.Texture(false)
				gl.Color(1, 1, 1, 0.92)
				for side = -1, 1, 2 do
					local bx = cx + side * (voiceTextW / 2 + gap) -- (the base by the words, the point away from them)
					gl.BeginEnd(GL.TRIANGLES, function()
						gl.Vertex(bx + side * a * 1.2, cy)
						gl.Vertex(bx, cy - a)
						gl.Vertex(bx, cy + a)
					end)
				end
				gl.Color(1, 1, 1, 1)
			end,
		})
	end
	local target = not say and voiceCurrent(voiceTargets())
	voiceArrows = target and true or false
	local caption = say or target and ("SPEAK TO " .. string.upper(target.name))
		or "SPEAK TO CHAT: JOIN A SERVER OR OPEN THE CHAT"
	local font = voiceLabel.font
	local ok, textW = pcall(function() return font:GetTextWidth(caption) end)
	voiceTextW = ok and tonumber(textW) or 0
	local w = math.min(screen0.width - 16, math.max(640, math.ceil(voiceTextW) + 48 + (voiceArrows and 60 or 0))) -- (a long name: the panel grows)
	voicePanel:SetPos(math.floor((screen0.width - w) / 2), 8, w, 56)
	voiceLabel:SetPos(0, 0, w, 56)
	voiceLabel:SetCaption(caption)
	voicePanel:Show()
	voicePanel:BringToFront()
end

local function voiceStep(by)
	local targets = voiceTargets()
	local now = voiceCurrent(targets)
	if not now then
		return
	end
	local at = 1
	for i, t in ipairs(targets) do
		if t == now then
			at = i
		end
	end
	local nextOne = targets[(at - 1 + by) % #targets + 1]
	voiceTarget = nextOne.name
	if nextOne.tab then -- (its tab shown: where the words will be)
		local root = WG.Chobby and WG.Chobby.interfaceRoot
		local chat = root and root.GetChatWindow and root.GetChatWindow()
		pcall(function() chat.tabPanel.tabBar:Select(nextOne.tab) end)
	end
	voiceShow()
end

-- (a game loaded beside the lobby: the engine's ActivateGame / ActivateMenu. Words said in a game are the game's
-- chat's alone; the app marks them "voicegame", which this widget does not read, and while a game runs the lobby
-- leaves "voice" lines to it too: Kailil, 2026-11-08, "the voice chat is also sending chats to the lobby")
-- The rest of speaking goes with the words: "voice_on" put the lobby's "< SPEAK TO SERVER ROOM >" up too, and the
-- D-pad's channel steps switched the lobby's chat tabs behind the game (2026-11-08).
function widget:ActivateGame()
	gameLoaded = true
	voiceOn = false
	if voicePanel then
		voicePanel:Hide()
	end
	if screen0 then -- (the upright grid is the lobby's: it lay over the game's dock, Kailil's screenshot 2026-11-09)
		uprightSet(false)
	end
end
function widget:ActivateMenu() gameLoaded = false end

local function voiceSay(text)
	if gameLoaded then
		return
	end
	text = text:gsub("%s+", " "):gsub("^ ", "")
	local target = voiceCurrent(voiceTargets())
	if target and text:find("%S") then
		pcall(target.send, text)
	end
end

-- The D-pad from control to control

local FOCUS_CLASSES = { "button", "checkbox", "tabbaritem", "combobox", "editbox", "trackbar" }
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local focus, focusRing, focusAt -- the control the D-pad put the pointer on, its ring, where the pointer went (mouse pixels)

local function focusable(obj)
	if obj.OnClick and #obj.OnClick > 0 then
		return true
	end
	for _, c in ipairs(FOCUS_CLASSES) do
		if obj.InheritsFrom and obj:InheritsFrom(c) then
			return true
		end
	end
	return false
end

-- every focusable control in sight: { obj, x0, y0, x1, y1 } in the screen's own coordinates, cut to the lists they sit in
local function collect(obj, clip, out)
	obj = real(obj)
	if not obj or obj.hidden or obj.visible == false or not obj.LocalToScreen or obj == real(focusRing) then
		return
	end
	local x, y = obj:LocalToScreen(0, 0)
	local r = { math.max(x, clip[1]), math.max(y, clip[2]), math.min(x + (obj.width or 0), clip[3]),
		math.min(y + (obj.height or 0), clip[4]) }
	if r[3] - r[1] < 6 or r[4] - r[2] < 6 then
		return
	end
	if obj ~= real(screen0) and focusable(obj) then
		out[#out + 1] = { obj = obj, r = r }
		return -- (a button's children are its caption and picture)
	end
	local inner = overflows(obj) and r or clip
	for _, child in ipairs(obj.children or {}) do
		collect(child, inner, out)
	end
end

-- not covered: the screen's own hit test at its middle lands on it (or inside it)
local function onTop(c)
	local cx, cy = (c.r[1] + c.r[3]) / 2, (c.r[2] + c.r[4]) / 2
	local hit = screen0:HitTest(cx, cy)
	hit = real(hit)
	while hit do
		if hit == c.obj then
			return true
		end
		hit = real(hit.parent)
	end
	return false
end

local function pointerToChili()
	local mx, my = mouse()
	local _, _, hx, hy = chiliPoint(mx, my)
	return hx, hy
end

local function focusRect()
	local obj = focus and real(focus)
	if not obj or obj.disposed or not obj.parent or not obj:IsVisibleOnScreen() then
		return nil
	end
	local x, y = obj:LocalToScreen(0, 0)
	return x, y, obj.width or 0, obj.height or 0
end

local function placeRing()
	local x, y, w, h = focusRect()
	if not x then
		focus = nil
		if focusRing then
			focusRing:Hide()
		end
		return
	end
	if not focusRing then
		focusRing = Chili.Control:New({
			name = "bardroidLobbyFocus",
			parent = screen0,
			x = 0, y = 0, width = 10, height = 10,
			padding = { 0, 0, 0, 0 },
			drawcontrolv2 = true,
			HitTest = function() return false end, -- (never in the way of a click)
			DrawControl = function(obj)
				gl.Texture(false)
				gl.Color(GOLD)
				local t = 3
				gl.Rect(0, 0, obj.width, t)
				gl.Rect(0, obj.height - t, obj.width, obj.height)
				gl.Rect(0, t, t, obj.height - t)
				gl.Rect(obj.width - t, t, obj.width, obj.height - t)
				gl.Color(1, 1, 1, 1)
			end,
		})
	end
	focusRing:SetPos(x - 3, y - 3, w + 6, h + 6)
	focusRing:Show()
	focusRing:BringToFront()
end

local function navigate(dir)
	if not screen0 then
		return
	end
	local d = DIRECTIONS[dir]
	local ox, oy
	local fx, fy, fw, fh = focusRect()
	if fx then
		ox, oy = fx + fw / 2, fy + fh / 2
	else
		ox, oy = pointerToChili()
	end
	local function best()
		local list = {}
		collect(screen0, { 0, 0, screen0.width, screen0.height }, list)
		local pick, score = nil, math.huge
		for _, c in ipairs(list) do
			if c.obj ~= real(focus) then
				local vx, vy = (c.r[1] + c.r[3]) / 2 - ox, (c.r[2] + c.r[4]) / 2 - oy
				local along = vx * d[1] + vy * d[2]
				if along > 4 then
					local s = along + math.abs(vx * d[2] - vy * d[1]) * 2.5
					if s < score and onTop(c) then
						pick, score = c, s
					end
				end
			end
		end
		return pick
	end
	local pick = best()
	if not pick and fx and d[1] == 0 then -- (the end of a list in sight: it scrolls on, then the next row)
		local obj = real(real(focus).parent)
		while obj and not overflows(obj) do
			obj = real(obj.parent)
		end
		if obj then
			obj:SetScrollPos(nil, obj.scrollPosY + d[2] * math.max(24, fh), false, true)
			pick = best()
		end
	end
	if not pick then
		Spring.Echo(string.format("[bardroid-lobby] the pad: nothing %s of %s", dir, fx
			and string.format("%s \"%s\"", tostring(real(focus).classname), tostring(real(focus).caption or real(focus).name or ""))
			or string.format("the pointer at %d %d", ox, oy))) -- (tools/lobby-phone-test.ps1)
		return
	end
	focus = pick.obj
	local cx, cy = (pick.r[1] + pick.r[3]) / 2, (pick.r[2] + pick.r[4]) / 2
	local s = uiScale()
	local mx, my = math.floor(cx * s + 0.5), math.floor((select(2, Spring.GetViewSizes()) - cy) * s + 0.5)
	if Spring.WarpMouse then
		pcall(Spring.WarpMouse, mx, my)
	end
	focusAt = { mx, my }
	placeRing()
	Spring.Echo(string.format("[bardroid-lobby] the pad on %s \"%s\" at %d %d", tostring(pick.obj.classname),
		tostring(pick.obj.caption or pick.obj.name or ""), mx, my)) -- (tools/lobby-phone-test.ps1)
end

local function appUpdate()
	local lines = appLines()
	if lines then
		for name in lines:gmatch("act (%S+)") do
			if name == "voice_on" then
				voiceOn = not gameLoaded -- (in a game: the game's own note and channels)
				-- (begun by a long press on a chat's box, textBoxAsk: the words into that chat, the server room's
				-- for the battle room's box)
				local box = upright.voiceBox
				upright.voiceBox = nil
				if voiceOn and box and Spring.DiffTimers(Spring.GetTimer(), upright.voiceBoxAt) < 4 then
					local o, room = box, real(chobbyObject("chatPanel"))
					while o and room do
						if o == room then
							voiceTarget = "SERVER ROOM"
							break
						end
						o = real(o.parent)
					end
					if o ~= room or not room then
						for _, t in ipairs(voiceTargets()) do
							if t.console and real(t.console.ebInputText) == box then
								voiceTarget = t.name
							end
						end
					end
				end
				if voiceOn then
					voiceNoteAt = nil
					voiceShow()
				end
			elseif name == "voice_nomic" or name == "voice_nonet" then -- (no network: the recognizer needed one)
				if not gameLoaded then
					voiceShow(name == "voice_nomic" and VOICE_NOMIC or "NOTHING SENT: SPEECH NEEDS A CONNECTION")
					voiceNoteAt = Spring.GetTimer()
				end
			elseif name == "voice_off" then
				voiceOn = false
				if voicePanel then
					voicePanel:Hide()
				end
			elseif voiceOn and (name == "voice_channel_next" or name == "voice_channel_prev") then
				voiceStep(name == "voice_channel_next" and 1 or -1)
			else
				local dir = name:match("^lobby_nav_(%a+)$")
				if DIRECTIONS[dir] then
					Spring.Echo("[bardroid-lobby] the pad's D-pad: " .. dir) -- (tools/lobby-phone-test.ps1)
					navigate(dir)
				end
			end
		end
		for hex in lines:gmatch("voice (%x+)") do
			voiceSay((hex:gsub("%x%x", function(h)
				return string.char(tonumber(h, 16))
			end)))
		end
	end
	if voiceNoteAt and Spring.DiffTimers(Spring.GetTimer(), voiceNoteAt) >= VOICE_NOMIC_SECONDS then
		voiceNoteAt = nil
		if voicePanel and not voiceOn then
			voicePanel:Hide()
		end
	end
	if focus then -- (the pointer moved away: let go; the control moved, as a list scrolls: the ring follows)
		local mx, my = mouse()
		if not focusAt or math.abs(mx - focusAt[1]) + math.abs(my - focusAt[2]) > 24 then
			Spring.Echo(string.format("[bardroid-lobby] the pad let go: the pointer at %d %d, put at %d %d", mx, my,
				focusAt and focusAt[1] or -1, focusAt and focusAt[2] or -1))
			focus = nil
		end
		placeRing()
	end
end

local lastUpdate
-- BAR's Rapid Pool Cache stopped while the lobby's Settings has it off (launch-bar.sh turns that off once): it reads
-- all of the rapid pool when the lobby opens, 50 ms of every frame, and through proot its speed test always finds the
-- cache cold: the lobby at 13-15 fps instead of 30 for its first ~30 s (dev phone, 2026-11-11). BAR's "Disable NonBar
-- Widgets" starts it at every start, in its first Update, so it is looked for over the first seconds.
local poolCacheFrom
local function poolCacheCheck(now)
	poolCacheFrom = poolCacheFrom or now
	if Spring.DiffTimers(now, poolCacheFrom) > 15 then
		return
	end
	local C = WG.Chobby and WG.Chobby.Configuration
	if not (C and C.enableCacheRapidPool == false) then
		return
	end
	-- (Chobby's "Caching..." label, bottom left over Exit, is the cache's to hide when it ends: stopped before its first
	-- frame it never found it, and the label stayed for the lobby's whole run; dev phone, 2026-11-12)
	local root = WG.Chobby.interfaceRoot
	local label = root and root.GetCachingLabel and root.GetCachingLabel()
	if label and label.visible ~= false and label.SetVisibility then
		label:SetVisibility(false)
	end
	local w = widgetHandler.FindByName and widgetHandler:FindByName("Rapid Pool Cache")
	if w then
		-- (its Shutdown still runs, its last line kept from failing: stopped before its first frame it divides 0 by 0,
		-- "bad argument #4 to 'format' ... NaN", an error in the log at every lobby start)
		local shutdown = w.Shutdown
		if type(shutdown) == "function" then
			w.Shutdown = function(...)
				pcall(shutdown, ...)
			end
		end
		widgetHandler:DisableWidget("Rapid Pool Cache")
		Spring.Echo("[bardroid-lobby] Rapid Pool Cache stopped (off in the lobby's Settings)") -- (tools)
	end
end

-- Chobby's Replays tab: Open Folder opens nothing on a phone (the replays are in the app's own storage, which no file
-- manager shows), a button that did nothing at a tap (dev phone, 2026-11-12; it was hidden). It is "Add" now: LobbyBridge
-- takes its OpenFile of demos/ to Android's file picker, and the replays picked (a browser's downloads from BAR's
-- replays website, the tab's Download) are copied into demos/ (ReplayImportActivity; 2026-11-17).
-- The same for Links' last line, "Game Data: Open game data folder to find config files and logs." (WrapperLoopback's
-- OpenFolder; on a phone the launcher's Share logs gives the logs): the line hidden, the last, so no gap.
-- And Plugins' "Widgets Folder" (the first of its row: Contribute and Refresh move left into its place).
local replaysRow = { at = nil, done = false, linksDone = false, pluginsDone = false }
local function replaysRowCheck(now)
	if (replaysRow.done and replaysRow.linksDone and replaysRow.pluginsDone)
		or (replaysRow.at and Spring.DiffTimers(now, replaysRow.at) < 1)
		or (replaysRow.at and not (tabWake.at and Spring.DiffTimers(now, tabWake.at) < 4)) then -- (once at the start,
		-- then for 4 s after a press: tabs open on one)
		return
	end
	replaysRow.at = now
	-- (Replays' Refresh by its tooltip, Links' Game Data and Plugins' Widgets Folder by their captions: no names on them)
	local refresh, gameData, widgetsFolder
	local function walk(o, depth)
		if (refresh and gameData and widgetsFolder) or not o or depth > 40 then
			return
		end
		if o.tooltip == "Refresh the list of replays" then
			refresh = o
		elseif o.caption == "Game Data" and o.classname ~= "label" then
			gameData = o
		elseif o.caption == "Widgets Folder" and o.classname ~= "label" then
			widgetsFolder = o
		end
		for _, c in ipairs(o.children or {}) do
			walk(c, depth + 1)
		end
	end
	walk(screen0, 0)
	local line = not replaysRow.linksDone and gameData and real(gameData.parent)
	if line and line.SetVisibility then
		line:SetVisibility(false)
		replaysRow.linksDone = true
		Spring.Echo("[bardroid-lobby] Links: Game Data hidden (no folder to open on Android)") -- (tools)
	end
	widgetsFolder = not replaysRow.pluginsDone and real(widgetsFolder)
	local strip = widgetsFolder and real(widgetsFolder.parent)
	if strip then
		local x0, y0, stride = widgetsFolder.x, widgetsFolder.y, nil
		for _, c in ipairs(strip.children or {}) do -- (the next one along: how far each moves)
			if c ~= widgetsFolder and c.y == y0 and c.x > x0 and (not stride or c.x - x0 < stride) then
				stride = c.x - x0
			end
		end
		widgetsFolder:SetVisibility(false)
		for _, c in ipairs(strip.children or {}) do
			-- (Contribute, Refresh and Update All, made with them though shown only with updates (it stood alone after a
			-- gap, review 2026-11-15): every captioned button right of it; the search box, no caption, stays)
			if stride and c ~= widgetsFolder and c.y == y0 and c.x > x0
				and type(c.caption) == "string" and c.caption ~= "" and c.SetPos then
				c:SetPos(c.x - stride)
			end
		end
		replaysRow.pluginsDone = true
		Spring.Echo("[bardroid-lobby] Plugins: Widgets Folder hidden (no folder to open on Android)") -- (tools)
		upright.pluginsWin = strip -- (its buttons sized for a finger, upright.pluginButtons)
	end
	local row = not replaysRow.done and refresh and real(refresh.parent)
	if not row then
		return
	end
	upright.replayPanel = real(row.parent) -- (the Replays tab: upright.replayTeams fits its rows' teams)
	local function rightOf(o)
		return o._relativeBounds and o._relativeBounds.right
	end
	for _, c in ipairs(row.children or {}) do
		local r = rightOf(c)
		if r == 145 and c ~= refresh and c.classname == "option_button" then
			if c.SetCaption then
				c:SetCaption("Add")
			else
				c.caption = "Add"
			end
			c.tooltip = "Adds replays (.sdfz) from the phone, as the browser downloads them"
			c:Invalidate()
		end
		-- (Download's tooltip asked for the .sdfz files in "your data/demos folder", which a phone's player cannot reach:
		-- a replay the browser downloads stays in the phone's Downloads; dev phone, the pad's ring on it, 2026-11-17)
		if type(c.tooltip) == "string" and c.tooltip:find("data/demos", 1, true) then
			-- (as short as BAR's: a longer one wrapped, its last word alone on a second line)
			c.tooltip = "BAR's replays website: Add brings a replay downloaded there into this list"
		end
	end
	replaysRow.done = true
	replaysRow.refresh = refresh -- (the list made again after the app's Add, replaysAdded)
	Spring.Echo("[bardroid-lobby] Replays: Open Folder is Add (Android's file picker, ReplayImportActivity)") -- (tools)
end

-- The app's Add copied replays into demos/ (ReplayImportActivity writes the time to STAMP): the list made again as
-- Refresh makes it. Read once a second; the first read only notes what is there (an Add of an earlier lobby).
local REPLAYS_STAMP = "LuaUI/Config/bardroid_replays.txt"
local function replaysAdded(now)
	if not replaysRow.refresh or (replaysRow.stampAt and Spring.DiffTimers(now, replaysRow.stampAt) < 1) then
		return
	end
	replaysRow.stampAt = now
	local f = io.open(REPLAYS_STAMP, "r")
	local t = f and f:read("*l") or ""
	if f then
		f:close()
	end
	if replaysRow.stamp ~= nil and t ~= replaysRow.stamp then
		local button = real(replaysRow.refresh)
		if button and not button.disposed then
			for _, fn in ipairs(button.OnClick or {}) do
				pcall(fn, button)
			end
			Spring.Echo("[bardroid-lobby] Replays: the list made again after Add") -- (tools)
		end
	end
	replaysRow.stamp = t
end

-- Chobby's Load Game writes a save's date day first, "12/11/2026" over "15:17:38" (gui_loadgame.lua WriteDate), which
-- on a US phone reads as December 11, beside Replays' "2026-11-16 19:23" (dev phone upright, 2026-11-17): the same
-- year-first way here, its minutes last. Walked once a second for 4 s after a press, as the tabs' fixes (Update).
local function saveDates(o, depth)
	if not o or o.disposed or depth > 40 then
		return
	end
	if o.classname == "textbox" and type(o.text) == "string" and o.SetText then
		local d, m, y, hh, mm = o.text:match("^(%d%d)/(%d%d)/(%d%d%d%d)\n(%d%d):(%d%d):%d%d$")
		if d then
			o:SetText(string.format("%s-%s-%s\n%s:%s", y, m, d, hh, mm))
		end
	end
	for _, c in ipairs(o.children or {}) do
		saveDates(real(c), depth + 1)
	end
end

-- Chobby's Load Game, a save of another engine version: "it will be opened in a new window", and on a phone none opens
-- (no second engine; LobbyBridge's toast gives the versions). Its popup says so instead (dev phone, 2026-11-17)
local NEW_WINDOW = "uses a different engine, so it will be opened in a new window"
local infoPopupWrapped = false
local function wrapInfoPopup()
	local C = WG.Chobby
	if infoPopupWrapped or not (C and C.InformationPopup) then
		return
	end
	infoPopupWrapped = true
	local orig = C.InformationPopup
	C.InformationPopup = function(text, ...)
		if type(text) == "string" and text:find(NEW_WINDOW, 1, true) then
			text = "The saved game uses a different engine version, which this phone cannot open."
		end
		return orig(text, ...)
	end
end

-- Chili's drop-down lists stop at 200 high (maxDropDownHeight): upright, the Scenarios' list of 24 showed five and a
-- half titles on a screen 2000 tall (dev phone, 2026-11-17). Upright, up to 45 % of the screen; its own size otherwise.
local comboWrapped = false
local function wrapComboBox()
	local CB = Chili and Chili.ComboBox
	if comboWrapped or not (CB and CB.MouseDown) then
		return
	end
	comboWrapped = true
	local orig = CB.MouseDown
	CB.MouseDown = function(self, ...)
		self.droidMaxH = self.droidMaxH or self.maxDropDownHeight
		local tall = upright.on and not upright.side and screen0 and screen0.height
		self.maxDropDownHeight = tall and math.max(self.droidMaxH, math.floor(tall * 0.45)) or self.droidMaxH
		return orig(self, ...)
	end
end

function widget:Update() -- (the lobby's Update has no frame time)
	wrapInfoPopup()
	wrapComboBox()
	local now = Spring.GetTimer()
	local dt = lastUpdate and math.min(0.1, Spring.DiffTimers(now, lastUpdate)) or 0
	lastUpdate = now
	poolCacheCheck(now)
	if screen0 and not gameLoaded then -- (no walks of the lobby's controls while a game runs)
		replaysRowCheck(now)
		if tabWake.at and Spring.DiffTimers(now, tabWake.at) < 4
			and not (replaysRow.datesAt and Spring.DiffTimers(now, replaysRow.datesAt) < 1) then
			replaysRow.datesAt = now
			saveDates(real(screen0), 0)
		end
	end
	replaysAdded(now)
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
		local mx, my, left, middle, right = mouse()
		if math.abs(mx - hush.x) + math.abs(my - hush.y) > DRAG_PX then
			local out = hush.out
			hush = nil
			if out and screen0._lastHoveredControl == out then
				pcall(function() out:MouseOver() end)
			end
		else
			screen0.currentTooltip = nil
			local hovered = screen0._lastHoveredControl
			-- (the same control lit again too: a page swipe's overshoot carried a grid button off the spot and back, and
			-- Chili hovered it anew, which a once-a-control MouseOut left lit; dev phone, 2026-11-10)
			if hovered and (hovered ~= hush.out or (hovered.state and hovered.state.hovered))
				and not (left or middle or right) then
				hush.out = hovered
				pcall(function() hovered:MouseOut() end) -- (a weak link: its control may be gone)
			end
		end
	end
	if popupButton and (popupButton.disposed or not popupButton.parent or popupButton.visible == false) then
		closePopup() -- the list went away (another screen, the server closed)
	elseif popupButton and barSize ~= sideKey() then
		placeBar() -- folded or unfolded
	end
	if not warningCheck or Spring.DiffTimers(now, warningCheck) >= WARNING_CHECK_S then
		warningCheck = now
		updateWarning()
	end
	uprightUpdate(now)
	if upright.anim then
		uprightAnimate(dt)
	end
	appUpdate()
end

function widget:Initialize()
	-- (tools/lobby-touch-test.ps1: the same input as a finger, without one)
	WG.BarDroidLobbyTouch = {
		upright = function() return upright.on and not upright.side end, -- (tools: the lobby test, upright or sideways)
		column = function() return upright.on and upright.side end, -- (tools: sideways, the buttons' column)
		barTop = function() return uprightBarTop and uprightBarTop() end, -- (upright: where the server bar stands on)
		sideLeft = function() return sideLeft and sideLeft() or 0 end, -- (sideways: the column's edge, the bar centred beside it)
		press = function(x, y) return widget:MousePress(x, y, 1) end,
		move = function(x, y) return widget:MouseMove(x, y, 0, 0, 1) end,
		release = function(x, y) return widget:MouseRelease(x, y, 1) end,
		popup = function() return popupButton end,
		warning = function() return warningShown end,
		-- (tools/lobby-touch-test: speak to chat's panel up, and a game loaded or not, as the engine's callins say)
		voiceShown = function() return voicePanel ~= nil and voicePanel.visible ~= false end,
		-- the panel, its label and the words' width (panel x, y, w, h; label x, w; words w; screen w; caption)
		voiceRect = function()
			if not voicePanel then
				return nil
			end
			return voicePanel.x, voicePanel.y, voicePanel.width, voicePanel.height, voiceLabel.x, voiceLabel.width,
				voiceTextW, screen0 and screen0.width, voiceLabel.caption
		end,
		activate = function(game)
			if game then
				widget:ActivateGame()
			else
				widget:ActivateMenu()
			end
		end,
	}
end

function widget:Shutdown()
	WG.BarDroidLobbyTouch = nil
	if screen0 then
		uprightSet(false)
	end
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
