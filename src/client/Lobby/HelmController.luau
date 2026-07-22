-- Client helm: while locked at the wheel, stream look + throttle to the server.
-- Drive: W/S (computer), left-stick Y (console), small ↑/↓ arrows (mobile).
-- Mount/dismount is server-authoritative.

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
local arrowsGui: ScreenGui? = nil
local sendAccum = 0
local throttleSendAccum = 0
local lastSentThrottle = 0
local heartbeatConn: RBXScriptConnection? = nil
local jumpConn: RBXScriptConnection? = nil
local inputBeganConn: RBXScriptConnection? = nil
local inputEndedConn: RBXScriptConnection? = nil
local HelmDismountRemote: RemoteEvent? = nil
local HelmThrottleRemote: RemoteEvent? = nil

-- Keyboard / touch button holds
local forwardHeld = false
local backwardHeld = false
-- Touch arrow buttons (mobile)
local mobileForward = false
local mobileBackward = false

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

local function destroyArrows()
	if arrowsGui then
		arrowsGui:Destroy()
		arrowsGui = nil
	end
	mobileForward = false
	mobileBackward = false
end

local function leaveHintText(): string
	local kind = PlatformInput.getDeviceKind()
	if kind == "Console" then
		return "Look to steer  ·  Stick forward/back to sail  ·  B / Jump to leave"
	elseif kind == "VR" then
		return "Look to steer  ·  Stick to sail  ·  Jump / B to leave"
	elseif kind == "Phone" or kind == "Tablet" then
		return "Look to steer  ·  Arrows to sail  ·  Jump to leave"
	end
	return "Look to steer  ·  Hold W / S to sail  ·  Jump to leave"
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
	label.Size = UDim2.fromOffset(math.floor(520 * scale), math.floor(54 * scale))
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

local function bindArrowHold(button: GuiButton, setHeld: (boolean) -> ())
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			setHeld(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			setHeld(false)
		end
	end)
	button.MouseButton1Up:Connect(function()
		setHeld(false)
	end)
end

local function showMobileArrows()
	destroyArrows()
	local kind = PlatformInput.getDeviceKind()
	if kind ~= "Phone" and kind ~= "Tablet" then
		return
	end

	local scale = PlatformInput.scaleForDevice()
	local size = math.floor(46 * scale)
	local gap = math.floor(8 * scale)

	local gui = Instance.new("ScreenGui")
	gui.Name = "HelmDriveArrows"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 41
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Small stack near bottom-right, above the default jump button
	local stack = Instance.new("Frame")
	stack.Name = "ArrowStack"
	stack.AnchorPoint = Vector2.new(1, 1)
	stack.Position = UDim2.new(1, -18, 1, -160)
	stack.Size = UDim2.fromOffset(size, size * 2 + gap)
	stack.BackgroundTransparency = 1
	stack.Parent = gui

	local function makeArrow(name: string, text: string, yOffset: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.AnchorPoint = Vector2.new(0.5, 0)
		btn.Position = UDim2.new(0.5, 0, 0, yOffset)
		btn.Size = UDim2.fromOffset(size, size)
		btn.BackgroundColor3 = Color3.fromRGB(10, 28, 42)
		btn.BackgroundTransparency = 0.12
		btn.BorderSizePixel = 0
		btn.Font = Config.UI.Font
		btn.Text = text
		btn.TextColor3 = Config.Theme.Foam
		btn.TextScaled = true
		btn.AutoButtonColor = true
		btn.Parent = stack

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = Config.Theme.UIAccent
		stroke.Thickness = 1.1
		stroke.Transparency = 0.3
		stroke.Parent = btn

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 4)
		pad.PaddingTop = UDim.new(0, 2)
		pad.PaddingBottom = UDim.new(0, 2)
		pad.Parent = btn

		local sizeConstraint = Instance.new("UITextSizeConstraint")
		sizeConstraint.MinTextSize = 14
		sizeConstraint.MaxTextSize = 28
		sizeConstraint.Parent = btn

		return btn
	end

	local up = makeArrow("Forward", "▲", 0)
	local down = makeArrow("Backward", "▼", size + gap)
	bindArrowHold(up, function(held)
		mobileForward = held
	end)
	bindArrowHold(down, function(held)
		mobileBackward = held
	end)

	arrowsGui = gui
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

local function readStickThrottle(): number
	local deadzone = Config.Helm.StickDeadzone
	local best = 0
	local bestMag = 0
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		local ok, states = pcall(function()
			return UserInputService:GetGamepadState(gamepad)
		end)
		if not ok or not states then
			continue
		end
		for _, input in states do
			-- Left stick Y: up = forward (+), down = reverse (−). Roblox Thumbstick Y is up-positive.
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local y = input.Position.Y
				local mag = math.abs(y)
				if mag > deadzone and mag > bestMag then
					bestMag = mag
					-- Remap past deadzone into -1..1
					local sign = if y > 0 then 1 else -1
					best = sign * math.clamp((mag - deadzone) / (1 - deadzone), 0, 1)
				end
			end
		end
	end
	return best
