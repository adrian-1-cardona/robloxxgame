-- Publishes day / night cycle state from server time so clients stay in sync.
-- Visual lighting is client-owned: lobby stays daytime; gameplay follows each
-- crew's cycleOrigin (voyage always begins at 9:00 AM). Attributes here are a
-- global fallback for debugging — clients prefer ClockHUD.getGameplayState().

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

local function publishState(state: DayNight.CycleState)
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

	publishState(DayNight.getState(Workspace:GetServerTimeNow()))

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		publishState(DayNight.getState(Workspace:GetServerTimeNow()))
	end)

	print("[SurviveAtSea] Day/night sync started — 5 min day / 5 min night, crews start at 9:00 AM")
end

return DayNightService
