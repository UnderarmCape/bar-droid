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
placeBar = function()
	local sw, sh = screen0.width, screen0.height
	local w, h = math.min(sw - 16, 760), 70
	local top = uprightBarTop and uprightBarTop()
	bar:SetPos(math.floor((sw - w) / 2), (top or sh) - h - (top and 4 or 10), w, h)
	barSize = sw .. "x" .. sh
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
local upright = { on = false, grid = nil, mirror = {}, scaleBefore = nil, checkAt = nil, page = 0, pages = 1,
	stripX = 0, anim = nil }

-- The pages' strip moved: each button to its place on its page plus x (a strip of its own, three screens wide, was not
-- drawn by Chili: its buttons stood in the grid as before)
local function stripTo(x)
	upright.stripX = x
	for _, m in ipairs(upright.mirror) do
		if m.base and not m.mine.disposed then
			m.mine:SetPos(math.floor(m.base + x + 0.5))
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
		end
	end
	table.sort(out, function(a, b)
		return rank[a] < rank[b]
	end)
	return out
end

uprightBarTop = function()
	if not (upright.on and upright.grid) then
		return nil
	end
	return upright.grid.y
end

-- the content between the top and the grid (and the server bar while it is up); Chobby's left column hidden
uprightRelayout = function()
	if not upright.on then
		return
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
	local perPage = PAGE_COLS * PAGE_ROWS
	local pages = math.ceil(#found / perPage)
	local rows = math.min(PAGE_ROWS, math.ceil(#found / PAGE_COLS))
	local dots = pages > 1 and GRID_DOTS_H or 0
	local h = rows * GRID_ROW_H + (rows + 1) * GRID_GAP + dots
	if upright.grid then
		upright.grid:Dispose()
	end
	upright.pages = pages
	upright.page = math.min(upright.page, pages - 1)
	upright.anim = nil
	upright.grid = Chili.Window:New({
		name = "bardroidLobbyGrid",
		parent = screen0,
		x = 0, y = sh - h, width = sw, height = h,
		resizable = false, draggable = false,
		padding = { 0, GRID_GAP, 0, GRID_GAP },
	})
	upright.caching = nil
	if pages > 1 then -- (the page strip, under the buttons: arrows at its ends, the dots between, the one shown lit)
		Chili.Control:New({
			parent = upright.grid,
			x = 0, bottom = 0, width = "100%", height = dots,
			padding = { 0, 0, 0, 0 },
			drawcontrolv2 = true,
			DrawControl = function(obj)
				local s, gap = 8, 12
				local x0 = (obj.width - (upright.pages * s + (upright.pages - 1) * gap)) / 2
				local at = -upright.stripX / math.max(1, screen0.width)
				local cy = obj.height / 2
				gl.Texture(false)
				for p = 0, upright.pages - 1 do
					local lit = math.max(0, 1 - math.abs(at - p)) -- (lit as the strip passes it)
					gl.Color(1, 0.78 + 0.2 * (1 - lit), 0.25 + 0.75 * (1 - lit), 0.3 + 0.7 * lit)
					local x = x0 + p * (s + gap)
					gl.Rect(x, cy - s / 2, x + s, cy + s / 2)
				end
				local a = obj.height * 0.34 -- (the arrows, dim at the first and the last page)
				gl.LineWidth(4)
				for side = -1, 1, 2 do
					local to = upright.page + side
					gl.Color(1, 1, 1, (to >= 0 and to < upright.pages) and 0.85 or 0.2)
					local x = side < 0 and obj.height * 0.6 or obj.width - obj.height * 0.6
					gl.BeginEnd(GL.LINE_STRIP, function()
						gl.Vertex(x - side * a * 0.5, cy - a)
						gl.Vertex(x + side * a * 0.5, cy)
						gl.Vertex(x - side * a * 0.5, cy + a)
					end)
				end
				gl.LineWidth(1)
				gl.Color(1, 1, 1, 1)
			end,
		})
		upright.caching = Chili.Label:New({ -- (Chobby's caching words, mirrored: uprightMirror; at the strip's own y: with
			-- bottom = 0 they stood over the last row's first button)
			parent = upright.grid,
			x = dots * 1.2, y = rows * (GRID_ROW_H + GRID_GAP) - GRID_GAP, width = "38%", height = dots,
			autosize = false,
			caption = "",
			valign = "center",
			objectOverrideFont = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(1),
		})
	end
	local font = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(3)
	upright.mirror = {}
	upright.stripX = -upright.page * sw
	local w = (sw - (PAGE_COLS + 1) * GRID_GAP) / PAGE_COLS
	for i, f in ipairs(found) do
		local page, k = math.floor((i - 1) / perPage), (i - 1) % perPage
		local col, row = k % PAGE_COLS, math.floor(k / PAGE_COLS)
		local target = f.button
		local base = math.floor(page * sw + GRID_GAP + col * (w + GRID_GAP))
		local mine = Chili.Button:New({
			parent = upright.grid,
			x = base + upright.stripX, y = row * (GRID_ROW_H + GRID_GAP),
			width = math.floor(w), height = GRID_ROW_H,
			caption = target.caption,
			classname = target.classname == "negative_button" and "negative_button" or nil,
			objectOverrideFont = font,
			OnClick = { function() target:CallListeners(target.OnClick) end },
		})
		upright.mirror[#upright.mirror + 1] = { button = target, mine = mine, top = f.top, base = base }
	end
	upright.grid:BringToFront()
	local words = {}
	for i, f in ipairs(found) do
		words[i] = f.button.caption:gsub("\255...", "")
	end
	Spring.Echo(string.format("[bardroid-lobby] grid: %d buttons, %d a page, %d pages: %s", #found, perPage, pages,
		table.concat(words, " | "))) -- (tools)
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
	upright.anim = { from = upright.stripX, to = -upright.page * screen0.width, t = 0 }
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

local function uprightSet(on)
	local config = WG.Chobby and WG.Chobby.Configuration
	if on == upright.on then
		return
	end
	upright.on = on
	if on then
		if config and config.SetUiScale and (config.uiScale or 1) < SCALE_UPRIGHT then
			upright.scaleBefore = config.uiScale or 1
			config:SetUiScale(SCALE_UPRIGHT)
		end
		return -- (the grid at the next check: the screen at its new scale)
	end
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

-- The battle room upright (Kailil, 2026-11-10: "the selectors in a row of their own ... the space under the team lists
-- stands empty"). Chobby's room (gui_battle_room_window.lua) is three columns side by side: the teams (playerPanel, to
-- 48 %), its buttons, selectors and states (leftInfo, 48-67 %) and the map with Start (rightInfo, from 67 %). Upright the
-- middle one is a sliver: "Update Rea", "BAR-31836-b..", a map's "...ownload failed [fa", the online room's Autobalance,
-- BalanceMode and Preset crushed, their labels over their values. Upright the teams keep the left's top half, the middle
-- column goes under them as wide as the left (60 %), the map and Start keep the right; both re-lay their own children as
-- they resize (their OnResize). Done once to each room's columns (a new room: new columns).
local roomsLaidOut = setmetatable({}, { __mode = "k" })
local function uprightBattleRoom()
	-- (Chili hands out weak links, a new one each time: the real objects, to compare and to remember)
	local players, middle, right = real(chobbyObject("playerPanel")), real(chobbyObject("leftInfo")),
		real(chobbyObject("rightInfo"))
	if not (players and middle and right) or roomsLaidOut[middle] or middle.disposed
		or not (players._relativeBounds and middle._relativeBounds and right._relativeBounds)
		or real(players.parent) ~= real(middle.parent) or real(middle.parent) ~= real(right.parent) then
		return
	end
	roomsLaidOut[middle] = true
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
	Spring.Echo("[bardroid-lobby] battle room upright: the teams over its buttons and states, the map beside them") -- (tools)
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
	Spring.Echo("[bardroid-lobby] scenario page upright: values clear of their labels, the map narrower") -- (tools)
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
	local top = 13 + 2 * h + 4 + 6
	for _, c in ipairs(win.children or {}) do
		c = real(c)
		if c.name == "imKeys" and (c.y ~= top or c.x ~= 1) then
			c:SetPos(1, top, win.width - 20, win.height - top - 10)
			moved = true
		end
	end
	if moved then
		Spring.Echo("[bardroid-lobby] Keys window upright: its tabs in two rows of three") -- (tools)
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
	C._Realign = function(self, sorted)
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
			local key = table.concat(words(n.window, {}, 0), "|")
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
					win:SetPos(2, 6 + (row - 1) * 110, math.min(win.bardroidW, room))
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

local function uprightUpdate(now)
	if upright.checkAt and Spring.DiffTimers(now, upright.checkAt) < 0.5 then
		return
	end
	upright.checkAt = now
	if not (screen0 and WG.Chobby and WG.Chobby.interfaceRoot) then
		return
	end
	uprightNotes()
	uprightSet(not gameLoaded and screen0.height > screen0.width * UPRIGHT)
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
	uprightBattleRoom()
	uprightScenario()
	uprightKeys()
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
		press = { grid = true, x = x, y = y, start = upright.stripX, moved = false, lastX = x, lastT = Spring.GetTimer(),
			vel = 0, settling = upright.anim ~= nil }
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
		if not p.moved and math.abs(x - p.x) > DRAG_PX then
			p.moved = true
		end
		if p.moved and upright.grid then
			local s = uiScale()
			local nx, minX = p.start + (x - p.x) / s * PAGE_GAIN, -(upright.pages - 1) * screen0.width
			if nx > 0 then
				nx = nx / 3
			elseif nx < minX then
				nx = minX + (nx - minX) / 3
			end
			stripTo(nx)
			local now = Spring.GetTimer()
			local dt = Spring.DiffTimers(now, p.lastT)
			if dt > 0.001 then
				p.vel = p.vel * 0.6 + (x - p.lastX) / s / dt * 0.4
				p.lastX, p.lastT = x, now
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
			local w = math.max(1, screen0.width)
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
local function appLines()
	if not logFile then
		logFile = io.open(TOUCH_LOG, "r")
		logPos = logFile and logFile:seek("end")
		return nil
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
local voiceTextW = 0 -- its words' width, as the font measures them

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
				open = tabBar.selected == i, send = console.listener }
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
local VOICE_NOMIC = "SPEAK TO CHAT: ALLOW THE MICROPHONE IN ANDROID'S SETTINGS" -- (bardroid_pad.lua's in a game)
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
	end
	local target = not say and voiceCurrent(voiceTargets())
	local caption = say or target and ("< SPEAK TO " .. string.upper(target.name) .. " >")
		or "SPEAK TO CHAT: JOIN A SERVER OR OPEN THE CHAT"
	local font = voiceLabel.font
	local ok, textW = pcall(function() return font:GetTextWidth(caption) end)
	voiceTextW = ok and tonumber(textW) or 0
	local w = math.min(screen0.width - 16, math.max(640, math.ceil(voiceTextW) + 48)) -- (a long name: the panel grows)
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
				if voiceOn then
					voiceNoteAt = nil
					voiceShow()
				end
			elseif name == "voice_nomic" then
				if not gameLoaded then
					voiceShow(VOICE_NOMIC)
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
-- manager shows; LobbyBridge's OpenFile leaves folders), a button that did nothing at a tap (dev phone, 2026-11-12).
-- Hidden, and the two left of it (Download, More: Chobby anchors the row from the right, 130 apart) close the gap.
-- The same for Links' last line, "Game Data: Open game data folder to find config files and logs." (WrapperLoopback's
-- OpenFolder; on a phone the launcher's Share logs gives the logs): the line hidden, the last, so no gap.
-- And Plugins' "Widgets Folder" (the first of its row: Contribute and Refresh move left into its place).
local replaysRow = { at = nil, done = false, linksDone = false, pluginsDone = false }
local function replaysRowCheck(now)
	if (replaysRow.done and replaysRow.linksDone and replaysRow.pluginsDone)
		or (replaysRow.at and Spring.DiffTimers(now, replaysRow.at) < 1) then
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
	local bar = widgetsFolder and real(widgetsFolder.parent)
	if bar then
		local x0, y0, step = widgetsFolder.x, widgetsFolder.y, nil
		for _, c in ipairs(bar.children or {}) do -- (the next one along: how far each moves)
			if c ~= widgetsFolder and c.y == y0 and c.x > x0 and (not step or c.x - x0 < step) then
				step = c.x - x0
			end
		end
		widgetsFolder:SetVisibility(false)
		for _, c in ipairs(bar.children or {}) do
			-- (Contribute and Refresh, the next two: the search box on the same row, at its right, stays)
			if step and c ~= widgetsFolder and c.y == y0 and c.x > x0 and c.x < x0 + 2.5 * step
				and type(c.caption) == "string" and c.caption ~= "" and c.SetPos then
				c:SetPos(c.x - step)
			end
		end
		replaysRow.pluginsDone = true
		Spring.Echo("[bardroid-lobby] Plugins: Widgets Folder hidden (no folder to open on Android)") -- (tools)
	end
	local row = not replaysRow.done and refresh and real(refresh.parent)
	if not row then
		return
	end
	local function rightOf(o)
		return o._relativeBounds and o._relativeBounds.right
	end
	for _, c in ipairs(row.children or {}) do
		local r = rightOf(c)
		if r == 145 and c ~= refresh and c.classname == "option_button" then
			c:SetVisibility(false)
		end
	end
	for _, c in ipairs(row.children or {}) do
		local r = rightOf(c)
		if (r == 275 or r == 405) and c.classname == "option_button" then
			c._relativeBounds.right = r - 130
			c:UpdateClientArea()
		end
	end
	replaysRow.done = true
	Spring.Echo("[bardroid-lobby] Replays: Open Folder hidden (no folder to open on Android)") -- (tools)
end

function widget:Update() -- (the lobby's Update has no frame time)
	local now = Spring.GetTimer()
	local dt = lastUpdate and math.min(0.1, Spring.DiffTimers(now, lastUpdate)) or 0
	lastUpdate = now
	poolCacheCheck(now)
	if screen0 and not gameLoaded then -- (no walks of the lobby's controls while a game runs)
		replaysRowCheck(now)
	end
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
	elseif popupButton and barSize ~= screen0.width .. "x" .. screen0.height then
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
		upright = function() return upright.on end, -- (tools: the lobby test, upright or sideways)
		barTop = function() return uprightBarTop and uprightBarTop() end, -- (upright: where the server bar stands on)
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
