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
	return IslandShape.forEntry(entry, OceanConfig.SurfaceY - topY)
end

-- Grid resolution: fine enough that the coastline reads as sculpted, coarse enough that an
-- island is a couple of thousand terrain writes rather than tens of thousands.
function IslandTerrain.stepFor(size: number): number
	return math.clamp(size / 90, 8, 16)
end

local function writeBoxes(boxes, center: Vector3, mayYield: boolean)
	local terrain = Workspace.Terrain
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
			if mayYield and written % BOXES_PER_YIELD == 0 then
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
	return writeBoxes(boxes, center, true)
end

-- Precompute the submerged footprint once; IslandService replays it whenever the ocean
-- streamer refills the water chunks over an island.
function IslandTerrain.submergedPlan(shape, topY: number)
	return IslandRaster.submergedBoxes(shape, { step = 48, topY = topY })
end

function IslandTerrain.repaintSubmerged(boxes, center: Vector3)
	-- Runs on the streaming tick, so it must complete in one pass rather than yielding
	-- mid-repaint and leaving an island half flooded for a frame.
	writeBoxes(boxes, center, false)
end

return IslandTerrain
