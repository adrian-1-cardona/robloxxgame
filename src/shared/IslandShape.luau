--!nocheck
-- =====================================================================================
-- IslandShape — organic island silhouettes for Survive at Sea
-- =====================================================================================
--
-- Every voyage island is generated from this module, and an island is NEVER a disc, a
-- dome, or a bullseye. The layout reproduces the reference art:
--
--   * ONE irregular, lobed landmass — the coast radius is a harmonic function of bearing
--     with broad arms, headlands and coves, so no arc of the shoreline is a circular arc.
--   * ONE large lagoon, placed OFF CENTRE on a single flank with an organic outline, open
--     to the sea through a single broad mouth. It is a bay carved into one side of the
--     island, not a moat ring around the middle.
--   * A faceted landmark (volcano / peak / rocky ridge) on the OPPOSITE flank, so the
--     island reads as "water on one side, mountain on the other".
--   * A sand beach at every waterline: outer coast, lagoon shore and river banks.
--   * A rolling interior with many separate knolls, and one modest, off-centre shelf that
--     the settlement is built on.
--   * Navigable channels MEANDER. A river is a curved valley, never a straight rectangle.
--
-- Two earlier attempts are worth not repeating. Stacking `FillCylinder` discs and
-- `FillBall` balls gives radial symmetry, which is what made islands look like round
-- blobs. Replacing that with a *concentric* lagoon ring plus a circular central plain
-- traded one symmetric look for another — a bullseye — and a straight rectangular river
-- slab cut across it like a ruler. Both are why the geometry here is deliberately
-- built from off-centre, non-concentric features.
--
-- The module is PURE LUAU (no Roblox globals, no Vector3, no Random) so the exact
-- silhouette the server rasterises into voxel Terrain can also be asserted and rendered
-- headlessly — see tests/IslandShape.spec.luau and tests/IslandPreview.luau.
--
-- Coordinate convention: every function takes offsets (dx, dz) measured from the island
-- centre, and returns heights in studs relative to Config.Islands.TopY. Sea level is
-- `opts.seaOffset` (negative) in that same space.
local IslandShape = {}
IslandShape.__index = IslandShape

local TAU = math.pi * 2

-- ==========================================================================================
-- Deterministic helpers (no Random / math.random anywhere: same island every boot)
-- ==========================================================================================

local function hashString(id: string): number
	local h = 2166136261
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 2147483647
	end
	return h
end

-- Park-Miller stream. Stable, tiny, and identical in Roblox and in Lune.
local function makeStream(seed: number): () -> number
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

local function smoothstep(t: number): number
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function fract(x: number): number
	return x - math.floor(x)
end

local function hash2(seed: number, ix: number, iz: number): number
	return fract(math.sin(ix * 127.1 + iz * 311.7 + seed * 0.0137) * 43758.5453123)
end

local function valueNoise(seed: number, x: number, z: number): number
	local x0, z0 = math.floor(x), math.floor(z)
	local tx, tz = smoothstep(x - x0), smoothstep(z - z0)
	local c00 = hash2(seed, x0, z0)
	local c10 = hash2(seed, x0 + 1, z0)
	local c01 = hash2(seed, x0, z0 + 1)
	local c11 = hash2(seed, x0 + 1, z0 + 1)
	return lerp(lerp(c00, c10, tx), lerp(c01, c11, tx), tz)
end

-- Three octaves, centred on zero, roughly [-1, 1].
local function fbm(seed: number, x: number, z: number): number
	local v = valueNoise(seed, x, z) * 0.58
		+ valueNoise(seed + 91, x * 2.17, z * 2.17) * 0.28
		+ valueNoise(seed + 173, x * 4.41, z * 4.41) * 0.14
	return v * 2 - 1
end

local function angleDelta(a: number, b: number): number
	local d = (a - b) % TAU
	if d > math.pi then
		d -= TAU
	end
	return d
end

local function harmonics(profile: { { k: number, amp: number, phase: number } }, angle: number): number
	local sum = 0
	for _, h in profile do
		sum += h.amp * math.sin(h.k * angle + h.phase)
	end
	return sum
end

-- ==========================================================================================
-- Construction
-- ==========================================================================================

-- height is a fraction of island size; baseR a fraction of half.
local BIOME_LANDMARK = {
	volcanic = { kind = "volcano", height = 0.150, baseR = 0.34, falloff = 1.30, facets = 7 },
	mountain = { kind = "peak", height = 0.155, baseR = 0.34, falloff = 1.42, facets = 6 },
	jungle = { kind = "ridge", height = 0.105, baseR = 0.31, falloff = 1.18, facets = 5 },
	highland = { kind = "ridge", height = 0.096, baseR = 0.32, falloff = 1.14, facets = 5 },
	palm = { kind = "knoll", height = 0.058, baseR = 0.27, falloff = 1.05, facets = 4 },
	beach = { kind = "knoll", height = 0.052, baseR = 0.25, falloff = 1.05, facets = 4 },
	twin_peaks = { kind = "ridge", height = 0.100, baseR = 0.28, falloff = 1.25, facets = 6 },
}

-- Ceiling on how much of an island's own footprint may be inland water. The reference
-- island is land with a bay bitten out of it; past roughly a third, the land degenerates
-- into thin arms with nowhere to walk, build a village, or place a forest.
-- An atoll is legitimately part water: the reference island's lagoon is roughly a third of
-- its footprint. The cap exists to stop the land degenerating into thin strands with
-- nowhere to walk, build a village, or grow a forest.
local MAX_WATER_FRACTION = 0.32

