-- Hold-to-drag world loot: RMB (PC), RT / ButtonR2 (console), hold touch / Drag button (mobile).
-- Weld / unweld: X key · Xbox ButtonX (ProximityPrompt) · Weld button on mobile.
-- Place equipped loot tool with left click / LT / Place button.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlatformInput = require(script.Parent.Parent:WaitForChild("Lobby"):WaitForChild("PlatformInput"))

local DragController = {}

local player = Players.LocalPlayer

local DragStart: RemoteEvent? = nil
local DragUpdate: RemoteEvent? = nil
local DragEnd: RemoteEvent? = nil
local WeldRemote: RemoteEvent? = nil
local UnweldRemote: RemoteEvent? = nil
local PlaceRemote: RemoteEvent? = nil

local holding = false
local holdStartedAt = 0
local dragging = false
local dragPropId: string? = nil
local dragModel: Model? = nil
local mobileGui: ScreenGui? = nil
local hintGui: ScreenGui? = nil

-- Shared flag so MeleeController won't swing while we're dragging / aiming loot
DragController.isBusy = false

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function findLootModel(inst: Instance?): Model?
	local cur: Instance? = inst
	while cur and cur ~= Workspace do
		if cur:IsA("Model") and cur:GetAttribute("IsLootProp") == true then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function raycastLoot(maxDist: number): (Model?, Vector3?)
	local camera = getCamera()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and root and root:IsA("BasePart")) then
		return nil, nil
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * maxDist

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction, params)
	if not result then
		return nil, nil
	end
	local model = findLootModel(result.Instance)
	if not model then
		return nil, nil
	end
	if (root.Position - result.Position).Magnitude > Config.Loot.DragRange + 6 then
		return nil, nil
	end
	return model, result.Position
end

local function targetCFrameForModel(model: Model): CFrame?
	local camera = getCamera()
	local primary = model.PrimaryPart
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and primary and root and root:IsA("BasePart")) then
		return nil
	end

	local hitDist = 10
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, model }
	params.IgnoreWater = true
	local result = Workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * Config.Loot.DragRange, params)
	local aimPos: Vector3
	if result then
		aimPos = result.Position + result.Normal * (math.max(primary.Size.X, primary.Size.Y, primary.Size.Z) * 0.35)
	else
		aimPos = camera.CFrame.Position + camera.CFrame.LookVector * hitDist
	end

	-- Keep roughly upright for walls / torches
	local kind = model:GetAttribute("LootKind")
	local flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.05 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	if kind == "Wall" then
		return CFrame.lookAt(aimPos, aimPos + flatLook)
	elseif kind == "Torch" then
		return CFrame.new(aimPos)
	elseif kind == "Plank" then
		return CFrame.lookAt(aimPos, aimPos + flatLook) * CFrame.Angles(0, 0, 0)
	end
	return CFrame.new(aimPos)
end

local function beginDrag(model: Model)
	local propId = model:GetAttribute("PropId")
	if typeof(propId) ~= "string" then
		return
	end
	dragging = true
	dragPropId = propId
	dragModel = model
	DragController.isBusy = true
	if DragStart then
		DragStart:FireServer(propId)
	end
end

local function endDrag()
	if dragging and dragPropId and DragEnd then
		DragEnd:FireServer(dragPropId)
	end
	dragging = false
	dragPropId = nil
	dragModel = nil
	holding = false
	DragController.isBusy = false
end

local function tryStartHold()
	if dragging then
		return
	end
	holding = true
	holdStartedAt = os.clock()
	local model = raycastLoot(Config.Loot.DragRange + 10)
	if model then
		DragController.isBusy = true
		-- Start after short hold so tap-melee still works when not aiming loot
		task.delay(Config.Loot.DragHoldSeconds, function()
			if holding and not dragging then
				local still, _ = raycastLoot(Config.Loot.DragRange + 10)
				if still == model then
					beginDrag(model)
				else
					DragController.isBusy = false
				end
			end
		end)
	end
end

local function onRelease()
	if dragging then
		endDrag()
		return
	end
	holding = false
	if not dragging then
		DragController.isBusy = false
	end
end

local function tryWeldKey()
	local model = dragModel or select(1, raycastLoot(Config.Loot.DragRange + 8))
	if not model then
		return
	end
	local propId = model:GetAttribute("PropId")
	if typeof(propId) ~= "string" then
		return
	end
	if model:GetAttribute("Welded") == true then
		if UnweldRemote then
			UnweldRemote:FireServer(propId)
		end
	else
		if WeldRemote then
			WeldRemote:FireServer(propId)
		end
	end
end

