-- BAR Droid lobby touch: the lobby (Chobby, Chili) for fingers (Kailil, 2026-10-27: "it is miserable to try to touch
-- and drag the tiny scroll bar"; "tapping servers to only cause the popup ... then touching it again lets me join").
-- On the phone a finger is the mouse (RtsTouch: down = press, drag = move, up = release), so this widget, ahead of
-- Chili's input widget, holds back a press on a list until it knows what the finger does:
--   drag     the list scrolls with the finger (and glides after a flick); nothing is clicked
--   tap      the click Chili would have had, on release
--   tap on a server (battle list)  its details (Chobby's own server tooltip) and a bar: Close, Previous, Next, Join;
--            a second tap on the same server joins it
-- Presses outside lists, on sliders, text boxes and scroll bars go to Chili as before. After a press the hover tooltips
-- wait until the pointer moves on (a finger leaves it where it lifted: a tooltip stayed up), and again from where a
-- drag on a list ends. Also: a warning in a server
-- whose settings take away the app's controls (Kailil, 2026-11-01: the lobby has no room to show them), and the pad's
-- Start in the lobby: the interface scale 100% or 130% (launch-bar.sh starts at 100%). Installed into LuaMenu/Widgets
-- by the app; Chobby loads it with its "loadLocalWidgets" setting (launch-bar.sh).

function widget:GetInfo()
	return {
		name = "BAR Droid lobby touch",
		desc = "Finger scrolling in the lobby's lists; server details before joining; warns of settings that stop the controls",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		-- before Chili's input (api_chili: an API widget, layer -1000). The engine's LuaHandler sorts every API widget
		-- ahead of the others whatever their layer: without api, Chili takes every press and nothing scrolls.
		api = true,
		layer = -100000,
		enabled = true,
	}
end

local DRAG_PX = 14 -- a finger that moves this far (screen pixels) scrolls instead of clicking
local FLING_MIN, FLING_DECAY = 150, 4 -- list pixels a second; per second
local BLOCKERS = { trackbar = true, editbox = true, scrollbar = true, colorbars = true }
local SCALE_KEY = 302 -- Scroll Lock (the engine's key code): ControllerBridge sends it for the pad's Start
local SCALE_SMALL, SCALE_LARGE = 1.0, 1.3
local WARNING_CHECK_S = 0.5 -- a joined server's settings arrive after the join, and its host can change them later
local OFF_VALUES = { ["0"] = true, ["false"] = true }
-- (the title white and the reason in the box's tint, a size smaller: with the title tinted and the reason white, the
-- reason outshone what the warning is about, dev phone 2026-11-05)
local WARNING_RED = { fill = { 0.5, 0.06, 0.05, 1 }, edge = { 0.95, 0.3, 0.25, 1 }, why = "\255\255\205\170" }
local WARNING_AMBER = { fill = { 0.42, 0.27, 0.02, 1 }, edge = { 0.95, 0.7, 0.2, 1 }, why = "\255\255\225\130" }

local Chili, screen0
local press, fling
local hush -- where the last press left the pointer: Chili's hover tooltip held back until it moves (Update)
local popupButton, bar
local warning, warningTitle, warningWhy, warningColour, warningShown, warningClosed, warningBattle, warningSize, warningCheck

local function uiScale()
	return WG.uiScale or 1
end

-- Spring's mouse coordinates as Chili's input widget hands them to the screen, and the screen's own hit-test point
-- (Screen:MouseDown flips y with the engine's view height)
local function chiliPoint(x, y)
	local s = uiScale()
	local sx, sy = x / s, y / s
	return sx, sy, sx, select(2, Spring.GetViewSizes()) - sy
end

-- Chili hands out each control behind proxies (New returns a hard link, every child's .parent is a weak link of its
-- own): compare the controls themselves. (Without this a tap on the server bar never counted as ours: the bar closed
-- and the tap went to whatever was behind it.)
local function real(obj)
	return obj and Chili.UnlinkSafe and Chili.UnlinkSafe(obj) or obj
end

local function battleIdOf(obj)
	return type(obj.tooltip) == "string" and tonumber(obj.tooltip:match("^battle_tooltip_(%d+)$"))
end

local function isOurs(obj)
	local ours = real(bar)
	while obj do
		if real(obj) == ours then
			return true
		end
		obj = obj.parent
	end
	return false
end

local function overflows(obj)
	return obj.SetScrollPos and obj.contentArea and obj.clientArea and obj.verticalScrollbar ~= false
		and obj.contentArea[4] > obj.clientArea[4] + 1
end

-- The innermost list within obj that lies under the point, by its place on the screen. Chili's hit test passes over a
-- list's labels and gaps (no handler of their own) to the window behind it: a finger on a settings line's words, or
-- between them and its control, did not scroll the lobby's Settings (only its checkbox lines did; dev phone,
-- 2026-11-02). Searched only inside what was hit, so a dropdown open over a list is not scrolled through.
local function listUnder(obj, hx, hy)
	obj = real(obj)
	if not obj or obj.hidden or obj.visible == false or not obj.LocalToScreen then
		return nil
	end
	local x, y = obj:LocalToScreen(0, 0)
	if hx < x or hy < y or hx > x + (obj.width or 0) or hy > y + (obj.height or 0) then
		return nil
	end
	for _, child in ipairs(obj.children or {}) do
		local inner = listUnder(child, hx, hy)
		if inner then
			return inner
		end
	end
	return overflows(obj) and obj or nil
end

-- What a press on hit means: the list it scrolls, the server row it is on, or nothing of ours (a slider, a text box,
-- a scroll bar, outside lists).
local function classify(hit, hx, hy)
	local panel, battle
	local obj, top = real(hit), real(screen0)
	while obj and obj ~= top do
		if BLOCKERS[obj.classname] then
			return nil, nil
		end
		if not battle and obj.name == "battleButton" and battleIdOf(obj) then
			battle = obj
		end
		if overflows(obj) then
			if obj == real(hit) and obj.IsAboveVScrollbars then
				local lx, ly = obj:ScreenToLocal(hx, hy)
				if obj:IsAboveVScrollbars(lx, ly) then
					return nil, nil -- the scroll bar itself: Chili drags it
				end
			end
			panel = obj
			break
		end
		obj = real(obj.parent)
	end
	if not panel and not battle then
		panel = listUnder(hit, hx, hy)
	end
	return panel, battle
end

local function mods()
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	return { alt = alt, ctrl = ctrl, meta = meta, shift = shift }
end

-- the click Chili's input widget would have sent
local function click(x, y)
	local sx, sy = chiliPoint(x, y)
	local m = mods()
	screen0:MouseDown(sx, sy, 1, m)
	screen0:MouseUp(sx, sy, 1, m)
end

--------------------------------------------------------------------------------
-- Server details

local function closePopup()
	if popupButton and WG.TooltipHandler and WG.TooltipHandler.TooltipOverrideClear then
		WG.TooltipHandler.TooltipOverrideClear()
	end
	popupButton = nil
	if bar then
		bar:Hide()
	end
end

local function scrollPanelOf(obj)
	obj = obj and obj.parent
	while obj do
		if obj.SetScrollPos and obj.contentArea then
			return obj
		end
		obj = obj.parent
	end
end

local function serverRows(panel)
	local rows = {}
	local function walk(obj)
		for _, c in ipairs(obj.children or {}) do
			if type(c) == "table" then
				if c.name == "battleButton" and battleIdOf(c) and c.visible ~= false then
					local _, y = c:LocalToScreen(0, 0)
					rows[#rows + 1] = { button = c, y = y }
				else
					walk(c)
				end
			end
		end
	end
	walk(panel)
	table.sort(rows, function(a, b)
		return a.y < b.y
	end)
	return rows
end

local makeBar, placeBar
local function openPopup(button)
	popupButton = real(button)
	if WG.TooltipHandler and WG.TooltipHandler.TooltipOverride then
		WG.TooltipHandler.TooltipOverride(button.tooltip)
	end
	makeBar()
	placeBar()
	bar:Show()
	bar:BringToFront()
end

local function step(dir)
	local panel = popupButton and scrollPanelOf(popupButton)
	if not panel then
		return
	end
	local rows = serverRows(panel)
	for i, r in ipairs(rows) do
		if real(r.button) == popupButton then
			local next = rows[i + dir]
			if next then
				-- into view: its place in the list's content, centred
				local _, py = panel:LocalToScreen(0, 0)
				local ca = panel.clientArea
				panel:SetScrollPos(nil, next.y - py - ca[2] + panel.scrollPosY + (next.button.height or 0) / 2, true)
				openPopup(next.button)
			end
			return
		end
	end
end

local function join()
	local button = popupButton
	closePopup()
	if button and button.OnClick then
		button:CallListeners(button.OnClick)
	end
end

-- centred at the bottom of the screen as it is now (folding or unfolding the phone resizes the lobby's screen)
local barSize
placeBar = function()
	local sw, sh = screen0.width, screen0.height
	local w, h = math.min(sw - 16, 760), 70
	bar:SetPos(math.floor((sw - w) / 2), sh - h - 10, w, h)
	barSize = sw .. "x" .. sh
end

makeBar = function()
	if bar then
		return
	end
	bar = Chili.Window:New({
		name = "bardroidServerBar",
		parent = screen0,
		x = 0,
		y = 0,
		width = 100,
		height = 70,
		resizable = false,
		draggable = false,
		padding = { 6, 6, 6, 6 },
	})
	local font = WG.Chobby and WG.Chobby.Configuration and WG.Chobby.Configuration:GetFont(3)
	local actions = {
		{ "Close", closePopup },
		{ "Previous", function() step(-1) end },
		{ "Next", function() step(1) end },
		{ "Join", join, "positive_button" }, -- (the skin's "go ahead", as its red negative_button is "cancel")
	}
	for i, a in ipairs(actions) do
		Chili.Button:New({
			parent = bar,
			x = string.format("%.1f%%", (i - 1) * 25 + 0.5),
			y = 0,
			width = "24%",
			bottom = 0,
			caption = a[1],
			classname = a[3],
			objectOverrideFont = font,
			OnClick = { a[2] },
		})
	end
	bar:Hide()
end

--------------------------------------------------------------------------------
-- A server's settings that stop the app's controls (BAR's luaui/barwidgets.lua). The controls are user widgets:
-- custom widgets off, or Anonymous Mode, keeps all of them out of a player's game (a spectator's game is exempt);
-- unit control widgets off only stops first person (the rest of the app gives no Spring.GiveOrder).

local function warningLines(title, why, colour)
	return "\255\255\255\255" .. title .. "\n" .. colour.why .. why, colour
end

local function controlsWarning(options)
	-- (the app's widgets loaded as the game's, an engine-branch build: launch-bar.sh's BARDROID_GAME_WIDGETS; neither
	-- setting reaches them there)
	if VFS.FileExists("LuaUI/Config/bardroid_game_widgets.txt", VFS.RAW) then
		return nil
	end
	local anonymous = options.teamcolors_anonymous_mode
	if OFF_VALUES[tostring(options.allowuserwidgets)] or (anonymous and anonymous ~= "disabled") then
		return warningLines("Touch and gamepad controls will not work if you play here",
			"The host turned off custom widgets. They do work if you spectate.", WARNING_RED)
	end
	if OFF_VALUES[tostring(options.allowunitcontrolwidgets)] then
		return warningLines("First person will not work in this game",
			"The host turned off unit control widgets. Touch and gamepad controls work.", WARNING_AMBER)
	end
end

-- at the top of the screen as it is now (the scale and folding the phone both resize the lobby's screen)
local function placeWarning()
	local sw = screen0.width
	local w = math.min(sw - 16, 900)
	warning:SetPos(math.floor((sw - w) / 2), 8, w, 92)
	warningSize = sw .. "x" .. screen0.height
end

local function closeWarning()
	warningClosed = warningShown
	warningShown = nil
	warning:Hide()
end

local function makeWarning()
	local config = WG.Chobby and WG.Chobby.Configuration
	local font = config and config:GetFont(3)
	local small = config and config:GetFont(2) or font
	warning = Chili.Window:New({
		name = "bardroidLobbyWarning",
		parent = screen0,
		x = 0,
		y = 0,
		width = 100,
		height = 92,
		resizable = false,
		draggable = false,
		padding = { 0, 0, 0, 0 },
	})
	-- (the title and the reason each a line of their own, apart and in the middle of the box: as one text box's two
	-- lines they touched, with the box's room all below them)
	warningTitle = Chili.TextBox:New({
		parent = warning,
		x = 14,
		y = 16,
		right = 118,
		height = 30,
		text = "",
		objectOverrideFont = font,
	})
	warningWhy = Chili.TextBox:New({
		parent = warning,
		x = 14,
		y = 52,
		right = 118,
		bottom = 0,
		text = "",
		objectOverrideFont = small,
	})
	Chili.Button:New({
		parent = warning,
		right = 8,
		y = 8,
		width = 100,
		bottom = 8,
		caption = "OK",
		objectOverrideFont = font,
		OnClick = { closeWarning },
	})
	Chili.Control:New({ -- (the last child draws first; a window's own colour only tints the skin's dark, clear picture)
		parent = warning,
		x = 0,
		y = 0,
		width = "100%",
		height = "100%",
		padding = { 0, 0, 0, 0 },
		drawcontrolv2 = true, -- (drawn in its own place, Chili 2.1: without it a warning in every lobby's log)
		DrawControl = function(obj)
			gl.Texture(false)
			gl.Color(warningColour.edge)
			gl.Rect(0, 0, obj.width, obj.height)
			gl.Color(warningColour.fill)
			gl.Rect(2, 2, obj.width - 2, obj.height - 2)
			gl.Color(1, 1, 1, 1)
		end,
	})
	warning:Hide()
end

-- Nothing while no server is joined. A warning closed stays closed until it says something else, the host takes the
-- setting back, or the player is in another server.
local function updateWarning()
	local lobby = WG.LibLobby and WG.LibLobby.lobby
	local battle = lobby and lobby.myBattleID
	local text, colour
	if battle then
		text, colour = controlsWarning(lobby.modoptions or {})
	end
	if not text or battle ~= warningBattle then
		warningClosed = nil
	end
	warningBattle = battle
	if text == warningClosed then
		text = nil
	end
	if text ~= warningShown then
		warningShown = text
		if not warning then
			makeWarning()
		end
		if text then
			local title, why = text:match("^(.-)\n(.*)$")
			warningTitle:SetText(title or text)
			warningWhy:SetText(why or "")
			warningColour = colour
			placeWarning()
			warning:Show()
			warning:BringToFront()
		else
			warning:Hide()
		end
	elseif warningShown and warningSize ~= screen0.width .. "x" .. screen0.height then
		placeWarning()
	end
end

--------------------------------------------------------------------------------
-- The interface scale, the same on every screen size (Chobby keeps one per size: folding would change it back)

local function toggleScale()
	local config = WG.Chobby and WG.Chobby.Configuration
	if not (config and config.SetUiScale) then
		return
	end
	local scale = (config.uiScale or SCALE_SMALL) < (SCALE_SMALL + SCALE_LARGE) / 2 and SCALE_LARGE or SCALE_SMALL
	for size in pairs(config.uiScalesForScreenSizes or {}) do -- (a lobby version without the per-size table: just the scale)
		config.uiScalesForScreenSizes[size] = scale
	end
	config:SetUiScale(scale)
end

function widget:KeyPress(key)
	if key ~= SCALE_KEY then
		return false
	end
	toggleScale()
	return true
end

--------------------------------------------------------------------------------
-- Input

function widget:MousePress(x, y, button)
	hush = { x = x, y = y } -- (any button: a finger's long press is a right click, and lifted there too)
	if button ~= 1 or not screen0 or Spring.IsGUIHidden() then
		return false
	end
	fling = nil
	local _, _, hx, hy = chiliPoint(x, y)
	local hit = screen0:HitTest(hx, hy)
	if hit and isOurs(hit) then
		return false -- the server bar's own buttons
	end
	local panel, battle = nil, nil
	if hit then
		panel, battle = classify(hit, hx, hy)
	end
	if popupButton and battle ~= popupButton then
		closePopup() -- a tap elsewhere: the details go
	end
	if not (panel or battle) then
		return false
	end
	press = { x = x, y = y, panel = panel, battle = battle, start = panel and panel.scrollPosY or 0, moved = false,
		lastY = y, lastT = Spring.GetTimer(), vel = 0 }
	return true
end

function widget:MouseMove(_, y)
	local p = press
	if not p then
		return false
	end
	if not p.moved and p.panel and math.abs(y - p.y) > DRAG_PX then
		p.moved = true
	end
	if p.moved then
		local s = uiScale()
		p.panel:SetScrollPos(nil, p.start + (y - p.y) / s, false, true)
		local now = Spring.GetTimer()
		local dt = Spring.DiffTimers(now, p.lastT)
		if dt > 0.001 then
			p.vel = p.vel * 0.6 + (y - p.lastY) / s / dt * 0.4
			p.lastY, p.lastT = y, now
		end
	end
	return true
end

function widget:MouseRelease(x, y)
	local p = press
	press = nil
	if not p then
		return false
	end
	hush = { x = x, y = y } -- (after a drag too: a replay's teams came up where the finger lifted)
	if p.moved then
		if math.abs(p.vel) > FLING_MIN and Spring.DiffTimers(Spring.GetTimer(), p.lastT) < 0.1 then
			fling = { panel = p.panel, v = p.vel }
		end
	elseif p.battle then
		if popupButton == p.battle then
			join()
		else
			openPopup(p.battle)
		end
	else
		click(x, y)
	end
	return true
end

--------------------------------------------------------------------------------
-- The app's lines in the lobby (RtsTouch's touch log, the one the game's widget reads; Kailil, 2026-11-06: "I want the
-- text chat stuff working in lobby too", "allow dpad menu navigation via selection in the lobby"):
--   speak to chat (a three-finger tap; the pad's LB held + RB twice): the words go to the server room's chat while one
--     is joined, else to the chat tab open; while it listens D-pad left / right or a sideways swipe step through them
--     (the room first, then each tab), a note at the top saying where
--   the pad's D-pad: the pointer onto the nearest control that way (a button, a tab, a list's row, a box), ringed in
--     gold; A clicks it as always. Only what is not covered (a dialog in front keeps the D-pad on itself); in a list
--     the D-pad scrolls on past its last row in sight. The left stick or a finger moving the pointer away lets go.

local TOUCH_LOG = "LuaUI/Config/bardroid_touch.txt"
local logFile, logPos

-- the log's new whole lines since the last call (none the first time: what came before is not replayed). Its size only
-- every 30 calls (a seek to the end is an fstat, which proot traps: bardroid_touch.lua's newTouchLines); else reads on.
local logCalls = 0
local function appLines()
	if not logFile then
		logFile = io.open(TOUCH_LOG, "r")
		logPos = logFile and logFile:seek("end")
		return nil
	end
	logCalls = logCalls + 1
	if logCalls % 30 == 0 then
		local size = logFile:seek("end")
		if not size then
			logFile:close()
			logFile = nil
			return nil
		end
		if size < logPos then
			logPos = 0 -- (the app began the log anew)
		end
	end
	if not logFile:seek("set", logPos) then
		return nil
	end
	local text = logFile:read("*a") or ""
	if text == "" then
		return nil
	end
	local last = text:match(".*()\n")
	if not last then
		return nil
	end
	logPos = logPos + last
	return text:sub(1, last)
end

local GOLD = { 1, 0.78, 0.25, 1 }

-- Speak to chat

local voiceOn, voiceTarget = false, nil -- listening; the target picked, by name (kept for the lobby's session)
local voicePanel, voiceLabel
local voiceTextW = 0 -- its words' width, as the font measures them

local function voiceTargets()
	local targets = {}
	local lobby = WG.LibLobby and WG.LibLobby.lobby
	if lobby and lobby.myBattleID then
		targets[#targets + 1] = { name = "SERVER ROOM", send = function(text) lobby:SayBattle(text) end }
	end
	local root = WG.Chobby and WG.Chobby.interfaceRoot
	local chat = root and root.GetChatWindow and root.GetChatWindow()
	local tabBar = chat and chat.tabPanel and chat.tabPanel.tabBar
	for i, child in ipairs(tabBar and tabBar.children or {}) do
		local console = chat.tabbars and chat.tabbars[child.name]
		if console and console.listener then
			local user = child.name:match("^(.-) messages$")
			targets[#targets + 1] = { name = user and ("@" .. user) or ("#" .. child.name), tab = child.name,
				open = tabBar.selected == i, send = console.listener }
		end
	end
	return targets
end

-- the target now: the one picked if it is still there, else the server room, else the open tab, else the first
local function voiceCurrent(targets)
	for _, t in ipairs(targets) do
		if t.name == voiceTarget then
			return t
		end
	end
	if targets[1] and targets[1].name == "SERVER ROOM" then
		return targets[1]
	end
	for _, t in ipairs(targets) do
		if t.open then
			return t
		end
	end
	return targets[1]
end

local function voiceShow()
	if not voicePanel then
		local config = WG.Chobby and WG.Chobby.Configuration
		voicePanel = Chili.Window:New({
			name = "bardroidLobbyVoice",
			parent = screen0,
			x = 0, y = 8, width = 100, height = 56,
			resizable = false, draggable = false,
			padding = { 0, 0, 0, 0 },
		})
		-- (not Chili's autosize: sized to its text while the panel was still 100 wide, the words sat off centre and their
		-- start was cut, "'EAK TO CHAT: JOIN A SERVER ...", dev phone, 2026-11-09)
		voiceLabel = Chili.Label:New({
			parent = voicePanel,
			x = 0, y = 0, right = 0, bottom = 0,
			autosize = false,
			align = "center", valign = "center",
			caption = "",
			objectOverrideFont = config and config:GetFont(3),
		})
	end
	local target = voiceCurrent(voiceTargets())
	local caption = target and ("< SPEAK TO " .. string.upper(target.name) .. " >")
		or "SPEAK TO CHAT: JOIN A SERVER OR OPEN THE CHAT"
	local font = voiceLabel.font
	local ok, textW = pcall(function() return font:GetTextWidth(caption) end)
	voiceTextW = ok and tonumber(textW) or 0
	local w = math.min(screen0.width - 16, math.max(640, math.ceil(voiceTextW) + 48)) -- (a long name: the panel grows)
	voicePanel:SetPos(math.floor((screen0.width - w) / 2), 8, w, 56)
	voiceLabel:SetPos(0, 0, w, 56)
	voiceLabel:SetCaption(caption)
	voicePanel:Show()
	voicePanel:BringToFront()
end

local function voiceStep(by)
	local targets = voiceTargets()
	local now = voiceCurrent(targets)
	if not now then
		return
	end
	local at = 1
	for i, t in ipairs(targets) do
		if t == now then
			at = i
		end
	end
	local nextOne = targets[(at - 1 + by) % #targets + 1]
	voiceTarget = nextOne.name
	if nextOne.tab then -- (its tab shown: where the words will be)
		local root = WG.Chobby and WG.Chobby.interfaceRoot
		local chat = root and root.GetChatWindow and root.GetChatWindow()
		pcall(function() chat.tabPanel.tabBar:Select(nextOne.tab) end)
	end
	voiceShow()
end

-- (a game loaded beside the lobby: the engine's ActivateGame / ActivateMenu. Words said in a game are the game's
-- chat's alone; the app marks them "voicegame", which this widget does not read, and while a game runs the lobby
-- leaves "voice" lines to it too: Kailil, 2026-11-08, "the voice chat is also sending chats to the lobby")
-- The rest of speaking goes with the words: "voice_on" put the lobby's "< SPEAK TO SERVER ROOM >" up too, and the
-- D-pad's channel steps switched the lobby's chat tabs behind the game (2026-11-08).
local gameLoaded = false
function widget:ActivateGame()
	gameLoaded = true
	voiceOn = false
	if voicePanel then
		voicePanel:Hide()
	end
end
function widget:ActivateMenu() gameLoaded = false end

local function voiceSay(text)
	if gameLoaded then
		return
	end
	text = text:gsub("%s+", " "):gsub("^ ", "")
	local target = voiceCurrent(voiceTargets())
	if target and text:find("%S") then
		pcall(target.send, text)
	end
end

-- The D-pad from control to control

local FOCUS_CLASSES = { "button", "checkbox", "tabbaritem", "combobox", "editbox", "trackbar" }
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local focus, focusRing, focusAt -- the control the D-pad put the pointer on, its ring, where the pointer went (mouse pixels)

local function focusable(obj)
	if obj.OnClick and #obj.OnClick > 0 then
		return true
	end
	for _, c in ipairs(FOCUS_CLASSES) do
		if obj.InheritsFrom and obj:InheritsFrom(c) then
			return true
		end
	end
	return false
end

-- every focusable control in sight: { obj, x0, y0, x1, y1 } in the screen's own coordinates, cut to the lists they sit in
local function collect(obj, clip, out)
	obj = real(obj)
	if not obj or obj.hidden or obj.visible == false or not obj.LocalToScreen or obj == real(focusRing) then
		return
	end
	local x, y = obj:LocalToScreen(0, 0)
	local r = { math.max(x, clip[1]), math.max(y, clip[2]), math.min(x + (obj.width or 0), clip[3]),
		math.min(y + (obj.height or 0), clip[4]) }
	if r[3] - r[1] < 6 or r[4] - r[2] < 6 then
		return
	end
	if obj ~= real(screen0) and focusable(obj) then
		out[#out + 1] = { obj = obj, r = r }
		return -- (a button's children are its caption and picture)
	end
	local inner = overflows(obj) and r or clip
	for _, child in ipairs(obj.children or {}) do
		collect(child, inner, out)
	end
end

-- not covered: the screen's own hit test at its middle lands on it (or inside it)
local function onTop(c)
	local cx, cy = (c.r[1] + c.r[3]) / 2, (c.r[2] + c.r[4]) / 2
	local hit = screen0:HitTest(cx, cy)
	hit = real(hit)
	while hit do
		if hit == c.obj then
			return true
		end
		hit = real(hit.parent)
	end
	return false
end

local function pointerToChili()
	local mx, my = Spring.GetMouseState()
	local _, _, hx, hy = chiliPoint(mx, my)
	return hx, hy
end

local function focusRect()
	local obj = focus and real(focus)
	if not obj or obj.disposed or not obj.parent or not obj:IsVisibleOnScreen() then
		return nil
	end
	local x, y = obj:LocalToScreen(0, 0)
	return x, y, obj.width or 0, obj.height or 0
end

local function placeRing()
	local x, y, w, h = focusRect()
	if not x then
		focus = nil
		if focusRing then
			focusRing:Hide()
		end
		return
	end
	if not focusRing then
		focusRing = Chili.Control:New({
			name = "bardroidLobbyFocus",
			parent = screen0,
			x = 0, y = 0, width = 10, height = 10,
			padding = { 0, 0, 0, 0 },
			drawcontrolv2 = true,
			HitTest = function() return false end, -- (never in the way of a click)
			DrawControl = function(obj)
				gl.Texture(false)
				gl.Color(GOLD)
				local t = 3
				gl.Rect(0, 0, obj.width, t)
				gl.Rect(0, obj.height - t, obj.width, obj.height)
				gl.Rect(0, t, t, obj.height - t)
				gl.Rect(obj.width - t, t, obj.width, obj.height - t)
				gl.Color(1, 1, 1, 1)
			end,
		})
	end
	focusRing:SetPos(x - 3, y - 3, w + 6, h + 6)
	focusRing:Show()
	focusRing:BringToFront()
end

local function navigate(dir)
	if not screen0 then
		return
	end
	local d = DIRECTIONS[dir]
	local ox, oy
	local fx, fy, fw, fh = focusRect()
	if fx then
		ox, oy = fx + fw / 2, fy + fh / 2
	else
		ox, oy = pointerToChili()
	end
	local function best()
		local list = {}
		collect(screen0, { 0, 0, screen0.width, screen0.height }, list)
		local pick, score = nil, math.huge
		for _, c in ipairs(list) do
			if c.obj ~= real(focus) then
				local vx, vy = (c.r[1] + c.r[3]) / 2 - ox, (c.r[2] + c.r[4]) / 2 - oy
				local along = vx * d[1] + vy * d[2]
				if along > 4 then
					local s = along + math.abs(vx * d[2] - vy * d[1]) * 2.5
					if s < score and onTop(c) then
						pick, score = c, s
					end
				end
			end
		end
		return pick
	end
	local pick = best()
	if not pick and fx and d[1] == 0 then -- (the end of a list in sight: it scrolls on, then the next row)
		local obj = real(real(focus).parent)
		while obj and not overflows(obj) do
			obj = real(obj.parent)
		end
		if obj then
			obj:SetScrollPos(nil, obj.scrollPosY + d[2] * math.max(24, fh), false, true)
			pick = best()
		end
	end
	if not pick then
		return
	end
	focus = pick.obj
	local cx, cy = (pick.r[1] + pick.r[3]) / 2, (pick.r[2] + pick.r[4]) / 2
	local s = uiScale()
	local mx, my = math.floor(cx * s + 0.5), math.floor((select(2, Spring.GetViewSizes()) - cy) * s + 0.5)
	if Spring.WarpMouse then
		pcall(Spring.WarpMouse, mx, my)
	end
	focusAt = { mx, my }
	placeRing()
	Spring.Echo(string.format("[bardroid-lobby] the pad on %s \"%s\" at %d %d", tostring(pick.obj.classname),
		tostring(pick.obj.caption or pick.obj.name or ""), mx, my)) -- (tools/lobby-phone-test.ps1)
end

local function appUpdate()
	local lines = appLines()
	if lines then
		for name in lines:gmatch("act (%S+)") do
			if name == "voice_on" then
				voiceOn = not gameLoaded -- (in a game: the game's own note and channels)
				if voiceOn then
					voiceShow()
				end
			elseif name == "voice_off" then
				voiceOn = false
				if voicePanel then
					voicePanel:Hide()
				end
			elseif voiceOn and (name == "voice_channel_next" or name == "voice_channel_prev") then
				voiceStep(name == "voice_channel_next" and 1 or -1)
			else
				local dir = name:match("^lobby_nav_(%a+)$")
				if DIRECTIONS[dir] then
					navigate(dir)
				end
			end
		end
		for hex in lines:gmatch("voice (%x+)") do
			voiceSay((hex:gsub("%x%x", function(h)
				return string.char(tonumber(h, 16))
			end)))
		end
	end
	if focus then -- (the pointer moved away: let go; the control moved, as a list scrolls: the ring follows)
		local mx, my = Spring.GetMouseState()
		if not focusAt or math.abs(mx - focusAt[1]) + math.abs(my - focusAt[2]) > 24 then
			focus = nil
		end
		placeRing()
	end
end

local lastUpdate
function widget:Update() -- (the lobby's Update has no frame time)
	local now = Spring.GetTimer()
	local dt = lastUpdate and math.min(0.1, Spring.DiffTimers(now, lastUpdate)) or 0
	lastUpdate = now
	if not screen0 then
		Chili = WG.Chili
		screen0 = Chili and Chili.Screen0
		return
	end
	if fling then
		local panel = fling.panel
		if panel.disposed or not panel.parent then
			fling = nil
		else
			panel:SetScrollPos(nil, panel.scrollPosY + fling.v * dt, false, true)
			fling.v = fling.v * math.exp(-dt * FLING_DECAY)
			if math.abs(fling.v) < 20 then
				fling = nil
			end
		end
	end
	-- A finger leaves the pointer where it lifted, and Chili's hover tooltip of whatever is under it stayed up: on the
	-- Skirmish screen a tapped map's picture as large as the screen, over the Next button (dev phone, 2026-11-02). Held
	-- back from a press until the pointer moves away; a mouse moving on gets its tooltips as before. And the hover look
	-- once the button is up: Cancel tapped in the Register dialog left the Welcome screen's "Code of Conduct" under the
	-- pointer lit as if picked (dev phone, 2026-11-03). Chili hovers a control again only when the pointer reaches another
	-- (Screen:IsAbove), so one MouseOut keeps it plain; a mouse moving on over that same control lights it again.
	if hush then
		local mx, my, left, middle, right = Spring.GetMouseState()
		if math.abs(mx - hush.x) + math.abs(my - hush.y) > DRAG_PX then
			local out = hush.out
			hush = nil
			if out and screen0._lastHoveredControl == out then
				pcall(function() out:MouseOver() end)
			end
		else
			screen0.currentTooltip = nil
			local hovered = screen0._lastHoveredControl
			if hovered and hovered ~= hush.out and not (left or middle or right) then
				hush.out = hovered
				pcall(function() hovered:MouseOut() end) -- (a weak link: its control may be gone)
			end
		end
	end
	if popupButton and (popupButton.disposed or not popupButton.parent or popupButton.visible == false) then
		closePopup() -- the list went away (another screen, the server closed)
	elseif popupButton and barSize ~= screen0.width .. "x" .. screen0.height then
		placeBar() -- folded or unfolded
	end
	if not warningCheck or Spring.DiffTimers(now, warningCheck) >= WARNING_CHECK_S then
		warningCheck = now
		updateWarning()
	end
	appUpdate()
end

function widget:Initialize()
	-- (tools/lobby-touch-test.ps1: the same input as a finger, without one)
	WG.BarDroidLobbyTouch = {
		press = function(x, y) return widget:MousePress(x, y, 1) end,
		move = function(x, y) return widget:MouseMove(x, y, 0, 0, 1) end,
		release = function(x, y) return widget:MouseRelease(x, y, 1) end,
		popup = function() return popupButton end,
		warning = function() return warningShown end,
		-- (tools/lobby-touch-test: speak to chat's panel up, and a game loaded or not, as the engine's callins say)
		voiceShown = function() return voicePanel ~= nil and voicePanel.visible ~= false end,
		-- the panel, its label and the words' width (panel x, y, w, h; label x, w; words w; screen w; caption)
		voiceRect = function()
			if not voicePanel then
				return nil
			end
			return voicePanel.x, voicePanel.y, voicePanel.width, voicePanel.height, voiceLabel.x, voiceLabel.width,
				voiceTextW, screen0 and screen0.width, voiceLabel.caption
		end,
		activate = function(game)
			if game then
				widget:ActivateGame()
			else
				widget:ActivateMenu()
			end
		end,
	}
end

function widget:Shutdown()
	WG.BarDroidLobbyTouch = nil
	closePopup()
	if bar then
		bar:Dispose()
		bar = nil
	end
	if warning then
		warning:Dispose()
		warning = nil
	end
end
