-- LuaUI widget for tools/stats-phone-test.ps1: the app's Statistics (bardroid_teamstats.lua, BAR's TeamStats copied)
-- upright on the dev phone, by real taps (2026-11-19's system, hardened 2026-11-20). In a skirmish: BAR's Statistics
-- button on the top bar tapped (found along its strip with WG.topbar.buttonAt); the panel open, the screen's width
-- (within it), between the top bar and the app's dock; the one-finger camera's knob and rails off meanwhile
-- (bardroid_camctl.txt "none": RtsTouch then hands their touches to the panel); a drag on the panel where the knob
-- stands leaves the camera still; its graphs open (12 a page, three across upright) with no Lua error; the red close
-- button tapped: closed, the knob back; Statistics tapped twice: open, then closed again. Taps and pictures asked for
-- by "do <n> tap|shot|swipe <x> <y> <vsx> [<x2> <y2>]" (X pixels, top left origin) in LuaUI/Config/bardroid_statstest.txt,
-- answered "<n>" in bardroid_statstest_cmd.txt. "[statstest] done: ALL PASS" or "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid stats test", desc = "Statistics upright by real taps", author = "BAR Droid", layer = 0,
		enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_statstest.txt", "LuaUI/Config/bardroid_statstest_cmd.txt"
local CAM_FILE = "LuaUI/Config/bardroid_camctl.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local statsAt -- BAR's Statistics button's middle (X pixels, top left origin)
local cam0 -- the camera before the drag on the panel
local readAt -- (when the answer file was last read)

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[statstest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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

-- the script asked to tap, swipe or take a picture at x, y (X pixels, top left origin); "nextStage" once it is done
local function ask(action, x, y, nextStage, f, x2, y2)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d%s\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx,
		x2 and string.format(" %d %d", math.floor(x2), math.floor(y2)) or ""))
	after = nextStage
	go("asked", f)
end

local function shown()
	local T = WG.teamstats
	return T and T.isvisible and T.isvisible() or false
end
-- BAR's Statistics button's middle on the top bar (X pixels from the top left), found along its strip
local function statsButton()
	local tb = WG.topbar
	local pos = tb and tb.GetButtonsPosition and tb.GetButtonsPosition()
	if not (pos and tb.buttonAt) then
		return nil
	end
	local vsy = select(2, Spring.GetViewGeometry())
	local y = math.floor((pos[2] + pos[4]) / 2)
	local x0, x1
	for x = math.floor(pos[1]), math.floor(pos[3]), 3 do
		if tb.buttonAt(x, y) == "stats" then
			x0, x1 = x0 or x, x
		end
	end
	return x0 and { (x0 + x1) / 2, vsy - y } or nil, pos
end
local function camSame(a, b)
	local worst = 0
	for _, k in ipairs({ "px", "py", "pz", "dist", "height", "rx", "ry", "rz", "zscale" }) do
		if type(a[k]) == "number" and type(b[k]) == "number" then
			worst = math.max(worst, math.abs(a[k] - b[k]) / (k:sub(1, 1) == "r" and 0.01 or 1))
		end
	end
	return worst < 1, worst
end

