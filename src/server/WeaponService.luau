-- Server authority for ALL weapons' ranged fire, ammo reserves, player currency,
-- weapon/ammo granting, world pickups and merchant crafting/buying grants.
--
-- Ammo reserves + currency live as Player attributes so they replicate to the owning
-- client for the HUD with no extra remote:
--   Ammo_<Type>  (e.g. Ammo_Bullet)   ·   Doubloons   ·   Scrap
--
-- Ranged fire is fully server-validated: cooldown, chamber (Tool "Loaded" attribute),
-- raycast (per-pellet spread), damage. Melee stays in MeleeService.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local WeaponToolFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("WeaponToolFactory"))

local WeaponService = {}

WeaponService._Toast = nil :: RemoteEvent?
WeaponService._WeaponFx = nil :: RemoteEvent?
WeaponService._lastShotAt = {} :: { [number]: number }
WeaponService._reloadingUntil = {} :: { [number]: number }
WeaponService._started = false
-- Optional hook: called when an NPC humanoid is damaged by a player (isle defense).
WeaponService.onNpcDamaged = nil :: ((Model, Player) -> ())?

local function toast(player: Player, message: string, kind: string)
	if WeaponService._Toast then
		WeaponService._Toast:FireClient(player, message, kind)
	end
end

-- === Currency & ammo (Player attributes) =================================

function WeaponService.getCurrency(player: Player, currencyId: string): number
	local def = Config.Currency[currencyId]
	if not def then
		return 0
	end
	local v = player:GetAttribute(def.Attribute)
	return if typeof(v) == "number" then v else 0
end

function WeaponService.addCurrency(player: Player, currencyId: string, amount: number)
	local def = Config.Currency[currencyId]
	if not def then
		return
	end
	local cur = WeaponService.getCurrency(player, currencyId)
	player:SetAttribute(def.Attribute, math.max(0, cur + amount))
end

function WeaponService.spendCurrency(player: Player, currencyId: string, amount: number): boolean
	local cur = WeaponService.getCurrency(player, currencyId)
	if cur < amount then
		return false
	end
	local def = Config.Currency[currencyId]
	player:SetAttribute(def.Attribute, cur - amount)
	return true
end

function WeaponService.getAmmo(player: Player, ammoId: string): number
	local attr = Weapons.ammoAttribute(ammoId)
	if not attr then
		return 0
	end
	local v = player:GetAttribute(attr)
	return if typeof(v) == "number" then v else 0
end

function WeaponService.giveAmmo(player: Player, ammoId: string, amount: number)
	local ammo = Weapons.Ammo[ammoId]
	if not ammo then
		return
	end
	local cur = WeaponService.getAmmo(player, ammoId)
	player:SetAttribute(ammo.Attribute, math.clamp(cur + amount, 0, ammo.Max))
end

function WeaponService.initPlayer(player: Player)
	for currencyId, def in Config.Currency do
		if player:GetAttribute(def.Attribute) == nil then
			player:SetAttribute(def.Attribute, def.StartAmount or 0)
		end
	end
	for _, ammo in Weapons.Ammo do
		if player:GetAttribute(ammo.Attribute) == nil then
			player:SetAttribute(ammo.Attribute, 0)
		end
	end
end

-- === Granting ============================================================

local function findWeaponTool(player: Player, weaponId: string): Tool?
	local function scan(container: Instance?): Tool?
		if not container then
			return nil
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("WeaponId") == weaponId then
				return child
			end
		end
		return nil
	end
	return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
end

function WeaponService.giveWeapon(player: Player, weaponId: string, silent: boolean?): boolean
	local def = Weapons.get(weaponId)
	if not def then
		return false
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end
	if findWeaponTool(player, weaponId) then
		if not silent then
			toast(player, `You already carry a {def.Name}.`, "info")
		end
		return false
	end
	local tool = WeaponToolFactory.createTool(weaponId)
	if not tool then
		return false
	end
	tool.Parent = backpack
	if not silent then
		toast(player, `Picked up a {def.Name}!`, "success")
	end
	return true
end

-- === World pickups =======================================================

