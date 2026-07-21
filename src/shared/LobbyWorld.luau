-- Builds and polishes the Survive at Sea boarding dock.
-- Safe to call from server (replicates) or client (local fallback).
-- Theme: sunny pier with palm trees & boats. No neon portal glows.
-- Players stay on the initial pier (invisible barriers).

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent:WaitForChild("Config"))

local LobbyWorld = {}

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

	task.spawn(function()
		local t = yawDegrees * 0.1
		while model.Parent do
			t += 0.04
			local bob = math.sin(t) * 0.55
			local roll = math.rad(math.sin(t * 0.7) * 3)
			local boatCf = CFrame.new(position + Vector3.new(0, bob, 0)) * CFrame.Angles(roll, yaw, 0)
			for _, item in built do
				if item.part.Parent then
					item.part.CFrame = boatCf * item.offset
				end
			end
			task.wait(0.06)
		end
	end)

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
	local berthRed = Config.Berth.Red
	local berthBlue = Config.Berth.DarkBlue

	-- Half red / half dark blue berth pad (left = red, right = blue)
	local padLeft = part({
		Name = "PadRed",
		Parent = model,
		Size = Vector3.new(7, 1.2, 14),
		CFrame = CFrame.new(position + Vector3.new(-3.5, 0, 0)),
		Color = berthRed,
		Material = Enum.Material.WoodPlanks,
	})
	local padRight = part({
		Name = "PadBlue",
		Parent = model,
		Size = Vector3.new(7, 1.2, 14),
		CFrame = CFrame.new(position + Vector3.new(3.5, 0, 0)),
		Color = berthBlue,
		Material = Enum.Material.WoodPlanks,
	})
	-- Invisible primary for anchoring / PrimaryPart
	local pad = part({
		Name = "Pad",
		Parent = model,
		Size = Vector3.new(14, 1.2, 14),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	part({
		Name = "BerthRim",
		Parent = model,
		Size = Vector3.new(14.5, 0.35, 14.5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.75, 0)),
		Color = Color3.fromRGB(30, 30, 40),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- Split center seam so the two halves read clearly
	part({
		Name = "BerthSeam",
		Parent = model,
		Size = Vector3.new(0.35, 1.35, 14.2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.05, 0)),
		Color = Color3.fromRGB(12, 14, 22),
		Material = Enum.Material.SmoothPlastic,
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

	-- Banner: half red / half dark blue to match the berth
	part({
		Name = "ArchBannerRed",
		Parent = model,
		Size = Vector3.new(5.5, 1.0, 0.3),
		CFrame = CFrame.new(position + Vector3.new(-2.8, 15.5, 0.5)),
		Color = berthRed,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	part({
		Name = "ArchBannerBlue",
		Parent = model,
		Size = Vector3.new(5.5, 1.0, 0.3),
		CFrame = CFrame.new(position + Vector3.new(2.8, 15.5, 0.5)),
		Color = berthBlue,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})

	-- Soft split gate canvas
	local gateRed = part({
		Name = "GateRed",
		Parent = model,
		Size = Vector3.new(4.1, 12, 0.45),
		CFrame = CFrame.new(position + Vector3.new(-2.1, 8.5, -0.5)),
		Color = Color3.fromRGB(198, 110, 100),
		Material = Enum.Material.Fabric,
		Transparency = 0.08,
		CanCollide = false,
	})
	local gateBlue = part({
		Name = "GateBlue",
		Parent = model,
		Size = Vector3.new(4.1, 12, 0.45),
		CFrame = CFrame.new(position + Vector3.new(2.1, 8.5, -0.5)),
		Color = Color3.fromRGB(70, 100, 160),
		Material = Enum.Material.Fabric,
		Transparency = 0.08,
		CanCollide = false,
	})

	task.spawn(function()
		local baseRed = gateRed.CFrame
		local baseBlue = gateBlue.CFrame
		local t = index * 1.3
		while gateRed.Parent and gateBlue.Parent do
			t += 0.05
			local sway = CFrame.Angles(0, math.rad(math.sin(t) * 1.8), 0)
			gateRed.CFrame = baseRed * sway
			gateBlue.CFrame = baseBlue * sway
			task.wait(0.05)
		end
	end)

	local signAnchor = part({
		Name = "SignAnchor",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(position + Vector3.new(0, 19, -0.5)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	billboard(signAnchor, `Berth {index}`, Color3.fromRGB(255, 236, 228), UDim2.fromOffset(120, 30), 0, 14)

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
	prompt.ObjectText = "Berth " .. index
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

	-- Keep padLeft/padRight referenced so they aren't optimized away by lint tools
	local _ = padLeft
	local __ = padRight
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
				if name == "Gate" or name == "GateRed" then
					desc.Material = Enum.Material.Fabric
					desc.Color = Color3.fromRGB(198, 110, 100)
					desc.Transparency = 0.08
				elseif name == "GateBlue" then
					desc.Material = Enum.Material.Fabric
					desc.Color = Color3.fromRGB(70, 100, 160)
					desc.Transparency = 0.08
				elseif name == "LighthouseLamp" then
					desc.Material = Enum.Material.SmoothPlastic
					desc.Color = Color3.fromRGB(245, 220, 160)
				else
					desc.Material = Enum.Material.SmoothPlastic
				end
			end
			if name == "Gate" or name == "GateRed" then
				desc.Material = Enum.Material.Fabric
				desc.Color = Color3.fromRGB(198, 110, 100)
				desc.Transparency = 0.08
			elseif name == "GateBlue" then
				desc.Material = Enum.Material.Fabric
				desc.Color = Color3.fromRGB(70, 100, 160)
				desc.Transparency = 0.08
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

local function buildScenery(root: Folder)
	local existing = root:FindFirstChild("Scenery")
	if existing then
		existing:Destroy()
	end

	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = root

	-- Palms on the pier (keep clear of berth row at z≈70)
	local palmSpots = {
		{ Vector3.new(-28, PIER.DeckY, -28), 1.1 },
		{ Vector3.new(28, PIER.DeckY, -28), 1.0 },
		{ Vector3.new(-30, PIER.DeckY, 38), 0.95 },
		{ Vector3.new(30, PIER.DeckY, 38), 1.05 },
		{ Vector3.new(-22, PIER.DeckY, 8), 0.85 },
		{ Vector3.new(24, PIER.DeckY, 16), 0.9 },
		{ Vector3.new(-26, PIER.DeckY, 26), 0.8 },
		{ Vector3.new(26, PIER.DeckY, 28), 0.85 },
	}
	for _, spot in palmSpots do
		buildPalm(scenery, spot[1] :: Vector3, spot[2] :: number)
	end

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

	-- Boats well clear of the berth row (z≈70) — especially berth 4 at x≈36
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

	part({
		Name = "PierDeck",
		Parent = dock,
		Size = Vector3.new(80, 3, 140),
		CFrame = CFrame.new(0, 2, 20),
		Color = Color3.fromRGB(118, 80, 48),
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
		Size = Vector3.new(12.4, 5, 12.4),
		CFrame = CFrame.new(-55, 18, -20),
		Color = Color3.fromRGB(170, 75, 65),
		Material = Enum.Material.SmoothPlastic,
	})
	part({
		Name = "LighthouseLamp",
		Parent = dock,
		Size = Vector3.new(10, 8, 10),
		CFrame = CFrame.new(-55, 52, -20),
		Color = Color3.fromRGB(245, 220, 160),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})

	for i = 1, 6 do
		part({
			Name = "Crate" .. i,
			Parent = dock,
			Size = Vector3.new(4.5, 4.5, 4.5),
			CFrame = CFrame.new(-20 + i * 5.5, 6.2, -32 + (i % 3) * 4) * CFrame.Angles(0, math.rad(i * 15), 0),
			Color = Color3.fromRGB(130, 90, 50),
			Material = Enum.Material.Wood,
		})
	end

	-- Barrel stacks for boaty flavor (cylinder default axis is +X, so tip upright)
	for i = 1, 4 do
		part({
			Name = "Barrel" .. i,
			Parent = dock,
			Size = Vector3.new(4, 3.2, 3.2),
			CFrame = CFrame.new(18 + (i % 2) * 4, 5.8, -25 + i * 4) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(100, 70, 40),
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Cylinder,
		})
	end

	-- No red buoy blocks near berths — keep the pier clear

	local title = part({
		Name = "TitleBanner",
		Parent = dock,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(0, 20, -35),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	billboard(title, "SURVIVE AT SEA\nBoarding pier", Config.Theme.Foam, UDim2.fromOffset(280, 64), 0, 22)
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

	-- Ocean should not be a walkable escape route — keep it readable mid-sea
	local oceanDeep = root:FindFirstChild("OceanDeep")
	if oceanDeep and oceanDeep:IsA("BasePart") then
		oceanDeep.CanCollide = false
		oceanDeep.Size = Vector3.new(2400, 40, 2400)
		oceanDeep.CFrame = CFrame.new(0, -20, 200)
		oceanDeep.Color = Color3.fromRGB(8, 55, 95)
		oceanDeep.Transparency = 0.05
	end
	local oceanSurface = root:FindFirstChild("OceanSurface")
	if oceanSurface and oceanSurface:IsA("BasePart") then
		oceanSurface.CanCollide = false
		oceanSurface.Size = Vector3.new(2400, 2, 2400)
		oceanSurface.CFrame = CFrame.new(0, 0.4, 200)
		oceanSurface.Color = Color3.fromRGB(28, 130, 165)
		oceanSurface.Transparency = 0.28
		oceanSurface.Reflectance = 0.18
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
		billboard(titleAnchor, "SURVIVE AT SEA\nBoarding pier", Config.Theme.Foam, UDim2.fromOffset(280, 64), 0, 22)
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
		Size = Vector3.new(2400, 40, 2400),
		CFrame = CFrame.new(0, -20, 200),
		Color = Color3.fromRGB(8, 55, 95),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.05,
		CanCollide = false,
	})

	part({
		Name = "OceanSurface",
		Parent = root,
		Size = Vector3.new(2400, 2, 2400),
		CFrame = CFrame.new(0, 0.4, 200),
		Color = Color3.fromRGB(28, 130, 165),
		Material = Enum.Material.Glass,
		Transparency = 0.28,
		Reflectance = 0.18,
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
