-- Creates pirate ships that spawn at night to hunt player crews.
-- Ships are built with proper hull collision, sails, masts, and cannons.
-- Each ship can carry multiple pirate NPCs and moves through the water autonomously.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PirateShipFactory = {}

-- Ship appearance colors matching the reference image
local SHIP_HULL_BROWN = Color3.fromRGB(139, 90, 43)
local SHIP_DECK_WOOD = Color3.fromRGB(160, 110, 70)
local SHIP_MAST_BROWN = Color3.fromRGB(101, 67, 33)
local SAIL_WHITE = Color3.fromRGB(240, 235, 215)
local SAIL_DIRTY = Color3.fromRGB(220, 215, 195)
local ROPE_BROWN = Color3.fromRGB(101, 67, 33)
local CANNON_METAL = Color3.fromRGB(45, 45, 50)

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "ShipPart"
	p.Anchored = props.Anchored or false
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color or SHIP_HULL_BROWN
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	p.Parent = props.Parent
	return p
end

local function weldTo(part: BasePart, target: BasePart, offset: CFrame?)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = target
	weld.Parent = part
	if offset then
		local alignPos = Instance.new("AlignPosition")
		alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
		alignPos.RigidityEnabled = true
		alignPos.Attachment0 = Instance.new("Attachment", part)
		alignPos.Attachment0.CFrame = offset
		alignPos.Parent = part
	end
	return weld
end

-- Creates the main hull of the pirate ship
local function buildHull(ship: Model, center: CFrame): BasePart
	-- Main hull body
	local hull = makePart({
		Name = "Hull",
		Parent = ship,
		Size = Vector3.new(24, 4, 8),
		CFrame = center,
		Color = SHIP_HULL_BROWN,
		Material = Enum.Material.Wood,
		Anchored = true,
	})
	
	-- Hull primary part for the ship model
	ship.PrimaryPart = hull
	
	-- Bow (front pointed section)
	local bow = makePart({
		Name = "Bow",
		Parent = ship,
		Size = Vector3.new(6, 3, 6),
		CFrame = center * CFrame.new(-15, 0.5, 0) * CFrame.Angles(0, 0, math.rad(45)),
		Color = SHIP_HULL_BROWN,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
	})
	
	-- Stern (back section)
	local stern = makePart({
		Name = "Stern", 
		Parent = ship,
		Size = Vector3.new(4, 4, 8),
		CFrame = center * CFrame.new(12, 0, 0),
		Color = SHIP_HULL_BROWN,
		Material = Enum.Material.Wood,
		Anchored = true,
	})
	
	-- Deck planking
	local deck = makePart({
		Name = "Deck",
		Parent = ship,
		Size = Vector3.new(22, 0.5, 7),
		CFrame = center * CFrame.new(-1, 2.25, 0),
		Color = SHIP_DECK_WOOD,
		Material = Enum.Material.Wood,
		Anchored = true,
	})
	
	-- Hull waterline (lower section for better water interaction)
	local waterline = makePart({
		Name = "Waterline",
		Parent = ship,
		Size = Vector3.new(26, 2, 9),
		CFrame = center * CFrame.new(0, -1, 0),
		Color = SHIP_HULL_BROWN,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Transparency = 0.3,
		Anchored = true,
	})
	
	return hull
end

-- Creates the ship's masts and rigging
local function buildMasts(ship: Model, center: CFrame)
	-- Main mast (center)
	local mainMast = makePart({
		Name = "MainMast",
		Parent = ship,
		Size = Vector3.new(1.5, 25, 1.5),
		CFrame = center * CFrame.new(-2, 12.5, 0),
		Color = SHIP_MAST_BROWN,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
	})
	
	-- Fore mast (front)
	local foreMast = makePart({
		Name = "ForeMast",
		Parent = ship,
		Size = Vector3.new(1.2, 20, 1.2),
		CFrame = center * CFrame.new(-8, 10, 0),
		Color = SHIP_MAST_BROWN,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
	})
	
	-- Cross beams (yards) for sails
	for i, mastCFrame in pairs({
		center * CFrame.new(-2, 18, 0), -- Main mast yard
		center * CFrame.new(-8, 15, 0), -- Fore mast yard
	}) do
		local yard = makePart({
			Name = "Yard" .. i,
			Parent = ship,
			Size = Vector3.new(0.8, 12, 0.8),
			CFrame = mastCFrame * CFrame.Angles(0, 0, math.rad(90)),
			Color = SHIP_MAST_BROWN,
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
		})
	end
end

