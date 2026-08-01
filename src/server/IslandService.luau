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
	-- from the circular shore guard because crews begin inside that waterway.
	safeHarbor: boolean?,
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
local function buildBallTree(model: Model, topY: number, x: number, z: number, scale: number?)
	local s = scale or (0.85 + math.random() * 0.35)
	local trunkH = (7 + math.random() * 4) * s
	makePart({
		Name = "BallTrunk",
		Parent = model,
		Size = Vector3.new(0.7 * s, trunkH, 0.7 * s),
		CFrame = CFrame.new(x, topY + trunkH * 0.5, z),
		Color = Color3.fromRGB(78, 54, 32),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	local canopy = (4.5 + math.random() * 1.8) * s
	makePart({
		Name = "BallCanopy",
		Parent = model,
		Size = Vector3.new(canopy, canopy, canopy),
		CFrame = CFrame.new(x, topY + trunkH + canopy * 0.28, z),
		Color = Color3.fromRGB(34, 96, 46),
		Material = Enum.Material.Grass,
		CanCollide = false,
		Shape = Enum.PartType.Ball,
	})
end

-- Chunky broadleaf tree used as the common visual language around every settlement.
-- The separate, offset canopy blocks intentionally match the low-poly forest silhouette
-- from the island reference instead of reading as round Roblox "lollipop" trees.
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
	local half = size * 0.5
	local count = math.clamp(math.floor(size / 16), 64, 110)
	local river = features and features.river
	local lagoon = features and features.lagoon
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local r = half * (0.68 + math.random() * 0.22)
		local x = center.X + math.cos(a) * r
		local z = center.Z + math.sin(a) * r
		-- Keep the navigable waterway clear: floating forest props make a river feel
		-- broken and can block the raft even though the terrain channel is open.
		if river and not lagoon then
			local yaw = math.atan2(math.cos(river.angle), math.sin(river.angle))
			local localPos = (CFrame.new(center.X, 0, center.Z) * CFrame.Angles(0, yaw, 0))
				:PointToObjectSpace(Vector3.new(x, 0, z))
			if math.abs(localPos.X) < river.width * 0.5 + 14 then
				continue
			end
		end
		local groundY = terrainSurfaceY(x, z, topY)
		if not groundY then
			continue
		end
		if math.random() < 0.3 then
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

local function buildRetainingRing(
	model: Model,
	cx: number,
	cz: number,
	radius: number,
	yBottom: number,
	height: number
)
	local segs = math.max(18, math.floor(radius / 10))
	local chord = (2 * math.pi * radius) / segs + 0.6
	for i = 0, segs - 1 do
		local a = (i / segs) * math.pi * 2
		local x = cx + math.cos(a) * radius
		local z = cz + math.sin(a) * radius
		makePart({
			Name = "RetainingWall",
			Parent = model,
			Size = Vector3.new(chord, height, 1.4),
			CFrame = CFrame.new(x, yBottom + height * 0.5, z) * CFrame.Angles(0, -a, 0),
			Color = TERRACE_STONE,
			Material = Enum.Material.Concrete,
			CastShadow = true,
		})
	end
end

-- Spiral walkway climbing the central cliff.
local function buildSpiralPath(
	model: Model,
	cx: number,
	cz: number,
	cliffR: number,
	y0: number,
	y1: number
)
	local turns = 2.15
	local steps = 30
	for i = 0, steps - 1 do
		local t = i / steps
		local a = t * math.pi * 2 * turns
		local y = y0 + (y1 - y0) * t
		local r = cliffR + 7
		local x = cx + math.cos(a) * r
		local z = cz + math.sin(a) * r
		makePart({
			Name = "SpiralStep",
			Parent = model,
			Size = Vector3.new(8, 1.15, 5.2),
			CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, -a + math.rad(90), math.rad(-6)),
			Color = Color3.fromRGB(96, 98, 102),
			Material = Enum.Material.Rock,
			CastShadow = true,
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
	local half = size * 0.5
	local beachBand = half * 0.78 -- outer ring stays sandier; vegetation denser inward

	-- Feature exclusion: never scatter flora inside a lake, on top of a volcano cone, or
	-- on a mountain peak — those get their own treatment. Returns true if (x,z) is blocked.
	local feat = features or {}
	local function blocked(x: number, z: number): boolean
		local river = feat.river
		if river and not feat.lagoon then
			local yaw = math.atan2(math.cos(river.angle), math.sin(river.angle))
			local localPos = (CFrame.new(center.X, 0, center.Z) * CFrame.Angles(0, yaw, 0))
				:PointToObjectSpace(Vector3.new(x, 0, z))
			if math.abs(localPos.X) < river.width * 0.5 + 10 and math.abs(localPos.Z) < river.length * 0.5 + 8 then
				return true
			end
		end
		local lake = feat.lake
		if lake then
			local dx, dz = x - lake.pos.X, z - lake.pos.Z
			if dx * dx + dz * dz < (lake.radius + 6) * (lake.radius + 6) then
				return true
			end
		end
		local lagoon = feat.lagoon
		if lagoon then
			for _, cut in lagoon.cuts do
				local halfWidth = lagoon.width * cut[3] * 0.5 + 12
				local halfDepth = lagoon.depth * cut[4] * 0.5 + 12
				if math.abs(x - lagoon.pos.X - cut[1]) < halfWidth
					and math.abs(z - lagoon.pos.Z - cut[2]) < halfDepth
				then
					return true
				end
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
		local tt = feat.tropicalTerrace
		if tt then
			local dx, dz = x - tt.cx, z - tt.cz
			if dx * dx + dz * dz < (tt.cliffR + 10) * (tt.cliffR + 10) then
				return true
			end
		end
		return false
	end
	local function dryGroundY(x: number, z: number): number?
		if blocked(x, z) then
			return nil
		end
		return terrainSurfaceY(x, z, topY)
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
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildPalm(model, groundY, x, z)
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
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildPine(model, groundY, x, z, snowy)
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
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildGem(model, groundY, x, z)
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
		local groundY = dryGroundY(x, z)
		if not groundY then
			continue
		end
		buildBush(model, groundY, x, z, biome == "jungle")
	end

	local tuftCount = math.floor(size / 17)
	for _ = 1, tuftCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.65)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		local groundY = dryGroundY(x, z)
		if not groundY then
			continue
		end
		buildGrassTuft(model, groundY, x, z)
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
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildJungleTree(model, groundY, x, z)
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
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildGiantTree(model, groundY, x, z)
		end

		local fernCount = if biome == "jungle" then math.floor(size / 18) else math.floor(size / 32)
		for _ = 1, fernCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.15 + math.random() * 0.7)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildFern(model, groundY, x, z)
		end

		local vineCount = math.clamp(math.floor(size / 160), 2, 7)
		for _ = 1, vineCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.62 + math.random() * 0.28)
			local h = 24 + math.random() * 18
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildClimbVine(model, groundY, x, z, h)
		end
	end

	-- Rolling dunes across the interior — breaks up the flat with gentle rises
	local duneCount = math.floor(size / 64)
	for _ = 1, duneCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.2 + math.random() * 0.62)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		local groundY = dryGroundY(x, z)
		if not groundY then
			continue
		end
		buildDune(model, groundY, x, z, math.random() < 0.6)
	end

	-- Rock outcrops — a few inland, more clustered near the shoreline
	local rockCount = math.floor(size / 96)
	for _ = 1, rockCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.35 + math.random() * 0.55)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		local groundY = dryGroundY(x, z)
		if not groundY then
			continue
		end
		buildRock(model, groundY, x, z)
	end

	-- Weathered driftwood logs washed up along the beach ring
	local driftCount = math.clamp(math.floor(size / 70), 2, 6)
	for _ = 1, driftCount do
		local angle = math.random() * math.pi * 2
		local r = half * (0.72 + math.random() * 0.2)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r
		local groundY = dryGroundY(x, z)
		if groundY then
			buildDriftwood(model, groundY, x, z)
		end
	end

	-- Scattered flowers for colour (shadowless, so nearly free). Tropical + temperate only.
	if biome ~= "mountain" then
		local flowerCount = math.floor(size / 46)
		for _ = 1, flowerCount do
			local angle = math.random() * math.pi * 2
			local r = half * (0.18 + math.random() * 0.62)
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r
			local groundY = dryGroundY(x, z)
			if not groundY then
				continue
			end
			buildFlower(model, groundY, x, z)
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

