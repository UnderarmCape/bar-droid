-- BAR Droid gamepad: the game side of the app's gamepad in BAR's own game (online, spectating). The app makes the pad a
-- mouse and keyboard rebuilt on Kailil's BAR Controller Support v0.8.5 ("Build-First Commander"; PadGame.java has the
-- whole layout) and sends what a mouse and keys cannot do as actions through bardroid_touch.lua ("act <name>"); this
-- widget does them, with what BAR lets a user widget do (Kailil, 2026-10-29: "match 1to1 using any means necessary ...
-- RB and Back + RB to teleport mouse to build menu and orders menu to replace the tactical menu radial"):
--   the order menu on the pad (Back + RB): the pointer onto its first order, the D-pad steps, the order under it lit
--     with BAR's own highlight, A gives it (an order that needs a target sends the pointer back to the middle to aim),
--     B leaves; the build menu's own (RB) is bardroid_buildmenu.lua's
--   control groups (Start + D-pad): recall, assign, BAR's autogroup (the app presses Alt+N), clear; BAR's group
--     actions, the group's number shown
--   idle units (D-pad; LB + D-pad), the commander (D-pad down), a camera bookmark (D-pad up; LT + up stores it)
--   cancel (B), LB + A/X/Y/B orders at the middle of the screen, removing queued orders (L3/R3), the D-gun (Back + R3)
--   a reticle in the middle while the pad is the input, and short notes (v0.8.5's hotkey feedback)
-- Orders at a point go to the units at once where the game allows unit-control widgets (BAR's default), else the order
-- is picked and A gives it. The app learns which menu has the pad, whether the game has started and what kind of order
-- is picked from LuaUI/Config/bardroid_pad.txt ("focus build|orders|none", "pregame 0|1",
-- "armed build|area|unitarea|other|none": a tap of A starts an area order's circle, PadGame).
-- A menu on the pad keeps the pointer on it (Kailil: "constrain the mouse within the menu bounds ... let the mouse leave
-- it if i press B only or i constantly move the left stick out of the box for ... 1 second"); the app brings the
-- pointer back to the middle afterwards, gliding.

function widget:GetInfo()
	return {
		name = "BAR Droid gamepad",
		desc = "The BAR Droid app's gamepad in BAR's game: menus, groups, idle units, orders",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -95000,
		enabled = true,
	}
end

local PAD_FILE = "LuaUI/Config/bardroid_pad.txt"
local TOAST_SECONDS = 1.3
local LEAVE_SECONDS = 0.25 -- the pointer pushed off a menu this long lets go of it (Kailil: "make it a quarter long")
local HIGHLIGHT = { 1, 0.8, 0.25 }

-- BAR's order menu (luaui/Widgets/gui_ordermenu.lua): the orders it hides, and how it lays out its grid
local HIDDEN = {
	[CMD.LOAD_ONTO] = true, [CMD.SELFD] = true, [CMD.GATHERWAIT] = true, [CMD.SQUADWAIT] = true,
	[CMD.DEATHWAIT] = true, [CMD.TIMEWAIT] = true, [CMD.AUTOREPAIRLEVEL] = true, [39812] = true, [34922] = true,
}
local HIDDEN_TYPE = { [CMDTYPE.CUSTOM] = true, [CMDTYPE.PREV] = true, [CMDTYPE.NEXT] = true }
local CANCEL_TARGET = 34924

local orders = nil -- the order menu on the pad: { index, cmdID, warped = {x, y, timer}, layout }
local toast, toastAt = nil, nil
local written, writtenAt = nil, nil
local bookmark = nil
local idleType = nil -- the type of the last idle unit picked (LB + D-pad down)
local lastIdleMobile = 0
local mouseMode = false -- Back + Start, as the app's switch (PadGame)
local controllerGame = false -- v0.8.5's game: the pad is v0.8.5's until a triple tap switches it (modV085)
local modV085 = false
-- v0.8.5's area select (A held with nothing picked: PadGame): a circle in the middle of the screen selects the player's
-- units it passes over while the camera pans; units first (buildings only when there are no units in it, or with RT:
-- added to the selection, buildings too); the D-pad sizes it, B undoes it. v0.8.5's radius: 320, 120..1200 in 80s.
local area = { on = false, radius = 320, units = {}, count = 0, keep = {}, shift = false, x = nil, y = nil, z = nil }
local warp, fakeWarp = Spring.WarpMouse, false -- (tools/touch-widget-test.ps1 records the moves instead)

local function now()
	return Spring.GetTimer()
end

-- The pad's pointer is free (the left stick moves it) before the start, or after Back + Start; else in the middle
local function freePointer()
	return mouseMode ~= (Spring.GetGameFrame() == 0 and not Spring.GetSpectatingState())
end

local function note(text)
	toast, toastAt = text, now()
end

-- Orders at a point straight to the units only where the game allows it (BAR's sandbox; the modoption is on by default)
local function unitControl()
	local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
	local v = mo.allowunitcontrolwidgets
	return v == nil or v == true or v == 1 or v == "1" or v == "true"
end

local function shiftHeld()
	local _, _, _, shift = Spring.GetModKeyState()
	return shift
end

local function selectAndLook(units)
	if #units == 0 then
		return false
	end
	Spring.SelectUnitArray(units)
	local x, y, z = Spring.GetUnitPosition(units[1])
	if x then
		Spring.SetCameraTarget(x, y, z, 0.3)
	end
	return true
end

local function myUnits()
	if Spring.GetSpectatingState() then
		return {}
	end
	return Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}
end

-- The order menu's commands in its own order (order states first, then Wait, then the rest)
local function orderCommands()
	local states, others, wait = {}, {}, nil
	local o = WG.ordermenu
	local hasTarget = false
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		if Spring.GetUnitRulesParam(unitID, "hasPriorityTarget") then
			hasTarget = true
			break
		end
	end
	for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do
		if type(cmd) == "table" and not (o.getDisabledCmd and o.getDisabledCmd(cmd.name))
			and not HIDDEN[cmd.id] and not HIDDEN_TYPE[cmd.type] and cmd.action ~= nil and not cmd.disabled
			and not (cmd.id == CANCEL_TARGET and not hasTarget) then
			if cmd.type == CMDTYPE.ICON_BUILDING or cmd.action:find("buildunit_", 1, true) == 1 then -- luacheck: ignore 542
			elseif cmd.type == CMDTYPE.ICON_MODE then
				states[#states + 1] = cmd
			elseif cmd.id == CMD.WAIT then
				wait = cmd
			else
				others[#others + 1] = cmd
			end
		end
	end
	if wait then
		states[#states + 1] = wait
	end
	for _, cmd in ipairs(others) do
		states[#states + 1] = cmd
	end
	return states
end

-- The order menu's cells as BAR lays them out (setupCellGrid in gui_ordermenu.lua), bottom left origin; nil: not shown
local function ordersLayout()
	local o = WG.ordermenu
	if not (o and o.getPosition and o.getIsShowing and o.getIsShowing()) then
		return nil
	end
	local cmds = orderCommands()
	if #cmds == 0 then
		return nil
	end
	local posX, posY, width, height = o.getPosition()
	local vsx, vsy = Spring.GetViewGeometry()
	local bp = WG.FlowUI and WG.FlowUI.elementPadding or 0
	local abp = math.floor(bp * 1.4 + 0.5)
	local ar = {
		posX * vsx + (posX > 0 and abp or math.ceil(bp * 0.6)),
		(posY - height) * vsy + (posY - height > 0 and math.floor(abp) or math.floor(abp / 3)),
		(posX + width) * vsx - abp,
		posY * vsy - abp,
	}
	local add = Spring.GetConfigFloat("ui_scale", 1) < 0.85 and -1 or 0
	local n, cols, rows = #cmds, 7 + add, 7
	for _, s in ipairs({ { 4, 4 }, { 5, 4 }, { 5, 5 }, { 5, 6 }, { 6, 6 }, { 6, 7 } }) do
		if n <= (s[1] + add) * s[2] then
			cols, rows = s[1] + add, s[2]
			break
		end
	end
	local cw, ch = math.floor((ar[3] - ar[1]) / cols), math.floor((ar[4] - ar[2]) / rows)
	local leftW = ((ar[3] - ar[1]) - cw * cols) - 1
	local leftH = ((ar[4] - ar[2]) - ch * rows) - (posY - height <= 0 and 1 or 0)
	local cells, addedH, addedHf = {}, 0, 0
	for row = 1, rows do
		local prevH = addedH
		addedHf = addedHf + leftH / rows
		addedH = math.floor(addedHf)
		local prevW, addedWf = 0, 0
		for col = 1, cols do
			addedWf = addedWf + leftW / cols
			local addedW = math.floor(addedWf)
			cells[#cells + 1] = {
				math.floor(ar[1] + prevW + cw * (col - 1) + 0.5),
				math.floor(ar[4] - addedH - ch * row + 0.5),
				math.ceil(ar[1] + addedW + cw * col + 0.5),
				math.ceil(ar[4] - prevH - ch * (row - 1) + 0.5),
			}
			prevW = addedW
		end
	end
	return { cmds = cmds, cells = cells, cols = cols, rows = rows }
end

local function ordersLight(cmdID)
	local o = WG.ordermenu
	if o and o.clearHighlights then
		o.clearHighlights()
	end
	if cmdID and o and o.setHighlight then
		o.setHighlight(cmdID, HIGHLIGHT)
	end
end

-- (the app glides the pointer back to the middle once no menu has the pad)
local function ordersEnd()
	if orders then
		ordersLight(nil)
	end
	orders = nil
end

local function ordersGo(index)
	local layout = ordersLayout()
	if not layout then
		ordersEnd()
		return
	end
	index = math.max(1, math.min(#layout.cmds, index))
	local r = layout.cells[index]
	orders = { index = index, cmdID = layout.cmds[index].id, layout = layout }
	local x, y = math.floor((r[1] + r[3]) / 2), math.floor((r[2] + r[4]) / 2)
	warp(x, y)
	orders.warped = { x, y, now() }
	ordersLight(orders.cmdID)
end

local function ordersStep(dx, dy)
	local layout = orders.layout
	local i = orders.index - 1
	local col, row = i % layout.cols + dx, math.floor(i / layout.cols) + dy
	col = (col + layout.cols) % layout.cols -- (wrapping, as the build menu's pages do)
	row = math.max(0, math.min(layout.rows - 1, row))
	local index = row * layout.cols + col + 1
	if index > #layout.cmds then
		index = dy ~= 0 and #layout.cmds or (dx > 0 and row * layout.cols + 1 or #layout.cmds)
	end
	ordersGo(index)
end

-- A on the order menu: the order as BAR's button gives it (a state changes, an order without a target is given, one
-- with a target is picked: the pointer back to the middle to aim it, A gives it there)
local function ordersSelect()
	local index = Spring.GetCmdDescIndex(orders.cmdID)
	if not index then
		return
	end
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	Spring.SetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
	local _, active = Spring.GetActiveCommand()
	if active == orders.cmdID then
		ordersEnd()
	else
		ordersGo(orders.index) -- (the menu may have changed: a state's label, Wait)
	end
end

-- The idle units: the builders' cycle is bardroid_touch.lua's; this is the rest (mobile units with nothing to do)
local function idleMobile(step)
	local idle = {}
	for _, unitID in ipairs(myUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and not def.isBuilder and (def.speed or 0) > 0 and Spring.GetUnitCommandCount(unitID) == 0
			and not Spring.GetUnitIsBeingBuilt(unitID) then
			idle[#idle + 1] = unitID
		end
	end
	if #idle == 0 then
		note("NO IDLE UNITS")
		return
	end
	table.sort(idle)
	local pick = step > 0 and idle[1] or idle[#idle]
	for i = 1, #idle do
		local id = step > 0 and idle[i] or idle[#idle + 1 - i]
		if (step > 0 and id > lastIdleMobile) or (step < 0 and id < lastIdleMobile) then
			pick = id
			break
		end
	end
	lastIdleMobile = pick
	idleType = Spring.GetUnitDefID(pick)
	selectAndLook({ pick })
end

local function idleOfType()
	local selected = Spring.GetSelectedUnits()
	local defID = idleType or (selected[1] and Spring.GetUnitDefID(selected[1]))
	if not defID then
		return
	end
	local units = {}
	for _, unitID in ipairs(myUnits()) do
		if Spring.GetUnitDefID(unitID) == defID and Spring.GetUnitCommandCount(unitID) == 0
			and not Spring.GetUnitIsBeingBuilt(unitID) then
			units[#units + 1] = unitID
		end
	end
	if #units > 0 then
		Spring.SelectUnitArray(units)
		note("IDLE " .. string.upper(UnitDefs[defID].translatedHumanName or UnitDefs[defID].humanName or "") .. " x" .. #units)
	end
end

local function commander()
	local units = {}
	for _, unitID in ipairs(myUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.customParams and def.customParams.iscommander then
			units[#units + 1] = unitID
		end
	end
	if selectAndLook(units) then
		note("COMMANDER")
	end
end

-- Where the middle of the screen (the pointer) points: a unit, else the ground
local function aim()
	local mx, my = Spring.GetMouseState()
	local kind, target = Spring.TraceScreenRay(mx, my)
	if kind == "unit" then
		return target, nil
	end
	local _, pos = Spring.TraceScreenRay(mx, my, true)
	return nil, pos
end

-- An order at the middle of the screen: given at once where allowed, else picked (A gives it)
local function orderAt(cmdID, name, unitOK)
	local selected = Spring.GetSelectedUnits()
	if #selected == 0 then
		return
	end
	local unitID, pos = aim()
	local opts = shiftHeld() and { "shift" } or {}
	if unitControl() and (pos or (unitID and unitOK)) then
		local params = unitID and unitOK and { unitID } or { pos[1], pos[2], pos[3] }
		if pcall(Spring.GiveOrderToUnitArray, selected, cmdID, params, opts) then
			note(string.upper(name))
			return
		end
	end
	Spring.SetActiveCommand(name)
	note(string.upper(name) .. ": A")
end

local function hasBuilder()
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.isBuilder then
			return true
		end
	end
	return false
end

local function enemyAt(unitID)
	return unitID and not Spring.IsUnitAllied(unitID)
end

-- L3 / R3: the next or the last queued order of the selected units removed
local function queueRemove(last)
	if not unitControl() then
		note("NOT IN THIS GAME")
		return
	end
	local removed = 0
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local queue = Spring.GetUnitCommands(unitID, -1) or {}
		local cmd = last and queue[#queue] or queue[1]
		if cmd and cmd.tag and pcall(Spring.GiveOrderToUnit, unitID, CMD.REMOVE, { cmd.tag }, 0) then
			removed = removed + 1
		end
	end
	if removed > 0 then
		note(last and "REMOVED LAST ORDER" or "REMOVED NEXT ORDER")
	end
end

local function pregameBuild()
	local pb = WG["pregame-build"]
	return Spring.GetGameFrame() == 0 and pb and pb.getPreGameDefID and pb.getPreGameDefID() ~= nil
end

-- What kind of order is picked, for the app: a building, an area only (area mex: A starts its circle, the next A ends
-- it), a unit or an area (repair, reclaim: hold A and draw for the area), another order, or none. Asked every frame:
-- a command's kind is looked up once (GetActiveCmdDesc makes a table each call)
local kindOf = {}
local function armedKind()
	if pregameBuild() then
		return "build"
	end
	local _, id = Spring.GetActiveCommand()
	if not id then
		return "none"
	elseif id < 0 then
		return "build"
	end
	local kind = kindOf[id]
	if not kind then
		local index = Spring.GetCmdDescIndex(id)
		local desc = index and Spring.GetActiveCmdDesc(index)
		local t = desc and desc.type
		if t == CMDTYPE.ICON_AREA then
			kind = "area"
		elseif t == CMDTYPE.ICON_UNIT_OR_AREA or t == CMDTYPE.ICON_UNIT_FEATURE_OR_AREA or t == CMDTYPE.ICON_UNIT_OR_RECTANGLE then
			kind = "unitarea"
		else
			kind = "other"
		end
		if desc then
			kindOf[id] = kind
		end
	end
	return kind
end

-- The area select's step: the units under the circle added, the selection set when that changed
local function areaUpdate()
	local vsx, vsy = Spring.GetViewGeometry()
	local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2), true)
	if not pos then
		area.x = nil
		return
	end
	area.x, area.y, area.z = pos[1], pos[2], pos[3]
	local added = false
	for _, unitID in ipairs(Spring.GetUnitsInCylinder(pos[1], pos[3], area.radius, Spring.GetMyTeamID()) or {}) do
		if not area.units[unitID] then
			area.units[unitID] = true
			area.count = area.count + 1
			added = true
		end
	end
	if not added then
		return
	end
	local mobile, all = {}, {}
	for unitID in pairs(area.units) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
		all[#all + 1] = unitID
		if def and (def.speed or 0) > 0 then
			mobile[#mobile + 1] = unitID
		end
	end
	local pick = (area.shift or #mobile == 0) and all or mobile
	for _, unitID in ipairs(area.keep) do
		pick[#pick + 1] = unitID
	end
	Spring.SelectUnitArray(pick)
end

local function cancel()
	if pregameBuild() then
		WG["pregame-build"].setPreGameDefID(nil)
	elseif select(2, Spring.GetActiveCommand()) then
		Spring.SetActiveCommand(0)
	else
		Spring.SelectUnitArray({})
	end
end

-- The app's build menu (bardroid_buildmenu.lua, WG.bardroidBuildmenu): RB puts the pointer on it. In the controller
-- game it runs beside v0.8.5's and shows while the app's controls have the pad (WG.BarDroidOwnsBuildMenu; Kailil, of
-- v0.8.5's own focus there: "its doing a weird selector system, i dont want that, i want a mouse cursor, with a stroke
-- just like the orders").
local function buildMenu(name)
	local b = WG.bardroidBuildmenu
	if b and b.droidPad then
		b.droidPad(name)
	end
end

local function buildFocus()
	local b = WG.bardroidBuildmenu
	return b and b.droidFocus and b.droidFocus() ~= nil or false
end

local ACTIONS = {
	pad_build = function() -- RB
		ordersEnd()
		buildMenu("build")
	end,
	pad_orders = function() -- Back + RB
		if orders then
			ordersEnd()
			return
		end
		if buildFocus() then
			buildMenu("build")
		end
		ordersGo(1)
		if not orders then
			note("NO ORDERS")
		end
	end,
	pad_select = function() -- A on the order menu
		if orders then
			ordersSelect()
		end
	end,
	area_on = function()
		local _, _, _, shift = Spring.GetModKeyState()
		area.on, area.units, area.count, area.shift = true, {}, 0, shift
		area.keep = shift and Spring.GetSelectedUnits() or {}
		if not shift then
			Spring.SelectUnitArray({})
		end
		areaUpdate()
	end,
	area_off = function()
		area.on = false
	end,
	area_cancel = function() -- B: the selection as it was before
		area.on = false
		Spring.SelectUnitArray(area.keep)
	end,
	area_bigger = function()
		area.radius = math.min(1200, area.radius + 80)
		note("AREA " .. area.radius)
	end,
	area_smaller = function()
		area.radius = math.max(120, area.radius - 80)
		note("AREA " .. area.radius)
	end,
	pad_page_next = function() -- RB / LB on the build menu: its pages (Kailil: "pressing RB or LB cycles the tabs")
		buildMenu("pagenext")
	end,
	pad_page_prev = function()
		buildMenu("pageprev")
	end,
	mod_bardroid = function() -- the triple tap in the controller game (GameActivity, through bardroid_touch.lua): the
		modV085 = false -- app's build menu in place of v0.8.5's (DrawGenesis hides v0.8.5's panel)
		WG.BarDroidOwnsBuildMenu = controllerGame or nil
		note("CONTROLLER MOD: BAR DROID")
	end,
	mod_v085 = function()
		modV085 = true
		WG.BarDroidOwnsBuildMenu = nil
		ordersEnd()
		buildMenu("back")
		note("CONTROLLER MOD: v0.8.5")
	end,
	pad_back = function()
		if orders then
			ordersEnd()
		else
			buildMenu("back")
		end
	end,
	slow_pan = function() -- Back while placing a building (v0.8.5): the pan at 30% until the building is put away
		WG.BarDroidPadSlowPan = not WG.BarDroidPadSlowPan
		note(WG.BarDroidPadSlowPan and "SLOW PAN" or "FULL PAN")
	end,
	cancel = cancel,
	commander = commander,
	idle_mobile_next = function() idleMobile(1) end,
	idle_mobile_prev = function() idleMobile(-1) end,
	idle_type = idleOfType,
	bookmark_store = function()
		bookmark = Spring.GetCameraState()
		note("BOOKMARK SET")
	end,
	bookmark_recall = function()
		if bookmark then
			Spring.SetCameraState(bookmark, 0.4)
		else
			note("LT + UP SETS A BOOKMARK")
		end
	end,
	rotate_left = function() Spring.SendCommands("buildfacing dec") end,
	rotate_right = function() Spring.SendCommands("buildfacing inc") end,
	spacing_up = function() Spring.SendCommands("buildspacing inc") end,
	spacing_down = function() Spring.SendCommands("buildspacing dec") end,
	lb_a = function() -- builders: repair (picked: A on a unit, or drag an area); else attack the enemy there, or fight
		if hasBuilder() then
			Spring.SetActiveCommand("repair")
			note("REPAIR: A")
			return
		end
		local unitID = aim()
		if enemyAt(unitID) then
			orderAt(CMD.ATTACK, "attack", true)
		else
			orderAt(CMD.FIGHT, "fight", false)
		end
	end,
	lb_x = function() -- builders: reclaim (picked); else attack there
		if hasBuilder() then
			Spring.SetActiveCommand("reclaim")
			note("RECLAIM: A")
			return
		end
		orderAt(CMD.ATTACK, "attack", true)
	end,
	lb_y = function()
		orderAt(CMD.PATROL, "patrol", false)
	end,
	lb_b = function()
		Spring.SetActiveCommand("stop")
		note("STOP")
	end,
	lb_b2 = function()
		Spring.SetActiveCommand("repeat")
		note("REPEAT")
	end,
	lb_b_hold = function()
		Spring.SetActiveCommand("wait")
		note("WAIT")
	end,
	queue_remove_first = function() queueRemove(false) end,
	queue_remove_last = function() queueRemove(true) end,
	dgun = function()
		for _, unitID in ipairs(Spring.GetSelectedUnits()) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			if def and def.customParams and def.customParams.iscommander then
				Spring.SetActiveCommand("manualfire")
				note("D-GUN: A")
				return
			end
		end
		note("SELECT THE COMMANDER")
	end,
	mouse_toggle = function() -- Back + Start (the app keeps the same switch)
		mouseMode = not mouseMode
		note(freePointer() and "MOUSE ON" or "MOUSE OFF")
	end,
}

-- control groups: group_<recall|assign|auto|clear|show>_<1..9>
local function group(kind, n)
	if kind == "recall" then
		Spring.SendCommands("group select " .. n)
		if #Spring.GetSelectedUnits() > 0 then
			Spring.SendCommands("viewselection")
			note("GROUP " .. n)
		else
			note("GROUP " .. n .. " EMPTY")
		end
	elseif kind == "assign" then
		Spring.SendCommands("group set " .. n)
		note("GROUP " .. n .. " SET")
	elseif kind == "auto" then
		note("GROUP " .. n .. ": THIS TYPE FROM NOW ON")
	elseif kind == "clear" then
		local keep = Spring.GetSelectedUnits()
		Spring.SendCommands("group select " .. n)
		Spring.SendCommands("group unset")
		Spring.SelectUnitArray(keep)
		note("GROUP " .. n .. " CLEARED")
	else
		note("GROUP " .. n)
	end
end

local function act(name)
	local action = ACTIONS[name]
	if action then
		action()
		return true
	end
	local kind, n = name:match("^group_(%a+)_(%d)$")
	if kind then
		group(kind, n)
		return true
	end
	-- the D-pad on a menu
	local dir = name:match("^pad_(%a+)$")
	if dir == "left" or dir == "right" or dir == "up" or dir == "down" then
		if orders then
			ordersStep(dir == "left" and -1 or dir == "right" and 1 or 0, dir == "up" and -1 or dir == "down" and 1 or 0)
		else
			buildMenu(dir)
		end
		return true
	end
	return false
end

-- The order menu on the pad follows the pointer once it is the player's again (the warp landed, or half a second),
-- keeps it on the menu (pushed off it for LEAVE_SECONDS it lets go) and ends when the menu goes; the app is told
-- which menu has the pad and what is picked
function widget:Update()
	if orders then
		local layout = ordersLayout()
		if not layout then
			ordersEnd()
		else
			orders.layout = layout
			local mx, my = Spring.GetMouseState()
			local w = fakeWarp or orders.warped
			if w and not fakeWarp and ((math.abs(mx - w[1]) <= 2 and math.abs(my - w[2]) <= 2) or Spring.DiffTimers(now(), w[3]) > 0.5) then
				orders.warped, w = nil, nil
			end
			if not w then
				local over
				for i, r in ipairs(layout.cells) do
					if i <= #layout.cmds and mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then
						over = i
						break
					end
				end
				if over and over ~= orders.index then
					orders.index, orders.cmdID = over, layout.cmds[over].id
					ordersLight(orders.cmdID)
				end
				local first, last = layout.cells[1], layout.cells[#layout.cells]
				local x0, y0, x1, y1 = first[1] + 2, last[2] + 2, last[3] - 2, first[4] - 2
				if mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
					orders.outSince = nil
				elseif not orders.outSince then
					orders.outSince = now()
					warp(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				elseif Spring.DiffTimers(now(), orders.outSince) >= LEAVE_SECONDS then
					ordersEnd()
				else
					warp(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				end
			end
		end
	end
	if area.on then
		areaUpdate()
	end
	local armed = armedKind()
	if armed ~= "build" and WG.BarDroidPadSlowPan then -- (the slow pan is for placing only, as in v0.8.5)
		WG.BarDroidPadSlowPan = nil
	end
	local focus = orders and "orders" or (buildFocus() and "build" or "none")
	local pregame = Spring.GetGameFrame() == 0 and not Spring.GetSpectatingState()
	local text = "focus " .. focus .. "\npregame " .. (pregame and 1 or 0) .. "\narmed " .. armed .. "\n"
	local t = now()
	if text ~= written or ((focus ~= "none" or pregame or armed ~= "none") and Spring.DiffTimers(t, writtenAt) > 1) then
		local f = io.open(PAD_FILE, "w")
		if f then
			f:write(text)
			f:close()
			written, writtenAt = text, t
		end
	end
end

-- The area select's circle on the ground
function widget:DrawWorld()
	if area.on and area.x then
		gl.DepthTest(false)
		gl.LineWidth(2.5)
		gl.Color(area.shift and 1 or 0.35, area.shift and 0.85 or 1, 0.35, 0.9)
		gl.DrawGroundCircle(area.x, area.y, area.z, area.radius, 48)
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
	end
end

-- The controller game with the app's controls: v0.8.5's build menu panel hidden through its own switch
-- (controllerSetPanelVisible); v0.8.5's camera widget sets that switch again in each Update, so here, after every
-- Update and before anything is drawn or clicked
function widget:DrawGenesis()
	local b = WG.buildmenu
	if WG.BarDroidOwnsBuildMenu and b and b ~= WG.bardroidBuildmenu and b.controllerSetPanelVisible then
		b.controllerSetPanelVisible(false)
	end
end

-- The reticle in the middle of the screen while the pad is the input (and its pointer is there), and the notes
function widget:DrawScreen()
	local vsx, vsy = Spring.GetViewGeometry()
	local cx, cy = math.floor(vsx / 2), math.floor(vsy / 2)
	local pad = WG.BarDroidInput == "pad"
	if pad and not modV085 and not orders and not buildFocus() and not freePointer() then
		local r = math.max(8, math.floor(vsy * 0.018))
		gl.Color(1, 1, 1, 0.55)
		gl.LineWidth(2)
		gl.BeginEnd(GL.LINE_LOOP, function()
			for i = 0, 23 do
				local a = i / 24 * 2 * math.pi
				gl.Vertex(cx + math.cos(a) * r, cy + math.sin(a) * r)
			end
		end)
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
	end
	if toast then
		local age = Spring.DiffTimers(now(), toastAt)
		local font = WG.fonts and WG.fonts.getFont()
		if age > TOAST_SECONDS or not font then
			toast = age > TOAST_SECONDS and nil or toast
			return
		end
		local size = math.max(14, math.floor(vsy * 0.03))
		local alpha = math.min(1, (TOAST_SECONDS - age) / 0.3)
		font:Begin()
		font:SetTextColor(1, 0.9, 0.5, alpha)
		font:Print(toast, cx, cy + vsy * 0.08, size, "oc")
		font:End()
	end
end

function widget:Initialize()
	-- the controller game (as bardroid_touch.lua finds it): the pad is v0.8.5's until a triple tap switches it
	local ok, found = pcall(VFS.FileExists, "LuaUI/Widgets/controller_socket_bridge.lua", VFS.ZIP)
	controllerGame = (ok and found) or Game.gameVersion == "$VERSION"
	modV085 = controllerGame
	WG.BarDroidPad = {
		act = act,
		-- (tools/touch-widget-test.ps1: the order on the pad, its place in the menu, the menu's size; putting the pad on
		-- one order; pointer moves recorded instead of made)
		orders = function()
			return orders and orders.cmdID, orders and orders.index, orders and #orders.layout.cmds
		end,
		ordersOn = function(cmdID)
			local layout = ordersLayout()
			for i, cmd in ipairs(layout and layout.cmds or {}) do
				if cmd.id == cmdID then
					ordersGo(i)
					return true
				end
			end
			return false
		end,
		setWarp = function(fn)
			warp, fakeWarp = fn or Spring.WarpMouse, fn ~= nil
		end,
		note = function()
			return toast
		end,
		area = function() -- (the area select: on, its radius, how many units it has passed over)
			return area.on, area.radius, area.count
		end,
	}
end

function widget:Shutdown()
	ordersEnd()
	WG.BarDroidPad = nil
	WG.BarDroidOwnsBuildMenu = nil
	local f = io.open(PAD_FILE, "w")
	if f then
		f:write("focus none\npregame 0\narmed none\n")
		f:close()
	end
end
