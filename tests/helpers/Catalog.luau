--!nocheck
-- Reads Config.Islands.Catalog straight out of the source so the headless specs and the
-- preview renderer exercise the REAL island list. Config.luau itself can't be required
-- outside Roblox (it builds Vector3 / Color3 values), so the fields the island silhouette
-- depends on are parsed out of the text instead.

local fs = require("@lune/fs")

local Catalog = {}

local function read(path: string): string
	if fs.isFile(path) then
		return fs.readFile(path)
	end
	return fs.readFile("../" .. path)
end

function Catalog.source(): string
	return read("src/shared/Config.luau")
end

function Catalog.slice(): string
	local config = Catalog.source()
	local from = string.find(config, "Catalog = {", 1, true)
	assert(from, "Config.Islands.Catalog not found")
	local to = string.find(config, "\n\t\t},\n\t},", from, true)
	assert(to, "end of Config.Islands.Catalog not found")
	return string.sub(config, from, to)
end

local function field(block: string, name: string): string?
	return string.match(block, name .. "%s*=%s*([^,\n]+)")
end

local function numberField(block: string, name: string): number?
	local raw = field(block, name)
	return raw and tonumber(raw) or nil
end

local function stringField(block: string, name: string): string?
	return string.match(block, name .. '%s*=%s*"([^"]+)"')
end

-- `Name = Vector3.new(x, y, z)` -> a plain table with X/Y/Z, which is all IslandShape's
-- override reader needs.
local function vectorField(block: string, name: string): { X: number, Y: number, Z: number }?
	local x, y, z = string.match(block, name .. "%s*=%s*Vector3%.new%(([^,]+),([^,]+),([^%)]+)%)")
	if not x then
		return nil
	end
	return { X = tonumber(x) or 0, Y = tonumber(y) or 0, Z = tonumber(z) or 0 }
end

local function boolField(block: string, name: string): boolean?
	local raw = field(block, name)
	if raw == nil then
		return nil
	end
	return string.find(raw, "true", 1, true) ~= nil
end

-- Every catalog entry, in order, with the fields that drive the island silhouette.
function Catalog.load(): { { [string]: any } }
	local catalog = Catalog.slice()
	local entries = {}
	local positions = {}
	for pos in string.gmatch(catalog, '()\n\t\t\t\tId = "') do
		table.insert(positions, pos)
	end
	for i, pos in positions do
		local finish = if positions[i + 1] then positions[i + 1] - 1 else #catalog
		local block = string.sub(catalog, pos, finish)
		table.insert(entries, {
			Id = stringField(block, "Id") :: string,
			Name = stringField(block, "Name"),
			SizeStuds = numberField(block, "SizeStuds") :: number,
			Biome = stringField(block, "Biome") or "beach",
			Theme = stringField(block, "Theme") or "wild",
			River = boolField(block, "River"),
			RiverAngle = numberField(block, "RiverAngle"),
			RiverWidth = numberField(block, "RiverWidth"),
			Docks = numberField(block, "Docks"),
			Volcano = boolField(block, "Volcano"),
			Lighthouse = boolField(block, "Lighthouse"),
			Abandoned = boolField(block, "Abandoned"),
			SafeHarbor = boolField(block, "SafeHarbor"),
			-- Hand-authored silhouette overrides (see IslandShape.applyOverrides).
			Lagoon = boolField(block, "Lagoon"),
			LagoonWidth = numberField(block, "LagoonWidth"),
			LagoonOffset = vectorField(block, "LagoonOffset"),
			VolcanoOffset = vectorField(block, "VolcanoOffset"),
			VolcanoBaseRadius = numberField(block, "VolcanoBaseRadius"),
			VolcanoHeight = numberField(block, "VolcanoHeight"),
			SettlementOffset = vectorField(block, "SettlementOffset"),
			VillageRadiusFactor = numberField(block, "VillageRadiusFactor"),
		})
	end
	return entries
end

-- Raft numbers, needed to derive a boarding island's spawn basin the way the server does.
function Catalog.raftConfig(): { slots: number, spacing: number, perRow: number, size: number, pad: number }
	local config = Catalog.source()
	local function number(name: string, fallback: number): number
		return tonumber(string.match(config, name .. "%s*=%s*([%d%.]+)")) or fallback
	end
	return {
		slots = number("BerthSlots", 4),
		spacing = number("SpacingX", 160),
		perRow = number("SlotsPerRow", 2),
		size = number("SizeStuds", 64),
		pad = number("RaftCollisionPad", 52),
	}
end

-- The same entry point the server uses, catalog overrides and spawn basin included.
function Catalog.shapeFor(IslandShape, entry: { [string]: any })
	local basinRadius = nil
	if entry.SafeHarbor == true then
		local raft = Catalog.raftConfig()
		basinRadius = IslandShape.spawnBasinRadius(raft.slots, raft.spacing, raft.perRow, raft.size, raft.pad)
	end
	return IslandShape.forEntry(entry, -3, { spawnBasinRadius = basinRadius })
end

-- Fraction of the island's own footprint (inside the coastline) that is inland water:
-- the lagoon, its inlets, the river and any highland lake.
function Catalog.waterFraction(shape): number
	local inside, water = 0, 0
	local step = math.max(shape.half / 34, 6)
	local reach = shape.maxCoast
	local dx = -reach
	while dx <= reach do
		local dz = -reach
		while dz <= reach do
			local kind = shape:sample(dx, dz)
			if kind == "land" then
				inside += 1
			elseif kind == "water" then
				inside += 1
				water += 1
			end
			dz += step
		end
		dx += step
	end
	if inside == 0 then
		return 0
	end
	return water / inside
end

-- Coastline radius samples: the raw evidence that an island is not a disc.
function Catalog.coastSamples(shape, count: number?): { number }
	local n = count or 360
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, shape:coastRadius((i / n) * math.pi * 2))
	end
	return out
end

return Catalog
