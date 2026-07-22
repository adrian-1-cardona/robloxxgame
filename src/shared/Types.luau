-- Shared type aliases for Survive at Sea lobby / party flow.
-- Crews are always private — friends join with the host's code only.

export type PartyPrivacy = "Private"

export type PartyMember = {
	userId: number,
	displayName: string,
	isHost: boolean,
}

export type PartySnapshot = {
	code: string,
	hostUserId: number,
	maxPlayers: number,
	privacy: PartyPrivacy,
	members: { PartyMember },
	-- Pier portal used to open create (atmosphere only — not a capacity lock)
	portalIndex: number,
	-- Independent raft placement slot (concurrent crews are not capped by portal count)
	baseSlot: number,
	-- Workspace:GetServerTimeNow() when the crew formed — day/night always starts at 6:00 AM
	cycleOrigin: number,
	status: "Open",
}

-- Pier portals are reusable boarding gates, not exclusive party pads.
export type PublicPortalInfo = {
	portalIndex: number,
	status: "Ready",
}

return {}
