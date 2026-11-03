-- BAR Droid layout editor (Kailil, 2026-10-28: "a tool to select ui elements on screen while in a real game both in
-- spectator mode and when actually playing. It will allow me to enter the ui scaling adjustment mode where I tap A ui
-- element, to adjust its size, position, and if possible, text size inside of it and padding").
-- Opens with three fingers held on the screen (RtsTouch "act hud"), "/hud" typed in the chat (bardroid_chat.lua) or
-- WG.BarDroidLayout.open(). Every panel shows its outline and name; a tap picks one, a drag moves it, a pinch (or the
-- buttons) sizes it; Done, Escape or three fingers again close the editor.
-- How far each panel goes depends on whose it is. The app's own (chat, unit info, the spectate bar) move and take
-- another size, text size and padding. BAR's own only as far as BAR lets another widget change them (its sandbox keeps
-- user widgets out of BAR's code): the minimap's and the player list's size. BAR's top bar (metal, energy, wind) and
-- its build and order menus have no setting for it: shown as fixed (their size follows the interface scale); BAR's
-- start countdown neither (the chat keeps clear of it). The editor's first version also put BAR's menus at the bottom
-- or the left (their own setting, setBottomPosition): BAR's older build menu, the controller game's, failed drawing
-- after the switch (gui_buildmenu.lua:1398, a cell without its command) and BAR removed it until the next start.
-- A movable HUD for BAR's own panels is BAR's to add (docs/HELP-WANTED.md).
-- The settings are kept per screen shape (wide: a phone folded; near-square: unfolded) in this widget's config.
-- Panels ask WG.BarDroidLayout.get(id) for theirs ({ dx, dy: moved, of the screen; size; text; pad }) and
-- register to be edited: register(id, { label, can = { move, size, text, pad }, rect = function() -> x0, y0, x1, y1,
-- relayout = function() }). Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid layout",
		desc = "Move and size the interface's panels (three fingers held, or /hud in the chat)",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -2000000, -- (first to hear the pointer and keys while open, drawn over everything)
		enabled = true,
	}
end

local SIZE_STEP, TEXT_STEP, PAD_STEP = 1.08, 1.08, 0.25
local SIZE_MIN, SIZE_MAX, TEXT_MIN, TEXT_MAX, PAD_MAX = 0.4, 2.5, 0.5, 2, 3
local DEFAULTS = { dx = 0, dy = 0, size = 1, text = 1, pad = 1 }
local YELLOW, GREY = { 1, 0.85, 0.2 }, { 0.65, 0.65, 0.65 }

