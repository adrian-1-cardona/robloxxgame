-- One huge square wooden plank per crew — the Survive at Sea starter base.
-- Party size only gates who can join; it never changes the plank footprint.
--
-- Bases are Models with PrimaryPart = Deck so they can be moved later
-- (sea drift / voyage travel) via setBaseCFrame without rebuilding.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

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

-- Move every BasePart in a model by the same delta (keeps relative layout).
local function shiftModel(model: Model, fromCFrame: CFrame, toCFrame: CFrame)
	local delta = toCFrame * fromCFrame:Inverse()
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CFrame = delta * desc.CFrame
		end
	end
end

-- baseSlot is an independent raft index — not tied to pier PortalCount.
function StarterBaseService.getBaseCenter(baseSlot: number): Vector3
	local cfg = Config.StarterBase
	-- Slot 1 at origin, then ±SpacingX for additional concurrent crews
	local offsetIndex = baseSlot - 1
	return cfg.Origin + Vector3.new(offsetIndex * cfg.SpacingX, 0, 0)
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
		StarterBaseService.refreshCodeLabel(code)
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

	-- Deck sits just above the ocean surface so it reads as mid-sea timber
	local deck = makePart({
		Name = "Deck",
		Parent = model,
		Size = Vector3.new(size, thickness, size),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(118, 80, 48),
		Material = Enum.Material.WoodPlanks,
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

	local seamColor = Color3.fromRGB(86, 58, 34)
	for i = -2, 2 do
		if i ~= 0 then
			makePart({
				Name = `SeamX_{i}`,
				Parent = model,
				Size = Vector3.new(0.6, thickness + 0.15, size - 4),
				CFrame = CFrame.new(center + Vector3.new(i * (size / 5), 0.05, 0)),
				Color = seamColor,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
			makePart({
				Name = `SeamZ_{i}`,
				Parent = model,
				Size = Vector3.new(size - 4, thickness + 0.15, 0.6),
				CFrame = CFrame.new(center + Vector3.new(0, 0.05, i * (size / 5))),
				Color = seamColor,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
	end

	local half = size / 2
	local railH = 2.2
	local railT = 1.2
	local railY = center.Y + thickness / 2 + railH / 2
	for _, spec in {
		{ Name = "RailNorth", CFrame = CFrame.new(center.X, railY, center.Z - half + railT / 2), Size = Vector3.new(size, railH, railT) },
		{ Name = "RailSouth", CFrame = CFrame.new(center.X, railY, center.Z + half - railT / 2), Size = Vector3.new(size, railH, railT) },
		{ Name = "RailWest", CFrame = CFrame.new(center.X - half + railT / 2, railY, center.Z), Size = Vector3.new(railT, railH, size - railT * 2) },
		{ Name = "RailEast", CFrame = CFrame.new(center.X + half - railT / 2, railY, center.Z), Size = Vector3.new(railT, railH, size - railT * 2) },
	} do
		makePart({
			Name = spec.Name,
			Parent = model,
			Size = spec.Size,
			CFrame = spec.CFrame,
			Color = Color3.fromRGB(92, 64, 42),
			Material = Enum.Material.Wood,
		})
	end

	for _, cornerOffset in {
		Vector3.new(-half + 1.5, 0, -half + 1.5),
		Vector3.new(half - 1.5, 0, -half + 1.5),
		Vector3.new(-half + 1.5, 0, half - 1.5),
		Vector3.new(half - 1.5, 0, half - 1.5),
	} do
		makePart({
			Name = "CornerPost",
			Parent = model,
			Size = Vector3.new(2.4, 5, 2.4),
			CFrame = CFrame.new(center + cornerOffset + Vector3.new(0, thickness / 2 + 2.5, 0)),
			Color = Color3.fromRGB(78, 52, 30),
			Material = Enum.Material.Wood,
		})
	end

	local marker = makePart({
		Name = "CodeMarker",
		Parent = model,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(center + Vector3.new(0, thickness / 2 + 8, -half + 6)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "BaseBillboard"
	gui.Adornee = marker
	gui.Size = UDim2.fromOffset(200, 48)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	gui.Parent = marker

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(18, 36, 48)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Config.Theme.Foam
	label.Text = `PRIVATE · {code}`
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

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

function StarterBaseService.refreshCodeLabel(code: string)
	local model = StarterBaseService._basesByCode[code]
	if not model then
		return
	end
	local privacyValue = model:FindFirstChild("Privacy")
	if privacyValue and privacyValue:IsA("StringValue") then
		privacyValue.Value = "Private"
	end
	local marker = model:FindFirstChild("CodeMarker")
	local gui = marker and marker:FindFirstChild("BaseBillboard")
	local label = gui and gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = `PRIVATE · {code}`
	end
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
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = StarterBaseService.getSpawnCFrame(baseSlot, slotIndex)
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

	RunService.Heartbeat:Connect(function()
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
