-- Open-sea weather FX (rain, thunder, overcast grading). Lobby stays clear:
-- effects only run while the local player is in a crew (party ~= nil).
-- Harmless / cosmetic. Lighting overlays are applied locally so pier players
-- keep the untouched day/night look.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayNight = require(Shared:WaitForChild("DayNight"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Weather = require(Shared:WaitForChild("Weather"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))

local WeatherController = {}

local started = false
local atSea = false
local fxFolder: Folder? = nil
local rainAnchor: Part? = nil
local rainEmitter: ParticleEmitter? = nil
local mistEmitter: ParticleEmitter? = nil
local weatherCc: ColorCorrectionEffect? = nil
local flashCc: ColorCorrectionEffect? = nil
local rainSound: Sound? = nil
local thunderSound: Sound? = nil
local windSound: Sound? = nil
local lastFlashAttr: number? = nil
local flashToken = 0
local ambienceTarget = {
	rain = 0,
	wind = 0,
}

-- Particle / ambience assets (catalog ids — no custom uploads required).
local RAIN_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local RAIN_SOUND_ID = "rbxassetid://151755512"
local THUNDER_SOUND_ID = "rbxassetid://166185616"
local WIND_SOUND_ID = "rbxassetid://166185967"

local function ensureFolder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "SurviveAtSeaWeatherFX"
	folder.Parent = Workspace.CurrentCamera or Workspace
	fxFolder = folder
	return folder
end

local function ensureWeatherCc(): ColorCorrectionEffect
	if weatherCc and weatherCc.Parent then
		return weatherCc
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SurviveAtSeaWeather"
	cc.Enabled = false
	cc.Parent = Lighting
	weatherCc = cc
	return cc
end

local function ensureFlashCc(): ColorCorrectionEffect
	if flashCc and flashCc.Parent then
		return flashCc
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SurviveAtSeaLightningFlash"
	cc.Enabled = false
	cc.Brightness = 0
	cc.Contrast = 0
	cc.Saturation = 0
	cc.TintColor = Color3.fromRGB(220, 230, 255)
	cc.Parent = Lighting
	flashCc = cc
	return cc
end

local function makeSound(name: string, soundId: string, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = looped
	sound.Volume = 0
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = SoundService
	return sound
end

local function ensureSounds()
	if not rainSound then
		rainSound = makeSound("SurviveAtSeaRain", RAIN_SOUND_ID, true)
	end
	if not windSound then
		windSound = makeSound("SurviveAtSeaWind", WIND_SOUND_ID, true)
	end
	if not thunderSound then
		thunderSound = makeSound("SurviveAtSeaThunder", THUNDER_SOUND_ID, false)
		thunderSound.Volume = 0.85
	end
end

local function ensureRainRig()
	local folder = ensureFolder()
	if rainAnchor and rainAnchor.Parent then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "RainEmitter"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(90, 1, 90)
	anchor.Parent = folder
	rainAnchor = anchor

	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Texture = RAIN_TEXTURE
	rain.Color = ColorSequence.new(Color3.fromRGB(190, 210, 230))
	rain.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.08),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	rain.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	rain.Lifetime = NumberRange.new(0.55, 0.85)
	rain.Rate = 0
	rain.Speed = NumberRange.new(42, 58)
	rain.SpreadAngle = Vector2.new(4, 4)
	rain.Drag = 0
	rain.Acceleration = Vector3.new(2, -110, 1)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.LightEmission = 0.05
	rain.LightInfluence = 0.65
	rain.LockedToPart = false
	rain.Parent = anchor
	rainEmitter = rain

	local mist = Instance.new("ParticleEmitter")
	mist.Name = "CloudMist"
	mist.Texture = RAIN_TEXTURE
	mist.Color = ColorSequence.new(Color3.fromRGB(160, 175, 190))
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 8),
		NumberSequenceKeypoint.new(1, 18),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.82),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Lifetime = NumberRange.new(2.5, 4.5)
	mist.Rate = 0
	mist.Speed = NumberRange.new(0.2, 1.2)
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.Drag = 1
	mist.Acceleration = Vector3.new(0, 0.15, 0)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.LightEmission = 0.02
	mist.LightInfluence = 0.8
	mist.LockedToPart = false
	mist.Parent = anchor
	mistEmitter = mist
end