--[[
	opts:
		biome      "beach" | "palm" | "jungle" | "highland" | "volcanic" | "mountain"
		theme      settlement theme; "wild" / "abandoned" keep the shelf smaller
		seaOffset  sea level relative to topY (negative; defaults to -3)
		river      { angle = number, width = number } navigable sea-to-sea channel
		volcano    force / suppress the crater on a volcanic isle
		lake       force / suppress the highland lake
		lagoon     force / suppress the main lagoon (default: on)
]]
function IslandShape.new(id: string, size: number, opts: { [string]: any }?)
	local o = opts or {}
	local half = size * 0.5
	local seed = hashString(id)
	local rand = makeStream(seed + 7)

	local self = setmetatable({}, IslandShape)
	self.id = id
	self.size = size
	self.half = half
	self.seed = seed
	self.noiseSeed = (seed % 9973) + 11
	self.biome = (o.biome :: string?) or "beach"
	self.theme = (o.theme :: string?) or "wild"
	self.seaOffset = (o.seaOffset :: number?) or -3

	-- ---- Outer coastline -------------------------------------------------------------
	-- Three to five broad arms plus finer bays and points. The low order sets the overall
	-- silhouette; the high orders make sure the edge never settles into an arc.
	local arms = 3 + math.floor(rand() * 2.99)
	self.arms = arms
	self.coastBase = 0.845
	self.coastProfile = {
		{ k = arms, amp = 0.070 + rand() * 0.030, phase = rand() * TAU },
		{ k = arms + 2, amp = 0.032 + rand() * 0.018, phase = rand() * TAU },
		{ k = 7, amp = 0.015 + rand() * 0.010, phase = rand() * TAU },
		{ k = 11, amp = 0.009 + rand() * 0.007, phase = rand() * TAU },
	}

	-- ---- Vertical profile ------------------------------------------------------------
	self.beachWidth = math.clamp(half * 0.052, 15, 44)
	self.riseWidth = math.max(half * 0.085, 26)
	self.reliefScale = math.max(half * 0.17, 44)
	self.hillCrest = 17 + rand() * 11
	-- The sandy arms are low dunes, not hills, and most of their surface stays bare sand.
	self.armCrest = 6 + rand() * 4
	self.armSandLine = 4.6 + rand() * 1.6
	self.shelfHeight = 1.1
	self.shelfWidth = math.max(half * 0.055, 22)
	self.shelfTop = self.seaOffset - 3.0
	self.lagoonBed = self.seaOffset - 7.5
	self.channelBed = self.seaOffset - 11
	self.baseBottom = self.seaOffset - 40

	-- Coast extremes: cheap broad-phase bounds for raft collision and streaming.
	local minCoast, maxCoast = math.huge, 0
	for i = 0, 359 do
		local c = self:coastRadius((i / 360) * TAU)
		minCoast = math.min(minCoast, c)
		maxCoast = math.max(maxCoast, c)
	end
	self.minCoast = minCoast
	self.maxCoast = maxCoast

	-- ---- The atoll: sandy outer arms, lagoon, and an off-centre inner island ---------
	-- This is the reference silhouette: a WIDE sand ring wraps a lagoon, and a separate
	-- jungle-covered inner island carrying the volcano sits inside it, off to one side.
	--
	-- The ring is what makes an island read as a tropical atoll rather than a green lump,
	-- but it is also how this generator previously produced a bullseye. Three things keep
	-- it organic here: the ring WIDTH varies with bearing, the lagoon's inner rim varies
	-- with bearing AND is shifted off centre (the `coreShift` cosine term), and the lagoon
	-- only opens across two or three windows, with solid land bridges joining the arms to
	-- the inner island between them.
	self.ringBase = 0.180 + rand() * 0.055
	self.ringProfile = {
		{ k = 2, amp = 0.040, phase = rand() * TAU },
		{ k = 3, amp = 0.026, phase = rand() * TAU },
		{ k = 5, amp = 0.015, phase = rand() * TAU },
	}
	-- The inner island has to be broad enough to carry a volcano, a jungle and a village.
	-- Keep its rim gently irregular: strong high-order harmonics here tear it into thin
	-- spikes that read as damage rather than as a coastline.
	self.coreBase = 0.440 + rand() * 0.065
	self.coreProfile = {
		{ k = 2, amp = 0.060, phase = rand() * TAU },
		{ k = 3, amp = 0.038, phase = rand() * TAU },
		{ k = 5, amp = 0.018, phase = rand() * TAU },
	}
	-- Push the inner island off centre so the lagoon is broad on one side and narrow on
	-- the other, the way the reference has its ships anchored in the wide southern water.
	self.coreAngle = rand() * TAU
	self.coreShift = half * (0.040 + rand() * 0.060)

	local windowCount = 2 + math.floor(rand() * 1.99)
	self.lagoonWindows = {}
	self.ringNotches = {}
	local firstWindow = rand() * TAU
	for i = 1, windowCount do
		local centre = firstWindow + (i - 1) * (TAU / windowCount) + (rand() - 0.5) * 0.45
		-- Window width plus feather must stay inside its share of the circle, or adjacent
		-- windows meet and the lagoon closes into an unbroken ring — which leaves the inner
		-- island cut off from the arms entirely. Measured at the old (0.60..0.92) widths,
		-- 6 of 13 islands shipped as 2-3 separate landmasses.
		local halfWidth = (0.42 + rand() * 0.16) * (math.pi / windowCount)
		table.insert(self.lagoonWindows, {
			center = centre % TAU,
			halfWidth = halfWidth,
			feather = halfWidth * 0.40,
		})
	end

	-- ---- The bay ---------------------------------------------------------------------
	-- An extra lobe bitten out of ONE flank, with an organic rim and a mouth to the sea.
	-- It merges with the lagoon into a single connected water system and is what the
	-- arrival island's spawn basin is pinned to.
	-- Put the anchorage on a lagoon WINDOW bearing. On a land-bridge bearing the bay is not
	-- carved at all (bridges are protected), so the "bay" came out as dry ground and crews
	-- were moored on a causeway — four islands shipped with sealed, landlocked anchorages.
	local lagoonAngle = rand() * TAU
	if #self.lagoonWindows > 0 then
		local best = self.lagoonWindows[1]
		for _, w in self.lagoonWindows do
			if math.abs(angleDelta(lagoonAngle, w.center)) < math.abs(angleDelta(lagoonAngle, best.center)) then
				best = w
			end
		end
		lagoonAngle = best.center
	end
	if o.lagoon ~= false then
		-- Sit the bay OUT IN THE LAGOON ANNULUS, between the inner island's rim and the
		-- sandy arms — not near the island centre. Centred, it carved a crescent out of the
		-- inner island and left the volcano perched on a thin arc. Out here it instead
		-- widens the lagoon into an anchorage, which is where the reference moors its ships
		-- and where crew rafts berth.
		-- Sit it on the annulus midline at this bearing, measured from the real core rim and
		-- arm edge. A fixed fraction of `half` does not work: the inner island's rim reaches
		-- 0.6 of half on some bearings, so a bay pinned at 0.50 landed inside the core, was
		-- suppressed (the core is protected), and became dry land.
		local ringInnerHere = self:coastRadius(lagoonAngle) - self:ringWidth(lagoonAngle)
		local coreHere = self:coreRadius(lagoonAngle)
		local margin = self.beachWidth * 0.9
		local lo, hi = coreHere + margin, ringInnerHere - margin
		local lagoonDist = if hi > lo then (lo + hi) * 0.5 else (coreHere + ringInnerHere) * 0.5
		self.lagoon = {
			angle = lagoonAngle,
			x = math.cos(lagoonAngle) * lagoonDist,
			z = math.sin(lagoonAngle) * lagoonDist,
			distance = lagoonDist,
			baseR = half * (0.15 + rand() * 0.06),
			profile = {
				{ k = 2, amp = 0.150, phase = rand() * TAU },
				{ k = 3, amp = 0.105, phase = rand() * TAU },
				{ k = 5, amp = 0.058, phase = rand() * TAU },
				{ k = 8, amp = 0.030, phase = rand() * TAU },
			},
			-- The mouth: a curved channel from the bay out through the coastal arm.
			mouthAngle = lagoonAngle + (rand() - 0.5) * 0.5,
			mouthHalfWidth = math.max(half * (0.045 + rand() * 0.020), 30),
			mouthMeanderAmp = half * (0.025 + rand() * 0.025),
			mouthMeanderLen = math.max(half * 0.30, 60),
			mouthMeanderPhase = rand() * TAU,
		}
		--[[
			Spawn basin: an area the bay MUST cover in open water.

			The arrival island is where crews board, and their rafts are placed on a fixed
			line of slots through the island's own centre. Generating the bay freely put dry
			land and a 127-stud river channel under those slots, so rafts would have spawned
			inside terrain. Pinning the bay to the island centre instead is what produced the
			moat/bullseye silhouette, so the basin is expressed as a REQUIREMENT here: the
			bay keeps its irregular rim and stays on one flank, but it is grown and moved so
			every slot is over water, and its mouth is aimed outward so crews can sail out.
		]]
		if o.spawnBasinRadius then
			-- A minimum rim, NOT a relocation. Two other approaches were tried and both
			-- reintroduced the symmetry this generator exists to avoid: pinning the bay to
			-- the island centre made it a moat, and inflating baseR until the smallest
			-- harmonic bearing covered the basin blew the bay out to over half the island.
			-- Holding the rim at a floor keeps the bay off centre and modest, and the
			-- harmonics still carry the rest of its outline outward.
			local basin = o.spawnBasinRadius :: number
			self.lagoonMinRim = basin
			self.lagoon.mouthAngle = self.lagoon.angle

			-- A berth grid for four rafts needs a disc of clear water roughly 550 studs
			-- across. No atoll lagoon on a 750-stud island can contain that: the annulus
			-- between the inner island and the sand arms is only ~130 studs wide, and
			-- drawing the inner island in far enough to fit the basin dissolves the jungle
			-- core into a sandbar (measured: 92% of the island turned to beach).
			--
			-- So the boarding island gets an OPEN HARBOUR instead of an enclosed lagoon: the
			-- sand ring is notched away across the bay's bearing, and the anchorage is
			-- pushed out far enough that its whole basin clears the inner island. Berths
			-- nearest the island lie in sheltered harbour water and the outermost lie just
			-- beyond the coast in open sea — all of them afloat. Every other island keeps
			-- the closed atoll silhouette.
			-- Freeze the inner island BEFORE measuring the harbour. `_fitLagoon`'s area cap
			-- grows `coreBase` to reduce water, and the harbour offset below is computed from
			-- the core rim — so without this the rim creeps into the raft basin afterwards
			-- and rafts spawn in terrain. `coreMax` is the ceiling the area cap honours.
			self.coreMax = self.coreBase
			local harbourDistance = self:coreRadius(lagoonAngle) + basin + self.beachWidth * 1.5
			self.lagoon.distance = harbourDistance
			self.lagoon.x = math.cos(lagoonAngle) * harbourDistance
			self.lagoon.z = math.sin(lagoonAngle) * harbourDistance
			self.lagoon.baseR = math.max(self.lagoon.baseR, basin)
			-- Open the sand arms and the lagoon across the harbour mouth.
			self.harbourNotch = { center = lagoonAngle % TAU, halfWidth = 0.62, feather = 0.34 }
			table.insert(self.ringNotches, self.harbourNotch)
			table.insert(self.lagoonWindows, {
				center = lagoonAngle % TAU,
				halfWidth = 0.62,
				feather = 0.30,
			})
		end
		-- NOTE: the bay is fitted further down, once the river and the lake exist. Fitting
		-- it here made the area cap measure a height field with no channel and no lake in
		-- it, so it always read well under the limit and never actually fired.
	end

	-- ---- River (navigable sea-to-sea channel) ----------------------------------------
	local river = o.river
	if river then
		-- Rafts are stopped at the shoreline by IslandService.collideRaft, so a channel
		-- wide enough to steer a raft down is decoration only — and a 300-to-440 stud
		-- trench turns an island into two separate halves of blue. Cap it at a width a
		-- real river would have on a landmass this size.
		local requested = (river.width :: number?) or (size * 0.07)
		-- Wide enough to read as a channel, never wide enough to halve the island. The
		-- ceiling has to be raised to a floor of its own, or a small isle produces
		-- `clamp(min > max)`.
		local maxWidth = math.max(size * 0.055, 62)
		local width = math.clamp(requested, 55, maxWidth)
		self.river = {
			angle = (river.angle :: number?) or 0,
			width = width,
			requestedWidth = requested,
			length = size * 1.25,
			-- Meander so the channel is a winding valley. A straight slab looks like a
			-- ruler laid across the island and is the single most artificial thing a
			-- generated island can have.
			meanderAmp = math.max(width * 0.9, half * 0.12),
			meanderLen = math.max(size * 0.17, 90),
			meanderPhase = rand() * TAU,
			widthWobble = 0.18 + rand() * 0.14,
			widthPhase = rand() * TAU,
		}
	end

	-- ---- Route the water openings through the lagoon windows -------------------------
	-- The land bridges are now inviolable, so a pass or a bay mouth aimed at a bridge
	-- bearing simply does not get carved and the lagoon seals into a pond. Snap both to the
	-- nearest window centre, which is where the lagoon is open and where a channel through
	-- the sand arms belongs anyway.
	if #self.lagoonWindows > 0 then
		local function nearestWindow(angle: number): number
			local best, bestDelta = angle, math.huge
			for _, w in self.lagoonWindows do
				local d = math.abs(angleDelta(angle, w.center))
				if d < bestDelta then
					best, bestDelta = w.center, d
				end
			end
			return best
		end
		if self.lagoon then
			self.lagoon.mouthAngle = nearestWindow(self.lagoon.mouthAngle)
		end
		if self.river then
			self.river.angle = nearestWindow(self.river.angle)
		end

		-- The tidal pass. Cut it as a gap in the sand arm at a window bearing, narrower than
		-- the window itself so arm land survives on both sides of it. This is the ONLY thing
		-- that vents the lagoon, which is why it is guaranteed here rather than left to a
		-- channel or bay mouth that might be aimed at a causeway.
		-- Land bridges segment the lagoon into separate arcs, so a single pass only vents the
		-- arc it sits in. The anchorage's own arc must always be vented, or crews are moored
		-- in a sealed pond; a river island additionally gets a pass on its channel bearing.
		local function windowNearest(angle: number)
			local best = self.lagoonWindows[1]
			for _, w in self.lagoonWindows do
				if math.abs(angleDelta(angle, w.center)) < math.abs(angleDelta(angle, best.center)) then
					best = w
				end
			end
			return best
		end
		local function notchAt(window)
			for _, existing in self.ringNotches do
				if math.abs(angleDelta(existing.center, window.center)) < 0.01 then
					return
				end
			end
			local passHalf = math.max(window.halfWidth * 0.34, 0.10)
			table.insert(self.ringNotches, {
				center = window.center,
				halfWidth = passHalf,
				feather = passHalf * 0.5,
			})
		end

		local anchorWindow = windowNearest(if self.lagoon then self.lagoon.angle else 0)
		notchAt(anchorWindow)
		self.passAngle = anchorWindow.center
		if self.river then
			notchAt(windowNearest(self.river.angle))
		end
	end

	-- ---- Landmark (cone / peak / rocky ridge) ----------------------------------------
	-- Opposite the lagoon, on solid ground, clear of the channel.
	local spec = BIOME_LANDMARK[self.biome] or BIOME_LANDMARK.beach
	local wantsVolcano = self.biome == "volcanic" and o.volcano ~= false
	-- Read the bay's FINAL bearing, not the raw draw: a catalog override or a boarding
	-- basin can move it, and the landmark has to end up opposite wherever it actually is.
	local landmarkAngle = self:_pickLandmarkAngle(rand, if self.lagoon then self.lagoon.angle else lagoonAngle)
	-- The landmark belongs on the INNER ISLAND, which is the only part of an atoll broad
	-- and high enough to carry it. Anchoring it to the inner island's centre (rather than
	-- to a fraction of the coast radius) is what keeps the cone out of the lagoon and off
	-- the low sand arms, where it would look like a mountain growing out of a beach.
	local coreCentreX = math.cos(self.coreAngle) * self.coreShift
	local coreCentreZ = math.sin(self.coreAngle) * self.coreShift
	-- Keep the foot inside the inner island's narrowest bearing.
	local coreNarrowest = math.huge
	for i = 0, 35 do
		coreNarrowest = math.min(coreNarrowest, self:coreRadius((i / 36) * TAU))
	end
	-- Leave most of the inner island free. At 0.82 of the narrowest core bearing the cone's
	-- foot covered nearly the whole jungle mass, so the settlement fitter could only find a
	-- 38-stud ring of flat ground and villages came out cramped against the lagoon.
	local baseR = math.min(half * spec.baseR, math.max(coreNarrowest * 0.55, half * 0.12))
	-- Drift the peak well off the inner island's centre so one side of the core stays open
	-- for the village — the reference has its town on the shore below the volcano, not
	-- wrapped around it.
	local drift = math.max(coreNarrowest - baseR, 0) * 0.55
	local lmX = coreCentreX + math.cos(landmarkAngle) * drift
	local lmZ = coreCentreZ + math.sin(landmarkAngle) * drift
	local landmark = {
		kind = if wantsVolcano then "volcano" else spec.kind,
		angle = landmarkAngle,
		x = lmX,
		z = lmZ,
		distance = math.sqrt(lmX * lmX + lmZ * lmZ),
		baseR = baseR,
		height = size * spec.height,
		falloff = spec.falloff,
		facets = spec.facets,
		facetPhase = rand() * TAU,
		-- Ridge landmarks are elongated, so they read as a spine rather than a cone.
		elongation = if spec.kind == "ridge" then 0.42 + rand() * 0.22 else 0,
		ridgeYaw = landmarkAngle + math.pi * 0.5 + (rand() - 0.5) * 1.1,
	}
	if landmark.kind == "volcano" then
		landmark.craterR = baseR * 0.17
		landmark.craterDepth = landmark.height * 0.13
	end
	self.landmark = landmark

	-- ---- Highland lake ---------------------------------------------------------------
	if (self.biome == "mountain" and o.lake ~= false) or o.lake == true then
		local lakeAngle = landmarkAngle + math.pi * (0.55 + rand() * 0.3)
		local lakeDist = half * (0.24 + rand() * 0.12)
		self.lake = {
			angle = lakeAngle,
			x = math.cos(lakeAngle) * lakeDist,
			z = math.sin(lakeAngle) * lakeDist,
			baseR = half * 0.115,
			profile = {
				{ k = 2, amp = 0.22, phase = rand() * TAU },
				{ k = 3, amp = 0.14, phase = rand() * TAU },
				{ k = 5, amp = 0.08, phase = rand() * TAU },
			},
			surface = 1.2,
			bed = -9.5,
		}
	end

	-- Fit the bay now that every other water feature exists: the geometric clamp keeps it
	-- inside the coastal band, and the area cap can see the channel and the lake it shares
	-- the island with.
	self:_fitLagoon()

	-- ---- Settlement shelf ------------------------------------------------------------
	-- A modest, OFF-CENTRE flattening the village is built on. Deliberately not a large
	-- disc at the island centre: that reads as a bullseye and wastes the whole interior.
	self.shelfSearchRadius = half * (if self.theme == "wild" then 0.30 else 0.42)
	self:_placeShelf(rand)

	return self
