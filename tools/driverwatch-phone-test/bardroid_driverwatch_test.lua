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
-- (the engine's line for a written save, which bardroid_topbar.lua answers with "Game saved" in BAR's message line: said as
-- chat it must not; a real save, made 3 s after the chat, must: 2026-11-20)
local SAVED = "[ILoadSaveHandler::CreateSave] saved game to file Saves/bardroid_chat.ssf"
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
		stage, at = "say", clock
	elseif stage == "say" and clock - at > 1 then
		-- (and as a player's own chat, "say": the form another player's words take in the log; with them the engine's
		-- other lines the app reads its state from: a lobby game's end, a load, a join's server)
		for _, words in ipairs({ REFUSAL, HUNG, "[SpringApp::Reload] test", "[LoadScreen] creating LoadScreen",
			"[CPreGame] using client IP 203.0.113.7 and port 8452", "recording demo to demos/test.sdfz", SAVED,
			-- (and the lines bardroid_chat.lua shows as the game's own: a pause, BAR's Autoquit countdown; 2026-11-21)
			"Phone paused the game", "<autoquit> Automatically exiting in 9 seconds" }) do
			Spring.SendCommands("say " .. words)
		end
		Spring.Echo("[driverwatchtest] the driver's refusal and the watchdog's words said as chat and echoed, and the"
			.. " engine's state lines said as chat")
		write("said\n")
		-- (Chobby's "the lobby is over the game", sent as any player's widget can, Spring.SendLuaUIMsg: it reaches every
		-- player's LuaUI; the app's fingers must stay on the game, the overlay file "0"; 2026-11-21)
		Spring.SendLuaUIMsg("LobbyOverlayActive1")
		stage, at = "spoofed", clock
	elseif stage == "spoofed" and clock - at > 3 then
		local f = io.open("LuaUI/Config/bardroid_overlay.txt", "r")
		local v = f and f:read("*l") or "none"
		if f then
			f:close()
		end
		Spring.Echo("[driverwatchtest] the lobby message from a widget: overlay " .. tostring(v) .. ", the dock "
			.. ((WG.BarDroidPortrait and WG.BarDroidPortrait.aside and WG.BarDroidPortrait.aside()) and "aside" or "in place"))
		Spring.SendLuaUIMsg("LobbyOverlayActive0") -- (whatever it did, undone)
		stage, at = "save", clock
	elseif stage == "save" and clock - at > 3 then
		Spring.Echo("[driverwatchtest] a real save now")
		Spring.SendCommands("savegame bardroid_dwtest")
		stage, at = "pause", clock
	elseif stage == "pause" and clock - at > 4 then -- (a real pause and unpause: the chat box's two system lines)
		Spring.Echo("[driverwatchtest] a real pause and unpause now")
		Spring.SendCommands("pause 1")
		stage, at = "unpause", clock
	elseif stage == "unpause" and clock - at > 1.5 then
		Spring.SendCommands("pause 0")
		stage, at = "watch", clock
	elseif stage == "watch" and clock - at > 12 then
		Spring.Echo(string.format("[driverwatchtest] the game still running %.0f s after (frame %d)", clock - at,
			Spring.GetGameFrame()))
		write("end\n")
		stage = "over"
	end
end
