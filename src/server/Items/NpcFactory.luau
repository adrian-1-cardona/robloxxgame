-- Builds island NPC models: tribal villagers (passive blue-eyed / aggressive red-eyed)
-- and the blue-hatted merchant. All NPC parts are Anchored — the island AI drives them
-- by CFrame (matching the existing pirate movement), so no physics humanoids to fight.
--
-- Attributes contract (read by IslandService AI / combat services):
--   IsNpc=true, NpcKind="villager"|"merchant", IslandId, Hostile(bool)
--   Villagers carry a Humanoid so they can take damage / die.
--   The merchant has NO Humanoid (never targeted by combat) and is tagged as a loot prop
--   elsewhere so it can be dragged / welded to a raft.

local NpcFactory = {}

local SKIN = Color3.fromRGB(196, 150, 108)
local SKIN_DARK = Color3.fromRGB(150, 108, 74)
local TRIBAL_TAN = Color3.fromRGB(150, 120, 80)
local TRIBAL_RED = Color3.fromRGB(150, 58, 46) -- aggressive war paint / gear
local WRAP_BROWN = Color3.fromRGB(96, 70, 44)
local MERCHANT_BLUE = Color3.fromRGB(46, 92, 168)
local MERCHANT_BLUE_DEEP = Color3.fromRGB(30, 62, 128)
local EYE_BLUE = Color3.fromRGB(90, 180, 255)
local EYE_RED = Color3.fromRGB(255, 60, 50)

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "NpcPart"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.Material = props.Material or Enum.Material.Fabric
	p.Color = props.Color or SKIN
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

