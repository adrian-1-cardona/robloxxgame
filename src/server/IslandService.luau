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
local IslandTerrain = require(script.Parent:WaitForChild("IslandTerrain"))
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
	-- A channel cut all the way through a large island. The helm uses this to allow
	-- boats through the river rather than treating the whole island as solid shore.
	river: { cframe: CFrame, width: number, length: number }?,
	-- Spawn plan retained for deterministic population and testability.
	villagerPlan: {
		spots: { Vector3 },
		passive: number,
		hostile: number,
		abandoned: boolean,
	}?,
	populated: boolean?,
	-- The arrival hub contains the crew spawn channel. It is deliberately excluded
	-- from the shoreline guard because crews begin inside that sheltered water.
	safeHarbor: boolean?,
	-- The island's silhouette (src/shared/IslandShape.luau). Terrain, props, the village
	-- and raft collision all read the coastline from here, so they cannot disagree.
	shape: any,
	-- Submerged footprint, replayed after the ocean streamer refills water chunks.
	submergedPlan: { any }?,
}

type CrewIslandState = {
	visited: boolean,
	locked: boolean,
	notifiedLock: boolean,
	notifiedVisit: boolean,
}

type DockCollider = {
	cframe: CFrame,
	size: Vector3,
	islandName: string,
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
-- Helm travel is kinematic (the raft is PivotTo'd), so it does not receive normal
-- physics contacts.  Keep a tiny collision representation for the solid dock decks.
IslandService._dockColliders = {} :: { DockCollider }
IslandService._Toast = nil :: RemoteEvent?
IslandService._getPartyCode = nil :: ((Player) -> string?)?
IslandService._getMemberUserIds = nil :: ((string) -> { number })?
IslandService._started = false
IslandService._starting = false
IslandService._folder = nil :: Folder?
IslandService._endlessQueued = {} :: { [string]: boolean }
IslandService._endlessBuildActive = false

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

-- Deterministic 0..1 stream keyed by a string. IslandShape's placement helpers take a
-- plain function so they stay free of Roblox APIs; this is the server's supply of one.
-- Keyed per purpose ("isleId_palms") so adding one prop pass cannot shift another's layout.
local function randomStream(key: string): () -> number
	local seed = 2166136261
	for i = 1, #key do
		seed = (seed * 31 + string.byte(key, i)) % 2147483647
	end
	local rng = Random.new(seed)
	return function(): number
		return rng:NextNumber()
	end
end

-- Shared wood colours for docks, boardwalks and stilt decks.
local DOCK_PLANK = Color3.fromRGB(122, 86, 52)
local DOCK_POST = Color3.fromRGB(84, 58, 36)

local function worldCenterForOffset(offset: Vector3, topY: number, thickness: number): Vector3
	local origin = Config.StarterBase.Origin
	return Vector3.new(origin.X + offset.X, topY - thickness * 0.5, origin.Z + offset.Z)
end

-- Reserve the opening-island folder without drawing placeholder land. The old
-- cylinder previews were visible as flat sand/grass disks while the real islands
-- loaded, which made the finished world look broken and hid its sculpted coastline.
local function ensureOpeningPreviews(folder: Folder)
	local previews = folder:FindFirstChild("OpeningPreviews")
	if not previews then
		previews = Instance.new("Folder")
		previews.Name = "OpeningPreviews"
		previews.Parent = folder
	end
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

-- Classic "ball on a stick" tree — dark green sphere canopy on a simple trunk.
local function buildVillageForestTree(model: Model, topY: number, x: number, z: number, scale: number?)
	local s = scale or (0.95 + math.random() * 0.55)
	local trunkH = (24 + math.random() * 18) * s
	local trunkCf = CFrame.new(x, topY + trunkH * 0.5, z)
	makePart({
		Name = "ForestTrunk",
		Parent = model,
		Size = Vector3.new(2.1 * s, trunkH, 2.1 * s),
		CFrame = trunkCf,
		Color = Color3.fromRGB(116, 76, 43),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	for branch = 1, 3 do
		local yaw = math.rad((branch - 1) * 120 + math.random(-18, 18))
		local length = (8 + math.random() * 5) * s
		makePart({
			Name = "ForestBranch",
			Parent = model,
			Size = Vector3.new(1.25 * s, 1.25 * s, length),
			CFrame = trunkCf * CFrame.new(0, trunkH * 0.23, 0) * CFrame.Angles(math.rad(-38), yaw, 0) * CFrame.new(0, 0, -length * 0.34),
			Color = Color3.fromRGB(116, 76, 43),
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end
	local greens = { Color3.fromRGB(30, 112, 47), Color3.fromRGB(42, 137, 57), Color3.fromRGB(52, 150, 62) }
	local canopyY = topY + trunkH + 1.5 * s
	for i = 1, 5 do
		local a = (i - 1) * (math.pi * 2 / 5)
		local radius = i == 5 and 0 or 6.2 * s
		local cube = (i == 5 and 13.5 or 10.5) * s
		makePart({
			Name = "ForestCanopyBlock",
			Parent = model,
			Size = Vector3.new(cube, cube * (0.72 + math.random() * 0.18), cube),
			CFrame = CFrame.new(x + math.cos(a) * radius, canopyY + (i == 5 and 2.2 * s or math.random(-1, 1) * s), z + math.sin(a) * radius)
				* CFrame.Angles(0, math.rad(math.random(0, 45)), 0),
			Color = greens[((i - 1) % #greens) + 1],
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

-- Tall tiered canopy used between the spreading broadleaf trees. Alternating these
-- silhouettes reproduces the reference forest's deep layers instead of making every
-- tree the same five-block crown.
local function buildTieredForestTree(model: Model, topY: number, x: number, z: number, scale: number?)
	local s = scale or (0.9 + math.random() * 0.5)
	local trunkH = (32 + math.random() * 22) * s
	makePart({
		Name = "TieredForestTrunk",
		Parent = model,
		Size = Vector3.new(2.2 * s, trunkH, 2.2 * s),
		CFrame = CFrame.new(x, topY + trunkH * 0.5, z),
		Color = Color3.fromRGB(92, 60, 38),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	local greens = {
		Color3.fromRGB(24, 94, 39),
		Color3.fromRGB(31, 118, 47),
		Color3.fromRGB(42, 139, 54),
	}
	for tier = 1, 5 do
		local width = (18 - tier * 2.1) * s
		local y = topY + trunkH * 0.4 + tier * 5.2 * s
		makePart({
			Name = "TieredCanopy",
			Parent = model,
			Size = Vector3.new(width, 4.2 * s, width),
			CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(tier * 13), 0),
			Color = greens[((tier - 1) % #greens) + 1],
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

local function terrainSurfaceY(x: number, z: number, fallbackY: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = true
	local result = Workspace:Raycast(
		Vector3.new(x, fallbackY + 280, z),
		Vector3.new(0, -420, 0),
		params
	)
	if not result or result.Material == Enum.Material.Water then
		return nil
	end
	-- A placement must have dry terrain clearly above the sea. This is the final guard
	-- against trees, shrubs, loot, and shoreline clutter appearing on open water.
	if result.Position.Y <= OceanConfig.SurfaceY + 0.65 then
		return nil
	end
	return result.Position.Y
end

-- A dense outer woodland keeps the view from each village framed by hills and trees,
-- while leaving the centre open for streets, houses, and safe player movement.
local function scatterSettlementForest(
	model: Model,
	center: Vector3,
	size: number,
	topY: number,
	features: { [string]: any }?
)
	local shape = features and features.shape
	if not shape then
		return
	end
	local count = math.clamp(math.floor(size / 16), 64, 110)
	local rand = randomStream(`{model.Name}_settlement_forest`)
	local vx, vz = shape:villageCenter()
	local clearing = shape.buildableRadius

	for _ = 1, count do
		-- Ring the settlement rather than a fixed band of the island radius: the clearing
		-- is off centre, so a fixed band used to cut straight through the village on one
		-- side and fall in the sea on the other.
		local dx, dz = shape:randomLandPoint(rand, { zone = "any", maxHeight = 60 })
		if not dx then
			continue
		end
		local toVillage = math.sqrt((dx - vx) ^ 2 + (dz - vz) ^ 2)
		-- Leave the streets and the immediate approach open.
		if toVillage < clearing * 1.05 then
			continue
		end
		local x, z = center.X + dx, center.Z + dz
		if shape:onLandmark(dx, dz) then
			continue
		end
		local groundY = terrainSurfaceY(x, z, topY)
		if not groundY then
			continue
		end
		if rand() < 0.3 then
			buildTieredForestTree(model, groundY, x, z)
		else
			buildVillageForestTree(model, groundY, x, z)
		end
	end
end

-- Four WedgeParts meeting at the peak — reads as a pyramid thatch roof.
local function buildPyramidRoof(parent: Instance, cf: CFrame, footprint: number, color: Color3)
	local h = footprint * 0.42
	local half = footprint * 0.5
	for i = 0, 3 do
		local yaw = math.rad(i * 90)
		local wedge = Instance.new("WedgePart")
		wedge.Name = "PyramidRoof"
		wedge.Anchored = true
		wedge.CanCollide = true
		wedge.CastShadow = true
		wedge.Material = Enum.Material.Grass
		wedge.Color = color
		wedge.Size = Vector3.new(footprint, h, half)
		wedge.CFrame = cf * CFrame.Angles(0, yaw, 0) * CFrame.new(0, h * 0.5, half * 0.5)
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		wedge.Parent = parent
	end
end

local STILT_WALL = Color3.fromRGB(148, 158, 110)
local STILT_ROOF = Color3.fromRGB(186, 148, 72)
local STILT_WOOD = Color3.fromRGB(110, 78, 48)
local TERRACE_STONE = Color3.fromRGB(168, 170, 172)

-- Open-window hut on stilts over the water (or a summit pavilion when overLand).
local function buildStiltHut(
	model: Model,
	pos: Vector3,
	surfaceY: number,
	yaw: number,
	opts: { [string]: any }?
)
	local o = opts or {}
	local s = (o.scale :: number?) or 1
	local overLand = o.overLand == true
	local hut = Instance.new("Model")
	hut.Name = if overLand then "SummitPavilion" else "StiltHut"
	hut.Parent = model

	local w, d, wallH = 14 * s, 12 * s, 7 * s
	local deckY = if overLand then pos.Y else (surfaceY + 5.5 * s)
	local floorCf = CFrame.new(pos.X, deckY, pos.Z) * CFrame.Angles(0, yaw, 0)

	if not overLand then
		local pileBot = surfaceY - 8
		local pileH = deckY - pileBot
		local pileY = (deckY + pileBot) * 0.5
		for _, ox in { -w * 0.42, w * 0.42 } do
			for _, oz in { -d * 0.42, d * 0.42 } do
				local p = floorCf * CFrame.new(ox, 0, oz)
				makePart({
					Name = "Stilt",
					Parent = hut,
					Size = Vector3.new(1.1 * s, pileH, 1.1 * s),
					CFrame = CFrame.new(p.X, pileY, p.Z),
					Color = STILT_WOOD,
					Material = Enum.Material.Wood,
					CastShadow = true,
				})
			end
		end
	end

	makePart({
		Name = "HutFloor",
		Parent = hut,
		Size = Vector3.new(w, 0.6 * s, d),
		CFrame = floorCf,
		Color = DOCK_PLANK,
		Material = Enum.Material.WoodPlanks,
		CastShadow = true,
	})

	-- Four walls with a big open window in each face.
	local walls = {
		{ offset = CFrame.new(0, wallH * 0.5, -d * 0.5), size = Vector3.new(w, wallH, 0.55 * s), win = "z" },
		{ offset = CFrame.new(0, wallH * 0.5, d * 0.5), size = Vector3.new(w, wallH, 0.55 * s), win = "z" },
		{ offset = CFrame.new(-w * 0.5, wallH * 0.5, 0), size = Vector3.new(0.55 * s, wallH, d), win = "x" },
		{ offset = CFrame.new(w * 0.5, wallH * 0.5, 0), size = Vector3.new(0.55 * s, wallH, d), win = "x" },
	}
	for i, wall in walls do
		local along = if wall.win == "z" then wall.size.X else wall.size.Z
		local side = along * 0.22
		local winW = along * 0.46
		local sillH = wallH * 0.28
		local headH = wallH * 0.22
		if wall.win == "z" then
			makePart({
				Name = `WallL_{i}`,
				Parent = hut,
				Size = Vector3.new(side, wallH, wall.size.Z),
				CFrame = floorCf * wall.offset * CFrame.new(-(winW * 0.5 + side * 0.5), 0, 0),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = `WallR_{i}`,
				Parent = hut,
				Size = Vector3.new(side, wallH, wall.size.Z),
				CFrame = floorCf * wall.offset * CFrame.new(winW * 0.5 + side * 0.5, 0, 0),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = `WallSill_{i}`,
				Parent = hut,
				Size = Vector3.new(winW, sillH, wall.size.Z),
				CFrame = floorCf * wall.offset * CFrame.new(0, -wallH * 0.5 + sillH * 0.5, 0),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = `WallHead_{i}`,
				Parent = hut,
				Size = Vector3.new(winW, headH, wall.size.Z),
				CFrame = floorCf * wall.offset * CFrame.new(0, wallH * 0.5 - headH * 0.5, 0),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
		else
			makePart({
				Name = `WallL_{i}`,
				Parent = hut,
				Size = Vector3.new(wall.size.X, wallH, side),
				CFrame = floorCf * wall.offset * CFrame.new(0, 0, -(winW * 0.5 + side * 0.5)),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = `WallR_{i}`,
				Parent = hut,
				Size = Vector3.new(wall.size.X, wallH, side),
				CFrame = floorCf * wall.offset * CFrame.new(0, 0, winW * 0.5 + side * 0.5),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = `WallSill_{i}`,
				Parent = hut,
				Size = Vector3.new(wall.size.X, sillH, winW),
				CFrame = floorCf * wall.offset * CFrame.new(0, -wallH * 0.5 + sillH * 0.5, 0),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = `WallHead_{i}`,
				Parent = hut,
				Size = Vector3.new(wall.size.X, headH, winW),
				CFrame = floorCf * wall.offset * CFrame.new(0, wallH * 0.5 - headH * 0.5, 0),
				Color = STILT_WALL,
				Material = Enum.Material.Wood,
			})
		end
	end

	buildPyramidRoof(hut, floorCf * CFrame.new(0, wallH + 0.15 * s, 0), math.max(w, d) + 2.5 * s, STILT_ROOF)
	return Vector3.new(pos.X, deckY, pos.Z)
end

-- Straight wooden boardwalk between two deck points (stilts + planks + rails).
local function buildBoardwalk(model: Model, from: Vector3, to: Vector3, surfaceY: number, width: number?)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	if length < 4 then
		return
	end
	local w = width or 5.5
	local deckY = (from.Y + to.Y) * 0.5
	local mid = Vector3.new((from.X + to.X) * 0.5, deckY, (from.Z + to.Z) * 0.5)
	local yaw = math.atan2(flat.X, flat.Z)
	local cf = CFrame.new(mid) * CFrame.Angles(0, yaw, 0)

	makePart({
		Name = "BoardwalkDeck",
		Parent = model,
		Size = Vector3.new(w, 0.45, length),
		CFrame = cf,
		Color = DOCK_PLANK,
		Material = Enum.Material.WoodPlanks,
		CastShadow = true,
	})

	local pileBot = surfaceY - 6
	local pileH = deckY - 0.2 - pileBot
	local pileY = (deckY - 0.2 + pileBot) * 0.5
	local posts = math.max(2, math.floor(length / 10))
	for i = 0, posts do
		local along = -length * 0.5 + (i / posts) * length
		for _, sx in { -w * 0.5 + 0.55, w * 0.5 - 0.55 } do
			local p = cf * CFrame.new(sx, 0, along)
			makePart({
				Name = "BoardwalkPiling",
				Parent = model,
				Size = Vector3.new(0.75, pileH, 0.75),
				CFrame = CFrame.new(p.X, pileY, p.Z),
				Color = DOCK_POST,
				Material = Enum.Material.Wood,
			})
			makePart({
				Name = "BoardwalkRailPost",
				Parent = model,
				Size = Vector3.new(0.35, 2.1, 0.35),
				CFrame = cf * CFrame.new(sx, 1.2, along),
				Color = DOCK_POST,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
	end
	for _, sx in { -w * 0.5 + 0.55, w * 0.5 - 0.55 } do
		makePart({
			Name = "BoardwalkRail",
			Parent = model,
			Size = Vector3.new(0.3, 0.3, length),
			CFrame = cf * CFrame.new(sx, 2.2, 0),
			Color = DOCK_PLANK,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end
end

-- Removed with the terraced island style: buildRetainingRing laid a ring of wall segments
-- around a radius and buildSpiralPath wound a staircase around a circular cliff. Both were
-- literal circles in Parts, and the only island style that used them is gone.

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

-- Low-poly ground shelf: a few tilted rectangular facets keep clear walking space
-- while avoiding the old half-buried ball that made hills look like smooth domes.
local function buildDune(model: Model, topY: number, x: number, z: number, grass: boolean)
	local w = 8 + math.random() * 10
	local h = 1.6 + math.random() * 2.4
	local color = if grass then Color3.fromRGB(74, 138, 66) else Color3.fromRGB(224, 204, 160)
	local material = if grass then Enum.Material.Grass else Enum.Material.Sand
	for i = -1, 1 do
		makePart({
			Name = "GroundFacet",
			Parent = model,
			Size = Vector3.new(w * (0.52 + math.abs(i) * 0.12), h * 1.5, w * 0.42),
			CFrame = CFrame.new(x + i * w * 0.22, topY + h * 0.18, z + (i % 2) * w * 0.08)
				* CFrame.Angles(math.rad(i * 7), math.rad(i * 18), math.rad(-i * 9)),
			Color = color,
			Material = material,
			CanCollide = false,
			CastShadow = false,
		})
	end
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

	-- Placement now asks the island's own silhouette where the land is, instead of guessing
	-- with a polar radius and then excluding each landform with its own hand-written circle.
	-- That guessing is why props used to float over water: the exclusion list had to be kept
	-- in sync with the terrain by hand, and any new water feature was invisible to it.
	local feat = features or {}
	local shape = feat.shape

	local function blocked(x: number, z: number): boolean
		if not shape then
			return false
		end
		local dx, dz = x - center.X, z - center.Z
		-- Water of any kind (sea, lagoon, mouth, river, lake) and the landmark's own slopes,
		-- which get lava, snow and rock treatment rather than shrubbery.
		return not shape:isLand(dx, dz) or shape:onLandmark(dx, dz)
	end

	local function dryGroundY(x: number, z: number): number?
		if blocked(x, z) then
			return nil
		end
		-- Terrain raycast stays as the final authority: it also rejects anything that ended
		-- up over water because a prop pass ran before the terrain settled.
		return terrainSurfaceY(x, z, topY)
	end

	-- Pick a land point in a zone of the island, or nil if the zone has no room.
	local function landPoint(rand: () -> number, opts: { [string]: any }?): (number?, number?)
		if not shape then
			return nil, nil
		end
		local dx, dz = shape:randomLandPoint(rand, opts)
		if not dx then
			return nil, nil
		end
		return center.X + dx, center.Z + dz
	end

	-- Which flora suits this biome. Tropical isles get palms; temperate highlands and cold
	-- mountains get pines instead; volcanic + mountain isles also grow loot-y gem clusters.
	local hasPalms = biome ~= "highland" and biome ~= "mountain"
	local hasPines = biome == "highland" or biome == "mountain"
	local hasGems = biome == "volcanic" or biome == "mountain"
	local snowy = biome == "mountain"

	-- Density divisors keep the per-isle part count low: island area grows with the square
	-- of the radius, and a fast raft streams several isles' worth of props in at once.
	--
	-- Every pass below asks the shape for a point in a zone rather than picking a polar
	-- radius and hoping. `coast` is the beach and the low ground just behind it, `interior`
	-- is the body of the island, `shelf` is the settlement clearing. Points that land on
	-- water or on the landmark are rejected and retried, so density stays even on an
	-- irregular island instead of thinning out wherever the old fixed radius fell in the sea.
	local function scatter(key: string, count: number, opts: { [string]: any }, place: (number, number, number) -> ())
		if count <= 0 then
			return
		end
		local rand = randomStream(`{model.Name}_{key}`)
		for _ = 1, count do
			local x, z = landPoint(rand, opts)
			if x and z then
				local groundY = dryGroundY(x, z)
				if groundY then
					place(groundY, x, z)
				end
			end
		end
	end

	-- Palms crowd the beaches; jungle isles also carry them inland.
	if hasPalms then
		local palmCount = if biome == "beach" then math.floor(size / 32) else math.floor(size / 28)
		local inland = math.floor(palmCount * (if biome == "jungle" then 0.35 else 0.12))
		scatter("palms", palmCount - inland, { zone = "coast" }, function(y, x, z)
			buildPalm(model, y, x, z)
		end)
		scatter("palms_inland", inland, { zone = "interior", maxHeight = 26 }, function(y, x, z)
			buildPalm(model, y, x, z)
		end)
	end

	-- Conifer forest for highland / mountain isles.
	if hasPines then
		local pineCount = if biome == "mountain" then math.floor(size / 26) else math.floor(size / 22)
		scatter("pines", pineCount, { zone = "interior" }, function(y, x, z)
			buildPine(model, y, x, z, snowy)
		end)
	end

	-- Glowing emerald gem clusters (tropical volcanic + mountain isles).
	if hasGems then
		scatter("gems", math.clamp(math.floor(size / 90), 3, 14), { zone = "interior" }, function(y, x, z)
			buildGem(model, y, x, z)
		end)
	end

	scatter("bushes", math.floor(size / 22), { zone = "any", maxHeight = 40 }, function(y, x, z)
		buildBush(model, y, x, z, biome == "jungle")
	end)

	scatter("tufts", math.floor(size / 17), { zone = "any", maxHeight = 40 }, function(y, x, z)
		buildGrassTuft(model, y, x, z)
	end)

	-- Broadleaf trees for jungle / palm / volcanic isles (volcanic isles are lush tropical
	-- slopes around a bare cone).
	local leafy = biome == "jungle" or biome == "palm" or biome == "volcanic"
	if leafy then
		local treeCount = if biome == "jungle" then math.floor(size / 42) else math.floor(size / 60)
		scatter("trees", treeCount, { zone = "interior", maxHeight = 34 }, function(y, x, z)
			buildJungleTree(model, y, x, z)
		end)

		-- Amazon rainforest layer: buttressed canopy giants, thick ferns on the floor, and
		-- climbable vines on the high ground so the relief is scalable.
		local giantCount = if biome == "jungle" then math.floor(size / 120) else math.floor(size / 220)
		scatter("giants", giantCount, { zone = "interior", maxHeight = 26 }, function(y, x, z)
			buildGiantTree(model, y, x, z)
		end)

		local fernCount = if biome == "jungle" then math.floor(size / 18) else math.floor(size / 32)
		scatter("ferns", fernCount, { zone = "any", maxHeight = 46 }, function(y, x, z)
			buildFern(model, y, x, z)
		end)

		local vineRand = randomStream(`{model.Name}_vines`)
		scatter("vines", math.clamp(math.floor(size / 160), 2, 7), { zone = "interior" }, function(y, x, z)
			buildClimbVine(model, y, x, z, 24 + vineRand() * 18)
		end)
	end

	-- Rolling dunes and rock outcrops break up the open ground.
	local duneRand = randomStream(`{model.Name}_dune_grass`)
	scatter("dunes", math.floor(size / 64), { zone = "any", maxHeight = 30 }, function(y, x, z)
		buildDune(model, y, x, z, duneRand() < 0.6)
	end)

	scatter("rocks", math.floor(size / 96), { zone = "any" }, function(y, x, z)
		buildRock(model, y, x, z)
	end)

	-- Weathered driftwood logs washed up on the beaches.
	scatter("driftwood", math.clamp(math.floor(size / 70), 2, 6), { zone = "coast", maxHeight = 6 }, function(y, x, z)
		buildDriftwood(model, y, x, z)
	end)

	-- Scattered flowers for colour (shadowless, so nearly free). Tropical + temperate only.
	if biome ~= "mountain" then
		scatter("flowers", math.floor(size / 46), { zone = "any", maxHeight = 34 }, function(y, x, z)
			buildFlower(model, y, x, z)
		end)
	end
end

local function scatterLooseLoot(
	model: Model,
	center: Vector3,
	size: number,
	topY: number,
	islandId: string,
	features: { [string]: any }?
)
	local shape = features and features.shape
	local lootFolder = Instance.new("Folder")
	lootFolder.Name = "IsleLoot"
	lootFolder.Parent = model
	local rand = randomStream(`{islandId}_loose_loot`)

	-- Salvage has to be reachable, so it is placed on sampled land and sits on the real
	-- ground height. Fixed polar radii used to drop torches and crates into the lagoon.
	local function lootSpots(count: number, opts: { [string]: any }): { Vector3 }
		local spots: { Vector3 } = {}
		if not shape then
			return spots
		end
		for _ = 1, count do
			local dx, dz, height = shape:randomLandPoint(rand, opts)
			if dx then
				table.insert(spots, Vector3.new(center.X + dx, topY + (height or 0), center.Z + dz))
			end
		end
		return spots
	end

	-- Torches stuck in the sand / grass
	for _, spot in lootSpots(math.clamp(math.floor(size / 55), 2, 5), { zone = "interior", maxHeight = 30 }) do
		local torch = LootPropFactory.createTorchWorld(lootFolder, CFrame.new(spot + Vector3.new(0, 1.7, 0)))
		torch:SetAttribute("IslandId", islandId)
	end

	-- Salvage planks washed up along the beaches
	for _, spot in lootSpots(math.clamp(math.floor(size / 40), 3, 8), { zone = "coast", maxHeight = 8 }) do
		local cf = CFrame.new(spot + Vector3.new(0, 0.35, 0))
			* CFrame.Angles(0, rand() * math.pi * 2, math.rad((rand() - 0.5) * 8))
		local plank = LootPropFactory.createPlankWorld(lootFolder, cf)
		plank:SetAttribute("IslandId", islandId)
	end

	for _, spot in lootSpots(math.clamp(math.floor(size / 70), 1, 4), { zone = "interior", maxHeight = 24 }) do
		local crate = LootPropFactory.createCrateWorld(lootFolder, CFrame.new(spot + Vector3.new(0, 1.2, 0)))
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

-- Bring an island's people to life during world generation. Idempotent so retries and
-- future streaming passes cannot duplicate a settlement's residents.
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

-- The island body is sculpted from the shared silhouette by src/server/IslandTerrain.luau.
--
-- Three generators used to live here and all three are gone:
--   * fillFacetedRidge        tilted slabs meant to fake angular relief. Its FillBlock
--                            call referenced an undefined `sectionLength`, so it threw
--                            on every invocation inside its own protected call and fell
--                            back to FillBall: the "faceted" pass only ever drew spheres.
--   * generateIslandTerrain   concentric FillCylinder land columns plus FillBall relief.
--   * generateLagoonHubTerrain a hand-placed block lagoon, for the arrival isle only.
--
-- FillCylinder and FillBall are radially symmetric, so no amount of layering escaped the
-- round-island-with-a-dome silhouette. IslandRaster rasterises the shared height field
-- into merged axis-aligned boxes instead, which follows the sculpted coast exactly.

-- =====================================================================================
-- Signature landform effects + shoreline structures (docks, lighthouses, boats)
-- =====================================================================================

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
	table.insert(IslandService._dockColliders, {
		cframe = cf,
		size = Vector3.new(width, 0.5, length),
		islandName = (o.islandName :: string?) or "the dock",
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
	table.insert(IslandService._dockColliders, {
		cframe = headCf,
		size = Vector3.new(width + 7, 0.5, 6.5),
		islandName = (o.islandName :: string?) or "the dock",
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

-- Broad, readable walking trails tie the settlement, docks, riverbanks and signature
-- landmark together. The reference islands are dense, but never feel like random props:
-- every important place is connected by a visible path with shrubs and flowers along it.
local function buildScenicTrail(
	model: Model,
	center: Vector3,
	fromPos: Vector3,
	toPos: Vector3,
	topY: number,
	biome: string,
	seed: number,
	features: { [string]: any }?
)
	local delta = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	local distance = delta.Magnitude
	if distance < 12 then
		return
	end
	local direction = delta.Unit
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local segments = math.clamp(math.ceil(distance / 13), 3, 48)
	local rng = Random.new(seed)

	--[[
		Every slab follows the sculpted ground.

		These used to be written at a flat `topY + 0.2`, which worked only because the old
		generator flattened the whole interior of every island to one height. On sculpted
		relief a flat trail is buried on the rises and hangs in the air over the dips, and
		crosses open water without noticing. Each step now samples the height field, and
		segments over water are skipped so a path stops at the shore instead of bridging it.
	]]
	local shape = if features then features.shape else nil
	local function groundAt(x: number, z: number): number?
		if not shape then
			return topY
		end
		local height = shape:landHeight(x - center.X, z - center.Z)
		if not height then
			return nil
		end
		return topY + height
	end

	for i = 1, segments do
		local t = (i - 0.5) / segments
		local wander = math.sin(t * math.pi * 3 + seed * 0.01) * 3.2
		local pos = fromPos:Lerp(toPos, t) + side * wander
		local nextPos = pos + direction
		local groundY = groundAt(pos.X, pos.Z)
		local nextY = groundAt(nextPos.X, nextPos.Z)
		if not groundY or not nextY then
			continue
		end
		makePart({
			Name = "ScenicPath",
			Parent = model,
			Size = Vector3.new(9, 0.35, distance / segments + 1.5),
			-- lookAt across the real heights, so the slab tilts with the slope.
			CFrame = CFrame.lookAt(
				Vector3.new(pos.X, groundY + 0.2, pos.Z),
				Vector3.new(nextPos.X, nextY + 0.2, nextPos.Z)
			),
			Color = if biome == "volcanic" then Color3.fromRGB(82, 72, 65) else Color3.fromRGB(126, 106, 72),
			Material = if biome == "volcanic" then Enum.Material.Slate else Enum.Material.Ground,
			CanCollide = false,
			CastShadow = false,
		})
		-- Alternate planted edges so the trail reads clearly without becoming a wall.
		if i % 2 == 0 then
			local edge = if i % 4 == 0 then 1 else -1
			local plantPos = pos + side * edge * rng:NextNumber(6.5, 9)
			local plantY = groundAt(plantPos.X, plantPos.Z)
			if plantY then
				buildBush(model, plantY, plantPos.X, plantPos.Z, biome == "jungle")
				if i % 4 == 0 then
					local flowerY = groundAt(plantPos.X + side.X * 2, plantPos.Z + side.Z * 2)
					if flowerY then
						buildFlower(model, flowerY, plantPos.X + side.X * 2, plantPos.Z + side.Z * 2)
					end
				end
			end
		end
	end
end

local function buildIslandTrailNetwork(
	model: Model,
	center: Vector3,
	size: number,
	topY: number,
	biome: string,
	features: { [string]: any }
)
	local shape = features.shape
	local targets: { Vector3 } = {}

	-- Trails radiate from the settlement, not from the island's geometric centre — on an
	-- irregular island the centre is often a hillside, and on this one the village is
	-- deliberately off centre.
	local vx, vz = shape:villageCenter()
	local hub = Vector3.new(center.X + vx, topY, center.Z + vz)

	-- A path is only worth building if both ends are dry, so trails no longer run out
	-- across the lagoon toward a landmark on the far shore.
	local function addTarget(dx: number, dz: number, pull: number)
		local tx, tz = dx * pull, dz * pull
		if shape:isLand(tx, tz) then
			table.insert(targets, Vector3.new(center.X + tx, topY, center.Z + tz))
		end
	end

	for _, dock in features.docks do
		if dock.target == "sea" then
			local r = shape:coastRadius(dock.angle) - shape.beachWidth * 1.4
			addTarget(math.cos(dock.angle) * r, math.sin(dock.angle) * r, 1)
		end
	end
	local lm = shape.landmark
	if lm and (features.volcano or features.peak) then
		-- Stop at the foot of the cone rather than trying to pave up it.
		local reach = math.max(lm.distance - lm.baseR * 0.9, lm.distance * 0.35)
		addTarget(math.cos(lm.angle) * reach, math.sin(lm.angle) * reach, 1)
	end
	if shape.lake then
		addTarget(shape.lake.x, shape.lake.z, 0.72)
	end
	if shape.lagoon then
		addTarget(shape.lagoon.x, shape.lagoon.z, 0.55)
	end

	for i, target in targets do
		buildScenicTrail(model, center, hub, target, topY, biome, seedFromId(model.Name) + i * 97, features)
	end
end

-- Mountain hubs use the same cheerful skyline landmark as the NewHub reference.
local function buildHotAirBalloon(model: Model, position: Vector3, color: Color3, scale: number)
	local balloon = Instance.new("Model")
	balloon.Name = "HotAirBalloon"
	balloon.Parent = model
	local envelope = makePart({
		Name = "Envelope",
		Parent = balloon,
		Size = Vector3.new(18 * scale, 23 * scale, 18 * scale),
		CFrame = CFrame.new(position),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
		CastShadow = true,
	})
	makePart({
		Name = "EnvelopeBand",
		Parent = balloon,
		Size = Vector3.new(18.4 * scale, 3.2 * scale, 18.4 * scale),
		CFrame = envelope.CFrame,
		Color = Color3.fromRGB(248, 177, 48),
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
		CastShadow = false,
	})
	local basketPos = position - Vector3.new(0, 17 * scale, 0)
	makePart({
		Name = "Basket",
		Parent = balloon,
		Size = Vector3.new(5 * scale, 4 * scale, 5 * scale),
		CFrame = CFrame.new(basketPos),
		Color = Color3.fromRGB(105, 70, 38),
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
	})
	for _, x in { -2, 2 } do
		for _, z in { -2, 2 } do
			makePart({
				Name = "BalloonRope",
				Parent = balloon,
				Size = Vector3.new(0.22 * scale, 12 * scale, 0.22 * scale),
				CFrame = CFrame.new(position.X + x * scale, position.Y - 11 * scale, position.Z + z * scale),
				Color = Color3.fromRGB(65, 48, 32),
				Material = Enum.Material.Fabric,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
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
	entry: { [string]: any },
	shape: any
): { [string]: any }
	local rng = Random.new(seedFromId(id) * 3 + 17)
	local half = size * 0.5
	local features: { [string]: any } = { docks = {}, shape = shape }

	-- Landform positions are READ OFF THE SHAPE rather than invented here. The props pass
	-- and the terrain used to compute their own positions independently, which is how lava
	-- ended up beside a cone and piers ended up starting inland.
	local lm = shape.landmark
	if lm and lm.kind == "volcano" then
		features.volcano = {
			pos = Vector3.new(center.X + lm.x, center.Y, center.Z + lm.z),
			baseR = lm.baseR,
			height = lm.height,
			craterR = lm.craterR or lm.baseR * 0.17,
			craterDepth = lm.craterDepth or 0,
			angle = lm.angle,
		}
	elseif lm and lm.kind == "peak" then
		features.peak = {
			pos = Vector3.new(center.X + lm.x, topY, center.Z + lm.z),
			baseR = lm.baseR,
			height = lm.height,
			angle = lm.angle,
		}
	end

	local lake = shape.lake
	if lake then
		features.lake = {
			pos = Vector3.new(center.X + lake.x, topY, center.Z + lake.z),
			radius = lake.baseR,
			surfaceY = topY + lake.surface,
			bedY = topY + lake.bed,
			angle = lake.angle,
		}
	end

	local lagoon = shape.lagoon
	if lagoon then
		features.lagoon = {
			pos = Vector3.new(center.X + lagoon.x, topY, center.Z + lagoon.z),
			radius = lagoon.baseR,
			surfaceY = OceanConfig.SurfaceY,
			angle = lagoon.angle,
			mouthAngle = lagoon.mouthAngle,
		}
	end

	local river = shape.river
	if river then
		features.river = {
			angle = river.angle,
			width = river.width,
			length = river.length,
		}
	end

	-- Dock bearings, spread around the coast and nudged onto real beach by the shape so a
	-- pier never starts in the lagoon or off the end of a submerged arm.
	local dcount = tonumber(entry.Docks) or 0
	if dcount > 0 then
		local baseA = rng:NextNumber(0, math.pi * 2)
		if lm then
			baseA = lm.angle + math.pi -- harbour on the flank away from the high ground
		end
		if lagoon then
			baseA = lagoon.mouthAngle + math.pi -- face the sheltered water
		end
		for i = 1, dcount do
			local wanted = baseA + (i - 1) * (math.pi * 2 / dcount) * 0.55
			table.insert(features.docks, {
				angle = shape:shoreAngleNear(wanted, true),
				target = "sea",
			})
		end
		-- The first pier goes on the sheltered water where there is any: the lagoon for a
		-- harbour town, the lake on a mountain isle. It is placed on the shore facing the
		-- village so the settlement actually looks out over its own moorings.
		if lagoon then
			local vx, vz = shape:villageCenter()
			features.docks[1].target = "lagoon"
			features.docks[1].angle = math.atan2(vz - lagoon.z, vx - lagoon.x)
		end
		if features.lake then
			features.docks[1].target = "lake"
		end
	end

	if entry.Lighthouse == true then
		local wanted = if #features.docks > 0 then features.docks[1].angle + 0.5 else 0.8
		if features.docks[1] and features.docks[1].target == "lake" and #features.docks > 1 then
			wanted = features.docks[2].angle + 0.5
		end
		features.lighthouse = { angle = shape:shoreAngleNear(wanted, true) }
	end

	return features
end

-- =====================================================================================
-- Removed: the twin-peaks and tropical-terrace island styles
-- =====================================================================================
--
-- Neither style is referenced by Config.Islands.Catalog, and both built their land out
-- of the primitives this change exists to remove: generateTwinPeaksTerrain stacked
-- FillCylinder sand columns with FillBall reef knobs, and decorateTropicalTerrace ringed
-- the island with concentric stone walls and a spiral path. Every biome now goes through
-- the shared IslandShape silhouette, so a "two stacks" or "terraced" isle would be
-- authored as shape parameters rather than as a bespoke pile of discs.
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

	-- Volcano lava + smoke. The lava pool sits on the crater FLOOR, which the height field
	-- digs `craterDepth` below the summit — filling at the summit height left the pool
	-- hanging over the crater it was supposed to be inside.
	if features.volcano then
		local v = features.volcano
		buildLavaCrater(model, v.pos, v.craterR, topY + v.height - (v.craterDepth or 0), v.baseR, topY)
	end

	-- Mountain waterfall, dropping off the coastal cliff below the peak. Anchored to the
	-- real coast radius on that bearing so it lands in the sea instead of hanging in the
	-- air off a narrow flank (or starting inland on a broad one).
	local shape = features.shape
	if features.peak then
		local pk = features.peak
		-- Find a lip on the peak's flank that is high enough for the fall to read, rather
		-- than assuming the coast is 22 studs up: on a sculpted island the shore is barely
		-- above sea level, which left the waterfall starting in mid-air above the beach.
		local dropX, dropZ, dropY
		for _, frac in { 0.62, 0.70, 0.78, 0.86, 0.94 } do
			local r = shape:coastRadius(pk.angle) * frac
			local dx, dz = math.cos(pk.angle) * r, math.sin(pk.angle) * r
			local height = shape:landHeight(dx, dz)
			if height and height > 16 then
				dropX, dropZ, dropY = center.X + dx, center.Z + dz, topY + height
			end
		end
		if dropY then
			buildWaterfall(model, Vector3.new(dropX, dropY, dropZ), surfaceY)
		end
	end

	buildIslandTrailNetwork(model, center, size, topY, biome, features)

	if features.peak then
		local pk = features.peak
		buildHotAirBalloon(
			model,
			Vector3.new(center.X - math.cos(pk.angle) * half * 0.25, topY + pk.height * 0.92, center.Z - math.sin(pk.angle) * half * 0.25),
			Color3.fromRGB(220, 52, 32),
			0.85
		)
		buildHotAirBalloon(
			model,
			Vector3.new(center.X + math.sin(pk.angle) * half * 0.38, topY + pk.height * 0.66, center.Z - math.cos(pk.angle) * half * 0.38),
			Color3.fromRGB(232, 92, 30),
			0.68
		)
	end

	-- Docks / piers.
	for _, dock in features.docks do
		if (dock.target == "lake" and features.lake) or (dock.target == "lagoon" and features.lagoon) then
			local water = if dock.target == "lagoon" then features.lagoon else features.lake
			local toCenter = if dock.target == "lagoon"
				then dock.angle
				else math.atan2(center.Z - water.pos.Z, center.X - water.pos.X)
			buildDock(model, water.pos, water.surfaceY, toCenter, water.radius + 20, math.max(
				water.radius * 0.58,
				Config.StarterBase.SizeStuds * 0.5 + Config.Islands.RaftCollisionPad + 40
			), {
				islandId = islandId,
				deckY = water.surfaceY + 1.2,
				width = 6,
				rowboat = true,
			})
			-- A rowboat drifting within the protected harbor rather than outside at sea.
			local bx = water.pos.X + math.cos(toCenter + 1.2) * water.radius * 0.4
			local bz = water.pos.Z + math.sin(toCenter + 1.2) * water.radius * 0.4
			buildRowboat(model, CFrame.new(bx, water.surfaceY + 0.4, bz) * CFrame.Angles(0, toCenter, 0))
		else
			-- Piers are anchored to the coastline on their own bearing: they begin just
			-- inside the beach and reach clear of the shore. A fixed half * 0.8 start left
			-- piers buried inland where the coast bulges and floating in open water where
			-- it cuts in.
			local startR, endR = shape:dockSpan(dock.angle, Config.Islands.RaftCollisionPad + 30)
			buildDock(model, center, surfaceY, dock.angle, startR, endR, {
				islandId = islandId,
				rowboat = true,
			})
		end
	end

	-- Stilt huts standing out over the lagoon on a linked boardwalk, reaching from the
	-- settlement's shore. This is the postcard detail from the reference isle, and it only
	-- works now that the lagoon is a known body of water with a known shore.
	local lagoon = features.lagoon
	if lagoon and entry.Abandoned ~= true and (entry.Theme or "wild") ~= "wild" then
		local vx, vz = shape:villageCenter()
		local shoreAngle = math.atan2(vz - shape.lagoon.z, vx - shape.lagoon.x)
		local decks: { Vector3 } = {}
		for i, spread in { -0.42, 0, 0.4 } do
			local a = shoreAngle + spread
			-- Inside the rim, so the hut really does stand over water.
			local r = shape:lagoonRadius(a) * 0.74
			local pos = Vector3.new(lagoon.pos.X + math.cos(a) * r, 0, lagoon.pos.Z + math.sin(a) * r)
			decks[i] = buildStiltHut(model, pos, surfaceY, a, { scale = if i == 2 then 1.05 else 0.92 })
		end
		buildBoardwalk(model, decks[1], decks[2], surfaceY, 5.2)
		buildBoardwalk(model, decks[2], decks[3], surfaceY, 5.2)
		-- A spur back to dry land on the village side.
		local landR = shape:lagoonRadius(shoreAngle) + shape.beachWidth * 0.8
		buildBoardwalk(
			model,
			decks[2],
			Vector3.new(
				lagoon.pos.X + math.cos(shoreAngle) * landR,
				decks[2].Y,
				lagoon.pos.Z + math.sin(shoreAngle) * landR
			),
			surfaceY,
			5
		)
	end

	-- Lighthouse on the shore of medieval seaside isles, set back one beach width from the
	-- waterline on its bearing.
	if features.lighthouse then
		local a = features.lighthouse.angle
		local r = shape:coastRadius(a) - shape.beachWidth * 1.6
		local lx = center.X + math.cos(a) * r
		local lz = center.Z + math.sin(a) * r
		buildLighthouse(model, topY + (shape:landHeight(lx - center.X, lz - center.Z) or 0), lx, lz)
	end

	-- A beached shipwreck on abandoned isles (washed-up wreck to poke around in).
	if entry.Abandoned == true then
		local rand = randomStream(entry.Id .. "_wreck")
		local dx, dz, height = shape:randomLandPoint(rand, { zone = "coast", maxHeight = 6 })
		if dx then
			local yaw = math.atan2(dz, dx)
			-- Beached on the sand it was actually sampled from, not at a nominal topY.
			buildRowboat(
				model,
				CFrame.new(center.X + dx, topY + (height or 0) + 0.6, center.Z + dz) * CFrame.Angles(0, yaw, 0),
				true
			)
		end
	end
end

-- The fixed arrival isle needs a few hand-authored landmarks so the first view reads
-- as a real low-poly hub rather than another randomly populated destination. The
-- crossing stays high enough for a raft to pass beneath; it is a pedestrian landmark,
-- not a river blocker.
local function decorateArrivalHub(model: Model, center: Vector3, topY: number, features: { [string]: any })
	local shape = features.shape
	local river = features.river
	if not river then
		return
	end
	-- Span the channel where it is actually flowing. The course meanders, so a crossing
	-- placed on the island's centre line would end up on dry land or half in the water.
	local bridgeAlong = shape.half * 0.18
	local bridgeCentre, courseWidth = shape:riverCourse(bridgeAlong)
	local width = courseWidth
	local c, s = math.cos(river.angle), math.sin(river.angle)
	local bridgeX = center.X + bridgeAlong * c - bridgeCentre * s
	local bridgeZ = center.Z + bridgeAlong * s + bridgeCentre * c
	local bridgeYaw = math.atan2(c, s)
	local bridgeY = topY + 13
	local stone = Color3.fromRGB(112, 116, 108)
	local darkStone = Color3.fromRGB(72, 78, 74)

	-- Broad arched-looking deck across the channel, with its supports planted well
	-- beyond the navigable water. The wood rail inserts echo the harbour reference.
	local deckCf = CFrame.new(bridgeX, bridgeY, bridgeZ) * CFrame.Angles(0, bridgeYaw, 0)
	makePart({
		Name = "HubCrossingDeck",
		Parent = model,
		Size = Vector3.new(22, 2.4, width + 52),
		CFrame = deckCf,
		Color = stone,
		Material = Enum.Material.Cobblestone,
		CastShadow = true,
	})
	for _, z in { -(width * 0.5 + 16), width * 0.5 + 16 } do
		local abutment = deckCf * CFrame.new(0, 0, z)
		makePart({
			Name = "HubCrossingAbutment",
			Parent = model,
			Size = Vector3.new(18, bridgeY - OceanConfig.SurfaceY + 2, 14),
			CFrame = CFrame.new(abutment.X, (bridgeY + OceanConfig.SurfaceY - 2) * 0.5, abutment.Z)
				* CFrame.Angles(0, bridgeYaw, 0),
			Color = darkStone,
			Material = Enum.Material.Rock,
			CastShadow = true,
		})
	end
	for _, z in { -width * 0.34, width * 0.34 } do
		for _, x in { -9, 9 } do
			makePart({
				Name = "HubBridgeRail",
				Parent = model,
				Size = Vector3.new(1.1, 3.2, width * 0.26),
				CFrame = deckCf * CFrame.new(x, 2, z),
				Color = DOCK_POST,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
	end

	-- Skyline balloon over the island's landmark. The landmark itself is terrain now: a
	-- separate fan of ridges used to be carved here, which both duplicated the shape's
	-- landform and relied on the broken fillFacetedRidge helper.
	local lm = shape.landmark
	if lm then
		buildHotAirBalloon(
			model,
			Vector3.new(center.X + lm.x + 56, topY + lm.height * 0.95, center.Z + lm.z + 38),
			Color3.fromRGB(214, 60, 36),
			0.8
		)
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

	-- One source of truth for this island's geometry. The silhouette (coastline, lagoon,
	-- landmark, settlement clearing) is decided once here and then shared by the terrain
	-- sculptor, the prop passes, the village and raft collision — so nothing can disagree
	-- about where the land actually is.
	local shape = IslandTerrain.shapeFor(entry, topY)
	model:SetAttribute("CoastRadiusMax", shape.maxCoast)

	-- Signature landforms + shoreline layout, all read off the shape.
	local features = planIslandFeatures(entry.Id, center, topY, size, biome, entry, shape)

	-- Sculpt the island as voxel Terrain: irregular coast, sand beaches, grass/jungle
	-- interior, rock and snow uplands, the lagoon bed, the river channel and the submerged
	-- approach shelf. No FillCylinder discs and no FillBall domes are involved.
	IslandTerrain.sculpt(shape, center, topY)

	scatterVegetation(model, center, size, topY, biome, features)
	if (entry.Theme or "village") ~= "wild" then
		scatterSettlementForest(model, center, size, topY, features)
	end
	scatterLooseLoot(model, center, size, topY, entry.Id, features)

	-- Docks / piers, lighthouse, crater lava, waterfalls, moored + beached boats.
	decorateShore(model, center, size, topY, biome, entry, features)
	if entry.Hub == true then
		decorateArrivalHub(model, center, topY, features)
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
		safeHarbor = entry.SafeHarbor == true,
		shape = shape,
		-- Replayed whenever the ocean streamer refills the water chunks over this isle.
		submergedPlan = IslandTerrain.submergedPlan(shape, topY),
	}
	if features.river then
		local river = features.river
		local yaw = math.atan2(math.cos(river.angle), math.sin(river.angle))
		record.river = {
			cframe = CFrame.new(center.X, 0, center.Z) * CFrame.Angles(0, yaw, 0),
			width = river.width,
			length = river.length,
		}
	end

	local villagerCfg = entry.Villagers or { Passive = 0, Hostile = 0 }

	if theme == "wild" then
		-- No village — just a little scattered weapon loot on the wild isle, placed on
		-- sampled land. The radius here was `size * (0.2 .. 0.44)`, measured off the full
		-- diameter rather than the half-width, so a good share of every wild isle's loot
		-- was dropped straight into the sea.
		local rand = randomStream(`{entry.Id}_wild_loot`)
		local weaponCount = (entry.Loot and entry.Loot.Weapons) or 0
		for _ = 1, weaponCount do
			local dx, dz, height = shape:randomLandPoint(rand, { zone = "interior", maxHeight = 30 })
			if dx then
				local weaponId = Weapons.rollLootWeapon(function(lo, hi)
					return math.random(lo, hi)
				end)
				local cf = CFrame.new(center.X + dx, topY + (height or 0) + 0.5, center.Z + dz)
					* CFrame.Angles(0, rand() * math.pi * 2, 0)
				WeaponService.spawnWeaponPickup(model, weaponId, cf)
			end
		end
		-- A scrap of armor may wash up on wild isles too.
		local armorCount = (entry.Loot and entry.Loot.Armor) or 0
		for _ = 1, armorCount do
			local dx, dz, height = shape:randomLandPoint(rand, { zone = "interior", maxHeight = 30 })
			if dx then
				local armorId = Armor.rollLootArmor(function(lo, hi)
					return math.random(lo, hi)
				end)
				ArmorService.spawnArmorPickup(
					model,
					armorId,
					CFrame.new(center.X + dx, topY + (height or 0) + 0.5, center.Z + dz)
				)
			end
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
		-- The village stands on the shape's settlement clearing: the one patch of the
		-- island that is guaranteed to be dry, flat, off the landmark's slopes and clear
		-- of the lagoon. `buildableRadius` caps how far its streets may spread, so houses
		-- can no longer march off a headland or into the water.
		local vx, vz = shape:villageCenter()
		local settlementCenter = Vector3.new(center.X + vx, center.Y, center.Z + vz)
		local settlementTopY = topY + shape.shelfHeight
		deps.buildableRadius = shape.buildableRadius
		local layout = VillageBuilder.build(model, settlementCenter, size, settlementTopY, entry, deps)

		record.villagerPlan = {
			spots = layout.villagerSpots,
			passive = (villagerCfg.Passive or 0),
			hostile = (villagerCfg.Hostile or 0),
			abandoned = record.abandoned,
		}
		-- Populate immediately so the settlements are visibly alive from the spawn raft.
		populateIsland(record)

		-- The blue-hatted merchant (never hostile, draggable / weldable to your raft) is
		-- part of the scenery, so it's placed right away — trade is always available.
		if entry.Merchant == true then
			local m = layout.merchantSpot
			MerchantService.spawnMerchant(model, CFrame.new(m), entry.Id)
		end
	end

	return record
end

-- The opening ring is handcrafted, but the rest of the ocean is a deterministic grid of
-- tropical islands.  We generate a cell only as a crew gets close to it; that makes the
-- map genuinely endless without paying to create a continent at server boot.
local function endlessEntryForCell(cellX: number, cellZ: number): { [string]: any }
	local cfg = Config.Islands.Endless
	local id = `endless_{cellX}_{cellZ}`
	local rng = Random.new(seedFromId(id))
	local cell = cfg.CellStuds
	local origin = Config.StarterBase.Origin
	local jitter = cell * 0.12
	local centerX = origin.X + (cellX + 0.5) * cell + rng:NextNumber(-jitter, jitter)
	local centerZ = origin.Z + (cellZ + 0.5) * cell + rng:NextNumber(-jitter, jitter)
	local volcanic = rng:NextNumber() < 0.34
	return {
		Id = id,
		Name = if volcanic then "Emberwater Atoll" else "Verdant River Atoll",
		Offset = Vector3.new(centerX - origin.X, 0, centerZ - origin.Z),
		SizeStuds = rng:NextInteger(cfg.MinSizeStuds, cfg.MaxSizeStuds),
		Biome = if volcanic then "volcanic" else (if rng:NextNumber() < 0.56 then "jungle" else "palm"),
		Theme = "wild",
		Volcano = volcanic,
		River = true,
		RiverAngle = rng:NextNumber(0, math.pi * 2),
		RiverWidth = cfg.RiverWidth,
		Docks = 1,
		Loot = { Weapons = 2, Chests = 1, Armor = 1 },
		Villagers = { Passive = 0, Hostile = 0 },
	}
end

local function isEndlessCellClear(entry: { [string]: any }): boolean
	local center = worldCenterForOffset(entry.Offset, Config.Islands.TopY, Config.Islands.Thickness)
	local clearance = entry.SizeStuds * 0.5 + 780
	for _, isle in IslandService._islands do
		if flatDistance(center, isle.center) < clearance + isle.size * 0.5 then
			return false
		end
	end
	return true
end

local function buildQueuedEndlessIsland(entry: { [string]: any })
	local folder = IslandService._folder
	if not folder or IslandService._byId[entry.Id] then
		return
	end
	local record = buildFlatIsland(entry, folder)
	table.insert(IslandService._islands, record)
	IslandService._byId[record.id] = record

	-- The normal boot pass registers loot after all handcrafted islands are made. Dynamic
	-- islands need the same registration immediately so their salvage remains draggable.
	local LootPropService = require(script.Parent:WaitForChild("LootPropService"))
	for _, desc in record.model:GetDescendants() do
		if desc:IsA("Model") and desc:GetAttribute("IsLootProp") == true then
			LootPropService.registerExisting(desc)
		end
	end
	-- Only the island just built: the other islands' submerged footprints are untouched.
	IslandService.paintTerrain({ record.center })
end

local function queueEndlessIslandsNearRafts()
	local cfg = Config.Islands.Endless
	if cfg.Enabled ~= true or IslandService._endlessBuildActive then
		return
	end
	local origin = Config.StarterBase.Origin
	local cell = cfg.CellStuds
	local candidates: { { x: number, z: number, distance: number } } = {}
	local seen: { [string]: boolean } = {}
	for _, raft in StarterBaseService._basesByCode do
		local deck = raft.PrimaryPart or raft:FindFirstChild("Deck")
		if not (deck and deck:IsA("BasePart")) then
			continue
		end
		local cx = math.floor((deck.Position.X - origin.X) / cell)
		local cz = math.floor((deck.Position.Z - origin.Z) / cell)
		for dx = -cfg.BuildRadiusCells, cfg.BuildRadiusCells do
			for dz = -cfg.BuildRadiusCells, cfg.BuildRadiusCells do
				local x, z = cx + dx, cz + dz
				local key = `{x},{z}`
				if not seen[key] then
					seen[key] = true
					table.insert(candidates, { x = x, z = z, distance = dx * dx + dz * dz })
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	for _, candidate in candidates do
		local entry = endlessEntryForCell(candidate.x, candidate.z)
		if not IslandService._byId[entry.Id] and not IslandService._endlessQueued[entry.Id] and isEndlessCellClear(entry) then
			IslandService._endlessQueued[entry.Id] = true
			IslandService._endlessBuildActive = true
			task.spawn(function()
				local ok, err = pcall(buildQueuedEndlessIsland, entry)
				if not ok then
					warn(`[SurviveAtSea] Endless island {entry.Id} failed:`, err)
				end
				IslandService._endlessQueued[entry.Id] = nil
				IslandService._endlessBuildActive = false
			end)
			return
		end
	end
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

--[[
	Re-assert each island's SUBMERGED footprint.

	Island bodies are sculpted once in buildFlatIsland, but the ocean streamer fills whole
	256-stud chunks with water below sea level, so every time it refills a chunk over an
	island it erases the part of that island that sits under the waterline. This pass puts
	it back, and is only called when the water field actually changed.

	This used to be one `FillCylinder` per island of radius size/2 + 8. That squared the
	island's underwater footprint back into a disc, and — worse — filled the lagoon and the
	river channel with sand from 1.5 studs below the surface downward, turning them into
	shallow puddles. Replaying the island's real footprint keeps the sculpted shoreline,
	the lagoon bed and the approach shelf intact.
]]
function IslandService.paintTerrain(touchedPoints: { Vector3 }?)
	for _, isle in IslandService._islands do
		if not isle.submergedPlan then
			continue
		end
		-- Only islands the caller actually disturbed. The replay is ~100 small writes per
		-- island, so repainting all thirteen every time a raft crossed a chunk boundary
		-- was a periodic hitch for no benefit: the untouched islands were already correct.
		if touchedPoints then
			local reach = (isle.shape and isle.shape.maxCoast or isle.size * 0.5) + 200
			local nearby = false
			for _, point in touchedPoints do
				if flatDistance(point, isle.center) <= reach then
					nearby = true
					break
				end
			end
			if not nearby then
				continue
			end
		end
		IslandTerrain.repaintSubmerged(isle.submergedPlan, isle.center)
	end
end

function IslandService.isLockedForCrew(code: string, islandId: string): boolean
	local byIsle = IslandService._crewState[code]
	local state = byIsle and byIsle[islandId]
	return state ~= nil and state.locked == true
end

-- Returns true when the horizontal movement segment enters a circle. Checking the whole
-- segment (rather than only its destination) closes the gap a fast raft could otherwise
-- skip through during a slow server frame.
local function segmentHitsCircle(fromPos: Vector3, toPos: Vector3, center: Vector3, radius: number): boolean
	local start = Vector3.new(fromPos.X - center.X, 0, fromPos.Z - center.Z)
	if start.Magnitude <= radius then
		return true
	end
	local delta = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	local lengthSq = delta:Dot(delta)
	if lengthSq < 0.0001 then
		return false
	end
	local t = math.clamp(-start:Dot(delta) / lengthSq, 0, 1)
	return (start + delta * t).Magnitude <= radius
end

-- The raft moves as a kinematic model, so it needs a cheap 2D swept collision test for
-- dock decks too. Expand the oriented dock rectangle by the raft's collision padding,
-- then use a slab intersection against the attempted movement segment.
local function segmentHitsDock(fromPos: Vector3, toPos: Vector3, dock: DockCollider): boolean
	local start = dock.cframe:PointToObjectSpace(fromPos)
	local finish = dock.cframe:PointToObjectSpace(toPos)
	local delta = finish - start
	local pad = Config.Islands.RaftCollisionPad
	local halfX = dock.size.X * 0.5 + pad
	local halfZ = dock.size.Z * 0.5 + pad
	local enter, exit = 0, 1

	for _, axis in { "X", "Z" } do
		local origin = if axis == "X" then start.X else start.Z
		local direction = if axis == "X" then delta.X else delta.Z
		local half = if axis == "X" then halfX else halfZ
		if math.abs(direction) < 0.0001 then
			if math.abs(origin) > half then
				return false
			end
		else
			local near = (-half - origin) / direction
			local far = (half - origin) / direction
			if near > far then
				near, far = far, near
			end
			enter = math.max(enter, near)
			exit = math.min(exit, far)
			if enter > exit then
				return false
			end
		end
	end

	return exit >= 0 and enter <= 1
end

--[[
	Shoreline distance at a world position: how far outside this island's coast the point
	is, in studs (negative when it is over the island's own footprint).

	The coast is a function of bearing, so a single radius cannot describe it. Using
	size/2 for collision made every island behave like the disc it used to look like:
	rafts were stopped up to 150 studs out to sea off the narrow flanks, and the deep
	coves were unreachable.
]]
local function shoreClearance(isle: IslandRecord, x: number, z: number): number
	local dx, dz = x - isle.center.X, z - isle.center.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	local shape = isle.shape
	if not shape then
		return distance - isle.size * 0.5
	end
	local angle = math.atan2(dz, dx)
	-- Even when outside maxCoast, compute clearance on the actual bearing; maxCoast is a global max and can over-block narrow flanks.
	return distance - shape:coastRadius(angle)
end

-- Swept shoreline test. The segment is sampled rather than solved analytically because the
-- coastline is a harmonic function; sampling at ~1 raft-length intervals closes the gap a
-- fast raft could otherwise skip through on a slow server frame.
local function segmentHitsShore(fromPos: Vector3, toPos: Vector3, isle: IslandRecord, pad: number): boolean
	local dx, dz = toPos.X - fromPos.X, toPos.Z - fromPos.Z
	local travel = math.sqrt(dx * dx + dz * dz)
	local steps = math.clamp(math.ceil(travel / 12), 1, 48)
	for i = 0, steps do
		local t = i / steps
		if shoreClearance(isle, fromPos.X + dx * t, fromPos.Z + dz * t) <= pad then
			return true
		end
	end
	return false
end

-- Solid shoreline and dock collision. Rafts are watercraft: their complete footprint
-- stays outside every island envelope, without river/channel exceptions that can be
-- abused to cut through land at high speed.
function IslandService.collideRaft(fromPos: Vector3, toPos: Vector3): (Vector3, string?)
	local pad = Config.Islands.RaftCollisionPad
	for _, isle in IslandService._islands do
		-- Crews are placed inside the arrival island's sheltered water, so its shoreline
		-- guard is omitted; its real terrain banks still fence the raft in visually.
		if isle.safeHarbor then
			continue
		end
		if segmentHitsShore(fromPos, toPos, isle, pad) then
			return fromPos, isle.name
		end
	end

	for _, dock in IslandService._dockColliders do
		if segmentHitsDock(fromPos, toPos, dock) then
			return fromPos, dock.islandName
		end
	end

	return toPos, nil
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
	if pos.Y < isle.topY - 8 or pos.Y > isle.topY + 320 then
		return false
	end
	-- Follows the sculpted coast, so standing in a deep cove still counts as being ashore.
	return shoreClearance(isle, pos.X, pos.Z) <= 3
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
	if folder and folder:IsA("Folder") and #IslandService._islands >= #Config.Islands.Catalog then
		IslandService._folder = folder
		IslandService.paintTerrain()
		return folder
	end

	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = "DriveIslands"
		folder.Parent = lobbyRoot()
	end
	if IslandService._folder ~= folder then
		IslandService._folder = folder
		table.clear(IslandService._islands)
		table.clear(IslandService._byId)
		table.clear(IslandService._npcs)
		table.clear(IslandService._dockColliders)
		table.clear(IslandService._endlessQueued)
	end
	ensureOpeningPreviews(folder)

	local failures = {}
	for i, entry in Config.Islands.Catalog do
		if not IslandService._byId[entry.Id] then
			-- Clean up a model left half-built by an earlier attempt, then continue
			-- with every other catalog island even if this one has a bad feature.
			local partial = folder:FindFirstChild(`Isle_{entry.Id}`)
			if partial then
				partial:Destroy()
			end
			local ok, recordOrError = pcall(buildFlatIsland, entry, folder)
			if ok then
				local record = recordOrError :: IslandRecord
				table.insert(IslandService._islands, record)
				IslandService._byId[record.id] = record
				local previews = folder:FindFirstChild("OpeningPreviews")
				local preview = previews and previews:FindFirstChild(`Preview_{entry.Id}`)
				if preview then
					preview:Destroy()
				end
			else
				table.insert(failures, `{entry.Id}: {recordOrError}`)
				warn(`[SurviveAtSea] Island {entry.Id} failed; continuing with the remaining islands:`, recordOrError)
			end
		end
		-- These flats are huge (thousands of parts each). Yield between isles so a
		-- cold boot can't exhaust the script execution budget building them all at
		-- once. Successful islands remain in place if a later island needs a retry.
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
	if #failures > 0 then
		error(`{#failures} voyage island(s) still need retry: {table.concat(failures, " | ")}`)
	end
	print(`[SurviveAtSea] {#IslandService._islands} populated sculpted isles ready (irregular coasts, elevated ridges, beaches, jungle, villages/towns, loot, solid raft shorelines)`)
	return folder
end

function IslandService.start(
	toastRemote: RemoteEvent,
	getPartyCode: (Player) -> string?,
	getMemberUserIds: (string) -> { number }
)
	if IslandService._started or IslandService._starting then
		return
	end
	IslandService._starting = true
	IslandService._Toast = toastRemote
	IslandService._getPartyCode = getPartyCode
	IslandService._getMemberUserIds = getMemberUserIds

	-- Keep startup retryable.  A failed partial build must not leave the portal
	-- flow permanently waiting on an IslandService marked as started.
	local ok, err = pcall(IslandService.ensure)
	IslandService._starting = false
	if not ok then
		error(err)
	end
	IslandService._started = true

	-- The NPC AI pass is O(NPCs x players) and used to run every Heartbeat (60 Hz) even
	-- with nobody online. Run it on a fixed ~15 Hz tick, feeding it the accumulated dt so
	-- movement stays time-correct, and skip it entirely when no players are present.
	local npcAccum = 0
	local NPC_INTERVAL = 1 / 15
	local lockAccum = 0
	local endlessAccum = 0
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

		endlessAccum += dt
		if endlessAccum >= Config.Islands.Endless.PulseSeconds then
			endlessAccum = 0
			queueEndlessIslandsNearRafts()
		end
	end)
end

return IslandService
