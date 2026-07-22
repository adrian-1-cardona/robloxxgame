-- Tiny flat drive-to isle near the open-sea raft spawn.
-- Part geometry for collision / look; Terrain sand carve so water doesn't swallow it.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local IslandService = {}

IslandService._model = nil :: Model?
IslandService._center = nil :: Vector3?
IslandService._size = nil :: number?
IslandService._topY = nil :: number?
IslandService._thickness = nil :: number?

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
	p.Parent = props.Parent
	return p
end

function IslandService.getWorldCenter(): Vector3
	local cfg = Config.DriveIsland
	local origin = Config.StarterBase.Origin
	return Vector3.new(
		origin.X + cfg.OffsetFromOrigin.X,
		cfg.TopY - cfg.Thickness * 0.5,
		origin.Z + cfg.OffsetFromOrigin.Z
	)
end

-- AABB the ocean streamer should paint as sand (keeps water from refilling over the isle).
function IslandService.getCarveBounds(): (Vector3, Vector3)?
	if not (IslandService._center and IslandService._size and IslandService._thickness and IslandService._topY) then
		return nil
	end
	local size = IslandService._size
	local thickness = IslandService._thickness
	-- Slightly oversized so chunk water edges don't peek through
	local pad = 4
	local center = IslandService._center
	local half = Vector3.new(size * 0.5 + pad, thickness * 0.5 + 2, size * 0.5 + pad)
	return center, half * 2
end

function IslandService.paintTerrain()
	local center, size = IslandService.getCarveBounds()
	if not (center and size) then
		return
	end
	-- Sand body above / through the sea surface so the isle reads as land
	Workspace.Terrain:FillBlock(CFrame.new(center), size, Enum.Material.Sand)
end

function IslandService.ensure(): Model
	if IslandService._model and IslandService._model.Parent then
		IslandService.paintTerrain()
		return IslandService._model
	end

	local cfg = Config.DriveIsland
	local size = cfg.SizeStuds
	local thickness = cfg.Thickness
	local topY = cfg.TopY
	local center = IslandService.getWorldCenter()

	IslandService._center = center
	IslandService._size = size
	IslandService._topY = topY
	IslandService._thickness = thickness

	local folder = lobbyRoot():FindFirstChild("DriveIslands")
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = "DriveIslands"
		folder.Parent = lobbyRoot()
	end

	local existing = folder:FindFirstChild("TinyFlatIsle")
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "TinyFlatIsle"
	model.Parent = folder

	-- One flat sand pad — no hills, no layered rises
	local deck = makePart({
		Name = "FlatSand",
		Parent = model,
		Size = Vector3.new(size, thickness, size),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(222, 202, 160),
		Material = Enum.Material.Sand,
		CanCollide = true,
	})
	model.PrimaryPart = deck

	-- Thin submerged shelf so the edge meets the water cleanly
	makePart({
		Name = "ReefShelf",
		Parent = model,
		Size = Vector3.new(size + 10, 2.2, size + 10),
		CFrame = CFrame.new(center.X, OceanConfig.SurfaceY - 1.2, center.Z),
		Color = Color3.fromRGB(72, 110, 98),
		Material = Enum.Material.Slate,
		CanCollide = false,
		CastShadow = false,
	})

	-- Soft rim lip so the flat top still reads as a beach edge
	local lipY = topY + 0.15
	local lipT = 1.4
	local half = size * 0.5
	for _, spec in {
		{ Name = "LipNorth", CFrame = CFrame.new(center.X, lipY, center.Z - half + lipT * 0.5), Size = Vector3.new(size, 0.35, lipT) },
		{ Name = "LipSouth", CFrame = CFrame.new(center.X, lipY, center.Z + half - lipT * 0.5), Size = Vector3.new(size, 0.35, lipT) },
		{ Name = "LipWest", CFrame = CFrame.new(center.X - half + lipT * 0.5, lipY, center.Z), Size = Vector3.new(lipT, 0.35, size - lipT * 2) },
		{ Name = "LipEast", CFrame = CFrame.new(center.X + half - lipT * 0.5, lipY, center.Z), Size = Vector3.new(lipT, 0.35, size - lipT * 2) },
	} do
		makePart({
			Name = spec.Name,
			Parent = model,
			Size = spec.Size,
			CFrame = spec.CFrame,
			Color = Color3.fromRGB(236, 218, 178),
			Material = Enum.Material.Sand,
			CanCollide = false,
		})
	end

	-- Single palm so the isle is readable from the raft without cluttering the flat
	local trunkH = 9
	local trunk = makePart({
		Name = "PalmTrunk",
		Parent = model,
		Size = Vector3.new(0.9, trunkH, 0.9),
		CFrame = CFrame.new(center.X - 6, topY + trunkH * 0.5, center.Z + 4) * CFrame.Angles(0, 0, math.rad(6)),
		Color = Color3.fromRGB(92, 64, 38),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	makePart({
		Name = "PalmFrond",
		Parent = model,
		Size = Vector3.new(7.5, 0.35, 2.2),
		CFrame = trunk.CFrame * CFrame.new(0, trunkH * 0.48, 0) * CFrame.Angles(0, math.rad(25), math.rad(12)),
		Color = Color3.fromRGB(48, 118, 62),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
	makePart({
		Name = "PalmFrond2",
		Parent = model,
		Size = Vector3.new(6.5, 0.35, 2),
		CFrame = trunk.CFrame * CFrame.new(0, trunkH * 0.46, 0) * CFrame.Angles(0, math.rad(-40), math.rad(-10)),
		Color = Color3.fromRGB(42, 108, 55),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})

	local marker = makePart({
		Name = "IsleMarker",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center.X, topY + 10, center.Z),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "IsleBillboard"
	gui.Adornee = marker
	gui.Size = UDim2.fromOffset(160, 40)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 420
	gui.Parent = marker

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(18, 36, 48)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Config.Theme.Foam
	label.Text = "TINY ISLE"
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	IslandService._model = model
	IslandService.paintTerrain()
	print("[SurviveAtSea] Tiny flat drive isle ready at", center)
	return model
end

return IslandService
