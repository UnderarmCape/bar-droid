-- BAR Droid top bar: upright, BAR's top bar buttons answer a tap (found 2026-11-11, dev phone, upright skirmish on Onyx
-- Cauldron: Statistics and Settings did nothing and showed the energy bar's and the tide's tooltips instead). Upright the
-- dock hides BAR's resource bars and indicators (wind, tide, commanders; bardroid_portrait.lua topbarBars), and BAR's
-- buttons, wider there than the quarter of the bar BAR keeps for them, lie over where those were. BAR's Top Bar hides them
-- from the picture only: still under the pointer, they show their tooltips and take the press (gui_top_bar.lua
-- hoveringElement), and that widget hears it before Top Bar Buttons (both layer -95000). Here a press on a button over
-- that hidden part does what BAR's button does (gui_top_bar_buttons.lua applyButtonAction, through BAR's WG windows),
-- any other press there is taken (not its hidden sliders), and the hidden parts' tooltips are taken away. BAR's own fix: docs/upstream/bar-topbar-hidden.patch; with it in BAR this
-- widget only repeats what BAR's buttons do.
-- A save unpicks every unit: the engine clears the selection before it writes the game (Recoil's CregLoadSaveHandler
-- SaveGame: a selection would leak on load), so after Save the dock fell back to its home page and the commander had to
-- be picked again (dev phone, 2026-11-12, upright and sideways alike). The selection is noted when BAR's "savegame"
-- action runs (the top bar's Save, here or BAR's own, and its key), before BAR's Save Game Menu does the save, and picked
-- again once the save has cleared it. Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid top bar",
		desc = "Upright: BAR's top bar buttons answer over its hidden resource bars and indicators",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -95500, -- (before BAR's Top Bar and Top Bar Buttons, -95000; after BAR's windows, -99990, which let a press on the top bar through)
		enabled = true,
		handler = true, -- (as the game's widget, BAR's widget handler: its Quit handed to Top Bar Buttons, below)
	}
end