-- Lay an angular ridge from low ground toward a raised spine. Tilted voxel slabs give
-- the shoreline and hills planar low-poly faces rather than the hemispherical silhouette
-- produced by stacking FillBall calls.
local function fillFacetedRidge(
	terrain: Terrain,
	origin: Vector3,
	yaw: number,
	length: number,
	width: number,
	rise: number,
	material: Enum.Material
)
	local segments = 5
	local segmentLength = length / segments
	for segment = 1, segments do
		local t0 = (segment - 1) / segments
		local t1 = segment / segments
		local t = (t0 + t1) * 0.5
		local distance = (t - 0.5) * length
		local sectionRise = rise * t
		local sectionWidth = width * (1 - t * 0.42)
		local thickness = math.max(10, width * (0.34 - t * 0.08))
		local pitch = -math.atan2(rise / segments, segmentLength)
		local center = Vector3.new(
			origin.X + math.cos(yaw) * distance,
			origin.Y + sectionRise - thickness * 0.38,
			origin.Z + math.sin(yaw) * distance
		)
		local ok = pcall(function()
		terrain:FillBlock(
			CFrame.new(center) * CFrame.Angles(0, -yaw + math.pi * 0.5, pitch),
			Vector3.new(sectionLength + 4, thickness, sectionWidth),
			material
		)
		end)
		if not ok then
			terrain:FillBall(center, math.max(sectionWidth * 0.34, 8), material)
		end
	end
end

-- Hand-authored arrival terrain: a single, asymmetric tropical landmass surrounding
-- a wide lagoon. Every landform is made of rotated blocks and planar ridges so the
-- opening world cannot regress to a circular atoll or smooth dome landscape.
local function generateLagoonHubTerrain(center: Vector3, topY: number, size: number, features: { [string]: any })
	local terrain = Workspace.Terrain
	local lagoon = features.lagoon
	if not lagoon then
		return
	end
	local surfaceY = OceanConfig.SurfaceY
	local baseBottom = surfaceY - 40
	local half = size * 0.5
	local grass = Enum.Material.LeafyGrass

	local function landTile(offsetX: number, offsetZ: number, width: number, depth: number, yawDegrees: number, height: number)
		local cf = CFrame.new(center.X + offsetX, 0, center.Z + offsetZ) * CFrame.Angles(0, math.rad(yawDegrees), 0)
		local fullHeight = height - baseBottom
		terrain:FillBlock(
			cf * CFrame.new(0, baseBottom + fullHeight * 0.5, 0),
			Vector3.new(width * 1.08, fullHeight, depth * 1.08),
			Enum.Material.Sand
		)
		terrain:FillBlock(
			cf * CFrame.new(0, height - 3, 0),
			Vector3.new(width, 6, depth),
			grass
		)
	end

	-- Overlapping skewed plates form one readable island outline with bays and headlands.
	for _, tile in {
		{ -405, -290, 560, 470, -14, topY + 4 },
		{ 225, -330, 620, 490, 9, topY + 8 },
		{ -445, 230, 540, 585, 17, topY + 5 },
		{ 260, 275, 655, 570, -11, topY + 9 },
		{ 0, 575, 850, 300, 4, topY + 6 },
		{ 0, -595, 820, 285, -3, topY + 8 },
	} do
		landTile(tile[1], tile[2], tile[3], tile[4], tile[5], tile[6])
	end

	-- Broken outer ridges give the coast a low-poly silhouette and forested slopes.
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2 + (i % 3 - 1) * 0.11
		local r = half * (0.59 + (i % 4) * 0.045)
		fillFacetedRidge(
			terrain,
			Vector3.new(center.X + math.cos(a) * r, topY, center.Z + math.sin(a) * r),
			a + math.pi + (i % 2) * 0.12,
			150 + (i % 3) * 28,
			68 + (i % 4) * 12,
			34 + (i % 5) * 9,
			if i % 3 == 0 then Enum.Material.Rock else grass
		)
	end

	-- The volcano is a fan of steep planar ridges, not stacked FillBall spheres.
	local volcano = features.volcano
	if volcano then
		for i = 1, 11 do
			local a = (i / 11) * math.pi * 2 + (i % 2) * 0.08
			local outer = Vector3.new(math.cos(a), 0, math.sin(a))
			local base = volcano.pos + outer * volcano.baseR * 0.58
			fillFacetedRidge(
				terrain,
				Vector3.new(base.X, topY + 4, base.Z),
				math.atan2(-outer.Z, -outer.X),
				volcano.baseR * (0.9 + (i % 3) * 0.06),
				volcano.baseR * (0.40 + (i % 2) * 0.06),
				volcano.height * (0.86 + (i % 4) * 0.035),
				if i % 3 == 0 then Enum.Material.Basalt else Enum.Material.Rock
			)
		end
		terrain:FillBlock(
			CFrame.new(volcano.pos.X, topY + volcano.height - 4, volcano.pos.Z) * CFrame.Angles(0, math.rad(18), 0),
			Vector3.new(volcano.craterR * 2.2, 18, volcano.craterR * 1.8),
			Enum.Material.Air
		)
	end

	-- Carve the central lagoon only after all land is placed, then refill at sea level.
	local clearTop = topY + 320
	local clearBottom = surfaceY - 48
	for _, cut in lagoon.cuts do
		local width = lagoon.width * cut[3]
		local depth = lagoon.depth * cut[4]
		local cf = CFrame.new(lagoon.pos.X + cut[1], 0, lagoon.pos.Z + cut[2]) * CFrame.Angles(0, math.rad(cut[5]), 0)
		terrain:FillBlock(
			cf * CFrame.new(0, (clearTop + clearBottom) * 0.5, 0),
			Vector3.new(width, clearTop - clearBottom, depth),
			Enum.Material.Air
		)
		terrain:FillBlock(
			cf * CFrame.new(0, (surfaceY + clearBottom) * 0.5, 0),
			Vector3.new(width - 7, surfaceY - clearBottom, depth - 7),
			Enum.Material.Water
		)
	end
