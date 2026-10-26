-- LuaMenu widget for tools/lobby-bridge-test.ps1: logs each ReplayInfo the lobby gets from LobbyBridge, opens the
-- Replays tab (which reads every replay in demos/) and a web link, then says "done" (the script ends the engine).
function widget:GetInfo()
	return { name = "BAR Droid bridge test", desc = "LobbyBridge against the real lobby", author = "BAR Droid",
		layer = 0, enabled = true }
end

local start, step, results = nil, 0, 0

local function log(...)
	Spring.Echo("[bridgetest] " .. table.concat({ ... }, " "))
end

function widget:Update() -- LuaMenu passes no dt
	start = start or Spring.GetTimer()
	local t = Spring.DiffTimers(Spring.GetTimer(), start)
	if step == 0 and t > 3 then
		step = 1
		local c = WG.Connector
		log("connector", tostring(c ~= nil), "enabled", tostring(c and c.enabled), "writePath", tostring(c and c.writePath))
		local rh = WG.ReplayHandler
		if rh and rh.ReadReplayInfoDone then
			local orig = rh.ReadReplayInfoDone
			rh.ReadReplayInfoDone = function(path, engine, game, map, players, time, winners)
				results = results + 1
				local names = {}
				for _, p in pairs(players or {}) do
					names[#names + 1] = tostring(p.name) .. "/a" .. tostring(p.allyTeamId) .. (p.aiId and "/ai" or "")
				end
				log("ReplayInfo", tostring(path), tostring(engine), tostring(game), tostring(map), tostring(time),
					"winners:", winners and table.concat(winners, ",") or "nil", "players:", table.concat(names, ","))
				return orig(path, engine, game, map, players, time, winners)
			end
		else
			log("no WG.ReplayHandler")
		end
	elseif step == 1 and t > 6 then
		step = 2
		local ok, err = pcall(function()
			WG.Chobby.interfaceRoot.GetMainWindowHandler().OpenSubmenu(1, "replays")
		end)
		log("open replays tab:", tostring(ok), tostring(err))
		WG.Connector.Send("OpenFile", { path = "https://www.beyondallreason.info/" })
	elseif step == 2 and t > 20 then
		step = 3
		log("done:", results, "replay infos")
	end
end
