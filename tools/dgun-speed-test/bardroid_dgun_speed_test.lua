-- LuaUI widget for tools/dgun-speed-test.ps1: does the Commander walk slower in the D-gun mode than on a plain move?
-- (Kailil, 2026-11-20: "Investigate if the commander moves slower in dgun mode than if he does when just given a move
-- commands over a medium distance. It feels like he's slower. If he isn't, do nothing.") In a skirmish, the same line
-- of open ground ahead of the camera, LEN elmos, walked three ways from its start: (A) a plain move order to its end;
-- (B) the D-gun mode (bardroid_pad.lua) with its move stick held forward through WG.BarDroidPadDgun.sticks; (C) the
-- D-gun mode with the dock's own stick held by a finger (the script's adb motion events, asked for by "do <n> stick 0 0
-- <vsx>" in LuaUI/Config/bardroid_dguntest.txt, answered "<n>" in bardroid_dguntest_cmd.txt). Each run: the time to
-- cover the line, the mean and top speed while walking, the frames under half the top speed after the start (stop and
-- go), the move orders given. A walk back to the start by a plain move between runs. "[dguntest] done" at the end.
function widget:GetInfo()
	return { name = "BAR Droid D-gun speed test", desc = "The Commander's walk: a move, the D-gun mode", author = "BAR Droid",
		layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_dguntest.txt", "LuaUI/Config/bardroid_dguntest_cmd.txt"
local LEN = 900
local stage, stageAt = "wait", 0
local asked, after = 0, nil
local com, p0, p1, dir
local run -- the run being timed: { name, startF, startX, startZ, speeds = {}, orders = 0, done }
local results = {}

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
local function ask(action, nextStage, f, sx, sy) -- (sx, sy: the stick's way, thousandths)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d\n", asked, action, math.floor((sx or 0) * 1000), math.floor((sy or 0) * 1000), vsx))
	after = nextStage
	go("asked", f)
end
local function speedOf(u)
	local vx, _, vz = Spring.GetUnitVelocity(u)
	return vx and math.sqrt(vx * vx + vz * vz) * Game.gameSpeed or 0
end
-- how far along the line from p0 the commander is
local function along()
	local x, _, z = Spring.GetUnitPosition(com)
	return (x - p0[1]) * dir[1] + (z - p0[3]) * dir[2]
end

function widget:UnitCommand(unitID, _, _, cmdID)
	if run and unitID == com and cmdID == CMD.MOVE then
		run.orders = run.orders + 1
	end
end

local function startRun(name, f)
	run = { name = name, startF = f, start = along(), speeds = {}, orders = 0 }
end
-- the run over once the line is walked (or 60 s): its numbers logged and kept
local function runOver(f)
	local a = along()
	if a - run.start < LEN - 40 and f - run.startF < 30 * 60 then
		return false
	end
	-- (timed from the commander's first step: C's finger lands a second or so after the run is asked for, and that
	-- wait counted as walking time, 93 % against the move order's, 2026-11-20)
	local first = #run.speeds
	for i, s in ipairs(run.speeds) do
		if s > 1 then
			first = i
			break
		end
	end
	local secs = (f - run.startF - (first - 1)) / Game.gameSpeed
	local top, sum, n, dips = 0, 0, 0, 0
	for _, s in ipairs(run.speeds) do
		top = math.max(top, s)
	end
	for i, s in ipairs(run.speeds) do
		if i > first + 30 then -- (after the first second of walking)
			sum, n = sum + s, n + 1
			if s < top * 0.5 then
				dips = dips + 1
			end
		end
	end
	local r = { name = run.name, secs = secs, dist = a - run.start, mean = n > 0 and sum / n or 0, top = top, dips = dips,
		orders = run.orders }
	results[#results + 1] = r
	Spring.Echo(string.format("[dguntest] %s: %.0f elmos in %.1f s (%.1f elmos/s), mean %.1f, top %.1f elmos/s, %d frames "
		.. "under half speed, %d move orders", r.name, r.dist, r.secs, r.dist / math.max(0.1, r.secs), r.mean, r.top, r.dips,
		r.orders))
	run = nil
	return true
end

-- the move stick that walks along the line, for the camera's heading now (bardroid_pad.lua's stickHeading turned round:
-- its heading is x * (-fz, fx) + y * (-fx, -fz))
local function stickFor()
	local cx, _, cz = Spring.GetCameraDirection()
	local l = math.sqrt(cx * cx + cz * cz)
	local fx, fz = 0, -1
	if l > 0.001 then
		fx, fz = cx / l, cz / l
	end
	return -dir[1] * fz + dir[2] * fx, -dir[1] * fx - dir[2] * fz
end
local function holdSticks()
	local D = WG.BarDroidPadDgun
	if D and D.sticks and stage == "B" then
		local x, y = stickFor()
		D.sticks(x, y, 0, 0) -- (the move stick fully along the line, the aim stick at rest)
	end
end

function widget:Update()
	holdSticks()
end

function widget:GameFrame(f)
	holdSticks()
	if run then
		run.speeds[#run.speeds + 1] = speedOf(com)
		if stage == "asked" then -- (C: timed while the finger still holds the stick)
			runOver(f)
		end
	end
	if stage == "wait" and f >= 300 then
		com = (Spring.GetTeamUnits(Spring.GetMyTeamID()) or {})[1]
		Spring.SelectUnitArray({ com })
		-- the line: from the commander along the camera's heading on the ground, open ground all the way (no building
		-- or cliff in the way: TestBuildOrder of a small building every 50 elmos), else turned 30 degrees and again
		local cx, _, cz = Spring.GetCameraDirection()
		local base = math.atan2(cz, cx)
		local x, y, z = Spring.GetUnitPosition(com)
		local small = UnitDefNames.armdrag.id
		for k = 0, 11 do
			local a = base + math.rad(30 * k)
			local dx, dz = math.cos(a), math.sin(a)
			local ok = true
			for d = 60, LEN + 60, 50 do
				local px, pz = x + dx * d, z + dz * d
				if px < 100 or pz < 100 or px > Game.mapSizeX - 100 or pz > Game.mapSizeZ - 100
					or Spring.TestBuildOrder(small, px, Spring.GetGroundHeight(px, pz), pz, 0) == 0 then
					ok = false
					break
				end
			end
			if ok then
				dir = { dx, dz }
				break
			end
		end
		if not dir then
			Spring.Echo("[dguntest] FAIL no open line of " .. LEN .. " elmos from the commander")
			go("end", f)
			return
		end
		p0 = { x, y, z }
		p1 = { x + dir[1] * LEN, 0, z + dir[2] * LEN }
		p1[2] = Spring.GetGroundHeight(p1[1], p1[3])
		Spring.Echo(string.format("[dguntest] the line: %d,%d to %d,%d (%d degrees from the camera's heading)", x, z, p1[1],
			p1[3], math.floor(math.deg(math.atan2(dir[2], dir[1]) - base) + 0.5) % 360))
		go("A", f)
		Spring.GiveOrderToUnit(com, CMD.MOVE, p1, 0)
		startRun("A: a plain move order", f)
	elseif stage == "A" and runOver(f) then
		Spring.GiveOrderToUnit(com, CMD.MOVE, p0, 0)
		go("backA", f)
	elseif (stage == "backA" or stage == "backB") and f - stageAt > 30 * 40 then
		Spring.Echo("[dguntest] FAIL the commander did not get back to the line's start")
		go("end", f)
	elseif (stage == "backA" or stage == "backB") and along() < 20 and speedOf(com) < 1 then
		Spring.SelectUnitArray({ com })
		WG.BarDroidPad.act("dgun")
		go(stage == "backA" and "dgunB" or "dgunC", f)
	elseif stage == "dgunB" and f - stageAt > 15 then
		if not (WG.BarDroidPadDgun and WG.BarDroidPadDgun.active()) then
			Spring.Echo("[dguntest] FAIL the D-gun mode did not open")
			go("end", f)
			return
		end
		go("B", f)
		startRun("B: the D-gun mode, its move stick held forward", f)
	elseif stage == "B" and runOver(f) then
		WG.BarDroidPadDgun.sticks(0, 0, 0, 0)
		WG.BarDroidPad.act("dgun_cancel")
		Spring.SelectUnitArray({ com })
		Spring.GiveOrderToUnit(com, CMD.MOVE, p0, 0)
		go("backB", f)
	elseif stage == "dgunC" and f - stageAt > 15 then
		if not WG.BarDroidPadDgun.active() then
			Spring.Echo("[dguntest] FAIL the D-gun mode did not open again")
			go("end", f)
			return
		end
		startRun("C: the D-gun mode, the dock's stick held by a finger", f)
		local sx, sy = stickFor()
		ask("stick", "C", f, sx, sy)
	elseif stage == "C" and (run == nil or runOver(f)) then
		WG.BarDroidPad.act("dgun_cancel")
		go("end", f)
	elseif stage == "end" then
		local a = results[1]
		for i = 2, #results do
			local r = results[i]
			Spring.Echo(string.format("[dguntest] %s against A: %.0f %% of its speed over the line", r.name:sub(1, 1),
				100 * (r.dist / math.max(0.1, r.secs)) / math.max(0.1, a.dist / math.max(0.1, a.secs))))
		end
		Spring.Echo("[dguntest] done")
		write("end\n")
		go("over", f)
	end
	if stage == "asked" and f % 3 == 0 then
		local c = readCmd()
		if c and tonumber(c) == asked then
			go(after, f)
		end
	end
end
