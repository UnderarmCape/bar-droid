-- BAR Droid touch action dock (touch-only mode, see TOUCH-UI.md): what phone RTS games put at the bottom of the
-- screen for the selected units. A row of selection cards (unit picture and count: tap = keep only that type, long
-- press = drop that type, X = deselect all) and a command bar with the selection's commands as big labelled buttons
-- (tap an order to arm it and tap or drag on the map; tap it again to put it away; states cycle with a tap, back with
-- a long press). Drawn over BAR's order menu while fingers are in use; with a mouse, keyboard or gamepad it steps
-- aside. Installed into LuaUI/Widgets by the app only in touch-only mode.

function widget:GetInfo()
	return {
		name = "BAR Droid touch dock",
		desc = "Selection cards and a big command bar for touch-only play (BAR Droid)",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -10, -- over BAR's order menu (layer 1), under its windows, top bar and chat
		enabled = true,
	}
end

local TOUCHUI = "LuaUI/Config/bardroid_touchui.txt"
local BUTTON_MM, CARD_MM, GAP_MM, MARGIN_MM, LABEL_MM = 9.5, 8.5, 1.2, 1.5, 2.5
local MAX_COMMAND_ROWS = 2 -- 3 on a tall screen (the unfolded inner display)
local REFRESH_SECONDS = 0.25

local spGetActiveCmdDescs = Spring.GetActiveCmdDescs
local spGetActiveCommand = Spring.GetActiveCommand
local spSetActiveCommand = Spring.SetActiveCommand
local spGetCmdDescIndex = Spring.GetCmdDescIndex
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetSelectedUnits = Spring.GetSelectedUnits
local spSelectUnitArray = Spring.SelectUnitArray
local spGetModKeyState = Spring.GetModKeyState
local spGetViewGeometry = Spring.GetViewGeometry
local spIsGUIHidden = Spring.IsGUIHidden
local glColor = gl.Color
local glRect = gl.Rect
local glTexture = gl.Texture
local glTexRect = gl.TexRect

-- Commands BAR's order menu leaves out too (gui_ordermenu.lua hiddenCommands), and the order the bar shows them in.
local HIDDEN = {
	[CMD.LOAD_ONTO] = true,
	[CMD.SELFD] = true,
	[CMD.GATHERWAIT] = true,
	[CMD.SQUADWAIT] = true,
	[CMD.DEATHWAIT] = true,
	[CMD.TIMEWAIT] = true,
	[CMD.AUTOREPAIRLEVEL] = true,
	[39812] = true, -- raw move
	[34922] = true, -- set unit target (no ground)
}
local HIDDEN_TYPES = { [CMDTYPE.CUSTOM] = true, [CMDTYPE.PREV] = true, [CMDTYPE.NEXT] = true }
local FIRST = {
	CMD.MOVE,
	CMD.FIGHT,
	CMD.ATTACK,
	CMD.MANUALFIRE,
	CMD.STOP,
	CMD.REPAIR,
	CMD.RECLAIM,
	CMD.PATROL,
	CMD.GUARD,
	CMD.WAIT,
	CMD.RESURRECT,
	CMD.CAPTURE,
	CMD.LOAD_UNITS,
	CMD.UNLOAD_UNITS,
}
local rank = {}
for i, id in ipairs(FIRST) do
	rank[id] = i
end
local SHORT = { -- labels that fit a button
	[CMD.MANUALFIRE] = "D-GUN",
	[CMD.LOAD_UNITS] = "LOAD",
	[CMD.UNLOAD_UNITS] = "UNLOAD",
	[CMD.RESURRECT] = "REZ",
}

local vsx, vsy = 1, 1
local touchOnly, pxmm, input = true, nil, "touch"
local cards, commands = {}, {} -- { udid, units } ; { id, type, label, state }
local buttons = {} -- { x1, y1, x2, y2, kind, value }
local rect -- the dock, when shown
local refreshTimer = 0
local page = 1 -- of the command bar, when MORE is needed
local font
local flash, flashTime = nil, 0
local shared = { rect = nil }

local function readTouchUi()
	local f = io.open(TOUCHUI, "r")
	if not f then
		return
	end
	local s = f:read("*l")
	f:close()
	local m, mm, used = (s or ""):match("^(%d) ([%d%.]+) ?(%a*)")
	if m then
		touchOnly, pxmm, input = m == "1", tonumber(mm), used ~= "" and used or "touch"
	end
end

