-- Authoritative day / night cycle. Advances Lighting from server time so every
-- client stays in sync. Players see a normal clock; brightness follows behind.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DayNight = require(Shared:WaitForChild("DayNight"))

local DayNightService = {}

local ATTR_CLOCK = "SurviveAtSeaClockTime"
local ATTR_DISPLAY = "SurviveAtSeaClockDisplay"
local ATTR_PHASE = "SurviveAtSeaDayPhase"
local ATTR_DAY_AMOUNT = "SurviveAtSeaDayAmount"

local started = false
local atmosphere: Atmosphere? = nil
local sunRays: SunRaysEffect? = nil
local colorCorrection: ColorCorrectionEffect? = nil
local sky: Sky? = nil

local function ensureEffects()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end

	sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not sunRays then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Spread = 0.55
		sunRays.Parent = Lighting
	end

	colorCorrection = nil
	for _, child in Lighting:GetChildren() do
		if child:IsA("ColorCorrectionEffect") and child.Name ~= "SurviveAtSeaUnderwater" then
			colorCorrection = child
			break
		end
	end
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "SurviveAtSeaDayNight"
		colorCorrection.Parent = Lighting
	end

	sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 20
	sky.MoonAngularSize = 11
end

local function applyState(state: DayNight.CycleState)
	local look = DayNight.lightingFor(state.dayAmount)

	Lighting.ClockTime = state.clockTime
	Lighting.Brightness = look.Brightness
	Lighting.Ambient = look.Ambient
	Lighting.OutdoorAmbient = look.OutdoorAmbient
	Lighting.FogColor = look.FogColor
	Lighting.FogStart = look.FogStart
	Lighting.FogEnd = look.FogEnd
	Lighting.GlobalShadows = true

	if atmosphere then
		atmosphere.Density = look.AtmosphereDensity
		atmosphere.Color = look.AtmosphereColor
		atmosphere.Decay = look.AtmosphereDecay
		atmosphere.Haze = look.AtmosphereHaze
		atmosphere.Glare = look.AtmosphereGlare
		atmosphere.Offset = 0.22
	end

	if sunRays then
		sunRays.Intensity = look.SunRaysIntensity
	end

	if colorCorrection then
		colorCorrection.TintColor = look.ColorCorrectionTint
		colorCorrection.Brightness = look.ColorCorrectionBrightness
		colorCorrection.Contrast = look.ColorCorrectionContrast
		colorCorrection.Saturation = look.ColorCorrectionSaturation
	end

	if sky then
		sky.StarCount = look.StarCount
	end

	-- Replicated attributes for HUD / client helpers (also computable from server time).
	Workspace:SetAttribute(ATTR_CLOCK, state.clockTime)
	Workspace:SetAttribute(ATTR_DISPLAY, state.displayTime)
	Workspace:SetAttribute(ATTR_PHASE, state.phase)
	Workspace:SetAttribute(ATTR_DAY_AMOUNT, state.dayAmount)
end

function DayNightService.start()
	if started then
		return
	end
	started = true

	ensureEffects()
	applyState(DayNight.getState(Workspace:GetServerTimeNow()))

	-- Smooth enough for sun motion without hammering property replication.
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		applyState(DayNight.getState(Workspace:GetServerTimeNow()))
	end)

	print("[SurviveAtSea] Day/night cycle started — 10 min day, 10 min night")
end

return DayNightService
