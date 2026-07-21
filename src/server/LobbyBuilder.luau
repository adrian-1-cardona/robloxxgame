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
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.Wood
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
	if props.Parent then
		p.Parent = props.Parent
	end
	return p
end

local function billboard(adornee: BasePart, text: string, color: Color3, size: UDim2?, offsetY: number?): BillboardGui
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
	label.Font = Enum.Font.GothamBlack
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

	return gui
end

local function safeLighting()
	-- Never let lighting tweaks prevent the dock from spawning.
	local ok, err = pcall(function()
		Lighting.ClockTime = 16.5
		Lighting.Brightness = 3
		Lighting.Ambient = Color3.fromRGB(50, 90, 110)
		Lighting.OutdoorAmbient = Color3.fromRGB(90, 140, 160)
		Lighting.FogColor = Color3.fromRGB(70, 140, 170)
		Lighting.FogStart = 200
		Lighting.FogEnd = 800
		Lighting.GlobalShadows = true

		for _, child in Lighting:GetChildren() do
			if child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("ColorCorrectionEffect") then
				child:Destroy()
			end
		end

		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.18
		atmosphere.Offset = 0.1
		atmosphere.Color = Color3.fromRGB(140, 185, 205)
		atmosphere.Decay = Color3.fromRGB(50, 90, 120)
		atmosphere.Glare = 0.08
		atmosphere.Haze = 0.6
		atmosphere.Parent = Lighting

		local sky = Lighting:FindFirstChildOfClass("Sky")
		if not sky then
			sky = Instance.new("Sky")
			sky.Parent = Lighting
		end
		sky.CelestialBodiesShown = true
		sky.StarCount = 1200
		sky.SunAngularSize = 21
		sky.MoonAngularSize = 11

		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.25
		bloom.Size = 14
		bloom.Threshold = 1.2
		bloom.Parent = Lighting

		local cc = Instance.new("ColorCorrectionEffect")
		cc.TintColor = Color3.fromRGB(225, 242, 255)
		cc.Contrast = 0.05
		cc.Saturation = 0.15
		cc.Parent = Lighting
	end)
	if not ok then
		warn("[SurviveAtSea] Lighting setup failed (lobby still builds):", err)
	end
end

local function clearWorkspaceClutter()
	-- Remove default / leftover place geometry so the dock is obvious.
	for _, name in { "Baseplate", "SpawnLocation", "Terrain" } do
		local inst = Workspace:FindFirstChild(name)
		if inst and not inst:IsA("Terrain") then
			inst:Destroy()
		end
	end

	-- Clear common starter-place leftovers (keeps cameras/characters)
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
			if child.Name ~= "SurviveAtSeaLobby" and child.Name ~= "Camera" and child.Name ~= "Terrain" then
				-- Keep player characters
				local isCharacter = false
				for _, plr in Players:GetPlayers() do
					if plr.Character == child then
						isCharacter = true
						break
					end
				end
				if not isCharacter then
					child:Destroy()
				end
			end
		end
	end
end

local function buildOcean(folder: Folder)
	-- Solid water plane players can stand near / see clearly
	part({
		Name = "OceanDeep",
		Parent = folder,
		Size = Vector3.new(1200, 30, 1200),
		CFrame = CFrame.new(0, -16, 0),
		Color = Color3.fromRGB(6, 40, 70),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		CanCollide = true,
	})

	part({
		Name = "OceanSurface",
		Parent = folder,
		Size = Vector3.new(1200, 2, 1200),
		CFrame = CFrame.new(0, 0, 0),
		Color = Color3.fromRGB(20, 120, 150),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Reflectance = 0.15,
		CanCollide = false,
	})

	-- Shore foam ring around dock
	part({
		Name = "Foam",
		Parent = folder,
		Size = Vector3.new(160, 0.6, 160),
		CFrame = CFrame.new(0, 1.2, 20),
		Color = Config.Theme.Foam,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.55,
		CanCollide = false,
	})
end

