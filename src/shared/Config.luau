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

	-- Starter base: one compact square wooden raft per crew (not scaled by party size).
	-- Spawned after create/join so the portal flow lands you on your base immediately.
	-- Bases are Models with a PrimaryPart so they can be moved later (sea drift / voyage).
	StarterBase = {
		-- Fixed footprint — same for solo or full (10) crews
		-- Slightly smaller than the original 72-stud deck so the surrounding island
		-- hubs dominate the opening view while ten players still have room to move.
		SizeStuds = 64,
		Thickness = 3,
		-- Far open ocean — lobby pier is well beyond fog so it feels like a new place
		Origin = Vector3.new(0, 3.0, 3200),
		-- Concurrent crews berth in a compact grid so their planks never overlap, spaced by
		-- SpacingX on both axes and SlotsPerRow wide. A grid rather than a single row: a row
		-- of four rafts needs 480 studs of open water in a straight line, which forced the
		-- arrival island to keep a channel through its own middle.
		SpacingX = 160,
		SlotsPerRow = 2,
		DeckClearance = 3.5,
		-- Fall into water below this Y → rescue back onto the raft
		-- Must be below the deck bottom so players don't get rescued while standing on deck.
		WaterRescueY = -0.5,
	},

	-- Starter gear: wooden club given when you board a crew raft.
	-- Melee swing: right-click (PC), RT / ButtonR2 (console), tap Attack (mobile).
	-- CanBeDropped = true so Roblox backpack drop works (Backspace / Xbox X / etc.).
	Club = {
		ToolName = "Club",
		-- Buffed starter club: hits harder, swings a touch faster, and reaches further
		-- with a wider arc so the opening weapon actually feels good to fight with.
		Damage = 30,
		SwingCooldown = 0.48,
		-- Forward reach from HumanoidRootPart for hit checks
		Range = 9,
		HitRadius = 3.8,
		-- How long the swing hit window stays open (server)
		HitWindow = 0.24,
		-- Client swing visual duration
		SwingDuration = 0.32,
		-- A solid two-handed swing shoves lighter foes back a step.
		Knockback = 14,
	},

	-- Starter raft kit: vertical steering column + upright look-steered helm wheel.
	-- Take the helm → locked standing at the wheel; look steers; W / stick / arrows drive;
	-- jump / gamepad B to unlock and step away.
	Helm = {
		-- Open-ocean sprint — the raft needs to feel FAST so the (now moderately
		-- spaced) isles are reached in a handful of seconds, not a long slog.
		SpeedStudsPerSecond = 520,
		TurnLerp = 7.5,
		-- Stand offset from deck center (aft). Y is ignored — stand sits on deck top.
		StandLocalOffset = Vector3.new(0, 0, 22),
		LookSendHz = 15,
		ThrottleSendHz = 15,
		-- Deadzone for console left-stick Y (and any analog throttle)
		StickDeadzone = 0.18,
		-- Generous for phone / VR laser / console approach
		PromptDistance = 14,
		-- Fixed third-person chase distance while driving so the wheel never fills
		-- the screen and the helmsman can see water, islands, and the raft bow.
		CameraDistance = 24,
		-- Visual: spin the wooden wheel with look yaw (matches helmsman face turn)
		WheelLookGain = 1.35,
		WheelMaxRadians = math.rad(85),
		WheelSpinLerp = 10,
	},

	-- Stationary open-sea isles. Visit → leave on the raft → sail far enough away → locked forever for that crew.
	-- Beach-vibe flats: sand ring → grass → jungle/village heart, palms everywhere.
	-- The opening set is built before boarding. The first island's beach sits directly
	-- beside the raft, while the remaining isles fill the surrounding horizon.
	Islands = {
		Thickness = 16,
		TopY = 3.4,
		-- Beyond the handcrafted opening ring, procedural cells keep the horizon full.
		-- Each cell produces one deterministic tropical isle and is only built when a
		-- crew sails close enough, so the sea can continue indefinitely without a huge
		-- up-front terrain cost.
		Endless = {
			Enabled = true,
		CellStuds = 5200,
		BuildRadiusCells = 1,
		PulseSeconds = 2.5,
			MinSizeStuds = 850,
			MaxSizeStuds = 1250,
			-- The channel is deliberately much wider than the 64-stud starter raft,
			-- leaving room to turn instead of forcing a pixel-perfect approach.
			RiverWidth = 260,
		},
		-- Distance from isle center after a visit before the isle locks. Must clear the
		-- whole sand pad of even the largest isle (radius ~900), so it's set well beyond it.
		LockoutStuds = 2000,
		-- Extra pad outside the sand when a locked crew tries to sail back in
		ApproachPadStuds = 220,
		-- How many concurrent crew rafts a boarding island (SafeHarbor) must berth in open
		-- water. Rafts sit on a line of slots through that island's centre, spaced by
		-- StarterBase.SpacingX, so this drives how much of its lagoon has to stay clear.
		BerthSlots = 4,

		-- Solid-shoreline collision: the complete raft footprint must remain over water.
		-- The extra hull margin keeps corners and passengers out of terrain even during a
		-- high-speed, low-frame-rate approach.
		RaftCollisionPad = 58,

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

		-- Themed catalog. HUGE footprints so each isle is a real place you can walk
		-- end-to-end — full villages, sprawling towns lit up with life, thick Amazonian
		-- jungles, towering castles, and quiet abandoned ruins. Spread far apart so sailing
		-- between them is a genuine open-ocean voyage. Every isle carries loot.
		--
		--   Biome: "beach" | "palm" | "jungle" | "highland" | "volcanic" | "mountain" | "twin_peaks"
		--     beach/palm/jungle → sandy tropical isles; highland → temperate grass + pines
		--     (medieval seaside look); volcanic → tropical isle around a smoking lava cone;
		--     mountain → snow-capped peak + a freshwater lake with a waterfall off the cliff;
		--     twin_peaks → two blocky low-poly rock stacks on separate sand pads.
		--   Theme: "wild" | "fishing_village" | "village" | "town" | "stone_town"
		--        | "castle" | "abandoned"
		-- Optional per-isle flags read by VillageBuilder / IslandService:
		--   TropicalTerrace = true → terraced grass rings, stone retaining walls,
		--     spiral cliff path, stilt huts with pyramid thatch roofs over the water
		--   Church     = true → raise a stone church with a steeple, bell & cross
		--   Mansions   = <n>  → n grand multi-storey manor houses in the settlement
		--   Lit        = true → street lamps + braziers so the town glows day and night
		--   Castle     = true → build a huge castle keep (used by the "castle" theme)
		--   Docks      = <n>  → n wooden piers reaching out over the water (moored rowboats,
		--                       barrels & crates); on mountain isles the first pier is on the lake
		--   Lighthouse = true → a tall banded stone lighthouse on the shore (seaside towns)
		--   Volcano    = true → force/allow the central lava cone on a "volcanic" biome isle
		--
		-- Villagers spawn with the opening archipelago. Towns must already look inhabited
		-- from the raft; landing is not required to make their residents appear.
		Catalog = {
			-- The first playable view after boarding: one irregular volcanic island with a
			-- sheltered lagoon, a dockside town on its shore and a tall smoking cone behind
			-- it. Its silhouette comes from src/shared/IslandShape.luau like every other
			-- isle, so it is never a circular atoll or a dome-shaped hill field.
			--
			-- The bay's position and size, the cone's position and footprint, and the town
			-- site are deliberately NOT pinned here. Pinning them produced a lagoon centred
			-- on the island (a moat, and the exact bullseye the shape generator exists to
			-- avoid) whose rim then swallowed the volcano that was pinned inside it. The
			-- generator already guarantees what this island wants: an off-centre bay with a
			-- mouth to the sea, the landmark on the opposite flank, and the town fitted to
			-- the bay shore. Only the things that cannot be derived are stated.
			{
				Id = "arrival_hub",
				Name = "Emberlagoon Haven",
				Offset = Vector3.new(0, 0, 0),
				SizeStuds = 1500,
				-- Jungle biome for dense tropical vegetation; Volcano = true turns the
				-- island's landmark into a crater cone without changing the flora.
				Biome = "jungle",
				Theme = "town",
				Abandoned = false,
				Hub = true,
				SafeHarbor = true,
				Merchant = true,
				Lagoon = true,
				-- A tall cone: this is the first landmark a crew ever sees.
				Volcano = true,
				VolcanoHeight = 260,
				-- Retained as the boarding/raft contract marker. The generator turns it
				-- into a meandering channel through the island.
				River = true,
				RiverWidth = 440,
				-- The town looks north across its own harbour, back toward the spawn raft.
				HarborFacingAngle = math.pi,
				VillageRadiusFactor = 0.36,
				Docks = 3,
				Lighthouse = true,
				Church = true,
				Lit = true,
				Villagers = { Passive = 18, Hostile = 0 },
				Loot = { Weapons = 5, Chests = 5, Armor = 3 },
			},
			-- Twelve sculpted islands form a complete archipelago around the central
			-- voyage hub. Their 2,100-stud ring stays inside the opening 4K streaming
			-- target, so every high-detail silhouette is present and visible from the raft.
			-- The clear inner basin still gives every crew room to board and choose a route.
			{
				Id = "tide_flat",
				Name = "Greenwood Landing",
				-- Directly north of spawn: a dense old-growth forest surrounds a medieval
				-- village clearing. A navigable river cuts through the woods to the harbour;
				-- sand is limited to a narrow shoreline instead of covering the whole island.
				Offset = Vector3.new(0, 0, -2100),
				SizeStuds = 1100,
				Biome = "jungle",
				Theme = "village",
				Abandoned = false,
				Merchant = true,
				River = true,
				RiverAngle = 0,
				RiverWidth = 280,
				Docks = 2,
				Church = true,
				Lit = true,
				Villagers = { Passive = 14, Hostile = 2 },
				Loot = { Weapons = 7, Chests = 5, Armor = 3 },
			},
			{
				Id = "quiet_sand",
				Name = "Quiet Sand",
				-- A snug medieval fishing village on a temperate headland: timber cottages,
				-- fish-drying racks, a banded stone lighthouse and two piers out over the water.
				Offset = Vector3.new(1050, 0, -1819),
				SizeStuds = 1100,
				Biome = "highland",
				Theme = "fishing_village",
				Abandoned = false,
				Merchant = true,
				Lighthouse = true,
				-- A winding open harbour channel makes this one of the first
				-- proper river landfalls crews see after leaving the spawn raft.
				River = true,
				RiverAngle = 0.82,
				RiverWidth = 260,
				Docks = 2,
				Villagers = { Passive = 9, Hostile = 0 },
				Loot = { Weapons = 5, Chests = 3, Armor = 2 },
			},
			{
				Id = "smuggler_hut",
				Name = "Smuggler Hollow",
				-- A small tropical isle built around a smoking lava cone — palms, gems and a
				-- single hidden smugglers' pier.
				Offset = Vector3.new(1819, 0, -1050),
				SizeStuds = 1100,
				Biome = "volcanic",
				Theme = "village",
				Abandoned = false,
				Merchant = true,
				Volcano = true,
				Docks = 1,
				Villagers = { Passive = 8, Hostile = 3 },
				Loot = { Weapons = 6, Chests = 4, Armor = 3 },
			},
			{
				Id = "raid_cove",
				Name = "Verde Town",
				-- The flagship: a big medieval seaside town lit up with people and life — a
				-- church and grand manors at its heart, a lighthouse on the point, and three
				-- busy piers along the harbour front (the postcard "seaside village" isle).
				Offset = Vector3.new(2100, 0, 0),
				SizeStuds = 1100,
				Biome = "highland",
				Theme = "town",
				Abandoned = false,
				Merchant = true,
				Church = true,
				Mansions = 2,
				Lit = true,
				Lighthouse = true,
				-- Verde is a huge, forest-framed town split by a navigable canal.
				River = true,
				RiverAngle = 2.22,
				RiverWidth = 270,
				Docks = 3,
				-- Lively and mostly friendly — lots of townsfolk, only a small watch.
				Villagers = { Passive = 20, Hostile = 4 },
				Loot = { Weapons = 9, Chests = 7, Armor = 5 },
			},
			{
				Id = "crow_cay",
				Name = "Crow Cay",
				-- A tropical stone town clinging to the slopes of an active volcano — lava glow
				-- over cobblestone streets, a church, and two harbour piers.
				Offset = Vector3.new(1819, 0, 1050),
				SizeStuds = 1100,
				Biome = "volcanic",
				Theme = "stone_town",
				Abandoned = false,
				Merchant = true,
				Church = true,
				Mansions = 1,
				Lit = true,
				Volcano = true,
				Docks = 2,
				Villagers = { Passive = 10, Hostile = 8 },
				Loot = { Weapons = 8, Chests = 6, Armor = 4 },
			},
			{
				Id = "riverlands",
				Name = "Riverlands",
				-- A huge jungle island split by a sea-to-sea river. The channel is wide
				-- enough for the starter raft, creating a proper helm voyage inland.
				Offset = Vector3.new(1050, 0, 1819),
				SizeStuds = 1100,
				Biome = "jungle",
				Theme = "town",
				Abandoned = false,
				Merchant = true,
				River = true,
				RiverAngle = 0,
				RiverWidth = 300,
				Docks = 3,
				Lighthouse = true,
				Villagers = { Passive = 16, Hostile = 3 },
				Loot = { Weapons = 10, Chests = 8, Armor = 6 },
			},
			{
				Id = "buccaneer_flat",
				Name = "Bastion Keep",
				-- A castle on a green mountain isle: a snow-capped peak behind the keep and a
				-- glassy lake below with its own jetty.
				Offset = Vector3.new(0, 0, 2100),
				SizeStuds = 1100,
				Biome = "mountain",
				Theme = "castle",
				Abandoned = false,
				Merchant = false,
				Castle = true,
				Docks = 1,
				Villagers = { Passive = 0, Hostile = 12 }, -- castle garrison
				Loot = { Weapons = 9, Chests = 7, Armor = 5 },
			},
			{
				Id = "kings_hold",
				Name = "King's Hold",
				-- A mightier mountain-lake stronghold — a torch-lit walled keep beside a
				-- waterfall-fed lake, a lakeside jetty and a sea pier below the cliffs.
				Offset = Vector3.new(-1050, 0, 1819),
				SizeStuds = 1100,
				Biome = "mountain",
				Theme = "castle",
				Abandoned = false,
				Merchant = true,
				Castle = true,
				Lit = true,
				Docks = 2,
				Villagers = { Passive = 4, Hostile = 14 },
				Loot = { Weapons = 10, Chests = 8, Armor = 6 },
			},
			{
				Id = "drift_shack",
				Name = "Drift Shack",
				Offset = Vector3.new(-1819, 0, 1050),
				SizeStuds = 1100,
				Biome = "jungle",
				-- A whole town, long abandoned and reclaimed by the jungle (ruined houses,
				-- cold pits, a rotting pier and only a few feral scavengers left).
				Theme = "town",
				Abandoned = true,
				Merchant = false,
				-- The jungle reclaimed both banks of this old river settlement.
				River = true,
				RiverAngle = 1.38,
				RiverWidth = 270,
				Docks = 1,
				Villagers = { Passive = 0, Hostile = 3 }, -- feral scavengers
				Loot = { Weapons = 6, Chests = 5, Armor = 3 },
			},
			{
				Id = "wreck_spit",
				Name = "Wreck Spit",
				-- Northwest opening-ring isle; kept clear of its neighbours so crews can
				-- sail the channels between every island.
				-- A dead volcanic spit strewn with shipwrecks — a smoking cone and one
				-- half-collapsed pier.
				Offset = Vector3.new(-2100, 0, 0),
				SizeStuds = 1100,
				Biome = "volcanic",
				Theme = "abandoned",
				Abandoned = true,
				Merchant = false,
				Volcano = true,
				Docks = 1,
				Villagers = { Passive = 0, Hostile = 2 },
				Loot = { Weapons = 5, Chests = 4, Armor = 2 },
			},
			{
				Id = "mistwood",
				Name = "Mistwood Crossing",
				-- Layered forest hills, a broad river ravine, and a bank-side settlement
				-- inspired by the deep green forest reference.
				Offset = Vector3.new(-1819, 0, -1050),
				SizeStuds = 1100,
				Biome = "jungle",
				Theme = "village",
				Abandoned = false,
				Merchant = true,
				River = true,
				RiverAngle = 0.52,
				RiverWidth = 290,
				Docks = 2,
				Lit = true,
				Villagers = { Passive = 12, Hostile = 2 },
				Loot = { Weapons = 7, Chests = 5, Armor = 3 },
			},
			{
				Id = "lantern_port",
				Name = "Lantern Port",
				-- A dense timber harbour town with a lighthouse, church, stacked roofs,
				-- waterfront piers, and a forested ridge behind it.
				Offset = Vector3.new(-1050, 0, -1819),
				SizeStuds = 1100,
				Biome = "highland",
				Theme = "town",
				Abandoned = false,
				Merchant = true,
				Church = true,
				Mansions = 2,
				Lit = true,
				Lighthouse = true,
				Docks = 3,
				Villagers = { Passive = 18, Hostile = 3 },
				Loot = { Weapons = 9, Chests = 7, Armor = 5 },
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
