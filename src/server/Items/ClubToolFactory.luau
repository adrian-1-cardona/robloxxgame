-- Builds a realistic wooden starter Club Tool.
-- CanBeDropped = true so default backpack drop works (Backspace / Xbox X / mobile drop).

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local ClubToolFactory = {}

local WOOD = Color3.fromRGB(118, 82, 48)
local WOOD_DARK = Color3.fromRGB(78, 52, 30)
local WOOD_LIGHT = Color3.fromRGB(148, 108, 68)
local BARK = Color3.fromRGB(62, 44, 28)
local GRIP_WRAP = Color3.fromRGB(96, 72, 42)

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function part(props: {
	Name: string,
	Parent: Instance,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
}): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Massless = true
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

-- Handle is a short block (Roblox grip convention). Visual shaft + head weld to it.
-- Club extends +Y from the grip toward a heavy striking head.
function ClubToolFactory.create(): Tool
	local tool = Instance.new("Tool")
	tool.Name = Config.Club.ToolName
	tool.ToolTip = "Wooden club — RMB / RT / tap to swing"
	tool.RequiresHandle = true
	tool.CanBeDropped = true
	tool.ManualActivationOnly = true -- custom melee input owns activation
	tool.Enabled = true
	tool:SetAttribute("ItemId", "StarterClub")
	tool:SetAttribute("MeleeWeapon", true)
	tool:SetAttribute("Damage", Config.Club.Damage)
	-- Slight forward/down hold so the club reads naturally in-hand
	tool.Grip = CFrame.new(0, -0.2, -0.15) * CFrame.Angles(math.rad(15), 0, math.rad(10))

	local handle = part({
		Name = "Handle",
		Parent = tool,
		Size = Vector3.new(0.32, 1.05, 0.32),
		CFrame = CFrame.new(),
		Color = GRIP_WRAP,
		Material = Enum.Material.Wood,
	})

	-- Cylinder wraps (axis along X by default → rotate to run along grip Y)
	for i = 0, 2 do
		local ring = part({
			Name = `GripRing_{i}`,
			Parent = tool,
			Size = Vector3.new(0.16, 0.4, 0.4),
			CFrame = CFrame.new(0, -0.32 + i * 0.26, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Cylinder,
		})
		weld(handle, ring)
	end

	local shaft = part({
		Name = "Shaft",
		Parent = tool,
		-- Cylinder length is Size.X; rotated 90° about Z so it runs along grip +Y
		Size = Vector3.new(2.35, 0.34, 0.34),
		CFrame = CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = WOOD,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})
	weld(handle, shaft)

	local midKnot = part({
		Name = "MidKnot",
		Parent = tool,
		Size = Vector3.new(0.3, 0.48, 0.48),
		CFrame = CFrame.new(0, 2.35, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = WOOD_LIGHT,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})
	weld(handle, midKnot)

	local headCore = part({
		Name = "ClubHead",
		Parent = tool,
		Size = Vector3.new(1.35, 1.55, 1.35),
		CFrame = CFrame.new(0, 3.55, 0),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Ball,
	})
	weld(handle, headCore)

	local headCap = part({
		Name = "ClubHeadCap",
		Parent = tool,
		Size = Vector3.new(1.05, 1.05, 1.05),
		CFrame = CFrame.new(0, 4.15, 0),
		Color = BARK,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Ball,
	})
	weld(handle, headCap)

	local nubOffsets = {
		CFrame.new(0.55, 3.45, 0.2),
		CFrame.new(-0.5, 3.65, -0.25),
		CFrame.new(0.15, 3.3, -0.55),
		CFrame.new(-0.2, 3.85, 0.5),
	}
	for i, cf in nubOffsets do
		local nub = part({
			Name = `BarkNub_{i}`,
			Parent = tool,
			Size = Vector3.new(0.35, 0.4, 0.35),
			CFrame = cf,
			Color = BARK,
			Material = Enum.Material.Wood,
			Shape = Enum.PartType.Ball,
		})
		weld(handle, nub)
	end

	local pommel = part({
		Name = "Pommel",
		Parent = tool,
		Size = Vector3.new(0.5, 0.35, 0.5),
		CFrame = CFrame.new(0, -0.7, 0),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Ball,
	})
	weld(handle, pommel)

	return tool
end

return ClubToolFactory
