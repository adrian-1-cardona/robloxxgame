-- Cosmetic open-sea weather: sunny, overcast, light rain, thunder, thunderstorm.
-- No damage — atmosphere only. Shared math for server schedule + client FX.
-- Lobby stays clear: clients apply FX only while in a crew at sea.

local Weather = {}

export type Mode = "Sunny" | "Overcast" | "LightRain" | "Thunder" | "Thunderstorm"

export type WeatherState = {
	fromMode: Mode,
	toMode: Mode,
	-- 0 = fully fromMode, 1 = fully toMode (during a hold, from==to and blend=1)
	blend: number,
	-- Effective weights after blending (for particles / sound)
	rain: number,
	cloud: number,
	thunderChance: number,
	sun: number,
	-- Session age factor [0, 1] — storms grow more likely as the voyage wears on
	voyageAge: number,
}

Weather.Modes = { "Sunny", "Overcast", "LightRain", "Thunder", "Thunderstorm" } :: { Mode }

-- Hold long enough to feel settled; short enough that the sky keeps moving.
Weather.MinHoldSeconds = 85
Weather.MaxHoldSeconds = 160
-- Crossfade between modes — gradual, never a hard cut.
Weather.MinTransitionSeconds = 22
Weather.MaxTransitionSeconds = 38

-- After this many seconds of server uptime, storm weights reach their peak.
Weather.VoyageRampSeconds = 720 -- 12 minutes

-- Workspace attribute names (server writes, clients read).
Weather.ATTR_FROM = "SurviveAtSeaWeatherFrom"
Weather.ATTR_TO = "SurviveAtSeaWeatherTo"
Weather.ATTR_BLEND = "SurviveAtSeaWeatherBlend"
Weather.ATTR_RAIN = "SurviveAtSeaWeatherRain"
Weather.ATTR_CLOUD = "SurviveAtSeaWeatherCloud"
Weather.ATTR_THUNDER = "SurviveAtSeaWeatherThunder"
Weather.ATTR_SUN = "SurviveAtSeaWeatherSun"
Weather.ATTR_VOYAGE = "SurviveAtSeaWeatherVoyage"
Weather.ATTR_FLASH = "SurviveAtSeaWeatherFlash" -- server time of last lightning strike

-- Realistic neighbor graph — weather drifts, it doesn't teleport.
local NEIGHBORS: { [Mode]: { Mode } } = {
	Sunny = { "Overcast", "Sunny" },
	Overcast = { "Sunny", "LightRain", "Thunder", "Overcast" },
	LightRain = { "Overcast", "Thunder", "Thunderstorm", "LightRain" },
	Thunder = { "Overcast", "LightRain", "Thunderstorm", "Thunder" },
	Thunderstorm = { "LightRain", "Thunder", "Thunderstorm" },
}

