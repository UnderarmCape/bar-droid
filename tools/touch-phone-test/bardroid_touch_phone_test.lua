-- User widget for tools/touch-phone-test.ps1: the touch camera (bardroid_touch.lua) on the phone, driven by lines this
-- widget appends to LuaUI/Config/bardroid_touch.txt as the app writes them (pan, zoom: X pixels, top-left origin). A
-- drag holds the map point under the finger: on the map, over the void past its edge (across and up), across the edge;
-- a pinch over the void zooms about its point; a drag over the sky moves the map; under BAR's lobby over the game the
-- fingers leave the camera and the dock steps aside. Logs "[touchphone] PASS|FAIL|SKIP <case>" and "[touchphone] done".
function widget:GetInfo()
	return { name = "BAR Droid touch phone test", desc = "Checks the touch camera at the map's edge", author = "BAR Droid",
		layer = 0, enabled = true }
end

local frames, step, waitUntil, repeats, fails = 0, 0, 0, 0, 0
local uprightDock = false -- (upright: the dock checked in the menus' place)
local vsx, vsy = Spring.GetViewGeometry()
local cx = math.floor(vsx / 2)

local function log(s)
	Spring.Echo("[touchphone] " .. s)
end

local function touch(line)
	local f = io.open("LuaUI/Config/bardroid_touch.txt", "a")
	f:write(line .. "\n")
	f:close()
end

-- The map point under X pixel (x, y from the top), or nil off the map
local function groundAt(x, y)
	local kind, pos = Spring.TraceScreenRay(x, vsy - y, true)
	if kind == "ground" and pos then
		return pos[1], pos[3], pos[2]
	end
end

-- Where the view ray through X pixel (x, y from the top: GetPixelDir's own way) meets the level plane at height h
-- (default: the ground the camera looks at), as bardroid_touch.lua's planePoint
local function planeAt(x, y, h)
	if not h then
		local cs = Spring.GetCameraState()
		h = Spring.GetGroundHeight(cs.px, cs.pz)
	end
	local dx, dy, dz = Spring.GetPixelDir(x, y)
	if not dy or dy > -0.01 then
		return nil
	end
	local px, py, pz = Spring.GetCameraPosition()
	local t = (h - py) / dy
	return px + dx * t, pz + dz * t
end

-- nothing moves the camera any more (the touch widget makes a pan over a few frames)
local settleCam
local function settle()
	local cs = Spring.GetCameraState()
	local last = settleCam
	settleCam = cs
	if not (last and math.abs(cs.px - last.px) < 0.5 and math.abs(cs.pz - last.pz) < 0.5
		and math.abs((cs.dist or 0) - (last.dist or 0)) < 0.5 and math.abs((cs.rx or 0) - (last.rx or 0)) < 0.001) then
		return false
	end
	settleCam = nil
end

local function camera(px, pz, dist, rx, outward)
	local cs = Spring.GetCameraState()
	cs.px, cs.pz, cs.dist, cs.rx, cs.ry = px, pz, dist, rx, 0
	Spring.SetCameraState(cs, 0)
	if outward then
		local forward = Spring.GetCameraVectors().forward
		if forward[3] > 0 then -- looking into the map (+z): turn round to look out over the z = 0 edge
			cs = Spring.GetCameraState()
			cs.ry = cs.ry + math.pi
			Spring.SetCameraState(cs, 0)
		end
	end
end

local function check(case, ax, az, bx, bz, moved)
	if not (ax and bx) then
		fails = fails + 1
		log("FAIL " .. case .. ": no point")
		return
	end
	local off = math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	local ok = off < math.max(20, (moved or 0) * 0.25)
	fails = fails + (ok and 0 or 1)
	log(string.format("%s %s: %.0f off%s", ok and "PASS" or "FAIL", case, off,
		moved and string.format(" after %.0f", moved) or ""))
end

-- The touch widget's answer for where the pointer is (LuaUI/Config/bardroid_hover.txt: "x y answer"; 1 interface,
-- 0 map); false (try again) until it is the wanted one, up to the runner's 30 tries
local hoverTries = 0
local function hoverAnswer(case, want)
	local f = io.open("LuaUI/Config/bardroid_hover.txt", "r")
	local got = f and tonumber((f:read("*l") or ""):match("(%d)%s*$"))
	if f then
		f:close()
	end
	if got ~= want and hoverTries < 20 then
		hoverTries = hoverTries + 1
		return false
	end
	hoverTries = 0
	local ok = got == want
	fails = fails + (ok and 0 or 1)
	log(string.format("%s %s: %s", ok and "PASS" or "FAIL", case, tostring(got)))
end

-- The overlay file the touch widget writes for the app (LuaUI/Config/bardroid_overlay.txt: "1" BAR's lobby is over the
-- game, "0" not); false (try again) until it says want, up to the runner's 30 tries
local overlayTries = 0
local function overlayIs(case, want)
	local f = io.open("LuaUI/Config/bardroid_overlay.txt", "r")
	local got = f and (f:read("*l") or "") or "none"
	if f then
		f:close()
	end
	if got ~= want and overlayTries < 20 then
		overlayTries = overlayTries + 1
		return false
	end
	overlayTries = 0
	local ok = got == want
	fails = fails + (ok and 0 or 1)
	log(string.format("%s %s: %s", ok and "PASS" or "FAIL", case, got))
end

local before, grab, endX, endY, row, mapRow
local function moved()
	local cs = Spring.GetCameraState()
	return math.sqrt((cs.px - before.px) ^ 2 + (cs.pz - before.pz) ^ 2)
end

local cases = {
	-- on the map: the point under the finger stays under it
	function() camera(Game.mapSizeX / 2, Game.mapSizeZ / 2, 2500, 1.9) end,
	settle,
	function()
		local y = math.floor(vsy * 0.55)
		before, grab, endX, endY = Spring.GetCameraState(), { groundAt(cx, y) }, cx + 120, y + 60
		touch(string.format("pan %d %d %d %d", cx, y, endX, endY))
	end,
	settle,
	function()
		local x, z = groundAt(endX, endY)
		check("a drag on the map holds the point under the finger", grab[1], grab[2], x, z, moved())
	end,
	-- a pinch on the map: its point stays put
	function()
		endX, endY = cx + 200, math.floor(vsy * 0.6)
		grab = { groundAt(endX, endY) }
		touch(string.format("zoom 1.4 %d %d", endX, endY))
	end,
	settle,
	function()
		local x, z = groundAt(endX, endY)
		check("a pinch on the map zooms about its point", grab[1], grab[2], x, z)
	end,
	-- a twist turns the camera the other way round (the map turns with the fingers); fingers down tilt it
	function()
		before = Spring.GetCameraState()
		touch("rot 0.3")
		touch("tilt 0.04")
	end,
	settle,
	function()
		local cs = Spring.GetCameraState()
		local turned = before.ry - cs.ry
		local ok = math.abs(turned - 0.3) < 0.02
		fails = fails + (ok and 0 or 1)
		log(string.format("%s a twist of 0.3 turns the camera by it: %.3f", ok and "PASS" or "FAIL", turned))
		ok = cs.rx > before.rx + 0.01
		fails = fails + (ok and 0 or 1)
		log(string.format("%s fingers down tilt the camera: rx %.3f -> %.3f", ok and "PASS" or "FAIL", before.rx, cs.rx))
	end,
	-- pinched far out: the camera stops at the touch widget's limit (a third past the map's longer side)
	function() touch(string.format("zoom 0.02 %d %d", cx, math.floor(vsy / 2))) end,
	settle,
	function()
		local cs = Spring.GetCameraState()
		local limit = math.max(Game.mapSizeX, Game.mapSizeZ) * 1.333
		local ok = cs.dist and cs.dist <= limit + 1 and cs.dist > limit * 0.5
		fails = fails + (ok and 0 or 1)
		log(string.format("%s a pinch far out stops at the limit: %.0f of %.0f", ok and "PASS" or "FAIL", cs.dist or -1, limit))
	end,
	-- past the edge, looking out over it: across and up (until 2026-11-03 up and down there went against the finger)
	function() camera(Game.mapSizeX / 2, 700, 2500, 1.9, true) end,
	settle,
	function()
		row = math.floor(vsy * 0.3)
		if groundAt(cx, row) or not planeAt(cx, row) then
			log("SKIP the void cases: the row at 30% shows the map or the sky")
			step = step + 8 -- (past the three void cases)
			return
		end
		before, grab, endX, endY = Spring.GetCameraState(), { planeAt(cx, row) }, cx + 100, row - 40
		touch(string.format("pan %d %d %d %d", cx, row, endX, endY))
	end,
	settle,
	function()
		local x, z = planeAt(endX, endY)
		check("a drag over the void past the edge holds the point under the finger", grab[1], grab[2], x, z, moved())
	end,
	-- a pinch there: its point stays put
	function()
		grab = { planeAt(cx, row) }
		touch(string.format("zoom 1.5 %d %d", cx, row))
	end,
	settle,
	function()
		local x, z = planeAt(cx, row)
		check("a pinch over the void zooms about its point", grab[1], grab[2], x, z)
	end,
	-- across the edge: from the map up onto the void (the camera backs away from the edge; the other way round it ran
	-- into the edge's clamp: the void's point brought near meant a camera past the edge)
	function()
		mapRow = math.floor(vsy * 0.8)
		local x, z, h = groundAt(cx, mapRow)
		if not h then
			log("SKIP across the edge: the row at 80% shows no map")
			step = step + 2
			return
		end
		before, grab, endX, endY = Spring.GetCameraState(), { x, z, h }, cx + 40, row
		touch(string.format("pan %d %d %d %d", cx, mapRow, endX, endY))
	end,
	settle,
	function()
		local x, z = planeAt(endX, endY, grab[3])
		local cs = Spring.GetCameraState()
		local detail = string.format("target %.0f,%.0f -> %.0f,%.0f; grabbed %.0f,%.0f, now under the finger %s",
			before.px, before.pz, cs.px, cs.pz, grab[1], grab[2], x and string.format("%.0f,%.0f", x, z) or "nothing")
		check("a drag from the map onto the void holds the point under the finger (" .. detail .. ")", grab[1], grab[2],
			x, z, moved())
	end,
	-- over the sky (the camera tilted up to the horizon): the map moves
	function() camera(Game.mapSizeX / 2, Game.mapSizeZ / 2, 2500, 1.62) end,
	settle,
	function()
		row = nil
		for y = 2, math.floor(vsy * 0.5), 4 do
			local _, dy = Spring.GetPixelDir(cx, y)
			if dy and dy > -0.01 then
				row = y
			end
		end
		if not row then
			log("SKIP a drag over the sky: no sky at that tilt")
			step = step + 2
			return
		end
		before = Spring.GetCameraState()
		touch(string.format("pan %d %d %d %d", cx, row, cx, row + 80))
	end,
	settle,
	function()
		local ok = moved() > 1
		fails = fails + (ok and 0 or 1)
		log(string.format("%s a drag over the sky moves the map: %.0f", ok and "PASS" or "FAIL", moved()))
	end,
	-- the pointer over the build and order menus answers "interface" (a finger's drag there drags, not pans), over the
	-- map "map": in the controller game the menus are v0.8.5's, which answer no IsAbove of their own
	function() camera(Game.mapSizeX / 2, Game.mapSizeZ / 2, 2500, 1.9) end,
	settle,
	function()
		-- (upright the portrait dock stands in BAR's menus' place: the pointer on it answers interface)
		local P = WG.BarDroidPortrait
		local d = P and P.active and P.active() and P.dock and P.dock()
		if d then
			uprightDock = true
			Spring.WarpMouse(math.floor((d[1] + d[3]) / 2), math.floor((d[2] + d[4]) / 2))
			return
		end
		local o = WG.ordermenu
		if not (o and o.getPosition and (not o.getIsShowing or o.getIsShowing())) then
			log("SKIP the menus' answers: no order menu shown")
			step = step + 5 -- (to the done step: the menus' five steps)
			return
		end
		local x, y, w, h = o.getPosition()
		Spring.WarpMouse(math.floor((x + w / 2) * vsx), math.floor((y - h / 2) * vsy))
	end,
	function()
		return hoverAnswer(uprightDock and "the pointer on the upright dock answers interface"
			or "the pointer on the order menu answers interface", 1)
	end,
	function()
		local b = WG.buildmenu
		if uprightDock then -- (the dock is the build menu too: checked above)
			step = step + 1
			return
		end
		if not (b and b.getSize and b.getIsShowing and b.getIsShowing()) then
			log("SKIP the build menu's answer: none shown")
			step = step + 1
			return
		end
		local top, bottom = b.getSize()
		if top > 1 then -- (BAR's grid menu gives pixels)
			top, bottom = top / vsy, bottom / vsy
		end
		Spring.WarpMouse(math.floor(vsx * 0.05), math.floor((top + bottom) / 2 * vsy))
	end,
	function() return hoverAnswer("the pointer on the build menu answers interface", 1) end,
	function() Spring.WarpMouse(math.floor(vsx * 0.6), math.floor(vsy * 0.55)) end,
	function() return hoverAnswer("the pointer on the map answers map", 0) end,
	-- BAR's lobby over the game (the top bar's Lobby): BAR tells the widgets "LobbyOverlayActive1" / "0", sent here the
	-- same way. The app is told (bardroid_overlay.txt), the dock steps aside ("dock none"), and the fingers' camera lines
	-- leave the game behind the lobby; with the lobby gone they pan again (2026-11-17)
	function()
		camera(Game.mapSizeX / 2, Game.mapSizeZ / 2, 2500, 1.9)
		Spring.SendLuaUIMsg("LobbyOverlayActive1")
	end,
	function() return overlayIs("the app is told BAR's lobby is over the game", "1") end,
	function()
		local P = WG.BarDroidPortrait
		if P and P.active and P.active() then
			local f = io.open("LuaUI/Config/bardroid_dock.txt", "r")
			local head = f and f:read("*l") or ""
			if f then
				f:close()
			end
			local ok = head == "dock none"
			fails = fails + (ok and 0 or 1)
			log(string.format("%s the dock steps aside under BAR's lobby: %s", ok and "PASS" or "FAIL", head))
		end
		before = Spring.GetCameraState()
		local y = math.floor(vsy * 0.4)
		touch(string.format("pan %d %d %d %d", cx, y, cx + 150, y + 90))
		touch(string.format("zoom 1.5 %d %d", cx, y))
	end,
	settle,
	function()
		local cs = Spring.GetCameraState()
		local m = moved() + math.abs((cs.dist or 0) - (before.dist or 0))
		local ok = m < 1
		fails = fails + (ok and 0 or 1)
		log(string.format("%s a drag and a pinch on BAR's lobby leave the game's camera: %.1f", ok and "PASS" or "FAIL", m))
		Spring.SendLuaUIMsg("LobbyOverlayActive0")
	end,
	function() return overlayIs("the app is told BAR's lobby is gone", "0") end,
	function()
		before = Spring.GetCameraState()
		local y = math.floor(vsy * 0.4)
		touch(string.format("pan %d %d %d %d", cx, y, cx + 150, y + 90))
	end,
	settle,
	function()
		local ok = moved() > 1
		fails = fails + (ok and 0 or 1)
		log(string.format("%s with BAR's lobby gone a drag pans again: %.0f", ok and "PASS" or "FAIL", moved()))
	end,
	function()
		log(fails == 0 and "done: ALL PASS" or ("done: " .. fails .. " FAILED"))
		widgetHandler:RemoveWidget()
	end,
}

function widget:Update()
	frames = frames + 1
	-- (from 10 s of game: BAR's own camera move to the start position comes in the first seconds)
	if Spring.GetGameFrame() < 300 or frames < waitUntil then
		return
	end
	step = step + 1
	local c = cases[step]
	if not c then
		return
	end
	local ok, result = pcall(c)
	if not ok then
		fails = fails + 1
		log("FAIL case " .. step .. " errored: " .. tostring(result))
		result = nil
	end
	if result == false and repeats < 30 then -- not ready yet: the same case again 15 frames later
		step, repeats = step - 1, repeats + 1
	else
		repeats = 0
	end
	waitUntil = frames + 15
end
