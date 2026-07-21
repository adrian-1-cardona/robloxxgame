-- Builds the Survive at Sea lobby: dock, ocean, boarding portals.
-- Geometry is created at runtime so the template stays Rojo-friendly.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyBuilder = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.CanCollide ~= false
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color or Config.Theme.Driftwood
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.Name = props.Name or "LobbyPart"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = props.CastShadow ~= false
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Parent then
		p.Parent = props.Parent
	end
	return p
end

local function weldBillboard(adornee: BasePart, text: string, color: Color3, size: UDim2?): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PortalSign"
	billboard.Adornee = adornee
	billboard.Size = size or UDim2.fromOffset(220, 70)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = adornee

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Config.Theme.UIPanel
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Config.UI.Font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Theme.UIAccent
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = label

	return billboard
end

local function styleLighting()
	Lighting.ClockTime = 17.2
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(40, 70, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 110, 130)
	Lighting.FogColor = Color3.fromRGB(90, 150, 170)
	Lighting.FogStart = 80
	Lighting.FogEnd = 420
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.GlobalShadows = true

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(120, 170, 190)
	atmosphere.Decay = Color3.fromRGB(40, 80, 110)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.4

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	sky.CelestialBodiesShown = true
	sky.StarCount = 1800
	sky.SkyboxGlare = 0.2
	sky.SunAngularSize = 18
	sky.MoonAngularSize = 11

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.35
	bloom.Size = 18
	bloom.Threshold = 1.1

	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Parent = Lighting
	end
	colorCorrection.TintColor = Color3.fromRGB(220, 240, 255)
	colorCorrection.Contrast = 0.08
	colorCorrection.Saturation = 0.12
end

local function clearDefaultBaseplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
end

local function buildOcean(folder: Folder)
	local ocean = part({
		Name = "Ocean",
		Parent = folder,
		Size = Vector3.new(900, 4, 900),
		CFrame = CFrame.new(0, -1, 0),
		Color = Config.Theme.DeepOcean,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CanCollide = true,
	})

	local foam = part({
		Name = "FoamRing",
		Parent = folder,
		Size = Vector3.new(220, 0.4, 220),
		CFrame = CFrame.new(0, 1.1, 0),
		Color = Config.Theme.Foam,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.72,
		CanCollide = false,
	})

	task.spawn(function()
		local bob = 0
		while foam.Parent do
			bob += 0.03
			foam.CFrame = CFrame.new(0, 1.1 + math.sin(bob) * 0.25, 0)
			ocean.Transparency = 0.32 + math.sin(bob * 0.7) * 0.04
			task.wait(0.05)
		end
	end)
end

