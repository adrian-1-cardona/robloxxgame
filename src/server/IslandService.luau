-- Stationary open-sea islands: huge beach flats with grass / jungle / palms,
-- detachable house walls + scattered loot, optional raid houses + chasing pirates.
-- Visit lockout: step on an isle, leave on the raft, sail LockoutStuds away → can't return.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Armor = require(Shared:WaitForChild("Armor"))

local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))
local LootPropFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("LootPropFactory"))
local NpcFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("NpcFactory"))
local VillageBuilder = require(script.Parent:WaitForChild("VillageBuilder"))
local MerchantService = require(script.Parent:WaitForChild("MerchantService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local ArmorService = require(script.Parent:WaitForChild("ArmorService"))

export type IslandRecord = {
	id: string,
	name: string,
	center: Vector3,
	size: number,
	topY: number,
	thickness: number,
	theme: string,
	abandoned: boolean,
	biome: string,
	model: Model,
	label: TextLabel?,
	npcs: { Model },
	-- Villagers are spawned lazily (see populateIsland) the first time a crew lands, so
	-- the world starts with no villagers. This plan holds what to spawn and where.
	villagerPlan: {
		spots: { Vector3 },
		passive: number,
		hostile: number,
		abandoned: boolean,
	}?,
	populated: boolean?,
}

type CrewIslandState = {
	visited: boolean,
	locked: boolean,
	notifiedLock: boolean,
	notifiedVisit: boolean,
}

type NpcRuntime = {
	model: Model,
	humanoid: Humanoid?,
	islandId: string,
	hostile: boolean,
	attackAccum: number,
	wanderAccum: number,
	homePos: Vector3,
	targetPos: Vector3?,
	alive: boolean,
}

local IslandService = {}

IslandService._islands = {} :: { IslandRecord }
IslandService._byId = {} :: { [string]: IslandRecord }
IslandService._crewState = {} :: { [string]: { [string]: CrewIslandState } }
IslandService._npcs = {} :: { NpcRuntime }
IslandService._Toast = nil :: RemoteEvent?
IslandService._getPartyCode = nil :: ((Player) -> string?)?
IslandService._getMemberUserIds = nil :: ((string) -> { number })?
IslandService._started = false

local function lobbyRoot(): Folder
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if root and root:IsA("Folder") then
		return root
	end
	return LobbyWorld.ensure()
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "IslandPart"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.Sand
	p.Color = props.Color or Color3.fromRGB(220, 200, 158)
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- Decorative scatter parts default to NO shadow. With ShadowMap + thousands of props
	-- per isle, per-part shadow casting was the single biggest GPU cost. Terrain/sun
	-- shadows (GlobalShadows) still ground the world; individual props opt in only if
	-- they explicitly pass CastShadow = true.
	p.CastShadow = props.CastShadow == true
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.Shape ~= nil then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function worldCenterForOffset(offset: Vector3, topY: number, thickness: number): Vector3
	local origin = Config.StarterBase.Origin
	return Vector3.new(origin.X + offset.X, topY - thickness * 0.5, origin.Z + offset.Z)
end

local function ensureCrewState(code: string, islandId: string): CrewIslandState
	local byIsle = IslandService._crewState[code]
	if not byIsle then
		byIsle = {}
		IslandService._crewState[code] = byIsle
	end
	local state = byIsle[islandId]
	if not state then
		state = {
			visited = false,
			locked = false,
			notifiedLock = false,
			notifiedVisit = false,
		}
		byIsle[islandId] = state
	end
	return state
end

local function buildPalm(model: Model, topY: number, x: number, z: number, scale: number?)
	local s = scale or (0.85 + math.random() * 0.45)
	local trunkH = (10 + math.random() * 5) * s
	local lean = math.rad((math.random() - 0.5) * 16)
	local trunk = makePart({
		Name = "PalmTrunk",
		Parent = model,
		Size = Vector3.new(0.95 * s, trunkH, 0.95 * s),
		CFrame = CFrame.new(x, topY + trunkH * 0.5, z) * CFrame.Angles(0, math.rad(math.random(0, 360)), lean),
		Color = Color3.fromRGB(92, 64, 38),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	local frondColors = {
		Color3.fromRGB(48, 118, 62),
		Color3.fromRGB(42, 108, 55),
		Color3.fromRGB(56, 132, 70),
		Color3.fromRGB(38, 98, 52),
	}
	for i = 0, 4 do
		local yaw = math.rad(i * 72 + math.random(-12, 12))
		local pitch = math.rad(8 + math.random() * 18)
		makePart({
			Name = `PalmFrond_{i}`,
			Parent = model,
			Size = Vector3.new((6.5 + math.random() * 2.5) * s, 0.32 * s, (1.6 + math.random() * 0.6) * s),
			CFrame = trunk.CFrame
				* CFrame.new(0, trunkH * 0.46, 0)
				* CFrame.Angles(pitch, yaw, math.rad((math.random() - 0.5) * 12)),
			Color = frondColors[(i % #frondColors) + 1],
			Material = Enum.Material.Grass,
			CanCollide = false,
			-- Fronds are small and everywhere; skipping their shadows is a big perf win.
			CastShadow = false,
		})
	end
	-- Coconuts cluster
	if math.random() < 0.55 then
		makePart({
			Name = "Coconuts",
			Parent = model,
			Size = Vector3.new(1.1 * s, 1.0 * s, 1.1 * s),
			CFrame = trunk.CFrame * CFrame.new(0.35 * s, trunkH * 0.42, 0.1 * s),
			Color = Color3.fromRGB(72, 48, 28),
			Material = Enum.Material.Wood,
			CanCollide = false,
			CastShadow = false,
			Shape = Enum.PartType.Ball,
		})
	end
end

-- A tiny splash of tropical colour — cheap, shadowless flowers for nicer beaches.
local function buildFlower(model: Model, topY: number, x: number, z: number)
	local palette = {
		Color3.fromRGB(240, 96, 120),
		Color3.fromRGB(255, 186, 72),
		Color3.fromRGB(210, 120, 240),
		Color3.fromRGB(255, 240, 150),
	}
	makePart({
		Name = "Flower",
		Parent = model,
		Size = Vector3.new(0.7, 0.7, 0.7),
		CFrame = CFrame.new(x, topY + 0.5, z),
		Color = palette[math.random(1, #palette)],
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Shape = Enum.PartType.Ball,
	})
end

local function buildBush(model: Model, topY: number, x: number, z: number, jungle: boolean)
	local h = if jungle then 2.8 + math.random() * 2.2 else 1.4 + math.random() * 1.2
	local w = if jungle then 4.5 + math.random() * 2.5 else 2.8 + math.random() * 1.6
	makePart({
		Name = "Bush",
		Parent = model,
		Size = Vector3.new(w, h, w * (0.75 + math.random() * 0.35)),
		CFrame = CFrame.new(x, topY + h * 0.45, z),
		Color = if jungle then Color3.fromRGB(28, 78, 38) else Color3.fromRGB(52, 118, 58),
		Material = Enum.Material.Grass,
		CanCollide = false,
		CastShadow = false,
		Shape = Enum.PartType.Ball,
	})
end

local function buildGrassTuft(model: Model, topY: number, x: number, z: number)
	makePart({
		Name = "GrassTuft",
		Parent = model,
		Size = Vector3.new(1.6 + math.random(), 1.1 + math.random() * 0.8, 0.35),
		CFrame = CFrame.new(x, topY + 0.7, z) * CFrame.Angles(0, math.rad(math.random(0, 360)), math.rad((math.random() - 0.5) * 20)),
		Color = Color3.fromRGB(68, 140, 62),
		Material = Enum.Material.Grass,
		CanCollide = false,
		CastShadow = false,
	})
end

local function buildJungleTree(model: Model, topY: number, x: number, z: number)
	local trunkH = 14 + math.random() * 8
	local trunk = makePart({
		Name = "JungleTrunk",
		Parent = model,
		Size = Vector3.new(1.4, trunkH, 1.4),
		CFrame = CFrame.new(x, topY + trunkH * 0.5, z),
		Color = Color3.fromRGB(62, 44, 28),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	for i = 0, 2 do
		makePart({
			Name = `Canopy_{i}`,
			Parent = model,
			Size = Vector3.new(8 + math.random() * 4, 4 + math.random() * 2, 8 + math.random() * 4),
			CFrame = trunk.CFrame * CFrame.new((math.random() - 0.5) * 2, trunkH * 0.42 + i * 1.2, (math.random() - 0.5) * 2),
			Color = Color3.fromRGB(24 + i * 8, 72 + i * 10, 34 + i * 6),
			Material = Enum.Material.Grass,
			CanCollide = false,
			-- Only the lowest canopy blob casts shadow; upper blobs skip it (perf).
			CastShadow = i == 0,
			Shape = Enum.PartType.Ball,
		})
	end
end

-- A towering buttressed rainforest giant (kapok / ceiba) — the Amazon canopy centrepiece.
-- Massive trunk with flaring root buttresses and a broad, layered canopy.
local function buildGiantTree(model: Model, topY: number, x: number, z: number)
	local trunkH = 30 + math.random() * 18
	local trunk = makePart({
		Name = "GiantTrunk",
		Parent = model,
		Size = Vector3.new(3.4, trunkH, 3.4),
		CFrame = CFrame.new(x, topY + trunkH * 0.5, z),
		Color = Color3.fromRGB(112, 86, 60),
		Material = Enum.Material.Wood,
		CanCollide = true,
	})
	-- Flaring root buttresses around the base.
	for i = 0, 4 do
		local a = math.rad(i * 72 + math.random(-10, 10))
		makePart({
			Name = `Buttress_{i}`,
			Parent = model,
			Size = Vector3.new(1.2, 6 + math.random() * 2, 3.2),
			CFrame = CFrame.new(x + math.cos(a) * 2.2, topY + 2.5, z + math.sin(a) * 2.2)
				* CFrame.Angles(0, -a, math.rad(16)),
			Color = Color3.fromRGB(98, 74, 50),
			Material = Enum.Material.Wood,
			CanCollide = false,
			CastShadow = false,
		})
	end
	-- Broad, layered emergent canopy.
	for i = 0, 3 do
		makePart({
			Name = `GiantCanopy_{i}`,
			Parent = model,
			Size = Vector3.new(20 - i * 3, 5 + math.random() * 2, 20 - i * 3),
			CFrame = trunk.CFrame * CFrame.new((math.random() - 0.5) * 3, trunkH * 0.42 + i * 3.4, (math.random() - 0.5) * 3),
			Color = Color3.fromRGB(22 + i * 6, 74 + i * 10, 32 + i * 6),
			Material = Enum.Material.LeafyGrass,
			CanCollide = false,
			CastShadow = i == 0,
			Shape = Enum.PartType.Ball,
		})
	end
end

-- Low broad rainforest ferns / undergrowth fronds — thick green floor cover.
local function buildFern(model: Model, topY: number, x: number, z: number)
	local blades = math.random(3, 5)
	for i = 1, blades do
		local a = math.rad((i / blades) * 360 + math.random(-20, 20))
		makePart({
			Name = "Fern",
			Parent = model,
			Size = Vector3.new(2.6 + math.random() * 1.4, 0.28, 0.9 + math.random() * 0.5),
			CFrame = CFrame.new(x, topY + 0.7, z)
				* CFrame.Angles(0, a, math.rad(22 + math.random() * 14)),
			Color = Color3.fromRGB(34, 98, 44),
			Material = Enum.Material.LeafyGrass,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

-- A climbable jungle vine: a TrussPart (auto-climbable by Humanoids) dressed with a couple
-- of leafy strips, giving players a real way to scale the isle's rocky peaks and cliffs.
local function buildClimbVine(model: Model, topY: number, x: number, z: number, height: number)
	local truss = Instance.new("TrussPart")
	truss.Name = "ClimbVine"
	truss.Anchored = true
	truss.CanCollide = true
	truss.Color = Color3.fromRGB(64, 88, 42)
	truss.Material = Enum.Material.Grass
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = CFrame.new(x, topY + height * 0.5, z)
	truss.CastShadow = false
	truss.Parent = model
	-- Leafy dressing so it reads as a hanging vine, not scaffolding.
	for i = 0, 2 do
		makePart({
			Name = `VineLeaf_{i}`,
			Parent = model,
			Size = Vector3.new(1.4, 1.2, 0.3),
			CFrame = CFrame.new(x + (i - 1) * 0.7, topY + height * (0.3 + i * 0.25), z - 1.1)
				* CFrame.Angles(0, math.rad(math.random(0, 360)), 0),
			Color = Color3.fromRGB(40, 104, 46),
			Material = Enum.Material.LeafyGrass,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

local function buildRock(model: Model, topY: number, x: number, z: number, scale: number?)
	local s = scale or (1 + math.random() * 1.7)
	local g = 92 + math.random(0, 34)
	local rockColor = Color3.fromRGB(g, g + 5, g + 12)
	-- A boulder is a small cluster of overlapping tilted blocks so it reads as weathered stone
	for _ = 1, math.random(2, 4) do
		local rs = s * (0.55 + math.random() * 0.75)
		makePart({
			Name = "Rock",
			Parent = model,
			Size = Vector3.new(2.6 * rs, 2.1 * rs, 2.4 * rs),
			CFrame = CFrame.new(x + (math.random() - 0.5) * 2.2 * s, topY + 0.65 * rs, z + (math.random() - 0.5) * 2.2 * s)
				* CFrame.Angles(
					math.rad(math.random(-18, 18)),
					math.rad(math.random(0, 360)),
					math.rad(math.random(-18, 18))
				),
			Color = rockColor,
			Material = Enum.Material.Slate,
			CanCollide = true,
		})
	end
end

local function buildDriftwood(model: Model, topY: number, x: number, z: number)
	local len = 5 + math.random() * 5
	local yaw = math.rad(math.random(0, 360))
	local log = makePart({
		Name = "Driftwood",
		Parent = model,
		Size = Vector3.new(len, 1.15, 1.15),
		CFrame = CFrame.new(x, topY + 0.5, z) * CFrame.Angles(0, yaw, math.rad((math.random() - 0.5) * 12)),
		Color = Color3.fromRGB(122, 98, 74),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	log.Shape = Enum.PartType.Cylinder
	-- A stub branch for a gnarled, beached look
	if math.random() < 0.5 then
		local branch = makePart({
			Name = "DriftwoodBranch",
			Parent = model,
			Size = Vector3.new(len * 0.4, 0.7, 0.7),
			CFrame = log.CFrame * CFrame.new(len * 0.15, 0.3, 0) * CFrame.Angles(0, math.rad(50), 0),
			Color = Color3.fromRGB(112, 90, 68),
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		branch.Shape = Enum.PartType.Cylinder
	end
end

-- Low rounded grass/sand mound — gentle rolling terrain so the flat isn't dead flat
local function buildDune(model: Model, topY: number, x: number, z: number, grass: boolean)
	local w = 8 + math.random() * 10
	local h = 1.6 + math.random() * 2.4
	makePart({
		Name = "Dune",
		Parent = model,
		Size = Vector3.new(w, h * 2, w * (0.8 + math.random() * 0.4)),
		-- Half-buried ball so only a smooth rise shows above the sand
		CFrame = CFrame.new(x, topY - h * 0.5, z),
		Color = if grass then Color3.fromRGB(74, 138, 66) else Color3.fromRGB(224, 204, 160),
		Material = if grass then Enum.Material.Grass else Enum.Material.Sand,
		CanCollide = false,
		CastShadow = false,
		Shape = Enum.PartType.Ball,
	})
end

-- A conifer/pine — the signature tree of temperate "highland" and cold "mountain" isles.
-- Brown trunk with 3 stacked green cones; on mountain isles the tip gets a snowy cap.
local function buildPine(model: Model, topY: number, x: number, z: number, snowy: boolean?, scale: number?)
	local s = scale or (0.85 + math.random() * 0.5)
	local trunkH = (5 + math.random() * 3) * s
	makePart({
		Name = "PineTrunk",
		Parent = model,
		Size = Vector3.new(1.1 * s, trunkH, 1.1 * s),
		CFrame = CFrame.new(x, topY + trunkH * 0.5, z),
		Color = Color3.fromRGB(84, 58, 36),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	local tiers = 3
	local tierH = 5 * s
	for i = 0, tiers - 1 do
		local w = (8 - i * 2.2) * s
		makePart({
			Name = `PineTier_{i}`,
			Parent = model,
			Size = Vector3.new(w, tierH, w),
			CFrame = CFrame.new(x, topY + trunkH + i * tierH * 0.62 + tierH * 0.4, z),
			Color = Color3.fromRGB(30 + i * 6, 82 + i * 8, 44 + i * 4),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CastShadow = i == 0,
		})
	end
	-- Snowy cap tip for cold isles.
	if snowy then
		makePart({
			Name = "PineSnow",
			Parent = model,
			Size = Vector3.new(2.4 * s, 1.6 * s, 2.4 * s),
			CFrame = CFrame.new(x, topY + trunkH + tiers * tierH * 0.62 + 0.4, z),
			Color = Color3.fromRGB(238, 244, 250),
			Material = Enum.Material.Snow,
			CanCollide = false,
			CastShadow = false,
			Shape = Enum.PartType.Ball,
		})
	end
end

-- A cluster of glowing emerald crystals poking out of the ground — the loot-y "green
-- gems" seen on tropical + mountain isles. Cheap, shadowless Neon shards.
local function buildGem(model: Model, topY: number, x: number, z: number)
	local shards = math.random(2, 4)
	for i = 1, shards do
		local h = 1.4 + math.random() * 2.2
		local a = math.rad(math.random(0, 360))
		local off = i == 1 and 0 or (0.6 + math.random() * 1.0)
		local gx = x + math.cos(a) * off
		local gz = z + math.sin(a) * off
		makePart({
			Name = "Gem",
			Parent = model,
			Size = Vector3.new(0.9, h, 0.9),
			CFrame = CFrame.new(gx, topY + h * 0.4, gz)
				* CFrame.Angles(math.rad((math.random() - 0.5) * 26), a, math.rad((math.random() - 0.5) * 26)),
			Color = Color3.fromRGB(70, 220, 130),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

local function scatterVegetation(model: Model, center: Vector3, size: number, topY: number, biome: string, features: { [string]: any }?)
	local half = size * 0.5
	local beachBand = half * 0.78 -- outer ring stays sandier; vegetation denser inward

	-- Feature exclusion: never scatter flora inside a lake, on top of a volcano cone, or
	-- on a mountain peak — those get their own treatment. Returns true if (x,z) is blocked.
	local feat = features or {}
	local function blocked(x: number, z: number): boolean
		local lake = feat.lake
		if lake then
			local dx, dz = x - lake.pos.X, z - lake.pos.Z
			if dx * dx + dz * dz < (lake.radius + 6) * (lake.radius + 6) then
				return true
			end
		end
		local volcano = feat.volcano
		if volcano then
			local dx, dz = x - volcano.pos.X, z - volcano.pos.Z
			if dx * dx + dz * dz < (volcano.baseR + 4) * (volcano.baseR + 4) then
				return true
			end
		end
		local peak = feat.peak
		if peak then
			local dx, dz = x - peak.pos.X, z - peak.pos.Z
			if dx * dx + dz * dz < (peak.baseR + 4) * (peak.baseR + 4) then
				return true
			end
		end
		return false
	end

	-- Which flora suits this biome. Tropical isles get palms; temperate highlands and cold
	-- mountains get pines instead; volcanic + mountain isles also grow loot-y gem clusters.
	local hasPalms = biome ~= "highland" and biome ~= "mountain"
	local hasPines = biome == "highland" or biome == "mountain"
	local hasGems = biome == "volcanic" or biome == "mountain"
	local snowy = biome == "mountain"

	-- Density divisors are tuned so isles stay lush and explorable while keeping the
	-- per-isle part count LOW (island area grows with the square of the radius, and a
	-- fast raft streams several isles' worth of parts in quickly — a big divisor keeps
	-- the approach smooth and lag-free instead of dumping thousands of parts at once).
	if hasPalms then
		local palmCount = math.floor(size / 28)
		if biome == "beach" then
			palmCount = math.floor(size / 32)
		elseif biome == "jungle" then
			palmCount = math.floor(size / 28)
		end
		for _ = 1, palmCount do
			local angle = math.random() * math.pi * 2
			-- Prefer shoreline palms for beach vibe
			local r = half * (0.55 + math.random() * 0.38)
			if biome == "jungle" and math.random() < 0.35 then
				r = half * (0.15 + math.random() * 0.4)
			end
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildPalm(model, topY, x, z)
		end
	end

	-- Conifer forest for highland / mountain isles.
	if hasPines then
		local pineCount = if biome == "mountain" then math.floor(size / 26) else math.floor(size / 22)
		for _ = 1, pineCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.18 + math.random() * 0.68)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildPine(model, topY, x, z, snowy)
		end
	end

	-- Glowing emerald gem clusters (tropical volcanic + mountain isles).
	if hasGems then
		local gemCount = math.clamp(math.floor(size / 90), 3, 14)
		for _ = 1, gemCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.2 + math.random() * 0.66)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildGem(model, topY, x, z)
		end
	end

	local bushCount = math.floor(size / 22)
	for _ = 1, bushCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.12 + math.random() * 0.7)
		if r > beachBand and biome == "beach" then
			continue
		end
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		if blocked(x, z) then
			continue
		end
		buildBush(model, topY, x, z, biome == "jungle")
	end

	local tuftCount = math.floor(size / 17)
	for _ = 1, tuftCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.65)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		if blocked(x, z) then
			continue
		end
		buildGrassTuft(model, topY, x, z)
	end

	-- Broadleaf trees for jungle / palm / volcanic isles (volcanic isles are lush tropical
	-- slopes around a bare cone).
	local leafy = biome == "jungle" or biome == "palm" or biome == "volcanic"
	if leafy then
		local treeCount = if biome == "jungle" then math.floor(size / 42) else math.floor(size / 60)
		for _ = 1, treeCount do
			local angle = math.random() * math.pi * 2
			-- Keep the very center clear for the hill/village heart, then spread trees
			-- across most of the interior so a huge jungle isle is dense to explore.
			local r = half * (0.22 + math.random() * 0.6)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildJungleTree(model, topY, x, z)
		end
	end

	-- Amazon rainforest layer: buttressed canopy giants, thick ferns on the floor, and
	-- climbable vines out on the peaks so the relief is scalable ("places to climb").
	-- Denser on jungle isles, a lighter touch on palm / volcanic isles.
	if leafy then
		local giantCount = if biome == "jungle" then math.floor(size / 120) else math.floor(size / 220)
		for _ = 1, giantCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.25 + math.random() * 0.5)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildGiantTree(model, topY, x, z)
		end

		local fernCount = if biome == "jungle" then math.floor(size / 18) else math.floor(size / 32)
		for _ = 1, fernCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.15 + math.random() * 0.7)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildFern(model, topY, x, z)
		end

		local vineCount = math.clamp(math.floor(size / 160), 2, 7)
		for _ = 1, vineCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.62 + math.random() * 0.28)
			local h = 24 + math.random() * 18
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildClimbVine(model, topY, x, z, h)
		end
	end

	-- Rolling dunes across the interior — breaks up the flat with gentle rises
	local duneCount = math.floor(size / 64)
	for _ = 1, duneCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.62)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		if blocked(x, z) then
			continue
		end
		buildDune(model, topY, x, z, math.random() < 0.6)
	end

	-- Rock outcrops — a few inland, more clustered near the shoreline
	local rockCount = math.floor(size / 96)
	for _ = 1, rockCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.35 + math.random() * 0.55)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		if blocked(x, z) then
			continue
		end
		buildRock(model, topY, x, z)
	end

	-- Weathered driftwood logs washed up along the beach ring
	local driftCount = math.clamp(math.floor(size / 70), 2, 6)
	for _ = 1, driftCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.72 + math.random() * 0.2)
		buildDriftwood(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r)
	end

	-- Scattered flowers for colour (shadowless, so nearly free). Tropical + temperate only.
	if biome ~= "mountain" then
		local flowerCount = math.floor(size / 46)
		for _ = 1, flowerCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.18 + math.random() * 0.62)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			if blocked(x, z) then
				continue
			end
			buildFlower(model, topY, x, z)
		end
	end
end

local function scatterLooseLoot(model: Model, center: Vector3, size: number, topY: number, islandId: string)
	local half = size * 0.5
	local lootFolder = Instance.new("Folder")
	lootFolder.Name = "IsleLoot"
	lootFolder.Parent = model

	-- Torches stuck in the sand / grass
	local torchCount = math.clamp(math.floor(size / 55), 2, 5)
	for i = 1, torchCount do
		local angle = (i / torchCount) * math.pi * 2 + math.random() * 0.4
		local r = half * (0.25 + math.random() * 0.45)
		local cf = CFrame.new(center.X + math.cos(angle) * r, topY + 1.7, center.Z + math.sin(angle) * r)
		local torch = LootPropFactory.createTorchWorld(lootFolder, cf)
		torch:SetAttribute("IslandId", islandId)
	end

	-- Salvage planks & crates along the beach ring
	local plankCount = math.clamp(math.floor(size / 40), 3, 8)
	for i = 1, plankCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.62 + math.random() * 0.28)
		local yaw = math.rad(math.random(0, 360))
		local cf = CFrame.new(center.X + math.cos(angle) * r, topY + 0.35, center.Z + math.sin(angle) * r)
			* CFrame.Angles(0, yaw, math.rad((math.random() - 0.5) * 8))
		local plank = LootPropFactory.createPlankWorld(lootFolder, cf)
		plank:SetAttribute("IslandId", islandId)
	end

	local crateCount = math.clamp(math.floor(size / 70), 1, 4)
	for i = 1, crateCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.5)
		local cf = CFrame.new(center.X + math.cos(angle) * r, topY + 1.2, center.Z + math.sin(angle) * r)
		local crate = LootPropFactory.createCrateWorld(lootFolder, cf)
		crate:SetAttribute("IslandId", islandId)
	end
end

-- When any villager on an isle is attacked, the whole village turns out to defend it:
-- passive islanders flip to red-eyed hostile defenders and hunt the attacker.
local function defendIsland(islandId: string)
	for _, rt in IslandService._npcs do
		if rt.islandId == islandId and rt.alive and not rt.hostile then
			rt.hostile = true
			rt.model:SetAttribute("Hostile", true)
			rt.model:SetAttribute("IsPirate", true)
			NpcFactory.makeHostileLook(rt.model)
		end
	end
end

-- Spawn a single villager NPC. kind: "passive" | "hostile" | "scavenger".
local function spawnVillager(island: IslandRecord, cf: CFrame, kind: string): Model
	local cfg = Config.Islands.Villager
	local hostile = kind ~= "passive"
	local health = cfg.Passive.Health
	if kind == "hostile" then
		health = cfg.Hostile.Health
	elseif kind == "scavenger" then
		health = cfg.Scavenger.Health
	end

	local model, humanoid = NpcFactory.createVillager(island.model, cf, {
		hostile = hostile,
		scavenger = kind == "scavenger",
		islandId = island.id,
		health = health,
	})

	local runtime: NpcRuntime = {
		model = model,
		humanoid = humanoid,
		islandId = island.id,
		hostile = hostile,
		attackAccum = 0,
		wanderAccum = math.random() * 2,
		homePos = cf.Position,
		targetPos = nil,
		alive = true,
	}

	-- Passive villagers defend their home the moment they take a hit.
	if kind == "passive" and cfg.Passive.DefendOnAttack then
		local prevHealth = humanoid.Health
		humanoid.HealthChanged:Connect(function(h)
			if h < prevHealth and runtime.alive then
				defendIsland(island.id)
			end
			prevHealth = h
		end)
	end

	humanoid.Died:Connect(function()
		runtime.alive = false
	end)

	table.insert(island.npcs, model)
	table.insert(IslandService._npcs, runtime)
	return model
end

-- Bring an island's people to life. Villagers are NOT spawned at world-gen — the world
-- starts empty of villagers — so this is called the first time a crew sets foot on the
-- isle (from updateVisitLockouts). Idempotent: only ever populates once per isle.
local function populateIsland(record: IslandRecord)
	if record.populated then
		return
	end
	record.populated = true

	local plan = record.villagerPlan
	if not plan then
		return
	end

	local spots = plan.spots
	local spotCount = math.max(#spots, 1)
	local center, topY = record.center, record.topY
	local function spotAt(i: number): CFrame
		local base = spots[((i - 1) % spotCount) + 1] or Vector3.new(center.X, topY + 2.5, center.Z)
		local jitter = Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8)
		local pos = base + jitter
		return CFrame.new(Vector3.new(pos.X, topY + 2.5, pos.Z))
	end

	if plan.abandoned then
		-- Rare feral scavengers only.
		for i = 1, plan.hostile do
			spawnVillager(record, spotAt(i), "scavenger")
		end
	else
		for i = 1, plan.passive do
			spawnVillager(record, spotAt(i), "passive")
		end
		for i = 1, plan.hostile do
			spawnVillager(record, spotAt(i + 3), "hostile")
		end
	end
end

-- Stable per-isle seed from its id so an island's terrain is identical every build
-- (deterministic) but distinct from every other island.
local function seedFromId(id: string): number
	local h = 2166136261
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 2147483647
	end
	return h
end

-- Enhanced terrain generation with better foundations for medieval villages
local function generateIslandTerrain(
	id: string,
	center: Vector3,
	topY: number,
	size: number,
	biome: string,
	theme: string,
	features: { [string]: any }
)
	local Terrain = Workspace.Terrain
	local rng = Random.new(seedFromId(id))
	local cx, cz = center.X, center.Z
	local half = size * 0.5
	local surfaceY = OceanConfig.SurfaceY
	local isTown = theme == "town" or theme == "stone_town"
	local hasVillage = theme ~= "wild" and theme ~= "abandoned"

	local grassMat = if biome == "jungle" or biome == "volcanic"
		then Enum.Material.LeafyGrass
		else Enum.Material.Grass
	local sandMat = Enum.Material.Sand

	-- Solid land column from a submerged base up to a flat top face at `topAt`.
	local baseBottom = surfaceY - 40
	local function landColumn(px: number, pz: number, radius: number, topAt: number, material: Enum.Material)
		local h = topAt - baseBottom
		if h <= 0 then
			return
		end
		Terrain:FillCylinder(CFrame.new(px, (topAt + baseBottom) * 0.5, pz), h, radius, material)
	end

	-- Enhanced foundation for villages: create a flatter, more stable base
	if hasVillage then
		-- Create a larger, flatter foundation for villages with smoother terrain
		local villageFoundationRadius = if isTown then half * 0.75 else half * 0.6
		local foundationHeight = topY + 0.5
		
		-- Main village foundation - perfectly flat for cobblestone streets
		Terrain:FillCylinder(
			CFrame.new(cx, (foundationHeight + topY) * 0.5, cz), 
			foundationHeight - topY, 
			villageFoundationRadius, 
			grassMat
		)
		
		-- Smooth transition zones around the village center
		for ring = 1, 3 do
			local ringRadius = villageFoundationRadius + (ring * half * 0.08)
			local ringHeight = topY - (ring * 0.3)
			if ringRadius < half * 0.95 then  -- Don't exceed island bounds
				Terrain:FillCylinder(
					CFrame.new(cx, (ringHeight + topY - 2) * 0.5, cz),
					math.abs(ringHeight - topY + 2),
					ringRadius,
					if ring == 3 then sandMat else grassMat
				)
			end
		end
		
		-- Add subtle terracing for medieval hillside village aesthetic
		if theme == "stone_town" or theme == "town" then
			for tier = 1, 2 do
				local tierAngle = rng:NextNumber(0, math.pi * 2)
				local tierDistance = villageFoundationRadius * 0.7 * tier
				local tierX = cx + math.cos(tierAngle) * tierDistance
				local tierZ = cz + math.sin(tierAngle) * tierDistance
				local tierRadius = villageFoundationRadius * (0.4 - tier * 0.1)
				local tierHeight = topY + (tier * 1.2)
				
				Terrain:FillCylinder(
					CFrame.new(tierX, (tierHeight + topY) * 0.5, tierZ),
					tierHeight - topY,
					tierRadius,
					grassMat
				)
			end
		end
	end

	-- 1) Sand body: a main plateau plus several offset lobes give an irregular coast.
	landColumn(cx, cz, half * 0.66, topY, sandMat)
	local lobes = rng:NextInteger(4, 7)
	for i = 1, lobes do
		local a = (i / lobes) * math.pi * 2 + rng:NextNumber(-0.55, 0.55)
		local dist = half * rng:NextNumber(0.22, 0.44)
		local lobeR = half * rng:NextNumber(0.26, 0.46)
		-- Keep every lobe inside the isle circle so the raft's shoreline collision is clean.
		if dist + lobeR > half * 0.98 then
			lobeR = math.max(half * 0.18, half * 0.98 - dist)
		end
		-- Avoid placing lobes too close to village centers
		if hasVillage then
			local lobeCenter = Vector3.new(cx + math.cos(a) * dist, topY, cz + math.sin(a) * dist)
			local distToVillage = (lobeCenter - center).Magnitude
			if distToVillage < half * 0.45 then
				continue  -- Skip this lobe to keep village area clear
			end
		end
		landColumn(cx + math.cos(a) * dist, cz + math.sin(a) * dist, lobeR, topY, sandMat)
	end

	-- 2) Enhanced grass/jungle cap with village considerations
	local capTop = topY + (if hasVillage then 0.2 else 0.3)  -- Flatter for villages
	local capBottom = topY - 3.5
	local capH = capTop - capBottom
	local capY = (capTop + capBottom) * 0.5
	local capRadius = if hasVillage then half * 0.7 else half * 0.6  -- Larger grass area for villages
	
	Terrain:FillCylinder(CFrame.new(cx, capY, cz), capH, capRadius, grassMat)
	
	-- Add grass patches but keep village center clear
	for i = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = half * rng:NextNumber(0.12, 0.4)
		local patchCenter = Vector3.new(cx + math.cos(a) * d, topY, cz + math.sin(a) * d)
		
		-- Skip patches too close to village center
		if hasVillage and (patchCenter - center).Magnitude < half * 0.35 then
			continue
		end
		
		local r = half * rng:NextNumber(0.2, 0.34)
		Terrain:FillCylinder(CFrame.new(cx + math.cos(a) * d, capY, cz + math.sin(a) * d), capH, r, grassMat)
	end

	-- 3) Enhanced biome relief with village-friendly positioning
	local rockMat = Enum.Material.Rock

	if biome == "volcanic" and features.volcano then
		local v = features.volcano
		-- Position volcano away from village center for better layouts
		local steps = 12
		for s = 0, steps do
			local t = s / steps
			local y = topY + v.height * t
			local r = v.baseR * (1 - t * 0.82)
			if t > 0.9 then
				r = math.max(r, v.craterR + 3)
			end
			local mat = if t < 0.18 then grassMat elseif t > 0.62 then Enum.Material.Basalt else rockMat
			Terrain:FillBall(Vector3.new(v.pos.X, y, v.pos.Z), math.max(r, v.craterR + 2), mat)
		end
		-- Hollow out the summit crater
		local rimY = topY + v.height
		Terrain:FillCylinder(CFrame.new(v.pos.X, rimY - 4, v.pos.Z), 14, v.craterR, Enum.Material.Air)
		
		-- Reduced tropical hillocks to avoid village interference
		for i = 1, rng:NextInteger(1, 2) do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = half * rng:NextNumber(0.7, 0.9)  -- Push further from center
			local hx, hz = cx + math.cos(a) * d, cz + math.sin(a) * d
			
			-- Check distance from village if applicable
			if hasVillage and (Vector3.new(hx, topY, hz) - center).Magnitude < half * 0.5 then
				continue
			end
			
			for s = 0, 4 do
				local t = s / 4
				Terrain:FillBall(Vector3.new(hx, topY + 14 * t, hz), math.max(half * 0.09 * (1 - t * 0.7), 3), grassMat)
			end
		end
		
	elseif biome == "mountain" then
		-- Mountain peak positioned for scenic backdrop
		local pk = features.peak
		if pk then
			local steps = 12
			for s = 0, steps do
				local t = s / steps
				local y = topY + pk.height * t
				local r = pk.baseR * (1 - t * 0.78)
				local mat = if t > 0.72 then Enum.Material.Snow elseif t > 0.3 then rockMat else grassMat
				Terrain:FillBall(Vector3.new(pk.pos.X, y, pk.pos.Z), math.max(r, 3), mat)
			end
		end
		
		-- Strategic hummock placement for medieval castle/village aesthetic  
		for i = 1, rng:NextInteger(1, 3) do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = half * rng:NextNumber(0.6, 0.9)  -- Keep away from village center
			local hx, hz = cx + math.cos(a) * d, cz + math.sin(a) * d
			
			-- Avoid village area
			if hasVillage and (Vector3.new(hx, topY, hz) - center).Magnitude < half * 0.4 then
				continue
			end
			
			for s = 0, 4 do
				local t = s / 4
				Terrain:FillBall(Vector3.new(hx, topY + 20 * t, hz), math.max(half * 0.12 * (1 - t * 0.7), 3), grassMat)
			end
		end
		
		-- Lake positioned for castle/village water feature
		local lake = features.lake
		if lake then
			local clearTop = topY + 6
			local clearH = clearTop - lake.bedY
			Terrain:FillCylinder(
				CFrame.new(lake.pos.X, (clearTop + lake.bedY) * 0.5, lake.pos.Z),
				clearH,
				lake.radius,
				Enum.Material.Air
			)
			local waterH = lake.surfaceY - lake.bedY
			Terrain:FillCylinder(
				CFrame.new(lake.pos.X, (lake.surfaceY + lake.bedY) * 0.5, lake.pos.Z),
				waterH,
				lake.radius - 1,
				Enum.Material.Water
			)
		end
		
	else
		-- Enhanced relief for other biomes with village considerations
		local peakExtra, hillCount
		if biome == "jungle" then
			peakExtra, hillCount = rng:NextNumber(34, 66), rng:NextInteger(1, 2)  -- Fewer hills for villages
		elseif biome == "palm" then
			peakExtra, hillCount = rng:NextNumber(16, 32), rng:NextInteger(0, 1)
		elseif biome == "highland" then
			peakExtra, hillCount = rng:NextNumber(20, 40), rng:NextInteger(1, 2)
		else
			peakExtra, hillCount = rng:NextNumber(5, 13), rng:NextInteger(0, 1)
		end
		
		-- Push hills to outer bands to preserve village flatness
		local hillBandMin = if isTown then 0.88 else (if hasVillage then 0.75 else 0.6)
		local hillBandMax = 0.94
		local hillRock = if biome == "jungle" then Enum.Material.Rock else grassMat
		
		for i = 1, hillCount do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = half * rng:NextNumber(hillBandMin, hillBandMax)
			local hx, hz = cx + math.cos(a) * d, cz + math.sin(a) * d
			local baseR = half * (if isTown then rng:NextNumber(0.05, 0.09) else rng:NextNumber(0.08, 0.15))
			
			-- Ensure hills don't interfere with village layout
			if hasVillage and (Vector3.new(hx, topY, hz) - center).Magnitude < half * 0.5 then
				continue
			end
			
			local steps = 6
			for s = 0, steps do
				local t = s / steps
				local y = topY + peakExtra * t
				local r = baseR * (1 - t * 0.72)
				Terrain:FillBall(Vector3.new(hx, y, hz), math.max(r, 3), if t > 0.55 then hillRock else grassMat)
			end
		end
	end

	-- 4) Refined coastal rock placement for better harbor/dock access
	local knobs = rng:NextInteger(2, 5)  -- Fewer rocks for cleaner shorelines
	for i = 1, knobs do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = half * rng:NextNumber(0.95, 1.05)
		
		-- Avoid dock areas if this island has docks
		local skipKnob = false
		if features.docks then
			for _, dock in features.docks do
				local knobAngle = math.atan2(math.sin(a), math.cos(a))
				local dockAngle = math.atan2(dock.dir.Z, dock.dir.X)
				local angleDiff = math.abs(knobAngle - dockAngle)
				if angleDiff < math.rad(45) or angleDiff > math.rad(315) then
					skipKnob = true
					break
				end
			end
		end
		
		if not skipKnob then
			Terrain:FillBall(
				Vector3.new(cx + math.cos(a) * d, surfaceY - 0.5, cz + math.sin(a) * d),
				rng:NextNumber(2, 5),  -- Smaller rocks
				Enum.Material.Rock
			)
		end
	end
end

-- =====================================================================================
-- Signature landform effects + shoreline structures (docks, lighthouses, boats)
-- =====================================================================================

local DOCK_PLANK = Color3.fromRGB(122, 86, 52)
local DOCK_POST = Color3.fromRGB(84, 58, 36)

-- A short wooden barrel standing on end (dock / harbour clutter).
local function buildBarrel(model: Model, pos: Vector3)
	makePart({
		Name = "Barrel",
		Parent = model,
		Size = Vector3.new(2.4, 1.9, 1.9),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(112, 76, 44),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	makePart({
		Name = "BarrelBand",
		Parent = model,
		Size = Vector3.new(2.5, 2.0, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 44, 30),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
end

-- A little open rowboat that floats on the water beside a dock (or lies beached/broken
-- on an abandoned isle). `cf` sits at the waterline; `broken` tilts + darkens it.
local function buildRowboat(model: Model, cf: CFrame, broken: boolean?)
	local hull = Color3.fromRGB(104, 72, 42)
	if broken then
		hull = Color3.fromRGB(78, 60, 44)
		cf = cf * CFrame.Angles(math.rad(12), 0, math.rad(18))
	end
	local boat = Instance.new("Model")
	boat.Name = if broken then "Shipwreck" else "Rowboat"
	boat.Parent = model
	local function part(name, size, off, color)
		return makePart({
			Name = name,
			Parent = boat,
			Size = size,
			CFrame = cf * off,
			Color = color or hull,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end
	part("Floor", Vector3.new(4.6, 0.4, 10), CFrame.new(0, 0.2, 0))
	part("SideL", Vector3.new(0.4, 1.6, 10), CFrame.new(-2.3, 0.9, 0) * CFrame.Angles(0, 0, math.rad(-12)))
	part("SideR", Vector3.new(0.4, 1.6, 10), CFrame.new(2.3, 0.9, 0) * CFrame.Angles(0, 0, math.rad(12)))
	part("Bow", Vector3.new(4.4, 1.6, 1.4), CFrame.new(0, 0.9, -5) * CFrame.Angles(math.rad(20), 0, 0))
	part("Stern", Vector3.new(4.4, 1.6, 1.2), CFrame.new(0, 0.9, 5))
	if not broken then
		part("Bench", Vector3.new(4.2, 0.35, 1.3), CFrame.new(0, 1.4, 0))
		part("Oar", Vector3.new(0.3, 0.3, 6), CFrame.new(2.7, 1.6, 0) * CFrame.Angles(math.rad(6), math.rad(18), 0), Color3.fromRGB(122, 90, 58))
	end
	local prim = boat:FindFirstChild("Floor")
	if prim and prim:IsA("BasePart") then
		boat.PrimaryPart = prim
	end
end

-- A wooden pier reaching out over the water: plank walkway on pilings, side rails, a wider
-- T-head at the end, and a little harbour clutter (barrels + a draggable crate). Optionally
-- moors a rowboat alongside the head. `origin` is the body the dock reaches out from (the
-- island for a sea dock, or the lake centre for a lake dock).
local function buildDock(
	model: Model,
	origin: Vector3,
	surfaceY: number,
	angle: number,
	startR: number,
	endR: number,
	opts: { [string]: any }?
)
	opts = opts or {}
	local o = opts :: { [string]: any }
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local yaw = math.atan2(dir.X, dir.Z)
	local length = math.abs(endR - startR)
	if length < 6 then
		return
	end
	local midR = (startR + endR) * 0.5
	local width = (o.width :: number?) or 7
	local deckY = (o.deckY :: number?) or (surfaceY + 1.4)
	local base = Vector3.new(origin.X + dir.X * midR, deckY, origin.Z + dir.Z * midR)
	local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0)

	makePart({
		Name = "DockDeck",
		Parent = model,
		Size = Vector3.new(width, 0.5, length),
		CFrame = cf,
		Color = DOCK_PLANK,
		Material = Enum.Material.WoodPlanks,
	})

	-- Pilings + short rail posts down both sides.
	local pileTop = deckY - 0.2
	local pileBot = surfaceY - 6
	local pileH = pileTop - pileBot
	local pileY = (pileTop + pileBot) * 0.5
	local posts = math.max(2, math.floor(length / 8))
	for i = 0, posts do
		local along = -length * 0.5 + (i / posts) * length
		for _, sx in { -width * 0.5 + 0.7, width * 0.5 - 0.7 } do
			local p = cf * CFrame.new(sx, 0, along)
			makePart({
				Name = "DockPiling",
				Parent = model,
				Size = Vector3.new(0.9, pileH, 0.9),
				CFrame = CFrame.new(p.X, pileY, p.Z),
				Color = DOCK_POST,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = "RailPost",
				Parent = model,
				Size = Vector3.new(0.4, 2.4, 0.4),
				CFrame = cf * CFrame.new(sx, 1.4, along),
				Color = DOCK_POST,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
	end
	-- Continuous top rails.
	for _, sx in { -width * 0.5 + 0.7, width * 0.5 - 0.7 } do
		makePart({
			Name = "DockRail",
			Parent = model,
			Size = Vector3.new(0.35, 0.35, length),
			CFrame = cf * CFrame.new(sx, 2.5, 0),
			Color = DOCK_PLANK,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	-- Wider T-head platform at the far (water) end.
	local headSign = if endR >= startR then 1 else -1
	local headCf = cf * CFrame.new(0, 0, headSign * (length * 0.5 - 3))
	makePart({
		Name = "DockHead",
		Parent = model,
		Size = Vector3.new(width + 7, 0.5, 6.5),
		CFrame = headCf,
		Color = DOCK_PLANK,
		Material = Enum.Material.WoodPlanks,
	})

	-- Harbour clutter near the land end: a couple of barrels + a draggable crate.
	local landCf = cf * CFrame.new(0, 0, -headSign * (length * 0.5 - 3.5))
	buildBarrel(model, (landCf * CFrame.new(width * 0.5 - 1.2, 0.25, 0)).Position)
	if math.random() < 0.7 then
		buildBarrel(model, (landCf * CFrame.new(width * 0.5 - 2.6, 0.25, 1.4)).Position)
	end
	if o.islandId then
		local crate = LootPropFactory.createCrateWorld(model, landCf * CFrame.new(-width * 0.5 + 1.4, 1.2, 0))
		crate:SetAttribute("IslandId", o.islandId)
	end

	-- Moor a rowboat alongside the head.
	if o.rowboat ~= false then
		local boatCf = headCf * CFrame.new(width * 0.5 + 4, surfaceY - deckY + 0.4, 0) * CFrame.Angles(0, math.rad(90), 0)
		buildRowboat(model, boatCf)
	end
end

-- Enhanced lighthouse with improved banded stone appearance matching reference images
local function buildLighthouse(model: Model, topY: number, x: number, z: number)
	local lh = Instance.new("Model")
	lh.Name = "Lighthouse"
	lh.Parent = model
	local baseY = topY
	local towerH = 42  -- Taller for more impressive silhouette
	
	-- Enhanced rocky foundation with more detail
	makePart({
		Name = "LHFoundation",
		Parent = lh,
		Size = Vector3.new(15, 5, 15),
		CFrame = CFrame.new(x, baseY + 1.5, z),
		Color = Color3.fromRGB(105, 102, 98),
		Material = Enum.Material.Rock,
		Shape = Enum.PartType.Cylinder,
	}).CFrame = CFrame.new(x, baseY + 1.5, z) * CFrame.Angles(0, 0, math.rad(90))
	
	-- Stone base platform
	makePart({
		Name = "LHBasePlatform",
		Parent = lh,
		Size = Vector3.new(11, 2, 11),
		CFrame = CFrame.new(x, baseY + 4, z),
		Color = Color3.fromRGB(135, 132, 128),
		Material = Enum.Material.Cobblestone,
	})
	
	-- Enhanced tapered banded tower with more distinctive stripes
	local segs = 8  -- More segments for finer banding
	local LIGHTHOUSE_WHITE = Color3.fromRGB(248, 248, 245)
	local LIGHTHOUSE_RED = Color3.fromRGB(165, 42, 38)
	local LIGHTHOUSE_STONE = Color3.fromRGB(140, 135, 130)
	
	for i = 0, segs - 1 do
		local segH = towerH / segs
		local r = 6.2 - i * 0.4  -- Slightly wider base, more gradual taper
		local y = baseY + 5 + segH * (i + 0.5)
		
		-- Alternating white and red bands
		local bandColor = if i % 2 == 0 then LIGHTHOUSE_WHITE else LIGHTHOUSE_RED
		local bandMaterial = if i % 2 == 0 then Enum.Material.SmoothPlastic else Enum.Material.SmoothPlastic
		
		makePart({
			Name = `LHSeg_{i}`,
			Parent = lh,
			Size = Vector3.new(segH + 0.2, r * 2, r * 2),
			CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = bandColor,
			Material = bandMaterial,
			Shape = Enum.PartType.Cylinder,
		})
		
		-- Add horizontal divider lines between segments
		if i > 0 then
			makePart({
				Name = `LHDivider_{i}`,
				Parent = lh,
				Size = Vector3.new(0.3, (r + 0.2) * 2, (r + 0.2) * 2),
				CFrame = CFrame.new(x, y - segH * 0.5, z) * CFrame.Angles(0, 0, math.rad(90)),
				Color = LIGHTHOUSE_STONE,
				Material = Enum.Material.Concrete,
				Shape = Enum.PartType.Cylinder,
				CanCollide = false,
			})
		end
	end
	
	local topOfTower = baseY + 5 + towerH
	
	-- Enhanced gallery deck with railings
	makePart({
		Name = "LHGallery",
		Parent = lh,
		Size = Vector3.new(1.2, 9.5, 9.5),
		CFrame = CFrame.new(x, topOfTower + 0.6, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(75, 78, 85),
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
	})
	
	-- Gallery railing posts
	for i = 0, 7 do
		local angle = (i / 8) * math.pi * 2
		local railX = x + math.cos(angle) * 4.2
		local railZ = z + math.sin(angle) * 4.2
		makePart({
			Name = "GalleryPost",
			Parent = lh,
			Size = Vector3.new(0.3, 2.5, 0.3),
			CFrame = CFrame.new(railX, topOfTower + 1.8, railZ),
			Color = Color3.fromRGB(75, 78, 85),
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
	
	-- Top railing ring
	makePart({
		Name = "GalleryRail",
		Parent = lh,
		Size = Vector3.new(0.4, 8.8, 8.8),
		CFrame = CFrame.new(x, topOfTower + 3, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(75, 78, 85),
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	
	-- Enhanced lantern room with detailed frame structure
	local lanternBase = makePart({
		Name = "LHLanternBase",
		Parent = lh,
		Size = Vector3.new(1.5, 6.5, 6.5),
		CFrame = CFrame.new(x, topOfTower + 4.2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(75, 78, 85),
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
	})
	
	-- Glowing lantern room glass
	local lantern = makePart({
		Name = "LHLantern",
		Parent = lh,
		Size = Vector3.new(3.8, 5.8, 5.8),
		CFrame = CFrame.new(x, topOfTower + 4.2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 235, 180),
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Transparency = 0.15,
	})
	
	-- Lantern room frame segments (vertical mullions)
	for i = 0, 5 do
		local angle = (i / 6) * math.pi * 2
		local frameX = x + math.cos(angle) * 2.9
		local frameZ = z + math.sin(angle) * 2.9
		makePart({
			Name = "LanternFrame",
			Parent = lh,
			Size = Vector3.new(0.2, 4, 0.5),
			CFrame = CFrame.new(frameX, topOfTower + 4.2, frameZ),
			Color = Color3.fromRGB(45, 48, 55),
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
	
	-- Enhanced light source
	local light = Instance.new("PointLight")
	light.Brightness = 5.5
	light.Range = 120
	light.Color = Color3.fromRGB(255, 240, 180)
	light.Shadows = false
	light.Parent = lantern
	
	-- Beacon effect (spot light for extra range)
	local beacon = Instance.new("SpotLight")
	beacon.Brightness = 3.5
	beacon.Range = 200
	beacon.Angle = 45
	beacon.Color = Color3.fromRGB(255, 240, 180)
	beacon.Face = Enum.NormalId.Top
	beacon.Shadows = false
	beacon.Parent = lantern
	
	-- Enhanced conical roof with weathered copper appearance
	makePart({
		Name = "LHCap",
		Parent = lh,
		Size = Vector3.new(4.5, 7, 7),
		CFrame = CFrame.new(x, topOfTower + 8.2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(95, 115, 105),  -- Weathered copper green
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
	})
	
	-- Roof finial
	makePart({
		Name = "LHFinial",
		Parent = lh,
		Size = Vector3.new(1.2, 0.8, 0.8),
		CFrame = CFrame.new(x, topOfTower + 11.8, z),
		Color = Color3.fromRGB(65, 68, 75),
		Material = Enum.Material.Metal,
	})
	
	-- Enhanced spiral staircase (external)
	local stairCount = 12
	for i = 0, stairCount - 1 do
		local stepAngle = (i / stairCount) * math.pi * 4  -- Two full rotations
		local stepRadius = 6.8
		local stepY = baseY + 5 + (i / stairCount) * (towerH - 5)
		local stepX = x + math.cos(stepAngle) * stepRadius
		local stepZ = z + math.sin(stepAngle) * stepRadius
		
		-- Step platform
		makePart({
			Name = "LHStep",
			Parent = lh,
			Size = Vector3.new(2.5, 0.3, 1.2),
			CFrame = CFrame.lookAt(Vector3.new(stepX, stepY, stepZ), Vector3.new(x, stepY, z)),
			Color = Color3.fromRGB(75, 78, 85),
			Material = Enum.Material.Metal,
		})
		
		-- Step railing
		makePart({
			Name = "StepRail",
			Parent = lh,
			Size = Vector3.new(0.2, 1.5, 2.8),
			CFrame = CFrame.lookAt(Vector3.new(stepX, stepY + 0.75, stepZ), Vector3.new(x, stepY + 0.75, z)) * CFrame.new(1.3, 0, 0),
			Color = Color3.fromRGB(75, 78, 85),
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
	
	-- Door at base
	makePart({
		Name = "LHDoor",
		Parent = lh,
		Size = Vector3.new(0.3, 3.5, 2),
		CFrame = CFrame.new(x + 5.5, baseY + 6.5, z),
		Color = Color3.fromRGB(85, 55, 35),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
end

-- Fill a volcano crater with glowing lava, embers, smoke and a warm glow, plus a couple of
-- cooled lava streaks running down the cone. `pos` is the cone centre, `rimY` the summit.
local function buildLavaCrater(model: Model, pos: Vector3, craterR: number, rimY: number, baseR: number, topY: number)
	local lava = makePart({
		Name = "Lava",
		Parent = model,
		Size = Vector3.new(1.4, (craterR - 1) * 2, (craterR - 1) * 2),
		CFrame = CFrame.new(pos.X, rimY - 3.5, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 104, 28),
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	local fire = Instance.new("Fire")
	fire.Size = 30
	fire.Heat = 18
	fire.Color = Color3.fromRGB(255, 128, 40)
	fire.SecondaryColor = Color3.fromRGB(120, 30, 10)
	fire.Parent = lava
	local smoke = Instance.new("Smoke")
	smoke.Size = 10
	smoke.Opacity = 0.4
	smoke.RiseVelocity = 12
	smoke.Color = Color3.fromRGB(70, 66, 62)
	smoke.Parent = lava
	local light = Instance.new("PointLight")
	light.Brightness = 5
	light.Range = 80
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Shadows = false
	light.Parent = lava
	-- Glowing lava streaks down the flanks.
	for i = 1, 3 do
		local a = math.rad(i * 120 + math.random(-25, 25))
		local dx, dz = math.cos(a), math.sin(a)
		makePart({
			Name = `LavaStreak_{i}`,
			Parent = model,
			Size = Vector3.new(2.2, rimY - topY - 6, 1.2),
			CFrame = CFrame.new(pos.X + dx * baseR * 0.5, topY + (rimY - topY) * 0.5, pos.Z + dz * baseR * 0.5)
				* CFrame.Angles(0, -a, math.rad(14)),
			Color = Color3.fromRGB(226, 72, 24),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

-- A translucent waterfall sheet with a foamy splash pool + drifting mist, cascading from
-- `topPos` down to `bottomY`. Used off the mountain isle's peak-side cliff.
local function buildWaterfall(model: Model, topPos: Vector3, bottomY: number)
	local h = math.max(topPos.Y - bottomY, 8)
	for i = -1, 1 do
		makePart({
			Name = "Waterfall",
			Parent = model,
			Size = Vector3.new(6, h, 1.4),
			CFrame = CFrame.new(topPos.X + i * 5.5, (topPos.Y + bottomY) * 0.5, topPos.Z) * CFrame.Angles(math.rad(4), 0, 0),
			Color = Color3.fromRGB(222, 240, 250),
			Material = Enum.Material.Glass,
			Transparency = 0.32,
			CanCollide = false,
			CastShadow = false,
		})
	end
	local splash = makePart({
		Name = "WaterfallSplash",
		Parent = model,
		Size = Vector3.new(20, 2, 8),
		CFrame = CFrame.new(topPos.X, bottomY + 1, topPos.Z),
		Color = Color3.fromRGB(230, 244, 252),
		Material = Enum.Material.Foil,
		Transparency = 0.3,
		CanCollide = false,
		CastShadow = false,
		Shape = Enum.PartType.Ball,
	})
	local mist = Instance.new("Smoke")
	mist.Size = 8
	mist.Opacity = 0.18
	mist.RiseVelocity = 3
	mist.Color = Color3.fromRGB(235, 245, 250)
	mist.Parent = splash
end

-- Precompute the deterministic geometry of an island's signature features (volcano cone,
-- mountain peak + lake, dock directions, lighthouse). Computed ONCE per isle and shared by
-- both the terrain sculptor and the decorative pass so they agree on exact positions.
local function planIslandFeatures(
	id: string,
	center: Vector3,
	topY: number,
	size: number,
	biome: string,
	entry: { [string]: any }
): { [string]: any }
	local rng = Random.new(seedFromId(id) * 3 + 17)
	local half = size * 0.5
	local features: { [string]: any } = { docks = {} }

	if biome == "volcanic" and entry.Volcano ~= false then
		-- Rise the cone on the "back" flank (−Z-ish) so the town core, harbour front
		-- (+Z) and the merchant/campfire keep flat ground — the village then climbs the
		-- lower slopes just like the reference tropical isle.
		local vAngle = math.pi * 1.5 + rng:NextNumber(-0.4, 0.4)
		features.volcano = {
			pos = Vector3.new(center.X + math.cos(vAngle) * half * 0.5, center.Y, center.Z + math.sin(vAngle) * half * 0.5),
			baseR = half * 0.32,
			height = rng:NextNumber(135, 180),
			craterR = half * 0.08,
			angle = vAngle,
		}
	end

	if biome == "mountain" then
		local peakAngle = rng:NextNumber(0, math.pi * 2)
		features.peak = {
			pos = Vector3.new(center.X + math.cos(peakAngle) * half * 0.74, topY, center.Z + math.sin(peakAngle) * half * 0.74),
			baseR = half * 0.24,
			height = rng:NextNumber(150, 210),
			angle = peakAngle,
		}
		local lakeAngle = peakAngle + math.pi
		features.lake = {
			pos = Vector3.new(center.X + math.cos(lakeAngle) * half * 0.52, topY, center.Z + math.sin(lakeAngle) * half * 0.52),
			radius = half * 0.17,
			surfaceY = topY - 1.2,
			bedY = topY - 12,
			angle = lakeAngle,
		}
	end

	-- Dock directions: evenly spaced around the coast, biased away from the tall side
	-- (peak / volcano) so a pier never tries to climb the mountain.
	local dcount = tonumber(entry.Docks) or 0
	if dcount > 0 then
		local baseA = rng:NextNumber(0, math.pi * 2)
		if features.peak then
			baseA = features.peak.angle + math.pi -- start opposite the peak
		elseif features.volcano then
			baseA = features.volcano.angle + math.pi * 0.5
		end
		for i = 1, dcount do
			local a = baseA + (i - 1) * (math.pi * 2 / dcount) * 0.55
			table.insert(features.docks, { angle = a, target = "sea" })
		end
		-- On mountain isles the first pier reaches out over the lake instead of the sea.
		if biome == "mountain" and features.lake then
			features.docks[1].target = "lake"
		end
	end

	if entry.Lighthouse == true then
		local a = if #features.docks > 0 then features.docks[1].angle + 0.5 else 0.8
		if features.docks[1] and features.docks[1].target == "lake" and #features.docks > 1 then
			a = features.docks[2].angle + 0.5
		end
		features.lighthouse = { angle = a }
	end

	return features
end

-- Decorative + structural pass run after terrain + vegetation: crater lava, waterfalls,
-- docks/piers, a lighthouse, moored + beached boats. Everything here is Parts parented to
-- the island model (terrain is already sculpted). Positions come from planIslandFeatures.
local function decorateShore(
	model: Model,
	center: Vector3,
	size: number,
	topY: number,
	biome: string,
	entry: { [string]: any },
	features: { [string]: any }
)
	local half = size * 0.5
	local surfaceY = OceanConfig.SurfaceY
	local islandId = entry.Id

	-- Volcano lava + smoke.
	if features.volcano then
		local v = features.volcano
		buildLavaCrater(model, v.pos, v.craterR, topY + v.height, v.baseR, topY)
	end

	-- Mountain waterfall off the peak-side cliff.
	if features.peak then
		local pk = features.peak
		local wx = center.X + math.cos(pk.angle) * half * 0.98
		local wz = center.Z + math.sin(pk.angle) * half * 0.98
		buildWaterfall(model, Vector3.new(wx, topY + 22, wz), surfaceY)
	end

	-- Docks / piers.
	for _, dock in features.docks do
		if dock.target == "lake" and features.lake then
			local lake = features.lake
			-- Reach out from the settlement-facing shore across the lake.
			local toCenter = math.atan2(center.Z - lake.pos.Z, center.X - lake.pos.X)
			buildDock(model, lake.pos, lake.surfaceY, toCenter, lake.radius + 1, lake.radius * 0.18, {
				islandId = islandId,
				deckY = lake.surfaceY + 1.2,
				width = 6,
				rowboat = true,
			})
			-- A rowboat drifting on the lake.
			local bx = lake.pos.X + math.cos(toCenter + 1.2) * lake.radius * 0.4
			local bz = lake.pos.Z + math.sin(toCenter + 1.2) * lake.radius * 0.4
			buildRowboat(model, CFrame.new(bx, lake.surfaceY + 0.4, bz) * CFrame.Angles(0, toCenter, 0))
		else
			local startR = half * 0.8
			local endR = half + Config.Islands.RaftCollisionPad + 30
			buildDock(model, center, surfaceY, dock.angle, startR, endR, {
				islandId = islandId,
				rowboat = true,
			})
		end
	end

	-- Lighthouse on the shore of medieval seaside isles.
	if features.lighthouse then
		local a = features.lighthouse.angle
		local lx = center.X + math.cos(a) * half * 0.72
		local lz = center.Z + math.sin(a) * half * 0.72
		buildLighthouse(model, topY, lx, lz)
	end

	-- A beached shipwreck on abandoned isles (washed-up wreck to poke around in).
	if entry.Abandoned == true then
		local a = math.random() * math.pi * 2
		local r = half * 0.82
		buildRowboat(model, CFrame.new(center.X + math.cos(a) * r, topY + 0.6, center.Z + math.sin(a) * r) * CFrame.Angles(0, a, 0), true)
	end
end

local function buildFlatIsland(entry: { [string]: any }, folder: Folder): IslandRecord
	local thickness = Config.Islands.Thickness
	local topY = Config.Islands.TopY
	local size = entry.SizeStuds
	local biome = entry.Biome or "beach"
	local center = worldCenterForOffset(entry.Offset, topY, thickness)

	local model = Instance.new("Model")
	model.Name = `Isle_{entry.Id}`
	model:SetAttribute("IslandId", entry.Id)
	model:SetAttribute("Biome", biome)
	model.Parent = folder

	-- The isle body is real Roblox voxel Terrain now (not Parts). Keep a tiny invisible
	-- anchor so the Model still has a stable PrimaryPart for any code that references it.
	local anchor = makePart({
		Name = "IsleAnchor",
		Parent = model,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(center.X, topY, center.Z),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	model.PrimaryPart = anchor

	-- Precompute this isle's signature landforms + shoreline layout so the terrain sculptor
	-- and the decorative pass agree on exact positions (volcano, lake, docks, lighthouse).
	local features = planIslandFeatures(entry.Id, center, topY, size, biome, entry)

	-- Carve the organic, biome-specific terrain island (beaches, grass/jungle/highland
	-- interior, hills, rocky peaks, volcanic cones, snow peaks + lakes). Seeded per isle so
	-- every island's shape is different.
	generateIslandTerrain(entry.Id, center, topY, size, biome, entry.Theme or "wild", features)

	scatterVegetation(model, center, size, topY, biome, features)
	scatterLooseLoot(model, center, size, topY, entry.Id)

	-- Docks / piers, lighthouse, crater lava, waterfalls, moored + beached boats.
	decorateShore(model, center, size, topY, biome, entry, features)

	local marker = makePart({
		Name = "IsleMarker",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center.X, topY + 18, center.Z),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	-- Island name billboard removed - names only show in popups now
	-- local gui = Instance.new("BillboardGui")
	-- gui.Name = "IsleBillboard"
	-- gui.Adornee = marker
	-- gui.Size = UDim2.fromOffset(200, 44)
	-- gui.AlwaysOnTop = true
	-- gui.MaxDistance = 900
	-- gui.Parent = marker

	-- local label = Instance.new("TextLabel")
	-- label.Name = "Label"
	-- label.BackgroundTransparency = 0.28
	-- label.BackgroundColor3 = Color3.fromRGB(18, 36, 48)
	-- label.Size = UDim2.fromScale(1, 1)
	-- label.Font = Enum.Font.GothamBold
	-- label.TextScaled = true
	-- label.TextColor3 = Config.Theme.Foam
	-- label.Text = string.upper(entry.Name)
	-- label.Parent = gui

	-- local corner = Instance.new("UICorner")
	-- corner.CornerRadius = UDim.new(0, 8)
	-- corner.Parent = label

	local theme = entry.Theme or "wild"
	local record: IslandRecord = {
		id = entry.Id,
		name = entry.Name,
		center = center,
		size = size,
		topY = topY,
		thickness = thickness,
		theme = theme,
		abandoned = entry.Abandoned == true,
		biome = biome,
		model = model,
		label = nil, -- No longer displaying island names in-game
		npcs = {},
	}

	local villagerCfg = entry.Villagers or { Passive = 0, Hostile = 0 }

	if theme == "wild" then
		-- No village — just a little scattered weapon loot on the wild isle.
		local weaponCount = (entry.Loot and entry.Loot.Weapons) or 0
		for _ = 1, weaponCount do
			local a = math.random() * math.pi * 2
			local r = size * (0.2 + math.random() * 0.24)
			local weaponId = Weapons.rollLootWeapon(function(lo, hi)
				return math.random(lo, hi)
			end)
			local cf = CFrame.new(center.X + math.cos(a) * r, topY + 0.5, center.Z + math.sin(a) * r)
				* CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
			WeaponService.spawnWeaponPickup(model, weaponId, cf)
		end
		-- A scrap of armor may wash up on wild isles too.
		local armorCount = (entry.Loot and entry.Loot.Armor) or 0
		for _ = 1, armorCount do
			local a = math.random() * math.pi * 2
			local r = size * (0.2 + math.random() * 0.24)
			local armorId = Armor.rollLootArmor(function(lo, hi)
				return math.random(lo, hi)
			end)
			local cf = CFrame.new(center.X + math.cos(a) * r, topY + 0.5, center.Z + math.sin(a) * r)
			ArmorService.spawnArmorPickup(model, armorId, cf)
		end
	else
		-- Build the themed village (houses, beds, torches, fences, campfire, chests, loot).
		local deps = {
			toast = function(player: Player, message: string, kind: string)
				if IslandService._Toast then
					IslandService._Toast:FireClient(player, message, kind)
				end
			end,
			getPartyCode = function(player: Player)
				return IslandService._getPartyCode and IslandService._getPartyCode(player)
			end,
			isLocked = function(code: string, islandId: string)
				return IslandService.isLockedForCrew(code, islandId)
			end,
			-- Armor hooks so village chests can grant armor and stands can spawn worn loot.
			wearArmor = function(player: Player, armorId: string)
				return ArmorService.wearArmor(player, armorId)
			end,
			spawnArmorPickup = function(parent: Instance, armorId: string, cf: CFrame)
				return ArmorService.spawnArmorPickup(parent, armorId, cf)
			end,
		}
		local layout = VillageBuilder.build(model, center, size, topY, entry, deps)

		-- No villagers at the start: the settlement is built empty of people. We only
		-- record WHERE and WHAT to spawn; populateIsland brings the town to life the first
		-- time a crew actually lands (see updateVisitLockouts).
		record.villagerPlan = {
			spots = layout.villagerSpots,
			passive = (villagerCfg.Passive or 0),
			hostile = (villagerCfg.Hostile or 0),
			abandoned = record.abandoned,
		}

		-- The blue-hatted merchant (never hostile, draggable / weldable to your raft) is
		-- part of the scenery, so it's placed right away — trade is always available.
		if entry.Merchant == true then
			local m = layout.merchantSpot
			MerchantService.spawnMerchant(model, CFrame.new(m), entry.Id)
		end
	end

	return record
end

function IslandService.getWorldCenters(): { Vector3 }
	local centers = {}
	for _, isle in IslandService._islands do
		table.insert(centers, isle.center)
	end
	if #centers == 0 then
		-- Before ensure(): still give ocean streamer a hint from catalog
		for _, entry in Config.Islands.Catalog do
			table.insert(
				centers,
				worldCenterForOffset(entry.Offset, Config.Islands.TopY, Config.Islands.Thickness)
			)
		end
	end
	return centers
end

-- Back-compat for older callers
function IslandService.getWorldCenter(): Vector3
	local centers = IslandService.getWorldCenters()
	return centers[1] or Config.StarterBase.Origin
end

function IslandService.paintTerrain()
	-- Isle bodies are sculpted ONCE as organic voxel Terrain in buildFlatIsland. Because
	-- that land lives above the sea surface, the ocean water streamer (which only fills
	-- below the surface) never touches it. This pass just re-asserts the SUBMERGED sand
	-- base each stream cycle so the water filler can't leave a hole under an isle. It
	-- stops well below the surface, so it never flattens the above-water terrain shape.
	local Terrain = Workspace.Terrain
	local surfaceY = OceanConfig.SurfaceY
	local baseTop = surfaceY - 1.5
	local baseBottom = surfaceY - 40
	local baseH = baseTop - baseBottom
	local baseY = (baseTop + baseBottom) * 0.5
	for _, isle in IslandService._islands do
		Terrain:FillCylinder(
			CFrame.new(isle.center.X, baseY, isle.center.Z),
			baseH,
			isle.size * 0.5 + 8,
			Enum.Material.Sand
		)
	end
end

function IslandService.isLockedForCrew(code: string, islandId: string): boolean
	local byIsle = IslandService._crewState[code]
	local state = byIsle and byIsle[islandId]
	return state ~= nil and state.locked == true
end

-- Solid-shoreline collision. Rafts can NEVER drive up onto an isle: sailing into one
-- runs the hull aground at the sand's edge (forward progress into the isle is stopped).
-- You can still slide along the coast and steer away, but you can't climb aboard.
-- Applies to EVERY isle, visited or not — separate from the visit-lockout clamp below.
function IslandService.collideRaft(fromPos: Vector3, toPos: Vector3): (Vector3, string?)
	local result = toPos
	local grounded: string? = nil

	for _, isle in IslandService._islands do
		local minDist = isle.size * 0.5 + Config.Islands.RaftCollisionPad
		local toDist = flatDistance(result, isle.center)
		if toDist >= minDist then
			continue
		end

		-- Destination is inside the shoreline ring — push it back out to the ring so the
		-- raft stops at the beach instead of driving over it.
		local outward = Vector3.new(result.X - isle.center.X, 0, result.Z - isle.center.Z)
		if outward.Magnitude < 0.05 then
			outward = Vector3.new(fromPos.X - isle.center.X, 0, fromPos.Z - isle.center.Z)
		end
		if outward.Magnitude < 0.05 then
			outward = Vector3.new(1, 0, 0)
		end
		outward = outward.Unit
		result = Vector3.new(
			isle.center.X + outward.X * minDist,
			result.Y,
			isle.center.Z + outward.Z * minDist
		)

		-- Only report "ran aground" when actually pushing toward the isle (approaching),
		-- so idling against a coast doesn't spam feedback.
		if toDist < flatDistance(fromPos, isle.center) then
			grounded = isle.name
		end
	end

	return result, grounded
end

-- Keep rafts outside locked isles (can't sail back after leaving far enough away).
function IslandService.clampRaftPosition(code: string, fromPos: Vector3, toPos: Vector3): (Vector3, string?)
	local result = toPos
	local blockedName: string? = nil

	for _, isle in IslandService._islands do
		if not IslandService.isLockedForCrew(code, isle.id) then
			continue
		end
		local minDist = isle.size * 0.5 + Config.Islands.ApproachPadStuds
		local dist = flatDistance(result, isle.center)
		if dist >= minDist then
			continue
		end

		-- Push out along the approach vector; if coming from outside, stop at the ring
		local fromDist = flatDistance(fromPos, isle.center)
		local outward = Vector3.new(result.X - isle.center.X, 0, result.Z - isle.center.Z)
		if outward.Magnitude < 0.05 then
			outward = Vector3.new(fromPos.X - isle.center.X, 0, fromPos.Z - isle.center.Z)
		end
		if outward.Magnitude < 0.05 then
			outward = Vector3.new(1, 0, 0)
		end
		outward = outward.Unit
		local ringPos = Vector3.new(
			isle.center.X + outward.X * minDist,
			result.Y,
			isle.center.Z + outward.Z * minDist
		)
		-- Prefer staying outside if we started outside
		if fromDist >= minDist then
			result = Vector3.new(fromPos.X, result.Y, fromPos.Z)
		else
			result = ringPos
		end
		blockedName = isle.name
	end

	return result, blockedName
end

local function pointOnIsland(pos: Vector3, isle: IslandRecord): boolean
	-- Anywhere from just below the shore up to the top of the tallest terrain peak counts
	-- as "on the isle" (volcano cones + snow peaks can rise ~200+ studs above the plateau).
	if pos.Y < isle.topY - 8 or pos.Y > isle.topY + 260 then
		return false
	end
	return flatDistance(pos, isle.center) <= isle.size * 0.5 + 3
end

local function toastCrew(code: string, message: string, kind: string)
	if not (IslandService._Toast and IslandService._getMemberUserIds) then
		return
	end
	for _, userId in IslandService._getMemberUserIds(code) do
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			IslandService._Toast:FireClient(plr, message, kind)
		end
	end
end

local function updateVisitLockouts()
	if not IslandService._getMemberUserIds then
		return
	end

	-- Gather active crew codes from live rafts
	local codes: { string } = {}
	local seen: { [string]: boolean } = {}
	for code, _ in StarterBaseService._basesByCode do
		if not seen[code] then
			seen[code] = true
			table.insert(codes, code)
		end
	end

	for _, code in codes do
		local members = IslandService._getMemberUserIds(code)
		local raft = StarterBaseService.getBaseModel(code)
		local deck = raft and (raft.PrimaryPart or raft:FindFirstChild("Deck"))
		local raftPos = if deck and deck:IsA("BasePart") then deck.Position else nil

		for _, isle in IslandService._islands do
			local state = ensureCrewState(code, isle.id)
			if state.locked then
				continue
			end

			local anyoneOn = false
			for _, userId in members do
				local plr = Players:GetPlayerByUserId(userId)
				local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and pointOnIsland(root.Position, isle) then
					anyoneOn = true
					break
				end
			end

			if anyoneOn then
				-- First boots on the sand: bring the town to life (villagers spawn now).
				if not isle.populated then
					populateIsland(isle)
				end
				state.visited = true
				if not state.notifiedVisit then
					state.notifiedVisit = true
					toastCrew(code, `Visited {isle.name} — leave & sail far away and you can't return.`, "info")
				end
				continue
			end

			if not state.visited then
				continue
			end

			-- Visited and everyone off the sand — lock when raft (or crew) is far enough
			local farEnough = false
			if raftPos then
				farEnough = flatDistance(raftPos, isle.center) >= Config.Islands.LockoutStuds
			else
				-- Fallback: all members far
				farEnough = true
				for _, userId in members do
					local plr = Players:GetPlayerByUserId(userId)
					local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						if flatDistance(root.Position, isle.center) < Config.Islands.LockoutStuds then
							farEnough = false
							break
						end
					end
				end
			end

			if farEnough then
				state.locked = true
				if not state.notifiedLock then
					state.notifiedLock = true
					toastCrew(code, `{isle.name} is behind you — that isle won't take your crew back.`, "info")
				end
			end
		end
	end
end

-- Rigid-move an anchored NPC model so its root lands at `nextPos` facing `lookAt`.
local function moveNpc(model: Model, root: BasePart, nextPos: Vector3, lookAt: Vector3)
	local newCf = CFrame.lookAt(nextPos, Vector3.new(lookAt.X, nextPos.Y, lookAt.Z))
	local delta = newCf * root.CFrame:Inverse()
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CFrame = delta * desc.CFrame
		end
	end
end

local function updateNpcs(dt: number)
	local vcfg = Config.Islands.Villager
	for _, runtime in IslandService._npcs do
		if not runtime.alive then
			continue
		end
		local model = runtime.model
		if not model.Parent then
			runtime.alive = false
			continue
		end
		local humanoid = runtime.humanoid or model:FindFirstChildOfClass("Humanoid")
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root and root:IsA("BasePart")) then
			runtime.alive = false
			continue
		end
		if humanoid.Health <= 0 then
			runtime.alive = false
			continue
		end

		local isle = IslandService._byId[runtime.islandId]
		if not isle then
			continue
		end

		if runtime.hostile then
			-- Aggressive defender: chase the nearest player near the isle, then strike.
			local combat = if runtime.model:GetAttribute("NpcKind") == "villager"
					and runtime.model.Name == "Scavenger"
				then vcfg.Scavenger
				else vcfg.Hostile

			local bestPlayer: Player? = nil
			local bestDist = combat.AggroRange
			local bestPos: Vector3? = nil
			for _, plr in Players:GetPlayers() do
				local character = plr.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local hum = character and character:FindFirstChildOfClass("Humanoid")
				if not (hrp and hrp:IsA("BasePart") and hum and hum.Health > 0) then
					continue
				end
				if flatDistance(hrp.Position, isle.center) > isle.size * 0.5 + 18 then
					continue
				end
				local d = flatDistance(hrp.Position, root.Position)
				if d < bestDist then
					bestDist = d
					bestPlayer = plr
					bestPos = hrp.Position
				end
			end

			if not (bestPlayer and bestPos) then
				continue
			end

			local toTarget = Vector3.new(bestPos.X - root.Position.X, 0, bestPos.Z - root.Position.Z)
			if toTarget.Magnitude > 0.15 then
				local step = math.min(combat.ChaseSpeed * dt, toTarget.Magnitude)
				local nextPos = root.Position + toTarget.Unit * step
				local fromCenter = Vector3.new(nextPos.X - isle.center.X, 0, nextPos.Z - isle.center.Z)
				local maxR = isle.size * 0.48
				if fromCenter.Magnitude > maxR then
					fromCenter = fromCenter.Unit * maxR
					nextPos = Vector3.new(isle.center.X + fromCenter.X, isle.topY + 2.5, isle.center.Z + fromCenter.Z)
				else
					nextPos = Vector3.new(nextPos.X, isle.topY + 2.5, nextPos.Z)
				end
				moveNpc(model, root, nextPos, bestPos)
			end

			runtime.attackAccum += dt
			if runtime.attackAccum >= combat.AttackCooldown and bestDist <= 3.8 then
				runtime.attackAccum = 0
				-- Route through ArmorService so worn armor reduces the hit.
				ArmorService.applyPlayerDamage(bestPlayer, combat.Damage)
			end
		else
			-- Passive islander: idle wander around their home within the village.
			runtime.wanderAccum -= dt
			if runtime.wanderAccum <= 0 or not runtime.targetPos then
				runtime.wanderAccum = 2.5 + math.random() * 3.5
				local wr = isle.size * 0.5 * vcfg.Passive.WanderRadiusFrac
				local a = math.random() * math.pi * 2
				local r = math.random() * wr
				runtime.targetPos = runtime.homePos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			end
			local target = runtime.targetPos :: Vector3
			local toTarget = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
			if toTarget.Magnitude > 0.6 then
				local step = math.min(vcfg.Passive.WanderSpeed * dt, toTarget.Magnitude)
				local nextPos = root.Position + toTarget.Unit * step
				nextPos = Vector3.new(nextPos.X, isle.topY + 2.5, nextPos.Z)
				moveNpc(model, root, nextPos, target)
			end
		end
	end
end

function IslandService.clearCrew(code: string)
	IslandService._crewState[code] = nil
end

function IslandService.ensure(): Folder
	local folder = lobbyRoot():FindFirstChild("DriveIslands")
	if folder and folder:IsA("Folder") and #IslandService._islands > 0 then
		IslandService.paintTerrain()
		return folder
	end

	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DriveIslands"
	folder.Parent = lobbyRoot()

	table.clear(IslandService._islands)
	table.clear(IslandService._byId)
	table.clear(IslandService._npcs)

	for i, entry in Config.Islands.Catalog do
		local record = buildFlatIsland(entry, folder)
		table.insert(IslandService._islands, record)
		IslandService._byId[record.id] = record
		-- These flats are huge (thousands of parts each). Yield between isles so a
		-- cold boot can't exhaust the script execution budget building them all at
		-- once. Safe: ensure() is only ever called off the critical portal path.
		if i < #Config.Islands.Catalog then
			task.wait()
		end
	end

	-- Register every loot model so drag / weld / pickup remotes can find them
	local LootPropService = require(script.Parent:WaitForChild("LootPropService"))
	for _, desc in folder:GetDescendants() do
		if desc:IsA("Model") and desc:GetAttribute("IsLootProp") == true then
			LootPropService.registerExisting(desc)
		end
	end

	IslandService.paintTerrain()
	print(`[SurviveAtSea] {#IslandService._islands} massive voxel-terrain isles ready (organic coastlines, beaches, hills & rocky peaks, jungle, villages/towns, loot, visit lockout)`)
	return folder
end

function IslandService.start(
	toastRemote: RemoteEvent,
	getPartyCode: (Player) -> string?,
	getMemberUserIds: (string) -> { number }
)
	if IslandService._started then
		return
	end
	IslandService._started = true
	IslandService._Toast = toastRemote
	IslandService._getPartyCode = getPartyCode
	IslandService._getMemberUserIds = getMemberUserIds

	IslandService.ensure()

	-- The NPC AI pass is O(NPCs x players) and used to run every Heartbeat (60 Hz) even
	-- with nobody online. Run it on a fixed ~15 Hz tick, feeding it the accumulated dt so
	-- movement stays time-correct, and skip it entirely when no players are present.
	local npcAccum = 0
	local NPC_INTERVAL = 1 / 15
	local lockAccum = 0
	RunService.Heartbeat:Connect(function(dt)
		npcAccum += dt
		if npcAccum >= NPC_INTERVAL then
			local step = npcAccum
			npcAccum = 0
			if #Players:GetPlayers() > 0 then
				updateNpcs(step)
			end
		end

		lockAccum += dt
		if lockAccum >= 0.2 then
			lockAccum = 0
			updateVisitLockouts()
		end
	end)
end

return IslandService
