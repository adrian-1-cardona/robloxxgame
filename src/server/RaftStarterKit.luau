-- Visual starter kit for each crew raft: pirate mast + white flag + helm wheel.
-- Pure construction — HelmService owns interaction / movement.

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

local function buildMastAndFlag(kit: Folder, deck: BasePart, center: Vector3)
	local thickness = Config.StarterBase.Thickness
	local mastOffset = Config.Helm.MastLocalOffset
	local mastBase = Vector3.new(center.X + mastOffset.X, deckTopY(deck), center.Z + mastOffset.Z)
	local mastHeight = 26

	local mast = makePart({
		Name = "Mast",
		Parent = kit,
		Size = Vector3.new(1.1, mastHeight, 1.1),
		CFrame = CFrame.new(mastBase + Vector3.new(0, mastHeight / 2, 0)),
		Color = Color3.fromRGB(78, 52, 30),
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	-- Cross yard so the white flag reads as a ship ensign, not a stick
	makePart({
		Name = "Yardarm",
		Parent = kit,
		Size = Vector3.new(10, 0.55, 0.55),
		CFrame = CFrame.new(mast.Position + Vector3.new(0, mastHeight * 0.28, 0)),
		Color = Color3.fromRGB(92, 64, 42),
		Material = Enum.Material.Wood,
	})

	makePart({
		Name = "MastCap",
		Parent = kit,
		Size = Vector3.new(1.6, 0.7, 1.6),
		CFrame = CFrame.new(mast.Position + Vector3.new(0, mastHeight / 2 + 0.2, 0)),
		Color = Color3.fromRGB(68, 46, 28),
		Material = Enum.Material.Wood,
	})

	-- Clean white flag hanging from the upper mast
	local flag = makePart({
		Name = "WhiteFlag",
		Parent = kit,
		Size = Vector3.new(0.18, 5.2, 7.5),
		CFrame = CFrame.new(mast.Position + Vector3.new(0, mastHeight * 0.22, -4.2))
			* CFrame.Angles(0, 0, math.rad(4)),
		Color = Color3.fromRGB(248, 248, 252),
		Material = Enum.Material.Fabric,
		CastShadow = true,
	})

	-- Soft pennant tip so it feels like cloth, not a box
	makePart({
		Name = "FlagTip",
		Parent = kit,
		Size = Vector3.new(0.16, 3.2, 2.4),
		CFrame = flag.CFrame * CFrame.new(0, -0.4, -4.6) * CFrame.Angles(0, 0, math.rad(8)),
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.Fabric,
	})

	-- Rope wraps at the mast foot
	makePart({
		Name = "MastCollar",
		Parent = kit,
		Size = Vector3.new(1.8, 1.2, 1.8),
		CFrame = CFrame.new(mastBase + Vector3.new(0, 0.8, 0)),
		Color = Config.Theme.Rope,
		Material = Enum.Material.Fabric,
		CanCollide = true,
	})

	-- Keep thickness reference used by callers that expect deck-relative layout
	return thickness
end

local function buildHelmWheel(kit: Folder, deck: BasePart, center: Vector3)
	local standOffset = Config.Helm.StandLocalOffset
	local topY = deckTopY(deck)
	local standPos = Vector3.new(center.X + standOffset.X, topY, center.Z + standOffset.Z)
	-- Face toward the bow (negative Z in local raft space)
	local standCf = CFrame.new(standPos, standPos + Vector3.new(0, 0, -10))

	local pedestal = makePart({
		Name = "HelmPedestal",
		Parent = kit,
		Size = Vector3.new(1.6, 3.2, 1.6),
		CFrame = standCf * CFrame.new(0, 1.6, 0),
		Color = Color3.fromRGB(72, 48, 28),
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	makePart({
		Name = "HelmBase",
		Parent = kit,
		Size = Vector3.new(3.2, 0.5, 3.2),
		CFrame = standCf * CFrame.new(0, 0.25, 0),
		Color = Color3.fromRGB(86, 58, 34),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})

	-- Rim (cylinder) — classic pirate wheel
	local rim = makePart({
		Name = "HelmRim",
		Parent = kit,
		Size = Vector3.new(0.55, 4.4, 4.4),
		CFrame = standCf * CFrame.new(0, 3.55, -0.55) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(110, 78, 48),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})

	local hub = makePart({
		Name = "HelmHub",
		Parent = kit,
		Size = Vector3.new(0.7, 1.1, 1.1),
		CFrame = rim.CFrame,
		Color = Color3.fromRGB(58, 40, 24),
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})

	-- Spokes
	for i = 0, 5 do
		local angle = math.rad(i * 30)
		makePart({
			Name = `HelmSpoke_{i}`,
			Parent = kit,
			Size = Vector3.new(0.28, 0.28, 3.6),
			CFrame = hub.CFrame * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, 0),
			Color = Color3.fromRGB(96, 68, 42),
			Material = Enum.Material.Wood,
		})
	end

	-- Handles on the rim
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		makePart({
			Name = `HelmHandle_{i}`,
			Parent = kit,
			Size = Vector3.new(0.35, 0.9, 0.35),
			CFrame = hub.CFrame * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 2.35, 0),
			Color = Color3.fromRGB(130, 92, 55),
			Material = Enum.Material.Wood,
		})
	end

	-- Invisible stand anchor: where the sailor is locked while steering
	local stand = makePart({
		Name = "HelmStand",
		Parent = kit,
		Size = Vector3.new(2.2, 0.4, 2.2),
		CFrame = standCf * CFrame.new(0, 0.15, 1.35),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	stand:SetAttribute("IsHelmStand", true)

	-- Prompt rides an upright anchor at hand height
	local promptAnchor = makePart({
		Name = "HelmPromptAnchor",
		Parent = kit,
		Size = Vector3.new(1, 1, 1),
		CFrame = standCf * CFrame.new(0, 3.2, 0.4),
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
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = promptAnchor

	return stand, prompt, pedestal
end

function RaftStarterKit.attach(model: Model, deck: BasePart, center: Vector3)
	local existing = model:FindFirstChild("StarterKit")
	if existing then
		existing:Destroy()
	end

	local kit = Instance.new("Folder")
	kit.Name = "StarterKit"
	kit.Parent = model

	buildMastAndFlag(kit, deck, center)
	local stand, prompt = buildHelmWheel(kit, deck, center)

	return {
		kit = kit,
		stand = stand,
		prompt = prompt,
	}
end

return RaftStarterKit