local function billboardTag(root: BasePart, text: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NpcTag"
	billboard.Size = UDim2.fromOffset(96, 24)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 100
	billboard.Adornee = root
	billboard.Parent = root

	local tag = Instance.new("TextLabel")
	tag.Name = "Label"
	tag.BackgroundTransparency = 1
	tag.Size = UDim2.fromScale(1, 1)
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = color
	tag.Text = text
	tag.Parent = billboard
	return tag
end

-- Shared humanoid-ish body. Returns the model + head reference so callers can restyle eyes.
local function buildBody(parent: Instance, cf: CFrame, gearColor: Color3): (Model, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Parent = parent

	local root = makePart({
		Name = "HumanoidRootPart",
		Parent = model,
		Size = Vector3.new(2, 2, 1),
		CFrame = cf,
		Color = gearColor,
		CanCollide = true,
	})
	model.PrimaryPart = root

	makePart({
		Name = "Torso",
		Parent = model,
		Size = Vector3.new(2.1, 2.1, 1.1),
		CFrame = root.CFrame * CFrame.new(0, 0.1, 0),
		Color = gearColor,
	})
	-- Tribal skirt / loincloth
	makePart({
		Name = "Skirt",
		Parent = model,
		Size = Vector3.new(2.2, 1.1, 1.2),
		CFrame = root.CFrame * CFrame.new(0, -1.3, 0),
		Color = WRAP_BROWN,
	})
	-- Arms
	for i = -1, 1, 2 do
		makePart({
			Name = "Arm",
			Parent = model,
			Size = Vector3.new(0.7, 2.0, 0.7),
			CFrame = root.CFrame * CFrame.new(i * 1.45, 0.05, 0),
			Color = SKIN,
			Material = Enum.Material.SmoothPlastic,
		})
	end
	-- Legs
	for i = -1, 1, 2 do
		makePart({
			Name = "Leg",
			Parent = model,
			Size = Vector3.new(0.85, 1.9, 0.9),
			CFrame = root.CFrame * CFrame.new(i * 0.5, -2.0, 0),
			Color = SKIN_DARK,
			Material = Enum.Material.SmoothPlastic,
		})
	end

	local head = makePart({
		Name = "Head",
		Parent = model,
		Size = Vector3.new(1.25, 1.25, 1.25),
		CFrame = root.CFrame * CFrame.new(0, 1.7, 0),
		Color = SKIN,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Ball,
	})
	return model, root, head
end

local function attachEyes(model: Model, head: BasePart, eyeColor: Color3)
	-- Remove any prior eyes (used when flipping passive -> hostile)
	for _, d in model:GetChildren() do
		if d.Name == "Eye" then
			d:Destroy()
		end
	end
	for i = -1, 1, 2 do
		local eye = makePart({
			Name = "Eye",
			Parent = model,
			Size = Vector3.new(0.22, 0.22, 0.14),
			CFrame = head.CFrame * CFrame.new(i * 0.28, 0.08, -0.6),
			Color = eyeColor,
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
		local light = Instance.new("PointLight")
		light.Brightness = 0.6
		light.Range = 5
		light.Color = eyeColor
		light.Parent = eye
	end
end

-- opts: { hostile: boolean, scavenger: boolean?, islandId: string, name: string?, health: number }
function NpcFactory.createVillager(parent: Instance, cf: CFrame, opts: { [string]: any }): (Model, Humanoid)
	local hostile = opts.hostile == true
	local gearColor = if hostile then TRIBAL_RED else TRIBAL_TAN
	local model, root, head = buildBody(parent, cf, gearColor)
	model.Name = if opts.scavenger then "Scavenger" elseif hostile then "Warrior" else "Villager"
	model:SetAttribute("IsNpc", true)
	model:SetAttribute("NpcKind", "villager")
	model:SetAttribute("Hostile", hostile)
	if opts.islandId then
		model:SetAttribute("IslandId", opts.islandId)
	end
	-- Legacy flag so existing gun/ melee "IsPirate" checks still hit hostile islanders.
	if hostile then
		model:SetAttribute("IsPirate", true)
	end

	-- War paint stripe for hostile warriors so they read differently at a glance.
	if hostile and not opts.scavenger then
		makePart({
			Name = "WarPaint",
			Parent = model,
			Size = Vector3.new(1.3, 0.18, 1.3),
			CFrame = head.CFrame * CFrame.new(0, 0.1, 0),
			Color = Color3.fromRGB(210, 60, 50),
			Material = Enum.Material.SmoothPlastic,
		})
	end

	attachEyes(model, head, if hostile then EYE_RED else EYE_BLUE)

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = opts.health or 55
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.Parent = model

	local tagColor = if hostile then EYE_RED else EYE_BLUE
	local tagText = if opts.scavenger then "Scavenger" elseif hostile then "Warrior" else "Villager"
	billboardTag(root, tagText, tagColor)

	humanoid.Died:Connect(function()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
		task.delay(3, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	return model, humanoid
end

-- Turn a passive villager hostile (defend the isle when attacked): red eyes + war gear.
function NpcFactory.makeHostileLook(model: Model)
	local head = model:FindFirstChild("Head")
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and (p.Name == "Torso" or p.Name == "HumanoidRootPart") then
			p.Color = TRIBAL_RED
		end
	end
	if head and head:IsA("BasePart") then
		attachEyes(model, head, EYE_RED)
	end
	local tag = model:FindFirstChild("NpcTag")
	local label = tag and tag:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = "Defender"
		label.TextColor3 = EYE_RED
	end
end

-- The blue-hatted tribal merchant. Never hostile, no Humanoid combat.
function NpcFactory.createMerchant(parent: Instance, cf: CFrame, opts: { [string]: any }?): (Model, BasePart)
	local model, root, head = buildBody(parent, cf, MERCHANT_BLUE)
	model.Name = "Merchant"
	model:SetAttribute("IsNpc", true)
	model:SetAttribute("NpcKind", "merchant")
	model:SetAttribute("Hostile", false)
	if opts and opts.islandId then
		model:SetAttribute("IslandId", opts.islandId)
	end

	-- Blue tribal sash across the torso
	makePart({
		Name = "Sash",
		Parent = model,
		Size = Vector3.new(2.2, 0.5, 1.2),
		CFrame = root.CFrame * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(20)),
		Color = MERCHANT_BLUE_DEEP,
	})

	-- Distinctive blue hat (brim + crown) so the merchant is unmistakable.
	makePart({
		Name = "HatBrim",
		Parent = model,
		Size = Vector3.new(1.9, 0.18, 1.9),
		CFrame = head.CFrame * CFrame.new(0, 0.62, 0),
		Color = MERCHANT_BLUE,
		Material = Enum.Material.Fabric,
		Shape = Enum.PartType.Cylinder,
	})
	makePart({
		Name = "HatCrown",
		Parent = model,
		Size = Vector3.new(1.15, 0.9, 1.15),
		CFrame = head.CFrame * CFrame.new(0, 1.0, 0),
		Color = MERCHANT_BLUE_DEEP,
		Material = Enum.Material.Fabric,
	})

	-- Friendly blue eyes
	attachEyes(model, head, EYE_BLUE)

	billboardTag(root, "Merchant", Color3.fromRGB(120, 190, 255))

	return model, root
end

return NpcFactory
