-- Merchant shop UI. When the server fires MerchantShop (after you trigger a merchant's
-- Trade prompt) this opens a panel listing wares: buy weapons / ammo with Doubloons, or
-- craft ammo from Scrap. Purchases go through the MerchantTrade RemoteFunction which the
-- server validates (proximity + currency).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MerchantController = {}

local player = Players.LocalPlayer
local shopRemote: RemoteEvent? = nil
local tradeRemote: RemoteFunction? = nil
local gui: ScreenGui? = nil
local currencyLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil

local function currencyText(): string
	local d = player:GetAttribute(Config.Currency.Doubloons.Attribute) or 0
	local s = player:GetAttribute(Config.Currency.Scrap.Attribute) or 0
	return `Doubloons: {d}    Scrap: {s}`
end

local function refreshCurrency()
	if currencyLabel then
		currencyLabel.Text = currencyText()
	end
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
		currencyLabel = nil
		statusLabel = nil
	end
end

local function buy(index: number)
	if not tradeRemote then
		return
	end
	local ok, result = pcall(function()
		return tradeRemote:InvokeServer(index)
	end)
	if ok and typeof(result) == "table" then
		if statusLabel then
			statusLabel.Text = result.message or ""
			statusLabel.TextColor3 = if result.ok
				then Color3.fromRGB(150, 235, 160)
				else Color3.fromRGB(240, 150, 150)
		end
		refreshCurrency()
	end
end

local function open(shop: { any })
	close()

	local screen = Instance.new("ScreenGui")
	screen.Name = "MerchantShop"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 60
	screen.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 460)
	panel.BackgroundColor3 = Color3.fromRGB(14, 30, 44)
	panel.BorderSizePixel = 0
	panel.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(46, 92, 168)
	stroke.Thickness = 2
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 34)
	title.Position = UDim2.fromOffset(12, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(150, 200, 255)
	title.Text = "Merchant"
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(30, 30)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -10, 0, 12)
	closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 34)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(240, 220, 220)
	closeBtn.TextSize = 18
	closeBtn.Parent = panel
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 6)
	cc.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(close)

	currencyLabel = Instance.new("TextLabel")
	currencyLabel.Size = UDim2.new(1, -24, 0, 24)
	currencyLabel.Position = UDim2.fromOffset(12, 46)
	currencyLabel.BackgroundTransparency = 1
	currencyLabel.Font = Enum.Font.GothamMedium
	currencyLabel.TextXAlignment = Enum.TextXAlignment.Left
	currencyLabel.TextSize = 15
	currencyLabel.TextColor3 = Color3.fromRGB(255, 214, 120)
	currencyLabel.Text = currencyText()
	currencyLabel.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -120)
	scroll.Position = UDim2.fromOffset(12, 76)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	for index, entry in shop do
		local currencyDef = Config.Currency[entry.Currency]
		local currencyName = currencyDef and currencyDef.Label or entry.Currency
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -6, 0, 42)
		row.LayoutOrder = index
		row.BackgroundColor3 = if entry.Currency == "Scrap"
			then Color3.fromRGB(30, 46, 40)
			else Color3.fromRGB(26, 42, 62)
		row.Font = Enum.Font.GothamBold
		row.TextSize = 15
		row.TextColor3 = Color3.fromRGB(230, 240, 248)
		row.Text = `{entry.Label}   —   {entry.Cost} {currencyName}`
		row.Parent = scroll
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 8)
		rc.Parent = row
		row.MouseButton1Click:Connect(function()
			buy(index)
		end)
	end

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -24, 0, 28)
	statusLabel.AnchorPoint = Vector2.new(0, 1)
	statusLabel.Position = UDim2.new(0, 12, 1, -10)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextSize = 14
	statusLabel.TextColor3 = Color3.fromRGB(190, 205, 215)
	statusLabel.Text = "Trade Doubloons or craft ammo from Scrap."
	statusLabel.Parent = panel

	gui = screen

	-- Keep currency line live while the shop is open.
	player:GetAttributeChangedSignal(Config.Currency.Doubloons.Attribute):Connect(refreshCurrency)
	player:GetAttributeChangedSignal(Config.Currency.Scrap.Attribute):Connect(refreshCurrency)
end

function MerchantController.start()
	shopRemote = Remotes.waitFor("MerchantShop") :: RemoteEvent
	tradeRemote = Remotes.waitFor("MerchantTrade") :: RemoteFunction

	shopRemote.OnClientEvent:Connect(function(shop)
		if typeof(shop) == "table" then
			open(shop)
		end
	end)
end

return MerchantController
