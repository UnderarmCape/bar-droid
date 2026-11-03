-- BAR Droid player list: BAR's player list (bottom right, AdvPlayersList) small until touched (Kailil, 2026-10-27:
-- "minimized by default, to show really small, and clicking on it makes it expand to its normal size, then i can
-- interact with it. not touching it after 7 seconds lets it return to normal minimized size").
--
-- Minimized: BAR's smallest list scale (0.65), the names column only (and the chat column where it is empty, room for
-- BAR's eraser button), no spectators. A tap on it brings back the
-- player's own scale and columns (the tap itself is taken: it only opens the list); every tap on the open list keeps
-- it open, and OPEN_SECONDS without one minimizes it again. Through BAR's WG.advplayerlist_api only; the player's own
-- settings are what the list returns to, also after a game that ended minimized (saved with this widget's config).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid player list",
		desc = "BAR's player list small until touched",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -5, -- before AdvPlayersList (-4): a tap on the small list opens it instead of acting on a name
		enabled = true,
	}
end

local OPEN_SECONDS = 7
local SMALL_SCALE = 0.65 -- BAR's smallest
-- AdvPlayersList's columns. GetModuleActive takes a number, SetModuleActive a name, and the numbers follow the places
-- BAR sorts its columns into, not its modules table's order: read in that order, the small list and the player's own
-- columns came back scrambled (the open list: income and chat on, resources and share off; dev phone, 2026-11-03).
-- Each column's number is found once per game (findColumns). A BAR version with other columns gets the scale and the
-- spectators only.
local COLUMNS = { "indent", "rank", "country", "allyid", "id", "playerid", "name", "skill", "resources", "income",
	"cpuping", "ally", "share", "chat" }
local KEEP = { name = true }
-- BAR's own columns (its defaults), for a list whose columns the old reading scrambled (config without CONFIG_VERSION)
local BAR_COLUMNS = { indent = true, rank = true, country = true, name = true, resources = true, cpuping = true,
	ally = true, share = true }
local CONFIG_VERSION = 2

-- seconds of real time, on the engine's timer as in the app's other widgets (the engine's os.clock measured the same
-- on the phone: x1.00, 2026-10-28)
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local timer0 = spGetTimer()
local function clock()
	return spDiffTimers(spGetTimer(), timer0)
end

local minimized = false
local normal -- the player's own list: { scale, hideSpecs, columns = { [name] = active } }
local saved -- the same from the last game (widget config data)
local reset -- BAR's columns, once, in place of the player's scrambled ones (SetConfigData)
local lastTouch = 0
local applied = 1 -- the layout editor's size in the list's scale now (open: its own scale times this)

local function api()
	return WG.advplayerlist_api
end

-- the layout editor's size for the list (bardroid_layout.lua): open and small, both times this
local function sizeFactor()
	local L = WG.BarDroidLayout
	return L and L.get("players").size or 1
end

