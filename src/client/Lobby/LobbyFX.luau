-- Client-only decorative motion for the boarding lobby.
-- The server used to run a task.spawn loop per boat / gate / flag, streaming
-- anchored-part CFrame updates to every client many times a second — the main
-- source of lobby lag. Instead the geometry is tagged (see LobbyWorld.Tags) and
-- animated here, purely locally, so nothing touches the network.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local LobbyFX = {}

local TAGS = LobbyWorld.Tags
local started = false

-- Per-instance animation state keyed by the tagged instance.
type BoatEntry = { model: Model, baseCf: CFrame, offsets: { { part: BasePart, offset: CFrame } }, phase: number }
type SwayEntry = { part: BasePart, base: CFrame, phase: number }

local boats: { [Model]: BoatEntry } = {}
local gates: { [BasePart]: SwayEntry } = {}
local flags: { [BasePart]: SwayEntry } = {}

local function trackBoat(model: Model)
	if boats[model] then
		return
	end
	local bx = model:GetAttribute("BaseX")
	local by = model:GetAttribute("BaseY")
	local bz = model:GetAttribute("BaseZ")
	local yawDeg = model:GetAttribute("YawDeg")
	if typeof(bx) ~= "number" or typeof(by) ~= "number" or typeof(bz) ~= "number" or typeof(yawDeg) ~= "number" then
		return
	end

	local baseCf = CFrame.new(bx, by, bz) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local inv = baseCf:Inverse()
	local offsets = {}
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			table.insert(offsets, { part = child, offset = inv * child.CFrame })
		end
	end

	boats[model] = {
		model = model,
		baseCf = baseCf,
		offsets = offsets,
		phase = yawDeg * 0.1,
	}
end

local function trackSway(store: { [BasePart]: SwayEntry }, inst: Instance)
	if not inst:IsA("BasePart") or store[inst] then
		return
	end
	local seed = inst:GetAttribute("PhaseSeed")
	store[inst] = {
		part = inst,
		base = inst.CFrame,
		phase = if typeof(seed) == "number" then seed else 0,
	}
end

local function bindTag(tag: string, onAdded: (Instance) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		onAdded(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded)
end

function LobbyFX.start()
	if started then
		return
	end
	started = true

	bindTag(TAGS.Boat, function(inst)
		if inst:IsA("Model") then
			trackBoat(inst)
		end
	end)
	bindTag(TAGS.Gate, function(inst)
		trackSway(gates, inst)
	end)
	bindTag(TAGS.Flag, function(inst)
		trackSway(flags, inst)
	end)

	local function drop(store, key)
		store[key] = nil
	end

	-- Re-CFraming every boat/gate/flag part touches a lot of instances. The motion is
	-- slow decorative bob/sway, so a ~30 Hz tick is visually indistinguishable from
	-- per-frame while halving the CFrame writes. Accumulated dt keeps phase timing exact.
	local fxAccum = 0
	local FX_INTERVAL = 1 / 30
	RunService.Heartbeat:Connect(function(frameDt)
		fxAccum += frameDt
		if fxAccum < FX_INTERVAL then
			return
		end
		local dt = fxAccum
		fxAccum = 0

		-- Boats: gentle bob + roll around their moored pose.
		for model, entry in boats do
			if not model.Parent then
				drop(boats, model)
				continue
			end
			entry.phase += dt
			local t = entry.phase
			local bob = math.sin(t) * 0.55
			local roll = math.rad(math.sin(t * 0.7) * 3)
			local animCf = entry.baseCf
				* CFrame.new(0, bob, 0)
				* CFrame.Angles(roll, 0, 0)
			for _, item in entry.offsets do
				if item.part.Parent then
					item.part.CFrame = animCf * item.offset
				end
			end
		end

		-- Portal gates: soft yaw sway.
		for gate, entry in gates do
			if not gate.Parent then
				drop(gates, gate)
				continue
			end
			entry.phase += dt
			gate.CFrame = entry.base * CFrame.Angles(0, math.rad(math.sin(entry.phase) * 1.8), 0)
		end

		-- Flags: two-axis flutter.
		for flag, entry in flags do
			if not flag.Parent then
				drop(flags, flag)
				continue
			end
			entry.phase += dt
			flag.CFrame = entry.base
				* CFrame.Angles(0, math.rad(math.sin(entry.phase) * 6), math.rad(math.sin(entry.phase * 1.6) * 3))
		end
	end)

	print("[SurviveAtSea] Lobby FX ready — boat/gate/flag motion runs local (no lag)")
end

return LobbyFX
