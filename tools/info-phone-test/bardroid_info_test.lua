-- LuaUI widget for tools/info-phone-test.ps1: the unit info panel in the touch dock's place (bardroid_info.lua in
-- bardroid_portrait.lua's SP.infoRect; Kailil, 2026-11-23: "I need a way to see my unit selection info ... when unfolded,
-- that info can go in the middle bar section above the Wind and tidal speeds"), checked while the script taps it on the
-- dev phone. The script writes a stage into LuaUI/Config/bardroid_infotest_cmd.txt; the widget answers in the log
-- ("[infotest] PASS|FAIL <case>") and writes what the script taps into LuaUI/Config/bardroid_infotest.txt (X screen
-- pixels, top left origin):
--   (frame 320) the commander picked: "text x y" a point on the panel's text, "tab x0 y0 x1 y1" its INFO tab, "folded 0|1"
--   commander?  the panel in the dock's place (where the split dock's middle is, over the wind's and the tide's pill; else
--               on the dock's top), the commander's name, its health and a DPS
--   folded? / opened?  a tap on the text folds it to its tab; a tap on the tab opens it again
--   give        three Pawns and two Construction Bots given by the commander
--   mixed?      all picked: their totals (the count, DPS, cost, buildpower, the health summed)
--   onetype?    the Pawns alone: the Pawn's stats, their health summed
--   end         "[infotest] done: ALL PASS" or "N FAILED"
function widget:GetInfo()
	return { name = "BAR Droid info test", desc = "The unit info panel in the dock", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_infotest.txt", "LuaUI/Config/bardroid_infotest_cmd.txt"
local com, ready, fails, lastCmd = nil, false, 0, nil
local given = {} -- unitID -> true (the given Pawns and Construction Bots)

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[infotest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end
local function readCmd()
	local f = io.open(CMD_FILE, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end

local function state()
	return WG.BarDroidInfoState and WG.BarDroidInfoState() or nil
end

-- the panel's points for the script: a point on its text (three quarters across, off the picture), its tab
local function writePoints()
	local s = state()
	local vsy = select(2, Spring.GetViewGeometry())
	if not (s and s.rect and s.tab) then
		write("none\n")
		return
	end
	local r, t = s.rect, s.tab
	write(string.format("text %d %d\ntab %d %d %d %d\nfolded %d\n", math.floor(r[1] + (r[3] - r[1]) * 0.78),
		math.floor(vsy - (r[2] + (r[4] - r[2]) * 0.55)), t[1], vsy - t[4], t[3], vsy - t[2], s.folded and 1 or 0))
end

-- the place the dock gives: inside it, and where it belongs (split: the middle, over the wind's and the tide's pill)
local function placeOk(s)
	local P = WG.BarDroidPortrait
	local want = P and P.infoRect and P.infoRect()
	if not (want and s.rect) then
		return false, "no place from the dock"
	end
	local r = s.rect
	if r[1] ~= want[1] or r[2] ~= want[2] or r[3] ~= want[3] or r[4] ~= want[4] then
		return false, string.format("panel %d,%d %d,%d, the dock's place %d,%d %d,%d", r[1], r[2], r[3], r[4], want[1],
			want[2], want[3], want[4])
	end
	local d = P.dock()
	local wb = P.windRects and P.windRects()
	if want.mid then -- (the split dock: between its blocks, over the pill)
		if wb and r[2] < wb[4] then
			return false, string.format("its foot %d under the pill's top %d", r[2], wb[4])
		end
		if r[4] > d[4] then
			return false, string.format("its top %d over the dock's %d", r[4], d[4])
		end
	elseif r[2] < d[4] then
		return false, string.format("its foot %d inside the dock (top %d)", r[2], d[4])
	end
	return true, string.format("%d,%d %d,%d%s", r[1], r[2], r[3], r[4], want.mid and " (the middle)" or " (on the dock)")
end

local function sumHealth(units)
	local h, mh = 0, 0
	for _, u in ipairs(units) do
		local a, b = Spring.GetUnitHealth(u)
		if a then
			h, mh = h + math.max(0, a), mh + b
		end
	end
	return h, mh
end

local function near(a, b)
	return a and b and math.abs(a - b) <= math.max(2, b * 0.02)
end

local function unitsOf(def)
	local out = {}
	for u in pairs(given) do
		if Spring.ValidUnitID(u) and Spring.GetUnitDefID(u) == UnitDefNames[def].id then
			out[#out + 1] = u
		end
	end
	return out
end

local function onCmd(c)
	local s = state()
	if c == "commander?" then
		local ok, why = false, nil
		if s and s.docked then
			ok, why = placeOk(s)
		end
		check("the commander's panel in the dock's place", s and s.docked and ok, s and (s.docked and why or "not docked") or "nothing shown")
		local name = UnitDefs[Spring.GetUnitDefID(com)].translatedHumanName or UnitDefs[Spring.GetUnitDefID(com)].humanName
		check("its name, health and DPS", s and s.kind == "unit" and s.name == name and (s.health or 0) > 0
			and tostring(s.stats):find("DPS") ~= nil,
			s and string.format("%s %s, health %s, stats %s", tostring(s.kind), tostring(s.name), tostring(s.health),
				tostring(s.stats):gsub("\255...", ""):gsub("\1", " ")) or "nothing")
		writePoints()
	elseif c == "folded?" then
		check("a tap on its text folds it to its tab", s and s.folded == true, s and ("folded " .. tostring(s.folded)) or "nothing")
		writePoints()
	elseif c == "opened?" then
		check("a tap on the tab opens it", s and s.folded == false, s and ("folded " .. tostring(s.folded)) or "nothing")
		writePoints()
	elseif c == "give" then
		local x, y, z = Spring.GetUnitPosition(com)
		Spring.SendCommands(string.format("give 3 armpw %d @%d,%d,%d", Spring.GetMyTeamID(), x + 100, y, z + 100))
		Spring.SendCommands(string.format("give 2 armck %d @%d,%d,%d", Spring.GetMyTeamID(), x - 100, y, z + 100))
	elseif c == "mixed" then
		local units = { com }
		for u in pairs(given) do
			units[#units + 1] = u
		end
		Spring.SelectUnitArray(units)
	elseif c == "mixed?" then
		local units = Spring.GetSelectedUnits()
		local h, mh = sumHealth(units)
		local stats = s and tostring(s.stats):gsub("\255...", ""):gsub("\1", " ") or ""
		check("several types: their totals", s and s.kind == "totals" and tostring(s.name):find("^" .. #units .. " ") ~= nil
			and stats:find("DPS") and stats:find("Cost") and stats:find("[Bb]uild"),
			s and string.format("%s '%s', stats %s", tostring(s.kind), tostring(s.name), stats) or "nothing")
		check("their health summed", s and near(s.health, h) and near(s.maxHealth, mh),
			s and string.format("%s / %s, the units' %d / %d", tostring(s.health), tostring(s.maxHealth), h, mh) or "nothing")
		local ok, why = false, "nothing shown"
		if s then
			ok, why = placeOk(s)
		end
		check("still in the dock's place (its selection row as tall)", ok, why)
		writePoints()
	elseif c == "onetype" then
		Spring.SelectUnitArray(unitsOf("armpw"))
	elseif c == "onetype?" then
		local pawns = unitsOf("armpw")
		local h, mh = sumHealth(pawns)
		check("one type: its stats, the health summed", s and s.kind == "def" and near(s.health, h) and near(s.maxHealth, mh)
			and tostring(s.stats):find("DPS") ~= nil,
			s and string.format("%s %s, %s / %s, the Pawns' %d / %d", tostring(s.kind), tostring(s.name), tostring(s.health),
				tostring(s.maxHealth), h, mh) or "nothing")
		writePoints()
	elseif c == "end" then
		Spring.Echo("[infotest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
	end
end

function widget:UnitCreated(unitID, unitDefID, teamID)
	if teamID == Spring.GetMyTeamID() and (unitDefID == UnitDefNames.armpw.id or unitDefID == UnitDefNames.armck.id) then
		given[unitID] = true
	end
end

function widget:GameFrame(f)
	if f == 60 then
		Spring.SendCommands("cheat 1")
	end
	if not com then
		for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
			local def = UnitDefs[Spring.GetUnitDefID(u)]
			if def and def.customParams and def.customParams.iscommander then
				com = u
			end
		end
	end
	if com and f == 290 then
		Spring.SelectUnitArray({ com })
	end
	if com and not ready and f >= 320 then
		ready = true
		writePoints()
		local s = state()
		Spring.Echo(string.format("[infotest] ready: %s", s and (s.kind .. (s.folded and " folded" or " open")) or "nothing shown"))
	end
end

-- (between frames too: the stages go on while the game is paused)
local cmdAt = 0
function widget:Update()
	local t = os.clock()
	if not ready or t - cmdAt < 0.2 then
		return
	end
	cmdAt = t
	local c = readCmd()
	if c and c ~= lastCmd then
		lastCmd = c
		onCmd(c)
	end
end
