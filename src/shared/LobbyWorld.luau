-- Builds and polishes the Survive at Sea boarding ship.
-- Safe to call from server (replicates) or client (local fallback).
-- Theme: a moored pirate galleon (hull, bulwarks, masts + sails, transom
-- stern, ship's wheel) that players board from. No neon portal glows.
-- Players stay on the ship's deck (invisible barriers).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))
local OceanConfig = require(script.Parent:WaitForChild("OceanConfig"))

local LobbyWorld = {}

-- Decorative motion (boat bob, gate sway, flag wave) is tagged here and driven
-- locally on each client by LobbyFX. Keeping it off the server means the engine
-- never streams thousands of anchored-part CFrame updates per second — the old
-- server task.spawn loops were the main source of lobby lag.
LobbyWorld.Tags = {
	Boat = "SurviveAtSeaFXBoat",
	Gate = "SurviveAtSeaFXGate",
	Flag = "SurviveAtSeaFXFlag",
}

-- Pier playable bounds (matches PierDeck at CFrame 0,2,20 size 80×140)
local PIER = {
	Center = Vector3.new(0, 2, 20),
	HalfX = 38,
	HalfZ = 68,
	DeckY = 3.5,
}

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
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function billboard(
	adornee: BasePart,
	text: string,
	color: Color3,
	size: UDim2?,
	offsetY: number?,
	maxTextSize: number?
)
	local gui = Instance.new("BillboardGui")
	gui.Name = "LobbyBillboard"
	gui.Adornee = adornee
	gui.Size = size or UDim2.fromOffset(160, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.fromRGB(32, 40, 44)
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 78, 58)
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = label

	local constrain = Instance.new("UITextSizeConstraint")
	constrain.MaxTextSize = maxTextSize or 16
	constrain.MinTextSize = 9
	constrain.Parent = label
end

local function buildPalm(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Palm"
	model.Parent = parent

	-- Slight lean + tapered trunk for a less blocky silhouette
	local lean = math.rad((math.noise(position.X * 0.07, position.Z * 0.07) - 0.5) * 14)
	part({
		Name = "TrunkLower",
		Parent = model,
		Size = Vector3.new(1.8 * s, 7 * s, 1.8 * s),
		CFrame = CFrame.new(position + Vector3.new(0, 3.5 * s, 0)) * CFrame.Angles(0, 0, lean * 0.5),
		Color = Color3.fromRGB(118, 86, 52),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part({
		Name = "TrunkUpper",
		Parent = model,
		Size = Vector3.new(1.35 * s, 8 * s, 1.35 * s),
		CFrame = CFrame.new(position + Vector3.new(math.sin(lean) * 1.2 * s, 10.5 * s, 0))
			* CFrame.Angles(0, 0, lean),
		Color = Color3.fromRGB(102, 74, 44),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	local crown = position + Vector3.new(math.sin(lean) * 2.2 * s, 15 * s, 0)
	for i = 0, 7 do
		local yaw = math.rad(i * 45 + 8)
		local droop = -22 - (i % 3) * 6
		part({
			Name = "Frond" .. i,
			Parent = model,
			Size = Vector3.new(0.9 * s, 0.28 * s, (7.5 + (i % 3)) * s),
			CFrame = CFrame.new(crown)
				* CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(math.rad(droop), 0, 0)
				* CFrame.new(0, 0, -3.2 * s),
			Color = if i % 2 == 0 then Color3.fromRGB(52, 118, 62) else Color3.fromRGB(38, 98, 50),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end

	part({
		Name = "Coconuts",
		Parent = model,
		Size = Vector3.new(1.8 * s, 1.3 * s, 1.8 * s),
		CFrame = CFrame.new(crown + Vector3.new(0, -0.6 * s, 0)),
		Color = Color3.fromRGB(86, 58, 30),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	return model
end

local function buildBoat(parent: Instance, position: Vector3, yawDegrees: number, hullColor: Color3?)
	local model = Instance.new("Model")
	model.Name = "Boat"
	model.Parent = parent

	local yaw = math.rad(yawDegrees)
	local hull = hullColor or Color3.fromRGB(150, 95, 55)

	-- Local offsets from hull center (reapplied each bob frame)
	local pieces: { { name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material } } = {
		{
			name = "Hull",
			size = Vector3.new(8, 3, 18),
			offset = CFrame.new(),
			color = hull,
			material = Enum.Material.Wood,
		},
		{
			name = "Bow",
			size = Vector3.new(6, 2.5, 6),
			offset = CFrame.new(0, 0.2, -10),
			color = hull,
			material = Enum.Material.Wood,
		},
		{
			name = "Deck",
			size = Vector3.new(6.5, 0.6, 14),
			offset = CFrame.new(0, 1.6, -1),
			color = Color3.fromRGB(170, 125, 75),
			material = Enum.Material.WoodPlanks,
		},
		{
			name = "Mast",
			size = Vector3.new(0.8, 16, 0.8),
			offset = CFrame.new(0, 9, 1),
			color = Color3.fromRGB(95, 68, 40),
			material = Enum.Material.Wood,
		},
		{
			name = "Sail",
			size = Vector3.new(0.4, 10, 8),
			offset = CFrame.new(0, 9, -1.5),
			color = Color3.fromRGB(235, 228, 210),
			material = Enum.Material.Fabric,
		},
		{
			name = "Cabin",
			size = Vector3.new(5, 3.5, 5),
			offset = CFrame.new(0, 3.5, 4),
			color = Color3.fromRGB(120, 80, 48),
			material = Enum.Material.Wood,
		},
	}

	local built: { { part: BasePart, offset: CFrame } } = {}
	for _, piece in pieces do
		local p = part({
			Name = piece.name,
			Parent = model,
			Size = piece.size,
			CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * piece.offset,
			Color = piece.color,
			Material = piece.material,
			CanCollide = false,
		})
		table.insert(built, { part = p, offset = piece.offset })
	end

	-- Client-driven bob/roll (see LobbyWorld.Tags). Store the base pose so every
	-- client can reproduce the exact same gentle motion without any replication.
	model:SetAttribute("BaseX", position.X)
	model:SetAttribute("BaseY", position.Y)
	model:SetAttribute("BaseZ", position.Z)
	model:SetAttribute("YawDeg", yawDegrees)
	CollectionService:AddTag(model, LobbyWorld.Tags.Boat)

	return model
end

local function buildBarriers(root: Folder)
	local existing = root:FindFirstChild("Barriers")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Barriers"
	folder.Parent = root

	-- Invisible walls keep sailors on the pier (easy lobby — no swimming off)
	local wallH = 18
	local wallY = PIER.DeckY + wallH / 2
	local cx, cz = PIER.Center.X, PIER.Center.Z
	local hx, hz = PIER.HalfX, PIER.HalfZ

	local walls = {
		{ Name = "WallWest", Size = Vector3.new(2, wallH, hz * 2 + 2), Pos = Vector3.new(cx - hx, wallY, cz) },
		{ Name = "WallEast", Size = Vector3.new(2, wallH, hz * 2 + 2), Pos = Vector3.new(cx + hx, wallY, cz) },
		{ Name = "WallSouth", Size = Vector3.new(hx * 2, wallH, 2), Pos = Vector3.new(cx, wallY, cz - hz) },
		{ Name = "WallNorth", Size = Vector3.new(hx * 2, wallH, 2), Pos = Vector3.new(cx, wallY, cz + hz) },
	}

	for _, w in walls do
		part({
			Name = w.Name,
			Parent = folder,
			Size = w.Size,
			CFrame = CFrame.new(w.Pos),
			Transparency = 1,
			CanCollide = true,
			CastShadow = false,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(255, 255, 255),
		})
	end

	-- Soft floor lip so players don't slip under rails
	part({
		Name = "DeckLip",
		Parent = folder,
		Size = Vector3.new(hx * 2 - 2, 1, hz * 2 - 2),
		CFrame = CFrame.new(cx, 1.2, cz),
		Transparency = 1,
		CanCollide = true,
		CastShadow = false,
	})
end

local function buildPortal(folder: Instance, index: number, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Portal_" .. index
	model.Parent = folder

	local wood = Color3.fromRGB(92, 62, 40)
	local purple = Config.Berth.Purple
	local purpleDeep = Config.Berth.PurpleDeep
	local purpleSoft = Config.Berth.PurpleSoft

	-- Solid purple berth pad (no half-and-half overlays)
	local pad = part({
		Name = "Pad",
		Parent = model,
		Size = Vector3.new(14, 1.2, 14),
		CFrame = CFrame.new(position),
		Color = purpleDeep,
		Material = Enum.Material.WoodPlanks,
	})

	part({
		Name = "BerthRim",
		Parent = model,
		Size = Vector3.new(14.5, 0.35, 14.5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.75, 0)),
		Color = purple,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	for _, offsetX in { -5.2, 5.2 } do
		part({
			Name = "ArchLeg",
			Parent = model,
			Size = Vector3.new(1.8, 15, 1.8),
			CFrame = CFrame.new(position + Vector3.new(offsetX, 8.5, -0.5)),
			Color = wood,
			Material = Enum.Material.Wood,
		})
	end

	part({
		Name = "ArchTop",
		Parent = model,
		Size = Vector3.new(12.4, 1.8, 1.8),
		CFrame = CFrame.new(position + Vector3.new(0, 16.5, -0.5)),
		Color = wood,
		Material = Enum.Material.Wood,
	})

	part({
		Name = "ArchBanner",
		Parent = model,
		Size = Vector3.new(11.2, 1.0, 0.3),
		CFrame = CFrame.new(position + Vector3.new(0, 15.5, 0.5)),
		Color = purple,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})

	local gate = part({
		Name = "Gate",
		Parent = model,
		Size = Vector3.new(8.2, 12, 0.45),
		CFrame = CFrame.new(position + Vector3.new(0, 8.5, -0.5)),
		Color = purpleSoft,
		Material = Enum.Material.Fabric,
		Transparency = 0.08,
		CanCollide = false,
	})

	-- Client-driven gentle sway (see LobbyWorld.Tags).
	gate:SetAttribute("PhaseSeed", index * 1.3)
	CollectionService:AddTag(gate, LobbyWorld.Tags.Gate)

	local signAnchor = part({
		Name = "SignAnchor",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(position + Vector3.new(0, 19, -0.5)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	billboard(signAnchor, `Portal {index}`, Color3.fromRGB(255, 236, 228), UDim2.fromOffset(120, 30), 0, 14)

	local promptPart = part({
		Name = "PromptAnchor",
		Parent = model,
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(position + Vector3.new(0, 3, 4)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ObjectText = "Portal " .. index
	prompt.ActionText = "Create Crew"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = promptPart

	local indexValue = Instance.new("IntValue")
	indexValue.Name = "PortalIndex"
	indexValue.Value = index
	indexValue.Parent = model

	local walkTrigger = part({
		Name = "WalkTrigger",
		Parent = model,
		Size = Vector3.new(10, 13, 9),
		CFrame = CFrame.new(position + Vector3.new(0, 7.5, 0.5)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
	})
	walkTrigger.CanTouch = true
	walkTrigger.CanQuery = false

	model.PrimaryPart = pad
	return model
end

local function stripGlowParts(root: Folder)
	for _, desc in root:GetDescendants() do
		if desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
			desc:Destroy()
			continue
		end
		if desc:IsA("BasePart") then
			local name = desc.Name
			if name == "NeonRing" or name == "Arrow" or name:find("Neon") then
				desc:Destroy()
				continue
			end
			-- Absolutely no Neon materials in the lobby
			if desc.Material == Enum.Material.Neon or desc.Material == Enum.Material.ForceField then
				if name == "Gate" then
					desc.Material = Enum.Material.Fabric
					desc.Color = Config.Berth.PurpleSoft
					desc.Transparency = 0.08
				elseif name == "LighthouseLamp" then
					desc.Material = Enum.Material.SmoothPlastic
					desc.Color = Color3.fromRGB(245, 220, 160)
				else
					desc.Material = Enum.Material.SmoothPlastic
				end
			end
			if name == "Gate" then
				desc.Material = Enum.Material.Fabric
				desc.Color = Config.Berth.PurpleSoft
				desc.Transparency = 0.08
			end
			-- Clean up leftover half-and-half parts from older builds
			if name == "PadRed" or name == "PadBlue" or name == "GateRed" or name == "GateBlue"
				or name == "ArchBannerRed" or name == "ArchBannerBlue" or name == "BerthSeam"
			then
				desc:Destroy()
			end
		end
	end
end

local function buildCannon(parent: Instance, position: Vector3, yawDegrees: number)
	local model = Instance.new("Model")
	model.Name = "Cannon"
	model.Parent = parent

	local yaw = math.rad(yawDegrees)
	local baseCf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local iron = Color3.fromRGB(42, 42, 46)
	local ironDark = Color3.fromRGB(28, 28, 32)
	local wood = Color3.fromRGB(92, 64, 40)
	local woodDark = Color3.fromRGB(70, 48, 30)

	-- Naval truck carriage (two cheeks + bed)
	part({
		Name = "Bed",
		Parent = model,
		Size = Vector3.new(3.2, 0.7, 5.2),
		CFrame = baseCf * CFrame.new(0, 0.55, 0.3),
		Color = wood,
		Material = Enum.Material.Wood,
	})
	for _, side in { -1.55, 1.55 } do
		part({
			Name = "Cheek",
			Parent = model,
			Size = Vector3.new(0.55, 2.4, 5.6),
			CFrame = baseCf * CFrame.new(side, 1.5, 0.15),
			Color = woodDark,
			Material = Enum.Material.Wood,
		})
		-- Cap square
		part({
			Name = "CapSquare",
			Parent = model,
			Size = Vector3.new(0.7, 0.45, 0.9),
			CFrame = baseCf * CFrame.new(side, 2.55, -0.2),
			Color = iron,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end

	-- Axle + trucks (wheels)
	part({
		Name = "Axle",
		Parent = model,
		Size = Vector3.new(5.2, 0.45, 0.45),
		CFrame = baseCf * CFrame.new(0, 1.05, 1.1),
		Color = ironDark,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	for _, side in { -2.35, 2.35 } do
		part({
			Name = "Truck",
			Parent = model,
			Size = Vector3.new(0.55, 2.6, 2.6),
			CFrame = baseCf * CFrame.new(side, 1.15, 1.1) * CFrame.Angles(0, 0, math.rad(90)),
			Color = woodDark,
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Cylinder,
		})
		part({
			Name = "TireBand",
			Parent = model,
			Size = Vector3.new(0.2, 2.85, 2.85),
			CFrame = baseCf * CFrame.new(side, 1.15, 1.1) * CFrame.Angles(0, 0, math.rad(90)),
			Color = iron,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		})
	end
	-- Smaller rear trucks
	for _, side in { -2.1, 2.1 } do
		part({
			Name = "RearTruck",
			Parent = model,
			Size = Vector3.new(0.45, 2.0, 2.0),
			CFrame = baseCf * CFrame.new(side, 0.95, -1.6) * CFrame.Angles(0, 0, math.rad(90)),
			Color = woodDark,
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Cylinder,
		})
	end

	-- Tapered barrel (cylinder axis = X, aim down local -Z)
	local elev = math.rad(-7)
	local function barrelSeg(name: string, length: number, diameter: number, z: number, y: number, color: Color3)
		part({
			Name = name,
			Parent = model,
			Size = Vector3.new(length, diameter, diameter),
			CFrame = baseCf
				* CFrame.new(0, y, z)
				* CFrame.Angles(elev, 0, 0)
				* CFrame.Angles(0, math.rad(90), 0),
			Color = color,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		})
	end
	barrelSeg("Breech", 2.4, 2.35, 1.4, 2.55, ironDark)
	barrelSeg("Chase", 3.4, 2.05, -0.9, 2.7, iron)
	barrelSeg("Muzzle", 2.2, 1.75, -3.5, 2.9, iron)
	barrelSeg("MuzzleSwell", 0.7, 2.05, -4.7, 3.0, ironDark)

	-- Cascabel
	part({
		Name = "Cascabel",
		Parent = model,
		Size = Vector3.new(0.9, 0.9, 0.9),
		CFrame = baseCf * CFrame.new(0, 2.45, 2.7) * CFrame.Angles(elev, 0, 0),
		Color = ironDark,
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
	})
	-- Trunnions
	part({
		Name = "Trunnions",
		Parent = model,
		Size = Vector3.new(4.2, 0.55, 0.55),
		CFrame = baseCf * CFrame.new(0, 2.55, -0.15),
		Color = iron,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	-- Quoin (elevation wedge)
	part({
		Name = "Quoin",
		Parent = model,
		Size = Vector3.new(1.4, 0.55, 1.8),
		CFrame = baseCf * CFrame.new(0, 1.85, 1.5) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = wood,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- Loose shot beside the truck
	local ballOffsets = {
		Vector3.new(3.0, 0.7, 1.2),
		Vector3.new(3.5, 0.7, 0.6),
		Vector3.new(3.2, 0.7, 0.1),
		Vector3.new(3.25, 1.25, 0.7),
	}
	for i, off in ballOffsets do
		part({
			Name = "Shot" .. i,
			Parent = model,
			Size = Vector3.new(1.05, 1.05, 1.05),
			CFrame = baseCf * CFrame.new(off),
			Color = ironDark,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Ball,
			CanCollide = false,
		})
	end

	return model
end

local function buildMiniIsland(parent: Instance, position: Vector3, footprint: Vector3, yawDegrees: number?)
	local yaw = math.rad(yawDegrees or 0)
	local island = Instance.new("Model")
	island.Name = "MiniIsland"
	island.Parent = parent

	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local sx, sy, sz = footprint.X, footprint.Y, footprint.Z

	-- Submerged shelf
	part({
		Name = "ReefShelf",
		Parent = island,
		Size = Vector3.new(sx * 1.35, sy * 0.7, sz * 1.35),
		CFrame = cf * CFrame.new(0, -sy * 0.55, 0),
		Color = Color3.fromRGB(55, 85, 78),
		Material = Enum.Material.Slate,
		CanCollide = false,
	})
	-- Main sand body (slightly irregular stack)
	part({
		Name = "SandCore",
		Parent = island,
		Size = Vector3.new(sx, sy, sz),
		CFrame = cf,
		Color = Color3.fromRGB(216, 196, 155),
		Material = Enum.Material.Sand,
		CanCollide = false,
	})
	part({
		Name = "SandRise",
		Parent = island,
		Size = Vector3.new(sx * 0.62, sy * 0.55, sz * 0.7),
		CFrame = cf * CFrame.new(sx * 0.08, sy * 0.35, -sz * 0.05),
		Color = Color3.fromRGB(228, 208, 168),
		Material = Enum.Material.Sand,
		CanCollide = false,
	})
	-- Beach spit toward the pier
	part({
		Name = "Spit",
		Parent = island,
		Size = Vector3.new(sx * 0.45, sy * 0.35, sz * 0.9),
		CFrame = cf * CFrame.new(0, -sy * 0.15, sz * 0.35) * CFrame.Angles(math.rad(8), 0, 0),
		Color = Color3.fromRGB(232, 214, 175),
		Material = Enum.Material.Sand,
		CanCollide = false,
	})

	-- Scattered rocks
	local rockSpecs = {
		{ Vector3.new(sx * 0.28, sy * 0.5, sz * 0.22), CFrame.new(-sx * 0.32, sy * 0.1, sz * 0.1), Color3.fromRGB(110, 100, 88) },
		{ Vector3.new(sx * 0.2, sy * 0.4, sz * 0.18), CFrame.new(sx * 0.3, sy * 0.05, -sz * 0.15), Color3.fromRGB(95, 90, 80) },
		{ Vector3.new(sx * 0.16, sy * 0.35, sz * 0.14), CFrame.new(-sx * 0.1, sy * 0.2, -sz * 0.28), Color3.fromRGB(125, 112, 96) },
	}
	for i, rock in rockSpecs do
		part({
			Name = "Rock" .. i,
			Parent = island,
			Size = rock[1] :: Vector3,
			CFrame = cf * (rock[2] :: CFrame) * CFrame.Angles(0.2, i * 0.7, 0.15),
			Color = rock[3] :: Color3,
			Material = Enum.Material.Slate,
			CanCollide = false,
		})
	end

	-- Low scrub near palms
	part({
		Name = "Scrub",
		Parent = island,
		Size = Vector3.new(sx * 0.35, 1.2, sz * 0.3),
		CFrame = cf * CFrame.new(sx * 0.15, sy * 0.55, sz * 0.05),
		Color = Color3.fromRGB(62, 100, 55),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})

	local top = position + Vector3.new(0, sy * 0.55, 0)
	local palmScale = math.clamp(0.55 + sx / 55, 0.55, 1.15)
	buildPalm(island, top + Vector3.new(-sx * 0.08, 0, 0), palmScale)
	if sx > 18 then
		buildPalm(island, top + Vector3.new(sx * 0.2, 0, sz * 0.12), palmScale * 0.78)
	end
	if sx > 26 then
		buildPalm(island, top + Vector3.new(-sx * 0.18, 0, -sz * 0.12), palmScale * 0.7)
	end

	return island
end

-- SOLAS-style lifebuoy lying flat on the deck: a smooth round tube banded
-- white/orange, wrapped with rope lashings and a drooping grab line.
local function buildFloatie(parent: Instance, position: Vector3, yawDegrees: number?, scale: number?)
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Floatie"
	model.Parent = parent

	local yaw = math.rad(yawDegrees or 0)
	-- Lay it flat on the deck, with a tiny natural tilt so it reads as "dropped there"
	local tilt = math.rad((math.noise(position.X * 0.11, position.Z * 0.11)) * 6)
	local baseCf = CFrame.new(position) * CFrame.Angles(0, yaw, tilt)

	local ringRadius = 2.2 * s
	local tubeDia = 0.82 * s
	local segments = 16
	local white = Color3.fromRGB(240, 238, 231)
	local orange = Color3.fromRGB(230, 92, 36)

	-- Smooth torus tube: tangential cylinder segments overlapped so the ring
	-- reads as one continuous rounded float instead of a bead necklace.
	local segLen = (2 * math.pi * ringRadius / segments) * 1.35
	for i = 0, segments - 1 do
		local ang = (i / segments) * math.pi * 2
		local localPos = Vector3.new(math.cos(ang) * ringRadius, 0, math.sin(ang) * ringRadius)
		local tangent = Vector3.new(-math.sin(ang), 0, math.cos(ang))
		-- Four painted quadrants alternate white / orange like a real lifebuoy
		local quarter = math.floor((i / segments) * 4)
		local color = if quarter % 2 == 0 then white else orange
		part({
			Name = "Tube" .. i,
			Parent = model,
			Size = Vector3.new(segLen, tubeDia, tubeDia),
			CFrame = baseCf * CFrame.fromMatrix(localPos, tangent, Vector3.yAxis),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.05,
			CanCollide = false,
			Shape = Enum.PartType.Cylinder,
		})
		-- Rounded ball caps hide the seams between straight cylinder chords.
		part({
			Name = "Joint" .. i,
			Parent = model,
			Size = Vector3.new(tubeDia, tubeDia, tubeDia),
			CFrame = baseCf * CFrame.new(localPos),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.05,
			CanCollide = false,
			Shape = Enum.PartType.Ball,
		})
	end

	-- Four rope lashings wrapped over the tube at the tie-off points.
	local rope = Color3.fromRGB(206, 186, 138)
	for i = 0, 3 do
		local ang = (i / 4) * math.pi * 2 + math.pi / 8
		local localPos = Vector3.new(math.cos(ang) * ringRadius, 0, math.sin(ang) * ringRadius)
		local tangent = Vector3.new(-math.sin(ang), 0, math.cos(ang))
		part({
			Name = "Lash" .. i,
			Parent = model,
			Size = Vector3.new(0.26 * s, tubeDia * 1.28, tubeDia * 1.28),
			CFrame = baseCf * CFrame.fromMatrix(localPos, tangent, Vector3.yAxis),
			Color = rope,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			Shape = Enum.PartType.Cylinder,
		})
	end

	-- Grab line draped between the lashings, sagging outward off the ring.
	local grabRadius = ringRadius + tubeDia * 0.55
	local droopSpans = 4
	local perSpan = 2
	-- A point along the sagging span at parameter t, bulging outward at the middle.
	local function ropePoint(a0: number, a1: number, t: number): Vector3
		local a = a0 + (a1 - a0) * t
		local sag = math.sin(t * math.pi) * (0.5 * s)
		local r = grabRadius + sag
		return Vector3.new(math.cos(a) * r, -0.04 * s, math.sin(a) * r)
	end
	for span = 0, droopSpans - 1 do
		local a0 = (span / droopSpans) * math.pi * 2 + math.pi / 8
		local a1 = ((span + 1) / droopSpans) * math.pi * 2 + math.pi / 8
		for j = 0, perSpan - 1 do
			local t0 = j / perSpan
			local t1 = (j + 1) / perSpan
			local p0 = ropePoint(a0, a1, t0)
			local p1 = ropePoint(a0, a1, t1)
			local mid = (p0 + p1) * 0.5
			local dir = (p1 - p0)
			local len = dir.Magnitude
			part({
				Name = "Grab" .. span .. "_" .. j,
				Parent = model,
				Size = Vector3.new(math.max(len, 0.05), 0.16 * s, 0.16 * s),
				CFrame = baseCf * CFrame.fromMatrix(mid, dir.Unit, Vector3.yAxis),
				Color = rope,
				Material = Enum.Material.Fabric,
				CanCollide = false,
				Shape = Enum.PartType.Cylinder,
			})
		end
	end

	return model
end

-- Realistic standing-water puddle: a soaked-in damp stain on the planks, a thin
-- glassy sky-reflecting water surface, and a soft bright meniscus around the rim
-- so it reads as real standing water catching the light.
local function buildPuddle(parent: Instance, center: Vector3, radius: number)
	local model = Instance.new("Model")
	model.Name = "Puddle"
	model.Parent = parent

	-- A few overlapping flat blobs give an irregular, natural puddle outline.
	local blobs = {
		{ Vector3.new(0, 0, 0), 1.0 },
		{ Vector3.new(radius * 0.5, 0, radius * 0.28), 0.6 },
		{ Vector3.new(-radius * 0.44, 0, radius * 0.4), 0.54 },
		{ Vector3.new(radius * 0.12, 0, -radius * 0.48), 0.46 },
	}

	for i, blob in blobs do
		local off = blob[1] :: Vector3
		local scale = blob[2] :: number
		local w = radius * 2 * scale
		local d = radius * 1.7 * scale

		-- Damp halo: the wood darkened and soaked where water has spread,
		-- slightly larger than the water and flush with the planks.
		part({
			Name = "Damp" .. i,
			Parent = model,
			Size = Vector3.new(w * 1.26, 0.04, d * 1.26),
			CFrame = CFrame.new(center + off + Vector3.new(0, 0.02, 0)),
			Color = Color3.fromRGB(58, 43, 29),
			Material = Enum.Material.WoodPlanks,
			Transparency = 0.4,
			CanCollide = false,
			CastShadow = false,
		})

		-- Water surface: thin, glassy, reflecting the sky with a cool tint. A
		-- little per-blob variance in sheen keeps the surface from looking flat
		-- and uniform, without any per-frame property writes to replicate.
		local sheen = 0.52 + math.noise(off.X * 0.5, off.Z * 0.5) * 0.12
		part({
			Name = "Water" .. i,
			Parent = model,
			Size = Vector3.new(w, 0.06, d),
			CFrame = CFrame.new(center + off + Vector3.new(0, 0.05, 0)),
			Color = Color3.fromRGB(96, 132, 148),
			Material = Enum.Material.Glass,
			Transparency = 0.16,
			Reflectance = math.clamp(sheen, 0.45, 0.66),
			CanCollide = false,
			CastShadow = false,
		})
	end

	-- Bright meniscus ring around the main blob: a thin wet lip where surface
	-- tension catches the sky, which sells it as standing water rather than paint.
	part({
		Name = "Meniscus",
		Parent = model,
		Size = Vector3.new(radius * 2.06, 0.05, radius * 1.76),
		CFrame = CFrame.new(center + Vector3.new(0, 0.045, 0)),
		Color = Color3.fromRGB(176, 200, 208),
		Material = Enum.Material.Glass,
		Transparency = 0.62,
		Reflectance = 0.35,
		CanCollide = false,
		CastShadow = false,
	})

	return model
end

-- Simple flag on a tall pole with a gentle wave.
local function buildFlag(parent: Instance, position: Vector3, yawDegrees: number?)
	local model = Instance.new("Model")
	model.Name = "Flag"
	model.Parent = parent

	local yaw = math.rad(yawDegrees or 0)
	local baseCf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)

	part({
		Name = "PoleBase",
		Parent = model,
		Size = Vector3.new(2.2, 0.6, 2.2),
		CFrame = baseCf * CFrame.new(0, 0.3, 0),
		Color = Color3.fromRGB(70, 48, 30),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	part({
		Name = "Pole",
		Parent = model,
		Size = Vector3.new(0.55, 24, 0.55),
		CFrame = baseCf * CFrame.new(0, 12, 0),
		Color = Color3.fromRGB(120, 96, 62),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part({
		Name = "Finial",
		Parent = model,
		Size = Vector3.new(1.1, 1.1, 1.1),
		CFrame = baseCf * CFrame.new(0, 24.2, 0),
		Color = Color3.fromRGB(220, 190, 110),
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
	})

	local flag = part({
		Name = "Cloth",
		Parent = model,
		Size = Vector3.new(0.3, 4.5, 8),
		CFrame = baseCf * CFrame.new(0, 21, 4.2),
		Color = Config.Berth.Purple,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})

	-- Client-driven wave (see LobbyWorld.Tags).
	flag:SetAttribute("PhaseSeed", (position.X + position.Z) * 0.05)
	CollectionService:AddTag(flag, LobbyWorld.Tags.Flag)

	return model
end

-- Simple objective sign posted on a wooden board (readable text on the sign face).
local function buildObjectiveSign(parent: Instance, position: Vector3, yawDegrees: number?)
	local model = Instance.new("Model")
	model.Name = "ObjectiveSign"
	model.Parent = parent

	local yaw = math.rad(yawDegrees or 0)
	local baseCf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)

	for _, side in { -3.2, 3.2 } do
		part({
			Name = "Post",
			Parent = model,
			Size = Vector3.new(0.7, 9, 0.7),
			CFrame = baseCf * CFrame.new(side, 4.5, 0),
			Color = Color3.fromRGB(88, 60, 36),
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	local board = part({
		Name = "Board",
		Parent = model,
		Size = Vector3.new(9, 5, 0.5),
		CFrame = baseCf * CFrame.new(0, 8, 0),
		Color = Color3.fromRGB(150, 110, 68),
		Material = Enum.Material.WoodPlanks,
	})

	-- Header trim strip so the sign reads clearly from the spawn
	part({
		Name = "TrimTop",
		Parent = model,
		Size = Vector3.new(9.6, 0.6, 0.7),
		CFrame = baseCf * CFrame.new(0, 10.7, 0),
		Color = Color3.fromRGB(112, 78, 46),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	local surface = Instance.new("SurfaceGui")
	surface.Name = "ObjectiveFace"
	surface.Adornee = board
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(360, 200)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.Parent = board

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(244, 234, 210)
	bg.BorderSizePixel = 0
	bg.Parent = surface

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = bg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bg

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 44)
	header.Font = Enum.Font.GothamBold
	header.Text = "OBJECTIVE"
	header.TextColor3 = Color3.fromRGB(196, 82, 40)
	header.TextScaled = true
	header.LayoutOrder = 1
	header.Parent = bg

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 110)
	body.Font = Enum.Font.GothamMedium
	body.Text = "Board a portal, gather your crew,\nand set sail to survive at sea."
	body.TextColor3 = Color3.fromRGB(48, 42, 34)
	body.TextWrapped = true
	body.TextScaled = true
	body.LayoutOrder = 2
	body.Parent = bg

	local bodyConstraint = Instance.new("UITextSizeConstraint")
	bodyConstraint.MaxTextSize = 26
	bodyConstraint.Parent = body

	return model
end

-- A small, eye-level placard along the walkway that spells out the objective
-- in one short paragraph. Sized so players can stroll right up and read it.
local function buildObjectiveBillboard(parent: Instance, position: Vector3, yawDegrees: number?)
	local model = Instance.new("Model")
	model.Name = "ObjectiveBillboard"
	model.Parent = parent

	local yaw = math.rad(yawDegrees or 0)
	local baseCf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)

	-- Single stout post
	part({
		Name = "Post",
		Parent = model,
		Size = Vector3.new(0.5, 3.4, 0.5),
		CFrame = baseCf * CFrame.new(0, 1.7, 0),
		Color = Color3.fromRGB(88, 60, 36),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- Compact board tilted back a touch so it reads while walking past
	local board = part({
		Name = "Board",
		Parent = model,
		Size = Vector3.new(4.6, 2.4, 0.28),
		CFrame = baseCf * CFrame.new(0, 4, 0) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = Color3.fromRGB(150, 110, 68),
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
	})

	-- Thin frame trim around the board face
	part({
		Name = "FrameTop",
		Parent = model,
		Size = Vector3.new(5.0, 0.28, 0.34),
		CFrame = baseCf * CFrame.new(0, 5.22, 0) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = Color3.fromRGB(108, 74, 44),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part({
		Name = "FrameBottom",
		Parent = model,
		Size = Vector3.new(5.0, 0.28, 0.34),
		CFrame = baseCf * CFrame.new(0, 2.78, 0) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = Color3.fromRGB(108, 74, 44),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	local surface = Instance.new("SurfaceGui")
	surface.Name = "ObjectiveFace"
	surface.Adornee = board
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(460, 240)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.Parent = board

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(246, 238, 216)
	bg.BorderSizePixel = 0
	bg.Parent = surface

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 22)
	pad.PaddingRight = UDim.new(0, 22)
	pad.Parent = bg

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.Font = Enum.Font.GothamMedium
	body.Text = "Gather your crew and board a portal boat. Set sail together and survive the open sea."
	body.TextColor3 = Color3.fromRGB(48, 42, 34)
	body.TextWrapped = true
	body.TextScaled = true
	body.Parent = bg

	local bodyConstraint = Instance.new("UITextSizeConstraint")
	bodyConstraint.MaxTextSize = 34
	bodyConstraint.Parent = body

	return model
end

-- Deck dressing: floaties, puddles, a flag, and the objective sign on the pier.
local function buildDeckDressing(parent: Instance)
	-- Lifeguard floaties laying on the deck (clear of the berth row at z≈68)
	local floaties = {
		{ Vector3.new(-24, PIER.DeckY, -18), 20, 1.0 },
		{ Vector3.new(22, PIER.DeckY, 4), -35, 0.95 },
		{ Vector3.new(-12, PIER.DeckY, 30), 65, 1.05 },
	}
	for _, f in floaties do
		buildFloatie(parent, f[1] :: Vector3, f[2] :: number, f[3] :: number)
	end

	-- Realistic standing-water puddles scattered across the planks
	local puddles = {
		{ Vector3.new(8, PIER.DeckY, -20), 3.2 },
		{ Vector3.new(-18, PIER.DeckY, 12), 2.6 },
		{ Vector3.new(16, PIER.DeckY, 34), 3.6 },
		{ Vector3.new(-6, PIER.DeckY, -4), 2.2 },
	}
	for _, p in puddles do
		buildPuddle(parent, p[1] :: Vector3, p[2] :: number)
	end

	-- A flag near the front corner of the pier
	buildFlag(parent, Vector3.new(-30, PIER.DeckY, -34), 25)

	-- Objective board mounted along the STARBOARD (right) side of the walkway,
	-- facing inward toward the deck, so players read it from the side as they
	-- head for the portals instead of it sitting behind them at the bow. Clear of
	-- the side cannons (z≈8/42) and the starboard barrels (z≈-30..-22).
	buildObjectiveSign(parent, Vector3.new(30, PIER.DeckY, 16), 270)

	-- Matching walk-by placard along the PORT (left) side, facing inward so the
	-- objective reads clearly from either side of the deck.
	buildObjectiveBillboard(parent, Vector3.new(-31, PIER.DeckY, 28), 90)
end

local function buildScenery(root: Folder)
	local existing = root:FindFirstChild("Scenery")
	if existing then
		existing:Destroy()
	end

	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = root

	-- No palms on the pier deck — keep the boarding ship clear (island palms only)

	-- Deck cannons aimed OUTWARD, inset from rails so they don't clip
	local cannons = {
		{ Vector3.new(-32, PIER.DeckY, 8), -90 },
		{ Vector3.new(-32, PIER.DeckY, 42), -90 },
		{ Vector3.new(32, PIER.DeckY, 8), 90 },
		{ Vector3.new(32, PIER.DeckY, 42), 90 },
		{ Vector3.new(-16, PIER.DeckY, -36), 0 },
		{ Vector3.new(16, PIER.DeckY, -36), 0 },
	}
	for _, c in cannons do
		buildCannon(scenery, c[1] :: Vector3, c[2] :: number)
	end

	-- Boats well clear of the berth row (z≈68) — three centered portals
	local boats = {
		{ Vector3.new(-70, 1.4, 5), 25, Color3.fromRGB(160, 90, 50) },
		{ Vector3.new(-78, 1.2, 40), -15, Color3.fromRGB(70, 95, 120) },
		{ Vector3.new(72, 1.3, 8), -155, Color3.fromRGB(145, 75, 55) },
		{ Vector3.new(80, 1.2, 45), 165, Color3.fromRGB(180, 140, 70) },
		{ Vector3.new(-75, 1.1, 110), 10, Color3.fromRGB(95, 70, 45) },
		{ Vector3.new(78, 1.15, 115), -170, Color3.fromRGB(55, 85, 100) },
	}
	for _, b in boats do
		buildBoat(scenery, b[1] :: Vector3, b[2] :: number, b[3] :: Color3)
	end

	-- Mini islands in the distance (scenery only — layered sand/rock, not walkable)
	local islands = {
		{ Vector3.new(-140, -1.2, 20), Vector3.new(34, 5.5, 24), 18 },
		{ Vector3.new(145, -1.0, 45), Vector3.new(38, 6, 26), -22 },
		{ Vector3.new(-120, -1.4, -70), Vector3.new(28, 5, 20), 42 },
		{ Vector3.new(125, -1.3, -55), Vector3.new(30, 5.2, 22), -48 },
		{ Vector3.new(-155, -0.9, 95), Vector3.new(32, 5.4, 22), 10 },
		{ Vector3.new(160, -1.1, 110), Vector3.new(36, 5.8, 24), -14 },
		{ Vector3.new(-95, -1.5, 150), Vector3.new(26, 4.8, 18), 28 },
		{ Vector3.new(100, -1.4, 155), Vector3.new(27, 5, 19), -32 },
		{ Vector3.new(0, -1.6, -130), Vector3.new(42, 6.5, 28), 6 },
		{ Vector3.new(-180, -1.2, 40), Vector3.new(22, 4.5, 16), 55 },
		{ Vector3.new(185, -1.2, 25), Vector3.new(24, 4.6, 17), -40 },
		{ Vector3.new(-70, -1.8, -110), Vector3.new(20, 4.2, 15), 70 },
		{ Vector3.new(80, -1.7, -120), Vector3.new(21, 4.3, 15), -65 },
	}
	for _, isle in islands do
		buildMiniIsland(scenery, isle[1] :: Vector3, isle[2] :: Vector3, isle[3] :: number)
	end

	-- Deck props: floaties, puddles, flag, and the objective sign
	buildDeckDressing(scenery)
end

local function clearPathwayMarkers(root: Folder)
	-- Strip leftover path stripes, foam runways, and red buoy “blocks” near berths
	local killNames = {
		CenterPlank = true,
		GuidePlank = true,
		GuideTip = true,
		Foam = true,
		Arrow = true,
	}
	for _, child in root:GetDescendants() do
		if child:IsA("BasePart") then
			local name = child.Name
			if
				killNames[name]
				or string.sub(name, 1, 5) == "Arrow"
				or string.sub(name, 1, 4) == "Buoy"
				or string.sub(name, 1, 9) == "PlankWear"
				or name == "RopePost"
				or name == "PostWrap"
				or string.find(string.lower(name), "path", 1, true)
			then
				child:Destroy()
				continue
			end
			local size = child.Size
			local flat = size.Y <= 2.5 and (size.X >= 5 or size.Z >= 5)
			if flat and child.Parent and child.Parent.Name ~= "Barriers" and child.Name ~= "PierDeck" and child.Name ~= "Pad" then
				local c = child.Color
				local isCyan = c.G > 0.45 and c.B > 0.55 and c.R < 0.55
				local isHotRed = c.R > 0.65 and c.G < 0.4 and c.B < 0.4
				if (isCyan or isHotRed) and child.Material ~= Enum.Material.WoodPlanks then
					child:Destroy()
				end
			end
			-- Tall red buoy-like blocks near the berth row
			local pos = child.Position
			if pos.Z > 45 and pos.Z < 95 and math.abs(pos.X) < 100 then
				local c = child.Color
				local isHotRed = c.R > 0.65 and c.G < 0.45 and c.B < 0.45
				if isHotRed and child.Material == Enum.Material.SmoothPlastic and size.Y >= 4 then
					child:Destroy()
				end
			end
		end
	end
end

local function hideVoyageStagingBoat(root: Folder)
	-- Keep an invisible teleport pad for launch fallback; remove the huge visible boat
	local staging = root:FindFirstChild("VoyageStaging")
	if staging then
		staging:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "VoyageStaging"
	folder.Parent = root
	part({
		Name = "Pad",
		Parent = folder,
		Size = Vector3.new(48, 1, 48),
		CFrame = CFrame.new(0, 4, 620),
		Transparency = 1,
		CanCollide = true,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 255, 255),
	})
end

local function buildDock(root: Folder)
	local dock = Instance.new("Folder")
	dock.Name = "Dock"
	dock.Parent = root

	-- ============================================================
	--  Pirate galleon "Sea Wraith" — the boarding ship.
	--  Replaces the old flat pier. The walkable deck top stays at
	--  PIER.DeckY (3.5) so spawn, portals and barriers still line up;
	--  everything else (hull, bulwarks, masts, stern) is dressed around it.
	--  Bow points toward -Z, transom (stern) toward +Z.
	-- ============================================================
	local DECK_TOP = PIER.DeckY

	-- Weathered-wood + canvas palette
	local hullWood = Color3.fromRGB(84, 56, 36)
	local hullDark = Color3.fromRGB(58, 38, 24)
	local plankWood = Color3.fromRGB(122, 86, 52)
	local plankDark = Color3.fromRGB(96, 66, 40)
	local trimWood = Color3.fromRGB(74, 50, 30)
	local sailCanvas = Color3.fromRGB(234, 226, 206)
	local sailShade = Color3.fromRGB(206, 196, 174)
	local goldCol = Color3.fromRGB(206, 168, 92)
	local ironCol = Color3.fromRGB(38, 34, 32)
	local ropeCol = Config.Theme.Rope

	local Z_BOW, Z_STERN = -58, 90

	-- Half-beam (hull half-width) as a function of length: point at the bow,
	-- full amidships, narrowing again toward the transom.
	local function halfBeamAt(z: number): number
		if z <= -50 then
			local a = math.clamp((z + 58) / 8, 0, 1)
			return 5 + a * 34
		elseif z >= 68 then
			local a = math.clamp((z - 68) / 22, 0, 1)
			return 39 - a * 15
		end
		return 39
	end

	-- Vertical cylinder helper (default cylinder axis is +X, tip it upright).
	local function cylV(name: string, pos: Vector3, height: number, dia: number, color: Color3, mat: Enum.Material, collide: boolean?)
		part({
			Name = name,
			Parent = dock,
			Size = Vector3.new(height, dia, dia),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = mat,
			CanCollide = collide or false,
			Shape = Enum.PartType.Cylinder,
		})
	end

	-- Straight rope/spar segment between two world points (square section).
	local function ropeSeg(name: string, p0: Vector3, p1: Vector3, dia: number, color: Color3?)
		local dir = p1 - p0
		local len = dir.Magnitude
		if len < 0.05 then
			return
		end
		part({
			Name = name,
			Parent = dock,
			Size = Vector3.new(dia, dia, len),
			CFrame = CFrame.lookAt((p0 + p1) * 0.5, p1),
			Color = color or ropeCol,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			CastShadow = false,
		})
	end

	-- Main walkable deck (kept named "PierDeck" for downstream polish logic).
	part({
		Name = "PierDeck",
		Parent = dock,
		Size = Vector3.new(80, 3, 140),
		CFrame = CFrame.new(0, 2, 20),
		Color = plankWood,
		Material = Enum.Material.WoodPlanks,
	})
	-- Deck seam lines for a finished, planked look.
	for _, sx in { -30, -18, -6, 6, 18, 30 } do
		part({
			Name = "DeckSeam",
			Parent = dock,
			Size = Vector3.new(0.35, 0.15, 136),
			CFrame = CFrame.new(sx, 3.55, 20),
			Color = plankDark,
			Material = Enum.Material.Wood,
			CanCollide = false,
			CastShadow = false,
		})
	end

	-- Hull: tapered planked sides + rub-rail wales, curving in plan.
	for z = Z_BOW, Z_STERN, 6 do
		local hb = halfBeamAt(z)
		local hbNext = halfBeamAt(z + 6)
		for _, s in { -1, 1 } do
			local yaw = math.atan2((hbNext - hb) * s, 6)
			-- upper strake (slight tumblehome — top leans inboard)
			part({
				Name = "HullUpper",
				Parent = dock,
				Size = Vector3.new(2.4, 7.5, 7),
				CFrame = CFrame.new(s * hb, 0.2, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(7) * s),
				Color = hullWood,
				Material = Enum.Material.Wood,
				CanCollide = false,
				CastShadow = false,
			})
			-- lower strake / turn of the bilge (rolls in toward the keel)
			part({
				Name = "HullLower",
				Parent = dock,
				Size = Vector3.new(2.2, 8, 7),
				CFrame = CFrame.new(s * hb * 0.7, -6.2, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(32) * s),
				Color = hullDark,
				Material = Enum.Material.Wood,
				CanCollide = false,
				CastShadow = false,
			})
			-- upper + lower wales (horizontal rub rails)
			part({
				Name = "Wale",
				Parent = dock,
				Size = Vector3.new(0.9, 1.1, 7),
				CFrame = CFrame.new(s * (hb + 0.4), 2.4, z) * CFrame.Angles(0, yaw, 0),
				Color = trimWood,
				Material = Enum.Material.Wood,
				CanCollide = false,
				CastShadow = false,
			})
			part({
				Name = "Wale",
				Parent = dock,
				Size = Vector3.new(0.8, 0.9, 7),
				CFrame = CFrame.new(s * (hb + 0.2), -1.6, z) * CFrame.Angles(0, yaw, 0),
				Color = trimWood,
				Material = Enum.Material.Wood,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end

	part({
		Name = "Keel",
		Parent = dock,
		Size = Vector3.new(2.6, 2.4, 150),
		CFrame = CFrame.new(0, -10.5, 16),
		Color = hullDark,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- Bulwarks (ship sides above the deck) + cap rail, hugging the hull curve.
	for z = Z_BOW + 2, 66, 6 do
		local hb = halfBeamAt(z)
		local hbNext = halfBeamAt(z + 6)
		for _, s in { -1, 1 } do
			local yaw = math.atan2((hbNext - hb) * s, 6)
			part({
				Name = "Bulwark",
				Parent = dock,
				Size = Vector3.new(1.3, 5.2, 7),
				CFrame = CFrame.new(s * (hb - 0.6), 6.1, z) * CFrame.Angles(0, yaw, 0),
				Color = plankWood,
				Material = Enum.Material.WoodPlanks,
				CanCollide = true,
			})
			part({
				Name = "CapRail",
				Parent = dock,
				Size = Vector3.new(2.1, 0.6, 7),
				CFrame = CFrame.new(s * (hb - 0.6), 8.9, z) * CFrame.Angles(0, yaw, 0),
				Color = trimWood,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
	end

	-- Open gun ports along the sides, lined up with the deck cannons.
	for _, gz in { 8, 42 } do
		local hb = halfBeamAt(gz)
		for _, s in { -1, 1 } do
			part({
				Name = "GunPort",
				Parent = dock,
				Size = Vector3.new(0.7, 2.2, 2.6),
				CFrame = CFrame.new(s * (hb + 0.2), 6.0, gz),
				Color = ironCol,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
	end

	-- Bow: stem post, converging prow planks, gilded figurehead, bowsprit + jib.
	part({
		Name = "Stem",
		Parent = dock,
		Size = Vector3.new(2.6, 15, 6),
		CFrame = CFrame.new(0, 1.5, -59) * CFrame.Angles(math.rad(-18), 0, 0),
		Color = hullDark,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	for _, s in { -1, 1 } do
		local p0 = Vector3.new(s * 33, 6, -50)
		local p1 = Vector3.new(0, 6, -60)
		part({
			Name = "BowPlank",
			Parent = dock,
			Size = Vector3.new(1.4, 6, (p1 - p0).Magnitude + 1),
			CFrame = CFrame.lookAt((p0 + p1) * 0.5, p1),
			Color = plankWood,
			Material = Enum.Material.WoodPlanks,
			CanCollide = false,
		})
	end
	part({
		Name = "FigureBody",
		Parent = dock,
		Size = Vector3.new(2.2, 3.2, 2.2),
		CFrame = CFrame.new(0, 2.6, -62) * CFrame.Angles(math.rad(22), 0, 0),
		Color = goldCol,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	part({
		Name = "FigureHead",
		Parent = dock,
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(0, 4.6, -63),
		Color = goldCol,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Shape = Enum.PartType.Ball,
	})
	for _, s in { -1, 1 } do
		part({
			Name = "FigureWing",
			Parent = dock,
			Size = Vector3.new(0.4, 1.6, 3.2),
			CFrame = CFrame.new(s * 1.3, 3.0, -62) * CFrame.Angles(0, math.rad(s * 30), math.rad(s * 18)),
			Color = goldCol,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
	local bowspritBase = Vector3.new(0, 7, -56)
	local bowspritTip = Vector3.new(0, 13, -74)
	part({
		Name = "Bowsprit",
		Parent = dock,
		Size = Vector3.new(1.2, 1.2, (bowspritTip - bowspritBase).Magnitude),
		CFrame = CFrame.lookAt((bowspritBase + bowspritTip) * 0.5, bowspritTip),
		Color = trimWood,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part({
		Name = "JibSail",
		Parent = dock,
		Size = Vector3.new(0.3, 8, 10),
		CFrame = CFrame.new(0, 10, -66) * CFrame.Angles(0, math.rad(90), math.rad(20)),
		Color = sailCanvas,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})

	-- Masts: fore + main, each with square sails, a cap, and shroud rigging.
	local function buildMast(zPos: number, mastHeight: number, yards, withNest: boolean?): number
		local baseY = DECK_TOP
		local topY = baseY + mastHeight
		cylV("Mast", Vector3.new(0, baseY + mastHeight * 0.34, zPos), mastHeight * 0.68, 2.3, trimWood, Enum.Material.Wood, true)
		cylV("MastTopSeg", Vector3.new(0, baseY + mastHeight * 0.78, zPos), mastHeight * 0.48, 1.5, trimWood, Enum.Material.Wood, true)
		part({
			Name = "MastCap",
			Parent = dock,
			Size = Vector3.new(1.3, 1.3, 1.3),
			CFrame = CFrame.new(0, topY, zPos),
			Color = goldCol,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Shape = Enum.PartType.Ball,
		})

		if withNest then
			local nestY = baseY + mastHeight * 0.72
			part({ Name = "CrowsNest", Parent = dock, Size = Vector3.new(6, 0.6, 6), CFrame = CFrame.new(0, nestY, zPos), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
			for _, dz in { -3, 3 } do
				part({ Name = "CrowsNestRail", Parent = dock, Size = Vector3.new(6.2, 1.6, 0.4), CFrame = CFrame.new(0, nestY + 0.9, zPos + dz), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
			end
		end

		for _, y in yards do
			local yardY = baseY + y.h
			part({ Name = "Yard", Parent = dock, Size = Vector3.new(y.len, 0.9, 0.9), CFrame = CFrame.new(0, yardY, zPos), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false, Shape = Enum.PartType.Cylinder })
			part({ Name = "Sail", Parent = dock, Size = Vector3.new(y.sailW, y.sailH, 0.35), CFrame = CFrame.new(0, yardY - y.sailH / 2 - 0.5, zPos + 0.4) * CFrame.Angles(math.rad(-3), 0, 0), Color = sailCanvas, Material = Enum.Material.Fabric, CanCollide = false })
			part({ Name = "SailBand", Parent = dock, Size = Vector3.new(y.sailW, 1.1, 0.4), CFrame = CFrame.new(0, yardY - y.sailH + 0.6, zPos + 0.45), Color = sailShade, Material = Enum.Material.Fabric, CanCollide = false })
		end

		local hb = halfBeamAt(zPos)
		for _, s in { -1, 1 } do
			for _, dz in { -6, 0, 6 } do
				ropeSeg("Shroud", Vector3.new(0, topY - 5, zPos), Vector3.new(s * (hb - 0.8), 9, zPos + dz), 0.2)
			end
		end
		return topY
	end

	local foreTop = buildMast(-18, 42, { { h = 20, len = 34, sailW = 30, sailH = 13 }, { h = 32, len = 24, sailW = 21, sailH = 9 } }, false)
	local mainTop = buildMast(28, 50, { { h = 22, len = 40, sailW = 36, sailH = 15 }, { h = 37, len = 28, sailW = 25, sailH = 11 } }, true)

	-- Standing rigging tying bow → foremast → mainmast → stern.
	ropeSeg("Forestay", bowspritTip, Vector3.new(0, foreTop - 3, -18), 0.22)
	ropeSeg("Stay", Vector3.new(0, foreTop - 3, -18), Vector3.new(0, mainTop - 4, 28), 0.22)
	ropeSeg("Backstay", Vector3.new(0, mainTop - 4, 28), Vector3.new(0, 12, 84), 0.22)

	-- Jolly Roger flying beside the mainmast head.
	part({
		Name = "JollyRoger",
		Parent = dock,
		Size = Vector3.new(0.2, 3.6, 6),
		CFrame = CFrame.new(3.2, mainTop - 2, 28) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(20, 20, 22),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	part({
		Name = "JollySkull",
		Parent = dock,
		Size = Vector3.new(0.25, 1.4, 1.4),
		CFrame = CFrame.new(3.3, mainTop - 2, 28),
		Color = Color3.fromRGB(232, 230, 224),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})

	-- Transom stern with gallery windows, name board and quarter lanterns.
	part({
		Name = "Transom",
		Parent = dock,
		Size = Vector3.new(50, 13, 3),
		CFrame = CFrame.new(0, 6.5, 90) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = hullDark,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part({
		Name = "TransomTrim",
		Parent = dock,
		Size = Vector3.new(52, 1.2, 3.4),
		CFrame = CFrame.new(0, 12.4, 89) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = goldCol,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	for i = -2, 2 do
		part({
			Name = "SternWindow",
			Parent = dock,
			Size = Vector3.new(4.5, 4, 0.6),
			CFrame = CFrame.new(i * 7, 8, 91.2) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = Color3.fromRGB(150, 205, 220),
			Material = Enum.Material.Glass,
			Reflectance = 0.35,
			Transparency = 0.25,
			CanCollide = false,
		})
	end
	local sternName = part({
		Name = "SternName",
		Parent = dock,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 11.6, 92),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	billboard(sternName, "SEA WRAITH", goldCol, UDim2.fromOffset(220, 40), 0, 20)
	for _, s in { -1, 1 } do
		cylV("LanternPost", Vector3.new(s * 21, 12, 88), 4, 0.5, trimWood, Enum.Material.Wood)
		part({ Name = "Lantern", Parent = dock, Size = Vector3.new(2, 3, 2), CFrame = CFrame.new(s * 21, 15, 88), Color = Config.Theme.Lantern, Material = Enum.Material.SmoothPlastic, CanCollide = false })
		part({ Name = "LanternCap", Parent = dock, Size = Vector3.new(2.4, 0.8, 2.4), CFrame = CFrame.new(s * 21, 16.6, 88), Color = ironCol, Material = Enum.Material.Metal, CanCollide = false })
	end

	-- Raised quarterdeck (poop) set well behind the boarding portals (z=68,
	-- pads reach ~z=75), with the ship's wheel. Kept clear of the portal row.
	part({
		Name = "PoopDeck",
		Parent = dock,
		Size = Vector3.new(50, 1.4, 12),
		CFrame = CFrame.new(0, 5.5, 84),
		Color = plankWood,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})
	part({
		Name = "PoopStep",
		Parent = dock,
		Size = Vector3.new(16, 1.2, 3),
		CFrame = CFrame.new(0, 4.5, 77.5),
		Color = plankDark,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})

	local function buildWheel(center: Vector3)
		local r = 2.2
		part({ Name = "Binnacle", Parent = dock, Size = Vector3.new(2.4, 3.2, 2.4), CFrame = CFrame.new(center - Vector3.new(0, 3.4, -0.8)), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
		-- Hub (axis along the fore-aft Z so the wheel faces forward)
		part({ Name = "WheelHub", Parent = dock, Size = Vector3.new(1.1, 1.1, 1.4), CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false, Shape = Enum.PartType.Cylinder })
		local seg = 10
		for i = 0, seg - 1 do
			local a0 = (i / seg) * math.pi * 2
			local a1 = ((i + 1) / seg) * math.pi * 2
			local p0 = center + Vector3.new(math.cos(a0) * r, math.sin(a0) * r, 0)
			local p1 = center + Vector3.new(math.cos(a1) * r, math.sin(a1) * r, 0)
			part({ Name = "WheelRim", Parent = dock, Size = Vector3.new(0.4, 0.4, (p1 - p0).Magnitude), CFrame = CFrame.lookAt((p0 + p1) * 0.5, p1), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
		end
		for i = 0, 5 do
			local a = (i / 6) * math.pi * 2
			local rim = center + Vector3.new(math.cos(a) * r, math.sin(a) * r, 0)
			part({ Name = "WheelSpoke", Parent = dock, Size = Vector3.new(0.35, 0.35, (rim - center).Magnitude + 0.6), CFrame = CFrame.lookAt((center + rim) * 0.5, rim), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
			local handle = center + Vector3.new(math.cos(a) * (r + 0.8), math.sin(a) * (r + 0.8), 0)
			part({ Name = "WheelHandle", Parent = dock, Size = Vector3.new(0.35, 0.35, 1.4), CFrame = CFrame.new(handle) * CFrame.Angles(0, 0, a), Color = goldCol, Material = Enum.Material.Wood, CanCollide = false })
		end
	end
	buildWheel(Vector3.new(0, 8.4, 82))

	-- Working deck dressing (replaces the old floating crate cubes).
	cylV("Capstan", Vector3.new(0, 4.6, 50), 2.6, 3, trimWood, Enum.Material.Wood, true)
	for i = 0, 3 do
		local a = (i / 4) * math.pi * 2
		part({ Name = "CapstanBar", Parent = dock, Size = Vector3.new(0.4, 0.4, 6), CFrame = CFrame.new(0, 5.4, 50) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 3), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
	end
	-- Cargo hatch grating
	part({ Name = "Hatch", Parent = dock, Size = Vector3.new(8, 0.5, 8), CFrame = CFrame.new(-2, 3.75, 10), Color = plankDark, Material = Enum.Material.WoodPlanks, CanCollide = false })
	for i = -3, 3, 2 do
		part({ Name = "HatchBar", Parent = dock, Size = Vector3.new(0.4, 0.7, 8), CFrame = CFrame.new(-2 + i, 3.9, 10), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
		part({ Name = "HatchBar", Parent = dock, Size = Vector3.new(8, 0.7, 0.4), CFrame = CFrame.new(-2, 3.9, 10 + i), Color = trimWood, Material = Enum.Material.Wood, CanCollide = false })
	end
	-- Barrels lashed neatly against the starboard bulwark
	for i = 1, 3 do
		part({
			Name = "Barrel" .. i,
			Parent = dock,
			Size = Vector3.new(3.4, 2.8, 2.8),
			CFrame = CFrame.new(30, 5.2, -34 + i * 4) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(104, 72, 42),
			Material = Enum.Material.Wood,
			CanCollide = false,
			Shape = Enum.PartType.Cylinder,
		})
	end
	-- Coiled ropes stowed on the planks
	for _, cpos in { Vector3.new(-28, 3.9, 44), Vector3.new(26, 3.9, -6) } do
		for ring = 1, 3 do
			cylV("RopeCoil", cpos + Vector3.new(0, ring * 0.25, 0), 0.5, 2.4 - ring * 0.4, ropeCol, Enum.Material.Fabric)
		end
	end

	local title = part({
		Name = "TitleBanner",
		Parent = dock,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(0, 20, -35),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	billboard(title, "SURVIVE AT SEA\nBoarding ship", Config.Theme.Foam, UDim2.fromOffset(280, 64), 0, 22)
end

function LobbyWorld.getLobbySpawnCFrame(): CFrame
	return CFrame.new(0, 6, 0)
end

function LobbyWorld.updatePortalSign(portalModel: Model, title: string, subtitle: string, color: Color3?)
	local anchor = portalModel:FindFirstChild("SignAnchor")
	if not (anchor and anchor:IsA("BasePart")) then
		anchor = portalModel:FindFirstChild("ArchTop")
	end
	if not (anchor and anchor:IsA("BasePart")) then
		anchor = portalModel:FindFirstChild("Pad")
	end
	if not (anchor and anchor:IsA("BasePart")) then
		return
	end
	local old = anchor:FindFirstChild("LobbyBillboard")
	if old then
		old:Destroy()
	end
	-- Also clear any leftover pad-level signs from older builds
	local pad = portalModel:FindFirstChild("Pad")
	if pad and pad ~= anchor then
		local padSign = pad:FindFirstChild("LobbyBillboard")
		if padSign then
			padSign:Destroy()
		end
	end
	local line = if subtitle ~= "" then `{title}  ·  {subtitle}` else title
	local offsetY = if anchor.Name == "SignAnchor" then 0 else 3
	billboard(anchor, line, color or Color3.fromRGB(255, 236, 228), UDim2.fromOffset(150, 32), offsetY, 13)
end

-- Polish any lobby (fresh or Rojo-synced): no glows, barriers, palms, boats.
function LobbyWorld.polish(root: Folder)
	stripGlowParts(root)

	-- Flat glass ocean is a fallback only — Terrain water (OceanTerrainService) is the real sea.
	-- Keep these parts non-colliding and fully hidden so they never fight the wave field.
	local oceanDeep = root:FindFirstChild("OceanDeep")
	if oceanDeep and oceanDeep:IsA("BasePart") then
		oceanDeep.CanCollide = false
		oceanDeep.CanQuery = false
		oceanDeep.CanTouch = false
		oceanDeep.CastShadow = false
		oceanDeep.Size = Vector3.new(4000, 4, 8000)
		oceanDeep.CFrame = CFrame.new(0, OceanConfig.SurfaceY - OceanConfig.DepthStuds + 2, 2000)
		oceanDeep.Color = OceanConfig.AbyssColor
		oceanDeep.Transparency = 1
	end
	local oceanSurface = root:FindFirstChild("OceanSurface")
	if oceanSurface and oceanSurface:IsA("BasePart") then
		oceanSurface.CanCollide = false
		oceanSurface.CanQuery = false
		oceanSurface.CanTouch = false
		oceanSurface.CastShadow = false
		oceanSurface.Size = Vector3.new(4000, 2, 8000)
		oceanSurface.CFrame = CFrame.new(0, OceanConfig.SurfaceY, 2000)
		oceanSurface.Color = OceanConfig.WaterColor
		oceanSurface.Transparency = 1
		oceanSurface.Reflectance = 0
	end

	buildBarriers(root)
	buildScenery(root)
	clearPathwayMarkers(root)
	hideVoyageStagingBoat(root)

	-- Soften spawn pad into the deck (no cyan marker pad)
	local spawn = root:FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("SpawnLocation") then
		spawn.Material = Enum.Material.WoodPlanks
		spawn.BrickColor = BrickColor.new("Brown")
		spawn.Color = Color3.fromRGB(118, 80, 48)
		spawn.Transparency = 1
		spawn.Enabled = true
		spawn.Neutral = true
		spawn.Duration = 0
	end

	-- Rebuild berths at safe Config positions (never reuse clipped map coords)
	local portals = root:FindFirstChild("Portals")
	if not portals then
		portals = Instance.new("Folder")
		portals.Name = "Portals"
		portals.Parent = root
	end
	for _, model in portals:GetChildren() do
		model:Destroy()
	end
	local startX = -((Config.PortalCount - 1) * Config.PortalSpacing) / 2
	for i = 1, Config.PortalCount do
		local pos = Vector3.new(startX + (i - 1) * Config.PortalSpacing, 3.5, 68)
		buildPortal(portals, i, pos)
	end

	local dock = root:FindFirstChild("Dock")
	if dock then
		local oldTitle = dock:FindFirstChild("TitleBanner") or dock:FindFirstChild("TitleAnchor")
		if oldTitle then
			oldTitle:Destroy()
		end
		local titleAnchor = part({
			Name = "TitleBanner",
			Parent = dock,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(0, 18, -35),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
		})
		billboard(titleAnchor, "SURVIVE AT SEA\nBoarding ship", Config.Theme.Foam, UDim2.fromOffset(280, 64), 0, 22)
	end

	print("[SurviveAtSea] Lobby polished — realistic cannons/islands, no path, no staging boat")
end

function LobbyWorld.ensure(): Folder
	local existing = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if existing and existing:IsA("Folder") then
		LobbyWorld.polish(existing)
		return existing
	end

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
		Size = Vector3.new(4000, 4, 8000),
		CFrame = CFrame.new(0, OceanConfig.SurfaceY - OceanConfig.DepthStuds + 2, 2000),
		Color = OceanConfig.AbyssColor,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
		CanCollide = false,
	})

	part({
		Name = "OceanSurface",
		Parent = root,
		Size = Vector3.new(4000, 2, 8000),
		CFrame = CFrame.new(0, OceanConfig.SurfaceY, 2000),
		Color = OceanConfig.WaterColor,
		Material = Enum.Material.Glass,
		Transparency = 1,
		Reflectance = 0,
		CanCollide = false,
	})

	-- No Foam runway / colored path around the pier

	buildDock(root)

	local portalsFolder = Instance.new("Folder")
	portalsFolder.Name = "Portals"
	portalsFolder.Parent = root

	local startX = -((Config.PortalCount - 1) * Config.PortalSpacing) / 2
	for i = 1, Config.PortalCount do
		local pos = Vector3.new(startX + (i - 1) * Config.PortalSpacing, 3.5, 68)
		buildPortal(portalsFolder, i, pos)
	end

	-- Invisible launch pad only (no giant boat behind the berths)
	hideVoyageStagingBoat(root)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, 4.2, 0)
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Transparency = 1
	spawn.BrickColor = BrickColor.new("Brown")
	spawn.Color = Color3.fromRGB(118, 80, 48)
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Parent = root

	LobbyWorld.polish(root)

	print("[SurviveAtSea] LobbyWorld.ensure built boarding pier + berths")
	return root
end

function LobbyWorld.seatCharacter(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = LobbyWorld.getLobbySpawnCFrame()
		root.CFrame = CFrame.new(root.Position, root.Position + Vector3.new(0, 0, 40))
	end
end

return LobbyWorld
