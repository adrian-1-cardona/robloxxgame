-- Server-authoritative melee for the starter Club.
-- Client requests a swing; server checks equip + cooldown + range, then applies damage.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local MeleeService = {}

local lastSwingAt: { [number]: number } = {}
local MeleeSwingFx: RemoteEvent? = nil
local isHelming: ((Player) -> boolean)? = nil

local function equippedClub(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("MeleeWeapon") == true then
			return child
		end
	end
	return nil
end

local function rootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function humanoidOf(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function findDamageTarget(attacker: Player, origin: Vector3, look: Vector3): (Humanoid?, Model?)
	local range = Config.Club.Range
	local radius = Config.Club.HitRadius
	local forward = look.Unit
	local probe = origin + forward * (range * 0.55)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if attacker.Character then
		table.insert(exclude, attacker.Character)
	end
	overlap.FilterDescendantsInstances = exclude

	local parts = Workspace:GetPartBoundsInRadius(probe, radius + 1.5, overlap)
	local bestHumanoid: Humanoid? = nil
	local bestModel: Model? = nil
	local bestDist = math.huge

	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or model == attacker.Character then
			continue
		end
		local humanoid = humanoidOf(model)
		if not humanoid then
			continue
		end
		-- Only hit player characters for now (crew combat / future NPCs can widen this)
		local victimPlayer = Players:GetPlayerFromCharacter(model)
		if not victimPlayer then
			continue
		end

		local victimRoot = model:FindFirstChild("HumanoidRootPart")
		local targetPos = if victimRoot and victimRoot:IsA("BasePart") then victimRoot.Position else part.Position
		local toTarget = targetPos - origin
		local dist = toTarget.Magnitude
		if dist > range then
			continue
		end
		-- Must be roughly in front of the attacker
		if dist > 0.5 and toTarget.Unit:Dot(forward) < 0.25 then
			continue
		end
		if dist < bestDist then
			bestDist = dist
			bestHumanoid = humanoid
			bestModel = model
		end
	end

	return bestHumanoid, bestModel
end

function MeleeService.tryAttack(player: Player): boolean
	local tool = equippedClub(player)
	if not tool then
		return false
	end

	if isHelming and isHelming(player) then
		return false
	end

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local root = rootPart(player)
	if not root then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	local last = lastSwingAt[player.UserId] or 0
	if now - last < Config.Club.SwingCooldown then
		return false
	end
	lastSwingAt[player.UserId] = now

	-- Broadcast swing FX to nearby clients (including attacker for sync polish)
	if MeleeSwingFx then
		MeleeSwingFx:FireAllClients(player.UserId, tool.Name)
	end

	-- Brief hit window so the swing feels intentional, not instant sniper
	task.delay(Config.Club.HitWindow * 0.35, function()
		if not player.Parent then
			return
		end
		if equippedClub(player) ~= tool then
			return
		end
		local liveRoot = rootPart(player)
		if not liveRoot then
			return
		end
		local look = liveRoot.CFrame.LookVector
		local origin = liveRoot.Position + Vector3.new(0, 1.2, 0)
		local victimHumanoid = findDamageTarget(player, origin, look)
		if victimHumanoid then
			local damage = tool:GetAttribute("Damage")
			if typeof(damage) ~= "number" then
				damage = Config.Club.Damage
			end
			victimHumanoid:TakeDamage(damage :: number)
		end
	end)

	return true
end

function MeleeService.start(
	swingFxRemote: RemoteEvent,
	attackRemote: RemoteEvent,
	helmingCheck: ((Player) -> boolean)?
)
	MeleeSwingFx = swingFxRemote
	isHelming = helmingCheck

	attackRemote.OnServerEvent:Connect(function(player)
		MeleeService.tryAttack(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwingAt[player.UserId] = nil
	end)
end

return MeleeService
