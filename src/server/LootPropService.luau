-- Server authority for loot props: drag, drop, inventory pickup, weld / unweld to crew rafts.
-- Welded props parent under the raft Model so StarterBaseService.shiftModel moves them with the deck.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local LootPropFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("LootPropFactory"))
local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))

local LootPropService = {}

LootPropService._propsById = {} :: { [string]: Model }
LootPropService._grabByUser = {} :: { [number]: string }
LootPropService._Toast = nil :: RemoteEvent?
LootPropService._getPartyCode = nil :: ((Player) -> string?)?
LootPropService._started = false

local function lobbyRoot(): Folder
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if root and root:IsA("Folder") then
		return root
	end
	return LobbyWorld.ensure()
end

local function worldLootFolder(): Folder
	local root = lobbyRoot()
	local folder = root:FindFirstChild("WorldLoot")
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "WorldLoot"
	folder.Parent = root
	return folder
end

local function toast(player: Player, message: string, kind: string)
	if LootPropService._Toast then
		LootPropService._Toast:FireClient(player, message, kind)
	end
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function registerProp(model: Model)
	local id = model:GetAttribute("PropId")
	if typeof(id) ~= "string" then
		return
	end
	LootPropService._propsById[id] = model
	model.Destroying:Connect(function()
		if LootPropService._propsById[id] == model then
			LootPropService._propsById[id] = nil
		end
	end)
end

local function setModelCFrame(model: Model, cf: CFrame)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local delta = cf * primary.CFrame:Inverse()
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CFrame = delta * desc.CFrame
			desc.Anchored = true
			desc.AssemblyLinearVelocity = Vector3.zero
			desc.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function findCrewRaftNear(player: Player, pos: Vector3): (Model?, BasePart?)
	local code = LootPropService._getPartyCode and LootPropService._getPartyCode(player)
	if not code then
		return nil, nil
	end
	local raft = StarterBaseService.getBaseModel(code)
	if not raft then
		return nil, nil
	end
	local deck = raft.PrimaryPart or raft:FindFirstChild("Deck")
	if not (deck and deck:IsA("BasePart")) then
		return nil, nil
	end
	local flat = Vector3.new(pos.X - deck.Position.X, 0, pos.Z - deck.Position.Z)
	local half = math.max(deck.Size.X, deck.Size.Z) * 0.5 + Config.Loot.WeldDeckRange * 0.35
	if flat.Magnitude > half then
		return nil, nil
	end
	return raft, deck
end

local function refreshPrompts(model: Model)
	LootPropFactory.attachPickupPrompt(model)
	LootPropFactory.attachWeldPrompt(model)
end

local function wirePromptTriggers(model: Model)
	local primary = model.PrimaryPart
	if not primary then
		return
	end

	local pickup = primary:FindFirstChild("LootPickupPrompt")
	if pickup and pickup:IsA("ProximityPrompt") and not pickup:GetAttribute("Wired") then
		pickup:SetAttribute("Wired", true)
		pickup.Triggered:Connect(function(player: Player)
			LootPropService.tryPickup(player, model)
		end)
	end

	local weldPrompt = primary:FindFirstChild("LootWeldPrompt")
	if weldPrompt and weldPrompt:IsA("ProximityPrompt") and not weldPrompt:GetAttribute("Wired") then
		weldPrompt:SetAttribute("Wired", true)
		weldPrompt.Triggered:Connect(function(player: Player)
			if model:GetAttribute("Welded") == true then
				LootPropService.tryUnweld(player, model)
			else
				LootPropService.tryWeld(player, model)
			end
		end)
	end
end

local function wireProp(model: Model)
	if model:GetAttribute("LootWired") == true then
		refreshPrompts(model)
		wirePromptTriggers(model)
		return
	end
	model:SetAttribute("LootWired", true)
	registerProp(model)
	refreshPrompts(model)
	wirePromptTriggers(model)
end