-- (stepped in Update by real time, in thirtieths of a second: a game alone may pause under BAR's windows, and then has
-- no GameFrame; the first run stood still after the tap on Statistics, 2026-11-20)
local function step(f)
	local vsx, vsy = Spring.GetViewGeometry()
	if stage == "wait" and Spring.GetGameFrame() >= 150 then
		local P = WG.BarDroidPortrait
		if not (P and P.active and P.active() and vsx < vsy) then
			check("upright with the app's dock", false, string.format("%dx%d, dock %s", vsx, vsy, tostring(P and P.active and P.active())))
			go("end", f)
			return
		end
		if not (WG.teamstats and WG.teamstats.droidRect) then
			check("the app's Statistics (bardroid_teamstats.lua) running, its droidRect there", false, tostring(WG.teamstats))
			go("end", f)
			return
		end
		Spring.SelectUnitArray({})
		local pos
		statsAt, pos = statsButton()
		Spring.Echo(string.format("[statstest] (%dx%d; the top bar's buttons %s; Statistics at %s)", vsx, vsy,
			pos and string.format("%d,%d-%d,%d", pos[1], pos[2], pos[3], pos[4]) or "none",
			statsAt and string.format("%d,%d", statsAt[1], statsAt[2]) or "none"))
		if not statsAt then
			check("BAR's Statistics button on the top bar", false, "not found along the strip")
			go("end", f)
			return
		end
		ask("tap", statsAt[1], statsAt[2], "open?", f)
	elseif stage == "open?" and f - stageAt > 30 then
		local rect, close = WG.teamstats.droidRect()
		local P = WG.BarDroidPortrait
		local dock = P.dock and P.dock()
		local _, pos = statsButton()
		check("Statistics tapped on the top bar: the panel open", shown(), tostring(shown()) .. ", the game "
			.. (select(3, Spring.GetGameSpeed()) and "paused" or "running"))
		local w = rect[3] - rect[1]
		check("upright as wide as the screen, within it", rect[1] >= 0 and rect[3] <= vsx and w >= vsx * 0.95,
			string.format("x %d-%d of %d", rect[1], rect[3], vsx))
		local dockTop = dock and dock[4] or 0
		local barBottom = pos and pos[2] or vsy
		check("between the app's dock and BAR's top bar", rect[2] >= dockTop - 2 and rect[4] <= barBottom + vsy * 0.02
			and rect[4] - rect[2] >= (barBottom - dockTop) * 0.8,
			string.format("y %d-%d, the dock's top %d, the top bar's buttons from %d", rect[2], rect[4], dockTop, barBottom))
		check("its close button at the header's right end", close and close[3] <= rect[3] and close[3] >= rect[3] - vsx * 0.1
			and close[4] <= rect[4] and close[4] >= rect[4] - vsy * 0.1,
			close and string.format("%d,%d-%d,%d", close[1], close[2], close[3], close[4]) or "none")
		local camLine = readLine(CAM_FILE)
		local C = WG.BarDroidCamCtl
		local knobOn = C and C.knob and C.knob()
		check("the camera knob and rails off while it is open (RtsTouch's file)", camLine == "none",
			tostring(camLine) .. (knobOn and "" or " (the knob is off on this phone)"))
		ask("shot", 0, 0, "drag", f)
	elseif stage == "drag" then -- (a drag up over the panel where the knob stands, else the panel's middle)
		local rect = WG.teamstats.droidRect()
		local C = WG.BarDroidCamCtl
		local knob = C and C.rects and C.rects()
		local x, y = (rect[1] + rect[3]) / 2, (rect[2] + rect[4]) / 2
		if knob and knob[1] then
			x, y = knob[1], knob[2]
		end
		y = math.max(rect[2] + 40, math.min(rect[4] - 240, y))
		cam0 = Spring.GetCameraState()
		Spring.Echo(string.format("[statstest] (the drag from %d,%d up 200: the knob %s)", x, y,
			knob and knob[1] and string.format("at %d,%d r %d", knob[1], knob[2], knob[3]) or "none"))
		ask("swipe", x, vsy - y, "drag?", f, x, vsy - y - 200)
	elseif stage == "drag?" and f - stageAt > 20 then
		local same, worst = camSame(cam0, Spring.GetCameraState())
		check("a drag over the panel where the knob stands: the camera still, the panel open", same and shown(),
			string.format("camera moved by %.2f, open %s", worst, tostring(shown())))
		WG.teamstats.showGraphs(true)
		go("graphs?", f)
	elseif stage == "graphs?" and f - stageAt > 45 then
		local _, _, open = WG.teamstats.droidRect()
		check("its graphs open (BAR's Graphs page)", open and shown(), "graphs " .. tostring(open))
		ask("shot", 1, 0, "close", f)
	elseif stage == "close" then
		local _, close, _, hit = WG.teamstats.droidRect()
		if not (close and hit) then
			check("the close button and its tap area", false, tostring(close) .. " " .. tostring(hit))
			go("end", f)
			return
		end
		-- (its tap area a fingertip's: some 7 mm wide and 3.5 tall at least, 13 X pixels a mm on the dev phone; the
		-- button alone was 45 x 30, 2026-11-20. Tapped left of and below the red button, inside the area)
		check("the close button's tap area a fingertip's", hit[3] - hit[1] >= vsx * 0.09 and hit[4] - hit[2] >= vsx * 0.045,
			string.format("%d x %d (the button %d x %d) of %d", hit[3] - hit[1], hit[4] - hit[2], close[3] - close[1],
				close[4] - close[2], vsx))
		ask("tap", (hit[1] + close[1]) / 2, vsy - (hit[2] + close[2]) / 2, "closed?", f)
	elseif stage == "closed?" and f - stageAt > 45 then
		local camLine = readLine(CAM_FILE)
		local C = WG.BarDroidCamCtl
		local on = C and ((C.knob and C.knob()) or (C.rails and C.rails()))
		check("the red close button tapped: closed", not shown(), tostring(shown()))
		check("the camera knob and rails back", not on or (camLine and camLine ~= "none"), tostring(camLine))
		ask("tap", statsAt[1], statsAt[2], "again?", f)
	elseif stage == "again?" and f - stageAt > 30 then
		check("Statistics tapped again: open", shown(), tostring(shown()))
		ask("tap", statsAt[1], statsAt[2], "toggled?", f)
	elseif stage == "toggled?" and f - stageAt > 30 then
		check("Statistics tapped once more: closed (the top bar's button toggles it)", not shown(), tostring(shown()))
		if shown() then
			WG.teamstats.toggle(false)
		end
		go("end", f)
	elseif stage == "end" then
		Spring.Echo("[statstest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
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
