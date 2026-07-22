-- Shared armor definitions for Survive at Sea.
-- Single source of truth for the server (authoritative wear + damage reduction) and the
-- client HUD. Kept OUT of Config.luau on purpose (same as Weapons.luau) so the headless
-- PortalLoad test — which only loads Config / PartyCode / Types — never touches it.
--
-- Armor pieces are WORN (not held): picking one up equips it to a body slot and raises
-- the player's damage reduction. Reuses the shared rarity tiers from Weapons.luau so a
-- looted helmet reads the same grey/green/blue/purple/gold as a looted gun.
--
-- Slots: "Head" | "Body" | "Legs". One piece per slot; a better piece replaces the old
-- one in that slot. Total reduction is the sum of worn Defense values, clamped in
-- ArmorService so armor can never make you invulnerable.

local Weapons = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Weapons"))

local Armor = {}

export type ArmorSlot = "Head" | "Body" | "Legs"

-- Defense is fractional incoming-damage reduction contributed by that piece (0..1).
-- A full common set ≈ 0.30, a full legendary set ≈ 0.70 (clamped by MaxReduction).
Armor.MaxReduction = 0.78

-- Reuse the weapon rarity palette so tiers look identical across all loot.
function Armor.rarityInfo(rarity: number?): { Name: string, Color: Color3 }
	return Weapons.rarityInfo(rarity)
end

Armor.List = {
	-- === Head =============================================================
	ClothHood = {
		Id = "ClothHood",
		Name = "Cloth Hood",
		Slot = "Head",
		Defense = 0.06,
		Rarity = 1,
		Color = Color3.fromRGB(120, 108, 86),
		Material = Enum.Material.Fabric,
	},
	LeatherCap = {
		Id = "LeatherCap",
		Name = "Leather Cap",
		Slot = "Head",
		Defense = 0.10,
		Rarity = 2,
		Color = Color3.fromRGB(96, 64, 38),
		Material = Enum.Material.Fabric,
	},
	IronHelm = {
		Id = "IronHelm",
		Name = "Iron Helm",
		Slot = "Head",
		Defense = 0.15,
		Rarity = 3,
		Color = Color3.fromRGB(150, 156, 164),
		Material = Enum.Material.Metal,
	},
	CorsairHelm = {
		Id = "CorsairHelm",
		Name = "Corsair Helm",
		Slot = "Head",
		Defense = 0.20,
		Rarity = 4,
		Color = Color3.fromRGB(120, 96, 176),
		Material = Enum.Material.Metal,
	},

	-- === Body =============================================================
	ClothTunic = {
		Id = "ClothTunic",
		Name = "Cloth Tunic",
		Slot = "Body",
		Defense = 0.10,
		Rarity = 1,
		Color = Color3.fromRGB(132, 120, 96),
		Material = Enum.Material.Fabric,
	},
	LeatherVest = {
		Id = "LeatherVest",
		Name = "Leather Vest",
		Slot = "Body",
		Defense = 0.16,
		Rarity = 2,
		Color = Color3.fromRGB(104, 68, 40),
		Material = Enum.Material.Fabric,
	},
	IronChestplate = {
		Id = "IronChestplate",
		Name = "Iron Chestplate",
		Slot = "Body",
		Defense = 0.24,
		Rarity = 3,
		Color = Color3.fromRGB(152, 158, 166),
		Material = Enum.Material.Metal,
	},
	CorsairCuirass = {
		Id = "CorsairCuirass",
		Name = "Corsair Cuirass",
		Slot = "Body",
		Defense = 0.32,
		Rarity = 4,
		Color = Color3.fromRGB(126, 100, 182),
		Material = Enum.Material.Metal,
	},
	WardenPlate = {
		Id = "WardenPlate",
		Name = "Warden's Plate",
		Slot = "Body",
		Defense = 0.40,
		Rarity = 5,
		Color = Color3.fromRGB(226, 176, 92),
		Material = Enum.Material.Metal,
	},

	-- === Legs =============================================================
	ClothWraps = {
		Id = "ClothWraps",
		Name = "Cloth Wraps",
		Slot = "Legs",
		Defense = 0.06,
		Rarity = 1,
		Color = Color3.fromRGB(126, 114, 90),
		Material = Enum.Material.Fabric,
	},
	LeatherGreaves = {
		Id = "LeatherGreaves",
		Name = "Leather Greaves",
		Slot = "Legs",
		Defense = 0.10,
		Rarity = 2,
		Color = Color3.fromRGB(100, 66, 40),
		Material = Enum.Material.Fabric,
	},
	IronGreaves = {
		Id = "IronGreaves",
		Name = "Iron Greaves",
		Slot = "Legs",
		Defense = 0.15,
		Rarity = 3,
		Color = Color3.fromRGB(148, 154, 162),
		Material = Enum.Material.Metal,
	},
}

-- Relative loot weights. Common cloth pieces show up the most; legendary plate is a
-- once-a-voyage prize. Weighted so armor as a whole is a meaningful but not guaranteed find.
Armor.LootWeights = {
	ClothHood = 20,
	ClothTunic = 22,
	ClothWraps = 20,
	LeatherCap = 14,
	LeatherVest = 15,
	LeatherGreaves = 13,
	IronHelm = 8,
	IronChestplate = 9,
	IronGreaves = 7,
	CorsairHelm = 4,
	CorsairCuirass = 4,
	WardenPlate = 2,
}

function Armor.get(id: string): { [string]: any }?
	return Armor.List[id]
end

-- Weighted random armor id for island loot rolls. `rng(lo, hi)` mirrors the signature
-- used by Weapons.rollLootWeapon so callers can pass the same math.random shim.
function Armor.rollLootArmor(rng: (number, number) -> number): string
	local total = 0
	for _, w in Armor.LootWeights do
		total += w
	end
	local pick = rng(1, total)
	local acc = 0
	for id, w in Armor.LootWeights do
		acc += w
		if pick <= acc then
			return id
		end
	end
	return "ClothTunic"
end

return Armor