-- Creates the ship's sails
local function buildSails(ship: Model, center: CFrame)
	-- Main sail (large center sail)
	local mainSail = makePart({
		Name = "MainSail",
		Parent = ship,
		Size = Vector3.new(0.3, 16, 10),
		CFrame = center * CFrame.new(-1.5, 18, 0),
		Color = SAIL_WHITE,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Anchored = true,
	})
	
	-- Fore sail (front sail)
	local foreSail = makePart({
		Name = "ForeSail",
		Parent = ship,
		Size = Vector3.new(0.3, 12, 8),
		CFrame = center * CFrame.new(-7.5, 15, 0),
		Color = SAIL_DIRTY,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Anchored = true,
	})
	
	-- Jib sail (triangular front sail)
	local jibSail = makePart({
		Name = "JibSail", 
		Parent = ship,
		Size = Vector3.new(0.3, 8, 6),
		CFrame = center * CFrame.new(-12, 12, 0) * CFrame.Angles(0, 0, math.rad(15)),
		Color = SAIL_WHITE,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Anchored = true,
	})
	
	-- Add billowing effect to sails
	for _, sail in pairs({mainSail, foreSail, jibSail}) do
		-- Create a slight curve by using a mesh
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Brick
		mesh.Scale = Vector3.new(1, 1, 1.1)
		mesh.Offset = Vector3.new(0, 0, 0.2)
		mesh.Parent = sail
	end
end

-- Creates cannons on the ship deck
local function buildCannons(ship: Model, center: CFrame)
	local cannonPositions = {
		Vector3.new(2, 2.5, 3), -- Starboard front
		Vector3.new(6, 2.5, 3), -- Starboard mid
		Vector3.new(2, 2.5, -3), -- Port front
		Vector3.new(6, 2.5, -3), -- Port mid
	}
	
	for i, pos in pairs(cannonPositions) do
		-- Cannon base
		local cannonBase = makePart({
			Name = "CannonBase" .. i,
			Parent = ship,
			Size = Vector3.new(2, 1, 2),
			CFrame = center * CFrame.new(pos.X, pos.Y, pos.Z),
			Color = CANNON_METAL,
			Material = Enum.Material.Metal,
			Anchored = true,
		})
		
		-- Cannon barrel
		local cannonBarrel = makePart({
			Name = "CannonBarrel" .. i,
			Parent = ship,
			Size = Vector3.new(4, 0.8, 0.8),
			CFrame = center * CFrame.new(pos.X, pos.Y + 0.5, pos.Z) * 
				CFrame.Angles(0, if pos.Z > 0 then math.rad(-90) else math.rad(90), 0),
			Color = CANNON_METAL,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
		})
		
		-- Cannon wheels
		for j = -1, 1, 2 do
			makePart({
				Name = "CannonWheel" .. i .. "_" .. j,
				Parent = ship,
				Size = Vector3.new(0.3, 1.5, 1.5),
				CFrame = center * CFrame.new(pos.X, pos.Y - 0.2, pos.Z + j * 1.2) *
					CFrame.Angles(0, 0, math.rad(90)),
				Color = SHIP_MAST_BROWN,
				Material = Enum.Material.Wood,
				Shape = Enum.PartType.Cylinder,
				Anchored = true,
			})
		end
	end
end

-- Creates ship details like railings, barrels, and rigging
local function buildDetails(ship: Model, center: CFrame)
	-- Ship railings
	local railingHeight = 1.5
	local railingPositions = {
		-- Port side railing
		{Vector3.new(-10, 3.25, -3.8), Vector3.new(20, 0.2, 0.3)},
		{Vector3.new(0, 3.25, -3.8), Vector3.new(16, 0.2, 0.3)},
		-- Starboard side railing  
		{Vector3.new(-10, 3.25, 3.8), Vector3.new(20, 0.2, 0.3)},
		{Vector3.new(0, 3.25, 3.8), Vector3.new(16, 0.2, 0.3)},
		-- Bow railing
		{Vector3.new(-11, 3.25, 0), Vector3.new(0.3, 0.2, 6)},
	}
	
	for i, railData in pairs(railingPositions) do
		makePart({
			Name = "Railing" .. i,
			Parent = ship,
			Size = railData[2],
			CFrame = center * CFrame.new(railData[1].X, railData[1].Y, railData[1].Z),
			Color = SHIP_DECK_WOOD,
			Material = Enum.Material.Wood,
			Anchored = true,
		})
	end
	
	-- Barrel and crate details on deck
	local propPositions = {
		{Vector3.new(-4, 2.8, 2), "Barrel"},
		{Vector3.new(-4, 2.8, -2), "Barrel"}, 
		{Vector3.new(8, 2.8, 1.5), "Crate"},
		{Vector3.new(8, 2.8, -1.5), "Crate"},
	}
	
	for i, propData in pairs(propPositions) do
		local size = if propData[2] == "Barrel" then Vector3.new(1.2, 1.5, 1.2) else Vector3.new(1.5, 1.5, 1.5)
		local shape = if propData[2] == "Barrel" then Enum.PartType.Cylinder else Enum.PartType.Block
		local color = if propData[2] == "Barrel" then SHIP_MAST_BROWN else SHIP_DECK_WOOD
		
		makePart({
			Name = propData[2] .. i,
			Parent = ship,
			Size = size,
			CFrame = center * CFrame.new(propData[1].X, propData[1].Y, propData[1].Z),
			Color = color,
			Material = Enum.Material.Wood,
			Shape = shape,
			Anchored = true,
		})
	end
	
	-- Rope rigging details
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2
		local x = math.cos(angle) * 3
		local z = math.sin(angle) * 3
		
		makePart({
			Name = "Rigging" .. i,
			Parent = ship,
			Size = Vector3.new(0.2, 15, 0.2),
			CFrame = center * CFrame.new(-2 + x, 12, z) * CFrame.Angles(math.rad(15), angle, 0),
			Color = ROPE_BROWN,
			Material = Enum.Material.Fabric,
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			Anchored = true,
		})
	end
