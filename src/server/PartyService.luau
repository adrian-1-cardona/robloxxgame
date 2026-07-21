-- Ephemeral party / game-state service.
-- No DataStore or MemoryStore caching — parties live only while this lobby server does.
--
-- Flow:
--   1. Walk a pier portal → pick crew size → form a private crew
--   2. Spawn onto ONE huge square wooden plank (starter base)
--   3. Top-right HUD shows the join code; friends join by code only
--
-- Rules:
--   • Every crew is private — join is code-only (never walk-in onto an occupied crew)
--   • Pier portals are reusable boarding gates, not exclusive party pads
--   • Player capacity is host-chosen maxPlayers (1–MaxPartySize), independent of portal count
--   • Concurrent crews use independent baseSlot raft placement (not capped by PortalCount)

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PartyCode = require(Shared:WaitForChild("PartyCode"))
local Types = require(Shared:WaitForChild("Types"))

local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))

type PartyPrivacy = Types.PartyPrivacy
type PartySnapshot = Types.PartySnapshot
type PartyMember = Types.PartyMember
type PublicPortalInfo = Types.PublicPortalInfo

export type PartyRecord = {
	code: string,
	hostUserId: number,
	maxPlayers: number,
	privacy: PartyPrivacy,
	portalIndex: number,
	baseSlot: number,
	memberUserIds: { number },
	countdownEndsAt: number?,
	status: "Open" | "Launching" | "Departed",
	reservedCode: string?,
}

local PartyService = {}
PartyService._partiesByCode = {} :: { [string]: PartyRecord }
PartyService._playerToCode = {} :: { [number]: string }
PartyService._onChanged = nil :: ((PartySnapshot?, { PublicPortalInfo }) -> ())?

