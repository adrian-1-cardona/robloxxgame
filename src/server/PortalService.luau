-- Wires pier portal proximity prompts + walk-in triggers.
-- Portals are reusable boarding gates: they open create, never walk-join a crew.
-- Friends always join via code.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local PartyService = require(script.Parent.PartyService)

local PortalService = {}

local touchDebounce: { [string]: boolean } = {}

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

local function handlePortalUse(
	player: Player,
	portalIndex: number,
	toastRemote: RemoteEvent,
	partyUpdated: RemoteEvent
)
	if PartyService.isInParty(player) then
		toastRemote:FireClient(player, "You're already on a crew — share your code from the HUD.", "info")
		return
	end

	toastRemote:FireClient(player, "Pick crew size, then spawn on your plank. Friends join by code.", "info")
	partyUpdated:FireClient(player, {
		__openCreate = true,
		portalIndex = portalIndex,
	})
end

local function wirePortalModel(
	model: Model,
	toastRemote: RemoteEvent,
	partyUpdated: RemoteEvent
)
	local indexValue = model:FindFirstChild("PortalIndex")
	local promptAnchor = model:FindFirstChild("PromptAnchor")
	local prompt = promptAnchor and promptAnchor:FindFirstChild("BoardPrompt")
	if not (indexValue and indexValue:IsA("IntValue")) then
		return
	end

	local portalIndex = indexValue.Value

	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			handlePortalUse(player, portalIndex, toastRemote, partyUpdated)
		end)
	end

	local walkTrigger = model:FindFirstChild("WalkTrigger")
	if walkTrigger and walkTrigger:IsA("BasePart") then
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

			handlePortalUse(player, portalIndex, toastRemote, partyUpdated)
		end)
	end
end

function PortalService.start(toastRemote: RemoteEvent, partyUpdated: RemoteEvent, portalsUpdated: RemoteEvent)
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

	local root = game:GetService("Workspace"):WaitForChild("SurviveAtSeaLobby")
	local portalsFolder = root:WaitForChild("Portals")

	for _, model in portalsFolder:GetChildren() do
		if model:IsA("Model") then
			wirePortalModel(model, toastRemote, partyUpdated)
		end
	end

	portalsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(function()
				wirePortalModel(child, toastRemote, partyUpdated)
			end)
		end
	end)
end

return PortalService