function LootPropService.registerExisting(model: Model)
	if model:GetAttribute("IsLootProp") ~= true then
		return
	end
	wireProp(model)
end

function LootPropService.spawnKind(kind: string, parent: Instance?, cf: CFrame, welded: boolean?): Model
	local folder = parent or worldLootFolder()
	local model = LootPropFactory.spawnFromKind(kind :: any, folder, cf)
	if welded then
		model:SetAttribute("Welded", true)
	end
	wireProp(model)
	return model
end

function LootPropService.attachStarterTorch(raft: Model, deck: BasePart)
	-- One flaming torch already welded near the bow for night light
	local topY = deck.Position.Y + deck.Size.Y * 0.5
	local bow = deck.CFrame * CFrame.new(-18, 0, -deck.Size.Z * 0.32)
	local torchCf = CFrame.new(bow.Position.X, topY + 1.7, bow.Position.Z)

	local kit = raft:FindFirstChild("StarterKit")
	local parent = if kit then kit else raft
	local torch = LootPropFactory.createTorchWorld(parent, torchCf)
	torch.Name = "StarterTorch"
	torch:SetAttribute("Welded", true)
	torch:SetAttribute("StarterTorch", true)
	wireProp(torch)
	return torch
end

function LootPropService.tryPickup(player: Player, model: Model): boolean
	if model:GetAttribute("IsLootProp") ~= true then
		return false
	end
	-- The merchant (and any NoPickup prop) can be dragged / welded but never pocketed.
	if model:GetAttribute("NoPickup") == true then
		return false
	end
	if model:GetAttribute("GrabbedBy") ~= 0 and model:GetAttribute("GrabbedBy") ~= player.UserId then
		toast(player, "Someone else has that.", "error")
		return false
	end

	local root = getRoot(player)
	local primary = model.PrimaryPart
	if not (root and primary) then
		return false
	end
	if (root.Position - primary.Position).Magnitude > Config.Loot.PickupPromptDistance + 6 then
		toast(player, "Too far to pick up.", "error")
		return false
	end

	local kind = model:GetAttribute("LootKind")
	if typeof(kind) ~= "string" then
		return false
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end

	-- Clear grab if this player was dragging it
	if LootPropService._grabByUser[player.UserId] == model:GetAttribute("PropId") then
		LootPropService._grabByUser[player.UserId] = nil
		model:SetAttribute("GrabbedBy", 0)
	end

	local tool = LootPropFactory.createTool(kind :: any)
	tool.Parent = backpack
	model:Destroy()
	toast(player, `Picked up {kind}.`, "success")
	return true
end

function LootPropService.tryWeld(player: Player, model: Model): boolean
	if model:GetAttribute("Weldable") ~= true then
		return false
	end
	if model:GetAttribute("Welded") == true then
		toast(player, "Already welded.", "info")
		return false
	end
	if model:GetAttribute("GrabbedBy") ~= 0 and model:GetAttribute("GrabbedBy") ~= player.UserId then
		return false
	end

	local primary = model.PrimaryPart
	if not primary then
		return false
	end

	local raft, deck = findCrewRaftNear(player, primary.Position)
	if not (raft and deck) then
		toast(player, "Bring it onto your raft to weld.", "error")
		return false
	end

	-- Snap lightly onto deck surface if floating too high / low
	local topY = deck.Position.Y + deck.Size.Y * 0.5
	local cf = primary.CFrame
	if math.abs(cf.Position.Y - (topY + primary.Size.Y * 0.5)) > 8 then
		cf = CFrame.new(cf.Position.X, topY + primary.Size.Y * 0.5 + 0.1, cf.Position.Z) * (cf - cf.Position)
		setModelCFrame(model, cf)
	end

	model.Parent = raft
	model:SetAttribute("Welded", true)
	model:SetAttribute("GrabbedBy", 0)
	if LootPropService._grabByUser[player.UserId] == model:GetAttribute("PropId") then
		LootPropService._grabByUser[player.UserId] = nil
	end
	refreshPrompts(model)
	wirePromptTriggers(model)
	toast(player, "Welded to the raft.", "success")
	return true
