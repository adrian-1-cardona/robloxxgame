-- Survive at Sea · Lobby server bootstrap

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PartyCode = require(Shared:WaitForChild("PartyCode"))

local LobbyBuilder = require(script:WaitForChild("Lobby"):WaitForChild("LobbyBuilder"))
local PartyService = require(script:WaitForChild("Lobby"):WaitForChild("PartyService"))
local PortalService = require(script:WaitForChild("Lobby"):WaitForChild("PortalService"))

print(`[SurviveAtSea] Booting {Config.GameName} lobby…`)

local okBuild, buildErr = pcall(function()
	LobbyBuilder.build()
end)
if not okBuild then
	warn("[SurviveAtSea] Lobby build FAILED:", buildErr)
	error(buildErr)
end

local remoteFolder = Remotes.createServerRemotes()
local CreateParty = remoteFolder:WaitForChild("CreateParty") :: RemoteEvent
local JoinParty = remoteFolder:WaitForChild("JoinParty") :: RemoteEvent
local LeaveParty = remoteFolder:WaitForChild("LeaveParty") :: RemoteEvent
local StartLaunch = remoteFolder:WaitForChild("StartLaunch") :: RemoteEvent
local PartyUpdated = remoteFolder:WaitForChild("PartyUpdated") :: RemoteEvent
local PortalsUpdated = remoteFolder:WaitForChild("PortalsUpdated") :: RemoteEvent
local Toast = remoteFolder:WaitForChild("Toast") :: RemoteEvent
local GetLobbyState = remoteFolder:WaitForChild("GetLobbyState") :: RemoteFunction

local okPortals, portalErr = pcall(function()
	PortalService.start(Toast, PartyUpdated, PortalsUpdated)
end)
if not okPortals then
	warn("[SurviveAtSea] PortalService failed:", portalErr)
end

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

local function onPlayerReady(player: Player)
	local function seatOnDock(character: Model)
		task.defer(function()
			LobbyBuilder.teleportPlayerToLobby(player)
		end)
	end

	if player.Character then
		seatOnDock(player.Character)
	end
	player.CharacterAdded:Connect(seatOnDock)

	task.defer(function()
		PortalsUpdated:FireClient(player, PartyService.getPortalInfos())
		local snapshot = PartyService.getSnapshotForPlayer(player)
		if snapshot then
			PartyUpdated:FireClient(player, snapshot)
		end
		Toast:FireClient(player, "Walk forward to the glowing portals to board!", "info")
	end)
end

Players.PlayerRemoving:Connect(function(player)
	PartyService.onPlayerRemoving(player)
end)

for _, player in Players:GetPlayers() do
	onPlayerReady(player)
end
Players.PlayerAdded:Connect(onPlayerReady)

print(`[SurviveAtSea] Lobby ready — portals online, max crew {Config.MaxPartySize}, no session saves.`)
