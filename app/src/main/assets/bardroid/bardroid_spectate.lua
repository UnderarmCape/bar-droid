-- BAR Droid spectating by touch (Kailil, 2026-10-27: "a touch focused spectator only setup ... cycling through players
-- to switch player cam to, blocking the bottom left hand ui from popping up ... camera tools that follow a unit or group
-- of units ... cycle through units to follow or double tap a unit to follow them"). Only while spectating and the
-- fingers were the last input (the app reports the input as "src touch|mouse|keyboard|pad" lines, bardroid_touch.lua
-- keeps it in WG.BarDroidInput); a mouse, keyboard or gamepad gets BAR's spectating as it is.
--   a bar at the bottom, shown while BAR's player list is open (a tap on the small list opens it, bardroid_players.lua;
--   7 s without a tap on either closes both: Kailil, "only popup when I touch player list"):
--                         < player >  BAR's player camera (its Lockcamera widget, WG.lockcamera) on the next or
--                                     previous player, top to bottom as the player list shows them; the button says
--                                     the player's name
--                         Free        back to the own camera
--                         < unit >    follow the next or previous most valuable mobile unit on the map
--                         Group       follow the unit's group (its team's units around it) instead of the unit alone
--   double tap a unit:    follow it; double tap the ground: stop following
--   a finger pan:         stops the player camera and the following (pinch and twist keep following)
-- Taps on the map select nothing while this is on, so BAR's selected-unit panels (info, orders, build menu) stay away.
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid spectate",
		desc = "Touch tools for spectating: player cameras, following units",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		-- after BAR's interface (map taps reach it only when nothing else took them), before the touch camera, which
		-- answers "map" to every pointer position no widget before it claimed
		layer = 999999,
		enabled = true,
	}
end

local DOUBLE_TAP_S, DOUBLE_TAP_PX = 0.45, 40
local FOLLOW_SMOOTHING = 0.25 -- seconds: the camera glides after its target
local GROUP_RADIUS = 700 -- elmos around the group's centre
local GROUP_EVERY = 0.5 -- seconds between new group members

local spGetCameraState, spSetCameraState = Spring.GetCameraState, Spring.SetCameraState
local spGetUnitPosition = Spring.GetUnitPosition
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers

local active = false
local shown = false -- the bar: active and BAR's player list open
local buttons = {} -- { x0, y0, x1, y1, action, label, lit, color }
local follow -- { unitID, group = bool, members = {...}, cx, cz, at = timer }
local groupMode = false
local lastTap -- { x, y, t }
local pressedOn -- the button a press went down on
local panSeen = 0
local t0 = spGetTimer()

local function now()
	return spDiffTimers(spGetTimer(), t0)
end

local function lockcamera()
	return WG.lockcamera
end

local function lockedPlayer()
	local lc = lockcamera()
	return lc and lc.GetPlayerID and lc.GetPlayerID()
end

-- BAR's player camera off, the view staying where it is (BAR would glide back to the view before the lock)
local function unlockPlayer()
	if lockedPlayer() then
		local cs = spGetCameraState()
		lockcamera().SetPlayerID(nil)
		spSetCameraState(cs, 0)
	end
end

local function stopFollow()
	follow = nil
end

