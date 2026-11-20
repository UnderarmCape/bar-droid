-- LuaUI widget for tools/overgame-phone-test.ps1, the game's half (bardroid_overgame_menu_test.lua drives the lobby): in
-- the game loaded from the lobby's Load Game, BAR's Lobby on the top bar found (WG.topbar.buttonAt) and tapped; the
-- overlay file "1" (bardroid_touch.lua); after the lobby's drag the camera where it was; once the lobby has gone
-- (Return to Battle) the overlay file "0", the camera knob and rails back, and a drag on the map pans the camera.
-- Asks "do <n> tap|shot|swipe ..." in LuaUI/Config/bardroid_overgame_ui.txt, answered "<n>" in
-- bardroid_overgame_ui_cmd.txt; "end" there when done. Steps by real time (the lobby pauses the game).
function widget:GetInfo()
	return { name = "BAR Droid over-game test (game)", desc = "The lobby over a game: the game's side", author = "BAR Droid",
		layer = 0, enabled = true }
end

local OUT, CMD_FILE = "LuaUI/Config/bardroid_overgame_ui.txt", "LuaUI/Config/bardroid_overgame_ui_cmd.txt"
local MENU_FILE = "LuaUI/Config/bardroid_overgame_menu.txt"
local OVERLAY, CAM_FILE = "LuaUI/Config/bardroid_overlay.txt", "LuaUI/Config/bardroid_camctl.txt"
local stage, stageAt = "wait", 0
local asked, after = 0, nil
local readAt
local clock, t0 = 0, nil
local cam0, lobbyAt
local chobby = Spring.GetMenuName and string.find(string.lower(Spring.GetMenuName() or ""), "chobby") ~= nil

local function check(case, ok, detail)
	Spring.Echo("[overgame] " .. (ok and "PASS " or "FAIL ") .. case .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function write(text)
	local f = io.open(OUT, "w")
	if f then
		f:write(text)
		f:close()
	end
end
local function readLine(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end
local function go(s)
	stage, stageAt = s, clock
end
local function ask(action, x, y, nextStage, x2, y2)
	local vsx = Spring.GetViewGeometry()
	asked = asked + 1
	write(string.format("do %d %s %d %d %d%s\n", asked, action, math.floor(x or 0), math.floor(y or 0), vsx,
		x2 and string.format(" %d %d", math.floor(x2), math.floor(y2)) or ""))
	after = nextStage
	go("asked")
end
local function camMoved(a, b)
	local worst = 0
	for _, k in ipairs({ "px", "py", "pz", "dist", "height", "rx", "ry", "rz" }) do
		if type(a[k]) == "number" and type(b[k]) == "number" then
			worst = math.max(worst, math.abs(a[k] - b[k]) / (k:sub(1, 1) == "r" and 0.01 or 1))
		end
	end
	return worst
end
-- BAR's Lobby button on the top bar (X pixels from the top left), found along its strip
local function lobbyButton()
	local tb = WG.topbar
	local pos = tb and tb.GetButtonsPosition and tb.GetButtonsPosition()
	if not (pos and tb.buttonAt) then
		return nil, "no top bar"
	end
	local vsy = select(2, Spring.GetViewGeometry())
	local y = math.floor((pos[2] + pos[4]) / 2)
	local x0, x1, seen = nil, nil, {}
	for x = math.floor(pos[1]), math.floor(pos[3]), 3 do
		local b = tb.buttonAt(x, y)
		if b then
			seen[b] = true
		end
		-- (in a game of the lobby's, BAR's "quit" button is its Lobby: gui_top_bar_buttons.lua, bardroid_topbar.lua's
		-- showLobby)
		if b == "lobby" or (b == "quit" and chobby) then
			x0, x1 = x0 or x, x
		end
	end
	local names = {}
	for b in pairs(seen) do
		names[#names + 1] = b
	end
	return x0 and { (x0 + x1) / 2, vsy - y } or nil, table.concat(names, " ")
end

local function step()
	local vsx, vsy = Spring.GetViewGeometry()
	if stage == "wait" and clock > 8 then -- (the save's game in, BAR's top bar up)
		local names
		lobbyAt, names = lobbyButton()
		Spring.Echo(string.format("[overgame] (in the game: %dx%d, frame %d; the top bar's buttons: %s; the menu %s)", vsx, vsy,
			Spring.GetGameFrame(), tostring(names), tostring(Spring.GetMenuName and Spring.GetMenuName())))
		if not lobbyAt then
			check("BAR's Lobby on the top bar (a game from the lobby)", false, "not found")
			go("end")
			return
		end
		cam0 = Spring.GetCameraState()
		ask("tap", lobbyAt[1], lobbyAt[2], "over?")
	elseif stage == "over?" and clock - stageAt > 2 then
		check("... the overlay file \"1\" (the app's touch in the lobby)", readLine(OVERLAY) == "1", tostring(readLine(OVERLAY)))
		go("dragwait")
	elseif stage == "dragwait" then
		local m = readLine(MENU_FILE)
		if m == "dragged" or m == "menu done" then
			local moved = camMoved(cam0, Spring.GetCameraState())
			check("a drag over the lobby: the game's camera under it still", moved < 1, string.format("moved %.2f", moved))
			go("backwait")
		elseif clock - stageAt > 90 then
			check("the lobby's drag", false, "no word from the lobby in 90 s")
			go("end")
		end
	elseif stage == "backwait" then
		if readLine(MENU_FILE) == "menu done" then
			go("back?")
		elseif clock - stageAt > 60 then
			check("the lobby's steps", false, "not done in 60 s")
			go("end")
		end
	elseif stage == "back?" and clock - stageAt > 2 then
		local cam = readLine(CAM_FILE)
		local C = WG.BarDroidCamCtl
		local on = C and ((C.knob and C.knob()) or (C.rails and C.rails()))
		check("back in the game: the overlay file \"0\"", readLine(OVERLAY) == "0", tostring(readLine(OVERLAY)))
		check("... the camera knob and rails back", not on or (cam ~= nil and cam ~= "none"), tostring(cam))
		cam0 = Spring.GetCameraState()
		-- (a drag on the map, well above the dock and clear of the rails: the camera pans)
		local P = WG.BarDroidPortrait
		local dock = P and P.dock and P.dock()
		local top = dock and dock[4] or 0
		local y = vsy - (top + (vsy - top) * 0.45)
		ask("swipe", vsx * 0.35, y, "pan?", vsx * 0.35, y + vsy * 0.12)
	elseif stage == "pan?" and clock - stageAt > 1.5 then
		local moved = camMoved(cam0, Spring.GetCameraState())
		check("... a drag on the map pans the camera", moved >= 1, string.format("moved %.2f", moved))
		ask("shot", 2, 0, "end")
	elseif stage == "end" then
		Spring.Echo("[overgame] game done")
		write("end\n")
		go("over")
	end
	if stage == "asked" and clock - (readAt or -1) >= 0.1 then
		readAt = clock
		local c = readLine(CMD_FILE)
		if c and tonumber(c) == asked then
			go(after)
		elseif clock - stageAt > 30 then
			check("the script's " .. tostring(after) .. " step", false, "not done in 30 s")
			go("end")
		end
	end
end

function widget:Update()
	local now = Spring.GetTimer()
	t0 = t0 or now
	clock = Spring.DiffTimers(now, t0)
	step()
end
