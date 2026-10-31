-- LuaUI widget for tools/spectate-test.ps1 -QuitCheck: a replay quit in a spectator's first person. BAR's Camera Remember
-- saves the camera as a game quits and opens every later game in it, so bardroid_padfp.lua puts the camera back first;
-- the script reads what was saved. Logs "[spectquit] ...".
function widget:GetInfo()
	return { name = "BAR Droid spectate quit test", desc = "Quits in first person", author = "BAR Droid", layer = 0, enabled = true }
end

local step, waitUntil, skipSent = 0, 0, false
local t0 = Spring.GetTimer()

local function now()
	return Spring.DiffTimers(Spring.GetTimer(), t0)
end

function widget:Update()
	if Spring.GetGameFrame() <= 0 then
		return
	end
	if not skipSent then
		skipSent = true
		Spring.SendCommands("skip 120")
		return
	end
	local S = WG.BarDroidSpectate
	if not S or Spring.GetGameFrame() < 3000 or now() < waitUntil then
		return
	end
	step = step + 1
	if step == 1 then
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			local def = UnitDefs[Spring.GetUnitDefID(unitID)]
			if def and (def.speed or 0) > 0 then
				S.follow(unitID)
				break
			end
		end
		waitUntil = now() + 3
	elseif step == 2 then
		S.actions.preset_first()
		waitUntil = now() + 5
	elseif step == 3 then
		Spring.Echo("[spectquit] camera before quitting: " .. tostring(Spring.GetCameraState().name))
		Spring.SendCommands("quitforce")
	end
end