end

-- Shrink the bay until two things hold, both of which the earlier ring-shaped lagoon got
-- wrong:
--
--   1. A continuous band of land (plus its beach) survives between the bay rim and the
--      outer coast at EVERY bearing. That keeps the island one walkable landmass instead
--      of a set of disconnected arms, and guarantees the outer beach is never breached
--      except along the single mouth channel.
--   2. Inland water stays under MAX_WATER_FRACTION of the footprint, so there is real
--      ground for a village, a forest and a mountain.
function IslandShape:_fitLagoon()
	local lagoon = self.lagoon
	if not lagoon then
		return
	end
	local margin = self.beachWidth * 1.6

	-- (1) Geometric clamp. For each bearing off the bay's own centre, find how far the rim
	-- may reach before it eats the coastal band, and keep the tightest limit.
	local allowed = math.huge
	for i = 0, 71 do
		local a = (i / 72) * TAU
		local ux, uz = math.cos(a), math.sin(a)
		-- Largest t where (lagoon centre + t * u) still sits `margin` inside the coast.
		local limit = 0
		local t = self.half * 0.04
		while t <= self.half * 1.2 do
			local px, pz = lagoon.x + ux * t, lagoon.z + uz * t
			local pr = math.sqrt(px * px + pz * pz)
			if pr > self:coastRadius(math.atan2(pz, px)) - margin then
				break
			end
			limit = t
			t += self.half * 0.02
		end
		-- Convert the positional limit back into a base radius via this bearing's profile.
		local shapeFactor = math.clamp(1 + harmonics(lagoon.profile, a), 0.50, 1.55)
		allowed = math.min(allowed, limit / shapeFactor)
	end
	local floor = self.half * 0.10
	lagoon.baseR = math.clamp(math.min(lagoon.baseR, allowed), floor, self.half * 0.34)

	-- (2) Area cap. Measured on the real height field, so it accounts for the atoll lagoon,
	-- the bay, its mouth, the river and the lake all contributing water to one island.
	-- Growing the inner island is the first lever, because on an atoll the lagoon annulus
	-- holds far more water than the bay lobe does; shrinking only the bay would pin it at
	-- its floor without ever bringing the total down.
	for _ = 1, 16 do
		if self:waterFraction() <= MAX_WATER_FRACTION then
			break
		end
		local coreCeiling = self.coreMax or 0.56
		if self.coreBase < coreCeiling then
			self.coreBase = math.min(self.coreBase * 1.06, coreCeiling)
		elseif lagoon.baseR * 0.92 >= floor then
			lagoon.baseR *= 0.92
			lagoon.mouthHalfWidth *= 0.96
		else
			lagoon.mouthHalfWidth *= 0.96
			break
		end
	end
