-- User widget for tools/touch-widget-test.ps1: moves the pointer over BAR's real interface and reads what
-- bardroid_touch.lua answers in LuaUI/Config/bardroid_hover.txt (1 = interface: a finger drag there is a mouse drag,
-- 0 = map: a pan). Logs "[touchtest] PASS|FAIL <case>" and "[touchtest] done".
function widget:GetInfo()
	return { name = "BAR Droid touch test", desc = "Checks the touch widget's interface answers", author = "BAR Droid",
		layer = 0, enabled = true }
end

local HOVER = "LuaUI/Config/bardroid_hover.txt"
local frames, step, waitUntil = 0, 0, 0
local waitClock = 0 -- a case that returns a number: the next one waits that many seconds
-- The interface-scale case reloads LuaUI (this widget too): the second half runs after the reload ("scale" phase).
local phase = Spring.GetConfigString("bardroid_touchtest_phase", "")
local fails = Spring.GetConfigInt("bardroid_touchtest_fails", 0)

local function log(s)
	Spring.Echo("[touchtest] " .. s)
end

local function answer()
	local f = io.open(HOVER, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s and tonumber(s:match("(%d)%s*$"))
end

local function expect(case, want)
	local got = answer()
	local ok = got == want
	if not ok then
		fails = fails + 1
	end
	log((ok and "PASS " or "FAIL ") .. case .. ": answer " .. tostring(got) .. ", expected " .. want)
end

-- The checks of what is under the pointer move the laptop's real mouse pointer (Spring.WarpMouse): only with
-- tools/touch-widget-test.ps1 -Pointer (Kailil, 2026-10-28: the tests must not take his mouse while he works)
local POINTER = Spring.GetConfigInt("bardroid_touchtest_pointer", 0) == 1
local function warp(x, y)
	if POINTER then
		Spring.WarpMouse(x, y)
	end
end
local function expectAt(case, want) -- the answer for a pointer moved by warp
	if POINTER then
		expect(case, want)
	else
		log("SKIP " .. case .. " (moves the mouse pointer: tools/touch-widget-test.ps1 -Pointer)")
	end
end

local cases
local repeats = 0
local pushPointer = nil -- {x, y}: the pad widget's made-up pointer put there every frame (a stick held out)
function widget:Update()
	frames = frames + 1
	if pushPointer and WG.BarDroidPad then
		WG.BarDroidPad.setPointer(pushPointer[1], pushPointer[2])
	end
	-- (from 5 s of game: BAR's own camera move to the start position came after the first cases on a fast laptop)
	if Spring.GetGameFrame() < 150 or frames < waitUntil or os.clock() < waitClock then
		return
	end
	step = step + 1
	local c = cases[step]
	if c then
		-- (a case that errors, as one after a failed one can, is a FAIL and the next case runs: BAR's widget handler
		-- would remove this widget, and the run stopped with no "done")
		local ok, seconds = pcall(c)
		if not ok then
			fails = fails + 1
			log("FAIL case " .. step .. " errored: " .. tostring(seconds))
			seconds = nil
		end
		if seconds == false and repeats < 30 then -- not ready yet: the same case again 20 frames later
			step, repeats = step - 1, repeats + 1
		else
			repeats = 0
		end
		waitUntil = frames + 20
		waitClock = type(seconds) == "number" and os.clock() + seconds or 0
	end
end

-- A case that waits (up to ~30 x 20 frames) until nothing else moves the camera: on a slow run BAR's own move to the
-- start position still came during the drag case (the map point 528 elmos off, 2026-10-27).
local settleCam
local function settle()
	local cs = Spring.GetCameraState()
	local last = settleCam
	settleCam = cs
	if not (last and math.abs(cs.px - last.px) < 0.5 and math.abs(cs.pz - last.pz) < 0.5
		and math.abs((cs.dist or 0) - (last.dist or 0)) < 0.5 and math.abs((cs.ry or 0) - (last.ry or 0)) < 0.001) then
		return false
	end
	settleCam = nil
end

-- The app's side of the touch log: lines appended to LuaUI/Config/bardroid_touch.txt (X pixels, top-left origin).
local function touch(line)
	local f = io.open("LuaUI/Config/bardroid_touch.txt", "a")
	f:write(line .. "\n")
	f:close()
end

local function near(case, got, want, tolerance)
	local ok = got and math.abs(got - want) <= tolerance
	if not ok then
		fails = fails + 1
	end
	log((ok and "PASS " or "FAIL ") .. case .. string.format(": %s, expected %.3f +- %.3f", tostring(got), want, tolerance))
end

local function verify(case, cond, detail)
	if not cond then
		fails = fails + 1
	end
	log((cond and "PASS " or "FAIL ") .. case .. (detail and (": " .. tostring(detail)) or ""))
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function groundAt(x, y) -- bottom-left origin
	local _, pos = Spring.TraceScreenRay(x, y, true)
	return pos
end

-- bardroid_queue.lua shows the queued buildings within its radius of the camera's target, up to its maximum
local function queueCheck(where)
	local q, api = WG.bardroidQueue, WG.BuilderQueueApi
	if not (q and api) then
		fails = fails + 1
		log("FAIL builder queue (" .. where .. "): " .. (q and "no BuilderQueueApi" or "bardroid_queue.lua not running"))
		return
	end
	local cs = Spring.GetCameraState()
	local inRange = 0
	api.ForEachActiveBuildCommand(function(_, c)
		local dx, dz = c.positionX - cs.px, c.positionZ - cs.pz
		if dx * dx + dz * dz <= q.radius * q.radius then
			inRange = inRange + 1
		end
	end)
	local want = math.min(inRange, q.max)
	local ok = q.total() > 0 and q.shown() == want
	if not ok then
		fails = fails + 1
	end
	log(string.format("%s builder queue, %s: %d of %d queued buildings drawn, %d in range", ok and "PASS" or "FAIL",
		where, q.shown(), q.total(), inRange))
end

local TILT_RANGE = math.pi / 2 * 1.75 * 1.5 -- bardroid_touch.lua's
local vsx, vsy = Spring.GetViewGeometry()
local cx, cy = math.floor(vsx / 2), math.floor(vsy / 2)
local before, groundBefore, edgeView, com, minimapHeight
local padDraw = {} -- the build menu's gamepad highlight, drawn once by DrawScreen (at the end)
cases = {
	-- the same start every run (the game keeps the camera of the last one): mid-map, BAR's usual angle
	function()
		local cs = Spring.GetCameraState()
		cs.px, cs.pz, cs.dist, cs.rx, cs.ry = Game.mapSizeX / 2, Game.mapSizeZ / 2, 2500, 2.6, 0
		Spring.SetCameraState(cs, 0)
	end,
	settle,
	-- the touch camera (bardroid_touch.lua applyTouch), smoothed over ~0.05 s: 20 frames later it has arrived
	function()
		before = Spring.GetCameraState()
		touch(string.format("zoom 2.00000 %.1f %.1f", cx, cy))
	end,
	function()
		local cs = Spring.GetCameraState()
		near("pinch 2x halves the distance", cs.dist and before.dist and cs.dist / before.dist, 0.5, 0.03)
	end,
	function()
		before = Spring.GetCameraState()
		touch("rot 0.5000")
	end,
	function() near("twist 0.5 turns the camera -0.5", Spring.GetCameraState().ry - before.ry, -0.5, 0.01) end,
	function()
		before = Spring.GetCameraState()
		touch("tilt -0.0500")
	end,
	function() near("tilt -0.05 of the screen", Spring.GetCameraState().rx - before.rx, -0.05 * TILT_RANGE, 0.01) end,
	settle,
	function()
		groundBefore = groundAt(cx, cy)
		touch(string.format("pan %.1f %.1f %.1f %.1f", cx, vsy - cy, cx - 100, vsy - cy))
	end,
	function()
		local g = groundAt(cx - 100, cy)
		local miss = g and groundBefore and math.sqrt((g[1] - groundBefore[1]) ^ 2 + (g[3] - groundBefore[3]) ^ 2)
		near("drag: the map point follows the finger (elmos off)", miss, 0, 8)
	end,
	-- at the map's edge, looking out over it: a drag high on the screen (over the void) still moves the camera, and a
	-- pointer there answers "map" (taps work), now that the map-edge rules are gone (Kailil, 2026-10-27)
	function()
		local cs = Spring.GetCameraState()
		cs.px, cs.pz, cs.dist, cs.rx, cs.ry = Game.mapSizeX / 2, 200, 2500, 1.9, 0
		Spring.SetCameraState(cs, 0)
	end,
	function()
		local forward = Spring.GetCameraVectors().forward
		if forward[3] > 0 then -- looking into the map (+z): turn round to look out over the z = 0 edge
			local cs = Spring.GetCameraState()
			cs.ry = cs.ry + math.pi
			Spring.SetCameraState(cs, 0)
		end
	end,
	settle,
	function()
		local row = math.floor(vsy * 0.3) -- X pixels from the top: past the edge, below the horizon
		local _, dy = Spring.GetPixelDir(cx, vsy - row)
		edgeView = Spring.TraceScreenRay(cx, vsy - row, true) ~= "ground" and dy and dy < -0.01
		before = Spring.GetCameraState()
		touch(string.format("pan %.1f %.1f %.1f %.1f", cx, row, cx + 100, row))
	end,
	function()
		if not edgeView then
			fails = fails + 1
			log("FAIL edge setup: that row shows the map, or the sky")
			return
		end
		local cs = Spring.GetCameraState()
		local moved = math.sqrt((cs.px - before.px) ^ 2 + (cs.pz - before.pz) ^ 2)
		log(string.format("     edge drag: before %.0f,%.0f ry %.2f rx %.2f, after %.0f,%.0f", before.px, before.pz,
			before.ry, before.rx, cs.px, cs.pz))
		local ok = moved > 1
		fails = fails + (ok and 0 or 1)
		log((ok and "PASS" or "FAIL") .. " drag over the void past the edge moves the camera: " .. string.format("%.0f", moved))
		warp(cx, vsy - math.floor(vsy * 0.3)) -- the pointer into that void
	end,
	function() expectAt("pointer off the map (the void): answer 0, taps work there", 0) end,
	-- the builder queue (bardroid_queue.lua): only queued buildings near the camera's target are drawn
	function()
		local myTeam = Spring.GetMyTeamID()
		local builder = (Spring.GetTeamUnits(myTeam) or {})[1]
		local wind = UnitDefNames and UnitDefNames.armwin
		if not (builder and wind) then
			return
		end
		local x, _, z = Spring.GetUnitPosition(builder)
		for i = 1, 12 do -- around the commander, and far across the map
			local nx, nz = x + (i % 4) * 96 - 150, z + math.floor(i / 4) * 96 + 200
			Spring.GiveOrderToUnit(builder, -wind.id, { nx, Spring.GetGroundHeight(nx, nz), nz, 0 }, { "shift" })
		end
		for i = 1, 12 do
			local fx, fz = Game.mapSizeX - 600 - (i % 4) * 96, Game.mapSizeZ - 600 - math.floor(i / 4) * 96
			Spring.GiveOrderToUnit(builder, -wind.id, { fx, Spring.GetGroundHeight(fx, fz), fz, 0 }, { "shift" })
		end
		local cs = Spring.GetCameraState()
		cs.px, cs.pz, cs.dist, cs.rx = x, z, 2500, 2.6
		Spring.SetCameraState(cs, 0)
	end,
	function() end,
	function() queueCheck("camera at the commander") end,
	function()
		local cs = Spring.GetCameraState()
		cs.px, cs.pz = Game.mapSizeX - 700, Game.mapSizeZ - 700
		Spring.SetCameraState(cs, 0)
	end,
	function() queueCheck("camera at the far corner") end,
	function() -- back over the middle of the map for the cases below
		local cs = Spring.GetCameraState()
		cs.px, cs.pz = Game.mapSizeX / 2, Game.mapSizeZ / 2
		Spring.SetCameraState(cs, 0)
	end,
	-- gesture actions ("act <name>" lines: RtsTouch's two-finger hold swipes, three-finger swipes, triple tap)
	function() touch("act select_all") end,
	function()
		near("act select_all: own units selected", #Spring.GetSelectedUnits() > 0 and 1 or 0, 1, 0)
		-- the app's info panel (bardroid_info.lua, in place of BAR's Info widget) shows the selection
		local info = WG.info
		near("info panel: shows the selection", (info and info.getIsShowing and info.getIsShowing()) and 1 or 0, 1, 0)
	end,
	function() touch("act deselect") end,
	function() near("act deselect: nothing selected", #Spring.GetSelectedUnits(), 0, 0) end,
	function()
		com = (Spring.GetTeamUnits(Spring.GetMyTeamID()) or {})[1]
		Spring.SelectUnitArray({ com }) -- (the interface lists the selection's orders by the next frame)
	end,
	function() touch("act stop") end, -- the commander still has the queue above
	function() near("act stop: the selected commander's orders gone", com and Spring.GetUnitCommandCount(com), 0, 0) end,
	function()
		Spring.SelectUnitArray({})
		touch("act idle_next")
	end,
	function()
		local sel = Spring.GetSelectedUnits()
		near("act idle_next: the idle commander selected", (#sel == 1 and sel[1] == com) and 1 or 0, 1, 0)
		touch("act type_all")
	end,
	function()
		local sel, def, same = Spring.GetSelectedUnits(), com and Spring.GetUnitDefID(com), true
		for _, u in ipairs(sel) do
			same = same and Spring.GetUnitDefID(u) == def
		end
		near("act type_all: the commander's type selected", (#sel >= 1 and same) and 1 or 0, 1, 0)
	end,
	function() touch("act fight") end,
	function()
		local _, cmd = Spring.GetActiveCommand()
		if Game.gameVersion == "$VERSION" and cmd ~= CMD.FIGHT then -- the controller game clears an armed command itself
			log("     act fight: not armed after 20 frames in the controller game (v0.8.5 clears it; known)")
		else
			near("act fight: fight armed", cmd == CMD.FIGHT and 1 or 0, 1, 0)
		end
		Spring.SelectUnitArray({})
		touch("act overview_in")
	end,
	function()
		near("act overview_in: overview camera", Spring.GetCameraState().name == "ov" and 1 or 0, 1, 0)
		touch("act overview_out")
	end,
	function()
		near("act overview_out: back", Spring.GetCameraState().name ~= "ov" and 1 or 0, 1, 0)
		-- the app's pad: a mouse and keys in BAR's game, v0.8.5's in the controller game (ControllerBridge)
		local want = Game.gameVersion == "$VERSION" and "controller 1\n" or "controller 0\n"
		verify("the game told the app who has the pad", readFile("LuaUI/Config/bardroid_game.txt") == want,
			readFile("LuaUI/Config/bardroid_game.txt"))
	end,
	-- the camera's way back from the overview: still for 20 frames before the pad moves it (a fixed wait of 20 frames
	-- was sometimes too short: "sticks at rest" saw the camera 695 elmos on, 2026-10-28)
	settle,
	-- the gamepad camera (online games; ControllerBridge sends "pad" lines when the sticks change)
	function()
		before = Spring.GetCameraState()
		touch("pad 32767 0 0 0 0 0") -- left stick full right
	end,
	function() touch("pad 0 0 0 0 0 0") end,
	function()
		local cs = Spring.GetCameraState()
		local right = Spring.GetCameraVectors().right
		local dx, dz = cs.px - before.px, cs.pz - before.pz
		local along = dx * right[1] + dz * right[3]
		local len = math.sqrt(right[1] ^ 2 + right[3] ^ 2)
		if Game.gameVersion == "$VERSION" then -- the controller game: v0.8.5 reads the pad, the widget leaves it alone
			near("controller game: pad lines leave the camera alone (elmos)", math.abs(along / len), 0, 1)
		else
			near("left stick right pans to the camera's right (elmos)", along / len > 100 and 1 or 0, 1, 0)
		end
		before = cs
	end,
	function()
		local cs = Spring.GetCameraState()
		near("sticks at rest: the camera stays (elmos)", math.sqrt((cs.px - before.px) ^ 2 + (cs.pz - before.pz) ^ 2), 0, 1)
	end,
	-- the interface answers (bardroid_hover.txt)
	function() warp(math.floor(vsx * 0.5), math.floor(vsy * 0.45)) end,
	function() warp(math.floor(vsx * 0.5), math.floor(vsy * 0.45)) end,
	function() expectAt("map in the middle", 0) end,
	function()
		local p = WG.topbar and WG.topbar.GetPosition and WG.topbar.GetPosition()
		if not p then
			fails = fails + 1
			log("FAIL no WG.topbar.GetPosition")
			return
		end
		warp(math.floor((p[1] + p[3]) / 2), math.floor((p[2] + p[4]) / 2))
	end,
	function() expectAt("top bar", 1) end,
	function() -- the classic minimap (the phone layer switches BAR's Picture-in-Picture Minimap off)
		local found
		for y = 0, vsy - 1, 8 do
			for x = 0, vsx - 1, 8 do
				if not found and Spring.IsAboveMiniMap(x, y) then
					found = { x + 8, y + 8 }
				end
			end
		end
		if not found then
			fails = fails + 1
			log("FAIL no minimap on the screen")
			return
		end
		warp(found[1], found[2])
	end,
	function() expectAt("minimap", 1) end,
	function()
		if WG.options and WG.options.toggle then
			WG.options.toggle(true)
		else
			Spring.SendCommands("options")
		end
		warp(math.floor(vsx * 0.5), math.floor(vsy * 0.45))
	end,
	function() expectAt("settings window open", 1) end,
	function()
		if WG.options and WG.options.toggle then
			WG.options.toggle(false)
		end
		warp(math.floor(vsx * 0.5) + 3, math.floor(vsy * 0.45))
	end,
	function() expectAt("map after the window closed", 0) end,
	-- the app's player list (bardroid_players.lua): BAR's list small from the start, a tap on it opens it at the
	-- player's own scale, and seven seconds without a tap make it small again
	function()
		local P, a = WG.BarDroidPlayers, WG.advplayerlist_api
		near("player list: small at the start (scale)", a and P and P.minimized() and a.GetScale() or -1, 0.65, 0.001)
	end,
	function()
		local P, a = WG.BarDroidPlayers, WG.advplayerlist_api
		local pos = a and a.GetPosition()
		local taken = P and pos and P.press(math.floor((pos[2] + pos[4]) / 2), math.floor((pos[1] + pos[3]) / 2))
		near("player list: a tap on it is taken (opens it)", taken and 1 or 0, 1, 0)
	end,
	function()
		local P, a = WG.BarDroidPlayers, WG.advplayerlist_api
		near("player list: open at the player's own scale", a and P and not P.minimized() and a.GetScale() or -1, 1, 0.001)
		return 8
	end,
	function()
		local P = WG.BarDroidPlayers
		near("player list: small again after 7 s untouched", P and P.minimized() and 1 or 0, 1, 0)
	end,
	-- the app's minimap (bardroid_minimap.lua): BAR's size on a wide screen; unfolded (here: told so) about half until
	-- a tap, which only opens it; seven seconds without a tap make it small again
	function()
		local M = WG.BarDroidMinimap
		minimapHeight = WG.minimap and WG.minimap.getHeight()
		near("minimap: BAR's own size on the wide screen", M and not M.small() and 1 or 0, 1, 0)
		if M then
			M.setUnfolded(true)
		end
	end,
	function() return 1 end, -- (BAR's Minimap reads the size four times a second)
	function()
		local M, h = WG.BarDroidMinimap, WG.minimap and WG.minimap.getHeight()
		near("minimap unfolded: small", M and M.small() and 1 or 0, 1, 0)
		near("minimap unfolded: about half its height", (h and minimapHeight) and h / minimapHeight or -1, 0.5, 0.1)
	end,
	function()
		local M, at = WG.BarDroidMinimap, nil
		for y = 0, vsy - 1, 4 do
			for x = 0, vsx - 1, 4 do
				if not at and Spring.IsAboveMiniMap(x, y) then
					at = { x + 4, y + 4 }
				end
			end
		end
		near("minimap unfolded: a tap on it is taken (opens it)", (M and at and M.press(at[1], at[2])) and 1 or 0, 1, 0)
		return 1
	end,
	function()
		local M, h = WG.BarDroidMinimap, WG.minimap and WG.minimap.getHeight()
		near("minimap unfolded: open at BAR's own size", (M and not M.small() and h and minimapHeight) and h / minimapHeight or -1,
			1, 0.02)
		return 8
	end,
	function()
		local M = WG.BarDroidMinimap
		near("minimap unfolded: small again after 7 s untouched", M and M.small() and 1 or 0, 1, 0)
		if M then
			M.setUnfolded(false)
		end
	end,
	function() return 1 end,
	function()
		local M, h = WG.BarDroidMinimap, WG.minimap and WG.minimap.getHeight()
		near("minimap folded again: BAR's own size", (M and not M.small() and h and minimapHeight) and h / minimapHeight or -1, 1,
			0.02)
		if M then
			M.setUnfolded(nil)
		end
		-- the player sets another size in BAR's settings: it stays (the widget's overlay from before must not hide it)
		before = WG.minimap and select(2, WG.minimap.getMaxHeight())
		if WG.minimap and WG.minimap.setMaxHeight then
			WG.minimap.setMaxHeight(0.2)
		end
		return 1
	end,
	function()
		near("minimap: a size set in BAR's settings stays", WG.minimap and select(2, WG.minimap.getMaxHeight()) or -1, 0.2,
			0.0001)
		if WG.minimap and WG.minimap.setMaxHeight and before then
			WG.minimap.setMaxHeight(before)
		end
	end,
	-- the app's chat display (bardroid_chat.lua): BAR's chat hands it each line it parsed
	function()
		before = WG.bardroidChat and WG.bardroidChat.lines()
		Spring.SendCommands("say touch test chat line")
	end,
	function()
		local now = WG.bardroidChat and WG.bardroidChat.lines()
		near("chat: a said line reaches BAR Droid chat", (before and now) and now - before or -1, 1, 0)
	end,
	-- the app's typing box (bardroid_chat.lua): Enter opens it (allies, playing), a long message wraps and gets smaller,
	-- Backspace, Escape; a message sent reaches the chat; "/hud" opens the layout editor
	function()
		local C = WG.bardroidChat
		local taken = C and C.widget:KeyPress(13, {})
		local t = C and C.typing()
		verify("typing: Enter opens the app's box (allies)", taken and t and t.mode == "a:", t and t.mode)
		verify("typing: BAR's own box stays closed", not (WG.chat and WG.chat.isInputActive()))
		-- the box owns the keys (BAR's hotkeys run before widgets hear a key): BAR's chat, asked for a map marker's box
		-- now, says no as it does whenever another widget has them
		verify("typing: the box owns the keys", WG.chat and WG.chat.startMapmarkInput
			and WG.chat.startMapmarkInput(100, 0, 100) == false)
		for _ = 1, 12 do
			C.widget:TextInput("wrapping ")
		end
		C.widget:TextInput("end")
	end,
	function()
		local C = WG.bardroidChat
		local t = C.typing()
		local left, top, right = C.box()
		verify("typing: a long message wraps into lines (smaller only past two)", t and t.lines >= 2
			and (t.lines <= 2) == (t.size == t.base), t and string.format("%d lines, size %.1f of %.1f", t.lines, t.size, t.base))
		verify("typing: the box at the top of the chat box, as wide", t and t.x0 == left and t.x1 == right and t.y1 == top,
			t and string.format("box %d-%d top %d, chat %d-%d top %d", t.x0, t.x1, t.y1, left, right, top))
		C.widget:KeyPress(8, {}) -- Backspace
		C.widget:KeyPress(8, {})
		t = C.typing()
		verify("typing: Backspace", t and t.text:sub(-2) == " e", t and t.text:sub(-6))
		C.widget:KeyPress(27, {}) -- Escape
		verify("typing: Escape closes it", C.typing() == nil)
		before = C.lines()
		C.widget:KeyPress(13, {})
		C.widget:TextInput("touch test typed line")
		C.widget:KeyPress(13, {})
		verify("typing: Enter sends and closes", C.typing() == nil)
		return 1
	end,
	function()
		local C = WG.bardroidChat
		near("typing: the message sent reaches the chat", C.lines() - before, 1, 0)
		C.widget:KeyPress(13, {})
		C.widget:TextInput("/hud")
		C.widget:KeyPress(13, {})
		verify("layout: /hud in the chat opens the editor", WG.BarDroidLayout and WG.BarDroidLayout.isOpen())
		verify("layout: the editor owns the keys while open", WG.BarDroidLayout and WG.BarDroidLayout.ownsText())
	end,
	-- the layout editor (bardroid_layout.lua): a tap picks a panel, a drag moves it, the buttons size it; BAR's panels
	-- only as far as BAR lets (the player list's and the minimap's size); Reset all, Done
	function()
		local L, C = WG.BarDroidLayout, WG.bardroidChat
		local ids = table.concat(L.ids(), " ")
		verify("layout: the panels known", ids:find("chat") and ids:find("info") and ids:find("players") and ids:find("minimap")
			and ids:find("topbar"), ids)
		local x0, y0, x1, y1 = L.rect("chat")
		local left, top = C.box()
		before = { left = left, top = top }
		local px, py = math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2)
		L.press(px, py)
		verify("layout: a tap picks the chat", L.picked() == "chat", L.picked())
		L.move(px + 100, py - 50)
		L.release()
		left, top = C.box()
		verify("layout: a drag moves the chat box", math.abs(left - before.left - 100) <= 2 and math.abs(top - before.top + 50) <= 2,
			string.format("left %d -> %d, top %d -> %d", before.left, left, before.top, top))
		local _, _, right, _, lineHeight = C.box()
		before.width, before.lineHeight = right - left, lineHeight
		L.act("size+")
		L.act("text+")
	end,
	function()
		-- (a screenshot is of the frame drawn last: the editor with the chat picked; build\touch-widget-test\data\screenshots)
		Spring.SendCommands("screenshot png")
		local C = WG.bardroidChat
		local left, _, right, _, lineHeight = C.box()
		near("layout: Size + widens the chat box", (right - left) / before.width, 1.08, 0.02)
		verify("layout: Text + makes the chat's text bigger", lineHeight > before.lineHeight,
			string.format("line height %d -> %d", before.lineHeight, lineHeight))
		local L = WG.BarDroidLayout
		-- twice the text: the longest message takes more than two lines, and the typing gets smaller
		for _ = 1, 8 do
			L.act("text+")
		end
		verify("typing: no box while the editor has the keys", not C.widget:KeyPress(13, {}) and C.typing() == nil)
		L.close()
		C.widget:KeyPress(13, {})
		for _ = 1, 14 do
			C.widget:TextInput("wrapping ")
		end
		local t = C.typing()
		verify("typing: past two lines the text gets smaller", t and t.lines >= 3 and t.size < t.base,
			t and string.format("%d lines, size %.1f of %.1f", t.lines, t.size, t.base))
		C.widget:KeyPress(27, {})
		L.open()
		local x0, y0, x1, y1 = L.rect("info")
		before.infoW = x1 - x0
		L.press(math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2))
		verify("layout: a tap picks the unit info panel", L.picked() == "info", L.picked())
		L.act("size+")
		local ix0, _, ix1 = L.rect("info")
		near("layout: Size + makes the unit info panel bigger", (ix1 - ix0) / before.infoW, 1.08, 0.02)
		local a = WG.advplayerlist_api
		x0, y0, x1, y1 = L.rect("players")
		before.scale = a.GetScale()
		L.press(math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2))
		verify("layout: a tap picks the player list", L.picked() == "players", L.picked())
		L.act("size+")
		near("layout: Size + scales BAR's player list", a.GetScale() / before.scale, 1.08, 0.01)
		x0, y0, x1, y1 = L.rect("minimap")
		before.minimap = WG.minimap and select(2, WG.minimap.getMaxHeight())
		L.press(math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2))
		verify("layout: a tap picks the minimap", L.picked() == "minimap", L.picked())
		L.act("size+")
		x0, y0, x1, y1 = L.rect("topbar")
		L.press(math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2))
		local fixed = false
		for _, b in ipairs(L.buttons()) do
			fixed = fixed or b.label == "BAR has no setting for it"
		end
		verify("layout: BAR's top bar picked, shown as fixed", L.picked() == "topbar" and fixed, L.picked())
		return 1
	end,
	function()
		local L = WG.BarDroidLayout
		near("layout: Size + makes BAR's minimap bigger (its max height)", WG.minimap and select(2, WG.minimap.getMaxHeight())
			/ before.minimap or -1, 1.08, 0.01)
		L.act("resetall")
		local C, a = WG.bardroidChat, WG.advplayerlist_api
		local left, top = C.box()
		verify("layout: Reset all puts the chat back", left == before.left and top == before.top,
			string.format("left %d, top %d", left, top))
		near("layout: Reset all puts the player list's size back", a.GetScale(), before.scale, 0.001)
		L.act("done")
		verify("layout: Done closes the editor", not L.isOpen())
		touch("act hud") -- three fingers held (RtsTouch)
		return 1
	end,
	function()
		local L = WG.BarDroidLayout
		verify("layout: three fingers held open the editor", L.isOpen())
		touch("act hud")
		return 1
	end,
	function()
		verify("layout: three fingers held again close it", not WG.BarDroidLayout.isOpen())
		near("layout: Reset all puts the minimap's size back", WG.minimap and select(2, WG.minimap.getMaxHeight()) or -1,
			before.minimap, 0.0001)
		-- the build menu: in BAR's released game the app's copy of BAR's Build menu (bardroid_buildmenu.lua), which the
		-- editor moves and sizes; in the controller game v0.8.5's own (the copy beside it, hidden until the app's controls
		-- have the pad). A builder selected shows it.
		for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			if def and def.isBuilder and (def.speed or 0) > 0 then
				Spring.SelectUnitArray({ unitID })
				break
			end
		end
		return 1.5
	end,
	function()
		Spring.SendCommands("screenshot png") -- the build menu for a builder (build\touch-widget-test\data\screenshots)
		local B, L = WG.buildmenu, WG.BarDroidLayout
		verify("build menu: shows for a builder", B and B.getIsShowing and B.getIsShowing())
		if B and B.controllerApiVersion then
			verify("build menu: the controller game's own (the app's copy hidden beside it)",
				WG.bardroidBuildmenu ~= nil and not WG.bardroidBuildmenu.getIsShowing())
			-- the triple tap (GameActivity): the pad to the app's controls, the camera with it
			before.ctl = Spring.GetCameraState()
			touch("act mod_bardroid")
			touch("pad 32767 0 0 0 0 0")
			return 0.3
		end
		local x0, y0, x1, y1 = L.rect("buildmenu")
		verify("build menu: the app's copy, known to the editor", x0 ~= nil, x0 and string.format("%d,%d-%d,%d", x0, y0, x1, y1))
		if not x0 then
			return
		end
		before.ctl = nil
		before.bm = { x0 = x0, y0 = y0, w = x1 - x0, h = y1 - y0 }
		-- a 3 x 3 grid, the page arrows in a strip under it (Kailil: "3x3 items on top of the left and right and page
		-- indicator", the strip half a cell high): 9 options a page
		local colls, rows, pages, count = B.droidGrid()
		verify("build menu: 3 x 3 options a page, the arrows in a strip under them", colls == 3 and rows == 3
			and pages == math.max(1, math.ceil(count / 9)),
			string.format("%s x %s, %s pages for %s options", tostring(colls), tostring(rows), tostring(pages), tostring(count)))
		-- (Kailil: "increase the total height of the build menu to allow the pictures to fill their squares": three
		-- pictures across the menu, three rows and half a row's strip high)
		near("build menu: 3 rows and the strip tall, 3 pictures wide", (y1 - y0) / (x1 - x0), 3.5 / 3, 0.06)
		L.open()
		local px, py = math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2)
		L.press(px, py)
		verify("build menu: a tap picks it", L.picked() == "buildmenu", L.picked())
		L.act("size-")
		L.act("size-")
		L.move(px + 60, py + 40)
		L.release()
		return 0.5
	end,
	-- the controller game: switched to the app's controls (a triple tap), the app's 3x3 build menu in place of v0.8.5's
	-- (Kailil: "What happened to my 3x3 build menu grid? its gone"), RB puts the pointer on it as in BAR's game
	function()
		if not before.ctl then
			return
		end
		touch("pad 0 0 0 0 0 0")
		local cs = Spring.GetCameraState()
		-- (the last note shown: at a few frames a second the 1.3 s note has faded by the next case)
		verify("controller game switched: the note", select(2, WG.BarDroidPad.note()) == "CONTROLLER MOD: BAR DROID",
			select(2, WG.BarDroidPad.note()))
		verify("controller game switched: the pad moves the camera",
			math.sqrt((cs.px - before.ctl.px) ^ 2 + (cs.pz - before.ctl.pz) ^ 2) > 50)
		verify("controller game: v0.8.5's build menu kept in BAR's place", WG.buildmenu and WG.buildmenu.controllerApiVersion
			and WG.bardroidBuildmenu and WG.bardroidBuildmenu ~= WG.buildmenu)
		before.warps = {}
		if not POINTER then
			WG.bardroidBuildmenu.droidSetWarp(function(x, y)
				before.warps[#before.warps + 1] = { x, y }
			end)
		end
		touch("act pad_build")
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		local B = WG.buildmenu
		verify("controller game switched: v0.8.5's build menu panel hidden", B.controllerGetPanelVisible() == false)
		verify("controller game switched: the app's 3x3 menu shows", WG.bardroidBuildmenu.getIsShowing())
		local _, _, pages = WG.bardroidBuildmenu.droidGrid()
		local focus, page = WG.bardroidBuildmenu.droidFocus()
		verify("controller game: RB puts the app's build menu on the pad, the pointer onto it", focus ~= nil
			and (POINTER or #before.warps >= 1) and (readFile("LuaUI/Config/bardroid_pad.txt") or ""):find("^focus build\n"),
			readFile("LuaUI/Config/bardroid_pad.txt"))
		before.ctlFocus, before.ctlPage, before.ctlPages = focus, page, pages
		touch("act pad_page_next") -- (RB on the menu)
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		local focus, page = WG.bardroidBuildmenu.droidFocus()
		verify("controller game: RB on the menu turns the page", before.ctlPages < 2 or (page == before.ctlPage % before.ctlPages + 1
			and focus ~= before.ctlFocus), tostring(before.ctlPage) .. " -> " .. tostring(page))
		touch("act pad_page_prev") -- (LB on the menu)
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		local focus, page = WG.bardroidBuildmenu.droidFocus()
		verify("controller game: LB on the menu turns it back", page == before.ctlPage and focus == before.ctlFocus,
			tostring(page) .. ", " .. tostring(focus))
		touch("act pad_back")
		-- Back + RB there: v0.8.5's order menu (BAR's of the release it was ported to, with v0.8.5's edits); the cells as
		-- bardroid_pad.lua works them out drawn over its buttons for the screenshot
		if not POINTER then
			WG.BarDroidPad.setWarp(function() end)
		end
		touch("act pad_orders")
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		local cmdID, index, count = WG.BarDroidPad.orders()
		verify("controller game: Back + RB puts v0.8.5's order menu's first order on the pad", cmdID and index == 1 and count > 1,
			string.format("%s, %s of %s", tostring(cmdID), tostring(index), tostring(count)))
		local cells, cmds = WG.BarDroidPad.ordersCells()
		padDraw.cells, padDraw.count = cells, cmds and #cmds or 0
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		Spring.SendCommands("screenshot png") -- (build\touch-widget-test\data\screenshots: each outline on one of its buttons)
		padDraw.cells = nil
		touch("act pad_back")
		WG.BarDroidPad.setWarp(nil)
		touch("act mod_v085")
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		verify("controller game switched back: the note", select(2, WG.BarDroidPad.note()) == "CONTROLLER MOD: v0.8.5",
			select(2, WG.BarDroidPad.note()))
		verify("controller game switched back: v0.8.5's panel again, the app's menu hidden",
			WG.buildmenu.controllerGetPanelVisible() == true and not WG.bardroidBuildmenu.getIsShowing())
		verify("controller game switched back: the layout editor has no outline for the hidden menu",
			WG.BarDroidLayout.rect("buildmenu") == nil)
		WG.bardroidBuildmenu.droidSetWarp(nil)
		-- touch building with v0.8.5's controls on (Kailil: the PLACE button "not even putting the place box over the
		-- orders box"): a building picked from v0.8.5's menu, PLACE over the order menu all the same
		for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do
			if cmd.id < 0 then
				Spring.SetActiveCommand(Spring.GetCmdDescIndex(cmd.id))
				break
			end
		end
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		local panel = WG.bardroidBuildmenu.droidPanel()
		local text = readFile("LuaUI/Config/bardroid_place.txt") or ""
		verify("controller game, v0.8.5's controls: a building picked shows PLACE and tells the app",
			panel ~= nil and text:match("^place one\ndone %d+ %d+ %d+ %d+\n"), text)
		touch("act cancel")
		Spring.SelectUnitArray({})
		return 1.5 -- (the note gone)
	end,
	-- the app tells its mode again every 2 s (a LuaUI reload, as a fold makes, starts the widgets with v0.8.5's): the
	-- same mode again changes nothing and shows no note
	function()
		if not before.ctl then
			return
		end
		touch("act mod_bardroid") -- (a change: the note)
		return 1.6
	end,
	function()
		if not before.ctl then
			return
		end
		local showing, last, count = WG.BarDroidPad.note()
		before.notes = count
		verify("controller game: the switch noted, the note faded after 1.3 s", last == "CONTROLLER MOD: BAR DROID"
			and showing == nil, tostring(last) .. ", " .. tostring(showing))
		touch("act mod_bardroid") -- (the same mode again, as the app's resend)
		return 0.3
	end,
	function()
		if not before.ctl then
			return
		end
		local _, last, count = WG.BarDroidPad.note()
		verify("controller game: the app's mode told again shows no second note", count == before.notes,
			tostring(before.notes) .. " -> " .. tostring(count) .. " (" .. tostring(last) .. ")")
		verify("controller game: ... and the app's menu still in place", WG.BarDroidOwnsBuildMenu == true)
		touch("act mod_v085")
	end,
	function()
		if not before.bm then
			return
		end
		local L = WG.BarDroidLayout
		local x0, y0, x1 = L.rect("buildmenu")
		near("build menu: Size - twice makes it smaller", (x1 - x0) / before.bm.w, 1 / 1.08 / 1.08, 0.02)
		verify("build menu: a drag moves it", math.abs(x0 - before.bm.x0 - 60) <= 2 and math.abs(y0 - before.bm.y0 - 40) <= 2,
			string.format("%d,%d -> %d,%d", before.bm.x0, before.bm.y0, x0, y0))
		verify("build menu: still showing", WG.buildmenu.getIsShowing())
		L.act("reset")
		local y1
		x0, y0, x1, y1 = L.rect("buildmenu")
		verify("build menu: Reset puts it back", x0 == before.bm.x0 and y0 == before.bm.y0 and x1 - x0 == before.bm.w,
			string.format("%d,%d %dx%d", x0, y0, x1 - x0, y1 - y0))
		L.act("done")
		-- touch building (Kailil, 2026-10-28): a building picked turns the page strip into ONE . LINE . GRID . BORDER and
		-- lays a big green PLACE button with rotate and cancel over the order menu; a tap on the map picks the spot,
		-- PLACE builds there. What the app needs goes to RtsTouch in bardroid_place.txt
		for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do
			if cmd.id < 0 then
				Spring.SetActiveCommand(Spring.GetCmdDescIndex(cmd.id))
				break
			end
		end
		return 0.5
	end,
	function()
		if not before.bm then
			return
		end
		local armed, shape, rects = WG.bardroidBuildmenu.droidPlace()
		verify("build menu: a building picked shows the shape strip", armed and #rects == 4,
			string.format("%s, %d buttons", tostring(armed), #rects))
		verify("build menu: ONE to start", shape == "one", shape)
		local text = readFile("LuaUI/Config/bardroid_place.txt") or ""
		verify("build menu: the app told the shape and the PLACE button", text:match("^place one\ndone %d+ %d+ %d+ %d+\n$"),
			text)
		local panel = WG.bardroidBuildmenu.droidPanel()
		local o = WG.ordermenu
		if panel and o and o.getPosition and o.getIsShowing() then -- (as the layout editor finds the order menu)
			local x, y, w = o.getPosition()
			verify("build menu: PLACE lies over the order menu", math.abs(panel.all[1] - x * vsx) <= 1
				and math.abs(panel.all[3] - (x + w) * vsx) <= 1 and math.abs(panel.all[4] - y * vsy) <= 1,
				string.format("%d,%d-%d,%d", panel.all[1], panel.all[2], panel.all[3], panel.all[4]))
		end
		before.facing = Spring.GetBuildFacing()
		for _, r in ipairs(rects) do
			if r[5] == "grid" then
				verify("build menu: GRID tapped", WG.bardroidBuildmenu.droidPress((r[1] + r[3]) / 2, (r[2] + r[4]) / 2))
			end
		end
		if panel then
			local r = panel.rotate
			verify("build menu: rotate inside PLACE", WG.bardroidBuildmenu.droidPressPanel((r[1] + r[3]) / 2, (r[2] + r[4]) / 2))
		end
		-- a tap on the middle of the map (RtsTouch: "spot <x> <y>", X screen pixels)
		touch(string.format("spot %d %d", cx, cy))
		return 0.5
	end,
	function()
		if not before.bm then
			return
		end
		Spring.SendCommands("screenshot png") -- the strip, PLACE and the spot (build\touch-widget-test\data\screenshots)
		local armed, shape = WG.bardroidBuildmenu.droidPlace()
		local _, spot = WG.bardroidBuildmenu.droidPanel()
		verify("build menu: GRID chosen", armed and shape == "grid", shape)
		verify("build menu: rotate turns the building", Spring.GetBuildFacing() == (before.facing + 1) % 4,
			before.facing .. " -> " .. Spring.GetBuildFacing())
		verify("build menu: a tap on the map picks the spot", spot ~= nil)
		local text = readFile("LuaUI/Config/bardroid_place.txt") or ""
		verify("build menu: the app told GRID, PLACE and the spot",
			text:match("^place grid\ndone %d+ %d+ %d+ %d+\nspot %d+ %d+\n$"), text)
		-- a spot that lies under the menu (the camera moved): PLACE would click the menu, so the app is told none
		local b = before.bm
		touch(string.format("spot %d %d", b.x0 + b.w / 2, vsy - (b.y0 + b.h / 2) - 1))
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local panel, spot = WG.bardroidBuildmenu.droidPanel()
		local text = readFile("LuaUI/Config/bardroid_place.txt") or ""
		verify("build menu: a spot under the menu is not told to the app", spot ~= nil and not text:find("spot"), text)
		touch("spot none") -- (RtsTouch after PLACE)
		if panel then
			local r = panel.cancel
			WG.bardroidBuildmenu.droidPressPanel((r[1] + r[3]) / 2, (r[2] + r[4]) / 2)
		end
		return 0.5
	end,
	function()
		if not before.bm then
			return
		end
		local _, id = Spring.GetActiveCommand()
		local armed, shape = WG.bardroidBuildmenu.droidPlace()
		local panel, spot = WG.bardroidBuildmenu.droidPanel()
		verify("build menu: cancel puts the building away", not armed and (id == nil or id >= 0), tostring(id))
		verify("build menu: no PLACE and no spot after", panel == nil and spot == nil)
		verify("build menu: the next building starts with ONE", shape == "one", shape)
		verify("build menu: the app told none", readFile("LuaUI/Config/bardroid_place.txt") == "place none\n")
		-- the gamepad (Kailil: v0.8.5's feel): RB puts the pointer on the menu's first option, the D-pad steps through
		-- them, picking one lets go of the menu (the app glides the pointer back to the middle). Pointer moves
		-- recorded, not made, unless -Pointer.
		before.warps = {}
		if not POINTER then
			WG.bardroidBuildmenu.droidSetWarp(function(x, y)
				before.warps[#before.warps + 1] = { x, y }
			end)
		end
		touch("act pad_build")
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local focus, page = WG.bardroidBuildmenu.droidFocus()
		before.first = (page - 1) * 9 + 1
		verify("pad: RB puts the menu's first option on the pad", focus == before.first,
			tostring(focus) .. " on page " .. tostring(page))
		verify("pad: the app told the focus", readFile("LuaUI/Config/bardroid_pad.txt") == "focus build\npregame 0\narmed none\n",
			readFile("LuaUI/Config/bardroid_pad.txt"))
		verify("pad: the pointer went onto it", POINTER or #before.warps >= 1)
		padDraw.cell = before.first -- (DrawScreen below: the focused option drawn bigger and outlined)
		touch("act pad_right") -- (quick presses, one frame: each from the last one's option, not the pointer's)
		touch("act pad_right")
		touch("act pad_down")
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		verify("pad: the option drawn bigger and outlined", padDraw.ok, padDraw.err)
		local focus = WG.bardroidBuildmenu.droidFocus()
		verify("pad: D-pad right, right, down: the right column, a row down", focus == before.first + 5, tostring(focus))
		touch("act pad_left")
		touch("act pad_left")
		touch("act pad_left") -- (past the left edge: the page before; from the first, the last)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local focus, page = WG.bardroidBuildmenu.droidFocus()
		local _, _, pages, count = WG.bardroidBuildmenu.droidGrid()
		local want = math.min(count, (pages - 1) * 9 + 3 + 2 + 1)
		verify("pad: past the left edge, the page before (the last), its right column", page == pages and focus == want,
			string.format("%s on page %s (want %d on %d)", tostring(focus), tostring(page), want, pages))
		before.pageFocus = focus
		touch("act pad_page_next") -- (RB on the menu, Kailil: "pressing RB or LB cycles the tabs"; from the last, the first)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local focus, page = WG.bardroidBuildmenu.droidFocus()
		verify("pad: RB on the menu: the next page (from the last, the first), the same place", page == 1
			and focus == before.pageFocus - (select(3, WG.bardroidBuildmenu.droidGrid()) - 1) * 9,
			string.format("%s on page %s", tostring(focus), tostring(page)))
		touch("act pad_page_prev")
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local focus = WG.bardroidBuildmenu.droidFocus()
		verify("pad: LB on the menu: the page before (the last again)", focus == before.pageFocus, tostring(focus))
		touch("act pad_down") -- (the last page's bottom row: its last option when the row is not full)
		touch("act pad_down")
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		before.bottom = WG.bardroidBuildmenu.droidFocus()
		touch("act pad_right")
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		-- right from there: the next option, or past the row's or the menu's end the next page (from the last, the
		-- first), the same row's first option (it stayed on the last option)
		local focus, page = WG.bardroidBuildmenu.droidFocus()
		local _, _, pages, count = WG.bardroidBuildmenu.droidGrid()
		local i = before.bottom - (pages - 1) * 9 - 1
		local row, col = math.floor(i / 3), i % 3
		local past = col == 2 or before.bottom == count
		local want = past and math.min(count, row * 3 + 1) or before.bottom + 1
		verify("pad: D-pad right from the last page's last option goes on (the first page)", focus == want
			and page == (past and 1 or pages), string.format("%s -> %s on page %s (want %d)", tostring(before.bottom),
			tostring(focus), tostring(page), want))
		before.warps = {}
		for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do -- (A on it: BAR's own menu picks it)
			if cmd.id < 0 then
				Spring.SetActiveCommand(Spring.GetCmdDescIndex(cmd.id))
				break
			end
		end
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		verify("pad: a building picked off the menu lets go of the menu", WG.bardroidBuildmenu.droidFocus() == nil)
		verify("pad: the app told the focus is over, a building picked",
			readFile("LuaUI/Config/bardroid_pad.txt") == "focus none\npregame 0\narmed build\n",
			readFile("LuaUI/Config/bardroid_pad.txt"))
		before.facing = Spring.GetBuildFacing()
		touch("act rotate_right") -- (the D-pad while a building is picked)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		verify("pad: D-pad right turns the building", Spring.GetBuildFacing() == (before.facing + 1) % 4,
			before.facing .. " -> " .. Spring.GetBuildFacing())
		touch("act cancel") -- (B: the building put away)
		WG.bardroidBuildmenu.droidSetWarp(nil)
		-- the order menu on the pad (Back + RB; bardroid_pad.lua)
		if not POINTER then
			WG.BarDroidPad.setWarp(function(x, y)
				before.warps[#before.warps + 1] = { x, y }
			end)
		end
		before.warps = {}
		touch("act pad_orders")
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local _, active = Spring.GetActiveCommand()
		verify("pad: B puts the picked building away", active == nil, tostring(active))
		local cmdID, index, count = WG.BarDroidPad.orders()
		verify("pad: Back + RB puts the order menu's first order on the pad", cmdID and index == 1 and count > 1,
			string.format("%s, %s of %s", tostring(cmdID), tostring(index), tostring(count)))
		local w = before.warps[1]
		local o = WG.ordermenu
		if w and o then -- (the pointer onto the order menu)
			local x, y, width, height = o.getPosition()
			verify("pad: the pointer went onto the order menu", w[1] >= x * vsx and w[1] <= (x + width) * vsx
				and w[2] >= (y - height) * vsy and w[2] <= y * vsy, w[1] .. "," .. w[2])
		end
		verify("pad: the app told the order menu's focus", (readFile("LuaUI/Config/bardroid_pad.txt") or ""):find("^focus orders\n"))
		touch("act pad_right")
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local _, index = WG.BarDroidPad.orders()
		verify("pad: D-pad right: the next order", index == 2, tostring(index))
		-- the order menu's cells as bardroid_pad.lua works them out, drawn over BAR's buttons for the screenshot
		-- (build\touch-widget-test\data\screenshots: each outline should sit on one of BAR's buttons)
		local cells, cmds = WG.BarDroidPad.ordersCells()
		padDraw.cells, padDraw.count = cells, cmds and #cmds or 0
		verify("pad: Move is on the order menu", WG.BarDroidPad.ordersOn(CMD.MOVE))
		touch("act pad_select") -- (A: Move needs a target: picked, the pointer back to the middle)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		Spring.SendCommands("screenshot png") -- (the cells drawn in the frames before)
		padDraw.cells = nil
		local _, active = Spring.GetActiveCommand()
		verify("pad: A on Move picks it and leaves the menu", active == CMD.MOVE and WG.BarDroidPad.orders() == nil,
			tostring(active))
		verify("pad: the app told an order is picked", (readFile("LuaUI/Config/bardroid_pad.txt") or ""):find("armed other\n", 1, true))
		touch("act cancel") -- (B: the order put away)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local _, active = Spring.GetActiveCommand()
		verify("pad: B puts the order away", active == nil, tostring(active))
		-- the order menu follows the pointer (here a made-up one the recorded moves land on): onto another order; pushed
		-- off the menu it is held on it; pushed off for 0.25 s it lets go (Kailil: "a quarter long")
		if not POINTER then
			WG.BarDroidPad.setPointer(0, 0)
			touch("act pad_orders")
		end
		return 0.3
	end,
	function()
		if not before.bm or POINTER then
			return
		end
		local cells, cmds = WG.BarDroidPad.ordersCells()
		local _, index = WG.BarDroidPad.orders()
		verify("pad: the order menu on the pad again, on its first order", index == 1, tostring(index))
		local r = cells and cmds and #cmds >= 3 and cells[3]
		if r then -- (the left stick takes the pointer onto the 3rd order)
			before.third = cmds[3].id
			WG.BarDroidPad.setPointer(math.floor((r[1] + r[3]) / 2), math.floor((r[2] + r[4]) / 2))
		end
		return 0.3
	end,
	function()
		if not before.bm or POINTER then
			return
		end
		local cmdID, index = WG.BarDroidPad.orders()
		verify("pad: the order menu follows the pointer onto another order", index == 3 and cmdID == before.third,
			tostring(index))
		local cells = WG.BarDroidPad.ordersCells()
		before.menuLeft = cells and cells[1][1]
		before.warps = {}
		if cells then -- (pushed off the menu's left edge once)
			WG.BarDroidPad.setPointer(cells[1][1] - 150, math.floor((cells[1][2] + cells[1][4]) / 2))
		end
		return 0.3
	end,
	function()
		if not before.bm or POINTER then
			return
		end
		local w = before.warps[#before.warps]
		verify("pad: pushed off the order menu once, the pointer held on it", WG.BarDroidPad.orders() ~= nil
			and w and before.menuLeft and w[1] >= before.menuLeft, w and (w[1] .. "," .. w[2]))
		local cells = WG.BarDroidPad.ordersCells()
		if cells then -- (pushed off it every frame: the stick held out)
			pushPointer = { cells[1][1] - 150, math.floor((cells[1][2] + cells[1][4]) / 2) }
		end
		return 0.6
	end,
	function()
		if not before.bm or POINTER then
			return
		end
		pushPointer = nil
		verify("pad: pushed off the order menu for 0.25 s, the menu let go", WG.BarDroidPad.orders() == nil)
		WG.BarDroidPad.setPointer(nil)
	end,
	function()
		if not before.bm then
			return
		end
		before.units = Spring.GetSelectedUnits()
		touch("act group_assign_3") -- (Start + D-pad left held)
		touch("act cancel") -- (B again: nothing picked, the selection cleared)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		verify("pad: B with nothing picked clears the selection", #Spring.GetSelectedUnits() == 0)
		touch("act group_recall_3") -- (Start + D-pad left tapped)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local sel = Spring.GetSelectedUnits()
		verify("pad: a control group set and recalled", #sel == #before.units and sel[1] == before.units[1],
			#sel .. " of " .. #before.units)
		Spring.SelectUnitArray({})
		touch("act commander") -- (D-pad down)
		return 0.3
	end,
	function()
		if not before.bm then
			return
		end
		local sel = Spring.GetSelectedUnits()
		local def = sel[1] and UnitDefs[Spring.GetUnitDefID(sel[1])]
		verify("pad: D-pad down selects the commander", def and def.customParams.iscommander, def and def.name)
		before.com = sel[1]
		if sel[1] then -- two orders queued, then R3: the last one removed (where unit control is allowed, as here)
			-- (behind a WAIT, so they are still queued however long the next steps take: at 5 fps the commander walked
			-- both moves before R3 came)
			local x, y, z = Spring.GetUnitPosition(sel[1])
			Spring.GiveOrderToUnit(sel[1], CMD.STOP, {}, 0)
			Spring.GiveOrderToUnit(sel[1], CMD.WAIT, {}, 0)
			Spring.GiveOrderToUnit(sel[1], CMD.MOVE, { x + 100, y, z }, { "shift" })
			Spring.GiveOrderToUnit(sel[1], CMD.MOVE, { x + 200, y, z }, { "shift" })
		end
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		before.queued = Spring.GetUnitCommandCount(before.com)
		local queue = Spring.GetUnitCommands(before.com, -1) or {}
		before.lastQueued = queue[#queue] and queue[#queue].params[1]
		touch("act queue_remove_last")
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		local queue = Spring.GetUnitCommands(before.com, -1) or {}
		local last = queue[#queue] and queue[#queue].params[1]
		verify("pad: R3 removes the last queued order", before.queued == 3 and #queue == 2 and last ~= before.lastQueued,
			before.queued .. " -> " .. #queue)
		touch("act lb_b") -- (LB + B: stop)
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		verify("pad: LB + B stops", Spring.GetUnitCommandCount(before.com) == 0, Spring.GetUnitCommandCount(before.com))
		WG.BarDroidPad.setWarp(nil)
		Spring.SelectUnitArray({})
		-- v0.8.5's area select (A held with nothing picked): the commander in the middle of the screen
		local x, y, z = Spring.GetUnitPosition(before.com)
		Spring.SetCameraTarget(x, y, z, 0)
		return 0.5
	end,
	function()
		if not before.com then
			return
		end
		touch("act area_on")
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		local on, radius, count = WG.BarDroidPad.area()
		local sel = Spring.GetSelectedUnits()
		verify("pad: the area select picks the unit under its circle", on and count >= 1 and sel[1] == before.com,
			string.format("%s, radius %s, %s units, %d selected", tostring(on), tostring(radius), tostring(count), #sel))
		touch("act area_bigger")
		touch("act area_cancel") -- (B: undone)
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		local on, radius = WG.BarDroidPad.area()
		verify("pad: the D-pad makes the circle bigger, B undoes the selection", not on and radius == 400
			and #Spring.GetSelectedUnits() == 0, tostring(radius))
		-- a control group cleared (Start + L3): set, cleared, recalled empty
		Spring.SelectUnitArray({ before.com })
		touch("act group_assign_4")
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		touch("act group_clear_4")
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		verify("pad: clearing a group keeps the selection", Spring.GetSelectedUnits()[1] == before.com)
		Spring.SelectUnitArray({})
		touch("act group_recall_4")
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		verify("pad: a cleared group recalls nothing", #Spring.GetSelectedUnits() == 0, #Spring.GetSelectedUnits())
		-- LB + Y: patrol at the middle (given at once where unit control is allowed, as in this skirmish; picked else),
		-- 400 elmos off the commander (a patrol to where it stands ends at once: the queue was empty, the order given)
		local x, y, z = Spring.GetUnitPosition(before.com)
		Spring.SetCameraTarget(x + 400, y, z, 0)
		return 0.5
	end,
	function()
		if not before.com then
			return
		end
		Spring.SelectUnitArray({ before.com })
		touch("act lb_y")
		return 1 -- (a given order reaches the queue a few frames on: 0.3 s was too short at 5 fps)
	end,
	function()
		if not before.com then
			return
		end
		-- (a patrol under way has the engine's own FIGHT in front of it)
		local queue, patrol = Spring.GetUnitCommands(before.com, -1) or {}, false
		for _, cmd in ipairs(queue) do
			patrol = patrol or cmd.id == CMD.PATROL
		end
		local _, active = Spring.GetActiveCommand()
		verify("pad: LB + Y patrols (the order given, or picked for A)", patrol or active == CMD.PATROL,
			string.format("queue %s, picked %s, note %s, %d selected", tostring(queue[1] and queue[1].id), tostring(active),
				tostring(select(2, WG.BarDroidPad.note())), #Spring.GetSelectedUnits()))
		Spring.SetActiveCommand(0)
		Spring.GiveOrderToUnit(before.com, CMD.STOP, {}, 0)
		Spring.SelectUnitArray({ before.com }) -- (B with nothing picked clears it: the D-gun needs the commander)
		touch("act dgun") -- (Back + R3)
		return 0.6
	end,
	function()
		if not before.com then
			return
		end
		local _, active = Spring.GetActiveCommand()
		verify("pad: Back + R3 picks the commander's D-gun", active == CMD.MANUALFIRE, tostring(active))
		touch("act cancel")
		-- a camera bookmark (LT + D-pad up stores, D-pad up returns)
		before.mark = Spring.GetCameraState()
		touch("act bookmark_store")
		return 0.3
	end,
	function()
		if not before.com then
			return
		end
		local cs = Spring.GetCameraState()
		Spring.SetCameraTarget(cs.px + 1500, cs.py, cs.pz + 1500, 0)
		return 0.5
	end,
	function()
		if not before.com then
			return
		end
		touch("act bookmark_recall")
		return 1
	end,
	function()
		if not before.com then
			return
		end
		local cs = Spring.GetCameraState()
		near("pad: D-pad up returns to the bookmark (elmos off)",
			math.sqrt((cs.px - before.mark.px) ^ 2 + (cs.pz - before.mark.pz) ^ 2), 0, 30)
		Spring.SelectUnitArray({})
	end,
	-- the interface scale for the Fold's cover screen: 2.0 and one LuaUI reload (which restarts this widget)
	function()
		Spring.SetConfigString("bardroid_touchtest_phase", "scale")
		Spring.SetConfigInt("bardroid_touchtest_fails", fails)
		local f = io.open("LuaUI/Config/bardroid_screen.txt", "w")
		f:write("1680 720 60 0\n")
		f:close()
	end,
	function() end, -- the touch widget looks at the screen file every 0.5 s
	function() end,
	function()
		fails = fails + 1
		log("FAIL cover screen: no interface reload within 20 frames")
	end,
	function() log("done: " .. (fails == 0 and "ALL PASS" or fails .. " FAILED")) end,
}

if phase == "scale" then -- after the reload: the scale is set, and the next look at the screen file reloads nothing
	cases = {
		function() near("cover screen: interface scale", Spring.GetConfigFloat("ui_scale", 1), 2.0, 0.001) end,
		function() -- the touch widget has read the screen file again by now (every 0.5 s)
			local guard = Spring.GetConfigString("bardroid_ui_scale_reload", "?")
			local ok = guard == ""
			if not ok then
				fails = fails + 1
			end
			log((ok and "PASS " or "FAIL ") .. "no second reload (guard '" .. guard .. "')")
			Spring.SetConfigString("bardroid_touchtest_phase", "")
		end,
		function() log("done: " .. (fails == 0 and "ALL PASS" or fails .. " FAILED")) end,
	}
end

-- The build menu's gamepad highlight, drawn once for the pad cases (no pointer over the menu without -Pointer)
function widget:DrawScreen()
	if padDraw.cells then -- (the order menu's cells: red outlines, the ones with an order thicker)
		for i, r in ipairs(padDraw.cells) do
			gl.Color(1, 0.1, 0.1, 0.9)
			gl.LineWidth(i <= padDraw.count and 2 or 1)
			gl.BeginEnd(GL.LINE_LOOP, function()
				gl.Vertex(r[1] + 1, r[2] + 1)
				gl.Vertex(r[3] - 1, r[2] + 1)
				gl.Vertex(r[3] - 1, r[4] - 1)
				gl.Vertex(r[1] + 1, r[4] - 1)
			end)
		end
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
	end
	if padDraw.cell and WG.bardroidBuildmenu and WG.bardroidBuildmenu.droidDrawHover then
		local list = gl.CreateList(function() end)
		padDraw.ok, padDraw.err = pcall(WG.bardroidBuildmenu.droidDrawHover, padDraw.cell, list)
		gl.DeleteList(list)
		padDraw.cell = nil
	end
end
