-- BAR Droid minimap: on the unfolded (near-square) screen BAR's minimap is about half its size until touched (Kailil,
-- 2026-10-28: "make map when unfolded in game, about half the size it already is, then when i tap it, it expands to
-- default size"). A tap on the small minimap only opens it (as the small player list, bardroid_players.lua); every
-- tap on the open minimap keeps it open, and OPEN_SECONDS without one makes it small again. Upright the same, its
-- small size as tall as BAR's top bar, beside its buttons (Kailil, 2026-11-10: the chat a row of its own under them).
-- Folded and held wide it stays as BAR has it.
--
-- Through BAR's own Minimap widget (gui_minimap.lua), which sizes itself by the MinimapMaxHeight setting and reads it
-- again four times a second: the small size goes in as the engine's in-memory overlay of that setting (never saved,
-- so the player's own stays in springsettings.cfg whatever happens to the game). The layout editor
-- (bardroid_layout.lua) can size it too: its size times the player's own, folded and unfolded (the small one half of
-- that). Installed into LuaUI/Widgets by the app.

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
-- How small the minimap waits: "row" upright (Kailil, 2026-11-10: "Shrink the map by default to fit at the same row as
-- the buttons at the top", the chat then its own row under them), as tall as BAR's top bar; "half" on the unfolded
-- screen held wide (near-square: as launch-bar.sh, the inner screen near-square, the cover screen wide); nil: BAR's size
local function mode()
	if testUnfolded ~= nil then
		return testUnfolded and "half" or nil
	end
	local vsx, vsy = Spring.GetViewGeometry()
	if vsy > vsx * 1.05 then
		return "row"
	end
	return (vsx * 10 < vsy * 16 and vsy * 10 < vsx * 16) and "half" or nil
end
local function unfolded()
	return mode() ~= nil
end

local overlaid -- the overlay this widget last set
local function setMaxHeight(v)
	Spring.SetConfigFloat(KEY, v, true) -- (the overlay: in memory only)
	overlaid = v
end

-- the open minimap's MinimapMaxHeight: the player's own, times the layout editor's size for it
local function full()
	local L = WG.BarDroidLayout
	return own * (L and L.get("minimap").size or 1)
end

local function expand()
	if small then
		small = false
		setMaxHeight(full())
	end
	lastTouch = now()
end

local function shrink()
	if small or not normalHeight then
		return
	end
	local target = normalHeight * SMALL
	if mode() == "row" then
		-- (as tall as BAR's top bar's box: its area less the margin its box keeps inside it, two paddings, and the
		-- minimap's own padding; as tall as the area it stood 12 pixels below the buttons' box, dev phone 2026-11-10)
		local p = WG.topbar and WG.topbar.GetPosition and WG.topbar.GetPosition()
		local _, vsy = Spring.GetViewGeometry()
		if not (p and p[4] and p[2] and p[4] > p[2]) then
			return
		end
		local pad = WG.FlowUI and WG.FlowUI.elementPadding or 0
		target = math.max(0.02, (p[4] - p[2] - 3 * pad) / vsy)
	end
	small = true
	setMaxHeight(target)
end

-- the minimap's height when open, from BAR's widget (its padding left out)
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

-- the minimap for the layout editor: its size (BAR's minimap takes no other place)
local registered = false
local function register()
	local L = WG.BarDroidLayout
	if registered or not (L and L.register) then
		return
	end
	registered = true
	L.register("minimap", {
		label = "Minimap",
		can = { size = true },
		rect = function()
			local px, py, sx, sy = Spring.GetMiniMapGeometry()
			if not (px and sx and sx > 0 and sy > 0) then
				return nil
			end
			local _, vsy = Spring.GetViewGeometry()
			if not Spring.IsAboveMiniMap(px + sx / 2, py + sy / 2) then -- (its y counted from the top)
				py = vsy - py - sy
			end
			return px, py, px + sx, py + sy
		end,
		relayout = function()
			small = false
			setMaxHeight(full())
			lastTouch = now() -- (open while it is sized; small again later, measured at the new size)
			normalHeight, startedAt = nil, now() - 2.5
		end,
	})
end

function widget:Update()
	register()
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
	-- fold/unfold: open at this screen's size (the player's own, or the layout editor's), measured again; the setting
	-- left alone where nothing of ours is on it (a size the player set in BAR's settings stays)
	small = false
	local target = full()
	if (overlaid and math.abs(overlaid - target) > 1e-6) or (not overlaid and math.abs(target - own) > 1e-6) then
		setMaxHeight(target)
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
	if registered and WG.BarDroidLayout then
		WG.BarDroidLayout.unregister("minimap")
	end
end
