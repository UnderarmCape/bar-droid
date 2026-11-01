-- LuaUI widget for tools/pad-test.ps1 -Online: BAR's released game with user widgets' orders forbidden, as a host can
-- forbid them; a virtual pad (pad-online.evemu) plays every control that used to say "NOT IN THIS GAME" and the rest of
-- what an online game needs. Kailil, 2026-11-01: "I should have no cases of that happening". Logs "[padtest] PASS|FAIL
-- <case>" and "[padtest] done".
function widget:GetInfo()
	return { name = "BAR Droid pad online test", desc = "What the virtual gamepad did with unit-control widgets forbidden", author = "BAR Droid", layer = 0, enabled = true }
end

local READY_FRAME = 420
local PING = { 2000, 2000 } -- x, z: "a ping from someone else" (WG.BarDroidPad.setPing)
local fails = 0
local com, lab
local counts, patrol, focus, allCombat, onScreen, selfD, myPing, jumped, labQueued, labCleared = {}, false, false, 0, 0, false, false, false, false, false
local lastCount, seenPad, done = nil, false, false
local labStep, lastTrace, centred = 0, nil, false

-- (its own file: the game's log reaches the disk late on a phone, and tools/pad-test.ps1 reads this as it goes)
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

local function has(list, a, b, c)
	for i = 1, #list - 2 do
		if list[i] == a and list[i + 1] == b and list[i + 2] == c then
			return true
		end
	end
	return false
end

local function finish()
	done = true
	check("the rule is on: a user widget's order is refused", not pcall(Spring.GiveOrderToUnit, com, CMD.STOP, {}, 0))
	check("the app's build menu runs in BAR's game", WG.bardroidBuildmenu ~= nil)
	check("RB: the build menu has the pad", focus)
	check("L3 and R3: the next, then the last order gone (3, 2, 1)", has(counts, 3, 2, 1), table.concat(counts, " "))
	check("LB + Y: a patrol at the middle, with no second press", patrol)
	check("RB + D-pad down: every combat unit, no commander", allCombat >= 3, allCombat)
	check("RB + D-pad right: the combat units on the screen", onScreen >= 1, onScreen)
	check("Back + R3 + L3 held: self-destruct", selfD)
	check("RB + D-pad up held: a ping", myPing)
	check("RB + D-pad up: the camera at the last ping", jumped)
	check("LB + B: the factory's queue gone", labQueued and labCleared, tostring(labQueued) .. " " .. tostring(labCleared))
	say("[padtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
end

function widget:MapDrawCmd(playerID, cmdType)
	if cmdType == "point" and playerID == Spring.GetMyPlayerID() then
		myPing = true
		WG.BarDroidPad.setPing(PING[1], 0, PING[2])
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
		Spring.SendCommands("give 3 armpw")
		Spring.SendCommands("give 1 armlab")
	elseif f == READY_FRAME then
		for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID())) do
			if UnitDefs[Spring.GetUnitDefID(unitID)].isFactory then
				lab = unitID
			end
		end
		say("[padtest] ready, the lab: " .. tostring(lab))
	end
	if not com or not Spring.GetUnitPosition(com) then
		return
	end
	local count = Spring.GetUnitCommandCount(com)
	if count ~= lastCount then
		lastCount = count
		counts[#counts + 1] = count
	end
	for _, cmd in ipairs(Spring.GetUnitCommands(com, 8) or {}) do
		patrol = patrol or cmd.id == CMD.PATROL
	end
	local b = WG.bardroidBuildmenu
	focus = focus or (b and b.droidFocus and b.droidFocus() ~= nil) or false
	local selected = Spring.GetSelectedUnits()
	local pawns, others = 0, 0
	for _, unitID in ipairs(selected) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def.isBuilder or def.isFactory then
			others = others + 1
		else
			pawns = pawns + 1
		end
		selfD = selfD or (Spring.GetUnitSelfDTime(unitID) or 0) > 0
	end
	if others == 0 and pawns > 0 and allCombat == 0 then
		allCombat = pawns
		local x, y, z = Spring.GetUnitPosition(selected[1]) -- (RB + D-pad right comes next: they have to be on the screen)
		Spring.SetCameraTarget(x, y, z, 0)
	end
	seenPad = seenPad or WG.BarDroidPadOnly == true
	local cs = Spring.GetCameraState()
	if myPing and cs.px and math.abs(cs.px - PING[1]) < 300 and math.abs(cs.pz - PING[2]) < 300 then
		jumped = true
	end
	-- after the jump the lab's turn: selected and queued as BAR's menu does; the pad's LB + B comes next
	if jumped and lab and labStep == 0 then
		labStep = 1
		Spring.SelectUnitArray({ lab })
	elseif labStep >= 1 and labStep <= 4 then
		labStep = labStep + 1
		local index = Spring.GetCmdDescIndex(-UnitDefNames.armpw.id)
		if index then
			Spring.SetActiveCommand(index, 1, true, false, false, false, false, false)
		end
	end
	if lab and labStep >= 5 then
		local n = Spring.GetFactoryCommands(lab, 0) or 0
		n = type(n) == "table" and #n or n
		labQueued = labQueued or n >= 3
		labCleared = labCleared or (labQueued and n == 0)
	end
	local _, note = WG.BarDroidPad.note()
	onScreen = tonumber((note or ""):match("^ON SCREEN: (%d+)$")) or onScreen
	if note == "COMMANDER" and not centred then -- (a random start: at a map's edge the pad's pans and orders stayed on the commander)
		centred = true
		Spring.SetCameraTarget(Game.mapSizeX / 2, 0, Game.mapSizeZ / 2, 0)
	end
	local trace = string.format("orders %s, selected %d, focus %s, input %s, padonly %s, note %s", tostring(count), #selected,
		tostring(focus), tostring(WG.BarDroidInput), tostring(WG.BarDroidPadOnly), tostring(note))
	if trace ~= lastTrace then
		lastTrace = trace
		say("[padtest] f" .. f .. " " .. trace)
	end
	if (seenPad and WG.BarDroidPadOnly == nil) or f > READY_FRAME + 2400 then
		finish()
	end
end
