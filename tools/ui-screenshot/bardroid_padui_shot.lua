-- User widget for tools/ui-screenshot.ps1 -PadUI: the app's gamepad interface staged one piece at a time, a screenshot
-- of each ("[uishot] shot <name>" just before it, which the script names the file by), then quit. Through the app's own
-- lines (LuaUI/Config/bardroid_touch.txt, as RtsTouch and ControllerBridge write them); pointer moves recorded, never
-- made (the laptop's pointer stays where it is).
--   buildmenu  RB: the build menu with the pad on its first option (the gold outline drawn here, as the pointer would)
--   orders     Back + RB: the order menu with the pad on it
--   grid       a building picked, LB: the shape strip and "GRID"
--   groups     two groups set, Start held: the group strip, and a note
--   radial     A held, X held: the area select's filter radial, the stick on Builders
--   place      touch: a building picked, a spot, PLACE, then held: a GRID with "GRID" over it
function widget:GetInfo()
	return { name = "BAR Droid pad screenshots", desc = "The app's gamepad interface, one screenshot each",
		author = "BAR Droid", layer = -10, enabled = true } -- (drawn after the app's widgets: on top)
end

local TOUCH = "LuaUI/Config/bardroid_touch.txt"
local function touch(line)
	local f = io.open(TOUCH, "a")
	f:write(line .. "\n")
	f:close()
end

local function shot(name)
	Spring.Echo("[uishot] shot " .. name)
	Spring.SendCommands("screenshot png")
end

local com, hoverCell
local function record() end

local function selectDefs(names)
	local want, units = {}, {}
	for _, n in ipairs(names) do
		want[n] = true
	end
	for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local def = UnitDefs[Spring.GetUnitDefID(u)]
		if def and want[def.name] then
			units[#units + 1] = u
		end
	end
	Spring.SelectUnitArray(units)
	return units
end

local function pickBuilding()
	for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do
		if cmd.id < 0 then
			Spring.SetActiveCommand(Spring.GetCmdDescIndex(cmd.id))
			return true
		end
	end
end

local controllerGame = Game.gameVersion == "$VERSION"
local STEPS = {
	[2] = function() touch("src test") end,
	[20] = function() Spring.SendCommands("cheat 1") end,
	[60] = function()
		com = (Spring.GetTeamUnits(Spring.GetMyTeamID()) or {})[1]
		local x, _, z = Spring.GetUnitPosition(com)
		for i, name in ipairs({ "armck", "armck", "armpw", "armpw", "armpw", "armham", "armham", "armflea" }) do
			Spring.SendCommands(string.format("give 1 %s 0 @%d,0,%d", name, x + 120 + (i % 4) * 50, z + 80 + math.floor(i / 4) * 50))
		end
	end,
	[100] = function()
		local x, _, z = Spring.GetUnitPosition(com)
		local cs = Spring.GetCameraState() -- (the same view each run: the units in the middle, BAR's usual angle)
		cs.px, cs.pz, cs.dist, cs.rx, cs.ry = x + 150, z + 80, 1600, 2.6, 0
		Spring.SetCameraState(cs, 0)
		if controllerGame then
			touch("act mod_bardroid") -- (the app's controls, its build menu, in the controller game)
		end
		touch("src pad")
		if WG.BarDroidPad then
			WG.BarDroidPad.setWarp(record)
		end
		if WG.bardroidBuildmenu and WG.bardroidBuildmenu.droidSetWarp then
			WG.bardroidBuildmenu.droidSetWarp(record)
		end
	end,
	[130] = function()
		Spring.SelectUnitArray({ com })
		touch("act pad_build")
	end,
	[165] = function()
		local focus = WG.bardroidBuildmenu and WG.bardroidBuildmenu.droidFocus and WG.bardroidBuildmenu.droidFocus()
		hoverCell = focus
	end,
	[170] = function() shot("buildmenu") end,
	[180] = function()
		hoverCell = nil
		touch("act pad_back")
		touch("act pad_orders")
	end,
	[210] = function() shot("orders") end,
	[220] = function()
		touch("act pad_back")
		Spring.SelectUnitArray({ com })
	end,
	[240] = function()
		pickBuilding()
		touch("act grid_on")
	end,
	[255] = function() shot("grid") end,
	[270] = function()
		Spring.SetActiveCommand(0)
		selectDefs({ "armck" })
		touch("act group_assign_1")
	end,
	[280] = function()
		selectDefs({ "armpw", "armham", "armflea" })
		touch("act group_assign_3")
		touch("act group_list_on")
	end,
	[300] = function() shot("groups") end,
	[315] = function()
		touch("act group_list_off")
		Spring.SelectUnitArray({})
		touch("act area_on")
		touch("act area_filter_open")
		touch("act area_filter_left")
	end,
	[345] = function() shot("radial") end,
	[355] = function()
		touch("act area_filter_close")
		touch("act area_off")
		Spring.SelectUnitArray({ com })
		touch("src touch")
	end,
	[370] = function() pickBuilding() end,
	[385] = function()
		local vsx, vsy = Spring.GetViewGeometry()
		touch(string.format("spot %d %d", math.floor(vsx * 0.55), math.floor(vsy * 0.45)))
	end,
	[395] = function()
		touch("grid start")
		touch("grid by 90 -60")
	end,
	[405] = function() shot("place") end,
	[440] = function()
		Spring.Echo("[uishot] done")
		Spring.SendCommands("quitforce")
	end,
}

function widget:GameFrame(f)
	local step = STEPS[f]
	if step then
		local ok, err = pcall(step)
		if not ok then
			Spring.Echo("[uishot] step " .. f .. " failed: " .. tostring(err))
		end
	end
end

-- the option the pad is on, as BAR's own hover and the app's outline draw it under a pointer (none moves here)
function widget:DrawScreen()
	local b = WG.bardroidBuildmenu
	if hoverCell and b and b.droidDrawHover then
		local list = gl.CreateList(function() end)
		pcall(b.droidDrawHover, hoverCell, list)
		gl.DeleteList(list)
	end
end
