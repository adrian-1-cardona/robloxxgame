-- Shared weapon / ammo definitions for Survive at Sea.
-- Single source of truth for both the server (authoritative fire + damage) and the
-- client (fire input, HUD, merchant shop). Kept OUT of Config.luau on purpose so the
-- headless PortalLoad test environment (which only loads Config/PartyCode/Types) is
-- never asked to construct weapon geometry data.
--
-- Weapon classes:
--   "melee"  — swung; hit detection in MeleeService (club spawns with you, spear looted).
--   "ranged" — fired; raycast in WeaponService. Ranged weapons consume Ammo per shot,
--              reload from carried reserve, and support multi-pellet spread (shotgun).

local Weapons = {}

-- Ammo reserves are tracked as Player attributes: "Ammo_" .. ammoId.
export type AmmoId = "Bullet" | "Shell" | "Arrow" | "Powder"

-- Loot rarity tiers. Shared by weapons AND armor (see Armor.luau) so a picked-up item's
-- floating tag / pricing reads the same colour everywhere:
--   1 Common (grey) · 2 Uncommon (green) · 3 Rare (blue) · 4 Epic (purple) · 5 Legendary (gold)
-- Common items drop the most often; each higher tier is progressively rarer.
Weapons.Rarity = {
	[0] = { Name = "Starter", Color = Color3.fromRGB(200, 205, 210) },
	[1] = { Name = "Common", Color = Color3.fromRGB(178, 186, 194) },
	[2] = { Name = "Uncommon", Color = Color3.fromRGB(108, 214, 116) },
	[3] = { Name = "Rare", Color = Color3.fromRGB(84, 168, 255) },
	[4] = { Name = "Epic", Color = Color3.fromRGB(190, 122, 255) },
	[5] = { Name = "Legendary", Color = Color3.fromRGB(255, 176, 72) },
}

function Weapons.rarityInfo(rarity: number?): { Name: string, Color: Color3 }
	return Weapons.Rarity[rarity or 1] or Weapons.Rarity[1]
end

Weapons.Ammo = {
	Bullet = { Id = "Bullet", Label = "Bullets", Attribute = "Ammo_Bullet", Max = 240 },
	Shell = { Id = "Shell", Label = "Shells", Attribute = "Ammo_Shell", Max = 120 },
	Arrow = { Id = "Arrow", Label = "Arrows", Attribute = "Ammo_Arrow", Max = 120 },
	Powder = { Id = "Powder", Label = "Powder & Ball", Attribute = "Ammo_Powder", Max = 60 },
}

