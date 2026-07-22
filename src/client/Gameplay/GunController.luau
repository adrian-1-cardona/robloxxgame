-- Client flintlock: while the Survive gun tool is equipped, click / tap to fire.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local GunController = {}

local player = Players.LocalPlayer
local shootRemote: RemoteEvent? = nil
local toolConns: { RBXScriptConnection } = {}

local function clearToolConns()
	for _, conn in toolConns do
		conn:Disconnect()
	end
	table.clear(toolConns)
end

local function currentLook(): Vector3
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.LookVector
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

local function bindTool(tool: Tool)
	if tool:GetAttribute("SurviveGun") ~= true then
		return
	end
	table.insert(
		toolConns,
		tool.Activated:Connect(function()
			if shootRemote then
				shootRemote:FireServer(currentLook())
			end
		end)
	)
end

local function watchCharacter(character: Model)
	clearToolConns()
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
	table.insert(
		toolConns,
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				bindTool(child)
			end
		end)
	)
end

function GunController.start()
	local remote = Remotes.waitFor("ShootGun")
	assert(remote:IsA("RemoteEvent"))
	shootRemote = remote

	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

return GunController
