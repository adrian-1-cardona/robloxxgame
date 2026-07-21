-- Survive at Sea shared configuration
-- Session state is intentionally ephemeral (no DataStores / caching).

local Config = {
	GameName = "Survive at Sea",
	Tagline = "Gather your crew. Board the voyage. Survive the deep.",

	-- Party / server limits (Dead Rails-style: 1–10 players per run)
	MinPartySize = 1,
	MaxPartySize = 10,
	DefaultPartySize = 4,
	LaunchCountdownSeconds = 10,

	-- Set this to your voyage PlaceId when the sea run place exists.
	-- Until then, Cast Off locks joins and keeps the crew on their wooden plank starter base.
	GamePlaceId = nil :: number?,

	-- Lobby layout (portals close to spawn so they're obvious)
	LobbyCenter = Vector3.new(0, 4, 0),
	PortalCount = 4,
	-- Keep berths inside the pier rails (≈±38) so frames don't clip the bulwark
	PortalSpacing = 18,

	-- Starter base: one huge square wooden plank per crew (not scaled by party size).
	-- Spawned after create/join so the berth flow lands you on your base immediately.
	StarterBase = {
		-- Fixed footprint — same for solo or full (10) crews
		SizeStuds = 72,
		Thickness = 3,
		-- Far past the boarding pier so bases sit out on the open water
		Origin = Vector3.new(0, 3.5, 260),
		-- Spread concurrent crews along X so planks never overlap
		SpacingX = 110,
		DeckClearance = 4,
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
