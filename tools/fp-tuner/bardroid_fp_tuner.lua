-- LuaUI widget for tools/fp-tuner.ps1 (the laptop only): Kailil sets bardroid_spectate.lua's 1st person camera while
-- it rides a unit in a replay (2026-10-27: "a way for me to adjust the view of the first person while its spectating
-- units. then you take those adjustments and apply them globally ... xyz, offsets/ anchor bone selection, fov,
-- smoothing of rotation"). A panel on the left: each value with - and + (the outer ones five steps; the mouse wheel
-- over a row steps too), the unit and its anchor piece (picked per unit type), Save. The values are
-- bardroid_spectate.lua's own (WG.BarDroidSpectate.fp), so the camera changes at once; Save writes them to
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
	{ key = "recenterDelay", label = "Recenter after (s)", step = 0.5, min = 0, max = 60 },
	{ key = "recenterSmoothing", label = "Recenter smooth (s)", step = 0.05, min = 0, max = 5 },
}

local function round(v, step)
	return math.floor(v / step + 0.5) * step
end

local function stepNumber(row, n)
	local fp = FP()
	local v = round(fp[row.key] + row.step * n, row.step / 10)
	if row.min then
		v = math.max(row.min, math.min(row.max, v))
	end
	fp[row.key] = v
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

local function save()
	local text = "-- 1st person camera set with tools/fp-tuner.ps1 (bardroid_spectate.lua FP)\nreturn " .. serialize(FP()) .. "\n"
	local f = io.open(FILE, "w")
	if f then
		f:write(text)
		f:close()
	end
	Spring.Echo("[fp-tuner] saved " .. FILE .. ": " .. text:gsub("\n", " "))
	savedAt = now()
end

local function build()
	rows = {
		{ label = "Unit", value = function() return select(2, unitDefName()) or "-" end,
			step = function(n) if S() then S().actions[n > 0 and "unit_next" or "unit_prev"]() end end },
		{ label = "Anchor", value = function()
				local a = S() and S().anchor()
				return a == nil and "-" or (a == "" and "middle" or a)
			end,
			step = function(n) anchorStep(n > 0 and 1 or -1) end },
		{ label = "Turn with", value = function() return FP().facing end,
			step = function() FP().facing = FP().facing == "unit" and "piece" or "unit" end },
	}
	for _, r in ipairs(NUMBERS) do
		rows[#rows + 1] = { label = r.label, value = function()
				local v = FP()[r.key]
				return r.step < 1 and string.format("%.2f", v) or string.format("%g", v)
			end, step = function(n) stepNumber(r, n) end }
	end
end

local function layout()
	local _, vsy = Spring.GetViewGeometry()
	local h = math.floor(vsy * 0.042)
	local w = math.floor(h * 13.5)
	local x0, top = 8, vsy - math.floor(vsy * 0.3)
	buttons = {}
	for i, r in ipairs(rows) do
		local y = top - i * (h + 3)
		local bw = h * 1.2
		r.y, r.x0, r.x1 = y, x0, x0 + w
		buttons[#buttons + 1] = { x0 = x0 + w - bw * 4 - 9, x1 = x0 + w - bw * 3 - 9, y0 = y, y1 = y + h, row = r, n = -5, label = "<<" }
		buttons[#buttons + 1] = { x0 = x0 + w - bw * 3 - 6, x1 = x0 + w - bw * 2 - 6, y0 = y, y1 = y + h, row = r, n = -1, label = "-" }
		buttons[#buttons + 1] = { x0 = x0 + w - bw * 2 - 3, x1 = x0 + w - bw - 3, y0 = y, y1 = y + h, row = r, n = 1, label = "+" }
		buttons[#buttons + 1] = { x0 = x0 + w - bw, x1 = x0 + w, y0 = y, y1 = y + h, row = r, n = 5, label = ">>" }
	end
	local y = top - (#rows + 1) * (h + 3)
	buttons[#buttons + 1] = { x0 = x0, x1 = x0 + w, y0 = y, y1 = y + h, save = true,
		label = now() - savedAt < 3 and "Saved" or "Save (bardroid_fp.lua)" }
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
	gl.Rect(x0 - 6, top - (#rows + 1) * (h + 3) - 6, x0 + w + 6, top + h * 1.2)
	for i, r in ipairs(rows) do
		if i % 2 == 0 then -- every other row a shade lighter: the eye stays on its line
			gl.Color(1, 1, 1, 0.06)
			gl.Rect(x0, r.y, x0 + w, r.y + h)
		end
	end
	for _, b in ipairs(buttons) do
		gl.Color(1, 1, 1, b.save and 0.3 or 0.2)
		gl.Rect(b.x0, b.y0, b.x1, b.y1)
	end
	gl.Color(1, 1, 1, 1)
	if font then
		font:Begin()
		local size = h * 0.62
		font:Print("\255\255\210\1001st person tuner", x0, top + h * 0.25, h * 0.75, "o")
		for _, r in ipairs(rows) do
			font:Print("\255\235\235\235" .. r.label, x0 + 6, r.y + h * 0.24, size, "o")
			font:Print("\255\255\230\90" .. tostring(r.value()), x0 + w * 0.47, r.y + h * 0.24, size, "o")
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
			build()
			S().firstPerson(unitID)
			started = true
		end
	end
end
