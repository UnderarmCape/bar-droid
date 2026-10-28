-- LuaMenu widget for the laptop lobby tests (tools/lobby-*-test.ps1): they never log in (Kailil, 2026-10-28: "dont
-- login and disable autologin on the laptop when you run the tests": BAR's server allows one session per account, and
-- a test's login ended his game on the phone). Sets WG.BarDroidLoggedIn (the time the lobby was ready; the tests'
-- start signal, the name from when they ran logged in) once the lobby's interface is built, and logs "[lobbylogin]"
-- lines for the script. If the lobby ever connects anyway, it is disconnected at once.
function widget:GetInfo()
	return { name = "BAR Droid lobby test login", desc = "The lobby tests start offline", author = "BAR Droid",
		layer = -10, enabled = true }
end

local warned = false

function widget:Update()
	local lobby = WG.LibLobby and WG.LibLobby.lobby
	local status = lobby and lobby:GetConnectionStatus() or "no lobby yet"
	if status == "connected" or status == "connecting" then
		if lobby.Disconnect then
			lobby:Disconnect()
		end
		if not warned then
			warned = true
			Spring.Echo("[lobbylogin] the test lobby connected (" .. status .. "): disconnected")
		end
	end
	if not WG.BarDroidLoggedIn and WG.Chobby and WG.Chobby.interfaceRoot then
		WG.BarDroidLoggedIn = Spring.GetTimer()
		Spring.Echo("[lobbylogin] ready (offline: " .. status .. ")")
	end
end