end

-- Enhanced terrain generation with compact village foundations and faceted relief.
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

	-- The starting isle uses a handcrafted lagoon layout rather than the generic
	-- radial generator. Keep the special case entirely in gameplay terrain so the
	-- boarding lobby stays unchanged.
	if features.lagoon then
		generateLagoonHubTerrain(center, topY, size, features)
		return
	end

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

	-- Keep only a compact settlement core buildable. Everything beyond the town square
	-- is raised, sloped, or terraced so the silhouette matches the reference islands.
	if hasVillage then
		local villageFoundationRadius = half * (if isTown then 0.27 else 0.22)
		landColumn(cx, cz, villageFoundationRadius, topY + 0.5, grassMat)
	end

	-- 1) A submerged sand shelf supports an irregular grassy landmass. Sand remains a
	-- narrow waterline detail rather than becoming the visible island surface.
	landColumn(cx, cz, half * 0.68, surfaceY + 0.8, sandMat)
	landColumn(cx, cz, half * 0.52, topY + 2, grassMat)
	local lobes = rng:NextInteger(8, 12)
	for i = 1, lobes do
		local a = (i / lobes) * math.pi * 2 + rng:NextNumber(-0.55, 0.55)
		local dist = half * rng:NextNumber(0.24, 0.55)
		local lobeR = half * rng:NextNumber(0.18, 0.34)
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
		local lobeTop = topY + rng:NextNumber(5, 22)
		landColumn(cx + math.cos(a) * dist, cz + math.sin(a) * dist, lobeR, lobeTop, grassMat)
	end

	-- 2) A modest grass cap supports only the central streets. Angular ridge fans carry
	-- the terrain toward the forest without a giant flat disc or rounded dome.
	local capTop = topY + (if hasVillage then 0.2 else 0.3)
	local capBottom = topY - 3.5
	local capH = capTop - capBottom
	local capY = (capTop + capBottom) * 0.5
	local capRadius = if hasVillage then half * (if isTown then 0.30 else 0.25) else half * 0.28

	Terrain:FillCylinder(CFrame.new(cx, capY, cz), capH, capRadius, grassMat)

	local shoulderCount = if hasVillage then 20 else 16
	for i = 1, shoulderCount do
		local a = (i / shoulderCount) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local d = half * rng:NextNumber(0.28, 0.76)
		local r = half * rng:NextNumber(0.10, 0.18)
		local rise = rng:NextNumber(18, 54)
		local px = cx + math.cos(a) * d
		local pz = cz + math.sin(a) * d
		-- Overlapping tilted slabs create climbable planar slopes, broken ridgelines,
		-- and shallow valleys while keeping the low-poly silhouette from the references.
		fillFacetedRidge(
			Terrain,
			Vector3.new(px, topY - r * 0.12, pz),
			a + rng:NextNumber(-0.35, 0.35),
			r * rng:NextNumber(1.8, 2.7),
			r * rng:NextNumber(1.25, 1.8),
			rise,
			if biome == "jungle" then Enum.Material.LeafyGrass else grassMat
		)
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
	elseif features.tropicalTerrace then
		-- Stacked grassy terraces + a central rocky cliff (low-poly tropical look).
		local tt = features.tropicalTerrace
		landColumn(cx, cz, tt.midR, tt.midY, grassMat)
		landColumn(cx, cz, tt.topR, tt.topY, grassMat)
		local cliffSteps = 10
		for s = 0, cliffSteps do
			local t = s / cliffSteps
			local y = topY + (tt.cliffTop - topY) * t
			local r = tt.cliffR * (1 - t * 0.22)
			Terrain:FillBall(Vector3.new(cx, y, cz), math.max(r, 5), rockMat)
		end
		-- Flat grassy summit pad on the cliff.
		Terrain:FillCylinder(
			CFrame.new(cx, tt.cliffTop - 0.5, cz),
			3.5,
			tt.cliffR * 0.78,
			grassMat
		)
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

			fillFacetedRidge(
				Terrain,
				Vector3.new(hx, topY, hz),
				a + rng:NextNumber(-0.4, 0.4),
				baseR * 2.4,
				baseR * 1.8,
				peakExtra,
				hillRock
			)
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
				local angleDiff = math.abs(math.atan2(
					math.sin(a - dock.angle),
					math.cos(a - dock.angle)
				))
				if angleDiff < math.rad(45) then
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

	-- Every settlement gets a few broad, climbable hills around its outer woodland.
	-- They are deliberately kept beyond the street clearing so town paths remain usable.
	if hasVillage then
		for i = 1, 8 do
			local a = (i / 8) * math.pi * 2 + rng:NextNumber(-0.28, 0.28)
			local d = half * rng:NextNumber(0.58, 0.84)
			local radius = half * rng:NextNumber(0.09, 0.16)
			local rise = rng:NextNumber(20, 48)
			fillFacetedRidge(
				Terrain,
				Vector3.new(cx + math.cos(a) * d, topY, cz + math.sin(a) * d),
				a + rng:NextNumber(-0.3, 0.3),
				radius * 2.6,
				radius * 1.9,
				rise,
				if biome == "jungle" then Enum.Material.LeafyGrass else grassMat
			)
		end
	end

	-- Carve a navigable sea-level river after all landforms are placed. It runs from
	-- coast to coast, so a crew can enter the island, steer through it, and leave again.
	local river = features.river
	if river then
		local yaw = math.atan2(math.cos(river.angle), math.sin(river.angle))
		local riverCf = CFrame.new(cx, 0, cz) * CFrame.Angles(0, yaw, 0)
		local clearTop = math.max(topY + 90, surfaceY + 18)
		local clearBottom = surfaceY - 42
		Terrain:FillBlock(
			riverCf * CFrame.new(0, (clearTop + clearBottom) * 0.5, 0),
			Vector3.new(river.width, clearTop - clearBottom, river.length),
			Enum.Material.Air
		)
		Terrain:FillBlock(
			riverCf * CFrame.new(0, (surfaceY - 16) * 0.5, 0),
			Vector3.new(river.width - 5, surfaceY + 16, river.length + 12),
			Enum.Material.Water
		)

		-- Broken rock walls and raised grassy shoulders give the channel the wooded
		-- ravine profile from the reference. They remain outside the raft-safe width.
		local bankOffset = river.width * 0.5 + 18
		local segments = 18
		for i = 1, segments do
			local along = -river.length * 0.42 + (i - 1) * (river.length * 0.84 / (segments - 1))
			for _, side in { -1, 1 } do
				local jitter = rng:NextNumber(-8, 8)
				local localBank = Vector3.new(side * (bankOffset + jitter), topY + 2, along)
				local bank = riverCf:PointToWorldSpace(localBank)
				Terrain:FillBall(bank, rng:NextNumber(10, 18), Enum.Material.Rock)
				local shoulder = riverCf:PointToWorldSpace(
					Vector3.new(side * (bankOffset + 28), topY + rng:NextNumber(8, 18), along)
				)
				Terrain:FillBall(shoulder, rng:NextNumber(22, 38), grassMat)
			end
		end
	end
