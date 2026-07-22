-- Builds weapon Tools (melee + ranged) and their world-loot pickup models from the
-- shared Weapons catalog. One factory so the tool a player picks up is always the same
-- one the merchant sells and the loot roller drops.
--
-- Tool attributes contract (read by MeleeService / WeaponService / client controllers):
--   Melee : MeleeWeapon=true, WeaponId, Damage, Range, HitRadius, HitWindow, SwingDuration
--   Ranged: Ranged=true, WeaponId, Ammo, MagSize, Loaded (current chamber/mag count)

local Weapons = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Weapons"))

local WeaponToolFactory = {}

local WOOD = Color3.fromRGB(96, 66, 40)
local WOOD_DARK = Color3.fromRGB(66, 44, 26)
local WOOD_LIGHT = Color3.fromRGB(150, 112, 70)
local METAL = Color3.fromRGB(96, 102, 110)
local METAL_DARK = Color3.fromRGB(48, 50, 56)
local BRASS = Color3.fromRGB(196, 156, 84)
local BONE = Color3.fromRGB(222, 214, 186)
local ROPE = Color3.fromRGB(158, 120, 72)
local BOWSTRING = Color3.fromRGB(232, 230, 214)

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "Part"
	p.Anchored = if props.Anchored == nil then false else props.Anchored
	p.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.CanTouch = false
	p.Massless = if props.Massless == nil then true else props.Massless
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color or WOOD
	p.Size = props.Size or Vector3.new(1, 1, 1)
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

-- === Geometry builders (attached to a Tool via its Handle) ===============