end

-- Where crew rafts berth on a boarding island: the centre of its sheltered bay, as offsets
-- from the island centre. Rafts used to be placed on a line through the island's centre,
-- which is why the hub had to keep water in the middle of itself.
function IslandShape:berthAnchor(): (number, number)
	if self.lagoon then
		return self.lagoon.x, self.lagoon.z
	end
	return 0, 0
end

-- Fraction of the island's own footprint (inside the coastline) that is inland water.
function IslandShape:waterFraction(): number
	local inside, water = 0, 0
	local step = math.max(self.half / 22, 8)
	self:forEachCell(step, function(_, _, kind)
		if kind == "land" then
			inside += 1
		elseif kind == "water" then
			inside += 1
			water += 1
		end
	end)
	if inside == 0 then
		return 0
	end
	return water / inside
end

-- A bearing that sits opposite the lagoon, on land, and off the navigable channel, so the
-- landmark rises from a broad landmass instead of out of the water.
function IslandShape:_pickLandmarkAngle(rand: () -> number, lagoonAngle: number): number
	local best, bestScore = lagoonAngle + math.pi, -math.huge
	local jitter = rand() * TAU
	for i = 0, 71 do
		local a = jitter + (i / 72) * TAU
		-- Prefer the flank opposite the bay.
		local score = math.abs(angleDelta(a, lagoonAngle)) * 1.4
		-- Reject bearings whose mid-radius is water (the bay, its mouth, the channel).
		local coast = self:coastRadius(a)
		local probe = coast * 0.5
		local kind = self:sample(math.cos(a) * probe, math.sin(a) * probe)
		if kind ~= "land" then
			score -= 6
		end
		if self.river then
			local d = math.min(
				math.abs(angleDelta(a, self.river.angle)),
				math.abs(angleDelta(a, self.river.angle + math.pi))
			)
			score += math.min(d, 1.1) * 0.85
		end
		if score > bestScore then
			best, bestScore = a % TAU, score
		end
	end
	return best
end

