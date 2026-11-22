-- LuaUI widget for tools/buildbar-phone-test.ps1: BAR's Build Bar ("Factory dock", gui_buildbar.lua, off on phones as
-- the app sets them up; turned on for the run by the script) by real taps upright on the dev phone. Its MousePress
-- decided by the icon the pointer was over at the last Update; a finger moves the pointer and presses in one frame
-- (docs/DELIVERY.md, "The same stale hover in BAR's player list and Build Bar"). In a skirmish (cheats on): a Bot Lab
-- given beside the commander; then three times: a tap on the map (the pointer away from the bar), a tap on the lab's
-- icon on the bar: the lab picked (its menu handler); a tap on the map (the pointer left on the bar): the press reaches
-- this widget, the last in the press order (layer 1e9), so the bar did not take it. The icons' places from the phone
-- version's WG.BarDroidBuildBar.rects. Taps and pictures asked for by "do <n> tap|shot <x> <y> <vsx>" (X pixels, top
-- left origin) in LuaUI/Config/bardroid_buildbartest.txt, answered "<n>" in bardroid_buildbartest_cmd.txt.
-- "[buildbartest] done: ALL PASS" or "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid build bar test", desc = "BAR's Build Bar by real taps", author = "BAR Droid",
		layer = 1000000000, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_buildbartest.txt", "LuaUI/Config/bardroid_buildbartest_cmd.txt"
local CAM_FILE = "LuaUI/Config/bardroid_camctl.txt" -- (the one-finger camera's rects for RtsTouch: X pixels, top left)
local ROUNDS = 3
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local readAt
local lab, round = nil, 0
local presses, pressesBefore = 0, 0

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[buildbartest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
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
local function go(s, f)
	stage, stageAt = s, f
end
local function ask(action, x, y, nextStage, f)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx))
	after = nextStage
	go("asked", f)
end

-- (the last in the press order: a press that reaches it was taken by no widget before it)
function widget:MousePress()
	presses = presses + 1
	return false
end

-- the lab's icon on the bar, left of its middle (its repeat switch is in the top right corner): X pixels, top left
local function labIcon()
	local B = WG.BarDroidBuildBar
	if not (B and B.rects) then
		return nil
	end
	local facRect, _, _, n = B.rects()
	if not (facRect and n and n >= 1 and facRect[3] > facRect[1]) then
		return nil
	end
	local vsy = select(2, Spring.GetViewGeometry())
	local h = (facRect[2] - facRect[4]) / n
	return facRect[1] + (facRect[3] - facRect[1]) * 0.35, vsy - (facRect[2] - h * 0.6), facRect
end
-- a spot of open map: left of the middle, under the top bar, above the dock, away from the bar on the right
local function mapSpot()
	local vsx, vsy = Spring.GetViewGeometry()
	return vsx * 0.22, vsy * 0.3
end
-- the zoom rail's rect in RtsTouch's file (X pixels, top left origin), or nil and the file's text
local function zoomRail()
	local f = io.open(CAM_FILE, "r")
	if not f then
		return nil, "no file"
	end
	local s = f:read("*a") or ""
	f:close()
	local x0, y0, x1, y1 = s:match("zoom (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)")
	if not x0 then
		return nil, s:gsub("\n", "; ")
	end
	return { tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1) }
end
local function picked()
	local sel = Spring.GetSelectedUnits()
	return #sel == 1 and sel[1] == lab, #sel
end

local function step(f)
	local vsx, vsy = Spring.GetViewGeometry()
	if stage == "wait" and Spring.GetGameFrame() >= 90 then
		local P = WG.BarDroidPortrait
		if not (P and P.active and P.active() and vsx < vsy) then
			check("upright with the app's dock", false, string.format("%dx%d", vsx, vsy))
			go("end", f)
			return
		end
		if not WG.BarDroidBuildBar then
			check("BAR's Build Bar on, the phone version (WG.BarDroidBuildBar)", false, "not there")
			go("end", f)
			return
		end
		Spring.SendCommands("cheat 1")
		go("give", f)
	elseif stage == "give" and f - stageAt > 15 then
		local com = Spring.GetTeamUnits(Spring.GetMyTeamID())[1]
		local x, y, z = Spring.GetUnitPosition(com)
		Spring.SendCommands(string.format("give 1 armlab @%d,%d,%d", x + 220, y, z + 60))
		go("given?", f)
	elseif stage == "given?" and f - stageAt > 45 then
		for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID())) do
			if UnitDefs[Spring.GetUnitDefID(unitID)].isFactory then
				lab = unitID
			end
		end
		local x, _, rect = labIcon()
		check("a Bot Lab given, its icon on the Build Bar", lab and x, string.format("lab %s, the bar %s", tostring(lab),
			rect and string.format("%d,%d-%d,%d (GL)", rect[1], rect[4], rect[3], rect[2]) or "none"))
		if not (lab and x) then
			go("end", f)
			return
		end
		-- (the one-finger camera on for the run: its zoom rail along the right edge stands clear of the bar's icons, which
		-- the phone version lists among the app's tap panels; upright it lay over them, 2026-11-20)
		local z, why = zoomRail()
		local bx0, by0, bx1, by1 = rect[1], vsy - rect[2], rect[3], vsy - rect[4]
		check("the camera's zoom rail clear of the bar's icons", z and (z[3] <= bx0 or z[1] >= bx1 or z[4] <= by0
			or z[2] >= by1), z and string.format("rail %d,%d-%d,%d, icons %d,%d-%d,%d", z[1], z[2], z[3], z[4], bx0, by0,
			bx1, by1) or ("no zoom rail: " .. tostring(why)))
		Spring.SelectUnitArray({})
		ask("shot", 0, 0, "round", f)
	elseif stage == "round" then
		round = round + 1
		local x, y = mapSpot()
		ask("tap", x, y, "icon", f)
	elseif stage == "icon" and f - stageAt > 15 then
		Spring.SelectUnitArray({})
		local x, y = labIcon()
		ask("tap", x, y, "icon?", f)
	elseif stage == "icon?" and f - stageAt > 20 then
		local ok, n = picked()
		check(string.format("round %d: a first tap on the lab's icon (the pointer on the map before): the lab picked", round),
			ok, n .. " picked")
		pressesBefore = presses
		local x, y = mapSpot()
		ask("tap", x, y, "map?", f)
	elseif stage == "map?" and f - stageAt > 20 then
		check(string.format("round %d: then a tap on the map (the pointer left on the bar): the press reaches the map",
			round), presses > pressesBefore, string.format("%d press(es) through", presses - pressesBefore))
		if round == 1 then
			ask("shot", 1, 0, round < ROUNDS and "round" or "end", f)
		else
			go(round < ROUNDS and "round" or "end", f)
		end
	elseif stage == "end" then
		Spring.Echo("[buildbartest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		write("end\n")
		go("over", f)
	end
	if stage == "asked" and f - (readAt or -10) >= 3 then
		readAt = f
		local c = readLine(CMD_FILE)
		if c and tonumber(c) == asked then
			go(after, f)
		elseif f - stageAt > 30 * 30 then
			check("the script's " .. after .. " step", false, "not done in 30 s")
			go("end", f)
		end
	end
end

local clock = 0
function widget:Update(dt)
	clock = clock + (dt or 0)
	step(math.floor(clock * 30))
end
