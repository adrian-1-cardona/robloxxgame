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

	-- Pier boarding portals: walk-in gates that open the create flow.
	-- Exactly three atmosphere portals — reusable, not exclusive party slots / player caps.
	-- Concurrent crews scale with lobby players; each crew gets its own raft via baseSlot.
	LobbyCenter = Vector3.new(0, 4, 0),
	PortalCount = 3,
	-- Spread three portals across the pier without clipping the rails (≈±38)
	PortalSpacing = 24,

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
		-- Kept slightly above OceanConfig.SurfaceY so swimming terrain water still rescues.
		WaterRescueY = 1.2,
	},

	-- Starter gear: wooden club given when you board a crew raft.
	-- Melee swing: right-click (PC), RT / ButtonR2 (console), tap Attack (mobile).
	-- CanBeDropped = true so Roblox backpack drop works (Backspace / Xbox X / etc.).
	Club = {
		ToolName = "Club",
		Damage = 22,
		SwingCooldown = 0.55,
		-- Forward reach from HumanoidRootPart for hit checks
		Range = 7.5,
		HitRadius = 3.2,
		-- How long the swing hit window stays open (server)
		HitWindow = 0.22,
		-- Client swing visual duration
		SwingDuration = 0.35,
	},

	-- Starter raft kit: vertical steering column + upright look-steered helm wheel.
	-- Take the helm → locked standing at the wheel; look steers; W / stick / arrows drive;
	-- jump / gamepad B to unlock and step away.
	Helm = {
		-- Open-ocean sprint — islands are huge and far; the raft needs to feel FAST
		SpeedStudsPerSecond = 340,
		TurnLerp = 7.5,
		-- Stand offset from deck center (aft). Y is ignored — stand sits on deck top.
		StandLocalOffset = Vector3.new(0, 0, 22),
		LookSendHz = 20,
		ThrottleSendHz = 30,
		-- Deadzone for console left-stick Y (and any analog throttle)
		StickDeadzone = 0.18,
		-- Generous for phone / VR laser / console approach
		PromptDistance = 14,
		-- Visual: spin the wooden wheel with look yaw (matches helmsman face turn)
		WheelLookGain = 1.35,
		WheelMaxRadians = math.rad(85),
		WheelSpinLerp = 10,
	},

	-- Stationary open-sea isles. Visit → leave on the raft → sail far enough away → locked forever for that crew.
	-- Huge beach-vibe flats: sand ring → grass → jungle heart, palms everywhere, widely spaced.
	Islands = {
		Thickness = 12,
		TopY = 3.4,
		-- Distance from isle center after a visit before the isle locks (must clear the huge sand pad)
		LockoutStuds = 700,
		-- Extra pad outside the sand when a locked crew tries to sail back in
		ApproachPadStuds = 95,
		Pirate = {
			Health = 40,
			Damage = 5,
			AttackCooldown = 1.15,
			ChaseSpeed = 11,
			AggroRange = 72,
		},
		Gun = {
			Damage = 28,
			Range = 220,
			Cooldown = 0.9,
		},
		-- Massive beach / jungle flats, spread far apart so sailing between them is a real trip.
		-- Islands are ~2.2x their old footprint and pushed ~1.9x further out — the fast helm makes
		-- the longer crossings feel like an open-ocean sprint instead of a slog.
		Catalog = {
			{
				Id = "tide_flat",
				Name = "Tide Flat",
				Offset = Vector3.new(1060, 0, -1300),
				SizeStuds = 380,
				HasHouse = false,
				Pirates = 0,
				Biome = "beach",
			},
			{
				Id = "drift_shack",
				Name = "Drift Shack",
				Offset = Vector3.new(-2240, 0, -2020),
				SizeStuds = 420,
				HasHouse = true,
				Pirates = 0,
				Biome = "palm",
			},
			{
				Id = "crow_cay",
				Name = "Crow Cay",
				Offset = Vector3.new(2780, 0, -2780),
				SizeStuds = 400,
				HasHouse = false,
				Pirates = 4,
				Biome = "jungle",
			},
			{
				Id = "raid_cove",
				Name = "Raid Cove",
				Offset = Vector3.new(-960, 0, -3840),
				SizeStuds = 440,
				HasHouse = true,
				Pirates = 3,
				Biome = "jungle",
			},
			{
				Id = "quiet_sand",
				Name = "Quiet Sand",
				Offset = Vector3.new(3620, 0, -860),
				SizeStuds = 360,
				HasHouse = false,
				Pirates = 0,
				Biome = "beach",
			},
			{
				Id = "smuggler_hut",
				Name = "Smuggler Hut",
				Offset = Vector3.new(480, 0, -5200),
				SizeStuds = 400,
				HasHouse = true,
				Pirates = 0,
				Biome = "palm",
			},
			{
				Id = "buccaneer_flat",
				Name = "Buccaneer Flat",
				Offset = Vector3.new(-3300, 0, -1480),
				SizeStuds = 420,
				HasHouse = false,
				Pirates = 5,
				Biome = "jungle",
			},
			{
				Id = "wreck_spit",
				Name = "Wreck Spit",
				Offset = Vector3.new(2020, 0, -4580),
				SizeStuds = 380,
				HasHouse = true,
				Pirates = 2,
				Biome = "palm",
			},
		},
	},

	-- World loot: drag (hold RMB / RT / touch) or pick up into backpack; weld to raft for shelters / light.
	Loot = {
		DragRange = 18,
		DragHoldSeconds = 0.18,
		WeldDeckRange = 22,
		MaxHeldProps = 1,
		-- Inventory pickup via ProximityPrompt (optional alongside drag)
		PickupPromptDistance = 10,
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
