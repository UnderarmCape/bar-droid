-- LuaUI widget for tools/pad-test.ps1: what a virtual gamepad (pad.evemu) did in a skirmish on the phone, through the app's
-- real pad path: LB + L3 held rides the commander, RT fires, the right stick looks, B leaves, the right stick zooms and LT
-- speeds it up, D-pad down is the commander, and the pad going away ends the pad's ways. The ride's squad also gets an
-- enemy unit, made visible by /globallos (as a unit captured in sight), which has to drop out. Logs "[padtest] PASS|FAIL
-- <case>" and "[padtest] done".
function widget:GetInfo()
	return { name = "BAR Droid pad test", desc = "Reports what the virtual gamepad did", author = "BAR Droid", layer = 0, enabled = true }
end

local READY_FRAME = 300
local picked, com, lastDist, done = false, nil, nil, false
local rode, fired, firedAfter, yawFrom, yawTo, left, sawPad, sawCommander = false, false, false, nil, nil, false, false, false
local zoomSteps = {}
local fails = 0
local taken = nil -- the enemy unit put in the squad

local function enemyUnit()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if Spring.GetUnitTeam(unitID) ~= Spring.GetMyTeamID() then
			return unitID
		end
	end
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[padtest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail and (": " .. tostring(detail)) or ""))
end

local function finish()
	done = true
	check("LB + L3 held: rides the unit", rode)
	check("RT: a target while it is held", fired)
	check("RT let go: the target gone", firedAfter)
	check("the right stick looks round", yawFrom and yawTo and math.abs(yawTo - yawFrom) > 0.3, tostring(yawFrom) .. " -> " .. tostring(yawTo))
	check("B: the ride over, the unit selected again", left)
	table.sort(zoomSteps)
	local slow, fast = zoomSteps[2], zoomSteps[#zoomSteps]
	check("LT speeds the zoom up", slow and fast and fast > slow * 1.8, tostring(slow) .. " -> " .. tostring(fast))
	check("D-pad down: the commander", sawCommander)
	check("the pad gone: its ways end, no taps needed", sawPad and WG.BarDroidPadOnly == nil)
	local fp = WG.BarDroidPadFP
	check("a unit no longer the player's leaves the squad", taken and fp and #fp.squad() == 0, tostring(taken))
	Spring.Echo("[padtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
end

function widget:GameFrame(f)
	if done then
		return
	end
	if f == READY_FRAME - 90 then
		Spring.SendCommands("cheat 1")
	elseif f == READY_FRAME - 45 then
		Spring.SendCommands("globallos")
	elseif f == READY_FRAME then
		Spring.Echo("[padtest] ready") -- (the script taps the screen three times: the app's controls in the controller game)
	end
	if WG.BarDroidOwnsBuildMenu and not picked then
		picked = true
		com = Spring.GetTeamUnits(Spring.GetMyTeamID())[1]
		Spring.SelectUnitArray({ com })
	end
	if not picked then
		return
	end
	local fp = WG.BarDroidPadFP
	local riding = fp and fp.active()
	local target = Spring.GetUnitWeaponTarget(com, 1)
	local cs = Spring.GetCameraState()
	sawPad = sawPad or WG.BarDroidPadOnly == true
	if riding then
		if not rode then
			taken = enemyUnit()
			if taken then
				table.insert(fp.squad(), taken)
			end
		end
		rode = true
		if target and target > 0 then
			fired = true
		elseif fired then
			firedAfter = true
		end
		yawFrom = yawFrom or cs.ry
		yawTo = cs.ry
	elseif rode then
		left = left or (Spring.GetSelectedUnits()[1] == com)
	end
	if left and f % 15 == 0 and cs.dist then
		if lastDist and lastDist / cs.dist > 1.02 then
			zoomSteps[#zoomSteps + 1] = math.log(lastDist / cs.dist)
		end
		lastDist = cs.dist
	end
	local _, note = WG.BarDroidPad.note()
	sawCommander = sawCommander or (note == "COMMANDER")
	if sawPad and WG.BarDroidPadOnly == nil then
		finish()
	end
end
