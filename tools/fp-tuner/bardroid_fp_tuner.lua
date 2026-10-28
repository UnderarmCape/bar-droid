-- LuaUI widget for tools/fp-tuner.ps1 (the laptop only): Kailil sets bardroid_spectate.lua's 1st person camera while
-- it rides a unit in a replay (2026-10-27: "a way for me to adjust the view of the first person while its spectating
-- units. then you take those adjustments and apply them globally ... xyz, offsets/ anchor bone selection, fov,
-- smoothing of rotation"), and the other views too ("edit all of the views to make them permanent settings"). A panel
-- on the left: the view, then each value with - and + (the outer ones five steps; the mouse wheel over a row steps
-- too), the unit and its anchor piece (picked per unit type), Save. The values are bardroid_spectate.lua's own
-- (WG.BarDroidSpectate.fp, its views), so the camera changes at once; Save writes them all to
-- LuaUI/Config/bardroid_fp.lua (the spectate widget reads it at its start here) and logs them ("[fp-tuner] saved").
function widget:GetInfo()
	return { name = "BAR Droid 1st person tuner", desc = "Sets the 1st person camera of bardroid_spectate.lua",
		author = "BAR Droid", layer = 0, enabled = true }
end

local SKIP = tonumber((VFS.LoadFile("LuaUI/Config/bardroid_fp_tuner_skip.txt", VFS.RAW) or ""):match("%d+")) or 240
local FILE = "LuaUI/Config/bardroid_fp.lua"

local rows, buttons = {}, {}
local skipSent, started = false, false
local savedAt = -100
local t0 = Spring.GetTimer()

local function now()
	return Spring.DiffTimers(Spring.GetTimer(), t0)
end

local function S()
	return WG.BarDroidSpectate
end

local function FP()
	return S() and S().fp
end

-- the mobile unit closest to where the camera looks
local function closestUnit()
	local cs = Spring.GetCameraState()
	local best, bestD
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		local x, _, z = Spring.GetUnitPosition(unitID)
		if x and def and (def.speed or 0) > 0 and not def.name:find("critter", 1, true)
			and Spring.GetUnitTeam(unitID) ~= Spring.GetGaiaTeamID() and not Spring.GetUnitIsBeingBuilt(unitID) then
			local d = (x - (cs.px or 0)) ^ 2 + (z - (cs.pz or 0)) ^ 2
			if not bestD or d < bestD then
				best, bestD = unitID, d
			end
		end
	end
	return best
end

local function unitDefName()
	local unitID = S() and S().following()
	local def = unitID and UnitDefs[Spring.GetUnitDefID(unitID) or -1]
	return def and def.name, def and (def.translatedHumanName or def.humanName), unitID
end

-- the anchor choices for the unit followed: its middle ("") and its pieces
local function anchorStep(step)
	local name, _, unitID = unitDefName()
	if not (name and unitID) then
		return
	end
	local list = { "" }
	for _, piece in ipairs(Spring.GetUnitPieceList(unitID) or {}) do
		list[#list + 1] = piece
	end
	local current, at = S().anchor() or "", 1
	for i, n in ipairs(list) do
		if n == current then
			at = i
		end
	end
	FP().pieces[name] = list[(at - 1 + step) % #list + 1]
end

local NUMBERS = {
	{ key = "forward", label = "Forward", step = 2 },
	{ key = "right", label = "Right", step = 2 },
	{ key = "up", label = "Up", step = 2 },
	{ key = "pitch", label = "Pitch (deg)", step = 1, min = -89, max = 89 },
	{ key = "yaw", label = "Yaw (deg)", step = 2, min = -180, max = 180 },
	{ key = "fov", label = "FOV (deg)", step = 2, min = 10, max = 150 },
	{ key = "posSmoothing", label = "Move smoothing (s)", step = 0.02, min = 0, max = 3 },
	{ key = "turnSmoothing", label = "Turn smoothing (s)", step = 0.05, min = 0, max = 5 },
	{ key = "lookSpeed", label = "Look speed (deg)", step = 10, min = 10, max = 720 }, -- (per drag across the screen)
	-- (recenter delay and smoothing, and "turn with", left out: Kailil does not need them and the panel ran off the
	-- screen; bardroid_spectate.lua's own values stand)
}

local function round(v, step)
	return math.floor(v / step + 0.5) * step
end

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = copy(v)
	end
	return c
end

-- the values as saved when the tuner started: what Reset puts back (Kailil: "a reset buton next to each value. it
-- resets the value back to the saved default")
local snapshot, snapshotViews

-- Whose values an edit sets: the unit type's only (Kailil, 2026-10-28: "remove the settings for all units and units. i
-- will only adjust unit by unit"); a unit takes its type's, else everyone's (the defaults in bardroid_spectate.lua).
local scope = "type"

local function followedDef()
	local unitID = S() and S().following()
	return unitID and UnitDefs[Spring.GetUnitDefID(unitID) or -1], unitID
end

local function scopeTable(fp, create)
	local def, unitID = followedDef()
	if scope == "class" and unitID then
		local cls = S().unitClass(unitID)
		if create and not fp.classes[cls] then
			fp.classes[cls] = {}
		end
		return fp.classes[cls]
	elseif scope == "type" and def then
		if create and not fp.types[def.name] then
			fp.types[def.name] = {}
		end
		return fp.types[def.name]
	end
	return fp
end

-- a value as the followed unit gets it, and where it comes from ("type", "class", "all")
local function effective(key)
	local def, unitID = followedDef()
	local fp = FP()
	if def and fp.types[def.name] and fp.types[def.name][key] ~= nil then
		return fp.types[def.name][key], "type"
	end
	local cls = unitID and S().unitClass(unitID)
	if cls and fp.classes[cls] and fp.classes[cls][key] ~= nil then
		return fp.classes[cls][key], "class"
	end
	return fp[key], "all"
end

local function setValue(key, v)
	scopeTable(FP(), true)[key] = v
end

local function resetValue(key)
	local was = scopeTable(snapshot, false)
	local t = scopeTable(FP(), scope ~= "all")
	if t then
		t[key] = was and copy(was[key]) or nil
	end
end

local function stepNumber(row, n)
	local v = round(effective(row.key) + row.step * n, row.step / 10)
	if row.min then
		v = math.max(row.min, math.min(row.max, v))
	end
	setValue(row.key, v)
end

local function serialize(t, indent)
	indent = indent or ""
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local out = { "{\n" }
	for _, k in ipairs(keys) do
		local v = t[k]
		local key = type(k) == "number" and "" or ("[" .. string.format("%q", k) .. "] = ")
		if type(v) == "table" then
			out[#out + 1] = indent .. "\t" .. key .. serialize(v, indent .. "\t") .. ",\n"
		elseif type(v) == "string" then
			out[#out + 1] = indent .. "\t" .. key .. string.format("%q", v) .. ",\n"
		else
			out[#out + 1] = indent .. "\t" .. key .. tostring(v) .. ",\n"
		end
	end
	out[#out + 1] = indent .. "}"
	return table.concat(out)
end

-- The other views (Kailil: "make me able to edit all of the views to make them permanent settings"): the Spring
-- camera's distance, pitch (degrees below level), turn (degrees from the unit's facing, the views that turn with it)
-- and the target's offset (to the right, ahead).
local VIEW_NUMBERS = {
	{ key = "dist", label = "Distance", step = 50, min = 20, max = 20000 },
	{ key = "rx", label = "Pitch down (deg)", step = 1, min = 0, max = 89.5, deg = true },
	{ key = "ryRel", label = "Turn (deg)", step = 5, min = -180, max = 180, rad = true, unitOnly = true },
	{ key = "ox", label = "Right", step = 10, min = -3000, max = 3000 },
	{ key = "oz", label = "Ahead", step = 10, min = -3000, max = 3000 },
	{ key = "oy", label = "Up", step = 10, min = -500, max = 3000 }, -- (Kailil: "shoulder needs to have an up adjustment")
}
local viewKey = "first"

-- a view's value as shown (rx as degrees below level, ryRel as degrees)
local function viewValue(row, p)
	local v = p[row.key] or 0
	if row.deg then
		return math.deg(v - math.pi / 2)
	elseif row.rad then
		return math.deg(v)
	end
	return v
end

local function stepView(row, n)
	local base = S().presetValues(viewKey)
	local p = {}
	for k, v in pairs(base) do
		p[k] = v
	end
	local v = round(viewValue(row, p) + row.step * n, row.step / 10)
	v = math.max(row.min, math.min(row.max, v))
	if row.deg then
		v = math.rad(v) + math.pi / 2
	elseif row.rad then
		v = math.rad(v)
	end
	p[row.key] = v
	S().setPreset(viewKey, p)
end

local build -- (below: the rows change with the view)

local function stepViewKey(n)
	local list = S().views()
	local at = 1
	for i, p in ipairs(list) do
		if p.key == viewKey then
			at = i
		end
	end
	viewKey = list[(at - 1 + n) % #list + 1].key
	S().apply(viewKey)
	build()
end

local function save()
	local all = {}
	for k, v in pairs(FP()) do
		all[k] = v
	end
	all.presets = S().saved()
	all.presetTypes = S().presetTypes() -- (the views per unit type)
	local text = "-- 1st person camera and the views set with tools/fp-tuner.ps1 (bardroid_spectate.lua FP, PRESETS)\nreturn " ..
		serialize(all) .. "\n"
	local f = io.open(FILE, "w")
	if f then
		f:write(text)
		f:close()
	end
	Spring.Echo("[fp-tuner] saved " .. FILE .. ": " .. text:gsub("\n", " "))
	savedAt = now()
	snapshot, snapshotViews = copy(FP()), copy(S().presetTypes()) -- (Reset goes back to these now)
end

-- the value's colour by where it comes from: the unit type's own (cyan), its class's (green), everyone's (yellow)
local SOURCE_COLOUR = { type = "\255\110\225\255", class = "\255\130\255\130", all = "\255\255\230\90" }

build = function()
	rows = {
		{ label = "View", value = function()
				local p = S().presetValues(viewKey)
				return p and p.label or viewKey
			end,
			step = function(n) stepViewKey(n > 0 and 1 or -1) end },
		{ label = "Unit", value = function() return select(2, unitDefName()) or "-" end,
			step = function(n) if S() then S().actions[n > 0 and "unit_next" or "unit_prev"]() end end },
	}
	if viewKey == "first" then
		rows[#rows + 1] = { label = "Anchor", value = function()
				local a = S() and S().anchor()
				return a == nil and "-" or (a == "" and "middle" or a)
			end,
			step = function(n) anchorStep(n > 0 and 1 or -1) end,
			reset = function()
				local name = unitDefName()
				if name then
					FP().pieces[name] = snapshot.pieces[name]
				end
			end }
		for _, r in ipairs(NUMBERS) do
			rows[#rows + 1] = { label = r.label, value = function()
					local v, from = effective(r.key)
					return SOURCE_COLOUR[from] .. (r.step < 1 and string.format("%.2f", v) or string.format("%g", v))
				end, step = function(n) stepNumber(r, n) end, reset = function() resetValue(r.key) end }
		end
		return
	end
	local p = S().presetValues(viewKey)
	for _, r in ipairs(VIEW_NUMBERS) do
		if not r.unitOnly or (p and p.frame == "unit") then
			rows[#rows + 1] = { label = r.label, reset = function()
					-- this value as saved for the unit type (none saved: everyone's view)
					local name = unitDefName()
					local base = name and snapshotViews[name] and snapshotViews[name][viewKey]
					if not base then
						base = S().saved()[viewKey]
						for _, d in ipairs(S().views()) do
							if not base and d.key == viewKey then
								base = d
							end
						end
					end
					local vals = copy(S().presetValues(viewKey))
					vals[r.key] = base and base[r.key]
					S().setPreset(viewKey, vals)
				end, value = function()
					return string.format("%g", round(viewValue(r, S().presetValues(viewKey)), r.step / 10))
				end, step = function(n) stepView(r, n) end }
		end
	end
end

local function layout()
	local _, vsy = Spring.GetViewGeometry()
	local h = math.floor(vsy * 0.038)
	local w = math.floor(h * 16)
	-- (below the minimap, Save first: Kailil could not see it at the bottom of a long panel)
	local x0, top = 8, vsy - math.floor(vsy * 0.36)
	buttons = {}
	buttons[1] = { x0 = x0 + w * 0.55, x1 = x0 + w, y0 = top, y1 = top + h, save = true,
		label = now() - savedAt < 3 and "Saved" or "Save" }
	for i, r in ipairs(rows) do
		local y = top - i * (h + 3)
		local bw, rw = h * 1.2, h * 2.2 -- (the step buttons; Reset at the end)
		local right = x0 + w - rw - 6
		r.y, r.x0, r.x1 = y, x0, x0 + w
		buttons[#buttons + 1] = { x0 = right - bw * 4 - 9, x1 = right - bw * 3 - 9, y0 = y, y1 = y + h, row = r, n = -5, label = "<<" }
		buttons[#buttons + 1] = { x0 = right - bw * 3 - 6, x1 = right - bw * 2 - 6, y0 = y, y1 = y + h, row = r, n = -1, label = "-" }
		buttons[#buttons + 1] = { x0 = right - bw * 2 - 3, x1 = right - bw - 3, y0 = y, y1 = y + h, row = r, n = 1, label = "+" }
		buttons[#buttons + 1] = { x0 = right - bw, x1 = right, y0 = y, y1 = y + h, row = r, n = 5, label = ">>" }
		if r.reset then
			buttons[#buttons + 1] = { x0 = x0 + w - rw, x1 = x0 + w, y0 = y, y1 = y + h, row = r, reset = true, label = "Reset" }
		end
	end
	return h, x0, w, top
end

local function buttonAt(x, y)
	for _, b in ipairs(buttons) do
		if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 then
			return b
		end
	end
end

local function rowAt(x, y)
	for _, r in ipairs(rows) do
		if r.y and x >= r.x0 and x <= r.x1 and y >= r.y and y <= r.y + (buttons[1] and (buttons[1].y1 - buttons[1].y0) or 0) then
			return r
		end
	end
end

function widget:DrawScreen()
	if not (started and FP()) then
		return
	end
	local h, x0, w, top = layout()
	-- (bold, large, light on a dark panel: Kailil, "make the adjustments easier to read and bold")
	local font = WG.fonts and (WG.fonts.getFont(2) or WG.fonts.getFont())
	gl.Color(0, 0, 0, 0.82)
	gl.Rect(x0 - 6, top - #rows * (h + 3) - 6, x0 + w + 6, top + h + 6)
	for i, r in ipairs(rows) do
		if i % 2 == 0 then -- every other row a shade lighter: the eye stays on its line
			gl.Color(1, 1, 1, 0.06)
			gl.Rect(x0, r.y, x0 + w, r.y + h)
		end
	end
	for _, b in ipairs(buttons) do
		if b.reset then
			gl.Color(0.9, 0.45, 0.2, 0.45)
		elseif b.save then
			gl.Color(0.25, 0.75, 0.35, 0.7)
		else
			gl.Color(1, 1, 1, b.save and 0.3 or 0.2)
		end
		gl.Rect(b.x0, b.y0, b.x1, b.y1)
	end
	gl.Color(1, 1, 1, 1)
	if font then
		font:Begin()
		local size = h * 0.62
		font:Print("\255\255\210\100Camera tuner", x0 + 6, top + h * 0.22, h * 0.7, "o")
		for _, r in ipairs(rows) do
			font:Print("\255\235\235\235" .. r.label, x0 + 6, r.y + h * 0.24, size, "o")
			local v = tostring(r.value())
			local colour, text = v:match("^(\255...)(.*)$")
			colour, text = colour or "\255\255\230\90", text or v
			if #text > 14 then -- (a long unit name stays clear of the buttons)
				text = text:sub(1, 13) .. "."
			end
			font:Print(colour .. text, x0 + w * 0.4, r.y + h * 0.24, size, "o")
		end
		for _, b in ipairs(buttons) do
			font:Print("\255\255\255\255" .. b.label, (b.x0 + b.x1) / 2, b.y0 + h * 0.24, size, "oc")
		end
		font:End()
	end
end

function widget:IsAbove(x, y)
	return started and (buttonAt(x, y) ~= nil or rowAt(x, y) ~= nil)
end

function widget:MousePress(x, y)
	if not started then
		return false
	end
	local b = buttonAt(x, y)
	if b then
		if b.save then
			save()
		elseif b.reset then
			b.row.reset()
		else
			b.row.step(b.n)
		end
		return true
	end
	return rowAt(x, y) ~= nil
end

function widget:MouseWheel(up, value)
	local mx, my = Spring.GetMouseState()
	local r = started and rowAt(mx, my)
	if r then
		r.step((up and 1 or -1) * math.max(1, math.abs(value or 1)))
		return true
	end
	return false
end

function widget:Update()
	local frame = Spring.GetGameFrame()
	if frame <= 0 or not S() then
		return
	end
	WG.BarDroidInput = "touch" -- (the spectate widget's tools: its double tap picks another unit to ride)
	if not skipSent then
		skipSent = true
		if SKIP > 0 then
			Spring.SendCommands("skip " .. SKIP)
		end
		return
	end
	if not started and frame >= SKIP * 30 then
		local unitID = closestUnit()
		if unitID then
			snapshot, snapshotViews = copy(FP()), copy(S().presetTypes()) -- (Reset's values: as saved)
			build()
			S().firstPerson(unitID)
			started = true
		end
	end
end