-- Search the finished height field for the best village site: low, flat, on land, clear of
-- the landmark's foot and the water. Candidates are biased to the lagoon shore so towns get
-- a harbour, matching the reference village looking out over the water.
function IslandShape:_placeShelf(rand: () -> number)
	-- Sweep a grid of candidate centres over the island and keep the one with the most
	-- usable room, breaking ties toward the bay so a town ends up with a harbour front.
	--
	-- A hand-written candidate list was tried first and does not work: "downhill of the
	-- landmark" points straight at the lagoon (the landmark is placed opposite the bay),
	-- and sites hugging the bay rim can never grow past the beach they sit on. Both
	-- collapsed almost every island to the minimum clearing.
	local cap = self.half * 0.30
	local step = math.max(self.half * 0.11, 26)
	local reach = self.half * 0.66
	local jitter = (rand() - 0.5) * step * 0.5

	local best = { x = 0, z = 0, radius = 0, score = -math.huge }
	local dx = -reach + jitter
	while dx <= reach do
		local dz = -reach + jitter
		while dz <= reach do
			local radius = self:_shelfFit(dx, dz)
			if radius > 0 then
				local score = math.min(radius, cap)
				if self.lagoon then
					-- Prefer a waterfront: penalise distance from the bay rim.
					local ldx, ldz = dx - self.lagoon.x, dz - self.lagoon.z
					local ld = math.sqrt(ldx * ldx + ldz * ldz)
					local rim = self:lagoonRadius(math.atan2(ldz, ldx))
					score -= math.abs(ld - rim) * 0.16
				end
				if score > best.score then
					best = { x = dx, z = dz, radius = radius, score = score }
				end
			end
			dz += step
		end
		dx += step
	end

	self.villageX = best.x
	self.villageZ = best.z
	-- Cap the shelf so it stays a settlement clearing rather than flattening the isle.
	-- Inset by one probe step: the fit records the last radius that was fully clear, so the
	-- boundary itself is the first ring that failed. Building right up to it puts the outer
	-- street on the waterline.
	local inset = best.radius * 0.94
	self.buildableRadius = math.min(math.max(inset, self.half * 0.07), self.half * 0.30)
	self.shelf = {
		x = best.x,
		z = best.z,
		radius = self.buildableRadius,
		feather = math.max(self.buildableRadius * 0.55, 20),
	}
end

-- Largest radius of dry ground around (cx, cz) that is clear of the landmark and the lake.
--
-- Height is deliberately NOT a rejection reason: the shelf flattens whatever hill it lands
-- on, which is what a cleared village site is. Requiring pre-existing flat ground instead
-- made almost every island fall back to the minimum clearing, cramming whole towns into a
-- 39-stud circle.
function IslandShape:_shelfFit(cx: number, cz: number): number
	local limit = self.shelfSearchRadius
	if self.lake then
		local dx, dz = self.lake.x - cx, self.lake.z - cz
		limit = math.min(limit, math.sqrt(dx * dx + dz * dz) - self.lake.baseR * 1.5)
	end
	if limit <= 0 then
		return 0
	end
	-- The landmark is tested per sample rather than as a circle around its centre,
	-- because a ridge's footprint is an ellipse (see landmarkDistance).
	if self:sample(cx, cz) ~= "land" or self:onLandmark(cx, cz) then
		return 0
	end

	local step = math.max(self.half * 0.03, 10)
	local radius, r = 0, step
	while r <= limit do
		-- 32 bearings, not 16. At 16 the probes are far enough apart on a large clearing that
		-- a narrow inlet of lagoon water slips between two of them, and the village footprint
		-- that gets derived from this radius then has houses standing in the water.
		for i = 0, 31 do
			local a = (i / 32) * TAU
			local px, pz = cx + math.cos(a) * r, cz + math.sin(a) * r
			if self:sample(px, pz) ~= "land" or self:onLandmark(px, pz) then
				return radius
			end
		end
		radius = r
		r += step
	end
	return radius
end

-- ==========================================================================================
-- Outline queries
-- ==========================================================================================

function IslandShape:coastRadius(angle: number): number
	local v = self.coastBase + harmonics(self.coastProfile, angle)
	return self.half * math.clamp(v, 0.42, 0.995)
end

-- Bay rim distance from the lagoon's own centre, at a bearing measured from that centre.
-- Width of the sandy outer arm at this bearing. Varies so the ring is never a clean band.
function IslandShape:ringWidth(angle: number): number
	local v = self.ringBase + harmonics(self.ringProfile, angle)
	local width = self.half * math.clamp(v, 0.10, 0.34)
	-- Notches cut the sand arm away to nothing: the tidal pass that vents the lagoon, and a
	-- boarding island's wider harbour mouth. Expressing the opening as a gap in the RING
	-- rather than as a separate carved channel is what keeps it from severing a land bridge:
	-- a notch only ever sits inside a lagoon window, where there is no causeway to cut.
	for _, notch in self.ringNotches do
		local d = math.abs(angleDelta(angle, notch.center))
		local w = 0
		if d <= notch.halfWidth then
			w = 1
		elseif d < notch.halfWidth + notch.feather then
			w = 1 - smoothstep((d - notch.halfWidth) / notch.feather)
		end
		width *= 1 - w
	end
	return width
end

-- Distance from the island centre to the inner island's rim at this bearing. The cosine
-- term shifts the whole inner mass off centre, which is what stops the lagoon reading as
-- a concentric moat.
function IslandShape:coreRadius(angle: number): number
	local v = self.coreBase + harmonics(self.coreProfile, angle)
	local shift = self.coreShift * math.cos(angle - self.coreAngle)
	return math.max(self.half * math.clamp(v, 0.16, 0.62) + shift, self.half * 0.10)
end

-- 1 in the middle of an open lagoon window, 0 on a solid land bridge.
function IslandShape:lagoonWindowWeight(angle: number): number
	local best = 0
	for _, w in self.lagoonWindows do
		local d = math.abs(angleDelta(angle, w.center))
		if d <= w.halfWidth then
			best = math.max(best, 1)
		elseif d < w.halfWidth + w.feather then
			best = math.max(best, 1 - smoothstep((d - w.halfWidth) / w.feather))
		end
	end
	return best
end

-- Inner / outer radius of the lagoon at this bearing, or nil where a land bridge carries
-- the arms straight through to the inner island.
function IslandShape:lagoonBand(angle: number): (number?, number?)
	local weight = self:lagoonWindowWeight(angle)
	if weight <= 0.02 then
		return nil, nil
	end
	local outer = self:coastRadius(angle) - self:ringWidth(angle)
	local core = self:coreRadius(angle)
	if core >= outer then
		return nil, nil
	end
	-- Fade the lagoon shut toward each window edge so its shoreline curves into the land
	-- bridge instead of stopping at a straight wall.
	local inner = lerp(outer, core, weight)
	if outer - inner < self.half * 0.03 then
		return nil, nil
	end
	return inner, outer
end

function IslandShape:lagoonRadius(angle: number): number
	local lagoon = self.lagoon
	if not lagoon then
		return 0
	end
	local rim = lagoon.baseR * math.clamp(1 + harmonics(lagoon.profile, angle), 0.50, 1.55)
	-- Boarding islands hold a minimum rim so the crew berths stay over open water.
	if self.lagoonMinRim then
		return math.max(rim, self.lagoonMinRim)
	end
	return rim
end

function IslandShape:lakeRadius(angle: number): number
	local lake = self.lake
	if not lake then
		return 0
	end
	return lake.baseR * math.clamp(1 + harmonics(lake.profile, angle), 0.45, 1.6)
end

--[[
	Distance from the landmark's centre measured in the landmark's OWN space. Anything
	below `landmark.baseR` is standing on the landform.

	Ridge landmarks squash their long axis, so their footprint is an ellipse reaching
	`baseR / elongation` along the spine — up to about 2.4x baseR. Anything that needs to
	keep clear of the landform has to use this metric; a plain circular test around the
	centre badly underestimates a ridge and lets it rise straight through a village.
]]
function IslandShape:landmarkDistance(dx: number, dz: number): number
	local lm = self.landmark
	if not lm then
		return math.huge
	end
	local ldx, ldz = dx - lm.x, dz - lm.z
	if lm.elongation > 0 then
		local c, s = math.cos(lm.ridgeYaw), math.sin(lm.ridgeYaw)
		local along = (ldx * c + ldz * s) * lm.elongation
		local across = -ldx * s + ldz * c
		return math.sqrt(along * along + across * across)
	end
	return math.sqrt(ldx * ldx + ldz * ldz)
