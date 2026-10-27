-- BAR Droid benchmark: the app's direct start of BAR's "Benchmark BAR" scenario (launch-bar.sh MODE=bench, which
-- leaves LuaUI/Config/bardroid_bench.txt; nothing happens without it). The game runs unattended: if it starts paused
-- (BAR pauses singleplayer while a window such as the scenario's Mission Info is open; launch-bar.sh switches that
-- widget off for benchmarks) it is resumed, and once the benchmark gadget has printed its results the game is quit, so
-- tools/phone-bench.ps1 can start the next run. Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid benchmark",
		desc = "Runs BAR's benchmark scenario unattended when the app starts it",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local FLAG = "LuaUI/Config/bardroid_bench.txt"
local QUIT_AFTER = 3 -- seconds after the results, for the log to take them
local quitAt

function widget:Initialize()
	if not VFS.FileExists(FLAG, VFS.RAW) then
		widgetHandler:RemoveWidget()
		return
	end
	Spring.Echo("[bardroid-bench] unattended benchmark")
end

local checked = 0
function widget:Update()
	local now = os.clock()
	if quitAt then
		if now >= quitAt then
			Spring.Echo("[bardroid-bench] done: quitting")
			Spring.SendCommands("quitforce")
			quitAt = math.huge
		end
		return
	end
	if now - checked < 2 then
		return
	end
	checked = now
	local _, _, paused = Spring.GetGameSpeed()
	if paused and Spring.GetGameFrame() > 0 then
		Spring.Echo("[bardroid-bench] the game was paused: resuming")
		Spring.SendCommands("pause 0")
	end
end

function widget:AddConsoleLine(line)
	if not quitAt and line:find("Benchmark ended", 1, true) then
		quitAt = os.clock() + QUIT_AFTER
	end
end
