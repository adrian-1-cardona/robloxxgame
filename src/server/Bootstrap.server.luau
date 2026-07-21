-- Survive at Sea · Server bootstrap

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[SurviveAtSea] Server bootstrap starting…")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not Shared then
	error("[SurviveAtSea] ReplicatedStorage.Shared missing — is Rojo connected?")
end

local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PartyCode = require(Shared:WaitForChild("PartyCode"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local LobbyBuilder = require(script.Parent:WaitForChild("LobbyBuilder"))
local PartyService = require(script.Parent:WaitForChild("PartyService"))
local PortalService = require(script.Parent:WaitForChild("PortalService"))

print(`[SurviveAtSea] Booting {Config.GameName} lobby…`)

-- Build/replicate dock on the server so all players share it
local lobby = LobbyWorld.ensure()
LobbyBuilder.enhanceExisting(lobby)

local remoteFolder = Remotes.createServerRemotes()
local CreateParty = remoteFolder:WaitForChild("CreateParty")
local JoinParty = remoteFolder:WaitForChild("JoinParty")
local LeaveParty = remoteFolder:WaitForChild("LeaveParty")
local StartLaunch = remoteFolder:WaitForChild("StartLaunch")
local PartyUpdated = remoteFolder:WaitForChild("PartyUpdated")
local PortalsUpdated = remoteFolder:WaitForChild("PortalsUpdated")
local Toast = remoteFolder:WaitForChild("Toast")
local GetLobbyState = remoteFolder:WaitForChild("GetLobbyState")

PortalService.start(Toast, PartyUpdated, PortalsUpdated)

GetLobbyState.OnServerInvoke = function(player)
	return PartyService.getLobbyState(player)
end

CreateParty.OnServerEvent:Connect(function(player, portalIndex, maxPlayers, privacy)
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

JoinParty.OnServerEvent:Connect(function(player, rawCode)
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

LeaveParty.OnServerEvent:Connect(function(player)
	local ok, message = PartyService.leaveParty(player)
	Toast:FireClient(player, message, if ok then "info" else "error")
	if ok then
		PartyUpdated:FireClient(player, nil)
	end
end)

StartLaunch.OnServerEvent:Connect(function(player)
	local ok, message, snapshot = PartyService.startLaunch(player)
	Toast:FireClient(player, message, if ok then "success" else "error")
	if ok and snapshot then
		PartyUpdated:FireClient(player, snapshot)
	end
end)

local function onPlayerReady(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			LobbyWorld.seatCharacter(character)
		end)
	end)
	if player.Character then
		task.defer(function()
			LobbyWorld.seatCharacter(player.Character :: Model)
		end)
	end

	task.defer(function()
		PortalsUpdated:FireClient(player, PartyService.getPortalInfos())
		Toast:FireClient(player, "Walk into a berth to create or join a crew.", "info")
	end)
end

Players.PlayerRemoving:Connect(function(player)
	PartyService.onPlayerRemoving(player)
end)

for _, player in Players:GetPlayers() do
	onPlayerReady(player)
end
Players.PlayerAdded:Connect(onPlayerReady)

print(`[SurviveAtSea] Lobby ready — max crew {Config.MaxPartySize}, no session saves.`)
