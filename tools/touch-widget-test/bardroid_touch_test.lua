-- User widget for tools/touch-widget-test.ps1: moves the pointer over BAR's real interface and reads what
-- bardroid_touch.lua answers in LuaUI/Config/bardroid_hover.txt (1 = interface: a finger drag there is a mouse drag,
-- 0 = map: a pan). Logs "[touchtest] PASS|FAIL <case>" and "[touchtest] done".
function widget:GetInfo()
	return { name = "BAR Droid touch test", desc = "Checks the touch widget's interface answers", author = "BAR Droid",
		layer = 0, enabled = true }
end

local HOVER = "LuaUI/Config/bardroid_hover.txt"
local frames, step, waitUntil = 0, 0, 0
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

local cases
function widget:Update()
	frames = frames + 1
	-- (from 5 s of game: BAR's own camera move to the start position came after the first cases on a fast laptop)
	if Spring.GetGameFrame() < 150 or frames < waitUntil then
		return
	end
	step = step + 1
	local c = cases[step]
	if c then
		c()
		waitUntil = frames + 20
	end
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
local before, groundBefore, edgeView, edgeExpect, com
cases = {
	-- the same start every run (the game keeps the camera of the last one): mid-map, BAR's usual angle
	function()
		local cs = Spring.GetCameraState()
		cs.px, cs.pz, cs.dist, cs.rx, cs.ry = Game.mapSizeX / 2, Game.mapSizeZ / 2, 2500, 2.6, 0
		Spring.SetCameraState(cs, 0)
	end,
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
	function()
		groundBefore = groundAt(cx, cy)
		touch(string.format("pan %.1f %.1f %.1f %.1f", cx, vsy - cy, cx - 100, vsy - cy))
	end,
	function()
		local g = groundAt(cx - 100, cy)
		local miss = g and groundBefore and math.sqrt((g[1] - groundBefore[1]) ^ 2 + (g[3] - groundBefore[3]) ^ 2)
		near("drag: the map point follows the finger (elmos off)", miss, 0, 8)
	end,
	-- at the map's edge, looking out over it: a drag high on the screen (over the void) moves the camera like the same
	-- drag in the middle of the screen (no jump from points near the horizon)
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
	function()
		local row = math.floor(vsy * 0.3) -- X pixels from the top: past the edge, below the horizon
		local _, dy = Spring.GetPixelDir(cx, vsy - row)
		edgeView = Spring.TraceScreenRay(cx, vsy - row, true) ~= "ground" and dy and dy < -0.01
		local a, b = groundAt(cx, cy), groundAt(cx + 100, cy)
		edgeExpect = a and b and math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
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
		log(string.format("     edge drag: before %.0f,%.0f ry %.2f rx %.2f, after %.0f,%.0f, expected %s", before.px, before.pz,
			before.ry, before.rx, cs.px, cs.pz, tostring(edgeExpect)))
		near("drag over the void past the edge moves like one mid-screen (moved / expected)",
			edgeExpect and moved / edgeExpect, 1, 0.15)
		Spring.WarpMouse(cx, vsy - math.floor(vsy * 0.3)) -- the pointer into that void
	end,
	function() expect("pointer off the map (the void): answer 2", 2) end,
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
	function() near("act overview_out: back", Spring.GetCameraState().name ~= "ov" and 1 or 0, 1, 0) end,
	function() end, -- the camera's way back from the overview
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
	function() Spring.WarpMouse(math.floor(vsx * 0.5), math.floor(vsy * 0.45)) end,
	function() Spring.WarpMouse(math.floor(vsx * 0.5), math.floor(vsy * 0.45)) end,
	function() expect("map in the middle", 0) end,
	function()
		local p = WG.topbar and WG.topbar.GetPosition and WG.topbar.GetPosition()
		if not p then
			fails = fails + 1
			log("FAIL no WG.topbar.GetPosition")
			return
		end
		Spring.WarpMouse(math.floor((p[1] + p[3]) / 2), math.floor((p[2] + p[4]) / 2))
	end,
	function() expect("top bar", 1) end,
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
		Spring.WarpMouse(found[1], found[2])
	end,
	function() expect("minimap", 1) end,
	function()
		if WG.options and WG.options.toggle then
			WG.options.toggle(true)
		else
			Spring.SendCommands("options")
		end
		Spring.WarpMouse(math.floor(vsx * 0.5), math.floor(vsy * 0.45))
	end,
	function() expect("settings window open", 1) end,
	function()
		if WG.options and WG.options.toggle then
			WG.options.toggle(false)
		end
		Spring.WarpMouse(math.floor(vsx * 0.5) + 3, math.floor(vsy * 0.45))
	end,
	function() expect("map after the window closed", 0) end,
	-- the app's chat display (bardroid_chat.lua): BAR's chat hands it each line it parsed
	function()
		before = WG.bardroidChat and WG.bardroidChat.lines()
		Spring.SendCommands("say touch test chat line")
	end,
	function()
		local now = WG.bardroidChat and WG.bardroidChat.lines()
		near("chat: a said line reaches BAR Droid chat", (before and now) and now - before or -1, 1, 0)
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
