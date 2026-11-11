-- BAR Droid build menu: BAR's own Build menu (luaui/Widgets/gui_buildmenu.lua, by Floris, GPL v2 or later), from
-- Beyond All Reason test-31836-b250a16, unchanged except where marked "BAR Droid:" (Kailil, 2026-10-28: "the vaniallal build menu works fine for
-- touch. just rebuild the exact same one with the ability for us to resize it freely"): its place and size come from
-- the app's layout editor (bardroid_layout.lua), and the widget-handler calls go through BAR's stand-in for the handler
-- that user widgets get. Made by tools/make-buildmenu.py; do not edit by hand, run it again.
-- launch-bar.sh runs it instead of BAR's Build menu; when an update changes BAR's file the phone makes it again from the
-- new file (the line below names the one it was made from; Installer, BuildMenuPatches); in the controller game, which keeps its
-- own ("Build menu (controller)", v0.8.5's gamepad drives it), this one runs beside it and shows only while the app's
-- gamepad controls have the pad (a triple tap switches; WG.bardroidBuildmenu there, BAR's WG.buildmenu stays v0.8.5's).
-- BARDROID_BUILDMENU_FROM 5fd93aec8f49ed557597312788ecdb14
local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "BAR Droid build menu", -- BAR Droid: its own name (BAR ignores copies under BAR's)
		desc = "BAR's Build menu, its size and place set with the BAR Droid layout editor",
		author = "Floris (BAR's Build menu), BAR Droid",
		date = "April 2020",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = false, -- BAR Droid: launch-bar.sh switches it on in place of BAR's Build menu (no handler: a user widget)
	}
end

-- Localized functions for performance
local mathFloor = math.floor
local mathMax = math.max

-- Localized Spring API for performance
local spGetGameFrame = Spring.GetGameFrame
local spGetGameSeconds = Spring.GetGameSeconds
local spGetMyTeamID = Spring.GetLocalTeamID
local spGetViewGeometry = Spring.GetViewGeometry
local spGetSpectatingState = Spring.GetSpectatingState

include("keysym.h.lua")
local dynamicBuildOptions = require("common/dynamicBuildOptions")

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local string_format = string.format
local table_invert = table.invert
local pcall = pcall
--- CHANGE START ---
-- Helper function to clear a table without creating garbage, using the standard Lua method.
local function clearTable(t)
	for k in pairs(t) do
		t[k] = nil
	end
end
--- CHANGE END ---

SYMKEYS = table_invert(KEYSYMS)

local CMD_STOP_PRODUCTION = GameCMD.STOP_PRODUCTION

local comBuildOptions
local boundUnits = {}
local stickToBottom = false

local alwaysShow = false

local cfgCellPadding = 0.007
local cfgIconPadding = 0.015 -- space between icons
local cfgIconCornerSize = 0.025
local cfgPriceFontSizeFourColls = 0.16
local cfgPriceFontSizeFiveColls = 0.19
local cfgActiveAreaMargin = 0.1 -- (# * bgpadding) space between the background border and active area

local defaultColls = 5
local dynamicIconsize = true
local minColls = 4
local maxColls = 5

local smartOrderUnits = true

local maxPosY = 0.74
-- BAR Droid: what the app adds, in one table (BAR's file is near Lua 5.1's limit of 200 locals in a chunk). At the left
-- a grid of colls x rows square cells across the menu's width (Kailil, 2026-10-28: "a 3x3 grid"), and the page arrows and
-- number in a strip under it, strip x a cell's height ("move the left and right arrows into their own small strip,
-- it will be about a quarter the height ... that will allow 3x3 items on top"; then "the page swapper and inidcator
-- needs to be bigger. double the size": half a cell, their text pageText x BAR's): 9 options a page. (BAR's own
-- paging gave a whole row to the arrows: 6 a page, the first version of this.)
-- While a building is picked the strip holds the building shapes instead (droid.place): ONE, LINE, GRID, BORDER
-- (Kailil, 2026-10-28, choosing "the build menu's own page strip turns into ONE . LINE . GRID . BORDER" for the touch
-- building of 2026-10-25, which he had removed as "ugly and clunky to switch between"), and a big green PLACE button
-- lies over the order menu with rotate and cancel inside it ("one tap needs to have a done confirmation ... appear on
-- top of the orders menu as one big green button saying done or place"; "Get rid of the circle and x and move those to
-- the order menu button popup with done as smaller sub buttons"): a tap on the map picks the spot (droid.spot, the
-- building drawn there), PLACE builds it there (the app clicks the spot with Shift held: RtsTouch).
-- The gamepad (the app makes it a mouse and keys in BAR's game; Kailil: "try your best to finesse a way" to v0.8.5's
-- feel, "RB with builder selected snaps the mouse to the build menu grid spot one, then a highlight stroke and
-- enlargement of like 10 percent of the build item ... pressing A snaps the mouse to the center of the screen ready to
-- place it"): RB puts the pointer on the menu's first option (droid.focus), the D-pad steps from option to option
-- (past the left or right edge: the page before or after), the option under the pointer is drawn 10% bigger with a
-- gold outline, A (a click) picks it and the pointer goes to the middle of the screen; B leaves the menu.
-- bardroid_pad.lua tells the app (droidFocus) and routes the pad's actions here (droidPad).
-- With ONE (Kailil, 2026-10-29) the app moves the waiting building (droid.spot) under a dragging finger or by a nudge,
-- and a finger held still (or a drag from the building) makes it the first corner of a GRID: the app holds BAR's own
-- build drag down with Shift+Alt, the engine draws it, and PLACE or a double tap lets go (droid.gridHeld: PLACE lit;
-- "GRID" shown for a moment, droid.gridShown).
local droid = { colls = 3, maxColls = 5, rows = 3, strip = 0.5, pageText = 2, gap = 0, registered = false,
	shape = "one", armed = false, defID = nil, spot = nil, panel = nil, written = nil, writtenAt = nil, shapeRects = {},
	gridHeld = nil, gridShown = nil, gridToast = 1.2, nudgeCarry = { 0, 0 },
	file = "LuaUI/Config/bardroid_place.txt",
	focus = nil, warped = nil, warpTo = nil, warp = Spring.WarpMouse, fakeWarp = false, ctl = false, shared = nil,
	wasActive = nil, leave = 0.25, settled = 150, redraw = 900, drawnAt = nil,
	items = { { "one", "ONE" }, { "line", "LINE" }, { "grid", "GRID" }, { "border", "BORDER" } } }

local disableInputWhenSpec = false -- disable specs selecting buildoptions

local showPrice = true -- false will still show hover
local showRadarIcon = true -- false will still show hover
local showGroupIcon = true -- false will still show hover
local showBuildProgress = true
local progressColor = { 0.08, 0.08, 0.08, 0.6 }
local drawnBuildTargets = {}

-- Highlight API state: { [unitDefID] = { color={r,g,b}, startTime=os_clock() } }
local highlights = {}
local highlightCount = 0
local defaultHighlightColor = { 1.0, 1.0, 1.0 }

local zoomMult = 1.5
local defaultCellZoom = 0.025 * zoomMult
local rightclickCellZoom = 0.033 * zoomMult
local clickCellZoom = 0.07 * zoomMult
local hoverCellZoom = 0.05 * zoomMult
local clickSelectedCellZoom = 0.125 * zoomMult
local selectedCellZoom = 0.135 * zoomMult

local bgpadding, activeAreaMargin
local dlistGuishader, dlistBuildmenuBg, dlistBuildmenu, font2
local doUpdate, ordermenuHeight, prevAdvplayerlistLeft
local cellPadding, iconPadding, cornerSize, cellInnerSize, cellSize, priceFontSize
local activeCmd, selBuildQueueDefID
local prevHoveredCellID, hoverDlist
local buildmenuTexHasContent = false
local buildmenuRenderedCells = 0

local math_isInRect = math.isInRect

local buildmenuShows = false
local refreshBuildmenu = true
local delayRefresh

local costOverrides = {}
--[[ MODIFICATION START ]]
-- New state variables for the robust update system
local selectionUpdateTime = 0 -- Time-based debouncer for selection changes
local raceConditionUpdateCountdown = 0 -- Timer for race conditions
local forceRefreshNextFrame = false -- The failsafe retry flag
local refreshRetryCounter = 0 -- Failsafe counter to prevent infinite retries
--[[ MODIFICATION END ]]

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local playSounds = true
local sound_queue_add = "LuaUI/Sounds/buildbar_add.wav"
local sound_queue_rem = "LuaUI/Sounds/buildbar_rem.wav"

local vsx, vsy = spGetViewGeometry()

local ordermenuLeft = mathFloor(vsx / 5)
local advplayerlistLeft = vsx * 0.8

local ui_opacity = Spring.GetConfigFloat("ui_opacity", 0.7)
local ui_scale = Spring.GetConfigFloat("ui_scale", 1)

local units = require("luaui/configs/unit_buildmenu_config")

local isSpec = spGetSpectatingState()
local myTeamID = spGetMyTeamID()

local startDefID = Spring.GetTeamRulesParam(myTeamID, "startUnit")

local disableInput = disableInputWhenSpec and isSpec
---@type ScreenRect
local backgroundRect = { 0, 0, 0, 0 }
local colls = 5
local rows = 5
local minimapHeight = 0.235
local posY = 0
local posY2 = 0
local posX = 0
local posX2 = 0.2
local width = 0
local height = 0
local selectedBuilders = {}
local selectedBuilderCount = 0
local selectedFactoryCount = 0
local prevAnyFactoryUnfinished = false
local cellRects = {}
local cmds = {}
local cmdsCount = 0
local currentPage = 1
local pages = 1
local paginatorRects = {}
local preGamestartPlayer = spGetGameFrame() == 0 and not isSpec

local unitDefToCellMap = {}
local cellQuotas = {}

-- Reusable tables to reduce allocations in hot paths
local cmdUnitdefsTemp = {}
local selBuilderDefsTemp1 = {}
local selBuilderDefsTemp2 = {}
local currentSelBuilderDefs = selBuilderDefsTemp1 -- Track which temp table is current
local buildCycleTemp = {}
local emptyParams = {}
local buildmenuUnitpicWarm = { warmed = {}, queued = {}, queuedSet = {}, count = 0 }
local buildmenuUnitpicWarmPerFrame = 2

-- Cache for expensive Spring API calls
local cachedActiveCmdDescs = nil
local cachedActiveCmdDescsTime = 0
local activeCmdDescsCacheDelay = 0.05 -- Cache for 50ms

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local unitName = {}
local unitBuildOptions = {}
local unitBuildOptionSet = {} -- unitDefID -> { buildOptionDefID = true }
local unitMetal_extractor = {}
local unitTranslatedHumanName = {}
local unitTranslatedTooltip = {}
local iconTypes = {}
local function refreshUnitDefs()
	unitName = {}
	unitBuildOptions = {}
	unitBuildOptionSet = {}
	unitMetal_extractor = {}
	unitTranslatedHumanName = {}
	unitTranslatedTooltip = {}
	iconTypes = {}
	local orgIconTypes = require("gamedata/icontypes")
	for udid, ud in pairs(UnitDefs) do
		unitName[udid] = ud.name
		unitBuildOptions[udid] = ud.buildOptions
		unitTranslatedHumanName[udid] = ud.translatedHumanName
		unitTranslatedTooltip[udid] = ud.translatedTooltip
		if ud.customParams.metal_extractor then
			unitMetal_extractor[udid] = ud.customParams.metal_extractor
		end
		if ud.iconType and orgIconTypes[ud.iconType] and orgIconTypes[ud.iconType].bitmap then
			iconTypes[ud.name] = orgIconTypes[ud.iconType].bitmap
		end
	end
	dynamicBuildOptions.apply(unitBuildOptions)
	for udid, buildOptions in pairs(unitBuildOptions) do
		local set = {}
		for i = 1, #buildOptions do
			set[buildOptions[i]] = true
		end
		unitBuildOptionSet[udid] = set
	end
end

local spIsUnitSelected = Spring.IsUnitSelected
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetActiveCommand = Spring.GetActiveCommand
local spGetActiveCmdDescs = Spring.GetActiveCmdDescs
local spGetCmdDescIndex = Spring.GetCmdDescIndex
local spGetUnitDefID = Spring.GetUnitDefID
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spGetMouseState = Spring.GetMouseState
local spGetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local spGetUnitIsBuilding = Spring.GetUnitIsBuilding

local SelectedUnitsCount = spGetSelectedUnitsCount()

local string_sub = string.sub
local os_clock = os.clock

local math_floor = mathFloor
local math_ceil = math.ceil
local math_max = mathMax
local math_min = math.min

local glTexture = gl.Texture
local glColor = gl.Color
local glBlending = gl.Blending
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA
local GL_ONE = GL.ONE
local GL_DST_ALPHA = GL.DST_ALPHA
local GL_ONE_MINUS_SRC_COLOR = GL.ONE_MINUS_SRC_COLOR

-- Helper function for cached Spring API calls (must be after localizations)
local function getCachedActiveCmdDescs()
	local now = os_clock()
	if not cachedActiveCmdDescs or (now - cachedActiveCmdDescsTime) > activeCmdDescsCacheDelay then
		cachedActiveCmdDescs = spGetActiveCmdDescs()
		cachedActiveCmdDescsTime = now
	end
	return cachedActiveCmdDescs
end

---Greyed out when blocked for the team, or for every selected builder type that offers it.
local function isUnitRestricted(uDefID)
	if preGamestartPlayer then
		return units.isRestricted(uDefID, startDefID)
	end
	if units.unitRestricted[uDefID] then
		return true
	end
	local anyBlocked = false
	for builderDefID in pairs(currentSelBuilderDefs) do
		local blocked = units.builderUnitRestricted[builderDefID]
		if blocked and blocked[uDefID] then
			anyBlocked = true
		elseif unitBuildOptionSet[builderDefID][uDefID] then
			return false -- a selected builder of another type can still build it
		end
	end
	return anyBlocked
end

local function clearBuildmenuUnitpicWarmQueue()
	local warm = buildmenuUnitpicWarm
	for defID in pairs(warm.queuedSet) do
		warm.queuedSet[defID] = nil
	end
	for i = 1, warm.count do
		warm.queued[i] = nil
	end
	warm.count = 0
end

local function queueBuildmenuUnitpicWarm(unitDefID)
	local warm = buildmenuUnitpicWarm
	if unitDefID and not warm.warmed[unitDefID] and not warm.queuedSet[unitDefID] then
		warm.count = warm.count + 1
		warm.queued[warm.count] = unitDefID
		warm.queuedSet[unitDefID] = true
	end
end

local function queueBuildmenuUnitpicWarmFromCommands()
	clearBuildmenuUnitpicWarmQueue()
	local numCellsPerPage = rows * colls
	local startCellID = numCellsPerPage * (currentPage - 1)
	local maxCellRectID = numCellsPerPage * currentPage
	if maxCellRectID > cmdsCount then
		maxCellRectID = cmdsCount
	end
	for cellRectID = startCellID + 1, maxCellRectID do
		local cmd = cmds[cellRectID]
		if cmd and cmd.id then
			queueBuildmenuUnitpicWarm(-cmd.id)
		end
	end
end

local function flushBuildmenuUnitpicWarmQueue()
	local warm = buildmenuUnitpicWarm
	local count = warm.count
	if count <= 0 then
		return true
	end

	tracy.ZoneBeginN("W:BuildMenu:UnitpicWarmup")
	local limit = math_min(count, buildmenuUnitpicWarmPerFrame)
	for i = 1, limit do
		local unitDefID = warm.queued[i]
		if unitDefID then
			if glTexture("#" .. unitDefID) then
				warm.warmed[unitDefID] = true
			end
			warm.queuedSet[unitDefID] = nil
		end
	end
	glTexture(false)
	if limit < count then
		for i = limit + 1, count do
			local unitDefID = warm.queued[i]
			local newIndex = i - limit
			warm.queued[newIndex] = unitDefID
			warm.queued[i] = nil
		end
		warm.count = count - limit
	else
		for i = 1, count do
			warm.queued[i] = nil
		end
		warm.count = 0
	end
	tracy.ZoneEnd()

	return warm.count == 0
end

local RectRound, RectRoundProgress, UiUnit, UiElement, UiButton, elementCorner

local folder = "LuaUI/Images/groupicons/"
local groups = {
	energy = folder .. "energy.png",
	metal = folder .. "metal.png",
	builder = folder .. "builder.png",
	buildert2 = folder .. "buildert2.png",
	buildert3 = folder .. "buildert3.png",
	buildert4 = folder .. "buildert4.png",
	util = folder .. "util.png",
	weapon = folder .. "weapon.png",
	explo = folder .. "weaponexplo.png",
	weaponaa = folder .. "weaponaa.png",
	weaponsub = folder .. "weaponsub.png",
	aa = folder .. "aa.png",
	emp = folder .. "emp.png",
	sub = folder .. "sub.png",
	nuke = folder .. "nuke.png",
	antinuke = folder .. "antinuke.png",
}

local modKeyMultiplier = {
	ctrl = 20,
	shift = 5,
	right = -1,
}

local function isFiniteNumber(value)
	return value and value == value and value > -math.huge and value < math.huge
end

local function isValidRect(x1, y1, x2, y2)
	return isFiniteNumber(x1)
		and isFiniteNumber(y1)
		and isFiniteNumber(x2)
		and isFiniteNumber(y2)
		and x2 > x1
		and y2 > y1
end

local function isValidBuildmenuGeometry()
	return isValidRect(backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4])
		and isFiniteNumber(width)
		and isFiniteNumber(height)
		and width > 0
		and height > 0
		and isFiniteNumber(cellSize)
		and cellSize > 0
		and isFiniteNumber(cellPadding)
		and isFiniteNumber(iconPadding)
		and cellSize > ((cellPadding + iconPadding) * 2)
end

local function checkGuishader(force)
	if WG.guishader then
		if force and dlistGuishader then
			dlistGuishader = gl.DeleteList(dlistGuishader)
		end
		if
			not dlistGuishader
			and isValidRect(backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4])
		then
			dlistGuishader = gl.CreateList(function()
				RectRound(backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4], elementCorner)
			end)
			if selectedBuilderCount > 0 then
				WG.guishader.InsertDlist(dlistGuishader, "buildmenu")
			end
		end
	elseif dlistGuishader then
		dlistGuishader = gl.DeleteList(dlistGuishader)
	end
