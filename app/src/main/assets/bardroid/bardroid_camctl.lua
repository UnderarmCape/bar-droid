-- BAR Droid camera controls: the camera zoomed and turned with one finger on the map (Kailil, 2026-11-19: "we need to
-- figure out a way to zoom out and in with one finger. and rotate", then of the ideas offered, "build both systems
-- fully, then i will test them both. add a settings toggle in settings under controls or camera controlls"):
--   the camera knob: a round knob over the map; held, the finger's first slide decides: up or down zooms (down closer,
--     as the dock's camera pad), sideways turns. Moved and sized in the layout editor (three fingers held, "Camera
--     knob");
--   the edge rails, with the app's touch dock up: one up the map's side edge zooms (down closer), one along its foot
--     turns, each half the edge it sits on, from the corner where they meet (Kailil, the same day: "they should only take
--     up half the space they are sitting in ... so its symmetrical").
-- Kailil, the same day, after the first build: a switch to put them on the left ("for left handed people too"), drags
-- whose speed counts ("slower speed means less movement. faster means more. so I can have fine adjustments": RtsTouch
-- scales each step by the finger's speed, a sensitivity setting on top), and looks to pick from in game ("I'm not a
-- huge fan of the look ... show me different finished variants and allow them to be selected between in game"); of the
-- four shown he kept Minimal, "white, or the same color the background of the bottom ui is".
-- Settings, Control tab, "Camera with one finger" (bardroid_options.lua moves them there from BAR's Custom tab): Camera
-- knob, Camera edge rails, Controls on the left, Colour (White, Dock grey), Sensitivity. Spring config
-- BarDroidCamKnob, BarDroidCamRails, BarDroidCamLeft, BarDroidCamLook, BarDroidCamGain (percent).
-- The fingers are RtsTouch's: this widget draws them and tells it where they are in LuaUI/Config/bardroid_camctl.txt (X
-- screen pixels, top left origin: "knob x0 y0 x1 y1", "zoom ...", "turn ...", "gain g"; "none" when nothing shows);
-- RtsTouch sends the dock pad's own "zoom" and "rot" lines to bardroid_touch.lua, and "camheld knob|zoom|turn|none" in
-- the touch log, which lights the part held.
-- WG.BarDroidCamCtl: knob(), rails(), left(), look(), gain(), setKnob(on), setRails(on), setLeft(on), setLook(i),
-- setGain(g), rects() (GL pixels: knob, zoom, turn), LOOKS. Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid camera controls",
		desc = "Zoom and turn the camera with one finger: a knob over the map and rails along its edges",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = 5, -- (under the dock, -10, and the layout editor: they draw over it)
		enabled = true,
	}
end

local CAM_FILE = "LuaUI/Config/bardroid_camctl.txt"
local TOUCH_LOG = "LuaUI/Config/bardroid_touch.txt"
local KEYS = { knob = "BarDroidCamKnob", rails = "BarDroidCamRails", left = "BarDroidCamLeft", look = "BarDroidCamLook",
	gain = "BarDroidCamGain" }
local LOOKS = { "White", "Dock grey" }
local KNOB_R = 0.06 -- the knob's radius, of the screen's short side (a 7 mm knob on a phone)
local RAIL_W = 0.06 -- the rails' width, of the screen's short side (a finger's tip at the edge)
local LAYOUT_ID = "camknob"
local GOLD = { 1, 0.78, 0.25 }

local floor, min, max, pi = math.floor, math.min, math.max, math.pi
local vsx, vsy = Spring.GetViewGeometry()
local set = { knob = true, rails = true, left = false, look = 1, gain = 1 }
local knob, zoomRail, turnRail -- GL pixels: { cx, cy, r } and { x0, y0, x1, y1 }
local held -- "knob", "zoom", "turn" or nil (RtsTouch's camheld lines)
local written, writtenAt = nil, -10
local optionsFor, layoutFor -- the WG.options and WG.BarDroidLayout this widget is known to
local timer = Spring.GetTimer()

local function now()
	return Spring.DiffTimers(Spring.GetTimer(), timer)
end

local function configInt(key, default)
	local ok, v = pcall(Spring.GetConfigInt, key, default)
	return ok and tonumber(v) or default
end

local function saveInt(key, v)
	pcall(Spring.SetConfigInt, key, v)
end

---------------------------------------------------------------------------------------------------------------------
-- where they stand

local function portrait()
	local P = WG.BarDroidPortrait
	return P and P.active and P.active() and P or nil
end

-- the dock (GL pixels) and the top of the game's room (under BAR's top bar)
local function room()
	local top = vsy
	local tb = WG["topbar"] and WG["topbar"].GetPosition and WG["topbar"].GetPosition()
	if type(tb) == "table" and tonumber(tb[2]) and tb[2] > vsy * 0.5 then
		top = floor(tb[2])
	end
	local P = portrait()
	local d = P and P.dock and P.dock()
	return d, top
end

local function hiddenNow()
	if Spring.IsGUIHidden() then
		return true
	end
	-- (a gamepad or a mouse the input, bardroid_touch.lua's WG.BarDroidInput: BAR's own screen, no fingers to use them;
	-- the knob stood over BAR's panels there. A finger's touch brings them back)
	local src = WG.BarDroidInput
	if src == "pad" or src == "mouse" then
		return true
	end
	local P = WG.BarDroidPortrait
	return P and P.aside and P.aside() or false -- (one of BAR's big windows, BAR's lobby over the game: their screen)
end

-- how far in from the hand's edge the zoom rail must stand: past BAR's button panels on that edge between y0 and y1
-- (WG.BarDroidTapPanels, GL pixels: a spectator's replay speed column on the left; left-handed, the rail lay over
-- 0.5x to 8x and took their taps, the turn rail over "skip"; dev phone 2026-11-19)
local function edgeInset(left, w, y0, y1, pad)
	local inset = 0
	for _, rect in pairs(WG.BarDroidTapPanels or {}) do
		local ok, x0, ry0, x1, ry1 = pcall(rect)
		if ok and tonumber(x0) and tonumber(ry1) and ry1 > y0 and ry0 < y1 then
			if left and x0 <= w then
				inset = max(inset, floor(x1) + pad)
			elseif not left and x1 >= vsx - w then
				inset = max(inset, floor(vsx - x0) + pad)
			end
		end
	end
	return min(inset, floor(vsx * 0.3))
end

local function layout()
	local short = min(vsx, vsy)
	local pad = max(4, floor(short * 0.012))
	local w = max(24, floor(short * RAIL_W))
	local d, top = room()
	local left = set.left
	zoomRail, turnRail = nil, nil
	-- the game's foot: a dock across the bottom (upright, sideways layout A), its top; a dock in a corner (sideways for
	-- one thumb), the screen's foot beside it. fx0..fx1: the free stretch along it
	local wide = d and d[3] - d[1] >= vsx * 0.9
	local footY, fx0, fx1 = 0, 0, vsx
	if d and wide then
		footY = d[4] + pad
	elseif d and d[1] > vsx * 0.3 then
		fx1 = d[1] - pad
	elseif d then
		fx0 = d[3] + pad
	end
	-- the hand's edge, and where the zoom rail starts on it: above the dock where the dock is under that edge
	local edgeUnder = d and (wide or (left and d[1] <= w) or (not left and d[3] >= vsx - w))
	local zoomFoot = edgeUnder and d[4] + pad or footY
	-- the L's corner: the zoom rail's foot on the turn rail's line and the turn rail's stretch out to that edge
	local corner = zoomFoot == footY and ((left and fx0 <= 0) or (not left and fx1 >= vsx))
	if set.rails and d then
		local zlen = floor((top - pad - zoomFoot) / 2)
		local inset = edgeInset(left, w, zoomFoot, zoomFoot + zlen, pad)
		local zx0 = left and inset or vsx - w - inset
		zoomRail = { zx0, zoomFoot, zx0 + w, zoomFoot + zlen }
		local tlen = floor((fx1 - fx0) / 2)
		if corner then -- (beside the zoom rail's foot, along the same line)
			local s = inset + w + pad
			if left then
				turnRail = { s, footY, max(s, tlen), footY + w }
			else
				turnRail = { min(vsx - s, vsx - tlen), footY, vsx - s, footY + w }
			end
		elseif left then -- (from the stretch's end at the hand's side)
			turnRail = { fx0, footY, fx0 + tlen, footY + w }
		else
			turnRail = { fx1 - tlen, footY, fx1, footY + w }
		end
		if zlen < w * 3 then
			zoomRail = nil
		end
		if turnRail[3] - turnRail[1] < w * 3 then
			turnRail = nil
		end
	end
	knob = nil
	if set.knob then
		local Lw = WG.BarDroidLayout
		local s = Lw and Lw.get and Lw.get(LAYOUT_ID) or {}
		local r = floor(short * KNOB_R * (s.size or 1))
		-- at the hand's side, inside the L (above the turn rail, beside the zoom rail); sideways with the dock in a
		-- corner, at the side away from it: the thumb that is free
		local onLeft = left
		if d and not wide then
			onLeft = d[1] > vsx * 0.3
		end
		local foot = footY
		if turnRail then
			foot = turnRail[4]
		end
		if d and not wide and (onLeft == (d[1] <= vsx * 0.3)) then
			foot = d[4] -- (the dock under this side)
		end
		local side = 0 -- (past the zoom rail on this side, wherever edgeInset put it)
		if zoomRail and (zoomRail[1] < vsx / 2) == onLeft then
			side = (onLeft and zoomRail[3] or vsx - zoomRail[1]) + pad
		end
		local cx = onLeft and (pad * 2 + side + r) or (vsx - pad * 2 - side - r)
		local cy = foot + pad * 3 + r
		cx = cx + (s.dx or 0) * vsx
		cy = cy + (s.dy or 0) * vsy -- (the editor's drag in GL pixels: up is up)
		cx = max(r + pad, min(vsx - r - pad, floor(cx)))
		cy = max(r + pad, min(top - r - pad, floor(cy)))
		knob = { cx, cy, r }
	end
end

-- the layout editor open: the knob drawn for it, but its touches the editor's (a tap on the knob to pick it, a drag to
-- move it, went to the camera: "camheld knob", the knob unmoved; dev phone 2026-11-19)
local function editing()
	local Lw = WG.BarDroidLayout
	return Lw and Lw.isOpen and Lw.isOpen() or false
end

-- RtsTouch's side: X screen pixels, top left origin
local function writeFile(force)
	local text
	if hiddenNow() or editing() or not (knob or zoomRail or turnRail) then
		text = "none\n"
	else
		local function r(x0, y0, x1, y1)
			return string.format("%d %d %d %d", x0, vsy - y1, x1, vsy - y0)
		end
		text = string.format("gain %.2f\n", set.gain)
		if knob then
			text = text .. "knob " .. r(knob[1] - knob[3], knob[2] - knob[3], knob[1] + knob[3], knob[2] + knob[3]) .. "\n"
		end
		if zoomRail then
			text = text .. "zoom " .. r(zoomRail[1], zoomRail[2], zoomRail[3], zoomRail[4]) .. "\n"
		end
		if turnRail then
			text = text .. "turn " .. r(turnRail[1], turnRail[2], turnRail[3], turnRail[4]) .. "\n"
		end
	end
	local t = now()
	if text == written and not force and t - writtenAt < 1 then
		return
	end
	local tmp = CAM_FILE .. ".tmp"
	local f = io.open(tmp, "w")
	if f then
		f:write(text)
		f:close()
		os.rename(tmp, CAM_FILE)
	end
	written, writtenAt = text, t
end

local function changed()
	layout()
	writeFile(true)
end

local function setKnob(on)
	set.knob = on and true or false
	saveInt(KEYS.knob, set.knob and 1 or 0)
	changed()
end
local function setRails(on)
	set.rails = on and true or false
	saveInt(KEYS.rails, set.rails and 1 or 0)
	changed()
end
local function setLeft(on)
	set.left = on and true or false
	saveInt(KEYS.left, set.left and 1 or 0)
	changed()
end
local function setLook(i)
	i = floor(tonumber(i) or 1)
	set.look = (i >= 1 and i <= #LOOKS) and i or 1
	saveInt(KEYS.look, set.look)
end
local function setGain(g)
	g = tonumber(g) or 1
	set.gain = max(0.25, min(3, g))
	saveInt(KEYS.gain, floor(set.gain * 100 + 0.5))
	writeFile(true)
end

---------------------------------------------------------------------------------------------------------------------
-- the switches (Settings, Control tab)

local OPTION_IDS = { "bardroid_camctl_label", "bardroid_camknob", "bardroid_camrails", "bardroid_camleft",
	"bardroid_camlook", "bardroid_camgain" }

-- (BAR's model puts options another widget adds under its Custom tab; droidGroup asks the app's Settings to show them
-- under Control: bardroid_options.lua, droid.regroup)
local function addOptions()
	local O = WG.options
	if not (O and O.addOptions) or optionsFor == O then
		return
	end
	optionsFor = O
	pcall(O.addOptions, {
		{ id = OPTION_IDS[1], droidGroup = "control", name = "Camera with one finger", category = 1 },
		{
			id = OPTION_IDS[2], droidGroup = "control", category = 1, type = "bool", value = set.knob,
			name = "Camera knob",
			description = "A round knob over the map: hold it and slide up or down to zoom, sideways to turn. "
				.. "Move or size it in the layout editor (three fingers held, or /hud in the chat)",
			onchange = function(_, value)
				setKnob(value)
			end,
		},
		{
			id = OPTION_IDS[3], droidGroup = "control", category = 1, type = "bool", value = set.rails,
			name = "Camera edge rails",
			description = "With the touch dock up: slide a finger along the rail at the map's side to zoom, along the "
				.. "one at its foot to turn",
			onchange = function(_, value)
				setRails(value)
			end,
		},
		{
			id = OPTION_IDS[4], droidGroup = "control", category = 1, type = "bool", value = set.left,
			name = "Controls on the left",
			description = "The rails and the knob at the left side, for the left hand",
			onchange = function(_, value)
				setLeft(value)
			end,
		},
		{
			id = OPTION_IDS[5], droidGroup = "control", category = 1, type = "select", options = LOOKS, value = set.look,
			name = "Controls colour",
			description = "Thin lines and a ring, lit gold while held: white, or the touch dock's own grey",
			onchange = function(_, value)
				setLook(value)
			end,
		},
		{
			id = OPTION_IDS[6], droidGroup = "control", category = 1, type = "slider", min = 0.5, max = 2, step = 0.1,
			value = set.gain,
			name = "Controls sensitivity",
			description = "How far a drag zooms or turns. The drag's speed counts too: slow for fine steps, fast for "
				.. "big ones",
			onchange = function(_, value)
				setGain(value)
			end,
		},
	})
end

-- the knob in the layout editor (it may load after this widget: asked again until it is there)
local function registerLayout()
	local Lw = WG.BarDroidLayout
	if not (Lw and Lw.register) or layoutFor == Lw then
		return
	end
	layoutFor = Lw
	pcall(Lw.register, LAYOUT_ID, {
		label = "Camera knob",
		can = { move = true, size = true },
		rect = function()
			if knob then
				return knob[1] - knob[3], knob[2] - knob[3], knob[1] + knob[3], knob[2] + knob[3]
			end
		end,
		relayout = changed,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- RtsTouch's lines (the touch log): which part a finger holds

local logFile, logPos, logCalls = nil, 0, 0
local function newLines()
	if not logFile then
		logFile = io.open(TOUCH_LOG, "r")
		logPos = logFile and logFile:seek("end") or 0
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
			logPos = 0
		end
	end
	if not logFile:seek("set", logPos) then
		return nil
	end
	local text = logFile:read("*a") or ""
	local last = text:match(".*()\n")
	if not last then
		return nil
	end
	logPos = logPos + last
	return text:sub(1, last)
end


---------------------------------------------------------------------------------------------------------------------
-- drawing: Minimal, a thin line with a dot at each end, the knob a thin ring with a dot, lit gold while held; white or
-- the touch dock's own grey (Kailil, 2026-11-19, of four looks shown: "keep only 3 minimal. but do white, or the same
-- color the background of the bottom ui is. all the other options are ugly")

local function circle(cx, cy, r, n)
	gl.BeginEnd(GL.TRIANGLE_FAN, function()
		gl.Vertex(cx, cy)
		for i = 0, n do
			local a = i / n * pi * 2
			gl.Vertex(cx + math.cos(a) * r, cy + math.sin(a) * r)
		end
	end)
end

local function ring(cx, cy, r, t, n)
	gl.BeginEnd(GL.TRIANGLE_STRIP, function()
		for i = 0, n do
			local a = i / n * pi * 2
			local c, s = math.cos(a), math.sin(a)
			gl.Vertex(cx + c * r, cy + s * r)
			gl.Vertex(cx + c * (r - t), cy + s * (r - t))
		end
	end)
end

-- a bar from (x0, y0) to (x1, y1), t thick
local function bar(x0, y0, x1, y1, t)
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy)
	if len <= 0 then
		return
	end
	local nx, ny = -dy / len * t / 2, dx / len * t / 2
	gl.BeginEnd(GL.QUADS, function()
		gl.Vertex(x0 + nx, y0 + ny)
		gl.Vertex(x1 + nx, y1 + ny)
		gl.Vertex(x1 - nx, y1 - ny)
		gl.Vertex(x0 - nx, y0 - ny)
	end)
end

-- the colour of a part: gold while held, else the look's (white; the dock's grey, as its panels: about 32 of 255 on
-- the dev phone's screenshots)
local LOOK_COLORS = { { 1, 1, 1, 0.6 }, { 0.125, 0.125, 0.125, 0.92 } }
local function partColor(lit)
	if lit then
		gl.Color(GOLD[1], GOLD[2], GOLD[3], 0.95)
	else
		local c = LOOK_COLORS[set.look] or LOOK_COLORS[1]
		gl.Color(c[1], c[2], c[3], c[4])
	end
end

local function drawRail(r, vertical, lit)
	local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
	local w = vertical and x1 - x0 or y1 - y0
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local base = set.look == 2 and 0.07 or 0.05 -- (the grey a little thicker: dark on a dark map)
	local t = lit and max(3, w * 0.1) or max(2, w * base)
	partColor(lit)
	local e = w * 0.25
	if vertical then
		bar(cx, y0 + e, cx, y1 - e, t)
		circle(cx, y0 + e, t * 1.6, 16)
		circle(cx, y1 - e, t * 1.6, 16)
	else
		bar(x0 + e, cy, x1 - e, cy, t)
		circle(x0 + e, cy, t * 1.6, 16)
		circle(x1 - e, cy, t * 1.6, 16)
	end
end

local function drawKnob(cx, cy, r, lit)
	partColor(lit)
	local base = set.look == 2 and 0.065 or 0.045
	ring(cx, cy, r * 0.8, lit and max(3, r * 0.08) or max(2, r * base), 40)
	circle(cx, cy, r * 0.12, 16)
end

function widget:DrawScreen()
	if hiddenNow() or not (knob or zoomRail or turnRail) then
		return
	end
	gl.Texture(false)
	if zoomRail then
		drawRail(zoomRail, true, held == "zoom")
	end
	if turnRail then
		drawRail(turnRail, false, held == "turn")
	end
	if knob then
		drawKnob(knob[1], knob[2], knob[3], held == "knob")
	end
	gl.Color(1, 1, 1, 1)
end

-- (a mouse over them: the interface's, as BAR's panels)
function widget:IsAbove(x, y)
	if hiddenNow() then
		return false
	end
	-- (a building picked: under them is the map's. The build menu took a spot under the turn rail, which stands just
	-- above the dock, for the interface and dropped it: a building dragged to the dock's top edge had no spot and PLACE
	-- nothing to click, dock-phone-test 4 runs in 5, 2026-11-19. A finger coming down on them is still the camera's,
	-- RtsTouch; PLACE's click there reaches the map, this widget takes no clicks)
	local _, cmd = Spring.GetActiveCommand()
	if cmd and cmd < 0 then
		return false
	end
	if knob and (x - knob[1]) ^ 2 + (y - knob[2]) ^ 2 <= knob[3] ^ 2 then
		return true
	end
	for _, r in ipairs({ zoomRail, turnRail }) do
		if r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
			return true
		end
	end
	return false
end

local lastLayout = -10
function widget:Update()
	addOptions()
	registerLayout()
	local lines = newLines()
	if lines then
		for part in lines:gmatch("camheld (%S+)") do
			held = part ~= "none" and part or nil
		end
	end
	local t = now()
	if t - lastLayout >= 0.25 then -- (the dock comes and goes, the layout editor moves the knob)
		lastLayout = t
		layout()
	end
	writeFile(false)
end

function widget:ViewResize(x, y)
	vsx, vsy = x, y
	changed()
end

function widget:Initialize()
	set.knob = configInt(KEYS.knob, 1) ~= 0
	set.rails = configInt(KEYS.rails, 1) ~= 0
	set.left = configInt(KEYS.left, 0) ~= 0
	local look = configInt(KEYS.look, 1)
	set.look = (look >= 1 and look <= #LOOKS) and look or 1
	set.gain = max(0.25, min(3, configInt(KEYS.gain, 100) / 100))
	vsx, vsy = Spring.GetViewGeometry()
	registerLayout()
	changed()
	WG.BarDroidCamCtl = {
		knob = function()
			return set.knob
		end,
		rails = function()
			return set.rails
		end,
		left = function()
			return set.left
		end,
		look = function()
			return set.look
		end,
		gain = function()
			return set.gain
		end,
		setKnob = setKnob,
		setRails = setRails,
		setLeft = setLeft,
		setLook = setLook,
		setGain = setGain,
		rects = function()
			return knob, zoomRail, turnRail
		end,
		LOOKS = LOOKS,
	}
	Spring.Echo(string.format("[bardroid-camctl] knob %s, edge rails %s, %s, look %s, sensitivity %.1f",
		set.knob and "on" or "off", set.rails and "on" or "off", set.left and "left" or "right", LOOKS[set.look], set.gain))
end

function widget:Shutdown()
	local f = io.open(CAM_FILE, "w")
	if f then
		f:write("none\n")
		f:close()
	end
	if optionsFor and optionsFor.removeOptions then
		pcall(optionsFor.removeOptions, OPTION_IDS)
	end
	if layoutFor and layoutFor.unregister then
		pcall(layoutFor.unregister, LAYOUT_ID)
	end
	if logFile then
		logFile:close()
	end
	WG.BarDroidCamCtl = nil
end
