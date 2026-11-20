-- LuaUI widget for tools/driverwatch-phone-test.ps1: the GPU driver fault's close (GameService + DriverWatch) must arm
-- only on Mesa's own line, never on a chat message or a Lua echo that carries its words. In a skirmish: the driver's
-- refusal and BAR's watchdog line said as chat (Spring.SendMessage) and echoed (Spring.Echo), each an engine log line
-- ("[t=...][f=...] ..."); then the widget waits 12 s while the script reads launcher.log for the app's "the GPU driver
-- refused a submit" (armed) and checks the game still runs. Logs "[driverwatchtest] ..." lines; "said" in
-- LuaUI/Config/bardroid_driverwatchtest.txt once the lines are out, "end" at the end.
function widget:GetInfo()
	return { name = "BAR Droid driver watch test", desc = "Chat with the driver fault's words arms nothing",
		author = "BAR Droid", layer = 0, enabled = true }
end

local OUT = "LuaUI/Config/bardroid_driverwatchtest.txt"
local REFUSAL = "MESA: error: flush_submit_list:89: submit failed -1 (Resource deadlock avoided)"
local HUNG = "Warning: [Watchdog] Hang detection triggered for Spring main thread."
local stage, at, clock = "wait", 0, 0

local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end

function widget:Update(dt)
	clock = clock + (dt or 0)
	if stage == "wait" and Spring.GetGameFrame() >= 150 then
		Spring.SendMessage(REFUSAL) -- (as a player would type it)
		Spring.Echo(REFUSAL)
		stage, at = "hung", clock
	elseif stage == "hung" and clock - at > 2 then
		Spring.SendMessage(HUNG)
		Spring.Echo(HUNG)
		Spring.Echo("[driverwatchtest] the driver's refusal and the watchdog's words said as chat and echoed")
		write("said\n")
		stage, at = "watch", clock
	elseif stage == "watch" and clock - at > 12 then
		Spring.Echo(string.format("[driverwatchtest] the game still running %.0f s after (frame %d)", clock - at,
			Spring.GetGameFrame()))
		write("end\n")
		stage = "over"
	end
end
