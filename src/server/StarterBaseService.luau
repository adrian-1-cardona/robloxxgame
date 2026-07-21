-- One huge square wooden plank per crew — the Survive at Sea starter base.
-- Party size only gates who can join; it never changes the plank footprint.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local StarterBaseService = {}

StarterBaseService._basesByCode = {} :: { [string]: Folder }

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

function StarterBaseService.getBaseCenter(portalIndex: number): Vector3
	local cfg = Config.StarterBase
	local count = Config.PortalCount
	local offsetIndex = portalIndex - (count + 1) / 2
	return cfg.Origin + Vector3.new(offsetIndex * cfg.SpacingX, 0, 0)
end

function StarterBaseService.getSpawnCFrame(portalIndex: number, slotIndex: number?): CFrame
	local center = StarterBaseService.getBaseCenter(portalIndex)
	local y = center.Y + Config.StarterBase.Thickness / 2 + Config.StarterBase.DeckClearance
	local slot = slotIndex or 1
	-- Spread crew slightly so they don't stack on the same stud
	local offset = Vector3.new(((slot - 1) % 5) * 4 - 8, 0, math.floor((slot - 1) / 5) * 4 - 2)
	local pos = Vector3.new(center.X, y, center.Z) + offset
	return CFrame.new(pos, pos + Vector3.new(0, 0, -40))
end

function StarterBaseService.ensureBase(code: string, portalIndex: number, privacy: string): Folder
	local existing = StarterBaseService._basesByCode[code]
	if existing and existing.Parent then
		return existing
	end

	local size = Config.StarterBase.SizeStuds
	local thickness = Config.StarterBase.Thickness
	local center = StarterBaseService.getBaseCenter(portalIndex)

	local model = Instance.new("Folder")
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

	-- One huge square plank — the starter base itself
	makePart({
		Name = "Deck",
		Parent = model,
		Size = Vector3.new(size, thickness, size),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(118, 80, 48),
		Material = Enum.Material.WoodPlanks,
	})

	-- Subtle plank seams so it reads as timber, not a flat slab
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

	-- Low edge rails so the square reads as a platform
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

	-- Corner posts
	for _, corner in {
		Vector3.new(-half + 1.5, 0, -half + 1.5),
		Vector3.new(half - 1.5, 0, -half + 1.5),
		Vector3.new(-half + 1.5, 0, half - 1.5),
		Vector3.new(half - 1.5, 0, half - 1.5),
	} do
		makePart({
			Name = "CornerPost",
			Parent = model,
			Size = Vector3.new(2.4, 5, 2.4),
			CFrame = CFrame.new(center + corner + Vector3.new(0, thickness / 2 + 2.5, 0)),
			Color = Color3.fromRGB(78, 52, 30),
			Material = Enum.Material.Wood,
		})
	end

	-- World label (code lives in HUD top-right; this is a deck marker)
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
	gui.Size = UDim2.fromOffset(220, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Parent = marker

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(18, 36, 48)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Config.Theme.Foam
	label.Text = if privacy == "Private" then `BASE · {code} · PRIVATE` else `BASE · {code} · PUBLIC`
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	StarterBaseService._basesByCode[code] = model
	return model
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

function StarterBaseService.seatIfInParty(
	player: Player,
	lookup: (Player) -> ({ portalIndex: number, slotIndex: number }?)
)
	local info = lookup(player)
	if info then
		StarterBaseService.teleportPlayerToBase(player, info.portalIndex, info.slotIndex)
	else
		StarterBaseService.teleportPlayerToLobby(player)
	end
end

-- Keep Players referenced for future hooks / type clarity
local _ = Players

return StarterBaseService
