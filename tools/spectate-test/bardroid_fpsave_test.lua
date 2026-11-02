-- LuaUI widget for tools/fp-save-test.ps1 (dev phone): a skirmish's player turns spectator and rides a unit in 1st person,
-- then BAR saves the widgets' settings mid-game, as it does whenever a widget is switched on or off (bardroid_padfp.lua's
-- GetConfigData): the camera saved must be the player's own, 1st person must go on, and its way back must stay the
-- player's camera (until 2026-11-02 the first save dropped it: leaving later gave a made-up camera at 1200).
-- Logs "[fpsave] PASS|FAIL <case>" and "[fpsave] done".
function widget:GetInfo()
	return { name = "BAR Droid fp save test", desc = "1st person through a mid-game settings save", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT = "LuaUI/Config/bardroid_fpsave.txt"
local function say(text)
	Spring.Echo(text)
	local f = io.open(OUT, "a")
	if f then
		f:write(text .. "\n")
		f:close()
	end
end

local step, at, unit = 0, nil, nil
local function since()
	return at and Spring.DiffTimers(Spring.GetTimer(), at) or 0
end
local function nextStep()
	step, at = step + 1, Spring.GetTimer()
end

function widget:Update()
	local S = WG.BarDroidSpectate
	local f = Spring.GetGameFrame()
	if step == 0 then
		if f > 150 and S then
			Spring.SendCommands("spectator")
			say("[fpsave] asked to spectate at frame " .. f)
			nextStep()
		end
	elseif step == 1 then
		if Spring.GetSpectatingState() then
			for _, id in ipairs(Spring.GetAllUnits()) do
				if S.followable(id) then
					unit = id
					break
				end
			end
			local cs = Spring.GetCameraState()
			say("[fpsave] spectating; unit " .. tostring(unit) .. ", camera mode " .. tostring(cs.mode))
			cs.dist = 2345
			Spring.SetCameraState(cs, 0)
			nextStep()
		elseif since() > 15 then
			say("[fpsave] FAIL never spectating")
			step = 99
		end
	elseif step == 2 and since() > 0.5 then
		S.firstPerson(unit)
		nextStep()
	elseif step == 3 and since() > 1.5 then
		local cs = Spring.GetCameraState()
		say("[fpsave] " .. (cs.mode == 0 and "PASS" or "FAIL") .. " in 1st person (mode " .. tostring(cs.mode) .. ")")
		S.cameraForSave()
		local back = Spring.GetCameraState()
		say("[fpsave] " .. ((back.mode == 2 and math.abs((back.dist or 0) - 2345) < 1) and "PASS" or "FAIL")
			.. " the saved camera is the player's (mode " .. tostring(back.mode) .. ", dist " .. tostring(back.dist) .. ")")
		nextStep()
	elseif step == 4 and since() > 0.5 then
		local cs = Spring.GetCameraState()
		say("[fpsave] " .. (cs.mode == 0 and "PASS" or "FAIL") .. " 1st person goes on (mode " .. tostring(cs.mode) .. ")")
		S.cameraForSave() -- (a second save: before the fix the way back was gone, a made-up camera at 1200)
		local back = Spring.GetCameraState()
		say("[fpsave] " .. (math.abs((back.dist or 0) - 2345) < 1 and "PASS" or "FAIL")
			.. " its way back kept (dist " .. tostring(back.dist) .. ")")
		nextStep()
	elseif step == 5 and since() > 0.5 then
		say("[fpsave] done")
		step = 99
	end
end
