-- One huge open wooden platform per crew — the Survive at Sea starter base.
-- Party size only gates who can join; it never changes the plank footprint.
-- Deck is timber planks with no rails / walls — pure open raft.
--
-- Bases are Models with PrimaryPart = Deck so they can be moved later
-- (sea drift / voyage travel) via setBaseCFrame without rebuilding.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))
local IslandShape = require(Shared:WaitForChild("IslandShape"))

local RaftStarterKit = require(script.Parent:WaitForChild("RaftStarterKit"))

local StarterBaseService = {}

StarterBaseService._basesByCode = {} :: { [string]: Model }
-- Optional hook so HelmService can bind the wheel prompt when a base is built.
StarterBaseService._onBaseBuilt = nil :: ((string, Model) -> ())?
StarterBaseService._onBaseDestroyed = nil :: ((string) -> ())?

local function lobbyRoot(): Folder
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if root and root:IsA("Folder") then
		return root
	end
	return LobbyWorld.ensure()
end

local function basesFolder(): Folder
	local root = lobbyRoot()
	local folder = root:FindFirstChild("StarterBases")
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "StarterBases"
	folder.Parent = root
	return folder
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "BasePart"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.WoodPlanks
	p.Color = props.Color or Config.Theme.Driftwood
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	p.Parent = props.Parent
	return p
end

-- Pivot the assembled raft in one engine operation.  Moving every decorative plank,
-- wheel piece, and marker individually on every helm frame was needlessly expensive
-- once several crews were sailing at the same time.
local function shiftModel(model: Model, fromCFrame: CFrame, toCFrame: CFrame)
	-- The model pivot follows PrimaryPart (Deck), so this places the deck exactly at
	-- toCFrame while preserving all of the raft's local offsets.
	model:PivotTo(toCFrame)
end

--[[
	Where concurrent crew rafts berth.

	Rafts used to be laid out on a single line running +X from Config.StarterBase.Origin,
	which is also the centre of the arrival island. That forced the arrival island to keep
	480 studs of open water through its own middle: a moat, and the reason its lagoon could
	not be shaped like a real bay.

	They now sit in a compact grid inside that island's sheltered bay. The bay's position is
	derived from the same deterministic silhouette the terrain is built from, so this needs
	no coordinates of its own and cannot drift out of sync with the island.
]]
local berthAnchorCache: Vector3? = nil

local function berthAnchor(): Vector3
	if berthAnchorCache then
		return berthAnchorCache
	end
	local origin = Config.StarterBase.Origin
	local anchor = origin
	for _, entry in Config.Islands.Catalog do
		if entry.SafeHarbor == true then
			local shape = IslandShape.forEntry(entry, OceanConfig.SurfaceY - Config.Islands.TopY, {
				spawnBasinRadius = StarterBaseService.berthBasinRadius(),
			})
			local dx, dz = shape:berthAnchor()
			-- Catalog offsets are relative to the same origin, so the island's own offset
			-- has to be added back in.
			anchor = origin + Vector3.new(entry.Offset.X + dx, 0, entry.Offset.Z + dz)
			break
		end
	end
	berthAnchorCache = anchor
	return anchor
end

function StarterBaseService.berthBasinRadius(): number
	local cfg = Config.StarterBase
	return IslandShape.spawnBasinRadius(
		Config.Islands.BerthSlots,
		cfg.SpacingX,
		cfg.SlotsPerRow,
		cfg.SizeStuds,
		Config.Islands.RaftCollisionPad
	)
end

-- baseSlot is an independent raft index — not tied to pier PortalCount.
function StarterBaseService.getBaseCenter(baseSlot: number): Vector3
	local cfg = Config.StarterBase
	local anchor = berthAnchor()
	local offsets = IslandShape.berthGrid(Config.Islands.BerthSlots, cfg.SpacingX, cfg.SlotsPerRow)
	-- Extra crews beyond the reserved berths continue the grid outward rather than failing.
	local offset = offsets[baseSlot]
	if not offset then
		local columns = math.max(math.min(Config.Islands.BerthSlots, cfg.SlotsPerRow), 1)
		local baseRows = math.ceil(Config.Islands.BerthSlots / columns)
		local spanX = (columns - 1) * cfg.SpacingX
		local baseZ0 = -((baseRows - 1) * cfg.SpacingX) * 0.5
		local col = (baseSlot - 1) % columns
		local row = math.floor((baseSlot - 1) / columns)
		offset = { x = col * cfg.SpacingX - spanX * 0.5, z = baseZ0 + row * cfg.SpacingX }
	end
	return Vector3.new(anchor.X + offset.x, cfg.Origin.Y, anchor.Z + offset.z)
