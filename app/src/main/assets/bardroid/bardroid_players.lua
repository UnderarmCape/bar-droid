-- BAR Droid player list: BAR's player list (bottom right, AdvPlayersList) small until touched (Kailil, 2026-10-27:
-- "minimized by default, to show really small, and clicking on it makes it expand to its normal size, then i can
-- interact with it. not touching it after 7 seconds lets it return to normal minimized size").
--
-- Minimized: BAR's smallest list scale (0.65), the names column only, no spectators. A tap on it brings back the
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
-- AdvPlayersList's columns by number (its modules table), for SetModuleActive, which takes names. Used only while the
-- list has exactly these many: a BAR version with other columns gets the scale and the spectators only.
local COLUMNS = { "indent", "rank", "country", "allyid", "id", "playerid", "name", "skill", "resources", "income",
	"cpuping", "ally", "share", "chat" }
local KEEP = { name = true }

local minimized = false
local normal -- the player's own list: { scale, hideSpecs, columns = { [name] = active } }
local saved -- the same from the last game (widget config data)
local lastTouch = 0

local function api()
	return WG.advplayerlist_api
end

local function columnsKnown(a)
	if not a.GetModuleActive then
		return false
	end
	local ok, last = pcall(a.GetModuleActive, #COLUMNS)
	local over = pcall(a.GetModuleActive, #COLUMNS + 1)
	return ok and last ~= nil and not over
end

local function readState(a)
	local state = { scale = a.GetScale(), hideSpecs = a.GetAlwaysHideSpecs(), columns = {} }
	if columnsKnown(a) then
		for i, name in ipairs(COLUMNS) do
			state.columns[name] = a.GetModuleActive(i) and true or false
		end
	end
	return state
end

local function setColumns(a, columns)
	if not columnsKnown(a) then
		return
	end
	for i, name in ipairs(COLUMNS) do
		local want = columns[name]
		if want ~= nil and (a.GetModuleActive(i) and true or false) ~= want then
			a.SetModuleActive({ name, want })
		end
	end
end

local function looksMinimized(state)
	return state.scale <= SMALL_SCALE + 0.001 and state.hideSpecs
end

local function minimize()
	local a = api()
	if minimized or not a then
		return
	end
	local current = readState(a)
	-- a game that ended minimized saved the small list as BAR's settings: the player's own are in our config
	normal = (looksMinimized(current) and saved) or current
	saved = normal
	a.SetScale(SMALL_SCALE)
	a.SetAlwaysHideSpecs(true)
	local small = {}
	for _, name in ipairs(COLUMNS) do
		small[name] = KEEP[name] or false
	end
	setColumns(a, small)
	minimized = true
end

local function expand()
	local a = api()
	if not minimized or not a or not normal then
		return
	end
	a.SetScale(normal.scale)
	a.SetAlwaysHideSpecs(normal.hideSpecs)
	setColumns(a, normal.columns)
	minimized = false
	lastTouch = os.clock()
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

function widget:MousePress(x, y, button)
	if button ~= 1 or not overList(x, y) then
		return false
	end
	if spectating() then
		lastTouch = os.clock()
		return true
	end
	if minimized then
		expand()
		return true
	end
	lastTouch = os.clock()
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
			lastTouch = os.clock()
		end,
		-- (a double tap that follows a unit brings up the bar, on the same timer; when not spectating the list opens)
		open = function()
			if not spectating() then
				expand()
			end
			lastTouch = os.clock()
		end,
		-- the spectate bar shows: the list open, or (spectating, the list kept small) tapped less than OPEN_SECONDS ago
		barWanted = function()
			return not minimized or (spectating() and os.clock() - lastTouch <= OPEN_SECONDS)
		end,
	}
end

local started = false
function widget:Update()
	if not api() then
		return
	end
	if not started then -- the list exists: small from the start
		started = true
		minimize()
		return
	end
	if not minimized and (spectating() or os.clock() - lastTouch > OPEN_SECONDS) then
		minimize()
	end
end

function widget:Shutdown()
	expand() -- (BAR keeps the list's settings: the player's own)
	WG.BarDroidPlayers = nil
end

function widget:GetConfigData()
	return saved and { normal = saved } or {}
end

function widget:SetConfigData(data)
	if type(data) == "table" and type(data.normal) == "table" and tonumber(data.normal.scale) then
		saved = data.normal
		saved.columns = type(saved.columns) == "table" and saved.columns or {}
	end
end
