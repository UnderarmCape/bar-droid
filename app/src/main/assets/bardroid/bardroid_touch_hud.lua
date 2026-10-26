-- BAR Droid touch HUD (touch-only mode, see TOUCH-UI.md): big buttons for what fingers cannot do otherwise (Shift,
-- Ctrl, selection, control groups, chat, pause), and "smart tap": a tap on the map gives the selected units the order
-- a right click would. Installed into LuaUI/Widgets by the app only while the launcher's Touch-only mode is on.
--
-- BAR's sandbox lets user widgets neither make input nor open sockets, so the app holds keys and shows the keyboard
-- for the HUD. Files (relative to the write dir; X screen pixels, origin at the top left):
--   LuaUI/Config/bardroid_app.txt      widget, appended:  mods <shift> <ctrl> <alt>   (hold 1 / release 0 in the X server)
--                                                         key <name>                 (enter, escape: press and release)
--                                                         keyboard <0|1>             (soft keyboard)
--                                                         box <0|1>                  (BOX latch: one-finger drags select)
--   LuaUI/Config/bardroid_touchui.txt  app, replaced:     <touchOnly 0|1> <X pixels per millimetre> <input>
--                                                         (input used last: touch, mouse, keyboard, gamepad; the HUD
--                                                         shows only for touch, so every input works together)
--   LuaUI/Config/bardroid_touch.txt    app, appended:     box <x0> <y0> <x1> <y1>    (selection box being dragged)
--                                                         boxend <x0> <y0> <x1> <y1> | boxcancel
--                                                         (and the camera lines bardroid_touch.lua reads)

function widget:GetInfo()
	return {
		name = "BAR Droid touch HUD",
		desc = "Touch-only controls from the BAR Droid app: big buttons, tap to order, control groups",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		-- After BAR's interface: a press reaches MousePress here only when no BAR widget took it (so it is on the map),
		-- and DrawScreen draws this under BAR's windows. Before bardroid_touch.lua (1000000), which must stay last for
		-- IsAbove: the HUD's buttons count as interface.
		layer = 999999,
		enabled = true,
	}
end

local APP = "LuaUI/Config/bardroid_app.txt"
local TOUCHUI = "LuaUI/Config/bardroid_touchui.txt"
local TOUCH = "LuaUI/Config/bardroid_touch.txt"

local BUTTON_MM, MIN_BUTTON_MM, GAP_MM, MARGIN_MM, LABEL_MM = 9, 7.5, 1.5, 1.5, 2.6
local REFOCUS_SECONDS = 0.6 -- a second tap on the group just selected moves the camera to it
local FLASH_SECONDS = 0.25

local spGetViewGeometry = Spring.GetViewGeometry
local spGetActiveCommand = Spring.GetActiveCommand
local spSetActiveCommand = Spring.SetActiveCommand
local spGetDefaultCommand = Spring.GetDefaultCommand
local spGetCmdDescIndex = Spring.GetCmdDescIndex
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount
local spSelectUnitArray = Spring.SelectUnitArray
local spGetModKeyState = Spring.GetModKeyState
local spGetMouseState = Spring.GetMouseState
local spTraceScreenRay = Spring.TraceScreenRay
local spIsAboveMiniMap = Spring.IsAboveMiniMap
local spGetMiniMapGeometry = Spring.GetMiniMapGeometry
local spGetGameFrame = Spring.GetGameFrame
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetMyTeamID = Spring.GetMyTeamID
local spGetSpectatingState = Spring.GetSpectatingState
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitPosition = Spring.GetUnitPosition
local spSetCameraTarget = Spring.SetCameraTarget
local spGetGroupList = Spring.GetGroupList
local spGetUnitsInScreenRectangle = Spring.GetUnitsInScreenRectangle
local spSendCommands = Spring.SendCommands
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local spIsGUIHidden = Spring.IsGUIHidden
local glColor = gl.Color
local glRect = gl.Rect

local vsx, vsy = 1, 1
local touchOnly, pxmm, input = true, nil, "touch"
local active = true -- touch-only mode and fingers used last: HUD shown, smart tap on
local latch = { shift = false, ctrl = false, box = false }
local shared = { railLeft = nil } -- WG.bardroidTouchHud, for the dock
local column, context, groups = {}, {}, {} -- buttons: { x1, y1, x2, y2, label, press, hold, latch, enabled }
local flashes = {}
local font
local layoutKey
local checkTimer = 0
local touchPos, partial = 0, ""
local boxRect -- { x1, y1, x2, y2 } GL pixels while the app drags a selection box
local smartCmdID -- the order a smart tap armed; disarmed once the tap is done
local lastGroup, lastGroupTimer
local comIndex, idleIndex = 0, 0

