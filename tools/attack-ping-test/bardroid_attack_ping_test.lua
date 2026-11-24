-- LuaUI widget for tools/attack-ping-test.ps1: my units under attack in the dock's last pings (bardroid_pad.lua ATTACK;
-- Kailil, 2026-11-20: "Alliw unit under attack notification to be tracked via the last pings system so I can teleoort
-- to the danger area"). In a skirmish (cheats on): four Pawns of mine and three of the enemy's Grunts given beside each
-- other (a fight), then the same far off 8 s later. Checked: the first fight one entry at its place, still one a few
-- seconds on (its hits merged), the LAST PINGS badge red; the second fight a second entry, the newest. Then the camera
-- on the first fight and the script's real tap on LAST PINGS (asked for by "do <n> tap|shot <x> <y> <vsx>" in
-- LuaUI/Config/bardroid_attacktest.txt, answered "<n>" in bardroid_attacktest_cmd.txt): the second fight in sight above
-- the dock. Then a busy fight beside a light one (2026-11-20 ~20:50): thirty Pawns against thirty Grunts, hits every
-- frame, and 4.5 s later far off one Grunt shooting a solar of mine: the light fight still gets its own entry (the hits
-- were looked at once every 8 frames, the first of a frame, so the busy fight's nearly always). The busy fight sprawls
-- (2026-11-24): five parts of ten against ten in a line, 1200 elmos apart: half as many entries as parts at most, and
-- the light one not kept out by the busy one's new entries. "[attacktest] done: ALL PASS" or "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid attack ping test", desc = "Under attack in the last pings", author = "BAR Droid", layer = 0,
		enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_attacktest.txt", "LuaUI/Config/bardroid_attacktest_cmd.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local fight1, fight2 -- { x, z }
local tapAt -- LAST PINGS' left half (X pixels, top left origin)
local firstCell -- LAST PINGS' cell (GL pixels) just after the start, to compare with the one at the tap

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[attacktest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
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

-- the script asked to tap or take a picture at x, y (X pixels, top left origin); "nextStage" once it is done
local function ask(action, x, y, nextStage, f)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx))
	after = nextStage
	go("asked", f)
end

local function enemyTeam()
	local me = Spring.GetMyTeamID()
	for _, t in ipairs(Spring.GetTeamList() or {}) do
		if t ~= Spring.GetGaiaTeamID() and not Spring.AreTeamsAllied(t, me) then
			return t
		end
	end
end
-- a fight at x, z: four Pawns of mine, three enemy Grunts 160 elmos on
local function fightAt(x, z)
	local me, foe = Spring.GetMyTeamID(), enemyTeam()
	local y = Spring.GetGroundHeight(x, z)
	Spring.SendCommands(string.format("give 4 armpw %d @%d,%d,%d", me, x, y, z))
	Spring.SendCommands(string.format("give 3 corak %d @%d,%d,%d", foe, x + 160, y, z))
