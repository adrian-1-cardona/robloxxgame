-- Small always-on HUD showing looted currency (Doubloons / Scrap) and the equipped
-- ranged weapon's ammo (loaded / reserve). Reads Player attributes which the server
-- keeps authoritative and which replicate automatically to the owning client.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local InventoryHUD = {}

local player = Players.LocalPlayer
local panel: Frame? = nil
local doubloonLabel: TextLabel? = nil
local scrapLabel: TextLabel? = nil
local armorLabel: TextLabel? = nil
local ammoLabel: TextLabel? = nil
local equippedRanged: Tool? = nil
local loadedConn: RBXScriptConnection? = nil
-- Panel is hidden on the lobby pier and only shown once the player is out at sea
-- (on a crew). Mirrors WeatherController / OceanController gameplay gating.
local atSea = false

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

local function refreshArmor()
	if not armorLabel then
		return
	end
	local rating = player:GetAttribute("ArmorRating")
	rating = if typeof(rating) == "number" then rating else 0
	-- Only show the armor line once you're actually wearing something.
	if rating <= 0 then
		armorLabel.Visible = false
		armorLabel.Text = ""
		return
	end
	armorLabel.Visible = true
	armorLabel.Text = `Armor: {math.floor(rating * 100 + 0.5)}%`
end

-- Pick the ammo type to display when no gun is equipped: whichever reserve the
-- player is actually carrying the most of. Returns nil when they hold no ammo.
local function bestCarriedAmmo(): ({ [string]: any }?, number)
	local bestDef: { [string]: any }? = nil
	local bestReserve = 0
	for _, ammoDef in Weapons.Ammo do
		local reserve = player:GetAttribute(ammoDef.Attribute)
		reserve = if typeof(reserve) == "number" then reserve else 0
		if reserve > bestReserve then
			bestReserve = reserve
			bestDef = ammoDef
		end
	end
	return bestDef, bestReserve
end

local function refreshAmmo()
	if not ammoLabel then
		return
	end
	-- Ammo shows whenever the player has ammo — either loaded in an equipped gun or
	-- sitting in reserve. With no ammo at all the line is hidden entirely (not blank).
	local tool = equippedRanged
	if tool and tool.Parent then
		local ammoId = tool:GetAttribute("Ammo")
		if typeof(ammoId) == "string" then
			-- Per-gun ammo: the equipped gun's own type + chambered / reserve counts.
			local ammoDef = Weapons.Ammo[ammoId]
			local reserve = player:GetAttribute(ammoDef and ammoDef.Attribute) or 0
			local loaded = tool:GetAttribute("Loaded") or 0
			local label = ammoDef and ammoDef.Label or ammoId
			ammoLabel.Visible = true
			ammoLabel.Text = `{label}: {loaded} / {reserve}`
			return
		end
	end

	-- No gun equipped: still surface the reserve the player is carrying so ammo looted
	-- before finding a weapon is visible. Nothing carried → hide the line.
	local ammoDef, reserve = bestCarriedAmmo()
	if ammoDef and reserve > 0 then
		ammoLabel.Visible = true
		ammoLabel.Text = `{ammoDef.Label}: {reserve}`
		return
	end

	ammoLabel.Visible = false
	ammoLabel.Text = ""
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

local function applyVisibility()
	if panel then
		panel.Visible = atSea
	end
end

local function setAtSea(value: boolean)
	if atSea == value then
		return
	end
	atSea = value
	applyVisibility()
end

-- Detect lobby vs. out-at-sea the same way WeatherController does: seed from the
-- GetLobbyState RemoteFunction, then follow PartyUpdated. Panel hides on the pier
-- (no party) and appears once you're on a crew.
local function watchPartyState()
	task.spawn(function()
		local ok, folder = pcall(function()
			return Remotes.getFolder()
		end)
		if not ok or not folder then
			return
		end
		local getLobbyState = folder:WaitForChild("GetLobbyState", 30)
		if getLobbyState and getLobbyState:IsA("RemoteFunction") then
			local success, lobbyState = pcall(function()
				return getLobbyState:InvokeServer()
			end)
			if success and typeof(lobbyState) == "table" then
				setAtSea(typeof(lobbyState.party) == "table")
			end
		end
		local partyUpdated = folder:WaitForChild("PartyUpdated", 30)
		if partyUpdated and partyUpdated:IsA("RemoteEvent") then
			partyUpdated.OnClientEvent:Connect(function(party)
				if typeof(party) == "table" and party.__openCreate then
					return
				end
				setAtSea(typeof(party) == "table")
			end)
		end
	end)
end

function InventoryHUD.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 22
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	-- Hidden until watchPartyState confirms we're on a crew (out at sea).
	panel.Visible = false
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.new(0, 16, 0, 96)
	panel.Size = UDim2.fromOffset(190, 108)
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
	armorLabel = makeRow(panel, 3, Color3.fromRGB(170, 220, 175))
	ammoLabel = makeRow(panel, 4, Color3.fromRGB(150, 205, 255))

	-- Currency attribute listeners
	player:GetAttributeChangedSignal(Config.Currency.Doubloons.Attribute):Connect(refreshCurrency)
	player:GetAttributeChangedSignal(Config.Currency.Scrap.Attribute):Connect(refreshCurrency)
	player:GetAttributeChangedSignal("ArmorRating"):Connect(refreshArmor)
	for _, ammo in Weapons.Ammo do
		player:GetAttributeChangedSignal(ammo.Attribute):Connect(refreshAmmo)
	end

	refreshCurrency()
	refreshArmor()
	refreshAmmo()

	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)

	-- Gate the whole panel on lobby vs. at-sea state (starts hidden on the pier).
	applyVisibility()
	watchPartyState()
end

return InventoryHUD
