-- LuaUI widget for tools/pad-test.ps1 -Shots: the pad's panels opened one at a time and screenshotted, for the user
-- guide's before/after pictures (build\pad-ui\). No pad: the pad widget's actions as the app sends them (a pad player's
-- screen, WG.BarDroidInput "pad"). Before each screenshot it logs "[padtest] shot <name> x0 y0 x1 y1": the piece's
-- rect in GL pixels (y up), the pad widget's own (WG.BarDroidPad.drawnRect) where it tells it, else worked out here;
-- pad-test.ps1 crops each screenshot to it. Then "[padtest] done".
function widget:GetInfo()
	return { name = "BAR Droid pad shots", desc = "The pad's panels, screenshotted", author = "BAR Droid", layer = -100000, enabled = true }
end

local READY_FRAME = 420
local STEP = 24 -- frames between the steps (a screenshot is the frame drawn last: taken a step after the piece opens)
local DRAWS = 6 -- and at least this many frames drawn since the step before (a slow draw left the share list in the note's)
local step, nextAt = 0, nil
local draws, drawsAt = 0, 0
local me, other, com = nil, nil, nil
local shots = 0

local function pad()
	return WG.BarDroidPad
end

local function unitsOf(name)
	local d = UnitDefNames[name]
	return d and Spring.GetTeamUnitsByDefs(me, d.id) or {}
end

local function clamp(r)
	local vsx, vsy = Spring.GetViewGeometry()
	return { math.max(0, math.floor(r[1])), math.max(0, math.floor(r[2])), math.min(vsx, math.ceil(r[3])),
		math.min(vsy, math.ceil(r[4])) }
end

-- the piece's rect: the pad widget's own as drawn, else a generous one from its old layout
local function rectOf(name)
	local P = pad()
	local vsx, vsy = Spring.GetViewGeometry()
	local S = WG.BarDroidStyle
	local o = WG.ordermenu
	if name == "orders" and o and o.getPosition then -- (the whole menu round the order on the pad)
		local px, py, w, h = o.getPosition()
		return clamp({ px * vsx, (py - h) * vsy, (px + w) * vsx, py * vsy })
	end
	local r = P.drawnRect and P.drawnRect(name == "dgun" and "dgunhud" or name == "groups-new" and "groups" or name)
	if name == "dgun" then -- (the commander's rings, and the mode's panel where there is one)
		local x, y, z = Spring.GetUnitPosition(com)
		local sx, sy = Spring.WorldToScreenCoords(x, y, z)
		local ex = Spring.WorldToScreenCoords(x + 300, y, z)
		local rr = math.max(80, math.abs(ex - sx) * 1.15)
		local c = { sx - rr, sy - rr, sx + rr, sy + rr }
		if r then
			c = { math.min(c[1], r[1]), math.min(c[2], r[2]), math.max(c[3], r[3]), math.max(c[4], r[4]) }
		end
		return clamp(c)
	end
	if r then
		return clamp(r)
	end
	if name == "groups" or name == "groups-new" then -- (the old strip's place: the order menu's top, else a tenth of the
		-- screen, over the dock upright)
		local size = S.size(0.048)
		local y0 = vsy * 0.1
		if o and o.getPosition and o.getIsShowing and o.getIsShowing() then
			y0 = select(2, o.getPosition()) * vsy
		end
		return clamp({ vsx * 0.2, y0, vsx * 0.8, y0 + size * 2 })
	elseif name == "radial" then
		local size = S.size(0.019)
		local rr = math.max(size * 2 * 2.2, vsy * 0.13)
		return clamp({ vsx / 2 - rr - size * 14, vsy / 2 - rr - size * 2, vsx / 2 + rr + size * 14, vsy / 2 + rr + size * 2 })
	elseif name == "share" or name == "share-units" then
		local s = P.shareRect()
		return s and clamp({ s[1], s[2], s[3], s[4] })
	elseif name == "note" then
		local t = P.toastRect()
		return t and clamp({ vsx * 0.25, t[1], vsx * 0.75, t[2] })
	elseif name == "queue" and o and o.getPosition and o.getIsShowing and o.getIsShowing() then -- (its old place)
		local px, py, w = o.getPosition()
		local x1, y0 = (px + w) * vsx, py * vsy + S.size(0.008, 3)
		return clamp({ x1 - S.size(0.11), y0, x1, y0 + S.size(0.036) })
	end
	return { 0, 0, vsx, vsy }
end

-- (a shot taken here, in this widget's DrawScreen: its layer under the pad widget's, so the pad's panels are drawn in
-- this frame already, and the engine reads the frame as drawn; asked from GameFrame, it read a frame of the step before)
local function shot(name)
	local r = rectOf(name) or { 0, 0, 0, 0 }
	shots = shots + 1
	Spring.Echo(string.format("[padtest] shot %s %d %d %d %d", name, r[1], r[2], r[3], r[4]))
	Spring.SendCommands("screenshot png")
end

local function pick(units)
	Spring.SelectUnitArray(units or {})
end

local function dockUp()
	local P = WG.BarDroidPortrait
	return P and P.active and P.active() or false
end

-- the steps: a function does its actions; a name, the piece's screenshot once a few frames show it ("?" at its end: only
-- with no dock up)
local STEPS = {
	function() -- units to make groups of, beside the commander (cheats on a step before: "give" in the same frame did nothing)
		local x, y, z = Spring.GetUnitPosition(com)
		for i, u in ipairs({ { "armpw", 6 }, { "armrock", 3 }, { "armck", 2 } }) do
			local ux, uz = x - 160 + i * 80, z + 120
			Spring.SendCommands(string.format("give %d %s %d @%d,%d,%d", u[2], u[1], me, ux, y, uz))
		end
		Spring.SetCameraTarget(x, y, z + 60, 0)
	end,
	function() -- (one group a step: the selection and "group set" in one frame each)
		pick(unitsOf("armpw"))
		Spring.SendCommands("group set 1")
	end,
	function()
		pick(unitsOf("armrock"))
		Spring.SendCommands("group set 2")
	end,
	function()
		pick(unitsOf("armck"))
		Spring.SendCommands("group set 3")
	end,
	function()
		pick({})
		Spring.Echo(string.format("[padtest] groups: %d, %d, %d units", #(Spring.GetGroupUnits(1) or {}),
			#(Spring.GetGroupUnits(2) or {}), #(Spring.GetGroupUnits(3) or {})))
		pad().act("group_show_2") -- the group list held (Start), the slot in use a group with units
		pad().act("group_list_on")
	end,
	"groups",
	function()
		pick(unitsOf("armpw"))
		pad().act("group_show_5") -- (the slot in use an empty one, units picked)
	end,
	"groups-new",
	function()
		pad().act("group_list_off")
		pick({})
		pad().act("area_on") -- (A held with nothing picked: the area select; X held: its filters, the stick left)
		pad().act("area_filter_open")
		pad().act("area_filter_left")
	end,
	"radial",
	function()
		pad().act("area_filter_close")
		pad().act("area_cancel")
		pad().shareTest({
			{ teamID = other, name = "Alpha", color = { 0.35, 0.75, 1 } },
			{ teamID = other, name = "Bravo", color = { 1, 0.45, 0.4 } },
			{ teamID = other, name = "Charlie", color = { 0.6, 0.9, 0.4 } },
		})
		pad().act("share_more")
	end,
	"share",
	function()
		pick(unitsOf("armpw"))
		for _ = 1, 3 do
			if select(9, pad().modal()) == 1 then
				break
			end
			pad().act("share_tab_prev")
		end
	end,
	"share-units",
	function()
		pad().act("share_cancel")
		pick({})
		pad().say("REPAIR: A")
	end,
	"note",
	function()
		pick({ com })
		pad().act("dgun")
	end,
	function() end, -- (the D-gun's aim a moment to settle)
	"dgun",
	function()
		pad().act("dgun_cancel")
		pick(unitsOf("armck"))
		pad().act("pad_orders")
	end,
	"orders",
	function()
		pad().act("pad_back")
		pick(unitsOf("armpw")) -- (QUEUE: a finger's button, units picked and no dock, sideways; on, as a tap leaves it)
		pad().queueOn(true)
	end,
	"queue?", -- (upright the dock's selection row is QUEUE: none of the pad's)
	function()
		pad().queueOn(false)
		pick({})
	end,
}

local pending, pendingDraws = nil, 0
function widget:GameFrame(f)
	if f == READY_FRAME then
		me = Spring.GetMyTeamID()
		for _, teamID in ipairs(Spring.GetTeamList() or {}) do
			local _, _, isDead = Spring.GetTeamInfo(teamID, false)
			if teamID ~= me and not isDead and teamID ~= Spring.GetGaiaTeamID() then
				other = teamID
				break
			end
		end
		for _, u in ipairs(Spring.GetTeamUnits(me) or {}) do
			local ud = UnitDefs[Spring.GetUnitDefID(u)]
			if ud and ud.customParams and ud.customParams.iscommander then
				com = u
			end
		end
		if not (pad() and pad().shareTest and other and com) then
			Spring.Echo("[padtest] FAIL no pad widget, other team or commander")
			Spring.Echo("[padtest] done: 1 FAILED")
			step = #STEPS + 1
			return
		end
		WG.BarDroidInput = "pad" -- (a pad player's screen, as a real pad's "src pad" makes it)
		Spring.SendCommands("cheat 1")
		Spring.Echo("[padtest] ready")
		nextAt = f + STEP
		return
	end
	if pending or not nextAt or f < nextAt or step > #STEPS or draws < drawsAt + DRAWS then
		return
	end
	drawsAt = draws
	step = step + 1
	local s = STEPS[step]
	if type(s) == "string" then
		local name, onlyBare = s:gsub("%?$", "")
		if onlyBare == 0 or not dockUp() then
			pending, pendingDraws = name, draws
		end
	else
		local ok, err = pcall(s)
		if not ok then
			Spring.Echo("[padtest] FAIL step " .. step .. ": " .. tostring(err))
		end
	end
	nextAt = f + STEP
	if step >= #STEPS then
		step = #STEPS + 1
	end
end

function widget:DrawScreen()
	draws = draws + 1
	if pending and draws >= pendingDraws + DRAWS then
		local ok, err = pcall(shot, pending)
		if not ok then
			Spring.Echo("[padtest] FAIL shot " .. pending .. ": " .. tostring(err))
		end
		pending, drawsAt = nil, draws
	end
	if step > #STEPS and not pending and nextAt then
		nextAt = nil
		Spring.Echo("[padtest] done: " .. shots .. " shots")
	end
end
