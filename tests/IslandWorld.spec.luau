--!nocheck
-- Lightweight source-level guards for world rules that must remain true even when
-- Roblox Studio is unavailable in CI. Run with: lune run tests/IslandWorld.spec.luau

local fs = require("@lune/fs")
local process = require("@lune/process")

local function read(path: string): string
	if fs.isFile(path) then
		return fs.readFile(path)
	end
	return fs.readFile("../" .. path)
end

local config = read("src/shared/Config.luau")
local islands = read("src/server/IslandService.luau")
local village = read("src/server/VillageBuilder.luau")
local starterBase = read("src/server/StarterBaseService.luau")
local shape = read("src/shared/IslandShape.luau")
local raster = read("src/shared/IslandRaster.luau")
local terrain = read("src/server/IslandTerrain.luau")
local twinPeaks = read("src/server/TwinPeaksBuilder.luau")
local islandLod = read("src/server/IslandLod.luau")

local passed = 0
local failed = 0

local function check(label: string, condition: boolean)
	if condition then
		passed += 1
		print(`  PASS  {label}`)
	else
		failed += 1
		print(`  FAIL  {label}`)
	end
end

print("\nSurvive at Sea · island world regression suite\n")

local catalogStart = string.find(config, "Catalog = {", 1, true)
local catalogEnd = string.find(config, "\n\t\t},\n\t},", catalogStart, true)
local catalog = string.sub(config, catalogStart, catalogEnd)
local _, islandCount = string.gsub(catalog, '\n\t\t\t\tId = "', "")

check("opening catalog contains twelve inner-ring islands, six plaza villages, and the river-spawn hub", islandCount == 19)
check("arrival hub is centered on the crew spawn river", string.find(catalog, 'Id = "arrival_hub"', 1, true) ~= nil
	and string.find(catalog, "SafeHarbor = true", 1, true) ~= nil
	and string.find(catalog, "RiverWidth = 440", 1, true) ~= nil)
check("at least one opening island has a river", string.find(catalog, "River = true", 1, true) ~= nil)
check("starter raft is a compact 64-stud voyage platform", string.find(config, "SizeStuds = 64", 1, true) ~= nil)
check("river is much wider than the 64-stud raft", string.find(catalog, "RiverWidth = 300", 1, true) ~= nil)
check("opening island ring sits within the 4K streaming target", string.find(catalog, "Offset = Vector3.new(0, 0, -2100)", 1, true) ~= nil)
check("opening islands use a high-detail 1,100-stud footprint", string.find(catalog, "SizeStuds = 1100", 1, true) ~= nil)
check("spawn raft is presented as a sailing ship", string.find(starterBase, 'hub.Name = "ShipRigging"', 1, true) ~= nil)
check("flat cylinder preview disks stay removed", string.find(islands, 'Name = "ForestFloor"', 1, true) == nil)
check("village residents spawn during island construction", string.find(islands, "populateIsland(record)", 1, true) ~= nil)
check("river bridges are not added to the island decoration pass", string.find(islands, "buildRiverBridge(model, center", 1, true) == nil)
check("peak rope bridge lives in TwinPeaksBuilder for the postcard twin-isle", string.find(twinPeaks, "function TwinPeaksBuilder.buildRopeBridge", 1, true) ~= nil)
-- The core regression this suite exists to prevent: island land must never again be built
-- from radially symmetric primitives. FillCylinder and FillBall are banned across the whole
-- island pipeline; the body comes from the shared silhouette instead.
check(
	"no island land is built from FillCylinder discs or FillBall spheres",
	string.find(islands, "FillCylinder(", 1, true) == nil
		and string.find(islands, "FillBall(", 1, true) == nil
		and string.find(terrain, "FillCylinder(", 1, true) == nil
		and string.find(terrain, "FillBall(", 1, true) == nil
)
check("twin peaks island uses the parts-only builder", string.find(config, "TwinPeaks = true", 1, true) ~= nil
	and string.find(islands, "TwinPeaksBuilder.build(model", 1, true) ~= nil)
