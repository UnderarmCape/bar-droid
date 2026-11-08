-- LuaUI widget for tools/pad-test.ps1 -Share: the pad's share list with metal and energy (Kailil, 2026-11-08: "expand
-- the share units interface to also be able tk send power and metal to your teammates"). A skirmish has no teammate,
-- so the list is opened on the AI's team standing in for two (WG.BarDroidPad.shareTest), driven by its actions as the
-- pad sends them (LB / RB what, D-pad left / right how much, A gives, B cancels), and Spring.ShareResources is recorded
-- here instead of sent. A screenshot of the list goes to screenshots/ (pad-test.ps1 copies it to build\). Logs
-- "[padtest] PASS|FAIL <case>" and "[padtest] done".
function widget:GetInfo()
	return { name = "BAR Droid pad share test", desc = "The share list's metal and energy", author = "BAR Droid", layer = 0, enabled = true }
end

local READY_FRAME = 420
local STEP = 20 -- frames between the steps (the list is drawn in between)
local fails, step, nextAt = 0, 0, nil
local other, calls, realShare, realRes = nil, {}, nil, nil
-- the stand-in's stock as an ally's reads (an enemy's reads nil): current, storage, share slider. Metal: 200 of 1000
-- at a 50 % slider, so room for 300, as BAR's "Prevent Excessive Share" counts it
local fake = { metal = { 200, 1000, 0.5 }, energy = { 0, 1000, 1 } }
local owner, realUnitTeam = {}, nil -- made-up units' teams (Spring.GetUnitTeam), for what BAR did with units given
local dead, realTeamInfo = {}, nil -- teams said to be out of the game (Spring.GetTeamInfo's isDead)

local function say(text)
	Spring.Echo(text)
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	say("[padtest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end

local function pad()
	return WG.BarDroidPad
end

local function state()
	local mode, _, _, _, index, count, _, _, tab, amountStep = pad().modal()
	return mode, index, count, tab, amountStep
end

local function open()
	pad().shareTest({
		{ teamID = other, name = "ALPHA", color = { 0.35, 0.75, 1 } },
		{ teamID = other, name = "BRAVO", color = { 1, 0.45, 0.4 } },
	})
end

-- a give: the call recorded, or the note said instead (their storage full, nothing to give)
local function gave(res)
	local amount, want, room = pad().shareAmount()
	local before = #calls
	pad().act("share_confirm")
	local c = calls[#calls]
	local _, note = pad().note()
	if (want or 0) >= 1 and (room or 0) >= 1 then
		return #calls == before + 1 and c[1] == other and c[2] == res and c[3] == amount,
			string.format("%s %s, wanted %s, room %s", tostring(c and c[2]), tostring(c and c[3]), tostring(want), tostring(room))
	end
	return #calls == before and note ~= nil, tostring(note)
end

local STEPS = {
	function()
		Spring.SelectUnitArray({})
		open()
		local mode, index, count, tab = state()
		check("the list opens with no unit selected, on a resource", mode == "share" and count == 2 and tab == 2,
			string.format("%s %s/%s tab %s", tostring(mode), tostring(index), tostring(count), tostring(tab)))
	end,
	function()
		pad().act("share_down")
		pad().act("share_more")
		pad().act("share_more")
		local _, index, _, tab, amountStep = state()
		check("D-pad down: the next teammate; D-pad right twice: more", index == 2 and tab == 2 and amountStep == 4,
			string.format("teammate %s, tab %s, step %s", tostring(index), tostring(tab), tostring(amountStep)))
	end,
	function()
		-- (the list as the step before left it: a screenshot takes the frame drawn last, so one at the end of that
		-- step showed the list from before its actions, 2026-11-08)
		Spring.SendCommands("screenshot png")
		local amount, want, room = pad().shareAmount()
		check("their room ends at their share slider (200 of 1000 at 50 %: 300)", room == 300 and amount == math.min(want, 300),
			string.format("amount %s, wanted %s, room %s", tostring(amount), tostring(want), tostring(room)))
		local ok, detail = gave("metal")
		check("A on METAL: BAR's share of metal, at most their room", ok, detail)
		check("... and the list closes", state() == nil)
	end,
	function()
		open()
		pad().act("share_tab_next")
		pad().act("share_less")
		local _, _, _, tab, amountStep = state()
		check("RB: ENERGY, the amount kept from the last time, D-pad left: less", tab == 3 and amountStep == 3,
			string.format("tab %s, step %s", tostring(tab), tostring(amountStep)))
	end,
	function()
		Spring.SendCommands("screenshot png") -- (the ENERGY list, as above)
		local ok, detail = gave("energy")
		check("A on ENERGY: BAR's share of energy", ok, detail)
	end,
	function()
		open() -- (on ENERGY, the last one used)
		pad().act("share_tab_next") -- (round to UNITS)
		local _, _, _, tab = state()
		local before = #calls
		pad().act("share_confirm")
		local mode = state()
		local _, note = pad().note()
		check("UNITS with none selected: A says so and the list stays", tab == 1 and mode == "share" and #calls == before,
			string.format("tab %s, mode %s, note %s", tostring(tab), tostring(mode), tostring(note)))
		pad().act("share_tab_prev")
		pad().act("share_less")
		pad().act("share_less")
		pad().act("share_less")
		pad().act("share_less")
		local _, _, _, tab2, amountStep = state()
		check("LB back round to ENERGY; the amount stops at a tenth", tab2 == 3 and amountStep == 1,
			string.format("tab %s, step %s", tostring(tab2), tostring(amountStep)))
		local before2 = #calls
		pad().act("share_cancel")
		check("B cancels, nothing given", state() == nil and #calls == before2)
	end,
	-- a note while the list is open (A on UNITS with none selected): beside the list, not across its rows
	function()
		open()
		for _ = 1, 3 do
			if select(4, state()) == 1 then
				break
			end
			pad().act("share_tab_next")
		end
		pad().act("share_confirm")
	end,
	function()
		Spring.SendCommands("screenshot png") -- (the list with its note, as drawn by now)
		local r, t = pad().shareRect(), pad().toastRect()
		check("a note while the list is open: beside it, not across its rows", r ~= nil and t ~= nil
			and (t[1] >= r[4] or t[2] <= r[2]),
			r and t and string.format("note %d-%d, list %d-%d", t[1], t[2], r[2], r[4]) or "nothing drawn")
		pad().act("share_cancel")
	end,
	function()
		fake.metal = { 500, 1000, 0.5 } -- (at their slider: BAR refuses any more)
		open()
		for _ = 1, 3 do
			if select(4, state()) == 2 then
				break
			end
			pad().act("share_tab_prev")
		end
		local before = #calls
		pad().act("share_confirm")
		local _, note = pad().note()
		check("METAL at their slider already: A says their storage is full, nothing given",
			#calls == before and state() == nil and note ~= nil and note:find("FULL") ~= nil, tostring(note))
		-- units given, what BAR did with them after (made-up units: 1 went over, 2 and 3 stayed)
		owner = { [900001] = other, [900002] = Spring.GetMyTeamID(), [900003] = Spring.GetMyTeamID() }
		pad().shareGiven({ 900001 }, other)
	end,
	function()
		local _, note = pad().note()
		check("units given and gone over: no note after", note == nil or not (note:find("KEPT") or note:find("NOT GIVEN")),
			tostring(note))
		pad().shareGiven({ 900001, 900002, 900003 }, other)
	end,
	function()
		local _, note = pad().note()
		check("some kept by BAR: it says how many went", note == "GAVE 1 OF 3: THIS GAME KEPT THE REST", tostring(note))
		pad().shareGiven({ 900002, 900003 }, other)
	end,
	function()
		local _, note = pad().note()
		check("all kept, unit sharing allowed: why it may be", note == "NOT GIVEN: PARTLY BUILT, OR THEIR UNIT LIMIT",
			tostring(note))
		-- a co-op team against Raptors: 15 teammates, the last one picked
		local many = {}
		for i = 1, 15 do
			many[i] = { teamID = other, name = "PLAYER " .. i, color = { 0.4 + i * 0.04, 0.8, 1 - i * 0.05 } }
		end
		pad().shareTest(many)
		for _ = 1, 14 do
			pad().act("share_down")
		end
	end,
	function()
		Spring.SendCommands("screenshot png") -- (the long list, as drawn by now)
		local r = pad().shareRect()
		local _, vsy = Spring.GetViewGeometry()
		local _, index = state()
		check("15 teammates: the list stays on the screen under BAR's top bar, the one picked in sight", r ~= nil
			and r[2] >= 0 and r[4] <= r[7] and r[7] <= vsy and index == 15 and r[5] <= 15 and 15 <= r[5] + r[6] - 1,
			r and string.format("y %d-%d, top bar from %d of %d, rows %d-%d, picked %s", r[2], r[4], r[7], vsy, r[5],
				r[5] + r[6] - 1, tostring(index)))
		pad().act("share_cancel")
		-- a teammate out of the game since the list opened (their team dead, as BAR's GetTeamInfo says)
		open()
		dead[other] = true
	end,
	function()
		local before = #calls
		pad().act("share_confirm")
		local _, note = pad().note()
		dead[other] = nil
		check("A on a teammate out of the game: says so, nothing given, the list made again (none here: closed)",
			#calls == before and note == "ALPHA IS OUT OF THE GAME" and state() == nil, tostring(note))
	end,
}

function widget:GameFrame(f)
	if f == READY_FRAME then
		local mine = Spring.GetMyTeamID()
		for _, teamID in ipairs(Spring.GetTeamList() or {}) do
			local _, _, isDead = Spring.GetTeamInfo(teamID, false)
			if teamID ~= mine and not isDead and teamID ~= Spring.GetGaiaTeamID() then
				other = teamID
				break
			end
		end
		if not (pad() and pad().shareTest and other) then
			say("[padtest] FAIL no pad widget or no other team: " .. tostring(other))
			say("[padtest] done: 1 FAILED")
			step = #STEPS + 1
			return
		end
		realShare = Spring.ShareResources
		Spring.ShareResources = function(...)
			calls[#calls + 1] = { ... }
		end
		realTeamInfo = Spring.GetTeamInfo
		Spring.GetTeamInfo = function(teamID, ...)
			if dead[teamID] then
				local r = { realTeamInfo(teamID, ...) }
				r[3] = true
				return unpack(r)
			end
			return realTeamInfo(teamID, ...)
		end
		realUnitTeam = Spring.GetUnitTeam
		Spring.GetUnitTeam = function(unitID, ...)
			if owner[unitID] then
				return owner[unitID]
			end
			return realUnitTeam(unitID, ...)
		end
		realRes = Spring.GetTeamResources
		Spring.GetTeamResources = function(teamID, res, ...)
			local s = teamID == other and fake[res]
			if s then
				return s[1], s[2], 0, 0, 0, s[3], 0, 0
			end
			return realRes(teamID, res, ...)
		end
		say("[padtest] ready, the stand-in teammate: team " .. other)
		nextAt = f + STEP
		return
	end
	if not nextAt or f < nextAt or step > #STEPS then
		return
	end
	step = step + 1
	if STEPS[step] then
		local ok, err = pcall(STEPS[step])
		if not ok then
			check("step " .. step .. " ran", false, err)
		end
		nextAt = f + STEP
	end
	if step >= #STEPS then
		Spring.ShareResources = realShare
		Spring.GetTeamResources = realRes
		Spring.GetUnitTeam = realUnitTeam
		Spring.GetTeamInfo = realTeamInfo
		step = #STEPS + 1
		say("[padtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
	end
end

function widget:Shutdown()
	if realShare then
		Spring.ShareResources = realShare
	end
	if realRes then
		Spring.GetTeamResources = realRes
	end
	if realUnitTeam then
		Spring.GetUnitTeam = realUnitTeam
	end
	if realTeamInfo then
		Spring.GetTeamInfo = realTeamInfo
	end
end
