-- Dev only (the touch playtest, toolchain\tmp\play; research report "Touch playtest agent approach", step 3): the game's
-- state as text for the agent that plays by touch, and a pause on the frame something happens, so the agent reads a
-- file instead of a screenshot and reacts to events. It never gives an order. Twice a second (also while paused)
-- LuaUI/Config/bardroid_playstate.txt:
--   t <gameSeconds> <paused 0|1> <speed>
--   scr <vsx> <vsy>                       (the X screen; positions below with y from the top)
--   res m <cur> <storage> <income> <expense> e <cur> <storage> <income> <expense>
--   shift <0|1>                           (QUEUE: the app's sticky Shift held)
--   sel <n> <defname>=<count> ...
--   active <defname|cmdID|->              (the building picked in the dock, or the order armed)
--   cam <wx> <wz>                         (the ground under the middle of the map's part of the screen)
--   u <id> <def> <wx> <wz> <sx> <sy> <hp%> <idle 0|1> <built%> <queue>  (my units; sx sy "-" off the screen)
--   e <id> <def|?> <wx> <wz> <sx> <sy> <hp%>                            (enemies in sight or on radar)
--   m <wx> <wz> <sx> <sy> <free 0|1>                                    (metal spots)
--   p <tag> <sx> <sy>                                                   (points asked for in bardroid_playreq.txt)
--   ev <seconds> <kind> <text>                                          (the last 30 events)
--   paused_by <kind> <text>                                             (the event that paused the game, if one did)
-- bardroid_playreq.txt (from the laptop), read twice a second: "p <tag> <wx> <wz>" points to put on the screen;
-- "autopause <kinds,...|none>" the events that pause the game (default lost,idle,enemy,comhit); "near <elmos>".
function widget:GetInfo()
	return {name = "Dev Play State", desc = "dev: game state as text for the touch playtest", layer = 0,
		enabled = true}
end

local OUT = "LuaUI/Config/bardroid_playstate.txt"
local REQ = "LuaUI/Config/bardroid_playreq.txt"
local myTeam, myAlly
local acc = 0
local events = {}
local pausedBy, pauseAskedAt
local autopause = {lost = true, idle = true, enemy = true, comhit = true}
local near = 1600
local seenEnemy = {}
local lastComHit = -999
local extractor, builder, factory, commander = {}, {}, {}, {}
for id, ud in pairs(UnitDefs) do
	if (ud.extractsMetal or 0) > 0 then
		extractor[id] = true
	end
	if ud.isFactory then
		factory[id] = true
	elseif ud.isBuilder and (ud.canMove or ud.speed and ud.speed > 0) then
		builder[id] = true
	end
	if ud.customParams and ud.customParams.iscommander then
		commander[id] = true
	end
end

local function now()
	return math.floor(Spring.GetGameFrame() / 30)
end

local function event(kind, text)
	events[#events + 1] = string.format("ev %d %s %s", now(), kind, text)
	if #events > 30 then
		table.remove(events, 1)
	end
	local _, _, paused = Spring.GetGameSpeed()
	if autopause[kind] and not paused then
		pausedBy = kind .. " " .. text
		pauseAskedAt = Spring.GetTimer()
		Spring.SendCommands("pause")
	end
end

local function scr(x, y, z)
	local sx, sy, sz = Spring.WorldToScreenCoords(x, y, z)
	local vsx, vsy = Spring.GetViewGeometry()
	if not sx or sz > 1 or sx < 0 or sx > vsx or sy < 0 or sy > vsy then
		return "-", "-"
	end
	return math.floor(sx + 0.5), math.floor(vsy - sy + 0.5)
end

function widget:Initialize()
	myTeam = Spring.GetMyTeamID()
	myAlly = Spring.GetMyAllyTeamID()
end

local gameOver -- "won" or "lost", once the game has ended
function widget:GameOver(winners)
	gameOver = "lost"
	for _, a in ipairs(winners or {}) do
		if a == myAlly then
			gameOver = "won"
		end
	end
	event("gameover", gameOver)
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if unitTeam == myTeam then
		local x, _, z = Spring.GetUnitPosition(unitID)
		event("lost", UnitDefs[unitDefID].name .. " #" .. unitID ..
			(x and string.format(" at %d,%d", x, z) or ""))
	end
end

function widget:UnitIdle(unitID, unitDefID, unitTeam)
	if unitTeam == myTeam and (builder[unitDefID] or factory[unitDefID]) then
		event("idle", UnitDefs[unitDefID].name .. " #" .. unitID)
	end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam == myTeam then
		event("done", UnitDefs[unitDefID].name .. " #" .. unitID)
		if factory[unitDefID] then -- (a new factory has nothing to build, and no UnitIdle says so)
			event("idle", UnitDefs[unitDefID].name .. " #" .. unitID)
		end
	end
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID,
							attackerDefID, attackerTeam)
	if unitTeam == myTeam and commander[unitDefID] and now() - lastComHit > 10 then
		lastComHit = now()
		event("comhit", UnitDefs[unitDefID].name .. " #" .. unitID .. " by " ..
			(attackerDefID and UnitDefs[attackerDefID] and UnitDefs[attackerDefID].name or "?"))
	end
end

local function nearMine(x, z)
	for _, id in ipairs(Spring.GetTeamUnits(myTeam)) do
		local ux, _, uz = Spring.GetUnitPosition(id)
		if ux and (ux - x) ^ 2 + (uz - z) ^ 2 < near * near then
			return true
		end
	end
	return false
end

function widget:UnitEnteredLos(unitID, unitTeam)
	if Spring.GetUnitAllyTeam(unitID) ~= myAlly and not seenEnemy[unitID] then
		local x, _, z = Spring.GetUnitPosition(unitID)
		if x and nearMine(x, z) then
			seenEnemy[unitID] = true
			local udid = Spring.GetUnitDefID(unitID)
			event("enemy", (udid and UnitDefs[udid].name or "?") .. " #" .. unitID .. string.format(" at %d,%d", x, z))
		end
	end
end

local function write()
	local out = {}
	local n = #out
	local function add(s)
		n = n + 1
		out[n] = s
	end
	local _, speed, paused = Spring.GetGameSpeed()
	-- (the pause lands a few frames after it is asked for: the reason kept until then, or it was lost on the way)
	if not paused and not (pauseAskedAt and Spring.DiffTimers(Spring.GetTimer(), pauseAskedAt) < 2) then
		pausedBy = nil
	end
	add(string.format("t %d %d %.2f", now(), paused and 1 or 0, speed or 0))
	local vsx, vsy = Spring.GetViewGeometry()
	add("scr " .. vsx .. " " .. vsy)
	local mc, ms, _, mi, me = Spring.GetTeamResources(myTeam, "metal")
	local ec, es, _, ei, ee = Spring.GetTeamResources(myTeam, "energy")
	add(string.format("res m %d %d %.1f %.1f e %d %d %.1f %.1f", mc, ms, mi, me, ec, es, ei, ee))
	local _, _, _, shift = Spring.GetModKeyState()
	add("shift " .. (shift and 1 or 0))
	local sel = Spring.GetSelectedUnitsCounts()
	local s = {}
	local total = 0
	for udid, c in pairs(sel) do
		if type(udid) == "number" then
			s[#s + 1] = UnitDefs[udid].name .. "=" .. c
			total = total + c
		end
	end
	add("sel " .. total .. " " .. table.concat(s, " "))
	local ids = Spring.GetSelectedUnits()
	local idl = {}
	for i = 1, math.min(#ids, 60) do
		idl[i] = ids[i]
	end
	add("sid " .. table.concat(idl, " "))
	add(string.format("map %d %d", Game.mapSizeX, Game.mapSizeZ))
	for _, tid in ipairs(Spring.GetTeamList()) do
		local sx, _, sz = Spring.GetTeamStartPosition(tid)
		if sx and sx > 0 then
			add(string.format("start %d %d %d %d", tid, Spring.AreTeamsAllied(tid, Spring.GetMyTeamID()) and 1 or 0, sx, sz))
		end
	end
	-- the first selected units' orders: "q <id> <order>@x,z ..." (a build by its unit name)
	for i = 1, math.min(#ids, 3) do
		local cmds = Spring.GetUnitCommands(ids[i], 16) or {}
		local parts = {}
		for _, c in ipairs(cmds) do
			local nm = c.id < 0 and UnitDefs[-c.id] and UnitDefs[-c.id].name or
				(CMD[c.id] and tostring(CMD[c.id]) or tostring(c.id))
			local p = c.params or {}
			parts[#parts + 1] = (#p >= 3) and string.format("%s@%d,%d", nm, p[1], p[3]) or
				(#p >= 1 and string.format("%s:%d", nm, p[1]) or nm)
		end
		add("q " .. ids[i] .. " " .. table.concat(parts, " "))
	end
	local _, cmdID = Spring.GetActiveCommand()
	add("active " .. ((cmdID and cmdID < 0 and UnitDefs[-cmdID]) and UnitDefs[-cmdID].name or tostring(cmdID or "-")))
	-- the order menu's buttons as laid out (the app's copy tells them): "o <name> <x1> <ytop> <x2> <ybottom>"
	local om = WG.ordermenu
	if om and om.droidCells and (not om.getIsShowing or om.getIsShowing()) then
		local rects, cmds = om.droidCells()
		for i, cmd in ipairs(cmds or {}) do
			local r = rects and rects[i]
			if r and type(cmd) == "table" then
				add(string.format("o %s %d %d %d %d", tostring(cmd.action or cmd.name or cmd.id):gsub("%s", "_"), r[1],
					vsy - r[4], r[3], vsy - r[2]))
			end
		end
	end
	-- the upright dock's tiles where they are drawn now (off its half when scrolled away): "c <L|R> <name> x1 ytop x2
	-- ybottom"; the left half's build tiles by unit name, the right half's orders by their label
	local dock = WG.BarDroidPortrait
	if dock and dock.itemCell then
		local seen = {}
		for _, side in ipairs({"left", "right"}) do
			for i = 1, 60 do
				local r, it = dock.itemCell(side, function(it)
					local key = tostring(it.kind) .. ":" .. tostring(it.defID or it.label or it.id)
					if seen[side .. key] then
						return false
					end
					seen[side .. key] = true
					return true
				end)
				if not r then
					break
				end
				local udid = it.defID or it.udid or it.unitDefID
				local name = udid and UnitDefs[udid] and ((it.kind == "build" and "" or tostring(it.kind) .. ":") ..
					UnitDefs[udid].name) or tostring(it.label or it.id or it.kind)
				local x1, x2 = math.min(r[1], r[3]), math.max(r[1], r[3])
				local y1, y2 = math.min(r[2], r[4]), math.max(r[2], r[4])
				add(string.format("c %s %s %d %d %d %d", side == "left" and "L" or "R", name:gsub("%s", "_"), x1,
					vsy - y2, x2, vsy - y1))
			end
		end
	end
	local _, pos = Spring.TraceScreenRay(vsx / 2, vsy - vsy * 0.258, true)
	if pos then
		add(string.format("cam %d %d", pos[1], pos[3]))
	end
	for _, id in ipairs(Spring.GetTeamUnits(myTeam)) do
		local udid = Spring.GetUnitDefID(id)
		local x, y, z = Spring.GetUnitPosition(id)
		if udid and x then
			local hp, maxhp, _, _, built = Spring.GetUnitHealth(id)
			local ud = UnitDefs[udid]
			local qn
			if ud.isFactory then
				qn = #(Spring.GetFactoryCommands(id, 30) or {})
			else
				qn = #(Spring.GetUnitCommands(id, 30) or {})
			end
			local sx, sy = scr(x, y, z)
			add(string.format("u %d %s %d %d %s %s %d %d %d %d", id, ud.name, x, z, sx, sy,
				maxhp and maxhp > 0 and math.floor(100 * hp / maxhp) or 0, qn == 0 and 1 or 0,
				math.floor(100 * (built or 1)), qn))
		end
	end
	for _, id in ipairs(Spring.GetAllUnits()) do
		if Spring.GetUnitAllyTeam(id) ~= myAlly then
			local los = Spring.GetUnitLosState(id, myAlly)
			if los and (los.los or los.radar) then
				local x, y, z = Spring.GetUnitPosition(id)
				if x then
					local udid = los.los and Spring.GetUnitDefID(id)
					local hp, maxhp = Spring.GetUnitHealth(id)
					local sx, sy = scr(x, y, z)
					add(string.format("e %d %s %d %d %s %s %d", id, udid and UnitDefs[udid].name or "?", x, z, sx, sy,
						(hp and maxhp and maxhp > 0) and math.floor(100 * hp / maxhp) or -1))
				end
			end
		end
	end
	local spots = WG["resource_spot_finder"] and WG["resource_spot_finder"].metalSpotsList
	if spots then
		local queuedMex = {} -- (extractors already in my builders' queues: their spots are not free)
		for _, uid in ipairs(Spring.GetTeamUnits(myTeam)) do
			if builder[Spring.GetUnitDefID(uid) or -1] then
				for _, c in ipairs(Spring.GetUnitCommands(uid, 40) or {}) do
					if c.id < 0 and extractor[-c.id] and c.params and c.params[3] then
						queuedMex[#queuedMex + 1] = {c.params[1], c.params[3]}
					end
				end
			end
		end
		for _, sp in ipairs(spots) do
			local x, z = sp.x, sp.z
			local y = Spring.GetGroundHeight(x, z)
			local free = 1
			for _, uid in ipairs(Spring.GetUnitsInCylinder(x, z, 110)) do -- (an extractor off the spot's middle covers it too)
				if extractor[Spring.GetUnitDefID(uid) or -1] then
					free = 0
				end
			end
			for _, q in ipairs(queuedMex) do
				if (q[1] - x) ^ 2 + (q[2] - z) ^ 2 < 110 * 110 then
					free = 0
				end
			end
			local sx, sy = scr(x, y, z)
			add(string.format("m %d %d %s %s %d", x, z, sx, sy, free))
		end
	end
	local f = io.open(REQ, "r")
	if f then
		for line in f:lines() do
			local tag, x, z = line:match("^p (%S+) (%S+) (%S+)")
			if tag then
				x, z = tonumber(x), tonumber(z)
				local sx, sy = scr(x, Spring.GetGroundHeight(x, z), z)
				add("p " .. tag .. " " .. sx .. " " .. sy)
			end
			-- "w <x1> <z1> <x2> <z2>": the path a Centurion would walk, answered "w x,z x,z ..." (every 4th waypoint)
			local wx1, wz1, wx2, wz2 = line:match("^w (%S+) (%S+) (%S+) (%S+)")
			if wx1 and UnitDefNames.armwar then
				wx1, wz1, wx2, wz2 = tonumber(wx1), tonumber(wz1), tonumber(wx2), tonumber(wz2)
				local md = UnitDefNames.armwar.moveDef and UnitDefNames.armwar.moveDef.name
				local path = md and Spring.RequestPath(md, wx1, Spring.GetGroundHeight(wx1, wz1), wz1, wx2,
					Spring.GetGroundHeight(wx2, wz2), wz2, 32)
				local out = {}
				if path then
					local pts = path:GetPathWayPoints() or {}
					for i = 1, #pts, 4 do
						out[#out + 1] = string.format("%d,%d", pts[i][1], pts[i][3])
					end
					if #pts > 0 then
						out[#out + 1] = string.format("%d,%d", pts[#pts][1], pts[#pts][3])
					end
				end
				add("w " .. table.concat(out, " "))
			end
			local kinds = line:match("^autopause (%S+)")
			if kinds then
				autopause = {}
				for k in kinds:gmatch("[^,]+") do
					autopause[k] = true
				end
			end
			-- "f <tag> <defname> <x> <z> <n> <gap>": n spots near x,z where that building can go now (the engine's own
			-- test, free ground), gap elmos apart at least; answered "f <tag> x,z x,z ..."
			local ftag, fdef, fx, fz, fn, fgap = line:match("^f (%S+) (%S+) (%S+) (%S+) (%d+) (%d+)")
			if ftag and UnitDefNames[fdef] then
				local udid = UnitDefNames[fdef].id
				fx, fz, fn, fgap = tonumber(fx), tonumber(fz), tonumber(fn), tonumber(fgap)
				local found = {}
				local planned = {} -- (buildings already queued by my builders: their ground is taken too)
				for _, uid in ipairs(Spring.GetTeamUnits(myTeam)) do
					local ud = UnitDefs[Spring.GetUnitDefID(uid) or 0]
					if ud and ud.isBuilder then
						for _, c in ipairs(Spring.GetUnitCommands(uid, 60) or {}) do
							if c.id < 0 and c.params and c.params[3] then
								local bd = UnitDefs[-c.id]
								local r = bd and math.max(bd.xsize or 4, bd.zsize or 4) * 4 or 16
								planned[#planned + 1] = {c.params[1], c.params[3], r}
							end
						end
					end
				end
				for ring = 0, 30 do
					for k = 0, math.max(0, ring * 8 - 1) do
						local a = ring == 0 and 0 or (k / (ring * 8)) * 2 * math.pi
						local x = fx + math.cos(a) * ring * fgap
						local z = fz + math.sin(a) * ring * fgap
						x, z = math.floor(x / 16 + 0.5) * 16, math.floor(z / 16 + 0.5) * 16
						local ok = true
						for _, p in ipairs(found) do
							if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < fgap * fgap then
								ok = false
							end
						end
						local mine = math.max(UnitDefs[udid].xsize or 4, UnitDefs[udid].zsize or 4) * 4
						for _, p in ipairs(planned) do
							if math.abs(p[1] - x) < p[3] + mine and math.abs(p[2] - z) < p[3] + mine then
								ok = false
							end
						end
						if ok and Spring.TestBuildOrder(udid, x, Spring.GetGroundHeight(x, z), z, 0) == 2 then
							found[#found + 1] = {x, z}
						end
						if #found >= fn then
							break
						end
					end
					if #found >= fn then
						break
					end
				end
				local s = {}
				for _, p in ipairs(found) do
					s[#s + 1] = p[1] .. "," .. p[2]
				end
				add("f " .. ftag .. " " .. table.concat(s, " "))
			end
			local r = line:match("^near (%d+)")
			if r then
				near = tonumber(r)
			end
		end
		f:close()
	end
	for _, e in ipairs(events) do
		add(e)
	end
	if pausedBy then
		add("paused_by " .. pausedBy)
	end
	local o = io.open(OUT, "w") -- (one write; the reader takes a file that ends without "end" as cut and reads again)
	if o then
		o:write(table.concat(out, "\n"), "\nend\n")
		o:close()
	end
end

function widget:Update(dt)
	acc = acc + dt
	if acc >= 0.5 then
		acc = 0
		local ok, err = pcall(write)
		if not ok then
			Spring.Echo("dev_playstate: " .. tostring(err))
		end
	end
end
