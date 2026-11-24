-- LuaUI widget for tools/guide-shots.ps1: sets up the game for the user guide's pictures (docs/guide), one stage at a
-- time, while the script taps and takes screenshots on the dev phone. Not a test: it checks nothing. The script writes
-- a stage into LuaUI/Config/bardroid_guideshots_cmd.txt; the widget says "[guideshots] <stage> ok" in the log and
-- writes the points the script taps into LuaUI/Config/bardroid_guideshots.txt (X screen pixels, top left origin).
--   none        nothing picked, the dock's menu closed (the camera pad)
--   menu        the dock's menu open (its home buttons)
--   com         the commander picked, the camera on it
--   army        six Pawns given and picked
--   mixed       the commander, the Pawns and two Construction Bots picked
--   cons        the two Construction Bots picked
--   rects       "metal ...", "energy ...", "wind ...", "tide ...", "tile ...", "info ...": the dock's boxes and the info panel
--   presets     the Pawns picked, the presets open;  presetsoff  closed
--   dgun        the D-gun mode on the commander;  dgunoff  off
--   editor      the layout editor open;  editoroff  closed
--   group       the Pawns made group 1 (BAR's own Ctrl+1)
function widget:GetInfo()
	return { name = "BAR Droid guide shots", desc = "Sets up the user guide's pictures", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_guideshots.txt", "LuaUI/Config/bardroid_guideshots_cmd.txt"
local com, ready, lastCmd = nil, false, nil
local given = {}

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
local function unitsOf(def)
	local out = {}
	for u in pairs(given) do
		if Spring.ValidUnitID(u) and Spring.GetUnitDefID(u) == UnitDefNames[def].id then
			out[#out + 1] = u
		end
	end
	return out
end
local function camOn(u)
	local x, y, z = Spring.GetUnitPosition(u)
	if x then
		local P = WG.BarDroidPortrait
		if P and P.cameraTo then
			P.cameraTo(x, z)
		else
			Spring.SetCameraTarget(x, y, z, 0)
		end
	end
end

local function onCmd(c)
	local P = WG.BarDroidPortrait
	local vsy = select(2, Spring.GetViewGeometry())
	local function line(name, r)
		return r and string.format("%s %d %d %d %d\n", name, r[1], vsy - r[4], r[3], vsy - r[2]) or ""
	end
	if c == "none" then
		Spring.SelectUnitArray({})
		if P and P.menuOpen then
			P.menuOpen(false)
		end
	elseif c == "menu" then
		Spring.SelectUnitArray({})
		if P and P.menuOpen then
			P.menuOpen(true)
		end
	elseif c == "com" then
		Spring.SelectUnitArray({ com })
		camOn(com)
	elseif c == "army" or c == "give" then
		if #unitsOf("armpw") == 0 then
			local x, y, z = Spring.GetUnitPosition(com)
			Spring.SendCommands(string.format("give 6 armpw %d @%d,%d,%d", Spring.GetMyTeamID(), x + 80, y, z + 140))
			Spring.SendCommands(string.format("give 2 armck %d @%d,%d,%d", Spring.GetMyTeamID(), x - 120, y, z + 100))
		end
	elseif c == "pickarmy" then
		Spring.SelectUnitArray(unitsOf("armpw"))
	elseif c == "mixed" then
		local units = { com }
		for u in pairs(given) do
			units[#units + 1] = u
		end
		Spring.SelectUnitArray(units)
	elseif c == "cons" then
		Spring.SelectUnitArray(unitsOf("armck"))
	elseif c == "group" then
		Spring.SelectUnitArray(unitsOf("armpw"))
		Spring.SendCommands("group set 1")
	elseif c == "rects" then
		local out = ""
		if P then
			local mb, eb, wb, tb
			if P.resBoxes then
				mb, eb = P.resBoxes()
			end
			if P.windRects then
				wb, tb = P.windRects()
			end
			out = out .. line("metal", mb) .. line("energy", eb) .. line("wind", wb) .. line("tide", tb)
			local cell = P.itemCell and P.itemCell("left", function(it)
				return it.kind == "build"
			end)
			out = out .. line("tile", cell)
			out = out .. line("dock", P.dock and P.dock())
		end
		local s = WG.BarDroidInfoState and WG.BarDroidInfoState()
		if s then
			out = out .. line("info", s.rect) .. line("infotab", s.tab)
		end
		write(out .. "end 0 0\n")
	elseif c == "presets" then
		Spring.SelectUnitArray(unitsOf("armpw"))
		if WG.BarDroidPresets then
			WG.BarDroidPresets.open()
		end
	elseif c == "presetsoff" then
		if WG.BarDroidPresets and WG.BarDroidPresets.close then
			WG.BarDroidPresets.close()
		end
		Spring.SelectUnitArray({})
	elseif c == "dgun" then
		Spring.SelectUnitArray({ com })
		camOn(com)
		if WG.BarDroidPad and WG.BarDroidPad.act then
			WG.BarDroidPad.act("dgun")
		end
	elseif c == "dgunoff" then
		if WG.BarDroidPad and WG.BarDroidPad.act then
			WG.BarDroidPad.act("dgun_cancel")
		end
	elseif c == "editor" then
		Spring.SelectUnitArray({ com })
		if WG.BarDroidLayout and WG.BarDroidLayout.open then
			WG.BarDroidLayout.open()
		end
	elseif c == "editoroff" then
		if WG.BarDroidLayout and WG.BarDroidLayout.close then
			WG.BarDroidLayout.close()
		end
	end
	Spring.Echo("[guideshots] " .. c .. " ok")
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
	if com and not ready and f >= 320 then
		ready = true
		Spring.Echo("[guideshots] ready")
	end
end

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
