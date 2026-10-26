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
	if Spring.GetGameFrame() < 60 or frames < waitUntil then
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

local TILT_RANGE = math.pi / 2 * 1.75 * 1.5 -- bardroid_touch.lua's
local vsx, vsy = Spring.GetViewGeometry()
local cx, cy = math.floor(vsx / 2), math.floor(vsy / 2)
local before, groundBefore
cases = {
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
		near("left stick right pans to the camera's right (elmos)", along / len > 100 and 1 or 0, 1, 0)
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
