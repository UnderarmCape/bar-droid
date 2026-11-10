-- BAR Droid presets: preset orders for the picked combat units (Kailil, 2026-11-10: "a PRESETS button ... the whole dock
-- shows the presets as 2 x 2 thumbnails ... closed by an X in the corner or Android's Back"; repeated moves along paths
-- that make units hard to hit, and formations by their types' strengths). Touch play's automation is his and BAR's
-- developers' call (GiveOrder). The upright dock (bardroid_portrait.lua) shows PRESETS among the orders while units
-- that fight are picked, and the presets over its whole grid; a preset tapped closes them and the next tap on the map is
-- where the picked units go (Back, or a press of the right button, lets it go).
-- WG.BarDroidPresets: fits(units), isOpen(), open(), close(), items(), pick(id), drawThumb(id, rect), closeRect(rect),
-- armed(). Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid presets",
		desc = "Preset orders for the picked units: zigzags and formations",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -20, -- (before the dock, -10, and BAR's menus: the destination's tap and Back are its first)
		enabled = true,
	}
end

local ZIG_STEP = 230 -- elmos along the way between the zigzag's turns
local ZIG_SIDE = 170 -- elmos to each side of the way at its turns
local ZIG_MAX_TURNS = 30
local BLOB = 260 -- elmos: the group's shape kept, at most this far from its middle
local KEY_ESCAPE = 27

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID

local opened = false
local armedFor -- { id, units }: a preset picked, the map's next tap is its destination

local function say(text)
	local P = WG.BarDroidPad
	if P and P.say then
		P.say(text)
	end
end
local function refreshDock()
	local D = WG.BarDroidPortrait
	if D and D.refresh then
		D.refresh()
	end
end

local function fighter(ud)
	return ud and ud.canMove and not ud.isBuilding and (ud.speed or 0) > 0 and not ud.isBuilder
		and #(ud.weapons or {}) > 0
