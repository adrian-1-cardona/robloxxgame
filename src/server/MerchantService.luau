-- The blue-hatted tribal merchant. NEVER hostile. Spawns on inhabited villages, is
-- registered as a draggable / weldable loot prop (so you can haul it onto your raft and
-- weld it), and runs a trade shop: buy weapons / ammo with looted Doubloons, or craft
-- ammo from scavenged Scrap.
--
-- Trade flow:
--   * A ProximityPrompt on the merchant fires MerchantShop:FireClient(player, shop) to
--     open the client shop UI.
--   * The client invokes MerchantTrade (RemoteFunction) with a shop index; the server
--     validates proximity + currency and grants the item.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local NpcFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("NpcFactory"))
local LootPropFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("LootPropFactory"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

local MerchantService = {}

MerchantService._merchants = {} :: { Model }
MerchantService._Toast = nil :: RemoteEvent?
MerchantService._Shop = nil :: RemoteEvent?
MerchantService._registerProp = nil :: ((Model) -> ())?
MerchantService._started = false

local function toast(player: Player, message: string, kind: string)
	if MerchantService._Toast then
		MerchantService._Toast:FireClient(player, message, kind)
	end
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root :: BasePart
	end
	return nil
end

local function nearestMerchantDistance(player: Player): number
	local root = getRoot(player)
	if not root then
		return math.huge
	end
	local best = math.huge
	for _, m in MerchantService._merchants do
		if not m.Parent then
			continue
		end
		local primary = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
		if primary and primary:IsA("BasePart") then
			local d = (primary.Position - root.Position).Magnitude
			if d < best then
				best = d
			end
		end
	end
	return best
end

function MerchantService.spawnMerchant(parent: Instance, cf: CFrame, islandId: string?): Model
	local model, root = NpcFactory.createMerchant(parent, cf, { islandId = islandId })

	-- Make the merchant a draggable / weldable prop (but never pocketable).
	LootPropFactory.tagAsProp(model, "Merchant", { noPickup = true })
	if MerchantService._registerProp then
		MerchantService._registerProp(model)
	end

	-- Trade prompt (E). Sits alongside the weld prompt (X) added by the loot system.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TradePrompt"
	prompt.ActionText = "Trade"
	prompt.ObjectText = "Merchant"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = Config.Islands.Merchant.GreetRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = root

	prompt.Triggered:Connect(function(player: Player)
		if MerchantService._Shop then
			MerchantService._Shop:FireClient(player, Weapons.Shop)
		end
		toast(player, "The merchant nods. Trade Doubloons or craft with Scrap.", "info")
	end)

	table.insert(MerchantService._merchants, model)
	model.Destroying:Connect(function()
		for i, m in MerchantService._merchants do
			if m == model then
				table.remove(MerchantService._merchants, i)
				break
			end
		end
	end)

	return model
end

function MerchantService.handleTrade(player: Player, index: any): { ok: boolean, message: string }
	if typeof(index) ~= "number" then
		return { ok = false, message = "Invalid trade." }
	end
	local entry = Weapons.Shop[index]
	if not entry then
		return { ok = false, message = "That item isn't for sale." }
	end

	-- Must be near a merchant (on an isle) or a merchant welded to your raft.
	if nearestMerchantDistance(player) > Config.Islands.Merchant.GreetRange + 12 then
		return { ok = false, message = "Get closer to a merchant to trade." }
	end

	local currencyId = entry.Currency
	local cost = entry.Cost or 0

	-- Weapons: reject up front if already carried (don't spend then refund).
	if entry.Kind == "weapon" then
		local def = Weapons.get(entry.Weapon)
		if not def then
			return { ok = false, message = "Unknown weapon." }
		end
	end

	if WeaponService.getCurrency(player, currencyId) < cost then
		local label = Config.Currency[currencyId] and Config.Currency[currencyId].Label or currencyId
		return { ok = false, message = `Not enough {label}.` }
	end

	if entry.Kind == "ammo" then
		if not WeaponService.spendCurrency(player, currencyId, cost) then
			return { ok = false, message = "Trade failed." }
		end
		WeaponService.giveAmmo(player, entry.Ammo, entry.Amount)
		local label = Weapons.Ammo[entry.Ammo] and Weapons.Ammo[entry.Ammo].Label or entry.Ammo
		return { ok = true, message = `Got {entry.Amount} {label}.` }
	elseif entry.Kind == "weapon" then
		-- Try to grant first (giveWeapon rejects duplicates) then charge.
		local granted = WeaponService.giveWeapon(player, entry.Weapon, true)
		if not granted then
			return { ok = false, message = "You already carry that weapon." }
		end
		if not WeaponService.spendCurrency(player, currencyId, cost) then
			return { ok = false, message = "Trade failed." }
		end
		local def = Weapons.get(entry.Weapon)
		-- Throw in a little ammo with a purchased gun.
		if def and def.Class == "ranged" and def.Ammo then
			WeaponService.giveAmmo(player, def.Ammo, Weapons.AmmoBundle[def.Ammo] or 6)
		end
		return { ok = true, message = `Bought {def and def.Name or entry.Weapon}.` }
	end

	return { ok = false, message = "Nothing happened." }
end

function MerchantService.start(remotes: {
	Toast: RemoteEvent,
	Shop: RemoteEvent,
	Trade: RemoteFunction,
}, registerProp: (Model) -> ())
	if MerchantService._started then
		return
	end
	MerchantService._started = true
	MerchantService._Toast = remotes.Toast
	MerchantService._Shop = remotes.Shop
	MerchantService._registerProp = registerProp

	remotes.Trade.OnServerInvoke = function(player, index)
		return MerchantService.handleTrade(player, index)
	end

	Players.PlayerRemoving:Connect(function() end)
end

return MerchantService