local function restoreLobbyLighting()
	-- Snap back to day/night so the pier never keeps storm fog / grading.
	local day = DayNight.getState(Workspace:GetServerTimeNow())
	local base = DayNight.lightingFor(day.dayAmount)
	Lighting.FogColor = base.FogColor
	Lighting.FogStart = base.FogStart
	Lighting.FogEnd = base.FogEnd
	Lighting.Brightness = base.Brightness

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = base.AtmosphereDensity
		atmosphere.Haze = base.AtmosphereHaze
		atmosphere.Glare = base.AtmosphereGlare
		atmosphere.Color = base.AtmosphereColor
		atmosphere.Decay = base.AtmosphereDecay
	end

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		sunRays.Intensity = base.SunRaysIntensity
	end
end

local function setAtSea(value: boolean)
	if atSea == value then
		return
	end
	atSea = value
	if not value then
		-- Hard stop — lobby must not keep rain / storm grading.
		if rainEmitter then
			rainEmitter.Rate = 0
		end
		if mistEmitter then
			mistEmitter.Rate = 0
		end
		if weatherCc then
			weatherCc.Enabled = false
		end
		if flashCc then
			flashCc.Enabled = false
			flashCc.Brightness = 0
		end
		if rainSound then
			rainSound.Volume = 0
			if rainSound.IsPlaying then
				rainSound:Stop()
			end
		end
		if windSound then
			windSound.Volume = 0
			if windSound.IsPlaying then
				windSound:Stop()
			end
		end
		ambienceTarget.rain = 0
		ambienceTarget.wind = 0
		restoreLobbyLighting()
	end
end

local function applyLightingOverlay(state: Weather.WeatherState)
	-- Skip while underwater — OceanController owns that lens.
	local cam = Workspace.CurrentCamera
	if cam and cam.CFrame.Position.Y < OceanConfig.SurfaceY - 0.15 then
		if weatherCc then
			weatherCc.Enabled = false
		end
		return
	end

	local day = DayNight.getState(Workspace:GetServerTimeNow())
	local base = DayNight.lightingFor(day.dayAmount)
	local over = Weather.lightingOverlay(state)

	Lighting.FogColor = base.FogColor:Lerp(over.FogColor, math.clamp(state.cloud * 0.9 + state.rain * 0.2, 0, 1))
	Lighting.FogStart = base.FogStart * over.FogStartMul
	Lighting.FogEnd = base.FogEnd * over.FogEndMul
	Lighting.Brightness = base.Brightness * over.BrightnessMul

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = math.clamp(base.AtmosphereDensity + over.AtmosphereDensityAdd, 0, 0.7)
		atmosphere.Haze = math.clamp(base.AtmosphereHaze + over.AtmosphereHazeAdd, 0, 10)
		atmosphere.Glare = base.AtmosphereGlare * over.AtmosphereGlareMul
		atmosphere.Color = base.AtmosphereColor:Lerp(Color3.fromRGB(120, 135, 150), state.cloud * 0.65)
		atmosphere.Decay = base.AtmosphereDecay:Lerp(Color3.fromRGB(40, 48, 62), state.cloud * 0.55)
	end

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		sunRays.Intensity = base.SunRaysIntensity * over.SunRaysMul
	end

	local cc = ensureWeatherCc()
	cc.Enabled = true
	cc.TintColor = over.ColorCorrectionTint
	cc.Brightness = over.ColorCorrectionBrightnessAdd
	cc.Contrast = over.ColorCorrectionContrastAdd
	cc.Saturation = over.ColorCorrectionSaturationAdd
end

local function syncRainRig(state: Weather.WeatherState, dt: number)
	ensureRainRig()
	local cam = Workspace.CurrentCamera
	if not (cam and rainAnchor) then
		return
	end

	-- Keep a rain volume above / around the camera so drops fill the view.
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.05 then
		flat = flat.Unit
	else
		flat = Vector3.new(0, 0, -1)
	end
	local pos = cam.CFrame.Position + flat * 18 + Vector3.new(0, 28, 0)
	rainAnchor.CFrame = CFrame.new(pos)

	local rainRate = state.rain * 280
	local mistRate = state.cloud * 6 + state.rain * 4
	if rainEmitter then
		-- Ease rates so showers swell instead of popping on.
		rainEmitter.Rate = rainEmitter.Rate + (rainRate - rainEmitter.Rate) * math.clamp(dt * 1.8, 0, 1)
		rainEmitter.Acceleration = Vector3.new(3 + state.rain * 4, -100 - state.rain * 40, 2)
	end
	if mistEmitter then
		mistEmitter.Rate = mistEmitter.Rate + (mistRate - mistEmitter.Rate) * math.clamp(dt * 1.2, 0, 1)
	end
end

