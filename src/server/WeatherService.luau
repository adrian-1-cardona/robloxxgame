-- Authoritative cosmetic weather schedule for the open sea.
-- Publishes Workspace attributes; clients apply FX only while in a crew.
-- Does not touch lobby geometry, portals, or LobbyWorld.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Weather = require(Shared:WaitForChild("Weather"))

local WeatherService = {}

local started = false
local bootTime = 0
local rng = Random.new()

local current: Weather.Mode = "Sunny"
local nextMode: Weather.Mode = "Sunny"
local phase: "Hold" | "Transition" = "Hold"
local phaseElapsed = 0
local phaseDuration = Weather.MinHoldSeconds
local nextLightningAt: number? = nil

local function publish(state: Weather.WeatherState)
	Workspace:SetAttribute(Weather.ATTR_FROM, state.fromMode)
	Workspace:SetAttribute(Weather.ATTR_TO, state.toMode)
	Workspace:SetAttribute(Weather.ATTR_BLEND, state.blend)
	Workspace:SetAttribute(Weather.ATTR_RAIN, state.rain)
	Workspace:SetAttribute(Weather.ATTR_CLOUD, state.cloud)
	Workspace:SetAttribute(Weather.ATTR_THUNDER, state.thunderChance)
	Workspace:SetAttribute(Weather.ATTR_SUN, state.sun)
	Workspace:SetAttribute(Weather.ATTR_VOYAGE, state.voyageAge)
end

local function currentState(): Weather.WeatherState
	local voyage = Weather.voyageAge(Workspace:GetServerTimeNow() - bootTime)
	if phase == "Hold" then
		return Weather.makeState(current, current, 1, voyage)
	end
	local blend = if phaseDuration > 0 then phaseElapsed / phaseDuration else 1
	return Weather.makeState(current, nextMode, blend, voyage)
end

local function scheduleLightning(state: Weather.WeatherState, now: number)
	local mean = Weather.lightningInterval(state.thunderChance)
	if not mean then
		nextLightningAt = nil
		return
	end
	-- Jitter around the mean so strikes feel organic.
	local gap = rng:NextNumber(mean * 0.55, mean * 1.45)
	nextLightningAt = now + gap
end

local function maybeStrike(state: Weather.WeatherState, now: number)
	if state.thunderChance < 0.12 then
		nextLightningAt = nil
		return
	end
	if nextLightningAt == nil then
		scheduleLightning(state, now)
		return
	end
	if now < nextLightningAt then
		return
	end
	-- Cosmetic flash marker — clients render local lightning only at sea.
	Workspace:SetAttribute(Weather.ATTR_FLASH, now)
	scheduleLightning(state, now)
end

local function beginHold(mode: Weather.Mode)
	current = mode
	nextMode = mode
	phase = "Hold"
	phaseElapsed = 0
	phaseDuration = Weather.holdDuration(rng)
end

local function beginTransition(fromMode: Weather.Mode, toMode: Weather.Mode, voyageAge: number)
	current = fromMode
	nextMode = toMode
	phase = "Transition"
	phaseElapsed = 0
	phaseDuration = Weather.transitionDuration(rng)
	-- Slightly longer fades when entering/leaving storms so they feel heavier.
	if toMode == "Thunderstorm" or fromMode == "Thunderstorm" then
		phaseDuration = math.max(phaseDuration, Weather.MaxTransitionSeconds * 0.85)
	end
	-- Prefer settling into something else rather than looping the same label.
	if fromMode == toMode then
		nextMode = Weather.pickNext(rng, fromMode, voyageAge)
	end
end

function WeatherService.start()
	if started then
		return
	end
	started = true
	bootTime = Workspace:GetServerTimeNow()

	-- Open on a calm sea; weather builds gradually as the session ages.
	beginHold("Sunny")
	publish(currentState())

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		phaseElapsed += dt

		local now = Workspace:GetServerTimeNow()
		local voyage = Weather.voyageAge(now - bootTime)

		if phase == "Hold" then
			if phaseElapsed >= phaseDuration then
				local pick = Weather.pickNext(rng, current, voyage)
				if pick == current then
					-- Rare same-mode "refresh" — just hold again so we don't thrash.
					beginHold(current)
				else
					beginTransition(current, pick, voyage)
				end
			end
		elseif phase == "Transition" then
			if phaseElapsed >= phaseDuration then
				beginHold(nextMode)
			end
		end

		local state = currentState()
		maybeStrike(state, now)

		-- Publish often enough for smooth client blends without flooding.
		if accum >= 0.2 then
			accum = 0
			publish(state)
		end
	end)

	print("[SurviveAtSea] Weather service started — gradual open-sea atmosphere (cosmetic)")
end

return WeatherService
