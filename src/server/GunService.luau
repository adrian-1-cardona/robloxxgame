-- Flintlock tools looted from island raid houses.
-- Server-authoritative fire: client sends look, server raycasts + damages.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local GunService = {}

GunService._Toast = nil :: RemoteEvent?
GunService._lastShotAt = {} :: { [number]: number }

local function makeHandle(): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 0.35, 1.7)
	handle.Color = Color3.fromRGB(48, 34, 22)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.28, 0.28, 1.1)
	barrel.Color = Color3.fromRGB(55, 58, 62)
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Massless = true
	barrel.CFrame = handle.CFrame * CFrame.new(0, 0.12, -1.15)
	barrel.TopSurface = Enum.SurfaceType.Smooth
	barrel.BottomSurface = Enum.SurfaceType.Smooth

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = barrel
	weld.Parent = handle
	barrel.Parent = handle

	return handle
end

function GunService.createFlintlock(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Flintlock"
	tool.ToolTip = "Click / tap to fire"
	tool.RequiresHandle = true
	tool.CanBeDropped = true
	tool:SetAttribute("SurviveGun", true)

	local handle = makeHandle()
	handle.Parent = tool

	return tool
end

function GunService.playerHasFlintlock(player: Player): boolean
	local function scan(container: Instance?): boolean
		if not container then
			return false
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("SurviveGun") == true then
				return true
			end
		end
		return false
	end
	return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
end

function GunService.giveFlintlock(player: Player): boolean
	if GunService.playerHasFlintlock(player) then
		if GunService._Toast then
			GunService._Toast:FireClient(player, "You already carry a flintlock.", "info")
		end
		return false
	end
	local tool = GunService.createFlintlock()
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		tool:Destroy()
		return false
	end
	tool.Parent = backpack
	if GunService._Toast then
		GunService._Toast:FireClient(player, "Raided a flintlock — equip and fire!", "success")
	end
	return true
end

local function equippedGun(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("SurviveGun") == true then
			return child
		end
	end
	return nil
end

function GunService.tryShoot(player: Player, look: Vector3): boolean
	if typeof(look) ~= "Vector3" then
		return false
	end
	if look.Magnitude < 0.05 then
		return false
	end
	local tool = equippedGun(player)
	if not tool then
		return false
	end

	local now = os.clock()
	local last = GunService._lastShotAt[player.UserId] or 0
	if now - last < Config.Islands.Gun.Cooldown then
		return false
	end
	GunService._lastShotAt[player.UserId] = now

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

	local dir = look.Unit
	local range = Config.Islands.Gun.Range
	local origin = originPart.Position + dir * 1.2

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, dir * range, params)
	if not result then
		return true
	end

	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	if not hitModel then
		return true
	end
	local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return true
	end

	-- Don't friendly-fire other crew mates through this gun (still hits pirates / strangers)
	local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
	if hitPlayer and hitPlayer ~= player then
		-- Allow PvP lightly later; for now skip other players, focus on pirates
		if hitModel:GetAttribute("IsPirate") ~= true then
			return true
		end
	end

	humanoid:TakeDamage(Config.Islands.Gun.Damage)
	return true
end

function GunService.start(toastRemote: RemoteEvent)
	GunService._Toast = toastRemote
	Players.PlayerRemoving:Connect(function(player)
		GunService._lastShotAt[player.UserId] = nil
	end)
end

return GunService
