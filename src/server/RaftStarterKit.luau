-- Visual starter kit for each crew raft: vertical steering column + ship's wheel.
-- Pure construction — HelmService owns interaction / movement / look-driven wheel spin.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local RaftStarterKit = {}

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "KitPart"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color or Config.Theme.Driftwood
	p.Size = props.Size or Vector3.new(1, 1, 1)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.Shape ~= nil then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function deckTopY(deck: BasePart): number
	return deck.Position.Y + deck.Size.Y / 2
end

-- Classic pirate helm: tall vertical post with an upright wheel mounted on it.
-- Cylinder axis is local X; rotate 90° about Y so the wheel stands vertical (YZ → world XY).
local function buildHelmWheel(kit: Folder, deck: BasePart, center: Vector3)
	local standOffset = Config.Helm.StandLocalOffset
	local topY = deckTopY(deck)
	local standPos = Vector3.new(center.X + standOffset.X, topY, center.Z + standOffset.Z)
	-- Face toward the bow (negative Z in local raft space)
	local standCf = CFrame.new(standPos, standPos + Vector3.new(0, 0, -10))

	-- Deck plate under the column
	makePart({
		Name = "HelmBase",
		Parent = kit,
		Size = Vector3.new(3.6, 0.45, 3.6),
		CFrame = standCf * CFrame.new(0, 0.22, 0),
		Color = Color3.fromRGB(86, 58, 34),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})

	-- Vertical steering column (the post the wheel lives on)
	local columnHeight = 4.4
	local column = makePart({
		Name = "HelmPedestal",
		Parent = kit,
		Size = Vector3.new(1.15, columnHeight, 1.15),
		CFrame = standCf * CFrame.new(0, columnHeight / 2, 0),
		Color = Color3.fromRGB(72, 48, 28),
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	-- Cap on top of the post
	makePart({
		Name = "HelmColumnCap",
		Parent = kit,
		Size = Vector3.new(1.55, 0.4, 1.55),
		CFrame = standCf * CFrame.new(0, columnHeight + 0.15, 0),
		Color = Color3.fromRGB(58, 40, 24),
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	-- Axle stub sticking out of the post toward the helmsman (+Z local)
	local wheelCenter = standCf * CFrame.new(0, 3.15, 0.95)
	-- Upright wheel: cylinder axis points at helmsman (world ±stand Look flipped → local +Z)
	local wheelCf = wheelCenter * CFrame.Angles(0, math.rad(90), 0)

	-- Spinning assembly — HelmService pivots this with look yaw while helming
	local wheelModel = Instance.new("Model")
	wheelModel.Name = "HelmWheel"
	wheelModel.Parent = kit

	makePart({
		Name = "HelmAxle",
		Parent = wheelModel,
		Size = Vector3.new(1.1, 0.55, 0.55),
		CFrame = wheelCf,
		Color = Color3.fromRGB(48, 34, 22),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})

	-- Rim — thick silhouette so it still reads at sailing distances
	makePart({
		Name = "HelmRim",
		Parent = wheelModel,
		Size = Vector3.new(0.7, 4.8, 4.8),
		CFrame = wheelCf,
		Color = Color3.fromRGB(110, 78, 48),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})

	local hub = makePart({
		Name = "HelmHub",
		Parent = wheelModel,
		Size = Vector3.new(0.85, 1.25, 1.25),
		CFrame = wheelCf,
		Color = Color3.fromRGB(58, 40, 24),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})
	wheelModel.PrimaryPart = hub

	-- Spokes in the wheel plane (radial around the cylinder axis / local X)
	for i = 0, 5 do
		local angle = math.rad(i * 30)
		makePart({
			Name = `HelmSpoke_{i}`,
			Parent = wheelModel,
			Size = Vector3.new(0.32, 0.32, 3.9),
			CFrame = hub.CFrame * CFrame.Angles(angle, 0, 0),
			Color = Color3.fromRGB(96, 68, 42),
			Material = Enum.Material.Wood,
		})
	end

	-- Handles on the rim
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		makePart({
			Name = `HelmHandle_{i}`,
			Parent = wheelModel,
			Size = Vector3.new(0.4, 1.05, 0.4),
			CFrame = hub.CFrame * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 2.55, 0),
			Color = Color3.fromRGB(130, 92, 55),
			Material = Enum.Material.Wood,
		})
	end

	-- Rest pose relative to the post so the wheel can spin after the raft moves
	local restLocal = Instance.new("CFrameValue")
	restLocal.Name = "WheelRestLocal"
	restLocal.Value = column.CFrame:ToObjectSpace(wheelCf)
	restLocal.Parent = wheelModel

	-- Invisible stand anchor: where the sailor is locked while steering (behind the wheel)
	local stand = makePart({
		Name = "HelmStand",
		Parent = kit,
		Size = Vector3.new(2.4, 0.4, 2.4),
		CFrame = standCf * CFrame.new(0, 0.15, 2.1),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	stand:SetAttribute("IsHelmStand", true)

	-- Prompt rides an upright anchor at hand height on the wheel
	local promptAnchor = makePart({
		Name = "HelmPromptAnchor",
		Parent = kit,
		Size = Vector3.new(1, 1, 1),
		CFrame = wheelCenter * CFrame.new(0, 0, 0.2),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HelmPrompt"
	prompt.ActionText = "Take the Helm"
	prompt.ObjectText = "Steering Wheel"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Helm.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.UIOffset = Vector2.new(0, -40)
	prompt.Parent = promptAnchor

	return stand, prompt, column
end

function RaftStarterKit.attach(model: Model, deck: BasePart, center: Vector3)
	local existing = model:FindFirstChild("StarterKit")
	if existing then
		existing:Destroy()
	end

	local kit = Instance.new("Folder")
	kit.Name = "StarterKit"
	kit.Parent = model

	local stand, prompt = buildHelmWheel(kit, deck, center)

	return {
		kit = kit,
		stand = stand,
		prompt = prompt,
	}
end

return RaftStarterKit
