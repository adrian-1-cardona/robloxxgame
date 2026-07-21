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
	label.BackgroundTransparency = 0.28
	label.BackgroundColor3 = Color3.fromRGB(28, 42, 48)
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 100, 70)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = label
end

local function buildPalm(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Palm"
	model.Parent = parent

	part({
		Name = "Trunk",
		Parent = model,
		Size = Vector3.new(1.6 * s, 14 * s, 1.6 * s),
		CFrame = CFrame.new(position + Vector3.new(0, 7 * s, 0)) * CFrame.Angles(0, 0, math.rad(6)),
		Color = Color3.fromRGB(110, 78, 42),
		Material = Enum.Material.Wood,
	})

	-- Fronds fan out from the crown (no glow — just leafy green)
	local crown = position + Vector3.new(0.6 * s, 14 * s, 0)
	for i = 0, 5 do
		local yaw = math.rad(i * 60)
		part({
			Name = "Frond" .. i,
			Parent = model,
			Size = Vector3.new(1.2 * s, 0.4 * s, 9 * s),
			CFrame = CFrame.new(crown)
				* CFrame.Angles(0, yaw, 0)
				* CFrame.Angles(math.rad(-28), 0, 0)
				* CFrame.new(0, 0, -3.5 * s),
			Color = if i % 2 == 0 then Color3.fromRGB(46, 120, 58) else Color3.fromRGB(34, 100, 48),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end

	part({
		Name = "Coconuts",
		Parent = model,
		Size = Vector3.new(2.2 * s, 1.6 * s, 2.2 * s),
		CFrame = CFrame.new(crown + Vector3.new(0, -0.8 * s, 0)),
		Color = Color3.fromRGB(90, 60, 30),
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

	-- Boarding berth pad (wood only — no neon rings)
	local pad = part({
		Name = "Pad",
		Parent = model,
		Size = Vector3.new(16, 1.4, 16),
		CFrame = CFrame.new(position),
		Color = Color3.fromRGB(98, 68, 42),
		Material = Enum.Material.WoodPlanks,
	})

	-- Painted berth rim (matte wood stain — readable, not glowing)
	part({
		Name = "BerthRim",
		Parent = model,
		Size = Vector3.new(16.6, 0.45, 16.6),
		CFrame = CFrame.new(position + Vector3.new(0, 0.85, 0)),
		Color = Color3.fromRGB(70, 95, 90),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- Rope posts at corners
	for _, ox in { -6.5, 6.5 } do
		for _, oz in { -6.5, 6.5 } do
			part({
				Name = "RopePost",
				Parent = model,
				Size = Vector3.new(1.2, 4, 1.2),
				CFrame = CFrame.new(position + Vector3.new(ox, 2.5, oz)),
				Color = Color3.fromRGB(85, 58, 34),
				Material = Enum.Material.Wood,
			})
		end
	end

	-- Wooden arch (gangway frame)
	for _, offsetX in { -6.5, 6.5 } do
		part({
			Name = "ArchLeg",
			Parent = model,
			Size = Vector3.new(2.2, 16, 2.2),
			CFrame = CFrame.new(position + Vector3.new(offsetX, 9, -1)),
			Color = Color3.fromRGB(88, 60, 36),
			Material = Enum.Material.Wood,
		})
	end

	part({
		Name = "ArchTop",
		Parent = model,
		Size = Vector3.new(15.5, 2.2, 2.2),
		CFrame = CFrame.new(position + Vector3.new(0, 17.5, -1)),
		Color = Color3.fromRGB(88, 60, 36),
		Material = Enum.Material.Wood,
	})

	-- Canvas sail gate (fabric, not ForceField / neon)
	local gate = part({
		Name = "Gate",
		Parent = model,
		Size = Vector3.new(10, 13, 0.6),
		CFrame = CFrame.new(position + Vector3.new(0, 9, -1)),
		Color = Color3.fromRGB(220, 210, 185),
		Material = Enum.Material.Fabric,
		Transparency = 0.08,
		CanCollide = false,
	})

	-- Soft sway on the canvas (motion, not glow)
	task.spawn(function()
		local base = gate.CFrame
		local t = index * 1.3
		while gate.Parent do
			t += 0.05
			gate.CFrame = base * CFrame.Angles(0, math.rad(math.sin(t) * 2.5), 0)
			task.wait(0.05)
		end
	end)

	-- Number plank hanging from the arch (matte paint)
	local numberPlank = part({
		Name = "NumberPlank",
		Parent = model,
		Size = Vector3.new(5, 3, 0.5),
		CFrame = CFrame.new(position + Vector3.new(0, 15.2, 0.4)),
		Color = Color3.fromRGB(72, 95, 88),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	billboard(numberPlank, tostring(index), Config.Theme.Foam, UDim2.fromOffset(70, 70), 0)

	local promptPart = part({
		Name = "PromptAnchor",
		Parent = model,
		Size = Vector3.new(6, 6, 6),
		CFrame = CFrame.new(position + Vector3.new(0, 3, 5)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ObjectText = "Boarding Berth " .. index
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

	billboard(pad, `BERTH {index}\nWalk up · press E`, Config.Theme.Foam, UDim2.fromOffset(240, 80), 9)
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
					desc.Color = Color3.fromRGB(220, 210, 185)
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
				desc.Color = Color3.fromRGB(220, 210, 185)
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

	-- Carriage
	part({
		Name = "Carriage",
		Parent = model,
		Size = Vector3.new(4.5, 1.8, 6),
		CFrame = baseCf * CFrame.new(0, 0.9, 0),
		Color = Color3.fromRGB(88, 60, 36),
		Material = Enum.Material.Wood,
	})
	-- Wheels
	for _, side in { -2.6, 2.6 } do
		part({
			Name = "Wheel",
			Parent = model,
			Size = Vector3.new(0.7, 3.2, 3.2),
			CFrame = baseCf * CFrame.new(side, 1.4, 0.4) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(55, 40, 28),
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Cylinder,
		})
	end
	-- Barrel (iron, matte — no neon)
	part({
		Name = "Barrel",
		Parent = model,
		Size = Vector3.new(2.2, 2.2, 9),
		CFrame = baseCf * CFrame.new(0, 2.6, -2.2) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = Color3.fromRGB(48, 48, 52),
		Material = Enum.Material.Metal,
	})
	part({
		Name = "Muzzle",
		Parent = model,
		Size = Vector3.new(2.5, 2.5, 1.2),
		CFrame = baseCf * CFrame.new(0, 3.1, -6.4) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = Color3.fromRGB(40, 40, 44),
		Material = Enum.Material.Metal,
	})
	-- Stack of cannonballs beside it
	part({
		Name = "BallPile",
		Parent = model,
		Size = Vector3.new(2.4, 1.6, 2.4),
		CFrame = baseCf * CFrame.new(3.2, 1.2, 1.5),
		Color = Color3.fromRGB(35, 35, 38),
		Material = Enum.Material.Metal,
		CanCollide = false,
	})

	return model
end

local function buildMiniIsland(parent: Instance, position: Vector3, size: Vector3, yawDegrees: number?)
	local yaw = math.rad(yawDegrees or 0)
	local island = Instance.new("Model")
	island.Name = "MiniIsland"
	island.Parent = parent

	part({
		Name = "Sand",
		Parent = island,
		Size = size,
		CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0),
		Color = Color3.fromRGB(214, 192, 148),
		Material = Enum.Material.Sand,
		CanCollide = false,
	})
	-- Slight rock edge
	part({
		Name = "RockRim",
		Parent = island,
		Size = Vector3.new(size.X * 0.85, size.Y * 0.55, size.Z * 0.85),
		CFrame = CFrame.new(position + Vector3.new(0, -size.Y * 0.25, 0)) * CFrame.Angles(0, yaw + 0.4, 0),
		Color = Color3.fromRGB(120, 110, 95),
		Material = Enum.Material.Slate,
		CanCollide = false,
	})

	local top = position + Vector3.new(0, size.Y * 0.5, 0)
	buildPalm(island, top, 0.9 + (size.X / 40))
	if size.X > 16 then
		buildPalm(island, top + Vector3.new(size.X * 0.22, 0, size.Z * 0.12), 0.7)
	end
	if size.X > 22 then
		buildPalm(island, top + Vector3.new(-size.X * 0.18, 0, -size.Z * 0.1), 0.75)
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

	-- Palms on the pier (decorative, stay out of the berth walk space)
	local palmSpots = {
		{ Vector3.new(-28, PIER.DeckY, -28), 1.1 },
		{ Vector3.new(28, PIER.DeckY, -28), 1.0 },
		{ Vector3.new(-30, PIER.DeckY, 55), 0.95 },
		{ Vector3.new(30, PIER.DeckY, 55), 1.05 },
		{ Vector3.new(-22, PIER.DeckY, 10), 0.85 },
		{ Vector3.new(24, PIER.DeckY, 18), 0.9 },
		{ Vector3.new(-26, PIER.DeckY, 32), 0.8 },
		{ Vector3.new(26, PIER.DeckY, 38), 0.85 },
	}
	for _, spot in palmSpots do
		buildPalm(scenery, spot[1] :: Vector3, spot[2] :: number)
	end

	-- Deck cannons aiming out to sea (props only)
	local cannons = {
		{ Vector3.new(-32, PIER.DeckY, 0), -90 },
		{ Vector3.new(-32, PIER.DeckY, 40), -85 },
		{ Vector3.new(32, PIER.DeckY, 0), 90 },
		{ Vector3.new(32, PIER.DeckY, 40), 95 },
		{ Vector3.new(-18, PIER.DeckY, -36), 180 },
		{ Vector3.new(18, PIER.DeckY, -36), 180 },
	}
	for _, c in cannons do
		buildCannon(scenery, c[1] :: Vector3, c[2] :: number)
	end

	-- Boats moored beside the pier (outside barriers — look, don't board)
	local boats = {
		{ Vector3.new(-52, 1.5, 10), 20, Color3.fromRGB(160, 90, 50) },
		{ Vector3.new(-55, 1.2, 45), -10, Color3.fromRGB(70, 95, 120) },
		{ Vector3.new(52, 1.4, 5), -160, Color3.fromRGB(145, 75, 55) },
		{ Vector3.new(54, 1.3, 50), 170, Color3.fromRGB(180, 140, 70) },
		{ Vector3.new(-48, 1.1, 75), 5, Color3.fromRGB(95, 70, 45) },
		{ Vector3.new(50, 1.2, 78), -175, Color3.fromRGB(55, 85, 100) },
	}
	for _, b in boats do
		buildBoat(scenery, b[1] :: Vector3, b[2] :: number, b[3] :: Color3)
	end

	-- Mini islands around the outside (no walkways — scenery only)
	local islands = {
		{ Vector3.new(-85, -0.4, 0), Vector3.new(24, 4, 18), 15 },
		{ Vector3.new(90, -0.4, 30), Vector3.new(26, 4.2, 17), -20 },
		{ Vector3.new(-70, -0.5, -40), Vector3.new(20, 3.8, 15), 40 },
		{ Vector3.new(75, -0.5, -35), Vector3.new(18, 3.6, 14), -55 },
		{ Vector3.new(-95, -0.3, 55), Vector3.new(22, 4, 16), 8 },
		{ Vector3.new(98, -0.4, 70), Vector3.new(20, 3.8, 15), -12 },
		{ Vector3.new(-60, -0.5, 100), Vector3.new(16, 3.4, 12), 25 },
		{ Vector3.new(62, -0.5, 105), Vector3.new(17, 3.5, 13), -30 },
		{ Vector3.new(0, -0.6, -75), Vector3.new(28, 4.5, 16), 5 },
		{ Vector3.new(-110, -0.4, 20), Vector3.new(14, 3.2, 11), 60 },
		{ Vector3.new(115, -0.4, 10), Vector3.new(15, 3.3, 12), -45 },
	}
	for _, isle in islands do
		buildMiniIsland(scenery, isle[1] :: Vector3, isle[2] :: Vector3, isle[3] :: number)
	end
end

local function clearPathwayMarkers(root: Folder)
	-- No glowing arrows / guide walkways — keep the pier calm and easy on the eyes
	for _, child in root:GetDescendants() do
		if child:IsA("BasePart") then
			local name = child.Name
			if name == "Arrow" or name == "GuidePlank" or name == "GuideTip" or name == "CenterPlank" then
				-- Soften the bright center stripe into matching deck wood (keep collision volume)
				if name == "CenterPlank" then
					child.Color = Color3.fromRGB(125, 86, 52)
					child.Material = Enum.Material.WoodPlanks
				else
					child:Destroy()
				end
			end
		end
	end
	-- Also clear direct children left from older builds
	for _, child in root:GetChildren() do
		if child.Name == "Arrow" or child.Name == "GuidePlank" or child.Name == "GuideTip" then
			child:Destroy()
		end
	end
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
		Color = Color3.fromRGB(120, 82, 48),
		Material = Enum.Material.WoodPlanks,
	})

	part({
		Name = "CenterPlank",
		Parent = dock,
		Size = Vector3.new(8, 3.2, 140),
		CFrame = CFrame.new(0, 2, 20),
		Color = Color3.fromRGB(125, 86, 52),
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

	for i = 1, 5 do
		local buoy = part({
			Name = "Buoy" .. i,
			Parent = dock,
			Size = Vector3.new(3.5, 6, 3.5),
			CFrame = CFrame.new(-65 + i * 28, 2.5, 95 + (i % 2) * 10),
			Color = if i % 2 == 0 then Color3.fromRGB(220, 70, 55) else Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		task.spawn(function()
			local t = i * 1.4
			local x, z = buoy.Position.X, buoy.Position.Z
			while buoy.Parent do
				t += 0.05
				buoy.CFrame = CFrame.new(x, 2.5 + math.sin(t) * 0.7, z)
					* CFrame.Angles(0, t * 0.2, math.rad(math.sin(t) * 6))
				task.wait(0.05)
			end
		end)
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
	billboard(title, "SURVIVE AT SEA\nBOARDING PIER", Config.Theme.Foam, UDim2.fromOffset(480, 120), 0)
end

function LobbyWorld.getLobbySpawnCFrame(): CFrame
	return CFrame.new(0, 6, 0)
end

function LobbyWorld.updatePortalSign(portalModel: Model, title: string, subtitle: string, color: Color3?)
	local pad = portalModel:FindFirstChild("Pad")
	if not (pad and pad:IsA("BasePart")) then
		return
	end
	local old = pad:FindFirstChild("LobbyBillboard")
	if old then
		old:Destroy()
	end
	billboard(pad, `{title}\n{subtitle}`, color or Config.Theme.Foam, UDim2.fromOffset(260, 90), 9)
end

-- Polish any lobby (fresh or Rojo-synced): no glows, barriers, palms, boats.
function LobbyWorld.polish(root: Folder)
	stripGlowParts(root)

	-- Ocean should not be a walkable escape route
	local oceanDeep = root:FindFirstChild("OceanDeep")
	if oceanDeep and oceanDeep:IsA("BasePart") then
		oceanDeep.CanCollide = false
	end
	local oceanSurface = root:FindFirstChild("OceanSurface")
	if oceanSurface and oceanSurface:IsA("BasePart") then
		oceanSurface.CanCollide = false
	end

	buildBarriers(root)
	buildScenery(root)
	clearPathwayMarkers(root)

	-- Soften spawn pad (wood, not neon)
	local spawn = root:FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("SpawnLocation") then
		spawn.Material = Enum.Material.WoodPlanks
		spawn.BrickColor = BrickColor.new("Brown")
		spawn.Transparency = 0.2
		spawn.Enabled = true
		spawn.Neutral = true
	end

	-- Restyle portals that still look like neon gates
	local portals = root:FindFirstChild("Portals")
	if portals then
		local stale: { Model } = {}
		for _, model in portals:GetChildren() do
			if model:IsA("Model") and not model:FindFirstChild("BerthRim") then
				table.insert(stale, model)
			else
				local neon = model:FindFirstChild("NeonRing")
				if neon then
					neon:Destroy()
				end
			end
		end
		for _, model in stale do
			local pad = model:FindFirstChild("Pad")
			local indexValue = model:FindFirstChild("PortalIndex")
			local index = if indexValue and indexValue:IsA("IntValue") then indexValue.Value else 1
			local position = if pad and pad:IsA("BasePart") then pad.Position else Vector3.new(0, 3.5, 70)
			model:Destroy()
			buildPortal(portals, index, position)
		end
	end

	local dock = root:FindFirstChild("Dock")
	if dock and not dock:FindFirstChild("TitleBanner") and not dock:FindFirstChild("TitleAnchor") then
		local titleAnchor = part({
			Name = "TitleBanner",
			Parent = dock,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(0, 20, -35),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
		})
		billboard(titleAnchor, "SURVIVE AT SEA\nBOARDING PIER", Config.Theme.Foam, UDim2.fromOffset(480, 120), 0)
	end

	print("[SurviveAtSea] Lobby polished — cannons, palms, mini islands, no glow pathways")
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
		Size = Vector3.new(1200, 30, 1200),
		CFrame = CFrame.new(0, -16, 0),
		Color = Color3.fromRGB(6, 40, 70),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.12,
		CanCollide = false,
	})

	part({
		Name = "OceanSurface",
		Parent = root,
		Size = Vector3.new(1200, 2, 1200),
		CFrame = CFrame.new(0, 0, 0),
		Color = Color3.fromRGB(20, 120, 150),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Reflectance = 0.12,
		CanCollide = false,
	})

	part({
		Name = "Foam",
		Parent = root,
		Size = Vector3.new(160, 0.6, 160),
		CFrame = CFrame.new(0, 1.2, 20),
		Color = Config.Theme.Foam,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.55,
		CanCollide = false,
	})

	buildDock(root)

	local portalsFolder = Instance.new("Folder")
	portalsFolder.Name = "Portals"
	portalsFolder.Parent = root

	local startX = -((Config.PortalCount - 1) * Config.PortalSpacing) / 2
	for i = 1, Config.PortalCount do
		local pos = Vector3.new(startX + (i - 1) * Config.PortalSpacing, 3.5, 70)
		buildPortal(portalsFolder, i, pos)
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
	part({
		Name = "Hull",
		Parent = staging,
		Size = Vector3.new(56, 12, 8),
		CFrame = CFrame.new(0, 7, 240),
		Color = Color3.fromRGB(60, 42, 28),
		Material = Enum.Material.Wood,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, 4.2, 0)
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Transparency = 0.15
	spawn.BrickColor = BrickColor.new("Brown")
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
