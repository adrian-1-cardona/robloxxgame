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

local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))
local LootPropFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("LootPropFactory"))
local NpcFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("NpcFactory"))
local VillageBuilder = require(script.Parent:WaitForChild("VillageBuilder"))
local MerchantService = require(script.Parent:WaitForChild("MerchantService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

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
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.Shape ~= nil then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

-- Horizontal disc (cylinder laid flat) — used to give islands a rounded, organic
-- footprint instead of the old hard square silhouette. Diameter spans XZ, thickness is Y.
local function makeDisc(props: { [string]: any }): Part
	local diameter = props.Diameter or 4
	local thickness = props.Thickness or 1
	local p = Instance.new("Part")
	p.Name = props.Name or "IslandDisc"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.Sand
	p.Color = props.Color or Color3.fromRGB(220, 200, 158)
	p.Shape = Enum.PartType.Cylinder
	-- A Cylinder's flat faces sit on its local X axis; rotate X→Y so the disc lies flat.
	p.Size = Vector3.new(thickness, diameter, diameter)
	p.CFrame = (props.CFrame or CFrame.new()) * CFrame.Angles(0, 0, math.rad(90))
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
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
			Shape = Enum.PartType.Ball,
		})
	end
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
			Shape = Enum.PartType.Ball,
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

-- Gentle central rise (a couple of walkable steps) topped with palms + a boulder so
-- every isle has a real high point instead of a pancake.
local function buildHill(model: Model, center: Vector3, size: number, topY: number, biome: string): number
	local baseDia = size * 0.46
	local layers = 3
	local stepH = 2.1
	local grassColor = if biome == "jungle" then Color3.fromRGB(40, 96, 48) else Color3.fromRGB(70, 134, 66)
	local peakY = topY
	for i = 0, layers - 1 do
		local t = i / layers
		local dia = baseDia * (1 - t * 0.6)
		local y = topY + 0.4 + i * stepH + stepH * 0.5
		makeDisc({
			Name = `HillTier_{i}`,
			Parent = model,
			Diameter = dia,
			Thickness = stepH + 0.4,
			CFrame = CFrame.new(center.X, y, center.Z),
			Color = grassColor:Lerp(Color3.fromRGB(150, 132, 96), t * 0.22),
			Material = Enum.Material.Grass,
			CanCollide = true,
		})
		peakY = y + (stepH + 0.4) * 0.5
	end
	-- Rounded grassy crown
	makePart({
		Name = "HillCrown",
		Parent = model,
		Size = Vector3.new(baseDia * 0.34, baseDia * 0.2, baseDia * 0.34),
		CFrame = CFrame.new(center.X, peakY - 0.4, center.Z),
		Color = grassColor,
		Material = Enum.Material.Grass,
		CanCollide = true,
		Shape = Enum.PartType.Ball,
	})
	-- A landmark palm cluster + boulder on the summit
	buildPalm(model, peakY, center.X - baseDia * 0.06, center.Z + baseDia * 0.04, 1.25)
	if math.random() < 0.6 then
		buildPalm(model, peakY, center.X + baseDia * 0.1, center.Z - baseDia * 0.08, 1.0)
	end
	buildRock(model, peakY, center.X + baseDia * 0.14, center.Z + baseDia * 0.12, 1.3)
	return peakY
end

