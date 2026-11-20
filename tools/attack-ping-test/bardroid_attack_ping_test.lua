-- LuaUI widget for tools/attack-ping-test.ps1: my units under attack in the dock's last pings (bardroid_pad.lua ATTACK;
-- Kailil, 2026-11-20: "Alliw unit under attack notification to be tracked via the last pings system so I can teleoort
-- to the danger area"). In a skirmish (cheats on): four Pawns of mine and three of the enemy's Grunts given beside each
-- other (a fight), then the same far off 8 s later. Checked: the first fight one entry at its place, still one a few
-- seconds on (its hits merged), the LAST PINGS badge red; the second fight a second entry, the newest. Then the camera
-- on the first fight and the script's real tap on LAST PINGS (asked for by "do <n> tap|shot <x> <y> <vsx>" in
-- LuaUI/Config/bardroid_attacktest.txt, answered "<n>" in bardroid_attacktest_cmd.txt): the second fight in sight above
-- the dock. "[attacktest] done: ALL PASS" or "N FAILED" at the end.
function widget:GetInfo()
	return { name = "BAR Droid attack ping test", desc = "Under attack in the last pings", author = "BAR Droid", layer = 0,
		enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_attacktest.txt", "LuaUI/Config/bardroid_attacktest_cmd.txt"
local stage, stageAt, fails = "wait", 0, 0
local asked, after = 0, nil
local fight1, fight2 -- { x, z }
local tapAt -- LAST PINGS' left half (X pixels, top left origin)

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
function widget:UnitDamaged(unitID, _, unitTeam, damage, paralyzer, weaponDefID, _, attackerID, _, attackerTeam)
	if hitsLogged < 4 and unitTeam == Spring.GetMyTeamID() then
		hitsLogged = hitsLogged + 1
		Spring.Echo(string.format("[attacktest] a hit: unit %d, damage %s, paralyzer %s, weapon %s, attacker %s of team %s",
			unitID, tostring(damage), tostring(paralyzer), tostring(weaponDefID), tostring(attackerID), tostring(attackerTeam)))
	end
end
local function dist(p, q)
	return p and q and math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) or math.huge
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
		Spring.Echo(string.format("[attacktest] the first fight given at %d,%d (enemy team %s)", fight1[1], fight1[2],
			tostring(enemyTeam())))
		go("fight1", f)
	elseif stage == "fight1" and f - stageAt > 90 then
		local a = attacks()
		local _, _, red = WG.BarDroidPad.pingCount()
		check("the first fight: one entry, at the fight", #a == 1 and dist(a[1], fight1) < 500,
			#a .. " entries, " .. (a[1] and math.floor(dist(a[1], fight1)) or "-") .. " elmos off")
		check("the first fight: LAST PINGS' badge red (the newest an attack going on)", red == true, red)
		go("fight1b", f)
	elseif stage == "fight1b" and f - stageAt > 90 then
		local a = attacks()
		check("the first fight 3 s on: still one entry (its hits merged)", #a == 1, #a .. " entries")
		-- (the second fight far off: the map's other side from the first, 1500+ elmos)
		local mx, mz = Game.mapSizeX, Game.mapSizeZ
		local x = fight1[1] > mx / 2 and fight1[1] - 1800 or fight1[1] + 1800
		x = math.max(300, math.min(mx - 300, x))
		local z = fight1[2] > mz / 2 and fight1[2] - 900 or fight1[2] + 900
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
		-- the camera on the first fight, then LAST PINGS tapped (its left half)
		local P = WG.BarDroidPortrait
		if P and P.cameraTo then
			P.cameraTo(fight1[1], Spring.GetGroundHeight(fight1[1], fight1[2]), fight1[2])
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
		local _, vsy = Spring.GetViewGeometry()
		tapAt = { r[1] + (r[3] - r[1]) * 0.25, vsy - (r[2] + r[4]) / 2 }
		ask("tap", tapAt[1], tapAt[2], "jumped?", f)
	elseif stage == "jumped?" and f - stageAt > 30 then
		local vsx, vsy = Spring.GetViewGeometry()
		local P = WG.BarDroidPortrait
		local dock = P and P.dock and P.dock()
		local x, z = fight2[1], fight2[2]
		local sx, sy, sz = Spring.WorldToScreenCoords(x, Spring.GetGroundHeight(x, z), z)
		local inSight = sz < 1 and sx > 0 and sx < vsx and sy > (dock and dock[4] or 0) and sy < vsy
		local cs = Spring.GetCameraState()
		check("LAST PINGS tapped: the camera on the second fight, in sight above the dock", inSight,
			string.format("at %d,%d of %dx%d, the dock's top %d; the camera's point %s,%s, %d units picked", sx, sy, vsx,
				vsy, dock and dock[4] or 0, tostring(cs.px and math.floor(cs.px)), tostring(cs.pz and math.floor(cs.pz)),
				Spring.GetSelectedUnitsCount()))
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