local function buildClub(tool: Tool)
	-- Gnarled driftwood club: wrapped grip, tapering shaft, heavy knotted head with bark nubs.
	tool.Grip = CFrame.new(0, -0.2, -0.15) * CFrame.Angles(math.rad(15), 0, math.rad(10))

	local handle = part({
		Name = "Handle",
		Parent = tool,
		Size = Vector3.new(0.34, 1.05, 0.34),
		Color = Color3.fromRGB(96, 72, 42),
		Material = Enum.Material.Wood,
	})
	for i = 0, 2 do
		local ring = part({
			Name = `GripWrap_{i}`,
			Parent = tool,
			Size = Vector3.new(0.18, 0.42, 0.42),
			Color = ROPE,
			Material = Enum.Material.Fabric,
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(0, -0.32 + i * 0.26, 0) * CFrame.Angles(0, 0, math.rad(90)),
		})
		weld(handle, ring)
	end

	local shaft = part({
		Name = "Shaft",
		Parent = tool,
		Size = Vector3.new(2.35, 0.36, 0.36),
		Color = WOOD,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	weld(handle, shaft)

	local head = part({
		Name = "ClubHead",
		Parent = tool,
		Size = Vector3.new(1.4, 1.6, 1.4),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(0, 3.55, 0),
	})
	weld(handle, head)

	local nubOffsets = {
		CFrame.new(0.58, 3.45, 0.22),
		CFrame.new(-0.52, 3.68, -0.26),
		CFrame.new(0.16, 3.3, -0.58),
		CFrame.new(-0.22, 3.9, 0.52),
	}
	for i, cf in nubOffsets do
		local nub = part({
			Name = `BarkNub_{i}`,
			Parent = tool,
			Size = Vector3.new(0.36, 0.42, 0.36),
			Color = Color3.fromRGB(62, 44, 28),
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Ball,
			CFrame = cf,
		})
		weld(handle, nub)
	end

	local pommel = part({
		Name = "Pommel",
		Parent = tool,
		Size = Vector3.new(0.5, 0.36, 0.5),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(0, -0.7, 0),
	})
	weld(handle, pommel)
end

local function buildSpear(tool: Tool)
	tool.Grip = CFrame.new(0, -0.2, 0.4) * CFrame.Angles(math.rad(90), 0, 0)
	local handle = part({
		Name = "Handle",
		Parent = tool,
		Size = Vector3.new(0.28, 0.28, 6.2),
		Color = WOOD,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.Angles(0, math.rad(90), 0),
	})
	local tip = part({
		Name = "Tip",
		Parent = tool,
		Size = Vector3.new(0.5, 0.5, 1.5),
		Color = BONE,
		Material = Enum.Material.Slate,
		CFrame = CFrame.new(0, 0, -3.4),
	})
	weld(handle, tip)
	-- Barbs swept back from the point so the head reads as a bone fishing spear.
	for i = -1, 1, 2 do
		local barb = part({
			Name = "Barb",
			Parent = tool,
			Size = Vector3.new(0.16, 0.16, 0.9),
			Color = BONE,
			Material = Enum.Material.Slate,
			CFrame = CFrame.new(i * 0.3, 0, -3.1) * CFrame.Angles(math.rad(28), math.rad(i * 30), 0),
		})
		weld(handle, barb)
	end
	for i = -1, 1, 2 do
		local lash = part({
			Name = "Lashing",
			Parent = tool,
			Size = Vector3.new(0.34, 0.34, 0.18),
			Color = ROPE,
			Material = Enum.Material.Fabric,
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(0, 0, -2.5 + i * 0.35) * CFrame.Angles(0, math.rad(90), 0),
		})
		weld(handle, lash)
	end
end

local function buildBow(tool: Tool)
	tool.Grip = CFrame.new(0, 0, 0.2) * CFrame.Angles(0, math.rad(90), math.rad(90))
	local handle = part({
		Name = "Handle",
		Parent = tool,
		Size = Vector3.new(0.35, 1.4, 0.5),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
	})
	for i = -1, 1, 2 do
		local limb = part({
			Name = "Limb",
			Parent = tool,
			Size = Vector3.new(0.3, 1.7, 0.4),
			Color = WOOD_LIGHT,
			Material = Enum.Material.Wood,
			CFrame = CFrame.new(0, i * 1.4, 0) * CFrame.Angles(math.rad(i * 26), 0, 0),
		})
		weld(handle, limb)
	end
	local string_ = part({
		Name = "String",
		Parent = tool,
		Size = Vector3.new(0.06, 4.1, 0.06),
		Color = BOWSTRING,
		Material = Enum.Material.Fabric,
		CFrame = CFrame.new(-0.5, 0, 0),
	})
	weld(handle, string_)
	-- Leather grip wrap on the riser
	local grip = part({
		Name = "GripWrap",
		Parent = tool,
		Size = Vector3.new(0.42, 0.9, 0.58),
		Color = Color3.fromRGB(70, 46, 28),
		Material = Enum.Material.Fabric,
		CFrame = CFrame.new(0, 0, 0),
	})
	weld(handle, grip)
	-- A nocked arrow so the bow reads clearly in hand.
	local shaft = part({
		Name = "ArrowShaft",
		Parent = tool,
		Size = Vector3.new(0.1, 0.1, 3.4),
		Color = Color3.fromRGB(150, 116, 74),
		Material = Enum.Material.Wood,
		CFrame = CFrame.new(-0.35, 0, -1.3),
	})
	weld(handle, shaft)
	local arrowTip = part({
		Name = "ArrowTip",
		Parent = tool,
		Size = Vector3.new(0.2, 0.2, 0.5),
		Color = METAL,
		Material = Enum.Material.Metal,
		CFrame = CFrame.new(-0.35, 0, -3.1),
	})
	weld(handle, arrowTip)
	for i = -1, 1, 2 do
		local fletch = part({
			Name = "Fletch",
			Parent = tool,
			Size = Vector3.new(0.04, 0.34, 0.5),
			Color = Color3.fromRGB(210, 70, 60),
			Material = Enum.Material.Fabric,
			CFrame = CFrame.new(-0.35, 0, 0.3) * CFrame.Angles(0, 0, math.rad(i * 45)),
		})
		weld(handle, fletch)
	end
end

local function buildFirearm(tool: Tool, kind: string)
	tool.Grip = CFrame.new(0, -0.3, -0.2) * CFrame.Angles(0, math.rad(0), 0)

	local stockLen = if kind == "Rifle" or kind == "Musket" then 2.1 elseif kind == "Shotgun" then 1.6 else 0.0
	local barrelLen = if kind == "Rifle" then 2.6
		elseif kind == "Musket" then 2.8
		elseif kind == "Shotgun" then 1.9
		elseif kind == "Revolver" then 0.9
		else 1.1

	local handle = part({
		Name = "Handle",
		Parent = tool,
		Size = Vector3.new(0.34, 0.9, 0.45),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		CFrame = CFrame.Angles(math.rad(18), 0, 0),
	})

	local body = part({
		Name = "Body",
		Parent = tool,
		Size = Vector3.new(0.3, 0.42, 1.0),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
		CFrame = handle.CFrame * CFrame.new(0, 0.55, -0.45),
	})
	weld(handle, body)

	local barrel = part({
		Name = "Barrel",
		Parent = tool,
		Size = Vector3.new(0.24, 0.24, barrelLen),
		Color = METAL,
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
		CFrame = body.CFrame * CFrame.new(0, 0.06, -(barrelLen * 0.5 + 0.4)) * CFrame.Angles(0, math.rad(90), 0),
	})
	weld(handle, barrel)

	if stockLen > 0 then
		local stock = part({
			Name = "Stock",
			Parent = tool,
			Size = Vector3.new(0.3, 0.55, stockLen),
			Color = WOOD,
			Material = Enum.Material.Wood,
			CFrame = body.CFrame * CFrame.new(0, -0.05, stockLen * 0.5 + 0.3),
		})
		weld(handle, stock)
	end

	if kind == "Revolver" then
		local cyl = part({
			Name = "Cylinder",
			Parent = tool,
			Size = Vector3.new(0.42, 0.42, 0.5),
			Color = METAL,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
			CFrame = body.CFrame * CFrame.new(0, 0.05, -0.2) * CFrame.Angles(0, math.rad(90), 0),
		})
		weld(handle, cyl)
	end

	-- Shared iron/brass furniture so every firearm reads as a real gun, not a block:
	-- trigger guard, trigger, hammer, and a front-sight bead at the muzzle.
	local guard = part({
		Name = "TriggerGuard",
		Parent = tool,
		Size = Vector3.new(0.12, 0.42, 0.5),
		Color = BRASS,
		Material = Enum.Material.Metal,
		CFrame = body.CFrame * CFrame.new(0, -0.28, 0.02),
	})
	weld(handle, guard)
	local trigger = part({
		Name = "Trigger",
		Parent = tool,
		Size = Vector3.new(0.08, 0.26, 0.1),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
		CFrame = body.CFrame * CFrame.new(0, -0.16, 0.02),
	})
	weld(handle, trigger)
	local hammer = part({
		Name = "Hammer",
		Parent = tool,
		Size = Vector3.new(0.12, 0.3, 0.16),
		Color = METAL_DARK,
		Material = Enum.Material.Metal,
		CFrame = body.CFrame * CFrame.new(0, 0.24, 0.36) * CFrame.Angles(math.rad(-24), 0, 0),
	})
	weld(handle, hammer)
	local sight = part({
		Name = "FrontSight",
		Parent = tool,
		Size = Vector3.new(0.06, 0.16, 0.06),
		Color = BRASS,
		Material = Enum.Material.Metal,
		CFrame = barrel.CFrame * CFrame.new(0, 0, barrelLen * 0.42) * CFrame.Angles(0, math.rad(-90), 0)
			* CFrame.new(0, 0.14, 0),
	})
	weld(handle, sight)
end

-- === Public API ==========================================================

function WeaponToolFactory.createTool(weaponId: string): Tool?
	local def = Weapons.get(weaponId)
	if not def then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.ToolTip = def.ToolTip
	tool.RequiresHandle = true
	tool.CanBeDropped = true
	tool:SetAttribute("WeaponId", weaponId)
	tool:SetAttribute("ItemId", "Weapon_" .. weaponId)

	if def.Class == "melee" then
		tool.ManualActivationOnly = true -- custom melee input owns activation
		tool:SetAttribute("MeleeWeapon", true)
		tool:SetAttribute("Damage", def.Damage)
		tool:SetAttribute("Range", def.Range)
		tool:SetAttribute("HitRadius", def.HitRadius)
		tool:SetAttribute("HitWindow", def.HitWindow)
		tool:SetAttribute("Cooldown", def.Cooldown)
		tool:SetAttribute("SwingDuration", def.SwingDuration)
		if weaponId == "Spear" then
			buildSpear(tool)
		elseif weaponId == "Club" then
			buildClub(tool)
		else
			-- fallback melee handle
			part({ Name = "Handle", Parent = tool, Size = Vector3.new(0.4, 3, 0.4), Color = WOOD })
		end
	else
		tool:SetAttribute("Ranged", true)
		tool:SetAttribute("Ammo", def.Ammo)
		tool:SetAttribute("MagSize", def.MagSize)
		tool:SetAttribute("Loaded", def.MagSize) -- starts loaded
		if weaponId == "Bow" then
			buildBow(tool)
		else
			buildFirearm(tool, weaponId)
		end
	end

	return tool
end

-- A world pickup: an anchored model resting in the world with a floating name tag.
-- WeaponService attaches the "Pick Up" ProximityPrompt and handles the grant.
function WeaponToolFactory.createWorldPickup(parent: Instance, weaponId: string, cf: CFrame): Model?
	local def = Weapons.get(weaponId)
	if not def then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "WeaponPickup_" .. weaponId
	model:SetAttribute("WeaponPickup", true)
	model:SetAttribute("WeaponId", weaponId)
	model.Parent = parent

	-- A small display stand so the weapon reads as lootable, not scenery.
	local base = part({
		Name = "Primary",
		Parent = model,
		Anchored = true,
		CanCollide = false,
		Massless = false,
		Size = Vector3.new(2.6, 0.4, 1.2),
		Color = WOOD_DARK,
		Material = Enum.Material.WoodPlanks,
		CFrame = cf,
	})
	model.PrimaryPart = base

	-- Build the weapon tool geometry into a throwaway tool, then reparent + anchor its
	-- parts onto the stand so we don't duplicate all the geometry code.
	local display = WeaponToolFactory.createTool(weaponId)
	if display then
		local handle = display:FindFirstChild("Handle")
		local rest = cf * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90))
		if handle and handle:IsA("BasePart") then
			local delta = rest * handle.CFrame:Inverse()
			for _, d in display:GetChildren() do
				if d:IsA("BasePart") then
					d.CFrame = delta * d.CFrame
					d.Anchored = true
					d.CanCollide = false
					d.Massless = false
					d.Parent = model
				end
			end
		end
		display:Destroy()
	end

	local rarity = Weapons.rarityInfo(def.Rarity)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PickupTag"
	billboard.Size = UDim2.fromOffset(168, 44)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Adornee = base
	billboard.Parent = base

	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 0.32
	tag.BackgroundColor3 = Color3.fromRGB(18, 30, 40)
	tag.Size = UDim2.fromScale(1, 1)
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = Color3.fromRGB(245, 248, 250)
	tag.Text = def.Name
	tag.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tag
	-- Rarity-coloured outline + a small tier label so grey/green/blue/etc. read at a glance.
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.Color
	stroke.Thickness = 2.5
	stroke.Parent = tag
	local tier = Instance.new("TextLabel")
	tier.Name = "Tier"
	tier.BackgroundTransparency = 1
	tier.Size = UDim2.new(1, 0, 0.32, 0)
	tier.Position = UDim2.fromScale(0, 0.02)
	tier.Font = Enum.Font.GothamBold
	tier.TextScaled = true
	tier.TextColor3 = rarity.Color
	tier.Text = rarity.Name
	tier.Parent = tag

	-- A soft rarity glow on the stand so the drop's tier reads even before you see the tag.
	local glow = Instance.new("PointLight")
	glow.Color = rarity.Color
	glow.Brightness = if (def.Rarity or 1) >= 4 then 2.2 else 1.1
	glow.Range = if (def.Rarity or 1) >= 4 then 16 else 10
	glow.Parent = base

	return model
end

return WeaponToolFactory
