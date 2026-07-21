-- Builds the Survive at Sea boarding dock in Workspace.
-- Safe to call from server (replicates) or client (local fallback).

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))

local LobbyWorld = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.WoodPlanks
	p.Color = props.Color or Config.Theme.Driftwood
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.Name = props.Name or "LobbyPart"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.Reflectance ~= nil then
		p.Reflectance = props.Reflectance
	end
	p.Parent = props.Parent
	return p
end

local function billboard(adornee: BasePart, text: string, color: Color3, size: UDim2?, offsetY: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "LobbyBillboard"
	gui.Adornee = adornee
	gui.Size = size or UDim2.fromOffset(280, 90)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 0.15
	label.BackgroundColor3 = Config.Theme.UIPanel
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Theme.UIAccent
	stroke.Thickness = 2
	stroke.Parent = label
end

local function buildPortal(folder: Instance, index: number, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Portal_" .. index
	model.Parent = folder

	local pad = part({
		Name = "Pad",
		Parent = model,
		Size = Vector3.new(18, 1.5, 18),
		CFrame = CFrame.new(position),
		Color = Color3.fromRGB(80, 58, 36),
		Material = Enum.Material.WoodPlanks,
	})

	part({
		Name = "NeonRing",
		Parent = model,
		Size = Vector3.new(18.5, 0.6, 18.5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.9, 0)),
		Color = Config.Theme.PortalGlow,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	for _, offsetX in { -7, 7 } do
		part({
			Name = "ArchLeg",
			Parent = model,
			Size = Vector3.new(2.5, 18, 2.5),
			CFrame = CFrame.new(position + Vector3.new(offsetX, 10, 0)),
			Color = Color3.fromRGB(95, 65, 40),
			Material = Enum.Material.Wood,
		})
	end

	part({
		Name = "ArchTop",
		Parent = model,
		Size = Vector3.new(18, 2.5, 2.5),
		CFrame = CFrame.new(position + Vector3.new(0, 20, 0)),
		Color = Color3.fromRGB(95, 65, 40),
		Material = Enum.Material.Wood,
	})

	local gate = part({
		Name = "Gate",
		Parent = model,
		Size = Vector3.new(11, 15, 1.4),
		CFrame = CFrame.new(position + Vector3.new(0, 9, 0)),
		Color = Config.Theme.PortalGlow,
		Material = Enum.Material.ForceField,
		Transparency = 0.25,
		CanCollide = false,
	})

	local gateLight = Instance.new("PointLight")
	gateLight.Color = Config.Theme.PortalGlow
	gateLight.Brightness = 3
	gateLight.Range = 28
	gateLight.Parent = gate

	task.spawn(function()
		local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(gate, info, { Transparency = 0.55 }):Play()
	end)

	local promptPart = part({
		Name = "PromptAnchor",
		Parent = model,
		Size = Vector3.new(6, 6, 6),
		CFrame = CFrame.new(position + Vector3.new(0, 3, 6)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ObjectText = "Voyage Portal " .. index
	prompt.ActionText = "Create Crew"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = promptPart

	local indexValue = Instance.new("IntValue")
	indexValue.Name = "PortalIndex"
	indexValue.Value = index
	indexValue.Parent = model

	billboard(pad, `PORTAL {index}\nWalk up · press E`, Config.Theme.Foam, UDim2.fromOffset(260, 90), 10)
	model.PrimaryPart = pad
	return model
end

function LobbyWorld.getLobbySpawnCFrame(): CFrame
	return CFrame.new(0, 6, 0)
end

function LobbyWorld.ensure(): Folder
	local existing = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if existing and existing:IsA("Folder") then
		return existing
	end

	-- Hide leftover starter pads so the pier is obvious
	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name ~= "Terrain") then
			if child.Name ~= "SurviveAtSeaLobby" then
				child.Transparency = 1
				if child:IsA("BasePart") then
					child.CanCollide = false
				end
				if child:IsA("SpawnLocation") then
					child.Enabled = false
				end
			end
		end
	end

	local root = Instance.new("Folder")
	root.Name = "SurviveAtSeaLobby"
	root.Parent = Workspace

	part({
		Name = "OceanDeep",
		Parent = root,
		Size = Vector3.new(1200, 30, 1200),
		CFrame = CFrame.new(0, -16, 0),
		Color = Color3.fromRGB(6, 40, 70),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.1,
	})

	part({
		Name = "OceanSurface",
		Parent = root,
		Size = Vector3.new(1200, 2, 1200),
		CFrame = CFrame.new(0, 0, 0),
		Color = Color3.fromRGB(20, 120, 150),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Reflectance = 0.15,
		CanCollide = false,
	})

	local dock = Instance.new("Folder")
	dock.Name = "Dock"
	dock.Parent = root

	part({
		Name = "PierDeck",
		Parent = dock,
		Size = Vector3.new(80, 3, 140),
		CFrame = CFrame.new(0, 2, 20),
		Color = Color3.fromRGB(120, 82, 48),
		Material = Enum.Material.WoodPlanks,
	})

	part({
		Name = "CenterPlank",
		Parent = dock,
		Size = Vector3.new(8, 3.2, 140),
		CFrame = CFrame.new(0, 2, 20),
		Color = Color3.fromRGB(170, 120, 70),
		Material = Enum.Material.WoodPlanks,
	})

	for _, x in { -38, 38 } do
		part({
			Name = "Rail",
			Parent = dock,
			Size = Vector3.new(1.5, 4, 140),
			CFrame = CFrame.new(x, 5, 20),
			Color = Color3.fromRGB(90, 60, 35),
			Material = Enum.Material.Wood,
		})
	end

	for z = -40, 80, 20 do
		for _, x in { -30, 30 } do
			part({
				Name = "Pillar",
				Parent = dock,
				Size = Vector3.new(4, 18, 4),
				CFrame = CFrame.new(x, -5, z),
				Color = Color3.fromRGB(70, 48, 28),
				Material = Enum.Material.Wood,
			})
		end
	end

	part({
		Name = "Lighthouse",
		Parent = dock,
		Size = Vector3.new(12, 48, 12),
		CFrame = CFrame.new(-55, 25, -20),
		Color = Color3.fromRGB(240, 240, 235),
		Material = Enum.Material.SmoothPlastic,
	})
	part({
		Name = "LighthouseStripe",
		Parent = dock,
		Size = Vector3.new(12.4, 8, 12.4),
		CFrame = CFrame.new(-55, 18, -20),
		Color = Color3.fromRGB(200, 60, 55),
		Material = Enum.Material.SmoothPlastic,
	})
	local lamp = part({
		Name = "LighthouseLamp",
		Parent = dock,
		Size = Vector3.new(10, 8, 10),
		CFrame = CFrame.new(-55, 52, -20),
		Color = Config.Theme.Lantern,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = 90
	light.Color = Config.Theme.Lantern
	light.Parent = lamp

	for i = 1, 8 do
		part({
			Name = "Crate" .. i,
			Parent = dock,
			Size = Vector3.new(5, 5, 5),
			CFrame = CFrame.new(-22 + i * 5, 6.5, -30 + (i % 3) * 5),
			Color = Color3.fromRGB(130, 90, 50),
			Material = Enum.Material.Wood,
		})
	end

	for i = 1, 6 do
		part({
			Name = "Buoy" .. i,
			Parent = dock,
			Size = Vector3.new(4, 7, 4),
			CFrame = CFrame.new(-70 + i * 26, 3, 55 + (i % 2) * 14),
			Color = if i % 2 == 0 then Color3.fromRGB(230, 55, 50) else Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end

	local title = part({
		Name = "TitleBanner",
		Parent = dock,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(0, 22, -35),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	billboard(title, "SURVIVE AT SEA\nBOARDING DOCK", Config.Theme.Foam, UDim2.fromOffset(520, 140), 0)

	local portalsFolder = Instance.new("Folder")
	portalsFolder.Name = "Portals"
	portalsFolder.Parent = root

	local startX = -((Config.PortalCount - 1) * Config.PortalSpacing) / 2
	for i = 1, Config.PortalCount do
		local pos = Vector3.new(startX + (i - 1) * Config.PortalSpacing, 3.5, 70)
		buildPortal(portalsFolder, i, pos)
	end

	for z = 20, 55, 12 do
		part({
			Name = "Arrow",
			Parent = root,
			Size = Vector3.new(6, 0.5, 8),
			CFrame = CFrame.new(0, 4, z),
			Color = Config.Theme.PortalGlow,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end

	local staging = Instance.new("Folder")
	staging.Name = "VoyageStaging"
	staging.Parent = root
	part({
		Name = "Deck",
		Parent = staging,
		Size = Vector3.new(70, 3, 46),
		CFrame = CFrame.new(0, 2, 220),
		Color = Color3.fromRGB(90, 65, 40),
		Material = Enum.Material.WoodPlanks,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, 4.2, 0)
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Transparency = 0.3
	spawn.BrickColor = BrickColor.new("Cyan")
	spawn.Material = Enum.Material.Neon
	spawn.Parent = root

	print("[SurviveAtSea] LobbyWorld.ensure built dock + portals")
	return root
end

function LobbyWorld.seatCharacter(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = LobbyWorld.getLobbySpawnCFrame() * CFrame.Angles(0, 0, 0)
		-- Face portals (+Z)
		root.CFrame = CFrame.new(root.Position, root.Position + Vector3.new(0, 0, 40))
	end
end

return LobbyWorld
