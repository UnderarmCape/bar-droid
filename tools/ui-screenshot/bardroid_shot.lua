-- User widget for tools/ui-screenshot.ps1: once the game runs, a screenshot (screenshots/ in the write dir), then quit.
-- bardroid_shot_chat = 1: a few chat lines first (the chat's layout on the phone's screens).
-- bardroid_shot_ships = 1: ships moving across the water near the map's middle, the camera on them (their wakes).
function widget:GetInfo()
	return { name = "BAR Droid screenshot", desc = "Screenshot after the game started, then quit", author = "BAR Droid",
		layer = 0, enabled = true }
end

local CHAT = {
	"gg",
	"a:anyone have a spare con for the front? my left side is collapsing fast and I need help over here",
	"push mid now, their t2 air is coming",
	"a:nice!",
}
local chat = Spring.GetConfigInt("bardroid_shot_chat", 0) == 1
local ships = Spring.GetConfigInt("bardroid_shot_ships", 0) == 1
local SHOT_FRAME = ships and 330 or 150
local shotAt, quitAt, water

local function waterNearMiddle()
	local cx, cz, best, bestD = Game.mapSizeX / 2, Game.mapSizeZ / 2, nil, math.huge
	for x = 256, Game.mapSizeX - 256, 128 do
		for z = 256, Game.mapSizeZ - 256, 128 do
			local deep = true
			for _, d in ipairs({ { 0, 0 }, { 600, 0 }, { 0, 300 }, { 0, -300 } }) do
				deep = deep and Spring.GetGroundHeight(x + d[1], z + d[2]) < -40
			end
			local dist = (x - cx) ^ 2 + (z - cz) ^ 2
			if deep and dist < bestD then
				best, bestD = { x, z }, dist
			end
		end
	end
	return best
end

function widget:GameFrame(f)
	if chat and f >= 40 and f < 40 + #CHAT * 15 and (f - 40) % 15 == 0 then
		Spring.SendCommands("say " .. CHAT[(f - 40) / 15 + 1])
	end
	if ships and f == 20 then
		Spring.SendCommands("cheat 1") -- (takes effect a few frames later)
	elseif ships and f == 40 then
		water = waterNearMiddle()
		if water then
			Spring.SendCommands(string.format("give 6 armpship 0 @%d,0,%d", water[1], water[2]))
		else
			Spring.Echo("[uishot] no water near the middle of the map")
		end
	elseif ships and water and f == 70 then
		local n = 0
		for _, u in ipairs(Spring.GetAllUnits() or {}) do
			if UnitDefs[Spring.GetUnitDefID(u)].name == "armpship" then
				local ok = Spring.GiveOrderToUnit(u, CMD.MOVE, { water[1] + 600, Spring.GetGroundHeight(water[1] + 600, water[2]), water[2] }, 0)
				n = n + 1
				if n == 1 then
					Spring.Echo("[uishot] move order: " .. tostring(ok))
				end
			end
		end
		Spring.Echo(string.format("[uishot] %d ships at %d,%d ordered east", n, water[1], water[2]))
	elseif ships and water and f == 200 then
		for _, u in ipairs(Spring.GetAllUnits() or {}) do
			if UnitDefs[Spring.GetUnitDefID(u)].name == "armpship" then
				local x, _, z = Spring.GetUnitPosition(u)
				local vx, _, vz = Spring.GetUnitVelocity(u)
				Spring.Echo(string.format("[uishot] ship at %d,%d speed %.2f", x, z, math.sqrt(vx * vx + vz * vz)))
				break
			end
		end
		Spring.SetCameraTarget(water[1] + 300, 0, water[2], 0)
	elseif ships and water and f > 70 and f % 30 == 0 then
		local cs = Spring.GetCameraState()
		cs.px, cs.pz, cs.dist, cs.rx = water[1] + 300, water[2], 1400, 2.4
		Spring.SetCameraState(cs, 0)
	end
	if not shotAt and f >= SHOT_FRAME then
		shotAt = f
		Spring.SendCommands("screenshot png")
		Spring.Echo("[uishot] screenshot at frame " .. f)
	elseif shotAt and not quitAt and f >= shotAt + 30 then
		quitAt = f
		Spring.Echo("[uishot] done")
		Spring.SendCommands("quitforce")
	end
end
