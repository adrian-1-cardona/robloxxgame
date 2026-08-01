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
	volcanic = { kind = "volcano", height = 0.150, baseR = 0.30, falloff = 1.30, facets = 7 },
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
local MAX_WATER_FRACTION = 0.30

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

	-- ---- The lagoon ------------------------------------------------------------------
	-- A single bay bitten out of ONE flank, with an organic rim and a mouth to the sea.
	-- Placed off centre on purpose: a lagoon centred on the island would read as a moat
	-- and the whole isle as a bullseye, which is the look we are avoiding.
	local lagoonAngle = rand() * TAU
	if o.lagoon ~= false then
		local lagoonDist = half * (0.26 + rand() * 0.10)
		self.lagoon = {
			angle = lagoonAngle,
			x = math.cos(lagoonAngle) * lagoonDist,
			z = math.sin(lagoonAngle) * lagoonDist,
			distance = lagoonDist,
			baseR = half * (0.26 + rand() * 0.07),
			profile = {
				{ k = 2, amp = 0.150, phase = rand() * TAU },
				{ k = 3, amp = 0.105, phase = rand() * TAU },
				{ k = 5, amp = 0.058, phase = rand() * TAU },
				{ k = 8, amp = 0.030, phase = rand() * TAU },
			},
			-- The mouth: a curved channel from the bay out through the coastal arm.
			mouthAngle = lagoonAngle + (rand() - 0.5) * 0.5,
			mouthHalfWidth = math.max(half * (0.075 + rand() * 0.035), 34),
			mouthMeanderAmp = half * (0.025 + rand() * 0.025),
			mouthMeanderLen = math.max(half * 0.30, 60),
			mouthMeanderPhase = rand() * TAU,
		}
		self:_fitLagoon()
	end

	-- ---- River (navigable sea-to-sea channel) ----------------------------------------
	local river = o.river
	if river then
		-- Rafts are stopped at the shoreline by IslandService.collideRaft, so a channel
		-- wide enough to steer a raft down is decoration only — and a 300-to-440 stud
		-- trench turns an island into two separate halves of blue. Cap it at a width a
		-- real river would have on a landmass this size.
		local requested = (river.width :: number?) or (size * 0.07)
		local width = math.clamp(requested, 70, size * 0.085)
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

	-- ---- Landmark (cone / peak / rocky ridge) ----------------------------------------
	-- Opposite the lagoon, on solid ground, clear of the channel.
	local spec = BIOME_LANDMARK[self.biome] or BIOME_LANDMARK.beach
	local wantsVolcano = self.biome == "volcanic" and o.volcano ~= false
	local landmarkAngle = self:_pickLandmarkAngle(rand, lagoonAngle)
	local baseR = half * spec.baseR
	local coastAtLandmark = self:coastRadius(landmarkAngle)
	local offset = math.clamp(coastAtLandmark * 0.46, baseR * 0.45, math.max(coastAtLandmark - baseR * 0.75, baseR * 0.45))
	local landmark = {
		kind = if wantsVolcano then "volcano" else spec.kind,
		angle = landmarkAngle,
		x = math.cos(landmarkAngle) * offset,
		z = math.sin(landmarkAngle) * offset,
		distance = offset,
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
	lagoon.baseR = math.clamp(math.min(lagoon.baseR, allowed), self.half * 0.10, self.half * 0.34)

	-- (2) Area cap. Measured on the real height field, so it accounts for the mouth, the
	-- river and the lake all contributing inland water on the same island.
	for _ = 1, 12 do
		if self:waterFraction() <= MAX_WATER_FRACTION then
			break
		end
		lagoon.baseR *= 0.92
		lagoon.mouthHalfWidth *= 0.96
		if lagoon.baseR < self.half * 0.10 then
			break
		end
	end
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
	self.buildableRadius = math.min(math.max(best.radius, self.half * 0.07), self.half * 0.30)
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
		for i = 0, 15 do
			local a = (i / 16) * TAU
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
function IslandShape:lagoonRadius(angle: number): number
	local lagoon = self.lagoon
	if not lagoon then
		return 0
	end
	return lagoon.baseR * math.clamp(1 + harmonics(lagoon.profile, angle), 0.50, 1.55)
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
	-- Flare the mouth toward open water. A constant-width channel reads as a drawn pipe
	-- joining a balloon to the sea; an estuary that widens as it leaves the bay reads as a
	-- real harbour entrance, and it gives rafts room to turn coming in.
	local widen = 1 + (along / math.max(self.half * 0.60, 1)) * 1.05
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

	-- --- navigable river ---
	if self.river then
		local edge = self:riverEdge(dx, dz)
		if edge <= 0 then
			return "water", self.channelBed, false
		end
		dw = math.min(dw, edge)
	end

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

	-- --- the lagoon and its mouth ---
	local lagoon = self.lagoon
	if lagoon then
		local ldx, ldz = dx - lagoon.x, dz - lagoon.z
		local ld = math.sqrt(ldx * ldx + ldz * ldz)
		local lr = self:lagoonRadius(math.atan2(ldz, ldx))
		if ld <= lr then
			return "water", self.lagoonBed, false
		end
		dw = math.min(dw, ld - lr)

		local mouth = self:lagoonMouthEdge(dx, dz)
		if mouth <= 0 then
			return "water", self.lagoonBed, false
		end
		dw = math.min(dw, mouth)
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
function IslandShape:dockSpan(angle: number, clearance: number): (number, number)
	local coast = self:coastRadius(angle)
	return coast - self.beachWidth * 1.1, coast + clearance
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
