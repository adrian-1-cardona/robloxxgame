--!nocheck
-- =====================================================================================
-- IslandTerrain — writes an IslandShape into Roblox voxel Terrain
-- =====================================================================================
--
-- Thin server-side adapter: IslandShape decides the silhouette, IslandRaster turns it into
-- merged axis-aligned boxes, and this module writes those boxes as Terrain. It contains no
-- shape logic of its own, and deliberately no `FillCylinder` / `FillBall` calls — those are
-- the radially symmetric primitives that made every island a round blob with a dome.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local IslandShape = require(Shared:WaitForChild("IslandShape"))
local IslandRaster = require(Shared:WaitForChild("IslandRaster"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))

local IslandTerrain = {}

local MATERIALS: { [string]: Enum.Material } = {
	Sand = Enum.Material.Sand,
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Rock = Enum.Material.Rock,
	Basalt = Enum.Material.Basalt,
	Snow = Enum.Material.Snow,
	Water = Enum.Material.Water,
}

-- Terrain writes are cheap individually but there are a couple of thousand per island, so
-- the build yields periodically to stay inside the script execution budget on a cold boot.
local BOXES_PER_YIELD = 450

--[[
	Build the shape for a catalog entry. Optional per-island overrides in the catalog are
	honoured so a hand-authored island (the arrival hub) can pin its own layout while every
	other isle stays procedural:

		SizeStuds, Biome, Theme                the basic silhouette inputs
		River / RiverAngle / RiverWidth         navigable channel
		Volcano = false                         suppress the crater on a volcanic isle
		Lagoon = false                          suppress the lagoon
		LagoonWidth                             override the bay's size
		LagoonOffset (Vector3)                  override the bay's position
		VolcanoOffset (Vector3), VolcanoBaseRadius, VolcanoHeight
		SettlementOffset (Vector3), VillageRadiusFactor
]]
function IslandTerrain.shapeFor(entry: { [string]: any }, topY: number)
	local size = entry.SizeStuds
	local shape = IslandShape.new(entry.Id, size, {
		biome = entry.Biome or "beach",
		theme = entry.Theme or "wild",
		seaOffset = OceanConfig.SurfaceY - topY,
		volcano = entry.Volcano,
		lake = entry.Lake,
		lagoon = entry.Lagoon,
		river = if entry.River == true
			then {
				angle = tonumber(entry.RiverAngle) or 0,
				width = tonumber(entry.RiverWidth) or math.max(110, size * 0.07),
			}
			else nil,
	})

	IslandTerrain.applyOverrides(shape, entry)
	return shape
end

-- Hand-authored catalog overrides. Applied after generation and re-validated, so a bad
-- override degrades to the procedural layout instead of producing a broken island.
function IslandTerrain.applyOverrides(shape, entry: { [string]: any })
	local half = shape.half

	local lagoon = shape.lagoon
	if lagoon then
		local offset = entry.LagoonOffset
		if typeof(offset) == "Vector3" and (offset.X ~= 0 or offset.Z ~= 0) then
			lagoon.x, lagoon.z = offset.X, offset.Z
			lagoon.distance = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
			lagoon.angle = math.atan2(offset.Z, offset.X)
		end
		local width = tonumber(entry.LagoonWidth)
		if width then
			lagoon.baseR = math.clamp(width * 0.5, half * 0.12, half * 0.62)
		end
	end

	local lm = shape.landmark
	if lm then
		local offset = entry.VolcanoOffset
		if typeof(offset) == "Vector3" and (offset.X ~= 0 or offset.Z ~= 0) then
			lm.x, lm.z = offset.X, offset.Z
			lm.distance = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
			lm.angle = math.atan2(offset.Z, offset.X)
		end
		local baseR = tonumber(entry.VolcanoBaseRadius)
		if baseR then
			lm.baseR = math.clamp(baseR, half * 0.10, half * 0.55)
		end
		local height = tonumber(entry.VolcanoHeight)
		if height then
			lm.height = math.clamp(height, 20, shape.size * 0.30)
		end
		if entry.Volcano == true and lm.kind ~= "volcano" then
			lm.kind = "volcano"
			lm.craterR = lm.baseR * 0.17
			lm.craterDepth = lm.height * 0.13
		end
	end

	-- The settlement clearing must be re-fitted whenever the landforms move, otherwise the
	-- village keeps the clearing it was given before the volcano was relocated on top of it.
	local settlement = entry.SettlementOffset
	if typeof(settlement) == "Vector3" and (settlement.X ~= 0 or settlement.Z ~= 0) then
		local fitted = shape:clearingRadiusAt(settlement.X, settlement.Z)
		if fitted > half * 0.06 then
			local radius = math.min(fitted, half * 0.30)
			local factor = tonumber(entry.VillageRadiusFactor)
			if factor then
				radius = math.min(radius, half * factor)
			end
			shape.villageX, shape.villageZ = settlement.X, settlement.Z
			shape.buildableRadius = radius
			shape.shelf = {
				x = settlement.X,
				z = settlement.Z,
				radius = radius,
				feather = math.max(radius * 0.55, 20),
			}
		else
			warn(
				`[SurviveAtSea] {entry.Id}: SettlementOffset is not on usable ground; `
					.. `keeping the generated village site`
			)
		end
	elseif tonumber(entry.VillageRadiusFactor) and shape.shelf then
		local radius = math.min(shape.buildableRadius, half * tonumber(entry.VillageRadiusFactor))
		shape.buildableRadius = radius
		shape.shelf.radius = radius
		shape.shelf.feather = math.max(radius * 0.55, 20)
	end
end

-- Grid resolution: fine enough that the coastline reads as sculpted, coarse enough that an
-- island is a couple of thousand terrain writes rather than tens of thousands.
function IslandTerrain.stepFor(size: number): number
	return math.clamp(size / 90, 8, 16)
end

local function writeBoxes(boxes, center: Vector3, yieldEvery: number?)
	local terrain = Workspace.Terrain
	local budget = yieldEvery or BOXES_PER_YIELD
	local written = 0
	for _, box in boxes do
		local height = box.top - box.bottom
		if height > 0 then
			terrain:FillBlock(
				CFrame.new(center.X + box.x, (box.top + box.bottom) * 0.5, center.Z + box.z),
				Vector3.new(box.sizeX, height, box.sizeZ),
				MATERIALS[box.material] or Enum.Material.Sand
			)
			written += 1
			if written % budget == 0 then
				task.wait()
			end
		end
	end
	return written
end

-- Sculpt the whole island: land, beaches, lagoon bed, river channel and approach shelf.
function IslandTerrain.sculpt(shape, center: Vector3, topY: number): number
	local boxes = IslandRaster.build(shape, {
		step = IslandTerrain.stepFor(shape.size),
		topY = topY,
		quantize = 2,
	})
	return writeBoxes(boxes, center)
end

-- Precompute the submerged footprint once; IslandService replays it whenever the ocean
-- streamer refills the water chunks over an island.
function IslandTerrain.submergedPlan(shape, topY: number)
	return IslandRaster.submergedBoxes(shape, { step = 48, topY = topY })
end

function IslandTerrain.repaintSubmerged(boxes, center: Vector3)
	-- No yielding here: this runs on the streaming tick and must complete in one pass.
	writeBoxes(boxes, center, math.huge)
end

return IslandTerrain