local function syncAmbience(state: Weather.WeatherState, dt: number)
	ensureSounds()
	ambienceTarget.rain = if state.rain > 0.05 then math.clamp(0.12 + state.rain * 0.55, 0, 0.7) else 0
	ambienceTarget.wind = math.clamp(state.cloud * 0.18 + state.rain * 0.12 + state.thunderChance * 0.1, 0, 0.35)

	if rainSound then
		local goal = ambienceTarget.rain
		rainSound.Volume += (goal - rainSound.Volume) * math.clamp(dt * 1.4, 0, 1)
		if rainSound.Volume > 0.02 and not rainSound.IsPlaying then
			rainSound:Play()
		elseif rainSound.Volume < 0.01 and rainSound.IsPlaying then
			rainSound:Stop()
		end
	end
	if windSound then
		local goal = ambienceTarget.wind
		windSound.Volume += (goal - windSound.Volume) * math.clamp(dt * 1.1, 0, 1)
		if windSound.Volume > 0.02 and not windSound.IsPlaying then
			windSound:Play()
		elseif windSound.Volume < 0.01 and windSound.IsPlaying then
			windSound:Stop()
		end
	end
end

local function playLightningFlash(intensity: number)
	flashToken += 1
	local token = flashToken
	local cc = ensureFlashCc()
	cc.Enabled = true
	cc.Brightness = 0.55 * intensity
	cc.Contrast = 0.08 * intensity
	cc.Saturation = -0.12 * intensity

	-- Brief whiteout, then a softer afterglow — reads as real lightning.
	task.spawn(function()
		task.wait(0.05)
		if token ~= flashToken then
			return
		end
		TweenService:Create(cc, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 0.12 * intensity,
		}):Play()
		task.wait(0.22)
		if token ~= flashToken then
			return
		end
		TweenService:Create(cc, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
		}):Play()
		task.wait(0.6)
		if token == flashToken then
			cc.Enabled = false
		end
	end)

	ensureSounds()
	if thunderSound then
		-- Delay rumble slightly after the flash (sound travels).
		local delaySec = math.clamp(0.35 + (1 - intensity) * 1.6, 0.25, 2.2)
		task.delay(delaySec, function()
			if not atSea then
				return
			end
			thunderSound.PlaybackSpeed = 0.92 + math.random() * 0.16
			thunderSound.Volume = 0.45 + intensity * 0.5
			thunderSound:Play()
		end)
	end
end

local function watchPartyState()
	task.spawn(function()
		local ok, folder = pcall(function()
			return Remotes.getFolder()
		end)
		if not ok or not folder then
			return
		end
		local partyUpdated = folder:WaitForChild("PartyUpdated", 30)
		local getLobbyState = folder:WaitForChild("GetLobbyState", 30)
		if getLobbyState and getLobbyState:IsA("RemoteFunction") then
			local success, lobbyState = pcall(function()
				return getLobbyState:InvokeServer()
			end)
			if success and typeof(lobbyState) == "table" then
				setAtSea(typeof(lobbyState.party) == "table")
			end
		end
		if partyUpdated and partyUpdated:IsA("RemoteEvent") then
			partyUpdated.OnClientEvent:Connect(function(party)
				if typeof(party) == "table" and party.__openCreate then
					return
				end
				setAtSea(typeof(party) == "table")
			end)
		end
	end)
end

function WeatherController.start()
	if started then
		return
	end
	started = true

	ensureWeatherCc()
	ensureFlashCc()
	ensureSounds()
	watchPartyState()

	-- Reparent FX folder under camera when it appears.
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if fxFolder and Workspace.CurrentCamera then
			fxFolder.Parent = Workspace.CurrentCamera
		end
	end)

	Workspace:GetAttributeChangedSignal(Weather.ATTR_FLASH):Connect(function()
		if not atSea then
			return
		end
		local flashAt = Workspace:GetAttribute(Weather.ATTR_FLASH)
		if typeof(flashAt) ~= "number" then
			return
		end
		if lastFlashAttr == flashAt then
			return
		end
		lastFlashAttr = flashAt
		local state = Weather.readStateFromWorkspace(Workspace)
		local intensity = if state then math.clamp(0.45 + state.thunderChance * 0.55, 0.4, 1) else 0.7
		playLightningFlash(intensity)
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not atSea then
			return
		end
		local state = Weather.readStateFromWorkspace(Workspace)
		if not state then
			return
		end
		applyLightingOverlay(state)
		syncRainRig(state, dt)
		syncAmbience(state, dt)
	end)

	print("[SurviveAtSea] Weather controller ready — open-sea only, lobby untouched")
end

return WeatherController
