-- For tools\touch-widget-test.ps1 -NoUnitControl: BAR's skirmish with "Allow Custom 'Unit Control' Widgets" unticked (Kailil,
-- 2026-11-01: "add a unitcontrol off rule when you test ... then you dont have to guess"), the pad's actions sent as the app
-- sends them. tools\pad-test.ps1 -Online plays the same on a phone with a virtual pad, through the app's input.
function widget:GetInfo()
	return { name = "BAR Droid rule off test", desc = "The pad's actions with unit-control widgets forbidden", author = "BAR Droid", layer = 0, enabled = true }
end

local PING = { 1500, 1500 }
local fails, frames, nextAt, step = 0, 0, 0, 0
local com, myPing = nil, false

local function verify(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[touchtest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end

local function touch(line)
	local f = io.open("LuaUI/Config/bardroid_touch.txt", "a")
	f:write(line .. "\n")
	f:close()
end

local function padFile()
	local f = io.open("LuaUI/Config/bardroid_pad.txt", "r")
	local text = f and f:read("*a") or ""
	if f then
		f:close()
	end
	return text
end

function widget:MapDrawCmd(playerID, cmdType)
	if cmdType == "point" and playerID == Spring.GetMyPlayerID() then
		myPing = true
	end
end

local STEPS = {
	function()
		Spring.SendCommands("cheat 1")
	end,
	function()
		com = Spring.GetTeamUnits(Spring.GetMyTeamID())[1]
		verify("the rule is on: a user widget's order is refused", not pcall(Spring.GiveOrderToUnit, com, CMD.STOP, {}, 0))
		Spring.SendCommands("give 3 armpw")
		Spring.SelectUnitArray({ com })
	end,
	function()
		touch("act pad_build")
	end,
	function()
		local b = WG.bardroidBuildmenu
		verify("RB: the build menu has the pad", b and b.droidFocus and b.droidFocus() ~= nil)
		touch("act pad_build")
		touch("act lb_y")
	end,
	function()
		local _, id = Spring.GetActiveCommand()
		verify("LB + Y: the patrol picked", id == CMD.PATROL, id)
		verify("... and the app asked to click", padFile():find("click 1\n", 1, true) ~= nil, padFile())
		Spring.SetActiveCommand(-1)
		touch("act queue_remove_last")
		touch("act queue_remove_first")
		touch("act select_combat")
	end,
	function()
		local _, note = WG.BarDroidPad.note()
		verify("no note says it cannot be done", note ~= "NOT IN THIS GAME", note)
		local selected = Spring.GetSelectedUnits()
		verify("RB + D-pad down: the combat units, no commander", #selected >= 3 and not Spring.IsUnitSelected(com), #selected)
		touch("act select_combat_screen")
	end,
	function()
		touch("act selfd")
	end,
	function()
		local first = Spring.GetSelectedUnits()[1]
		verify("Back + R3 + L3: self-destruct", first and (Spring.GetUnitSelfDTime(first) or 0) > 0, first)
		touch("act ping")
	end,
	function()
		verify("RB + D-pad up held: a ping", myPing)
		WG.BarDroidPad.setPing(PING[1], 0, PING[2])
		touch("act ping_look")
	end,
	function()
		local cs = Spring.GetCameraState()
		verify("RB + D-pad up: the camera at the last ping", math.abs(cs.px - PING[1]) < 400 and math.abs(cs.pz - PING[2]) < 400, cs.px)
		Spring.Echo("[touchtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
	end,
}

function widget:Update()
	frames = frames + 1
	if Spring.GetGameFrame() < 150 or frames < nextAt or step >= #STEPS then
		return
	end
	step = step + 1
	STEPS[step]()
	nextAt = frames + 30
end
