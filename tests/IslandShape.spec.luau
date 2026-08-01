--!nocheck
-- =====================================================================================
-- Survive at Sea · island silhouette verification
-- =====================================================================================
--
-- WHAT THIS GUARDS
-- ----------------
-- Islands must NOT be circles or domes. The old generator stacked `FillCylinder` discs
-- and `FillBall` balls, both of which are radially symmetric, so every isle read as a
-- round blob with a smooth hill on top. `src/shared/IslandShape.luau` replaced that with
-- a real coastline function plus a sculpted height field, and this suite measures the
-- actual geometry of every island in the shipping catalog to prove the reference
-- silhouette is present:
--
--   * a lobed, many-armed coastline that is measurably non-circular
--   * open lagoon water INSIDE the island, vented to the sea through narrow inlets
--   * solid land bridges between the lagoon windows (arms, not a closed atoll ring)
--   * a sand beach at every waterline
--   * one faceted landmark (volcano / peak / ridge) standing off centre
--   * relief with several summits and saddles rather than a single dome
--   * a flat, walkable settlement shelf that is genuinely on land
--   * a navigable channel that runs all the way through the river islands
--
-- It also prints a top-down ASCII map of every island so the silhouette can be checked
-- by eye without opening Roblox Studio.
--
-- Run locally:  lune run tests/IslandShape.spec.luau      (from the repo root)
-- =====================================================================================

local fs = require("@lune/fs")
local process = require("@lune/process")

local function read(path: string): string
	if fs.isFile(path) then
		return fs.readFile(path)
	end
	return fs.readFile("../" .. path)
end

-- -------------------------------------------------------------------------------------
-- Minimal Roblox datatype shims so the real Config module loads unmodified.
-- -------------------------------------------------------------------------------------
local BASE = getfenv()

local Vector3 = {}
Vector3.new = function(x, y, z)
	return { X = x or 0, Y = y or 0, Z = z or 0 }
end

local Color3 = {
	fromRGB = function(r, g, b)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
	end,
	new = function(r, g, b)
		return { R = r or 0, G = g or 0, B = b or 0 }
	end,
}

local UDim = {
	new = function(s, o)
		return { Scale = s, Offset = o }
	end,
}
local UDim2 = {
	fromScale = function(x, y)
		return { X = x, Y = y }
	end,
	fromOffset = function(x, y)
		return { X = x, Y = y }
	end,
}
local Enum = setmetatable({}, {
	__index = function()
		return setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		})
	end,
})

local function loadModule(path: string, name: string)
	local env = setmetatable({
		Vector3 = Vector3,
		Color3 = Color3,
		UDim = UDim,
		UDim2 = UDim2,
		Enum = Enum,
	}, { __index = BASE })
	local chunk, err = loadstring(read(path), "@" .. name)
	if not chunk then
		error(`failed to compile {path}: {err}`)
	end
	setfenv(chunk, env)
	return chunk()
end

local IslandShape = loadModule("src/shared/IslandShape.luau", "IslandShape")
local IslandRaster = loadModule("src/shared/IslandRaster.luau", "IslandRaster")
local Config = loadModule("src/shared/Config.luau", "Config")
local OceanConfig = loadModule("src/shared/OceanConfig.luau", "OceanConfig")

-- -------------------------------------------------------------------------------------
-- Harness
-- -------------------------------------------------------------------------------------
local passed, failed = 0, 0
local failures: { string } = {}

