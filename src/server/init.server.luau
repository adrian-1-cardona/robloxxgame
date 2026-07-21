-- Survive at Sea · Lobby server bootstrap

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PartyCode = require(Shared:WaitForChild("PartyCode"))

local LobbyBuilder = require(script.Lobby.LobbyBuilder)
local PartyService = require(script.Lobby.PartyService)
local PortalService = require(script.Lobby.PortalService)

print(`[SurviveAtSea] Booting {Config.GameName} lobby…`)

LobbyBuilder.build()

local remoteFolder = Remotes.createServerRemotes()
local CreateParty = remoteFolder:WaitForChild("CreateParty") :: RemoteEvent
local JoinParty = remoteFolder:WaitForChild("JoinParty") :: RemoteEvent
local LeaveParty = remoteFolder:WaitForChild("LeaveParty") :: RemoteEvent
local StartLaunch = remoteFolder:WaitForChild("StartLaunch") :: RemoteEvent
local PartyUpdated = remoteFolder:WaitForChild("PartyUpdated") :: RemoteEvent
local PortalsUpdated = remoteFolder:WaitForChild("PortalsUpdated") :: RemoteEvent
local Toast = remoteFolder:WaitForChild("Toast") :: RemoteEvent
local GetLobbyState = remoteFolder:WaitForChild("GetLobbyState") :: RemoteFunction

PortalService.start(Toast, PartyUpdated, PortalsUpdated)

GetLobbyState.OnServerInvoke = function(player: Player)
	return PartyService.getLobbyState(player)
end

CreateParty.OnServerEvent:Connect(function(player: Player, portalIndex: any, maxPlayers: any, privacy: any)
	if typeof(portalIndex) ~= "number" or typeof(maxPlayers) ~= "number" then
		Toast:FireClient(player, "Invalid boarding request.", "error")
		return
	end
	local privacyValue = if privacy == "Private" then "Private" else "Public"
	local ok, message, snapshot = PartyService.createParty(player, portalIndex, maxPlayers, privacyValue)
	Toast:FireClient(player, message, if ok then "success" else "error")
	if ok and snapshot then
		PartyUpdated:FireClient(player, snapshot)
	end
end)

JoinParty.OnServerEvent:Connect(function(player: Player, rawCode: any)
	if typeof(rawCode) ~= "string" then
		Toast:FireClient(player, "Enter a crew code.", "error")
		return
	end
	local ok, message, snapshot = PartyService.joinParty(player, PartyCode.normalize(rawCode))
	Toast:FireClient(player, message, if ok then "success" else "error")
	if ok and snapshot then
		PartyUpdated:FireClient(player, snapshot)
	end
end)

LeaveParty.OnServerEvent:Connect(function(player: Player)
	local ok, message = PartyService.leaveParty(player)
	Toast:FireClient(player, message, if ok then "info" else "error")
	if ok then
		PartyUpdated:FireClient(player, nil)
	end
end)

StartLaunch.OnServerEvent:Connect(function(player: Player)
	local ok, message, snapshot = PartyService.startLaunch(player)
	Toast:FireClient(player, message, if ok then "success" else "error")
	if ok and snapshot then
		PartyUpdated:FireClient(player, snapshot)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	PartyService.onPlayerRemoving(player)
end)

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		PortalsUpdated:FireClient(player, PartyService.getPortalInfos())
		local snapshot = PartyService.getSnapshotForPlayer(player)
		if snapshot then
			PartyUpdated:FireClient(player, snapshot)
		end
	end)
end)

print(`[SurviveAtSea] Lobby ready — portals online, max crew {Config.MaxPartySize}, no session saves.`)
