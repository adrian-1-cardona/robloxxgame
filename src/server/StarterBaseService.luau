-- One huge square wooden plank per crew — the Survive at Sea starter base.
-- Party size only gates who can join; it never changes the plank footprint.
--
-- Bases are Models with PrimaryPart = Deck so they can be moved later
-- (sea drift / voyage travel) via setBaseCFrame without rebuilding.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local StarterBaseService = {}

StarterBaseService._basesByCode = {} :: { [string]: Model }

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

function StarterBaseService.getBaseCenter(portalIndex: number): Vector3
	local cfg = Config.StarterBase
	local count = Config.PortalCount
	local offsetIndex = portalIndex - (count + 1) / 2
	return cfg.Origin + Vector3.new(offsetIndex * cfg.SpacingX, 0, 0)
end

function StarterBaseService.getSpawnCFrame(portalIndex: number, slotIndex: number?): CFrame
	local center = StarterBaseService.getBaseCenter(portalIndex)
	local base = StarterBaseService._basesByCode
	-- If a live base exists for this portal, prefer its current deck position (supports future movement)
	for _, model in base do
		local portalValue = model:FindFirstChild("PortalIndex")
		local deck = model.PrimaryPart or model:FindFirstChild("Deck")
		if portalValue and portalValue:IsA("IntValue") and portalValue.Value == portalIndex and deck and deck:IsA("BasePart") then
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

function StarterBaseService.ensureBase(code: string, portalIndex: number, privacy: string): Model
	local existing = StarterBaseService._basesByCode[code]
	if existing and existing.Parent then
		StarterBaseService.refreshPrivacyLabel(code, privacy)
		return existing
	end

	local size = Config.StarterBase.SizeStuds
	local thickness = Config.StarterBase.Thickness
	local center = StarterBaseService.getBaseCenter(portalIndex)

	local model = Instance.new("Model")
	model.Name = `StarterBase_{code}`
	model.Parent = basesFolder()

	local codeValue = Instance.new("StringValue")
	codeValue.Name = "PartyCode"
	codeValue.Value = code
	codeValue.Parent = model

	local portalValue = Instance.new("IntValue")
	portalValue.Name = "PortalIndex"
	portalValue.Value = portalIndex
	portalValue.Parent = model

	local privacyValue = Instance.new("StringValue")
	privacyValue.Name = "Privacy"
	privacyValue.Value = privacy
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

	-- Local water ring so the base always feels surrounded by ocean
	makePart({
		Name = "LocalSea",
		Parent = model,
		Size = Vector3.new(size + 180, 1.5, size + 180),
		CFrame = CFrame.new(center.X, 0.35, center.Z),
		Color = Color3.fromRGB(22, 118, 150),
		Material = Enum.Material.Glass,
		Transparency = 0.32,
		CanCollide = false,
		CastShadow = false,
	})
	makePart({
		Name = "LocalSeaDeep",
		Parent = model,
		Size = Vector3.new(size + 180, 24, size + 180),
		CFrame = CFrame.new(center.X, -12, center.Z),
		Color = Color3.fromRGB(6, 48, 82),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.08,
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
	label.Text = if privacy == "Private" then `PRIVATE · {code}` else `PUBLIC · {code}`
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	StarterBaseService._basesByCode[code] = model
	return model
end

function StarterBaseService.refreshPrivacyLabel(code: string, privacy: string)
	local model = StarterBaseService._basesByCode[code]
	if not model then
		return
	end
	local privacyValue = model:FindFirstChild("Privacy")
	if privacyValue and privacyValue:IsA("StringValue") then
		privacyValue.Value = privacy
	end
	local marker = model:FindFirstChild("CodeMarker")
	local gui = marker and marker:FindFirstChild("BaseBillboard")
	local label = gui and gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = if privacy == "Private" then `PRIVATE · {code}` else `PUBLIC · {code}`
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
	if base then
		base:Destroy()
	end
end

function StarterBaseService.teleportPlayerToBase(player: Player, portalIndex: number, slotIndex: number)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = StarterBaseService.getSpawnCFrame(portalIndex, slotIndex)
	end
end

function StarterBaseService.teleportPlayerToLobby(player: Player)
	local character = player.Character
	if not character then
		return
	end
	LobbyWorld.seatCharacter(character)
end

local _ = Players

return StarterBaseService
