-- LuaUI widget for tools/pregame-phone-test.ps1: the touch dock's faction buttons before the start (bardroid_portrait.lua
-- pregameFactions), in a skirmish the script turned into one with a pre-game (StartPosType 2, its dev-env.sh). No phone
-- test reached a pre-game, so 3104771e's guard erring at every faction tap went unseen until the in-play tour
-- (2026-11-22, 86012f7f). The script's real taps, each asked for by a line in LuaUI/Config/bardroid_pregametest.txt,
-- "do <n> tap <x> <y> <vsx>" (X screen pixels, top left origin), answered "<n>" in bardroid_pregametest_cmd.txt.
-- Checked: with nothing queued one tap on the other faction switches; with a building queued the first tap says "TAP ...
-- AGAIN TO SWITCH" and switches nothing, the second switches, the queue goes with it (the other faction's building) and
-- the note goes at once (it stood its full 3 s after the switch, the tour). "[pregametest] done: ALL PASS" or "N FAILED".
function widget:GetInfo()
	return { name = "BAR Droid pregame test", desc = "The dock's faction buttons before the start", author = "BAR Droid",
		layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_pregametest.txt", "LuaUI/Config/bardroid_pregametest_cmd.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local timer0 = Spring.GetTimer()
local function now()
	return Spring.DiffTimers(Spring.GetTimer(), timer0)
end
local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[pregametest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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
local function go(s)
	stage, stageAt = s, now()
end

local function startUnit()
	return Spring.GetTeamRulesParam(Spring.GetMyTeamID(), "startUnit")
end
-- the faction button for a start unit other than this one (not RANDOM): its cell (GL pixels) and item
local function otherFaction(than)
	local Pt = WG.BarDroidPortrait
	if not (Pt and Pt.itemCell) then
		return nil
	end
	for _, side in ipairs({ "left", "right" }) do
		local r, it = Pt.itemCell(side, function(i)
			return i.kind == "faction" and not i.random and i.startUnit ~= than
		end)
		if r then
			return r, it
		end
	end
end
local function ask(r, nextStage)
	local vsx, vsy = Spring.GetViewGeometry()
	if not r then
		check("the dock's faction button for the " .. nextStage .. " step", false, "none")
		go("end")
		return
	end
	asked = asked + 1
	write(string.format("do %d tap %d %d %d\n", asked, math.floor((r[1] + r[3]) / 2), math.floor(vsy - (r[2] + r[4]) / 2), vsx))
	after = nextStage
	go("asked")
end
local function note()
	local Pd = WG.BarDroidPad
	local toast = Pd and Pd.note and Pd.note()
	return toast
end
local function queue()
	local pb = WG["pregame-build"]
	return pb and pb.getBuildQueue and pb.getBuildQueue() or {}
end
local function name(defID)
	local ud = defID and UnitDefs[defID]
	return ud and ud.name or tostring(defID)
end

local target, noteFrom
function widget:Update()
	if Spring.GetGameFrame() > 0 and stage ~= "over" then
		check("still before the start", false, "the game started")
		stage = "end"
	end
	if stage == "wait" then
		local r = otherFaction(startUnit())
		if r and now() > 8 then -- (the dock up and settled: its first seconds' taps are dropped on purpose)
			Spring.Echo("[pregametest] the faction buttons up; the start unit " .. name(startUnit()))
			go("tap1")
		end
	elseif stage == "tap1" and now() - stageAt > 1 then
		local r, it = otherFaction(startUnit())
		target = it and it.startUnit
		ask(r, "switched1?")
	elseif stage == "switched1?" and now() - stageAt > 1.5 then
		check("nothing queued, the other faction tapped once: switched", startUnit() == target,
			"start unit " .. name(startUnit()) .. ", wanted " .. name(target))
		-- a building of this faction queued at the start box's middle
		local pb = WG["pregame-build"]
		local opts = UnitDefs[startUnit()] and UnitDefs[startUnit()].buildOptions or {}
		local x1, z1, x2, z2 = Spring.GetAllyTeamStartBox(Spring.GetMyAllyTeamID())
		local cx, cz = ((x1 or 0) + (x2 or 2000)) / 2, ((z1 or 0) + (z2 or 2000)) / 2
		local def
		for _, d in ipairs(opts) do
			local ud = UnitDefs[d]
			if not def and ud and ud.name:find("solar", 1, true) then
				def = d
			end
		end
		def = def or opts[1]
		if pb and pb.setBuildQueue and def then
			pb.setBuildQueue({ { def, cx, Spring.GetGroundHeight(cx, cz), cz, 0 } })
			if pb.forceRefresh then
				pb.forceRefresh()
			end
		end
		Spring.Echo("[pregametest] queued: " .. #queue() .. " (" .. name(def) .. ")")
		go("tap2")
	elseif stage == "tap2" and now() - stageAt > 2 then
		local r, it = otherFaction(startUnit())
		target = it and it.startUnit
		ask(r, "asked2?")
	elseif stage == "asked2?" and now() - stageAt > 0.6 then
		local t = note()
		check("a building queued, the other faction tapped once: not switched, the dock asks for a second tap",
			startUnit() ~= target and t and tostring(t):find("AGAIN TO SWITCH", 1, true) ~= nil,
			"start unit " .. name(startUnit()) .. ", note " .. tostring(t))
		noteFrom = stageAt -- (the first tap answered: its note up from about then, for 3 s)
		ask((otherFaction(startUnit())), "notegone?")
	elseif stage == "notegone?" and now() - stageAt > 0.4 then
		-- (looked at soon after the second tap, while the note's own 3 s still run: later it was gone by itself, the
		-- check passing without the switch taking it away; vacuous-pass audit, 2026-11-23)
		local t, since = note(), now() - noteFrom
		check("... tapped again: its note gone with the switch, before its own 3 s were up",
			since < 2.7 and not (t and tostring(t):find("AGAIN TO SWITCH", 1, true)),
			string.format("note %s, %.1f s after the first tap", tostring(t), since))
		go("switched2?")
	elseif stage == "switched2?" and now() - stageAt > 0.6 then
		local q = queue()
		local qd = q[1] and q[1][1]
		local prefix = name(target):sub(1, 3)
		check("... tapped again: switched, the queue with it", startUnit() == target and #q == 1
			and name(qd):sub(1, 3) == prefix, "start unit " .. name(startUnit()) .. ", queue " .. #q .. " (" .. name(qd) .. ")")
		local pb = WG["pregame-build"]
		if pb and pb.setBuildQueue then
			pb.setBuildQueue({})
		end
		go("end")
	elseif stage == "end" then
		Spring.Echo("[pregametest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
		write("end\n")
		stage = "over"
	end
	if stage == "asked" then
		local c = readCmd()
		if c and tonumber(c) == asked then
			go(after)
		elseif now() - stageAt > 30 then
			check("the script's " .. after .. " step", false, "not done in 30 s")
			go("end")
		end
	end
end