local function tryPlaceTool()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not (tool and tool:GetAttribute("IsLootTool") == true) then
		return
	end
	local camera = getCamera()
	if not (camera and PlaceRemote) then
		return
	end
	PlaceRemote:FireServer(camera.CFrame.LookVector)
end

local function destroyMobileGui()
	if mobileGui then
		mobileGui:Destroy()
		mobileGui = nil
	end
end

local function ensureMobileGui()
	local kind = PlatformInput.getDeviceKind()
	if kind ~= "Phone" and kind ~= "Tablet" then
		destroyMobileGui()
		return
	end
	if mobileGui then
		return
	end

	local scale = PlatformInput.scaleForDevice()
	local size = math.floor(58 * scale)

	local gui = Instance.new("ScreenGui")
	gui.Name = "LootDragButtons"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 36
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local function makeBtn(name: string, text: string, pos: UDim2, color: Color3): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.AnchorPoint = Vector2.new(1, 1)
		btn.Position = pos
		btn.Size = UDim2.fromOffset(size, size)
		btn.BackgroundColor3 = color
		btn.BackgroundTransparency = 0.08
		btn.BorderSizePixel = 0
		btn.Font = Config.UI.Font
		btn.Text = text
		btn.TextColor3 = Config.Theme.Foam
		btn.TextScaled = true
		btn.AutoButtonColor = true
		btn.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = btn
		return btn
	end

	local dragBtn = makeBtn("Drag", "DRAG", UDim2.new(1, -20, 1, -170), Color3.fromRGB(48, 88, 78))
	local weldBtn = makeBtn("Weld", "WELD", UDim2.new(1, -20, 1, -240), Color3.fromRGB(72, 56, 28))
	local placeBtn = makeBtn("Place", "PLACE", UDim2.new(1, -88, 1, -170), Color3.fromRGB(58, 72, 96))

	dragBtn.MouseButton1Down:Connect(function()
		tryStartHold()
	end)
	dragBtn.MouseButton1Up:Connect(function()
		onRelease()
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			-- Safety: if touch ended anywhere, stop drag hold from the button
			if holding or dragging then
				-- only if our drag button started it — handled via MouseButton1Up mostly
			end
		end
	end)

	weldBtn.MouseButton1Click:Connect(function()
		tryWeldKey()
	end)
	placeBtn.MouseButton1Click:Connect(function()
		tryPlaceTool()
	end)

	mobileGui = gui
end

local function ensureHint()
	if hintGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "LootHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Hint"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -24)
	label.Size = UDim2.new(0.7, 0, 0, 28)
	label.BackgroundTransparency = 1
	label.Font = Config.UI.BodyFont
	label.TextSize = 15
	label.TextColor3 = Config.Theme.Foam
	label.TextTransparency = 0.15
	label.Text = "Hold RMB / RT to drag loot · X to weld · E to pick up"
	label.Parent = gui
	hintGui = gui
end

function DragController.isLookingAtLoot(): boolean
	local model = raycastLoot(Config.Loot.DragRange + 6)
	return model ~= nil
end

function DragController.start()
	DragStart = Remotes.waitFor("LootDragStart") :: RemoteEvent
	DragUpdate = Remotes.waitFor("LootDragUpdate") :: RemoteEvent
	DragEnd = Remotes.waitFor("LootDragEnd") :: RemoteEvent
	WeldRemote = Remotes.waitFor("LootWeld") :: RemoteEvent
	UnweldRemote = Remotes.waitFor("LootUnweld") :: RemoteEvent
	PlaceRemote = Remotes.waitFor("LootPlace") :: RemoteEvent

	ensureMobileGui()
	ensureHint()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			tryStartHold()
			return
		end

		-- Weld / unweld: X (PC) — console uses ProximityPrompt ButtonX; also allow ButtonY as alt
		if input.KeyCode == Enum.KeyCode.X or input.KeyCode == Enum.KeyCode.ButtonY then
			tryWeldKey()
			return
		end

		-- Place loot tool from inventory
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			tryPlaceTool()
			return
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			onRelease()
		end
	end)

	-- Touch hold anywhere when aiming at loot (phones without pressing DRAG)
	UserInputService.TouchLongPress:Connect(function(_positions, state, _processed)
		if state == Enum.UserInputState.Begin then
			tryStartHold()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			onRelease()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not dragging or not dragPropId or not dragModel then
			return
		end
		if not dragModel.Parent then
			endDrag()
			return
		end
		local cf = targetCFrameForModel(dragModel)
		if cf and DragUpdate then
			DragUpdate:FireServer(dragPropId, cf)
		end
	end)

	player.CharacterAdded:Connect(function()
		endDrag()
		task.defer(ensureMobileGui)
	end)
end

return DragController
