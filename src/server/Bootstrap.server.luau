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
local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))
local HelmService = require(script.Parent:WaitForChild("HelmService"))
local OceanTerrainService = require(script.Parent:WaitForChild("OceanTerrainService"))
local DayNightService = require(script.Parent:WaitForChild("DayNightService"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))
local StarterGearService = require(script.Parent:WaitForChild("StarterGearService"))
local MeleeService = require(script.Parent:WaitForChild("Combat"):WaitForChild("MeleeService"))

print(`[SurviveAtSea] Booting {Config.GameName} lobby…`)

-- Build/replicate dock on the server so all players share it
local lobby = LobbyWorld.ensure()
LobbyBuilder.enhanceExisting(lobby)

-- Day / night cycle owns Lighting.ClockTime after the lobby shell is ready
DayNightService.start()

-- Cosmetic open-sea weather schedule (clients apply FX only while in a crew)
WeatherService.start()

-- Realistic Terrain water streams around the pier and every sailing raft
OceanTerrainService.start()

local remoteFolder = Remotes.createServerRemotes()
local CreateParty = remoteFolder:WaitForChild("CreateParty")
local JoinParty = remoteFolder:WaitForChild("JoinParty")
local LeaveParty = remoteFolder:WaitForChild("LeaveParty")
local PartyUpdated = remoteFolder:WaitForChild("PartyUpdated")
local PortalsUpdated = remoteFolder:WaitForChild("PortalsUpdated")
local Toast = remoteFolder:WaitForChild("Toast")
local GetLobbyState = remoteFolder:WaitForChild("GetLobbyState")
local HelmLook = remoteFolder:WaitForChild("HelmLook")
local HelmThrottle = remoteFolder:WaitForChild("HelmThrottle")
local HelmState = remoteFolder:WaitForChild("HelmState")
local HelmDismount = remoteFolder:WaitForChild("HelmDismount")
local MeleeAttack = remoteFolder:WaitForChild("MeleeAttack")
local MeleeSwingFx = remoteFolder:WaitForChild("MeleeSwingFx")

-- Helm: look-steer + throttle drive, jump to unlock
StarterBaseService._onBaseBuilt = function(code, model)
	HelmService.bindBase(code, model)
end
StarterBaseService._onBaseDestroyed = function(code)
	HelmService.onBaseDestroyed(code)
end

HelmService.start(
	HelmState :: RemoteEvent,
	Toast :: RemoteEvent,
	function(player: Player): string?
		return PartyService.getPartyCode(player)
	end,
	function(code: string): { number }
		return PartyService.getMemberUserIds(code)
	end
)

HelmLook.OnServerEvent:Connect(function(player, look)
	if typeof(look) ~= "Vector3" then
		return
	end
	HelmService.setLook(player, look)
end)

HelmThrottle.OnServerEvent:Connect(function(player, throttle)
	if typeof(throttle) ~= "number" then
		return
	end
	HelmService.setThrottle(player, throttle)
end)

HelmDismount.OnServerEvent:Connect(function(player)
	if HelmService.isHelming(player) then
		HelmService.release(player, "Left the helm.")
	end
end)

-- Starter club + melee (RMB / RT / mobile tap). Drop uses default Tool backpack.
StarterGearService.start(function(player)
	return PartyService.isInParty(player)
end)
MeleeService.start(MeleeSwingFx :: RemoteEvent, MeleeAttack :: RemoteEvent, function(player)
	return HelmService.isHelming(player)
end)

PortalService.start(Toast, PartyUpdated, PortalsUpdated)

GetLobbyState.OnServerInvoke = function(player)
	return PartyService.getLobbyState(player)
end

CreateParty.OnServerEvent:Connect(function(player, portalIndex, maxPlayers, _privacy)
	if typeof(portalIndex) ~= "number" or typeof(maxPlayers) ~= "number" then
		Toast:FireClient(player, "Invalid boarding request.", "error")
		return
	end
	-- Crews are always private; ignore any client privacy flag.
	local ok, message, snapshot = PartyService.createParty(player, portalIndex, maxPlayers)
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

local function seatPlayer(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local seat = PartyService.getBaseSeatInfo(player)
	if seat then
		-- Death / respawn while on a crew → back on the raft (for now)
		StarterBaseService.teleportPlayerToBase(player, seat.baseSlot, seat.slotIndex)
		StarterGearService.ensureStarterClub(player)
	else
		LobbyWorld.seatCharacter(character)
	end
end

local function onPlayerReady(player)
	player.CharacterAdded:Connect(function(_character)
		-- Brief defer so HumanoidRootPart exists after respawn
		task.defer(function()
			seatPlayer(player)
		end)
	end)
	if player.Character then
		task.defer(function()
			seatPlayer(player)
		end)
	end

	task.defer(function()
		PortalsUpdated:FireClient(player, PartyService.getPortalInfos())
		Toast:FireClient(
			player,
			"Walk a portal to form a private crew. Friends join with your code.",
			"info"
		)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	HelmService.releaseIfHelming(player)
	PartyService.onPlayerRemoving(player)
end)

for _, player in Players:GetPlayers() do
	onPlayerReady(player)
end
Players.PlayerAdded:Connect(onPlayerReady)

-- Fall into water → rescued onto raft; death already uses CharacterAdded → seatPlayer
-- Skip while at the helm (stand lock owns their position)
StarterBaseService.startWaterRescue(function(player)
	return PartyService.getBaseSeatInfo(player)
end, function(player)
	return HelmService.isHelming(player)
end)

print(`[SurviveAtSea] Lobby ready — private crews only, max {Config.MaxPartySize} per run, portals are reusable.`)
