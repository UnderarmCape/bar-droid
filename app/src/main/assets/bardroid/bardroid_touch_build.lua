-- BAR Droid touch build menu (touch-only mode, see TOUCH-UI.md): the selected builder's buildings as big icons (BAR's
-- own categories and grid order), and how to place them: ONE (tap the spot, or drag the ghost and lift), LINE (a drag
-- lays a row) or GRID (a drag fills a rectangle), with ROTATE, spacing and CANCEL. A factory's units queue with a tap
-- (+5 with QUEUE latched) and leave the queue with a long press. Drawn over BAR's build menu while fingers are in use;
-- with a mouse, keyboard or gamepad it steps aside and BAR's menu is there as usual.
--
-- LINE and GRID are the engine's own (Shift+drag, Shift+Alt+drag): the touch HUD (bardroid_touch_hud.lua) has the app
-- hold those keys while a building is armed, reading the mode from WG.bardroidTouchBuild. Installed into LuaUI/Widgets
-- by the app only in touch-only mode.

function widget:GetInfo()
	return {
		name = "BAR Droid touch build menu",
		desc = "Big build icons and ONE / LINE / GRID placement for touch-only play (BAR Droid)",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -10, -- over BAR's build and order menus (layers 0-1), under its windows, top bar and chat
		enabled = true,
	}
end

local TOUCHUI = "LuaUI/Config/bardroid_touchui.txt"
local APP = "LuaUI/Config/bardroid_app.txt"
local ICON_MM, MIN_ICON_MM, MAX_ICON_MM = 12, 9, 13
local GAP_MM, MARGIN_MM, LABEL_MM, COST_MM = 1.2, 1.5, 2.6, 2.1
local FLOAT_MM = 10 -- PLACE / ROTATE / CANCEL beside the ghost
local BAR_ROW = 0.6 -- tab, mode and action rows, as a fraction of the icon size
local COLUMNS, ROWS = 4, 3 -- BAR's build grid
local REFRESH_SECONDS = 0.25

local spGetActiveCommand = Spring.GetActiveCommand
local spSetActiveCommand = Spring.SetActiveCommand
local spGetActiveCmdDescs = Spring.GetActiveCmdDescs
local spGetCmdDescIndex = Spring.GetCmdDescIndex
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetModKeyState = Spring.GetModKeyState
local spGetMiniMapGeometry = Spring.GetMiniMapGeometry
local spGetViewGeometry = Spring.GetViewGeometry
local spGetGameFrame = Spring.GetGameFrame
local spGetSpectatingState = Spring.GetSpectatingState
local spGetMyTeamID = Spring.GetMyTeamID
local spSendCommands = Spring.SendCommands
local spIsGUIHidden = Spring.IsGUIHidden
local spGetMouseState = Spring.GetMouseState
local spIsAboveMiniMap = Spring.IsAboveMiniMap
local spTraceScreenRay = Spring.TraceScreenRay
local glColor = gl.Color
local glRect = gl.Rect
local glTexture = gl.Texture
local glTexRect = gl.TexRect

local CATEGORIES = { "ECON", "COMBAT", "UTILITY", "BUILD" }
local CATEGORY_OF_GROUP = {
	energy = 1,
	metal = 1,
	weapon = 2,
	explo = 2,
	weaponaa = 2,
	weaponsub = 2,
	aa = 2,
	emp = 2,
	sub = 2,
	nuke = 2,
	antinuke = 2,
	util = 3,
	builder = 4,
	buildert2 = 4,
	buildert3 = 4,
	buildert4 = 4,
}
local categoryOf = {}
for udid, ud in pairs(UnitDefs) do
	categoryOf[udid] = CATEGORY_OF_GROUP[ud.customParams and ud.customParams.unitgroup] or 3
end

-- BAR's grid positions, so the big menu matches the one players know. Optional: without it, build order.
local barGrid, barCategoryNames
do
	local ok, grid = pcall(require, "luaui/configs/gridmenu_config")
	if ok and type(grid) == "table" and grid.getSortedGridForBuilder and BAR and BAR.I18N then
		barGrid = grid
		barCategoryNames = {
			BAR.I18N("ui.buildMenu.category_econ"),
			BAR.I18N("ui.buildMenu.category_combat"),
			BAR.I18N("ui.buildMenu.category_utility"),
			BAR.I18N("ui.buildMenu.category_production"),
		}
	end
