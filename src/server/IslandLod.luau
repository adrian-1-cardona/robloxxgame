-- Distant island silhouettes that stay streamed in even when detail props stream out.
--
-- Roblox StreamingEnabled unloads island Models when the camera sails away. Without a
-- Persistent proxy, far isles collapse to blank water — the postcard rocky exterior and
-- the valley town in the middle both vanish. This module builds a cheap, non-colliding
-- stand-in that always remains on the client:
--
--   OUTSIDE  — blocky dark-grey rock stacks on pale sand pads, clump canopy trees, palms
--              (the twin-peaks / rocky-isle reference look)
--   MIDDLE   — a cluster of light-blue timber cottages with tan roofs in the settlement
--              clearing (the valley-town reference look)
--
-- Parts never collide and sit slightly above/alongside real terrain so close-up play is
-- unchanged once Streaming brings the high-detail Model back in.

local IslandLod = {}

local SAND = Color3.fromRGB(234, 226, 207)
local SAND_DEEP = Color3.fromRGB(214, 204, 178)
local ROCK = Color3.fromRGB(85, 85, 85)
local ROCK_LIT = Color3.fromRGB(98, 98, 102)
local LEAF = Color3.fromRGB(46, 139, 87)
local LEAF_DARK = Color3.fromRGB(36, 118, 72)
local TRUNK = Color3.fromRGB(92, 64, 38)
local ROPE = Color3.fromRGB(72, 52, 34)
local TOWN_WALL = Color3.fromRGB(148, 186, 210)
local TOWN_TIMBER = Color3.fromRGB(62, 39, 35)
local TOWN_ROOF = Color3.fromRGB(186, 154, 108)
local PATH = Color3.fromRGB(196, 168, 120)