end

-- Creates a pirate flag
local function buildFlag(ship: Model, center: CFrame)
	-- Flag pole
	local flagPole = makePart({
		Name = "FlagPole",
		Parent = ship,
		Size = Vector3.new(0.3, 8, 0.3),
		CFrame = center * CFrame.new(10, 6, 0),
		Color = SHIP_MAST_BROWN,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
	})
	
	-- Pirate flag (black with skull)
	local flag = makePart({
		Name = "PirateFlag",
		Parent = ship,
		Size = Vector3.new(0.1, 3, 4),
		CFrame = center * CFrame.new(9, 8, 0),
		Color = Color3.fromRGB(20, 20, 20),
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Anchored = true,
	})
	
	-- Skull and crossbones decal
	local decal = Instance.new("Decal")
	decal.Texture = "rbxassetid://8560915132" -- Pirate skull texture ID
	decal.Face = Enum.NormalId.Front
	decal.Color3 = Color3.fromRGB(255, 255, 255)
	decal.Parent = flag
end

-- Main function to create a complete pirate ship
function PirateShipFactory.createShip(parent: Instance, position: Vector3, rotation: number?): Model
	local ship = Instance.new("Model")
	ship.Name = "PirateShip"
	ship.Parent = parent
	
	-- Set ship attributes for identification and behavior
	ship:SetAttribute("IsPirateShip", true)
	ship:SetAttribute("ShipHealth", 500)
	ship:SetAttribute("MaxSpeed", 80) -- Slower than player rafts for balance
	ship:SetAttribute("TurnSpeed", 2.5)
	ship:SetAttribute("CrewCapacity", 4) -- Max pirates per ship
	
	local centerCFrame = CFrame.new(position) * CFrame.Angles(0, rotation or 0, 0)
	
	-- Build ship components
	local hull = buildHull(ship, centerCFrame)
	buildMasts(ship, centerCFrame)
	buildSails(ship, centerCFrame)
	buildCannons(ship, centerCFrame)
	buildDetails(ship, centerCFrame)
	buildFlag(ship, centerCFrame)
	
	-- Add collision detection for ship vs player boats
	local function onTouched(hit)
		local hitModel = hit:FindFirstAncestorOfClass("Model")
		if hitModel and hitModel:GetAttribute("IsPlayerBase") then
			-- Ship collision with player raft - handle in PirateService
			local bindableEvent = ship:FindFirstChild("ShipCollision")
			if not bindableEvent then
				bindableEvent = Instance.new("BindableEvent")
				bindableEvent.Name = "ShipCollision"
				bindableEvent.Parent = ship
			end
			bindableEvent:Fire(hitModel)
		end
	end
	
	hull.Touched:Connect(onTouched)
	
	-- Add lighting effects for nighttime ambiance
	local lantern1 = Instance.new("PointLight")
	lantern1.Brightness = 2
	lantern1.Range = 25
	lantern1.Color = Color3.fromRGB(255, 200, 100)
	lantern1.Parent = hull
	
	local lantern2 = Instance.new("PointLight")
	lantern2.Brightness = 1.5
	lantern2.Range = 20
	lantern2.Color = Color3.fromRGB(255, 200, 100)
	lantern2.Parent = ship:FindFirstChild("Stern")
	
	-- Add sound effects
	local sailingSound = Instance.new("Sound")
	sailingSound.Name = "SailingSound"
	sailingSound.SoundId = "rbxassetid://131961136" -- Ocean/sailing ambient
	sailingSound.Volume = 0.3
	sailingSound.Looped = true
	sailingSound.Parent = hull
	
	print("[PirateShipFactory] Created pirate ship at", position)
	return ship
end

-- Cleanup function to properly destroy a ship and its components
function PirateShipFactory.destroyShip(ship: Model)
	if not ship or not ship:GetAttribute("IsPirateShip") then
		return
	end
	
	-- Stop sounds
	for _, sound in ship:GetDescendants() do
		if sound:IsA("Sound") then
			sound:Stop()
		end
	end
	
	ship:Destroy()
	print("[PirateShipFactory] Destroyed pirate ship")
end

return PirateShipFactory