end

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
	fromPos: Vector3,
	toPos: Vector3,
	topY: number,
	biome: string,
	seed: number
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
	for i = 1, segments do
		local t = (i - 0.5) / segments
		local wander = math.sin(t * math.pi * 3 + seed * 0.01) * 3.2
		local pos = fromPos:Lerp(toPos, t) + side * wander
		local nextPos = pos + direction
		makePart({
			Name = "ScenicPath",
			Parent = model,
			Size = Vector3.new(9, 0.35, distance / segments + 1.5),
			CFrame = CFrame.lookAt(Vector3.new(pos.X, topY + 0.2, pos.Z), Vector3.new(nextPos.X, topY + 0.2, nextPos.Z)),
			Color = if biome == "volcanic" then Color3.fromRGB(82, 72, 65) else Color3.fromRGB(126, 106, 72),
			Material = if biome == "volcanic" then Enum.Material.Slate else Enum.Material.Ground,
			CanCollide = false,
			CastShadow = false,
		})
		-- Alternate planted edges so the trail reads clearly without becoming a wall.
		if i % 2 == 0 then
			local edge = if i % 4 == 0 then 1 else -1
			local plantPos = pos + side * edge * rng:NextNumber(6.5, 9)
			buildBush(model, topY, plantPos.X, plantPos.Z, biome == "jungle")
			if i % 4 == 0 then
				buildFlower(model, topY, plantPos.X + side.X * 2, plantPos.Z + side.Z * 2)
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
	local half = size * 0.5
	local targets = {}
	for _, dock in features.docks do
		if dock.target ~= "lake" then
			table.insert(targets, center + Vector3.new(math.cos(dock.angle) * half * 0.76, 0, math.sin(dock.angle) * half * 0.76))
		end
	end
	if features.volcano then
		local v = features.volcano
		table.insert(targets, center:Lerp(Vector3.new(v.pos.X, topY, v.pos.Z), 0.72))
	end
	if features.peak then
		local p = features.peak
		table.insert(targets, center:Lerp(Vector3.new(p.pos.X, topY, p.pos.Z), 0.62))
	end
	if features.lake then
		local lake = features.lake
		table.insert(targets, center:Lerp(Vector3.new(lake.pos.X, topY, lake.pos.Z), 0.82))
	end
	if features.river then
		table.insert(targets, center + Vector3.new(half * 0.42, 0, 0))
	end
	for i, target in targets do
		buildScenicTrail(model, center, target, topY, biome, seedFromId(model.Name) + i * 97)
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
	entry: { [string]: any }
): { [string]: any }
	local rng = Random.new(seedFromId(id) * 3 + 17)
	local half = size * 0.5
	local features: { [string]: any } = { docks = {} }

	if (biome == "volcanic" or entry.Volcano == true) and entry.Volcano ~= false then
		-- Arrival hubs can pin the cone to a hand-authored flank; all other volcanic
		-- isles retain their deterministic variation.
		local vAngle = math.pi * 1.5 + rng:NextNumber(-0.4, 0.4)
		local volcanoOffset = entry.VolcanoOffset
		local volcanoPos = if typeof(volcanoOffset) == "Vector3"
			then center + (volcanoOffset :: Vector3)
			else Vector3.new(center.X + math.cos(vAngle) * half * 0.5, center.Y, center.Z + math.sin(vAngle) * half * 0.5)
		features.volcano = {
			pos = volcanoPos,
			baseR = tonumber(entry.VolcanoBaseRadius) or half * 0.32,
			height = tonumber(entry.VolcanoHeight) or rng:NextNumber(135, 180),
			craterR = tonumber(entry.VolcanoCraterRadius) or half * 0.08,
			angle = vAngle,
		}
	end

	if entry.Lagoon == true then
		local lagoonOffset = entry.LagoonOffset
		features.lagoon = {
			pos = if typeof(lagoonOffset) == "Vector3" then center + (lagoonOffset :: Vector3) else center,
			width = tonumber(entry.LagoonWidth) or size * 0.5,
			depth = tonumber(entry.LagoonDepth) or size * 0.4,
			radius = math.min(tonumber(entry.LagoonWidth) or size * 0.5, tonumber(entry.LagoonDepth) or size * 0.4) * 0.42,
			surfaceY = OceanConfig.SurfaceY,
			-- Offset rectangular cuts deliberately create a natural, asymmetric harbour
			-- instead of a circular lake or a straight canal.
			cuts = {
				{ -80, -35, 0.72, 0.72, -8 },
				{ 205, 28, 0.42, 0.52, 13 },
				{ -232, 82, 0.34, 0.47, -18 },
				{ 48, -214, 0.48, 0.34, 9 },
			},
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

	-- Twin Peaks: two blocky rock stacks on separate sand pads with open water between.
	if biome == "twin_peaks" then
		local axis = rng:NextNumber(-0.25, 0.25)
		local sep = half * 0.3
		local padR = half * 0.22
		local rockFoot = padR * 0.78
		local rockH = math.clamp(size * 0.09, 88, 130)
		features.peaks = {
			{
				pos = Vector3.new(center.X - sep, center.Y, center.Z + sep * axis),
				padR = padR,
				padW = padR * 2.15,
				padD = padR * 1.85,
				rockFoot = rockFoot,
				rockH = rockH * rng:NextNumber(0.92, 1.05),
				angle = math.pi, -- outward (−X)
			},
			{
				pos = Vector3.new(center.X + sep, center.Y, center.Z - sep * axis),
				padR = padR * rng:NextNumber(0.92, 1.05),
				padW = padR * 2.05,
				padD = padR * 1.75,
				rockFoot = rockFoot * 0.92,
				rockH = rockH * rng:NextNumber(0.85, 0.98),
				angle = 0, -- outward (+X)
			},
		}
	end

	-- Low-poly tropical terrace isle (Palm Terrace): stacked grass rings, stone walls,
	-- spiral cliff, and stilt huts over the water on the harbour side.
	if entry.TropicalTerrace == true then
		features.tropicalTerrace = {
			cx = center.X,
			cz = center.Z,
			midR = half * 0.48,
			midY = topY + 9,
			topR = half * 0.26,
			topY = topY + 20,
			cliffR = half * 0.13,
			cliffTop = topY + 34,
		}
	end

	-- Large river islands have a sea-to-sea channel, wide enough for the starter raft.
	-- Keep this deterministic so the carved terrain and helm collision agree exactly.
	if entry.River == true then
		local angle = tonumber(entry.RiverAngle) or rng:NextNumber(0, math.pi * 2)
		features.river = {
			angle = angle,
			width = tonumber(entry.RiverWidth) or math.max(110, size * 0.07),
			length = size * 1.16,
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
		elseif features.peaks and features.peaks[1] then
			-- Twin Peaks: pier reaches out from the left sand pad into open water.
			baseA = features.peaks[1].angle
		elseif features.tropicalTerrace then
			-- Keep the pier on the +Z-ish harbour side so stilts cluster near it.
			baseA = math.pi * 0.5
		end
		for i = 1, dcount do
			local a = baseA + (i - 1) * (math.pi * 2 / dcount) * 0.55
			table.insert(features.docks, { angle = a, target = "sea" })
		end
		-- The arrival town's piers run from the south bank into the lagoon, not out
		-- through the outer coast. A small fan leaves room for boats to maneuver.
		if features.lagoon then
			for i, dock in features.docks do
				dock.target = "lagoon"
				dock.angle = math.pi * 0.5 + (i - (dcount + 1) * 0.5) * 0.34
			end
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

-- =====================================================================================
-- Twin Peaks biome — low-poly dual rock stacks on separate sand pads
-- (matches the postcard "two blocky isles + sagging span" look).
-- =====================================================================================

local TWIN_SAND = Color3.fromRGB(234, 226, 207)
local TWIN_ROCK = Color3.fromRGB(85, 85, 85)
local TWIN_ROCK_LIT = Color3.fromRGB(98, 98, 102)
local TWIN_LEAF = Color3.fromRGB(46, 139, 87)
local TWIN_LEAF_DARK = Color3.fromRGB(36, 118, 72)
local TWIN_TRUNK = Color3.fromRGB(92, 64, 38)

-- Clumpy low-poly canopy tree: thin trunk + clustered leaf balls (the "broccoli" tree).
local function buildClumpTree(model: Model, baseY: number, x: number, z: number, scale: number?)
	local s = scale or (0.9 + math.random() * 0.55)
	local trunkH = (9 + math.random() * 5) * s
	local trunkR = 1.15 * s
	-- Cylinder length is Size.X; rotate 90° about Z so the trunk stands upright.
	makePart({
		Name = "ClumpTrunk",
		Parent = model,
		Size = Vector3.new(trunkH, trunkR, trunkR),
		CFrame = CFrame.new(x, baseY + trunkH * 0.5, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = TWIN_TRUNK,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	local canopyY = baseY + trunkH
	local blobs = {
		{ 0, 0, 5.5 },
		{ 2.2, 1.0, 4.2 },
		{ -2.0, 0.6, 4.0 },
		{ 0.4, 2.4, 3.6 },
		{ -1.2, -1.6, 3.8 },
	}
	for i, b in blobs do
		local r = b[3] * s
		makePart({
			Name = `ClumpLeaf_{i}`,
			Parent = model,
			Size = Vector3.new(r, r, r),
			CFrame = CFrame.new(x + b[1] * s, canopyY + b[2] * s, z + (i % 2 == 0 and 0.6 or -0.4) * s),
			Color = if i % 2 == 0 then TWIN_LEAF else TWIN_LEAF_DARK,
			Material = Enum.Material.Grass,
			CanCollide = false,
			CastShadow = i == 1,
			Shape = Enum.PartType.Ball,
		})
	end
end

-- Stacked rectangular rock mass — stair-step / jagged low-poly cliff like the reference.
local function buildBlockyRockStack(
	model: Model,
	rng: Random,
	baseCenter: Vector3,
	baseY: number,
	footprint: number,
	height: number,
	side: number
): Vector3
	-- Returns the top plateau center for trees and lookout props.
	local tiers = rng:NextInteger(6, 8)
	local topPos = baseCenter + Vector3.new(0, height, 0)
	for t = 0, tiers - 1 do
		local frac = t / (tiers - 1)
		local y0 = baseY + height * (t / tiers)
		local y1 = baseY + height * ((t + 1) / tiers)
		local midY = (y0 + y1) * 0.5
		local tierH = math.max(y1 - y0, 4)
		-- Shrink + offset each tier for the stair-step silhouette.
		local w = footprint * (1 - frac * 0.62) * rng:NextNumber(0.88, 1.06)
		local d = footprint * (1 - frac * 0.58) * rng:NextNumber(0.82, 1.04)
		local ox = side * footprint * 0.04 * (1 - frac) + rng:NextNumber(-w * 0.06, w * 0.06)
		local oz = rng:NextNumber(-d * 0.08, d * 0.08)
		local col = if t % 2 == 0 then TWIN_ROCK else TWIN_ROCK_LIT
		makePart({
			Name = `RockTier_{t}`,
			Parent = model,
			Size = Vector3.new(w, tierH + 0.4, d),
			CFrame = CFrame.new(baseCenter.X + ox, midY, baseCenter.Z + oz)
				* CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0),
			Color = col,
			Material = Enum.Material.Slate,
			CanCollide = true,
			CastShadow = true,
		})
		-- Extra jutting blocks for a jagged, modular read.
		local juts = rng:NextInteger(1, 3)
		for j = 1, juts do
			local jw = w * rng:NextNumber(0.28, 0.48)
			local jh = tierH * rng:NextNumber(0.55, 1.1)
			local jd = d * rng:NextNumber(0.28, 0.45)
			local ja = rng:NextNumber(0, math.pi * 2)
			local jr = (math.min(w, d) * 0.42) * rng:NextNumber(0.7, 1.05)
			makePart({
				Name = `RockJut_{t}_{j}`,
				Parent = model,
				Size = Vector3.new(jw, jh, jd),
				CFrame = CFrame.new(
					baseCenter.X + ox + math.cos(ja) * jr,
					midY + rng:NextNumber(-tierH * 0.15, tierH * 0.2),
					baseCenter.Z + oz + math.sin(ja) * jr
				) * CFrame.Angles(0, ja, 0),
				Color = col,
				Material = Enum.Material.Slate,
				CanCollide = true,
				CastShadow = false,
			})
		end
		if t == tiers - 1 then
			topPos = Vector3.new(baseCenter.X + ox, y1, baseCenter.Z + oz)
		end
	end

	-- Climbable vine/truss on the outer face so players can reach the lookout.
	local climbH = height * 0.92
	local truss = Instance.new("TrussPart")
	truss.Name = "PeakClimb"
	truss.Anchored = true
	truss.CanCollide = true
	truss.Color = Color3.fromRGB(64, 88, 42)
	truss.Material = Enum.Material.Grass
	truss.Size = Vector3.new(2, climbH, 2)
	truss.CFrame = CFrame.new(baseCenter.X + side * footprint * 0.42, baseY + climbH * 0.5, baseCenter.Z)
	truss.CastShadow = false
	truss.Parent = model

	return topPos
end

-- Flat sandy rectangular pad (the pale base under each rock stack in the reference).
local function buildSandPad(model: Model, center: Vector3, topY: number, width: number, depth: number)
	makePart({
		Name = "SandPad",
		Parent = model,
		Size = Vector3.new(width, 3.2, depth),
		CFrame = CFrame.new(center.X, topY - 0.4, center.Z),
		Color = TWIN_SAND,
		Material = Enum.Material.Sand,
		CanCollide = true,
		CastShadow = true,
	})
	-- Slightly larger submerged shelf so the pad reads as rising from the sea.
	makePart({
		Name = "SandShelf",
		Parent = model,
		Size = Vector3.new(width * 1.08, 2.4, depth * 1.08),
		CFrame = CFrame.new(center.X, topY - 2.6, center.Z),
		Color = Color3.fromRGB(214, 204, 178),
		Material = Enum.Material.Sand,
		CanCollide = true,
		CastShadow = false,
	})
end

-- Terrain under twin peaks: two sandy columns + a thin shoal between them (raft collision
-- still uses the enclosing SizeStuds circle from paintTerrain).
local function generateTwinPeaksTerrain(
	id: string,
	center: Vector3,
	topY: number,
	size: number,
	features: { [string]: any }
)
	local Terrain = Workspace.Terrain
	local rng = Random.new(seedFromId(id))
	local half = size * 0.5
	local surfaceY = OceanConfig.SurfaceY
	local sandMat = Enum.Material.Sand
	local baseBottom = surfaceY - 40

	local peaks = features.peaks
	if not peaks then
		return
	end

	local function sandColumn(px: number, pz: number, radius: number)
		local h = topY - baseBottom
		Terrain:FillCylinder(CFrame.new(px, (topY + baseBottom) * 0.5, pz), h, radius, sandMat)
	end

	for _, peak in peaks do
		sandColumn(peak.pos.X, peak.pos.Z, peak.padR * 0.72)
		-- Soft irregular lobes around each pad.
		for _ = 1, 3 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = peak.padR * rng:NextNumber(0.15, 0.4)
			sandColumn(peak.pos.X + math.cos(a) * d, peak.pos.Z + math.sin(a) * d, peak.padR * rng:NextNumber(0.28, 0.42))
		end
	end

	-- Thin submerged shoal through the open-water gap.
	if #peaks >= 2 then
		local a, b = peaks[1].pos, peaks[2].pos
		local mid = (a + b) * 0.5
		local span = (Vector3.new(a.X - b.X, 0, a.Z - b.Z)).Magnitude
		local yaw = math.atan2(b.X - a.X, b.Z - a.Z)
		Terrain:FillBlock(
			CFrame.new(mid.X, (topY - 1 + baseBottom) * 0.5, mid.Z) * CFrame.Angles(0, yaw, 0),
			Vector3.new(half * 0.1, topY - 1 - baseBottom, math.max(span * 0.45, 40)),
			sandMat
		)
	end

	-- A few reef knobs off the coast.
	for _ = 1, rng:NextInteger(3, 5) do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = half * rng:NextNumber(0.88, 1.02)
		Terrain:FillBall(
			Vector3.new(center.X + math.cos(a) * d, surfaceY - 0.5, center.Z + math.sin(a) * d),
			rng:NextNumber(3, 7),
			Enum.Material.Rock
		)
	end
end

-- Parts pass: sand pads, blocky rock stacks, clump trees, and palms.
local function decorateTwinPeaks(
	model: Model,
	center: Vector3,
	topY: number,
	size: number,
	features: { [string]: any }
)
	local rng = Random.new(seedFromId((model:GetAttribute("IslandId") :: string?) or "twin") * 5 + 11)
	local peaks = features.peaks
	if not peaks or #peaks < 2 then
		return
	end

	local tops: { Vector3 } = {}
	for i, peak in peaks do
		local side = if i == 1 then -1 else 1
		buildSandPad(model, peak.pos, topY, peak.padW, peak.padD)
		local top = buildBlockyRockStack(model, rng, peak.pos, topY, peak.rockFoot, peak.rockH, side)
		table.insert(tops, top)

		-- Clumpy canopy trees on the upper plateaus.
		local treeCount = rng:NextInteger(3, 5)
		for t = 1, treeCount do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = peak.rockFoot * rng:NextNumber(0.05, 0.22)
			buildClumpTree(model, top.Y, top.X + math.cos(a) * r, top.Z + math.sin(a) * r, rng:NextNumber(0.85, 1.25))
		end

		-- Palm trees on the sandy pad (around the rock foot).
		local palmCount = rng:NextInteger(4, 7)
		for _ = 1, palmCount do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = peak.padR * rng:NextNumber(0.55, 0.92)
			local px = peak.pos.X + math.cos(a) * r
			local pz = peak.pos.Z + math.sin(a) * r
			-- Keep palms off the rock footprint.
			if (Vector3.new(px - peak.pos.X, 0, pz - peak.pos.Z)).Magnitude > peak.rockFoot * 0.48 then
				buildPalm(model, topY, px, pz, rng:NextNumber(0.8, 1.15))
			end
		end
	end

	-- Keep the water gap between summits completely open; traversal is by boat.

	-- A couple of shoreline rocks for scale.
	local half = size * 0.5
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = half * rng:NextNumber(0.72, 0.92)
		buildRock(model, topY, center.X + math.cos(a) * r, center.Z + math.sin(a) * r, rng:NextNumber(1.2, 2.2))
	end
end

-- Decorative + structural pass run after terrain + vegetation: crater lava, waterfalls,
-- docks/piers, a lighthouse, moored + beached boats. Everything here is Parts parented to
-- the island model (terrain is already sculpted). Positions come from planIslandFeatures.
local function decorateTropicalTerrace(
	model: Model,
	size: number,
	topY: number,
	surfaceY: number,
	features: { [string]: any }
)
	local tt = features.tropicalTerrace
	if not tt then
		return
	end
	local half = size * 0.5
	local cx, cz = tt.cx, tt.cz

	-- Stone retaining walls at each grassy terrace rim.
	buildRetainingRing(model, cx, cz, tt.midR + 1.2, topY - 0.5, tt.midY - topY + 1.2)
	buildRetainingRing(model, cx, cz, tt.topR + 1.0, tt.midY - 0.5, tt.topY - tt.midY + 1.0)

	-- Spiral path up the central cliff to the summit pad.
	buildSpiralPath(model, cx, cz, tt.cliffR, tt.topY + 1, tt.cliffTop - 1)

	-- Short stair ramps from beach → mid terrace and mid → upper (harbour-facing).
	local harbourA = if #features.docks > 0 then features.docks[1].angle else math.pi * 0.5
	for _, ramp in {
		{ r0 = half * 0.72, r1 = tt.midR - 4, y0 = topY + 0.4, y1 = tt.midY + 0.4, w = 10 },
		{ r0 = tt.midR - 2, r1 = tt.topR - 3, y0 = tt.midY + 0.4, y1 = tt.topY + 0.4, w = 8 },
	} do
		local steps = 8
		for i = 0, steps - 1 do
			local t = i / steps
			local r = ramp.r0 + (ramp.r1 - ramp.r0) * t
			local y = ramp.y0 + (ramp.y1 - ramp.y0) * t
			local x = cx + math.cos(harbourA) * r
			local z = cz + math.sin(harbourA) * r
			makePart({
				Name = "TerraceStep",
				Parent = model,
				Size = Vector3.new(ramp.w, 1.1, 5.5),
				CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, -harbourA + math.rad(90), 0),
				Color = TERRACE_STONE,
				Material = Enum.Material.Concrete,
				CastShadow = true,
			})
		end
	end

	-- Ball-on-stick trees in neat rows along the grassy terrace edges.
	for _, ring in {
		{ r = tt.midR - 8, y = tt.midY, count = 14, scale = 1.05 },
		{ r = tt.topR - 6, y = tt.topY, count = 8, scale = 0.9 },
	} do
		for i = 0, ring.count - 1 do
			local a = (i / ring.count) * math.pi * 2 + 0.15
			-- Leave a gap at the harbour stair.
			local delta = math.abs(((a - harbourA + math.pi) % (math.pi * 2)) - math.pi)
			if delta > 0.35 then
				buildBallTree(model, ring.y, cx + math.cos(a) * ring.r, cz + math.sin(a) * ring.r, ring.scale)
			end
		end
	end

	-- Three stilt huts over the water near the pier, linked by boardwalks.
	local hutAngles = { harbourA - 0.7, harbourA - 0.28, harbourA + 0.22 }
	local hutRadii = { half * 1.06, half * 1.1, half * 1.05 }
	local hutDecks = {}
	for i, a in hutAngles do
		local r = hutRadii[i]
		local pos = Vector3.new(cx + math.cos(a) * r, 0, cz + math.sin(a) * r)
		local scale = if i == 2 then 1.05 else 0.92
		hutDecks[i] = buildStiltHut(model, pos, surfaceY, a + math.pi, { scale = scale })
	end
	-- Boardwalks: hut ↔ hut, and a spur from the middle hut toward the beach.
	buildBoardwalk(model, hutDecks[1], hutDecks[2], surfaceY, 5.2)
	buildBoardwalk(model, hutDecks[2], hutDecks[3], surfaceY, 5.2)
	local shore = Vector3.new(
		cx + math.cos(harbourA - 0.28) * half * 0.86,
		hutDecks[2].Y,
		cz + math.sin(harbourA - 0.28) * half * 0.86
	)
	buildBoardwalk(model, hutDecks[2], shore, surfaceY, 5.0)

	-- Larger pavilion on the cliff summit.
	buildStiltHut(
		model,
		Vector3.new(cx, tt.cliffTop + 0.4, cz),
		surfaceY,
		harbourA,
		{ scale = 1.35, overLand = true }
	)
end

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
			local startR = half * 0.8
			-- Twin Peaks: pier starts at the outer edge of a sand pad, not mid-channel.
			if biome == "twin_peaks" and features.peaks and #features.peaks > 0 then
				local peak = features.peaks[1]
				local peakDist = flatDistance(peak.pos, center)
				startR = peakDist + peak.padR * 0.82
			end
			local endR = half + Config.Islands.RaftCollisionPad + 30
			buildDock(model, center, surfaceY, dock.angle, startR, endR, {
				islandId = islandId,
				rowboat = true,
			})
		end
	end

	-- Low-poly tropical terrace props (stilts, walls, spiral, ball trees).
	if features.tropicalTerrace then
		decorateTropicalTerrace(model, size, topY, surfaceY, features)
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

-- The fixed arrival isle needs a few hand-authored landmarks so the first view reads
-- as a real low-poly hub rather than another randomly populated destination. The
-- crossing stays high enough for a raft to pass beneath; it is a pedestrian landmark,
-- not a river blocker.
local function decorateArrivalHub(model: Model, center: Vector3, topY: number, features: { [string]: any })
	-- Emberlagoon has its own dock fan and asymmetric harbor; do not layer the
	-- legacy river bridge/peak set across it.
	if features.lagoon then
		return
	end
	local river = features.river
	if not river then
		return
	end
	local width = river.width
	local bridgeX = center.X + 120
	local bridgeY = topY + 13
	local stone = Color3.fromRGB(112, 116, 108)
	local darkStone = Color3.fromRGB(72, 78, 74)

	-- Broad arched-looking deck across the channel, with its supports planted well
	-- beyond the navigable water. The wood rail inserts echo the harbour reference.
	makePart({
		Name = "HubCrossingDeck",
		Parent = model,
		Size = Vector3.new(22, 2.4, width + 52),
		CFrame = CFrame.new(bridgeX, bridgeY, center.Z),
		Color = stone,
		Material = Enum.Material.Cobblestone,
		CastShadow = true,
	})
	for _, z in { -(width * 0.5 + 16), width * 0.5 + 16 } do
		makePart({
			Name = "HubCrossingAbutment",
			Parent = model,
			Size = Vector3.new(18, bridgeY - OceanConfig.SurfaceY + 2, 14),
			CFrame = CFrame.new(bridgeX, (bridgeY + OceanConfig.SurfaceY - 2) * 0.5, center.Z + z),
			Color = darkStone,
			Material = Enum.Material.Rock,
			CastShadow = true,
		})
	end
	for _, z in { -width * 0.34, width * 0.34 } do
		makePart({
			Name = "HubBridgeRail",
			Parent = model,
			Size = Vector3.new(1.1, 3.2, width * 0.26),
			CFrame = CFrame.new(bridgeX - 9, bridgeY + 2, center.Z + z),
			Color = DOCK_POST,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		makePart({
			Name = "HubBridgeRail",
			Parent = model,
			Size = Vector3.new(1.1, 3.2, width * 0.26),
			CFrame = CFrame.new(bridgeX + 9, bridgeY + 2, center.Z + z),
			Color = DOCK_POST,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	-- A rocky rainforest peak on the northern bank supplies the unmistakable skyline
	-- from the hub reference without covering the river spawn or settlement paths.
	local peak = Vector3.new(center.X - 300, topY, center.Z - width * 0.5 - 150)
	for ridge = 1, 8 do
		local angle = (ridge / 8) * math.pi * 2
		local length = 185 + (ridge % 3) * 14
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		fillFacetedRidge(
			Workspace.Terrain,
			peak + outward * (length * 0.5),
			angle + math.pi,
			length,
			58 + (ridge % 2) * 14,
			175 + (ridge % 3) * 12,
			if ridge % 3 == 0 then Enum.Material.LeafyGrass else Enum.Material.Rock
		)
	end
	buildHotAirBalloon(model, peak + Vector3.new(56, 170, 38), Color3.fromRGB(214, 60, 36), 0.8)
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
	-- and the decorative pass agree on exact positions (volcano, lake, docks, lighthouse,
	-- twin-peak pads).
	local features = planIslandFeatures(entry.Id, center, topY, size, biome, entry)

	if biome == "twin_peaks" then
		-- Low-poly dual stacks: sand pads + blocky rocks + clump trees.
		-- Skip the organic disc / scatter vegetation so the gap between peaks stays open sea.
		generateTwinPeaksTerrain(entry.Id, center, topY, size, features)
		decorateTwinPeaks(model, center, topY, size, features)
	else
		-- Carve the organic, biome-specific terrain island (beaches, grass/jungle/highland
		-- interior, hills, rocky peaks, volcanic cones, snow peaks + lakes). Seeded per isle
		-- so every island's shape is different.
		generateIslandTerrain(entry.Id, center, topY, size, biome, entry.Theme or "wild", features)
		scatterVegetation(model, center, size, topY, biome, features)
		-- Settlement woodland belongs only on the normal terrain isles. Twin Peaks keeps
		-- its open-water gap clear for sailing.
		if (entry.Theme or "village") ~= "wild" then
			scatterSettlementForest(model, center, size, topY, features)
		end
	end
	scatterLooseLoot(model, center, size, topY, entry.Id)

	-- Docks / piers, lighthouse, crater lava, waterfalls, moored + beached boats.
	decorateShore(model, center, size, topY, biome, entry, features)
	if entry.Hub == true then
		decorateArrivalHub(model, center, topY, features)
	end

	local marker = makePart({
		Name = "IsleMarker",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center.X, topY + (if biome == "twin_peaks" then 140 else 18), center.Z),
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
		local settlementOffset = entry.SettlementOffset
		local settlementCenter = if typeof(settlementOffset) == "Vector3"
			then center + (settlementOffset :: Vector3)
			else center
		local settlementTopY = topY + (tonumber(entry.SettlementTopYOffset) or 0)
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
	IslandService.paintTerrain()
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
		-- The arrival world has its own irregular block-built sand shelf. Repainting
		-- it as a cylinder would recreate the circular-atoll silhouette we removed.
		if isle.safeHarbor then
			continue
		end
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

-- Solid shoreline and dock collision. Rafts are watercraft: their complete footprint
-- stays outside every island envelope, without river/channel exceptions that can be
-- abused to cut through land at high speed.
function IslandService.collideRaft(fromPos: Vector3, toPos: Vector3): (Vector3, string?)
	for _, isle in IslandService._islands do
		-- Crews are initially placed inside Rivergate's carved central channel. The
		-- hub's real terrain banks still provide visual boundaries; omit only its
		-- broad circular guard so the raft can leave the starting waterway.
		if isle.safeHarbor then
			continue
		end
		local minDist = isle.size * 0.5 + Config.Islands.RaftCollisionPad
		if segmentHitsCircle(fromPos, toPos, isle.center, minDist) then
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