local function check(label: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
		print(`  PASS  {label}`)
	else
		failed += 1
		table.insert(failures, label)
		print(`  FAIL  {label}{if detail then "  ->  " .. detail else ""}`)
	end
end

local TAU = math.pi * 2
local TOP_Y = Config.Islands.TopY
-- Heights from IslandShape are relative to TopY, so sea level is a negative offset.
local SEA_OFFSET = OceanConfig.SurfaceY - TOP_Y

-- The same entry point the server uses (IslandTerrain.shapeFor delegates to it), catalog
-- overrides included. Building shapes any other way here would verify geometry the game
-- never renders.
local function basinRadiusFor(entry)
	if entry.SafeHarbor ~= true then
		return nil
	end
	local base = Config.StarterBase
	return IslandShape.spawnBasinRadius(
		Config.Islands.BerthSlots,
		base.SpacingX,
		base.SlotsPerRow,
		base.SizeStuds,
		Config.Islands.RaftCollisionPad
	)
end

local function shapeFor(entry)
	return IslandShape.forEntry(entry, SEA_OFFSET, { spawnBasinRadius = basinRadiusFor(entry) })
end

-- -------------------------------------------------------------------------------------
-- Measurements
-- -------------------------------------------------------------------------------------

-- Counts sign changes in the derivative of the coast radius. A circle scores 0; every
-- headland/cove pair adds two. This is the direct "is it still a blob?" measurement.
local function countCoastExtrema(shape): number
	local N = 360
	local radii = table.create(N)
	for i = 1, N do
		radii[i] = shape:coastRadius(((i - 1) / N) * TAU)
	end
	local extrema = 0
	for i = 1, N do
		local prev = radii[((i - 2) % N) + 1]
		local cur = radii[i]
		local nextR = radii[(i % N) + 1]
		-- coastRadius is smooth and analytic, so a sign change is a real feature.
		if (cur > prev and cur >= nextR) or (cur < prev and cur <= nextR) then
			extrema += 1
		end
	end
	return extrema
end

-- Mean absolute deviation of the coastline from its best-fit circle, as a fraction of
-- the mean radius. A perfect circle scores 0.
local function coastStats(shape): (number, number)
	local N = 720
	local sum = 0
	for i = 1, N do
		sum += shape:coastRadius(((i - 1) / N) * TAU)
	end
	local mean = sum / N
	local dev = 0
	for i = 1, N do
		dev += math.abs(shape:coastRadius(((i - 1) / N) * TAU) - mean)
	end
	return mean, (dev / N) / mean
end

-- Cell census over the whole island at the sculpting resolution.
type Census = {
	land: number,
	water: number,
	shelf: number,
	beach: number,
	high: number,
	grid: { [string]: number },
	step: number,
}

local function census(shape): Census
	local step = math.max(shape.half / 30, 12)
	local out: Census = { land = 0, water = 0, shelf = 0, beach = 0, high = 0, grid = {}, step = step }
	shape:forEachCell(step, function(dx, dz, kind, height, beach)
		if kind == "land" then
			out.land += 1
			if beach then
				out.beach += 1
			end
			if height > 12 then
				out.high += 1
			end
			out.grid[`{math.floor(dx / step)},{math.floor(dz / step)}`] = height
		elseif kind == "water" then
			out.water += 1
		elseif kind == "shelf" then
			out.shelf += 1
		end
	end)
	return out
end

-- Local maxima of the land height field. A single dome scores 1.
local function countSummits(c: Census): number
	local summits = 0
	for key, height in c.grid do
		local gxStr, gzStr = string.match(key, "^(%-?%d+),(%-?%d+)$")
		local gx, gz = tonumber(gxStr), tonumber(gzStr)
		local isPeak, neighbours = true, 0
		for dz = -1, 1 do
			for dx = -1, 1 do
				if dx == 0 and dz == 0 then
					continue
				end
				local nh = c.grid[`{gx + dx},{gz + dz}`]
				if nh then
					neighbours += 1
					if nh >= height then
						isPeak = false
					end
				end
			end
		end
		-- Only count fully interior cells that actually stand above the shore platform.
		if isPeak and neighbours == 8 and height > 6 then
			summits += 1
		end
	end
	return summits
end

-- Walks out of the bay along its mouth bearing and reports whether the water reaches the
-- open sea without crossing land. That is what makes the inner water a lagoon rather than
-- a sealed pond, and it is checked from the BAY's own centre because the mouth channel is
-- defined relative to the bay, not to the island centre.
-- Does the anchorage connect to the open sea? Flood-filled across water cells rather than
-- probed along a bearing.
--
-- A radial probe from the bay outward was tried and is the wrong test: land bridges cut the
-- lagoon into separate arcs, and the tidal pass that vents it is a notch in the sand arm at
-- a window bearing, which is generally NOT on the straight line out from the anchorage. The
-- route from a berth to open ocean curves along the lagoon and then out through the pass, so
-- only a connectivity test can answer whether a crew can actually sail out.
local function bayIsVented(shape): boolean
	local lagoon = shape.lagoon
	if not lagoon then
		return false
	end
	local step = math.max(shape.half / 40, 8)
	local sailable: { [string]: boolean } = {}
	local escapes: { [string]: boolean } = {}
	shape:forEachCell(step, function(dx, dz, kind)
		if kind == "water" or kind == "shelf" then
			local key = `{math.floor(dx / step)},{math.floor(dz / step)}`
			sailable[key] = true
			-- The submerged approach shelf sits outside the coastline: reaching it is
			-- reaching the ocean.
			if kind == "shelf" then
				escapes[key] = true
			end
		end
	end)

	local startKey = `{math.floor(lagoon.x / step)},{math.floor(lagoon.z / step)}`
	if not sailable[startKey] then
		return false
	end
	local seen: { [string]: boolean } = { [startKey] = true }
	local stack = { { x = math.floor(lagoon.x / step), z = math.floor(lagoon.z / step) } }
	while #stack > 0 do
		local current = table.remove(stack) :: { x: number, z: number }
		if escapes[`{current.x},{current.z}`] then
			return true
		end
		for ddz = -1, 1 do
			for ddx = -1, 1 do
				if ddx ~= 0 or ddz ~= 0 then
					local key = `{current.x + ddx},{current.z + ddz}`
					if sailable[key] and not seen[key] then
						seen[key] = true
						table.insert(stack, { x = current.x + ddx, z = current.z + ddz })
					end
				end
			end
		end
	end
	return false
end

-- -------------------------------------------------------------------------------------
-- Top-down ASCII map, for eyeballing the silhouette
-- -------------------------------------------------------------------------------------
local function renderMap(shape, entry)
	local COLS, ROWS = 84, 36
	local span = (shape.maxCoast + shape.shelfWidth) * 1.02
	print("")
	print(
		`  ---- {entry.Id}  "{entry.Name}"  ({entry.Biome}/{entry.Theme})  arms {shape.arms}`
			.. `  coast {math.floor(shape.minCoast)}..{math.floor(shape.maxCoast)} studs`
			.. `  landmark {shape.landmark.kind} +{math.floor(shape.landmark.height)} ----`
	)
	for row = 1, ROWS do
		local dz = ((row - 0.5) / ROWS * 2 - 1) * span
		local chars = {}
		for col = 1, COLS do
			local dx = ((col - 0.5) / COLS * 2 - 1) * span
			local kind, height, beach = shape:sample(dx, dz)
			local glyph
			if kind == "ocean" then
				glyph = " "
			elseif kind == "shelf" then
				glyph = ","
			elseif kind == "water" then
				glyph = "~"
			elseif beach then
				glyph = "."
			elseif height > shape.landmark.height * 0.62 then
				glyph = "A"
			elseif height > shape.landmark.height * 0.30 then
				glyph = "M"
			elseif height > 24 then
				glyph = "O"
			elseif height > 11 then
				glyph = "o"
			elseif height > 4 then
				glyph = ":"
			else
				glyph = "-"
			end
			table.insert(chars, glyph)
		end
		print(`  |{table.concat(chars)}|`)
	end
	print("  legend: ' ' sea  ',' shelf  '~' lagoon/river  '.' beach  '-' plain  ':' low  'o'/'O' hills  'M'/'A' landmark")
end

-- -------------------------------------------------------------------------------------
-- Run
-- -------------------------------------------------------------------------------------
print("\nSurvive at Sea · island silhouette verification\n")

local catalog = Config.Islands.Catalog
check("catalog is populated", #catalog > 0, `#catalog = {#catalog}`)

local fingerprints: { [string]: string } = {}
local roundIslands: { string } = {}
local domeIslands: { string } = {}
local pondIslands: { string } = {}

for _, entry in catalog do
	local id = entry.Id
	local shape = shapeFor(entry)
	local mean, residual = coastStats(shape)
	local extrema = countCoastExtrema(shape)
	local spread = (shape.maxCoast - shape.minCoast) / mean
	local c = census(shape)
	local summits = countSummits(c)

	-- 1) The coastline must be visibly non-circular.
	if spread < 0.20 or residual < 0.05 or extrema < 6 then
		table.insert(roundIslands, id)
	end
	check(
		`{id}: coastline is not a circle (radius spread >= 0.20)`,
		spread >= 0.20,
		`spread = {string.format("%.3f", spread)}`
	)
	check(
		`{id}: coastline deviates from its best-fit circle (>= 5%)`,
		residual >= 0.05,
		`residual = {string.format("%.3f", residual)}`
	)
	check(
		`{id}: coastline has multiple headlands and coves (>= 6 extrema)`,
		extrema >= 6,
		`extrema = {extrema}`
	)

	-- 2) Open water INSIDE the island — the defining feature of the reference silhouette.
	check(
		`{id}: has open lagoon / channel water inside the coastline`,
		c.water >= 20,
		`water cells = {c.water}`
	)
	-- 3) The bay sits on ONE flank with an irregular rim. A lagoon centred on the island
	--    reads as a moat and turns the whole isle into a bullseye, which is the second
	--    symmetric look this generator had to shed.
	local lagoon = shape.lagoon
	check(`{id}: has a lagoon basin`, lagoon ~= nil)
	if lagoon then
		local lagoonOffset = math.sqrt(lagoon.x * lagoon.x + lagoon.z * lagoon.z)
		check(
			`{id}: lagoon is a bay on one flank, not a ring around the centre`,
			lagoonOffset >= shape.half * 0.18,
			`bay centre is {math.floor(lagoonOffset)} from island centre (half = {math.floor(shape.half)})`
		)

		local rimMin, rimMax, rimSum = math.huge, 0, 0
		for i = 0, 179 do
			local rim = shape:lagoonRadius((i / 180) * TAU)
			rimMin = math.min(rimMin, rim)
			rimMax = math.max(rimMax, rim)
			rimSum += rim
		end
		-- A boarding island's anchorage is deliberately an OPEN HARBOUR notched through the
		-- sand arms (a four-raft berth grid needs more clear water than any atoll lagoon on
		-- this island size can hold), so its rim is not a closed curve to measure.
		if not shape.harbourNotch then
			check(
				`{id}: anchorage rim is irregular, not a circle`,
				(rimMax - rimMin) / (rimSum / 180) >= 0.20,
				`rim spread = {string.format("%.3f", (rimMax - rimMin) / (rimSum / 180))}`
			)
		end
	end

	-- 3a) CONNECTIVITY. An island must be ONE walkable landmass. This is flood-filled on the
	-- real height field rather than inferred from the layout, because the bay lobe and the
	-- channel pass are both capable of severing the causeways between the sandy arms and the
	-- inner island: before the land bridges were protected, 6 of 13 islands shipped as 2-3
	-- separate pieces and one had its village and volcano unreachable on foot.
	do
		local step = math.max(shape.half / 34, 8)
		local land: { [string]: boolean } = {}
		local order: { { x: number, z: number } } = {}
		shape:forEachCell(step, function(dx, dz, kind)
			if kind == "land" then
				local gx, gz = math.floor(dx / step), math.floor(dz / step)
				land[`{gx},{gz}`] = true
				table.insert(order, { x = gx, z = gz })
			end
		end)

		local seen: { [string]: boolean } = {}
		local components, largest = 0, 0
		for _, cell in order do
			local rootKey = `{cell.x},{cell.z}`
			if not seen[rootKey] then
				components += 1
				local size = 0
				local stack = { cell }
				seen[rootKey] = true
				while #stack > 0 do
					local current = table.remove(stack) :: { x: number, z: number }
					size += 1
					-- 8-connected: a diagonal step is walkable terrain, not a gap.
					for ddz = -1, 1 do
						for ddx = -1, 1 do
							if ddx ~= 0 or ddz ~= 0 then
								local key = `{current.x + ddx},{current.z + ddz}`
								if land[key] and not seen[key] then
									seen[key] = true
									table.insert(stack, { x = current.x + ddx, z = current.z + ddz })
								end
							end
						end
					end
				end
				largest = math.max(largest, size)
			end
		end

		local total = #order
		check(
			`{id}: island is one connected landmass`,
			total > 0 and largest >= total * 0.97,
			`{components} land components, largest holds {largest}/{total} cells`
		)

		-- And specifically: the inner island (village, volcano, loot) must be reachable on
		-- foot from the outer beach, not marooned across the lagoon.
		local coreCx = math.cos(shape.coreAngle) * shape.coreShift
		local coreCz = math.sin(shape.coreAngle) * shape.coreShift
		local coreKey = `{math.floor(coreCx / step)},{math.floor(coreCz / step)}`
		local beachKey: string? = nil
		for _, cell in order do
			local dx, dz = cell.x * step, cell.z * step
			local _, _, isBeach = shape:sample(dx, dz)
			if isBeach and math.sqrt(dx * dx + dz * dz) > shape.minCoast * 0.80 then
				beachKey = `{cell.x},{cell.z}`
				break
			end
		end
		local function componentOf(startKey: string): { [string]: boolean }
			local reached: { [string]: boolean } = {}
			if not land[startKey] then
				return reached
			end
			local sx, sz = string.match(startKey, "^(%-?%d+),(%-?%d+)$")
			local stack = { { x = tonumber(sx), z = tonumber(sz) } }
			reached[startKey] = true
			while #stack > 0 do
				local current = table.remove(stack) :: { x: number, z: number }
				for ddz = -1, 1 do
					for ddx = -1, 1 do
						if ddx ~= 0 or ddz ~= 0 then
							local key = `{current.x + ddx},{current.z + ddz}`
							if land[key] and not reached[key] then
								reached[key] = true
								table.insert(stack, { x = current.x + ddx, z = current.z + ddz })
							end
						end
					end
				end
			end
			return reached
		end
		if beachKey and land[coreKey] then
			check(
				`{id}: inner island is walkable from the outer beach`,
				componentOf(beachKey)[coreKey] == true,
				`core cell {coreKey} not reachable from beach cell {beachKey}`
			)
		else
			check(
				`{id}: has both an outer beach and inner-island ground to connect`,
				beachKey ~= nil and land[coreKey] == true,
				`beach = {tostring(beachKey)}, core cell on land = {tostring(land[coreKey])}`
			)
		end
	end

	-- 3b) The atoll: the lagoon must be walled OUTWARD by the sandy arms on most bearings,
	-- broken only where a pass cuts through. That is what makes it a lagoon held inside the
	-- island rather than a bite taken out of the coast.
	do
		local walled, lagoonBearings = 0, 0
		for i = 0, 71 do
			local a = (i / 72) * TAU
			local _, outer = shape:lagoonBand(a)
			-- Skip the tidal passes and a boarding island's harbour mouth: those are gaps in
			-- the arm on purpose, and counting them as unwalled just measures how many
			-- openings the island has.
			local inNotch = false
			for _, notch in shape.ringNotches do
				local d = math.abs(math.atan2(math.sin(a - notch.center), math.cos(a - notch.center)))
				if d <= notch.halfWidth + notch.feather then
					inNotch = true
					break
				end
			end
			if outer and not inNotch then
				lagoonBearings += 1
				local probe = outer + shape:ringWidth(a) * 0.5
				if shape:sample(math.cos(a) * probe, math.sin(a) * probe) == "land" then
					walled += 1
				end
			end
		end
		check(
			`{id}: sandy arms wall the lagoon in on most bearings`,
			lagoonBearings > 0 and walled >= lagoonBearings * 0.60,
			`walled {walled}/{lagoonBearings} lagoon bearings`
		)
	end

	-- 4) The lagoon is vented to the sea through its mouth, not a sealed pond.
	local vented = bayIsVented(shape)
	if not vented and entry.River ~= true then
		table.insert(pondIslands, id)
	end
	check(
		`{id}: anchorage can sail out to the open sea`,
		vented or entry.River == true,
		`pass bearing = {if shape.passAngle then string.format("%.2f rad", shape.passAngle) else "none"}`
	)

	-- 5) Sand beaches at the waterlines.
	check(`{id}: sand beaches ring the waterlines`, c.beach >= 24, `beach cells = {c.beach}`)
	check(
		`{id}: beaches are a shoreline band, not the whole island`,
		c.beach < c.land * 0.75,
		`beach share = {string.format("%.2f", c.beach / math.max(c.land, 1))}`
	)

	-- 6) A faceted landmark, standing clearly off centre.
	local lm = shape.landmark
	local lmOffset = math.sqrt(lm.x * lm.x + lm.z * lm.z)
	check(`{id}: carries a landmark landform`, lm.height >= 34, `{lm.kind} height = {math.floor(lm.height)}`)
	-- On an atoll the landmark belongs ON THE INNER ISLAND, which is the only ground broad
	-- and high enough to carry it. Requiring a large offset from the island centre (the old
	-- rule, from when the island was a single landmass) would push the cone into the lagoon
	-- or onto a sand arm. What matters now is that it sits on the core and is not
	-- mechanically centred on it.
	local coreCentreX = math.cos(shape.coreAngle) * shape.coreShift
	local coreCentreZ = math.sin(shape.coreAngle) * shape.coreShift
	local fromCore = math.sqrt((lm.x - coreCentreX) ^ 2 + (lm.z - coreCentreZ) ^ 2)
	check(
		`{id}: landmark stands on the inner island`,
		shape:sample(lm.x, lm.z) == "land" and fromCore + lm.baseR <= shape:coreRadius(lm.angle) * 1.35,
		`{math.floor(fromCore)} from core centre, foot {math.floor(lm.baseR)}, core rim {math.floor(shape:coreRadius(lm.angle))}`
	)
	check(
		`{id}: landmark is not mechanically centred on the inner island`,
		fromCore >= shape.half * 0.03,
		`offset from core centre = {math.floor(fromCore)}`
	)
	check(`{id}: high ground exists around the landmark`, c.high >= 8, `cells above 12 studs = {c.high}`)

	-- 7) Relief must not be a single dome.
	if summits < 3 then
		table.insert(domeIslands, id)
	end
	check(`{id}: relief has several summits, not one dome (>= 3)`, summits >= 3, `summits = {summits}`)

	-- 8) A flat, walkable settlement shelf that is really on land.
	if (entry.Theme or "wild") ~= "wild" then
		check(
			`{id}: settlement shelf has usable room`,
			shape.buildableRadius >= shape.half * 0.10,
			`buildable = {math.floor(shape.buildableRadius)} of half {math.floor(shape.half)}`
		)
		local vx, vz = shape:villageCenter()
		local flat, worst = true, 0
		for i = 0, 31 do
			local a = (i / 32) * TAU
			for _, frac in { 0.0, 0.45, 0.9 } do
				local kind, height = shape:sample(vx + math.cos(a) * shape.buildableRadius * frac, vz + math.sin(a) * shape.buildableRadius * frac)
				if kind ~= "land" then
					flat = false
				else
					worst = math.max(worst, height)
					if height > 12 then
						flat = false
					end
				end
			end
		end
		check(
			`{id}: settlement shelf is land and walkably flat`,
			flat,
			`tallest ground in footprint = {string.format("%.1f", worst)} studs`
		)
	end

	-- 9) A navigable channel must run all the way through the river islands. The course
	--    MEANDERS, so this scans across the valley at each step down the channel instead
	--    of walking a straight line along the river bearing — a straight probe leaves the
	--    water almost immediately and would "fail" a perfectly continuous river.
	if entry.River == true then
		local river = shape.river
		local c, s = math.cos(river.angle), math.sin(river.angle)
		local sweep = river.meanderAmp * 1.8 + river.width
		local blocked = 0
		local stations = 0
		for i = -12, 12 do
			local along = (i / 12) * shape.minCoast * 0.94
			local found = false
			for j = -24, 24 do
				local across = (j / 24) * sweep
				local dx, dz = along * c - across * s, along * s + across * c
				if shape:sample(dx, dz) == "water" then
					found = true
					break
				end
			end
			stations += 1
			if not found then
				blocked += 1
			end
		end
		-- On an atoll the channel is a tidal PASS, not a sea-to-sea crossing: it cuts the
		-- sand arms so the lagoon reaches the open sea, and stops at the inner island. A
		-- full crossing drew a blue ribbon across the atoll and split the jungle core in
		-- half. So the requirement is that the pass is continuous water from the coast in to
		-- the lagoon — the inner stations are expected to be land (the core).
		local outerStations, outerBlocked = 0, 0
		for i = -12, 12 do
			local along = (i / 12) * shape.minCoast * 0.94
			if math.abs(along) > shape:coreRadius(river.angle) then
				local found = false
				for j = -24, 24 do
					local across = (j / 24) * sweep
					local dx, dz = along * c - across * s, along * s + across * c
					local kind = shape:sample(dx, dz)
					if kind == "water" or kind == "shelf" or kind == "ocean" then
						found = true
						break
					end
				end
				outerStations += 1
				if not found then
					outerBlocked += 1
				end
			end
		end
		-- The pass runs in from ONE side. The opposite side of the channel axis is usually a
		-- protected land bridge, and deliberately stays dry — requiring both ends to be open
		-- would demand the channel sever a causeway, which is what disconnected islands in
		-- the first place. So: count the open side, and require it to reach the lagoon.
		local openSides = 0
		for _, direction in { 1, -1 } do
			local dry, total = 0, 0
			for i = 1, 12 do
				local along = direction * (i / 12) * shape.minCoast * 0.94
				if math.abs(along) > shape:coreRadius(river.angle) then
					local found = false
					for j = -24, 24 do
						local across = (j / 24) * sweep
						local dx, dz = along * c - across * s, along * s + across * c
						local kind = shape:sample(dx, dz)
						if kind == "water" or kind == "shelf" or kind == "ocean" then
							found = true
							break
						end
					end
					total += 1
					if not found then
						dry += 1
					end
				end
			end
			if total > 0 and dry == 0 then
				openSides += 1
			end
		end
		check(
			`{id}: navigable pass connects the sea to the lagoon`,
			openSides >= 1,
			`open channel sides = {openSides}/2 (dry outside core = {outerBlocked}/{outerStations})`
		)
	end

	-- 10) Boarding islands must float every crew raft. Rafts are placed on a line of slots
	--     through this island's own centre, so a bay generated without regard for them puts
	--     rafts inside terrain — which is exactly what happened once the hub's hand-pinned
	--     central lagoon was removed.
	if entry.SafeHarbor == true then
		local base = Config.StarterBase
		local slots = Config.Islands.BerthSlots
		local pad = Config.Islands.RaftCollisionPad
		local halfDeck = base.SizeStuds * 0.5
		local offsets = IslandShape.berthGrid(slots, base.SpacingX, base.SlotsPerRow)
		local ax, az = shape:berthAnchor()
		-- Anything that is not land floats a raft: the bay, the submerged approach shelf,
		-- and the open sea past the coast all count.
		local grounded = {}
		for slot, offset in offsets do
			-- The whole footprint plus the collision pad, corners included.
			for _, ox in { -halfDeck - pad, -halfDeck, 0, halfDeck, halfDeck + pad } do
				for _, oz in { -halfDeck - pad, -halfDeck, 0, halfDeck, halfDeck + pad } do
					local px, pz = ax + offset.x + ox, az + offset.z + oz
					if shape:sample(px, pz) == "land" then
						table.insert(grounded, `berth {slot} at ({math.floor(px)}, {math.floor(pz)})`)
					end
				end
			end
		end
		check(
			`{id}: berths all {slots} crew rafts clear of land`,
			#grounded == 0,
			`footprint over land: {table.concat(grounded, ", ")}`
		)
		-- The anchorage is an open harbour notched through the sand arms, so its centre may
		-- legitimately sit in open sea rather than enclosed bay water. What must hold is
		-- that it is water, and that the harbour actually opens to the sea so crews can
		-- sail out.
		local anchorKind = select(1, shape:sample(ax, az))
		check(
			`{id}: anchorage centre is open water`,
			anchorKind ~= "land",
			`anchorage centre sample = {anchorKind}`
		)
		check(
			`{id}: boarding island opens its harbour mouth to the sea`,
			shape.harbourNotch ~= nil,
			`harbourNotch = {tostring(shape.harbourNotch)}`
		)
	end

	-- 11) The terrain plan must stay affordable. Every cell written individually is tens of
	--     thousands of Terrain writes per island; the rectangle merge is what makes a
	--     sculpted coastline cheap enough to build at runtime, so its effect is asserted
	--     rather than assumed.
	local step = math.clamp(entry.SizeStuds / 90, 8, 16)
	local boxes, rasterStats = IslandRaster.build(shape, { step = step, topY = TOP_Y, quantize = 2 })
	local naive = rasterStats.cells * 2
	check(
		`{id}: terrain plan is merged into rectangles (<= 40% of one box per cell)`,
		#boxes <= naive * 0.40,
		`{#boxes} boxes vs {naive} cells`
	)
	check(
		`{id}: terrain plan stays under 4,000 Terrain writes`,
		#boxes < 4000,
		`{#boxes} boxes`
	)
	-- Same resolution the server uses (IslandTerrain.submergedPlan: twice the sculpt step),
	-- so this measures the plan that actually ships.
	local submerged = IslandRaster.submergedBoxes(shape, { step = step * 2, topY = TOP_Y })
	check(
		`{id}: submerged repaint stays a small replay, not a per-cell one`,
		#submerged < 700,
		`{#submerged} boxes`
	)
	-- Nothing in the plan may be water above the waterline, or an island would ship with
	-- water hanging over its own beaches.
	local floatingWater = 0
	for _, box in boxes do
		if box.water and box.bottom > TOP_Y + SEA_OFFSET then
			floatingWater += 1
		end
	end
	check(`{id}: no water is written above sea level`, floatingWater == 0, `{floatingWater} boxes`)

	fingerprints[id] = table.concat({
		string.format("%.4f", shape:coastRadius(0)),
		string.format("%.4f", shape:coastRadius(1.1)),
		string.format("%.4f", shape:coastRadius(2.7)),
		string.format("%.4f", shape:coastRadius(4.9)),
	}, "/")

	renderMap(shape, entry)