-- Rarity is used both for loot weighting on islands and merchant pricing.
Weapons.List = {
	Club = {
		Id = "Club",
		Name = "Club",
		Class = "melee",
		ToolTip = "Heavy wooden club — RMB / RT / tap to swing",
		-- Buffed to match the improved starter club: hits harder, faster, wider arc.
		Damage = 30,
		Cooldown = 0.48,
		Range = 9,
		HitRadius = 3.8,
		HitWindow = 0.24,
		SwingDuration = 0.32,
		Knockback = 14,
		Rarity = 1, -- Common grey — the most abundant island loot (see LootWeights)
	},
	WarClub = {
		Id = "WarClub",
		Name = "Spiked War Club",
		Class = "melee",
		ToolTip = "Stone-spiked war club — brutal reach and knockback",
		-- A meaner club: a jagged stone head studded with spikes. Best-in-slot melee
		-- short of the spear's reach, with a strong shove on every connect.
		Damage = 44,
		Cooldown = 0.52,
		Range = 9.5,
		HitRadius = 4.0,
		HitWindow = 0.26,
		SwingDuration = 0.34,
		Knockback = 22,
		Rarity = 3,
	},
	Spear = {
		Id = "Spear",
		Name = "Fishing Spear",
		Class = "melee",
		ToolTip = "Bone-tipped spear — long reach, RMB / RT / tap to thrust",
		Damage = 34,
		Cooldown = 0.7,
		Range = 12,
		HitRadius = 2.4,
		HitWindow = 0.24,
		SwingDuration = 0.32,
		Rarity = 2,
	},
	Bow = {
		Id = "Bow",
		Name = "Hunting Bow",
		Class = "ranged",
		ToolTip = "Draw and loose — quiet, needs arrows",
		Damage = 38,
		Cooldown = 0.85,
		Range = 280,
		Ammo = "Arrow",
		MagSize = 1,
		ReloadTime = 0.0,
		Pellets = 1,
		Spread = 0.0,
		Rarity = 2,
	},
	Pistol = {
		Id = "Pistol",
		Name = "Flintlock Pistol",
		Class = "ranged",
		ToolTip = "Quick sidearm — needs bullets",
		Damage = 26,
		Cooldown = 0.5,
		Range = 230,
		Ammo = "Bullet",
		MagSize = 6,
		ReloadTime = 1.6,
		Pellets = 1,
		Spread = 0.012,
		Rarity = 2,
	},
	Revolver = {
		Id = "Revolver",
		Name = "Sea Revolver",
		Class = "ranged",
		ToolTip = "Six-shooter — punchy, needs bullets",
		Damage = 32,
		Cooldown = 0.42,
		Range = 250,
		Ammo = "Bullet",
		MagSize = 6,
		ReloadTime = 1.9,
		Pellets = 1,
		Spread = 0.016,
		Rarity = 4,
	},
	Rifle = {
		Id = "Rifle",
		Name = "Long Rifle",
		Class = "ranged",
		ToolTip = "Precise and hard-hitting at range — needs bullets",
		Damage = 48,
		Cooldown = 1.0,
		Range = 420,
		Ammo = "Bullet",
		MagSize = 5,
		ReloadTime = 2.4,
		Pellets = 1,
		Spread = 0.004,
		Rarity = 5,
	},
	Shotgun = {
		Id = "Shotgun",
		Name = "Boarding Shotgun",
		Class = "ranged",
		ToolTip = "Close-range spread — devastating up close, needs shells",
		Damage = 13,
		Cooldown = 1.05,
		Range = 100,
		Ammo = "Shell",
		MagSize = 2,
		ReloadTime = 2.2,
		Pellets = 8,
		Spread = 0.10,
		Rarity = 3,
	},
	-- (Musket below)
	Musket = {
		Id = "Musket",
		Name = "Old Musket",
		Class = "ranged",
		ToolTip = "One heavy shot, slow reload — needs powder & ball",
		Damage = 64,
		Cooldown = 1.9,
		Range = 380,
		Ammo = "Powder",
		MagSize = 1,
		ReloadTime = 2.8,
		Pellets = 1,
		Spread = 0.006,
		Rarity = 2,
	},
}

-- Weapons that can drop as island loot, with relative weights (rarer = smaller weight).
-- Clubs are Common grey and drop the most often; bows are a frequent find too. Rifles
-- are Legendary and barely ever show up.
Weapons.LootWeights = {
	Club = 46, -- Common grey — you'll find these all over the beaches
	WarClub = 12, -- Rare blue — a prized melee upgrade
	Spear = 26, -- Common melee
	Bow = 30, -- frequent find (quiet hunting)
	Pistol = 20,
	Musket = 16,
	Shotgun = 12,
	Revolver = 10,
	Rifle = 4, -- Legendary — extremely rare
}

-- Ammo bundle sizes handed out by loot / merchant.
Weapons.AmmoBundle = {
	Bullet = 12,
	Shell = 6,
	Arrow = 16, -- bows are common, so arrows come in bigger bundles
	Powder = 4,
}

