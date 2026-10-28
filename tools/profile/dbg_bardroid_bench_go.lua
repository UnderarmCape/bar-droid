-- BAR Droid profiling runs (tools/profile-benchmark.ps1, laptop only, never in the APK): in BAR's benchmark scenario,
-- starts the widget and unsynced gadget profilers once the battle is on (frame 300; units spawn at frame 15) and logs
-- the engine's own timers (/debuginfo profiling) at frame 1500, as the synced profile ends.
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

function widget:GameFrame(n)
	if n == 300 then
		Spring.Echo(string.format("[bardroid-bench-profile] go at frame 300, %d units", #Spring.GetAllUnits()))
		Spring.SetConfigString("bardroid_profile_go", "1", true)
	elseif n == 1500 then
		Spring.Echo(string.format("[bardroid-bench-profile] engine timers at frame 1500, %d units:", #Spring.GetAllUnits()))
		Spring.SendCommands("debuginfo profiling")
	end
end
