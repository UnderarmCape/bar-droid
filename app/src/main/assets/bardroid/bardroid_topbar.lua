-- BAR Droid top bar: upright, BAR's top bar buttons answer a tap (found 2026-11-11, dev phone, upright skirmish on Onyx
-- Cauldron: Statistics and Settings did nothing and showed the energy bar's and the tide's tooltips instead). Upright the
-- dock hides BAR's resource bars and indicators (wind, tide, commanders; bardroid_portrait.lua topbarBars), and BAR's
-- buttons, wider there than the quarter of the bar BAR keeps for them, lie over where those were. BAR's Top Bar hides them
-- from the picture only: still under the pointer, they show their tooltips and take the press (gui_top_bar.lua
-- hoveringElement), and that widget hears it before Top Bar Buttons (both layer -95000). Here a press on a button over
-- that hidden part does what BAR's button does (gui_top_bar_buttons.lua applyButtonAction, through BAR's WG windows), and
-- the hidden parts' tooltips are taken away. BAR's own fix: docs/upstream/bar-topbar-hidden.patch; with it in BAR this
-- widget only repeats what BAR's buttons do. Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid top bar",
		desc = "Upright: BAR's top bar buttons answer over its hidden resource bars and indicators",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -95500, -- (before BAR's Top Bar and Top Bar Buttons, -95000; after BAR's windows, -99990, which let a press on the top bar through)
		enabled = true,
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
	local name = tb.buttonAt and tb.buttonAt(x, y)
	if not name then
		return false
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
	else
		return false -- (BAR's quit dialog and anything new: left to BAR)
	end
	Spring.PlaySoundFile(CLICK, 0.8, "ui")
	Spring.Echo("[bardroid-topbar] " .. name .. ": pressed over BAR's hidden top bar")
	return true
end

function widget:Update()
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