local CLICK = "LuaUI/Sounds/tock.wav" -- (BAR's buttons' own click)
-- BAR's buttons that open one of its windows, and the window's WG name (applyButtonAction's toggleWindow)
local WINDOWS = { options = "options", stats = "teamstats", info = "gameinfo", keybinds = "keybinds",
	changelog = "changelog", mission = "missioninfo", scavengers = "scavengerinfo" }
-- the Top Bar's tooltips for its resource bars and indicators (its Shutdown's list, and the tide's)
local TIPS = { "coms", "wind", "tidal" }
for _, res in ipairs({ "metal", "energy" }) do
	for _, part in ipairs({ "_share_slider", "_share_slider2", "_metalmaker_slider", "_pull", "_income", "_storage", "_current" }) do
		TIPS[#TIPS + 1] = res .. part
	end
end

local chobby = Spring.GetMenuName and string.find(string.lower(Spring.GetMenuName() or ""), "chobby") ~= nil
local gameOver = false
local tipsAt = 0
local wasHidden = false
local saidStrip = false
local reselect, reselectLeft = nil, 0 -- the selection before a save, and the updates left to see the save clear it

local function noteSelection()
	local sel = Spring.GetSelectedUnits()
	if #sel > 0 then
		-- (the engine saves at its loop's next turn, before the next update: 3 updates and the selection still there,
		-- the save did not happen, and a later unpick by the player is left alone)
		reselect, reselectLeft = sel, 3
	end
	return false -- (BAR's Save Game Menu, after this widget in line, does the save)
end

local function pickAgain()
	reselectLeft = reselectLeft - 1
	if Spring.GetSelectedUnitsCount() == 0 then
		local units = {}
		for i = 1, #reselect do
			if Spring.ValidUnitID(reselect[i]) and not Spring.GetUnitIsDead(reselect[i]) then
				units[#units + 1] = reselect[i]
			end
		end
		Spring.SelectUnitArray(units)
		Spring.Echo("[bardroid-topbar] the save unpicked the units: " .. #units .. " picked again")
		reselectLeft = 0
	end
	if reselectLeft <= 0 then
		reselect = nil
	end
end

-- (through actionHandler, with the widget first: BAR's own handler, which this widget has as the game's, has no
-- AddAction of its own; the stand-in user widgets get answers the same call the same way)
function widget:Initialize()
	widgetHandler.actionHandler:AddAction(widget, "savegame", noteSelection, nil, "t")
end

function widget:Shutdown()
	widgetHandler.actionHandler:RemoveAction(widget, "savegame")
end

-- where BAR's hidden resource bars and indicators are on its top bar (x0, y0, x1; GL), or nil when none is hidden or the
-- dock is not up. (Without BAR's Top Bar running, Top Bar Buttons' stand-in GetFreeArea starts where it ends: nothing.)
local function hiddenSpan()
	local P, tb = WG.BarDroidPortrait, WG.topbar
	if not (P and P.active and P.active() and tb and tb.GetPosition and tb.GetFreeArea) then
		return nil
	end
	local barsOff = tb.getResourceBarsVisible and tb.getResourceBarsVisible() == false
	local marksOff = tb.getIndicatorsVisible and tb.getIndicatorsVisible() == false
	if not (barsOff or marksOff) then
		return nil
	end
	local pos, free = tb.GetPosition(), tb.GetFreeArea()
	if not (pos and free and pos[1] and free[1]) or free[1] <= pos[1] then
		return nil
	end
	return pos[1], pos[2], free[1]
end

function widget:MousePress(x, y, button)
	if button ~= 1 then
		return false
	end
	local x0, y0, x1 = hiddenSpan()
	if not x0 or x < x0 or x >= x1 or y < y0 then
		return false
	end
	local tb = WG.topbar
	if tb.showingQuit and tb.showingQuit() then -- (BAR's quit dialog up: its own)
		return false
	end
	if not tb.buttonAt then -- (a release without it: BAR's own Top Bar takes the press, its buttons work; review 2026-11-16)
		return false
	end
	local name = tb.buttonAt(x, y)
	if not name then
		-- (not a button: taken here, as BAR's Top Bar takes it, but without its hidden sliders: a press on the hidden
		-- energy bar's conversion knob, or a team game's share knobs, dragged it unseen and set it where the finger let
		-- go; gui_top_bar.lua MousePress)
		if not saidStrip then
			saidStrip = true
			Spring.Echo("[bardroid-topbar] a press over BAR's hidden top bar, off its buttons: taken (no hidden slider)")
		end
		return true
	end
	local window = WINDOWS[name]
	if window then
		local w = WG[window]
		local open = w and w.isvisible and w.isvisible()
		if tb.hideWindows then
			tb.hideWindows()
		end
		-- (BAR's key binding editor stays up while it holds unsaved edits: nothing is opened over it)
		local held = WG.keybinds and WG.keybinds.isvisible and WG.keybinds.isvisible()
		if w and w.toggle and not open and not held then
			w.toggle()
		end
	elseif name == "save" then -- (the button is there only in a game that can be saved)
		if tb.hideWindows then
			tb.hideWindows()
		end
		Spring.SendCommands("savegame " .. os.date("%Y%m%d_%H%M%S"))
	elseif name == "quit" and chobby and not gameOver then
		Spring.SendLuaMenuMsg("showLobby")
	elseif name == "quit" then -- (a game not from the lobby, or over: BAR's quit screen. Top Bar Buttons opens it only
		-- from its own MousePress, which BAR's Top Bar, taking the press over its hidden bars, kept it from: the tap did
		-- nothing, 2026-11-20. As the game's widget this one has BAR's handler and hands it the press; as a user widget,
		-- not: left to BAR, as before; Android's Back asks the same question)
		local wh = widgetHandler
		local tbb = wh and wh.FindWidget and wh:FindWidget("Top Bar Buttons")
		if not (tbb and tbb.MousePress) then
			return false
		end
		tbb:MousePress(x, y, button) -- (it clicks, as its own button does)
		Spring.Echo("[bardroid-topbar] quit: pressed over BAR's hidden top bar, handed to Top Bar Buttons") -- (tools)
		return true
	else
		return false -- (BAR's quit dialog and anything new: left to BAR)
	end
	Spring.PlaySoundFile(CLICK, 0.8, "ui")
	Spring.Echo("[bardroid-topbar] " .. name .. ": pressed over BAR's hidden top bar")
	return true
end

function widget:Update()
	if reselect then
		pickAgain()
	end
	local now = os.clock()
	if now < tipsAt then
		return
	end
	tipsAt = now + 0.25
	local hidden = hiddenSpan() ~= nil
	if hidden and WG.tooltip and WG.tooltip.RemoveTooltip then -- (the Top Bar adds them again when it lays itself out)
		for i = 1, #TIPS do
			WG.tooltip.RemoveTooltip(TIPS[i])
		end
	end
	if hidden ~= wasHidden then
		wasHidden = hidden
		Spring.Echo("[bardroid-topbar] BAR's top bar " .. (hidden and "partly hidden: its buttons answered here, those tooltips off"
			or "whole again"))
	end
end

function widget:GameOver()
	gameOver = true
end

-- A save said nothing: the game stood still ~3 s and went on (dev phone, 2026-11-12). The engine's line for a written
-- save (ILoadSaveHandler::CreateSave; a user widget's VFS does not see Saves/) puts BAR's message up (WG.messages: the
-- app's chat box shows it, else BAR's own), with where the save opens again.
function widget:AddConsoleLine(line)
	if line:find("[ILoadSaveHandler::CreateSave] saved game to file", 1, true) then
		local m = WG.messages
		if m and m.addMessage then
			m.addMessage("Game saved: the lobby's Load Game opens it")
		end
		Spring.Echo("[bardroid-topbar] the save said in BAR's message line: " .. tostring(m and m.addMessage ~= nil))
	end
end
