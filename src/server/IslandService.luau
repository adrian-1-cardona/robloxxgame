-- Stationary open-sea islands: spread flats with optional raid houses + chasing pirates.
-- Visit lockout: step on an isle, leave on the raft, sail LockoutStuds away → can't return.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OceanConfig = require(Shared:WaitForChild("OceanConfig"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local GunService = require(script.Parent:WaitForChild("GunService"))
local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))

export type IslandRecord = {
	id: string,
	name: string,
	center: Vector3,
	size: number,
	topY: number,
	thickness: number,
	hasHouse: boolean,
	pirateCount: number,
	model: Model,
	label: TextLabel?,
	pirates: { Model },
}

type CrewIslandState = {
	visited: boolean,
	locked: boolean,
	notifiedLock: boolean,
	notifiedVisit: boolean,
}

type PirateRuntime = {
	model: Model,
	islandId: string,
	attackAccum: number,
	alive: boolean,
}

local IslandService = {}

IslandService._islands = {} :: { IslandRecord }
IslandService._byId = {} :: { [string]: IslandRecord }
IslandService._crewState = {} :: { [string]: { [string]: CrewIslandState } }
IslandService._pirates = {} :: { PirateRuntime }
IslandService._Toast = nil :: RemoteEvent?
IslandService._getPartyCode = nil :: ((Player) -> string?)?
IslandService._getMemberUserIds = nil :: ((string) -> { number })?
IslandService._started = false

local function lobbyRoot(): Folder
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if root and root:IsA("Folder") then
		return root
	end
	return LobbyWorld.ensure()
end

local function makePart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = props.Name or "IslandPart"
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.Material = props.Material or Enum.Material.Sand
	p.Color = props.Color or Color3.fromRGB(220, 200, 158)
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.Shape ~= nil then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function worldCenterForOffset(offset: Vector3, topY: number, thickness: number): Vector3
	local origin = Config.StarterBase.Origin
	return Vector3.new(origin.X + offset.X, topY - thickness * 0.5, origin.Z + offset.Z)
end

local function ensureCrewState(code: string, islandId: string): CrewIslandState
	local byIsle = IslandService._crewState[code]
	if not byIsle then
		byIsle = {}
		IslandService._crewState[code] = byIsle
	end
	local state = byIsle[islandId]
	if not state then
		state = {
			visited = false,
			locked = false,
			notifiedLock = false,
			notifiedVisit = false,
		}
		byIsle[islandId] = state
	end
	return state
end

