-- BAR Droid minimap: on the unfolded (near-square) screen BAR's minimap is about half its size until touched (Kailil,
-- 2026-10-28: "make map when unfolded in game, about half the size it already is, then when i tap it, it expands to
-- default size"). A tap on the small minimap only opens it (as the small player list, bardroid_players.lua); every
-- tap on the open minimap keeps it open, and OPEN_SECONDS without one makes it small again. Folded it stays as BAR
-- has it.
--
-- Through BAR's own Minimap widget (gui_minimap.lua), which sizes itself by the MinimapMaxHeight setting and reads it
-- again four times a second: the small size goes in as the engine's in-memory overlay of that setting (never saved,
-- so the player's own stays in springsettings.cfg whatever happens to the game). Installed into LuaUI/Widgets by the
-- app.

function widget:GetInfo()
	return {
		name = "BAR Droid minimap",
		desc = "BAR's minimap half size on the unfolded screen until touched",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -5, -- before BAR's Minimap (0): a tap on the small minimap opens it instead of moving the camera
		enabled = true,
	}
end

local OPEN_SECONDS = 7
local SMALL = 0.5 -- of the minimap's height at the player's own size
local KEY, DEFAULT = "MinimapMaxHeight", 0.32 -- (BAR's Minimap's setting and default)

local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local timer0 = spGetTimer()
local function now()
	return spDiffTimers(spGetTimer(), timer0)
end

local own -- the player's MinimapMaxHeight, read before this widget overlays it
local normalHeight -- the minimap's height (fraction of the screen) at the player's own setting
local small = false
local lastTouch = 0
local startedAt

local testUnfolded -- (tools/touch-widget-test.ps1 on a wide laptop window: as if unfolded)
local function unfolded()
	if testUnfolded ~= nil then
		return testUnfolded
	end
	local vsx, vsy = Spring.GetViewGeometry()
	return vsx * 10 < vsy * 16 -- (as launch-bar.sh: the inner screen is near-square, the cover screen wide)
end

local function setMaxHeight(v)
	Spring.SetConfigFloat(KEY, v, true) -- (the overlay: in memory only)
end

local function expand()
	if small then
		small = false
		setMaxHeight(own)
	end
	lastTouch = now()
end

local function shrink()
	if small or not normalHeight then
		return
	end
	small = true
	setMaxHeight(normalHeight * SMALL)
end

-- the minimap's height at the player's own setting, from BAR's widget (its padding left out)
local function measure()
	local m = WG.minimap
	if not (m and m.getHeight) then
		return nil
	end
	local _, vsy = Spring.GetViewGeometry()
	local pad = WG.FlowUI and WG.FlowUI.elementPadding or 0
	return (m.getHeight() - pad) / vsy
end

function widget:Initialize()
	own = Spring.GetConfigFloat(KEY, DEFAULT)
	startedAt = now()
	WG.BarDroidMinimap = { -- (tools/touch-widget-test.ps1)
		small = function() return small end,
		press = function(x, y) return widget:MousePress(x, y, 1) end,
		setUnfolded = function(v) testUnfolded = v end,
	}
end

function widget:Update()
	-- BAR's Minimap settles its size ~2 s in (the top bar, its own delayed setup)
	if not normalHeight then
		if now() - startedAt < 3 then
			return
		end
		normalHeight = measure()
		if not normalHeight then
			return
		end
	end
	if not unfolded() then
		if small then
			expand()
		end
		return
	end
	if not small and now() - lastTouch > OPEN_SECONDS then
		shrink()
	end
end

function widget:ViewResize()
	-- fold/unfold: measured again at the player's own size
	if small then
		small = false
		setMaxHeight(own)
	end
	normalHeight, startedAt = nil, now()
end

function widget:MousePress(x, y)
	if not Spring.IsAboveMiniMap(x, y) then
		return false
	end
	if small then
		expand()
		return true -- (the tap only opens it)
	end
	lastTouch = now()
	return false
end

function widget:Shutdown()
	setMaxHeight(own)
	WG.BarDroidMinimap = nil
end
