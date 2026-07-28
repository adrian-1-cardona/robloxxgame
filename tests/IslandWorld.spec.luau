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

check("opening catalog contains twelve islands around the hub", islandCount == 12)
check("at least one opening island has a river", string.find(catalog, "River = true", 1, true) ~= nil)
check("starter raft is a compact 64-stud voyage platform", string.find(config, "SizeStuds = 64", 1, true) ~= nil)
check("river is much wider than the 64-stud raft", string.find(catalog, "RiverWidth = 300", 1, true) ~= nil)
check("opening island ring sits within the 4K streaming target", string.find(catalog, "Offset = Vector3.new(0, 0, -2100)", 1, true) ~= nil)
check("opening islands use a high-detail 1,100-stud footprint", string.find(catalog, "SizeStuds = 1100", 1, true) ~= nil)
check("spawn raft is presented as the central voyage hub", string.find(starterBase, 'hub.Name = "VoyageHub"', 1, true) ~= nil)
check("flat cylinder preview disks stay removed", string.find(islands, 'Name = "ForestFloor"', 1, true) == nil)
check(
	"island surfaces use layered rolling shoulders",
	string.find(islands, "local shoulderCount =", 1, true) ~= nil
		and string.find(islands, "Layered spheres create climbable slopes", 1, true) ~= nil
)
check(
	"river collision checks both movement endpoints",
	string.find(islands, "math.abs(fromLocal.X) <= safeHalfWidth", 1, true) ~= nil
		and string.find(islands, "math.abs(toLocal.X) <= safeHalfWidth", 1, true) ~= nil
)
check(
	"raft stops at its last safe position on first shoreline contact",
	string.find(islands, "return fromPos, isle.name", 1, true) ~= nil
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
	"river terrain includes rocky ravine banks",
	string.find(islands, "Broken rock walls and raised grassy shoulders", 1, true) ~= nil
)

print(`\nResults: {passed} passed, {failed} failed\n`)
if failed > 0 then
	process.exit(1)
end