-- The players in the game (not spectators) top to bottom as BAR's player list shows them (gui_advplayerslist.lua
-- SortAllyTeams: the watched team's alliance first, then the others; their teams and players in the engine's order).
-- Taken once when the bar opens: the player camera changes the watched team, and the list reorders after it.
local order
local function players()
	local list, first = {}, Spring.GetMyAllyTeamID()
	local allyTeams = { first }
	for _, allyTeamID in ipairs(Spring.GetAllyTeamList() or {}) do
		if allyTeamID ~= first then
			allyTeams[#allyTeams + 1] = allyTeamID
		end
	end
	for _, allyTeamID in ipairs(allyTeams) do
		for _, teamID in ipairs(Spring.GetTeamList(allyTeamID) or {}) do
			for _, playerID in ipairs(Spring.GetPlayerList(teamID, true) or {}) do
				local name, _, spec = Spring.GetPlayerInfo(playerID, false)
				if name and not spec then
					list[#list + 1] = { id = playerID, name = name }
				end
			end
		end
	end
	return list
end

local function cyclePlayer(step)
	order = order or players()
	local list = order
	if #list == 0 or not (lockcamera() and lockcamera().SetPlayerID) then
		return
	end
	local current, at = lockedPlayer(), nil
	for i, p in ipairs(list) do
		if p.id == current then
			at = i
		end
	end
	local nextIndex = at and ((at - 1 + step) % #list + 1) or (step > 0 and 1 or #list)
	stopFollow()
	lockcamera().SetPlayerID(list[nextIndex].id)
end

-- mobile units on the map, the most valuable first
local function valuableUnits()
	local list = {}
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and (def.speed or 0) > 0 and not Spring.GetUnitIsBeingBuilt(unitID) then
			list[#list + 1] = { id = unitID, cost = def.metalCost or 0 }
		end
	end
	table.sort(list, function(a, b)
		if a.cost ~= b.cost then
			return a.cost > b.cost
		end
		return a.id < b.id
	end)
	return list
end

local function startFollow(unitID)
	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return
	end
	unlockPlayer()
	follow = { unitID = unitID, team = Spring.GetUnitTeam(unitID), cx = x, cz = z, members = { unitID }, at = -1 }
end

local function cycleUnit(step)
	local list = valuableUnits()
	if #list == 0 then
		return
	end
	local at
	for i, u in ipairs(list) do
		if follow and u.id == follow.unitID then
			at = i
		end
	end
	local nextIndex = at and ((at - 1 + step) % #list + 1) or (step > 0 and 1 or #list)
	startFollow(list[nextIndex].id)
end

-- where the camera should look: the unit, or the centre of its group (its team's units around the last centre)
local function followTarget()
	local f = follow
	local x, _, z = spGetUnitPosition(f.unitID)
	if not groupMode then
		return x, z
	end
	if now() - f.at >= GROUP_EVERY then
		f.at = now()
		local cx, cz = x or f.cx, z or f.cz
		local members = Spring.GetUnitsInCylinder(cx, cz, GROUP_RADIUS, f.team) or {}
		local sx, sz, n = 0, 0, 0
		local kept = {}
		for _, unitID in ipairs(members) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			local ux, _, uz = spGetUnitPosition(unitID)
			if def and (def.speed or 0) > 0 and ux then
				sx, sz, n = sx + ux, sz + uz, n + 1
				kept[#kept + 1] = unitID
			end
		end
		if n > 0 then
			f.cx, f.cz, f.members = sx / n, sz / n, kept
		end
		if not x and n > 0 then -- the unit is gone: the group goes on around its nearest member
			f.unitID = kept[1]
		end
	end
	if not x and #f.members == 0 then
		return nil
	end
	return f.cx, f.cz
end

local function updateFollow(dt)
	if not follow then
		return
	end
	local tx, tz = followTarget()
	if not tx then
		stopFollow()
		return
	end
	local cs = spGetCameraState()
	if not (cs.px and cs.pz) then
		return
	end
	local k = 1 - math.exp(-dt / FOLLOW_SMOOTHING)
	cs.px = cs.px + (tx - cs.px) * k
	cs.pz = cs.pz + (tz - cs.pz) * k
	cs.py = Spring.GetGroundHeight(cs.px, cs.pz)
	spSetCameraState(cs, 0)
end

local ACTIONS = {
	player_prev = function() cyclePlayer(-1) end,
	player_next = function() cyclePlayer(1) end,
	free = function() unlockPlayer(); stopFollow() end,
	unit_prev = function() cycleUnit(-1) end,
	unit_next = function() cycleUnit(1) end,
	group = function() groupMode = not groupMode; if follow then follow.at = -1 end end,
}

local function isActive()
	local spec = Spring.GetSpectatingState()
	local input = WG.BarDroidInput or "touch" -- (nothing reported yet: the app's own screen is a touch screen)
	return spec and input == "touch" and not Spring.IsGUIHidden()
end

---------------------------------------------------------------------------------------------------------------------
-- the bar

local function playerLabel()
	local id = lockedPlayer()
	if not id then
		return "Player cam", nil
	end
	local name, _, _, teamID = Spring.GetPlayerInfo(id, false)
	return name or "?", teamID and { Spring.GetTeamColor(teamID) }
end

local function followLabel()
	if not follow then
		return "Follow unit", nil
	end
	local def = UnitDefs[Spring.GetUnitDefID(follow.unitID) or -1]
	local name = def and (def.translatedHumanName or def.humanName) or "unit"
	if groupMode then
		name = name .. " +" .. math.max(0, #follow.members - 1)
	end
	return name, follow.team and { Spring.GetTeamColor(follow.team) }
end

local function layout()
	local vsx, vsy = Spring.GetViewGeometry()
	local h = math.floor(math.min(vsy * 0.085, vsx / 15))
	local gap = math.floor(h * 0.15)
	local pLabel, pColor = playerLabel()
	local fLabel, fColor = followLabel()
	local rowA = {
		{ w = h, action = "player_prev", label = "<" },
		{ w = h * 3.2, action = "player_next", label = pLabel, color = pColor, lit = lockedPlayer() ~= nil },
		{ w = h, action = "player_next", label = ">" },
		{ w = h * 1.6, action = "free", label = "Free", lit = not (lockedPlayer() or follow) },
	}
	local rowB = {
		{ w = h, action = "unit_prev", label = "<" },
		{ w = h * 3.2, action = "unit_next", label = fLabel, color = fColor, lit = follow ~= nil },
		{ w = h, action = "unit_next", label = ">" },
		{ w = h * 1.6, action = "group", label = "Group", lit = groupMode },
	}
	local function width(row)
		local w = 0
		for _, b in ipairs(row) do
			w = w + b.w + gap
		end
		return w - gap
	end
	buttons = {}
	local function place(row, x, y)
		for _, b in ipairs(row) do
			buttons[#buttons + 1] = { x0 = x, y0 = y, x1 = x + b.w, y1 = y + h, action = b.action, label = b.label,
				lit = b.lit, color = b.color, size = h }
			x = x + b.w + gap
		end
	end
	local y = math.floor(h * 0.25)
	local wa, wb = width(rowA), width(rowB)
	if wa + wb + gap * 3 <= vsx * 0.9 then -- one row
		local x = math.floor((vsx - (wa + wb + gap * 3)) / 2)
		place(rowA, x, y)
		place(rowB, x + wa + gap * 3, y)
	else -- two rows: the players above
		place(rowB, math.floor((vsx - wb) / 2), y)
		place(rowA, math.floor((vsx - wa) / 2), y + h + gap)
	end
end

local function buttonAt(x, y)
	for _, b in ipairs(buttons) do
		if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 then
			return b
		end
	end
end

function widget:DrawScreen()
	if not shown then
		return
	end
	layout()
	local font = WG.fonts and WG.fonts.getFont()
	for _, b in ipairs(buttons) do
		if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
			WG.FlowUI.Draw.Element(b.x0, b.y0, b.x1, b.y1, 1, 1, 1, 1)
		else
			gl.Color(0, 0, 0, 0.6)
			gl.Rect(b.x0, b.y0, b.x1, b.y1)
		end
		if b.lit then
			gl.Color(1, 1, 1, 0.16)
			gl.Rect(b.x0, b.y0, b.x1, b.y1)
		end
		if b.color then -- the team's colour as a strip along the bottom
			gl.Color(b.color[1], b.color[2], b.color[3], 0.9)
			gl.Rect(b.x0 + 3, b.y0 + 3, b.x1 - 3, b.y0 + math.max(3, b.size * 0.08))
		end
	end
	gl.Color(1, 1, 1, 1)
	if font then
		font:Begin()
		for _, b in ipairs(buttons) do
			local size = b.size * 0.36
			local text = b.label
			local maxW = (b.x1 - b.x0) * 0.9
			while #text > 4 and font:GetTextWidth(text) * size > maxW do
				text = text:sub(1, #text - 2) .. "."
			end
			font:Print(text, (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2 - size * 0.35, size, "oc")
		end
		font:End()
	end
end

function widget:IsAbove(x, y)
	return shown and buttonAt(x, y) ~= nil
end

function widget:GetTooltip(x, y)
	local b = shown and buttonAt(x, y)
	return b and b.label or nil
end

---------------------------------------------------------------------------------------------------------------------
-- taps

function widget:MousePress(x, y, button)
	if not active then
		return false
	end
	local b = shown and buttonAt(x, y)
	if b then
		pressedOn = b
		return true
	end
	if Spring.IsAboveMiniMap(x, y) then
		return false
	end
	-- a tap on the map: it selects nothing; a second one quickly at the same place follows the unit there
	pressedOn = nil
	local t = now()
	if button == 1 and lastTap and t - lastTap.t <= DOUBLE_TAP_S and math.abs(x - lastTap.x) <= DOUBLE_TAP_PX
		and math.abs(y - lastTap.y) <= DOUBLE_TAP_PX then
		lastTap = nil
		local what, unitID = Spring.TraceScreenRay(x, y)
		if what == "unit" then
			startFollow(unitID)
		else
			stopFollow()
		end
	elseif button == 1 then
		lastTap = { x = x, y = y, t = t }
	end
	return true
end

function widget:MouseRelease(x, y)
	local b = pressedOn
	pressedOn = nil
	if b and buttonAt(x, y) == b and ACTIONS[b.action] then
		ACTIONS[b.action]()
		if WG.BarDroidPlayers and WG.BarDroidPlayers.keepOpen then
			WG.BarDroidPlayers.keepOpen() -- (the list and the bar stay open while the bar is used)
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------

function widget:Update(dt)
	local was = active
	active = isActive()
	WG.BarDroidSpectating = active -- bardroid_info.lua shows no unit then
	-- Nothing stays selected while this is on: BAR's selected-unit panels (info, orders, build menu) never open, whatever
	-- selected the units (the two-finger swipe's select-all, a box). A frame later, not from SelectionChanged: a
	-- selection replaced there is never told to the widgets after it (BAR's build menu kept showing the builder's).
	if active and Spring.GetSelectedUnitsCount() > 0 then
		Spring.SelectUnitArray({})
	end
	-- the bar with BAR's player list: open while it is (without bardroid_players.lua: always)
	local list = WG.BarDroidPlayers
	local wasShown = shown
	shown = active and not (list and list.minimized and list.minimized())
	if shown and not wasShown then
		order = players() -- top to bottom as the list shows them now
	end
	if not active then
		if was then
			stopFollow()
		end
		return
	end
	-- a finger pan takes the camera back
	local pan = WG.BarDroidPanAt or 0
	if pan ~= panSeen then
		panSeen = pan
		unlockPlayer()
		stopFollow()
	end
	updateFollow(dt)
end

function widget:Initialize()
	-- (also for tools/spectate-test.ps1: a user widget cannot send the engine's mouse callins, so its taps come in here)
	WG.BarDroidSpectate = {
		actions = ACTIONS,
		following = function() return follow and follow.unitID end,
		members = function() return follow and #follow.members or 0 end,
		shown = function() return shown end,
		label = function() return (playerLabel()) end,
		tap = function(x, y)
			local taken = widget:MousePress(x, y, 1)
			widget:MouseRelease(x, y, 1)
			return taken
		end,
	}
end

function widget:Shutdown()
	WG.BarDroidSpectate = nil
	WG.BarDroidSpectating = nil
end
