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
local IslandService = require(script.Parent:WaitForChild("IslandService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local MerchantService = require(script.Parent:WaitForChild("MerchantService"))
local OceanTerrainService = require(script.Parent:WaitForChild("OceanTerrainService"))
local DayNightService = require(script.Parent:WaitForChild("DayNightService"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))
local StarterGearService = require(script.Parent:WaitForChild("StarterGearService"))
local MeleeService = require(script.Parent:WaitForChild("Combat"):WaitForChild("MeleeService"))
local LootPropService = require(script.Parent:WaitForChild("LootPropService"))

print(`[SurviveAtSea] Booting {Config.GameName} lobby…`)

-- Build/replicate dock on the server so all players share it
local lobby = LobbyWorld.ensure()
LobbyBuilder.enhanceExisting(lobby)

-- Fault isolation: a crash in any single service must never take down the
-- boarding-pier / crew-creation path wired below. (Regression guard: the huge
-- island + loot world-gen used to run BEFORE the remotes existed, so any hiccup
-- there left every portal dead.)
local function safeStart(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[SurviveAtSea] {label} failed to start (lobby still playable):`, err)
	end
end

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
local ShootGun = remoteFolder:WaitForChild("ShootGun")
local WeaponReload = remoteFolder:WaitForChild("WeaponReload")
local WeaponFx = remoteFolder:WaitForChild("WeaponFx")
local MeleeAttack = remoteFolder:WaitForChild("MeleeAttack")
local MeleeSwingFx = remoteFolder:WaitForChild("MeleeSwingFx")
local LootDragStart = remoteFolder:WaitForChild("LootDragStart")
local LootDragUpdate = remoteFolder:WaitForChild("LootDragUpdate")
local LootDragEnd = remoteFolder:WaitForChild("LootDragEnd")
local LootWeld = remoteFolder:WaitForChild("LootWeld")
local LootUnweld = remoteFolder:WaitForChild("LootUnweld")
local LootPlace = remoteFolder:WaitForChild("LootPlace")
local MerchantTrade = remoteFolder:WaitForChild("MerchantTrade")
local MerchantShop = remoteFolder:WaitForChild("MerchantShop")

-- Shared accessors used by several services below.
local function getPartyCode(player: Player): string?
	return PartyService.getPartyCode(player)
end
local function getMemberUserIds(code: string): { number }
	return PartyService.getMemberUserIds(code)
end

-- Raft build hooks must exist before any crew spawns its plank.
StarterBaseService._onBaseBuilt = function(code, model)
	HelmService.bindBase(code, model)
end
StarterBaseService._onBaseDestroyed = function(code)
	HelmService.onBaseDestroyed(code)
	IslandService.clearCrew(code)
end

-- === Boarding-pier / crew path — wired first so portals always work, even if
-- the heavier world generation below is slow or throws. ===
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

-- === Gameplay + world services — each fault-isolated so a failure here can
-- never break the boarding pier / crew creation wired above. ===
safeStart("DayNightService", DayNightService.start)
safeStart("WeatherService", WeatherService.start)

-- Weapons: ranged fire, ammo reserves, player currency, weapon/ammo grants + pickups.
safeStart("WeaponService", function()
	WeaponService.start({
		Toast = Toast :: RemoteEvent,
		WeaponFx = WeaponFx :: RemoteEvent,
	})
end)

-- Merchant trading (buy with Doubloons / craft with Scrap). Started BEFORE IslandService
-- so merchants spawned during island generation register + wire correctly.
safeStart("MerchantService", function()
	MerchantService.start({
		Toast = Toast :: RemoteEvent,
		Shop = MerchantShop :: RemoteEvent,
		Trade = MerchantTrade :: RemoteFunction,
	}, function(model)
		LootPropService.registerExisting(model)
	end)
end)

-- Helm: look-steer + throttle drive, jump to unlock
safeStart("HelmService", function()
	HelmService.start(HelmState :: RemoteEvent, Toast :: RemoteEvent, getPartyCode, getMemberUserIds)
end)

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

ShootGun.OnServerEvent:Connect(function(player, look)
	if typeof(look) ~= "Vector3" then
		return
	end
	WeaponService.tryShoot(player, look)
end)

WeaponReload.OnServerEvent:Connect(function(player)
	WeaponService.reload(player)
end)

-- Starter club + melee (RMB / RT / mobile tap). Drop uses default Tool backpack.
safeStart("StarterGearService", function()
	StarterGearService.start(function(player)
		return PartyService.isInParty(player)
	end)
end)
safeStart("MeleeService", function()
	MeleeService.start(MeleeSwingFx :: RemoteEvent, MeleeAttack :: RemoteEvent, function(player)
		return HelmService.isHelming(player)
	end)
end)

-- World loot: drag / weld / pick up island salvage.
safeStart("LootPropService", function()
	LootPropService.start(Toast :: RemoteEvent, getPartyCode, {
		DragStart = LootDragStart :: RemoteEvent,
		DragUpdate = LootDragUpdate :: RemoteEvent,
		DragEnd = LootDragEnd :: RemoteEvent,
		WeldProp = LootWeld :: RemoteEvent,
		UnweldProp = LootUnweld :: RemoteEvent,
		PlaceLoot = LootPlace :: RemoteEvent,
	})
end)

-- Fall into water → rescued onto raft; death already uses CharacterAdded → seatPlayer
-- Skip while at the helm (stand lock owns their position)
safeStart("WaterRescue", function()
	StarterBaseService.startWaterRescue(function(player)
		return PartyService.getBaseSeatInfo(player)
	end, function(player)
		return HelmService.isHelming(player)
	end)
end)

-- Heavy world generation (huge islands, loot props, streaming terrain water)
-- runs off the main boot thread so it can never stall or break the pier above.
task.spawn(function()
	safeStart("OceanTerrainService", OceanTerrainService.start)
	safeStart("IslandService", function()
		IslandService.start(Toast :: RemoteEvent, getPartyCode, getMemberUserIds)
	end)
end)

print(`[SurviveAtSea] Lobby ready — private crews only, max {Config.MaxPartySize} per run, portals are reusable.`)
