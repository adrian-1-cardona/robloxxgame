--!nocheck
-- =====================================================================================
-- IslandRaster — turns an IslandShape into voxel Terrain boxes
-- =====================================================================================
--
-- The island body used to be built from `Terrain:FillCylinder` land columns and stacked
-- `Terrain:FillBall` relief. Both primitives are radially symmetric, so no matter how they
-- were layered the result was a round island with a dome on it. This module replaces them
-- entirely: it samples the IslandShape height field on a grid and emits axis-aligned
-- boxes, so the terrain follows the sculpted coastline exactly and contains no circular
-- primitive at all.
--
-- Naively that is one FillBlock per cell, which is tens of thousands of terrain writes per
-- island. Cells are therefore merged into maximal rectangles first (greedy, row-major),
-- which collapses flat ground, beaches and open water into a few large boxes and cuts the
-- write count by more than an order of magnitude.
--
-- Pure Luau, no Roblox APIs: materials are plain strings that the server maps to
-- `Enum.Material`. tests/IslandShape.spec.luau uses this to assert the terrain plan is
-- both circle-free and cheap enough to build at runtime.

local IslandRaster = {}

-- Material names, mapped to Enum.Material by src/server/IslandTerrain.luau.
export type Box = {
	x: number, -- centre, island-relative
	z: number,
	sizeX: number,
	sizeZ: number,
	bottom: number, -- absolute Y
	top: number, -- absolute Y
	material: string,
	water: boolean,
}

local function quantize(value: number, q: number): number
	return math.floor(value / q + 0.5) * q
end

--[[
	Greedy maximal-rectangle merge over a grid of cell keys. Cells with the same key that
	form a rectangle are emitted once. Row-major: grow along X first, then extend that run
	down Z for as long as every cell in the run matches.
]]
local function mergeCells(
	keys: { [number]: string? },
	nx: number,
	nz: number,
	emit: (number, number, number, number, number) -> ()
)
	local used: { [number]: boolean } = {}
	for iz = 0, nz - 1 do
		for ix = 0, nx - 1 do
			local index = ix + iz * nx + 1
			local key = keys[index]
			if key == nil or used[index] then
				continue
			end

			local x1 = ix
			while x1 + 1 < nx do
				local probe = (x1 + 1) + iz * nx + 1
				if keys[probe] ~= key or used[probe] then
					break
				end
				x1 += 1
			end

			local z1 = iz
			while z1 + 1 < nz do
				local rowMatches = true
				for x = ix, x1 do
					local probe = x + (z1 + 1) * nx + 1
					if keys[probe] ~= key or used[probe] then
						rowMatches = false
						break
					end
				end
				if not rowMatches then
					break
				end
				z1 += 1
			end

			for z = iz, z1 do
				for x = ix, x1 do
					used[x + z * nx + 1] = true
				end
			end
			emit(ix, iz, x1, z1, index)
		end
	end
end

-- Surface material for a land cell. Sand rings every waterline; the landmark carries rock,
-- basalt or snow by height so a volcano reads as a volcano and a peak as a peak.
function IslandRaster.materialFor(shape, height: number, beach: boolean): string
	if beach then
		return "Sand"
	end

	local biome = shape.biome
	local grass = if biome == "jungle" or biome == "volcanic" then "LeafyGrass" else "Grass"
	local lm = shape.landmark
	if lm and lm.height > 1 then
		local share = height / lm.height
		if lm.kind == "volcano" then
			if share > 0.46 then
				return "Basalt"
			elseif share > 0.20 then
				return "Rock"
			end
		elseif lm.kind == "peak" then
			if share > 0.60 then
				return "Snow"
			elseif share > 0.26 then
				return "Rock"
			end
		elseif share > 0.72 then
			return "Rock"
		end
	end
	-- Generic cliff faces on any steep upland.
	if height > 62 then
		return "Rock"
	end
	return grass
end

