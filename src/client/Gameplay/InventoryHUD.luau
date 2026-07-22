-- Small always-on HUD showing looted currency (Doubloons / Scrap) and the equipped
-- ranged weapon's ammo (loaded / reserve). Reads Player attributes which the server
-- keeps authoritative and which replicate automatically to the owning client.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local InventoryHUD = {}

local player = Players.LocalPlayer
local doubloonLabel: TextLabel? = nil
local scrapLabel: TextLabel? = nil
local ammoLabel: TextLabel? = nil
local equippedRanged: Tool? = nil
local loadedConn: RBXScriptConnection? = nil

local function makeRow(parent: Instance, order: number, color: Color3): TextLabel
	local row = Instance.new("TextLabel")
	row.Name = "Row" .. order
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.GothamBold
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextSize = 16
	row.TextColor3 = color
	row.Text = ""
	row.Parent = parent
	return row
end

local function refreshCurrency()
	if doubloonLabel then
		local v = player:GetAttribute(Config.Currency.Doubloons.Attribute) or 0
		doubloonLabel.Text = `Doubloons: {v}`
	end
	if scrapLabel then
		local v = player:GetAttribute(Config.Currency.Scrap.Attribute) or 0
		scrapLabel.Text = `Scrap: {v}`
	end
end

local function refreshAmmo()
	if not ammoLabel then
		return
	end
	-- Ammo is only ever shown while a gun is actually equipped. Clubs / spears and an
	-- empty-handed player show no ammo line at all (it's hidden, not just blank).
	local tool = equippedRanged
	if not (tool and tool.Parent) then
		ammoLabel.Visible = false
		ammoLabel.Text = ""
		return
	end
	local ammoId = tool:GetAttribute("Ammo")
	if typeof(ammoId) ~= "string" then
		ammoLabel.Visible = false
		ammoLabel.Text = ""
		return
	end
	-- Per-gun ammo: reads the equipped gun's own ammo type + chambered/reserve counts.
	local ammoDef = Weapons.Ammo[ammoId]
	local reserve = player:GetAttribute(ammoDef and ammoDef.Attribute) or 0
	local loaded = tool:GetAttribute("Loaded") or 0
	local label = ammoDef and ammoDef.Label or ammoId
	ammoLabel.Visible = true
	ammoLabel.Text = `{label}: {loaded} / {reserve}`
end

local function watchEquipped(tool: Tool?)
	if loadedConn then
		loadedConn:Disconnect()
		loadedConn = nil
	end
	equippedRanged = tool
	if tool then
		loadedConn = tool:GetAttributeChangedSignal("Loaded"):Connect(refreshAmmo)
	end
	refreshAmmo()
end

local function isRanged(tool: Instance?): boolean
	-- Match the gun controller: real ranged weapons (Ranged) and the legacy flintlock.
	return tool ~= nil
		and tool:IsA("Tool")
		and (tool:GetAttribute("Ranged") == true or tool:GetAttribute("SurviveGun") == true)
end

local function hookCharacter(character: Model)
	watchEquipped(nil)
	character.ChildAdded:Connect(function(child)
		if isRanged(child) then
			watchEquipped(child :: Tool)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == equippedRanged then
			watchEquipped(nil)
		end
	end)
	for _, child in character:GetChildren() do
		if isRanged(child) then
			watchEquipped(child :: Tool)
		end
	end
end

function InventoryHUD.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 22
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.new(0, 16, 0, 96)
	panel.Size = UDim2.fromOffset(190, 84)
	panel.BackgroundColor3 = Color3.fromRGB(10, 24, 36)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	doubloonLabel = makeRow(panel, 1, Color3.fromRGB(255, 214, 120))
	scrapLabel = makeRow(panel, 2, Color3.fromRGB(190, 200, 210))
	ammoLabel = makeRow(panel, 3, Color3.fromRGB(150, 205, 255))

	-- Currency attribute listeners
	player:GetAttributeChangedSignal(Config.Currency.Doubloons.Attribute):Connect(refreshCurrency)
	player:GetAttributeChangedSignal(Config.Currency.Scrap.Attribute):Connect(refreshCurrency)
	for _, ammo in Weapons.Ammo do
		player:GetAttributeChangedSignal(ammo.Attribute):Connect(refreshAmmo)
	end

	refreshCurrency()
	refreshAmmo()

	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
end

return InventoryHUD
