--!nocheck
-- Low-poly dual rock stacks on sandy pads, linked by a sagging rope bridge.
-- Parts-only landform (no FillCylinder / FillBall) for the postcard twin-isle look.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))

local TwinPeaksBuilder = {}

export type PeakPlan = {
	pos: Vector3,
	padR: number,
	padW: number,
	padD: number,
	rockFoot: number,
	rockH: number,
	side: number,
}

local TWIN_SAND = Color3.fromRGB(234, 226, 207)
local TWIN_ROCK = Color3.fromRGB(85, 85, 85)
local TWIN_ROCK_LIT = Color3.fromRGB(98, 98, 102)
local TWIN_LEAF = Color3.fromRGB(46, 139, 87)
local TWIN_LEAF_DARK = Color3.fromRGB(36, 118, 72)
local TWIN_TRUNK = Color3.fromRGB(92, 64, 38)
local TWIN_ROPE = Color3.fromRGB(72, 52, 34)

local function seedFromId(id: string): number
	local h = 2166136261
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 2147483647
	end
	return h
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "TwinPeaksPart"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.Sand
	p.Color = props.Color or TWIN_SAND
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = props.CastShadow == true
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.Shape ~= nil then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function buildClumpTree(model: Model, baseY: number, x: number, z: number, scale: number?)
	local s = scale or (0.9 + math.random() * 0.55)
	local trunkH = (9 + math.random() * 5) * s
	local trunkR = 1.15 * s
	makePart({
		Name = "ClumpTrunk",
		Parent = model,
		Size = Vector3.new(trunkH, trunkR, trunkR),
		CFrame = CFrame.new(x, baseY + trunkH * 0.5, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = TWIN_TRUNK,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
	})
	local canopyY = baseY + trunkH
	local blobs = {
		{ 0, 0, 5.5 },
		{ 2.2, 1.0, 4.2 },
		{ -2.0, 0.6, 4.0 },
		{ 0.4, 2.4, 3.6 },
		{ -1.2, -1.6, 3.8 },
	}
	for i, b in blobs do
		local r = b[3] * s
		makePart({
			Name = `ClumpLeaf_{i}`,
			Parent = model,
			Size = Vector3.new(r, r, r),
			CFrame = CFrame.new(x + b[1] * s, canopyY + b[2] * s, z + (i % 2 == 0 and 0.6 or -0.4) * s),
			Color = if i % 2 == 0 then TWIN_LEAF else TWIN_LEAF_DARK,
			Material = Enum.Material.Grass,
			CanCollide = false,
			CastShadow = i == 1,
			Shape = Enum.PartType.Ball,
		})
	end
end

local function buildPalm(model: Model, topY: number, x: number, z: number, scale: number?)
	local s = scale or (0.85 + math.random() * 0.45)
	local trunkH = (10 + math.random() * 5) * s
	local lean = math.rad((math.random() - 0.5) * 16)
	local trunk = makePart({
		Name = "PalmTrunk",
		Parent = model,
		Size = Vector3.new(0.95 * s, trunkH, 0.95 * s),
		CFrame = CFrame.new(x, topY + trunkH * 0.5, z) * CFrame.Angles(0, math.rad(math.random(0, 360)), lean),
		Color = TWIN_TRUNK,
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	local frondColors = { TWIN_LEAF, TWIN_LEAF_DARK, Color3.fromRGB(56, 132, 70) }
	for i = 0, 4 do
		local yaw = math.rad(i * 72 + math.random(-12, 12))
		local pitch = math.rad(8 + math.random() * 18)
		makePart({
			Name = `PalmFrond_{i}`,
			Parent = model,
			Size = Vector3.new((6.5 + math.random() * 2.5) * s, 0.32 * s, (1.6 + math.random() * 0.6) * s),
			CFrame = trunk.CFrame
				* CFrame.new(0, trunkH * 0.46, 0)
				* CFrame.Angles(pitch, yaw, math.rad((math.random() - 0.5) * 12)),
			Color = frondColors[(i % #frondColors) + 1],
			Material = Enum.Material.Grass,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

-- Sagging rope bridge between two peak tops — walkable planks + twin side ropes.
function TwinPeaksBuilder.buildRopeBridge(model: Model, a: Vector3, b: Vector3)
	local segs = 18
	local sag = math.clamp((a - b).Magnitude * 0.08, 6, 18)
	local function pointAt(t: number): Vector3
		local p = a:Lerp(b, t)
		local dip = sag * 4 * t * (1 - t)
		return Vector3.new(p.X, p.Y - dip, p.Z)
	end
	local across = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local side = if across.Magnitude > 0.1 then across.Unit:Cross(Vector3.yAxis) else Vector3.new(1, 0, 0)
	local halfW = 2.4

	for i = 0, segs - 1 do
		local t0 = i / segs
		local t1 = (i + 1) / segs
		local p0 = pointAt(t0)
		local p1 = pointAt(t1)
		local mid = (p0 + p1) * 0.5
		local dir = p1 - p0
		local len = math.max(dir.Magnitude, 0.4)
		local look = CFrame.lookAt(mid, mid + dir)
		makePart({
			Name = `BridgePlank_{i}`,
			Parent = model,
			Size = Vector3.new(halfW * 2, 0.35, len + 0.08),
			CFrame = look,
			Color = Color3.fromRGB(118, 86, 54),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			CastShadow = false,
		})
		for _, sx in { -halfW, halfW } do
			local r0 = p0 + side * sx + Vector3.new(0, 2.2, 0)
			local r1 = p1 + side * sx + Vector3.new(0, 2.2, 0)
			local rmid = (r0 + r1) * 0.5
			local rdir = r1 - r0
			makePart({
				Name = `BridgeRope_{i}`,
				Parent = model,
				Size = Vector3.new(0.22, 0.22, math.max(rdir.Magnitude, 0.3)),
				CFrame = CFrame.lookAt(rmid, rmid + rdir),
				Color = TWIN_ROPE,
				Material = Enum.Material.Fabric,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end

	for _, endPos in { a, b } do
		for _, sx in { -halfW, halfW } do
			makePart({
				Name = "BridgePost",
				Parent = model,
				Size = Vector3.new(0.55, 5.2, 0.55),
				CFrame = CFrame.new(endPos + side * sx + Vector3.new(0, 1.4, 0)),
				Color = TWIN_TRUNK,
				Material = Enum.Material.Wood,
				CanCollide = false,
			})
		end
	end
end

local function buildBlockyRockStack(
	model: Model,
	rng: Random,
	baseCenter: Vector3,
	baseY: number,
	footprint: number,
	height: number,
	side: number
): Vector3
	local tiers = rng:NextInteger(6, 8)
	local topPos = baseCenter + Vector3.new(0, height, 0)
	for t = 0, tiers - 1 do
		local frac = t / (tiers - 1)
		local y0 = baseY + height * (t / tiers)
		local y1 = baseY + height * ((t + 1) / tiers)
		local midY = (y0 + y1) * 0.5
		local tierH = math.max(y1 - y0, 4)
		local w = footprint * (1 - frac * 0.62) * rng:NextNumber(0.88, 1.06)
		local d = footprint * (1 - frac * 0.58) * rng:NextNumber(0.82, 1.04)
		local ox = side * footprint * 0.04 * (1 - frac) + rng:NextNumber(-w * 0.06, w * 0.06)
		local oz = rng:NextNumber(-d * 0.08, d * 0.08)
		local col = if t % 2 == 0 then TWIN_ROCK else TWIN_ROCK_LIT
		makePart({
			Name = `RockTier_{t}`,
			Parent = model,
			Size = Vector3.new(w, tierH + 0.4, d),
			CFrame = CFrame.new(baseCenter.X + ox, midY, baseCenter.Z + oz)
				* CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0),
			Color = col,
			Material = Enum.Material.Slate,
			CanCollide = true,
			CastShadow = true,
		})
		for j = 1, rng:NextInteger(1, 3) do
			local jw = w * rng:NextNumber(0.28, 0.48)
			local jh = tierH * rng:NextNumber(0.55, 1.1)
			local jd = d * rng:NextNumber(0.28, 0.45)
			local ja = rng:NextNumber(0, math.pi * 2)
			local jr = (math.min(w, d) * 0.42) * rng:NextNumber(0.7, 1.05)
			makePart({
				Name = `RockJut_{t}_{j}`,
				Parent = model,
				Size = Vector3.new(jw, jh, jd),
				CFrame = CFrame.new(
					baseCenter.X + ox + math.cos(ja) * jr,
					midY + rng:NextNumber(-tierH * 0.15, tierH * 0.2),
					baseCenter.Z + oz + math.sin(ja) * jr
				) * CFrame.Angles(0, ja, 0),
				Color = col,
				Material = Enum.Material.Slate,
				CanCollide = true,
				CastShadow = false,
			})
		end
		if t == tiers - 1 then
			topPos = Vector3.new(baseCenter.X + ox, y1, baseCenter.Z + oz)
		end
	end

	local climbH = height * 0.92
	local truss = Instance.new("TrussPart")
	truss.Name = "PeakClimb"
	truss.Anchored = true
	truss.CanCollide = true
	truss.Color = Color3.fromRGB(64, 88, 42)
	truss.Material = Enum.Material.Grass
	truss.Size = Vector3.new(2, climbH, 2)
	truss.CFrame = CFrame.new(baseCenter.X + side * footprint * 0.42, baseY + climbH * 0.5, baseCenter.Z)
	truss.CastShadow = false
	truss.Parent = model

	return topPos
end

local function buildSandPad(model: Model, center: Vector3, topY: number, width: number, depth: number)
	makePart({
		Name = "SandPad",
		Parent = model,
		Size = Vector3.new(width, 3.2, depth),
		CFrame = CFrame.new(center.X, topY - 0.4, center.Z),
		Color = TWIN_SAND,
		Material = Enum.Material.Sand,
		CanCollide = true,
		CastShadow = true,
	})
	makePart({
		Name = "SandShelf",
		Parent = model,
		Size = Vector3.new(width * 1.08, 2.4, depth * 1.08),
		CFrame = CFrame.new(center.X, topY - 2.6, center.Z),
		Color = Color3.fromRGB(214, 204, 178),
		Material = Enum.Material.Sand,
		CanCollide = true,
		CastShadow = false,
	})
end

function TwinPeaksBuilder.plan(id: string, center: Vector3, _topY: number, size: number): { PeakPlan }
	local rng = Random.new(seedFromId(id))
	local half = size * 0.5
	local sep = half * 0.30
	local padR = half * 0.22
	local rockFoot = padR * 0.78
	local rockH = math.clamp(size * 0.09, 88, 130)
	local axis = rng:NextNumber(-0.25, 0.25)
	return {
		{
			pos = Vector3.new(center.X - sep, center.Y, center.Z + sep * axis),
			padR = padR,
			padW = padR * 2.15,
			padD = padR * 1.85,
			rockFoot = rockFoot,
			rockH = rockH * rng:NextNumber(0.92, 1.05),
			side = -1,
		},
		{
			pos = Vector3.new(center.X + sep, center.Y, center.Z - sep * axis),
			padR = padR * rng:NextNumber(0.92, 1.05),
			padW = padR * 2.05,
			padD = padR * 1.75,
			rockFoot = rockFoot * 0.92,
			rockH = rockH * rng:NextNumber(0.85, 0.98),
			side = 1,
		},
	}
end

-- Submerged sand columns under each pad (FillBlock boxes, replayed by the ocean streamer).
function TwinPeaksBuilder.submergedBoxes(center: Vector3, topY: number, peaks: { PeakPlan }): { any }
	local surfaceY = OceanConfig.SurfaceY
	local bottom = surfaceY - 40
	local landTop = surfaceY - 1.5
	local boxes = {}
	for _, peak in peaks do
		table.insert(boxes, {
			x = peak.pos.X - center.X,
			z = peak.pos.Z - center.Z,
			sizeX = peak.padW * 1.12,
			sizeZ = peak.padD * 1.12,
			bottom = bottom,
			top = landTop,
			material = "Sand",
			water = false,
		})
	end
	return boxes
end

function TwinPeaksBuilder.writeSubmerged(center: Vector3, boxes: { any })
	local terrain = Workspace.Terrain
	for _, box in boxes do
		local height = box.top - box.bottom
		if height > 0 then
			terrain:FillBlock(
				CFrame.new(center.X + box.x, (box.top + box.bottom) * 0.5, center.Z + box.z),
				Vector3.new(box.sizeX, height, box.sizeZ),
				Enum.Material.Sand
			)
		end
	end
end

function TwinPeaksBuilder.build(model: Model, center: Vector3, topY: number, size: number, id: string): { tops: { Vector3 }, peaks: { PeakPlan } }
	local rng = Random.new(seedFromId(id) * 5 + 11)
	local peaks = TwinPeaksBuilder.plan(id, center, topY, size)
	local tops: { Vector3 } = {}

	for _, peak in peaks do
		buildSandPad(model, peak.pos, topY, peak.padW, peak.padD)
		local top = buildBlockyRockStack(model, rng, peak.pos, topY, peak.rockFoot, peak.rockH, peak.side)
		table.insert(tops, top)

		for _ = 1, rng:NextInteger(3, 5) do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = peak.rockFoot * rng:NextNumber(0.05, 0.22)
			buildClumpTree(model, top.Y, top.X + math.cos(a) * r, top.Z + math.sin(a) * r, rng:NextNumber(0.85, 1.25))
		end

		for _ = 1, rng:NextInteger(4, 7) do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = peak.padR * rng:NextNumber(0.55, 0.92)
			local px = peak.pos.X + math.cos(a) * r
			local pz = peak.pos.Z + math.sin(a) * r
			if (Vector3.new(px - peak.pos.X, 0, pz - peak.pos.Z)).Magnitude > peak.rockFoot * 0.48 then
				buildPalm(model, topY, px, pz, rng:NextNumber(0.8, 1.15))
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
		TwinPeaksBuilder.buildRopeBridge(model, a, b)
	end

	return { tops = tops, peaks = peaks }
end

return TwinPeaksBuilder