end

-- True when (dx, dz) stands on the landmark's slopes.
function IslandShape:onLandmark(dx: number, dz: number): boolean
	local lm = self.landmark
	return lm ~= nil and self:landmarkDistance(dx, dz) < lm.baseR
end

-- River-local coordinates: `along` runs down the channel, `across` is the bank axis.
function IslandShape:riverLocal(dx: number, dz: number): (number, number)
	local river = self.river
	if not river then
		return 0, math.huge
	end
	local c, s = math.cos(river.angle), math.sin(river.angle)
	return dx * c + dz * s, -dx * s + dz * c
end

--[[
	Where the channel is at a given distance along its axis: the offset of its centreline
	from that axis, and how wide it is there.

	Two sine terms of different wavelengths give a curved, non-repeating course, and the
	width breathes slightly along it — a valley rather than a slab. Anything that has to
	meet the river (a bridge, a bank-side prop) must ask for the course here instead of
	assuming the channel runs down the island's centre line, because it does not.
]]
function IslandShape:riverCourse(along: number): (number, number)
	local river = self.river
	if not river then
		return 0, 0
	end
	local centre = river.meanderAmp * math.sin(along / river.meanderLen + river.meanderPhase)
		+ river.meanderAmp * 0.42 * math.sin(along / (river.meanderLen * 0.43) + river.meanderPhase * 1.7)
	local width = river.width
		* (1 + river.widthWobble * math.sin(along / (river.meanderLen * 0.8) + river.widthPhase))
	return centre, width
end

-- Signed distance outside the channel walls: <= 0 means inside the navigable water.
function IslandShape:riverEdge(dx: number, dz: number): number
	local river = self.river
	if not river then
		return math.huge
	end
	local along, across = self:riverLocal(dx, dz)
	if math.abs(along) > river.length * 0.5 then
		return math.huge
	end
	local centre, width = self:riverCourse(along)
	return math.abs(across - centre) - width * 0.5
end

-- Signed distance outside the lagoon mouth channel: <= 0 means inside the mouth water.
function IslandShape:lagoonMouthEdge(dx: number, dz: number): number
	local lagoon = self.lagoon
	if not lagoon then
		return math.huge
	end
	local ldx, ldz = dx - lagoon.x, dz - lagoon.z
	local c, s = math.cos(lagoon.mouthAngle), math.sin(lagoon.mouthAngle)
	local along = ldx * c + ldz * s
	if along <= 0 then
		return math.huge
	end
	local across = -ldx * s + ldz * c
	local centre = lagoon.mouthMeanderAmp
		* math.sin(along / lagoon.mouthMeanderLen + lagoon.mouthMeanderPhase)
	-- Flare the mouth gently toward open water so it reads as a tidal pass through the sand
	-- arm. The flare has to stay modest and capped: an aggressive one turns the pass into a
	-- broad straight-edged wedge, which renders as a rectangle laid over the lagoon.
	local widen = math.min(1 + (along / math.max(self.half * 0.90, 1)) * 0.45, 1.55)
	return math.abs(across - centre) - lagoon.mouthHalfWidth * widen
end

-- ==========================================================================================
-- The height field
-- ==========================================================================================

--[[
	Returns:
		kind    "ocean" | "shelf" | "water" | "land"
		height  land surface (studs above topY) for "land";
		        submerged bed top for "shelf" / "water";
		        unused for "ocean"
		beach   true when the land surface is bare sand at a waterline
]]
function IslandShape:sample(dx: number, dz: number): (string, number, boolean)
	local r = math.sqrt(dx * dx + dz * dz)
	local angle = math.atan2(dz, dx)
	local coast = self:coastRadius(angle)

	if r > coast + self.shelfWidth then
		return "ocean", 0, false
	end
	if r > coast then
		return "shelf", self.shelfTop, false
	end

	-- Distance to the nearest waterline. Starts at the open sea and shrinks as the
	-- lagoon, its mouth, the river and the lake are taken into account. It drives the
	-- sand band, so every waterline gets a beach.
	local dw = coast - r

	-- Is this point on the inner island? Several features below must not cut into it.
	local onCore = r <= self:coreRadius(angle)

	-- Is this bearing a LAND BRIDGE — one of the solid causeways between two lagoon windows
	-- that join the sandy arms to the inner island? Nothing is allowed to carve a bridge.
	-- The bay lobe and the channel pass were previously free to cut whichever bearings they
	-- liked, and they cut the bridges: 6 of 13 islands ended up as 2-3 disconnected
	-- landmasses, and on one the village and volcano were unreachable on foot from any
	-- beach. Protecting the bridges is what keeps an island a single walkable place.
	local onLandBridge = self:lagoonWindowWeight(angle) <= 0.02

	-- --- navigable channel ---
	-- On an atoll the channel is a tidal PASS: it cuts the sand arms so the lagoon connects
	-- to the open sea, and stops at the inner island. Letting it run the full sea-to-sea
	-- length instead drew a blue ribbon straight across the atoll and sliced the jungle
	-- core in half, which is both unlike the reference and a worse place to live.
	-- The channel is NOT carved as a separate trench any more. On an atoll the lagoon plus
	-- its tidal pass (a notch in the sand arm, see ringWidth) already provide navigable
	-- water from the sea to the island's interior. A second carved channel had to cross
	-- either the inner island or a land bridge, and cutting either one is what left islands
	-- in disconnected pieces with unreachable villages. `self.river` is retained, aimed at
	-- the pass, for callers that ask where the navigable water is.

	-- --- highland lake ---
	local lake = self.lake
	if lake then
		local ldx, ldz = dx - lake.x, dz - lake.z
		local ld = math.sqrt(ldx * ldx + ldz * ldz)
		local lr = self:lakeRadius(math.atan2(ldz, ldx))
		if ld <= lr then
			return "water", lake.bed, false
		end
		dw = math.min(dw, ld - lr)
	end

	-- --- the atoll lagoon, between the sandy arms and the inner island ---
	local lagoonInner, lagoonOuter = self:lagoonBand(angle)
	local onArm = false
	if lagoonInner and lagoonOuter then
		if r >= lagoonInner and r <= lagoonOuter then
			return "water", self.lagoonBed, false
		end
		dw = math.min(dw, math.abs(r - lagoonInner), math.abs(r - lagoonOuter))
		onArm = r > lagoonOuter
	else
		-- A land bridge: this bearing is continuous land from the coast to the inner
		-- island, so the arm and the core are the same surface here.
		onArm = r > self:coastRadius(angle) - self:ringWidth(angle)
	end

	-- --- the bay and its mouth ---
	-- Never allowed to cut the inner island. The bay is an anchorage carved out of the
	-- lagoon and the sand arms; if it may also eat the core, the jungle mass degenerates
	-- into a crescent and the volcano ends up on a spit.
	local lagoon = if onCore or onLandBridge then nil else self.lagoon
	if lagoon then
		local ldx, ldz = dx - lagoon.x, dz - lagoon.z
		local ld = math.sqrt(ldx * ldx + ldz * ldz)
		local lr = self:lagoonRadius(math.atan2(ldz, ldx))
		if ld <= lr then
			return "water", self.lagoonBed, false
		end
		dw = math.min(dw, ld - lr)
		-- No separate mouth channel: the bay is an anchorage lobe of the lagoon, and the
		-- lagoon reaches the sea through the ring's tidal pass. A mouth carved straight out
		-- through the arms was free to land on a causeway and cut the island in two.
	end

	-- --- land surface ---
	local beachWidth = self.beachWidth
	-- Many separate knolls and saddles: reliefScale is a small fraction of the island so
	-- the interior is genuinely bumpy instead of one broad swell.
	local n = fbm(self.noiseSeed, (dx + 4096) / self.reliefScale, (dz + 4096) / self.reliefScale)
	local height: number
	local beach = false
	if dw <= beachWidth then
		beach = true
		height = 0.25 + 2.0 * (dw / beachWidth)
	elseif onArm then
		-- The sandy outer arms stay low and dune-like, and read as SAND across most of
		-- their width with only scattered scrub on the higher humps — the broad pale
		-- beaches that dominate the reference island.
		local rise = smoothstep((dw - beachWidth) / (self.riseWidth * 1.5))
		height = 1.4 + rise * self.armCrest * (0.30 + 1.15 * n)
		beach = height < self.armSandLine
	else
		local rise = smoothstep((dw - beachWidth) / self.riseWidth)
		height = 2.25 + rise * self.hillCrest * (0.35 + 1.25 * n)
	end

	-- The settlement clearing: a small, off-centre flattening that the village is built
	-- on. It must be FULLY flat out to `radius` — the taper belongs outside that circle,
	-- not inside it, or houses on the outer streets end up pitched on a hillside.
	local shelf = self.shelf
	if shelf then
		local sdx, sdz = dx - shelf.x, dz - shelf.z
		local sd = math.sqrt(sdx * sdx + sdz * sdz)
		if sd < shelf.radius + shelf.feather then
			-- Fade in only at the very waterline, so a clearing on the shore keeps its beach.
			local w = (1 - smoothstep((sd - shelf.radius) / shelf.feather))
				* smoothstep(dw / (beachWidth * 0.8))
			if w > 0 then
				height = lerp(height, self.shelfHeight + n * 0.8, w)
			end
		end
	end

	-- --- the signature landmark ---
	local lm = self.landmark
	if lm then
		local ldx, ldz = dx - lm.x, dz - lm.z
		local ld = self:landmarkDistance(dx, dz)
		if ld < lm.baseR then
			local t = 1 - ld / lm.baseR
			-- Facet modulation keeps the flanks angular: ridges and gullies, not a dome.
			-- It has to fade out toward the summit, because an angular term in atan2 is
			-- singular at the centre and otherwise renders a pinwheel starburst on the peak.
			local facetFade = smoothstep(ld / (lm.baseR * 0.42))
			local facet = 1 + 0.055 * facetFade * math.sin(lm.facets * math.atan2(ldz, ldx) + lm.facetPhase)
			-- Broken, uneven flanks: spurs and gullies instead of a mathematically clean cone.
			-- Noise carries most of the irregularity, because it has no angular symmetry and
			-- therefore cannot reintroduce a spoked pattern around the summit.
			local rough = 1 + 0.20 * facetFade * fbm(self.noiseSeed + 61, ldx / (lm.baseR * 0.26), ldz / (lm.baseR * 0.26))
			local cone = lm.height * (t ^ lm.falloff) * facet * rough
			if lm.craterR and ld < lm.craterR then
				local ct = ld / lm.craterR
				cone -= lm.craterDepth * (1 - ct * ct)
			end
			if cone > height then
				height = cone
				beach = false
			end
		end
	end

	return "land", height, beach