end

function LootPropService.tryUnweld(player: Player, model: Model): boolean
	if model:GetAttribute("Welded") ~= true then
		return false
	end
	local code = LootPropService._getPartyCode and LootPropService._getPartyCode(player)
	if not code then
		return false
	end
	local raft = StarterBaseService.getBaseModel(code)
	if not raft or not model:IsDescendantOf(raft) then
		toast(player, "That's not on your raft.", "error")
		return false
	end

	model.Parent = worldLootFolder()
	model:SetAttribute("Welded", false)
	refreshPrompts(model)
	wirePromptTriggers(model)
	toast(player, "Unwelded — drag it wherever you want.", "info")
	return true
end

function LootPropService.beginDrag(player: Player, propId: string): boolean
	if typeof(propId) ~= "string" then
		return false
	end
	local model = LootPropService._propsById[propId]
	if not model or not model.Parent then
		return false
	end
	if model:GetAttribute("Draggable") ~= true then
		return false
	end

	local held = LootPropService._grabByUser[player.UserId]
	if held and held ~= propId then
		toast(player, "Drop what you're holding first.", "error")
		return false
	end

	local grabbedBy = model:GetAttribute("GrabbedBy")
	if typeof(grabbedBy) == "number" and grabbedBy ~= 0 and grabbedBy ~= player.UserId then
		toast(player, "Someone else is dragging that.", "error")
		return false
	end

	local root = getRoot(player)
	local primary = model.PrimaryPart
	if not (root and primary) then
		return false
	end
	if (root.Position - primary.Position).Magnitude > Config.Loot.DragRange + 8 then
		return false
	end

	-- Auto-unweld when you start dragging a welded piece; always lift into WorldLoot while free
	if model:GetAttribute("Welded") == true then
		local code = LootPropService._getPartyCode and LootPropService._getPartyCode(player)
		local raft = code and StarterBaseService.getBaseModel(code)
		if raft and model:IsDescendantOf(raft) then
			model.Parent = worldLootFolder()
			model:SetAttribute("Welded", false)
			refreshPrompts(model)
			wirePromptTriggers(model)
		else
			toast(player, "Can't take that off another crew's raft.", "error")
			return false
		end
	elseif not model:IsDescendantOf(worldLootFolder()) then
		model.Parent = worldLootFolder()
	end

	LootPropService._grabByUser[player.UserId] = propId
	model:SetAttribute("GrabbedBy", player.UserId)
	-- Soften collision while dragging so it doesn't shove the player
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
		end
	end
	return true
end

function LootPropService.updateDrag(player: Player, propId: string, cf: CFrame): boolean
	if typeof(propId) ~= "string" or typeof(cf) ~= "CFrame" then
		return false
	end
	if LootPropService._grabByUser[player.UserId] ~= propId then
		return false
	end
	local model = LootPropService._propsById[propId]
	if not model or model:GetAttribute("GrabbedBy") ~= player.UserId then
		return false
	end

	local root = getRoot(player)
	if not root then
		return false
	end

	-- Clamp so you can't fling loot across the map
	local pos = cf.Position
	local to = pos - root.Position
	local maxR = Config.Loot.DragRange + 4
	if to.Magnitude > maxR then
		pos = root.Position + to.Unit * maxR
		cf = CFrame.new(pos) * (cf - cf.Position)
	end
	-- Keep above water a bit
	local minY = Config.StarterBase.WaterRescueY + 1.5
	if cf.Position.Y < minY then
		cf = CFrame.new(cf.Position.X, minY, cf.Position.Z) * (cf - cf.Position)
	end

	setModelCFrame(model, cf)
	return true
end

