-- Wires portal proximity prompts and keeps world signs in sync with parties.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyBuilder = require(script.Parent.LobbyBuilder)
local PartyService = require(script.Parent.PartyService)

local PortalService = {}

local function refreshPortalVisuals(portals)
	for _, info in portals do
		local model = LobbyBuilder.getPortalModel(info.portalIndex)
		if not model then
			continue
		end

		local promptAnchor = model:FindFirstChild("PromptAnchor")
		local prompt = promptAnchor and promptAnchor:FindFirstChild("BoardPrompt")

		if info.status == "Empty" then
			LobbyBuilder.updatePortalSign(model, `BERTH {info.portalIndex}`, "Empty — create a crew", Config.Theme.Foam)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.ActionText = "Create Crew"
				prompt.ObjectText = `Boarding Berth {info.portalIndex}`
				prompt.Enabled = true
			end
		elseif info.status == "Launching" then
			LobbyBuilder.updatePortalSign(
				model,
				`BERTH {info.portalIndex}`,
				`Casting off — {info.memberCount}/{info.maxPlayers}`,
				Config.Theme.Lantern
			)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = false
			end
		elseif info.status == "Full" then
			LobbyBuilder.updatePortalSign(
				model,
				`BERTH {info.portalIndex}`,
				`Full crew · {info.hostName}`,
				Config.Theme.DangerRed
			)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.ActionText = "Crew Full"
				prompt.Enabled = false
			end
		else
			local codeLine = if info.code then `Code {info.code}` else "Private berth"
			LobbyBuilder.updatePortalSign(
				model,
				`BERTH {info.portalIndex}`,
				`{info.hostName} · {info.memberCount}/{info.maxPlayers}\n{codeLine}`,
				Config.Theme.UIAccent
			)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.ActionText = if info.code then "Join Public Crew" else "Private — use code"
				prompt.ObjectText = `Boarding Berth {info.portalIndex}`
				prompt.Enabled = info.code ~= nil
			end
		end
	end
end

function PortalService.start(toastRemote: RemoteEvent, partyUpdated: RemoteEvent, portalsUpdated: RemoteEvent)
	PartyService.setChangedCallback(function(partySnapshot, portalInfos)
		refreshPortalVisuals(portalInfos)
		portalsUpdated:FireAllClients(portalInfos)
		if partySnapshot then
			for _, member in partySnapshot.members do
				local player = game:GetService("Players"):GetPlayerByUserId(member.userId)
				if player then
					partyUpdated:FireClient(player, partySnapshot)
				end
			end
		end
	end)

	-- Initial paint
	refreshPortalVisuals(PartyService.getPortalInfos())

	local root = game:GetService("Workspace"):WaitForChild("SurviveAtSeaLobby")
	local portalsFolder = root:WaitForChild("Portals")

	for _, model in portalsFolder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local indexValue = model:FindFirstChild("PortalIndex")
		local promptAnchor = model:FindFirstChild("PromptAnchor")
		local prompt = promptAnchor and promptAnchor:FindFirstChild("BoardPrompt")
		if not (indexValue and indexValue:IsA("IntValue") and prompt and prompt:IsA("ProximityPrompt")) then
			continue
		end

		local portalIndex = indexValue.Value
		prompt.Triggered:Connect(function(player: Player)
			local infos = PartyService.getPortalInfos()
			local info = infos[portalIndex]
			if not info or info.status == "Empty" then
				-- Client opens create UI; server just acknowledges empty portal.
				toastRemote:FireClient(player, "Pick crew size and cast your berth.", "info")
				partyUpdated:FireClient(player, {
					__openCreate = true,
					portalIndex = portalIndex,
				})
				return
			end

			local ok, message, snapshot = PartyService.joinPortal(player, portalIndex)
			toastRemote:FireClient(player, message, if ok then "success" else "error")
			if ok and snapshot then
				partyUpdated:FireClient(player, snapshot)
			end
		end)
	end
end

return PortalService
