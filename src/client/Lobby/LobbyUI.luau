-- Survive at Sea lobby HUD — ocean themed, Dead Rails-style crew boarding.
-- Built for phone, tablet, computer, console, and VR (large targets, TextScaled, gamepad).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlatformInput = require(script.Parent.PlatformInput)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LobbyUI = {}

local state = {
	party = nil :: any,
	portals = {} :: { any },
	createPortalIndex = 1,
	selectedMax = Config.DefaultPartySize,
	privacy = "Public",
	device = PlatformInput.getDeviceKind(),
}

local remotes
local screenGui
local partyPanel
local createPanel
local joinPanel
local toastFrame
local countdownLabel
local brandLabel
local deviceLabel

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Config.Theme.UIAccent
	s.Thickness = thickness or 1.5
	s.Transparency = 0.25
	s.Parent = parent
	return s
end

local function textLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = props.BackgroundTransparency or 1
	label.BackgroundColor3 = props.BackgroundColor3 or Config.Theme.UIPanel
	label.Size = props.Size or UDim2.fromScale(1, 0.2)
	label.Position = props.Position or UDim2.fromScale(0, 0)
	label.Font = props.Font or Config.UI.BodyFont
	label.Text = props.Text or ""
	label.TextColor3 = props.TextColor3 or Config.Theme.UIText
	label.TextScaled = true
	label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	label.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	label.Name = props.Name or "Label"
	label.Parent = props.Parent
	if props.BackgroundTransparency ~= 1 and props.BackgroundTransparency ~= nil then
		corner(label, 10)
	end
	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = props.MaxTextSize or 28
	sizeConstraint.MinTextSize = 10
	sizeConstraint.Parent = label
	return label
end

local function button(props: { [string]: any }): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = props.Name or "Button"
	btn.Size = props.Size or UDim2.new(1, 0, 0, math.max(Config.UI.MinTouchTarget, 48))
	btn.Position = props.Position or UDim2.fromScale(0, 0)
	btn.BackgroundColor3 = props.BackgroundColor3 or Config.Theme.UIAccent
	btn.TextColor3 = props.TextColor3 or Config.Theme.DeepOcean
	btn.Font = Config.UI.Font
	btn.Text = props.Text or "OK"
	btn.TextScaled = true
	btn.AutoButtonColor = true
	btn.Parent = props.Parent
	corner(btn, 12)
	stroke(btn, Color3.fromRGB(255, 255, 255), 1)

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = 22
	sizeConstraint.Parent = btn

	-- Console / VR / gamepad selection feedback
	btn.SelectionImageObject = nil
	btn.Activated:Connect(function()
		if props.OnClick then
			props.OnClick()
		end
	end)

	return btn
end