end

function StarterBaseService.getSpawnCFrame(baseSlot: number, slotIndex: number?): CFrame
	local center = StarterBaseService.getBaseCenter(baseSlot)
	local base = StarterBaseService._basesByCode
	-- If a live base exists for this slot, prefer its current deck position (supports future movement)
	for _, model in base do
		local slotValue = model:FindFirstChild("BaseSlot")
		local deck = model.PrimaryPart or model:FindFirstChild("Deck")
		if slotValue and slotValue:IsA("IntValue") and slotValue.Value == baseSlot and deck and deck:IsA("BasePart") then
			center = deck.Position
			break
		end
	end

	local y = center.Y + Config.StarterBase.Thickness / 2 + Config.StarterBase.DeckClearance
	local slot = slotIndex or 1
	local offset = Vector3.new(((slot - 1) % 5) * 4 - 8, 0, math.floor((slot - 1) / 5) * 4 - 2)
	local pos = Vector3.new(center.X, y, center.Z) + offset
	return CFrame.new(pos, pos + Vector3.new(0, 0, -40))
end

function StarterBaseService.ensureBase(code: string, baseSlot: number): Model
	local existing = StarterBaseService._basesByCode[code]
	if existing and existing.Parent then
		return existing
	end

	local size = Config.StarterBase.SizeStuds
	local thickness = Config.StarterBase.Thickness
	local center = StarterBaseService.getBaseCenter(baseSlot)

	local model = Instance.new("Model")
	model.Name = `StarterBase_{code}`
	model.Parent = basesFolder()

	local codeValue = Instance.new("StringValue")
	codeValue.Name = "PartyCode"
	codeValue.Value = code
	codeValue.Parent = model

	local slotValue = Instance.new("IntValue")
	slotValue.Name = "BaseSlot"
	slotValue.Value = baseSlot
	slotValue.Parent = model

	local privacyValue = Instance.new("StringValue")
	privacyValue.Name = "Privacy"
	privacyValue.Value = "Private"
	privacyValue.Parent = model

	-- Structural deck (collision) — a long, narrow deck so the crew actually sails on a ship.
	-- The broad berth rules still use SizeStuds, keeping spawn safety and island clearance stable.
	local deck = makePart({
		Name = "Deck",
		Parent = model,
		Size = Vector3.new(34, thickness, size),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(96, 64, 38),
		Material = Enum.Material.Wood,
	})
	model.PrimaryPart = deck

	-- Legacy local-sea markers (hidden). Real waves come from OceanTerrainService.
	-- Kept as large non-colliding parts so older clients / maps still have a sea hint.
	makePart({
		Name = "LocalSea",
		Parent = model,
		Size = Vector3.new(size + 420, 1.5, size + 420),
		CFrame = CFrame.new(center.X, OceanConfig.SurfaceY, center.Z),
		Color = OceanConfig.WaterColor,
		Material = Enum.Material.Glass,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	makePart({
		Name = "LocalSeaDeep",
		Parent = model,
		Size = Vector3.new(size + 900, 4, size + 900),
		CFrame = CFrame.new(center.X, OceanConfig.SurfaceY - OceanConfig.DepthStuds + 2, center.Z),
		Color = OceanConfig.AbyssColor,
		Material = Enum.Material.SmoothPlastic,
		Transparency = OceanConfig.AbyssTransparency,
		CanCollide = false,
		CastShadow = false,
	})

	-- Ship silhouette: the collision deck is intentionally simple, while a compact set of
	-- anchored hull pieces provides the readable vessel shape without physics overhead.
	local half = size / 2
	local deckTop = center.Y + thickness / 2
	local plankColors = {
		Color3.fromRGB(138, 96, 58),
		Color3.fromRGB(122, 82, 48),
		Color3.fromRGB(148, 104, 64),
		Color3.fromRGB(110, 74, 42),
		Color3.fromRGB(132, 90, 54),
		Color3.fromRGB(118, 78, 46),
	}
	local hullLength = size - 4
	local hullWidth = 32
	local plankW = 3.2
	local plankGap = 0.18
	local plankStep = plankW + plankGap
	local plankCount = math.max(1, math.floor((hullWidth - 1.5) / plankStep))
	local plankSpan = plankCount * plankStep - plankGap
	local plankStart = -plankSpan / 2 + plankW / 2
	for i = 0, plankCount - 1 do
		local tone = plankColors[(i % #plankColors) + 1]
		makePart({
			Name = `Plank_{i}`,
			Parent = model,
			Size = Vector3.new(plankW, 0.55, hullLength),
			CFrame = CFrame.new(center.X + plankStart + i * plankStep, deckTop + 0.22, center.Z),
			Color = tone,
			Material = Enum.Material.WoodPlanks,
			CanCollide = false,
		})
	end

	-- Cross-grain timber joists peeking between plank runs
	local joistColor = Color3.fromRGB(78, 50, 28)
	for j = -3, 3 do
		makePart({
			Name = `Joist_{j}`,
			Parent = model,
			Size = Vector3.new(hullWidth - 2, 0.35, 0.9),
			CFrame = CFrame.new(center.X, deckTop + 0.05, center.Z + j * (hullLength / 7)),
			Color = joistColor,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	-- Sloped side hull and pointed bow/stern make the vessel read from the waterline.
	local hullColor = Color3.fromRGB(72, 45, 27)
	for _, spec in {
		{ Name = "PortHull", CFrame = CFrame.new(center.X - 17, center.Y - 1.6, center.Z), Size = Vector3.new(2.2, 4.2, hullLength - 8), Angle = math.rad(-18) },
		{ Name = "StarboardHull", CFrame = CFrame.new(center.X + 17, center.Y - 1.6, center.Z), Size = Vector3.new(2.2, 4.2, hullLength - 8), Angle = math.rad(18) },
		{ Name = "Bow", CFrame = CFrame.new(center.X, center.Y - 0.5, center.Z - half + 1), Size = Vector3.new(18, 4.5, 9), Angle = 0 },
		{ Name = "Stern", CFrame = CFrame.new(center.X, center.Y - 0.3, center.Z + half - 3), Size = Vector3.new(28, 4.4, 7), Angle = 0 },
	} do
		makePart({
			Name = spec.Name,
			Parent = model,
			Size = spec.Size,
			CFrame = spec.CFrame * CFrame.Angles(0, 0, spec.Angle),
			Color = hullColor,
			Material = Enum.Material.Wood,
			CanCollide = true,
		})
	end

	-- Underside timber beams so the hull still reads as wood from the waterline
	local beamY = center.Y - thickness / 2 - 0.35
	for b = -1, 1 do
		makePart({
			Name = `KeelBeam_{b}`,
			Parent = model,
			Size = Vector3.new(1.6, 0.9, hullLength - 4),
			CFrame = CFrame.new(center.X + b * 9, beamY, center.Z),
			Color = Color3.fromRGB(72, 46, 26),
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	-- Rigging is deliberately static and part of the moving model.  Two masts, two sails,
	-- rails and stern lanterns give a strong ship silhouette without per-frame animation.
	local hub = Instance.new("Model")
	hub.Name = "ShipRigging"
	hub.Parent = model
	local postColor = Color3.fromRGB(76, 50, 29)
	local sailColor = Color3.fromRGB(225, 214, 180)
	for index, z in { -12, 12 } do
		local mast = makePart({
			Name = `Mast_{index}`,
				Parent = hub,
				Size = Vector3.new(1.5, 25, 1.5),
				CFrame = CFrame.new(center.X, deckTop + 12, center.Z + z),
				Color = postColor,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		makePart({
			Name = `Yard_{index}`,
			Parent = hub,
			Size = Vector3.new(22, 0.7, 0.7),
			CFrame = mast.CFrame * CFrame.new(0, 5, 0),
			Color = postColor,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		makePart({
			Name = `Sail_{index}`,
			Parent = hub,
			Size = Vector3.new(17, 10, 0.25),
			CFrame = mast.CFrame * CFrame.new(0, 0, 0.45),
			Color = sailColor,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CastShadow = false,
		})
	end
	for _, x in { -14, 14 } do
		makePart({
			Name = "RailPost",
			Parent = hub,
			Size = Vector3.new(0.6, 2.2, 0.6),
			CFrame = CFrame.new(center.X + x, deckTop + 1.2, center.Z),
			Color = postColor,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end
	makePart({
		Name = "PortRail",
		Parent = hub,
		Size = Vector3.new(0.5, 0.5, hullLength - 12),
		CFrame = CFrame.new(center.X - 15, deckTop + 2.1, center.Z),
		Color = postColor,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	makePart({
		Name = "StarboardRail",
		Parent = hub,
		Size = Vector3.new(0.5, 0.5, hullLength - 12),
		CFrame = CFrame.new(center.X + 15, deckTop + 2.1, center.Z),
		Color = postColor,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- Invisible spawn pad so deaths land on the raft (not the pier)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "RaftSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(center + Vector3.new(0, thickness / 2 + 0.6, 0))
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Parent = model

	-- Starter kit: vertical steering column + upright pirate wheel
	RaftStarterKit.attach(model, deck, center)

	StarterBaseService._basesByCode[code] = model
	if StarterBaseService._onBaseBuilt then
		StarterBaseService._onBaseBuilt(code, model)
	end
	return model
end

-- Future sea travel: move the whole plank (and its local water) as one unit.
function StarterBaseService.setBaseCFrame(code: string, newDeckCFrame: CFrame): boolean
	local model = StarterBaseService._basesByCode[code]
	if not model then
		return false
	end
	local deck = model.PrimaryPart or model:FindFirstChild("Deck")
	if not (deck and deck:IsA("BasePart")) then
		return false
	end
	shiftModel(model, deck.CFrame, newDeckCFrame)
	return true
end

function StarterBaseService.getBaseModel(code: string): Model?
	return StarterBaseService._basesByCode[code]
end

function StarterBaseService.destroyBase(code: string)
	local base = StarterBaseService._basesByCode[code]
	StarterBaseService._basesByCode[code] = nil
	if StarterBaseService._onBaseDestroyed then
		StarterBaseService._onBaseDestroyed(code)
	end
	if base then
		base:Destroy()
	end
end

function StarterBaseService.teleportPlayerToBase(player: Player, baseSlot: number, slotIndex: number)
	local character = player.Character
	if not character then
		return
	end
	local spawnCFrame = StarterBaseService.getSpawnCFrame(baseSlot, slotIndex)
	-- Pivoting the character model does not depend on HumanoidRootPart having
	-- replicated on this exact frame, so boarding cannot silently do nothing.
	character:PivotTo(spawnCFrame)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	-- Bind respawn to this raft so death returns here (for now)
	for _, model in StarterBaseService._basesByCode do
		local slotValue = model:FindFirstChild("BaseSlot")
		local raftSpawn = model:FindFirstChild("RaftSpawn")
		if slotValue and slotValue:IsA("IntValue") and slotValue.Value == baseSlot
			and raftSpawn and raftSpawn:IsA("SpawnLocation")
		then
			player.RespawnLocation = raftSpawn
			break
		end
	end
end

function StarterBaseService.clearRespawn(player: Player)
	player.RespawnLocation = nil
end

function StarterBaseService.teleportPlayerToLobby(player: Player)
	local character = player.Character
	if not character then
		return
	end
	StarterBaseService.clearRespawn(player)
	LobbyWorld.seatCharacter(character)
end

-- If a crewmate falls in the water, put them back on top of their raft.
local rescueDebounce: { [number]: boolean } = {}

function StarterBaseService.startWaterRescue(
	getSeatInfo: (Player) -> ({ baseSlot: number, slotIndex: number }?),
	shouldSkip: ((Player) -> boolean)?
)
	local RunService = game:GetService("RunService")
	local waterY = Config.StarterBase.WaterRescueY
	local rescueAccum = 0
	local RESCUE_INTERVAL = 0.25 -- Check 4 times per second instead of every frame

	RunService.Heartbeat:Connect(function(dt)
		rescueAccum += dt
		if rescueAccum < RESCUE_INTERVAL then
			return
		end
		rescueAccum = 0

		for _, player in Players:GetPlayers() do
			if rescueDebounce[player.UserId] then
				continue
			end
			if shouldSkip and shouldSkip(player) then
				continue
			end
			local seat = getSeatInfo(player)
			if not seat then
				continue
			end
			local character = player.Character
			if not character then
				continue
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if not (humanoid and root and root:IsA("BasePart")) then
				continue
			end
			if humanoid.Health <= 0 then
				continue
			end
			if root.Position.Y > waterY then
				continue
			end

			rescueDebounce[player.UserId] = true
			-- Kill horizontal velocity so they don't immediately slide off again
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			StarterBaseService.teleportPlayerToBase(player, seat.baseSlot, seat.slotIndex)
			task.delay(1.25, function()
				rescueDebounce[player.UserId] = nil
			end)
		end
	end)
end

return StarterBaseService