local function buildDock(folder: Folder)
	local dock = Instance.new("Folder")
	dock.Name = "Dock"
	dock.Parent = folder

	-- Main pier deck
	part({
		Name = "PierDeck",
		Parent = dock,
		Size = Vector3.new(72, 2, 120),
		CFrame = CFrame.new(0, 3, -10),
		Color = Config.Theme.Driftwood,
		Material = Enum.Material.WoodPlanks,
	})

	-- Boardwalk toward portals
	part({
		Name = "Boardwalk",
		Parent = dock,
		Size = Vector3.new(28, 2, 48),
		CFrame = CFrame.new(0, 3, 70),
		Color = Color3.fromRGB(110, 78, 48),
		Material = Enum.Material.WoodPlanks,
	})

	-- Side rails
	for _, x in { -35, 35 } do
		part({
			Name = "Rail",
			Parent = dock,
			Size = Vector3.new(1.2, 3, 120),
			CFrame = CFrame.new(x, 5, -10),
			Color = Config.Theme.Rope,
			Material = Enum.Material.Wood,
		})
	end

	-- Support pillars
	for z = -50, 40, 18 do
		for _, x in { -28, 28 } do
			part({
				Name = "Pillar",
				Parent = dock,
				Size = Vector3.new(3, 14, 3),
				CFrame = CFrame.new(x, -2, z),
				Color = Color3.fromRGB(70, 48, 30),
				Material = Enum.Material.Wood,
			})
		end
	end

	-- Lighthouse silhouette
	local lighthouse = part({
		Name = "Lighthouse",
		Parent = dock,
		Size = Vector3.new(10, 42, 10),
		CFrame = CFrame.new(-48, 22, -40),
		Color = Color3.fromRGB(230, 230, 220),
		Material = Enum.Material.SmoothPlastic,
	})
	part({
		Name = "LighthouseLamp",
		Parent = dock,
		Size = Vector3.new(8, 6, 8),
		CFrame = lighthouse.CFrame * CFrame.new(0, 24, 0),
		Color = Config.Theme.Lantern,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	local light = Instance.new("PointLight")
	light.Brightness = 2.5
	light.Range = 60
	light.Color = Config.Theme.Lantern
	light.Parent = lighthouse

	-- Crates / atmosphere props
	for i = 1, 6 do
		part({
			Name = "Crate" .. i,
			Parent = dock,
			Size = Vector3.new(4, 4, 4),
			CFrame = CFrame.new(-18 + i * 5.5, 6, -35 + (i % 2) * 6) * CFrame.Angles(0, math.rad(i * 17), 0),
			Color = Color3.fromRGB(120, 85, 50),
			Material = Enum.Material.Wood,
		})
	end

	-- Buoys in the water
	for i = 1, 5 do
		local buoy = part({
			Name = "Buoy" .. i,
			Parent = dock,
			Size = Vector3.new(3, 5, 3),
			CFrame = CFrame.new(-60 + i * 28, 2, 40 + (i % 2) * 12),
			Color = if i % 2 == 0 then Color3.fromRGB(220, 70, 60) else Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		task.spawn(function()
			local t = i
			while buoy.Parent do
				t += 0.04
				buoy.CFrame = CFrame.new(buoy.Position.X, 2 + math.sin(t) * 0.6, buoy.Position.Z)
					* CFrame.Angles(0, t * 0.2, math.rad(math.sin(t) * 6))
				task.wait(0.05)
			end
		end)
	end
end

local function buildTitleSign(folder: Folder)
	local sign = part({
		Name = "TitleAnchor",
		Parent = folder,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(0, 18, -55),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "GameTitle"
	gui.Adornee = sign
	gui.Size = UDim2.fromOffset(520, 140)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 250
	gui.Parent = sign

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.65)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Config.Theme.Foam
	title.Text = Config.GameName
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0, 0.65)
	subtitle.Size = UDim2.fromScale(1, 0.35)
	subtitle.Font = Config.UI.BodyFont
	subtitle.TextScaled = true
	subtitle.TextColor3 = Config.Theme.UIAccent
	subtitle.Text = "BOARDING DOCK · CREW UP TO 10"
	subtitle.Parent = gui
end

local function buildPortal(folder: Folder, index: number, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Portal_" .. index
	model.Parent = folder

	local pad = part({
		Name = "Pad",
		Parent = model,
		Size = Vector3.new(16, 1.2, 16),
		CFrame = CFrame.new(position),
		Color = Color3.fromRGB(70, 55, 40),
		Material = Enum.Material.WoodPlanks,
	})

	-- Arch legs
	for _, offsetX in { -6, 6 } do
		part({
			Name = "ArchLeg",
			Parent = model,
			Size = Vector3.new(2, 16, 2),
			CFrame = CFrame.new(position + Vector3.new(offsetX, 8.5, 0)),
			Color = Config.Theme.Driftwood,
			Material = Enum.Material.Wood,
		})
	end

	part({
		Name = "ArchTop",
		Parent = model,
		Size = Vector3.new(16, 2, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 17, 0)),
		Color = Config.Theme.Driftwood,
		Material = Enum.Material.Wood,
	})

	local gate = part({
		Name = "Gate",
		Parent = model,
		Size = Vector3.new(10, 14, 1.2),
		CFrame = CFrame.new(position + Vector3.new(0, 8, 0)),
		Color = Config.Theme.PortalGlow,
		Material = Enum.Material.ForceField,
		Transparency = 0.35,
		CanCollide = false,
	})

	local gateLight = Instance.new("PointLight")
	gateLight.Color = Config.Theme.PortalGlow
	gateLight.Brightness = 2
	gateLight.Range = 24
	gateLight.Parent = gate

	-- Soft pulse for presence
	task.spawn(function()
		local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(gate, info, { Transparency = 0.62 }):Play()
	end)

	local promptPart = part({
		Name = "PromptAnchor",
		Parent = model,
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(position + Vector3.new(0, 3, 4)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ObjectText = "Voyage Portal " .. index
	prompt.ActionText = "Open Boarding"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- Works for touch, gamepad, keyboard, VR laser
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.UIOffset = Vector2.new(0, -20)
	prompt.Parent = promptPart

	local attrs = Instance.new("Folder")
	attrs.Name = "PortalData"
	attrs.Parent = model

	local indexValue = Instance.new("IntValue")
	indexValue.Name = "PortalIndex"
	indexValue.Value = index
	indexValue.Parent = model

	weldBillboard(pad, `PORTAL {index}\nEmpty berth`, Config.Theme.Foam)

	model.PrimaryPart = pad
	return model
end

local function buildVoyageStaging(folder: Folder)
	local staging = Instance.new("Folder")
	staging.Name = "VoyageStaging"
	staging.Parent = folder

	part({
		Name = "Deck",
		Parent = staging,
		Size = Vector3.new(60, 2, 40),
		CFrame = CFrame.new(0, 3, 220),
		Color = Color3.fromRGB(80, 60, 40),
		Material = Enum.Material.WoodPlanks,
	})

	part({
		Name = "ShipHullHint",
		Parent = staging,
		Size = Vector3.new(50, 10, 6),
		CFrame = CFrame.new(0, 6, 238),
		Color = Color3.fromRGB(55, 40, 28),
		Material = Enum.Material.Wood,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "VoyageSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 5, 220)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = false
	spawn.Parent = staging

	local sign = part({
		Name = "VoyageSignAnchor",
		Parent = staging,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 14, 220),
		Transparency = 1,
		CanCollide = false,
	})
	weldBillboard(sign, "VOYAGE UNDERWAY\n(No save — session only)", Config.Theme.Lantern, UDim2.fromOffset(360, 90))
end

local function setupLobbySpawn(folder: Folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 5, -20)
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Transparency = 0.4
	spawn.BrickColor = BrickColor.new("Cyan")
	spawn.Material = Enum.Material.Neon
	spawn.Parent = folder

	-- Disable any other default spawns
	for _, child in Workspace:GetDescendants() do
		if child:IsA("SpawnLocation") and child ~= spawn and child.Name ~= "VoyageSpawn" then
			child.Enabled = false
		end
	end
end

function LobbyBuilder.build(): Folder
	clearDefaultBaseplate()
	styleLighting()

	local existing = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "SurviveAtSeaLobby"
	root.Parent = Workspace

	buildOcean(root)
	buildDock(root)
	buildTitleSign(root)
	buildVoyageStaging(root)
	setupLobbySpawn(root)

	local portalsFolder = Instance.new("Folder")
	portalsFolder.Name = "Portals"
	portalsFolder.Parent = root

	local portals = {}
	local startX = -((Config.PortalCount - 1) * Config.PortalSpacing) / 2
	for i = 1, Config.PortalCount do
		local pos = Vector3.new(startX + (i - 1) * Config.PortalSpacing, 4, 95)
		local model = buildPortal(portalsFolder, i, pos)
		portals[i] = model
	end

	Players.CharacterAutoLoads = true

	return root
end

function LobbyBuilder.updatePortalSign(portalModel: Model, title: string, subtitle: string, color: Color3?)
	local pad = portalModel:FindFirstChild("Pad")
	if not (pad and pad:IsA("BasePart")) then
		return
	end

	local billboard = pad:FindFirstChild("PortalSign")
	if billboard then
		billboard:Destroy()
	end
	weldBillboard(pad, `{title}\n{subtitle}`, color or Config.Theme.Foam)
end

function LobbyBuilder.getPortalModel(index: number): Model?
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if not root then
		return nil
	end
	local portals = root:FindFirstChild("Portals")
	if not portals then
		return nil
	end
	local model = portals:FindFirstChild("Portal_" .. index)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

function LobbyBuilder.getVoyageSpawnCFrame(): CFrame
	return CFrame.new(0, 6, 220)
end

function LobbyBuilder.getLobbySpawnCFrame(): CFrame
	return CFrame.new(0, 6, -20)
end

return LobbyBuilder
