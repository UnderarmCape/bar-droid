-- LuaUI widget for tools/camctl-phone-test.ps1: the one-finger camera (bardroid_camctl.lua's knob and edge rails,
-- RtsTouch's CAM state; Kailil 2026-11-19) upright on the dev phone, by real drags. In a skirmish: the knob dragged up,
-- then down (the camera's distance one way, then back the other), right, then left (it turns one way, then the other);
-- the zoom rail dragged up (as the knob's up), the turn rail dragged right (the other way from the knob's right, Kailil:
-- "invert it"); the zoom rail slow, then as far fast (the fast one moves more: "slower speed means less movement");
-- a tap on the knob (the camera still, the map's tap under it: a Pawn given there picked); Settings open: the knob and rails gone from RtsTouch's file, a
-- drag where the knob was leaves the camera; left-handed (BarDroidCamLeft, put back after): the rails on the left, a
-- drag up the left zoom rail zooms as the right one. Drags asked for by "do <n> swipe|tap|shot <x> <y> <vsx> [<x2> <y2>
-- <ms>]" (X pixels, top left origin) in LuaUI/Config/bardroid_camctltest.txt, answered "<n>". Steps in Update by real
-- time (Settings pauses a game alone). "[camctltest] done: ALL PASS" or "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid camctl test", desc = "The camera knob and rails by real drags", author = "BAR Droid",
		layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_camctltest.txt", "LuaUI/Config/bardroid_camctltest_cmd.txt"
local CAM_FILE = "LuaUI/Config/bardroid_camctl.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local readAt
local clock, t0 = 0, nil
local before -- the camera's { dist, yaw } before a drag
local d = {} -- what each drag did: d.knobUp = { dDist, dYaw }, ...
local leftWas -- the player's left-handed setting

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[camctltest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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

-- the camera: its distance to the ground at the view's middle, and which way it looks (radians round the vertical)
local function camNow()
	local vsx, vsy = Spring.GetViewGeometry()
	local cx, cy, cz = Spring.GetCameraPosition()
	local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy * 0.6), true)
	local dist = pos and math.sqrt((pos[1] - cx) ^ 2 + (pos[2] - cy) ^ 2 + (pos[3] - cz) ^ 2) or cy
	local dx, _, dz = Spring.GetCameraDirection()
	return { dist = dist, yaw = math.atan2(dx, dz) }
end
local function change(a, b) -- (the distance as a ratio's log, the turn in radians the short way round)
	local dyaw = b.yaw - a.yaw
	dyaw = (dyaw + math.pi) % (2 * math.pi) - math.pi
	return { math.log(b.dist / a.dist), dyaw }
end
local function said(c)
	return string.format("distance x%.3f, turned %.3f rad", math.exp(c[1]), c[2])
end
local function rects()
	local C = WG.BarDroidCamCtl
	if not (C and C.rects) then
		return nil
	end
	return C.rects()
end
-- a drag (X pixels, top left) from GL point (x, y) by (dx, dy) GL pixels (up is +dy), over ms
local function drag(x, y, dx, dy, nextStage, ms)
	local _, vsy = Spring.GetViewGeometry()
	before = camNow()
	ask("swipe", x, vsy - y, nextStage, x + dx, vsy - (y + dy), ms)
end
local function measured(key)
	d[key] = change(before, camNow())
	Spring.Echo("[camctltest] (" .. key .. ": " .. said(d[key]) .. ")")
	return d[key]
end
local SETTLE = 1.2 -- (s: the touch widget's smoothing done)

local function step()
	local vsx, vsy = Spring.GetViewGeometry()
	local knob, zoom, turn
	if stage ~= "wait" then
		knob, zoom, turn = rects()
	end
	if stage == "wait" and Spring.GetGameFrame() >= 150 then
		local P = WG.BarDroidPortrait
		local C = WG.BarDroidCamCtl
		if not (P and P.active and P.active() and vsx < vsy and C) then
			check("upright with the app's dock and the camera controls", false, string.format("%dx%d, %s", vsx, vsy, tostring(C)))
			go("end")
			return
		end
		Spring.SelectUnitArray({})
		Spring.SendCommands("cheat 1") -- (the knob tap's Pawn, given later: a give in the cheat's own frame is ignored)
		leftWas = C.left()
		if leftWas then
			C.setLeft(false)
		end
		if not C.knob() then
			C.setKnob(true)
			d.knobWasOff = true
		end
		if not C.rails() then
			C.setRails(true)
			d.railsWereOff = true
		end
		go("ready")
	elseif stage == "ready" and clock - stageAt > 1 then
		local camLine = readLine(CAM_FILE)
		check("the knob and both rails up, in RtsTouch's file", knob and zoom and turn and camLine ~= nil
			and camLine ~= "none",
			string.format("knob %s, zoom rail %s, turn rail %s; the file \"%s\"", knob and "yes" or "no", zoom and "yes" or "no",
				turn and "yes" or "no", tostring(camLine)))
		if not (knob and zoom and turn) then
			go("end")
			return
		end
		Spring.Echo(string.format("[camctltest] (knob at %d,%d r %d; zoom rail %d,%d-%d,%d; turn rail %d,%d-%d,%d; %dx%d)",
			knob[1], knob[2], knob[3], zoom[1], zoom[2], zoom[3], zoom[4], turn[1], turn[2], turn[3], turn[4], vsx, vsy))
		ask("shot", 0, 0, "knobUp")
	elseif stage == "knobUp" then
		drag(knob[1], knob[2], 0, vsy * 0.12, "knobUp?")
	elseif stage == "knobUp?" and clock - stageAt > SETTLE then
		measured("knobUp")
		drag(knob[1], knob[2], 0, -vsy * 0.12, "knobDown?")
	elseif stage == "knobDown?" and clock - stageAt > SETTLE then
		local up, down = d.knobUp, measured("knobDown")
		check("the knob up, then down: the camera's distance one way, then the other, no turn",
			math.abs(up[1]) > 0.05 and math.abs(down[1]) > 0.05 and up[1] * down[1] < 0
				and math.abs(up[2]) < 0.05 and math.abs(down[2]) < 0.05,
			"up " .. said(up) .. "; down " .. said(down))
		drag(knob[1], knob[2], vsx * 0.2, 0, "knobRight?")
	elseif stage == "knobRight?" and clock - stageAt > SETTLE then
		measured("knobRight")
		drag(knob[1], knob[2], -vsx * 0.2, 0, "knobLeft?")
	elseif stage == "knobLeft?" and clock - stageAt > SETTLE then
		local r, l = d.knobRight, measured("knobLeft")
		check("the knob right, then left: it turns one way, then the other, the distance kept",
			math.abs(r[2]) > 0.05 and math.abs(l[2]) > 0.05 and r[2] * l[2] < 0 and math.abs(r[1]) < 0.05 and math.abs(l[1]) < 0.05,
			"right " .. said(r) .. "; left " .. said(l))
		local x = (zoom[1] + zoom[3]) / 2
		drag(x, zoom[2] + (zoom[4] - zoom[2]) * 0.2, 0, (zoom[4] - zoom[2]) * 0.6, "zoomUp?")
	elseif stage == "zoomUp?" and clock - stageAt > SETTLE then
		local z = measured("zoomUp")
		check("the zoom rail up: the distance as the knob's up", math.abs(z[1]) > 0.05 and z[1] * d.knobUp[1] > 0
			and math.abs(z[2]) < 0.05, said(z) .. " (the knob up " .. said(d.knobUp) .. ")")
		local y = (turn[2] + turn[4]) / 2
		drag(turn[1] + (turn[3] - turn[1]) * 0.15, y, (turn[3] - turn[1]) * 0.7, 0, "turnRight?")
	elseif stage == "turnRight?" and clock - stageAt > SETTLE then
		local t = measured("turnRight")
		check("the turn rail right: it turns the other way from the knob's right (Kailil: \"invert it\")",
			math.abs(t[2]) > 0.05 and t[2] * d.knobRight[2] < 0 and math.abs(t[1]) < 0.05,
			said(t) .. " (the knob right " .. said(d.knobRight) .. ")")
		local x = (zoom[1] + zoom[3]) / 2
		drag(x, zoom[2] + (zoom[4] - zoom[2]) * 0.8, 0, -(zoom[4] - zoom[2]) * 0.6, "slow?", 2400)
	elseif stage == "slow?" and clock - stageAt > SETTLE then
		measured("slow")
		local x = (zoom[1] + zoom[3]) / 2
		drag(x, zoom[2] + (zoom[4] - zoom[2]) * 0.8, 0, -(zoom[4] - zoom[2]) * 0.6, "fast?", 200)
	elseif stage == "fast?" and clock - stageAt > SETTLE then
		local s, f = d.slow, measured("fast")
		check("the zoom rail slow, then as far fast: the fast one moves more", math.abs(f[1]) > math.abs(s[1]) * 1.3
			and s[1] * f[1] > 0, "slow " .. said(s) .. "; fast " .. said(f))
		-- (the slow drag's floor, RC 0.2.0 item 4: at the old one it zoomed x0.946, "the rail is broken", NB2-5)
		check("... the slow one still zooms a good step (the rail's floor): over 15 %", math.abs(s[1]) >= math.log(1 / 0.86),
			"slow " .. said(s))
		-- (a Pawn of mine on the ground under the knob: a tap on the knob that does not move is the map's tap there, so it
		-- picks the Pawn; RC 0.2.0 item 4, the playtest's converter taps on the knob, NB3-4)
		local _, pos = Spring.TraceScreenRay(knob[1], knob[2], true)
		if pos then
			Spring.SendCommands(string.format("give 1 armpw %d @%d,%d,%d", Spring.GetMyTeamID(), pos[1], pos[2], pos[3]))
		end
		go("pawn")
	elseif stage == "pawn" and clock - stageAt > 1.5 then
		Spring.SelectUnitArray({})
		before = camNow()
		ask("tap", knob[1], vsy - knob[2], "tap?")
	elseif stage == "tap?" and clock - stageAt > SETTLE then
		local c = change(before, camNow())
		local sel = Spring.GetSelectedUnits()
		local ud = sel[1] and UnitDefs[Spring.GetUnitDefID(sel[1]) or -1]
		check("a tap on the knob that does not move: the camera still, the map's tap under it (the Pawn there picked)",
			math.abs(c[1]) < 0.01 and math.abs(c[2]) < 0.01 and #sel == 1 and ud and ud.name == "armpw",
			said(c) .. ", " .. #sel .. " picked" .. (ud and (": " .. ud.name) or ""))
		Spring.SelectUnitArray({})
		d.knobAt = { knob[1], knob[2] }
		WG.options.toggle(true)
		go("settings")
	elseif stage == "settings" and clock - stageAt > 1.5 then
		local camLine = readLine(CAM_FILE)
		check("Settings open: the knob and rails gone from RtsTouch's file", camLine == "none", tostring(camLine))
		drag(d.knobAt[1], d.knobAt[2], 0, vsy * 0.1, "settings?")
	elseif stage == "settings?" and clock - stageAt > SETTLE then
		local c = measured("underSettings")
		check("... a drag where the knob was: the camera still", math.abs(c[1]) < 0.01 and math.abs(c[2]) < 0.01, said(c))
		WG.options.toggle(false)
		WG.BarDroidCamCtl.setLeft(true)
		go("left")
	elseif stage == "left" and clock - stageAt > 1.5 then
		local lk, lz = rects()
		check("left-handed: the zoom rail and the knob on the left", lz and lk and lz[3] < vsx / 2 and lk[1] < vsx / 2,
			lz and lk and string.format("zoom rail x %d-%d, knob x %d of %d", lz[1], lz[3], lk[1], vsx) or "missing")
		if not lz then
			go("end")
			return
		end
		ask("shot", 1, 0, "leftZoom")
	elseif stage == "leftZoom" then
		local x = (zoom[1] + zoom[3]) / 2
		drag(x, zoom[2] + (zoom[4] - zoom[2]) * 0.2, 0, (zoom[4] - zoom[2]) * 0.6, "leftZoom?")
	elseif stage == "leftZoom?" and clock - stageAt > SETTLE then
		local z = measured("leftZoomUp")
		check("... a drag up its zoom rail: the distance as on the right", math.abs(z[1]) > 0.05 and z[1] * d.knobUp[1] > 0,
			said(z))
		go("end")
	elseif stage == "end" then
		local C = WG.BarDroidCamCtl
		if C then -- (the player's settings back)
			if leftWas ~= nil and C.left() ~= leftWas then
				C.setLeft(leftWas)
			end
			if d.knobWasOff then
				C.setKnob(false)
			end
			if d.railsWereOff then
				C.setRails(false)
			end
		end
		if WG.options and WG.options.isvisible and WG.options.isvisible() then
			WG.options.toggle(false)
		end
		Spring.Echo("[camctltest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
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