local function showToast(message: string, kind: string?)
	if not toastFrame then
		return
	end
	local label = toastFrame:FindFirstChild("Message") :: TextLabel
	if not label then
		return
	end

	local color = Config.Theme.UIAccent
	if kind == "error" then
		color = Config.Theme.DangerRed
	elseif kind == "success" then
		color = Color3.fromRGB(80, 200, 140)
	elseif kind == "info" then
		color = Config.Theme.Lantern
	end

	toastFrame.BackgroundColor3 = Config.Theme.UIPanel
	stroke(toastFrame, color, 2)
	label.Text = message
	toastFrame.Visible = true
	toastFrame.GroupTransparency = 0

	TweenService:Create(toastFrame, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
	task.delay(3.2, function()
		if label.Text == message then
			local tw = TweenService:Create(toastFrame, TweenInfo.new(0.35), { GroupTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			if label.Text == message then
				toastFrame.Visible = false
			end
		end
	end)
end

local function refreshPartyPanel()
	if not partyPanel then
		return
	end

	local party = state.party
	local title = partyPanel:FindFirstChild("Title") :: TextLabel
	local members = partyPanel:FindFirstChild("Members") :: TextLabel
	local codeLabel = partyPanel:FindFirstChild("Code") :: TextLabel
	local castOff = partyPanel:FindFirstChild("CastOff") :: TextButton
	local leaveBtn = partyPanel:FindFirstChild("Leave") :: TextButton

	if typeof(party) ~= "table" or party.__openCreate then
		partyPanel.Visible = false
		return
	end

	partyPanel.Visible = true
	title.Text = `CREW · Berth {party.portalIndex}`
	codeLabel.Text = `CODE  {party.code}  ·  {party.privacy}`

	local lines = {}
	for _, member in party.members do
		local tag = if member.isHost then "★ " else "• "
		table.insert(lines, tag .. member.displayName)
	end
	members.Text = table.concat(lines, "\n") .. `\n\n{ #party.members }/{party.maxPlayers} sailors`

	local isHost = party.hostUserId == player.UserId
	castOff.Visible = isHost and party.status == "Open"
	leaveBtn.Visible = party.status == "Open"

	if party.status == "Launching" and party.countdownEndsAt then
		countdownLabel.Visible = true
	else
		countdownLabel.Visible = false
	end
end

local function openCreate(portalIndex: number)
	state.createPortalIndex = portalIndex
	state.selectedMax = Config.DefaultPartySize
	state.privacy = "Public"
	if createPanel then
		createPanel.Visible = true
		local sliderLabel = createPanel:FindFirstChild("MaxLabel") :: TextLabel
		if sliderLabel then
			sliderLabel.Text = `Crew size: {state.selectedMax}`
		end
	end
	if joinPanel then
		joinPanel.Visible = false
	end
end

local function buildGui()
	local scale = PlatformInput.scaleForDevice()

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SurviveAtSeaLobbyUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 20
	-- Compatible with VR (laser pointer) and console focus nav
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screenGui
	PlatformInput.applySafeArea(root)

	local scaler = Instance.new("UIScale")
	scaler.Scale = scale
	scaler.Parent = root

	-- Brand hero signal (not just nav chrome)
	brandLabel = textLabel({
		Name = "Brand",
		Parent = root,
		Text = Config.GameName,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Config.Theme.Foam,
		Size = UDim2.new(0.56, 0, 0, 52),
		Position = UDim2.new(0, 8, 0, 4),
		MaxTextSize = 40,
	})

	local tagline = textLabel({
		Name = "Tagline",
		Parent = root,
		Text = Config.Tagline,
		TextColor3 = Config.Theme.UIMuted,
		Size = UDim2.new(0.56, 0, 0, 28),
		Position = UDim2.new(0, 8, 0, 52),
		MaxTextSize = 18,
	})

	deviceLabel = textLabel({
		Name = "Device",
		Parent = root,
		Text = `Deck ready · {state.device}`,
		TextColor3 = Config.Theme.UIAccent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.38, 0, 0, 24),
		Position = UDim2.new(0.62, -8, 0, 12),
		MaxTextSize = 16,
	})

	countdownLabel = textLabel({
		Name = "Countdown",
		Parent = root,
		Text = "CASTING OFF…",
		TextColor3 = Config.Theme.Lantern,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack,
		Size = UDim2.new(0.6, 0, 0, 48),
		Position = UDim2.new(0.2, 0, 0.12, 0),
		MaxTextSize = 36,
	})
	countdownLabel.Visible = false

	-- Join by code (always available — Dead Rails style)
	joinPanel = Instance.new("Frame")
	joinPanel.Name = "JoinPanel"
	joinPanel.BackgroundColor3 = Config.Theme.UIPanel
	joinPanel.BackgroundTransparency = 0.12
	joinPanel.Size = UDim2.new(0, 320, 0, 150)
	joinPanel.Position = UDim2.new(1, -336, 1, -170)
	joinPanel.AnchorPoint = Vector2.new(0, 0)
	joinPanel.Parent = root
	corner(joinPanel, 16)
	stroke(joinPanel)

	-- Responsive: on phones, stretch join panel
	local joinConstraint = Instance.new("UISizeConstraint")
	joinConstraint.MinSize = Vector2.new(260, 140)
	joinConstraint.MaxSize = Vector2.new(420, 200)
	joinConstraint.Parent = joinPanel

	textLabel({
		Name = "JoinTitle",
		Parent = joinPanel,
		Text = "JOIN CREW BY CODE",
		Font = Config.UI.Font,
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.new(0, 12, 0, 10),
		MaxTextSize = 18,
	})

	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.Size = UDim2.new(1, -24, 0, 44)
	codeBox.Position = UDim2.new(0, 12, 0, 46)
	codeBox.BackgroundColor3 = Color3.fromRGB(6, 20, 32)
	codeBox.TextColor3 = Config.Theme.Foam
	codeBox.PlaceholderText = "Enter code (e.g. K7QM)"
	codeBox.PlaceholderColor3 = Config.Theme.UIMuted
	codeBox.Font = Config.UI.Font
	codeBox.Text = ""
	codeBox.TextScaled = true
	codeBox.ClearTextOnFocus = false
	codeBox.Parent = joinPanel
	corner(codeBox, 10)
	stroke(codeBox, Config.Theme.SeaTeal, 1)

	button({
		Name = "JoinButton",
		Parent = joinPanel,
		Text = "Join Friends",
		Size = UDim2.new(1, -24, 0, 44),
		Position = UDim2.new(0, 12, 0, 98),
		OnClick = function()
			remotes.JoinParty:FireServer(codeBox.Text)
		end,
	})

	-- Create crew panel
	createPanel = Instance.new("Frame")
	createPanel.Name = "CreatePanel"
	createPanel.BackgroundColor3 = Config.Theme.UIPanel
	createPanel.BackgroundTransparency = 0.08
	createPanel.Size = UDim2.new(0, 360, 0, 280)
	createPanel.Position = UDim2.fromScale(0.5, 0.55)
	createPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	createPanel.Visible = false
	createPanel.Parent = root
	corner(createPanel, 18)
	stroke(createPanel, Config.Theme.SeaTeal, 2)

	textLabel({
		Name = "CreateTitle",
		Parent = createPanel,
		Text = "CREATE CREW BERTH",
		Font = Enum.Font.GothamBlack,
		Size = UDim2.new(1, -28, 0, 34),
		Position = UDim2.new(0, 14, 0, 14),
		MaxTextSize = 24,
	})

	local maxLabel = textLabel({
		Name = "MaxLabel",
		Parent = createPanel,
		Text = `Crew size: {state.selectedMax}`,
		Size = UDim2.new(1, -28, 0, 28),
		Position = UDim2.new(0, 14, 0, 56),
		MaxTextSize = 20,
	})

	button({
		Name = "Minus",
		Parent = createPanel,
		Text = "−",
		Size = UDim2.new(0, 56, 0, 48),
		Position = UDim2.new(0, 14, 0, 96),
		BackgroundColor3 = Config.Theme.SeaTeal,
		TextColor3 = Config.Theme.Foam,
		OnClick = function()
			state.selectedMax = math.max(Config.MinPartySize, state.selectedMax - 1)
			maxLabel.Text = `Crew size: {state.selectedMax}`
		end,
	})

	button({
		Name = "Plus",
		Parent = createPanel,
		Text = "+",
		Size = UDim2.new(0, 56, 0, 48),
		Position = UDim2.new(0, 80, 0, 96),
		BackgroundColor3 = Config.Theme.SeaTeal,
		TextColor3 = Config.Theme.Foam,
		OnClick = function()
			state.selectedMax = math.min(Config.MaxPartySize, state.selectedMax + 1)
			maxLabel.Text = `Crew size: {state.selectedMax}`
		end,
	})

	local privacyBtn = button({
		Name = "Privacy",
		Parent = createPanel,
		Text = "Privacy: Public",
		Size = UDim2.new(1, -28, 0, 48),
		Position = UDim2.new(0, 14, 0, 156),
		BackgroundColor3 = Color3.fromRGB(20, 70, 90),
		TextColor3 = Config.Theme.Foam,
		OnClick = function()
			state.privacy = if state.privacy == "Public" then "Private" else "Public"
			privacyBtn.Text = `Privacy: {state.privacy}`
		end,
	})

	button({
		Name = "ConfirmCreate",
		Parent = createPanel,
		Text = "Open Berth",
		Size = UDim2.new(0.55, -10, 0, 48),
		Position = UDim2.new(0, 14, 0, 216),
		OnClick = function()
			remotes.CreateParty:FireServer(state.createPortalIndex, state.selectedMax, state.privacy)
			createPanel.Visible = false
		end,
	})

	button({
		Name = "CancelCreate",
		Parent = createPanel,
		Text = "Cancel",
		Size = UDim2.new(0.45, -18, 0, 48),
		Position = UDim2.new(0.55, 4, 0, 216),
		BackgroundColor3 = Color3.fromRGB(50, 60, 70),
		TextColor3 = Config.Theme.Foam,
		OnClick = function()
			createPanel.Visible = false
		end,
	})

	-- Active party panel
	partyPanel = Instance.new("Frame")
	partyPanel.Name = "PartyPanel"
	partyPanel.BackgroundColor3 = Config.Theme.UIPanel
	partyPanel.BackgroundTransparency = 0.1
	partyPanel.Size = UDim2.new(0, 300, 0, 260)
	partyPanel.Position = UDim2.new(0, 12, 1, -280)
	partyPanel.Visible = false
	partyPanel.Parent = root
	corner(partyPanel, 16)
	stroke(partyPanel, Config.Theme.Lantern, 1.5)

	textLabel({
		Name = "Title",
		Parent = partyPanel,
		Text = "CREW",
		Font = Enum.Font.GothamBlack,
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 10, 0, 10),
		MaxTextSize = 22,
	})

	textLabel({
		Name = "Code",
		Parent = partyPanel,
		Text = "CODE",
		TextColor3 = Config.Theme.UIAccent,
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 10, 0, 42),
		MaxTextSize = 18,
	})

	textLabel({
		Name = "Members",
		Parent = partyPanel,
		Text = "",
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -20, 0, 110),
		Position = UDim2.new(0, 10, 0, 72),
		MaxTextSize = 16,
	})

	button({
		Name = "CastOff",
		Parent = partyPanel,
		Text = "Cast Off →",
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0, 10, 0, 190),
		BackgroundColor3 = Config.Theme.Lantern,
		OnClick = function()
			remotes.StartLaunch:FireServer()
		end,
	})

	button({
		Name = "Leave",
		Parent = partyPanel,
		Text = "Leave Crew",
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.new(0, 10, 0, 238),
		BackgroundColor3 = Color3.fromRGB(70, 40, 45),
		TextColor3 = Config.Theme.Foam,
		OnClick = function()
			remotes.LeaveParty:FireServer()
		end,
	})

	-- Toast
	toastFrame = Instance.new("CanvasGroup")
	toastFrame.Name = "Toast"
	toastFrame.BackgroundColor3 = Config.Theme.UIPanel
	toastFrame.Size = UDim2.new(0.5, 0, 0, 48)
	toastFrame.Position = UDim2.new(0.25, 0, 0.08, 0)
	toastFrame.Visible = false
	toastFrame.GroupTransparency = 1
	toastFrame.Parent = root
	corner(toastFrame, 12)

	local toastConstraint = Instance.new("UISizeConstraint")
	toastConstraint.MinSize = Vector2.new(200, 44)
	toastConstraint.MaxSize = Vector2.new(560, 64)
	toastConstraint.Parent = toastFrame

	textLabel({
		Name = "Message",
		Parent = toastFrame,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 20,
	})

	-- Soft brand bob
	task.spawn(function()
		local t = 0
		while brandLabel.Parent do
			t += 0.03
			brandLabel.Position = UDim2.new(0, 8, 0, 4 + math.sin(t) * 2)
			tagline.TextTransparency = 0.15 + math.sin(t * 0.8) * 0.08
			task.wait(0.05)
		end
	end)

	-- Layout adaptation on resize / device
	local function relayout()
		state.device = PlatformInput.getDeviceKind()
		deviceLabel.Text = `Deck ready · {state.device}`
		scaler.Scale = PlatformInput.scaleForDevice()

		local cam = workspace.CurrentCamera
		local width = if cam then cam.ViewportSize.X else 1280
		if width < 700 then
			joinPanel.Size = UDim2.new(1, -24, 0, 150)
			joinPanel.Position = UDim2.new(0, 12, 1, -166)
			partyPanel.Size = UDim2.new(1, -24, 0, 250)
			partyPanel.Position = UDim2.new(0, 12, 1, -420)
			createPanel.Size = UDim2.new(1, -24, 0, 300)
			brandLabel.Size = UDim2.new(1, -16, 0, 44)
		elseif width < 1100 then
			joinPanel.Size = UDim2.new(0, 320, 0, 150)
			joinPanel.Position = UDim2.new(1, -336, 1, -170)
			partyPanel.Position = UDim2.new(0, 12, 1, -280)
		else
			joinPanel.Size = UDim2.new(0, 320, 0, 150)
			joinPanel.Position = UDim2.new(1, -336, 1, -170)
			partyPanel.Position = UDim2.new(0, 12, 1, -280)
		end
	end

	relayout()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	UserInputService.LastInputTypeChanged:Connect(relayout)

	-- Gamepad focus defaults
	if PlatformInput.isGamepadPreferred() then
		local joinButton = joinPanel:FindFirstChild("JoinButton")
		if joinButton and joinButton:IsA("GuiButton") then
			game:GetService("GuiService").SelectedObject = joinButton
		end
	end
