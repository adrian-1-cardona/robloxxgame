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

local GunService = require(script.Parent:WaitForChild("GunService"))
local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))
local LootPropFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("LootPropFactory"))

export type IslandRecord = {
	id: string,
	name: string,
	center: Vector3,
	size: number,
	topY: number,
	thickness: number,
	hasHouse: boolean,
	pirateCount: number,
	biome: string,
	model: Model,
	label: TextLabel?,
	pirates: { Model },
}

type CrewIslandState = {
	visited: boolean,
	locked: boolean,
	notifiedLock: boolean,
	notifiedVisit: boolean,
}

type PirateRuntime = {
	model: Model,
	islandId: string,
	attackAccum: number,
	alive: boolean,
}

local IslandService = {}

IslandService._islands = {} :: { IslandRecord }
IslandService._byId = {} :: { [string]: IslandRecord }
IslandService._crewState = {} :: { [string]: { [string]: CrewIslandState } }
IslandService._pirates = {} :: { PirateRuntime }
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

local function scatterVegetation(model: Model, center: Vector3, size: number, topY: number, biome: string)
	local half = size * 0.5
	local beachBand = half * 0.78 -- outer ring stays sandier; vegetation denser inward

	local palmCount = math.floor(size / 9)
	if biome == "beach" then
		palmCount = math.floor(size / 11)
	elseif biome == "jungle" then
		palmCount = math.floor(size / 10)
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

	local bushCount = math.floor(size / 7)
	for _ = 1, bushCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.12 + math.random() * 0.7)
		if r > beachBand and biome == "beach" then
			continue
		end
		buildBush(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r, biome == "jungle")
	end

	local tuftCount = math.floor(size / 4)
	for _ = 1, tuftCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.65)
		buildGrassTuft(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r)
	end

	if biome == "jungle" or biome == "palm" then
		local treeCount = if biome == "jungle" then math.floor(size / 16) else math.floor(size / 28)
		for _ = 1, treeCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.08 + math.random() * 0.45)
			buildJungleTree(model, topY, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r)
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

