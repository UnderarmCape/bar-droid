-- BAR Droid profiling runs (tools/profile-benchmark.ps1, laptop only, never in the APK): in BAR's benchmark scenario,
-- starts the widget and unsynced gadget profilers once the battle is on (frame 300; units spawn at frame 15) and logs
-- the engine's own timers (/debuginfo profiling) at frame 1500, as the synced profile ends. With
-- bardroid_profile_pointer = 1 (-PointerOnBattle) the pointer stays in the middle of the window, on the battle.
function widget:GetInfo()
	return {
		name = "BAR Droid benchmark profile go",
		desc = "Starts the profilers in BAR's benchmark scenario (BAR Droid profiling runs)",
		author = "BAR Droid",
		license = "GPL-2.0-or-later",
		layer = -999998,
		enabled = true,
	}
end

local pointer = Spring.GetConfigInt("bardroid_profile_pointer", 0) == 1
local warpedAt = 0
function widget:Update()
	local t = os.clock()
	if pointer and t - warpedAt >= 0.5 then
		warpedAt = t
		local vsx, vsy = Spring.GetViewGeometry()
		Spring.WarpMouse(math.floor(vsx / 2), math.floor(vsy / 2))
	end
end

-- os.clock (the process's CPU time in standard Lua) against real time over the battle: widgets must time with
-- Spring.GetTimer if the two differ
local clock0, timer0
function widget:GameFrame(n)
	if n == 300 then
		Spring.Echo(string.format("[bardroid-bench-profile] go at frame 300, %d units", #Spring.GetAllUnits()))
		Spring.SetConfigString("bardroid_profile_go", "1", true)
		clock0, timer0 = os.clock(), Spring.GetTimer()
	elseif n == 1500 then
		Spring.Echo(string.format("[bardroid-bench-profile] engine timers at frame 1500, %d units:", #Spring.GetAllUnits()))
		Spring.SendCommands("debuginfo profiling")
		local real = Spring.DiffTimers(Spring.GetTimer(), timer0)
		Spring.Echo(string.format("[bardroid-bench-profile] frames 300-1500: os.clock %.1f s in %.1f s of real time (x%.2f)",
			os.clock() - clock0, real, (os.clock() - clock0) / real))
	end
end
