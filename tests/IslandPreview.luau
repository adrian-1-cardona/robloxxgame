--!nocheck
-- Headless island preview renderer.
--
--   lune run tests/IslandPreview.luau
--
-- Rasterises every catalog island straight out of src/shared/IslandShape.luau and writes
-- a top-down PNG per island plus one contact sheet into build/island-preview/. This is
-- the check that the generated silhouettes really are the lobed, lagoon-cut tropical
-- islands from the reference art rather than discs — no Roblox Studio required.

local fs = require("@lune/fs")
local IslandShape = require("../src/shared/IslandShape")
local Catalog = require("./helpers/Catalog")

local OUT_DIR = "build/island-preview"
local TILE = 360

-- ==========================================================================================
-- Minimal PNG writer (RGB8, stored deflate blocks — no external dependencies)
-- ==========================================================================================

local CRC_TABLE = {}
for n = 0, 255 do
	local c = n
	for _ = 1, 8 do
		if c % 2 == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	CRC_TABLE[n] = c
end

local function crc32(bytes: string): number
	local c = 0xFFFFFFFF
	for i = 1, #bytes do
		c = bit32.bxor(CRC_TABLE[bit32.band(bit32.bxor(c, string.byte(bytes, i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function be32(v: number): string
	return string.char(
		bit32.band(bit32.rshift(v, 24), 0xFF),
		bit32.band(bit32.rshift(v, 16), 0xFF),
		bit32.band(bit32.rshift(v, 8), 0xFF),
		bit32.band(v, 0xFF)
	)
end

local function chunk(kind: string, data: string): string
	return be32(#data) .. kind .. data .. be32(crc32(kind .. data))
end

local function adler32(bytes: string): number
	local a, b = 1, 0
	for i = 1, #bytes do
		a = (a + string.byte(bytes, i)) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end

-- zlib stream made of uncompressed deflate blocks: tiny code, valid PNG.
local function zlibStore(raw: string): string
	local out = { string.char(0x78, 0x01) }
	local pos = 1
	local total = #raw
	repeat
		local len = math.min(65535, total - pos + 1)
		local final = if pos + len > total then 1 else 0
		local nlen = 65535 - len
		table.insert(out, string.char(final))
		table.insert(out, string.char(len % 256, math.floor(len / 256)))
		table.insert(out, string.char(nlen % 256, math.floor(nlen / 256)))
		table.insert(out, string.sub(raw, pos, pos + len - 1))
		pos += len
	until pos > total
	table.insert(out, be32(adler32(raw)))
	return table.concat(out)
end

local function writePng(path: string, width: number, height: number, pixels: { number })
	local rows = {}
	for y = 0, height - 1 do
		local row = { "\0" }
		local base = y * width * 3
		for i = 1, width * 3 do
			table.insert(row, string.char(pixels[base + i] or 0))
		end
		table.insert(rows, table.concat(row))
	end
	local raw = table.concat(rows)
	local header = be32(width) .. be32(height) .. string.char(8, 2, 0, 0, 0)
	local png = string.char(137, 80, 78, 71, 13, 10, 26, 10)
		.. chunk("IHDR", header)
		.. chunk("IDAT", zlibStore(raw))
		.. chunk("IEND", "")
	fs.writeFile(path, png)
end

-- ==========================================================================================
-- Shading
-- ==========================================================================================

local function mix(c1, c2, t)
	return {
		c1[1] + (c2[1] - c1[1]) * t,
		c1[2] + (c2[2] - c1[2]) * t,
		c1[3] + (c2[3] - c1[3]) * t,
	}
end

local OCEAN = { 150, 197, 222 }
local SHELF = { 116, 190, 208 }
local LAGOON = { 26, 118, 205 }
local LAGOON_SHALLOW = { 78, 168, 224 }
local SAND = { 235, 221, 178 }
local SAND_WET = { 214, 199, 156 }
local GRASS = { 86, 156, 66 }
local GRASS_DEEP = { 48, 116, 52 }
local JUNGLE = { 40, 104, 48 }
local ROCK = { 116, 112, 106 }
local BASALT = { 62, 56, 54 }
local SNOW = { 240, 246, 250 }
local LAVA = { 240, 122, 32 }

local function surfaceColor(shape, kind, height, beach)
	if kind == "ocean" then
		return OCEAN
	elseif kind == "shelf" then
		return SHELF
	elseif kind == "water" then
		local depth = math.clamp((shape.seaOffset - height) / 12, 0, 1)
		return mix(LAGOON_SHALLOW, LAGOON, depth)
	end

	if beach then
		return mix(SAND_WET, SAND, math.clamp(height / 2.2, 0, 1))
	end

	local lm = shape.landmark
	if lm and lm.kind == "volcano" and height > lm.height * 0.80 then
		return LAVA
	end
	if shape.biome == "mountain" then
		if height > 95 then
			return SNOW
		elseif height > 40 then
			return mix(ROCK, SNOW, math.clamp((height - 40) / 55, 0, 1))
		end
	end
	if shape.biome == "volcanic" and height > 55 then
		return mix(ROCK, BASALT, math.clamp((height - 55) / 70, 0, 1))
	end
	if height > 60 then
		return mix(GRASS_DEEP, ROCK, math.clamp((height - 60) / 60, 0, 1))
	end

	local base = if shape.biome == "jungle" then JUNGLE else GRASS
	return mix(base, GRASS_DEEP, math.clamp((height - 1) / 26, 0, 1))
end

-- One sample per pixel, cached, then a second pass for the hillshade.
local function renderShape(shape, size: number): { number }
	local reach = (shape.maxCoast + shape.shelfWidth) * 1.04
	local scale = (reach * 2) / size
	local kinds, heights, beaches = {}, {}, {}
	for py = 0, size - 1 do
		local dz = -reach + (py + 0.5) * scale
		local row = py * size
		for px = 0, size - 1 do
			local dx = -reach + (px + 0.5) * scale
			local kind, height, beach = shape:sample(dx, dz)
			local i = row + px
			kinds[i] = kind
			heights[i] = height
			beaches[i] = beach
		end
	end

	local pixels = {}
	for py = 0, size - 1 do
		for px = 0, size - 1 do
			local i = py * size + px
			local kind, height = kinds[i], heights[i]
			local color = surfaceColor(shape, kind, height, beaches[i])
			if kind == "land" then
				-- Light from the north-west, like the reference renders.
				local function landAt(ox: number, oz: number): number
					local nx, nz = px + ox, py + oz
					if nx < 0 or nz < 0 or nx >= size or nz >= size then
						return height
					end
					local j = nz * size + nx
					return if kinds[j] == "land" then heights[j] else 0
				end
				local hx = landAt(1, 0) - landAt(-1, 0)
				local hz = landAt(0, 1) - landAt(0, -1)
				local shade = math.clamp(1 + (-hx - hz) / (scale * 2.2) * 0.5, 0.55, 1.5)
				color = { color[1] * shade, color[2] * shade, color[3] * shade }
			end
			local base = i * 3
			pixels[base + 1] = math.clamp(math.floor(color[1]), 0, 255)
			pixels[base + 2] = math.clamp(math.floor(color[2]), 0, 255)
			pixels[base + 3] = math.clamp(math.floor(color[3]), 0, 255)
		end
	end
	return pixels
end

-- ==========================================================================================
-- Run
-- ==========================================================================================

if not fs.isDir("build") then
	fs.writeDir("build")
end
if not fs.isDir(OUT_DIR) then
	fs.writeDir(OUT_DIR)
end

local entries = Catalog.load()
print(`\nRendering {#entries} catalog islands into {OUT_DIR}/\n`)

local sheetCols = 4
local sheetRows = math.ceil(#entries / sheetCols)
local sheetTile = 224
local sheetW, sheetH = sheetCols * sheetTile, sheetRows * sheetTile
local sheet = {}
for i = 1, sheetW * sheetH * 3 do
	sheet[i] = 255
end

for index, entry in entries do
	local shape = Catalog.shapeFor(IslandShape, entry)
	local pixels = renderShape(shape, TILE)
	writePng(`{OUT_DIR}/{entry.Id}.png`, TILE, TILE, pixels)

	local small = renderShape(shape, sheetTile)
	local col = (index - 1) % sheetCols
	local row = math.floor((index - 1) / sheetCols)
	for y = 0, sheetTile - 1 do
		for x = 0, sheetTile - 1 do
			local src = (y * sheetTile + x) * 3
			local dst = ((row * sheetTile + y) * sheetW + (col * sheetTile + x)) * 3
			sheet[dst + 1] = small[src + 1]
			sheet[dst + 2] = small[src + 2]
			sheet[dst + 3] = small[src + 3]
		end
	end

	print(string.format(
		"  %-16s %-9s coast %4.0f-%4.0f (x%.2f)  lagoon %2d%%  landmark %-8s %3.0f  village r%3.0f",
		entry.Id,
		entry.Biome,
		shape.minCoast,
		shape.maxCoast,
		shape.maxCoast / shape.minCoast,
		math.floor(Catalog.waterFraction(shape) * 100),
		shape.landmark.kind,
		shape.landmark.height,
		shape.buildableRadius
	))
end

writePng(`{OUT_DIR}/contact-sheet.png`, sheetW, sheetH, sheet)
print(`\nWrote {#entries} island PNGs + contact-sheet.png\n`)