end

function IslandShape:isLand(dx: number, dz: number): boolean
	local kind = self:sample(dx, dz)
	return kind == "land"
end

-- Land surface height above topY, or nil when (dx, dz) is water / open sea.
function IslandShape:landHeight(dx: number, dz: number): number?
	local kind, height = self:sample(dx, dz)
	if kind ~= "land" then
		return nil
	end
	return height
end

-- ==========================================================================================
-- Placement helpers shared by terrain, props and gameplay
-- ==========================================================================================

--[[
	Rejection-sample a point on this island.
	opts:
		zone      "shelf" (settlement clearing) | "interior" | "coast" | "any"
		maxHeight reject ground above this height
		minR/maxR fractions of `half` to search between (defaults per zone)
]]
function IslandShape:randomLandPoint(rand: () -> number, opts: { [string]: any }?): (number?, number?, number?)
	local o = opts or {}
	local zone = (o.zone :: string?) or "any"
	local attempts = (o.attempts :: number?) or 30
	local maxHeight = (o.maxHeight :: number?) or math.huge

	-- The settlement clearing is a disc around its own off-centre origin.
	if zone == "shelf" and self.shelf then
		for _ = 1, attempts do
			local a = rand() * TAU
			local r = math.sqrt(rand()) * self.shelf.radius
			local dx, dz = self.shelf.x + math.cos(a) * r, self.shelf.z + math.sin(a) * r
			local kind, height = self:sample(dx, dz)
			if kind == "land" and height <= maxHeight then
				return dx, dz, height
			end
		end
		return nil, nil, nil
	end

	local minR, maxR
	if zone == "interior" then
		minR, maxR = self.half * 0.05, self.half * 0.62
	elseif zone == "coast" then
		minR, maxR = self.half * 0.55, self.maxCoast
	else
		minR, maxR = 0, self.maxCoast
	end
	if o.minR then
		minR = self.half * (o.minR :: number)
	end
	if o.maxR then
		maxR = self.half * (o.maxR :: number)
	end

	for _ = 1, attempts do
		local a = rand() * TAU
		-- sqrt keeps the sampling area-uniform instead of clustering at the centre
		local r = minR + math.sqrt(rand()) * (maxR - minR)
		local dx, dz = math.cos(a) * r, math.sin(a) * r
		local kind, height, beach = self:sample(dx, dz)
		if kind == "land" and height <= maxHeight then
			if zone ~= "coast" or beach or height < 14 then
				return dx, dz, height
			end
		end
	end
	return nil, nil, nil
end

-- Where a pier should start (just inside the beach) and end (clear of the shore).
-- The start is pushed well into the beach so the deck visibly overlaps with the
-- sand/grass terrain and never looks disconnected from the island.
function IslandShape:dockSpan(angle: number, clearance: number): (number, number)
	local coast = self:coastRadius(angle)
	return coast - self.beachWidth * 1.8, coast + clearance
end

-- A land bearing near `angle` whose shore is real beach: piers, lighthouses and shore
-- props use this so they never sprout out of the lagoon mouth or off a submerged arm.
function IslandShape:shoreAngleNear(angle: number, avoidLagoon: boolean?): number
	local best, bestScore = angle, -math.huge
	for i = 0, 47 do
		local candidate = angle + (if i % 2 == 0 then 1 else -1) * (i * 0.033)
		local coast = self:coastRadius(candidate)
		local probe = coast - self.beachWidth * 0.8
		local kind = self:sample(math.cos(candidate) * probe, math.sin(candidate) * probe)
		if kind == "land" then
			local score = -math.abs(angleDelta(candidate, angle))
			if avoidLagoon and self.lagoon then
				-- Penalise bearings that cross the bay mouth.
				local mouth = self:lagoonMouthEdge(math.cos(candidate) * probe, math.sin(candidate) * probe)
				if mouth < self.beachWidth * 2 then
					score -= 3
				end
			end
			if score > bestScore then
				best, bestScore = candidate, score
			end
		end
	end
	return best
end

-- Reads an (X, Z) offset out of a catalog field. Accepts anything with numeric X and Z, so
-- it works for a real Vector3 on the server and for a plain table in the headless specs.
local function readOffset(value: any): (number?, number?)
	if value == nil or type(value) == "string" or type(value) == "number" then
		return nil, nil
	end
	local ok, x, z = pcall(function()
		return value.X, value.Z
	end)
	if ok and type(x) == "number" and type(z) == "number" then
		return x, z
	end
	return nil, nil
end

