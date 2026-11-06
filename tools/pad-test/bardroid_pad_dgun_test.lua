-- LuaUI widget for tools/pad-test.ps1 -Dgun: BAR's released game with user widgets' orders forbidden, as a host can
-- forbid them; a virtual pad (pad-dgun.evemu) plays v0.8.5's D-gun mode (Kailil, 2026-11-06: LB + RB + R3; the right
-- stick aims, RT fires, the left stick walks the commander, B leaves) and the share list's chord (LB + D-pad up tapped,
-- then held: a skirmish has no teammate, so "NO TEAMMATES"). With orders forbidden the shot and the walk are BAR's D-gun
-- and Move picked and clicked by the app on the spot: the commander's orders show it went the whole way. Logs
-- "[padtest] PASS|FAIL <case>" and "[padtest] done".
function widget:GetInfo()
	return { name = "BAR Droid pad D-gun test", desc = "What the virtual gamepad did in the D-gun mode", author = "BAR Droid", layer = 0, enabled = true }
end

local READY_FRAME = 420
local fails, done = 0, false
local com
local seenMode, aimStart, aimTurned, fired, moved, left, clickPoint, noTeammates = false, nil, false, false, false, false, nil, false
local seenPad, lastTrace = false, nil

local function say(text)
	Spring.Echo(text)
	local f = io.open("LuaUI/Config/bardroid_padtest.txt", "a")
	if f then
		f:write(text .. "\n")
		f:close()
	end
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	say("[padtest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end

local function finish()
	done = true
	check("the rule is on: a user widget's order is refused", not pcall(Spring.GiveOrderToUnit, com, CMD.STOP, {}, 0))
	check("LB + RB + R3: v0.8.5's D-gun mode on the commander", seenMode)
	check("the right stick turns the aim", aimTurned)
	check("RT: the D-gun, picked and clicked by the app on the spot", fired and clickPoint ~= nil, clickPoint)
	check("the left stick walks the commander (BAR's Move, clicked)", moved)
	check("B leaves the mode", left)
	check("LB + D-pad up tapped, then held: the share list's chord (no teammate here)", noTeammates)
	say("[padtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
end

function widget:UnitCommand(unitID, _, _, cmdID)
	if unitID ~= com then
		return
	end
	local mode = WG.BarDroidPad and WG.BarDroidPad.modal()
	if cmdID == CMD.MANUALFIRE then
		fired = true
	elseif cmdID == CMD.MOVE and mode == "dgun" then
		moved = true
	end
end

function widget:GameFrame(f)
	if done then
		return
	end
	if f == 60 then
		Spring.SendCommands("cheat 1")
	elseif f == 120 then
		com = Spring.GetTeamUnits(Spring.GetMyTeamID())[1]
	elseif f == READY_FRAME then
		local x, y, z = Spring.GetUnitPosition(com)
		Spring.SelectUnitArray({ com })
		Spring.SetCameraTarget(x, y, z, 0) -- (the D-gun's ring on the screen: its clicks must land on it)
		say("[padtest] ready, the commander: " .. tostring(com))
	end
	if not com or f < READY_FRAME then
		return
	end
	if Spring.GetSelectedUnitsCount() == 0 and Spring.GetUnitPosition(com) then
		Spring.SelectUnitArray({ com }) -- (the D-gun mode wants it selected)
	end
	local mode, unitID, ax, az, _, _, cx, cy = WG.BarDroidPad.modal()
	if mode == "dgun" and unitID == com then
		seenMode = true
		if not aimStart then
			aimStart = { ax, az }
		elseif math.abs(ax - aimStart[1]) + math.abs(az - aimStart[2]) > 0.5 then
			aimTurned = true
		end
	end
	if seenMode and mode == nil then
		left = true
	end
	if cx then
		clickPoint = string.format("%.2f %.2f", cx, cy)
	end
	local _, note = WG.BarDroidPad.note()
	noTeammates = noTeammates or note == "NO TEAMMATES"
	seenPad = seenPad or WG.BarDroidPadOnly == true
	local trace = string.format("mode %s, aim %s %s, fired %s, moved %s, note %s, input %s", tostring(mode),
		ax and string.format("%.2f", ax) or "-", az and string.format("%.2f", az) or "-", tostring(fired), tostring(moved),
		tostring(note), tostring(WG.BarDroidInput))
	if trace ~= lastTrace then
		lastTrace = trace
		say("[padtest] f" .. f .. " " .. trace)
	end
	if (seenPad and WG.BarDroidPadOnly == nil) or f > READY_FRAME + 2400 then
		finish()
	end
end
