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

check("opening catalog contains exactly ten islands", islandCount == 10)
check("at least one opening island has a river", string.find(catalog, "River = true", 1, true) ~= nil)
check("river is wider than the 72-stud raft", string.find(catalog, "RiverWidth = 200", 1, true) ~= nil)
check("flat cylinder preview disks stay removed", string.find(islands, 'Name = "ForestFloor"', 1, true) == nil)
check(
	"river collision checks both movement endpoints",
	string.find(islands, "math.abs(fromLocal.X) <= safeHalfWidth", 1, true) ~= nil
		and string.find(islands, "math.abs(toLocal.X) <= safeHalfWidth", 1, true) ~= nil
)
check(
	"river towns keep houses on the banks",
	string.find(village, "local bankOffset =", 1, true) ~= nil
		and string.find(village, "riverCf:PointToObjectSpace", 1, true) ~= nil
)

print(`\nResults: {passed} passed, {failed} failed\n`)
if failed > 0 then
	process.exit(1)
end