end

local function bindRemotes()
	local folder = Remotes.getFolder()
	remotes = {
		CreateParty = folder:WaitForChild("CreateParty") :: RemoteEvent,
		JoinParty = folder:WaitForChild("JoinParty") :: RemoteEvent,
		LeaveParty = folder:WaitForChild("LeaveParty") :: RemoteEvent,
		StartLaunch = folder:WaitForChild("StartLaunch") :: RemoteEvent,
		PartyUpdated = folder:WaitForChild("PartyUpdated") :: RemoteEvent,
		PortalsUpdated = folder:WaitForChild("PortalsUpdated") :: RemoteEvent,
		Toast = folder:WaitForChild("Toast") :: RemoteEvent,
		GetLobbyState = folder:WaitForChild("GetLobbyState") :: RemoteFunction,
	}

	remotes.Toast.OnClientEvent:Connect(function(message, kind)
		showToast(tostring(message), kind)
	end)

	remotes.PartyUpdated.OnClientEvent:Connect(function(party)
		if typeof(party) == "table" and party.__openCreate then
			openCreate(party.portalIndex or 1)
			return
		end
		state.party = party
		refreshPartyPanel()
	end)

	remotes.PortalsUpdated.OnClientEvent:Connect(function(portals)
		state.portals = portals
	end)

	local ok, lobbyState = pcall(function()
		return remotes.GetLobbyState:InvokeServer()
	end)
	if ok and typeof(lobbyState) == "table" then
		state.party = lobbyState.party
		state.portals = lobbyState.portals or {}
		refreshPartyPanel()
	end
