-- LuaUI widget for tools/replay-phone-test.ps1: BAR's replay speed column on a phone upright (BAR's Replay buttons with
-- the app's phone patch, phone-widget-gui_replaybuttons.lua.patch; 2026-11-19's system), by real taps in a replay the
-- lobby started (bardroid_replay_menu_test.lua). The column's rect from WG.BarDroidTapPanels.replaybuttons (its foot,
-- skip or pause, then BAR's ten speeds 0.5x to 20x, one height each): above the app's dock; 4x, 1x, 10x and 0.5x tapped
-- (the replay's speed each: Spring.GetGameSpeed); a drag from the column across the map pans the camera, the speed
-- kept; left-handed (the camera's rails on the left, put back after) the zoom and turn rails clear of the column.
-- Asks "do <n> tap|swipe|shot <x> <y> <vsx> [<x2> <y2> <ms>]" (X pixels, top left origin) in
-- LuaUI/Config/bardroid_replaytest.txt, answered "<n>". "[replaytest] done: ALL PASS" or "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid replay test", desc = "The replay speed column by real taps", author = "BAR Droid", layer = 0,
		enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_replaytest.txt", "LuaUI/Config/bardroid_replaytest_cmd.txt"
local SPEEDS = { 0.5, 1, 2, 3, 4, 6, 8, 10, 15, 20 } -- (BAR's, gui_replaybuttons.lua)
local TRY = { 5, 2, 8, 1 } -- 4x, 1x, 10x, 0.5x (each a change: a replay starts at 1x, so 1x first proved nothing)
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local readAt
local clock, t0 = 0, nil
local col -- the column's rect (GL pixels: x0, y0, x1, y1)
local tryAt = 0 -- (TRY's index being tapped)
local leftWas, camBefore

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[replaytest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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
local function go(s)
	stage, stageAt = s, clock
end
local function ask(action, x, y, nextStage, x2, y2, ms)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d%s\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx,
		x2 and string.format(" %d %d %d", math.floor(x2), math.floor(y2), ms or 600) or ""))
	after = nextStage
	go("asked")
end
local function columnRect()
	local f = WG.BarDroidTapPanels and WG.BarDroidTapPanels.replaybuttons
	if not f then
		return nil
	end
	local ok, x0, y0, x1, y1 = pcall(f)
	return ok and x0 and { x0, y0, x1, y1 } or nil
end
-- a speed's button middle (GL pixels): the foot is slot 0, speed i slot i, all one height
local function slot(i)
	local h = (col[4] - col[2]) / (#SPEEDS + 1)
	return (col[1] + col[3]) / 2, col[2] + (i + 0.5) * h
end
local function overlaps(a, b)
	return a and b and a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

local function step()
	local vsx, vsy = Spring.GetViewGeometry()
	if stage == "wait" then
		Spring.SelectUnitArray({}) -- (BAR's column shows with nothing picked)
		col = columnRect()
		if Spring.IsReplay() and Spring.GetGameFrame() > 90 and col and clock > 5 then
			go("check")
		elseif clock > 150 then
			check("a replay with BAR's speed column", false, string.format("replay %s, frame %d, column %s",
				tostring(Spring.IsReplay()), Spring.GetGameFrame(), tostring(col)))
			go("end")
		end
	elseif stage == "check" then
		local P = WG.BarDroidPortrait
		local dock = P and P.active and P.active() and P.dock and P.dock()
		Spring.Echo(string.format("[replaytest] (%dx%d; the column %d,%d-%d,%d; the dock's top %s; speed %.2f)", vsx, vsy,
			col[1], col[2], col[3], col[4], dock and tostring(dock[4]) or "none", Spring.GetGameSpeed()))
		check("upright, the column above the app's dock and on the screen", vsx < vsy and dock and col[2] >= dock[4]
			and col[1] >= 0 and col[4] <= vsy, string.format("column y %d-%d, the dock's top %s", col[2], col[4],
				dock and tostring(dock[4]) or "none"))
		tryAt = 1
		go("tap")
	elseif stage == "tap" then
		local i = TRY[tryAt]
		local x, y = slot(i)
		ask("tap", x, vsy - y, "tap?")
	elseif stage == "tap?" and clock - stageAt > 1.2 then
		local want = SPEEDS[TRY[tryAt]]
		local now = Spring.GetGameSpeed()
		check(string.format("%gx tapped: the replay at %gx", want, want), math.abs(now - want) < 0.01,
			string.format("at %.2f", now))
		if want == 4 then
			ask("shot", 0, 0, "next")
		else
			go("next")
		end
	elseif stage == "next" then
		tryAt = tryAt + 1
		if tryAt <= #TRY then
			go("tap")
		else
			local x, y = slot(3) -- (2x's button: a drag from it across the map)
			camBefore = { Spring.GetCameraPosition() }
			ask("swipe", x, vsy - y, "drag?", x + vsx * 0.35, vsy - y - vsy * 0.08, 500)
		end
	elseif stage == "drag?" and clock - stageAt > 1.2 then
		local cx, _, cz = Spring.GetCameraPosition()
		local moved = math.sqrt((cx - camBefore[1]) ^ 2 + (cz - camBefore[3]) ^ 2)
		local now = Spring.GetGameSpeed()
		check("a drag from the column across the map: the camera pans, the speed kept (0.5x)", moved > 20
			and math.abs(now - 0.5) < 0.01, string.format("moved %.0f, speed %.2f", moved, now))
		local C = WG.BarDroidCamCtl
		if not C then
			check("the camera controls", false, "none")
			go("end")
			return
		end
		leftWas = C.left()
		C.setLeft(true)
		go("left")
	elseif stage == "left" and clock - stageAt > 1.5 then
		col = columnRect() or col
		local _, zoom, turn = WG.BarDroidCamCtl.rects()
		check("left-handed: the zoom rail clear of the column", zoom and not overlaps(zoom, col),
			zoom and string.format("rail x %d-%d y %d-%d, column x %d-%d y %d-%d", zoom[1], zoom[3], zoom[2], zoom[4], col[1],
				col[3], col[2], col[4]) or "no zoom rail")
		check("... and the turn rail", not overlaps(turn, col), turn and string.format("rail x %d-%d y %d-%d", turn[1],
			turn[3], turn[2], turn[4]) or "no turn rail")
		ask("shot", 1, 0, "end")
	elseif stage == "end" then
		local C = WG.BarDroidCamCtl
		if C and leftWas ~= nil and C.left() ~= leftWas then
			C.setLeft(leftWas)
		end
		Spring.SendCommands("setspeed 1")
		Spring.Echo("[replaytest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		write("end\n")
		go("over")
	end
	if stage == "asked" and clock - (readAt or -1) >= 0.1 then
		readAt = clock
		local c = readLine(CMD_FILE)
		if c and tonumber(c) == asked then
			go(after)
		elseif clock - stageAt > 30 then
			check("the script's " .. tostring(after) .. " step", false, "not done in 30 s")
			go("end")
		end
	end
end

function widget:Update()
	local now = Spring.GetTimer()
	t0 = t0 or now
	clock = Spring.DiffTimers(now, t0)
	step()
end

function widget:Shutdown() -- (a test cut short: the player's left-handed setting back)
	local C = WG.BarDroidCamCtl
	if C and leftWas ~= nil and C.left() ~= leftWas then
		C.setLeft(leftWas)
	end
end
