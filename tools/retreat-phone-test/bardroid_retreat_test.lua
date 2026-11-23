-- LuaUI widget for tools/retreat-phone-test.ps1: auto retreat (bardroid_retreat.lua) for every kind of combat unit, by
-- repeatable fights (Kailil, 2026-11-20: "Make sure auto retreat issues working for all combat units. Actually test it.
-- Like make a test scenario ... an enemy unit attacking our unit or formation ... Something easily repeating to allow the
-- most repetition for your data and trial and error."). In a skirmish (cheats on, AUTO RETREAT on): a round for each
-- kind (a bot, a vehicle, a hover, an amphibious one, a T2 one, a squad of four Pawns), each at a new place out from my
-- start: two of that kind (the squad four), an enemy pack (the AI's team) given 260 elmos further out. Each of
-- my units watched every frame: hurt (under the retreat's 50 %) alive; fell back (a move order within a second of it,
-- the retreat's "falls back"); got clear (300 elmos further from the enemy's nearest unit within 10 s, or 1500 away); turned back (after getting clear, back within 150 elmos of an enemy before the round ends); died before
-- falling back (killed within a second of being hurt: no time) or after. Per kind and in all; "[retreattest] done".
function widget:GetInfo()
	return { name = "BAR Droid retreat test", desc = "Auto retreat by repeatable fights", author = "BAR Droid", layer = 0,
		enabled = true }
end

local ROUND_SECONDS = 20
-- one kind a round, the first of each list this game has (all kinds at once: the enemy shot the Pawns and the hovers,
-- the rest never came under half, dev phone 2026-11-20); n of it, and the enemy pack against it
-- (14 Grunts: at 10 the Rocketeers won at range unhurt, lowest health 78 %)
local KINDS = {
	{ "bot", { "armrock", "armham" }, 2, { corak = 14 } },
	{ "vehicle", { "armstump", "armflash" }, 2, { corak = 14 } },
	{ "hover", { "armsh", "armanac", "armmh" }, 2, { corak = 14 } },
	{ "amphibious", { "armpincer", "armcroc" }, 2, { corak = 14 } },
	{ "T2", { "armzeus", "armfido", "armbull" }, 2, { corak = 14, corcan = 3 } },
	{ "squad", { "armpw" }, 4, { corak = 14 } },
}
-- each kind twice: AUTO RETREAT on, then off, the same fight (does the retreat keep units alive? 5 of the first run's 8
-- that fell back died anyway, chased down)
local ROUNDS = #KINDS * 2
-- (one kind only, LuaUI/Config/bardroid_retreattest_only.txt "hover": its on and off rounds three times, each unit
-- that falls back followed for its first 3 s: the Skaters died with and without the retreat, 2026-11-20)
local only
local function onlyKind()
	local fh = io.open("LuaUI/Config/bardroid_retreattest_only.txt", "r")
	local s = fh and fh:read("*l")
	if fh then
		fh:close()
	end
	for _, k in ipairs(KINDS) do
		if s and k[1] == s then
			KINDS, ROUNDS = { k, k, k }, 6
			return s
		end
	end
end
local roundKind -- this round's { name, def, on }
local minHealth -- this round's lowest health share among mine
local versus = {} -- kind -> { on = { n, alive, enemies, foes, minH }, off = ... }
local stage, stageAt, round = "wait", 0, 0
local me, foe, home
local watched = {} -- unitID -> { kind, hurtAt, fellAt, clearAt, turned, died, round }
local stats = {} -- kind -> counters

local function enemyTeam()
	for _, t in ipairs(Spring.GetTeamList() or {}) do
		if t ~= Spring.GetGaiaTeamID() and not Spring.AreTeamsAllied(t, me) then
			return t
		end
	end
end
local function go(s, f)
	stage, stageAt = s, f
end
local function stat(kind)
	stats[kind] = stats[kind] or { units = 0, hurt = 0, fell = 0, clear = 0, turned = 0, diedFirst = 0, diedAfter = 0,
		slow = 0, early = 0 }
	return stats[kind]
end
-- the nearest enemy unit to a point and its distance (all of them, seen or not: the test's own view)
local function nearestEnemy(x, z)
	local best, bd = nil, math.huge
	for _, u in ipairs(Spring.GetTeamUnits(foe) or {}) do
		local ux, _, uz = Spring.GetUnitPosition(u)
		if ux then
			local d = math.sqrt((ux - x) ^ 2 + (uz - z) ^ 2)
			if d < bd then
				best, bd = u, d
			end
		end
	end
	return best, bd
end

function widget:UnitCreated(unitID, unitDefID, teamID)
	-- (this round's kind, given a few frames after the round began)
	if teamID == me and roundKind and unitDefID == roundKind.def then
		watched[unitID] = { kind = roundKind.name, round = round, born = Spring.GetGameFrame() }
		if roundKind.on then
			stat(roundKind.name).units = stat(roundKind.name).units + 1
		end
	end
end

function widget:UnitDestroyed(unitID)
	local w = watched[unitID]
	if w and not w.died then
		w.died = Spring.GetGameFrame()
		-- (the retreat's numbers: its own round with the retreat on only; those sent home after it died in later rounds'
		-- fights, counted as dying after)
		if not (w.round == round and roundKind and roundKind.on and stage == "fight") then
			return
		end
		local s = stat(w.kind)
		if w.hurtAt and not w.fellAt then
			s.diedFirst = s.diedFirst + 1
		elseif w.fellAt then
			s.diedAfter = s.diedAfter + 1
		end
	end
end

-- each watched unit this frame: its health, its orders, how far the enemy is
local function watch(f)
	for u, w in pairs(watched) do
		if not w.died and w.round == round then
			local h, mh = Spring.GetUnitHealth(u)
			local x, _, z = Spring.GetUnitPosition(u)
			if h and mh and x and f - (w.born or 0) > 15 then -- (a unit just given read 0 % for a frame)
				minHealth = math.min(minHealth or 1, h / mh)
			end
			if h and mh and x and roundKind and roundKind.on then -- (the retreat's own numbers: its rounds only)
				local s = stat(w.kind)
				if not w.hurtAt and h / mh < 0.5 then
					w.hurtAt = f
					s.hurt = s.hurt + 1
					local _, d = nearestEnemy(x, z)
					w.enemyDist = d
				end
				if not w.fellAt then -- (the retreat's own word: a move order counted 14 where it gave 11)
					local R = WG.BarDroidRetreat
					if R and R.fell and R.fell(u) then
						w.fellAt, w.fellX, w.fellZ, w.fellH = f, x, z, h / mh
						s.fell = s.fell + 1
						if not w.hurtAt then -- (above half: losing health fast, the retreat's DOOMED rule)
							s.early = s.early + 1
							local _, d = nearestEnemy(x, z)
							w.enemyDist = d
						elseif f - w.hurtAt > 30 then
							s.slow = s.slow + 1
						end
					end
				end
				if w.fellAt and not w.went and f - w.fellAt >= 90 then -- (how far it got in the 3 s after falling back)
					w.went = math.sqrt((x - w.fellX) ^ 2 + (z - w.fellZ) ^ 2)
					s.went = (s.went or 0) + w.went
					s.wentN = (s.wentN or 0) + 1
					if only then -- (and how: its order, the point reachable for it, its speed, the enemy's distance)
						local c = (Spring.GetUnitCommands(u, 1) or {})[1]
						local tx, tz = c and c.id == CMD.MOVE and c.params[1], c and c.id == CMD.MOVE and c.params[3]
						local reach = tx and Spring.TestMoveOrder(Spring.GetUnitDefID(u), tx, Spring.GetGroundHeight(tx, tz), tz)
						local vx, _, vz = Spring.GetUnitVelocity(u)
						local _, ed = nearestEnemy(x, z)
						Spring.Echo(string.format("[retreattest] (%s %d: fell back at %.0f %%, %.0f elmos in 3 s, %.0f elmos/s now, "
							.. "%.0f %% health, the enemy %.0f away, its order %s%s)", w.kind, u, 100 * (w.fellH or 0), w.went,
							vx and math.sqrt(vx * vx + vz * vz) * 30 or 0, 100 * h / mh, ed, c and tostring(c.id) or "none",
							tx and string.format(" to %d,%d (%d away, reachable %s)", tx, tz, math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2),
								tostring(reach)) or ""))
					end
				end
				if w.fellAt and not w.clearAt and f - w.fellAt <= 30 * 10 then -- (the T2 bot walks ~30 elmos a second)
					local _, d = nearestEnemy(x, z)
					if d >= (w.enemyDist or 0) + 300 or d > 1500 then
						w.clearAt = f
						s.clear = s.clear + 1
					end
				end
				if w.clearAt and not w.turned then
					local _, d = nearestEnemy(x, z)
					if d < 150 then
						w.turned = f
						s.turned = s.turned + 1
						local c = (Spring.GetUnitCommands(u, 1) or {})[1]
						Spring.Echo(string.format("[retreattest] (%s %d turned back into the fight %.1f s after getting clear; "
							.. "its order: %s, health %.0f %%)", w.kind, u, (f - w.clearAt) / 30, c and tostring(c.id) or "none",
							100 * h / mh))
					end
				end
			end
		end
	end
end

-- The commander's case (bardroid_retreattest_only.txt "commander", retreat-phone-test.ps1 -Commander), as the
-- coordinator's tour played it (2026-11-22): the D-gun mode entered and left (the dock's X: the pad's dgun_cancel), the
-- commander let go, the game paused 12 s, then two enemy Bulldogs and the fight in 1 s steps between 6 s pauses. Checked:
-- not read as catching up after a pause (WG.BarDroidCatchingUp; the pause counted as ground lost dropped every hit);
-- the commander retreats within a second of going under half; then the player's Fight back into them: under 30 % the
-- dock's note "COMMANDER AT n %: PULL IT BACK" (and the infolog's "told").
local cm -- the commander case's state
local function pass(case, ok, detail)
	cm.fails = cm.fails + (ok and 0 or 1)
	Spring.Echo("[retreattest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail and (": " .. detail) or ""))
end
local function healthOf(u)
	local h, mh = Spring.GetUnitHealth(u)
	return h and mh and mh > 0 and h / mh or nil
end
local function pauseNow(on)
	local _, _, paused = Spring.GetGameSpeed()
	if (paused and true or false) ~= on then
		Spring.SendCommands("pause")
	end
end
local function commanderFrame(f)
	local R, Pd = WG.BarDroidRetreat, WG.BarDroidPad
	if cm.stage == "start" then
		for _, u in ipairs(Spring.GetTeamUnits(me) or {}) do
			local ud = UnitDefs[Spring.GetUnitDefID(u) or -1]
			if ud and ud.customParams and ud.customParams.iscommander then
				cm.com = u
			end
		end
		if not (cm.com and Pd and Pd.act and Pd.modal) then
			pass("the commander and the pad's D-gun mode", false, "commander " .. tostring(cm.com))
			cm.stage = "done"
			return
		end
		Spring.SelectUnitArray({ cm.com })
		cm.stage, cm.at = "enter", f
	elseif cm.stage == "enter" and f - cm.at > 15 then
		Pd.act("dgun")
		cm.stage, cm.at = "leave", f
	elseif cm.stage == "leave" and f - cm.at > 30 then
		local mode = Pd.modal()
		Pd.act("dgun_cancel")
		Spring.SelectUnitArray({})
		Spring.Echo(string.format("[retreattest] the D-gun mode entered (%s) and left (%s), the commander let go", tostring(mode),
			tostring(Pd.modal())))
		cm.stage, cm.at = "pause", f
	elseif cm.stage == "pause" and f - cm.at > 15 then
		cm.pausedAt, cm.pauseFor, cm.after = Spring.GetTimer(), 12, "fightstart"
		cm.stage = "paused"
		pauseNow(true)
	elseif cm.stage == "resumed" then
		cm.stage, cm.at = cm.after, f
		if cm.after == "fightstart" then
			cm.stage, cm.firstAt = "fight", f
		end
	elseif cm.stage == "fight" and cm.firstAt and f - cm.firstAt >= 40 then -- (past the touch widget's next second's check)
		local C = WG.BarDroidCatchingUp
		local up = C and C()
		pass("12 s paused, then running: not read as catching up", C ~= nil and not up, "catching up " .. tostring(up))
		cm.firstAt = nil
		local x, _, z = Spring.GetUnitPosition(cm.com)
		local ex, ez = x + 260, z
		cm.ex, cm.ez = ex, ez
		Spring.SendCommands(string.format("give 2 armbull %d @%d,%d,%d", foe, ex, Spring.GetGroundHeight(ex, ez), ez))
		Spring.Echo(string.format("[retreattest] two Bulldogs given to the enemy by the commander at %d %%, the fight in 1 s "
			.. "steps between 6 s pauses", math.floor(100 * (healthOf(cm.com) or 0))))
		cm.stepAt, cm.steps = f, 0
	elseif cm.stage == "fight" and cm.stepAt then
		local h = healthOf(cm.com)
		if not h then
			pass("the commander retreats within a second of going under half (the fight in steps)", false, "it died first")
			cm.stage = "done"
			return
		end
		if h < 0.5 and not cm.halfAt then
			cm.halfAt = f
		end
		if R.fell(cm.com) and not cm.fellAt then
			cm.fellAt = f
			pass("the commander retreats within a second of going under half (the fight in steps)", cm.halfAt ~= nil
				and f - cm.halfAt <= 30, string.format("under half at frame %s, retreated at %d, %d steps",
					tostring(cm.halfAt), f, cm.steps))
			cm.stage, cm.at = "back", f
			return
		end
		if cm.halfAt and f - cm.halfAt > 30 * 8 then
			pass("the commander retreats within a second of going under half (the fight in steps)", false,
				string.format("not in 8 s, %.0f %% now, %d steps", 100 * h, cm.steps))
			cm.stage = "done"
			return
		end
		if f - cm.stepAt >= 30 then -- (a step: 1 s played, then 6 s paused)
			cm.steps, cm.stepAt = cm.steps + 1, f
			cm.pausedAt, cm.pauseFor, cm.after = Spring.GetTimer(), 6, "fight"
			cm.stage = "paused"
			pauseNow(true)
		end
	elseif cm.stage == "back" and f - cm.at > 100 then -- (past the retreat's 3 s watch: the player's own Fight back in)
		Spring.GiveOrderToUnit(cm.com, CMD.FIGHT, { cm.ex, Spring.GetGroundHeight(cm.ex, cm.ez), cm.ez }, 0)
		local _, last = Pd.note()
		cm.noteBefore = last
		Spring.Echo(string.format("[retreattest] the player's Fight back into the Bulldogs at %d %%",
			math.floor(100 * (healthOf(cm.com) or 0))))
		cm.stage, cm.at = "warn", f
	elseif cm.stage == "warn" then
		local h = healthOf(cm.com)
		local _, last = Pd.note()
		local told = last and last ~= cm.noteBefore and tostring(last):find("PULL IT BACK", 1, true)
		if told or not h or f - cm.at > 30 * 25 then
			pass("the player's Fight back, the commander under 30 %: the dock's note says so", told and true or false,
				string.format("note %q at %s", tostring(last), h and string.format("%.0f %%", 100 * h) or "its death"))
			cm.stage = "done"
		end
	elseif cm.stage == "done" then
		pauseNow(false)
		Spring.Echo("[retreattest] commander case: " .. (cm.fails == 0 and "ALL PASS" or (cm.fails .. " FAILED")))
		Spring.Echo("[retreattest] done")
		cm.stage = "over"
	end
end

function widget:Update()
	if cm and cm.stage == "paused" and Spring.DiffTimers(Spring.GetTimer(), cm.pausedAt) >= cm.pauseFor then
		cm.stage = "resumed"
		pauseNow(false)
	end
end

function widget:GameFrame(f)
	if cm then
		if cm.stage ~= "over" then
			commanderFrame(f)
		end
		return
	end
	if stage ~= "wait" and stage ~= "over" then
		watch(f)
	end
	if stage == "wait" and f >= 300 then
		me = Spring.GetMyTeamID()
		foe = enemyTeam()
		local R = WG.BarDroidRetreat
		if not (R and R.set and foe) then
			Spring.Echo("[retreattest] FAIL no bardroid_retreat.lua or no enemy team")
			go("end", f)
			return
		end
		R.set(true)
		local fh = io.open("LuaUI/Config/bardroid_retreattest_only.txt", "r")
		local which = fh and fh:read("*l")
		if fh then
			fh:close()
		end
		if which == "commander" then -- (the commander's case alone, above)
			Spring.SendCommands("cheat 1")
			cm = { stage = "start", fails = 0 }
			Spring.Echo("[retreattest] the commander's case: D-gun mode in and out, a pause, a fight in steps, the warning")
			go("over", f)
			return
		end
		only = onlyKind()
		if only then
			Spring.Echo("[retreattest] only " .. only .. ": its on and off rounds three times, each fall-back followed")
		end
		local hx, _, hz = Spring.GetTeamStartPosition(me)
		home = { hx, hz }
		Spring.SendCommands("cheat 1")
		go("next", f)
	elseif stage == "next" and f - stageAt > 30 then
		round = round + 1
		if round > ROUNDS then
			go("end", f)
			return
		end
		-- the place: from home toward the map's middle, further each round and turned 25 degrees
		local mx, mz = Game.mapSizeX / 2, Game.mapSizeZ / 2
		-- (each kind 400 elmos further and turned 30 degrees; its two rounds, the retreat on and off, at the same place:
		-- at different places one run gave the off round all four Pawns alive by the map's edge and the on round none)
		local ki = math.ceil(round / 2)
		local a = math.atan2(mz - home[2], mx - home[1]) + math.rad(30 * (ki - 3))
		local d = 600 + 400 * ki
		local x = math.max(300, math.min(Game.mapSizeX - 300, home[1] + math.cos(a) * d))
		local z = math.max(300, math.min(Game.mapSizeZ - 300, home[2] + math.sin(a) * d))
		local ex = math.max(200, math.min(Game.mapSizeX - 200, x + math.cos(a) * 260))
		local ez = math.max(200, math.min(Game.mapSizeZ - 200, z + math.sin(a) * 260))
		local k = KINDS[math.ceil(round / 2)]
		local on = round % 2 == 1
		WG.BarDroidRetreat.set(on)
		minHealth = nil
		local defName
		for _, n in ipairs(k[2]) do
			if UnitDefNames[n] then
				defName = n
				break
			end
		end
		if not defName then
			Spring.Echo("[retreattest] (no " .. k[1] .. " in this game: its round left out)")
			go("next", f)
			return
		end
		roundKind = { name = k[1] .. " (" .. defName .. ")", def = UnitDefNames[defName].id, on = on }
		go("fight", f)
		local y = Spring.GetGroundHeight(x, z)
		Spring.SendCommands(string.format("give %d %s %d @%d,%d,%d", k[3], defName, me, x, y, z))
		local pack = {}
		roundKind.foes, roundKind.at = 0, { x, z }
		for n, c in pairs(k[4]) do
			if UnitDefNames[n] then
				Spring.SendCommands(string.format("give %d %s %d @%d,%d,%d", c, n, foe, ex, Spring.GetGroundHeight(ex, ez), ez))
				pack[#pack + 1] = c .. " " .. n
				roundKind.foes = roundKind.foes + c
			end
		end
		Spring.Echo(string.format("[retreattest] round %d (retreat %s): %d %s at %d,%d, the enemy's %s 260 elmos on", round,
			on and "on" or "off", k[3], defName, x, z, table.concat(pack, " and ")))
	elseif stage == "fight" and f - stageAt > 30 * ROUND_SECONDS then
		-- the round's end: mine alive and the enemy's alive counted; what is left of mine sent home, out of the next
		-- round's way
		local n, alive, left = 0, 0, 0
		local foes
		for u, w in pairs(watched) do
			if w.round == round then
				n = n + 1
				if not w.died then
					alive = alive + 1
					Spring.GiveOrderToUnit(u, CMD.MOVE, { home[1], Spring.GetGroundHeight(home[1], home[2]), home[2] }, 0)
				end
			end
		end
		-- (the enemy's given units are not reported to widgets out of sight: the pack's size, and the enemy's units left
		-- within 900 elmos of the fight, the test's own view)
		foes = roundKind.foes or 0
		for _, u in ipairs(Spring.GetTeamUnits(foe) or {}) do
			local ux, _, uz = Spring.GetUnitPosition(u)
			if ux and math.sqrt((ux - roundKind.at[1]) ^ 2 + (uz - roundKind.at[2]) ^ 2) < 900 then
				left = left + 1
			end
		end
		local v = versus[roundKind.name] or {}
		versus[roundKind.name] = v
		local key = roundKind.on and "on" or "off"
		local was = v[key] or { n = 0, alive = 0, foes = 0, left = 0, minH = 1 } -- (summed over -Only's repeats: the
		-- last pair alone was shown, 2026-11-20)
		v[key] = { n = was.n + n, alive = was.alive + alive, foes = was.foes + foes, left = was.left + left,
			minH = math.min(was.minH, minHealth or 1) }
		Spring.Echo(string.format("[retreattest] round %d over: %d of %d mine alive, %d of the enemy's %d left, lowest health "
			.. "%.0f %%", round, alive, n, left, foes, 100 * (minHealth or 1)))
		go("next", f)
	elseif stage == "end" then
		local all = { units = 0, hurt = 0, fell = 0, clear = 0, turned = 0, diedFirst = 0, diedAfter = 0, slow = 0, early = 0,
			went = 0, wentN = 0 }
		local kinds = {}
		for k in pairs(stats) do
			kinds[#kinds + 1] = k
		end
		table.sort(kinds)
		for _, k in ipairs(kinds) do
			local s = stats[k]
			for key, v in pairs(s) do
				all[key] = (all[key] or 0) + v
			end
			Spring.Echo(string.format("[retreattest] %s: %d units, %d hurt alive, %d fell back (%d above half; %d over a second "
				.. "late; %s elmos in the 3 s after), %d got clear, %d turned back, %d died before falling back, %d after", k,
				s.units, s.hurt, s.fell, s.early, s.slow, s.wentN and string.format("%.0f", s.went / s.wentN) or "-", s.clear,
				s.turned, s.diedFirst, s.diedAfter))
		end
		Spring.Echo(string.format("[retreattest] ALL: %d units, %d hurt alive, %d fell back (%d slow), %d got clear, %d turned "
			.. "back, %d died before falling back, %d after", all.units, all.hurt, all.fell, all.slow, all.clear, all.turned,
			all.diedFirst, all.diedAfter))
		local onA, offA, onN, offN = 0, 0, 0, 0
		for _, k in ipairs(kinds) do
			local v = versus[k] or {}
			local a, b = v.on, v.off
			if a and b then
				onA, offA, onN, offN = onA + a.alive, offA + b.alive, onN + a.n, offN + b.n
				Spring.Echo(string.format("[retreattest] %s, retreat on against off: %d/%d alive against %d/%d, the enemy %d/%d "
					.. "left against %d/%d, lowest health %.0f %% against %.0f %%", k, a.alive, a.n, b.alive, b.n, a.left, a.foes,
					b.left, b.foes, 100 * a.minH, 100 * b.minH))
			end
		end
		Spring.Echo(string.format("[retreattest] ALL, retreat on against off: %d/%d alive against %d/%d", onA, onN, offA, offN))
		WG.BarDroidRetreat.set(true)
		Spring.Echo("[retreattest] done")
		go("over", f)
	end
end