local function scatterVegetation(model: Model, center: Vector3, size: number, topY: number, biome: string)
	local half = size * 0.5
	local beachBand = half * 0.78 -- outer ring stays sandier; vegetation denser inward

	-- Density divisors are tuned so these HUGE isles stay lush and explorable without the
	-- per-isle part count exploding (island area grows with the square of the radius).
	local palmCount = math.floor(size / 13)
	if biome == "beach" then
		palmCount = math.floor(size / 16)
	elseif biome == "jungle" then
		palmCount = math.floor(size / 14)
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
		buildPalm(model, topY, x, z)
	end

	local bushCount = math.floor(size / 10)
	for _ = 1, bushCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.12 + math.random() * 0.7)
		if r > beachBand and biome == "beach" then
			continue
		end
		buildBush(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r, biome == "jungle")
	end

	local tuftCount = math.floor(size / 6)
	for _ = 1, tuftCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.65)
		buildGrassTuft(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r)
	end

	if biome == "jungle" or biome == "palm" then
		local treeCount = if biome == "jungle" then math.floor(size / 20) else math.floor(size / 36)
		for _ = 1, treeCount do
			local angle = math.random() * math.pi * 2
			-- Keep the very center clear for the hill/village heart, then spread trees
			-- across most of the interior so a huge jungle isle is dense to explore.
			local r = half * (0.22 + math.random() * 0.6)
			buildJungleTree(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r)
		end
	end

	-- Rolling dunes across the interior — breaks up the flat with gentle rises
	local duneCount = math.floor(size / 34)
	for _ = 1, duneCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.62)
		buildDune(
			model,
			topY,
			center.X + math.cos(angle) * r,
			center.Z + math.sin(angle) * r,
			math.random() < 0.6
		)
	end

	-- Rock outcrops — a few inland, more clustered near the shoreline
	local rockCount = math.floor(size / 50)
	for _ = 1, rockCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.35 + math.random() * 0.55)
		buildRock(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r)
	end

	-- Weathered driftwood logs washed up along the beach ring
	local driftCount = math.clamp(math.floor(size / 55), 2, 8)
	for _ = 1, driftCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.72 + math.random() * 0.2)
		buildDriftwood(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r)
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

	-- Rounded sand foundation — a solid disc gives the isle an organic, circular
	-- coastline instead of the old hard square. This is the walkable footprint.
	local deck = makeDisc({
		Name = "FlatSand",
		Parent = model,
		Diameter = size,
		Thickness = thickness,
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(228, 208, 164),
		Material = Enum.Material.Sand,
		CanCollide = true,
	})
	model.PrimaryPart = deck

	-- Sloping beach shelf — wider, lower rounded sand that eases down into the surf.
	-- COLLIDABLE so you can actually walk the outer coastline instead of sinking through
	-- the sand fringe that sits beyond the solid deck disc.
	makeDisc({
		Name = "BeachShelf",
		Parent = model,
		Diameter = size + 46,
		Thickness = 2.6,
		-- Top sits ~0.1 below the deck top so the outer sand fringe is walkable (no falling
		-- through past the deck edge) without forming a lip above the interior.
		CFrame = CFrame.new(center.X, topY - 1.4, center.Z),
		Color = Color3.fromRGB(236, 218, 178),
		Material = Enum.Material.Sand,
		CanCollide = true,
		CastShadow = false,
	})

	-- Tide-wet sand band near the shoreline (darker, damp ring). Sits ~flush with the deck
	-- top so it's a thin cosmetic skin, never a lip you sink into.
	makeDisc({
		Name = "WetSandRing",
		Parent = model,
		Diameter = size * 0.98,
		Thickness = 0.35,
		CFrame = CFrame.new(center.X, topY - 0.1, center.Z),
		Color = Color3.fromRGB(198, 178, 142),
		Material = Enum.Material.Sand,
		CanCollide = false,
		CastShadow = false,
	})

	-- Rounded grass meadow (sand rim → green heart) laid flush on top of the deck.
	-- Top is essentially level with the sand deck (topY) so players stand on a single
	-- clean surface — no sinking into the "first layer" of grass/sand.
	local grassSize = size * 0.74
	makeDisc({
		Name = "GrassHeart",
		Parent = model,
		Diameter = grassSize,
		Thickness = 0.5,
		CFrame = CFrame.new(center.X, topY - 0.2, center.Z),
		Color = if biome == "jungle" then Color3.fromRGB(46, 102, 52) else Color3.fromRGB(72, 138, 68),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})

	-- Jungle undergrowth: a darker leafy patch toward the center (flush cosmetic skin)
	if biome == "jungle" or biome == "palm" then
		local jungleSize = size * (if biome == "jungle" then 0.44 else 0.3)
		makeDisc({
			Name = "JungleFloor",
			Parent = model,
			Diameter = jungleSize,
			Thickness = 0.5,
			CFrame = CFrame.new(center.X + size * 0.03, topY - 0.14, center.Z - size * 0.02),
			Color = Color3.fromRGB(34, 82, 40),
			Material = Enum.Material.LeafyGrass,
			CanCollide = false,
		})
	end

	-- Submerged reef shelf ringing the isle (rounded, sits just under the surface)
	makeDisc({
		Name = "ReefShelf",
		Parent = model,
		Diameter = size + 90,
		Thickness = 3,
		CFrame = CFrame.new(center.X, OceanConfig.SurfaceY - 1.4, center.Z),
		Color = Color3.fromRGB(62, 118, 108),
		Material = Enum.Material.Limestone,
		CanCollide = false,
		CastShadow = false,
	})

	-- Coral / rock knolls in the shallows
	local knobCount = math.floor(size / 30)
	for i = 1, knobCount do
		local angle = (i / math.max(knobCount, 1)) * math.pi * 2 + math.random() * 0.5
		local r = size * 0.5 + 8 + math.random() * 12
		makePart({
			Name = `ReefKnob_{i}`,
			Parent = model,
			Size = Vector3.new(3 + math.random() * 4, 1.5 + math.random() * 1.5, 3 + math.random() * 4),
			CFrame = CFrame.new(center.X + math.cos(angle) * r, OceanConfig.SurfaceY - 0.4, center.Z + math.sin(angle) * r),
			Color = Color3.fromRGB(180 + math.random(0, 40), 110 + math.random(0, 40), 120),
			Material = Enum.Material.Coral,
			CanCollide = false,
			Shape = Enum.PartType.Ball,
		})
	end

	-- Central grassy rise so the isle has a real high point
	buildHill(model, center, size, topY, biome)

	scatterVegetation(model, center, size, topY, biome)
	scatterLooseLoot(model, center, size, topY, entry.Id)

	local marker = makePart({
		Name = "IsleMarker",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center.X, topY + 18, center.Z),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "IsleBillboard"
	gui.Adornee = marker
	gui.Size = UDim2.fromOffset(200, 44)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 900
	gui.Parent = marker

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 0.28
	label.BackgroundColor3 = Color3.fromRGB(18, 36, 48)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Config.Theme.Foam
	label.Text = string.upper(entry.Name)
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

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
		label = label,
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
		}
		local layout = VillageBuilder.build(model, center, size, topY, entry, deps)
		local spots = layout.villagerSpots
		local spotCount = math.max(#spots, 1)

		local function spotAt(i: number): CFrame
			local base = spots[((i - 1) % spotCount) + 1] or Vector3.new(center.X, topY + 2.5, center.Z)
			local jitter = Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8)
			local pos = base + jitter
			return CFrame.new(Vector3.new(pos.X, topY + 2.5, pos.Z))
		end

		if record.abandoned then
			-- Rare feral scavengers only.
			for i = 1, (villagerCfg.Hostile or 0) do
				spawnVillager(record, spotAt(i), "scavenger")
			end
		else
			for i = 1, (villagerCfg.Passive or 0) do
				spawnVillager(record, spotAt(i), "passive")
			end
			for i = 1, (villagerCfg.Hostile or 0) do
				spawnVillager(record, spotAt(i + 3), "hostile")
			end
		end

		-- The blue-hatted merchant (never hostile, draggable / weldable to your raft).
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
	for _, isle in IslandService._islands do
		-- Rounded sand body under the isle so the terrain silhouette matches the
		-- new circular disc coastline (FillCylinder axis follows the CFrame up vector).
		local sandRadius = isle.size * 0.5 + 12
		Workspace.Terrain:FillCylinder(
			CFrame.new(isle.center),
			isle.thickness + 8,
			sandRadius,
			Enum.Material.Sand
		)
		-- Soft grass cap in the heart for beach / jungle read under fog
		local grassRadius = isle.size * 0.36
		Workspace.Terrain:FillCylinder(
			CFrame.new(isle.center.X, isle.center.Y + 2, isle.center.Z),
			4,
			grassRadius,
			if isle.biome == "jungle" then Enum.Material.LeafyGrass else Enum.Material.Grass
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
	if math.abs(pos.Y - isle.topY) > 18 then
		-- Allow standing / jumping on the flat
		if pos.Y < isle.topY - 2 or pos.Y > isle.topY + 20 then
			return false
		end
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
				local character = bestPlayer.Character
				local hum = character and character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					hum:TakeDamage(combat.Damage)
				end
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
	print(`[SurviveAtSea] {#IslandService._islands} massive rounded isles ready (hills, dunes, rocks, driftwood, palms, jungle, loot, visit lockout)`)
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

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		updateNpcs(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		updateVisitLockouts()
	end)
end

return IslandService
