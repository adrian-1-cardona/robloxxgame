-- Server authority for wearable armor.
--
-- Armor is WORN, not held: walking into a piece's ProximityPrompt equips it to a body
-- slot (Head / Body / Legs), welding cosmetic geometry to the character and raising the
-- player's damage reduction. One piece per slot; picking up a piece for a slot you already
-- wear swaps it.
--
-- Damage reduction is exposed two ways:
--   * Player attribute "ArmorRating" (0..MaxReduction) — replicates to the owning client
--     for the HUD.
--   * ArmorService.applyPlayerDamage(player, amount) — the single choke point every source
--     of player damage should call so armor is always respected.
--
-- Worn state survives respawns: on CharacterAdded we re-weld whatever the player had on.
-- (This is a session game with no DataStores, so armor is only lost on leave, not death.)

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Armor = require(Shared:WaitForChild("Armor"))

local ArmorToolFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("ArmorToolFactory"))

local ArmorService = {}

-- userId -> { Head = armorId?, Body = armorId?, Legs = armorId? }
ArmorService._wornByUser = {} :: { [number]: { [string]: string } }
ArmorService._Toast = nil :: RemoteEvent?
ArmorService._started = false

local function toast(player: Player, message: string, kind: string)
	if ArmorService._Toast then
		ArmorService._Toast:FireClient(player, message, kind)
	end
end

local function wornSet(userId: number): { [string]: string }
	local set = ArmorService._wornByUser[userId]
	if not set then
		set = {}
		ArmorService._wornByUser[userId] = set
	end
	return set
end

-- Sum the worn pieces' Defense, clamped so armor can never fully negate damage.
local function computeRating(userId: number): number
	local total = 0
	for _, armorId in wornSet(userId) do
		local def = Armor.get(armorId)
		if def then
			total += def.Defense or 0
		end
	end
	return math.clamp(total, 0, Armor.MaxReduction)
end

local function refreshRating(player: Player)
	player:SetAttribute("ArmorRating", computeRating(player.UserId))
end

-- Weld the geometry for every worn slot onto the (live) character.
local function applyVisuals(player: Player)
	local character = player.Character
	if not character then
		return
	end
	-- Clear any stale armor folders first so a swap / respawn never doubles up.
	for _, child in character:GetChildren() do
		if child:IsA("Folder") and string.sub(child.Name, 1, 6) == "Armor_" then
			child:Destroy()
		end
	end
	for _, armorId in wornSet(player.UserId) do
		ArmorToolFactory.wearOnCharacter(character, armorId)
	end
end

-- === Public API ==========================================================

function ArmorService.getRating(player: Player): number
	return computeRating(player.UserId)
end

-- Equip a piece (swapping whatever's in that slot). Returns true if worn.
function ArmorService.wearArmor(player: Player, armorId: string, silent: boolean?): boolean
	local def = Armor.get(armorId)
	if not def then
		return false
	end
	local set = wornSet(player.UserId)
	local prev = set[def.Slot]
	if prev == armorId then
		if not silent then
			toast(player, `Already wearing {def.Name}.`, "info")
		end
		return false
	end
	set[def.Slot] = armorId
	applyVisuals(player)
	refreshRating(player)

	if not silent then
		local rating = math.floor(computeRating(player.UserId) * 100 + 0.5)
		toast(player, `Equipped {def.Name} — {rating}% armor.`, "success")
	end
	return true
end

-- The single choke point for damaging a player: applies worn armor reduction, then hits
-- the humanoid. Returns the damage actually dealt.
function ArmorService.applyPlayerDamage(player: Player, amount: number): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return 0
	end
	local rating = computeRating(player.UserId)
	local dealt = math.max(0, amount * (1 - rating))
	humanoid:TakeDamage(dealt)
	return dealt
end

function ArmorService.attachPickupPrompt(model: Model)
	local primary = model.PrimaryPart or model:FindFirstChild("Primary")
	if not (primary and primary:IsA("BasePart")) then
		return
	end
	if primary:FindFirstChild("ArmorPickupPrompt") then
		return
	end
	local armorId = model:GetAttribute("ArmorId")
	local def = typeof(armorId) == "string" and Armor.get(armorId)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ArmorPickupPrompt"
	prompt.ActionText = "Wear"
	prompt.ObjectText = if def then def.Name else "Armor"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = primary

	prompt.Triggered:Connect(function(player: Player)
		if typeof(armorId) ~= "string" then
			return
		end
		if ArmorService.wearArmor(player, armorId) then
			model:Destroy()
		end
	end)
end

function ArmorService.spawnArmorPickup(parent: Instance, armorId: string, cf: CFrame): Model?
	local model = ArmorToolFactory.createWorldPickup(parent, armorId, cf)
	if model then
		ArmorService.attachPickupPrompt(model)
	end
	return model
end

function ArmorService.start(remotes: { Toast: RemoteEvent })
	if ArmorService._started then
		return
	end
	ArmorService._started = true
	ArmorService._Toast = remotes.Toast

	local function hookPlayer(player: Player)
		if player:GetAttribute("ArmorRating") == nil then
			player:SetAttribute("ArmorRating", 0)
		end
		player.CharacterAdded:Connect(function()
			-- Re-weld worn armor after a respawn (defer so the rig exists first).
			task.defer(function()
				task.wait(0.2)
				if player.Parent then
					applyVisuals(player)
					refreshRating(player)
				end
			end)
		end)
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		ArmorService._wornByUser[player.UserId] = nil
	end)
end

return ArmorService
