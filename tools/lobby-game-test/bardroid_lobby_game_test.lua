-- LuaMenu widget for tools/lobby-game-test.ps1: the lobby's Skirmish screen with the controller game, as the phone
-- sets it up (Chobby's byar-dev config, games/BAR-gamepad.sdd as the app installs it). The lobby reads the game's
-- options from that archive alone (2026-10-27: without modoptions.lua in it the Skirmish screen stayed empty).
-- Logs "[lobbygame] PASS|FAIL <case>" and "[lobbygame] done".
function widget:GetInfo()
	return { name = "BAR Droid lobby game test", desc = "Checks the lobby's Skirmish screen with the controller game",
		author = "BAR Droid", layer = 0, enabled = true }
end

local GAME = "Beyond All Reason $VERSION"
local step, wait, fails = 0, 0, 0

local function log(s)
	Spring.Echo("[lobbygame] " .. s)
end

-- the click on a main menu button (Chobby's tab panel: "<tab>_button"; its click runs the tab's entry check, which
-- picks the singleplayer game, then shows the tab)
local function clickMenu(tab)
	local b = WG.Chili.Screen0:GetObjectByName(tab .. "_button")
	if not b then
		return false
	end
	b:CallListeners(b.OnClick)
	return true
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	log((ok and "PASS " or "FAIL ") .. case .. (detail and (": " .. detail) or ""))
end

local cases = {
	function()
		log("start")
		local name = WG.Chobby.Configuration:GetDefaultGameName()
		check("the singleplayer game is the controller game", name == GAME and VFS.HasArchive(GAME), tostring(name))
		check("the Skirmish button is there", clickMenu("skirmish"))
	end,
	function()
		local wrapper = WG.Chili.Screen0:GetObjectByName("singleplayerWrapper")
		check("Skirmish: the battle room is built", wrapper ~= nil and #wrapper.children > 0,
			wrapper and (#wrapper.children .. " children") or "no singleplayerWrapper")
		local options = WG.ModoptionsPanel and WG.ModoptionsPanel.ReturnModoptions()
		check("Skirmish: the game's options load", type(options) == "table" and #options > 0,
			type(options) == "table" and (#options .. " options") or tostring(options))
		log("done: " .. (fails == 0 and "ALL PASS" or fails .. " FAILED"))
	end,
}

local t0 = Spring.GetTimer()
function widget:Update()
	-- the lobby builds its interface first
	if Spring.DiffTimers(Spring.GetTimer(), t0) < 8 or not (WG.Chobby and WG.Chobby.interfaceRoot) then
		return
	end
	wait = wait - 1
	if wait > 0 then
		return
	end
	step = step + 1
	local c = cases[step]
	if c then
		local ok, err = pcall(c)
		if not ok then
			check("case " .. step .. " ran", false, tostring(err))
		end
		wait = 30
	end
end
