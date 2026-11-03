-- BAR Droid info: the unit info panel (bottom left) laid out for a phone (Kailil, 2026-10-27: "the text on the selected
-- unit menu ... does not fit the box. the text is too large and it is jumbled up"). BAR's Info widget sizes its text
-- by the interface scale (2.0 on the Fold's cover screen, 1.3 on the inner one) but makes the panel narrower on wide
-- screens, and starts its text column 18% in while the unit picture is 4.4 text heights wide: the stats ran under the
-- picture and off the bottom of the screen. This panel takes the same place (BAR's other bottom menus are laid out
-- around it) and the same numbers (BAR's own calculation, ported from gui_info.lua, GPL-2.0-or-later), and picks the
-- largest text size at which everything fits; lines below the unit picture use the panel's full width.
--   one unit (selected, or under the pointer with nothing selected): picture, name, description, health, stats
--   a building or unit to build (the build menu under the pointer, a building being placed): the same for its type
--   several units selected: their types in a grid with counts; tap a type to keep only it, long-press to drop it
-- launch-bar.sh switches BAR's Info widget off; this one stands down if BAR's runs anyway (WG.info is BAR's then).
-- Installed into LuaUI/Widgets by the app.

function widget:GetInfo()
	return {
		name = "BAR Droid info",
		desc = "The unit info panel laid out for a phone: text sized to fit the panel",
		author = "BAR Droid (stats: BAR's gui_info.lua)",
		license = "GPL-3.0-or-later",
		layer = 0,
		enabled = true,
	}
end

local MIN_TEXT, MAX_TEXT_LINES = 8, 6.2 -- smallest text (pixels); the largest: panel height / this
local REFRESH = 0.25 -- seconds between rebuilding a shown unit's text (health, experience)
local PICK_EVERY = 0.1 -- seconds between looking again at what to show (and at once when the selection changes)
local LABEL, VALUE, DIM = "\255\175\175\175", "\255\255\255\255", "\255\200\200\200"
local KEEP = "\1" -- a space inside one stat, its label and value (wrap breaks lines only between stats)

local floor, max, min = math.floor, math.max, math.min
local spGetUnitDefID = Spring.GetUnitDefID
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount

local function round(v, digits)
	local m = 10 ^ (digits or 0)
	return floor(v * m + 0.5) / m
end

-- a number as text with at most that many decimals ("0.4", not "0.40000001")
local function num(v, digits)
	local s = string.format("%." .. (digits or 0) .. "f", v)
	if s:find("%.") then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return s
end

-- A price as BAR's build menu beside the panel prints it: a space every three digits ("1 150", "26 000"; its AddSpaces)
local function price(v)
	v = math.floor(v + 0.5)
	if v >= 1000 then
		return string.format("%s %03d", price(math.floor(v / 1000)), v % 1000)
	end
	return tostring(v)
end

-- BAR's translation of one of gui_info.lua's labels (all exist in BAR's language files; an unknown key logs a warning),
-- looked up once per label (the stats text is rebuilt four times a second; each key has one set of params)
local translated = {}
local function L(key, english, params)
	local s = translated[key]
	if s == nil then
		local ok, t = pcall(function() return BAR.I18N(key, params) end)
		s = (ok and type(t) == "string" and t ~= "" and t ~= key) and t or english
		translated[key] = s
	end
	return s
end

--------------------------------------------------------------------------------
-- What BAR's Info widget knows about a unit type (gui_info.lua refreshUnitInfo), worked out the first time it is shown

local weaponsLib
do
	-- (Lua's own functions too: BAR's file of 2026-10 calls tonumber, and with only math and Game every beam laser's
	-- unit, the commander's too, lost all its stats in BAR's released game)
	local env = { math = math, Game = Game, tonumber = tonumber, tostring = tostring, type = type, pairs = pairs,
		ipairs = ipairs, select = select, next = next, string = string, table = table, error = error, assert = assert,
		pcall = pcall, unpack = unpack, setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget }
	local ok, lib = pcall(VFS.Include, "common/weapons.lua", env)
	weaponsLib = ok and type(lib) == "table" and lib.GetDamagePerSecond and lib or nil
end

local armorIndex = {}
for i = 1, #Game.armorTypes do
	armorIndex[Game.armorTypes[i]] = i
end
local SHOW_WEAPON_GROUPS = { ["0"] = true, ["1"] = true } -- <0 fake weapons, 0 always active, 1 primary set
local FIRST_WEAPON_ONLY = { armcom = true, corcom = true, legcom = true, corkarg = true, armguard = true,
	corpun = true, legcluster = true, leglob = true, legnavyfrigate = true, armamb = true, cortoast = true,
	armvang = true }

local function hasBuilderTrait(def)
	return def.isFactory or next(def.buildOptions) ~= nil
		or (not def.isFactory and (def.canAssist
			or (def.buildDistance > 0 and (def.canCapture or def.canReclaim or def.canRepair or def.canRestore))))
end

local defCache = {}
local defInfo

local function computeDef(id)
	local ud = UnitDefs[id]
	local info = {}
	info.name = (ud.translatedHumanName or ud.humanName or ud.name):gsub("Scavenger", "Scav")
	info.description = ud.translatedTooltip or ud.tooltip or ""
	info.airUnit = ud.isAirUnit or nil
	if ud.maxWeaponRange > 16 then
		info.maxWeaponRange = ud.maxWeaponRange
	end
	if ud.speed > 0 then
		local inWater = tonumber(ud.customParams.speedfactorinwater or 1) or 1
		if inWater == 1 then
			info.speed = round(ud.speed)
		else
			local wet = round(ud.speed * min(max(inWater, 0), 1e4))
			info.speedMin, info.speedMax = min(ud.speed, wet), max(ud.speed, wet)
		end
	end
	if ud.rSpeed > 0 then
		info.reverseSpeed = round(ud.rSpeed)
	end
	info.stealth = ud.stealth or nil
	if ud.cloakCost and ud.canCloak then
		info.cloakCost = ud.cloakCost
		if ud.cloakCostMoving > ud.cloakCost then
			info.cloakCostMoving = ud.cloakCostMoving
		end
	end
	if ud.isTransport then
		info.transport = { ud.transportMass, ud.transportSize, ud.transportCapacity }
	end
	for _, k in ipairs({ "sightDistance", "airSightDistance", "radarDistance", "sonarDistance", "radarDistanceJam",
		"sonarDistanceJam", "seismicDistance" }) do
		if (ud[k] or 0) > 0 then
			info[k] = ud[k]
		end
	end
	if ud.customParams.energyconv_capacity and ud.customParams.energyconv_efficiency then
		info.metalmaker = { tonumber(ud.customParams.energyconv_capacity), tonumber(ud.customParams.energyconv_efficiency) }
	end
	info.energyCost, info.metalCost = ud.energyCost, ud.metalCost
	info.energyStorage, info.metalStorage = ud.energyStorage, ud.metalStorage
	info.health = ud.health
	if ud.buildSpeed > 0 and hasBuilderTrait(ud) then
		info.buildSpeed = ud.buildSpeed
	end

	local weapons = ud.weapons
	local exempt = false
	local function addPrimary(lo, hi)
		info.mindps = (info.mindps or 0) + lo
		info.maxdps = (info.maxdps or 0) + hi
	end
	local function addSecondary(_, hi)
		info.maxdps = (info.maxdps or 0) + hi
	end
	local function laserDPS(def, damage)
		if weaponsLib then -- (BAR's own sum; should a later version of it fail here, the plain one below)
			local ok, lo, hi = pcall(weaponsLib.GetDamagePerSecond, def, damage)
			if ok and lo then
				return lo, hi or lo
			end
		end
		local d = damage * def.projectiles / def.reload
		return d, d
	end
	local function weaponDPS(def, damage)
		local reload = damage * (def.salvoSize * def.projectiles) / def.reload
		local stock = damage * (def.salvoSize * def.projectiles) / (def.stockpile and def.stockpileTime / 30 or def.reload)
		return min(reload, stock), max(reload, stock)
	end
	local function clusterDPS(def, damage)
		local munition = WeaponDefNames[ud.name .. "_" .. def.customParams.cluster_def]
		local main = (def.salvoSize * def.projectiles) / def.reload * damage
		local sub = munition and (def.salvoSize * def.projectiles) / def.reload
			* ((tonumber(def.customParams.cluster_number) or 0) * munition.damages[0]) or 0
		return main, main + sub
	end
	local function areaDPS(def, damage)
		local burst = def.salvoSize * def.projectiles
		local impact = damage * burst / def.reload
		local area = tonumber(def.customParams.area_onhit_damage) or 0
		return impact, max(impact + area, area * burst * (tonumber(def.customParams.area_onhit_time) or 0) / def.reload)
	end
	local function shotCosts(def)
		if def.energyCost > 0 and (not info.energyPerShot or def.energyCost > info.energyPerShot) then
			info.energyPerShot = def.energyCost
		end
		if def.metalCost > 0 and (not info.metalPerShot or def.metalCost > info.metalPerShot) then
			info.metalPerShot = def.metalCost
		end
	end

	local function weapon(i, wd, primary)
		info.weapons[i] = wd
		if primary and weapons[i].onlyTargets.vtol then
			info.isAaUnit = true
		end
		local add = primary and addPrimary or addSecondary
		if wd.interceptor ~= 0 and wd.coverageRange then
			info.maxCoverage = max(info.maxCoverage or 1, wd.coverageRange)
			return
		elseif wd.shieldRadius and wd.shieldRadius > 0 then
			if #weapons == 1 then
				info.weapons, info.shieldOnly = {}, true
			end
			info.shieldRange, info.shieldCapacity = wd.shieldRadius, wd.shieldPower
			info.shieldRechargeRate, info.shieldRechargeCost = wd.shieldPowerRegen, wd.shieldPowerRegenEnergy
			return
		end
		local cp = wd.customParams
		if ud.customParams.weapons_smart_select and (cp.smart_priority or cp.smart_backup or cp.smart_trajectory_checker) then
			exempt = true
			if cp.smart_priority then
				add(weaponDPS(wd, wd.damages[0]))
			end
		elseif ud.customParams.evocomlvl or FIRST_WEAPON_ONLY[ud.name] then
			exempt = true
			if i == 1 then
				shotCosts(wd)
				if wd.type == "BeamLaser" then
					add(laserDPS(wd, wd.damages[0]))
				elseif cp.cluster then
					add(clusterDPS(wd, wd.damages[0]))
				elseif weapons[i].onlyTargets.vtol ~= nil then
					add(weaponDPS(wd, wd.damages[armorIndex.vtol]))
				else
					add(weaponDPS(wd, wd.damages[0]))
				end
			end
		elseif ud.name == "corkorg" then
			exempt = true
			if i == 1 or i == 3 then
				add(weaponDPS(wd, wd.damages[0]))
			elseif i == 2 then
				shotCosts(wd)
				add(laserDPS(wd, wd.damages[0]))
			end
		elseif cp.area_onhit_damage and cp.area_onhit_time then
			exempt = true
			add(areaDPS(wd, wd.damages[0]))
		elseif cp.cluster then
			exempt = true
			add(clusterDPS(wd, wd.damages[0]))
		elseif cp.speceffect == "split" then
			exempt = true
			local split = WeaponDefNames[cp.speceffect_def]
			add(weaponDPS(wd, (split and split.damages[0] or 0) * (tonumber(cp.number) or 1)))
		elseif cp.spark_forkdamage then
			exempt = true
			add(weaponDPS(wd, wd.damages[0]))
			addSecondary(weaponDPS(wd, wd.damages[0] * (tonumber(cp.spark_forkdamage) or 0)))
			if wd.paralyzer then
				info.minemp, info.maxemp, info.mindps, info.maxdps = info.mindps, info.maxdps, nil, nil
			end
		end
		if info.mainWeapon == 0 then
			info.mainWeapon = i
			info.range = wd.range
			info.reloadTime = cp.dronesuesestockpile and wd.stockpileTime or wd.reload
		end
		local vtolFirst = weapons[1].onlyTargets.vtol ~= nil
		if wd.type == "BeamLaser" and not exempt then
			shotCosts(wd)
			if wd.paralyzer ~= true then
				add(laserDPS(wd, vtolFirst and wd.damages[armorIndex.vtol] or wd.damages[0]))
			else
				local lo, hi = laserDPS(wd, wd.damages[0])
				info.minemp, info.maxemp = (info.minemp or 0) + lo, (info.maxemp or 0) + hi
			end
		elseif wd.paralyzer == true and ud.name ~= "armthor" then
			local emp = floor(wd.damages[0] * wd.salvoSize / wd.reload)
			info.minemp, info.maxemp, info.range, info.reloadTime = emp, emp, wd.range, wd.reload
		end
		if wd.type ~= "BeamLaser" and wd.paralyzer ~= true and not exempt then
			local damage = vtolFirst and wd.damages[armorIndex.vtol] or wd.damages[0]
			if damage > 0 then
				add(weaponDPS(wd, damage))
				shotCosts(wd)
			end
		end
	end

	for i = 1, #weapons do
		if not info.weapons then
			info.weapons, info.mindps, info.maxdps, info.range, info.reloadTime, info.mainWeapon = {}, 0, 0, 0, 0, 0
		end
		local wd = WeaponDefs[weapons[i].weaponDef]
		if SHOW_WEAPON_GROUPS[wd.customParams.weapons_group] and wd.customParams.bogus ~= "1" then
			weapon(i, wd, wd.customParams.weapons_role ~= "secondary")
		end
	end
	if info.mainWeapon == 0 then
		info.mainWeapon = 1 -- all the unit's weapons were fakes
	end
	if ud.customParams.unitgroup == "explo" and ud.deathExplosion and WeaponDefNames[ud.deathExplosion] then
		local wd = WeaponDefs[WeaponDefNames[ud.deathExplosion].id]
		if wd then
			local dmg = wd.damages[Game.armorTypes.default]
			info.mindps, info.maxdps, info.reloadTime = dmg, dmg, nil
		end
	end
	-- carriers: their drones' damage
	for _, w in ipairs(weapons) do
		local cp = WeaponDefs[w.weaponDef].customParams
		local drone = cp.carried_unit and UnitDefNames[cp.carried_unit]
		if drone and drone.id ~= id then
			local d = defInfo(drone.id)
			local count = tonumber(cp.maxunits) or 1
			for _, k in ipairs({ "mindps", "minemp" }) do
				if d[k] then
					info[k] = info[k] or 0
				end
			end
			for _, k in ipairs({ "maxdps", "maxemp" }) do
				if d[k] then
					info[k] = (info[k] or 0) + d[k] * count
				end
			end
		end
	end
	for _, k in ipairs({ "mindps", "maxdps", "minemp", "maxemp" }) do
		if type(info[k]) == "number" then
			info[k] = floor(info[k])
		end
	end
	return info
end

defInfo = function(id)
	local info = defCache[id]
	if not info then
		local ok, result = pcall(computeDef, id)
		if not ok then -- (the plain fallback below shows; the log says why, once per unit type)
			Spring.Echo("[bardroid_info] no stats for " .. tostring(UnitDefs[id].name) .. ": " .. tostring(result))
		end
		info = ok and result or { name = UnitDefs[id].humanName or "?", description = "", health = UnitDefs[id].health,
			metalCost = UnitDefs[id].metalCost, energyCost = UnitDefs[id].energyCost, energyStorage = 0, metalStorage = 0 }
		defCache[id] = info
	end
	return info
end

-- The stats line, in BAR's order and words (gui_info.lua drawUnitInfo)
local function statsText(id, unitID)
	local info = defInfo(id)
	local parts = {}
	local function add(label, value) -- (its spaces kept from wrap: a line never ends between "M storage" and its 500)
		local part = LABEL .. label:sub(1, 1):upper() .. label:sub(2) .. (value and (VALUE .. " " .. value) or "")
		parts[#parts + 1] = part:gsub(" ", KEEP)
	end
	local maxRange, exp
	if unitID then
		maxRange = info.mainWeapon and Spring.GetUnitWeaponState(unitID, info.mainWeapon, "range") or info.range
		exp = Spring.GetUnitExperience(unitID)
	elseif info.maxWeaponRange then
		maxRange = info.range
	end
	if info.weapons then
		local speedup, reload = 1, info.reloadTime
		if exp and exp > 0.009 then
			add(L("ui.info.xp", "xp"), num(exp, 2))
			local _, maxHealth = Spring.GetUnitHealth(unitID)
			if maxHealth and info.health and info.health > 0 then
				add(L("ui.info.maxhealth", "max health"), "+" .. round((maxHealth / info.health - 1) * 100) .. "%")
			end
			reload = Spring.GetUnitWeaponState(unitID, info.mainWeapon, "reloadTimeXP") or reload
			if info.reloadTime and info.reloadTime > 0 and reload then
				speedup = reload / info.reloadTime
				local pct = round((1 - speedup) * 100)
				if pct > 0 then
					add(L("ui.info.reload", "reload"), "-" .. pct .. "%")
				end
			end
		end
		local lo, hi = info.mindps, info.maxdps
		if lo and lo > 0 and lo == hi then
			add(L("ui.info.dps", "DPS"), num(lo / speedup))
		elseif lo ~= hi then
			add("DPS", num((lo or 0) / speedup) .. "-" .. num((hi or 0) / speedup))
		end
		lo, hi = info.minemp, info.maxemp
		if lo and lo > 0 and lo == hi then
			add("DPS(EMP)", num(lo / speedup))
		elseif lo ~= hi then
			add("DPS(EMP)", num((lo or 0) / speedup) .. "-" .. num((hi or 0) / speedup))
		end
		if info.maxCoverage then
			add(L("ui.info.coverrange", "coverage"), info.maxCoverage)
		elseif maxRange and not info.shieldOnly then
			add(L("ui.info.weaponrange", "range"), floor(maxRange))
		end
		if reload and reload > 0 then
			add(L("ui.info.reloadtime", "reload"), num(reload, 2))
		end
		if info.energyPerShot then
			add(L("ui.info.energyshot", "energy/shot"), info.energyPerShot)
		end
		if info.metalPerShot then
			add(L("ui.info.metalshot", "metal/shot"), info.metalPerShot)
		end
	end
	if info.shieldCapacity then
		add(L("ui.info.shieldcapacity", "shield"), info.shieldCapacity)
		add(L("ui.info.shieldrange", "shield range"), info.shieldRange)
		add(L("ui.info.shieldrechargerate", "recharge"), info.shieldRechargeRate)
		add(L("ui.info.shieldrechargecost", "recharge cost"), info.shieldRechargeCost)
	end
	if info.stealth then
		add(L("ui.info.stealthy", "stealthy"))
	end
	if info.cloakCost then
		add(L("ui.info.cloakcost", "cloak cost"), info.cloakCost .. (info.cloakCostMoving and ("/" .. info.cloakCostMoving) or ""))
	end
	if info.speed then
		add(L("ui.info.speed", "speed"), info.speed)
	elseif info.speedMin then
		add(L("ui.info.speed", "speed"), info.speedMin .. "-" .. info.speedMax)
	end
	if info.reverseSpeed then
		add(L("ui.info.reversespeed", "reverse speed"), info.reverseSpeed)
	end
	if info.buildSpeed then
		add(L("ui.info.buildpower", "buildpower"), info.buildSpeed)
	end
	if info.sightDistance then
		add(L("ui.info.los", "LoS"), num(info.sightDistance))
	end
	if info.airSightDistance and (info.airUnit or info.isAaUnit) then
		add(L("ui.info.airlos", "air LoS"), num(info.airSightDistance))
	end
	for _, s in ipairs({ { "radarDistance", "ui.info.radar", "radar" }, { "sonarDistance", "ui.info.sonar", "sonar" },
		{ "radarDistanceJam", "ui.info.jamrange", "jammer" }, { "sonarDistanceJam", "ui.info.sonarjamrange", "sonar jammer" },
		{ "seismicDistance", "ui.info.seismic", "seismic" } }) do
		if info[s[1]] then
			add(L(s[2], s[3]), num(info[s[1]]))
		end
	end
	if info.metalmaker then
		add(L("ui.info.eneededforconversion", "E needed"), info.metalmaker[1])
		add(L("ui.info.convertedm", "converted M"), num(info.metalmaker[1] * info.metalmaker[2], 1))
	end
	if (info.energyStorage or 0) > 0 then
		add(L("ui.info.estorage", "E storage"), info.energyStorage)
	end
	if (info.metalStorage or 0) > 0 then
		add(L("ui.info.mstorage", "M storage"), info.metalStorage)
	end
	if info.transport then
		if info.transport[1] < 5001 then
			add(L("ui.info.transport_light", "light transport", { highlightColor = VALUE }))
		else
			add(L("ui.info.transport_heavy", "heavy transport", { highlightColor = VALUE }))
		end
		add(L("ui.info.transportcapacity", "capacity"), info.transport[3])
	end
	if unitID then
		-- made and used, a side of nothing left out ("Metal +2 -0" for a commander standing still)
		local function flow(make, use)
			local sides = {}
			if make > 0.05 then
				sides[#sides + 1] = "\255\180\255\180+" .. num(make, 1)
			end
			if use > 0.05 then
				sides[#sides + 1] = "\255\255\180\180-" .. num(use, 1)
			end
			return table.concat(sides, " ")
		end
		local mMake, mUse, eMake, eUse = Spring.GetUnitResources(unitID)
		if mMake and (mMake > 0.05 or mUse > 0.05) then
			add(L("ui.info.metal", "metal"), flow(mMake, mUse))
		end
		if eMake and (eMake > 0.05 or eUse > 0.05) then
			add(L("ui.info.energy", "energy"), flow(eMake, eUse))
		end
	end
	-- (BAR prints it on the picture) metal white, energy yellow; a cost of nothing left out ("Cost 155 0": a solar)
	local cost = {}
	if (info.metalCost or 0) > 0 then
		cost[#cost + 1] = "\255\235\235\235" .. price(info.metalCost)
	end
	if (info.energyCost or 0) > 0 then
		cost[#cost + 1] = "\255\255\255\150" .. price(info.energyCost)
	end
	if #cost > 0 then
		add("Cost", table.concat(cost, "   ")) -- (wider than a price's own spaces: "2 700   26 000")
	end
	return table.concat(parts, LABEL .. ",  ")
end

--------------------------------------------------------------------------------
-- Layout

local vsx, vsy = Spring.GetViewGeometry()
local rect = { 0, 0, 0, 0 } -- left, bottom, right, top (BAR's Info panel's place)
local widthFrac, heightFrac = 0, 0
local font, bold, pad
local background
-- What the panel shows (picture, text, health) recorded once per rebuild and replayed every frame: printed afresh each
-- frame it cost 4 ms a second with the pointer resting on a unit (laptop, BAR's benchmark, 2026-10-27), for text that
-- changes four times a second at most (REFRESH).
local content
local drawn -- what the recorded drawing shows (a unit's: its picture, text and health line), to keep it while that stays
local fitKey -- what the text size was fitted for (the text and the panel)
local function dropContent()
	if content then
		gl.DeleteList(content)
		content = nil
	end
	drawn = nil
end
local stub -- our WG.info
local standDown, overlay = false, false

-- The layout editor's settings for the panel (bardroid_layout.lua): moved by dx, dy (of the screen), size, the largest
-- text size (the text still fits the panel), padding
local NO_EDITS = { dx = 0, dy = 0, size = 1, text = 1, pad = 1 }
local function edits()
	local editor = WG.BarDroidLayout
	return editor and editor.get("info") or NO_EDITS
end

local orderX, orderY -- BAR's order menu's place the last layout kept clear of (layout, Update)
local function layout()
	vsx, vsy = Spring.GetViewGeometry()
	local ui = Spring.GetConfigFloat("ui_scale", 1) or 1
	local e = edits()
	widthFrac = floor(0.2125 / (vsx / vsy) * 1.78 * ui * e.size * vsx) / vsx
	heightFrac = floor(0.14 * ui * e.size * vsy) / vsy
	local w, h = floor(widthFrac * vsx), floor(heightFrac * vsy)
	local x0 = max(0, min(vsx - w, floor(e.dx * vsx)))
	local y0 = max(0, min(vsy - h, floor(e.dy * vsy)))
	-- BAR's order menu sits right of the Info panel's default width and moves for nothing (gui_ordermenu.lua posX): a
	-- panel made bigger in the editor stops at its left edge, so D-Gun and the orders under it still take taps (where
	-- the order menu was when this ran: after a fold this panel, layer 0, lays out before it, layer 1; Update looks)
	local o = WG.ordermenu
	orderX, orderY = nil, nil
	if o and o.getPosition and o.getBottomPosition and o.getBottomPosition() then
		local ox, oy, _, oh = o.getPosition()
		orderX, orderY = ox, oy
		if ox and oh then
			local left = floor(ox * vsx) - (WG.FlowUI and WG.FlowUI.elementMargin or 0)
			if x0 < left and y0 < oy * vsy and y0 + h > (oy - oh) * vsy then
				w = max(1, min(w, left - x0))
				widthFrac = w / vsx
			end
		end
	end
	rect = { x0, y0, x0 + w, y0 + h }
	font = WG.fonts and WG.fonts.getFont() or font
	bold = WG.fonts and WG.fonts.getFont(2) or font
	pad = (WG.FlowUI and WG.FlowUI.elementPadding or 4) * e.pad
	if background then
		gl.DeleteList(background)
		background = nil
	end
	dropContent()
	fitKey = nil
end

-- Lines of text no wider than widthAt(line number) pixels at size; colour codes carried onto the next line.
local function lastColor(s)
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

-- (KEEP: a space no line breaks at, printed as a space)
local function wrap(f, text, size, widthAt, maxLines)
	local lines, line, color = {}, "", ""
	local function width()
		return widthAt(#lines + 1)
	end
	local function done()
		for i, l in ipairs(lines) do
			lines[i] = l:gsub(KEEP, " ")
		end
		return lines
	end
	for word in text:gmatch("%S+") do
		local candidate = (line == "" or line == color) and line .. word or line .. " " .. word
		if f:GetTextWidth((candidate:gsub(KEEP, " "))) * size > width() and line ~= "" and line ~= color then
			lines[#lines + 1] = line
			if maxLines and #lines >= maxLines then
				lines[#lines] = line .. "..."
				return done()
			end
			line = color .. word
		else
			line = candidate
		end
		color = lastColor(word) or color
	end
	if line ~= "" and line ~= color then
		lines[#lines + 1] = line
	end
	return done()
end

-- The largest text size at which name, description, health and stats fit the panel, on half-pixel steps: a binary
-- search (each try wraps the text again, measuring every word; stepping down from the largest size took up to ~30
-- tries, and the phone's widget profiler had this panel at 7.9% of the benchmark's running time, 2026-10-28)
local function fit(view)
	local x0, y0, x1, y1 = rect[1] + pad, rect[2] + pad, rect[3] - pad, rect[4] - pad
	local innerW, innerH = x1 - x0, y1 - y0
	local pic = floor(min(innerH, innerW * 0.3))
	local textX = x0 + pic + floor(pad * 1.5)
	local narrow, wide = x1 - textX, innerW
	local largest = max(MIN_TEXT, innerH / MAX_TEXT_LINES * edits().text)
	local function try(s)
		local nameSize, descSize, statSize = s * 1.12, s * 0.86, s
		local lh = s * 1.22
		local name = view.name
		while bold:GetTextWidth(name) * nameSize > narrow and #name > 3 do
			name = name:sub(1, -2)
		end
		if name ~= view.name then
			name = name:sub(1, -2) .. "..."
		end
		local used = nameSize * 1.25
		local desc = wrap(font, view.description, descSize, function() return narrow end, 2)
		used = used + #desc * descSize * 1.2
		local barH = view.health and floor(s * 1.05) or 0
		if barH > 0 then
			used = used + barH + s * 0.35
		end
		local top = used
		-- a line is as wide as the panel once its top is below the picture
		local function beside(n)
			return top + (n - 1) * lh < pic - s * 0.1
		end
		local stats = wrap(font, view.stats, statSize, function(n)
			return beside(n) and narrow or wide
		end)
		for i, line in ipairs(stats) do -- a stat that ends its line drops its comma (the break is the separator)
			stats[i] = line:gsub(",$", "")
		end
		used = used + #stats * lh
		return used <= innerH, { beside = beside, s = s, name = name, nameSize = nameSize, desc = desc, descSize = descSize,
			statSize = statSize, lh = lh, stats = stats, statsTop = top, barH = barH, pic = pic, textX = textX, x0 = x0, y1 = y1,
			x1 = x1 }
	end
	-- (the text only shrinks as the size does; the smallest size is taken whether it fits or not)
	local steps = max(0, math.ceil((largest - MIN_TEXT) / 0.5))
	local fits, result = try(largest)
	if fits or steps == 0 then
		return result
	end
	local lo, hi = 0, steps -- lo does not fit; hi fits, or is the smallest size
	local _, best = try(largest - steps * 0.5)
	while hi - lo > 1 do
		local mid = floor((lo + hi) / 2)
		local ok, r = try(largest - mid * 0.5)
		if ok then
			hi, best = mid, r
		else
			lo = mid
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- What to show

local cfgUnit, cfgDef, customType, customData
local shown -- { kind = "unit"|"def"|"units", id, unitID | types }
local view, laidOut, rebuildAt = nil, nil, 0
local cells = {} -- the grid: { x0, y0, x1, y1, defID, units }

local function selectedTypes()
	local sorted = Spring.GetSelectedUnitsSorted() or {}
	local types = {}
	for defID, units in pairs(sorted) do
		if type(defID) == "number" and type(units) == "table" and #units > 0 then
			types[#types + 1] = { defID = defID, units = units }
		end
	end
	table.sort(types, function(a, b)
		if #a.units ~= #b.units then
			return #a.units > #b.units
		end
		return a.defID < b.defID
	end)
	return types
end

local function pick()
	if WG.BarDroidSpectating then -- spectating by touch (bardroid_spectate.lua): no unit panel
		return nil
	end
	if customType == "unit" and customData and spGetUnitDefID(customData) then
		return { kind = "unit", id = spGetUnitDefID(customData), unitID = customData }
	end
	if cfgUnit and spGetUnitDefID(cfgUnit) then
		return { kind = "unit", id = spGetUnitDefID(cfgUnit), unitID = cfgUnit }
	end
	if cfgDef and UnitDefs[cfgDef] then
		return { kind = "def", id = cfgDef }
	end
	local hover = WG.buildmenu and WG.buildmenu.hoverID
	if hover and UnitDefs[hover] then
		return { kind = "def", id = hover }
	end
	local _, cmdID = Spring.GetActiveCommand()
	if cmdID and cmdID < 0 and UnitDefs[-cmdID] then
		return { kind = "def", id = -cmdID }
	end
	local count = spGetSelectedUnitsCount()
	if count == 1 then
		local unitID = Spring.GetSelectedUnits()[1]
		local id = unitID and spGetUnitDefID(unitID)
		if id then
			return { kind = "unit", id = id, unitID = unitID }
		end
	elseif count > 1 then
		local types = selectedTypes()
		if #types == 1 then -- (one type: its name and stats, the count on its picture; as a grid it was one big picture)
			return { kind = "def", id = types[1].defID, count = #types[1].units }
		end
		return { kind = "units", types = types }
	end
	local mx, my = Spring.GetMouseState()
	local what, unitID = Spring.TraceScreenRay(mx, my)
	if what == "unit" and spGetUnitDefID(unitID) then
		return { kind = "unit", id = spGetUnitDefID(unitID), unitID = unitID }
	end
	return nil
end

local function sameShown(a, b)
	if not (a and b) or a.kind ~= b.kind then
		return a == b
	end
	if a.kind == "units" then
		if #a.types ~= #b.types then
			return false
		end
		for i, t in ipairs(a.types) do
			if t.defID ~= b.types[i].defID or #t.units ~= #b.types[i].units then
				return false
			end
		end
		return true
	end
	return a.id == b.id and a.unitID == b.unitID and a.count == b.count
end

local function buildView()
	if not shown or shown.kind == "units" then
		dropContent()
		view, laidOut, fitKey = nil, nil, nil
		return
	end
	local info = defInfo(shown.id)
	local v = { name = info.name, description = info.description, stats = statsText(shown.id, shown.unitID) }
	if shown.unitID then
		local health, maxHealth, _, _, build = Spring.GetUnitHealth(shown.unitID)
		if health and maxHealth and maxHealth > 0 then
			v.health, v.maxHealth, v.build = health, maxHealth, build
		end
	end
	view = v
	-- the text size fitted again only when the text or the panel changed (health moves only the bar), the drawing
	-- recorded again only when what it shows changed: with the pointer on a battle both stay most of the time
	local key = v.name .. "\n" .. v.description .. "\n" .. v.stats .. (v.health and "\nh" or "") .. "\n" .. rect[3] .. "x" .. rect[4]
	if key ~= fitKey then
		fitKey, laidOut = key, fit(v)
		dropContent()
	end
	local now = shown.id .. "x" .. (shown.count or 1) .. "\n" .. (v.health and (floor(v.health) .. "/" .. floor(v.maxHealth) .. "/" .. floor((v.build or 1) * 100)) or "")
	if now ~= drawn then
		dropContent()
		drawn = now
	end
end

local function layoutGrid(types)
	dropContent()
	cells = {}
	local x0, y0, x1, y1 = rect[1] + pad, rect[2] + pad, rect[3] - pad, rect[4] - pad
	local w, h, n = x1 - x0, y1 - y0, #types
	local bestCell, bestCols = 0, 1
	for cols = 1, n do
		local rows = math.ceil(n / cols)
		local cell = min(w / cols, h / rows)
		if cell > bestCell then
			bestCell, bestCols = cell, cols
		end
	end
	local cell = floor(max(bestCell, 16))
	local cols = max(1, min(bestCols, floor(w / cell)))
	local rows = max(1, floor(h / cell))
	-- (in the middle of the panel: the room left over was all on the right)
	local left = x0 + floor((w - min(n, cols) * cell) / 2)
	local top = y1 - floor((h - min(rows, math.ceil(n / cols)) * cell) / 2)
	for i, t in ipairs(types) do
		if i > cols * rows then
			break
		end
		local c, r = (i - 1) % cols, floor((i - 1) / cols)
		local cx, cy = left + c * cell, top - (r + 1) * cell
		cells[#cells + 1] = { cx, cy, cx + cell, cy + cell, t.defID, t.units, more = (i == cols * rows and n > i) and (n - i) or nil }
	end
end

--------------------------------------------------------------------------------
-- Drawing

local function drawBackground()
	if not background then
		background = gl.CreateList(function()
			if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
				WG.FlowUI.Draw.Element(rect[1], rect[2], rect[3], rect[4], 0, 1, 0, 0)
			else
				gl.Color(0, 0, 0, 0.6)
				gl.Rect(rect[1], rect[2], rect[3], rect[4])
			end
		end)
	end
	gl.CallList(background)
end

local function drawPicture(defID, x0, y0, x1, y1)
	gl.Color(1, 1, 1, 1) -- (FlowUI's unit frame leaves a dimmed colour set: every picture after the first came out dark)
	if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Unit then
		WG.FlowUI.Draw.Unit(x0, y0, x1, y1, nil, 1, 1, 1, 1, 0.03, nil, nil, "#" .. defID)
	else
		gl.Color(1, 1, 1, 1)
		gl.Texture("#" .. defID)
		gl.TexRect(x0, y0, x1, y1)
		gl.Texture(false)
	end
end

-- The health bar in the shape of BAR's panels (corners a fifth of its height: a third read as a hexagon; never more
-- than half its width, so a sliver of health stays a bar)
local BAR_BACK = { 0, 0, 0, 0.45 }
local BAR_SHADE = 0.68 -- the health colours' brightness
local function roundBar(x0, y0, x1, y1, color)
	local f = WG.FlowUI
	local cs = min(floor((y1 - y0) / 5), floor((x1 - x0) / 2))
	if cs >= 1 and f and f.Draw and f.Draw.RectRound then
		f.Draw.RectRound(x0, y0, x1, y1, cs, 1, 1, 1, 1, color, color)
	elseif x1 > x0 then
		gl.Color(color)
		gl.Rect(x0, y0, x1, y1)
	end
end

local function drawUnitView()
	local l = laidOut
	local pic = l.pic
	gl.Color(1, 1, 1, 1)
	drawPicture(shown.id, l.x0, l.y1 - pic, l.x0 + pic, l.y1)
	if shown.count then -- (as the grid's cells print it, no larger than the name: on the big picture it outweighed it)
		local size = min(pic * 0.3, l.nameSize)
		bold:Begin()
		bold:Print(VALUE .. shown.count, l.x0 + pic - size * 0.25, l.y1 - pic + size * 0.3, size, "or")
		bold:End()
	end
	local y = l.y1
	bold:Begin()
	bold:Print(VALUE .. l.name, l.textX, y - l.nameSize * 0.95, l.nameSize, "o")
	bold:End()
	y = y - l.nameSize * 1.25
	font:Begin()
	for _, line in ipairs(l.desc) do
		font:Print(DIM .. line, l.textX, y - l.descSize * 0.95, l.descSize, "o")
		y = y - l.descSize * 1.2
	end
	font:End()
	if view.health then
		local barH = l.barH
		local x0, x1 = l.textX, l.x1
		local frac = max(0, min(1, view.health / view.maxHealth))
		local yb = y - barH - l.s * 0.15
		roundBar(x0, yb, x1, yb + barH, BAR_BACK)
		local label = floor(view.health) .. " / " .. floor(view.maxHealth)
		if view.build and view.build < 1 then
			-- under construction: the bar is the building's progress, in blue (as health it read as a damaged unit,
			-- orange at 18% built)
			frac = max(0, min(1, view.build))
			roundBar(x0, yb, x0 + (x1 - x0) * frac, yb + barH, { 0.22, 0.45, 0.78, 0.85 })
			label = "Building " .. floor(view.build * 100) .. "%"
		else
			-- (a deeper green to red: the white figures on full green were hard to read, dev phone 2026-11-03)
			local s = BAR_SHADE
			roundBar(x0, yb, x0 + (x1 - x0) * frac, yb + barH,
				{ min(1, 2 - frac * 2) * s, min(1, frac * 2) * s, 0.12, 0.85 })
		end
		gl.Color(1, 1, 1, 1)
		font:Begin()
		font:Print(VALUE .. label, (x0 + x1) / 2, yb + barH * 0.18, barH * 0.82, "oc")
		font:End()
	end
	y = l.y1 - l.statsTop
	font:Begin()
	for n, line in ipairs(l.stats) do
		local ly = y - n * l.lh
		local x = l.beside(n) and l.textX or l.x0
		font:Print(line, x, ly + l.lh * 0.18, l.statSize, "o")
	end
	font:End()
end

local function drawGrid()
	gl.Color(1, 1, 1, 1) -- (the background's drawing leaves its own colour)
	for _, c in ipairs(cells) do
		local inset = max(1, floor((c[3] - c[1]) * 0.03))
		drawPicture(c[5], c[1] + inset, c[2] + inset, c[3] - inset, c[4] - inset)
	end
	bold:Begin()
	for _, c in ipairs(cells) do
		local size = (c[3] - c[1]) * 0.3
		local text = c.more and ("+" .. c.more) or tostring(#c[6])
		bold:Print(VALUE .. text, c[3] - size * 0.25, c[2] + size * 0.3, size, "or")
	end
	bold:End()
end

function widget:DrawScreen()
	if standDown or overlay or not shown or Spring.IsGUIHidden() or not font then
		return
	end
	gl.Color(1, 1, 1, 1)
	drawBackground()
	if not content and (shown.kind == "units" or laidOut) then
		content = gl.CreateList(shown.kind == "units" and drawGrid or drawUnitView)
	end
	if content then
		gl.CallList(content)
	end
	gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Input

local function inRect(x, y, r)
	return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4]
end

function widget:IsAbove(x, y)
	return not standDown and not overlay and shown ~= nil and inRect(x, y, rect)
end

function widget:MousePress(x, y, button)
	if standDown or overlay or not shown or not inRect(x, y, rect) then
		return false
	end
	if shown.unitID and laidOut then -- the unit's picture: the camera to the unit (as BAR's panel)
		local l = laidOut
		if inRect(x, y, { l.x0, l.y1 - l.pic, l.x0 + l.pic, l.y1 }) then
			local ux, uy, uz = Spring.GetUnitPosition(shown.unitID)
			if ux then
				Spring.SetCameraTarget(ux, uy, uz, 0.4)
			end
			return true
		end
	end
	if shown.count and laidOut then -- one type's picture: the camera to the group (BAR's middle click on a cell)
		local l = laidOut
		if inRect(x, y, { l.x0, l.y1 - l.pic, l.x0 + l.pic, l.y1 }) then
			Spring.SendCommands("viewselection")
			return true
		end
	end
	if shown.kind == "units" then
		for _, c in ipairs(cells) do
			if inRect(x, y, c) then
				if button == 1 then -- only this type
					Spring.SelectUnitArray(c[6])
				elseif button == 3 then -- all but this type
					local keep, drop = {}, {}
					for _, u in ipairs(c[6]) do
						drop[u] = true
					end
					for _, u in ipairs(Spring.GetSelectedUnits()) do
						if not drop[u] then
							keep[#keep + 1] = u
						end
					end
					Spring.SelectUnitArray(keep)
				end
				return true
			end
		end
	end
	return true -- the panel takes the tap: no order to the map under it
end

function widget:RecvLuaMsg(msg)
	if msg:sub(1, 18) == "LobbyOverlayActive" then
		overlay = msg:sub(1, 19) == "LobbyOverlayActive1"
	end
end

--------------------------------------------------------------------------------
-- Life cycle

local elapsed, pickAt = 0, 0
local registered = false
function widget:SelectionChanged()
	pickAt = 0
end

function widget:Update(dt)
	if WG.info and WG.info ~= stub then -- BAR's own Info widget runs: it is the panel
		standDown = true
		return
	end
	standDown = false
	if not WG.info then
		WG.info = stub
	end
	if not font then
		layout()
	end
	local o = WG.ordermenu -- (its place since the last layout: moved after a fold, or by its own setting)
	if o and o.getPosition and o.getBottomPosition then
		local ox, oy
		if o.getBottomPosition() then
			ox, oy = o.getPosition()
		end
		if ox ~= orderX or oy ~= orderY then
			layout()
			rebuildAt = 0
			if shown and shown.kind == "units" then
				layoutGrid(shown.types)
			end
		end
	end
	local editor = WG.BarDroidLayout
	if editor and editor.register and not registered then -- the panel for the layout editor
		registered = true
		editor.register("info", {
			label = "Unit info",
			can = { move = true, size = true, text = true, pad = true },
			rect = function() return rect[1], rect[2], rect[3], rect[4] end,
			relayout = function()
				layout()
				rebuildAt = 0
				if shown and shown.kind == "units" then
					layoutGrid(shown.types)
				end
			end,
		})
	end
	elapsed = elapsed + dt
	if elapsed < pickAt then
		if shown and shown.kind ~= "units" and elapsed >= rebuildAt then
			rebuildAt = elapsed + REFRESH
			buildView()
		end
		return
	end
	pickAt = elapsed + PICK_EVERY
	local now = pick()
	if not sameShown(now, shown) then
		shown = now
		rebuildAt = 0
		if shown and shown.kind == "units" then
			layoutGrid(shown.types)
		end
	elseif shown and shown.kind == "units" then
		shown.types = now.types -- the same types, maybe other units
		layoutGrid(shown.types)
	end
	if shown and shown.kind ~= "units" and elapsed >= rebuildAt then
		rebuildAt = elapsed + REFRESH
		buildView()
	end
end

function widget:ViewResize()
	layout()
	rebuildAt = 0
	if shown and shown.kind == "units" then
		layoutGrid(shown.types)
	end
end

function widget:Initialize()
	stub = { -- what BAR's widgets ask of BAR's Info widget (gui_info.lua WG.info)
		getShowBuilderBuildlist = function() return false end,
		setShowBuilderBuildlist = function() end,
		getDisplayMapPosition = function() return false end,
		setDisplayMapPosition = function() end,
		getAlwaysShow = function() return false end,
		setAlwaysShow = function() end,
		displayUnitID = function(unitID) cfgUnit = unitID end,
		clearDisplayUnitID = function() cfgUnit = nil end,
		displayUnitDefID = function(defID) cfgDef = defID end,
		clearDisplayUnitDefID = function() cfgDef = nil end,
		getPosition = function() return widthFrac, heightFrac end,
		getIsShowing = function() return shown ~= nil and not standDown end,
		setCustomHover = function(kind, data) customType, customData = kind, data end,
		clearCustomHover = function() customType, customData = nil, nil end,
	}
	layout()
	-- the engine's own selection text and selected-unit count (bottom left), off as BAR's Info widget has them
	Spring.SendCommands("tooltip 0")
	Spring.SetDrawSelectionInfo(false)
end

function widget:Shutdown()
	if registered and WG.BarDroidLayout then
		WG.BarDroidLayout.unregister("info")
	end
	if WG.info == stub then
		WG.info = nil
		Spring.SendCommands("tooltip 1")
		Spring.SetDrawSelectionInfo(true)
	end
	if background then
		gl.DeleteList(background)
	end
	dropContent()
end
