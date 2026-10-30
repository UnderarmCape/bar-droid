-- BAR Droid low memory: keeps BAR's GL4 unit shaders (CUS GL4) off on an 8 GB phone, where launch-bar.sh's low-memory
-- mode sets "cus2 = 0" (BarDroidLowMemory = 1). BAR's CUS GL4 gadget reads cus2 once, when LuaRules loads, and then
-- stays off; but BAR's Options widget, in a developer game (the controller game is "Beyond All Reason $VERSION") with
-- 3 GB or more of GPU memory (a phone reports all of its RAM), finds cus2 off and switches the shaders back on at the
-- game's start (+60-100 MB of GPU memory, which a phone cannot swap; docs/HISTORY.md "Fitting BAR into an 8 GB phone").
-- So this widget, before BAR's Options widget (its layer), puts cus2 back to 1 once CUS GL4 has seen 0, and back to 0
-- when LuaUI ends (a next game started from the lobby in the same engine loads LuaRules again). BAR's own game (online)
-- treats the phone's GPU as a low-end one and never switches them on; there this changes nothing. Installed into
-- LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid low memory",
		desc = "Keeps BAR's GL4 unit shaders off on an 8 GB phone",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -3000000, -- before BAR's Options (-99990)
		enabled = true,
	}
end

local lowMemory = Spring.GetConfigInt("BarDroidLowMemory", 0) == 1

function widget:Initialize()
	if lowMemory and Spring.GetConfigInt("cus2", 1) == 0 then
		Spring.SetConfigInt("cus2", 1)
		Spring.Echo("[bardroid-lowmem] BAR's GL4 unit shaders stay off (low-memory mode)")
	end
end

function widget:Shutdown()
	if lowMemory then
		Spring.SetConfigInt("cus2", 0)
	end
end
