-- Persistent clock HUD. Shows a normal wall-clock time (e.g. 2:00 PM) while
-- the day/night cycle advances lighting behind the scenes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DayNight = require(Shared:WaitForChild("DayNight"))

local PlatformInput = require(script.Parent.PlatformInput)

local ClockHUD = {}

local started = false

function ClockHUD.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SurviveAtSeaClockHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 15
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screenGui
	PlatformInput.applySafeArea(root)

	local scaler = Instance.new("UIScale")
	scaler.Scale = PlatformInput.scaleForDevice()
	scaler.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "ClockPanel"
	panel.BackgroundColor3 = Config.Theme.UIPanel
	panel.BackgroundTransparency = 0.18
	panel.Size = UDim2.new(0, 128, 0, 44)
	panel.Position = UDim2.new(0.5, 0, 0, 10)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Theme.SeaTeal
	stroke.Thickness = 1.2
	stroke.Transparency = 0.35
	stroke.Parent = panel

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.BackgroundTransparency = 1
	timeLabel.Size = UDim2.new(1, -12, 1, -4)
	timeLabel.Position = UDim2.new(0, 6, 0, 2)
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.Text = "12:00 PM"
	timeLabel.TextColor3 = Config.Theme.UIText
	timeLabel.TextScaled = true
	timeLabel.Parent = panel

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = 20
	sizeConstraint.MinTextSize = 12
	sizeConstraint.Parent = timeLabel

	local function refresh()
		local state = DayNight.getState(Workspace:GetServerTimeNow())
		timeLabel.Text = state.displayTime
		-- Slightly cooler text at night so the clock reads with the sky.
		if state.phase == "Night" then
			timeLabel.TextColor3 = Color3.fromRGB(190, 210, 235)
			stroke.Color = Color3.fromRGB(90, 110, 160)
		else
			timeLabel.TextColor3 = Config.Theme.UIText
			stroke.Color = Config.Theme.SeaTeal
		end
	end

	refresh()
	RunService.RenderStepped:Connect(function()
		refresh()
	end)

	UserInputService.LastInputTypeChanged:Connect(function()
		scaler.Scale = PlatformInput.scaleForDevice()
	end)

	print("[SurviveAtSea] Clock HUD ready")
end

return ClockHUD