end

local function keyboardThrottle(): number
	-- Poll keys every tick so focus/chat glitches can't leave us stuck at 0
	local forward = forwardHeld
		or UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.Up)
	local backward = backwardHeld
		or UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.Down)
	local digital = 0
	if forward then
		digital += 1
	end
	if backward then
		digital -= 1
	end
	return math.clamp(digital, -1, 1)
end

local function currentThrottle(): number
	-- Digital holds (keyboard W/S or mobile arrows) win when pressed
	local digital = keyboardThrottle()
	if mobileForward then
		digital = math.clamp(digital + 1, -1, 1)
	end
	if mobileBackward then
		digital = math.clamp(digital - 1, -1, 1)
	end
	if digital ~= 0 then
		return digital
	end

	-- Console / gamepad analog when no digital hold
	local kind = PlatformInput.getDeviceKind()
	if kind == "Console" or kind == "VR" or UserInputService.GamepadEnabled then
		return readStickThrottle()
	end

	return 0
end

local function requestDismount()
	if helming and HelmDismountRemote then
		HelmDismountRemote:FireServer()
	end
end

local function pushThrottle(force: boolean?)
	if not (helming and HelmThrottleRemote) then
		return
	end
	local throttle = currentThrottle()
	if force or math.abs(throttle - lastSentThrottle) > 0.02 then
		lastSentThrottle = throttle
		HelmThrottleRemote:FireServer(throttle)
	end
end

local function stopSending()
	helming = false
	sendAccum = 0
	throttleSendAccum = 0
	lastSentThrottle = 0
	forwardHeld = false
	backwardHeld = false
	destroyTip()
	destroyArrows()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if jumpConn then
		jumpConn:Disconnect()
		jumpConn = nil
	end
	if inputBeganConn then
		inputBeganConn:Disconnect()
		inputBeganConn = nil
	end
	if inputEndedConn then
		inputEndedConn:Disconnect()
		inputEndedConn = nil
	end
end

local function startSending(HelmLook: RemoteEvent)
	if helming then
		return
	end
	helming = true
	forwardHeld = false
	backwardHeld = false
	lastSentThrottle = 0
	showTip()
	showMobileArrows()
	-- Idle at mount — tell server throttle is 0 so the raft doesn't keep old state
	pushThrottle(true)

	local lookInterval = 1 / math.max(1, Config.Helm.LookSendHz)
	local throttleInterval = 1 / math.max(1, Config.Helm.ThrottleSendHz)
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not helming then
			return
		end
		sendAccum += dt
		throttleSendAccum += dt
		if sendAccum >= lookInterval then
			sendAccum = 0
			HelmLook:FireServer(currentLook())
		end
		if throttleSendAccum >= throttleInterval then
			throttleSendAccum = 0
			pushThrottle(false)
		end
	end)

	-- Jump unlocks on PC / mobile jump button / console A (JumpRequest)
	jumpConn = UserInputService.JumpRequest:Connect(function()
		requestDismount()
	end)

	inputBeganConn = UserInputService.InputBegan:Connect(function(input, processed)
		if not helming then
			return
		end
		if DISMOUNT_GAMEPAD[input.KeyCode] and not processed then
			requestDismount()
			return
		end
		-- W / S drive even if chat/processed — helm owns WalkSpeed already
		if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
			forwardHeld = true
			pushThrottle(true)
		elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
			backwardHeld = true
			pushThrottle(true)
		end
	end)

	inputEndedConn = UserInputService.InputEnded:Connect(function(input, _processed)
		if not helming then
			return
		end
		if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
			forwardHeld = false
			pushThrottle(true)
		elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
			backwardHeld = false
			pushThrottle(true)
		end
	end)
end

function HelmController.start()
	local HelmLook = Remotes.waitFor("HelmLook")
	local HelmThrottle = Remotes.waitFor("HelmThrottle")
	local HelmState = Remotes.waitFor("HelmState")
	local HelmDismount = Remotes.waitFor("HelmDismount")
	assert(
		HelmLook:IsA("RemoteEvent")
			and HelmThrottle:IsA("RemoteEvent")
			and HelmState:IsA("RemoteEvent")
			and HelmDismount:IsA("RemoteEvent")
	)
	HelmDismountRemote = HelmDismount
	HelmThrottleRemote = HelmThrottle

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
			destroyArrows()
		end
	end)
end

return HelmController
