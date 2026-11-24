-- BAR Droid gamepad: the game side of the app's gamepad in BAR's own game (online, spectating). The app makes the pad a
-- mouse and keyboard rebuilt on Kailil's BAR Controller Support v0.8.5 ("Build-First Commander"; PadGame.java has the
-- whole layout) and sends what a mouse and keys cannot do as actions through bardroid_touch.lua ("act <name>"); this
-- widget does them, with what BAR lets a user widget do (Kailil, 2026-10-29: "match 1to1 using any means necessary ...
-- RB and Back + RB to teleport mouse to build menu and orders menu to replace the tactical menu radial"):
--   the order menu on the pad (Back + RB): the pointer onto its first order, the D-pad steps, the order under it lit
--     with BAR's own highlight, A gives it (an order that needs a target sends the pointer back to the middle to aim),
--     B leaves; the build menu's own (RB) is bardroid_buildmenu.lua's
--   control groups (Start + D-pad): recall, assign, BAR's autogroup (the app presses Alt+N), clear; BAR's group
--     actions, the group's number shown
--   idle units (D-pad; LB + D-pad), the commander (D-pad down), a camera bookmark (D-pad up; LT + up stores it)
--   cancel (B), LB + A/X/Y/B orders at the middle of the screen, removing queued orders (L3/R3), v0.8.5's D-gun mode
--     (LB + RB + R3, or Back + R3), the share list (LB + D-pad up tapped, then held: the selected units, metal or energy
--     to a teammate; LB / RB what, D-pad left / right how much)
--   a reticle in the middle while the pad is the input, and short notes (v0.8.5's hotkey feedback)
-- Every control here works in every game (Kailil, 2026-11-01, after 40 minutes online: "I should have no cases of that
-- happening"). A host can forbid user widgets Spring.GiveOrder* (the modoption allowunitcontrolwidgets; first person
-- alone needs it): the rest goes the way a player's own hotkey or click goes, BAR's actions and its order menu's picks
-- (Spring.SendCommands, Spring.SetActiveCommand). An order at a point goes straight to the units where allowed, else it
-- is picked and the app clicks in the middle ("click <n>"). The app learns which menu has the pad, whether the game has
-- started and what kind of order is picked from LuaUI/Config/bardroid_pad.txt ("focus build|orders|none", "pregame 0|1",
-- "armed build|area|unitarea|other|none": a tap of A starts an area order's circle, PadGame).
-- A menu on the pad keeps the pointer on it (Kailil: "constrain the mouse within the menu bounds ... let the mouse leave
-- it if i press B only or i constantly move the left stick out of the box for ... 1 second"); the app brings the
-- pointer back to the middle afterwards, gliding.

function widget:GetInfo()
	return {
		name = "BAR Droid gamepad",
		desc = "The BAR Droid app's gamepad in BAR's game: menus, groups, idle units, orders",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -95000,
		enabled = true,
	}
end

local PAD_FILE = "LuaUI/Config/bardroid_pad.txt"

-- written whole, then renamed: the app reads it every 100 ms and must never find it empty (io.open "w" empties it
-- first: "no menu" pulled the pointer out of the menu, "not pregame" to the middle)
local function writeWhole(path, text)
	local f = io.open(path .. ".tmp", "w")
	if not f then
		return false
	end
	f:write(text)
	f:close()
	local ok, renamed = pcall(os.rename, path .. ".tmp", path)
	if not (ok and renamed) then -- (Windows, for the laptop tests: rename does not replace a file)
		pcall(os.remove, path)
		pcall(os.rename, path .. ".tmp", path)
	end
	return true
end

local TOAST_SECONDS = 1.3
local VOICE_PING_NOTE = "SPEAK THE PING" -- (voice_on_ping: what is said labels a ping, voicePing)
local VOICE_SECONDS = 15 -- the listening note's longest stay (the app ends it: voice_off)
-- (voice_nomic; the lobby's the same. Not "SPEAK TO CHAT: ...": a ping's spoken label asks for the microphone too, PING
-- held, and the note spoke of chat; dev phone 2026-11-17)
local VOICE_NOMIC_NOTE = "TO SPEAK, ALLOW THE MICROPHONE IN ANDROID'S SETTINGS"
-- (voice_nonet: the phone's recognizer needed the network, none or its server not answering; the lobby's the same)
local VOICE_NONET_NOTE = "NOTHING SENT: SPEECH NEEDS A CONNECTION"
local voiceToast = false -- the note showing is the listening one
local VOICE_PING_SECONDS = 30 -- the ping's place kept this long for the words
local voicePingAt = nil -- where the spoken ping goes: { x, y, z, at }
local LEAVE_SECONDS = 0.25 -- the pointer pushed off a menu this long lets go of it (Kailil: "make it a quarter long")
local HIGHLIGHT = { 1, 0.8, 0.25 }

-- BAR's order menu (luaui/Widgets/gui_ordermenu.lua): the orders it hides, and how it lays out its grid
local HIDDEN = {
	[CMD.LOAD_ONTO] = true, [CMD.SELFD] = true, [CMD.GATHERWAIT] = true, [CMD.SQUADWAIT] = true,
	[CMD.DEATHWAIT] = true, [CMD.TIMEWAIT] = true, [CMD.AUTOREPAIRLEVEL] = true, [39812] = true, [34922] = true,
}
local HIDDEN_TYPE = { [CMDTYPE.CUSTOM] = true, [CMDTYPE.PREV] = true, [CMDTYPE.NEXT] = true }
local CANCEL_TARGET = 34924

local orders = nil -- the order menu on the pad: { index, cmdID, warped = {x, y, timer}, layout }
local toast, toastAt = nil, nil
local written, writtenAt = nil, nil
local bookmark = nil
-- The last pings from someone else, newest first ({ x, y, z } each): RB + D-pad up goes to the newest, and pressed
-- again within PING_CYCLE_SECONDS to the one before, and so on
local PINGS_KEPT = 5
local PING_CYCLE_SECONDS = 2
local pings = {}
local pingStep, pingStepAt = 0, nil
local pingKept = PINGS_KEPT -- (how many the cycle under way goes through: the pad's 5, the dock's 4)
local function addPing(x, y, z, e) -- (e: more about it, an attack on my units: ATTACK)
	e = e or {}
	e[1], e[2], e[3] = x, y, z
	table.insert(pings, 1, e)
	pings[PINGS_KEPT + 1] = nil
	if pingStepAt and pingStep > 0 then
		-- (still the same ping for a press that cycles on; the dock shows its last 4: "PING 5 OF 4" past them, the next
		-- tap back to the newest; review 2026-11-16)
		pingStep = math.min(pingStep + 1, #pings, pingKept)
	end
end
-- The camera to the last ping from someone else, then the ones before it (the pad's RB + D-pad up; the portrait dock's
-- PINGS, kept = 4: Kailil, 2026-11-11, "a button to go to last 4 pings like we have on controller")
local pingLook -- (defined after now() and note())
local padClicks = 0 -- clicks asked of the app ("click <n>" in bardroid_pad.txt)
local padClickAt = nil -- the last one's point if not the middle: { x, y }, fractions of the screen from its top left
local idleType = nil -- the type of the last idle unit picked (LB + D-pad down)
local lastIdleMobile = 0
local mouseMode = false -- Back + Start, as the app's switch (PadGame)
-- v0.8.5's area select (A held with nothing picked: PadGame): a circle in the middle of the screen selects the player's
-- units it passes over while the camera pans; units first (buildings only when there are no units in it, or with RT:
-- added to the selection, buildings too); the D-pad sizes it, held quickly, the circle easing to its new size in about
-- 0.1 s (Kailil, 2026-10-30); B undoes it. v0.8.5's radius: 320 in 80s up to 1200; down to 20, in 20s under 160.
-- X held as well: v0.8.5's filter radial (Kailil, 2026-10-29), the left stick picks All Mobile (up), Combat (down),
-- Builders (left) or Air (right), kept for the next area select. Builders and combat units are never selected together
-- (Kailil: "prefer combat units (BAR's vanilla behavior), so con bots are not sent into battle").
local FILTER_SIDES = { up = "All Mobile", down = "Combat", left = "Builders", right = "Air" }
local area = { on = false, radius = 320, target = 320, units = {}, count = 0, keep = {}, shift = false, x = nil, y = nil,
	z = nil, filter = "All Mobile", radial = false, highlight = nil }
local AREA_MIN, AREA_MAX, AREA_EASE = 20, 1200, 0.035 -- (the ease: 95% of the way in 0.1 s)
-- the group list (control groups, below): the slot in use, Start held, shown until
local GROUP_LIST_SECONDS = 1.5
local groupList = { slot = 1, held = false, untilAt = nil }
local warp, fakeWarp = Spring.WarpMouse, false -- (tools/touch-widget-test.ps1 records the moves instead)
-- (tools/touch-widget-test.ps1: a made-up pointer, {x, y}, which the recorded moves land on, so the order menu's
-- following, holding and letting go run without moving the real one)
local fakePointer = nil
local function pointerAt()
	if fakePointer then
		return fakePointer[1], fakePointer[2]
	end
	return Spring.GetMouseState()
end
local function warpTo(x, y)
	if fakePointer then
		fakePointer = { x, y }
	end
	warp(x, y)
end

local function now()
	return Spring.GetTimer()
end

-- The pad's pointer is free (the left stick moves it) before the start, or after Back + Start; else in the middle
local function freePointer()
	return mouseMode ~= (Spring.GetGameFrame() == 0 and not Spring.GetSpectatingState())
end

-- The app's controller interface, one look with the touch dock (Kailil, 2026-10-30: "make them look more polished. not
-- extravagant"; 2026-11-23: "bring the gamepad support side of the phone mod in sync visually and kinda functionally with
-- our super optimized touch ui and ux. make the gamepad ui cohesive with that"): bardroid_portrait.lua's look, its values
-- copied here (that file is the dock's): BAR's panels (WG.FlowUI's Element) and buttons (its Button: plain, BAR's gold
-- for the one picked, the D-gun's red), unit pictures as the dock's tiles, its round pill (its own round corners:
-- FlowUI's RectRound cuts them straight), its white, grey and gold words, BAR's font and its bold, sizes from BAR's
-- interface scale for words (the phone sets it per Fold screen) and from the screen's short side for tiles and gaps, as
-- the dock's; gold where the pad is (the focus on a menu), v0.8.5's blue for placing and filters. The app's build menu,
-- first person and the speed tuner draw with it too (WG.BarDroidStyle).
local style = {
	GOLD = { 1, 0.78, 0.25 },
	BLUE = { 0.2, 0.8, 1 },
	TEXT = { 0.94, 0.94, 0.94 }, -- (the dock's words, \240)
	WHITE = { 1, 1, 1 }, -- (on a coloured button: FIRE's)
	LACK = { 0.78, 0.63, 0.59 }, -- (FIRE without a shot's energy: \200\160\150)
	SOFT = { 0.78, 0.78, 0.78 }, -- (a count, a second line: \200)
	DIM = { 0.55, 0.55, 0.55 }, -- (nothing to do there: \140)
	-- the pad's face buttons in their Xbox colours (a note naming one at its end, "REPAIR: A", shows it as a key)
	KEYS = { A = { 0.33, 0.66, 0.24 }, B = { 0.82, 0.24, 0.2 }, X = { 0.2, 0.44, 0.88 }, Y = { 0.9, 0.7, 0.1 } },
	-- the dock's buttons (FlowUI Button's two colours, its foot's and its top's): BAR's gold for the one picked, the
	-- D-gun's red, an open place, + NEW
	LIT = { { 0.38, 0.3, 0.04, 0.9 }, { 0.66, 0.53, 0.12, 0.9 } },
	RED = { { 0.5, 0.06, 0.05, 1 }, { 0.86, 0.14, 0.11, 1 } },
	AUTO = { { 0.55, 0.2, 0.02, 1 }, { 0.95, 0.48, 0.07, 1 } },
	BLANK = { { 0, 0, 0, 0.25 }, { 0.12, 0.12, 0.12, 0.3 } },
	NEW = { { 0.2, 0.2, 0.2, 0.8 }, { 0.32, 0.32, 0.32, 0.8 } },
	PLAIN = { { 0, 0, 0, 1 }, { 1, 1, 1, 0.1 } }, -- (FlowUI Button's own)
	GLOW = { { 1, 0.85, 0.2, 0.08 }, { 1, 0.85, 0.2, 0.28 } }, -- (BAR's gold light over a picked cell: style.lit)
	-- the dock's pill (SP.NOOK_C): its top lit, dark from its foot up, a gold tint on the one open
	PILL = { edge = { 1, 1, 1, 0.16 }, c0 = { 0.075, 0.08, 0.09, 1 }, c1 = { 0.165, 0.17, 0.185, 1 },
		gold0 = { 1, 0.78, 0.25, 0.06 }, gold1 = { 1, 0.78, 0.25, 0.22 }, shade = { 0, 0, 0, 0.4 } },
	fade1 = { 0, 0, 0, 0 }, fade2 = { 0, 0, 0, 0 }, -- (a button's colours faded: reused, no table a frame)
	drawn = {}, -- (tools: each piece's rect as drawn last, and the draw frame: drawnRect)
}

-- a size from BAR's interface scale: this fraction of the screen's height at scale 1; least: the smallest (10: text)
function style.size(fraction, least)
	local _, vsy = Spring.GetViewGeometry()
	local scale = (WG.FlowUI and WG.FlowUI.scale) or Spring.GetConfigFloat("ui_scale", 1) or 1
	return math.max(least or 10, math.floor(vsy * fraction * scale + 0.5))
end

-- the dock's sizes by the screen (bardroid_portrait.lua layout: its pad and gap from the short side, 0.008 of it on a
-- near-square screen, else 0.012; a build tile 0.075 of it, the groups row's tiles as tall)
function style.dock()
	local vsx, vsy = Spring.GetViewGeometry()
	local d = style.dockSizes
	if not d or d.vsx ~= vsx or d.vsy ~= vsy then
		local short = math.min(vsx, vsy)
		local pad = math.max(4, math.floor(short * (math.max(vsx, vsy) < short * 1.5 and 0.008 or 0.012)))
		d = { vsx = vsx, vsy = vsy, pad = pad, gap = math.max(3, math.floor(pad * 0.6)), tile = math.floor(short * 0.075) }
		style.dockSizes = d
	end
	return d
end

-- BAR's font and its bold (the dock's numbers, QUEUE, the keys' letters)
function style.font()
	return WG.fonts and WG.fonts.getFont()
end
function style.bold()
	return WG.fonts and (WG.fonts.getFont(2) or WG.fonts.getFont())
end

-- (tools: a piece's rect as drawn, for tools/pad-test.ps1 -Shots; one table each, reused)
function style.mark(name, x0, y0, x1, y1)
	local r = style.drawn[name]
	if not r then
		r = {}
		style.drawn[name] = r
	end
	r[1], r[2], r[3], r[4], r.at = x0, y0, x1, y1, Spring.GetDrawFrame()
end

-- BAR's panel, as the dock's (FlowUI's Element, its own colours and padding), its alpha times alpha (least: at least
-- this opaque; 0.9 or more, whole: the dock's opaque panel)
function style.panel(x0, y0, x1, y1, alpha, least)
	local f = WG.FlowUI
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	if f and f.Draw and f.Draw.Element then
		local o = math.max(least or 0, math.min(1, (f.opacity or 0.7) + 0.1) * (alpha or 1))
		f.Draw.Element(x0, y0, x1, y1, 1, 1, 1, 1, 1, 1, 1, 1, o, nil, nil, nil, (least or 0) >= 0.9 and (alpha or 1) >= 1)
	else
		gl.Color(0.04, 0.04, 0.04, math.max(least or 0, 0.8 * (alpha or 1)))
		gl.Rect(x0, y0, x1, y1)
	end
	gl.Color(1, 1, 1, 1) -- (a unit picture right after an Element came out dark: the state it leaves; the dock's panel)
	gl.Texture(false)
end

-- a button as the dock's (FlowUI's Button, its padding a third of the dock's pad): c its two colours (style.LIT, RED,
-- BLANK, NEW; nil: BAR's plain one), faded by alpha
function style.button(x0, y0, x1, y1, c, alpha)
	local f = WG.FlowUI
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	local c1, c2 = c and c[1], c and c[2]
	local a = alpha or 1
	if a < 1 then
		local b1, b2 = c1 or style.PLAIN[1], c2 or style.PLAIN[2]
		c1, c2 = style.fade1, style.fade2
		c1[1], c1[2], c1[3], c1[4] = b1[1], b1[2], b1[3], b1[4] * a
		c2[1], c2[2], c2[3], c2[4] = b2[1], b2[2], b2[3], b2[4] * a
	end
	if f and f.Draw and f.Draw.Button then
		f.Draw.Button(x0, y0, x1, y1, 1, 1, 1, 1, 1, 1, 1, 1, nil, c1, c2, math.max(1, math.floor(style.dock().pad * 0.35)))
	else
		local k = c1 or style.PLAIN[1]
		gl.Color(math.max(0.15, k[1]), math.max(0.15, k[2]), math.max(0.15, k[3]), 0.9 * a)
		gl.Rect(x0, y0, x1, y1)
	end
	-- (a unit picture drawn right after a FlowUI button came out dark: the state it leaves; the dock's resetGL)
	gl.Color(1, 1, 1, 1)
	gl.Texture(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
end

-- a button over the game, on the dock's own dark ground (its opaque panel's colours under it: FlowUI's button alone is
-- clear at its top, the map showed through the filter radial's, dev phone shots 2026-11-24)
function style.float(x0, y0, x1, y1, c, alpha)
	local f = WG.FlowUI and WG.FlowUI.Draw
	local a = alpha or 1
	if f and f.RectRound then
		local g1, g2 = style.fade1, style.fade2
		g1[1], g1[2], g1[3], g1[4] = 0.04, 0.04, 0.04, 0.92 * a
		g2[1], g2[2], g2[3], g2[4] = 0.12, 0.12, 0.12, 0.92 * a
		f.RectRound(math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1),
			math.max(2, math.floor(math.min(x1 - x0, y1 - y0) * 0.12)), 1, 1, 1, 1, g1, g2)
	end
	style.button(x0, y0, x1, y1, c, alpha)
end

-- a unit type's picture as the dock's tiles (its unitTile: FlowUI's Unit; in use, the picture closer and BAR's gold
-- light over it, as BAR's build menu shows its picked cell)
function style.unit(defID, x0, y0, x1, y1, inUse, alpha)
	local f = WG.FlowUI and WG.FlowUI.Draw
	local a = alpha or 1
	local cs = math.max(2, math.floor((x1 - x0) * 0.06))
	if f and f.Unit then
		local zoom = inUse and 0.135 or 0.04
		gl.Color(1, 1, 1, a)
		f.Unit(x0, y0, x1, y1, cs, 1, 1, 1, 1, zoom, nil, nil, "#" .. defID)
		if inUse then
			gl.Blending(GL.SRC_ALPHA, GL.ONE)
			gl.Color(1, 0.85, 0.2, 0.25 * a)
			gl.Texture("#" .. defID)
			f.Unit(x0, y0, x1, y1, cs, 1, 1, 1, 1, zoom)
			gl.Texture(false)
			gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
		end
	else
		gl.Color(1, 1, 1, a)
		gl.Texture("#" .. defID)
		gl.TexRect(x0, y0, x1, y1)
		gl.Texture(false)
	end
	gl.Color(1, 1, 1, 1)
end

-- words in the middle of a rect as the dock's buttons have them (textIn: no wider than 76 % of it, the outline is not in
-- the font's width), in BAR's font or the bold one
function style.words(text, x0, y0, x1, y1, size, color, alpha, bold)
	local font = bold and style.bold() or style.font()
	if not font then
		return
	end
	local room = (x1 - x0) * 0.76
	local w = font:GetTextWidth(text) * size
	if w > room then
		size = size * room / w
	end
	local a = alpha or 1
	font:Begin()
	font:SetOutlineColor(0, 0, 0, 0.6 * a)
	font:SetTextColor(color[1], color[2], color[3], a)
	font:Print(text, (x0 + x1) / 2, (y0 + y1) / 2 - size * 0.32, size, "co")
	font:End()
end

-- a rounded rect as a fan from its middle, from c0 at its foot to c1 at its top, its corners' radius r, drawn dy lower,
-- faded by a: the dock's own round corners (SP.roundPath, SP.fan), its vertices made here (gl.BeginEnd's function: no
-- table a frame)
function style.roundFan(x0, y0, x1, y1, r, c0, c1, a, dy)
	local span = math.max(1, y1 - y0)
	local t = 0.5
	gl.Color(c0[1] + (c1[1] - c0[1]) * t, c0[2] + (c1[2] - c0[2]) * t, c0[3] + (c1[3] - c0[3]) * t,
		(c0[4] + (c1[4] - c0[4]) * t) * a)
	gl.Vertex((x0 + x1) / 2, (y0 + y1) / 2 - dy)
	local q = math.pi / 2
	for k = 0, 4 do -- (the four corners, top right first, round to its first point again)
		local c = k % 4
		local cx = (c == 0 or c == 3) and x1 - r or x0 + r
		local cy = c <= 1 and y1 - r or y0 + r
		for i = 0, k < 4 and 8 or 0 do
			local ang = (c + i / 8) * q
			local x, y = cx + r * math.cos(ang), cy + r * math.sin(ang)
			t = math.max(0, math.min(1, (y - y0) / span))
			gl.Color(c0[1] + (c1[1] - c0[1]) * t, c0[2] + (c1[2] - c0[2]) * t, c0[3] + (c1[3] - c0[3]) * t,
				(c0[4] + (c1[4] - c0[4]) * t) * a)
			gl.Vertex(x, y - dy)
		end
	end
end

-- the dock's pill (SP.drawPill): round corners, its top lit, dark from its foot up, a soft shade under it over the game;
-- tint: BAR's gold over it (the one open)
function style.pill(x0, y0, x1, y1, alpha, tint)
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	local a = alpha or 1
	local r = math.floor(math.min(y1 - y0, x1 - x0) * 0.3)
	local P = style.PILL
	gl.Texture(false)
	local fan, TF = style.roundFan, GL.TRIANGLE_FAN
	gl.BeginEnd(TF, fan, x0 - 1, y0 - 1, x1 + 1, y1, r + 1, P.shade, P.shade, a, 2)
	gl.BeginEnd(TF, fan, x0, y0, x1, y1, r, P.edge, P.edge, a, -1)
	gl.BeginEnd(TF, fan, x0, y0, x1, y1, r, P.c0, P.c1, a, 0)
	if tint then
		gl.BeginEnd(TF, fan, x0, y0, x1, y1, r, P.gold0, P.gold1, a, 0)
	end
	gl.Color(1, 1, 1, 1)
end

-- BAR's gold light over a rect, from its foot up (the dock's lit tile: the gold BAR's build menu lays over its picked
-- cell), its corners cut as BAR's cells' are
function style.lit(x0, y0, x1, y1)
	local f = WG.FlowUI and WG.FlowUI.Draw
	gl.Texture(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE)
	if f and f.RectRound then
		f.RectRound(x0, y0, x1, y1, math.max(2, math.floor(math.min(x1 - x0, y1 - y0) * 0.1)), 1, 1, 1, 1, style.GLOW[1],
			style.GLOW[2])
	else
		gl.Color(1, 0.85, 0.2, 0.18)
		gl.Rect(x0, y0, x1, y1)
	end
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	gl.Color(1, 1, 1, 1)
end

-- a key's name on a small dark chip ("LB", "RT": the pad's other buttons, beside the face buttons' coloured keys)
function style.chip(x0, y0, h, label, alpha)
	local bold = style.bold()
	if not bold then
		return 0
	end
	local a = alpha or 1
	local size = h * 0.5
	local w = math.ceil(bold:GetTextWidth(label) * size + h * 0.7)
	local f = WG.FlowUI and WG.FlowUI.Draw
	local cs = math.max(2, math.floor(h * 0.22))
	local c = style.fade1
	c[1], c[2], c[3], c[4] = 0.2, 0.2, 0.22, 0.95 * a
	if f and f.RectRound then
		f.RectRound(x0, y0, x0 + w, y0 + h, cs, 1, 1, 1, 1, c, c)
	else
		gl.Color(c[1], c[2], c[3], c[4])
		gl.Rect(x0, y0, x0 + w, y0 + h)
	end
	bold:Begin()
	bold:SetOutlineColor(0, 0, 0, 0.5 * a)
	bold:SetTextColor(1, 1, 1, 0.95 * a)
	bold:Print(label, x0 + w / 2, y0 + h / 2 - size * 0.34, size, "co")
	bold:End()
	gl.Color(1, 1, 1, 1)
	return w
end

-- (a rounded rect, filled; BAR's own when it is there)
function style.fill(x0, y0, x1, y1, color, alpha, corner)
	local f = WG.FlowUI
	local c = { color[1], color[2], color[3], (color[4] or 1) * (alpha or 1) }
	local cs = corner or math.max(2, math.floor(math.min(x1 - x0, y1 - y0) * 0.14))
	if f and f.Draw and f.Draw.RectRound then
		f.Draw.RectRound(x0, y0, x1, y1, cs, 1, 1, 1, 1, c, c)
	else
		gl.Color(c[1], c[2], c[3], c[4])
		gl.Rect(x0, y0, x1, y1)
	end
end

-- an accent line round a rect (the pad's focus, a lit choice), its corners cut as BAR's panels' are; width: about BAR's
-- element padding
local function ring(x0, y0, x1, y1, cs, w)
	local ics = math.max(0, cs - w * 0.586) -- (the cut as thick as the sides)
	local points = {
		x1, y1 - cs, x1 - w, y1 - w - ics, x1 - cs, y1, x1 - w - ics, y1 - w,
		x0 + cs, y1, x0 + w + ics, y1 - w, x0, y1 - cs, x0 + w, y1 - w - ics,
		x0, y0 + cs, x0 + w, y0 + w + ics, x0 + cs, y0, x0 + w + ics, y0 + w,
		x1 - cs, y0, x1 - w - ics, y0 + w, x1, y0 + cs, x1 - w, y0 + w + ics,
		x1, y1 - cs, x1 - w, y1 - w - ics,
	}
	gl.BeginEnd(GL.TRIANGLE_STRIP, function()
		for i = 1, #points, 2 do
			gl.Vertex(points[i], points[i + 1])
		end
	end)
end
function style.outline(x0, y0, x1, y1, color, alpha, width)
	local w = width or style.size(0.0026, 2)
	local cs = math.max(w + 1, math.floor(math.min(x1 - x0, y1 - y0) * 0.1))
	gl.Color(color[1], color[2], color[3], alpha or 1)
	ring(math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1), cs, w)
	gl.Color(1, 1, 1, 1)
end

-- (a filled circle)
function style.disc(x, y, r, color, alpha)
	gl.Color(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
	gl.BeginEnd(GL.TRIANGLE_FAN, function()
		gl.Vertex(x, y)
		for i = 0, 24 do
			local a = i / 24 * 2 * math.pi
			gl.Vertex(x + math.cos(a) * r, y + math.sin(a) * r)
		end
	end)
	gl.Color(1, 1, 1, 1)
end

-- a pad button as a small round key in its colour, its letter on it; size: its side
function style.key(x0, y0, size, letter, alpha)
	local c = style.KEYS[letter] or { 0.4, 0.4, 0.4 }
	local r = size / 2
	style.disc(x0 + r, y0 + r, r, { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5 }, alpha)
	style.disc(x0 + r, y0 + r, r - math.max(1, size * 0.08), c, alpha)
	local font = WG.fonts and WG.fonts.getFont()
	if font then
		font:Begin()
		font:SetTextColor(1, 1, 1, alpha or 1)
		font:SetOutlineColor(0, 0, 0, 0.5 * (alpha or 1))
		font:Print(letter, x0 + size / 2, y0 + size * 0.5 - size * 0.62 * 0.36, size * 0.62, "co")
		font:End()
	end
end

-- a short message in a panel, its middle at x and its bottom at y; key: a pad button shown after the words
-- listening: seconds since it began, for a pulsing red dot before the words, the sign that the phone listens now
-- ("< SPEAK TO ALLIES >" alone read as any note, dev phone 2026-11-08)
function style.toast(text, x, y, color, alpha, key, listening)
	local font = WG.fonts and WG.fonts.getFont()
	if not font then
		return
	end
	local vsx, vsy = Spring.GetViewGeometry()
	local size = style.size(0.02)
	-- (a channel's arrows, "< SPEAK TO ALLIES >": solid triangles in the words' colour, a size each with its gap, as the
	-- dock's spectator arrows; the font's "<" and ">" were thin marks, dev phone screenshot 2026-11-18)
	local arrows = text:sub(1, 2) == "< " and text:sub(-2) == " >"
	if arrows then
		text = text:sub(3, -3)
	end
	-- (no wider than the screen: upright a long note, "BATTLE LINE: TAP TO SEND, OR DRAW THE FRONT LINE", ran off both
	-- edges, dev phone screenshot 2026-11-12; the words a size smaller until it fits)
	local textW = font:GetTextWidth(text) + (arrows and 2 or 0)
	local unit = 1.5 + textW + (key and 1.8 or 0) + (listening and 1 or 0) -- (the box's width in sizes, as below)
	size = math.min(size, (vsx - 16) / unit)
	local pad = math.floor(size * 0.75)
	local chip = key and math.floor(size * 1.3) or 0
	local gap = key and math.floor(size * 0.5) or 0
	local dot = listening and math.floor(size * 0.55) or 0
	local dotGap = listening and math.floor(size * 0.45) or 0
	local tw = math.ceil(textW * size)
	local w, h = dot + dotGap + tw + gap + chip + pad * 2, math.floor(size * 2)
	local x0 = math.floor(x - w / 2)
	y = math.min(math.floor(y), vsy - h - 2)
	-- (the box fades ahead of its words: at the same alpha its light rim outlasted the words, an empty box over the game
	-- for a moment as a note went, dev phone screenshot 2026-11-12)
	-- (the dock's pill, round, 2026-11-23: one look with the touch dock)
	style.pill(x0, y, x0 + w, y + h, alpha * alpha)
	style.mark("note", x0, y, x0 + w, y + h)
	if listening then
		local pulse = 0.55 + 0.45 * math.cos(listening * math.pi * 2.4)
		local mx, my, r = x0 + pad + dot / 2, y + h / 2, dot / 2 -- (a round dot: style.fill's corners made a diamond)
		gl.Color(1, 0.3, 0.28, alpha * pulse)
		gl.BeginEnd(GL.TRIANGLE_FAN, function()
			gl.Vertex(mx, my)
			for k = 0, 20 do
				local a = k / 20 * math.pi * 2
				gl.Vertex(mx + math.cos(a) * r, my + math.sin(a) * r)
			end
		end)
		gl.Color(1, 1, 1, 1)
	end
	local tx = x0 + pad + dot + dotGap
	if arrows then
		local a, cy = size * 0.34, y + h / 2
		local function tri(px, d) -- (its point at px, d -1 pointing left; a dark edge under it as the words' outline)
			for pass = 1, 2 do
				local e = pass == 1 and math.max(1, size * 0.06) or 0
				if pass == 1 then
					gl.Color(0, 0, 0, 0.55 * alpha)
				else
					gl.Color(color[1], color[2], color[3], alpha)
				end
				gl.BeginEnd(GL.TRIANGLES, function()
					gl.Vertex(px + d * e, cy)
					gl.Vertex(px - d * (a * 1.2 + e), cy + a + e)
					gl.Vertex(px - d * (a * 1.2 + e), cy - a - e)
				end)
			end
		end
		tri(tx, -1)
		tri(tx + tw, 1)
		gl.Color(1, 1, 1, 1)
		tx = tx + size
	end
	font:Begin()
	font:SetTextColor(color[1], color[2], color[3], alpha)
	font:SetOutlineColor(0, 0, 0, 0.55 * alpha)
	font:Print(text, tx, y + h / 2 - size * 0.36, size, "o")
	font:End()
	if key then
		style.key(x0 + pad + dot + dotGap + tw + gap, math.floor(y + (h - chip) / 2), chip, key, alpha)
	end
end

local lastNote, notes = nil, 0 -- (tools/touch-widget-test.ps1: the last note, also once it has faded, and how many)
local GOLD, BLUE = style.TEXT, style.BLUE -- (notes in the dock's white; blue: v0.8.5's placement notes, "SLOW PAN", "GRID")
local toastColor = GOLD
local toastFor = TOAST_SECONDS
local function note(text, color, seconds)
	toast, toastAt, toastColor, toastFor = text, now(), color or GOLD, seconds or TOAST_SECONDS
	lastNote, notes = text, notes + 1
	voiceToast = false
end

-- (Kailil, 2026-11-05: pressed again within PING_CYCLE_SECONDS, the next older of the last PINGS_KEPT, round to the
-- newest after the oldest; after a pause, the newest again; kept: fewer of them, the dock's last 4)
pingLook = function(kept)
	pingKept = kept or PINGS_KEPT
	local n = math.min(#pings, pingKept)
	if n > 0 then
		local t = now()
		if pingStepAt and Spring.DiffTimers(t, pingStepAt) <= PING_CYCLE_SECONDS and pingStep <= n then
			pingStep = pingStep % n + 1
		else
			pingStep = 1
		end
		pingStepAt = t
		local p = pings[pingStep]
		local x, y, z = p[1], p[2], p[3]
		if p.attack and p.unit and not Spring.GetUnitIsDead(p.unit) then -- (an attack: where its unit is now)
			local ux, uy, uz = Spring.GetUnitPosition(p.unit)
			if ux then
				x, y, z = ux, uy, uz
			end
		end
		-- (upright the dock's own camera move: the ping in the game's middle above the dock, as its other jumps; the
		-- screen's middle was at or behind the dock; review 2026-11-16)
		local P = WG.BarDroidPortrait
		if P and P.active and P.active() and P.cameraTo then
			P.cameraTo(x, y, z)
		else
			Spring.SetCameraTarget(x, y, z, 0.3)
		end
		Spring.Echo(string.format("[bardroid-pad] the camera to %s, %d of %d, at %d,%d", p.attack and "an attack" or "a ping",
			pingStep, n, x, z)) -- (tools)
		if p.attack then
			note(n == 1 and "UNDER ATTACK" or string.format("UNDER ATTACK, %d OF %d", pingStep, n), { 1, 0.4, 0.32 })
		else
			note(n == 1 and "LAST PING" or string.format("PING %d OF %d", pingStep, n))
		end
	else
		Spring.SendCommands("lastmsgpos") -- (none seen: the engine's own jump to the last message's place)
		note("NO PING FROM OTHERS YET")
	end
end

-- speak to chat's note, "< SPEAK TO ALLIES >" in the channel's colour (step: the channel changed first; the note keeps
-- the time the listening has left)
local function voiceNote(step)
	if step and not voiceToast then
		return -- (not listening, as far as this widget knows: no change)
	end
	local left = VOICE_SECONDS
	if step and toastAt then
		left = math.max(1, toastFor - Spring.DiffTimers(now(), toastAt))
	end
	local chat = WG.bardroidChat
	local name, color = "CHAT", nil
	if chat and chat.channel then
		name, color = chat.channel(step)
	end
	note("< SPEAK TO " .. name .. " >", color, left)
	voiceToast = true
end

-- Orders at a point straight to the units only where this widget may give them: BAR's sandbox takes Spring.GiveOrder*
-- from user widgets where the lobby's option forbids them (on by default); the app's widgets loaded as the game's (an
-- engine-branch build, launch-bar.sh BARDROID_GAME_WIDGETS) may. Asked of the function itself, once: an order to no units
local canOrder = nil
local function unitControl()
	if canOrder == nil then
		canOrder = pcall(Spring.GiveOrderToUnitArray, {}, CMD.STOP, {}, 0)
	end
	return canOrder
end

local function shiftHeld()
	local _, _, _, shift = Spring.GetModKeyState()
	return shift
end

local function selectAndLook(units)
	if #units == 0 then
		return false
	end
	Spring.SelectUnitArray(units)
	local x, y, z = Spring.GetUnitPosition(units[1])
	if x then
		Spring.SetCameraTarget(x, y, z, 0.3)
	end
	return true
end

local function myUnits()
	if Spring.GetSpectatingState() then
		return {}
	end
	return Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}
end

-- The order menu's commands in its own order (order states first, then Wait, then the rest)
local function orderCommands()
	local states, others, wait = {}, {}, nil
	local o = WG.ordermenu
	local hasTarget = false
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		if Spring.GetUnitRulesParam(unitID, "hasPriorityTarget") then
			hasTarget = true
			break
		end
	end
	for _, cmd in ipairs(Spring.GetActiveCmdDescs() or {}) do
		if type(cmd) == "table" and not (o.getDisabledCmd and o.getDisabledCmd(cmd.name))
			and not HIDDEN[cmd.id] and not HIDDEN_TYPE[cmd.type] and cmd.action ~= nil and not cmd.disabled
			and not (cmd.id == CANCEL_TARGET and not hasTarget) then
			if cmd.type == CMDTYPE.ICON_BUILDING or cmd.action:find("buildunit_", 1, true) == 1 then -- luacheck: ignore 542
			elseif cmd.type == CMDTYPE.ICON_MODE then
				states[#states + 1] = cmd
			elseif cmd.id == CMD.WAIT then
				wait = cmd
			else
				others[#others + 1] = cmd
			end
		end
	end
	if wait then
		states[#states + 1] = wait
	end
	for _, cmd in ipairs(others) do
		states[#states + 1] = cmd
	end
	return states
end

-- The order menu's cells as BAR lays them out (setupCellGrid in gui_ordermenu.lua), bottom left origin; nil: not shown
local function ordersLayout()
	local o = WG.ordermenu
	if not (o and o.getPosition and o.getIsShowing and o.getIsShowing()) then
		return nil
	end
	if o.droidCells then -- (the app's order menu copy tells its own cells: its even layout with the pad)
		local rects, list = o.droidCells()
		local cells, cmds = {}, {}
		for i, cmd in ipairs(list or {}) do
			local r = rects and rects[i]
			if r and type(cmd) == "table" then
				cells[#cells + 1] = { r[1], r[2], r[3], r[4] }
				cmds[#cmds + 1] = cmd
			end
		end
		return #cmds > 0 and { cmds = cmds, cells = cells } or nil
	end
	local cmds = orderCommands()
	if #cmds == 0 then
		return nil
	end
	local posX, posY, width, height = o.getPosition()
	local vsx, vsy = Spring.GetViewGeometry()
	local bp = WG.FlowUI and WG.FlowUI.elementPadding or 0
	local abp = math.floor(bp * 1.4 + 0.5)
	local ar = {
		posX * vsx + (posX > 0 and abp or math.ceil(bp * 0.6)),
		(posY - height) * vsy + (posY - height > 0 and math.floor(abp) or math.floor(abp / 3)),
		(posX + width) * vsx - abp,
		posY * vsy - abp,
	}
	local add = Spring.GetConfigFloat("ui_scale", 1) < 0.85 and -1 or 0
	local n, cols, rows = #cmds, 7 + add, 7
	for _, s in ipairs({ { 4, 4 }, { 5, 4 }, { 5, 5 }, { 5, 6 }, { 6, 6 }, { 6, 7 } }) do
		if n <= (s[1] + add) * s[2] then
			cols, rows = s[1] + add, s[2]
			break
		end
	end
	local cw, ch = math.floor((ar[3] - ar[1]) / cols), math.floor((ar[4] - ar[2]) / rows)
	local leftW = ((ar[3] - ar[1]) - cw * cols) - 1
	local leftH = ((ar[4] - ar[2]) - ch * rows) - (posY - height <= 0 and 1 or 0)
	local cells, addedH, addedHf = {}, 0, 0
	for row = 1, rows do
		local prevH = addedH
		addedHf = addedHf + leftH / rows
		addedH = math.floor(addedHf)
		local prevW, addedWf = 0, 0
		for col = 1, cols do
			addedWf = addedWf + leftW / cols
			local addedW = math.floor(addedWf)
			cells[#cells + 1] = {
				math.floor(ar[1] + prevW + cw * (col - 1) + 0.5),
				math.floor(ar[4] - addedH - ch * row + 0.5),
				math.ceil(ar[1] + addedW + cw * col + 0.5),
				math.ceil(ar[4] - prevH - ch * (row - 1) + 0.5),
			}
			prevW = addedW
		end
	end
	return { cmds = cmds, cells = cells, cols = cols, rows = rows }
end

local function ordersLight(cmdID)
	local o = WG.ordermenu
	if o and o.clearHighlights then
		o.clearHighlights()
	end
	if cmdID and o and o.setHighlight then
		o.setHighlight(cmdID, HIGHLIGHT)
	end
end

-- (the app glides the pointer back to the middle once no menu has the pad)
local function ordersEnd()
	if orders then
		ordersLight(nil)
	end
	orders = nil
end

local function ordersGo(index)
	local layout = ordersLayout()
	if not layout then
		ordersEnd()
		return
	end
	index = math.max(1, math.min(#layout.cmds, index))
	local r = layout.cells[index]
	orders = { index = index, cmdID = layout.cmds[index].id, layout = layout }
	local x, y = math.floor((r[1] + r[3]) / 2), math.floor((r[2] + r[4]) / 2)
	warpTo(x, y)
	orders.warped = { x, y, now() }
	ordersLight(orders.cmdID)
end

-- The D-pad on the order menu, by where the buttons are (rows may hold different numbers of them: the order menu copy's
-- even layout): left / right the next button in the row, wrapping round it; up / down the nearest in the row above or
-- below, staying put at the top or bottom
local function ordersStep(dx, dy)
	local layout = orders.layout
	local n = #layout.cmds
	local cur = layout.cells[orders.index]
	if not cur then
		ordersGo(1)
		return
	end
	local cx, cy = (cur[1] + cur[3]) / 2, (cur[2] + cur[4]) / 2
	local best, bestScore
	for i = 1, n do
		local r = layout.cells[i]
		local x, y = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
		local sameRow = y > cur[2] and y < cur[4]
		local score
		if dx ~= 0 and sameRow and i ~= orders.index then
			local ahead = (x - cx) * dx
			score = ahead > 0 and ahead or ahead + 1e6 -- (none ahead: the farthest the other way)
		elseif dy ~= 0 and not sameRow and (cy - y) * dy > 0 then -- (dy > 0: down the screen, y smaller)
			score = math.abs(cy - y) * 1e4 + math.abs(x - cx)
		end
		if score and (not bestScore or score < bestScore) then
			best, bestScore = i, score
		end
	end
	ordersGo(best or orders.index)
end

-- A on the order menu: the order as BAR's button gives it (a state changes, an order without a target is given, one
-- with a target is picked: the pointer back to the middle to aim it, A gives it there)
local function ordersSelect()
	local index = Spring.GetCmdDescIndex(orders.cmdID)
	if not index then
		return
	end
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	Spring.SetActiveCommand(index, 1, true, false, alt, ctrl, meta, shift)
	local _, active = Spring.GetActiveCommand()
	if active == orders.cmdID then
		ordersEnd()
	else
		ordersGo(orders.index) -- (the menu may have changed: a state's label, Wait)
	end
end

-- The idle units: the builders' cycle is bardroid_touch.lua's; this is the rest (mobile units with nothing to do)
local function idleMobile(step)
	local idle = {}
	for _, unitID in ipairs(myUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and not def.isBuilder and (def.speed or 0) > 0 and Spring.GetUnitCommandCount(unitID) == 0
			and not Spring.GetUnitIsBeingBuilt(unitID) then
			idle[#idle + 1] = unitID
		end
	end
	if #idle == 0 then
		note("NO IDLE UNITS")
		return
	end
	table.sort(idle)
	local pick = step > 0 and idle[1] or idle[#idle]
	for i = 1, #idle do
		local id = step > 0 and idle[i] or idle[#idle + 1 - i]
		if (step > 0 and id > lastIdleMobile) or (step < 0 and id < lastIdleMobile) then
			pick = id
			break
		end
	end
	lastIdleMobile = pick
	idleType = Spring.GetUnitDefID(pick)
	selectAndLook({ pick })
end

local function idleOfType()
	local selected = Spring.GetSelectedUnits()
	local defID = idleType or (selected[1] and Spring.GetUnitDefID(selected[1]))
	if not defID then
		return
	end
	local units = {}
	for _, unitID in ipairs(myUnits()) do
		if Spring.GetUnitDefID(unitID) == defID and Spring.GetUnitCommandCount(unitID) == 0
			and not Spring.GetUnitIsBeingBuilt(unitID) then
			units[#units + 1] = unitID
		end
	end
	if #units > 0 then
		Spring.SelectUnitArray(units)
		note("IDLE " .. string.upper(UnitDefs[defID].translatedHumanName or UnitDefs[defID].humanName or "") .. " x" .. #units)
	end
end

local function commander()
	local units = {}
	for _, unitID in ipairs(myUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.customParams and def.customParams.iscommander then
			units[#units + 1] = unitID
		end
	end
	if selectAndLook(units) then
		note("COMMANDER")
	end
end

-- Where the pad points: the reticle in the middle of the screen (the pointer only while it is free: it is still gliding
-- back to the middle for 160 ms after a drag or a menu); the unit there, and the ground (under a unit too: patrol or
-- fight on a unit goes to its place)
local function aim()
	local x, y
	if freePointer() then
		x, y = Spring.GetMouseState()
	else
		local vsx, vsy = Spring.GetViewGeometry()
		x, y = math.floor(vsx / 2), math.floor(vsy / 2)
	end
	local kind, target = Spring.TraceScreenRay(x, y)
	local _, pos = Spring.TraceScreenRay(x, y, true)
	return kind == "unit" and target or nil, pos
end

-- An order picked, if any of the selected units has it: true, and text as the note
local function pickOrder(cmdID, name, text)
	Spring.SetActiveCommand(name)
	local picked = select(2, Spring.GetActiveCommand()) == cmdID
	note(picked and text or "NOT FOR THESE UNITS")
	return picked
end

-- An order at the middle of the screen: given at once where allowed, else picked and the app clicks there
local function orderAt(cmdID, name, unitOK)
	local selected = Spring.GetSelectedUnits()
	if #selected == 0 then
		return
	end
	local unitID, pos = aim()
	local opts = shiftHeld() and { "shift" } or {}
	-- (only an order the selection has: a building given a fight would drop it with no word; picked, it says so)
	if unitControl() and Spring.GetCmdDescIndex(cmdID) and ((unitID and unitOK) or pos) then
		local params = (unitID and unitOK) and { unitID } or { pos[1], pos[2], pos[3] }
		if pcall(Spring.GiveOrderToUnitArray, selected, cmdID, params, opts) then
			note(string.upper(name))
			return
		end
	end
	if pickOrder(cmdID, name, string.upper(name)) then -- (else the click would only drop the units)
		padClicks, padClickAt = padClicks + 1, nil
	end
end

local function hasBuilder() -- (a factory neither repairs nor reclaims)
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID)]
		if def and def.isBuilder and not def.isFactory then
			return true
		end
	end
	return false
end

local function enemyAt(unitID)
	return unitID and not Spring.IsUnitAllied(unitID)
end

-- L3 / R3: the next or the last queued order of the selected units removed, by BAR's own Command Queue Manager, which any
-- game allows (it also takes care of area orders and of a build queue before the start). It listens for key presses only,
-- so these two keys, used by nothing else and bound whatever keys the player's BAR has for it, are what PadGame presses.
-- And the portrait dock's INSERT (Kailil, 2026-11-10: "insert things in front of queue"): BAR's CommandInsert puts an
-- order given while its key is down at the front of the queue (Space in BAR's keys, which also shows unit stats, picks
-- idle units in a box and more): the app holds numpad*, which BAR leaves unbound, given the same action.
-- (Any+: QUEUE's Shift held, the dock's remove buttons still reach them)
-- (prepend_queue, 2026-11-22: alone the same as prepend_between, the order at the queue's front; under QUEUE's Shift at
-- the front too, where prepend_between put it where the walk was shortest, often the end)
local QUEUE_KEYS = { { "Any+insert", "command_skip_current" }, { "Any+numpad/", "command_cancel_last" },
	{ "Any+numpad*", "commandinsert prepend_queue" } }
local keysLookedAt = nil
local function bindQueueKeys()
	for _, k in ipairs(QUEUE_KEYS) do
		local bound = false
		for _, key in ipairs(Spring.GetActionHotKeys(k[2]) or {}) do
			bound = bound or key:lower() == k[1]:lower()
		end
		if not bound then
			Spring.SendCommands("bind " .. k[1] .. " " .. k[2])
		end
	end
end

-- (looked at five times a second, not as the note is made: by then PadGame's key may have taken the only order away)
local hasOrders, ordersLookedAt = false, nil
local function lookAtOrders(t)
	if ordersLookedAt and Spring.DiffTimers(t, ordersLookedAt) < 0.2 then
		return
	end
	ordersLookedAt, hasOrders = t, false
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		if (Spring.GetUnitCommandCount(unitID) or 0) > 0 then
			hasOrders = true
			break
		end
	end
end

local function queueRemove(last)
	if Spring.GetGameFrame() == 0 or hasOrders then
		note(last and "REMOVED LAST ORDER" or "REMOVED NEXT ORDER")
	else
		note("NO ORDERS QUEUED")
	end
end

-- The same keys asked of the app for the portrait dock's remove buttons (bardroid_pad.txt "key <n> first|last": RtsTouch
-- presses Insert or numpad/ when n grows)
local padKeys, padKeyName = 0, "first"
local function queueKey(last)
	padKeys, padKeyName = padKeys + 1, last and "last" or "first"
	queueRemove(last)
end

local function pregameBuild()
	local pb = WG["pregame-build"]
	return Spring.GetGameFrame() == 0 and pb and pb.getPreGameDefID and pb.getPreGameDefID() ~= nil
end
-- the building picked for BAR's pregame queue put away: its setPreGamestartDefID (this called its old name
-- setPreGameDefID, gone from BAR: an error, and BAR took the pad's widget out of the game, 2026-11-09)
local function pregamePutAway()
	local pb = WG["pregame-build"]
	local putAway = pb and (pb.setPreGamestartDefID or pb.setPreGameDefID)
	if putAway then
		putAway(nil)
	end
end

-- LB + B with factories selected: each stopped with its whole queue gone. BAR's own Stop Production (it keeps the unit
-- being built), then that one taken off too (a right click on its build option, Ctrl+Shift: as many as there are); each
-- as BAR's menus give them, which any game allows. True when there were factories
local CMD_STOP_PRODUCTION = (GameCMD and GameCMD.STOP_PRODUCTION) or 13923 -- luacheck: ignore 113 (BAR's global)
local function clearFactories()
	local factories = {}
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
		if def and def.isFactory then
			factories[#factories + 1] = unitID
		end
	end
	if #factories == 0 then
		return false
	end
	local inBuild = {} -- (the unit each is building: read before Stop Production empties the queues)
	for _, unitID in ipairs(factories) do
		local first = (Spring.GetFactoryCommands(unitID, 1) or {})[1]
		if first and first.id < 0 then
			inBuild[first.id] = true
		end
	end
	local index = Spring.GetCmdDescIndex(CMD_STOP_PRODUCTION)
	if index then
		Spring.SetActiveCommand(index, 1, true, false, false, false, false, false)
	end
	for cmdID in pairs(inBuild) do
		index = Spring.GetCmdDescIndex(cmdID)
		if index then
			Spring.SetActiveCommand(index, 3, false, true, false, true, false, true)
		end
	end
	note(#factories > 1 and "FACTORIES STOPPED, QUEUES CLEARED" or "FACTORY STOPPED, QUEUE CLEARED")
	return true
end

-- What kind of order is picked, for the app: a building, an area only (area mex: A starts its circle, the next A ends
-- it), a unit or an area (repair, reclaim: hold A and draw for the area), another order, or none. Asked every frame:
-- a command's kind is looked up once (GetActiveCmdDesc makes a table each call)
local kindOf = {}
local function armedKind()
	if pregameBuild() then
		return "build"
	end
	local _, id = Spring.GetActiveCommand()
	if not id then
		return "none"
	elseif id < 0 then
		return "build"
	end
	local kind = kindOf[id]
	if not kind then
		local index = Spring.GetCmdDescIndex(id)
		local desc = index and Spring.GetActiveCmdDesc(index)
		local t = desc and desc.type
		if t == CMDTYPE.ICON_AREA then
			kind = "area"
		elseif t == CMDTYPE.ICON_UNIT_OR_AREA or t == CMDTYPE.ICON_UNIT_FEATURE_OR_AREA or t == CMDTYPE.ICON_UNIT_OR_RECTANGLE then
			kind = "unitarea"
		else
			kind = "other"
		end
		if desc then
			kindOf[id] = kind
		end
	end
	return kind
end

-- The units the area select has passed over that its filter takes: mobile units first (buildings only when there are
-- none, or with RT); of those, builders only when no combat unit is among them (Builders: builders only)
local function chooseUnits(units, defOf, filter, shift)
	local builders, others, buildings = {}, {}, {}
	for _, unitID in ipairs(units) do
		local def = defOf(unitID)
		if def and (def.speed or 0) > 0 and not def.isFactory then
			local builder = def.isBuilder
			local fits = filter == "All Mobile" or (filter == "Air" and def.canFly) or (filter == "Builders" and builder)
				or (filter == "Combat" and not builder and (def.canAttack or #(def.weapons or {}) > 0))
			if fits then
				local list = builder and builders or others
				list[#list + 1] = unitID
			end
		elseif def then
			buildings[#buildings + 1] = unitID
		end
	end
	local pick = #others > 0 and others or builders
	if shift or (#pick == 0 and filter == "All Mobile") then
		for _, unitID in ipairs(buildings) do
			pick[#pick + 1] = unitID
		end
	end
	return pick
end

local function unitDefOf(unitID)
	return UnitDefs[Spring.GetUnitDefID(unitID) or -1]
end

-- RB + D-pad down / right: the player's combat units, all of them or those on the screen (the area select's Combat)
local function selectCombat(units, name)
	local pick = chooseUnits(units, unitDefOf, "Combat", false)
	if #pick == 0 then
		note("NO COMBAT UNITS")
		return
	end
	Spring.SelectUnitArray(pick)
	note(name .. ": " .. #pick)
end

local function areaPick()
	local units = {}
	for unitID in pairs(area.units) do
		units[#units + 1] = unitID
	end
	local pick = chooseUnits(units, unitDefOf, area.filter, area.shift)
	for _, unitID in ipairs(area.keep) do
		pick[#pick + 1] = unitID
	end
	return pick
end

-- The area select's step: the units under the circle added, the selection set when that changed
local function areaUpdate(force)
	local vsx, vsy = Spring.GetViewGeometry()
	local _, pos = Spring.TraceScreenRay(math.floor(vsx / 2), math.floor(vsy / 2), true)
	if not pos then
		area.x = nil
		return
	end
	area.x, area.y, area.z = pos[1], pos[2], pos[3]
	local added = false
	for _, unitID in ipairs(Spring.GetUnitsInCylinder(pos[1], pos[3], area.radius, Spring.GetMyTeamID()) or {}) do
		if not area.units[unitID] then
			area.units[unitID] = true
			area.count = area.count + 1
			added = true
		end
	end
	if added or force then
		Spring.SelectUnitArray(areaPick())
	end
end

local function cancel()
	if pregameBuild() then
		pregamePutAway()
	elseif select(2, Spring.GetActiveCommand()) then
		Spring.SetActiveCommand(0)
	else
		Spring.SelectUnitArray({})
	end
end

-- The app's build menu (bardroid_buildmenu.lua, WG.bardroidBuildmenu): RB puts the pointer on it (Kailil, of v0.8.5's
-- own focus: "its doing a weird selector system, i dont want that, i want a mouse cursor, with a stroke just like the
-- orders").
local function buildMenu(name)
	local b = WG.bardroidBuildmenu
	if b and b.droidPad then
		b.droidPad(name)
	end
end

local function buildFocus()
	local b = WG.bardroidBuildmenu
	return b and b.droidFocus and b.droidFocus() ~= nil or false
end

-- The pad's own modes, one at a time: v0.8.5's D-gun mode ("dgun") and the share list ("share"). While one is on only
-- its buttons count in the app (bardroid_pad.txt "modal dgun|share|none", PadGame).
local modal = nil

-- A click asked of the app at a point on the screen (engine pixels, from the bottom left)
local function clickAt(sx, sy)
	local vsx, vsy = Spring.GetViewGeometry()
	padClicks = padClicks + 1
	padClickAt = { sx / vsx, 1 - sy / vsy }
end

-- The point on the screen for a click on the ground at x, y, z: on the screen and off the interface (BAR's panels, the
-- minimap: a click there would press a button), else nil
local function clickable(x, y, z)
	local sx, sy, sz = Spring.WorldToScreenCoords(x, y, z)
	local vsx, vsy = Spring.GetViewGeometry()
	if not sx or sz > 1 or sx < 2 or sx > vsx - 3 or sy < 2 or sy > vsy - 3 then
		return nil
	end
	local over = WG.BarDroidOnInterface
	if over and over(math.floor(sx), math.floor(sy)) then
		return nil
	end
	-- (and on the ground: a point on the map's edge was a pixel off it half the time, and the engine refused the shot;
	-- dev phone, a commander by the north edge, 2026-11-09)
	if not Spring.TraceScreenRay(math.floor(sx + 0.5), math.floor(sy + 0.5), true) then
		return nil
	end
	return sx, sy
end

-- x, z kept this far inside the map's edges
local MAP_MARGIN = 24
local function onMap(x, z)
	return math.max(MAP_MARGIN, math.min(Game.mapSizeX - MAP_MARGIN, x)),
		math.max(MAP_MARGIN, math.min(Game.mapSizeZ - MAP_MARGIN, z))
end

local function selectedCommander()
	for _, unitID in ipairs(Spring.GetSelectedUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(unitID) or -1]
		if def and def.customParams and def.customParams.iscommander then
			return unitID, def
		end
	end
	return nil
end

-- v0.8.5's D-gun mode (Kailil, 2026-11-06: "make LB + RB + R3 the dgun control mechanism that the commander has in
-- 0.8.5"; v0.8.5's own Back + R3 opens it too): the selected commander's D-gun aimed around it at the D-gun's range.
-- While it lasts the sticks are its (bardroid_touch.lua hands them over; the camera stays): the right stick aims (past
-- half way, along the camera's heading), the left stick walks the commander (a move 150 ahead, every 0.2 s); RT fires
-- once, B leaves; v0.8.5's red range ring, target and line on the ground. It ends when the commander is no longer
-- selected or is lost. Where the host lets user widgets give orders the move and the shot go to the commander as in
-- v0.8.5; where it does not, BAR's Move or D-gun is picked and the app clicks on the point (it has to be on the screen
-- and off the interface: a shot aimed off it goes to the farthest point of the aim that is on it, the same way).
local DGUN_AIM_DEADZONE, DGUN_MOVE_DEADZONE = 0.5, 0.4
local DGUN_TOUCH_AIM_DEADZONE = 0.2 -- (the dock's touch AIM: its ring's fifth; a thumb's short flick aims)
-- (the walk's step: 150 ahead walked on for 4 s after the stick was let go; Kailil, 2026-11-10: "move commands to be
-- way shorter so if I stop moving my analog, the commander almost stops walking immediately": 56 ahead, given more
-- often, and a stop as the stick comes to rest, dgunUpdate)
local DGUN_MOVE_STEP, DGUN_MOVE_EVERY, DGUN_FIRE_EVERY = 56, 0.15, 0.15
local DGUN_RANGE = 280 -- (v0.8.5's when the D-gun's own is not found)
local DGUN_SHOT_HOLD = 0.6 -- seconds after a shot is ordered with no step from the stick (a move order replaces it)
local dgun = nil -- { unitID, range, aimX, aimZ, x, y, z: the target, lx, ly, rx, ry: the sticks, moveAt, fireAt,
-- weapon, cost, speed: the D-gun's number, energy a shot and speed (elmos a frame); auto, autoAt, target: full auto }

-- the D-gun's range, its weapon number (GetUnitWeaponState's), energy a shot and projectile speed
local function dgunWeapon(def)
	for i, w in ipairs(def.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and (wd.range or 0) > 0 and (wd.manualFire or wd.type == "DGun") then
			return wd.range, i, wd.energyCost or 0, wd.projectilespeed or 0
		end
	end
	return DGUN_RANGE
end

-- A stick past its deadzone as a heading on the ground, from the camera's (v0.8.5's); nil at rest
local function stickHeading(x, y, deadzone)
	if math.sqrt(x * x + y * y) <= deadzone then
		return nil
	end
	local cx, _, cz = Spring.GetCameraDirection()
	local len = math.sqrt((cx or 0) ^ 2 + (cz or 0) ^ 2)
	local fx, fz = 0, -1
	if len > 0.001 then
		fx, fz = cx / len, cz / len
	end
	local hx, hz = x * -fz - y * fx, x * fx - y * fz
	len = math.sqrt(hx * hx + hz * hz)
	if len <= 0.001 then
		return 0, -1
	end
	return hx / len, hz / len
end

-- The touch sticks (the dock's MOVE and AIM): the way the stick points on the screen, from the unit's own place there,
-- found on the ground under that pixel: what the player sees, whatever the camera's turn and tilt. The camera's heading
-- above gave the world's axes on a camera turned by the rail (the night's touch playtest, in play 2026-11-22: a flick
-- to the right aimed down and right). The heading above where the unit is off the screen or the pixel is sky.
local function screenHeading(unitID, x, y, deadzone)
	local len = math.sqrt(x * x + y * y)
	if len <= deadzone then
		return nil
	end
	local ux, uy, uz = Spring.GetUnitPosition(unitID)
	if ux then
		local sx, sy, sz = Spring.WorldToScreenCoords(ux, uy, uz)
		local reach = math.max(60, math.floor(Spring.GetViewGeometry() * 0.12))
		if sz <= 1 then -- (y down on the stick, up in GL pixels)
			local _, pos = Spring.TraceScreenRay(math.floor(sx + x / len * reach + 0.5), math.floor(sy - y / len * reach + 0.5), true)
			local dx, dz = pos and pos[1] - ux or 0, pos and pos[3] - uz or 0
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 1 then
				return dx / d, dz / d
			end
		end
	end
	return stickHeading(x, y, deadzone)
end

local function dgunTarget(d)
	local cx, cy, cz = Spring.GetUnitPosition(d.unitID)
	if not cx then
		return false
	end
	d.x, d.z = onMap(cx + d.aimX * d.range, cz + d.aimZ * d.range)
	d.y = Spring.GetGroundHeight(d.x, d.z) or cy
	return true
end

local function dgunExit(text)
	if dgun then
		dgun = nil
		modal = nil
		if text then
			note(text)
		end
	end
end

local function dgunEnter()
	if Spring.GetSpectatingState() then
		note("NOT WHILE SPECTATING")
		return
	end
	local unitID, def = selectedCommander()
	if not unitID then
		note("SELECT THE COMMANDER")
		return
	end
	if modal == "share" then
		return
	end
	local cx, _, cz = Spring.GetUnitPosition(unitID)
	if not cx then
		return
	end
	-- the first aim: to the reticle's ground, else the camera's heading (v0.8.5's)
	local _, pos = aim()
	local dx, dz = pos and pos[1] - cx or 0, pos and pos[3] - cz or 0
	local dist = math.sqrt(dx * dx + dz * dz)
	local ax, az
	if dist > 10 then
		ax, az = dx / dist, dz / dist
	else
		ax, az = stickHeading(0, -1, 0)
	end
	local range, weapon, cost, speed = dgunWeapon(def)
	dgun = { unitID = unitID, range = range, weapon = weapon, cost = cost, speed = speed, aimX = ax, aimZ = az,
		lx = 0, ly = 0, rx = 0, ry = 0 }
	modal = "dgun"
	dgunTarget(dgun)
	local P = WG.BarDroidPortrait -- (the touch dock's sticks and FIRE need no gamepad words over the map)
	if not (P and P.dock and P.dock()) then
		note("D-GUN: RIGHT STICK AIMS, RT FIRES, B LEAVES", nil, 3)
	end
end

-- An order on the ground for the commander: given where allowed, else picked and clicked (off the screen or over the
-- interface: the farthest point towards from that is clickable, for a shot; none for a move)
local function dgunOrder(cmdID, name, x, y, z, along)
	local d = dgun
	if unitControl() and pcall(Spring.GiveOrderToUnit, d.unitID, cmdID, { x, y, z }, 0) then
		return true
	end
	local cx, cy, cz = Spring.GetUnitPosition(d.unitID)
	local sx, sy = clickable(x, y, z)
	if not sx and along and cx then
		for t = 0.9, 0.15, -0.075 do
			local px, pz = cx + (x - cx) * t, cz + (z - cz) * t
			sx, sy = clickable(px, Spring.GetGroundHeight(px, pz) or cy, pz)
			if sx then
				break
			end
		end
	end
	if not sx then
		return false
	end
	Spring.SetActiveCommand(name)
	if select(2, Spring.GetActiveCommand()) ~= cmdID then
		return false
	end
	clickAt(sx, sy)
	d.clickedAt = now()
	return true
end

-- Full auto (Kailil, 2026-11-10: "add an dgun full auto mode by holding fire button then swiping to the right"; on the
-- portrait dock, RtsTouch's "act dgun_auto"; FIRE again turns it off): whenever the D-gun is loaded and the energy is
-- there, it fires at the best enemy in its range seen (a commander first, then the dearest, the nearer the better; no
-- aircraft), led by the target's speed, and never where the shot's path (out to its full range: it goes through
-- everything) passes one of our or our allies' units. Only where the host lets user widgets give orders (BAR's "Allow
-- Custom 'Unit Control' Widgets"): it aims and fires on its own, which that rule is there to forbid, so the app's clicks
-- never stand in for its shots (bardroid_retreat.lua stands down the same way; the D-gun by hand still works there).
local DGUN_AUTO_EVERY, DGUN_AUTO_SAFE = 0.1, 40 -- seconds between looks; elmos kept between the path and a friend
local function dgunAuto(d)
	local t = now()
	if d.autoAt and Spring.DiffTimers(t, d.autoAt) < DGUN_AUTO_EVERY then
		return
	end
	d.autoAt = t
	d.target = nil
	if d.fireAt and Spring.DiffTimers(t, d.fireAt) < DGUN_SHOT_HOLD then
		return -- (a shot ordered just now: let it go first)
	end
	local cx, _, cz = Spring.GetUnitPosition(d.unitID)
	if not cx then
		return
	end
	local friends, best, bestScore, bx, bz = {}, nil, 0, 0, 0
	for _, u in ipairs(Spring.GetUnitsInCylinder(cx, cz, d.range + 60) or {}) do
		if u ~= d.unitID and Spring.IsUnitAllied(u) then
			friends[#friends + 1] = u
		end
	end
	local loaded = true
	if d.weapon then
		local ready = Spring.GetUnitWeaponState(d.unitID, d.weapon, "reloadFrame")
			or Spring.GetUnitWeaponState(d.unitID, d.weapon, "reloadState")
		loaded = not ready or ready <= Spring.GetGameFrame()
	end
	local energy = Spring.GetTeamResources(Spring.GetMyTeamID(), "energy") or 0
	for _, u in ipairs(Spring.GetUnitsInCylinder(cx, cz, d.range * 0.95) or {}) do
		local def = not Spring.IsUnitAllied(u) and UnitDefs[Spring.GetUnitDefID(u) or -1]
		if def and not def.canFly and Spring.GetUnitIsDead(u) == false then
			local ux, _, uz = Spring.GetUnitPosition(u)
			local dist = ux and math.sqrt((ux - cx) ^ 2 + (uz - cz) ^ 2) or 0
			if ux and dist > 10 then
				if d.speed and d.speed > 0 then -- (where it will be when the shot gets there)
					local vx, _, vz = Spring.GetUnitVelocity(u)
					ux, uz = ux + (vx or 0) * dist / d.speed, uz + (vz or 0) * dist / d.speed
				end
				local dx, dz = ux - cx, uz - cz
				local len = math.sqrt(dx * dx + dz * dz)
				local clear = len > 1
				for i = 1, clear and #friends or 0 do -- (the path: a line from the commander out to the range)
					local fx, _, fz = Spring.GetUnitPosition(friends[i])
					if fx then
						local along = ((fx - cx) * dx + (fz - cz) * dz) / len
						local side = math.abs((fx - cx) * dz - (fz - cz) * dx) / len
						if along > -20 and along < d.range + 20
							and side < DGUN_AUTO_SAFE + (Spring.GetUnitRadius(friends[i]) or 16) then
							clear = false
							break
						end
					end
				end
				local value = def.customParams and def.customParams.iscommander and 1e6
					or (def.metalCost or 0) + (def.energyCost or 0) / 60
				local score = value / (1 + dist / d.range)
				if clear and score > bestScore then
					best, bestScore, bx, bz = u, score, dx / len, dz / len
				end
			end
		end
	end
	if not best then
		return
	end
	d.target = best
	d.aimX, d.aimZ = bx, bz -- (the aim line shows where it will go)
	if loaded and energy >= (d.cost or 0) and dgunTarget(d) and unitControl()
		and pcall(Spring.GiveOrderToUnit, d.unitID, CMD.MANUALFIRE, { d.x, d.y, d.z }, 0) then
		d.fireAt = t
	end
end

-- An enemy tapped in the dock's D-gun mode (bardroid_portrait.lua, aimAtUnit): the aim kept on it, led by its speed as
-- full auto leads its pick, until the stick or a ground tap takes the aim, or it is lost. The touch playtest's game 9,
-- 2026-11-22: the camera follows the commander, so a moving enemy tapped as a ground point was elsewhere by FIRE.
local function dgunTrack(d)
	local u = d.track
	local ux, _, uz = Spring.GetUnitPosition(u)
	if not ux or Spring.GetUnitIsDead(u) ~= false then
		d.track = nil
		note("D-GUN: TARGET LOST")
		return
	end
	local cx, _, cz = Spring.GetUnitPosition(d.unitID)
	if not cx then
		return
	end
	local dist = math.sqrt((ux - cx) ^ 2 + (uz - cz) ^ 2)
	if d.speed and d.speed > 0 then
		local vx, _, vz = Spring.GetUnitVelocity(u)
		ux, uz = ux + (vx or 0) * dist / d.speed, uz + (vz or 0) * dist / d.speed
	end
	local dx, dz = ux - cx, uz - cz
	local len = math.sqrt(dx * dx + dz * dz)
	if len > 10 then
		d.aimX, d.aimZ = dx / len, dz / len
	end
	-- (the aim's rings drawn there, where the shot meets it, while it is within reach; the shot still goes to the reach
	-- on that line, through it. They stood at the reach beyond it: the in-play tour, 2026-11-22)
	d.leadX, d.leadZ, d.leadIn = ux, uz, len <= (d.range or 0)
end

-- where the aim's rings stand: on a tapped enemy within reach (its led place), else at the reach on the aim's line
local function dgunRing(d)
	if d.track and d.leadIn and d.leadX then
		return d.leadX, Spring.GetGroundHeight(d.leadX, d.leadZ) or d.y, d.leadZ
	end
	return d.x, d.y, d.z
end

local function dgunUpdate()
	local d = dgun
	local unitID = selectedCommander()
	-- (the app's click for the shot or a step sometimes left nothing selected after it, and the mode ended at once:
	-- the commander picked again within a second of such a click; dev phone, online rules, 2026-11-09)
	if unitID ~= d.unitID and d.clickedAt and Spring.DiffTimers(now(), d.clickedAt) < 1
		and Spring.GetUnitIsDead(d.unitID) == false and Spring.GetUnitTeam(d.unitID) == Spring.GetMyTeamID()
		and Spring.GetSelectedUnitsCount() == 0 then
		Spring.SelectUnitArray({ d.unitID })
		unitID = d.unitID
	end
	if unitID ~= d.unitID or Spring.GetUnitIsDead(d.unitID) ~= false
		or Spring.GetUnitTeam(d.unitID) ~= Spring.GetMyTeamID() then
		dgunExit("D-GUN OFF")
		return
	end
	local ax, az
	if d.touch then -- (the dock's sticks: their ways on the screen, the AIM from a fifth of its ring; sticks() above)
		ax, az = screenHeading(d.unitID, d.rx, d.ry, DGUN_TOUCH_AIM_DEADZONE)
	else
		ax, az = stickHeading(d.rx, d.ry, DGUN_AIM_DEADZONE)
	end
	if ax and not d.auto then
		d.aimX, d.aimZ = ax, az
		d.track = nil -- (the stick takes the aim back from a tapped enemy)
	end
	if d.track and not d.auto then
		dgunTrack(d)
	end
	if not dgunTarget(d) then
		dgunExit("D-GUN OFF")
		return
	end
	if d.auto then
		dgunAuto(d)
	end
	local mx, mz
	if d.touch then
		mx, mz = screenHeading(d.unitID, d.lx, d.ly, DGUN_MOVE_DEADZONE)
	else
		mx, mz = stickHeading(d.lx, d.ly, DGUN_MOVE_DEADZONE)
	end
	local t = now()
	-- (no step just after a shot is ordered: the step's move took the shot's place in the queue before the commander
	-- had turned to it)
	local shotHeld = d.fireAt and Spring.DiffTimers(t, d.fireAt) < DGUN_SHOT_HOLD
	if mx and (not d.moveAt or Spring.DiffTimers(t, d.moveAt) >= DGUN_MOVE_EVERY) and not shotHeld then
		d.moveAt, d.walking = t, true
		local cx, cy, cz = Spring.GetUnitPosition(d.unitID)
		local x, z = onMap(cx + mx * DGUN_MOVE_STEP, cz + mz * DGUN_MOVE_STEP)
		dgunOrder(CMD.MOVE, "move", x, Spring.GetGroundHeight(x, z) or cy, z, false)
	elseif not mx and d.walking and not shotHeld then
		-- (the stick at rest: the commander stops where it is; not over a shot just ordered, which a stop would drop)
		d.walking = false
		-- (a shot ordered after the last step took the step's place already: a stop then dropped a shot still turning,
		-- walking into range or waiting for energy, once the shot's hold was over, 2026-11-11)
		local shotSince = d.fireAt and (not d.moveAt or Spring.DiffTimers(d.fireAt, d.moveAt) >= 0)
		if shotSince then
			return
		end
		if not (unitControl() and pcall(Spring.GiveOrderToUnit, d.unitID, CMD.STOP, {}, 0)) then
			local cx, cy, cz = Spring.GetUnitPosition(d.unitID)
			dgunOrder(CMD.MOVE, "move", cx, cy, cz, false)
		end
	end
end

local function dgunFire()
	local d = dgun
	if not d then
		return
	end
	if d.auto then -- (FIRE again: full auto off, no shot)
		d.auto, d.target = false, nil
		note("AUTO D-GUN OFF")
		return
	end
	local t = now()
	if d.fireAt and Spring.DiffTimers(t, d.fireAt) < DGUN_FIRE_EVERY then
		return
	end
	d.fireAt = t
	if dgunTarget(d) and dgunOrder(CMD.MANUALFIRE, "manualfire", d.x, d.y, d.z, true) then
		note("D-GUN FIRED")
	else
		note("D-GUN: AIM ON THE SCREEN")
	end
end

local function dgunDraw()
	local d = dgun
	local cx, cy, cz = Spring.GetUnitPosition(d.unitID)
	if not (cx and d.x) then
		return
	end
	gl.DepthTest(false)
	gl.LineWidth(1.5)
	gl.Color(1, 0, 0, 0.25) -- (v0.8.5's: a faint range ring, the target in two rings, a line to it)
	if d.auto then -- (full auto: the ring pulses gold-red, a sweep goes round it, the target held in brackets)
		-- (never under 0, nor NaN: math.max(0, NaN) is 0. A difference of two timers came out just under 0 or not a
		-- number, its sonar ring's ping ^ 0.7 was NaN, and DrawGroundCircle's error took this whole widget out, the
		-- D-gun mode with it: dev phone, dock-phone-test, FIRE swiped right, 2026-11-15)
		local t = math.max(0, Spring.DiffTimers(now(), d.autoOn or now()))
		local pulse = 0.5 + 0.5 * math.sin(t * 6)
		gl.LineWidth(2 + pulse)
		gl.Color(1, 0.35 + 0.35 * pulse, 0.1, 0.45 + 0.35 * pulse)
		if t < 0.5 then -- (as it engages: a ring sweeping out to the range)
			gl.DrawGroundCircle(cx, cy, cz, d.range * (0.2 + 1.6 * t), 64)
		end
		-- the sonar (Kailil, 2026-11-10: "make the sonar animation that plays in auto mode more pronounced"): a ping ring
		-- out from the commander to the range every 1.1 s, thick and bright as it leaves, thin and faded at the edge; a
		-- radar wedge sweeping round behind a bright leading line, fading over its 0.9 rad tail
		local ping = math.max(0, math.min(1, (t % 1.1) / 1.1))
		gl.LineWidth(1 + 5 * (1 - ping))
		gl.Color(1, 0.6, 0.15, 0.9 * (1 - ping))
		gl.DrawGroundCircle(cx, cy, cz, d.range * ping ^ 0.7, 64)
		local a = t * 2.5
		local tail, parts = 0.9, 18
		gl.BeginEnd(GL.TRIANGLE_FAN, function()
			gl.Color(1, 0.5, 0.1, 0.3)
			gl.Vertex(cx, cy + 4, cz)
			for i = 0, parts do
				local q = i / parts -- (0: the leading edge, 1: the end of the tail)
				local b = a - q * tail
				gl.Color(1, 0.5 + 0.2 * (1 - q), 0.1, 0.42 * (1 - q) ^ 1.5)
				gl.Vertex(cx + math.cos(b) * d.range, cy + 4, cz + math.sin(b) * d.range)
			end
		end)
		gl.LineWidth(3)
		gl.Color(1, 0.85, 0.35, 0.95)
		gl.BeginEnd(GL.LINES, function()
			gl.Vertex(cx, cy + 5, cz)
			gl.Vertex(cx + math.cos(a) * d.range, cy + 5, cz + math.sin(a) * d.range)
		end)
		gl.LineWidth(2 + pulse)
		gl.Color(1, 0.35 + 0.35 * pulse, 0.1, 0.55 + 0.4 * pulse)
		gl.DrawGroundCircle(cx, cy, cz, d.range, 64)
		local tx, ty, tz
		if d.target then
			tx, ty, tz = Spring.GetUnitPosition(d.target)
		end
		if tx then
			local r = (Spring.GetUnitRadius(d.target) or 20) + 10
			local spin = t * 1.5
			for k = 0, 3 do
				local b = spin + k * math.pi / 2
				gl.BeginEnd(GL.LINE_STRIP, function()
					for i = -3, 3 do
						local c = b + i * 0.12
						gl.Vertex(tx + math.cos(c) * r, ty + 6, tz + math.sin(c) * r)
					end
				end)
			end
		end
		gl.LineWidth(1.5)
		gl.Color(1, 0, 0, 0.25)
	end
	gl.DrawGroundCircle(cx, cy, cz, d.range, 64)
	if not d.auto then -- (the stick's aim: full auto shoots what it picks, its brackets above; the stick's ring and line
		-- pointed at a spot it ignores, dev phone screenshot 2026-11-11)
		gl.LineWidth(2.5)
		gl.Color(1, 0, 0, 0.8)
		local rx, ry, rz = dgunRing(d)
		gl.DrawGroundCircle(rx, ry, rz, 32, 24)
		gl.DrawGroundCircle(rx, ry, rz, 8, 12)
		local tx, ty, tz -- (a tapped enemy the aim follows: a ring round it, dgunTrack)
		if d.track then
			tx, ty, tz = Spring.GetUnitPosition(d.track)
		end
		if tx then
			gl.DrawGroundCircle(tx, ty, tz, (Spring.GetUnitRadius(d.track) or 20) + 12, 24)
		end
		gl.BeginEnd(GL.LINE_STRIP, function()
			gl.Vertex(cx, cy + 12, cz)
			gl.Vertex(d.x, d.y + 2, d.z)
		end)
	end
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

-- The share list (Kailil, 2026-11-06: "a way to share selected units to another player quickly on gamepad ... LB +
-- Double tap Up on dpad hold ... a toast that cycles through a list of my team mates and their respective colors
-- represented by their names text being the color ... regular dpad then to cycle through the list up and down ... on
-- the center of the screen semi transparent. Pressing A confirms the transfer. B CANCELS"): the selected units go to
-- the teammate picked with BAR's own share (Spring.ShareResources, as its player list's: no order, so in every game).
-- Metal and energy too (Kailil, 2026-11-08: "expand the share units interface to also be able tk send power and metal
-- to your teammates in a sleek and nice looking ui ux way"): LB / RB switch what is given (UNITS, METAL, ENERGY), the
-- D-pad left / right how much (a share of what this team holds), each teammate's row shows how much of it they hold;
-- never more than the teammate has room for (BAR's storage: the rest would be lost).
local SHARE_TABS = { "UNITS", "METAL", "ENERGY" }
local SHARE_STEPS = { 0.1, 0.25, 0.5, 0.75, 1 }
-- (UNITS a soft green: in gold beside ENERGY's yellow the two tabs read alike, dev phone 2026-11-17)
local SHARE_COLORS = { UNITS = { 0.55, 0.88, 0.55 }, METAL = { 0.8, 0.84, 0.92 }, ENERGY = { 1, 0.86, 0.22 } }
local share = nil -- { index, teams = { { teamID, name, color } }, tab (SHARE_TABS), step (SHARE_STEPS) }
local shareLastTab, shareLastStep = 2, 2 -- (the resource and the amount last used: metal, a quarter)
-- units just given, each give its own: { units, teamID, from, at }; still ours SHARE_CHECK_SECONDS later with some gone:
-- BAR kept the rest; none gone: the share may not have run yet (a phone behind its game), so up to SHARE_WAIT_SECONDS
-- (a second give within the first's 1.5 s took its place, its report lost; review 2026-11-15)
local given = {}
local shareRect = nil -- the list as drawn last: x0, y0, x1, y1, the first teammate shown, how many, the room's top and
-- floor (tools/pad-test.ps1)
local toastDrawnAt = nil -- the note as drawn last: its bottom and top (tools/pad-test.ps1)
local SHARE_CHECK_SECONDS, SHARE_WAIT_SECONDS = 1.5, 6

-- BAR's rules for a gift, as its gadgets apply them (review 2026-11-15): a team with nobody at its controls (left,
-- away, lagging: its numActivePlayers 0) takes nothing (cmd_idle_players.lua, unless cheats are on), A said "GIVING"
-- and nothing moved; and Tax Resource Sharing (a modoption, easytax's 30 %) gives the teammate (1 - tax) of a transfer,
-- up to their room, the sender paying it all: sent at their room, a third of it was lost
local shareRules = {}
function shareRules.away(teamID)
	local n = Spring.GetTeamRulesParam(teamID, "numActivePlayers")
	return n ~= nil and n == 0 and not Spring.IsCheatingEnabled()
end
function shareRules.tax()
	local mo = Spring.GetModOptions() or {}
	local e = mo.easytax
	if e == true or e == "1" or e == "true" then
		return 0.3
	end
	local t = tonumber(mo.tax_resource_sharing_amount) or 0
	return (t > 0 and t < 1) and t or 0
end
-- what to send for a want and their room, and what arrives (whole numbers)
function shareRules.amount(want, room)
	local tax = shareRules.tax()
	local amount = math.min(want, tax > 0 and math.floor(room / (1 - tax)) or room)
	return amount, math.floor(math.min((1 - tax) * amount, room)), tax
end
function shareRules.taxWords(tax)
	return tax > 0 and (" (" .. math.floor(tax * 100 + 0.5) .. "% TAX)") or ""
end

local function teammates()
	local list = {}
	local myTeam = Spring.GetMyTeamID()
	-- (BAR's anonymous mode hides who plays which team: the list shows them by colour and number only)
	local mode = (Spring.GetModOptions() or {}).teamcolors_anonymous_mode
	local anonymous = mode ~= nil and mode ~= "" and mode ~= "disabled"
	local number = 0 -- (anonymous: each teammate numbered by team, the dead counted too, so the numbers never move: a
	-- death renumbered the rest, the pick's row then another team under the same label; review 2026-11-15)
	for _, teamID in ipairs(Spring.GetTeamList(Spring.GetMyAllyTeamID()) or {}) do
		local _, leader, isDead, isAI = Spring.GetTeamInfo(teamID, false)
		if teamID ~= myTeam then
			number = number + 1
		end
		if teamID ~= myTeam and not isDead then
			local name
			for _, playerID in ipairs(Spring.GetPlayerList(teamID, true) or {}) do
				local pname, active, spectator = Spring.GetPlayerInfo(playerID, false)
				if pname and active and not spectator then
					name = name and (name .. ", " .. pname) or pname -- (a team of several players: all of them)
				end
			end
			if not name and isAI then
				-- (BAR's own name for it first, the one its player list shows; the start script's was another)
				local aiName = Spring.GetGameRulesParam("ainame_" .. teamID) or select(2, Spring.GetAIInfo(teamID))
				name = aiName or ("AI " .. teamID)
			end
			if not name and leader and leader >= 0 then
				name = Spring.GetPlayerInfo(leader, false) -- (gone from the game: still a team to give to)
			end
			if name then
				if anonymous then
					name = "TEAMMATE " .. number
				end
				local r, g, b = Spring.GetTeamColor(teamID)
				list[#list + 1] = { teamID = teamID, name = name, color = { r or 1, g or 1, b or 1 } }
			end
		end
	end
	return list
end

local function shareOpen()
	if Spring.GetSpectatingState() then
		note("NOT WHILE SPECTATING")
		return
	end
	if modal then
		return
	end
	local teams = teammates()
	if #teams == 0 then
		note("NO TEAMMATES")
		return
	end
	-- (units selected: they are what is given; none: the resource last given)
	local tab = Spring.GetSelectedUnitsCount() > 0 and 1 or shareLastTab
	share = { index = 1, teams = teams, tab = tab, step = shareLastStep }
	modal = "share"
end

-- the resource the list gives now ("metal", "energy"), nil for units
local function shareResource(s)
	local tab = SHARE_TABS[s.tab]
	return tab ~= "UNITS" and string.lower(tab) or nil
end

-- what A gives the teammate now: the step's share of what this team holds, at most the room in their storage; also
-- what was wanted and their room. Their room ends at their share slider, not the storage's top: BAR's "Prevent
-- Excessive Share" (and "Tax Resource Sharing") take storage * share - current, cut a bigger transfer to that and
-- refuse one when it is 0 (the toast said "GIVING 500 METAL" over a refused transfer)
local function shareAmount(s, team)
	local res = shareResource(s)
	local mine = Spring.GetTeamResources(Spring.GetMyTeamID(), res) or 0
	local want = math.floor(mine * SHARE_STEPS[s.step])
	local theirs, storage, _, _, _, slider = Spring.GetTeamResources(team.teamID, res)
	local room = (theirs and storage) and math.max(0, math.floor(storage * (slider or 1) - theirs)) or want
	return shareRules.amount(want, room), want, room
end

local function shareFmt(n)
	n = math.floor((n or 0) + 0.5)
	if n >= 10000 then
		return string.format("%.1fk", n / 1000)
	end
	return tostring(n)
end

local function shareClose(text, color)
	share, modal = nil, nil
	if text then
		note(text, color) -- (a resource given: in its colour, as its tab)
	end
end

local function shareConfirm()
	local s = share
	local team = s and s.teams[s.index]
	if not team then
		shareClose()
		return
	end
	-- (a spectator now: resigned, or out of the game, with the list open; the engine drops a spectator's share and A
	-- said "GIVING"; the dock's giving checked it, the list only as it opened; review 2026-11-18)
	if Spring.GetSpectatingState() then
		shareClose("NOT WHILE SPECTATING")
		return
	end
	-- (the list is made when it opens: a teammate who died or resigned since was still there, and A said "GIVING"
	-- to a team that takes nothing; the list made again, the pick kept in range)
	local _, _, isDead = Spring.GetTeamInfo(team.teamID, false)
	if isDead then
		local teams = teammates()
		if #teams == 0 then
			shareClose(string.upper(team.name) .. " IS OUT OF THE GAME")
			return
		end
		s.teams, s.index = teams, math.min(s.index, #teams)
		note(string.upper(team.name) .. " IS OUT OF THE GAME")
		return
	end
	if shareRules.away(team.teamID) then -- (the list stays: another teammate may be picked)
		note(string.upper(team.name) .. " IS AWAY: THIS GAME GIVES THEM NOTHING")
		return
	end
	local res = shareResource(s)
	if res then
		local amount, want, room = shareAmount(s, team)
		local what = SHARE_TABS[s.tab]
		if want < 1 then
			shareClose("NO " .. what .. " TO GIVE")
		elseif room < 1 then
			shareClose(string.upper(team.name) .. "'S " .. what .. " STORAGE IS FULL")
		else
			local _, arrives, tax = shareRules.amount(want, room)
			Spring.ShareResources(team.teamID, res, amount)
			shareClose("GIVING " .. shareFmt(arrives) .. " " .. what .. " TO " .. string.upper(team.name)
				.. shareRules.taxWords(tax), SHARE_COLORS[what])
		end
		return
	end
	local units = Spring.GetSelectedUnits()
	if #units == 0 then
		note("SELECT UNITS FIRST, OR RB: METAL / ENERGY") -- (the list stays: RB moves to the resources)
		return
	end
	Spring.ShareResources(team.teamID, "units")
	given[#given + 1] = { units = units, teamID = team.teamID, from = Spring.GetMyTeamID(), at = now() }
	shareClose("GIVING " .. #units .. (#units == 1 and " UNIT TO " or " UNITS TO ") .. string.upper(team.name))
end

-- The portrait dock's giving (bardroid_portrait.lua, Kailil 2026-11-09: a transfer button and a teammate picker,
-- metal and energy sent from the resource panel): the share list's teammates, rules and notes. what: "units",
-- "metal" or "energy"; fraction: of what this team holds (resources)
local function giveTo(teamID, what, fraction)
	-- (only these: a teammate's row tapped just as the dock let the share list go handed nil, and string.upper(nil)
	-- below would have removed the dock with this widget's error; review 2026-11-21)
	if what ~= "units" and what ~= "metal" and what ~= "energy" then
		return
	end
	local team
	for _, t in ipairs(teammates()) do
		if t.teamID == teamID then
			team = t
		end
	end
	if not team then
		note("OUT OF THE GAME")
		return
	end
	-- (the share list's rules: no gift from a spectator, the engine dropped it with "GIVING" said; none to a team BAR
	-- will not give to; review 2026-11-15)
	if Spring.GetSpectatingState() then
		note("NOT WHILE SPECTATING")
		return
	end
	if shareRules.away(teamID) then
		note(string.upper(team.name) .. " IS AWAY: THIS GAME GIVES THEM NOTHING")
		return
	end
	if what == "units" then
		local units = Spring.GetSelectedUnits()
		if #units == 0 then
			note("SELECT UNITS FIRST")
			return
		end
		Spring.ShareResources(teamID, "units")
		given[#given + 1] = { units = units, teamID = teamID, from = Spring.GetMyTeamID(), at = now() }
		note("GIVING " .. #units .. (#units == 1 and " UNIT TO " or " UNITS TO ") .. string.upper(team.name))
		return
	end
	local WHAT = string.upper(what)
	local mine = Spring.GetTeamResources(Spring.GetMyTeamID(), what) or 0
	local want = math.floor(mine * (fraction or 0.25))
	local theirs, storage, _, _, _, slider = Spring.GetTeamResources(teamID, what)
	local room = (theirs and storage) and math.max(0, math.floor(storage * (slider or 1) - theirs)) or want
	if want < 1 then
		note("NO " .. WHAT .. " TO GIVE")
	elseif room < 1 then
		note(string.upper(team.name) .. "'S " .. WHAT .. " STORAGE IS FULL")
	else
		local amount, arrives, tax = shareRules.amount(want, room)
		Spring.ShareResources(teamID, what, amount)
		note("GIVING " .. shareFmt(arrives) .. " " .. WHAT .. " TO " .. string.upper(team.name) .. shareRules.taxWords(tax),
			SHARE_COLORS[WHAT])
	end
end

-- (units BAR kept: all of them in a game whose rules forbid giving units, BAR's disable_unit_sharing; some or all
-- for its other gadgets: partly built units with "easytax", a teammate at their unit limit. It said "this game does
-- not allow giving units" only when none went, for any reason, and nothing when some stayed, 2026-11-08)
local function shareCheck()
	for i = #given, 1, -1 do
		local g = given[i]
		local t = Spring.DiffTimers(now(), g.at)
		if g.checkNow or t >= SHARE_CHECK_SECONDS then
			local moved, kept = 0, 0
			for _, unitID in ipairs(g.units) do
				local team = Spring.GetUnitTeam(unitID) -- (nil: gone meanwhile, counted neither way)
				if team == g.teamID then
					moved = moved + 1
				elseif team == g.from then
					kept = kept + 1
				end
			end
			-- (none gone yet: the share may still be on its way; said once SHARE_WAIT_SECONDS have passed)
			if kept == 0 or moved > 0 or g.checkNow or t >= SHARE_WAIT_SECONDS then
				table.remove(given, i)
				local rule = (Spring.GetModOptions() or {}).disable_unit_sharing
				if kept == 0 then -- luacheck: ignore 542
				elseif moved > 0 then
					note("GAVE " .. moved .. " OF " .. (moved + kept) .. ": THIS GAME KEPT THE REST", nil, 2.5)
				elseif rule == true or rule == "1" or rule == "true" then
					note("THIS GAME DOES NOT ALLOW GIVING UNITS", nil, 2.5)
				else
					note("NOT GIVEN: PARTLY BUILT, OR THEIR UNIT LIMIT", nil, 2.5)
				end
			end
		end
	end
end

local function shareDraw(vsx, vsy)
	local s = share
	local font = WG.fonts and WG.fonts.getFont()
	if not font then
		return
	end
	local size = style.size(0.022)
	local small = math.max(10, math.floor(size * 0.78))
	local rowH, pad = math.floor(size * 1.9), math.floor(size * 0.8)
	local count = Spring.GetSelectedUnitsCount()
	local res = shareResource(s)
	local tabName = SHARE_TABS[s.tab]
	local accent = SHARE_COLORS[tabName]
	local function text(str, x, y, sz, c, a, opts)
		font:Begin()
		font:SetOutlineColor(0, 0, 0, 0.8 * (a or 1))
		font:SetTextColor(c[1], c[2], c[3], a or 1)
		font:Print(str, x, y, sz, opts or "o")
		font:End()
	end
	-- the widths: the tab strip (LB, the three, RB), the teammates' rows (name, their amount, its bar), the amount line
	local labels = {}
	for i, t in ipairs(SHARE_TABS) do
		labels[i] = (t == "UNITS" and count > 0) and (t .. " " .. count) or t
	end
	local tabPad, gap = math.floor(size * 0.7), math.floor(size * 0.35)
	local chipH = math.floor(math.floor(size * 1.45) * 0.7) -- (style.chip's: LB and RB)
	local chipW = math.ceil((style.bold() or font):GetTextWidth("RB") * chipH * 0.5 + chipH * 0.7)
	local tabsW = chipW * 2 + gap * 4
	for _, l in ipairs(labels) do
		tabsW = tabsW + math.ceil(font:GetTextWidth(l) * small / 0.76) + tabPad
	end
	local nameW = 0
	for _, team in ipairs(s.teams) do
		nameW = math.max(nameW, font:GetTextWidth(string.upper(team.name)) * size)
	end
	local barW, numW = math.floor(size * 5), math.ceil(font:GetTextWidth("00.0k") * small)
	local rowW = nameW + pad * 2 + (res and (numW + pad * 0.5 + barW) or 0)
	-- (the amount's five steps as the dock's buttons, "100%" at 76 % of one at most)
	local stepsW = 5 * math.ceil(font:GetTextWidth("100%") * small / 0.7) + 4 * gap + size * 3
	local lineW = math.max(font:GetTextWidth("SEND 00.0k ENERGY") * size + size * 3, stepsW)
	local w = math.ceil(math.max(rowW, tabsW, lineW, size * 14)) + pad * 2
	local tabRowH, amountH = math.floor(rowH * 1.15), res and math.floor(rowH * 1.6) or rowH
	-- the teammates' rows on the screen: closer together, then a window that follows the one picked (a co-op game
	-- against Raptors puts ten or more on one team: the list ran off the screen, tabs and keys with it)
	local fixedH = tabRowH + amountH + rowH + pad
	local nTeams = #s.teams
	local bar = WG.topbar and WG.topbar.GetPosition and WG.topbar.GetPosition() -- (under BAR's top bar: its [2] is its foot)
	local top = math.floor(bar and bar[2] or vsy * 0.92)
	-- (upright, above the portrait dock: 15 teammates ran down over it; the list in the middle of the game above it)
	local P = WG.BarDroidPortrait
	local dock = P and P.active and P.active() and P.dock and P.dock()
	local floorY = dock and math.floor(dock[4]) or 0
	-- (a long list leaves a note's height under it: "NOT GIVEN: PARTLY BUILT, OR THEIR UNIT LIMIT" lay across the
	-- dock's top edge and its resource bars, pad-test -Share's screenshots 2026-11-16)
	local noteRoom = math.floor(style.size(0.02) * 2) + style.size(0.008, 3) * 2
	local roomH = top - floorY - pad * 2 - fixedH - noteRoom
	local teamH = math.max(math.floor(size * 1.35), math.min(rowH, math.floor(roomH / nTeams)))
	local shown = math.max(1, math.min(nTeams, math.floor(roomH / teamH)))
	local first = math.max(1, math.min(s.index - math.floor((shown - 1) / 2), nTeams - shown + 1))
	local nameSize = math.min(size, math.floor(teamH / 1.9 + 0.5))
	local h = fixedH + teamH * shown
	-- (centred over the room left above the note's: centred over all of it, half the note's room went above the list
	-- and a note under a full list overlapped its last row by a few pixels; review 2026-11-16)
	local midY = (top + floorY + noteRoom) / 2
	local x0, y1 = math.floor(vsx / 2 - w / 2), math.min(math.floor(midY + h / 2), top - pad)
	-- (right of the unit info panel, bottom left, when the list reaches down past its top: 15 teammates ran over its
	-- right edge; dev phone, pad-test -Share 2026-11-11)
	local lay = WG.BarDroidLayout
	local ix0, iy0, ix1, iy1
	if lay and lay.rect then
		ix0, iy0, ix1, iy1 = lay.rect("info")
	end
	-- (only while it shows: with nothing picked it draws nothing, and the list stood 94 pixels right of the screen's
	-- middle, of the note under it too, beside an empty corner; pad-test -Share sideways, dev phone 2026-11-17)
	local info = WG.info
	local infoShows = not (info and info.getIsShowing) or info.getIsShowing()
	if infoShows and ix1 and y1 - h < iy1 and y1 > iy0 and x0 < ix1 and x0 + w > ix0 then
		x0 = math.max(0, math.min(math.floor(ix1 + pad), math.floor(vsx - w - pad)))
	end
	shareRect = { x0, y1 - h, x0 + w, y1, first, shown, top, floorY }
	-- (as the pad's other panels, BAR's opacity: at 0.8 of it, 0.64, the commander's name and the metal spots' rings lay
	-- between the tabs and the rows, BAR's GUI blur being off on phones; pad-test -Share's screenshots 2026-11-17. The
	-- battle still shows faintly)
	-- (and at BAR's 0.8 the commander's name tag still read through a row, "Phone" over "PLAYER 7", pad-test -Share's
	-- screenshots 2026-11-19: the list, read row by row, at least 0.92)
	style.panel(x0, y1 - h, x0 + w, y1, 1, 0.92)

	-- the tab strip: LB [UNITS] [METAL] [ENERGY] RB, as the dock's buttons (2026-11-23: one look with it): the one given in
	-- BAR's gold, each with its colour along its foot
	local tabH = math.floor(size * 1.45)
	local ty = math.floor(y1 - tabRowH / 2 - tabH / 2)
	local tx = math.floor(x0 + (w - tabsW) / 2)
	local function chip(label)
		local cw = style.chip(tx, math.floor(ty + tabH * 0.15), math.floor(tabH * 0.7), label, 0.95)
		tx = tx + math.max(cw, chipW) + gap
	end
	chip("LB")
	for i, l in ipairs(labels) do
		local tw = math.ceil(font:GetTextWidth(l) * small / 0.76) + tabPad
		local c = SHARE_COLORS[SHARE_TABS[i]]
		local on = i == s.tab
		style.button(tx, ty, tx + tw, ty + tabH, on and style.LIT or nil)
		local e = math.max(2, math.floor(tabH * 0.07))
		gl.Color(c[1], c[2], c[3], on and 0.95 or 0.6)
		gl.Rect(tx + e * 3, ty + e, tx + tw - e * 3, ty + e * 2)
		gl.Color(1, 1, 1, 1)
		style.words(l, tx, ty + e, tx + tw, ty + tabH, small, on and style.TEXT or style.SOFT, 1)
		tx = tx + tw + gap
	end
	chip("RB")

	-- the teammates as the dock's teammate picker has them (its SEND's rows): a button each, the name in capitals, their
	-- colour along its foot; the one picked in BAR's gold; for a resource, how much of it they hold (a bar of their storage)
	for k = 1, shown do
		local team = s.teams[first + k - 1]
		local yr = y1 - tabRowH - teamH * k
		local c = team.color
		local picked = first + k - 1 == s.index
		local rx0, ry0, rx1, ry1 = x0 + math.floor(pad * 0.4), yr + 2, x0 + w - math.floor(pad * 0.4), yr + teamH - 2
		style.button(rx0, ry0, rx1, ry1, picked and style.LIT or nil)
		local cb = math.max(3, math.floor((ry1 - ry0) * 0.07))
		gl.Color(c[1], c[2], c[3], 0.95)
		gl.Rect(rx0 + 8, ry0 + cb, rx1 - 8, ry0 + cb * 2)
		gl.Color(1, 1, 1, 1)
		text(string.upper(team.name), x0 + pad, yr + (teamH - nameSize) / 2 + nameSize * 0.2, nameSize, style.TEXT, 1)
		if res then
			local theirs, storage, _, _, _, slider = Spring.GetTeamResources(team.teamID, res)
			local frac = (theirs and storage and storage > 0) and math.min(1, theirs / storage) or 0
			local bx1 = x0 + w - pad
			local bx0 = bx1 - barW
			local bh = math.max(3, math.floor(size * 0.32))
			local by = math.floor(yr + teamH / 2 - bh / 2)
			local fl, cs = WG.FlowUI, math.floor(bh / 2)
			if fl and fl.Draw and fl.Draw.RectRound then
				-- (as the dock's resource bars: a dark outlined track, the fill shaded from its foot with a gloss on its top
				-- half; it was two flat strips, pad-test -Share's screenshots 2026-11-18)
				local rr = fl.Draw.RectRound
				rr(bx0 - 1, by - 1, bx1 + 1, by + bh + 1, cs + 1, 1, 1, 1, 1, { 0, 0, 0, 0.6 }, { 0, 0, 0, 0.6 })
				rr(bx0, by, bx1, by + bh, cs, 1, 1, 1, 1, { 0.05, 0.05, 0.06, 0.9 }, { 0.12, 0.12, 0.13, 0.9 })
				if frac > 0 then
					local fx = bx0 + math.max(bh, (bx1 - bx0) * frac)
					rr(bx0, by, fx, by + bh, cs, 1, 1, 1, 1, { accent[1] * 0.55, accent[2] * 0.55, accent[3] * 0.55, 0.95 },
						{ accent[1], accent[2], accent[3], 0.95 })
					gl.Blending(GL.SRC_ALPHA, GL.ONE)
					rr(bx0, by + bh / 2, fx, by + bh, cs, 1, 1, 0, 0, { 1, 1, 1, 0 }, { 1, 1, 1, 0.18 })
					gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
				end
			else
				style.fill(bx0, by, bx1, by + bh, { 0.08, 0.08, 0.09 }, 0.85, cs)
				if frac > 0 then
					style.fill(bx0, by, bx0 + math.max(bh, (bx1 - bx0) * frac), by + bh, accent, 0.95, cs)
				end
			end
			-- (their share slider: a mark where their room ends, what BAR lets in; in BAR's share red, as the dock's
			-- resource bar and BAR's top bar show it (Kailil, 2026-11-17, of the dock's: "red line as the share value"),
			-- at the bar's end too; it was a white tick, left out at the top)
			if slider then
				local sx = math.floor(bx0 + (bx1 - bx0) * math.max(0, math.min(1, slider)))
				sx = math.max(bx0 + 2, math.min(bx1 - 2, sx))
				style.fill(sx - 3, by - 4, sx + 3, by + bh + 4, { 0, 0, 0 }, 0.6)
				style.fill(sx - 2, by - 3, sx + 2, by + bh + 3, { 0.85, 0, 0 }, 1)
			end
			text(shareFmt(theirs), bx0 - pad * 0.5, yr + teamH / 2 - small * 0.36, small, style.TEXT, 0.75, "ro")
		end
	end
	-- (rows out of the window: a small arrow at its top or bottom edge)
	local function more(y, dir)
		local t = math.floor(size * 0.3)
		gl.Color(1, 1, 1, 0.8)
		gl.BeginEnd(GL.TRIANGLES, function()
			gl.Vertex(x0 + w / 2, y + dir * t)
			gl.Vertex(x0 + w / 2 - t * 1.3, y)
			gl.Vertex(x0 + w / 2 + t * 1.3, y)
		end)
	end
	if first > 1 then
		more(y1 - tabRowH - math.floor(size * 0.32), 1)
	end
	if first + shown - 1 < nTeams then
		more(y1 - tabRowH - teamH * shown + math.floor(size * 0.32), -1)
	end

	-- what A gives: the units selected, or the amount (D-pad left / right: a tenth to all of it) as words and steps
	local ya = y1 - tabRowH - teamH * shown - amountH
	local mid = x0 + w / 2
	-- (A able to give: else its key and GIVE dimmed, A then only says why not; they stood lit over "NO UNITS SELECTED",
	-- pad-test -Share screenshot 2026-11-19)
	local canGive = not res and count > 0
	if res then
		local amount, want, room = shareAmount(s, s.teams[s.index])
		local line, lc
		lc = accent
		if want < 1 then
			line, lc = "NO " .. tabName .. " TO SEND", style.SOFT
		elseif room < 1 then
			line, lc = "THEIR " .. tabName .. " STORAGE IS FULL", { 1, 0.45, 0.35 }
		elseif amount < want then
			line = "SEND " .. shareFmt(amount) .. " " .. tabName .. " (ALL THEY CAN TAKE)"
		else
			-- (the dock's words: its SEND METAL, SEND ENERGY; the share as its step buttons below say it)
			line = "SEND " .. shareFmt(amount) .. " " .. tabName
		end
		-- (within the panel: "GIVE 300 METAL (ALL THEY HAVE ROOM FOR)" ran past both its edges, dev phone 2026-11-08)
		local ls = math.min(size, size * (w - pad * 2) / math.max(1, font:GetTextWidth(line) * size))
		text(line, mid, ya + amountH * 0.62 + (size - ls) * 0.36, ls, lc, 1, "co")
		-- the steps as the dock's teammate picker has them (10%, 25%, 50%, 100% buttons, the one in use in BAR's gold;
		-- the pad's five, D-pad left and right, between two arrows); dimmed while nothing can go (none to give, their
		-- storage full: the strip still lit gold under a red "STORAGE IS FULL" read as a choice that mattered, pad-test
		-- -Share screenshot 2026-11-18)
		local idle = want < 1 or room < 1
		canGive = not idle
		local tri = math.floor(size * 0.45)
		local sh = math.floor(amountH * 0.42)
		local sy = math.floor(ya + amountH * 0.08)
		local function arrow(x, dir)
			local a = (dir < 0 and s.step > 1 or dir > 0 and s.step < #SHARE_STEPS) and (idle and 0.35 or 0.95) or 0.3
			gl.Color(1, 1, 1, a)
			gl.BeginEnd(GL.TRIANGLES, function()
				gl.Vertex(x + dir * tri, sy + sh / 2)
				gl.Vertex(x, sy + sh / 2 + tri * 0.8)
				gl.Vertex(x, sy + sh / 2 - tri * 0.8)
			end)
			gl.Color(1, 1, 1, 1)
		end
		local sx0, sx1 = x0 + pad + tri * 2, x0 + w - pad - tri * 2
		arrow(x0 + pad * 0.5 + tri, -1)
		arrow(x0 + w - pad * 0.5 - tri, 1)
		local n = #SHARE_STEPS
		local bw = math.floor((sx1 - sx0 - gap * (n - 1)) / n)
		for k = 1, n do
			local bx = sx0 + (k - 1) * (bw + gap)
			local on = k == s.step
			style.button(bx, sy, bx + bw, sy + sh, on and not idle and style.LIT or nil, idle and 0.5 or 1)
			style.words(math.floor(SHARE_STEPS[k] * 100 + 0.5) .. "%", bx, sy, bx + bw, sy + sh, small,
				idle and style.DIM or on and style.TEXT or style.SOFT, 1)
		end
	elseif count > 0 then -- (the dock's word for units: its TRANSFER)
		text("TRANSFER " .. count .. (count == 1 and " UNIT" or " UNITS"), mid,
			ya + (amountH - size) / 2 + size * 0.14, size, accent, 1, "co")
	else -- (as the count reads; A's note says what to do: "SELECT UNITS FIRST" here repeated it under the note; the dock
		-- says "No units picked")
		text("NO UNITS PICKED", mid, ya + (amountH - size) / 2 + size * 0.14, size, style.DIM, 1, "co")
	end

	-- the keys: A sends (the dock's SEND, TRANSFER), B cancels; centred, as the tabs and the amount above them (at the
	-- left they read as stray)
	local key = math.floor(size * 1.2)
	-- (in the middle of their band, rowH + pad under the amount: half a pad over the panel's foot they sat low, a wide
	-- empty band over them; dev phone screenshots 2026-11-12)
	local hy = math.floor(y1 - h + (rowH + pad - key) / 2)
	local hs = size * 0.8
	local give = res and "SEND" or "TRANSFER"
	local keysW = 2 * (key + pad * 0.4) + (font:GetTextWidth(give) + font:GetTextWidth("CANCEL")) * hs + pad
	local hx = math.floor(math.max(x0 + pad, mid - keysW / 2))
	style.key(hx, hy, key, "A", canGive and 0.95 or 0.4)
	font:Begin()
	font:SetOutlineColor(0, 0, 0, canGive and 0.8 or 0.35)
	font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], canGive and 0.85 or 0.4)
	hx = hx + key + pad * 0.4
	font:Print(give, hx, hy + key / 2 - hs * 0.36, hs, "o")
	hx = hx + font:GetTextWidth(give) * hs + pad
	font:End()
	style.key(hx, hy, key, "B", 0.95)
	font:Begin()
	font:SetOutlineColor(0, 0, 0, 0.8)
	font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 0.85)
	font:Print("CANCEL", hx + key + pad * 0.4, hy + key / 2 - hs * 0.36, hs, "o")
	font:End()
	gl.Color(1, 1, 1, 1)
end

local ACTIONS = {
	pad_build = function() -- RB
		ordersEnd()
		buildMenu("build")
	end,
	pad_orders = function() -- Back + RB
		if orders then
			ordersEnd()
			return
		end
		if buildFocus() then
			buildMenu("build")
		end
		ordersGo(1)
		if not orders then
			note("NO ORDERS")
		end
	end,
	pad_select = function() -- A on the order menu
		if orders then
			ordersSelect()
		end
	end,
	area_on = function()
		local _, _, _, shift = Spring.GetModKeyState()
		area.on, area.units, area.count, area.shift = true, {}, 0, shift
		area.keep = shift and Spring.GetSelectedUnits() or {}
		if not shift then
			Spring.SelectUnitArray({})
		end
		areaUpdate()
	end,
	area_off = function()
		area.on, area.radial = false, false
	end,
	area_cancel = function() -- B: the selection as it was before
		area.on, area.radial = false, false
		Spring.SelectUnitArray(area.keep)
	end,
	area_filter_open = function() -- X held in the area select: the filter radial
		area.radial, area.highlight = area.on, nil
	end,
	area_filter_pick = function() -- X let go: the side the stick picked (none: the filter stays)
		if area.radial and area.highlight then
			area.filter = area.highlight
			note("FILTER: " .. string.upper(area.filter), BLUE)
			areaUpdate(true)
		end
		area.radial, area.highlight = false, nil
	end,
	area_filter_close = function()
		area.radial, area.highlight = false, nil
	end,
	grid_on = function() -- LB with a building picked (PadGame holds Shift+Alt: BAR's grid)
		note("GRID", BLUE)
	end,
	build_placed = function() -- X placed the building: the engine lets go of it as Shift comes up, and X keeps it
		local b = WG.bardroidBuildmenu
		if b and b.droidSpot then
			b.droidSpot(nil, nil, true)
		end
	end,
	build_exit = function() -- a grid placed with A: the building put away, as v0.8.5's A does
		if pregameBuild() then
			pregamePutAway()
		else
			local _, id = Spring.GetActiveCommand()
			if id and id < 0 then
				Spring.SetActiveCommand(0)
			end
		end
	end,
	area_bigger = function()
		area.target = math.min(AREA_MAX, area.target + (area.target >= 160 and 80 or 20))
		note("AREA " .. area.target)
	end,
	area_smaller = function()
		area.target = math.max(AREA_MIN, area.target - (area.target > 160 and 80 or 20))
		note("AREA " .. area.target)
	end,
	pad_page_next = function() -- RB / LB on the build menu: its pages (Kailil: "pressing RB or LB cycles the tabs")
		buildMenu("pagenext")
	end,
	pad_page_prev = function()
		buildMenu("pageprev")
	end,
	pad_back = function()
		if orders then
			ordersEnd()
		else
			buildMenu("back")
		end
	end,
	slow_pan = function() -- Back while placing a building (v0.8.5): the pan at 30% until the building is put away
		WG.BarDroidPadSlowPan = not WG.BarDroidPadSlowPan
		note(WG.BarDroidPadSlowPan and "SLOW PAN" or "FULL PAN")
	end,
	cancel = cancel,
	commander = commander,
	idle_mobile_next = function() idleMobile(1) end,
	idle_mobile_prev = function() idleMobile(-1) end,
	idle_type = idleOfType,
	bookmark_store = function()
		bookmark = Spring.GetCameraState()
		note("BOOKMARK SET")
	end,
	bookmark_recall = function()
		if bookmark then -- (the place and the zoom; the tilt stays as it is, Kailil 2026-10-30)
			bookmark.rx = Spring.GetCameraState().rx
			Spring.SetCameraState(bookmark, 0.4)
		else
			note("LT + UP SETS A BOOKMARK")
		end
	end,
	rotate_left = function() Spring.SendCommands("buildfacing dec") end,
	rotate_right = function() Spring.SendCommands("buildfacing inc") end,
	walls_toggle = function() -- (a GRID held: the PLACE panel's WALLS, RtsTouch.gridTap; bardroid_walls.lua)
		local W = WG.BarDroidWalls
		if W and W.set and W.on then
			W.set(not W.on())
		end
	end,
	spacing_up = function() Spring.SendCommands("buildspacing inc") end,
	spacing_down = function() Spring.SendCommands("buildspacing dec") end,
	lb_a = function() -- builders: repair (picked: A on a unit, or drag an area); else attack the enemy there, or fight
		if hasBuilder() then
			pickOrder(CMD.REPAIR, "repair", "REPAIR: A")
			return
		end
		local unitID = aim()
		if enemyAt(unitID) then
			orderAt(CMD.ATTACK, "attack", true)
		else
			orderAt(CMD.FIGHT, "fight", false)
		end
	end,
	lb_x = function() -- builders: reclaim (picked); else attack there
		if hasBuilder() then
			pickOrder(CMD.RECLAIM, "reclaim", "RECLAIM: A")
			return
		end
		orderAt(CMD.ATTACK, "attack", true)
	end,
	lb_y = function()
		orderAt(CMD.PATROL, "patrol", false)
	end,
	path_fight = function() -- LB + A held: picked, the app's drag draws it (BAR's formation widget gives the path)
		pickOrder(CMD.FIGHT, "fight", "FIGHT PATH")
	end,
	path_patrol = function() -- LB + Y held
		pickOrder(CMD.PATROL, "patrol", "PATROL PATH")
	end,
	path_end = function() -- the drag let go: BAR's formation widget has the path, and leaves the order picked for many units
		Spring.SetActiveCommand(0)
	end,
	selfd = function() -- Back + R3 + L3 held, as v0.8.5's (given again: called off)
		if #Spring.GetSelectedUnits() > 0 then
			Spring.SetActiveCommand("selfd") -- (as BAR's own hotkey gives it: any game allows that)
			note("SELF DESTRUCT")
		end
	end,
	ping = function() -- RB + D-pad up held: a ping in the middle of the screen, as BAR's own
		local _, pos = aim()
		if pos then
			Spring.MarkerAddPoint(pos[1], pos[2], pos[3], "")
			note("PING")
		end
	end,
	ping_look = function() -- RB + D-pad up: the camera to the last ping from someone else, then the ones before it
		pingLook()
	end,
	select_combat = function() -- RB + D-pad down
		selectCombat(myUnits(), "COMBAT UNITS")
	end,
	select_combat_screen = function() -- RB + D-pad right
		selectCombat(Spring.GetVisibleUnits(Spring.GetMyTeamID(), nil, true) or {}, "ON SCREEN")
	end,
	pad_speed = function() -- Back + Y: the path speed tuner
		if WG.BarDroidPadSpeed then
			WG.BarDroidPadSpeed.toggle()
		end
	end,
	fp_toggle = function() -- LB + L3 held, or B in first person (bardroid_padfp.lua)
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.toggle()
		end
	end,
	fp_fire_on = function() -- RT in first person
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.fire(true)
		end
	end,
	fp_fire_off = function()
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.fire(false)
		end
	end,
	lb_b = function() -- stop; factories selected: stopped and their whole queue cleared (Kailil, 2026-10-29)
		if clearFactories() then
			return
		end
		Spring.SetActiveCommand("stop")
		note("STOP")
	end,
	lb_b2 = function()
		Spring.SetActiveCommand("repeat")
		note("REPEAT")
	end,
	lb_b_hold = function()
		Spring.SetActiveCommand("wait")
		note("WAIT")
	end,
	queue_remove_first = function() queueRemove(false) end,
	queue_remove_last = function() queueRemove(true) end,
	dgun = dgunEnter, -- LB + RB + R3, or Back + R3 (v0.8.5's D-gun mode)
	dgun_fire = dgunFire, -- RT in it
	dgun_auto = function() -- the portrait dock's FIRE held and swiped right: full auto on (dgunAuto)
		if dgun and not dgun.auto then
			if not unitControl() then -- (the host forbids widgets' orders: no aiming and firing on its own, dgunAuto)
				note("AUTO D-GUN: THIS HOST FORBIDS IT")
				return
			end
			dgun.auto, dgun.autoAt, dgun.autoOn = true, nil, now()
			note("AUTO D-GUN ON")
		end
	end,
	dgun_auto_off = function() -- the dock's AUTO swiped left (Kailil, 2026-11-10)
		if dgun and dgun.auto then
			dgun.auto, dgun.target = false, nil
			note("AUTO D-GUN OFF")
		end
	end,
	dgun_cancel = function() -- B in it
		dgunExit("D-GUN OFF")
	end,
	share_open = shareOpen, -- LB + D-pad up tapped, then held
	share_up = function()
		if share then
			share.index = (share.index - 2) % #share.teams + 1
		end
	end,
	share_down = function()
		if share then
			share.index = share.index % #share.teams + 1
		end
	end,
	-- LB / RB on the list: what is given (units, metal, energy); D-pad left / right: how much of a resource
	share_tab_prev = function()
		if share then
			share.tab = (share.tab - 2) % #SHARE_TABS + 1
			shareLastTab = share.tab > 1 and share.tab or shareLastTab
		end
	end,
	share_tab_next = function()
		if share then
			share.tab = share.tab % #SHARE_TABS + 1
			shareLastTab = share.tab > 1 and share.tab or shareLastTab
		end
	end,
	share_less = function()
		if share and shareResource(share) then
			share.step = math.max(1, share.step - 1)
			shareLastStep = share.step
		end
	end,
	share_more = function()
		if share and shareResource(share) then
			share.step = math.min(#SHARE_STEPS, share.step + 1)
			shareLastStep = share.step
		end
	end,
	voice_on = function() -- speak to chat (the app's VoiceChat: a three-finger tap, or LB held + RB twice) is listening
		voiceNote(nil)
	end,
	-- while it listens, D-pad left / right or a sideways swipe: the chat's channel (allies, everyone, spectators), kept
	-- (Kailil, 2026-11-06: "switching the channel permanently. Don't extend the time"): the words go where it is then
	voice_channel_next = function()
		voiceNote(1)
	end,
	voice_channel_prev = function()
		voiceNote(-1)
	end,
	voice_on_ping = function() -- ... for a ping's label (LB held + RB three times)
		note(VOICE_PING_NOTE, nil, VOICE_SECONDS)
		voiceToast = true
	end,
	voice_off = function() -- (done: what was said goes to chat, bardroid_chat.lua, or to the ping, voicePing)
		if voiceToast and toast == lastNote then
			toast = nil
		end
		voiceToast = false
	end,
	voice_ping_here = function() -- (LB held + RB three times: where the ping goes, the middle now)
		local _, pos = aim()
		voicePingAt = pos and { pos[1], pos[2], pos[3], at = now() } or nil
	end,
	voice_none = function()
		note("NO SPEECH RECOGNITION ON THIS PHONE", nil, 2.5)
	end,
	voice_nomic = function() -- (the microphone not allowed; after two "Don't allow" Android no longer asks)
		note(VOICE_NOMIC_NOTE, nil, 4)
	end,
	voice_nonet = function() -- (said and lost: the recognizer needed a connection)
		note(VOICE_NONET_NOTE, nil, 4)
	end,
	share_confirm = shareConfirm, -- A on the list
	share_cancel = function() -- B on it
		shareClose()
	end,
	mouse_toggle = function() -- Back + Start (the app keeps the same switch)
		mouseMode = not mouseMode
		note(freePointer() and "MOUSE ON" or "MOUSE OFF")
	end,
	group_list_on = function() -- Start held: the group list
		groupList.held = true
	end,
	group_list_off = function()
		if groupList.held then
			groupList.held, groupList.untilAt = false, now()
		end
	end,
}

-- control groups: group_<recall|assign|look|clear|show>_<1..9>. BAR's own system with other keys (Kailil, 2026-10-30: "it
-- should literarly just be the vanilla system just different UI and keybindings"): the engine's group commands and BAR's
-- autogroup, nothing kept here. Recall: "group select", the camera stays. Assign: BAR's select of the selection's types
-- on the whole map (a double tap's), "group set", and the autogroup so that those to come join. Look: "group focus".
-- Clear: the group selected, taken out of its autogroup and "group unset", the selection as it was. The group list
-- (v0.8.5's: a box for each group that has units, the slot in use too) shows while Start or Back is held and for a moment
-- after each group action.
local function groupUnits(n)
	local units = {}
	for _, unitID in ipairs(Spring.GetGroupUnits(n) or {}) do
		if not Spring.GetUnitIsDead(unitID) then
			units[#units + 1] = unitID
		end
	end
	return units
end
local function group(kind, n)
	n = tonumber(n)
	groupList.slot, groupList.untilAt = n, now()
	local autogroup = WG.autogroup
	if kind == "recall" then
		if #groupUnits(n) > 0 then
			Spring.SendCommands("group select " .. n)
			note("GROUP " .. n)
		else
			note("GROUP " .. n .. " EMPTY")
		end
	elseif kind == "assign" then
		if Spring.GetSelectedUnitsCount() == 0 then
			note("SELECT A UNIT")
			return
		end
		Spring.SendCommands("select AllMap+_InPrevSel+_ClearSelection_SelectAll+")
		Spring.SendCommands("group set " .. n)
		if autogroup and autogroup.addCurrentSelectionToAutogroup then
			autogroup.addCurrentSelectionToAutogroup(n)
		end
		note("GROUP " .. n .. " SET: " .. #groupUnits(n))
	elseif kind == "look" then
		if #groupUnits(n) > 0 then
			Spring.SendCommands("group focus " .. n .. " 0.3")
			note("GROUP " .. n)
		else
			note("GROUP " .. n .. " EMPTY")
		end
	elseif kind == "clear" then
		if #groupUnits(n) == 0 then -- (what comes next would work on the selection, in other groups)
			note("GROUP " .. n .. " EMPTY")
			return
		end
		local keep = Spring.GetSelectedUnits()
		Spring.SendCommands("group select " .. n)
		if autogroup and autogroup.removeCurrentSelectionFromAutogroup then
			autogroup.removeCurrentSelectionFromAutogroup()
		end
		Spring.SendCommands("group unset")
		Spring.SelectUnitArray(keep)
		note("GROUP " .. n .. " CLEARED")
	else
		note("GROUP " .. n)
	end
end

-- (the groups that have units, in key order 1..9, 0; the slot in use as well while it is empty)
local function groupSlots()
	local slots = {}
	for _, n in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }) do
		local units = groupUnits(n)
		if #units > 0 or n == groupList.slot then
			slots[#slots + 1] = { n = n, units = units }
		end
	end
	return slots
end

-- (where the interface at the bottom of the screen ends: upright the touch dock's top (the pad's panels lay over it),
-- else the order menu's, else a tenth of the screen)
local function bottomInterfaceTop(vsy)
	local P = WG.BarDroidPortrait
	local dock = P and P.active and P.active() and P.dock and P.dock()
	if dock then
		return math.floor(dock[4])
	end
	local o = WG.ordermenu
	if o and o.getPosition and o.getIsShowing and o.getIsShowing() then
		local _, y = o.getPosition()
		if y then
			return math.floor(y * vsy)
		end
	end
	return math.floor(vsy * 0.1)
end

-- The group strip, as the touch dock's groups row (bardroid_portrait.lua drawGroups; 2026-11-23, one look with it): one
-- of BAR's panels in the middle just above the interface at the bottom, a tile for each group with units, as tall as the
-- dock's (the picture of its most numerous type, its number in gold on a dark badge at the top left, how many at the
-- bottom right, in bold), the slot in use as the dock's group in use (the picture closer, BAR's gold light) and outlined
-- in gold, the pad's place; empty, an open place with its number, or with units picked the dock's "+ NEW": Start + D-pad
-- left held puts them there
local function groupBadge(bold, n, x0, y1, h, alpha)
	local ns, pad = h * 0.26, math.max(2, math.floor(h * 0.06))
	local bx0, by1 = x0 + pad * 0.5, y1 - pad * 0.5
	local bx1, by0 = bx0 + bold:GetTextWidth(tostring(n)) * ns + 2 * pad, y1 - h * 0.36
	local f = WG.FlowUI and WG.FlowUI.Draw
	local c = style.fade1
	c[1], c[2], c[3], c[4] = 0, 0, 0, 0.62 * alpha
	if f and f.RectRound then
		f.RectRound(bx0, by0, bx1, by1, pad, 1, 1, 1, 1, c, c)
	else
		gl.Color(0, 0, 0, c[4])
		gl.Rect(bx0, by0, bx1, by1)
	end
	gl.Color(1, 1, 1, 1)
	bold:Begin()
	bold:SetOutlineColor(0, 0, 0, 0.6 * alpha)
	bold:SetTextColor(style.GOLD[1], style.GOLD[2], style.GOLD[3], alpha)
	bold:Print(tostring(n), bx0 + pad, y1 - h * 0.3, ns, "o")
	bold:End()
end
local function drawGroupList(vsx, vsy)
	local shown = groupList.held or (groupList.untilAt and Spring.DiffTimers(now(), groupList.untilAt) < GROUP_LIST_SECONDS)
	if not shown then
		groupList.untilAt = nil
		return
	end
	local alpha = groupList.held and 1 or math.min(1, (GROUP_LIST_SECONDS - Spring.DiffTimers(now(), groupList.untilAt)) / 0.3)
	local slots = groupSlots()
	local D = style.dock()
	local size, gap, pad = D.tile, D.gap, D.pad
	local width = #slots * size + (#slots - 1) * gap
	local x0 = math.floor((vsx - width) / 2)
	local y0 = bottomInterfaceTop(vsy) + pad * 3
	style.panel(x0 - pad, y0 - pad, x0 + width + pad, y0 + size + pad, alpha)
	style.mark("groups", x0 - pad, y0 - pad, x0 + width + pad, y0 + size + pad)
	local bold = style.bold()
	if not bold then
		return
	end
	local picked = Spring.GetSelectedUnitsCount() > 0
	for i, s in ipairs(slots) do
		local x = x0 + (i - 1) * (size + gap)
		local x1, y1 = x + size, y0 + size
		local active = s.n == groupList.slot
		local best, bestN = nil, 0
		if #s.units > 0 then
			for d, c in pairs(Spring.GetGroupUnitsCounts(s.n) or {}) do
				if type(d) == "number" and c > bestN then -- (the counts carry their total as "n")
					best, bestN = d, c
				end
			end
			best = best or Spring.GetUnitDefID(s.units[1])
		end
		if best then
			style.unit(best, x, y0, x1, y1, active, alpha)
			groupBadge(bold, s.n, x, y1, size, alpha)
			bold:Begin()
			bold:SetOutlineColor(0, 0, 0, 0.7 * alpha)
			bold:SetTextColor(1, 1, 1, alpha)
			bold:Print(tostring(#s.units), x1 - 6, y0 + 6, size * 0.2, "ro")
			bold:End()
		elseif active and picked then -- (the dock's + NEW: the next free group for the units picked)
			style.button(x, y0, x1, y1, style.NEW, alpha)
			style.words("+", x, y0 + size * 0.3, x1, y1, size * 0.42, style.GOLD, alpha, true)
			style.words("NEW " .. s.n, x, y0, x1, y0 + size * 0.4, size * 0.25, style.TEXT, alpha, true)
		else
			style.button(x, y0, x1, y1, style.BLANK, alpha)
			groupBadge(bold, s.n, x, y1, size, alpha)
		end
		if active then -- (the pad's place, as the dock outlines its picked tile)
			style.outline(x, y0, x1, y1, style.GOLD, alpha, math.max(2, math.floor(size * 0.04)))
		end
	end
	gl.Color(1, 1, 1, 1)
end

-- The D-gun mode's panel while no dock is up (sideways with the pad; upright the dock shows its own sticks and FIRE):
-- the dock's FIRE (bardroid_portrait.lua drawDgun, 2026-11-23: one look with it): the D-gun's red, AUTO's orange in full
-- auto, a thin bar along its foot while it reloads (white) or the team lacks a shot's energy (amber, the word dimmed);
-- beside it the pad's keys, RT fires, B leaves
local function dgunPanel(vsx, vsy)
	local d = dgun
	local bold = style.bold()
	if not (d and bold) then
		return
	end
	local loaded, energy = 1, 1
	local D = WG.BarDroidPadDgun
	if D and D.ready then
		loaded, energy = D.ready()
		loaded, energy = loaded or 1, energy or 1
	end
	local lacking = energy < 1
	local part = lacking and energy or loaded
	local size = style.size(0.02)
	local pad, gap = style.dock().pad, math.floor(size * 0.6)
	local h = math.floor(size * 2.6)
	local bw = math.floor(h * 3)
	local key = math.floor(size * 1.3)
	local hs = size * 0.85
	local fireW, leaveW = bold:GetTextWidth("FIRE") * hs, bold:GetTextWidth("LEAVE") * hs
	local rtW = math.ceil(bold:GetTextWidth("RT") * key * 0.5 + key * 0.7) -- (style.chip's width)
	-- (the button, two gaps, RT and a fifth of one, FIRE, a gap and a half, B and a fifth, LEAVE, and a gap as a margin)
	local w = math.ceil(bw + gap * 2 + rtW + gap * 0.4 + fireW + gap * 1.5 + key + gap * 0.4 + leaveW + gap)
	local x0 = math.floor((vsx - w) / 2)
	local y0 = bottomInterfaceTop(vsy) + pad * 3
	style.panel(x0 - pad, y0 - pad, x0 + w + pad, y0 + h + pad, 1)
	style.mark("dgunhud", x0 - pad, y0 - pad, x0 + w + pad, y0 + h + pad)
	local x1, y1 = x0 + bw, y0 + h
	style.button(x0, y0, x1, y1, d.auto and style.AUTO or style.RED)
	if part < 1 then
		local e = math.max(2, math.floor(pad * 0.35))
		local bh = math.max(3, math.floor(h * 0.07))
		local bx0, bx1 = x0 + e * 2, x1 - e * 2
		gl.Color(0, 0, 0, 0.45)
		gl.Rect(bx0, y0 + e * 2, bx1, y0 + e * 2 + bh)
		if lacking then
			gl.Color(1, 0.7, 0.2, 0.95)
		else
			gl.Color(1, 1, 1, 0.9)
		end
		gl.Rect(bx0, y0 + e * 2, bx0 + (bx1 - bx0) * part, y0 + e * 2 + bh)
		gl.Color(1, 1, 1, 1)
	end
	style.words(d.auto and "AUTO" or "D-GUN", x0, y0, x1, y1, h * 0.42, lacking and style.LACK or style.WHITE, 1, true)
	local kx, ky = x1 + gap * 2, math.floor(y0 + (h - key) / 2)
	kx = kx + style.chip(kx, ky, key, "RT", 1) + gap * 0.4
	bold:Begin()
	bold:SetOutlineColor(0, 0, 0, 0.7)
	bold:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 0.9)
	bold:Print("FIRE", kx, ky + key / 2 - hs * 0.34, hs, "o")
	bold:End()
	kx = kx + fireW + gap * 1.5
	style.key(kx, ky, key, "B", 0.95)
	bold:Begin()
	bold:SetOutlineColor(0, 0, 0, 0.7)
	bold:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 0.9)
	bold:Print("LEAVE", kx + key + gap * 0.4, ky + key / 2 - hs * 0.34, hs, "o")
	bold:End()
	gl.Color(1, 1, 1, 1)
end

-- v0.8.5's filter radial around the area select's middle: the four filters as the touch dock's FILTERS page has them
-- (2026-11-23, one look with it: its buttons, the filter in use in BAR's gold, the words in its white), the one the
-- stick points at outlined in gold, the pad's place
local FILTER_PLACES = { { "All Mobile", 0, 1, "ALL MOBILE" }, { "Combat", 0, -1, "COMBAT" },
	{ "Builders", -1, 0, "BUILDERS" }, { "Air", 1, 0, "AIR" } }
local function drawFilterRadial(cx, cy, vsy)
	local font = style.font()
	if not font then
		return
	end
	local size = style.size(0.019)
	local w = 0
	for _, p in ipairs(FILTER_PLACES) do
		w = math.max(w, font:GetTextWidth(p[4]) * size)
	end
	-- (the words at 76 % of the button at most, as the dock's)
	w = math.ceil(w / 0.7)
	local h = math.floor(size * 2.3)
	local r = math.max(h * 2.2, vsy * 0.13)
	local edge = math.max(2, math.floor(h * 0.06))
	-- (all four clear of the interface at the bottom and on the screen: over a tall order menu COMBAT lay on its top row;
	-- upright the middle is at the dock's top, COMBAT lay on the dock and BUILDERS and AIR ran off both edges; dev phone
	-- shots 2026-11-24)
	local vsx = Spring.GetViewGeometry()
	local gap = style.dock().gap
	local bottom = bottomInterfaceTop(vsy)
	local down = math.max(math.floor(h * 1.2), math.min(r, cy - bottom - gap * 2 - h / 2))
	cy = math.max(cy, bottom + gap * 2 + h / 2 + down)
	local rx0, ry0, rx1, ry1 = cx, cy, cx, cy
	for _, p in ipairs(FILTER_PLACES) do
		local lit, inUse = area.highlight == p[1], area.filter == p[1]
		local x = math.floor(cx + p[2] * (r * 0.9 + w / 2) - w / 2)
		x = math.max(gap, math.min(vsx - gap - w, x))
		local y = math.floor(cy + p[3] * (p[3] < 0 and down or r) - h / 2)
		style.float(x, y, x + w, y + h, inUse and style.LIT or nil)
		if lit then
			style.outline(x, y, x + w, y + h, style.GOLD, 1, edge)
		end
		style.words(p[4], x, y, x + w, y + h, size, (lit or inUse) and style.TEXT or style.SOFT, 1)
		rx0, ry0, rx1, ry1 = math.min(rx0, x), math.min(ry0, y), math.max(rx1, x + w), math.max(ry1, y + h)
	end
	style.mark("radial", rx0, ry0, rx1, ry1)
	gl.Color(1, 1, 1, 1)
end

local function act(name)
	local action = ACTIONS[name]
	if action then
		action()
		return true
	end
	local kind, n = name:match("^group_(%a+)_(%d)$")
	if kind then
		group(kind, n)
		return true
	end
	local fpOrder = name:match("^fp_order_(%a+)$")
	if fpOrder then -- (first person: the squad's orders)
		if WG.BarDroidPadFP then
			WG.BarDroidPadFP.order(fpOrder)
		end
		return true
	end
	local side = FILTER_SIDES[name:match("^area_filter_(%a+)$") or ""]
	if side then -- (the left stick on the filter radial)
		if area.radial then
			area.highlight = side
		end
		return true
	end
	-- the D-pad on a menu
	local dir = name:match("^pad_(%a+)$")
	if dir == "left" or dir == "right" or dir == "up" or dir == "down" then
		if orders then
			ordersStep(dir == "left" and -1 or dir == "right" and 1 or 0, dir == "up" and -1 or dir == "down" and 1 or 0)
		else
			buildMenu(dir)
		end
		return true
	end
	return false
end

-- The order menu while the pad is the input (Kailil, 2026-10-29, both controller modes): the orders the pad gives with
-- its buttons are hidden (BAR's own switch, WG.ordermenu.setDisabledCmd), so the rest is bigger. BAR saves that switch
-- with its settings, so the names hidden here are kept in springsettings (bardroid_pad_hidden_orders) and shown again
-- at the next start, whatever ended the game; names the player had hidden in BAR's options stay theirs.
local PAD_HIDDEN_ORDERS = { "Stop", "Wait", "Attack", "Repeat", "Move", "Reclaim", "Repair", "Fight", "Patrol" }
local HIDDEN_KEY = "bardroid_pad_hidden_orders"
local ordersHidden, ordersRecovered = nil, false
local function padOrders(want)
	local o = WG.ordermenu
	if not (o and o.getDisabledCmd and o.setDisabledCmd) then
		return
	end
	if not ordersRecovered then -- (a game that ended with them hidden)
		ordersRecovered = true
		local names = Spring.GetConfigString(HIDDEN_KEY, "") or ""
		if names == "" then
			-- all nine hidden and none of them noted: BAR's own save of them hidden at a game's end, before this
			-- widget's Shutdown showed them again (until GetConfigData below did it); the app's doing, not a choice
			local all = true
			for _, name in ipairs(PAD_HIDDEN_ORDERS) do
				all = all and o.getDisabledCmd(name) == true
			end
			names = all and table.concat(PAD_HIDDEN_ORDERS, ",") or ""
		end
		for name in names:gmatch("[^,]+") do
			o.setDisabledCmd({ name, false })
		end
		Spring.SetConfigString(HIDDEN_KEY, "")
	end
	if want == (ordersHidden ~= nil) then
		return
	end
	-- (the app's order menu copy then lays the rest out evenly over the whole menu: bardroid_ordermenu.lua)
	WG.BarDroidPadOrders = want or nil
	if want then
		ordersHidden = {}
		for _, name in ipairs(PAD_HIDDEN_ORDERS) do
			if not o.getDisabledCmd(name) then
				o.setDisabledCmd({ name, true })
				ordersHidden[#ordersHidden + 1] = name
			end
		end
		Spring.SetConfigString(HIDDEN_KEY, table.concat(ordersHidden, ","))
	else
		for _, name in ipairs(ordersHidden) do
			o.setDisabledCmd({ name, false })
		end
		ordersHidden = nil
		Spring.SetConfigString(HIDDEN_KEY, "")
	end
end

-- BAR saves the order menu's switch with every widget's config before any widget's Shutdown (barwidgets.lua
-- widgetHandler:Shutdown), and this widget's config comes first (layer -95000, BAR's order menu 1): the orders are shown
-- again for that save, and hidden again at the next Update if the game goes on (a widget switched on or off). Shown in
-- Shutdown, they had stayed hidden after a game played with the pad, in every game after it, by touch and online too
-- (Kailil, 2026-11-03: the order menu no longer "rearranges"; dev phone: the nine hidden with no pad).
function widget:GetConfigData()
	padOrders(false)
end

-- BAR's info panel (bottom left) shows the unit under the pointer before the selection, and the pad's pointer rests in
-- the middle of the screen: a unit there stayed on the panel, whatever was selected, also after B, until a tap moved the
-- pointer (Kailil, 2026-10-30: it "freezes ... or it doesn't close after I hit B"). While the pad is in use with its
-- pointer in the middle the panel gets no hover (BAR's own WG.info.setCustomHover, there for its picture-in-picture).
local hoverOff = false
local function padHover()
	local info = WG.info
	if not (info and info.setCustomHover and info.clearCustomHover) then
		return
	end
	local want = WG.BarDroidPadOnly == true and not freePointer() and not orders and not buildFocus()
	if want ~= hoverOff then
		hoverOff = want
		if want then
			info.setCustomHover("none", 1)
		else
			info.clearCustomHover()
		end
	end
end

-- QUEUE (Kailil, 2026-10-30: touch "doesn't have a way to add to queue (the shift button)"): a button above the order
-- menu while fingers have units selected, a sticky Shift: on, the app holds Shift, so orders and buildings queue as with
-- BAR's Shift key, until it is tapped off (bardroid_pad.txt "queue 1", RtsTouch). Over any of BAR's interface it answers
-- IsAbove, so a tap on it is a click and not an order.
-- Upright the dock's selection row is the button (Kailil, 2026-11-10: "turn the entire selected unit description into the
-- queue button"): its right two thirds QUEUE, its left third INSERT (bardroid_pad.txt "insert 1": the app holds numpad*
-- for BAR's CommandInsert, QUEUE_KEYS), one or the other; the dock draws both.
local queue = { on = false, rect = nil, insert = false, insertRect = nil, dock = false }
local factoriesPicked -- (only factories picked, for INSERT's key: nil until worked out for this pick, widget:Update)
function widget:SelectionChanged()
	factoriesPicked = nil
end
local function queueShows()
	-- (before the start, nothing picked: on the portrait dock, its selection row is QUEUE then, bardroid_portrait.lua)
	local P = Spring.GetGameFrame() == 0 and WG.BarDroidPortrait
	return queue.on or queue.insert or (WG.BarDroidPadOnly ~= true and WG.BarDroidInput ~= "mouse"
		and not Spring.GetSpectatingState()
		and (Spring.GetSelectedUnitsCount() > 0 or (P and P.active and P.active() and true or false)))
end
local function queueLayout(vsx, vsy)
	if not queueShows() then
		queue.rect, queue.insertRect = nil, nil
		return
	end
	local P = WG.BarDroidPortrait -- (the portrait dock: its selection row, none while nothing is picked)
	queue.dock = P and P.active and P.active() or false
	if queue.dock then
		queue.rect = P.queueRect and P.queueRect()
		queue.insertRect = P.insertRect and P.insertRect()
		return
	end
	queue.insertRect = nil
	-- (no dock, no INSERT button: one left on from the upright dock let go, else every finger order went to the front of
	-- the queues with nothing on the screen to say so or tap off; review 2026-11-16)
	queue.insert = false
	local h, w = style.size(0.036), style.size(0.11)
	local gap = style.size(0.008, 3)
	local x1, y0 = math.floor(vsx * 0.65), math.floor(vsy * 0.16)
	local o = WG.ordermenu
	if o and o.getPosition and o.getIsShowing and o.getIsShowing() then
		local x, y, width = o.getPosition()
		if x and y and width then
			x1, y0 = math.floor((x + width) * vsx), math.floor(y * vsy) + gap
		end
	end
	queue.rect = { x1 - w, y0, x1, y0 + h }
end
local function drawQueue()
	local r = queue.rect
	if not r or queue.dock then
		return
	end
	-- (as the dock's QUEUE (drawQueueZones, 2026-11-23): a button, on it lit gold with a gold edge, its word bold as BAR's
	-- order menu's right under it, gold while on; it stays on until tapped off: plain to see)
	style.float(r[1], r[2], r[3], r[4])
	if queue.on then
		local e = math.max(2, math.floor(style.dock().pad * 0.3))
		gl.Color(1, 0.78, 0.25, 0.14)
		gl.Rect(r[1], r[2], r[3], r[4])
		gl.Color(1, 0.78, 0.25, 0.95)
		gl.Rect(r[1], r[2], r[3], r[2] + e)
		gl.Rect(r[1], r[4] - e, r[3], r[4])
		gl.Rect(r[1], r[2], r[1] + e, r[4])
		gl.Rect(r[3] - e, r[2], r[3], r[4])
		gl.Color(1, 1, 1, 1)
	end
	style.words("QUEUE", r[1], r[2], r[3], r[4], math.floor((r[4] - r[2]) * 0.42), queue.on and style.GOLD or style.TEXT,
		1, true)
	style.mark("queue", r[1], r[2], r[3], r[4])
end
-- (no tables made: IsAbove asks it every frame, and the lists of rects it built were three quarters of this widget's
-- garbage in an idle skirmish, 50 of 66 kB/s on the dev phone; release overhaul item 7, 2026-11-21)
local function inRectXY(r, x, y)
	return r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end
local function inQueueButton(x, y)
	-- (not on the wind's or the tide's box, in the upright dock's selection row since 2026-11-17: a tap there opens its
	-- details, bardroid_portrait.lua, and left QUEUE as it was)
	local P = queue.dock and WG.BarDroidPortrait
	if P and P.windRects then
		local wb, tb = P.windRects()
		if inRectXY(wb, x, y) or inRectXY(tb, x, y) then
			return nil
		end
	end
	if inRectXY(queue.rect, x, y) then
		return "queue"
	elseif inRectXY(queue.insertRect, x, y) then
		return "insert"
	end
	return nil
end
function widget:IsAbove(x, y)
	return inQueueButton(x, y) ~= nil
end
-- Presses before the first draws go no further (2026-10-30): BAR's music widget reads its buttons before it has any, and
-- BAR takes a widget that fails out of the game: no music, no volume sliders. A tap while the game loads comes in just then.
local draws = 0
function widget:MousePress(x, y)
	if draws < 2 then
		return true
	end
	local b = inQueueButton(x, y)
	local P = b and queue.dock and WG.BarDroidPortrait
	if P and P.settling and P.settling() then -- (the dock's row just moved under the finger: not this button's tap)
		Spring.Echo("[bardroid-pad] a tap on QUEUE or INSERT just after the dock changed: dropped") -- (tools)
		return true
	end
	if b == "queue" then -- (each on its own; both on: Shift and Alt held, the app's "alt" line)
		queue.on = not queue.on
		return true
	elseif b == "insert" then
		queue.insert = not queue.insert
		return true
	end
	return false
end

-- The order menu on the pad follows the pointer once it is the player's again (the warp landed, or half a second),
-- keeps it on the menu (pushed off it for LEAVE_SECONDS it lets go) and ends when the menu goes; the app is told
-- which menu has the pad and what is picked
function widget:Update(dt)
	padOrders(WG.BarDroidPadOnly == true)
	padHover()
	if (queue.on or queue.insert) and WG.BarDroidPadOnly == true then -- (fingers' buttons: left on, every order of the
		-- pad's would queue)
		queue.on, queue.insert = false, false
	end
	-- (nothing picked: both off; Kailil, 2026-11-13: "remove queue and insert toggle if the unit is not selected")
	-- (before the start nothing is ever picked: the pre-game dock's own QUEUE, bardroid_portrait.lua, keeps it on there)
	if (queue.on or queue.insert) and Spring.GetSelectedUnitsCount() == 0
		and not (queue.on and Spring.GetGameFrame() == 0 and not Spring.GetSpectatingState()) then
		queue.on, queue.insert = false, false
	end
	if area.radius ~= area.target then
		local r = area.radius + (area.target - area.radius) * math.min(1, (dt or 0) / AREA_EASE)
		area.radius = math.abs(area.target - r) < 1 and area.target or r
	end
	if orders then
		local layout = ordersLayout()
		if not layout then
			ordersEnd()
		else
			orders.layout = layout
			local mx, my = pointerAt()
			local recorded = fakeWarp and not fakePointer -- (the moves only recorded: no pointer to follow)
			local w = recorded or orders.warped
			if w and not recorded and ((math.abs(mx - w[1]) <= 2 and math.abs(my - w[2]) <= 2) or Spring.DiffTimers(now(), w[3]) > 0.5) then
				orders.warped, w = nil, nil
			end
			if not w then
				local over
				for i, r in ipairs(layout.cells) do
					if i <= #layout.cmds and mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then
						over = i
						break
					end
				end
				-- (also the same cell with another order in it: the menu changed under a pointer at rest, as when a
				-- selected unit dies or the priority target button comes; the order lit and given is the one there)
				if over and (over ~= orders.index or layout.cmds[over].id ~= orders.cmdID) then
					orders.index, orders.cmdID = over, layout.cmds[over].id
					ordersLight(orders.cmdID)
				end
				local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge -- (the menu: all its cells)
				for _, r in ipairs(layout.cells) do
					x0, y0, x1, y1 = math.min(x0, r[1] + 2), math.min(y0, r[2] + 2), math.max(x1, r[3] - 2), math.max(y1, r[4] - 2)
				end
				if mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
					orders.outSince = nil
				elseif not orders.outSince then
					orders.outSince = now()
					warpTo(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				elseif Spring.DiffTimers(now(), orders.outSince) >= LEAVE_SECONDS then
					ordersEnd()
				else
					warpTo(math.max(x0, math.min(x1, mx)), math.max(y0, math.min(y1, my)))
				end
			end
		end
	end
	if area.on then
		areaUpdate()
	end
	if dgun then
		dgunUpdate()
	end
	-- (no units selected: the list stays, for metal and energy; the fingers the input, the pad gone: it closes, it took no
	-- touches and held D-GUN and the next A, review 2026-11-15)
	if share and (Spring.GetSpectatingState() or WG.BarDroidInput == "touch") then
		shareClose()
	end
	if #given > 0 then
		shareCheck()
	end
	local armed = armedKind()
	if armed ~= "build" and WG.BarDroidPadSlowPan then -- (the slow pan is for placing only, as in v0.8.5)
		WG.BarDroidPadSlowPan = nil
	end
	local focus = orders and "orders" or (buildFocus() and "build" or "none")
	local pregame = Spring.GetGameFrame() == 0 and not Spring.GetSpectatingState()
	-- (INSERT with only factories picked: no CommandInsert key, whose CMD.INSERT a factory's build queue does not take,
	-- so +1, +5 and +20 added nothing (Kailil, 2026-11-11); the dock gives those Alt instead, BAR's alt-click to the
	-- queue's front)
	local insertKey = queue.insert
	if insertKey then
		-- (worked out again only when the pick changes, SelectionChanged: a table of counts each frame for as long as
		-- INSERT stayed on, minutes; review 2026-11-16)
		if factoriesPicked == nil then
			local counts = Spring.GetSelectedUnitsCounts() or {}
			local factories = true
			for d in pairs(counts) do
				local ud = type(d) == "number" and UnitDefs[d]
				if ud and not ud.isFactory then
					factories = false
					break
				end
			end
			factoriesPicked = factories and Spring.GetSelectedUnitsCount() > 0
		end
		insertKey = not factoriesPicked
	end
	-- (QUEUE and INSERT both on, factories: Shift and Alt held, BAR's own with them (a factory's Alt is its queue's front).
	-- Builders keep the CommandInsert key under QUEUE's Shift, its prepend_queue: each building at the queue's front, after
	-- the ones placed so before it or, once the held key's repeats start CommandInsert's count again, first (dev phone,
	-- touchfix-phone-test: either way ahead of the rest of the queue). With
	-- Shift and Alt a builder's building went to its queue's end, Alt is nothing to a builder's build order: the night's
	-- touch playtest, 2026-11-22, "INSERT on a builder ... did not put a placed building at the queue's front")
	local both = queue.on and queue.insert and factoriesPicked == true
	local text = "focus " .. focus .. "\npregame " .. (pregame and 1 or 0) .. "\narmed " .. armed .. "\ndrawspeed "
		.. string.format("%.2f", WG.BarDroidDrawSpeed or 1) .. "\nqueue " .. (queue.on and 1 or 0)
		.. "\ninsert " .. (insertKey and 1 or 0) .. "\nalt " .. (both and 1 or 0) .. "\nkey " .. padKeys .. " " .. padKeyName .. "\nfp " .. ((WG.BarDroidPadFP and WG.BarDroidPadFP.active()) and 1 or 0) .. "\nclick " .. padClicks
		.. "\nmodal " .. (modal or "none") .. "\n"
	if padClickAt then -- (the last click's point: the app clicks there, not in the middle)
		text = text .. string.format("clickat %.4f %.4f\n", padClickAt[1], padClickAt[2])
	end
	local t = now()
	lookAtOrders(t)
	if not keysLookedAt or Spring.DiffTimers(t, keysLookedAt) > 10 then -- (a change of BAR's keyset drops the two keys)
		keysLookedAt = t
		bindQueueKeys()
	end
	local keep = focus ~= "none" or pregame or armed ~= "none" or queue.on or queue.insert or text:find("fp 1", 1, true)
		or modal
	if text ~= written or (keep and Spring.DiffTimers(t, writtenAt) > 1) then
		if writeWhole(PAD_FILE, text) then
			written, writtenAt = text, t
		end
	end
end

-- A ping from someone else: RB + D-pad up goes there
function widget:MapDrawCmd(playerID, cmdType, x, y, z)
	if cmdType == "point" and playerID ~= Spring.GetMyPlayerID() then
		addPing(x, y, z)
	end
end

-- My units under attack in the same list (Kailil, 2026-11-20: "Alliw unit under attack notification to be tracked via
-- the last pings system so I can teleoort to the danger area"): an enemy's hit on one of my units (the event BAR's own
-- "unit under attack" notice comes from) is an entry at that unit, the camera going to where it is then ("UNDER ATTACK"
-- in red). A fight stays one entry, moved along to each new hit within NEAR elmos and KEEP frames of its last, and kept
-- going where it is by hits within SPREAD (1.6 x NEAR: at 2 x NEAR a fight 2000 elmos off, the entry having followed its
-- own 460 elmos that way, was taken in, attack-ping-test 2026-11-24). A hit farther from every live entry is a new
-- fight: within 3 x NEAR of one (the same battle spreading) an entry at most every GAP frames, farther (a new place) at
-- most every FAR frames. Each of my units looked at no more than every LOOK frames, at most BUDGET a frame (a late 8v8 has thousands of
-- hits a second). (One hit every 8 frames for the whole game, the first of its frame, left a light fight unseen beside a
-- busy one, whose hits came first nearly every time: one Grunt on a far solar while thirty Pawns fought thirty Grunts,
-- attack-ping-test, 2026-11-20.) (One GAP for every new entry, the hits within NEAR alone merged: a busy fight spreading
-- past NEAR opened entries of its own every 4 s and its far hits took each gap first, the light fight far off never got
-- one: attack-ping-test's full set on 912e7b2a, 2026-11-24.) (One table: under Lua's 200 locals.)
local ATTACK = { NEAR = 900, SPREAD = 1440, KEEP = 30 * 15, GAP = 30 * 4, FAR = 30, LOOK = 30 * 2, BUDGET = 4,
	seen = {}, seenFrom = 0, frame = -1, looked = 0, lastNew = -1e9 }
function widget:UnitDamaged(unitID, _, unitTeam, damage, paralyzer, weaponDefID, _, _, _, attackerTeam)
	if unitTeam ~= Spring.GetMyTeamID() or not damage or damage <= 0 or paralyzer then
		return
	end
	local f = Spring.GetGameFrame()
	if f - ATTACK.seenFrom > 30 * 60 then -- (the units looked at, forgotten once a minute: dead ones' ids)
		ATTACK.seen, ATTACK.seenFrom = {}, f
	end
	if f - (ATTACK.seen[unitID] or -1e9) < ATTACK.LOOK then
		return
	end
	if ATTACK.frame ~= f then
		ATTACK.frame, ATTACK.looked = f, 0
	end
	if ATTACK.looked >= ATTACK.BUDGET then
		return
	end
	ATTACK.looked = ATTACK.looked + 1
	-- (LuaUI is handed no weapon and no attacker for these hits, dev phone 2026-11-20: as BAR's own notices, any damage
	-- to my units counts; when they are given, a weapon below 0 (a fall, a crush, lava, debris) or an allied attacker,
	-- a teammate's or my own fire, does not)
	if (weaponDefID and weaponDefID < 0) or (attackerTeam and Spring.AreTeamsAllied(attackerTeam, unitTeam))
		or Spring.GetSpectatingState() then
		return
	end
	local x, y, z = Spring.GetUnitPosition(unitID)
	if not x then
		return
	end
	ATTACK.seen[unitID] = f
	local best, bestD2 = nil, nil -- (the nearest live entry)
	for _, p in ipairs(pings) do
		if p.attack and f - p.frame <= ATTACK.KEEP then
			local d2 = (p[1] - x) ^ 2 + (p[3] - z) ^ 2
			if not bestD2 or d2 < bestD2 then
				best, bestD2 = p, d2
			end
		end
	end
	local near = ATTACK.NEAR
	if best and bestD2 <= near ^ 2 then -- (the same fight: its entry follows it)
		best[1], best[2], best[3], best.unit, best.frame = x, y, z, unitID, f
		return
	elseif best and bestD2 <= ATTACK.SPREAD ^ 2 then -- (its spread: kept going where it is)
		best.frame = f
		return
	end
	if f - ATTACK.lastNew >= ((best and bestD2 <= (3 * near) ^ 2) and ATTACK.GAP or ATTACK.FAR) then
		ATTACK.lastNew = f
		addPing(x, y, z, { attack = true, unit = unitID, frame = f })
	end
end

-- The area select's circle on the ground
function widget:DrawWorld()
	if dgun then
		dgunDraw()
	end
	if area.on and area.x then
		gl.DepthTest(false)
		gl.LineWidth(2.5)
		gl.Color(area.shift and 1 or 0.35, area.shift and 0.85 or 1, 0.35, 0.9)
		gl.DrawGroundCircle(area.x, area.y, area.z, area.radius, 48)
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
	end
end

-- The reticle in the middle of the screen while the pad is the input (and its pointer is there), and the notes
function widget:DrawScreen()
	draws = math.min(draws + 1, 2)
	local vsx, vsy = Spring.GetViewGeometry()
	local cx, cy = math.floor(vsx / 2), math.floor(vsy / 2)
	local pad = WG.BarDroidInput == "pad"
	local riding = WG.BarDroidPadFP and WG.BarDroidPadFP.active() -- (first person has its own crosshair)
	-- (not over the share list either: the ring sat on its middle row, a second teammate's name, pad-test -Share's
	-- screenshots 2026-11-13; the pointer does nothing there)
	if pad and not riding and not dgun and not share and not orders and not buildFocus()
		and not freePointer() then
		-- (a white ring on a dark one: it reads over snow and over water alike)
		local r = style.size(0.016)
		for pass = 1, 2 do
			gl.Color(pass == 1 and 0 or 1, pass == 1 and 0 or 1, pass == 1 and 0 or 1, pass == 1 and 0.35 or 0.75)
			gl.LineWidth(pass == 1 and 4 or 2)
			gl.BeginEnd(GL.LINE_LOOP, function()
				for i = 0, 47 do
					local a = i / 48 * 2 * math.pi
					gl.Vertex(cx + math.cos(a) * r, cy + math.sin(a) * r)
				end
			end)
		end
		gl.LineWidth(1)
		gl.Color(1, 1, 1, 1)
	end
	-- the order on the pad: BAR's gold light over it (the dock's lit tile, 2026-11-23) and outlined in gold over BAR's own
	-- highlight, as the build menu's option on the pad
	local cell = orders and orders.layout and orders.layout.cells[orders.index]
	if cell then
		style.lit(cell[1] + 1, cell[2] + 1, cell[3] - 1, cell[4] - 1)
		style.outline(cell[1] + 1, cell[2] + 1, cell[3] - 1, cell[4] - 1, style.GOLD, 1)
		style.mark("orders", cell[1], cell[2], cell[3], cell[4])
	end
	if not (area.radial and area.on) then -- (the filter radial reaches down to where the strip is)
		drawGroupList(vsx, vsy)
	end
	if area.radial and area.on then
		drawFilterRadial(cx, cy, vsy)
	end
	queueLayout(vsx, vsy)
	drawQueue()
	if share then
		shareDraw(vsx, vsy)
	end
	if dgun then
		local P = WG.BarDroidPortrait -- (upright the dock's own sticks and FIRE)
		if not (P and P.dock and P.dock()) then
			dgunPanel(vsx, vsy)
		end
	end
	if toast then
		local age = Spring.DiffTimers(now(), toastAt)
		if age > toastFor then
			toast = nil
			return
		end
		-- (a quick fade in, a slower fade out; a pad button at the end of a note as its key)
		local alpha = math.max(0, math.min(1, age / 0.08, (toastFor - age) / 0.3))
		local words, key = toast:match("^(.-): ([ABXY])$")
		local ty = cy + vsy * 0.09
		-- (the share list open: its notes just above it, else under it; at the middle they lay across its first row,
		-- "GIVING 300 METAL TO BRAVO" through ALPHA's name, dev phone 2026-11-08)
		local r = share and shareRect
		if r then
			local h, gap = math.floor(style.size(0.02) * 2), style.size(0.008, 3)
			ty = (r[4] + gap + h <= (r[7] or vsy)) and (r[4] + gap) or math.max((r[8] or 0) + gap, r[2] - gap - h)
		end
		style.toast(words or toast, cx, ty, toastColor, alpha, key, voiceToast and age or nil)
		toastDrawnAt = { ty, ty + math.floor(style.size(0.02) * 2) }
	end
end

function widget:Initialize()
	-- (until 2026-11-21 the controller game, v0.8.5's, took the pad here; that check took BAR's own developer game,
	-- "$VERSION", for it too, and the app's pad controls stood down there)
	WG.BarDroidStyle = style -- (the app's build menu: its GRID note and its option on the pad in the same look)
	WG.BarDroidPadDgun = { -- (bardroid_touch.lua hands the sticks to the D-gun mode)
		active = function()
			return dgun ~= nil
		end,
		unit = function() -- (the portrait dock's camera follows it)
			return dgun and dgun.unitID or nil
		end,
		range = function() -- (the portrait dock's camera fits it in)
			return dgun and dgun.range or nil
		end,
		ready = function() -- (the dock's FIRE shows them) how far reloaded (0..1), and the energy of a shot held (0..1)
			if not dgun then
				return nil
			end
			local d, loaded = dgun, 1
			if d.weapon then
				local at = Spring.GetUnitWeaponState(d.unitID, d.weapon, "reloadFrame")
				local secs = Spring.GetUnitWeaponState(d.unitID, d.weapon, "reloadTime")
				if at and secs and secs > 0 then
					loaded = math.max(0, math.min(1, 1 - (at - Spring.GetGameFrame()) / (secs * Game.gameSpeed)))
				end
			end
			local energy = Spring.GetTeamResources(Spring.GetMyTeamID(), "energy") or 0
			return loaded, (d.cost or 0) > 0 and math.min(1, energy / d.cost) or 1
		end,
		auto = function() -- full auto on, and for how many seconds
			if not (dgun and dgun.auto) then
				return false
			end
			return true, math.max(0, Spring.DiffTimers(now(), dgun.autoOn or now())) -- (never under 0 nor NaN: dgunDraw)
		end,
		sticks = function(lx, ly, rx, ry, touch)
			local d = dgun
			if not d then
				return
			end
			d.lx, d.ly, d.rx, d.ry = lx, ly, rx, ry
			d.touch = touch and true or false -- (dgunUpdate: the touch sticks' ways from the screen, screenHeading)
			-- (the dock's touch AIM, bardroid_portrait.lua's dgunsticks lines: each line's way at once, from a fifth of the
			-- ring out (a short drag did nothing under the pad's half way: the night's touch playtest, 2026-11-22), the way
			-- on the screen. The pad's sticks keep dgunUpdate's half way and the camera's heading)
			if touch and not d.auto then
				local ax, az = screenHeading(d.unitID, rx, ry, DGUN_TOUCH_AIM_DEADZONE)
				if ax then
					d.aimX, d.aimZ, d.track = ax, az, nil
					dgunTarget(d)
				end
			end
		end,
		-- (a map tap in the dock's D-gun mode, bardroid_portrait.lua: the shot's way towards the ground tapped, FIRE then
		-- fires it, BAR's own D-gun is a click on a target; the tap had deselected the commander and ended the mode)
		aimAt = function(x, z)
			local d = dgun
			if not (d and x and z) or d.auto then
				return false
			end
			local cx, _, cz = Spring.GetUnitPosition(d.unitID)
			local dx, dz = cx and x - cx or 0, cz and z - cz or 0
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 10 then
				return false
			end
			d.aimX, d.aimZ, d.track = dx / len, dz / len, nil
			dgunTarget(d)
			return true
		end,
		-- (an enemy tapped in the dock's D-gun mode: the aim follows it, led, dgunTrack; false: not an enemy, or none)
		aimAtUnit = function(u)
			local d = dgun
			if not (d and u) or d.auto or Spring.IsUnitAllied(u) ~= false or Spring.GetUnitIsDead(u) ~= false then
				return false
			end
			d.track = u
			dgunTrack(d)
			dgunTarget(d)
			return d.track == u
		end,
		tracking = function() -- (tools: the enemy the aim follows, or nil)
			return dgun and dgun.track or nil
		end,
		ring = function() -- (tools: where the aim's rings stand, x and z)
			if dgun and dgun.x then
				local x, _, z = dgunRing(dgun)
				return x, z
			end
		end,
	}
	WG.BarDroidPad = {
		act = act,
		say = note, -- (bardroid_padfp.lua's notes)
		unsay = function(text) -- (that note gone if it still shows: the portrait dock's "TAP ... AGAIN" once it is done)
			if toast and toast == text then
				toast = nil
			end
		end,
		teammates = teammates, -- (the portrait dock's teammate picker)
		give = giveTo,
		queueState = function() -- (the portrait dock draws QUEUE and INSERT: on or off)
			return queue.on, queue.insert
		end,
		queueKey = queueKey, -- (the portrait dock's remove buttons: the next order off, or the last)
		-- the words said for a ping (bardroid_touch.lua; LB held + RB three times): a ping with them as its label where
		-- the middle was then (Kailil, 2026-11-06: as BAR's own labelled ping); BAR's 127 bytes at most, whole letters
		voicePing = function(text)
			local p = voicePingAt
			voicePingAt = nil
			if not (p and Spring.DiffTimers(now(), p.at) <= VOICE_PING_SECONDS) then
				local _, pos = aim()
				p = pos
			end
			text = text:gsub("%s+", " "):gsub("^ ", "")
			if not (p and text:find("%S")) then
				return
			end
			if #text > 127 then
				local after = text:byte(128)
				text = text:sub(1, 127)
				if after >= 128 and after < 192 then -- (inside a character: its lead byte and what got in go; bardroid_chat.lua)
					text = text:gsub("[\192-\255][\128-\191]*$", "")
				end
			end
			Spring.MarkerAddPoint(p[1], p[2], p[3], text)
			note("PING")
		end,
		-- (tools/pad-test.ps1: the mode on, the D-gun's commander, aim and target; the share list's pick and length; the
		-- last click's point; the share list's tab and amount step)
		modal = function()
			return modal, dgun and dgun.unitID, dgun and dgun.aimX, dgun and dgun.aimZ, share and share.index,
				share and #share.teams, padClickAt and padClickAt[1], padClickAt and padClickAt[2], share and share.tab,
				share and share.step
		end,
		-- (tools/pad-test.ps1 -Share: the list opened on the teams given, as if they were teammates)
		shareTest = function(teams)
			share = { index = 1, teams = teams, tab = shareLastTab, step = shareLastStep }
			modal = "share"
		end,
		shareRect = function()
			return shareRect
		end,
		toastRect = function()
			return toastDrawnAt
		end,
		-- (tools/pad-test.ps1 -Shots: a piece's rect as drawn in the last few frames, GL pixels; nil: not drawn lately)
		drawnRect = function(name)
			local r = style.drawn[name]
			return r and Spring.GetDrawFrame() - r.at <= 5 and r or nil
		end,
		shareGiven = function(units, teamID) -- (tools/pad-test.ps1 -Share: units just given, checked at the next update)
			given[#given + 1] = { units = units, teamID = teamID, from = Spring.GetMyTeamID(), at = now(), checkNow = true }
		end,
		shareAmount = function() -- (all three: "a and f()" kept only the amount, and the test's checks went blind)
			if share and shareResource(share) then
				return shareAmount(share, share.teams[share.index])
			end
		end,
		setPing = function(x, y, z) -- (tools/pad-test.ps1: a ping from someone else)
			addPing(x, y, z)
		end,
		pingLook = pingLook, -- (the portrait dock's PINGS: the last 4)
		pingCount = function() -- (the pings from others seen; the one the camera went to last, 0 after the cycle's pause;
			-- the newest an attack on my units still going)
			local cycling = pingStepAt and Spring.DiffTimers(now(), pingStepAt) <= PING_CYCLE_SECONDS
			local p = pings[1]
			return #pings, cycling and pingStep or 0,
				p and p.attack and Spring.GetGameFrame() - p.frame <= ATTACK.KEEP or false
		end,
		pingAt = function(i) -- (tools: the list's i-th entry: x, z, an attack's or not)
			local p = pings[i]
			if p then
				return p[1], p[3], p.attack or false
			end
		end,
		-- (tools/touch-widget-test.ps1: the order on the pad, its place in the menu, the menu's size; putting the pad on
		-- one order; pointer moves recorded instead of made)
		orders = function()
			return orders and orders.cmdID, orders and orders.index, orders and #orders.layout.cmds
		end,
		ordersCells = function() -- (the order menu's cells as worked out here, and its commands)
			local layout = ordersLayout()
			return layout and layout.cells, layout and layout.cmds
		end,
		ordersOn = function(cmdID)
			local layout = ordersLayout()
			for i, cmd in ipairs(layout and layout.cmds or {}) do
				if cmd.id == cmdID then
					ordersGo(i)
					return true
				end
			end
			return false
		end,
		setWarp = function(fn)
			warp, fakeWarp = fn or Spring.WarpMouse, fn ~= nil
			if not fn then
				fakePointer = nil
			end
		end,
		setPointer = function(x, y) -- (a made-up pointer the recorded moves land on, with setWarp; nil: none)
			fakePointer = x and { x, y } or nil
		end,
		note = function() -- (the note showing, the last one shown, how many so far)
			return toast, lastNote, notes
		end,
		area = function() -- (the area select: on, its radius, how many units it has passed over; its filter, radial)
			return area.on, area.target, area.count, area.filter, area.radial and area.highlight
		end,
		chooseUnits = chooseUnits, -- (what the area select takes of units: made-up unit types)
		ordersHidden = function() -- (the order menu's orders hidden while the pad is the input)
			return ordersHidden
		end,
		queueOn = function(on) -- (QUEUE: on or off, as a tap on it would)
			if on ~= nil then
				queue.on = on
			end
			return queue.on
		end,
	}
end

function widget:Shutdown()
	padOrders(false)
	ordersEnd()
	if hoverOff and WG.info and WG.info.clearCustomHover then
		WG.info.clearCustomHover()
	end
	WG.BarDroidPad = nil
	WG.BarDroidPadDgun = nil
	WG.BarDroidStyle = nil
	writeWhole(PAD_FILE, "focus none\npregame 0\narmed none\nqueue 0\nmodal none\n")
end
