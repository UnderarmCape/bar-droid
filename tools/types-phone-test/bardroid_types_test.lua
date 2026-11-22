-- LuaUI widget for tools/types-phone-test.ps1: a unit type left out of ALL UNITS for a while (bardroid_portrait.lua
-- SP.leftOut; Kailil, 2026-11-20: "a way to exclude a unit type temporarily from the all units commands when I press all
-- units"). In a skirmish (cheats on): three Pawns, two Blitzes and two Maces given beside the commander; then the
-- script's real taps and long presses on the dock, each asked for by a line in LuaUI/Config/bardroid_typestest.txt,
-- "do <n> tap|hold|shot <x> <y> <vsx>" (X screen pixels, top left origin), the script answering "<n>" in
-- bardroid_typestest_cmd.txt once done. Checked: ALL UNITS picks all seven; the Blitzes held: out of the pick, dimmed
-- in the list, not in ALL's count; ALL UNITS again (nothing picked first): still without them; held again: back in; the
-- Pawns and the Maces held out: the list's last type (the Blitzes) stays in when held; a plain tap on a left-out type
-- (the Pawns) picks that type alone. Then LOCAL UNITS where only a left-out type stands (two Pawns given far off, the
-- camera on them): that type back in and picked, the other left-out type (the Maces) still out under ALL UNITS (it
-- brought every left-out type back, 2026-11-20). Last, two Falcons, a Construction Aircraft and a Construction Bot given:
-- ALL UNITS and LOCAL UNITS pick the Falcons, not the constructors (RC 0.2.0, Kailil's calls' default).
-- "[typestest] done: ALL PASS" or "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid types test", desc = "ALL UNITS without a type", author = "BAR Droid", layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_typestest.txt", "LuaUI/Config/bardroid_typestest_cmd.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil -- the last action asked of the script; the stage once it is done
local DEF = {
	pawn = UnitDefNames.armpw and UnitDefNames.armpw.id,
	flash = UnitDefNames.armflash and UnitDefNames.armflash.id,
	ham = UnitDefNames.armham and UnitDefNames.armham.id,
	-- (the last case: aircraft in ALL / LOCAL UNITS, constructors out; RC 0.2.0, Kailil's calls' default)
	fig = UnitDefNames.armfig and UnitDefNames.armfig.id,
	ca = UnitDefNames.armca and UnitDefNames.armca.id,
	ck = UnitDefNames.armck and UnitDefNames.armck.id,
}

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[typestest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end
local function readCmd()
	local f = io.open(CMD_FILE, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end
local function go(s, f)
	stage, stageAt = s, f
end

-- the dock's cell an item stands in (either half), as GL pixels, and the item
local function cellOf(test)
	local Pt = WG.BarDroidPortrait
	if not (Pt and Pt.itemCell) then
		return nil
	end
	for _, side in ipairs({ "left", "right" }) do
		local r, it = Pt.itemCell(side, test)
		if r then
			return r, it
		end
	end
end
local function typeCell(d)
	return cellOf(function(it)
		return it.kind == "type" and it.defID == d
	end)
end
local function allUnitsCell()
	return cellOf(function(it)
		return it.kind == "units" and it.from == "all"
	end)
end
local function localUnitsCell()
	return cellOf(function(it)
		return it.kind == "units" and it.from == "local"
	end)
end
local home, far -- { x, z }: beside the commander; two Pawns far off
local function allCount()
	local _, it = cellOf(function(it)
		return it.kind == "alltypes"
	end)
	return it and it.count
end

-- the script asked to tap, hold or take a picture at a cell's middle; "next" the stage once it is done
local function ask(action, r, nextStage, f)
	local vsx, vsy = Spring.GetViewGeometry()
	if not r and action ~= "shot" then
		check("the dock's cell for the " .. nextStage .. " step", false, "none")
		go("end", f)
		return
	end
	asked = asked + 1
	local x, y = r and math.floor((r[1] + r[3]) / 2) or 0, r and math.floor(vsy - (r[2] + r[4]) / 2) or 0
	write(string.format("do %d %s %d %d %d\n", asked, action, x, y, vsx))
	after = nextStage
	go("asked", f)
end

-- what is picked: { pawn = n, flash = n, ham = n, total = n }
local function picked()
	local n = { pawn = 0, flash = 0, ham = 0, fig = 0, ca = 0, ck = 0, total = 0 }
	for _, u in ipairs(Spring.GetSelectedUnits() or {}) do
		local d = Spring.GetUnitDefID(u)
		for k, id in pairs(DEF) do
			if d == id then
				n[k] = n[k] + 1
			end
		end
		n.total = n.total + 1
	end
	return n
end
local function pickText(n)
	return string.format("%d Pawns, %d Blitzes, %d Maces (%d picked)", n.pawn, n.flash, n.ham, n.total)
end
local function outOf(d)
	local _, it = typeCell(d)
	return it and it.out or false
end

local WAIT = 40 -- frames after an action before its check

function widget:GameFrame(f)
	if stage == "wait" and f >= 300 then
		Spring.SendCommands("cheat 1") -- (the give a second later: in the same frame it came to nothing)
		go("cheat", f)
	elseif stage == "cheat" and f - stageAt > 30 then
		local team = Spring.GetMyTeamID()
		local com = (Spring.GetTeamUnits(team) or {})[1]
		local x, y, z = Spring.GetUnitPosition(com)
		home = { x, z }
		Spring.SendCommands(string.format("give 3 armpw %d @%d,%d,%d", team, x + 200, y, z))
		Spring.SendCommands(string.format("give 2 armflash %d @%d,%d,%d", team, x + 260, y, z + 90))
		Spring.SendCommands(string.format("give 2 armham %d @%d,%d,%d", team, x + 200, y, z + 180))
		Spring.Echo("[typestest] three Pawns, two Blitzes and two Maces given beside the commander")
		go("given", f)
	elseif stage == "given" and f - stageAt > 60 then
		Spring.SelectUnitArray({})
		go("home", f)
	elseif stage == "home" and f - stageAt > 15 then
		ask("tap", (allUnitsCell()), "all?", f)
	elseif stage == "all?" and f - stageAt > WAIT then
		local n = picked()
		check("ALL UNITS tapped: every combat unit picked", n.pawn == 3 and n.flash == 2 and n.ham == 2, pickText(n))
		ask("hold", (typeCell(DEF.flash)), "flashout?", f)
	elseif stage == "flashout?" and f - stageAt > WAIT then
		local n = picked()
		check("the Blitzes held in the list: out of ALL's pick, the rest still picked",
			n.flash == 0 and n.pawn == 3 and n.ham == 2, pickText(n))
		check("the Blitzes held: dimmed in the list, not in ALL's count", outOf(DEF.flash) and allCount() == 5,
			"left out " .. tostring(outOf(DEF.flash)) .. ", ALL " .. tostring(allCount()))
		ask("shot", nil, "shotdone", f)
	elseif stage == "shotdone" then
		Spring.SelectUnitArray({}) -- (the list closes with nothing picked: the home grid's ALL UNITS again)
		go("home2", f)
	elseif stage == "home2" and f - stageAt > 15 then
		ask("tap", (allUnitsCell()), "allagain?", f)
	elseif stage == "allagain?" and f - stageAt > WAIT then
		local n = picked()
		check("ALL UNITS again: the Blitzes still left out", n.flash == 0 and n.pawn == 3 and n.ham == 2, pickText(n))
		check("ALL UNITS again: the Blitzes still dimmed", outOf(DEF.flash), outOf(DEF.flash))
		ask("hold", (typeCell(DEF.flash)), "flashin?", f)
	elseif stage == "flashin?" and f - stageAt > WAIT then
		local n = picked()
		check("the Blitzes held again: back in ALL's pick", n.flash == 2 and n.pawn == 3 and n.ham == 2, pickText(n))
		check("the Blitzes held again: not dimmed, in ALL's count", not outOf(DEF.flash) and allCount() == 7,
			"left out " .. tostring(outOf(DEF.flash)) .. ", ALL " .. tostring(allCount()))
		ask("hold", (typeCell(DEF.pawn)), "pawnout?", f)
	elseif stage == "pawnout?" and f - stageAt > WAIT then
		local n = picked()
		check("the Pawns held: out", n.pawn == 0 and n.flash == 2 and n.ham == 2, pickText(n))
		ask("hold", (typeCell(DEF.ham)), "hamout?", f)
	elseif stage == "hamout?" and f - stageAt > WAIT then
		local n = picked()
		check("the Maces held: out, only the Blitzes picked", n.ham == 0 and n.pawn == 0 and n.flash == 2, pickText(n))
		ask("hold", (typeCell(DEF.flash)), "laststays?", f)
	elseif stage == "laststays?" and f - stageAt > WAIT then
		local n = picked()
		check("the list's last type held: it stays in, still picked", not outOf(DEF.flash) and n.flash == 2 and n.total == 2,
			pickText(n) .. ", left out " .. tostring(outOf(DEF.flash)))
		ask("tap", (typeCell(DEF.pawn)), "pawntap?", f)
	elseif stage == "pawntap?" and f - stageAt > WAIT then
		local n = picked()
		check("a left-out type tapped: that type alone picked", n.pawn == 3 and n.total == 3, pickText(n))
		-- (now the Pawns and the Maces are left out: two Pawns far off, the map's other side, and the camera on them)
		local mx, mz = Game.mapSizeX, Game.mapSizeZ
		far = { home[1] > mx / 2 and math.max(400, home[1] - 3500) or math.min(mx - 400, home[1] + 3500),
			home[2] > mz / 2 and math.max(400, home[2] - 2500) or math.min(mz - 400, home[2] + 2500) }
		local team = Spring.GetMyTeamID()
		Spring.SendCommands(string.format("give 2 armpw %d @%d,%d,%d", team, far[1], Spring.GetGroundHeight(far[1], far[2]),
			far[2]))
		Spring.SelectUnitArray({})
		go("farpawns", f)
	elseif stage == "farpawns" and f - stageAt > 45 then
		local Pt = WG.BarDroidPortrait
		Pt.cameraTo(far[1], Spring.GetGroundHeight(far[1], far[2]), far[2])
		go("localtap", f)
	elseif stage == "localtap" and f - stageAt > 45 then
		Spring.Echo(string.format("[typestest] two Pawns given far off at %d,%d, the camera on them", far[1], far[2]))
		ask("tap", (localUnitsCell()), "local?", f)
	elseif stage == "local?" and f - stageAt > WAIT then
		local n = picked()
		check("LOCAL UNITS with only a left-out type there: that type back in, picked", n.pawn == 2 and n.total == 2
			and not outOf(DEF.pawn), pickText(n) .. ", Pawns left out " .. tostring(outOf(DEF.pawn)))
		Spring.SelectUnitArray({})
		local Pt = WG.BarDroidPortrait
		Pt.cameraTo(home[1], Spring.GetGroundHeight(home[1], home[2]), home[2])
		go("home3", f)
	elseif stage == "home3" and f - stageAt > 45 then
		ask("tap", (allUnitsCell()), "macesstill?", f)
	elseif stage == "macesstill?" and f - stageAt > WAIT then
		local n = picked()
		check("... and ALL UNITS after it: the Maces, not in that list, still left out", outOf(DEF.ham) and n.ham == 0
			and n.pawn == 5 and n.flash == 2, pickText(n) .. ", Maces left out " .. tostring(outOf(DEF.ham)))
		-- (aircraft in ALL and LOCAL UNITS, constructors kept out: two Falcons, a Construction Aircraft and a Construction
		-- Bot given beside the commander)
		local team = Spring.GetMyTeamID()
		local y = Spring.GetGroundHeight(home[1], home[2])
		Spring.SendCommands(string.format("give 2 armfig %d @%d,%d,%d", team, home[1] - 200, y, home[2]))
		Spring.SendCommands(string.format("give 1 armca %d @%d,%d,%d", team, home[1] - 200, y, home[2] + 120))
		Spring.SendCommands(string.format("give 1 armck %d @%d,%d,%d", team, home[1] - 120, y, home[2] + 200))
		Spring.SelectUnitArray({})
		go("airgiven", f)
	elseif stage == "airgiven" and f - stageAt > 60 then
		Spring.SelectUnitArray({})
		go("home4", f)
	elseif stage == "home4" and f - stageAt > 15 then
		ask("tap", (allUnitsCell()), "airall?", f)
	elseif stage == "airall?" and f - stageAt > WAIT then
		local n = picked()
		check("ALL UNITS: the Falcons in, the Construction Aircraft and Bot out", n.fig == 2 and n.ca == 0 and n.ck == 0
			and n.pawn == 5 and n.flash == 2, string.format("%s; %d Falcons, %d Construction Aircraft, %d Construction Bots",
				pickText(n), n.fig, n.ca, n.ck))
		Spring.SelectUnitArray({})
		go("home5", f)
	elseif stage == "home5" and f - stageAt > 15 then
		ask("tap", (localUnitsCell()), "airlocal?", f)
	elseif stage == "airlocal?" and f - stageAt > WAIT then
		local n = picked()
		check("LOCAL UNITS: the Falcons in, the Construction Aircraft and Bot out", n.fig == 2 and n.ca == 0 and n.ck == 0,
			string.format("%s; %d Falcons, %d Construction Aircraft, %d Construction Bots", pickText(n), n.fig, n.ca, n.ck))
		go("end", f)
	elseif stage == "end" then
		Spring.Echo("[typestest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		write("end\n")
		go("over", f)
	end
	if stage == "asked" and f % 3 == 0 then
		local c = readCmd()
		if c and tonumber(c) == asked then
			go(after, f)
		elseif f - stageAt > 30 * 30 then
			check("the script's " .. after .. " step", false, "not done in 30 s")
			go("end", f)
		end
	end
end
