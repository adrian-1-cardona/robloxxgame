-- Streams Roblox Terrain water around the lobby pier and every sailing raft.
-- Engine water gives real waves / reflection; chunks keep the infinite ocean cheap.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))

local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))
local IslandService = require(script.Parent:WaitForChild("IslandService"))

local OceanTerrainService = {}

local CHUNK = OceanConfig.ChunkStuds
local RADIUS = OceanConfig.KeepRadiusChunks
local DEPTH = OceanConfig.DepthStuds
local SURFACE_Y = OceanConfig.SurfaceY

-- chunkKey -> true while filled with water
local activeChunks: { [string]: boolean } = {}
local started = false

local function terrain(): Terrain
	return Workspace.Terrain
end

local function applyWaterMaterial()
	local t = terrain()
	t.WaterColor = OceanConfig.WaterColor
	t.WaterReflectance = OceanConfig.WaterReflectance
	t.WaterTransparency = OceanConfig.WaterTransparency
	t.WaterWaveSize = OceanConfig.WaterWaveSize
	t.WaterWaveSpeed = OceanConfig.WaterWaveSpeed
end

local function chunkKey(cx: number, cz: number): string
	return `{cx},{cz}`
end

local function worldToChunk(x: number, z: number): (number, number)
	return math.floor(x / CHUNK), math.floor(z / CHUNK)
end

local function fillChunk(cx: number, cz: number)
	local key = chunkKey(cx, cz)
	if activeChunks[key] then
		return
	end

	local centerX = cx * CHUNK + CHUNK * 0.5
	local centerZ = cz * CHUNK + CHUNK * 0.5
	local centerY = SURFACE_Y - DEPTH * 0.5
	terrain():FillBlock(
		CFrame.new(centerX, centerY, centerZ),
		Vector3.new(CHUNK, DEPTH, CHUNK),
		Enum.Material.Water
	)
	activeChunks[key] = true
end

local function clearChunk(cx: number, cz: number)
	local key = chunkKey(cx, cz)
	if not activeChunks[key] then
		return
	end

	local centerX = cx * CHUNK + CHUNK * 0.5
	local centerZ = cz * CHUNK + CHUNK * 0.5
	local centerY = SURFACE_Y - DEPTH * 0.5
	terrain():FillBlock(
		CFrame.new(centerX, centerY, centerZ),
		Vector3.new(CHUNK, DEPTH, CHUNK),
		Enum.Material.Air
	)
	activeChunks[key] = nil
end

local function ensureAround(x: number, z: number, wanted: { [string]: boolean })
	local cx, cz = worldToChunk(x, z)
	for dx = -RADIUS, RADIUS do
		for dz = -RADIUS, RADIUS do
			local nx, nz = cx + dx, cz + dz
			local key = chunkKey(nx, nz)
			wanted[key] = true
			fillChunk(nx, nz)
		end
	end
end

local function collectFocusPoints(): { Vector3 }
	local points = {
		Vector3.new(0, SURFACE_Y, 40), -- boarding pier
		Config.StarterBase.Origin,
		IslandService.getWorldCenter(), -- tiny drive-to isle
	}

	for _, model in StarterBaseService._basesByCode do
		local deck = model.PrimaryPart or model:FindFirstChild("Deck")
		if deck and deck:IsA("BasePart") then
			table.insert(points, deck.Position)
		end
	end

	return points
end

local function streamOnce()
	local wanted: { [string]: boolean } = {}
	for _, pos in collectFocusPoints() do
		ensureAround(pos.X, pos.Z, wanted)
	end

	local stale: { string } = {}
	for key, _ in activeChunks do
		if not wanted[key] then
			table.insert(stale, key)
		end
	end
	for _, key in stale do
		local cxStr, czStr = string.match(key, "^(%-?%d+),(%-?%d+)$")
		if cxStr and czStr then
			clearChunk(tonumber(cxStr) :: number, tonumber(czStr) :: number)
		end
	end

	-- Re-paint sand after water fills so the isle stays land
	IslandService.paintTerrain()
end

-- Hide legacy flat-glass ocean parts so Terrain water is the visible sea.
local function hideLegacyOceanParts()
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if not (root and root:IsA("Folder")) then
		return
	end

	for _, name in { "OceanSurface", "OceanDeep" } do
		local part = root:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end

	local bases = root:FindFirstChild("StarterBases")
	if not bases then
		return
	end
	for _, model in bases:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		for _, name in { "LocalSea", "LocalSeaDeep" } do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
			end
		end
	end
end

function OceanTerrainService.start()
	if started then
		return
	end
	started = true

	applyWaterMaterial()
	hideLegacyOceanParts()
	streamOnce()

	local accum = 0
	local interval = 1 / math.max(OceanConfig.StreamHz, 0.5)
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < interval then
			return
		end
		accum = 0
		hideLegacyOceanParts()
		streamOnce()
	end)

	print("[SurviveAtSea] Ocean terrain streaming online — realistic waves enabled")
end

return OceanTerrainService
