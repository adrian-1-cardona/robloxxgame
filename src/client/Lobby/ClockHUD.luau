-- Gameplay clock lives in the crew menu (old Cast Off slot).
-- Lobby stays daytime with no clock — this module only applies lighting.
-- While on a crew, lighting follows that crew's cycle (always starts at 6:00 AM).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DayNight = require(Shared:WaitForChild("DayNight"))

local ClockHUD = {}

local started = false
local inGameplay = false
-- Server time when the local player's crew was created (nil in lobby).
local cycleOrigin: number? = nil

local atmosphere: Atmosphere? = nil
local sunRays: SunRaysEffect? = nil
local colorCorrection: ColorCorrectionEffect? = nil
local sky: Sky? = nil

local function ensureEffects()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	sky = Lighting:FindFirstChildOfClass("Sky")

	colorCorrection = nil
	for _, child in Lighting:GetChildren() do
		if
			child:IsA("ColorCorrectionEffect")
			and child.Name ~= "SurviveAtSeaUnderwater"
			and child.Name ~= "SurviveAtSeaWeather"
			and child.Name ~= "SurviveAtSeaLightningFlash"
		then
			colorCorrection = child
			break
		end
	end
end

local function applyLook(clockTime: number, dayAmount: number)
	ensureEffects()
	local look = DayNight.lightingFor(dayAmount)

	Lighting.ClockTime = clockTime
	Lighting.Brightness = look.Brightness
	Lighting.Ambient = look.Ambient
	Lighting.OutdoorAmbient = look.OutdoorAmbient
	Lighting.FogColor = look.FogColor
	Lighting.FogStart = look.FogStart
	Lighting.FogEnd = look.FogEnd

	if atmosphere then
		atmosphere.Density = look.AtmosphereDensity
		atmosphere.Color = look.AtmosphereColor
		atmosphere.Decay = look.AtmosphereDecay
		atmosphere.Haze = look.AtmosphereHaze
		atmosphere.Glare = look.AtmosphereGlare
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
end

-- Midday lobby look — pier is always bright daytime.
local function applyLobbyDay()
	applyLook(12, 1)
end

local function applyGameplayCycle()
	local state = DayNight.getState(Workspace:GetServerTimeNow(), cycleOrigin)
	applyLook(state.clockTime, state.dayAmount)
end

function ClockHUD.setGameplayActive(active: boolean, origin: number?)
	inGameplay = active
	cycleOrigin = if active then origin else nil
	if active then
		applyGameplayCycle()
	else
		applyLobbyDay()
	end
end

function ClockHUD.isGameplayActive(): boolean
	return inGameplay
end

function ClockHUD.getCycleOrigin(): number?
	return cycleOrigin
end

-- Shared day/night state for ocean fog / weather overlays while at sea.
function ClockHUD.getGameplayState(): DayNight.CycleState
	return DayNight.getState(Workspace:GetServerTimeNow(), cycleOrigin)
end

function ClockHUD.start()
	if started then
		return
	end
	started = true

	-- Default: lobby daytime until the crew menu says otherwise.
	applyLobbyDay()

	local accum = 0
	RunService.RenderStepped:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		if inGameplay then
			applyGameplayCycle()
		else
			applyLobbyDay()
		end
	end)

	print("[SurviveAtSea] Lobby daytime lock ready (crew clocks start at 6:00 AM)")
end

return ClockHUD
