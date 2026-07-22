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
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

-- One house. `opts`: cobblestone (bool), ruined (bool), islandId (string).
-- Walls are detachable salvage (LootPropFactory) so they can be hauled to a raft.
local function buildHouse(model: Model, cf: CFrame, opts: { [string]: any })
	local cobble = opts.cobblestone == true
	local ruined = opts.ruined == true
	local wallColor = if cobble then STONE else WOOD
	local wallMat = if cobble then Enum.Material.Cobblestone else Enum.Material.Wood
	local floorColor = if cobble then STONE_DARK else Color3.fromRGB(104, 74, 46)

	local w, d = 16, 14
	local wallH = if ruined then 4.5 else 7

	local floor = makePart({
		Name = "HouseFloor",
		Parent = model,
		Size = Vector3.new(w, 0.6, d),
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = floorColor,
		Material = if cobble then Enum.Material.Slate else Enum.Material.WoodPlanks,
	})

	local wallsFolder = Instance.new("Folder")
	wallsFolder.Name = "SalvageWalls"
	wallsFolder.Parent = model

	local wallY = wallH * 0.5
	local specs = {
		{ Name = "WallBack", Size = Vector3.new(w, wallH, 0.7), Offset = Vector3.new(0, wallY, -d * 0.5) },
		{ Name = "WallLeft", Size = Vector3.new(0.7, wallH, d), Offset = Vector3.new(-w * 0.5, wallY, 0) },
		{ Name = "WallRight", Size = Vector3.new(0.7, wallH, d), Offset = Vector3.new(w * 0.5, wallY, 0) },
		{ Name = "WallFrontL", Size = Vector3.new(w * 0.34, wallH, 0.7), Offset = Vector3.new(-w * 0.33, wallY, d * 0.5) },
		{ Name = "WallFrontR", Size = Vector3.new(w * 0.34, wallH, 0.7), Offset = Vector3.new(w * 0.33, wallY, d * 0.5) },
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
				prim.Color = STONE
				prim.Material = Enum.Material.Cobblestone
			end
		end
	end

	if not ruined then
		makePart({
			Name = "Roof",
			Parent = model,
			Size = Vector3.new(w + 1.6, 0.7, d + 1.6),
			CFrame = cf * CFrame.new(0, wallH + 0.4, 0),
			Color = if cobble then ROOF_WOOD else ROOF_THATCH,
			Material = if cobble then Enum.Material.Wood else Enum.Material.Grass,
		})
	else
		-- collapsed beam
		makePart({
			Name = "CollapsedBeam",
			Parent = model,
			Size = Vector3.new(w * 0.8, 0.5, 0.5),
			CFrame = cf * CFrame.new(0, wallH * 0.4, 0) * CFrame.Angles(0, math.rad(18), math.rad(24)),
			Color = MOSS,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	-- Interior bed (loot) + torch (loot)
	local bed = LootPropFactory.createBedWorld(model, cf * CFrame.new(-w * 0.25, 0.95, -d * 0.22))
	if opts.islandId then
		bed:SetAttribute("IslandId", opts.islandId)
	end
	local torch = LootPropFactory.createTorchWorld(model, cf * CFrame.new(w * 0.28, 1.7, -d * 0.22))
	if opts.islandId then
		torch:SetAttribute("IslandId", opts.islandId)
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

-- Random chest reward: weapon (+starter ammo), ammo bundle, or currency.
function VillageBuilder.grantChestLoot(player: Player, deps: { [string]: any })
	local roll = math.random()
	if roll < 0.45 then
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
	elseif roll < 0.75 then
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

	-- Houses laid out around the heart. Towns get many more, spread over two rings so
	-- the settlement reads as a proper town you can wander through, not a tiny hamlet.
	local totalPop = (entry.Villagers and (entry.Villagers.Passive + entry.Villagers.Hostile)) or 0
	local houseCount
	if abandoned then
		houseCount = if isTown then math.random(7, 11) else math.random(3, 6)
	elseif isTown then
		houseCount = math.clamp(math.floor(totalPop / 2) + 6, 10, 22)
	else
		houseCount = math.clamp(math.floor(totalPop / 2) + 3, 4, 10)
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

	return { villagerSpots = villagerSpots, merchantSpot = merchantSpot }
end

return VillageBuilder