end

local vsx, vsy = 1, 1
local ghostX, ghostY -- GL pixels of the building ghost in ONE mode
local floating = {} -- PLACE / ROTATE / CANCEL beside it
local lastArmed
local touchOnly, pxmm, input = true, nil, "touch"
local mode, collapsed, category = "one", false, 1
local page = 1
local builderDefID, isFactory = nil, false
local cells = {} -- page of { udid, disabled, queue } in grid order (row 1 = top), false = empty cell
local pages = 1
local armedDefID -- the building armed now (engine command or pregame pick)
local L = {} -- layout
local buttons = {} -- { x1, y1, x2, y2, kind, value }
local refreshTimer, layoutTimer = 0, 0
local font
local shared = { mode = mode, armed = false, rect = nil }

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

local function isPregame()
	return spGetGameFrame() <= 0 and WG["pregame-build"] and WG["pregame-build"].setPreGamestartDefID ~= nil
end

-- The builder the menu is for: BAR's active builder when it says, else the selected type with the most options.
local function pickBuilder()
	if isPregame() then
		local udid = Spring.GetTeamRulesParam(spGetMyTeamID(), "startUnit")
		return udid and UnitDefs[udid] and udid or nil
	end
	local sorted = spGetSelectedUnitsSorted() or {}
	local active = WG.gridmenu and WG.gridmenu.getActiveBuilder and WG.gridmenu.getActiveBuilder()
	if active and sorted[active] then
		return active
	end
	local best, most = nil, 0
	for udid in pairs(sorted) do
		local n = type(udid) == "number" and UnitDefs[udid] and #(UnitDefs[udid].buildOptions or {}) or 0
		if n > most then
			best, most = udid, n
		end
	end
	return best
end