--[[
	Full-detail terrain plan for one island.

	opts:
		step      grid resolution in studs (smaller = finer coast, more boxes)
		topY      world Y that shape heights are measured from
		quantize  vertical snap in studs; makes flat ground merge into single boxes
]]
function IslandRaster.build(shape, opts: { [string]: any }): ({ Box }, { [string]: number })
	local step = (opts.step :: number?) or 12
	local topY = (opts.topY :: number?) or 0
	local q = (opts.quantize :: number?) or 2
	local seaY = topY + shape.seaOffset
	local bottom = topY + shape.baseBottom

	local cells, origin = shape:gridInfo(step)
	local solidKeys: { [number]: string? } = {}
	local waterKeys: { [number]: string? } = {}
	local tops: { [number]: number } = {}
	local materials: { [number]: string } = {}
	local beds: { [number]: number } = {}
	local stats = { land = 0, water = 0, shelf = 0, cells = 0 }

	for iz = 0, cells - 1 do
		local dz = origin + iz * step
		for ix = 0, cells - 1 do
			local dx = origin + ix * step
			local kind, height, beach = shape:sample(dx, dz)
			if kind == "ocean" then
				continue
			end
			local index = ix + iz * cells + 1
			stats.cells += 1
			if kind == "land" then
				stats.land += 1
				local top = quantize(topY + height, q)
				local material = IslandRaster.materialFor(shape, height, beach)
				tops[index] = top
				materials[index] = material
				solidKeys[index] = `{material}|{top}`
			else
				if kind == "water" then
					stats.water += 1
				else
					stats.shelf += 1
				end
				-- Submerged sand bed, then engine water on top of it up to sea level.
				local bed = quantize(topY + height, q)
				tops[index] = bed
				materials[index] = "Sand"
				beds[index] = bed
				solidKeys[index] = `Sand|{bed}`
				waterKeys[index] = `Water|{bed}`
			end
		end
	end

	local boxes: { Box } = {}
	local function emitter(isWater: boolean)
		return function(ix: number, iz: number, x1: number, z1: number, index: number)
			local wide = (x1 - ix + 1) * step
			local deep = (z1 - iz + 1) * step
			local cx = origin + (ix + x1) * 0.5 * step
			local cz = origin + (iz + z1) * 0.5 * step
			local low = if isWater then beds[index] else bottom
			local high = if isWater then seaY else tops[index]
			if high - low <= 0 then
				return
			end
			table.insert(boxes, {
				x = cx,
				z = cz,
				sizeX = wide,
				sizeZ = deep,
				bottom = low,
				top = high,
				material = if isWater then "Water" else materials[index],
				water = isWater,
			})
		end
	end

	mergeCells(solidKeys, cells, cells, emitter(false))
	mergeCells(waterKeys, cells, cells, emitter(true))
	stats.boxes = #boxes
	return boxes, stats
end

--[[
	Coarse "everything below the waterline" plan.

	The ocean streamer fills whole 256-stud chunks with water below sea level, which wipes
	out the submerged part of an island every time a chunk is refilled. This is the pass
	that puts it back. It used to be a single `FillCylinder` per island of radius
	size/2 + 8, which also flooded the lagoon with sand and squared off the coast below the
	waterline. Replaying the real footprint keeps the shoreline, the lagoon bed and the
	approach shelf intact.
]]
function IslandRaster.submergedBoxes(shape, opts: { [string]: any }): { Box }
	local step = (opts.step :: number?) or 48
	local topY = (opts.topY :: number?) or 0
	local seaY = topY + shape.seaOffset
	local bottom = topY + shape.baseBottom
	-- Land keeps its sand base just under the waterline; water bodies keep their own bed.
	local landTop = seaY - 1.5

	local cells, origin = shape:gridInfo(step)
	local keys: { [number]: string? } = {}
	local tops: { [number]: number } = {}
	for iz = 0, cells - 1 do
		local dz = origin + iz * step
		for ix = 0, cells - 1 do
			local dx = origin + ix * step
			local kind, height = shape:sample(dx, dz)
			if kind == "ocean" then
				continue
			end
			local index = ix + iz * cells + 1
			local top = if kind == "land" then landTop else math.min(topY + height, landTop)
			tops[index] = top
			keys[index] = `{math.floor(top * 4)}`
		end
	end

	local boxes: { Box } = {}
	mergeCells(keys, cells, cells, function(ix, iz, x1, z1, index)
		local top = tops[index]
		if top - bottom <= 0 then
			return
		end
		table.insert(boxes, {
			x = origin + (ix + x1) * 0.5 * step,
			z = origin + (iz + z1) * 0.5 * step,
			sizeX = (x1 - ix + 1) * step,
			sizeZ = (z1 - iz + 1) * step,
			bottom = bottom,
			top = top,
			material = "Sand",
			water = false,
		})
	end)
	return boxes
end

return IslandRaster
