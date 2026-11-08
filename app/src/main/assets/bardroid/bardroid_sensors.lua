-- BAR Droid sensor ranges: BAR's sonar, radar and line-of-sight circles off in big games (Kailil, 2026-11-05: "Yes turn
-- them off in big games"). Each of BAR's three GL4 range widgets tests every line pixel against every other circle on
-- the GPU, so their cost grows with the square of the units that have the sensor: in a late 8v8 at full resolution on a
-- Galaxy S23 Ultra they took ~13% of the GPU's time between them, as much as drawing every unit (BarDroidGpuTimer,
-- docs/ENGINE-SIM.md). A game of BIG_GAME_TEAMS teams or more (5v5 and up) starts with the three at opacity 0 (BAR's
-- widgets draw nothing at 0.01 or less); the player's options menu can still turn them on for that game. BAR's jammer
-- coverage shown all the time (Sensor Ranges Jammer Preview's JammerPreviewAlwaysShow, ~1 ms of GPU a frame there) goes
-- with them; it still shows while a jammer is picked or placed.
--
-- BAR saves the widgets' opacity with their settings when the game ends, so the player's own values are kept in
-- LuaUI/Config/bardroid_sensors.txt while they are hidden, and the next smaller game puts them back, the file kept
-- until that game ends cleanly (the jammer setting is put back when the game ends, or at the next start after a
-- crash). Installed into LuaUI/Widgets by the app.
-- Loaded as one of the game's widgets (an engine-branch build: launch-bar.sh's BARDROID_GAME_WIDGETS) it holds the real
-- widget handler, and switches the three off whole instead: at opacity 0 the line of sight's still draws its stencil
-- every frame (0.9-1.4 % of a late 8v8's real time on the dev phone, 2026-11-06). Those it switched off are noted in
-- the same file ("<api>Off 1") and switched on again by the next smaller game.

function widget:GetInfo()
	return {
		name = "BAR Droid sensor ranges",
		desc = "BAR's sonar, radar and line-of-sight circles off in big games",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
		handler = true, -- (granted to the game's own widgets only: then the range widgets can be switched off whole)
	}
end

local BIG_GAME_TEAMS = 10
local SAVED = "LuaUI/Config/bardroid_sensors.txt"
local APIS = { "sonarrange", "radarrange", "losrange" } -- BAR's WG names (gui_sensor_ranges_*.lua)
local WIDGETS = { sonarrange = "Sensor Ranges Sonar", radarrange = "Sensor Ranges Radar", losrange = "Sensor Ranges LOS" }
local OFF = 0.01 -- (BAR's widgets draw nothing at this or less)
local JAMMER = "JammerPreviewAlwaysShow" -- (an engine setting BAR's jammer preview reads every few seconds)
local jammerOff, restored

-- the real widget handler, if this widget was given it (a game widget's); a user widget's stand-in does not count.
-- Looked up raw: the stand-in's own lookups log "widgetHandler.knownWidgets is not available to user widgets", one
-- warning each, three in every game's infolog (dev phone, 2026-11-08); the real handler holds all three as its own
-- fields (barwidgets.lua)
local function realHandler()
	local h = rawget(widget, "widgetHandler")
	if type(h) ~= "table" then
		return nil
	end
	local known, disable, enable = rawget(h, "knownWidgets"), rawget(h, "DisableWidget"), rawget(h, "EnableWidget")
	return type(known) == "table" and disable and enable and h or nil
end

local function readSaved()
	local saved = {}
	local f = io.open(SAVED, "r")
	if not f then
		return nil
	end
	for line in f:lines() do
		local name, value = line:match("^(%w+) ([%d.]+)$")
		if name then
			saved[name] = tonumber(value)
		end
	end
	f:close()
	return saved
end

local function writeSaved(saved)
	local f = io.open(SAVED, "w")
	if not f then
		return false
	end
	for name, value in pairs(saved) do
		f:write(string.format("%s %.3f\n", name, value))
	end
	f:close()
	return true
end

local function bigGame()
	local teams = 0
	local gaia = Spring.GetGaiaTeamID()
	for _, teamID in ipairs(Spring.GetTeamList() or {}) do
		if teamID ~= gaia then
			teams = teams + 1
		end
	end
	return teams >= BIG_GAME_TEAMS, teams
end

-- once, at the first Update: BAR's range widgets have made their WG tables in their Initialize by then
local done
function widget:Update()
	if done then
		return
	end
	done = true
	local saved = readSaved()
	-- the player's values from a big game before: back first
	if saved then
		for _, api in ipairs(APIS) do
			local w = WG[api]
			if w and saved[api] and w.getOpacity() <= OFF then
				w.setOpacity(saved[api])
			end
		end
		if saved[JAMMER] then
			Spring.SetConfigInt(JAMMER, 1)
		end
	end
	local big, teams = bigGame()
	local handler = realHandler()
	if saved and handler and not big then -- (switched off whole by a big game before: on again)
		for _, api in ipairs(APIS) do
			if saved[api .. "Off"] then
				handler:EnableWidget(WIDGETS[api])
			end
		end
	end
	if not big then
		if saved then
			-- (switched off whole by a big game with the game's widgets: a user widget, as here with BAR's own engine,
			-- cannot switch them on, so the note stays for the next game that can; it said "back", the file went at
			-- the game's end, and the circles stayed off for good, dev phone 2026-11-08)
			local pending = {}
			if not handler then
				for _, api in ipairs(APIS) do
					if saved[api .. "Off"] and not WG[api] then -- (loaded: the player switched it on in BAR's Settings)
						pending[api .. "Off"] = 1
					end
				end
			end
			if next(pending) then
				writeSaved(pending)
				Spring.Echo("[bardroid-sensors] the sensor range circles stay off until a game with the app's game widgets"
					.. " (BAR's Settings can switch them on)")
			else
				-- (the file goes when this game ends cleanly, when BAR saves the values put back: a crash before that
				-- would otherwise leave BAR's saved 0s for good)
				restored = true
				Spring.Echo("[bardroid-sensors] the sensor range circles are back (" .. teams .. " teams)")
			end
		end
		return
	end
	local values, hidden = {}, {}
	for _, api in ipairs(APIS) do
		local w = WG[api]
		local known = handler and handler.knownWidgets[WIDGETS[api]]
		if saved and saved[api .. "Off"] and not (known and known.active) then
			values[api .. "Off"] = 1 -- (still off from the big game before: kept noted)
		elseif known and known.active then
			values[api .. "Off"] = 1 -- (switched off whole, below)
			hidden[#hidden + 1] = api
		elseif w and w.getOpacity() > OFF then
			values[api] = w.getOpacity()
			hidden[#hidden + 1] = api
		end
	end
	if Spring.GetConfigInt(JAMMER, 1) ~= 0 then
		values[JAMMER] = 1
		hidden[#hidden + 1] = "jammer coverage"
	end
	-- (hidden only when the values are kept, else BAR would save them as 0 for good)
	if #hidden > 0 and writeSaved(values) then
		for _, api in ipairs(APIS) do
			if values[api .. "Off"] and handler then
				handler:DisableWidget(WIDGETS[api])
			elseif values[api] then
				WG[api].setOpacity(0)
			end
		end
		if values[JAMMER] then
			Spring.SetConfigInt(JAMMER, 0)
			jammerOff = true
		end
		Spring.Echo("[bardroid-sensors] " .. teams .. " teams: the sensor range circles off (" .. table.concat(hidden, ", ")
			.. "), back in a smaller game")
	end
end

function widget:Shutdown()
	if jammerOff then
		Spring.SetConfigInt(JAMMER, 1)
	end
	if restored then
		pcall(os.remove, SAVED)
	end
end
