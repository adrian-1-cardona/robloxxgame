-- Client ocean polish: underwater lens, raft foam, and a wake when sailing.
-- Terrain water (server) owns the wave field; this layer sells the immersion.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))
local DayNight = require(Shared:WaitForChild("DayNight"))

local ClockHUD = require(script.Parent.ClockHUD)

local OceanController = {}

local SURFACE_Y = OceanConfig.SurfaceY
local TAG_FOAM = "SurviveAtSeaOceanFoam"

local underwaterCc: ColorCorrectionEffect? = nil
local underwaterActive = false
local foamByDeck: { [BasePart]: Folder } = {}
local lastDeckPos: { [BasePart]: Vector3 } = {}
local started = false

local function surfaceFogFromCycle()
	-- Lobby is always midday; only follow the cycle while on a crew.
	local dayAmount = if ClockHUD.isGameplayActive()
		then ClockHUD.getGameplayState().dayAmount
		else 1
	local look = DayNight.lightingFor(dayAmount)
	return {
		FogColor = look.FogColor,
		FogStart = look.FogStart,
		FogEnd = look.FogEnd,
	}
end

local function ensureUnderwaterFx()
	if underwaterCc and underwaterCc.Parent then
		return underwaterCc
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SurviveAtSeaUnderwater"
	cc.Enabled = false
	cc.TintColor = OceanConfig.Underwater.Tint
	cc.Contrast = OceanConfig.Underwater.Contrast
	cc.Saturation = OceanConfig.Underwater.Saturation
	cc.Brightness = OceanConfig.Underwater.Brightness
	cc.Parent = Lighting
	underwaterCc = cc
	return cc
end

local function setUnderwater(active: boolean)
	local cc = ensureUnderwaterFx()
	if underwaterActive == active and cc.Enabled == active then
		return
	end
	underwaterActive = active
	cc.Enabled = active
	if active then
		Lighting.FogColor = OceanConfig.Underwater.FogColor
		Lighting.FogStart = OceanConfig.Underwater.FogStart
		Lighting.FogEnd = OceanConfig.Underwater.FogEnd
	else
		-- Restore fog from the live day/night cycle, not a stale boot snapshot.
		local fog = surfaceFogFromCycle()
		Lighting.FogColor = fog.FogColor
		Lighting.FogStart = fog.FogStart
		Lighting.FogEnd = fog.FogEnd
	end
end

local function makeEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = props.Name or "OceanParticle"
	e.Texture = props.Texture or "rbxasset://textures/particles/smoke_main.dds"
	e.Color = props.Color or ColorSequence.new(Color3.fromRGB(230, 245, 250))
	e.Size = props.Size
		or NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.5, 1.1),
			NumberSequenceKeypoint.new(1, 0.2),
		})
	e.Transparency = props.Transparency
		or NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.7, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
	e.Lifetime = props.Lifetime or NumberRange.new(0.45, 1.1)
	e.Rate = props.Rate or 0
	e.Speed = props.Speed or NumberRange.new(0.4, 1.8)
	e.SpreadAngle = props.SpreadAngle or Vector2.new(25, 25)
	e.Drag = props.Drag or 2.5
	e.Acceleration = props.Acceleration or Vector3.new(0, -2, 0)
	e.EmissionDirection = props.EmissionDirection or Enum.NormalId.Top
	e.LightEmission = props.LightEmission or 0.15
	e.LightInfluence = props.LightInfluence or 0.55
	e.RotSpeed = props.RotSpeed or NumberRange.new(-40, 40)
	e.Rotation = NumberRange.new(0, 360)
	e.LockedToPart = false
	e.Parent = parent
	return e
end

local function attachFoamToDeck(deck: BasePart)
	if foamByDeck[deck] then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "OceanFoamFX"
	folder.Parent = deck

	local size = deck.Size
	local half = size * 0.5
	local waterlineY = SURFACE_Y - deck.Position.Y

	local edges = {
		{ Name = "FoamNorth", Local = CFrame.new(0, waterlineY, -half.Z + 0.4), Size = Vector3.new(size.X * 0.92, 0.2, 1.2) },
		{ Name = "FoamSouth", Local = CFrame.new(0, waterlineY, half.Z - 0.4), Size = Vector3.new(size.X * 0.92, 0.2, 1.2) },
		{ Name = "FoamWest", Local = CFrame.new(-half.X + 0.4, waterlineY, 0), Size = Vector3.new(1.2, 0.2, size.Z * 0.92) },
		{ Name = "FoamEast", Local = CFrame.new(half.X - 0.4, waterlineY, 0), Size = Vector3.new(1.2, 0.2, size.Z * 0.92) },
	}

	for _, edge in edges do
		local anchor = Instance.new("Part")
		anchor.Name = edge.Name
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = edge.Size
		anchor.CFrame = deck.CFrame * edge.Local
		anchor.Parent = folder

		local foam = makeEmitter(anchor, {
			Name = "Foam",
			Rate = 10,
			Lifetime = NumberRange.new(0.55, 1.25),
			Speed = NumberRange.new(0.2, 1.1),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.55, 1.6),
				NumberSequenceKeypoint.new(1, 0.3),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.65, 0.65),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Color = ColorSequence.new(Color3.fromRGB(235, 248, 252)),
			Acceleration = Vector3.new(0, -1.2, 0),
		})
		foam:SetAttribute("BaseRate", 10)

		local mist = makeEmitter(anchor, {
			Name = "Mist",
			Rate = 3,
			Lifetime = NumberRange.new(1.2, 2.4),
			Speed = NumberRange.new(0.1, 0.5),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.2),
				NumberSequenceKeypoint.new(1, 3.5),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Color = ColorSequence.new(Color3.fromRGB(190, 220, 230)),
			Acceleration = Vector3.new(0, 0.4, 0),
			LightEmission = 0.05,
		})
		mist:SetAttribute("BaseRate", 3)
	end

	local bow = Instance.new("Part")
	bow.Name = "BowSpray"
	bow.Anchored = true
	bow.CanCollide = false
	bow.CanQuery = false
	bow.CanTouch = false
	bow.CastShadow = false
	bow.Transparency = 1
	bow.Size = Vector3.new(6, 0.4, 4)
	bow.CFrame = deck.CFrame * CFrame.new(0, waterlineY, -half.Z - 1.5)
	bow.Parent = folder

	local spray = makeEmitter(bow, {
		Name = "Spray",
		Rate = 0,
		Lifetime = NumberRange.new(0.35, 0.85),
		Speed = NumberRange.new(4, 12),
		SpreadAngle = Vector2.new(35, 55),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.4, 1.4),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.55, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(245, 252, 255)),
		Acceleration = Vector3.new(0, -18, 0),
		EmissionDirection = Enum.NormalId.Front,
		LightEmission = 0.25,
	})
	spray:SetAttribute("BaseRate", 0)

	foamByDeck[deck] = folder
	lastDeckPos[deck] = deck.Position
	CollectionService:AddTag(deck, TAG_FOAM)
