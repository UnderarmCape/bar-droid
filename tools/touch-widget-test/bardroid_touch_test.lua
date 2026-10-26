-- User widget for tools/touch-widget-test.ps1: moves the pointer over BAR's real interface and reads what
-- bardroid_touch.lua answers in LuaUI/Config/bardroid_hover.txt (1 = interface: a finger drag there is a mouse drag,
-- 0 = map: a pan). Logs "[touchtest] PASS|FAIL <case>" and "[touchtest] done".
function widget:GetInfo()
	return { name = "BAR Droid touch test", desc = "Checks the touch widget's interface answers", author = "BAR Droid",
		layer = 0, enabled = true }
end

local HOVER = "LuaUI/Config/bardroid_hover.txt"
local frames, step, waitUntil = 0, 0, 0
local fails = 0

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

local vsx, vsy = Spring.GetViewGeometry()
cases = {
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
	function() log("done: " .. (fails == 0 and "ALL PASS" or fails .. " FAILED")) end,
}
