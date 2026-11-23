-- LuaMenu widget for tools/menusession-phone-test.ps1: two games in one lobby session (RC 0.2.0 item 7). A lobby
-- session is one engine: the lobby starts a game by Spring.Reload with its script (Chobby's InterfaceSkirmish, here its
-- StartGameFromString with the phone's skirmish.txt) and BAR's Leave goes back the same way (Spring.Reload("")), so
-- launch-bar.sh runs once for all of them. The offline lobby (bardroid_login_wait.lua): the login dialog's Cancel, game 1
-- started; in it the LuaUI widget (bardroid_menusession_ui_test.lua) breaks the app's build menu copy and checks BAR's
-- own in its place, then says "game1 checked"; back to the lobby; game 2 started, checked the same way ("game2
-- checked"). The lobby's widgets stay loaded through a game's Reload (dev phone, 2026-11-23): the engine's
-- ActivateGame and ActivateMenu say where the session stands; should they load again, the state file says it. Logs
-- "[menusession] ..." lines.
function widget:GetInfo()
	return { name = "BAR Droid menu session test (lobby)", desc = "Two games in one lobby session", author = "BAR Droid",
		layer = 0, enabled = true }
end

local STATE = "LuaUI/Config/bardroid_menusession_state.txt" -- (nil, game1, back1, game2, end)
local UI = "LuaUI/Config/bardroid_menusession_ui.txt" -- (the game widget's word)
local stage, stageAt, clock = "wait", 0, 0
local menuAt -- (the lobby back after game 1: ActivateMenu's time, or 0 when this widget loaded again there)

local function log(s)
	Spring.Echo("[menusession] " .. s)
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
local function writeLine(path, s)
	local f = io.open(path, "w")
	if f then
		f:write(s .. "\n")
		f:close()
	end
end
local function go(s)
	stage, stageAt = s, clock
end
local function real(o)
	return o and WG.Chili and WG.Chili.UnlinkSafe and WG.Chili.UnlinkSafe(o) or o
end
local function plain(s)
	return type(s) == "string" and s:gsub("\255...", ""):gsub("^%s+", ""):gsub("%s+$", "") or nil
end
local function click(caption) -- (setup, not under test: the button's own listeners)
	local found
	local function walk(o, depth)
		o = real(o)
		if found or not o or o.disposed or depth > 40 or o.visible == false then
			return
		end
		if o.classname ~= "label" and plain(o.caption) == caption and o.OnClick ~= nil and #o.OnClick > 0 then
			found = o
			return
		end
		for _, ch in ipairs(o.children or {}) do
			walk(ch, depth + 1)
		end
	end
	walk(WG.Chili and WG.Chili.Screen0, 0)
	if found then
		found:CallListeners(found.OnClick)
	end
	return found ~= nil
end
local function finish(why)
	log("FAIL " .. why)
	writeLine(STATE, "end")
	writeLine(UI, "end")
	go("over")
end

local function startGame(n)
	local f = io.open("skirmish.txt", "r") -- (the phone's skirmish: the launcher's map, BAR's game as installed)
	local script = f and f:read("*a")
	if f then
		f:close()
	end
	local lobby = WG.LibLobby and WG.LibLobby.localLobby
	if not script or script == "" or not (lobby and lobby.StartGameFromString) then
		finish(string.format("game %d from the lobby: skirmish.txt %s, the lobby's start %s", n, script and "read" or "missing",
			lobby and lobby.StartGameFromString and "there" or "missing"))
		return
	end
	writeLine(STATE, "game" .. n)
	lobby:StartGameFromString(script, "skirmish")
	log(string.format("(game %d started from the lobby: its StartGameFromString, Spring.Reload in this engine)", n))
	go("game" .. n)
end

function widget:Initialize()
	local state = readLine(STATE)
	log("(the lobby's widgets loaded: " .. tostring(state or "the session's start") .. ")")
	if state == "game1" or state == "game2" then
		stage = state
	elseif state == "back1" then
		stage, menuAt = "back1", 0
	elseif state ~= nil then
		stage = "over"
	end
end
function widget:ActivateGame()
	log("(a game of the session loaded: ActivateGame)")
end
function widget:ActivateMenu()
	menuAt = clock
	log("(the lobby back: ActivateMenu)")
end

function widget:Update()
	local now = Spring.GetTimer()
	widget.t0 = widget.t0 or now
	clock = Spring.DiffTimers(now, widget.t0)
	if stage == "wait" and clock > 6 and (WG.BarDroidLoggedIn or clock > 30) then
		click("Cancel") -- (the offline lobby's login dialog, if it shows)
		go("start1")
	elseif stage == "start1" and clock - stageAt > 2 then
		startGame(1)
	elseif stage == "game1" or stage == "game2" then -- (the game widget's checks)
		local word = readLine(UI)
		if word == stage .. " checked" then
			if stage == "game1" then
				writeLine(STATE, "back1")
				menuAt = nil
				log("(game 1 checked: back to the lobby, Spring.Reload(\"\") as BAR's Leave does)")
				go("back1")
				Spring.Reload("")
			else
				writeLine(STATE, "end")
				log("menu done")
				go("over")
			end
		elseif word == "end" then
			go("over")
		elseif clock - stageAt > 300 then
			finish(stage .. ": the game widget's checks not done in 5 min")
		end
	elseif stage == "back1" then
		if menuAt and clock - menuAt > 5 then
			startGame(2)
		elseif clock - stageAt > 120 then
			finish("back in the lobby after game 1: not in 2 min (no ActivateMenu)")
		end
	end
end
