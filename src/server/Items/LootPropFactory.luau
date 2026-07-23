-- Builds world loot props (walls, torches, planks) and backpack Tools from the same kinds.
-- World props stay Anchored so raft shiftModel / island flats stay consistent.

local HttpService = game:GetService("HttpService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local LootPropFactory = {}

export type LootKind = "Wall" | "Torch" | "Plank" | "Crate" | "Bed"

local BED_FRAME = Color3.fromRGB(96, 66, 40)
local BED_SHEET = Color3.fromRGB(206, 198, 176)
local BED_PILLOW = Color3.fromRGB(224, 220, 206)

local WOOD = Color3.fromRGB(128, 92, 58)
local WOOD_DARK = Color3.fromRGB(78, 52, 30)
local WOOD_LIGHT = Color3.fromRGB(148, 108, 68)
local TORCH_HANDLE = Color3.fromRGB(92, 64, 38)
local TORCH_WRAP = Color3.fromRGB(160, 120, 70)

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "PropPart"
	p.Anchored = if props.Anchored == nil then true else props.Anchored
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.CanTouch = if props.CanTouch == nil then false else props.CanTouch
	p.Massless = props.Massless == true
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color or WOOD
	p.Size = props.Size or Vector3.new(1, 1, 1)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- Loot props (walls, planks, crates, beds, torches) are numerous — especially the
	-- 5 salvage walls per village house. Default them to no shadow; sun/terrain shadows
	-- via GlobalShadows still apply.
	p.CastShadow = props.CastShadow == true
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.Shape ~= nil then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function tagProp(model: Model, kind: LootKind, propId: string?)
	local id = propId or HttpService:GenerateGUID(false)
	model:SetAttribute("IsLootProp", true)
	model:SetAttribute("LootKind", kind)
	model:SetAttribute("PropId", id)
	model:SetAttribute("Draggable", true)
	model:SetAttribute("Weldable", true)
	model:SetAttribute("Welded", false)
	model:SetAttribute("GrabbedBy", 0)
	return id
end

-- Tag an externally-built model (e.g. the merchant NPC) as a draggable / weldable loot
-- prop so it flows through the existing drag / weld system. `opts.noPickup` blocks the
-- backpack pickup prompt (you can't pocket a person).
function LootPropFactory.tagAsProp(model: Model, kind: string, opts: { [string]: any }?): string
	local id = (opts and opts.propId) or HttpService:GenerateGUID(false)
	model:SetAttribute("IsLootProp", true)
	model:SetAttribute("LootKind", kind)
	model:SetAttribute("PropId", id)
	model:SetAttribute("Draggable", true)
	model:SetAttribute("Weldable", true)
	model:SetAttribute("Welded", false)
	model:SetAttribute("GrabbedBy", 0)
	if opts and opts.noPickup then
		model:SetAttribute("NoPickup", true)
	end
	return id
end

local function attachFlame(holder: BasePart)
	-- Classic Roblox Fire + warm PointLight for night sailing
	local fire = Instance.new("Fire")
	fire.Name = "TorchFlame"
	fire.Size = 3.2
	fire.Heat = 8
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = holder

	local light = Instance.new("PointLight")
	light.Name = "TorchLight"
	light.Brightness = 2.4
	light.Range = 24
	light.Color = Color3.fromRGB(255, 186, 90)
	-- Shadow-casting dynamic lights are extremely expensive and torches are everywhere
	-- (houses, village posts, island scatter). Keep the warm glow, drop the shadow pass.
	light.Shadows = false
	light.Parent = holder

	return fire, light
end

function LootPropFactory.createTorchWorld(parent: Instance, cf: CFrame, propId: string?): Model
	local model = Instance.new("Model")
	model.Name = "LootTorch"
	model.Parent = parent

	local pole = makePart({
		Name = "Primary",
		Parent = model,
		Size = Vector3.new(0.45, 3.4, 0.45),
		CFrame = cf,
		Color = TORCH_HANDLE,
		Material = Enum.Material.Wood,
	})
	model.PrimaryPart = pole

	makePart({
		Name = "Wrap",
		Parent = model,
		Size = Vector3.new(0.7, 0.55, 0.7),
		CFrame = cf * CFrame.new(0, 1.35, 0),
		Color = TORCH_WRAP,
		Material = Enum.Material.Fabric,
	})

	local head = makePart({
		Name = "FlameHolder",
		Parent = model,
		Size = Vector3.new(0.55, 0.45, 0.55),
		CFrame = cf * CFrame.new(0, 1.75, 0),
		Color = Color3.fromRGB(48, 36, 28),
		Material = Enum.Material.Slate,
	})
	attachFlame(head)

	tagProp(model, "Torch", propId)
	model:SetAttribute("ProvidesLight", true)
	return model
end

function LootPropFactory.createWallWorld(parent: Instance, size: Vector3, cf: CFrame, propId: string?): Model
	local model = Instance.new("Model")
	model.Name = "LootWall"
	model.Parent = parent

	local wall = makePart({
		Name = "Primary",
		Parent = model,
		Size = size,
		CFrame = cf,
		Color = WOOD,
		Material = Enum.Material.Wood,
	})
	model.PrimaryPart = wall

	-- Subtle plank seams so walls read as salvage timber
	local seamCount = math.clamp(math.floor(size.Y / 2.2), 1, 4)
	for i = 1, seamCount do
		local t = (i / (seamCount + 1)) - 0.5
		makePart({
			Name = `Seam_{i}`,
			Parent = model,
			Size = Vector3.new(size.X * 0.92, 0.12, size.Z + 0.08),
			CFrame = cf * CFrame.new(0, t * size.Y, 0),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	tagProp(model, "Wall", propId)
	return model
end

function LootPropFactory.createPlankWorld(parent: Instance, cf: CFrame, propId: string?): Model
	local model = Instance.new("Model")
	model.Name = "LootPlank"
	model.Parent = parent

	local plank = makePart({
		Name = "Primary",
		Parent = model,
		Size = Vector3.new(6.5, 0.45, 1.4),
		CFrame = cf,
		Color = WOOD_LIGHT,
		Material = Enum.Material.WoodPlanks,
	})
	model.PrimaryPart = plank
	tagProp(model, "Plank", propId)
	return model
end

function LootPropFactory.createCrateWorld(parent: Instance, cf: CFrame, propId: string?): Model
	local model = Instance.new("Model")
	model.Name = "LootCrate"
	model.Parent = parent

	local box = makePart({
		Name = "Primary",
		Parent = model,
		Size = Vector3.new(2.4, 2.2, 2.4),
		CFrame = cf,
		Color = Color3.fromRGB(110, 78, 48),
		Material = Enum.Material.Wood,
	})
	model.PrimaryPart = box
	makePart({
		Name = "Lid",
		Parent = model,
		Size = Vector3.new(2.55, 0.35, 2.55),
		CFrame = cf * CFrame.new(0, 1.25, 0),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
	})
	tagProp(model, "Crate", propId)
	return model
end

function LootPropFactory.createBedWorld(parent: Instance, cf: CFrame, propId: string?): Model
	local model = Instance.new("Model")
	model.Name = "LootBed"
	model.Parent = parent

	local frame = makePart({
		Name = "Primary",
		Parent = model,
		Size = Vector3.new(3.4, 0.7, 6.4),
		CFrame = cf,
		Color = BED_FRAME,
		Material = Enum.Material.Wood,
	})
	model.PrimaryPart = frame

	makePart({
		Name = "Mattress",
		Parent = model,
		Size = Vector3.new(3.1, 0.6, 5.6),
		CFrame = cf * CFrame.new(0, 0.6, 0),
		Color = BED_SHEET,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	makePart({
		Name = "Pillow",
		Parent = model,
		Size = Vector3.new(2.6, 0.5, 1.2),
		CFrame = cf * CFrame.new(0, 1.0, -2.2),
		Color = BED_PILLOW,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	makePart({
		Name = "Headboard",
		Parent = model,
		Size = Vector3.new(3.4, 1.6, 0.4),
		CFrame = cf * CFrame.new(0, 0.8, -3.1),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	tagProp(model, "Bed", propId)
	return model
end

local function toolPart(props: { [string]: any }): Part
	props.Anchored = false
	props.CanCollide = false
	props.Massless = true
	return makePart(props)
end

function LootPropFactory.createTool(kind: LootKind): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = true
	tool.ManualActivationOnly = true
	tool:SetAttribute("IsLootTool", true)
	tool:SetAttribute("LootKind", kind)
	tool:SetAttribute("ItemId", `Loot_{kind}`)

	if kind == "Torch" then
		tool.Name = "Torch"
		tool.ToolTip = "Flaming torch — place / weld for light"
		tool.Grip = CFrame.new(0, -0.4, -0.1) * CFrame.Angles(math.rad(20), 0, 0)

		local handle = toolPart({
			Name = "Handle",
			Parent = tool,
			Size = Vector3.new(0.35, 1.2, 0.35),
			CFrame = CFrame.new(),
			Color = TORCH_HANDLE,
			Material = Enum.Material.Wood,
		})
		local head = toolPart({
			Name = "FlameHolder",
			Parent = tool,
			Size = Vector3.new(0.45, 0.4, 0.45),
			CFrame = CFrame.new(0, 0.85, 0),
			Color = Color3.fromRGB(48, 36, 28),
			Material = Enum.Material.Slate,
		})
		weld(handle, head)
		attachFlame(head)
	elseif kind == "Wall" then
		tool.Name = "Wall Panel"
		tool.ToolTip = "Salvaged wall — drag onto your raft for a shelter"
		tool.Grip = CFrame.new(0, -0.5, 1.2) * CFrame.Angles(0, math.rad(90), 0)
		local handle = toolPart({
			Name = "Handle",
			Parent = tool,
			Size = Vector3.new(0.4, 1.1, 0.4),
			CFrame = CFrame.new(),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
		})
		local panel = toolPart({
			Name = "Panel",
			Parent = tool,
			Size = Vector3.new(3.2, 2.6, 0.35),
			CFrame = CFrame.new(0, 1.4, -0.2),
			Color = WOOD,
			Material = Enum.Material.Wood,
		})
		weld(handle, panel)
	elseif kind == "Plank" then
		tool.Name = "Plank"
		tool.ToolTip = "Timber plank — build with it on your raft"
		tool.Grip = CFrame.new(0, -0.2, 0.6)
		local handle = toolPart({
			Name = "Handle",
			Parent = tool,
			Size = Vector3.new(0.35, 0.9, 0.35),
			CFrame = CFrame.new(),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
		})
		local plank = toolPart({
			Name = "Plank",
			Parent = tool,
			Size = Vector3.new(4.2, 0.3, 0.9),
			CFrame = CFrame.new(0, 0.6, -0.4),
			Color = WOOD_LIGHT,
			Material = Enum.Material.WoodPlanks,
		})
		weld(handle, plank)
	elseif kind == "Bed" then
		tool.Name = "Bed Roll"
		tool.ToolTip = "Villager bed — drag / place it on your raft to rest"
		tool.Grip = CFrame.new(0, -0.4, 0)
		local handle = toolPart({
			Name = "Handle",
			Parent = tool,
			Size = Vector3.new(1.4, 0.5, 2.6),
			CFrame = CFrame.new(),
			Color = BED_FRAME,
			Material = Enum.Material.Wood,
		})
		local roll = toolPart({
			Name = "Roll",
			Parent = tool,
			Size = Vector3.new(1.3, 0.5, 2.4),
			CFrame = CFrame.new(0, 0.5, 0),
			Color = BED_SHEET,
			Material = Enum.Material.Fabric,
		})
		weld(handle, roll)
	else
		tool.Name = "Crate"
		tool.ToolTip = "Salvage crate"
		tool.Grip = CFrame.new(0, -0.6, -0.4)
		local handle = toolPart({
			Name = "Handle",
			Parent = tool,
			Size = Vector3.new(0.4, 0.8, 0.4),
			CFrame = CFrame.new(),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
		})
		local box = toolPart({
			Name = "Box",
			Parent = tool,
			Size = Vector3.new(1.6, 1.4, 1.6),
			CFrame = CFrame.new(0, 1.0, 0),
			Color = Color3.fromRGB(110, 78, 48),
			Material = Enum.Material.Wood,
		})
		weld(handle, box)
	end

	return tool
end

function LootPropFactory.spawnFromKind(kind: LootKind, parent: Instance, cf: CFrame, propId: string?): Model
	if kind == "Torch" then
		return LootPropFactory.createTorchWorld(parent, cf, propId)
	elseif kind == "Wall" then
		return LootPropFactory.createWallWorld(parent, Vector3.new(8, 7, 0.7), cf, propId)
	elseif kind == "Plank" then
		return LootPropFactory.createPlankWorld(parent, cf, propId)
	elseif kind == "Bed" then
		return LootPropFactory.createBedWorld(parent, cf, propId)
	end
	return LootPropFactory.createCrateWorld(parent, cf, propId)
end

function LootPropFactory.attachPickupPrompt(model: Model)
	-- Some draggable props (the merchant) can never be pocketed into a backpack.
	if model:GetAttribute("NoPickup") == true then
		return
	end
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local existing = primary:FindFirstChild("LootPickupPrompt")
	if existing then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPickupPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = model.Name:gsub("Loot", ""):gsub("^%s+", "")
	local kind = model:GetAttribute("LootKind")
	if typeof(kind) == "string" then
		prompt.ObjectText = kind
	end
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = Config.Loot.PickupPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = primary
end

function LootPropFactory.attachWeldPrompt(model: Model)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local existing = primary:FindFirstChild("LootWeldPrompt")
	if existing then
		existing:Destroy()
	end

	local welded = model:GetAttribute("Welded") == true
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootWeldPrompt"
	prompt.ActionText = if welded then "Unweld" else "Weld"
	prompt.ObjectText = if welded then "Detach from raft" else "Attach to raft"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.X
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.UIOffset = Vector2.new(0, -28)
	prompt.Parent = primary
end

return LootPropFactory