local panels, order = {}, {} -- id -> { label, can, rect, relayout }; the ids in order
local saved = { wide = {}, square = {} } -- screen shape -> id -> settings
local isOpen, picked = false, nil
local drag -- { x, y: the press; dx, dy: the panel's then }
local buttons = {} -- the control bar's: { x0, y0, x1, y1, label, action, lit }
local vsx, vsy = Spring.GetViewGeometry()

local function shape()
	local w, h = Spring.GetViewGeometry() -- (the panels ask in their own ViewResize, maybe before this widget's)
	return w * 10 < h * 16 and "square" or "wide" -- (as launch-bar.sh: the inner screen near-square, the cover wide)
end

local function get(id)
	return saved[shape()][id] or DEFAULTS
end

local function edit(id)
	local all = saved[shape()]
	local s = all[id]
	if not s then
		s = { dx = 0, dy = 0, size = 1, text = 1, pad = 1 }
		all[id] = s
	end
	return s
end

local function relayout(id)
	local p = panels[id]
	if p and p.relayout then
		p.relayout()
	end
end

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

local function register(id, def)
	if not panels[id] then
		order[#order + 1] = id
	end
	panels[id] = def
	if def.relayout and saved[shape()][id] then -- (laid out before it knew of the editor: its settings now)
		def.relayout()
	end
end

local function unregister(id)
	panels[id] = nil
	for i, o in ipairs(order) do
		if o == id then
			table.remove(order, i)
			break
		end
	end
	if picked == id then
		picked = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- BAR's own panels that take no setting from another widget: shown, fixed

local function infoRight()
	local w = WG.info and WG.info.getPosition and WG.info.getPosition()
	return w and w * vsx or vsx * 0.2
end

local function registerBar()
	register("topbar", {
		label = "Top bar (BAR's: fixed)",
		can = {},
		rect = function()
			local p = WG.topbar and WG.topbar.GetPosition and WG.topbar.GetPosition()
			if type(p) == "table" and p[4] then
				return p[1], p[2], p[3], p[4] -- left, bottom, right, top
			end
		end,
	})
	register("ordermenu", {
		label = "Order menu (BAR's: fixed)",
		can = {},
		rect = function()
			local o = WG.ordermenu
			if o and o.getPosition and o.getIsShowing and o.getIsShowing() then
				local x, y, w, h = o.getPosition()
				if x and h then
					return x * vsx, (y - h) * vsy, (x + w) * vsx, y * vsy
				end
			end
		end,
	})
	-- (its own id: the app's copy of BAR's Build menu is "buildmenu", sizeable, and outlined only while it shows; the
	-- controller game with v0.8.5's controls shows v0.8.5's in its place, which had no outline at all)
	register("barbuildmenu", {
		label = "Build menu (BAR's: fixed)",
		can = {},
		rect = function()
			local own = panels.buildmenu
			if own and own.rect and own.rect() then
				return nil
			end
			local b = WG.buildmenu
			if not (b and b.getSize and b.getIsShowing and b.getIsShowing()) then
				return nil
			end
			local y0, y1 = b.getSize()
			if not (y0 and y1) then
				return nil
			end
			if y1 <= 1 then -- (the old build menu: fractions of the screen)
				y0, y1 = y0 * vsy, y1 * vsy
			end
			y0, y1 = math.min(y0, y1), math.max(y0, y1)
			-- BAR tells no width: at the bottom it sits right of the order menu, at the left as wide as the unit panel
			if b.getBottomPosition and b.getBottomPosition() then
				local x0 = infoRight()
				local o = WG.ordermenu
				if o and o.getPosition and o.getBottomPosition and o.getBottomPosition() then
					local x, _, w = o.getPosition()
					x0 = (x + w) * vsx
				end
				return x0, y0, math.min(vsx, x0 + (y1 - y0) * 3), y1
			end
			return 0, y0, infoRight(), y1
		end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- The editor

local function rectOf(id)
	local p = panels[id]
	if not (p and p.rect) then
		return nil
	end
	local ok, x0, y0, x1, y1 = pcall(p.rect)
	if ok and x0 and y1 and x1 > x0 and y1 > y0 then
		return x0, y0, x1, y1
	end
end

local function editable(p)
	local c = p.can or {}
	return c.move or c.size or c.text or c.pad
end

-- the panel under a point: the one picked if it is there, else the smallest
local function panelAt(x, y)
	local best, area
	for _, id in ipairs(order) do
		local x0, y0, x1, y1 = rectOf(id)
		if x0 and x >= x0 and x <= x1 and y >= y0 and y <= y1 then
			if id == picked then
				return id
			end
			local a = (x1 - x0) * (y1 - y0)
			if not area or a < area then
				best, area = id, a
			end
		end
	end
	return best
end

local function percent(v)
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

-- the room the panels leave between the screen's left and right at heights ya to yb: the panels on the left half end
-- before it, those on the right half start after it
local function freeSpan(ya, yb)
	local lo, hi = 0, vsx
	for _, id in ipairs(order) do
		local x0, y0, x1, y1 = rectOf(id)
		if x0 and y0 < yb and y1 > ya then
			if (x0 + x1) / 2 < vsx / 2 then lo = math.max(lo, x1) else hi = math.min(hi, x0) end
		end
	end
	return lo, hi
end

-- the control bar: the panel picked and what can change, Reset and Done
local function layoutButtons()
	local h = math.floor(math.min(vsy * 0.075, vsx / 18))
	local gap = math.floor(h * 0.15)
	local row = {}
	local p = picked and panels[picked]
	if p then
		local s, c = get(picked), p.can or {}
		row[#row + 1] = { w = h * 3.4, label = p.label, lit = true }
		-- (join: kept in one row with the button before it, a "- value +" never split)
		if c.size then
			row[#row + 1] = { w = h, label = "-", action = "size-" }
			row[#row + 1] = { w = h * 2.2, label = "Size " .. percent(s.size), join = true }
			row[#row + 1] = { w = h, label = "+", action = "size+", join = true }
		end
		if c.text then
			row[#row + 1] = { w = h, label = "-", action = "text-" }
			row[#row + 1] = { w = h * 2.2, label = "Text " .. percent(s.text), join = true }
			row[#row + 1] = { w = h, label = "+", action = "text+", join = true }
		end
		if c.pad then
			row[#row + 1] = { w = h, label = "-", action = "pad-" }
			row[#row + 1] = { w = h * 2.4, label = "Padding " .. percent(s.pad), join = true }
			row[#row + 1] = { w = h, label = "+", action = "pad+", join = true }
		end
		if editable(p) then
			row[#row + 1] = { w = h * 1.6, label = "Reset", action = "reset" }
		else
			row[#row + 1] = { w = h * 6, label = "BAR has no setting for it" }
		end
	else
		row[#row + 1] = { w = h * 6.5, label = "Tap a panel, drag to move, pinch to size" }
		row[#row + 1] = { w = h * 2, label = "Reset all", action = "resetall" }
	end
	row[#row + 1] = { w = h * 1.6, label = "Done", action = "done", lit = true }
	-- each button at least as wide as its words (the hint ran out of its box)
	local font = WG.fonts and WG.fonts.getFont()
	if font then
		for _, b in ipairs(row) do
			b.w = math.max(b.w, math.ceil(font:GetTextWidth(b.label) * h * 0.38 + h * 0.6))
		end
	end
	-- rows no wider than the room the panels leave in the middle of the screen, where they go, if that is half the
	-- screen at least, else than the screen (one row of a picked panel's buttons crossed the build menu, 2026-11-03)
	local lo, hi = freeSpan(vsy / 2 - h * 1.5, vsy / 2 + h * 1.5)
	local maxW = hi - lo - 2 * gap
	if maxW < vsx * 0.5 then
		maxW = vsx - 2 * gap
	end
	local groups = {}
	for _, b in ipairs(row) do
		if b.join and #groups > 0 then
			local g = groups[#groups]
			g[#g + 1] = b
			g.w = g.w + gap + b.w
		else
			groups[#groups + 1] = { b, w = b.w }
		end
	end
	local rows, current, width = {}, {}, 0
	for _, g in ipairs(groups) do
		if #current > 0 and width + gap + g.w > maxW then
			rows[#rows + 1], current, width = current, {}, 0
		end
		width = width + (#current > 0 and gap or 0) + g.w
		for _, b in ipairs(g) do
			current[#current + 1] = b
		end
	end
	rows[#rows + 1] = current
	-- in the middle of the screen (the panels sit at its edges), else just above or below the panel picked
	buttons = {}
	local total = #rows * h + (#rows - 1) * gap
	local top = math.floor((vsy + total) / 2)
	if picked then
		local _, y0, _, y1 = rectOf(picked)
		if y0 and top - total < y1 + gap and top > y0 - gap then
			if y1 + gap + total <= vsy * 0.92 then
				top = math.floor(y1 + gap + total)
			else
				top = math.floor(math.max(total + gap, y0 - gap))
			end
		end
	end
	local y = top - h
	for _, r in ipairs(rows) do
		local w = 0
		for i, b in ipairs(r) do
			w = w + b.w + (i > 1 and gap or 0)
		end
		-- centred in the room the panels leave at its height, else on the screen (the hint crossed the build menu's last
		-- column on a phone's wide screen, 2026-11-02)
		lo, hi = freeSpan(y, y + h)
		local x = hi - lo >= w + 2 * gap and math.floor(lo + (hi - lo - w) / 2) or math.floor((vsx - w) / 2)
		for _, b in ipairs(r) do
			buttons[#buttons + 1] = { x0 = x, y0 = y, x1 = x + b.w, y1 = y + h, label = b.label, action = b.action,
				lit = b.lit, size = h }
			x = x + b.w + gap
		end
		y = y - h - gap
	end
end

-- While open the editor owns the keys (widgetHandler:OwnText): BAR's widget handler runs its hotkeys before any other
-- widget hears a key, so Escape and the rest would have gone to the game.
local ownsText = false

local function open()
	if isOpen then
		return
	end
	isOpen, picked, drag = true, nil, nil
	ownsText = widgetHandler:OwnText()
	layoutButtons()
	Spring.Echo("[bardroid-layout] open")
end

local function close()
	if ownsText then
		widgetHandler:DisownText()
		ownsText = false
	end
	isOpen, picked, drag = false, nil, nil
	Spring.Echo("[bardroid-layout] closed")
end

local function act(action)
	local id = picked
	local can = id and panels[id] and panels[id].can or {}
	local s = (can.size or can.text or can.pad) and edit(id)
	if action == "done" then
		close()
		return
	elseif action == "resetall" then
		saved[shape()] = {}
		for _, o in ipairs(order) do
			relayout(o)
		end
	elseif action == "reset" and id then
		saved[shape()][id] = nil
		relayout(id)
	elseif s then
		if action == "size+" or action == "size-" then
			s.size = clamp(s.size * (action == "size+" and SIZE_STEP or 1 / SIZE_STEP), SIZE_MIN, SIZE_MAX)
		elseif action == "text+" or action == "text-" then
			s.text = clamp(s.text * (action == "text+" and TEXT_STEP or 1 / TEXT_STEP), TEXT_MIN, TEXT_MAX)
		elseif action == "pad+" or action == "pad-" then
			s.pad = clamp(s.pad + (action == "pad+" and PAD_STEP or -PAD_STEP), 0, PAD_MAX)
		end
		relayout(id)
	end
	layoutButtons()
end

local function buttonAt(x, y)
	for _, b in ipairs(buttons) do
		if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 then
			return b
		end
	end
end

function widget:MousePress(x, y, button)
	if not isOpen then
		return false
	end
	if button ~= 1 then
		return true
	end
	local b = buttonAt(x, y)
	if b then
		if b.action then
			act(b.action)
		end
		return true
	end
	picked = panelAt(x, y)
	local p = picked and panels[picked]
	if p and p.can and p.can.move then
		local s = get(picked)
		drag = { x = x, y = y, dx = s.dx, dy = s.dy }
	end
	layoutButtons()
	return true
end

function widget:MouseMove(x, y)
	if not (isOpen and drag and picked) then
		return
	end
	local s = edit(picked)
	s.dx = clamp(drag.dx + (x - drag.x) / vsx, -1, 1)
	s.dy = clamp(drag.dy + (y - drag.y) / vsy, -1, 1)
	relayout(picked)
end

function widget:MouseRelease()
	if drag then
		drag = nil
		layoutButtons()
	end
end

function widget:MouseWheel(up)
	if not isOpen then
		return false
	end
	local p = picked and panels[picked]
	if p and p.can and p.can.size then
		act(up and "size+" or "size-")
	end
	return true
end

function widget:KeyPress(key)
	if not isOpen then
		return false
	end
	if key == 27 then -- Escape
		close()
	end
	return true -- (no hotkeys while the panels are being edited)
end

function widget:IsAbove()
	return isOpen -- (bardroid_touch.lua then tells the app the whole screen is interface: a drag drags, not pans)
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	if isOpen then
		layoutButtons()
	end
end

local function outline(x0, y0, x1, y1, color, width, fill)
	if fill then
		gl.Color(color[1], color[2], color[3], fill)
		gl.Rect(x0, y0, x1, y1)
	end
	gl.Color(color[1], color[2], color[3], 0.95)
	gl.Rect(x0, y0, x1, y0 + width)
	gl.Rect(x0, y1 - width, x1, y1)
	gl.Rect(x0, y0, x0 + width, y1)
	gl.Rect(x1 - width, y0, x1, y1)
end

-- (where no room is left beside the panels the bar crosses one: nothing shows through its words; at 0.85-0.92 the build
-- menu's pictures still did, dev phone 2026-11-03)
local BAR_HINT, BAR_BUTTON, BAR_LIT = { 0.02, 0.02, 0.02, 0.96 }, { 0.08, 0.08, 0.08, 0.97 }, { 0.25, 0.22, 0.06, 0.97 }
local BAR_TAB = { 0, 0, 0, 0.7 }

function widget:DrawScreen()
	if not isOpen then
		return
	end
	local font = WG.fonts and WG.fonts.getFont()
	gl.Color(0, 0, 0, 0.18)
	gl.Rect(0, 0, vsx, vsy)
	local labelSize = math.floor(math.min(vsy * 0.075, vsx / 18) * 0.36)
	local th = labelSize * 1.5
	for _, id in ipairs(order) do
		local x0, y0, x1, y1 = rectOf(id)
		if x0 then
			local p = panels[id]
			local color = editable(p) and YELLOW or GREY
			outline(x0, y0, x1, y1, color, id == picked and 4 or 2, id == picked and 0.18 or nil)
			if font then
				local w = font:GetTextWidth(p.label) * labelSize + labelSize
				local lx = math.max(0, math.min(x0, vsx - w))
				-- a tab on the panel's top edge, outside, where that is on the screen and on no other panel (inside, the
				-- label covered the panel's own first line: the order menu's Fire at will); else on its bottom edge,
				-- outside (the chat, under BAR's top bar); else in its top left corner
				-- (at the panel's left end, else at its right end: the build menu reaches under the chat's left end)
				local function free(top)
					if top > vsy or top - th < 0 then
						return false
					end
					for _, x in ipairs({ lx, math.max(0, math.min(x1, vsx) - w) }) do
						local clear = true
						for _, other in ipairs(order) do
							local ox0, oy0, ox1, oy1 = rectOf(other)
							if other ~= id and ox0 and ox0 < x + w and ox1 > x and oy0 < top and oy1 > top - th then
								clear = false
							end
						end
						if clear then
							lx = x
							return true
						end
					end
					return false
				end
				local above = free(y1 + th)
				local below = not above and free(y0)
				local ly = above and y1 + th or below and y0 or math.min(y1, vsy) -- (the tab's top)
				local f = WG.FlowUI
				if f and f.Draw and f.Draw.RectRound then
					local cs = f.elementCorner or 4
					if above then
						f.Draw.RectRound(lx, ly - th, lx + w, ly, cs, 1, 1, 0, 0, BAR_TAB, BAR_TAB)
					elseif below then
						f.Draw.RectRound(lx, ly - th, lx + w, ly, cs, 0, 0, 1, 1, BAR_TAB, BAR_TAB)
					else
						f.Draw.RectRound(lx, ly - th, lx + w, ly, cs, 0, 0, 1, 0, BAR_TAB, BAR_TAB)
					end
				else
					gl.Color(BAR_TAB)
					gl.Rect(lx, ly - th, lx + w, ly)
				end
				font:Begin()
				font:SetTextColor(1, 1, 1, 1) -- (else what the last widget left)
				font:SetOutlineColor(0, 0, 0, 0.8)
				font:Print(p.label, lx + labelSize * 0.5, ly - labelSize * 1.15, labelSize, "o")
				font:End()
			end
		end
	end
	for _, b in ipairs(buttons) do
		local c = not b.action and BAR_HINT or b.lit and BAR_LIT or BAR_BUTTON
		local f = WG.FlowUI
		if f and f.Draw and f.Draw.RectRound then
			f.Draw.RectRound(b.x0, b.y0, b.x1, b.y1, f.elementCorner or 4, 1, 1, 1, 1, c, c)
		else
			gl.Color(c)
			gl.Rect(b.x0, b.y0, b.x1, b.y1)
		end
		if font then
			font:Begin()
			font:Print((b.lit and "\255\255\225\110" or "\255\235\235\235") .. b.label, (b.x0 + b.x1) / 2,
				b.y0 + (b.y1 - b.y0) * 0.32, b.size * 0.38, "oc")
			font:End()
		end
	end
	gl.Color(1, 1, 1, 1)
end

function widget:Initialize()
	vsx, vsy = Spring.GetViewGeometry()
	registerBar()
	WG.BarDroidLayout = {
		get = get,
		register = register,
		unregister = unregister,
		open = open,
		close = close,
		toggle = function()
			if isOpen then
				close()
			else
				open()
			end
		end,
		isOpen = function() return isOpen end,
		-- a pinch while open (bardroid_touch.lua): the panel picked takes the fingers' size change
		pinch = function(ratio)
			local p = picked and panels[picked]
			if p and p.can and p.can.size and ratio and ratio > 0 then
				local s = edit(picked)
				s.size = clamp(s.size * ratio, SIZE_MIN, SIZE_MAX)
				relayout(picked)
				layoutButtons()
			end
		end,
		-- (tools/touch-widget-test.ps1: taps and drags without a finger, the editor's state)
		press = function(x, y) return widget:MousePress(x, y, 1) end,
		move = function(x, y) widget:MouseMove(x, y) end,
		release = function() widget:MouseRelease() end,
		act = act,
		picked = function() return picked end,
		ownsText = function() return ownsText end,
		rect = rectOf,
		ids = function() return order end,
		buttons = function() return buttons end,
	}
end

function widget:Shutdown()
	close()
	WG.BarDroidLayout = nil
end

function widget:GetConfigData()
	return { saved = saved }
end

function widget:SetConfigData(data)
	local s = type(data) == "table" and data.saved
	if type(s) == "table" then
		saved.wide = type(s.wide) == "table" and s.wide or {}
		saved.square = type(s.square) == "table" and s.square or {}
		for _, all in pairs(saved) do
			for id, v in pairs(all) do
				if type(v) ~= "table" then
					all[id] = nil
				else
					for k, d in pairs(DEFAULTS) do
						v[k] = tonumber(v[k]) or d
					end
					v.bottom = nil -- (the first version's menu placement, gone)
				end
			end
		end
	end
end
