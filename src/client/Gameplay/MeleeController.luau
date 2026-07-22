-- Melee input for equipped Club: right-click (PC), RT / ButtonR2 (console), tap Attack (mobile).
-- Drop uses default Roblox backpack (Backspace / Xbox X / backpack drop) via CanBeDropped.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlatformInput = require(script.Parent.Parent:WaitForChild("Lobby"):WaitForChild("PlatformInput"))

-- Optional: DragController may load after us; lazy-require when swinging
local function isDragBusy(): boolean
	local drag = script.Parent:FindFirstChild("DragController")
	if not drag then
		return false
	end
	local ok, mod = pcall(require, drag)
	if not ok or typeof(mod) ~= "table" then
		return false
	end
	if mod.isBusy then
		return true
	end
	if typeof(mod.isLookingAtLoot) == "function" and mod.isLookingAtLoot() then
		return true
	end
	return false
end

local MeleeController = {}

local player = Players.LocalPlayer
local MeleeAttack: RemoteEvent? = nil
local attackGui: ScreenGui? = nil
local lastClientSwing = 0
local equippedTool: Tool? = nil
local swinging = false

local function isMeleeTool(tool: Instance?): boolean
	return tool ~= nil and tool:IsA("Tool") and tool:GetAttribute("MeleeWeapon") == true
end

local function destroyAttackButton()
	if attackGui then
		attackGui:Destroy()
		attackGui = nil
	end
end

local function showMobileAttackButton()
	destroyAttackButton()
	local kind = PlatformInput.getDeviceKind()
	if kind ~= "Phone" and kind ~= "Tablet" then
		return
	end
	if not equippedTool then
		return
	end

	local scale = PlatformInput.scaleForDevice()
	local size = math.floor(64 * scale)

	local gui = Instance.new("ScreenGui")
	gui.Name = "MeleeAttackButton"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 35
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.Name = "Attack"
	btn.AnchorPoint = Vector2.new(1, 1)
	-- Left of jump; avoids helm arrows on the far right
	btn.Position = UDim2.new(1, -96, 1, -88)
	btn.Size = UDim2.fromOffset(size, size)
	btn.BackgroundColor3 = Color3.fromRGB(72, 48, 28)
	btn.BackgroundTransparency = 0.08
	btn.BorderSizePixel = 0
	btn.Font = Config.UI.Font
	btn.Text = "ATK"
	btn.TextColor3 = Config.Theme.Foam
	btn.TextScaled = true
	btn.AutoButtonColor = true
	btn.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Theme.Lantern
	stroke.Thickness = 1.4
	stroke.Transparency = 0.25
	stroke.Parent = btn

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MinTextSize = 12
	sizeConstraint.MaxTextSize = 22
	sizeConstraint.Parent = btn

	btn.MouseButton1Click:Connect(function()
		MeleeController.requestSwing()
	end)

	attackGui = gui
end

local function playLocalSwing(tool: Tool)
	if swinging then
		return
	end
	swinging = true

	local gripWas = tool.Grip
	local swingGrip = gripWas * CFrame.Angles(math.rad(-55), math.rad(15), math.rad(-25))
	tool.Grip = swingGrip

	local head = tool:FindFirstChild("ClubHead")
	if head and head:IsA("BasePart") then
		local flash = Instance.new("PointLight")
		flash.Brightness = 0.6
		flash.Range = 6
		flash.Color = Color3.fromRGB(255, 210, 140)
		flash.Parent = head
		task.delay(0.12, function()
			if flash.Parent then
				flash:Destroy()
			end
		end)
	end

	-- Animate grip back
	task.spawn(function()
		local duration = Config.Club.SwingDuration
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local alpha = (os.clock() - t0) / duration
			-- Ease out back toward rest
			local eased = 1 - (1 - alpha) * (1 - alpha)
			tool.Grip = gripWas:Lerp(swingGrip, 1 - eased)
			task.wait()
		end
		tool.Grip = gripWas
		swinging = false
	end)
end

function MeleeController.requestSwing()
	if not equippedTool or not MeleeAttack then
		return
	end
	if isDragBusy() then
		return
	end
	local now = os.clock()
	if now - lastClientSwing < Config.Club.SwingCooldown * 0.85 then
		return
	end
	lastClientSwing = now
	playLocalSwing(equippedTool)
	MeleeAttack:FireServer()
end

local function onEquipped(tool: Tool)
	equippedTool = tool
	showMobileAttackButton()
end

local function onUnequipped(tool: Tool)
	if equippedTool == tool then
		equippedTool = nil
		destroyAttackButton()
		swinging = false
	end
end

local function hookTool(tool: Tool)
	if not isMeleeTool(tool) then
		return
	end
	tool.Equipped:Connect(function()
		onEquipped(tool)
	end)
	tool.Unequipped:Connect(function()
		onUnequipped(tool)
	end)
	if tool.Parent == player.Character then
		onEquipped(tool)
	end
end

local function scanContainers()
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then
				hookTool(child)
			end
		end
	end
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				hookTool(child)
			end
		end
	end
end

local function hookCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			hookTool(child)
		end
	end
end

function MeleeController.start()
	local attack = Remotes.waitFor("MeleeAttack")
	local swingFx = Remotes.waitFor("MeleeSwingFx")
	assert(attack:IsA("RemoteEvent") and swingFx:IsA("RemoteEvent"))
	MeleeAttack = attack

	-- Other players' swings: brief toast-free cue via their held tool grip if we can find it
	swingFx.OnClientEvent:Connect(function(userId: number, _toolName: string)
		if typeof(userId) ~= "number" or userId == player.UserId then
			return
		end
		local other = Players:GetPlayerByUserId(userId)
		local character = other and other.Character
		if not character then
			return
		end
		for _, child in character:GetChildren() do
			if isMeleeTool(child) then
				local gripWas = (child :: Tool).Grip
				;(child :: Tool).Grip = gripWas * CFrame.Angles(math.rad(-50), 0, math.rad(-20))
				task.delay(Config.Club.SwingDuration, function()
					if child.Parent then
						(child :: Tool).Grip = gripWas
					end
				end)
				break
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if not equippedTool then
			return
		end
		-- Don't swing when dragging loot or aiming at a draggable prop (hold RT / RMB)
		if isDragBusy() then
			return
		end

		-- PC: right mouse button
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			MeleeController.requestSwing()
			return
		end

		-- Console / gamepad: right trigger
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			MeleeController.requestSwing()
			return
		end
	end)

	local function onBackpack(backpack: Instance)
		backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				hookTool(child)
			end
		end)
	end

	if player:FindFirstChild("Backpack") then
		onBackpack(player.Backpack)
	end
	player.ChildAdded:Connect(function(child)
		if child.Name == "Backpack" then
			onBackpack(child)
		end
	end)

	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		equippedTool = nil
		destroyAttackButton()
		swinging = false
		hookCharacter(character)
		task.defer(scanContainers)
	end)

	scanContainers()
end

return MeleeController
