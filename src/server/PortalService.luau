-- Wires pier portal proximity prompts + walk-in triggers.
-- Portals are reusable boarding gates: they open create, never walk-join a crew.
-- Friends always join via code.
--
-- Resilient to Rojo live-sync / LobbyWorld.polish replacing Portals models or the
-- whole SurviveAtSeaLobby folder after boot (old ChildAdded connections go dead).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local PartyService = require(script.Parent.PartyService)

local PortalService = {}

local touchDebounce: { [string]: boolean } = {}
local wiredModels: { [Model]: boolean } = {}
local folderConnections: { RBXScriptConnection } = {}
local lobbyConnections: { RBXScriptConnection } = {}
local started = false
local toastRemote: RemoteEvent? = nil
local partyUpdatedRemote: RemoteEvent? = nil
local portalsUpdatedRemote: RemoteEvent? = nil

local function disconnectAll(connections: { RBXScriptConnection })
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
end

local function refreshPortalVisuals(portals)
	for _, info in portals do
		local model = LobbyBuilder.getPortalModel(info.portalIndex)
		if not model then
			continue
		end

		local promptAnchor = model:FindFirstChild("PromptAnchor")
		local prompt = promptAnchor and promptAnchor:FindFirstChild("BoardPrompt")

		LobbyBuilder.updatePortalSign(
			model,
			`Portal {info.portalIndex}`,
			"Form a private crew · friends join by code",
			Config.Theme.Foam
		)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.ActionText = "Create Crew"
			prompt.ObjectText = `Portal {info.portalIndex}`
			prompt.Enabled = true
		end
	end
end

local function handlePortalUse(player: Player, portalIndex: number)
	local toast = toastRemote
	local partyUpdated = partyUpdatedRemote
	if not (toast and partyUpdated) then
		return
	end

	if PartyService.isInParty(player) then
		toast:FireClient(player, "You're already on a crew — share your code from the HUD.", "info")
		return
	end

	toast:FireClient(player, "Pick crew size, then spawn on your plank. Friends join by code.", "info")
	partyUpdated:FireClient(player, {
		__openCreate = true,
		portalIndex = portalIndex,
	})
end

-- Map JSON may omit WalkTrigger; polish rebuilds usually add it, but Rojo can
-- re-sync the map afterward. Guarantee a touch volume so walk-in keeps working.
local function ensureWalkTrigger(model: Model): BasePart?
	local existing = model:FindFirstChild("WalkTrigger")
	if existing and existing:IsA("BasePart") then
		existing.CanCollide = false
		existing.CanTouch = true
		existing.CanQuery = false
		existing.Transparency = 1
		return existing
	end

	local pad = model:FindFirstChild("Pad")
	local anchor = if pad and pad:IsA("BasePart") then pad else model.PrimaryPart
	if not (anchor and anchor:IsA("BasePart")) then
		return nil
	end

	local trigger = Instance.new("Part")
	trigger.Name = "WalkTrigger"
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanTouch = true
	trigger.CanQuery = false
	trigger.CastShadow = false
	trigger.Transparency = 1
	trigger.Material = Enum.Material.SmoothPlastic
	trigger.Size = Vector3.new(10, 13, 9)
	trigger.CFrame = anchor.CFrame * CFrame.new(0, 7.5 - anchor.Size.Y * 0.5, 0.5)
	trigger.Parent = model
	return trigger
end

local function wirePortalModel(model: Model)
	if wiredModels[model] then
		return
	end

	local indexValue = model:FindFirstChild("PortalIndex")
	local promptAnchor = model:FindFirstChild("PromptAnchor")
	local prompt = promptAnchor and promptAnchor:FindFirstChild("BoardPrompt")
	if not (indexValue and indexValue:IsA("IntValue")) then
		return
	end

	local portalIndex = indexValue.Value
	wiredModels[model] = true

	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			handlePortalUse(player, portalIndex)
		end)
	end

	local walkTrigger = ensureWalkTrigger(model)
	if walkTrigger then
		walkTrigger.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if not character then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end

			local key = `{player.UserId}:{portalIndex}`
			if touchDebounce[key] then
				return
			end
			touchDebounce[key] = true
			task.delay(1.6, function()
				touchDebounce[key] = nil
			end)

			handlePortalUse(player, portalIndex)
		end)
	end
end

local function wirePortalsFolder(portalsFolder: Instance)
	disconnectAll(folderConnections)

	-- Drop wiring bookkeeping for models that were destroyed/replaced
	for model, _ in wiredModels do
		if not model.Parent then
			wiredModels[model] = nil
		end
	end

	for _, child in portalsFolder:GetChildren() do
		if child:IsA("Model") then
			wirePortalModel(child)
		end
	end

	table.insert(
		folderConnections,
		portalsFolder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				task.defer(function()
					wirePortalModel(child)
				end)
			end
		end)
	)
end

local function bindLobby(lobby: Instance)
	disconnectAll(lobbyConnections)

	local portalsFolder = lobby:FindFirstChild("Portals")
	if portalsFolder then
		wirePortalsFolder(portalsFolder)
	end

	table.insert(
		lobbyConnections,
		lobby.ChildAdded:Connect(function(child)
			if child.Name == "Portals" then
				wirePortalsFolder(child)
			end
		end)
	)
end

function PortalService.start(toast: RemoteEvent, partyUpdated: RemoteEvent, portalsUpdated: RemoteEvent)
	if started then
		return
	end
	started = true
	toastRemote = toast
	partyUpdatedRemote = partyUpdated
	portalsUpdatedRemote = portalsUpdated

	PartyService.setChangedCallback(function(partySnapshot, portalInfos)
		refreshPortalVisuals(portalInfos)
		portalsUpdated:FireAllClients(portalInfos)
		if partySnapshot then
			for _, member in partySnapshot.members do
				local player = Players:GetPlayerByUserId(member.userId)
				if player then
					partyUpdated:FireClient(player, partySnapshot)
				end
			end
		end
	end)

	refreshPortalVisuals(PartyService.getPortalInfos())

	-- Initial bind (lobby should already exist from Bootstrap polish)
	local root = Workspace:WaitForChild("SurviveAtSeaLobby", 30)
	if root then
		bindLobby(root)
	end

	-- Rojo live-sync can replace the whole lobby folder after scripts start.
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "SurviveAtSeaLobby" then
			task.defer(function()
				bindLobby(child)
				refreshPortalVisuals(PartyService.getPortalInfos())
			end)
		end
	end)

	-- Periodic re-bind if Portals was swapped in place without replacing the lobby
	task.spawn(function()
		while started do
			task.wait(2)
			local lobby = Workspace:FindFirstChild("SurviveAtSeaLobby")
			if not lobby then
				continue
			end
			local portalsFolder = lobby:FindFirstChild("Portals")
			if not portalsFolder then
				continue
			end
			local needsRewire = false
			for _, child in portalsFolder:GetChildren() do
				if child:IsA("Model") and not wiredModels[child] then
					needsRewire = true
					break
				end
			end
			if needsRewire then
				bindLobby(lobby)
				refreshPortalVisuals(PartyService.getPortalInfos())
			end
		end
	end)

	print("[SurviveAtSea] PortalService ready — prompts + walk-in, resilient to lobby resync")
end

return PortalService
