-- BAR Droid chat: BAR's chat lines laid out for a phone (Kailil, 2026-10-26: the text "only appears in the center of the
-- box ... ugly and a waste of space"; "slam the names to the left most sides and allow wordwrap on names if they go
-- past 10 characters"). BAR's chat gives each line a game-time column and a name column as wide as the longest player
-- name in the game, so on the Fold's inner screen the message wrapped in ~120 pixels. Here the names sit at the box's
-- left edge, broken every 10 characters, and the message fills the rest of the box.
-- BAR's chat widget still does the rest (sounds, ignore list, history when scrolled, map marker labels): its own lines
-- are hidden (WG.chat.setHide) and this widget gets every line it parsed through WG.chat.addChatProcessor. A few of
-- the engine's system lines BAR shows as console lines (paused, left the game, lagging) come from AddConsoleLine.
-- Typing (Kailil, 2026-10-28: "I want the message to word wrap and grow smaller as new lines populate so I can see my
-- entire message. Right now it's just pushing the message off screen to the right"; "the message chat box overlaps
-- with the GAME COUNT DOWN POP-UP"): BAR's typing box is one line under the chat lines. This widget opens its own on
-- Enter before BAR's chat hears the key (a lower layer hears keys first): at the top of the chat box, the text wrapped
-- and smaller as lines are added, the chat lines below it, and before the game starts everything above BAR's start
-- countdown. As BAR's: Enter sends, Ctrl / Alt / Shift + Enter switch to everyone / allies / spectators, Escape
-- cancels, Up and Down go through the messages sent, Ctrl+V pastes, "/" sends a command, BAR's word filter
-- (luaui/configs/badwords.lua) holds a message back once. "/hud" opens the app's layout editor (bardroid_layout.lua),
-- "/padspeed" the gamepad's path speed tuner (bardroid_padspeed.lua).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid chat",
		desc = "Chat lines with the names at the left edge and the text filling the box, a typing box that wraps",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -96000, -- (below BAR's chat, -95000: Enter comes here first)
		enabled = true,
	}
end

local FONT_SIZE = 0.75 -- of BAR's chat font size (Kailil: "make the text chat wayy smaller")
local NAME_CHARS = 10 -- a name is broken after this many characters
local LINES = 8 -- screen lines shown (BAR shows 5 lines of text; names broken in two take two)
local LINES_TYPING = 14 -- while the typing box is open (BAR's own history is switched off for it)
local LINE_TTL = 40 -- seconds a line stays (BAR's)
local BOX_RIGHT = 0.74 -- of the screen width (BAR's chat box)
local UPRIGHT_TEXT = 0.87 -- upright, of FONT_SIZE (the row across the screen)
local BACKGROUND = 0.3
local MAX_BYTES = 127 -- a message's length at most (BAR's typing box)
local TYPE_SIZE = 1.03 / 0.75 -- the typing text, of the chat lines' size (BAR's typing box: 1.03 x its chat font)
local TYPE_FULL_LINES = 2 -- lines at that size; with more the text gets smaller ...
local TYPE_MIN = 0.55 -- ... down to this much of it
-- BAR's start countdown ("Game starts in 3", gui_pregameui): 67% up the screen, its font 18.5 x (0.75 + pixels / 6e6)
local COUNTDOWN_Y, COUNTDOWN_FONT = 0.67, 18.5
local MODES = { -- (BAR's channels: everyone, allies, spectators)
	[""] = { label = "All", color = "\255\255\255\255" },
	["a:"] = { label = "Allies", color = "\255\120\235\120" },
	["s:"] = { label = "Specs", color = "\255\255\225\110" },
}

local LineTypes = { Player = 1, Spectator = 2, Mapmark = 3, Battleroom = 4, System = 5 } -- BAR's gui_chat.lua
local WHITE = "\255\255\255\255"
local SYSTEM_COLOR = "\255\200\200\200"

-- seconds of real time, on the engine's timer as in the app's other widgets (the engine's os.clock measured the same
-- on the phone: x1.00, 2026-10-28)
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local timer0 = spGetTimer()
local function clock()
	return spDiffTimers(spGetTimer(), timer0)
end
local entries = {} -- { time, chunks = name pieces, nameColor, text, lines = wrapped text }
-- BAR's chat as the player has it (hidden or not, its history over the typing box), given back at the end (giveBack)
local hooked, wasInputHistory, wasHidden = false, nil, false
-- this widget's config version: none, from a version whose end left BAR's chat saved hidden (SetConfigData)
local CONFIG_VERSION, configVersion = 1, nil
local relayoutNext = false -- (ViewResize: once more in the next Update, BAR's top bar placed by then)
local chatMinimap, chatMinimapAt -- upright: the minimap's height the box was laid out under, when it was looked at
local vsx, vsy = Spring.GetViewGeometry()
local font, nameFont, fontSize, lineHeight
local boxLeft, boxRight, boxTop, nameWidth, textLeft, gap, maxLines

-- The layout editor's settings for the chat box (bardroid_layout.lua): moved by dx, dy (of the screen), size (its width
-- and lines), text size, padding
local NO_EDITS = { dx = 0, dy = 0, size = 1, text = 1, pad = 1 }
local function edits()
	local L = WG.BarDroidLayout
	return L and L.get("chat") or NO_EDITS
end

-- Words wrapped into lines no wider than width pixels at size; a word longer than a line is cut. Each line starts with
-- the colour the text had there.
-- The last colour code in s ("\255" and three bytes, which can be 255 too), or nil.
local function lastColorCode(s)
	local code, i = nil, 1
	while i <= #s do
		if s:byte(i) == 255 then
			code = s:sub(i, i + 3)
			i = i + 4
		else
			i = i + 1
		end
	end
	return code
end

local function wrap(text, width, size)
	local lines, line, color = {}, "", ""
	local function push()
		lines[#lines + 1] = line
		line = color
	end
	for word in text:gmatch("%S+") do
		local lastColor = lastColorCode(word)
		local candidate = (line == "" or line == color) and line .. word or line .. " " .. word
		if font:GetTextWidth(candidate) * size <= width then
			line = candidate
		else
			if line ~= "" and line ~= color then
				push()
			end
			candidate = line .. word
			while font:GetTextWidth(candidate) * size > width and #candidate > 1 do
				local cut = #candidate - 1
				while cut > 1 and font:GetTextWidth(candidate:sub(1, cut)) * size > width do
					cut = cut - 1
				end
				line = candidate:sub(1, cut)
				push()
				candidate = color .. candidate:sub(cut + 1)
			end
			line = candidate
		end
		color = lastColor or color
	end
	if line ~= "" and line ~= color then
		lines[#lines + 1] = line
	end
	return lines
end

-- How far an entry's longest line reaches on the screen: the box ends there when no typing box is open above it (a
-- short line had a box three quarters of the screen wide)
local function reach(e)
	local w = 0
	for _, line in ipairs(e.lines) do
		w = math.max(w, font:GetTextWidth(line) * fontSize)
	end
	return (#e.chunks > 0 and textLeft or boxLeft + gap) + w
end

local function chunks(name)
	local out = {}
	for i = 1, #name, NAME_CHARS do
		out[#out + 1] = name:sub(i, i + NAME_CHARS - 1)
	end
	return out
end

-- upright, the minimap's height the box goes under: while it waits small (bardroid_minimap.lua: as tall as the top
-- bar's row); opened by a tap it lies over the box's corner for its few seconds, the box does not jump down and back
local function smallMinimap()
	local M = WG.BarDroidMinimap
	if M and M.small and M.small() and WG.minimap and WG.minimap.getHeight then
		return WG.minimap.getHeight() or 0
	end
	return 0
end

local function layout()
	vsx, vsy = Spring.GetViewGeometry()
	if not (WG.fonts and WG.fonts.getFont) then
		return false
	end
	font = WG.fonts.getFont()
	nameFont = WG.fonts.getFont(2, 1.2, 0.13, 20) or font
	-- BAR's chat: 21 x a small-screen boost x vsy * 0.00075 x ui_scale
	local barSize = 21 * math.min(1.2, math.max(1, 1 + (1 - vsy / 1200) * 0.5)) * vsy * 0.00075
		* (Spring.GetConfigFloat("ui_scale", 1) or 1)
	local ed = edits()
	local upright = vsy > vsx * 1.05
	-- (upright a little smaller: Kailil, 2026-11-10, the chat a row of its own: "Its okay for the text size to be a
	-- little smaller")
	fontSize = barSize * FONT_SIZE * (upright and UPRIGHT_TEXT or 1) * ed.text
	lineHeight = math.floor(fontSize * 1.3)
	gap = math.floor(fontSize * 0.6 * ed.pad)
	maxLines = math.max(2, math.floor(LINES * ed.size + 0.5))
	local p = WG.topbar and WG.topbar.GetPosition and WG.topbar.GetPosition()
	local left = p and p[1] or vsx * 0.3
	if upright then
		-- upright: a row of its own across the screen under BAR's top bar and the small minimap beside it (Kailil,
		-- 2026-11-10: "make chat take up the entire row instead of sharing the row with the map"); under the top bar alone,
		-- between the minimap and the top bar's buttons, it was a column 38 % wide where a long line took five rows. The
		-- minimap settles its size a little later: laid out again when it does (widget:Update)
		local mm = smallMinimap()
		chatMinimap = mm
		local margin = math.floor(vsx * 0.02)
		local top = math.min(p and p[2] or vsy * 0.94, vsy - mm) - fontSize * 0.5
		boxLeft = math.floor(math.max(0, math.min(vsx * 0.9, margin + ed.dx * vsx)))
		boxTop = math.floor(math.max(vsy * 0.1, math.min(vsy, top + ed.dy * vsy)))
		boxRight = math.floor(math.min(vsx - margin, boxLeft + (vsx - 2 * margin) * ed.size))
	else
		chatMinimap = nil
		boxLeft = math.floor(math.max(0, math.min(vsx * 0.9, left + ed.dx * vsx)))
		boxTop = math.floor(math.max(vsy * 0.1, math.min(vsy, (p and p[2] - fontSize * 0.5 or vsy * 0.94) + ed.dy * vsy)))
		boxRight = math.floor(math.min(vsx, boxLeft + (vsx * BOX_RIGHT - left) * ed.size))
	end
	-- the name column: the widest 10-character piece of any player's name
	nameWidth = nameFont:GetTextWidth("Player") * fontSize
	for _, playerID in ipairs(Spring.GetPlayerList() or {}) do
		for _, piece in ipairs(chunks(Spring.GetPlayerInfo(playerID, false) or "")) do
			nameWidth = math.max(nameWidth, nameFont:GetTextWidth(piece) * fontSize)
		end
	end
	nameWidth = math.ceil(nameWidth)
	textLeft = boxLeft + gap + nameWidth + gap
	for _, e in ipairs(entries) do
		e.lines = wrap(e.text, boxRight - gap - (#e.chunks > 0 and textLeft or boxLeft + gap), fontSize)
		e.right = reach(e)
	end
	return true
end

local function add(name, nameColor, text, ttl)
	-- BAR's messages (a ttl of their own) leave the list after their time, as BAR's own widget lets them go: not in the
	-- history the typing box shows, and repeated ones ("commander under attack") never push the players' lines out
	local now = clock()
	for i = #entries, 1, -1 do
		local o = entries[i]
		if o.ttl and now - o.time > o.ttl then
			table.remove(entries, i)
		end
	end
	local e = { time = now, chunks = name ~= "" and chunks(name) or {}, nameColor = nameColor, text = text, ttl = ttl }
	if font then
		e.lines = wrap(text, boxRight - gap - (name ~= "" and textLeft or boxLeft + gap), fontSize)
		e.right = reach(e)
	end
	entries[#entries + 1] = e
	if #entries > 100 then
		table.remove(entries, 1)
	end
	return e
end

-- BAR's chat calls this for every chat line it parsed: text carries its colour (all, allies, spectators)
local function processor(_, lineType, name, nameText, text, _, ignore)
	if not ignore and text and text ~= "" then
		local nameColor = (type(nameText) == "string" and nameText:match("^\255...")) or WHITE
		-- a unit share is BAR's system line with the sharer in nameText only (its name stays ""): the line read "shared
		-- Tidal Generator to Heroic_El_Paska" with no one in front (dev phone, a replay, 2026-11-05)
		if (name == nil or name == "") and type(nameText) == "string" then
			name = nameText:gsub("\255...", ""):match("^%s*<?(.-)>?%s*$")
		end
		if lineType == LineTypes.Player and text:sub(5, 6) == "> " then
			-- metal or energy given: "<key>:amount=500:name=Kailil", which BAR words from its translations
			local params, values = {}, {}
			for part in text:sub(7):gmatch("[^:]+") do
				params[#params + 1] = part
			end
			for i = 2, #params do
				local key, value = params[i]:match("^([^=]+)=(.*)$")
				if key then
					values[key] = value
				end
			end
			local ok, worded = pcall(function() return BAR.I18N(params[1], values) end)
			add(name or "", nameColor, SYSTEM_COLOR .. (ok and type(worded) == "string" and worded or "shared resources"))
		elseif lineType == LineTypes.Mapmark then
			add(name or "", nameColor, text .. SYSTEM_COLOR .. "  (map marker)")
		else
			add(name or "", nameColor, text)
		end
	end
	return text
end

local SYSTEM_LINES = { " paused the game", " unpaused the game", " left the game", " is lagging behind", "Sync error for" }
local WARNING_COLOR = "\255\255\220\120"
-- that line, where the pointer was (it goes once the pointer moves: Update), how to keep the game, the seconds shown
local quitNote, quitX, quitY, quitHow, quitShown
local function quitText(secs)
	return WARNING_COLOR .. "Leaving the game in " .. secs .. " s: " .. quitHow .. " to stay longer"
end
function widget:AddConsoleLine(line)
	if not hooked then
		return
	end
	-- BAR's Autoquit leaves an ended game after 12 s unless the pointer moves, and says so in the console only: on a
	-- phone the game closed with no word 12 s after a lost skirmish (dev phone, 2026-11-03). Said here for that time,
	-- counting down; a finger's tap moves the pointer, and then the line goes (BAR waits a minute after each move).
	local secs = line:match("<autoquit> Automatically exiting in (%d+) seconds")
	if secs then
		-- (BAR's Autoquit waits only for the pointer to move: the pad holds it in the middle, so with the pad too it is a
		-- tap on the screen; "move the mouse" was said to pad players, 2026-11-08)
		quitHow = WG.BarDroidInput == "mouse" and "move the mouse" or "tap the screen"
		quitShown = tonumber(secs)
		quitNote = add("", WHITE, quitText(quitShown), quitShown)
		quitX, quitY = Spring.GetMouseState()
		return
	end
	for _, s in ipairs(SYSTEM_LINES) do
		if line:find(s, 1, true) then
			add("", WHITE, SYSTEM_COLOR .. line:gsub("%s+", " "))
			return
		end
	end
end

-- BAR's messages ("Battle Started", a commander under attack, the tutorial's lines: snd_notifications sends them with
-- its voice lines) are typed by gui_messages at 16% of the screen's height from 31% of its width: on a phone, under the
-- order menu and the unit info, unread (dev phone, 2026-11-02); it has no position setter. Its WG.messages.addMessage
-- puts them in the chat box instead, in BAR's message white, for BAR's 15 seconds (they repeat: "wasting metal" every
-- few seconds would push the players' lines out of the box).
local MESSAGE_COLOR = "\255\240\240\240"
local MESSAGE_TTL = 15
local barAddMessage, ownAddMessage -- BAR's function, and the one in its place
local function takeMessages()
	local m = WG.messages
	if m and m.addMessage and m.addMessage ~= ownAddMessage then -- (again after a LuaUI reload makes a new WG.messages)
		barAddMessage = m.addMessage
		ownAddMessage = ownAddMessage or function(text)
			if type(text) == "string" and text:find("%S") then
				add("", WHITE, MESSAGE_COLOR .. (text:gsub("%s+", " ")), MESSAGE_TTL)
			end
		end
		m.addMessage = ownAddMessage
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Typing

local typing -- the open typing box: { chars = the text's UTF-8 characters, at = characters before the cursor, mode }
-- the channel of the last message (BAR's: the next box opens on it), kept across games (Kailil, 2026-11-06: speak to
-- chat's channel switched "permanently")
local CHANNEL_KEY = "bardroid_chat_channel"
local CHANNEL_SAVED = { all = "", allies = "a:", spectators = "s:" }
local lastMode = CHANNEL_SAVED[Spring.GetConfigString(CHANNEL_KEY, "") or ""]
local function keepMode(mode)
	lastMode = mode
	local name = mode == "a:" and "allies" or mode == "s:" and "spectators" or "all"
	if Spring.GetConfigString(CHANNEL_KEY, "") ~= name then
		Spring.SetConfigString(CHANNEL_KEY, name)
	end
end
-- the channel a message goes to now: the last one, else allies (a spectator's: spectators; allies is not theirs)
local function channelNow()
	local spec = Spring.GetSpectatingState()
	local mode = lastMode or (spec and "s:" or "a:")
	if spec and mode == "a:" then
		mode = "s:"
	end
	return mode
end
local sent, sentAt = {}, 0 -- the messages sent this game, and which one Up / Down show (#sent + 1: the new text)
local lastHeld -- a message BAR's word filter held back: sent as it is the second time (BAR's)
local badWords -- BAR's word filter's patterns (false: not found)
local charWidth = {} -- a character's width at font size 1
local typed -- the typing box as drawn: { size, lines = { { first, last } }, x0, y0, x1, y1, textX, tagWidth }

local function utf8Chars(s)
	local out = {}
	for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		out[#out + 1] = c
	end
	return out
end

local function widthOf(c)
	local w = charWidth[c]
	if not w then
		w = font:GetTextWidth(c)
		charWidth[c] = w
	end
	return w
end

-- the characters wrapped into lines at most width pixels wide at size: { { first, last } }, broken after the last
-- space that fits (a word longer than a line is cut)
local function wrapChars(cs, width, size)
	local lines, first, w, space = {}, 1, 0, nil
	local i = 1
	while i <= #cs do
		local cw = widthOf(cs[i]) * size
		if w + cw > width and i > first then
			local last = (space and space >= first and space < i) and space or i - 1
			lines[#lines + 1] = { first, last }
			first, w, space = last + 1, 0, nil
			for j = first, i - 1 do
				w = w + widthOf(cs[j]) * size
			end
		end
		if cs[i] == " " then
			space = i
		end
		w = w + cw
		i = i + 1
	end
	lines[#lines + 1] = { first, #cs }
	return lines
end

-- the typing box laid out: the text's size (smaller as lines are added) and lines, and the box under the chat box's top
local function layoutTyping()
	if not (typing and font) then
		typed = nil
		return
	end
	local mode = MODES[typing.mode]
	local base = fontSize * TYPE_SIZE
	local tagWidth = font:GetTextWidth(mode.label .. ": ") * base
	local textX = boxLeft + gap + tagWidth
	local width = boxRight - gap - textX
	local size, lines = base
	while true do
		lines = wrapChars(typing.chars, width, size)
		if #lines <= TYPE_FULL_LINES or size <= base * TYPE_MIN then
			break
		end
		size = math.max(base * TYPE_MIN, size * 0.9)
	end
	local lh = math.floor(size * 1.3)
	local height = #lines * lh + math.floor(gap * 0.8)
	typed = { size = size, lineHeight = lh, lines = lines, x0 = boxLeft, y1 = boxTop, x1 = boxRight,
		y0 = boxTop - height, textX = textX, base = base }
end

-- The box owns the text while open (widgetHandler:OwnText, as BAR's chat does): BAR's widget handler then gives every
-- key to it before BAR's hotkeys (its actions run before any other widget hears a key: typing "s" would also have
-- stopped the units selected).
local function openTyping(mode)
	if not widgetHandler:OwnText() then
		return false -- (another box has the keys)
	end
	typing = { chars = {}, at = 0, mode = mode, opened = clock() }
	sentAt = #sent + 1
	Spring.SDLStartTextInput() -- (as BAR's chat: text input may have been stopped by the lobby)
	layoutTyping()
	return true
end

local function closeTyping()
	if typing then
		widgetHandler:DisownText()
	end
	typing, typed = nil, nil
end

local function insert(s)
	local text = table.concat(typing.chars)
	for _, c in ipairs(utf8Chars(s)) do
		if #text + #c > MAX_BYTES then
			break
		end
		text = text .. c
		typing.at = typing.at + 1
		table.insert(typing.chars, typing.at, c)
	end
	layoutTyping()
end

local function badWord(text)
	if badWords == nil then
		local ok, list = pcall(VFS.Include, "luaui/configs/badwords.lua")
		badWords = ok and type(list) == "table" and list or false
	end
	for w in text:lower():gmatch("%w+") do
		for _, pattern in ipairs(badWords or {}) do
			if w:find(pattern) then
				return w
			end
		end
	end
end

local function i18n(key, values, fallback)
	local ok, s = pcall(function() return BAR.I18N(key, values) end)
	return ok and type(s) == "string" and s ~= key and s or fallback
end

local deliver -- (below)

local function send()
	local text, mode = table.concat(typing.chars), typing.mode
	keepMode(mode)
	closeTyping()
	if not text:find("%S") then
		return
	end
	if sent[#sent] ~= text then
		sent[#sent + 1] = text
	end
	deliver(text, mode)
end

-- A message to its channel: "/" a command, else BAR's word filter first (held back once), then sent
function deliver(text, mode)
	if text:sub(1, 1) == "/" then
		local command = text:sub(2)
		if (command == "hud" or command == "layout") and WG.BarDroidLayout then
			WG.BarDroidLayout.open()
		elseif command == "padspeed" and WG.BarDroidPadSpeed then
			WG.BarDroidPadSpeed.toggle()
		else
			Spring.SendCommands(command == "lr" and "luaui reload" or command)
		end
		return
	end
	local bad = badWord(text)
	if bad and text ~= lastHeld then
		lastHeld = text
		add("", WHITE, "\255\255\000\000" .. i18n("ui.chat.moderation.prefix", nil, "Moderation") .. " "
			.. SYSTEM_COLOR .. i18n("ui.chat.moderation.blocked", { badWord = bad }, "message not sent: \"" .. bad
			.. "\" (send it again to send it anyway)"))
		return
	end
	lastHeld = nil
	if mode == "a:" then
		Spring.SendAllyChat(text)
	elseif mode == "s:" then
		Spring.SendSpectatorChat(text)
	else
		Spring.SendPublicChat(text)
	end
end

local function showSent(i)
	sentAt = math.max(1, math.min(#sent + 1, i))
	typing.chars = utf8Chars(sent[sentAt] or "")
	typing.at = #typing.chars
	layoutTyping()
end

function widget:KeyPress(key, mods)
	if not hooked or Spring.IsGUIHidden() then
		return false
	end
	local chat = WG.chat or {}
	local enter = key == 13 or key == 271 -- (Return, the keypad's Enter)
	if not typing then
		if not enter or (chat.isInputActive and chat.isInputActive())
			or (chat.getHandleInput and not chat.getHandleInput()) then
			return false -- (BAR's own box is open for a map marker, or the player switched typing off in BAR)
		end
		local spec = Spring.GetSpectatingState()
		local mode = lastMode or (spec and "s:" or "a:")
		if mods.ctrl then
			mode = ""
		elseif mods.alt then
			mode = spec and "s:" or "a:"
		elseif mods.shift then
			mode = "s:"
		elseif spec and mode == "a:" then
			mode = "s:"
		end
		return openTyping(mode)
	end
	local cs = typing.chars
	if enter then
		if mods.ctrl then
			typing.mode = ""
		elseif mods.alt and not Spring.GetSpectatingState() then
			typing.mode = typing.mode == "a:" and "" or "a:"
		elseif mods.alt or mods.shift then
			typing.mode = typing.mode == "s:" and "" or "s:"
		else
			send()
			return true
		end
	elseif key == 27 then -- Escape
		closeTyping()
		return true
	elseif mods.ctrl and key == 118 then -- Ctrl+V
		insert((Spring.GetClipboard() or ""):gsub("[\r\n\t]+", " "))
		return true
	elseif key == 8 then -- Backspace
		if typing.at > 0 then
			table.remove(cs, typing.at)
			typing.at = typing.at - 1
		end
	elseif key == 127 then -- Delete
		if typing.at < #cs then
			table.remove(cs, typing.at + 1)
		end
	elseif key == 276 then -- Left
		typing.at = math.max(0, typing.at - 1)
	elseif key == 275 then -- Right
		typing.at = math.min(#cs, typing.at + 1)
	elseif key == 278 then -- Home
		typing.at = 0
	elseif key == 279 then -- End
		typing.at = #cs
	elseif key == 273 then -- Up: the message sent before
		showSent(sentAt - 1)
		return true
	elseif key == 274 then -- Down
		showSent(sentAt + 1)
		return true
	end
	typing.opened = clock() -- (the cursor shows steadily while keys are pressed)
	layoutTyping()
	return true -- (every key goes to the text while the box is open, none to the game's hotkeys)
end

function widget:TextInput(text)
	if not typing then
		return false
	end
	insert(text)
	typing.opened = clock()
	return true
end

-- A dark box in the shape of BAR's panels
local TYPING_BOX, LINES_BOX = { 0, 0, 0, 0.62 }, { 0, 0, 0, BACKGROUND }
local function box(x0, y0, x1, y1, color)
	local f = WG.FlowUI
	if f and f.Draw and f.Draw.RectRound then
		f.Draw.RectRound(x0, y0, x1, y1, f.elementCorner or 4, 1, 1, 1, 1, color, color)
	else
		gl.Color(color)
		gl.Rect(x0, y0, x1, y1)
	end
end

-- the typing box: the channel, the text (its lines wrapped), the cursor blinking
local function drawTyping()
	local t, mode = typed, MODES[typing.mode]
	box(t.x0, t.y0, t.x1, t.y1, TYPING_BOX)
	local corner = WG.FlowUI and WG.FlowUI.elementCorner or 0
	gl.Color(1, 1, 1, 0.25)
	gl.Rect(t.x0 + corner, t.y0, t.x1 - corner, t.y0 + 1)
	gl.Color(1, 1, 1, 1)
	local top = t.y1 - math.floor(gap * 0.4)
	local function baseline(r)
		return top - (r - 1) * t.lineHeight - math.floor(t.lineHeight * 0.78)
	end
	font:Begin()
	font:Print(mode.color .. mode.label .. ":", boxLeft + gap, baseline(1), t.size, "o")
	local cursorX, cursorRow = t.textX, 1
	for r, line in ipairs(t.lines) do
		local first, last = line[1], line[2]
		font:Print(WHITE .. table.concat(typing.chars, "", first, last), t.textX, baseline(r), t.size, "o")
		if typing.at >= first - 1 and typing.at <= last then
			cursorRow = r
			cursorX = t.textX + font:GetTextWidth(table.concat(typing.chars, "", first, typing.at)) * t.size
		end
	end
	font:End()
	if (clock() - typing.opened) % 1 < 0.6 then
		local y = baseline(cursorRow)
		gl.Color(1, 1, 1, 0.9)
		gl.Rect(cursorX, y - t.size * 0.2, cursorX + math.max(1, t.size * 0.08), y + t.size * 0.9)
	end
end

local function hook()
	local chat = WG.chat
	if not (chat and chat.setHide and chat.addChatProcessor) or not layout() then
		return false
	end
	wasHidden = chat.getHide and chat.getHide() or false
	chat.setHide(true)
	chat.addChatProcessor("bardroid_chat", processor)
	if chat.getChatInputHistory and chat.setChatInputHistory then
		wasInputHistory = chat.getChatInputHistory()
		chat.setChatInputHistory(false)
	end
	if configVersion ~= CONFIG_VERSION then
		-- BAR saved its chat as this widget keeps it (hidden, no history) at every game's end before: BAR's own
		-- defaults instead, once
		wasHidden = false
		if wasInputHistory ~= nil then
			wasInputHistory = true
		end
	end
	Spring.Echo("[bardroid-chat] BAR's chat lines drawn by BAR Droid chat")
	WG.bardroidChat = { -- (tools/touch-widget-test.ps1)
		-- what was said for the chat (the app's VoiceChat, bardroid_touch.lua): sent as a message typed and sent with
		-- Enter would be, to the channel Enter opens (the last one used, else allies; a spectator's: spectators), never
		-- a command
		voice = function(text)
			text = text:gsub("^/+", ""):gsub("%s+", " ")
			if not text:find("%S") then
				return
			end
			local cut = text
			if #text > MAX_BYTES then -- (BAR's length; never half a character at the end)
				local next = text:byte(MAX_BYTES + 1)
				cut = text:sub(1, MAX_BYTES)
				if next >= 128 and next < 192 then -- (the cut is inside a character: that character goes)
					-- (its lead byte and what of it got in: "[\128-\191]*[\192-\255]$", the other way round, left
					-- the broken character, or took the one before's tail and left a lead byte, 2026-11-08)
					cut = cut:gsub("[\192-\255][\128-\191]*$", "")
				end
			end
			if sent[#sent] ~= cut then
				sent[#sent + 1] = cut
			end
			deliver(cut, channelNow())
		end,
		-- speak to chat's channel (bardroid_pad.lua's note while it listens): its name and colour now; step: the next
		-- (1) or the one before (-1): allies, everyone, spectators (a spectator's: everyone, spectators), kept
		channel = function(step)
			local order = Spring.GetSpectatingState() and { "", "s:" } or { "a:", "", "s:" }
			local mode = channelNow()
			if step then
				local at = 1
				for i, m in ipairs(order) do
					if m == mode then
						at = i
					end
				end
				mode = order[(at - 1 + step) % #order + 1]
				keepMode(mode)
			end
			local names = { [""] = "EVERYONE", ["a:"] = "ALLIES", ["s:"] = "SPECTATORS" }
			local c = MODES[mode].color
			return names[mode], { c:byte(2) / 255, c:byte(3) / 255, c:byte(4) / 255 }
		end,
		lines = function()
			return #entries
		end,
		widget = widget, -- (its KeyPress and TextInput: a widget cannot send the engine's key events)
		typing = function()
			return typing and { text = table.concat(typing.chars), mode = typing.mode, lines = #typed.lines,
				size = typed.size, base = typed.base, x0 = typed.x0, y0 = typed.y0, x1 = typed.x1, y1 = typed.y1 }
		end,
		box = function()
			return boxLeft, boxTop, boxRight, maxLines, lineHeight
		end,
		countdownTop = function()
			return Spring.GetGameFrame() <= 0 and COUNTDOWN_Y * vsy + COUNTDOWN_FONT * (0.75 + vsx * vsy / 6e6) * 1.2
				or nil
		end,
	}
	return true
end

-- the chat box for the layout editor (bardroid_layout.lua): where it is, with its lines' room
local registered = false
local function register()
	local L = WG.BarDroidLayout
	if registered or not (L and L.register) then
		return
	end
	registered = true
	L.register("chat", {
		label = "Chat",
		can = { move = true, size = true, text = true, pad = true },
		rect = function()
			if not lineHeight then
				return nil
			end
			return boxLeft, boxTop - maxLines * lineHeight - math.floor(lineHeight * 0.3), boxRight, boxTop
		end,
		relayout = function()
			if layout() then
				layoutTyping()
			end
		end,
	})
end

-- BAR saves every widget's config before any widget's Shutdown (barwidgets.lua widgetHandler:Shutdown), this widget's
-- before its chat's (layers -96000, -95000): BAR's chat gets the player's own hide and history back for that save, and
-- is taken over again at the next Update if the game goes on (a widget switched on or off). Given back in Shutdown
-- only, BAR had kept its chat hidden with no history as the player's own (dev phone, 2026-11-03: hide = true).
local takeAgain = false
local function giveBack()
	local chat = WG.chat
	if not (hooked and chat) then
		return
	end
	if chat.setHide then
		chat.setHide(wasHidden)
	end
	if wasInputHistory ~= nil and chat.setChatInputHistory then
		chat.setChatInputHistory(wasInputHistory)
	end
end

function widget:GetConfigData()
	if hooked then
		giveBack()
		takeAgain = true
	end
	return { version = CONFIG_VERSION }
end

function widget:SetConfigData(data)
	configVersion = type(data) == "table" and data.version or nil
end

function widget:Shutdown()
	closeTyping()
	WG.bardroidChat = nil
	if registered and WG.BarDroidLayout and WG.BarDroidLayout.unregister then
		WG.BarDroidLayout.unregister("chat")
	end
	local chat = WG.chat
	if hooked and chat then
		giveBack()
		if chat.removeChatProcessor then
			chat.removeChatProcessor("bardroid_chat")
		end
	end
	if WG.messages and WG.messages.addMessage == ownAddMessage and barAddMessage then
		WG.messages.addMessage = barAddMessage
	end
end

function widget:Update()
	if not hooked then
		hooked = hook()
	end
	if hooked and not registered then
		register()
	end
	if quitNote then
		local mx, my = Spring.GetMouseState()
		if mx ~= quitX or my ~= quitY then
			quitNote.ttl = 0 -- (gone at the next draw)
			quitNote = nil
		elseif clock() - quitNote.time > quitNote.ttl then
			quitNote = nil
		else
			local left = math.max(1, math.ceil(quitNote.ttl - (clock() - quitNote.time)))
			if left ~= quitShown and font then -- (the seconds left, once a second)
				quitShown = left
				quitNote.text = quitText(left)
				quitNote.lines = wrap(quitNote.text, boxRight - gap - (boxLeft + gap), fontSize)
				quitNote.right = reach(quitNote)
			end
		end
	end
	if takeAgain then -- (a save while the game goes on: GetConfigData)
		takeAgain = false
		local chat = WG.chat
		if hooked and chat then
			chat.setHide(true)
			if chat.setChatInputHistory then
				chat.setChatInputHistory(false)
			end
		end
	end
	if hooked then
		takeMessages()
		local now = clock()
		if chatMinimap and now - (chatMinimapAt or 0) >= 1 then -- (upright: the box under the minimap, which settles later)
			chatMinimapAt = now
			if smallMinimap() ~= chatMinimap then
				relayoutNext = true
			end
		end
		if relayoutNext then
			relayoutNext = false
			layout()
			layoutTyping()
		end
	end
end

-- The box hangs under BAR's top bar, which lays itself out after this widget (its layer, -95000): after a fold the box
-- went by the top bar's place on the other screen. Laid out again in the next Update, when every widget has its new one.
function widget:ViewResize()
	if hooked then
		layout()
		layoutTyping()
		relayoutNext = true
	end
end

local drawLines -- (below)

-- upright, the minimap opened (not BarDroidMinimap's small one): its rect (GL: x0, y0, x1, y1), or nil
local function openMinimap()
	local M = WG.BarDroidMinimap
	if chatMinimap == nil or not (M and M.small) or M.small() then
		return nil
	end
	local px, py, sx, sy, minimized = Spring.GetMiniMapGeometry()
	if not (px and sx and sx > 0 and sy > 0) or minimized then
		return nil
	end
	if not Spring.IsAboveMiniMap(px + sx / 2, py + sy / 2) then -- (its y counted from the top, as bardroid_minimap.lua)
		py = vsy - py - sy
	end
	return px, py, px + sx, py + sy
end

function widget:DrawScreen()
	if not hooked or not font or Spring.IsGUIHidden() then
		return
	end
	local top = boxTop -- (the chat lines: under the typing box while it is open)
	if typing then
		drawTyping()
		top = typed.y0 - math.floor(gap * 0.5)
	end
	if #entries == 0 then
		return
	end
	local barTyping = WG.chat and WG.chat.isInputActive and WG.chat.isInputActive() -- (BAR's box: a map marker)
	local budget = (typing or barTyping) and math.max(maxLines, LINES_TYPING) or maxLines
	-- before the game starts: the lines end above BAR's start countdown
	local countdownTop = WG.bardroidChat and WG.bardroidChat.countdownTop()
	if countdownTop and top > countdownTop then
		budget = math.min(budget, math.floor((top - countdownTop) / lineHeight))
	end
	local now = clock()
	-- the newest lines that fit, oldest first on the screen
	local shown, used = {}, 0
	for i = #entries, 1, -1 do
		local e = entries[i]
		local old
		if e.ttl then -- (BAR's messages: gone after their time, typing or not)
			old = now - e.time > e.ttl
		else
			old = not (typing or barTyping) and now - e.time > LINE_TTL
			if old then
				break
			end
		end
		if not old then -- (a message gone: the chat lines before it may still stay)
			local rows = math.max(#e.lines, #e.chunks)
			if used + rows > budget then
				break
			end
			used = used + rows
			table.insert(shown, 1, e)
		end
	end
	if #shown == 0 then
		return
	end
	local bottom = top - used * lineHeight - math.floor(lineHeight * 0.3)
	local right = boxRight -- (while typing: as wide as the typing box above)
	if not (typing or barTyping) then
		right = 0
		for _, e in ipairs(shown) do
			right = math.max(right, e.right or boxRight)
		end
		right = math.min(boxRight, math.ceil(right + gap))
	end
	-- Upright, the minimap opened (a tap, or the game's start) lies over the box's corner: the lines drawn around it, not
	-- over it (this widget draws after the minimap; "Battle, Started" sat on the opened map, dev phone 2026-11-11)
	local x0, y0, x1, y1 = openMinimap()
	if x0 and x0 < right and x1 > boxLeft and y0 < top and y1 > bottom then
		for _, s in ipairs({ { 0, 0, x0, vsy }, { x1, 0, vsx, vsy }, { x0, 0, x1, y0 }, { x0, y1, x1, vsy } }) do
			if s[3] > s[1] and s[4] > s[2] then
				gl.Scissor(s[1], s[2], s[3] - s[1], s[4] - s[2])
				drawLines(shown, top, bottom, right)
			end
		end
		gl.Scissor(false)
		return
	end
	drawLines(shown, top, bottom, right)
end

-- (the lines' box, names and text)
drawLines = function(shown, top, bottom, right)
	box(boxLeft, bottom, right, top, LINES_BOX)
	gl.Color(1, 1, 1, 1)
	local y = top
	local baseline = math.floor(lineHeight * 0.78)
	nameFont:Begin()
	for _, e in ipairs(shown) do
		for r, piece in ipairs(e.chunks) do
			nameFont:Print(e.nameColor .. piece, boxLeft + gap, y - (r - 1) * lineHeight - baseline, fontSize, "o")
		end
		y = y - math.max(#e.lines, #e.chunks) * lineHeight
	end
	nameFont:End()
	y = top
	font:Begin()
	for _, e in ipairs(shown) do
		local x = #e.chunks > 0 and textLeft or boxLeft + gap
		for r, line in ipairs(e.lines) do
			font:Print(line, x, y - (r - 1) * lineHeight - baseline, fontSize, "o")
		end
		y = y - math.max(#e.lines, #e.chunks) * lineHeight
	end
	font:End()
end
