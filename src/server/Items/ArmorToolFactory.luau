-- Builds armor world pickups (a looted piece resting on a small stand with a rarity tag)
-- and the parts that get welded onto a character when a piece is worn.
--
-- Worn armor is cosmetic geometry welded to the character's real body parts (Head /
-- Torso-or-UpperTorso / legs). ArmorService owns the equip logic + damage reduction; this
-- factory only produces geometry so the visuals stay in one place.

local Armor = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Armor"))

local ArmorToolFactory = {}

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "ArmorPart"
	p.Anchored = if props.Anchored == nil then false else props.Anchored
	p.CanCollide = false
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.CanTouch = false
	p.Massless = true
	p.Material = props.Material or Enum.Material.Metal
	p.Color = props.Color or Color3.fromRGB(150, 156, 164)
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

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Find the best anchor part on a character for each slot, tolerant of R6 and R15 rigs.
local function anchorForSlot(character: Model, slot: string): BasePart?
	if slot == "Head" then
		local head = character:FindFirstChild("Head")
		return if head and head:IsA("BasePart") then head else nil
	elseif slot == "Body" then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		return if torso and torso:IsA("BasePart") then torso else nil
	elseif slot == "Legs" then
		-- Prefer a centred hip/torso anchor so the wrap sits at the waist, not on one leg.
		local leg = character:FindFirstChild("LowerTorso")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("LeftUpperLeg")
			or character:FindFirstChild("Left Leg")
		return if leg and leg:IsA("BasePart") then leg else nil
	end
	return nil
end

-- === Worn geometry per slot ==============================================

local function buildHeadPiece(folder: Folder, anchor: BasePart, def: { [string]: any })
	local shell = makePart({
		Name = "Helm",
		Parent = folder,
		Size = anchor.Size * Vector3.new(1.16, 0.78, 1.16),
		Color = def.Color,
		Material = def.Material,
		CFrame = anchor.CFrame * CFrame.new(0, 0.18, 0),
	})
	weld(anchor, shell)
	-- Iron/plate pieces get a nose guard so metal helms read differently from cloth hoods.
	if def.Material == Enum.Material.Metal then
		local guard = makePart({
			Name = "NoseGuard",
			Parent = folder,
			Size = Vector3.new(0.18, 0.7, 0.2),
			Color = def.Color,
			Material = def.Material,
			CFrame = anchor.CFrame * CFrame.new(0, 0.02, -anchor.Size.Z * 0.55),
		})
		weld(anchor, guard)
	end
end

local function buildBodyPiece(folder: Folder, anchor: BasePart, def: { [string]: any })
	local plate = makePart({
		Name = "Chestplate",
		Parent = folder,
		Size = anchor.Size * Vector3.new(1.14, 1.02, 1.2),
		Color = def.Color,
		Material = def.Material,
		CFrame = anchor.CFrame,
	})
	weld(anchor, plate)
	-- Pauldrons for metal body armor so it reads as heavy plate.
	if def.Material == Enum.Material.Metal then
		for i = -1, 1, 2 do
			local pauldron = makePart({
				Name = "Pauldron",
				Parent = folder,
				Size = Vector3.new(anchor.Size.X * 0.34, anchor.Size.Y * 0.34, anchor.Size.Z * 0.9),
				Color = def.Color,
				Material = def.Material,
				Shape = Enum.PartType.Ball,
				CFrame = anchor.CFrame * CFrame.new(i * anchor.Size.X * 0.62, anchor.Size.Y * 0.42, 0),
			})
			weld(anchor, pauldron)
		end
	end
end

local function buildLegsPiece(folder: Folder, anchor: BasePart, def: { [string]: any })
	-- A belt/skirt wrap at the hips reads on both R6 and R15 without per-limb welds.
	local wrap = makePart({
		Name = "Greaves",
		Parent = folder,
		Size = Vector3.new(anchor.Size.X * 1.2, math.max(anchor.Size.Y * 0.5, 0.9), anchor.Size.Z * 1.2),
		Color = def.Color,
		Material = def.Material,
		CFrame = anchor.CFrame * CFrame.new(0, -anchor.Size.Y * 0.2, 0),
	})
	weld(anchor, wrap)
end

-- Public: weld a piece's geometry onto a character. Returns the created Folder (parented
-- to the character) or nil if the character has no anchor for that slot yet.
function ArmorToolFactory.wearOnCharacter(character: Model, armorId: string): Folder?
	local def = Armor.get(armorId)
	if not def then
		return nil
	end
	local anchor = anchorForSlot(character, def.Slot)
	if not anchor then
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "Armor_" .. def.Slot
	folder:SetAttribute("ArmorId", armorId)
	folder.Parent = character

	if def.Slot == "Head" then
		buildHeadPiece(folder, anchor, def)
	elseif def.Slot == "Body" then
		buildBodyPiece(folder, anchor, def)
	else
		buildLegsPiece(folder, anchor, def)
	end

	return folder
end

-- Public: a world pickup — an anchored piece on a small stand with a rarity-coloured tag.
-- ArmorService attaches the "Wear" ProximityPrompt and handles the grant.
function ArmorToolFactory.createWorldPickup(parent: Instance, armorId: string, cf: CFrame): Model?
	local def = Armor.get(armorId)
	if not def then
		return nil
	end
	local rarity = Armor.rarityInfo(def.Rarity)

	local model = Instance.new("Model")
	model.Name = "ArmorPickup_" .. armorId
	model:SetAttribute("ArmorPickup", true)
	model:SetAttribute("ArmorId", armorId)
	model.Parent = parent

	local base = makePart({
		Name = "Primary",
		Parent = model,
		Anchored = true,
		Size = Vector3.new(2.4, 0.4, 1.4),
		Color = Color3.fromRGB(74, 52, 30),
		Material = Enum.Material.WoodPlanks,
		CFrame = cf,
	})
	model.PrimaryPart = base

	-- A simple floating display of the piece above the stand.
	local display = makePart({
		Name = "Display",
		Parent = model,
		Anchored = true,
		Size = if def.Slot == "Head" then Vector3.new(1.3, 1.1, 1.3)
			elseif def.Slot == "Legs" then Vector3.new(1.9, 1.0, 1.3)
			else Vector3.new(2.0, 2.0, 1.2),
		Color = def.Color,
		Material = def.Material,
		Shape = if def.Slot == "Head" then Enum.PartType.Ball else Enum.PartType.Block,
		CFrame = cf * CFrame.new(0, 1.7, 0),
	})
	if def.Slot == "Head" and def.Material == Enum.Material.Metal then
		local guard = makePart({
			Name = "DisplayGuard",
			Parent = model,
			Anchored = true,
			Size = Vector3.new(0.2, 0.8, 0.22),
			Color = def.Color,
			Material = def.Material,
			CFrame = display.CFrame * CFrame.new(0, -0.1, -0.7),
		})
		weld(display, guard)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PickupTag"
	billboard.Size = UDim2.fromOffset(172, 44)
	billboard.StudsOffset = Vector3.new(0, 3.0, 0)
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
	tier.Text = `{rarity.Name} Armor`
	tier.Parent = tag

	local glow = Instance.new("PointLight")
	glow.Color = rarity.Color
	glow.Brightness = if (def.Rarity or 1) >= 4 then 2.2 else 1.1
	glow.Range = if (def.Rarity or 1) >= 4 then 16 else 10
	glow.Parent = base

	return model
end

return ArmorToolFactory
