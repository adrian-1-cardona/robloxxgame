-- Client ranged-weapon input: while any ranged weapon (Ranged attribute) or the legacy
-- flintlock (SurviveGun) is equipped, tap / click fires; R (or a mobile button) reloads.
-- Firing an empty magazine auto-reloads so gamepad / touch players aren't stuck.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlatformInput = require(script.Parent.Parent:WaitForChild("Lobby"):WaitForChild("PlatformInput"))

local GunController = {}

local player = Players.LocalPlayer
local shootRemote: RemoteEvent? = nil
local reloadRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil
local toolConns: { RBXScriptConnection } = {}
local equippedRanged: Tool? = nil
local reloadGui: ScreenGui? = nil

local function isRanged(tool: Instance?): boolean
	return tool ~= nil
		and tool:IsA("Tool")
		and (tool:GetAttribute("Ranged") == true or tool:GetAttribute("SurviveGun") == true)
end

local function clearToolConns()
	for _, conn in toolConns do
		conn:Disconnect()
	end
	table.clear(toolConns)
end

local function currentLook(): Vector3
	local cam = Workspace.CurrentCamera
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

local function fire(tool: Tool)
	-- Auto-reload an empty mag instead of dry-firing.
	if tool:GetAttribute("Ammo") ~= nil then
		local loaded = tool:GetAttribute("Loaded")
		if typeof(loaded) == "number" and loaded <= 0 then
			if reloadRemote then
				reloadRemote:FireServer()
			end
			return
		end
	end
	if shootRemote then
		shootRemote:FireServer(currentLook())
	end
end

local function destroyReloadButton()
	if reloadGui then
		reloadGui:Destroy()
		reloadGui = nil
	end
end

local function showReloadButton()
	destroyReloadButton()
	local kind = PlatformInput.getDeviceKind()
	if kind ~= "Phone" and kind ~= "Tablet" then
		return
	end
	if not equippedRanged then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ReloadButton"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 35
	gui.Parent = player:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.Name = "Reload"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -96, 1, -160)
	btn.Size = UDim2.fromOffset(64, 64)
	btn.BackgroundColor3 = Color3.fromRGB(40, 56, 84)
	btn.BackgroundTransparency = 0.08
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.Text = "RELOAD"
	btn.TextColor3 = Color3.fromRGB(220, 235, 245)
	btn.TextScaled = true
	btn.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = btn
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = btn

	btn.MouseButton1Click:Connect(function()
		if reloadRemote then
			reloadRemote:FireServer()
		end
	end)

	reloadGui = gui
end

local function bindTool(tool: Tool)
	if not isRanged(tool) then
		return
	end
	table.insert(
		toolConns,
		tool.Activated:Connect(function()
			fire(tool)
		end)
	)
	table.insert(
		toolConns,
		tool.Equipped:Connect(function()
			equippedRanged = tool
			showReloadButton()
		end)
	)
	table.insert(
		toolConns,
		tool.Unequipped:Connect(function()
			if equippedRanged == tool then
				equippedRanged = nil
				destroyReloadButton()
			end
		end)
	)
	if tool.Parent == player.Character then
		equippedRanged = tool
		showReloadButton()
	end
end

local function watchCharacter(character: Model)
	clearToolConns()
	equippedRanged = nil
	destroyReloadButton()
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
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		table.insert(
			toolConns,
			backpack.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					bindTool(child)
				end
			end)
		)
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then
				bindTool(child)
			end
		end
	end
end

-- Lightweight tracer + muzzle flash so shots read clearly for everyone.
local function playShotFx(origin: Vector3, dir: Vector3)
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 220, 140)
	beam.Size = Vector3.new(0.12, 0.12, 40)
	beam.CFrame = CFrame.lookAt(origin + dir * 20, origin + dir * 40)
	beam.Parent = Workspace
	Debris:AddItem(beam, 0.06)

	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 90)
	flash.Size = Vector3.new(0.8, 0.8, 0.8)
	flash.CFrame = CFrame.new(origin + dir * 1.5)
	flash.Parent = Workspace
	Debris:AddItem(flash, 0.05)
end

function GunController.start()
	shootRemote = Remotes.waitFor("ShootGun") :: RemoteEvent
	reloadRemote = Remotes.waitFor("WeaponReload") :: RemoteEvent
	fxRemote = Remotes.waitFor("WeaponFx") :: RemoteEvent

	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if not equippedRanged then
			return
		end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.DPadUp then
			if reloadRemote then
				reloadRemote:FireServer()
			end
		end
	end)

	fxRemote.OnClientEvent:Connect(function(_userId, _weaponId, origin, dir)
		if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
			playShotFx(origin, dir)
		end
	end)
end

return GunController