end
-- the picked units presets order: those that move and fight (builders and buildings keep their orders)
local function combatUnits(units)
	local out = {}
	for _, u in ipairs(units or {}) do
		if fighter(UnitDefs[spGetUnitDefID(u) or -1]) then
			out[#out + 1] = u
		end
	end
	return out
end

local function onMap(x, z)
	return math.max(32, math.min(Game.mapSizeX - 32, x)), math.max(32, math.min(Game.mapSizeZ - 32, z))
end
local function ground(x, z)
	x, z = onMap(x, z)
	return { x, Spring.GetGroundHeight(x, z), z }
end
-- the units' middle and each one's place from it (the group's shape, drawn in to BLOB)
local function shape(units)
	local cx, cz, n, at = 0, 0, 0, {}
	for _, u in ipairs(units) do
		local x, _, z = spGetUnitPosition(u)
		if x then
			at[u] = { x, z }
			cx, cz, n = cx + x, cz + z, n + 1
		end
	end
	if n == 0 then
		return nil
	end
	cx, cz = cx / n, cz / n
	local far = 0
	for _, p in pairs(at) do
		p[1], p[2] = p[1] - cx, p[2] - cz
		far = math.max(far, math.sqrt(p[1] * p[1] + p[2] * p[2]))
	end
	local k = far > BLOB and BLOB / far or 1
	for _, p in pairs(at) do
		p[1], p[2] = p[1] * k, p[2] * k
	end
	return cx, cz, at
end
local function way(cx, cz, tx, tz)
	local dx, dz = tx - cx, tz - cz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1 then
		return 0, 1, 0
	end
	return dx / d, dz / d, d
end
local function orders(u, list)
	local cmds = {}
	for i, p in ipairs(list) do
		cmds[#cmds + 1] = { CMD.MOVE, p, i == 1 and {} or { "shift" } }
	end
	if #cmds > 0 then
		Spring.GiveOrderArrayToUnitArray({ u }, cmds)
	end
end

-- ZIGZAG: to the destination in big turns from side to side (slow shots aimed where a unit was going land beside it),
-- each unit keeping its place in the group
local function zigzag(units, tx, tz)
	local cx, cz, at = shape(units)
	if not cx then
		return 0
	end
	local fx, fz, d = way(cx, cz, tx, tz)
	local px, pz = -fz, fx
	local turns = math.min(ZIG_MAX_TURNS, math.floor(d / ZIG_STEP))
	local n = 0
	for u, o in pairs(at) do
		local list = {}
		for k = 1, turns do
			local side = (k % 2 == 1) and ZIG_SIDE or -ZIG_SIDE
			list[#list + 1] = ground(cx + fx * ZIG_STEP * k + px * side + o[1], cz + fz * ZIG_STEP * k + pz * side + o[2])
		end
		list[#list + 1] = ground(tx + o[1], tz + o[2])
		orders(u, list)
		n = n + 1
	end
	return n
end

local PRESETS = {
	{ name = "ZIGZAG", run = zigzag, thumb = "zigzag" },
}

-- the thumbnails: small drawings of what each does, in the rect (x0, y0, x1, y1), y up
local function line(points, width, c)
	gl.Color(c[1], c[2], c[3], c[4] or 1)
	gl.LineWidth(width)
	gl.BeginEnd(GL.LINE_STRIP, function()
		for _, p in ipairs(points) do
			gl.Vertex(p[1], p[2], 0)
		end
	end)
	gl.LineWidth(1)
end
local function dot(x, y, r, c)
	gl.Color(c[1], c[2], c[3], c[4] or 1)
	gl.Rect(x - r, y - r, x + r, y + r)
end
local THUMBS = {}
function THUMBS.zigzag(x0, y0, x1, y1)
	local w, h = x1 - x0, y1 - y0
	local pts = {}
	for k = 0, 6 do -- (from the bottom left up to the top right, side to side)
		local t = k / 6
		local side = (k == 0 or k == 6) and 0 or ((k % 2 == 1) and 1 or -1)
		pts[#pts + 1] = { x0 + w * (0.15 + 0.7 * t) + side * w * 0.11, y0 + h * (0.12 + 0.76 * t) - side * h * 0.06 }
	end
	line(pts, math.max(2, w * 0.018), { 0.95, 0.78, 0.25, 0.95 })
	local e = pts[#pts]
	dot(e[1], e[2], math.max(3, w * 0.025), { 0.95, 0.78, 0.25, 1 })
	for i = 1, 3 do -- (the group at the start)
		dot(x0 + w * (0.08 + i * 0.05), y0 + h * (0.1 + (i % 2) * 0.05), math.max(3, w * 0.022), { 0.4, 0.7, 1, 1 })
	end
end

local function closePresets()
	if opened then
		opened = false
		refreshDock()
	end
end

function widget:Initialize()
	WG.BarDroidPresets = {
		fits = function(units)
			return #combatUnits(units) > 0
		end,
		isOpen = function()
			return opened
		end,
		open = function()
			opened, armedFor = true, nil
			refreshDock()
		end,
		close = closePresets,
		items = function()
			local out = {}
			for i, p in ipairs(PRESETS) do
				out[#out + 1] = { kind = "preset", id = i, label = p.name }
			end
			return out
		end,
		pick = function(id)
			local p = PRESETS[id]
			local units = combatUnits(Spring.GetSelectedUnits())
			opened = false
			if p and #units > 0 then
				armedFor = { id = id, units = units }
				say(p.name .. ": TAP THE DESTINATION")
			end
			refreshDock()
		end,
		armed = function()
			return armedFor ~= nil
		end,
		drawThumb = function(id, r)
			local p = PRESETS[id]
			local f = p and THUMBS[p.thumb]
			if f then
				local m = math.min(r[3] - r[1], r[4] - r[2]) * 0.08
				f(r[1] + m, r[2] + m, r[3] - m, r[4] - m)
				gl.Color(1, 1, 1, 1)
			end
		end,
		closeRect = function(r) -- (the X: a square in the grid's top right corner)
			local s = math.floor(math.min(r[3] - r[1], r[4] - r[2]) * 0.14)
			return { r[3] - s, r[4] - s, r[3], r[4] }
		end,
	}
end

function widget:Shutdown()
	WG.BarDroidPresets = nil
end

function widget:MousePress(x, y, btn)
	if not armedFor then
		return false
	end
	local D = WG.BarDroidPortrait
	local dock = D and D.dock and D.dock()
	if dock and x >= dock[1] and x <= dock[3] and y >= dock[2] and y <= dock[4] then
		return false -- (the dock's own presses)
	end
	local a = armedFor
	armedFor = nil
	if btn ~= 1 then
		say("PRESET CANCELLED")
		return true
	end
	local kind, pos = Spring.TraceScreenRay(x, y, true)
	if kind ~= "ground" or not pos then
		say("PRESET CANCELLED")
		return true
	end
	local alive = {}
	for _, u in ipairs(a.units) do
		if Spring.ValidUnitID(u) and not Spring.GetUnitIsDead(u) then
			alive[#alive + 1] = u
		end
	end
	local p = PRESETS[a.id]
	local n = p and p.run(alive, pos[1], pos[3]) or 0
	say(string.format("%s: %d %s", p and p.name or "PRESET", n, n == 1 and "UNIT" or "UNITS"))
	Spring.Echo(string.format("[bardroid-presets] %s to %d,%d: %d units", p and p.name or "?", pos[1], pos[3], n)) -- (tools)
	return true
end

function widget:KeyPress(key)
	if key ~= KEY_ESCAPE then
		return false
	end
	if opened then -- (Android's Back is Escape in the game: it closes the presets, BAR's menu stays shut)
		closePresets()
		return true
	end
	if armedFor then
		armedFor = nil
		say("PRESET CANCELLED")
		return true
	end
	return false
end