local function seedFromId(id: string): number
	local h = 2166136261
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 2147483647
	end
	return h
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "LodPart"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = props.Material or Enum.Material.Slate
	p.Color = props.Color or ROCK
	p.Size = props.Size or Vector3.new(4, 4, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	p.Parent = props.Parent
	return p
end

local function buildClumpTree(parent: Instance, baseY: number, x: number, z: number, scale: number)
	local s = scale
	local trunkH = 10 * s
	makePart({
		Name = "LodTrunk",
		Parent = parent,
		Size = Vector3.new(trunkH, 1.2 * s, 1.2 * s),
		CFrame = CFrame.new(x, baseY + trunkH * 0.5, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = TRUNK,
		Material = Enum.Material.Wood,
		Shape = Enum.PartType.Cylinder,
	})
	local canopyY = baseY + trunkH
	local blobs = {
		{ 0, 0, 5.2 },
		{ 2.0, 1.0, 4.0 },
		{ -1.8, 0.6, 3.8 },
		{ 0.3, 2.2, 3.4 },
	}
	for i, b in blobs do
		local r = b[3] * s
		makePart({
			Name = `LodLeaf_{i}`,
			Parent = parent,
			Size = Vector3.new(r, r, r),
			CFrame = CFrame.new(x + b[1] * s, canopyY + b[2] * s, z),
			Color = if i % 2 == 0 then LEAF else LEAF_DARK,
			Material = Enum.Material.Grass,
			Shape = Enum.PartType.Ball,
		})
	end
end

local function buildPalm(parent: Instance, baseY: number, x: number, z: number, scale: number)
	local s = scale
	local trunkH = 11 * s
	makePart({
		Name = "LodPalmTrunk",
		Parent = parent,
		Size = Vector3.new(0.9 * s, trunkH, 0.9 * s),
		CFrame = CFrame.new(x, baseY + trunkH * 0.5, z),
		Color = TRUNK,
		Material = Enum.Material.Wood,
	})
	for i = 0, 4 do
		local yaw = math.rad(i * 72)
		makePart({
			Name = `LodPalmFrond_{i}`,
			Parent = parent,
			Size = Vector3.new(6.5 * s, 0.3 * s, 1.5 * s),
			CFrame = CFrame.new(x, baseY + trunkH, z) * CFrame.Angles(math.rad(14), yaw, 0),
			Color = LEAF,
			Material = Enum.Material.Grass,
		})
	end
end

-- Stair-step blocky rock mass — the exterior silhouette from the rocky-isle reference.
local function buildRockStack(
	parent: Instance,
	rng: Random,
	base: Vector3,
	baseY: number,
	footprint: number,
	height: number,
	side: number
): Vector3
	local tiers = 6
	local topPos = base + Vector3.new(0, height, 0)
	for t = 0, tiers - 1 do
		local frac = t / (tiers - 1)
		local y0 = baseY + height * (t / tiers)
		local y1 = baseY + height * ((t + 1) / tiers)
		local midY = (y0 + y1) * 0.5
		local tierH = math.max(y1 - y0, 4)
		local w = footprint * (1 - frac * 0.62) * rng:NextNumber(0.9, 1.05)
		local d = footprint * (1 - frac * 0.58) * rng:NextNumber(0.85, 1.05)
		local ox = side * footprint * 0.04 * (1 - frac)
		local oz = rng:NextNumber(-d * 0.06, d * 0.06)
		local col = if t % 2 == 0 then ROCK else ROCK_LIT
		makePart({
			Name = `LodRockTier_{t}`,
			Parent = parent,
			Size = Vector3.new(w, tierH + 0.4, d),
			CFrame = CFrame.new(base.X + ox, midY, base.Z + oz),
			Color = col,
			Material = Enum.Material.Slate,
		})
		if t == tiers - 1 then
			topPos = Vector3.new(base.X + ox, y1, base.Z + oz)
		end
	end
	return topPos
end

local function buildSandPad(parent: Instance, center: Vector3, topY: number, width: number, depth: number)
	makePart({
		Name = "LodSandPad",
		Parent = parent,
		Size = Vector3.new(width, 3.0, depth),
		CFrame = CFrame.new(center.X, topY - 0.4, center.Z),
		Color = SAND,
		Material = Enum.Material.Sand,
	})
	makePart({
		Name = "LodSandShelf",
		Parent = parent,
		Size = Vector3.new(width * 1.08, 2.2, depth * 1.08),
		CFrame = CFrame.new(center.X, topY - 2.4, center.Z),
		Color = SAND_DEEP,
		Material = Enum.Material.Sand,
	})
end

-- Simplified sagging span between two rock tops (distant silhouette only).
local function buildDistantSpan(parent: Instance, a: Vector3, b: Vector3)
	local segs = 10
	local sag = math.clamp((a - b).Magnitude * 0.08, 5, 16)
	local across = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local side = if across.Magnitude > 0.1 then across.Unit:Cross(Vector3.yAxis) else Vector3.new(1, 0, 0)
	for i = 0, segs - 1 do
		local t0 = i / segs
		local t1 = (i + 1) / segs
		local function pointAt(t: number): Vector3
			local p = a:Lerp(b, t)
			return Vector3.new(p.X, p.Y - sag * 4 * t * (1 - t), p.Z)
		end
		local p0, p1 = pointAt(t0), pointAt(t1)
		local mid = (p0 + p1) * 0.5
		local dir = p1 - p0
		makePart({
			Name = `LodSpan_{i}`,
			Parent = parent,
			Size = Vector3.new(4.2, 0.35, math.max(dir.Magnitude, 0.4)),
			CFrame = CFrame.lookAt(mid, mid + dir),
			Color = Color3.fromRGB(118, 86, 54),
			Material = Enum.Material.WoodPlanks,
		})
		for _, sx in { -2.2, 2.2 } do
			local r0 = p0 + side * sx + Vector3.new(0, 2.0, 0)
			local r1 = p1 + side * sx + Vector3.new(0, 2.0, 0)
			local rmid = (r0 + r1) * 0.5
			makePart({
				Name = `LodSpanRope_{i}`,
				Parent = parent,
				Size = Vector3.new(0.2, 0.2, math.max((r1 - r0).Magnitude, 0.3)),
				CFrame = CFrame.lookAt(rmid, rmid + (r1 - r0)),
				Color = ROPE,
				Material = Enum.Material.Fabric,
			})
		end
	end
end

-- Tiny light-blue Tudor cottage for the distant town cluster.
local function buildLodHouse(parent: Instance, cf: CFrame, scale: number, ruined: boolean)
	local w, d, h = 14 * scale, 12 * scale, 8 * scale
	makePart({
		Name = "LodHouseWall",
		Parent = parent,
		Size = Vector3.new(w, h, d),
		CFrame = cf * CFrame.new(0, h * 0.5, 0),
		Color = if ruined then Color3.fromRGB(120, 130, 140) else TOWN_WALL,
		Material = Enum.Material.SmoothPlastic,
	})
	-- Dark timber cross so it still reads as Tudor from a kilometre away.
	makePart({
		Name = "LodHouseTimber",
		Parent = parent,
		Size = Vector3.new(w * 0.08, h * 0.95, d * 1.02),
		CFrame = cf * CFrame.new(0, h * 0.5, 0),
		Color = TOWN_TIMBER,
		Material = Enum.Material.Wood,
	})
	makePart({
		Name = "LodHouseTimberH",
		Parent = parent,
		Size = Vector3.new(w * 1.02, h * 0.08, d * 1.02),
		CFrame = cf * CFrame.new(0, h * 0.55, 0),
		Color = TOWN_TIMBER,
		Material = Enum.Material.Wood,
	})
	if not ruined then
		for i = -1, 1, 2 do
			makePart({
				Name = "LodHouseRoof",
				Parent = parent,
				Size = Vector3.new(w * 0.7, 0.55 * scale, d + 2 * scale),
				CFrame = cf * CFrame.new(i * w * 0.28, h + 2.2 * scale, 0) * CFrame.Angles(0, 0, math.rad(i * -34)),
				Color = TOWN_ROOF,
				Material = Enum.Material.WoodPlanks,
			})
		end
	end
end

local function buildTownCluster(
	parent: Instance,
	rng: Random,
	townCenter: Vector3,
	topY: number,
	radius: number,
	abandoned: boolean
)
	-- Winding dirt path through the middle of the valley town.
	makePart({
		Name = "LodTownPath",
		Parent = parent,
		Size = Vector3.new(math.max(radius * 1.6, 40), 0.4, 8),
		CFrame = CFrame.new(townCenter.X, topY + 0.3, townCenter.Z)
			* CFrame.Angles(0, rng:NextNumber(-0.35, 0.35), 0),
		Color = PATH,
		Material = Enum.Material.Ground,
	})

	local houseCount = math.clamp(math.floor(radius / 18), 5, 14)
	for i = 1, houseCount do
		local a = (i / houseCount) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = radius * rng:NextNumber(0.15, 0.85)
		-- Keep a clear path corridor down the middle.
		local lateral = math.sin(a) * r
		if math.abs(lateral) < 6 then
			r = math.max(r, radius * 0.35)
		end
		local x = townCenter.X + math.cos(a) * r
		local z = townCenter.Z + math.sin(a) * r
		local yaw = a + math.pi
		local scale = rng:NextNumber(0.85, 1.25)
		buildLodHouse(
			parent,
			CFrame.new(x, topY, z) * CFrame.Angles(0, yaw, 0),
			scale,
			abandoned and rng:NextNumber() < 0.55
		)
	end

	-- One round tower / hall so the town has a skyline landmark from far away.
	if not abandoned then
		makePart({
			Name = "LodTownHall",
			Parent = parent,
			Size = Vector3.new(10, 18, 10),
			CFrame = CFrame.new(townCenter.X, topY + 9, townCenter.Z)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(130, 132, 138),
			Material = Enum.Material.Concrete,
			Shape = Enum.PartType.Cylinder,
		})
		makePart({
			Name = "LodTownHallRoof",
			Parent = parent,
			Size = Vector3.new(12, 6, 12),
			CFrame = CFrame.new(townCenter.X, topY + 20, townCenter.Z),
			Color = Color3.fromRGB(110, 112, 118),
			Material = Enum.Material.Slate,
			Shape = Enum.PartType.Ball,
		})
	end
end

export type LodArgs = {
	id: string,
	center: Vector3,
	topY: number,
	size: number,
	shape: any,
	theme: string,
	abandoned: boolean,
}

-- Build (or replace) the Persistent distant silhouette for one island.
function IslandLod.build(folder: Folder, args: LodArgs): Model
	local existing = folder:FindFirstChild(`IsleLod_{args.id}`)
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = `IsleLod_{args.id}`
	model:SetAttribute("IslandId", args.id)
	model:SetAttribute("IsIslandLod", true)
	-- Always stay on the client so sailing away never erases the rocky exterior + town.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = folder

	local rng = Random.new(seedFromId(args.id) * 7 + 41)
	local center = args.center
	local topY = args.topY
	local half = args.size * 0.5
	local shape = args.shape

	-- ---- OUTSIDE: two blocky rock stacks flanking the settlement valley -----------------
	local landmarkAngle = 0
	if shape.landmark and shape.landmark.angle then
		landmarkAngle = shape.landmark.angle
	else
		landmarkAngle = rng:NextNumber(0, math.pi * 2)
	end
	-- Place the stacks on opposite flanks so the town sits in a valley between them —
	-- matching the "rocky outside, town in the middle" postcard composition.
	local stackSpecs = {
		{ angle = landmarkAngle, side = -1 },
		{ angle = landmarkAngle + math.pi, side = 1 },
	}
	local tops: { Vector3 } = {}
	for _, spec in stackSpecs do
		local dist = half * rng:NextNumber(0.52, 0.68)
		local px = center.X + math.cos(spec.angle) * dist
		local pz = center.Z + math.sin(spec.angle) * dist
		local padW = half * rng:NextNumber(0.28, 0.38)
		local padD = half * rng:NextNumber(0.24, 0.34)
		local rockFoot = math.min(padW, padD) * 0.72
		local rockH = half * rng:NextNumber(0.22, 0.34)
		local base = Vector3.new(px, topY, pz)
		buildSandPad(model, base, topY, padW, padD)
		local top = buildRockStack(model, rng, base, topY, rockFoot, rockH, spec.side)
		table.insert(tops, top)

		for _ = 1, rng:NextInteger(2, 4) do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rockFoot * rng:NextNumber(0.05, 0.2)
			buildClumpTree(model, top.Y, top.X + math.cos(a) * r, top.Z + math.sin(a) * r, rng:NextNumber(0.9, 1.3))
		end
		for _ = 1, rng:NextInteger(3, 5) do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = math.min(padW, padD) * 0.5 * rng:NextNumber(0.55, 0.9)
			local qx = px + math.cos(a) * r
			local qz = pz + math.sin(a) * r
			if (Vector3.new(qx - px, 0, qz - pz)).Magnitude > rockFoot * 0.45 then
				buildPalm(model, topY, qx, qz, rng:NextNumber(0.85, 1.15))
			end
		end
	end

	if #tops >= 2 then
		local a, b = tops[1], tops[2]
		local toward = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if toward.Magnitude > 1 then
			toward = toward.Unit
			a = a + toward * 4 + Vector3.new(0, 1.2, 0)
			b = b - toward * 4 + Vector3.new(0, 1.2, 0)
		end
		buildDistantSpan(model, a, b)
	end

	-- ---- MIDDLE: valley town cluster (skip on pure wild isles) -------------------------
	if args.theme ~= "wild" then
		local vx, vz = 0, 0
		if shape.villageCenter then
			vx, vz = shape:villageCenter()
		elseif shape.villageX and shape.villageZ then
			vx, vz = shape.villageX, shape.villageZ
		end
		local townCenter = Vector3.new(center.X + vx, topY, center.Z + vz)
		local townRadius = if shape.buildableRadius
			then math.clamp(shape.buildableRadius * 0.85, 40, 160)
			else math.clamp(half * 0.18, 40, 140)
		local townY = topY + (shape.shelfHeight or 1.1)
		buildTownCluster(model, rng, townCenter, townY, townRadius, args.abandoned)
	end

	local anchor = makePart({
		Name = "LodAnchor",
		Parent = model,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(center.X, topY + 8, center.Z),
		Transparency = 1,
	})
	model.PrimaryPart = anchor

	return model
end

return IslandLod
