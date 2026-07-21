-- Shared type aliases for Survive at Sea lobby / party flow.

export type PartyPrivacy = "Public" | "Private"

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
	portalIndex: number,
	countdownEndsAt: number?,
	status: "Open" | "Launching" | "Departed",
}

export type PublicPortalInfo = {
	portalIndex: number,
	code: string?,
	hostName: string?,
	memberCount: number,
	maxPlayers: number,
	status: "Empty" | "Open" | "Launching" | "Full",
}

return {}