end

local function runCountdownTicker()
	RunService.RenderStepped:Connect(function()
		local party = state.party
		if typeof(party) ~= "table" or party.status ~= "Launching" or not party.countdownEndsAt then
			if countdownLabel then
				countdownLabel.Visible = false
			end
			return
		end
		local remaining = math.max(0, math.ceil(party.countdownEndsAt - workspace:GetServerTimeNow()))
		countdownLabel.Visible = true
		countdownLabel.Text = if remaining > 0 then `CASTING OFF IN {remaining}` else "SETTING SAIL!"
	end)
end

function LobbyUI.openCreateForPortal(portalIndex: number)
	openCreate(portalIndex)
	showToast(`Berth {portalIndex} — pick crew size and cast your berth.`, "info")
end

function LobbyUI.start()
	buildGui()
	bindRemotes()
	runCountdownTicker()

	-- Client-built portals signal create via BindableEvent
	local openEvent = ReplicatedStorage:FindFirstChild("SurviveAtSeaOpenCreate")
	if not openEvent then
		openEvent = Instance.new("BindableEvent")
		openEvent.Name = "SurviveAtSeaOpenCreate"
		openEvent.Parent = ReplicatedStorage
	end
	(openEvent :: BindableEvent).Event:Connect(function(portalIndex)
		if typeof(portalIndex) == "number" then
			LobbyUI.openCreateForPortal(portalIndex)
		end
	end)

	showToast("Walk to a berth on the pier · press E to board.", "info")
	print(`[SurviveAtSea] Lobby UI ready ({state.device})`)
end

return LobbyUI
