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
local DOCK_MAX = 0.54 -- of the screen's height at most
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
local slide = nil -- a slider being dragged: { item, rect }
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
-- (a picked unit with a building queued: a one-finger drag pans the camera, it draws no move path, until the queue's
-- buildings are done; MOVE, FIGHT or PATROL pressed still draws one. Kailil, 2026-11-11: "It is very easy to place a
-- move path after placing a build order on accident due to the muscle memory of grabbing the screen")
function idleB.buildBusy()
	local t = now()
	if idleB.busyAt and t - idleB.busyAt < 0.3 then
		return idleB.busy
	end
	idleB.busyAt = t
	local busy = false
	local sel = spGetSelectedUnits() or {}
	for i = 1, min(#sel, 60) do
		for _, c in ipairs(Spring.GetUnitCommands(sel[i], 16) or {}) do
			if c.id < 0 then -- (a building)
				busy = true
				break
			end
		end
		if busy then
			break
		end
	end
	idleB.busy = busy
	return busy
end

-- Spectating upright in the dock (Kailil, 2026-11-11, a spectated online game: "The spectator mode buttons is much too
-- small. Unify the look and feel between playing and spectating with the bottom half ui experience. Hide the team list
-- and create a team list inside of our ui experience ... next to ping and last pings ... last pings shoukd be the only
-- option instead of ping. Add a toggle to hide the bottom half ui that will leave a small un hide button"): the spectate
-- widget's tools (bardroid_spectate.lua, WG.BarDroidSpectate) as the dock's big buttons over its whole grid, 6 narrow
-- columns (the arrows one each); TEAMS lists the players by alliance in the grid's place (BAR's own list, at the
-- bottom right, is under the dock); HIDE folds the dock to a small SHOW button at the bottom of the screen.
local SP = { hidden = false, teams = false, COLS = 6 }
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
		if n % 2 == 1 then -- (the next alliance from a new row: an empty place, no button drawn there)
			out[#out + 1] = { kind = "gap", w = SP.COLS / 2 }
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
	L.thumb, L.tabs, L.homeBtn, L.swapBtn = false, nil, nil, nil
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
		-- (HOME over the swap button, on the panel's side of the minimap: next to what it opens)
		local col = right and { M[3] - colW, my0, M[3], my1 } or { M[1], my0, M[1] + colW, my1 }
		local cmid = floor((my0 + my1) / 2)
		L.homeBtn = { col[1], cmid + floor(gap / 2), col[3], col[4] }
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
		L.leftCols = max(3, min(6, floor((panelW + gap) / (tile + gap))))
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
		L.leftCols = max(3, min(6, floor((sideW + gap) / (tile + gap))))
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
		L.btnW = floor((sideW - (L.rightCols - 1) * gap) / L.rightCols)
		L.rightRows = max(3, floor((inner + gap) / (floor(tile * 0.5) + gap)))
		L.btnH = floor((inner + gap) / L.rightRows) - gap
		SP.laidOut = false
		return
	end
	local pad = max(4, floor(vsx * 0.012))
	local gap = max(3, floor(pad * 0.6))
	-- (by the width, and by the height on a near-square screen: the unfolded Fold7 upright, 1080x1198, gave a quarter
	-- of its short dock to these rows and the build grid small tiles beside a blank strip; tall phones keep the width's)
	local selH = floor(min(vsx * 0.15, vsy * 0.09))
	local groupsH = floor(min(vsx * 0.13, vsy * 0.075))
	local half = floor(vsx * 0.5)
	local tile = floor((half - pad - floor(pad / 2) - 2 * gap) / 3)
	local room = floor(vsy * DOCK_MAX) - (pad * 4 + selH + groupsH) -- the grid's height at most
	local rows = max(2, min(4, floor((room + gap) / (tile + gap))))
	if rows * (tile + gap) - gap > room then -- (2 rows that do not fit: smaller tiles)
		tile = max(16, floor((room + gap) / rows) - gap)
	end
	local resH = floor(min(vsx * 0.06, vsy * 0.04))
	room = room - resH - pad
	rows = max(2, min(4, floor((room + gap) / (tile + gap))))
	if rows * (tile + gap) - gap > room then
		tile = max(16, floor((room + gap) / rows) - gap)
	end
	local gridH = rows * (tile + gap) - gap
	SP.laidOut = SP.on() and true or false
	if SP.laidOut then -- (spectating: no selection or groups rows; their room to the grid, up to five button rows as tall
		-- as the build tiles: on the unfolded Fold7 the spectator's five rows were 62 pixels, dev phone at 1080x1198)
		gridH = max(gridH, min(5 * (tile + gap) - gap, room + selH + groupsH + 2 * pad))
	end
	L.pad, L.gap, L.tile, L.leftRows = pad, gap, tile, rows
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
	if active then
		local function r(x)
			return string.format("%d %d %d %d", x[1], vsy - x[4], x[3], vsy - x[2])
		end
		local _, cmd = spGetActiveCommand()
		local draw = DRAW_CMDS[cmd] or (cmd == nil and mobilePicked and not idleB.buildBusy())
		-- (folded, HIDE: the SHOW button alone, a camera pad whose tap brings the dock back, act dock_menu)
		local lr = SP.hidden and L.dock
		text = string.format("dock %s %s\nleft %s\nright %s\nselect %s\ndraw %d\n", r(L.dock), menu and "menu" or "pad",
			r(lr or L.left), r(lr or L.right), selStyle, draw and 1 or 0)
			.. (showGroups and not SP.hidden and ("groups " .. r(L.groups) .. "\n") or "")
			.. (L.hole and ("map " .. r(L.hole) .. "\n") or "") -- (sideways: BAR's minimap, its touches the engine's)
			-- (the build options, a builder's or a factory's, shown: their first tap acts, the camera pad or not; Kailil,
			-- 2026-11-12, "The build menus and factory build menus should all have this no tap required")
			.. ((leftKind == "build" or leftKind == "pregame") and L.left[3] > 0 and not SP.hidden
				and ("live " .. r(L.left) .. "\n") or "")
			-- (and the selection row: INSERT and QUEUE. Kailil, 2026-11-12, a Bot Lab: "Insert plus tapoing a unit to build.
			-- Is not interrupting the build queue": with the camera pad up INSERT's tap only opened the menu, and the unit's
			-- tap, which acts at once, went to the queue's end)
			.. (showSel and not SP.hidden and leftKind ~= "spec" and L.sel and L.sel[3] > L.sel[1]
				and ("live " .. r(L.sel) .. "\n") or "")
			-- (and the home grid, nothing picked: Kailil, 2026-11-12, "make rhe commander button. All units and local
			-- units buttins not need the ui one tap engage. Allow me to be able to directly click them"; sideways while
			-- HOME's panel is open)
			.. (rightKind == "home" and leftKind ~= "spec" and not SP.hidden and (not L.thumb or L.homeOpen)
				and ("live " .. r(SP.homeLive()) .. "\n") or "")
			-- (and the groups row: the unit groups and the idle builders, the same "directly click them")
			.. (showGroups and not SP.hidden and L.groups and L.groups[3] > L.groups[1]
				and ("live " .. r(L.groups) .. "\n") or "")
			-- (sideways, one thumb: the BUILD | ORDERS tabs; HOME opens with the menu's first tap anyway)
			.. (L.thumb and L.tabsOn and L.tabs and L.tabs.left and L.tabs.right and not SP.hidden
				and ("live " .. r(L.tabs.left) .. "\nlive " .. r(L.tabs.right) .. "\n") or "")
			-- (PING on the home grid: held, a spoken ping; tapped twice, CHAT; pingT)
			.. (rightKind == "home" and leftKind ~= "spec" and L.pingBtn and not SP.hidden and (not L.thumb or L.homeOpen)
				and ("ping " .. r(L.pingBtn) .. "\n") or "")
			.. (dgunLines and dgunLines() or "")
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
local function readCommands()
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

-- its parts in the grid: the sticks (x, y, radius), FIRE and the cancel corner (rects); GL pixels
local function dgunParts()
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
	local c = floor(min(w * 0.13, h * 0.2))
	return { l = { r[1] + floor(w * 0.24), cy, rad }, r = { r[3] - floor(w * 0.24), cy, rad }, fire = fire,
		cancel = { r[1], r[4] - c, r[1] + c, r[4] } }
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
	return string.format("dgun 1\nstickl %d %d %d\nstickr %d %d %d\nfire %s\ncancel %s\ndgunauto %d\n", p.l[1], vsy - p.l[2],
		p.l[3], p.r[1], vsy - p.r[2], p.r[3], rect(p.fire), rect(p.cancel), auto and 1 or 0)
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

-- the resource panel: BAR's top bar's sliders (energy: conversion, grey; both: sharing above, red), SEND, CLOSE
local function panelItems(res)
	local items = {}
	if res == "energy" then
		items[#items + 1] = { kind = "slider", what = "convert", res = res, label = "CONVERT ENERGY ABOVE", w = 2 }
	end
	-- (its resource named, as CONVERT ENERGY's: "SHARE TO ALLIES ABOVE" alone read the same in both panels, dev phone
	-- 2026-11-12)
	items[#items + 1] = { kind = "slider", what = "share", res = res, label = "SHARE " .. string.upper(res) .. " TO ALLIES ABOVE",
		w = 2 }
	if #teammateList() > 0 then
		items[#items + 1] = { kind = "sendres", res = res, label = res == "metal" and "SEND METAL" or "SEND ENERGY", w = 2 }
	end
	items[#items + 1] = { kind = "panelclose", label = "CLOSE", w = 2 }
	return items
end

local function sliderValue(item)
	if item.what == "convert" then
		return Spring.GetTeamRulesParam(myTeam(), "mmLevel") or 0.75
	end
	return select(6, Spring.GetTeamResources(myTeam(), item.res)) or 1
end

-- a slider set from x across its track (BAR's own calls: SetShareLevel; conversion, its LuaRules message 12-88 %)
local function setSlider(item, r, x)
	local v = max(0, min(1, (x - r[1]) / max(1, r[3] - r[1])))
	if item.what == "convert" then
		Spring.SendLuaRulesMsg(string.format(string.char(137) .. "%i", max(12, min(88, floor(v * 100 + 0.5)))))
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
	return pingT.armedAt ~= nil and now() - pingT.armedAt < pingT.ARM
		or pingT.voice ~= nil and pingT.voice.endedAt == nil
end
function pingT.look()
	local Pd = WG.BarDroidPad
	if Pd and Pd.pingLook then
		Pd.pingLook(pingT.KEPT)
	end
end
-- (how many pings from others wait, in gold at LAST PINGS' top right as the idle builders' counts: it said nothing of
-- whether there was one to see)
function pingT.badge(r, n)
	if n > 0 and bold then
		local h = r[4] - r[2]
		bold:Print("\255\255\200\064" .. n, r[3] - max(4, h * 0.08), r[4] - h * 0.3, h * 0.24, "ro")
	end
end
function pingT.state() -- (what the tile shows: "LAST PINGS" or "PING 2 OF 4", PING lit while armed)
	local Pd = WG.BarDroidPad
	local n, step = 0, 0
	if Pd and Pd.pingCount then
		n, step = Pd.pingCount()
	end
	return min(n, pingT.KEPT), step, pingT.armed()
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
	elseif name == "voice_off" or name == "voice_none" or name == "voice_nomic" then
		if c and not c.endAt then
			c.endAt = t
		end
		if v and not v.endedAt then
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
		elseif not c.endAt and not c.on and t - c.at > 8 then
			c.endAt = t
		end
		markDirty() -- (the flip, the burst, CHAT's glow)
	end
	if v then
		if v.endedAt and t - v.endedAt > 1.5 or t - v.at > 40 then
			pingT.voice = nil
			if v.spot then
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
		cameraTo(x, y, z)
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
	local wantSel, wantGroups = #sel > 0 and not dg, (#sel > 0 or anyGroup or #idleB.list > 0) and not dg
	if wantSel ~= showSel or wantGroups ~= showGroups then -- (the dock's rows: laid out again)
		showSel, showGroups = wantSel, wantGroups
		layout()
	end
	local unq = #sel > 0 and selectedFactory()
	for i = 1, unq and 0 or #sel do
		if (Spring.GetUnitCommandCount(sel[i]) or 0) > 0 then
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
	local newLeft, newRight, lk, rk
	local pregame = #sel == 0 and not typesFrom and pregameStart()
	if pregame then
		newLeft, lk = pregameItems(pregame), "pregame"
	elseif typesFrom then -- LOCAL / ALL UNITS: the combat units by type, ALL first (IDLE: every idle unit)
		local types = byType(typesUnits(), combat)
		newLeft = { { kind = "alltypes", label = "ALL", count = 0 } }
		for _, g in ipairs(types) do
			newLeft[#newLeft + 1] = g
			newLeft[1].count = newLeft[1].count + #g.units
		end
		lk = "types:" .. typesFrom
	elseif #sel == 0 then
		newLeft, lk = {}, "none"
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
		rk = "pregame"
	elseif typesFrom and #sel == 0 then -- a list on the left with nothing picked: the lists, MULTI and DONE (with units
		-- picked, their orders as for any pick: Kailil, 2026-11-10, "For selecting all units or local units. Get rid of the
		-- buttons thats on the right. Instead show the order buttons that appear when a unit is selected")
		newRight = {
			{ kind = "units", from = "local", label = "LOCAL UNITS" },
			{ kind = "units", from = "all", label = "ALL UNITS" },
			{ kind = "multi", label = multi and "MULTI: ON" or "MULTI" },
			{ kind = "done", label = "DONE" },
		}
		rk = "units"
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
		local qh = (need * 2 <= rr or rr >= 6 or rr % 2 == 0) and 2 or 1
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
			local bh = (L.rightRows or 3) >= 4 and 2 or 1
			local big = { [CMD.FIGHT] = { 1, 2, bh }, [CMD.MOVE] = { 2, 1, bh }, [CMD.PATROL] = { 3, 1, bh },
				[CMD.MANUALFIRE] = { 4, 2, 1 } }
			if not mobilePicked then
				big[CMD.MANUALFIRE], big[CMD.REPEAT] = nil, { 4, 2, 1 }
			end
			local first, rest = {}, {}
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
		if WG.BarDroidPresets and WG.BarDroidPresets.fits(sel) then -- (after FIGHT, MOVE, PATROL, D-gun: bardroid_presets.lua)
			local at = 1
			while newRight[at] and newRight[at].h do
				at = at + 1
			end
			table.insert(newRight, at, { kind = "presets", label = "PRESETS" })
		end
		newRight[#newRight + 1] = style
		newRight[#newRight + 1] = { kind = "filterpick", label = "FILTER: " .. selFilter:upper() }
	end
	if sharing or resPanel then -- (the picker or the panel: the whole grid)
		newLeft, lk = {}, sharing and "share" or "panel"
		-- (with nothing picked the home grid stays under the panel, a drop-down over it: it took the whole dock, half of
		-- it empty below CLOSE; a press on one of them closes the panel)
		local home = not sharing and rk == "home" and newRight
		newRight, rk = sharing and shareItems() or panelItems(resPanel), lk
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
	if L.land and not L.dgun then -- sideways, one thumb: the panel, its tabs and the tab shown (layout)
		-- (nothing picked: the map slot alone until a tap opens the home buttons; both sides with something: BUILD | ORDERS
		-- tabs, a builder opening on its build options and other units on their orders, a building picked on PLACE; a tab
		-- tapped stays until what the dock shows changes)
		local panelOn = not (lk == "none" and rk == "home" and not L.homeOpen)
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
	cellsOf.left, leftRowsN = pack(leftItems, L.leftCols or 3)
	cellsOf.right, rightRowsN = pack(rightItems, lk == "spec" and SP.COLS
		or (rk == "home" or rk == "presets" or rk == "share" or rk == "panel") and 2 or (rk == "place" and SP.shapeRow()) and 4
		or L.rightCols or 2)
	snapSet(leftScroll, leftRowsN, L.leftRows or 2, lk == leftKind and not newPick)
	local wideRows = max(1, floor((L.left[4] - L.left[2] + L.gap) / (floor(L.btnH * 1.5) + L.gap)))
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
	if rk ~= "home" and pingT.armedAt then -- (PING armed, then units picked: the next map tap is theirs, not a ping)
		pingT.armedAt = nil
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
		local _, sy = Spring.WorldToScreenCoords(x or 0, y or 0, z or 0)
		if x and sy >= L.dock[4] then
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
			-- upon first tapping all units or local units": the list stays, its ALL lit, a type still narrows it)
			local all = {}
			for _, g in ipairs(byType(typesUnits(), combat)) do
				for _, u in ipairs(g.units) do
					all[#all + 1] = u
				end
			end
			keepTypes, allPicked = true, #all > 0
			selectUnits(all)
		end
	elseif k == "multi" then
		multi, multiPicked = not multi, {}
	elseif k == "done" then
		typesFrom, multi, multiPicked = nil, false, {}
	elseif k == "alltypes" then
		local all = {}
		for _, g in ipairs(leftItems) do
			for _, u in ipairs(g.units or {}) do
				all[#all + 1] = u
			end
		end
		selectUnits(all)
		typesFrom, multi, multiPicked = nil, false, {}
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
			selectUnits({ u })
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
		if r and pingT.pressX and pingT.pressX >= (r[1] + r[3]) / 2 and leftKind ~= "spec" then
			pingT.armedAt = not pingT.armed() and now() or nil
			if WG.BarDroidPad and WG.BarDroidPad.say then
				WG.BarDroidPad.say(pingT.armedAt and "TAP THE MAP TO PING" or "NO PING")
			end
		else
			pingT.armedAt = nil
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
local function homeRect() -- (sideways: the right half's place, the minimap between the halves)
	return L.land and L.right or { L.left[1], L.left[2], L.right[3], L.right[4] }
end
function SP.homeLive() -- (writeDock's "live" home grid: it comes before homeRect)
	return homeRect()
end

-- a half's geometry: its rect, scroll, items, columns, cell width and height
local function half(side)
	if side == "left" then
		return L.left, leftScroll, leftItems, L.leftCols or 3, L.tile, L.tile
	end
	if rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets" then -- (the whole grid)
		local r = homeRect()
		local cols = leftKind == "spec" and SP.COLS or 2 -- (spectating: 6 narrow columns, SP)
		return r, rightScroll, rightItems, cols, floor((r[3] - r[1] - (cols - 1) * L.gap) / cols),
			(rightKind == "home" or rightKind == "presets") and floor((r[4] - r[2] + L.gap) / (L.homeRows or HOME_ROWS)) - L.gap
			or floor(L.btnH * 1.5)
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
	if side == "right" then -- (packed: the cell that holds the point)
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
	-- (at most 84% of the width: the outline is not in the font's width, and at 88% words that just fit, ROTATE in its
	-- square on the unfolded Fold7 upright, LAST PINGS, ran up to the button's edges: dev phone, 2026-11-11)
	local room = (x1 - x0) * 0.84
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
	if v and not v.endedAt then
		word, fill, edge = "SPEAK", { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 }
		sub = v.spot and "PING SET" or nil
	elseif armed then
		word, fill, edge = "TAP MAP", { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 }
		sub = pingT.label
	end
	local sy, burst = 1, nil
	if c then
		local chatFill, chatEdge = { 0.04, 0.2, 0.25, 0.95 }, { 0.25, 0.72, 0.85, 0.75 + 0.25 * math.sin(t * 6) ^ 2 }
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
	if item.kind == "alltypes" then
		button(r, { 0.2, 0.2, 0.2, 0.8 }, { 0.35, 0.35, 0.35, 0.8 })
		-- (none: dimmed, as FACTORIES with no factory; a lit "ALL 0" read as a list of something)
		local none = item.count == 0
		textIn("ALL", r[1], r[2] + h * 0.38, r[3], r[4], h * 0.26, none and "\255\140\140\140" or "\255\255\255\255", bold)
		textIn(tostring(item.count), r[1], r[2], r[3], r[2] + h * 0.42, h * 0.2, none and "\255\140\140\140" or "\255\255\200\064")
		if allPicked then -- (all of the list picked: LOCAL or ALL UNITS' first tap)
			selector(r)
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
	if item.kind == "build" or item.kind == "pregame" then -- (as BAR's build menu: metal white, energy yellow, bottom right)
		local ud = UnitDefs[item.defID]
		if ud then
			font:Print("\255\245\245\245" .. floor(ud.metalCost or 0), r[3] - p, r[2] + p + size * 1.05, size, "ro")
			font:Print("\255\255\255\000" .. floor(ud.energyCost or 0), r[3] - p, r[2] + p, size, "ro")
		end
		if item.queued and item.queued > 0 then
			bold:Print("\255\255\255\255" .. item.queued, r[1] + p * 1.5, r[4] - p - size * 1.5, size * 1.5, "o")
		end
		if item.id and (activeBuild() == item.id or factoryItem == item.id) then
			selector(r)
		end
	else -- a type: its count
		bold:Print("\255\255\255\255" .. #item.units, r[3] - p, r[2] + p, size * 1.4, "ro")
		if multi and multiPicked[item.defID] then
			selector(r)
		end
	end
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

local function drawSlider(item, r)
	button(r)
	local v = sliderValue(item)
	local h = r[4] - r[2]
	local tx0, tx1 = r[1] + h * 0.2, r[3] - h * 0.2
	local ty0 = r[2] + h * 0.2
	local ty1 = ty0 + max(4, floor(h * 0.16))
	gl.Color(0.08, 0.08, 0.08, 0.95)
	gl.Rect(tx0, ty0, tx1, ty1)
	if item.what == "convert" then -- (BAR's top bar: the conversion grey, the share red)
		gl.Color(0.72, 0.72, 0.72, 1)
	else
		gl.Color(0.86, 0.2, 0.18, 1)
	end
	local kx = tx0 + (tx1 - tx0) * v
	gl.Rect(tx0, ty0, kx, ty1)
	gl.Color(1, 1, 1, 1)
	gl.Rect(kx - 3, ty0 - h * 0.07, kx + 3, ty1 + h * 0.07)
	textIn(item.label .. "  " .. floor(v * 100 + 0.5) .. "%", r[1], ty1, r[3], r[4], h * 0.24, "\255\235\235\235", font)
end

local function drawButton(item, r)
	if item.kind == "slider" then
		drawSlider(item, r)
		return
	end
	if item.kind == "gap" then -- (TEAMS: the place after an alliance's odd team)
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
	if item.kind == "pings" then -- (two buttons in one place: the last pings, and a ping of your own)
		pingT.rect = r
		local n, step, armed = pingT.state()
		pingT.drawn = step .. (armed and "a" or "")
		local mx = floor((r[1] + r[3]) / 2)
		local gap = max(2, floor(L.gap / 2))
		local a, b = { r[1], r[2], mx - gap, r[4] }, { mx + gap, r[2], r[3], r[4] }
		button(a)
		local th = min((r[4] - r[2]) * 0.34, L.btnH * 0.46)
		textIn(step > 0 and string.format("%d OF %d", step, n) or "LAST PINGS", a[1], a[2], a[3], a[4], th,
			n > 0 and "\255\240\240\240" or "\255\140\140\140", font, true)
		pingT.badge(a, n)
		L.pingBtn = b -- (RtsTouch's "ping": its hold and its double tap; L: writeDock comes before pingT)
		pingT.drawBtn(b, armed, th)
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
	local on = armed or item.kind == "units" and typesFrom == item.from or item.kind == "multi" and multi
		or (item.kind == "specact" or item.kind == "specteam" or item.kind == "specfull") and item.on
		or item.kind == "shape" and currentShape() == item.shape or item.kind == "filter" and selFilter == item.key
		or item.kind == "faction" and Spring.GetTeamRulesParam(myTeam(), "startUnit") == item.startUnit
		or item.kind == "sharestep" and shareFraction == item.value or item.kind == "retreat" and item.on
	if on then -- (picked: BAR's gold)
		button(r, { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 })
	else
		button(r)
	end
	-- (the home grid's tall buttons: their words a little larger than the order buttons', not by their height)
	local label = armedName or item.label or ""
	local th = min((r[4] - r[2]) * 0.34, L.btnH * ((item.h or 1) > 1 and 0.6 or 0.46))
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
		textIn(label, r[1], r[2], r[3], r[4], th, (item.kind == "none" or item.dim) and "\255\140\140\140" or "\255\240\240\240",
			font, true)
	end
	if item.color then -- a teammate: their colour along the bottom
		gl.Color(item.color[1], item.color[2], item.color[3], 0.95)
		gl.Rect(r[1] + 8, r[2] + 5, r[3] - 8, r[2] + max(5, (r[4] - r[2]) * 0.09))
		gl.Color(1, 1, 1, 1)
	end
	if item.states and item.states > 1 then -- a state: its light along the bottom, as BAR's
		local st = min(3, (item.state or 0) + 1)
		local c = STATE_COLORS[(item.states == 2 and st == 2) and 3 or st]
		local w = (r[3] - r[1]) * 0.28
		local y = r[2] + max(3, (r[4] - r[2]) * 0.1)
		gl.Color(c)
		gl.Rect(r[3] - w - 6, y, r[3] - 6, y + max(2, (r[4] - r[2]) * 0.06))
		gl.Color(1, 1, 1, 1)
	end
	if lit then
		selector(r)
	end
end

local function drawHalf(side)
	local r, s, items = half(side)
	if r[3] < 0 then -- (sideways, one thumb: the tab not shown, laid out off the screen)
		return
	end
	SP.scissor(r[1], r[2], r[3] - r[1], r[4] - r[2])
	for i, item in ipairs(items) do
		local rect = cellRect(side, i)
		if rect and rect[2] < r[4] and rect[4] > r[2] then -- (in sight)
			if side == "left" then
				drawTile(item, rect)
			else
				drawButton(item, rect)
			end
		end
	end
	gl.Scissor(false)
	if side == "right" and rightKind == "presets" and WG.BarDroidPresets then -- (the presets' X, in the corner)
		local x = WG.BarDroidPresets.closeRect(r)
		button(x, { 0.42, 0.1, 0.08, 0.95 }, { 0.75, 0.25, 0.2, 0.95 })
		textIn("\195\151", x[1], x[2], x[3], x[4], (x[4] - x[2]) * 0.7, "\255\250\240\240", bold)
	end
	-- more rows: a small gold chevron at the edge they come from, its point out in the gap beside the half (all inside
	-- it, it covered the bottom tile's costs and the order's state line in the middle: dev phone, 2026-11-11)
	if s.rows > s.visible then
		local cx = (r[1] + r[3]) / 2
		local h = max(6, floor(L.pad * 1.3))
		local w, out = h * 1.15, max(2, L.pad - 2)
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
	for _, k in ipairs({ "rotate", "cancel" }) do
		local r = p[k]
		button(r, { 0, 0, 0, 0.55 }, { 0.15, 0.15, 0.15, 0.6 })
		if k == "rotate" then -- (Kailil, 2026-11-11: its arrow read as a redo button; it turns the building 90 degrees, the
			-- game's only turn, so no "90°" on it: "its redundant")
			-- (across half the panel since 2026-11-12: the word at a third of its height)
			textIn("ROTATE", r[1], r[2], r[3], r[4], max((r[4] - r[2]) * 0.34, min((r[4] - r[2]) * 0.5, 30)),
				"\255\235\235\235", bold)
		else
			textIn("\226\156\149", r[1], r[2], r[3], r[4], max((r[4] - r[2]) * 0.6, min((r[4] - r[2]) * 0.8, 44)),
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
	bold:Print("\255\255\255\255" .. name, x, r[4] - h * 0.36, h * 0.24, "o")
	L.selCountEnd = nil -- (where the count line ends: the camera pad's words keep right of it, drawMode)
	if n > 1 then
		-- ("6 units, 6 of this type" said the same thing twice: all of one type, the count alone)
		local count = bestN < n and (n .. " units, " .. bestN .. " of this type") or (n .. " units")
		font:Print("\255\200\200\200" .. count, x, r[4] - h * 0.62, h * 0.17, "o")
		L.selCountEnd = x + font:GetTextWidth(count) * h * 0.17
	end
	local hp, maxHp = Spring.GetUnitHealth(sel[1])
	if hp and maxHp and maxHp > 0 then
		local x1 = r[3] - L.pad
		local frac = max(0, min(1, hp / maxHp))
		gl.Color(0.12, 0.12, 0.12, 0.9)
		gl.Rect(x, r[2] + h * 0.13, x1, r[2] + h * 0.25)
		gl.Color(1 - frac, 0.3 + 0.55 * frac, 0.2, 1)
		gl.Rect(x, r[2] + h * 0.13, x + (x1 - x) * frac, r[2] + h * 0.25)
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
local function drawResources()
	local r = L.res
	local w = floor((r[3] - r[1] - L.pad) / 2)
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
			local x0 = r[1] + (i - 1) * (w + L.pad)
			local flows = string.format("\255\120\230\120+%s \255\240\110\100-%s", short(income or 0), short(expense or 0))
			local left = x0 + pad * 1.5 + bold:GetTextWidth(short(cur)) * big + pad * 2 + font:GetTextWidth(flows) * small
				+ pad * 2
			if x0 + w - pad * 1.5 - font:GetTextWidth(short(storage)) * small * 0.85 < left then
				storageFits = false
			end
		end
	end
	for i, res in ipairs({ "metal", "energy" }) do
		local cur, storage, _, income, expense = Spring.GetTeamResources(myTeam(), res)
		local x0 = r[1] + (i - 1) * (w + L.pad)
		local x1 = x0 + w
		local box = { x0, r[2], x1, r[4] }
		panel(box)
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
				rx = rx - sw - pad * 3
			end
			if res == "energy" then
				local s = rowH
				local tide = tostring(floor(Spring.GetTidal() or 0))
				if tideRelevant() and rx - indicatorWidth(tide, s) >= left then
					rx = rx - indicatorWidth(tide, s)
					drawIndicator(WAVES, 0, rx, cy, s, tide)
					rx = rx - pad * 3
				end
				if (Game.windMax or 0) > 0 then
					local range = floor(Game.windMin or 0) .. "-" .. floor(Game.windMax or 0)
					local wind = string.format("%.1f", select(4, Spring.GetWind()) or 0)
					if rx - indicatorWidth(wind, s, range) >= left then
						drawIndicator(BLADES, windTurn, rx - indicatorWidth(wind, s, range), cy, s, wind, range)
					elseif rx - indicatorWidth(wind, s) >= left then
						drawIndicator(BLADES, windTurn, rx - indicatorWidth(wind, s), cy, s, wind)
					end
				end
			end
		end
	end
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
		local bw = floor(h * 1.7)
		for i, which in ipairs({ "first", "last" }) do
			local b = { r[3] - (3 - i) * bw + 3, r[2] + 3, r[3] - (2 - i) * bw - 3, r[4] - 3, unq = which }
			L.groupRects[#L.groupRects + 1] = b
			button(b, { 0.3, 0.09, 0.08, 0.9 }, { 0.46, 0.13, 0.11, 0.9 })
			textIn("\195\151 " .. which:upper(), b[1], b[2], b[3], b[4], h * 0.26, "\255\255\228\218", bold)
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
		textIn("NEW " .. free, nr[1], nr[2], nr[3], nr[2] + h * 0.4, h * 0.2, "\255\220\220\220", font)
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
		bold:Print("\255\255\200\064" .. g, gr[1] + 6, gr[4] - h * 0.3, h * 0.26, "o")
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
		if showSel then -- (no selection row: the dimmed dock says it alone)
			local s = L.sel
			local h = s[4] - s[2]
			-- (just above the picked unit's health bar, drawSelection's r[2] + h * 0.25: at the bottom it was printed over it;
			-- right of the count line, "6 units, 6 of this type", which it ran under: left out where it does not fit; the name
			-- alone, no "tap to use the menu" beside it: Kailil, 2026-11-09, the dock shows no hint text)
			local size, right = h * 0.15, s[3] - L.pad
			local from = (L.selCountEnd or 0) + L.pad * 2
			local label = "CAMERA PAD"
			if right - font:GetTextWidth(label) * size >= from then
				font:Print("\255\190\190\190" .. label, right, s[2] + h * 0.3, size, "ro")
			end
		end
		return
	end
	local age = t - menuAt
	local edge = max(2, floor(L.pad * 0.3))
	if age < BLINK then -- two quick pulses of light over the dock, gold at its top edge
		local a = math.sin(age / BLINK * math.pi * 2) ^ 2
		gl.Color(1, 0.9, 0.6, 0.16 * a)
		gl.Rect(d[1], d[2], d[3], d[4])
		gl.Color(1, 0.82, 0.35, 0.9 * a)
		gl.Rect(d[1], d[4] - edge * 3, d[3], d[4])
	end
	local left = SP.held() and 1 or max(0, 1 - (t - lastTouch) / MENU_SECONDS) -- (placing, picking: no clock)
	gl.Color(1, 0.78, 0.25, 0.85)
	gl.Rect(d[1], d[4] - edge, d[1] + (d[3] - d[1]) * left, d[4])
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
	if logCalls % 30 == 0 then
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
		local wide = rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets"
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
				if not DG.slide then -- (a new hold: its way from its first line, "-0.00" on AUTO)
					DG.slideLocked, DG.slideDir = false, slidWord:sub(1, 1) == "-" and -1 or 1
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
		if any and active then -- (PING held or tapped twice, and speak to chat's state: pingT)
			pingT.act(any)
		end
		local name = line:match("^act (dock_%S+)")
		if name == "dock_menu" and active and SP.hidden then -- (the SHOW button tapped: the dock back)
			SP.setHidden(false)
		elseif name == "dock_menu" and active then
			setMenu(true)
			if L.thumb and not L.panelOn then -- (sideways, nothing picked: the tap that opens the menu opens the home
				-- buttons too, the one thing it holds then)
				L.homeOpen = true
				refresh()
			end
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

---------------------------------------------------------------------------------------------------------------------
-- Callins

-- Sideways too, layout A (Kailil, 2026-11-12, of the landscape mockups: "Split dock: build left, minimap + eco middle,
-- orders right. Is the best"; his idea: "split the right and left half of the botom UI and shove a map into the middle
-- with the eco bars on top of it ... that returns vertical real estate back to the actual game world"): with the
-- launcher's "Touch dock sideways" on (launch-bar.sh: bardroid_landdock.txt), playing, the fingers the input (a pad or
-- a mouse brings BAR's own screen back). BAR's minimap goes into the dock's middle (its Minimap widget's external
-- frame: the engine draws and clicks it there), a hole RtsTouch and this widget leave to it (L.hole, "map" line).
function SP.landMinimap()
	local m = WG.minimap
	if not (m and m.setExternalFrame) then
		return
	end
	local h = active and L.land and L.hole or nil
	local key = h and table.concat(h, " ") or nil
	if key == L.frameKey then
		return
	end
	L.frameKey = key
	if h then
		m.setExternalFrame(h[1], h[2], h[3], h[4], 0)
	else
		m.setExternalFrame()
	end
end
-- the rects of d left around h (h inside d): the dock drawn and dimmed around the minimap
function SP.around(d, h)
	if not h then
		return { d }
	end
	return { { d[1], h[4], d[3], d[4] }, { d[1], d[2], d[3], h[2] }, { d[1], h[2], h[1], h[4] }, { h[3], h[2], d[3], h[4] } }
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
		if active and not SP.hidden and L.dock then
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
	SP.guardTooltips()
	dockLines()
	topbarBars(active or upright())
	if not active then
		return
	end
	startFit()
	factoryStates()
	windTurn =(windTurn + (select(4, Spring.GetWind()) or 0) * 0.2 * (dt or 0) * 30) % 360 -- (BAR's top bar's blade speed)
	drawingCursor()
	if rightKind == "home" and pingT.drawn then -- (PINGS: "2 OF 4" back to LAST PINGS after the cycle's pause, TAP MAP
		-- back to PING when it runs out)
		local _, step, armed = pingT.state()
		if step .. (armed and "a" or "") ~= pingT.drawn then
			markDirty()
		end
	end
	pingT.update() -- (CHAT's flips, a spoken ping's end)
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
	writeDock(false)
end

function widget:CommandsChanged()
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
-- FIRE's swipe track (Kailil, 2026-11-10: "the fire mode animation doesn't fully slide to the right and fill the auto.
-- And when you swipe left to disable auto, the animation doesn't work. Its just frozen"): FIRE's to the right, to the
-- grid's edge, AUTO at its end; AUTO's to the left, to the cancel corner, FIRE at its end (RtsTouch measures the swipe
-- against the same spans). The knob goes all the way, the track fills behind it (red to gold towards AUTO, gold to red
-- towards FIRE), chevrons run the way to go; locked (past 0.92) it is full, the knob gone into it, the word on it.
-- f: FIRE's rect, cancel: the cancel corner's, dir 1 right / -1 left, v 0..1, alpha
function DG.track(f, cancel, dir, v, alpha, locked, t)
	local fh = f[4] - f[2]
	local m = dir > 0 and 0.16 or 0.26 -- (the left one thinner: the cancel corner leaves it less room across)
	local y0, y1 = f[2] + floor(fh * m), f[4] - floor(fh * m)
	local k = dir > 0 and { f[3] + L.gap * 2, y0, L.right[3], y1 } or { cancel[3] + L.gap * 2, y0, f[1] - L.gap * 2, y1 }
	local tw, th = k[3] - k[1], k[4] - k[2]
	if tw < th * 1.3 or alpha <= 0 then
		return
	end
	local r, cy = th * 0.4, (k[2] + k[4]) / 2
	local from, to = dir > 0 and k[1] + r or k[3] - r, dir > 0 and k[3] - r or k[1] + r
	local kx = from + (to - from) * v
	gl.Color(0, 0, 0, 0.6 * alpha)
	gl.Rect(k[1], k[2], k[3], k[4])
	local c = dir > 0 and v or 1 - v
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
		local word = dir > 0 and "AUTO" or "FIRE"
		local tx = dir > 0 and k[3] - L.pad or k[1] + L.pad
		local ww = bold:GetTextWidth(word) * ls
		local mid = tx - dir * ww / 2
		-- (the white knob under the word: dark letters on it, the gold ones were lost there; dev phone screenshots)
		local onKnob = not locked and abs(kx - mid) < r + ww * 0.4
		local col = locked and (dir > 0 and "\255\050\024\000" or "\255\255\255\255")
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
	for i, s in ipairs({ p.l, p.r }) do
		gl.Color(0, 0, 0, 0.5)
		disc(s[1], s[2], s[3], true)
		gl.LineWidth(2)
		gl.Color(1, 1, 1, 0.3)
		disc(s[1], s[2], s[3], false)
		gl.LineWidth(1)
		local kx, ky = s[1] + DG.stick[i * 2 - 1] * s[3], s[2] - DG.stick[i * 2] * s[3]
		if i == 1 then
			gl.Color(0.8, 0.8, 0.8, 0.9)
		elseif autoOn then -- (full auto aims itself: the stick greyed, "AIM: AUTO"; its red read as aiming, screenshot)
			gl.Color(0.45, 0.45, 0.45, 0.6)
		else
			gl.Color(1, 0.3, 0.25, 0.95) -- (the aim: the shot's red, as its ring on the ground)
		end
		disc(kx, ky, s[3] * 0.36, true)
		gl.Color(1, 1, 1, 1)
		textIn(i == 1 and "MOVE" or autoOn and "AIM: AUTO" or "AIM", s[1] - s[3], s[2] - s[3] - L.btnH * 0.55, s[1] + s[3],
			s[2] - s[3] - L.gap, L.btnH * 0.36, "\255\200\200\200", font)
	end
	local f, t = p.fire, now()
	local fw, fh = f[3] - f[1], f[4] - f[2]
	local e = max(2, floor(L.pad * 0.35))
	if DG.autoWas and not autoOn then
		DG.autoOffAt = t -- (full auto just ended: the gold drains out of the button, below)
	end
	DG.autoWas = autoOn
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
	-- whether it can fire now: a thin bar along FIRE's foot, white as the D-gun reloads, amber (and the word dimmed)
	-- while the team lacks a shot's energy; none once it is ready
	local loaded, energy = 1, 1
	if D and D.ready then
		loaded, energy = D.ready()
		loaded, energy = loaded or 1, energy or 1
	end
	local lacking = energy < 1
	local part = lacking and energy or loaded
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
	-- FIRE held: its swipe's track (DG.track). Let go past 0.92 the track stays full and fades; short of it it runs back
	local held = DG.slide
	local fade = not held and DG.slideOff and t - DG.slideOff < 0.3 and 1 - (t - DG.slideOff) / 0.3
	if held or fade then
		local s = held or DG.slideLast or 0
		local locked = DG.slideLocked
		local v = locked and 1 or abs(s) * (held and 1 or fade)
		DG.track(f, p.cancel, DG.slideDir or (s < 0 and -1 or 1), v, held and 1 or fade, locked, t)
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
	local s = L.sel
	local third = s[1] + floor((s[3] - s[1]) / 3)
	return { s[1], s[2], third, s[4] }, { third, s[2], s[3], s[4] }
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
	bold:Print((qOn and gold or white) .. "QUEUE", que[3] - L.pad, que[4] - h * 0.36, size, "ro")
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
			local label = SP.TAB_LABELS[kind] or (kind:sub(1, 6) == "types:" and "UNITS")
				or (side == "left" and "BUILD" or "ORDERS")
			if L.tab == side then
				button(r, gold, { 0.66, 0.53, 0.12, 0.9 })
			else
				button(r)
			end
			textIn(label, r[1], r[2], r[3], r[4], (r[4] - r[2]) * 0.46, "\255\240\240\240", bold)
		end
	end
	local h = L.homeBtn
	if L.homeOpen then
		button(h, gold, { 0.66, 0.53, 0.12, 0.9 })
	else
		button(h)
	end
	textIn("HOME", h[1], h[2], h[3], h[4], min((h[4] - h[2]) * 0.3, (h[3] - h[1]) * 0.26), "\255\240\240\240", bold)
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
	panel(L.dock, 1, 1, 0, 0, true)
	if showSel then
		drawSelection()
	end
	drawHalf("left")
	drawHalf("right")
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
function SP.resSignature()
	local parts = { L.res[1], L.res[2], L.res[3], L.res[4], tideRelevant() and "t" or "" }
	for _, res in ipairs({ "metal", "energy" }) do
		local cur, storage, _, income, expense = Spring.GetTeamResources(myTeam(), res)
		parts[#parts + 1] = cur and string.format("%s/%s/%s/%s/%d", short(cur), short(income or 0), short(expense or 0),
			short(storage or 0), (storage or 0) > 0 and floor(cur / storage * 200) or 0) or "-"
	end
	parts[#parts + 1] = string.format("%.1f/%d", select(4, Spring.GetWind()) or 0, floor(Spring.GetTidal() or 0))
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
	local R = gl.R2tHelper
	if texMode ~= 0 and R and R.RenderInRect and R.BlendTexRect then
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
		if L.hole then -- (no texture: the minimap drawn again over the dock's panel)
			gl.DrawMiniMap()
		end
	end
	resetGL()
	local tRes = PROF.on and spGetTimer() -- (profiling: the resource panels' share, drawn live every frame)
	if not (L.land and rightKind == "dgun") then -- (sideways FIRE stands where they are: their edges showed round it)
		SP.drawRes()
	end
	if tRes then
		PROF.resMs = (PROF.resMs or 0) + spDiffTimers(spGetTimer(), tRes) * 1000
	end
	drawQueueZones()
	if rightKind == "place" then
		drawPlace()
	end
	if rightKind == "dgun" then
		drawDgun()
		return -- (no camera pad dimming or menu edge: the sticks are always live)
	end
	drawMode()
end

function widget:DrawScreen()
	if not active then
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
	for _, name in ipairs({ "options", "gameinfo", "keybinds", "changelog", "widgetselector", "missioninfo", "scavengerinfo" }) do
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
	return active and inRect(x, y, L.dock) and not (L.hole and inRect(x, y, L.hole))
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
			pingT.armedAt, pingT.label = nil, nil
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
	if rightKind == "presets" and WG.BarDroidPresets and inRect(x, y, WG.BarDroidPresets.closeRect(homeRect())) then
		WG.BarDroidPresets.close() -- (the presets' X)
		return true
	end
	local wide = rightKind == "home" or rightKind == "share" or rightKind == "panel" or rightKind == "presets"
	local side = wide and inRect(x, y, homeRect()) and "right" -- (the whole grid: both halves)
		or inRect(x, y, L.left) and "left" or inRect(x, y, L.right) and "right" or nil
	if side == "right" and rightKind == "panel" then -- a slider: set where pressed, then follows the finger
		for i, item in ipairs(rightItems) do
			local cr = cellRect("right", i)
			if item.kind == "slider" and cr and inRect(x, y, cr) then
				slide = { item = item, rect = cr }
				setSlider(item, cr, x)
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
	press = { side = side, x = x, y = y, button = btn, lastY = y, lastT = now(), vel = 0, empty = empty,
		panX = x, panY = y, settling = settling }
	return true -- (the dock is the dock's: no press goes through to the map under it)
end


function widget:MouseMove(x, y)
	if slide then
		setSlider(slide.item, slide.rect, x)
		touched()
		return
	end
	local p = press
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
		setSlider(slide.item, slide.rect, x)
		slide = nil
		refresh()
		return true
	end
	local p = press
	press = nil
	if not p then
		return false
	end
	if p.empty and (p.moved or not p.side) then -- (a pan, or a tap on nothing; a tap on a half with nothing to scroll is
		-- its button's: those halves were all "empty" for the pan, and their buttons took no taps, 2026-11-10)
		return true
	end
	local thumb = not p.side and SP.thumbAt(p.x, p.y)
	if thumb == "home" then -- (sideways, one thumb: the home buttons in the panel, or closed again)
		L.homeOpen = not L.homeOpen
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
		pressItem(itemAt(p.side, p.x, p.y), btn == 3)
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
		sideways = function() -- (layout A: the dock along the bottom of a wide screen, BAR's minimap in it)
			return active and L.land or false
		end,
		dock = function() -- (other widgets keep out of it: x0, y0, x1, y1)
			return active and L.dock or nil
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
	if SP.tipOwner and SP.tipOwner.ShowTooltip == SP.tipWrap then -- (BAR's tooltip widget as it was)
		SP.tipOwner.ShowTooltip = SP.tipInner
	end
	WG.BarDroidPortrait = nil
	active = false
	SP.landMinimap() -- (BAR's minimap back in its own place)
	topbarBars(false)
	writeDock(true)
	if logFile then
		logFile:close()
	end
end
