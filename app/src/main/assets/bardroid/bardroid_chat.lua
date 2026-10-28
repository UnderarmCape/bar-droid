-- BAR Droid chat: BAR's chat lines laid out for a phone (Kailil, 2026-10-26: the text "only appears in the center of the
-- box ... ugly and a waste of space"; "slam the names to the left most sides and allow wordwrap on names if they go
-- past 10 characters"). BAR's chat gives each line a game-time column and a name column as wide as the longest player
-- name in the game, so on the Fold's inner screen the message wrapped in ~120 pixels. Here the names sit at the box's
-- left edge, broken every 10 characters, and the message fills the rest of the box.
-- BAR's chat widget still does everything else (typing box, sounds, ignore list, history when scrolled): its own lines
-- are hidden (WG.chat.setHide) and this widget gets every line it parsed through WG.chat.addChatProcessor. A few of
-- the engine's system lines BAR shows as console lines (paused, left the game, lagging) come from AddConsoleLine.
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid chat",
		desc = "Chat lines with the names at the left edge and the text filling the box (the phone's chat)",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local FONT_SIZE = 0.75 -- of BAR's chat font size (Kailil: "make the text chat wayy smaller")
local NAME_CHARS = 10 -- a name is broken after this many characters
local LINES = 8 -- screen lines shown (BAR shows 5 lines of text; names broken in two take two)
local LINES_TYPING = 14 -- while the typing box is open (BAR's own history is switched off for it)
local LINE_TTL = 40 -- seconds a line stays (BAR's)
local BOX_RIGHT = 0.74 -- of the screen width (BAR's chat box)
local BACKGROUND = 0.3

local LineTypes = { Player = 1, Spectator = 2, Mapmark = 3, Battleroom = 4, System = 5 } -- BAR's gui_chat.lua
local WHITE = "\255\255\255\255"
local SYSTEM_COLOR = "\255\200\200\200"

-- seconds of real time (os.clock is the process's CPU time on Linux, the phone's: all the engine's threads together,
-- faster than real time in a busy game)
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local timer0 = spGetTimer()
local function clock()
	return spDiffTimers(spGetTimer(), timer0)
end
local entries = {} -- { time, chunks = name pieces, nameColor, text, lines = wrapped text }
local hooked, wasInputHistory = false, nil
local vsx, vsy = Spring.GetViewGeometry()
local font, nameFont, fontSize, lineHeight
local boxLeft, boxRight, boxTop, nameWidth, textLeft, gap

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

local function chunks(name)
	local out = {}
	for i = 1, #name, NAME_CHARS do
		out[#out + 1] = name:sub(i, i + NAME_CHARS - 1)
	end
	return out
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
	fontSize = barSize * FONT_SIZE
	lineHeight = math.floor(fontSize * 1.3)
	gap = math.floor(fontSize * 0.6)
	local p = WG.topbar and WG.topbar.GetPosition and WG.topbar.GetPosition()
	boxLeft = math.floor(p and p[1] or vsx * 0.3)
	boxTop = math.floor(p and p[2] - fontSize * 0.5 or vsy * 0.94)
	boxRight = math.floor(vsx * BOX_RIGHT)
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
	end
	return true
end

local function add(name, nameColor, text)
	local e = { time = clock(), chunks = name ~= "" and chunks(name) or {}, nameColor = nameColor, text = text }
	if font then
		e.lines = wrap(text, boxRight - gap - (name ~= "" and textLeft or boxLeft + gap), fontSize)
	end
	entries[#entries + 1] = e
	if #entries > 100 then
		table.remove(entries, 1)
	end
end

-- BAR's chat calls this for every chat line it parsed: text carries its colour (all, allies, spectators)
local function processor(_, lineType, name, nameText, text, _, ignore)
	if not ignore and text and text ~= "" then
		local nameColor = (type(nameText) == "string" and nameText:match("^\255...")) or WHITE
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
function widget:AddConsoleLine(line)
	if not hooked then
		return
	end
	for _, s in ipairs(SYSTEM_LINES) do
		if line:find(s, 1, true) then
			add("", WHITE, SYSTEM_COLOR .. line:gsub("%s+", " "))
			return
		end
	end
end

local function hook()
	local chat = WG.chat
	if not (chat and chat.setHide and chat.addChatProcessor) or not layout() then
		return false
	end
	chat.setHide(true)
	chat.addChatProcessor("bardroid_chat", processor)
	if chat.getChatInputHistory and chat.setChatInputHistory then
		wasInputHistory = chat.getChatInputHistory()
		chat.setChatInputHistory(false)
	end
	Spring.Echo("[bardroid-chat] BAR's chat lines drawn by BAR Droid chat")
	WG.bardroidChat = { -- (tools/touch-widget-test.ps1)
		lines = function()
			return #entries
		end,
	}
	return true
end

function widget:Shutdown()
	WG.bardroidChat = nil
	local chat = WG.chat
	if hooked and chat then
		if chat.setHide then
			chat.setHide(false)
		end
		if chat.removeChatProcessor then
			chat.removeChatProcessor("bardroid_chat")
		end
		if wasInputHistory ~= nil and chat.setChatInputHistory then
			chat.setChatInputHistory(wasInputHistory)
		end
	end
end

function widget:Update()
	if not hooked then
		hooked = hook()
	end
end

function widget:ViewResize()
	if hooked then
		layout()
	end
end

function widget:DrawScreen()
	if not hooked or not font or #entries == 0 or Spring.IsGUIHidden() then
		return
	end
	local typing = WG.chat and WG.chat.isInputActive and WG.chat.isInputActive()
	local budget = typing and LINES_TYPING or LINES
	local now = clock()
	-- the newest lines that fit, oldest first on the screen
	local shown, used = {}, 0
	for i = #entries, 1, -1 do
		local e = entries[i]
		if not typing and now - e.time > LINE_TTL then
			break
		end
		local rows = math.max(#e.lines, #e.chunks)
		if used + rows > budget then
			break
		end
		used = used + rows
		table.insert(shown, 1, e)
	end
	if #shown == 0 then
		return
	end
	local bottom = boxTop - used * lineHeight - math.floor(lineHeight * 0.3)
	gl.Color(0, 0, 0, BACKGROUND)
	gl.Rect(boxLeft, bottom, boxRight, boxTop)
	gl.Color(1, 1, 1, 1)
	local y = boxTop
	local baseline = math.floor(lineHeight * 0.78)
	nameFont:Begin()
	for _, e in ipairs(shown) do
		for r, piece in ipairs(e.chunks) do
			nameFont:Print(e.nameColor .. piece, boxLeft + gap, y - (r - 1) * lineHeight - baseline, fontSize, "o")
		end
		y = y - math.max(#e.lines, #e.chunks) * lineHeight
	end
	nameFont:End()
	y = boxTop
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
