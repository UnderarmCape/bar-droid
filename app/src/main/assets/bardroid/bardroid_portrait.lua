-- BAR Droid portrait dock (Kailil, 2026-11-09: "Lets explore vertical orientation for playing bar ... All the menu ui
-- stuff can be on the bottom portion of the phone. And the game unobstructed shows at the top half"; his pick, layout
-- D: "Lets do D but instead of more orders button ... just have a scroll option ... Cap the buildmenu to 3x4 and have
-- the vertical scroll. If phone has less vertical space, reduce to 3x3 at minimum 3x2. Scroll should be magnetic ...
-- Do not allow scroll to half reveal objects. It should snap the next rows into place"; "I want the UI to look as
-- close as possible to the BAR original still": BAR's own FlowUI panels, buttons and unit tiles).
--
-- While the game's screen is taller than wide (a phone held upright, the unfolded Fold7 held upright: Android leaves
-- the game's orientation to the hand there) the lower part is a dock:
--   top row   the units picked (picture, name, count, health)
--   left      a builder or factory: its build options, 3 wide, 2-4 rows in sight, scrolled by whole rows; units that
--             build nothing: the selection by type (a tap keeps that type); nothing picked, after LOCAL UNITS or ALL
--             UNITS: the combat units by type (a tap picks them; MULTI picks several types)
--   right     the orders, 2 wide, scrolled by whole rows; a building picked: ONE / LINE / GRID / BORDER and the PLACE
--             panel (the build menu copy's, in placeRect); a factory's option pressed: its queue buttons; nothing
--             picked: LOCAL UNITS / ALL UNITS; a box selection being dragged: the unit filters
--   bottom    nothing picked: the control groups as pictures
-- Two modes for fingers (Kailil: the dock as "a camera movement pad ... if I single tap, the ui at the bottom, then I
-- can interact with the ui. It should indicate when its ready to be touched via a quick blink ... if I dont touch the
-- menu after like 5-10seconds, camera panning turns back on"): pad (RtsTouch moves the camera from touches on the dock)
-- and menu (taps press, up and down scroll, a drag on the game box-selects with the dock's filters). The mode and the
-- dock's rects go to RtsTouch in LuaUI/Config/bardroid_dock.txt; its lines come back in the touch log (dockscroll,
-- dockfling, docktap, act dock_menu / dock_select_start / dock_select_end). A mouse or the pad always press directly.
-- Every press goes through Spring.SetActiveCommand or a selection, as BAR's own menus do (online-safe); the one
-- GiveOrder, a factory's state for the units it built, goes through pcall (a host can forbid widgets' orders).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid portrait",
		desc = "Portrait play: the game on top, a touch dock below (build grid, orders, groups)",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -10, -- (before BAR's menus and the touch widget: the dock answers IsAbove and presses first)
		enabled = true,
		handler = true, -- (BAR's widget handler as a game widget, the phone engine: SP.factionPicker; a user widget gets none)
	}
end

local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local spGetActiveCmdDescs, spGetActiveCommand = Spring.GetActiveCmdDescs, Spring.GetActiveCommand
local spGetSelectedUnits, spGetSelectedUnitsCounts = Spring.GetSelectedUnits, Spring.GetSelectedUnitsCounts
local spGetCmdDescIndex, spSetActiveCommand = Spring.GetCmdDescIndex, Spring.SetActiveCommand
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local timer0 = spGetTimer()
local function now()
	return spDiffTimers(spGetTimer(), timer0)
end

-- taller than wide by this much: the dock is up (the unfolded Fold7 upright is 1080x1198, 1.11: at 1.15 it got BAR's
-- landscape HUD squeezed upright, the case the dock is for)
local PORTRAIT = 1.05
local DOCK_MAX = 0.54 -- of the screen's height at most (a tall phone's; a near-square screen's: 0.32, layout)
local MENU_SECONDS = 2.6 -- the menu goes back to the camera pad after this long untouched (Kailil: "5-10seconds";
-- 2026-11-10: 1.25, then "Extend mouse tap ui delay too instead 2 seconds"; 2026-11-12: "extend bottom UI time out by
-- 30 percent. its too short")
local HOME_ROWS = 3 -- nothing picked: the home grid's rows of big buttons (L.homeRows: as many as its buttons take,
-- one more at most, refreshNow; no new local here: the file's main chunk is at Lua's 200)
local BLINK = 0.45 -- seconds of the menu's opening pulse
local DOCK_FILE = "LuaUI/Config/bardroid_dock.txt"
local TOUCH_LOG = "LuaUI/Config/bardroid_touch.txt"

---------------------------------------------------------------------------------------------------------------------
-- Rows that scroll by whole rows (Kailil: "Scroll should be magnetic ... A swipe up or down should make the next blocks
-- appear with a small nudge animation ... Do not allow scroll to half reveal objects"). A finger moves them (the app's
-- dockscroll lines, or a mouse drag); on release they settle on whole rows: a quick flick brings the next page, a slow
-- drag the nearest row; the settle overshoots a little and comes back (the nudge). At rest no row is cut.
local SETTLE, OVERSHOOT, FLICK = 0.30, 1.4, 3.0 -- seconds; easeOutBack's overshoot; rows a second for a page

local function snapNew()
	return { rows = 0, visible = 1, pos = 0, from = 0, to = 0, t = 1 }
end
local function snapMax(s)
	return max(0, s.rows - s.visible)
end
local function easeOutBack(t)
	t = t - 1
	return 1 + (OVERSHOOT + 1) * t * t * t + OVERSHOOT * t * t
end
local function snapSettle(s, target)
	s.from, s.to, s.t = s.pos, max(0, min(snapMax(s), target)), 0
end
local function snapSet(s, rows, visible, keep)
	s.rows, s.visible = rows, visible
	if not keep then
		s.pos, s.from, s.to, s.t, s.drag = 0, 0, 0, 1, nil
	elseif s.to > snapMax(s) then
		snapSettle(s, snapMax(s))
	end
end
-- dy: the finger's move, pixels (up is +); rowH: a row's height
local function snapBy(s, dy, rowH)
	if not s.drag then
		s.drag = { pos0 = s.pos, raw = s.pos }
		s.t = 1 -- (a touch holds a settle where it is)
	end
	local d = s.drag
	d.raw = d.raw + dy / rowH -- (a finger moving up brings the rows below into sight)
	local p, hi = d.raw, snapMax(s)
	if p < 0 then
		p = p / 3 -- (past the ends a rubber band, a third as far)
	elseif p > hi then
		p = hi + (p - hi) / 3
	end
	s.pos = p
end
-- vel: the finger's speed at release, rows a second (up is +)
local function snapRelease(s, vel)
	local d = s.drag
	s.drag = nil
	if not d then
		return
	end
	local base = floor(d.pos0 + 0.5)
	if vel > FLICK then
		snapSettle(s, max(base + s.visible, floor(s.pos + 0.5)))
	elseif vel < -FLICK then
		snapSettle(s, min(base - s.visible, floor(s.pos + 0.5)))
	else
		snapSettle(s, floor(s.pos + 0.5))
	end
end
local function snapUpdate(s, dt)
	if s.drag or s.t >= 1 then
		return
	end
	s.t = min(1, s.t + dt / SETTLE)
	s.pos = s.t >= 1 and s.to or s.from + (s.to - s.from) * easeOutBack(s.t)
end

---------------------------------------------------------------------------------------------------------------------
-- State

local active = false -- the dock is up (a tall screen, playing)
local vsx, vsy = 0, 0
local L = {} -- the layout: rects { x0, y0, x1, y1 } (GL: y up from the bottom)
-- (sideways, one thumb: the pinned side, the panel's tab, whether the panel and its tabs show, HOME's panel open, the
-- D-gun mode on: refresh decides, layout places)
L.side, L.tab, L.panelOn, L.tabsOn, L.homeOpen, L.dgun = "right", "right", true, false, false, false
local font, bold
local leftScroll, rightScroll = snapNew(), snapNew()
local leftItems, rightItems = {}, {} -- what the two halves show now (tiles, buttons)
local leftKind, rightKind = "", ""
local press -- a mouse press on the dock: { side, x, y, button, lastY, lastT, vel, moved }
local typesFrom -- nil, or "local" / "all": a list pressed, those units by type on the left
local multi, multiPicked = false, {}
local cycleAt = {} -- COMMANDER, an idle builder type: the last one each picked (a tap again: the next)
-- Giving and the resource panel (Kailil, 2026-11-09: "a transfer unit ... button to the orders menu ... a teammate
-- selection ui"; a tap on metal or energy: "a drop down that spans the width of the phone" with the conversion (grey)
-- and share (red) sliders and "a send power or send metal button"). Both take the whole grid while open.
local sharing = nil -- "units", "metal" or "energy": the teammate picker
local shareFraction = 0.25 -- of what this team holds (metal, energy)
local resPanel = nil -- "metal" or "energy": its panel
local unqShown = false -- the groups strip's remove-order buttons: a factory picked, or units with orders
local allPicked, keepTypes = false, false -- LOCAL / ALL UNITS: the whole list picked; the list kept through that pick
local slide = nil -- a resource bar's knob being dragged: { item, rect, what: "share" or "convert" }
local factoryItem -- a factory's build option pressed last: its queue buttons on the right
local lastSelection = ""
local menu = false -- the dock's menu is open (fingers press it); else it is the camera pad
local menuAt, lastTouch = -100, -100 -- when it opened; the last touch on it
local selecting = false -- a box selection being dragged on the game (its filters on the right)
local selFilter = "all" -- the box selection's filter, kept for the next one
local filterAt -- a box selection just ended: the filter goes on when the engine has made it
-- the selection's style (Kailil: "I want to test this using the traditional mouse drag or the controller radial"):
-- "box", BAR's own drag; or "circle", the pad's area selection by finger (from where it came down out to it); kept
local selStyle = "box"
local circle -- the circle being dragged: { x, y, z, r } on the ground

local function inRect(x, y, r)
	return r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end

local dirty = true -- the dock's still parts changed: its texture is drawn again (drawDock)
local function markDirty()
	dirty = true
end

local function myTeam()
	return Spring.GetMyTeamID()
end

local function playing()
	local spec = Spring.GetSpectatingState()
	return not spec
end

local function touched()
	lastTouch = now()
end

---------------------------------------------------------------------------------------------------------------------
-- Layout: the dock's rects for this screen; the build grid 3 wide with 2-4 rows, as many as fit (Kailil: "Cap the
-- buildmenu to 3x4 ... reduce to 3x3 at minimum 3x2"); the dock no taller than it needs, DOCK_MAX at most

local showSel, showGroups = true, true -- the selection row and the groups strip shown (refreshNow decides)
local mobilePicked = false -- units that move are picked (refreshNow): a drag on the game draws their orders (writeDock)
-- the orders a drag draws when armed (BAR's custom formations take them with the right button; another order armed
-- would be cancelled by it)
local DRAW_CMDS = { [CMD.MOVE] = true, [CMD.FIGHT] = true, [CMD.PATROL] = true, [CMD.ATTACK] = true }
-- The idle builders in the groups row (drawGroups), and the picked units' build orders (writeDock's draw)
local idleB = { list = {}, at = -1, sig = "", visited = {}, last = nil, origin = nil, scroll = 0, defs = nil, fac = {},
	busy = false, busyAt = nil, tileW = nil, over = 0, snapTo = nil }
-- (the groups row let go, vx its speed in X pixels a second: the tile it would coast to in 0.15 s, whole; Update eases
-- there, idleB.settle)
function idleB.fling(vx)
	local w = idleB.tileW
	if not w or w <= 0 then
		return
	end
	local target = floor((idleB.scroll - vx * 0.15) / w + 0.5) * w
	idleB.snapTo = max(0, min(idleB.over or 0, target))
	markDirty()
end
function idleB.settle(dt)
	local to = idleB.snapTo
	if not to then
		return
	end
	local d = to - idleB.scroll
	if abs(d) < 0.5 then
		idleB.scroll, idleB.snapTo = to, nil
	else
		idleB.scroll = idleB.scroll + d * min(1, (dt or 0.03) * 14)
	end
	markDirty()
end
-- Spectating upright in the dock (Kailil, 2026-11-11, a spectated online game: "The spectator mode buttons is much too
-- small. Unify the look and feel between playing and spectating with the bottom half ui experience. Hide the team list
-- and create a team list inside of our ui experience ... next to ping and last pings ... last pings shoukd be the only
-- option instead of ping. Add a toggle to hide the bottom half ui that will leave a small un hide button"): the spectate
-- widget's tools (bardroid_spectate.lua, WG.BarDroidSpectate) as the dock's big buttons over its whole grid, 6 narrow
-- columns (the arrows one each); TEAMS lists the players by alliance in the grid's place (BAR's own list, at the
-- bottom right, is under the dock); HIDE folds the dock to a small SHOW button at the bottom of the screen.
local SP = { hidden = false, teams = false, COLS = 6 }
-- Types left out of LOCAL / ALL UNITS for a while (Kailil, 2026-11-20: "a way to exclude a unit type temporarily from
-- the all units commands when I press all units. it should be a simple triple tap of the unit icon or something"): a long
-- press on its picture in the list takes it out (dimmed, struck through, the ALL count without it), another brings it
-- back; a plain tap still picks that type alone. For the game (a new game's widgets start with none). (Not a triple tap:
-- the list's first tap picks that type alone and the list closes, so a second and third had nothing to land on.)
SP.leftOut = {} -- defID -> true
function SP.unitsIn(groups) -- the groups' units but the left-out types', and how many were left out
	local all, out = {}, 0
	for _, g in ipairs(groups) do
		if g.defID and SP.leftOut[g.defID] then
			out = out + #(g.units or {})
		else
			for _, u in ipairs(g.units or {}) do
				all[#all + 1] = u
			end
		end
	end
	return all, out
end
-- a scissor in screen pixels, also while drawing into the dock's texture (SP.inTex), whose pixels start at the dock's
-- corner: sideways, one thumb, the dock no longer starts at the screen's left edge, and the halves' rows were cut away
function SP.scissor(x, y, w, h)
	if SP.inTex then
		x, y = x - L.dock[1], y - L.dock[2]
	end
	gl.Scissor(x, y, w, h)
end
function SP.on()
	return Spring.GetSpectatingState() and (WG.BarDroidInput or "touch") == "touch"
end
-- The command types whose order a drag on the map draws as an area, BAR's circle (Area Mex, Reclaim, Repair, Restore,
-- Capture, Load units...): with one armed a one-finger drag is a left drag, writeDock's "draw 2" (Kailil, 2026-11-17:
-- "Area mex command is not working anymore. I cant draw the vanilla circle thing to expand it": since one finger pans
-- whatever is picked, 2026-11-13, only MOVE, FIGHT, PATROL and ATTACK drew, and an area order's drag panned)
SP.AREA_TYPES = {}
for _, name in ipairs({ "ICON_AREA", "ICON_UNIT_OR_AREA", "ICON_UNIT_FEATURE_OR_AREA", "ICON_UNIT_OR_RECTANGLE" }) do
	if CMDTYPE and CMDTYPE[name] then
		SP.AREA_TYPES[CMDTYPE[name]] = true
	end
end
function SP.act(name)
	local S = WG.BarDroidSpectate
	local a = S and S.actions and S.actions[name]
	if a then
		a()
	end
end
-- a team's name: its first player not spectating, else its AI's ("BARb (AI)"); and that player, for the player camera
function SP.teamName(teamID)
	for _, p in ipairs(Spring.GetPlayerList(teamID) or {}) do
		local name, _, spec = Spring.GetPlayerInfo(p, false)
		if name and not spec then
			return name, p
		end
	end
	-- (BAR's own name for an AI first, as its player list and the name over the commander show it: the start script's
	-- was another, "BARbArmada (AI)" in the list over "Zagupi (AI)" on the map, dev phone 2026-11-11)
	local aiName = Spring.GetGameRulesParam("ainame_" .. teamID) or select(2, Spring.GetAIInfo(teamID))
	return (aiName or ("Team " .. teamID)) .. " (AI)", nil
end
-- TEAMS: every team, two to a row, each alliance from a new row, the one watched lit; CLOSE first
function SP.teamItems()
	local out = { { kind = "specclose", label = "CLOSE", w = SP.COLS } }
	local gaia = Spring.GetGaiaTeamID()
	local watched = Spring.GetMyTeamID()
	for _, a in ipairs(Spring.GetAllyTeamList() or {}) do
		local n = 0
		for _, teamID in ipairs(Spring.GetTeamList(a) or {}) do
			if teamID ~= gaia then
				local name, playerID = SP.teamName(teamID)
				local dead = select(3, Spring.GetTeamInfo(teamID, false))
				local r, g, b = Spring.GetTeamColor(teamID)
				out[#out + 1] = { kind = "specteam", team = teamID, player = playerID, label = name, color = { r, g, b },
					w = SP.COLS / 2, on = teamID == watched, dim = dead }
				n = n + 1
			end
		end
		if n % 2 == 1 then -- (the next alliance from a new row: the alliance's last team across the whole row; with an
			-- empty half beside it a 1v1's two teams stood in the left half over a blank one, dev phone 2026-11-13)
			out[#out].w = SP.COLS
		end
	end
	return out
end
-- the grid: following, the camera's views in place of the players (as the spectate bar)
function SP.items()
	if SP.teams then
		return SP.teamItems()
	end
	local S = WG.BarDroidSpectate
	local d = S and S.dockInfo and S.dockInfo() or {}
	local out = {}
	local function add(it)
		out[#out + 1] = it
	end
	if d.follow then
		for _, v in ipairs(S.views and S.views() or {}) do
			add({ kind = "specact", act = "preset_" .. v.key, label = v.label:upper(), w = 2, on = d.view == v.key })
		end
		add({ kind = "specact", act = "tune", label = "TUNE", w = 2, on = d.tuning })
	else
		local none = (d.players or 0) == 0
		add({ kind = "specact", act = "player_prev", label = "<", w = 1, dim = none })
		add({ kind = "specact", act = "player_next", w = 4, on = d.player ~= nil, dim = none, color = d.player and d.playerColor,
			label = none and "NO PLAYER CAMS" or d.player and d.playerName or "PLAYER CAM" })
		add({ kind = "specact", act = "player_next", label = ">", w = 1, dim = none })
	end
	add({ kind = "specteams", label = "TEAMS", w = 2 })
	add({ kind = "pings", w = 2 })
	add({ kind = "spechide", label = "HIDE", w = 2 })
	add({ kind = "specact", act = "unit_prev", label = "<", w = 1 })
	add({ kind = "specact", act = "unit_next", w = 4, on = d.follow, color = d.follow and d.followColor,
		label = d.follow and d.followName or "FOLLOW UNIT" })
	add({ kind = "specact", act = "unit_next", label = ">", w = 1 })
	add({ kind = "specact", act = "free", label = "FREE CAM", w = 2, on = not d.player and not d.follow })
	add({ kind = "specact", act = "group", label = "GROUP", w = 2, on = d.group })
	add({ kind = "specfull", label = "FULL VIEW", w = 2, on = select(2, Spring.GetSpectatingState()) and true or false })
	return out
end
-- a team picked in TEAMS: its view (BAR's specteam, the team's sight) and its player's camera; the list closes
function SP.pick(it)
	Spring.SendCommands("specteam " .. it.team)
	local S = WG.BarDroidSpectate
	if it.player and S and S.lockPlayer then
		S.lockPlayer(it.player)
	end
	SP.teams = false
end

local function layout()
	markDirty()
	vsx, vsy = Spring.GetViewGeometry()
	L.hole, L.leftCols, L.rightCols = nil, 3, 2
	L.thumb, L.tabs, L.homeBtn, L.swapBtn, L.dgFloat, L.windCol = false, nil, nil, nil, false, nil
	L.windW, L.windT = nil, nil -- (SP.windRects: made again from this layout)
	-- Unfolded (a near-square screen, either way up), playing: two blocks in the bottom corners, one under each thumb,
	-- the game between them (Kailil, 2026-11-15, of the unfolded Fold7: "the bottom dock in both vertical and horizontal
	-- is entirely too large. The footprint is too large, can you make it smaller and split with no map in the middle.
	-- Split so the right and left thumb can easily reach the buttons ... the amount of buttons seen on the dock should
	-- never be less buttons than when phone is unfolded and vertical"). The same blocks both ways up, so the same buttons:
	-- left, metal and energy over the build grid (4 x 3); right, the selection over the orders (2 wide). Both as tall; the
	-- groups between them at the bottom (Kailil, the same day, of the groups row across the bottom: "this bottom bar is
	-- entirely wasted space ... maybe it can sit in the middle, separating the left and right"); over the groups the gap
	-- is the dock's hole (L.hole, RtsTouch's "map" and "gap"): the game's. Spectating keeps the full-width dock (its six
	-- narrow columns).
	local short = min(vsx, vsy)
	L.split = max(vsx, vsy) < short * 1.5 and not SP.on()
	if L.split then
		local pad = max(4, floor(short * 0.008))
		local gap = max(3, floor(pad * 0.6))
		local tile = floor(short * 0.075)
		local w = 4 * tile + 3 * gap
		-- (the groups as tall as a build tile, their top level with the grid's bottom row: Kailil, 2026-11-15, of the
		-- groups between the blocks, "should be taller", a red line at that row's top; the panel's rim reaches a pad out)
		local resH, selH, groupsH = floor(short * 0.036), floor(short * 0.06), tile - pad
		local gridH = 3 * tile + 2 * gap
		local h = pad + gridH + pad + resH + pad
		local bw = w + 2 * pad -- (a block, its pads in)
		L.splitL, L.splitR = { 0, 0, bw, h }, { vsx - bw, 0, vsx, h }
		L.dock = { 0, 0, vsx, h }
		L.groups = { bw + pad, pad, vsx - bw - pad, pad + groupsH } -- (between the blocks, at the bottom)
		-- (the gap's foot over the groups and the wind and tide boxes on them, SP.windRects: Kailil, 2026-11-16, "Move the
		-- widgets to be on top of the idle unit or unit group bar when in unfolded")
		L.hole = { bw, 3 * pad + groupsH + max(10, floor(resH * 0.9)), vsx - bw, h }
		L.pad, L.gap, L.tile, L.leftRows, L.leftCols = pad, gap, tile, 3, 4
		L.left = { pad, pad, pad + w, pad + gridH }
		L.res = { pad, h - pad - resH, pad + w, h - pad }
		local x0, x1, y0, y1 = vsx - bw + pad, vsx - pad, pad, h - pad
		L.sel = { x0, y1 - selH, x1, y1 }
		if showSel then
			y1 = y1 - selH - pad
		end
		L.right = { x0, y0, x1, y1 } -- (the orders, and with nothing picked the home buttons: homeRect)
		L.btnW = floor((w - gap) / 2)
		-- (the orders' rows by the height under the selection row, picked or not: by the block's whole height with
		-- nothing picked, a MULTI list's tiles changed size as its first type was tapped, review 2026-11-15)
		local yr = h - pad - selH - pad
		L.rightRows = max(3, floor((yr - y0 + gap) / (floor(tile * 0.62) + gap)))
		L.btnH = floor((yr - y0 + gap) / L.rightRows) - gap
		if L.dgun then -- (the D-gun mode: its sticks and FIRE in the two corners over the game, as sideways; no hole)
			L.dgFloat, L.hole = true, nil
		end
		SP.laidOut = false
		return
	end
	if L.land and not L.dgun then
		-- Sideways, one thumb (Kailil, 2026-11-12: "keep the bottom ui two slots only ... snapped to the left side or right
		-- side of the bottom of the phone so it can be used by one finger only. Add a button or symbol to swap what side";
		-- nothing picked: "Only have the map show"; of the choices, a HOME button on the map and BUILD | ORDERS tabs): at
		-- the pinned side's edge the map slot (metal and energy, BAR's minimap, the groups; HOME and the swap button
		-- beside the minimap), the panel beside it (the tabs, the selection, the tab's buttons); the rest of the bottom is
		-- the game's. Nothing picked: the map slot alone, a tap on it opens the home buttons in the panel (refresh). The
		-- D-gun mode keeps the band below (its sticks under both thumbs).
		local pad = max(4, floor(vsy * 0.012))
		local gap = max(3, floor(pad * 0.6))
		local bandH = floor(vsy * 0.4)
		local inner = bandH - 2 * pad
		local resH = floor(inner * 0.15)
		local groupsH = floor(inner * 0.2)
		local mapH = inner - resH - groupsH - 2 * gap
		local colW = floor(mapH * 0.5)
		local mapW = min(floor(mapH * (Game.mapSizeX / max(1, Game.mapSizeZ))), floor(vsx * 0.3))
		local slotW = max(floor(vsx * 0.2), colW + gap + mapW)
		local panelW = min(floor(vsx * 0.36), vsx - slotW - 3 * pad)
		-- (the panel at the edge, the map slot beside it, where it stays while the panel is closed: at the edge BAR's
		-- minimap lay under BAR's player list, clock and music lines, which BAR stacks up from the bottom right corner and
		-- no widget can move; the panel covers them. The thumb's buttons the nearest, the dock not jumping about)
		local right = L.side ~= "left"
		local P = right and { vsx - pad - panelW, pad, vsx - pad, bandH - pad } or { pad, pad, pad + panelW, bandH - pad }
		local M = right and { P[1] - pad - slotW, pad, P[1] - pad, bandH - pad }
			or { P[3] + pad, pad, P[3] + pad + slotW, bandH - pad }
		L.res = { M[1], M[4] - resH, M[3], M[4] }
		L.groups = { M[1], M[2], M[3], M[2] + groupsH }
		local my0, my1 = L.groups[4] + gap, L.res[2] - gap
		-- (the wind and the tide over the swap button, on the panel's side of the minimap, where HOME was: Kailil,
		-- 2026-11-16, "When in landscape folded, Replace the home button with the water tidal widget and wind speed stuff";
		-- the home buttons still show with nothing picked, SP.windRects)
		local col = right and { M[3] - colW, my0, M[3], my1 } or { M[1], my0, M[1] + colW, my1 }
		local cmid = floor((my0 + my1) / 2)
		L.windCol = { col[1], cmid + floor(gap / 2), col[3], col[4] }
		L.swapBtn = { col[1], col[2], col[3], cmid - floor(gap / 2) }
		local ax0, ax1 = right and M[1] or col[3] + gap, right and col[1] - gap or M[3]
		local mw = min(ax1 - ax0, mapW)
		local hx0 = floor((ax0 + ax1 - mw) / 2)
		L.hole = { hx0, my0, hx0 + mw, my1 }
		local top = P[4]
		if L.tabsOn then
			local tabH = floor(inner * 0.14)
			local mx = floor((P[1] + P[3]) / 2)
			L.tabs = { left = { P[1], top - tabH, mx - floor(gap / 2), top }, right = { mx + floor(gap / 2), top - tabH, P[3], top } }
			top = top - tabH - gap
		end
		local selH = min(floor(inner * 0.24), floor(panelW / 6.5))
		L.sel = { P[1], top - selH, P[3], top }
		if showSel then
			top = top - selH - pad
		end
		local gridH = top - P[2]
		local tile = floor((gridH - gap) / 2)
		-- (up to 7: at 6 the dev phone's panel had a seventh tile's width blank at its end, the "more" arrow off the
		-- tiles' middle)
		L.leftCols = max(3, min(7, floor((panelW + gap) / (tile + gap))))
		tile = min(tile, floor((panelW - (L.leftCols - 1) * gap) / L.leftCols))
		L.rightCols = panelW >= 3 * tile and 3 or 2
		local rows = max(2, floor((gridH + gap) / (tile + gap)))
		L.pad, L.gap, L.tile, L.leftRows = pad, gap, tile, rows
		L.left = { P[1], top - (rows * (tile + gap) - gap), P[3], top }
		L.right = { P[1], P[2], P[3], top }
		L.btnW = floor((panelW - (L.rightCols - 1) * gap) / L.rightCols)
		L.rightRows = max(3, floor((gridH + gap) / (floor(tile * 0.5) + gap)))
		L.btnH = floor((gridH + gap) / L.rightRows) - gap
		-- the tab not shown, and the whole panel while it is closed: off the screen (not drawn; no press, and no finger
		-- through RtsTouch's rects, finds it)
		local away = -4 * vsx
		local function off(r)
			return { r[1] + away, r[2], r[3] + away, r[4] }
		end
		if not L.panelOn then
			L.left, L.right, L.sel = off(L.left), off(L.right), off(L.sel)
		elseif L.tab == "right" then
			L.left = off(L.left)
		else
			L.right = off(L.right)
		end
		local x0, x1 = M[1], M[3]
		if L.panelOn then
			x0, x1 = min(x0, P[1]), max(x1, P[3])
		end
		L.dock = { x0 - pad, 0, x1 + pad, bandH }
		L.thumb = true
		SP.laidOut = false
		return
	end
	if L.land then
		-- Sideways (layout A): a band along the bottom, 0.4 of the height. Left: the selection over the build grid (2 rows
		-- of tiles, as many columns as fit); middle: metal and energy, the minimap (the map's shape), the groups; right:
		-- the orders (their whole height, 3 wide where there is room). The middle as wide as the minimap and a fifth of
		-- the width at least; the halves take the rest.
		local pad = max(4, floor(vsy * 0.012))
		local gap = max(3, floor(pad * 0.6))
		local bandH = floor(vsy * 0.4)
		local inner = bandH - 2 * pad
		local mid0 = max(floor(vsx * 0.2), floor(inner * 0.6)) -- (about the middle's width, for the halves' share)
		-- (at 0.2 of the height its name and INSERT were half the upright size; no taller than a sixth and a half of its
		-- width, the upright row's shape: on the unfolded Fold7's narrow halves the name ran into QUEUE)
		local selH = min(floor(inner * 0.26), floor((vsx - mid0 - 4 * pad) / 2 / 6.5))
		local gridH = inner - selH - pad
		local tile = floor((gridH - gap) / 2)
		local resH = floor(inner * 0.15)
		local groupsH = floor(inner * 0.2)
		local mapH = inner - resH - groupsH - 2 * gap
		local mapW = floor(mapH * (Game.mapSizeX / max(1, Game.mapSizeZ)))
		local midW = max(floor(vsx * 0.2), min(mapW, floor(vsx * 0.34)))
		local sideW = floor((vsx - midW - 4 * pad) / 2)
		L.leftCols = max(3, min(7, floor((sideW + gap) / (tile + gap))))
		tile = min(tile, floor((sideW - (L.leftCols - 1) * gap) / L.leftCols))
		L.rightCols = sideW >= 3 * tile and 3 or 2
		-- (whole rows only, under the selection: tiles narrowed by the width left a part of a third row in sight on the
		-- unfolded Fold7, "Do not allow scroll to half reveal objects")
		local rows = max(2, floor((gridH + gap) / (tile + gap)))
		L.pad, L.gap, L.tile, L.leftRows = pad, gap, tile, rows
		L.left = { pad, pad + gridH - (rows * (tile + gap) - gap), pad + sideW, pad + gridH }
		L.sel = { pad, pad + gridH + pad, pad + sideW, bandH - pad }
		L.right = { vsx - pad - sideW, pad, vsx - pad, bandH - pad }
		local mx0, mx1 = L.left[3] + pad, L.right[1] - pad
		L.res = { mx0, bandH - pad - resH, mx1, bandH - pad }
		L.groups = { mx0, pad, mx1, pad + groupsH }
		local hx0, hy0, hx1, hy1 = mx0, L.groups[4] + gap, mx1, L.res[2] - gap
		mapW = min(hx1 - hx0, mapW) -- (the map's shape, in the middle of its room)
		hx0 = floor((hx0 + hx1 - mapW) / 2)
		L.hole = { hx0, hy0, hx0 + mapW, hy1 }
		L.dock = { 0, 0, vsx, bandH }
		-- the D-gun mode sideways floats over the game (Kailil, 2026-11-13: "Don't do the half screen ui for the dgun
		-- mode. Instead do floating buttons with fire on both sides and remove the map. So there will be no Grey ui bottom
		-- half"): no band, no minimap; its sticks, a FIRE beside each and the cancel X drawn on the game (dgunParts). The
		-- band's place stays the mode's for the fingers (RtsTouch: the sticks, FIRE, X, elsewhere zoom or turn)
		if L.dgun then
			L.dgFloat, L.hole = true, nil
		end
		L.btnW = floor((sideW - (L.rightCols - 1) * gap) / L.rightCols)
		L.rightRows = max(3, floor((inner + gap) / (floor(tile * 0.5) + gap)))
		L.btnH = floor((inner + gap) / L.rightRows) - gap
		SP.laidOut = false
		return
	end
	-- A near-square screen (the unfolded Fold7 upright, 1080x1198) keeps the dock to 0.32 of its height (Kailil,
	-- 2026-11-15, his screenshot with a red line a third of the way up: "The bottom ui takes up FARRRRRR TOo much screen
	-- real-estate ... The max it shoukd come up is the red line I drew. Smaller would be better"; it was 0.54, DOCK_MAX):
	-- its rows and gaps by the height, the build grid's tiles as small as two rows need and as many across as fill the
	-- half. Tall phones keep the width's sizes.
	local square = vsy < vsx * 1.5
	local pad = square and max(4, floor(vsy * 0.008)) or max(4, floor(vsx * 0.012))
	local gap = max(3, floor(pad * 0.6))
	-- (by the width, and by the height on a near-square screen: the unfolded Fold7 upright, 1080x1198, gave a quarter
	-- of its short dock to these rows and the build grid small tiles beside a blank strip; tall phones keep the width's)
	local selH = square and floor(vsy * 0.06) or floor(min(vsx * 0.15, vsy * 0.09))
	local groupsH = square and floor(vsy * 0.05) or floor(min(vsx * 0.13, vsy * 0.075))
	local half = floor(vsx * 0.5)
	local tile = floor((half - pad - floor(pad / 2) - 2 * gap) / 3)
	local room = floor(vsy * (square and 0.32 or DOCK_MAX)) - (pad * 4 + selH + groupsH) -- the grid's height at most
	local rows = max(2, min(4, floor((room + gap) / (tile + gap))))
	if rows * (tile + gap) - gap > room then -- (2 rows that do not fit: smaller tiles)
		tile = max(16, floor((room + gap) / rows) - gap)
	end
	local resH = square and floor(vsy * 0.032) or floor(min(vsx * 0.06, vsy * 0.04))
	room = room - resH - pad
	rows = max(2, min(4, floor((room + gap) / (tile + gap))))
	if rows * (tile + gap) - gap > room then
		tile = max(16, floor((room + gap) / rows) - gap)
	end
	if square then -- (the smaller tiles across the whole half: 3 of them left most of it blank)
		local halfW = half - pad - floor(pad / 2)
		L.leftCols = max(3, min(6, floor((halfW + gap) / (tile + gap) + 0.5)))
		tile = min(tile, floor((halfW - (L.leftCols - 1) * gap) / L.leftCols))
	end
	local gridH = rows * (tile + gap) - gap
	SP.laidOut = SP.on() and true or false
	if SP.laidOut then -- (spectating: no selection or groups rows; their room to the grid, up to five button rows as tall
		-- as the build tiles: on the unfolded Fold7 the spectator's five rows were 62 pixels, dev phone at 1080x1198)
		gridH = max(gridH, min(5 * (tile + gap) - gap, room + selH + groupsH + 2 * pad))
	end
	if square and (L.dgun or not showSel) then -- (without the selection row, nothing picked or the D-gun mode, the grid
		-- takes its room: in the 0.32 dock's grid height the D-gun's sticks were 90 pixels and its X 34, the home buttons'
		-- 4 rows 37, small for a thumb, dev phone at 1080x1198; now 56, and the dock all but still as a pick comes and goes
		-- (0.31 to 0.32; a box drag's filters page between them had made it jump)
		gridH = max(gridH, floor(vsy * 0.2))
	end
	-- the build grid's tiles: in that taller grid (pregame's) whole rows filling it, as many across as fill the half (two
	-- rows of the short grid's tiles left the top of a third in sight under them, "Do not allow scroll to half reveal
	-- objects"; dev phone at 1080x1198); the order buttons keep the short grid's rows (tile, below)
	local leftTile, leftRows = tile, rows
	if square and leftRows * (tile + gap) - gap < gridH - floor(tile / 3) then
		leftRows = max(2, floor((gridH + gap) / (tile + gap) + 0.5))
		leftTile = floor((gridH + gap) / leftRows) - gap
		local halfW = half - pad - floor(pad / 2)
		L.leftCols = max(3, min(6, floor((halfW + gap) / (leftTile + gap) + 0.5)))
		leftTile = min(leftTile, floor((halfW - (L.leftCols - 1) * gap) / L.leftCols))
	end
	L.pad, L.gap, L.tile, L.leftRows = pad, gap, leftTile, leftRows
	-- From the bottom: the groups (with groups, or units picked for + NEW), the grid, the selection (units picked),
	-- metal and energy. A row not shown takes no room: the dock is that much lower and the game taller (Kailil,
	-- 2026-11-09: "Remove the no units pick bar ... It should just not be there"); the grid keeps its size.
	local y = pad
	L.groups = { pad, y, vsx - pad, y + groupsH }
	if showGroups then
		y = y + groupsH + pad
	end
	L.left = { pad, y, half - floor(pad / 2), y + gridH }
	L.right = { half + floor(pad / 2), y, vsx - pad, y + gridH }
	y = y + gridH + pad
	L.sel = { pad, y, vsx - pad, y + selH }
	if showSel then
		y = y + selH + pad
	end
	-- metal and energy, at the dock's top (BAR's top bar keeps its wind, units and buttons; its two resource bars are
	-- off while the dock is up: about 1600 pixels wide at a readable size, they ran over its buttons upright)
	L.res = { pad, y, vsx - pad, y + resH }
	L.dock = { 0, 0, vsx, y + resH + pad }
	-- order buttons: 2 wide, rows of about 0.42 of a tile in the same height
	local rw = L.right[3] - L.right[1]
	L.btnW = floor((rw - gap) / 2)
	L.rightRows = max(3, floor((gridH + gap) / (floor(tile * 0.55) + gap))) -- (about 6 mm tall on a phone: thumbs)
	L.btnH = floor((gridH + gap) / L.rightRows) - gap
	-- HIDE (spectating): the dock folded to a SHOW button at the bottom's middle, the game on the whole screen
	if SP.hidden then
		local bw, bh = floor(vsx * 0.28), max(floor(vsy * 0.042), resH + 2 * pad)
		L.dock = { floor((vsx - bw) / 2), pad, floor((vsx + bw) / 2), pad + bh }
	end
end

---------------------------------------------------------------------------------------------------------------------
-- RtsTouch's side: the dock's rects and mode (X screen pixels, top left origin), written when they change and every
-- second (RtsTouch takes a file older than 5 s for no dock)

local dockWritten, dockWrittenAt = nil, -10
local dgunLines -- (the D-gun mode's parts for RtsTouch, below)
local function writeDock(force)
	local text
	-- (aside for one of BAR's windows: no dock for RtsTouch, SP.windowOpen; and under BAR's lobby over the game, which
	-- covers it: there a drag on the lobby's lists was the camera pad's and panned the game behind it, SP.lobbyOver)
	if active and not L.aside and not SP.lobbyOver then
		local function r(x)
			return string.format("%d %d %d %d", x[1], vsy - x[4], x[3], vsy - x[2])
		end
		local _, cmd, cmdType = spGetActiveCommand()
		-- (a one-finger drag draws a path only with MOVE, FIGHT, PATROL or ATTACK pressed; with units merely picked it
		-- pans, their path a press held, then a drag: RtsTouch's long press, BAR's right button. Kailil, 2026-11-13, asked
		-- whether a drag with units picked should pan too: "Pan, hold for paths". Before: picked units without a building
		-- queued drew a path, 2026-11-11's "very easy to place a move path ... on accident due to the muscle memory of
		-- grabbing the screen". A preset armed: taps only, a drag pans, Kailil 2026-11-13: "make presets a single tap only")
		-- (an area order armed, SP.AREA_TYPES: 2, a left drag that draws its circle; 3 for an area-only one, ICON_AREA,
		-- Area Mex: a tap on the map waits for a drag, its click alone would use the order up at a point; Kailil,
		-- 2026-11-17, tap then drag drew Repair's and Restore's circles but not Area Mex's)
		local draw = DRAW_CMDS[cmd] and 1 or cmd and SP.AREA_TYPES[cmdType]
			and (CMDTYPE and cmdType == CMDTYPE.ICON_AREA and 3 or 2) or 0
		-- (folded, HIDE: the SHOW button alone, a camera pad whose tap brings the dock back, act dock_menu)
		local lr = SP.hidden and L.dock
		text = string.format("dock %s %s\nleft %s\nright %s\nselect %s\ndraw %d\n", r(SP.dockAll()), menu and "menu" or "pad",
			r(lr or L.left), r(lr or L.right), selStyle, draw)
			.. (showGroups and not SP.hidden and ("groups " .. r(L.groups) .. "\n") or "")
			.. (L.hole and ("map " .. r(L.hole) .. "\n") or "") -- (sideways: BAR's minimap, its touches the engine's)
			-- (unfolded: the game between the two blocks; a drag ending there keeps its point, RtsTouch.aboveDock)
			.. (L.split and L.hole and ("gap " .. r(L.hole) .. "\n") or "")
			-- (the build options, a builder's or a factory's, shown: their first tap acts, the camera pad or not; Kailil,
			-- 2026-11-12, "The build menus and factory build menus should all have this no tap required")
			-- (and the unit lists' types, ALL / MULTI first, and a pick's types: as the home grid's LOCAL and ALL UNITS that
			-- open them; MULTI's tap only opened the menu, dev phone 2026-11-13)
			.. ((leftKind == "build" or leftKind == "quick" or leftKind == "pregame" or leftKind == "seltypes"
				or tostring(leftKind):sub(1, 6) == "types:") and L.left[3] > 0 and not SP.hidden
				and ("live " .. r(L.left) .. "\n") or "")
			-- (and the orders, a factory's queue buttons too: Kailil, 2026-11-13, asked whether FIGHT, MOVE, PATROL,
			-- D-Gun and the states should act on the first tap as well: "1", yes; D-Gun's first tap only opened the menu)
			-- (and before the start, UNDO LAST, CLEAR QUEUE, the factions and PING: the same)
			.. ((rightKind == "orders" or rightKind == "factory" or rightKind == "pregame") and L.right[3] > 0
				and not SP.hidden
				and ("live " .. r(L.right) .. "\n") or "")
			-- (and the selection row: INSERT and QUEUE. Kailil, 2026-11-12, a Bot Lab: "Insert plus tapoing a unit to build.
			-- Is not interrupting the build queue": with the camera pad up INSERT's tap only opened the menu, and the unit's
			-- tap, which acts at once, went to the queue's end)
			.. (showSel and not SP.hidden and leftKind ~= "spec" and L.sel and L.sel[3] > L.sel[1]
				and ("live " .. r(L.sel) .. "\n") or "")
			-- (and the home grid, nothing picked: Kailil, 2026-11-12, "make rhe commander button. All units and local
			-- units buttins not need the ui one tap engage. Allow me to be able to directly click them"; sideways in the
			-- panel, which is always open now. Spectating its grid too, PLAYER CAM, TEAMS, FOLLOW UNIT...: Kailil,
			-- 2026-11-17, "Yes, first tap"; a drag starting on it still pans, as the open menu's drags do)
			.. (rightKind == "home" and not SP.hidden and (not L.thumb or L.panelOn)
				and ("live " .. r(SP.homeLive()) .. "\n") or "")
			-- (and the groups row: the unit groups and the idle builders, the same "directly click them")
			.. (showGroups and not SP.hidden and L.groups and L.groups[3] > L.groups[1]
				and ("live " .. r(L.groups) .. "\n") or "")
			-- (and metal and energy: their panel on the first tap, as the launcher's words say; with the camera pad up the
			-- tap only opened the menu, a second one the panel, dev phone 2026-11-13; spectating they open nothing)
			.. (leftKind ~= "spec" and not SP.hidden and L.res and L.res[3] > L.res[1]
				and ("live " .. r(L.res) .. "\n") or "")
			-- (sideways, one thumb: the BUILD | ORDERS tabs; HOME opens with the menu's first tap anyway)
			.. (L.thumb and L.tabsOn and L.tabs and L.tabs.left and L.tabs.right and not SP.hidden
				and ("live " .. r(L.tabs.left) .. "\nlive " .. r(L.tabs.right) .. "\n") or "")
			-- (and the swap arrow: its first tap moves the dock; with the camera pad up it only opened the menu, dev
			-- phone 2026-11-13)
			.. (L.thumb and L.swapBtn and not SP.hidden and ("live " .. r(L.swapBtn) .. "\n") or "")
			-- (and HOME: with the camera pad up its first tap only opened the menu, on the orders of the units still picked;
			-- review 2026-11-16)
			.. (L.thumb and L.homeBtn and not SP.hidden and ("live " .. r(L.homeBtn) .. "\n") or "")
			-- (and the wind's and the tide's boxes: their details at once, SP.drawWindInfo)
			.. SP.windLive(r)
			-- (PING on the home grid and before the start: held, a spoken ping; tapped twice, CHAT; pingT)
			.. ((rightKind == "home" or rightKind == "pregame") and leftKind ~= "spec" and L.pingBtn and not SP.hidden
				and (not L.thumb or L.panelOn or rightKind == "pregame")
				and ("ping " .. r(L.pingBtn) .. "\n") or "")
			.. (dgunLines and dgunLines() or "")
			.. SP.backLine() -- (Android's Back at home: BAR's way out, RtsTouch.back)
	else
		text = "dock none\n"
	end
	local t = now()
	if text == dockWritten and not force and (not active or t - dockWrittenAt < 1) then
		return
	end
	local tmp = DOCK_FILE .. ".tmp"
	local f = io.open(tmp, "w")
	if f then
		f:write(text)
		f:close()
		os.rename(tmp, DOCK_FILE)
	end
	dockWritten, dockWrittenAt = text, t
end

local function setMenu(on)
	if on == menu then
		if on then
			touched()
		end
		return
	end
	menu = on
	if on then
		menuAt = now()
		touched()
	else -- (sideways, one thumb: HOME's panel closes with the menu, the map slot alone again)
		L.homeOpen = false
	end
	writeDock(true)
end

-- the menu held open, no clock: placing (Kailil, 2026-11-12: "When in build place mode, dont let the bottom ui half
-- time out. So it will always accept touch": a building picked, or about to be picked again after PLACE or ONE, the
-- build menu copy's fourth answer: in those frames the dock showed the orders and its 2.6 s ran out), and picking
function SP.held()
	if rightKind == "place" or rightKind == "presets" or rightKind == "share" or rightKind == "panel"
		or (leftKind == "spec" and SP.teams) then
		return true
	end
	if SP.pingBusy and SP.pingBusy() then -- (PING armed, SPEAK or CHAT: sideways HOME's panel closed with the clock,
		-- TAP MAP and its words gone from sight, dev phone 2026-11-12)
		return true
	end
	local B = WG.bardroidBuildmenu
	if B and B.droidPlace then
		local armed, _, _, again = B.droidPlace()
		return (armed or again) and true or false
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- What the halves hold

-- BAR's own words for a command, as its order menu shows them ("commands.<action>" or "commands.<state>"), else nil
local trCache = {}
local function tr(key)
	if trCache[key] == nil then
		local ok, s = pcall(function()
			return BAR and BAR.I18N and BAR.I18N(key)
		end)
		trCache[key] = (ok and type(s) == "string" and s ~= "" and s ~= key and not s:find("commands.", 1, true)) and s or false
	end
	return trCache[key] or nil
end

local function cmdLabel(cmd)
	if cmd.type == CMDTYPE.ICON_MODE and cmd.params and #cmd.params > 1 then
		local state = tonumber(cmd.params[1]) or 0
		local name = cmd.params[state + 2] or cmd.name
		return tr("commands." .. tostring(name)) or name, state, #cmd.params - 1
	end
	return tr("commands." .. tostring(cmd.action)) or cmd.name
end

-- BAR's order menu's filter (gui_ordermenu.lua, as bardroid_pad.lua's orderCommands): BAR marks every command hidden
-- (the engine's own panel), so "hidden" says nothing; these are the ones its menu leaves out
local HIDDEN = {
	[CMD.LOAD_ONTO] = true, [CMD.SELFD] = true, [CMD.GATHERWAIT] = true, [CMD.SQUADWAIT] = true,
	[CMD.DEATHWAIT] = true, [CMD.TIMEWAIT] = true, [CMD.AUTOREPAIRLEVEL] = true, [39812] = true, [34922] = true,
	[34924] = true, -- (cancel target: only with a priority target; left out here)
}
local HIDDEN_TYPE = { [CMDTYPE.CUSTOM] = true, [CMDTYPE.PREV] = true, [CMDTYPE.NEXT] = true }

-- the selection's build options (builders, factories) and its orders in the order menu's order (states, Wait, the
-- rest), from the engine's own list
-- The engine's command list read again only when it says it changed (widget:CommandsChanged: a pick, a state toggled, a
-- factory's queue) or after a second, else the last read's items in new lists (refreshNow adds to them): read four times
-- a second, its copy of every command was ~50 kB of tables each time, three quarters of the dock's garbage in an idle
-- skirmish (dev phone; release overhaul item 7, 2026-11-21)
SP.cmds = { at = -10, stale = true }
local function readCommands()
	local c = SP.cmds
	local t = now()
	if not c.stale and c.builds and t - c.at < 1 then
		local b, s = {}, {}
		for i = 1, #c.builds do
			b[i] = c.builds[i]
		end
		for i = 1, #c.states do
			local it = c.states[i]
			it.w, it.h = nil, nil -- (as a fresh read's: refreshNow sizes the big orders again)
			s[i] = it
		end
		return b, s
	end
	local builds, states = SP.readCommandsNow()
	-- (an empty list stays stale: right after a pick the engine's list is empty for a frame until it is made again,
	-- refreshNow; small to read again)
	c.builds, c.states, c.at, c.stale = builds, states, t, #builds == 0 and #states == 0
	local b, s = {}, {}
	for i = 1, #builds do
		b[i] = builds[i]
	end
	for i = 1, #states do
		s[i] = states[i]
	end
	return b, s
end
function SP.readCommandsNow()
	local builds, states, others, wait = {}, {}, {}, nil
	for _, cmd in ipairs(spGetActiveCmdDescs() or {}) do
		if type(cmd) == "table" and cmd.action and not cmd.disabled and not HIDDEN[cmd.id] and not HIDDEN_TYPE[cmd.type] then
			if cmd.action:find("buildunit_", 1, true) == 1 then
				builds[#builds + 1] = { kind = "build", id = cmd.id, defID = -cmd.id,
					queued = tonumber(cmd.params and cmd.params[1]) }
			elseif cmd.type ~= CMDTYPE.ICON_BUILDING then
				local label, state, count = cmdLabel(cmd)
				local item = { kind = "order", id = cmd.id, label = label, state = state, states = count }
				if cmd.type == CMDTYPE.ICON_MODE then
					states[#states + 1] = item
				elseif cmd.id == CMD.WAIT then
					wait = item
				else
					others[#others + 1] = item
				end
			end
		end
	end
	if wait then
		states[#states + 1] = wait
	end
	for _, item in ipairs(others) do
		states[#states + 1] = item
	end
	return builds, states
end

local function selectedFactory()
	for defID in pairs(spGetSelectedUnitsCounts() or {}) do
		local ud = defID ~= "n" and UnitDefs[defID]
		if ud and ud.isFactory then
			return true
		end
	end
	return false
end

-- the unit filters (Kailil: "like the controller mod Hold A and hold x menu to select builders, combat, air, etc.")
local function builder(ud)
	return ud and ud.isBuilder and not ud.isFactory and ud.canMove
end
local function flying(ud)
	return ud and ud.canFly
end
local function naval(ud)
	return ud and ud.canMove and (ud.minWaterDepth or 0) > 0 and not ud.canFly
end
-- combat units: they move, carry a weapon, build nothing and do not fly
local function combat(ud)
	return ud and ud.canMove and not ud.isBuilder and not ud.isFactory and not ud.canFly and ud.weapons and #ud.weapons > 0
end
local FILTERS = {
	{ key = "all", label = "ALL" },
	{ key = "builders", label = "BUILDERS", test = builder },
	{ key = "combat", label = "COMBAT", test = combat },
	{ key = "air", label = "AIR", test = flying },
	{ key = "naval", label = "NAVAL", test = naval },
}

-- the units by type: { defID, units = {...} }, the biggest groups first
local function byType(units, filter)
	local t, list = {}, {}
	for _, u in ipairs(units or {}) do
		local d = Spring.GetUnitDefID(u)
		if d and (not filter or filter(UnitDefs[d])) then
			if not t[d] then
				t[d] = { kind = "type", defID = d, units = {} }
				list[#list + 1] = t[d]
			end
			local g = t[d].units
			g[#g + 1] = u
		end
	end
	table.sort(list, function(a, b)
		return #a.units > #b.units or (#a.units == #b.units and a.defID < b.defID)
	end)
	return list
end

-- my commanders, or (kind "factories") my finished factories, oldest first (COMMANDER and FACTORIES cycle through them)
local function myCommanders(kind)
	local out = {}
	for _, u in ipairs(Spring.GetTeamUnits(myTeam()) or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
		if ud and (kind == "factories" and ud.isFactory and not select(3, Spring.GetUnitIsStunned(u))
			or kind ~= "factories" and ud.customParams and ud.customParams.iscommander) then
			out[#out + 1] = u
		end
	end
	return out
end

-- Nothing picked, the split dock's empty left block (the unfolded Fold7): the build grid of the builder last picked alone,
-- else the commander, dimmed; its tap picks that builder and its building at once (Kailil, 2026-11-16, of the empty block
-- circled in a screenshot: "lets try 2", build without picking first). In the order its own grid had when it was last
-- picked (refreshNow keeps it), else its UnitDef's.
function SP.quickBuilds()
	if not (L.split and active) or Spring.GetSpectatingState() then
		return {}
	end
	local u = SP.lastBuilder
	if not (u and Spring.ValidUnitID(u) and not Spring.GetUnitIsDead(u) and Spring.GetUnitTeam(u) == myTeam()) then
		u = myCommanders("commander")[1]
	end
	local d = u and Spring.GetUnitDefID(u)
	local ud = d and UnitDefs[d]
	if not ud then
		return {}
	end
	local items = {}
	for _, b in ipairs(SP.lastBuilds and SP.lastBuilds[d] or ud.buildOptions or {}) do
		items[#items + 1] = { kind = "quickbuild", id = -b, defID = b, unit = u }
	end
	return items
end

-- The camera on a point of the map, the point in the middle of the game above the dock: the engine's camera target is
-- the screen's middle, which upright is the dock's top edge (a unit jumped to sat half under it). The shift is where the
-- two middles' rays meet the point's height now (a plane: the ground's ray missed over the void past the map's edge).
-- cam: where the camera will be ({ x, y, z }, its heading as now), else where it is.
local function planeAt(sx, sy, h, cam)
	local px, py, pz
	if cam then
		px, py, pz = cam[1], cam[2], cam[3]
	else
		px, py, pz = Spring.GetCameraPosition()
	end
	local dx, dy, dz = Spring.GetPixelDir(sx, vsy - sy) -- (its y from the top, as the engine's mouse; ours from the bottom)
	if not (px and dx) or dy > -1e-4 then
		return nil
	end
	local t = (h - py) / dy
	return px + dx * t, pz + dz * t
end
-- The view above the dock kept on the map where it fits (upright, a commander by the map's edge left almost half of it
-- on the empty void past the edge; dev phone, 2026-11-09): the point moved just enough for the view's corners to stay
-- inside the edges, and the view centred along a side where it is longer than the map
local function keepOnMap(x, z, h, cam)
	local ox, oz = planeAt(floor(vsx / 2), floor((L.dock[4] + vsy) / 2), h, cam)
	if not ox then
		return x, z
	end
	local x0, x1, z0, z1 = 0, 0, 0, 0
	for _, c in ipairs({ { 0, L.dock[4] }, { vsx - 1, L.dock[4] }, { 0, vsy - 1 }, { vsx - 1, vsy - 1 } }) do
		local px, pz = planeAt(c[1], c[2], h, cam)
		if not px then
			return x, z -- (a corner past the horizon: a tilted camera, left as it is)
		end
		x0, x1 = min(x0, px - ox), max(x1, px - ox)
		z0, z1 = min(z0, pz - oz), max(z1, pz - oz)
	end
	local function fit(v, lo, hi, size)
		if hi - lo >= size then
			return (size - lo - hi) / 2
		end
		return max(-lo, min(size - hi, v))
	end
	local nx, nz = fit(x, x0, x1, Game.mapSizeX), fit(z, z0, z1, Game.mapSizeZ)
	-- but never so far that the point leaves the middle half of the view: a tilted camera's far half covers a long way,
	-- and the whole move put a commander by the edge out of sight (2490 elmos). The middle half's corners on the ground,
	-- from the view's middle; after a part t of the move the point is -t times the move from that middle.
	local band = (vsy - L.dock[4]) * 0.25
	local quad = {}
	for _, c in ipairs({ { 0.2, L.dock[4] + band }, { 0.8, L.dock[4] + band }, { 0.8, vsy - band }, { 0.2, vsy - band } }) do
		local px, pz = planeAt(floor(vsx * c[1]), floor(c[2]), h, cam)
		if not px then
			return x, z
		end
		quad[#quad + 1] = { px - ox, pz - oz }
	end
	local function inMiddle(t)
		local dx, dz = -t * (nx - x), -t * (nz - z)
		local side = 0
		for i = 1, 4 do
			local a, b = quad[i], quad[i % 4 + 1]
			local cross = (b[1] - a[1]) * (dz - a[2]) - (b[2] - a[2]) * (dx - a[1])
			local s = cross > 0 and 1 or (cross < 0 and -1 or 0)
			if s ~= 0 then
				if side == 0 then
					side = s
				elseif s ~= side then
					return false
				end
			end
		end
		return true
	end
	if not inMiddle(1) then
		local lo, hi = 0, 1
		for _ = 1, 10 do
			local t = (lo + hi) / 2
			if inMiddle(t) then
				lo = t
			else
				hi = t
			end
		end
		nx, nz = x + lo * (nx - x), z + lo * (nz - z)
	end
	return nx, nz
end

-- COMMANDER and BASE's zoom (Kailil, 2026-11-10: "a comfortable level where the icon is not visible and the full 3d model
-- is shown"): the camera this far from the point, and always well under the height where units are drawn as icons
-- (the engine's: 750^0.5 x UnitIconDist over the map, by height when UseDistToGroundForIcons; 3900 by BAR's settings)
local COMFORT_DIST = 1300
local function comfortDist()
	local icon = 750 ^ 0.5 * (Spring.GetConfigFloat("UnitIconDist", 200) or 200)
	local k = Spring.GetConfigFloat("UseDistToGroundForIcons", 0) or 0
	if k > 0 then
		icon = icon / math.sqrt(k)
	end
	return max(400, min(COMFORT_DIST, icon * 0.8))
end

local function cameraTo(x, y, z, zoom)
	-- with zoom, the camera's own state (BAR's spring camera): the new distance along its heading, the view measured
	-- from where the camera will be (zoom a number: that much further out than the comfortable distance)
	local s = zoom and Spring.GetCameraState()
	local cam
	if s and s.name == "spring" and (s.dist or 0) > 1 and s.px then
		local px, py, pz = Spring.GetCameraPosition()
		local k = comfortDist() * (type(zoom) == "number" and zoom or 1) / s.dist
		s.dist = s.dist * k
		cam = { x + (px - s.px) * k, y + (py - s.py) * k, z + (pz - s.pz) * k }
	else
		s = nil
	end
	x, z = keepOnMap(x, z, y, cam)
	local cx = floor(vsx / 2)
	local ax, az = planeAt(cx, floor(vsy / 2), y, cam)
	local bx, bz = planeAt(cx, floor((L.dock[4] + vsy) / 2), y, cam)
	if ax and bx then
		x, z = x + ax - bx, z + az - bz
	end
	if s then
		s.px, s.py, s.pz = x, Spring.GetGroundHeight(x, z) or y, z
		Spring.SetCameraState(s, 0.25)
	else
		Spring.SetCameraTarget(x, y, z, 0.25)
	end
end

-- The camera dragged from the dock's empty space (Kailil, 2026-11-10: "if I grab empty space in the ui and moved my
-- finger around, let that pan my camera"), as the camera pad drags it (RtsTouch's PAD_PAN_GAIN): the ground at the
-- middle of the game above the dock follows the finger's move (GL pixels, y up), a little more than it
local PAN_GAIN = 1.3
local function panBy(dx, dy)
	local s = Spring.GetCameraState()
	if not (s and s.px) or (dx == 0 and dy == 0) then
		return
	end
	local mx, my = floor(vsx / 2), floor((L.dock[4] + vsy) / 2)
	local ax, az = planeAt(mx, my, s.py or 0)
	local bx, bz = planeAt(mx + dx * PAN_GAIN, my + dy * PAN_GAIN, s.py or 0)
	if ax and bx then
		s.px, s.pz = s.px - (bx - ax), s.pz - (bz - az)
		Spring.SetCameraState(s, 0)
	end
end

-- The D-gun mode's camera (DG above): the commander kept in the middle of the game above the dock, caught up with in
-- FOLLOW seconds (smooth as it enters the mode and between the simulation's frames); the zoom and the turn stay the
-- player's (the dock's empty space), past the map's edge too
local DG = { stick = { 0, 0, 0, 0 } } -- the D-gun mode's (below): stick: lx, ly, rx, ry as RtsTouch sent them (the
-- knobs); slide: FIRE's swipe, 0..1 while held, nil after (slideOff: when it ended, slideLast: how far it had gone)

-- The camera distance that shows the D-gun's whole reach around the commander: its ring and a target at the ring's
-- edge (32 across, and a little more) inside the game above the dock with room to spare; upright the screen's width
-- decides (dev phone, 2026-11-10: at COMMANDER's distance the ring touched both sides and a target at its side was cut
-- off). On-screen sizes go as one over the distance, so the distance now times how far past the room it reaches.
function DG.fitDist(u, s)
	local D = WG.BarDroidPadDgun
	local range = D and D.range and D.range()
	local x, y, z = Spring.GetUnitPosition(u)
	if not (range and x and s and s.dist) then
		return nil
	end
	local ux, uy = Spring.WorldToScreenCoords(x, y, z)
	local r = range + 48
	local halfW, halfH = vsx / 2 - L.pad * 2, (vsy - L.dock[4]) / 2 - L.pad * 2
	local need = 0
	for i = 0, 15 do
		local a = i * math.pi / 8
		local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
		local sx, sy = Spring.WorldToScreenCoords(px, Spring.GetGroundHeight(px, pz) or y, pz)
		if sx and halfW > 0 and halfH > 0 then
			need = max(need, abs(sx - ux) / halfW, abs(sy - uy) / halfH)
		end
	end
	return need > 0 and s.dist * need or nil
end

function DG.follow(dt)
	local FOLLOW = 0.08
	local D = WG.BarDroidPadDgun
	local u = D and D.unit and D.unit()
	local x, y, z
	if u then
		x, y, z = Spring.GetUnitPosition(u)
	end
	local s = x and Spring.GetCameraState()
	if u ~= DG.unitWas then -- (the mode just entered: from far off, the camera eased in once to COMMANDER's distance,
		-- the D-gun's ring a speck at the start's 5000; dev phone, 2026-11-10; the zoom is the player's from there), and
		-- out as far as the D-gun's whole reach needs (fitDist)
		DG.unitWas, DG.zoomUntil = u, u and now() + 0.6 or nil
		local fit = u and DG.fitDist(u, s)
		DG.zoomTo = u and s and s.dist and s.dist > comfortDist() * 1.2 and max(comfortDist(), fit or 0) or nil
		if u and not DG.zoomTo and fit and s.dist < fit then
			DG.zoomTo = fit
		end
	end
	if not (s and s.px) then
		return
	end
	local zooming = DG.zoomTo and now() < DG.zoomUntil and s.dist
	if zooming then
		s.dist = s.dist + (DG.zoomTo - s.dist) * (1 - math.exp(-(dt or 0.033) / 0.12))
	end
	-- the ground at the middle of the game above the dock, at the commander's height: the camera moved by what is
	-- between them
	local bx, bz = planeAt(floor(vsx / 2), floor((L.dock[4] + vsy) / 2), y)
	if not bx then
		return
	end
	local tx, tz = s.px + x - bx, s.pz + z - bz
	local k = 1 - math.exp(-(dt or 0.033) / FOLLOW)
	local nx, nz = s.px + (tx - s.px) * k, s.pz + (tz - s.pz) * k
	if abs(nx - s.px) + abs(nz - s.pz) < 0.05 and not zooming then
		return
	end
	s.px, s.pz = nx, nz
	s.py = Spring.GetGroundHeight(nx, nz) or s.py
	Spring.SetCameraState(s, 0)
end

-- Once at the start, after the engine's own move to the start spot (a second): the start spot in the middle of the view
-- above the dock (the engine's middle is the dock's top edge: the commander sat on it), the view kept on the map
local startFitted = false
local function startFit()
	if startFitted then
		return
	end
	local f = Spring.GetGameFrame()
	if f < 40 then
		return
	end
	startFitted = true
	if f > 90 then
		return -- (the widget loaded mid-game: the camera is the player's)
	end
	local x, y, z = Spring.GetTeamStartPosition(myTeam())
	if x and (x > 0 or z > 0) then
		cameraTo(x, y, z)
		Spring.Echo("[bardroid-portrait] start view on the start spot")
	end
end

-- Pregame, once, a second into it: my team's start box in the middle of the view above the dock, the camera as far as
-- the box needs to fit across and above the dock (BAR's own start camera looked at the whole map from far off: upright,
-- two thirds of the screen were sky beyond the map's far edge, the start box small near the dock; dev phone, 2026-11-14,
-- a lobby skirmish on Avalanche). The camera is the player's after that.
SP.pregameFit = { wait = 0 }
function SP.pregameView(dt)
	local pf = SP.pregameFit
	if pf.done or Spring.GetGameFrame() > 0 or Spring.GetSpectatingState() then
		return
	end
	pf.wait = pf.wait + (dt or 0)
	if pf.wait < 1 then
		return
	end
	pf.done = true
	-- (only where the player picks a start spot in the box: with fixed or random start positions the "box" is the whole
	-- map, and the camera went to the map's size before the start view; dock-phone-test, 2026-11-14)
	if Game.startPosType ~= 2 then
		return
	end
	local x1, z1, x2, z2 = Spring.GetAllyTeamStartBox(Spring.GetMyAllyTeamID())
	if not (x1 and x2 and x2 > x1 and z2 > z1) then
		return
	end
	local w, h = x2 - x1, z2 - z1
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	-- (seen from straight above: the field's width at distance d is 2 d tan(hfov / 2), its depth above the dock that of
	-- the screen's lines above the dock; a tilted camera sees more ground in depth, so the box fits with room)
	local tv = math.tan(math.rad((Spring.GetCameraFOV and Spring.GetCameraFOV() or 45) / 2))
	local above = max(0.2, (vsy - L.dock[4]) / vsy)
	local d = max(w / (2 * tv * vsx / vsy), h / (2 * tv * above)) * 1.1
	local zoom = max(0.6, min(5, d / comfortDist()))
	cameraTo(cx, Spring.GetGroundHeight(cx, cz) or 0, cz, zoom)
	Spring.Echo(string.format("[bardroid-portrait] pregame view on the start box (%d x %d, zoom %.2f)", w, h, zoom))
end

-- BAR's faction picker (gui_factionpicker.lua) stands down for this game while the dock is up before the start: the
-- dock's ARMADA / CORTEX / RANDOM make the same choice, and BAR's panel sits by its order menu at the bottom, under the
-- dock (upright all of it; sideways half of it stuck out left of the dock, its buttons under the dock's minimap: dev
-- phone, 2026-11-14). Removed as BAR's picker removes itself when the game starts (for this game only, its order in
-- BYAR.lua untouched). Only a game widget has the widget handler for it (the phone engine; GetInfo's handler); as a
-- user widget, on BAR's official engine, BAR's picker stays.
function SP.factionPicker()
	if SP.pickerDone or Spring.GetGameFrame() > 0 then
		return
	end
	-- (looked up raw: a user widget's stand-in answers every member with a function that does nothing, and a warning;
	-- that one was called every frame before the start, dev phone 2026-11-18)
	local wh, get = widgetHandler, rawget
	if not (wh and get and get(wh, "FindWidget") and get(wh, "RemoveWidget")) then
		SP.pickerDone = true
		return
	end
	local w = wh:FindWidget("Factionpicker")
	if w then
		wh:RemoveWidget(w)
		SP.pickerDone, SP.pickerRemoved = true, true
		Spring.Echo("[bardroid-portrait] BAR's faction picker off for this game: the dock's factions")
	end
end
-- (back when the dock goes down before the start: turned sideways with no sideways dock, or the pad taken up, BAR's own
-- screen came back with no faction picker; removed again if the dock comes back up; review 2026-11-16)
function SP.factionPickerBack()
	if not SP.pickerRemoved or Spring.GetGameFrame() > 0 then
		return
	end
	local wh, get = widgetHandler, rawget
	if wh and get and get(wh, "EnableWidget") then
		wh:EnableWidget("Factionpicker")
		Spring.Echo("[bardroid-portrait] BAR's faction picker back: the dock is down before the start")
	end
	SP.pickerDone, SP.pickerRemoved = false, false
end

local function typesUnits()
	if typesFrom == "local" then -- (units drawn as icons too, as the pad's ON SCREEN: zoomed out, as sideways's start
		-- view is, the units on the screen are icons and LOCAL UNITS left them out)
		return Spring.GetVisibleUnits(myTeam(), nil, true)
	end
	return Spring.GetTeamUnits(myTeam())
end

local function activeBuild()
	local _, cmdID = spGetActiveCommand()
	return cmdID and cmdID < 0 and cmdID or nil
end

-- Before the game starts (an online game's start spot and first buildings): the start unit's build options, as BAR's
-- build menu shows them then, picked through BAR's own pregame queue widget (WG["pregame-build"], as that menu does).
-- The dock stood there with "No units picked" and nothing to queue. Its start unit, nil once the game runs
local function pregameStart()
	if Spring.GetGameFrame() > 0 or Spring.GetSpectatingState() then
		return nil
	end
	local pb = WG["pregame-build"]
	if not (pb and pb.setPreGamestartDefID and pb.getPreGameDefID and pb.getBuildQueue) then
		return nil
	end
	local d = Spring.GetTeamRulesParam(myTeam(), "startUnit")
	return d and UnitDefs[d] and d or nil -- (with no build options too: the faction buttons stay, to pick another)
end

local function pregameItems(startDefID)
	local queued = {}
	for _, b in ipairs(WG["pregame-build"].getBuildQueue() or {}) do
		if type(b) == "table" and type(b[1]) == "number" and b[1] > 0 then
			queued[b[1]] = (queued[b[1]] or 0) + 1
		end
	end
	local items = {}
	for _, d in ipairs(UnitDefs[startDefID].buildOptions or {}) do
		items[#items + 1] = { kind = "pregame", defID = d, queued = queued[d] }
	end
	return items
end

-- BAR's faction picker (gui_factionpicker.lua) sits at the bottom of the screen, under the dock upright: its factions
-- here as buttons, the same choice by the same message ("changeStartUnit", BAR's picker's own; validStartUnits, no
-- RANDOM when one real faction is left, none with one)
local FACTION_NAMES = { arm = "ARMADA", cor = "CORTEX", leg = "LEGION", dum = "RANDOM" }
local function pregameFactions()
	local valid = Spring.GetTeamRulesParam(myTeam(), "validStartUnits") or Spring.GetGameRulesParam("validStartUnits")
	local out = {}
	for s in tostring(valid or ""):gmatch("[^|]+") do
		local d = tonumber(s)
		local ud = d and UnitDefs[d]
		if ud then
			local p = ud.name:sub(1, 3)
			out[#out + 1] = { kind = "faction", startUnit = d, label = FACTION_NAMES[p] or p:upper(), random = p == "dum" }
		end
	end
	if #out == 2 then
		for i = #out, 1, -1 do
			if out[i].random then
				table.remove(out, i)
			end
		end
	end
	return #out > 1 and out or {}
end

-- the shapes in one row of four, PLACE two rows tall under them: sideways (one thumb), and upright where the half has
-- three rows only (the Fold7 unfolded: under two rows of shapes PLACE was one row, its ROTATE and X a thin strip,
-- dev phone at 1080x1198, 2026-11-12)
function SP.shapeRow()
	return L.thumb or (L.rightRows or 9) <= 3
end
local function placeShapes()
	return {
		{ kind = "shape", shape = "one", label = "ONE" }, { kind = "shape", shape = "line", label = "LINE" },
		{ kind = "shape", shape = "grid", label = "GRID" }, { kind = "shape", shape = "border", label = "BORDER" },
	}
end

-- Each item's cell in a half: its row and column and the columns and rows it spans (item.w, item.h, 1 by default),
-- packed in order, each at the first free place: FIGHT across both columns at twice the height, MOVE and PATROL
-- side by side as tall, then the rest (Kailil, 2026-11-09: "fight, and move and maybe patrol needs to be the largest
-- buttons in the orders ui"). Made with the items (refreshNow): cells, rows.
local function pack(items, cols)
	local cells, used, rows = {}, {}, 0
	local function free(r, c, w, h)
		for rr = r, r + h - 1 do
			for cc = c, c + w - 1 do
				if cc >= cols or used[rr * cols + cc] then
					return false
				end
			end
		end
		return true
	end
	local r, c = 0, 0
	for i, it in ipairs(items) do
		local w, h = min(cols, it.w or 1), it.h or 1
		while not free(r, c, w, h) do
			c = c + 1
			if c >= cols then
				c, r = 0, r + 1
			end
		end
		for rr = r, r + h - 1 do
			for cc = c, c + w - 1 do
				used[rr * cols + cc] = true
			end
		end
		cells[i] = { row = r, col = c, w = w, h = h }
		rows = max(rows, r + h)
	end
	return cells, rows
end
local cellsOf = { left = {}, right = {} }

-- The pad's D-gun mode (bardroid_pad.lua, v0.8.5's) on the dock (Kailil, 2026-11-09: "two joy sticks appear and a big
-- red fire button for the dgun. Then an in the corner ... to cancel the dgun control"): MOVE (left) walks the
-- commander, AIM (right) turns the shot, FIRE fires, the corner's cross leaves. RtsTouch reads them from the dock's
-- file (writeDock) and sends the sticks back (dgunsticks); the mode does the rest as with a pad.
-- Kailil, 2026-11-10: while it lasts "unit group selection and first and last row be hidden so the ui is shorter. And
-- hide the commander selected bar" (refreshNow: the dock's lower rows go and the game takes their room); "Have the camera
-- follow the commander and keep the commander in the center" (DG.follow: the middle of the game above the dock); "the
-- empty Gray space to let me zoom up and down. Or rotate. Not panning" (RtsTouch: a finger there, up or down zooms,
-- sideways turns); full auto "by holding fire button then swiping to the right" (RtsTouch's dgunslide lines: the track
-- beside FIRE fills, at its end "act dgun_auto"; FIRE again ends it; bardroid_pad.lua dgunAuto)
local function dgunOn()
	local D = WG.BarDroidPadDgun
	return D and D.active and D.active() or false
end

-- its parts in the grid: the sticks (x, y, radius), FIRE and the cancel corner (rects); GL pixels. Sideways, floating
-- (L.dgFloat): the sticks low in the bottom corners, under the thumbs, each with a FIRE on its inner side (fire:
-- the left one, fire2: the right one; either thumb fires), their swipes towards the middle; the X at the top left of
-- the band's place, away from the thumbs
local function dgunParts()
	if L.dgFloat then
		local d, pad, gap = L.dock, L.pad, L.gap
		local h = d[4] - d[2]
		local words = floor(L.btnH * 0.6)
		local rad = floor(min(h * 0.33, vsx * 0.1))
		local cy = d[2] + pad + words + rad
		local cxL, cxR = floor(vsx * 0.13), vsx - floor(vsx * 0.13)
		local fw, fh = floor(rad * 1.5), floor(rad * 0.95)
		local fy0 = cy - floor(fh / 2) -- (level with the sticks' middles: a third of its height above them, from when
		-- MOVE and AIM were printed under the sticks, it stood off them, dev phone screenshot 2026-11-13)
		-- (the X by the band's height too: by the width alone it was 53 pixels on the unfolded Fold7's narrow screen)
		local c = floor(min(h * 0.2, max(vsx * 0.045, h * 0.17)))
		return { l = { cxL, cy, rad }, r = { cxR, cy, rad }, float = true,
			fire = { cxL + rad + gap * 3, fy0, cxL + rad + gap * 3 + fw, fy0 + fh },
			fire2 = { cxR - rad - gap * 3 - fw, fy0, cxR - rad - gap * 3, fy0 + fh },
			cancel = { d[1] + pad, d[4] - pad - c, d[1] + pad + c, d[4] - pad } }
	end
	-- (sideways: the band's whole height, the right half's; the left's foot is up by its whole rows)
	local r = { L.left[1], L.land and L.right[2] or L.left[2], L.right[3], L.right[4] }
	local w, h = r[3] - r[1], r[4] - r[2]
	-- the sticks between their words (MOVE, AIM: under them) and FIRE's foot (on the near-square screen, the Fold7
	-- unfolded upright, a stick sized by the height alone reached the grid's foot and its word fell off the screen)
	local words = floor(L.btnH * 0.6)
	local room = floor(h * 0.74) - L.gap - words
	local rad = floor(min(w * 0.2, room * 0.5))
	local cy = r[2] + words + floor(room / 2)
	local fire = { r[1] + floor(w * 0.3), r[2] + floor(h * 0.74), r[3] - floor(w * 0.3), r[4] - L.gap }
	-- (the X's top on FIRE's: at the band's own top it stood a gap above FIRE, dev phone screenshot 2026-11-17)
	local c = floor(min(w * 0.13, h * 0.2))
	return { l = { r[1] + floor(w * 0.24), cy, rad }, r = { r[3] - floor(w * 0.24), cy, rad }, fire = fire,
		cancel = { r[1], fire[4] - c, r[1] + c, fire[4] } }
end

-- (X pixels, top left origin, as the dock's other lines)
dgunLines = function()
	if rightKind ~= "dgun" then
		return ""
	end
	local p = dgunParts()
	local function rect(x)
		return string.format("%d %d %d %d", x[1], vsy - x[4], x[3], vsy - x[2])
	end
	-- (dgunauto: full auto on, FIRE's swipe goes left to end it)
	local D = WG.BarDroidPadDgun
	local auto = D and D.auto and D.auto()
	-- (fire2: floating sideways, the second FIRE; with it each FIRE's swipe goes towards the middle, on or off)
	return string.format("dgun 1\nstickl %d %d %d\nstickr %d %d %d\nfire %s\ncancel %s\ndgunauto %d\n", p.l[1], vsy - p.l[2],
		p.l[3], p.r[1], vsy - p.r[2], p.r[3], rect(p.fire), rect(p.cancel), auto and 1 or 0)
		.. (p.fire2 and ("fire2 " .. rect(p.fire2) .. "\n") or "")
end

local function teammateList()
	local P = WG.BarDroidPad
	return P and P.teammates and P.teammates() or {}
end

-- the teammate picker: amounts (resources), the teammates in their colours, CANCEL
local function shareItems()
	local items = {}
	if sharing ~= "units" then
		for _, f in ipairs({ 0.1, 0.25, 0.5, 1 }) do
			items[#items + 1] = { kind = "sharestep", value = f, label = floor(f * 100) .. "%" }
		end
	end
	local teams = teammateList()
	for _, t in ipairs(teams) do
		items[#items + 1] = { kind = "shareto", teamID = t.teamID, label = string.upper(t.name), color = t.color, w = 2 }
	end
	if #teams == 0 then
		items[#items + 1] = { kind = "none", label = "NO TEAMMATES", w = 2 }
	end
	items[#items + 1] = { kind = "sharecancel", label = "CANCEL", w = 2 }
	return items
end

-- the resource panel: BAR's top bar's resource bar, SEND, CLOSE. One bar as BAR's (Kailil, 2026-11-17, of the share
-- slider: "Make this bar relative. And make it have the same look as the actual power yellow bar and red line as the
-- share value. And have the mex conversion Grey bar be on it too. It shoukd look vanilla"): the storage's fill in BAR's
-- colours, the share knob (red) on it and on energy's the conversion knob (pale) too; it was a red fill up to the share
-- level, conversion a second slider of its own (SP.drawResBar)
local function panelItems(res)
	local items = {}
	items[#items + 1] = { kind = "slider", res = res, w = 2 }
	if #teammateList() > 0 then
		items[#items + 1] = { kind = "sendres", res = res, label = res == "metal" and "SEND METAL" or "SEND ENERGY", w = 2 }
	end
	items[#items + 1] = { kind = "panelclose", label = "CLOSE", w = 2 }
	return items
end

-- what: "share" or "convert" (energy's conversion)
local function sliderValue(item, what)
	local v
	if what == "convert" then
		v = Spring.GetTeamRulesParam(myTeam(), "mmLevel") or 0.75
	else
		v = select(6, Spring.GetTeamResources(myTeam(), item.res)) or 1
	end
	-- (the value the finger set, until the game's own comes back to it: online the knob and its words ran a round
	-- trip behind the finger and jumped back at the release; BAR's top bar draws its dragged value too)
	local key = item.res .. what
	local set = SP.slidSet and SP.slidSet[key]
	if set then
		if abs(v - set.v) < 0.006 or now() - set.t > 3 then
			SP.slidSet[key] = nil
		else
			return set.v
		end
	end
	return v
end

-- a knob set from x along its bar (BAR's own calls: SetShareLevel; conversion, its LuaRules message 12-88 %), in whole
-- percents and only when that changed: every finger move had sent it again, to every player online (review
-- 2026-11-17: 32-36 values a 1.5 s drag on the dev phone, the share's unrounded)
local function setSlider(item, r, x, what)
	local b = SP.barArea(r)
	local v = max(0, min(1, (x - b[1]) / max(1, b[3] - b[1])))
	v = (what == "convert" and max(12, min(88, floor(v * 100 + 0.5))) or floor(v * 100 + 0.5)) / 100
	SP.slidSet = SP.slidSet or {}
	SP.slidSet[item.res .. what] = { v = v, t = now() }
	if slide and slide.sent == v then
		return
	end
	if slide then
		slide.sent = v
	end
	if what == "convert" then
		Spring.SendLuaRulesMsg(string.format(string.char(137) .. "%i", floor(v * 100 + 0.5)))
	else
		Spring.SetShareLevel(item.res, v)
	end
	markDirty()
end

-- The idle builders in the groups row (Kailil, 2026-11-11: "Add an idle builders grid icon into the unit groups row ...
-- stack builders of the same type and let me cycle through them like vanilla behavior. It should display the number of
-- how many are idle of that unit type"; IDLE UNITS and IDLE BUILDER left the home grid): BAR's Idle Builders' units
-- (gui_idle_builders.lua: build power and something to build or assist; a factory with an empty queue), by type. A tap
-- picks the nearest one not picked yet, from where the view was as the round began, round them all, and the camera
-- goes to it. (One table: the main chunk is at Lua's 200 locals.)
-- The home grid's PINGS (Kailil, 2026-11-11): its left half the camera to the last 4 pings from others (the pad's list,
-- RB + D-pad up's cycle), its right half a ping of your own where the map is tapped next (armed for PING_ARM seconds)
local pingT = { armedAt = nil, rect = nil, pressX = nil, eat = false, drawn = nil, ARM = 10, KEPT = 4 }
function pingT.armed() -- (and while PING held listens for its label: the map's tap is its spot)
	local v = pingT.voice
	return pingT.armedAt ~= nil and now() - pingT.armedAt < pingT.ARM
		or v ~= nil and v.endedAt == nil and not v.cancelled
end
-- PING let go (tapped again, LAST PINGS, units picked): its words said already go with it, and a session still listening
-- is marked so its words, when they come, are swallowed (dropped, they went to the pad's ping at its aim); before, a
-- label outlived the arm and came back on a later plain ping, and a ping let go while its words were spoken dropped
-- anyway (review 2026-11-15)
function pingT.cancel()
	local v = pingT.voice
	pingT.voice = v and not v.endedAt and { at = v.at, cancelled = true } or nil
	pingT.armedAt, pingT.label = nil, nil
end
function pingT.look()
	local Pd = WG.BarDroidPad
	if Pd and Pd.pingLook then
		Pd.pingLook(pingT.KEPT)
	end
end
-- (how many pings from others wait, in gold at LAST PINGS' top right as the idle builders' counts: it said nothing of
-- whether there was one to see)
-- (red while the newest is an attack on my units still going, bardroid_pad.lua's ATTACK: the danger waits there)
function pingT.badge(r, n, attack)
	if n > 0 and bold then
		local h = r[4] - r[2]
		bold:Print((attack and "\255\255\090\070" or "\255\255\200\064") .. n, r[3] - max(4, h * 0.08), r[4] - h * 0.3,
			h * 0.24, "ro")
	end
end
function pingT.state() -- (what the tile shows: "LAST PINGS" or "PING 2 OF 4", PING lit while armed; the newest an attack)
	local Pd = WG.BarDroidPad
	local n, step, attack = 0, 0, false
	if Pd and Pd.pingCount then
		n, step, attack = Pd.pingCount()
	end
	return min(n, pingT.KEPT), step, pingT.armed(), attack
end
-- PING beside its own tap (Kailil, 2026-11-12): held (RtsTouch "dock_voiceping"), what is said labels the ping the map's
-- next tap drops, "as the vanilla game ... send a ping with words" (pingT.voice while listening, with its spot when the
-- map was tapped meanwhile; pingT.label once said); tapped twice ("dock_chat"), CHAT: speak to chat, the button flips to
-- CHAT with a gold burst, "a sleak pop animation that fits the tone of the game", and back to PING the same way when
-- the chat is sent or let go (pingT.chat: its start, its end)
pingT.FLIP, pingT.GROW, pingT.BURST = 0.12, 0.24, 0.5 -- seconds: the old word squashes away, the new one pops in
function pingT.ease(p) -- (ease out with an overshoot: the pop)
	local c1 = 1.70158
	return 1 + (c1 + 1) * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
end
-- the flip's state at an age: the height (0..~1.1), whether the new word shows, the burst's progress (nil: none)
function pingT.flip(age)
	if age < pingT.FLIP then
		return math.cos(age / pingT.FLIP * math.pi / 2), false, nil
	end
	local p = min(1, (age - pingT.FLIP) / pingT.GROW)
	local burst = age - pingT.FLIP < pingT.BURST and (age - pingT.FLIP) / pingT.BURST or nil
	return pingT.ease(p), true, burst
end
function SP.pingBusy() -- (SP.held: the menu stays open while PING waits for the map, listens, or is CHAT)
	return pingT.armed() or pingT.chat ~= nil
end
-- the app's lines for PING: its hold and double tap, and VoiceChat's state ("act voice_on", "voice_off", ...)
function pingT.act(name)
	local t, c, v = now(), pingT.chat, pingT.voice
	if name == "dock_chat" then
		pingT.armedAt, pingT.voice, pingT.label = nil, nil, nil
		pingT.chat = { at = t }
	elseif name == "dock_voiceping" then
		pingT.chat = nil
		pingT.voice, pingT.label, pingT.armedAt = { at = t }, nil, t
	elseif name == "voice_on" and c then
		c.on = true
	elseif name == "voice_off" or name == "voice_none" or name == "voice_nomic" or name == "voice_nonet" then
		if c and not c.endAt then
			c.endAt = t
		end
		if v and not v.endedAt then -- (a session let go meanwhile too: VoiceChat's end comes before its words, which it
			-- still swallows until update lets it go, 1.5 s on)
			v.endedAt = t
		end
	else
		return
	end
	markDirty()
end
-- each frame: the flips drawn as they go, a chat that never began let go, a spoken ping with no words after the
-- listening ended: dropped where the map was tapped, plain (else PING stays armed for a tap)
function pingT.update()
	local t, c, v = now(), pingT.chat, pingT.voice
	if c then
		if c.endAt and t - c.endAt > pingT.FLIP + pingT.BURST then
			pingT.chat = nil
		elseif not c.endAt and (not c.on and t - c.at > 8 or t - c.at > 60) then -- (a minute at most: a session's end
			-- lost meanwhile left CHAT on and the menu open)
			c.endAt = t
		end
		-- (the flip and the burst frame by frame, CHAT's glow 8 times a second: each mark redraws the whole dock's
		-- texture, 1 to 2 ms, and it ran every frame of a chat up to a minute long; review 2026-11-16)
		local step = math.floor(t * 8)
		if t - (c.endAt or c.at) < pingT.FLIP + pingT.BURST or step ~= c.glowStep then
			c.glowStep = step
			markDirty()
		end
	end
	if pingT.label and not pingT.armed() then -- (the words said for a ping go when its arm runs out)
		pingT.label = nil
		markDirty()
	end
	if v then
		if v.endedAt and t - v.endedAt > 1.5 or t - v.at > 40 then
			pingT.voice = nil
			if v.spot and not v.cancelled then
				Spring.MarkerAddPoint(v.spot[1], v.spot[2], v.spot[3], "")
				pingT.armedAt = nil
			end
			markDirty()
		end
	end
end
-- the words said for a ping (bardroid_touch.lua): taken when PING was held for them; with the spot already tapped the
-- ping drops there now, else PING waits for the map's tap with them (BAR's 127 bytes at most, whole letters)
function pingT.voicePing(text)
	local v = pingT.voice
	if not (v and now() - v.at < 40) then
		return false
	end
	if v.cancelled then -- (PING let go while they were spoken: swallowed, not the pad's ping either)
		pingT.voice = nil
		markDirty()
		return true
	end
	text = text:gsub("%s+", " "):gsub("^ ", "")
	if #text > 127 then
		local after = text:byte(128)
		text = text:sub(1, 127)
		if after >= 128 and after < 192 then
			text = text:gsub("[\192-\255][\128-\191]*$", "")
		end
	end
	pingT.voice = nil
	if v.spot then
		Spring.MarkerAddPoint(v.spot[1], v.spot[2], v.spot[3], text)
		Spring.Echo("[bardroid-portrait] a spoken ping at " .. floor(v.spot[1]) .. " " .. floor(v.spot[3])) -- (tools)
		pingT.armedAt = nil
	else
		pingT.label, pingT.armedAt = text:find("%S") and text or nil, now()
	end
	markDirty()
	return true
end
function idleB.update()
	local t = now()
	if t - idleB.at < 0.5 then
		return
	end
	idleB.at = t
	if not idleB.defs then
		idleB.defs = {}
		for id, ud in pairs(UnitDefs) do
			local cp = ud.customParams or {}
			if cp.virtualunit ~= "1" and (ud.buildSpeed or 0) > 0 and not ud.name:find("spy") and not ud.name:find("infestor")
				and (ud.canAssist or (ud.buildOptions and ud.buildOptions[1])) and not cp.isairbase then
				idleB.defs[#idleB.defs + 1] = id
				idleB.fac[id] = ud.isFactory and true or false
			end
		end
	end
	local byDef, list = {}, {}
	if not Spring.GetSpectatingState() then
		for _, u in ipairs(Spring.GetTeamUnitsByDefs(myTeam(), idleB.defs) or {}) do
			local d = Spring.GetUnitDefID(u)
			local n = idleB.fac[d] and Spring.GetFactoryCommandCount(u) or Spring.GetUnitCommandCount(u)
			if (n or 0) == 0 and not Spring.GetUnitIsBeingBuilt(u) then
				if not byDef[d] then
					byDef[d] = {}
					list[#list + 1] = { def = d, units = byDef[d] }
				end
				byDef[d][#byDef[d] + 1] = u
			end
		end
	end
	table.sort(list, function(a, b)
		return a.def < b.def
	end)
	local sig = {}
	for i, e in ipairs(list) do
		sig[i] = e.def .. "x" .. #e.units
	end
	sig = table.concat(sig, " ")
	idleB.list = list
	if sig ~= idleB.sig then -- (the row drawn again: its pictures and counts)
		idleB.sig = sig
		markDirty()
	end
end
function idleB.pick(def)
	local units
	for _, e in ipairs(idleB.list) do
		if e.def == def then
			units = e.units
		end
	end
	if not units or #units == 0 then
		return
	end
	local sel = spGetSelectedUnits() or {}
	if not (idleB.origin and #sel == 1 and sel[1] == idleB.last) then -- (a new round: from where the view is now)
		local _, pos = Spring.TraceScreenRay(floor(vsx / 2), floor((vsy + (L.dock and L.dock[4] or 0)) / 2), true)
		local cx, _, cz = Spring.GetCameraPosition()
		idleB.origin = pos and { pos[1], pos[3] } or { cx, cz }
		idleB.visited = {}
	end
	local visited = idleB.visited[def] or {}
	idleB.visited[def] = visited
	local function nearest()
		local best, bestD
		for _, u in ipairs(units) do
			local x, _, z = Spring.GetUnitPosition(u)
			if x and not visited[u] then
				local d = (x - idleB.origin[1]) ^ 2 + (z - idleB.origin[2]) ^ 2
				if not bestD or d < bestD then
					best, bestD = u, d
				end
			end
		end
		return best
	end
	local u = nearest()
	if not u then -- (round them all: again from the nearest)
		for k in pairs(visited) do
			visited[k] = nil
		end
		u = nearest()
	end
	if not u then
		return
	end
	visited[u] = true
	idleB.last = u
	Spring.SelectUnitArray({ u })
	local x, y, z = Spring.GetUnitPosition(u)
	if x then
		-- (zoomed in as COMMANDER does, not only moved: Kailil, 2026-11-13, "When you select commander, or cycle to an
		-- idle builder, it should zoom you into that unit as well ... the same zoom level pressing the commander button is")
		cameraTo(x, y, z, 1.3)
	end
end

-- The profile (springsettings bardroid_portrait_profile = 1, widget:DrawScreen): the refreshes and their time, the
-- dock's drawing time and frames since the last line. (One table: the file's main chunk was at Lua's 200 locals.)
local PROF = { on = Spring.GetConfigInt("bardroid_portrait_profile", 0) == 1, refreshN = 0, refreshMs = 0, sum = 0,
	n = 0, at = 0, texN = 0, texMs = 0 }

-- what each half shows, refreshed a few times a second and after every press
local refreshNow
local function refresh()
	local t0 = spGetTimer()
	refreshNow()
	PROF.refreshN, PROF.refreshMs = PROF.refreshN + 1, PROF.refreshMs + spDiffTimers(spGetTimer(), t0) * 1000
end
function refreshNow()
	local sel = spGetSelectedUnits() or {}
	local builds, orders = readCommands()
	if #sel == 1 and #builds > 0 then -- (a builder picked alone: its grid kept for nothing picked, SP.quickBuilds)
		local d = Spring.GetUnitDefID(sel[1])
		if d and builder(UnitDefs[d]) then
			local list = {}
			for i, b in ipairs(builds) do
				list[i] = b.defID
			end
			SP.lastBuilder, SP.lastBuilds = sel[1], SP.lastBuilds or {}
			SP.lastBuilds[d] = list
		end
	end
	-- (units picked and no command at all: the engine's list for a frame after a press or a pick, before it is made
	-- again; taken as it was, it threw the build menu back to its first rows after each factory press)
	if #sel > 0 and #builds == 0 and #orders == 0 and not typesFrom and not selecting then
		return
	end
	local anyGroup = false
	for _, c in pairs(Spring.GetGroupList() or {}) do
		if c > 0 then
			anyGroup = true
			break
		end
	end
	mobilePicked = false
	for d in pairs(spGetSelectedUnitsCounts() or {}) do
		local ud = type(d) == "number" and UnitDefs[d]
		if ud and ud.canMove and not ud.isFactory then
			mobilePicked = true
			break
		end
	end
	local dg = dgunOn() -- (the D-gun mode: neither row, a shorter dock)
	if dg ~= L.dgun then -- (sideways its sticks under both thumbs: the band across the bottom, layout)
		L.dgun = dg
		layout()
	end
	if #sel > 0 then -- (HOME's panel was for nothing picked)
		L.homeOpen = false
	end
	idleB.update()
	-- (the full-width upright dock, a game played and running: the groups row kept, empty or not. It came with the
	-- first idle builder or group and went with the last, and the grid over it rose and fell by its height, 132 pixels
	-- on the dev phone: a finger reaching for a home button hit the one below; attack-ping-test, 2026-11-20. The split
	-- dock has its groups between its blocks, the sideways one its own: they do not move)
	local keepGroups = not L.split and not L.thumb and Spring.GetGameFrame() > 0 and not Spring.GetSpectatingState()
	local wantSel, wantGroups = #sel > 0 and not dg, (#sel > 0 or anyGroup or #idleB.list > 0 or keepGroups) and not dg
	if wantSel ~= showSel or wantGroups ~= showGroups then -- (the dock's rows: laid out again)
		showSel, showGroups = wantSel, wantGroups
		layout()
	end
	-- (a factory picked: its build queue, what the buttons take from (removeOrder); with nothing queued they stood there
	-- doing nothing, dev phone 2026-11-13, a Bot Lab picked by FACTORIES. Other units: their orders)
	local unq = false
	local fac = #sel > 0 and selectedFactory()
	for i = 1, #sel do
		local n
		if fac then
			local ud = UnitDefs[Spring.GetUnitDefID(sel[i]) or -1]
			n = ud and ud.isFactory and Spring.GetFactoryCommands(sel[i], 0) or 0
		else
			n = Spring.GetUnitCommandCount(sel[i]) or 0
		end
		if (tonumber(n) or 0) > 0 then
			unq = true
			break
		end
	end
	if (unq == true) ~= unqShown then
		unqShown = unq == true
		markDirty()
	end
	local key = #sel .. ":" .. tostring(sel[1])
	local newPick = key ~= lastSelection -- (another pick: both halves from their first rows, not the last unit's place)
	if newPick then
		lastSelection, factoryItem = key, nil
		if sharing == "units" then -- (another pick: not what TRANSFER was pressed for)
			sharing = nil
		end
		if #sel > 0 and not multi and not keepTypes then
			typesFrom = nil
		end
		allPicked = allPicked and keepTypes
	end
	keepTypes = false
	if typesFrom and #sel == 0 and not multi then -- (the list's units all let go, ALL on: the home grid again; its LOCAL,
		-- ALL UNITS, MULTI and DONE half went, Kailil 2026-11-13: "Its redundant")
		typesFrom, allPicked = nil, false
	end
	local newLeft, newRight, lk, rk
	local pregame = #sel == 0 and not typesFrom and pregameStart()
	if pregame then
		newLeft, lk = pregameItems(pregame), "pregame"
	elseif typesFrom then -- LOCAL / ALL UNITS: the combat units by type, ALL first (IDLE: every idle unit)
		local types = byType(typesUnits(), combat)
		newLeft = { { kind = "alltypes", label = "ALL", count = 0 } }
		for _, g in ipairs(types) do
			newLeft[#newLeft + 1] = g
			g.out = SP.leftOut[g.defID] or nil -- (a type left out: dimmed, not in ALL's count)
			if not g.out then
				newLeft[1].count = newLeft[1].count + #g.units
			end
		end
		lk = "types:" .. typesFrom
	elseif #sel == 0 then -- (the split dock: a builder's grid, dimmed, SP.quickBuilds)
		newLeft = SP.quickBuilds()
		lk = #newLeft > 0 and "quick" or "none"
	elseif #builds > 0 then
		newLeft, lk = builds, "build"
	else -- units that build nothing: the selection by type (a tap keeps one type)
		newLeft, lk = byType(sel), "seltypes"
		for _, g in ipairs(newLeft) do
			g.kind = "seltype"
		end
	end
	local building = activeBuild()
	local style = { kind = "style", label = selStyle == "circle" and "SELECT: CIRCLE" or "SELECT: BOX" }
	if selecting then -- a selection being dragged: its filters (a second finger on the dock picks one)
		newRight = {}
		for _, f in ipairs(FILTERS) do
			newRight[#newRight + 1] = { kind = "filter", key = f.key, label = f.label }
		end
		rk = "filters"
	elseif pregame and WG["pregame-build"].getPreGameDefID() then -- a building picked: its shapes and PLACE, as in
		-- the game (the build menu copy places pregame buildings too: a map tap picks the spot, PLACE's Shift click
		-- adds it to BAR's queue)
		newRight, rk = placeShapes(), "place"
	elseif pregame then -- (the queue on the map, BAR's: its last one off, or all of it; the factions)
		newRight = { { kind = "pregameundo", label = "UNDO LAST" }, { kind = "pregameclear", label = "CLEAR QUEUE" } }
		for _, f in ipairs(pregameFactions()) do
			newRight[#newRight + 1] = f
		end
		-- (PING after them, as on the home grid's: tap, then the map; held, its words; tapped twice, CHAT. Kailil,
		-- 2026-11-13, a pregame screenshot, the place beside RANDOM: "Add ping here. So I can place pings and chat")
		newRight[#newRight + 1] = { kind = "pings", pingOnly = true }
		-- (two rows tall where all of them fit so: five short buttons over an empty half, dev phone 2026-11-13)
		-- (unfolded, the split dock: their rows fill the block instead, half())
		if not L.split and (L.rightRows or 3) >= 2 * math.ceil(#newRight / (L.rightCols or 2)) then
			for _, it in ipairs(newRight) do
				it.h = 2
			end
		end
		rk = "pregame"
	elseif typesFrom and #sel == 0 then -- MULTI on, no type tapped yet: nothing to order (with units picked, their orders
		-- as for any pick; Kailil, 2026-11-13: "Get rid of the right half of the page that has the all units, local units,
		-- and done. Its redundant")
		newRight, rk = {}, "none"
	elseif #sel == 0 then -- nothing picked: the home grid, big buttons across the dock (Kailil, 2026-11-09: the
		-- commander with the camera on it, the camera to the base; 2026-11-11: no IDLE UNITS or IDLE BUILDER, the idle
		-- builders are in the groups row, drawGroups)
		-- (IDLE BUILDER's place: PINGS, Kailil 2026-11-11 "a button to go to last 4 pings like we have on controller. And
		-- to set a ping"; IDLE UNITS' place: FACTORIES, Kailil 2026-11-12 "lets do FACTORIES for the button beside
		-- PINGS": the next factory picked, the camera on it, its build menu in the dock to queue units; dim with none)
		local hasFactory = false
		for d in pairs(Spring.GetTeamUnitsCounts(myTeam()) or {}) do
			local ud = type(d) == "number" and UnitDefs[d]
			if ud and ud.isFactory then
				hasFactory = true
				break
			end
		end
		newRight = {
			{ kind = "units", from = "local", label = "LOCAL UNITS" },
			{ kind = "units", from = "all", label = "ALL UNITS" },
			{ kind = "factories", label = "FACTORIES", dim = not hasFactory },
			{ kind = "pings" },
			{ kind = "commander", label = "COMMANDER" },
			{ kind = "base", label = "BASE" },
		}
		if WG.BarDroidRetreat then -- (across the dock under them: hurt units fall back, bardroid_retreat.lua; where the
			-- host forbids widgets' orders it cannot, and says so)
			local R = WG.BarDroidRetreat
			local allowed = not R.allowed or R.allowed()
			newRight[#newRight + 1] = { kind = "retreat", w = 2, on = allowed and R.on(),
				label = not allowed and "AUTO RETREAT: OFF IN THIS GAME" or R.on() and "AUTO RETREAT: ON"
					or "AUTO RETREAT: OFF" }
		end
		rk = "home"
	elseif building and not selectedFactory() then -- a building picked: its shapes, and PLACE under them (the build
		-- menu copy's panel, in placeRect: RtsTouch places from its rects, bardroid_place.txt)
		newRight, rk = placeShapes(), "place"
	elseif factoryItem then -- a factory's item pressed: its queue
		-- (two rows tall each, as the big orders: six buttons filled three short rows of the half; one row where pages
		-- of two-row pairs would be cut: an odd number of rows under six in sight)
		local rr = L.rightRows or 3
		-- (sideways three wide: two rows of them, double height where the half has the rows for it; they were two thin
		-- rows over an empty half, dev phone 2026-11-12, a Bot Lab)
		local need = math.ceil(6 / (L.rightCols or 2))
		-- (not in the split's four rows: two-row buttons there were six rows, four in sight, CLEAR and ORDERS a scroll
		-- away; one row each, all six in sight, as upright before the split; review 2026-11-16)
		local qh = (need * 2 <= rr or not L.split and (rr >= 6 or rr % 2 == 0)) and 2 or 1
		newRight = {
			{ kind = "queue", n = 1, label = "+1", h = qh }, { kind = "queue", n = 5, label = "+5", h = qh },
			{ kind = "queue", n = 20, label = "+20", h = qh }, { kind = "queue", n = -1, label = "-1", h = qh },
			{ kind = "clearitem", label = "CLEAR", h = qh }, { kind = "back", label = "ORDERS", h = qh },
		}
		rk = "factory"
	else -- (the box or circle and its filter after the orders: with units picked only, Kailil 2026-11-09)
		newRight, rk = orders, "orders"
		if mobilePicked or selectedFactory() then -- (units that move picked: FIGHT, MOVE, PATROL first and largest, pack)
			-- (and a commander's D-gun across after them: its touch sticks, k == "order" with CMD.MANUALFIRE; a factory's
			-- FIGHT, MOVE and PATROL are where its new units go, the same size, and its REPEAT across after them: Kailil,
			-- 2026-11-10, the factory's order menu "with the larger buttons arrangement too", the rest left to us)
			-- (two rows tall where the half shows four or more: three, the unfolded Fold7 upright, cut MOVE and PATROL
			-- through the middle at its foot, Kailil: "Do not allow scroll to half reveal objects"; one row then)
			-- (unfolded, the split dock's right block: one row, so its four rows show six orders, not three; Kailil,
			-- 2026-11-15, never fewer buttons than the unfolded upright dock showed)
			local bh = (L.rightRows or 3) >= 4 and not L.split and 2 or 1
			local big = { [CMD.FIGHT] = { 1, 2, bh }, [CMD.MOVE] = { 2, 1, bh }, [CMD.PATROL] = { 3, 1, bh },
				[CMD.MANUALFIRE] = { 4, 2, 1 } }
			if not mobilePicked then
				big[CMD.MANUALFIRE], big[CMD.REPEAT] = nil, { 4, 2, 1 }
			end
			local first, rest = {}, {}
			-- (PRESETS in MOVE's big place, MOVE among the small ones: Kailil, 2026-11-13, "Move is super redundant to have
			-- as a big button. Put presets in its place"; a long press, then a drag, moves anyway)
			if mobilePicked and WG.BarDroidPresets and WG.BarDroidPresets.fits(sel) then
				big[CMD.MOVE] = nil
				first[2] = { kind = "presets", label = "PRESETS", w = 1, h = bh }
			end
			for _, it in ipairs(orders) do
				local b = it.kind == "order" and big[it.id]
				if b then
					it.w, it.h = b[2], b[3]
					first[b[1]] = it
				else
					rest[#rest + 1] = it
				end
			end
			newRight = {}
			for i = 1, 4 do
				if first[i] then
					newRight[#newRight + 1] = first[i]
				end
			end
			for _, it in ipairs(rest) do
				newRight[#newRight + 1] = it
			end
		end
		if #teammateList() > 0 then -- (after FIGHT, MOVE, PATROL: the picked units to a teammate)
			local at = 1
			while newRight[at] and newRight[at].h do
				at = at + 1
			end
			table.insert(newRight, at, { kind = "transfer", label = "TRANSFER" })
		end
		local placed = false -- (PRESETS already in MOVE's big place, above)
		for _, it in ipairs(newRight) do
			placed = placed or it.kind == "presets"
		end
		if not placed and WG.BarDroidPresets and WG.BarDroidPresets.fits(sel) then -- (after the big ones: bardroid_presets.lua)
			local at = 1
			while newRight[at] and newRight[at].h do
				at = at + 1
			end
			-- (a factory with a preset: its name, its units joining that formation; bardroid_presets.lua factoryForms)
			local fp = #sel == 1 and WG.BarDroidPresets.factoryPreset and WG.BarDroidPresets.factoryPreset(sel[1])
			-- (a factory's as big as the units' PRESETS, one column and MOVE's height, after FIGHT, MOVE, PATROL and
			-- REPEAT, MOVE kept: Kailil, 2026-11-21, "Make the preset button for factories big")
			local big = fac and not mobilePicked
			table.insert(newRight, at, { kind = "presets", label = fp and ("PRESETS: " .. fp) or "PRESETS",
				w = big and 1 or nil, h = big and ((L.rightRows or 3) >= 4 and not L.split and 2 or 1) or nil })
		end
		newRight[#newRight + 1] = style
		newRight[#newRight + 1] = { kind = "filterpick", label = "FILTER: " .. selFilter:upper() }
	end
	if sharing or resPanel then -- (the picker or the panel: the whole grid)
		-- (the split dock: the left block keeps its own, the picker or panel in the right block, its place (homeRect); the
		-- left had stood empty beside it, dev phone at 1080x1198, 2026-11-17; a press there puts them away, MouseRelease)
		if not L.split then
			newLeft, lk = {}, sharing and "share" or "panel"
		end
		-- (with nothing picked the home grid stays under the panel, a drop-down over it: it took the whole dock, half of
		-- it empty below CLOSE; a press on one of them closes the panel)
		local home = not sharing and rk == "home" and newRight
		newRight, rk = sharing and shareItems() or panelItems(resPanel), sharing and "share" or "panel"
		for _, it in ipairs(home or {}) do
			it.home = true
			newRight[#newRight + 1] = it
		end
	end
	if WG.BarDroidPresets and WG.BarDroidPresets.isOpen() then -- (the presets: 2 x 2 over the whole grid, an X)
		if #sel > 0 then
			newLeft, lk, newRight, rk = {}, "presets", WG.BarDroidPresets.items(), "presets"
		else
			WG.BarDroidPresets.close()
		end
	end
	if dgunOn() then -- (the D-gun mode: its sticks, FIRE and cancel over the whole grid)
		newLeft, lk, newRight, rk = {}, "dgun", {}, "dgun"
	end
	if SP.on() then -- (spectating: the spectator's grid over the whole dock, SP.items; or TEAMS)
		newLeft, lk, newRight, rk = {}, "spec", SP.items(), "home"
	end
	-- A pick's few types on the left (units that build nothing, the unit lists): the orders past the right half's first
	-- page in the left half's empty place under the types, two wide, the same size; the right half as it always is
	-- (Kailil, 2026-11-13: "i want the orders that originally go on the right side to always stay there. so we can build
	-- muscle memory. only orders that arent seen on the first page without scrolling down, move over into the overflow
	-- left side of the UI"; first "orders allow more orders to fill the space"). More than that place holds: at the
	-- right's end, as before. Upright only (sideways the halves are tabs).
	-- (with orders spilling over, the types as tall as an order, more of them a row, and more rows of orders under them:
	-- Kailil, 2026-11-13, "shrink them to be as tall as the orders so two rows can fit under it instead of 1 row")
	SP.overRect, SP.overItems, SP.smallTypes = nil, {}, nil
	local listPage = lk:sub(1, 6) == "types:"
	if (rk == "orders" or listPage) and (not L.land or L.split) and not SP.on() and (lk == "seltypes" or listPage) then
		-- (as tall as FIGHT beside them, its rows' height: Kailil, 2026-11-13, "I meant, it match the size of the fight
		-- button"; the overflow then starts level with PRESETS)
		local fh = (L.rightRows or 3) >= 4 and not L.split and 2 or 1
		local ts = fh * L.btnH + (fh - 1) * L.gap
		local tcols = max(1, floor((L.left[3] - L.left[1] + L.gap) / (ts + L.gap)))
		local top = L.left[4] - math.ceil(#newLeft / tcols) * (ts + L.gap)
		local rows = floor((top - L.left[2] + L.gap) / (L.btnH + L.gap))
		-- (unfolded, the split dock: the types grown into what the whole order rows leave, so three rows of orders fill
		-- the block under one row of types; Kailil, 2026-11-15: the picked unit's picture "too big. There should be 3
		-- rows of orders with the selected units boxes above those. So the 3 order rows fit perfectly")
		if L.split and rows >= 1 then
			local typeRows = math.ceil(#newLeft / tcols)
			local grown = ts + floor(((L.left[4] - L.left[2] + L.gap) - (typeRows + rows) * (L.btnH + L.gap)) / max(1, typeRows))
			local gcols = max(1, floor((L.left[3] - L.left[1] + L.gap) / (grown + L.gap)))
			if math.ceil(#newLeft / gcols) == typeRows then
				ts, tcols = grown, gcols
				top = L.left[4] - typeRows * (ts + L.gap)
			end
		end
		-- (the unit lists keep the small tiles: MULTI lets everyone go, no orders, and the tiles grew back to their full
		-- size, then shrank again with the first type tapped: the next one moved from under the finger)
		if listPage and rows >= 1 then
			SP.smallTypes = { cols = tcols, size = ts }
		end
		if rows >= 1 and rk == "orders" then
			local cells = pack(newRight, L.rightCols or 2)
			local keep, past = {}, {}
			for i, it in ipairs(newRight) do
				local c = cells[i]
				if c.row + c.h <= (L.rightRows or 3) then
					keep[#keep + 1] = it
				else
					past[#past + 1] = it
				end
			end
			local oc = pack(past, 2)
			for i, it in ipairs(past) do
				if oc[i].row + oc[i].h <= rows then
					SP.overItems[#SP.overItems + 1] = it
				else
					keep[#keep + 1] = it
				end
			end
			if #SP.overItems > 0 then
				newRight = keep
				SP.overRect = { L.left[1], top - rows * (L.btnH + L.gap) + L.gap, L.left[3], top }
				SP.smallTypes = { cols = tcols, size = ts }
			end
		end
	end
	if L.land and not L.dgun and not L.split then -- sideways, one thumb: the panel, its tabs and the tab shown (layout)
		-- (nothing picked: the home buttons in the panel; both sides with something: BUILD | ORDERS tabs, a builder opening
		-- on its build options and other units on their orders, a building picked on PLACE; a tab tapped stays until what
		-- the dock shows changes)
		-- (the panel always open: with nothing picked it had closed to the map slot alone until HOME was tapped; Kailil,
		-- 2026-11-15, "remove the auto hide behavior in landscape where the byttobs that aren't the map auto hide and I
		-- have to press home to see them")
		local panelOn = true
		local tabsOn = panelOn and #newLeft > 0 and #newRight > 0
		local tab = L.tab
		if lk ~= leftKind or rk ~= rightKind or newPick then
			tab = (lk == "build" or lk == "pregame" or lk:sub(1, 6) == "types:") and rk ~= "place" and rk ~= "factory"
				and rk ~= "filters" and "left" or "right"
		end
		if not tabsOn then
			tab = #newLeft > 0 and "left" or "right"
		end
		if panelOn ~= L.panelOn or tabsOn ~= L.tabsOn or tab ~= L.tab then
			L.panelOn, L.tabsOn, L.tab = panelOn, tabsOn, tab
			layout()
		end
	end
	leftItems, rightItems = newLeft, newRight
	markDirty()
	local leftRowsN, rightRowsN
	cellsOf.left, leftRowsN = pack(leftItems, SP.smallTypes and SP.smallTypes.cols or L.leftCols or 3)
	cellsOf.over = pack(SP.overItems or {}, 2) -- (the overflow under a pick's types: never scrolls)
	SP.overScroll = SP.overScroll or snapNew()
	cellsOf.right, rightRowsN = pack(rightItems, lk == "spec" and SP.COLS
		or (rk == "home" or rk == "presets" or rk == "share" or rk == "panel") and 2 or (rk == "place" and SP.shapeRow()) and 4
		or L.rightCols or 2)
	SP.rightRowsN = rightRowsN -- (half: the pregame's rows filling the right)
	snapSet(leftScroll, leftRowsN, L.leftRows or 2, lk == leftKind and not newPick)
	-- (the share list's and a panel's rows in sight, from the place they are drawn, homeRect: the split dock's right
	-- block is not the left's height, a third row ran 20 pixels under it, review 2026-11-15)
	local wideRows = SP.wideRows()
	if lk == "spec" then -- (the spectator's 4 or 5 rows; TEAMS: as tall as those, 4 or 5 in sight, more scroll: always 5,
		-- a 1v1's three rows were small, the unfolded Fold7's 70 pixels)
		L.homeRows = SP.teams and max(4, min(5, rightRowsN)) or max(1, min(5, rightRowsN))
	elseif rk == "home" then -- (all of it on the dock: AUTO RETREAT a fourth row, no scrolling)
		L.homeRows = max(HOME_ROWS, min(HOME_ROWS + 1, rightRowsN))
	elseif rk == "presets" then -- (laid out as the home grid, 2 x 2)
		L.homeRows = 2
	end
	snapSet(rightScroll, rightRowsN, (rk == "home" or rk == "presets") and (L.homeRows or HOME_ROWS)
		or (rk == "share" or rk == "panel") and wideRows
		or L.rightRows or 3, rk == rightKind and not newPick)
	if lk ~= leftKind or rk ~= rightKind then
		Spring.Echo(string.format("[bardroid-portrait] %d picked: left %s (%d), right %s (%d)", #sel, lk, #leftItems, rk,
			#rightItems)) -- (tools: what the dock shows)
	end
	leftKind, rightKind = lk, rk
	if rk ~= "home" and rk ~= "pregame" and pingT.armed() then -- (PING armed, then units picked: the next map tap is
		-- theirs, not a ping; listening for its words too)
		pingT.cancel()
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Pressing

local function runCommand(id, right, shift, ctrl, alt)
	local index = spGetCmdDescIndex(id)
	if index then
		spSetActiveCommand(index, right and 3 or 1, not right, right or false, alt or false, ctrl or false, false, shift or false)
	end
end

local function selectUnits(units, append)
	Spring.SelectUnitArray(units or {}, append or false)
end

-- A factory's move state for its units (Kailil, 2026-11-10: "sets every unit that came out of the factory or that will
-- come out of the factory to the status I toggle it to. Tapping the button will cycle through the three states.
-- Stopping on a state for .3 seconds still initiate the selection"; and an air factory's fly / land for "all planes that
-- came out of the factory (except the builders)"). Units built later take the factory's state themselves (the engine's;
-- BAR's Factory hold position relies on it); those it built before get it once the factory's button has rested
-- fac.REST: the units each factory turned out are remembered (UnitFromFactory). (One table: the file's main chunk is at
-- Lua's 200 locals.)
local fac = {
	REST = 0.3,
	made = {}, -- factory unitID -> { unitID = true }
	pressed = nil, -- { cmd, give, at }: a factory's move state or fly / land pressed last, the order its units get
}
-- An air plant's fly / land is BAR's own button (gadget unit_air_plants, "apLandAt": 0 Fly, 1 Land), which hands its
-- state to new planes as CMD.IDLEMODE (0 fly, 1 land); the engine's IDLEMODE button is not on an air plant
function fac.isLandAt(id)
	for _, f in ipairs(spGetSelectedUnits() or {}) do
		for _, d in ipairs(Spring.GetUnitCmdDescs(f) or {}) do
			if d.id == id then
				return d.name == "apLandAt" or d.action == "apLandAt"
			end
		end
	end
	return false
end
local function factoryStates()
	local p = fac.pressed
	if not p or now() - p.at < fac.REST then -- (now(): seconds)
		return
	end
	fac.pressed = nil
	local total, label = 0, nil
	for _, f in ipairs(spGetSelectedUnits() or {}) do
		local fd = UnitDefs[Spring.GetUnitDefID(f) or -1]
		local made = fac.made[f]
		if fd and fd.isFactory and made then
			local state
			for _, d in ipairs(Spring.GetUnitCmdDescs(f) or {}) do
				if d.id == p.cmd and d.params and d.params[1] then
					state = tonumber(d.params[1])
					label = d.params[(state or 0) + 2] or label
				end
			end
			local units = {}
			for u in pairs(made) do
				local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
				if not ud or Spring.GetUnitTeam(u) ~= myTeam() then
					made[u] = nil -- (gone, or no longer this team's)
				elseif p.give ~= CMD.IDLEMODE or (ud.canFly and not ud.isBuilder) then
					units[#units + 1] = u
				end
			end
			-- (through pcall: a host can forbid user widgets' orders, BAR's handler then throws, and a widget that throws
			-- is removed, the whole dock with it; the units built later still take the factory's state)
			if state and #units > 0 and pcall(Spring.GiveOrderToUnitArray, units, p.give, { state }, 0) then
				total = total + #units
			end
		end
	end
	if total > 0 then
		label = (label or ""):match("^%s*(.-)%s*$") -- (BAR's " Fly ")
		local P = WG.BarDroidPad
		if P and P.say then
			P.say(string.format("%d %s: %s", total, total == 1 and "UNIT" or "UNITS", string.upper(label)))
		end
		Spring.Echo(string.format("[bardroid-portrait] factory state %s to %d units", label, total)) -- (tools)
	end
end

function widget:UnitFromFactory(unitID, _, unitTeam, factID)
	if unitTeam == myTeam() and factID then
		fac.made[factID] = fac.made[factID] or {}
		fac.made[factID][unitID] = true
	end
end

function widget:UnitDestroyed(unitID)
	fac.made[unitID] = nil
end

-- The first or the last order taken off (Kailil, 2026-11-10: "a way to remove orders at the front or end of a queue"):
-- a factory's build queue through BAR's own build button right-clicked (the engine takes one of that type off the
-- back; with Alt the first of it), the last or the first item's type; units' orders through BAR's Command Queue
-- Manager, whose keys the app presses (bardroid_pad.lua queueKey), as the pad's L3 and R3 do
local function removeOrder(last)
	for _, u in ipairs(spGetSelectedUnits() or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
		if ud and ud.isFactory then
			local items = {}
			for _, c in ipairs(Spring.GetFactoryCommands(u, -1) or {}) do
				if c.id < 0 then
					items[#items + 1] = c.id
				end
			end
			local id = last and items[#items] or items[1]
			local index = id and spGetCmdDescIndex(id)
			if index then
				spSetActiveCommand(index, 3, false, true, not last, false, false, false)
			end
			return
		end
	end
	local P = WG.BarDroidPad
	if P and P.queueKey then
		P.queueKey(last)
	end
end

-- the units the filter keeps (an "all" keeps them all)
local function filtered(units)
	local f
	for _, x in ipairs(FILTERS) do
		if x.key == selFilter then
			f = x
		end
	end
	if not (f and f.test) then
		return units
	end
	local keep = {}
	for _, u in ipairs(units or {}) do
		if f.test(UnitDefs[Spring.GetUnitDefID(u) or -1]) then
			keep[#keep + 1] = u
		end
	end
	return keep
end

-- the box selection's filter on what the engine selected
local function applyFilter()
	if selFilter ~= "all" then
		selectUnits(filtered(spGetSelectedUnits() or {}))
	end
end

-- the circle's units: my team's within it on the ground, through the filter
local function pickCircle()
	local c = circle
	circle = nil
	if not (c and c.r > 0) then
		return
	end
	-- (only those in sight above the dock: a circle drawn on into it picked units it hides, 2026-11-11)
	local seen, all = {}, Spring.GetUnitsInCylinder(c.x, c.z, c.r, myTeam()) or {}
	for _, u in ipairs(all) do
		local x, y, z = Spring.GetUnitPosition(u)
		local sx, sy = Spring.WorldToScreenCoords(x or 0, y or 0, z or 0)
		-- (and in the split dock's game between its blocks, which is the map: a circle there picked nothing; review
		-- 2026-11-16)
		if x and (sy >= L.dock[4] or L.split and L.hole and inRect(sx, sy, L.hole)) then
			seen[#seen + 1] = u
		end
	end
	Spring.Echo(string.format("[bardroid-portrait] circle: %d units in it, %d in sight above the dock (its top %d)", #all,
		#seen, L.dock[4])) -- (tools)
	selectUnits(filtered(seen))
end

-- a "dockcircle x y r" line (X screen pixels, top left origin): its middle and edge on the ground
local function circleTo(x, y, r)
	local gy = vsy - y
	local _, a = Spring.TraceScreenRay(x, gy, true)
	if not a then
		return
	end
	local _, b = Spring.TraceScreenRay(min(vsx - 1, x + max(1, r)), gy, true)
	local wr = b and math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2) or 0
	circle = { x = a[1], y = a[2], z = a[3], r = wr }
end

-- a type in the LOCAL / ALL UNITS list held: out of ALL's picks, or back in (SP.leftOut); ALL lit, the pick follows
function SP.toggleOut(item)
	local d = item.defID
	if not SP.leftOut[d] then -- (the list's last type stays in: else ALL picked nothing and the list closed)
		local others = 0
		for _, g in ipairs(leftItems) do
			if g.defID and g.defID ~= d and not SP.leftOut[g.defID] then
				others = others + 1
			end
		end
		if others == 0 then
			Spring.Echo("[bardroid-portrait] the list's last type stays in ALL UNITS") -- (tools)
			return
		end
	end
	SP.leftOut[d] = not SP.leftOut[d] or nil
	local ud = UnitDefs[d]
	Spring.Echo(("[bardroid-portrait] %s %s ALL UNITS"):format(ud and (ud.translatedHumanName or ud.humanName) or d,
		SP.leftOut[d] and "left out of" or "back in")) -- (tools)
	if allPicked and not multi then
		keepTypes = true
		selectUnits((SP.unitsIn(leftItems)))
	end
end

local function pressItem(item, long)
	if not item then
		return
	end
	local k = item.kind
	if item.home then -- (the home grid under the resource panel)
		resPanel = nil
	end
	if k == "build" then
		if selectedFactory() then -- a factory: one more (a long press: one less), and its queue buttons
			-- (INSERT on: Alt, the queue's front, as BAR's alt-click; Kailil, 2026-11-12: "Insert is still not inserting the
			-- unit I select in front of everything", the picture's tap went to the end, only +1/+5/+20 had it)
			local Pd = WG.BarDroidPad
			local insert = not long and Pd and Pd.queueState and select(2, Pd.queueState())
			runCommand(item.id, long, false, false, insert or false)
			factoryItem = item.id
		else
			runCommand(item.id)
		end
	elseif k == "quickbuild" then -- (nothing picked: its builder picked; the building once the engine has made that
		-- builder's commands, a frame or two later, widget:Update)
		selectUnits({ item.unit })
		SP.quickPending = { id = item.id, unit = item.unit, at = now() }
	elseif k == "order" and item.id == CMD.MANUALFIRE and not long and WG.BarDroidPad and WG.BarDroidPad.act then
		WG.BarDroidPad.act("dgun") -- (the pad's D-gun mode, its sticks on the dock: dgunOn)
	elseif k == "order" then
		runCommand(item.id, long)
		if selectedFactory() then -- (its units follow once the state rests: factoryStates)
			local give = (item.id == CMD.MOVE_STATE or item.id == CMD.IDLEMODE) and item.id
				or (fac.isLandAt(item.id) and CMD.IDLEMODE)
			if give then
				fac.pressed = { cmd = item.id, give = give, at = now() }
			end
		end
	elseif k == "units" then
		typesFrom = typesFrom ~= item.from and item.from or nil
		multi, multiPicked, allPicked = false, {}, false
		if typesFrom == "local" or typesFrom == "all" then -- (Kailil, 2026-11-10: "default to all and have them selected
			-- upon first tapping all units or local units": the list stays, its ALL lit, a type still narrows it; the types
			-- left out not picked, SP.leftOut)
			local groups = byType(typesUnits(), combat)
			local all, out = SP.unitsIn(groups)
			if #all == 0 and out > 0 then -- (only left-out types here, LOCAL UNITS say: they come back in, or the list
				-- picked nothing, closed at once and never let one be brought back; only this list's, the others stay out:
				-- every one came back, a type out of ALL UNITS too, types-phone-test 2026-11-20)
				for _, g in ipairs(groups) do
					if g.defID then
						SP.leftOut[g.defID] = nil
					end
				end
				all = SP.unitsIn(groups)
				Spring.Echo("[bardroid-portrait] every type in the list was left out: those back in") -- (tools)
			end
			keepTypes, allPicked = true, #all > 0
			selectUnits(all)
		end
	elseif k == "alltypes" then -- the ALL / MULTI toggle (Kailil, 2026-11-13: "replace the ALL BUTTON with an all/multi
		-- toggle. Toggling multi will allow me to select multiple unit types and give them orders instead of everyone
		-- selected"): MULTI lets everyone go, each type tapped joins; ALL picks the whole list again; the list stays
		multi, multiPicked = not multi, {}
		local all = not multi and SP.unitsIn(leftItems) or {} -- (the types left out not picked)
		keepTypes, allPicked = true, #all > 0
		selectUnits(all)
	elseif k == "type" and long then -- (held: that type out of ALL's picks for a while, or back in)
		SP.toggleOut(item)
	elseif k == "type" then
		if multi then
			multiPicked[item.defID] = not multiPicked[item.defID] or nil
			local all = {}
			for _, g in ipairs(leftItems) do
				if g.defID and multiPicked[g.defID] then
					for _, u in ipairs(g.units) do
						all[#all + 1] = u
					end
				end
			end
			selectUnits(all)
		else
			selectUnits(item.units)
			typesFrom = nil
		end
	elseif k == "seltype" then
		selectUnits(item.units)
	elseif k == "shape" then
		local B = WG.bardroidBuildmenu
		if B and B.droidSetShape then
			B.droidSetShape(item.shape)
		end
	elseif k == "filter" then
		selFilter = item.key
	elseif k == "style" then
		selStyle = selStyle == "box" and "circle" or "box"
		writeDock(true)
	elseif k == "filterpick" then -- (nothing picked: the next filter for the next selection, round the list)
		for i, f in ipairs(FILTERS) do
			if f.key == selFilter then
				selFilter = FILTERS[i % #FILTERS + 1].key
				break
			end
		end
	elseif k == "queue" and factoryItem then
		if item.n < 0 then
			runCommand(factoryItem, true)
		else
			-- (Shift: 5, Ctrl: 20, as BAR's build menu; both are 100: +20 sent both and queued 100, 2026-11-10. INSERT on:
			-- Alt, BAR's alt-click to the queue's front; bardroid_pad.lua holds no CommandInsert key for factories)
			local Pd = WG.BarDroidPad
			local insert = Pd and Pd.queueState and select(2, Pd.queueState())
			runCommand(factoryItem, false, item.n == 5, item.n == 20, insert or false)
		end
	elseif k == "clearitem" and factoryItem then
		runCommand(factoryItem, true, true, true) -- (right click with Shift and Ctrl: the whole queue of it)
	elseif k == "back" then
		factoryItem = nil
	elseif k == "commander" or k == "factories" then -- the next one picked and the camera on it (again: the next)
		local list = myCommanders(k)
		if #list > 0 then
			cycleAt[k] = (cycleAt[k] or 0) % #list + 1
			local u = list[cycleAt[k]]
			if k == "factories" then -- (picked once FACTORIES rests 0.75 s, Update: picked at once the dock went to the
				-- factory's screen and the next press had no FACTORIES; Kailil, 2026-11-13: "The factories button should let
				-- me cycle through factories. Only after I dont press the factories button after .75 seconds does the bottom
				-- ui switch to show the selected factory screen")
				L.factoryPick = { unit = u, at = now() + 0.75, wait = 0.75 }
				-- (which one, by name and place in the list: factories side by side, the camera's move alone did not say)
				local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
				local P = WG.BarDroidPad
				if ud and P and P.say then
					P.say(string.format("%s (%d OF %d)", string.upper(ud.translatedHumanName or ud.humanName or ud.name),
						cycleAt[k], #list))
				end
			else
				selectUnits({ u })
			end
			local x, y, z = Spring.GetUnitPosition(u)
			if x then
				-- (30 % further out than the comfortable distance: Kailil, 2026-11-11, "Commander button is too zoomed in.
				-- Zoom out like 30 percent"; a factory the same)
				cameraTo(x, y, z, 1.3)
			end
		end
	elseif k == "specact" then -- (spectating, SP: the spectate widget's own action)
		SP.act(item.act)
	elseif k == "specteams" then
		SP.teams = true
	elseif k == "specclose" then
		SP.teams = false
	elseif k == "specteam" then
		SP.pick(item)
	elseif k == "specfull" then -- (BAR's own: the whole map's view, or the watched team's sight)
		Spring.SendCommands("specfullview")
	elseif k == "spechide" then
		SP.setHidden(true)
	elseif k == "pings" then -- (left half: the camera to the last 4 pings, again within 2 s the one before; right half:
		-- the map's next tap is a ping, pressed again: not; spectating, the whole of it: the last pings)
		local r = pingT.rect
		if r and (item.pingOnly or pingT.pressX and pingT.pressX >= (r[1] + r[3]) / 2) and leftKind ~= "spec" then
			if pingT.armed() then
				pingT.cancel()
			else
				pingT.armedAt = now()
			end
			if WG.BarDroidPad and WG.BarDroidPad.say then
				WG.BarDroidPad.say(pingT.armedAt and "TAP THE MAP TO PING" or "NO PING")
			end
		else
			pingT.cancel()
			pingT.look()
		end
	elseif k == "base" then -- the camera where the commander began (the start spot)
		local x, y, z = Spring.GetTeamStartPosition(myTeam())
		if x and (x > 0 or z > 0) then
			cameraTo(x, y, z, true)
		end
	elseif k == "retreat" and WG.BarDroidRetreat then -- (bardroid_retreat.lua: hurt units fall back, on or off)
		if WG.BarDroidRetreat.allowed and not WG.BarDroidRetreat.allowed() then
			if WG.BarDroidPad and WG.BarDroidPad.say then
				WG.BarDroidPad.say("THIS GAME'S HOST TURNED OFF UNIT CONTROL WIDGETS")
			end
		else
			WG.BarDroidRetreat.set(not WG.BarDroidRetreat.on())
		end
	elseif k == "presets" and WG.BarDroidPresets then -- (bardroid_presets.lua: the presets over the grid)
		WG.BarDroidPresets.open()
	elseif k == "preset" and WG.BarDroidPresets then -- (one picked: the map's next tap is where they go)
		WG.BarDroidPresets.pick(item.id)
	elseif k == "transfer" then
		sharing = "units"
	elseif k == "sendres" then
		sharing, resPanel = item.res, nil
	elseif k == "sharestep" then
		shareFraction = item.value
	elseif k == "shareto" then
		local P = WG.BarDroidPad
		if P and P.give then
			P.give(item.teamID, sharing, shareFraction)
		end
		sharing = nil
	elseif k == "sharecancel" then
		sharing = nil
	elseif k == "panelclose" then
		resPanel = nil
	elseif k == "faction" and Spring.GetGameFrame() == 0 then
		Spring.SendLuaRulesMsg("changeStartUnit" .. tostring(item.startUnit))
	elseif k == "pregame" or k == "pregameundo" or k == "pregameclear" then
		local pb = WG["pregame-build"]
		if pb then
			if k == "pregame" then -- (a second tap puts it away; so does PLACE's cancel)
				pb.setPreGamestartDefID(pb.getPreGameDefID() ~= item.defID and item.defID or nil)
			elseif k == "pregameundo" then -- (as BAR's right click there: the last one off)
				local q = pb.getBuildQueue()
				if q and #q > 0 then
					table.remove(q)
				end
			elseif pb.setBuildQueue then
				pb.setBuildQueue({})
			end
			if pb.forceRefresh then
				pb.forceRefresh()
			end
		end
	end
	refresh()
end

-- Nothing picked ("home"): the right half's buttons across both halves, 2 wide and HOME_ROWS tall (Kailil,
-- 2026-11-09: "much larger buttons ... Only buttons should be there")
local function homeRect() -- (sideways: the right half's place, the minimap between the halves; unfolded: the right block)
	return (L.land or L.split) and L.right or { L.left[1], L.left[2], L.right[3], L.right[4] }
end
-- A button's words by the order rows' height (L.btnH): two rows tall, a little larger. The unfolded dock's pregame
-- buttons too: one row each there, their rows filling the block (half), their words were an order button's in buttons
-- twice as tall, smaller than the same buttons upright or sideways (dev phone at 1080x1198, 2026-11-17)
function SP.wordsK(item)
	return ((item.h or 1) > 1 or L.split and rightKind == "pregame" and item.kind ~= "build") and 0.6 or 0.46
end
function SP.homeLive() -- (writeDock's "live" home grid: it comes before homeRect)
	return homeRect()
end
-- the share list's and a panel's rows in sight: about an order and a half tall, the nearest whole number of them filling
-- the grid (half sizes them to it). At a fixed height 4.8 stood in the upright teammate picker, the fifth cut at rest
-- (dev phone screenshot 2026-11-17)
function SP.wideRows()
	local hr = homeRect()
	return max(1, floor((hr[4] - hr[2] + L.gap) / (floor(L.btnH * 1.5) + L.gap) + 0.5))
end

-- a half's geometry: its rect, scroll, items, columns, cell width and height
local function half(side)
	if side == "left" then
		local st = SP.smallTypes -- (a pick's types as tall as an order while orders spill over: refreshNow)
		if st then
			return L.left, leftScroll, leftItems, st.cols, st.size, st.size
		end
		return L.left, leftScroll, leftItems, L.leftCols or 3, L.tile, L.tile
	end
	if side == "over" then -- (the orders past the right's first page, under a pick's types: refreshNow)
		return SP.overRect or { 0, 0, -1, -1 }, SP.overScroll, SP.overItems or {}, 2, L.btnW, L.btnH
	end
	if rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets" then -- (the whole grid)
		local r = homeRect()
		local cols = leftKind == "spec" and SP.COLS or 2 -- (spectating: 6 narrow columns, SP)
		return r, rightScroll, rightItems, cols, floor((r[3] - r[1] - (cols - 1) * L.gap) / cols),
			floor((r[4] - r[2] + L.gap) / ((rightKind == "home" or rightKind == "presets") and (L.homeRows or HOME_ROWS)
				or SP.wideRows())) - L.gap
	end
	if rightKind == "pregame" and (L.split or not L.land) then -- (unfolded: the pregame buttons' rows fill the right
		-- block; at the orders' height three rows left two empty under them, dev phone 2026-11-15. Upright likewise: their
		-- two-row-tall buttons left one short row empty under RANDOM and PING, above the build grid's bottom, dev phone
		-- 2026-11-17, a skirmish from the lobby; the packed rows, refreshNow, so a two-row button stays two)
		local rows = max(1, SP.rightRowsN or math.ceil(#rightItems / (L.rightCols or 2)))
		return L.right, rightScroll, rightItems, L.rightCols or 2, L.btnW,
			max(L.btnH, floor((L.right[4] - L.right[2] + L.gap) / rows) - L.gap)
	end
	if rightKind == "place" and SP.shapeRow() then -- (the four shapes in one row, PLACE the taller under it: SP.shapeRow)
		return L.right, rightScroll, rightItems, 4, floor((L.right[3] - L.right[1] - 3 * L.gap) / 4), L.btnH
	end
	return L.right, rightScroll, rightItems, L.rightCols or 2, L.btnW, L.btnH
end

-- an item's rect in its half as the rows stand scrolled (pack)
local function cellRect(side, i)
	local r, s, _, _, cw, ch = half(side)
	local c = cellsOf[side][i]
	if not c then
		return nil
	end
	local y1 = r[4] - (c.row - s.pos) * (ch + L.gap)
	local x0 = r[1] + c.col * (cw + L.gap)
	return { x0, y1 - (c.h * ch + (c.h - 1) * L.gap), x0 + c.w * cw + (c.w - 1) * L.gap, y1 }
end

-- the item under a point of a half
local function itemAt(side, x, y)
	local r, s, items, cols, cw, ch = half(side)
	if not inRect(x, y, r) then
		return nil
	end
	if side ~= "left" then -- (packed: the cell that holds the point; the right half and its overflow)
		for i, it in ipairs(items) do
			local cr = cellRect(side, i)
			if cr and inRect(x, y, cr) then
				return it
			end
		end
		return nil
	end
	local row = floor((r[4] - y) / (ch + L.gap) + s.pos)
	local col = floor((x - r[1]) / (cw + L.gap))
	if col < 0 or col >= cols then
		return nil
	end
	return items[row * cols + col + 1]
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing: BAR's own FlowUI (gui_flowui.lua): Element for panels, Button for buttons, Unit for unit tiles, Selector for
-- the one in use (Kailil: "as close as possible to the BAR original")

local function flow()
	return WG.FlowUI and WG.FlowUI.Draw
end

-- opaque: the dock itself (BAR's panels show the game through; the dock covers the menus and lists under it)
local function panel(r, ctl, ctr, cbr, cbl, opaque)
	local f = flow()
	if f and f.Element then
		f.Element(r[1], r[2], r[3], r[4], ctl or 1, ctr or 1, cbr or 1, cbl or 1, nil, nil, nil, nil, nil, nil, nil, nil, opaque)
	else
		gl.Color(0.04, 0.04, 0.04, opaque and 1 or 0.8)
		gl.Rect(r[1], r[2], r[3], r[4])
	end
	gl.Color(1, 1, 1, 1) -- (a unit picture right after an Element came out dark: the state it leaves)
	gl.Texture(false)
end

-- (a unit picture drawn right after a FlowUI button or selector came out dark: the state they leave)
local function resetGL()
	gl.Color(1, 1, 1, 1)
	gl.Texture(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
end

local function button(r, c1, c2)
	local f = flow()
	if f and f.Button then
		f.Button(r[1], r[2], r[3], r[4], 1, 1, 1, 1, 1, 1, 1, 1, nil, c1, c2, max(1, floor(L.pad * 0.35)))
	else
		gl.Color(c1 or { 0.15, 0.15, 0.15, 0.9 })
		gl.Rect(r[1], r[2], r[3], r[4])
	end
	resetGL()
end

local function selector(r)
	local f = flow()
	if f and f.Selector then
		f.Selector(r[1], r[2], r[3], r[4])
	end
	resetGL()
end

-- in use: as BAR's build menu shows its picked cell (gui_buildmenu.lua drawCell): the picture closer, gold light over it
local function unitTile(defID, r, inUse)
	local f = flow()
	local cs = max(2, floor((r[3] - r[1]) * 0.06))
	if f and f.Unit then
		local zoom = inUse and 0.135 or 0.04
		f.Unit(r[1], r[2], r[3], r[4], cs, 1, 1, 1, 1, zoom, nil, nil, "#" .. defID)
		if inUse then
			gl.Blending(GL.SRC_ALPHA, GL.ONE)
			gl.Color(1, 0.85, 0.2, 0.25)
			gl.Texture("#" .. defID)
			f.Unit(r[1], r[2], r[3], r[4], cs, 1, 1, 1, 1, zoom)
			gl.Texture(false)
			gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
		end
	else
		gl.Texture("#" .. defID)
		gl.TexRect(r[1], r[2], r[3], r[4])
		gl.Texture(false)
	end
	gl.Color(1, 1, 1, 1)
end

local function textIn(text, x0, y0, x1, y1, size, color, f, wrap)
	f = f or font
	if not f then
		return
	end
	-- (at most 76% of the width: the outline is not in the font's width, and at 88% words that just fit, ROTATE in its
	-- square on the unfolded Fold7 upright, LAST PINGS, ran up to the button's edges: dev phone, 2026-11-11; at 84 %
	-- LAST PINGS in its half of the home grid upright still stood a few pixels from them, 2026-11-13)
	local room = (x1 - x0) * 0.76
	local w = f:GetTextWidth(text) * size
	if w > room then
		local one = size * room / w
		-- (wrap, a button's words: two lines where one would shrink under 70 %, broken at the space that evens them;
		-- sideways for one thumb on the unfolded Fold7 LAST PINGS was a speck in its half, dev phone 2026-11-12)
		if wrap and one < size * 0.7 then
			local at, widest
			for i in text:gmatch("() ") do
				local m = max(f:GetTextWidth(text:sub(1, i - 1)), f:GetTextWidth(text:sub(i + 1)))
				if not widest or m < widest then
					at, widest = i, m
				end
			end
			local two = at and min(size, room / widest, (y1 - y0) / 2.4) or 0
			if two > one then
				local cx, cy, c = (x0 + x1) / 2, (y0 + y1) / 2, color or "\255\235\235\235"
				f:Print(c .. text:sub(1, at - 1), cx, cy + two * 0.2, two, "co")
				f:Print(c .. text:sub(at + 1), cx, cy - two * 0.85, two, "co")
				return
			end
		end
		size = one
	end
	f:Print((color or "\255\235\235\235") .. text, (x0 + x1) / 2, (y0 + y1) / 2 - size * 0.32, size, "co")
end

-- PING's half of the tile (b): PING, TAP MAP (the label under it), SPEAK, or CHAT, as the states are
function pingT.drawBtn(b, armed, th)
	local t, c, v = now(), pingT.chat, pingT.voice
	local word, sub = "PING", nil
	local fill, edge = nil, nil
	if v and not v.endedAt and not v.cancelled then
		word, fill, edge = "SPEAK", { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 }
		sub = v.spot and "PING SET" or nil
	elseif armed then
		word, fill, edge = "TAP MAP", { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 }
		sub = pingT.label
	end
	local sy, burst = 1, nil
	if c then
		local glow = math.floor(t * 8) / 8 -- (in the steps pingT.update redraws it at)
		local chatFill, chatEdge = { 0.04, 0.2, 0.25, 0.95 }, { 0.25, 0.72, 0.85, 0.75 + 0.25 * math.sin(glow * 6) ^ 2 }
		local newWord
		if c.endAt then -- (back to PING)
			sy, newWord, burst = pingT.flip(t - c.endAt)
			if not newWord then
				word, sub, fill, edge = "CHAT", nil, chatFill, chatEdge
			end
		else
			sy, newWord, burst = pingT.flip(t - c.at)
			if newWord then
				word, sub, fill, edge = "CHAT", nil, chatFill, chatEdge
			end
		end
	end
	local cx, cy, w, h = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2, b[3] - b[1], b[4] - b[2]
	local sx = max(1, sy) -- (the pop: as wide as it is tall past 1)
	local r = { cx - w * sx / 2, cy - h * sy / 2, cx + w * sx / 2, cy + h * sy / 2 }
	if burst then -- (a gold ring bursting out of the button and fading)
		local k = 1 + 0.32 * burst
		local a = 0.85 * (1 - burst)
		local lw = max(2, floor(h * 0.045))
		local x0, y0, x1, y1 = cx - w * k / 2, cy - h * k / 2, cx + w * k / 2, cy + h * k / 2
		x0, x1 = max(x0, L.dock[1] + 1), min(x1, L.dock[3] - 1) -- (inside the dock: past the screen's edge it was cut)
		gl.Color(1, 0.82, 0.35, a)
		gl.Rect(x0, y0, x1, y0 + lw)
		gl.Rect(x0, y1 - lw, x1, y1)
		gl.Rect(x0, y0, x0 + lw, y1)
		gl.Rect(x1 - lw, y0, x1, y1)
		gl.Color(1, 1, 1, 1)
	end
	if r[4] - r[2] < 2 then
		return
	end
	button(r, fill, edge)
	if sy < 0.25 then -- (the word too squashed to read: none)
		return
	end
	local size = th * min(1, sy)
	if sub then
		local mid = r[2] + (r[4] - r[2]) * 0.38
		textIn(word, r[1], mid, r[3], r[4], size * 0.9, "\255\240\240\240", font)
		textIn(sub, r[1], r[2], r[3], mid, size * 0.6, "\255\255\215\120", font)
	else
		textIn(word, r[1], r[2], r[3], r[4], size, "\255\240\240\240", font)
	end
end

local function drawTile(item, r)
	local w, h = r[3] - r[1], r[4] - r[2]
	if item.kind == "alltypes" then -- the ALL / MULTI toggle: ALL and its count above, MULTI below, the side on lit
		button(r, { 0.2, 0.2, 0.2, 0.8 }, { 0.35, 0.35, 0.35, 0.8 })
		-- (none: dimmed, as FACTORIES with no factory; a lit "ALL 0" read as a list of something)
		local none = item.count == 0
		local mid, dim = r[2] + floor(h / 2), "\255\120\120\120"
		if SP.smallTypes and h < L.tile * 0.8 then -- (as short as an order: ALL and its count on one line, MULTI under it)
			textIn("ALL " .. item.count, r[1], mid, r[3], r[4], h * 0.3, (none or multi) and dim or "\255\255\255\255", bold)
			textIn("MULTI", r[1], r[2], r[3], mid, h * 0.3, multi and "\255\255\255\255" or dim, bold)
		else
			textIn("ALL", r[1], mid + h * 0.17, r[3], r[4] - h * 0.02, h * 0.2,
				(none or multi) and dim or "\255\255\255\255", bold)
			textIn(tostring(item.count), r[1], mid, r[3], mid + h * 0.19, h * 0.14,
				(none or multi) and dim or "\255\255\200\064")
			textIn("MULTI", r[1], r[2], r[3], mid, h * 0.2, multi and "\255\255\255\255" or dim, bold)
		end
		local S, lw = WG.BarDroidStyle, max(2, floor(w * 0.04))
		local lit = multi and { r[1], r[2], r[3], mid } or { r[1], mid, r[3], r[4] }
		if S and (multi or allPicked) then
			S.outline(lit[1], lit[2], lit[3], lit[4], S.GOLD, 1, lw)
		elseif multi or allPicked then
			selector(lit)
		end
		return
	end
	-- (a pregame option picked: lit as BAR's menu lights its picked cell)
	local pb = item.kind == "pregame" and WG["pregame-build"]
	-- (the building PLACE will build: BAR's picked cell (the picture closer, gold light) and the gold line of the build
	-- menu copy's picked cell; FlowUI's selector alone was a faint border nobody saw, dev phone screenshot 2026-11-11)
	local picked = item.kind == "build" and item.id and activeBuild() == item.id
	unitTile(item.defID, r, picked or (pb and pb.getPreGameDefID and pb.getPreGameDefID() == item.defID) or false)
	if picked and WG.BarDroidStyle then
		WG.BarDroidStyle.outline(r[1], r[2], r[3], r[4], WG.BarDroidStyle.GOLD, 1, max(2, floor(w * 0.04)))
	end
	local p, size = max(2, floor(w * 0.05)), h * 0.15
	if item.kind == "build" or item.kind == "pregame" or item.kind == "quickbuild" then -- (as BAR's build menu: metal
		-- white, energy yellow, bottom right)
		local ud = UnitDefs[item.defID]
		if ud then
			font:Print("\255\245\245\245" .. floor(ud.metalCost or 0), r[3] - p, r[2] + p + size * 1.05, size, "ro")
			font:Print("\255\255\255\000" .. floor(ud.energyCost or 0), r[3] - p, r[2] + p, size, "ro")
		end
		if item.queued and item.queued > 0 then
			bold:Print("\255\255\255\255" .. item.queued, r[1] + p * 1.5, r[4] - p - size * 1.5, size * 1.5, "o")
		end
		if item.kind ~= "quickbuild" and item.id and (activeBuild() == item.id or factoryItem == item.id) then
			selector(r)
		end
		if item.kind == "quickbuild" then -- (dimmed: no builder picked yet, the tap picks it)
			gl.Color(0, 0, 0, 0.38)
			gl.Rect(r[1], r[2], r[3], r[4])
			gl.Color(1, 1, 1, 1)
		end
	else -- a type: its count (on the small tiles, SP.smallTypes, half again as large: "10" and "4" were hard to read)
		if item.out then -- (left out of ALL UNITS, SP.leftOut: darkened and struck through corner to corner, red; from
			-- the bottom left to the top right, clear of the count in the bottom right corner, which the other diagonal
			-- ran through: dev phone picture, 2026-11-20)
			gl.Color(0, 0, 0, 0.6)
			gl.Rect(r[1], r[2], r[3], r[4])
			local t = max(2, floor(w * 0.05))
			gl.Color(0.9, 0.2, 0.15, 0.95)
			gl.BeginEnd(GL.QUADS, function()
				gl.Vertex(r[1], r[2] + t)
				gl.Vertex(r[1] + t, r[2])
				gl.Vertex(r[3], r[4] - t)
				gl.Vertex(r[3] - t, r[4])
			end)
			gl.Color(1, 1, 1, 1)
		end
		bold:Print((item.out and "\255\150\150\150" or "\255\255\255\255") .. #item.units, r[3] - p, r[2] + p,
			size * (h < L.tile * 0.8 and 2.1 or 1.4), "ro")
		if multi and multiPicked[item.defID] then -- (gold, as the toggle's MULTI: FlowUI's selector alone did not show on
			-- the unit pictures, dev phone 2026-11-13)
			if WG.BarDroidStyle then
				WG.BarDroidStyle.outline(r[1], r[2], r[3], r[4], WG.BarDroidStyle.GOLD, 1, max(2, floor(w * 0.04)))
			else
				selector(r)
			end
		end
	end
end

-- TRANSFER's arrow, handing over to the right, in its button's left part; the x the word starts from
function SP.transferArrow(r)
	local w, h = r[3] - r[1], r[4] - r[2]
	local s = min(h * 0.42, w * 0.14)
	local x0 = r[1] + max(6, floor(w * 0.07))
	local cy = (r[2] + r[4]) / 2
	gl.Color(0.88, 0.95, 1, 0.95)
	gl.Rect(x0, cy - s * 0.13, x0 + s * 0.58, cy + s * 0.13)
	gl.BeginEnd(GL.TRIANGLES, function()
		gl.Vertex(x0 + s * 0.52, cy + s * 0.42)
		gl.Vertex(x0 + s, cy)
		gl.Vertex(x0 + s * 0.52, cy - s * 0.42)
	end)
	gl.Color(1, 1, 1, 1)
	return x0 + s * 0.6
end

-- BAR's order menu's state lights (gui_ordermenu.lua's DrawCell): the first state red, the second yellow (green when
-- there are only two), the third and on green; "Fire at will" red and "Hold pos" green here before, the other way
-- round from BAR's (dev phone screenshot 2026-11-11)
local STATE_COLORS = { { 0.9, 0.25, 0.2, 1 }, { 0.95, 0.8, 0.2, 1 }, { 0.3, 0.85, 0.3, 1 } }

local function currentShape()
	local B = WG.bardroidBuildmenu
	if B and B.droidPlace then
		local _, shape = B.droidPlace()
		return shape
	end
end

-- the resource bar in a panel's slider cell: its rect and height (the knobs' halves fit at its ends)
function SP.barArea(r)
	local h = r[4] - r[2]
	local bh = max(5, floor(h * 0.12 + 0.5))
	local side = floor((bh + 2 * bh / 0.75) * 0.5 + h * 0.14)
	local y0 = r[2] + floor(h * 0.26)
	return { r[1] + side, y0, r[3] - side, y0 + bh }, bh
end
SP.KNOB = { share = { 0.85, 0, 0, 1 }, convert = { 0.95, 0.95, 0.7, 1 } } -- (gui_top_bar.lua's)
function SP.glowQuad(x0, y0, x1, y1, o) -- (gui_top_bar.lua's RectQuad)
	gl.BeginEnd(GL.QUADS, function()
		gl.TexCoord(o, 1 - o)
		gl.Vertex(x0, y0)
		gl.TexCoord(1 - o, 1 - o)
		gl.Vertex(x1, y0)
		gl.TexCoord(1 - o, o)
		gl.Vertex(x1, y1)
		gl.TexCoord(o, o)
		gl.Vertex(x0, y1)
	end)
end
-- BAR's top bar's resource bar as gui_top_bar.lua draws it, at this cell's size: the track (its dark outlines, inner
-- light edge, noise and gloss), the storage's fill (metal grey to white, energy dark to bright yellow, its glow; energy's
-- shimmer), and FlowUI's slider knobs: the share red, energy's conversion pale; a knob held as BAR's hovered one. Live
-- each frame (the fill moves): drawDock, over the dock's texture
-- part: "track" (still: into the dock's texture), "live" (the fill and knobs: each frame over it), nil both. The track
-- had been drawn live too: the open panel took the dock from 1.1-1.3 to 1.6-1.8 ms a frame (dev phone, 2026-11-17)
function SP.drawResBar(item, r, part)
	local f = flow()
	local b, bh = SP.barArea(r)
	local res = item.res
	local metal = res == "metal"
	local cur, storage = Spring.GetTeamResources(myTeam(), res)
	local w = b[3] - b[1]
	local frac = (storage or 0) > 0 and max(0, min(1, (cur or 0) / storage)) or 0
	local fw = max(math.ceil(bh * 0.2), floor(frac * w))
	if not (f and f.RectRound and f.RectRoundOutline and f.TexturedRectRound and f.SliderKnob) then
		if part ~= "live" then
			gl.Color(0.08, 0.08, 0.08, 0.95)
			gl.Rect(b[1], b[2], b[3], b[4])
		end
		if part ~= "track" then
			gl.Color(metal and 0.9 or 1, metal and 0.9 or 0.86, metal and 0.9 or 0.15, 1)
			gl.Rect(b[1], b[2], b[1] + fw, b[4])
			for _, what in ipairs(metal and { "share" } or { "convert", "share" }) do
				local c = SP.KNOB[what]
				local kx = b[1] + w * sliderValue(item, what)
				gl.Color(c[1], c[2], c[3], 1)
				gl.Rect(kx - bh * 0.6, b[2] - bh * 0.6, kx + bh * 0.6, b[4] + bh * 0.6)
			end
		end
		gl.Color(1, 1, 1, 1)
		return
	end
	local add = max(1, floor(bh * 0.15 + 0.5))
	local fh = add * 4
	if part ~= "live" then
		SP.drawResTrack(f, b, bh, w, add, fh)
		if part == "track" then
			resetGL()
			return
		end
	end
	SP.drawResFill(f, item, b, bh, w, add, fw, frac, metal, r)
end
-- the bar's track: gui_top_bar.lua's background, dark outlines, inner light edge, noise and gloss
function SP.drawResTrack(f, b, bh, w, add, fh)
	f.RectRound(b[1], b[2], b[3], b[4], bh * 0.2, 1, 1, 1, 1, { 0, 0, 0, 0.15 }, { 0, 0, 0, 0.2 })
	f.RectRoundOutline(b[1] - add - fh - 1, b[2] - add - fh - 1, b[3] + add + fh + 1, b[4] + add + fh + 1, bh * 0.8, fh,
		1, 1, 1, 1, { 0, 0, 0, 0 }, { 0, 0, 0, 0.22 })
	f.RectRoundOutline(b[1] - 2 * add - 1, b[2] - 2 * add - 1, b[3] + 2 * add + 1, b[4] + 2 * add + 1, add * 1.5, add,
		1, 1, 1, 1, { 0, 0, 0, 0 }, { 0, 0, 0, 0.66 })
	f.RectRoundOutline(b[1] - add - 1, b[2] - add - 1, b[3] + add + 1, b[4] + add + 1, bh * 0.33, bh * 0.1,
		1, 1, 1, 1, { 1, 1, 1, 0.3 }, { 1, 1, 1, 0 })
	gl.Blending(GL.SRC_ALPHA, GL.ONE)
	gl.Texture(":g:LuaUI/Images/rgbnoise.png")
	gl.Color(1, 1, 1, 0.88)
	f.TexturedRectRound(b[1] - 1, b[2] - 1, b[3] + 1, b[4] + 1, bh * 0.33, 1, 1, 1, 1, w * 0.33, 0)
	gl.Texture(false)
	f.RectRound(b[1] - add - 1, b[2] - add - 1, b[3] + add + 1, b[4] + add + 1, bh * 0.33, 1, 1, 1, 1,
		{ 0, 0, 0, 0.1 }, { 0, 0, 0, 0.1 })
	f.RectRound(b[1] - add, b[2] - add, b[3] + add, b[4] + add, bh * 0.33, 1, 1, 1, 1,
		{ 0.15, 0.15, 0.15, 0.17 }, { 0.8, 0.8, 0.8, 0.13 })
	f.RectRound(b[1] - add, b[2] + add, b[3] + add, b[4] + add, bh * 0.33, 1, 1, 0, 0, { 1, 1, 1, 0 }, { 1, 1, 1, 0.05 })
	f.RectRound(b[1] - add, b[2] - add, b[3] + add, b[2] + add * 2.5, bh * 0.2, 0, 0, 1, 1, { 1, 1, 1, 0.08 }, { 1, 1, 1, 0 })
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
end
-- the bar's fill (its glow, energy's shimmer) and knobs: live
function SP.drawResFill(f, item, b, bh, w, add, fw, frac, metal, r)
	f.RectRound(b[1], b[2], b[1] + fw, b[4], bh * 0.2, 1, 1, 1, 1,
		metal and { 0.51, 0.51, 0.5, 1 } or { 0.5, 0.45, 0, 1 }, metal and { 0.95, 0.95, 0.95, 1 } or { 0.8, 0.75, 0, 1 })
	f.RectRound(b[1] + 1, b[2] + 1, b[1] + fw - 1, b[4] - 1, bh * 0.2, 1, 1, 1, 1, { 0, 0, 0, 0.1 }, { 0, 0, 0, 0.17 })
	gl.Blending(GL.SRC_ALPHA, GL.ONE)
	local g = min(bh * 3, (r[4] - r[2]) * 0.3) -- (BAR's glow reaches 7 bar heights: here within the cell)
	local ga = metal and 0.025 + 0.05 * min(1, frac * 40) or 0.035 + 0.07 * min(1, frac * 40)
	gl.Color(1, 1, metal and 1 or 0, ga * 2)
	gl.Texture(":l:LuaUI/Images/barglow-center.png")
	SP.glowQuad(b[1], b[2] - g, b[1] + fw, b[4] + g, 0.008)
	gl.Texture(":l:LuaUI/Images/barglow-edge.png")
	SP.glowQuad(b[1] - g * 2.5, b[2] - g, b[1], b[4] + g, 0.008)
	SP.glowQuad(b[1] + fw + g * 3, b[2] - g, b[1] + fw, b[4] + g, 0.008)
	if metal then
		gl.Texture(":g:LuaUI/Images/rgbnoise.png")
		gl.Color(1, 1, 1, 0.37)
		f.TexturedRectRound(b[1], b[2], b[1] + fw, b[4], bh * 0.2, 1, 1, 1, 1, w * 0.33, 0)
	else -- (energy's shimmer, its texture drifting as BAR's)
		local t = now()
		gl.Texture("LuaUI/Images/paralyzed.png")
		gl.Color(1, 1, 1, 0.33)
		for _, k in ipairs({ { -80, 0.5 }, { 70, 0.33 }, { -55, 0.45 } }) do
			f.TexturedRectRound(b[1], b[2], b[1] + fw, b[4], bh * 0.2, 0, 0, 1, 1, w / k[2], (t / k[1]) % 1)
		end
		gl.Texture(false)
		gl.Color(1, 1, 0, 0.14)
		f.RectRound(b[1] - add, b[2] - add, b[1] + fw + add, b[4] + add, bh * 0.33)
	end
	gl.Texture(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	-- the knobs (energy: conversion first, the share over it, as BAR's)
	for _, what in ipairs(metal and { "share" } or { "convert", "share" }) do
		local held = slide and slide.item == item and slide.what == what
		local kw = bh + 2 * (held and bh / 0.75 or floor(bh / 1.55))
		f.SliderKnob(floor(b[1] + w * sliderValue(item, what)), floor((b[2] + b[4]) / 2), floor(kw / 2), SP.KNOB[what])
	end
	resetGL()
end

-- a resource panel's bar cell: BAR's dark panel, the words above the bar and its track (in the dock's texture); its
-- fill and knobs live (SP.drawResBars; all of it here without the texture)
local function drawSlider(item, r)
	panel(r)
	local h = r[4] - r[2]
	local b, bh = SP.barArea(r)
	local y0, y1 = b[4] + bh * 1.4, r[4] - h * 0.04
	local size = h * 0.22
	local share = floor(sliderValue(item, "share") * 100 + 0.5) .. "%"
	-- (the first wording that fits at 80 % of the words' size, else the shortest: in the unfolded split's narrow block
	-- energy's two long ones came out at half the size, dev phone at 1080x1198, 2026-11-17)
	local function fitting(room, ...)
		local pick, fit
		for _, words in ipairs({ ... }) do
			local wide = 0
			for _, s in ipairs(words) do
				wide = max(wide, font and font:GetTextWidth(s) or 0)
			end
			pick, fit = words, min(size, room * 0.76 / max(0.01, wide))
			if fit >= size * 0.8 then
				break
			end
		end
		return pick, fit
	end
	if item.res == "metal" then
		local w, fit = fitting(r[3] - r[1], { "SHARE METAL TO ALLIES ABOVE  " .. share }, { "SHARE METAL ABOVE  " .. share })
		textIn(w[1], r[1], y0, r[3], y1, fit, "\255\235\235\235", font)
	else -- (each value in its knob's colour, over its own half, both one size: the longer had come out smaller,
		-- sideways, dev phone 2026-11-17)
		local mid = (r[1] + r[3]) / 2
		local conv = floor(sliderValue(item, "convert") * 100 + 0.5) .. "%"
		local w, fit = fitting(mid - r[1], { "SHARE ENERGY ABOVE  " .. share, "CONVERT ABOVE  " .. conv },
			{ "SHARE ABOVE  " .. share, "CONVERT ABOVE  " .. conv }, { "SHARE  " .. share, "CONVERT  " .. conv })
		textIn(w[1], r[1], y0, mid, y1, fit, "\255\255\150\140", font)
		textIn(w[2], mid, y0, r[3], y1, fit, "\255\242\242\190", font)
	end
	SP.drawResBar(item, r, SP.inTex and "track" or nil)
end
-- the open resource panel's bars over the dock's texture (drawDock: the fill moves, the texture is made again only when
-- the dock changes)
function SP.drawResBars()
	if rightKind ~= "panel" then
		return
	end
	local hr = homeRect()
	for i, item in ipairs(rightItems) do
		local cr = item.kind == "slider" and cellRect("right", i)
		if cr and cr[2] >= hr[2] - 1 and cr[4] <= hr[4] + 1 then -- (wholly in sight; scrolled part way: the texture's
			-- words and track)
			SP.drawResBar(item, cr, "live")
		end
	end
end

local function drawButton(item, r, cap)
	if item.kind == "slider" then
		drawSlider(item, r)
		return
	end
	if item.kind == "blank" then -- (an open place on the home grid: a faint tile)
		button(r, { 0, 0, 0, 0.25 }, { 0.12, 0.12, 0.12, 0.3 })
		return
	end
	if item.kind == "pings" and leftKind == "spec" then -- (spectating: LAST PINGS alone, Kailil 2026-11-11)
		pingT.rect, L.pingBtn = r, nil
		local n, step = pingT.state()
		pingT.drawn = step .. ""
		button(r)
		textIn(step > 0 and string.format("PING %d OF %d", step, n) or "LAST PINGS", r[1], r[2], r[3], r[4],
			min((r[4] - r[2]) * 0.34, L.btnH * 0.46), n > 0 and "\255\240\240\240" or "\255\140\140\140", font, true)
		pingT.badge(r, n)
		return
	end
	if item.kind == "pings" and item.pingOnly then -- (pregame: PING alone, the whole place)
		pingT.rect = r
		local _, _, armed = pingT.state()
		pingT.drawn = "0" .. (armed and "a" or "")
		L.pingBtn = r
		-- (its row's size too, drawHalf: PING stood larger than RANDOM beside it before the start, 2026-11-17)
		pingT.drawBtn(r, armed, min((r[4] - r[2]) * 0.34, L.btnH * SP.wordsK(item), cap or math.huge))
		return
	end
	if item.kind == "pings" then -- (two buttons in one place: the last pings, and a ping of your own)
		pingT.rect = r
		local n, step, armed, attack = pingT.state()
		pingT.drawn = n .. ":" .. step .. (armed and "a" or "") .. (attack and "!" or "")
		local mx = floor((r[1] + r[3]) / 2)
		local gap = max(2, floor(L.gap / 2))
		local a, b = { r[1], r[2], mx - gap, r[4] }, { mx + gap, r[2], r[3], r[4] }
		button(a)
		-- (not its row's size: FACTORIES beside the pair shrank to LAST PINGS', smaller than the rows around it upright)
		local th = min((r[4] - r[2]) * 0.34, L.btnH * 0.46)
		textIn(step > 0 and string.format("%d OF %d", step, n) or "LAST PINGS", a[1], a[2], a[3], a[4], th,
			n > 0 and "\255\240\240\240" or "\255\140\140\140", font, true)
		pingT.badge(a, n, attack)
		L.pingBtn = b -- (RtsTouch's "ping": its hold and its double tap; L: writeDock comes before pingT)
		-- (PING as large as LAST PINGS beside it, unless that breaks over two lines: PING stood larger, 2026-11-17)
		local last = font and min(th, (a[3] - a[1]) * 0.76 / max(0.01, font:GetTextWidth("LAST PINGS"))) or th
		pingT.drawBtn(b, armed, last >= th * 0.7 and last or th)
		return
	end
	if item.kind == "preset" and WG.BarDroidPresets then -- (its thumbnail, its name under it)
		button(r)
		local lh = (r[4] - r[2]) * 0.2
		WG.BarDroidPresets.drawThumb(item.id, { r[1], r[2] + lh, r[3], r[4] })
		textIn(item.label or "", r[1], r[2], r[3], r[2] + lh * 1.2, lh * 0.62, "\255\240\240\240", font)
		return
	end
	local _, activeID = spGetActiveCommand()
	local lit = item.kind == "order" and activeID == item.id
	-- (a preset armed: PRESETS in gold with its name, as long as the map waits for its drag; it looked like any button
	-- once the pick's note had gone, dev phone screenshot 2026-11-11)
	local armed, armedName = false, nil
	if item.kind == "presets" and WG.BarDroidPresets then
		armed, armedName = WG.BarDroidPresets.armed()
	end
	local on = armed or item.kind == "units" and typesFrom == item.from
		or (item.kind == "specact" or item.kind == "specteam" or item.kind == "specfull") and item.on
		or item.kind == "shape" and currentShape() == item.shape or item.kind == "filter" and selFilter == item.key
		or item.kind == "faction" and Spring.GetTeamRulesParam(myTeam(), "startUnit") == item.startUnit
		or item.kind == "sharestep" and shareFraction == item.value or item.kind == "retreat" and item.on
	if on then -- (picked: BAR's gold)
		button(r, { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 })
	elseif lit then -- (the order armed: as BAR's order menu shows its active command, light grey to white, its words dark;
		-- FlowUI's Selector, used here before, is a drop-down field now: it left a light square at the button's right end,
		-- Area Mex armed in Kailil's screenshot, 2026-11-17)
		button(r, { 0.66, 0.66, 0.66, 0.95 }, { 1, 1, 1, 0.95 })
	elseif item.kind == "order" and item.id == CMD.MANUALFIRE then -- (the D-Gun red, in the gold's shades: Kailil,
		-- 2026-11-13, "Make the dgun button RED but still fit the ui look and feel")
		button(r, { 0.42, 0.07, 0.05, 0.9 }, { 0.74, 0.17, 0.12, 0.9 })
	elseif item.kind == "transfer" then -- (Kailil, 2026-11-20: "Make the transfer button more pronounced": the hand-over's
		-- blue, outlined, an arrow before the word; grey, it read as one more order beside Fire at will, dev phone
		-- screenshot 2026-11-20)
		button(r, { 0.04, 0.2, 0.38, 0.95 }, { 0.1, 0.42, 0.74, 0.95 })
		if WG.BarDroidStyle then
			WG.BarDroidStyle.outline(r[1], r[2], r[3], r[4], { 0.5, 0.8, 1, 0.9 }, 1, max(2, floor((r[4] - r[2]) * 0.04)))
		end
	else
		button(r)
	end
	-- (the home grid's tall buttons: their words a little larger than the order buttons', not by their height)
	local label = armedName or item.label or ""
	local th = min((r[4] - r[2]) * 0.34, L.btnH * SP.wordsK(item))
	if label == "<" or label == ">" then
		-- (the spectator's arrows as solid triangles: the font's "<" was a thin small mark in a big button, dev phone
		-- screenshot 2026-11-12)
		local cx, cy, s, d = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2, th * 0.45, label == "<" and -1 or 1
		local g = item.dim and 0.55 or 0.94
		gl.Color(g, g, g, 1)
		gl.BeginEnd(GL.TRIANGLES, function()
			gl.Vertex(cx + d * s * 0.6, cy)
			gl.Vertex(cx - d * s * 0.4, cy + s)
			gl.Vertex(cx - d * s * 0.4, cy - s)
		end)
		gl.Color(1, 1, 1, 1)
	else
		if item.kind == "shape" and font then -- (the four shapes in one size, BORDER's: shrunk alone to its width it
			-- stood smaller than ONE, LINE and GRID beside it, the unfolded Fold7's row of four, dev phone 2026-11-13)
			th = min(th, (r[3] - r[1]) * 0.76 / max(0.01, font:GetTextWidth("BORDER")))
		end
		if cap then -- (an order: its row's size, drawHalf)
			th = min(th, cap)
		end
		-- (TRANSFER: its arrow at the left, the word in the rest)
		local tx0 = item.kind == "transfer" and SP.transferArrow(r) or r[1]
		textIn(label, tx0, r[2], r[3], r[4], th, (item.kind == "none" or item.dim) and "\255\140\140\140"
			or lit and "\255\020\020\020" or "\255\240\240\240", item.kind == "transfer" and bold or font, true)
	end
	if item.color then -- a teammate: their colour along the bottom
		-- (3 pixels at least: the minimum was its top's, so in the split dock's rows, about 70 high, it came out 1 pixel,
		-- a teammate's colour hard to tell; dev phone screenshot 2026-11-17)
		local h = r[4] - r[2]
		local y0 = r[2] + max(3, floor(h * 0.05))
		gl.Color(item.color[1], item.color[2], item.color[3], 0.95)
		gl.Rect(r[1] + 8, y0, r[3] - 8, y0 + max(3, floor(h * 0.05)))
		gl.Color(1, 1, 1, 1)
	end
	local fp = item.kind == "factories" and L.factoryPick
	if fp then -- (FACTORIES cycling: a gold bar along its foot, where a state's lights go, runs out over the pause before
		-- the factory it came to is picked and the dock goes to its screen; the wait was not to be seen)
		local left = max(0, min(1, (fp.at - now()) / fp.wait))
		local bw, bh = r[3] - r[1], r[4] - r[2]
		local m = max(6, floor(bw * 0.06))
		local y = r[2] + max(3, bh * 0.1)
		gl.Color(1, 0.78, 0.25, 0.95)
		gl.Rect(r[1] + m, y, r[1] + m + (bw - 2 * m) * left, y + max(2, bh * 0.06))
		gl.Color(1, 1, 1, 1)
	end
	if item.states and item.states > 1 then -- a state: one light per state along the bottom, as BAR's order menu
		-- (Kailil, 2026-11-13: "In vanilla, red is always on the left. Then green on the right. And yellow in the middle
		-- ... As of now. The lights are staying all to the right side"): the state it is in lit, the first red, the
		-- second yellow (green when there are two), the rest green; the others dark
		local n = item.states
		local cur = min(n, (item.state or 0) + 1)
		local bw, bh = r[3] - r[1], r[4] - r[2]
		local m, g = max(6, floor(bw * 0.06)), max(2, floor(bw * 0.025))
		local sw = (bw - 2 * m - (n - 1) * g) / n
		local y, h = r[2] + max(3, bh * 0.1), max(2, bh * 0.06)
		for i = 1, n do
			if i == cur then
				gl.Color(STATE_COLORS[i == 1 and 1 or (i == 2 and n > 2) and 2 or 3])
			else
				gl.Color(0, 0, 0, 0.4)
			end
			local x = r[1] + m + (i - 1) * (sw + g)
			gl.Rect(x, y, x + sw, y + h)
		end
		gl.Color(1, 1, 1, 1)
	end
end

-- the presets' X a little in from the grid's corner, drawn and pressed there: flush with it, the square sat over the
-- top right preset's rounded corner and border and stood a pixel or two past them (dev phone screenshot 2026-11-16)
function SP.presetsX(r)
	local x = WG.BarDroidPresets.closeRect(r)
	local m = max(3, floor(L.pad * 0.5))
	return { x[1] - m, x[2] - m, x[3] - m, x[4] - m }
end

local function drawHalf(side)
	local r, s, items = half(side)
	if r[3] < 0 then -- (sideways, one thumb: the tab not shown, laid out off the screen)
		return
	end
	-- (the orders of a row in one size, the one its longest word fits at, on one line: on the unfolded Fold7 sideways
	-- "Fire at will" stood shrunk beside "Repeat Off" broken over two larger lines, dev phone screenshot 2026-11-13)
	-- The home grid's rows likewise (the split dock's narrow halves: LOCAL UNITS stood smaller than ALL UNITS beside it,
	-- COMMANDER than BASE, dev phone screenshot 2026-11-16); a word that breaks over two lines there (textIn's wrap, LAST
	-- PINGS) sets no size for the rest of its row. And the pregame's (CLEAR QUEUE smaller than UNDO LAST beside it on
	-- the split dock, dev phone screenshot 2026-11-17)
	local rowCap = {}
	local home = rightKind == "home" or rightKind == "pregame"
	if side ~= "left" and font then
		local wraps = {} -- (the words left out, as breaking over two lines: key, fit)
		for i, item in ipairs(items) do
			-- (PING alone in its place, before the start: as the word "PING")
			local label = item.kind == "pings" and item.pingOnly and "PING" or item.label
			local rect = (item.kind == "order" or home and (item.kind ~= "pings" or item.pingOnly)) and label
				and cellRect(side, i)
			if rect then
				local key = rect[2] .. ":" .. rect[4]
				local th = min((rect[4] - rect[2]) * 0.34, L.btnH * SP.wordsK(item))
				local fit = min(th, (rect[3] - rect[1]) * 0.76 / max(0.01, font:GetTextWidth(label)))
				if item.kind == "order" or fit >= th * 0.7 or not label:find(" ") then
					rowCap[key] = min(rowCap[key] or fit, fit)
				else
					wraps[#wraps + 1] = { key, fit }
				end
			end
		end
		-- (one that fits on one line at its row's smaller size does not break there, textIn: shrunk alone it stood smaller
		-- than the row, CLEAR QUEUE beside UNDO LAST on the split dock once their words were larger, 2026-11-17: the row
		-- at its size)
		for _, w in ipairs(wraps) do
			local cap = rowCap[w[1]]
			if cap and w[2] >= cap * 0.7 then
				rowCap[w[1]] = min(cap, w[2])
			end
		end
	end
	SP.scissor(r[1], r[2], r[3] - r[1], r[4] - r[2])
	for i, item in ipairs(items) do
		local rect = cellRect(side, i)
		if rect and rect[2] < r[4] and rect[4] > r[2] then -- (in sight)
			if side == "left" then
				drawTile(item, rect)
			else
				drawButton(item, rect, (item.kind == "order" or home) and rowCap[rect[2] .. ":" .. rect[4]] or nil)
			end
		end
	end
	gl.Scissor(false)
	if side == "right" and rightKind == "presets" and WG.BarDroidPresets then -- (the presets' X, in the corner)
		local x = SP.presetsX(r)
		button(x, { 0.42, 0.1, 0.08, 0.95 }, { 0.75, 0.25, 0.2, 0.95 })
		textIn("\195\151", x[1], x[2], x[3], x[4], (x[4] - x[2]) * 0.7, "\255\250\240\240", bold)
	end
	-- more rows: a small gold chevron at the edge they come from, its point out in the gap beside the half (all inside
	-- it, it covered the bottom tile's costs and the order's state line in the middle: dev phone, 2026-11-11)
	if s.rows > s.visible then
		local cx = (r[1] + r[3]) / 2
		local h = max(6, floor(L.pad * 1.3))
		local w, out = h * 1.15, max(2, L.pad - 2)
		-- (wholly in the gap, its base a pixel over the half's edge: reaching a third of a pad in, it touched the bottom
		-- tile's cost in the split dock, dev phone 2026-11-15)
		h = max(4, out + 1)
		gl.Color(1, 0.78, 0.25, 0.85)
		if s.pos < snapMax(s) - 0.01 then
			gl.BeginEnd(GL.TRIANGLES, function()
				gl.Vertex(cx - w, r[2] - out + h)
				gl.Vertex(cx + w, r[2] - out + h)
				gl.Vertex(cx, r[2] - out)
			end)
		end
		if s.pos > 0.01 then
			gl.BeginEnd(GL.TRIANGLES, function()
				gl.Vertex(cx - w, r[4] + out - h)
				gl.Vertex(cx + w, r[4] + out - h)
				gl.Vertex(cx, r[4] + out)
			end)
		end
		gl.Color(1, 1, 1, 1)
	end
end

-- the place for the build menu copy's PLACE panel: the right half under the shapes' two rows
local function placeRect()
	if not (active and rightKind == "place") then
		return nil
	end
	local top = L.right[4] - (SP.shapeRow() and 1 or 2) * (L.btnH + L.gap) - L.gap
	return { L.right[1], L.right[2], L.right[3], top }
end

-- the PLACE panel as the copy laid it out in placeRect (its rects are what RtsTouch places from): green, brighter once a
-- tap has picked the spot, rotate and cancel across its bottom
local function drawPlace()
	local B = WG.bardroidBuildmenu
	local p, spot = nil, nil
	if B and B.droidPanel then
		p, spot = B.droidPanel()
	end
	if not p then
		return
	end
	-- (lit too while a GRID from a long press waits: PLACE builds it, as the build menu copy's own panel shows)
	local ready = spot ~= nil or (B.droidPlace and select(5, B.droidPlace()) == true)
	button(p.all, ready and { 0.1, 0.5, 0.1, 1 } or { 0.1, 0.25, 0.1, 1 },
		ready and { 0.25, 0.8, 0.25, 1 } or { 0.2, 0.35, 0.2, 1 })
	-- (upright PLACE is the whole panel: its word clear of rotate and cancel, above them or beside them, wherever it is
	-- the larger: the tall panel above them; the Fold7 unfolded's one-row panel beside them, where the room above them
	-- left a speck of a word, dev phone at 1080x1198 2026-11-11)
	local pl, rot = p.place, p.rotate
	local box = pl
	local below = rot and p.cancel and max(rot[4], p.cancel[4]) or (rot and rot[4]) -- (the X is the taller since 11-11)
	if rot and below > pl[2] and bold then
		local tw = max(0.01, bold:GetTextWidth("PLACE"))
		local function fits(b)
			return min((b[4] - b[2]) * 0.3, (b[3] - b[1]) * 0.88 / tw)
		end
		local above, beside = { pl[1], below, pl[3], pl[4] }, { pl[1], pl[2], rot[1], pl[4] }
		-- (buttons as tall as the panel, a short one: the unfolded Fold7 upright: beside them; centred on the whole
		-- panel the word ran into ROTATE, dev phone at 1080x1198)
		box = (below >= pl[4] or fits(beside) > fits(above)) and beside or above
	end
	-- (a short panel, sideways: the word a larger share of its height; at 0.3 it was a small word in a wide green bar,
	-- dev phone screenshot 2026-11-12)
	local bh = box[4] - box[2]
	textIn("PLACE", box[1], box[2], box[3], box[4], max(bh * 0.3, min(bh * 0.55, 40)),
		ready and "\255\255\255\255" or "\255\205\225\205", bold)
	for _, k in ipairs({ "rotate", "cancel", "walls" }) do
		local r = p[k]
		if r then
			button(r, { 0, 0, 0, 0.55 }, { 0.15, 0.15, 0.15, 0.6 })
		end
		if not r then -- luacheck: ignore 542 -- (no WALLS: not a sentry)
			-- nothing
		elseif k == "walls" then -- (a sentry picked: its walls on, gold and outlined, or off, grey; the host forbidding
			-- widgets' orders: grey, they cannot be given; bardroid_walls.lua, Kailil 2026-11-20)
			local W = WG.BarDroidWalls
			local on = W and W.on() and (not W.allowed or W.allowed())
			local size = max((r[4] - r[2]) * 0.34, min((r[4] - r[2]) * 0.5, 30))
			if bold then
				size = min(size, (r[3] - r[1]) * 0.7 / max(0.01, bold:GetTextWidth("WALLS")))
			end
			textIn("WALLS", r[1], r[2], r[3], r[4], size, on and "\255\255\215\100" or "\255\130\130\130", bold)
			if on and WG.BarDroidStyle then
				WG.BarDroidStyle.outline(r[1], r[2], r[3], r[4], WG.BarDroidStyle.GOLD, 1, max(2, floor((r[3] - r[1]) * 0.03)))
			end
		elseif k == "rotate" then -- (Kailil, 2026-11-11: its arrow read as a redo button; it turns the building 90 degrees, the
			-- game's only turn, so no "90°" on it: "its redundant")
			-- (across half the panel since 2026-11-12: the word at a third of its height, and over 70 % of its width at
			-- most: at the textIn's 84 % upright it ran nearly edge to edge, as large as PLACE above it, dev phone
			-- screenshot 2026-11-13)
			local size = max((r[4] - r[2]) * 0.34, min((r[4] - r[2]) * 0.5, 30))
			if bold then
				size = min(size, (r[3] - r[1]) * 0.7 / max(0.01, bold:GetTextWidth("ROTATE")))
			end
			textIn("ROTATE", r[1], r[2], r[3], r[4], size, "\255\235\235\235", bold)
		else
			-- (the cross fills about half its font size: in a mid-height button, the Fold7 unfolded sideways, it stood
			-- smaller than ROTATE beside it, dev phone at 1192x1080)
			textIn("\226\156\149", r[1], r[2], r[3], r[4], max((r[4] - r[2]) * 0.6, min((r[4] - r[2]) * 0.9, 60)),
				"\255\255\150\140", bold)
		end
	end
	-- (no "tap the map for the spot" under it any more, Kailil 2026-11-10: the panel's dim green says it is waiting)
end

local function drawSelection()
	local r = L.sel
	panel(r)
	local counts = spGetSelectedUnitsCounts() or {}
	local sel = spGetSelectedUnits() or {}
	local n = #sel
	local h = r[4] - r[2]
	local p = floor(h * 0.08)
	if n == 0 then
		-- (before the game: what to do there, the start spot first; BAR's position reads 0,0 until one is picked)
		local sx, _, sz = Spring.GetTeamStartPosition(myTeam())
		local pregameText = pregameStart() and ((sx or 0) <= 0 and (sz or 0) <= 0
			and "START SPOT:  tap the map for yours" or "Start spot picked: queue buildings, then Ready")
		textIn(selecting and ((selStyle == "circle" and "CIRCLE" or "BOX") .. " SELECTION:  a second finger picks a filter")
			or pregameText or "No units picked",
			r[1], r[2] + h * 0.3, r[3], r[4], h * 0.2, "\255\175\175\175") -- (above the camera pad's hint, drawMode)
		return
	end
	local best, bestN = nil, 0
	for d, c in pairs(counts) do
		if d ~= "n" and c > bestN then
			best, bestN = d, c
		end
	end
	if not best then
		return
	end
	unitTile(best, { r[1] + p, r[2] + p, r[1] + h - p, r[4] - p })
	local ud = UnitDefs[best]
	local name = ud and (ud.translatedHumanName or ud.humanName) or ""
	local x = r[1] + floor((r[3] - r[1]) / 3) + L.pad -- (the row's left third is INSERT, its words beside the tile, drawn
	-- live with QUEUE's: drawQueueZones)
	-- (no wider than the room left of QUEUE, on the same line: in the split dock's narrow right block "Advanced
	-- Construction Bot" ran under it and off the screen; review 2026-11-16)
	-- (QUEUE now under the name's line, at the row's middle: the name has the line to the right edge; drawQueueZones)
	local nk = not SP.windOff() and SP.windRects() and L.windNook
	-- ("6 units, 6 of this type" said the same thing twice: all of one type, the count alone)
	local count = n > 1 and (bestN < n and (n .. " units, " .. bestN .. " of this type") or (n .. " units")) or nil
	if nk then
		-- (the wind's and the tide's nook in the name's place at the top, Kailil 2026-11-17: the name on the row's middle
		-- line, left of QUEUE at the same height; the count beside the nook at the top right)
		local qw = bold:GetTextWidth("QUEUE") * h * 0.2
		local room = r[3] - L.pad * 3 - qw - x
		local nameSize = min(h * 0.22, room / max(1, bold:GetTextWidth(name)))
		nameSize = max(h * 0.12, nameSize)
		bold:Print("\255\255\255\255" .. name, x, SP.selLineY(r, nk) - nameSize * 0.35, nameSize, "o")
		if count then
			local cx0, cx1 = nk[3] + L.pad, r[3] - L.pad
			local cs = min(h * 0.17, (cx1 - cx0) / max(1, font:GetTextWidth(count)))
			font:Print("\255\200\200\200" .. count, cx1, (nk[2] + nk[4]) / 2 - cs * 0.35, max(h * 0.1, cs), "ro")
		end
	else
		local room = r[3] - L.pad * 2 - x
		local nameSize = min(h * 0.24, room / max(1, bold:GetTextWidth(name)))
		bold:Print("\255\255\255\255" .. name, x, r[4] - h * 0.36, max(h * 0.12, nameSize), "o")
		if count then
			font:Print("\255\200\200\200" .. count, x, r[4] - h * 0.62, h * 0.17, "o")
		end
	end
	local hp, maxHp = Spring.GetUnitHealth(sel[1])
	if hp and maxHp and maxHp > 0 then
		local x1 = r[3] - L.pad
		local frac = max(0, min(1, hp / maxHp))
		local y0, y1 = r[2] + h * 0.13, r[2] + h * 0.25
		local f = flow()
		if f and f.RectRound and f.RectRoundOutline then
			-- (as the resource bars above it: a dark round track with its outline, the fill shaded from its foot and a
			-- gloss on its top half; green to yellow to red)
			local cr = (y1 - y0) * 0.3
			f.RectRoundOutline(x - 1, y0 - 1, x1 + 1, y1 + 1, cr, 1, 1, 1, 1, 1, { 0, 0, 0, 0.6 }, { 0, 0, 0, 0.6 })
			f.RectRound(x, y0, x1, y1, cr, 1, 1, 1, 1, { 0, 0, 0, 0.5 }, { 0.07, 0.07, 0.07, 0.55 })
			local fx = x + max(cr * 2, (x1 - x) * frac)
			local cR, cG = frac < 0.5 and 1 or (1 - frac) * 2, 0.85 * min(1, frac * 2)
			f.RectRound(x, y0, fx, y1, cr, 1, 1, 1, 1, { cR * 0.55, cG * 0.55, 0.08, 1 }, { cR, cG, 0.15, 1 })
			gl.Blending(GL.SRC_ALPHA, GL.ONE)
			f.RectRound(x, (y0 + y1) / 2, fx, y1, cr, 1, 1, 0, 0, { 1, 1, 1, 0 }, { 1, 1, 1, 0.16 })
			gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
		else
			gl.Color(0.12, 0.12, 0.12, 0.9)
			gl.Rect(x, y0, x1, y1)
			gl.Color(1 - frac, 0.3 + 0.55 * frac, 0.2, 1)
			gl.Rect(x, y0, x + (x1 - x) * frac, y1)
		end
		gl.Color(1, 1, 1, 1)
	end
end

-- metal and energy as BAR's top bar shows them: a bar filled to the storage, the amount and storage, income in green and
-- spending in red
local function short(v)
	v = floor(v + 0.5)
	return v >= 10000 and string.format("%.1fk", v / 1000) or tostring(v)
end
-- The energy box also has BAR's wind and tide indicators, as its top bar draws them (its blades turning with the wind,
-- the speed, the map's range; the waves and the tidal speed where the map has water for tidal generators), which are off
-- upright (Kailil, 2026-11-10: "the wind and wave details widgets should be present in the energy portion. There's
-- plenty of empty space ... make the numbers size bigger ... keep the overall size of the metal and energy boxes")
local BLADES, WAVES = ":n:LuaUI/Images/wind-blades.png", ":n:LuaUI/Images/tidal-waves.png"
local windTurn, tideShown = 0, nil
local function tideRelevant() -- (BAR's top bar's test: water 20 deep somewhere, where tidal generators can stand)
	if tideShown == nil then
		local low = select(3, Spring.GetGroundExtremes()) or 0
		tideShown = (Spring.GetTidal() or 0) > 0 and low - ((Spring.GetModOptions() or {}).map_waterlevel or 0) <= -20
	end
	return tideShown
end
-- The wind's or the tide's reading: its picture turning before the number (behind it, as BAR's top bar has it, the
-- blades' hub sat on the decimal point at this size: "6.5" read "6:5", dev phone 2026-11-10), the wind's range after it
local function indicatorSlot(text, s)
	return s * 0.95 + bold:GetTextWidth(text) * s * 0.62
end
local function indicatorWidth(text, s, extra)
	return indicatorSlot(text, s) + (extra and s * 0.14 + font:GetTextWidth(extra) * s * 0.5 or 0)
end
local function drawIndicator(tex, turn, x, cy, s, text, extra)
	local slot = indicatorSlot(text, s)
	if L.resIcons then -- (drawn into the resource panels' texture: its turning picture drawn live over it, SP.drawRes)
		L.resIcons[#L.resIcons + 1] = { tex, x + s * 0.42, cy, s * 0.42, tex == BLADES }
	else
		gl.Color(1, 1, 1, 0.8)
		gl.Texture(tex)
		gl.PushMatrix()
		gl.Translate(x + s * 0.42, cy, 0)
		gl.Rotate(turn, 0, 0, 1)
		gl.TexRect(-s * 0.42, -s * 0.42, s * 0.42, s * 0.42)
		gl.PopMatrix()
		gl.Texture(false)
		gl.Color(1, 1, 1, 1)
	end
	local size = s * 0.62
	bold:Print("\255\255\255\255" .. text, x + s * 0.95, cy - size * 0.32, size, "o")
	if extra then
		font:Print("\255\185\185\185" .. extra, x + slot + s * 0.14, cy - size * 0.32, s * 0.5, "o")
	end
end
-- metal's and energy's boxes: the two halves of their row, or either side of the wind's and the tide's nook in its middle
function SP.resBoxes()
	local r, pad = L.res, L.pad
	local nk = not SP.windOff() and SP.windRects() and L.windNook
	if nk and nk.kind == "res" then
		local g = max(2, floor(pad * 0.5))
		return { r[1], r[2], nk[1] - g, r[4] }, { nk[3] + g, r[2], r[3], r[4] }
	end
	local w = floor((r[3] - r[1] - pad) / 2)
	return { r[1], r[2], r[1] + w, r[4] }, { r[1] + w + pad, r[2], r[1] + 2 * w + pad, r[4] }
end
local function drawResources()
	local r = L.res
	local mB, eB = SP.resBoxes()
	local h = r[4] - r[2]
	local pad = max(2, floor(h * 0.1))
	local barH = max(3, floor(h * 0.12))
	local rowH = h - 3 * pad - barH -- (the text above a thin bar: the numbers about two fifths bigger than they were)
	local big, small = rowH * 0.92, rowH * 0.62
	-- (the storage on both boxes or neither: sideways in a narrow middle metal showed its own and energy, with longer
	-- flows, not, dev phone 2026-11-12)
	local storageFits = true
	for i, res in ipairs({ "metal", "energy" }) do
		local cur, storage, _, income, expense = Spring.GetTeamResources(myTeam(), res)
		if cur and storage then
			local b = i == 1 and mB or eB
			local x0 = b[1]
			local flows = string.format("\255\120\230\120+%s \255\240\110\100-%s", short(income or 0), short(expense or 0))
			local left = x0 + pad * 1.5 + bold:GetTextWidth(short(cur)) * big + pad * 2 + font:GetTextWidth(flows) * small
				+ pad * 2
			if b[3] - pad * 1.5 - font:GetTextWidth(short(storage)) * small * 0.85 < left then
				storageFits = false
			end
		end
	end
	for i, res in ipairs({ "metal", "energy" }) do
		local cur, storage, _, income, expense, share = Spring.GetTeamResources(myTeam(), res)
		local box = i == 1 and mB or eB
		local x0, x1 = box[1], box[3]
		panel(box)
		if resPanel == res or sharing == res then -- (its panel or picker open: BAR's gold along its top and a little over
			-- it; nothing had said which box the panel below was for, dev phone screenshot 2026-11-17)
			local lw = max(2, floor(pad * 0.4))
			gl.Color(1, 0.78, 0.25, 0.07)
			gl.Rect(x0 + 1, box[2] + 1, x1 - 1, box[4] - 1)
			gl.Color(1, 0.78, 0.25, 0.9)
			gl.Rect(x0 + pad * 2, box[4] - lw - 1, x1 - pad * 2, box[4] - 1)
			gl.Color(1, 1, 1, 1)
		end
		if cur and storage then
			local by0, by1 = r[2] + pad, r[2] + pad + barH
			local frac = storage > 0 and max(0, min(1, cur / storage)) or 0
			gl.Color(0.1, 0.1, 0.1, 0.9)
			gl.Rect(x0 + pad, by0, x1 - pad, by1)
			if res == "metal" then
				gl.Color(0.85, 0.85, 0.85, 1)
			else
				gl.Color(1, 0.86, 0.15, 1)
			end
			gl.Rect(x0 + pad, by0, x0 + pad + (x1 - x0 - 2 * pad) * frac, by1)
			-- (the levels on the bar as BAR's top bar always shows them: energy's conversion grey, the share red over it;
			-- the boxes had the fill alone, the knobs only in the panel. Dev phone, 2026-11-17)
			local mw = max(2, floor(barH * 0.5))
			for m = res == "energy" and 1 or 2, 2 do
				local v = m == 1 and (Spring.GetTeamRulesParam(myTeam(), "mmLevel") or 0.75) or share or 1
				local mx = floor(x0 + pad + (x1 - x0 - 2 * pad) * max(0, min(1, v)) - mw / 2 + 0.5)
				mx = max(x0 + pad, min(x1 - pad - mw, mx))
				gl.Color(0, 0, 0, 0.8)
				gl.Rect(mx - 1, by0 - 1, mx + mw + 1, by1 + 1)
				if m == 1 then
					gl.Color(0.62, 0.62, 0.62, 1)
				else
					gl.Color(0.85, 0, 0, 1)
				end
				gl.Rect(mx, by0 - 1, mx + mw, by1 + 1)
			end
			gl.Color(1, 1, 1, 1)
			local cy = by1 + pad + rowH / 2 -- (the row's middle)
			local amount = short(cur)
			bold:Print((res == "metal" and "\255\225\225\225" or "\255\255\230\080") .. amount, x0 + pad * 1.5,
				cy - big * 0.34, big, "o")
			local flows = string.format("\255\120\230\120+%s \255\240\110\100-%s", short(income or 0), short(expense or 0))
			local fx = x0 + pad * 1.5 + bold:GetTextWidth(amount) * big + pad * 2
			font:Print(flows, fx, cy - small * 0.32, small, "o")
			local left = fx + font:GetTextWidth(flows) * small + pad * 2 -- (where the right side's things must stop)
			local rx = x1 - pad * 1.5
			local sw = font:GetTextWidth(short(storage)) * small * 0.85
			if storageFits and rx - sw >= left then -- (sideways in a narrow middle it ran into the income: left out there)
				font:Print("\255\150\150\150" .. short(storage), rx, cy - small * 0.32, small * 0.85, "ro")
			end
			-- (the wind and the tide: their own boxes above these now, SP.drawWindTide; in the energy box they fitted
			-- only where it was wide, never in the split dock's)
		end
	end
end

-- The wind and the tide in boxes of their own (Kailil, 2026-11-16: "show the wind speed widget just above the eco
-- NUMBERS. it can be outside of the bottom UI anchored to it. it should displa wind speed, and water power generation
-- widget too"): the wind's blades turning, the speed and the map's range; the tide's waves and strength, "NO WATER" where
-- tidal generators cannot stand (BAR's own test). Where (the same day: "Move the widgets to be on top of the idle unit or
-- unit group bar when in unfolded. WHen in landscape folded, Replace the home button with the water tidal widget and
-- wind speed stuff"): unfolded, side by side on the groups between the blocks; sideways folded, one over the other in
-- HOME's place by the minimap; elsewhere over metal and energy, out of the dock and held to it. The wind's, then the
-- tide's rect, or nil. Made once a layout (layout() clears them): drawing, the dock file and the dock's rect ask each frame.
function SP.windRects()
	if L.windW == nil then
		L.windW, L.windT = SP.windRectsNow()
		L.windW = L.windW or false
	end
	if L.windW then
		return L.windW, L.windT
	end
end
function SP.windRectsNow()
	L.windNook = nil -- (set below while they stand in the selection row's nook)
	L.windPill = true -- (one pill, as in the nook, SP.drawPill: everywhere but over metal and energy, at the end)
	local pad, g, r = L.pad or 4, L.groups, L.res
	if not (r and r[3] > r[1]) then
		return nil
	end
	local hh = max(10, floor((r[4] - r[2]) * 0.9)) -- (at 0.72 the reading was small beside the numbers under it)
	if L.split and g then -- (the hole's foot over them: layout's split dock)
		local y0, mid = g[4] + pad, floor((g[1] + g[3]) / 2)
		return { g[1], y0, mid, y0 + hh }, { mid, y0, g[3], y0 + hh }
	elseif L.thumb and L.windCol then -- (one over the other, the wind on top)
		local c = L.windCol
		local mid = floor((c[2] + c[4]) / 2)
		return { c[1], mid, c[3], c[4] }, { c[1], c[2], c[3], mid }
	end
	-- Upright with units picked: side by side in a nook at the selection row's top, where the unit's name was (Kailil,
	-- 2026-11-17, a screenshot with a red box round "Armada Commander": "lets move the wind and tidal widgets to inside of
	-- this red box instead. it will be like a nudge/nook looking thing with the widgets in it. tapping on it shows the same
	-- widget popup"): from the INSERT third's edge to seven tenths across, the name a line lower (drawSelection). Nothing
	-- picked (no selection row; Kailil, the same day: "Nook there too"): a nook as wide in the dock's top edge between
	-- metal and energy, their boxes either side of it (SP.resBoxes), the pill on their row. The two boxes one pill
	-- (SP.drawNook), the nook's top the edge it is sunk from (kind: whose).
	local s = L.sel
	local inset = max(2, floor(pad * 0.6))
	if not L.land and showSel and leftKind ~= "spec" and s and s[3] > s[1] and s[4] > s[2] then
		local h = s[4] - s[2]
		local x0 = s[1] + floor((s[3] - s[1]) / 3) + pad
		local x1 = s[1] + floor((s[3] - s[1]) * 0.70)
		local y1 = s[4] - inset
		local y0 = y1 - floor(h * 0.36)
		local mid = floor((x0 + x1) / 2)
		L.windNook = { x0 - inset, y0 - inset, x1 + inset, s[4], kind = "sel" }
		return { x0, y0, mid, y1 }, { mid, y0, x1, y1 }
	end
	local d = L.dock
	-- (spectating too: they stood over metal and energy as flat boxes, dev phone screenshot of a replay 2026-11-17)
	if not L.land and not showSel and d and d[4] > r[4] then
		local pw = floor((r[3] - r[1]) * (0.70 - 1 / 3)) - pad
		local x0 = floor((r[1] + r[3] - pw) / 2)
		local y0 = floor((r[2] + r[4] - hh) / 2)
		local mid = x0 + floor(pw / 2)
		L.windNook = { x0 - inset, y0 - inset, x0 + pw + inset, d[4], kind = "res" }
		return { x0, y0, mid, y0 + hh }, { mid, y0, x0 + pw, y0 + hh }
	end
	L.windPill = false
	local w, y0 = floor((r[3] - r[1] - pad) / 2), r[4] + pad + max(2, floor(pad * 0.5)) -- (a gap over the dock's edge)
	return { r[1], y0, r[1] + w, y0 + hh }, { r[1] + w + pad, y0, r[1] + 2 * w + pad, y0 + hh }
end
-- the selection row's line under the nook (the name's and QUEUE's): between the health bar's top and the nook's foot
function SP.selLineY(r, nk)
	return (r[2] + (r[4] - r[2]) * 0.25 + nk[2]) / 2
end
-- The nook's look (Kailil, 2026-11-17: "make the Nook sleak and look better, give it a nice look. it looks jank right
-- now"; it was a flat dark box with a hard rim and two boxes in it): a channel sunk from the edge, its foot rounded round
-- the pill's at the same distance, curved shoulders where it leaves the edge, darker under the edge and a faint light on
-- its lower lip; in it the wind and the tide one pill, lit along its top, a hairline between them, the open one's half
-- tinted gold and underlined. Its own round corners: FlowUI's RectRound cuts them straight (BAR's bevel), the pill read
-- as an octagon (dev phone, 2026-11-17).
-- a rounded rect's outline, x and y in turn, its corners' radii tl, tr, br, bl (0: square)
function SP.roundPath(x0, y0, x1, y1, rtl, rtr, rbr, rbl)
	local pts, n, q = {}, 8, math.pi / 2
	for _, c in ipairs({ { x1 - rtr, y1 - rtr, rtr, 0 }, { x0 + rtl, y1 - rtl, rtl, q }, { x0 + rbl, y0 + rbl, rbl, 2 * q },
		{ x1 - rbr, y0 + rbr, rbr, 3 * q } }) do
		for i = 0, c[3] > 0 and n or 0 do
			local t = c[4] + q * i / n
			pts[#pts + 1] = c[1] + c[3] * math.cos(t)
			pts[#pts + 1] = c[2] + c[3] * math.sin(t)
		end
	end
	return pts
end
-- a shoulder: the corner where the channel leaves the edge, filled out to an arc from the edge down its side (s: 1 the
-- left one, -1 the right one)
function SP.shoulderPath(x, y, rs, s)
	local pts, n, q = { x, y }, 8, math.pi / 2
	for i = 0, n do
		local t = q * i / n
		pts[#pts + 1] = x - s * rs + s * rs * math.cos(t)
		pts[#pts + 1] = y - rs + rs * math.sin(t)
	end
	return pts
end
function SP.fanColor(c1, c2, t)
	t = max(0, min(1, t))
	gl.Color(c1[1] + (c2[1] - c1[1]) * t, c1[2] + (c2[2] - c1[2]) * t, c1[3] + (c2[3] - c1[3]) * t,
		c1[4] + (c2[4] - c1[4]) * t)
end
-- gl.BeginEnd's fan over an outline: from its first point (center: from b's middle), c1 at b's foot to c2 at its top, dy
-- lower
function SP.fan(pts, b, dy, c1, c2, center)
	local y0, span = b[2], max(1, b[4] - b[2])
	if center then
		SP.fanColor(c1, c2, 0.5)
		gl.Vertex((b[1] + b[3]) / 2, (b[2] + b[4]) / 2 - dy)
	end
	for i = 1, #pts, 2 do
		SP.fanColor(c1, c2, (pts[i + 1] - y0) / span)
		gl.Vertex(pts[i], pts[i + 1] - dy)
	end
	if center then
		SP.fanColor(c1, c2, (pts[2] - y0) / span)
		gl.Vertex(pts[1], pts[2] - dy)
	end
end
SP.NOOK_C = {
	lip0 = { 1, 1, 1, 0.12 }, lip1 = { 1, 1, 1, 0 }, -- (the lower lip's light: the channel drawn a little lower first)
	well0 = { 0, 0, 0, 0.45 }, well1 = { 0, 0, 0, 0.82 },
	edge = { 1, 1, 1, 0.16 }, -- (the pill's top lit: the pill drawn a pixel higher first)
	pill0 = { 0.075, 0.08, 0.09, 1 }, pill1 = { 0.165, 0.17, 0.185, 1 },
	gold0 = { 1, 0.78, 0.25, 0.06 }, gold1 = { 1, 0.78, 0.25, 0.22 },
}
function SP.drawNook(nk, wb, tb)
	local C = SP.NOOK_C
	local pad = L.pad or 4
	if not nk.body then -- (made once a layout: the nook is made again with it)
		local rp = floor((wb[4] - wb[2]) * 0.3)
		local rw = min(rp + (wb[1] - nk[1]), floor((nk[4] - nk[2]) / 2), floor((nk[3] - nk[1]) / 2))
		local rs = max(3, floor(pad * 0.9))
		nk.body = SP.roundPath(nk[1], nk[2], nk[3], nk[4], 0, 0, rw, rw)
		nk.shL = SP.shoulderPath(nk[1], nk[4], rs, 1)
		nk.shR = SP.shoulderPath(nk[3], nk[4], rs, -1)
	end
	gl.Texture(false)
	local fan, TF = SP.fan, GL.TRIANGLE_FAN
	gl.BeginEnd(TF, fan, nk.body, nk, max(1, floor(pad * 0.2)), C.lip0, C.lip1, true)
	gl.BeginEnd(TF, fan, nk.body, nk, 0, C.well0, C.well1, true)
	gl.BeginEnd(TF, fan, nk.shL, nk, 0, C.well1, C.well1)
	gl.BeginEnd(TF, fan, nk.shR, nk, 0, C.well1, C.well1)
	SP.drawPill(wb, tb, nk)
end
-- the wind and the tide as one pill: side by side (in the nook, and unfolded on the groups between the blocks) or one
-- over the other (sideways folded, in HOME's place); its outlines kept in cache (a table made again with the layout)
function SP.drawPill(wb, tb, cache)
	local C = SP.NOOK_C
	local ph = wb[4] - wb[2]
	local up = tb[4] <= wb[2] + 1
	local rp = floor(min(ph, wb[3] - wb[1]) * 0.3)
	local pb = cache.pb
	if not pb then
		if up then
			pb = { wb[1], tb[2], wb[3], wb[4] }
			cache.wind = SP.roundPath(wb[1], wb[2], wb[3], wb[4], rp, rp, 0, 0)
			cache.tide = SP.roundPath(tb[1], tb[2], tb[3], tb[4], 0, 0, rp, rp)
		else
			pb = { wb[1], wb[2], tb[3], wb[4] }
			cache.wind = SP.roundPath(wb[1], wb[2], wb[3], wb[4], rp, 0, 0, rp)
			cache.tide = SP.roundPath(tb[1], tb[2], tb[3], tb[4], 0, rp, rp, 0)
		end
		cache.pb = pb
		cache.pill = SP.roundPath(pb[1], pb[2], pb[3], pb[4], rp, rp, rp, rp)
	end
	gl.Texture(false)
	local fan, TF = SP.fan, GL.TRIANGLE_FAN
	gl.BeginEnd(TF, fan, cache.pill, pb, -1, C.edge, C.edge, true)
	gl.BeginEnd(TF, fan, cache.pill, pb, 0, C.pill0, C.pill1, true)
	local info = SP.windInfo
	local kind = info and info.kind
	local lit = kind == "wind" and wb or kind == "tide" and tb
	if lit then
		gl.BeginEnd(TF, fan, cache[kind], lit, 0, C.gold0, C.gold1, true)
		local u = max(2, floor(ph * 0.05))
		gl.Color(1, 0.8, 0.3, 0.95)
		gl.Rect(lit[1] + rp, lit[2] + u, lit[3] - rp, lit[2] + 2 * u)
	end
	gl.Color(1, 1, 1, 0.14) -- (the hairline between them)
	if up then
		local my, pw = floor(wb[2]), pb[3] - pb[1]
		gl.Rect(pb[1] + floor(pw * 0.18), my, pb[3] - floor(pw * 0.18), my + 1)
	else
		local mx = floor(wb[3])
		gl.Rect(mx, pb[2] + floor(ph * 0.22), mx + 1, pb[4] - floor(ph * 0.22))
	end
	resetGL()
end
-- The nook's and the pill's shapes, the same few hundred vertices every frame (0.2 ms of the boxes' 0.4-0.6 a frame on
-- the dev phone, release overhaul item 7): a display list, the same calls played back, made again when the layout makes
-- their rects anew (wb, with the nook) or another box is lit
function SP.windBack(nk, wb, tb)
	local kind = SP.windInfo and SP.windInfo.kind or ""
	local B = SP.windBackDL
	if not (B and B.wb == wb and B.kind == kind) then
		if B and B.id then
			gl.DeleteList(B.id)
		end
		B = { wb = wb, kind = kind, id = gl.CreateList(function()
			if nk then
				SP.drawNook(nk, wb, tb)
			else
				SP.drawPill(wb, tb, wb)
			end
		end) }
		SP.windBackDL = B
	end
	if B.id then
		gl.CallList(B.id)
	elseif nk then -- (no list: drawn as they are)
		SP.drawNook(nk, wb, tb)
	else
		SP.drawPill(wb, tb, wb)
	end
end
-- Drawn live: a few rectangles and words; the box whose details are open lit gold
function SP.drawWindTide()
	local wb, tb = SP.windRects()
	if not wb then
		return
	end
	local nk = L.windNook
	local pill = nk or L.windPill
	if pill then
		SP.windBack(nk, wb, tb)
	end
	for i, box in ipairs({ wb, tb }) do
		local hh, bw = box[4] - box[2], box[3] - box[1]
		local s = hh * 0.86
		if not pill then
			panel(box, nil, nil, nil, nil, true) -- (opaque: the game's metal spot rings showed through, over the reading)
			if SP.windInfo and SP.windInfo.kind == (i == 1 and "wind" or "tide") then
				gl.Color(1, 0.8, 0.25, 0.18)
				gl.Rect(box[1], box[2], box[3], box[4])
				gl.Color(1, 1, 1, 1)
			end
		end
		local cy, px = box[2] + hh / 2, box[1] + max(3, floor(hh * 0.18))
		local small = min(hh * 0.42, bw * 0.16)
		if i == 1 then
			if (Game.windMax or 0) > 0 then
				local range = floor(Game.windMin or 0) .. "-" .. floor(Game.windMax or 0)
				-- (before the game starts there is no wind yet: its range alone, as BAR's top bar shows only its minimum and
				-- maximum then; "0.0" read as a windless map while the start was picked, dev phone pregame 2026-11-16)
				local started = Spring.GetGameFrame() > 0
				local wind = started and string.format("%.1f", select(4, Spring.GetWind()) or 0) or range
				local extra = started and range or nil
				local room = box[3] - 3 - px
				s = min(s, s * room / indicatorWidth(wind, s)) -- (narrow, in HOME's place: smaller, the range left out)
				local fits = extra and px + indicatorWidth(wind, s, extra) <= box[3] - 3
				-- (in the middle of its box, as NO WATER beside it: at the left the wide box upright was mostly empty)
				px = max(px, floor((box[1] + box[3] - indicatorWidth(wind, s, fits and extra or nil)) / 2))
				drawIndicator(BLADES, windTurn, px, box[2] + hh / 2, s, wind, fits and extra or nil)
			else
				textIn("NO WIND", box[1], box[2], box[3], box[4], small, "\255\150\150\150", font)
			end
		elseif tideRelevant() then
			local tide = tostring(floor(Spring.GetTidal() or 0))
			drawIndicator(WAVES, 0, max(px, floor((box[1] + box[3] - indicatorWidth(tide, s)) / 2)), cy, s, tide)
		else
			textIn("NO WATER", box[1], box[2], box[3], box[4], small, "\255\150\150\150", font)
		end
	end
	gl.Color(1, 1, 1, 1)
end
-- not shown: the dock hidden, or the D-gun mode's sticks and FIRE where they stand (drawDock)
function SP.windOff()
	return SP.hidden or (rightKind == "dgun" and (L.land or L.dgFloat))
end
-- the dock's rect with the wind and the tide over metal and energy, up to their top: for the fingers (RtsTouch's "dock")
-- and for the other widgets (WG.BarDroidPortrait.dock and onDock: BAR's replay speeds went under the wind's box, dev
-- phone 2026-11-16, a replay spectated upright). The same table while the dock and the boxes stay (asked each frame).
function SP.dockAll()
	local d = L.dock
	local wb = d and not (L.split or L.thumb or SP.windOff()) and SP.windRects()
	if not (wb and wb[4] > d[4]) then
		return d
	end
	local c = L.dockAllR
	if not (c and c.d == d and c.w == wb) then
		c = { d[1], d[2], d[3], wb[4], d = d, w = wb }
		L.dockAllR = c
	end
	return c
end
-- their boxes take the first tap (RtsTouch's "live"): the details open at once, the camera pad up or not
function SP.windLive(r)
	local wb, tb
	if not SP.windOff() then
		wb, tb = SP.windRects()
	end
	return wb and ("live " .. r(wb) .. "\nlive " .. r(tb) .. "\n") or ""
end

-- A tap on the wind's box shows what BAR's top bar shows for a mouse over its wind (Kailil, 2026-11-16: "when pressing
-- the wind speed widget, it should display the same info that the vanilla one does, like telling us how much of the time,
-- the windspeed will be at the lowest number"): its average, minimum, maximum, the share of the time under 6 and its
-- advice, in its words, over a graph of the last five minutes; the tide's, its strength and its words. Any tap closes it.
-- (the second: the words where BAR's are missing, BAR's own English of test-31958: a replay of an October game, its BAR
-- without the minimap's, read "Average", "Under 6" where the game's read "Average speed", "Time below 6"; dev phone
-- 2026-11-17)
SP.WIND_WORDS = {
	title = { "ui.topbar.windspeed", "Wind Speed" }, avg = { "ui.minimap.windAverage", "Average speed" },
	min = { "ui.minimap.windMinimum", "Minimum speed" }, max = { "ui.minimap.windMaximum", "Maximum speed" },
	low = { "ui.minimap.windLow", "Time below 6" }, note = { "ui.minimap.windAdvice" },
	none = { "ui.topbar.wind.nowind1", "None" },
	tide = { "ui.topbar.tidalspeed", "Tidal Speed" }, tideNote = { "ui.topbar.tidalspeedTooltip" },
}
function SP.windWord(k)
	local w = SP.WIND_WORDS[k]
	return tr(w[1]) or w[2]
end
-- BAR's numbers (common/wind_functions.lua, as its top bar): the average from its table, else its guess; the share of
-- the time under 6 from its table; nil where its file is missing
function SP.windFacts()
	if SP.windF == nil then
		local ok, wf = pcall(VFS.Include, "common/wind_functions.lua")
		SP.windF = ok and type(wf) == "table" and wf or false
		if not SP.windF then
			Spring.Echo("[bardroid-portrait] BAR's wind table not found: " .. tostring(wf)) -- (tools)
		end
	end
	local lo, hi, wf = Game.windMin or 0, Game.windMax or 0, SP.windF
	local t = wf and wf.averageWindLookup
	local ok, risk = pcall(function()
		return wf and wf.getWindRisk and wf.getWindRisk()
	end)
	return t and t[lo] and t[lo][hi] or ("~" .. tostring(max(lo, hi * 0.75))), ok and risk or nil, lo, hi
end
-- the graph's samples, as BAR's top bar takes them: every 150 frames, the last five minutes
SP.windHist = { f = {}, v = {} }
function SP.windSample()
	local n = Spring.GetGameFrame()
	local H = SP.windHist
	if n <= 0 or n < (H.next or 0) or (Game.windMin or 0) + (Game.windMax or 0) < 0.5 then
		return
	end
	H.next = n - n % 150 + 150
	H.f[#H.f + 1], H.v[#H.v + 1] = n, select(4, Spring.GetWind()) or 0
	local from = n - 300 * Game.gameSpeed
	while #H.f > 2 and H.f[1] < from do
		table.remove(H.f, 1)
		table.remove(H.v, 1)
	end
end
function SP.drawWindInfo()
	local info = SP.windInfo
	if not info then
		return
	end
	if now() - info.at > 15 then -- (a tap that never reached the widget: it goes by itself)
		SP.windInfo = nil
		return
	end
	local wind = info.kind == "wind"
	local wb, tb = SP.windRects() -- (its box where it stands now: a fold, a turn or a swap moves it; the tapped one's
	if SP.windOff() or not wb then -- place kept the panel over nothing for its 15 s)
		SP.windInfo = nil
		return
	end
	info.box = wind and wb or tb
	local fs = max(13, min(30, floor(min(vsx, vsy) * 0.024)))
	local pad, rowH, dim = max(6, floor(fs * 0.6)), floor(fs * 1.5), "\255\170\176\174"
	local W = min(vsx - 2 * (L.pad or 4), floor(fs * 17))
	local lo0, hi0 = L.pad or 4, vsx - (L.pad or 4) -- (where it may stand: unfolded, in the gap between the blocks; wider, it
	if L.split and L.hole then -- covered the build grid and metal and energy, dev phone at 1080x1198)
		lo0, hi0 = L.hole[1] + L.pad, L.hole[3] - L.pad
		W = min(W, hi0 - lo0)
	end
	local avg, risk, lo, hi = SP.windFacts()
	local rows
	if wind then
		local none = lo + hi < 0.5
		rows = { { SP.windWord("avg"), none and SP.windWord("none") or avg }, { SP.windWord("min"), lo, true },
			{ SP.windWord("max"), hi, true }, { SP.windWord("low"), risk and (risk .. "%") or "-", true } }
	else -- (the tide's strength on its title's line: as a row its name stood twice, dev phone 2026-11-16)
		rows = {}
	end
	local note = SP.windWord(wind and "note" or "tideNote")
	local noteFs, lines = fs * 0.82, {}
	if note then
		note = note:gsub("%s*\n%s*", " ") -- (BAR's own line break, for its tooltip's width: "average" alone on a line here)
		local ok, wrapped = pcall(font.WrapText, font, note, W - 2 * pad, nil, noteFs)
		for line in tostring(ok and wrapped or note):gmatch("[^\n]+") do
			lines[#lines + 1] = line
		end
	end
	local H = SP.windHist
	local graph = wind and #H.f >= 2 and hi > lo
	local graphH, axisFs = floor(fs * 3), fs * 0.68
	local height = pad * 2 + rowH * (1 + #rows) + (#lines > 0 and (#lines * noteFs * 1.2 + pad * 0.5) or 0)
		+ (graph and (graphH + axisFs * 1.6 + pad) or 0)
	local b = info.box
	-- (over the box; folded sideways, and from either nook, over the dock: over the nook in the selection row it covered
	-- metal and energy, dev phone 2026-11-17)
	local base = ((L.thumb or L.windNook) and L.dock and L.dock[4] or b[4]) + (L.pad or 4)
	local x0 = max(lo0, min(hi0 - W, floor((b[1] + b[3]) / 2 - W / 2)))
	local r = { x0, base, x0 + W, base + floor(height) }
	info.rect = r
	panel(r, nil, nil, nil, nil, true) -- (opaque, as its boxes: the game's metal spot rings sat on its numbers)
	local y = r[4] - pad
	bold:Print("\255\255\255\255" .. SP.windWord(wind and "title" or "tide"), r[1] + pad, y - rowH * 0.5, fs * 1.1, "ov")
	if not wind then
		local tidal = tideRelevant() -- (NO WATER grey, as in its box: in white it read as a value)
		bold:Print(tidal and "\255\255\255\255" .. floor(Spring.GetTidal() or 0) or "\255\150\150\150NO WATER",
			r[3] - pad, y - rowH * 0.5, fs * 1.1, "orv")
	end
	y = y - rowH
	for i, row in ipairs(rows) do
		if i % 2 == 1 then -- (BAR's tooltip's stripes)
			gl.Color(1, 1, 1, 0.05)
			gl.Rect(r[1] + pad * 0.5, y - rowH, r[3] - pad * 0.5, y)
			gl.Color(1, 1, 1, 1)
		end
		font:Print((row[3] and dim or "\255\235\235\235") .. row[1], r[1] + pad, y - rowH * 0.5, fs, "ov")
		bold:Print((row[3] and "\255\210\210\210" or "\255\255\255\255") .. tostring(row[2]), r[3] - pad, y - rowH * 0.5, fs,
			"orv")
		y = y - rowH
	end
	if #lines > 0 then
		y = y - pad * 0.5
		for _, line in ipairs(lines) do
			font:Print(dim .. line, r[1] + pad, y - noteFs * 0.6, noteFs, "ov")
			y = y - noteFs * 1.2
		end
	end
	if graph then
		local top = y - pad
		local bottom = top - graphH
		local left, right = r[1] + pad + font:GetTextWidth(tostring(hi)) * axisFs + pad * 0.6, r[3] - pad
		gl.Color(1, 1, 1, 0.1)
		gl.Rect(left, top - 1, right, top)
		gl.Rect(left, bottom, right, bottom + 1)
		gl.Color(1, 1, 1, 1)
		font:Print(dim .. hi, left - pad * 0.5, top, axisFs, "orv")
		font:Print(dim .. "0", left - pad * 0.5, bottom, axisFs, "orv")
		font:Print(dim .. "-5:00", left, bottom - axisFs * 0.85, axisFs, "ov")
		font:Print(dim .. "0:00", right, bottom - axisFs * 0.85, axisFs, "orv")
		local span, from = 300 * Game.gameSpeed, H.f[#H.f] - 300 * Game.gameSpeed
		local sx, sy = (right - left) / span, (top - bottom) / max(1, hi)
		gl.BeginEnd(GL.TRIANGLE_STRIP, function() -- (BAR's fill: fading down to the axis)
			for i = 1, #H.f do
				local x, v = left + max(0, H.f[i] - from) * sx, min(hi, H.v[i])
				gl.Color(0.96, 0.96, 0.96, 0)
				gl.Vertex(x, bottom)
				gl.Color(0.96, 0.96, 0.96, 0.28 * v / max(1, hi))
				gl.Vertex(x, bottom + v * sy)
			end
		end)
		gl.LineWidth(max(1, fs * 0.08))
		gl.Color(0.96, 0.96, 0.96, 1)
		gl.BeginEnd(GL.LINE_STRIP, function()
			for i = 1, #H.f do
				gl.Vertex(left + max(0, H.f[i] - from) * sx, bottom + min(hi, H.v[i]) * sy)
			end
		end)
		gl.LineWidth(1)
	end
	gl.Color(1, 1, 1, 1)
end

-- BAR's top bar's own resource bars: off while the screen is upright (the dock shows them; a spectator has no dock, and
-- upright they ran over the top bar's numbers and buttons there too, 2026-11-09), back once it is not
local resBarsHidden = false
local function upright()
	local x, y = Spring.GetViewGeometry()
	return y > x * PORTRAIT
end
-- Its indicators too (wind, tide, the commander counts): BAR places them by the screen's width while its buttons go by
-- their own, so upright they sat over Statistics, Settings and Quit; the dock's energy panel shows the wind instead.
local indicatorsHidden = false
local function topbarBars(dockUp)
	local tb = WG.topbar
	if not tb then
		return
	end
	if tb.setResourceBarsVisible and tb.getResourceBarsVisible then
		if dockUp and tb.getResourceBarsVisible() then -- (also when BAR shows them again, at the game's start)
			tb.setResourceBarsVisible(false)
			resBarsHidden = true
		elseif not dockUp and resBarsHidden then
			tb.setResourceBarsVisible(true)
			resBarsHidden = false
		end
	end
	if tb.setIndicatorsVisible and tb.getIndicatorsVisible then
		if dockUp and tb.getIndicatorsVisible() then
			tb.setIndicatorsVisible(false)
			indicatorsHidden = true
		elseif not dockUp and indicatorsHidden then
			tb.setIndicatorsVisible(true)
			indicatorsHidden = false
		end
	end
end

-- nothing picked: the control groups as pictures along the bottom (Kailil: "touch friendly unit groups by keeping
-- unit groups in pictures at the bottom whenever no unit is slected"); a tap picks a group
local function drawGroups()
	L.groupRects = {}
	local r = L.groups
	panel(r)
	-- the remove-order buttons at the strip's right end (unqShown): the first or the last order of the units picked, or
	-- of a factory's build queue (removeOrder)
	local x1 = r[3]
	if unqShown then
		local h = r[4] - r[2]
		-- (in the split dock's narrow middle no wider than a fifth of it each: at 1.7 heights the pair left one group in
		-- sight upright)
		local bw = floor(L.split and min(h * 1.7, max(h, (r[3] - r[1]) * 0.22)) or h * 1.7)
		for i, which in ipairs({ "first", "last" }) do
			local b = { r[3] - (3 - i) * bw + 3, r[2] + 3, r[3] - (2 - i) * bw - 3, r[4] - 3, unq = which }
			L.groupRects[#L.groupRects + 1] = b
			button(b, { 0.3, 0.09, 0.08, 0.9 }, { 0.46, 0.13, 0.11, 0.9 })
			-- (the cross larger than the word, as NEW's plus is: at the word's size it was a speck before FIRST and LAST,
			-- dev phone screenshot 2026-11-13; the pair centred, shrunk together where the button is narrow)
			local f, word, c = bold or font, which:upper(), "\255\255\228\218"
			if f then
				local size, xs = h * 0.26, h * 0.44
				local ww, xw, gap = f:GetTextWidth(word) * size, f:GetTextWidth("\195\151") * xs, size * 0.3
				local fit = min(1, (b[3] - b[1]) * 0.8 / (ww + xw + gap))
				size, xs, ww, xw, gap = size * fit, xs * fit, ww * fit, xw * fit, gap * fit
				local x0, cy = (b[1] + b[3] - (ww + xw + gap)) / 2, (b[2] + b[4]) / 2
				f:Print(c .. "\195\151", x0, cy - xs * 0.27, xs, "o")
				f:Print(c .. word, x0 + xw + gap, cy - size * 0.32, size, "o")
			end
		end
		x1 = r[3] - 2 * bw
	end
	local groups = Spring.GetGroupList() or {}
	local list = {}
	for g, c in pairs(groups) do
		if c > 0 then
			list[#list + 1] = g
		end
	end
	table.sort(list)
	local h = r[4] - r[2]
	-- the group whose units are exactly the ones picked: marked as in use (a recalled group showed nothing on its tile)
	local sel = spGetSelectedUnits() or {}
	local current = #sel > 0 and Spring.GetUnitGroup(sel[1]) or nil
	if current and groups[current] ~= #sel then
		current = nil
	end
	for i = 2, current and #sel or 0 do
		if Spring.GetUnitGroup(sel[i]) ~= current then
			current = nil
			break
		end
	end
	-- units picked: a "+ NEW" tile after the groups puts their types in the next free group (BAR's auto groups: a
	-- number held by an auto group's type with no unit left is not free)
	local free
	if #sel > 0 then
		local taken = {}
		local A = WG.autogroup
		for _, gr in pairs(A and A.getGroups and A.getGroups() or {}) do
			taken[tonumber(gr) or -1] = true
		end
		for n = 1, 9 do
			if (not groups[n] or groups[n] == 0) and not taken[n] then
				free = n
				break
			end
		end
	end
	local idle = idleB.list
	if #list == 0 and not free and #idle == 0 then
		textIn("Groups: pick units, then + NEW here", r[1], r[2], x1, r[4], h * 0.24, "\255\140\140\140")
		return
	end
	-- The row's tiles (Kailil, 2026-11-11): the groups and + NEW from the left, the idle builders from the right, up to
	-- the remove-order buttons; each side takes the other's room as it grows, and past the row's width it scrolls
	-- sideways ("dockscroll groups" from RtsTouch, idleB.scroll), the groups first
	local w = h
	local nLeft = #list + (free and 1 or 0)
	local room = x1 - r[1]
	local over = max(0, (nLeft + #idle) * w - room)
	if over > 0 then -- (scrolling: the tiles a little wider, a whole number of them fills the room; at rest no tile is cut,
		-- Kailil's "Do not allow scroll to half reveal objects", idleB.fling)
		w = room / max(1, floor(room / h))
		over = (nLeft + #idle) * w - room
	end
	if idleB.tileW and idleB.tileW ~= w and not idleB.snapTo then -- (the room changed, the remove buttons came or went:
		-- the same first tile in sight)
		idleB.scroll = floor(idleB.scroll / idleB.tileW + 0.5) * w
	end
	idleB.tileW, idleB.over = w, over
	idleB.scroll = max(0, min(over, idleB.scroll))
	local off = r[1] - idleB.scroll
	local function place(x0, extra) -- a tile's rect, and the part of it in sight for the taps (nil: none)
		local t = { x0 + 3, r[2] + 3, x0 + w - 3, r[4] - 3 }
		for k, v in pairs(extra) do
			t[k] = v
		end
		if t[3] > r[1] and t[1] < x1 then
			local hit = { max(t[1], r[1]), t[2], min(t[3], x1), t[4] }
			for k, v in pairs(extra) do
				hit[k] = v
			end
			L.groupRects[#L.groupRects + 1] = hit
		end
		return t
	end
	SP.scissor(r[1], r[2], max(0, room), h)
	if free then
		local nr = place(off + #list * w, { new = free })
		button(nr, { 0.2, 0.2, 0.2, 0.8 }, { 0.32, 0.32, 0.32, 0.8 })
		textIn("+", nr[1], nr[2] + h * 0.3, nr[3], nr[4], h * 0.42, "\255\255\200\064", bold)
		-- (as large as the tiles' counts beside it, bold: at a fifth of the row in the plain font it was the row's
		-- smallest words, 14 pixels on the folded Fold7 sideways; dev phone screenshot 2026-11-17)
		textIn("NEW " .. free, nr[1], nr[2], nr[3], nr[2] + h * 0.4, h * 0.25, "\255\225\225\225", bold)
	end
	for i, g in ipairs(list) do
		local gr = place(off + (i - 1) * w, { group = g })
		local best, bestN = nil, 0
		for d, c in pairs(Spring.GetGroupUnitsCounts(g) or {}) do
			if type(d) == "number" and c > bestN then -- (the counts carry their total as "n")
				best, bestN = d, c
			end
		end
		if best then
			unitTile(best, gr, g == current)
		else
			button(gr)
		end
		-- (the number on a dark badge in the corner: gold straight on the picture all but vanished on the commander's
		-- yellow trim and the sand behind it, dev phone screenshot 2026-11-18)
		local ns, pad = h * 0.26, max(2, floor(h * 0.06))
		local bx0, by1 = gr[1] + pad * 0.5, gr[4] - pad * 0.5
		local bx1, by0 = bx0 + bold:GetTextWidth(tostring(g)) * ns + 2 * pad, gr[4] - h * 0.36
		local f = flow()
		if f and f.RectRound then
			f.RectRound(bx0, by0, bx1, by1, pad, 1, 1, 1, 1, { 0, 0, 0, 0.62 }, { 0, 0, 0, 0.62 })
		else
			gl.Color(0, 0, 0, 0.62)
			gl.Rect(bx0, by0, bx1, by1)
		end
		resetGL()
		bold:Print("\255\255\200\064" .. g, bx0 + pad, gr[4] - h * 0.3, ns, "o")
		bold:Print("\255\255\255\255" .. groups[g], gr[3] - 6, gr[2] + 6, h * 0.2, "ro")
	end
	-- the idle builders: right against the remove buttons while all fits, else straight after the groups
	local first = over > 0 and (off + nLeft * w) or (x1 - #idle * w)
	for j, e in ipairs(idle) do
		local ir = place(first + (j - 1) * w, { idle = e.def })
		unitTile(e.def, ir, false)
		bold:Print("\255\255\255\255" .. #e.units, ir[3] - 6, ir[2] + 6, h * 0.26, "ro") -- (how many of it are idle)
	end
	gl.Scissor(false)
end

-- the mode: the camera pad dims the dock a little and names itself; the open menu has BAR's gold along its top,
-- a pulse as it opens (Kailil: "a quick blink or sparkle or something that fits the BAR aesthetic"), and the time it
-- has left before the pad comes back
local function drawMode()
	local d = L.dock
	local t = now()
	if not menu then
		gl.Color(0, 0, 0, 0.32)
		for _, r in ipairs(SP.around(d, L.hole)) do -- (sideways the minimap not dimmed: it takes taps either way)
			gl.Rect(r[1], r[2], r[3], r[4])
		end
		gl.Color(1, 1, 1, 1)
		-- (no "CAMERA PAD" on the selection row any more: it sat in the QUEUE button's corner, Kailil 2026-11-16: "remove
		-- the camera pad label in the QUEUE button"; the dimmed dock says the mode alone)
		return
	end
	local age = t - menuAt
	local edge = max(2, floor(L.pad * 0.3))
	-- (unfolded, the split dock: on each block, not across the game between them; the line ran over it, dev phone
	-- sideways at 1080x1198)
	local blocks = L.split and L.splitL and L.splitR and { L.splitL, L.splitR } or { d }
	local left = SP.held() and 1 or max(0, 1 - (t - lastTouch) / MENU_SECONDS) -- (placing, picking: no clock)
	for _, b in ipairs(blocks) do
		if age < BLINK then -- two quick pulses of light over the dock, gold at its top edge
			local a = math.sin(age / BLINK * math.pi * 2) ^ 2
			gl.Color(1, 0.9, 0.6, 0.16 * a)
			gl.Rect(b[1], b[2], b[3], b[4])
			gl.Color(1, 0.82, 0.35, 0.9 * a)
			gl.Rect(b[1], b[4] - edge * 3, b[3], b[4])
		end
		gl.Color(1, 0.78, 0.25, 0.85)
		gl.Rect(b[1], b[4] - edge, b[1] + (b[3] - b[1]) * left, b[4])
	end
	gl.Color(1, 1, 1, 1)
end

---------------------------------------------------------------------------------------------------------------------
-- The app's lines in the touch log (RtsTouch): only the dock's are read here; bardroid_touch.lua reads the rest. One
-- handle; the size is looked at every 30 reads (the app starts a new, shorter log now and then).

local logFile, logPos, logCalls = nil, 0, 0
local function newLines()
	if not logFile then
		logFile = io.open(TOUCH_LOG, "r")
		logPos = logFile and logFile:seek("end") or 0
		return nil
	end
	logCalls = logCalls + 1
	-- (and every call once past 256 KB, RtsTouch.LOG_RESTART_BYTES, where the app begins the log anew after a lift: a
	-- second's lines were held back till the 30th call; release overhaul audit, 2026-11-21)
	if logCalls % 30 == 0 or logPos >= 262144 then
		local size = logFile:seek("end")
		if not size then
			logFile:close()
			logFile = nil
			return nil
		end
		if size < logPos then
			logPos = 0
		end
	end
	if not logFile:seek("set", logPos) then
		return nil
	end
	local text = logFile:read("*a") or ""
	local last = text:match(".*()\n")
	if not last then
		return nil
	end
	logPos = logPos + last
	return text:sub(1, last)
end

-- HIDE and SHOW (spectating, SP): the dock folded to its SHOW button or open again, laid out and told to RtsTouch
function SP.setHidden(on)
	SP.hidden, SP.teams = on, false
	if on then
		setMenu(false)
	end
	SP.hiddenAt = on and Spring.GetTimer() or nil -- (the HIDE tap's own dock_menu line comes after it: act below)
	-- BAR's player list with it (Kailil, 2026-11-11: "Hide the team list"; up, the dock covers it): the phone engine's
	-- phone version of BAR's list has SetHidden (phone-widget-gui_advplayerslist.lua.patch); BAR's own has not
	local api = WG.advplayerlist_api
	if api and api.SetHidden then
		api.SetHidden(on)
	end
	layout()
	refresh()
	writeDock(true)
	Spring.Echo("[bardroid-portrait] dock " .. (on and "hidden: the SHOW button" or "shown again")) -- (tools)
end

local function dockLines()
	local lines = newLines()
	if not lines then
		return
	end
	for line in lines:gmatch("[^\n]+") do
		local side, v, vx = line:match("^dockscroll (%a+) (%S+) ?(%S*)")
		if side == "groups" then -- (the groups row, sideways: its tiles follow the finger)
			if active and menu then
				idleB.scroll = idleB.scroll - (tonumber(vx) or 0)
				idleB.snapTo = nil
				markDirty()
				touched()
			end
			side = nil
		end
		local fs, _, fvx = line:match("^dockfling (%a+) (%S+) ?(%S*)")
		if fs == "groups" and active then -- (let go: on to a whole tile, further for a flick)
			idleB.fling(tonumber(fvx) or 0)
			touched()
		end
		-- (a grid over both halves, home, the spectator's and TEAMS, the teammate picker, a panel: a drag on its left half
		-- is its own; the empty left half took it and panned the camera, so a long TEAMS list scrolled from the right only)
		-- (only where that grid spans both halves: sideways and in the split it is the right block's alone, homeRect, and a
		-- drag on the left block scrolled the share list or a panel on the right; review 2026-11-16)
		local wide = (rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets")
			and not (L.land or L.split)
		if side == "left" and wide then
			side = "right"
		end
		if side and active and menu then
			local _, s, _, _, _, ch = half(side)
			if snapMax(s) == 0 then -- (nothing to scroll there: the drag pans the camera; X pixels, y down)
				panBy(tonumber(vx) or 0, -(tonumber(v) or 0))
			else
				snapBy(s, -(tonumber(v) or 0), ch + L.gap) -- (X pixels down: the rows follow the finger)
			end
			touched()
		end
		side, v = line:match("^dockfling (%a+) (%S+)")
		if side == "left" and wide then
			side = "right"
		end
		if side and active and side ~= "groups" then
			local _, s, _, _, _, ch = half(side)
			snapRelease(s, -(tonumber(v) or 0) / (ch + L.gap))
			touched()
		end
		local cx, cy, cr = line:match("^dockcircle (%S+) (%S+) (%S+)")
		if cx and active then
			circleTo(tonumber(cx), tonumber(cy), tonumber(cr))
			touched()
		end
		local a, b, c, d = line:match("^dgunsticks (%S+) (%S+) (%S+) (%S+)")
		if a then -- the D-gun mode's sticks from the dock (RtsTouch): to it, and the knobs drawn
			DG.stick = { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, tonumber(d) or 0 }
			local D = WG.BarDroidPadDgun
			if D and D.sticks then
				D.sticks(DG.stick[1], DG.stick[2], DG.stick[3], DG.stick[4])
			end
		end
		local slidWord = line:match("^dgunslide (%S+)")
		if slidWord then -- FIRE held: how far it is swiped, right (to AUTO) or left (below 0: back to FIRE); "off": let go
			local slid = tonumber(slidWord)
			if slid then
				if not DG.slide then -- (a new hold: its way from its first line, "-0.00" on AUTO; whether it turns full auto
					-- on or off: floating sideways both FIREs swipe towards the middle, either way)
					local D = WG.BarDroidPadDgun
					DG.slideLocked, DG.slideDir = false, slidWord:sub(1, 1) == "-" and -1 or 1
					DG.slideToAuto = not (D and D.auto and D.auto())
				end
				DG.slide = max(-1, min(1, slid))
				DG.slideLocked = DG.slideLocked or abs(DG.slide) >= 0.92
			elseif DG.slide then
				DG.slide, DG.slideLast, DG.slideOff = nil, DG.slide, now()
			end
		end
		local tx, ty = line:match("^docktap (%S+) (%S+)")
		if tx and active then -- a second finger on the dock while a box selection is dragged: a filter
			local item = itemAt("right", tonumber(tx), vsy - tonumber(ty))
			if item and item.kind == "filter" then
				selFilter = item.key
			end
			touched()
		end
		local any = line:match("^act (%S+)")
		-- (PING held or tapped twice, and speak to chat's state: pingT; the state's lines even while the dock is down: a
		-- session's end lost while the phone was turned left CHAT on and the menu open, review 2026-11-15)
		if any and (active or any:match("^voice_")) then
			pingT.act(any)
		end
		local name = line:match("^act (dock_%S+)")
		if name == "dock_menu" and active and SP.hidden then -- (the SHOW button tapped: the dock back)
			-- (but not the HIDE tap's own line: RtsTouch writes it as the finger comes down on the dock, the tap's click
			-- comes as it lifts, and when both fall in one frame the click is handled first, so HIDE hid the dock and
			-- its own line opened it again 9 ms later; dev phone spectating upright, 2026-11-17)
			if not (SP.hiddenAt and Spring.DiffTimers(Spring.GetTimer(), SP.hiddenAt) < 0.3) then
				SP.setHidden(false)
			end
		elseif name == "dock_menu" and active then
			setMenu(true)
			if L.thumb and not L.panelOn then -- (sideways, nothing picked: the tap that opens the menu opens the home
				-- buttons too, the one thing it holds then)
				L.homeOpen = true
				refresh()
			end
		elseif name == "dock_back" and active then -- (Android's Back: RtsTouch.back)
			SP.back()
		elseif name == "dock_select_start" and active then
			selecting = true
			touched()
			refresh()
		elseif name == "dock_select_end" then
			selecting = false
			if circle then
				pickCircle()
			else
				filterAt = now() + 0.15 -- (the engine makes the box selection when the button goes up)
			end
			touched()
			refresh()
		end
	end
end

-- Android's Back in a game (Kailil, 2026-11-20: "make the android back command contextual ... clearing unit selection
-- ... so I can easily have access to the bottom ui that displays the commander Hotkey, base, pings ... any point I am
-- in. Build place menu, faculty queue, preset commands ... If I'm at that mode already for the bottom ui, make it does
-- the leave battle path where it asks you if you are sure"): back to the home grid from anything over it, the pick,
-- its orders and every menu put away (RtsTouch sends Escape with it: BAR's own command, its chat). Already there, BAR's
-- own way out, SP.backLine: in a game from the lobby the lobby over it, as BAR's Lobby button (Leave Battle there,
-- with its question); else BAR's quit question (Stay, Resign, Quit), asked by the engine's quit request as for the
-- window's close button (RtsTouch: "back quit"). A click on BAR's quit button upright did nothing: BAR's Top Bar, the
-- resource bars hidden under the buttons, takes the press before Top Bar Buttons (bardroid_topbar.lua; dev phone 2026-11-20)
SP.chobby = Spring.GetMenuName and string.find(string.lower(Spring.GetMenuName() or ""), "chobby") ~= nil
function SP.back()
	if SP.atHome() and SP.chobby and not SP.gameOver then
		Spring.SendLuaMenuMsg("showLobby")
		return
	end
	if dgunOn() and WG.BarDroidPad and WG.BarDroidPad.act then
		WG.BarDroidPad.act("dgun_cancel")
	end
	local P = WG.BarDroidPresets
	if P and P.close then
		P.close()
	end
	if P and P.disarm then
		P.disarm()
	end
	sharing, resPanel, factoryItem, typesFrom = nil, nil, nil, nil
	pingT.cancel()
	local pb = Spring.GetGameFrame() == 0 and WG["pregame-build"]
	local putAway = pb and (pb.setPreGamestartDefID or pb.setPreGameDefID)
	if putAway then
		putAway(nil)
	elseif select(2, spGetActiveCommand()) then
		Spring.SetActiveCommand(0)
	end
	Spring.SelectUnitArray({})
	if SP.hidden then
		SP.setHidden(false)
	end
	setMenu(true)
	refresh()
end

-- the home grid with nothing on it to put away: no pick, order, menu, preset, ping armed, D-gun mode, nor BAR's quit
-- question already up (Back closes that one, Escape)
function SP.atHome()
	if rightKind ~= "home" or sharing or resPanel or typesFrom or SP.hidden or dgunOn() or pingT.armed() then
		return false
	end
	if Spring.GetSelectedUnitsCount() > 0 or select(2, spGetActiveCommand()) then
		return false
	end
	local P = WG.BarDroidPresets
	if P and (P.isOpen() or P.armed()) then
		return false
	end
	local tb = WG.topbar
	return not (tb and tb.showingQuit and tb.showingQuit())
end

-- the dock file's "back" line, at home: "back lobby" in a game from the lobby (SP.back shows it; RtsTouch sends no
-- Escape, which the lobby would take); "back quit" where BAR's quit question comes from the engine's quit request (Top
-- Bar Buttons' AllowQuit asks only a player in a started game, the interface shown: a spectator's or a finished game's
-- request quits at once, so then no line, Back stays Escape)
function SP.backLine()
	if not SP.atHome() then
		return ""
	end
	if SP.chobby and not SP.gameOver then
		return "back lobby\n"
	end
	local tb = WG.topbar
	if not (tb and tb.showingQuit) or SP.gameOver or Spring.GetSpectatingState() or Spring.GetGameFrame() <= 0
		or Spring.IsGUIHidden() then
		return ""
	end
	return "back quit\n"
end

---------------------------------------------------------------------------------------------------------------------
-- Callins

-- Sideways too, layout A (Kailil, 2026-11-12, of the landscape mockups: "Split dock: build left, minimap + eco middle,
-- orders right. Is the best"; his idea: "split the right and left half of the botom UI and shove a map into the middle
-- with the eco bars on top of it ... that returns vertical real estate back to the actual game world"): with the
-- launcher's "Touch dock sideways" on (launch-bar.sh: bardroid_landdock.txt), playing, the fingers the input (a pad or
-- a mouse brings BAR's own screen back). BAR's minimap goes into the dock's middle (its Minimap widget's external
-- frame: the engine draws and clicks it there), a hole RtsTouch and this widget leave to it (L.hole, "map" line).
SP.NO_MINIMAP = { 0, 0, 1, 1 }
function SP.landMinimap()
	local m = WG.minimap
	if not (m and m.setExternalFrame) then
		return
	end
	local h = active and L.land and not L.split and L.hole or nil -- (unfolded the hole is the game's: no minimap)
	if active and L.dgFloat and not L.split then -- (the D-gun mode sideways shows no minimap: a pixel in the bottom left corner, under
		-- the band's place; given back its own place BAR's showed at the top left)
		h = SP.NO_MINIMAP
	end
	-- (its numbers against the last ones: a string made of them each frame, before)
	local f = L.frameWas
	if h == f or h and f and h[1] == f[1] and h[2] == f[2] and h[3] == f[3] and h[4] == f[4] then
		return
	end
	L.frameWas = h and { h[1], h[2], h[3], h[4] } or nil
	if h then
		m.setExternalFrame(h[1], h[2], h[3], h[4], 0)
	else
		m.setExternalFrame()
	end
end
-- a dark frame just outside the minimap's place (sideways), round at its corners as the dock's boxes are: its square
-- corners stood bare in the panel beside the metal, energy and wind boxes (dev phone screenshot 2026-11-18)
function SP.holeFrame(h)
	local f = flow()
	if not (f and f.RectRoundOutline) or h == SP.NO_MINIMAP then
		return
	end
	local e = max(2, floor((h[4] - h[2]) * 0.012 + 0.5))
	f.RectRoundOutline(h[1] - e, h[2] - e, h[3] + e, h[4] + e, e * 2, e, 1, 1, 1, 1, { 0, 0, 0, 0.75 }, { 0, 0, 0, 0.75 })
	gl.Color(1, 1, 1, 1)
end
-- the rects of d left around h (h inside d): the dock drawn and dimmed around the minimap
-- (kept while d and h stay as they are: made twice a frame, five tables each; the callers only read them; review
-- 2026-11-16)
function SP.around(d, h)
	if not h then
		SP.aroundOne = SP.aroundOne or {}
		SP.aroundOne[1] = d
		return SP.aroundOne
	end
	local c = SP.aroundCache
	if c and c[1] == d[1] and c[2] == d[2] and c[3] == d[3] and c[4] == d[4] and c[5] == h[1] and c[6] == h[2]
		and c[7] == h[3] and c[8] == h[4] then
		return c.rects
	end
	SP.aroundCache = { d[1], d[2], d[3], d[4], h[1], h[2], h[3], h[4], rects = { { d[1], h[4], d[3], d[4] },
		{ d[1], d[2], d[3], h[2] }, { d[1], h[2], h[1], h[4] }, { h[3], h[2], d[3], h[4] } } }
	return SP.aroundCache.rects
end

local function checkActive()
	local x, y = Spring.GetViewGeometry()
	local was, wasLand = active, L.land
	local input = WG.BarDroidInput
	L.land = (y <= x * PORTRAIT and L.landOn and playing() and input ~= "pad" and input ~= "mouse") or false
	-- (and spectating by touch: the spectator's grid, SP; Kailil, 2026-11-11)
	active = (y > x * PORTRAIT and (playing() or SP.on())) or L.land
	if SP.hidden and not (active and SP.on()) then -- (folded only while spectating)
		SP.hidden, SP.teams = false, false
		-- (and BAR's player list with it, as SP.setHidden: folded upright, then turned sideways, it stayed hidden for the
		-- rest of the game, review 2026-11-15)
		local api = WG.advplayerlist_api
		if api and api.SetHidden then
			api.SetHidden(false)
		end
		if active then
			layout()
		end
	end
	-- (laid out again when the player turns spectator too: the spectator's grid is taller, layout)
	if active and (x ~= vsx or y ~= vsy or not was or (SP.on() and true or false) ~= SP.laidOut or L.land ~= wasLand) then
		layout()
		refresh()
	end
	if active ~= was or L.land ~= wasLand then
		menu, selecting = false, false
		Spring.Echo("[bardroid-portrait] dock " .. (active and "up" or "down") .. (L.land and " sideways" or "")
			.. string.format(" (%dx%d)", x, y))
		writeDock(true)
		if not active then
			SP.factionPickerBack()
			local api = WG.advplayerlist_api -- (BAR's player list, hidden in widget:Update: back with the dock gone)
			if SP.listOff and api and api.SetHidden then
				api.SetHidden(false)
			end
			SP.listOff = nil
		end
	end
	SP.landMinimap()
end

local refreshAt = 0
-- The order a drag draws, its cursor through the drag (Kailil, 2026-11-09: for Fight and Patrol "the order is placed
-- correctly, but the cursor ... stays green"): BAR's formation widget unpicks the order as a one-unit path starts
-- (cmd_customformations2: SetActiveCommand(0), the order kept as its own), so the pointer showed Move's green cursor
-- over a Fight or Patrol path. The order picked when the right button went down: its cursor until it comes up.
local armedCursor, drawCursor = nil, nil
local function drawingCursor()
	local _, _, _, _, right = Spring.GetMouseState()
	if right then
		drawCursor = drawCursor or armedCursor
		if drawCursor then
			Spring.SetMouseCursor(drawCursor)
		end
		return
	end
	drawCursor = nil
	local index, id = spGetActiveCommand()
	local desc = id and DRAW_CMDS[id] and index and Spring.GetActiveCmdDesc(index)
	armedCursor = desc and desc.cursor or nil
end

-- No BAR tooltips over the dock: after a tap the pointer rests on it, over BAR's panels under it, whose tooltips BAR's
-- tooltip widget (gui_tooltip.lua) drew on top, for buttons not to be seen ("Only view what the player can see", BAR's
-- player list under the spectator's dock; "Patrol", the order menu's; dev phone 2026-11-11). That widget draws what is
-- asked of it each frame (WG.tooltip.ShowTooltip): an ask while the pointer is over the dock is dropped. (SP holds it:
-- the file's main chunk is at Lua's 200 locals.)
function SP.guardTooltips()
	local T = WG.tooltip
	if not (T and T.ShowTooltip) or T.ShowTooltip == SP.tipWrap then
		return
	end
	local inner = T.ShowTooltip
	SP.tipInner, SP.tipOwner = inner, T
	SP.tipWrap = function(name, value, x, y, title)
		if active and not SP.hidden and not L.aside and L.dock then
			local mx, my = Spring.GetMouseState()
			if inRect(mx, my, L.dock) then
				return
			end
		end
		return inner(name, value, x, y, title)
	end
	T.ShowTooltip = SP.tipWrap
end

function widget:Update(dt)
	checkActive()
	-- BAR's lobby over the game (the top bar's Lobby button), as bardroid_touch.lua has checked it with this phone's own
	-- lobby (WG.BarDroidLobbyOver): the dock out of RtsTouch's way under it (writeDock), back with the game. Chobby's
	-- message itself reaches LuaUI from any player online too (2026-11-21)
	local over = WG.BarDroidLobbyOver == true
	if over ~= (SP.lobbyOver == true) then
		SP.lobbyOver = over
		writeDock(true)
	end
	SP.guardTooltips()
	dockLines()
	topbarBars(active or upright())
	if not active then
		return
	end
	startFit()
	SP.pregameView(dt)
	if rightKind == "pregame" then
		SP.factionPicker()
	end
	factoryStates()
	windTurn =(windTurn + (select(4, Spring.GetWind()) or 0) * 0.2 * (dt or 0) * 30) % 360 -- (BAR's top bar's blade speed)
	SP.windSample() -- (the wind details' graph)
	drawingCursor()
	if (rightKind == "home" or rightKind == "pregame") and pingT.drawn then -- (PINGS: "2 OF 4" back to LAST PINGS after
		-- the cycle's pause, TAP MAP back to PING when it runs out; pregame's PING alone draws no step)
		-- (and a new ping's count, an attack's red: the badge waited for the dock's next redraw)
		local n, step, armed, attack = pingT.state()
		if (rightKind == "pregame" and ("0" .. (armed and "a" or ""))
			or (n .. ":" .. step .. (armed and "a" or "") .. (attack and "!" or ""))) ~= pingT.drawn then
			markDirty()
		end
	end
	pingT.update() -- (CHAT's flips, a spoken ping's end)
	local fp = L.factoryPick -- (FACTORIES at rest: the factory it came to picked; something picked meanwhile: dropped)
	if fp and (now() >= fp.at or Spring.GetSelectedUnitsCount() > 0) then
		L.factoryPick = nil
		markDirty() -- (FACTORIES' bar gone with it)
		if Spring.GetSelectedUnitsCount() == 0 and Spring.ValidUnitID(fp.unit) and not Spring.GetUnitIsDead(fp.unit) then
			selectUnits({ fp.unit })
		end
	elseif fp then
		markDirty() -- (FACTORIES' bar running out)
	end
	if rightKind == "dgun" then
		DG.follow(dt)
	else
		DG.unitWas = nil -- (the next start eases in again, the same commander too)
	end
	for _, s in ipairs({ leftScroll, rightScroll }) do
		if s.drag or s.t < 1 then
			markDirty() -- (rows moving: the texture drawn again each frame until they settle)
		end
		snapUpdate(s, dt)
	end
	idleB.settle(dt) -- (the groups row on to a whole tile)
	local t = now()
	-- (a building picked: the menu stays open, PLACE, rotate and cancel take the first tap. Its 2 s ran out while the
	-- spot was picked on the map, the dock went back to the camera pad, and PLACE's tap only opened the menu again: "it
	-- keeps canceling a place", Kailil 2026-11-10, a Bot Lab; dev phone: the spot tapped, PLACE 2.5 s later, nothing)
	-- (so with the presets, the teammate picker and the resource panel over the grid: picked to be tapped next; the
	-- presets' thumbnails went back to the camera pad under a finger reaching for one, dev phone)
	-- (and the spectator's TEAMS list: a tap on a team after 2 s only opened the menu again, dev phone 2026-11-11)
	if SP.held() then
		if not menu then
			setMenu(true)
		end
	elseif menu and not selecting and not leftScroll.drag and not rightScroll.drag and t - lastTouch > MENU_SECONDS then
		setMenu(false)
	end
	if filterAt and t >= filterAt then
		filterAt = nil
		applyFilter()
	end
	if t >= refreshAt and not press then
		refreshAt = t + 0.25
		refresh()
	end
	local q = SP.quickPending -- (a building tapped with nothing picked: placed once its builder's commands are there)
	if q then
		local s = spGetSelectedUnits() or {}
		if #s == 1 and s[1] == q.unit and spGetCmdDescIndex(q.id) then
			SP.quickPending = nil
			runCommand(q.id)
			Spring.Echo("[bardroid-portrait] built without picking first: " .. ((UnitDefs[-q.id] or {}).name or q.id)) -- (tools)
		elseif now() - q.at > 1.5 then
			SP.quickPending = nil
		end
	end
	local aside = SP.windowOpen() -- (one of BAR's big windows open: the dock out of its way until it closes)
	if aside ~= L.aside then
		L.aside = aside
		markDirty()
		writeDock(true)
	end
	-- BAR's player list, which the dock covers, hidden where the dock is not: aside for a window (it showed beside or under
	-- the window, cut by its edge, sideways at the bottom right, upright at 1080x1198 under Settings' corner), folded
	-- (HIDE), and the D-gun mode's sticks without the dock (sideways in the corner under AIM's stick); dev phone 2026-11-16.
	-- Aside, the panels BAR stacks on it away too (the music line under Settings' corner upright, dev phone 2026-11-19)
	local listOff = aside and "away" or SP.windOff() and "hidden" or false
	if listOff ~= SP.listOff then
		SP.listOff = listOff
		local api = WG.advplayerlist_api
		if api and api.SetHidden then
			api.SetHidden(listOff ~= false, listOff == "away")
		end
	end
	writeDock(false)
end

function widget:CommandsChanged()
	SP.cmds.stale = true -- (readCommands: the engine's list read again)
	if active and not press then
		refresh()
	end
end

-- springsettings bardroid_portrait_profile = 1 (PROF): the dock's drawing time, its average every 10 s in the log
-- (tools; 2.1 ms a frame on the dev phone, 2026-11-09; a display list of it made that 4-10 ms, growing: FlowUI's own
-- lists inside it, made again several times a second; BAR's menus keep theirs in a texture, the way to try next)

-- The dock's still parts in a texture, drawn again only when something changed (dirty: the refresh a few times a
-- second, a press, rows moving, the layout), as BAR's own build and order menus keep theirs (gl.R2tHelper); the
-- moving parts drawn over it every frame: metal and energy, PLACE, the mode. Screen pixels (no supersampling: the
-- dock starts at 0,0, so the halves' scissor rects are the texture's own). Without the helper: all drawn each frame.
local dockTex, texW, texH
-- springsettings bardroid_portrait_tex (tools): 0 no texture (all drawn each frame), 2 the texture drawn again every
-- frame (a stress test: two GPU driver faults on the dev phone in its first 8 games, none in 18 before it, 2026-11-09)
local texMode = Spring.GetConfigInt("bardroid_portrait_tex", 1)

-- the D-gun mode's controls (live: the knobs follow the thumbs)
local function disc(x, y, r, fill)
	gl.BeginEnd(fill and GL.TRIANGLE_FAN or GL.LINE_LOOP, function()
		if fill then
			gl.Vertex(x, y)
		end
		for i = 0, 40 do
			local a = i / 40 * 2 * math.pi
			gl.Vertex(x + math.cos(a) * r, y + math.sin(a) * r)
		end
	end)
end
-- a disc shaded from a point inside it (ox, oy: that point's offset from the middle, shares of r) to its rim: c0 there,
-- c1 at the rim (the D-gun sticks' wells and knobs; flat discs read as holes cut in the dock, dev phone screenshot
-- 2026-11-17)
function DG.litDisc(x, y, r, c0, c1, ox, oy)
	gl.BeginEnd(GL.TRIANGLE_FAN, function()
		gl.Color(c0[1], c0[2], c0[3], c0[4])
		gl.Vertex(x + (ox or 0) * r, y + (oy or 0) * r)
		gl.Color(c1[1], c1[2], c1[3], c1[4])
		for i = 0, 40 do
			local a = i / 40 * 2 * math.pi
			gl.Vertex(x + math.cos(a) * r, y + math.sin(a) * r)
		end
	end)
end
DG.STICK_C = {
	well0 = { 0, 0, 0, 0.72 }, well1 = { 0.11, 0.115, 0.13, 0.66 }, -- (a bowl: dark in the middle, lighter to the rim)
	move0 = { 0.97, 0.97, 0.97, 0.95 }, move1 = { 0.6, 0.61, 0.64, 0.95 }, -- (the knobs lit from their top left)
	aim0 = { 1, 0.52, 0.44, 0.97 }, aim1 = { 0.76, 0.15, 0.11, 0.97 },
	auto0 = { 0.56, 0.56, 0.57, 0.6 }, auto1 = { 0.33, 0.33, 0.35, 0.6 },
}
-- FIRE's swipe track (Kailil, 2026-11-10: "the fire mode animation doesn't fully slide to the right and fill the auto.
-- And when you swipe left to disable auto, the animation doesn't work. Its just frozen"): FIRE's to the right, to the
-- grid's edge, AUTO at its end; AUTO's to the left, to the cancel corner, FIRE at its end (RtsTouch measures the swipe
-- against the same spans). The knob goes all the way, the track fills behind it (red to gold towards AUTO, gold to red
-- towards FIRE), chevrons run the way to go; locked (past 0.92) it is full, the knob gone into it, the word on it.
-- f: FIRE's rect, cancel: the cancel corner's, dir 1 right / -1 left, v 0..1, alpha. Floating sideways (float): from
-- the held FIRE to the screen's middle, either way; toAuto: full auto on at its end (else off; upright: rightwards)
function DG.track(f, cancel, dir, v, alpha, locked, t, float, toAuto)
	if toAuto == nil then
		toAuto = dir > 0
	end
	local fh = f[4] - f[2]
	local m = (dir > 0 or float) and 0.16 or 0.26 -- (the left one thinner: the cancel corner leaves it less room across)
	local y0, y1 = f[2] + floor(fh * m), f[4] - floor(fh * m)
	-- (floating: to the middle, a FIRE's width at least, as RtsTouch measures it: on the unfolded Fold7 the middle was
	-- 106 pixels away)
	local mid, fw = floor(vsx / 2), f[3] - f[1]
	local k = float and (dir > 0 and { f[3] + L.gap * 2, y0, max(mid - L.gap, f[3] + L.gap * 2 + fw), y1 }
			or { min(mid + L.gap, f[1] - L.gap * 2 - fw), y0, f[1] - L.gap * 2, y1 })
		or dir > 0 and { f[3] + L.gap * 2, y0, L.right[3], y1 } or { cancel[3] + L.gap * 2, y0, f[1] - L.gap * 2, y1 }
	local tw, th = k[3] - k[1], k[4] - k[2]
	if tw < th * 1.3 or alpha <= 0 then
		return
	end
	local r, cy = th * 0.4, (k[2] + k[4]) / 2
	local from, to = dir > 0 and k[1] + r or k[3] - r, dir > 0 and k[3] - r or k[1] + r
	local kx = from + (to - from) * v
	gl.Color(0, 0, 0, 0.6 * alpha)
	gl.Rect(k[1], k[2], k[3], k[4])
	local c = toAuto and v or 1 - v
	gl.Color(0.86 + 0.14 * c, 0.14 + 0.66 * c, 0.11, (locked and 0.95 or 0.85) * alpha)
	if locked then
		gl.Rect(k[1], k[2], k[3], k[4])
	elseif dir > 0 then
		gl.Rect(k[1], k[2], kx, k[4])
	else
		gl.Rect(kx, k[2], k[3], k[4])
	end
	gl.Color(1, 1, 1, 0.3 * alpha)
	gl.Rect(k[1], k[2], k[3], k[2] + 1)
	gl.Rect(k[1], k[4] - 1, k[3], k[4])
	gl.Rect(k[1], k[2], k[1] + 1, k[4])
	gl.Rect(k[3] - 1, k[2], k[3], k[4])
	if not locked then
		local phase, cw = (t * 1.6) % 1, th * 0.22
		gl.LineWidth(max(2, floor(th * 0.09)))
		for i = 0, 2 do
			local q = (i + phase) / 3
			local x = from + (to - from) * q
			gl.Color(1, 1, 1, math.sin(q * math.pi) * 0.8 * alpha)
			gl.BeginEnd(GL.LINE_STRIP, function()
				gl.Vertex(x - dir * cw * 0.5, cy + cw)
				gl.Vertex(x + dir * cw * 0.5, cy)
				gl.Vertex(x - dir * cw * 0.5, cy - cw)
			end)
		end
		gl.LineWidth(1)
		gl.Color(1, 1, 1, alpha)
		disc(kx, cy, r, true)
	end
	if alpha > 0.2 then
		local ls = fh * 0.245 -- (from FIRE's height, as the right track's: the thinner left one's word came out small)
		local word = toAuto and "AUTO" or "FIRE"
		local tx = dir > 0 and k[3] - L.pad or k[1] + L.pad
		local ww = bold:GetTextWidth(word) * ls
		local wordMid = tx - dir * ww / 2
		-- (the white knob under the word: dark letters on it, the gold ones were lost there; dev phone screenshots)
		local onKnob = not locked and abs(kx - wordMid) < r + ww * 0.4
		local col = locked and (toAuto and "\255\050\024\000" or "\255\255\255\255")
			or onKnob and "\255\070\040\010"
			or (v >= 0.6 and "\255\255\200\064" or "\255\190\190\190")
		bold:Print(col .. word, tx, cy - ls * 0.36, ls, dir > 0 and "ro" or "o")
	end
	gl.Color(1, 1, 1, 1)
end

local function drawDgun()
	local p = dgunParts()
	local D = WG.BarDroidPadDgun
	local autoOn, autoFor = false, 0
	if D and D.auto then
		autoOn, autoFor = D.auto()
		autoFor = autoFor or 0
	end
	-- (the two sticks' words one size, the one "AIM: AUTO" fits at: textIn shrank only a word too wide for its stick, so
	-- on the unfolded Fold7's narrower sticks MOVE stood large beside a small AIM: AUTO, and AIM's size jumped as full
	-- auto came and went; dev phone at 1080x1198, 2026-11-15)
	local wordSize = L.btnH * 0.36
	if font then
		local wide = font:GetTextWidth("AIM: AUTO") * wordSize
		local room = min(p.l[3], p.r[3]) * 2 * 0.76 -- (textIn's room: 76 % of the width it is given)
		if wide > room then
			wordSize = wordSize * room / wide
		end
	end
	local C = DG.STICK_C
	for i, s in ipairs({ p.l, p.r }) do
		DG.litDisc(s[1], s[2], s[3], C.well0, C.well1)
		gl.LineWidth(2)
		gl.Color(1, 1, 1, 0.2)
		disc(s[1], s[2], s[3], false)
		gl.LineWidth(1)
		-- (four small marks inside the rim, the ways the stick goes)
		gl.Color(1, 1, 1, 0.16)
		local m, mr = s[3] * 0.07, s[3] * 0.86
		gl.BeginEnd(GL.TRIANGLES, function()
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local ax, ay = s[1] + d[1] * mr, s[2] + d[2] * mr
				gl.Vertex(ax, ay)
				gl.Vertex(ax - d[1] * m * 1.4 - d[2] * m, ay - d[2] * m * 1.4 - d[1] * m)
				gl.Vertex(ax - d[1] * m * 1.4 + d[2] * m, ay - d[2] * m * 1.4 + d[1] * m)
			end
		end)
		local kx, ky = s[1] + DG.stick[i * 2 - 1] * s[3], s[2] - DG.stick[i * 2] * s[3]
		local kr = s[3] * 0.36
		local c0, c1 = C.move0, C.move1
		if i == 2 and autoOn then -- (full auto aims itself: the stick greyed, "AIM: AUTO"; its red read as aiming, screenshot)
			c0, c1 = C.auto0, C.auto1
		elseif i == 2 then -- (the aim: the shot's red, as its ring on the ground)
			c0, c1 = C.aim0, C.aim1
		end
		gl.Color(0, 0, 0, 0.35 * c0[4]) -- (its shadow, a little lower)
		disc(kx, ky - kr * 0.1, kr * 1.06, true)
		DG.litDisc(kx, ky, kr, c0, c1, -0.3, 0.35)
		gl.LineWidth(1.5)
		gl.Color(1, 1, 1, 0.25 * c0[4])
		disc(kx, ky, kr, false)
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
		-- (floating sideways above the stick: under it AIM's word lay on BAR's player list in the bottom right corner, the
		-- two unreadable, dev phone screenshot 2026-11-13)
		local wy0 = p.float and s[2] + s[3] + L.gap or s[2] - s[3] - L.btnH * 0.55
		local wy1 = p.float and s[2] + s[3] + L.btnH * 0.55 or s[2] - s[3] - L.gap
		textIn(i == 1 and "MOVE" or autoOn and "AIM: AUTO" or "AIM", s[1] - s[3], wy0, s[1] + s[3], wy1, wordSize,
			"\255\200\200\200", font)
	end
	local t = now()
	if DG.autoWas and not autoOn then
		DG.autoOffAt = t -- (full auto just ended: the gold drains out of the button, below)
	end
	DG.autoWas = autoOn
	-- whether it can fire now: a thin bar along FIRE's foot, white as the D-gun reloads, amber (and the word dimmed)
	-- while the team lacks a shot's energy; none once it is ready
	local loaded, energy = 1, 1
	if D and D.ready then
		loaded, energy = D.ready()
		loaded, energy = loaded or 1, energy or 1
	end
	local lacking = energy < 1
	local part = lacking and energy or loaded
	for _, f in ipairs({ p.fire, p.fire2 }) do -- (FIRE; floating sideways, one beside each stick)
		local fw, fh = f[3] - f[1], f[4] - f[2]
		local e = max(2, floor(L.pad * 0.35))
		if autoOn then -- full auto: FIRE turns gold-orange, stripes run across it, its edge pulses; AUTO on it
			button(f, { 0.55, 0.2, 0.02, 1 }, { 0.95, 0.48, 0.07, 1 })
			local step = fh * 0.6
			local shift = (t * fh * 1.4) % step
			gl.Scissor(f[1], f[2], fw, fh)
			gl.Color(1, 0.9, 0.4, 0.18)
			for sx = f[1] - fh - step + shift, f[3], step do
				gl.BeginEnd(GL.QUADS, function()
					gl.Vertex(sx, f[2])
					gl.Vertex(sx + step * 0.45, f[2])
					gl.Vertex(sx + step * 0.45 + fh, f[4])
					gl.Vertex(sx + fh, f[4])
				end)
			end
			gl.Scissor(false)
			local pulse = 0.5 + 0.5 * math.sin(t * 6)
			gl.Color(1, 0.85, 0.35, 0.45 + 0.45 * pulse)
			gl.Rect(f[1], f[2], f[3], f[2] + e)
			gl.Rect(f[1], f[4] - e, f[3], f[4])
			gl.Rect(f[1], f[2], f[1] + e, f[4])
			gl.Rect(f[3] - e, f[2], f[3], f[4])
			if autoFor < 0.3 then -- (as it engages the gold fills the button from the left, the red going out at the right)
				local w = (1 - autoFor / 0.3) ^ 2
				gl.Color(0.86, 0.14, 0.11, 0.95)
				gl.Rect(f[3] - fw * w, f[2], f[3], f[4])
			end
			if autoFor < 0.6 then -- (and a flash, and the edge thrown out around the button)
				local a, grow = 1 - autoFor / 0.6, autoFor / 0.6 * fh * 0.6
				gl.Color(1, 0.92, 0.6, 0.55 * a)
				gl.Rect(f[1], f[2], f[3], f[4])
				gl.Color(1, 0.8, 0.3, 0.8 * a)
				gl.Rect(f[1] - grow, f[2] - grow, f[3] + grow, f[2] - grow + e)
				gl.Rect(f[1] - grow, f[4] + grow - e, f[3] + grow, f[4] + grow)
				gl.Rect(f[1] - grow, f[2] - grow, f[1] - grow + e, f[4] + grow)
				gl.Rect(f[3] + grow - e, f[2] - grow, f[3] + grow, f[4] + grow)
			end
			gl.Color(1, 1, 1, 1)
		else
			button(f, { 0.5, 0.06, 0.05, 1 }, { 0.86, 0.14, 0.11, 1 })
			local off = DG.autoOffAt and t - DG.autoOffAt
			if off and off < 0.4 then -- (full auto ended: the gold drains to the left, a white flash going with it)
				local w = (1 - off / 0.4) ^ 2
				gl.Color(0.95, 0.48, 0.07, 0.95)
				gl.Rect(f[1], f[2], f[1] + fw * w, f[4])
				gl.Color(1, 1, 1, 0.5 * w)
				gl.Rect(f[1], f[2], f[3], f[4])
				gl.Color(1, 1, 1, 1)
			end
		end
		if part < 1 then
			local bh = max(3, floor(fh * 0.07))
			local x0, x1 = f[1] + e * 2, f[3] - e * 2
			gl.Color(0, 0, 0, 0.45)
			gl.Rect(x0, f[2] + e * 2, x1, f[2] + e * 2 + bh)
			if lacking then
				gl.Color(1, 0.7, 0.2, 0.95)
			else
				gl.Color(1, 1, 1, 0.9)
			end
			gl.Rect(x0, f[2] + e * 2, x0 + (x1 - x0) * part, f[2] + e * 2 + bh)
			gl.Color(1, 1, 1, 1)
		end
		textIn(autoOn and "AUTO" or "FIRE", f[1], f[2], f[3], f[4], fh * 0.42,
			lacking and "\255\200\160\150" or "\255\255\255\255", bold)
	end -- (each FIRE)
	-- FIRE held: its swipe's track (DG.track). Let go past 0.92 the track stays full and fades; short of it it runs back
	local held = DG.slide
	local fade = not held and DG.slideOff and t - DG.slideOff < 0.3 and 1 - (t - DG.slideOff) / 0.3
	if held or fade then
		local s = held or DG.slideLast or 0
		local locked = DG.slideLocked
		local v = locked and 1 or abs(s) * (held and 1 or fade)
		local dir = DG.slideDir or (s < 0 and -1 or 1)
		-- (floating: the left FIRE's swipe goes right, the right one's left, both towards the middle)
		DG.track(p.fire2 and dir < 0 and p.fire2 or p.fire, p.cancel, dir, v, held and 1 or fade, locked, t, p.float,
			DG.slideToAuto)
	end
	button(p.cancel)
	textIn("\226\156\149", p.cancel[1], p.cancel[2], p.cancel[3], p.cancel[4], (p.cancel[4] - p.cancel[2]) * 0.5,
		"\255\255\150\140", bold)
	resetGL()
end

-- The selection row as two buttons (Kailil, 2026-11-10: "turn the entire selected unit description into the queue
-- button 2/3s is queue on the right. And 1/3 is alt queue modifier so we can insert things in front of queue"):
-- bardroid_pad.lua's QUEUE (a sticky Shift) and INSERT (BAR's CommandInsert: the front of the queue) take the presses;
-- here their words, gold and a gold edge while one is on, drawn live over the row
local function queueZones()
	-- (made once per selection row: layout makes L.sel anew, never changes it in place; asked several times a frame,
	-- here and by bardroid_pad.lua, each answer was two new tables; release overhaul item 7, 2026-11-21)
	local s = L.sel
	if L.qzFor ~= s then
		local third = s[1] + floor((s[3] - s[1]) / 3)
		L.qzFor, L.qz = s, { { s[1], s[2], third, s[4] }, { third, s[2], s[3], s[4] } }
	end
	return L.qz[1], L.qz[2]
end
local function drawQueueZones()
	if not showSel then
		return
	end
	local Pd = WG.BarDroidPad
	local qOn, iOn = false, false
	if Pd and Pd.queueState then
		qOn, iOn = Pd.queueState()
	end
	local ins, que = queueZones()
	local h = ins[4] - ins[2]
	local e = max(2, floor(L.pad * 0.3))
	for _, z in ipairs({ { ins, iOn }, { que, qOn } }) do
		local r = z[1]
		if z[2] then
			gl.Color(1, 0.78, 0.25, 0.14)
			gl.Rect(r[1], r[2], r[3], r[4])
			gl.Color(1, 0.78, 0.25, 0.95)
			gl.Rect(r[1], r[2], r[3], r[2] + e)
			gl.Rect(r[1], r[4] - e, r[3], r[4])
			gl.Rect(r[1], r[2], r[1] + e, r[4])
			gl.Rect(r[3] - e, r[2], r[3], r[4])
		end
	end
	gl.Color(1, 1, 1, 0.16) -- (where one ends and the other begins)
	gl.Rect(ins[3] - 1, ins[2] + h * 0.18, ins[3] + 1, ins[4] - h * 0.18)
	gl.Color(1, 1, 1, 1)
	local size = h * 0.2
	local gold, white = "\255\255\200\064", "\255\235\235\235"
	bold:Print((iOn and gold or white) .. "INSERT", (ins[1] + h + ins[3]) / 2, (ins[2] + ins[4]) / 2 - size * 0.35, size, "co")
	-- (QUEUE as INSERT: its middle on the row's, between the name and the health bar, where the camera pad's words were;
	-- on the name's line at the top right it read smaller, Kailil 2026-11-16: "make QUEUE larger, the same size as insert")
	-- (with the wind's and the tide's nook up: on the name's line under it, SP.selLineY)
	local nk = not SP.windOff() and SP.windRects() and L.windNook
	local qy = nk and SP.selLineY(L.sel, nk) or (que[2] + que[4]) / 2
	bold:Print((qOn and gold or white) .. "QUEUE", que[3] - L.pad, qy - size * 0.35, size, "ro")
end

-- Sideways, one thumb: the tabs over the panel (the one shown in gold), HOME (gold while its buttons are open) and the
-- swap button, its arrow towards the side the dock would go to
SP.TAB_LABELS = { build = "BUILD", pregame = "BUILD", seltypes = "UNITS", orders = "ORDERS", place = "PLACE",
	home = "HOME", units = "LISTS", factory = "QUEUE", filters = "FILTERS" }
function SP.drawThumb()
	local gold = { 0.38, 0.3, 0.04, 0.9 }
	for _, side in ipairs({ "left", "right" }) do
		local r = L.tabs and L.tabs[side]
		if r then
			local kind = side == "left" and leftKind or rightKind
			-- (before the start the right page holds UNDO LAST, CLEAR QUEUE, the factions and PING: "START", not a second
			-- "BUILD" beside the build page's; dev phone sideways, 2026-11-14)
			local label = (side == "right" and kind == "pregame" and "START") or SP.TAB_LABELS[kind]
				or (kind:sub(1, 6) == "types:" and "UNITS") or (side == "left" and "BUILD" or "ORDERS")
			if L.tab == side then
				button(r, gold, { 0.66, 0.53, 0.12, 0.9 })
			else
				button(r)
			end
			textIn(label, r[1], r[2], r[3], r[4], (r[4] - r[2]) * 0.46, "\255\240\240\240", bold)
		end
	end
	local h = L.homeBtn -- (none now: the wind and the tide have its place, SP.windRects; kept for a layout that has one)
	if h then
		if L.homeOpen then
			button(h, gold, { 0.66, 0.53, 0.12, 0.9 })
		else
			button(h)
		end
		textIn("HOME", h[1], h[2], h[3], h[4], min((h[4] - h[2]) * 0.3, (h[3] - h[1]) * 0.26), "\255\240\240\240", bold)
	end
	local s = L.swapBtn
	button(s)
	local cx, cy = (s[1] + s[3]) / 2, (s[2] + s[4]) / 2
	local a, d = min(s[3] - s[1], s[4] - s[2]) * 0.22, L.side == "left" and 1 or -1
	gl.Color(0.94, 0.94, 0.94, 1)
	gl.BeginEnd(GL.TRIANGLES, function()
		gl.Vertex(cx + d * a * 0.9, cy)
		gl.Vertex(cx - d * a * 0.6, cy + a)
		gl.Vertex(cx - d * a * 0.6, cy - a)
	end)
	gl.Rect(cx - d * a * 1.1 - 2, cy - a, cx - d * a * 1.1 + 2, cy + a) -- (a bar behind it: "to the other side")
	gl.Color(1, 1, 1, 1)
end
-- which of them is at x, y: "home", "swap", "left" or "right" (a tab), or nil
function SP.thumbAt(x, y)
	if not L.thumb then
		return nil
	end
	if L.homeBtn and inRect(x, y, L.homeBtn) then
		return "home"
	end
	if L.swapBtn and inRect(x, y, L.swapBtn) then
		return "swap"
	end
	for _, side in ipairs({ "left", "right" }) do
		if L.tabs and L.tabs[side] and inRect(x, y, L.tabs[side]) then
			return side
		end
	end
	return nil
end

local function drawStill()
	if L.split then -- (unfolded: a panel for each block, the game between them)
		panel(L.splitL, 1, 1, 0, 0, true)
		panel(L.splitR, 1, 1, 0, 0, true)
	else
		panel(L.dock, 1, 1, 0, 0, true)
	end
	if showSel then
		drawSelection()
	end
	drawHalf("left")
	drawHalf("right")
	if SP.overRect then -- (the orders past the right's first page, under a pick's types)
		drawHalf("over")
	end
	if L.thumb then
		SP.drawThumb()
	end
	if showGroups then
		drawGroups()
	else
		L.groupRects = {}
	end
end

-- The metal and energy panels in a texture of their own, drawn again only when what they show changes (the numbers,
-- the bar by a two-hundredth, the wind and tide readings, their place): drawn live every frame they took 0.8-1.0 ms of
-- the dock's 1.2-1.7 ms a frame (dev phone, 2026-11-12). The wind's blades (and the waves) turn live over it.
SP.RES_KINDS = { "metal", "energy" }
function SP.resSignature() -- (its parts in one table kept for it: made each frame, two tables a frame)
	local parts = SP.resParts or {}
	SP.resParts = parts
	parts[1], parts[2], parts[3], parts[4], parts[5] = L.res[1], L.res[2], L.res[3], L.res[4], tideRelevant() and "t" or ""
	for i, res in ipairs(SP.RES_KINDS) do
		local cur, storage, _, income, expense, share = Spring.GetTeamResources(myTeam(), res)
		-- (and the share and conversion marks on the bar, by a hundredth)
		parts[5 + i] = cur and string.format("%s/%s/%s/%s/%d/%d/%d", short(cur), short(income or 0), short(expense or 0),
			short(storage or 0), (storage or 0) > 0 and floor(cur / storage * 200) or 0, floor((share or 1) * 100),
			res == "energy" and floor((Spring.GetTeamRulesParam(myTeam(), "mmLevel") or 0.75) * 100) or 0) or "-"
	end
	-- (the wind and tide: their own boxes now, drawn live, SP.drawWindTide; their nook between metal and energy narrows them)
	local nk = not SP.windOff() and SP.windRects() and L.windNook
	parts[8] = nk and nk.kind == "res" and (nk[1] .. "," .. nk[3]) or ""
	parts[9] = (resPanel or "") .. "/" .. (sharing or "") -- (the open panel's box lit)
	return table.concat(parts, " ")
end
function SP.drawRes()
	local R, r = gl.R2tHelper, L.res
	if texMode == 0 or not (R and R.RenderInRect and R.BlendTexRect) then
		drawResources()
		return
	end
	local w, h = r[3] - r[1], r[4] - r[2]
	if L.resTex and (L.resTexW ~= w or L.resTexH ~= h) then
		gl.DeleteTexture(L.resTex)
		L.resTex = nil
	end
	if not L.resTex then
		L.resTex = gl.CreateTexture(w, h, { target = GL.TEXTURE_2D, format = GL.RGBA8, fbo = true })
		L.resTexW, L.resTexH, L.resSig = w, h, nil
		if not L.resTex then
			drawResources()
			return
		end
	end
	local sig = SP.resSignature()
	if sig ~= L.resSig then
		L.resSig, L.resIcons = sig, {}
		R.RenderInRect(L.resTex, r[1], r[2], r[3], r[4], drawResources, true)
		L.resIconsLive, L.resIcons = L.resIcons, nil
		if PROF.on then
			PROF.resN = (PROF.resN or 0) + 1
		end
	end
	R.BlendTexRect(L.resTex, r[1], r[2], r[3], r[4], true)
	for _, ic in ipairs(L.resIconsLive or {}) do -- (the turning pictures)
		gl.Color(1, 1, 1, 0.8)
		gl.Texture(ic[1])
		gl.PushMatrix()
		gl.Translate(ic[2], ic[3], 0)
		gl.Rotate(ic[5] and windTurn or 0, 0, 0, 1)
		gl.TexRect(-ic[4], -ic[4], ic[4], ic[4])
		gl.PopMatrix()
		gl.Texture(false)
	end
	gl.Color(1, 1, 1, 1)
end

local function drawDock(post) -- (post: drawn again over a band, DrawScreenPost; the texture as it is, not made again)
	if not post then
		L.drawFrame = Spring.GetDrawFrame()
	end
	if SP.hidden then -- (folded: its SHOW button only, BAR's dark glass and gold along its top as the open dock's)
		local d = L.dock
		button(d, { 0.05, 0.05, 0.06, 0.82 }, { 0.16, 0.16, 0.18, 0.82 })
		gl.Color(0.9, 0.72, 0.25, 0.9)
		gl.Rect(d[1] + L.pad, d[4] - max(2, floor(L.pad * 0.35)), d[3] - L.pad, d[4])
		gl.Color(1, 1, 1, 1)
		textIn("\226\150\178  SHOW", d[1], d[2], d[3], d[4], (d[4] - d[2]) * 0.42, "\255\240\240\240", bold)
		resetGL()
		return
	end
	if L.dgFloat and rightKind == "dgun" then -- (the D-gun mode sideways: its controls on the game, no band, layout)
		drawDgun()
		return
	end
	local R = gl.R2tHelper
	local inTex = texMode ~= 0 and R and R.RenderInRect and R.BlendTexRect
	if inTex then
		local w, h = L.dock[3] - L.dock[1], L.dock[4] - L.dock[2]
		if dockTex and (texW ~= w or texH ~= h) then
			gl.DeleteTexture(dockTex)
			dockTex = nil
		end
		if not dockTex then
			dockTex = gl.CreateTexture(w, h, { target = GL.TEXTURE_2D, format = GL.RGBA8, fbo = true })
			texW, texH, dirty = w, h, true
		end
		if (dirty or texMode == 2) and dockTex and not post then
			local t0 = PROF.on and spGetTimer()
			R.RenderInRect(dockTex, L.dock[1], L.dock[2], L.dock[3], L.dock[4], function()
				SP.inTex = true
				drawStill()
				SP.inTex = false
				local hole = L.hole
				if hole then -- (sideways: the minimap's place left clear in the texture; BAR's minimap shows there)
					gl.Blending(false)
					gl.Color(0, 0, 0, 0)
					gl.Rect(hole[1], hole[2], hole[3], hole[4])
					gl.Blending(true)
					gl.Color(1, 1, 1, 1)
					SP.holeFrame(hole)
				end
			end, true)
			dirty = false
			if t0 then
				PROF.texN, PROF.texMs = PROF.texN + 1, PROF.texMs + spDiffTimers(spGetTimer(), t0) * 1000
			end
		end
		if dockTex then
			-- (drawn into the texture the dock's panel is no longer opaque: the game and BAR's menus under it showed
			-- through; an opaque base under it; sideways around the minimap)
			gl.Color(0.03, 0.035, 0.04, 1)
			for _, r in ipairs(SP.around(L.dock, L.hole)) do
				gl.Rect(r[1], r[2], r[3], r[4])
			end
			gl.Color(1, 1, 1, 1)
			R.BlendTexRect(dockTex, L.dock[1], L.dock[2], L.dock[3], L.dock[4], true)
		end
	else
		drawStill()
		if L.hole and not L.split then -- (no texture: the minimap drawn again over the dock's panel)
			gl.DrawMiniMap()
			resetGL()
			SP.holeFrame(L.hole)
		end
	end
	resetGL()
	local tRes = PROF.on and spGetTimer() -- (profiling: the resource panels' share, drawn live every frame)
	if not (L.land and rightKind == "dgun") then -- (sideways FIRE stands where they are: their edges showed round it)
		SP.drawRes()
		SP.drawWindTide()
	end
	if tRes then
		PROF.resMs = (PROF.resMs or 0) + spDiffTimers(spGetTimer(), tRes) * 1000
	end
	drawQueueZones()
	if inTex and dockTex then -- (a resource panel's bar: live over the texture)
		SP.drawResBars()
	end
	if rightKind == "place" then
		drawPlace()
	end
	if rightKind == "dgun" then
		drawDgun()
		return -- (no camera pad dimming or menu edge: the sticks are always live)
	end
	drawMode()
	SP.drawWindInfo() -- (over the camera pad's dimming: it is open, it reads as such)
end

function widget:DrawScreen()
	if not active or L.aside then
		return
	end
	if drawCursor then -- (again here: after the engine has picked its own for the frame)
		Spring.SetMouseCursor(drawCursor)
	end
	font = WG.fonts and WG.fonts.getFont() or font
	bold = WG.fonts and WG.fonts.getFont(2) or font
	if not font then
		return
	end
	if not PROF.on then
		drawDock()
		return
	end
	local t0 = spGetTimer()
	drawDock()
	PROF.sum, PROF.n = PROF.sum + spDiffTimers(spGetTimer(), t0) * 1000, PROF.n + 1
	if now() - PROF.at >= 10 then
		Spring.Echo(string.format("[bardroid-portrait] drawing %.2f ms a frame (%d frames), %d refreshes taking %.2f ms each, "
			.. "%d texture draws taking %.2f ms each, the resources %.2f ms a frame (drawn %d times)", PROF.sum / max(1, PROF.n),
			PROF.n, PROF.refreshN, PROF.refreshMs / max(1, PROF.refreshN), PROF.texN, PROF.texMs / max(1, PROF.texN),
			(PROF.resMs or 0) / max(1, PROF.n), PROF.resN or 0))
		PROF.sum, PROF.n, PROF.at, PROF.refreshN, PROF.refreshMs, PROF.texN, PROF.texMs = 0, 0, now(), 0, 0, 0, 0
		PROF.resMs, PROF.resN = 0, 0
	end
end

-- Before the game, BAR's draft-order pregame (gui_pregameui_draft.lua, layer -999999: drawn after every widget) writes
-- its lines 19-27 % up the screen ("Pick a starting location within the green area then click Ready", "Waiting for
-- ..."): upright that is across the dock's tiles and RANDOM. The dock is drawn again over that band, after everything,
-- unless one of BAR's windows is open there. (map_startbox's own line, without the draft order, is under the dock already.)
function widget:DrawScreenPost()
	-- (only over a dock drawn this frame: not over the lobby's overlay, a modal window or a hidden interface, when BAR's
	-- handler skips the widgets' DrawScreen but not this)
	if not (active and font and dockTex) or texMode == 0 or Spring.GetGameFrame() > 0 or SP.hidden
		or L.drawFrame ~= Spring.GetDrawFrame() then
		return
	end
	if L.aside then
		return
	end
	for _, name in ipairs({ "missioninfo", "scavengerinfo" }) do
		local w = WG[name]
		if w and w.isvisible and w.isvisible() then
			return
		end
	end
	local y0, y1 = max(L.dock[2], floor(vsy * 0.19)), min(L.dock[4], math.ceil(vsy * 0.27))
	if y1 <= y0 then
		return
	end
	gl.Scissor(L.dock[1], y0, L.dock[3] - L.dock[1], y1 - y0)
	drawDock(true)
	-- (sideways the texture leaves the minimap's place clear: BAR's line showed through there, "...ocation within the
	-- green area t" across the map, dev phone 2026-11-17, a skirmish from the lobby; the minimap drawn again over the band,
	-- as drawDock does without the texture)
	if L.hole and not L.split and dockTex then
		gl.DrawMiniMap()
		resetGL()
	end
	gl.Scissor(false)
end

-- the circle being dragged, on the ground in BAR's gold
function widget:DrawWorld()
	local c = active and selecting and circle
	if not (c and c.r > 0) then
		return
	end
	gl.DepthTest(false)
	gl.LineWidth(3)
	gl.Color(1, 0.78, 0.25, 0.9)
	gl.DrawGroundCircle(c.x, c.y, c.z, c.r, 64)
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

function widget:IsAbove(x, y)
	return active and not L.aside and inRect(x, y, L.dock) and not (L.hole and inRect(x, y, L.hole))
end

-- One of BAR's big windows open (Settings, Game info, Keybinds, Changelog, the Widget Selector): centred at their
-- landscape size they run down over the dock (sideways Settings' Environment rows lay under its bars and tabs, the two
-- drawn through each other, dev phone 2026-11-13; upright they are wider than the screen as well): the dock steps
-- aside, not drawn and no rects for RtsTouch ("dock none"), until the window closes; BAR's own panels stay hidden
SP.WINDOWS = { "options", "gameinfo", "keybinds", "changelog", "widgetselector" } -- (once, not a list each frame)
function SP.windowOpen()
	if not active then
		return false
	end
	-- (and the game over: BAR's Awards, centred, ran down under the dock, its Leave and Show Graphs at its foot out of
	-- reach upright, the player resigned and the spectator's grid up; dev phone 2026-11-17. Nothing to order then)
	if SP.gameOver then
		return true
	end
	for _, name in ipairs(SP.WINDOWS) do
		local w = WG[name]
		if w and w.isvisible and w.isvisible() then
			return true
		end
	end
	-- (and BAR's Statistics sideways on a tall phone: the app's copy is as large as fits there, over the dock; fitted
	-- above it its words were about 11 pixels high. Upright and over the split dock it fits above the dock:
	-- bardroid_teamstats.lua ViewResize, by WG.BarDroidPortrait.sideways)
	local ts = WG.teamstats
	return L.land and not L.split and ts and ts.isvisible and ts.isvisible() or false
end

-- The game over (BAR's Awards up): the dock steps aside for good (SP.windowOpen)
function widget:GameOver()
	SP.gameOver = true
end

function widget:GetConfigData()
	return { selStyle = selStyle, selFilter = selFilter, landSide = L.side }
end

function widget:SetConfigData(data)
	if data and (data.selStyle == "box" or data.selStyle == "circle") then
		selStyle = data.selStyle
	end
	if data and type(data.selFilter) == "string" then
		selFilter = data.selFilter
	end
	if data and (data.landSide == "left" or data.landSide == "right") then -- (sideways, one thumb: the side picked)
		L.side = data.landSide
	end
end

-- presses come from fingers in menu mode (RtsTouch clicks the dock only then), a mouse, or the pad's pointer
function widget:MousePress(x, y, btn)
	pingT.eat = false -- (a ping's release that never came must not eat this press's)
	if L.aside then -- (stepped aside for one of BAR's windows: SP.windowOpen)
		return false
	end
	-- BAR's wind or tide details (SP.drawWindInfo): any press closes them, one on them or on their box is theirs; a press on
	-- the wind's or the tide's box opens them
	local info = SP.windInfo
	if info then
		SP.windInfo = nil
		if inRect(x, y, info.rect) or inRect(x, y, info.box) then
			return true
		end
	end
	if active and not SP.windOff() then
		local wb, tb = SP.windRects()
		local hit = inRect(x, y, wb) and "wind" or inRect(x, y, tb) and "tide"
		if hit then
			SP.windInfo = { kind = hit, box = hit == "wind" and wb or tb, at = now() }
			Spring.Echo("[bardroid-portrait] the " .. hit .. "'s details") -- (tools)
			touched()
			return true
		end
	end
	local onMap = L.hole and inRect(x, y, L.hole) -- (sideways: BAR's minimap in the dock's middle)
	if active and btn == 1 and pingT.armed() and (onMap or not inRect(x, y, L.dock)) then -- PINGS' PING: a ping where the map is
		-- tapped (on the minimap: the place it shows), as BAR's own point marker
		local kind, pos = Spring.TraceScreenRay(x, y, true, true)
		local v = pingT.voice
		if kind == "ground" and pos and v and not v.endedAt then -- (PING held, its words not in yet: the spot, the
			-- ping drops there with them)
			v.spot = { pos[1], pos[2], pos[3] }
			Spring.Echo("[bardroid-portrait] a spoken ping's spot at " .. floor(pos[1]) .. " " .. floor(pos[3])) -- (tools)
			markDirty()
		elseif kind == "ground" and pos then
			Spring.MarkerAddPoint(pos[1], pos[2], pos[3], pingT.label or "") -- (with what was said for it, if PING was held)
			Spring.Echo("[bardroid-portrait] a ping at " .. floor(pos[1]) .. " " .. floor(pos[3])
				.. (pingT.label and " with its words" or "")) -- (tools)
			-- (and a spoken ping's spot that got no words goes: this tap is the ping; it dropped a second, plain, at that
			-- spot 1.5 s after the listening ended, review 2026-11-15)
			pingT.armedAt, pingT.label = nil, nil
			if v and v.endedAt then
				pingT.voice = nil
			end
			markDirty()
		end
		pingT.eat = true
		return true
	end
	if not (active and inRect(x, y, L.dock)) or onMap then
		return false
	end
	if SP.hidden then -- (the SHOW button clicked with a mouse: fingers have it through act dock_menu)
		SP.setHidden(false)
		return true
	end
	touched()
	local pr = placeRect()
	if pr and inRect(x, y, pr) then -- the PLACE panel: the build menu copy's (rotate, cancel; PLACE is RtsTouch's)
		local B = WG.bardroidBuildmenu
		if B and B.droidPressPanel then
			B.droidPressPanel(x, y)
		end
		return true
	end
	if rightKind == "presets" and WG.BarDroidPresets and inRect(x, y, SP.presetsX(homeRect())) then
		WG.BarDroidPresets.close() -- (the presets' X)
		return true
	end
	local wide = rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets"
	local side = wide and inRect(x, y, homeRect()) and "right" -- (the whole grid: both halves)
		or SP.overRect and inRect(x, y, SP.overRect) and "over" -- (the orders' overflow under a pick's types)
		or inRect(x, y, L.left) and "left" or inRect(x, y, L.right) and "right" or nil
	if side == "right" and rightKind == "panel" then -- a resource bar: its nearer knob (energy: share or conversion) set
		-- where pressed, then follows the finger
		for i, item in ipairs(rightItems) do
			local cr = cellRect("right", i)
			if item.kind == "slider" and cr and inRect(x, y, cr) then
				local what = "share"
				if item.res == "energy" then
					local b = SP.barArea(cr)
					local w = b[3] - b[1]
					local dc = abs(b[1] + w * sliderValue(item, "convert") - x)
					local ds = abs(b[1] + w * sliderValue(item, "share") - x)
					what = dc < ds and "convert" or "share"
				end
				slide = { item = item, rect = cr, what = what }
				setSlider(item, cr, x, what)
				return true
			end
		end
	end
	-- (empty space in the open menu: a drag there pans the camera as the camera pad does; Kailil, 2026-11-10: "if I grab
	-- empty space in the ui and moved my finger around, let that pan my camera"; a half whose rows scroll keeps its drag)
	local empty -- (a half with nothing to scroll: a drag anywhere on it pans, as the fingers' dockscroll lines do)
	local settling -- (its rows still settling after a flick: a tap is no press, its item was passing under the finger)
	if side then
		local _, s = half(side)
		empty = snapMax(s) == 0
		settling = not s.drag and s.t < 1
	else
		empty = not (inRect(x, y, L.res) or (showSel and inRect(x, y, L.sel)) or SP.thumbAt(x, y))
		for _, gr in ipairs(L.groupRects or {}) do
			empty = empty and not inRect(x, y, gr)
		end
	end
	-- (sideways with BUILD | ORDERS: a sideways swipe on the panel changes the tab; Kailil, 2026-11-17, "in horizontal
	-- landscape mode, allow me to change tabs out of the build tab/orders by swiping right to left". RtsTouch hands a
	-- sideways drag on the dock over as a mouse drag; before, its release pressed the tile it began on)
	local swipeOk = L.land and L.tabsOn and not L.split and not L.dgun and (side == "left" or side == "right"
		or showSel and inRect(x, y, L.sel) or L.tabs and (inRect(x, y, L.tabs.left) or inRect(x, y, L.tabs.right)))
	press = { side = side, x = x, y = y, button = btn, lastY = y, lastT = now(), vel = 0, empty = empty,
		panX = x, panY = y, settling = settling, swipeOk = swipeOk }
	return true -- (the dock is the dock's: no press goes through to the map under it)
end


function widget:MouseMove(x, y)
	if slide then
		setSlider(slide.item, slide.rect, x, slide.what)
		touched()
		return
	end
	local p = press
	if p and p.swipeOk and not p.moved and not p.swiping and abs(x - p.x) >= vsx * 0.012
		and abs(x - p.x) > 1.5 * abs(y - p.y) then
		p.swiping = true -- (the tab swipe: neither a pan nor the rows' scroll, MouseRelease)
	end
	if p and p.swiping then
		touched()
		return
	end
	if p and p.empty then
		if not p.moved and abs(x - p.x) + abs(y - p.y) < vsx * 0.012 then
			return
		end
		p.moved = true
		panBy(x - p.panX, y - p.panY)
		p.panX, p.panY = x, y
		touched()
		return
	end
	if not (p and p.side) then
		return
	end
	if not p.moved and abs(y - p.y) < vsx * 0.012 then
		return
	end
	p.moved = true
	local _, s, _, _, _, ch = half(p.side)
	snapBy(s, y - p.lastY, ch + L.gap) -- (a mouse drag: the rows follow it)
	local t = now()
	if t > p.lastT then
		p.vel = 0.6 * p.vel + 0.4 * ((y - p.lastY) / (ch + L.gap) / (t - p.lastT))
	end
	p.lastY, p.lastT = y, t
	touched()
end

function widget:MouseRelease(x, _, btn)
	if pingT.eat then -- (the ping's tap: not the map's)
		pingT.eat = false
		return true
	end
	if slide then
		setSlider(slide.item, slide.rect, x, slide.what)
		slide = nil
		refresh()
		return true
	end
	local p = press
	press = nil
	if not p then
		return false
	end
	if p.swiping then -- the tab swipe (either way: two tabs), far enough; a shorter one does nothing
		if abs(x - p.x) >= vsx * 0.035 and L.land and L.tabsOn then
			L.tab = L.tab == "left" and "right" or "left"
			Spring.Echo("[bardroid-portrait] swiped to the " .. L.tab .. " tab") -- (tools)
			layout()
			refresh()
		end
		return true
	end
	if p.empty and (p.moved or not p.side) then -- (a pan, or a tap on nothing; a tap on a half with nothing to scroll is
		-- its button's: those halves were all "empty" for the pan, and their buttons took no taps, 2026-11-10)
		return true
	end
	local thumb = not p.side and SP.thumbAt(p.x, p.y)
	if thumb == "home" then -- (sideways, one thumb: the home buttons in the panel, which no longer hides them: HOME lets
		-- the pick go, so they show; it had opened and closed the hidden panel)
		Spring.SelectUnitArray({})
		-- (and a unit list with MULTI on let go too: the list stayed, its right half empty, not the home buttons; review
		-- 2026-11-16)
		typesFrom, multi, multiPicked, allPicked = nil, false, {}, false
		L.homeOpen = false
		refresh()
		return true
	elseif thumb == "swap" then -- (the dock to the other side of the screen; kept for the next game, GetConfigData)
		L.side = L.side == "left" and "right" or "left"
		Spring.Echo("[bardroid-portrait] the dock on the " .. L.side) -- (tools)
		layout()
		refresh()
		writeDock(true)
		return true
	elseif thumb then -- a tab: its side's buttons in the panel
		if L.tab ~= thumb then
			L.tab = thumb
			layout()
			refresh()
		end
		return true
	end
	local nk = L.windNook -- (the nook between metal and energy: its edges around the pill open neither)
	if nk and nk.kind == "res" and not SP.windOff() and inRect(p.x, p.y, nk) then
		return true
	end
	if not p.side and inRect(p.x, p.y, L.res) and leftKind ~= "spec" then -- metal or energy tapped: its panel (again:
		-- closed; spectating, nothing to share or convert: none)
		local res = p.x < (L.res[1] + L.res[3]) / 2 and "metal" or "energy"
		resPanel = resPanel ~= res and res or nil
		sharing = nil
		refresh()
		return true
	end
	if p.side then
		if p.moved then
			local _, s = half(p.side)
			snapRelease(s, p.vel)
			return true
		end
		-- (a tap while the rows settled after a flick picked the item passing under the finger, a building at random;
		-- dev phone, a flick and a tap, 2026-11-11: the rows settle on, the tap picks nothing)
		if p.settling then
			Spring.Echo("[bardroid-portrait] a tap on settling rows: no press") -- (tools)
			return true
		end
		pingT.pressX = p.x -- (PINGS: which of its halves)
		local item = itemAt(p.side, p.x, p.y)
		if item and L.split and p.side == "left" and (resPanel or sharing) then -- (the split's left block beside an open
			-- panel or picker, refreshNow: its press puts them away first)
			resPanel, sharing = nil, nil
		end
		pressItem(item, btn == 3)
		return true
	end
	if L.groupRects then -- a control group's picture: those units; "+ NEW": the types picked become the next free group,
		-- every one of them now and later (Kailil, 2026-11-10: "Unit groups at the bottom should use the unit group vanilla
		-- behavior. Assigning a unit type to a group", BAR's Auto Group, its Alt+number); a long press on a picture takes
		-- that group's assignment off ("hold the unit pictures and it unassign the group assignment")
		for _, gr in ipairs(L.groupRects) do
			if inRect(p.x, p.y, gr) then
				local A = WG.autogroup
				if gr.unq then
					removeOrder(gr.unq == "last")
				elseif gr.idle then -- an idle builder type: the next of them picked, the camera on it
					idleB.pick(gr.idle)
				elseif gr.new then
					if A and A.addCurrentSelectionToAutogroup then
						A.addCurrentSelectionToAutogroup(gr.new)
					else -- (no Auto Group: the engine's own group of the units picked, as BAR's Ctrl+number)
						Spring.SendCommands("group set " .. gr.new)
					end
					Spring.Echo("[bardroid-portrait] group " .. gr.new .. " made") -- (tools)
				elseif btn == 3 then
					local types = A and A.getGroups and A.getGroups()
					for defID, g in pairs(types or {}) do
						if tonumber(g) == gr.group then
							types[defID] = nil
						end
					end
					for _, u in ipairs(Spring.GetGroupUnits(gr.group) or {}) do
						Spring.SetUnitGroup(u, -1)
					end
					Spring.Echo("[bardroid-portrait] group " .. gr.group .. " unassigned")
				else
					Spring.SendCommands("group select " .. gr.group)
				end
				refresh()
				return true
			end
		end
	end
	return true
end

function widget:ViewResize()
	checkActive()
end

function widget:Initialize()
	do -- (the launcher's "Touch dock sideways": launch-bar.sh leaves this file while it is on)
		local f = io.open("LuaUI/Config/bardroid_landdock.txt", "r")
		L.landOn = f ~= nil
		if f then
			f:close()
		end
	end
	WG.BarDroidPortrait = {
		active = function()
			return active
		end,
		sideways = function() -- (layout A: the dock along the bottom of a wide screen, BAR's minimap in it; not the split
			-- dock, which gives BAR's minimap its own corner back: the chat had laid itself over it and the minimap no
			-- longer waited half size, review 2026-11-15)
			return active and L.land and not L.split or false
		end,
		dock = function() -- (other widgets keep out of it: x0, y0, x1, y1; the wind's and tide's boxes over it with it)
			return active and SP.dockAll() or nil
		end,
		-- (stepped aside, its room free: one of BAR's big windows, BAR's lobby over the game, the game over; dock() still
		-- answers its rect: bardroid_teamstats.lua upright takes the whole height then)
		aside = function()
			return active and L.aside or false
		end,
		-- (the wind's and the tide's boxes where they are shown, and which one's details are open: tools/dock-phone-test)
		windRects = function()
			if active and not SP.windOff() then
				return SP.windRects()
			end
		end,
		windOpen = function()
			return SP.windInfo and SP.windInfo.kind or nil
		end,
		-- (tools/dock-phone-test.ps1: the details closed before the next case: open for 15 s they lay over the metal spot
		-- Area Mex's tap was for, 2026-11-19)
		windClose = function()
			SP.windInfo = nil
		end,
		resBoxes = function() -- (tools/dock-phone-test.ps1: metal's and energy's boxes, GL pixels)
			if active and L.res then
				return SP.resBoxes()
			end
		end,
		gridRect = function() -- (tools/dock-phone-test.ps1: where the home grid, a panel or the teammate picker stands)
			if active then
				return homeRect()
			end
		end,
		-- (a screen point on the dock itself: the split dock's band less the game between its blocks, where a building's
		-- spot or a preset's tap belongs to the game; dock() alone refused both there, review 2026-11-15)
		onDock = function(x, y)
			local d = active and SP.dockAll()
			if not (d and x >= d[1] and x <= d[3] and y >= d[2] and y <= d[4]) then
				return false
			end
			local h = L.split and L.hole
			return not (h and x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4])
		end,
		placeRect = placeRect, -- (the build menu copy's PLACE panel goes there while a building is picked)
		queueRect = function() -- (bardroid_pad.lua's QUEUE, the fingers' sticky Shift: the selection row's right two
			-- thirds; none while nothing is picked)
			if not (active and showSel) then
				return nil
			end
			local _, q = queueZones()
			return q
		end,
		insertRect = function() -- (its INSERT, BAR's CommandInsert: the row's left third)
			if not (active and showSel) then
				return nil
			end
			return (queueZones())
		end,
		menu = function()
			return menu
		end,
		refresh = refresh, -- (bardroid_presets.lua: its presets opened or closed)
		voicePing = pingT.voicePing, -- (bardroid_touch.lua: words said for PING held; true: taken)
		pingState = function() -- (tools: PING's states: chat started and ended, a spoken ping waiting, its label)
			local c, v = pingT.chat, pingT.voice
			return { chat = c and (c.endAt and "ending" or "on") or nil, voice = v and (v.spot and "spot" or "listening") or nil,
				label = pingT.label, armed = pingT.armed() }
		end,
		cameraTo = cameraTo, -- (bardroid_touch.lua: a point in the middle of the game above the dock; a loaded game)
		-- (tools/dock-phone-test.ps1: the first item of a half the test function takes: its cell (GL pixels, where it is
		-- drawn now: off the half when scrolled away) and the item)
		itemCell = function(side, test)
			for i, it in ipairs(side == "left" and leftItems or rightItems) do
				if test(it) then
					return cellRect(side, i), it
				end
			end
		end,
		-- (tools: the selection's style, "box" or "circle", as SELECT: BOX / CIRCLE sets it; the style now)
		selectStyle = function(s)
			if s == "box" or s == "circle" then
				selStyle = s
				writeDock(true)
			end
			return selStyle
		end,
	}
	checkActive()
	writeDock(true)
end

function widget:Shutdown()
	if dockTex then
		gl.DeleteTexture(dockTex)
	end
	if L.resTex then
		gl.DeleteTexture(L.resTex)
	end
	if SP.windBackDL and SP.windBackDL.id then
		gl.DeleteList(SP.windBackDL.id)
	end
	if SP.tipOwner and SP.tipOwner.ShowTooltip == SP.tipWrap then -- (BAR's tooltip widget as it was)
		SP.tipOwner.ShowTooltip = SP.tipInner
	end
	WG.BarDroidPortrait = nil
	active = false
	-- (BAR's player list back too: folded, or hidden under the D-gun mode's sticks or with the dock aside, widget:Update)
	if (SP.hidden or SP.listOff) and WG.advplayerlist_api and WG.advplayerlist_api.SetHidden then
		WG.advplayerlist_api.SetHidden(false)
	end
	SP.landMinimap() -- (BAR's minimap back in its own place)
	topbarBars(false)
	writeDock(true)
	if logFile then
		logFile:close()
	end
end
