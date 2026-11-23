-- LuaUI widget for tools/menusession-phone-test.ps1 (RC 0.2.0 item 7): in each game of one lobby session (the state
-- file the lobby's test widget writes: game1, game2) the commander picked and the build menu looked at. Game 1: the
-- app's copy runs (its own grid shown or not by the layout), then it is broken on purpose (droidBreak): BAR removes it, the
-- menu watch (bardroid_touch.lua) puts BAR's own on in its place, showing. Game 2, the same session after the lobby: BAR's
-- own build menu from the start, showing, the copy not back. A picture of each ("shot <n> <game>" in its file, answered
-- "<n>"), then "<game> checked" for the lobby's widget. Logs "[menusession] PASS|FAIL ..." lines.
function widget:GetInfo()
	return { name = "BAR Droid menu session test (game)", desc = "The build menu in each game of a lobby session",
		author = "BAR Droid", layer = 0, enabled = true }
end

local STATE = "LuaUI/Config/bardroid_menusession_state.txt"
local OUT, CMD = "LuaUI/Config/bardroid_menusession_ui.txt", "LuaUI/Config/bardroid_menusession_ui_cmd.txt"
local game -- ("game1", "game2"; nil: not this test's game)
local stage, stageAt, clock, asked, fails = "wait", 0, 0, 0, 0
local copyWas, com

local function log(s)
	Spring.Echo("[menusession] " .. s)
end
local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	log((ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function readLine(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end
local function writeLine(path, s)
	local f = io.open(path, "w")
	if f then
		f:write(s .. "\n")
		f:close()
	end
end
local function go(s)
	stage, stageAt = s, clock
end
local function commander()
	for _, u in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u)]
		if ud and ud.customParams and ud.customParams.iscommander then
			return u
		end
	end
end
local function pick()
	com = com or commander()
	if com then
		Spring.SelectUnitArray({})
		Spring.SelectUnitArray({ com })
	end
end
-- the build menu as it stands: the copy, WG.buildmenu, whose it is, and whether it shows (the commander picked)
local function menu()
	local B, M = WG.bardroidBuildmenu, WG.buildmenu
	local showing = M and M.getIsShowing and M.getIsShowing() and true or false
	local whose = M == nil and "none" or (B ~= nil and M == B) and "the copy's"
		or (copyWas ~= nil and M == copyWas) and "the removed copy's" or "BAR's"
	return B, M, showing, string.format("copy %s, WG.buildmenu %s, showing %s, %d picked", B ~= nil and "running" or "gone",
		whose, tostring(showing), #(Spring.GetSelectedUnits() or {}))
end

function widget:Initialize()
	game = readLine(STATE)
	if game ~= "game1" and game ~= "game2" then
		game = nil
	else
		writeLine(CMD, "0") -- (the last game's answers out: each game counts its pictures from 1)
	end
	log("(the game widget loaded: " .. tostring(game or "not the test's game") .. ")")
end

function widget:Update()
	if not game then
		return
	end
	local now = Spring.GetTimer()
	widget.t0 = widget.t0 or now
	clock = Spring.DiffTimers(now, widget.t0)
	if stage == "wait" and Spring.GetGameFrame() >= 150 then -- (past the menu watch's first look, frame 90)
		pick()
		go("look")
	elseif stage == "look" and clock - stageAt > 1.5 then
		local B, M, showing, detail = menu()
		if game == "game1" then -- (the copy's own grid shows or not by the layout: sideways the dock has the build grid)
			check("game 1 of a lobby session: the app's build menu copy runs", B ~= nil and M == B, detail)
			copyWas = B
			if B and B.droidBreak then
				B.droidBreak()
			else
				check("game 1: the copy broken on purpose (droidBreak)", false, "no copy, or no droidBreak")
			end
			go("broken")
		else
			check("game 2 of the same lobby session: BAR's own build menu from the start, showing, the copy not back",
				B == nil and M ~= nil and showing, detail)
			go("shot")
		end
	elseif stage == "broken" and clock - stageAt > 4 then
		pick() -- (BAR's menu came on with the commander already picked)
		go("broken2")
	elseif stage == "broken2" and clock - stageAt > 1.5 then
		local B, M, showing, detail = menu()
		check("game 1: the copy removed for its error, BAR's own build menu in its place (the menu watch), showing",
			B == nil and M ~= nil and M ~= copyWas and showing, detail)
		go("shot")
	elseif stage == "shot" then
		asked = asked + 1
		writeLine(OUT, string.format("shot %d %s", asked, game))
		go("shotwait")
	elseif stage == "shotwait" and (readLine(CMD) == tostring(asked) or clock - stageAt > 15) then
		log(string.format("%s done: %s", game, fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		writeLine(OUT, game .. " checked")
		go("over")
	end
end