end

print("")
check("no island in the catalog is still a round blob", #roundIslands == 0, table.concat(roundIslands, ", "))
check("no island in the catalog is still a smooth dome", #domeIslands == 0, table.concat(domeIslands, ", "))
check("no island's inner water is a sealed pond", #pondIslands == 0, table.concat(pondIslands, ", "))

-- 10) Determinism and distinctness.
local first = catalog[1]
local a1, a2 = shapeFor(first), shapeFor(first)
local deterministic = true
for i = 0, 255 do
	local angle = (i / 256) * TAU
	if math.abs(a1:coastRadius(angle) - a2:coastRadius(angle)) > 0.000001 then
		deterministic = false
		break
	end
end
check("island geometry is deterministic for a given id", deterministic)

local seen: { [string]: string } = {}
local duplicates: { string } = {}
for id, fingerprint in fingerprints do
	if seen[fingerprint] then
		table.insert(duplicates, `{id} == {seen[fingerprint]}`)
	end
	seen[fingerprint] = id
end
check("every island has its own distinct silhouette", #duplicates == 0, table.concat(duplicates, ", "))

print(`\nResults: {passed} passed, {failed} failed\n`)
if failed > 0 then
	print("Failing checks:")
	for _, label in failures do
		print(`  - {label}`)
	end
	process.exit(1)
end
print("All island silhouette checks passed — no circular or dome-shaped islands.\n")