-- Merchant shop: what the blue-hatted trader sells. Cost is either Doubloons (buy) or
-- Scrap (craft). The merchant is never hostile and always trades.
Weapons.Shop = {
	-- Ammo you craft from Scrap you scavenge on islands.
	{ Kind = "ammo", Ammo = "Bullet", Amount = 12, Currency = "Scrap", Cost = 4, Label = "Craft 12 Bullets" },
	{ Kind = "ammo", Ammo = "Shell", Amount = 6, Currency = "Scrap", Cost = 4, Label = "Craft 6 Shells" },
	{ Kind = "ammo", Ammo = "Arrow", Amount = 10, Currency = "Scrap", Cost = 2, Label = "Craft 10 Arrows" },
	{ Kind = "ammo", Ammo = "Powder", Amount = 4, Currency = "Scrap", Cost = 4, Label = "Craft 4 Powder & Ball" },
	-- Ammo you buy outright with Doubloons.
	{ Kind = "ammo", Ammo = "Bullet", Amount = 24, Currency = "Doubloons", Cost = 10, Label = "Buy 24 Bullets" },
	{ Kind = "ammo", Ammo = "Shell", Amount = 12, Currency = "Doubloons", Cost = 10, Label = "Buy 12 Shells" },
	-- Weapons for sale.
	{ Kind = "weapon", Weapon = "Pistol", Currency = "Doubloons", Cost = 30, Label = "Buy Flintlock Pistol" },
	{ Kind = "weapon", Weapon = "Bow", Currency = "Doubloons", Cost = 26, Label = "Buy Hunting Bow" },
	{ Kind = "weapon", Weapon = "Spear", Currency = "Doubloons", Cost = 18, Label = "Buy Fishing Spear" },
	{ Kind = "weapon", Weapon = "WarClub", Currency = "Doubloons", Cost = 40, Label = "Buy Spiked War Club" },
	{ Kind = "weapon", Weapon = "Shotgun", Currency = "Doubloons", Cost = 55, Label = "Buy Boarding Shotgun" },
	{ Kind = "weapon", Weapon = "Revolver", Currency = "Doubloons", Cost = 60, Label = "Buy Sea Revolver" },
	{ Kind = "weapon", Weapon = "Rifle", Currency = "Doubloons", Cost = 90, Label = "Buy Long Rifle" },
}

-- === Selling ==============================================================
-- The merchant buys anything you carry. Base sell value scales with rarity so a
-- legendary rifle is worth far more than a common club. Loot props (walls, torches,
-- planks, crates, beds) fetch a small flat scrap-tier value. Shared by client (price
-- preview) and server (authoritative payout) so both always agree.
Weapons.SellByRarity = {
	[0] = 3, -- Starter gear
	[1] = 4, -- Common
	[2] = 8, -- Uncommon
	[3] = 16, -- Rare
	[4] = 30, -- Epic
	[5] = 55, -- Legendary
}

-- Flat Doubloon value for salvage loot tools (Loot_Wall, Loot_Torch, ...).
Weapons.LootSellValue = 3

-- Authoritative sell price in Doubloons for an item, from what a Tool advertises via its
-- attributes. `itemId` is the Tool's "ItemId" attribute; `rarity` is optional (armor /
-- future items can pass their own tier). Returns 0 only for genuinely worthless items.
function Weapons.sellValue(itemId: string?, rarity: number?): number
	if typeof(itemId) == "string" then
		-- Looted weapons carry ItemId = "Weapon_<id>".
		local weaponId = string.match(itemId, "^Weapon_(.+)$")
		local def = weaponId and Weapons.List[weaponId]
		if def then
			return Weapons.SellByRarity[def.Rarity or 1] or 4
		end
		-- The starter club.
		if itemId == "StarterClub" then
			return Weapons.SellByRarity[0]
		end
		-- Salvage loot tools.
		if string.match(itemId, "^Loot_") then
			return Weapons.LootSellValue
		end
	end
	if typeof(rarity) == "number" then
		return Weapons.SellByRarity[rarity] or 4
	end
	-- Anything else the merchant will still take for a couple of coins.
	return 2
end

function Weapons.get(id: string): { [string]: any }?
	return Weapons.List[id]
end

function Weapons.isRanged(id: string): boolean
	local w = Weapons.List[id]
	return w ~= nil and w.Class == "ranged"
end

function Weapons.isMelee(id: string): boolean
	local w = Weapons.List[id]
	return w ~= nil and w.Class == "melee"
end

function Weapons.ammoAttribute(ammoId: string): string?
	local a = Weapons.Ammo[ammoId]
	return a and a.Attribute
end

-- Weighted random weapon id for island loot rolls.
function Weapons.rollLootWeapon(rng: (number, number) -> number): string
	local total = 0
	for _, w in Weapons.LootWeights do
		total += w
	end
	local pick = rng(1, total)
	local acc = 0
	for id, w in Weapons.LootWeights do
		acc += w
		if pick <= acc then
			return id
		end
	end
	return "Pistol"
end

return Weapons