-- every column's state by number, nil if the list has not exactly #COLUMNS
local function states(a)
	if pcall(a.GetModuleActive, #COLUMNS + 1) then
		return nil
	end
	local s = {}
	for i = 1, #COLUMNS do
		local ok, on = pcall(a.GetModuleActive, i)
		if not ok or on == nil then
			return nil
		end
		s[i] = on and true or false
	end
	return s
end

-- the one number whose state differs, else nil
local function changed(s0, s1)
	local at
	for i = 1, #COLUMNS do
		if s0[i] ~= s1[i] then
			if at then
				return nil
			end
			at = i
		end
	end
	return at
end

-- [name] = its number, false if not found: each column switched on (or off, if it already was) and back, once a game
-- (BAR sorts its columns before it offers the calls, and by fixed places: the numbers stay)
local columnAt
local function findColumns(a)
	if columnAt ~= nil then
		return columnAt
	end
	columnAt = false
	if not (a.GetModuleActive and a.SetModuleActive) then
		return false
	end
	local found = {}
	for _, name in ipairs(COLUMNS) do
		local s0 = states(a)
		if not s0 then
			return false
		end
		for _, want in ipairs({ true, false }) do
			a.SetModuleActive({ name, want })
			local s1 = states(a)
			local at = s1 and changed(s0, s1)
			if at then
				found[name] = at
				a.SetModuleActive({ name, s0[at] })
				break
			end
		end
		if not found[name] then
			return false
		end
	end
	columnAt = found
	return found
end

local function readState(a)
	local state = { scale = a.GetScale(), hideSpecs = a.GetAlwaysHideSpecs(), columns = {} }
	local at = findColumns(a)
	if at then
		for _, name in ipairs(COLUMNS) do
			state.columns[name] = a.GetModuleActive(at[name]) and true or false
		end
	end
	return state
end

local function setColumns(a, columns)
	local at = findColumns(a)
	if not at then
		return
	end
	for _, name in ipairs(COLUMNS) do
		local want = columns[name]
		if want ~= nil and (a.GetModuleActive(at[name]) and true or false) ~= want then
			a.SetModuleActive({ name, want })
		end
	end
end

-- BAR's map marks eraser (Clearmapmarks button) sits in the list's bottom right corner, where the small list's last name
-- ran under it ("SuperKitowiec (AI)", dev phone, 2026-11-03). BAR's chat column, as wide as the eraser, keeps that
-- corner free where it draws nothing: no other player (a skirmish: no chat button for an AI) or the player spectating.
local function chatColumnEmpty()
	local me = Spring.GetMyPlayerID()
	if select(3, Spring.GetPlayerInfo(me, false)) then
		return true
	end
	for _, id in ipairs(Spring.GetPlayerList() or {}) do
		if id ~= me and not select(3, Spring.GetPlayerInfo(id, false)) then
			return false
		end
	end
	return true
end

local function looksMinimized(state)
	return state.scale <= SMALL_SCALE * math.max(1, sizeFactor()) + 0.001 and state.hideSpecs
end

local function minimize()
	local a = api()
	if minimized or not a then
		return
	end
	local current = readState(a)
	current.scale = current.scale / applied -- (the player's own scale, without the editor's size)
	applied = 1
	-- a game that ended minimized saved the small list as BAR's settings: the player's own are in our config
	normal = (looksMinimized(current) and saved) or current
	if reset then
		normal.columns, reset = reset, nil
	end
	saved = normal
	a.SetScale(SMALL_SCALE * sizeFactor())
	a.SetAlwaysHideSpecs(true)
	local small = {}
	for _, name in ipairs(COLUMNS) do
		small[name] = KEEP[name] or false
	end
	small.chat = chatColumnEmpty()
	setColumns(a, small)
	minimized = true
end

local function expand()
	local a = api()
	if not minimized or not a or not normal then
		return
	end
	applied = sizeFactor()
	a.SetScale(normal.scale * applied)
	a.SetAlwaysHideSpecs(normal.hideSpecs)
	setColumns(a, normal.columns)
	minimized = false
	lastTouch = clock()
end

local function overList(x, y)
	local pos = api() and api().GetPosition()
	-- { top, left, bottom, right, ... } in screen pixels
	return pos and pos[1] and x >= pos[2] and x <= pos[4] and y >= pos[3] and y <= pos[1]
end

-- spectating by touch (bardroid_spectate.lua): the list stays small and a tap on it brings up the spectate bar instead,
-- on the same timer (Kailil, 2026-10-27: the open list covered the bar's buttons on the inner screen)
local function spectating()
	return WG.BarDroidSpectating == true
end

local barPressed = false -- (a press handed to the spectate bar: its release too)
function widget:MousePress(x, y, button)
	local bar = WG.BarDroidSpectate
	if button == 1 and spectating() and bar and bar.barPress and bar.barPress(x, y) then
		barPressed = true -- the bar's own buttons, ahead of BAR's list (it takes presses far from where it draws)
		return true
	end
	if button ~= 1 or not overList(x, y) then
		return false
	end
	if spectating() then
		lastTouch = clock()
		return true
	end
	if minimized then
		expand()
		return true
	end
	lastTouch = clock()
	return false
end

function widget:MouseRelease(x, y)
	if barPressed then
		barPressed = false
		local bar = WG.BarDroidSpectate
		if bar and bar.barRelease then
			bar.barRelease(x, y)
		end
	end
	return false
end

function widget:Initialize()
	-- (tools/touch-widget-test.ps1: a tap without a finger)
	WG.BarDroidPlayers = {
		press = function(x, y)
			return widget:MousePress(x, y, 1)
		end,
		minimized = function()
			return minimized
		end,
		-- bardroid_spectate.lua's bar opens and closes with the list; a tap on the bar counts as one on the list
		keepOpen = function()
			lastTouch = clock()
		end,
		-- (a double tap that follows a unit brings up the bar, on the same timer; when not spectating the list opens)
		open = function()
			if not spectating() then
				expand()
			end
			lastTouch = clock()
		end,
		-- the spectate bar shows: the list open, or (spectating, the list kept small) tapped less than OPEN_SECONDS ago
		barWanted = function()
			return not minimized or (spectating() and clock() - lastTouch <= OPEN_SECONDS)
		end,
	}
end

-- the list for the layout editor: its size (BAR's list takes no other place)
local registered = false
local function register()
	local L = WG.BarDroidLayout
	if registered or not (L and L.register) then
		return
	end
	registered = true
	L.register("players", {
		label = "Player list",
		can = { size = true },
		rect = function()
			local pos = api() and api().GetPosition()
			if pos and pos[4] then -- { top, left, bottom, right }
				return pos[2], pos[3], pos[4], pos[1]
			end
		end,
		relayout = function()
			local a = api()
			if not a then
				return
			end
			if minimized then
				a.SetScale(SMALL_SCALE * sizeFactor())
			elseif normal then
				applied = sizeFactor()
				a.SetScale(normal.scale * applied)
			end
		end,
	})
end

-- The player's own list back, for BAR to keep: BAR saves every widget's config before any widget's Shutdown
-- (barwidgets.lua widgetHandler:Shutdown), and this widget's before BAR's list's (layer -5, its -4), so it is done
-- in GetConfigData; the small list had gone into BAR's settings at every game's end (dev phone, 2026-11-03). A save
-- while the game goes on (a widget switched on or off) gets the list small again at the next Update.
local smallAgain = false
local function forBarsSave()
	local a = api()
	if not a or not normal then
		return
	end
	if minimized then
		expand()
		smallAgain = true
	end
	if applied ~= 1 then
		a.SetScale(normal.scale) -- (without the layout editor's size)
		applied = 1
	end
end

local started = false
function widget:Update()
	if not api() then
		return
	end
	register()
	if not started or smallAgain then -- the list exists: small from the start
		started, smallAgain = true, false
		minimize()
		return
	end
	if not minimized and (spectating() or clock() - lastTouch > OPEN_SECONDS) then
		minimize()
	end
end

function widget:Shutdown()
	forBarsSave() -- (a reload without a save)
	WG.BarDroidPlayers = nil
	if registered and WG.BarDroidLayout then
		WG.BarDroidLayout.unregister("players")
	end
end

function widget:GetConfigData()
	forBarsSave()
	return saved and { normal = saved, version = CONFIG_VERSION } or {}
end

function widget:SetConfigData(data)
	if type(data) == "table" and type(data.normal) == "table" and tonumber(data.normal.scale) then
		saved = data.normal
		saved.columns = type(saved.columns) == "table" and saved.columns or {}
		if data.version ~= CONFIG_VERSION then
			-- saved by the old reading: these columns, and BAR's own settings with them (put back at every game's
			-- end), are scrambled; BAR's columns instead, once
			reset = {}
			for _, name in ipairs(COLUMNS) do
				reset[name] = BAR_COLUMNS[name] or false
			end
			saved.columns = reset
		end
	end
end