end
-- the list's attack entries: how many, and the newest's distance from a point
local function attacks()
	local Pd = WG.BarDroidPad
	local out = {}
	for i = 1, 10 do
		local x, z, attack = Pd.pingAt(i)
		if not x then
			break
		end
		if attack then
			out[#out + 1] = { x, z, i }
		end
	end
	return out
end
-- (the first hits on my units as LuaUI hands them over: what bardroid_pad.lua's ATTACK sees)
local hitsLogged = 0
local lightAt, lightHits, lightUnit = nil, 0, nil -- (the light fight's place once given; hits on my units there)
local f1Hits -- (hits on my units by the first fight while its merge is watched: none, nothing to merge)
local fight2SeenBefore -- (the second fight in sight before LAST PINGS' tap)
function widget:UnitDamaged(unitID, _, unitTeam, damage, paralyzer, weaponDefID, _, attackerID, _, attackerTeam)
	if f1Hits and unitTeam == Spring.GetMyTeamID() then
		local x, _, z = Spring.GetUnitPosition(unitID)
		if x and (x - fight1[1]) ^ 2 + (z - fight1[2]) ^ 2 < 500 ^ 2 then
			f1Hits = f1Hits + 1
		end
	end
	if lightAt and unitTeam == Spring.GetMyTeamID() then
		local x, _, z = Spring.GetUnitPosition(unitID)
		if x and (x - lightAt[1]) ^ 2 + (z - lightAt[2]) ^ 2 < 500 ^ 2 then
			lightHits, lightUnit = lightHits + 1, unitID
		end
	end
	if hitsLogged < 4 and unitTeam == Spring.GetMyTeamID() then
		hitsLogged = hitsLogged + 1
		Spring.Echo(string.format("[attacktest] a hit: unit %d, damage %s, paralyzer %s, weapon %s, attacker %s of team %s",
			unitID, tostring(damage), tostring(paralyzer), tostring(weaponDefID), tostring(attackerID), tostring(attackerTeam)))
	end
end
local function dist(p, q)
	return p and q and math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) or math.huge
end
-- a place on the map as far as can be from the given ones (on a grid of candidates a quarter of the map apart), where
-- the named building can stand if one is named (a solar given on a slope came to nothing: no fight there, 2026-11-20)
local function farFrom(places, building)
	local mx, mz = Game.mapSizeX, Game.mapSizeZ
	local def = building and UnitDefNames[building]
	local best, bestD
	for i = 1, 4 do
		for j = 1, 4 do
			local p = { mx * (i - 0.5) / 4, mz * (j - 0.5) / 4 }
			local d = math.huge
			for _, q in ipairs(places) do
				d = math.min(d, dist(p, q))
			end
			local y = Spring.GetGroundHeight(p[1], p[2])
			local stands = not def or (Spring.TestBuildOrder(def.id, p[1], y, p[2], 0) or 0) > 0
			if y > 0 and stands and (not bestD or d > bestD) then
				best, bestD = p, d
			end
		end
	end
	return best, bestD
end
local busy, light -- { x, z } of the busy fight (its middle part) and the light one
-- (elmos between the busy fight's parts: past ATTACK.NEAR, 900, by more than a part's own size, within its SPREAD, 1440.
-- At 1100 the old rule's entries hopped from part to part and the light fight got its entry before the fix too; five
-- parts keep the old rule opening entries past the check, each gap's first look a part's nearly always, 2026-11-24)
local SPRAWL, PARTS = 1200, 5
local parts -- the busy fight's parts, { x, z } each
local lightFar -- (the light fight's distance from the nearest other)
local function alive(team, x, z)
	return #(Spring.GetUnitsInCylinder(x, z, 700, team) or {})
end

function widget:GameFrame(f)
	if stage == "wait" and f >= 300 then
		Spring.SendCommands("cheat 1") -- (the give a second later: in the same frame it came to nothing)
		go("cheat", f)
	elseif stage == "cheat" and f - stageAt > 30 then
		if not (WG.BarDroidPad and WG.BarDroidPad.pingAt) then
			check("bardroid_pad.lua's pingAt", false, "none")
			go("end", f)
			return
		end
		local com = (Spring.GetTeamUnits(Spring.GetMyTeamID()) or {})[1]
		local x, _, z = Spring.GetUnitPosition(com)
		fight1 = { x + 500, z }
		fightAt(fight1[1], fight1[2])
		Spring.SelectUnitArray({})
		go("firstcell", f)
	elseif stage == "firstcell" and f - stageAt > 10 then -- (where LAST PINGS stands now, the home grid just up)
		local P = WG.BarDroidPortrait
		firstCell = P and P.itemCell and P.itemCell("right", function(it)
			return it.kind == "pings" and not it.pingOnly
		end)
		Spring.Echo(string.format("[attacktest] the first fight given at %d,%d (enemy team %s)", fight1[1], fight1[2],
			tostring(enemyTeam())))
		go("fight1", f)
	elseif stage == "fight1" and f - stageAt > 90 then
		local a = attacks()
		local _, _, red = WG.BarDroidPad.pingCount()
		check("the first fight: one entry, at the fight", #a == 1 and dist(a[1], fight1) < 500,
			#a .. " entries, " .. (a[1] and math.floor(dist(a[1], fight1)) or "-") .. " elmos off")
		check("the first fight: LAST PINGS' badge red (the newest an attack going on)", red == true, red)
		f1Hits = 0
		go("fight1b", f)
	elseif stage == "fight1b" and f - stageAt > 90 then
		local a = attacks()
		-- (and hits landed meanwhile: a fight already over also left one entry; vacuous-pass audit, 2026-11-23)
		check("the first fight 3 s on: still one entry (its hits merged)", #a == 1 and f1Hits > 0,
			#a .. " entries, " .. f1Hits .. " hits on mine there in those 3 s")
		f1Hits = nil
		-- (the second fight far off: the map's other side from the first, about 2460 elmos, past the first fight's SPREAD
		-- (1350) by more than its entry may follow it: 2000 off, it was taken in once the first's entry had moved 460
		-- elmos that way, 2026-11-24)
		local mx, mz = Game.mapSizeX, Game.mapSizeZ
		local x = fight1[1] > mx / 2 and fight1[1] - 2200 or fight1[1] + 2200
		x = math.max(300, math.min(mx - 300, x))
		local z = fight1[2] > mz / 2 and fight1[2] - 1100 or fight1[2] + 1100
		z = math.max(300, math.min(mz - 300, z))
		fight2 = { x, z }
		fightAt(x, z)
		Spring.Echo(string.format("[attacktest] the second fight given at %d,%d (%d elmos from the first)", x, z,
			dist(fight1, fight2)))
		go("fight2", f)
	elseif stage == "fight2" and f - stageAt > 150 then -- (a new entry at most every 4 s: the first fight's came up
		-- to 2 s after its give, the second's hits in the 4 s after it wait)
		local a = attacks()
		check("the second fight: a second entry, the newest, at it", #a == 2 and a[1][3] == 1 and dist(a[1], fight2) < 500,
			#a .. " entries, the newest " .. (a[1] and math.floor(dist(a[1], fight2)) or "-") .. " elmos off")
		-- the camera past the first fight, away from the second, then LAST PINGS tapped (its left half). (On the first
		-- fight itself the second was in sight already with some start places, the tap's jump proving nothing: the
		-- check's guard failed, 2026-11-24)
		local P = WG.BarDroidPortrait
		if P and P.cameraTo then
			local dx, dz = fight1[1] - fight2[1], fight1[2] - fight2[2]
			local len = math.max(1, math.sqrt(dx * dx + dz * dz))
			local cx = math.max(300, math.min(Game.mapSizeX - 300, fight1[1] + dx / len * 1500))
			local cz = math.max(300, math.min(Game.mapSizeZ - 300, fight1[2] + dz / len * 1500))
			P.cameraTo(cx, Spring.GetGroundHeight(cx, cz), cz)
		end
		go("cell", f)
	elseif stage == "cell" and f - stageAt > 20 then
		ask("shot", 0, 0, "shotdone", f)
	elseif stage == "shotdone" then -- (LAST PINGS' cell now, just before the tap: worked out before the screenshot, the
		-- groups row came up meanwhile, the home grid rose 131 pixels and the tap hit BASE, 2026-11-20)
		local P = WG.BarDroidPortrait
		local r
		for _, side in ipairs({ "right", "left" }) do
			r = r or (P and P.itemCell and P.itemCell(side, function(it)
				return it.kind == "pings" and not it.pingOnly
			end))
		end
		if not r then
			check("LAST PINGS on the dock", false, "no cell (something picked?)")
			go("end", f)
			return
		end
		local vsx, vsy = Spring.GetViewGeometry()
		tapAt = { r[1] + (r[3] - r[1]) * 0.25, vsy - (r[2] + r[4]) / 2 }
		-- (the second fight out of sight before the tap: in sight already, the tap's jump proved nothing)
		local dock = P and P.dock and P.dock()
		local sx, sy, sz = Spring.WorldToScreenCoords(fight2[1], Spring.GetGroundHeight(fight2[1], fight2[2]), fight2[2])
		fight2SeenBefore = sz < 1 and sx > 0 and sx < vsx and sy > (dock and dock[4] or 0) and sy < vsy
		-- (the home grid still where it stood at the start: the groups row coming up with the first idle builder lifted it
		-- 132 pixels and this tap once hit BASE, 2026-11-20)
		check("the home grid still where it stood a minute before (LAST PINGS)", firstCell and firstCell[2] == r[2]
			and firstCell[4] == r[4], firstCell and string.format("then %d-%d, now %d-%d", firstCell[2], firstCell[4], r[2], r[4])
			or "no cell then")
		ask("tap", tapAt[1], tapAt[2], "jumped?", f)
	elseif stage == "jumped?" and f - stageAt > 30 then
		local vsx, vsy = Spring.GetViewGeometry()
		local P = WG.BarDroidPortrait
		local dock = P and P.dock and P.dock()
		local x, z = fight2[1], fight2[2]
		local sx, sy, sz = Spring.WorldToScreenCoords(x, Spring.GetGroundHeight(x, z), z)
		local inSight = sz < 1 and sx > 0 and sx < vsx and sy > (dock and dock[4] or 0) and sy < vsy
		local cs = Spring.GetCameraState()
		check("LAST PINGS tapped: the camera on the second fight, in sight above the dock", inSight
			and fight2SeenBefore == false, string.format("at %d,%d of %dx%d, the dock's top %d; the camera's point %s,%s, %d "
				.. "units picked; in sight before the tap %s", sx, sy, vsx, vsy, dock and dock[4] or 0,
				tostring(cs.px and math.floor(cs.px)), tostring(cs.pz and math.floor(cs.pz)), Spring.GetSelectedUnitsCount(),
				tostring(fight2SeenBefore)))
		go("busy", f)
	elseif stage == "busy" and f - stageAt > 30 then -- (a busy fight far from the first two, sprawling: PARTS parts of
		-- ten Pawns against ten Grunts in a line, SPRAWL elmos apart, farther than ATTACK.NEAR (900) from each other. A
		-- 30 v 30 in one place spread past NEAR by itself now and then and opened entries of its own every 4 s, the
		-- light fight's looks missing the gap: the full set on 912e7b2a, 2026-11-24; this makes it every run)
		busy = farFrom({ fight1, fight2 })
		local mx, mz = Game.mapSizeX, Game.mapSizeZ
		local alongX = mx >= mz
		local span = (alongX and mx or mz) - 600
		local n = math.max(3, math.min(PARTS, math.floor(span / SPRAWL) + 1)) -- (fewer on a small map)
		local half = (n - 1) / 2
		local c = alongX and busy[1] or busy[2]
		c = math.max(300 + half * SPRAWL, math.min(300 + span - half * SPRAWL, c))
		parts = {}
		local me, foe = Spring.GetMyTeamID(), enemyTeam()
		for k = -half, half do
			local p = alongX and { c + k * SPRAWL, busy[2] } or { busy[1], c + k * SPRAWL }
			parts[#parts + 1] = p
			local y = Spring.GetGroundHeight(p[1], p[2])
			Spring.SendCommands(string.format("give 10 armpw %d @%d,%d,%d", me, p[1], y, p[2]))
			Spring.SendCommands(string.format("give 10 corak %d @%d,%d,%d", foe, p[1] + (alongX and 0 or 200), y,
				p[2] + (alongX and 200 or 0)))
		end
		busy = parts[math.ceil(#parts / 2)]
		Spring.Echo(string.format("[attacktest] a busy sprawling fight given: %d parts %d elmos apart from %d,%d to %d,%d "
			.. "(map %dx%d)", #parts, SPRAWL, parts[1][1], parts[1][2], parts[#parts][1], parts[#parts][2], mx, mz))
		go("light", f)
	elseif stage == "light" and f - stageAt > 135 then -- (past the 4 s between new entries; then a light one far off)
		local d
		local others = { fight1, fight2 }
		for _, p in ipairs(parts) do
			others[#others + 1] = p
		end
		light, d = farFrom(others, "armsolar")
		lightFar = d
		local me, foe = Spring.GetMyTeamID(), enemyTeam()
		local y = Spring.GetGroundHeight(light[1], light[2])
		Spring.SendCommands(string.format("give 1 armsolar %d @%d,%d,%d", me, light[1], y, light[2]))
		Spring.SendCommands(string.format("give 1 corak %d @%d,%d,%d", foe, light[1] + 150, y, light[2]))
		Spring.Echo(string.format("[attacktest] a light fight given at %d,%d (%d elmos from the nearest other)", light[1],
			light[2], d))
		lightAt = light
		go("light?", f)
	elseif stage == "light?" and f - stageAt > 150 then
		local a, near = attacks(), nil
		for _, p in ipairs(a) do
			if dist(p, light) < 500 then
				near = p
			end
		end
		local me, foe = Spring.GetMyTeamID(), enemyTeam()
		local busyMine, busyFoe = alive(me, busy[1], busy[2]), alive(foe, busy[1], busy[2])
		local hp, maxHp
		if lightUnit then
			hp, maxHp = Spring.GetUnitHealth(lightUnit)
		end
		local why = string.format("%d attack entries, %s; %d hits on mine there (%s); the busy fight still on: %d of mine, "
			.. "%d of theirs near it", #a, near and ("one " .. math.floor(dist(near, light)) .. " elmos from it") or
			"none at it", lightHits, hp and string.format("its health %d of %d", hp, maxHp or 0) or "gone or never hit",
			busyMine, busyFoe)
		-- (the busy fight's entries: those within NEAR of one of its parts)
		local front = 0
		for _, p in ipairs(a) do
			for _, q in ipairs(parts) do
				if dist(p, q) <= 900 then
					front = front + 1
					break
				end
			end
		end
		why = why .. string.format("; %d of the entries on the busy fight's parts; the light one %d elmos from the nearest "
			.. "other", front, lightFar or -1)
		if lightHits == 0 then -- (no fight there: nothing to tell; the test's own, its place)
			check("a light fight beside a busy one: hits there to judge by", false, why)
		elseif (lightFar or 0) <= 2700 then -- (a map too small to put it past 3 x NEAR from the rest: it may wait 4 s)
			Spring.Echo("[attacktest] NOT RUN a light fight beside a busy, sprawling one: its own entry (the map leaves it "
				.. "within 2700 elmos of the rest): " .. why)
		else -- (and the busy fight still on: with its give dropped the light one stood alone)
			check("a light fight beside a busy, sprawling one: its own entry", near ~= nil and busyMine > 0 and busyFoe > 0,
				why)
		end
		-- (a fight spreading past NEAR: each entry takes in its neighbours within SPREAD, so half its parts' entries at
		-- most: before, each part far from the entries opened its own, one every 4 s)
		local most = math.ceil(#parts / 2)
		check("the busy sprawling fight: " .. most .. " entries at most for its " .. #parts .. " parts", front >= 1
			and front <= most, why)
		go("end", f)
	elseif stage == "end" then
		Spring.Echo("[attacktest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
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