end

function widget:PlayerChanged(playerID)
	isSpec = spGetSpectatingState()
	myTeamID = spGetMyTeamID()
end

local function UpdateGridGeometry()
	tracy.ZoneBeginN("W:BuildMenu:UpdateGridGeometry")
	local activeArea = {
		backgroundRect[1] + (stickToBottom and bgpadding or 0) + activeAreaMargin,
		backgroundRect[2] + (stickToBottom and 0 or bgpadding) + activeAreaMargin,
		backgroundRect[3] - bgpadding - activeAreaMargin,
		backgroundRect[4] - bgpadding - activeAreaMargin,
	}
	local contentHeight = activeArea[4] - activeArea[2]
	local contentWidth = activeArea[3] - activeArea[1]
	local maxCellSize = contentHeight / 2
	-- determine grid size
	if not dynamicIconsize then
		colls = defaultColls
		cellSize = math_min(maxCellSize, math_floor((contentWidth / colls)))
		rows = math_floor(contentHeight / cellSize)
	else
		colls = minColls
		cellSize = math_min(maxCellSize, math_floor((contentWidth / colls)))

		rows = math_floor(contentHeight / cellSize)
		if minColls < maxColls then
			while cmdsCount > rows * colls do
				colls = colls + 1
				cellSize = math_min(maxCellSize, math_floor((contentWidth / colls)))
				rows = math_floor(contentHeight / cellSize)
				if colls == maxColls then
					break
				end
			end
		end
		if stickToBottom then
			if rows > 1 and cmdsCount <= (colls - 1) * rows then
				colls = colls - 1
				cellSize = math_min(maxCellSize, math_floor((contentHeight / rows)))
			end
		end
	end

	-- BAR Droid: the grid at the left, droid.colls x droid.rows, the page strip under it. Where the menu's height keeps
	-- the cells smaller than a third of its width (a wide, short screen: the Fold7 folded, the dev phone) more columns
	-- of that size fill the sides that stood empty, up to droid.maxColls (Kailil, 2026-11-02: "try 5 x 3")
	droid.gap = 0
	if not stickToBottom then
		colls = droid.colls
		cellSize = math_floor(math_min(contentWidth / colls, contentHeight / (droid.rows + droid.strip)))
		colls = math_max(colls, math_min(droid.maxColls, math_floor(contentWidth / math_max(1, cellSize))))
		rows = droid.rows
		droid.gap = math_floor((contentWidth - colls * cellSize) / 2) -- (the grid in the middle of the menu)
	end

	-- adjust grid size when pages are needed
	local paginatorCellHeight = math_floor(contentHeight - (rows * cellSize))
	if cmdsCount > colls * rows then
		pages = math_ceil(cmdsCount / (colls * rows))
		-- when more than 1 page: reserve bottom row for paginator and calc again
		if pages > 1 then
			pages = math_ceil(cmdsCount / (colls * (rows - 1)))
		end
		if currentPage > pages then
			currentPage = pages
		end

		-- remove a row if there isn't enough room for the paginator UI
		if not stickToBottom then
			if paginatorCellHeight < (0.06 * (1 - ((colls / 4) * 0.25))) * vsy then
				rows = rows - 1
			end
		else
			if paginatorCellHeight < (0.06 * (1 - ((rows / 4) * 0.25))) * vsx then
				colls = colls - 1
			end
		end
	else
		currentPage = 1
		pages = 1
	end
	-- BAR Droid: at the left all droid.rows stay items, the arrows in the strip under them
	if not stickToBottom then
		rows = droid.rows
		pages = math_max(1, math_ceil(cmdsCount / (colls * rows)))
		if currentPage > pages then
			currentPage = pages
		end
	end

	-- these are globals so it can be reused (hover highlight)
	cellPadding = math_floor(cellSize * cfgCellPadding)
	iconPadding = math_max(1, math_floor(cellSize * cfgIconPadding))
	cornerSize = math_floor(cellSize * cfgIconCornerSize)
	cellInnerSize = cellSize - cellPadding - cellPadding
	priceFontSize =
		math_floor((cellInnerSize * (colls == 5 and cfgPriceFontSizeFiveColls or cfgPriceFontSizeFourColls)) + 0.5)
	tracy.ZoneEnd()
end

local function RefreshCommands()
	tracy.ZoneBeginN("W:BuildMenu:RefreshCommands")
	tracy.ZoneBeginN("W:BuildMenu:RefreshCommands:Collect")
	-- Clear and reuse cmds table instead of creating new one
	for i = #cmds, 1, -1 do
		cmds[i] = nil
	end
	cmdsCount = 0
	clearTable(cellRects)

	if preGamestartPlayer then
		if startDefID then
			-- Clear and reuse temp table instead of creating new one
			clearTable(cmdUnitdefsTemp)
			for i, udefid in ipairs(unitBuildOptions[startDefID]) do
				cmdUnitdefsTemp[udefid] = i
			end
			for k, uDefID in ipairs(units.unitOrder) do
				if cmdUnitdefsTemp[uDefID] and not units.unitHidden[uDefID] then
					cmdsCount = cmdsCount + 1
					-- mimic output of spGetActiveCmdDescs
					cmds[cmdsCount] = {
						id = -uDefID,
						name = unitName[uDefID],
						params = emptyParams,
					}
				end
			end
		end
	else
		local activeCmdDescs = getCachedActiveCmdDescs()
		if smartOrderUnits then
			-- Clear and reuse temp table instead of creating new one
			clearTable(cmdUnitdefsTemp)
			for index, cmd in ipairs(activeCmdDescs) do
				if type(cmd) == "table" then
					if not cmd.disabled and string_sub(cmd.action, 1, 10) == "buildunit_" then
						cmdUnitdefsTemp[-cmd.id] = index
					end
				end
			end
			for k, uDefID in ipairs(units.unitOrder) do
				if cmdUnitdefsTemp[uDefID] and not units.unitHidden[uDefID] then
					cmdsCount = cmdsCount + 1
					cmds[cmdsCount] = activeCmdDescs[cmdUnitdefsTemp[uDefID]]
				end
			end
		else
			for index, cmd in ipairs(activeCmdDescs) do
				if type(cmd) == "table" then
					local uDefID = -cmd.id
					if
						not cmd.disabled
						and string_sub(cmd.action, 1, 10) == "buildunit_"
						and not units.unitHidden[uDefID]
					then
						cmdsCount = cmdsCount + 1
						cmds[cmdsCount] = cmd
					end
				end
			end
		end
	end
	tracy.ZoneEnd()

	--[[ MODIFICATION START ]]
	-- Failsafe check with reset logic
	if (not preGamestartPlayer) and cmdsCount == 0 and selectedBuilderCount > 0 then
		forceRefreshNextFrame = true
		refreshRetryCounter = 10 -- Set a retry limit
	else
		-- On success, explicitly cancel any ongoing retry
		forceRefreshNextFrame = false
		refreshRetryCounter = 0
	end
	--[[ MODIFICATION END ]]

	tracy.ZoneBeginN("W:BuildMenu:RefreshCommands:GridGeometry")
	UpdateGridGeometry()
	tracy.ZoneEnd()
	queueBuildmenuUnitpicWarmFromCommands()

	--- CHANGE START ---
	tracy.ZoneBeginN("W:BuildMenu:RefreshCommands:CellMap")
	clearTable(unitDefToCellMap)
	clearTable(cellQuotas)
	--- CHANGE END ---

	local numCellsPerPage = rows * colls
	local startCellID = numCellsPerPage * (currentPage - 1)
	for i = 1, numCellsPerPage do
		local cellRectID = startCellID + i
		if cmds[cellRectID] then
			local uDefID = -cmds[cellRectID].id
			unitDefToCellMap[uDefID] = cellRectID
		end
	end
	tracy.ZoneEnd()

	if WG.Quotas then
		tracy.ZoneBeginN("W:BuildMenu:RefreshCommands:Quotas")
		local quotas = WG.Quotas.getQuotas()
		for _, factoryID in ipairs(spGetSelectedUnits()) do
			if quotas[factoryID] then
				for uDefID, quotaValue in pairs(quotas[factoryID]) do
					cellQuotas[uDefID] = {
						builderID = factoryID,
						quota = quotaValue,
					}
				end
			end
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

local function clear()
	refreshBuildmenu = true
	dlistBuildmenu = gl.DeleteList(dlistBuildmenu)
	dlistBuildmenuBg = gl.DeleteList(dlistBuildmenuBg)
	hoverDlist = gl.DeleteList(hoverDlist)
	prevHoveredCellID = nil
	if buildmenuTex then
		gl.DeleteTexture(buildmenuBgTex)
		buildmenuBgTex = nil
		gl.DeleteTexture(buildmenuTex)
		buildmenuTex = nil
		buildmenuTexHasContent = false
	end
end

-- BAR Droid: the layout editor's settings for the menu (moved by dx, dy of the screen; size)
function droid.edits()
	local editor = WG.BarDroidLayout
	return editor and editor.get("buildmenu") or { dx = 0, dy = 0, size = 1 }
end

-- BAR Droid: the unit panel's height (of the screen), BAR's or the app's (bardroid_info.lua, sized in the layout editor)
function droid.infoTall()
	local info = WG.info
	if info and info.getPosition then
		local _, h = info.getPosition()
		return h
	end
end