local function buildDock(folder: Folder)
	local dock = Instance.new("Folder")
	dock.Name = "Dock"
	dock.Parent = folder

	-- Huge visible pier under spawn
	part({
		Name = "PierDeck",
		Parent = dock,
		Size = Vector3.new(80, 3, 140),
		CFrame = CFrame.new(0, 2, 20),
		Color = Color3.fromRGB(120, 82, 48),
		Material = Enum.Material.WoodPlanks,
	})

	-- Bright center stripe so you know you landed
	part({
		Name = "CenterPlank",
		Parent = dock,
		Size = Vector3.new(8, 3.2, 140),
		CFrame = CFrame.new(0, 2, 20),
		Color = Color3.fromRGB(170, 120, 70),
		Material = Enum.Material.WoodPlanks,
	})

	-- Rails
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

	-- Pillars into the water
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

	-- Lighthouse (very visible landmark)
	local tower = part({
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

	-- Crates
	for i = 1, 8 do
		part({
			Name = "Crate" .. i,
			Parent = dock,
			Size = Vector3.new(5, 5, 5),
			CFrame = CFrame.new(-22 + i * 5, 6.5, -30 + (i % 3) * 5) * CFrame.Angles(0, math.rad(i * 12), 0),
			Color = Color3.fromRGB(130, 90, 50),
			Material = Enum.Material.Wood,
		})
	end

	-- Bobbing buoys
	for i = 1, 6 do
		local buoy = part({
			Name = "Buoy" .. i,
			Parent = dock,
			Size = Vector3.new(4, 7, 4),
			CFrame = CFrame.new(-70 + i * 26, 3, 55 + (i % 2) * 14),
			Color = if i % 2 == 0 then Color3.fromRGB(230, 55, 50) else Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		task.spawn(function()
			local t = i * 1.7
			while buoy.Parent do
				t += 0.05
				local pos = buoy.Position
				buoy.CFrame = CFrame.new(pos.X, 3 + math.sin(t) * 0.8, pos.Z)
					* CFrame.Angles(0, t * 0.25, math.rad(math.sin(t) * 8))
				task.wait(0.05)
			end
		end)
	end

	-- Title banner above dock
	local titleAnchor = part({
		Name = "TitleAnchor",
		Parent = dock,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(0, 22, -35),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	billboard(titleAnchor, "SURVIVE AT SEA\nBOARDING DOCK", Config.Theme.Foam, UDim2.fromOffset(520, 140), 0)

	return tower
end

local function buildPortal(folder: Folder, index: number, position: Vector3): Model
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

	-- Neon ring so portals pop from spawn
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
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = promptPart

	local indexValue = Instance.new("IntValue")
	indexValue.Name = "PortalIndex"
	indexValue.Value = index
	indexValue.Parent = model

	billboard(pad, `PORTAL {index}\nWalk up · press E`, Config.Theme.Foam, UDim2.fromOffset(240, 80), 10)

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
		Size = Vector3.new(70, 3, 46),
		CFrame = CFrame.new(0, 2, 220),
		Color = Color3.fromRGB(90, 65, 40),
		Material = Enum.Material.WoodPlanks,
	})

	part({
		Name = "Hull",
		Parent = staging,
		Size = Vector3.new(56, 12, 8),
		CFrame = CFrame.new(0, 7, 240),
		Color = Color3.fromRGB(60, 42, 28),
		Material = Enum.Material.Wood,
	})

	local sign = part({
		Name = "VoyageSign",
		Parent = staging,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 16, 220),
		Transparency = 1,
		CanCollide = false,
	})
	billboard(sign, "VOYAGE UNDERWAY\n(No save — session only)", Config.Theme.Lantern, UDim2.fromOffset(400, 100), 0)
end

local function setupSpawn(folder: Folder)
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
	spawn.Parent = folder

	-- Face the portals (positive Z)
	spawn.CFrame = CFrame.new(0, 4.2, 0) * CFrame.Angles(0, 0, 0)
end

function LobbyBuilder.enhanceExisting(root: Folder)
	safeLighting()

	local spawn = root:FindFirstChild("LobbySpawn")
	if not (spawn and spawn:IsA("SpawnLocation")) then
		setupSpawn(root)
	else
		local spawnLocation = spawn :: SpawnLocation
		spawnLocation.Enabled = true
		spawnLocation.Neutral = true
	end

	-- World-space title
	local dock = root:FindFirstChild("Dock")
	if dock and not dock:FindFirstChild("TitleBanner") then
		local titleAnchor = part({
			Name = "TitleBanner",
			Parent = dock,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(0, 22, -35),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
		})
		billboard(titleAnchor, "SURVIVE AT SEA\nBOARDING DOCK", Config.Theme.Foam, UDim2.fromOffset(520, 140), 0)
	end

	local portals = root:FindFirstChild("Portals")
	if portals then
		for _, model in portals:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local pad = model:FindFirstChild("Pad")
			local indexValue = model:FindFirstChild("PortalIndex")
			local index = if indexValue and indexValue:IsA("IntValue") then indexValue.Value else 0
			if pad and pad:IsA("BasePart") and not pad:FindFirstChild("LobbyBillboard") then
				billboard(pad, `PORTAL {index}\nWalk up · press E`, Config.Theme.Foam, UDim2.fromOffset(260, 90), 10)
			end

			local gate = model:FindFirstChild("Gate")
			if gate and gate:IsA("BasePart") then
				if not gate:FindFirstChildOfClass("PointLight") then
					local light = Instance.new("PointLight")
					light.Color = Config.Theme.PortalGlow
					light.Brightness = 3
					light.Range = 28
					light.Parent = gate
				end
				task.spawn(function()
					local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
					TweenService:Create(gate, info, { Transparency = 0.55 }):Play()
				end)
			end
		end
	end

	print("[SurviveAtSea] Enhanced existing lobby map")
end

function LobbyBuilder.build(): Folder
	local existing = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if existing then
		existing:Destroy()
	end

	clearWorkspaceClutter()
	safeLighting()

	local root = Instance.new("Folder")
	root.Name = "SurviveAtSeaLobby"
	root.Parent = Workspace

	buildOcean(root)
	buildDock(root)
	buildVoyageStaging(root)
	setupSpawn(root)

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

	print("[SurviveAtSea] Lobby geometry built — dock +", Config.PortalCount, "portals")
	return root
end

function LobbyBuilder.updatePortalSign(portalModel: Model, title: string, subtitle: string, color: Color3?)
	local pad = portalModel:FindFirstChild("Pad")
	if not (pad and pad:IsA("BasePart")) then
		return
	end
	local old = pad:FindFirstChild("LobbyBillboard")
	if old then
		old:Destroy()
	end
	billboard(pad, `{title}\n{subtitle}`, color or Config.Theme.Foam, UDim2.fromOffset(260, 90), 10)
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
	return CFrame.new(0, 6, 0)
end

function LobbyBuilder.teleportPlayerToLobby(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))
	LobbyWorld.seatCharacter(character)
end

return LobbyBuilder
