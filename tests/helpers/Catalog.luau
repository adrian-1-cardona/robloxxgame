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
		})
	end
	return entries
end

-- Mirrors IslandService.shapeForEntry so specs and previews match the running server.
function Catalog.shapeFor(IslandShape, entry: { [string]: any })
	local river = nil
	if entry.River == true then
		river = {
			angle = entry.RiverAngle or 0,
			width = entry.RiverWidth or math.max(110, entry.SizeStuds * 0.07),
		}
	end
	return IslandShape.new(entry.Id, entry.SizeStuds, {
		biome = entry.Biome,
		theme = entry.Theme,
		river = river,
		volcano = entry.Volcano,
		seaOffset = -3,
	})
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