--[[
	Water a boarding island must keep clear, derived from the raft geometry.

	Crew rafts are placed on a fixed line of slots running through the boarding island's own
	centre (StarterBaseService.getBaseCenter: origin + (slot - 1) * spacing along +X), and a
	raft is not a swimmer: it needs open water under its whole footprint plus its collision
	pad. Kept here as a pure function of the raft numbers so the server and the specs derive
	the same basin, and so changing the raft size or slot spacing cannot silently strand a
	crew inside terrain.
]]
function IslandShape.berthGrid(
	slots: number,
	spacing: number,
	perRow: number
): ({ { x: number, z: number } }, number)
	local columns = math.max(math.min(slots, perRow), 1)
	local rows = math.ceil(slots / columns)
	local spanX = (columns - 1) * spacing
	local spanZ = (rows - 1) * spacing
	local offsets = {}
	for index = 0, slots - 1 do
		table.insert(offsets, {
			x = (index % columns) * spacing - spanX * 0.5,
			z = math.floor(index / columns) * spacing - spanZ * 0.5,
		})
	end
	-- Radius of the circle that contains every berth, measured from the grid's centre.
	return offsets, math.sqrt(spanX * spanX + spanZ * spanZ) * 0.5
end

-- Smallest bay rim that keeps a whole berth grid, plus each raft's footprint and collision
-- pad, over open water.
function IslandShape.spawnBasinRadius(
	slots: number,
	spacing: number,
	perRow: number,
	raftSize: number,
	pad: number
): number
	local _, reach = IslandShape.berthGrid(slots, spacing, perRow)
	return reach + raftSize * 0.5 + pad + 40
end

--[[
	Apply hand-authored catalog overrides to a generated shape.

	This lives here, next to the generator, so the server and the headless specs apply the
	same overrides. Each one is re-validated: an override that would put the settlement in
	the water, or the volcano on top of it, is rejected and the generated layout is kept, so
	a typo in the catalog degrades instead of shipping a broken island.

	Supported fields:
		LagoonWidth, LagoonOffset
		VolcanoOffset, VolcanoBaseRadius, VolcanoHeight, Volcano
		SettlementOffset, VillageRadiusFactor
]]
function IslandShape.applyOverrides(shape, entry: { [string]: any }): { string }
	local half = shape.half
	local applied: { string } = {}

	local lagoon = shape.lagoon
	if lagoon then
		local x, z = readOffset(entry.LagoonOffset)
		if x and (x ~= 0 or z ~= 0) then
			lagoon.x, lagoon.z = x, z
			lagoon.distance = math.sqrt(x * x + z * z)
			lagoon.angle = math.atan2(z, x)
			table.insert(applied, "LagoonOffset")
		end
		local width = tonumber(entry.LagoonWidth)
		if width then
			lagoon.baseR = math.clamp(width * 0.5, half * 0.12, half * 0.62)
			table.insert(applied, "LagoonWidth")
		end
	end

	local lm = shape.landmark
	if lm then
		local x, z = readOffset(entry.VolcanoOffset)
		if x and (x ~= 0 or z ~= 0) then
			lm.x, lm.z = x, z
			lm.distance = math.sqrt(x * x + z * z)
			lm.angle = math.atan2(z, x)
			table.insert(applied, "VolcanoOffset")
		end
		local baseR = tonumber(entry.VolcanoBaseRadius)
		if baseR then
			lm.baseR = math.clamp(baseR, half * 0.10, half * 0.55)
			table.insert(applied, "VolcanoBaseRadius")
		end
		local height = tonumber(entry.VolcanoHeight)
		if height then
			lm.height = math.clamp(height, 20, shape.size * 0.30)
			table.insert(applied, "VolcanoHeight")
		end
		if entry.Volcano == true and lm.kind ~= "volcano" then
			lm.kind = "volcano"
			lm.craterR = lm.baseR * 0.17
			lm.craterDepth = lm.height * 0.13
			-- A cone is a cone: drop the ridge elongation so it does not read as a spine.
			lm.elongation = 0
			table.insert(applied, "Volcano")
		end
	end

	-- The clearing has to be re-fitted whenever a landform moves, or the village keeps a
	-- clearing that was measured before the volcano was relocated on top of it.
	local sx, sz = readOffset(entry.SettlementOffset)
	local factor = tonumber(entry.VillageRadiusFactor)
	if sx and (sx ~= 0 or sz ~= 0) then
		local fitted = shape:clearingRadiusAt(sx, sz)
		if fitted > half * 0.06 then
			local radius = math.min(fitted, half * 0.30)
			if factor then
				radius = math.min(radius, half * factor)
			end
			shape.villageX, shape.villageZ = sx, sz
			shape.buildableRadius = radius
			shape.shelf = {
				x = sx,
				z = sz,
				radius = radius,
				feather = math.max(radius * 0.55, 20),
			}
			table.insert(applied, "SettlementOffset")
		else
			table.insert(applied, "SettlementOffset(rejected)")
		end
	elseif factor and shape.shelf then
		local radius = math.min(shape.buildableRadius, half * factor)
		shape.buildableRadius = radius
		shape.shelf.radius = radius
		shape.shelf.feather = math.max(radius * 0.55, 20)
		table.insert(applied, "VillageRadiusFactor")
	end

	return applied
end

--[[
	Build the shape for a catalog entry, overrides included. Single entry point shared by
	the server (IslandTerrain) and the headless specs, so what CI measures is what ships.
]]
function IslandShape.forEntry(entry: { [string]: any }, seaOffset: number?, extra: { [string]: any }?)
	local size = entry.SizeStuds
	local shape = IslandShape.new(entry.Id, size, {
		biome = entry.Biome or "beach",
		theme = entry.Theme or "wild",
		seaOffset = seaOffset,
		volcano = entry.Volcano,
		lake = entry.Lake,
		lagoon = entry.Lagoon,
		spawnBasinRadius = extra and extra.spawnBasinRadius,
		river = if entry.River == true
			then {
				angle = tonumber(entry.RiverAngle) or 0,
				width = tonumber(entry.RiverWidth) or math.max(110, size * 0.07),
			}
			else nil,
	})
	IslandShape.applyOverrides(shape, entry)
	return shape
end

-- Offsets of the settlement clearing's centre from the island centre.
function IslandShape:villageCenter(): (number, number)
	return self.villageX, self.villageZ
end

-- Radius of usable ground around a point: dry land, clear of the landmark's slopes and the
-- lake. Catalog overrides use this to validate a hand-picked settlement position before it
-- is accepted, so a bad override degrades to the generated site instead of a broken island.
function IslandShape:clearingRadiusAt(dx: number, dz: number): number
	return self:_shelfFit(dx, dz)
end

-- ==========================================================================================
-- Rasterisation
-- ==========================================================================================

--[[
	Walk a square grid of `step`-stud cells covering the island and hand each cell to
	`visit(dx, dz, kind, height, beach)`. Shared by the Terrain sculptor, the submerged
	shelf pass and the headless preview renderer so all three agree exactly.
]]
function IslandShape:forEachCell(step: number, visit: (number, number, string, number, boolean) -> ())
	local reach = self.maxCoast + self.shelfWidth + step
	local cells = math.ceil((reach * 2) / step)
	local origin = -reach + step * 0.5
	for ix = 0, cells - 1 do
		local dx = origin + ix * step
		for iz = 0, cells - 1 do
			local dz = origin + iz * step
			local kind, height, beach = self:sample(dx, dz)
			if kind ~= "ocean" then
				visit(dx, dz, kind, height, beach)
			end
		end
	end
end

-- Cell count and origin offset for a given grid step, without sampling anything.
function IslandShape:gridInfo(step: number): (number, number)
	local reach = self.maxCoast + self.shelfWidth + step
	return math.ceil((reach * 2) / step), -reach + step * 0.5
end

return IslandShape