local function translate(key, fallback)
	if BAR and BAR.I18N then
		local ok, s = pcall(BAR.I18N, key)
		if ok and type(s) == "string" and s ~= "" and s ~= key and not s:find("^%[") then
			return s
		end
	end
	return fallback
end

local function commandLabel(cmd)
	if cmd.type == CMDTYPE.ICON_MODE then
		local state = tonumber(cmd.params and cmd.params[1]) or 0
		local name = cmd.params and cmd.params[state + 2]
		return (name or cmd.name or "?"):upper()
	end
	return SHORT[cmd.id] or translate("commands." .. tostring(cmd.action), cmd.name or "?"):upper()
end

local function refresh()
	cards, commands = {}, {}
	local sorted = spGetSelectedUnitsSorted() or {}
	for udid, units in pairs(sorted) do
		if type(udid) == "number" and type(units) == "table" and UnitDefs[udid] then
			cards[#cards + 1] = { udid, units }
		end
	end
	table.sort(cards, function(a, b)
		if #a[2] ~= #b[2] then
			return #a[2] > #b[2]
		end
		return a[1] < b[1]
	end)
	if #cards == 0 then
		return
	end
	local orders, states = {}, {}
	for _, cmd in ipairs(spGetActiveCmdDescs() or {}) do
		if
			type(cmd) == "table"
			and cmd.id >= 0
			and not cmd.hidden
			and not cmd.disabled
			and not HIDDEN[cmd.id]
			and not HIDDEN_TYPES[cmd.type]
			and cmd.type ~= CMDTYPE.ICON_BUILDING
			and cmd.action
			and not cmd.action:find("^buildunit_")
		then
			local entry = { cmd.id, cmd.type, commandLabel(cmd) }
			if cmd.type == CMDTYPE.ICON_MODE then
				states[#states + 1] = entry
			else
				orders[#orders + 1] = entry
			end
		end
	end
	table.sort(orders, function(a, b)
		local ra, rb = rank[a[1]] or 1000, rank[b[1]] or 1000
		if ra ~= rb then
			return ra < rb
		end
		return a[1] < b[1]
	end)
	for _, e in ipairs(orders) do
		commands[#commands + 1] = e
	end
	for _, e in ipairs(states) do
		commands[#commands + 1] = e
	end
end

-- Layout ---------------------------------------------------------------------------------------------------------------

local function topOf(api)
	local ok, p = pcall(api)
	if ok and type(p) == "table" and type(p[1]) == "number" then
		return p[1], p[2]
	end
end

-- Between the build drawer (or BAR's info panel) and the touch rail (or BAR's player list).
local function span(margin)
	local left, right = margin, vsx - margin
	local build = WG.bardroidTouchBuild and WG.bardroidTouchBuild.rect
	if build then
		left = build[3] + margin
	elseif WG.info and WG.info.getPosition and WG.info.getIsShowing and WG.info.getIsShowing() then
		local ok, w = pcall(WG.info.getPosition)
		if ok and type(w) == "number" and w < vsx / 2 then
			left = w + margin
		end
	end
	local hud = WG.bardroidTouchHud and WG.bardroidTouchHud.railLeft
	if hud then
		right = math.min(right, hud - margin)
	end
	return left, right
end

local function layout()
	buttons, rect = {}, nil
	if #cards == 0 then
		return
	end
	local mm = pxmm or (vsy / 75)
	local margin, gap = math.floor(MARGIN_MM * mm + 0.5), math.floor(GAP_MM * mm + 0.5)
	local bh, ch = math.floor(BUTTON_MM * mm + 0.5), math.floor(CARD_MM * mm + 0.5)
	local bw = math.floor(bh * 1.2)
	local left, right = span(margin)
	-- BAR's bottom-right panels (player list...) reach into the dock's rows?
	for _, name in ipairs({ "advplayerlist_api", "displayinfo", "unittotals" }) do
		local api = WG[name] and WG[name].GetPosition
		local t, l = nil, nil
		if api then
			t, l = topOf(api)
		end
		if t and l and t < vsy * 0.5 and l > left then
			right = math.min(right, l - margin)
		end
	end
	local width = right - left
	if width < 3 * bw then
		return
	end
	local perRow = math.max(1, math.floor((width + gap) / (bw + gap)))
	local active = select(2, spGetActiveCommand())
	local list = {}
	for _, c in ipairs(commands) do
		list[#list + 1] = c
	end
	if active and active >= 0 then
		list[#list + 1] = { "cancel" } -- put the armed order away
	end
	local maxRows = vsy > 1000 and MAX_COMMAND_ROWS + 1 or MAX_COMMAND_ROWS
	local rows = math.min(maxRows, math.max(1, math.ceil(#list / perRow)))
	local slots = rows * perRow
	if #list > slots then -- pages, the last slot of each is MORE
		local perPage = slots - 1
		local pages = math.ceil(#list / perPage)
		page = math.min(page, pages)
		local paged = {}
		for i = (page - 1) * perPage + 1, math.min(#list, page * perPage) do
			paged[#paged + 1] = list[i]
		end
		paged[slots] = { "more", page .. "/" .. pages }
		for i = #paged + 1, slots - 1 do
			paged[i] = false
		end
		list = paged
	else
		page = 1
	end
	local shownCommands = math.min(#list, slots)
	local used = math.min(perRow, math.max(#list, 1))
	local dockW = math.max(used * (bw + gap) - gap, math.min(width, (#cards + 1) * (ch + gap)))
	local x0 = math.floor(left + (width - dockW) / 2)
	local y = margin
	-- commands, bottom row first
	for i = 1, shownCommands do
		local r = math.floor((i - 1) / perRow)
		local c = (i - 1) % perRow
		local bx = x0 + c * (bw + gap)
		local by = y + (rows - 1 - r) * (bh + gap)
		local e = list[i]
		if not e then -- luacheck: ignore 542 (an empty slot before MORE)
		elseif e[1] == "cancel" or e[1] == "more" then
			buttons[#buttons + 1] = { bx, by, bx + bw, by + bh, e[1], e[2] }
		else
			buttons[#buttons + 1] = { bx, by, bx + bw, by + bh, "command", e }
		end
	end
	y = y + rows * (bh + gap)
	-- cards
	local cw = ch
	local maxCards = math.max(1, math.floor((dockW + gap) / (cw + gap)) - 1)
	for i = 1, math.min(#cards, maxCards) do
		local bx = x0 + (i - 1) * (cw + gap)
		buttons[#buttons + 1] = { bx, y, bx + cw, y + ch, "card", cards[i] }
	end
	local bx = x0 + math.min(#cards, maxCards) * (cw + gap)
	buttons[#buttons + 1] = { bx, y, bx + cw, y + ch, "deselect" }
	rect = { x0 - gap, margin - gap, x0 + dockW + gap, y + ch + gap, mm = mm }
end

local function shown()
	return touchOnly and input == "touch" and rect ~= nil and not spIsGUIHidden()
end

local function hit(x, y)
	if not shown() then
		return nil
	end
	for _, b in ipairs(buttons) do
		if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
			return b
		end
	end
	if x >= rect[1] and x <= rect[3] and y >= rect[2] and y <= rect[4] then
		return { rect[1], rect[2], rect[3], rect[4], "panel" }
	end
end

-- Actions --------------------------------------------------------------------------------------------------------------

local function useCommand(e, button)
	local id, ctype = e[1], e[2]
	local index = spGetCmdDescIndex(id)
	if not index then
		return
	end
	local alt, ctrl, meta, shift = spGetModKeyState()
	if ctype == CMDTYPE.ICON_MODE then
		if button == 3 then
			spSetActiveCommand(index, 3, false, true, alt, ctrl, meta, shift) -- state back
		else
			spSetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
		end
	elseif button == 1 then
		if select(2, spGetActiveCommand()) == id then
			spSetActiveCommand(nil) -- tapped again: put it away
		else
			spSetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
		end
	end
	refreshTimer = 0
end

local function press(b, button)
	local kind, value = b[5], b[6]
	if kind == "command" then
		useCommand(value, button)
	elseif kind == "card" then
		if button == 3 then -- drop this type from the selection
			local drop = {}
			for _, u in ipairs(value[2]) do
				drop[u] = true
			end
			local keep = {}
			for _, u in ipairs(spGetSelectedUnits() or {}) do
				if not drop[u] then
					keep[#keep + 1] = u
				end
			end
			spSelectUnitArray(keep)
		else
			spSelectUnitArray(value[2]) -- only this type
		end
	elseif kind == "deselect" and button == 1 then
		spSelectUnitArray({})
	elseif kind == "cancel" and button == 1 then
		spSetActiveCommand(nil)
	elseif kind == "more" and button == 1 then
		page = page + 1 -- layout wraps it round
		local slash = value and value:find("/")
		if slash and page > tonumber(value:sub(slash + 1)) then
			page = 1
		end
	end
	flash, flashTime = b, 0.25
end

-- Call-ins -------------------------------------------------------------------------------------------------------------

function widget:Initialize()
	vsx, vsy = spGetViewGeometry()
	WG.bardroidTouchDock = shared
	readTouchUi()
	refresh()
	layout()
	Spring.Echo("[bardroid-dock] touch dock on")
end

function widget:Shutdown()
	WG.bardroidTouchDock = nil
end

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
	refreshTimer = 0
end

function widget:SelectionChanged()
	refreshTimer = 0
end

function widget:CommandsChanged()
	refreshTimer = 0
end

function widget:Update(dt)
	readTouchUi()
	refreshTimer = refreshTimer - dt
	if refreshTimer <= 0 then
		refreshTimer = REFRESH_SECONDS -- states (fire state, on/off...) change without a call-in
		refresh()
	end
	layout() -- cheap; follows the armed command, the build drawer and the rail
	shared.rect = shown() and rect or nil
	flashTime = flashTime - dt
end

function widget:IsAbove(x, y)
	return hit(x, y) ~= nil
end

function widget:MousePress(x, y, button)
	local b = hit(x, y)
	if not b then
		return false
	end
	if b[5] ~= "panel" then
		press(b, button)
	end
	return true
end

function widget:MouseRelease()
	return false
end

-- Drawing --------------------------------------------------------------------------------------------------------------

local COLOR_PANEL = { 0.03, 0.04, 0.05, 0.72 }
local COLOR_BUTTON = { 0.1, 0.11, 0.13, 0.92 }
local COLOR_STATE = { 0.08, 0.16, 0.12, 0.92 }
local COLOR_ON = { 0.12, 0.45, 0.9, 0.95 }
local COLOR_FLASH = { 1, 1, 1, 0.35 }
local COLOR_STOP = { 0.35, 0.08, 0.08, 0.92 }

local function roundRect(x1, y1, x2, y2, r, color)
	local rr = WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.RectRound
	if rr then
		rr(x1, y1, x2, y2, r, 1, 1, 1, 1, color, color)
	else
		glColor(color)
		glRect(x1, y1, x2, y2)
	end
end

local function text(s, x, y, size, options)
	if font then
		font:Begin()
		font:SetTextColor(1, 1, 1, 1)
		font:SetOutlineColor(0, 0, 0, 0.9)
		font:Print(s, x, y, size, options .. "o")
		font:End()
	else
		glColor(1, 1, 1, 1)
		gl.Text(s, x, y, size, options)
	end
end

-- The label as big as fits the button.
local function fitted(s, width, size)
	return math.min(size, width / math.max(1, #s * 0.62))
end

function widget:DrawScreen()
	if not shown() then
		return
	end
	if not font and WG.fonts and WG.fonts.getFont then
		font = WG.fonts.getFont(2, 1.5)
	end
	local mm = rect.mm
	local r = math.floor(mm)
	roundRect(rect[1], rect[2], rect[3], rect[4], r, COLOR_PANEL)
	local active = select(2, spGetActiveCommand())
	local ls = mm * LABEL_MM
	for _, b in ipairs(buttons) do
		local x1, y1, x2, y2, kind, value = b[1], b[2], b[3], b[4], b[5], b[6]
		local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
		if kind == "card" then
			glColor(1, 1, 1, 1)
			glTexture("#" .. value[1])
			glTexRect(x1, y1, x2, y2)
			glTexture(false)
			if #value[2] > 1 then
				text(tostring(#value[2]), x2 - mm * 0.6, y1 + mm * 0.8, mm * 3.2, "r")
			end
		else
			local color, label = COLOR_BUTTON, "X"
			if kind == "command" then
				label = value[3]
				if value[2] == CMDTYPE.ICON_MODE then
					color = COLOR_STATE
				elseif value[1] == active then
					color = COLOR_ON
				elseif value[1] == CMD.STOP then
					color = COLOR_STOP
				end
			elseif kind == "cancel" then
				label = "CANCEL"
			elseif kind == "more" then
				label = "MORE " .. value
			end
			roundRect(x1, y1, x2, y2, r, color)
			text(label, cx, cy, fitted(label, x2 - x1 - mm, ls), "cv")
		end
		if flashTime > 0 and flash and flash[5] == kind and flash[6] == value then
			roundRect(x1, y1, x2, y2, r, COLOR_FLASH)
		end
	end
	glColor(1, 1, 1, 1)
end