function LootPropService.endDrag(player: Player, propId: string?): boolean
	local id = propId or LootPropService._grabByUser[player.UserId]
	if typeof(id) ~= "string" then
		return false
	end
	if LootPropService._grabByUser[player.UserId] ~= id then
		return false
	end

	local model = LootPropService._propsById[id]
	LootPropService._grabByUser[player.UserId] = nil
	if not model then
		return false
	end
	model:SetAttribute("GrabbedBy", 0)

	local kind = model:GetAttribute("LootKind")
	local restoreCollide = kind ~= "Torch" -- torches stay non-blocking-ish; walls need collide
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			if kind == "Torch" then
				desc.CanCollide = desc.Name == "Primary"
			elseif kind == "Plank" then
				desc.CanCollide = desc.Name == "Primary"
			else
				desc.CanCollide = restoreCollide or desc.Name == "Primary"
			end
			if desc.Name ~= "Primary" and (kind == "Wall" or kind == "Crate") then
				desc.CanCollide = false
			end
		end
	end
	if model.PrimaryPart then
		model.PrimaryPart.CanCollide = true
	end

	-- Auto-suggest weld if dropped on your raft
	local primary = model.PrimaryPart
	if primary then
		local raft = findCrewRaftNear(player, primary.Position)
		if raft then
			toast(player, "On your raft — press X / use Weld to attach.", "info")
		end
	end
	return true
end

function LootPropService.tryPlaceFromTool(player: Player, look: Vector3): boolean
	local character = player.Character
	if not character then
		return false
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not (tool and tool:GetAttribute("IsLootTool") == true) then
		return false
	end
	local kind = tool:GetAttribute("LootKind")
	if typeof(kind) ~= "string" then
		return false
	end
	local root = getRoot(player)
	if not root then
		return false
	end

	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		flat = root.CFrame.LookVector
		flat = Vector3.new(flat.X, 0, flat.Z)
	end
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	local placePos = root.Position + flat * 6 + Vector3.new(0, 1.5, 0)
	local cf = CFrame.lookAt(placePos, placePos + flat)
	local model = LootPropService.spawnKind(kind, worldLootFolder(), cf, false)
	tool:Destroy()
	toast(player, `Placed {kind}. Hold RMB / RT to drag it.`, "success")
	return true
end

function LootPropService.start(
	toastRemote: RemoteEvent,
	getPartyCode: (Player) -> string?,
	remotes: {
		DragStart: RemoteEvent,
		DragUpdate: RemoteEvent,
		DragEnd: RemoteEvent,
		WeldProp: RemoteEvent,
		UnweldProp: RemoteEvent,
		PlaceLoot: RemoteEvent,
	}
)
	if LootPropService._started then
		return
	end
	LootPropService._started = true
	LootPropService._Toast = toastRemote
	LootPropService._getPartyCode = getPartyCode

	worldLootFolder()

	remotes.DragStart.OnServerEvent:Connect(function(player, propId)
		LootPropService.beginDrag(player, propId)
	end)
	remotes.DragUpdate.OnServerEvent:Connect(function(player, propId, cf)
		LootPropService.updateDrag(player, propId, cf)
	end)
	remotes.DragEnd.OnServerEvent:Connect(function(player, propId)
		LootPropService.endDrag(player, propId)
	end)
	remotes.WeldProp.OnServerEvent:Connect(function(player, propId)
		if typeof(propId) ~= "string" then
			return
		end
		local model = LootPropService._propsById[propId]
		if model then
			LootPropService.tryWeld(player, model)
		end
	end)
	remotes.UnweldProp.OnServerEvent:Connect(function(player, propId)
		if typeof(propId) ~= "string" then
			return
		end
		local model = LootPropService._propsById[propId]
		if model then
			LootPropService.tryUnweld(player, model)
		end
	end)
	remotes.PlaceLoot.OnServerEvent:Connect(function(player, look)
		if typeof(look) ~= "Vector3" then
			return
		end
		LootPropService.tryPlaceFromTool(player, look)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local id = LootPropService._grabByUser[player.UserId]
		if id then
			LootPropService.endDrag(player, id)
		end
	end)
end

return LootPropService
