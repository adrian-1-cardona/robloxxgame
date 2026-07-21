-- Survive at Sea · Client bootstrap
-- If Rojo didn't sync the Workspace map (common on existing places like "dnd"),
-- this client builds the boarding dock locally so you still see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local LobbyUI = require(script:WaitForChild("Lobby"):WaitForChild("LobbyUI"))

print(`[SurviveAtSea] Client hello — welcome aboard {Config.GameName}`)

-- Prefer a server-replicated lobby; otherwise build one here.
local lobby = Workspace:FindFirstChild("SurviveAtSeaLobby")
if not lobby then
	lobby = Workspace:WaitForChild("SurviveAtSeaLobby", 2)
end
if not lobby then
	print("[SurviveAtSea] No lobby in Workspace yet — building on client")
	lobby = LobbyWorld.ensure()
else
	print("[SurviveAtSea] Found Workspace.SurviveAtSeaLobby")
end

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

task.spawn(function()
	local openEvent = ReplicatedStorage:FindFirstChild("SurviveAtSeaOpenCreate")
	if not (openEvent and openEvent:IsA("BindableEvent")) then
		openEvent = Instance.new("BindableEvent")
		openEvent.Name = "SurviveAtSeaOpenCreate"
		openEvent.Parent = ReplicatedStorage
	end

	local portals = lobby:WaitForChild("Portals", 5)
	if not portals then
		warn("[SurviveAtSea] Portals folder missing")
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

	print("[SurviveAtSea] Portals wired:", #portals:GetChildren())
end)

pcall(function()
	local Lighting = game:GetService("Lighting")
	Lighting.Brightness = 3
	Lighting.FogStart = 200
	Lighting.FogEnd = 800
	Lighting.ClockTime = 16.5
end)
