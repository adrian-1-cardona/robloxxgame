-- Survive at Sea · Client bootstrap
-- Builds the dock locally if Rojo didn't sync Workspace (common with existing places).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local LobbyUI = require(script:WaitForChild("Lobby"):WaitForChild("LobbyUI"))

print(`[SurviveAtSea] Client hello — welcome aboard {Config.GameName}`)

local lobby = LobbyWorld.ensure()
LobbyUI.start()

local player = Players.LocalPlayer

local function seat(character: Model)
	task.defer(function()
		LobbyWorld.seatCharacter(character)
	end)
end

if player.Character then
	seat(player.Character)
end
player.CharacterAdded:Connect(seat)

-- Wire portal prompts to open the create-crew panel
task.spawn(function()
	local openEvent = ReplicatedStorage:WaitForChild("SurviveAtSeaOpenCreate", 5)
	if not openEvent or not openEvent:IsA("BindableEvent") then
		openEvent = Instance.new("BindableEvent")
		openEvent.Name = "SurviveAtSeaOpenCreate"
		openEvent.Parent = ReplicatedStorage
	end

	local portals = lobby:WaitForChild("Portals", 5)
	if not portals then
		warn("[SurviveAtSea] No Portals folder after LobbyWorld.ensure")
		return
	end

	for _, model in portals:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local indexValue = model:FindFirstChild("PortalIndex")
		local promptAnchor = model:FindFirstChild("PromptAnchor")
		local prompt = promptAnchor and promptAnchor:FindFirstChild("BoardPrompt")
		if not (indexValue and indexValue:IsA("IntValue") and prompt and prompt:IsA("ProximityPrompt")) then
			continue
		end

		local portalIndex = indexValue.Value
		prompt.Triggered:Connect(function()
			(openEvent :: BindableEvent):Fire(portalIndex)
		end)
	end

	print("[SurviveAtSea] Client dock live —", #portals:GetChildren(), "portals")
end)

pcall(function()
	local Lighting = game:GetService("Lighting")
	Lighting.Brightness = 3
	Lighting.FogStart = 200
	Lighting.FogEnd = 800
	Lighting.ClockTime = 16.5
end)