-- The cells of the current category (or the factory's list) and page, from the engine's command list.
local function refresh()
	builderDefID = pickBuilder()
	cells, pages = {}, 1
	if not builderDefID then
		return
	end
	local ud = UnitDefs[builderDefID]
	isFactory = ud.isFactory and true or false
	local available, cmds = {}, {}
	if isPregame() then
		for _, udid in ipairs(ud.buildOptions or {}) do
			available[udid] = { id = -udid, params = {} }
		end
	else
		for _, cmd in ipairs(spGetActiveCmdDescs() or {}) do
			if cmd.id < 0 then
				available[-cmd.id] = cmd
				cmds[#cmds + 1] = cmd
			end
		end
	end
	local list = {}
	local function add(udid)
		local cmd = available[udid]
		list[#list + 1] = cmd and { udid, cmd.disabled, tonumber(cmd.params and cmd.params[1]) } or false
	end
	-- BAR's grid: index 1 is the bottom left, 9-12 the top row; ours runs from the top
	local function addBarGrid(grid)
		for r = 1, ROWS do
			for c = 1, COLUMNS do
				local opt = grid[(ROWS - r) * COLUMNS + c]
				if opt and opt.id and available[-opt.id] then
					add(-opt.id)
				else
					list[#list + 1] = false
				end
			end
		end
		for i, opt in pairs(grid) do -- anything past BAR's 12 cells (scavenger units...)
			if type(i) == "number" and i > ROWS * COLUMNS and opt and opt.id and available[-opt.id] then
				add(-opt.id)
			end
		end
	end
	local ok = false
	if barGrid then
		ok = pcall(function()
			local grid
			if isFactory then
				grid = barGrid.getSortedGridForLab(builderDefID, cmds)
			else
				local opts = {}
				for udid in pairs(available) do
					opts[#opts + 1] = udid
				end
				grid = barGrid.getSortedGridForBuilder(builderDefID, opts, barCategoryNames[category])
			end
			addBarGrid(grid or {})
		end)
	end
	if not ok then
		list = {}
		for _, udid in ipairs(ud.buildOptions or {}) do
			if available[udid] and (isFactory or categoryOf[udid] == category) then
				add(udid)
			end
		end
	end
	local perPage = COLUMNS * ROWS
	pages = math.max(1, math.ceil(#list / perPage))
	page = math.min(page, pages)
	for i = 1, perPage do
		cells[i] = list[(page - 1) * perPage + i] or false
	end
end

local function updateArmed()
	armedDefID = nil
	if isPregame() then
		local udid = WG["pregame-build"].getPreGameDefID and WG["pregame-build"].getPreGameDefID()
		armedDefID = udid and udid > 0 and udid or nil
	else
		local _, cmdID = spGetActiveCommand()
		armedDefID = cmdID and cmdID < 0 and -cmdID or nil
	end
	shared.armed = armedDefID ~= nil
end

-- Layout ---------------------------------------------------------------------------------------------------------------

local function layout()
	local mm = pxmm or (vsy / 75)
	local margin, gap = math.floor(MARGIN_MM * mm + 0.5), math.floor(GAP_MM * mm + 0.5)
	local pad = gap
	local function iconFor(height)
		return math.floor((height - 5 * gap - 2 * pad) / (ROWS + 3 * BAR_ROW))
	end
	-- under the minimap if the icons fit there at a good size, else over it (the cover screen is short)
	local top = vsy - margin
	local mx, my, _, _, minimized = spGetMiniMapGeometry()
	if mx and not minimized and iconFor(my - margin - margin) >= math.floor(ICON_MM * mm) then
		top = my - margin
	end
	local icon = math.max(math.floor(MIN_ICON_MM * mm), math.min(math.floor(MAX_ICON_MM * mm), iconFor(top - margin)))
	local row = math.floor(icon * BAR_ROW)
	local width = COLUMNS * icon + (COLUMNS - 1) * gap + 2 * pad
	local height = ROWS * icon + 3 * row + 5 * gap + 2 * pad
	L = { mm = mm, icon = icon, row = row, gap = gap, pad = pad, x1 = margin, y1 = margin, x2 = margin + width, y2 = margin + height }
end

-- The buttons for what is on screen now.
local function buildButtons()
	buttons = {}
	if collapsed then
		local w = math.floor(L.icon * 1.3)
		buttons[1] = { L.x1, L.y1, L.x1 + w, L.y1 + L.row, "expand" }
		return
	end
	local x1, x2, gap, pad, row, icon = L.x1, L.x2, L.gap, L.pad, L.row, L.icon
	local inner = x2 - x1 - 2 * pad
	local y = L.y2 - pad
	local function rowOf(entries, height)
		local n = #entries
		local w = (inner - (n - 1) * gap) / n
		for i, e in ipairs(entries) do
			local bx = x1 + pad + (i - 1) * (w + gap)
			buttons[#buttons + 1] = { math.floor(bx), y - height, math.floor(bx + w), y, e[1], e[2] }
		end
		y = y - height - gap
	end
	-- tabs (a factory has none: its units in BAR's order), with the collapse button
	if isFactory then
		local entries = { { "hide" } }
		if pages > 1 then
			entries[2] = { "page" }
		end
		rowOf(entries, row)
	else
		local entries = {}
		for i = 1, #CATEGORIES do
			entries[i] = { "category", i }
		end
		entries[#entries + 1] = { "hide" }
		rowOf(entries, row)
	end
	-- icons
	for r = 1, ROWS do
		for c = 1, COLUMNS do
			local cell = cells[(r - 1) * COLUMNS + c]
			if cell then
				local bx = x1 + pad + (c - 1) * (icon + gap)
				buttons[#buttons + 1] = { bx, y - icon, bx + icon, y, "unit", cell }
			end
		end
		y = y - icon - gap
	end
	if isFactory then
		return
	end
	rowOf({ { "mode", "one" }, { "mode", "line" }, { "mode", "grid" }, pages > 1 and { "page" } or nil }, row)
	if armedDefID then
		rowOf({ { "rotate" }, { "spacing", -1 }, { "spacing", 1 }, { "cancel" } }, row)
	end
end

local function shown()
	return touchOnly and input == "touch" and builderDefID ~= nil and not spIsGUIHidden() and not spGetSpectatingState()
end

local function hit(x, y)
	if not shown() then
		return nil
	end
	for _, b in ipairs(floating) do
		if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
			return b
		end
	end
	for _, b in ipairs(buttons) do
		if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
			return b
		end
	end
	if not collapsed and x >= L.x1 and x <= L.x2 and y >= L.y1 and y <= L.y2 then
		return { L.x1, L.y1, L.x2, L.y2, "panel" } -- the gaps between buttons are ours too
	end
end

-- Actions --------------------------------------------------------------------------------------------------------------

local function arm(udid)
	if isPregame() then
		WG["pregame-build"].setPreGamestartDefID(udid)
		return
	end
	local index = spGetCmdDescIndex(-udid)
	if index then
		local alt, ctrl, meta, shift = spGetModKeyState()
		spSetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
	end
end

local function queue(udid, remove)
	local index = spGetCmdDescIndex(-udid)
	if index then
		local alt, ctrl, meta, shift = spGetModKeyState()
		if remove then
			spSetActiveCommand(index, 3, false, true, alt, ctrl, meta, shift)
		else
			spSetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
		end
	end
end

local function cancel()
	if isPregame() then
		WG["pregame-build"].setPreGamestartDefID(nil)
	else
		spSetActiveCommand(nil)
	end
end

-- ONE mode: the ghost and PLACE / TURN / X beside it --------------------------------------------------------------------

local function send(line) -- a request for the app (bardroid_touch_hud.lua lists them)
	local f = io.open(APP, "a")
	if f then
		f:write(line, "\n")
		f:close()
	end
end

local function moveGhost() -- the pointer (and with it the engine's ghost) to the ghost's place
	if ghostX then
		send(string.format("move %d %d", ghostX, vsy - 1 - ghostY))
	end
end

-- Whether GL pixel (x, y) is open map (not this menu, the dock, the touch rail or the minimap).
local function overMap(x, y)
	if spIsAboveMiniMap(x, y) or hit(x, y) then
		return false
	end
	local dock = WG.bardroidTouchDock and WG.bardroidTouchDock.rect
	if dock and x >= dock[1] and x <= dock[3] and y >= dock[2] and y <= dock[4] then
		return false
	end
	local rail = WG.bardroidTouchHud and WG.bardroidTouchHud.railLeft
	if rail and x >= rail then
		return false
	end
	return spTraceScreenRay(x, y, true) == "ground"
end

-- After PLACE the next ghost goes right beside the last building (along the screen's horizontal, on the build grid):
-- four wind turbines are pick, PLACE, PLACE, PLACE, PLACE.
local function nextGhost(udid)
	local _, pos = spTraceScreenRay(ghostX, ghostY, true)
	local ud = UnitDefs[udid]
	if not (pos and ud) then
		return
	end
	local xs, zs = (ud.xsize or 4) * 8, (ud.zsize or 4) * 8
	if (Spring.GetBuildFacing() or 0) % 2 == 1 then
		xs, zs = zs, xs
	end
	local spacing = (Spring.GetBuildSpacing() or 0) * 16
	local right = (Spring.GetCameraVectors() or {}).right or { 1, 0, 0 }
	local wx, wz = pos[1], pos[3]
	if math.abs(right[1]) >= math.abs(right[3]) then
		wx = wx + (right[1] >= 0 and 1 or -1) * (xs + spacing)
	else
		wz = wz + (right[3] >= 0 and 1 or -1) * (zs + spacing)
	end
	local sx, sy = Spring.WorldToScreenCoords(wx, Spring.GetGroundHeight(wx, wz), wz)
	if sx and sx > 0 and sx < vsx and sy > 0 and sy < vsy then
		ghostX, ghostY = math.floor(sx), math.floor(sy)
	end
end

local function layoutFloating()
	floating = {}
	if not ghostX then
		return
	end
	local mm = L.mm
	local s, gap = math.floor(FLOAT_MM * mm), math.floor(GAP_MM * mm)
	local wide = math.floor(s * 1.4)
	local total = wide + 2 * s + 2 * gap
	local x = ghostX + math.floor(9 * mm)
	if x + total > vsx - gap then
		x = ghostX - math.floor(9 * mm) - total -- no room on the right
	end
	local y = math.max(gap, math.min(vsy - s - gap, ghostY + math.floor(5 * mm)))
	floating[1] = { x, y, x + wide, y + s, "place" }
	floating[2] = { x + wide + gap, y, x + wide + gap + s, y + s, "rotate" }
	floating[3] = { x + wide + 2 * gap + s, y, x + total, y + s, "cancel" }
end

local flash -- the button pressed last, briefly lit
local flashTime = 0

local function press(b, button)
	local kind, value = b[5], b[6]
	if kind == "place" then
		if button == 1 and ghostX and armedDefID then
			-- a real click at the ghost: BAR's own placement rules apply (mex snapping, pregame queue); Shift held by the
			-- HUD keeps the building armed for the next one
			send(string.format("click %d %d", ghostX, vsy - 1 - ghostY))
			nextGhost(armedDefID)
			send("buzz")
		end
	elseif kind == "unit" then
		if value[2] then
			return -- disabled (unit limit, restrictions)
		end
		if isFactory then
			queue(value[1], button == 3)
		elseif button == 1 then
			arm(value[1])
		end
	elseif button ~= 1 then
		return
	elseif kind == "category" then
		category, page = value, 1
		refresh()
	elseif kind == "mode" then
		mode = value
		shared.mode = mode
	elseif kind == "page" then
		page = page % pages + 1
		refresh()
	elseif kind == "rotate" then
		spSendCommands("buildfacing inc")
	elseif kind == "spacing" then
		spSendCommands(value > 0 and "buildspacing inc" or "buildspacing dec")
	elseif kind == "cancel" then
		cancel()
	elseif kind == "hide" then
		collapsed = true
	elseif kind == "expand" then
		collapsed = false
	end
	flash, flashTime = kind .. tostring(value), 0.25
end

-- Call-ins -------------------------------------------------------------------------------------------------------------

function widget:Initialize()
	vsx, vsy = spGetViewGeometry()
	WG.bardroidTouchBuild = shared
	readTouchUi()
	layout()
	refresh()
	updateArmed()
	buildButtons()
	Spring.Echo(string.format("[bardroid-build] touch build menu on (BAR grid order: %s)", barGrid and "yes" or "no"))
end

function widget:Shutdown()
	WG.bardroidTouchBuild = nil
end

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
	layout()
	buildButtons()
end

function widget:SelectionChanged()
	page = 1
	refreshTimer = 0
end

function widget:CommandsChanged()
	refreshTimer = 0
end

function widget:Update(dt)
	readTouchUi()
	refreshTimer = refreshTimer - dt
	if refreshTimer <= 0 then
		refreshTimer = REFRESH_SECONDS -- also keeps factory queue counts current
		refresh()
	end
	layoutTimer = layoutTimer - dt
	if layoutTimer <= 0 then
		layoutTimer = 1
		layout() -- fold/unfold, minimap size
	end
	updateArmed()
	buildButtons()
	shared.rect = shown() and not collapsed and { L.x1, L.y1, L.x2, L.y2 } or nil
	-- ONE mode: the ghost starts at the centre of the screen, then follows where the pointer goes on the map (a tap
	-- moves it, a drag on it moves it); PLACE / TURN / X stay beside it
	if shown() and armedDefID and mode == "one" then
		if armedDefID ~= lastArmed or not ghostX then
			ghostX, ghostY = math.floor(vsx / 2), math.floor(vsy / 2)
			moveGhost()
		else
			local mx, my = spGetMouseState()
			if overMap(mx, my) then
				ghostX, ghostY = mx, my
			end
		end
		layoutFloating()
	else
		ghostX, floating = nil, {}
	end
	lastArmed = armedDefID
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
	if ghostX and armedDefID and mode == "one" then
		moveGhost() -- the press moved the pointer onto this menu: back to the ghost (or the next one after PLACE)
	end
	return true
end

function widget:MouseRelease()
	return false
end

function widget:GetConfigData()
	return { mode = mode, collapsed = collapsed, category = category }
end

function widget:SetConfigData(data)
	if data.mode == "one" or data.mode == "line" or data.mode == "grid" then
		mode = data.mode
		shared.mode = mode
	end
	collapsed = data.collapsed == true
	category = tonumber(data.category) or 1
end

-- Drawing --------------------------------------------------------------------------------------------------------------

local COLOR_PANEL = { 0.03, 0.04, 0.05, 0.78 }
local COLOR_BUTTON = { 0.1, 0.11, 0.13, 0.9 }
local COLOR_ON = { 0.12, 0.45, 0.9, 0.95 }
local COLOR_ARMED = { 1, 0.8, 0.2, 1 }
local LABELS = {
	one = "ONE",
	line = "LINE",
	grid = "GRID",
	rotate = "ROTATE",
	cancel = "CANCEL",
	hide = "<",
	place = "BUILD",
	expand = "BUILD >",
	page = "MORE",
}

local function roundRect(x1, y1, x2, y2, r, color)
	local rr = WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.RectRound
	if rr then
		rr(x1, y1, x2, y2, r, 1, 1, 1, 1, color, color)
	else
		glColor(color)
		glRect(x1, y1, x2, y2)
	end
end

local function text(s, x, y, size, options, alpha)
	if font then
		font:Begin()
		font:SetTextColor(1, 1, 1, alpha or 1)
		font:SetOutlineColor(0, 0, 0, 0.9)
		font:Print(s, x, y, size, options .. "o")
		font:End()
	else
		glColor(1, 1, 1, alpha or 1)
		gl.Text(s, x, y, size, options)
	end
end

local function label(b)
	local kind, value = b[5], b[6]
	if kind == "category" then
		return CATEGORIES[value]
	elseif kind == "spacing" then
		return value > 0 and "SPACE +" or "SPACE -"
	elseif kind == "page" then
		return "MORE " .. page .. "/" .. pages
	end
	return LABELS[kind] or kind
end

local function drawUnit(b)
	local x1, y1, x2, y2 = b[1], b[2], b[3], b[4]
	local udid, disabled, queued = b[6][1], b[6][2], b[6][3]
	local ud = UnitDefs[udid]
	glColor(disabled and 0.35 or 1, disabled and 0.35 or 1, disabled and 0.35 or 1, 1)
	glTexture("#" .. udid)
	glTexRect(x1, y1, x2, y2)
	glTexture(false)
	if armedDefID == udid then
		local t = math.max(2, math.floor(L.mm * 0.5))
		glColor(COLOR_ARMED)
		glRect(x1, y1, x2, y1 + t)
		glRect(x1, y2 - t, x2, y2)
		glRect(x1, y1, x1 + t, y2)
		glRect(x2 - t, y1, x2, y2)
	end
	local cs = L.mm * COST_MM
	if ud then
		text(tostring(math.floor(ud.metalCost or 0)), x1 + cs * 0.3, y1 + cs * 0.9, cs, "", 0.95)
		text(tostring(math.floor(ud.energyCost or 0)), x2 - cs * 0.3, y1 + cs * 0.9, cs, "r", 0.85)
	end
	if queued and queued > 0 then
		text(tostring(queued), x2 - cs * 0.4, y2 - cs * 1.2, cs * 1.6, "r", 1)
	end
end

function widget:DrawScreen()
	if not shown() then
		return
	end
	if not font and WG.fonts and WG.fonts.getFont then
		font = WG.fonts.getFont(2, 1.5)
	end
	local r = math.floor(L.icon * 0.08)
	if not collapsed then
		roundRect(L.x1, L.y1, L.x2, L.y2, r, COLOR_PANEL)
	end
	local ls = L.mm * LABEL_MM
	for _, b in ipairs(floating) do
		local lit = flashTime > 0 and flash == b[5] .. tostring(b[6])
		roundRect(b[1], b[2], b[3], b[4], r, (lit or b[5] == "place") and COLOR_ON or COLOR_BUTTON)
		text(label(b), (b[1] + b[3]) / 2, (b[2] + b[4]) / 2, ls, "cv", 1)
	end
	for _, b in ipairs(buttons) do
		if b[5] == "unit" then
			drawUnit(b)
		else
			local on = (b[5] == "category" and b[6] == category) or (b[5] == "mode" and b[6] == mode)
			local lit = flashTime > 0 and flash == b[5] .. tostring(b[6])
			roundRect(b[1], b[2], b[3], b[4], r, (on or lit) and COLOR_ON or COLOR_BUTTON)
			text(label(b), (b[1] + b[3]) / 2, (b[2] + b[4]) / 2, ls, "cv", 1)
		end
	end
	glColor(1, 1, 1, 1)
end
