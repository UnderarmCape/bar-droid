-- LuaMenu widget for the laptop lobby tests (tools/lobby-*-test.ps1): they run logged in (Kailil, 2026-10-27: "Make
-- the lobby tests wait for me to log in before they run"). Sets WG.BarDroidLoggedIn (the time of the login) once the
-- server accepted the login (liblobby's status "connected") and logs "[lobbylogin]" lines for the script: waiting
-- (every 10 s) and logged in. The login itself is Chobby's automatic login with the settings the script wrote from
-- bar-lobby-login.txt (tools/toolchain.ps1 Get-LobbyLoginLua), or the player on the lobby's own login screen.
function widget:GetInfo()
	return { name = "BAR Droid lobby test login", desc = "The lobby tests wait for the login", author = "BAR Droid",
		layer = -10, enabled = true }
end

local t0, said = Spring.GetTimer(), -1

function widget:Update()
	local lobby = WG.LibLobby and WG.LibLobby.lobby
	local status = lobby and lobby:GetConnectionStatus() or "no lobby yet"
	if status == "connected" then
		if not WG.BarDroidLoggedIn then
			WG.BarDroidLoggedIn = Spring.GetTimer()
			Spring.Echo("[lobbylogin] logged in")
		end
		return
	end
	local tens = math.floor(Spring.DiffTimers(Spring.GetTimer(), t0) / 10)
	if tens ~= said then
		said = tens
		Spring.Echo("[lobbylogin] waiting for the login (" .. status .. ")")
	end
end
