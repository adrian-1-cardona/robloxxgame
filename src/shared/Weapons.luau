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
		ToolTip = "Wooden club — RMB / RT / tap to swing",
		Damage = 22,
		Cooldown = 0.55,
		Range = 7.5,
		HitRadius = 3.2,
		HitWindow = 0.22,
		SwingDuration = 0.35,
		Rarity = 0, -- starter; not part of loot rolls
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
		Rarity = 3,
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
		Rarity = 3,
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
		Rarity = 3,
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
		Rarity = 4,
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
Weapons.LootWeights = {
	Spear = 24,
	Bow = 20,
	Pistol = 22,
	Revolver = 12,
	Shotgun = 12,
	Rifle = 6,
	Musket = 14,
}

-- Ammo bundle sizes handed out by loot / merchant.
Weapons.AmmoBundle = {
	Bullet = 12,
	Shell = 6,
	Arrow = 10,
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
	{ Kind = "weapon", Weapon = "Shotgun", Currency = "Doubloons", Cost = 55, Label = "Buy Boarding Shotgun" },
	{ Kind = "weapon", Weapon = "Revolver", Currency = "Doubloons", Cost = 60, Label = "Buy Sea Revolver" },
	{ Kind = "weapon", Weapon = "Rifle", Currency = "Doubloons", Cost = 90, Label = "Buy Long Rifle" },
}

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
