-- BAR Droid path speed: how fast the pad's pointer draws (X, or LB + A / Y, held) at each zoom (Kailil, 2026-10-30: "Zoom
-- distance determines the speed of mouse movement ... build a tool that will let me adjust the mouse speed curve based on
-- zoom level"; the speed at full zoom out is right as it is). The curve: points of zoom (the camera's distance) and speed,
-- 100% at full zoom out, smoothly between them (by the zoom's logarithm: a step in or out counts the same anywhere) and
-- the nearest point's speed beyond them, in LuaUI/Config/bardroid_padspeed.txt ("<zoom> <speed>" lines).
-- The tuner (Back + Y, or /padspeed in the chat box): a panel at the top right of the screen with the curve, the zoom now and
-- its speed. Zoom with the right stick, hold X to try it; the D-pad's left and right (or - and +) set the speed at this
-- zoom, down (or Remove) takes the point away, B (or Close) closes. The speed goes to the app through bardroid_pad.lua
-- (WG.BarDroidDrawSpeed). Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid path speed",
		desc = "How fast the gamepad's pointer draws paths at each zoom, and its tuner",
		author = "BAR Droid",
		license = "GPL-3.0-or-later",
		layer = -95001,
		enabled = true,
	}
end

local FILE = "LuaUI/Config/bardroid_padspeed.txt"
local STEP = 0.05
local MIN_SPEED, MAX_SPEED = 0.05, 3
local SAME_POINT = 1.15 -- a point this close (as a ratio) to the zoom now is the same point
local LOOK_SECONDS = 0.1

local points = {} -- { zoom, speed }, nearest first; 100% at full zoom out is not one of them
local open = false
local zoomNow, speedNow = 1000, 1
local lookedAt = nil
local buttons = {} -- the panel's buttons: { name, x0, y0, x1, y1 }
local panel = nil

local function fullZoom() -- the engine's farthest (CCameraController: the map's longest side * 1.333)
	return math.max(Game.mapSizeX, Game.mapSizeZ, 1000) * 1.333
end

local function zoomOfCamera()
	local cs = Spring.GetCameraState()
	return math.max(1, cs.dist or cs.height or cs.py or 1)
end

local function speedAt(zoom)
	local top = fullZoom()
	local first = points[1]
	if not first or zoom <= first[1] then
		return first and first[2] or 1
	end
	for i = 1, #points do
		local a, b = points[i], points[i + 1] or { top, 1 }
		if zoom <= b[1] then
			local t = (math.log(zoom) - math.log(a[1])) / (math.log(b[1]) - math.log(a[1]))
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return 1
end