local function displayNameFor(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	return `Crew_{userId}`
end

local function memberSlot(party: PartyRecord, userId: number): number
	for index, id in party.memberUserIds do
		if id == userId then
			return index
		end
	end
	return #party.memberUserIds
end

local function allocateBaseSlot(): number
	local used: { [number]: boolean } = {}
	for _, party in PartyService._partiesByCode do
		used[party.baseSlot] = true
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	return slot
end

local function toSnapshot(party: PartyRecord): PartySnapshot
	local members: { PartyMember } = {}
	for _, userId in party.memberUserIds do
		table.insert(members, {
			userId = userId,
			displayName = displayNameFor(userId),
			isHost = userId == party.hostUserId,
		})
	end

	return {
		code = party.code,
		hostUserId = party.hostUserId,
		maxPlayers = party.maxPlayers,
		privacy = party.privacy,
		members = members,
		portalIndex = party.portalIndex,
		baseSlot = party.baseSlot,
		countdownEndsAt = party.countdownEndsAt,
		status = party.status,
	}
end

local function buildPortalInfos(): { PublicPortalInfo }
	local infos = {}
	for i = 1, Config.PortalCount do
		table.insert(infos, {
			portalIndex = i,
			status = "Ready",
		})
	end
	return infos
end

local function notify(party: PartyRecord?)
	if PartyService._onChanged then
		PartyService._onChanged(if party then toSnapshot(party) else nil, buildPortalInfos())
	end
end

local function seatOnBase(player: Player, party: PartyRecord)
	StarterBaseService.ensureBase(party.code, party.baseSlot)
	StarterBaseService.teleportPlayerToBase(player, party.baseSlot, memberSlot(party, player.UserId))
end

local function removePlayerFromCurrentParty(userId: number)
	local code = PartyService._playerToCode[userId]
	if not code then
		return
	end

	local party = PartyService._partiesByCode[code]
	PartyService._playerToCode[userId] = nil
	if not party then
		return
	end

	-- Drop the wheel before teleporting home
	local leavingPlayer = Players:GetPlayerByUserId(userId)
	if leavingPlayer then
		local HelmService = require(script.Parent:WaitForChild("HelmService"))
		HelmService.releaseIfHelming(leavingPlayer)
	end

	local remaining = {}
	for _, id in party.memberUserIds do
		if id ~= userId then
			table.insert(remaining, id)
		end
	end
	party.memberUserIds = remaining

	if leavingPlayer then
		StarterBaseService.teleportPlayerToLobby(leavingPlayer)
	end

	if #remaining == 0 then
		StarterBaseService.destroyBase(code)
		PartyService._partiesByCode[code] = nil
		notify(nil)
		return
	end

	if party.hostUserId == userId then
		party.hostUserId = remaining[1]
	end

	notify(party)
end

function PartyService.setChangedCallback(callback: (PartySnapshot?, { PublicPortalInfo }) -> ())
	PartyService._onChanged = callback
end

function PartyService.getPartyCode(player: Player): string?
	return PartyService._playerToCode[player.UserId]
end

function PartyService.getMemberUserIds(code: string): { number }
	local party = PartyService._partiesByCode[code]
	if not party then
		return {}
	end
	return party.memberUserIds
end

function PartyService.getSnapshotForPlayer(player: Player): PartySnapshot?
	local code = PartyService._playerToCode[player.UserId]
	if not code then
		return nil
	end
	local party = PartyService._partiesByCode[code]
	if not party then
		return nil
	end
	return toSnapshot(party)
end

function PartyService.isInParty(player: Player): boolean
	return PartyService._playerToCode[player.UserId] ~= nil
end

function PartyService.getPortalInfos(): { PublicPortalInfo }
	return buildPortalInfos()
end

function PartyService.getLobbyState(player: Player): { party: PartySnapshot?, portals: { PublicPortalInfo } }
	return {
		party = PartyService.getSnapshotForPlayer(player),
		portals = buildPortalInfos(),
	}
end

function PartyService.getBaseSeatInfo(player: Player): { baseSlot: number, slotIndex: number }?
	local code = PartyService._playerToCode[player.UserId]
	if not code then
		return nil
	end
	local party = PartyService._partiesByCode[code]
	if not party then
		return nil
	end
	return {
		baseSlot = party.baseSlot,
		slotIndex = memberSlot(party, player.UserId),
	}
end

function PartyService.createParty(
	player: Player,
	portalIndex: number,
	maxPlayers: number
): (boolean, string, PartySnapshot?)
	if PartyService._playerToCode[player.UserId] then
		return false, "Leave your current crew before creating another.", nil
	end

	if portalIndex < 1 or portalIndex > Config.PortalCount then
		return false, "That boarding portal doesn't exist.", nil
	end

	maxPlayers = math.clamp(math.floor(maxPlayers), Config.MinPartySize, Config.MaxPartySize)

	local code = PartyCode.generate(PartyService._partiesByCode)
	local baseSlot = allocateBaseSlot()
	local party: PartyRecord = {
		code = code,
		hostUserId = player.UserId,
		maxPlayers = maxPlayers,
		privacy = "Private",
		portalIndex = portalIndex,
		baseSlot = baseSlot,
		memberUserIds = { player.UserId },
		countdownEndsAt = nil,
		status = "Open",
		reservedCode = nil,
	}

	PartyService._partiesByCode[code] = party
	PartyService._playerToCode[player.UserId] = code

	StarterBaseService.ensureBase(code, baseSlot)
	seatOnBase(player, party)

	local snapshot = toSnapshot(party)
	notify(party)
	return true, "Private crew ready — share your code so friends can join.", snapshot
end

function PartyService.joinParty(player: Player, rawCode: string): (boolean, string, PartySnapshot?)
	if PartyService._playerToCode[player.UserId] then
		return false, "You're already on a crew.", nil
	end

	local code = PartyCode.normalize(rawCode)
	if #code < 4 then
		return false, "Enter a valid crew code.", nil
	end

	local party = PartyService._partiesByCode[code]
	if not party then
		return false, "No crew found with that code.", nil
	end

	if party.status ~= "Open" then
		return false, "That voyage is already launching.", nil
	end

	if #party.memberUserIds >= party.maxPlayers then
		return false, `That crew is full ({party.maxPlayers}/{party.maxPlayers}).`, nil
	end

	table.insert(party.memberUserIds, player.UserId)
	PartyService._playerToCode[player.UserId] = code

	StarterBaseService.ensureBase(party.code, party.baseSlot)
	seatOnBase(player, party)

	local snapshot = toSnapshot(party)
	notify(party)
	return true, "You joined the crew base!", snapshot
end

function PartyService.leaveParty(player: Player): (boolean, string)
	if not PartyService._playerToCode[player.UserId] then
		return false, "You're not on a crew."
	end
	removePlayerFromCurrentParty(player.UserId)
	return true, "Left the crew — back on the pier."
end

function PartyService.startLaunch(player: Player): (boolean, string, PartySnapshot?)
	local code = PartyService._playerToCode[player.UserId]
	if not code then
		return false, "Create or join a crew first.", nil
	end

	local party = PartyService._partiesByCode[code]
	if not party then
		return false, "Crew not found.", nil
	end

	if party.hostUserId ~= player.UserId then
		return false, "Only the host can cast off.", nil
	end

	if party.status ~= "Open" then
		return false, "Launch already in progress.", nil
	end

	if #party.memberUserIds < 1 then
		return false, "Need at least one sailor.", nil
	end

	party.status = "Launching"
	-- Use server time so clients can render a synced countdown.
	party.countdownEndsAt = Workspace:GetServerTimeNow() + Config.LaunchCountdownSeconds
	notify(party)

	task.delay(Config.LaunchCountdownSeconds, function()
		PartyService._finalizeLaunch(party.code)
	end)

	return true, "Casting off!", toSnapshot(party)
end

function PartyService._finalizeLaunch(code: string)
	local party = PartyService._partiesByCode[code]
	if not party or party.status ~= "Launching" then
		return
	end

	party.status = "Departed"
	notify(party)

	local playersToTeleport: { Player } = {}
	for _, userId in party.memberUserIds do
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			table.insert(playersToTeleport, plr)
		end
	end

	if #playersToTeleport == 0 then
		StarterBaseService.destroyBase(code)
		PartyService._partiesByCode[code] = nil
		notify(nil)
		return
	end

	local leftForVoyage = false

	-- Prefer reserved-server teleport when a voyage place is configured.
	if typeof(Config.GamePlaceId) == "number" and Config.GamePlaceId > 0 then
		local ok, reservedCode = pcall(function()
			return TeleportService:ReserveServer(Config.GamePlaceId :: number)
		end)
		if ok and typeof(reservedCode) == "string" then
			party.reservedCode = reservedCode
			local teleportOk, err = pcall(function()
				TeleportService:TeleportToPrivateServer(
					Config.GamePlaceId :: number,
					reservedCode,
					playersToTeleport
				)
			end)
			if teleportOk then
				leftForVoyage = true
			else
				warn("[SurviveAtSea] Teleport failed:", err)
			end
		else
			warn("[SurviveAtSea] ReserveServer failed; staying on starter base.")
		end
	end

	if not leftForVoyage then
		-- No voyage place yet — lock joins, keep the plank + crew HUD alive.
		party.status = "Open"
		party.countdownEndsAt = nil
		for index, plr in playersToTeleport do
			StarterBaseService.teleportPlayerToBase(plr, party.baseSlot, index)
		end
		party.status = "Departed"
		notify(party)
		return
	end

	-- Destroy the plank only when the crew left this place.
	StarterBaseService.destroyBase(code)
	for _, userId in party.memberUserIds do
		PartyService._playerToCode[userId] = nil
	end
	PartyService._partiesByCode[code] = nil
	notify(nil)
end

function PartyService.onPlayerRemoving(player: Player)
	removePlayerFromCurrentParty(player.UserId)
end

return PartyService