local isCommander, isMobileBuilder, isCombat = {}, {}, {}
for udid, ud in pairs(UnitDefs) do
	local mobile = ud.canMove and not ud.isBuilding and (ud.speed or 0) > 0
	isCommander[udid] = ud.customParams and ud.customParams.iscommander and true or nil
	isMobileBuilder[udid] = (mobile and ud.isBuilder) or nil
	isCombat[udid] = (mobile and not ud.isBuilder and #(ud.weapons or {}) > 0) or nil
end

-- The app's side --------------------------------------------------------------------------------------------------

local function send(line)
	local f = io.open(APP, "a")
	if f then
		f:write(line, "\n")
		f:close()
	end
end

-- The keys the app holds: the QUEUE/CTRL latches, plus while a building is armed in the build menu's LINE mode Shift
-- (the engine lays a row along a drag) and in GRID mode Shift+Alt (it fills the dragged rectangle).
local sentMods
local function wantedMods()
	local shift, ctrl, alt = latch.shift, latch.ctrl, false
	local build = WG.bardroidTouchBuild
	if not active then
		shift, ctrl = false, false -- a mouse or keyboard in use: hands off the keys
	elseif build and build.armed and (build.mode == "line" or build.mode == "grid") then
		shift, alt = true, build.mode == "grid"
	end
	return string.format("mods %d %d %d", shift and 1 or 0, ctrl and 1 or 0, alt and 1 or 0)
end

local function sendMods(force)
	local mods = wantedMods()
	if force or mods ~= sentMods then
		send(mods)
		sentMods = mods
	end
end

local function sendLatches()
	sendMods(true)
	send("box " .. (latch.box and 1 or 0))
end

local function readTouchUi()
	local f = io.open(TOUCHUI, "r")
	if not f then
		return
	end
	local s = f:read("*l")
	f:close()
	local mode, mm, used = (s or ""):match("^(%d) ([%d%.]+) ?(%a*)")
	if mode then
		touchOnly = mode == "1"
		pxmm = tonumber(mm)
		input = used ~= "" and used or "touch"
	end
end

-- Complete new lines of the app's touch log since the last call (bardroid_touch.lua reads the same log).
local function newTouchLines()
	local f = io.open(TOUCH, "r")
	if not f then
		return nil
	end
	local size = f:seek("end")
	if size < touchPos then -- the app started a new log
		touchPos, partial = 0, ""
	end
	if size == touchPos then
		f:close()
		return nil
	end
	f:seek("set", touchPos)
	local data = partial .. (f:read("*a") or "")
	touchPos = f:seek()
	f:close()
	local cut = data:match(".*\n()")
	if not cut then
		partial = data
		return nil
	end
	partial = data:sub(cut)
	return data:sub(1, cut - 1)
end

-- Units --------------------------------------------------------------------------------------------------------------

local function canSelect(unitID)
	local spec, fullView = spGetSpectatingState()
	return (spec and fullView) or spGetUnitTeam(unitID) == spGetMyTeamID()
end

local function finished(unitID)
	local _, _, _, _, progress = spGetUnitHealth(unitID)
	return progress == nil or progress >= 1
end

local function ownUnits(filter)
	local list = {}
	for _, unitID in ipairs(spGetTeamUnits(spGetMyTeamID()) or {}) do
		if filter[spGetUnitDefID(unitID)] and finished(unitID) then
			list[#list + 1] = unitID
		end
	end
	table.sort(list)
	return list
end

-- Selects the next of these units (cycling) and points the camera at it.
local function cycleTo(list, index)
	if #list == 0 then
		return index
	end
	index = index % #list + 1
	local unitID = list[index]
	spSelectUnitArray({ unitID })
	local x, y, z = spGetUnitPosition(unitID)
	if x then
		spSetCameraTarget(x, y, z, 0.5)
	end
	return index
end

local function selectArmy()
	spSelectUnitArray(ownUnits(isCombat), latch.shift)
end

local function selectIdleBuilder()
	local idle = {}
	for _, unitID in ipairs(ownUnits(isMobileBuilder)) do
		local cmds = spGetUnitCommands(unitID, 1)
		if cmds and #cmds == 0 then
			idle[#idle + 1] = unitID
		end
	end
	idleIndex = cycleTo(idle, idleIndex)
end

local function selectCommander()
	comIndex = cycleTo(ownUnits(isCommander), comIndex)
end

local function openChat()
	latch.shift, latch.ctrl = false, false -- typed letters must not come out shifted
	sendLatches()
	send("key enter") -- BAR's chat opens its input on a real Enter key press
	send("keyboard 1")
end

local function toggleMenu()
	if WG.options and WG.options.toggle then
		WG.options.toggle()
	else
		send("key escape")
	end
end

local function groupPress(n)
	local now = spGetTimer()
	if lastGroup == n and lastGroupTimer and spDiffTimers(now, lastGroupTimer) < REFOCUS_SECONDS then
		spSendCommands("group focus " .. n)
		lastGroup = nil
	else
		spSendCommands("group select " .. n)
		lastGroup, lastGroupTimer = n, now
	end
end

local function groupAssign(n)
	if spGetSelectedUnitsCount() > 0 then
		spSendCommands("group set " .. n)
		Spring.Echo("[bardroid-hud] control group " .. n .. " = " .. spGetSelectedUnitsCount() .. " units")
	end
end

local function newGroup()
	local used = spGetGroupList() or {}
	for _, n in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }) do
		if not used[n] then
			groupAssign(n)
			return
		end
	end
end

-- Layout -------------------------------------------------------------------------------------------------------------

local function toggle(name)
	return function()
		latch[name] = not latch[name]
		sendLatches()
	end
end

local function hasSelection()
	return spGetSelectedUnitsCount() > 0
end

local menuOpen = false -- the rail's pop-out (chat, pause, settings, Ctrl)

-- The rail, in priority order: on a short screen the last ones are left out (the menu button always fits).
local COLUMN = {
	{ "QUEUE", toggle("shift"), latch = "shift" },
	{ "SELECT", toggle("box"), latch = "box" },
	{ "ARMY", selectArmy },
	{ "IDLE", selectIdleBuilder },
	{ "COM", selectCommander },
	{
		"MENU",
		function()
			menuOpen = not menuOpen
		end,
		latch = "menu",
	},
}

-- The pop-out beside the menu button; a choice closes it (CTRL stays, it is a latch).
local MENU = {
	{
		"CHAT",
		function()
			menuOpen = false
			openChat()
		end,
	},
	{
		"PAUSE",
		function()
			menuOpen = false
			spSendCommands("pause")
		end,
	},
	{
		"SETTINGS",
		function()
			menuOpen = false
			toggleMenu()
		end,
	},
	{ "CTRL", toggle("ctrl"), latch = "ctrl" },
}
local menuButtons = {}

local function topOf(api)
	local ok, p = pcall(api)
	if ok and type(p) == "table" and type(p[1]) == "number" then
		return p[1]
	end
end

-- Where the HUD may go: under the top bar, above BAR's bottom-right panels (player list and friends).
local function freeArea(margin)
	local top, bottom = vsy - margin, margin
	if WG.topbar and WG.topbar.GetPosition then
		local ok, p = pcall(WG.topbar.GetPosition)
		if ok and type(p) == "table" and type(p[2]) == "number" and p[2] > vsy / 2 then
			top = math.min(top, p[2] - margin)
		end
	end
	for _, name in ipairs({ "advplayerlist_api", "displayinfo", "music", "unittotals", "converter_usage" }) do
		local api = WG[name] and WG[name].GetPosition
		local t = api and topOf(api)
		if t and t < vsy * 0.75 then
			bottom = math.max(bottom, t + margin)
		end
	end
	local mmRight = 0
	local mx, _, msx, _, minimized = spGetMiniMapGeometry()
	if mx and not minimized then
		mmRight = mx + msx
	end
	return top, bottom, mmRight
end

local function layout()
	local mm = pxmm or (vsy / 75) -- about right for a phone if the app has not said
	local margin, gap = math.floor(MARGIN_MM * mm + 0.5), math.floor(GAP_MM * mm + 0.5)
	local top, bottom, mmRight = freeArea(margin)
	local key = table.concat({ vsx, vsy, mm, top, bottom, mmRight }, " ")
	if key == layoutKey then
		return
	end
	layoutKey = key

	-- Column(s) on the right edge: as few columns as hold every button, buttons never below MIN_BUTTON_MM.
	local maxSize = math.floor(BUTTON_MM * mm + 0.5)
	local minSize = math.floor(MIN_BUTTON_MM * mm + 0.5)
	local height = math.max(0, top - bottom)
	local function rows(s)
		return math.max(1, math.floor((height + gap) / (s + gap)))
	end
	local size, cols
	for c = 1, 3 do
		size, cols = maxSize, c
		while rows(size) * cols < #COLUMN and size > minSize do
			size = size - 1
		end
		if rows(size) * cols >= #COLUMN then
			break
		end
	end
	local perCol = rows(size)
	column = {}
	for i, def in ipairs(COLUMN) do
		local c = math.floor((i - 1) / perCol) -- 0 = rightmost
		local r = (i - 1) % perCol
		if c < cols then
			local x2 = vsx - margin - c * (size + gap)
			local y2 = top - r * (size + gap)
			column[#column + 1] = {
				x2 - size,
				y2 - size,
				x2,
				y2,
				def[1],
				def[2],
				nil,
				def.latch,
				def.enabled,
			}
		end
	end
	if #column < #COLUMN then
		Spring.Echo(string.format("[bardroid-hud] only %d of %d buttons fit (%dx%d)", #column, #COLUMN, vsx, vsy))
	end
	local columnLeft = vsx - margin - cols * (size + gap) + gap
	shared.railLeft = columnLeft -- the dock stops here

	-- The menu's pop-out: a stack left of the menu button, upwards from its bottom.
	menuButtons = {}
	for _, b in ipairs(column) do
		if b[8] == "menu" then
			local w = math.floor(size * 1.5)
			for i, def in ipairs(MENU) do
				local y1 = b[2] + (i - 1) * (size + gap)
				menuButtons[i] = { columnLeft - gap - w, y1, columnLeft - gap, y1 + size, def[1], def[2], nil, def.latch }
			end
		end
	end

	-- Context bar left of the column's bottom: ROTATE / CANCEL while a building is armed and the build menu is hidden.
	local w = math.floor(size * 1.4)
	local cy1 = bottom
	context = {
		rotate = { columnLeft - gap - 2 * w - gap, cy1, columnLeft - gap - w - gap, cy1 + size, "ROTATE" },
		cancel = { columnLeft - gap - w, cy1, columnLeft - gap, cy1 + size, "CANCEL" },
	}
	context.rotate[6] = function()
		spSendCommands("buildfacing inc")
	end
	context.cancel[6] = function()
		spSetActiveCommand(nil)
	end

	-- Group row under the top bar, right of the minimap.
	groups = {
		x = mmRight + margin,
		right = columnLeft - gap,
		top = top,
		w = size,
		h = math.floor(size * 0.8),
		gap = gap,
	}
	Spring.Echo(
		string.format(
			"[bardroid-hud] layout %dx%d, %.1f px/mm, buttons %d px in %d column(s), free %d..%d",
			vsx,
			vsy,
			mm,
			size,
			cols,
			bottom,
			top
		)
	)
end

-- The group row's buttons for the groups that exist now, plus "+".
local function groupButtons()
	local list = {}
	if not groups.x then
		return list
	end
	local counts = spGetGroupList() or {}
	local x = groups.x
	local y2 = groups.top
	local buildMenu = WG.bardroidTouchBuild and WG.bardroidTouchBuild.rect
	if buildMenu and buildMenu[4] > y2 - groups.h then
		x = math.max(x, buildMenu[3] + groups.gap) -- the build menu covers the minimap on a short screen
	end
	local function add(label, press, hold)
		if x + groups.w <= groups.right then
			list[#list + 1] = { x, y2 - groups.h, x + groups.w, y2, label, press, hold }
		end
		x = x + groups.w + groups.gap
	end
	for _, n in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }) do
		if counts[n] then
			add(n .. "\n" .. counts[n], function()
				groupPress(n)
			end, function()
				groupAssign(n)
			end)
		end
	end
	if hasSelection() then
		add("+", newGroup)
	end
	return list
end

local function visibleButtons()
	local list = {}
	for _, b in ipairs(column) do
		list[#list + 1] = b
	end
	if menuOpen then
		for _, b in ipairs(menuButtons) do
			list[#list + 1] = b
		end
	end
	-- ROTATE / CANCEL for a building when the build menu (which has its own) is folded away; the dock has CANCEL
	-- for orders
	local _, activeID = spGetActiveCommand()
	local buildMenu = WG.bardroidTouchBuild and WG.bardroidTouchBuild.rect
	if activeID and activeID < 0 and not buildMenu then
		list[#list + 1] = context.rotate
		list[#list + 1] = context.cancel
	end
	for _, b in ipairs(groups.list or {}) do
		list[#list + 1] = b
	end
	return list
end

local function hit(x, y)
	if not active or spIsGUIHidden() then
		return nil
	end
	for _, b in ipairs(visibleButtons()) do
		if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
			return b
		end
	end
end

-- Smart tap ----------------------------------------------------------------------------------------------------------

-- A left press on the map that no BAR widget wanted. With units selected and no command armed, arm the order a right
-- click would give here; the engine then carries it out when the press is released (CGuiHandler::MouseRelease).
local function smartTap(x, y)
	if spGetGameFrame() <= 0 or spIsAboveMiniMap(x, y) or spGetSpectatingState() then
		return
	end
	local _, activeID = spGetActiveCommand()
	if activeID or spGetSelectedUnitsCount() == 0 then
		return
	end
	local alt, ctrl, meta, shift = spGetModKeyState()
	if alt or ctrl then
		return -- Ctrl/Alt clicks keep their own meaning
	end
	local kind, id = spTraceScreenRay(x, y)
	if kind == "unit" and canSelect(id) then
		return -- a tap on one of ours selects it
	end
	local index, cmdID = spGetDefaultCommand()
	if cmdID and spSetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift) then
		smartCmdID = cmdID
	end
end

-- Call-ins -----------------------------------------------------------------------------------------------------------

function widget:Initialize()
	vsx, vsy = spGetViewGeometry()
	touchPos = 0
	local f = io.open(TOUCH, "r")
	if f then
		touchPos = f:seek("end") -- old gestures are not replayed
		f:close()
	end
	WG.bardroidTouchHud = shared
	readTouchUi()
	sendLatches() -- nothing latched: also releases keys a previous HUD left held
	layout()
	Spring.Echo("[bardroid-hud] touch-only HUD on")
end

function widget:Shutdown()
	WG.bardroidTouchHud = nil
	latch.shift, latch.ctrl, latch.box = false, false, false
	sendLatches()
end

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
	layoutKey = nil
	layout()
end

-- Two-finger tap, a phone's "back": put away the armed order or building, else close the menu, else deselect.
local function cancelGesture()
	local _, activeID = spGetActiveCommand()
	local pregame = WG["pregame-build"]
	if activeID then
		spSetActiveCommand(nil)
	elseif pregame and pregame.getPreGameDefID and (pregame.getPreGameDefID() or 0) > 0 then
		pregame.setPreGamestartDefID(nil)
	elseif menuOpen then
		menuOpen = false
	else
		spSelectUnitArray({})
	end
	send("buzz")
end

-- Selects what is inside the box the app is dragging (one-finger drag with BOX latched, or tap-then-drag): drawn and
-- applied here instead of the engine's selection box, so a left press on the map is always a tap (smart tap).
local function selectInBox(x0, y0, x1, y1)
	if not boxRect and WG.SmartSelect_SetReference then
		WG.SmartSelect_SetReference() -- what Shift adds to / Ctrl removes from
	end
	-- X screen pixels (top left) -> GL pixels (bottom left)
	boxRect = { math.min(x0, x1), vsy - 1 - math.max(y0, y1), math.max(x0, x1), vsy - 1 - math.min(y0, y1) }
	local spec = spGetSpectatingState()
	local units = spGetUnitsInScreenRectangle(boxRect[1], boxRect[2], boxRect[3], boxRect[4], not spec and -2 or nil) or {}
	if WG.SmartSelect_SelectUnits then
		WG.SmartSelect_SelectUnits(units) -- BAR's own rules: no buildings with mobile units, Shift adds, Ctrl removes
	else
		spSelectUnitArray(units, latch.shift)
	end
end

-- Press and hold: the radial menu ------------------------------------------------------------------------------------

local RADIAL_DEAD_MM, RADIAL_RING_MM, RADIAL_LABEL_W_MM, RADIAL_LABEL_H_MM = 6, 16, 15, 8
local MAX_RADIAL = 8
local radial -- { x, y (GL pixels), sx, sy (X screen pixels), options = { { label, run } }, choice, title }

local function haveCommand(id)
	return id ~= nil and spGetCmdDescIndex(id) ~= nil
end

-- A game command known by its action name (BAR's set target), if the selection has it.
local function commandByAction(action)
	for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do
		if cmd.action == action and not cmd.disabled then
			return cmd.id
		end
	end
end

-- An order straight to the selected units (QUEUE adds it to their queues). If the game does not let widgets give
-- orders, the engine's way: arm the command and click there through the app.
local function order(id, params, sx, sy)
	local ok = pcall(Spring.GiveOrder, id, params, latch.shift and { "shift" } or {})
	if not ok then
		local index = spGetCmdDescIndex(id)
		if index then
			local alt, ctrl, meta, shift = spGetModKeyState()
			spSetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
			send(string.format("click %d %d", sx, sy))
		end
	end
end

-- World radius of an area order: about a thumb (12 mm on screen) around the point.
local function areaRadius(x, y, pos)
	local mm = pxmm or (vsy / 75)
	local _, edge = spTraceScreenRay(x + 12 * mm, y, true)
	if edge and pos then
		return math.max(64, math.sqrt((edge[1] - pos[1]) ^ 2 + (edge[3] - pos[3]) ^ 2))
	end
	return 200
end

local function selectType(udid, wholeMap)
	local list = {}
	if wholeMap then
		list = Spring.GetTeamUnitsByDefs(spGetMyTeamID(), udid) or {}
	else
		for _, u in ipairs(spGetUnitsInScreenRectangle(0, 0, vsx, vsy, -2) or {}) do
			if spGetUnitDefID(u) == udid then
				list[#list + 1] = u
			end
		end
	end
	spSelectUnitArray(list, latch.shift)
end

-- What the selection can do at GL pixel (x, y): only orders it has, the most likely first.
local function radialOptions(x, y, sx, sy)
	local opts = {}
	local function add(label, run)
		if #opts < MAX_RADIAL then
			opts[#opts + 1] = { label, run }
		end
	end
	local kind, target = spTraceScreenRay(x, y)
	local _, ground = spTraceScreenRay(x, y, true)
	local pos = ground and { ground[1], ground[2], ground[3] } or nil
	local selected = spGetSelectedUnitsCount() > 0
	local title = "GROUND"
	if kind == "unit" then
		local own = canSelect(target)
		local allied = own or Spring.IsUnitAllied(target)
		local udid = spGetUnitDefID(target)
		title = own and "OURS" or allied and "ALLIED" or "ENEMY"
		if selected and allied then
			if haveCommand(CMD.GUARD) then
				add("GUARD", function()
					order(CMD.GUARD, { target }, sx, sy)
				end)
			end
			if haveCommand(CMD.REPAIR) then
				add("REPAIR", function()
					order(CMD.REPAIR, { target }, sx, sy)
				end)
			end
			if haveCommand(CMD.LOAD_UNITS) then
				add("LOAD", function()
					order(CMD.LOAD_UNITS, { target }, sx, sy)
				end)
			end
		elseif selected then
			if haveCommand(CMD.ATTACK) then
				add("ATTACK", function()
					order(CMD.ATTACK, { target }, sx, sy)
				end)
			end
			if haveCommand(CMD.MANUALFIRE) then
				add("D-GUN", function()
					order(CMD.MANUALFIRE, { target }, sx, sy)
				end)
			end
			local setTarget = commandByAction("settarget")
			if setTarget then
				add("SET TARGET", function()
					order(setTarget, { target }, sx, sy)
				end)
			end
			if haveCommand(CMD.CAPTURE) then
				add("CAPTURE", function()
					order(CMD.CAPTURE, { target }, sx, sy)
				end)
			end
			if haveCommand(CMD.RECLAIM) then
				add("RECLAIM", function()
					order(CMD.RECLAIM, { target }, sx, sy)
				end)
			end
		end
		if own and udid then
			add("SAME TYPE", function()
				selectType(udid, false)
			end)
			add("ALL OF TYPE", function()
				selectType(udid, true)
			end)
		end
	elseif kind == "feature" and selected then
		title = "WRECK"
		if haveCommand(CMD.RECLAIM) then
			add("RECLAIM", function()
				order(CMD.RECLAIM, { target + Game.maxUnits }, sx, sy)
			end)
		end
		if haveCommand(CMD.RESURRECT) then
			add("REZ", function()
				order(CMD.RESURRECT, { target + Game.maxUnits }, sx, sy)
			end)
		end
	end
	if selected and pos then
		if haveCommand(CMD.MOVE) then
			add("MOVE", function()
				order(CMD.MOVE, pos, sx, sy)
			end)
		end
		if haveCommand(CMD.FIGHT) then
			add("FIGHT", function()
				order(CMD.FIGHT, pos, sx, sy)
			end)
		end
		if kind ~= "unit" then
			if haveCommand(CMD.PATROL) then
				add("PATROL", function()
					order(CMD.PATROL, pos, sx, sy)
				end)
			end
			if haveCommand(CMD.ATTACK) then
				add("FIRE HERE", function()
					order(CMD.ATTACK, pos, sx, sy)
				end)
			end
			local r = areaRadius(x, y, pos)
			if haveCommand(CMD.RECLAIM) then
				add("RECLAIM AREA", function()
					order(CMD.RECLAIM, { pos[1], pos[2], pos[3], r }, sx, sy)
				end)
			end
			if haveCommand(CMD.REPAIR) then
				add("REPAIR AREA", function()
					order(CMD.REPAIR, { pos[1], pos[2], pos[3], r }, sx, sy)
				end)
			end
			if haveCommand(CMD.UNLOAD_UNITS) then
				add("UNLOAD", function()
					order(CMD.UNLOAD_UNITS, { pos[1], pos[2], pos[3], r }, sx, sy)
				end)
			end
		end
	end
	return opts, title
end

-- The option the finger points at (GL pixels), or nil inside the dead zone.
local function radialChoice(fx, fy)
	local n = #radial.options
	local dx, dy = fx - radial.x, fy - radial.y
	local mm = pxmm or (vsy / 75)
	if n == 0 or dx * dx + dy * dy < (RADIAL_DEAD_MM * mm) ^ 2 then
		return nil
	end
	-- option i sits at 90 degrees minus i steps (clockwise from the top)
	local a = math.atan2(dy, dx)
	local step = 2 * math.pi / n
	local i = math.floor(((math.pi / 2 - a) / step) + 0.5) % n
	return i + 1
end

local function radialGesture(kind, sx, sy)
	if kind == "radialcancel" then
		radial = nil
		return
	end
	if not (sx and sy) then
		return
	end
	local x, y = sx, vsy - 1 - sy
	if kind == "radial" then
		local options, title = radialOptions(x, y, sx, sy)
		radial = { x = x, y = y, sx = sx, sy = sy, options = options, title = title }
	elseif radial and kind == "radialmove" then
		local choice = radialChoice(x, y)
		if choice ~= radial.choice then
			radial.choice = choice
			if choice then
				send("buzz")
			end
		end
	elseif radial and kind == "radialup" then
		local choice = radialChoice(x, y)
		local r = radial
		radial = nil
		if choice and r.options[choice] then
			r.options[choice][2]()
			send("buzz")
		elseif spGetSelectedUnitsCount() > 0 then
			send(string.format("rclick %d %d", r.sx, r.sy)) -- lifted without choosing: the right-click order there
		end
	end
end

local function applyBox(lines)
	local last -- only the newest box of this frame is worth selecting
	for line in lines:gmatch("[^\n]+") do
		if line == "cancel" then
			cancelGesture()
		end
		local rk, rx, ry = line:match("^(radial%a*) ?(%S*) ?(%S*)")
		if rk then
			radialGesture(rk, tonumber(rx), tonumber(ry))
		end
		local kind, x0, y0, x1, y1 = line:match("^(box%a*) ?(%S*) ?(%S*) ?(%S*) ?(%S*)")
		x0, y0, x1, y1 = tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1)
		if kind == "box" and y1 then
			last = { x0, y0, x1, y1 }
		elseif kind == "boxend" and y1 then
			selectInBox(x0, y0, x1, y1)
			boxRect, last = nil, nil
			if WG.SmartSelect_ClearReference then
				WG.SmartSelect_ClearReference()
			end
		elseif kind == "boxcancel" then
			boxRect, last = nil, nil
		end
	end
	if last then
		selectInBox(last[1], last[2], last[3], last[4])
	end
end

function widget:Update(dt)
	-- the order a smart tap armed is done once the press is released (Shift would keep it armed for the next tap)
	if smartCmdID then
		local _, _, lmb = spGetMouseState()
		if not lmb then
			local _, activeID = spGetActiveCommand()
			if activeID == smartCmdID then
				spSetActiveCommand(nil)
			end
			smartCmdID = nil
		end
	end

	local lines = newTouchLines()
	if lines then
		applyBox(lines)
	end

	-- every frame: a tap right after a mouse was used must find the HUD active again
	readTouchUi()
	local nowActive = touchOnly and input == "touch"
	if nowActive ~= active then
		active = nowActive
		Spring.Echo("[bardroid-hud] input: " .. input .. (active and ", touch HUD shown" or ", touch HUD hidden"))
		if not active then -- the latches are touch tools; a keyboard has its own Shift
			latch.shift, latch.ctrl, latch.box = false, false, false
			sendLatches()
			boxRect = nil
		end
	end
	sendMods() -- a building armed or put away in LINE/GRID mode holds or releases Shift (+Alt)

	checkTimer = checkTimer - dt
	if checkTimer <= 0 then
		checkTimer = 0.5
		layout() -- the screen (fold/unfold) or BAR's panels may have moved
	end
	groups.list = groupButtons()

	for label, t in pairs(flashes) do
		flashes[label] = t > dt and t - dt or nil
	end
end

function widget:IsAbove(x, y)
	return hit(x, y) ~= nil
end

function widget:MousePress(x, y, button)
	local b = hit(x, y)
	if b then
		if button == 1 and b[6] then
			if not b[9] or b[9]() then
				b[6]()
			end
		elseif button == 3 and b[7] then
			b[7]() -- long press: the button's second action (assign a control group)
		end
		flashes[b[5]] = FLASH_SECONDS
		return true
	end
	if button == 1 and active then -- not for a real mouse: its left click keeps its desktop meaning
		smartTap(x, y)
	end
	return false
end

function widget:MouseRelease()
	return false
end

-- Drawing ------------------------------------------------------------------------------------------------------------

local function roundRect(x1, y1, x2, y2, r, color)
	local rr = WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.RectRound
	if rr then
		rr(x1, y1, x2, y2, r, 1, 1, 1, 1, color, color)
	else
		glColor(color)
		glRect(x1, y1, x2, y2)
	end
end

local COLOR_BUTTON = { 0.08, 0.09, 0.1, 0.72 }
local COLOR_LATCHED = { 0.12, 0.45, 0.9, 0.9 }
local COLOR_FLASH = { 1, 1, 1, 0.35 }
local COLOR_BORDER = { 1, 1, 1, 0.18 }

local function drawLabel(text, cx, cy, size, alpha)
	if font then
		font:Begin()
		font:SetTextColor(1, 1, 1, alpha)
		font:SetOutlineColor(0, 0, 0, 0.8 * alpha)
		local lineCount = select(2, text:gsub("\n", "")) + 1
		font:Print(text, cx, cy + (lineCount - 1) * size * 0.5, size, "cvo")
		font:End()
	else
		glColor(1, 1, 1, alpha)
		gl.Text(text, cx, cy, size, "cv")
	end
end

local function drawButton(b)
	local x1, y1, x2, y2 = b[1], b[2], b[3], b[4]
	local r = math.floor((x2 - x1) * 0.12)
	local on = b[8] and (b[8] == "menu" and menuOpen or latch[b[8]])
	roundRect(x1, y1, x2, y2, r, COLOR_BORDER)
	roundRect(x1 + 1, y1 + 1, x2 - 1, y2 - 1, r, on and COLOR_LATCHED or COLOR_BUTTON)
	if flashes[b[5]] then
		roundRect(x1, y1, x2, y2, r, COLOR_FLASH)
	end
	local enabled = not b[9] or b[9]()
	local size = (pxmm or (vsy / 75)) * LABEL_MM
	size = math.min(size, (x2 - x1) * 0.9 / math.max(1, #b[5] * 0.62)) -- long labels shrink to fit
	drawLabel(b[5], (x1 + x2) / 2, (y1 + y2) / 2, size, enabled and 1 or 0.4)
end

-- The radial menu: the target in the middle, the options on a ring (the chosen one lit).
local function drawRadial()
	local mm = pxmm or (vsy / 75)
	local n = #radial.options
	local c = math.floor(5 * mm)
	roundRect(radial.x - c, radial.y - c, radial.x + c, radial.y + c, c, { 0, 0, 0, 0.6 })
	drawLabel(n > 0 and radial.title or "NO ORDERS", radial.x, radial.y, math.min(LABEL_MM * mm, c * 2 / 7), 0.9)
	local w, h = RADIAL_LABEL_W_MM * mm, RADIAL_LABEL_H_MM * mm
	local ring = math.max(RADIAL_RING_MM, 3.2 * n) * mm -- far enough out that the labels do not overlap
	for i, opt in ipairs(radial.options) do
		local a = math.pi / 2 - (i - 1) * 2 * math.pi / n
		local cx = math.max(w / 2, math.min(vsx - w / 2, radial.x + math.cos(a) * ring))
		local cy = math.max(h / 2, math.min(vsy - h / 2, radial.y + math.sin(a) * ring))
		roundRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, math.floor(h * 0.3), COLOR_BORDER)
		roundRect(cx - w / 2 + 1, cy - h / 2 + 1, cx + w / 2 - 1, cy + h / 2 - 1, math.floor(h * 0.3),
			radial.choice == i and COLOR_LATCHED or COLOR_BUTTON)
		drawLabel(opt[1], cx, cy, math.min(LABEL_MM * mm, w * 0.9 / math.max(1, #opt[1] * 0.62)), 1)
	end
end

function widget:DrawScreen()
	if not active or spIsGUIHidden() then
		return
	end
	if not font and WG.fonts and WG.fonts.getFont then
		font = WG.fonts.getFont(2, 1.5) -- BAR's font widget may start after this one
	end
	for _, b in ipairs(visibleButtons()) do
		drawButton(b)
	end
	if radial then
		drawRadial()
	end
	if boxRect then
		glColor(1, 1, 1, 0.08)
		glRect(boxRect[1], boxRect[2], boxRect[3], boxRect[4])
		local x1, y1, x2, y2 = boxRect[1], boxRect[2], boxRect[3], boxRect[4]
		glColor(1, 1, 1, 0.7)
		glRect(x1, y1, x2, y1 + 2)
		glRect(x1, y2 - 2, x2, y2)
		glRect(x1, y1, x1 + 2, y2)
		glRect(x2 - 2, y1, x2, y2)
	end
	glColor(1, 1, 1, 1)
end