end

local function detachFoam(deck: BasePart)
	local folder = foamByDeck[deck]
	if folder then
		folder:Destroy()
	end
	foamByDeck[deck] = nil
	lastDeckPos[deck] = nil
end

local function findCrewDeck(): BasePart?
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if not root then
		return nil
	end
	local bases = root:FindFirstChild("StarterBases")
	if not bases then
		return nil
	end

	local player = Players.LocalPlayer
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return nil
	end

	local best: BasePart? = nil
	local bestDist = 220
	for _, model in bases:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local deck = model.PrimaryPart or model:FindFirstChild("Deck")
		if deck and deck:IsA("BasePart") then
			local dist = (deck.Position - hrp.Position).Magnitude
			if dist < bestDist then
				bestDist = dist
				best = deck
			end
		end
	end
	return best
end

local function syncFoamAnchors(deck: BasePart, folder: Folder, speed: number)
	local size = deck.Size
	local half = size * 0.5
	local waterlineY = SURFACE_Y - deck.Position.Y

	local layout = {
		FoamNorth = CFrame.new(0, waterlineY, -half.Z + 0.4),
		FoamSouth = CFrame.new(0, waterlineY, half.Z - 0.4),
		FoamWest = CFrame.new(-half.X + 0.4, waterlineY, 0),
		FoamEast = CFrame.new(half.X - 0.4, waterlineY, 0),
		BowSpray = CFrame.new(0, waterlineY, -half.Z - 1.5),
	}

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			local localCf = layout[child.Name]
			if localCf then
				child.CFrame = deck.CFrame * localCf
			end
			for _, emitter in child:GetChildren() do
				if emitter:IsA("ParticleEmitter") then
					local base = emitter:GetAttribute("BaseRate")
					if typeof(base) ~= "number" then
						base = emitter.Rate
					end
					if emitter.Name == "Spray" then
						emitter.Rate = if speed > 6 then math.clamp(speed * 1.8, 0, 90) else 0
					else
						emitter.Rate = (base :: number) * (1 + math.clamp(speed / 40, 0, 2.5))
					end
				end
			end
		end
	end
end

function OceanController.start()
	if started then
		return
	end
	started = true

	ensureUnderwaterFx()

	RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			local under = cam.CFrame.Position.Y < SURFACE_Y - 0.15
			setUnderwater(under)
			-- Re-assert underwater fog each frame so server day/night fog updates don't punch through.
			if under then
				Lighting.FogColor = OceanConfig.Underwater.FogColor
				Lighting.FogStart = OceanConfig.Underwater.FogStart
				Lighting.FogEnd = OceanConfig.Underwater.FogEnd
			end
		end
	end)

	-- Foam / wake upkeep is expensive (scans crew decks + re-CFrames many parts), so it
	-- runs on a fixed ~15 Hz tick instead of every frame, and is skipped entirely in the
	-- lobby where there are no crew rafts to foam.
	local foamAccum = 0
	local FOAM_INTERVAL = 1 / 15
	RunService.Heartbeat:Connect(function(dt)
		if not ClockHUD.isGameplayActive() then
			-- Left the crew / on the pier: drop any lingering foam and idle.
			if next(foamByDeck) then
				for tracked in foamByDeck do
					detachFoam(tracked)
				end
			end
			foamAccum = 0
			return
		end

		foamAccum += dt
		if foamAccum < FOAM_INTERVAL then
			return
		end
		local step = foamAccum
		foamAccum = 0

		local deck = findCrewDeck()
		if deck then
			attachFoamToDeck(deck)
		end

		for tracked, folder in foamByDeck do
			if not tracked.Parent or not folder.Parent then
				detachFoam(tracked)
			end
		end

		for tracked, folder in foamByDeck do
			local prev = lastDeckPos[tracked]
			local pos = tracked.Position
			local speed = 0
			if prev and step > 0 then
				speed = (pos - prev).Magnitude / step
			end
			lastDeckPos[tracked] = pos
			syncFoamAnchors(tracked, folder, speed)
		end
	end)

	print("[SurviveAtSea] Ocean controller ready — foam, wake, underwater lens")
end

return OceanController