local function load()
	points = {}
	local f = io.open(FILE, "r")
	if not f then
		return
	end
	for line in f:lines() do
		local zoom, speed = line:match("^(%S+) (%S+)")
		zoom, speed = tonumber(zoom), tonumber(speed)
		if zoom and speed then
			points[#points + 1] = { zoom, speed }
		end
	end
	f:close()
	table.sort(points, function(a, b)
		return a[1] < b[1]
	end)
end

local function save()
	local f = io.open(FILE, "w")
	if f then
		for _, p in ipairs(points) do
			f:write(string.format("%.0f %.2f\n", p[1], p[2]))
		end
		f:close()
	end
end

local function pointHere()
	for i, p in ipairs(points) do
		if zoomNow < p[1] * SAME_POINT and zoomNow > p[1] / SAME_POINT then
			return i
		end
	end
	return nil
end

local function look()
	zoomNow = zoomOfCamera()
	speedNow = speedAt(zoomNow)
	WG.BarDroidDrawSpeed = speedNow
end

local function setSpeed(step)
	local i = pointHere()
	local speed = math.max(MIN_SPEED, math.min(MAX_SPEED, (i and points[i][2] or speedNow) + step))
	if i then
		points[i][2] = speed
	else
		points[#points + 1] = { zoomNow, speed }
		table.sort(points, function(a, b)
			return a[1] < b[1]
		end)
	end
	save()
	look()
end

local function remove()
	local i = pointHere()
	if i then
		table.remove(points, i)
		save()
		look()
	end
end

local function reset()
	points = {}
	save()
	look()
end

local DO = {
	minus = function() setSpeed(-STEP) end,
	plus = function() setSpeed(STEP) end,
	remove = remove,
	reset = reset,
	close = function() open = false end,
}

-- The curve in a box: x the zoom (near at the left), y the speed
local function drawCurve(x0, y0, x1, y1, style)
	local top = fullZoom()
	local near = math.min(120, top / 20)
	local function xOf(zoom)
		local t = (math.log(math.max(near, math.min(top, zoom))) - math.log(near)) / (math.log(top) - math.log(near))
		return x0 + (x1 - x0) * t
	end
	local most = 1.5
	for _, p in ipairs(points) do
		most = math.max(most, p[2] * 1.15)
	end
	local function yOf(speed)
		return y0 + (y1 - y0) * math.min(1, speed / most)
	end
	gl.Color(0, 0, 0, 0.35)
	gl.Rect(x0, y0, x1, y1)
	gl.Color(1, 1, 1, 0.14)
	gl.LineWidth(1)
	gl.BeginEnd(GL.LINES, function()
		gl.Vertex(x0, yOf(1))
		gl.Vertex(x1, yOf(1))
	end)
	gl.Color(style.BLUE[1], style.BLUE[2], style.BLUE[3], 0.95)
	gl.LineWidth(2)
	gl.BeginEnd(GL.LINE_STRIP, function()
		for i = 0, 48 do
			local zoom = near * (top / near) ^ (i / 48)
			gl.Vertex(xOf(zoom), yOf(speedAt(zoom)))
		end
	end)
	gl.LineWidth(1)
	for _, p in ipairs(points) do
		style.disc(xOf(p[1]), yOf(p[2]), 5, style.TEXT, 1)
	end
	style.disc(xOf(top), yOf(1), 5, style.TEXT, 1)
	local x = xOf(zoomNow)
	gl.Color(style.GOLD[1], style.GOLD[2], style.GOLD[3], 0.9)
	gl.BeginEnd(GL.LINES, function()
		gl.Vertex(x, y0)
		gl.Vertex(x, y1)
	end)
	style.disc(x, yOf(speedNow), 6, style.GOLD, 1)
	gl.Color(1, 1, 1, 1)
end

function widget:DrawScreen()
	if not open then
		return
	end
	local style, font = WG.BarDroidStyle, WG.fonts and WG.fonts.getFont()
	if not (style and font) then
		return
	end
	local vsx, vsy = Spring.GetViewGeometry()
	local size = style.size(0.017, 11)
	local pad = math.floor(size * 0.6)
	local w = math.floor(size * 24)
	local boxH, buttonH = math.floor(size * 3.6), math.floor(size * 2.2)
	local h = pad * 4 + size + boxH + buttonH
	-- (at the right, under the top bar: the middle of the screen stays free to try the speed there)
	local x0, y1 = vsx - w - pad, math.floor(vsy * 0.92)
	local y0 = y1 - h
	panel = { x0, y0, x0 + w, y1 }
	style.panel(x0, y0, x0 + w, y1, 1)
	font:Begin()
	font:SetOutlineColor(0, 0, 0, 0.6)
	font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 1)
	font:Print("Path speed", x0 + pad, y1 - pad - size * 0.85, size, "o")
	font:SetTextColor(style.GOLD[1], style.GOLD[2], style.GOLD[3], 1)
	font:Print(string.format("zoom %d   speed %d%%", zoomNow, speedNow * 100 + 0.5), x0 + w - pad, y1 - pad - size * 0.85, size, "ro")
	font:End()
	drawCurve(x0 + pad, y0 + pad * 2 + buttonH, x0 + w - pad, y0 + pad * 2 + buttonH + boxH, style)
	local list = { { "minus", "-" }, { "plus", "+" }, { "remove", "Remove" }, { "reset", "Reset" }, { "close", "Close" } }
	local gap = math.floor(pad * 0.6)
	local bw = math.floor((w - pad * 2 - gap * (#list - 1)) / #list)
	buttons = {}
	for i, b in ipairs(list) do
		local bx = x0 + pad + (i - 1) * (bw + gap)
		local by = y0 + pad
		buttons[i] = { b[1], bx, by, bx + bw, by + buttonH }
		style.fill(bx, by, bx + bw, by + buttonH, { 0.16, 0.16, 0.16, 0.95 }, 1)
		style.outline(bx, by, bx + bw, by + buttonH, { 1, 1, 1 }, 0.16, 1)
		-- (the words a little smaller, with air at both ends; - and + bigger: they are the buttons used)
		local bs = size * (#b[2] == 1 and 1.35 or 0.86)
		font:Begin()
		font:SetOutlineColor(0, 0, 0, 0.6)
		font:SetTextColor(style.TEXT[1], style.TEXT[2], style.TEXT[3], 1)
		font:Print(b[2], bx + bw / 2, by + buttonH / 2 - bs * 0.36, bs, "co")
		font:End()
	end
	gl.Color(1, 1, 1, 1)
end

function widget:IsAbove(x, y)
	return open and panel and x >= panel[1] and x <= panel[3] and y >= panel[2] and y <= panel[4]
end

function widget:MousePress(x, y)
	if not widget:IsAbove(x, y) then
		return false
	end
	for _, b in ipairs(buttons) do
		if x >= b[2] and x <= b[4] and y >= b[3] and y <= b[5] then
			DO[b[1]]()
			break
		end
	end
	return true
end

function widget:Update()
	local t = Spring.GetTimer()
	if lookedAt and Spring.DiffTimers(t, lookedAt) < LOOK_SECONDS then
		return
	end
	lookedAt = t
	look()
end

function widget:Initialize()
	load()
	look()
	WG.BarDroidPadSpeed = {
		toggle = function()
			open = not open
			if open then
				look()
			end
		end,
		isOpen = function()
			return open
		end,
		-- while the tuner is open the pad's D-pad and B are its own (bardroid_touch.lua asks before its actions)
		act = function(name)
			if not open then
				return false
			end
			if name == "idle_prev" then
				DO.minus()
			elseif name == "idle_next" then
				DO.plus()
			elseif name == "commander" then
				DO.remove()
			elseif name == "cancel" then
				DO.close()
			else
				return false
			end
			return true
		end,
		speedAt = speedAt, -- (tools/touch-widget-test.ps1)
		setPoints = function(list)
			points = list
			look()
		end,
	}
end

function widget:Shutdown()
	WG.BarDroidPadSpeed = nil
	WG.BarDroidDrawSpeed = nil
end
