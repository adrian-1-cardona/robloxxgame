-- Client helm: while locked at the wheel, stream camera/head look to the server
-- and show a platform-aware leave tip. Mount/dismount is server-authoritative.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlatformInput = require(script.Parent:WaitForChild("PlatformInput"))

local HelmController = {}

local player = Players.LocalPlayer
local helming = false
local tipGui: ScreenGui? = nil
local sendAccum = 0
local heartbeatConn: RBXScriptConnection? = nil
local jumpConn: RBXScriptConnection? = nil
local inputConn: RBXScriptConnection? = nil
local HelmDismountRemote: RemoteEvent? = nil

-- Leave mapping: JumpRequest covers PC / touch jump / console A.
-- ButtonB is the console/VR "back" affordance so players aren't stuck without a jump bind.
local DISMOUNT_GAMEPAD = {
	[Enum.KeyCode.ButtonB] = true,
}

local function destroyTip()
	if tipGui then
		tipGui:Destroy()
		tipGui = nil
	end
end

local function leaveHintText(): string
	local kind = PlatformInput.getDeviceKind()
	if kind == "Console" then
		return "Look to steer  ·  Press B (or Jump) to leave the helm"
	elseif kind == "VR" then
		return "Look to steer  ·  Jump / B to leave the helm"
	elseif kind == "Phone" or kind == "Tablet" then
		return "Look to steer  ·  Tap Jump to leave the helm"
	end
	return "Look to steer  ·  Jump to leave the helm"
end

local function showTip()
	destroyTip()
	local scale = PlatformInput.scaleForDevice()
	local kind = PlatformInput.getDeviceKind()

	local gui = Instance.new("ScreenGui")
	gui.Name = "HelmTip"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- VR / console need the tip in screen space; laser still hits ClickablePrompt on the wheel
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Sit above mobile jump / thumb controls; console/VR get a larger scaled bar
	local bottomPad = if kind == "Phone" or kind == "Tablet" then 88 elseif kind == "VR" then 56 else 40

	local label = Instance.new("TextLabel")
	label.Name = "Tip"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -bottomPad)
	label.Size = UDim2.fromOffset(math.floor(480 * scale), math.floor(54 * scale))
	label.BackgroundColor3 = Color3.fromRGB(10, 28, 42)
	label.BackgroundTransparency = 0.15
	label.Font = Config.UI.Font
	label.Text = leaveHintText()
	label.TextColor3 = Config.Theme.Foam
	label.TextScaled = true
	label.Parent = gui

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MinTextSize = 12
	sizeConstraint.MaxTextSize = if kind == "Console" or kind == "VR" then 26 else 20
	sizeConstraint.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Theme.UIAccent
	stroke.Thickness = 1.2
	stroke.Transparency = 0.35
	stroke.Parent = label

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = label

	tipGui = gui
end

local function currentLook(): Vector3
	-- VR: prefer headset forward so look-steer tracks the head, not a flat camera pivot
	if VRService.VREnabled then
		local ok, headCf = pcall(function()
			return VRService:GetUserCFrame(Enum.UserCFrame.Head)
		end)
		local cam = workspace.CurrentCamera
		if ok and headCf and cam then
			local worldHead = cam.CFrame * headCf
			return worldHead.LookVector
		end
	end

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

local function requestDismount()
	if helming and HelmDismountRemote then
		HelmDismountRemote:FireServer()
	end
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
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
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

	-- Jump unlocks on PC / mobile jump button / console A (JumpRequest)
	jumpConn = UserInputService.JumpRequest:Connect(function()
		requestDismount()
	end)

	-- Console B + VR controller buttons (JumpRequest is unreliable in VR)
	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not helming then
			return
		end
		if DISMOUNT_GAMEPAD[input.KeyCode] then
			requestDismount()
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