check(
	"island bodies are sculpted from the shared IslandShape silhouette",
	string.find(islands, 'require(script.Parent:WaitForChild("IslandTerrain"))', 1, true) ~= nil
		and string.find(islands, "IslandTerrain.sculpt(shape, center, topY)", 1, true) ~= nil
		and string.find(terrain, "IslandRaster.build(shape", 1, true) ~= nil
)
check(
	"the silhouette is a harmonic coastline, not a radius",
	string.find(shape, "function IslandShape:coastRadius", 1, true) ~= nil
		and string.find(shape, "harmonics(self.coastProfile, angle)", 1, true) ~= nil
)
check(
	"the lagoon is an off-centre bay with an irregular rim and a mouth to the sea",
	string.find(shape, "function IslandShape:lagoonRadius", 1, true) ~= nil
		and string.find(shape, "function IslandShape:lagoonMouthEdge", 1, true) ~= nil
)
check(
	"terrain writes are merged into rectangles rather than one box per cell",
	string.find(raster, "Greedy maximal-rectangle merge", 1, true) ~= nil
		and string.find(raster, "local function mergeCells", 1, true) ~= nil
)
check(
	"all scattered vegetation samples dry terrain above the ocean",
	string.find(islands, "params.IgnoreWater = true", 1, true) ~= nil
		and string.find(islands, "result.Position.Y <= OceanConfig.SurfaceY + 0.65", 1, true) ~= nil
		and string.find(islands, "local function dryGroundY", 1, true) ~= nil
)
check("raft collision has no through-island river exception", string.find(islands, "inNavigableRiver", 1, true) == nil)
check(
	"rafts stop on sand/land and cannot drive through islands",
	string.find(islands, "function IslandService.collideRaft", 1, true) ~= nil
		and string.find(islands, "segmentHitsSand", 1, true) ~= nil
		and string.find(islands, "isSandOrLand", 1, true) ~= nil
		and string.find(islands, '-- All collision disabled', 1, true) == nil
)
check(
	"river towns keep houses on the banks",
	string.find(village, "local bankOffset =", 1, true) ~= nil
		and string.find(village, "riverCf:PointToObjectSpace", 1, true) ~= nil
)
check(
	"reference forest uses mixed broad and tiered canopies",
	string.find(islands, "buildVillageForestTree", 1, true) ~= nil
		and string.find(islands, "buildTieredForestTree", 1, true) ~= nil
)
check(
	"island hubs include landmark trails lined with shrubs",
	string.find(islands, "buildIslandTrailNetwork", 1, true) ~= nil
		and string.find(islands, 'Name = "ScenicPath"', 1, true) ~= nil
		and string.find(islands, "buildBush(model", 1, true) ~= nil
)
check(
	"mountain hubs carry the reference hot-air-balloon skyline",
	string.find(islands, "buildHotAirBalloon", 1, true) ~= nil
		and string.find(islands, 'balloon.Name = "HotAirBalloon"', 1, true) ~= nil
)
check(
	"towns include a dense harbour-facing building row",
	string.find(village, "local waterfrontCount =", 1, true) ~= nil
		and string.find(village, "harborForward", 1, true) ~= nil
)
check(
	"timber villages build a cobblestone plaza with stone obelisks",
	string.find(village, "buildVillagePlaza(", 1, true) ~= nil
		and string.find(village, 'Name = "PlazaCobble"', 1, true) ~= nil
		and string.find(village, 'Name = "ObeliskCap"', 1, true) ~= nil
)
check(
	"timber towns raise a round keep on the village square",
	string.find(village, "buildRoundKeep(", 1, true) ~= nil
		and string.find(village, 'Name = "RoundKeep"', 1, true) ~= nil
)
check(
	"outer-ring plaza villages are in the opening catalog",
	string.find(catalog, 'Id = "amber_square"', 1, true) ~= nil
		and string.find(catalog, 'Id = "willow_green"', 1, true) ~= nil
)
check(
	"navigable channels meander instead of cutting a straight trench",
	string.find(shape, "function IslandShape:riverCourse", 1, true) ~= nil
		and string.find(shape, "meanderAmp", 1, true) ~= nil
)
check(
	"arrival hub has a raised crossing and landmark skyline",
	string.find(islands, "decorateArrivalHub", 1, true) ~= nil
		and string.find(islands, 'Name = "HubCrossingDeck"', 1, true) ~= nil
		and string.find(islands, "buildHotAirBalloon(", 1, true) ~= nil
)

-- Gameplay must agree with the shape it is now drawn from.
check(
	"raft collision follows the sculpted coast instead of a bounding circle",
	string.find(islands, "local function shoreClearance", 1, true) ~= nil
		and string.find(islands, "shape:coastRadius(math.atan2(dz, dx))", 1, true) ~= nil
		and string.find(islands, "segmentHitsCircle(fromPos, toPos, isle.center", 1, true) == nil
		and string.find(islands, "isSandOrLand", 1, true) ~= nil
)
check(
	"the submerged repaint replays the real footprint, not a sand cylinder",
	string.find(islands, "IslandTerrain.repaintSubmerged(isle.submergedPlan", 1, true) ~= nil
		and string.find(raster, "function IslandRaster.submergedBoxes", 1, true) ~= nil
)
check(
	"settlements are capped by the island's usable clearing",
	string.find(islands, "deps.buildableRadius = shape.buildableRadius", 1, true) ~= nil
		and string.find(village, "buildable / 1.3", 1, true) ~= nil
)
check(
	"props are placed on sampled land rather than a polar radius",
	string.find(islands, "shape:randomLandPoint(rand", 1, true) ~= nil
		and string.find(islands, "local function landPoint", 1, true) ~= nil
)
check(
	"distant island LOD keeps rocky exterior + town silhouette while streaming",
	string.find(islands, 'require(script.Parent:WaitForChild("IslandLod"))', 1, true) ~= nil
		and string.find(islands, "IslandLod.build(folder", 1, true) ~= nil
		and string.find(islandLod, "ModelStreamingMode.Persistent", 1, true) ~= nil
		and string.find(islandLod, "buildTownCluster", 1, true) ~= nil
		and string.find(islandLod, "buildRockStack", 1, true) ~= nil
)
check(
	"timber town houses use the light-blue valley-town palette",
	string.find(village, "PLASTER_BLUE", 1, true) ~= nil
		and string.find(village, "ROOF_TAN", 1, true) ~= nil
)

print(`\nResults: {passed} passed, {failed} failed\n`)
if failed > 0 then
	process.exit(1)
end