local function buildHouse(model: Model, center: Vector3, topY: number, islandId: string)
	local houseCf = CFrame.new(center.X + 6, topY, center.Z - 4)
	local floor = makePart({
		Name = "HouseFloor",
		Parent = model,
		Size = Vector3.new(16, 0.6, 14),
		CFrame = houseCf * CFrame.new(0, 0.3, 0),
		Color = Color3.fromRGB(110, 78, 48),
		Material = Enum.Material.WoodPlanks,
	})

	local wallH = 7
	local wallY = topY + wallH * 0.5
	local wallsFolder = Instance.new("Folder")
	wallsFolder.Name = "SalvageWalls"
	wallsFolder.Parent = model

	-- Detachable walls — drag onto your boat for a mini shelter
	for _, spec in {
		{ Name = "WallBack", Size = Vector3.new(16, wallH, 0.7), Offset = Vector3.new(0, 0, -6.65) },
		{ Name = "WallLeft", Size = Vector3.new(0.7, wallH, 13), Offset = Vector3.new(-7.65, 0, 0) },
		{ Name = "WallRight", Size = Vector3.new(0.7, wallH, 13), Offset = Vector3.new(7.65, 0, 0) },
		{ Name = "WallFrontL", Size = Vector3.new(5.2, wallH, 0.7), Offset = Vector3.new(-5.4, 0, 6.65) },
		{ Name = "WallFrontR", Size = Vector3.new(5.2, wallH, 0.7), Offset = Vector3.new(5.4, 0, 6.65) },
	} do
		local wallCf = CFrame.new(floor.Position + Vector3.new(spec.Offset.X, wallY - topY - 0.3, spec.Offset.Z))
		local wall = LootPropFactory.createWallWorld(wallsFolder, spec.Size, wallCf)
		wall.Name = spec.Name
		wall:SetAttribute("IslandId", islandId)
		wall:SetAttribute("FromHouse", true)
	end

	-- Roof stays fixed (not loot) so the shack still reads as a ruin after walls leave
	makePart({
		Name = "Roof",
		Parent = model,
		Size = Vector3.new(17.5, 0.7, 15.5),
		CFrame = CFrame.new(floor.Position + Vector3.new(0, wallH + 0.2, 0)),
		Color = Color3.fromRGB(78, 52, 30),
		Material = Enum.Material.Wood,
	})

	-- Interior torch (loot)
	local torch = LootPropFactory.createTorchWorld(
		model,
		CFrame.new(floor.Position + Vector3.new(4, 1.7, -3))
	)
	torch:SetAttribute("IslandId", islandId)

	-- Raid chest
	local chest = makePart({
		Name = "RaidChest",
		Parent = model,
		Size = Vector3.new(2.4, 1.6, 1.5),
		CFrame = CFrame.new(floor.Position + Vector3.new(-2, 1.1, -2)),
		Color = Color3.fromRGB(96, 68, 36),
		Material = Enum.Material.Wood,
	})
	chest:SetAttribute("IslandId", islandId)
	chest:SetAttribute("LootedBy", "")

	local anchor = makePart({
		Name = "ChestPromptAnchor",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = chest.CFrame * CFrame.new(0, 1.2, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RaidPrompt"
	prompt.ActionText = "Raid Chest"
	prompt.ObjectText = "Hidden Cache"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		local code = IslandService._getPartyCode and IslandService._getPartyCode(player)
		if not code then
			return
		end
		local state = ensureCrewState(code, islandId)
		if state.locked then
			if IslandService._Toast then
				IslandService._Toast:FireClient(player, "This isle is closed to your crew.", "error")
			end
			return
		end
		local lootedAttr = chest:GetAttribute("Looted_" .. player.UserId)
		if lootedAttr == true then
			if IslandService._Toast then
				IslandService._Toast:FireClient(player, "You already raided this chest.", "info")
			end
			return
		end
		if GunService.giveFlintlock(player) then
			chest:SetAttribute("Looted_" .. player.UserId, true)
		end
	end)
end

local function spawnPirate(island: IslandRecord, index: number): Model
	local cfg = Config.Islands.Pirate
	local angle = (index / math.max(island.pirateCount, 1)) * math.pi * 2
	local radius = island.size * 0.22
	local spawnPos = Vector3.new(
		island.center.X + math.cos(angle) * radius,
		island.topY + 2.5,
		island.center.Z + math.sin(angle) * radius
	)

	local model = Instance.new("Model")
	model.Name = `Pirate_{island.id}_{index}`
	model:SetAttribute("IsPirate", true)
	model:SetAttribute("IslandId", island.id)
	model.Parent = island.model

	local root = makePart({
		Name = "HumanoidRootPart",
		Parent = model,
		Size = Vector3.new(2, 2, 1),
		CFrame = CFrame.new(spawnPos),
		Color = Color3.fromRGB(70, 52, 40),
		Material = Enum.Material.Fabric,
		CanCollide = true,
	})
	model.PrimaryPart = root

	makePart({
		Name = "Torso",
		Parent = model,
		Size = Vector3.new(2.1, 2.1, 1.1),
		CFrame = root.CFrame * CFrame.new(0, 0.1, 0),
		Color = Color3.fromRGB(48, 72, 88),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	makePart({
		Name = "Head",
		Parent = model,
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = root.CFrame * CFrame.new(0, 1.7, 0),
		Color = Color3.fromRGB(210, 180, 145),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Shape = Enum.PartType.Ball,
	})
	makePart({
		Name = "Bandana",
		Parent = model,
		Size = Vector3.new(1.35, 0.35, 1.35),
		CFrame = root.CFrame * CFrame.new(0, 2.15, 0),
		Color = Color3.fromRGB(160, 40, 40),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = cfg.Health
	humanoid.Health = cfg.Health
	humanoid.WalkSpeed = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PirateTag"
	billboard.Size = UDim2.fromOffset(80, 24)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.Adornee = root
	billboard.Parent = root

	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Size = UDim2.fromScale(1, 1)
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = Config.Theme.DangerRed
	tag.Text = "Pirate"
	tag.Parent = billboard

	humanoid.Died:Connect(function()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
		task.delay(2.5, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	return model
end

local function buildFlatIsland(entry: {
	Id: string,
	Name: string,
	Offset: Vector3,
	SizeStuds: number,
	HasHouse: boolean,
	Pirates: number,
	Biome: string?,
}, folder: Folder): IslandRecord
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

	-- Deep sand foundation (whole island footprint)
	local deck = makePart({
		Name = "FlatSand",
		Parent = model,
		Size = Vector3.new(size, thickness, size),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(228, 208, 164),
		Material = Enum.Material.Sand,
		CanCollide = true,
	})
	model.PrimaryPart = deck

	-- Soft beach apron — wider shallow sand lip into the water
	makePart({
		Name = "BeachApron",
		Parent = model,
		Size = Vector3.new(size + 18, 1.1, size + 18),
		CFrame = CFrame.new(center.X, topY - 0.2, center.Z),
		Color = Color3.fromRGB(236, 218, 178),
		Material = Enum.Material.Sand,
		CanCollide = false,
		CastShadow = false,
	})

	-- Inner grass meadow (beach vibe: sand rim, green heart)
	local grassSize = size * 0.72
	makePart({
		Name = "GrassHeart",
		Parent = model,
		Size = Vector3.new(grassSize, 0.55, grassSize),
		CFrame = CFrame.new(center.X, topY + 0.2, center.Z),
		Color = if biome == "jungle" then Color3.fromRGB(46, 102, 52) else Color3.fromRGB(72, 138, 68),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})

	-- Jungle undergrowth darker patch toward center
	if biome == "jungle" or biome == "palm" then
		local jungleSize = size * (if biome == "jungle" then 0.42 else 0.28)
		makePart({
			Name = "JungleFloor",
			Parent = model,
			Size = Vector3.new(jungleSize, 0.5, jungleSize),
			CFrame = CFrame.new(center.X + size * 0.04, topY + 0.35, center.Z - size * 0.03),
			Color = Color3.fromRGB(34, 82, 40),
			Material = Enum.Material.LeafyGrass,
			CanCollide = false,
		})
	end

	-- Tide-wet sand band near the shoreline
	local wet = size * 0.92
	makePart({
		Name = "WetSandRing",
		Parent = model,
		Size = Vector3.new(wet, 0.25, wet),
		CFrame = CFrame.new(center.X, topY + 0.05, center.Z),
		Color = Color3.fromRGB(198, 178, 142),
		Material = Enum.Material.Sand,
		CanCollide = false,
		CastShadow = false,
	})
	-- Punch visual: grass sits on top of wet sand in the middle via GrassHeart already

	makePart({
		Name = "ReefShelf",
		Parent = model,
		Size = Vector3.new(size + 28, 2.8, size + 28),
		CFrame = CFrame.new(center.X, OceanConfig.SurfaceY - 1.4, center.Z),
		Color = Color3.fromRGB(62, 118, 108),
		Material = Enum.Material.Limestone,
		CanCollide = false,
		CastShadow = false,
	})

	-- Coral / rock knolls in the shallows
	for i = 1, math.floor(size / 35) do
		local angle = (i / math.max(size / 35, 1)) * math.pi * 2
		local r = size * 0.5 + 6 + math.random() * 8
		makePart({
			Name = `ReefKnob_{i}`,
			Parent = model,
			Size = Vector3.new(3 + math.random() * 3, 1.5 + math.random(), 3 + math.random() * 3),
			CFrame = CFrame.new(center.X + math.cos(angle) * r, OceanConfig.SurfaceY - 0.4, center.Z + math.sin(angle) * r),
			Color = Color3.fromRGB(180 + math.random(0, 40), 110 + math.random(0, 40), 120),
			Material = Enum.Material.Coral,
			CanCollide = false,
			Shape = Enum.PartType.Ball,
		})
	end

	local lipY = topY + 0.18
	local lipT = 2.4
	local half = size * 0.5
	for _, spec in {
		{ Name = "LipNorth", CFrame = CFrame.new(center.X, lipY, center.Z - half + lipT * 0.5), Size = Vector3.new(size, 0.4, lipT) },
		{ Name = "LipSouth", CFrame = CFrame.new(center.X, lipY, center.Z + half - lipT * 0.5), Size = Vector3.new(size, 0.4, lipT) },
		{ Name = "LipWest", CFrame = CFrame.new(center.X - half + lipT * 0.5, lipY, center.Z), Size = Vector3.new(lipT, 0.4, size - lipT * 2) },
		{ Name = "LipEast", CFrame = CFrame.new(center.X + half - lipT * 0.5, lipY, center.Z), Size = Vector3.new(lipT, 0.4, size - lipT * 2) },
	} do
		makePart({
			Name = spec.Name,
			Parent = model,
			Size = spec.Size,
			CFrame = spec.CFrame,
			Color = Color3.fromRGB(242, 224, 186),
			Material = Enum.Material.Sand,
			CanCollide = false,
		})
	end

	scatterVegetation(model, center, size, topY, biome)
	scatterLooseLoot(model, center, size, topY, entry.Id)

	if entry.HasHouse then
		buildHouse(model, center, topY, entry.Id)
	end

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

	local record: IslandRecord = {
		id = entry.Id,
		name = entry.Name,
		center = center,
		size = size,
		topY = topY,
		thickness = thickness,
		hasHouse = entry.HasHouse == true,
		pirateCount = entry.Pirates or 0,
		biome = biome,
		model = model,
		label = label,
		pirates = {},
	}

	for i = 1, record.pirateCount do
		local pirate = spawnPirate(record, i)
		table.insert(record.pirates, pirate)
		table.insert(IslandService._pirates, {
			model = pirate,
			islandId = record.id,
			attackAccum = 0,
			alive = true,
		})
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
		local pad = 10
		local size = Vector3.new(isle.size + pad * 2, isle.thickness + 6, isle.size + pad * 2)
		Workspace.Terrain:FillBlock(CFrame.new(isle.center), size, Enum.Material.Sand)
		-- Soft grass fill in the heart for beach / jungle read under fog
		local grass = isle.size * 0.7
		Workspace.Terrain:FillBlock(
			CFrame.new(isle.center.X, isle.center.Y + 1.5, isle.center.Z),
			Vector3.new(grass, 3, grass),
			if isle.biome == "jungle" then Enum.Material.LeafyGrass else Enum.Material.Grass
		)
	end
end

function IslandService.isLockedForCrew(code: string, islandId: string): boolean
	local byIsle = IslandService._crewState[code]
	local state = byIsle and byIsle[islandId]
	return state ~= nil and state.locked == true
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

local function updatePirates(dt: number)
	local cfg = Config.Islands.Pirate
	for _, runtime in IslandService._pirates do
		if not runtime.alive then
			continue
		end
		local model = runtime.model
		if not model.Parent then
			runtime.alive = false
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
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

		-- Nearest living player on this island (or within aggro of the sand)
		local bestPlayer: Player? = nil
		local bestDist = cfg.AggroRange
		local bestPos: Vector3? = nil
		for _, plr in Players:GetPlayers() do
			local character = plr.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if not (hrp and hrp:IsA("BasePart") and hum and hum.Health > 0) then
				continue
			end
			-- Stay bound to island waters — only chase people near this isle
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
			local step = math.min(cfg.ChaseSpeed * dt, toTarget.Magnitude)
			local nextPos = root.Position + toTarget.Unit * step
			-- Keep pirates on the flat
			local fromCenter = Vector3.new(nextPos.X - isle.center.X, 0, nextPos.Z - isle.center.Z)
			local maxR = isle.size * 0.48
			if fromCenter.Magnitude > maxR then
				fromCenter = fromCenter.Unit * maxR
				nextPos = Vector3.new(isle.center.X + fromCenter.X, isle.topY + 2.5, isle.center.Z + fromCenter.Z)
			else
				nextPos = Vector3.new(nextPos.X, isle.topY + 2.5, nextPos.Z)
			end
			local lookAt = Vector3.new(bestPos.X, nextPos.Y, bestPos.Z)
			local newCf = CFrame.lookAt(nextPos, lookAt)
			local oldCf = root.CFrame
			local delta = newCf * oldCf:Inverse()
			for _, desc in model:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.CFrame = delta * desc.CFrame
				end
			end
		end

		runtime.attackAccum += dt
		if runtime.attackAccum >= cfg.AttackCooldown and bestDist <= 3.6 then
			runtime.attackAccum = 0
			local character = bestPlayer.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum:TakeDamage(cfg.Damage)
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
	table.clear(IslandService._pirates)

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
	print(`[SurviveAtSea] {#IslandService._islands} huge beach isles ready (palms, jungle, loot, visit lockout)`)
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
		updatePirates(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		updateVisitLockouts()
	end)
end

return IslandService
