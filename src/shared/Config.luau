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
	-- Huge beach-vibe flats: sand ring → grass → jungle/village heart, palms everywhere, widely spaced.
	Islands = {
		Thickness = 16,
		TopY = 3.4,
		-- Distance from isle center after a visit before the isle locks (must clear the huge sand pad)
		LockoutStuds = 900,
		-- Extra pad outside the sand when a locked crew tries to sail back in
		ApproachPadStuds = 110,

		-- Legacy hostile "pirate" tuning — kept for back-compat; hostile villagers reuse it.
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

		-- Villagers: tribal islanders. Passive ones (blue eyes) mind their own business
		-- until struck, then defend their home. Aggressive ones (red eyes) hunt trespassers
		-- on sight. Abandoned isles have only a few feral scavengers, if any.
		Villager = {
			Passive = {
				Health = 55,
				WanderSpeed = 5.5,
				WanderRadiusFrac = 0.34, -- of island half-size
				-- When a passive villager is attacked it turns hostile to defend the isle.
				DefendOnAttack = true,
			},
			Hostile = {
				Health = 70,
				Damage = 8,
				AttackCooldown = 1.1,
				ChaseSpeed = 12,
				AggroRange = 82,
			},
			-- Feral scavengers that linger on abandoned isles (rare, weak, hostile).
			Scavenger = {
				Health = 45,
				Damage = 6,
				AttackCooldown = 1.25,
				ChaseSpeed = 10,
				AggroRange = 70,
			},
		},

		-- Merchant: blue-hatted tribal trader. NEVER hostile. Can be dragged onto and
		-- welded to your raft (reuses the loot drag/weld system) so you can carry a
		-- shop between voyages. Trade with looted Doubloons / crafting Scrap.
		Merchant = {
			Health = 120, -- cosmetic; the merchant is never targeted by combat
			GreetRange = 14,
		},

		-- Themed catalog. Bigger footprints so a whole village fits realistically, spread
		-- far apart so sailing between them is a real open-ocean trip. Abandoned isles are
		-- rarer (2 of 8). Every inhabited & abandoned isle carries loot.
		--   Theme: "wild" | "fishing_village" | "village" | "stone_village" | "abandoned"
		Catalog = {
			{
				Id = "tide_flat",
				Name = "Tide Flat",
				Offset = Vector3.new(1200, 0, -1480),
				SizeStuds = 520,
				Biome = "beach",
				Theme = "wild",
				Abandoned = false,
				Merchant = false,
				Villagers = { Passive = 0, Hostile = 0 },
				Loot = { Weapons = 1, Chests = 0 },
			},
			{
				Id = "quiet_sand",
				Name = "Quiet Sand",
				Offset = Vector3.new(4020, 0, -960),
				SizeStuds = 540,
				Biome = "beach",
				Theme = "fishing_village",
				Abandoned = false,
				Merchant = true,
				Villagers = { Passive = 6, Hostile = 0 },
				Loot = { Weapons = 3, Chests = 2 },
			},
			{
				Id = "smuggler_hut",
				Name = "Smuggler Hollow",
				Offset = Vector3.new(560, 0, -5800),
				SizeStuds = 580,
				Biome = "palm",
				Theme = "village",
				Abandoned = false,
				Merchant = true,
				Villagers = { Passive = 5, Hostile = 2 },
				Loot = { Weapons = 4, Chests = 3 },
			},
			{
				Id = "raid_cove",
				Name = "Raid Cove",
				Offset = Vector3.new(-1080, 0, -4300),
				SizeStuds = 640,
				Biome = "jungle",
				Theme = "village",
				Abandoned = false,
				Merchant = true,
				Villagers = { Passive = 7, Hostile = 4 },
				Loot = { Weapons = 5, Chests = 3 },
			},
			{
				Id = "crow_cay",
				Name = "Crow Cay",
				Offset = Vector3.new(3120, 0, -3120),
				SizeStuds = 600,
				Biome = "jungle",
				Theme = "stone_village",
				Abandoned = false,
				Merchant = false,
				Villagers = { Passive = 4, Hostile = 6 },
				Loot = { Weapons = 5, Chests = 4 },
			},
			{
				Id = "buccaneer_flat",
				Name = "Bastion Reach",
				Offset = Vector3.new(-3700, 0, -1660),
				SizeStuds = 620,
				Biome = "jungle",
				Theme = "stone_village",
				Abandoned = false,
				Merchant = false,
				Villagers = { Passive = 3, Hostile = 8 },
				Loot = { Weapons = 6, Chests = 4 },
			},
			{
				Id = "drift_shack",
				Name = "Drift Shack",
				Offset = Vector3.new(-2540, 0, -2280),
				SizeStuds = 560,
				Biome = "palm",
				Theme = "abandoned",
				Abandoned = true,
				Merchant = false,
				Villagers = { Passive = 0, Hostile = 2 }, -- feral scavengers
				Loot = { Weapons = 4, Chests = 3 },
			},
			{
				Id = "wreck_spit",
				Name = "Wreck Spit",
				Offset = Vector3.new(2260, 0, -5100),
				SizeStuds = 540,
				Biome = "palm",
				Theme = "abandoned",
				Abandoned = true,
				Merchant = false,
				Villagers = { Passive = 0, Hostile = 1 },
				Loot = { Weapons = 3, Chests = 2 },
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

	-- Player-carried currencies (tracked as Player attributes so they replicate to the
	-- owning client for the HUD). Doubloons buy finished goods from the merchant; Scrap
	-- is the crafting material you convert into ammo at the merchant.
	Currency = {
		Doubloons = { Attribute = "Doubloons", Label = "Doubloons", StartAmount = 25 },
		Scrap = { Attribute = "Scrap", Label = "Scrap", StartAmount = 10 },
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

	-- Objective directions: little one-line hints that pop up in the top corner,
	-- linger for an adequate read, then fade out. Shown once per phase (lobby vs voyage)
	-- so newcomers always know what to do without cluttering the ocean view.
	ObjectiveHints = {
		-- Fade + linger timing (seconds). Each hint holds for HoldSeconds, so the whole
		-- lobby/voyage set stays on screen for roughly a minute before the last one fades.
		FadeInSeconds = 0.45,
		HoldSeconds = 11,
		FadeOutSeconds = 0.6,

		-- On the pier, before boarding a crew. One line each.
		Lobby = {
			"Walk into a glowing pier portal to start a voyage.",
			"Pick your crew size, then spawn on your own raft.",
			"Share your crew code so friends can board with you.",
		},

		-- Out at sea, once you're on a crew raft. One line each.
		Voyage = {
			"Take the helm and sail out to the distant islands.",
			"Raid island chests and pirates for guns and loot.",
			"Swing your club to fight — haul loot to build your raft.",
			"Survive the day and night out on the open sea.",
		},
	},
}

return Config