-- Per-mode visual targets (0–1 intensity channels).
local MODE_LOOK: { [Mode]: { rain: number, cloud: number, thunder: number, sun: number } } = {
	Sunny = { rain = 0, cloud = 0.05, thunder = 0, sun = 1 },
	Overcast = { rain = 0, cloud = 0.72, thunder = 0, sun = 0.25 },
	LightRain = { rain = 0.45, cloud = 0.82, thunder = 0.05, sun = 0.12 },
	Thunder = { rain = 0.15, cloud = 0.88, thunder = 0.55, sun = 0.08 },
	Thunderstorm = { rain = 1, cloud = 0.96, thunder = 1, sun = 0.02 },
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Weather.isMode(value: unknown): boolean
	return typeof(value) == "string"
		and (
			value == "Sunny"
			or value == "Overcast"
			or value == "LightRain"
			or value == "Thunder"
			or value == "Thunderstorm"
		)
end

function Weather.voyageAge(elapsedSeconds: number): number
	return smoothstep(math.clamp(elapsedSeconds / Weather.VoyageRampSeconds, 0, 1))
end

-- Base pick weights, then voyage age leans the sky toward wetter weather.
function Weather.weightFor(mode: Mode, voyageAge: number): number
	local early: { [Mode]: number } = {
		Sunny = 42,
		Overcast = 28,
		LightRain = 18,
		Thunder = 8,
		Thunderstorm = 4,
	}
	local late: { [Mode]: number } = {
		Sunny = 18,
		Overcast = 24,
		LightRain = 26,
		Thunder = 16,
		Thunderstorm = 16,
	}
	return lerp(early[mode], late[mode], voyageAge)
end

function Weather.pickNext(rng: Random, current: Mode, voyageAge: number): Mode
	local candidates = NEIGHBORS[current]
	local total = 0
	local weights = table.create(#candidates)
	for i, mode in candidates do
		-- Softly discourage immediate repeats of the same label during a "hold refresh".
		local w = Weather.weightFor(mode, voyageAge)
		if mode == current then
			w *= 0.35
		end
		weights[i] = w
		total += w
	end
	if total <= 0 then
		return "Overcast"
	end
	local roll = rng:NextNumber(0, total)
	local acc = 0
	for i, mode in candidates do
		acc += weights[i]
		if roll <= acc then
			return mode
		end
	end
	return candidates[#candidates]
end

function Weather.holdDuration(rng: Random): number
	return rng:NextNumber(Weather.MinHoldSeconds, Weather.MaxHoldSeconds)
end

function Weather.transitionDuration(rng: Random): number
	return rng:NextNumber(Weather.MinTransitionSeconds, Weather.MaxTransitionSeconds)
end

function Weather.channelsFor(fromMode: Mode, toMode: Mode, blend: number): {
	rain: number,
	cloud: number,
	thunder: number,
	sun: number,
}
	local t = smoothstep(blend)
	local a = MODE_LOOK[fromMode]
	local b = MODE_LOOK[toMode]
	return {
		rain = lerp(a.rain, b.rain, t),
		cloud = lerp(a.cloud, b.cloud, t),
		thunder = lerp(a.thunder, b.thunder, t),
		sun = lerp(a.sun, b.sun, t),
	}
end

function Weather.makeState(
	fromMode: Mode,
	toMode: Mode,
	blend: number,
	voyageAge: number
): WeatherState
	local ch = Weather.channelsFor(fromMode, toMode, blend)
	return {
		fromMode = fromMode,
		toMode = toMode,
		blend = math.clamp(blend, 0, 1),
		rain = ch.rain,
		cloud = ch.cloud,
		thunderChance = ch.thunder,
		sun = ch.sun,
		voyageAge = voyageAge,
	}
end

-- Lighting overlays blended on top of DayNight.lightingFor() for at-sea clients.
function Weather.lightingOverlay(state: WeatherState): {
	FogColor: Color3,
	FogStartMul: number,
	FogEndMul: number,
	AtmosphereDensityAdd: number,
	AtmosphereHazeAdd: number,
	AtmosphereGlareMul: number,
	BrightnessMul: number,
	SunRaysMul: number,
	ColorCorrectionTint: Color3,
	ColorCorrectionSaturationAdd: number,
	ColorCorrectionBrightnessAdd: number,
	ColorCorrectionContrastAdd: number,
}
	local cloud = state.cloud
	local rain = state.rain
	local sun = state.sun

	local clearFog = Color3.fromRGB(130, 170, 190)
	local stormFog = Color3.fromRGB(72, 84, 96)
	local fogColor = clearFog:Lerp(stormFog, math.clamp(cloud * 0.85 + rain * 0.25, 0, 1))

	return {
		FogColor = fogColor,
		FogStartMul = lerp(1, 0.55, cloud * 0.7 + rain * 0.3),
		FogEndMul = lerp(1, 0.48, cloud * 0.65 + rain * 0.35),
		AtmosphereDensityAdd = cloud * 0.22 + rain * 0.08,
		AtmosphereHazeAdd = cloud * 1.35 + rain * 0.4,
		AtmosphereGlareMul = lerp(1, 0.15, 1 - sun),
		BrightnessMul = lerp(0.72, 1.05, sun) * lerp(1, 0.88, rain),
		SunRaysMul = math.clamp(sun * 1.15, 0, 1),
		ColorCorrectionTint = Color3.fromRGB(255, 248, 238):Lerp(Color3.fromRGB(188, 200, 214), cloud),
		ColorCorrectionSaturationAdd = lerp(0.04, -0.16, cloud) + rain * -0.04,
		ColorCorrectionBrightnessAdd = lerp(0.02, -0.05, cloud) + rain * -0.03,
		ColorCorrectionContrastAdd = cloud * 0.04 + rain * 0.02,
	}
end

-- Mean seconds between lightning strikes at full thunderstorm intensity.
function Weather.lightningInterval(thunderChance: number): number?
	if thunderChance < 0.12 then
		return nil
	end
	-- Thunder: ~18–40s · Thunderstorm: ~4–12s (scaled by chance)
	local minGap = lerp(40, 4.5, thunderChance)
	local maxGap = lerp(70, 12, thunderChance)
	return (minGap + maxGap) * 0.5
end

function Weather.readStateFromWorkspace(workspace: Workspace): WeatherState?
	local fromMode = workspace:GetAttribute(Weather.ATTR_FROM)
	local toMode = workspace:GetAttribute(Weather.ATTR_TO)
	if not (Weather.isMode(fromMode) and Weather.isMode(toMode)) then
		return nil
	end
	local blend = workspace:GetAttribute(Weather.ATTR_BLEND)
	local rain = workspace:GetAttribute(Weather.ATTR_RAIN)
	local cloud = workspace:GetAttribute(Weather.ATTR_CLOUD)
	local thunder = workspace:GetAttribute(Weather.ATTR_THUNDER)
	local sun = workspace:GetAttribute(Weather.ATTR_SUN)
	local voyage = workspace:GetAttribute(Weather.ATTR_VOYAGE)
	if typeof(blend) ~= "number" then
		blend = 1
	end
	return {
		fromMode = fromMode :: Mode,
		toMode = toMode :: Mode,
		blend = blend,
		rain = if typeof(rain) == "number" then rain else 0,
		cloud = if typeof(cloud) == "number" then cloud else 0,
		thunderChance = if typeof(thunder) == "number" then thunder else 0,
		sun = if typeof(sun) == "number" then sun else 1,
		voyageAge = if typeof(voyage) == "number" then voyage else 0,
	}
end

return Weather