local function buildPalm(model: Model, topY: number, center: Vector3, ox: number, oz: number)
	local trunkH = 8 + math.random() * 2
	local trunk = makePart({
		Name = "PalmTrunk",
		Parent = model,
		Size = Vector3.new(0.85, trunkH, 0.85),
		CFrame = CFrame.new(center.X + ox, topY + trunkH * 0.5, center.Z + oz)
			* CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * 10)),
		Color = Color3.fromRGB(92, 64, 38),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	makePart({
		Name = "PalmFrond",
		Parent = model,
		Size = Vector3.new(7.2, 0.35, 2.1),
		CFrame = trunk.CFrame * CFrame.new(0, trunkH * 0.48, 0) * CFrame.Angles(0, math.rad(20), math.rad(10)),
		Color = Color3.fromRGB(48, 118, 62),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
	makePart({
		Name = "PalmFrond2",
		Parent = model,
		Size = Vector3.new(6.2, 0.35, 1.9),
		CFrame = trunk.CFrame * CFrame.new(0, trunkH * 0.45, 0) * CFrame.Angles(0, math.rad(-35), math.rad(-8)),
		Color = Color3.fromRGB(42, 108, 55),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
end

local function buildHouse(model: Model, center: Vector3, topY: number, islandId: string)
	local houseCf = CFrame.new(center.X + 4, topY, center.Z - 2)
	local floor = makePart({
		Name = "HouseFloor",
		Parent = model,
		Size = Vector3.new(14, 0.6, 12),
		CFrame = houseCf * CFrame.new(0, 0.3, 0),
		Color = Color3.fromRGB(110, 78, 48),
		Material = Enum.Material.WoodPlanks,
	})

	local wallH = 7
	local wallY = topY + wallH * 0.5
	for _, spec in {
		{ Name = "WallBack", Size = Vector3.new(14, wallH, 0.7), Offset = Vector3.new(0, 0, -5.65) },
		{ Name = "WallLeft", Size = Vector3.new(0.7, wallH, 11), Offset = Vector3.new(-6.65, 0, 0) },
		{ Name = "WallRight", Size = Vector3.new(0.7, wallH, 11), Offset = Vector3.new(6.65, 0, 0) },
		{ Name = "WallFrontL", Size = Vector3.new(4.5, wallH, 0.7), Offset = Vector3.new(-4.75, 0, 5.65) },
		{ Name = "WallFrontR", Size = Vector3.new(4.5, wallH, 0.7), Offset = Vector3.new(4.75, 0, 5.65) },
	} do
		makePart({
			Name = spec.Name,
			Parent = model,
			Size = spec.Size,
			CFrame = CFrame.new(floor.Position + Vector3.new(spec.Offset.X, wallY - topY - 0.3, spec.Offset.Z)),
			Color = Color3.fromRGB(128, 92, 58),
			Material = Enum.Material.Wood,
		})
	end

	makePart({
		Name = "Roof",
		Parent = model,
		Size = Vector3.new(15.5, 0.7, 13.5),
		CFrame = CFrame.new(floor.Position + Vector3.new(0, wallH + 0.2, 0)),
		Color = Color3.fromRGB(78, 52, 30),
		Material = Enum.Material.Wood,
	})

	-- Raid chest
	local chest = makePart({
		Name = "RaidChest",
		Parent = model,
		Size = Vector3.new(2.4, 1.6, 1.5),
		CFrame = CFrame.new(floor.Position + Vector3.new(-2, 1.1, -2)),
		Color = Color3.fromRGB(96, 68, 36),
		Material = Enum.Material.Wood,
	})
	chest:SetAttribute("IslandId", islandId)
	chest:SetAttribute("LootedBy", "")

	local anchor = makePart({
		Name = "ChestPromptAnchor",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = chest.CFrame * CFrame.new(0, 1.2, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RaidPrompt"
	prompt.ActionText = "Raid Chest"
	prompt.ObjectText = "Hidden Cache"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		local code = IslandService._getPartyCode and IslandService._getPartyCode(player)
		if not code then
			return
		end
		local state = ensureCrewState(code, islandId)
		if state.locked then
			if IslandService._Toast then
				IslandService._Toast:FireClient(player, "This isle is closed to your crew.", "error")
			end
			return
		end
		local lootedAttr = chest:GetAttribute("Looted_" .. player.UserId)
		if lootedAttr == true then
			if IslandService._Toast then
				IslandService._Toast:FireClient(player, "You already raided this chest.", "info")
			end
			return
		end
		if GunService.giveFlintlock(player) then
			chest:SetAttribute("Looted_" .. player.UserId, true)
		end
	end)
end

local function spawnPirate(island: IslandRecord, index: number): Model
	local cfg = Config.Islands.Pirate
	local angle = (index / math.max(island.pirateCount, 1)) * math.pi * 2
	local radius = island.size * 0.22
	local spawnPos = Vector3.new(
		island.center.X + math.cos(angle) * radius,
		island.topY + 2.5,
		island.center.Z + math.sin(angle) * radius
	)

	local model = Instance.new("Model")
	model.Name = `Pirate_{island.id}_{index}`
	model:SetAttribute("IsPirate", true)
	model:SetAttribute("IslandId", island.id)
	model.Parent = island.model

	local root = makePart({
		Name = "HumanoidRootPart",
		Parent = model,
		Size = Vector3.new(2, 2, 1),
		CFrame = CFrame.new(spawnPos),
		Color = Color3.fromRGB(70, 52, 40),
		Material = Enum.Material.Fabric,
		CanCollide = true,
	})
	model.PrimaryPart = root

	makePart({
		Name = "Torso",
		Parent = model,
		Size = Vector3.new(2.1, 2.1, 1.1),
		CFrame = root.CFrame * CFrame.new(0, 0.1, 0),
		Color = Color3.fromRGB(48, 72, 88),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	makePart({
		Name = "Head",
		Parent = model,
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = root.CFrame * CFrame.new(0, 1.7, 0),
		Color = Color3.fromRGB(210, 180, 145),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Shape = Enum.PartType.Ball,
	})
	makePart({
		Name = "Bandana",
		Parent = model,
		Size = Vector3.new(1.35, 0.35, 1.35),
		CFrame = root.CFrame * CFrame.new(0, 2.15, 0),
		Color = Color3.fromRGB(160, 40, 40),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = cfg.Health
	humanoid.Health = cfg.Health
	humanoid.WalkSpeed = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PirateTag"
	billboard.Size = UDim2.fromOffset(80, 24)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.Adornee = root
	billboard.Parent = root

	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Size = UDim2.fromScale(1, 1)
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = Config.Theme.DangerRed
	tag.Text = "Pirate"
	tag.Parent = billboard

	humanoid.Died:Connect(function()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
		task.delay(2.5, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	return model
end

local function buildFlatIsland(entry: {
	Id: string,
	Name: string,
	Offset: Vector3,
	SizeStuds: number,
	HasHouse: boolean,
	Pirates: number,
}, folder: Folder): IslandRecord
	local thickness = Config.Islands.Thickness
	local topY = Config.Islands.TopY
	local size = entry.SizeStuds
	local center = worldCenterForOffset(entry.Offset, topY, thickness)

	local model = Instance.new("Model")
	model.Name = `Isle_{entry.Id}`
	model:SetAttribute("IslandId", entry.Id)
	model.Parent = folder

	local deck = makePart({
		Name = "FlatSand",
		Parent = model,
		Size = Vector3.new(size, thickness, size),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(222, 202, 160),
		Material = Enum.Material.Sand,
		CanCollide = true,
	})
	model.PrimaryPart = deck

	makePart({
		Name = "ReefShelf",
		Parent = model,
		Size = Vector3.new(size + 28, 2.2, size + 28),
		CFrame = CFrame.new(center.X, OceanConfig.SurfaceY - 1.2, center.Z),
		Color = Color3.fromRGB(72, 110, 98),
		Material = Enum.Material.Slate,
		CanCollide = false,
		CastShadow = false,
	})

	local lipY = topY + 0.15
	local lipT = 1.4
	local half = size * 0.5
	for _, spec in {
		{ Name = "LipNorth", CFrame = CFrame.new(center.X, lipY, center.Z - half + lipT * 0.5), Size = Vector3.new(size, 0.35, lipT) },
		{ Name = "LipSouth", CFrame = CFrame.new(center.X, lipY, center.Z + half - lipT * 0.5), Size = Vector3.new(size, 0.35, lipT) },
		{ Name = "LipWest", CFrame = CFrame.new(center.X - half + lipT * 0.5, lipY, center.Z), Size = Vector3.new(lipT, 0.35, size - lipT * 2) },
		{ Name = "LipEast", CFrame = CFrame.new(center.X + half - lipT * 0.5, lipY, center.Z), Size = Vector3.new(lipT, 0.35, size - lipT * 2) },
	} do
		makePart({
			Name = spec.Name,
			Parent = model,
			Size = spec.Size,
			CFrame = spec.CFrame,
			Color = Color3.fromRGB(236, 218, 178),
			Material = Enum.Material.Sand,
			CanCollide = false,
		})
	end

	-- Scatter palms across the big flats so the sand doesn't read empty
	buildPalm(model, topY, center, -size * 0.28, size * 0.18)
	buildPalm(model, topY, center, size * 0.22, -size * 0.2)
	buildPalm(model, topY, center, -size * 0.12, -size * 0.26)
	if size >= 170 then
		buildPalm(model, topY, center, size * 0.3, size * 0.12)
		buildPalm(model, topY, center, size * 0.08, size * 0.32)
	end
	if size >= 185 then
		buildPalm(model, topY, center, -size * 0.32, -size * 0.08)
	end

	if entry.HasHouse then
		buildHouse(model, center, topY, entry.Id)
	end

	local marker = makePart({
		Name = "IsleMarker",
		Parent = model,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center.X, topY + 11, center.Z),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "IsleBillboard"
	gui.Adornee = marker
	gui.Size = UDim2.fromOffset(180, 42)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 900
	gui.Parent = marker

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 0.28
	label.BackgroundColor3 = Color3.fromRGB(18, 36, 48)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Config.Theme.Foam
	label.Text = string.upper(entry.Name)
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local record: IslandRecord = {
		id = entry.Id,
		name = entry.Name,
		center = center,
		size = size,
		topY = topY,
		thickness = thickness,
		hasHouse = entry.HasHouse == true,
		pirateCount = entry.Pirates or 0,
		model = model,
		label = label,
		pirates = {},
	}

	for i = 1, record.pirateCount do
		local pirate = spawnPirate(record, i)
		table.insert(record.pirates, pirate)
		table.insert(IslandService._pirates, {
			model = pirate,
			islandId = record.id,
			attackAccum = 0,
			alive = true,
		})
	end

	return record
end

function IslandService.getWorldCenters(): { Vector3 }
	local centers = {}
	for _, isle in IslandService._islands do
		table.insert(centers, isle.center)
	end
	if #centers == 0 then
		-- Before ensure(): still give ocean streamer a hint from catalog
		for _, entry in Config.Islands.Catalog do
			table.insert(
				centers,
				worldCenterForOffset(entry.Offset, Config.Islands.TopY, Config.Islands.Thickness)
			)
		end
	end
	return centers
end

-- Back-compat for older callers
function IslandService.getWorldCenter(): Vector3
	local centers = IslandService.getWorldCenters()
	return centers[1] or Config.StarterBase.Origin
end

function IslandService.paintTerrain()
	for _, isle in IslandService._islands do
		local pad = 4
		local size = Vector3.new(isle.size + pad * 2, isle.thickness + 4, isle.size + pad * 2)
		Workspace.Terrain:FillBlock(CFrame.new(isle.center), size, Enum.Material.Sand)
	end
end

function IslandService.isLockedForCrew(code: string, islandId: string): boolean
	local byIsle = IslandService._crewState[code]
	local state = byIsle and byIsle[islandId]
	return state ~= nil and state.locked == true
end

-- Keep rafts outside locked isles (can't sail back after leaving far enough away).
function IslandService.clampRaftPosition(code: string, fromPos: Vector3, toPos: Vector3): (Vector3, string?)
	local result = toPos
	local blockedName: string? = nil

	for _, isle in IslandService._islands do
		if not IslandService.isLockedForCrew(code, isle.id) then
			continue
		end
		local minDist = isle.size * 0.5 + Config.Islands.ApproachPadStuds
		local dist = flatDistance(result, isle.center)
		if dist >= minDist then
			continue
		end

		-- Push out along the approach vector; if coming from outside, stop at the ring
		local fromDist = flatDistance(fromPos, isle.center)
		local outward = Vector3.new(result.X - isle.center.X, 0, result.Z - isle.center.Z)
		if outward.Magnitude < 0.05 then
			outward = Vector3.new(fromPos.X - isle.center.X, 0, fromPos.Z - isle.center.Z)
		end
		if outward.Magnitude < 0.05 then
			outward = Vector3.new(1, 0, 0)
		end
		outward = outward.Unit
		local ringPos = Vector3.new(
			isle.center.X + outward.X * minDist,
			result.Y,
			isle.center.Z + outward.Z * minDist
		)
		-- Prefer staying outside if we started outside
		if fromDist >= minDist then
			result = Vector3.new(fromPos.X, result.Y, fromPos.Z)
		else
			result = ringPos
		end
		blockedName = isle.name
	end

	return result, blockedName
end

local function pointOnIsland(pos: Vector3, isle: IslandRecord): boolean
	if math.abs(pos.Y - isle.topY) > 18 then
		-- Allow standing / jumping on the flat
		if pos.Y < isle.topY - 2 or pos.Y > isle.topY + 20 then
			return false
		end
	end
	return flatDistance(pos, isle.center) <= isle.size * 0.5 + 3
end

local function toastCrew(code: string, message: string, kind: string)
	if not (IslandService._Toast and IslandService._getMemberUserIds) then
		return
	end
	for _, userId in IslandService._getMemberUserIds(code) do
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			IslandService._Toast:FireClient(plr, message, kind)
		end
	end
end

local function updateVisitLockouts()
	if not IslandService._getMemberUserIds then
		return
	end

	-- Gather active crew codes from live rafts
	local codes: { string } = {}
	local seen: { [string]: boolean } = {}
	for code, _ in StarterBaseService._basesByCode do
		if not seen[code] then
			seen[code] = true
			table.insert(codes, code)
		end
	end

	for _, code in codes do
		local members = IslandService._getMemberUserIds(code)
		local raft = StarterBaseService.getBaseModel(code)
		local deck = raft and (raft.PrimaryPart or raft:FindFirstChild("Deck"))
		local raftPos = if deck and deck:IsA("BasePart") then deck.Position else nil

		for _, isle in IslandService._islands do
			local state = ensureCrewState(code, isle.id)
			if state.locked then
				continue
			end

			local anyoneOn = false
			for _, userId in members do
				local plr = Players:GetPlayerByUserId(userId)
				local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and pointOnIsland(root.Position, isle) then
					anyoneOn = true
					break
				end
			end

			if anyoneOn then
				state.visited = true
				if not state.notifiedVisit then
					state.notifiedVisit = true
					toastCrew(code, `Visited {isle.name} — leave & sail far away and you can't return.`, "info")
				end
				continue
			end

			if not state.visited then
				continue
			end

			-- Visited and everyone off the sand — lock when raft (or crew) is far enough
			local farEnough = false
			if raftPos then
				farEnough = flatDistance(raftPos, isle.center) >= Config.Islands.LockoutStuds
			else
				-- Fallback: all members far
				farEnough = true
				for _, userId in members do
					local plr = Players:GetPlayerByUserId(userId)
					local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						if flatDistance(root.Position, isle.center) < Config.Islands.LockoutStuds then
							farEnough = false
							break
						end
					end
				end
			end

			if farEnough then
				state.locked = true
				if not state.notifiedLock then
					state.notifiedLock = true
					toastCrew(code, `{isle.name} is behind you — that isle won't take your crew back.`, "info")
				end
			end
		end
	end
end

local function updatePirates(dt: number)
	local cfg = Config.Islands.Pirate
	for _, runtime in IslandService._pirates do
		if not runtime.alive then
			continue
		end
		local model = runtime.model
		if not model.Parent then
			runtime.alive = false
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root and root:IsA("BasePart")) then
			runtime.alive = false
			continue
		end
		if humanoid.Health <= 0 then
			runtime.alive = false
			continue
		end

		local isle = IslandService._byId[runtime.islandId]
		if not isle then
			continue
		end

		-- Nearest living player on this island (or within aggro of the sand)
		local bestPlayer: Player? = nil
		local bestDist = cfg.AggroRange
		local bestPos: Vector3? = nil
		for _, plr in Players:GetPlayers() do
			local character = plr.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if not (hrp and hrp:IsA("BasePart") and hum and hum.Health > 0) then
				continue
			end
			-- Stay bound to island waters — only chase people near this isle
			if flatDistance(hrp.Position, isle.center) > isle.size * 0.5 + 18 then
				continue
			end
			local d = flatDistance(hrp.Position, root.Position)
			if d < bestDist then
				bestDist = d
				bestPlayer = plr
				bestPos = hrp.Position
			end
		end

		if not (bestPlayer and bestPos) then
			continue
		end

		local toTarget = Vector3.new(bestPos.X - root.Position.X, 0, bestPos.Z - root.Position.Z)
		if toTarget.Magnitude > 0.15 then
			local step = math.min(cfg.ChaseSpeed * dt, toTarget.Magnitude)
			local nextPos = root.Position + toTarget.Unit * step
			-- Keep pirates on the flat
			local fromCenter = Vector3.new(nextPos.X - isle.center.X, 0, nextPos.Z - isle.center.Z)
			local maxR = isle.size * 0.48
			if fromCenter.Magnitude > maxR then
				fromCenter = fromCenter.Unit * maxR
				nextPos = Vector3.new(isle.center.X + fromCenter.X, isle.topY + 2.5, isle.center.Z + fromCenter.Z)
			else
				nextPos = Vector3.new(nextPos.X, isle.topY + 2.5, nextPos.Z)
			end
			local lookAt = Vector3.new(bestPos.X, nextPos.Y, bestPos.Z)
			local newCf = CFrame.lookAt(nextPos, lookAt)
			local oldCf = root.CFrame
			local delta = newCf * oldCf:Inverse()
			for _, desc in model:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.CFrame = delta * desc.CFrame
				end
			end
		end

		runtime.attackAccum += dt
		if runtime.attackAccum >= cfg.AttackCooldown and bestDist <= 3.6 then
			runtime.attackAccum = 0
			local character = bestPlayer.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum:TakeDamage(cfg.Damage)
			end
		end
	end
end

function IslandService.clearCrew(code: string)
	IslandService._crewState[code] = nil
end

function IslandService.ensure(): Folder
	local folder = lobbyRoot():FindFirstChild("DriveIslands")
	if folder and folder:IsA("Folder") and #IslandService._islands > 0 then
		IslandService.paintTerrain()
		return folder
	end

	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DriveIslands"
	folder.Parent = lobbyRoot()

	table.clear(IslandService._islands)
	table.clear(IslandService._byId)
	table.clear(IslandService._pirates)

	for _, entry in Config.Islands.Catalog do
		local record = buildFlatIsland(entry, folder)
		table.insert(IslandService._islands, record)
		IslandService._byId[record.id] = record
	end

	IslandService.paintTerrain()
	print(`[SurviveAtSea] {#IslandService._islands} stationary isles ready (houses, pirates, visit lockout)`)
	return folder
end

function IslandService.start(
	toastRemote: RemoteEvent,
	getPartyCode: (Player) -> string?,
	getMemberUserIds: (string) -> { number }
)
	if IslandService._started then
		return
	end
	IslandService._started = true
	IslandService._Toast = toastRemote
	IslandService._getPartyCode = getPartyCode
	IslandService._getMemberUserIds = getMemberUserIds

	IslandService.ensure()

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		updatePirates(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		updateVisitLockouts()
	end)
end

return IslandService
