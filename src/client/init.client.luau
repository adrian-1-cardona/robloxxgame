-- Survive at Sea · Client bootstrap

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyUI = require(script:WaitForChild("Lobby"):WaitForChild("LobbyUI"))

print(`[SurviveAtSea] Client hello — welcome aboard {Config.GameName}`)
LobbyUI.start()

-- Point the camera toward the boarding portals once the dock streams in.
task.spawn(function()
	local lobby = Workspace:WaitForChild("SurviveAtSeaLobby", 30)
	if not lobby then
		warn("[SurviveAtSea] Lobby folder not found — is the server script running?")
		return
	end

	local player = Players.LocalPlayer
	local function facePortals(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 5)
		local humanoid = character:WaitForChild("Humanoid", 5)
		local camera = Workspace.CurrentCamera
		if not (root and humanoid and camera) then
			return
		end
		-- Look down the pier toward portals (positive Z)
		root.CFrame = CFrame.new(root.Position, root.Position + Vector3.new(0, 0, 20))
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Custom
	end

	if player.Character then
		facePortals(player.Character)
	end
	player.CharacterAdded:Connect(facePortals)

	print("[SurviveAtSea] Dock streamed — portals ahead!")
end)
