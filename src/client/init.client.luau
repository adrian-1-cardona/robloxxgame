-- Survive at Sea · Client bootstrap

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyUI = require(script:WaitForChild("Lobby"):WaitForChild("LobbyUI"))

print(`[SurviveAtSea] Client hello — welcome aboard {Config.GameName}`)
LobbyUI.start()

task.spawn(function()
	local lobby = Workspace:WaitForChild("SurviveAtSeaLobby", 10)
	if not lobby then
		warn("[SurviveAtSea] SurviveAtSeaLobby not in Workspace — reconnect Rojo / stop+play again")
		return
	end

	local player = Players.LocalPlayer
	local function facePortals(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if not root or not root:IsA("BasePart") then
			return
		end
		root.CFrame = CFrame.new(root.Position, root.Position + Vector3.new(0, 0, 40))
	end

	if player.Character then
		facePortals(player.Character)
	end
	player.CharacterAdded:Connect(facePortals)

	print("[SurviveAtSea] Dock visible — walk toward the neon portals!")
end)
