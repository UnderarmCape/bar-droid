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
local pauseFrom -- (the ping round's pause: from when)
local labStep, lastTrace, centred = 0, nil, false
local solar, solarStep, solarAt, solarKept, solarNote, solarNotes, solarHeld = nil, 0, 0, false, nil, 0, false
local evenOrders = 0 -- the most orders seen laid out evenly in the app's order menu while the pad hid its own

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
	-- (the app's copy of BAR's Order menu: BAR's own has no droidCells; Kailil, 2026-11-03: online "like offline")
	check("the app's order menu runs in BAR's game", WG.ordermenu ~= nil and WG.ordermenu.droidCells ~= nil)
	check("the pad's orders hidden: the rest fill the order menu, one cell each", evenOrders > 0, evenOrders)
	check("L3 and R3: the next, then the last order gone (3, 2, 1)", has(counts, 3, 2, 1), table.concat(counts, " "))
	check("LB + Y: a patrol at the middle, with no second press", patrol)
	check("RB + D-pad down: every combat unit, no commander", allCombat >= 3, allCombat)
	check("RB + D-pad right: the combat units on the screen", onScreen >= 1, onScreen)
	check("Back + R3 + L3 held: self-destruct", selfD)
	check("RB + D-pad up held: a ping", myPing)
	check("RB + D-pad up: the camera at the last ping", jumped)
	check("LB + B: the factory's queue gone", labQueued and labCleared, tostring(labQueued) .. " " .. tostring(labCleared))
	check("LB + Y on a building, which has no patrol: no click, it stays selected", solarKept and solarNote == "NOT FOR THESE UNITS", solarNote)
	check("LB + A held on it: no path drawn, it stays selected", solarKept and solarHeld)
	WG.BarDroidPadFP.toggle()
	local _, fpNote = WG.BarDroidPad.note()
	-- (the app's widgets loaded as the game's, pad-test.ps1 -Engine: first person works; the building selected says so)
	check("LB + L3 held: first person off in this game (or, as the game's widget, not on this building)",
		fpNote == "FIRST PERSON OFF IN THIS GAME" or fpNote == "NOT ON THIS BUILDING", fpNote)
	-- RB + D-pad up again and again (Kailil, 2026-11-05): the last pings, newest first, round again; after a pause the
	-- newest (three more pings from others: four with the test's first)
	for i = 1, 3 do
		WG.BarDroidPad.setPing(PING[1] + 300 * i, 0, PING[2])
	end
	local seen = {}
	for _ = 1, 5 do
		WG.BarDroidPad.act("ping_look")
		local _, n = WG.BarDroidPad.note()
		seen[#seen + 1] = n
	end
	check("RB + D-pad up pressed on: the last pings, newest first, round again",
		table.concat(seen, ",") == "PING 1 OF 4,PING 2 OF 4,PING 3 OF 4,PING 4 OF 4,PING 1 OF 4", table.concat(seen, ","))
	pauseFrom = Spring.GetTimer() -- (the pause: widget:Update, which then says done)
end

function widget:Update()
	if not pauseFrom or Spring.DiffTimers(Spring.GetTimer(), pauseFrom) < 2.5 then
		return
	end
	pauseFrom = nil
	WG.BarDroidPad.act("ping_look") -- (2: the next older after the round's first)
	WG.BarDroidPad.act("ping_look")
	local _, n = WG.BarDroidPad.note()
	check("... and after a pause the newest first again, then the next", n == "PING 2 OF 4", n)
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
	local o = WG.ordermenu
	if WG.BarDroidPadOrders and o and o.droidCells then -- (BAR's grid has at least 16 cells, the even layout one an order)
		local rects, cmds = o.droidCells()
		if #cmds > 0 and #rects == #cmds then
			evenOrders = math.max(evenOrders, #cmds)
		end
	end
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
	-- then a building, which has no patrol, for the pad's last LB + Y (only now: the self-destructs would take it too)
	if labCleared and solarStep == 0 then
		solarStep, solarAt = 1, f
		Spring.SendCommands("give 1 armsolar")
	elseif solarStep == 1 and f >= solarAt + 2 then -- (selected as soon as it stands: the pad's script keeps its own clock)
		for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID())) do
			if UnitDefs[Spring.GetUnitDefID(unitID)].name == "armsolar" then
				solar = unitID
			end
		end
		if solar then
			solarStep = 2
			Spring.SelectUnitArray({ solar })
		end
	elseif solarStep == 2 and select(2, WG.BarDroidPad.note()) == "NOT FOR THESE UNITS" then
		solarStep = 3
		solarNote = "NOT FOR THESE UNITS"
		solarNotes = select(3, WG.BarDroidPad.note())
	elseif solarStep == 3 and select(3, WG.BarDroidPad.note()) > solarNotes then -- (then LB + A held, the same note again)
		solarStep = 4
		solarHeld = select(2, WG.BarDroidPad.note()) == "NOT FOR THESE UNITS"
	end
	if solarStep >= 3 then
		solarKept = Spring.IsUnitSelected(solar)
	end
	local _, note = WG.BarDroidPad.note()
	onScreen = tonumber((note or ""):match("^ON SCREEN: (%d+)$")) or onScreen
	if note == "COMMANDER" and not centred then -- (a random start: at a map's edge the pad's pans and orders stayed on the commander)
		centred = true
		Spring.SetCameraTarget(Game.mapSizeX / 2, 0, Game.mapSizeZ / 2, 0)
	end
	-- (the lab's queue seen and gone, and the solar's step: a run that never finished on a hot phone did not say which)
	local trace = string.format("orders %s, selected %d, focus %s, input %s, padonly %s, note %s, lab %s/%s, solar %d",
		tostring(count), #selected, tostring(focus), tostring(WG.BarDroidInput), tostring(WG.BarDroidPadOnly), tostring(note),
		tostring(labQueued), tostring(labCleared), solarStep)
	if trace ~= lastTrace then
		lastTrace = trace
		say("[padtest] f" .. f .. " " .. trace)
	end
	if (seenPad and WG.BarDroidPadOnly == nil and solarStep == 4) or f > READY_FRAME + 2400 then
		finish()
	end
end
