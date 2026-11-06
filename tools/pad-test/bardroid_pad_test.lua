-- LuaUI widget for tools/pad-test.ps1: what a virtual gamepad (pad.evemu) did in a skirmish on the phone, through the app's
-- real pad path: LB + L3 held rides the commander, RT fires, the right stick looks, B leaves, the right stick zooms and LT
-- speeds it up, D-pad down is the commander, and the pad going away ends the pad's ways. The ride's squad also gets an
-- enemy unit, made visible by /globallos (as a unit captured in sight), which has to drop out. Not the pad's, but it needs
-- a game on the phone too: new render textures start as zeros (libbardroid_pace.so, BARDROID_TEX_ZERO; each round makes one,
-- counts what it holds, fills it and frees it, so that a later round gets its buffer back). Logs "[padtest] PASS|FAIL
-- <case>" and "[padtest] done".
function widget:GetInfo()
	return { name = "BAR Droid pad test", desc = "Reports what the virtual gamepad did", author = "BAR Droid", layer = 0, enabled = true }
end

local READY_FRAME = 300
local picked, com, lastDist, done = false, nil, nil, false
local rode, fired, firedAfter, yawFrom, yawTo, left, sawPad, sawCommander = false, false, false, nil, nil, false, false, false
local zoomSteps = {}
local fails = 0
local taken = nil -- the enemy unit put in the squad
local evenOrders = 0 -- the most orders seen laid out evenly in the order menu while the pad hid its own
local TEX_SIZES, TEX_ROUNDS = { { 85, 83 }, { 170, 166 }, { 340, 83 }, { 128, 128 } }, 40 -- (as BAR's unit-groups panel)
local texRound, texWait, texDirty = 0, 0, 0

local function enemyUnit()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if Spring.GetUnitTeam(unitID) ~= Spring.GetMyTeamID() then
			return unitID
		end
	end
end

local function check(case, ok, detail)
	if not ok then
		fails = fails + 1
	end
	Spring.Echo("[padtest] " .. (ok and "PASS " or "FAIL ") .. case .. (detail and (": " .. tostring(detail)) or ""))
end

local function finish()
	done = true
	check("LB + L3 held: rides the unit", rode)
	check("RT: a target while it is held", fired)
	check("RT let go: the target gone", firedAfter)
	check("the right stick looks round", yawFrom and yawTo and math.abs(yawTo - yawFrom) > 0.3, tostring(yawFrom) .. " -> " .. tostring(yawTo))
	check("B: the ride over, the unit selected again", left)
	table.sort(zoomSteps)
	local slow, fast = zoomSteps[2], zoomSteps[#zoomSteps]
	check("LT speeds the zoom up", slow and fast and fast > slow * 1.8, tostring(slow) .. " -> " .. tostring(fast))
	check("D-pad down: the commander", sawCommander)
	-- (the app's copy of BAR's Order menu: skirmish plays BAR's game since v0.8.5's went, 2026-11-06)
	check("the app's order menu in skirmish", WG.ordermenu ~= nil and WG.ordermenu.droidCells ~= nil)
	check("the pad's orders hidden: the rest fill the order menu, one cell each", evenOrders > 0, evenOrders)
	check("the pad gone: its ways end, no taps needed", sawPad and WG.BarDroidPadOnly == nil)
	local fp = WG.BarDroidPadFP
	check("a unit no longer the player's leaves the squad", taken and fp and #fp.squad() == 0, tostring(taken))
	check("no new render texture holds an old picture", texRound == TEX_ROUNDS and texDirty == 0, texDirty .. " of " .. texRound .. " did")
	Spring.Echo("[padtest] done: " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
end

local function samplesHolding(tex, w, h)
	local n, last, samples = 0, nil, 0
	gl.RenderToTexture(tex, function()
		for y = 0, h - 1, 7 do
			for x = 0, w - 1, 7 do
				local r, g, b, a = gl.ReadPixels(x, y, 1, 1)
				samples = samples + 1
				if r ~= 0 or g ~= 0 or b ~= 0 or a ~= 0 then
					n, last = n + 1, string.format("%.2f %.2f %.2f %.2f", r, g, b, a)
				end
			end
		end
	end)
	return n, samples, last
end

function widget:DrawScreen()
	texWait = texWait + 1
	if texWait < 6 or texRound >= TEX_ROUNDS or Spring.GetGameFrame() < 30 then
		return
	end
	texWait = 0
	texRound = texRound + 1
	local s = TEX_SIZES[texRound % #TEX_SIZES + 1]
	local tex = gl.CreateTexture(s[1], s[2], { target = GL.TEXTURE_2D, format = GL.RGBA, fbo = true })
	local n, samples, last = samplesHolding(tex, s[1], s[2])
	if n > 0 then -- (a recycled buffer fills the whole texture; a few white pixels turn up on some runs, cause not known)
		texDirty = texDirty + (n > samples / 2 and 1 or 0)
		Spring.Echo(string.format("[padtest] a new %dx%d texture held something, game frame %d: %d of %d samples, %s", s[1], s[2],
			Spring.GetGameFrame(), n, samples, last))
	end
	gl.RenderToTexture(tex, function()
		gl.Clear(GL.COLOR_BUFFER_BIT, 1, 0, 1, 1)
	end)
	gl.DeleteTexture(tex)
end

function widget:GameFrame(f)
	if done then
		return
	end
	if f == READY_FRAME - 90 then
		Spring.SendCommands("cheat 1")
	elseif f == READY_FRAME - 45 then
		Spring.SendCommands("globallos")
	elseif f == READY_FRAME then
		Spring.Echo("[padtest] ready")
	end
	if f >= READY_FRAME and not picked then -- (BAR's game since v0.8.5's went: the app's controls from the start)
		picked = true
		com = Spring.GetTeamUnits(Spring.GetMyTeamID())[1]
		Spring.SelectUnitArray({ com })
	end
	if not picked then
		return
	end
	local fp = WG.BarDroidPadFP
	local riding = fp and fp.active()
	local target = Spring.GetUnitWeaponTarget(com, 1)
	local cs = Spring.GetCameraState()
	sawPad = sawPad or WG.BarDroidPadOnly == true
	local o = WG.ordermenu
	if WG.BarDroidPadOrders and o and o.droidCells then -- (BAR's grid has at least 16 cells, the even layout one an order)
		local rects, cmds = o.droidCells()
		if #cmds > 0 and #rects == #cmds then
			evenOrders = math.max(evenOrders, #cmds)
		end
	end
	if riding then
		if not rode then
			taken = enemyUnit()
			if taken then
				table.insert(fp.squad(), taken)
			end
		end
		rode = true
		if target and target > 0 then
			fired = true
		elseif fired then
			firedAfter = true
		end
		yawFrom = yawFrom or cs.ry
		yawTo = cs.ry
	elseif rode then
		left = left or (Spring.GetSelectedUnits()[1] == com)
	end
	if left and f % 15 == 0 and cs.dist then
		if lastDist and lastDist / cs.dist > 1.02 then
			zoomSteps[#zoomSteps + 1] = math.log(lastDist / cs.dist)
		end
		lastDist = cs.dist
	end
	local _, note = WG.BarDroidPad.note()
	sawCommander = sawCommander or (note == "COMMANDER")
	if sawPad and WG.BarDroidPadOnly == nil then
		finish()
	end
end
