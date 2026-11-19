-- BAR Droid camera controls: the camera zoomed and turned with one finger on the map (Kailil, 2026-11-19: "we need to
-- figure out a way to zoom out and in with one finger. and rotate", then of the ideas offered, "build both systems
-- fully, then i will test them both. add a settings toggle in settings under controls or camera controlls"):
--   the camera knob: a round knob over the map; held, the finger's first slide decides: up or down zooms (down closer,
--     as the dock's camera pad), sideways turns. Moved and sized in the layout editor (three fingers held, "Camera
--     knob");
--   the edge rails: a strip down the map's right edge zooms (a finger slid along it, down closer) and one along the
--     map's foot, above the dock, turns. Only with the app's touch dock up (BAR's own screen keeps its panels there).
-- Each has its switch in Settings, Control tab ("Camera knob", "Camera edge rails"; bardroid_options.lua moves them
-- there from BAR's Custom tab); both on at first. The fingers are RtsTouch's: this widget draws the knob and the rails
-- and tells RtsTouch where they are in LuaUI/Config/bardroid_camctl.txt (X screen pixels, top left origin: "knob x0 y0
-- x1 y1", "zoom ...", "turn ..."; "none" when neither shows); RtsTouch sends the dock pad's own "zoom" and "rot" lines
-- to bardroid_touch.lua, and "camheld knob|zoom|turn|none" in the touch log, which lights the part held.
-- WG.BarDroidCamCtl: knob(), rails() (on or off), setKnob(on), setRails(on), rects() (GL pixels: knob, zoom, turn).
-- Installed into LuaUI/Widgets by the app.

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
local KNOB_KEY, RAILS_KEY = "BarDroidCamKnob", "BarDroidCamRails"
local KNOB_R = 0.06 -- the knob's radius, of the screen's short side (a 7 mm knob on a phone)
local RAIL_W = 0.06 -- the rails' width, of the screen's short side (a finger's tip at the edge)
local LAYOUT_ID = "camknob"

local vsx, vsy = Spring.GetViewGeometry()
local knobOn, railsOn = true, true
local knob, zoomRail, turnRail -- GL pixels: { cx, cy, r } and { x0, y0, x1, y1 }
local held -- "knob", "zoom", "turn" or nil (RtsTouch's camheld lines)
local written, writtenAt = nil, -10
local optionsFor -- the WG.options the switches were added to
local timer = Spring.GetTimer()

local function now()
	return Spring.DiffTimers(Spring.GetTimer(), timer)
end

local function configOn(key)
	local ok, v = pcall(Spring.GetConfigInt, key, 1)
	return not ok or v ~= 0
end

local function saveConfig(key, on)
	pcall(Spring.SetConfigInt, key, on and 1 or 0)
end

---------------------------------------------------------------------------------------------------------------------
-- where they stand

local function portrait()
	local P = WG.BarDroidPortrait
	return P and P.active and P.active() and P or nil
end

-- the game's room: the screen less BAR's top bar above and the dock below (GL pixels)
local function room()
	local top = vsy
	local tb = WG["topbar"] and WG["topbar"].GetPosition and WG["topbar"].GetPosition()
	if type(tb) == "table" and tonumber(tb[2]) and tb[2] > vsy * 0.5 then
		top = math.floor(tb[2])
	end
	local P = portrait()
	local d = P and P.dock and P.dock()
	return d, top
end

local function hiddenNow()
	if Spring.IsGUIHidden() then
		return true
	end
	local P = WG.BarDroidPortrait
	if P and P.aside and P.aside() then -- (one of BAR's big windows, BAR's lobby over the game: they have the screen)
		return true
	end
	return false
end

local function layout()
	local short = math.min(vsx, vsy)
	local pad = math.max(4, math.floor(short * 0.012))
	local w = math.max(24, math.floor(short * RAIL_W))
	local d, top = room()
	zoomRail, turnRail = nil, nil
	-- the rails: only with the dock up (it says where the game's room ends); the zoom rail down the right edge between
	-- the top bar and the dock (a dock in the right corner, sideways: above it), the turn rail along the foot of the game
	-- above the dock, from the left edge to the zoom rail (a dock in a corner: beside it, at the screen's foot)
	if railsOn and d then
		local wide = d[3] - d[1] >= vsx * 0.9
		local zoomFoot = (wide or d[3] >= vsx - w) and d[4] + pad or pad
		zoomRail = { vsx - w, zoomFoot, vsx, top - pad }
		if wide then
			turnRail = { 0, d[4] + pad, vsx - w - pad, d[4] + pad + w }
		elseif d[1] > vsx * 0.3 then -- (the dock in the right corner: the foot left of it)
			turnRail = { 0, 0, d[1] - pad, w }
		else -- (in the left corner: right of it, short of the zoom rail)
			turnRail = { d[3] + pad, 0, vsx - w - pad, w }
		end
		if zoomRail[4] - zoomRail[2] < w * 3 then
			zoomRail = nil
		end
		if turnRail[3] - turnRail[1] < w * 3 then
			turnRail = nil
		end
	end
	knob = nil
	if knobOn then
		local Lw = WG.BarDroidLayout
		local s = Lw and Lw.get and Lw.get(LAYOUT_ID) or {}
		local r = math.floor(short * KNOB_R * (s.size or 1))
		local foot = (d and d[3] - d[1] >= vsx * 0.9) and d[4] or 0
		if turnRail and turnRail[2] >= foot then
			foot = turnRail[4]
		end
		-- (at the thumb's side: the right, above the dock and the turn rail, left of the zoom rail; sideways with the dock
		-- in the right corner, the left)
		local right = not (d and d[1] > vsx * 0.3 and d[3] - d[1] < vsx * 0.9)
		local cx = right and (vsx - (zoomRail and w or 0) - pad * 2 - r) or (pad * 2 + r)
		local cy = foot + pad * 3 + r
		cx = cx + (s.dx or 0) * vsx
		cy = cy + (s.dy or 0) * vsy -- (the editor's drag in GL pixels: up is up)
		cx = math.max(r + pad, math.min(vsx - r - pad, math.floor(cx)))
		cy = math.max(r + pad, math.min(top - r - pad, math.floor(cy)))
		knob = { cx, cy, r }
	end
end

-- RtsTouch's side: X screen pixels, top left origin
local function writeFile(force)
	local text
	if hiddenNow() or not (knob or zoomRail or turnRail) then
		text = "none\n"
	else
		local function r(x0, y0, x1, y1)
			return string.format("%d %d %d %d", x0, vsy - y1, x1, vsy - y0)
		end
		text = ""
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

---------------------------------------------------------------------------------------------------------------------
-- the switches (Settings, Control tab)

local function setKnob(on)
	knobOn = on and true or false
	saveConfig(KNOB_KEY, knobOn)
	layout()
	writeFile(true)
end

local function setRails(on)
	railsOn = on and true or false
	saveConfig(RAILS_KEY, railsOn)
	layout()
	writeFile(true)
end

local OPTION_IDS = { "bardroid_camctl_label", "bardroid_camknob", "bardroid_camrails" }

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
			id = OPTION_IDS[2], droidGroup = "control", category = 1, type = "bool", value = knobOn,
			name = "Camera knob",
			description = "A round knob over the map: hold it and slide up or down to zoom, sideways to turn. "
				.. "Move or size it in the layout editor (three fingers held)",
			onchange = function(_, value)
				setKnob(value)
			end,
		},
		{
			id = OPTION_IDS[3], droidGroup = "control", category = 1, type = "bool", value = railsOn,
			name = "Camera edge rails",
			description = "With the touch dock up: slide a finger along the map's right edge to zoom, along its foot "
				.. "above the dock to turn",
			onchange = function(_, value)
				setRails(value)
			end,
		},
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
-- drawing

local function circle(cx, cy, r, n)
	gl.BeginEnd(GL.TRIANGLE_FAN, function()
		gl.Vertex(cx, cy)
		for i = 0, n do
			local a = i / n * math.pi * 2
			gl.Vertex(cx + math.cos(a) * r, cy + math.sin(a) * r)
		end
	end)
end

local function ring(cx, cy, r, t, n)
	gl.BeginEnd(GL.TRIANGLE_STRIP, function()
		for i = 0, n do
			local a = i / n * math.pi * 2
			local c, s = math.cos(a), math.sin(a)
			gl.Vertex(cx + c * r, cy + s * r)
			gl.Vertex(cx + c * (r - t), cy + s * (r - t))
		end
	end)
end

-- a small triangle pointing along (dx, dy) with its tip at (x, y)
local function arrow(x, y, dx, dy, s)
	local px, py = -dy, dx
	gl.BeginEnd(GL.TRIANGLES, function()
		gl.Vertex(x, y)
		gl.Vertex(x - dx * s + px * s * 0.75, y - dy * s + py * s * 0.75)
		gl.Vertex(x - dx * s - px * s * 0.75, y - dy * s - py * s * 0.75)
	end)
end

local function drawKnob()
	local cx, cy, r = knob[1], knob[2], knob[3]
	local lit = held == "knob"
	gl.Color(0, 0, 0, 0.35)
	circle(cx, cy - math.max(1, r * 0.05), r * 1.02, 40) -- (a soft shadow under it)
	if lit then
		gl.Color(0.42, 0.33, 0.12, 0.85)
	else
		gl.Color(0.12, 0.13, 0.13, 0.72)
	end
	circle(cx, cy, r, 40)
	gl.Color(lit and 1 or 0.85, lit and 0.82 or 0.85, lit and 0.35 or 0.85, lit and 0.95 or 0.55)
	ring(cx, cy, r, math.max(1.5, r * 0.06), 40)
	-- up and down for the zoom, left and right for the turn; a dot in the middle
	local a = r * 0.62
	local s = r * 0.2
	gl.Color(1, 1, 1, lit and 0.95 or 0.8)
	arrow(cx, cy + a, 0, 1, s)
	arrow(cx, cy - a, 0, -1, s)
	gl.Color(1, 0.85, 0.45, lit and 0.95 or 0.75)
	arrow(cx + a, cy, 1, 0, s)
	arrow(cx - a, cy, -1, 0, s)
	gl.Color(1, 1, 1, 0.5)
	circle(cx, cy, r * 0.09, 16)
end

local function drawRail(rect, vertical, lit)
	local x0, y0, x1, y1 = rect[1], rect[2], rect[3], rect[4]
	if lit then
		gl.Color(0.5, 0.38, 0.12, 0.55)
	else
		gl.Color(0.05, 0.06, 0.06, 0.32)
	end
	gl.Rect(x0, y0, x1, y1)
	local w = vertical and (x1 - x0) or (y1 - y0)
	local len = vertical and (y1 - y0) or (x1 - x0)
	-- a groove down its middle and ticks across it: a slider's track
	gl.Color(1, 1, 1, lit and 0.55 or 0.28)
	local mid = vertical and math.floor((x0 + x1) / 2) or math.floor((y0 + y1) / 2)
	if vertical then
		gl.Rect(mid - 1, y0 + w, mid + 1, y1 - w)
	else
		gl.Rect(x0 + w, mid - 1, x1 - w, mid + 1)
	end
	local step = math.max(w * 0.9, 16)
	local tick = math.floor(w * 0.22)
	for p = w * 1.5, len - w * 1.5, step do
		if vertical then
			gl.Rect(mid - tick, y0 + p, mid + tick, y0 + p + 1)
		else
			gl.Rect(x0 + p, mid - tick, x0 + p + 1, mid + tick)
		end
	end
	-- its ends: which way each goes
	local s = w * 0.28
	gl.Color(1, lit and 0.85 or 1, lit and 0.4 or 1, lit and 0.95 or 0.6)
	if vertical then
		arrow(mid, y1 - w * 0.35, 0, 1, s)
		arrow(mid, y0 + w * 0.35, 0, -1, s)
	else
		arrow(x1 - w * 0.35, mid, 1, 0, s)
		arrow(x0 + w * 0.35, mid, -1, 0, s)
	end
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
		drawKnob()
	end
	gl.Color(1, 1, 1, 1)
end

-- (a mouse over them: the interface's, as BAR's panels)
function widget:IsAbove(x, y)
	if hiddenNow() then
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

-- the knob in the layout editor (it may load after this widget: asked again until it is there)
local layoutFor
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
		relayout = function()
			layout()
			writeFile(true)
		end,
	})
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
	layout()
	writeFile(true)
end

function widget:Initialize()
	knobOn, railsOn = configOn(KNOB_KEY), configOn(RAILS_KEY)
	vsx, vsy = Spring.GetViewGeometry()
	registerLayout()
	layout()
	writeFile(true)
	WG.BarDroidCamCtl = {
		knob = function()
			return knobOn
		end,
		rails = function()
			return railsOn
		end,
		setKnob = setKnob,
		setRails = setRails,
		rects = function()
			return knob, zoomRail, turnRail
		end,
	}
	Spring.Echo(string.format("[bardroid-camctl] knob %s, edge rails %s", knobOn and "on" or "off", railsOn and "on" or "off"))
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
