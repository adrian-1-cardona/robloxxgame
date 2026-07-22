-- Day / night cycle math shared by server lighting and client clock HUD.
-- Real time: 10 minutes day + 10 minutes night = 20-minute full cycle.
-- Game clock: day runs 6:00 AM → 6:00 PM, night runs 6:00 PM → 6:00 AM.
-- Crews always begin at 6:00 AM (pass cycleOrigin = create server time).
-- Players see a whole-hour clock (e.g. 2:00 PM); lighting still blends smoothly.

local DayNight = {}

DayNight.DaySeconds = 600
DayNight.NightSeconds = 600
DayNight.CycleSeconds = DayNight.DaySeconds + DayNight.NightSeconds

-- Game-clock endpoints (Roblox Lighting.ClockTime is 0–24)
DayNight.DayStartHour = 6
DayNight.NightStartHour = 18

export type Phase = "Day" | "Night"

export type CycleState = {
	phase: Phase,
	-- Position within the full 20-minute cycle [0, CycleSeconds)
	cycleSeconds: number,
	-- Progress within the current phase [0, 1]
	phaseAlpha: number,
	-- Roblox ClockTime hours [0, 24) — smooth for lighting
	clockTime: number,
	-- Display string like "2:00 PM" (whole hours only)
	displayTime: string,
	-- 1 = full daylight, 0 = deep night (smooth across dawn/dusk)
	dayAmount: number,
	-- Whole voyage day counter — starts at 1 (6:00 AM) and increments each cycle
	dayNumber: number,
}

-- Timer advances one game hour at a time (minutes always show :00).
local function formatClock(clockTime: number): string
	local hour24 = math.floor(clockTime % 24 + 1e-6) % 24
	local suffix = if hour24 >= 12 then "PM" else "AM"
	local hour12 = hour24 % 12
	if hour12 == 0 then
		hour12 = 12
	end
	return string.format("%d:00 %s", hour12, suffix)
end

-- Soft dayAmount for lighting blends: 1 at midday, 0 at midnight, smooth at dusk/dawn.
local function dayAmountFromClock(clockTime: number): number
	-- Peak day at 12:00, peak night at 0:00.
	-- Cosine of solar angle: noon = 1, midnight = 0.
	local angle = ((clockTime - 12) / 24) * math.pi * 2
	local solar = (math.cos(angle) + 1) * 0.5 -- 1 at noon, 0 at midnight
	-- Keep midday bright and nights clearly dark.
	return math.clamp(solar, 0, 1)
end

-- cycleOrigin: server time when the crew was created. Elapsed from origin maps
-- to cycle position so every voyage starts at 6:00 AM daytime.
-- Without origin, uses absolute server time (global fallback / lobby sync).
function DayNight.getState(serverTime: number, cycleOrigin: number?): CycleState
	local elapsed = serverTime
	if cycleOrigin ~= nil then
		elapsed = serverTime - cycleOrigin
	end

	local cycleSeconds = elapsed % DayNight.CycleSeconds
	if cycleSeconds < 0 then
		cycleSeconds += DayNight.CycleSeconds
	end

	-- Voyage day counter: every full cycle (starting at 6:00 AM) is one day.
	-- Day 1 covers the first cycle; negative elapsed (shouldn't happen) clamps to 1.
	local dayNumber = math.floor(elapsed / DayNight.CycleSeconds) + 1
	if dayNumber < 1 then
		dayNumber = 1
	end

	local phase: Phase
	local phaseAlpha: number
	local clockTime: number

	if cycleSeconds < DayNight.DaySeconds then
		phase = "Day"
		phaseAlpha = cycleSeconds / DayNight.DaySeconds
		clockTime = DayNight.DayStartHour + phaseAlpha * 12 -- 6 → 18
	else
		phase = "Night"
		phaseAlpha = (cycleSeconds - DayNight.DaySeconds) / DayNight.NightSeconds
		clockTime = DayNight.NightStartHour + phaseAlpha * 12 -- 18 → 30
		if clockTime >= 24 then
			clockTime -= 24
		end
	end

	return {
		phase = phase,
		cycleSeconds = cycleSeconds,
		phaseAlpha = phaseAlpha,
		clockTime = clockTime,
		displayTime = formatClock(clockTime),
		dayAmount = dayAmountFromClock(clockTime),
		dayNumber = dayNumber,
	}
end

-- Whole voyage day number (1-based) for a given server time / crew origin.
function DayNight.getDayNumber(serverTime: number, cycleOrigin: number?): number
	local elapsed = serverTime
	if cycleOrigin ~= nil then
		elapsed = serverTime - cycleOrigin
	end
	return math.max(1, math.floor(elapsed / DayNight.CycleSeconds) + 1)
end

function DayNight.formatClock(clockTime: number): string
	return formatClock(clockTime)
end

-- Lighting presets blended by dayAmount (1 = noon, 0 = midnight).
function DayNight.lightingFor(dayAmount: number): {
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	AtmosphereDensity: number,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	AtmosphereHaze: number,
	AtmosphereGlare: number,
	SunRaysIntensity: number,
	ColorCorrectionTint: Color3,
	ColorCorrectionBrightness: number,
	ColorCorrectionContrast: number,
	ColorCorrectionSaturation: number,
	StarCount: number,
}
	local t = math.clamp(dayAmount, 0, 1)

	local function lerpNumber(a: number, b: number): number
		return a + (b - a) * t
	end

	local function lerpColor(a: Color3, b: Color3): Color3
		return a:Lerp(b, t)
	end

	-- Night (t=0) → Day (t=1)
	return {
		Brightness = lerpNumber(0.45, 2.7),
		Ambient = lerpColor(Color3.fromRGB(28, 34, 58), Color3.fromRGB(78, 92, 98)),
		OutdoorAmbient = lerpColor(Color3.fromRGB(36, 48, 78), Color3.fromRGB(118, 128, 132)),
		FogColor = lerpColor(Color3.fromRGB(18, 28, 52), Color3.fromRGB(130, 170, 190)),
		FogStart = lerpNumber(180, 280),
		FogEnd = lerpNumber(900, 1400),
		AtmosphereDensity = lerpNumber(0.28, 0.12),
		AtmosphereColor = lerpColor(Color3.fromRGB(48, 62, 98), Color3.fromRGB(168, 198, 214)),
		AtmosphereDecay = lerpColor(Color3.fromRGB(12, 18, 42), Color3.fromRGB(42, 78, 108)),
		AtmosphereHaze = lerpNumber(1.1, 0.55),
		AtmosphereGlare = lerpNumber(0, 0.08),
		SunRaysIntensity = lerpNumber(0, 0.045),
		ColorCorrectionTint = lerpColor(Color3.fromRGB(170, 190, 230), Color3.fromRGB(255, 246, 236)),
		ColorCorrectionBrightness = lerpNumber(-0.06, 0.02),
		ColorCorrectionContrast = lerpNumber(0.04, 0.06),
		ColorCorrectionSaturation = lerpNumber(-0.08, 0.05),
		StarCount = math.floor(lerpNumber(3000, 400) + 0.5),
	}
end

return DayNight