-- BAR Droid: the menu for the layout editor, once it is there (BAR's own shows in it as fixed)
function droid.register()
	local editor = WG.BarDroidLayout
	if droid.registered or not (editor and editor.register) then
		return
	end
	droid.registered = true
	editor.register("buildmenu", {
		label = "Build menu",
		can = { move = true, size = true },
		rect = function() -- (none while hidden: the controller game with v0.8.5's controls, its own menu in the place)
			if not droid.active() then
				return nil
			end
			return backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4]
		end,
		relayout = function()
			widget:ViewResize()
		end,
	})
end

-- BAR Droid: a building picked (from this menu, a key or before the start), the shape for it, the PLACE button and the
-- spot a tap picked, for the app (RtsTouch: how a finger on the map builds it), in LuaUI/Config/bardroid_place.txt,
-- X screen pixels (top left origin):
--   place <one|line|grid|border|none>
--   done <x0> <y0> <x1> <y1>    (the PLACE button, without its rotate and cancel)
--   spot <x> <y> <r>            (where the spot is on the screen now, and the building's size there; only while it is)
--   rotate, cancel <x0> <y0> <x1> <y1>    (the buttons beside PLACE: a GRID's left button is down, so taps there are the app's)
-- The strip is drawn again when the building is picked or put away.
function droid.place()
	if droid.again then
		droid.pickAgain()
	end
	local active = droid.active()
	if active ~= droid.wasActive then -- (the controller game: shown or hidden with the app's controls)
		droid.wasActive = active
		if not active then
			droid.endFocus()
		end
		clear()
		doUpdate = true
	end
	local defID
	if spGetGameFrame() == 0 and WG["pregame-build"] and WG["pregame-build"].getPreGameDefID then
		defID = WG["pregame-build"].getPreGameDefID()
	else
		local _, id = spGetActiveCommand()
		defID = id and id < 0 and -id or nil
	end
	local armed = defID ~= nil
	if defID ~= droid.defID then
		droid.defID, droid.spot = defID, nil -- (another building: the spot was for the last one)
	end
	if armed ~= droid.armed then
		droid.armed = armed
		if not armed then
			droid.gridHeld = nil
			droid.shape = "one" -- (each building picked starts with ONE: a drag pans the map until a shape is chosen)
		elseif droid.focus then
			droid.endFocus() -- (picked with the gamepad: the app glides the pointer to the middle, ready to place it)
		end
		clear()
	end
	droid.padFocus()
	if not armed and droid.written == "place none\n" then
		droid.panel = nil
		return
	end
	droid.layoutPanel()
	local text = "place " .. (armed and droid.shape or "none") .. "\n"
	local p = droid.panel
	if p then
		for _, b in ipairs({ { "done", p.place }, { "rotate", p.rotate }, { "cancel", p.cancel } }) do
			local r = b[2]
			text = text .. string.format("%s %d %d %d %d\n", b[1], r[1], vsy - r[4], r[3], vsy - r[2])
		end
	end
	local sx, sy, sr = droid.spotOnScreen()
	if sx then
		text = text .. string.format("spot %d %d %d\n", sx, vsy - sy - 1, sr)
	end
	-- (written again every second while a building is picked: the app takes an older file for none, so a file left by
	-- a game that ended with a building picked never turns taps into Shift clicks)
	local now = Spring.GetTimer()
	if text ~= droid.written or (armed and Spring.DiffTimers(now, droid.writtenAt) > 1) then
		-- written whole, then renamed: the app must never read it empty (io.open "w" empties it first), which made a
		-- tap a plain click that placed the building at once
		local f = io.open(droid.file .. ".tmp", "w")
		if f then
			f:write(text)
			f:close()
			local ok, renamed = pcall(os.rename, droid.file .. ".tmp", droid.file)
			if not (ok and renamed) then -- (Windows, for the laptop tests: rename does not replace a file)
				pcall(os.remove, droid.file)
				pcall(os.rename, droid.file .. ".tmp", droid.file)
			end
			droid.written, droid.writtenAt = text, now
		end
	end
end

-- BAR Droid: the spot a tap picked (X screen pixels; nil: none): the building goes there when PLACE is tapped
-- BAR Droid: the building the app has just placed, picked again: the engine keeps a Shift click's building only until Shift
-- comes up (CGuiHandler needShift), and it stays picked for the next spot, until the cancel button or a long press
function droid.pickAgain()
	local again = droid.again
	local _, id = spGetActiveCommand()
	again.frames = again.frames - 1
	if id == nil and spGetGameFrame() > 0 then
		droid.again = nil
		local index = Spring.GetCmdDescIndex(-again.defID)
		if index then
			Spring.SetActiveCommand(index, 1, true, false, false, false, false, false)
		end
	elseif id ~= -again.defID or again.frames <= 0 then
		droid.again = nil -- (another order picked, or Shift never came up)
	end
end

function droid.setSpot(x, y, placed)
	droid.spot, droid.nudgeCarry = nil, { 0, 0 }
	if placed and droid.defID then -- (RtsTouch sent the building off: "spot placed")
		droid.again = { defID = droid.defID, frames = 30 } -- (frames, not seconds: a slow frame must not lose it)
	end
	if x and y and droid.armed then
		local _, pos = Spring.TraceScreenRay(x, vsy - y - 1, true)
		if pos then
			droid.spot = { pos[1], pos[2], pos[3] }
		end
	end
	droid.place()
end

-- (a map point moved by dx, dy X screen pixels, y down: the ground under the pixel it lands on; nil: off the screen
-- or over the sky. The part of a pixel left over is carried to the next move: the app sends a finger's way in small
-- steps)
function droid.screenMove(p, dx, dy, carry)
	local sx, sy, sz = Spring.WorldToScreenCoords(p[1], p[2], p[3])
	if sz > 1 then
		return nil
	end
	local tx, ty = sx + dx + carry[1], sy - dy + carry[2]
	local ix, iy = math_floor(tx + 0.5), math_floor(ty + 0.5)
	local _, pos = Spring.TraceScreenRay(ix, iy, true)
	if not pos then
		return nil
	end
	carry[1], carry[2] = tx - ix, ty - iy
	return { pos[1], pos[2], pos[3] }
end

-- BAR Droid: the waiting building moved by a finger's nudge, X screen pixels
function droid.nudge(dx, dy)
	local s = droid.spot
	local moved = s and droid.armed and dx and dy and droid.screenMove(s, dx, dy, droid.nudgeCarry)
	if not moved then
		return
	end
	droid.spot = moved
	droid.place()
end

-- BAR Droid: the app's GRID, BAR's own build drag with its left button held until PLACE (RtsTouch): "held" or "free"
function droid.setGrid(kind)
	if kind == "held" then
		droid.gridHeld, droid.gridShown = true, Spring.GetTimer()
	elseif kind == "free" then
		droid.gridHeld = nil
	end
	droid.place()
end

-- (a point the app may click on the map: on the screen, not under this menu, PLACE or the minimap)
function droid.clickable(bx, by, bz)
	local sx, sy, sz = Spring.WorldToScreenCoords(bx, by, bz)
	if sz > 1 or sx < 0 or sy < 0 or sx >= vsx or sy >= vsy or widget:IsAbove(sx, sy) or Spring.IsAboveMiniMap(sx, sy) then
		return nil
	end
	local P = WG.BarDroidPortrait -- (not under the portrait dock either: the click would land on it)
	local d = P and P.dock and P.dock()
	if d and sx >= d[1] and sx <= d[3] and sy >= d[2] and sy <= d[4] then
		return nil
	end
	return math_floor(sx), math_floor(sy)
end

-- (the building's place on the build grid at the spot, and where that is on the screen)
function droid.spotPos()
	local s = droid.spot
	if not (s and droid.defID) then
		return nil
	end
	return Spring.Pos2BuildPos(droid.defID, s[1], s[2], s[3], Spring.GetBuildFacing())
end
-- (none when it is off the screen or under this menu, PLACE or the minimap: a click there would hit them, not the map;
-- with it the building's size on the screen, pixels from its middle)
function droid.spotOnScreen()
	local bx, by, bz = droid.spotPos()
	if not bx then
		return nil
	end
	local sx, sy = droid.clickable(bx, by, bz)
	if not sx then
		return nil
	end
	local def = UnitDefs[droid.defID]
	local half = math.max(def.xsize, def.zsize) * 4
	local r = 0
	for _, d in ipairs({ { half, 0 }, { 0, half } }) do
		local ex, ey = Spring.WorldToScreenCoords(bx + d[1], by, bz + d[2])
		r = math.max(r, math.sqrt((ex - sx) ^ 2 + (ey - sy) ^ 2))
	end
	return sx, sy, math_floor(r + 0.5)
end

-- BAR Droid: the building at the spot, as the engine draws a building being placed, and its footprint
function droid.drawSpot()
	local bx, by, bz = droid.spotPos()
	if not bx then
		return
	end
	local def = UnitDefs[droid.defID]
	local facing = Spring.GetBuildFacing()
	gl.DepthTest(true)
	gl.PushMatrix()
	gl.Translate(bx, by, bz)
	gl.Rotate(90 * facing, 0, 1, 0)
	gl.UnitShape(droid.defID, Spring.GetMyTeamID(), false, false, false)
	gl.PopMatrix()
	gl.DepthTest(false)
	-- (its footprint on the ground, green as the engine's own placement square, turned with the building: Kailil,
	-- 2026-11-11, "remove the green circle cursor radial that follows my finger"; the ring around it is gone)
	local fx, fz = (def and def.xsize or 2) * 4, (def and def.zsize or 2) * 4
	if facing % 2 == 1 then
		fx, fz = fz, fx
	end
	gl.Color(0.3, 1, 0.3, 0.45)
	gl.DrawGroundQuad(bx - fx, bz - fz, bx + fx, bz + fz)
	gl.Color(1, 1, 1, 1)
end

-- BAR Droid: "GRID" over the waiting building for a moment once a GRID starts, in v0.8.5's blue (its "SLOW PAN")
function droid.drawGridShown()
	local t = droid.gridShown
	local age = t and Spring.DiffTimers(Spring.GetTimer(), t)
	if not age or age > droid.gridToast then
		droid.gridShown = nil
		return
	end
	local bx, by, bz = droid.spotPos()
	local sx, sy, sz
	if bx then
		sx, sy, sz = Spring.WorldToScreenCoords(bx, by, bz)
	end
	if not sx or sz > 1 then
		sx, sy = vsx / 2, vsy / 2
	end
	local alpha = math.max(0, math.min(1, age / 0.08, (droid.gridToast - age) / 0.3))
	local s = WG.BarDroidStyle
	if s then -- (the app's controller look: a note in BAR's panel, as the pad's)
		s.toast("GRID", sx, sy + s.size(0.035), s.BLUE, alpha)
		return
	end
	local size = math.max(16, math_floor(vsy * 0.045))
	font2:Begin(true)
	font2:SetTextColor(0.2, 0.8, 1, alpha)
	font2:SetOutlineColor(0, 0, 0, 0.8)
	font2:Print("GRID", sx, math.min(vsy - size, sy + size * 1.4), size, "co")
	font2:End()
end

-- BAR Droid: the PLACE button over the order menu (else under the middle of the screen), rotate and cancel inside it
-- at the right, each a square of 0.7 of its height
function droid.layoutPanel()
	droid.panel = nil
	if not droid.armed or WG.BarDroidInput == "pad" or WG.BarDroidInput == "mouse" then -- (fingers' only: A or a
		return -- click places where the pointer is)
	end
	local x0, y0, x1, y1
	local o = WG.ordermenu
	local dock = WG.BarDroidPortrait and WG.BarDroidPortrait.placeRect and WG.BarDroidPortrait.placeRect()
	if dock then -- (the portrait dock, bardroid_portrait.lua: its place for it, under the shapes)
		x0, y0, x1, y1 = dock[1], dock[2], dock[3], dock[4]
	elseif o and o.getPosition and o.getIsShowing and o.getIsShowing() then
		local x, y, w, h = o.getPosition()
		if x and h then
			x0, y0, x1, y1 = x * vsx, (y - h) * vsy, (x + w) * vsx, y * vsy
		end
	end
	if not x0 then
		-- (no order menu: before the game. Under the build menu when there is room; at the bottom's middle it went
		-- behind BAR's "Pick your faction" panel there, rotate and cancel hidden, 2026-11-09)
		local b, h, gap = backgroundRect, vsy * 0.14, vsy * 0.01
		if b[3] > b[1] and b[2] - h - gap >= 0 then
			x0, y0, x1, y1 = b[1], b[2] - h - gap, b[3], b[2] - gap
		else
			x0, y0, x1, y1 = vsx * 0.35, 0, vsx * 0.65, vsy * 0.14
		end
	end
	x0, y0, x1, y1 = math_floor(x0), math_floor(y0), math_floor(x1), math_floor(y1)
	local pad = math_floor(math.max(2, (y1 - y0) * 0.08))
	local s = math_floor(math.min((y1 - y0) * 0.7, (x1 - x0) * 0.2))
	local my = math_floor((y0 + y1 - s) / 2)
	local cs = s
	if dock then -- (upright, the tall panel: at its bottom right corner; Kailil, 2026-11-10; its cancel twice the size,
		-- 2026-11-11: "make the X button on place 100 percent bigger")
		my = y0 + pad
		cs = math_floor(math.min(s * 2, (y1 - y0) - 2 * pad, (x1 - x0) * 0.45))
	end
	local cancel = { x1 - pad - cs, my, x1 - pad, my + cs }
	local rotate = { cancel[1] - pad - s, my, cancel[1] - pad, my + s }
	-- (upright PLACE is the whole panel but its two buttons, which RtsTouch and pressPanel tell first: the column above
	-- them was a dead part of the green panel, dev phone screenshot 2026-11-11)
	local place = dock and { x0, y0, x1, y1 } or { x0, y0, rotate[1] - pad, y1 }
	droid.panel = { all = { x0, y0, x1, y1 }, place = place, rotate = rotate, cancel = cancel }
end

function droid.drawPanel()
	local p = droid.panel
	if not p then
		return
	end
	-- (green once a tap has picked the spot, while it can be clicked, or while a GRID waits)
	local ready = droid.gridHeld or droid.spotOnScreen() ~= nil
	local a = p.all
	UiButton(a[1], a[2], a[3], a[4], 1, 1, 1, 1, 1, 1, 1, 1, nil,
		ready and { 0.1, 0.5, 0.1, 1 } or { 0.1, 0.25, 0.1, 1 }, ready and { 0.25, 0.8, 0.25, 1 } or { 0.2, 0.35, 0.2, 1 },
		bgpadding * 0.5) -- (solid: the order menu's buttons are under it)
	for _, name in ipairs({ "rotate", "cancel" }) do
		local r = p[name]
		UiButton(r[1], r[2], r[3], r[4], 1, 1, 1, 1, 1, 1, 1, 1, nil, { 0, 0, 0, 0.55 }, { 0.15, 0.15, 0.15, 0.6 }, bgpadding * 0.4)
	end
	font2:Begin(true)
	local pl = p.place
	local size = math.min((pl[4] - pl[2]) * 0.45, (pl[3] - pl[1]) * 0.8 / math.max(0.01, font2:GetTextWidth("PLACE")))
	font2:Print((ready and "\255\255\255\255" or "\255\150\190\150") .. "PLACE", (pl[1] + pl[3]) / 2,
		(pl[2] + pl[4]) / 2 - size * 0.3, size, "co")
	local r = p.rotate
	local sym = (r[4] - r[2]) * 0.6
	font2:Print("\255\235\235\235\226\134\187", (r[1] + r[3]) / 2, (r[2] + r[4]) / 2 - sym * 0.3, sym, "co")
	r = p.cancel -- (its cross a soft red: in the green panel it read as one more way to build)
	font2:Print("\255\255\150\140\226\156\149", (r[1] + r[3]) / 2, (r[2] + r[4]) / 2 - sym * 0.3, sym, "co")
	font2:End()
end

-- BAR Droid: a press on the PLACE button: rotate turns the building, cancel puts it away; PLACE itself is the app's
-- (it clicks the spot); a mouse there does nothing
function droid.pressPanel(x, y)
	local p = droid.panel
	local function inside(r)
		return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
	end
	if not (p and inside(p.all)) then
		return false
	end
	if inside(p.rotate) then
		Spring.SendCommands("buildfacing inc")
	elseif inside(p.cancel) then
		droid.spot, droid.again = nil, nil
		-- (before the game: BAR's pregame queue's setPreGamestartDefID; its old name setPreGameDefID, which this called,
		-- is gone, and cancel did nothing there)
		local pb = spGetGameFrame() == 0 and WG["pregame-build"]
		local putAway = pb and (pb.setPreGamestartDefID or pb.setPreGameDefID)
		if putAway then
			putAway(nil)
		else
			Spring.SetActiveCommand(0)
		end
	end
	droid.place()
	return true
end

-- BAR Droid: the shape strip, in the page strip's place (area: the menu's inner rect; h: the strip's height)
function droid.drawShapes(area, width, h)
	local w = width / #droid.items
	local y0, y1 = area[2], area[2] + h - cellPadding - activeAreaMargin
	-- (one size for all: the page strip's, which they replace; at half the strip's height they read a size smaller)
	local size = math.min(math.max(0.016 * vsy, h * 0.2) * droid.pageText, (y1 - y0) * 0.62,
		w * 0.8 / math.max(0.01, font2:GetTextWidth("BORDER")))
	for i, item in ipairs(droid.items) do
		local x0 = area[1] + (i - 1) * w
		local rect = { x0, y0, x0 + w, y1, item[1] }
		droid.shapeRects[#droid.shapeRects + 1] = rect
		-- (the picked one gold with white words: its pale gold words on the gold read worst of the four, dev phone
		-- 2026-11-03)
		local lit = item[1] == droid.shape
		UiButton(rect[1] + cellPadding, rect[2] + cellPadding, rect[3] - cellPadding, rect[4] - cellPadding,
			1, 1, 1, 1, 1, 1, 1, 1, nil,
			lit and { 0.38, 0.3, 0.04, 0.9 } or { 0, 0, 0, 0.8 }, lit and { 0.66, 0.53, 0.12, 0.9 } or { 0.2, 0.2, 0.2, 0.8 },
			bgpadding * 0.5)
		font2:Print((lit and "\255\255\255\255" or "\255\235\235\235") .. item[2], x0 + w * 0.5,
			(y0 + y1) * 0.5 - size * 0.3, size, "co")
	end
end

-- BAR Droid: a tap on the shape strip picks the shape
function droid.press(x, y)
	for _, r in ipairs(droid.shapeRects) do
		if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
			droid.shape = r[5]
			clear()
			droid.place()
			return true
		end
	end
	return false
end

-- BAR Droid: the gamepad's buttons for the menu (bardroid_touch.lua's pad_* actions): build (RB: on, or off again),
-- back (B), left, right, up, down (the D-pad)
function droid.cellAt(x, y)
	for id, r in pairs(cellRects) do
		if cmds[id] and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
			return id
		end
	end
end

-- (the app glides the pointer back to the middle once no menu has the pad: Kailil, "make sure that snap back is smooth";
-- in the controller game the menu goes with the pad)
function droid.endFocus()
	droid.focus, droid.warpTo, droid.warped, droid.outSince = nil, nil, nil, nil
	droid.opened, droid.openedAt = false, nil
end

-- BAR Droid: the menu is shown and takes input (the controller game: only while the app's controls have the pad; then,
-- once the pad is in use (WG.BarDroidPadOnly: until a few taps), only after RB has opened it, as v0.8.5's own; Kailil,
-- 2026-10-29: hidden until RB, "to save screen space"; 2026-10-30, by touch: "open in its usual location. not hide by
-- default like gamepad behavior"; the PLACE button and a building's spot work either way, for fingers)
function droid.active()
	if WG.BarDroidPortrait and WG.BarDroidPortrait.active() then -- (the portrait dock has its own grid; PLACE stays this one's)
		return false
	end
	return not droid.ctl or (WG.BarDroidOwnsBuildMenu == true and (droid.opened == true or not WG.BarDroidPadOnly))
end

function droid.pad(name)
	if name == "build" then
		if droid.focus or droid.openedAt then
			droid.endFocus()
		elseif buildmenuShows and cmdsCount > 0 then
			droid.focus = math.min(cmdsCount, (currentPage - 1) * colls * rows + 1)
			droid.warpTo = droid.focus
			droid.opened = true -- (a menu fingers left open: it stays, now the pad is in use)
		elseif droid.ctl and WG.BarDroidOwnsBuildMenu == true then -- (opened: the pad on it once it is laid out)
			droid.opened, droid.openedAt, droid.openedWait = true, Spring.GetTimer(), 0
			doUpdate = true
		end
	elseif not droid.focus then
		return
	elseif name == "back" then
		droid.endFocus()
	elseif name == "pagenext" or name == "pageprev" then -- RB / LB on the menu (Kailil: "pressing RB or LB cycles the
		local per = colls * rows -- tabs"): the same place on the page after or before
		local page = math_ceil(droid.focus / per)
		local i = droid.focus - (page - 1) * per
		page = name == "pagenext" and page % pages + 1 or (page + pages - 2) % pages + 1
		local target = math.min(cmdsCount, (page - 1) * per + i)
		if page ~= currentPage then
			currentPage = page
			doUpdate = true
		end
		droid.focus, droid.warpTo = target, target
	else
		-- (from the focused option, not the one under the pointer: two quick presses come before the pointer has
		-- moved; the focus follows the pointer once it is the player's again, droid.padFocus)
		local per = colls * rows
		local id = droid.focus
		local page = math_ceil(id / per)
		local i = id - (page - 1) * per - 1
		local row, col = math_floor(i / colls), i % colls
		if name == "left" then
			col = col - 1
		elseif name == "right" then
			col = col + 1
		elseif name == "up" then
			row = math.max(0, row - 1)
		elseif name == "down" then
			row = math.min(rows - 1, row + 1)
		end
		if col < 0 then
			page, col = page - 1, colls - 1
		elseif col >= colls or (name == "right" and (page - 1) * per + row * colls + col + 1 > cmdsCount) then
			page, col = page + 1, 0 -- (right past the last option too: it stayed on it, stuck)
		end
		page = page < 1 and pages or (page > pages and 1 or page)
		local target = math.min(cmdsCount, (page - 1) * per + row * colls + col + 1)
		if page ~= currentPage then
			currentPage = page
			doUpdate = true
		end
		droid.focus, droid.warpTo = target, target
	end
	droid.padFocus()
end

-- (each Update: the pointer onto the focused option once the menu has laid it out; once the pointer has got there
-- (or half a second on) it is the player's again: the focus follows it over the options and ends off the menu, as
-- when the menu goes)
function droid.padFocus()
	if droid.openedAt then -- (the controller game: RB opened the menu; nothing to build after half a second: closed)
		if buildmenuShows and cmdsCount > 0 then
			droid.openedAt = nil
			droid.focus = math.min(cmdsCount, (currentPage - 1) * colls * rows + 1)
			droid.warpTo = droid.focus
		else
			droid.openedWait = droid.openedWait + 1 -- (and a few frames: a stall outlasts half a second before it is laid out)
			if droid.openedWait > 8 and Spring.DiffTimers(Spring.GetTimer(), droid.openedAt) > 0.5 then
				droid.endFocus()
			end
		end
	end
	if droid.focus then
		local now = Spring.GetTimer()
		if not buildmenuShows then
			droid.endFocus()
		elseif droid.warpTo then
			local r = cellRects[droid.warpTo]
			if r then
				local x, y = math_floor((r[1] + r[3]) / 2), math_floor((r[2] + r[4]) / 2)
				droid.warp(x, y)
				droid.warpTo, droid.warped = nil, { x, y, now }
			end
		elseif not droid.fakeWarp then
			local mx, my = spGetMouseState()
			local w = droid.warped
			if w and ((math.abs(mx - w[1]) <= 2 and math.abs(my - w[2]) <= 2) or Spring.DiffTimers(now, w[3]) > 0.5) then
				droid.warped, w = nil, nil
			end
			if not w then
				-- (kept on the menu: pushed off it for droid.leave seconds the pointer is let go - Kailil: "let the mouse
				-- leave it if i press B only or i constantly move the left stick out of the box", then "make it a quarter
				-- long instead": 0.25 s)
				local id = droid.cellAt(mx, my)
				if id then
					droid.focus = id
				end
				local r = backgroundRect
				local x0, y0, x1, y1 = r[1] + 2, r[2] + 2, r[3] - 2, r[4] - 2
				if mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
					droid.outSince = nil
				elseif droid.outSince and Spring.DiffTimers(now, droid.outSince) >= droid.leave then
					droid.endFocus()
				else
					droid.outSince = droid.outSince or now
					droid.warp(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				end
			end
		end
	end
end

-- BAR Droid: the option under the pointer, with the gamepad: 10% bigger, a gold line round it (the app's controller
-- look, WG.BarDroidStyle: as the order on the pad in the order menu)
function droid.drawHover(cellID, list)
	local r = cellRects[cellID]
	if not (r and (droid.focus or WG.BarDroidInput == "pad")) then
		gl.CallList(list)
		return
	end
	local cx, cy = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
	gl.PushMatrix()
	gl.Translate(cx, cy, 0)
	gl.Scale(1.1, 1.1, 1)
	gl.Translate(-cx, -cy, 0)
	gl.CallList(list)
	droid.goldLine(r)
	gl.PopMatrix()
end

-- BAR Droid: a gold line round a cell (rect r; width: of the cell's, else the style's)
function droid.goldLine(r, width)
	local s = WG.BarDroidStyle
	local x0, y0, x1, y1 = r[1] + cellPadding, r[2] + cellPadding, r[3] - cellPadding, r[4] - cellPadding
	local w = width and math.max(2, math_floor((r[3] - r[1]) * width)) or nil
	if s then
		s.outline(x0, y0, x1, y1, s.GOLD, 1, w)
	else
		local t = w or math.max(2, math_floor((r[3] - r[1]) * 0.03))
		gl.Color(1, 0.78, 0.25, 1)
		gl.Rect(x0, y0, x1, y0 + t)
		gl.Rect(x0, y1 - t, x1, y1)
		gl.Rect(x0, y0, x0 + t, y1)
		gl.Rect(x1 - t, y0, x1, y1)
		gl.Color(1, 1, 1, 1)
	end
end

-- BAR Droid: while a building is picked, its option with the gold line (BAR's lighter cell alone read faintly on the
-- phone, 2026-11-04; gold is the app's "on": QUEUE, the picked shape below it). Not while the pad is on the menu
-- (its own gold line is the focus).
function droid.drawPicked()
	if not (droid.armed and droid.defID) or droid.focus then
		return
	end
	for id, r in pairs(cellRects) do
		if cmds[id] and cmds[id].id == -droid.defID then
			droid.goldLine(r, 0.04) -- (the pad focus's 2 px read as a hairline on the dev phone)
			return
		end
	end
end

function widget:ViewResize()
	tracy.ZoneBeginN("W:BuildMenu:ViewResize")
	vsx, vsy = spGetViewGeometry()

	local outlineMult = math.clamp(1 / (vsy / 1400), 1, 1.5)
	font2 = WG.fonts.getFont(2)

	if WG.minimap then
		minimapHeight = WG.minimap.getHeight()
	end

	local widgetSpaceMargin = WG.FlowUI.elementMargin
	bgpadding = WG.FlowUI.elementPadding
	elementCorner = WG.FlowUI.elementCorner

	RectRound = WG.FlowUI.Draw.RectRound
	RectRoundProgress = WG.FlowUI.Draw.RectRoundProgress
	UiUnit = WG.FlowUI.Draw.Unit
	UiButton = WG.FlowUI.Draw.Button
	UiElement = WG.FlowUI.Draw.Element

	activeAreaMargin = math_ceil(bgpadding * cfgActiveAreaMargin)

	if stickToBottom then
		posY = math_floor(0.14 * ui_scale * vsy) / vsy
		posY2 = 0
		posX = ordermenuLeft + widgetSpaceMargin
		posX2 = advplayerlistLeft - widgetSpaceMargin
		width = (posX2 - posX) / vsx
		height = posY
		minColls = math_max(8, math_floor((width / vsx) * 25))
		maxColls = 30
	else
		posY = math.clamp(((vsy - minimapHeight) / vsy) - (widgetSpaceMargin / vsy), 0.4615, maxPosY)
		posY2 = math_floor(0.14 * ui_scale * vsy) / vsy
		posY2 = posY2 + (widgetSpaceMargin / vsy)
		posX = 0
		minColls = 4
		maxColls = 5

		if WG.minimap then
			posY = 1 - (WG.minimap.getHeight() / vsy) - (widgetSpaceMargin / vsy)
			if posY > maxPosY then
				posY = maxPosY
			end

			if WG.ordermenu then
				local oposX, oposY, owidth, oheight = WG.ordermenu.getPosition()
				if oposY > 0.5 then
					posY = oposY - oheight - (widgetSpaceMargin / vsy)
				end
			end
		end

		posY = math_floor(posY * vsy) / vsy
		posX = math_floor(posX * vsx) / vsx

		height = (posY - posY2)
		width = 0.212

		width = width / (vsx / vsy) * 1.78 -- make smaller for ultrawide screens
		width = width * ui_scale

		posX2 = math_floor(width * vsx)

		-- make pixel aligned
		width = math_floor(width * vsx) / vsx
		height = math_floor(height * vsy) / vsy

		-- BAR Droid: as tall as droid.rows cells as wide as the menu allows, and the page strip under them (Kailil:
		-- "increase the total height of the build menu to allow the pictures to fill their squares"); its bottom
		-- above the unit panel, also the app's made taller in the layout editor (droid.infoHeight)
		droid.infoHeight = droid.infoTall()
		if droid.infoHeight and droid.infoHeight + widgetSpaceMargin / vsy > posY2 then
			posY2 = math.min(droid.infoHeight + widgetSpaceMargin / vsy, posY - 0.1)
			height = math_floor((posY - posY2) * vsy) / vsy
		end
		local cellPx = (width * vsx - (bgpadding + activeAreaMargin) * 2) / droid.colls
		local want = math_floor((droid.rows + droid.strip) * cellPx + (bgpadding + activeAreaMargin) * 2) / vsy
		if want < height then
			height = want
			posY = posY2 + height
		end
	end

	-- BAR Droid: the layout editor's size (width and height from the menu's bottom left corner) and place
	local edit = droid.edits()
	if edit.size ~= 1 or edit.dx ~= 0 or edit.dy ~= 0 then
		local bottom = posY - height
		width, height = width * edit.size, height * edit.size
		local w = math_floor(width * vsx)
		posX = math.clamp(posX + math_floor(edit.dx * vsx), 0, math.max(0, vsx - w))
		posX2 = posX + w
		bottom = math.clamp(bottom + edit.dy, 0, math.max(0, 1 - height))
		posY, posY2 = bottom + height, bottom
	end
	backgroundRect = { posX, (posY - height) * vsy, posX2, posY * vsy }

	checkGuishader(true)
	clear()
	doUpdate = true
	if cmdsCount > 0 then
		UpdateGridGeometry()
	end
	tracy.ZoneEnd()
end

function widget:LanguageChanged()
	refreshUnitDefs()
	clear()
	doUpdate = true
end

-- update queue number
function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)
	if spIsUnitSelected(factID) then
		raceConditionUpdateCountdown = 2
	end
end

local sec = 0
function widget:Update(dt)
	droid.register() -- BAR Droid
	droid.place()
	if not stickToBottom and droid.infoTall() ~= droid.infoHeight then -- BAR Droid: the unit panel's height changed
		widget:ViewResize()
	end
	tracy.ZoneBeginN("W:BuildMenu:Update")
	if delayRefresh and spGetGameSeconds() >= delayRefresh then
		clear()
		doUpdate = true
		delayRefresh = nil
	end
	--[[ MODIFICATION START ]]
	-- Check failsafe retry flag
	if forceRefreshNextFrame and refreshRetryCounter > 0 then
		doUpdate = true
		refreshRetryCounter = refreshRetryCounter - 1
		if refreshRetryCounter == 0 then
			forceRefreshNextFrame = false
		end
	end

	-- Debounced selection update logic (time-based)
	if selectionUpdateTime > 0 then
		tracy.ZoneBeginN("W:BuildMenu:Update:Selection")
		local now = os_clock()
		if now >= selectionUpdateTime then
			selectionUpdateTime = 0
			-- The old `updateSelection = false` is no longer needed
			-- The rest of the original logic from `if updateSelection` block is moved here
			selectedBuilders = {}
			selectedBuilderCount = 0
			local prevSelectedFactoryCount = selectedFactoryCount
			selectedFactoryCount = 0

			-- Swap to the other temp table (ping-pong buffering)
			local prevSelBuilderDefs = currentSelBuilderDefs
			currentSelBuilderDefs = (currentSelBuilderDefs == selBuilderDefsTemp1) and selBuilderDefsTemp2
				or selBuilderDefsTemp1
			clearTable(currentSelBuilderDefs)

			SelectedUnitsCount = spGetSelectedUnitsCount()
			if SelectedUnitsCount > 0 then
				local sel = Spring.GetSelectedUnits()
				for _, unitID in ipairs(sel) do
					local uDefID = spGetUnitDefID(unitID)
					if units.isFactory[uDefID] then
						selectedFactoryCount = selectedFactoryCount + 1
						currentSelBuilderDefs[uDefID] = true
					end
					if units.isBuilder[uDefID] then
						selectedBuilders[unitID] = true
						selectedBuilderCount = selectedBuilderCount + 1
						currentSelBuilderDefs[uDefID] = true
					end
				end

				if selectedFactoryCount ~= prevSelectedFactoryCount then
					doUpdate = true
				end

				-- check if builder type selection actually differs from previous selection
				if not doUpdate then
					if #currentSelBuilderDefs ~= #prevSelBuilderDefs then
						doUpdate = true
					else
						for uDefID, _ in pairs(prevSelBuilderDefs) do
							if not currentSelBuilderDefs[uDefID] then
								doUpdate = true
								break
							end
						end
						if not doUpdate then
							for uDefID, _ in pairs(currentSelBuilderDefs) do
								if not prevSelBuilderDefs[uDefID] then
									doUpdate = true
									break
								end
							end
						end
					end
				end
			end
		end
		tracy.ZoneEnd()
	end
	--[[ MODIFICATION END ]]

	local prevBuildmenuShows = buildmenuShows
	if not droid.active() or (not preGamestartPlayer and selectedBuilderCount == 0 and not alwaysShow) then -- BAR Droid
		buildmenuShows = false
	else
		buildmenuShows = true
	end

	if WG.guishader and prevBuildmenuShows ~= buildmenuShows and dlistGuishader then
		if buildmenuShows then
			WG.guishader.InsertDlist(dlistGuishader, "buildmenu")
		else
			WG.guishader.RemoveDlist("buildmenu")
		end
	end

	sec = sec + dt
	if sec > 0.33 then
		tracy.ZoneBeginN("W:BuildMenu:Update:Periodic")
		sec = 0
		checkGuishader()
		if WG.minimap and minimapHeight ~= WG.minimap.getHeight() then
			widget:ViewResize()
		end

		if stickToBottom then
			if WG.advplayerlist_api ~= nil then
				local advplayerlistPos = WG.advplayerlist_api.GetPosition() -- returns {top,left,bottom,right,widgetScale}
				advplayerlistLeft = advplayerlistPos[2]
			end
		end
		local prevOrdermenuLeft = ordermenuLeft
		local prevOrdermenuHeight = ordermenuHeight
		if WG.ordermenu then
			local oposX, oposY, owidth, oheight = WG.ordermenu.getPosition()
			ordermenuLeft = math_floor((oposX + owidth) * vsx)
			ordermenuHeight = oheight
		end
		if
			not prevAdvplayerlistLeft
			or advplayerlistLeft ~= prevAdvplayerlistLeft
			or not prevOrdermenuLeft
			or ordermenuLeft ~= prevOrdermenuLeft
			or not prevOrdermenuHeight
			or ordermenuHeight ~= prevOrdermenuHeight
		then
			prevAdvplayerlistLeft = advplayerlistLeft
			widget:ViewResize()
		end

		disableInput = Spring.IsGodModeEnabled() and false or (disableInputWhenSpec and isSpec)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function drawBuildmenuBg()
	UiElement(
		backgroundRect[1],
		backgroundRect[2],
		backgroundRect[3],
		backgroundRect[4],
		(posX > 0 and 1 or 0),
		1,
		((posY - height > 0 or posX <= 0) and 1 or 0),
		0,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil
	)
end

-- The player queue vs the widget-provided queue have different accounting due to quota mode.
-- cellQuotas contains the live count from the widget, which we should remove from the total.
local function getPlayerQueueCount(cellRectID, uDefID)
	local queueCount = tonumber(cmds[cellRectID].params[1])
	if not queueCount then
		return nil
	end
	local quotaInfo = cellQuotas[uDefID]
	if quotaInfo and WG.Quotas then
		queueCount = queueCount - WG.Quotas.getQuotaOrderCount(quotaInfo.builderID, uDefID)
	end
	if queueCount < 1 then
		return nil
	end
	return queueCount
end

local function drawCell(cellRectID, usedZoom, cellColor, disabled, underConstruction)
	tracy.ZoneBeginN("W:BuildMenu:DrawCell")
	local uDefID = -cmds[cellRectID].id
	local queueCount = getPlayerQueueCount(cellRectID, uDefID)
	local unitTexture = "#" .. uDefID
	local cellRect = cellRects[cellRectID]
	if not cellRect then
		tracy.ZoneEnd()
		return false
	end
	local iconX1 = cellRect[1] + cellPadding + iconPadding
	local iconY1 = cellRect[2] + cellPadding + iconPadding
	local iconX2 = cellRect[3] - cellPadding - iconPadding
	local iconY2 = cellRect[4] - cellPadding - iconPadding
	if not isValidRect(iconX1, iconY1, iconX2, iconY2) then
		tracy.ZoneEnd()
		return false
	end
	if not buildmenuUnitpicWarm.warmed[uDefID] then
		tracy.ZoneBeginN("W:BuildMenu:DrawCell:TextureWarmFallback")
		if glTexture(unitTexture) then
			buildmenuUnitpicWarm.warmed[uDefID] = true
		end
		glTexture(false)
		tracy.ZoneEnd()
	end

	-- unit icon
	local texprefix = ""
	if disabled then
		glColor(0.4, 0.4, 0.4, 1)
		texprefix = "t0.3,0.3,0.3"
	elseif underConstruction then
		glColor(0.77, 0.77, 0.77, 1)
		texprefix = "t0.63,0.63,0.63"
	else
		glColor(1, 1, 1, 1)
	end
	tracy.ZoneBeginN("W:BuildMenu:DrawCell:UiUnit")
	UiUnit(
		iconX1,
		iconY1,
		iconX2,
		iconY2,
		cornerSize,
		1,
		1,
		1,
		1,
		usedZoom,
		nil,
		disabled and 0 or nil,
		unitTexture,
		showRadarIcon
				and ((units.unitIconType[uDefID] and iconTypes[units.unitIconType[uDefID]]) and ":l" .. texprefix .. ":" .. iconTypes[units.unitIconType[uDefID]] or nil)
			or nil,
		showGroupIcon
				and (groups[units.unitGroup[uDefID]] and ":l" .. texprefix .. ":" .. groups[units.unitGroup[uDefID]] or nil)
			or nil,
		{ units.unitMetalCost[uDefID], units.unitEnergyCost[uDefID] },
		queueCount
	)
	tracy.ZoneEnd()

	-- colorize/highlight unit icon
	if cellColor then
		glBlending(GL_DST_ALPHA, GL_ONE_MINUS_SRC_COLOR)
		glColor(cellColor[1], cellColor[2], cellColor[3], cellColor[4])
		glTexture(unitTexture)
		UiUnit(
			cellRects[cellRectID][1] + cellPadding + iconPadding,
			cellRects[cellRectID][2] + cellPadding + iconPadding,
			cellRects[cellRectID][3] - cellPadding - iconPadding,
			cellRects[cellRectID][4] - cellPadding - iconPadding,
			cornerSize,
			1,
			1,
			1,
			1,
			usedZoom
		)
		if cellColor[4] > 0 then
			glBlending(GL_SRC_ALPHA, GL_ONE)
			UiUnit(
				cellRects[cellRectID][1] + cellPadding + iconPadding,
				cellRects[cellRectID][2] + cellPadding + iconPadding,
				cellRects[cellRectID][3] - cellPadding - iconPadding,
				cellRects[cellRectID][4] - cellPadding - iconPadding,
				cornerSize,
				1,
				1,
				1,
				1,
				usedZoom
			)
		end
		glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	end
	glTexture(false)

	-- price
	if showPrice then
		local function AddSpaces(price)
			if price >= 1000 then
				return string_format("%s %03d", AddSpaces(math_floor(price / 1000)), price % 1000)
			end
			return price
		end

		local costOverride = costOverrides and costOverrides[uDefID]

		if costOverride then
			local topValue = costOverride.top and costOverride.top.value or units.unitMetalCost[uDefID]
			local bottomValue = costOverride.bottom and costOverride.bottom.value or units.unitEnergyCost[uDefID]

			if costOverride.top and not costOverride.top.disabled then
				local costColor = costOverride.top.color or "\255\100\255\100"
				if disabled then
					costColor = costOverride.top.colorDisabled or "\255\100\200\100"
				end
				local costPrice = AddSpaces(mathFloor(topValue))
				local costPriceText = costColor .. costPrice
				font2:Print(
					costPriceText,
					cellRects[cellRectID][3] - cellPadding - (cellInnerSize * 0.048),
					cellRects[cellRectID][2] + cellPadding + (priceFontSize * 1.35),
					priceFontSize,
					"ro"
				)
			elseif not costOverride.top then
				local metalColor = disabled and "\255\125\125\125" or "\255\245\245\245"
				local metalPrice = AddSpaces(units.unitMetalCost[uDefID])
				font2:Print(
					metalColor .. metalPrice,
					cellRects[cellRectID][3] - cellPadding - (cellInnerSize * 0.048),
					cellRects[cellRectID][2] + cellPadding + (priceFontSize * 1.35),
					priceFontSize,
					"ro"
				)
			end

			if costOverride.bottom and not costOverride.bottom.disabled then
				local costColor = costOverride.bottom.color or "\255\255\255\000"
				if disabled then
					costColor = costOverride.bottom.colorDisabled or "\255\135\135\135"
				end
				local costPrice = AddSpaces(mathFloor(bottomValue))
				local costPriceText = costColor .. costPrice
				font2:Print(
					costPriceText,
					cellRects[cellRectID][3] - cellPadding - (cellInnerSize * 0.048),
					cellRects[cellRectID][2] + cellPadding + (priceFontSize * 0.35),
					priceFontSize,
					"ro"
				)
			elseif not costOverride.bottom then
				local energyColor = disabled and "\255\135\135\135" or "\255\255\255\000"
				local energyPrice = AddSpaces(units.unitEnergyCost[uDefID])
				font2:Print(
					energyColor .. energyPrice,
					cellRects[cellRectID][3] - cellPadding - (cellInnerSize * 0.048),
					cellRects[cellRectID][2] + cellPadding + (priceFontSize * 0.35),
					priceFontSize,
					"ro"
				)
			end
		else
			local metalColor = disabled and "\255\125\125\125" or "\255\245\245\245"
			local energyColor = disabled and "\255\135\135\135" or "\255\255\255\000"
			local metalPrice = AddSpaces(units.unitMetalCost[uDefID])
			local energyPrice = AddSpaces(units.unitEnergyCost[uDefID])
			local metalPriceText = metalColor .. metalPrice
			local energyPriceText = energyColor .. energyPrice
			font2:Print(
				metalPriceText,
				cellRects[cellRectID][3] - cellPadding - (cellInnerSize * 0.048),
				cellRects[cellRectID][2] + cellPadding + (priceFontSize * 1.35),
				priceFontSize,
				"ro"
			)
			font2:Print(
				energyPriceText,
				cellRects[cellRectID][3] - cellPadding - (cellInnerSize * 0.048),
				cellRects[cellRectID][2] + cellPadding + (priceFontSize * 0.35),
				priceFontSize,
				"ro"
			)
		end
	end

	-- factory queue number
	if queueCount then
		local pad = math_floor(cellInnerSize * 0.03)
		local textWidth = math_floor(font2:GetTextWidth(queueCount .. "  ") * cellInnerSize * 0.285)
		local pad2 = 0
		RectRound(
			cellRects[cellRectID][3] - cellPadding - iconPadding - textWidth - pad2,
			cellRects[cellRectID][4] - cellPadding - iconPadding - math_floor(cellInnerSize * 0.365) - pad2,
			cellRects[cellRectID][3] - cellPadding - iconPadding,
			cellRects[cellRectID][4] - cellPadding - iconPadding,
			cornerSize * 3.3,
			0,
			0,
			0,
			1,
			{ 0.15, 0.15, 0.15, 0.95 },
			{ 0.25, 0.25, 0.25, 0.95 }
		)
		RectRound(
			cellRects[cellRectID][3] - cellPadding - iconPadding - textWidth - pad2,
			cellRects[cellRectID][4] - cellPadding - iconPadding - math_floor(cellInnerSize * 0.15) - pad2,
			cellRects[cellRectID][3] - cellPadding - iconPadding,
			cellRects[cellRectID][4] - cellPadding - iconPadding,
			0,
			0,
			0,
			0,
			0,
			{ 1, 1, 1, 0 },
			{ 1, 1, 1, 0.05 }
		)
		RectRound(
			cellRects[cellRectID][3] - cellPadding - iconPadding - textWidth - pad2 + pad,
			cellRects[cellRectID][4] - cellPadding - iconPadding - math_floor(cellInnerSize * 0.365) - pad2 + pad,
			cellRects[cellRectID][3] - cellPadding - iconPadding - pad2,
			cellRects[cellRectID][4] - cellPadding - iconPadding - pad2,
			cornerSize * 2.6,
			0,
			0,
			0,
			1,
			{ 0.7, 0.7, 0.7, 0.1 },
			{ 1, 1, 1, 0.1 }
		)
		font2:Print(
			"\255\190\255\190" .. queueCount,
			cellRects[cellRectID][1] + cellPadding + math_floor(cellInnerSize * 0.96) - pad2,
			cellRects[cellRectID][2] + cellPadding + math_floor(cellInnerSize * 0.735) - pad2,
			cellInnerSize * 0.29,
			"ro"
		)
	end

	local quotaInfo = cellQuotas[uDefID]
	if quotaInfo and quotaInfo.quota ~= 0 then
		local quotaText = WG.Quotas.getUnitAmount(quotaInfo.builderID, uDefID) .. "/" .. quotaInfo.quota
		local quotaFontSize = cellInnerSize * 0.29
		local textWidth = font2:GetTextWidth(quotaText .. "  ") * quotaFontSize
		local pad = math_floor(cellInnerSize * 0.03)
		if textWidth > 0.75 * cellInnerSize then
			local newFontSize = quotaFontSize * 0.75 * cellInnerSize / textWidth
			textWidth = font2:GetTextWidth(quotaText .. "  ") * newFontSize
			quotaFontSize = newFontSize
		end
		local pad2 = 0
		RectRound(
			cellRects[cellRectID][3] - cellPadding - iconPadding - textWidth - pad2,
			cellRects[cellRectID][2] + cellPadding + iconPadding,
			cellRects[cellRectID][3] - cellPadding - iconPadding,
			cellRects[cellRectID][2] + cellPadding + iconPadding + math_floor(cellInnerSize * 0.365) + pad2,
			cornerSize * 3.3,
			1,
			0,
			0,
			0,
			{ 0.15, 0.15, 0.15, 0.95 },
			{ 0.25, 0.25, 0.25, 0.95 }
		)
		RectRound(
			cellRects[cellRectID][3] - cellPadding - iconPadding - textWidth - pad2,
			cellRects[cellRectID][2] + cellPadding + iconPadding,
			cellRects[cellRectID][3] - cellPadding - iconPadding,
			cellRects[cellRectID][2] + cellPadding + iconPadding + math_floor(cellInnerSize * 0.15) + pad2,
			0,
			0,
			0,
			0,
			0,
			{ 1, 1, 1, 0 },
			{ 1, 1, 1, 0.05 }
		)
		RectRound(
			cellRects[cellRectID][3] - cellPadding - iconPadding - textWidth - pad2 + pad,
			cellRects[cellRectID][2] + cellPadding + iconPadding,
			cellRects[cellRectID][3] - cellPadding - iconPadding - pad2,
			cellRects[cellRectID][2] + cellPadding + iconPadding + math_floor(cellInnerSize * 0.365) + pad2 - pad,
			cornerSize * 2.6,
			1,
			0,
			0,
			0,
			{ 0.7, 0.7, 0.7, 0.1 },
			{ 1, 1, 1, 0.1 }
		)
		font2:Print(
			"\255\255\130\190" .. quotaText,
			cellRects[cellRectID][1] + cellPadding + math_floor(cellInnerSize * 0.96) - pad2,
			cellRects[cellRectID][2]
				+ cellPadding
				+ (math_floor(cellInnerSize * 0.365) - font2:GetTextHeight(quotaInfo.quota) * quotaFontSize) / 2,
			quotaFontSize,
			"ro"
		)
	end
	tracy.ZoneEnd()
	return true
end

local function drawHighlights()
	if highlightCount == 0 or not next(highlights) then
		return
	end
	local now = os_clock()
	for uDefID, hl in pairs(highlights) do
		local cellRectID = unitDefToCellMap[uDefID]
		local rect = cellRectID and cellRects[cellRectID]
		if rect then
			local color = hl.color or defaultHighlightColor
			local r, g, b = color[1], color[2], color[3]
			local t = now - (hl.startTime or now)
			-- Pulse, period ~1.4s
			local pulse = 0.5 + 0.5 * math.sin(t * 4.5)

			local x1 = rect[1] + cellPadding + iconPadding
			local y1 = rect[2] + cellPadding + iconPadding
			local x2 = rect[3] - cellPadding - iconPadding
			local y2 = rect[4] - cellPadding - iconPadding

			-- Brighten unit icon (additive overlay using its own texture)
			local brighten = 0.10 + 0.22 * pulse
			glBlending(GL_SRC_ALPHA, GL_ONE)
			glColor(r * brighten, g * brighten, b * brighten, 1)
			glTexture("#" .. uDefID)
			UiUnit(x1, y1, x2, y2, cornerSize, 1, 1, 1, 1, defaultCellZoom)
			glTexture(false)

			-- Feathered inner outline ring with pulsing alpha (proper chamfered corners)
			local thickness = math_max(2, math_floor((x2 - x1) * 0.04))
			local outlineAlpha = 0.45 + 0.5 * pulse
			local cs = cornerSize
			local outerCol = { r, g, b, outlineAlpha }
			local innerCol = { r, g, b, outlineAlpha * 0.85 }
			WG.FlowUI.Draw.RectRoundOutline(x1, y1, x2, y2, cs, thickness, 1, 1, 1, 1, outerCol, innerCol)

			-- Soft inner glow fading inward from the outline
			local glowAlpha = 0.10 + 0.20 * pulse
			local glowWidth = thickness * 3
			WG.FlowUI.Draw.RectRoundOutline(
				x1 + thickness,
				y1 + thickness,
				x2 - thickness,
				y2 - thickness,
				math_max(0, cs - thickness),
				glowWidth,
				1,
				1,
				1,
				1,
				{ r, g, b, glowAlpha },
				{ r, g, b, 0 }
			)

			glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
		end
	end
end

function drawBuildmenu()
	tracy.ZoneBeginN("W:BuildMenu:DrawBuildmenu")
	buildmenuRenderedCells = 0
	local activeArea = {
		backgroundRect[1] + (stickToBottom and bgpadding or 0) + activeAreaMargin,
		backgroundRect[2] + (stickToBottom and 0 or bgpadding) + activeAreaMargin,
		backgroundRect[3] - bgpadding - activeAreaMargin,
		backgroundRect[4] - bgpadding - activeAreaMargin,
	}
	local contentHeight = activeArea[4] - activeArea[2]
	local contentWidth = activeArea[3] - activeArea[1]
	local paginatorCellHeight = math_floor(contentHeight - (rows * cellSize))

	--- CHANGE START ---
	clearTable(cellRects)
	--- CHANGE END ---

	local numCellsPerPage = rows * colls
	local cellRectID = numCellsPerPage * (currentPage - 1)
	local maxCellRectID = numCellsPerPage * currentPage
	if maxCellRectID > cmdsCount then
		maxCellRectID = cmdsCount
	end
	-- build set of unit defs that can be built by at least one finished factory
	tracy.ZoneBeginN("W:BuildMenu:DrawBuildmenu:Buildable")
	local finishedBuildable = {}
	if selectedFactoryCount > 0 then
		for _, unitID in ipairs(spGetSelectedUnits()) do
			local defID = spGetUnitDefID(unitID)
			if units.isFactory and units.isFactory[defID] and not spGetUnitIsBeingBuilt(unitID) then
				local opts = unitBuildOptions[defID]
				if opts then
					for _, optDefID in ipairs(opts) do
						finishedBuildable[optDefID] = true
					end
				end
			end
		end
	end
	tracy.ZoneEnd()
	tracy.ZoneBeginN("W:BuildMenu:DrawBuildmenu:Cells")
	font2:Begin(true)
	local iconCount = 0
	for row = 1, rows do
		if cellRectID >= maxCellRectID then
			break
		end
		for coll = 1, colls do
			if cellRectID >= maxCellRectID then
				break
			end

			iconCount = iconCount + 1
			cellRectID = cellRectID + 1

			if stickToBottom then
				cellRects[cellRectID] = {
					activeArea[1] + ((coll - 1) * cellSize),
					activeArea[4] - (row * cellSize),
					activeArea[1] + (coll * cellSize),
					activeArea[4] - ((row - 1) * cellSize),
				}
			else
				cellRects[cellRectID] = { -- BAR Droid: droid.gap, the grid in the middle
					activeArea[3] - droid.gap - ((colls - coll + 1) * cellSize),
					activeArea[4] - (row * cellSize),
					activeArea[3] - droid.gap - ((colls - coll) * cellSize),
					activeArea[4] - ((row - 1) * cellSize),
				}
			end
			local cellIsSelected = (activeCmd and cmds[cellRectID] and activeCmd == cmds[cellRectID].name)
			local usedZoom = cellIsSelected and selectedCellZoom or defaultCellZoom

			local uDefIDCell = -cmds[cellRectID].id
			if
				drawCell(
					cellRectID,
					usedZoom,
					cellIsSelected and { 1, 0.85, 0.2, 0.25 } or nil,
					isUnitRestricted(uDefIDCell),
					selectedFactoryCount > 0 and not finishedBuildable[uDefIDCell]
				)
			then
				buildmenuRenderedCells = buildmenuRenderedCells + 1
			end
		end
	end
	tracy.ZoneEnd()

	-- paginator (BAR Droid: while a building is picked, the shape strip in its place)
	droid.shapeRects = {}
	if droid.armed and not stickToBottom then
		paginatorRects = {}
		droid.drawShapes(activeArea, contentWidth, paginatorCellHeight)
	elseif pages == 1 then
		paginatorRects = {}
	else
		tracy.ZoneBeginN("W:BuildMenu:DrawBuildmenu:Paginator")
		local paginatorFontSize = math_max(0.016 * vsy, paginatorCellHeight * 0.2)
			* (stickToBottom and 1 or droid.pageText) -- BAR Droid: the page strip's arrows and number bigger
		local paginatorCellWidth = math_floor(contentWidth * 0.3)

		paginatorRects[1] = {
			activeArea[1],
			activeArea[2],
			activeArea[1] + paginatorCellWidth,
			activeArea[2] + paginatorCellHeight - cellPadding - activeAreaMargin,
		}
		paginatorRects[2] = {
			activeArea[3] - paginatorCellWidth,
			activeArea[2],
			activeArea[3],
			activeArea[2] + paginatorCellHeight - cellPadding - activeAreaMargin,
		}

		UiButton(
			paginatorRects[1][1] + cellPadding,
			paginatorRects[1][2] + cellPadding,
			paginatorRects[1][3] - cellPadding,
			paginatorRects[1][4] - cellPadding,
			1,
			1,
			1,
			1,
			1,
			1,
			1,
			1,
			nil,
			{ 0, 0, 0, 0.8 },
			{ 0.2, 0.2, 0.2, 0.8 },
			bgpadding * 0.5
		)
		font2:Print(
			"<",
			paginatorRects[1][1] + (paginatorCellWidth * 0.5),
			paginatorRects[1][2] + (paginatorCellHeight * 0.5) - (paginatorFontSize * 0.25),
			paginatorFontSize * 1.2,
			"co"
		)
		UiButton(
			paginatorRects[2][1] + cellPadding,
			paginatorRects[2][2] + cellPadding,
			paginatorRects[2][3] - cellPadding,
			paginatorRects[2][4] - cellPadding,
			1,
			1,
			1,
			1,
			1,
			1,
			1,
			1,
			nil,
			{ 0, 0, 0, 0.8 },
			{ 0.2, 0.2, 0.2, 0.8 },
			bgpadding * 0.5
		)
		font2:Print(
			">",
			paginatorRects[2][1] + (paginatorCellWidth * 0.5),
			paginatorRects[2][2] + (paginatorCellHeight * 0.5) - (paginatorFontSize * 0.25),
			paginatorFontSize * 1.2,
			"co"
		)

		font2:Print(
			"\255\245\245\245" .. currentPage .. "  /  " .. pages,
			contentWidth * 0.5,
			activeArea[2] + (paginatorCellHeight * 0.5) - (paginatorFontSize * 0.25),
			paginatorFontSize,
			"co"
		)
		tracy.ZoneEnd()
	end

	font2:End()
	tracy.ZoneEnd()
end

local function refreshBuildmenuTexture()
	if not refreshBuildmenu then
		return
	end
	tracy.ZoneBeginN("W:BuildMenu:DrawScreen:RefreshTexture")
	if not isValidBuildmenuGeometry() then
		refreshBuildmenu = true
		tracy.ZoneEnd()
		return
	end
	if cmdsCount <= 0 then
		refreshBuildmenu = true
		tracy.ZoneEnd()
		return
	end
	local buildmenuUnitpicsWarmDone = true
	local warmedBuildmenuUnitpicThisFrame = false
	if buildmenuUnitpicWarm.count > 0 then
		warmedBuildmenuUnitpicThisFrame = true
		buildmenuUnitpicsWarmDone = flushBuildmenuUnitpicWarmQueue()
	end
	refreshBuildmenu = false
	if not buildmenuTex and width > 0.05 and height > 0.05 then
		tracy.ZoneBeginN("W:BuildMenu:DrawScreen:CreateTextures")
		local ss = WG.FlowUI.supersample or 2
		buildmenuTex = gl.CreateTexture(math_floor(width * vsx) * ss, math_floor(height * vsy) * ss, {
			target = GL.TEXTURE_2D,
			format = GL.RGBA8,
			fbo = true,
		})
		buildmenuTexHasContent = false
		buildmenuBgTex = gl.CreateTexture(math_floor(width * vsx), math_floor(height * vsy), {
			target = GL.TEXTURE_2D,
			format = GL.RGBA8,
			fbo = true,
		})
		gl.R2tHelper.RenderInRect(
			buildmenuBgTex,
			backgroundRect[1],
			backgroundRect[2],
			backgroundRect[3],
			backgroundRect[4],
			drawBuildmenuBg,
			true
		)
		tracy.ZoneEnd()
	end
	local forceInitialRender = buildmenuTex and not buildmenuTexHasContent
	local renderedBuildmenuTex = false
	if buildmenuTex and (forceInitialRender or (buildmenuUnitpicsWarmDone and not warmedBuildmenuUnitpicThisFrame)) then
		tracy.ZoneBeginN("W:BuildMenu:DrawScreen:RenderTexture")
		gl.R2tHelper.RenderInRect(
			buildmenuTex,
			backgroundRect[1],
			backgroundRect[2],
			backgroundRect[3],
			backgroundRect[4],
			drawBuildmenu,
			true
		)
		if buildmenuRenderedCells > 0 then
			droid.drawnAt = spGetGameFrame() -- BAR Droid: (droid.settled)
			buildmenuTexHasContent = true
			renderedBuildmenuTex = true
			if forceInitialRender then
				clearBuildmenuUnitpicWarmQueue()
			end
		else
			buildmenuTexHasContent = false
			refreshBuildmenu = true
		end
		tracy.ZoneEnd()
	end
	if not renderedBuildmenuTex and (not buildmenuUnitpicsWarmDone or warmedBuildmenuUnitpicThisFrame) then
		refreshBuildmenu = true
	end
	tracy.ZoneEnd()
end

function widget:DrawScreen()
	tracy.ZoneBeginN("W:BuildMenu:DrawScreen")
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	droid.drawPanel() -- BAR Droid: the PLACE button (over the order menu)
	droid.drawGridShown() -- BAR Droid: "GRID" over a building for a moment
	if not droid.active() then -- BAR Droid: the controller game while v0.8.5 has the pad: its own menu shows
		tracy.ZoneEnd()
		return
	end
	-- BAR Droid: BAR draws the menu into its texture at a game's frame 0 and again about 1.4 s in, then only when
	-- something changes; at some starts on the phones its pictures came out of those drawings in stripes, every other
	-- 16 pixels empty, until the next change (dev phone, 2026-11-03: 2 of 8 starts; drawn every 1.5 s, only the drawings
	-- in the start's stutter were striped). A menu last drawn before droid.settled (5 s) is drawn once more then. And
	-- an unchanged menu again every droid.redraw (30 s): one start on the hot dev phone kept its stripes past the 5 s
	-- drawing (2026-11-04, stripes evenly spaced across the cells: the drawing into the texture, not the pictures; the
	-- next drawing clean), one drawing of the texture each time
	local droidFrame = spGetGameFrame()
	if droid.drawnAt and (droid.drawnAt < droid.settled and droidFrame >= droid.settled
		or droidFrame - droid.drawnAt >= droid.redraw) then
		droid.drawnAt = nil
		refreshBuildmenu = true
	end

	if WG.buildmenu then
		WG.buildmenu.hoverID = nil
	end

	if not buildmenuShows then
		tracy.ZoneEnd()
		return
	end

	-- refresh buildmenu if active cmd changed
	local prevActiveCmd = activeCmd

	if spGetGameFrame() == 0 and WG["pregame-build"] then
		activeCmd = WG["pregame-build"] and WG["pregame-build"].getPreGameDefID()
		if activeCmd then
			activeCmd = unitName[activeCmd]
		end
	else
		activeCmd = select(4, spGetActiveCommand())
	end
	if activeCmd ~= prevActiveCmd then
		doUpdate = true
	end

	local x, y, b, b2, b3 = spGetMouseState()
	-- Handle the frame-based counter for race conditions
	if raceConditionUpdateCountdown > 0 then
		raceConditionUpdateCountdown = raceConditionUpdateCountdown - 1
		if raceConditionUpdateCountdown == 0 then
			doUpdate = true
		end
	end

	-- The main refresh condition check
	if doUpdate or refreshBuildmenu then
		tracy.ZoneBeginN("W:BuildMenu:DrawScreen:RefreshCommands")
		RefreshCommands()
		doUpdate = nil
		refreshBuildmenu = true
		tracy.ZoneEnd()
	end

	-- create buildmenu
	refreshBuildmenuTexture()

	-- draw buildmenu background
	tracy.ZoneBeginN("W:BuildMenu:DrawScreen:BlendBackground")
	if buildmenuBgTex and backgroundRect then
		gl.R2tHelper.BlendTexRect(
			buildmenuBgTex,
			backgroundRect[1],
			backgroundRect[2],
			backgroundRect[3],
			backgroundRect[4],
			true
		)
	end
	tracy.ZoneEnd()

	local hovering = false
	if math_isInRect(x, y, backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4]) then
		Spring.SetMouseCursor("cursornormal")
		hovering = true
	end

	if preGamestartPlayer or selectedBuilderCount ~= 0 then
		tracy.ZoneBeginN("W:BuildMenu:DrawScreen:Content")
		-- pre process + 'highlight' under the icons
		local hoveredCellID
		if not WG.topbar or not WG.topbar.showingQuit() then
			if hovering then
				for cellRectID, cellRect in pairs(cellRects) do
					local cmd = cmds[cellRectID]
					if cmd and math_isInRect(x, y, cellRect[1], cellRect[2], cellRect[3], cellRect[4]) then
						hoveredCellID = cellRectID
						local uDefID = -cmd.id
						WG.buildmenu.hoverID = uDefID
						gl.Color(1, 1, 1, 1)
						local _, _, meta, _ = Spring.GetModKeyState()
						if WG.tooltip and not meta and WG.BarDroidInput ~= "pad" and WG.BarDroidInput ~= "touch" then
							-- BAR Droid: with the pad or fingers it covers the grid's next row (a finger's pointer stays on
							-- the cell it tapped), and BAR's info panel says the same
							-- when meta: unitstats does the tooltip
							local text
							local textColor = "\255\215\255\215"
							if isUnitRestricted(uDefID) then
								text = BAR.I18N("ui.buildMenu.disabled", {
									unit = unitTranslatedHumanName[uDefID],
									textColor = textColor,
									warnColor = "\255\166\166\166",
								})
							else
								text = UnitDefs[uDefID].translatedHumanName
							end
							local tooltip = unitTranslatedTooltip[uDefID]
							if unitMetal_extractor[uDefID] then
								tooltip = tooltip .. "\n" .. BAR.I18N("ui.buildMenu.areamex_tooltip")
							end
							WG.tooltip.ShowTooltip("buildmenu", "\255\240\240\240" .. tooltip, nil, nil, text)
						end

						-- highlight --if b and not disableInput then
						glBlending(GL_SRC_ALPHA, GL_ONE)
						RectRound(
							cellRects[cellRectID][1] + cellPadding,
							cellRects[cellRectID][2] + cellPadding,
							cellRects[cellRectID][3] - cellPadding,
							cellRects[cellRectID][4] - cellPadding,
							cellSize * 0.03,
							1,
							1,
							1,
							1,
							{ 0, 0, 0, 0.1 * ui_opacity },
							{ 0, 0, 0, 0.1 * ui_opacity }
						)
						glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
						break
					end
				end
			end
		end

		-- draw buildmenu content
		if buildmenuTex and buildmenuTexHasContent then
			tracy.ZoneBeginN("W:BuildMenu:DrawScreen:BlendContent")
			-- content
			gl.Color(1, 1, 1, 1)
			gl.Texture(buildmenuTex)
			gl.TexRect(backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4], false, true)
			gl.Texture(false)
			tracy.ZoneEnd()
		elseif dlistBuildmenu then
			gl.CallList(dlistBuildmenu)
		end
		droid.drawPicked() -- BAR Droid: the picked building's option outlined

		-- draw highlight
		local usedZoom
		local cellColor
		if not WG.topbar or not WG.topbar.showingQuit() then
			if math_isInRect(x, y, backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4]) then
				-- paginator buttons
				local paginatorHovered = false
				if
					paginatorRects[1]
					and math_isInRect(
						x,
						y,
						paginatorRects[1][1],
						paginatorRects[1][2],
						paginatorRects[1][3],
						paginatorRects[1][4]
					)
				then
					paginatorHovered = 1
				end
				if
					paginatorRects[2]
					and math_isInRect(
						x,
						y,
						paginatorRects[2][1],
						paginatorRects[2][2],
						paginatorRects[2][3],
						paginatorRects[2][4]
					)
				then
					paginatorHovered = 2
				end
				if paginatorHovered then
					if WG.tooltip then
						local text = "\255\240\240\240"
							.. (
								paginatorHovered == 1 and BAR.I18N("ui.buildMenu.previousPage")
								or BAR.I18N("ui.buildMenu.nextPage")
							)
						WG.tooltip.ShowTooltip("buildmenu", text)
					end
					RectRound(
						paginatorRects[paginatorHovered][1] + cellPadding,
						paginatorRects[paginatorHovered][2] + cellPadding,
						paginatorRects[paginatorHovered][3] - cellPadding,
						paginatorRects[paginatorHovered][4] - cellPadding,
						cellSize * 0.03,
						2,
						2,
						2,
						2,
						{ 1, 1, 1, 0 },
						{ 1, 1, 1, (b and 0.35 or 0.15) }
					)
					-- gloss
					RectRound(
						paginatorRects[paginatorHovered][1] + cellPadding,
						paginatorRects[paginatorHovered][4]
							- cellPadding
							- ((paginatorRects[paginatorHovered][4] - paginatorRects[paginatorHovered][2]) * 0.5),
						paginatorRects[paginatorHovered][3] - cellPadding,
						paginatorRects[paginatorHovered][4] - cellPadding,
						cellSize * 0.03,
						2,
						2,
						0,
						0,
						{ 1, 1, 1, 0.015 },
						{ 1, 1, 1, 0.13 }
					)
					RectRound(
						paginatorRects[paginatorHovered][1] + cellPadding,
						paginatorRects[paginatorHovered][2] + cellPadding,
						paginatorRects[paginatorHovered][3] - cellPadding,
						paginatorRects[paginatorHovered][2]
							+ cellPadding
							+ ((paginatorRects[paginatorHovered][4] - paginatorRects[paginatorHovered][2]) * 0.33),
						cellSize * 0.03,
						0,
						0,
						2,
						2,
						{ 1, 1, 1, 0.025 },
						{ 1, 1, 1, 0 }
					)
				end

				-- draw cell hover
				if hoveredCellID then
					local uDefID = -cmds[hoveredCellID].id
					local cellIsSelected = (activeCmd and cmds[hoveredCellID] and activeCmd == cmds[hoveredCellID].name)
					if
						not prevHoveredCellID
						or hoveredCellID ~= prevHoveredCellID
						or uDefID ~= hoverUdefID
						or cellIsSelected ~= hoverCellSelected
						or b ~= prevB
						or b3 ~= prevB3
						or cmds[hoveredCellID].params[1] ~= prevQueueNr
					then
						prevQueueNr = cmds[hoveredCellID].params[1]
						prevB = b
						prevB3 = b3
						prevHoveredCellID = hoveredCellID
						hoverCellSelected = cellIsSelected
						hoverUdefID = uDefID
						if hoverDlist then
							hoverDlist = gl.DeleteList(hoverDlist)
						end
						hoverDlist = gl.CreateList(function()
							-- determine zoom amount and cell color
							usedZoom = hoverCellZoom
							if not cellIsSelected then
								if (b or b2) and cellIsSelected then
									usedZoom = clickSelectedCellZoom
								elseif cellIsSelected then
									usedZoom = selectedCellZoom
								elseif (b or b2) and not disableInput then
									usedZoom = clickCellZoom
								elseif b3 and not disableInput and cmds[hoveredCellID].params[1] then
									-- has queue
									usedZoom = rightclickCellZoom
								end
								-- determine color
								if (b or b2) and not disableInput then
									cellColor = { 0.3, 0.8, 0.25, 0.2 }
								elseif b3 and not disableInput then
									cellColor = { 1, 0.35, 0.3, 0.2 }
								else
									cellColor = { 0.63, 0.63, 0.63, 0 }
								end
							else
								-- selected cell
								if b or b2 or b3 then
									usedZoom = clickSelectedCellZoom
								else
									usedZoom = selectedCellZoom
								end
								cellColor = { 1, 0.85, 0.2, 0.25 }
							end
							if not isUnitRestricted(uDefID) then
								local unsetShowPrice
								if not showPrice then
									unsetShowPrice = true
									showPrice = true
								end

								-- re-draw cell with hover zoom (and price shown)
								font2:Begin(true)
								drawCell(hoveredCellID, usedZoom, cellColor, isUnitRestricted(uDefID))
								font2:End()

								if unsetShowPrice then
									showPrice = false
									unsetShowPrice = nil
								end
							end
						end)
					end
					if hoverDlist then
						droid.drawHover(hoveredCellID, hoverDlist) -- BAR Droid: with the gamepad bigger, outlined
						droid.drawPicked() -- BAR Droid: again (a finger's tap leaves the pointer on the cell it picked,
						-- which BAR draws anew here)
					end
				end
			end
		end

		-- draw attention highlights (animated)
		tracy.ZoneBeginN("W:BuildMenu:DrawScreen:Highlights")
		drawHighlights()
		tracy.ZoneEnd()

		-- draw builders buildoption progress
		if showBuildProgress then
			tracy.ZoneBeginN("W:BuildMenu:DrawScreen:BuildProgress")
			for builderUnitID, _ in pairs(selectedBuilders) do
				local unitBuildID = spGetUnitIsBuilding(builderUnitID)
				if unitBuildID and not drawnBuildTargets[unitBuildID] then
					drawnBuildTargets[unitBuildID] = true
					local unitBuildDefID = spGetUnitDefID(unitBuildID)
					if unitBuildDefID then
						local cellRectID = unitDefToCellMap[unitBuildDefID]
						if cellRectID and cellRects[cellRectID] then
							local _, progress = spGetUnitIsBeingBuilt(unitBuildID)
							progress = 1 - progress -- make the effect wind counter-clockwise
							local progressRect = cellRects[cellRectID]
							local x1 = progressRect[1] + cellPadding + iconPadding
							local y1 = progressRect[2] + cellPadding + iconPadding
							local x2 = progressRect[3] - cellPadding - iconPadding
							local y2 = progressRect[4] - cellPadding - iconPadding
							if isValidRect(x1, y1, x2, y2) then
								RectRoundProgress(x1, y1, x2, y2, cellSize * 0.03, progress, progressColor)
							end
						end
					end
				end
			end
			for k in pairs(drawnBuildTargets) do
				drawnBuildTargets[k] = nil
			end
			tracy.ZoneEnd()
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

-- BAR Droid: the menu and the PLACE button are interface: a finger there clicks, it does not pan or pick a spot
function widget:IsAbove(x, y)
	local r, p = backgroundRect, droid.panel
	return (buildmenuShows and r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4])
		or (p and x >= p.all[1] and x <= p.all[3] and y >= p.all[2] and y <= p.all[4]) or false
end

function widget:DrawWorld()
	droid.drawSpot() -- BAR Droid: the spot a tap picked (so this call-in stays after the start)
	-- Avoid unnecessary overhead after buildqueue has been setup in early frames
	if spGetGameFrame() > 0 then
		return
	end

	if not preGamestartPlayer then
		return
	end

	if startDefID ~= Spring.GetTeamRulesParam(myTeamID, "startUnit") then
		startDefID = Spring.GetTeamRulesParam(myTeamID, "startUnit")
		doUpdate = true
	end
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdOpts, cmdParams, cmdTag)
	if units.isFactory[unitDefID] and cmdID < 0 then
		-- filter away non build cmd's
		raceConditionUpdateCountdown = 2
	end
	if cmdID == CMD_STOP_PRODUCTION then
		if WG.Quotas then
			local quotas = WG.Quotas.getQuotas()
			quotas[unitID] = nil
			doUpdate = true
		end
	end
end

function widget:SelectionChanged(sel)
	--[[ MODIFICATION START ]]
	-- Adaptive throttling: increase delay based on selection size
	local selCount = #sel
	local throttleDelay = 0.01
	if selCount >= 300 then
		throttleDelay = 0.03
	elseif selCount >= 160 then
		throttleDelay = 0.02
	elseif selCount >= 80 then
		throttleDelay = 0.015
	end

	selectionUpdateTime = os_clock() + throttleDelay
	-- Invalidate cached commands on selection change
	cachedActiveCmdDescs = nil
	--[[ MODIFICATION END ]]
end

local function unbindBuildUnits()
	for _, buildOption in ipairs(boundUnits) do
		widgetHandler.actionHandler:RemoveAction(self, "buildunit_" .. buildOption, "p") ---@diagnostic disable-line: undefined-global
	end

	boundUnits = {}
end

function widget:GameStart()
	preGamestartPlayer = false

	unbindBuildUnits()
end

function widget:GameFrame(n)
	if n % 15 ~= 0 or selectedFactoryCount == 0 then
		return
	end
	local finishedCount = 0
	for _, unitID in ipairs(spGetSelectedUnits()) do
		local defID = spGetUnitDefID(unitID)
		if units.isFactory and units.isFactory[defID] then
			if not spGetUnitIsBeingBuilt(unitID) then
				finishedCount = finishedCount + 1
			end
		end
	end
	if finishedCount ~= prevAnyFactoryUnfinished then
		prevAnyFactoryUnfinished = finishedCount
		refreshBuildmenu = true
	end
end

local function setPreGamestartDefID(uDefID)
	selBuildQueueDefID = uDefID
	if WG["pregame-build"] then
		WG["pregame-build"].setPreGamestartDefID(uDefID)
	end
end

local function isOnQuotaBuildMode(targetDefID)
	for _, unitID in ipairs(spGetSelectedUnits()) do
		local uDefID = spGetUnitDefID(unitID)
		if units.isFactory[uDefID] and table.contains(unitBuildOptions[uDefID], targetDefID) then
			return WG.Quotas and WG.Quotas.isOnQuotaMode(unitID)
		end
	end
	return false
end

local function updateQuotaNumber(unitDefID, count)
	if WG.Quotas then
		local quotaChanged = false
		for _, builderID in ipairs(Spring.GetSelectedUnits()) do
			local uDefID = spGetUnitDefID(builderID)
			if units.isFactory[uDefID] and table.contains(unitBuildOptions[uDefID], unitDefID) then
				local quotas = WG.Quotas.getQuotas()
				quotas[builderID] = quotas[builderID] or {}
				quotas[builderID][unitDefID] = quotas[builderID][unitDefID] or 0
				local prev = quotas[builderID][unitDefID]
				quotas[builderID][unitDefID] = mathMax(quotas[builderID][unitDefID] + (count or 0), 0)
				quotaChanged = quotaChanged or prev ~= quotas[builderID][unitDefID]
			end
		end
		doUpdate = true
		return quotaChanged
	end
end

local function changeQuotas(uDefID, quantity)
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	if ctrl then
		quantity = quantity * modKeyMultiplier.ctrl
	end
	if shift then
		quantity = quantity * modKeyMultiplier.shift
	end
	return updateQuotaNumber(uDefID, quantity)
end

function widget:MousePress(x, y, button)
	if Spring.IsGUIHidden() then
		return
	end
	if droid.pressPanel(x, y) then -- BAR Droid: the PLACE button
		return true
	end
	if not droid.active() then -- BAR Droid: hidden (the controller game while v0.8.5 has the pad)
		return
	end
	if WG.topbar and WG.topbar.showingQuit() then
		return
	end

	if
		buildmenuShows
		and math_isInRect(x, y, backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4])
	then
		if selectedBuilderCount > 0 or (preGamestartPlayer and startDefID) then
			if droid.press(x, y) then -- BAR Droid: the shape strip
				return true
			end
			if
				paginatorRects[1]
				and math_isInRect(
					x,
					y,
					paginatorRects[1][1],
					paginatorRects[1][2],
					paginatorRects[1][3],
					paginatorRects[1][4]
				)
			then
				currentPage = currentPage - 1
				if currentPage < 1 then
					currentPage = pages
				end
				doUpdate = true
			end
			if
				paginatorRects[2]
				and math_isInRect(
					x,
					y,
					paginatorRects[2][1],
					paginatorRects[2][2],
					paginatorRects[2][3],
					paginatorRects[2][4]
				)
			then
				currentPage = currentPage + 1
				if currentPage > pages then
					currentPage = 1
				end
				doUpdate = true
			end
			if not disableInput then
				for cellRectID, cellRect in pairs(cellRects) do
					if
						cmds[cellRectID]
						and cmds[cellRectID].id
						and unitTranslatedHumanName[-cmds[cellRectID].id]
						and math_isInRect(x, y, cellRect[1], cellRect[2], cellRect[3], cellRect[4])
						and not isUnitRestricted(-cmds[cellRectID].id)
					then
						local uDefID = cmds[cellRectID].id --WARNING: THIS IS -unitDefID, not unitDefID
						local setQuotas = isOnQuotaBuildMode(-uDefID)
						local alt, ctrl, meta, shift = Spring.GetModKeyState()
						if button ~= 3 then
							if playSounds then
								Spring.PlaySoundFile(sound_queue_add, 0.75, "ui")
							end
							if setQuotas and not alt then
								changeQuotas(-uDefID, 1)
							else
								if preGamestartPlayer then
									setPreGamestartDefID(-uDefID)
								elseif spGetCmdDescIndex(uDefID) then
									local isRepeatMex = unitMetal_extractor[-uDefID] and unitName[-uDefID] == activeCmd
									local cmd = isRepeatMex and "areamex" or spGetCmdDescIndex(uDefID)
									if isRepeatMex then
										WG.areamex.setAreaMexType(uDefID)
									end
									Spring.SetActiveCommand(cmd, 1, true, false, alt, ctrl, meta, shift)
								end
							end
						else
							-- Ignores the count from the quota widget.
							local queueCount = getPlayerQueueCount(cellRectID, -uDefID) or 0

							local function decreaseQuota()
								if changeQuotas(-uDefID, modKeyMultiplier.right) and playSounds then
									Spring.PlaySoundFile(sound_queue_rem, 0.75, "ui")
								end
							end

							local function decreaseQueue()
								if queueCount > 0 and playSounds then
									Spring.PlaySoundFile(sound_queue_rem, 0.75, "ui")
								end
								if preGamestartPlayer then
									setPreGamestartDefID(-cmds[cellRectID].id)
								elseif spGetCmdDescIndex(cmds[cellRectID].id) then
									Spring.SetActiveCommand(
										spGetCmdDescIndex(cmds[cellRectID].id),
										3,
										false,
										true,
										Spring.GetModKeyState()
									)
								end
							end

							local isQuotaMode = setQuotas and not alt
							local quotaInfo = cellQuotas[-uDefID]
							local currentQuota = (quotaInfo and quotaInfo.quota) or 0

							if isQuotaMode then
								if currentQuota > 0 then
									decreaseQuota()
								else
									decreaseQueue()
								end
							else
								if queueCount > 0 then
									decreaseQueue()
								else
									decreaseQuota()
								end
							end
						end
						raceConditionUpdateCountdown = 2
						return true
					end
				end
			end
			return true
		elseif alwaysShow then
			return true
		end
	end
end

-- Used for hotkeys at pregamestart
local function buildUnitHandler(_, _, _, data)
	-- sanity check
	if not preGamestartPlayer then
		return
	end
	if isUnitRestricted(data.unitDefID) then
		return
	end

	if
		not unitName[startDefID]
		or not comBuildOptions[unitName[startDefID]]
		or not comBuildOptions[unitName[startDefID]][data.unitDefID]
	then
		return
	end

	-- If no current active selection we can return early
	if not selBuildQueueDefID then
		setPreGamestartDefID(data.unitDefID)
		return true
	end

	-- Find the buildcycle for current key and iterate on it
	local pressedKey, pressedScan
	for k, v in pairs(Spring.GetPressedKeys()) do
		if v and tonumber(k) then
			local key = Spring.GetKeySymbol(tonumber(k))
			if key and #key == 1 then
				pressedKey = key
				break
			end
		end
	end

	-- check if engine supports GetPressedScans first, adjust when/if https://github.com/beyond-all-reason/spring/pull/388 is deployed
	local pressedScans = Spring.GetPressedScans and Spring.GetPressedScans() or {}
	for k, v in pairs(pressedScans) do
		if v and tonumber(k) then
			local scan = Spring.GetScanSymbol(tonumber(k))
			if scan and #scan == 4 then -- quick hack to avoid modifiers
				pressedScan = scan
				break
			end
		end
	end

	-- didn't find a suitable binding to cycle from
	if not (pressedKey or pressedScan) then
		return
	end

	-- Clear and reuse temp table instead of creating new one
	clearTable(buildCycleTemp)
	local buildCycleCount = 0
	for _, keybind in ipairs(Spring.GetKeyBindings(pressedKey, pressedScan)) do
		if string_sub(keybind.command, 1, 10) == "buildunit_" then
			local uDefName = string_sub(keybind.command, 11)
			local uDef = UnitDefNames[uDefName]
			if uDef then -- prevents crashing when trying to access unloaded units (legion)
				if comBuildOptions[unitName[startDefID]][uDef.id] and not isUnitRestricted(uDef.id) then
					buildCycleCount = buildCycleCount + 1
					buildCycleTemp[buildCycleCount] = uDef.id
				end
			end
		end
	end

	if buildCycleCount == 0 then
		return
	end

	local buildCycleIndex
	for i = 1, buildCycleCount do
		if buildCycleTemp[i] == selBuildQueueDefID then
			buildCycleIndex = i
			break
		end
	end

	if not buildCycleIndex then
		setPreGamestartDefID(data.unitDefID)
		return true
	end

	buildCycleIndex = buildCycleIndex + 1
	if buildCycleIndex > buildCycleCount then
		buildCycleIndex = 1
	end

	setPreGamestartDefID(buildCycleTemp[buildCycleIndex])

	return true
end

local function bindBuildUnits(widget)
	if not preGamestartPlayer then
		return
	end

	unbindBuildUnits()

	comBuildOptions = {}
	local validStartUnits = string.split(
		spGetTeamRulesParam(myTeamID, "validStartUnits") or Spring.GetGameRulesParam("validStartUnits"),
		"|"
	)
	for _, unitDefIDString in ipairs(validStartUnits) do
		local unitDefID = tonumber(unitDefIDString)
		local unitDef = unitDefID and UnitDefs[unitDefID]
		if unitDef then
			comBuildOptions[unitDef.name] = {}
		end
	end

	for comDefName, buildOptions in pairs(comBuildOptions) do
		for _, buildOption in ipairs(UnitDefNames[comDefName].buildOptions) do
			if not units.unitRestricted[buildOption] then
				local unitDefName = unitName[buildOption]
				buildOptions[buildOption] = true
				table.insert(boundUnits, unitDefName)
				widgetHandler.actionHandler:AddAction(
					widget,
					"buildunit_" .. unitDefName,
					buildUnitHandler,
					{ unitDefID = buildOption },
					"p"
				)
			end
		end
	end
end

function widget:Initialize()
	-- BAR Droid: the controller game keeps v0.8.5's build menu in BAR's place (WG.buildmenu: v0.8.5's gamepad drives
	-- it); this one runs beside it (WG.bardroidBuildmenu), shown only while the app's controls have the pad (a triple
	-- tap; bardroid_pad.lua sets WG.BarDroidOwnsBuildMenu and hides v0.8.5's panel then). Kailil, 2026-10-29: "What
	-- happened to my 3x3 build menu grid? its gone".
	if (Game.gameVersion or ""):find("$VERSION", 1, true) or (WG.buildmenu and WG.buildmenu.controllerApiVersion) then
		Spring.Echo("[bardroid-buildmenu] the controller game: beside its own build menu, shown with the app's controls")
		droid.ctl = true
	end
	widgetHandler:RegisterUnitCommand(CMD.BUILD) -- BAR Droid: the handler's stand-in for user widgets
	widgetHandler:RegisterUnitCommand(CMD_STOP_PRODUCTION)
	refreshUnitDefs()
	units.loadBlocked()

	-- BAR Droid: BAR's Grid menu is off by launch-bar.sh (a user widget cannot switch widgets)

	-- If mission disables the initial commander spawn, suppress the entire pregame build path (build menu, startDefID binding, buildmenuShows = true, etc.)
	if preGamestartPlayer then
		local missionOptions = require("luaui/Include/mission_options")
		preGamestartPlayer = not missionOptions.IsStartUnitSpawnDisabled()
	end

	-- Get our starting unit
	if preGamestartPlayer then
		bindBuildUnits(self)
		if not startDefID or startDefID ~= spGetTeamRulesParam(myTeamID, "startUnit") then
			startDefID = spGetTeamRulesParam(myTeamID, "startUnit")
			doUpdate = true
		end
	end

	widget:ViewResize()
	widget:SelectionChanged(spGetSelectedUnits())

	droid.register() -- BAR Droid
	droid.shared = WG.buildmenu -- (the controller game: v0.8.5's, given back at the end of Initialize)
	WG.buildmenu = {}
	-- BAR Droid: the grid as laid out (tools/touch-widget-test.ps1)
	WG.buildmenu.droidGrid = function()
		return colls, rows, pages, cmdsCount
	end
	WG.buildmenu.droidPlace = function() -- (and the shape strip: a building picked, the shape, the buttons, a tap)
		return droid.armed, droid.shape, droid.shapeRects
	end
	WG.buildmenu.droidPress = droid.press
	WG.buildmenu.droidSetShape = function(shape) -- (the portrait dock's own shape buttons: one, line, grid, border)
		droid.shape = shape
		clear()
		droid.place()
	end
	WG.buildmenu.droidPanel = function() -- (the PLACE button's rects and the spot)
		return droid.panel, droid.spot
	end
	WG.buildmenu.droidPressPanel = droid.pressPanel
	WG.buildmenu.droidSpot = droid.setSpot -- (bardroid_touch.lua: the app's "spot" lines)
	WG.buildmenu.droidNudge = droid.nudge -- (the app's "nudge" lines)
	WG.buildmenu.droidSetGrid = droid.setGrid -- (the app's "grid" lines)
	WG.buildmenu.droidPad = droid.pad -- (bardroid_touch.lua: the gamepad's pad_* actions)
	WG.buildmenu.droidFocus = function() -- (the option the gamepad is on, and the page)
		return droid.focus, currentPage
	end
	WG.buildmenu.droidSetWarp = function(fn) -- (tools/touch-widget-test.ps1: no pointer moves without -Pointer; the
		droid.warp, droid.fakeWarp = fn or Spring.WarpMouse, fn ~= nil -- focus then does not follow the pointer)
	end
	WG.buildmenu.droidDrawHover = droid.drawHover -- (the same: drawn once without a pointer over the menu)
	WG.buildmenu.getGroups = function()
		return groups, units.unitGroup
	end
	WG.buildmenu.getOrder = function()
		return units.unitOrder
	end
	WG.buildmenu.getShowPrice = function()
		return showPrice
	end
	WG.buildmenu.setShowPrice = function(value)
		showPrice = value
		clear()
	end
	WG.buildmenu.getAlwaysShow = function()
		return alwaysShow
	end
	WG.buildmenu.setAlwaysShow = function(value)
		alwaysShow = value
		clear()
	end
	WG.buildmenu.getShowRadarIcon = function()
		return showRadarIcon
	end
	WG.buildmenu.setShowRadarIcon = function(value)
		showRadarIcon = value
		clear()
	end
	WG.buildmenu.getShowGroupIcon = function()
		return showGroupIcon
	end
	WG.buildmenu.setShowGroupIcon = function(value)
		showGroupIcon = value
		clear()
	end
	WG.buildmenu.getDynamicIconsize = function()
		return dynamicIconsize
	end
	WG.buildmenu.setDynamicIconsize = function(value)
		dynamicIconsize = value
		clear()
	end
	WG.buildmenu.getMinColls = function()
		return minColls
	end
	WG.buildmenu.setMinColls = function(value)
		minColls = value
		clear()
	end
	WG.buildmenu.getMaxColls = function()
		return maxColls
	end
	WG.buildmenu.setMaxColls = function(value)
		maxColls = value
		clear()
	end
	WG.buildmenu.getDefaultColls = function()
		return defaultColls
	end

	WG.buildmenu.setDefaultColls = function(value)
		defaultColls = value
		clear()
	end
	WG.buildmenu.getBottomPosition = function()
		return stickToBottom
	end
	WG.buildmenu.setBottomPosition = function(value)
		stickToBottom = value
		widget:Update(1000)
		widget:ViewResize()
		clear()
	end
	WG.buildmenu.getSize = function()
		return posY, posY2
	end
	WG.buildmenu.getMaxPosY = function()
		return maxPosY
	end
	WG.buildmenu.setMaxPosY = function(value)
		maxPosY = value
		clear()
	end
	WG.buildmenu.reloadBindings = function()
		bindBuildUnits(self)
	end
	WG.buildmenu.getIsShowing = function()
		return buildmenuShows
	end
	---@class CostLine
	---@field value number?
	---@field color string?
	---@field colorDisabled string?
	---@field disabled boolean?

	---@class CostData
	---@field top CostLine?
	---@field bottom CostLine?

	---Override the cost display for a specific unit in the build menu
	---@param unitDefID UnitDefID The unit definition ID to override costs for
	---@param costData CostData Cost override configuration table with optional properties
	WG.buildmenu.setCostOverride = function(unitDefID, costData)
		if unitDefID and costData then
			costOverrides[unitDefID] = costData
			clear()
		end
	end

	---Clear cost overrides for a specific unit or all units
	---@param unitDefID UnitDefID? The unit definition ID to clear overrides for. If nil or not provided, clears all cost overrides.
	WG.buildmenu.clearCostOverrides = function(unitDefID)
		if unitDefID then
			costOverrides[unitDefID] = nil
		else
			for defID in pairs(costOverrides) do
				costOverrides[defID] = nil
			end
		end
		clear()
	end

	---Highlight a build option to draw the player's attention to it with a pulsing
	---inner outline and a soft inner glow. Non-destructive: does not affect input or
	---block hover/selection visuals. Subsequent calls update the existing highlight.
	---@param unitDefID UnitDefID The unit definition ID to highlight.
	---@param color number[]? Optional {r,g,b} in 0..1. Defaults to a warm yellow.
	WG.buildmenu.setHighlight = function(unitDefID, color)
		if not unitDefID then
			return
		end
		if not highlights[unitDefID] then
			highlightCount = highlightCount + 1
		end
		highlights[unitDefID] = {
			color = color,
			startTime = (highlights[unitDefID] and highlights[unitDefID].startTime) or os_clock(),
		}
	end

	---Remove a highlight previously set via setHighlight.
	---@param unitDefID UnitDefID
	WG.buildmenu.removeHighlight = function(unitDefID)
		if unitDefID and highlights[unitDefID] then
			highlights[unitDefID] = nil
			highlightCount = math_max(0, highlightCount - 1)
		end
	end

	---Clear all active highlights.
	WG.buildmenu.clearHighlights = function()
		for k in pairs(highlights) do
			highlights[k] = nil
		end
		highlightCount = 0
	end

	---Returns true if there is an active highlight for the given unitDefID.
	---@param unitDefID UnitDefID
	---@return boolean
	WG.buildmenu.hasHighlight = function(unitDefID)
		return unitDefID ~= nil and highlights[unitDefID] ~= nil
	end
	-- BAR Droid: the app's widgets find this menu as WG.bardroidBuildmenu; in the controller game BAR's place
	-- (WG.buildmenu) goes back to v0.8.5's (nil if it has not started yet: it sets its own then)
	WG.bardroidBuildmenu = WG.buildmenu
	if droid.ctl then
		WG.buildmenu = droid.shared
	end
	droid.shared = nil
end

function widget:UnitBlocked(unitDefID, reasons, builderUnitDefID)
	units.setBlocked(unitDefID, reasons, builderUnitDefID)
	if not delayRefresh or delayRefresh < spGetGameSeconds() then
		delayRefresh = spGetGameSeconds() + 0.5 -- delay so multiple sequential UnitBlocked calls are batched in a single update.
	end
end

function widget:BuildOptionsChanged(builderUnitDefID, builtUnitDefID, added)
	local buildOptions = unitBuildOptions[builderUnitDefID]
	if buildOptions then
		dynamicBuildOptions.patch(buildOptions, builtUnitDefID, added)
		unitBuildOptionSet[builderUnitDefID][builtUnitDefID] = added or nil
	end
	if currentSelBuilderDefs[builderUnitDefID] then
		cachedActiveCmdDescs = nil
		doUpdate = true
	end
end

function widget:Shutdown()
	clear()
	if WG.guishader and dlistGuishader then
		WG.guishader.DeleteDlist("buildmenu")
		dlistGuishader = nil
	end
	if WG.buildmenu and WG.buildmenu.getSize and not WG.buildmenu.controllerApiVersion then
		WG.buildmenu = nil
	end
	WG.bardroidBuildmenu = nil -- BAR Droid
	if WG.BarDroidLayout and WG.BarDroidLayout.unregister then -- BAR Droid
		WG.BarDroidLayout.unregister("buildmenu")
	end
end

function widget:GetConfigData()
	return {
		showPrice = showPrice,
		showRadarIcon = showRadarIcon,
		showGroupIcon = showGroupIcon,
		dynamicIconsize = dynamicIconsize,
		minColls = minColls,
		maxColls = maxColls,
		defaultColls = defaultColls,
		stickToBottom = stickToBottom,
		maxPosY = maxPosY,
		gameID = Game.gameID and Game.gameID or Spring.GetGameRulesParam("GameID"),
		alwaysShow = alwaysShow,
	}
end

function widget:SetConfigData(data)
	if data.showPrice ~= nil then
		showPrice = data.showPrice
	end
	if data.showRadarIcon ~= nil then
		showRadarIcon = data.showRadarIcon
	end
	if data.showGroupIcon ~= nil then
		showGroupIcon = data.showGroupIcon
	end
	if data.dynamicIconsize ~= nil then
		dynamicIconsize = data.dynamicIconsize
	end
	if data.minColls ~= nil then
		minColls = data.minColls
	end
	if data.maxColls ~= nil then
		maxColls = data.maxColls
	end
	if data.defaultColls ~= nil then
		defaultColls = data.defaultColls
	end
	if data.stickToBottom ~= nil then
		stickToBottom = data.stickToBottom
	end
	if data.alwaysShow ~= nil then
		alwaysShow = data.alwaysShow
	end
	if data.maxPosY ~= nil then
		maxPosY = data.maxPosY
	end
end