function WeaponService.attachPickupPrompt(model: Model)
	local primary = model.PrimaryPart or model:FindFirstChild("Primary")
	if not (primary and primary:IsA("BasePart")) then
		return
	end
	if primary:FindFirstChild("WeaponPickupPrompt") then
		return
	end
	local weaponId = model:GetAttribute("WeaponId")
	local def = typeof(weaponId) == "string" and Weapons.get(weaponId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WeaponPickupPrompt"
	prompt.ActionText = "Take"
	prompt.ObjectText = if def then def.Name else "Weapon"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = Config.Loot.PickupPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = primary

	prompt.Triggered:Connect(function(player: Player)
		if typeof(weaponId) ~= "string" then
			return
		end
		if WeaponService.giveWeapon(player, weaponId) then
			-- Toss in a little starter ammo so a looted gun isn't dead weight.
			if def and def.Class == "ranged" and def.Ammo then
				WeaponService.giveAmmo(player, def.Ammo, Weapons.AmmoBundle[def.Ammo] or 6)
			end
			model:Destroy()
		end
	end)
end

function WeaponService.spawnWeaponPickup(parent: Instance, weaponId: string, cf: CFrame): Model?
	local model = WeaponToolFactory.createWorldPickup(parent, weaponId, cf)
	if model then
		WeaponService.attachPickupPrompt(model)
	end
	return model
end

-- === Ranged fire =========================================================

local function equippedRanged(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and (child:GetAttribute("Ranged") == true or child:GetAttribute("SurviveGun") == true) then
			return child
		end
	end
	return nil
end

local function weaponDefForTool(tool: Tool): { [string]: any }?
	local id = tool:GetAttribute("WeaponId")
	if typeof(id) == "string" then
		return Weapons.get(id)
	end
	-- Legacy flintlock (from old chests) behaves like a pistol with no ammo cost.
	if tool:GetAttribute("SurviveGun") == true then
		return {
			Id = "Flintlock",
			Name = "Flintlock",
			Class = "ranged",
			Damage = Config.Islands.Gun.Damage,
			Cooldown = Config.Islands.Gun.Cooldown,
			Range = Config.Islands.Gun.Range,
			Ammo = nil,
			MagSize = 1,
			Pellets = 1,
			Spread = 0.01,
			ReloadTime = 0,
		}
	end
	return nil
end

function WeaponService.reload(player: Player): boolean
	local tool = equippedRanged(player)
	if not tool then
		return false
	end
	local def = weaponDefForTool(tool)
	if not def or not def.Ammo then
		return false
	end
	local loaded = tool:GetAttribute("Loaded") or 0
	if typeof(loaded) ~= "number" then
		loaded = 0
	end
	local magSize = def.MagSize or 1
	if loaded >= magSize then
		return false
	end
	local reserve = WeaponService.getAmmo(player, def.Ammo)
	if reserve <= 0 then
		toast(player, `Out of {Weapons.Ammo[def.Ammo].Label}.`, "error")
		return false
	end
	local need = magSize - loaded
	local take = math.min(need, reserve)

	WeaponService._reloadingUntil[player.UserId] = os.clock() + (def.ReloadTime or 0)
	task.delay(def.ReloadTime or 0, function()
		if not player.Parent then
			return
		end
		local live = equippedRanged(player)
		if live ~= tool then
			return
		end
		-- Recompute reserve at completion in case it changed
		local reserveNow = WeaponService.giveAmmoConsume(player, def.Ammo, take)
		tool:SetAttribute("Loaded", (tool:GetAttribute("Loaded") or 0) + reserveNow)
	end)
	return true
end

-- Consume up to `amount` ammo from reserve; returns amount actually consumed.
function WeaponService.giveAmmoConsume(player: Player, ammoId: string, amount: number): number
	local have = WeaponService.getAmmo(player, ammoId)
	local take = math.min(have, amount)
	if take > 0 then
		local ammo = Weapons.Ammo[ammoId]
		player:SetAttribute(ammo.Attribute, have - take)
	end
	return take
end

function WeaponService.tryShoot(player: Player, look: Vector3): boolean
	if typeof(look) ~= "Vector3" then
		return false
	end
	local tool = equippedRanged(player)
	if not tool then
		return false
	end
	local def = weaponDefForTool(tool)
	if not def then
		return false
	end

	local now = os.clock()
	local last = WeaponService._lastShotAt[player.UserId] or 0
	if now - last < (def.Cooldown or 0.5) then
		return false
	end
	if (WeaponService._reloadingUntil[player.UserId] or 0) > now then
		return false
	end

	-- Ammo / chamber handling
	if def.Ammo then
		local loaded = tool:GetAttribute("Loaded")
		if typeof(loaded) ~= "number" then
			loaded = 0
		end
		if loaded <= 0 then
			-- Instant-draw weapons (bow) pull straight from the reserve.
			if (def.ReloadTime or 0) <= 0 and WeaponService.getAmmo(player, def.Ammo) > 0 then
				WeaponService.giveAmmoConsume(player, def.Ammo, 1)
				loaded = 1
			else
				toast(player, `Empty — press R to reload {Weapons.Ammo[def.Ammo].Label}.`, "error")
				return false
			end
		end
		tool:SetAttribute("Loaded", loaded - 1)
	end

	WeaponService._lastShotAt[player.UserId] = now

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local originPart = if head and head:IsA("BasePart")
		then head
		elseif root and root:IsA("BasePart") then root
		else nil
	if not originPart then
		return false
	end

	local baseDir = look.Unit
	local origin = originPart.Position + baseDir * 1.5

	-- Broadcast FX (muzzle flash / tracer) so all clients can render the shot.
	if WeaponService._WeaponFx then
		WeaponService._WeaponFx:FireAllClients(player.UserId, def.Id, origin, baseDir)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local pellets = def.Pellets or 1
	local spread = def.Spread or 0
	local range = def.Range or 200

	for _ = 1, pellets do
		local dir = baseDir
		if spread > 0 then
			dir = (baseDir + Vector3.new(
				(math.random() - 0.5) * spread * 2,
				(math.random() - 0.5) * spread * 2,
				(math.random() - 0.5) * spread * 2
			)).Unit
		end

		local result = Workspace:Raycast(origin, dir * range, params)
		if result then
			local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
			if hitModel then
				local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
				local isNpc = hitModel:GetAttribute("IsNpc") == true or hitModel:GetAttribute("IsPirate") == true
				if humanoid and humanoid.Health > 0 and isNpc then
					humanoid:TakeDamage(def.Damage)
					if WeaponService.onNpcDamaged then
						WeaponService.onNpcDamaged(hitModel, player)
					end
				end
			end
		end
	end

	return true
end

function WeaponService.start(remotes: {
	Toast: RemoteEvent,
	WeaponFx: RemoteEvent,
})
	if WeaponService._started then
		return
	end
	WeaponService._started = true
	WeaponService._Toast = remotes.Toast
	WeaponService._WeaponFx = remotes.WeaponFx

	for _, player in Players:GetPlayers() do
		WeaponService.initPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		WeaponService.initPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		WeaponService._lastShotAt[player.UserId] = nil
		WeaponService._reloadingUntil[player.UserId] = nil
	end)
end

return WeaponService
