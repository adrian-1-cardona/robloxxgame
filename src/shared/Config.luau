-- Survive at Sea shared configuration
-- Session state is intentionally ephemeral (no DataStores / caching).

local Config = {
	GameName = "Survive at Sea",
	Tagline = "Gather your crew. Board the voyage. Survive the deep.",

	-- Crew size per private run (host picks; friends join by code).
	-- This is player capacity — NOT the pier portal count.
	MinPartySize = 1,
	MaxPartySize = 10,
	DefaultPartySize = 4,
	LaunchCountdownSeconds = 10,

	-- Set this to your voyage PlaceId when the sea run place exists.
	-- Until then, Cast Off locks joins and keeps the crew on their wooden plank starter base.
	GamePlaceId = nil :: number?,

	-- Pier boarding portals: walk-in gates that open the create flow.
	-- They are reusable atmosphere portals — not exclusive party slots and not a player cap.
	-- Concurrent crews scale with lobby players; each crew gets its own raft via baseSlot.
	LobbyCenter = Vector3.new(0, 4, 0),
	PortalCount = 6,
	-- Keep portals inside the pier rails (≈±38) so frames don't clip the bulwark
	PortalSpacing = 14,

	-- Starter base: one huge square wooden plank per crew (not scaled by party size).
	-- Spawned after create/join so the portal flow lands you on your base immediately.
	-- Bases are Models with a PrimaryPart so they can be moved later (sea drift / voyage).
	StarterBase = {
		-- Fixed footprint — same for solo or full (10) crews
		SizeStuds = 72,
		Thickness = 3,
		-- Far open ocean — lobby pier is well beyond fog so it feels like a new place
		Origin = Vector3.new(0, 2.2, 3200),
		-- Spread concurrent crews along X so planks never overlap (indexed by baseSlot)
		SpacingX = 160,
		DeckClearance = 3.5,
		-- Fall into water below this Y → rescue back onto the raft
		WaterRescueY = 1.2,
	},

	-- Portal / berth accent (solid purple — no half-and-half overlays)
	Berth = {
		Purple = Color3.fromRGB(118, 72, 168),
		PurpleDeep = Color3.fromRGB(72, 42, 110),
		PurpleSoft = Color3.fromRGB(168, 132, 210),
	},

	-- Ocean theme palette
	Theme = {
		DeepOcean = Color3.fromRGB(8, 32, 58),
		SeaTeal = Color3.fromRGB(18, 110, 130),
		Foam = Color3.fromRGB(210, 235, 240),
		Driftwood = Color3.fromRGB(92, 64, 42),
		Rope = Color3.fromRGB(160, 120, 70),
		Lantern = Color3.fromRGB(255, 186, 90),
		SeaAccent = Color3.fromRGB(42, 120, 110),
		DangerRed = Color3.fromRGB(220, 70, 70),
		UIPanel = Color3.fromRGB(10, 28, 42),
		UIAccent = Color3.fromRGB(46, 180, 170),
		UIText = Color3.fromRGB(235, 248, 250),
		UIMuted = Color3.fromRGB(150, 185, 195),
	},

	-- Cross-platform UI scale targets
	UI = {
		MinTouchTarget = 48,
		SafePadding = 16,
		Font = Enum.Font.GothamBold,
		BodyFont = Enum.Font.GothamMedium,
	},
}

return Config
