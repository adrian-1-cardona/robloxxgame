-- Client helm: while locked at the wheel, stream camera look to the server
-- and show a jump-to-exit tip. Mount/dismount is entirely server-authoritative.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HelmController = {}

local player = Players.LocalPlayer
local helming = false
local tipGui: ScreenGui? = nil
local sendAccum = 0
local heartbeatConn: RBXScriptConnection? = nil
local jumpConn: RBXScriptConnection? = nil
local HelmDismountRemote: RemoteEvent? = nil

local function destroyTip()
	if tipGui then
		tipGui:Destroy()
		tipGui = nil
	end
end

local function showTip()
	destroyTip()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HelmTip"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Tip"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -36)
	label.Size = UDim2.fromOffset(420, 40)
	label.BackgroundColor3 = Color3.fromRGB(10, 28, 42)
	label.BackgroundTransparency = 0.2
	label.Font = Config.UI.Font
	label.TextSize = 18
	label.TextColor3 = Config.Theme.Foam
	label.Text = "Look to steer the raft  ·  Jump to leave the helm"
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Theme.UIAccent
	stroke.Thickness = 1.2
	stroke.Transparency = 0.35
	stroke.Parent = label

	tipGui = gui
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

local function stopSending()
	helming = false
	sendAccum = 0
	destroyTip()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if jumpConn then
		jumpConn:Disconnect()
		jumpConn = nil
	end
end

local function startSending(HelmLook: RemoteEvent)
	if helming then
		return
	end
	helming = true
	showTip()

	local interval = 1 / math.max(1, Config.Helm.LookSendHz)
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not helming then
			return
		end
		sendAccum += dt
		if sendAccum < interval then
			return
		end
		sendAccum = 0
		HelmLook:FireServer(currentLook())
	end)

	-- Jump up unlocks — fire before the server stand-snap eats the jump
	jumpConn = UserInputService.JumpRequest:Connect(function()
		if helming and HelmDismountRemote then
			HelmDismountRemote:FireServer()
		end
	end)
end

function HelmController.start()
	local HelmLook = Remotes.waitFor("HelmLook")
	local HelmState = Remotes.waitFor("HelmState")
	local HelmDismount = Remotes.waitFor("HelmDismount")
	assert(HelmLook:IsA("RemoteEvent") and HelmState:IsA("RemoteEvent") and HelmDismount:IsA("RemoteEvent"))
	HelmDismountRemote = HelmDismount

	HelmState.OnClientEvent:Connect(function(active: boolean)
		if active then
			startSending(HelmLook)
		else
			stopSending()
		end
	end)

	player.CharacterAdded:Connect(function()
		if not helming then
			destroyTip()
		end
	end)
end

return HelmController
