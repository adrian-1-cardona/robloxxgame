-- Builds themed island villages: wooden / cobblestone houses (with detachable salvage
-- walls you can drag to your raft), beds, torches, fences, a central campfire or well,
-- weapon pickups and lootable chests. Returns suggested villager + merchant spawn spots.
--
-- Loot props created here (walls, beds, torches) are tagged IsLootProp by LootPropFactory
-- and get auto-registered by IslandService.ensure() after the island is built, so they are
-- immediately draggable / weldable. Weapon pickups wire their own prompt on spawn. Chests
-- are wired here using the passed-in deps (toast / party accessors).

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Weapons = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Weapons"))
local Armor = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Armor"))

local LootPropFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("LootPropFactory"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

local VillageBuilder = {}

local WOOD = Color3.fromRGB(120, 84, 50)
local WOOD_DARK = Color3.fromRGB(80, 54, 32)
local ROOF_THATCH = Color3.fromRGB(150, 120, 64)
local ROOF_WOOD = Color3.fromRGB(74, 50, 30)
local STONE = Color3.fromRGB(128, 130, 132)
local STONE_DARK = Color3.fromRGB(96, 98, 100)
local MOSS = Color3.fromRGB(96, 118, 76)
local ASH = Color3.fromRGB(60, 58, 54)
local GLASS_WARM = Color3.fromRGB(255, 214, 130)
local DOOR_WOOD = Color3.fromRGB(64, 42, 26)
local NET = Color3.fromRGB(196, 188, 150)

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "VillagePart"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color or WOOD
	p.Size = props.Size or Vector3.new(1, 1, 1)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- Village geometry (houses, walls, roofs, fences, towers) no longer casts shadows by
	-- default — a town of 20+ houses was thousands of shadow-casters. Sun/terrain shadows
	-- still apply via GlobalShadows.
	p.CastShadow = props.CastShadow == true
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

-- Level-of-Detail system for buildings based on distance from players
local function setupBuildingLOD(model: Model, center: Vector3)
	local LOD_NEAR = 150   -- Full detail
	local LOD_MID = 300    -- Medium detail
	local LOD_FAR = 500    -- Low detail
	
	local lodFolder = Instance.new("Folder")
	lodFolder.Name = "LODController"
	lodFolder.Parent = model
	
	-- Create LOD script for runtime distance checking
	local lodScript = Instance.new("Script")
	lodScript.Name = "BuildingLOD"
	lodScript.Parent = lodFolder
	
		-- LOD script code (runs on server with optimizations)
	lodScript.Source = [[
		local Players = game:GetService("Players")
		local RunService = game:GetService("RunService")
		
		local model = script.Parent.Parent
		local center = Vector3.new(]] .. center.X .. [[, ]] .. center.Y .. [[, ]] .. center.Z .. [[)
		local LOD_NEAR = 150
		local LOD_MID = 300
		local LOD_FAR = 500
		
		-- Cache for performance
		local detailParts = {}
		local borderParts = {}
		local decorativeParts = {}
		
		-- Categorize parts on startup
		for _, child in pairs(model:GetChildren()) do
			if child.Name == "Village" then
				for _, building in pairs(child:GetChildren()) do
					for _, part in pairs(building:GetDescendants()) do
						if part:IsA("BasePart") then
							if part.Name:match("TimberPost") or part.Name:match("TimberBeam") or 
							   part.Name:match("WindowFrame") or part.Name:match("WindowShutter") then
								table.insert(detailParts, part)
							elseif part.Name:match("DoorHandle") or part.Name:match("RoofSupport") or
								   part.Name:match("ChimneyCap") or part.Name:match("StepRail") then
								table.insert(borderParts, part)
							elseif part.Name:match("PathBorder") or part.Name:match("Rubble") or
								   part.Name:match("Finial") or part.Name:match("LanternFrame") then
								table.insert(decorativeParts, part)
							end
						end
					end
				end
			end
		end
		
		local function getClosestPlayerDistance()
			local minDist = math.huge
			for _, player in pairs(Players:GetPlayers()) do
				if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
					local dist = (player.Character.HumanoidRootPart.Position - center).Magnitude
					minDist = math.min(minDist, dist)
				end
			end
			return minDist
		end
		
		local function setDetailLevel(level)
			-- Level 0: High detail (all visible)
			-- Level 1: Medium detail (hide fine details)  
			-- Level 2: Low detail (hide most decorative elements)
			
			-- Performance optimization: batch operations
			local hideDetail = level >= 2
			local hideBorder = level >= 1
			local hideDecorative = level >= 2
			
			for _, part in pairs(detailParts) do
				if part.Parent then
					part.Transparency = hideDetail and 1 or 0
				end
			end
			
			for _, part in pairs(borderParts) do
				if part.Parent then
					part.Transparency = hideBorder and 1 or 0
				end
			end
			
			for _, part in pairs(decorativeParts) do
				if part.Parent then
					part.Transparency = hideDecorative and 1 or 0
				end
			end
		end
		
		local lastLevel = -1
		local updateTimer = 0
		local UPDATE_INTERVAL = 1.0  -- Update every second for performance
		
		RunService.Heartbeat:Connect(function(dt)
			updateTimer += dt
			if updateTimer < UPDATE_INTERVAL then
				return
			end
			updateTimer = 0
			
			local dist = getClosestPlayerDistance()
			local level = 0
			
			if dist > LOD_FAR then
				level = 2  -- Low detail
			elseif dist > LOD_MID then 
				level = 1  -- Medium detail
			else
				level = 0  -- High detail
			end
			
			if level ~= lastLevel then
				setDetailLevel(level)
				lastLevel = level
			end
		end)
	]]
end

-- Enhanced medieval house with detailed timber framing and architectural variety.
-- `opts`: cobblestone (bool), ruined (bool), islandId (string), style ("timber"|"stone"|"cottage").
-- Walls are detachable salvage (LootPropFactory) so they can be hauled to a raft.
local function buildHouse(model: Model, cf: CFrame, opts: { [string]: any })
	local cobble = opts.cobblestone == true
	local ruined = opts.ruined == true
	local style = opts.style or (if cobble then "stone" else "timber")
	
	-- Enhanced color palette for medieval aesthetics
	local TIMBER_FRAME = Color3.fromRGB(62, 39, 35)
	local PLASTER_WHITE = Color3.fromRGB(245, 240, 230)
	local PLASTER_CREAM = Color3.fromRGB(235, 220, 200)
	local MEDIEVAL_STONE = Color3.fromRGB(140, 135, 130)
	local COBBLE_DARK = Color3.fromRGB(85, 82, 78)
	
	local wallColor = if cobble then MEDIEVAL_STONE else PLASTER_CREAM
	local wallMat = if cobble then Enum.Material.Cobblestone else Enum.Material.SmoothPlastic
	local floorColor = if cobble then COBBLE_DARK else Color3.fromRGB(104, 74, 46)

	local w, d = 16, 14
	local wallH = if ruined then 4.5 else 8.5  -- Slightly taller for more impressive medieval look

	-- Enhanced stone foundation
	local foundation = makePart({
		Name = "HouseFoundation",
		Parent = model,
		Size = Vector3.new(w + 1, 1.2, d + 1),
		CFrame = cf * CFrame.new(0, 0.6, 0),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
	})

	local floor = makePart({
		Name = "HouseFloor",
		Parent = model,
		Size = Vector3.new(w, 0.4, d),
		CFrame = cf * CFrame.new(0, 1.4, 0),
		Color = floorColor,
		Material = if cobble then Enum.Material.Slate else Enum.Material.WoodPlanks,
	})

	local wallsFolder = Instance.new("Folder")
	wallsFolder.Name = "SalvageWalls"
	wallsFolder.Parent = model

	local wallY = wallH * 0.5 + 1.6
	local specs = {
		{ Name = "WallBack", Size = Vector3.new(w, wallH, 0.8), Offset = Vector3.new(0, wallY, -d * 0.5) },
		{ Name = "WallLeft", Size = Vector3.new(0.8, wallH, d), Offset = Vector3.new(-w * 0.5, wallY, 0) },
		{ Name = "WallRight", Size = Vector3.new(0.8, wallH, d), Offset = Vector3.new(w * 0.5, wallY, 0) },
		{ Name = "WallFrontL", Size = Vector3.new(w * 0.32, wallH, 0.8), Offset = Vector3.new(-w * 0.34, wallY, d * 0.5) },
		{ Name = "WallFrontR", Size = Vector3.new(w * 0.32, wallH, 0.8), Offset = Vector3.new(w * 0.34, wallY, d * 0.5) },
	}
	
	for i, spec in specs do
		-- Ruined houses are missing a wall or two.
		if ruined and (i == 2 or i == 4) and math.random() < 0.6 then
			continue
		end
		local wallCf = cf * CFrame.new(spec.Offset)
		local wall = LootPropFactory.createWallWorld(wallsFolder, spec.Size, wallCf)
		wall.Name = spec.Name
		if opts.islandId then
			wall:SetAttribute("IslandId", opts.islandId)
		end
		wall:SetAttribute("FromHouse", true)
		if cobble then
			local prim = wall.PrimaryPart
			if prim then
				prim.Color = MEDIEVAL_STONE
				prim.Material = Enum.Material.Cobblestone
			end
		else
			local prim = wall.PrimaryPart
			if prim then
				prim.Color = wallColor
				prim.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	-- Add detailed timber framing for non-stone houses
	if not cobble and not ruined then
		-- Vertical timber posts
		for _, pos in { 
			{-w * 0.45, 0, -d * 0.45}, {w * 0.45, 0, -d * 0.45}, 
			{-w * 0.45, 0, d * 0.45}, {w * 0.45, 0, d * 0.45},
			{0, 0, -d * 0.5}, {0, 0, d * 0.5}
		} do
			makePart({
				Name = "TimberPost",
				Parent = model,
				Size = Vector3.new(0.4, wallH, 0.4),
				CFrame = cf * CFrame.new(pos[1], wallY, pos[3]),
				Color = TIMBER_FRAME,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
		
		-- Horizontal timber beams
		for y = wallH * 0.3, wallH * 0.8, wallH * 0.25 do
			-- Front and back beams
			for _, z in {-d * 0.5, d * 0.5} do
				makePart({
					Name = "TimberBeam",
					Parent = model,
					Size = Vector3.new(w * 0.9, 0.3, 0.4),
					CFrame = cf * CFrame.new(0, 1.6 + y, z),
					Color = TIMBER_FRAME,
					Material = Enum.Material.Wood,
					CanCollide = false,
				})
			end
			-- Side beams
			for _, x in {-w * 0.5, w * 0.5} do
				makePart({
					Name = "TimberBeam",
					Parent = model,
					Size = Vector3.new(0.4, 0.3, d * 0.9),
					CFrame = cf * CFrame.new(x, 1.6 + y, 0),
					Color = TIMBER_FRAME,
					Material = Enum.Material.Wood,
					CanCollide = false,
				})
			end
		end
	end

	if not ruined then
		-- Enhanced pitched roof with overhangs and detailed structure
		for i = -1, 1, 2 do
			makePart({
				Name = "RoofSlope",
				Parent = model,
				Size = Vector3.new(w * 0.65, 0.6, d + 3.0),
				CFrame = cf * CFrame.new(i * w * 0.26, wallY + wallH * 0.45 + 1.8, 0) * CFrame.Angles(0, 0, math.rad(i * -35)),
				Color = if cobble then ROOF_WOOD else Color3.fromRGB(120, 85, 45),
				Material = if cobble then Enum.Material.Wood else Enum.Material.Grass,
			})
		end
		
		-- Roof ridge beam
		makePart({
			Name = "RoofRidge",
			Parent = model,
			Size = Vector3.new(0.8, 0.8, d + 3.2),
			CFrame = cf * CFrame.new(0, wallY + wallH * 0.45 + 3.2, 0),
			Color = ROOF_WOOD,
			Material = Enum.Material.Wood,
		})
		
		-- Roof supports/rafters
		for i = -1, 1, 1 do
			if i ~= 0 then
				makePart({
					Name = "RoofSupport",
					Parent = model,
					Size = Vector3.new(0.3, w * 0.4, 0.3),
					CFrame = cf * CFrame.new(0, wallY + wallH * 0.3 + 1.5, i * d * 0.25) * CFrame.Angles(0, 0, math.rad(i * 25)),
					Color = TIMBER_FRAME,
					Material = Enum.Material.Wood,
					CanCollide = false,
				})
			end
		end
		
		-- Enhanced chimney with detailed brickwork
		if cobble or math.random() < 0.7 then
			local chimney = makePart({
				Name = "Chimney",
				Parent = model,
				Size = Vector3.new(1.6, 4.2, 1.6),
				CFrame = cf * CFrame.new(w * 0.25, wallY + wallH * 0.5 + 2.8, -d * 0.25),
				Color = if cobble then STONE_DARK else Color3.fromRGB(120, 65, 45),
				Material = if cobble then Enum.Material.Cobblestone else Enum.Material.Brick,
			})
			
			-- Chimney cap
			makePart({
				Name = "ChimneyCap",
				Parent = model,
				Size = Vector3.new(2.2, 0.4, 2.2),
				CFrame = cf * CFrame.new(w * 0.25, wallY + wallH * 0.5 + 5.2, -d * 0.25),
				Color = STONE_DARK,
				Material = Enum.Material.Slate,
			})
			
			local smoke = Instance.new("Smoke")
			smoke.Size = 2.8
			smoke.Opacity = 0.3
			smoke.RiseVelocity = 5
			smoke.Color = Color3.fromRGB(180, 180, 180)
			smoke.Parent = chimney
		end
	else
		-- Enhanced ruins with more detail
		makePart({
			Name = "CollapsedBeam",
			Parent = model,
			Size = Vector3.new(w * 0.8, 0.6, 0.6),
			CFrame = cf * CFrame.new(0, wallH * 0.4, 0) * CFrame.Angles(0, math.rad(18), math.rad(24)),
			Color = MOSS,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		
		-- Rubble pile
		for i = 1, 3 do
			makePart({
				Name = "Rubble",
				Parent = model,
				Size = Vector3.new(1 + math.random(), 0.8 + math.random() * 0.4, 1 + math.random()),
				CFrame = cf * CFrame.new((math.random() - 0.5) * w * 0.8, 2, (math.random() - 0.5) * d * 0.8),
				Color = STONE_DARK,
				Material = Enum.Material.Concrete,
				CanCollide = false,
				Shape = Enum.PartType.Block,
			})
		end
	end

	-- Enhanced door with frame and details
	if not ruined or math.random() < 0.5 then
		-- Door frame
		makePart({
			Name = "DoorFrame",
			Parent = model,
			Size = Vector3.new(w * 0.32, wallH * 0.8, 0.2),
			CFrame = cf * CFrame.new(0, wallY - wallH * 0.1, d * 0.5 + 0.1),
			Color = TIMBER_FRAME,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		
		-- Door
		makePart({
			Name = "Door",
			Parent = model,
			Size = Vector3.new(w * 0.26, wallH * 0.72, 0.3),
			CFrame = cf * CFrame.new(0, wallY - wallH * 0.14, d * 0.5 + 0.05),
			Color = Color3.fromRGB(85, 55, 35),
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		
		-- Door handle
		makePart({
			Name = "DoorHandle",
			Parent = model,
			Size = Vector3.new(0.2, 0.2, 0.3),
			CFrame = cf * CFrame.new(w * 0.08, wallY - wallH * 0.14, d * 0.5 + 0.2),
			Color = Color3.fromRGB(60, 60, 60),
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end

	-- Enhanced windows with frames and shutters
	if not ruined then
		for i = -1, 1, 2 do
			-- Window frame
			makePart({
				Name = "WindowFrame",
				Parent = model,
				Size = Vector3.new(0.4, 2.2, 2.4),
				CFrame = cf * CFrame.new(i * w * 0.5, wallY - wallH * 0.1, d * 0.1),
				Color = TIMBER_FRAME,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
			
			-- Window pane (diamond pattern)
			local pane = makePart({
				Name = "Window",
				Parent = model,
				Size = Vector3.new(0.2, 1.8, 2.0),
				CFrame = cf * CFrame.new(i * w * 0.5, wallY - wallH * 0.1, d * 0.1),
				Color = GLASS_WARM,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			pane.Transparency = 0.12
			
			-- Window shutters
			for j = -1, 1, 2 do
				makePart({
					Name = "WindowShutter",
					Parent = model,
					Size = Vector3.new(0.3, 1.8, 0.8),
					CFrame = cf * CFrame.new(i * w * 0.5, wallY - wallH * 0.1, d * 0.1 + j * 1.2),
					Color = Color3.fromRGB(65, 45, 30),
					Material = Enum.Material.Wood,
					CanCollide = false,
				})
			end
		end
	end

	-- Interior bed (loot) + torch (loot)
	local bed = LootPropFactory.createBedWorld(model, cf * CFrame.new(-w * 0.25, 2.5, -d * 0.22))
	if opts.islandId then
		bed:SetAttribute("IslandId", opts.islandId)
	end
	local torch = LootPropFactory.createTorchWorld(model, cf * CFrame.new(w * 0.28, 3.5, -d * 0.22))
	if opts.islandId then
		torch:SetAttribute("IslandId", opts.islandId)
	end
end

-- Enhanced cobblestone street network connecting buildings and village center
local function buildCobblestoneStreets(model: Model, center: Vector3, topY: number, villagerSpots: { Vector3 }, villageRadius: number)
	local COBBLE_MAIN = Color3.fromRGB(110, 108, 105)
	local COBBLE_ACCENT = Color3.fromRGB(95, 92, 88)
	
	-- Main town square (circular plaza)
	local squareRadius = villageRadius * 0.25
	makePart({
		Name = "TownSquare",
		Parent = model,
		Size = Vector3.new(squareRadius * 2, 0.3, squareRadius * 2),
		CFrame = CFrame.new(center.X, topY + 0.15, center.Z),
		Color = COBBLE_MAIN,
		Material = Enum.Material.Cobblestone,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	
	-- Radial streets from center to houses
	for i, spot in villagerSpots do
		if i > #villagerSpots * 0.7 then break end -- Don't connect every house to avoid overcrowding
		
		local direction = (Vector3.new(spot.X, topY, spot.Z) - Vector3.new(center.X, topY, center.Z)).Unit
		local distance = (Vector3.new(spot.X, topY, spot.Z) - Vector3.new(center.X, topY, center.Z)).Magnitude
		local pathLength = distance - squareRadius - 8 -- Leave gaps at both ends
		
		if pathLength > 10 then
			local pathCenter = Vector3.new(center.X, topY, center.Z) + direction * (squareRadius + pathLength * 0.5 + 8)
			
			-- Main path
			makePart({
				Name = "CobblePath",
				Parent = model,
				Size = Vector3.new(4, 0.2, pathLength),
				CFrame = CFrame.lookAt(pathCenter, pathCenter + direction) * CFrame.Angles(math.rad(90), 0, 0),
				Color = COBBLE_MAIN,
				Material = Enum.Material.Cobblestone,
				CanCollide = false,
			})
			
			-- Path border stones
			for side = -1, 1, 2 do
				makePart({
					Name = "PathBorder",
					Parent = model,
					Size = Vector3.new(0.5, 0.3, pathLength + 2),
					CFrame = CFrame.lookAt(pathCenter + direction:Cross(Vector3.new(0, 1, 0)) * side * 2.2, pathCenter + direction + direction:Cross(Vector3.new(0, 1, 0)) * side * 2.2) * CFrame.Angles(math.rad(90), 0, 0),
					Color = COBBLE_ACCENT,
					Material = Enum.Material.Cobblestone,
					CanCollide = false,
				})
			end
		end
	end
	
	-- Connecting ring road around the village
	local ringRadius = villageRadius * 0.65
	local segments = 24
	for i = 1, segments do
		local angle1 = (i - 1) / segments * math.pi * 2
		local angle2 = i / segments * math.pi * 2
		local pos1 = Vector3.new(center.X + math.cos(angle1) * ringRadius, topY, center.Z + math.sin(angle1) * ringRadius)
		local pos2 = Vector3.new(center.X + math.cos(angle2) * ringRadius, topY, center.Z + math.sin(angle2) * ringRadius)
		local segmentCenter = (pos1 + pos2) * 0.5
		local segmentLength = (pos2 - pos1).Magnitude
		
		makePart({
			Name = "RingRoad",
			Parent = model,
			Size = Vector3.new(3, 0.2, segmentLength),
			CFrame = CFrame.lookAt(segmentCenter, pos2) * CFrame.Angles(math.rad(90), 0, 0),
			Color = COBBLE_MAIN,
			Material = Enum.Material.Cobblestone,
			CanCollide = false,
		})
	end
end

-- A perimeter of short posts + rails around the village heart.
local function buildFenceRing(model: Model, center: Vector3, topY: number, radius: number)
	local posts = math.clamp(math.floor(radius / 6), 10, 40)
	for i = 1, posts do
		local a = (i / posts) * math.pi * 2
		local x = center.X + math.cos(a) * radius
		local z = center.Z + math.sin(a) * radius
		makePart({
			Name = "FencePost",
			Parent = model,
			Size = Vector3.new(0.5, 3, 0.5),
			CFrame = CFrame.new(x, topY + 1.3, z),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end
end

local function buildCampfire(model: Model, pos: Vector3)
	local ring = makePart({
		Name = "FirePit",
		Parent = model,
		Size = Vector3.new(4, 0.5, 4),
		CFrame = CFrame.new(pos),
		Color = STONE_DARK,
		Material = Enum.Material.Slate,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	local logs = makePart({
		Name = "Logs",
		Parent = model,
		Size = Vector3.new(2.4, 1.0, 2.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)),
		Color = ASH,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.Parent = logs
	local light = Instance.new("PointLight")
	light.Brightness = 3
	light.Range = 34
	light.Color = Color3.fromRGB(255, 176, 90)
	light.Parent = logs
end

-- A lootable chest. Wired here with deps so IslandService stays lean.
local function buildChest(model: Model, cf: CFrame, islandId: string, deps: { [string]: any })
	local chest = makePart({
		Name = "VillageChest",
		Parent = model,
		Size = Vector3.new(2.6, 1.7, 1.7),
		CFrame = cf,
		Color = Color3.fromRGB(96, 68, 36),
		Material = Enum.Material.Wood,
	})
	chest:SetAttribute("IslandId", islandId)
	makePart({
		Name = "ChestLid",
		Parent = model,
		Size = Vector3.new(2.75, 0.4, 1.85),
		CFrame = cf * CFrame.new(0, 1.0, 0),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
	})

	local anchor = makePart({
		Name = "ChestPromptAnchor",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = cf * CFrame.new(0, 1.4, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Loot"
	prompt.ObjectText = "Village Cache"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		if deps.isLocked and deps.getPartyCode then
			local code = deps.getPartyCode(player)
			if code and deps.isLocked(code, islandId) then
				if deps.toast then
					deps.toast(player, "This isle is closed to your crew.", "error")
				end
				return
			end
		end
		if chest:GetAttribute("Looted_" .. player.UserId) == true then
			if deps.toast then
				deps.toast(player, "You already looted this cache.", "info")
			end
			return
		end
		chest:SetAttribute("Looted_" .. player.UserId, true)
		VillageBuilder.grantChestLoot(player, deps)
	end)
end

-- Random chest reward: weapon (+starter ammo), armor, ammo bundle, or currency.
function VillageBuilder.grantChestLoot(player: Player, deps: { [string]: any })
	local roll = math.random()
	if roll < 0.38 then
		local weaponId = Weapons.rollLootWeapon(function(a, b)
			return math.random(a, b)
		end)
		local def = Weapons.get(weaponId)
		WeaponService.giveWeapon(player, weaponId, true)
		if def and def.Class == "ranged" and def.Ammo then
			WeaponService.giveAmmo(player, def.Ammo, Weapons.AmmoBundle[def.Ammo] or 6)
		end
		if deps.toast then
			deps.toast(player, `Looted a {def and def.Name or weaponId}!`, "success")
		end
	elseif roll < 0.58 and deps.wearArmor then
		-- Armor cache — equipped straight away (swaps the slot).
		local armorId = Armor.rollLootArmor(function(a, b)
			return math.random(a, b)
		end)
		local def = Armor.get(armorId)
		deps.wearArmor(player, armorId)
		if deps.toast and def then
			deps.toast(player, `Looted {def.Name} armor!`, "success")
		end
	elseif roll < 0.78 then
		local types = { "Bullet", "Shell", "Arrow", "Powder" }
		local ammoId = types[math.random(1, #types)]
		local amount = (Weapons.AmmoBundle[ammoId] or 6) * math.random(1, 2)
		WeaponService.giveAmmo(player, ammoId, amount)
		if deps.toast then
			deps.toast(player, `Found {amount} {Weapons.Ammo[ammoId].Label}.`, "success")
		end
	else
		local doubloons = math.random(10, 30)
		local scrap = math.random(3, 8)
		WeaponService.addCurrency(player, "Doubloons", doubloons)
		WeaponService.addCurrency(player, "Scrap", scrap)
		if deps.toast then
			deps.toast(player, `Found {doubloons} Doubloons & {scrap} Scrap.`, "success")
		end
	end
end

-- A stone well — village centrepiece for stone settlements.
local function buildWell(model: Model, pos: Vector3)
	-- Vertical stone ring (cylinder axis is local X, so rotate 90° about Z to stand it up).
	makePart({
		Name = "WellRing",
		Parent = model,
		Size = Vector3.new(2.4, 4.4, 4.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE,
		Material = Enum.Material.Cobblestone,
		Shape = Enum.PartType.Cylinder,
		CanCollide = true,
	})
	makePart({
		Name = "WellWater",
		Parent = model,
		Size = Vector3.new(3.4, 0.3, 3.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.0, 0)),
		Color = Color3.fromRGB(40, 96, 120),
		Material = Enum.Material.Glass,
		CanCollide = false,
	})
	for i = -1, 1, 2 do
		makePart({
			Name = "WellPost",
			Parent = model,
			Size = Vector3.new(0.4, 3.4, 0.4),
			CFrame = CFrame.new(pos + Vector3.new(i * 1.9, 3.0, 0)),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
		})
	end
	makePart({
		Name = "WellRoof",
		Parent = model,
		Size = Vector3.new(5.0, 0.4, 2.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.8, 0)),
		Color = ROOF_WOOD,
		Material = Enum.Material.Wood,
	})
end

-- A covered market stall with a striped awning — a town square touch.
local function buildMarketStall(model: Model, cf: CFrame)
	makePart({
		Name = "StallCounter",
		Parent = model,
		Size = Vector3.new(5, 1.6, 2),
		CFrame = cf * CFrame.new(0, 0.8, 0),
		Color = WOOD,
		Material = Enum.Material.Wood,
	})
	for _, sx in { -2.2, 2.2 } do
		makePart({
			Name = "StallPost",
			Parent = model,
			Size = Vector3.new(0.3, 4.2, 0.3),
			CFrame = cf * CFrame.new(sx, 2.1, -0.8),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
		})
	end
	makePart({
		Name = "StallAwning",
		Parent = model,
		Size = Vector3.new(5.6, 0.3, 3),
		CFrame = cf * CFrame.new(0, 4.2, -0.2) * CFrame.Angles(math.rad(-16), 0, 0),
		Color = Color3.fromRGB(180, 72, 66),
		Material = Enum.Material.Fabric,
	})
end

-- Fish-drying rack with hanging catch — a fishing-village staple.
local function buildFishRack(model: Model, cf: CFrame)
	for _, sx in { -2, 2 } do
		makePart({
			Name = "RackPost",
			Parent = model,
			Size = Vector3.new(0.3, 3.4, 0.3),
			CFrame = cf * CFrame.new(sx, 1.7, 0),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
		})
	end
	makePart({
		Name = "RackBar",
		Parent = model,
		Size = Vector3.new(4.4, 0.25, 0.25),
		CFrame = cf * CFrame.new(0, 3.2, 0),
		Color = WOOD,
		Material = Enum.Material.Wood,
	})
	for i = -1, 1 do
		makePart({
			Name = "DryingNet",
			Parent = model,
			Size = Vector3.new(0.1, 1.6, 1.2),
			CFrame = cf * CFrame.new(i * 1.3, 2.2, 0),
			Color = NET,
			Material = Enum.Material.Fabric,
			CanCollide = false,
		})
	end
end

-- A stone watchtower — stone-town skyline landmark with a torch on top.
local function buildWatchtower(model: Model, pos: Vector3)
	makePart({
		Name = "TowerBody",
		Parent = model,
		Size = Vector3.new(6, 18, 6),
		CFrame = CFrame.new(pos + Vector3.new(0, 9, 0)),
		Color = STONE,
		Material = Enum.Material.Cobblestone,
		CanCollide = true,
	})
	makePart({
		Name = "TowerCrown",
		Parent = model,
		Size = Vector3.new(7, 1.6, 7),
		CFrame = CFrame.new(pos + Vector3.new(0, 18.5, 0)),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
	})
	-- Battlement teeth
	for i = 0, 3 do
		local a = math.rad(i * 90)
		makePart({
			Name = "Merlon",
			Parent = model,
			Size = Vector3.new(1.4, 1.6, 1.4),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 2.6, 19.8, math.sin(a) * 2.6)),
			Color = STONE,
			Material = Enum.Material.Cobblestone,
		})
	end
end

-- === Palette for grand structures (church / mansion / castle / lamps) ===============
local STONE_LIGHT = Color3.fromRGB(178, 180, 182)
local GOLD = Color3.fromRGB(226, 190, 96)
local BANNER = Color3.fromRGB(150, 46, 52)
local BANNER_GOLD = Color3.fromRGB(210, 176, 96)
local LAMP_GLASS = Color3.fromRGB(255, 224, 150)
local IRON = Color3.fromRGB(58, 60, 66)
local STAINED = {
	Color3.fromRGB(196, 72, 72),
	Color3.fromRGB(72, 132, 196),
	Color3.fromRGB(96, 176, 96),
	Color3.fromRGB(226, 196, 96),
}

-- A warm glowing lantern head + PointLight (shadowless — see makePart notes). Used by
-- lamp posts, mansions and castle walls to make a settlement read as "lit up".
local function attachLampGlow(holder: BasePart, range: number?)
	local light = Instance.new("PointLight")
	light.Brightness = 2.2
	light.Range = range or 26
	light.Color = Color3.fromRGB(255, 206, 130)
	light.Shadows = false
	light.Parent = holder
	return light
end

-- A climbable ladder. TrussParts are auto-climbable by Roblox Humanoids, so this is a
-- real way to scale towers, steeples and cliffs. `height` studs tall, base at basePos.
local function buildLadder(model: Model, basePos: Vector3, height: number, yaw: number?): BasePart
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Anchored = true
	truss.CanCollide = true
	truss.Color = Color3.fromRGB(96, 66, 40)
	truss.Material = Enum.Material.Wood
	-- TrussPart climbs along its Y axis; X/Z are fixed at 2 studs.
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = CFrame.new(basePos + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(0, yaw or 0, 0)
	truss.CastShadow = false
	truss.Parent = model
	return truss
end

-- A lit iron street lamp — the backbone of a town that glows at night.
local function buildLampPost(model: Model, pos: Vector3)
	makePart({
		Name = "LampPost",
		Parent = model,
		Size = Vector3.new(0.5, 7.5, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.75, 0)),
		Color = IRON,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	local lantern = makePart({
		Name = "Lantern",
		Parent = model,
		Size = Vector3.new(1.1, 1.5, 1.1),
		CFrame = CFrame.new(pos + Vector3.new(0, 7.7, 0)),
		Color = LAMP_GLASS,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	makePart({
		Name = "LampCap",
		Parent = model,
		Size = Vector3.new(1.5, 0.4, 1.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 8.6, 0)),
		Color = IRON,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	attachLampGlow(lantern, 30)
end

-- A stone church: nave with a pitched roof, arched stained-glass windows, a warm interior
-- glow, and a tall bell tower topped with a golden cross. A climbable ladder runs up the
-- tower so players can reach the belfry. `cf` faces the church entrance toward +Z.
local function buildChurch(model: Model, cf: CFrame, islandId: string?)
	local w, d, wallH = 18, 30, 13

	makePart({
		Name = "ChurchFloor",
		Parent = model,
		Size = Vector3.new(w + 1, 0.8, d + 1),
		CFrame = cf * CFrame.new(0, 0.4, 0),
		Color = STONE_DARK,
		Material = Enum.Material.Slate,
	})

	-- Four stone walls (front wall split to leave a doorway).
	local wallY = wallH * 0.5 + 0.8
	local wallSpecs = {
		{ Name = "NaveBack", Size = Vector3.new(w, wallH, 0.9), Offset = Vector3.new(0, wallY, -d * 0.5) },
		{ Name = "NaveLeft", Size = Vector3.new(0.9, wallH, d), Offset = Vector3.new(-w * 0.5, wallY, 0) },
		{ Name = "NaveRight", Size = Vector3.new(0.9, wallH, d), Offset = Vector3.new(w * 0.5, wallY, 0) },
		{ Name = "NaveFrontL", Size = Vector3.new(w * 0.36, wallH, 0.9), Offset = Vector3.new(-w * 0.32, wallY, d * 0.5) },
		{ Name = "NaveFrontR", Size = Vector3.new(w * 0.36, wallH, 0.9), Offset = Vector3.new(w * 0.32, wallY, d * 0.5) },
	}
	for _, spec in wallSpecs do
		makePart({
			Name = spec.Name,
			Parent = model,
			Size = spec.Size,
			CFrame = cf * CFrame.new(spec.Offset),
			Color = STONE,
			Material = Enum.Material.Cobblestone,
		})
	end

	-- Pitched roof panels + ridge.
	for i = -1, 1, 2 do
		makePart({
			Name = "ChurchRoof",
			Parent = model,
			Size = Vector3.new(w * 0.64, 0.6, d + 2),
			CFrame = cf * CFrame.new(i * w * 0.25, wallY + wallH * 0.5 + 1.4, 0) * CFrame.Angles(0, 0, math.rad(i * -34)),
			Color = ROOF_WOOD,
			Material = Enum.Material.Wood,
		})
	end
	makePart({
		Name = "ChurchRidge",
		Parent = model,
		Size = Vector3.new(0.7, 0.7, d + 2.1),
		CFrame = cf * CFrame.new(0, wallY + wallH * 0.5 + 2.6, 0),
		Color = ROOF_WOOD,
		Material = Enum.Material.Wood,
	})

	-- Arched stained-glass windows down each side (emissive so they "glow").
	for i = -2, 2 do
		if i == 0 then
			continue
		end
		for side = -1, 1, 2 do
			local pane = makePart({
				Name = "StainedGlass",
				Parent = model,
				Size = Vector3.new(0.3, 3.4, 1.6),
				CFrame = cf * CFrame.new(side * w * 0.5, wallY, i * d * 0.16),
				Color = STAINED[((i + 2) % #STAINED) + 1],
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			pane.Transparency = 0.12
		end
	end

	-- Big doors.
	makePart({
		Name = "ChurchDoor",
		Parent = model,
		Size = Vector3.new(w * 0.24, wallH * 0.66, 0.4),
		CFrame = cf * CFrame.new(0, wallY - wallH * 0.16, d * 0.5),
		Color = DOOR_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})

	-- Warm interior glow.
	local glowHolder = makePart({
		Name = "ChurchGlow",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = cf * CFrame.new(0, wallH * 0.5, 0),
		Transparency = 1,
		CanCollide = false,
	})
	attachLampGlow(glowHolder, 46)

	-- Bell tower at the back, rising well above the roof.
	local towerH = wallH + 16
	local towerW = 6
	local towerCf = cf * CFrame.new(0, 0, -d * 0.5 + towerW * 0.5)
	makePart({
		Name = "BellTower",
		Parent = model,
		Size = Vector3.new(towerW, towerH, towerW),
		CFrame = towerCf * CFrame.new(0, towerH * 0.5 + 0.8, 0),
		Color = STONE,
		Material = Enum.Material.Cobblestone,
	})
	-- Belfry openings (dark) near the top.
	for side = -1, 1, 2 do
		makePart({
			Name = "BelfryArch",
			Parent = model,
			Size = Vector3.new(towerW + 0.1, 3, 1.4),
			CFrame = towerCf * CFrame.new(0, towerH - 3, side * (towerW * 0.5 - 0.2)),
			Color = STONE_DARK,
			Material = Enum.Material.Slate,
			CanCollide = false,
		})
	end
	-- The bell.
	makePart({
		Name = "Bell",
		Parent = model,
		Size = Vector3.new(2, 2.2, 2),
		CFrame = towerCf * CFrame.new(0, towerH - 3, 0),
		Color = GOLD,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	-- Spire + golden cross crowning the steeple.
	makePart({
		Name = "Spire",
		Parent = model,
		Size = Vector3.new(towerW - 1, 5, towerW - 1),
		CFrame = towerCf * CFrame.new(0, towerH + 3, 0),
		Color = ROOF_WOOD,
		Material = Enum.Material.Wood,
	})
	makePart({
		Name = "CrossV",
		Parent = model,
		Size = Vector3.new(0.5, 3.2, 0.5),
		CFrame = towerCf * CFrame.new(0, towerH + 7.2, 0),
		Color = GOLD,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	makePart({
		Name = "CrossH",
		Parent = model,
		Size = Vector3.new(2, 0.5, 0.5),
		CFrame = towerCf * CFrame.new(0, towerH + 7.8, 0),
		Color = GOLD,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})

	-- Climbable ladder up the outside of the tower to reach the belfry.
	local _, churchYaw = cf:ToOrientation()
	buildLadder(model, (towerCf * CFrame.new(0, 0, -towerW * 0.5 - 0.6)).Position, towerH - 2, churchYaw)
end

-- A grand two-storey manor house: columned portico entrance, many lit windows, a balcony
-- and a chimney. `cobble` gives it a stone-town palette instead of timber.
local function buildMansion(model: Model, cf: CFrame, cobble: boolean, islandId: string?)
	local w, d = 24, 20
	local storyH = 7
	local wallColor = if cobble then STONE else Color3.fromRGB(150, 120, 84)
	local wallMat = if cobble then Enum.Material.Cobblestone else Enum.Material.WoodPlanks

	makePart({
		Name = "ManorFloor",
		Parent = model,
		Size = Vector3.new(w + 1, 0.8, d + 1),
		CFrame = cf * CFrame.new(0, 0.4, 0),
		Color = STONE_DARK,
		Material = Enum.Material.Slate,
	})

	-- Two stacked storeys of solid walls (front wall left open at ground for the portico).
	for story = 0, 1 do
		local baseY = 0.8 + story * storyH + storyH * 0.5
		local specs = {
			{ Name = "Back", Size = Vector3.new(w, storyH, 0.8), Offset = Vector3.new(0, baseY, -d * 0.5) },
			{ Name = "Left", Size = Vector3.new(0.8, storyH, d), Offset = Vector3.new(-w * 0.5, baseY, 0) },
			{ Name = "Right", Size = Vector3.new(0.8, storyH, d), Offset = Vector3.new(w * 0.5, baseY, 0) },
			{ Name = "Front", Size = Vector3.new(w, storyH, 0.8), Offset = Vector3.new(0, baseY, d * 0.5) },
		}
		for _, spec in specs do
			-- Ground front stays open (portico), upper front is solid with a balcony rail.
			if story == 0 and spec.Name == "Front" then
				continue
			end
			makePart({
				Name = `Manor_{spec.Name}_{story}`,
				Parent = model,
				Size = spec.Size,
				CFrame = cf * CFrame.new(spec.Offset),
				Color = wallColor,
				Material = wallMat,
			})
		end
		-- Storey divider slab.
		makePart({
			Name = `ManorFloorSlab_{story}`,
			Parent = model,
			Size = Vector3.new(w, 0.5, d),
			CFrame = cf * CFrame.new(0, 0.8 + (story + 1) * storyH, 0),
			Color = STONE_DARK,
			Material = Enum.Material.Slate,
		})
		-- Lit windows around this storey.
		for i = -1, 1, 2 do
			for _, zf in { -0.28, 0.0, 0.28 } do
				local pane = makePart({
					Name = "ManorWindow",
					Parent = model,
					Size = Vector3.new(0.3, 2.6, 1.6),
					CFrame = cf * CFrame.new(i * w * 0.5, baseY, zf * d),
					Color = GLASS_WARM,
					Material = Enum.Material.Neon,
					CanCollide = false,
				})
				pane.Transparency = 0.15
			end
		end
	end

	-- Portico: columns + entablature over the ground-floor entrance.
	for _, sx in { -w * 0.32, -w * 0.11, w * 0.11, w * 0.32 } do
		makePart({
			Name = "Column",
			Parent = model,
			Size = Vector3.new(1.4, storyH - 0.5, 1.4),
			CFrame = cf * CFrame.new(sx, 0.8 + (storyH - 0.5) * 0.5, d * 0.5 + 2.2),
			Color = STONE_LIGHT,
			Material = Enum.Material.Marble,
		})
	end
	makePart({
		Name = "Portico",
		Parent = model,
		Size = Vector3.new(w * 0.86, 0.8, 5),
		CFrame = cf * CFrame.new(0, 0.8 + storyH, d * 0.5 + 1.6),
		Color = STONE_LIGHT,
		Material = Enum.Material.Marble,
	})
	-- Balcony rail on the upper front.
	makePart({
		Name = "BalconyRail",
		Parent = model,
		Size = Vector3.new(w * 0.86, 1.1, 0.4),
		CFrame = cf * CFrame.new(0, 0.8 + storyH + 0.9, d * 0.5 + 3.8),
		Color = STONE_LIGHT,
		Material = Enum.Material.Marble,
		CanCollide = false,
	})

	-- Pitched roof + chimney.
	for i = -1, 1, 2 do
		makePart({
			Name = "ManorRoof",
			Parent = model,
			Size = Vector3.new(w * 0.62, 0.6, d + 2),
			CFrame = cf * CFrame.new(i * w * 0.24, 0.8 + 2 * storyH + 1.6, 0) * CFrame.Angles(0, 0, math.rad(i * -30)),
			Color = ROOF_WOOD,
			Material = Enum.Material.Wood,
		})
	end
	local chimney = makePart({
		Name = "ManorChimney",
		Parent = model,
		Size = Vector3.new(1.6, 4, 1.6),
		CFrame = cf * CFrame.new(w * 0.3, 0.8 + 2 * storyH + 3, -d * 0.3),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
	})
	local smoke = Instance.new("Smoke")
	smoke.Size = 3
	smoke.Opacity = 0.22
	smoke.RiseVelocity = 5
	smoke.Color = Color3.fromRGB(180, 180, 180)
	smoke.Parent = chimney
end

-- A huge castle: square curtain walls with battlements, four corner towers, a gatehouse,
-- a tall central keep, hanging banners, wall torches, and climbable ladders up the towers.
-- Centred on `center`, sized by `radius` (half the wall span). Reused by the "castle" theme.
local function buildCastle(model: Model, center: Vector3, topY: number, radius: number, islandId: string?)
	local wallH = 20
	local wallT = 3
	local half = radius
	local baseY = topY + wallH * 0.5

	local function wallRun(name: string, size: Vector3, pos: Vector3)
		makePart({
			Name = name,
			Parent = model,
			Size = size,
			CFrame = CFrame.new(pos),
			Color = STONE,
			Material = Enum.Material.Cobblestone,
		})
	end

	-- Four curtain walls, with a gap in the front (+Z) wall for the gate.
	wallRun("WallBack", Vector3.new(half * 2, wallH, wallT), Vector3.new(center.X, baseY, center.Z - half))
	wallRun("WallLeft", Vector3.new(wallT, wallH, half * 2), Vector3.new(center.X - half, baseY, center.Z))
	wallRun("WallRight", Vector3.new(wallT, wallH, half * 2), Vector3.new(center.X + half, baseY, center.Z))
	local gateGap = half * 0.5
	wallRun("WallFrontL", Vector3.new(half - gateGap * 0.5, wallH, wallT), Vector3.new(center.X - (half + gateGap * 0.5) * 0.5, baseY, center.Z + half))
	wallRun("WallFrontR", Vector3.new(half - gateGap * 0.5, wallH, wallT), Vector3.new(center.X + (half + gateGap * 0.5) * 0.5, baseY, center.Z + half))

	-- Battlement merlons along all four wall tops.
	local function crenellate(fromP: Vector3, toP: Vector3)
		local span = (toP - fromP).Magnitude
		local count = math.max(2, math.floor(span / 6))
		for i = 0, count do
			local t = i / count
			local p = fromP:Lerp(toP, t)
			makePart({
				Name = "Merlon",
				Parent = model,
				Size = Vector3.new(2, 2.4, 2),
				CFrame = CFrame.new(p.X, topY + wallH + 1.2, p.Z),
				Color = STONE_DARK,
				Material = Enum.Material.Cobblestone,
				CastShadow = false,
			})
		end
	end
	crenellate(Vector3.new(center.X - half, 0, center.Z - half), Vector3.new(center.X + half, 0, center.Z - half))
	crenellate(Vector3.new(center.X - half, 0, center.Z + half), Vector3.new(center.X + half, 0, center.Z + half))
	crenellate(Vector3.new(center.X - half, 0, center.Z - half), Vector3.new(center.X - half, 0, center.Z + half))
	crenellate(Vector3.new(center.X + half, 0, center.Z - half), Vector3.new(center.X + half, 0, center.Z + half))

	-- Four corner towers (taller than the walls) with a ladder up each + a torch on top.
	local towerH = wallH + 14
	for _, corner in {
		Vector3.new(-half, 0, -half),
		Vector3.new(half, 0, -half),
		Vector3.new(-half, 0, half),
		Vector3.new(half, 0, half),
	} do
		local tx, tz = center.X + corner.X, center.Z + corner.Z
		makePart({
			Name = "CornerTower",
			Parent = model,
			Size = Vector3.new(9, towerH, 9),
			CFrame = CFrame.new(tx, topY + towerH * 0.5, tz),
			Color = STONE,
			Material = Enum.Material.Cobblestone,
		})
		makePart({
			Name = "TowerCrown",
			Parent = model,
			Size = Vector3.new(10.5, 1.6, 10.5),
			CFrame = CFrame.new(tx, topY + towerH + 0.8, tz),
			Color = STONE_DARK,
			Material = Enum.Material.Cobblestone,
		})
		for i = 0, 3 do
			local a = math.rad(i * 90 + 45)
			makePart({
				Name = "TowerMerlon",
				Parent = model,
				Size = Vector3.new(1.6, 1.8, 1.6),
				CFrame = CFrame.new(tx + math.cos(a) * 4, topY + towerH + 2, tz + math.sin(a) * 4),
				Color = STONE_DARK,
				Material = Enum.Material.Cobblestone,
				CastShadow = false,
			})
		end
		buildLadder(model, Vector3.new(tx + 5.4, topY, tz), towerH - 2)
		local torch = LootPropFactory.createTorchWorld(model, CFrame.new(tx, topY + towerH + 1.6, tz))
		if islandId then
			torch:SetAttribute("IslandId", islandId)
		end
	end

	-- Gatehouse framing the entrance, with a raised portcullis and banners.
	for _, sx in { -gateGap * 0.5 - 1.5, gateGap * 0.5 + 1.5 } do
		makePart({
			Name = "GatePillar",
			Parent = model,
			Size = Vector3.new(3, wallH + 6, wallT + 2),
			CFrame = CFrame.new(center.X + sx, topY + (wallH + 6) * 0.5, center.Z + half),
			Color = STONE_DARK,
			Material = Enum.Material.Cobblestone,
		})
	end
	makePart({
		Name = "GateArch",
		Parent = model,
		Size = Vector3.new(gateGap + 5, 4, wallT + 2),
		CFrame = CFrame.new(center.X, topY + wallH + 4, center.Z + half),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
	})
	makePart({
		Name = "Portcullis",
		Parent = model,
		Size = Vector3.new(gateGap, 6, 0.4),
		CFrame = CFrame.new(center.X, topY + wallH + 5, center.Z + half),
		Color = IRON,
		Material = Enum.Material.DiamondPlate,
		CanCollide = false,
	})
	for _, sx in { -gateGap * 0.5 - 1.5, gateGap * 0.5 + 1.5 } do
		makePart({
			Name = "GateBanner",
			Parent = model,
			Size = Vector3.new(0.3, 6, 2.4),
			CFrame = CFrame.new(center.X + sx, topY + wallH - 1, center.Z + half + wallT * 0.5 + 0.3),
			Color = BANNER,
			Material = Enum.Material.Fabric,
			CanCollide = false,
		})
	end

	-- Central keep: a tall square tower with its own battlements and a ladder up.
	local keepW = math.max(16, half * 0.7)
	local keepH = towerH + 14
	makePart({
		Name = "Keep",
		Parent = model,
		Size = Vector3.new(keepW, keepH, keepW),
		CFrame = CFrame.new(center.X, topY + keepH * 0.5, center.Z),
		Color = STONE,
		Material = Enum.Material.Cobblestone,
	})
	makePart({
		Name = "KeepCrown",
		Parent = model,
		Size = Vector3.new(keepW + 2, 2, keepW + 2),
		CFrame = CFrame.new(center.X, topY + keepH + 1, center.Z),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
	})
	for i = 0, 7 do
		local a = math.rad(i * 45)
		makePart({
			Name = "KeepMerlon",
			Parent = model,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(center.X + math.cos(a) * keepW * 0.5, topY + keepH + 2.5, center.Z + math.sin(a) * keepW * 0.5),
			Color = STONE_DARK,
			Material = Enum.Material.Cobblestone,
			CastShadow = false,
		})
	end
	-- Keep banner + a golden pennant on top.
	makePart({
		Name = "KeepBanner",
		Parent = model,
		Size = Vector3.new(0.3, 8, 3),
		CFrame = CFrame.new(center.X, topY + keepH * 0.7, center.Z + keepW * 0.5 + 0.3),
		Color = BANNER,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	makePart({
		Name = "KeepPennant",
		Parent = model,
		Size = Vector3.new(0.4, 6, 0.4),
		CFrame = CFrame.new(center.X, topY + keepH + 5, center.Z),
		Color = BANNER_GOLD,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	buildLadder(model, Vector3.new(center.X + keepW * 0.5 + 0.6, topY, center.Z), keepH - 2)
end

-- Main entry. Returns { villagerSpots = {Vector3}, merchantSpot = Vector3 }.
function VillageBuilder.build(
	model: Model,
	center: Vector3,
	size: number,
	topY: number,
	entry: { [string]: any },
	deps: { [string]: any }
): { villagerSpots: { Vector3 }, merchantSpot: Vector3 }
	local theme = entry.Theme or "village"
	local islandId = entry.Id
	local abandoned = entry.Abandoned == true
	-- Stone settlements (stone_village / stone_town) get cobblestone houses.
	local cobble = theme == "stone_village" or theme == "stone_town"
	-- Towns are larger settlements — more houses spread over a wider heart.
	local isTown = theme == "town" or theme == "stone_town"
	local half = size * 0.5
	local villageRadius = half * (if isTown then 0.62 else 0.5)

	local villageFolder = Instance.new("Folder")
	villageFolder.Name = "Village"
	villageFolder.Parent = model

	-- === Castle isles ===============================================================
	-- Some islands are just one huge castle rising out of the jungle. Build the keep,
	-- scatter garrison loot inside the courtyard, and hand back guard posts + a merchant
	-- spot just outside the gate. No houses / campfire / fences.
	if theme == "castle" then
		local castleRadius = math.clamp(half * 0.4, 70, 240)
		buildCastle(villageFolder, center, topY, castleRadius, islandId)

		-- Wall + gate lighting so the keep glows if the isle is flagged Lit.
		if entry.Lit == true then
			local lamps = 8
			for i = 1, lamps do
				local a = (i / lamps) * math.pi * 2
				local r = castleRadius * 0.72
				buildLampPost(villageFolder, Vector3.new(center.X + math.cos(a) * r, topY, center.Z + math.sin(a) * r))
			end
		end

		-- Garrison guard posts spread across the courtyard.
		local guardSpots: { Vector3 } = {}
		for i = 1, 16 do
			local a = (i / 16) * math.pi * 2 + math.random() * 0.4
			local r = castleRadius * (0.2 + math.random() * 0.55)
			table.insert(guardSpots, Vector3.new(center.X + math.cos(a) * r, topY + 2.5, center.Z + math.sin(a) * r))
		end

		-- Treasure: weapon / armor / chest loot inside the walls.
		local weaponCount = (entry.Loot and entry.Loot.Weapons) or 4
		for _ = 1, weaponCount do
			local a = math.random() * math.pi * 2
			local r = castleRadius * (0.15 + math.random() * 0.6)
			local weaponId = Weapons.rollLootWeapon(function(lo, hi)
				return math.random(lo, hi)
			end)
			local cf = CFrame.new(center.X + math.cos(a) * r, topY + 0.5, center.Z + math.sin(a) * r)
				* CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
			WeaponService.spawnWeaponPickup(villageFolder, weaponId, cf)
		end
		local armorCount = (entry.Loot and entry.Loot.Armor) or 0
		if deps.spawnArmorPickup then
			for _ = 1, armorCount do
				local a = math.random() * math.pi * 2
				local r = castleRadius * (0.15 + math.random() * 0.6)
				local armorId = Armor.rollLootArmor(function(lo, hi)
					return math.random(lo, hi)
				end)
				deps.spawnArmorPickup(villageFolder, armorId, CFrame.new(center.X + math.cos(a) * r, topY + 0.4, center.Z + math.sin(a) * r))
			end
		end
		local chestCount = (entry.Loot and entry.Loot.Chests) or 0
		for i = 1, chestCount do
			local a = (i / math.max(chestCount, 1)) * math.pi * 2 + 0.6
			local r = castleRadius * (0.2 + math.random() * 0.5)
			buildChest(villageFolder, CFrame.new(center.X + math.cos(a) * r, topY + 0.85, center.Z + math.sin(a) * r), islandId, deps)
		end

		local merchantSpot = Vector3.new(center.X, topY + 2.5, center.Z + castleRadius + 16)
		return { villagerSpots = guardSpots, merchantSpot = merchantSpot }
	end

	-- Houses laid out around the heart. Towns get many more, spread over two rings so
	-- the settlement reads as a proper town you can wander through, not a tiny hamlet.
	local totalPop = (entry.Villagers and (entry.Villagers.Passive + entry.Villagers.Hostile)) or 0
	local houseCount
	if abandoned then
		houseCount = if isTown then math.random(10, 16) else math.random(5, 9)
	elseif isTown then
		houseCount = math.clamp(math.floor(totalPop / 2) + 10, 16, 32)
	else
		houseCount = math.clamp(math.floor(totalPop / 2) + 6, 8, 16)
	end
	local villagerSpots: { Vector3 } = {}

	for i = 1, houseCount do
		local a = (i / houseCount) * math.pi * 2 + math.random() * 0.3
		-- Towns fill an inner + outer ring so streets of houses stretch outward.
		local ringSpread = if isTown and i % 2 == 0 then 0.9 else 0.55
		local r = villageRadius * (ringSpread + math.random() * 0.4)
		local x = center.X + math.cos(a) * r
		local z = center.Z + math.sin(a) * r
		-- Face the house toward the village center
		local houseCf = CFrame.lookAt(Vector3.new(x, topY, z), Vector3.new(center.X, topY, center.Z))
		buildHouse(villageFolder, houseCf, {
			cobblestone = cobble,
			ruined = abandoned,
			islandId = islandId,
		})
		-- A villager spot by each house
		table.insert(villagerSpots, Vector3.new(x, topY + 2.5, z))
	end

	-- Central campfire (lit villages) or a cold ash pit (abandoned).
	if abandoned then
		makePart({
			Name = "ColdPit",
			Parent = villageFolder,
			Size = Vector3.new(4, 0.5, 4),
			CFrame = CFrame.new(center.X, topY + 0.3, center.Z),
			Color = ASH,
			Material = Enum.Material.Ground,
			CanCollide = false,
		})
	else
		buildCampfire(villageFolder, Vector3.new(center.X, topY + 0.3, center.Z))
	end

	-- Theme flavour: each settlement type gets a distinctive landmark so isles feel
	-- different at a glance (a fishing village reads nothing like a stone town).
	if not abandoned then
		if theme == "fishing_village" then
			for i = 1, 4 do
				local a = (i / 4) * math.pi * 2 + 0.4
				local r = villageRadius * 0.6
				local cf = CFrame.new(center.X + math.cos(a) * r, topY, center.Z + math.sin(a) * r)
				buildFishRack(villageFolder, cf)
			end
		elseif theme == "town" then
			for i = 1, 3 do
				local a = (i / 3) * math.pi * 2
				local r = villageRadius * 0.32
				local cf = CFrame.new(center.X + math.cos(a) * r, topY, center.Z + math.sin(a) * r)
				buildMarketStall(villageFolder, cf)
			end
		elseif theme == "stone_town" then
			buildWell(villageFolder, Vector3.new(center.X + villageRadius * 0.22, topY, center.Z))
			local towerPos = Vector3.new(center.X - villageRadius * 0.5, topY, center.Z - villageRadius * 0.4)
			buildWatchtower(villageFolder, towerPos)
			-- A climbable ladder so players can actually get up on the watchtower.
			buildLadder(villageFolder, towerPos + Vector3.new(3.4, 0, 0), 18)
		elseif cobble then
			buildWell(villageFolder, Vector3.new(center.X + villageRadius * 0.22, topY, center.Z))
		end
	end

	-- Grand landmarks: a church, manor houses, and street lamps that light up the town.
	if not abandoned then
		if entry.Church == true then
			-- Church sits on the near side of the square, facing the heart.
			local churchCf = CFrame.lookAt(
				Vector3.new(center.X, topY + 0.8, center.Z + villageRadius * 0.72),
				Vector3.new(center.X, topY + 0.8, center.Z)
			)
			buildChurch(villageFolder, churchCf, islandId)
		end

		local mansions = tonumber(entry.Mansions) or 0
		for i = 1, mansions do
			local a = (i / math.max(mansions, 1)) * math.pi * 2 + 1.1
			local r = villageRadius * 0.82
			local pos = Vector3.new(center.X + math.cos(a) * r, topY + 0.8, center.Z + math.sin(a) * r)
			buildMansion(villageFolder, CFrame.lookAt(pos, Vector3.new(center.X, topY + 0.8, center.Z)), cobble, islandId)
		end

		if entry.Lit == true then
			-- Street lamps ring the square and dot an inner path so the town glows.
			local lamps = math.clamp(math.floor(villageRadius / 10), 6, 16)
			for i = 1, lamps do
				local a = (i / lamps) * math.pi * 2
				local r = villageRadius * 0.55
				buildLampPost(villageFolder, Vector3.new(center.X + math.cos(a) * r, topY, center.Z + math.sin(a) * r))
			end
			for i = 1, 4 do
				local a = (i / 4) * math.pi * 2 + 0.5
				local r = villageRadius * 0.25
				buildLampPost(villageFolder, Vector3.new(center.X + math.cos(a) * r, topY, center.Z + math.sin(a) * r))
			end
		end

		-- A couple of derelict, abandoned huts on the outskirts of an otherwise living
		-- settlement — ruined shells to poke around in ("some houses abandoned").
		local ruins = if isTown then 3 else 2
		for i = 1, ruins do
			local a = (i / ruins) * math.pi * 2 + 2.3
			local r = villageRadius * (0.98 + math.random() * 0.22)
			local pos = Vector3.new(center.X + math.cos(a) * r, topY, center.Z + math.sin(a) * r)
			buildHouse(villageFolder, CFrame.lookAt(pos, Vector3.new(center.X, topY, center.Z)), {
				cobblestone = cobble,
				ruined = true,
				islandId = islandId,
			})
		end
	end

	-- Torch posts around the village (simple villages "with torches and stuff").
	local torchPosts = if abandoned then 2 else math.clamp(math.floor(villageRadius / 12), 4, 10)
	for i = 1, torchPosts do
		local a = (i / torchPosts) * math.pi * 2
		local r = villageRadius * 0.75
		local cf = CFrame.new(center.X + math.cos(a) * r, topY + 1.7, center.Z + math.sin(a) * r)
		local torch = LootPropFactory.createTorchWorld(villageFolder, cf)
		torch:SetAttribute("IslandId", islandId)
		-- Abandoned torches are unlit (kill the flame + light)
		if abandoned then
			for _, d in torch:GetDescendants() do
				if d:IsA("Fire") or d:IsA("PointLight") then
					d:Destroy()
				end
			end
		end
	end

	if not abandoned then
		buildFenceRing(villageFolder, center, topY, villageRadius * 0.95)
		
		-- Add cobblestone streets connecting the village
		buildCobblestoneStreets(villageFolder, center, topY, villagerSpots, villageRadius)
	end

	-- Weapon pickups scattered through the village (all villages have loot).
	local weaponCount = (entry.Loot and entry.Loot.Weapons) or 2
	for _ = 1, weaponCount do
		local a = math.random() * math.pi * 2
		local r = villageRadius * (0.2 + math.random() * 0.7)
		local weaponId = Weapons.rollLootWeapon(function(lo, hi)
			return math.random(lo, hi)
		end)
		local cf = CFrame.new(center.X + math.cos(a) * r, topY + 0.5, center.Z + math.sin(a) * r)
			* CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
		WeaponService.spawnWeaponPickup(villageFolder, weaponId, cf)
	end

	-- Armor pickups on display stands scattered through the settlement.
	local armorCount = (entry.Loot and entry.Loot.Armor) or 0
	if deps.spawnArmorPickup then
		for _ = 1, armorCount do
			local a = math.random() * math.pi * 2
			local r = villageRadius * (0.2 + math.random() * 0.7)
			local armorId = Armor.rollLootArmor(function(lo, hi)
				return math.random(lo, hi)
			end)
			local cf = CFrame.new(center.X + math.cos(a) * r, topY + 0.4, center.Z + math.sin(a) * r)
			deps.spawnArmorPickup(villageFolder, armorId, cf)
		end
	end

	-- Lootable chests.
	local chestCount = (entry.Loot and entry.Loot.Chests) or 0
	for i = 1, chestCount do
		local a = (i / math.max(chestCount, 1)) * math.pi * 2 + 0.6
		local r = villageRadius * (0.3 + math.random() * 0.5)
		local cf = CFrame.new(center.X + math.cos(a) * r, topY + 0.85, center.Z + math.sin(a) * r)
		buildChest(villageFolder, cf, islandId, deps)
	end

	local merchantSpot = Vector3.new(
		center.X + villageRadius * 0.35,
		topY + 2.5,
		center.Z + villageRadius * 0.15
	)

	-- Setup Level-of-Detail system for performance optimization
	setupBuildingLOD(model, center)

	return { villagerSpots = villagerSpots, merchantSpot = merchantSpot }
end

return VillageBuilder
